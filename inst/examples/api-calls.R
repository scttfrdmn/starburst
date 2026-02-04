#!/usr/bin/env Rscript
#
# Parallel Bulk API Calls Example
#
# This script demonstrates parallel API calls using staRburst.
# It fetches data for 1,000 companies using a mock API.
#
# Usage:
#   Rscript api-calls.R
#   # or from R:
#   source(system.file("examples/api-calls.R", package = "starburst"))

library(starburst)

cat("=== Parallel Bulk API Calls Example ===\n\n")

# Mock API function (simulates real API with delays)
fetch_company_data_mock <- function(ticker) {
  # Simulate network latency
  Sys.sleep(runif(1, 0.2, 0.8))

  # Simulate occasional failures (5% rate)
  if (runif(1) < 0.05) {
    return(list(
      ticker = ticker,
      success = FALSE,
      error = "API timeout",
      timestamp = Sys.time()
    ))
  }

  # Generate mock data
  list(
    ticker = ticker,
    success = TRUE,
    company_name = paste("Company", ticker),
    market_cap = round(rnorm(1, 50e9, 20e9), 0),
    pe_ratio = round(rnorm(1, 25, 10), 2),
    revenue = round(rnorm(1, 10e9, 5e9), 0),
    employees = round(rnorm(1, 50000, 20000), 0),
    sector = sample(c("Technology", "Healthcare", "Finance", "Energy"), 1),
    timestamp = Sys.time()
  )
}

# Generate mock ticker symbols
set.seed(123)
n_companies <- 1000
tickers <- paste0(
  sample(LETTERS, n_companies, replace = TRUE),
  sample(LETTERS, n_companies, replace = TRUE),
  sample(LETTERS, n_companies, replace = TRUE)
)

cat(sprintf("Generated %d company tickers\n\n", n_companies))

# Local benchmark (50 calls)
cat("Running local benchmark (50 API calls)...\n")
local_start <- Sys.time()
local_results <- lapply(head(tickers, 50), fetch_company_data_mock)
local_time <- as.numeric(difftime(Sys.time(), local_start, units = "secs"))

cat(sprintf("✓ Completed in %.1f seconds\n", local_time))
cat(sprintf("  Estimated time for %d: %.1f minutes\n\n",
            n_companies, local_time * n_companies / 50 / 60))

# Cloud execution
n_workers <- 25

cat(sprintf("Fetching data for %d companies on %d workers...\n",
            n_companies, n_workers))

cloud_start <- Sys.time()
results <- starburst_map(
  tickers,
  fetch_company_data_mock,
  workers = n_workers,
  cpu = 1,
  memory = "2GB"
)
cloud_time <- as.numeric(difftime(Sys.time(), cloud_start, units = "mins"))

cat(sprintf("\n✓ Completed in %.2f minutes\n\n", cloud_time))

# Process results into data frame
results_df <- do.call(rbind, lapply(results, function(x) {
  if (x$success) {
    data.frame(
      ticker = x$ticker,
      company_name = x$company_name,
      market_cap = x$market_cap,
      pe_ratio = x$pe_ratio,
      revenue = x$revenue,
      employees = x$employees,
      sector = x$sector,
      success = TRUE,
      error = NA,
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(
      ticker = x$ticker,
      company_name = NA,
      market_cap = NA,
      pe_ratio = NA,
      revenue = NA,
      employees = NA,
      sector = NA,
      success = FALSE,
      error = x$error,
      stringsAsFactors = FALSE
    )
  }
}))

# Print summary
cat("=== Results Summary ===\n\n")
success_rate <- mean(results_df$success) * 100
cat(sprintf("Total companies: %d\n", nrow(results_df)))
cat(sprintf("Successful fetches: %d (%.1f%%)\n",
            sum(results_df$success), success_rate))
cat(sprintf("Failed fetches: %d\n\n", sum(!results_df$success)))

# Sample results
cat("=== Sample Results ===\n\n")
successful <- results_df[results_df$success, ]
print(head(successful[, c("ticker", "company_name", "sector", "market_cap")], 10))

# Sector distribution
cat("\n=== Sector Distribution ===\n\n")
sector_table <- table(results_df$sector)
print(sector_table)

# Market cap statistics
cat("\n=== Market Cap Statistics ===\n\n")
cat(sprintf("Mean: $%.2fB\n",
            mean(results_df$market_cap, na.rm = TRUE) / 1e9))
cat(sprintf("Median: $%.2fB\n",
            median(results_df$market_cap, na.rm = TRUE) / 1e9))
cat(sprintf("Range: $%.2fB - $%.2fB\n",
            min(results_df$market_cap, na.rm = TRUE) / 1e9,
            max(results_df$market_cap, na.rm = TRUE) / 1e9))

# Performance comparison
cat("\n=== Performance Comparison ===\n\n")
estimated_local_time <- local_time * n_companies / 50 / 60
speedup <- estimated_local_time / cloud_time
cat(sprintf("Local (estimated): %.1f minutes\n", estimated_local_time))
cat(sprintf("Cloud (%d workers): %.2f minutes\n", n_workers, cloud_time))
cat(sprintf("Speedup: %.1fx\n", speedup))

# Save results (optional)
if (interactive()) {
  save_results <- readline("Save results to CSV? (y/n): ")
  if (tolower(save_results) == "y") {
    write.csv(results_df, "company_data.csv", row.names = FALSE)
    cat("Results saved to company_data.csv\n")
  }
}

cat("\n✓ Done!\n")
