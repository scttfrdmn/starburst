#!/usr/bin/env Rscript
#
# Parallel Report Generation Example
#
# This script demonstrates parallel RMarkdown report rendering using staRburst.
# It generates 50 personalized customer reports in parallel.
#
# Usage:
#   Rscript reports.R
#   # or from R:
#   source(system.file("examples/reports.R", package = "starburst"))

library(starburst)

cat("=== Parallel Report Generation Example ===\n\n")

# Create report template
cat("Creating report template...\n")

report_template <- '
---
title: "Monthly Analytics Report"
output: html_document
params:
  customer_id: ""
  customer_name: ""
  month: ""
  revenue_total: 0
  transaction_count: 0
---

# Monthly Report for `r params$customer_name`

**Customer ID:** `r params$customer_id`
**Period:** `r params$month`
**Report Generated:** `r format(Sys.time(), "%Y-%m-%d %H:%M")`

---

## Executive Summary

- **Total Transactions:** `r params$transaction_count`
- **Total Revenue:** $`r format(params$revenue_total, big.mark=",")`
- **Average Order Value:** $`r round(params$revenue_total / params$transaction_count, 2)`

## Revenue Summary

This report shows a summary of activity for the period.

```{r, echo=FALSE}
# Generate sample data for visualization
set.seed(as.numeric(gsub("[^0-9]", "", params$customer_id)))
daily_revenue <- rnorm(30, mean = params$revenue_total / 30, sd = params$revenue_total / 60)
plot(1:30, daily_revenue, type = "l", lwd = 2, col = "steelblue",
     main = "Daily Revenue Trend", xlab = "Day", ylab = "Revenue ($)")
grid()
```

---

*Report automatically generated using staRburst*
'

# Create temporary template file
template_file <- tempfile(fileext = ".Rmd")
writeLines(report_template, template_file)

cat(sprintf("✓ Template created: %s\n\n", template_file))

# Generate customer data
n_customers <- 50
customers <- data.frame(
  customer_id = sprintf("CUST%03d", 1:n_customers),
  customer_name = paste("Company", LETTERS[(1:n_customers - 1) %% 26 + 1],
                       ((1:n_customers - 1) %/% 26) + 1),
  stringsAsFactors = FALSE
)

cat(sprintf("Generated %d customer records\n\n", n_customers))

# Report generation function
generate_report <- function(customer_info, template_path) {
  customer_id <- customer_info$customer_id
  customer_name <- customer_info$customer_name

  # Generate random metrics for this customer
  set.seed(as.numeric(gsub("[^0-9]", "", customer_id)))
  transaction_count <- sample(100:500, 1)
  revenue_total <- round(transaction_count * rnorm(1, 150, 30), 2)

  # Create output directory if needed
  output_dir <- tempdir()
  output_file <- file.path(output_dir, sprintf("report_%s.html", customer_id))

  tryCatch({
    # Render report (suppress output)
    suppressMessages(suppressWarnings(
      rmarkdown::render(
        input = template_path,
        output_file = output_file,
        params = list(
          customer_id = customer_id,
          customer_name = customer_name,
          month = "January 2026",
          revenue_total = revenue_total,
          transaction_count = transaction_count
        ),
        quiet = TRUE
      )
    ))

    list(
      customer_id = customer_id,
      customer_name = customer_name,
      success = TRUE,
      output_file = output_file,
      file_size = file.size(output_file),
      revenue = revenue_total,
      transactions = transaction_count
    )
  }, error = function(e) {
    list(
      customer_id = customer_id,
      customer_name = customer_name,
      success = FALSE,
      error = as.character(e)
    )
  })
}

# Local benchmark (5 reports)
cat("Running local benchmark (5 reports)...\n")
test_customers <- head(customers, 5)

local_start <- Sys.time()
local_results <- lapply(
  split(test_customers, 1:nrow(test_customers)),
  generate_report,
  template_path = template_file
)
local_time <- as.numeric(difftime(Sys.time(), local_start, units = "secs"))

cat(sprintf("✓ Completed in %.1f seconds\n", local_time))
cat(sprintf("  Average: %.1f seconds per report\n", local_time / 5))
cat(sprintf("  Estimated time for %d reports: %.1f seconds\n\n",
            n_customers, local_time / 5 * n_customers))

# Cloud execution
n_workers <- 25

cat(sprintf("Rendering %d reports on %d workers...\n", n_customers, n_workers))

customer_list <- split(customers, 1:nrow(customers))

cloud_start <- Sys.time()
results <- starburst_map(
  customer_list,
  generate_report,
  template_path = template_file,
  workers = n_workers,
  cpu = 2,
  memory = "4GB"
)
cloud_time <- as.numeric(difftime(Sys.time(), cloud_start, units = "secs"))

cat(sprintf("\n✓ Completed in %.1f seconds\n\n", cloud_time))

# Analyze results
success_count <- sum(sapply(results, function(x) x$success))
failure_count <- sum(!sapply(results, function(x) x$success))

cat("=== Report Generation Summary ===\n\n")
cat(sprintf("Total reports: %d\n", length(results)))
cat(sprintf("Successfully generated: %d (%.1f%%)\n",
            success_count, (success_count / length(results)) * 100))
cat(sprintf("Failed: %d\n\n", failure_count))

# File statistics
if (success_count > 0) {
  successful_results <- results[sapply(results, function(x) x$success)]
  file_sizes <- sapply(successful_results, function(x) x$file_size)

  cat("File size statistics:\n")
  cat(sprintf("  Total size: %.2f MB\n", sum(file_sizes) / 1024^2))
  cat(sprintf("  Average size: %.1f KB\n", mean(file_sizes) / 1024))
  cat(sprintf("  Range: %.1f - %.1f KB\n\n",
              min(file_sizes) / 1024, max(file_sizes) / 1024))

  # Revenue statistics
  revenues <- sapply(successful_results, function(x) x$revenue)
  cat("Revenue statistics:\n")
  cat(sprintf("  Total revenue: $%.0f\n", sum(revenues)))
  cat(sprintf("  Average: $%.0f\n", mean(revenues)))
  cat(sprintf("  Range: $%.0f - $%.0f\n\n",
              min(revenues), max(revenues)))

  # Show sample output files
  cat("Sample generated reports:\n")
  sample_files <- sapply(successful_results[1:min(5, success_count)],
                        function(x) basename(x$output_file))
  for (f in sample_files) {
    cat(sprintf("  - %s\n", f))
  }
  cat("\n")
}

# Performance comparison
cat("=== Performance Comparison ===\n\n")
estimated_local_time <- (local_time / 5) * n_customers
speedup <- estimated_local_time / cloud_time
cat(sprintf("Local (estimated): %.1f seconds\n", estimated_local_time))
cat(sprintf("Cloud (%d workers): %.1f seconds\n", n_workers, cloud_time))
cat(sprintf("Speedup: %.1fx\n", speedup))

# Cleanup
unlink(template_file)

cat("\n✓ Done!\n")
cat(sprintf("Note: Reports saved to: %s\n", tempdir()))
