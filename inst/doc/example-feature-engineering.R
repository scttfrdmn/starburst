## ----include = FALSE----------------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>"
)

## ----setup, eval=FALSE--------------------------------------------------------
# library(starburst)
# library(dplyr)

## ----data, eval=FALSE---------------------------------------------------------
# set.seed(123)
# 
# # Generate 100,000 transactions for 5,000 customers
# n_customers <- 5000
# n_transactions <- 100000
# 
# transactions <- data.frame(
#   customer_id = sample(1:n_customers, n_transactions, replace = TRUE),
#   transaction_date = as.Date("2023-01-01") + sample(0:364, n_transactions, replace = TRUE),
#   amount = exp(rnorm(n_transactions, log(50), 0.8)),  # Log-normal distribution
#   category = sample(c("groceries", "electronics", "clothing", "restaurants", "other"),
#                    n_transactions, replace = TRUE, prob = c(0.4, 0.1, 0.2, 0.2, 0.1)),
#   payment_method = sample(c("credit", "debit", "cash"), n_transactions, replace = TRUE),
#   is_online = sample(c(TRUE, FALSE), n_transactions, replace = TRUE, prob = c(0.3, 0.7))
# )
# 
# # Sort by customer and date
# transactions <- transactions[order(transactions$customer_id, transactions$transaction_date), ]
# 
# cat(sprintf("Dataset: %s transactions for %s customers\n",
#             format(nrow(transactions), big.mark = ","),
#             format(length(unique(transactions$customer_id)), big.mark = ",")))
# cat(sprintf("Date range: %s to %s\n",
#             min(transactions$transaction_date),
#             max(transactions$transaction_date)))

## ----features-fn, eval=FALSE--------------------------------------------------
# engineer_features <- function(customer_ids, transactions_data) {
#   # Filter to specified customers
#   customer_data <- transactions_data[transactions_data$customer_id %in% customer_ids, ]
# 
#   if (nrow(customer_data) == 0) {
#     return(NULL)
#   }
# 
#   # Sort by customer and date
#   customer_data <- customer_data[order(customer_data$customer_id,
#                                       customer_data$transaction_date), ]
# 
#   # Compute features for each customer
#   features_list <- lapply(customer_ids, function(cid) {
#     cust_txn <- customer_data[customer_data$customer_id == cid, ]
# 
#     if (nrow(cust_txn) == 0) {
#       return(NULL)
#     }
# 
#     # Basic statistics
#     total_transactions <- nrow(cust_txn)
#     total_spend <- sum(cust_txn$amount)
#     avg_transaction <- mean(cust_txn$amount)
# 
#     # Time-based features
#     first_purchase <- min(cust_txn$transaction_date)
#     last_purchase <- max(cust_txn$transaction_date)
#     days_active <- as.numeric(difftime(last_purchase, first_purchase, units = "days"))
#     purchase_frequency <- if (days_active > 0) total_transactions / days_active else 0
# 
#     # Rolling statistics (last 30 days)
#     recent_cutoff <- last_purchase - 30
#     recent_txn <- cust_txn[cust_txn$transaction_date > recent_cutoff, ]
#     recent_spend <- if (nrow(recent_txn) > 0) sum(recent_txn$amount) else 0
#     recent_count <- nrow(recent_txn)
# 
#     # Category preferences
#     category_counts <- table(cust_txn$category)
#     favorite_category <- names(category_counts)[which.max(category_counts)]
#     category_diversity <- length(unique(cust_txn$category))
# 
#     # Payment behavior
#     online_pct <- mean(cust_txn$is_online) * 100
#     credit_pct <- mean(cust_txn$payment_method == "credit") * 100
# 
#     # Volatility metrics
#     amount_sd <- sd(cust_txn$amount)
#     amount_cv <- amount_sd / avg_transaction  # Coefficient of variation
# 
#     # Time patterns
#     weekday <- as.POSIXlt(cust_txn$transaction_date)$wday
#     weekend_pct <- mean(weekday %in% c(0, 6)) * 100
# 
#     # RFM features (Recency, Frequency, Monetary)
#     recency <- as.numeric(difftime(as.Date("2024-01-01"), last_purchase, units = "days"))
# 
#     data.frame(
#       customer_id = cid,
#       total_transactions = total_transactions,
#       total_spend = total_spend,
#       avg_transaction = avg_transaction,
#       days_active = days_active,
#       purchase_frequency = purchase_frequency,
#       recent_spend_30d = recent_spend,
#       recent_count_30d = recent_count,
#       favorite_category = favorite_category,
#       category_diversity = category_diversity,
#       online_pct = online_pct,
#       credit_pct = credit_pct,
#       amount_sd = amount_sd,
#       amount_cv = amount_cv,
#       weekend_pct = weekend_pct,
#       recency_days = recency,
#       stringsAsFactors = FALSE
#     )
#   })
# 
#   # Combine results
#   do.call(rbind, features_list[!sapply(features_list, is.null)])
# }

## ----local, eval=FALSE--------------------------------------------------------
# # Process 500 customers locally
# set.seed(456)
# sample_customers <- sample(unique(transactions$customer_id), 500)
# 
# cat(sprintf("Processing features for %d customers locally...\n", length(sample_customers)))
# local_start <- Sys.time()
# 
# local_features <- engineer_features(sample_customers, transactions)
# 
# local_time <- as.numeric(difftime(Sys.time(), local_start, units = "secs"))
# 
# cat(sprintf("✓ Completed in %.2f seconds\n", local_time))
# cat(sprintf("  Generated %d features per customer\n", ncol(local_features) - 1))
# cat(sprintf("  Estimated time for all %s customers: %.1f minutes\n",
#             format(n_customers, big.mark = ","),
#             local_time * (n_customers / 500) / 60))

## ----cloud, eval=FALSE--------------------------------------------------------
# # Split customers into chunks
# all_customers <- unique(transactions$customer_id)
# n_workers <- 20
# 
# cat(sprintf("Processing features for %s customers on %d workers...\n",
#             format(length(all_customers), big.mark = ","),
#             n_workers))
# 
# # Create chunks of customer IDs
# chunk_size <- ceiling(length(all_customers) / n_workers)
# customer_chunks <- split(all_customers,
#                         ceiling(seq_along(all_customers) / chunk_size))
# 
# cloud_start <- Sys.time()
# 
# # Process chunks in parallel
# results <- starburst_map(
#   customer_chunks,
#   engineer_features,
#   transactions_data = transactions,
#   workers = n_workers,
#   cpu = 2,
#   memory = "4GB"
# )
# 
# cloud_time <- as.numeric(difftime(Sys.time(), cloud_start, units = "secs"))
# 
# cat(sprintf("\n✓ Completed in %.1f seconds\n", cloud_time))
# 
# # Combine results
# features <- do.call(rbind, results)

## ----analysis, eval=FALSE-----------------------------------------------------
# cat("\n=== Feature Engineering Results ===\n\n")
# cat(sprintf("Total customers processed: %s\n",
#             format(nrow(features), big.mark = ",")))
# cat(sprintf("Features generated per customer: %d\n", ncol(features) - 1))
# cat(sprintf("\nFeature names:\n"))
# print(names(features)[names(features) != "customer_id"])
# 
# # Summary statistics
# cat("\n=== Feature Summary Statistics ===\n\n")
# cat(sprintf("Average transactions per customer: %.1f\n",
#             mean(features$total_transactions)))
# cat(sprintf("Average total spend: $%.2f\n",
#             mean(features$total_spend)))
# cat(sprintf("Average transaction value: $%.2f\n",
#             mean(features$avg_transaction)))
# cat(sprintf("\nMost common category: %s\n",
#             names(sort(table(features$favorite_category), decreasing = TRUE)[1])))
# cat(sprintf("Average category diversity: %.1f categories\n",
#             mean(features$category_diversity)))
# cat(sprintf("\nAverage online purchase rate: %.1f%%\n",
#             mean(features$online_pct)))
# cat(sprintf("Average credit card usage: %.1f%%\n",
#             mean(features$credit_pct)))
# cat(sprintf("\nMean purchase frequency: %.3f transactions/day\n",
#             mean(features$purchase_frequency, na.rm = TRUE)))
# cat(sprintf("Mean recency: %.0f days since last purchase\n",
#             mean(features$recency_days)))
# 
# # Identify high-value segments
# high_value <- features[features$total_spend > quantile(features$total_spend, 0.9), ]
# cat(sprintf("\n=== Top 10%% Customers (by spend) ===\n"))
# cat(sprintf("Count: %d customers\n", nrow(high_value)))
# cat(sprintf("Average total spend: $%.2f\n", mean(high_value$total_spend)))
# cat(sprintf("Average transactions: %.1f\n", mean(high_value$total_transactions)))
# cat(sprintf("Average online rate: %.1f%%\n", mean(high_value$online_pct)))

## ----ml-features, eval=FALSE--------------------------------------------------
# engineer_ml_features <- function(customer_ids, transactions_data) {
#   base_features <- engineer_features(customer_ids, transactions_data)
# 
#   if (is.null(base_features)) {
#     return(NULL)
#   }
# 
#   # Add derived features for ML
#   base_features$clv_estimate <- base_features$avg_transaction *
#                                  base_features$purchase_frequency * 365
#   base_features$engagement_score <- scale(base_features$total_transactions) +
#                                     scale(base_features$category_diversity)
#   base_features$recency_score <- -scale(base_features$recency_days)
#   base_features$is_high_value <- base_features$total_spend >
#                                   median(base_features$total_spend)
#   base_features$purchase_momentum <- base_features$recent_count_30d /
#                                      (base_features$total_transactions + 1)
# 
#   base_features
# }
# 
# # Process with enhanced features
# ml_results <- starburst_map(
#   customer_chunks,
#   engineer_ml_features,
#   transactions_data = transactions,
#   workers = 20,
#   cpu = 2,
#   memory = "4GB"
# )
# 
# ml_features <- do.call(rbind, ml_results)

## ----eval=FALSE---------------------------------------------------------------
# system.file("examples/feature-engineering.R", package = "starburst")

## ----eval=FALSE---------------------------------------------------------------
# source(system.file("examples/feature-engineering.R", package = "starburst"))

