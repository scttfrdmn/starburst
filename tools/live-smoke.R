#!/usr/bin/env Rscript
# Live smoke test: every public way of running work, on real AWS EC2.
#
# Release gate. 0.3.0-0.3.10 shipped with plan(starburst), starburst_map() and
# starburst_cluster() all failing on real workers while the mocked suite and
# the monthly "quick" CI run stayed green (#63-#65). Run this on the release
# commit before tagging or submitting to CRAN; every check must PASS.
#
# Usage (needs a configured account and Docker for the env image build):
#   timeout 45m Rscript tools/live-smoke.R
#
# Environment:
#   STARBURST_SMOKE_INSTANCE    instance type (default c7g.xlarge)
#   STARBURST_SMOKE_LOCK        renv.lock for the worker image (default: the
#                               repo's bench/worker-renv.lock, which matches the
#                               public base image so the image build is quick)
#   STARBURST_SMOKE_SCALE_DOWN  "true" (default) scales the instance type's
#                               ASG to 0 at the end. ASGs are shared, so set
#                               "false" on an account with other live users.
#
# Cost: ~2 instances for ~10-20 min (about $0.10 on c7g.xlarge on-demand),
# plus the env image build the first time a starburst version is used.

# Repo root = parent of this script's directory
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
repo <- if (!is.na(script)) normalizePath(file.path(dirname(script), "..")) else getwd()

suppressMessages({
  if (dir.exists(file.path(repo, "R")) && file.exists(file.path(repo, "DESCRIPTION"))) {
    devtools::load_all(repo, quiet = TRUE)
  } else {
    library(starburst)
  }
})

# Build the worker image from a minimal lockfile in an isolated directory.
# staRburst uses the renv.lock of the working directory (or the nearest package
# root), which in the repo is the ~100-package dev lockfile: a multi-arch build
# of that takes far longer than the smoke test's budget, especially under QEMU.
lock <- Sys.getenv("STARBURST_SMOKE_LOCK", file.path(repo, "bench", "worker-renv.lock"))
if (file.exists(lock)) {
  smoke_dir <- file.path(tempdir(), "starburst-live-smoke")
  dir.create(smoke_dir, showWarnings = FALSE)
  file.copy(lock, file.path(smoke_dir, "renv.lock"), overwrite = TRUE)
  setwd(smoke_dir)
  cat("worker lockfile:", lock, "\n")
}

instance_type <- Sys.getenv("STARBURST_SMOKE_INSTANCE", "c7g.xlarge")
scale_down <- !identical(tolower(Sys.getenv("STARBURST_SMOKE_SCALE_DOWN", "true")), "false")
workers <- 2

results <- data.frame(check = character(), status = character(),
                      seconds = numeric(), detail = character())
ts <- function() format(Sys.time(), "%H:%M:%S", tz = "UTC")

# Run one check; `expect` returns TRUE or a failure description.
check <- function(name, expr, expect = function(x) TRUE) {
  cat(sprintf("\n[%s] >>> %s\n", ts(), name))
  start <- Sys.time()
  value <- tryCatch(expr, error = function(e) e)
  ok <- if (inherits(value, "error")) conditionMessage(value) else expect(value)
  status <- if (isTRUE(ok)) "PASS" else "FAIL"
  detail <- if (isTRUE(ok)) "" else substr(paste(ok, collapse = " "), 1, 200)
  secs <- round(as.numeric(difftime(Sys.time(), start, units = "secs")))
  cat(sprintf("[%s] <<< %s %s (%ss) %s\n", ts(), status, name, secs, detail))
  results[nrow(results) + 1, ] <<- list(name, status, secs, detail)
  invisible(value)
}
is_equal <- function(expected) function(x) {
  if (identical(x, expected) || isTRUE(all.equal(x, expected))) TRUE
  else paste("got", paste(deparse(x), collapse = ""))
}

cluster <- NULL
session <- NULL
local_host <- Sys.info()[["nodename"]]
cfg <- starburst:::get_starburst_config()
asg_name <- sprintf("starburst-asg-%s", gsub("\\.", "-", instance_type))
autoscaling <- starburst:::get_autoscaling_client(cfg$region)
asg_state <- function() {
  g <- autoscaling$describe_auto_scaling_groups(
    AutoScalingGroupNames = list(asg_name))$AutoScalingGroups[[1]]
  actions <- autoscaling$describe_scheduled_actions(
    AutoScalingGroupName = asg_name)$ScheduledUpdateGroupActions
  list(min = g$MinSize, desired = g$DesiredCapacity,
       release = any(vapply(actions, function(a)
         identical(a$ScheduledActionName, "starburst-release-warm-pool"), logical(1))))
}

tryCatch({
  # 1. future backend: plan(starburst) ---------------------------------------
  check("plan(starburst)", future::plan(starburst, workers = workers,
                                        instance_type = instance_type, use_spot = FALSE,
                                        warm_pool_timeout = 600))
  check("future value runs remotely",
        future::value(future::future(Sys.info()[["nodename"]])),
        function(x) if (is.character(x) && nzchar(x) && x != local_host) TRUE
                    else paste("nodename", x))
  y <- 21
  check("future globals", future::value(future::future(y * 2)), is_equal(42))
  check("future worker error keeps its message",
        tryCatch({ future::value(future::future(stop("smoke-boom"))); "no error raised" },
                 error = function(e) conditionMessage(e)),
        function(msg) if (grepl("smoke-boom", msg) && !grepl("INTERNAL ERROR", msg)) TRUE
                      else msg)
  if (requireNamespace("future.apply", quietly = TRUE)) {
    check("future.apply::future_lapply",
          future.apply::future_lapply(1:4, function(i) i^2), is_equal(list(1, 4, 9, 16)))
    check("future_lapply with a failing element does not hang",
          tryCatch({ future.apply::future_lapply(1:3, function(i) if (i == 1) stop("lapply-boom") else i)
                     "no error raised" }, error = function(e) conditionMessage(e)),
          function(msg) if (grepl("lapply-boom", msg)) TRUE else msg)
  }
  check("worker killed mid-task is reported, not waited on (#67)", {
    f <- future::future({ Sys.sleep(600); "should not finish" })
    for (i in 1:60) if (!is.null(f$task_arn)) break else Sys.sleep(2)
    starburst:::get_ecs_client(cfg$region)$stop_task(
      cluster = cfg$cluster_name, task = f$task_arn, reason = "live-smoke: simulated crash")
    tryCatch({ future::value(f); "no error raised" }, error = function(e) conditionMessage(e))
  }, function(msg) if (grepl("stopped without returning a result", msg)) TRUE else msg)
  check("plan(sequential)", future::plan(future::sequential))
  check("plan(sequential) keeps the pool warm and schedules its release (#59)", asg_state(),
        function(st) if (st$min >= 1 && st$release) TRUE
                     else sprintf("MinSize=%s release scheduled=%s", st$min, st$release))

  # 2. starburst_map() --------------------------------------------------------
  check("starburst_map", starburst_map(1:4, function(x) x^2, workers = workers,
                                       instance_type = instance_type, use_spot = FALSE,
                                       .progress = FALSE),
        is_equal(list(1, 4, 9, 16)))
  check("starburst_map worker error keeps its message",
        tryCatch({ starburst_map(1:2, function(x) stop("map-boom"), workers = workers,
                                 instance_type = instance_type, use_spot = FALSE,
                                 .progress = FALSE); "no error raised" },
                 error = function(e) conditionMessage(e)),
        function(msg) if (grepl("map-boom", msg)) TRUE else msg)
  check("starburst_map releases the pool when done (#59)", asg_state(),
        function(st) if (st$min == 0 && !st$release) TRUE
                     else sprintf("MinSize=%s release scheduled=%s", st$min, st$release))

  # 3. starburst_cluster() ----------------------------------------------------
  cluster <- check("starburst_cluster", starburst_cluster(workers = workers,
                                                          instance_type = instance_type,
                                                          use_spot = FALSE),
                   function(x) inherits(x, "starburst_cluster") || "not a starburst_cluster")
  if (inherits(cluster, "starburst_cluster")) {
    check("cluster$map", cluster$map(1:2, function(x) x + 100, .progress = FALSE),
          is_equal(list(101, 102)))
  }

  # 4. starburst_session() (detached) -----------------------------------------
  session <- check("starburst_session", starburst_session(workers = workers,
                                                          instance_type = instance_type,
                                                          use_spot = FALSE),
                   function(x) is.environment(x) || is.list(x) || "no session object")
  if (is.environment(session) || is.list(session)) {
    check("session submit + collect", {
      session$submit(quote(6 * 7))
      session$collect(wait = TRUE, timeout = 900)
    }, function(r) if (length(r) == 1 && 42 %in% unlist(r)) TRUE
                   else paste("got", paste(deparse(r), collapse = "")))
  }
}, finally = {
  cat(sprintf("\n[%s] cleanup\n", ts()))
  try(future::plan(future::sequential), silent = TRUE)
  if (inherits(cluster, "starburst_cluster")) try(cluster$shutdown(), silent = TRUE)
  if (is.environment(session) || is.list(session)) try(session$cleanup(force = TRUE), silent = TRUE)
  if (scale_down) {
    # Sessions keep the pool warm for warm_pool_timeout (#59); don't pay for it
    try({
      starburst:::stop_warm_pool(list(region = cfg$region, asg_name = asg_name))
      cat("scaled", asg_name, "to 0\n")
    }, silent = TRUE)
  }
})

cat("\n== live smoke summary ==\n")
print(results[, c("check", "status", "seconds")], row.names = FALSE)
failed <- results[results$status != "PASS", ]
if (nrow(failed) > 0) {
  cat("\nFAILED:\n")
  for (i in seq_len(nrow(failed))) cat(sprintf("  - %s: %s\n", failed$check[i], failed$detail[i]))
  quit(status = 1)
}
cat(sprintf("\nALL %d CHECKS PASSED\n", nrow(results)))
