#' View worker logs
#'
#' @param task_id Optional task ID to view logs for specific task
#' @param cluster_id Optional cluster ID to view logs for specific cluster
#' @param last_n Number of last log lines to show (default: 50)
#' @param region AWS region (default: from config)
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # View recent logs
#' starburst_logs()
#'
#' # View logs for specific task
#' starburst_logs(task_id = "abc-123")
#'
#' # View last 100 lines
#' starburst_logs(last_n = 100)
#' }
starburst_logs <- function(task_id = NULL,
                          cluster_id = NULL,
                          last_n = 50,
                          region = NULL) {

  config <- get_starburst_config()
  region <- region %||% config$region

  logs <- paws.management::cloudwatchlogs(config = list(region = region))

  # Determine log group and stream
  log_group <- "/aws/ecs/starburst-worker"

  if (!is.null(task_id)) {
    # Get logs for specific task
    log_stream <- sprintf("starburst/%s", task_id)
  } else if (!is.null(cluster_id)) {
    # Get logs for cluster
    log_stream <- sprintf("starburst-cluster/%s", cluster_id)
  } else {
    # Get most recent logs
    streams <- logs$describe_log_streams(
      logGroupName = log_group,
      orderBy = "LastEventTime",
      descending = TRUE,
      limit = 1
    )

    if (length(streams$logStreams) == 0) {
      message("No logs found")
      return(invisible(NULL))
    }

    log_stream <- streams$logStreams[[1]]$logStreamName
  }

  tryCatch({
    # Get log events
    events <- logs$get_log_events(
      logGroupName = log_group,
      logStreamName = log_stream,
      limit = last_n,
      startFromHead = FALSE
    )

    if (length(events$events) == 0) {
      message("No log events found")
      return(invisible(NULL))
    }

    # Print logs
    cat_header(sprintf("Logs: %s\n", log_stream))

    for (event in events$events) {
      timestamp <- format(
        as.POSIXct(event$timestamp / 1000, origin = "1970-01-01"),
        "%Y-%m-%d %H:%M:%S"
      )
      cat(sprintf("[%s] %s\n", timestamp, event$message))
    }

    invisible(events$events)

  }, error = function(e) {
    cat_error(sprintf("Error retrieving logs: %s\n", e$message))
    invisible(NULL)
  })
}

#' Rebuild environment image
#'
#' @param region AWS region (default: from config)
#' @param force Force rebuild even if current environment hasn't changed
#'
#' @export
#'
#' @examples
#' \dontrun{
#' starburst_rebuild_environment()
#' }
starburst_rebuild_environment <- function(region = NULL, force = FALSE) {
  config <- get_starburst_config()
  region <- region %||% config$region

  cat_info("Rebuilding R environment Docker image...\n")

  if (force) {
    cat_info("Force rebuild requested\n")
  }

  # Take new snapshot
  renv::snapshot(prompt = FALSE)

  # Calculate new hash
  lock_file <- renv::paths$lockfile()
  env_hash <- digest::digest(file = lock_file, algo = "md5")

  # Build image
  build_environment_image(env_hash, region)

  cat_success(sprintf("[OK] Environment rebuilt (hash: %s)\n", env_hash))

  invisible(env_hash)
}
