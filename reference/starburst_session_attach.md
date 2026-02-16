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
if (FALSE) { # \dontrun{
session <- starburst_session_attach("session-abc123")
status <- session$status()
results <- session$collect()
} # }
```
