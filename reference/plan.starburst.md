# staRburst Future Backend

A future backend for running parallel R workloads on AWS (EC2 or
Fargate)

## Usage

``` r
# S3 method for class 'starburst'
plan(
  strategy,
  workers = 10,
  cpu = 4,
  memory = "8GB",
  region = NULL,
  timeout = 3600,
  auto_quota_request = interactive(),
  launch_type = "EC2",
  instance_type = "c7g.xlarge",
  use_spot = TRUE,
  warm_pool_timeout = 3600,
  detached = FALSE,
  ...
)
```

## Arguments

- strategy:

  The starburst strategy marker (ignored, for S3 dispatch)

- workers:

  Number of parallel workers

- cpu:

  vCPUs per worker (1, 2, 4, 8, or 16)

- memory:

  Memory per worker (supports GB notation, e.g., "8GB")

- region:

  AWS region (default: from config or "us-east-1")

- timeout:

  Maximum runtime in seconds (default: 3600)

- auto_quota_request:

  Automatically request quota increases (default: interactive())

- launch_type:

  Launch type: EC2 or FARGATE (default: EC2)

- instance_type:

  EC2 instance type when using EC2 launch type (default: c7g.xlarge)

- use_spot:

  Use EC2 Spot instances for cost savings (default: TRUE)

- warm_pool_timeout:

  Timeout for warm pool in seconds (default: 3600)

- detached:

  Use detached session mode (deprecated, use starburst_session instead)

- ...:

  Additional arguments passed to future backend

## Value

A future plan object

## Examples

``` r
if (FALSE) { # \dontrun{
library(furrr)
plan(starburst, workers = 50)
results <- future_map(1:1000, expensive_function)
} # }
```
