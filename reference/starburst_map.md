# Map Function Over Data Using AWS Fargate

Parallel map function that executes on AWS Fargate using the Future
backend

## Usage

``` r
starburst_map(
  .x,
  .f,
  workers = 10,
  cpu = 4,
  memory = "8GB",
  platform = "X86_64",
  region = NULL,
  timeout = 3600,
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

- platform:

  CPU architecture (X86_64 or ARM64)

- region:

  AWS region

- timeout:

  Maximum runtime in seconds per task

- .progress:

  Show progress bar (default: TRUE)

- ...:

  Additional arguments passed to .f

## Value

A list of results, one per element of .x

## Examples

``` r
if (FALSE) { # \dontrun{
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
} # }
```
