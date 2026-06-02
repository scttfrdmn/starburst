# ECR repositories and Docker environment images for staRburst

Functions for building and tracking the worker Docker images stored in
ECR, including the shared base image and per-environment images keyed by
a hash of the project's renv.lock.
