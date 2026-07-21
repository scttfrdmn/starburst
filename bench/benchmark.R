#!/usr/bin/env Rscript
# bench/benchmark.R — Reproducible, phase-split benchmark harness for staRburst.
#
# Produces the timing tables the example vignettes cite, as trustworthy engineering
# evidence rather than hand-written numbers. For each run it records the full
# disclosure metadata (version / region / backend / worker type & count / spot /
# cold-or-warm / input size / local machine / date) and splits wall-clock into
# infrastructure startup, computation, and result collection, plus estimated cost.
#
# OPT-IN ONLY. This launches REAL, BILLABLE AWS workers, so it never runs in CI or
# on CRAN — it refuses to do anything unless STARBURST_BENCH=TRUE is set.
#
# Usage:
#   STARBURST_BENCH=TRUE AWS_PROFILE=aws Rscript bench/benchmark.R geospatial
#   STARBURST_BENCH=TRUE AWS_PROFILE=aws Rscript bench/benchmark.R geospatial --warm
#   STARBURST_BENCH=TRUE AWS_PROFILE=aws Rscript bench/benchmark.R all
#
# Flags:
#   --warm            Reuse an already-warm pool: run the workload twice and report
#                     the second (warm) run, so startup is excluded/near-zero.
#   --workers N       Override worker count (default: per-workload).
#   --launch-type X   "EC2" (default) or "FARGATE".
#   --out PATH        Markdown output file (default: bench/results/<name>-<date>.md).
#
# Results are written as a markdown table you can paste into a vignette, plus a
# machine-readable .rds alongside it.

suppressWarnings(suppressMessages({
  library(starburst)
  library(jsonlite)
}))

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

# ---- Guard: never run without explicit opt-in --------------------------------
if (!identical(Sys.getenv("STARBURST_BENCH"), "TRUE")) {
  stop("bench/benchmark.R launches real, billable AWS workers.\n",
       "Set STARBURST_BENCH=TRUE to run it. It is intentionally never run in CI/CRAN.")
}

# ---- Isolate the worker environment ------------------------------------------
# staRburst builds the worker image by restoring the renv.lock nearest an R/ dir.
# If we run from the staRburst repo, that is the ~250KB DEV lockfile (hundreds of
# packages) — a slow, fragile multi-arch build for a benchmark whose workloads
# only use base R. Run from an isolated temp dir with a COMPLETE-but-minimal lock.
#
# CRITICAL: the lock must list ALL worker-runtime packages, not be empty. staRburst
# builds the env image with `renv::init(bare=TRUE); renv::restore()`, which isolates
# .libPaths() to the project library — so any package NOT in the lock (even ones
# baked into the base image, e.g. paws.storage/qs2) becomes invisible at runtime
# and worker.R fails to bootstrap. We generate the lock FROM the base image's own
# installed packages so restore is a no-op and every worker dep is present.
.orig_wd <- normalizePath(getwd())
.bench_wd <- file.path(tempdir(), "starburst-bench-env")
dir.create(.bench_wd, showWarnings = FALSE, recursive = TRUE)
.lock_path <- file.path(.bench_wd, "renv.lock")

# Use the committed worker lock: the EXACT package set of the base image (generated
# once via `installed.packages()` inside the base container). It must match the base
# so `renv::restore()` on the worker is a no-op — a lock with MORE packages triggers
# real installs/compiles under arm64 emulation (build failure), and an EMPTY lock
# makes worker.R fail to load paws.storage. Regenerate with:
#   docker run --rm --platform linux/amd64 -v $PWD:/out <base-image> Rscript -e \
#     'ip<-installed.packages();b<-rownames(installed.packages(priority="base"));
#      P<-list();for(p in setdiff(rownames(ip),c(b,"starburst")))
#      P[[p]]<-list(Package=p,Version=unname(ip[p,"Version"]),Source="Repository",Repository="CRAN");
#      jsonlite::write_json(list(R=list(Version=paste(R.version$major,R.version$minor,sep="."),
#      Repositories=list(list(Name="CRAN",URL="https://cloud.r-project.org"))),Packages=P),
#      "/out/worker-renv.lock",auto_unbox=TRUE,pretty=TRUE)'
.committed_lock <- file.path(.orig_wd, "bench", "worker-renv.lock")
if (!file.exists(.committed_lock)) {
  stop("[bench] missing bench/worker-renv.lock — regenerate it from the base image ",
       "(see the comment in benchmark.R).")
}
file.copy(.committed_lock, .lock_path, overwrite = TRUE)
message("[bench] worker env isolated in ", .bench_wd,
        " (using committed bench/worker-renv.lock)")
setwd(.bench_wd)

# ---- Workload registry -------------------------------------------------------
# Each workload is sized to be a MEANINGFUL benchmark (per-task work in the
# seconds+, many tasks), matching the example vignettes it backs. `local()` gives
# the sequential baseline; `f`/`x` are the mapped function and inputs.
WORKLOADS <- list(
  geospatial = list(
    label = "Geospatial analysis (per-region terrain stats)",
    n = 20L, workers = 20L,
    f = function(region_id) {
      set.seed(region_id)
      # stand-in for real raster work: heavy per-region compute
      grid <- matrix(rnorm(400 * 400), 400, 400)
      list(region = region_id,
           mean_elev = mean(grid),
           ruggedness = sd(as.numeric(abs(diff(grid)))),
           slope_q95 = quantile(abs(as.numeric(diff(t(grid)))), 0.95))
    }
  ),
  bootstrap = list(
    label = "Bootstrap confidence intervals",
    n = 10000L, workers = 25L,
    f = function(i) {
      set.seed(i)
      n <- 5000L
      x <- rnorm(n, mean = 10, sd = 3)
      y <- rnorm(n, mean = 10.4, sd = 3)
      idx <- sample(n, replace = TRUE)
      mean(y[idx]) - mean(x[idx])
    }
  ),
  montecarlo = list(
    label = "Monte Carlo portfolio simulation",
    n = 10000L, workers = 50L,
    f = function(seed) {
      set.seed(seed)
      r <- rnorm(252, 0.0003, 0.02)
      v <- cumprod(1 + r)
      list(final = v[252], sharpe = mean(r) / sd(r) * sqrt(252))
    }
  )
)

# ---- Arg parsing -------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("Usage: benchmark.R <workload|all> [--warm] [--workers N] ",
       "[--launch-type EC2|FARGATE] [--out path]")
}
which_wl <- args[1]
flag <- function(name, default = NULL) {
  hit <- which(args == name)
  if (length(hit) && hit[1] < length(args)) args[hit[1] + 1] else default
}
has_flag <- function(name) any(args == name)
warm        <- has_flag("--warm")
launch_type <- flag("--launch-type", "EC2")
# Default to c7i.xlarge (x86_64) — a type whose capacity provider is commonly
# pre-provisioned. staRburst's session path requires the instance type's ASG to
# already exist (run starburst_setup_ec2(instance_types=...) once); it does not
# create it on demand.
instance_type <- flag("--instance-type", "c7i.xlarge")
out_path    <- flag("--out", NULL)
workers_ovr <- flag("--workers", NULL)

# ---- Local machine + environment metadata -----------------------------------
# get_local_hardware_specs() is internal; access with ::: for the metadata block.
local_specs <- tryCatch(starburst:::get_local_hardware_specs(), error = function(e) NULL)
local_desc <- if (!is.null(local_specs)) {
  sprintf("%s, %s cores (%s)", local_specs$cpu_name %||% "unknown CPU",
          local_specs$cores %||% NA, local_specs$architecture %||% "?")
} else {
  sprintf("%s %s", Sys.info()[["sysname"]], Sys.info()[["machine"]])
}
region <- tryCatch(get_starburst_config()$region, error = function(e) NULL) %||%
  Sys.getenv("AWS_REGION", "us-east-1")
# Timestamp is passed in / stamped from the OS at run time (bench is opt-in and
# never resumed, so a real clock read is fine here).
run_date <- format(Sys.time(), "%Y-%m-%d")
sb_version <- as.character(utils::packageVersion("starburst"))

# ---- Run one workload with phase timing --------------------------------------
run_workload <- function(name) {
  wl <- WORKLOADS[[name]]
  if (is.null(wl)) stop("Unknown workload '", name, "'. Known: ",
                        paste(names(WORKLOADS), collapse = ", "))
  n <- wl$n
  workers <- as.integer(workers_ovr %||% wl$workers)
  x <- seq_len(n)

  message(sprintf("== %s ==", wl$label))
  message(sprintf("   n=%d, workers=%d, launch_type=%s, mode=%s",
                  n, workers, launch_type, if (warm) "warm" else "cold"))

  # --- Local sequential baseline (compute-only) ---
  message("   [local] running sequential baseline...")
  t0 <- Sys.time()
  local_res <- lapply(x, wl$f)
  local_secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

  # --- Cloud: phase 1 = session startup (provision workers or warm reuse) ---
  # We use starburst_session() (detached backend) because it cleanly separates
  # worker startup from submit/collect — exactly the phase split we want — and is
  # the most-exercised execution path.
  fn <- wl$f
  message("   [cloud] creating session (startup phase)...")
  t_startup0 <- Sys.time()
  session <- starburst_session(workers = workers, launch_type = launch_type,
                               instance_type = instance_type)
  startup_secs <- as.numeric(difftime(Sys.time(), t_startup0, units = "secs"))
  on.exit(try(session$cleanup(), silent = TRUE), add = TRUE)

  run_once <- function() {
    t0 <- Sys.time()
    for (item in x) {
      session$submit(quote(fn(item)),
                     globals = list(fn = fn, item = item))
    }
    res <- session$collect(wait = TRUE)
    list(res = res, secs = as.numeric(difftime(Sys.time(), t0, units = "secs")))
  }

  # --- Phase 2/3 = submit + compute + collect ---
  if (warm) {
    message("   [cloud] warm-up run (discarded)...")
    invisible(run_once())
    message("   [cloud] measured warm run...")
    r <- run_once()
    startup_measured <- 0  # warm: startup excluded by design
  } else {
    message("   [cloud] measured cold run...")
    r <- run_once()
    startup_measured <- startup_secs
  }
  compute_collect_secs <- r$secs
  total_secs <- startup_measured + compute_collect_secs

  # Cost estimate from the measured wall-clock (estimate_cost is internal -> :::).
  cost <- tryCatch(
    starburst:::estimate_cost(
      workers, cpu = 4, memory = "8GB",
      estimated_runtime_hours = total_secs / 3600,
      launch_type = launch_type,
      instance_type = if (launch_type == "EC2") instance_type else NULL,
      use_spot = (launch_type == "EC2"))$total_estimated,
    error = function(e) NA_real_)

  list(
    name = name, label = wl$label, n = n, workers = workers,
    launch_type = launch_type, instance_type = instance_type, warm = warm,
    local_secs = local_secs,
    startup_secs = startup_measured,
    compute_collect_secs = compute_collect_secs,
    total_secs = total_secs,
    cost = cost
  )
}

# ---- Markdown emitter --------------------------------------------------------
fmt <- function(s) if (is.na(s)) "n/a" else sprintf("%.1f s", s)
emit_markdown <- function(runs) {
  lines <- c(
    sprintf("# staRburst benchmark — %s", run_date),
    "",
    "> Generated by `bench/benchmark.R` on real AWS workers. Phase-split, with full",
    "> disclosure. Cloud times are **compute + collect**; the **startup** column is",
    "> the one-time cluster provision/image pull (0 for warm runs, where it is",
    "> excluded by design).",
    "",
    "## Run metadata",
    "",
    sprintf("- **staRburst version:** %s", sb_version),
    sprintf("- **Date tested:** %s", run_date),
    sprintf("- **AWS region:** %s", region),
    sprintf("- **Backend:** %s", runs[[1]]$launch_type),
    sprintf("- **Instance type:** %s", runs[[1]]$instance_type %||% "n/a"),
    sprintf("- **Spot:** %s (staRburst default use_spot=TRUE)", "yes"),
    sprintf("- **Cold or warm:** %s", if (runs[[1]]$warm) "warm (startup excluded)" else "cold (startup included)"),
    sprintf("- **Local machine:** %s", local_desc),
    "",
    "## Results",
    "",
    paste0("| Workload | Input (n) | Workers | Local (seq) | Startup | ",
           "Compute+collect | Cloud total | Est. cost |"),
    "|---|---|---|---|---|---|---|---|"
  )
  for (r in runs) {
    lines <- c(lines, sprintf(
      "| %s | %d | %d | %s | %s | %s | %s | %s |",
      r$label, r$n, r$workers, fmt(r$local_secs), fmt(r$startup_secs),
      fmt(r$compute_collect_secs), fmt(r$total_secs),
      if (is.na(r$cost)) "n/a" else sprintf("$%.2f", r$cost)
    ))
  }
  lines <- c(lines, "",
    "**How to read this:** \"Cloud total\" includes startup only for cold runs. For",
    "small workloads the startup line dominates and local is faster overall — cloud",
    "bursting wins when compute+collect greatly exceeds startup (many tasks, minutes",
    "each). See `vignette(\"performance\")`.")
  paste(lines, collapse = "\n")
}

# ---- Main --------------------------------------------------------------------
targets <- if (identical(which_wl, "all")) names(WORKLOADS) else which_wl
runs <- lapply(targets, run_workload)

md <- emit_markdown(runs)
# Resolve output against the ORIGINAL working dir (we setwd()'d into a temp env dir).
out_path <- out_path %||% file.path(
  "bench", "results",
  sprintf("%s-%s.md", if (identical(which_wl, "all")) "all" else which_wl, run_date))
if (!startsWith(out_path, "/")) out_path <- file.path(.orig_wd, out_path)
dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
writeLines(md, out_path)
saveRDS(list(runs = runs, version = sb_version, region = region,
             local = local_desc, date = run_date),
        sub("\\.md$", ".rds", out_path))

cat("\n", md, "\n\n", sep = "")
message("Wrote: ", out_path)
