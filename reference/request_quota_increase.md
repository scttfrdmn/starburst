# Request quota increase

Request quota increase

## Usage

``` r
request_quota_increase(service, quota_code, desired_value, region, reason = "")
```

## Arguments

- service:

  AWS service (e.g., "fargate")

- quota_code:

  Service quota code

- desired_value:

  Desired quota value

- region:

  AWS region

- reason:

  Justification for increase

## Value

Case ID if successful, NULL if failed
