# Retry S3 operations

Specialized wrapper for S3 operations with S3-specific retry patterns

## Usage

``` r
with_s3_retry(expr, max_attempts = 3, operation_name = "S3 operation")
```

## Arguments

- expr:

  Expression to evaluate (AWS API call)

- max_attempts:

  Maximum retry attempts (default: 3)

- operation_name:

  Optional name for logging (default: "AWS operation")
