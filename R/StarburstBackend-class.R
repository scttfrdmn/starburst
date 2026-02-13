#' Starburst Future Backend
#'
#' A future backend for running parallel R workloads on AWS ECS
#'
#' @param workers Number of parallel workers
#' @param cpu vCPUs per worker (1, 2, 4, 8, or 16)
#' @param memory Memory per worker (supports GB notation, e.g., "8GB")
#' @param region AWS region (default: from config or "us-east-1")
#' @param timeout Maximum runtime in seconds (default: 3600)
#' @param launch_type "EC2" or "FARGATE" (default: "EC2")
#' @param instance_type EC2 instance type (e.g., "c6a.large")
#' @param use_spot Use spot instances (default: FALSE)
#' @param warm_pool_timeout Pool timeout in seconds (default: 3600)
#' @param ... Additional arguments
#'
#' @return A StarburstBackend object
#' @export
StarburstBackend <- function(workers = 10,
                             cpu = 4,
                             memory = "8GB",
                             region = NULL,
                             timeout = 3600,
                             launch_type = "EC2",
                             instance_type = "c6a.large",
                             use_spot = FALSE,
                             warm_pool_timeout = 3600,
                             ...) {

  # Validate inputs
  validate_workers(workers)
  validate_launch_type(launch_type)

  # For EC2, auto-adjust cpu/memory based on instance type
  if (launch_type == "EC2") {
    validate_instance_type(instance_type)
    instance_specs <- get_instance_specs(instance_type)

    # Use max available resources on instance
    # For ECS, valid CPU values are: 0.25, 0.5, 1, 2, 4, 8, 16
    # Use the largest valid value that fits on the instance
    valid_cpus <- c(0.25, 0.5, 1, 2, 4, 8, 16)
    cpu <- max(valid_cpus[valid_cpus <= instance_specs$vcpus])

    # Memory: use instance capacity minus 512MB for ECS agent overhead
    memory_gb <- instance_specs$memory_gb - 0.5
    memory <- sprintf("%dGB", floor(memory_gb))

    cat_info(sprintf("   * Using instance resources: %g vCPUs, %s memory\n", cpu, memory))
  }

  # Validate after potential adjustment
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

  # Create cluster identifier
  cluster_id <- sprintf("starburst-%s", uuid::UUIDgenerate())

  # Ensure environment is ready
  env_info <- ensure_environment(region)

  # Create backend state
  backend <- list(
    cluster_id = cluster_id,
    cluster = env_info$cluster,
    cluster_name = config$cluster_name,
    workers = workers,
    cpu = cpu,
    memory = memory,
    region = region,
    bucket = config$bucket,
    timeout = timeout,
    env_hash = env_info$hash,
    image_uri = env_info$image_uri,
    created_at = Sys.time(),
    total_tasks = 0,
    completed_tasks = 0,
    failed_tasks = 0,
    total_cost = 0,
    launch_type = launch_type,
    instance_type = instance_type,
    use_spot = use_spot,
    architecture = architecture,
    warm_pool_timeout = warm_pool_timeout,
    capacity_provider_name = sprintf("starburst-%s", gsub("\\.", "-", instance_type)),
    pool_started_at = NULL,
    asg_name = sprintf("starburst-asg-%s", gsub("\\.", "-", instance_type)),
    aws_account_id = config$aws_account_id,
    # VPC configuration
    subnets = config$subnets,
    security_groups = config$security_groups
  )

  # Convert to environment for mutability
  backend_env <- list2env(backend, parent = emptyenv())

  # Store in options
  options(starburst.current_backend = backend_env)
  options(starburst.current_cluster_id = cluster_id)

  cat_success(sprintf("[OK] Cluster ready: %s\n", cluster_id))

  # Create the backend object using future::FutureBackend
  core <- future::FutureBackend(
    workers = workers,
    reg = "workers-starburst"
  )

  # Store our backend state in the core object
  for (name in names(backend)) {
    core[[name]] <- backend[[name]]
  }

  # Set S3 class hierarchy
  class(core) <- c("StarburstBackend", "FutureBackend", class(core))

  # Store backend_env in options for StarburstFuture to access
  attr(core, "backend") <- backend_env

  core
}


#' Starburst strategy marker
#'
#' This function should never be called directly. Use plan(starburst, ...) instead.
#'
#' @param ... Arguments passed to StarburstBackend()
#' @export
starburst <- function(...) {
  stop("INTERNAL ERROR: The starburst() function must never be called directly. Use plan(starburst, ...) instead.")
}

# Set class and attributes
class(starburst) <- c("starburst", "future", "function")
attr(starburst, "init") <- TRUE
attr(starburst, "factory") <- StarburstBackend
attr(starburst, "tweakable") <- c("workers", "cpu", "memory", "region", "timeout",
                                  "launch_type", "instance_type", "use_spot",
                                  "warm_pool_timeout")


#' Number of workers for StarburstBackend
#'
#' @param evaluator A StarburstBackend object
#' @return Number of workers
#' @importFrom future nbrOfWorkers
#' @method nbrOfWorkers StarburstBackend
#' @export
nbrOfWorkers.StarburstBackend <- function(evaluator) {
  backend <- evaluator  # Match generic signature
  backend$workers
}


#' List futures for StarburstBackend
#'
#' @param backend A StarburstBackend object
#' @param ... Additional arguments
#' @return List of futures (empty for this backend)
#' @importFrom future listFutures
#' @method listFutures StarburstBackend
#' @export
listFutures.StarburstBackend <- function(backend, ...) {
  # We don't track futures in the backend, they're managed by the future package
  list()
}


#' Launch a future on the Starburst backend
#'
#' @param backend A StarburstBackend object
#' @param future The future object to launch
#' @param ... Additional arguments
#' @return The future object (invisibly)
#' @importFrom future launchFuture
#' @method launchFuture StarburstBackend
#' @export
launchFuture.StarburstBackend <- function(backend, future, ...) {

  # The future should already be created by the future package
  # We just need to submit it to ECS and update its state

  # Get backend environment from options or attribute
  backend_env <- getOption("starburst.current_backend")
  if (is.null(backend_env)) {
    backend_env <- attr(backend, "backend")
  }

  if (is.null(backend_env)) {
    stop("No backend environment found")
  }

  # Generate task ID if not present
  if (is.null(future$task_id)) {
    future$task_id <- sprintf("task-%s", gsub("-", "", uuid::UUIDgenerate()))
  }

  # Serialize task data
  task_data <- list(
    expr = future$expr,
    globals = future$globals,
    packages = future$packages,
    seed = future$seed
  )

  # Upload to S3
  s3 <- get_s3_client(backend_env$region)
  task_key <- sprintf("tasks/%s.qs", future$task_id)
  temp_task_file <- tempfile(fileext = ".qs")
  on.exit(unlink(temp_task_file), add = TRUE)

  qs2::qs_save(task_data, temp_task_file)

  s3$put_object(
    Bucket = backend_env$bucket,
    Key = task_key,
    Body = temp_task_file
  )

  # Submit task to ECS
  ecs <- get_ecs_client(backend_env$region)

  # Get or create task definition
  task_def_arn <- get_or_create_task_definition(backend_env)
  backend_env$task_definition_arn <- task_def_arn

  # Prepare network configuration
  # Note: For EC2, assignPublicIp is not supported and networking comes from instance
  # For FARGATE, assignPublicIp is required for internet access
  awsvpc_config <- list(
    subnets = backend_env$subnets,
    securityGroups = backend_env$security_groups
  )

  # Add assignPublicIp only for Fargate (EC2 doesn't support it)
  if (backend_env$launch_type != "EC2") {
    awsvpc_config$assignPublicIp <- "ENABLED"
  }

  # Prepare run_task parameters
  run_task_params <- list(
    cluster = backend_env$cluster_name,
    taskDefinition = task_def_arn,
    count = 1L,
    networkConfiguration = list(
      awsvpcConfiguration = awsvpc_config
    ),
    overrides = list(
      containerOverrides = list(
        list(
          name = "starburst-worker",
          environment = list(
            list(name = "TASK_ID", value = future$task_id),
            list(name = "S3_BUCKET", value = backend_env$bucket),
            list(name = "AWS_DEFAULT_REGION", value = backend_env$region)
          )
        )
      )
    )
  )

  # Add launch type specific parameters
  if (backend_env$launch_type == "EC2") {
    run_task_params$capacityProviderStrategy <- list(
      list(
        capacityProvider = backend_env$capacity_provider_name,
        weight = 1
      )
    )

    # Start warm pool if not started
    if (is.null(backend_env$pool_started_at)) {
      cat_info("[Setup] Starting warm EC2 pool...\n")
      start_warm_pool(backend_env, backend_env$workers, timeout_seconds = 120)
      backend_env$pool_started_at <- Sys.time()
    }
  } else {
    run_task_params$launchType <- "FARGATE"
  }

  # Submit task
  response <- do.call(ecs$run_task, run_task_params)

  # Check for failures
  if (length(response$failures) > 0) {
    failure <- response$failures[[1]]
    stop(sprintf("Failed to submit task: %s - %s",
                 failure$reason, failure$detail))
  }

  # Store task ARN in future
  if (length(response$tasks) > 0) {
    future$task_arn <- response$tasks[[1]]$taskArn
  }

  # Set the future class so our S3 methods get called
  class(future) <- c("StarburstFuture", "Future", class(future))

  # Update state to running
  future$state <- "running"

  # Track in backend
  backend_env$total_tasks <- backend_env$total_tasks + 1

  invisible(future)
}
