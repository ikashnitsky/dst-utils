# Verification on DST for the open items in dev/TODO.md -----------------------
#
# Run this on DST, logged in with an ident that has access to DB_PSD, from
# the package source directory. It uses dummy ids only ("1234", "2345"), so
# no real CPR numbers are involved. Every check is wrapped in tryCatch(): a
# failing check is recorded and the script goes on. All test tables are
# dropped at the end. Your recycle bin is not purged; only the one test table
# used to check it is.
#
# 1. First run the package tests against the real DB_PSD:
#      devtools::test(filter = "convert_person_id")
# 2. Optionally fill in the settings below (other user, proxy).
# 3. Source this file and paste the printed summary into the PR / TODO.md.

devtools::load_all()

# Settings ----------------------------------------------------------------------

# Another user ident to pass as p_bruger (recipient). NULL skips that check.
other_user <- NULL
# A database and project schema to test proxy connections and copying to
# another database, e.g. "STATPROD" and "D222401". NULL skips those checks.
proxy_database <- NULL
proxy_schema <- NULL

# Helpers -------------------------------------------------------------------------

psd <- DSTdb::get_conn("DB_PSD")
me <- db_user(psd)
results <- list()
test_tables <- character()

check <- function(item, expr) {
  message("\n== ", item)
  value <- tryCatch(expr, error = function(e) paste("ERROR:", conditionMessage(e)))
  value <- paste(format(value), collapse = "; ")
  message(value)
  results[[item]] <<- value
  invisible(value)
}

drop_if_exists <- function(conn, tbl, schema) {
  if (table_exists(conn, tbl, schema)) {
    db_execute(conn, paste("drop table", tbl))
  }
}

make_test_table <- function(name, data) {
  drop_if_exists(psd, name, me)
  test_tables <<- c(test_tables, name)
  db_write_table(psd, name, data)
  name
}

# Run a procedure with the PL/SQL the package builds, but with any input table
# name (p_ind_tabelnavn) and recipient (p_bruger). Returns the result text,
# the run id and the name of the output table.
run_proc <- function(proc, input_table, recipient = me) {
  spec <- bef_procedure(proc)
  run_table <- run_table_name()
  db_execute(
    psd,
    paste0("create table ", run_table, " (v_resultat VARCHAR2(200), v_koerselsid NUMBER)")
  )
  on.exit(drop_if_exists(psd, run_table, me), add = TRUE)
  plsql <- build_bef_plsql(spec, "DSTUTILS_TEST", recipient, "none", list(), run_table)
  plsql <- sub("'BEF_ID_PROC'", sql_string(input_table), plsql, fixed = TRUE)
  psd_run_plsql(psd, plsql)
  run <- read_run_info(psd, run_table)
  run$out <- paste0(spec$prefix, run$id)
  test_tables <<- c(test_tables, run$out)
  run
}

owners_of <- function(tbl) {
  db_query(
    psd,
    paste0("select owner from all_tables where table_name = ", sql_string(tbl))
  )$OWNER
}

ids <- data.frame(PERSON_ID = c("1234", "2345"))

# Item 3: does the output contain other input columns? -------------------------
# Item 5b: does the procedure accept any p_ind_tabelnavn? ----------------------

input_extra <- make_test_table(
  "DSTUTILS_T_EXTRA",
  data.frame(PERSON_ID = c("1234", "2345"), EXTRA_COL = c("a", "b"))
)

run3 <- NULL
check("5b: procedure accepts an input table not called BEF_ID_PROC", {
  run3 <- run_proc("BEF_AKTUELLE_PNR", input_extra)
  paste("yes;", run3$result)
})
check("3: output columns when the input has an extra column", {
  cols <- names(db_query(psd, paste("select * from", run3$out, "where 1 = 0")))
  paste0(
    paste(cols, collapse = ", "),
    if ("EXTRA_COL" %in% cols) " -> EXTRA_COL IS passed through" else
      " -> EXTRA_COL is NOT passed through"
  )
})

check("5b: p_ind_tabelnavn accepts a schema-qualified name", {
  run <- run_proc("BEF_AKTUELLE_PNR", paste0(me, ".", input_extra))
  n <- db_query(psd, paste("select count(*) as N from", run$out))$N
  paste("yes;", run$result, "; rows:", n)
})

# p_bruger: where is the output table created? ----------------------------------

check("p_bruger = own user: owner of the output table", {
  paste(owners_of(run3$out), collapse = ", ")
})
if (!is.null(other_user)) {
  check(paste0("p_bruger = ", other_user, ": owner of the output table"), {
    run <- run_proc("BEF_AKTUELLE_PNR", input_extra, recipient = other_user)
    owners <- owners_of(run$out)
    paste0(
      if (length(owners)) paste(owners, collapse = ", ") else "not visible",
      "; ",
      run$result
    )
  })
}
check("p_bruger = '' (recipient = NULL): owner of the output table", {
  run <- run_proc("BEF_AKTUELLE_PNR", input_extra, recipient = NULL)
  paste(owners_of(run$out), collapse = ", ")
})

# BEF_IDSKIFT output columns -------------------------------------------------------

check("BEF_IDSKIFT output columns", {
  input <- make_test_table("DSTUTILS_T_IDS", ids)
  run <- run_proc("BEF_IDSKIFT", input)
  cols <- db_query(
    psd,
    paste0(
      "select column_name, data_type from user_tab_columns where table_name = ",
      sql_string(run$out),
      " order by column_id"
    )
  )
  paste(cols$COLUMN_NAME, cols$DATA_TYPE, collapse = ", ")
})

# Item 4b: column types the procedures produce and accept ------------------------

check("4b: column types of an output table (BEF_AKTUELLE_PNR)", {
  cols <- db_query(
    psd,
    paste0(
      "select column_name, data_type, data_length from user_tab_columns ",
      "where table_name = ",
      sql_string(run3$out),
      " order by column_id"
    )
  )
  paste(cols$COLUMN_NAME, cols$DATA_TYPE, cols$DATA_LENGTH, collapse = ", ")
})
check("4b: type of PERSON_ID uploaded from R as character", {
  cols <- db_query(
    psd,
    paste0(
      "select column_name, data_type, data_length from user_tab_columns ",
      "where table_name = ",
      sql_string(input_extra)
    )
  )
  paste(cols$COLUMN_NAME, cols$DATA_TYPE, cols$DATA_LENGTH, collapse = ", ")
})
check("4b: procedure accepts a NUMBER PERSON_ID column", {
  input <- make_test_table("DSTUTILS_T_NUM", data.frame(PERSON_ID = c(1234, 2345)))
  run <- run_proc("BEF_AKTUELLE_PNR", input)
  paste("yes;", run$result)
})

# Registry time: text lookup vs. the old POSIXct round trip ----------------------

check("registry time: old POSIXct value vs. new text value (2021-12-31)", {
  old <- db_query(
    psd,
    paste0(
      "select min(time_stamp) as TID from D101200.bef_leverance_time ",
      "where trunc(cpr_slut) >= TO_DATE('2021-12-31','YYYY-MM-DD')"
    )
  )$TID
  new <- suppressMessages(lookup_registry_time(psd, "2021-12-31"))
  paste0(
    "old: ", as.character(old), " | new: ", new,
    if (identical(as.character(old), new)) " -> identical" else " -> DIFFERENT"
  )
})
check("registry time: column type of time_stamp", {
  db_query(
    psd,
    paste0(
      "select data_type from all_tab_columns where owner = 'D101200' ",
      "and table_name = 'BEF_LEVERANCE_TIME' and column_name = 'TIME_STAMP'"
    )
  )$DATA_TYPE
})

# Housekeeping queries used by convert_person_id() ------------------------------

check("user_objects query for old run tables works", {
  stale <- db_query(
    psd,
    paste0(
      "SELECT object_name FROM user_objects WHERE object_type = 'TABLE' ",
      "AND object_name LIKE 'PSDMYTEMP\\_%' ESCAPE '\\' ",
      "AND created < SYSDATE - 1"
    )
  )
  paste("yes;", nrow(stale), "old run tables")
})
check("legacy PSDMYTEMP table in own schema (SAS job?)", {
  if (table_exists(psd, "PSDMYTEMP", me)) "exists" else "does not exist"
})

# PURGE and the recycle bin ---------------------------------------------------------

check("recycle bin: a dropped table stays there (without PURGE)", {
  tbl <- make_test_table("DSTUTILS_T_BIN", ids)
  db_execute(psd, paste("drop table", tbl))
  n <- db_query(
    psd,
    paste0("select count(*) as N from user_recyclebin where original_name = ", sql_string(tbl))
  )$N
  if (n > 0) {
    # Remove only this test table from the recycle bin
    db_execute(psd, paste("purge table", tbl))
    "yes: dropped work tables (with CPR) stay in the recycle bin"
  } else {
    "no"
  }
})
check("DROP TABLE ... PURGE is allowed", {
  tbl <- make_test_table("DSTUTILS_T_PURGE", ids)
  db_execute(psd, paste("drop table", tbl, "purge"))
  "yes"
})

# Item 5b: OUT binds via ROracle::oracleProc() instead of a run table -----------

check("OUT binds via ROracle::oracleProc()", {
  input <- make_test_table("DSTUTILS_T_BIND", ids)
  data <- data.frame(
    proj = "DSTUTILS_TEST",
    bruger = me,
    tab = input,
    resultat = NA_character_,
    koerselsid = NA_real_,
    stringsAsFactors = FALSE
  )
  attr(data$resultat, "ora.parameter_mode") <- "OUT"
  attr(data$resultat, "ora.maxlength") <- 200L
  attr(data$koerselsid, "ora.parameter_mode") <- "OUT"
  res <- ROracle::oracleProc(
    psd,
    paste0(
      "BEGIN BEF01_pck_laes_personnummer.BEF_AKTUELLE_PNR(",
      "p_projektnummer => :1, p_bruger => :2, p_ind_tabelnavn => :3, ",
      "p_resultat => :4, p_koerselsid => :5); END;"
    ),
    data
  )
  id <- format_run_id(res$koerselsid[1])
  test_tables <<- c(test_tables, paste0("AKTPNR", id))
  paste("yes; resultat:", res$resultat[1], "; run id:", id)
})

# Proxy connections and copying to another database ------------------------------

if (!is.null(proxy_database) && !is.null(proxy_schema)) {
  proxy <- check_proxy(proxy_schema)
  check("proxy: USER of a proxy connection (bef_personnummer namespace)", {
    conn <- db_connect(proxy_database, proxy)
    user <- db_user(conn)
    db_disconnect(conn)
    user
  })
  check("proxy: a plain connection after a proxy one is not the proxy user", {
    conn_proxy <- db_connect(proxy_database, proxy)
    conn_plain <- db_connect(proxy_database)
    users <- c(db_user(conn_proxy), db_user(conn_plain))
    db_disconnect(conn_plain)
    db_disconnect(conn_proxy)
    paste(users, collapse = " / ")
  })
  check("chunked copy DB_PSD -> proxy schema (copy_output)", local({
      src <- make_test_table("DSTUTILS_T_COPY", data.frame(A = 1:5, B = letters[1:5]))
      conn <- db_connect(proxy_database, proxy)
      on.exit(db_disconnect(conn), add = TRUE)
      schema <- db_user(conn)
      drop_if_exists(conn, "DSTUTILS_T_COPY", schema)
      withr::with_options(
        list(DSTutils.chunk_size = 2),
        copy_output(psd, src, conn, "DSTUTILS_T_COPY", schema, proxy_database)
      )
      n <- db_query(conn, "select count(*) as N from DSTUTILS_T_COPY")$N
      drop_if_exists(conn, "DSTUTILS_T_COPY", schema)
      paste("rows copied:", n, "(expected 5)")
  }))
  check("end to end: in and out in the proxy schema", local({
      conn <- db_connect(proxy_database, proxy)
      on.exit(db_disconnect(conn), add = TRUE)
      schema <- db_user(conn)
      for (tbl in c("DSTUTILS_T_SRC", "DSTUTILS_T_OUT")) drop_if_exists(conn, tbl, schema)
      db_write_table(conn, "DSTUTILS_T_SRC", ids)
      convert_person_id(
        procedure = "BEF_AKTUELLE_PNR",
        in_data = "ORACLE",
        in_table_name = paste0(schema, ".DSTUTILS_T_SRC"),
        out_data = "ORACLE",
        out_table_name = "DSTUTILS_T_OUT",
        in_database = proxy_database,
        out_database = proxy_database,
        proxy = proxy,
        project_id = "DSTUTILS_TEST"
      )
      n <- db_query(conn, "select count(*) as N from DSTUTILS_T_OUT")$N
      for (tbl in c("DSTUTILS_T_SRC", "DSTUTILS_T_OUT")) drop_if_exists(conn, tbl, schema)
      paste("yes; rows:", n)
  }))
}

# Clean up and summary ------------------------------------------------------------

for (tbl in unique(test_tables)) {
  tryCatch(drop_if_exists(psd, tbl, me), error = function(e) {
    message("Could not drop ", tbl, ": ", conditionMessage(e))
  })
}
db_disconnect(psd)

cat("\n\n## DST verification results (", format(Sys.time()), ")\n\n", sep = "")
for (item in names(results)) {
  cat("- **", item, "**: ", results[[item]], "\n", sep = "")
}
