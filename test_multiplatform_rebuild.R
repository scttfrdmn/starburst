#!/usr/bin/env Rscript
# Force rebuild of base image with multi-platform support

library(starburst)

Sys.setenv(AWS_PROFILE = "aws")

cat("=== Rebuilding Base Image with Multi-Platform Support ===\n\n")

# We need to delete the existing single-platform image tag from ECR
# so build_base_image() will rebuild it

account_id <- "942542972736"
region <- "us-east-1"
r_version <- paste0(R.version$major, ".", R.version$minor)
base_tag <- sprintf("base-%s", r_version)

cat("Current base tag:", base_tag, "\n")
cat("Deleting old single-platform image from ECR...\n\n")

# Delete from ECR (not local Docker)
delete_cmd <- sprintf(
  "AWS_PROFILE=aws aws ecr batch-delete-image --repository-name starburst-worker --region %s --image-ids imageTag=%s 2>&1",
  region, base_tag
)

delete_result <- system(delete_cmd, intern = TRUE)
cat(paste(delete_result, collapse = "\n"), "\n\n")

# Now rebuild with multi-platform
cat("Rebuilding with multi-platform support...\n")
cat("This will take 3-5 minutes...\n\n")

base_uri <- starburst:::build_base_image(region = region)

cat("\n✓ Base image rebuilt!\n")
cat("Image URI:", base_uri, "\n\n")

# Verify platforms
cat("Verifying multi-platform manifest...\n")
manifest_cmd <- sprintf(
  "docker buildx imagetools inspect %s",
  base_uri
)

manifest <- system(manifest_cmd, intern = TRUE)
cat(paste(manifest, collapse = "\n"), "\n\n")

has_amd64 <- any(grepl("linux/amd64", manifest))
has_arm64 <- any(grepl("linux/arm64", manifest))

cat("\nPlatform verification:\n")
cat("  ✓ linux/amd64:", if(has_amd64) "PRESENT" else "MISSING", "\n")
cat("  ✓ linux/arm64:", if(has_arm64) "PRESENT" else "MISSING", "\n\n")

if (has_amd64 && has_arm64) {
  cat("🎉 SUCCESS: Multi-platform base image is working!\n")
} else {
  cat("❌ FAILED: Missing platform support\n")
}
