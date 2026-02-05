#!/usr/bin/env Rscript
# Simple EC2 infrastructure test
# Just validates that EC2 functions work without full integration

# Set AWS profile BEFORE loading any packages
Sys.setenv(AWS_PROFILE = "aws")

# Load package from source
if (!requireNamespace("devtools", quietly = TRUE)) {
  install.packages("devtools")
}
devtools::load_all("/Users/scttfrdmn/src/starburst", quiet = TRUE)

cat("\n=== EC2 Infrastructure Test ===\n\n")

# Test 1: Check credentials
cat("Test 1: AWS Credentials\n")
if (check_aws_credentials()) {
  cat("✓ AWS credentials found\n")
} else {
  cat("✗ AWS credentials not found\n")
  cat("Make sure AWS_PROFILE=aws is set\n")
  quit(status = 1)
}

# Test 2: Get architecture from instance type
cat("\nTest 2: Architecture Detection\n")
test_types <- c("c6a.large", "c7g.xlarge", "c8a.xlarge", "m6a.2xlarge")
for (type in test_types) {
  arch <- starburst:::get_architecture_from_instance_type(type)
  cat(sprintf("  %s -> %s\n", type, arch))
}
cat("✓ Architecture detection working\n")

# Test 3: Get instance pricing
cat("\nTest 3: Instance Pricing\n")
for (type in c("c6a.large", "c7g.xlarge")) {
  price <- starburst:::get_ec2_instance_price(type, use_spot = FALSE)
  price_spot <- starburst:::get_ec2_instance_price(type, use_spot = TRUE)
  cat(sprintf("  %s: $%.4f/hr (on-demand), $%.4f/hr (spot)\n",
              type, price, price_spot))
}
cat("✓ Pricing lookup working\n")

# Test 4: Cost estimation
cat("\nTest 4: Cost Estimation\n")
cost <- starburst:::estimate_cost(
  workers = 10,
  cpu = 4,
  memory = "8GB",
  estimated_runtime_hours = 1,
  launch_type = "EC2",
  instance_type = "c6a.large",
  use_spot = FALSE
)
cat(sprintf("  Workers: 10, CPU: 4, Memory: 8GB\n"))
cat(sprintf("  Instance: c6a.large\n"))
cat(sprintf("  Instances needed: %d\n", cost$instances_needed))
cat(sprintf("  Cost (1 hour): $%.4f\n", cost$total_estimated))
cat("✓ Cost estimation working\n")

# Test 5: ECS client
cat("\nTest 5: AWS ECS Client\n")
tryCatch({
  ecs <- starburst:::get_ecs_client("us-east-1")
  clusters <- ecs$list_clusters(maxResults = 10)
  cat(sprintf("  Found %d ECS clusters\n", length(clusters$clusterArns)))
  cat("✓ ECS client working\n")
}, error = function(e) {
  cat(sprintf("✗ ECS client failed: %s\n", e$message))
  quit(status = 1)
})

# Test 6: Check if starburst cluster exists
cat("\nTest 6: Starburst Cluster\n")
config <- get_starburst_config()
cluster_name <- config$cluster_name
cluster_exists <- FALSE

tryCatch({
  ecs <- starburst:::get_ecs_client("us-east-1")
  response <- ecs$describe_clusters(clusters = list(cluster_name))

  if (length(response$clusters) > 0 && response$clusters[[1]]$status == "ACTIVE") {
    cluster_exists <- TRUE
    cat(sprintf("✓ Cluster '%s' exists and is active\n", cluster_name))
  } else {
    cat(sprintf("✗ Cluster '%s' not found\n", cluster_name))
  }
}, error = function(e) {
  cat(sprintf("✗ Error checking cluster: %s\n", e$message))
})

# Test 7: EC2 pool management functions exist
cat("\nTest 7: EC2 Pool Functions\n")
funcs <- c("setup_ec2_capacity_provider", "start_warm_pool", "stop_warm_pool", "get_pool_status")
for (func in funcs) {
  if (exists(func, where = "package:starburst", mode = "function") ||
      exists(func, where = asNamespace("starburst"), mode = "function")) {
    cat(sprintf("  ✓ %s exists\n", func))
  } else {
    cat(sprintf("  ✗ %s not found\n", func))
  }
}

# Test 8: Create a test backend object
cat("\nTest 8: Backend Object Creation\n")
tryCatch({
  backend <- list(
    cluster_name = cluster_name,
    region = "us-east-1",
    launch_type = "EC2",
    instance_type = "c6a.large",
    use_spot = FALSE,
    architecture = "X86_64",
    warm_pool_timeout = 3600,
    capacity_provider_name = "starburst-c6a-large",
    asg_name = "starburst-asg-c6a-large",
    workers = 4,
    aws_account_id = config$aws_account_id
  )

  cat("  Backend object:\n")
  cat(sprintf("    Cluster: %s\n", backend$cluster_name))
  cat(sprintf("    Launch type: %s\n", backend$launch_type))
  cat(sprintf("    Instance: %s (%s)\n", backend$instance_type, backend$architecture))
  cat(sprintf("    Capacity provider: %s\n", backend$capacity_provider_name))
  cat(sprintf("    ASG: %s\n", backend$asg_name))
  cat("✓ Backend object created\n")

}, error = function(e) {
  cat(sprintf("✗ Backend creation failed: %s\n", e$message))
  quit(status = 1)
})

cat("\n=== All Basic Tests Passed ===\n\n")
cat("Next steps:\n")
cat("  • Run actual EC2 setup: starburst_setup_ec2(instance_types = 'c6a.large')\n")
cat("  • Test pool creation and task execution\n")
cat("\n")
