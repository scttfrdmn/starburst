#!/usr/bin/env Rscript
# Test EC2 pool setup

library(starburst)

Sys.setenv(AWS_PROFILE = "aws")

cat("=== Test 2: EC2 Pool Setup ===\n\n")

region <- "us-east-1"

cat("Setting up EC2 capacity provider for c6a.large...\n")
cat("This will create:\n")
cat("  - IAM instance role and profile\n")
cat("  - Security group for ECS workers\n")
cat("  - Launch template\n")
cat("  - Auto-Scaling Group\n")
cat("  - ECS Capacity Provider\n\n")

tryCatch({
  # Run EC2 setup for c6a.large (6th gen AMD - widely available)
  starburst_setup_ec2(
    region = region,
    instance_types = c("c6a.large"),  # 6th gen AMD for testing
    force = TRUE
  )

  cat("\n✓ EC2 setup completed!\n\n")

  # Verify components were created
  cat("Verifying setup...\n\n")

  # Check IAM role
  iam <- paws.management::iam()
  role_check <- tryCatch({
    role <- iam$get_role(RoleName = "starburstECSInstanceRole")
    cat("✓ IAM instance role exists\n")
    TRUE
  }, error = function(e) {
    cat("✗ IAM instance role missing\n")
    FALSE
  })

  # Check instance profile
  profile_check <- tryCatch({
    profile <- iam$get_instance_profile(InstanceProfileName = "starburstECSInstanceProfile")
    cat("✓ IAM instance profile exists\n")
    TRUE
  }, error = function(e) {
    cat("✗ IAM instance profile missing\n")
    FALSE
  })

  # Check ASG
  autoscaling <- paws.compute::autoscaling(config = list(region = region))
  asg_check <- tryCatch({
    asg <- autoscaling$describe_auto_scaling_groups(
      AutoScalingGroupNames = list("starburst-asg-c6a-large")
    )
    if (length(asg$AutoScalingGroups) > 0) {
      cat("✓ Auto-Scaling Group exists\n")
      cat("  Min:", asg$AutoScalingGroups[[1]]$MinSize, "\n")
      cat("  Max:", asg$AutoScalingGroups[[1]]$MaxSize, "\n")
      cat("  Desired:", asg$AutoScalingGroups[[1]]$DesiredCapacity, "\n")
      TRUE
    } else {
      cat("✗ Auto-Scaling Group missing\n")
      FALSE
    }
  }, error = function(e) {
    cat("✗ Error checking ASG:", e$message, "\n")
    FALSE
  })

  # Check ECS capacity provider
  ecs <- paws.compute::ecs(config = list(region = region))
  cp_check <- tryCatch({
    cp <- ecs$describe_capacity_providers(
      capacityProviders = list("starburst-c6a-large")
    )
    if (length(cp$capacityProviders) > 0) {
      cat("✓ ECS Capacity Provider exists\n")
      cat("  Status:", cp$capacityProviders[[1]]$status, "\n")
      TRUE
    } else {
      cat("✗ ECS Capacity Provider missing\n")
      FALSE
    }
  }, error = function(e) {
    cat("✗ Error checking capacity provider:", e$message, "\n")
    FALSE
  })

  cat("\n")
  if (role_check && profile_check && asg_check && cp_check) {
    cat("🎉 SUCCESS: All EC2 components created!\n")
  } else {
    cat("⚠️ PARTIAL: Some components missing\n")
  }

}, error = function(e) {
  cat("\n✗ Error during setup:", e$message, "\n")
  cat("\nStack trace:\n")
  print(e)
})
