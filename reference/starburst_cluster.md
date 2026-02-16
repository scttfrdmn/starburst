# Create a Starburst Cluster

Creates a cluster object for managing AWS Fargate workers using Future
backend

## Usage

``` r
starburst_cluster(
  workers = 10,
  cpu = 4,
  memory = "8GB",
  platform = "X86_64",
  region = NULL,
  timeout = 3600
)
```

## Arguments

- workers:

  Number of parallel workers

- cpu:

  CPU units per worker

- memory:

  Memory per worker

- platform:

  CPU architecture (X86_64 or ARM64)

- region:

  AWS region

- timeout:

  Maximum runtime in seconds

## Value

A starburst_cluster object

## Examples

``` r
if (FALSE) { # \dontrun{
cluster <- starburst_cluster(workers = 20)
results <- cluster$map(data, function(x) x * 2)
} # }
```
