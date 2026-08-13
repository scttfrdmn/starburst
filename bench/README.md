# staRburst benchmark harness

Reproducible, phase-split benchmarks for the timings cited in the example
vignettes. Turns "persuasive illustration" into engineering evidence: every run
records full disclosure metadata and splits wall-clock into **startup**,
**compute + collect**, and **total**, with an estimated cost.

## ⚠️ Opt-in only — this spends real money

`benchmark.R` launches **real, billable AWS workers**. It is intentionally **never
run in CI or on CRAN** and refuses to run unless you opt in:

```bash
STARBURST_BENCH=TRUE AWS_PROFILE=aws Rscript bench/benchmark.R geospatial
```

Prerequisites: staRburst configured (`starburst_is_configured()` is `TRUE` — run
`starburst_setup()` first) and AWS credentials available.

## Usage

```bash
# One workload, cold start (startup included in the total)
STARBURST_BENCH=TRUE AWS_PROFILE=aws Rscript bench/benchmark.R bootstrap

# Warm run: runs twice, reports the second (startup excluded by design)
STARBURST_BENCH=TRUE AWS_PROFILE=aws Rscript bench/benchmark.R bootstrap --warm

# All workloads
STARBURST_BENCH=TRUE AWS_PROFILE=aws Rscript bench/benchmark.R all

# Overrides
STARBURST_BENCH=TRUE AWS_PROFILE=aws Rscript bench/benchmark.R geospatial \
  --workers 40 --launch-type FARGATE --out bench/results/geo-fargate.md
```

Workloads: `geospatial`, `bootstrap`, `montecarlo` (see the `WORKLOADS` list in
`benchmark.R`). Each is sized to be a meaningful benchmark, matching the vignette
it backs.

## Output

Writes a markdown table (paste-ready for a vignette) and a machine-readable `.rds`
to `bench/results/<workload>-<date>.md`. The table columns are:

| Column | Meaning |
|---|---|
| Local (seq) | Sequential baseline on this machine, compute only |
| Startup | One-time cluster provision + image pull (0 for `--warm`) |
| Compute+collect | Submit → run on workers → collect results |
| Cloud total | Startup + compute+collect (startup only counted for cold runs) |
| Est. cost | From `cluster$estimate_cost()` for the measured wall-clock |

Plus a metadata block: staRburst version, date, region, backend, Spot, cold/warm,
and local machine.

## Status (2026-07)

The harness is **working end-to-end on real AWS**: it builds the worker image, launches
workers, and the workers execute and write real results to S3. Its geospatial run
produced the measured table now published in `vignette("example-geospatial")`.

Bringing it up surfaced three staRburst integration bugs, all since **fixed**:

| Symptom in the live run | Issue | Fixed in |
|---|---|---|
| `starburst_session(launch_type="EC2")` failed with `AutoScalingGroup name not found` — it called `set_desired_capacity` on an ASG it never created | [#37](https://github.com/scttfrdmn/starburst/issues/37) | `b9cfc67` — `starburst_setup()` now provisions the default capacity provider |
| `use_public_base=TRUE` build failed "no match for platform": the env build is `--platform linux/amd64,linux/arm64` but the public base was amd64-only | [#39](https://github.com/scttfrdmn/starburst/issues/39) | `13b1252` — public base images are built multi-arch |
| `collect(wait=TRUE)` hung even though all results were present in `s3://…/results/` | [#38](https://github.com/scttfrdmn/starburst/issues/38) | `ce743b5` |

One constraint remains, and it is a property of the harness rather than a bug:

**The worker renv.lock must exactly match the base image.** An empty lock makes worker.R
fail to load `paws.storage`; a lock with *more* packages than the base triggers real
installs under arm64 emulation and the build fails. `bench/worker-renv.lock` is generated
from the base image's own `installed.packages()` for this reason (regeneration command in
the header of `benchmark.R`).

## Regenerating vignette tables

`vignette("example-geospatial")` carries **measured** numbers produced here. The other
example vignettes still carry **illustrative** timings, each labelled as such with a
"warm-compute-only, excludes startup" caveat. To replace one with measured numbers, run
the matching workload here and copy the emitted row into that vignette's Performance
section, keeping the disclosure metadata. Until a table is regenerated this way, it stays
labelled illustrative — don't present hand-written numbers as measured.
