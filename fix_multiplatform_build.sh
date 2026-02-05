#!/bin/bash
# Fix multi-platform Docker buildx setup

set -e

echo "=== Setting up Docker Buildx for Multi-Platform ==="
echo

# Create a new buildx builder with docker-container driver (required for multi-platform)
echo "Creating buildx builder..."
docker buildx create --name starburst-builder --driver docker-container --use 2>/dev/null || \
  docker buildx use starburst-builder

# Inspect and bootstrap the builder
echo "Bootstrapping builder..."
docker buildx inspect --bootstrap

echo
echo "Builder ready! Now testing multi-platform build..."
echo

# Get R version
R_VERSION=$(R --version | head -1 | sed 's/.*R version \([0-9.]*\).*/\1/')
echo "R version: $R_VERSION"

# Build multi-platform base image
echo
echo "Building multi-platform base image (this may take 3-5 min)..."
echo

cd /Users/scttfrdmn/src/starburst

AWS_PROFILE=aws Rscript -e "
library(starburst)

# Delete old image first
system('AWS_PROFILE=aws aws ecr batch-delete-image --repository-name starburst-worker --region us-east-1 --image-ids imageTag=base-4.5.2 2>/dev/null', ignore.stdout = TRUE)

# Build with proper buildx
result <- starburst:::build_base_image('us-east-1')
cat('Base image:', result, '\n')
"

echo
echo "Verifying platforms..."
docker buildx imagetools inspect 942542972736.dkr.ecr.us-east-1.amazonaws.com/starburst-worker:base-4.5.2

echo
echo "✓ Done!"
