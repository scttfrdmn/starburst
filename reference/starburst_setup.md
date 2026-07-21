# Setup staRburst

One-time configuration to set up AWS resources for staRburst

## Usage

``` r
starburst_setup(
  region = "us-east-1",
  force = FALSE,
  use_public_base = TRUE,
  ecr_image_ttl_days = NULL,
  build_image = TRUE,
  setup_ec2 = TRUE
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

- build_image:

  Build the worker environment image during setup (default: TRUE). Set
  to FALSE to provision AWS resources (S3/ECR/ECS/VPC), write config,
  and check quotas without triggering the multi-minute Docker image
  build. The image is then built lazily on first worker launch via
  [`ensure_environment()`](https://starburst.ing/reference/ensure_environment.md).
  Useful for CI / connectivity checks.

- setup_ec2:

  Provision the EC2 capacity provider and Auto Scaling Group for the
  default instance type during setup (default: TRUE). This is what makes
  the default EC2 backend work out of the box — without it, the first
  [`starburst_map()`](https://starburst.ing/reference/starburst_map.md)/`plan(starburst)`
  run on EC2 would fail because no capacity provider exists. It creates
  infrastructure at `DesiredCapacity = 0` (no billable instances are
  launched during setup). Set to FALSE if you only use the Fargate
  backend, which needs no capacity provider. Provision additional
  instance types later with
  [`starburst_setup_ec2`](https://starburst.ing/reference/starburst_setup_ec2.md).

## Value

Invisibly returns the configuration list.

## Examples

``` r
# \donttest{
if (starburst_is_configured()) {
  # Default: keep images forever (~$0.50/month idle cost)
  starburst_setup()

  # Auto-delete images after 30 days (saves money if you stop using it)
  starburst_setup(ecr_image_ttl_days = 30)

  # Use private base images with 7-day cleanup
  starburst_setup(use_public_base = FALSE, ecr_image_ttl_days = 7)

  # Provision resources without building the image (fast; CI / connectivity checks)
  starburst_setup(build_image = FALSE)
}
# }
```
