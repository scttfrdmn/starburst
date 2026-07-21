# staRburst Examples

This directory contains realistic examples demonstrating staRburst usage across different use cases.

## Examples

### 1. Monte Carlo Portfolio Simulation (`01-monte-carlo-portfolio.R`)
Simulates 10,000 portfolio scenarios to assess investment risk.
- **Use case**: Risk analysis, financial modeling
- **Characteristics**: CPU-intensive, embarrassingly parallel
- **Runtime**: ~30 seconds local (sequential), ~20 seconds with 100 workers

### 2. Bootstrap Confidence Intervals (`02-bootstrap-confidence-intervals.R`)
Calculates bootstrap confidence intervals for treatment effects.
- **Use case**: Statistical inference, A/B testing
- **Characteristics**: Moderate compute, many independent samples
- **Runtime**: ~25 seconds local, ~15 seconds with 50 workers

### 3. Parallel Data Processing (`03-parallel-data-processing.R`)
Processes 100 dataset chunks with feature engineering and modeling.
- **Use case**: ETL, batch data processing
- **Characteristics**: Data-intensive with moderate computation
- **Runtime**: ~40 seconds local, ~25 seconds with 50 workers

### 4. Hyperparameter Grid Search (`04-grid-search-tuning.R`)
Performs grid search with cross-validation for model tuning.
- **Use case**: Machine learning, model optimization
- **Characteristics**: CPU-intensive, many model fits
- **Runtime**: ~60 seconds local, ~30 seconds with 50 workers

## Running Examples

### Run Locally (Sequential)
```bash
# Run any example without staRburst
Rscript examples/01-monte-carlo-portfolio.R
```

### Run with staRburst on AWS
```bash
# Set environment variables
export USE_STARBURST=TRUE
export STARBURST_WORKERS=100  # Number of workers
export AWS_PROFILE=aws         # Your AWS profile

# Run example
Rscript examples/01-monte-carlo-portfolio.R
```

### Run All Examples
```bash
# Local baseline
./examples/run-all-examples.sh local

# AWS with staRburst
./examples/run-all-examples.sh aws 50  # 50 workers
```

## Using as Integration Tests

These examples double as integration tests:

```r
# In tests/testthat/test-integration-examples.R
test_that("Monte Carlo example runs successfully", {
  skip_if_not(Sys.getenv("RUN_INTEGRATION_TESTS") == "TRUE")

  result <- system2(
    "Rscript",
    args = c("examples/01-monte-carlo-portfolio.R"),
    env = c("USE_STARBURST=TRUE", "STARBURST_WORKERS=10")
  )

  expect_equal(result, 0)  # Should exit successfully
  expect_true(file.exists("monte-carlo-results-aws.rds"))
})
```

## Results Files

Each example saves results as `.rds` files:
- `*-results-local.rds`: Local execution results
- `*-results-aws.rds`: AWS execution results

Results include:
- Computation outputs
- Execution time
- Worker count
- Timestamp

Use these for benchmarking and validation.

## Performance Expectations

> **Read the runtimes above honestly.** The "with N workers" figures are
> **compute-only on a warm worker pool** — they exclude the one-time cluster
> startup (~2 minutes) and image pull. For the small, seconds-scale demos here,
> that startup dominates and **running locally is faster overall**. These examples
> are sized to run quickly for illustration, not to show a net win.
>
> Cloud bursting pays off when each task runs for **minutes** and there are many of
> them, so the fixed startup is amortized away. See `vignette("performance")` for
> the sizing heuristics (roughly: tasks under ~30 min of total local work often
> aren't worth bursting).

Speedup potential at scale (compute-only, once workers are warm — not net of
startup) with 50–100 workers:
- Monte Carlo, Bootstrap, Data Processing, Grid Search all parallelize near-linearly

Actual performance depends on:
- Task granularity (bigger per-task work amortizes startup better)
- Whether the pool is cold or warm, and whether provisioning is counted
- Data transfer overhead and network conditions
- AWS region and availability
