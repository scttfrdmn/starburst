## Submission

This is a patch update from the current CRAN release (0.3.10, accepted
2026-10-24) to 0.3.11. It fixes bugs that made the package's main `future`
backend fail on real AWS.

### Bug fixes in 0.3.11

* The worker script (`inst/templates/worker.R`) uploaded results of
  `plan(starburst)` futures under an empty S3 key, so every such future failed
  remotely.
* `starburst_map()` and `starburst_cluster()` registered a strategy that
  `future::plan()` rejects; they now submit to their own backend without
  changing the active plan.
* Errors from remote workers were returned in a `FutureResult` with malformed
  `conditions`, which `future` reported as an internal error; they now use
  `future::FutureResult()` and keep the original message.
* Canceled futures (e.g. after an error in `future.apply`) never counted as
  resolved, so collecting results could wait forever.
* EC2 task submission from `starburst_map()`/`starburst_cluster()` used invalid
  parameters and unplaceable task sizes.

Offline regression tests cover all of these, including new round-trip tests
that run the shipped worker script against the client code. No exported API
was removed. See NEWS.md.

## Test environments

* local: Docker rocker/r-ver:4.6.1 (Ubuntu 24.04, aarch64), R 4.6.1
* GitHub Actions:
  - Ubuntu latest, R oldrel-1, release, devel
  - Windows latest, R release
  - macOS latest, R release
* win-builder: R-devel

## R CMD check results

0 errors | 0 warnings | 0 notes

All tests requiring AWS credentials are gated (skipped on CRAN); `\donttest`
examples guard on `starburst_is_configured()` and make no network calls when
credentials are absent.

## Downstream dependencies

There are currently no downstream dependencies for this package.
