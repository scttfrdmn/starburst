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
