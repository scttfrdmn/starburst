# Create task status in S3

Create task status in S3

## Usage

``` r
create_task_status(session_id, task_id, state = "pending", region, bucket)
```

## Arguments

- session_id:

  Session identifier

- task_id:

  Task identifier

- state:

  Initial state (default: "pending")

- region:

  AWS region

- bucket:

  S3 bucket

## Value

Invisibly returns NULL
