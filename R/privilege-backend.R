# Database backends and statement planning for dst_db_privilege_management()
#
# The app talks to the database only through a small "backend" object, so the
# exact same UI and logging code runs against Oracle or against an in-memory
# simulation (dry-run mode). A backend is a list with:
#   mode            "oracle" or "dry_run"
#   database,schema what we are connected to
#   list_tables()   character vector of tables/views owned by `schema`
#   list_grants()   data frame: grantee, table_name, privilege, grantor
#   execute(stmt)   run one planned statement (a one-row list); error on failure
#   disconnect()

privilege_choices <- c("READ", "SELECT", "INSERT", "UPDATE")

# Unquoted Oracle identifier. Anything else is rejected, which also rules out
# SQL injection through the free-text inputs.
is_oracle_identifier <- function(x) {
  grepl("^[A-Z][A-Z0-9_$#]{0,127}$", x)
}

#' Split free text (commas, semicolons, whitespace, new lines) into IDs
#' @noRd
parse_id_list <- function(x) {
  if (is.null(x) || length(x) == 0) {
    return(character())
  }
  ids <- toupper(unlist(strsplit(paste(x, collapse = ","), "[,;[:space:]]+")))
  unique(ids[nzchar(ids)])
}

#' Validate inputs and build the list of statements to execute
#'
#' @return A list with `plan` (data frame, one row per statement) and
#'   `problems` (character vector; empty when the plan can be executed).
#' @noRd
build_privilege_plan <- function(
  action,
  privilege,
  tables,
  grantees,
  schema,
  note,
  current_grants = NULL
) {
  action <- toupper(action)
  schema <- toupper(trimws(schema))
  tables <- parse_id_list(tables)
  grantees <- parse_id_list(grantees)
  note <- if (is.null(note)) "" else trimws(note)
  problems <- character()

  if (!action %in% c("GRANT", "REVOKE")) {
    problems <- c(problems, "Action must be GRANT or REVOKE.")
  }
  if (!privilege %in% privilege_choices) {
    problems <- c(problems, paste("Unsupported privilege:", privilege))
  }
  if (length(tables) == 0) {
    problems <- c(problems, "Select at least one table.")
  }
  if (length(grantees) == 0) {
    problems <- c(problems, "Enter at least one grantee.")
  }
  if (!nzchar(note)) {
    problems <- c(
      problems,
      "A reason / reference is required (it is stored in the log)."
    )
  }
  bad <- c(tables, grantees)[!is_oracle_identifier(c(tables, grantees))]
  if (length(bad) > 0) {
    problems <- c(
      problems,
      paste0(
        "Not a valid Oracle name: ",
        paste(bad, collapse = ", "),
        " (letters, digits and _ only; must start with a letter)."
      )
    )
  }
  if ("PUBLIC" %in% grantees) {
    problems <- c(
      problems,
      "Granting to PUBLIC would expose the table to every database user and is not allowed here."
    )
  }
  if (schema %in% grantees) {
    problems <- c(
      problems,
      paste0("The schema ", schema, " already owns its tables; remove it from the grantees.")
    )
  }

  plan <- expand.grid(
    table_name = tables,
    grantee = grantees,
    stringsAsFactors = FALSE
  )
  plan <- plan[order(plan$table_name, plan$grantee), , drop = FALSE]
  rownames(plan) <- NULL
  plan$action <- rep(action, nrow(plan))
  plan$privilege <- rep(privilege, nrow(plan))
  plan$schema <- rep(schema, nrow(plan))
  plan$sql <- privilege_sql(plan$action, plan$privilege, schema, plan$table_name, plan$grantee)
  plan$currently_granted <- grant_exists(plan, current_grants)

  list(plan = plan, problems = problems)
}

privilege_sql <- function(action, privilege, schema, table_name, grantee) {
  ifelse(
    action == "GRANT",
    paste0("GRANT ", privilege, " ON ", schema, ".", table_name, " TO ", grantee),
    paste0("REVOKE ", privilege, " ON ", schema, ".", table_name, " FROM ", grantee)
  )
}

grant_key <- function(df) {
  paste(toupper(df$grantee), toupper(df$table_name), toupper(df$privilege), sep = "|")
}

grant_exists <- function(plan, current_grants) {
  if (is.null(current_grants) || nrow(plan) == 0) {
    return(rep(NA, nrow(plan)))
  }
  grant_key(plan) %in% grant_key(current_grants)
}

#' Execute a plan statement by statement, logging each one immediately
#'
#' Stops the batch if a log write fails: continuing would create privileges
#' that nobody can trace afterwards.
#'
#' @return The plan with `status` and `error` columns added.
#' @noRd
execute_privilege_plan <- function(backend, plan, note, performed_by, log_file) {
  batch_id <- format(Sys.time(), "%Y%m%d-%H%M%OS3")
  plan$status <- rep("NOT RUN", nrow(plan))
  plan$error <- rep("", nrow(plan))

  for (i in seq_len(nrow(plan))) {
    stmt <- as.list(plan[i, , drop = FALSE])
    err <- tryCatch(
      {
        backend$execute(stmt)
        ""
      },
      error = function(e) conditionMessage(e)
    )
    plan$status[i] <- if (nzchar(err)) "FAILED" else "OK"
    plan$error[i] <- err

    log_error <- tryCatch(
      {
        append_privilege_log(
          log_file,
          data.frame(
            timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %z"),
            batch_id = batch_id,
            performed_by = performed_by,
            database = backend$database,
            schema = backend$schema,
            action = stmt$action,
            privilege = stmt$privilege,
            table_name = stmt$table_name,
            grantee = stmt$grantee,
            status = plan$status[i],
            note = note,
            error = err,
            stringsAsFactors = FALSE
          )
        )
        ""
      },
      error = function(e) conditionMessage(e)
    )
    if (nzchar(log_error)) {
      plan$status[i] <- paste(plan$status[i], "- NOT LOGGED")
      plan$error[i] <- trimws(paste(err, "Log write failed:", log_error))
      break
    }
  }
  plan
}

#' Compare the live privileges with the log
#'
#' @return A list: `live` (live grants annotated with the latest matching log
#'   entry) and `missing` (log says granted, database disagrees).
#' @noRd
reconcile_grants <- function(live, log, database, schema) {
  log <- log[
    log$status == "OK" &
      toupper(log$schema) == toupper(schema) &
      (toupper(log$database) == toupper(database) | log$database == ""),
    ,
    drop = FALSE
  ]
  # Latest successful action per grantee/table/privilege (log is newest first)
  log <- log[!duplicated(grant_key(log)), , drop = FALSE]
  log_keys <- grant_key(log)

  idx <- match(grant_key(live), log_keys)
  live$logged <- ifelse(
    !is.na(idx) & log$action[idx] %in% "GRANT",
    "yes",
    "NOT IN LOG"
  )
  live$logged_at <- ifelse(is.na(idx), "", log$timestamp[idx])
  live$logged_by <- ifelse(is.na(idx), "", log$performed_by[idx])
  live$note <- ifelse(is.na(idx), "", log$note[idx])

  believed <- log[log$action == "GRANT", , drop = FALSE]
  missing <- believed[!grant_key(believed) %in% grant_key(live), , drop = FALSE]

  list(
    live = live[order(live$logged != "NOT IN LOG", live$table_name, live$grantee), , drop = FALSE],
    missing = missing[c("grantee", "table_name", "privilege", "timestamp", "performed_by", "note")]
  )
}

# -- Oracle backend ---------------------------------------------------------

new_oracle_backend <- function(database, schema) {
  if (!requireNamespace("DSTdb", quietly = TRUE)) {
    stop(
      "Package 'DSTdb' is not available, so the app cannot connect to a database.\n",
      "Run `dst_db_privilege_management(dry_run = TRUE)` to try the app without one.",
      call. = FALSE
    )
  }
  conn <- DSTdb::get_conn(database, proxy = paste0("[", schema, "]"))
  DBI::dbGetQuery(conn, "SELECT 1 FROM DUAL")

  list(
    mode = "oracle",
    database = database,
    schema = schema,
    list_tables = function() {
      # `schema` is a validated identifier, so inlining it is safe
      res <- DBI::dbGetQuery(
        conn,
        paste0(
          "SELECT object_name FROM all_objects WHERE owner = '",
          schema,
          "' AND object_type IN ('TABLE', 'VIEW') ORDER BY object_name"
        )
      )
      as.character(res[[1]])
    },
    list_grants = function() {
      res <- DBI::dbGetQuery(
        conn,
        paste0(
          "SELECT grantee, table_name, privilege, grantor FROM all_tab_privs ",
          "WHERE table_schema = '",
          schema,
          "' ORDER BY table_name, grantee, privilege"
        )
      )
      names(res) <- tolower(names(res))
      res[] <- purrr::map(res, as.character)
      res
    },
    execute = function(stmt) {
      res <- DBI::dbSendQuery(conn, stmt$sql)
      DBI::dbClearResult(res)
      invisible(TRUE)
    },
    disconnect = function() {
      try(DBI::dbDisconnect(conn), silent = TRUE)
    }
  )
}

# -- Dry-run backend --------------------------------------------------------

#' In-memory stand-in for an Oracle schema
#'
#' Mimics the Oracle errors users actually hit, so the full flow (including
#' failure logging) can be exercised without a database:
#' * unknown table             -> ORA-00942
#' * grantee starting with ZZ  -> ORA-01917 (user does not exist)
#' * revoke of a missing grant -> ORA-01927
#' @noRd
new_dry_run_backend <- function(database, schema) {
  state <- new.env()
  state$tables <- c(
    "BEF_2020",
    "BEF_2021",
    "IND_2021",
    "LIFELINES",
    "LIFELINES_KOEN",
    "UDDA_2021"
  )
  state$grants <- data.frame(
    grantee = c("IKX", "X01"),
    table_name = c("LIFELINES", "BEF_2021"),
    privilege = c("READ", "SELECT"),
    grantor = schema,
    stringsAsFactors = FALSE
  )

  list(
    mode = "dry_run",
    database = database,
    schema = schema,
    list_tables = function() state$tables,
    list_grants = function() state$grants,
    execute = function(stmt) {
      if (!stmt$table_name %in% state$tables) {
        stop("ORA-00942: table or view does not exist", call. = FALSE)
      }
      if (startsWith(stmt$grantee, "ZZ")) {
        stop(
          "ORA-01917: user or role '",
          stmt$grantee,
          "' does not exist",
          call. = FALSE
        )
      }
      key <- grant_key(as.data.frame(stmt[c("grantee", "table_name", "privilege")]))
      held <- key %in% grant_key(state$grants)
      if (stmt$action == "GRANT" && !held) {
        state$grants <- rbind(
          state$grants,
          data.frame(
            grantee = stmt$grantee,
            table_name = stmt$table_name,
            privilege = stmt$privilege,
            grantor = schema,
            stringsAsFactors = FALSE
          )
        )
      }
      if (stmt$action == "REVOKE") {
        if (!held) {
          stop("ORA-01927: cannot REVOKE privileges you did not grant", call. = FALSE)
        }
        state$grants <- state$grants[grant_key(state$grants) != key, , drop = FALSE]
      }
      invisible(TRUE)
    },
    disconnect = function() invisible(NULL)
  )
}
