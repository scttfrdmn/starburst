# Create ECR lifecycle policy to auto-delete old images

Create ECR lifecycle policy to auto-delete old images

## Usage

``` r
create_ecr_lifecycle_policy(region, repository_name, ttl_days = NULL)
```

## Arguments

- region:

  AWS region

- repository_name:

  ECR repository name

- ttl_days:

  Number of days to keep images (NULL = no auto-delete)
