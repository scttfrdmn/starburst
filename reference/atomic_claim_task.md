# Atomically claim a pending task

This is a helper that combines get + conditional update in one operation

## Usage

``` r
atomic_claim_task(session_id, task_id, worker_id, region, bucket)
```

## Arguments

- session_id:

  Session identifier

- task_id:

  Task identifier

- worker_id:

  Worker identifier claiming the task

- region:

  AWS region

- bucket:

  S3 bucket

## Value

TRUE if claimed successfully, FALSE if already claimed
