#' Estimate Cloud Performance and Cost
#'
#' Runs a small sample of tasks locally to estimate cloud execution time and cost.
#' Provides informed prediction before spending money on cloud execution.
#'
#' @param .x A vector or list to iterate over
#' @param .f A function to apply to each element
#' @param workers Number of parallel workers to estimate for
#' @param cpu CPU units per worker (1, 2, 4, 8, or 16)
#' @param memory Memory per worker (e.g., "8GB")
#' @param platform CPU architecture: "X86_64" (default) or "ARM64" (Graviton3)
#' @param sample_size Number of items to run locally for estimation (default: 10)
#' @param region AWS region
#' @param ... Additional arguments passed to .f
#'
#' @return Invisible list with estimates, prints summary to console
#' @export
#'
#' @examples
#' \dontrun{
#' # Estimate before running
#' starburst_estimate(1:1000, expensive_function, workers = 50)
#'
#' # Then decide whether to proceed
#' results <- starburst_map(1:1000, expensive_function, workers = 50)
#' }
starburst_estimate <- function(.x, .f, workers = 10, cpu = 2, memory = "8GB",
                               platform = "X86_64", sample_size = 10,
                               region = NULL, ...) {

  n_total <- length(.x)

  # Validate inputs
  validate_workers(workers)
  validate_cpu(cpu)
  validate_memory(memory)
  validate_platform(platform)

  if (sample_size > n_total) {
    sample_size <- n_total
  }

  cat_info(sprintf("[Check] Running local calibration with %d sample tasks...\n", sample_size))

  # Get local hardware specs
  local_specs <- get_local_hardware_specs()
  cat_info(sprintf("[OK] Detected: %s (%d cores)\n", local_specs$cpu_name, local_specs$cores))

  # Run sample locally
  sample_indices <- if (n_total <= sample_size) {
    seq_along(.x)
  } else {
    sample(seq_along(.x), sample_size)
  }

  sample_data <- .x[sample_indices]

  # Time the sample
  start_time <- Sys.time()
  if (length(list(...)) > 0) {
    extra_args <- list(...)
    results_sample <- lapply(sample_data, function(item) {
      do.call(.f, c(list(item), extra_args))
    })
  } else {
    results_sample <- lapply(sample_data, .f)
  }
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  avg_time_per_task <- elapsed / sample_size

  cat_info(sprintf("[OK] Sample complete: %.2f seconds per task average\n\n", avg_time_per_task))

  # Calculate predictions
  predictions <- calculate_predictions(
    n_total = n_total,
    avg_time_per_task = avg_time_per_task,
    local_specs = local_specs,
    workers = workers,
    cpu = cpu,
    memory = parse_memory(memory),
    platform = platform
  )

  # Print comparison
  print_estimate_summary(predictions, local_specs)

  invisible(predictions)
}

#' Get Local Hardware Specifications
#'
#' Detects local CPU model and core count for performance estimation.
#'
#' @return List with cpu_name, cores, and architecture
#' @keywords internal
get_local_hardware_specs <- function() {
  os <- Sys.info()["sysname"]

  if (os == "Darwin") {
    # macOS
    cpu_brand <- system("sysctl -n machdep.cpu.brand_string", intern = TRUE)

    # Try to get performance cores (Apple Silicon)
    perf_cores <- tryCatch({
      as.numeric(system("sysctl -n hw.perflevel0.physicalcpu", intern = TRUE))
    }, error = function(e) {
      # Fallback to total physical cores
      as.numeric(system("sysctl -n hw.physicalcpu", intern = TRUE))
    })

    # Detect if ARM (Apple Silicon)
    arch <- system("uname -m", intern = TRUE)

    list(
      cpu_name = cpu_brand,
      cores = perf_cores,
      architecture = if (grepl("arm", arch, ignore.case = TRUE)) "ARM64" else "X86_64"
    )

  } else if (os == "Linux") {
    # Linux
    cpu_info <- system("cat /proc/cpuinfo | grep 'model name' | head -1", intern = TRUE)
    cpu_name <- sub("model name\\s*:\\s*", "", cpu_info)

    cores <- as.numeric(system("nproc", intern = TRUE))

    arch <- system("uname -m", intern = TRUE)

    list(
      cpu_name = cpu_name,
      cores = cores,
      architecture = if (grepl("aarch64|arm64", arch, ignore.case = TRUE)) "ARM64" else "X86_64"
    )

  } else if (os == "Windows") {
    # Windows
    cpu_name <- Sys.getenv("PROCESSOR_IDENTIFIER")
    cores <- as.numeric(Sys.getenv("NUMBER_OF_PROCESSORS"))

    list(
      cpu_name = cpu_name,
      cores = cores,
      architecture = "X86_64"  # Assume x86 for Windows
    )

  } else {
    # Unknown OS, use parallel package
    list(
      cpu_name = "Unknown",
      cores = parallel::detectCores(),
      architecture = "Unknown"
    )
  }
}

#' Calculate Cloud Performance Predictions
#'
#' @keywords internal
calculate_predictions <- function(n_total, avg_time_per_task, local_specs,
                                  workers, cpu, memory, platform) {

  # Sequential time
  sequential_time <- n_total * avg_time_per_task

  # Local parallel time (ideal)
  local_parallel_time <- sequential_time / local_specs$cores

  # Cloud performance ratio (AWS vs local)
  # These are empirical ratios from benchmarking
  performance_ratio <- get_cloud_performance_ratio(local_specs, platform)

  # Cloud parallel time (accounting for slower per-core performance)
  cloud_parallel_time <- (sequential_time / workers) / performance_ratio

  # Add startup overhead (empirical - will be updated from profiling data)
  # TODO: Update these values from profiling results
  startup_overhead <- 600  # 10 minutes in seconds (placeholder)

  # Add straggler buffer (empirical - tasks don't all finish at exactly same time)
  straggler_factor <- 1.15  # 15% buffer (placeholder)

  cloud_total_time <- (startup_overhead + cloud_parallel_time) * straggler_factor

  # Cost estimation
  hours <- cloud_total_time / 3600
  vCPU_cost_per_hour <- 0.04048
  memory_cost_per_gb_hour <- 0.004445
  cpu_cost <- workers * cpu * vCPU_cost_per_hour * hours
  mem_cost <- workers * memory * memory_cost_per_gb_hour * hours
  cost <- cpu_cost + mem_cost

  # Speedup calculations
  speedup_vs_sequential <- sequential_time / cloud_total_time
  speedup_vs_local_parallel <- local_parallel_time / cloud_total_time

  list(
    n_tasks = n_total,
    avg_time_per_task = avg_time_per_task,
    sequential_time = sequential_time,
    local_parallel_time = local_parallel_time,
    cloud_time = cloud_total_time,
    cloud_startup_overhead = startup_overhead,
    cloud_compute_time = cloud_parallel_time,
    cost = cost,
    speedup_vs_sequential = speedup_vs_sequential,
    speedup_vs_local_parallel = speedup_vs_local_parallel,
    performance_ratio = performance_ratio,
    workers = workers,
    cpu = cpu,
    memory = memory,
    platform = platform
  )
}

#' Get Cloud Performance Ratio
#'
#' Returns estimated per-core performance of cloud vs local hardware.
#' Based on empirical benchmarking data.
#'
#' @keywords internal
get_cloud_performance_ratio <- function(local_specs, platform) {
  cpu_name <- local_specs$cpu_name
  local_arch <- local_specs$architecture

  # M4 Pro baseline (from benchmarking)
  if (grepl("M4 Pro", cpu_name, ignore.case = TRUE)) {
    if (platform == "ARM64") {
      # Graviton3 vs M4 Pro: ~55% per-core performance
      return(0.55)
    } else {
      # Default Fargate x86 vs M4 Pro: ~42% per-core performance
      return(0.42)
    }
  }

  # M3 family (estimate based on M4 data)
  if (grepl("M3", cpu_name, ignore.case = TRUE)) {
    if (platform == "ARM64") {
      return(0.60)  # Graviton3 closer to M3 performance
    } else {
      return(0.45)
    }
  }

  # Intel/AMD x86 local machines
  if (local_arch == "X86_64") {
    # Assume modern desktop/laptop Intel/AMD
    if (platform == "ARM64") {
      return(0.85)  # Graviton3 vs typical Intel/AMD
    } else {
      return(0.75)  # Fargate x86 vs typical Intel/AMD
    }
  }

  # Conservative default
  if (platform == "ARM64") {
    return(0.70)
  } else {
    return(0.60)
  }
}

#' Print Estimate Summary
#'
#' @keywords internal
print_estimate_summary <- function(pred, local_specs) {
  cat_info("============================================================\n")
  cat_info("|  EXECUTION TIME & COST ESTIMATES                         |\n")
  cat_info("============================================================\n\n")

  # Format times
  format_time <- function(seconds) {
    if (seconds < 120) {
      sprintf("%.1f sec", seconds)
    } else if (seconds < 7200) {
      sprintf("%.1f min", seconds / 60)
    } else {
      sprintf("%.1f hours", seconds / 3600)
    }
  }

  cat(sprintf("[Status] Workload: %d tasks, %.2f sec/task average\n\n",
              pred$n_tasks, pred$avg_time_per_task))

  cat(sprintf("Local Options:\n"))
  cat(sprintf("  Sequential (1 core):      %s\n", format_time(pred$sequential_time)))
  cat(sprintf("  Parallel (%d cores):       %s\n",
              local_specs$cores, format_time(pred$local_parallel_time)))
  cat("\n")

  cat(sprintf("Cloud Option:\n"))
  cat(sprintf("  %d workers (%s):         %s\n",
              pred$workers, pred$platform, format_time(pred$cloud_time)))
  cat(sprintf("    Startup overhead:       %s\n", format_time(pred$cloud_startup_overhead)))
  cat(sprintf("    Compute time:           %s\n", format_time(pred$cloud_compute_time)))
  cat(sprintf("    Estimated cost:         $%.2f\n", pred$cost))
  cat("\n")

  cat(sprintf("Speedup:\n"))
  cat(sprintf("  vs Sequential:            %.1fx faster\n", pred$speedup_vs_sequential))

  if (pred$speedup_vs_local_parallel > 1.3) {
    cat(sprintf("  vs Local Parallel:        %.1fx faster [OK]\n", pred$speedup_vs_local_parallel))
    cat("\n")
    cat_success("[TIP] Recommendation: Cloud execution is significantly faster\n")
  } else if (pred$speedup_vs_local_parallel > 1.05) {
    cat(sprintf("  vs Local Parallel:        %.1fx faster [WARNING]\n", pred$speedup_vs_local_parallel))
    cat("\n")
    cat_info(sprintf("[TIP] Recommendation: Cloud is slightly faster but consider cost ($%.2f)\n", pred$cost))
  } else {
    cat(sprintf("  vs Local Parallel:        %.2fx (slower!) [WARNING]\n", pred$speedup_vs_local_parallel))
    cat("\n")
    cat_warn("[TIP] Recommendation: Local parallel execution is better for this workload\n")
    cat_warn(sprintf("   Startup overhead (%.1f min) is too high relative to task duration\n",
                pred$cloud_startup_overhead / 60))
  }

  cat("\n")
}

#' Estimate Cost
#'
#' @keywords internal
estimate_cost <- function(workers, cpu, memory, time_seconds) {
  hours <- time_seconds / 3600

  # Fargate pricing (us-east-1)
  # TODO: Add region-specific pricing
  vCPU_cost_per_hour <- 0.04048
  memory_cost_per_gb_hour <- 0.004445

  # Graviton pricing is 20% cheaper (if platform == "ARM64")
  # For now, using x86 pricing (conservative)

  cpu_cost <- workers * cpu * vCPU_cost_per_hour * hours
  mem_cost <- workers * memory * memory_cost_per_gb_hour * hours

  cpu_cost + mem_cost
}

#' Parse Memory String
# Note: parse_memory() is defined in R/plan-starburst.R
