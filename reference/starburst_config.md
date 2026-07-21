# Configure staRburst options

Reads and updates the persisted staRburst configuration. Call with no
arguments to leave settings unchanged (it still returns the current
config invisibly); pass one or more of the arguments below to update
them.

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

  Maximum estimated cost (USD) for a single job. Jobs whose estimate
  exceeds this error before launching. `NULL` leaves it unchanged.

- cost_alert_threshold:

  Estimated cost (USD) at which a warning is emitted. `NULL` leaves it
  unchanged.

- auto_cleanup_s3:

  Logical; automatically delete a job's S3 task/result objects after
  completion. `NULL` leaves it unchanged.

- ...:

  Additional user-settable keys merged into the config. Recognized keys:

  `use_public_base`

  :   Logical; pull the public base image instead of building a private
      one (see
      [`starburst_setup`](https://starburst.ing/reference/starburst_setup.md)).

  `ecr_image_ttl_days`

  :   Integer; lifecycle age at which cached ECR images are expired.

## Value

Invisibly returns the updated configuration list.

## Details

Other keys in the stored config are \*\*infrastructure-managed\*\* —
written by
[`starburst_setup`](https://starburst.ing/reference/starburst_setup.md)/[`starburst_setup_ec2`](https://starburst.ing/reference/starburst_setup_ec2.md)
and not intended to be set by hand: `region`, `bucket`, `cluster`,
`ecr_repository`, `aws_account_id`, `execution_role_arn`,
`task_role_arn`, `subnets`, and `security_groups`. Use
[`starburst_status`](https://starburst.ing/reference/starburst_status.md)
to inspect the effective configuration read-only.

## See also

[`starburst_status`](https://starburst.ing/reference/starburst_status.md)
to view config without changing it;
[`starburst_setup`](https://starburst.ing/reference/starburst_setup.md)
for initial provisioning.

## Examples

``` r
# \donttest{
if (starburst_is_configured()) {
  # Update cost guardrails
  starburst_config(
    max_cost_per_job = 10,
    cost_alert_threshold = 5
  )

  # Read the current config without changing anything
  cfg <- starburst_config()
}
# }
```
