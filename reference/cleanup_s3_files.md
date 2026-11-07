# Cleanup S3 files

Deletes the task payloads and results of the tasks this backend
launched. (Task objects are stored as `tasks/<task_id>.qs` and
`results/<task_id>.qs`; the old per-cluster prefix matched nothing, so
they were never deleted.)

## Usage

``` r
cleanup_s3_files(plan)
```
