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

## Status / findings from the first live runs (2026-07)

The harness was exercised end-to-end on real AWS. It **works**: it builds the worker
image, launches workers, and the workers execute and write real results to S3
(verified — 20 distinct per-region geospatial outputs). Getting there surfaced four
real staRburst behaviors worth knowing (and coding around here):

1. **Session path needs a pre-provisioned ASG.** `starburst_session(launch_type="EC2")`
   calls `set_desired_capacity` on `starburst-asg-<instance-type>` but does not create
   it — you must run `starburst_setup_ec2(instance_types="<type>")` once first, or you
   get `AutoScalingGroup name not found`. The harness defaults to `c7i.xlarge` for this
   reason; override with `--instance-type` only for a type you've provisioned.
2. **The public base image must be multi-arch.** staRburst's env build is hardcoded
   `--platform linux/amd64,linux/arm64`; if `use_public_base=TRUE` points at an
   amd64-only public base, the build fails "no match for platform". Use a multi-arch
   private base (`starburst_config` `use_public_base=FALSE`).
3. **The worker renv.lock must exactly match the base image.** An empty lock makes
   worker.R fail to load `paws.storage`; a lock with *more* packages than the base
   triggers real installs under arm64 emulation and the build fails. `bench/worker-renv.lock`
   is generated from the base image's own `installed.packages()` for this reason.
4. **`collect(wait=TRUE)` can hang even after all results land in S3.** In the live
   run all 20 results were present in `s3://.../results/` but the client's blocking
   collect did not return. Until that is fixed upstream, the harness cannot reliably
   auto-emit the compute-phase timing; the vignette tables therefore remain labelled
   **illustrative** rather than replaced with measured numbers.

These are staRburst integration gaps, not harness bugs — see the project's follow-up
issues. The `--warm` path and cost estimate are wired and correct; the blocker to
fully-measured tables is (4).

## Regenerating vignette tables

The example vignettes (`vignettes/example-*.Rmd`) currently carry **illustrative**
timings with an honest "warm-compute-only, excludes startup" caveat. To replace any
of them with measured numbers, run the matching workload here and copy the emitted
row into that vignette's Performance section, keeping the disclosure note. Until a
table is regenerated this way, it stays labelled illustrative — don't present
hand-written numbers as measured.
