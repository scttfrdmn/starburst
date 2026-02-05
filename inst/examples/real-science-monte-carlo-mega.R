#!/usr/bin/env Rscript

# ============================================================================
# REAL SCIENCE: Massive Monte Carlo Simulation
# ============================================================================
#
# Ultra-large scale Monte Carlo for financial risk / physics simulation:
# - 100 scenarios × 1,000,000 iterations each = 100 million total iterations
# - Each iteration: Complex path-dependent calculation
# - Per scenario: ~3-5 minutes of pure computation
# - Total sequential time: ~5-8 hours on M4 Pro
# - With 100 workers: ~5-10 minutes
# - Expected speedup: 60-100x
#
# This is computationally intensive, algorithmically simple, and bulletproof.
# ============================================================================

suppressPackageStartupMessages({
  library(starburst)
})

cat("=== REAL SCIENCE: Massive Monte Carlo Simulation ===\n\n")

# Configuration
n_scenarios <- 100
iters_per_scenario <- 1000000  # 1 million iterations per scenario
scenarios_per_worker <- 1      # Each scenario is big enough for one worker

cat("Monte Carlo Configuration:\n")
cat(sprintf("  Scenarios: %d\n", n_scenarios))
cat(sprintf("  Iterations per scenario: %s\n", format(iters_per_scenario, big.mark = ",")))
cat(sprintf("  Total iterations: %s\n\n",
            format(as.numeric(n_scenarios) * iters_per_scenario, big.mark = ",")))

# Complex Monte Carlo simulation function
# Simulates path-dependent stochastic process (e.g., options pricing, epidemic model)
run_monte_carlo_scenario <- function(scenario_ids) {
  # Define iterations here so it's available in worker scope
  iters_per_scenario <- 1000000  # 1 million iterations

  results <- lapply(scenario_ids, function(scenario_id) {
    set.seed(scenario_id)

    # Scenario parameters (varies by ID for ensemble)
    mu <- 0.05 + (scenario_id * 0.001)      # Drift
    sigma <- 0.2 + (scenario_id * 0.0005)   # Volatility
    S0 <- 100                               # Initial value
    T <- 1.0                                # Time horizon (years)
    dt <- 1.0 / 252                         # Daily timesteps
    n_steps <- floor(T / dt)                # ~252 steps
    barrier <- 90                           # Knock-out barrier

    # Storage for statistics
    final_values <- numeric(iters_per_scenario)
    max_values <- numeric(iters_per_scenario)
    barrier_hits <- 0

    # Main Monte Carlo loop
    for (iter in 1:iters_per_scenario) {
      # Simulate path (Geometric Brownian Motion)
      S <- S0
      S_max <- S0
      hit_barrier <- FALSE

      for (step in 1:n_steps) {
        # Random walk step
        z <- rnorm(1)
        S <- S * exp((mu - 0.5 * sigma^2) * dt + sigma * sqrt(dt) * z)

        # Track maximum
        if (S > S_max) S_max <- S

        # Check barrier
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
    # Payoff calculations (path-dependent option pricing)
    call_payoff <- pmax(final_values - 100, 0)
    barrier_call_payoff <- ifelse(
      (1:iters_per_scenario) <= barrier_hits,
      0,  # Knocked out
      call_payoff[(barrier_hits + 1):iters_per_scenario]
    )

    # Risk metrics
    var_95 <- quantile(final_values, 0.05)  # Value at Risk (5th percentile)
    cvar_95 <- mean(final_values[final_values <= var_95])  # Conditional VaR

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
cat("Testing single scenario (1M iterations)...\n")
cat("This will take a few minutes...\n")
single_start <- Sys.time()
test_result <- run_monte_carlo_scenario(1:1)
single_time <- as.numeric(difftime(Sys.time(), single_start, units = "secs"))
cat(sprintf("Single scenario: %.1f seconds (%.1f minutes)\n\n",
            single_time, single_time / 60))

# Estimate total time
total_sequential <- single_time * n_scenarios
cat(sprintf("Estimated sequential time: %.1f hours\n", total_sequential / 3600))
cat("(This would saturate M4 Pro cores for hours!)\n\n")

# Create batches
scenario_batches <- split(
  1:n_scenarios,
  ceiling(seq_along(1:n_scenarios) / scenarios_per_worker)
)

n_workers <- length(scenario_batches)

cat(sprintf("CLOUD EXECUTION: %d workers processing %d scenarios\n",
            n_workers, length(scenario_batches)))
cat(sprintf("Each worker runs %d scenario(s) (~%.1f minutes)\n\n",
            scenarios_per_worker, (scenarios_per_worker * single_time) / 60))

# LOCAL benchmark
cat("LOCAL (M4 Pro): Running 1 scenario for timing...\n")
local_start <- Sys.time()
local_results <- run_monte_carlo_scenario(1:1)
local_time <- as.numeric(difftime(Sys.time(), local_start, units = "secs"))
local_estimated <- local_time * n_scenarios

cat(sprintf("✓ 1 scenario in %.1f seconds (%.1f minutes)\n",
            local_time, local_time / 60))
cat(sprintf("  Estimated for %d: %.1f hours\n\n", n_scenarios, local_estimated / 3600))

# CLOUD execution
cat("Starting cloud Monte Carlo...\n")
cat("(Your laptop can relax)\n\n")

cloud_start <- Sys.time()
cloud_results <- starburst_map(
  scenario_batches,
  run_monte_carlo_scenario,
  workers = n_workers
)
cloud_time <- as.numeric(difftime(Sys.time(), cloud_start, units = "secs"))

cat(sprintf("\n✓ All scenarios completed in %.1f minutes (%.1f hours)\n\n",
            cloud_time / 60, cloud_time / 3600))

# Performance metrics
speedup <- local_estimated / cloud_time
time_saved <- local_estimated - cloud_time

cat("╔══════════════════════════════════════════════════╗\n")
cat("║     MONTE CARLO SIMULATION RESULTS               ║\n")
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
cat(sprintf("│ Time saved: %.1f hours                    │\n", time_saved / 3600))
cat("└────────────────────────────────────────────────┘\n\n")

# Scientific/Financial results
all_results <- unlist(cloud_results, recursive = FALSE)
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

cat("✓ Monte Carlo simulation complete!\n\n")

if (speedup >= 50) {
  cat(sprintf("🎉 MASSIVE SCALE: %.0fx speedup on %s iterations!\n",
              speedup, format(as.numeric(n_scenarios) * iters_per_scenario, big.mark = ",")))
  cat(sprintf("%.1f hours of computation done in %.1f minutes.\n",
              local_estimated / 3600, cloud_time / 60))
  cat("This is the power of cloud parallel computing. 🚀\n")
} else {
  cat(sprintf("Current speedup: %.0fx\n", speedup))
}
