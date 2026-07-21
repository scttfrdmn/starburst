# Create a Starburst Cluster

Creates a cluster object for managing AWS workers (EC2 by default, or
Fargate) using the staRburst Future backend.

## Usage

``` r
starburst_cluster(
  workers = 10,
  cpu = 4,
  memory = "8GB",
  region = NULL,
  timeout = 3600,
  launch_type = "EC2",
  instance_type = "c7g.xlarge",
  use_spot = TRUE
)
```

## Arguments

- workers:

  Number of parallel workers

- cpu:

  CPU units per worker

- memory:

  Memory per worker

- region:

  AWS region

- timeout:

  Maximum runtime in seconds

- launch_type:

  Compute backend: "EC2" (default) or "FARGATE"

- instance_type:

  EC2 instance type when `launch_type = "EC2"` (default: "c7g.xlarge").
  Worker CPU architecture follows the instance type (Graviton `*g.*` =
  ARM64, Intel/AMD = x86_64); there is no separate platform argument.

- use_spot:

  Use EC2 Spot instances for cost savings (default: TRUE)

## Value

A starburst_cluster object

## Examples

``` r
# \donttest{
if (starburst_is_configured()) {
  cluster <- starburst_cluster(workers = 20)
  results <- cluster$map(data, function(x) x * 2)

  # Fargate backend instead of the EC2 default
  fg <- starburst_cluster(workers = 20, launch_type = "FARGATE")
}
# }
```
