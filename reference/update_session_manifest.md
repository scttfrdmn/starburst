# Update session manifest atomically

Uses S3 ETags for optimistic locking to prevent race conditions.

## Usage

``` r
update_session_manifest(session_id, updates, region, bucket, max_retries = 3)
```

## Arguments

- session_id:

  Session identifier

- updates:

  Named list of fields to update

- region:

  AWS region

- bucket:

  S3 bucket

- max_retries:

  Maximum number of retry attempts (default: 3)

## Value

Invisibly returns updated manifest
