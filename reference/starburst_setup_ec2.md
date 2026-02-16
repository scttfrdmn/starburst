# Setup EC2 capacity providers for staRburst

One-time setup for EC2 launch type. Creates IAM roles, instance
profiles, and capacity providers for specified instance types.

## Usage

``` r
starburst_setup_ec2(
  region = "us-east-1",
  instance_types = c("c7g.xlarge", "c7i.xlarge"),
  force = FALSE
)
```

## Arguments

- region:

  AWS region (default: "us-east-1")

- instance_types:

  Character vector of instance types to setup (default: c("c7g.xlarge",
  "c7i.xlarge"))

- force:

  Force re-setup even if already configured

## Examples

``` r
if (FALSE) { # \dontrun{
# Setup with default instance types (Graviton and Intel)
starburst_setup_ec2()

# Setup with custom instance types
starburst_setup_ec2(instance_types = c("c7g.2xlarge", "r7g.xlarge"))
} # }
```
