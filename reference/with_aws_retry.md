# Retry AWS operations with exponential backoff

Wraps AWS API calls with automatic retry logic for transient failures.
Uses exponential backoff with jitter to avoid thundering herd.

## Usage

``` r
with_aws_retry(
  expr,
  max_attempts = 3,
  base_delay = 1,
  max_delay = 60,
  retryable_errors = c("Throttling", "ThrottlingException", "RequestTimeout",
    "ServiceUnavailable", "InternalError", "InternalServerError", "TooManyRequests",
    "RequestLimitExceeded", "5\\d{2}"),
  operation_name = "AWS operation"
)
```

## Arguments

- expr:

  Expression to evaluate (AWS API call)

- max_attempts:

  Maximum retry attempts (default: 3)

- base_delay:

  Initial delay in seconds (default: 1)

- max_delay:

  Maximum delay in seconds (default: 60)

- retryable_errors:

  Regex patterns for retryable error messages

- operation_name:

  Optional name for logging (default: "AWS operation")

## Value

Result of expression

## Examples

``` r
if (FALSE) { # \dontrun{
# Retry S3 upload
with_aws_retry({
  s3$put_object(Bucket = "bucket", Key = "key", Body = "data")
})

# Retry with custom parameters
with_aws_retry(
  {
    ecs$run_task(...)
  },
  max_attempts = 5,
  operation_name = "ECS RunTask"
)
} # }
```
