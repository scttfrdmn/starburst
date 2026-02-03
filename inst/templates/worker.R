#!/usr/bin/env Rscript

# staRburst Worker Script
# This script runs inside Fargate containers to execute user tasks

main <- function() {
  # Get configuration from environment variables
  task_id <- Sys.getenv("TASK_ID")
  cluster_id <- Sys.getenv("CLUSTER_ID")
  bucket <- Sys.getenv("S3_BUCKET")
  region <- Sys.getenv("AWS_REGION", "us-east-1")

  if (task_id == "" || bucket == "") {
    stop("Missing required environment variables: TASK_ID, S3_BUCKET")
  }

  message(sprintf("Worker starting for task: %s", task_id))

  tryCatch({
    # Download task from S3
    task_key <- sprintf("tasks/%s/%s.qs", cluster_id, task_id)
    task_file <- tempfile(fileext = ".qs")

    message(sprintf("Downloading task from s3://%s/%s", bucket, task_key))

    download_from_s3(bucket, task_key, task_file)

    # Load task
    task <- qs::qread(task_file)
    unlink(task_file)

    message("Task loaded, restoring environment...")

    # Restore environment
    if (!is.null(task$globals)) {
      for (name in names(task$globals)) {
        assign(name, task$globals[[name]], envir = .GlobalEnv)
      }
    }

    # Load packages
    if (!is.null(task$packages)) {
      for (pkg in task$packages) {
        library(pkg, character.only = TRUE)
      }
    }

    message("Executing task...")

    # Execute task
    result <- tryCatch({
      eval(task$expr, envir = .GlobalEnv)
    }, error = function(e) {
      list(
        error = TRUE,
        message = e$message,
        traceback = capture.output(traceback())
      )
    })

    message("Task completed, uploading result...")

    # Upload result to S3
    result_key <- sprintf("results/%s/%s.qs", cluster_id, task_id)
    result_file <- tempfile(fileext = ".qs")

    qs::qsave(result, result_file)
    upload_to_s3(bucket, result_key, result_file)
    unlink(result_file)

    message(sprintf("Result uploaded to s3://%s/%s", bucket, result_key))
    message("Worker completed successfully")

    quit(status = 0)

  }, error = function(e) {
    message(sprintf("Worker failed: %s", e$message))

    # Try to upload error result
    tryCatch({
      error_result <- list(
        error = TRUE,
        message = e$message,
        traceback = capture.output(traceback())
      )

      result_key <- sprintf("results/%s/%s.qs", cluster_id, task_id)
      result_file <- tempfile(fileext = ".qs")

      qs::qsave(error_result, result_file)
      upload_to_s3(bucket, result_key, result_file)
      unlink(result_file)
    }, error = function(e2) {
      message(sprintf("Failed to upload error result: %s", e2$message))
    })

    quit(status = 1)
  })
}

# Helper functions

download_from_s3 <- function(bucket, key, dest_file) {
  cmd <- sprintf(
    "aws s3 cp s3://%s/%s %s --region %s",
    bucket, key, dest_file, Sys.getenv("AWS_REGION", "us-east-1")
  )

  status <- system(cmd)

  if (status != 0) {
    stop(sprintf("Failed to download from S3: %s/%s", bucket, key))
  }

  invisible(NULL)
}

upload_to_s3 <- function(bucket, key, source_file) {
  cmd <- sprintf(
    "aws s3 cp %s s3://%s/%s --region %s",
    source_file, bucket, key, Sys.getenv("AWS_REGION", "us-east-1")
  )

  status <- system(cmd)

  if (status != 0) {
    stop(sprintf("Failed to upload to S3: %s/%s", bucket, key))
  }

  invisible(NULL)
}

# Run main
main()
