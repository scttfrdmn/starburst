## ----include = FALSE----------------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>"
)

## ----setup, eval=FALSE--------------------------------------------------------
# library(starburst)

## ----data, eval=FALSE---------------------------------------------------------
# set.seed(789)
# 
# # Define 20 metropolitan regions (simplified coordinates)
# regions <- data.frame(
#   region_id = 1:20,
#   region_name = c("New York", "Los Angeles", "Chicago", "Houston", "Phoenix",
#                  "Philadelphia", "San Antonio", "San Diego", "Dallas", "San Jose",
#                  "Austin", "Jacksonville", "Fort Worth", "Columbus", "Charlotte",
#                  "San Francisco", "Indianapolis", "Seattle", "Denver", "Boston"),
#   center_lat = c(40.71, 34.05, 41.88, 29.76, 33.45,
#                 39.95, 29.42, 32.72, 32.78, 37.34,
#                 30.27, 30.33, 32.75, 39.96, 35.23,
#                 37.77, 39.77, 47.61, 39.74, 42.36),
#   center_lon = c(-74.01, -118.24, -87.63, -95.37, -112.07,
#                 -75.17, -98.49, -117.16, -96.80, -121.89,
#                 -97.74, -81.66, -97.33, -83.00, -80.84,
#                 -122.42, -86.16, -122.33, -104.99, -71.06),
#   stringsAsFactors = FALSE
# )
# 
# # Generate store locations (5 per region)
# stores <- do.call(rbind, lapply(1:nrow(regions), function(i) {
#   n_stores <- 5
#   # Add random offset to region center
#   data.frame(
#     store_id = (i - 1) * n_stores + 1:n_stores,
#     region_id = regions$region_id[i],
#     region_name = regions$region_name[i],
#     latitude = regions$center_lat[i] + rnorm(n_stores, 0, 0.1),
#     longitude = regions$center_lon[i] + rnorm(n_stores, 0, 0.1),
#     annual_revenue = rlnorm(n_stores, log(1000000), 0.5),
#     stringsAsFactors = FALSE
#   )
# }))
# 
# # Generate competitor locations (10 per region)
# competitors <- do.call(rbind, lapply(1:nrow(regions), function(i) {
#   n_competitors <- 10
#   data.frame(
#     competitor_id = (i - 1) * n_competitors + 1:n_competitors,
#     region_id = regions$region_id[i],
#     latitude = regions$center_lat[i] + rnorm(n_competitors, 0, 0.15),
#     longitude = regions$center_lon[i] + rnorm(n_competitors, 0, 0.15),
#     stringsAsFactors = FALSE
#   )
# }))
# 
# # Generate customer points (1000 per region)
# customers <- do.call(rbind, lapply(1:nrow(regions), function(i) {
#   n_customers <- 1000
#   data.frame(
#     customer_id = (i - 1) * n_customers + 1:n_customers,
#     region_id = regions$region_id[i],
#     latitude = regions$center_lat[i] + rnorm(n_customers, 0, 0.2),
#     longitude = regions$center_lon[i] + rnorm(n_customers, 0, 0.2),
#     annual_spend = rlnorm(n_customers, log(500), 0.8),
#     stringsAsFactors = FALSE
#   )
# }))
# 
# cat(sprintf("Dataset created:\n"))
# cat(sprintf("  %d stores across %d regions\n", nrow(stores), nrow(regions)))
# cat(sprintf("  %s competitors\n", format(nrow(competitors), big.mark = ",")))
# cat(sprintf("  %s customers\n", format(nrow(customers), big.mark = ",")))

## ----spatial-fn, eval=FALSE---------------------------------------------------
# # Haversine distance function (in km)
# haversine_distance <- function(lat1, lon1, lat2, lon2) {
#   R <- 6371  # Earth's radius in km
# 
#   lat1_rad <- lat1 * pi / 180
#   lat2_rad <- lat2 * pi / 180
#   delta_lat <- (lat2 - lat1) * pi / 180
#   delta_lon <- (lon2 - lon1) * pi / 180
# 
#   a <- sin(delta_lat/2)^2 +
#        cos(lat1_rad) * cos(lat2_rad) * sin(delta_lon/2)^2
#   c <- 2 * atan2(sqrt(a), sqrt(1-a))
# 
#   R * c
# }
# 
# analyze_region <- function(region_id, stores_data, competitors_data,
#                           customers_data) {
#   # Filter data for this region
#   region_stores <- stores_data[stores_data$region_id == region_id, ]
#   region_competitors <- competitors_data[competitors_data$region_id == region_id, ]
#   region_customers <- customers_data[customers_data$region_id == region_id, ]
# 
#   if (nrow(region_stores) == 0) {
#     return(NULL)
#   }
# 
#   # Analyze each store
#   store_metrics <- lapply(1:nrow(region_stores), function(i) {
#     store <- region_stores[i, ]
# 
#     # Distance to nearest competitor
#     competitor_distances <- sapply(1:nrow(region_competitors), function(j) {
#       haversine_distance(
#         store$latitude, store$longitude,
#         region_competitors$latitude[j], region_competitors$longitude[j]
#       )
#     })
#     nearest_competitor_km <- min(competitor_distances)
#     avg_competitor_distance <- mean(competitor_distances)
#     competitors_within_5km <- sum(competitor_distances <= 5)
# 
#     # Customer coverage analysis
#     customer_distances <- sapply(1:nrow(region_customers), function(j) {
#       haversine_distance(
#         store$latitude, store$longitude,
#         region_customers$latitude[j], region_customers$longitude[j]
#       )
#     })
# 
#     # Customers within radius
#     customers_1km <- sum(customer_distances <= 1)
#     customers_3km <- sum(customer_distances <= 3)
#     customers_5km <- sum(customer_distances <= 5)
#     customers_10km <- sum(customer_distances <= 10)
# 
#     # Market potential (customers within 5km)
#     nearby_customers <- region_customers[customer_distances <= 5, ]
#     market_potential <- if (nrow(nearby_customers) > 0) {
#       sum(nearby_customers$annual_spend)
#     } else {
#       0
#     }
# 
#     # Average distance to customers
#     avg_customer_distance <- mean(customer_distances)
#     median_customer_distance <- median(customer_distances)
# 
#     # Spatial density (customers per km² within 10km radius)
#     area_10km <- pi * 10^2  # ~314 km²
#     customer_density <- customers_10km / area_10km
# 
#     # Competitive intensity score (0-1, higher = more competitive)
#     competitive_intensity <- min(1, competitors_within_5km / 10)
# 
#     data.frame(
#       store_id = store$store_id,
#       region_id = region_id,
#       region_name = store$region_name,
#       annual_revenue = store$annual_revenue,
#       nearest_competitor_km = nearest_competitor_km,
#       avg_competitor_distance = avg_competitor_distance,
#       competitors_within_5km = competitors_within_5km,
#       customers_1km = customers_1km,
#       customers_3km = customers_3km,
#       customers_5km = customers_5km,
#       customers_10km = customers_10km,
#       market_potential = market_potential,
#       avg_customer_distance = avg_customer_distance,
#       median_customer_distance = median_customer_distance,
#       customer_density = customer_density,
#       competitive_intensity = competitive_intensity,
#       stringsAsFactors = FALSE
#     )
#   })
# 
#   do.call(rbind, store_metrics)
# }

## ----local, eval=FALSE--------------------------------------------------------
# # Analyze 3 regions locally
# test_regions <- c(1, 2, 3)
# 
# cat(sprintf("Analyzing %d regions locally...\n", length(test_regions)))
# local_start <- Sys.time()
# 
# local_results <- lapply(test_regions, analyze_region,
#                        stores_data = stores,
#                        competitors_data = competitors,
#                        customers_data = customers)
# local_metrics <- do.call(rbind, local_results)
# 
# local_time <- as.numeric(difftime(Sys.time(), local_start, units = "secs"))
# 
# cat(sprintf("✓ Completed in %.2f seconds\n", local_time))
# cat(sprintf("  Processed %d stores\n", nrow(local_metrics)))
# cat(sprintf("  Estimated time for all %d regions: %.1f seconds\n",
#             nrow(regions), local_time * (nrow(regions) / length(test_regions))))

## ----cloud, eval=FALSE--------------------------------------------------------
# n_workers <- 20
# 
# cat(sprintf("Analyzing %d regions on %d workers...\n", nrow(regions), n_workers))
# 
# cloud_start <- Sys.time()
# 
# results <- starburst_map(
#   regions$region_id,
#   analyze_region,
#   stores_data = stores,
#   competitors_data = competitors,
#   customers_data = customers,
#   workers = n_workers,
#   cpu = 2,
#   memory = "4GB"
# )
# 
# cloud_time <- as.numeric(difftime(Sys.time(), cloud_start, units = "secs"))
# 
# cat(sprintf("\n✓ Completed in %.1f seconds\n", cloud_time))
# 
# # Combine results
# spatial_metrics <- do.call(rbind, results)

## ----analysis, eval=FALSE-----------------------------------------------------
# cat("\n=== Geospatial Analysis Results ===\n\n")
# cat(sprintf("Total stores analyzed: %d\n", nrow(spatial_metrics)))
# cat(sprintf("Regions covered: %d\n\n", length(unique(spatial_metrics$region_id))))
# 
# # Competition metrics
# cat("=== Competition Analysis ===\n")
# cat(sprintf("Average distance to nearest competitor: %.2f km\n",
#             mean(spatial_metrics$nearest_competitor_km)))
# cat(sprintf("Median distance to nearest competitor: %.2f km\n",
#             median(spatial_metrics$nearest_competitor_km)))
# cat(sprintf("Average competitors within 5km: %.1f\n",
#             mean(spatial_metrics$competitors_within_5km)))
# cat(sprintf("Stores with high competition (5+ competitors within 5km): %d (%.1f%%)\n\n",
#             sum(spatial_metrics$competitors_within_5km >= 5),
#             mean(spatial_metrics$competitors_within_5km >= 5) * 100))
# 
# # Customer coverage
# cat("=== Customer Coverage Analysis ===\n")
# cat(sprintf("Average customers within 5km: %.0f\n",
#             mean(spatial_metrics$customers_5km)))
# cat(sprintf("Average market potential (5km radius): $%.0f\n",
#             mean(spatial_metrics$market_potential)))
# cat(sprintf("Average customer density: %.1f customers/km²\n",
#             mean(spatial_metrics$customer_density)))
# cat(sprintf("Median distance to customers: %.2f km\n\n",
#             mean(spatial_metrics$median_customer_distance)))
# 
# # Store performance correlation
# cat("=== Performance Insights ===\n")
# correlation <- cor(spatial_metrics$annual_revenue,
#                    spatial_metrics$market_potential)
# cat(sprintf("Correlation (revenue vs market potential): %.3f\n", correlation))
# 
# # Identify opportunity stores
# opportunity_stores <- spatial_metrics[
#   spatial_metrics$market_potential > median(spatial_metrics$market_potential) &
#   spatial_metrics$competitors_within_5km < median(spatial_metrics$competitors_within_5km),
# ]
# cat(sprintf("\nHigh opportunity stores (low competition, high potential): %d\n",
#             nrow(opportunity_stores)))
# if (nrow(opportunity_stores) > 0) {
#   cat(sprintf("  Average market potential: $%.0f\n",
#               mean(opportunity_stores$market_potential)))
#   cat(sprintf("  Average competitors nearby: %.1f\n",
#               mean(opportunity_stores$competitors_within_5km)))
# }
# 
# # Identify challenged stores
# challenged_stores <- spatial_metrics[
#   spatial_metrics$competitive_intensity > 0.7 &
#   spatial_metrics$market_potential < median(spatial_metrics$market_potential),
# ]
# cat(sprintf("\nChallenged stores (high competition, low potential): %d\n",
#             nrow(challenged_stores)))
# if (nrow(challenged_stores) > 0) {
#   cat(sprintf("  Average market potential: $%.0f\n",
#               mean(challenged_stores$market_potential)))
#   cat(sprintf("  Average competitors nearby: %.1f\n",
#               mean(challenged_stores$competitors_within_5km)))
# }
# 
# # Top regions by market potential
# cat("\n=== Top 5 Regions by Market Potential ===\n")
# region_summary <- aggregate(market_potential ~ region_name,
#                            data = spatial_metrics, FUN = mean)
# region_summary <- region_summary[order(-region_summary$market_potential), ]
# for (i in 1:min(5, nrow(region_summary))) {
#   cat(sprintf("%d. %s: $%.0f\n", i,
#               region_summary$region_name[i],
#               region_summary$market_potential[i]))
# }

## ----zones, eval=FALSE--------------------------------------------------------
# optimize_delivery_zones <- function(region_id, stores_data, customers_data) {
#   region_stores <- stores_data[stores_data$region_id == region_id, ]
#   region_customers <- customers_data[customers_data$region_id == region_id, ]
# 
#   # Assign each customer to nearest store
#   customer_assignments <- lapply(1:nrow(region_customers), function(i) {
#     customer <- region_customers[i, ]
# 
#     distances <- sapply(1:nrow(region_stores), function(j) {
#       haversine_distance(
#         customer$latitude, customer$longitude,
#         region_stores$latitude[j], region_stores$longitude[j]
#       )
#     })
# 
#     nearest_store <- which.min(distances)
# 
#     list(
#       customer_id = customer$customer_id,
#       assigned_store = region_stores$store_id[nearest_store],
#       distance_km = distances[nearest_store],
#       annual_spend = customer$annual_spend
#     )
#   })
# 
#   # Aggregate by store
#   assignments_df <- do.call(rbind, lapply(customer_assignments, as.data.frame))
# 
#   store_zones <- aggregate(
#     cbind(customer_count = customer_id,
#           total_revenue = annual_spend,
#           avg_distance = distance_km) ~ assigned_store,
#     data = assignments_df,
#     FUN = function(x) if (is.numeric(x)) mean(x) else length(x)
#   )
# 
#   store_zones
# }
# 
# # Run optimization
# zone_results <- starburst_map(
#   regions$region_id,
#   optimize_delivery_zones,
#   stores_data = stores,
#   customers_data = customers,
#   workers = 20
# )

## ----eval=FALSE---------------------------------------------------------------
# system.file("examples/geospatial.R", package = "starburst")

## ----eval=FALSE---------------------------------------------------------------
# source(system.file("examples/geospatial.R", package = "starburst"))

