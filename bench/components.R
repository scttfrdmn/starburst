#!/usr/bin/env Rscript
# bench/components.R — per-phase component timings for staRburst.
#
# benchmark.R measures end-to-end wall-clock (startup / compute+collect / total).
# This script isolates the pieces inside those phases, each through the SAME code
# path staRburst uses at runtime, so a regression can be pinned to one component:
#
#   serialize  qs2::qs_save / qs2::qs_read of task-sized payloads (local, free)
#   s3         put_object / get_object round-trip of those payloads to the
#              staRburst bucket, then delete (real AWS, fractions of a cent)
#   image      build_environment_image() under a fresh tag: base resolution +
#              multi-arch docker buildx build + ECR push, then delete the tag
#              (real AWS + local Docker, ~minutes)
#   ci         base-image build times from the build-base-images.yml workflow
#              history (GitHub CLI, free) — CI already builds them monthly, so
#              this reads the record instead of rebuilding
#
# Usage:
#   Rscript bench/components.R serialize                       # no AWS, no opt-in
#   Rscript bench/components.R ci                              # needs `gh`
#   STARBURST_BENCH=TRUE AWS_PROFILE=aws Rscript bench/components.R s3
#   STARBURST_BENCH=TRUE AWS_PROFILE=aws Rscript bench/components.R image
#   STARBURST_BENCH=TRUE AWS_PROFILE=aws Rscript bench/components.R all
#
# Flags:
#   --reps N     Repetitions per measurement; the median is reported (default 5;
#                image is always 1 — it is minutes long).
#   --out PATH   Markdown output (default: bench/results/components-<date>.md).
#
# Writes a markdown table plus a machine-readable .rds (a data.frame, one row per
# measurement) that bench/trends.R aggregates across dates.

suppressWarnings(suppressMessages({
  library(starburst)
  library(jsonlite)
}))

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("Usage: components.R <serialize|s3|image|ci|all> [--reps N] [--out path]")
}
which_c <- args[1]
flag <- function(name, default = NULL) {
  hit <- which(args == name)
  if (length(hit) && hit[1] < length(args)) args[hit[1] + 1] else default
}
reps     <- as.integer(flag("--reps", "5"))
out_path <- flag("--out", NULL)
targets  <- if (identical(which_c, "all")) c("serialize", "s3", "image", "ci") else which_c
known    <- c("serialize", "s3", "image", "ci")
if (!all(targets %in% known)) {
  stop("Unknown component '", which_c, "'. Known: ", paste(c(known, "all"), collapse = ", "))
}

# s3 and image touch real, billable AWS resources: same opt-in as benchmark.R.
if (any(targets %in% c("s3", "image")) &&
    !identical(Sys.getenv("STARBURST_BENCH"), "TRUE")) {
  stop("components s3/image use real AWS resources.\n",
       "Set STARBURST_BENCH=TRUE to run them (serialize and ci need no opt-in).")
}

.orig_wd <- normalizePath(getwd())
run_date <- format(Sys.time(), "%Y-%m-%d")
sb_version <- as.character(utils::packageVersion("starburst"))
host <- sprintf("%s %s, R %s", Sys.info()[["sysname"]], Sys.info()[["machine"]],
                getRversion())

timed <- function(expr_fn) {
  t0 <- Sys.time()
  expr_fn()
  as.numeric(difftime(Sys.time(), t0, units = "secs"))
}
row <- function(component, metric, size_bytes, seconds, detail = "") {
  data.frame(date = run_date, component = component, metric = metric,
             size_bytes = as.numeric(size_bytes), seconds = seconds,
             detail = detail, stringsAsFactors = FALSE)
}

# Task-shaped payloads: the list structure staRburst ships (expr + globals), with
# a numeric global of the given size. rnorm() data is near-incompressible, so this
# is the pessimistic case for qs2's compression.
PAYLOAD_MB <- c(0.001, 1, 10, 100)
make_payload <- function(mb) {
  n <- max(1L, as.integer(mb * 1024^2 / 8))
  list(expr = quote(f(x)), globals = list(f = function(x) sum(x), x = rnorm(n)),
       packages = character(0))
}
size_label <- function(mb) if (mb < 1) sprintf("%.0f KB", mb * 1024) else sprintf("%.0f MB", mb)

# ---- serialize ---------------------------------------------------------------
bench_serialize <- function() {
  message("== serialize (qs2, local) ==")
  out <- list()
  for (mb in PAYLOAD_MB) {
    obj <- make_payload(mb)
    f <- tempfile(fileext = ".qs")
    save_s <- vapply(seq_len(reps), function(i) timed(function() qs2::qs_save(obj, f)), 0)
    bytes <- file.size(f)
    read_s <- vapply(seq_len(reps), function(i) timed(function() qs2::qs_read(f)), 0)
    unlink(f)
    message(sprintf("   %-7s save %.3fs  read %.3fs  (%.1f MB on disk)",
                    size_label(mb), median(save_s), median(read_s), bytes / 1024^2))
    out[[length(out) + 1]] <- row("serialize", paste("qs_save", size_label(mb)), bytes, median(save_s))
    out[[length(out) + 1]] <- row("serialize", paste("qs_read", size_label(mb)), bytes, median(read_s))
  }
  do.call(rbind, out)
}

# ---- s3 ----------------------------------------------------------------------
bench_s3 <- function() {
  if (!starburst_is_configured()) stop("staRburst is not configured; run starburst_setup() first.")
  message("== s3 (put/get round-trip) ==")
  config <- starburst:::get_starburst_config()
  bucket <- starburst:::get_starburst_bucket()
  s3 <- starburst:::get_s3_client(config$region)
  prefix <- sprintf("bench/components/%s/", uuid::UUIDgenerate())
  keys <- character(0)
  on.exit({
    for (k in keys) try(s3$delete_object(Bucket = bucket, Key = k), silent = TRUE)
  }, add = TRUE)

  out <- list()
  for (mb in PAYLOAD_MB) {
    f <- tempfile(fileext = ".qs")
    qs2::qs_save(make_payload(mb), f)
    bytes <- file.size(f)
    key <- paste0(prefix, gsub(" ", "", size_label(mb)), ".qs")
    keys <- c(keys, key)
    # Same calls as serialize_and_upload() / the result download path.
    put_s <- vapply(seq_len(reps), function(i)
      timed(function() s3$put_object(Bucket = bucket, Key = key, Body = f)), 0)
    get_s <- vapply(seq_len(reps), function(i) timed(function() {
      resp <- s3$get_object(Bucket = bucket, Key = key)
      writeBin(resp$Body, tempfile(fileext = ".qs"))
    }), 0)
    unlink(f)
    message(sprintf("   %-7s put %.3fs  get %.3fs  (%.1f MB)",
                    size_label(mb), median(put_s), median(get_s), bytes / 1024^2))
    detail <- sprintf("region %s", config$region)
    out[[length(out) + 1]] <- row("s3", paste("put", size_label(mb)), bytes, median(put_s), detail)
    out[[length(out) + 1]] <- row("s3", paste("get", size_label(mb)), bytes, median(get_s), detail)
  }
  do.call(rbind, out)
}

# ---- image -------------------------------------------------------------------
bench_image <- function() {
  if (!starburst_is_configured()) stop("staRburst is not configured; run starburst_setup() first.")
  message("== image (build_environment_image, fresh tag) ==")
  config <- starburst:::get_starburst_config()
  region <- config$region
  # Build from the committed minimal worker lock (see benchmark.R for why it must
  # match the base image exactly), in an isolated dir so the dev renv.lock is
  # never picked up.
  lock <- file.path(.orig_wd, "bench", "worker-renv.lock")
  if (!file.exists(lock)) stop("missing bench/worker-renv.lock")
  wd <- file.path(tempdir(), "starburst-bench-image")
  dir.create(wd, showWarnings = FALSE, recursive = TRUE)
  file.copy(lock, file.path(wd, "renv.lock"), overwrite = TRUE)
  old <- setwd(wd)
  on.exit(setwd(old), add = TRUE)

  tag <- sprintf("bench-%s", format(Sys.time(), "%Y%m%d%H%M%S"))
  ecr <- starburst:::get_ecr_client(region)
  on.exit(try(ecr$batch_delete_image(repositoryName = "starburst-worker",
                                     imageIds = list(list(imageTag = tag))),
              silent = TRUE), add = TRUE)

  secs <- timed(function() starburst:::build_environment_image(tag, region, use_public = TRUE))
  message(sprintf("   build+push %.1fs (tag %s, deleted afterwards)", secs, tag))
  row("image", "env image build+push (amd64+arm64, --no-cache)", NA, secs,
      sprintf("build host %s; region %s", host, region))
}

# ---- ci ----------------------------------------------------------------------
bench_ci <- function(limit = 12L) {
  message("== ci (base-image build history) ==")
  if (!nzchar(Sys.which("gh"))) stop("`gh` (GitHub CLI) is required for the ci component.")
  gh_json <- function(...) jsonlite::fromJSON(paste(system2("gh", c(...), stdout = TRUE), collapse = "\n"))
  runs <- gh_json("run", "list", "--repo", "scttfrdmn/starburst",
                  "--workflow", "build-base-images.yml", "--status", "success",
                  "--limit", limit, "--json", "databaseId,createdAt")
  if (!length(runs) || !nrow(runs)) stop("no successful build-base-images runs found")
  out <- list()
  for (i in seq_len(nrow(runs))) {
    jobs <- gh_json("run", "view", runs$databaseId[i], "--repo", "scttfrdmn/starburst",
                    "--json", "jobs")$jobs
    jobs <- jobs[grepl("^build", jobs$name), , drop = FALSE]
    for (j in seq_len(nrow(jobs))) {
      secs <- as.numeric(difftime(as.POSIXct(jobs$completedAt[j], format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                                  as.POSIXct(jobs$startedAt[j], format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                                  units = "secs"))
      r <- row("ci", paste("base image", sub("^build ", "", jobs$name[j])), NA, secs,
               sprintf("run %s", runs$databaseId[i]))
      # Date the row by when CI ran, not when this script ran, so trends line up.
      r$date <- substr(runs$createdAt[i], 1, 10)
      out[[length(out) + 1]] <- r
    }
  }
  res <- do.call(rbind, out)
  message(sprintf("   %d job timings from %d runs", nrow(res), nrow(runs)))
  res
}

# ---- Main --------------------------------------------------------------------
fns <- list(serialize = bench_serialize, s3 = bench_s3, image = bench_image, ci = bench_ci)
results <- do.call(rbind, lapply(targets, function(t) fns[[t]]()))

fmt_size <- function(b) ifelse(is.na(b), "",
                               ifelse(b < 1024^2, sprintf("%.1f KB", b / 1024), sprintf("%.1f MB", b / 1024^2)))
md <- c(
  sprintf("# staRburst component timings — %s", run_date),
  "",
  "> Generated by `bench/components.R`. Each row is the median of the stated number of",
  "> repetitions, measured through the same internal code path staRburst uses.",
  "",
  "## Run metadata",
  "",
  sprintf("- **staRburst version:** %s", sb_version),
  sprintf("- **Date tested:** %s", run_date),
  sprintf("- **Host:** %s", host),
  sprintf("- **Repetitions:** %d (image: 1)", reps),
  "",
  "## Results",
  "",
  "| Component | Metric | Payload | Seconds | Detail |",
  "|---|---|---|---|---|",
  sprintf("| %s | %s | %s | %.3f | %s |", results$component, results$metric,
          fmt_size(results$size_bytes), results$seconds, results$detail)
)
out_path <- out_path %||% file.path("bench", "results",
                                    sprintf("components-%s.md", run_date))
if (!startsWith(out_path, "/")) out_path <- file.path(.orig_wd, out_path)
dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
writeLines(md, out_path)
saveRDS(results, sub("\\.md$", ".rds", out_path))
cat("\n", paste(md, collapse = "\n"), "\n\n", sep = "")
message("Wrote: ", out_path)
