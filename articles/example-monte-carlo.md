# Example: Monte Carlo Portfolio Simulation

## Overview

Monte Carlo simulations are a common use case for parallel computing.
This example demonstrates running 10,000 portfolio simulations to
estimate risk metrics.

**Use Case**: Portfolio risk analysis, Value at Risk (VaR) calculations,
stress testing

**Computational Pattern**: Embarrassingly parallel - each simulation is
independent

## The Problem

You need to simulate 10,000 different portfolio scenarios to estimate: -
Expected portfolio value - Value at Risk (VaR) at 95% confidence -
Sharpe ratio distribution - Probability of loss scenarios

Each simulation involves 252 trading days (one year) with correlated
asset returns.

## Setup

``` r

library(starburst)
library(ggplot2)
```

## Simulation Function

Define a function that simulates one portfolio trajectory:

``` r

simulate_portfolio <- function(seed) {
  set.seed(seed)

  # Portfolio parameters
  n_days <- 252
  initial_value <- 1000000  # $1M portfolio

  # Asset allocation (60/40 stocks/bonds)
  stock_weight <- 0.6
  bond_weight <- 0.4

  # Expected returns (annualized)
  stock_return <- 0.10 / 252  # 10% annual
  bond_return <- 0.04 / 252   # 4% annual

  # Volatility (annualized)
  stock_vol <- 0.20 / sqrt(252)  # 20% annual
  bond_vol <- 0.05 / sqrt(252)   # 5% annual

  # Correlation
  correlation <- 0.3

  # Generate correlated returns
  stock_returns <- rnorm(n_days, mean = stock_return, sd = stock_vol)
  bond_noise <- rnorm(n_days)
  bond_returns <- rnorm(n_days, mean = bond_return, sd = bond_vol)
  bond_returns <- correlation * stock_returns +
                  sqrt(1 - correlation^2) * bond_returns

  # Portfolio returns
  portfolio_returns <- stock_weight * stock_returns +
                      bond_weight * bond_returns

  # Cumulative value
  portfolio_values <- initial_value * cumprod(1 + portfolio_returns)

  # Calculate metrics
  final_value <- portfolio_values[n_days]
  max_drawdown <- max((cummax(portfolio_values) - portfolio_values) /
                      cummax(portfolio_values))
  sharpe_ratio <- mean(portfolio_returns) / sd(portfolio_returns) * sqrt(252)

  list(
    final_value = final_value,
    return_pct = (final_value - initial_value) / initial_value * 100,
    max_drawdown = max_drawdown,
    sharpe_ratio = sharpe_ratio,
    min_value = min(portfolio_values),
    max_value = max(portfolio_values)
  )
}
```

## Local Execution

Run a smaller test locally:

``` r

# Test with 100 simulations
set.seed(123)
local_start <- Sys.time()
local_results <- lapply(1:100, simulate_portfolio)
local_time <- as.numeric(difftime(Sys.time(), local_start, units = "secs"))

cat(sprintf("100 simulations completed in %.1f seconds\n", local_time))
cat(sprintf("Estimated time for 10,000: %.1f minutes\n",
            local_time * 100 / 60))
```

**Illustrative output** (depends on your machine):

    100 simulations completed in ~2 seconds
    Estimated time for 10,000: ~a few minutes

## Cloud Execution with staRburst

Each simulation is tiny (well under a millisecond), so this is a
**batch-it** workload: submitting 10,000 one-simulation tasks would be
dominated by per-task S3 overhead (see the [Workload
Shapes](https://starburst.ing/articles/workload-shapes.html) guide,
which measures that anti-pattern at ~77 minutes). Instead, batch into
~100 tasks of 100 simulations each:

``` r

# 100 tasks x 100 simulations = 10,000 simulations, batched
batches <- split(1:10000, ceiling(seq_along(1:10000) / 100))
results <- starburst_map(
  batches,
  function(seeds) lapply(seeds, simulate_portfolio),
  workers = 50,
  cpu = 2,
  memory = "4GB"
)
results <- unlist(results, recursive = FALSE)  # flatten to 10,000 results
```

**Illustrative output** (times/cost vary — see the Workload Shapes and
Performance guides for measured numbers):

    [Starting] Starting starburst cluster with 50 workers
    [Status] Processing 100 items with 50 workers
    [Starting] Submitting 100 tasks...
    [Wait] Progress: 100/100
    [OK] Completed
    [Cost] Estimated cost: (printed per run)

## Results Analysis

Extract and analyze the results:

``` r

# Extract metrics
final_values <- sapply(results, function(x) x$final_value)
returns <- sapply(results, function(x) x$return_pct)
sharpe_ratios <- sapply(results, function(x) x$sharpe_ratio)
max_drawdowns <- sapply(results, function(x) x$max_drawdown)

# Summary statistics
cat("\n=== Portfolio Simulation Results (10,000 scenarios) ===\n")
cat(sprintf("Mean final value: $%.0f\n", mean(final_values)))
cat(sprintf("Median final value: $%.0f\n", median(final_values)))
cat(sprintf("\nMean return: %.2f%%\n", mean(returns)))
cat(sprintf("Std dev of returns: %.2f%%\n", sd(returns)))
cat(sprintf("\nValue at Risk (5%%): $%.0f\n",
            quantile(final_values, 0.05)))
cat(sprintf("Expected Shortfall (5%%): $%.0f\n",
            mean(final_values[final_values <= quantile(final_values, 0.05)])))
cat(sprintf("\nMean Sharpe Ratio: %.2f\n", mean(sharpe_ratios)))
cat(sprintf("Mean Max Drawdown: %.2f%%\n", mean(max_drawdowns) * 100))
cat(sprintf("\nProbability of loss: %.2f%%\n",
            mean(returns < 0) * 100))

# Distribution plot
hist(final_values / 1000,
     breaks = 50,
     main = "Distribution of Portfolio Final Values",
     xlab = "Final Value ($1000s)",
     col = "lightblue",
     border = "white")
abline(v = 1000, col = "red", lwd = 2, lty = 2)
abline(v = quantile(final_values / 1000, 0.05), col = "orange", lwd = 2, lty = 2)
legend("topright",
       c("Initial Value", "VaR (5%)"),
       col = c("red", "orange"),
       lwd = 2, lty = 2)
```

**Illustrative output** (values depend on the random draws):

    === Portfolio Simulation Results (10,000 scenarios) ===
    Mean final value: $1,102,450
    Median final value: $1,097,230
    Mean return: 10.24%   Std dev: 12.83%
    Value at Risk (5%): $892,340
    Probability of loss: 18.34%

## Performance

Monte Carlo of tiny per-simulation tasks is a **batching** story, not a
raw-fan-out story: batch to ~100 tasks (as above) and the run is
dominated by real compute rather than per-task overhead. For
**measured** cold/warm numbers — including how batching turns a
~77-minute naive run into minutes, and how to pick worker counts — see
the [Workload
Shapes](https://starburst.ing/articles/workload-shapes.html) and
[Performance](https://starburst.ing/articles/performance.html) guides.
We don’t repeat hand-written speedup tables here; those guides are the
single source of truth.

## When to Use This Pattern

**Good fit**: - Each iteration is independent - Computational time \>
0.1 seconds per iteration - Total iterations \> 1,000 - Results can be
easily aggregated

**Not ideal**: - Very fast iterations (\< 0.01 seconds) - High data
transfer per iteration - Strong sequential dependencies

## Running the Full Example

The complete runnable script is available at:

``` r

system.file("examples/monte-carlo.R", package = "starburst")
```

Run it with:

``` r

source(system.file("examples/monte-carlo.R", package = "starburst"))
```

## Next Steps

- Try adjusting portfolio parameters (allocation, volatility)
- Experiment with different worker counts
- Compare costs for different AWS regions
- Add more sophisticated portfolio models

**Related examples**: - [Bootstrap Confidence
Intervals](https://starburst.ing/articles/example-bootstrap.md) -
Another Monte Carlo application - [Financial Risk
Modeling](https://starburst.ing/articles/example-risk-modeling.md) -
Advanced portfolio analysis
