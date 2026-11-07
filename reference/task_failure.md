# Why a future's worker task ended without a result, if it did

Checks ECS at most every
`getOption("starburst.task_check_interval", 15)` seconds. All of this R
session's pending tasks are described together (100 per call), so
polling many futures does not multiply API calls.

## Usage

``` r
task_failure(future, backend)
```

## Value

NULL while the task is fine, else a failure message
