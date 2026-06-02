# Utility functions for staRburst

General-purpose helpers shared across the package. AWS-specific helpers
live in dedicated files: `aws-clients.R` (service clients), `cost.R`
(pricing), `images.R` (ECR/Docker), `task-definition.R` (ECS task defs),
`network.R` (VPC), `task-registry.R` (task ARNs), and `s3-io.R` (S3
task/result transfer).
