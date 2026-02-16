# Configure staRburst options

Configure staRburst options

## Usage

``` r
starburst_config(
  max_cost_per_job = NULL,
  cost_alert_threshold = NULL,
  auto_cleanup_s3 = NULL,
  ...
)
```

## Arguments

- max_cost_per_job:

  Maximum cost per job in dollars

- cost_alert_threshold:

  Cost threshold for alerts

- auto_cleanup_s3:

  Automatically clean up S3 files after completion

- ...:

  Additional configuration options

## Examples

``` r
if (FALSE) { # \dontrun{
starburst_config(
  max_cost_per_job = 10,
  cost_alert_threshold = 5
)
} # }
```
