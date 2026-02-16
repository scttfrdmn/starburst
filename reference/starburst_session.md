# Create a Detached Starburst Session

Creates a new detached session that can run computations independently
of your R session. You can close R and reattach later to collect
results.

## Usage

``` r
starburst_session(
  workers = 10,
  cpu = 4,
  memory = "8GB",
  region = NULL,
  timeout = 3600,
  session_timeout = 3600,
  absolute_timeout = 86400,
  launch_type = "FARGATE",
  instance_type = "c6a.large",
  use_spot = FALSE,
  warm_pool_timeout = 3600
)
```

## Arguments

- workers:

  Number of parallel workers (default: 10)

- cpu:

  vCPUs per worker (default: 4)

- memory:

  Memory per worker, e.g., "8GB" (default: "8GB")

- region:

  AWS region (default: from config or "us-east-1")

- timeout:

  Task timeout in seconds (default: 3600)

- session_timeout:

  Active timeout in seconds (default: 3600)

- absolute_timeout:

  Maximum session lifetime in seconds (default: 86400)

- launch_type:

  "FARGATE" or "EC2" (default: "FARGATE")

- instance_type:

  EC2 instance type for EC2 launch (default: "c6a.large")

- use_spot:

  Use spot instances for EC2 (default: FALSE)

- warm_pool_timeout:

  EC2 warm pool timeout in seconds (default: 3600)

## Value

A StarburstSession object with methods:

- `submit(expr, ...)` - Submit a task to the session

- `status()` - Get progress summary

- `collect(wait = FALSE)` - Collect completed results

- `extend(seconds = 3600)` - Extend timeout

- `cleanup()` - Terminate and cleanup

## Examples

``` r
if (FALSE) { # \dontrun{
# Create detached session
session <- starburst_session(workers = 10)

# Submit tasks
task_ids <- lapply(1:100, function(i) {
  session$submit(quote(expensive_computation(i)))
})

# Close R and come back later...
session_id <- session$session_id

# Reattach
session <- starburst_session_attach(session_id)

# Collect results
results <- session$collect(wait = TRUE)
} # }
```
