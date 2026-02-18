## Test environments

* local: macOS 14.2 (Tahoe), R 4.5.2
* GitHub Actions:
  - Ubuntu 22.04, R oldrel-1, release, devel
  - Windows latest, R release
  - macOS latest, R release
* win-builder: R-devel, R-release

## R CMD check results

0 errors ✓ | 0 warnings ✓ | 1 NOTE

```
* checking CRAN incoming feasibility ... NOTE
Maintainer: 'Scott Friedman <help@starburst.ing>'

New submission

Package has a VignetteBuilder field but no prebuilt vignette index.
```

**Explanation:** This is expected behavior for source packages. The package has 12 vignettes in `vignettes/` with proper YAML metadata, and `VignetteBuilder: knitr` is correctly specified in DESCRIPTION. Vignettes build successfully during `R CMD check`. The NOTE appears because `inst/doc/` is not included in the source package (following R package best practices). CRAN will build vignettes during the check process.

## Downstream dependencies

There are currently no downstream dependencies for this package.

## CRAN submission notes

This is a new submission of the staRburst package. The package provides seamless AWS cloud bursting capabilities for parallel R workloads on AWS (EC2 and Fargate backends).

Key points for reviewers:
- All tests that require AWS credentials are properly gated with `skip_if_offline()` and will not run on CRAN's test servers
- Package includes 12 vignettes with real-world examples
- Default backend is EC2 with spot instances for cost optimization
- Fully documented with 29+ exported functions
