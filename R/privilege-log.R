# Audit log for dst_db_privilege_management()
#
# Design
# ------
# * One append-only CSV file (`privilege_log.csv`) inside a log directory.
#   Every row is one GRANT/REVOKE statement that was *attempted*, including
#   failed ones, so the log answers "who did what, when, why, and did it work".
# * The person who ran the statement is a column (`performed_by`), not part of
#   the file location. The log is about the *schema* being governed; the actor
#   is an attribute of each event. This keeps one complete history per schema
#   even when several colleagues administer the same project schema.
# * The directory is resolved by `privilege_log_dir()`: explicit argument >
#   option `DSTutils.privilege_log_dir` > env var `DSTUTILS_PRIVILEGE_LOG_DIR`
#   > a per-user default (`tools::R_user_dir()`), which always works without
#   configuration. Point it at a shared project folder to give a team one log.
# * Writes are serialized with a lock directory (atomic `dir.create()`), so
#   several people can safely append to the same file on a shared drive.
# * Rows are written immediately after each statement, never batched, so a
#   crash in the middle of a batch cannot leave executed-but-unlogged grants.

privilege_log_columns <- c(
  "timestamp",
  "performed_by",
  "action",
  "privilege",
  "schema",
  "table_name",
  "grantee",
  "status",
  "note",
  "error",
  "database",
  "batch_id"
)

privilege_log_file_name <- "privilege_log.csv"

#' Resolve the directory holding the privilege log
#'
#' @param log_dir Explicit directory, or `NULL` to fall back to the option,
#'   the environment variable and finally the per-user default.
#' @return A single path (not yet created).
#' @noRd
privilege_log_dir <- function(log_dir = NULL) {
  candidates <- list(
    log_dir,
    getOption("DSTutils.privilege_log_dir"),
    Sys.getenv("DSTUTILS_PRIVILEGE_LOG_DIR", unset = ""),
    tools::R_user_dir("DSTutils", which = "data")
  )
  candidates <- purrr::keep(candidates, ~ !is.null(.x) && nzchar(.x))
  normalizePath(candidates[[1]], winslash = "/", mustWork = FALSE)
}

#' Create the log directory and fail early if it is not writable
#'
#' Checking before the app starts means a user can never execute a grant that
#' then cannot be logged because of a permissions problem.
#'
#' @return The path of the log file.
#' @noRd
privilege_log_prepare <- function(log_dir) {
  if (!dir.exists(log_dir)) {
    ok <- dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
    if (!ok) {
      stop(
        "Cannot create the privilege log directory:\n  ",
        log_dir,
        "\nChoose another location with the `log_dir` argument.",
        call. = FALSE
      )
    }
  }
  probe <- tempfile("write-test-", tmpdir = log_dir)
  writable <- tryCatch(
    {
      writeLines("", probe)
      TRUE
    },
    error = function(e) FALSE,
    warning = function(w) FALSE
  )
  unlink(probe)
  if (!writable) {
    stop(
      "The privilege log directory is not writable:\n  ",
      log_dir,
      "\nChoose another location with the `log_dir` argument.",
      call. = FALSE
    )
  }
  file.path(log_dir, privilege_log_file_name)
}

empty_privilege_log <- function() {
  cols <- purrr::map(
    stats::setNames(privilege_log_columns, privilege_log_columns),
    ~ character()
  )
  as.data.frame(cols, stringsAsFactors = FALSE)
}

#' Read the privilege log
#'
#' Tolerates a missing file (returns an empty log) and the column layout of
#' the first version of the app (`granted_by`, no `action`/`status`).
#'
#' @return A data frame with all columns as character, newest rows first.
#' @noRd
read_privilege_log <- function(log_file) {
  if (!file.exists(log_file) || file.size(log_file) == 0) {
    return(empty_privilege_log())
  }
  df <- utils::read.csv(
    log_file,
    colClasses = "character",
    na.strings = character(),
    check.names = FALSE,
    encoding = "UTF-8"
  )
  standardize_privilege_log(df)[
    order(df$timestamp, decreasing = TRUE),
    ,
    drop = FALSE
  ] |>
    `rownames<-`(NULL)
}

standardize_privilege_log <- function(df) {
  if ("granted_by" %in% names(df) && !"performed_by" %in% names(df)) {
    names(df)[names(df) == "granted_by"] <- "performed_by"
  }
  legacy_defaults <- c(action = "GRANT", status = "OK")
  for (col in privilege_log_columns) {
    if (!col %in% names(df)) {
      df[[col]] <- if (col %in% names(legacy_defaults)) {
        rep(legacy_defaults[[col]], nrow(df))
      } else {
        rep("", nrow(df))
      }
    }
  }
  df[privilege_log_columns]
}

#' Append rows to the privilege log
#'
#' @param log_file Path to the CSV file.
#' @param rows Data frame with (a subset of) `privilege_log_columns`.
#' @noRd
append_privilege_log <- function(log_file, rows) {
  rows <- standardize_privilege_log(as.data.frame(rows))
  rows[] <- purrr::map(rows, ~ clean_log_text(as.character(.x)))

  with_file_lock(log_file, {
    upgrade_privilege_log(log_file)
    new_file <- !file.exists(log_file) || file.size(log_file) == 0
    utils::write.table(
      rows,
      log_file,
      sep = ",",
      append = !new_file,
      col.names = new_file,
      row.names = FALSE,
      qmethod = "double",
      fileEncoding = "UTF-8"
    )
  })
  invisible(log_file)
}

# Rewrite a log with an outdated header into the current layout, keeping a
# backup copy of the original file next to it.
upgrade_privilege_log <- function(log_file) {
  if (!file.exists(log_file) || file.size(log_file) == 0) {
    return(invisible(FALSE))
  }
  header <- names(utils::read.csv(log_file, nrows = 1, check.names = FALSE))
  if (identical(header, privilege_log_columns)) {
    return(invisible(FALSE))
  }
  backup <- paste0(log_file, ".bak-", format(Sys.time(), "%Y%m%d-%H%M%S"))
  file.copy(log_file, backup)
  old <- utils::read.csv(log_file, colClasses = "character", check.names = FALSE)
  utils::write.table(
    standardize_privilege_log(old),
    log_file,
    sep = ",",
    row.names = FALSE,
    qmethod = "double",
    fileEncoding = "UTF-8"
  )
  invisible(TRUE)
}

clean_log_text <- function(x) {
  x[is.na(x)] <- ""
  trimws(gsub("[\r\n\t]+", " ", x))
}

#' Run code while holding an exclusive lock on a file
#'
#' Uses `dir.create()`, which is atomic on local and network file systems.
#' A lock older than `stale_after` seconds is assumed to be left behind by a
#' crashed session and is removed.
#' @noRd
with_file_lock <- function(path, code, timeout = 15, stale_after = 120) {
  lock <- paste0(path, ".lock")
  deadline <- Sys.time() + timeout
  repeat {
    if (dir.create(lock, showWarnings = FALSE)) {
      break
    }
    age <- difftime(Sys.time(), file.mtime(lock), units = "secs")
    if (!is.na(age) && age > stale_after) {
      unlink(lock, recursive = TRUE)
      next
    }
    if (Sys.time() > deadline) {
      stop(
        "Could not lock the privilege log (another user is writing to it?):\n  ",
        path,
        call. = FALSE
      )
    }
    Sys.sleep(0.1)
  }
  on.exit(unlink(lock, recursive = TRUE), add = TRUE)
  force(code)
}

#' Who is performing the action
#'
#' On a Shiny server `session$user` identifies the logged-in person; when the
#' app runs locally from RStudio it is `NULL` and the OS login is used.
#' @noRd
current_user <- function(session = NULL) {
  user <- if (!is.null(session)) session$user else NULL
  if (is.null(user) || !nzchar(user)) {
    user <- Sys.getenv("USERNAME", unset = Sys.getenv("USER", unset = ""))
  }
  if (!nzchar(user)) {
    user <- Sys.info()[["user"]]
  }
  toupper(user)
}
