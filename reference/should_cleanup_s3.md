# Resolve whether to auto-clean S3 files after a job

Order: the `starburst.cleanup_s3` option (explicit runtime override),
then the persisted `auto_cleanup_s3` config (set via
[`starburst_config`](https://starburst.ing/reference/starburst_config.md)),
then default `TRUE`.

## Usage

``` r
should_cleanup_s3()
```
