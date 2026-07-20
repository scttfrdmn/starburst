# Check if a public base image exists (anonymously)

Public ECR images are world-readable, so we can probe the manifest
without credentials via \`docker manifest inspect\`. Returns FALSE on
any error (Docker missing, network issue, tag absent) so callers fall
back to a private build.

## Usage

``` r
public_base_image_exists(image_uri)
```

## Arguments

- image_uri:

  Full public image reference, e.g.
  `public.ecr.aws/f8g1e7l5/base:r4.6.1`.

## Value

TRUE if the manifest is retrievable, FALSE otherwise.
