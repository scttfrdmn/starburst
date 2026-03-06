# Rebuild environment image

Rebuild environment image

## Usage

``` r
starburst_rebuild_environment(region = NULL, force = FALSE)
```

## Arguments

- region:

  AWS region (default: from config)

- force:

  Force rebuild even if current environment hasn't changed

## Value

Invisibly returns `NULL`. Called for its side effect of rebuilding and
pushing the Docker environment image.

## Examples

``` r
# \donttest{
starburst_rebuild_environment()
#> Error in get_starburst_config(): staRburst not configured. Run starburst_setup() first.
# }
```
