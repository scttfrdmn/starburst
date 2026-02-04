#!/usr/bin/env Rscript
#
# Parallel Geospatial Analysis Example
#
# This script demonstrates parallel spatial analysis across geographic regions.
# It analyzes store locations, competitors, and customer coverage.
#
# Usage:
#   Rscript geospatial.R
#   # or from R:
#   source(system.file("examples/geospatial.R", package = "starburst"))

library(starburst)

cat("=== Parallel Geospatial Analysis ===\n\n")

# Generate synthetic geospatial data
set.seed(789)

# Define metropolitan regions
regions <- data.frame(
  region_id = 1:20,
  region_name = c("New York", "Los Angeles", "Chicago", "Houston", "Phoenix",
                 "Philadelphia", "San Antonio", "San Diego", "Dallas", "San Jose",
                 "Austin", "Jacksonville", "Fort Worth", "Columbus", "Charlotte",
                 "San Francisco", "Indianapolis", "Seattle", "Denver", "Boston"),
  center_lat = c(40.71, 34.05, 41.88, 29.76, 33.45,
                39.95, 29.42, 32.72, 32.78, 37.34,
                30.27, 30.33, 32.75, 39.96, 35.23,
                37.77, 39.77, 47.61, 39.74, 42.36),
  center_lon = c(-74.01, -118.24, -87.63, -95.37, -112.07,
                -75.17, -98.49, -117.16, -96.80, -121.89,
                -97.74, -81.66, -97.33, -83.00, -80.84,
                -122.42, -86.16, -122.33, -104.99, -71.06),
  stringsAsFactors = FALSE
)

cat("Generating geospatial dataset...\n")

# Generate stores (5 per region)
stores <- do.call(rbind, lapply(1:nrow(regions), function(i) {
  n_stores <- 5
  data.frame(
    store_id = (i - 1) * n_stores + 1:n_stores,
    region_id = regions$region_id[i],
    region_name = regions$region_name[i],
    latitude = regions$center_lat[i] + rnorm(n_stores, 0, 0.1),
    longitude = regions$center_lon[i] + rnorm(n_stores, 0, 0.1),
    annual_revenue = rlnorm(n_stores, log(1000000), 0.5),
    stringsAsFactors = FALSE
  )
}))

# Generate competitors (10 per region)
competitors <- do.call(rbind, lapply(1:nrow(regions), function(i) {
  n_competitors <- 10
  data.frame(
    competitor_id = (i - 1) * n_competitors + 1:n_competitors,
    region_id = regions$region_id[i],
    latitude = regions$center_lat[i] + rnorm(n_competitors, 0, 0.15),
    longitude = regions$center_lon[i] + rnorm(n_competitors, 0, 0.15),
    stringsAsFactors = FALSE
  )
}))

# Generate customers (1000 per region)
customers <- do.call(rbind, lapply(1:nrow(regions), function(i) {
  n_customers <- 1000
  data.frame(
    customer_id = (i - 1) * n_customers + 1:n_customers,
    region_id = regions$region_id[i],
    latitude = regions$center_lat[i] + rnorm(n_customers, 0, 0.2),
    longitude = regions$center_lon[i] + rnorm(n_customers, 0, 0.2),
    annual_spend = rlnorm(n_customers, log(500), 0.8),
    stringsAsFactors = FALSE
  )
}))

cat(sprintf("✓ Dataset created:\n"))
cat(sprintf("  %d stores across %d regions\n", nrow(stores), nrow(regions)))
cat(sprintf("  %s competitors\n", format(nrow(competitors), big.mark = ",")))
cat(sprintf("  %s customers\n\n", format(nrow(customers), big.mark = ",")))

# Haversine distance function
haversine_distance <- function(lat1, lon1, lat2, lon2) {
  R <- 6371  # Earth's radius in km

  lat1_rad <- lat1 * pi / 180
  lat2_rad <- lat2 * pi / 180
  delta_lat <- (lat2 - lat1) * pi / 180
  delta_lon <- (lon2 - lon1) * pi / 180

  a <- sin(delta_lat/2)^2 +
       cos(lat1_rad) * cos(lat2_rad) * sin(delta_lon/2)^2
  c <- 2 * atan2(sqrt(a), sqrt(1-a))

  R * c
}

# Spatial analysis function
analyze_region <- function(region_id, stores_data, competitors_data,
                          customers_data) {
  region_stores <- stores_data[stores_data$region_id == region_id, ]
  region_competitors <- competitors_data[competitors_data$region_id == region_id, ]
  region_customers <- customers_data[customers_data$region_id == region_id, ]

  if (nrow(region_stores) == 0) {
    return(NULL)
  }

  store_metrics <- lapply(1:nrow(region_stores), function(i) {
    store <- region_stores[i, ]

    # Distance to competitors
    competitor_distances <- sapply(1:nrow(region_competitors), function(j) {
      haversine_distance(
        store$latitude, store$longitude,
        region_competitors$latitude[j], region_competitors$longitude[j]
      )
    })
    nearest_competitor_km <- min(competitor_distances)
    avg_competitor_distance <- mean(competitor_distances)
    competitors_within_5km <- sum(competitor_distances <= 5)

    # Customer coverage
    customer_distances <- sapply(1:nrow(region_customers), function(j) {
      haversine_distance(
        store$latitude, store$longitude,
        region_customers$latitude[j], region_customers$longitude[j]
      )
    })

    customers_1km <- sum(customer_distances <= 1)
    customers_3km <- sum(customer_distances <= 3)
    customers_5km <- sum(customer_distances <= 5)
    customers_10km <- sum(customer_distances <= 10)

    nearby_customers <- region_customers[customer_distances <= 5, ]
    market_potential <- if (nrow(nearby_customers) > 0) {
      sum(nearby_customers$annual_spend)
    } else {
      0
    }

    avg_customer_distance <- mean(customer_distances)
    median_customer_distance <- median(customer_distances)

    area_10km <- pi * 10^2
    customer_density <- customers_10km / area_10km
    competitive_intensity <- min(1, competitors_within_5km / 10)

    data.frame(
      store_id = store$store_id,
      region_id = region_id,
      region_name = store$region_name,
      annual_revenue = store$annual_revenue,
      nearest_competitor_km = nearest_competitor_km,
      avg_competitor_distance = avg_competitor_distance,
      competitors_within_5km = competitors_within_5km,
      customers_1km = customers_1km,
      customers_3km = customers_3km,
      customers_5km = customers_5km,
      customers_10km = customers_10km,
      market_potential = market_potential,
      avg_customer_distance = avg_customer_distance,
      median_customer_distance = median_customer_distance,
      customer_density = customer_density,
      competitive_intensity = competitive_intensity,
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, store_metrics)
}

# Local benchmark (3 regions)
test_regions <- c(1, 2, 3)

cat(sprintf("Running local benchmark (%d regions)...\n", length(test_regions)))
local_start <- Sys.time()

local_results <- lapply(test_regions, analyze_region,
                       stores_data = stores,
                       competitors_data = competitors,
                       customers_data = customers)
local_metrics <- do.call(rbind, local_results)

local_time <- as.numeric(difftime(Sys.time(), local_start, units = "secs"))

cat(sprintf("✓ Completed in %.2f seconds\n", local_time))
cat(sprintf("  Processed %d stores\n", nrow(local_metrics)))
cat(sprintf("  Estimated time for all %d regions: %.1f seconds\n\n",
            nrow(regions), local_time * (nrow(regions) / length(test_regions))))

# Cloud execution
n_workers <- 20

cat(sprintf("Analyzing %d regions on %d workers...\n", nrow(regions), n_workers))

cloud_start <- Sys.time()

results <- starburst_map(
  regions$region_id,
  analyze_region,
  stores_data = stores,
  competitors_data = competitors,
  customers_data = customers,
  workers = n_workers,
  cpu = 2,
  memory = "4GB"
)

cloud_time <- as.numeric(difftime(Sys.time(), cloud_start, units = "secs"))

cat(sprintf("\n✓ Completed in %.1f seconds\n\n", cloud_time))

# Combine results
spatial_metrics <- do.call(rbind, results)

# Print results
cat("=== Geospatial Analysis Results ===\n\n")
cat(sprintf("Total stores analyzed: %d\n", nrow(spatial_metrics)))
cat(sprintf("Regions covered: %d\n\n", length(unique(spatial_metrics$region_id))))

# Competition analysis
cat("=== Competition Analysis ===\n")
cat(sprintf("Average distance to nearest competitor: %.2f km\n",
            mean(spatial_metrics$nearest_competitor_km)))
cat(sprintf("Median distance to nearest competitor: %.2f km\n",
            median(spatial_metrics$nearest_competitor_km)))
cat(sprintf("Average competitors within 5km: %.1f\n",
            mean(spatial_metrics$competitors_within_5km)))
cat(sprintf("High competition stores (5+ nearby): %d (%.1f%%)\n\n",
            sum(spatial_metrics$competitors_within_5km >= 5),
            mean(spatial_metrics$competitors_within_5km >= 5) * 100))

# Customer coverage
cat("=== Customer Coverage Analysis ===\n")
cat(sprintf("Average customers within 5km: %.0f\n",
            mean(spatial_metrics$customers_5km)))
cat(sprintf("Average market potential (5km): $%,.0f\n",
            mean(spatial_metrics$market_potential)))
cat(sprintf("Average customer density: %.1f customers/km²\n",
            mean(spatial_metrics$customer_density)))
cat(sprintf("Median distance to customers: %.2f km\n\n",
            mean(spatial_metrics$median_customer_distance)))

# Performance insights
cat("=== Performance Insights ===\n")
correlation <- cor(spatial_metrics$annual_revenue,
                   spatial_metrics$market_potential)
cat(sprintf("Correlation (revenue vs market potential): %.3f\n\n", correlation))

# Opportunity stores
opportunity_stores <- spatial_metrics[
  spatial_metrics$market_potential > median(spatial_metrics$market_potential) &
  spatial_metrics$competitors_within_5km < median(spatial_metrics$competitors_within_5km),
]
cat(sprintf("High opportunity stores: %d\n", nrow(opportunity_stores)))
if (nrow(opportunity_stores) > 0) {
  cat(sprintf("  Avg market potential: $%,.0f\n",
              mean(opportunity_stores$market_potential)))
  cat(sprintf("  Avg competitors nearby: %.1f\n\n",
              mean(opportunity_stores$competitors_within_5km)))
}

# Top regions
cat("=== Top 5 Regions by Market Potential ===\n")
region_summary <- aggregate(market_potential ~ region_name,
                           data = spatial_metrics, FUN = mean)
region_summary <- region_summary[order(-region_summary$market_potential), ]
for (i in 1:min(5, nrow(region_summary))) {
  cat(sprintf("%d. %s: $%,.0f\n", i,
              region_summary$region_name[i],
              region_summary$market_potential[i]))
}

# Performance comparison
cat("\n=== Performance Comparison ===\n\n")
estimated_local <- local_time * (nrow(regions) / length(test_regions))
speedup <- estimated_local / cloud_time
cat(sprintf("Local (estimated): %.1f seconds\n", estimated_local))
cat(sprintf("Cloud (%d workers): %.1f seconds\n", n_workers, cloud_time))
cat(sprintf("Speedup: %.1fx\n", speedup))

cat("\n✓ Done!\n")
