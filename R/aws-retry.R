#' AWS Retry Logic
#'
#' Centralized retry logic for AWS operations with exponential backoff
#'
#' @name aws-retry
#' @keywords internal
NULL

#' Retry AWS operations with exponential backoff
#'
#' Wraps AWS API calls with automatic retry logic for transient failures.
#' Uses exponential backoff with jitter to avoid thundering herd.
#'
#' @param expr Expression to evaluate (AWS API call)
#' @param max_attempts Maximum retry attempts (default: 3)
#' @param base_delay Initial delay in seconds (default: 1)
#' @param max_delay Maximum delay in seconds (default: 60)
#' @param retryable_errors Regex patterns for retryable error messages
#' @param operation_name Optional name for logging (default: "AWS operation")
#'
#' @return Result of expression
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' # Retry S3 upload
#' with_aws_retry({
#'   s3$put_object(Bucket = "bucket", Key = "key", Body = "data")
#' })
#'
#' # Retry with custom parameters
#' with_aws_retry(
#'   {
#'     ecs$run_task(...)
#'   },
#'   max_attempts = 5,
#'   operation_name = "ECS RunTask"
#' )
#' }
with_aws_retry <- function(expr,
                          max_attempts = 3,
                          base_delay = 1,
                          max_delay = 60,
                          retryable_errors = c(
                            "Throttling",
                            "ThrottlingException",
                            "RequestTimeout",
                            "ServiceUnavailable",
                            "InternalError",
                            "InternalServerError",
                            "TooManyRequests",
                            "RequestLimitExceeded",
                            "5\\d{2}"  # 5xx HTTP errors
                          ),
                          operation_name = "AWS operation") {

  last_error <- NULL

  for (attempt in seq_len(max_attempts)) {
    tryCatch({
      # Execute expression
      return(force(expr))  # Success - return immediately

    }, error = function(e) {
      last_error <<- e

      # Check if error is retryable
      is_retryable <- any(vapply(retryable_errors, function(pattern) {
        grepl(pattern, e$message, ignore.case = TRUE)
      }, FUN.VALUE = logical(1)))

      if (!is_retryable) {
        # Not retryable - fail immediately
        stop(e)
      }

      if (attempt >= max_attempts) {
        # Exhausted retries - fail
        stop(e)
      }

      # Calculate exponential backoff with jitter
      # delay = base_delay * (2 ^ (attempt - 1)) + random jitter
      exponential_delay <- base_delay * (2 ^ (attempt - 1))
      capped_delay <- min(exponential_delay, max_delay)
      jitter <- runif(1, 0, capped_delay * 0.1)  # 10% jitter
      total_delay <- capped_delay + jitter

      cat_warn(sprintf(
        "[WARNING] %s failed (attempt %d/%d): %s\n  Retrying in %.1fs...\n",
        operation_name, attempt, max_attempts,
        substring(e$message, 1, 100),  # Truncate long messages
        total_delay
      ))

      Sys.sleep(total_delay)

      NULL  # Continue to next iteration
    })
  }

  # Should never reach here, but if we do, throw last error
  stop(last_error)
}

#' Retry S3 operations
#'
#' Specialized wrapper for S3 operations with S3-specific retry patterns
#'
#' @inheritParams with_aws_retry
#' @keywords internal
with_s3_retry <- function(expr, max_attempts = 3, operation_name = "S3 operation") {
  with_aws_retry(
    expr,
    max_attempts = max_attempts,
    retryable_errors = c(
      "Throttling",
      "RequestTimeout",
      "ServiceUnavailable",
      "SlowDown",
      "5\\d{2}"
    ),
    operation_name = operation_name
  )
}

#' Retry ECS operations
#'
#' Specialized wrapper for ECS operations with ECS-specific retry patterns
#'
#' @inheritParams with_aws_retry
#' @keywords internal
with_ecs_retry <- function(expr, max_attempts = 3, operation_name = "ECS operation") {
  with_aws_retry(
    expr,
    max_attempts = max_attempts,
    retryable_errors = c(
      "Throttling",
      "RequestTimeout",
      "ServiceUnavailable",
      "ServerException",
      "ClusterNotFoundException",  # Sometimes transient during cluster creation
      "5\\d{2}"
    ),
    operation_name = operation_name
  )
}

#' Retry ECR operations
#'
#' Specialized wrapper for ECR operations with ECR-specific retry patterns
#'
#' @inheritParams with_aws_retry
#' @keywords internal
with_ecr_retry <- function(expr, max_attempts = 3, operation_name = "ECR operation") {
  with_aws_retry(
    expr,
    max_attempts = max_attempts,
    retryable_errors = c(
      "Throttling",
      "TooManyRequests",
      "RequestTimeout",
      "ServiceUnavailable",
      "5\\d{2}"
    ),
    operation_name = operation_name
  )
}
