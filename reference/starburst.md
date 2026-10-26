# Starburst strategy marker

This function should never be called directly. Use plan(starburst, ...)
instead.

## Usage

``` r
starburst(...)
```

## Arguments

- ...:

  Arguments passed to StarburstBackend()

## Value

Does not return a value; always signals an error if called directly.
This object exists as a strategy marker for
[`plan`](https://future.futureverse.org/reference/plan.html).

## See also

[`plan.starburst`](https://starburst.ing/reference/plan.starburst.md)
for the worker, backend, and cost arguments.

## Examples

``` r
# \donttest{
if (starburst_is_configured()) {
  # Pass `starburst` to plan(); existing future code then runs on AWS workers
  future::plan(starburst, workers = 4)
  f <- future::future(Sys.info()[["nodename"]])
  future::value(f)
  future::plan(future::sequential)
}
# }
```
