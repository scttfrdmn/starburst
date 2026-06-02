#' S3 task/result I/O for staRburst
#'
#' Serialization of task payloads to S3, polling for results, and cleanup of
#' the per-cluster task objects.
#'
#' @name s3-io
#' @keywords internal
NULL

#' Get starburst bucket name
#'
#' @return S3 bucket name
#' @keywords internal
get_starburst_bucket <- function() {
  config <- get_starburst_config()
  config$bucket
}

#' Create task object
#'
#' @keywords internal
create_task <- function(expr, globals, packages, plan) {
  list(
    expr = expr,
    globals = globals,
    packages = packages,
    plan_info = list(
      cluster_id = plan$cluster_id,
      cpu = plan$cpu,
      memory = plan$memory,
      region = plan$region
    )
  )
}

#' Serialize and upload to S3
#'
#' @keywords internal
serialize_and_upload <- function(obj, bucket, key) {
  temp_file <- tempfile(fileext = ".qs")
  on.exit(unlink(temp_file))

  qs2::qs_save(obj, temp_file)

  s3 <- get_s3_client(extract_region_from_key(key))
  s3$put_object(
    Bucket = bucket,
    Key = key,
    Body = temp_file
  )

  invisible(NULL)
}

#' Extract region from S3 key
#'
#' @keywords internal
extract_region_from_key <- function(key) {
  config <- get_starburst_config()
  config$region
}

#' Check if result exists
#'
#' @keywords internal
result_exists <- function(task_id, region) {
  bucket <- get_starburst_bucket()
  key <- sprintf("results/%s.qs", task_id)

  s3 <- get_s3_client(region)

  tryCatch({
    s3$head_object(Bucket = bucket, Key = key)
    return(TRUE)
  }, error = function(e) {
    return(FALSE)
  })
}

#' Poll for result
#'
#' @keywords internal
poll_for_result <- function(future, timeout = 3600) {
  bucket <- get_starburst_bucket()
  key <- sprintf("results/%s/%s.qs", future$plan$cluster_id, future$task_id)
  region <- future$plan$region

  s3 <- get_s3_client(region)

  start_time <- Sys.time()

  while (TRUE) {
    # Check if result exists
    if (result_exists(future$task_id, region)) {
      # Download and deserialize
      temp_file <- tempfile(fileext = ".qs")
      on.exit(unlink(temp_file))

      s3$download_file(
        Bucket = bucket,
        Key = key,
        Filename = temp_file
      )

      result <- qs2::qs_read(temp_file)
      return(result)
    }

    # Check timeout
    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    if (elapsed > timeout) {
      stop(sprintf("Task timeout after %d seconds", timeout))
    }

    # Wait before next poll
    Sys.sleep(2)
  }
}

#' Cleanup S3 files
#'
#' @keywords internal
cleanup_s3_files <- function(plan) {
  bucket <- get_starburst_bucket()
  prefix <- sprintf("tasks/%s/", plan$cluster_id)

  s3 <- get_s3_client(plan$region)

  tryCatch({
    # List and delete task files
    objects <- s3$list_objects_v2(Bucket = bucket, Prefix = prefix)

    if (length(objects$Contents) > 0) {
      delete_objects <- lapply(objects$Contents, function(obj) {
        list(Key = obj$Key)
      })

      s3$delete_objects(
        Bucket = bucket,
        Delete = list(Objects = delete_objects)
      )
    }
  }, error = function(e) {
    warning(sprintf("Error cleaning S3 files: %s", e$message))
  })

  invisible(NULL)
}
