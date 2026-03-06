# Request quota increase (user-facing)

Request quota increase (user-facing)

## Usage

``` r
starburst_request_quota_increase(vcpus = 500, region = NULL)
```

## Arguments

- vcpus:

  Desired vCPU quota

- region:

  AWS region (default: from config)

## Value

Invisibly returns `TRUE` if the increase was requested, `FALSE` if
already sufficient or cancelled.

## Examples

``` r
# \donttest{
starburst_request_quota_increase(vcpus = 500)
#> Error in get_starburst_config(): staRburst not configured. Run starburst_setup() first.
# }
```
