# Get task status from S3

Get task status from S3

## Usage

``` r
get_task_status(session_id, task_id, region, bucket, include_etag = FALSE)
```

## Arguments

- session_id:

  Session identifier

- task_id:

  Task identifier

- region:

  AWS region

- bucket:

  S3 bucket

- include_etag:

  Include ETag in result (for atomic operations)

## Value

Task status list (with optional \$etag field)
