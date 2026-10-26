# Show staRburst status

Prints the configured region, S3 bucket, and ECR repository, plus
current Fargate vCPU quota usage (this makes AWS API calls).

## Usage

``` r
starburst_status()
```

## Value

Invisibly returns a list with current configuration and quota
information.

## Examples

``` r
# \donttest{
if (starburst_is_configured()) {
  starburst_status()
}
# }
```
