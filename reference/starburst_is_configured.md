# Check if staRburst is configured

Returns `TRUE` if
[`starburst_setup()`](https://starburst.ing/reference/starburst_setup.md)
has been run, the configuration file exists, and AWS credentials are
available. Useful for guarding example code that requires AWS
credentials.

## Usage

``` r
starburst_is_configured()
```

## Value

`TRUE` if configured and credentials are available, `FALSE` otherwise.

## Examples

``` r
starburst_is_configured()
#> [1] FALSE
```
