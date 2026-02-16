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
if (FALSE) { # \dontrun{
sessions <- starburst_list_sessions()
print(sessions)
} # }
```
