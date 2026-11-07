# Mutable state behind a backend

A future `StarburstBackend` keeps its state in an environment attached
as `attr(, "backend")`; the backend from
[`plan.starburst()`](https://starburst.ing/reference/plan.starburst.md)
is that environment itself.

## Usage

``` r
backend_state(backend)
```
