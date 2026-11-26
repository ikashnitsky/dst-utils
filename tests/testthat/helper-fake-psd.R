#' Replace the database wrappers of convert_person_id() with an in-memory fake
#'
#' Records every statement and keeps track of which tables exist, so tests can
#' check what is sent to Oracle and that work tables are cleaned up. DB_PSD
#' tables are in `db$tables`; tables in other databases in `db$remote` as
#' "DATABASE:NAME".
#'
#' @param run_id Run id the fake procedure reports (`v_koerselsid`).
#' @param leftover Tables that exist in DB_PSD before the call.
#' @param stale Of those, run tables older than a day.
#' @param proc_error If not NULL, the procedure call fails with this message.
#' @param create_output Whether the procedure creates its output table.
#' @param output The procedure's output table.
#' @param remote Tables that exist in other databases ("DATABASE:NAME").
#' @param source_columns What `all_tab_columns` returns for the source table.
#' @param source_rows What reading the distinct ids from a source returns.
#' @param remote_create Whether the user may create tables in other databases.
#' @param fail_write_at Fail a write to another database once it holds this many rows.
#' @noRd
local_fake_psd <- function(
  run_id = 4711,
  leftover = character(),
  stale = character(),
  proc_error = NULL,
  create_output = TRUE,
  output = data.frame(PNR = "0101011234", PERSON_ID = 1),
  remote = character(),
  source_columns = data.frame(COLUMN_NAME = "PNR", DATA_TYPE = "VARCHAR2"),
  source_rows = data.frame(PNR = c("0101011234", "0202024321")),
  remote_create = TRUE,
  fail_write_at = NULL,
  env = parent.frame()
) {
  db <- new.env()
  db$tables <- leftover
  db$remote <- remote
  db$statements <- character()
  db$remote_statements <- character()
  db$plsql <- character()
  db$uploads <- list()
  db$remote_writes <- list()
  db$connects <- 0
  db$disconnects <- 0
  db$remote_connects <- character()
  db$remote_disconnects <- 0
  db$run <- NULL

  prefixes <- vapply(bef_procedures, `[[`, "", "prefix")
  is_psd <- function(conn) conn$db == "DB_PSD"
  remote_key <- function(conn, name) paste0(conn$db, ":", name)
  log_sql <- function(conn, sql) {
    if (is_psd(conn)) {
      db$statements <- c(db$statements, sql)
    } else {
      db$remote_statements <- c(db$remote_statements, sql)
    }
  }
  add_table <- function(conn, name) {
    if (is_psd(conn)) {
      db$tables <- c(db$tables, name)
    } else {
      db$remote <- c(db$remote, remote_key(conn, name))
    }
  }
  drop_table <- function(conn, name) {
    if (is_psd(conn)) {
      db$tables <- setdiff(db$tables, name)
    } else {
      db$remote <- setdiff(db$remote, remote_key(conn, name))
    }
  }

  testthat::local_mocked_bindings(
    psd_connect = function() {
      db$connects <- db$connects + 1
      structure(list(db = "DB_PSD", proxy = NULL), class = "fake_db")
    },
    db_connect = function(database, proxy = NULL) {
      db$remote_connects <- c(
        db$remote_connects,
        paste0(database, if (!is.null(proxy)) proxy)
      )
      structure(list(db = database, proxy = proxy), class = "fake_db")
    },
    db_disconnect = function(conn) {
      if (is_psd(conn)) {
        db$disconnects <- db$disconnects + 1
      } else {
        db$remote_disconnects <- db$remote_disconnects + 1
      }
      TRUE
    },
    table_exists = function(conn, table_name, schema_name) {
      if (is_psd(conn)) {
        table_name %in% db$tables
      } else {
        remote_key(conn, table_name) %in% db$remote
      }
    },
    db_query = function(conn, sql) {
      log_sql(conn, sql)
      if (grepl("FROM DUAL", sql)) {
        user <- if (is.null(conn$proxy)) "IKX" else gsub("\\[|\\]", "", conn$proxy)
        return(data.frame(SCHEMA_NAME = user))
      }
      if (grepl("session_privs", sql)) {
        ok <- is_psd(conn) || remote_create
        return(data.frame(PRIVILEGE = rep("CREATE TABLE", ok)))
      }
      if (grepl("all_tab_privs", sql)) {
        return(data.frame(PRIVILEGE = "X"))
      }
      if (grepl("all_tab_columns", sql)) {
        return(source_columns)
      }
      if (grepl("user_objects", sql)) {
        return(data.frame(OBJECT_NAME = intersect(stale, db$tables)))
      }
      if (grepl("bef_leverance_time", sql)) {
        return(data.frame(TID = "2022-01-16 18:00:00.000000"))
      }
      if (grepl("from PSDMYTEMP_", sql)) {
        return(db$run)
      }
      if (grepl("^select distinct ", sql)) {
        return(source_rows)
      }
      if (grepl("^select \\* from ", sql)) {
        return(output)
      }
      stop("fake db: unexpected query ", sql)
    },
    db_execute = function(conn, sql) {
      log_sql(conn, sql)
      if (grepl("^alter table", sql)) {
        from <- sub("^alter table (\\w+) rename to (\\w+)$", "\\1", sql)
        to <- sub("^alter table (\\w+) rename to (\\w+)$", "\\2", sql)
        drop_table(conn, from)
        add_table(conn, to)
        return(invisible(TRUE))
      }
      name <- toupper(sub("^(create|drop) table (\\w+).*$", "\\2", sql))
      if (startsWith(sql, "create")) {
        add_table(conn, name)
      } else {
        drop_table(conn, name)
      }
      invisible(TRUE)
    },
    db_write_table = function(conn, name, data, append = FALSE) {
      if (is_psd(conn)) {
        db$tables <- c(db$tables, name)
        db$uploads[[name]] <- data
        return(TRUE)
      }
      key <- remote_key(conn, name)
      db$remote_writes[[key]] <- rbind(db$remote_writes[[key]], data)
      if (!append) {
        db$remote <- c(db$remote, key)
      }
      if (!is.null(fail_write_at) && nrow(db$remote_writes[[key]]) >= fail_write_at) {
        stop("ORA-01653: unable to extend table")
      }
      TRUE
    },
    db_read_chunked = function(conn, sql, chunk_size, write_chunk) {
      log_sql(conn, sql)
      starts <- if (nrow(output) == 0) 1 else seq(1, nrow(output), by = chunk_size)
      for (i in seq_along(starts)) {
        rows <- seq(starts[i], min(starts[i] + chunk_size - 1, nrow(output)))
        write_chunk(output[rows[rows > 0], , drop = FALSE], first = i == 1)
      }
      nrow(output)
    },
    psd_run_plsql = function(conn, plsql) {
      db$plsql <- c(db$plsql, plsql)
      if (!is.null(proc_error)) {
        stop(proc_error)
      }
      run_table <- sub("(?s).*insert into (\\w+) values.*", "\\1", plsql, perl = TRUE)
      if (!run_table %in% db$tables) {
        stop("fake db: ORA-00942: table or view ", run_table, " does not exist")
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
