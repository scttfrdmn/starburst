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
  launch_type = "EC2",
  instance_type = "c7g.xlarge",
  use_spot = TRUE,
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

  "EC2" or "FARGATE" (default: "EC2")

- instance_type:

  EC2 instance type for EC2 launch (default: "c7g.xlarge")

- use_spot:

  Use spot instances for EC2 (default: TRUE)

- warm_pool_timeout:

  EC2 warm pool timeout in seconds (default: 3600)

## Value

A `StarburstSession` object (also carrying `$session_id`, the handle you
pass to
[`starburst_session_attach`](https://starburst.ing/reference/starburst_session_attach.md))
with methods:

- `submit(expr, globals = NULL, packages = NULL)`:

  Submit one task (a quoted expression). Returns the task id. Call
  repeatedly to fan out work.

- `status()`:

  Return a progress summary (counts of pending / running / completed /
  failed tasks). Safe to call from a fresh R session after reattaching.

- `collect(wait = FALSE)`:

  Retrieve results. With `wait = FALSE` returns whatever has completed
  so far; with `wait = TRUE` blocks until all submitted tasks finish.
  Results come back in submission order.

- `extend(seconds = 3600)`:

  Extend the active/absolute timeout of a still-running session.

- `cleanup()`:

  Stop all tasks/workers for the session and delete its S3 objects. Call
  when done; otherwise the session self-terminates at
  `absolute_timeout`.

## Lifecycle

`starburst_session()` launches workers immediately and returns a handle.
Submit tasks, then either poll `status()`/`collect()` in the same
session, or record `session$session_id`, close R, and later
[`starburst_session_attach`](https://starburst.ing/reference/starburst_session_attach.md)`(session_id)`
to reconnect and collect. A session ends when you call `cleanup()`, when
`session_timeout` elapses with no activity, or at `absolute_timeout` —
whichever comes first.

## Failure behavior

A failed task is recorded (surfaced via `status()`) and does not abort
the others; its error is raised when you `collect()` that result. If the
client dies, workers keep running against S3 until a timeout, which is
what makes reattaching possible. `cleanup()` is the only thing that
frees resources early — sessions do not auto-clean on garbage
collection.

## See also

[`starburst_session_attach`](https://starburst.ing/reference/starburst_session_attach.md),
[`starburst_list_sessions`](https://starburst.ing/reference/starburst_list_sessions.md);
[`starburst_map`](https://starburst.ing/reference/starburst_map.md) for
ephemeral (non-detached) fan-out.

## Examples

``` r
# \donttest{
if (starburst_is_configured()) {
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
}
# }
```
