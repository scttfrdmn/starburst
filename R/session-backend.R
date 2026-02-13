#' Session Backend Initialization
#'
#' Backend initialization for detached session mode
#'
#' @name session-backend
#' @keywords internal
NULL

#' Initialize backend for detached mode
#'
#' Creates a backend for detached sessions without modifying the future plan
#'
#' @param session_id Unique session identifier
#' @param workers Number of workers
#' @param cpu vCPUs per worker
#' @param memory Memory per worker (GB notation like "8GB")
#' @param region AWS region
#' @param timeout Task timeout in seconds
#' @param absolute_timeout Maximum session lifetime in seconds
#' @param launch_type "FARGATE" or "EC2"
#' @param instance_type EC2 instance type (for EC2 launch type)
#' @param use_spot Use spot instances
#' @param warm_pool_timeout Warm pool timeout for EC2
#' @return Backend environment
#' @keywords internal
initialize_detached_backend <- function(session_id,
                                       workers = 10,
                                       cpu = 4,
                                       memory = "8GB",
                                       region = NULL,
                                       timeout = 3600,
                                       absolute_timeout = 86400,
                                       launch_type = "FARGATE",
                                       instance_type = "c6a.large",
                                       use_spot = FALSE,
                                       warm_pool_timeout = 3600) {

  # Validate inputs
  validate_workers(workers)
  validate_launch_type(launch_type)

  # For EC2, auto-adjust cpu/memory based on instance type
  if (launch_type == "EC2") {
    validate_instance_type(instance_type)
    instance_specs <- get_instance_specs(instance_type)

    # Use max available resources on instance
    valid_cpus <- c(0.25, 0.5, 1, 2, 4, 8, 16)
    cpu <- max(valid_cpus[valid_cpus <= instance_specs$vcpus])

    # Memory: use instance capacity minus 512MB for ECS agent overhead
    memory_gb <- instance_specs$memory_gb - 0.5
    memory <- sprintf("%dGB", floor(memory_gb))

    cat_info(sprintf("   • Using instance resources: %g vCPUs, %s memory\n", cpu, memory))
  }

  validate_cpu(cpu)
  validate_memory(memory)

  # Get configuration
  config <- get_starburst_config()
  region <- region %||% config$region %||% "us-east-1"

  # Check AWS credentials
  check_aws_credentials()

  # Get architecture from instance type
  architecture <- if (launch_type == "EC2") {
    get_architecture_from_instance_type(instance_type)
  } else {
    "X86_64"  # Fargate default
  }

  # Ensure environment is ready
  env_info <- ensure_environment(region)

  # Create backend state
  backend <- list(
    session_id = session_id,
    mode = "detached",
    cluster = env_info$cluster,
    cluster_name = config$cluster_name,
    workers = workers,
    cpu = cpu,
    memory = memory,
    region = region,
    bucket = config$bucket,
    timeout = timeout,
    absolute_timeout = absolute_timeout,
    env_hash = env_info$hash,
    image_uri = env_info$image_uri,
    created_at = Sys.time(),
    total_tasks = 0,
    completed_tasks = 0,
    failed_tasks = 0,
    launch_type = launch_type,
    instance_type = instance_type,
    use_spot = use_spot,
    architecture = architecture,
    warm_pool_timeout = warm_pool_timeout,
    capacity_provider_name = sprintf("starburst-%s", gsub("\\.", "-", instance_type)),
    pool_started_at = NULL,
    asg_name = sprintf("starburst-asg-%s", gsub("\\.", "-", instance_type)),
    aws_account_id = config$aws_account_id,
    subnets = config$subnets,
    security_groups = config$security_groups,
    task_definition_arn = NULL  # Will be set during worker launch
  )

  # Convert to environment for mutability
  backend_env <- list2env(backend, parent = emptyenv())
  class(backend_env) <- c("StarburstBackend", "DetachedBackend", "environment")

  backend_env
}

#' Launch workers for detached session
#'
#' Launches workers with bootstrap tasks that tell them the session ID
#'
#' @param backend Backend environment
#' @return Invisibly returns NULL
#' @keywords internal
launch_detached_workers <- function(backend) {
  cat_info(sprintf("[Starting] Launching %d detached workers...\n", backend$workers))

  # Get or create task definition
  if (is.null(backend$task_definition_arn)) {
    backend$task_definition_arn <- get_or_create_task_definition(backend)
  }

  # Handle EC2 pool warmup if needed
  if (backend$launch_type == "EC2" && is.null(backend$pool_started_at)) {
    cat_info("🔧 Starting warm EC2 pool (~2 min first time)...\n")
    start_warm_pool(backend, backend$workers, timeout_seconds = 120)
    backend$pool_started_at <- Sys.time()
  }

  # Create session manifest in S3
  create_session_manifest(backend$session_id, backend)

  # Launch workers with bootstrap tasks
  for (i in seq_len(backend$workers)) {
    bootstrap_task_id <- sprintf("bootstrap-%s-%d", backend$session_id, i)

    # Create minimal bootstrap task (tells worker the session ID)
    bootstrap_task <- list(
      session_id = backend$session_id,
      task_id = bootstrap_task_id,
      expr = NULL,  # No execution needed
      globals = list(),
      packages = NULL
    )

    # Upload bootstrap task to S3
    upload_detached_task(bootstrap_task_id, bootstrap_task, backend)

    # Create task status (claimed by bootstrap)
    create_task_status(
      session_id = backend$session_id,
      task_id = bootstrap_task_id,
      state = "claimed",
      region = backend$region,
      bucket = backend$bucket
    )

    # Launch worker via ECS and track task ARN
    task_arn <- submit_detached_worker(backend, bootstrap_task_id)

    # Store task ARN in session manifest for cleanup tracking
    tryCatch({
      current_manifest <- get_session_manifest(
        backend$session_id,
        backend$region,
        backend$bucket
      )

      # Initialize ecs_task_arns if not present
      if (is.null(current_manifest$ecs_task_arns)) {
        current_manifest$ecs_task_arns <- character(0)
      }

      # Add new task ARN
      current_manifest$ecs_task_arns <- c(current_manifest$ecs_task_arns, task_arn)

      # Update manifest
      update_session_manifest(
        backend$session_id,
        list(ecs_task_arns = current_manifest$ecs_task_arns),
        backend$region,
        backend$bucket
      )
    }, error = function(e) {
      cat_warn(sprintf("  [WARNING] Failed to track task ARN: %s\n", e$message))
    })
  }

  cat_success(sprintf("[OK] Launched %d workers for session: %s\n",
                     backend$workers, backend$session_id))

  invisible(NULL)
}

#' Upload task for detached session
#'
#' @param task_id Task identifier
#' @param task_data Task data (expr, globals, packages, session_id)
#' @param backend Backend environment
#' @return Invisibly returns NULL
#' @keywords internal
upload_detached_task <- function(task_id, task_data, backend) {
  s3 <- get_s3_client(backend$region)
  task_key <- sprintf("tasks/%s.qs", task_id)

  temp_file <- tempfile(fileext = ".qs")
  on.exit(unlink(temp_file), add = TRUE)

  qs2::qs_save(task_data, temp_file)

  s3$put_object(
    Bucket = backend$bucket,
    Key = task_key,
    Body = temp_file
  )

  invisible(NULL)
}

#' Submit detached worker to ECS
#'
#' @param backend Backend environment
#' @param task_id Task ID for the worker to execute
#' @return Task ARN
#' @keywords internal
submit_detached_worker <- function(backend, task_id) {
  ecs <- get_ecs_client(backend$region)

  # Prepare network configuration
  awsvpc_config <- list(
    subnets = backend$subnets,
    securityGroups = backend$security_groups
  )

  # Add assignPublicIp only for Fargate (EC2 doesn't support it)
  if (backend$launch_type != "EC2") {
    awsvpc_config$assignPublicIp <- "ENABLED"
  }

  # Build run_task parameters
  run_task_params <- list(
    cluster = backend$cluster_name,
    taskDefinition = backend$task_definition_arn,
    count = 1L,
    networkConfiguration = list(
      awsvpcConfiguration = awsvpc_config
    ),
    overrides = list(
      containerOverrides = list(
        list(
          name = "starburst-worker",
          environment = list(
            list(name = "TASK_ID", value = task_id),
            list(name = "S3_BUCKET", value = backend$bucket),
            list(name = "AWS_DEFAULT_REGION", value = backend$region)
          )
        )
      )
    )
  )

  # Add launch-type specific parameters
  if (backend$launch_type == "EC2") {
    run_task_params$capacityProviderStrategy <- list(
      list(
        capacityProvider = backend$capacity_provider_name,
        weight = 1
      )
    )
  } else {
    run_task_params$launchType <- "FARGATE"
  }

  # Submit task with retry logic
  response <- with_ecs_retry(
    {
      do.call(ecs$run_task, run_task_params)
    },
    max_attempts = 3,
    operation_name = "ECS RunTask (detached worker)"
  )

  # Check for failures
  if (length(response$failures) > 0) {
    failure <- response$failures[[1]]
    stop(sprintf("Failed to submit worker: %s - %s",
                failure$reason, failure$detail))
  }

  # Return task ARN
  if (length(response$tasks) > 0) {
    return(response$tasks[[1]]$taskArn)
  } else {
    stop("No task ARN returned from ECS")
  }
}

#' Reconstruct backend from session manifest
#'
#' Used when reattaching to an existing session
#'
#' @param manifest Session manifest from S3
#' @return Backend environment
#' @keywords internal
reconstruct_backend_from_manifest <- function(manifest) {
  # Extract backend configuration
  backend_config <- manifest$backend
  backend_config$session_id <- manifest$session_id
  backend_config$mode <- "detached"
  backend_config$created_at <- manifest$created_at

  # Set task counts from stats
  backend_config$total_tasks <- manifest$stats$total_tasks
  backend_config$completed_tasks <- manifest$stats$completed
  backend_config$failed_tasks <- manifest$stats$failed

  # Convert to environment
  backend_env <- list2env(backend_config, parent = emptyenv())
  class(backend_env) <- c("StarburstBackend", "DetachedBackend", "environment")

  backend_env
}
