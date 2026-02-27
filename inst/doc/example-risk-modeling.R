## ----include = FALSE----------------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>"
)

## ----setup, eval=FALSE--------------------------------------------------------
# library(starburst)

## ----data, eval=FALSE---------------------------------------------------------
# set.seed(3141)
# 
# # Define portfolio positions
# n_assets <- 50
# 
# portfolio <- data.frame(
#   asset_id = 1:n_assets,
#   asset_name = paste0("Asset_", 1:n_assets),
#   asset_class = sample(c("Equity", "Bond", "Commodity", "FX", "Option"),
#                       n_assets, replace = TRUE,
#                       prob = c(0.4, 0.3, 0.1, 0.1, 0.1)),
#   position_value = rlnorm(n_assets, log(1000000), 1),
#   beta = rnorm(n_assets, 1.0, 0.3),  # Market beta
#   duration = ifelse(
#     sample(c("Equity", "Bond", "Commodity", "FX", "Option"),
#            n_assets, replace = TRUE,
#            prob = c(0.4, 0.3, 0.1, 0.1, 0.1)) == "Bond",
#     runif(n_assets, 1, 10), 0
#   ),
#   delta = runif(n_assets, 0.3, 0.7),  # Options delta
#   vega = runif(n_assets, 10000, 50000),  # Options vega
#   stringsAsFactors = FALSE
# )
# 
# total_portfolio_value <- sum(portfolio$position_value)
# 
# cat(sprintf("Portfolio Summary:\n"))
# cat(sprintf("  Total value: $%.0f\n", total_portfolio_value))
# cat(sprintf("  Number of positions: %d\n", n_assets))
# cat(sprintf("  Asset classes: %s\n",
#             paste(unique(portfolio$asset_class), collapse = ", ")))
# 
# # Breakdown by asset class
# cat(sprintf("\nAllocation by asset class:\n"))
# for (ac in unique(portfolio$asset_class)) {
#   pct <- sum(portfolio$position_value[portfolio$asset_class == ac]) /
#          total_portfolio_value * 100
#   cat(sprintf("  %s: %.1f%%\n", ac, pct))
# }

## ----scenarios, eval=FALSE----------------------------------------------------
# # Generate stress test scenarios
# generate_stress_scenarios <- function(n_scenarios = 100) {
#   scenarios <- list()
# 
#   for (i in 1:n_scenarios) {
#     # Define adverse market moves
#     scenario <- list(
#       scenario_id = i,
#       scenario_type = "stress_test",
#       equity_shock = rnorm(1, -0.15, 0.05),  # Average -15% with volatility
#       rate_shock = rnorm(1, 0.02, 0.01),     # +200bps average
#       vol_shock = rnorm(1, 0.5, 0.2),        # +50% volatility
#       fx_shock = rnorm(1, -0.05, 0.03),      # -5% average
#       commodity_shock = rnorm(1, -0.10, 0.05)
#     )
#     scenarios[[i]] <- scenario
#   }
# 
#   scenarios
# }
# 
# # Generate Monte Carlo scenarios
# generate_mc_scenarios <- function(n_scenarios = 1000) {
#   scenarios <- list()
# 
#   for (i in 1:n_scenarios) {
#     scenario <- list(
#       scenario_id = 1000 + i,
#       scenario_type = "monte_carlo",
#       equity_shock = rnorm(1, 0, 0.10),
#       rate_shock = rnorm(1, 0, 0.005),
#       vol_shock = rnorm(1, 0, 0.2),
#       fx_shock = rnorm(1, 0, 0.05),
#       commodity_shock = rnorm(1, 0, 0.12)
#     )
#     scenarios[[i]] <- scenario
#   }
# 
#   scenarios
# }
# 
# # Generate sensitivity scenarios (grid around current values)
# generate_sensitivity_scenarios <- function() {
#   scenarios <- list()
#   scenario_id <- 20000
# 
#   risk_factors <- c("equity", "rate", "vol", "fx", "commodity")
#   shock_levels <- seq(-0.02, 0.02, by = 0.005)  # -2% to +2% in 0.5% steps
# 
#   for (factor in risk_factors) {
#     for (shock in shock_levels) {
#       scenario_id <- scenario_id + 1
# 
#       scenario <- list(
#         scenario_id = scenario_id,
#         scenario_type = "sensitivity",
#         risk_factor = factor,
#         equity_shock = if (factor == "equity") shock else 0,
#         rate_shock = if (factor == "rate") shock else 0,
#         vol_shock = if (factor == "vol") shock else 0,
#         fx_shock = if (factor == "fx") shock else 0,
#         commodity_shock = if (factor == "commodity") shock else 0
#       )
#       scenarios[[length(scenarios) + 1]] <- scenario
#     }
#   }
# 
#   scenarios
# }

## ----valuation, eval=FALSE----------------------------------------------------
# value_portfolio_scenario <- function(scenario, portfolio_data) {
#   # Simulate computation time
#   Sys.sleep(0.001)
# 
#   # Calculate position-level P&L
#   position_pnl <- numeric(nrow(portfolio_data))
# 
#   for (i in 1:nrow(portfolio_data)) {
#     asset <- portfolio_data[i, ]
# 
#     # Apply shocks based on asset class
#     pnl <- 0
# 
#     if (asset$asset_class == "Equity") {
#       # Equity: affected by equity shock and beta
#       pnl <- asset$position_value * scenario$equity_shock * asset$beta
#     } else if (asset$asset_class == "Bond") {
#       # Bond: affected by rate shock and duration
#       pnl <- -asset$position_value * scenario$rate_shock * asset$duration
#     } else if (asset$asset_class == "Commodity") {
#       # Commodity: direct commodity shock
#       pnl <- asset$position_value * scenario$commodity_shock
#     } else if (asset$asset_class == "FX") {
#       # FX: direct fx shock
#       pnl <- asset$position_value * scenario$fx_shock
#     } else if (asset$asset_class == "Option") {
#       # Option: delta and vega exposure
#       pnl <- asset$position_value * scenario$equity_shock * asset$delta +
#              asset$vega * scenario$vol_shock
#     }
# 
#     position_pnl[i] <- pnl
#   }
# 
#   # Aggregate results
#   total_pnl <- sum(position_pnl)
#   portfolio_return <- total_pnl / sum(portfolio_data$position_value)
# 
#   list(
#     scenario_id = scenario$scenario_id,
#     scenario_type = scenario$scenario_type,
#     total_pnl = total_pnl,
#     portfolio_return = portfolio_return,
#     equity_contribution = sum(position_pnl[portfolio_data$asset_class == "Equity"]),
#     bond_contribution = sum(position_pnl[portfolio_data$asset_class == "Bond"]),
#     position_pnl = position_pnl
#   )
# }

## ----local, eval=FALSE--------------------------------------------------------
# # Generate sample scenarios
# test_stress <- generate_stress_scenarios(n_scenarios = 20)
# test_mc <- generate_mc_scenarios(n_scenarios = 100)
# 
# test_scenarios <- c(test_stress, test_mc)
# 
# cat(sprintf("Running local benchmark (%d scenarios)...\n", length(test_scenarios)))
# local_start <- Sys.time()
# 
# local_results <- lapply(test_scenarios, value_portfolio_scenario,
#                        portfolio_data = portfolio)
# 
# local_time <- as.numeric(difftime(Sys.time(), local_start, units = "secs"))
# 
# cat(sprintf("✓ Completed in %.2f seconds\n", local_time))
# cat(sprintf("  Average time per scenario: %.3f seconds\n",
#             local_time / length(test_scenarios)))
# cat(sprintf("  Estimated time for 10,000 scenarios: %.1f minutes\n",
#             local_time * 10000 / length(test_scenarios) / 60))

## ----cloud, eval=FALSE--------------------------------------------------------
# # Generate full scenario set
# cat("Generating scenario sets...\n")
# stress_scenarios <- generate_stress_scenarios(n_scenarios = 100)
# mc_scenarios <- generate_mc_scenarios(n_scenarios = 10000)
# sensitivity_scenarios <- generate_sensitivity_scenarios()
# 
# all_scenarios <- c(stress_scenarios, mc_scenarios, sensitivity_scenarios)
# 
# cat(sprintf("  Stress test scenarios: %d\n", length(stress_scenarios)))
# cat(sprintf("  Monte Carlo scenarios: %s\n",
#             format(length(mc_scenarios), big.mark = ",")))
# cat(sprintf("  Sensitivity scenarios: %d\n", length(sensitivity_scenarios)))
# cat(sprintf("  Total scenarios: %s\n\n",
#             format(length(all_scenarios), big.mark = ",")))
# 
# # Run parallel valuation
# n_workers <- 50
# 
# cat(sprintf("Running risk analysis (%s scenarios) on %d workers...\n",
#             format(length(all_scenarios), big.mark = ","), n_workers))
# 
# cloud_start <- Sys.time()
# 
# results <- starburst_map(
#   all_scenarios,
#   value_portfolio_scenario,
#   portfolio_data = portfolio,
#   workers = n_workers,
#   cpu = 2,
#   memory = "4GB"
# )
# 
# cloud_time <- as.numeric(difftime(Sys.time(), cloud_start, units = "mins"))
# 
# cat(sprintf("\n✓ Completed in %.2f minutes\n", cloud_time))

## ----analysis, eval=FALSE-----------------------------------------------------
# # Extract P&L from all scenarios
# pnl_values <- sapply(results, function(x) x$total_pnl)
# return_values <- sapply(results, function(x) x$portfolio_return)
# 
# # Separate by scenario type
# stress_pnl <- pnl_values[1:100]
# mc_pnl <- pnl_values[101:10100]
# sensitivity_pnl <- pnl_values[10101:length(pnl_values)]
# 
# cat("\n=== Comprehensive Risk Analysis Results ===\n\n")
# 
# # 1. Stress Test Results
# cat("=== Stress Test Results ===\n")
# cat(sprintf("Worst case loss: $%.0f (%.2f%%)\n",
#             min(stress_pnl),
#             min(stress_pnl) / total_portfolio_value * 100))
# cat(sprintf("Average stress loss: $%.0f (%.2f%%)\n",
#             mean(stress_pnl),
#             mean(stress_pnl) / total_portfolio_value * 100))
# cat(sprintf("Best case (least bad): $%.0f (%.2f%%)\n\n",
#             max(stress_pnl),
#             max(stress_pnl) / total_portfolio_value * 100))
# 
# # 2. Value at Risk (VaR) from Monte Carlo
# cat("=== Value at Risk (Monte Carlo) ===\n")
# var_95 <- quantile(mc_pnl, 0.05)
# var_99 <- quantile(mc_pnl, 0.01)
# var_999 <- quantile(mc_pnl, 0.001)
# 
# cat(sprintf("VaR (95%%): $%.0f (%.2f%%)\n",
#             -var_95, -var_95 / total_portfolio_value * 100))
# cat(sprintf("VaR (99%%): $%.0f (%.2f%%)\n",
#             -var_99, -var_99 / total_portfolio_value * 100))
# cat(sprintf("VaR (99.9%%): $%.0f (%.2f%%)\n\n",
#             -var_999, -var_999 / total_portfolio_value * 100))
# 
# # 3. Expected Shortfall (Conditional VaR)
# cat("=== Expected Shortfall (CVaR) ===\n")
# es_95 <- mean(mc_pnl[mc_pnl <= var_95])
# es_99 <- mean(mc_pnl[mc_pnl <= var_99])
# 
# cat(sprintf("ES (95%%): $%.0f (%.2f%%)\n",
#             -es_95, -es_95 / total_portfolio_value * 100))
# cat(sprintf("ES (99%%): $%.0f (%.2f%%)\n\n",
#             -es_99, -es_99 / total_portfolio_value * 100))
# 
# # 4. Portfolio Statistics
# cat("=== Portfolio Statistics ===\n")
# cat(sprintf("Mean P&L: $%.0f\n", mean(mc_pnl)))
# cat(sprintf("Std Dev P&L: $%.0f\n", sd(mc_pnl)))
# cat(sprintf("Skewness: %.3f\n",
#             mean((mc_pnl - mean(mc_pnl))^3) / sd(mc_pnl)^3))
# cat(sprintf("Probability of loss: %.2f%%\n\n",
#             mean(mc_pnl < 0) * 100))
# 
# # 5. Asset Class Contributions
# cat("=== Risk Contribution by Asset Class ===\n")
# for (ac in unique(portfolio$asset_class)) {
#   ac_contrib <- sapply(results[101:10100], function(x) {
#     sum(x$position_pnl[portfolio$asset_class == ac])
#   })
#   ac_var <- quantile(ac_contrib, 0.05)
#   cat(sprintf("%s VaR (95%%): $%.0f\n", ac, -ac_var))
# }
# 
# # 6. Sensitivity Analysis Summary
# if (length(sensitivity_pnl) > 0) {
#   cat("\n=== Sensitivity Analysis ===\n")
#   cat(sprintf("Maximum sensitivity loss: $%.0f\n", min(sensitivity_pnl)))
#   cat(sprintf("Maximum sensitivity gain: $%.0f\n", max(sensitivity_pnl)))
#   cat(sprintf("Average absolute sensitivity: $%.0f\n",
#               mean(abs(sensitivity_pnl))))
# }
# 
# # 7. Regulatory Metrics
# cat("\n=== Regulatory Metrics ===\n")
# market_risk_capital <- -var_99 * 3  # Simplified Basel III calculation
# cat(sprintf("Market Risk Capital Requirement: $%.0f\n", market_risk_capital))
# cat(sprintf("Capital as %% of Portfolio: %.2f%%\n",
#             market_risk_capital / total_portfolio_value * 100))

## ----incremental, eval=FALSE--------------------------------------------------
# # For each position, calculate VaR with and without it
# analyze_incremental_risk <- function(position_idx, scenarios, portfolio_data) {
#   # Create modified portfolio without this position
#   modified_portfolio <- portfolio_data
#   original_value <- modified_portfolio$position_value[position_idx]
#   modified_portfolio$position_value[position_idx] <- 0
# 
#   # Value under all scenarios
#   results_without <- lapply(scenarios, value_portfolio_scenario,
#                            portfolio_data = modified_portfolio)
# 
#   pnl_without <- sapply(results_without, function(x) x$total_pnl)
#   var_without <- quantile(pnl_without, 0.05)
# 
#   list(
#     position_idx = position_idx,
#     asset_name = portfolio_data$asset_name[position_idx],
#     var_without = var_without,
#     original_value = original_value
#   )
# }
# 
# # Run in parallel (demonstration - would use smaller scenario set)
# # incremental_results <- starburst_map(
# #   1:nrow(portfolio),
# #   analyze_incremental_risk,
# #   scenarios = mc_scenarios[1:1000],  # Use subset for speed
# #   portfolio_data = portfolio,
# #   workers = 25
# # )

## ----eval=FALSE---------------------------------------------------------------
# system.file("examples/risk-modeling.R", package = "starburst")

## ----eval=FALSE---------------------------------------------------------------
# source(system.file("examples/risk-modeling.R", package = "starburst"))

