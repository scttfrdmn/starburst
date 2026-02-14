#!/usr/bin/env Rscript
Sys.setenv(AWS_PROFILE = "aws")
library(starburst)
library(future)

# Create plan
plan(starburst, workers=1, launch_type='EC2', instance_type='c6a.large')

# Create future
f <- future({ 42 })

# Extract task ID
task_id <- f$task_id
cat(sprintf("\n=== Task submitted ===\n"))
cat(sprintf("Task ID: %s\n", task_id))

# Get backend details
backend <- f$backend
cat(sprintf("Bucket: %s\n", backend$bucket))
cat(sprintf("Region: %s\n", backend$region))
cat(sprintf("Task file: s3://%s/tasks/%s.qs\n", backend$bucket, task_id))
cat(sprintf("Result file: s3://%s/results/%s.qs\n", backend$bucket, task_id))

# Wait and check
cat("\nWaiting 60 seconds for task to complete...\n")
for (i in 1:12) {
  Sys.sleep(5)
  if (resolved(f)) {
    cat(sprintf("\n✓ Task completed after %d seconds!\n", i * 5))
    result <- value(f)
    cat(sprintf("Result: %s\n", result))
    quit(status = 0)
  }
  cat(".")
}

cat("\n\n⚠ Task did not complete within 60 seconds\n")
cat("Check CloudWatch Logs at: /ecs/starburst-worker\n")
quit(status = 1)
