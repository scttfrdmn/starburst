# Create a Future using Starburst Backend

This is the entry point called by the Future package when a
plan(starburst) is active

## Usage

``` r
# S3 method for class 'starburst'
future(
  expr,
  envir = parent.frame(),
  substitute = TRUE,
  lazy = FALSE,
  seed = FALSE,
  globals = TRUE,
  packages = NULL,
  stdout = TRUE,
  conditions = "condition",
  label = NULL,
  ...
)
```

## Arguments

- expr:

  Expression to evaluate

- envir:

  Environment for evaluation

- substitute:

  Whether to substitute the expression

- lazy:

  Whether to lazily evaluate (always FALSE for remote)

- seed:

  Random seed

- globals:

  Globals to export (TRUE for auto-detection, list for manual)

- packages:

  Packages to load

- stdout:

  Whether to capture stdout (TRUE, FALSE, or NA)

- conditions:

  Character vector of condition classes to capture

- label:

  Optional label for the future

- ...:

  Additional arguments

## Value

A StarburstFuture object
