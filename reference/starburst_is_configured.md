# Check if staRburst is configured

Returns `TRUE` if
[`starburst_setup()`](https://starburst.ing/reference/starburst_setup.md)
has been run and the configuration file exists. Useful for guarding
example code that requires AWS credentials.

## Usage

``` r
starburst_is_configured()
```

## Value

`TRUE` if configured, `FALSE` otherwise.

## Examples

``` r
starburst_is_configured()
#> [1] FALSE
```
