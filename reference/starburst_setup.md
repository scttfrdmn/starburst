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

## Examples

``` r
if (FALSE) { # \dontrun{
# Default: keep images forever (~$0.50/month idle cost)
starburst_setup()

# Auto-delete images after 30 days (saves money if you stop using it)
starburst_setup(ecr_image_ttl_days = 30)

# Use private base images with 7-day cleanup
starburst_setup(use_public_base = FALSE, ecr_image_ttl_days = 7)
} # }
```
