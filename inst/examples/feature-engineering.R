#!/usr/bin/env Rscript
#
# Parallel Feature Engineering Example
#
# This script demonstrates parallel feature computation across customer segments.
# It processes 100,000 transactions to generate engineered features for ML.
#
# Usage:
#   Rscript feature-engineering.R
#   # or from R:
#   source(system.file("examples/feature-engineering.R", package = "starburst"))

library(starburst)

cat("=== Parallel Feature Engineering ===\n\n")

# Generate synthetic transaction data
set.seed(123)

n_customers <- 5000
n_transactions <- 100000

cat(sprintf("Generating %s transactions for %s customers...\n",
            format(n_transactions, big.mark = ","),
            format(n_customers, big.mark = ",")))

transactions <- data.frame(
  customer_id = sample(1:n_customers, n_transactions, replace = TRUE),
  transaction_date = as.Date("2023-01-01") + sample(0:364, n_transactions, replace = TRUE),
  amount = exp(rnorm(n_transactions, log(50), 0.8)),
  category = sample(c("groceries", "electronics", "clothing", "restaurants", "other"),
                   n_transactions, replace = TRUE, prob = c(0.4, 0.1, 0.2, 0.2, 0.1)),
  payment_method = sample(c("credit", "debit", "cash"), n_transactions, replace = TRUE),
  is_online = sample(c(TRUE, FALSE), n_transactions, replace = TRUE, prob = c(0.3, 0.7)),
  stringsAsFactors = FALSE
)

transactions <- transactions[order(transactions$customer_id, transactions$transaction_date), ]

cat(sprintf("✓ Generated dataset\n"))
cat(sprintf("  Date range: %s to %s\n\n",
            min(transactions$transaction_date),
            max(transactions$transaction_date)))

# Feature engineering function
engineer_features <- function(customer_ids, transactions_data) {
  customer_data <- transactions_data[transactions_data$customer_id %in% customer_ids, ]

  if (nrow(customer_data) == 0) {
    return(NULL)
  }

  customer_data <- customer_data[order(customer_data$customer_id,
                                      customer_data$transaction_date), ]

  features_list <- lapply(customer_ids, function(cid) {
    cust_txn <- customer_data[customer_data$customer_id == cid, ]

    if (nrow(cust_txn) == 0) {
      return(NULL)
    }

    # Basic statistics
    total_transactions <- nrow(cust_txn)
    total_spend <- sum(cust_txn$amount)
    avg_transaction <- mean(cust_txn$amount)

    # Time-based features
    first_purchase <- min(cust_txn$transaction_date)
    last_purchase <- max(cust_txn$transaction_date)
    days_active <- as.numeric(difftime(last_purchase, first_purchase, units = "days"))
    purchase_frequency <- if (days_active > 0) total_transactions / days_active else 0

    # Rolling statistics (last 30 days)
    recent_cutoff <- last_purchase - 30
    recent_txn <- cust_txn[cust_txn$transaction_date > recent_cutoff, ]
    recent_spend <- if (nrow(recent_txn) > 0) sum(recent_txn$amount) else 0
    recent_count <- nrow(recent_txn)

    # Category preferences
    category_counts <- table(cust_txn$category)
    favorite_category <- names(category_counts)[which.max(category_counts)]
    category_diversity <- length(unique(cust_txn$category))

    # Payment behavior
    online_pct <- mean(cust_txn$is_online) * 100
    credit_pct <- mean(cust_txn$payment_method == "credit") * 100

    # Volatility metrics
    amount_sd <- sd(cust_txn$amount)
    amount_cv <- amount_sd / avg_transaction

    # Time patterns
    weekday <- as.POSIXlt(cust_txn$transaction_date)$wday
    weekend_pct <- mean(weekday %in% c(0, 6)) * 100

    # RFM features
    recency <- as.numeric(difftime(as.Date("2024-01-01"), last_purchase, units = "days"))

    data.frame(
      customer_id = cid,
      total_transactions = total_transactions,
      total_spend = total_spend,
      avg_transaction = avg_transaction,
      days_active = days_active,
      purchase_frequency = purchase_frequency,
      recent_spend_30d = recent_spend,
      recent_count_30d = recent_count,
      favorite_category = favorite_category,
      category_diversity = category_diversity,
      online_pct = online_pct,
      credit_pct = credit_pct,
      amount_sd = amount_sd,
      amount_cv = amount_cv,
      weekend_pct = weekend_pct,
      recency_days = recency,
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, features_list[!sapply(features_list, is.null)])
}

# Local benchmark (500 customers)
cat("Running local benchmark (500 customers)...\n")
set.seed(456)
sample_customers <- sample(unique(transactions$customer_id), 500)

local_start <- Sys.time()
local_features <- engineer_features(sample_customers, transactions)
local_time <- as.numeric(difftime(Sys.time(), local_start, units = "secs"))

cat(sprintf("✓ Completed in %.2f seconds\n", local_time))
cat(sprintf("  Generated %d features per customer\n", ncol(local_features) - 1))
cat(sprintf("  Estimated time for all %s customers: %.1f seconds\n\n",
            format(n_customers, big.mark = ","),
            local_time * (n_customers / 500)))

# Cloud execution
all_customers <- unique(transactions$customer_id)
n_workers <- 20

cat(sprintf("Processing features for %s customers on %d workers...\n",
            format(length(all_customers), big.mark = ","),
            n_workers))

# Create chunks
chunk_size <- ceiling(length(all_customers) / n_workers)
customer_chunks <- split(all_customers,
                        ceiling(seq_along(all_customers) / chunk_size))

cloud_start <- Sys.time()

results <- starburst_map(
  customer_chunks,
  engineer_features,
  transactions_data = transactions,
  workers = n_workers,
  cpu = 2,
  memory = "4GB"
)

cloud_time <- as.numeric(difftime(Sys.time(), cloud_start, units = "secs"))

cat(sprintf("\n✓ Completed in %.1f seconds\n\n", cloud_time))

# Combine results
features <- do.call(rbind, results)

# Print results
cat("=== Feature Engineering Results ===\n\n")
cat(sprintf("Total customers processed: %s\n",
            format(nrow(features), big.mark = ",")))
cat(sprintf("Features per customer: %d\n\n", ncol(features) - 1))

# Summary statistics
cat("=== Feature Summary Statistics ===\n\n")
cat(sprintf("Average transactions per customer: %.1f\n",
            mean(features$total_transactions)))
cat(sprintf("Average total spend: $%.2f\n",
            mean(features$total_spend)))
cat(sprintf("Average transaction value: $%.2f\n\n",
            mean(features$avg_transaction)))

cat(sprintf("Most common category: %s\n",
            names(sort(table(features$favorite_category), decreasing = TRUE)[1])))
cat(sprintf("Average category diversity: %.1f categories\n\n",
            mean(features$category_diversity)))

cat(sprintf("Average online purchase rate: %.1f%%\n",
            mean(features$online_pct)))
cat(sprintf("Average credit card usage: %.1f%%\n\n",
            mean(features$credit_pct)))

cat(sprintf("Mean purchase frequency: %.3f transactions/day\n",
            mean(features$purchase_frequency, na.rm = TRUE)))
cat(sprintf("Mean recency: %.0f days since last purchase\n\n",
            mean(features$recency_days)))

# High-value segment
high_value <- features[features$total_spend > quantile(features$total_spend, 0.9), ]
cat("=== Top 10% Customers (by spend) ===\n")
cat(sprintf("Count: %d customers\n", nrow(high_value)))
cat(sprintf("Average total spend: $%.2f\n", mean(high_value$total_spend)))
cat(sprintf("Average transactions: %.1f\n", mean(high_value$total_transactions)))
cat(sprintf("Average online rate: %.1f%%\n\n", mean(high_value$online_pct)))

# Performance comparison
cat("=== Performance Comparison ===\n\n")
estimated_local <- local_time * (n_customers / 500)
speedup <- estimated_local / cloud_time
cat(sprintf("Local (estimated): %.1f seconds\n", estimated_local))
cat(sprintf("Cloud (%d workers): %.1f seconds\n", n_workers, cloud_time))
cat(sprintf("Speedup: %.1fx\n", speedup))

cat("\n✓ Done!\n")
