#' S3 Session State Management
#'
#' Core S3 operations for managing detached session state
#'
#' @name session-state
#' @keywords internal
NULL

#' Create session manifest in S3
#'
#' @param session_id Unique session identifier
#' @param backend Backend configuration
#' @return Invisibly returns NULL
#' @keywords internal
create_session_manifest <- function(session_id, backend) {
  s3 <- get_s3_client(backend$region)
  bucket <- backend$bucket

  manifest <- list(
    session_id = session_id,
    created_at = Sys.time(),
    last_activity = Sys.time(),
    absolute_timeout = Sys.time() + backend$absolute_timeout,
    backend = list(
      workers = backend$workers,
      cpu = backend$cpu,
      memory = backend$memory,
      region = backend$region,
      bucket = backend$bucket,
      timeout = backend$timeout,
      image_uri = backend$image_uri,
      cluster = backend$cluster,
      cluster_name = backend$cluster_name,
      launch_type = backend$launch_type,
      instance_type = backend$instance_type,
      use_spot = backend$use_spot,
      architecture = backend$architecture,
      warm_pool_timeout = backend$warm_pool_timeout,
      capacity_provider_name = backend$capacity_provider_name,
      asg_name = backend$asg_name,
      aws_account_id = backend$aws_account_id,
      subnets = backend$subnets,
      security_groups = backend$security_groups,
      task_definition_arn = backend$task_definition_arn
    ),
    stats = list(
      total_tasks = 0,
      pending = 0,
      running = 0,
      completed = 0,
      failed = 0
    )
  )

  # Upload manifest to S3
  manifest_key <- sprintf("sessions/%s/manifest.qs", session_id)
  temp_file <- tempfile(fileext = ".qs")
  on.exit(unlink(temp_file), add = TRUE)

  qs::qsave(manifest, temp_file)

  s3$put_object(
    Bucket = bucket,
    Key = manifest_key,
    Body = temp_file
  )

  invisible(NULL)
}

#' Update session manifest atomically
#'
#' Uses S3 ETags for optimistic locking to prevent race conditions.
#'
#' @param session_id Session identifier
#' @param updates Named list of fields to update
#' @param region AWS region
#' @param bucket S3 bucket
#' @param max_retries Maximum number of retry attempts (default: 3)
#' @return Invisibly returns updated manifest
#' @keywords internal
update_session_manifest <- function(session_id, updates, region, bucket, max_retries = 3) {
  s3 <- get_s3_client(region)
  manifest_key <- sprintf("sessions/%s/manifest.qs", session_id)

  last_error <- NULL

  for (attempt in seq_len(max_retries)) {
    tryCatch({
      # 1. Get current manifest WITH ETag
      temp_file <- tempfile(fileext = ".qs")
      on.exit(unlink(temp_file), add = TRUE)

      # Get object with retry logic
      response <- with_s3_retry(
        {
          s3$get_object(
            Bucket = bucket,
            Key = manifest_key
          )
        },
        max_attempts = 3,
        operation_name = "S3 GetObject (manifest)"
      )

      # Extract ETag for conditional write
      etag <- response$ETag

      # Download object body
      writeBin(response$Body, temp_file)
      manifest <- qs::qread(temp_file)

      # 2. Apply updates
      for (name in names(updates)) {
        if (name == "stats") {
          # Update stats fields
          for (stat_name in names(updates$stats)) {
            manifest$stats[[stat_name]] <- updates$stats[[stat_name]]
          }
        } else {
          manifest[[name]] <- updates[[name]]
        }
      }

      # Update last_activity
      manifest$last_activity <- Sys.time()

      # 3. Save updated manifest
      qs::qsave(manifest, temp_file)

      # 4. Upload ATOMICALLY with conditional write
      # This only succeeds if ETag matches (i.e., object hasn't changed)
      s3$put_object(
        Bucket = bucket,
        Key = manifest_key,
        Body = temp_file,
        IfMatch = etag  # Conditional write - only if unchanged
      )

      # Success - return updated manifest
      return(invisible(manifest))

    }, error = function(e) {
      last_error <<- e

      # Check if error is due to ETag mismatch (precondition failed)
      if (grepl("PreconditionFailed|412", e$message, ignore.case = TRUE)) {
        # Another update happened concurrently, retry
        if (attempt < max_retries) {
          # Exponential backoff with jitter
          delay <- runif(1, 0.1, 0.5) * (2 ^ (attempt - 1))
          cat_warn(sprintf("  [WARNING] Concurrent update detected (attempt %d/%d), retrying in %.2fs...\n",
                          attempt, max_retries, delay))
          Sys.sleep(delay)
          # Continue to next iteration
        } else {
          # Exhausted retries
          stop(sprintf("Failed to update manifest after %d retries due to concurrent modifications",
                      max_retries))
        }
      } else {
        # Non-retryable error - fail immediately
        stop(e)
      }
    })
  }

  # Should only reach here if all retries exhausted
  stop(last_error)
}

#' Get session manifest from S3
#'
#' @param session_id Session identifier
#' @param region AWS region
#' @param bucket S3 bucket
#' @return Session manifest list
#' @keywords internal
get_session_manifest <- function(session_id, region, bucket) {
  s3 <- get_s3_client(region)
  manifest_key <- sprintf("sessions/%s/manifest.qs", session_id)

  temp_file <- tempfile(fileext = ".qs")
  on.exit(unlink(temp_file), add = TRUE)

  tryCatch({
    s3$download_file(
      Bucket = bucket,
      Key = manifest_key,
      Filename = temp_file
    )

    qs::qread(temp_file)
  }, error = function(e) {
    stop(sprintf("Session not found: %s", session_id))
  })
}

#' Create task status in S3
#'
#' @param session_id Session identifier
#' @param task_id Task identifier
#' @param state Initial state (default: "pending")
#' @param region AWS region
#' @param bucket S3 bucket
#' @return Invisibly returns NULL
#' @keywords internal
create_task_status <- function(session_id, task_id, state = "pending", region, bucket) {
  s3 <- get_s3_client(region)

  status <- list(
    task_id = task_id,
    state = state,
    created_at = Sys.time(),
    claimed_at = NULL,
    claimed_by = NULL,
    started_at = NULL,
    completed_at = NULL,
    error = NULL
  )

  status_key <- sprintf("sessions/%s/tasks/%s/status.qs", session_id, task_id)
  temp_file <- tempfile(fileext = ".qs")
  on.exit(unlink(temp_file), add = TRUE)

  qs::qsave(status, temp_file)

  s3$put_object(
    Bucket = bucket,
    Key = status_key,
    Body = temp_file
  )

  invisible(NULL)
}

#' Update task status with atomic write
#'
#' @param session_id Session identifier
#' @param task_id Task identifier
#' @param state New state
#' @param etag Optional ETag for conditional write (atomic claiming)
#' @param region AWS region
#' @param bucket S3 bucket
#' @param updates Optional additional fields to update
#' @return TRUE if successful, FALSE if conditional write failed
#' @keywords internal
update_task_status <- function(session_id, task_id, state, etag = NULL,
                               region, bucket, updates = list()) {
  s3 <- get_s3_client(region)
  status_key <- sprintf("sessions/%s/tasks/%s/status.qs", session_id, task_id)

  # Download current status
  temp_file <- tempfile(fileext = ".qs")
  on.exit(unlink(temp_file), add = TRUE)

  tryCatch({
    s3$download_file(
      Bucket = bucket,
      Key = status_key,
      Filename = temp_file
    )

    status <- qs::qread(temp_file)

    # Update state
    status$state <- state

    # Apply additional updates
    for (name in names(updates)) {
      status[[name]] <- updates[[name]]
    }

    # Save updated status
    qs::qsave(status, temp_file)

    # Conditional put if ETag provided
    put_params <- list(
      Bucket = bucket,
      Key = status_key,
      Body = temp_file
    )

    if (!is.null(etag)) {
      put_params$IfMatch <- etag
    }

    do.call(s3$put_object, put_params)

    return(TRUE)

  }, error = function(e) {
    # Check if it's a precondition failed error
    if (!is.null(etag) && grepl("PreconditionFailed|412", e$message)) {
      return(FALSE)
    }
    stop(e)
  })
}

#' Get task status from S3
#'
#' @param session_id Session identifier
#' @param task_id Task identifier
#' @param region AWS region
#' @param bucket S3 bucket
#' @param include_etag Include ETag in result (for atomic operations)
#' @return Task status list (with optional $etag field)
#' @keywords internal
get_task_status <- function(session_id, task_id, region, bucket, include_etag = FALSE) {
  s3 <- get_s3_client(region)
  status_key <- sprintf("sessions/%s/tasks/%s/status.qs", session_id, task_id)

  if (include_etag) {
    # Use get_object to retrieve ETag
    response <- s3$get_object(
      Bucket = bucket,
      Key = status_key
    )

    temp_file <- tempfile(fileext = ".qs")
    on.exit(unlink(temp_file), add = TRUE)

    writeBin(response$Body, temp_file)
    status <- qs::qread(temp_file)
    status$etag <- response$ETag

    return(status)
  } else {
    # Simple download
    temp_file <- tempfile(fileext = ".qs")
    on.exit(unlink(temp_file), add = TRUE)

    s3$download_file(
      Bucket = bucket,
      Key = status_key,
      Filename = temp_file
    )

    qs::qread(temp_file)
  }
}

#' List pending tasks in session
#'
#' @param session_id Session identifier
#' @param region AWS region
#' @param bucket S3 bucket
#' @return Character vector of pending task IDs
#' @keywords internal
list_pending_tasks <- function(session_id, region, bucket) {
  s3 <- get_s3_client(region)
  prefix <- sprintf("sessions/%s/tasks/", session_id)

  # List all task status files
  result <- s3$list_objects_v2(
    Bucket = bucket,
    Prefix = prefix
  )

  if (length(result$Contents) == 0) {
    return(character(0))
  }

  pending_tasks <- character(0)

  # Check each task status
  for (obj in result$Contents) {
    # Extract task_id from key (sessions/{session}/tasks/{task_id}/status.qs)
    key <- obj$Key
    if (!grepl("/status\\.qs$", key)) next

    key_parts <- strsplit(key, "/")[[1]]
    task_id <- key_parts[4]

    # Download and check status
    temp_file <- tempfile(fileext = ".qs")
    tryCatch({
      s3$download_file(
        Bucket = bucket,
        Key = key,
        Filename = temp_file
      )

      status <- qs::qread(temp_file)

      if (status$state == "pending") {
        pending_tasks <- c(pending_tasks, task_id)
      }
    }, error = function(e) {
      # Skip if error reading status
    }, finally = {
      unlink(temp_file)
    })
  }

  pending_tasks
}

#' List all task statuses in session
#'
#' @param session_id Session identifier
#' @param region AWS region
#' @param bucket S3 bucket
#' @return Named list of task statuses (task_id -> status)
#' @keywords internal
list_task_statuses <- function(session_id, region, bucket) {
  s3 <- get_s3_client(region)
  prefix <- sprintf("sessions/%s/tasks/", session_id)

  # List all task status files
  result <- s3$list_objects_v2(
    Bucket = bucket,
    Prefix = prefix
  )

  if (length(result$Contents) == 0) {
    return(list())
  }

  statuses <- list()

  # Read each task status
  for (obj in result$Contents) {
    key <- obj$Key
    if (!grepl("/status\\.qs$", key)) next

    # Extract task_id
    key_parts <- strsplit(key, "/")[[1]]
    task_id <- key_parts[4]

    # Download status
    temp_file <- tempfile(fileext = ".qs")
    tryCatch({
      s3$download_file(
        Bucket = bucket,
        Key = key,
        Filename = temp_file
      )

      statuses[[task_id]] <- qs::qread(temp_file)
    }, error = function(e) {
      # Skip if error reading status
    }, finally = {
      unlink(temp_file)
    })
  }

  statuses
}

#' Atomically claim a pending task
#'
#' This is a helper that combines get + conditional update in one operation
#'
#' @param session_id Session identifier
#' @param task_id Task identifier
#' @param worker_id Worker identifier claiming the task
#' @param region AWS region
#' @param bucket S3 bucket
#' @return TRUE if claimed successfully, FALSE if already claimed
#' @keywords internal
atomic_claim_task <- function(session_id, task_id, worker_id, region, bucket) {
  # Get current status with ETag
  status <- get_task_status(session_id, task_id, region, bucket, include_etag = TRUE)

  # Only claim if pending
  if (status$state != "pending") {
    return(FALSE)
  }

  # Attempt atomic update
  success <- update_task_status(
    session_id = session_id,
    task_id = task_id,
    state = "claimed",
    etag = status$etag,
    region = region,
    bucket = bucket,
    updates = list(
      claimed_at = Sys.time(),
      claimed_by = worker_id
    )
  )

  success
}
