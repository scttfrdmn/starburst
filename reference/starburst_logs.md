# View worker logs

View worker logs

## Usage

``` r
starburst_logs(task_id = NULL, cluster_id = NULL, last_n = 50, region = NULL)
```

## Arguments

- task_id:

  Optional task ID to view logs for specific task

- cluster_id:

  Optional cluster ID to view logs for specific cluster

- last_n:

  Number of last log lines to show (default: 50)

- region:

  AWS region (default: from config)

## Examples

``` r
if (FALSE) { # \dontrun{
# View recent logs
starburst_logs()

# View logs for specific task
starburst_logs(task_id = "abc-123")

# View last 100 lines
starburst_logs(last_n = 100)
} # }
```
