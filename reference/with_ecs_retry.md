# Retry ECS operations

Specialized wrapper for ECS operations with ECS-specific retry patterns

## Usage

``` r
with_ecs_retry(expr, max_attempts = 3, operation_name = "ECS operation")
```

## Arguments

- expr:

  Expression to evaluate (AWS API call)

- max_attempts:

  Maximum retry attempts (default: 3)

- operation_name:

  Optional name for logging (default: "AWS operation")
