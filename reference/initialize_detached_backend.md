# Initialize backend for detached mode

Creates a backend for detached sessions without modifying the future
plan

## Usage

``` r
initialize_detached_backend(
  session_id,
  workers = 10,
  cpu = 4,
  memory = "8GB",
  region = NULL,
  timeout = 3600,
  absolute_timeout = 86400,
  launch_type = "EC2",
  instance_type = "c7g.xlarge",
  use_spot = TRUE,
  warm_pool_timeout = 3600
)
```

## Arguments

- session_id:

  Unique session identifier

- workers:

  Number of workers

- cpu:

  vCPUs per worker

- memory:

  Memory per worker (GB notation like "8GB")

- region:

  AWS region

- timeout:

  Task timeout in seconds

- absolute_timeout:

  Maximum session lifetime in seconds

- launch_type:

  "FARGATE" or "EC2"

- instance_type:

  EC2 instance type (for EC2 launch type)

- use_spot:

  Use spot instances

- warm_pool_timeout:

  Warm pool timeout for EC2

## Value

Backend environment
