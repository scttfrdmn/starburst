# Monitor quota increase request

Monitor quota increase request

## Usage

``` r
starburst_check_quota_request(case_id, region = NULL)
```

## Arguments

- case_id:

  Case ID from quota increase request

- region:

  AWS region

## Value

Invisibly returns the quota request details, or `NULL` on error.

## Examples

``` r
# \donttest{
if (starburst_is_configured()) {
  starburst_check_quota_request("case-12345")
}
# }
```
