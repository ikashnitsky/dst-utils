#' Interactive DB privilege management
#'
#' Opens a Shiny app to grant and revoke privileges on the tables of a
#' project schema at DST, with an audit log of every action.
#'
#' The app connects with `DSTdb::get_conn(database, proxy = "[<schema>]")`,
#' i.e. as the project schema, and only manages privileges on that schema's
#' own tables and views. Every statement is shown for review before it runs,
#' and every attempt (successful or not) is written to the log together with
#' the person who ran it and the required reason.
#'
#' @section The log:
#' The log is one CSV file, `privilege_log.csv`, in `log_dir`. It is keyed by
#' *what is governed* (database and schema columns) and records *who acted*
#' (`performed_by`, taken from the login, not typed in). Where it lives is
#' resolved in this order:
#'
#' 1. the `log_dir` argument;
#' 2. `options(DSTutils.privilege_log_dir = ...)`, e.g. in `.Rprofile`;
#' 3. the environment variable `DSTUTILS_PRIVILEGE_LOG_DIR`;
#' 4. a per-user folder, `tools::R_user_dir("DSTutils", "data")`.
#'
#' The per-user default always works but is only visible to you. When several
#' people administer the same project schema, point all of them at one shared
#' folder (for example in the project's area on the shared drive), so the log
#' holds the complete history of that schema. Concurrent writes are
#' serialized with a lock file. The "Current access" tab compares the log
#' with what the database actually reports, which reveals privileges granted
#' or revoked outside the app.
#'
#' @param dry_run If `TRUE`, no database is contacted. A simulated schema
#'   with a few tables and privileges is used, and actions are logged to a
#'   sandbox log in [tempdir()], unless `log_dir` is given explicitly. Useful
#'   for trying the app, training and development outside the secure
#'   environment.
#' @param database Database name pre-filled in the app.
#' @param schema Project schema pre-filled in the app, e.g. `"D221911"`.
#' @param log_dir Directory for the log file; see the section 'The log'.
#' @param launch.browser Passed to [shiny::runApp()].
#'
#' @return Called for its side effect of running the app; returns the value
#'   of [shiny::runApp()] invisibly.
#'
#' @examples
#' if (interactive()) {
#'   # Try it anywhere, no database needed
#'   dst_db_privilege_management(dry_run = TRUE)
#'
#'   # In the secure environment, with a log shared by the project team
#'   dst_db_privilege_management(
#'     schema = "D221911",
#'     log_dir = "path/to/project/folder/privilege-log"
#'   )
#' }
#'
#' @export
dst_db_privilege_management <- function(
  dry_run = FALSE,
  database = "STATPROD",
  schema = "",
  log_dir = NULL,
  launch.browser = getOption("shiny.launch.browser", interactive())
) {
  stopifnot(is.logical(dry_run), length(dry_run) == 1, !is.na(dry_run))

  if (!dry_run && !requireNamespace("DSTdb", quietly = TRUE)) {
    stop(
      "Package 'DSTdb' is required to connect to the database.\n",
      "Use `dst_db_privilege_management(dry_run = TRUE)` to try the app without one.",
      call. = FALSE
    )
  }

  if (dry_run && is.null(log_dir)) {
    log_dir <- file.path(tempdir(), "DSTutils-dry-run")
    if (!nzchar(schema)) schema <- "D123456"
  } else {
    log_dir <- privilege_log_dir(log_dir)
  }
  log_file <- privilege_log_prepare(log_dir)
  message("Privilege log: ", log_file)

  app <- privilege_app(
    dry_run = dry_run,
    database = database,
    schema = schema,
    log_file = log_file
  )
  invisible(shiny::runApp(app, launch.browser = launch.browser))
}
