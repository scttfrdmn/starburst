#' Detached Session API
#'
#' User-facing API for creating and managing detached sessions
#'
#' @name session-api
NULL

#' Create a Detached Starburst Session
#'
#' Creates a new detached session that can run computations independently
#' of your R session. You can close R and reattach later to collect results.
#'
#' @param workers Number of parallel workers (default: 10)
#' @param cpu vCPUs per worker (default: 4)
#' @param memory Memory per worker, e.g., "8GB" (default: "8GB")
#' @param region AWS region (default: from config or "us-east-1")
#' @param timeout Task timeout in seconds (default: 3600)
#' @param session_timeout Active timeout in seconds (default: 3600)
#' @param absolute_timeout Maximum session lifetime in seconds (default: 86400)
#' @param launch_type "FARGATE" or "EC2" (default: "FARGATE")
#' @param instance_type EC2 instance type for EC2 launch (default: "c6a.large")
#' @param use_spot Use spot instances for EC2 (default: FALSE)
#' @param warm_pool_timeout EC2 warm pool timeout in seconds (default: 3600)
#'
#' @return A StarburstSession object with methods:
#'   \itemize{
#'     \item \code{submit(expr, ...)} - Submit a task to the session
#'     \item \code{status()} - Get progress summary
#'     \item \code{collect(wait = FALSE)} - Collect completed results
#'     \item \code{extend(seconds = 3600)} - Extend timeout
#'     \item \code{cleanup()} - Terminate and cleanup
#'   }
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Create detached session
#' session <- starburst_session(workers = 10)
#'
#' # Submit tasks
#' task_ids <- lapply(1:100, function(i) {
#'   session$submit(quote(expensive_computation(i)))
#' })
#'
#' # Close R and come back later...
#' session_id <- session$session_id
#'
#' # Reattach
#' session <- starburst_session_attach(session_id)
#'
#' # Collect results
#' results <- session$collect(wait = TRUE)
#' }
starburst_session <- function(workers = 10,
                              cpu = 4,
                              memory = "8GB",
                              region = NULL,
                              timeout = 3600,
                              session_timeout = 3600,
                              absolute_timeout = 86400,
                              launch_type = "FARGATE",
                              instance_type = "c6a.large",
                              use_spot = FALSE,
                              warm_pool_timeout = 3600) {

  # Generate session ID
  session_id <- sprintf("session-%s", gsub("-", "", uuid::UUIDgenerate()))

  cat_info(sprintf("📦 Creating detached session: %s\n", session_id))

  # Initialize backend
  backend <- initialize_detached_backend(
    session_id = session_id,
    workers = workers,
    cpu = cpu,
    memory = memory,
    region = region,
    timeout = timeout,
    absolute_timeout = absolute_timeout,
    launch_type = launch_type,
    instance_type = instance_type,
    use_spot = use_spot,
    warm_pool_timeout = warm_pool_timeout
  )

  # Launch workers
  launch_detached_workers(backend)

  # Create session object
  session <- create_session_object(backend)

  cat_success(sprintf("✓ Session ready: %s\n", session_id))
  cat_info("   Use session$submit(expr) to add tasks\n")
  cat_info("   Use session$status() to check progress\n")
  cat_info("   Use session$collect() to retrieve results\n")

  session
}

#' Reattach to Existing Session
#'
#' Reattach to a previously created detached session
#'
#' @param session_id Session identifier
#' @param region AWS region (default: from config)
#'
#' @return A StarburstSession object
#' @export
#'
#' @examples
#' \dontrun{
#' session <- starburst_session_attach("session-abc123")
#' status <- session$status()
#' results <- session$collect()
#' }
starburst_session_attach <- function(session_id, region = NULL) {
  config <- get_starburst_config()
  region <- region %||% config$region %||% "us-east-1"
  bucket <- config$bucket

  cat_info(sprintf("🔗 Attaching to session: %s\n", session_id))

  # Load session manifest from S3
  manifest <- get_session_manifest(session_id, region, bucket)

  # Check if session expired
  if (Sys.time() > manifest$absolute_timeout) {
    stop(sprintf("Session expired: %s", session_id))
  }

  # Reconstruct backend
  backend <- reconstruct_backend_from_manifest(manifest)

  # Create session object
  session <- create_session_object(backend)

  cat_success(sprintf("✓ Attached to session: %s\n", session_id))

  session
}

#' List All Sessions
#'
#' List all detached sessions in S3
#'
#' @param region AWS region (default: from config)
#'
#' @return Data frame with session information
#' @export
#'
#' @examples
#' \dontrun{
#' sessions <- starburst_list_sessions()
#' print(sessions)
#' }
starburst_list_sessions <- function(region = NULL) {
  config <- get_starburst_config()
  region <- region %||% config$region %||% "us-east-1"
  bucket <- config$bucket

  s3 <- get_s3_client(region)

  # List all session manifests
  result <- s3$list_objects_v2(
    Bucket = bucket,
    Prefix = "sessions/",
    Delimiter = "/"
  )

  if (length(result$CommonPrefixes) == 0) {
    cat_info("No sessions found\n")
    return(data.frame(
      session_id = character(0),
      created_at = character(0),
      last_activity = character(0),
      total_tasks = integer(0),
      pending = integer(0),
      running = integer(0),
      completed = integer(0),
      failed = integer(0)
    ))
  }

  sessions <- list()

  for (prefix_obj in result$CommonPrefixes) {
    # Extract session ID from prefix
    session_id <- sub("sessions/(.*)/", "\\1", prefix_obj$Prefix)

    tryCatch({
      manifest <- get_session_manifest(session_id, region, bucket)

      sessions[[session_id]] <- data.frame(
        session_id = session_id,
        created_at = format(manifest$created_at),
        last_activity = format(manifest$last_activity),
        total_tasks = manifest$stats$total_tasks,
        pending = manifest$stats$pending,
        running = manifest$stats$running,
        completed = manifest$stats$completed,
        failed = manifest$stats$failed,
        stringsAsFactors = FALSE
      )
    }, error = function(e) {
      # Skip if manifest cannot be read
    })
  }

  if (length(sessions) == 0) {
    return(data.frame(
      session_id = character(0),
      created_at = character(0),
      last_activity = character(0),
      total_tasks = integer(0),
      pending = integer(0),
      running = integer(0),
      completed = integer(0),
      failed = integer(0)
    ))
  }

  do.call(rbind, sessions)
}

#' Create session object with methods
#'
#' @param backend Backend environment
#' @return Session object (environment)
#' @keywords internal
create_session_object <- function(backend) {
  session <- new.env(parent = emptyenv())
  session$backend <- backend
  session$session_id <- backend$session_id

  # Submit method
  session$submit <- function(expr, envir = parent.frame(), substitute = TRUE,
                            globals = TRUE, packages = NULL) {
    submit_to_session(session, expr, envir, substitute, globals, packages)
  }

  # Status method
  session$status <- function() {
    get_session_status(session)
  }

  # Collect method
  session$collect <- function(wait = FALSE, timeout = 3600) {
    collect_session_results(session, wait, timeout)
  }

  # Extend method
  session$extend <- function(seconds = 3600) {
    extend_session_timeout(session, seconds)
  }

  # Cleanup method
  session$cleanup <- function() {
    cleanup_session(session)
  }

  class(session) <- c("StarburstSession", "environment")

  session
}

#' Submit task to session
#'
#' @keywords internal
submit_to_session <- function(session, expr, envir, substitute, globals, packages) {
  backend <- session$backend

  # Substitute expression if needed
  if (substitute) {
    expr_sub <- base::substitute(expr)
    # If substitute returns a symbol 'expr', it means the argument was already
    # evaluated (e.g., user passed quote(...)). In that case, use the value.
    if (is.symbol(expr_sub) && identical(as.character(expr_sub), "expr")) {
      # expr is already evaluated, check if it's a language object
      if (!is.language(expr)) {
        stop("When substitute=TRUE and passing an evaluated expression, ",
             "it must be a language object (e.g., created with quote())")
      }
      # Use the evaluated expression as-is
    } else {
      # Use the substituted expression
      expr <- expr_sub
    }
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

  # Create task data
  task_data <- list(
    session_id = backend$session_id,
    task_id = task_id,
    expr = expr,
    globals = globals,
    packages = packages
  )

  # Upload task to S3
  upload_detached_task(task_id, task_data, backend)

  # Create task status as pending
  create_task_status(
    session_id = backend$session_id,
    task_id = task_id,
    state = "pending",
    region = backend$region,
    bucket = backend$bucket
  )

  # Update manifest stats
  update_session_manifest(
    session_id = backend$session_id,
    updates = list(
      stats = list(
        total_tasks = backend$total_tasks + 1,
        pending = NA  # Will be recalculated in status()
      )
    ),
    region = backend$region,
    bucket = backend$bucket
  )

  backend$total_tasks <- backend$total_tasks + 1

  cat_info(sprintf("✓ Task submitted: %s\n", task_id))

  invisible(task_id)
}

#' Get session status
#'
#' @keywords internal
get_session_status <- function(session) {
  backend <- session$backend

  # Get all task statuses
  statuses <- list_task_statuses(
    session_id = backend$session_id,
    region = backend$region,
    bucket = backend$bucket
  )

  # Count by state (excluding bootstrap tasks)
  counts <- list(
    total = 0,
    pending = 0,
    claimed = 0,
    running = 0,
    completed = 0,
    failed = 0
  )

  for (task_id in names(statuses)) {
    # Skip bootstrap tasks
    if (grepl("^bootstrap-", task_id)) {
      next
    }

    status <- statuses[[task_id]]
    state <- status$state

    counts$total <- counts$total + 1

    if (state %in% names(counts)) {
      counts[[state]] <- counts[[state]] + 1
    }
  }

  # Combine claimed and running
  counts$running <- counts$running + counts$claimed
  counts$claimed <- NULL

  structure(counts, class = "StarburstSessionStatus")
}

#' Collect results from session
#'
#' @keywords internal
collect_session_results <- function(session, wait, timeout) {
  backend <- session$backend
  s3 <- get_s3_client(backend$region)

  start_time <- Sys.time()
  results <- list()

  repeat {
    # Get all task statuses
    statuses <- list_task_statuses(
      session_id = backend$session_id,
      region = backend$region,
      bucket = backend$bucket
    )

    # Collect completed results that we haven't collected yet
    for (task_id in names(statuses)) {
      # Skip bootstrap tasks
      if (grepl("^bootstrap-", task_id)) {
        next
      }

      status <- statuses[[task_id]]

      # Skip if not completed or already collected
      if (status$state != "completed" || task_id %in% names(results)) {
        next
      }

      # Download result from S3
      result_key <- sprintf("results/%s.qs", task_id)
      temp_file <- tempfile(fileext = ".qs")

      tryCatch({
        s3$download_file(
          Bucket = backend$bucket,
          Key = result_key,
          Filename = temp_file
        )

        result_data <- qs::qread(temp_file)
        results[[task_id]] <- result_data
      }, error = function(e) {
        cat_warn(sprintf("Failed to download result for task %s: %s\n",
                        task_id, e$message))
      }, finally = {
        unlink(temp_file)
      })
    }

    # Check if we should continue waiting
    if (!wait) {
      break
    }

    # Check if all tasks are completed
    all_completed <- all(sapply(statuses, function(s) {
      s$state %in% c("completed", "failed")
    }))

    if (all_completed) {
      break
    }

    # Check timeout
    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    if (elapsed > timeout) {
      cat_warn("Collection timeout reached\n")
      break
    }

    # Wait before next poll
    Sys.sleep(2)
  }

  cat_info(sprintf("✓ Collected %d results\n", length(results)))

  results
}

#' Extend session timeout
#'
#' @keywords internal
extend_session_timeout <- function(session, seconds) {
  backend <- session$backend

  # Update manifest with new timeout
  update_session_manifest(
    session_id = backend$session_id,
    updates = list(
      absolute_timeout = Sys.time() + seconds
    ),
    region = backend$region,
    bucket = backend$bucket
  )

  cat_success(sprintf("✓ Extended session timeout by %d seconds\n", seconds))

  invisible(NULL)
}

#' Cleanup session
#'
#' @keywords internal
cleanup_session <- function(session) {
  backend <- session$backend

  cat_info(sprintf("🧹 Cleaning up session: %s\n", backend$session_id))

  # Stop any running tasks (optional - they will time out naturally)
  # For now, just mark session as cleaned up

  # Could delete S3 files if desired
  # For safety, we'll leave them for manual cleanup

  cat_success("✓ Session marked for cleanup\n")
  cat_info("   Workers will self-terminate after idle timeout\n")
  cat_info("   S3 files remain available for recovery\n")

  invisible(NULL)
}

#' Print method for session status
#'
#' @export
print.StarburstSessionStatus <- function(x, ...) {
  cat("Session Status:\n")
  cat(sprintf("  Total tasks:     %d\n", x$total))
  cat(sprintf("  Pending:         %d\n", x$pending))
  cat(sprintf("  Running:         %d\n", x$running))
  cat(sprintf("  Completed:       %d\n", x$completed))
  cat(sprintf("  Failed:          %d\n", x$failed))

  if (x$total > 0) {
    pct_complete <- round(100 * x$completed / x$total, 1)
    cat(sprintf("  Progress:        %.1f%%\n", pct_complete))
  }

  invisible(x)
}
