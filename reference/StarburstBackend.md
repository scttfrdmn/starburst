# Starburst Future Backend

A future backend for running parallel R workloads on AWS ECS

## Usage

``` r
StarburstBackend(
  workers = 10,
  cpu = 4,
  memory = "8GB",
  region = NULL,
  timeout = 3600,
  launch_type = "EC2",
  instance_type = "c6a.large",
  use_spot = FALSE,
  warm_pool_timeout = 3600,
  ...
)
```

## Arguments

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

- launch_type:

  "EC2" or "FARGATE" (default: "EC2")

- instance_type:

  EC2 instance type (e.g., "c6a.large")

- use_spot:

  Use spot instances (default: FALSE)

- warm_pool_timeout:

  Pool timeout in seconds (default: 3600)

- ...:

  Additional arguments

## Value

A StarburstBackend object
