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
  
  # Create plan object
  plan <- structure(
    list(
      cluster_id = cluster_id,
      workers = workers,
      workers_per_wave = workers_per_wave,
      num_waves = num_waves,
      quota_limited = quota_limited,
      cpu = cpu,
      memory = memory,
      region = region,
      timeout = timeout,
      env_hash = env_info$hash,
      image_uri = env_info$image_uri,
      created_at = Sys.time(),
      total_tasks = 0,
      completed_tasks = 0,
      failed_tasks = 0,
      total_cost = 0,
      wave_queue = list(
        pending = list(),         # Tasks waiting to be submitted
        current_wave = 1,         # Current wave number
        wave_futures = list(),    # Currently running futures
        completed = 0             # Number of completed tasks
      ),
      worker_cpu = cpu,
      worker_memory = as.numeric(gsub("[^0-9.]", "", memory)),
      task_definition_arn = NULL  # Will be set during first task submission
    ),
    class = c("starburst", "cluster", "future")
  )
  
  # Register cleanup on exit
  register_cleanup(plan)
  
  cat_success(sprintf("✓ Cluster ready: %s\n", cluster_id))
  
  plan
}

#' Create a future using staRburst backend
#'
#' @param expr Expression to evaluate
#' @param envir Environment for evaluation
#' @param substitute Substitute expression
#' @param globals List of global variables
#' @param packages Packages to load
#' @param ... Additional arguments
#'
#' @keywords internal
future_starburst <- function(expr, envir = parent.frame(), 
                            substitute = TRUE, globals = TRUE,
                            packages = NULL, ...) {
  
  # Get current plan
  plan <- future::plan("next")
  if (!inherits(plan, "starburst")) {
    stop("No starburst plan active. Call plan(future_starburst) first.")
  }
  
  # Capture expression
  if (substitute) {
    expr <- substitute(expr)
  }
  
  # Identify dependencies
  if (isTRUE(globals)) {
    globals <- future::getGlobalsAndPackages(expr, envir = envir)
  }
  
  # Create task
  task <- create_task(
    expr = expr,
    globals = globals,
    packages = packages,
    plan = plan
  )
  
  # Submit to Fargate
  future_obj <- submit_task(task, plan)
  
  # Update plan counters
  plan$total_tasks <- plan$total_tasks + 1
  
  future_obj
}

#' Get value from starburst future
#'
#' @param future A starburst future object
#' @param ... Additional arguments
#'
#' @return The result of the future evaluation
#' @keywords internal
value.starburst_future <- function(future, ...) {
  
  # Check if already resolved
  if (!is.null(future$value)) {
    return(future$value)
  }
  
  # Poll for result
  result <- poll_for_result(future)
  
  # Handle errors
  if (is.list(result) && isTRUE(result$error)) {
    stop(sprintf("Task failed: %s\n%s", result$message, result$traceback))
  }
  
  # Cache value
  future$value <- result
  future$state <- "resolved"
  
  # Update plan
  plan <- future$plan
  plan$completed_tasks <- plan$completed_tasks + 1
  
  # Track cost for this task
  task_cost <- calculate_task_cost(future)
  plan$total_cost <- plan$total_cost + task_cost
  
  result
}

#' Check if future is resolved
#'
#' @param future A starburst future object
#' @param ... Additional arguments
#'
#' @return Logical indicating if resolved
#' @keywords internal
resolved.starburst_future <- function(future, ...) {
  if (!is.null(future$value)) {
    return(TRUE)
  }

  # If using wave execution, check wave queue progress
  if (future$plan$quota_limited && future$state == "queued") {
    # Trigger wave check (will submit next wave if current is done)
    future$plan <- check_and_submit_wave(future$plan)

    # Check if this task has been submitted yet
    if (future$task_id %in% names(future$plan$wave_queue$wave_futures)) {
      future$state <- "running"
    } else if (!(future$task_id %in% future$plan$wave_queue$pending)) {
      # Not in pending and not in wave_futures - must check S3
      # (could have been submitted and completed)
    }
  }

  # Check S3 for result
  result_exists(future$task_id, future$plan$region)
}

#' Submit task to Fargate
#'
#' @keywords internal
submit_task <- function(task, plan) {

  # Generate task ID
  task_id <- uuid::UUIDgenerate()

  # Serialize task to S3
  bucket <- get_starburst_bucket()
  task_key <- sprintf("tasks/%s/%s.qs", plan$cluster_id, task_id)

  serialize_and_upload(task, bucket, task_key)

  # Determine if we need to queue or can submit now
  if (plan$quota_limited) {
    # Wave-based execution - add to queue and get updated plan
    plan <- add_to_queue(task_id, plan)
  } else {
    # Submit immediately
    submit_fargate_task(task_id, plan)
  }

  # Create future object with updated plan
  future_obj <- structure(
    list(
      task_id = task_id,
      plan = plan,
      submitted_at = Sys.time(),
      state = if (plan$quota_limited) "queued" else "running",
      value = NULL
    ),
    class = c("starburst_future", "future")
  )

  future_obj
}

#' Submit actual Fargate task
#'
#' @keywords internal
submit_fargate_task <- function(task_id, plan) {
  
  # Get AWS clients
  ecs <- get_ecs_client(plan$region)
  
  # Task definition ARN
  task_def <- get_or_create_task_definition(plan)
  
  # Submit task
  response <- ecs$run_task(
    cluster = "starburst-cluster",
    taskDefinition = task_def,
    launchType = "FARGATE",
    networkConfiguration = list(
      awsvpcConfiguration = list(
        subnets = get_starburst_subnets(plan$region),
        securityGroups = get_starburst_security_groups(plan$region),
        assignPublicIp = "DISABLED"
      )
    ),
    overrides = list(
      containerOverrides = list(
        list(
          name = "worker",
          environment = list(
            list(name = "TASK_ID", value = task_id),
            list(name = "CLUSTER_ID", value = plan$cluster_id),
            list(name = "S3_BUCKET", value = get_starburst_bucket()),
            list(name = "AWS_REGION", value = plan$region)
          )
        )
      )
    )
  )
  
  # Store task ARN for monitoring
  store_task_arn(task_id, response$tasks[[1]]$taskArn)
  
  invisible(NULL)
}

#' Wave-based queue management - Add task to queue
#'
#' @keywords internal
#' @return Modified plan object
add_to_queue <- function(task_id, plan) {
  # Add task to pending queue
  plan$wave_queue$pending <- append(plan$wave_queue$pending, task_id)

  # Check if we can submit the next wave
  plan <- check_and_submit_wave(plan)

  return(plan)
}

#' Check and submit wave if ready
#'
#' @keywords internal
#' @return Modified plan object
check_and_submit_wave <- function(plan) {
  # Check how many tasks are currently running
  running_count <- length(plan$wave_queue$wave_futures)

  # Remove completed futures from wave_futures
  if (running_count > 0) {
    still_running <- list()
    for (task_id in names(plan$wave_queue$wave_futures)) {
      future_obj <- plan$wave_queue$wave_futures[[task_id]]
      if (!resolved(future_obj)) {
        still_running[[task_id]] <- future_obj
      } else {
        plan$wave_queue$completed <- plan$wave_queue$completed + 1
      }
    }
    plan$wave_queue$wave_futures <- still_running
    running_count <- length(still_running)
  }

  # If current wave is empty and there are pending tasks, start new wave
  if (running_count == 0 && length(plan$wave_queue$pending) > 0) {
    # Calculate how many tasks to submit in this wave
    tasks_to_submit <- min(plan$workers_per_wave, length(plan$wave_queue$pending))

    cat_info(sprintf(
      "📊 Starting wave %d: submitting %d tasks (%d pending, %d completed)\n",
      plan$wave_queue$current_wave,
      tasks_to_submit,
      length(plan$wave_queue$pending),
      plan$wave_queue$completed
    ))

    # Submit tasks
    for (i in 1:tasks_to_submit) {
      task_id <- plan$wave_queue$pending[[1]]
      plan$wave_queue$pending <- plan$wave_queue$pending[-1]

      # Submit the task
      submit_fargate_task(task_id, plan)

      # Create a future object for tracking
      future_obj <- structure(
        list(
          task_id = task_id,
          plan = plan,
          submitted_at = Sys.time(),
          state = "running",
          value = NULL
        ),
        class = c("starburst_future", "future")
      )

      plan$wave_queue$wave_futures[[task_id]] <- future_obj
    }

    # Increment wave counter
    plan$wave_queue$current_wave <- plan$wave_queue$current_wave + 1
  }

  return(plan)
}

#' Get wave queue status
#'
#' @keywords internal
get_wave_status <- function(plan) {
  if (!plan$quota_limited) {
    return(NULL)
  }

  list(
    current_wave = plan$wave_queue$current_wave,
    pending = length(plan$wave_queue$pending),
    running = length(plan$wave_queue$wave_futures),
    completed = plan$wave_queue$completed,
    total_waves = plan$num_waves
  )
}

#' Clean up cluster resources
#'
#' @keywords internal
cleanup_cluster <- function(plan) {
  cat_info(sprintf("\n🧹 Cleaning up cluster: %s\n", plan$cluster_id))
  
  # Stop any running tasks
  stop_running_tasks(plan)
  
  # Calculate final cost
  final_cost <- calculate_total_cost(plan)
  
  # Calculate runtime
  runtime <- as.numeric(difftime(Sys.time(), plan$created_at, units = "mins"))
  
  # Report
  cat_success(sprintf(
    "✓ Cluster shutdown:\n   • Runtime: %.1f minutes\n   • Tasks completed: %d\n   • Tasks failed: %d\n   • Total cost: $%.2f\n",
    runtime, plan$completed_tasks, plan$failed_tasks, final_cost
  ))
  
  # Optionally clean up S3 files
  if (getOption("starburst.cleanup_s3", TRUE)) {
    cleanup_s3_files(plan)
  }
  
  invisible(NULL)
}

#' Register cleanup handler
#'
#' @keywords internal
register_cleanup <- function(plan) {
  # Register cleanup on R session exit
  cleanup_handler <- function() {
    cleanup_cluster(plan)
  }
  
  # Store in option for later retrieval
  cleanup_handlers <- getOption("starburst.cleanup_handlers", list())
  cleanup_handlers[[plan$cluster_id]] <- cleanup_handler
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
starburst <- local({
  ## The factory function that creates the actual plan
  factory <- function(workers = 10, cpu = 4, memory = "8GB", region = NULL,
                     timeout = 3600, auto_quota_request = interactive(), ...) {
    plan.starburst(
      workers = workers,
      cpu = cpu,
      memory = memory,
      region = region,
      timeout = timeout,
      auto_quota_request = auto_quota_request,
      ...
    )
  }

  ## The strategy function with attributes
  strategy <- function(..., workers = 10, cpu = 4, memory = "8GB",
                       region = NULL, timeout = 3600,
                       auto_quota_request = interactive(),
                       envir = parent.frame()) {
    ## Just call the factory - plan() will handle the rest
    factory(workers = workers, cpu = cpu, memory = memory,
           region = region, timeout = timeout,
           auto_quota_request = auto_quota_request, ...)
  }

  ## Add required attributes
  class(strategy) <- c("starburst", "cluster", "future", "function")
  attr(strategy, "init") <- TRUE
  attr(strategy, "tweakable") <- c("workers", "cpu", "memory", "region", "timeout", "auto_quota_request")
  attr(strategy, "factory") <- factory

  strategy
})
