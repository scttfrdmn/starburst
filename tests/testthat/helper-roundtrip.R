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
# the worker synchronously, as a container started by ECS would.
fake_ecs <- function(worker, cluster_name) {
  calls <- new.env()
  calls$n <- 0
  list(
    calls = calls,
    run_task = function(...) {
      p <- list(...)
      calls$n <- calls$n + 1
      calls$last <- p
      if (!identical(p$cluster, cluster_name)) {
        stop(sprintf("ClusterNotFoundException: %s", deparse(p$cluster)))
      }
      vpc <- p$networkConfiguration$awsvpcConfiguration
      if (length(vpc$subnets) == 0) stop("InvalidParameterException: subnets required")
      if (!is.null(p$capacityProviderStrategy) && !is.null(vpc$assignPublicIp)) {
        stop("InvalidParameterException (HTTP 400). Assign public IP is not supported for this launch type.")
      }
      env <- p$overrides$containerOverrides[[1]]$environment
      vars <- stats::setNames(vapply(env, `[[`, "", "value"),
                              vapply(env, `[[`, "", "name"))
      run_worker(worker, vars[["TASK_ID"]], vars[["S3_BUCKET"]], vars[["AWS_DEFAULT_REGION"]])
      list(tasks = list(list(taskArn = sprintf("arn:aws:ecs:task/%s", vars[["TASK_ID"]]))),
           failures = list())
    }
  )
}

# Wire the fakes into the package for the calling test.
local_fake_aws <- function(env = parent.frame(), instance_type = "c7g.xlarge") {
  s3 <- fake_s3()
  worker <- load_worker(s3)
  cluster_name <- "starburst-cluster"
  ecs <- fake_ecs(worker, cluster_name)
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
    start_warm_pool = function(backend, capacity, ...) {
      if (!is.character(backend$cluster_name) || !nzchar(backend$cluster_name)) {
        stop("start_warm_pool: backend has no cluster_name (would poll the default cluster)")
      }
      invisible(NULL)
    },
    .env = env
  )
  old_opts <- options(starburst.cleanup_handlers = NULL,
                      starburst.current_backend = NULL,
                      starburst.current_cluster_id = NULL)
  withr::defer(options(old_opts), envir = env)
  list(s3 = s3, ecs = ecs, worker = worker)
}
