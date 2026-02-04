#!/usr/bin/env Rscript

# staRburst Worker Script for Future Backend
# This script runs inside Fargate containers to execute Future tasks

main <- function() {
  # Get configuration from environment variables
  task_id <- Sys.getenv("TASK_ID")
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

    # Create S3 client
    s3 <- paws.storage::s3(config = list(region = region))

    # Download task from S3
    task_key <- sprintf("tasks/%s.qs", task_id)
    task_file <- tempfile(fileext = ".qs")

    message(sprintf("Downloading task from s3://%s/%s", bucket, task_key))

    s3$download_file(
      Bucket = bucket,
      Key = task_key,
      Filename = task_file
    )

    # Load task data
    task_data <- qs::qread(task_file)
    unlink(task_file)

    message("Task loaded, executing...")

    # Set up environment with globals
    exec_env <- new.env(parent = globalenv())

    # Load globals into environment
    if (!is.null(task_data$globals) && length(task_data$globals) > 0) {
      for (name in names(task_data$globals)) {
        assign(name, task_data$globals[[name]], envir = exec_env)
      }
    }

    # Load packages
    if (!is.null(task_data$packages)) {
      for (pkg in task_data$packages) {
        library(pkg, character.only = TRUE)
      }
    }

    # Evaluate expression in the environment
    result_value <- eval(task_data$expr, envir = exec_env)

    message("Task completed, uploading result...")

    # Create result object
    result <- list(
      error = FALSE,
      value = result_value,
      stdout = "",
      conditions = list()
    )

    # Upload result to S3
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
    message("Worker completed successfully")

    quit(status = 0)

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
        traceback = capture.output(traceback()),
        value = NULL,
        stdout = "",
        conditions = list(simpleError(e$message))
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

# Run main function
main()
