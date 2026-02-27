## Resubmission

This is a resubmission addressing the CRAN auto-check NOTE from 2026-02-18:

> Package has a VignetteBuilder field but no prebuilt vignette index.

**Fix applied:** Pre-built vignettes are now included in `inst/doc/`. All 12
vignettes were built with `devtools::build_vignettes()` and the resulting HTML,
R, and Rmd files are committed to `inst/doc/` and included in the package tarball.

## Test environments

* local: macOS 14.2 (Tahoe), R 4.5.2
* GitHub Actions:
  - Ubuntu 22.04, R oldrel-1, release, devel
  - Windows latest, R release
  - macOS latest, R release
* win-builder: R-devel, R-release

## R CMD check results

0 errors ✓ | 0 warnings ✓ | 0 notes ✓

Local check with `devtools::check()` now shows no VignetteBuilder NOTE after
adding pre-built vignettes to `inst/doc/`.

## Downstream dependencies

There are currently no downstream dependencies for this package.

## CRAN submission notes

The package provides seamless AWS cloud bursting capabilities for parallel R
workloads on AWS (EC2 and Fargate backends).

Key points for reviewers:
- All tests that require AWS credentials are properly gated with `skip_if_offline()` and will not run on CRAN's test servers
- Package includes 12 vignettes with real-world examples in `inst/doc/`
- Default backend is EC2 with spot instances for cost optimization
- Fully documented with 29+ exported functions
