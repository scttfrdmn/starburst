# Create informative staRburst error

Creates error messages with context, solutions, and links to
documentation

## Usage

``` r
starburst_error(
  message,
  context = list(),
  solution = NULL,
  call = sys.call(-1)
)
```

## Arguments

- message:

  Main error message

- context:

  Named list of contextual information

- solution:

  Suggested solution (optional)

- call:

  Calling function (default: sys.call(-1))

## Value

Error condition with class "starburst_error"

## Examples

``` r
if (FALSE) { # \dontrun{
if (vcpus_needed > vcpus_available) {
  stop(starburst_error(
    "Insufficient Fargate vCPU quota",
    context = list(
      workers_requested = workers,
      vcpus_needed = vcpus_needed,
      vcpus_available = vcpus_available,
      region = region
    ),
    solution = "Request quota increase or reduce workers"
  ))
}
} # }
```
