#!/bin/bash

# Replace specific sapply patterns with vapply

# R/ec2-pool.R:365 - checking LifecycleState
sed -i '' 's/sum(sapply(asg\$Instances, function(i) {$/sum(vapply(asg$Instances, function(i) {/g' R/ec2-pool.R
sed -i '' 's/i\$LifecycleState == "InService"$/i$LifecycleState == "InService"/' R/ec2-pool.R
sed -i '' 's/}))$/}, FUN.VALUE = logical(1)))/g' R/ec2-pool.R

# R/session-api.R - checking task statuses
sed -i '' 's/all(sapply(statuses, function(s) {$/all(vapply(statuses, function(s) {/g' R/session-api.R
sed -i '' 's/s\$state == "completed" || s\$state == "failed"$/s$state == "completed" || s$state == "failed"/' R/session-api.R

# Replace simple one-liners
sed -i '' 's/sapply(result\$Contents, function(x) x\$Key)/vapply(result$Contents, function(x) x$Key, FUN.VALUE = character(1))/g' R/session-api.R
sed -i '' 's/sapply(tasks_result\$Contents, function(obj) {$/vapply(tasks_result$Contents, function(obj) {/g' R/session-api.R
sed -i '' 's/strsplit(obj\$Key, "\/")\\[\\[1\\]\\]\\[2\\]$/strsplit(obj$Key, "\\/")[[1]][2]/' R/session-api.R

# R/utils.R
sed -i '' 's/return(sapply(subnets\$Subnets, function(s) s\$SubnetId))/return(vapply(subnets$Subnets, function(s) s$SubnetId, FUN.VALUE = character(1)))/g' R/utils.R
sed -i '' 's/return(sapply(all_subnets\$Subnets, function(s) s\$SubnetId))/return(vapply(all_subnets$Subnets, function(s) s$SubnetId, FUN.VALUE = character(1)))/g' R/utils.R
