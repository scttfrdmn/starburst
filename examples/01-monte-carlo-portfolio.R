#!/usr/bin/env Rscript
# Monte Carlo Portfolio Risk Simulation
#
# Simulates 10,000 potential portfolio outcomes to assess risk.
# Demonstrates: CPU-intensive parallel computation with independent tasks.

library(furrr)

# Only load starburst if using AWS
use_starburst <- Sys.getenv("USE_STARBURST", "FALSE") == "TRUE"
if (use_starburst) {
  library(starburst)
}

# Simulation function: one year of daily returns
simulate_portfolio <- function(seed, initial_value = 100000,
                               mean_return = 0.0003, sd_return = 0.02) {
  set.seed(seed)

  # 252 trading days in a year
  daily_returns <- rnorm(252, mean = mean_return, sd = sd_return)
  daily_values <- initial_value * cumprod(1 + daily_returns)

  # Calculate metrics
  final_value <- daily_values[252]
  total_return <- (final_value - initial_value) / initial_value

  # Maximum drawdown
  running_max <- cummax(daily_values)
  drawdowns <- (daily_values - running_max) / running_max
  max_drawdown <- min(drawdowns)

  # Sharpe ratio (annualized)
  sharpe_ratio <- mean(daily_returns) / sd(daily_returns) * sqrt(252)

  list(
    final_value = final_value,
    total_return = total_return,
    max_drawdown = max_drawdown,
    sharpe_ratio = sharpe_ratio
  )
}

# Configuration
n_simulations <- 10000
n_workers <- as.integer(Sys.getenv("STARBURST_WORKERS", "100"))

cat("Monte Carlo Portfolio Simulation\n")
cat("=================================\n")
cat("Simulations:", n_simulations, "\n")
cat("Mode:", if(use_starburst) paste("AWS Fargate (", n_workers, "workers)") else "Local\n")
cat("\n")

# Set up execution plan
if (use_starburst) {
  cat("Setting up staRburst...\n")
  plan(future_starburst, workers = n_workers)
} else {
  cat("Using local sequential execution...\n")
  plan(sequential)
}

# Run simulations
cat("Running simulations...\n")
start_time <- Sys.time()

results <- future_map(
  1:n_simulations,
  simulate_portfolio,
  .options = furrr_options(seed = TRUE),
  .progress = TRUE
)

end_time <- Sys.time()
elapsed <- as.numeric(difftime(end_time, start_time, units = "secs"))

# Analyze results
final_values <- sapply(results, function(x) x$final_value)
total_returns <- sapply(results, function(x) x$total_return)
max_drawdowns <- sapply(results, function(x) x$max_drawdown)
sharpe_ratios <- sapply(results, function(x) x$sharpe_ratio)

cat("\n")
cat("Results Summary\n")
cat("===============\n")
cat(sprintf("Execution time: %.1f seconds (%.1f minutes)\n", elapsed, elapsed/60))
cat("\n")
cat("Portfolio Outcomes ($100,000 initial):\n")
cat(sprintf("  Mean final value: $%s\n", format(round(mean(final_values)), big.mark = ",")))
cat(sprintf("  Median final value: $%s\n", format(round(median(final_values)), big.mark = ",")))
cat(sprintf("  5th percentile: $%s\n", format(round(quantile(final_values, 0.05)), big.mark = ",")))
cat(sprintf("  95th percentile: $%s\n", format(round(quantile(final_values, 0.95)), big.mark = ",")))
cat("\n")
cat(sprintf("  Mean return: %.1f%%\n", mean(total_returns) * 100))
cat(sprintf("  Median return: %.1f%%\n", median(total_returns) * 100))
cat(sprintf("  Mean max drawdown: %.1f%%\n", mean(max_drawdowns) * 100))
cat(sprintf("  Mean Sharpe ratio: %.2f\n", mean(sharpe_ratios)))
cat("\n")
cat(sprintf("  Probability of loss: %.1f%%\n",
            sum(final_values < 100000) / n_simulations * 100))
cat(sprintf("  Probability of 20%%+ gain: %.1f%%\n",
            sum(final_values > 120000) / n_simulations * 100))

# Save results
output_file <- sprintf("monte-carlo-results-%s.rds",
                       if(use_starburst) "aws" else "local")
saveRDS(list(
  results = results,
  elapsed = elapsed,
  mode = if(use_starburst) "aws" else "local",
  workers = if(use_starburst) n_workers else 1,
  timestamp = Sys.time()
), output_file)

cat("\nResults saved to:", output_file, "\n")
