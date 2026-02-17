# staRburst Testing Guide

## Quick Start

### 1. Install Dependencies

``` bash
# Install required packages
Rscript -e "install.packages(c('paws.compute', 'paws.storage', 'paws.management', 'paws.networking', 'qs', 'uuid', 'renv', 'jsonlite', 'digest', 'base64enc', 'arrow', 'devtools', 'testthat', 'mockery'))"
```

### 2. Run Test Suite

``` bash
# Run all tests
Rscript -e "devtools::test()"

# Run specific test files
Rscript -e "devtools::test(filter = 'docker')"
Rscript -e "devtools::test(filter = 'task-def')"
Rscript -e "devtools::test(filter = 'waves')"
Rscript -e "devtools::test(filter = 'cost')"
```

### 3. Check Package

``` bash
# Check package (requires Author/Maintainer in DESCRIPTION)
R CMD build .
R CMD check starburst_*.tar.gz
```

------------------------------------------------------------------------

## Test Organization

### Unit Tests (No AWS Required)

These tests use `mockery` to mock AWS API calls and test logic
independently:

#### `test-docker.R` (5 tests)

- Docker validation
- renv.lock checks
- Image URI generation
- Build triggering

**Run**: `devtools::test(filter = 'docker')`

#### `test-task-def.R` (6 tests)

- Log group creation
- IAM role management
- Task definition creation/reuse

**Run**: `devtools::test(filter = 'task-def')`

#### `test-waves.R` (10 tests)

- Queue management
- Wave submission
- Task progression
- Status tracking

**Run**: `devtools::test(filter = 'waves')`

#### `test-task-storage.R` (7 tests)

- Registry creation
- Task storage/retrieval
- Registry persistence

**Run**: `devtools::test(filter = 'task-storage')`

#### `test-cost.R` (6 tests)

- Cost calculation
- Runtime tracking
- Batch processing

**Run**: `devtools::test(filter = 'cost')`

#### `test-clusters.R` (5 tests)

- Cluster listing
- Task grouping
- Error handling

**Run**: `devtools::test(filter = 'clusters')`

#### `test-subnets.R` (8 tests)

- Subnet creation
- Multi-AZ support
- Reuse logic

**Run**: `devtools::test(filter = 'subnets')`

------------------------------------------------------------------------

## Integration Testing with AWS

### Prerequisites

1.  **AWS Credentials**:

    ``` bash
    export AWS_PROFILE=aws
    # OR
    export AWS_ACCESS_KEY_ID=...
    export AWS_SECRET_ACCESS_KEY=...
    ```

2.  **Required IAM Permissions**:

    - ECR: CreateRepository, GetAuthorizationToken, PutImage
    - ECS: RegisterTaskDefinition, RunTask, ListTasks, DescribeTasks,
      StopTask
    - IAM: CreateRole, AttachRolePolicy, PutRolePolicy, GetRole
    - EC2: DescribeVpcs, DescribeSubnets, CreateSubnet,
      DescribeSecurityGroups, CreateSecurityGroup
    - S3: CreateBucket, PutObject, GetObject, ListBucket
    - CloudWatch Logs: CreateLogGroup, DescribeLogGroups
    - Service Quotas: GetServiceQuota, RequestServiceQuotaIncrease

3.  **Docker Installed**:

    ``` bash
    docker --version
    # Should return: Docker version X.Y.Z
    ```

4.  **renv Initialized**:

    ``` r
    renv::init()  # In your project
    ```

### Test Scenarios

#### 1. Setup Test

``` r
library(starburst)

# Run setup wizard
starburst_setup()

# Should create:
# - S3 bucket
# - ECR repository
# - VPC (if needed)
# - Subnets
# - Security groups
# - Save config to ~/.starburst/config.rds
```

#### 2. Single Task Test

``` r
library(starburst)
library(future)

# Simple function
test_fn <- function(x) {
  Sys.sleep(5)  # Simulate work
  x * 2
}

# Create plan (1 worker)
plan(future_starburst, workers = 1, cpu = 1, memory = "2GB")

# Execute single task
result <- future({ test_fn(42) })
value(result)  # Should return 84

# Check costs
# Should show ~$0.01 for 5 seconds of execution
```

#### 3. Parallel Execution Test

``` r
library(starburst)
library(furrr)

# Create plan (10 workers)
plan(future_starburst, workers = 10, cpu = 2, memory = "4GB")

# Execute parallel workload
results <- future_map(1:100, function(x) {
  Sys.sleep(2)
  x^2
})

# Verify results
all(results == (1:100)^2)  # Should be TRUE
```

#### 4. Wave Execution Test

``` r
library(starburst)
library(furrr)

# Request more workers than quota allows
# This will trigger wave-based execution
plan(future_starburst, workers = 100, cpu = 4, memory = "8GB")
# Should show message about wave execution

# Execute workload
results <- future_map(1:500, function(x) x * 10)

# Watch waves progress
# Should see messages like "Starting wave 2: submitting 10 tasks"
```

#### 5. Cost Tracking Test

``` r
library(starburst)

# Create plan
plan_obj <- plan(future_starburst, workers = 5, cpu = 4, memory = "8GB")

# Execute tasks
library(furrr)
results <- future_map(1:50, function(x) {
  Sys.sleep(60)  # 1 minute of work
  x
})

# Calculate actual cost
total_cost <- calculate_total_cost(plan_obj)
print(total_cost)

# Expected: ~$0.20-0.30 for 50 tasks × 1 minute
# (5 workers × 10 batches × 1 minute = 10 minutes total)
# 4 vCPU × $0.04048 × (10/60) = $0.027
# 8 GB × $0.004445 × (10/60) = $0.006
# Total per worker-minute: $0.033
# 10 worker-minutes × $0.033 = $0.33
```

#### 6. Cluster Listing Test

``` r
library(starburst)

# Create plan and start tasks
plan(future_starburst, workers = 5, cpu = 2, memory = "4GB")

# Get active clusters
clusters <- list_active_clusters("us-east-1")
print(clusters)

# Should show current cluster with task count
```

#### 7. Error Handling Test

``` r
library(starburst)
library(future)

# Function that fails
failing_fn <- function(x) {
  if (x == 5) stop("Intentional error")
  x * 2
}

plan(future_starburst, workers = 2, cpu = 1, memory = "2GB")

# Execute - should handle failure gracefully
results <- lapply(1:10, function(x) {
  f <- future({ failing_fn(x) })
  tryCatch(value(f), error = function(e) NA)
})

# Check: should have 1 NA (task 5)
sum(is.na(results))  # Should be 1
```

------------------------------------------------------------------------

## Performance Testing

### Load Test: 10 Workers

``` r
library(starburst)
library(furrr)
library(tictoc)

plan(future_starburst, workers = 10, cpu = 2, memory = "4GB")

tic()
results <- future_map(1:100, function(x) {
  Sys.sleep(1)
  x^2
})
toc()

# Expected: ~10 seconds (100 tasks / 10 workers = 10 batches)
```

### Load Test: 50 Workers

``` r
plan(future_starburst, workers = 50, cpu = 4, memory = "8GB")

tic()
results <- future_map(1:500, function(x) {
  Sys.sleep(5)
  x * 10
})
toc()

# Expected: ~50 seconds (500 tasks / 50 workers = 10 batches × 5 seconds)
```

### Load Test: 100 Workers (Wave Execution)

``` r
# Will likely trigger wave execution due to quota limits
plan(future_starburst, workers = 100, cpu = 4, memory = "8GB")

tic()
results <- future_map(1:1000, function(x) {
  Sys.sleep(2)
  sqrt(x)
})
toc()

# Expected: Depends on quota, but should complete successfully
# Watch for wave progression messages
```

------------------------------------------------------------------------

## Debugging

### Enable Verbose Logging

``` r
# Set options for more detailed output
options(starburst.verbose = TRUE)
```

### Check Task Logs

``` r
library(starburst)

# After running tasks, check CloudWatch logs
# Log group: /aws/ecs/starburst-worker
# Stream prefix: starburst/{cluster-id}
```

### Inspect Task Registry

``` r
# Get all stored task ARNs
tasks <- list_task_arns()
print(tasks)

# Get specific task ARN
task_arn <- get_task_arn("task-id-here")
print(task_arn)
```

### Check AWS Resources

``` bash
# List ECR images
aws ecr describe-images --repository-name starburst-worker --profile aws

# List ECS tasks
aws ecs list-tasks --cluster starburst-cluster --profile aws

# List task definitions
aws ecs list-task-definitions --family-prefix starburst-worker --profile aws

# Check S3 bucket
aws s3 ls s3://starburst-{account-id}/ --profile aws
```

------------------------------------------------------------------------

## Cleanup

### Manual Cleanup

``` r
library(starburst)

# Stop running tasks
# (called automatically on plan cleanup)
stop_running_tasks(plan_obj)

# Calculate final costs
final_cost <- calculate_total_cost(plan_obj)
print(final_cost)
```

### Full Resource Cleanup

``` bash
# Delete ECR repository
aws ecr delete-repository --repository-name starburst-worker --force --profile aws

# Delete S3 bucket
aws s3 rb s3://starburst-{account-id} --force --profile aws

# Delete ECS cluster
aws ecs delete-cluster --cluster starburst-cluster --profile aws

# Delete IAM roles (manually via console or CLI)
```

------------------------------------------------------------------------

## Troubleshooting

### Issue: Docker not found

**Error**: “Docker is not installed or not accessible”

**Solution**:

``` bash
# Install Docker
# macOS: https://docs.docker.com/desktop/install/mac-install/
# Linux: https://docs.docker.com/engine/install/
# Windows: https://docs.docker.com/desktop/install/windows-install/

# Verify installation
docker --version
```

### Issue: ECR authentication failed

**Error**: “Failed to authenticate with ECR”

**Solution**:

``` bash
# Check AWS credentials
aws sts get-caller-identity --profile aws

# Manually test ECR login
aws ecr get-login-password --region us-east-1 --profile aws | \
  docker login --username AWS --password-stdin {account-id}.dkr.ecr.us-east-1.amazonaws.com
```

### Issue: Task definition registration failed

**Error**: “Failed to register task definition”

**Solution**: - Check IAM permissions (needs
`ecs:RegisterTaskDefinition`) - Verify execution and task role ARNs
exist - Check CloudWatch log group exists

### Issue: No subnets created

**Error**: “Failed to create any subnets”

**Solution**: - Check VPC exists - Verify EC2 permissions
(`ec2:CreateSubnet`, `ec2:DescribeSubnets`) - Check availability zones
in region

### Issue: Quota limit preventing execution

**Error**: Messages about wave execution

**Solution**: - This is expected behavior when quota-limited - Request
quota increase via Service Quotas console - Or reduce number of workers
to fit within quota

### Issue: Cost calculation returns 0

**Problem**:
[`calculate_total_cost()`](https://starburst.ing/reference/calculate_total_cost.md)
returns 0

**Solution**: - Check if tasks completed (not still running) - Verify
task ARNs stored in registry:
[`list_task_arns()`](https://starburst.ing/reference/list_task_arns.md) -
Check ECS API permissions (`ecs:DescribeTasks`)

------------------------------------------------------------------------

## CI/CD Integration

### GitHub Actions Example

``` yaml
name: Test staRburst

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Setup R
        uses: r-lib/actions/setup-r@v2

      - name: Install dependencies
        run: |
          Rscript -e "install.packages(c('devtools', 'testthat', 'mockery'))"
          Rscript -e "devtools::install_deps()"

      - name: Run tests
        run: Rscript -e "devtools::test()"

      # Integration tests only on main branch
      - name: Run integration tests
        if: github.ref == 'refs/heads/main'
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        run: Rscript -e "source('tests/integration/test-aws.R')"
```

------------------------------------------------------------------------

## Performance Benchmarks

Expected performance on AWS Fargate (based on task specification):

| Workers | Tasks | Task Duration | Total Time | Cost (est.) |
|---------|-------|---------------|------------|-------------|
| 1       | 10    | 10s           | 100s       | \$0.02      |
| 10      | 100   | 10s           | 100s       | \$0.20      |
| 50      | 500   | 10s           | 100s       | \$1.00      |
| 100     | 1000  | 10s           | 100s       | \$2.00      |

*Assumes 4 vCPU, 8GB memory per worker*

------------------------------------------------------------------------

## Support

For issues, questions, or contributions: - GitHub Issues:
<https://github.com/yourusername/starburst/issues> - Documentation: Run
[`?starburst`](https://starburst.ing/reference/starburst.md) in R

------------------------------------------------------------------------

**Happy Testing! 🚀**
