# Get EC2 instance pricing (live, cached, with static fallback)

Looks up the current AWS price for an instance type. On-Demand rates
come from the AWS Pricing API and Spot rates from EC2 spot-price
history; both are cached per session. Any failure (offline, missing
perms, unknown type) falls back to a built-in static rate, so cost
estimates always return a number.

## Usage

``` r
get_ec2_instance_price(instance_type, use_spot = FALSE, region = NULL)
```

## Arguments

- instance_type:

  EC2 instance type (e.g., "c7g.xlarge")

- use_spot:

  Whether to use spot pricing

- region:

  AWS region (default: from config or "us-east-1")

## Value

Price per hour in USD
