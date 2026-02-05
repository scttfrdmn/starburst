#!/usr/bin/env Rscript
# Test EC2/ECR multi-platform image building

library(starburst)

Sys.setenv(AWS_PROFILE = "aws")

cat("=== Test 1: Multi-Platform Base Image ===\n\n")

# Test buildx setup
cat("Checking Docker buildx...\n")
buildx_check <- system("docker buildx ls", intern = TRUE)
cat(paste(buildx_check, collapse = "\n"), "\n\n")

# Build multi-platform base image
cat("Building multi-platform base image...\n")
cat("This will build for linux/amd64 and linux/arm64\n\n")

tryCatch({
  # This should trigger build_base_image() which now uses buildx
  base_uri <- starburst:::build_base_image(region = "us-east-1")
  cat("\n✓ Base image built successfully!\n")
  cat("Image URI:", base_uri, "\n\n")

  # Verify manifest has both platforms
  cat("Checking image manifest...\n")
  account_id <- "942542972736"
  r_version <- paste0(R.version$major, ".", R.version$minor)
  base_tag <- sprintf("base-%s", r_version)

  inspect_cmd <- sprintf(
    "docker manifest inspect %s.dkr.ecr.us-east-1.amazonaws.com/starburst-worker:%s 2>&1",
    account_id, base_tag
  )

  manifest <- system(inspect_cmd, intern = TRUE)

  has_amd64 <- any(grepl("amd64", manifest))
  has_arm64 <- any(grepl("arm64", manifest))

  cat("\nPlatform support:\n")
  cat("  - linux/amd64:", if(has_amd64) "✓" else "✗", "\n")
  cat("  - linux/arm64:", if(has_arm64) "✓" else "✗", "\n\n")

  if (has_amd64 && has_arm64) {
    cat("✓ SUCCESS: Multi-platform base image working!\n")
  } else {
    cat("✗ FAILED: Missing platform support\n")
  }

}, error = function(e) {
  cat("\n✗ Error:", e$message, "\n")
  cat("This may be expected if base image already exists.\n")
  cat("Checking existing image...\n\n")

  # Check existing image
  account_id <- "942542972736"
  r_version <- paste0(R.version$major, ".", R.version$minor)
  base_tag <- sprintf("base-%s", r_version)

  # Pull and inspect
  pull_cmd <- sprintf(
    "AWS_PROFILE=aws docker pull %s.dkr.ecr.us-east-1.amazonaws.com/starburst-worker:%s",
    account_id, base_tag
  )
  system(pull_cmd)

  inspect_cmd <- sprintf(
    "docker inspect %s.dkr.ecr.us-east-1.amazonaws.com/starburst-worker:%s --format '{{.Architecture}}'",
    account_id, base_tag
  )
  arch <- system(inspect_cmd, intern = TRUE)
  cat("Existing image architecture:", arch, "\n")
})
