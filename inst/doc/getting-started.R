## ----setup, include = FALSE---------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>",
  eval = FALSE
)

## -----------------------------------------------------------------------------
# # Install from GitHub
# remotes::install_github("yourname/starburst")

## -----------------------------------------------------------------------------
# library(starburst)
# 
# # Interactive setup wizard (takes ~2 minutes)
# starburst_setup()

## -----------------------------------------------------------------------------
# library(furrr)
# library(starburst)
# 
# # Define your work
# expensive_simulation <- function(i) {
#   # Some computation that takes a few minutes
#   results <- replicate(1000, {
#     x <- rnorm(10000)
#     mean(x^2)
#   })
#   mean(results)
# }
# 
# # Local execution (single core)
# plan(sequential)
# system.time({
#   results_local <- future_map(1:100, expensive_simulation)
# })
# #> ~16 minutes on typical laptop
# 
# # Cloud execution (50 workers)
# plan(future_starburst, workers = 50)
# system.time({
#   results_cloud <- future_map(1:100, expensive_simulation)
# })
# #> ~2 minutes (including 45s startup)
# #> Cost: ~$0.85
# 
# # Results are identical
# identical(results_local, results_cloud)
# #> [1] TRUE

## -----------------------------------------------------------------------------
# library(starburst)
# library(furrr)
# 
# # Simulate portfolio returns
# simulate_portfolio <- function(seed) {
#   set.seed(seed)
# 
#   # Random walk for 252 trading days
#   returns <- rnorm(252, mean = 0.0003, sd = 0.02)
#   prices <- cumprod(1 + returns)
# 
#   list(
#     final_value = prices[252],
#     max_drawdown = max(cummax(prices) - prices) / max(prices),
#     sharpe_ratio = mean(returns) / sd(returns) * sqrt(252)
#   )
# }
# 
# # Run 10,000 simulations on 100 workers
# plan(future_starburst, workers = 100)
# 
# results <- future_map(1:10000, simulate_portfolio, .options = furrr_options(seed = TRUE))
# 
# # Analyze results
# final_values <- sapply(results, `[[`, "final_value")
# hist(final_values, breaks = 50, main = "Distribution of Portfolio Final Values")
# 
# # 95% confidence interval
# quantile(final_values, c(0.025, 0.975))

## -----------------------------------------------------------------------------
# library(starburst)
# library(furrr)
# 
# # Your data
# data <- read.csv("my_data.csv")
# 
# # Bootstrap function
# bootstrap_regression <- function(i, data) {
#   # Resample with replacement
#   boot_indices <- sample(nrow(data), replace = TRUE)
#   boot_data <- data[boot_indices, ]
# 
#   # Fit model
#   model <- lm(y ~ x1 + x2 + x3, data = boot_data)
# 
#   # Return coefficients
#   coef(model)
# }
# 
# # Run 10,000 bootstrap samples
# plan(future_starburst, workers = 50)
# 
# boot_results <- future_map(1:10000, bootstrap_regression, data = data)
# 
# # Convert to matrix
# boot_coefs <- do.call(rbind, boot_results)
# 
# # 95% confidence intervals for each coefficient
# apply(boot_coefs, 2, quantile, probs = c(0.025, 0.975))

## -----------------------------------------------------------------------------
# library(starburst)
# library(furrr)
# 
# # Process one sample
# process_sample <- function(sample_id) {
#   # Read from S3 (data already in cloud)
#   fastq_path <- sprintf("s3://my-genomics-data/samples/%s.fastq", sample_id)
#   data <- read_fastq(fastq_path)
# 
#   # Align reads
#   aligned <- align_reads(data, reference = "hg38")
# 
#   # Call variants
#   variants <- call_variants(aligned)
# 
#   # Return summary
#   list(
#     sample_id = sample_id,
#     num_variants = nrow(variants),
#     variants = variants
#   )
# }
# 
# # Process 1000 samples on 100 workers
# sample_ids <- list.files("s3://my-genomics-data/samples/", pattern = ".fastq$")
# 
# plan(future_starburst, workers = 100)
# 
# results <- future_map(sample_ids, process_sample, .progress = TRUE)
# 
# # Combine results
# all_variants <- do.call(rbind, lapply(results, `[[`, "variants"))

## -----------------------------------------------------------------------------
# plan(future_starburst, workers = 50)
# 
# results <- future_map(file_list, function(file) {
#   # Workers read directly from S3
#   data <- read.csv(sprintf("s3://my-bucket/%s", file))
#   process(data)
# })

## -----------------------------------------------------------------------------
# # Load data locally
# data <- read.csv("local_file.csv")
# 
# # staRburst automatically uploads to S3 and distributes
# plan(future_starburst, workers = 50)
# 
# results <- future_map(1:1000, function(i) {
#   # Each worker gets a copy of 'data'
#   bootstrap_analysis(data, i)
# })

## -----------------------------------------------------------------------------
# # Upload once
# large_data <- read.csv("huge_file.csv")
# s3_path <- starburst_upload(large_data, "s3://my-bucket/large_data.rds")
# 
# # Workers read from S3
# plan(future_starburst, workers = 100)
# 
# results <- future_map(1:1000, function(i) {
#   # Read from S3 inside worker
#   data <- readRDS(s3_path)
#   process(data, i)
# })

## -----------------------------------------------------------------------------
# # Check cost before running
# plan(future_starburst, workers = 100, cpu = 4, memory = "8GB")
# #> Estimated cost: ~$3.50/hour

## -----------------------------------------------------------------------------
# # Set maximum cost per job
# starburst_config(
#   max_cost_per_job = 10,      # Don't start jobs that would cost >$10
#   cost_alert_threshold = 5     # Warn when approaching $5
# )
# 
# # Now jobs exceeding limit will error before starting
# plan(future_starburst, workers = 1000)  # Would cost ~$35/hour
# #> Error: Estimated cost ($35/hr) exceeds limit ($10/hr)

## -----------------------------------------------------------------------------
# plan(future_starburst, workers = 50)
# 
# results <- future_map(data, process)
# 
# #> Cluster runtime: 23 minutes
# #> Total cost: $1.34

## -----------------------------------------------------------------------------
# starburst_quota_status()
# #> Fargate vCPU Quota: 100 / 100 used
# #> Allows: ~25 workers with 4 vCPUs each
# #>
# #> Recommended: Request increase to 500 vCPUs

## -----------------------------------------------------------------------------
# starburst_request_quota_increase(vcpus = 500)
# #> Requesting Fargate vCPU quota increase:
# #>   Current: 100 vCPUs
# #>   Requested: 500 vCPUs
# #>
# #> ✓ Quota increase requested (Case ID: 12345678)
# #> ✓ AWS typically approves within 1-24 hours

## -----------------------------------------------------------------------------
# # Quota allows 25 workers, but you request 100
# plan(future_starburst, workers = 100, cpu = 4)
# 
# #> ⚠ Requested: 100 workers (400 vCPUs)
# #> ⚠ Current quota: 100 vCPUs (allows 25 workers max)
# #>
# #> 📋 Execution plan:
# #>   • Running in 4 waves of 25 workers each
# #>
# #> 💡 Request quota increase to 500 vCPUs? [y/n]: y
# #>
# #> ✓ Quota increase requested
# #> ⚡ Starting wave 1 (25 workers)...
# 
# results <- future_map(1:1000, expensive_function)
# 
# #> ⚡ Wave 1: 100% complete (250 tasks)
# #> ⚡ Wave 2: 100% complete (500 tasks)
# #> ⚡ Wave 3: 100% complete (750 tasks)
# #> ⚡ Wave 4: 100% complete (1000 tasks)

## -----------------------------------------------------------------------------
# # View logs from most recent cluster
# starburst_logs()
# 
# # View logs from specific task
# starburst_logs(task_id = "abc-123")
# 
# # View last 100 log lines
# starburst_logs(last_n = 100)

## -----------------------------------------------------------------------------
# starburst_status()
# #> Active Clusters:
# #>   • starburst-xyz123: 50 workers running
# #>   • starburst-abc456: 25 workers running

## -----------------------------------------------------------------------------
# # Rebuild environment
# starburst_rebuild_environment()

## -----------------------------------------------------------------------------
# # Check logs
# starburst_logs(task_id = "failed-task-id")
# 
# # Often due to memory limits - increase worker memory
# plan(future_starburst, workers = 50, memory = "16GB")  # Default is 8GB

## -----------------------------------------------------------------------------
# # Use Arrow for data frames
# library(arrow)
# write_parquet(my_data, "s3://bucket/data.parquet")
# 
# # Workers read Arrow
# results <- future_map(1:100, function(i) {
#   data <- read_parquet("s3://bucket/data.parquet")
#   process(data, i)
# })

## -----------------------------------------------------------------------------
# # 100 tasks, each takes 10 minutes
# # Local: 1000 minutes, Cloud: ~10 minutes

## -----------------------------------------------------------------------------
# # 10000 tasks, each takes 30 seconds
# # Startup overhead (45s) dominates

## -----------------------------------------------------------------------------
# # 10,000 tiny tasks
# results <- future_map(1:10000, small_function)

## -----------------------------------------------------------------------------
# # 100 batches of 100 tasks each
# batches <- split(1:10000, ceiling(seq_along(1:10000) / 100))
# 
# results <- future_map(batches, function(batch) {
#   lapply(batch, small_function)
# })
# 
# # Flatten results
# results <- unlist(results, recursive = FALSE)

## -----------------------------------------------------------------------------
# big_data <- read.csv("10GB_file.csv")  # Upload for every task
# results <- future_map(1:1000, function(i) process(big_data, i))

## -----------------------------------------------------------------------------
# # Upload once to S3
# s3_path <- "s3://bucket/big_data.csv"
# write.csv(big_data, s3_path)
# 
# # Workers read from S3
# results <- future_map(1:1000, function(i) {
#   data <- read.csv(s3_path)
#   process(data, i)
# })

## -----------------------------------------------------------------------------
# starburst_config(
#   max_cost_per_job = 50,           # Prevent accidents
#   cost_alert_threshold = 25        # Get warned early
# )

## -----------------------------------------------------------------------------
# # staRburst auto-cleans, but you can force it
# plan(sequential)  # Switch back to local
# # Old cluster resources are cleaned up automatically

## -----------------------------------------------------------------------------
# # High CPU, low memory (CPU-bound work)
# plan(future_starburst, workers = 50, cpu = 8, memory = "16GB")
# 
# # Low CPU, high memory (memory-bound work)
# plan(future_starburst, workers = 25, cpu = 4, memory = "32GB")

## -----------------------------------------------------------------------------
# # Increase timeout for long-running tasks (default 1 hour)
# plan(future_starburst, workers = 10, timeout = 7200)  # 2 hours

## -----------------------------------------------------------------------------
# # Use specific region (default from config)
# plan(future_starburst, workers = 50, region = "us-west-2")

