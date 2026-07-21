
<!-- README.md is generated from README.Rmd. Please edit that file -->

# staRburst <img src="man/figures/logo.png" align="right" height="200" alt="staRburst logo" />

<!-- badges: start -->

[![CRAN
status](https://www.r-pkg.org/badges/version/starburst)](https://cran.r-project.org/package=starburst)
[![R-CMD-check](https://github.com/scttfrdmn/starburst/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/scttfrdmn/starburst/actions/workflows/R-CMD-check.yaml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/license/apache-2-0)
<!-- badges: end -->

> Seamless AWS cloud bursting for parallel R workloads

staRburst lets you run parallel R code on AWS with zero infrastructure
management. Scale from your laptop to 100+ cloud workers with a single
function call. Supports both EC2 (recommended for performance and cost)
and Fargate (serverless) backends.

## Features

- **Simple Setup**: One-time configuration (~2 minutes), then seamless
  operation
- **Simple API**: Direct `starburst_map()` function - no new concepts to
  learn
- **Flexible Backends**: EC2 (recommended - faster, cheaper, spot
  support) and Fargate (serverless)
- **Detached Sessions**: Submit long-running jobs and detach - retrieve
  results anytime
- **Automatic Environment Sync**: Your packages and dependencies
  automatically available on workers
- **Smart Quota Management**: Automatically handles AWS quota limits
  with wave execution
- **Cost Transparent**: See estimated and actual costs for every run
- **Auto Cleanup**: Workers shut down automatically when done

## Installation

> **Note on versions.** This documentation describes the **development
> version, 0.3.9**. The current CRAN release is **0.3.8**, which does
> **not** include some APIs documented here (notably backend arguments —
> `launch_type`/`instance_type`/ `use_spot` — on `starburst_map()` and
> `starburst_cluster()`). To use the APIs as documented, install from
> GitHub.

Development version (0.3.9 — matches this documentation):

``` r
remotes::install_github("scttfrdmn/starburst")
```

Latest CRAN release (0.3.8):

``` r
install.packages("starburst")
```

## Quick Start

``` r
library(starburst)

# One-time setup (~2 min to provision; first run also builds the worker image,
# +5-10 min once)
starburst_setup()

# Run parallel computation on AWS (each task should be real work — seconds+ —
# so it's worth shipping; batch tiny items first). Console output is illustrative:
results <- starburst_map(
  inputs,                       # e.g. a list of scenarios / parameter sets
  function(x) expensive_computation(x),
  workers = 50
)
#> [Starting] Starting starburst cluster with 50 workers
#> [Status] Processing 200 items with 50 workers
#> [Starting] Submitting 200 tasks...
#> [Wait] Progress: 200/200
#> [OK] Completed
#> [Cost] Estimated cost: (printed per run)
```

## Example: Monte Carlo Simulation

``` r
library(starburst)

# Define simulation
simulate_portfolio <- function(seed) {
  set.seed(seed)
  returns <- rnorm(252, mean = 0.0003, sd = 0.02)
  prices <- cumprod(1 + returns)

  list(
    final_value = prices[252],
    sharpe_ratio = mean(returns) / sd(returns) * sqrt(252)
  )
}

# Each simulation is tiny (sub-millisecond), so BATCH them: 100 tasks of 100
# simulations each, not 10,000 one-simulation tasks. (Thousands of tiny tasks are
# an anti-pattern — see the "Workload Shapes" guide for measured numbers.)
batches <- split(1:10000, ceiling(seq_along(1:10000) / 100))
results <- starburst_map(
  batches,
  function(seeds) lapply(seeds, simulate_portfolio),
  workers = 50
)
results <- unlist(results, recursive = FALSE)  # flatten to 10,000 results

# Extract results
final_values <- sapply(results, function(x) x$final_value)
sharpe_ratios <- sapply(results, function(x) x$sharpe_ratio)

# Summary
mean(final_values)    # Average portfolio outcome
quantile(final_values, c(0.05, 0.95))  # Risk range
```

> For real, measured performance (when the cloud wins, when it loses,
> and how to size tasks/workers), see the [Workload
> Shapes](https://starburst.ing/articles/workload-shapes.html) and
> [Performance](https://starburst.ing/articles/performance.html) guides.

## Advanced Usage

### Reuse Cluster for Multiple Operations

``` r
# Create cluster once
cluster <- starburst_cluster(workers = 50, cpu = 4, memory = "8GB")

# Run multiple analyses
results1 <- cluster$map(dataset1, analysis_function)
results2 <- cluster$map(dataset2, processing_function)
results3 <- cluster$map(dataset3, modeling_function)

# All use the same Docker image and configuration
```

### Custom Worker Configuration

``` r
# For memory-intensive workloads
results <- starburst_map(
  large_datasets,
  memory_intensive_function,
  workers = 20,
  cpu = 8,
  memory = "16GB"
)

# For CPU-intensive workloads
results <- starburst_map(
  cpu_tasks,
  cpu_intensive_function,
  workers = 50,
  cpu = 4,
  memory = "8GB"
)
```

### Detached Sessions

Run long jobs and disconnect - results persist in S3:

``` r
# Start a detached session (EC2 + Spot by default)
session <- starburst_session(workers = 50)

# Fan work out by submitting one task per input
task_ids <- lapply(inputs, function(input) {
  session$submit(quote(expensive_function(input)),
                 globals = list(input = input))
})
session_id <- session$session_id

# Disconnect - job continues running.
# Later (hours/days), reconnect from a fresh R session:
session <- starburst_session_attach(session_id)
status  <- session$status()          # Check progress
results <- session$collect(wait = TRUE)  # Collect results (in submission order)

# Cleanup when done
session$cleanup()
```

## How It Works

1.  **Environment Snapshot**: Captures your R packages using renv
2.  **Container Build**: Creates a Docker image with your environment,
    cached in ECR
3.  **Task Creation**: Creates one task per element of your input (`.x`)
    — there is no automatic chunking; batch small items yourself if
    per-task overhead matters
4.  **Worker Launch**: Starts EC2 workers by default (Spot-enabled), or
    Fargate tasks if you pass `launch_type = "FARGATE"`; falls back to
    waves if quota-limited
5.  **Data Transfer**: Serializes each task’s function, inputs, and
    globals to S3 using the fast `qs2` format
6.  **Execution**: Each worker pulls a task from S3, runs your function,
    pushes the result back to S3
7.  **Result Collection**: Downloads and combines results in the
    original order
8.  **Cleanup**: Automatically shuts workers down (warm-pool timeout
    configurable)

## Cost Management

``` r
# Set an hourly cost ceiling (USD/hour)
starburst_config(
  max_hourly_cost = 10,       # Jobs estimated over $10/hour won't start
  cost_alert_threshold = 5     # Warn at $5/hour
)

# Costs shown transparently
results <- starburst_map(data, fn, workers = 100)
#> [Starting] Starting starburst cluster with 100 workers
#> [OK] Completed in 1380.0 seconds
#> [Cost] Estimated cost: $1.34
```

## Quota Management

When using the Fargate backend, staRburst automatically handles AWS
Fargate vCPU quota limits (EC2 uses your standard On-Demand/Spot
limits):

``` r
results <- starburst_map(data, fn, workers = 100, cpu = 4, launch_type = "FARGATE")
#> [!] Requested 100 workers (400 vCPUs) but quota allows 25 workers (100 vCPUs)
#> [!] Using 25 workers instead
```

Your work still completes, just with fewer workers. You can request
quota increases through AWS Service Quotas.

## API Reference

### Main Functions

- `starburst_map(.x, .f, workers, ...)` - Parallel map over data
- `starburst_cluster(workers, cpu, memory)` - Create reusable cluster
- `starburst_setup()` - Initial AWS configuration
- `starburst_config(...)` - Update configuration
- `starburst_status()` - Check cluster status

### Configuration Options

``` r
starburst_config(
  max_hourly_cost = 10,        # USD/hour rate ceiling
  cost_alert_threshold = 5     # USD/hour warning
)
```

## Documentation

Full documentation available at
**[starburst.ing](https://starburst.ing)**

- [Getting Started
  Guide](https://starburst.ing/articles/getting-started.html)
- [Detached
  Sessions](https://starburst.ing/articles/detached-sessions.html)
- [Example Vignettes](https://starburst.ing/articles/)
- [API Reference](https://starburst.ing/reference/)
- [Security Guide](https://starburst.ing/articles/security.html)
- [Troubleshooting](https://starburst.ing/articles/troubleshooting.html)

## Comparison

| Feature                   | staRburst | RStudio Server on EC2 | Coiled (Python) |
|---------------------------|-----------|-----------------------|-----------------|
| Setup time                | 2 minutes | 30+ minutes           | 5 minutes       |
| Infrastructure management | Zero      | Manual                | Zero            |
| Learning curve            | Minimal   | Medium                | Medium          |
| Auto scaling              | Yes       | No                    | Yes             |
| Cost optimization         | Automatic | Manual                | Automatic       |
| R-native                  | Yes       | Yes                   | No (Python)     |

## Requirements

- R \>= 4.0
- AWS account with:
  - AWS CLI configured or `AWS_PROFILE` set
  - IAM permissions for ECS, ECR, S3, VPC
  - Two IAM roles (created during setup):
    - `starburstECSExecutionRole` - for ECS/ECR access
    - `starburstECSTaskRole` - for S3 access

For detailed setup instructions, see the [Getting
Started](https://starburst.ing/articles/getting-started.html) guide.

## Roadmap

### v0.3.9 (development — this documentation)

- ✅ Backend arguments (`launch_type`/`instance_type`/`use_spot`) on
  `starburst_map()`/`starburst_cluster()`
- ✅ One-step EC2 setup (`starburst_setup()` provisions the default
  capacity provider)
- ✅ Measured performance/workload-shape guides

### v0.3.8 (current CRAN release)

- ✅ Direct API (`starburst_map`, `starburst_cluster`)
- ✅ EC2 backend (default, with spot instances) + Fargate (serverless
  alternative)
- ✅ Detached session mode for long-running jobs
- ✅ Automatic environment management
- ✅ Cost tracking and quota handling
- ✅ Full `future` backend integration (`future.apply`, `furrr`,
  `targets`)
- ✅ Security hardening (safe command execution, worker limits)
- ✅ Published on CRAN (0 errors, 0 warnings, 0 notes)

### Future Releases

- [ ] Performance optimizations
- [ ] Enhanced error recovery
- [ ] Interactive progress monitoring
- [ ] Multi-region support

## Contributing

Contributions welcome! See the [GitHub
repository](https://github.com/scttfrdmn/starburst) for contribution
guidelines.

## License

Apache License 2.0 - see
[LICENSE](https://github.com/scttfrdmn/starburst/blob/main/LICENSE)

Copyright 2026 Scott Friedman

## Citation

``` bibtex
@software{starburst,
  title = {staRburst: Seamless AWS Cloud Bursting for R},
  author = {Scott Friedman},
  year = {2026},
  version = {0.3.9},
  url = {https://starburst.ing},
  license = {Apache-2.0}
}
```

## Credits

Built using the [paws](https://github.com/paws-r/paws) AWS SDK for R.

Container management with [renv](https://rstudio.github.io/renv/) and
[rocker](https://rocker-project.org/).

Inspired by [Coiled](https://coiled.io/) for Python/Dask.
