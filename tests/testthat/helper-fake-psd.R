#' Replace the DB_PSD wrappers of convert_person_id() with an in-memory fake
#'
#' Records every statement and keeps track of which tables exist, so tests can
#' check what is sent to Oracle and that work tables are cleaned up.
#'
#' @param run_id Run id the fake procedure reports (`v_koerselsid`).
#' @param leftover Tables that exist before the call (an interrupted run).
#' @param proc_error If not NULL, the procedure call fails with this message.
#' @param create_output Whether the procedure creates its output table.
#' @noRd
local_fake_psd <- function(
  run_id = 4711,
  leftover = character(),
  proc_error = NULL,
  create_output = TRUE,
  env = parent.frame()
) {
  db <- new.env()
  db$tables <- leftover
  db$statements <- character()
  db$plsql <- character()
  db$uploads <- list()
  db$connects <- 0
  db$disconnects <- 0
  db$run <- NULL

  prefixes <- vapply(bef_procedures, `[[`, "", "prefix")

  testthat::local_mocked_bindings(
    psd_connect = function() {
      db$connects <- db$connects + 1
      structure(list(), class = "fake_psd")
    },
    psd_disconnect = function(conn) {
      db$disconnects <- db$disconnects + 1
      TRUE
    },
    table_exists = function(conn, table_name, schema_name) {
      table_name %in% db$tables
    },
    psd_query = function(conn, sql) {
      db$statements <- c(db$statements, sql)
      if (grepl("FROM DUAL", sql)) {
        return(data.frame(SCHEMA_NAME = "IKX"))
      }
      if (grepl("session_privs|all_tab_privs", sql)) {
        return(data.frame(PRIVILEGE = "X"))
      }
      if (grepl("bef_leverance_time", sql)) {
        return(data.frame(TID = as.POSIXct("2022-01-16 18:00:00", tz = "UTC")))
      }
      if (grepl("from psdmytemp", sql)) {
        return(db$run)
      }
      if (grepl("^select \\* from ", sql)) {
        return(data.frame(PNR = "0101011234", PERSON_ID = 1))
      }
      stop("fake psd: unexpected query ", sql)
    },
    psd_execute = function(conn, sql) {
      db$statements <- c(db$statements, sql)
      name <- toupper(sub("^(create|drop) table (\\w+).*$", "\\2", sql))
      if (startsWith(sql, "create")) {
        db$tables <- c(db$tables, name)
      } else {
        db$tables <- setdiff(db$tables, name)
      }
      invisible(TRUE)
    },
    psd_write_table = function(conn, name, data) {
      db$tables <- c(db$tables, name)
      db$uploads[[name]] <- data
      TRUE
    },
    psd_run_plsql = function(conn, plsql) {
      db$plsql <- c(db$plsql, plsql)
      if (!is.null(proc_error)) {
        stop(proc_error)
      }
      proc <- sub("(?s).*\\.(BEF_[A-Z_]+)\\(.*", "\\1", plsql, perl = TRUE)
      if (create_output) {
        db$tables <- c(db$tables, paste0(prefixes[[proc]], format_run_id(run_id)))
      }
      db$run <- data.frame(RESULTAT = "Koersel OK", KOERSELSID = run_id)
      TRUE
    },
    .env = env
  )
  db
}
