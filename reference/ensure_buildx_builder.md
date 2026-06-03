# Ensure a buildx builder with the docker-container driver exists and is usable

Idempotent across repeated runs and cross-platform
(Windows/macOS/Linux). Probes for an existing builder via
`docker buildx inspect`; creates it only when missing; bootstraps it so
it is ready to build. A docker-container driver is required for
multi-platform (`linux/amd64,linux/arm64`) builds. Does not mutate the
user's default buildx context (no `--use`); the build pins the builder
explicitly via `--builder`.

## Usage

``` r
ensure_buildx_builder(builder_name = "starburst-builder")
```

## Arguments

- builder_name:

  Name of the buildx builder (default "starburst-builder")

## Value

TRUE if the named builder is usable, FALSE otherwise

## Details

Returns TRUE if the named builder is usable, FALSE otherwise, and never
throws – callers decide policy. This fixes the failure mode where
`buildx create` errored on an already-existing builder, the error was
swallowed, and the subsequent `buildx build` failed with "existing
instance for \<name\> but no append mode" (GitHub \#24).
