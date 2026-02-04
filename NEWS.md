# starburst 0.2.0 (2026-02-04)

## Major Features

* **Multi-stage base image system** for dramatically faster builds
  - Base images contain system dependencies + core R packages
  - Project images only install project-specific packages
  - Reduces typical build times from 20 min to 3-5 min
  - One-time base build per R version, reused across all projects

* **Complete Docker dependency support**
  - Added 15 system packages for comprehensive R package compilation
  - Supports graphics packages (ragg, systemfonts, textshaping)
  - Supports data packages (httpuv, readr, haven)
  - All common CRAN packages now compile successfully

* **Fixed globals serialization** (#1)
  - Proper function closure capture for remote execution
  - Converts plain lists to `globals::Globals` objects
  - Ensures variables are correctly serialized to workers

## Performance Improvements

* **ECR image caching validated** with 40x speedup
  - First run: ~42 min (one-time Docker build)
  - Subsequent runs: ~1 min (cached image from ECR)
  - No rebuild needed when renv.lock unchanged

* **Build time optimizations**
  - Dev environment (112 packages): 20 min → 6-8 min
  - Production (30 packages): 8-10 min → 3-5 min
  - Minimal projects: 3-5 min → 1-2 min

## New Functions

* `build_base_image()` - Build base Docker image with common dependencies
* `ensure_base_image()` - Check for/create base image as needed
* `get_base_image_uri()` - Get ECR URI for base image

## Bug Fixes

* Fixed globals serialization causing empty results from workers
* Added missing system dependencies for package compilation
* Resolved Docker build failures for graphics packages

## Infrastructure

* New `inst/templates/Dockerfile.base` for base image builds
* Simplified `inst/templates/Dockerfile.template` (42 → 19 lines)
* Base images tagged by R version: `base-{R.VERSION}`

## Known Limitations

* No GPU support (planned for v1.0)
* No Spot instance support (planned for v1.0)
* Limited to Fargate resources (16 vCPU, 120GB RAM max)
* Public base images not yet available (coming in 0.3.0)

---

# starburst 0.1.0 (2026-02-03)

## Initial Release

* Initial development version
* Core features:
  - future backend for AWS Fargate
  - Automatic environment synchronization with renv
  - Wave-based quota management
  - Cost estimation and tracking
  - One-time setup wizard
  - Transparent quota handling with automatic increase requests
