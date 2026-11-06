#' Create a Future using Starburst Backend
#'
#' This is the entry point called by the Future package when a plan(starburst) is active
#'
#' @param expr Expression to evaluate
#' @param envir Environment for evaluation
#' @param substitute Whether to substitute the expression
#' @param globals Globals to export (TRUE for auto-detection, list for manual)
#' @param packages Packages to load
#' @param lazy Whether to lazily evaluate (always FALSE for remote)
#' @param seed Random seed
#' @param stdout Whether to capture stdout (TRUE, FALSE, or NA)
#' @param conditions Character vector of condition classes to capture
#' @param label Optional label for the future
#' @param ... Additional arguments
#'
#' @return A StarburstFuture object
#' @importFrom future future
#' @method future starburst
#' @export
future.starburst <- function(expr, envir = parent.frame(), substitute = TRUE,
                             lazy = FALSE, seed = FALSE, globals = TRUE,
                             packages = NULL, stdout = TRUE, conditions = "condition",
                             label = NULL, ...) {
  StarburstFuture(
    expr = expr,
    envir = envir,
    substitute = substitute,
    globals = globals,
    packages = packages,
    lazy = lazy,
    seed = seed,
    stdout = stdout,
    conditions = conditions,
    label = label,
    ...
  )
}

#' StarburstFuture Constructor
#'
#' Creates a Future object for evaluation on AWS workers (EC2 by default, or Fargate)
#'
#' You do not normally call this yourself: with \code{plan(starburst)} active,
#' \code{future::future()}, \pkg{future.apply}, and \pkg{furrr} create these for you.
#'
#' @param expr Expression to evaluate
#' @param envir Environment for evaluation
#' @param substitute Whether to substitute the expression
#' @param globals Globals to export (TRUE for auto-detection, list for manual)
#' @param packages Packages to load
#' @param lazy Whether to lazily evaluate (always FALSE for remote)
#' @param seed Random seed
#' @param backend Backend environment to submit to. Defaults to the active
#'   \code{plan(starburst)} backend, then \code{getOption("starburst.current_backend")}.
#' @param ... Additional arguments
#'
#' @return A StarburstFuture object
#' @keywords internal
#' @export
StarburstFuture <- function(expr, envir = parent.frame(), substitute = TRUE,
                            globals = TRUE, packages = NULL, lazy = FALSE,
                            seed = FALSE, stdout = TRUE, conditions = "condition",
                            label = NULL, backend = NULL, ...) {

  # Substitute expression if needed
  if (substitute) {
    expr <- substitute(expr)
  }

  # Get backend from the explicit argument, the current plan, or options
  if (is.null(backend)) {
    backend <- attr(future::plan("next"), "backend")
  }

  if (is.null(backend)) {
    # Try to get from options
    backend <- getOption("starburst.current_backend")
  }

  if (is.null(backend)) {
    stop("No starburst backend found. Call plan(starburst, ...) first.")
  }

  if (!inherits(backend, "StarburstBackend")) {
    class(backend) <- c("StarburstBackend", "FutureBackend", class(backend))
  }

  # Auto-detect globals and packages
  if (isTRUE(globals)) {
    gp <- future::getGlobalsAndPackages(expr, envir = envir, globals = TRUE)
    globals <- gp$globals
    if (is.null(packages)) {
      packages <- gp$packages
    }
  } else if (is.list(globals) && !inherits(globals, "Globals")) {
    # Convert plain list to Globals object for proper serialization
    globals <- globals::as.Globals(globals)
  }

  # Generate task ID
  task_id <- sprintf("task-%s", gsub("-", "", uuid::UUIDgenerate()))

  # Create future object as a list first
  f_list <- list(
    expr = expr,
    envir = envir,
    globals = globals,
    packages = packages,
    seed = seed,
    task_id = task_id,
    backend = backend,
    state = "created",
    result_value = NULL,
    task_arn = NULL,
    submitted_at = NULL,
    ...
  )

  # Convert to environment for mutability
  f <- list2env(f_list, parent = emptyenv())

  # Set class after conversion to environment
  class(f) <- c("StarburstFuture", "Future", "environment")

  f
}

#' Run a StarburstFuture
#'
#' Submits the future task to AWS for execution (EC2 by default, or Fargate)
#'
#' @param future A StarburstFuture object
#' @param ... Additional arguments
#'
#' @return The future object (invisibly)
#' @importFrom future run resolved result
#' @export
run.StarburstFuture <- function(future, ...) {

  # Skip if already running or resolved
  if (future$state %in% c("running", "finished")) {
    return(invisible(future))
  }

  # Get backend/plan
  backend <- future$backend

  # Serialize task data
  task_data <- list(
    expr = future$expr,
    globals = future$globals,
    packages = future$packages,
    seed = future$seed
  )

  # Upload to S3
  s3 <- get_s3_client(backend$region)
  task_key <- sprintf("tasks/%s.qs", future$task_id)
  temp_file <- tempfile(fileext = ".qs")

  tryCatch({
    qs2::qs_save(task_data, temp_file)
    s3$put_object(
      Bucket = backend$bucket,
      Key = task_key,
      Body = temp_file
    )
  }, finally = {
    unlink(temp_file)
  })

  # Check if we should queue or submit immediately
  if (backend$quota_limited) {
    # Add to wave queue
    future$state <- "queued"
    backend$wave_queue$pending <- append(
      backend$wave_queue$pending,
      list(future)
    )
    # Try to submit next wave
    check_and_submit_wave(backend)
  } else {
    # Submit immediately
    submit_task(future, backend)
  }

  invisible(future)
}

#' Check if StarburstFuture is Resolved
#'
#' Checks whether the future task has completed execution
#'
#' @param x A StarburstFuture object
#' @param ... Additional arguments
#'
#' @return Logical indicating if the future is resolved
#' @export
resolved.StarburstFuture <- function(x, ...) {
  future <- x  # Match generic signature
  # If already resolved, return TRUE
  if (future$state == "finished") {
    return(TRUE)
  }

  # future's cancel() (used e.g. by future.apply/furrr after an error) sets
  # "canceled"; a canceled future is resolved, or callers wait forever
  if (future$state == "canceled") {
    return(TRUE)
  }

  # If queued, check if wave has progressed
  if (future$state == "queued") {
    backend <- future$backend
    if (backend$quota_limited) {
      check_and_submit_wave(backend)
    }
    return(FALSE)
  }

  # If not running yet, return FALSE
  if (future$state != "running") {
    return(FALSE)
  }

  # Check S3 for result
  backend <- future$backend
  if (result_in_s3(future, backend)) {
    future$state <- "finished"
    return(TRUE)
  }

  # The worker uploads its result before exiting, so a task that stopped
  # without one died (OOM, image pull failure, Spot reclaim, ...); without
  # this check value() would wait forever (#67)
  failure <- task_failure(future, backend)
  if (!is.null(failure)) {
    # The result may have landed between the two checks
    if (result_in_s3(future, backend)) {
      future$state <- "finished"
      return(TRUE)
    }
    future$result_value <- future::FutureResult(
      conditions = list(list(condition = simpleError(failure), signal = TRUE))
    )
    future$state <- "finished"
    return(TRUE)
  }

  FALSE
}

#' Does a future's result exist in S3?
#'
#' @keywords internal
result_in_s3 <- function(future, backend) {
  s3 <- get_s3_client(backend$region)
  tryCatch({
    s3$head_object(
      Bucket = backend$bucket,
      Key = sprintf("results/%s.qs", future$task_id)
    )
    TRUE
  }, error = function(e) FALSE)
}

#' Why a future's worker task ended without a result, if it did
#'
#' Checks ECS at most every \code{getOption("starburst.task_check_interval", 15)}
#' seconds. All of this R session's pending tasks are described together (100
#' per call), so polling many futures does not multiply API calls.
#'
#' @return NULL while the task is fine, else a failure message
#' @keywords internal
task_failure <- function(future, backend) {
  # Enforce the backend timeout, plus a margin for instance start and image pull
  timeout <- backend$timeout
  if (!is.null(timeout) && !is.null(future$submitted_at)) {
    elapsed <- as.numeric(difftime(Sys.time(), future$submitted_at, units = "secs"))
    if (elapsed > timeout + getOption("starburst.task_start_margin", 900)) {
      if (!is.null(future$task_arn)) {
        tryCatch(get_ecs_client(backend$region)$stop_task(
          cluster = backend$cluster_name %||% backend$cluster,
          task = future$task_arn,
          reason = "starburst: task timeout exceeded"
        ), error = function(e) NULL)
      }
      return(sprintf("Task %s did not finish within its timeout (%d s) and was stopped",
                     future$task_id, as.integer(timeout)))
    }
  }

  if (is.null(future$task_arn)) {
    return(NULL)
  }
  status <- ecs_task_status(future$task_arn, backend)
  if (is.null(status)) {
    return(NULL)
  }
  if (identical(status$lastStatus, "MISSING")) {
    return(sprintf("Worker task %s is no longer known to ECS and returned no result",
                   future$task_id))
  }
  if (!identical(status$lastStatus, "STOPPED")) {
    return(NULL)
  }
  details <- c(
    status$stoppedReason,
    if (!is.null(status$containerReason)) sprintf("container: %s", status$containerReason),
    if (!is.null(status$exitCode)) sprintf("exit code %s", status$exitCode)
  )
  sprintf("Worker task %s stopped without returning a result: %s",
          future$task_id,
          if (length(details)) paste(details, collapse = "; ") else "no reason given")
}

#' Cached ECS status of a task
#'
#' @keywords internal
ecs_task_status <- function(task_arn, backend) {
  cache <- get_task_status_cache()
  interval <- getOption("starburst.task_check_interval", 15)
  stale <- is.null(cache$checked_at) ||
    as.numeric(difftime(Sys.time(), cache$checked_at, units = "secs")) >= interval
  if (stale || is.null(cache$status[[task_arn]])) {
    refresh_task_status(cache, backend, task_arn)
  }
  cache$status[[task_arn]]
}

#' Describe all not-yet-stopped tasks this session launched
#'
#' @keywords internal
refresh_task_status <- function(cache, backend, task_arn) {
  terminal <- function(a) identical(cache$status[[a]]$lastStatus, "STOPPED") ||
    identical(cache$status[[a]]$lastStatus, "MISSING")
  arns <- unique(c(task_arn, vapply(list_task_arns(), function(r) r$task_arn %||% NA_character_,
                                    character(1))))
  arns <- arns[!is.na(arns)]
  arns <- arns[!vapply(arns, terminal, logical(1))]
  ecs <- get_ecs_client(backend$region)
  cluster <- backend$cluster_name %||% backend$cluster

  for (batch in split(arns, ceiling(seq_along(arns) / 100))) {
    resp <- tryCatch(ecs$describe_tasks(cluster = cluster, tasks = as.list(batch)),
                     error = function(e) NULL)
    # Transient API error: try again on the next check
    if (is.null(resp)) next
    for (t in resp$tasks) {
      container <- if (length(t$containers)) t$containers[[1]] else list()
      cache$status[[t$taskArn]] <- list(
        lastStatus = t$lastStatus,
        stoppedReason = t$stoppedReason,
        containerReason = container$reason,
        exitCode = container$exitCode
      )
    }
    for (f in resp$failures) {
      if (identical(f$reason, "MISSING")) {
        cache$status[[f$arn]] <- list(lastStatus = "MISSING")
      }
    }
  }
  cache$checked_at <- Sys.time()
  invisible(NULL)
}

#' Session-wide cache of ECS task status
#'
#' @keywords internal
get_task_status_cache <- function() {
  if (!exists(".starburst_task_status", envir = .starburst_env)) {
    cache <- new.env(parent = emptyenv())
    cache$status <- list()
    assign(".starburst_task_status", cache, envir = .starburst_env)
  }
  get(".starburst_task_status", envir = .starburst_env)
}

#' Get Result from StarburstFuture
#'
#' Retrieves the result from a resolved future
#'
#' @param future A StarburstFuture object
#' @param ... Additional arguments
#'
#' @return A FutureResult object
#' @export
result.StarburstFuture <- function(future, ...) {
  # If already have result, return it
  if (!is.null(future$result_value)) {
    return(future$result_value)
  }

  # Wait for resolution
  while (!resolved(future)) {
    Sys.sleep(1)
  }

  # resolved() records a failure result itself when the worker died (#67)
  if (!is.null(future$result_value)) {
    return(future$result_value)
  }

  # Download result from S3
  backend <- future$backend
  s3 <- get_s3_client(backend$region)
  result_key <- sprintf("results/%s.qs", future$task_id)
  temp_file <- tempfile(fileext = ".qs")

  result_data <- tryCatch({
    s3$download_file(
      Bucket = backend$bucket,
      Key = result_key,
      Filename = temp_file
    )
    qs2::qs_read(temp_file)
  }, error = function(e) {
    # A canceled future may never produce a result
    if (!identical(future$state, "canceled")) stop(e)
    NULL
  }, finally = {
    unlink(temp_file)
  })

  if (is.null(result_data)) {
    canceled <- structure(
      class = c("FutureCanceledError", "FutureError", "error", "condition"),
      list(message = sprintf("Future (task %s) was canceled", future$task_id),
           call = NULL)
    )
    result_obj <- future::FutureResult(
      conditions = list(list(condition = canceled, signal = TRUE))
    )
    future$result_value <- result_obj
    return(result_obj)
  }

  # Create FutureResult object
  if (!is.null(result_data$error) && result_data$error) {
    # Task failed. future expects each condition as list(condition, signal);
    # a bare condition is reported as an INTERNAL ERROR that hides the message.
    result_obj <- future::FutureResult(
      value = NULL,
      stdout = result_data$stdout %||% "",
      conditions = list(list(
        condition = simpleError(result_data$message %||% "Task failed"),
        signal = TRUE
      ))
    )
  } else {
    # Task succeeded
    result_obj <- future::FutureResult(
      value = result_data$value,
      stdout = result_data$stdout %||% "",
      conditions = list()
    )
  }

  # Cache result
  future$result_value <- result_obj

  # The result is cached, so the task payload and result can go (honours
  # auto_cleanup_s3, like cleanup_cluster())
  if (should_cleanup_s3()) {
    delete_task_objects(backend, future$task_id)
  }

  # Update backend stats
  backend$completed_tasks <- backend$completed_tasks + 1

  result_obj
}

#' Submit Task to ECS
#'
#' Internal function to submit a task to ECS (Fargate or EC2)
#'
#' @param future StarburstFuture object
#' @param backend Backend/plan object
#' @keywords internal
submit_task <- function(future, backend) {

  # Ensure task definition exists
  if (is.null(backend$task_definition_arn)) {
    backend$task_definition_arn <- get_or_create_task_definition(backend)
  }

  # Handle EC2 pool warmup if needed. Recorded on the backend's state env,
  # which is what cleanup_cluster()/stopWorkers() see.
  state <- backend_state(backend)
  if (backend$launch_type == "EC2" && is.null(state$pool_started_at)) {
    cat_info("[Setup] Starting warm EC2 pool (~2 min first time)...\n")
    start_warm_pool(backend, backend$workers)
    state$pool_started_at <- Sys.time()
  }

  # Get ECS client
  ecs <- get_ecs_client(backend$region)

  # Network configuration: the configured subnets/security groups (as
  # launchFuture() and sessions use), else the default VPC's
  if (length(backend$subnets) > 0 && length(backend$security_groups) > 0) {
    vpc_config <- list(subnets = backend$subnets,
                       security_groups = backend$security_groups)
  } else {
    vpc_config <- get_vpc_config(backend$region)
  }
  awsvpc_config <- list(
    subnets = vpc_config$subnets,
    securityGroups = vpc_config$security_groups
  )
  # assignPublicIp is Fargate-only; EC2 run_task rejects it
  if (backend$launch_type != "EC2") {
    awsvpc_config$assignPublicIp <- "ENABLED"
  }

  # Build base run_task parameters
  run_task_params <- list(
    cluster = backend$cluster_name %||% backend$cluster,
    taskDefinition = backend$task_definition_arn,
    networkConfiguration = list(
      awsvpcConfiguration = awsvpc_config
    ),
    overrides = list(
      containerOverrides = list(
        list(
          name = "starburst-worker",
          environment = list(
            list(name = "TASK_ID", value = future$task_id),
            list(name = "S3_BUCKET", value = backend$bucket),
            list(name = "AWS_DEFAULT_REGION", value = backend$region),
            list(name = "CLUSTER_ID", value = backend$cluster_id)
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
    run_task_params$placementConstraints <- list(
      list(
        type = "memberOf",
        expression = sprintf("attribute:ecs.instance-type == %s",
                           backend$instance_type)
      )
    )
  } else {
    run_task_params$launchType <- "FARGATE"
  }

  # Submit task
  response <- do.call(ecs$run_task, run_task_params)

  if (length(response$tasks) > 0) {
    future$task_arn <- response$tasks[[1]]$taskArn
    future$submitted_at <- Sys.time()
    future$state <- "running"

    # Store task ARN for monitoring and for scoped cleanup
    store_task_arn(future$task_id, future$task_arn)
    state$task_arns <- c(state$task_arns, future$task_arn)
    state$task_ids <- c(state$task_ids, future$task_id)
    # Keep the pool warm for warm_pool_timeout past this submission (#59)
    hold_warm_pool(backend)
  } else {
    # Task submission failed
    failure_msg <- if (length(response$failures) > 0) {
      sprintf("%s: %s", response$failures[[1]]$reason, response$failures[[1]]$detail)
    } else {
      "Unknown reason"
    }
    stop(sprintf("Failed to submit task: %s", failure_msg))
  }

  invisible(NULL)
}

#' Check and Submit Wave if Ready
#'
#' Checks wave queue and submits next wave if current wave is complete
#'
#' @param backend Backend environment
#' @keywords internal
check_and_submit_wave <- function(backend) {

  if (!backend$quota_limited) {
    return(invisible(NULL))
  }

  # Check how many futures are currently running
  running_futures <- backend$wave_queue$wave_futures
  running_count <- length(running_futures)

  # Remove completed futures from wave_futures
  if (running_count > 0) {
    still_running <- list()
    for (i in seq_along(running_futures)) {
      future_obj <- running_futures[[i]]
      if (!resolved(future_obj)) {
        still_running <- append(still_running, list(future_obj))
      } else {
        backend$wave_queue$completed <- backend$wave_queue$completed + 1
      }
    }
    backend$wave_queue$wave_futures <- still_running
    running_count <- length(still_running)
  }

  # If current wave is empty and there are pending futures, start new wave
  pending_futures <- backend$wave_queue$pending
  if (running_count == 0 && length(pending_futures) > 0) {
    # Calculate how many tasks to submit in this wave
    tasks_to_submit <- min(backend$workers_per_wave, length(pending_futures))

    cat_info(sprintf(
      "[Status] Starting wave %d: submitting %d tasks (%d pending, %d completed)\n",
      backend$wave_queue$current_wave,
      tasks_to_submit,
      length(pending_futures),
      backend$wave_queue$completed
    ))

    # Submit futures
    for (i in seq_len(tasks_to_submit)) {
      future_obj <- pending_futures[[1]]
      backend$wave_queue$pending <- pending_futures[-1]
      pending_futures <- backend$wave_queue$pending

      # Submit the future to Fargate
      submit_task(future_obj, backend)

      # Add to wave_futures for tracking
      backend$wave_queue$wave_futures <- append(
        backend$wave_queue$wave_futures,
        list(future_obj)
      )
    }

    # Increment wave counter
    backend$wave_queue$current_wave <- backend$wave_queue$current_wave + 1
  }

  invisible(NULL)
}

# Note: %||% operator defined in R/utils.R
