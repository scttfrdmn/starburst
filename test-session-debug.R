#!/usr/bin/env Rscript
# Debug script to test detached session behavior

Sys.setenv(AWS_PROFILE = "aws")

# Load the package
devtools::load_all()

cat("Creating session...\n")
session <- starburst_session(workers = 2, cpu = 1, memory = "2GB")
session_id <- session$session_id

cat("Session ID:", session_id, "\n")

# Submit some simple tasks
cat("\nSubmitting tasks...\n")
for (i in 1:3) {
  task_id <- session$submit(substitute(x * 2, list(x = i)))
  cat("  Submitted task:", task_id, "for value:", i, "\n")
}

# Check status immediately
cat("\nImmediate status:\n")
status <- session$status()
print(status)

# Wait a bit
cat("\nWaiting 30 seconds for tasks to start...\n")
Sys.sleep(30)

# Check status again
cat("\nStatus after 30s:\n")
status <- session$status()
print(status)

# Wait more
cat("\nWaiting another 60 seconds for completion...\n")
Sys.sleep(60)

# Check status again
cat("\nStatus after 90s total:\n")
status <- session$status()
print(status)

# Try to collect
cat("\nAttempting to collect results (wait=FALSE)...\n")
results <- session$collect(wait = FALSE)
cat("Collected", length(results), "results\n")
if (length(results) > 0) {
  print(results)
}

# Try with wait=TRUE and longer timeout
cat("\nAttempting to collect with wait=TRUE, timeout=120...\n")
results <- session$collect(wait = TRUE, timeout = 120)
cat("Collected", length(results), "results\n")
if (length(results) > 0) {
  print(results)
}

# Check what's in S3
cat("\nChecking S3 for task files...\n")
s3 <- paws.storage::s3(config = list(region = session$backend$region))
prefix <- sprintf("sessions/%s/tasks/", session_id)
result <- s3$list_objects_v2(
  Bucket = session$backend$bucket,
  Prefix = prefix
)
cat("Found", length(result$Contents), "objects in S3\n")
if (length(result$Contents) > 0) {
  for (obj in result$Contents) {
    cat("  -", obj$Key, "\n")
  }
}

# Cleanup
cat("\nCleaning up...\n")
session$cleanup()

cat("\nDone!\n")
