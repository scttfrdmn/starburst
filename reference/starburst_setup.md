# Setup staRburst

One-time configuration to set up AWS resources for staRburst

## Usage

``` r
starburst_setup(
  region = "us-east-1",
  force = FALSE,
  use_public_base = TRUE,
  ecr_image_ttl_days = NULL
)
```

## Arguments

- region:

  AWS region (default: "us-east-1")

- force:

  Force re-setup even if already configured

- use_public_base:

  Use public base Docker images (default: TRUE). Set to FALSE to build
  private base images in your ECR.

- ecr_image_ttl_days:

  Number of days to keep Docker images in ECR (default: NULL = never
  delete). AWS will automatically delete images older than this many
  days. This prevents surprise costs if you stop using staRburst.
  Recommended: 30 days for regular users, 7 days for occasional users.
  When images are deleted, they will be rebuilt on next use (adds 3-5
  min).

## Value

Invisibly returns the configuration list.

## Examples

``` r
# \donttest{
# Default: keep images forever (~$0.50/month idle cost)
starburst_setup()
#> 
#> [Start] staRburst Setup
#> 
#> 
#> This will configure AWS resources for staRburst:
#>   * S3 bucket for data transfer
#>   * ECR repository for Docker images
#>   * ECS cluster for Fargate tasks
#>   * VPC resources (subnets, security groups)
#> 
#> [1/5] Checking AWS credentials...
#> AWS credentials not found
#> 
#> Please configure AWS credentials using one of:
#>   1. AWS CLI: aws configure
#>   2. Environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
#>   3. AWS credentials file: ~/.aws/credentials
#> 
#> Error in starburst_setup(): AWS credentials required

# Auto-delete images after 30 days (saves money if you stop using it)
starburst_setup(ecr_image_ttl_days = 30)
#> 
#> [Start] staRburst Setup
#> 
#> 
#> This will configure AWS resources for staRburst:
#>   * S3 bucket for data transfer
#>   * ECR repository for Docker images
#>   * ECS cluster for Fargate tasks
#>   * VPC resources (subnets, security groups)
#> 
#> [1/5] Checking AWS credentials...
#> AWS credentials not found
#> 
#> Please configure AWS credentials using one of:
#>   1. AWS CLI: aws configure
#>   2. Environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
#>   3. AWS credentials file: ~/.aws/credentials
#> 
#> Error in starburst_setup(ecr_image_ttl_days = 30): AWS credentials required

# Use private base images with 7-day cleanup
starburst_setup(use_public_base = FALSE, ecr_image_ttl_days = 7)
#> 
#> [Start] staRburst Setup
#> 
#> 
#> This will configure AWS resources for staRburst:
#>   * S3 bucket for data transfer
#>   * ECR repository for Docker images
#>   * ECS cluster for Fargate tasks
#>   * VPC resources (subnets, security groups)
#> 
#> [1/5] Checking AWS credentials...
#> AWS credentials not found
#> 
#> Please configure AWS credentials using one of:
#>   1. AWS CLI: aws configure
#>   2. Environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
#>   3. AWS credentials file: ~/.aws/credentials
#> 
#> Error in starburst_setup(use_public_base = FALSE, ecr_image_ttl_days = 7): AWS credentials required
# }
```
