# Package environment for storing the current backend
.starburst_state <- new.env(parent = emptyenv())

#' staRburst Future Backend
#'
#' A future backend for running parallel R workloads on AWS Fargate
#'
#' @param strategy The starburst strategy marker (ignored, for S3 dispatch)
#' @param workers Number of parallel workers
#' @param cpu vCPUs per worker (1, 2, 4, 8, or 16)
#' @param memory Memory per worker (supports GB notation, e.g., "8GB")
#' @param region AWS region (default: from config or "us-east-1")
#' @param timeout Maximum runtime in seconds (default: 3600)
#' @param auto_quota_request Automatically request quota increases (default: interactive())
#' @param ... Additional arguments passed to future backend
#'
#' @return A future plan object
#' @importFrom future plan
#' @method plan starburst
#' @export
#'
#' @examples
#' \dontrun{
#' library(furrr)
#' plan(starburst, workers = 50)
#' results <- future_map(1:1000, expensive_function)
#' }
plan.starburst <- function(strategy,
                           workers = 10,
                           cpu = 4,
                           memory = "8GB",
                           region = NULL,
                           timeout = 3600,
                           auto_quota_request = interactive(),
                           launch_type = "FARGATE",
                           instance_type = "c7g.xlarge",
                           use_spot = FALSE,
                           warm_pool_timeout = 3600,
                           detached = FALSE,
                           ...) {

  cat("DEBUG: plan.starburst() CALLED\n")
  cat(sprintf("  workers=%s, launch_type=%s, instance_type=%s\n",
              workers, launch_type, instance_type))

  # Guard against misuse of detached mode
  if (detached) {
    stop("Detached mode cannot be used with plan(). Use starburst_session() instead.\n\n",
         "Example:\n",
         "  session <- starburst_session(workers = 10)\n",
         "  session$submit(quote(my_computation()))\n",
         "  results <- session$collect()\n\n",
         "See ?starburst_session for details.")
  }

  # Validate inputs
  validate_workers(workers)
  validate_cpu(cpu)
  validate_memory(memory)
  validate_launch_type(launch_type)

  # Get configuration
  config <- get_starburst_config()
  region <- region %||% config$region %||% "us-east-1"

  # Check AWS credentials
  check_aws_credentials()

  # Validate instance type for EC2
  if (launch_type == "EC2") {
    validate_instance_type(instance_type)
  }

  # Get architecture from instance type
  architecture <- if (launch_type == "EC2") {
    get_architecture_from_instance_type(instance_type)
  } else {
    "X86_64"  # Fargate default
  }
  
  # Check quota (only for Fargate)
  quota_limited <- FALSE
  workers_per_wave <- workers
  num_waves <- 1

  if (launch_type == "FARGATE") {
    quota_info <- check_fargate_quota(region)
    vcpus_needed <- workers * cpu
    vcpus_available <- quota_info$limit

    if (vcpus_needed > vcpus_available) {
    # Calculate wave-based execution
    workers_per_wave <- floor(vcpus_available / cpu)
    num_waves <- ceiling(workers / workers_per_wave)
    quota_limited <- TRUE
    
    # Inform user
    cat_warn(sprintf(
      "⚠ Requested: %d workers (%d vCPUs)\n⚠ Current quota: %d vCPUs (allows %d workers max)\n",
      workers, vcpus_needed, vcpus_available, workers_per_wave
    ))
    
    cat_info(sprintf(
      "\n📋 Execution plan:\n   • Running in %d waves of %d workers each\n",
      num_waves, workers_per_wave
    ))
    
    # Offer quota increase
    if (!quota_info$increase_pending && auto_quota_request) {
      recommended_quota <- suggest_quota(vcpus_needed)
      
      cat_info(sprintf(
        "\n💡 Quota increase recommended:\n   Request %d vCPU quota? (usually approved in 1-24 hours)\n",
        recommended_quota
      ))
      
      response <- readline("   [y/n]: ")
      if (tolower(response) == "y") {
        case_id <- request_quota_increase(
          service = "fargate",
          quota_code = "L-3032A538",
          desired_value = recommended_quota,
          region = region,
          reason = sprintf("staRburst parallel R computing with %d workers", workers)
        )
        
        if (!is.null(case_id)) {
          cat_success(sprintf("✓ Quota increase requested (Case ID: %s)\n", case_id))
          cat_success("✓ You'll receive email when approved\n")
          cat_success("✓ Future runs will use full parallelism\n")
        }
      }
    }
    }
  }

  # Estimate cost
  cost_est <- estimate_cost(workers, cpu, memory,
                           launch_type = launch_type,
                           instance_type = instance_type,
                           use_spot = use_spot)

  if (launch_type == "FARGATE") {
    cat_info(sprintf("\n💰 Estimated cost: ~$%.2f/hour\n", cost_est$per_hour))
  } else {
    cat_info(sprintf("\n💰 Estimated cost: ~$%.2f/hour (%d x %s%s)\n",
                    cost_est$total_per_hour,
                    cost_est$instances_needed,
                    instance_type,
                    if (use_spot) " spot" else ""))
  }
  
  # Check cost limits
  if (!is.null(config$max_cost_per_job) && cost_est$per_hour > config$max_cost_per_job) {
    stop(sprintf(
      "Estimated cost ($%.2f/hr) exceeds limit ($%.2f/hr). Adjust with starburst_config(max_cost_per_job = ...)",
      cost_est$per_hour, config$max_cost_per_job
    ))
  }
  
  # Ensure environment is ready
  env_info <- ensure_environment(region)

  # Create cluster identifier
  cluster_id <- sprintf("starburst-%s", uuid::UUIDgenerate())
  
  # Get config for bucket
  config <- get_starburst_config()

  # Create backend object (mutable environment)
  backend <- list(
    cluster_id = cluster_id,
    cluster = env_info$cluster,
    workers = workers,
    workers_per_wave = workers_per_wave,
    num_waves = num_waves,
    quota_limited = quota_limited,
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
    wave_queue = list(
      pending = list(),         # Futures waiting to be submitted
      current_wave = 1,         # Current wave number
      wave_futures = list(),    # Currently running futures
      completed = 0             # Number of completed tasks
    ),
    worker_cpu = cpu,
    worker_memory = as.numeric(gsub("[^0-9.]", "", memory)),
    task_definition_arn = NULL,  # Will be set during first task submission
    # EC2-specific fields
    launch_type = launch_type,
    instance_type = instance_type,
    use_spot = use_spot,
    architecture = architecture,
    warm_pool_timeout = warm_pool_timeout,
    capacity_provider_name = sprintf("starburst-%s", gsub("\\.", "-", instance_type)),
    pool_started_at = NULL,
    asg_name = sprintf("starburst-asg-%s", gsub("\\.", "-", instance_type)),
    aws_account_id = config$aws_account_id
  )

  # Convert backend list to environment for mutability
  backend_env <- list2env(backend, parent = emptyenv())

  # Create an evaluator function that creates StarburstFuture objects
  evaluator <- function(expr, envir = parent.frame(), substitute = TRUE,
                        globals = TRUE, packages = NULL, lazy = FALSE,
                        seed = FALSE, ...) {
    StarburstFuture(
      expr = expr,
      envir = envir,
      substitute = substitute,
      globals = globals,
      packages = packages,
      lazy = lazy,
      seed = seed,
      ...
    )
  }

  # Register cleanup on exit
  if (!is.null(backend_env)) {
    cleanup_handler <- function() {
      cleanup_cluster(backend_env)
    }
    cleanup_handlers <- getOption("starburst.cleanup_handlers", list())
    cleanup_handlers[[backend_env$cluster_id]] <- cleanup_handler
    options(starburst.cleanup_handlers = cleanup_handlers)
  }

  cat_success(sprintf("✓ Cluster ready: %s\n", cluster_id))
  cat_info("DEBUG: About to call future::tweak()\n")

  # Create a tweaked strategy that knows about our backend
  # This tells future() to call future.starburst() when creating futures
  tweaked_strategy <- future::tweak(
    starburst,
    backend = backend_env,
    workers = workers,
    cpu = cpu,
    memory = memory,
    region = region,
    timeout = timeout
  )

  cat_info("DEBUG: tweak() returned successfully\n")

  # Store backend in option so StarburstFuture can access it
  options(starburst.current_backend = backend_env)
  options(starburst.current_cluster_id = cluster_id)

  # DEBUG
  cat_info(sprintf("DEBUG: Setting backend in options (is.null: %s)\n",
                   is.null(getOption("starburst.current_backend"))))

  # Attach backend as attribute to tweaked strategy (for potential direct access)
  attr(tweaked_strategy, "backend") <- backend_env
  attr(tweaked_strategy, "init") <- TRUE
  attr(tweaked_strategy, "cluster_id") <- cluster_id

  # DEBUG
  cat_info(sprintf("DEBUG: Backend attribute set (is.null: %s)\n",
                   is.null(attr(tweaked_strategy, "backend"))))

  tweaked_strategy
}

#' Get wave queue status
#'
#' @param backend Backend environment
#' @keywords internal
get_wave_status <- function(backend) {
  if (!backend$quota_limited) {
    return(NULL)
  }

  list(
    current_wave = backend$wave_queue$current_wave,
    pending = length(backend$wave_queue$pending),
    running = length(backend$wave_queue$wave_futures),
    completed = backend$wave_queue$completed,
    total_waves = backend$num_waves
  )
}

#' Clean up cluster resources
#'
#' @keywords internal
cleanup_cluster <- function(backend) {
  cat_info(sprintf("\n🧹 Cleaning up cluster: %s\n", backend$cluster_id))

  # Stop any running tasks
  stop_running_tasks(backend)

  # Calculate final cost
  final_cost <- calculate_total_cost(backend)

  # Calculate runtime
  runtime <- as.numeric(difftime(Sys.time(), backend$created_at, units = "mins"))

  # Report
  cat_success(sprintf(
    "✓ Cluster shutdown:\n   • Runtime: %.1f minutes\n   • Tasks completed: %d\n   • Tasks failed: %d\n   • Total cost: $%.2f\n",
    runtime, backend$completed_tasks, backend$failed_tasks, final_cost
  ))

  # Optionally clean up S3 files
  if (getOption("starburst.cleanup_s3", TRUE)) {
    cleanup_s3_files(backend)
  }

  # Handle EC2 warm pool cleanup
  if (backend$launch_type == "EC2" && !is.null(backend$pool_started_at)) {
    idle_time <- difftime(Sys.time(), backend$pool_started_at, units = "secs")

    if (idle_time > backend$warm_pool_timeout) {
      cat_info("🧹 Pool timeout reached, scaling down...\n")
      stop_warm_pool(backend)
    } else {
      remaining_mins <- (backend$warm_pool_timeout - as.numeric(idle_time)) / 60
      cat_info(sprintf("⏱  Pool will remain warm for %.1f more minutes\n", remaining_mins))
      cat_info(sprintf("   Set warm_pool_timeout=0 to scale down immediately\n"))
    }
  }

  invisible(NULL)
}

#' Register cleanup handler
#'
#' @keywords internal
register_cleanup <- function(evaluator) {
  # Get backend from evaluator
  backend <- attr(evaluator, "backend")

  if (is.null(backend)) {
    return(invisible(NULL))
  }

  # Register cleanup on R session exit
  cleanup_handler <- function() {
    cleanup_cluster(backend)
  }

  # Store in option for later retrieval
  cleanup_handlers <- getOption("starburst.cleanup_handlers", list())
  cleanup_handlers[[backend$cluster_id]] <- cleanup_handler
  options(starburst.cleanup_handlers = cleanup_handlers)

  invisible(NULL)
}

# Helper functions

validate_workers <- function(workers) {
  if (!is.numeric(workers) || workers < 1 || workers > 10000) {
    stop("workers must be between 1 and 10000")
  }
}

validate_cpu <- function(cpu) {
  valid_cpus <- c(0.25, 0.5, 1, 2, 4, 8, 16)
  if (!cpu %in% valid_cpus) {
    stop(sprintf("cpu must be one of: %s", paste(valid_cpus, collapse = ", ")))
  }
}

validate_memory <- function(memory) {
  # Parse memory string (e.g., "8GB")
  memory_gb <- parse_memory(memory)

  # Fargate memory ranges depend on CPU
  # This is simplified - actual validation would check CPU/memory compatibility
  if (memory_gb < 0.5 || memory_gb > 120) {
    stop("memory must be between 0.5GB and 120GB")
  }
}

validate_platform <- function(platform) {
  valid_platforms <- c("X86_64", "ARM64")
  if (!platform %in% valid_platforms) {
    stop(sprintf("platform must be one of: %s", paste(valid_platforms, collapse = ", ")))
  }
}

validate_launch_type <- function(launch_type) {
  valid_launch_types <- c("FARGATE", "EC2")
  if (!launch_type %in% valid_launch_types) {
    stop(sprintf("launch_type must be one of: %s", paste(valid_launch_types, collapse = ", ")))
  }
}

validate_instance_type <- function(instance_type) {
  # Validate instance type format (e.g., c7g.xlarge)
  if (!grepl("^[a-z][0-9]+[a-z]*\\.(nano|micro|small|medium|large|xlarge|[0-9]+xlarge)$", instance_type)) {
    stop(sprintf("Invalid instance_type: %s. Example valid types: c7g.xlarge, c7i.2xlarge, r7g.large", instance_type))
  }
}

parse_memory <- function(memory) {
  if (is.numeric(memory)) {
    return(memory)
  }
  
  if (grepl("GB$", memory, ignore.case = TRUE)) {
    return(as.numeric(sub("GB$", "", memory, ignore.case = TRUE)))
  }
  
  if (grepl("MB$", memory, ignore.case = TRUE)) {
    return(as.numeric(sub("MB$", "", memory, ignore.case = TRUE)) / 1024)
  }
  
  stop("memory must be numeric (GB) or string like '8GB'")
}

`%||%` <- function(a, b) {
  if (is.null(a)) b else a
}

#' staRburst Future Strategy
#'
#' Future strategy for running parallel R workloads on AWS Fargate
#'
#' @param workers Number of parallel workers
#' @param cpu vCPUs per worker (1, 2, 4, 8, or 16)
#' @param memory Memory per worker (supports GB notation, e.g., "8GB")
#' @param region AWS region (default: from config or "us-east-1")
#' @param timeout Maximum runtime in seconds (default: 3600)
#' @param auto_quota_request Automatically request quota increases
#' @param envir Environment for evaluation
#' @param ... Additional arguments
#'
#' @return A starburst future plan
#' @export
#'
#' @examples
#' \dontrun{
#' library(furrr)
#' plan(starburst, workers = 50)
#' results <- future_map(1:1000, expensive_function)
#' }

# Starburst marker now defined in StarburstBackend-class.R
