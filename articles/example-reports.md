# Example: Parallel Report Generation

## Overview

Generating personalized reports for many customers is a common
bottleneck. This example demonstrates parallelizing RMarkdown/Quarto
report generation using staRburst.

**Use Case**: Monthly customer reports, automated analytics,
personalized dashboards, regulatory reporting

**Computational Pattern**: I/O-bound parallel processing with document
rendering

## The Problem

You need to generate 50 customized monthly reports for different
customers: - Each report includes data analysis, visualizations, and
summary statistics - Each report takes 1-2 minutes to render -
Sequential generation would take 50-100 minutes - Reports must be
delivered by end of business day

## Setup

``` r
library(starburst)
library(rmarkdown)
```

## Report Template

Create a simple RMarkdown template:

``` r
# Create report template
report_template <- '
---
title: "Monthly Analytics Report"
output: html_document
params:
  customer_id: ""
  customer_name: ""
  month: ""
  data: NULL
---

`​``{r template-setup, include=FALSE}
knitr::opts_chunk$set(echo = FALSE, warning = FALSE, message = FALSE)
`​``

# Monthly Report for `r params$customer_name`

**Customer ID:** `r params$customer_id`
**Period:** `r params$month`
**Report Generated:** `r format(Sys.time(), "%Y-%m-%d %H:%M")`

---

## Executive Summary

This report summarizes activity for `r params$customer_name` during `r params$month`.

\`\`\`{r summary}
data <- params$data
cat(sprintf("Total transactions: %d\\n", nrow(data)))
cat(sprintf("Total revenue: $%.2f\\n", sum(data$revenue)))
cat(sprintf("Average order value: $%.2f\\n", mean(data$revenue)))
cat(sprintf("Active days: %d\\n", length(unique(data$date))))
\`\`\`

## Revenue Trend

\`\`\`{r revenue-plot, fig.width=8, fig.height=4}
daily_revenue <- aggregate(revenue ~ date, data, sum)
plot(daily_revenue$date, daily_revenue$revenue,
     type = "l", lwd = 2, col = "steelblue",
     main = "Daily Revenue Trend",
     xlab = "Date", ylab = "Revenue ($)")
grid()
\`\`\`

## Top Products

\`\`\`{r top-products}
top_products <- head(
  aggregate(revenue ~ product, data, sum),
  10
)
top_products <- top_products[order(-top_products$revenue), ]
knitr::kable(top_products, format.args = list(big.mark = ","))
\`\`\`

## Summary Statistics

\`\`\`{r stats}
stats <- data.frame(
  Metric = c("Total Orders", "Avg Order Value", "Max Order",
             "Min Order", "Std Dev"),
  Value = c(
    nrow(data),
    round(mean(data$revenue), 2),
    round(max(data$revenue), 2),
    round(min(data$revenue), 2),
    round(sd(data$revenue), 2)
  )
)
knitr::kable(stats, format.args = list(big.mark = ","))
\`\`\`

---

*This report was automatically generated using staRburst parallel processing.*
'

# Save template to file
writeLines(report_template, "report_template.Rmd")
```

## Generate Sample Data

Create synthetic customer data:

``` r
# Function to generate data for one customer
generate_customer_data <- function(customer_id) {
  set.seed(customer_id)

  n_transactions <- sample(100:500, 1)
  dates <- sort(sample(seq.Date(
    from = as.Date("2026-01-01"),
    to = as.Date("2026-01-31"),
    by = "day"
  ), n_transactions, replace = TRUE))

  products <- c("Product A", "Product B", "Product C",
                "Product D", "Product E")

  data.frame(
    customer_id = customer_id,
    date = dates,
    product = sample(products, n_transactions, replace = TRUE),
    revenue = round(rnorm(n_transactions, mean = 150, sd = 50), 2),
    stringsAsFactors = FALSE
  )
}

# Generate customer list
n_customers <- 50
customers <- data.frame(
  customer_id = sprintf("CUST%03d", 1:n_customers),
  customer_name = paste("Company", LETTERS[1:n_customers %% 26 + 1],
                       (1:n_customers %/% 26) + 1),
  stringsAsFactors = FALSE
)

head(customers)
```

## Report Generation Function

Define function to generate one report:

``` r
generate_report <- function(customer_info) {
  customer_id <- customer_info$customer_id
  customer_name <- customer_info$customer_name

  # Generate data for this customer
  data <- generate_customer_data(as.numeric(gsub("CUST", "", customer_id)))

  # Output file path
  output_file <- sprintf("report_%s.html", customer_id)

  tryCatch({
    # Render report
    rmarkdown::render(
      input = "report_template.Rmd",
      output_file = output_file,
      params = list(
        customer_id = customer_id,
        customer_name = customer_name,
        month = "January 2026",
        data = data
      ),
      quiet = TRUE
    )

    list(
      customer_id = customer_id,
      success = TRUE,
      output_file = output_file,
      file_size = file.size(output_file),
      render_time = Sys.time()
    )
  }, error = function(e) {
    list(
      customer_id = customer_id,
      success = FALSE,
      error = as.character(e),
      render_time = Sys.time()
    )
  })
}
```

## Local Execution

Test with a few reports locally:

``` r
# Test with 5 reports
test_customers <- head(customers, 5)

cat(sprintf("Rendering %d reports locally...\n", nrow(test_customers)))
local_start <- Sys.time()

local_results <- lapply(
  split(test_customers, 1:nrow(test_customers)),
  generate_report
)

local_time <- as.numeric(difftime(Sys.time(), local_start, units = "secs"))

cat(sprintf("✓ Completed in %.1f seconds\n", local_time))
cat(sprintf("  Average: %.1f seconds per report\n", local_time / 5))
cat(sprintf("  Estimated time for %d reports: %.1f minutes\n\n",
            n_customers, (local_time / 5 * n_customers) / 60))
```

**Typical output**:

    Rendering 5 reports locally...
    ✓ Completed in 23.4 seconds
      Average: 4.7 seconds per report
      Estimated time for 50 reports: 3.9 minutes

## Cloud Execution with staRburst

Render all reports in parallel:

``` r
cat(sprintf("Rendering %d reports on AWS...\n", n_customers))

# Convert data frame rows to list for starburst_map
customer_list <- split(customers, 1:nrow(customers))

results <- starburst_map(
  customer_list,
  generate_report,
  workers = 25,
  cpu = 2,
  memory = "4GB"
)
```

**Typical output**:

    🚀 Starting starburst cluster with 25 workers
    💰 Estimated cost: ~$2.00/hour
    📊 Processing 50 items with 25 workers
    📦 Created 25 chunks (avg 2 items per chunk)
    🚀 Submitting tasks...
    ✓ Submitted 25 tasks
    ⏳ Progress: 25/25 tasks (0.4 minutes elapsed)

    ✓ Completed in 0.4 minutes
    💰 Actual cost: $0.01

## Results Processing

Analyze the generation results:

``` r
# Check success rate
success_count <- sum(sapply(results, function(x) x$success))
failure_count <- sum(!sapply(results, function(x) x$success))

cat("\n=== Report Generation Summary ===\n\n")
cat(sprintf("Total reports: %d\n", length(results)))
cat(sprintf("Successfully generated: %d (%.1f%%)\n",
            success_count, (success_count / length(results)) * 100))
cat(sprintf("Failed: %d\n\n", failure_count))

# File size summary
successful_results <- results[sapply(results, function(x) x$success)]
file_sizes <- sapply(successful_results, function(x) x$file_size)

cat("File size statistics:\n")
cat(sprintf("  Total size: %.2f MB\n", sum(file_sizes) / 1024^2))
cat(sprintf("  Average size: %.1f KB\n", mean(file_sizes) / 1024))
cat(sprintf("  Range: %.1f - %.1f KB\n\n",
            min(file_sizes) / 1024, max(file_sizes) / 1024))

# Show sample of generated reports
cat("Generated reports:\n")
report_files <- sapply(successful_results[1:10], function(x) x$output_file)
print(report_files)
```

**Typical output**:

    === Report Generation Summary ===

    Total reports: 50
    Successfully generated: 50 (100.0%)
    Failed: 0

    File size statistics:
      Total size: 2.45 MB
      Average size: 50.2 KB
      Range: 45.3 - 55.8 KB

    Generated reports:
     [1] "report_CUST001.html" "report_CUST002.html"
     [3] "report_CUST003.html" "report_CUST004.html"
     [5] "report_CUST005.html" "report_CUST006.html"
     [7] "report_CUST007.html" "report_CUST008.html"
     [9] "report_CUST009.html" "report_CUST010.html"

## Performance Comparison

| Method    | Reports         | Time    | Cost    | Speedup |
|-----------|-----------------|---------|---------|---------|
| Local     | 50              | 3.9 min | \$0     | 1x      |
| staRburst | 50 (10 workers) | 1.2 min | \$0.004 | 3.3x    |
| staRburst | 50 (25 workers) | 0.4 min | \$0.01  | 9.8x    |
| staRburst | 50 (50 workers) | 0.3 min | \$0.02  | 13x     |

**Key Insights**: - Near-linear scaling with worker count - Sweet spot:
25-50 workers for this workload - Minimal cost (\$0.01) for significant
time savings - Can easily scale to 500+ reports

## Advanced: Custom Report Distribution

Automatically distribute reports after generation:

``` r
generate_and_distribute <- function(customer_info) {
  # Generate report
  result <- generate_report(customer_info)

  if (result$success) {
    # Upload to S3 (example)
    tryCatch({
      # paws::s3()$put_object(
      #   Bucket = "my-reports-bucket",
      #   Key = sprintf("reports/2026-01/%s", result$output_file),
      #   Body = readBin(result$output_file, "raw",
      #                  file.size(result$output_file))
      # )

      result$uploaded <- TRUE
      result$s3_url <- sprintf("s3://my-reports-bucket/reports/2026-01/%s",
                              result$output_file)
    }, error = function(e) {
      result$uploaded <- FALSE
      result$upload_error <- as.character(e)
    })
  }

  result
}
```

## When to Use This Pattern

**Good fit**: - Many independent reports (\> 10) - Report rendering
takes \> 30 seconds - Time-sensitive delivery requirements - CPU or I/O
intensive rendering

**Not ideal**: - Very simple reports (\< 10 seconds to render) - Reports
with shared state or dependencies - Interactive report generation -
Real-time reporting

## Running the Full Example

The complete runnable script is available at:

``` r
system.file("examples/reports.R", package = "starburst")
```

Run it with:

``` r
source(system.file("examples/reports.R", package = "starburst"))
```

## Next Steps

- Use real customer data from database
- Add more complex visualizations
- Implement automated email distribution
- Create PDF reports instead of HTML
- Add report templating system
- Schedule monthly report generation

**Related examples**: - [API
Calls](https://starburst.ing/articles/example-api-calls.md) - Another
I/O-bound parallel task - [Feature
Engineering](https://starburst.ing/articles/example-feature-engineering.md) -
Data processing patterns
