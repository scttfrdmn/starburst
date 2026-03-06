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
if (starburst_is_configured()) {
  session <- starburst_session_attach("session-abc123")
  status <- session$status()
  results <- session$collect()
}
# }
```
