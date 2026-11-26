# ..........................................................
# 2026-03-25 -- misc
# keep track of privileges                -----------
# Ilya Kashnitsky, ilya.kashnitsky@gmail.com
# ..........................................................

library(DSTdb)
library(tidyverse)
library(glue)

LOG_PATH <- "privilege_log.csv"

# Initialize log file if it doesn't exist
init_privilege_log <- function(path = LOG_PATH) {
  if (!file.exists(path)) {
    tibble(
      timestamp = character(),
      grantee = character(),
      table_name = character(),
      schema = character(),
      privilege = character(),
      granted_by = character(),
      note = character()
    ) |>
      write_csv(path)
  }
}

# Core grant + log function
grant_privilege <- function(
  conn,
  grantee = NULL,
  table_name = "LIFELINES",
  privilege = "READ",
  schema = "D221911",
  granted_by = Sys.getenv("USERNAME"),
  note = "",
  log_path = LOG_PATH,
  dry_run = FALSE
) {
  sql <- glue("GRANT {privilege} ON {schema}.{table_name} TO {grantee}")

  if (dry_run) {
    message("[DRY RUN] Would execute: ", sql)
    return(invisible(NULL))
  }

  dbSendQuery(conn, sql)

  tibble(
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    grantee = grantee,
    table_name = table_name,
    schema = schema,
    privilege = privilege,
    granted_by = granted_by,
    note = note
  ) |>
    write_csv(log_path, append = TRUE)

  message(glue(
    "[{Sys.time()}] GRANT {privilege} ON {schema}.{table_name} TO {grantee} — logged."
  ))
  invisible(TRUE)
}

# Batch grant from a 3-column tibble: GRANTEE, PRIVILEGE, TABLE_NAME
grant_privilege_batch <- function(
  conn,
  grants, # tibble with columns: GRANTEE, PRIVILEGE, TABLE_NAME
  schema = "D221911",
  ...
) {
  grants |>
    purrr::pwalk(\(GRANTEE, PRIVILEGE, TABLE_NAME, ...) {
      grant_privilege(
        conn,
        grantee = GRANTEE,
        table_name = TABLE_NAME,
        privilege = PRIVILEGE,
        schema = schema,
        ...
      )
    })
}

# Read the local log
read_privilege_log <- function(log_path = LOG_PATH) {
  read_csv(log_path, show_col_types = FALSE)
}

# Query Oracle directly for current live privileges on a schema
query_live_privileges <- function(conn, schema = "D221911") {
  sql <- glue_sql(
    "SELECT grantee, privilege, table_name
     FROM dba_tab_privs
     WHERE owner = {schema}
     ORDER BY table_name, grantee",
    .con = conn
  )
  dbGetQuery(conn, sql)
}
