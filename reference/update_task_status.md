# Update task status with atomic write

Update task status with atomic write

## Usage

``` r
update_task_status(
  session_id,
  task_id,
  state,
  etag = NULL,
  region,
  bucket,
  updates = list()
)
```

## Arguments

- session_id:

  Session identifier

- task_id:

  Task identifier

- state:

  New state

- etag:

  Optional ETag for conditional write (atomic claiming)

- region:

  AWS region

- bucket:

  S3 bucket

- updates:

  Optional additional fields to update

## Value

TRUE if successful, FALSE if conditional write failed
