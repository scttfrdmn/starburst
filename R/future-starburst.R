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
#' @param ... Additional arguments
#'
#' @return A StarburstFuture object
#' @importFrom future future
#' @method future starburst
#' @export
future.starburst <- function(expr, envir = parent.frame(), substitute = TRUE,
                             globals = TRUE, packages = NULL, lazy = FALSE,
                             seed = FALSE, ...) {
  StarburstFuture(
    expr = expr,
    envir = envir,
    substitute = substitute,
    globals = globals,
    packages = packages,
    lazy = lazy,
    seed = FALSE,
    ...
  )
}

#' StarburstFuture Constructor
#'
#' Creates a Future object for evaluation on AWS Fargate
#'
#' @param expr Expression to evaluate
#' @param envir Environment for evaluation
#' @param substitute Whether to substitute the expression
#' @param globals Globals to export (TRUE for auto-detection, list for manual)
#' @param packages Packages to load
#' @param lazy Whether to lazily evaluate (always FALSE for remote)
#' @param seed Random seed
#' @param ... Additional arguments
#'
#' @return A StarburstFuture object
#' @keywords internal
#' @export
StarburstFuture <- function(expr, envir = parent.frame(), substitute = TRUE,
                            globals = TRUE, packages = NULL, lazy = FALSE,
                            seed = FALSE, ...) {

  # Substitute expression if needed
  if (substitute) {
    expr <- substitute(expr)
  }

  # Get current plan
  plan_obj <- future::plan("next")

  # Get backend from plan attributes or options
  backend <- attr(plan_obj, "backend")

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
#' Submits the future task to AWS Fargate for execution
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
    qs::qsave(task_data, temp_file)
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
    submit_fargate_task(future, backend)
  }

  invisible(future)
}

#' Check if StarburstFuture is Resolved
#'
#' Checks whether the future task has completed execution
#'
#' @param future A StarburstFuture object
#' @param ... Additional arguments
#'
#' @return Logical indicating if the future is resolved
#' @export
resolved.StarburstFuture <- function(future, ...) {

  # If already resolved, return TRUE
  if (future$state == "finished") {
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
  s3 <- get_s3_client(backend$region)
  result_key <- sprintf("results/%s.qs", future$task_id)

  result_exists <- tryCatch({
    s3$head_object(
      Bucket = backend$bucket,
      Key = result_key
    )
    TRUE
  }, error = function(e) {
    FALSE
  })

  if (result_exists) {
    future$state <- "finished"
    return(TRUE)
  }

  # Check if task failed (optional: query ECS for task status)
  # For now, just return FALSE
  FALSE
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

  # Download result from S3
  backend <- future$backend
  s3 <- get_s3_client(backend$region)
  result_key <- sprintf("results/%s.qs", future$task_id)
  temp_file <- tempfile(fileext = ".qs")

  tryCatch({
    s3$download_file(
      Bucket = backend$bucket,
      Key = result_key,
      Filename = temp_file
    )
    result_data <- qs::qread(temp_file)
  }, finally = {
    unlink(temp_file)
  })

  # Create FutureResult object
  if (!is.null(result_data$error) && result_data$error) {
    # Task failed
    result_obj <- structure(
      list(
        value = NULL,
        visible = TRUE,
        stdout = result_data$stdout %||% "",
        conditions = list(
          simpleError(result_data$message %||% "Task failed")
        ),
        version = "1.8"
      ),
      class = "FutureResult"
    )
  } else {
    # Task succeeded
    result_obj <- structure(
      list(
        value = result_data$value,
        visible = TRUE,
        stdout = result_data$stdout %||% "",
        conditions = list(),
        version = "1.8"
      ),
      class = "FutureResult"
    )
  }

  # Cache result
  future$result_value <- result_obj

  # Update backend stats
  backend$completed_tasks <- backend$completed_tasks + 1

  result_obj
}

#' Submit Fargate Task
#'
#' Internal function to submit a task to ECS Fargate
#'
#' @param future StarburstFuture object
#' @param backend Backend/plan object
#' @keywords internal
submit_fargate_task <- function(future, backend) {

  # Ensure task definition exists
  if (is.null(backend$task_definition_arn)) {
    backend$task_definition_arn <- get_or_create_task_definition(backend)
  }

  # Get ECS client
  ecs <- get_ecs_client(backend$region)

  # Get network configuration
  vpc_config <- get_vpc_config(backend$region)

  # Submit task
  response <- ecs$run_task(
    cluster = "default",
    taskDefinition = backend$task_definition_arn,
    launchType = "FARGATE",
    networkConfiguration = list(
      awsvpcConfiguration = list(
        subnets = vpc_config$subnets,
        securityGroups = vpc_config$security_groups,
        assignPublicIp = "ENABLED"
      )
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

  if (length(response$tasks) > 0) {
    future$task_arn <- response$tasks[[1]]$taskArn
    future$submitted_at <- Sys.time()
    future$state <- "running"

    # Store task ARN for monitoring
    store_task_arn(future$task_id, future$task_arn)
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
      "📊 Starting wave %d: submitting %d tasks (%d pending, %d completed)\n",
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
      submit_fargate_task(future_obj, backend)

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

#' Null-coalescing operator
#' @keywords internal
`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}
