# Compute environment image hash

Computes the hash used to tag environment Docker images, combining the
renv.lock file contents with the starburst package version and the
worker script baked into the image. This ensures new images are built
when either the R package environment or the starburst worker script
changes (including unreleased worker changes under an unchanged
version).

## Usage

``` r
compute_env_hash(lock_file)
```

## Arguments

- lock_file:

  Path to renv.lock file

## Value

MD5 hash string
