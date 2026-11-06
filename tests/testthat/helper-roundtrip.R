# Offline round-trip harness: client -> S3 -> real worker.R -> S3 -> client.
#
# The live future-backend paths were broken from 0.3.0 to 0.3.10 because every
# test mocked the seam between the client and the worker (#63-#65). These fakes
# keep that seam real: tasks are serialized by the client code, executed by the
# shipped inst/templates/worker.R, and read back by the client code. The fake
# ECS/S3 enforce the AWS rules that the broken code violated.

# In-memory S3 with paws-like methods and paws-like failures.
fake_s3 <- function() {
  store <- new.env()
  check_key <- function(Key) {
    # A NULL/character(0) key is what produced SignatureDoesNotMatch (#63)
    if (!is.character(Key) || length(Key) != 1 || !nzchar(Key)) {
      stop("SignatureDoesNotMatch (HTTP 403). Invalid S3 key: ", deparse(Key))
    }
  }
  missing_key <- function(Key) stop(sprintf("NotFound (HTTP 404). %s", Key))
  list(
    store = store,
    put_object = function(Bucket, Key, Body, ...) {
      check_key(Key)
      # paws uploads a file path's contents; raw vectors as-is
      if (is.character(Body) && length(Body) == 1 && file.exists(Body)) {
        Body <- readBin(Body, "raw", file.info(Body)$size)
      }
      assign(Key, Body, envir = store)
      list(ETag = digest::digest(Body))
    },
    head_object = function(Bucket, Key, ...) {
      check_key(Key)
      if (!exists(Key, envir = store, inherits = FALSE)) missing_key(Key)
      list(ContentLength = length(get(Key, envir = store)))
    },
    get_object = function(Bucket, Key, ...) {
      check_key(Key)
      if (!exists(Key, envir = store, inherits = FALSE)) missing_key(Key)
      body <- get(Key, envir = store)
      list(Body = body, ETag = digest::digest(body))
    },
    delete_objects = function(Bucket, Delete, ...) {
      for (o in Delete$Objects) {
        if (exists(o$Key, envir = store, inherits = FALSE)) rm(list = o$Key, envir = store)
      }
      invisible(list())
    },
    list_objects_v2 = function(Bucket, Prefix = "", ...) {
      keys <- ls(store)
      keys <- keys[startsWith(keys, Prefix)]
      list(Contents = lapply(keys, function(k) list(Key = k)))
    },
    download_file = function(Bucket, Key, Filename, ...) {
      check_key(Key)
      if (!exists(Key, envir = store, inherits = FALSE)) missing_key(Key)
      writeBin(get(Key, envir = store), Filename)
      invisible(list())
    }
  )
}

# The shipped worker script, loaded without running main(), talking to `s3`.
load_worker <- function(s3) {
  worker <- system.file("templates", "worker.R", package = "starburst")
  if (!nzchar(worker)) testthat::skip("worker template not installed")
  env <- new.env(parent = globalenv())
  src <- readLines(worker, warn = FALSE)
  eval(parse(text = src[!grepl("^main\\(\\)\\s*$", src)]), envir = env)
  env$make_s3_client <- function(region, ...) s3
  # quit() is called inside the worker's tryCatch(error = ); a restart
  # leaves without being caught as an error
  env$quit <- function(status = 0, ...) invokeRestart("worker_quit", status)
  env$message <- function(...) invisible(NULL)
  env
}

run_worker <- function(worker, task_id, bucket, region) {
  old <- Sys.getenv(c("TASK_ID", "S3_BUCKET", "AWS_DEFAULT_REGION"), unset = NA)
  on.exit({
    for (n in names(old)) {
      if (is.na(old[[n]])) Sys.unsetenv(n) else do.call(Sys.setenv, as.list(old[n]))
    }
  })
  Sys.setenv(TASK_ID = task_id, S3_BUCKET = bucket, AWS_DEFAULT_REGION = region)
  withRestarts(worker$main(), worker_quit = function(status) status)
}

# Fake ECS whose run_task enforces the parameters EC2 accepts and then runs
# the worker synchronously, as a container started by ECS would. Set
# `ecs$calls$mode` to "die" (container killed before uploading, e.g. OOM) or
# "hang" (never finishes) to simulate broken workers.
fake_ecs <- function(worker, cluster_name) {
  calls <- new.env()
  calls$n <- 0
  calls$mode <- "run"
  calls$stopped <- character(0)
  task_db <- new.env()
  check_cluster <- function(cluster) {
    if (!identical(cluster, cluster_name)) {
      stop(sprintf("ClusterNotFoundException: %s", deparse(cluster)))
    }
  }
  list(
    calls = calls,
    tasks = task_db,
    run_task = function(...) {
      p <- list(...)
      calls$n <- calls$n + 1
      calls$last <- p
      check_cluster(p$cluster)
      vpc <- p$networkConfiguration$awsvpcConfiguration
      if (length(vpc$subnets) == 0) stop("InvalidParameterException: subnets required")
      if (!is.null(p$capacityProviderStrategy) && !is.null(vpc$assignPublicIp)) {
        stop("InvalidParameterException (HTTP 400). Assign public IP is not supported for this launch type.")
      }
      env <- p$overrides$containerOverrides[[1]]$environment
      vars <- stats::setNames(vapply(env, `[[`, "", "value"),
                              vapply(env, `[[`, "", "name"))
      arn <- sprintf("arn:aws:ecs:task/%s", vars[["TASK_ID"]])
      if (calls$mode == "die") {
        assign(arn, list(taskArn = arn, lastStatus = "STOPPED",
                         stoppedReason = "Essential container in task exited",
                         containers = list(list(exitCode = 137L, reason = "OutOfMemoryError"))),
               envir = task_db)
      } else if (calls$mode == "hang") {
        assign(arn, list(taskArn = arn, lastStatus = "RUNNING", containers = list(list())),
               envir = task_db)
      } else {
        run_worker(worker, vars[["TASK_ID"]], vars[["S3_BUCKET"]], vars[["AWS_DEFAULT_REGION"]])
        assign(arn, list(taskArn = arn, lastStatus = "STOPPED",
                         stoppedReason = "Essential container in task exited",
                         containers = list(list(exitCode = 0L))),
               envir = task_db)
      }
      list(tasks = list(list(taskArn = arn)), failures = list())
    },
    describe_tasks = function(cluster, tasks = list(), ...) {
      check_cluster(cluster)
      arns <- unlist(tasks)
      known <- arns[vapply(arns, exists, logical(1), envir = task_db, inherits = FALSE)]
      list(
        tasks = lapply(known, get, envir = task_db),
        failures = lapply(setdiff(arns, known), function(a) list(arn = a, reason = "MISSING"))
      )
    },
    list_tasks = function(cluster, desiredStatus = "RUNNING", ...) {
      check_cluster(cluster)
      all <- mget(ls(task_db), envir = task_db)
      list(taskArns = unname(unlist(lapply(all, function(t)
        if (identical(t$lastStatus, desiredStatus)) t$taskArn))))
    },
    stop_task = function(cluster, task, ...) {
      check_cluster(cluster)
      calls$stopped <- c(calls$stopped, task)
      if (exists(task, envir = task_db, inherits = FALSE)) {
        t <- get(task, envir = task_db)
        t$lastStatus <- "STOPPED"
        t$stoppedReason <- "Task stopped by user"
        assign(task, t, envir = task_db)
      }
      invisible(list())
    },
    list_container_instances = function(cluster, ...) {
      check_cluster(cluster)
      list(containerInstanceArns = as.list(sprintf("ci-%d", seq_len(100))))
    }
  )
}

# Fake Auto Scaling group with the constraints the pool code must respect:
# DesiredCapacity within [MinSize, MaxSize], deleting a missing scheduled
# action is an error.
fake_autoscaling <- function() {
  asg <- new.env()
  asg$min <- 0L
  asg$desired <- 0L
  asg$max <- 100L
  asg$actions <- list()
  list(
    asg = asg,
    describe_auto_scaling_groups = function(...) {
      list(AutoScalingGroups = list(list(
        AutoScalingGroupName = "starburst-asg",
        MinSize = asg$min, MaxSize = asg$max, DesiredCapacity = asg$desired,
        Instances = lapply(seq_len(asg$desired), function(i) list(LifecycleState = "InService"))
      )))
    },
    update_auto_scaling_group = function(AutoScalingGroupName, MinSize = asg$min,
                                         DesiredCapacity = asg$desired, ...) {
      if (DesiredCapacity < MinSize || DesiredCapacity > asg$max) {
        stop(sprintf("ValidationError: Desired capacity:%d must be between the specified min size:%d and max size:%d",
                     DesiredCapacity, MinSize, asg$max))
      }
      asg$min <- as.integer(MinSize)
      asg$desired <- as.integer(DesiredCapacity)
      invisible(list())
    },
    set_desired_capacity = function(...) {
      stop("AccessDenied: autoscaling:SetDesiredCapacity is not in the CI role")
    },
    put_scheduled_update_group_action = function(AutoScalingGroupName, ScheduledActionName,
                                                 StartTime, MinSize = NULL, ...) {
      asg$actions[[ScheduledActionName]] <- list(start = StartTime, min = MinSize)
      invisible(list())
    },
    delete_scheduled_action = function(AutoScalingGroupName, ScheduledActionName, ...) {
      if (is.null(asg$actions[[ScheduledActionName]])) {
        stop("ValidationError: Scheduled action name not found")
      }
      asg$actions[[ScheduledActionName]] <- NULL
      invisible(list())
    }
  )
}

# Wire the fakes into the package for the calling test.
local_fake_aws <- function(env = parent.frame(), instance_type = "c7g.xlarge") {
  s3 <- fake_s3()
  worker <- load_worker(s3)
  cluster_name <- "starburst-cluster"
  ecs <- fake_ecs(worker, cluster_name)
  autoscaling <- fake_autoscaling()
  config <- list(
    region = "us-east-1", bucket = "starburst-test", cluster_name = cluster_name,
    subnets = list("subnet-1"), security_groups = list("sg-1"),
    aws_account_id = "123456789012"
  )
  testthat::local_mocked_bindings(
    get_starburst_config = function(...) config,
    check_aws_credentials = function(...) TRUE,
    ensure_environment = function(...) list(cluster = "starburst-cluster", hash = "h",
                                            image_uri = "img:h"),
    estimate_cost = function(...) list(hourly_rate = 0.1, per_hour = 0.1,
                                       total_estimate = 0.1),
    get_s3_client = function(...) s3,
    get_ecs_client = function(...) ecs,
    get_autoscaling_client = function(...) autoscaling,
    get_vpc_config = function(...) list(subnets = list("subnet-default"),
                                        security_groups = list("sg-default")),
    store_task_arn = function(...) invisible(NULL),
    # The task must fit on the instance, or ECS leaves it PROVISIONING forever
    get_or_create_task_definition = function(backend, ...) {
      specs <- get_instance_specs(backend$instance_type)
      if (identical(backend$launch_type, "EC2") &&
          (parse_memory(backend$memory) > specs$memory_gb - 0.5 ||
           backend$cpu > specs$vcpus)) {
        stop(sprintf("task (%s vCPU, %s) cannot be placed on %s; it would stay PROVISIONING",
                     backend$cpu, backend$memory, backend$instance_type))
      }
      "arn:aws:ecs:task-definition/starburst-worker:1"
    },
    .env = env
  )
  # Leave any starburst plan while the fakes are still in place (runs before
  # the mocks are restored), so its stopWorkers() cleanup never hits real AWS
  old_plan <- future::plan()
  withr::defer(future::plan(old_plan), envir = env)
  old_opts <- options(starburst.current_backend = NULL,
                      starburst.current_cluster_id = NULL,
                      starburst.task_check_interval = 0)
  withr::defer(options(old_opts), envir = env)
  list(s3 = s3, ecs = ecs, autoscaling = autoscaling, worker = worker)
}

# Fail, instead of hanging the whole check, if a future never resolves
local_time_limit <- function(seconds, env = parent.frame()) {
  setTimeLimit(elapsed = seconds, transient = TRUE)
  withr::defer(setTimeLimit(elapsed = Inf), envir = env)
}
