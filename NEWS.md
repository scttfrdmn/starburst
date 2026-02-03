# starburst 0.1.0 (Development)

## Initial Release

* Initial development version
* Core features:
  - future backend for AWS Fargate
  - Automatic environment synchronization with renv
  - Wave-based quota management
  - Cost estimation and tracking
  - One-time setup wizard
  - Transparent quota handling with automatic increase requests

## Known Limitations

* Docker image building not yet implemented (coming in 0.1.1)
* No GPU support (planned for v1.1)
* No Spot instance support (planned for v1.1)
* Limited to Fargate resources (16 vCPU, 120GB RAM max)
