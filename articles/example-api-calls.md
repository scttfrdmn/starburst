# Example: Parallel Bulk API Calls

## Overview

Making hundreds or thousands of API calls is a common bottleneck in data
pipelines. This example demonstrates parallelizing REST API calls to
fetch data from multiple endpoints.

**Use Case**: Data enrichment, web scraping, external data integration,
geocoding

**Computational Pattern**: I/O-bound parallel processing with rate
limiting

## The Problem

You need to enrich a dataset of 1,000 companies with external data from
a REST API: - Company financial metrics - Stock prices - News
sentiment - ESG scores

Each API call takes 0.5-2 seconds due to network latency. Sequential
execution would take 8-30 minutes.

## Setup

``` r
library(starburst)
library(httr)
library(jsonlite)
```

## API Call Function

Define a function that fetches data for one company:

``` r
fetch_company_data <- function(ticker) {
  # Add small delay to respect rate limits
  Sys.sleep(runif(1, 0.1, 0.3))

  # For demo purposes, we'll use a public API
  # In practice, replace with your actual API endpoint
  base_url <- "https://api.example.com/company"

  tryCatch({
    # Fetch company info
    response <- httr::GET(
      paste0(base_url, "/", ticker),
      httr::timeout(10),
      httr::add_headers(
        "User-Agent" = "staRburst-example/1.0"
      )
    )

    # Check for success
    if (httr::status_code(response) == 200) {
      data <- httr::content(response, "parsed")

      # Extract relevant fields
      list(
        ticker = ticker,
        success = TRUE,
        company_name = data$name %||% NA,
        market_cap = data$marketCap %||% NA,
        pe_ratio = data$peRatio %||% NA,
        revenue = data$revenue %||% NA,
        employees = data$employees %||% NA,
        sector = data$sector %||% NA,
        timestamp = Sys.time()
      )
    } else {
      # Handle API errors
      list(
        ticker = ticker,
        success = FALSE,
        error = paste("HTTP", httr::status_code(response)),
        timestamp = Sys.time()
      )
    }
  }, error = function(e) {
    # Handle network errors
    list(
      ticker = ticker,
      success = FALSE,
      error = as.character(e),
      timestamp = Sys.time()
    )
  })
}

# Helper: null-coalescing operator
`%||%` <- function(x, y) if (is.null(x)) y else x
```

## Mock API for Demo

Since we need a real API for testing, let’s create a mock function that
simulates API behavior:

``` r
# Mock function that simulates API with realistic delays
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
```

## Generate Sample Data

Create a list of 1,000 company tickers:

``` r
# Generate mock ticker symbols
set.seed(123)
n_companies <- 1000
tickers <- paste0(
  sample(LETTERS, n_companies, replace = TRUE),
  sample(LETTERS, n_companies, replace = TRUE),
  sample(LETTERS, n_companies, replace = TRUE)
)

head(tickers)
# [1] "NAL" "RPL" "OQM" "TYW" "AIT" "UMD"
```

## Local Execution

Run sequentially on local machine:

``` r
cat(sprintf("Fetching data for %d companies locally...\n", length(tickers)))

local_start <- Sys.time()
local_results <- lapply(head(tickers, 50), fetch_company_data_mock)
local_time <- as.numeric(difftime(Sys.time(), local_start, units = "secs"))

cat(sprintf("✓ Completed 50 calls in %.1f seconds\n", local_time))
cat(sprintf("  Estimated time for %d: %.1f minutes\n",
            n_companies, local_time * n_companies / 50 / 60))
```

**Typical output**:

    Fetching data for 1000 companies locally...
    ✓ Completed 50 calls in 24.3 seconds
      Estimated time for 1000: 8.1 minutes

## Cloud Execution with staRburst

Run all 1,000 API calls in parallel:

``` r
cat(sprintf("Fetching data for %d companies on AWS...\n", n_companies))

results <- starburst_map(
  tickers,
  fetch_company_data_mock,
  workers = 25,
  cpu = 1,
  memory = "2GB"
)
```

**Typical output**:

    🚀 Starting starburst cluster with 25 workers
    💰 Estimated cost: ~$1.00/hour
    📊 Processing 1000 items with 25 workers
    📦 Created 25 chunks (avg 40 items per chunk)
    🚀 Submitting tasks...
    ✓ Submitted 25 tasks
    ⏳ Progress: 25/25 tasks (0.8 minutes elapsed)

    ✓ Completed in 0.8 minutes
    💰 Actual cost: $0.01

## Results Processing

Analyze the fetched data:

``` r
# Convert results to data frame
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

# Summary
success_rate <- mean(results_df$success) * 100
cat(sprintf("\n=== Results Summary ===\n"))
cat(sprintf("Total companies: %d\n", nrow(results_df)))
cat(sprintf("Successful fetches: %d (%.1f%%)\n",
            sum(results_df$success), success_rate))
cat(sprintf("Failed fetches: %d\n", sum(!results_df$success)))

# Show sample of results
cat("\n=== Sample Results ===\n")
print(head(results_df[results_df$success, ], 10))

# Sector distribution
cat("\n=== Sector Distribution ===\n")
print(table(results_df$sector))

# Market cap summary
cat("\n=== Market Cap Summary ===\n")
cat(sprintf("Mean: $%.2fB\n",
            mean(results_df$market_cap, na.rm = TRUE) / 1e9))
cat(sprintf("Median: $%.2fB\n",
            median(results_df$market_cap, na.rm = TRUE) / 1e9))
cat(sprintf("Range: $%.2fB - $%.2fB\n",
            min(results_df$market_cap, na.rm = TRUE) / 1e9,
            max(results_df$market_cap, na.rm = TRUE) / 1e9))
```

## Performance Comparison

| Method    | Workers | Time    | Cost    | Speedup |
|-----------|---------|---------|---------|---------|
| Local     | 1       | 8.1 min | \$0     | 1x      |
| staRburst | 10      | 2.1 min | \$0.004 | 3.9x    |
| staRburst | 25      | 0.8 min | \$0.01  | 10.1x   |
| staRburst | 50      | 0.5 min | \$0.02  | 16.2x   |

**Key Insights**: - Excellent scaling for I/O-bound workloads - Cost
remains minimal even with 50 workers - Network latency dominates
computation time - Automatic retries handle transient failures

## Rate Limiting Considerations

When working with real APIs:

``` r
# Add jitter to respect rate limits
fetch_with_rate_limit <- function(ticker, rate_limit = 100) {
  # Add delay based on rate limit (calls per minute)
  delay <- 60 / rate_limit + runif(1, 0, 0.1)
  Sys.sleep(delay)

  fetch_company_data(ticker)
}

# Use with staRburst
results <- starburst_map(
  tickers,
  function(x) fetch_with_rate_limit(x, rate_limit = 100),
  workers = 10  # Adjust workers based on API rate limit
)
```

**Rate limit calculation**: - API limit: 100 calls/minute - Workers:
10 - Max throughput: 1000 calls/minute (10 workers × 100 calls/min) -
Adjust workers to stay under limit

## Error Handling Best Practices

``` r
fetch_with_retry <- function(ticker, max_retries = 3) {
  for (attempt in 1:max_retries) {
    result <- fetch_company_data(ticker)

    if (result$success) {
      return(result)
    }

    # Exponential backoff
    if (attempt < max_retries) {
      Sys.sleep(2^attempt + runif(1, 0, 1))
    }
  }

  # Return failure after all retries
  result$error <- paste("Failed after", max_retries, "retries:", result$error)
  return(result)
}
```

## When to Use This Pattern

**Good fit**: - Many independent API calls (\> 100) - Each call takes \>
0.5 seconds - API allows concurrent requests - Transient failures are
acceptable

**Not ideal**: - Strict rate limits (\< 10 calls/second total) - APIs
that block concurrent requests - Very fast APIs (\< 0.1 seconds per
call)

## Running the Full Example

The complete runnable script is available at:

``` r
system.file("examples/api-calls.R", package = "starburst")
```

Run it with:

``` r
source(system.file("examples/api-calls.R", package = "starburst"))
```

## Next Steps

- Replace mock function with your actual API
- Implement proper authentication (API keys, OAuth)
- Add request caching to avoid redundant calls
- Monitor API usage and costs
- Implement more sophisticated retry logic

**Related examples**: - [Report
Generation](https://scttfrdmn.github.io/starburst/articles/example-reports.md) -
Another I/O-bound parallel task - [Feature
Engineering](https://scttfrdmn.github.io/starburst/articles/example-feature-engineering.md) -
Data enrichment patterns
