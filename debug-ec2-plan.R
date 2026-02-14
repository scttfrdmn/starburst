#!/usr/bin/env Rscript
# Minimal test case to debug EC2 plan

Sys.setenv(AWS_PROFILE = "aws")
library(starburst)
library(future)

cat("Setting up EC2 plan...\n")

# Try to set up the plan
plan_result <- plan(starburst,
                    workers = 2,
                    cpu = 2,
                    memory = "4GB",
                    launch_type = "EC2",
                    instance_type = "c6a.large",
                    use_spot = FALSE,
                    warm_pool_timeout = 600,
                    region = "us-east-1"
)

cat("Plan set up successfully\n")
cat("Plan class:", class(plan_result), "\n")
cat("Plan attributes:\n")
print(names(attributes(plan_result)))

cat("\nTrying to create a single future...\n")

# Try to create one future
f <- future({
  Sys.info()[["nodename"]]
})

cat("Future created successfully\n")
cat("Future class:", class(f), "\n")

cat("\nTrying to get result...\n")
result <- value(f)
cat("Result:", result, "\n")

cat("\n✓ Success!\n")
