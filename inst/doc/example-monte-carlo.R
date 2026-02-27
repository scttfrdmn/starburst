## ----include = FALSE----------------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>"
)

## ----setup, eval=FALSE--------------------------------------------------------
# library(starburst)
# library(ggplot2)

## ----simulation, eval=FALSE---------------------------------------------------
# simulate_portfolio <- function(seed) {
#   set.seed(seed)
# 
#   # Portfolio parameters
#   n_days <- 252
#   initial_value <- 1000000  # $1M portfolio
# 
#   # Asset allocation (60/40 stocks/bonds)
#   stock_weight <- 0.6
#   bond_weight <- 0.4
# 
#   # Expected returns (annualized)
#   stock_return <- 0.10 / 252  # 10% annual
#   bond_return <- 0.04 / 252   # 4% annual
# 
#   # Volatility (annualized)
#   stock_vol <- 0.20 / sqrt(252)  # 20% annual
#   bond_vol <- 0.05 / sqrt(252)   # 5% annual
# 
#   # Correlation
#   correlation <- 0.3
# 
#   # Generate correlated returns
#   stock_returns <- rnorm(n_days, mean = stock_return, sd = stock_vol)
#   bond_noise <- rnorm(n_days)
#   bond_returns <- rnorm(n_days, mean = bond_return, sd = bond_vol)
#   bond_returns <- correlation * stock_returns +
#                   sqrt(1 - correlation^2) * bond_returns
# 
#   # Portfolio returns
#   portfolio_returns <- stock_weight * stock_returns +
#                       bond_weight * bond_returns
# 
#   # Cumulative value
#   portfolio_values <- initial_value * cumprod(1 + portfolio_returns)
# 
#   # Calculate metrics
#   final_value <- portfolio_values[n_days]
#   max_drawdown <- max((cummax(portfolio_values) - portfolio_values) /
#                       cummax(portfolio_values))
#   sharpe_ratio <- mean(portfolio_returns) / sd(portfolio_returns) * sqrt(252)
# 
#   list(
#     final_value = final_value,
#     return_pct = (final_value - initial_value) / initial_value * 100,
#     max_drawdown = max_drawdown,
#     sharpe_ratio = sharpe_ratio,
#     min_value = min(portfolio_values),
#     max_value = max(portfolio_values)
#   )
# }

## ----local, eval=FALSE--------------------------------------------------------
# # Test with 100 simulations
# set.seed(123)
# local_start <- Sys.time()
# local_results <- lapply(1:100, simulate_portfolio)
# local_time <- as.numeric(difftime(Sys.time(), local_start, units = "secs"))
# 
# cat(sprintf("100 simulations completed in %.1f seconds\n", local_time))
# cat(sprintf("Estimated time for 10,000: %.1f minutes\n",
#             local_time * 100 / 60))

## ----cloud, eval=FALSE--------------------------------------------------------
# # Run 10,000 simulations on 50 workers
# results <- starburst_map(
#   1:10000,
#   simulate_portfolio,
#   workers = 50,
#   cpu = 2,
#   memory = "4GB"
# )

## ----analysis, eval=FALSE-----------------------------------------------------
# # Extract metrics
# final_values <- sapply(results, function(x) x$final_value)
# returns <- sapply(results, function(x) x$return_pct)
# sharpe_ratios <- sapply(results, function(x) x$sharpe_ratio)
# max_drawdowns <- sapply(results, function(x) x$max_drawdown)
# 
# # Summary statistics
# cat("\n=== Portfolio Simulation Results (10,000 scenarios) ===\n")
# cat(sprintf("Mean final value: $%.0f\n", mean(final_values)))
# cat(sprintf("Median final value: $%.0f\n", median(final_values)))
# cat(sprintf("\nMean return: %.2f%%\n", mean(returns)))
# cat(sprintf("Std dev of returns: %.2f%%\n", sd(returns)))
# cat(sprintf("\nValue at Risk (5%%): $%.0f\n",
#             quantile(final_values, 0.05)))
# cat(sprintf("Expected Shortfall (5%%): $%.0f\n",
#             mean(final_values[final_values <= quantile(final_values, 0.05)])))
# cat(sprintf("\nMean Sharpe Ratio: %.2f\n", mean(sharpe_ratios)))
# cat(sprintf("Mean Max Drawdown: %.2f%%\n", mean(max_drawdowns) * 100))
# cat(sprintf("\nProbability of loss: %.2f%%\n",
#             mean(returns < 0) * 100))
# 
# # Distribution plot
# hist(final_values / 1000,
#      breaks = 50,
#      main = "Distribution of Portfolio Final Values",
#      xlab = "Final Value ($1000s)",
#      col = "lightblue",
#      border = "white")
# abline(v = 1000, col = "red", lwd = 2, lty = 2)
# abline(v = quantile(final_values / 1000, 0.05), col = "orange", lwd = 2, lty = 2)
# legend("topright",
#        c("Initial Value", "VaR (5%)"),
#        col = c("red", "orange"),
#        lwd = 2, lty = 2)

## ----eval=FALSE---------------------------------------------------------------
# system.file("examples/monte-carlo.R", package = "starburst")

## ----eval=FALSE---------------------------------------------------------------
# source(system.file("examples/monte-carlo.R", package = "starburst"))

