# Show quota status

Show quota status

## Usage

``` r
starburst_quota_status(region = NULL)
```

## Arguments

- region:

  AWS region (default: from config)

## Value

Invisibly returns a list with quota information including current limit,
usage, and any pending requests.

## Examples

``` r
# \donttest{
if (starburst_is_configured()) {
  starburst_quota_status()
}
# }
```
