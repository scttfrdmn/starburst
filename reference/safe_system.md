# Execute system command safely (no shell injection)

Execute system command safely (no shell injection)

## Usage

``` r
safe_system(
  command,
  args = character(),
  allowed_commands = c("docker", "aws", "uname", "sysctl", "cat", "nproc"),
  stdin = NULL,
  ...
)
```

## Arguments

- command:

  Command to execute (must be in whitelist)

- args:

  Character vector of arguments

- allowed_commands:

  Commands allowed to be executed

- stdin:

  Optional input to pass to stdin

- ...:

  Additional arguments passed to processx::run()

## Value

Result from processx::run()
