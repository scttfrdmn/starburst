# Map a Function Over Data on AWS Workers

Parallel map function that executes across AWS workers (EC2 by default,
or Fargate) using the staRburst Future backend.

## Usage

``` r
starburst_map(
  .x,
  .f,
  workers = 10,
  cpu = 4,
  memory = "8GB",
  region = NULL,
  timeout = 3600,
  launch_type = "EC2",
  instance_type = "c7g.xlarge",
  use_spot = TRUE,
  .progress = TRUE,
  ...
)
```

## Arguments

- .x:

  A vector or list to iterate over

- .f:

  A function to apply to each element

- workers:

  Number of parallel workers (default: 10)

- cpu:

  CPU units per worker (1, 2, 4, 8, or 16)

- memory:

  Memory per worker (e.g., 8GB)

- region:

  AWS region

- timeout:

  Maximum runtime in seconds per task

- launch_type:

  Compute backend: "EC2" (default) or "FARGATE"

- instance_type:

  EC2 instance type when `launch_type = "EC2"` (default: "c7g.xlarge").
  The worker CPU architecture follows the instance type — Graviton types
  (e.g. `c7g.*`) run ARM64, Intel/AMD types (e.g. `c7i.*`) run x86_64 —
  so there is no separate platform argument.

- use_spot:

  Use EC2 Spot instances for cost savings (default: TRUE)

- .progress:

  Show progress bar (default: TRUE)

- ...:

  Additional arguments passed to .f

## Value

A list of results, one per element of .x

## Examples

``` r
# \donttest{
if (starburst_is_configured()) {
  # Simple parallel computation
  results <- starburst_map(1:100, function(x) x^2, workers = 10)

  # With custom configuration
  results <- starburst_map(
    data_list,
    expensive_function,
    workers = 50,
    cpu = 4,
    memory = "8GB"
  )

  # Use the Fargate backend instead of the EC2 default
  results <- starburst_map(1:100, function(x) x^2,
                           workers = 10, launch_type = "FARGATE")
}
# }
```
