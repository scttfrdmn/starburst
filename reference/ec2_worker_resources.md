# Size an EC2 worker task to fit its instance

ECS can only place a task whose cpu/memory fit on the instance; a task
that asks for more (e.g. the default 8GB on an 8 GiB c7g.xlarge, after
the ECS agent's share) stays PROVISIONING forever. Every EC2 entry point
must size tasks with this helper.

## Usage

``` r
ec2_worker_resources(instance_type)
```

## Arguments

- instance_type:

  EC2 instance type

## Value

list(cpu = vCPUs, memory = "\<n\>GB")
