# Stop workers for StarburstBackend

Called by future when the plan changes (e.g. `plan(sequential)`): stops
this backend's remaining tasks, cleans up its S3 objects, and holds the
EC2 pool for `warm_pool_timeout` before releasing it.

## Usage

``` r
# S3 method for class 'StarburstBackend'
stopWorkers(backend, ...)
```

## Arguments

- backend:

  A StarburstBackend object

- ...:

  Additional arguments

## Value

TRUE (invisibly)
