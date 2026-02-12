#!/usr/bin/env Rscript

# staRburst Worker Script
# This script runs inside Fargate containers to execute user tasks

main <- function() {
  # Get configuration from environment variables
  task_id <- Sys.getenv("TASK_ID")
  cluster_id <- Sys.getenv("CLUSTER_ID")
  bucket <- Sys.getenv("S3_BUCKET")
  region <- Sys.getenv("AWS_DEFAULT_REGION", "us-east-1")

  if (task_id == "" || bucket == "") {
    stop("Missing required environment variables: TASK_ID, S3_BUCKET")
  }

  message(sprintf("Worker starting for task: %s", task_id))

  tryCatch({
    # Load required packages
    library(paws.storage)
    library(qs)

    # Create S3 client with timeouts to prevent hanging
    s3 <- paws.storage::s3(config = list(
      region = region,
      connect_timeout = 60,    # 60 seconds to establish connection
      timeout = 300            # 5 minutes for operations
    ))

    # Download task from S3
    task_key <- sprintf("tasks/%s.qs", task_id)
    task_file <- tempfile(fileext = ".qs")

    message(sprintf("Downloading task from s3://%s/%s", bucket, task_key))

    s3$download_file(
      Bucket = bucket,
      Key = task_key,
      Filename = task_file
    )

    # Load task
    task <- qs::qread(task_file)
    unlink(task_file)

    # Auto-detect mode from task metadata
    if (!is.null(task$session_id)) {
      # Detached mode
      message(sprintf("Running in DETACHED mode for session: %s", task$session_id))
      run_detached_worker(task, s3, bucket, region, task_id)
    } else {
      # Ephemeral mode (existing behavior)
      message("Running in EPHEMERAL mode")
      run_ephemeral_worker(task, s3, bucket, region)
    }

  }, error = function(e) {
    message(sprintf("Worker failed: %s", e$message))
    message(sprintf("Traceback: %s", paste(capture.output(traceback()), collapse = "\n")))

    # Try to upload error result
    tryCatch({
      library(paws.storage)
      library(qs)

      s3 <- paws.storage::s3(config = list(region = region))

      error_result <- list(
        error = TRUE,
        message = e$message,
        traceback = capture.output(traceback())
      )

      result_key <- sprintf("results/%s.qs", task_id)
      result_file <- tempfile(fileext = ".qs")

      qs::qsave(error_result, result_file)

      s3$put_object(
        Bucket = bucket,
        Key = result_key,
        Body = result_file
      )

      unlink(result_file)

      message("Error result uploaded")
    }, error = function(e2) {
      message(sprintf("Failed to upload error result: %s", e2$message))
    })

    quit(status = 1)
  })
}

#' Run worker in ephemeral mode (existing behavior)
#'
#' Executes one task and exits
run_ephemeral_worker <- function(task, s3, bucket, region) {
  result <- execute_task_content(task)

  # Upload result and exit
  upload_result(result, task$task_id, s3, bucket)

  message("Worker completed successfully")
  quit(status = 0)
}

#' Run worker in detached mode
#'
#' Executes initial task, then polls for more work
run_detached_worker <- function(task, s3, bucket, region, worker_id) {
  session_id <- task$session_id
  idle_timeout <- 300  # 5 minutes
  last_task_time <- Sys.time()
  poll_interval <- 1
  max_poll_interval <- 30

  # Execute initial task (if not bootstrap)
  if (!is.null(task$expr)) {
    message("Executing initial task...")
    result <- execute_task_content(task)
    upload_result(result, task$task_id, s3, bucket)
    update_task_status_to_completed(session_id, task$task_id, s3, bucket, region)
    last_task_time <- Sys.time()
  } else {
    message("Bootstrap task - entering polling loop")
  }

  # Polling loop
  message("Entering polling loop for pending tasks...")

  while (TRUE) {
    # Check idle timeout
    idle_seconds <- difftime(Sys.time(), last_task_time, units = "secs")
    if (idle_seconds > idle_timeout) {
      message(sprintf("Idle timeout reached (%.0f seconds), exiting gracefully", idle_seconds))
      quit(status = 0)
    }

    # Try to claim a pending task
    pending_tasks <- list_pending_tasks(session_id, s3, bucket)

    if (length(pending_tasks) > 0) {
      message(sprintf("Found %d pending tasks, attempting to claim one", length(pending_tasks)))

      claimed <- FALSE
      for (pending_task_id in pending_tasks) {
        claimed <- try_claim_task(session_id, pending_task_id, worker_id, s3, bucket, region)

        if (claimed) {
          message(sprintf("Successfully claimed task: %s", pending_task_id))

          # Download and execute task
          task_data <- download_task(pending_task_id, s3, bucket)

          # Update status to running
          update_task_status_simple(session_id, pending_task_id, "running", s3, bucket, region)

          # Execute task
          result <- execute_task_content(task_data)

          # Upload result
          upload_result(result, pending_task_id, s3, bucket)

          # Update status to completed
          update_task_status_to_completed(session_id, pending_task_id, s3, bucket, region)

          last_task_time <- Sys.time()
          poll_interval <- 1  # Reset backoff
          break
        }
      }

      if (!claimed) {
        message("Failed to claim any pending tasks (race condition)")
      }
    } else {
      # No pending tasks, increase backoff
      message(sprintf("No pending tasks found, sleeping for %d seconds", poll_interval))
      Sys.sleep(poll_interval)
      poll_interval <- min(poll_interval * 2, max_poll_interval)
    }
  }
}

#' Execute task content (chunk or expr)
#'
#' Returns result object
execute_task_content <- function(task) {
  # Detect task format (chunk-based or Future-based)
  if (!is.null(task$chunk)) {
    # OLD FORMAT: Chunk-based execution
    message(sprintf("Task loaded with %d items in chunk", length(task$chunk)))
    message("Executing task...")

    chunk_results <- lapply(task$chunk, function(x) {
      tryCatch({
        task$fn(x)
      }, error = function(e) {
        list(
          error = TRUE,
          message = e$message,
          value = x
        )
      })
    })

    # Check for any errors
    errors <- sapply(chunk_results, function(r) {
      is.list(r) && !is.null(r$error) && r$error
    })

    if (any(errors)) {
      first_error <- which(errors)[1]
      result <- list(
        error = TRUE,
        message = sprintf("Error in chunk item %d: %s",
                         first_error,
                         chunk_results[[first_error]]$message),
        chunk_index = task$chunk_index
      )
    } else {
      result <- list(
        error = FALSE,
        value = chunk_results,
        chunk_index = task$chunk_index
      )
    }

  } else if (!is.null(task$expr)) {
    # NEW FORMAT: Future-based execution
    message("Task loaded (Future format)")
    message("Executing task...")

    # Set up environment with globals
    exec_env <- new.env(parent = globalenv())

    # Load globals into environment
    if (!is.null(task$globals) && length(task$globals) > 0) {
      for (name in names(task$globals)) {
        assign(name, task$globals[[name]], envir = exec_env)
      }
    }

    # Load packages
    if (!is.null(task$packages)) {
      for (pkg in task$packages) {
        library(pkg, character.only = TRUE)
      }
    }

    # Evaluate expression with error handling
    result <- tryCatch({
      result_value <- eval(task$expr, envir = exec_env)
      list(
        error = FALSE,
        value = result_value,
        stdout = "",
        conditions = list()
      )
    }, error = function(e) {
      # Capture error for debugging
      list(
        error = TRUE,
        message = e$message,
        value = NULL,
        stdout = "",
        conditions = list(list(
          type = "error",
          message = e$message,
          call = deparse(e$call)
        ))
      )
    })

  } else {
    stop("Unknown task format - neither chunk nor expr found")
  }

  result
}

#' Upload result to S3
upload_result <- function(result, task_id, s3, bucket) {
  result_key <- sprintf("results/%s.qs", task_id)
  result_file <- tempfile(fileext = ".qs")

  qs::qsave(result, result_file)

  s3$put_object(
    Bucket = bucket,
    Key = result_key,
    Body = result_file
  )

  unlink(result_file)

  message(sprintf("Result uploaded to s3://%s/%s", bucket, result_key))
}

#' Download task from S3
download_task <- function(task_id, s3, bucket) {
  task_key <- sprintf("tasks/%s.qs", task_id)
  task_file <- tempfile(fileext = ".qs")

  s3$download_file(
    Bucket = bucket,
    Key = task_key,
    Filename = task_file
  )

  task <- qs::qread(task_file)
  unlink(task_file)

  task
}

#' Try to atomically claim a task
#'
#' Returns TRUE if claimed, FALSE if race condition
try_claim_task <- function(session_id, task_id, worker_id, s3, bucket, region) {
  status_key <- sprintf("sessions/%s/tasks/%s/status.qs", session_id, task_id)

  tryCatch({
    # Get current status with ETag
    response <- s3$get_object(Bucket = bucket, Key = status_key)
    etag <- response$ETag

    # Read status
    status_file <- tempfile(fileext = ".qs")
    writeBin(response$Body, status_file)
    status <- qs::qread(status_file)
    unlink(status_file)

    # Only claim if pending
    if (status$state != "pending") {
      return(FALSE)
    }

    # Attempt atomic claim
    status$state <- "claimed"
    status$claimed_at <- Sys.time()
    status$claimed_by <- worker_id

    temp_file <- tempfile(fileext = ".qs")
    qs::qsave(status, temp_file)

    # Conditional PUT - only succeeds if ETag matches
    s3$put_object(
      Bucket = bucket,
      Key = status_key,
      Body = temp_file,
      IfMatch = etag
    )

    unlink(temp_file)

    return(TRUE)

  }, error = function(e) {
    # Check if it's a precondition failed (another worker claimed it)
    if (grepl("PreconditionFailed|412", e$message)) {
      return(FALSE)
    }
    # Other errors - return FALSE
    return(FALSE)
  })
}

#' List pending tasks in session
list_pending_tasks <- function(session_id, s3, bucket) {
  prefix <- sprintf("sessions/%s/tasks/", session_id)

  result <- s3$list_objects_v2(
    Bucket = bucket,
    Prefix = prefix
  )

  if (length(result$Contents) == 0) {
    return(character(0))
  }

  pending_tasks <- character(0)

  for (obj in result$Contents) {
    key <- obj$Key
    if (!grepl("/status\\.qs$", key)) next

    # Extract task_id
    key_parts <- strsplit(key, "/")[[1]]
    task_id <- key_parts[4]

    # Check status
    tryCatch({
      temp_file <- tempfile(fileext = ".qs")
      s3$download_file(
        Bucket = bucket,
        Key = key,
        Filename = temp_file
      )

      status <- qs::qread(temp_file)
      unlink(temp_file)

      if (status$state == "pending") {
        pending_tasks <- c(pending_tasks, task_id)
      }
    }, error = function(e) {
      # Skip on error
    })
  }

  pending_tasks
}

#' Update task status (simple version without ETag)
update_task_status_simple <- function(session_id, task_id, state, s3, bucket, region) {
  status_key <- sprintf("sessions/%s/tasks/%s/status.qs", session_id, task_id)

  tryCatch({
    temp_file <- tempfile(fileext = ".qs")
    s3$download_file(
      Bucket = bucket,
      Key = status_key,
      Filename = temp_file
    )

    status <- qs::qread(temp_file)
    status$state <- state

    if (state == "running") {
      status$started_at <- Sys.time()
    }

    qs::qsave(status, temp_file)

    s3$put_object(
      Bucket = bucket,
      Key = status_key,
      Body = temp_file
    )

    unlink(temp_file)
  }, error = function(e) {
    message(sprintf("Failed to update status: %s", e$message))
  })
}

#' Update task status to completed
update_task_status_to_completed <- function(session_id, task_id, s3, bucket, region) {
  status_key <- sprintf("sessions/%s/tasks/%s/status.qs", session_id, task_id)

  tryCatch({
    temp_file <- tempfile(fileext = ".qs")
    s3$download_file(
      Bucket = bucket,
      Key = status_key,
      Filename = temp_file
    )

    status <- qs::qread(temp_file)
    status$state <- "completed"
    status$completed_at <- Sys.time()

    qs::qsave(status, temp_file)

    s3$put_object(
      Bucket = bucket,
      Key = status_key,
      Body = temp_file
    )

    unlink(temp_file)
  }, error = function(e) {
    message(sprintf("Failed to update status to completed: %s", e$message))
  })
}

# Run main
main()
