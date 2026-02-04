#' staRburst Future Backend
#'
#' A future backend for running parallel R workloads on AWS Fargate
#'
#' @param workers Number of parallel workers
#' @param cpu vCPUs per worker (1, 2, 4, 8, or 16)
#' @param memory Memory per worker (supports GB notation, e.g., "8GB")
#' @param region AWS region (default: from config or "us-east-1")
#' @param timeout Maximum runtime in seconds (default: 3600)
#' @param auto_quota_request Automatically request quota increases (default: interactive())
#' @param ... Additional arguments passed to future backend
#'
#' @return A future plan object
#' @export
#'
#' @examples
#' \dontrun{
#' library(furrr)
#' plan(future_starburst, workers = 50)
#' results <- future_map(1:1000, expensive_function)
#' }
plan.starburst <- function(workers = 10,
                           cpu = 4,
                           memory = "8GB",
                           region = NULL,
                           timeout = 3600,
                           auto_quota_request = interactive(),
                           ...) {
  
  # Validate inputs
  validate_workers(workers)
  validate_cpu(cpu)
  validate_memory(memory)
  
  # Get configuration
  config <- get_starburst_config()
  region <- region %||% config$region %||% "us-east-1"
  
  # Check AWS credentials
  check_aws_credentials()
  
  # Check quota
  quota_info <- check_fargate_quota(region)
  vcpus_needed <- workers * cpu
  vcpus_available <- quota_info$limit
  
  quota_limited <- FALSE
  workers_per_wave <- workers
  num_waves <- 1
  
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
  
  # Estimate cost
  cost_est <- estimate_cost(workers, cpu, memory)
  cat_info(sprintf("\n💰 Estimated cost: ~$%.2f/hour\n", cost_est$per_hour))
  
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
    task_definition_arn = NULL  # Will be set during first task submission
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

  # Attach backend as attribute
  attr(evaluator, "backend") <- backend_env
  attr(evaluator, "init") <- TRUE

  # Set proper class
  class(evaluator) <- c("StarburstEvaluator", "FutureEvaluator", "function")

  evaluator

  # Register cleanup on exit
  register_cleanup(evaluator)

  cat_success(sprintf("✓ Cluster ready: %s\n", cluster_id))

  evaluator
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

#' Starburst strategy marker
#' @export
starburst <- structure(function(...) {},
                       class = c("starburst", "future", "function"))
