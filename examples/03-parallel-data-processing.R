#!/usr/bin/env Rscript
# Parallel Data Processing
#
# Processes multiple datasets in parallel, performing feature engineering
# and model fitting on each.
# Demonstrates: Data-intensive tasks with moderate computation per chunk.

library(furrr)

# Only load starburst if using AWS
use_starburst <- Sys.getenv("USE_STARBURST", "FALSE") == "TRUE"
if (use_starburst) {
  library(starburst)
}

# Function to process one dataset chunk
process_dataset_chunk <- function(chunk_id, n_rows = 10000) {
  # Simulate loading a dataset (in reality, might read from S3/database)
  set.seed(chunk_id)

  data <- data.frame(
    customer_id = 1:n_rows,
    age = sample(18:80, n_rows, replace = TRUE),
    income = rlnorm(n_rows, meanlog = 10.5, sdlog = 0.8),
    previous_purchases = rpois(n_rows, lambda = 3),
    time_since_last = rexp(n_rows, rate = 1/30)
  )

  # Feature engineering
  data$income_bracket <- cut(data$income,
                             breaks = c(0, 30000, 60000, 100000, Inf),
                             labels = c("Low", "Medium", "High", "Very High"))

  data$age_group <- cut(data$age,
                        breaks = c(0, 25, 40, 60, Inf),
                        labels = c("Young", "Adult", "Middle", "Senior"))

  data$engagement_score <- with(data,
    previous_purchases * 10 +
    pmax(0, 100 - time_since_last) * 2 +
    (income / 1000) * 0.5
  )

  # Fit simple model: predict purchase probability
  data$purchase_prob <- plogis(
    -2 +
    0.01 * data$age +
    0.00001 * data$income +
    0.3 * data$previous_purchases -
    0.02 * data$time_since_last +
    rnorm(n_rows, 0, 0.5)  # Add noise
  )

  # Classify as likely purchaser
  data$likely_purchaser <- data$purchase_prob > 0.6

  # Aggregate statistics for this chunk
  stats <- list(
    chunk_id = chunk_id,
    n_rows = n_rows,
    n_likely_purchasers = sum(data$likely_purchaser),
    mean_engagement = mean(data$engagement_score),
    median_income = median(data$income),
    mean_age = mean(data$age),
    income_by_bracket = tapply(data$income, data$income_bracket, mean),
    engagement_by_age = tapply(data$engagement_score, data$age_group, mean)
  )

  # In reality, might write processed data back to S3/database
  # For demo, just return summary statistics
  stats
}

# Configuration
n_chunks <- 100  # Process 100 dataset chunks
n_workers <- as.integer(Sys.getenv("STARBURST_WORKERS", "50"))
rows_per_chunk <- 10000

cat("Parallel Data Processing\n")
cat("========================\n")
cat("Dataset chunks:", n_chunks, "\n")
cat("Rows per chunk:", rows_per_chunk, "\n")
cat("Total rows:", n_chunks * rows_per_chunk, "\n")
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

# Process all chunks in parallel
cat("Processing dataset chunks...\n")
start_time <- Sys.time()

chunk_stats <- future_map(
  1:n_chunks,
  ~process_dataset_chunk(.x, rows_per_chunk),
  .options = furrr_options(seed = TRUE),
  .progress = TRUE
)

end_time <- Sys.time()
elapsed <- as.numeric(difftime(end_time, start_time, units = "secs"))

# Aggregate results across all chunks
total_likely_purchasers <- sum(sapply(chunk_stats, function(x) x$n_likely_purchasers))
mean_engagement <- mean(sapply(chunk_stats, function(x) x$mean_engagement))
median_income <- median(sapply(chunk_stats, function(x) x$median_income))
mean_age <- mean(sapply(chunk_stats, function(x) x$mean_age))

cat("\n")
cat("Processing Results\n")
cat("==================\n")
cat(sprintf("Execution time: %.1f seconds (%.1f minutes)\n", elapsed, elapsed/60))
cat(sprintf("Throughput: %.0f rows/second\n",
            (n_chunks * rows_per_chunk) / elapsed))
cat("\n")
cat("Aggregate Statistics:\n")
cat(sprintf("  Total likely purchasers: %s (%.1f%%)\n",
            format(total_likely_purchasers, big.mark = ","),
            (total_likely_purchasers / (n_chunks * rows_per_chunk)) * 100))
cat(sprintf("  Mean engagement score: %.1f\n", mean_engagement))
cat(sprintf("  Median income: $%,.0f\n", median_income))
cat(sprintf("  Mean age: %.1f years\n", mean_age))
cat("\n")

# Performance metrics
if (use_starburst) {
  cat("Scaling Efficiency:\n")
  cat(sprintf("  Workers: %d\n", n_workers))
  cat(sprintf("  Time per chunk: %.2f seconds\n", elapsed / n_chunks))
  cat(sprintf("  Parallel speedup: ~%.1fx\n", n_chunks / (elapsed / (rows_per_chunk / 10000))))
}

# Save results
output_file <- sprintf("processing-results-%s.rds",
                       if(use_starburst) "aws" else "local")
saveRDS(list(
  chunk_stats = chunk_stats,
  elapsed = elapsed,
  mode = if(use_starburst) "aws" else "local",
  workers = if(use_starburst) n_workers else 1,
  timestamp = Sys.time()
), output_file)

cat("\nResults saved to:", output_file, "\n")
