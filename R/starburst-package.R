#' @keywords internal
#' @importFrom stats runif
#' @importFrom utils capture.output
"_PACKAGE"

# The following block is used by usethis to automatically manage
# roxygen namespace tags. Modify with care!
## usethis namespace: start
## usethis namespace: end
NULL

# Package-level environment for task registry
.starburst_task_registry <- NULL

.onLoad <- function(libname, pkgname) {
  .starburst_task_registry <<- new.env(parent = emptyenv())
}
