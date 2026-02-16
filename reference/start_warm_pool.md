# Start warm EC2 pool

Scales Auto-Scaling Group to desired capacity and waits for instances

## Usage

``` r
start_warm_pool(backend, capacity, timeout_seconds = 180)
```

## Arguments

- backend:

  Backend configuration object

- capacity:

  Desired number of instances

- timeout_seconds:

  Maximum time to wait for instances (default: 180)

## Value

Invisible NULL
