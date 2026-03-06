# Clean up staRburst ECR images

Manually delete Docker images from ECR to save storage costs. Images
will be rebuilt on next use (adds 3-5 min delay).

## Usage

``` r
starburst_cleanup_ecr(force = FALSE, region = NULL)
```

## Arguments

- force:

  Delete all images immediately, ignoring TTL

- region:

  AWS region (default: from config)

## Value

Invisibly returns `TRUE` on success or `FALSE` if not configured.

## Examples

``` r
# \donttest{
# Delete images past TTL
starburst_cleanup_ecr()
#> [ERROR] staRburst not configured. Run starburst_setup() first.
#> 

# Delete all images immediately (save $0.50/month)
starburst_cleanup_ecr(force = TRUE)
#> [ERROR] staRburst not configured. Run starburst_setup() first.
#> 
# }
```
