#!/usr/bin/env Rscript

# ============================================================================
# REAL SCIENCE: ULTRA-MASSIVE Monte Carlo - Targeting 100x Speedup
# ============================================================================
#
# Ultra-large scale targeting maximum speedup:
# - 50 scenarios × 10,000,000 iterations each = 500 million total iterations
# - Per scenario: ~15-20 minutes of computation
# - Total sequential time: ~12-16 hours on M4 Pro
# - With 50 workers: ~20-30 minutes
# - Expected speedup: 80-100x
#
# This is publication-grade Monte Carlo at truly massive scale.
# ============================================================================

suppressPackageStartupMessages({
  library(starburst)
})

cat("=== REAL SCIENCE: ULTRA-MASSIVE Monte Carlo ===\n\n")

# Configuration for maximum speedup
n_scenarios <- 50
iters_per_scenario <- 10000000  # 10 MILLION iterations per scenario

cat("Ultra Monte Carlo Configuration:\n")
cat(sprintf("  Scenarios: %d\n", n_scenarios))
cat(sprintf("  Iterations per scenario: %s\n", format(iters_per_scenario, big.mark = ",")))
cat(sprintf("  Total iterations: %s\n\n",
            format(as.numeric(n_scenarios) * iters_per_scenario, big.mark = ",")))
cat("This is MASSIVE SCALE computation!\n\n")

# Monte Carlo simulation function (same as before but 10x more iterations)
run_ultra_monte_carlo <- function(scenario_ids) {
  # CRITICAL: Define iterations inside function for worker scope
  iters_per_scenario <- 10000000  # 10 million

  results <- lapply(scenario_ids, function(scenario_id) {
    set.seed(scenario_id)

    # Scenario parameters
    mu <- 0.05 + (scenario_id * 0.001)
    sigma <- 0.2 + (scenario_id * 0.0005)
    S0 <- 100
    T <- 1.0
    dt <- 1.0 / 252
    n_steps <- floor(T / dt)
    barrier <- 90

    # Storage
    final_values <- numeric(iters_per_scenario)
    max_values <- numeric(iters_per_scenario)
    barrier_hits <- 0

    # Main Monte Carlo loop - this is the CPU burner
    for (iter in 1:iters_per_scenario) {
      S <- S0
      S_max <- S0
      hit_barrier <- FALSE

      for (step in 1:n_steps) {
        z <- rnorm(1)
        S <- S * exp((mu - 0.5 * sigma^2) * dt + sigma * sqrt(dt) * z)

        if (S > S_max) S_max <- S

        if (S < barrier) {
          hit_barrier <- TRUE
          break
        }
      }

      final_values[iter] <- S
      max_values[iter] <- S_max
      if (hit_barrier) barrier_hits <- barrier_hits + 1
    }

    # Compute statistics
    call_payoff <- pmax(final_values - 100, 0)
    var_95 <- quantile(final_values, 0.05)
    cvar_95 <- mean(final_values[final_values <= var_95])

    list(
      scenario_id = scenario_id,
      mu = mu,
      sigma = sigma,
      n_iterations = iters_per_scenario,
      mean_final = mean(final_values),
      sd_final = sd(final_values),
      mean_payoff = mean(call_payoff),
      barrier_prob = barrier_hits / iters_per_scenario,
      var_95 = var_95,
      cvar_95 = cvar_95,
      max_observed = max(max_values)
    )
  })

  results
}

# Test single scenario timing
cat("Testing single scenario (10M iterations)...\n")
cat("This will take 10-20 minutes - REAL computation!\n")
single_start <- Sys.time()
test_result <- run_ultra_monte_carlo(1:1)
single_time <- as.numeric(difftime(Sys.time(), single_start, units = "secs"))
cat(sprintf("\nSingle scenario: %.1f seconds (%.1f minutes)\n\n",
            single_time, single_time / 60))

# Estimate total time
total_sequential <- single_time * n_scenarios
cat(sprintf("Estimated sequential time: %.1f hours\n", total_sequential / 3600))
cat("(This would run your M4 Pro HOT for half a day!)\n\n")

# LOCAL benchmark
cat("LOCAL (M4 Pro): Running 1 scenario for confirmation...\n")
local_start <- Sys.time()
local_results <- run_ultra_monte_carlo(1:1)
local_time <- as.numeric(difftime(Sys.time(), local_start, units = "secs"))
local_estimated <- local_time * n_scenarios

cat(sprintf("✓ 1 scenario in %.1f seconds (%.1f minutes)\n",
            local_time, local_time / 60))
cat(sprintf("  Estimated for %d: %.1f hours\n\n", n_scenarios, local_estimated / 3600))

# CLOUD execution - one scenario per worker
n_workers <- n_scenarios

cat(sprintf("CLOUD EXECUTION: %d workers (one scenario each)\n", n_workers))
cat(sprintf("Expected per-task time: ~%.1f minutes\n\n", single_time / 60))

cat("Starting ULTRA cloud Monte Carlo...\n")
cat("☕ Time to get coffee while your laptop relaxes...\n\n")

cloud_start <- Sys.time()
cloud_results <- starburst_map(
  1:n_scenarios,
  run_ultra_monte_carlo,
  workers = n_workers,
  cpu = 2048,
  memory = 4096
)
cloud_time <- as.numeric(difftime(Sys.time(), cloud_start, units = "secs"))

cat(sprintf("\n✓ ULTRA simulation completed in %.1f minutes (%.1f hours)\n\n",
            cloud_time / 60, cloud_time / 3600))

# Performance metrics
speedup <- local_estimated / cloud_time
time_saved <- local_estimated - cloud_time
efficiency <- (speedup / n_workers) * 100

cat("╔══════════════════════════════════════════════════╗\n")
cat("║     ULTRA MONTE CARLO RESULTS                    ║\n")
cat("╚══════════════════════════════════════════════════╝\n\n")

cat(sprintf("Scenarios simulated: %d\n", n_scenarios))
cat(sprintf("Total iterations: %s\n\n",
            format(as.numeric(n_scenarios) * iters_per_scenario, big.mark = ",")))

cat("┌────────────────────────────────────────────────┐\n")
cat("│ PERFORMANCE                                    │\n")
cat("├────────────────────────────────────────────────┤\n")
cat(sprintf("│ Local (estimated): %.1f hours             │\n", local_estimated / 3600))
cat(sprintf("│ Cloud (%d workers): %.1f hours            │\n", n_workers, cloud_time / 3600))
cat(sprintf("│ Speedup: %.0fx                             │\n", speedup))
cat(sprintf("│ Efficiency: %.0f%%                         │\n", efficiency))
cat(sprintf("│ Time saved: %.1f hours                    │\n", time_saved / 3600))
cat("└────────────────────────────────────────────────┘\n\n")

# Scientific results
all_results <- cloud_results
mean_finals <- sapply(all_results, function(r) r$mean_final)
var_95s <- sapply(all_results, function(r) r$var_95)
barrier_probs <- sapply(all_results, function(r) r$barrier_prob)

cat("┌────────────────────────────────────────────────┐\n")
cat("│ SIMULATION RESULTS                             │\n")
cat("├────────────────────────────────────────────────┤\n")
cat(sprintf("│ Mean final value: $%.2f (±%.2f)           │\n",
            mean(mean_finals), sd(mean_finals)))
cat(sprintf("│ VaR (95%%): $%.2f                          │\n",
            mean(var_95s)))
cat(sprintf("│ Barrier hit probability: %.1f%%            │\n",
            mean(barrier_probs) * 100))
cat(sprintf("│ Mean option value: $%.2f                  │\n",
            mean(sapply(all_results, function(r) r$mean_payoff))))
cat("└────────────────────────────────────────────────┘\n\n")

cat("✓ ULTRA Monte Carlo complete!\n\n")

if (speedup >= 80) {
  cat(sprintf("🏆 AMAZING: %.0fx speedup on %.0fM iterations!\n",
              speedup, as.numeric(n_scenarios) * iters_per_scenario / 1e6))
  cat(sprintf("Saved %.1f hours of computation time.\n", time_saved / 3600))
  cat("This is the power of cloud parallel computing at scale! 🚀\n")
} else if (speedup >= 50) {
  cat(sprintf("🎉 EXCELLENT: %.0fx speedup demonstrates real cloud advantage!\n", speedup))
  cat(sprintf("%.1f hours → %.1f minutes\n",
              local_estimated / 3600, cloud_time / 60))
} else {
  cat(sprintf("✓ Good speedup: %.0fx\n", speedup))
  cat("Note: Increase iterations further for even larger speedup.\n")
}
