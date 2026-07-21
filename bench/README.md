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

## Regenerating vignette tables

The example vignettes (`vignettes/example-*.Rmd`) currently carry **illustrative**
timings with an honest "warm-compute-only, excludes startup" caveat. To replace any
of them with measured numbers, run the matching workload here and copy the emitted
row into that vignette's Performance section, keeping the disclosure note. Until a
table is regenerated this way, it stays labelled illustrative — don't present
hand-written numbers as measured.
