#!/usr/bin/env Rscript
# Quick timing test for one task

run_mcmc_chain <- function(chain_id, n_iter = 100000, n_params = 50) {
  set.seed(chain_id)

  log_likelihood <- function(params, data) {
    X <- matrix(rnorm(length(data) * length(params)),
                nrow = length(data), ncol = length(params))
    linear_pred <- X %*% params
    size <- exp(params[1])
    mu <- exp(linear_pred)
    sum(dnbinom(data, size = size, mu = mu, log = TRUE))
  }

  n_obs <- 1000
  data <- rpois(n_obs, lambda = 50)

  current <- rnorm(n_params)
  samples <- matrix(0, nrow = n_iter, ncol = n_params)
  accept_count <- 0

  for (i in 1:n_iter) {
    proposal <- current + rnorm(n_params, sd = 0.1)

    current_ll <- tryCatch(log_likelihood(current, data), error = function(e) -Inf)
    proposal_ll <- tryCatch(log_likelihood(proposal, data), error = function(e) -Inf)

    log_ratio <- proposal_ll - current_ll
    if (log(runif(1)) < log_ratio) {
      current <- proposal
      accept_count <- accept_count + 1
    }

    samples[i, ] <- current
  }

  list(
    chain_id = chain_id,
    samples = samples,
    acceptance_rate = accept_count / n_iter,
    posterior_mean = colMeans(samples[-(1:1000), ])
  )
}

cat("Testing MCMC chain timing...\n")
start <- Sys.time()
result <- run_mcmc_chain(1, n_iter = 10000, n_params = 50)
elapsed <- as.numeric(difftime(Sys.time(), start, units = "secs"))

cat(sprintf("\nOne MCMC chain (10k iterations): %.1f seconds\n", elapsed))
cat(sprintf("Estimated for 100k iterations: %.1f seconds (%.1f minutes)\n",
            elapsed * 10, elapsed * 10 / 60))
cat(sprintf("8 chains sequentially: %.1f minutes\n", elapsed * 10 * 8 / 60))
cat(sprintf("Acceptance rate: %.1f%%\n", result$acceptance_rate * 100))
