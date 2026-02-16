# Check ECR image age and suggest/force rebuild

Check ECR image age and suggest/force rebuild

## Usage

``` r
check_ecr_image_age(region, image_tag, ttl_days = NULL, force_rebuild = FALSE)
```

## Arguments

- region:

  AWS region

- image_tag:

  Image tag to check

- ttl_days:

  TTL setting (NULL = no check)

- force_rebuild:

  Force rebuild if past TTL

## Value

TRUE if image is fresh or doesn't exist, FALSE if stale
