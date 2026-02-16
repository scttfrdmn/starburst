# Retry ECR operations

Specialized wrapper for ECR operations with ECR-specific retry patterns

## Usage

``` r
with_ecr_retry(expr, max_attempts = 3, operation_name = "ECR operation")
```

## Arguments

- expr:

  Expression to evaluate (AWS API call)

- max_attempts:

  Maximum retry attempts (default: 3)

- operation_name:

  Optional name for logging (default: "AWS operation")
