## Resubmission (3rd)

This resubmission addresses all feedback from CRAN reviewer Beni Altmann
(2026-03-05).

### Changes made:

1. **DESCRIPTION**: Expanded 'AWS' acronym to 'Amazon Web Services' ('AWS')
   with link `<https://aws.amazon.com>`; quoted 'EC2' as a software name;
   removed `| file LICENSE` (standard Apache 2.0, no additional restrictions);
   bumped version to 0.3.7.

2. **Vignette syntax error**: Fixed unexecutable code in
   `vignettes/detached-sessions.Rmd` — `quote(Sys.sleep(60); i)` →
   `quote({ Sys.sleep(60); i })`.

3. **Examples for unexported functions**: Removed `@examples` from
   `starburst_error()` and `with_aws_retry()` (both `@keywords internal`).

4. **`\dontrun{}` → `\donttest{}`**: Replaced throughout all 17 exported
   function documentation blocks. Examples in `\donttest{}` require AWS
   credentials and infrastructure, which users with AWS accounts can run
   interactively.

5. **Missing `\value` tags**: Added `@return` documentation to all 12
   flagged exported functions.

### Note on `\donttest{}` examples

All examples require live AWS credentials, an S3 bucket, and ECR/ECS
infrastructure. Local `R CMD check --run-donttest` fails these examples
as expected (no AWS available during check). CRAN's automated incoming
check does not run `\donttest{}` examples.

## Test environments

* local: macOS 26.3 (Tahoe), R 4.5.2
* GitHub Actions:
  - Ubuntu 22.04, R oldrel-1, release, devel
  - Windows latest, R release
  - macOS latest, R release
* win-builder: R-devel (r89498)

## R CMD check results

0 errors ✓ | 0 warnings ✓ | 1 NOTE

```
* checking CRAN incoming feasibility ... NOTE
Maintainer: 'Scott Friedman <help@starburst.ing>'

New submission
```

This NOTE is expected and unavoidable for any new CRAN submission.

## Downstream dependencies

There are currently no downstream dependencies for this package.

## CRAN submission notes

The package provides seamless 'Amazon Web Services' ('AWS') cloud bursting
for parallel R workloads on 'EC2' and 'Fargate'.

Key points for reviewers:
- All tests requiring AWS credentials are gated with `skip_if_offline()`
  and will not run on CRAN's test servers
- Package includes 12 vignettes with real-world examples in `inst/doc/`
- Default backend is 'EC2' with spot instances for cost optimization
- Fully documented with 29+ exported functions
