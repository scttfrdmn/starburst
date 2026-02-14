#!/usr/bin/env Rscript
# EC2 Benchmark using plan() and future_lapply

Sys.setenv(AWS_PROFILE = "aws")
suppressPackageStartupMessages({
  library(starburst)
  library(future)
  library(future.apply)
})

# Monte Carlo simulation function
simulate_portfolio <- function(seed, initial_value = 100000,
                               mean_return = 0.0003, sd_return = 0.02) {
  set.seed(seed)
  daily_returns <- rnorm(252, mean = mean_return, sd = sd_return)
  daily_values <- initial_value * cumprod(1 + daily_returns)
  final_value <- daily_values[252]
  total_return <- (final_value - initial_value) / initial_value
  running_max <- cummax(daily_values)
  drawdowns <- (daily_values - running_max) / running_max
  max_drawdown <- min(drawdowns)
  sharpe_ratio <- mean(daily_returns) / sd(daily_returns) * sqrt(252)

  list(
    final_value = final_value,
    total_return = total_return,
    max_drawdown = max_drawdown,
    sharpe_ratio = sharpe_ratio
  )
}

cat("\n======================================================================\n")
cat("BENCHMARK: STARBURST-EC2\n")
cat("======================================================================\n")

system_info <- list(
  hostname = Sys.info()[["nodename"]],
  machine = Sys.info()[["machine"]]
)

cat(sprintf("Hostname: %s\n", system_info$hostname))
cat(sprintf("Platform: %s\n", system_info$machine))
cat("Simulations: 1000\n")
cat("Mode: staRburst EC2 (25 workers on c6a.large)\n\n")

# Configure EC2 backend
plan(starburst,
     workers = 25,
     cpu = 2,
     memory = "4GB",
     launch_type = "EC2",
     instance_type = "c6a.large",
     use_spot = FALSE,
     warm_pool_timeout = 600,
     region = "us-east-1"
)

cat("Running benchmark...\n")
start_time <- Sys.time()

results <- future_lapply(1:1000, simulate_portfolio, future.seed = TRUE)

end_time <- Sys.time()
elapsed <- as.numeric(difftime(end_time, start_time, units = "secs"))

plan(sequential)  # Clean up

# Analyze results
final_values <- sapply(results, function(x) x$final_value)
total_returns <- sapply(results, function(x) x$total_return)

summary_stats <- list(
  mean_final_value = mean(final_values),
  mean_return = mean(total_returns),
  prob_loss = sum(final_values < 100000) / 1000
)

cat("\n=== RESULTS ===\n")
cat(sprintf("Execution time: %.2f seconds (%.2f minutes)\n",
            elapsed, elapsed/60))
cat(sprintf("Workers: %d\n", 25))
cat(sprintf("Throughput: %.1f simulations/second\n", 1000 / elapsed))
cat(sprintf("\nMean final value: $%s\n",
            format(round(summary_stats$mean_final_value), big.mark = ",")))
cat(sprintf("Mean return: %.2f%%\n", summary_stats$mean_return * 100))
cat(sprintf("Probability of loss: %.1f%%\n",
            summary_stats$prob_loss * 100))

# Save results
timestamp <- format(Sys.time(), "%Y%m%d-%H%M%S")
output_file <- sprintf("benchmark-results-starburst-ec2-%s.rds", timestamp)

benchmark_data <- list(
  mode = "starburst-ec2",
  timestamp = Sys.time(),
  system_info = system_info,
  config = list(
    n_simulations = 1000,
    workers = 25,
    instance_type = "c6a.large",
    use_spot = FALSE
  ),
  performance = list(
    elapsed_seconds = elapsed,
    throughput = 1000 / elapsed,
    workers = 25
  ),
  results_summary = summary_stats,
  raw_results = results
)

saveRDS(benchmark_data, output_file)
cat(sprintf("\n✓ Results saved to: %s\n", output_file))
