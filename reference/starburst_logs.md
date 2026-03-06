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

## Value

Invisibly returns the list of log events, or `NULL` if no events were
found.

## Examples

``` r
# \donttest{
# View recent logs
starburst_logs()
#> Error in get_starburst_config(): staRburst not configured. Run starburst_setup() first.

# View logs for specific task
starburst_logs(task_id = "abc-123")
#> Error in get_starburst_config(): staRburst not configured. Run starburst_setup() first.

# View last 100 lines
starburst_logs(last_n = 100)
#> Error in get_starburst_config(): staRburst not configured. Run starburst_setup() first.
# }
```
