# List All Sessions

List all detached sessions in S3

## Usage

``` r
starburst_list_sessions(region = NULL)
```

## Arguments

- region:

  AWS region (default: from config)

## Value

Data frame with session information

## Examples

``` r
# \donttest{
sessions <- starburst_list_sessions()
#> Error in get_starburst_config(): staRburst not configured. Run starburst_setup() first.
print(sessions)
#> Error: object 'sessions' not found
# }
```
