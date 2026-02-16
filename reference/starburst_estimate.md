# Estimate Cloud Performance and Cost

Runs a small sample of tasks locally to estimate cloud execution time
and cost. Provides informed prediction before spending money on cloud
execution.

## Usage

``` r
starburst_estimate(
  .x,
  .f,
  workers = 10,
  cpu = 2,
  memory = "8GB",
  platform = "X86_64",
  sample_size = 10,
  region = NULL,
  ...
)
```

## Arguments

- .x:

  A vector or list to iterate over

- .f:

  A function to apply to each element

- workers:

  Number of parallel workers to estimate for

- cpu:

  CPU units per worker (1, 2, 4, 8, or 16)

- memory:

  Memory per worker (e.g., "8GB")

- platform:

  CPU architecture: "X86_64" (default) or "ARM64" (Graviton3)

- sample_size:

  Number of items to run locally for estimation (default: 10)

- region:

  AWS region

- ...:

  Additional arguments passed to .f

## Value

Invisible list with estimates, prints summary to console

## Examples

``` r
if (FALSE) { # \dontrun{
# Estimate before running
starburst_estimate(1:1000, expensive_function, workers = 50)

# Then decide whether to proceed
results <- starburst_map(1:1000, expensive_function, workers = 50)
} # }
```
