#!/usr/bin/env Rscript
# tools/check-docs.R — documentation-consistency guard.
#
# Fails (non-zero exit) when documentation drifts from the code, catching the
# classes of bug found in the 2026 site review:
#   1. Dead/renamed symbols (e.g. `future_starburst`) appearing anywhere in docs.
#   2. A vignette calling a `starburst_*` function that is not an exported symbol.
#   3. A `_pkgdown.yml` internal href pointing at a reference page that will 404.
#   4. A man page whose \usage{} default disagrees with its \item{} "(default: …)".
#
# Run from the package root:  Rscript tools/check-docs.R
# Dependency-light: base R only (+ the package's own DESCRIPTION/NAMESPACE).

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
# Resolve the package root. CI and normal use run from the repo root; also accept
# being run from tools/ by walking up one level to find DESCRIPTION.
pkg_root <- getwd()
if (!file.exists(file.path(pkg_root, "DESCRIPTION")) &&
    file.exists(file.path(pkg_root, "..", "DESCRIPTION"))) {
  pkg_root <- normalizePath(file.path(pkg_root, ".."))
}
if (!file.exists(file.path(pkg_root, "DESCRIPTION"))) {
  stop("check-docs.R: run from the package root (no DESCRIPTION found at ", pkg_root, ")")
}

problems <- character(0)
note <- function(...) problems[[length(problems) + 1]] <<- paste0(...)

read_lines_safe <- function(path) if (file.exists(path)) readLines(path, warn = FALSE) else character(0)

vignettes <- list.files(file.path(pkg_root, "vignettes"), pattern = "\\.Rmd$", full.names = TRUE)
readme    <- Filter(file.exists, file.path(pkg_root, c("README.md", "README.Rmd")))
r_files   <- list.files(file.path(pkg_root, "R"), pattern = "\\.R$", full.names = TRUE)
man_files <- list.files(file.path(pkg_root, "man"), pattern = "\\.Rd$", full.names = TRUE)
# Top-level developer docs that get the dead-symbol/terminology scan.
# NOTE: NEWS.md is intentionally excluded — a changelog must be able to mention
# renamed/removed names (e.g. "renamed max_cost_per_job -> max_hourly_cost").
top_docs  <- Filter(file.exists, file.path(pkg_root, c("ARCHITECTURE.md")))

# ---- 1. Dead / banned symbols -------------------------------------------------
# Symbols that no longer exist and must never reappear in code or docs.
banned <- c("future_starburst", "starburst_upload", "yourname/starburst",
            "yourusername/starburst", "starburst_setup(bucket",
            # removed/renamed args that must not reappear in docs or code:
            "detached = TRUE",   # starburst_session has no `detached` arg
            "max_cost_per_job",  # renamed to max_hourly_cost
            "readRDS(url(",      # base url() can't read s3:// — use an S3 client
            # obsolete engine/backend terminology (no auto-chunking; EC2 default):
            "Fargate workers",   # workers are EC2 by default; Fargate is opt-in
            "Fargate over EC2")  # stale design principle; EC2 is the default
scan_targets <- c(vignettes, readme, r_files, top_docs)
# Obsolete chunking language (regex): the engine creates one task per element and
# does NOT auto-chunk, so any "Created N chunks" output is fabricated.
banned_re <- c("Created\\s+[0-9]+\\s+chunks")
for (f in scan_targets) {
  lines <- read_lines_safe(f)
  for (re in banned_re) {
    for (h in grep(re, lines)) {
      note(sprintf("[obsolete-term] %s:%d matches /%s/ — the engine does not auto-chunk",
                   sub(paste0("^", pkg_root, "/?"), "", f), h, re))
    }
  }
  for (b in banned) {
    hits <- grep(b, lines, fixed = TRUE)
    for (h in hits) {
      note(sprintf("[dead-symbol] %s:%d references '%s'",
                   sub(paste0("^", pkg_root, "/?"), "", f), h, b))
    }
  }
}

# ---- 2. Vignettes must not call non-exported starburst_* functions ------------
ns <- read_lines_safe(file.path(pkg_root, "NAMESPACE"))
exported <- sub("^export\\(([^)]*)\\).*", "\\1", grep("^export\\(", ns, value = TRUE))
exported <- gsub("[`\"']", "", exported)
# starburst_* functions that are intentionally internal (allowed to be absent
# from NAMESPACE and must NOT be recommended in user-facing vignettes).
for (f in vignettes) {
  lines <- read_lines_safe(f)
  calls <- unique(unlist(regmatches(
    lines, gregexpr("\\bstarburst_[A-Za-z0-9_]*\\s*\\(", lines))))
  calls <- gsub("\\s*\\($", "", calls)
  for (fn in calls) {
    if (!(fn %in% exported)) {
      note(sprintf("[unexported-call] %s calls '%s()' which is not exported in NAMESPACE",
                   basename(f), fn))
    }
  }
}

# ---- 3. _pkgdown.yml internal reference hrefs must resolve --------------------
pk <- read_lines_safe(file.path(pkg_root, "_pkgdown.yml"))
href_lines <- grep("href:\\s*reference/", pk, value = TRUE)
for (hl in href_lines) {
  target <- sub(".*href:\\s*reference/([A-Za-z0-9_.-]+)\\.html.*", "\\1", hl)
  # pkgdown generates reference/<topic>.html from man/<topic>.Rd (or index.html).
  if (target != "index" &&
      !file.exists(file.path(pkg_root, "man", paste0(target, ".Rd")))) {
    note(sprintf("[pkgdown-404] _pkgdown.yml href 'reference/%s.html' has no man/%s.Rd (will 404)",
                 target, target))
  }
}

# ---- 4. man \usage{} defaults vs \item{} "(default: …)" prose -----------------
# Catches the starburst_session() class of bug (signature says EC2, prose says FARGATE).
extract_usage_defaults <- function(rd) {
  # Line-based parse of the \usage{ ... } block: collect "name = value" pairs.
  start <- grep("\\\\usage\\{", rd)
  if (!length(start)) return(list())
  # find the closing brace line at column 1 after the usage start
  rest <- rd[(start[1] + 1):length(rd)]
  end_rel <- which(grepl("^\\}", rest))[1]
  if (is.na(end_rel)) return(list())
  block <- rest[seq_len(end_rel - 1)]
  out <- list()
  for (ln in block) {
    if (!grepl("=", ln)) next
    nm  <- trimws(sub("=.*", "", ln))
    nm  <- gsub("[^A-Za-z0-9_.]", "", nm)
    if (!nchar(nm)) next
    val <- trimws(sub("^[^=]*=\\s*", "", ln))
    val <- sub(",\\s*$", "", val)          # strip trailing comma
    val <- gsub('"', "", val)
    out[[nm]] <- val
  }
  out
}
# Only compare when the prose gives an EXPLICIT literal default — a quoted string
# ("FARGATE"), a boolean (TRUE/FALSE), or a number. Descriptive prose like
# "(default: from config or us-east-1)" is legitimate and is intentionally NOT
# flagged. This targets exactly the starburst_session EC2-vs-FARGATE bug class:
# a concrete literal in the prose that contradicts the signature default.
for (f in man_files) {
  rd <- read_lines_safe(f)
  defs <- extract_usage_defaults(rd)
  if (!length(defs)) next
  item_lines <- grep("\\\\item\\{[A-Za-z0-9_.]+\\}\\{.*default:", rd, value = TRUE)
  for (il in item_lines) {
    nm <- sub("^.*\\\\item\\{([A-Za-z0-9_.]+)\\}\\{.*$", "\\1", il)
    if (is.null(defs[[nm]])) next
    # Only pull an EXPLICIT literal: quoted string, TRUE/FALSE, or number.
    m <- regmatches(il, regexpr('default:\\s*("[^"]*"|TRUE|FALSE|-?[0-9.]+)',
                                il, ignore.case = TRUE))
    if (!length(m)) next  # prose default is descriptive, not a literal -> skip
    pd  <- gsub('.*default:\\s*', "", m)
    pd  <- gsub('["]', "", trimws(pd))
    sig <- gsub('["]', "", trimws(defs[[nm]]))
    if (nchar(pd) && !identical(tolower(sig), tolower(pd))) {
      note(sprintf("[usage-vs-prose] %s: arg '%s' usage default '%s' != prose '(default: %s)'",
                   basename(f), nm, sig, pd))
    }
  }
}

# ---- 5. Naive big-count anti-pattern in examples -----------------------------
# `starburst_map(1:N, ...)` / `future_map(1:N, ...)` / `future_lapply(1:N, ...)`
# with a large N is the "thousands of tiny tasks" trap the guides warn against —
# and the furrr/future spellings are the same anti-pattern as the direct API (the
# plan is `starburst`). Flag them all in user-facing docs so examples model batching.
anti_marker <- "DON'T|Don't|Bad:|❌|anti-pattern|don't do this|Instead of|tiny task"
naive_re <- "(starburst_map|future_map|future_lapply)\\(\\s*1:([0-9]{4,})"
for (f in c(vignettes, readme)) {
  lines <- read_lines_safe(f)
  hits <- grep(naive_re, lines)
  for (h in hits) {
    m  <- regmatches(lines[h], regexec(naive_re, lines[h]))[[1]]
    fn <- m[2]
    n  <- as.integer(m[3])
    # Allow deliberately-labeled anti-pattern demos (a DON'T/Bad/"Instead of"
    # marker on this or the preceding three lines — the marker often sits just
    # above the ```{r} fence).
    ctx <- paste(lines[max(1, h - 3):h], collapse = " ")
    if (!is.na(n) && n >= 1000 && !grepl(anti_marker, ctx, ignore.case = TRUE)) {
      note(sprintf("[naive-big-count] %s:%d %s(1:%d, ...) — model batching or mark it as an anti-pattern (# DON'T / # Bad:)",
                   basename(f), h, fn, n))
    }
  }
}

# ---- 6. Fabricated performance claims in example vignettes -------------------
# The measured performance/workload-shapes guides are the single source of truth.
# Example vignettes must NOT present hand-written performance as if measured. Two
# tells, both flagged (only in example-*.Rmd; the measured guides are exempt):
#   (a) a "Typical output" label (implies measured) on a console block — use
#       "Illustrative output" instead;
#   (b) a fabricated speedup table row like `| staRburst | ... | 24.3x |`.
example_vigs <- Filter(function(p) grepl("/example-", p), vignettes)
for (f in example_vigs) {
  lines <- read_lines_safe(f)
  for (h in grep("Typical output", lines, ignore.case = TRUE)) {
    note(sprintf("[unmeasured-output] %s:%d 'Typical output' implies measured — label example console output 'Illustrative output'",
                 basename(f), h))
  }
  for (h in grep("\\|\\s*[0-9]+(\\.[0-9]+)?x\\s*\\|", lines)) {
    note(sprintf("[fabricated-speedup] %s:%d speedup table row — remove; point to vignette(\"performance\")/vignette(\"workload-shapes\") for measured numbers",
                 basename(f), h))
  }
}

# ---- Report -------------------------------------------------------------------
if (length(problems)) {
  cat("Documentation consistency check FAILED:\n")
  cat(paste0("  - ", unlist(problems), collapse = "\n"), "\n")
  quit(status = 1)
}
cat("Documentation consistency check passed.\n")
