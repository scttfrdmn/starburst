# Keep a warm pool for warm_pool_timeout seconds from now

Holds the pool at its current size (ASG `MinSize`, so ECS managed
scaling does not drain idle instances between runs) and schedules an ASG
action that lowers `MinSize` to zero `warm_pool_timeout` seconds from
now. Called when the pool starts and, at most once a minute, on each
submission, so the timeout counts from the last activity. Because the
release is always scheduled on AWS, a crashed or exited R session never
leaves a pool held: it expires at most `warm_pool_timeout` after the
last submission, and ECS managed scaling then removes the idle instances
(usually within about 15 minutes). Instances still running tasks are
never removed.

## Usage

``` r
hold_warm_pool(backend, force = FALSE)
```

## Arguments

- backend:

  Backend configuration object

- force:

  Refresh even if refreshed in the last minute

## Value

Invisible NULL
