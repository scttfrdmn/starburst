# Troubleshooting staRburst

## Troubleshooting staRburst

This guide helps you diagnose and fix common issues with staRburst.

### Accessing Logs

#### CloudWatch Logs Structure

staRburst automatically sends worker logs to CloudWatch Logs:

- **Log Group:** `/aws/ecs/starburst-worker`
- **Log Stream Pattern:** `starburst/<task-id>`
- **Retention:** 7 days (configurable)

#### Viewing Logs in R

``` r
# For ephemeral mode
library(starburst)
plan(starburst, workers = 10)

# Check logs for a specific task
# (get task ID from error messages or futures)

# For detached sessions
session <- starburst_session_attach("session-id")
status <- session$status()

# View failed task logs using AWS CLI or console
```

#### Viewing Logs in AWS Console

1.  Navigate to **CloudWatch → Log Groups**
2.  Find `/aws/ecs/starburst-worker`
3.  Search for task ID in stream names
4.  Use CloudWatch Insights for advanced queries:

&nbsp;

    fields @timestamp, @message
    | filter @message like /ERROR/
    | sort @timestamp desc
    | limit 100

### Common Issues

#### Issue 1: Tasks Stuck in “Pending”

**Symptoms:** - `session$status()` shows tasks never start - Workers = 0
in status - Tasks remain in pending state for \>5 minutes

**Diagnosis:**

``` r
# Check Fargate quota
config <- get_starburst_config()
sts <- paws.security.identity::sts()
account <- sts$get_caller_identity()

# Check service quotas manually in AWS Console:
# Service Quotas → AWS Fargate → Fargate vCPUs
```

**Common Causes:**

1.  **Insufficient vCPU quota** - Most common issue
    - Default Fargate quota: 6 vCPUs in us-east-1
    - Each worker uses configured CPU (default: 4 vCPUs)
    - With 10 workers × 4 vCPUs = 40 vCPUs needed
2.  **Invalid task definition** - Wrong CPU/memory combination
    - Fargate has strict CPU/memory pairings
    - Example: 4 vCPUs supports 8-30 GB memory
3.  **Network/subnet issues** - VPC configuration problems
    - Subnets must have available IP addresses
    - Security groups must allow outbound traffic
4.  **IAM permission errors** - Missing ECS task execution role
    permissions
    - Must have ECR, S3, CloudWatch Logs access

**Solutions:**

``` r
# Solution 1: Request quota increase
# Go to AWS Console → Service Quotas → AWS Fargate
# Request vCPUs quota increase to 100+

# Solution 2: Reduce workers
plan(starburst, workers = 1)  # Use only 1 worker (4 vCPUs)

# Solution 3: Reduce CPU per worker
plan(starburst, workers = 10, cpu = 0.25, memory = "512MB")

# Solution 4: Check IAM permissions
# Ensure ECS task execution role has:
# - AmazonECSTaskExecutionRolePolicy
# - S3 read/write access to starburst bucket
# - CloudWatch Logs write access
```

#### Issue 2: Workers Crash Immediately

**Symptoms:** - Tasks start but stop within 30 seconds - Status shows
workers = 0 after initial launch - CloudWatch logs show error before
exit

**Diagnosis:**

``` r
# View CloudWatch logs for the failed task
# Look for error messages in the logs

# Common error patterns:
# - "Error: Cannot connect to S3" → S3 permissions
# - "Error loading package" → Package installation failed
# - "Cannot allocate memory" → Memory limit too low
# - "exec format error" → Architecture mismatch
```

**Common Causes:**

1.  **S3 permission errors** - Task role can’t access bucket
2.  **Package installation failures** - Missing system dependencies
3.  **Out of memory** - Memory limit too low for workload
4.  **Architecture mismatch** - ARM64 vs X86_64 image/instance mismatch

**Solutions:**

``` r
# Solution 1: Verify S3 permissions
# Check task role has S3 access:
# IAM → Roles → starburstECSTaskRole → Permissions
# Should have S3 GetObject/PutObject on bucket

# Solution 2: Increase memory
plan(starburst, workers = 5, cpu = 4, memory = "16GB")

# Solution 3: Check Docker build logs
# Re-run starburst setup to rebuild image
# Watch for package installation errors

# Solution 4: For EC2 mode, verify architecture matches
plan(starburst,
     launch_type = "EC2",
     instance_type = "c7g.xlarge")  # Graviton (ARM64)
# Ensure Docker image built for matching architecture
```

#### Issue 3: “Access Denied” Errors

**Symptoms:** - Error messages containing “AccessDenied” or
“Forbidden” - Can’t create tasks, access S3, or push Docker images

**Diagnosis:**

``` r
# Check which operation is failing:
# 1. Docker push → ECR permissions
# 2. S3 operations → S3 permissions
# 3. Task launch → ECS permissions

# Verify credentials
library(paws.security.identity)
sts <- paws.security.identity::sts()
identity <- sts$get_caller_identity()
print(identity)  # Should show your AWS account
```

**Common Causes:**

1.  **No AWS credentials configured**
2.  **IAM user lacks required permissions**
3.  **S3 bucket policy blocks access**
4.  **ECR repository doesn’t exist or blocks access**

**Solutions:**

``` r
# Solution 1: Configure AWS credentials
# Option A: Environment variables
Sys.setenv(
  AWS_ACCESS_KEY_ID = "YOUR_KEY",
  AWS_SECRET_ACCESS_KEY = "YOUR_SECRET",
  AWS_DEFAULT_REGION = "us-east-1"
)

# Option B: AWS CLI profile
Sys.setenv(AWS_PROFILE = "your-profile")

# Option C: IAM role (when running on EC2/ECS)
# No configuration needed - automatic

# Solution 2: Add required IAM permissions
# Your IAM user/role needs:
# - ECS: RunTask, DescribeTasks, StopTask
# - ECR: GetAuthorizationToken, BatchCheckLayerAvailability,
#        GetDownloadUrlForLayer, PutImage, InitiateLayerUpload, etc.
# - S3: GetObject, PutObject, ListBucket on your bucket
# - IAM: PassRole (to pass ECS task role)

# Solution 3: Run starburst_setup() to create all resources
library(starburst)
starburst_setup(bucket = "my-starburst-bucket")
```

#### Issue 4: High Costs / Runaway Workers

**Symptoms:** - AWS bill higher than expected - Many tasks running when
you expected them to stop - Old sessions still have active workers

**Diagnosis:**

``` r
# List all active sessions
library(starburst)
sessions <- starburst_list_sessions()
print(sessions)

# Check for old sessions with running tasks
```

**Common Causes:**

1.  **Forgot to cleanup session** - Workers keep running
2.  **Requested too many workers** - Cost adds up quickly
3.  **Long-running tasks** - Tasks running for hours/days

**Solutions:**

``` r
# Solution 1: Cleanup all sessions
sessions <- starburst_list_sessions()
for (session_id in sessions$session_id) {
  session <- starburst_session_attach(session_id)
  session$cleanup(stop_workers = TRUE, force = TRUE)
}

# Solution 2: Set budget alerts in AWS
# AWS Billing Console → Budgets → Create budget
# Set alert at $100, $500 thresholds

# Solution 3: Use worker validation to prevent mistakes
# staRburst now enforces max 500 workers
# Previously you could accidentally request 10,000+

# Solution 4: Set absolute timeout on sessions
session <- starburst_session(
  workers = 10,
  absolute_timeout = 3600  # Auto-terminate after 1 hour
)
```

#### Issue 5: Session Cleanup Not Working

**Symptoms:** - Called `session$cleanup()` but workers still running -
S3 files not deleted - Tasks still appearing in ECS console

**Diagnosis:**

``` r
# Check if cleanup was called with correct parameters
session$cleanup(stop_workers = TRUE, force = TRUE)

# Verify tasks actually stopped (may take 30-60 seconds)
Sys.sleep(60)

# Check ECS tasks manually
library(paws.compute)
ecs <- paws.compute::ecs(config = list(region = "us-east-1"))
tasks <- ecs$list_tasks(cluster = "starburst-cluster")
print(tasks$taskArns)  # Should be empty or not include your tasks
```

**Common Causes:**

1.  **Cleanup called without stop_workers** - Workers not stopped
2.  **Cleanup called without force** - S3 files preserved
3.  **Tasks in different cluster** - Cleanup looking in wrong place
4.  **ECS eventual consistency** - Tasks take time to stop

**Solutions:**

``` r
# Solution 1: Always use both flags for full cleanup
session$cleanup(stop_workers = TRUE, force = TRUE)

# Solution 2: Wait for ECS to process stop requests
session$cleanup(stop_workers = TRUE)
Sys.sleep(60)  # Wait 1 minute
# Then verify in AWS console

# Solution 3: Manual cleanup if needed
library(paws.compute)
library(paws.storage)

ecs <- paws.compute::ecs(config = list(region = "us-east-1"))
s3 <- paws.storage::s3(config = list(region = "us-east-1"))

# Stop all tasks in cluster
tasks <- ecs$list_tasks(cluster = "starburst-cluster", desiredStatus = "RUNNING")
for (task_arn in tasks$taskArns) {
  ecs$stop_task(cluster = "starburst-cluster", task = task_arn)
}

# Delete all session S3 files
result <- s3$list_objects_v2(Bucket = "your-bucket", Prefix = "sessions/")
# ... delete objects
```

#### Issue 6: Results Not Appearing

**Symptoms:** - `session$collect()` returns empty list - Tasks show as
“completed” but no results - S3 doesn’t contain result files

**Diagnosis:**

``` r
# Check session status
status <- session$status()
print(status)

# Verify tasks were actually submitted
# Check S3 for task files
library(paws.storage)
s3 <- paws.storage::s3(config = list(region = "us-east-1"))
result <- s3$list_objects_v2(
  Bucket = "your-bucket",
  Prefix = sprintf("sessions/%s/results/", session$session_id)
)
print(result$Contents)  # Should show .qs files
```

**Common Causes:**

1.  **Tasks failed before producing results** - Check for errors
2.  **Workers can’t write to S3** - Permission issue
3.  **Looking at wrong session ID** - Attached to wrong session
4.  **Results already collected** - Results only collected once

**Solutions:**

``` r
# Solution 1: Check task status for errors
status <- session$status()
if (status$failed_tasks > 0) {
  # Check CloudWatch logs for failed task IDs
  # Look for error messages
}

# Solution 2: Verify S3 write permissions
# Task role must have S3 PutObject permission

# Solution 3: Verify session ID
print(session$session_id)
# Make sure this matches the session you created

# Solution 4: Results can only be collected once
# If you already called collect(), results are removed from S3
# You should store results after collection:
results <- session$collect(wait = TRUE)
saveRDS(results, "my_results.rds")  # Save locally
```

#### Issue 7: Detached Session Reattach Fails

**Symptoms:** -
[`starburst_session_attach()`](https://scttfrdmn.github.io/starburst/reference/starburst_session_attach.md)
throws error - “Session not found” message - Can’t reconnect after
closing R

**Diagnosis:**

``` r
# List all sessions to find your session ID
sessions <- starburst_list_sessions()
print(sessions)

# Try to attach with exact session ID
session_id <- "session-abc123..."
session <- starburst_session_attach(session_id)
```

**Common Causes:**

1.  **Wrong session ID** - Typo or wrong ID
2.  **Session expired** - Exceeded absolute_timeout
3.  **S3 manifest deleted** - Someone deleted session files
4.  **Wrong region** - Session created in different region

**Solutions:**

``` r
# Solution 1: List and copy exact session ID
sessions <- starburst_list_sessions()
session_id <- sessions$session_id[1]  # Use exact ID
session <- starburst_session_attach(session_id)

# Solution 2: Save session ID immediately after creation
session <- starburst_session(workers = 10)
session_id <- session$session_id
write(session_id, "my_session_id.txt")  # Save to file
# Later:
session_id <- readLines("my_session_id.txt")
session <- starburst_session_attach(session_id)

# Solution 3: Check correct region
session <- starburst_session_attach(session_id, region = "us-west-2")
```

#### Issue 8: Package Installation Failures

**Symptoms:** - Docker build fails during
[`renv::restore()`](https://rstudio.github.io/renv/reference/restore.html) -
Error messages about missing system dependencies - Specific packages
fail to install

**Diagnosis:**

Look at Docker build output when running staRburst. Common error
patterns:

    Error: installation of package 'X' had non-zero exit status
    Error: compilation failed for package 'X'
    Error: unable to load shared library

**Common Causes:**

1.  **Missing system dependencies** - Package needs system libraries
2.  **Package not in CRAN** - Private or development package
3.  **Version conflicts** - renv.lock specifies unavailable version

**Solutions:**

``` r
# Solution 1: Add system dependencies to Dockerfile.base
# Edit starburst package Dockerfile.base template:
# Add RUN apt-get install -y libcurl4-openssl-dev

# Solution 2: Use renv snapshot to capture dependencies
renv::snapshot()  # Updates renv.lock

# Solution 3: Install from GitHub for dev packages
renv::install("user/package")
renv::snapshot()

# Solution 4: Check package availability
install.packages("package")  # Test locally first
```

### Advanced Diagnostics

#### Checking ECS Task Status

``` r
library(paws.compute)
ecs <- paws.compute::ecs(config = list(region = "us-east-1"))

# List all tasks
tasks <- ecs$list_tasks(
  cluster = "starburst-cluster",
  desiredStatus = "RUNNING"
)

# Describe specific task
task_detail <- ecs$describe_tasks(
  cluster = "starburst-cluster",
  tasks = tasks$taskArns[1:1]
)

# Check exit code and reason
print(task_detail$tasks[[1]]$containers[[1]]$exitCode)
print(task_detail$tasks[[1]]$stoppedReason)
```

#### Monitoring S3 Storage

``` r
library(paws.storage)
s3 <- paws.storage::s3(config = list(region = "us-east-1"))

# List all session files
result <- s3$list_objects_v2(
  Bucket = "your-starburst-bucket",
  Prefix = "sessions/"
)

# Calculate total storage
total_bytes <- sum(sapply(result$Contents, function(x) x$Size))
total_mb <- total_bytes / 1024^2
cat(sprintf("Total storage: %.2f MB\n", total_mb))
```

#### Estimating Costs

``` r
# Fargate pricing (us-east-1, 2026):
# - vCPU: $0.04048 per hour
# - Memory: $0.004445 per GB-hour

vcpu_price <- 0.04048
memory_price <- 0.004445

workers <- 10
cpu <- 4
memory_gb <- 8
runtime_hours <- 1

cost_per_worker <- (cpu * vcpu_price) + (memory_gb * memory_price)
total_cost <- workers * cost_per_worker * runtime_hours

cat(sprintf("Estimated cost: $%.2f for %d hours\n", total_cost, runtime_hours))
```

### Getting Help

If you encounter issues not covered here:

1.  **Check CloudWatch Logs** - Most issues have error messages in logs
2.  **Review AWS Console** - Check ECS, S3, ECR for resource status
3.  **File GitHub Issue** - Include error messages and logs
4.  **AWS Support** - For quota increases or AWS-specific issues

**Information to Include in Bug Reports:**

- staRburst version: `packageVersion("starburst")`
- R version: `R.version.string`
- AWS region
- Launch type (Fargate vs EC2)
- Error messages from R and CloudWatch logs
- Session ID (for detached sessions)
- Output of `session$status()` (if applicable)

### See Also

- [Security Best
  Practices](https://scttfrdmn.github.io/starburst/articles/security.md) -
  Securing your staRburst deployments
- [staRburst README](https://github.com/scttfrdmn/starburst) - Getting
  started guide
- [AWS Fargate
  Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
