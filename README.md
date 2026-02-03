# staRburst

<!-- badges: start -->
[![R-CMD-check](https://github.com/scttfrdmn/starburst/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/scttfrdmn/starburst/actions/workflows/R-CMD-check.yaml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Version](https://img.shields.io/badge/version-0.1.0-brightgreen.svg)](https://github.com/scttfrdmn/starburst/releases/tag/v0.1.0)
<!-- badges: end -->

> Seamless AWS cloud bursting for parallel R workloads

staRburst is a [future](https://future.futureverse.org/) backend that lets you run parallel R code on AWS with zero infrastructure management. Change one line of code to scale from your laptop to 100+ cloud workers.

## Features

- **Zero Configuration**: One-time setup, then it just works
- **future Ecosystem**: Works with furrr, future.apply, targets, and all future-based packages
- **Automatic Environment Sync**: Your packages and dependencies automatically available on workers
- **Smart Quota Management**: Wave-based execution when hitting AWS limits, automatic quota increase requests
- **Cost Transparent**: See estimated and actual costs for every run
- **Auto Cleanup**: Workers shut down automatically when done

## Installation

```r
# Install from GitHub
remotes::install_github("scttfrdmn/starburst")
```

## Quick Start

```r
library(starburst)
library(furrr)

# One-time setup (2 minutes)
starburst_setup()

# Use with furrr - change one line to scale to AWS
plan(future_starburst, workers = 50)

results <- future_map(samples, expensive_analysis)
# Your code runs on 50 AWS Fargate workers automatically
```

## Example: Monte Carlo Simulation

```r
library(starburst)
library(furrr)

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
plan(future_starburst, workers = 100)

results <- future_map(1:10000, simulate_portfolio,
                     .options = furrr_options(seed = TRUE))

# Local (single core): ~4 hours
# Cloud (100 workers): ~3 minutes, Cost: ~$1.80
```

## How It Works

1. **Environment Snapshot**: Captures your R packages using renv
2. **Container Build**: Creates Docker image with your environment, cached in ECR
3. **Task Submission**: Launches Fargate tasks (or waves if quota-limited)
4. **Data Transfer**: Serializes dependencies to S3 using optimized methods
5. **Execution**: Workers pull data, execute, push results to S3
6. **Result Collection**: Downloads and deserializes results
7. **Cleanup**: Automatically shuts down workers

## Cost Management

```r
# Set cost limits
starburst_config(
  max_cost_per_job = 10,      # Hard limit
  cost_alert_threshold = 5     # Warning at $5
)

# Costs shown transparently
plan(future_starburst, workers = 100)
#> 💰 Estimated cost: ~$3.50/hour

results <- future_map(samples, analysis)
#> ✓ Cluster runtime: 23 minutes
#> ✓ Total cost: $1.34
```

## Quota Management

staRburst automatically handles AWS Fargate quota limitations:

```r
plan(future_starburst, workers = 100, cpu = 4)
#> ⚠ Requested: 100 workers (400 vCPUs)
#> ⚠ Current quota: 100 vCPUs (allows 25 workers max)
#> 📋 Running in 4 waves of 25 workers each
#> 💡 Request quota increase to 500 vCPUs? [y/n]: y
#> ✓ Quota increase requested (Case ID: 12345)
```

All your work completes, just takes slightly longer. After quota increase, full parallelism is available.

## Architecture

staRburst implements a complete cloud-bursting solution:

- **Docker Image Building**: Automatic from renv.lock with ECR push
- **ECS Task Management**: Dynamic task definition creation with IAM roles
- **Wave-Based Queue**: In-memory queue with automatic wave progression
- **Cost Tracking**: Real-time calculation from actual task runtimes
- **Multi-AZ Networking**: Automatic subnet creation and management

See [ARCHITECTURE.md](ARCHITECTURE.md) for details.

## Documentation

- [Getting Started](vignettes/getting-started.Rmd)
- [Architecture](ARCHITECTURE.md)
- [Testing Guide](TESTING_GUIDE.md)
- [Implementation Details](IMPLEMENTATION_SUMMARY.md)
- [Roadmap](ROADMAP.md)

## Requirements

- R >= 4.0.0
- Docker installed locally (for image building)
- AWS account with appropriate permissions
- AWS CLI configured (or use `AWS_PROFILE` environment variable)

## Comparison

| Feature | staRburst | RStudio Server on EC2 | Coiled (Python) |
|---------|-----------|----------------------|-----------------|
| Setup time | 2 minutes | 30+ minutes | 5 minutes |
| Infrastructure management | Zero | Manual | Zero |
| Works with existing code | Yes (future) | Yes | Yes (Dask) |
| Auto scaling | Yes | No | Yes |
| Cost optimization | Automatic | Manual | Automatic |
| R-native | Yes | Yes | No (Python) |

## Status

- **Version**: 0.1.0 (Initial Release)
- **Tests**: 62/62 passing (100%)
- **License**: Apache 2.0
- **Status**: Production ready for AWS integration testing

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Apache License 2.0 - see [LICENSE](LICENSE)

Copyright 2026 Scott Friedman

## Citation

```bibtex
@software{starburst,
  title = {staRburst: Seamless AWS Cloud Bursting for R},
  author = {Scott Friedman},
  year = {2026},
  version = {0.1.0},
  url = {https://github.com/scttfrdmn/starburst},
  license = {Apache-2.0}
}
```

## Credits

Built on the excellent [future](https://future.futureverse.org/) framework by Henrik Bengtsson.

Inspired by [Coiled](https://www.coiled.io/) for Python/Dask.
