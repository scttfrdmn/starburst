# Release a warm pool after a run

Called when a cluster, plan or session finishes with its EC2 pool. With
`warm_pool_timeout = 0` the pool is released now: scaled to zero if the
cluster has no other running tasks, otherwise left for ECS managed
scaling to drain once those finish. Otherwise it stays warm for
`warm_pool_timeout` more seconds (see
[`hold_warm_pool()`](https://starburst.ing/reference/hold_warm_pool.md)).

## Usage

``` r
release_warm_pool(backend)
```

## Arguments

- backend:

  Backend configuration object

## Value

Invisible NULL
