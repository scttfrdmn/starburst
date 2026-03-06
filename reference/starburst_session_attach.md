# Reattach to Existing Session

Reattach to a previously created detached session

## Usage

``` r
starburst_session_attach(session_id, region = NULL)
```

## Arguments

- session_id:

  Session identifier

- region:

  AWS region (default: from config)

## Value

A StarburstSession object

## Examples

``` r
# \donttest{
session <- starburst_session_attach("session-abc123")
#> Error in get_starburst_config(): staRburst not configured. Run starburst_setup() first.
status <- session$status()
#> Error: object 'session' not found
results <- session$collect()
#> Error: object 'session' not found
# }
```
