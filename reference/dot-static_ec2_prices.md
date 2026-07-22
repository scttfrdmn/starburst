# Built-in fallback EC2 On-Demand prices (us-east-1, Linux, per hour).

Used when the live AWS Pricing API can't be reached (offline, missing
perms, or an unknown type). Kept as a static snapshot so cost estimates
always work.

## Usage

``` r
.static_ec2_prices()
```
