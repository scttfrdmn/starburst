#!/usr/bin/env Rscript
#
# Parallel Portfolio Risk Modeling Example
#
# This script demonstrates parallel risk analysis for a financial portfolio.
# It performs stress testing, VaR calculation, and sensitivity analysis.
#
# Usage:
#   Rscript risk-modeling.R
#   # or from R:
#   source(system.file("examples/risk-modeling.R", package = "starburst"))

library(starburst)

cat("=== Parallel Portfolio Risk Modeling ===\n\n")

# Generate synthetic portfolio
set.seed(3141)

n_assets <- 50

cat("Generating portfolio...\n")

portfolio <- data.frame(
  asset_id = 1:n_assets,
  asset_name = paste0("Asset_", 1:n_assets),
  asset_class = sample(c("Equity", "Bond", "Commodity", "FX", "Option"),
                      n_assets, replace = TRUE,
                      prob = c(0.4, 0.3, 0.1, 0.1, 0.1)),
  position_value = rlnorm(n_assets, log(1000000), 1),
  beta = rnorm(n_assets, 1.0, 0.3),
  duration = ifelse(
    sample(c("Equity", "Bond", "Commodity", "FX", "Option"),
           n_assets, replace = TRUE,
           prob = c(0.4, 0.3, 0.1, 0.1, 0.1)) == "Bond",
    runif(n_assets, 1, 10), 0
  ),
  delta = runif(n_assets, 0.3, 0.7),
  vega = runif(n_assets, 10000, 50000),
  stringsAsFactors = FALSE
)

total_portfolio_value <- sum(portfolio$position_value)

cat(sprintf("✓ Portfolio created:\n"))
cat(sprintf("  Total value: $%.0f\n", total_portfolio_value))
cat(sprintf("  Number of positions: %d\n\n", n_assets))

# Scenario generation functions
generate_stress_scenarios <- function(n_scenarios = 100) {
  scenarios <- list()

  for (i in 1:n_scenarios) {
    scenario <- list(
      scenario_id = i,
      scenario_type = "stress_test",
      equity_shock = rnorm(1, -0.15, 0.05),
      rate_shock = rnorm(1, 0.02, 0.01),
      vol_shock = rnorm(1, 0.5, 0.2),
      fx_shock = rnorm(1, -0.05, 0.03),
      commodity_shock = rnorm(1, -0.10, 0.05)
    )
    scenarios[[i]] <- scenario
  }

  scenarios
}

generate_mc_scenarios <- function(n_scenarios = 1000) {
  scenarios <- list()

  for (i in 1:n_scenarios) {
    scenario <- list(
      scenario_id = 1000 + i,
      scenario_type = "monte_carlo",
      equity_shock = rnorm(1, 0, 0.10),
      rate_shock = rnorm(1, 0, 0.005),
      vol_shock = rnorm(1, 0, 0.2),
      fx_shock = rnorm(1, 0, 0.05),
      commodity_shock = rnorm(1, 0, 0.12)
    )
    scenarios[[i]] <- scenario
  }

  scenarios
}

# Portfolio valuation function
value_portfolio_scenario <- function(scenario, portfolio_data) {
  Sys.sleep(0.001)

  position_pnl <- numeric(nrow(portfolio_data))

  for (i in 1:nrow(portfolio_data)) {
    asset <- portfolio_data[i, ]
    pnl <- 0

    if (asset$asset_class == "Equity") {
      pnl <- asset$position_value * scenario$equity_shock * asset$beta
    } else if (asset$asset_class == "Bond") {
      pnl <- -asset$position_value * scenario$rate_shock * asset$duration
    } else if (asset$asset_class == "Commodity") {
      pnl <- asset$position_value * scenario$commodity_shock
    } else if (asset$asset_class == "FX") {
      pnl <- asset$position_value * scenario$fx_shock
    } else if (asset$asset_class == "Option") {
      pnl <- asset$position_value * scenario$equity_shock * asset$delta +
             asset$vega * scenario$vol_shock
    }

    position_pnl[i] <- pnl
  }

  total_pnl <- sum(position_pnl)
  portfolio_return <- total_pnl / sum(portfolio_data$position_value)

  list(
    scenario_id = scenario$scenario_id,
    scenario_type = scenario$scenario_type,
    total_pnl = total_pnl,
    portfolio_return = portfolio_return,
    position_pnl = position_pnl
  )
}

# Local benchmark
test_stress <- generate_stress_scenarios(n_scenarios = 20)
test_mc <- generate_mc_scenarios(n_scenarios = 100)
test_scenarios <- c(test_stress, test_mc)

cat(sprintf("Running local benchmark (%d scenarios)...\n", length(test_scenarios)))
local_start <- Sys.time()

local_results <- lapply(test_scenarios, value_portfolio_scenario,
                       portfolio_data = portfolio)

local_time <- as.numeric(difftime(Sys.time(), local_start, units = "secs"))

cat(sprintf("✓ Completed in %.2f seconds\n", local_time))
cat(sprintf("  Average time per scenario: %.3f seconds\n",
            local_time / length(test_scenarios)))
cat(sprintf("  Estimated time for 10,000 scenarios: %.1f minutes\n\n",
            local_time * 10000 / length(test_scenarios) / 60))

# Generate full scenario set
cat("Generating scenario sets...\n")
stress_scenarios <- generate_stress_scenarios(n_scenarios = 100)
mc_scenarios <- generate_mc_scenarios(n_scenarios = 10000)

all_scenarios <- c(stress_scenarios, mc_scenarios)

cat(sprintf("  Stress test scenarios: %d\n", length(stress_scenarios)))
cat(sprintf("  Monte Carlo scenarios: %s\n",
            format(length(mc_scenarios), big.mark = ",")))
cat(sprintf("  Total scenarios: %s\n\n",
            format(length(all_scenarios), big.mark = ",")))

# Cloud execution
n_workers <- 50

cat(sprintf("Running risk analysis (%s scenarios) on %d workers...\n",
            format(length(all_scenarios), big.mark = ","), n_workers))

cloud_start <- Sys.time()

results <- starburst_map(
  all_scenarios,
  value_portfolio_scenario,
  portfolio_data = portfolio,
  workers = n_workers,
  cpu = 2,
  memory = "4GB"
)

cloud_time <- as.numeric(difftime(Sys.time(), cloud_start, units = "mins"))

cat(sprintf("\n✓ Completed in %.2f minutes\n\n", cloud_time))

# Extract P&L values
pnl_values <- sapply(results, function(x) x$total_pnl)
stress_pnl <- pnl_values[1:100]
mc_pnl <- pnl_values[101:length(pnl_values)]

# Print results
cat("=== Comprehensive Risk Analysis Results ===\n\n")

# Stress test results
cat("=== Stress Test Results ===\n")
cat(sprintf("Worst case loss: $%.0f (%.2f%%)\n",
            min(stress_pnl),
            min(stress_pnl) / total_portfolio_value * 100))
cat(sprintf("Average stress loss: $%.0f (%.2f%%)\n",
            mean(stress_pnl),
            mean(stress_pnl) / total_portfolio_value * 100))
cat(sprintf("Best case: $%.0f (%.2f%%)\n\n",
            max(stress_pnl),
            max(stress_pnl) / total_portfolio_value * 100))

# Value at Risk
cat("=== Value at Risk (Monte Carlo) ===\n")
var_95 <- quantile(mc_pnl, 0.05)
var_99 <- quantile(mc_pnl, 0.01)
var_999 <- quantile(mc_pnl, 0.001)

cat(sprintf("VaR (95%%): $%.0f (%.2f%%)\n",
            -var_95, -var_95 / total_portfolio_value * 100))
cat(sprintf("VaR (99%%): $%.0f (%.2f%%)\n",
            -var_99, -var_99 / total_portfolio_value * 100))
cat(sprintf("VaR (99.9%%): $%.0f (%.2f%%)\n\n",
            -var_999, -var_999 / total_portfolio_value * 100))

# Expected Shortfall
cat("=== Expected Shortfall (CVaR) ===\n")
es_95 <- mean(mc_pnl[mc_pnl <= var_95])
es_99 <- mean(mc_pnl[mc_pnl <= var_99])

cat(sprintf("ES (95%%): $%.0f (%.2f%%)\n",
            -es_95, -es_95 / total_portfolio_value * 100))
cat(sprintf("ES (99%%): $%.0f (%.2f%%)\n\n",
            -es_99, -es_99 / total_portfolio_value * 100))

# Portfolio statistics
cat("=== Portfolio Statistics ===\n")
cat(sprintf("Mean P&L: $%.0f\n", mean(mc_pnl)))
cat(sprintf("Std Dev P&L: $%.0f\n", sd(mc_pnl)))
cat(sprintf("Skewness: %.3f\n",
            mean((mc_pnl - mean(mc_pnl))^3) / sd(mc_pnl)^3))
cat(sprintf("Probability of loss: %.2f%%\n\n",
            mean(mc_pnl < 0) * 100))

# Regulatory metrics
cat("=== Regulatory Metrics ===\n")
market_risk_capital <- -var_99 * 3
cat(sprintf("Market Risk Capital Requirement: $%.0f\n", market_risk_capital))
cat(sprintf("Capital as %% of Portfolio: %.2f%%\n\n",
            market_risk_capital / total_portfolio_value * 100))

# Performance comparison
cat("=== Performance Comparison ===\n\n")
estimated_local <- local_time * length(all_scenarios) / length(test_scenarios) / 60
speedup <- estimated_local / cloud_time
cat(sprintf("Local (estimated): %.1f minutes\n", estimated_local))
cat(sprintf("Cloud (%d workers): %.2f minutes\n", n_workers, cloud_time))
cat(sprintf("Speedup: %.1fx\n", speedup))

cat("\n✓ Done!\n")
