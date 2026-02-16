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

## Examples

``` r
if (FALSE) { # \dontrun{
# Delete images past TTL
starburst_cleanup_ecr()

# Delete all images immediately (save $0.50/month)
starburst_cleanup_ecr(force = TRUE)
} # }
```
