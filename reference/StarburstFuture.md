# StarburstFuture Constructor

Creates a Future object for evaluation on AWS Fargate

## Usage

``` r
StarburstFuture(
  expr,
  envir = parent.frame(),
  substitute = TRUE,
  globals = TRUE,
  packages = NULL,
  lazy = FALSE,
  seed = FALSE,
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

- globals:

  Globals to export (TRUE for auto-detection, list for manual)

- packages:

  Packages to load

- lazy:

  Whether to lazily evaluate (always FALSE for remote)

- seed:

  Random seed

- ...:

  Additional arguments

## Value

A StarburstFuture object
