# Getting Started with staRburst

## Introduction

staRburst makes it trivial to scale your parallel R code from your
laptop to 100+ AWS workers. This vignette walks through setup and common
usage patterns.

### Installation

``` r
# Install from GitHub
remotes::install_github("yourname/starburst")
```

### One-Time Setup

Before using staRburst, you need to configure AWS resources. This only
needs to be done once.

``` r
library(starburst)

# Interactive setup wizard (takes ~2 minutes)
starburst_setup()
```

This will: - Validate your AWS credentials - Create an S3 bucket for
data transfer - Create an ECR repository for Docker images - Set up ECS
cluster and VPC resources - Check Fargate quotas and offer to request
increases

### Basic Usage

The simplest way to use staRburst is with the `furrr` package:

``` r
library(furrr)
library(starburst)

# Define your work
expensive_simulation <- function(i) {
  # Some computation that takes a few minutes
  results <- replicate(1000, {
    x <- rnorm(10000)
    mean(x^2)
  })
  mean(results)
}

# Local execution (single core)
plan(sequential)
system.time({
  results_local <- future_map(1:100, expensive_simulation)
})
#> ~16 minutes on typical laptop

# Cloud execution (50 workers)
plan(future_starburst, workers = 50)
system.time({
  results_cloud <- future_map(1:100, expensive_simulation)
})
#> ~2 minutes (including 45s startup)
#> Cost: ~$0.85

# Results are identical
identical(results_local, results_cloud)
#> [1] TRUE
```

### Example 1: Monte Carlo Simulation

``` r
library(starburst)
library(furrr)

# Simulate portfolio returns
simulate_portfolio <- function(seed) {
  set.seed(seed)
  
  # Random walk for 252 trading days
  returns <- rnorm(252, mean = 0.0003, sd = 0.02)
  prices <- cumprod(1 + returns)
  
  list(
    final_value = prices[252],
    max_drawdown = max(cummax(prices) - prices) / max(prices),
    sharpe_ratio = mean(returns) / sd(returns) * sqrt(252)
  )
}

# Run 10,000 simulations on 100 workers
plan(future_starburst, workers = 100)

results <- future_map(1:10000, simulate_portfolio, .options = furrr_options(seed = TRUE))

# Analyze results
final_values <- sapply(results, `[[`, "final_value")
hist(final_values, breaks = 50, main = "Distribution of Portfolio Final Values")

# 95% confidence interval
quantile(final_values, c(0.025, 0.975))
```

**Performance**: - Local (single core): ~4 hours - Cloud (100 workers):
~3 minutes - Cost: ~\$1.80

### Example 2: Bootstrap Resampling

``` r
library(starburst)
library(furrr)

# Your data
data <- read.csv("my_data.csv")

# Bootstrap function
bootstrap_regression <- function(i, data) {
  # Resample with replacement
  boot_indices <- sample(nrow(data), replace = TRUE)
  boot_data <- data[boot_indices, ]
  
  # Fit model
  model <- lm(y ~ x1 + x2 + x3, data = boot_data)
  
  # Return coefficients
  coef(model)
}

# Run 10,000 bootstrap samples
plan(future_starburst, workers = 50)

boot_results <- future_map(1:10000, bootstrap_regression, data = data)

# Convert to matrix
boot_coefs <- do.call(rbind, boot_results)

# 95% confidence intervals for each coefficient
apply(boot_coefs, 2, quantile, probs = c(0.025, 0.975))
```

### Example 3: Genomics Pipeline

``` r
library(starburst)
library(furrr)

# Process one sample
process_sample <- function(sample_id) {
  # Read from S3 (data already in cloud)
  fastq_path <- sprintf("s3://my-genomics-data/samples/%s.fastq", sample_id)
  data <- read_fastq(fastq_path)
  
  # Align reads
  aligned <- align_reads(data, reference = "hg38")
  
  # Call variants
  variants <- call_variants(aligned)
  
  # Return summary
  list(
    sample_id = sample_id,
    num_variants = nrow(variants),
    variants = variants
  )
}

# Process 1000 samples on 100 workers
sample_ids <- list.files("s3://my-genomics-data/samples/", pattern = ".fastq$")

plan(future_starburst, workers = 100)

results <- future_map(sample_ids, process_sample, .progress = TRUE)

# Combine results
all_variants <- do.call(rbind, lapply(results, `[[`, "variants"))
```

**Performance**: - Local (sequential): ~208 hours (8.7 days) - Cloud
(100 workers): ~2 hours - Cost: ~\$47

### Working with Data

#### Data Already in S3

If your data is already in S3, workers can read it directly:

``` r
plan(future_starburst, workers = 50)

results <- future_map(file_list, function(file) {
  # Workers read directly from S3
  data <- read.csv(sprintf("s3://my-bucket/%s", file))
  process(data)
})
```

#### Uploading Local Data

For smaller datasets, you can pass data as arguments:

``` r
# Load data locally
data <- read.csv("local_file.csv")

# staRburst automatically uploads to S3 and distributes
plan(future_starburst, workers = 50)

results <- future_map(1:1000, function(i) {
  # Each worker gets a copy of 'data'
  bootstrap_analysis(data, i)
})
```

#### Large Data Optimization

For very large objects, pre-upload to S3:

``` r
# Upload once
large_data <- read.csv("huge_file.csv")
s3_path <- starburst_upload(large_data, "s3://my-bucket/large_data.rds")

# Workers read from S3
plan(future_starburst, workers = 100)

results <- future_map(1:1000, function(i) {
  # Read from S3 inside worker
  data <- readRDS(s3_path)
  process(data, i)
})
```

### Cost Management

#### Estimate Costs

``` r
# Check cost before running
plan(future_starburst, workers = 100, cpu = 4, memory = "8GB")
#> Estimated cost: ~$3.50/hour
```

#### Set Cost Limits

``` r
# Set maximum cost per job
starburst_config(
  max_cost_per_job = 10,      # Don't start jobs that would cost >$10
  cost_alert_threshold = 5     # Warn when approaching $5
)

# Now jobs exceeding limit will error before starting
plan(future_starburst, workers = 1000)  # Would cost ~$35/hour
#> Error: Estimated cost ($35/hr) exceeds limit ($10/hr)
```

#### Track Actual Costs

``` r
plan(future_starburst, workers = 50)

results <- future_map(data, process)

#> Cluster runtime: 23 minutes
#> Total cost: $1.34
```

### Quota Management

#### Check Your Quota

``` r
starburst_quota_status()
#> Fargate vCPU Quota: 100 / 100 used
#> Allows: ~25 workers with 4 vCPUs each
#>
#> Recommended: Request increase to 500 vCPUs
```

#### Request Quota Increase

``` r
starburst_request_quota_increase(vcpus = 500)
#> Requesting Fargate vCPU quota increase:
#>   Current: 100 vCPUs
#>   Requested: 500 vCPUs
#>
#> ✓ Quota increase requested (Case ID: 12345678)
#> ✓ AWS typically approves within 1-24 hours
```

#### Wave-Based Execution

If you request more workers than your quota allows, staRburst
automatically uses wave-based execution:

``` r
# Quota allows 25 workers, but you request 100
plan(future_starburst, workers = 100, cpu = 4)

#> ⚠ Requested: 100 workers (400 vCPUs)
#> ⚠ Current quota: 100 vCPUs (allows 25 workers max)
#>
#> 📋 Execution plan:
#>   • Running in 4 waves of 25 workers each
#>
#> 💡 Request quota increase to 500 vCPUs? [y/n]: y
#>
#> ✓ Quota increase requested
#> ⚡ Starting wave 1 (25 workers)...

results <- future_map(1:1000, expensive_function)

#> ⚡ Wave 1: 100% complete (250 tasks)
#> ⚡ Wave 2: 100% complete (500 tasks)
#> ⚡ Wave 3: 100% complete (750 tasks)
#> ⚡ Wave 4: 100% complete (1000 tasks)
```

### Troubleshooting

#### View Worker Logs

``` r
# View logs from most recent cluster
starburst_logs()

# View logs from specific task
starburst_logs(task_id = "abc-123")

# View last 100 log lines
starburst_logs(last_n = 100)
```

#### Check Cluster Status

``` r
starburst_status()
#> Active Clusters:
#>   • starburst-xyz123: 50 workers running
#>   • starburst-abc456: 25 workers running
```

#### Common Issues

**Environment mismatch**: Packages not found on workers

``` r
# Rebuild environment
starburst_rebuild_environment()
```

**Task failures**: Some tasks failing

``` r
# Check logs
starburst_logs(task_id = "failed-task-id")

# Often due to memory limits - increase worker memory
plan(future_starburst, workers = 50, memory = "16GB")  # Default is 8GB
```

**Slow data transfer**: Large objects taking too long

``` r
# Use Arrow for data frames
library(arrow)
write_parquet(my_data, "s3://bucket/data.parquet")

# Workers read Arrow
results <- future_map(1:100, function(i) {
  data <- read_parquet("s3://bucket/data.parquet")
  process(data, i)
})
```

### Best Practices

#### 1. Use for Right-Sized Workloads

✅ **Good**: Each task takes \>5 minutes

``` r
# 100 tasks, each takes 10 minutes
# Local: 1000 minutes, Cloud: ~10 minutes
```

❌ **Bad**: Each task takes \<1 minute

``` r
# 10000 tasks, each takes 30 seconds
# Startup overhead (45s) dominates
```

#### 2. Batch Small Tasks

Instead of:

``` r
# 10,000 tiny tasks
results <- future_map(1:10000, small_function)
```

Do:

``` r
# 100 batches of 100 tasks each
batches <- split(1:10000, ceiling(seq_along(1:10000) / 100))

results <- future_map(batches, function(batch) {
  lapply(batch, small_function)
})

# Flatten results
results <- unlist(results, recursive = FALSE)
```

#### 3. Use S3 for Large Data

Don’t:

``` r
big_data <- read.csv("10GB_file.csv")  # Upload for every task
results <- future_map(1:1000, function(i) process(big_data, i))
```

Do:

``` r
# Upload once to S3
s3_path <- "s3://bucket/big_data.csv"
write.csv(big_data, s3_path)

# Workers read from S3
results <- future_map(1:1000, function(i) {
  data <- read.csv(s3_path)
  process(data, i)
})
```

#### 4. Set Reasonable Limits

``` r
starburst_config(
  max_cost_per_job = 50,           # Prevent accidents
  cost_alert_threshold = 25        # Get warned early
)
```

#### 5. Clean Up

``` r
# staRburst auto-cleans, but you can force it
plan(sequential)  # Switch back to local
# Old cluster resources are cleaned up automatically
```

### Advanced: Custom Configuration

#### CPU and Memory

``` r
# High CPU, low memory (CPU-bound work)
plan(future_starburst, workers = 50, cpu = 8, memory = "16GB")

# Low CPU, high memory (memory-bound work)
plan(future_starburst, workers = 25, cpu = 4, memory = "32GB")
```

#### Timeout

``` r
# Increase timeout for long-running tasks (default 1 hour)
plan(future_starburst, workers = 10, timeout = 7200)  # 2 hours
```

#### Region

``` r
# Use specific region (default from config)
plan(future_starburst, workers = 50, region = "us-west-2")
```

### Next Steps

- Check out the [Advanced
  Usage](https://scttfrdmn.github.io/starburst/articles/advanced-usage.md)
  vignette
- Review [Performance
  Tuning](https://scttfrdmn.github.io/starburst/articles/performance-tuning.md)
  guide
- See [Example
  Workflows](https://scttfrdmn.github.io/starburst/articles/examples.md)
  for real-world patterns
- Read [Troubleshooting
  Guide](https://scttfrdmn.github.io/starburst/articles/troubleshooting.md)
  when stuck

### Getting Help

- GitHub Issues: <https://github.com/yourname/starburst/issues>
- Discussions: <https://github.com/yourname/starburst/discussions>
- Email: <your.email@example.com>
