# Example: Bootstrap Confidence Intervals for A/B Testing

## Overview

Bootstrap resampling is a powerful statistical technique for estimating
confidence intervals without assuming a specific distribution. This
example demonstrates parallelizing bootstrap analysis for A/B test
results.

**Use Case**: A/B testing, hypothesis testing, statistical inference,
conversion rate analysis

**Computational Pattern**: Embarrassingly parallel resampling with
aggregation

## The Problem

You’ve run an A/B test on your website with two variants: - **Variant A
(Control)**: 10,000 visitors, 850 conversions (8.5% conversion rate) -
**Variant B (Treatment)**: 10,000 visitors, 920 conversions (9.2%
conversion rate)

You need to: 1. Estimate the confidence interval for the difference in
conversion rates 2. Calculate the probability that B is better than A 3.
Determine if the result is statistically significant

Traditional parametric tests assume normal distributions. Bootstrap
resampling makes no such assumptions and provides more robust estimates.

## Setup

``` r

library(starburst)
```

## Generate Sample Data

Create synthetic A/B test data:

``` r

set.seed(42)

# Variant A (control)
n_a <- 10000
conversions_a <- 850
variant_a <- c(rep(1, conversions_a), rep(0, n_a - conversions_a))

# Variant B (treatment)
n_b <- 10000
conversions_b <- 920
variant_b <- c(rep(1, conversions_b), rep(0, n_b - conversions_b))

# Observed difference
observed_diff <- mean(variant_b) - mean(variant_a)
cat(sprintf("Observed conversion rates:\n"))
cat(sprintf("  Variant A: %.2f%%\n", mean(variant_a) * 100))
cat(sprintf("  Variant B: %.2f%%\n", mean(variant_b) * 100))
cat(sprintf("  Difference: %.2f%% (%.1f%% relative lift)\n",
            observed_diff * 100,
            (observed_diff / mean(variant_a)) * 100))
```

**Output**:

    Observed conversion rates:
      Variant A: 8.50%
      Variant B: 9.20%
      Difference: 0.70% (8.2% relative lift)

## Bootstrap Function

Define a function that performs one bootstrap iteration:

``` r

bootstrap_iteration <- function(iter, data_a, data_b) {
  # Resample with replacement
  n_a <- length(data_a)
  n_b <- length(data_b)

  sample_a <- sample(data_a, n_a, replace = TRUE)
  sample_b <- sample(data_b, n_b, replace = TRUE)

  # Calculate metrics
  rate_a <- mean(sample_a)
  rate_b <- mean(sample_b)
  diff <- rate_b - rate_a
  relative_lift <- diff / rate_a

  list(
    iteration = iter,
    rate_a = rate_a,
    rate_b = rate_b,
    diff = diff,
    relative_lift = relative_lift,
    b_wins = diff > 0
  )
}
```

## Local Execution

Run a smaller bootstrap locally:

``` r

n_bootstrap_local <- 1000

cat(sprintf("Running %d bootstrap iterations locally...\n", n_bootstrap_local))
local_start <- Sys.time()

local_results <- lapply(
  1:n_bootstrap_local,
  bootstrap_iteration,
  data_a = variant_a,
  data_b = variant_b
)

local_time <- as.numeric(difftime(Sys.time(), local_start, units = "secs"))
cat(sprintf("[OK] Completed in %.2f seconds\n\n", local_time))
```

**Typical output**:

    Running 1000 bootstrap iterations locally...
    [OK] Completed in 2.1 seconds

## Cloud Execution with staRburst

Run 10,000 bootstrap iterations on AWS:

``` r

n_bootstrap <- 10000

cat(sprintf("Running %d bootstrap iterations on AWS...\n", n_bootstrap))

results <- starburst_map(
  1:n_bootstrap,
  bootstrap_iteration,
  data_a = variant_a,
  data_b = variant_b,
  workers = 25,
  cpu = 1,
  memory = "2GB"
)
```

**Typical output**:

    [Starting] Starting starburst cluster with 25 workers
    [Status] Processing 10000 items with 25 workers
    [Starting] Submitting 10000 tasks...
    [Wait] Progress: 10000/10000 (18.0s)
    [OK] Completed in 18.0 seconds
    [Cost] Estimated cost: $0.01

## Results Analysis

Extract and analyze the bootstrap distribution:

``` r

# Extract metrics
diffs <- sapply(results, function(x) x$diff)
relative_lifts <- sapply(results, function(x) x$relative_lift)
b_wins <- sapply(results, function(x) x$b_wins)

# Calculate confidence intervals
ci_95 <- quantile(diffs, c(0.025, 0.975))
ci_99 <- quantile(diffs, c(0.005, 0.995))

# Probability that B is better than A
prob_b_wins <- mean(b_wins) * 100

# Print results
cat("\n=== Bootstrap Results (10,000 iterations) ===\n\n")
cat(sprintf("Observed difference: %.2f%%\n", observed_diff * 100))
cat(sprintf("\n95%% Confidence Interval: [%.2f%%, %.2f%%]\n",
            ci_95[1] * 100, ci_95[2] * 100))
cat(sprintf("99%% Confidence Interval: [%.2f%%, %.2f%%]\n",
            ci_99[1] * 100, ci_99[2] * 100))
cat(sprintf("\nProbability that B > A: %.1f%%\n", prob_b_wins))

# Statistical significance
if (ci_95[1] > 0) {
  cat("\n[OK] Result is statistically significant at 95% confidence level\n")
  cat("  (95% CI does not include zero)\n")
} else {
  cat("\n[X] Result is NOT statistically significant at 95% confidence level\n")
  cat("  (95% CI includes zero)\n")
}

# Relative lift analysis
cat(sprintf("\nRelative lift: %.1f%%\n",
            median(relative_lifts) * 100))
cat(sprintf("95%% CI for relative lift: [%.1f%%, %.1f%%]\n",
            quantile(relative_lifts, 0.025) * 100,
            quantile(relative_lifts, 0.975) * 100))
```

**Typical output**:

    === Bootstrap Results (10,000 iterations) ===

    Observed difference: 0.70%

    95% Confidence Interval: [0.21%, 1.19%]
    99% Confidence Interval: [0.08%, 1.32%]

    Probability that B > A: 99.7%

    [OK] Result is statistically significant at 95% confidence level
      (95% CI does not include zero)

    Relative lift: 8.2%
    95% CI for relative lift: [2.5%, 14.0%]

## Visualization

Plot the bootstrap distribution:

``` r

# Create histogram
hist(diffs * 100,
     breaks = 50,
     main = "Bootstrap Distribution of Conversion Rate Difference",
     xlab = "Difference in Conversion Rate (percentage points)",
     col = "lightblue",
     border = "white")

# Add reference lines
abline(v = 0, col = "red", lwd = 2, lty = 2)
abline(v = ci_95 * 100, col = "darkblue", lwd = 2, lty = 2)
abline(v = observed_diff * 100, col = "darkgreen", lwd = 2)

# Add legend
legend("topright",
       c("Observed difference", "Zero (no effect)", "95% CI"),
       col = c("darkgreen", "red", "darkblue"),
       lwd = 2,
       lty = c(1, 2, 2))
```

## Performance Comparison

| Method       | Iterations | Compute time          | Cost   |
|--------------|------------|-----------------------|--------|
| Local        | 1,000      | 2.1 sec               | \$0    |
| Local (est.) | 10,000     | 21 sec                | \$0    |
| staRburst    | 10,000     | 18 sec (compute only) | \$0.01 |

> **Reading these numbers honestly:** the staRburst row is *compute time
> only* on a warm pool and excludes the one-time startup (~2 minutes)
> and image pull. For a job that finishes in ~20 seconds locally, that
> startup makes local the faster choice — the numbers here are
> illustrative, not a claim that bursting a 20-second job wins.
> Bootstrap *does* parallelize well; the payoff is real once iterations
> are expensive or you scale to 100,000+. See
> [`vignette("performance")`](https://starburst.ing/articles/performance.md)
> for the sizing heuristics.

**Key Insights**: - Bootstrap is highly parallelizable - Minimal
per-task cost even with 10,000 iterations - The win comes at scale
(100,000+ iterations or expensive per-iteration work), where startup
overhead is amortized away

## Advanced: Multi-Metric Bootstrap

Bootstrap multiple metrics simultaneously:

``` r

bootstrap_all_metrics <- function(iter, data_a, data_b) {
  n_a <- length(data_a)
  n_b <- length(data_b)

  sample_a <- sample(data_a, n_a, replace = TRUE)
  sample_b <- sample(data_b, n_b, replace = TRUE)

  # Multiple metrics
  rate_a <- mean(sample_a)
  rate_b <- mean(sample_b)
  se_a <- sd(sample_a) / sqrt(n_a)
  se_b <- sd(sample_b) / sqrt(n_b)

  list(
    diff_rate = rate_b - rate_a,
    relative_lift = (rate_b - rate_a) / rate_a,
    z_score = (rate_b - rate_a) / sqrt(se_a^2 + se_b^2),
    effect_size = (rate_b - rate_a) / sqrt((var(sample_a) + var(sample_b)) / 2)
  )
}

# Run multi-metric bootstrap
multi_results <- starburst_map(
  1:10000,
  bootstrap_all_metrics,
  data_a = variant_a,
  data_b = variant_b,
  workers = 25
)
```

## When to Use This Pattern

**Good fit**: - Need robust confidence intervals - Non-normal
distributions - Small sample sizes - Complex metrics (e.g., ratios,
quantiles) - Multiple hypothesis testing

**Not ideal**: - Very large datasets (\> 1M rows per group) - Simple
metrics with known distributions - Real-time analysis requirements

## Running the Full Example

The complete runnable script is available at:

``` r

system.file("examples/bootstrap.R", package = "starburst")
```

Run it with:

``` r

source(system.file("examples/bootstrap.R", package = "starburst"))
```

## Next Steps

- Try different sample sizes
- Experiment with stratified bootstrap
- Compare with parametric tests (t-test, z-test)
- Add multiple variants (A/B/C testing)
- Bootstrap other metrics (median, quantiles, variance)

**Related examples**: - [Monte Carlo
Simulation](https://starburst.ing/articles/example-monte-carlo.md) -
Similar resampling pattern - [Risk
Modeling](https://starburst.ing/articles/example-risk-modeling.md) -
Advanced statistical analysis
