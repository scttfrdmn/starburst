
<!-- README.md is generated from README.Rmd. Please edit that file -->

# staRburst <img src="man/figures/logo.png" align="right" height="200" alt="staRburst logo" />

<!-- badges: start -->

[![R-CMD-check](https://github.com/scttfrdmn/starburst/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/scttfrdmn/starburst/actions/workflows/R-CMD-check.yaml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/license/apache-2-0)
[![Version](https://img.shields.io/badge/version-0.3.6-brightgreen.svg)](https://github.com/scttfrdmn/starburst/releases/tag/v0.3.6)
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

**CRAN submission in progress for v0.3.6** (expected within 2-4 weeks).

Once available:

``` r
install.packages("starburst")
```

Development version from GitHub:

``` r
remotes::install_github("scttfrdmn/starburst")
```

## Quick Start

``` r
library(starburst)

# One-time setup (2 minutes)
starburst_setup()

# Run parallel computation on AWS
results <- starburst_map(
  1:1000,
  function(x) expensive_computation(x),
  workers = 50
)
#> 🚀 Starting starburst cluster with 50 workers
#> 💰 Estimated cost: ~$2.80/hour
#> 📊 Processing 1000 items with 50 workers
#> 📦 Created 50 chunks (avg 20 items per chunk)
#> 🚀 Submitting tasks...
#> ✓ Submitted 50 tasks
#> ⏳ Progress: 50/50 tasks (3.2 minutes elapsed)
#>
#> ✓ Completed in 3.2 minutes
#> 💰 Estimated cost: $0.15
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

# Run 10,000 simulations on 100 AWS workers
results <- starburst_map(
  1:10000,
  simulate_portfolio,
  workers = 100
)
#> 🚀 Starting starburst cluster with 100 workers
#> 💰 Estimated cost: ~$5.60/hour
#> 📊 Processing 10000 items with 100 workers
#> ⏳ Progress: 100/100 tasks (3.1 minutes elapsed)
#>
#> ✓ Completed in 3.1 minutes
#> 💰 Estimated cost: $0.29

# Extract results
final_values <- sapply(results, function(x) x$final_value)
sharpe_ratios <- sapply(results, function(x) x$sharpe_ratio)

# Summary
mean(final_values)    # Average portfolio outcome
quantile(final_values, c(0.05, 0.95))  # Risk range

# Comparison:
# Local (single core): ~4 hours
# Cloud (100 workers): 3 minutes, $0.29
```

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
# Start detached session
session <- starburst_session(workers = 50, detached = TRUE)

# Submit work and get session ID
session$submit(quote({
  results <- starburst_map(huge_dataset, expensive_function)
  saveRDS(results, "results.rds")
}))
session_id <- session$session_id

# Disconnect - job continues running
# Later (hours/days), reconnect:
session <- starburst_session_attach(session_id)
status <- session$status()  # Check progress
results <- session$collect()  # Get results

# Cleanup when done
session$cleanup(force = TRUE)
```

## How It Works

1.  **Environment Snapshot**: Captures your R packages using renv
2.  **Container Build**: Creates Docker image with your environment,
    cached in ECR
3.  **Task Distribution**: Splits data into chunks across workers
4.  **Task Submission**: Launches Fargate tasks (or sequential batches
    if quota-limited)
5.  **Data Transfer**: Serializes task data to S3 using fast qs format
6.  **Execution**: Workers pull data, execute function on chunk items,
    push results
7.  **Result Collection**: Downloads and combines results in correct
    order
8.  **Cleanup**: Automatically shuts down workers

## Cost Management

``` r
# Set cost limits
starburst_config(
  max_cost_per_job = 10,      # Hard limit
  cost_alert_threshold = 5     # Warning at $5
)

# Costs shown transparently
results <- starburst_map(data, fn, workers = 100)
#> 💰 Estimated cost: ~$3.50/hour
#> ✓ Completed in 23 minutes
#> 💰 Estimated cost: $1.34
```

## Quota Management

staRburst automatically handles AWS Fargate quota limitations:

``` r
results <- starburst_map(data, fn, workers = 100, cpu = 4)
#> ⚠ Requested 100 workers (400 vCPUs) but quota allows 25 workers (100 vCPUs)
#> ⚠ Using 25 workers instead
#> 💰 Estimated cost: ~$1.40/hour
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
  region = "us-east-1",
  max_cost_per_job = 10,
  cost_alert_threshold = 5
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

### v0.3.6 (Current - CRAN Submission)

- ✅ Direct API (`starburst_map`, `starburst_cluster`)
- ✅ AWS Fargate integration
- ✅ EC2 backend support with spot instances
- ✅ Detached session mode for long-running jobs
- ✅ Automatic environment management
- ✅ Cost tracking and quota handling
- ✅ Full `future` backend integration
- ✅ Support for `future.apply`, `furrr`, `targets`
- ✅ Comprehensive AWS integration testing
- ✅ CRAN-ready (0 errors, 0 notes)

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

Apache License 2.0 - see [LICENSE](LICENSE)

Copyright 2026 Scott Friedman

## Citation

``` bibtex
@software{starburst,
  title = {staRburst: Seamless AWS Cloud Bursting for R},
  author = {Scott Friedman},
  year = {2026},
  version = {0.3.6},
  url = {https://starburst.ing},
  license = {Apache-2.0}
}
```

## Credits

Built using the [paws](https://github.com/paws-r/paws) AWS SDK for R.

Container management with [renv](https://rstudio.github.io/renv/) and
[rocker](https://rocker-project.org/).

Inspired by [Coiled](https://coiled.io/) for Python/Dask.
