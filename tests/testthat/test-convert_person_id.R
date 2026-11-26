# Offline tests (no database) -------------------------------------------------

pnr <- data.frame(pnr = c("0101011234", "0202024321"))
pid <- data.frame(PERSON_ID = c("1234", "2345"))

test_that("character arguments work quoted, bare and as variables", {
  f <- function(x) arg_as_string(substitute(x), parent.frame(), "x")
  my_proc <- "BEF_OMKOD"
  not_a_string <- 1:3

  expect_equal(f("BEF_OMKOD"), "BEF_OMKOD")
  expect_equal(f(BEF_OMKOD), "BEF_OMKOD")
  expect_equal(f(my_proc), "BEF_OMKOD")
  expect_equal(f(paste0("D", "101200")), "D101200")
  expect_equal(f(101200), "101200")
  expect_null(f(NULL))
  # A bare word naming a non-character object is still taken literally
  expect_equal(f(not_a_string), "not_a_string")
  expect_error(f(c("A", "B")), "single character string")
})

test_that("procedures are looked up case-insensitively", {
  expect_equal(bef_procedure("bef_omkod")$name, "BEF_OMKOD")
  expect_equal(bef_procedure("BEF_OMKOD")$package$call, "BEF01_pck_omkodning")
  expect_equal(
    bef_procedure("BEF_IDSKIFT")$package$call,
    "BEF01_pck_laes_personnummer"
  )
  expect_error(bef_procedure(NULL), "Specify the name")
  expect_error(bef_procedure("BEF_NOPE"), "not recognized")
})

test_that("date arguments map to the combinations each procedure accepts", {
  # Same accept/reject matrix as the original if/else chain
  inputs <- list(
    none = list(),
    V = list(validity_date = 1),
    VR = list(validity_date = 1, registry_time = 1),
    SE = list(registry_start_time = 1, registry_end_time = 1),
    R = list(registry_time = 1),
    VSE = list(validity_date = 1, registry_start_time = 1, registry_end_time = 1)
  )
  current <- c(none = "none", V = "validity")
  historic <- c(V = "historic", VR = "historic")
  full <- c(none = "none", SE = "range")
  expected <- list(
    BEF_OMKOD = current,
    BEF_AKTUELLE_ID = current,
    BEF_AKTUELLE_PNR = current,
    BEF_AKTUEL_KOEN_FOEDSELSDAG = current,
    BEF_HISTORISK_ID = historic,
    BEF_HISTORISK_PNR = historic,
    BEF_HISTORISK_KOEN_FOEDSELSDAG = historic,
    BEF_FULD_HISTORIK_ID = full,
    BEF_FULD_HISTORIK_PNR = full,
    BEF_FULD_HIS_KOEN_FOEDSELSDAG = full,
    BEF_IDSKIFT = c(none = "none"),
    BEF_INVALIDE = full
  )
  expect_setequal(names(expected), names(bef_procedures))

  for (proc in names(expected)) {
    spec <- bef_procedure(proc)
    for (input in names(inputs)) {
      mode <- tryCatch(
        do.call(resolve_date_mode, c(list(spec), inputs[[input]])),
        error = function(e) "error"
      )
      want <- if (input %in% names(expected[[proc]])) {
        expected[[proc]][[input]]
      } else {
        "error"
      }
      expect_identical(mode, want, label = paste(proc, input))
    }
  }

  expect_error(
    resolve_date_mode(bef_procedure("BEF_INVALIDE"), registry_start_time = 1),
    "registry_start_time eller registry_end_time"
  )
  expect_error(
    resolve_date_mode(bef_procedure("BEF_IDSKIFT"), validity_date = 1),
    "BEF_IDSKIFT accepts: no date arguments"
  )
})

test_that("dates are parsed into Oracle strings, keeping milliseconds", {
  expect_equal(parse_datetime_arg(31122021, "d")$date, "2021-12-31")
  expect_equal(parse_datetime_arg("2021-12-31", "d")$date, "2021-12-31")
  expect_equal(parse_datetime_arg(01012021, "d")$date, "2021-01-01")
  expect_equal(
    parse_datetime_arg("16012022 18:00:00", "d")$datetime,
    "2022-01-16 18:00:00"
  )
  expect_equal(
    parse_datetime_arg("31122000 120303.232", "d")$datetime,
    "2000-12-31 12:03:03.232"
  )
  expect_equal(
    parse_datetime_arg("31129999 235959.999", "d")$datetime,
    "9999-12-31 23:59:59.999"
  )
  expect_error(parse_datetime_arg("not a date", "validity_date"), "Ukendt format")
  expect_error(parse_datetime_arg(c(1, 2), "validity_date"), "single value")
})

test_that("the input table is checked and the id column named as required", {
  res <- prepare_input_table(pnr, "PNR", NULL, "BEF_OMKOD")
  expect_named(res, "PNR")

  cpr <- data.frame(cpr_nr = "0101011234", other = 1)
  expect_message(
    res <- prepare_input_table(cpr, "PNR", "cpr_nr", "BEF_OMKOD"),
    "uploaded as PNR"
  )
  expect_named(res, c("PNR", "OTHER"))

  expect_error(
    prepare_input_table(pid, "PNR", NULL, "BEF_OMKOD"),
    "no column PNR"
  )
  expect_error(
    prepare_input_table(data.frame(PNR = 1, CPR = 1), "PNR", "CPR", "BEF_OMKOD"),
    "both CPR"
  )
  expect_error(
    prepare_input_table(data.frame(pnr = 1, PNR = 2), "PNR", NULL, "BEF_OMKOD"),
    "unique regardless of case"
  )
  expect_error(
    prepare_input_table("MY_TABLE", "PNR", NULL, "BEF_OMKOD"),
    "must be a data frame"
  )
})

test_that("generated PL/SQL is stable for every date mode", {
  plsql <- function(proc, mode, dates = list(), project_id = "D101200", recipient = "IKX") {
    run_table <- "PSDMYTEMP_261126120000_4242"
    cat(build_bef_plsql(bef_procedure(proc), project_id, recipient, mode, dates, run_table))
  }
  expect_snapshot({
    plsql("BEF_OMKOD", "none")
    plsql("BEF_AKTUELLE_PNR", "validity", list(validity = "2021-12-31"))
    plsql(
      "BEF_HISTORISK_ID",
      "historic",
      list(validity = "2021-12-31", registry = "2022-01-16 18:00:00")
    )
    plsql(
      "BEF_FULD_HIS_KOEN_FOEDSELSDAG",
      "range",
      list(start = "2000-12-31 12:03:03.232", end = "9999-12-31 23:59:59.999")
    )
    plsql("BEF_INVALIDE", "none")
    plsql(
      "BEF_INVALIDE",
      "range",
      list(start = "1900-01-01 00:00:00", end = "2100-01-01 00:00:00")
    )
    # Quotes are escaped; NULL recipient is sent as an empty string
    plsql("BEF_IDSKIFT", "none", project_id = "O'Brien", recipient = NULL)
  })
})

test_that("run ids never use scientific notation", {
  expect_equal(format_run_id(4711), "4711")
  expect_equal(format_run_id(3e6), "3000000")
  expect_equal(format_run_id(1e5), "100000")
})

# Orchestration against a fake DB_PSD ------------------------------------------

test_that("a conversion uploads, runs, returns the output and cleans up", {
  withr::local_envvar(USERNAME = "IKX")
  db <- local_fake_psd()

  msgs <- capture_messages(
    res <- convert_person_id(
      procedure = "BEF_HISTORISK_ID",
      in_table_name = pnr,
      project_id = "D101200",
      validity_date = 31122021
    )
  )
  expect_match(msgs, "registry datetime used is = 2022-01-16 18:00:00", all = FALSE)
  expect_match(msgs, "Koersel OK", all = FALSE)

  expect_equal(res, data.frame(PNR = "0101011234", PERSON_ID = 1))
  expect_equal(names(db$uploads), "BEF_ID_PROC")
  expect_named(db$uploads$BEF_ID_PROC, "PNR")
  expect_length(db$plsql, 1)
  expect_match(db$plsql, "BEF01_pck_laes_personnummer.BEF_HISTORISK_ID(", fixed = TRUE)
  expect_match(db$plsql, "p_registerdato   => TO_TIMESTAMP('2022-01-16 18:00:00'", fixed = TRUE)
  expect_true("select * from HIS_ID4711" %in% db$statements)
  expect_length(db$tables, 0)
  expect_equal(c(db$connects, db$disconnects), c(1, 1))
})

test_that("the default project id is the user ident", {
  withr::local_envvar(USERNAME = "IKX")
  db <- local_fake_psd()
  msgs <- capture_messages(convert_person_id(procedure = "BEF_INVALIDE"))
  expect_match(msgs, "anvendes user-ident IKX", all = FALSE)
  expect_match(db$plsql, "p_projektnummer => 'IKX'", fixed = TRUE)
  expect_no_match(db$plsql, "p_ind_tabelnavn", fixed = TRUE)
})

test_that("work tables are dropped and the connection closed on failure", {
  withr::local_envvar(USERNAME = "IKX")
  db <- local_fake_psd(proc_error = "ORA-06550: boom")
  expect_error(
    convert_person_id(procedure = "BEF_OMKOD", in_table_name = pnr, project_id = "X"),
    "ORA-06550"
  )
  expect_length(db$tables, 0)
  expect_equal(db$disconnects, 1)

  db <- local_fake_psd(create_output = FALSE)
  expect_error(
    suppressMessages(
      convert_person_id(procedure = "BEF_OMKOD", in_table_name = pnr, project_id = "X")
    ),
    "PNROMKOD4711 was not created. Procedure result: Koersel OK"
  )
  expect_length(db$tables, 0)
})

test_that("invalid input fails before connecting", {
  db <- local_fake_psd()
  expect_error(convert_person_id(procedure = "BEF_OMKOD"), "in_table_name")
  expect_error(
    convert_person_id(procedure = "BEF_OMKOD", in_table_name = pnr, registry_time = 1),
    "kombinationen"
  )
  expect_error(
    convert_person_id(procedure = "BEF_OMKOD", in_table_name = pnr, in_data = "ORACLE"),
    "must be a table name"
  )
  expect_error(
    convert_person_id(procedure = "BEF_OMKOD", in_table_name = pnr, out_data = "ORACLE"),
    "out_table_name="
  )
  expect_error(
    convert_person_id(
      procedure = "BEF_OMKOD",
      in_table_name = pnr,
      out_data = "ORACLE",
      out_table_name = "MY TABLE"
    ),
    "not a valid Oracle name"
  )
  expect_error(
    convert_person_id(procedure = "BEF_OMKOD", in_table_name = pnr, in_data = "SAS"),
    "must be \"R\" or \"ORACLE\""
  )
  expect_error(
    convert_person_id(procedure = "BEF_OMKOD", in_table_name = pnr, proxy = "[D2; x]"),
    "'proxy'"
  )
  expect_equal(db$connects, 0)
})

test_that("leftovers from an interrupted run are dropped first", {
  withr::local_envvar(USERNAME = "IKX")
  old_run <- "PSDMYTEMP_251126120000_1"
  db <- local_fake_psd(
    leftover = c("BEF_ID_PROC", "PSDMYTEMP", old_run, "PSDMYTEMP_261126115959_2"),
    stale = old_run
  )
  msgs <- capture_messages(
    convert_person_id(procedure = "BEF_OMKOD", in_table_name = pnr, project_id = "X")
  )
  expect_equal(sum(grepl("left in DB_PSD by an earlier", msgs)), 1)
  expect_true("drop table BEF_ID_PROC" %in% db$statements)
  expect_true(paste("drop table", old_run) %in% db$statements)
  # The legacy PSDMYTEMP (maybe a SAS job's) and a recent run table are kept
  expect_setequal(db$tables, c("PSDMYTEMP", "PSDMYTEMP_261126115959_2"))
})

test_that("round run ids find their output table", {
  withr::local_envvar(USERNAME = "IKX")
  db <- local_fake_psd(run_id = 3e6)
  res <- suppressMessages(
    convert_person_id(procedure = "BEF_OMKOD", in_table_name = pnr, project_id = "X")
  )
  expect_s3_class(res, "data.frame")
  expect_true("select * from PNROMKOD3000000" %in% db$statements)
})

test_that("Oracle names, proxies and source tables are validated", {
  expect_equal(check_identifier("my_tab$1", "x"), "MY_TAB$1")
  expect_error(check_identifier("1TAB", "x"), "not a valid Oracle name")
  expect_error(check_identifier("A.B", "x"), "not a valid Oracle name")
  expect_error(check_identifier("a'--", "x"), "not a valid Oracle name")
  expect_error(check_identifier(strrep("A", 129), "x"), "not a valid Oracle name")

  expect_equal(check_proxy("d222401"), "[D222401]")
  expect_equal(check_proxy("[D222401]"), "[D222401]")

  expect_equal(check_out_table_name("idskift_2024"), "IDSKIFT_2024")
  expect_error(check_out_table_name(NULL), "out_table_name=")
  expect_error(check_out_table_name("bef_id_proc"), "work table")
  expect_error(check_out_table_name("PSDMYTEMP"), "work table")

  src <- parse_source_table("d222401.persons", NULL, "PERSON_ID")
  expect_equal(src$schema, "D222401")
  expect_equal(src$qualified, "D222401.PERSONS")
  expect_equal(src$column, "PERSON_ID")
  src <- parse_source_table("persons", "cpr_nr", "PNR")
  expect_null(src$schema)
  expect_equal(src$qualified, "PERSONS")
  expect_equal(src$column, "CPR_NR")
  expect_error(parse_source_table("a.b.c", NULL, "PNR"), "SCHEMA.TABLE")
  expect_error(parse_source_table("X.BEF_ID_PROC", NULL, "PNR"), "work table")
  expect_error(parse_source_table(pnr, NULL, "PNR"), "must be a table name")
  expect_error(parse_source_table("T", "bad col", "PNR"), "column_name")
})

test_that("run tables get unique names within Oracle's 30-character limit", {
  t <- as.POSIXct("2026-11-26 12:34:56", tz = "UTC")
  expect_equal(run_table_name(t, 1234567), "PSDMYTEMP_261126123456_34567")
  expect_lte(nchar(run_table_name(t, 99999)), 30)
  expect_match(run_table_name(), "^PSDMYTEMP_[0-9]{12}_[0-9]{1,5}$")
})

test_that("trailing zeros of the registry time fraction are trimmed", {
  expect_equal(trim_fraction("2022-01-16 18:00:00.000000"), "2022-01-16 18:00:00")
  expect_equal(trim_fraction("2022-01-16 18:00:10.000000"), "2022-01-16 18:00:10")
  expect_equal(trim_fraction("2022-01-16 18:00:00.123000"), "2022-01-16 18:00:00.123")
  expect_equal(trim_fraction("2022-01-16 18:00:00"), "2022-01-16 18:00:00")
})

test_that("numeric PNRs give a warning", {
  expect_warning(
    prepare_input_table(data.frame(PNR = 101011234), "PNR", NULL, "BEF_OMKOD"),
    "lost their leading zero"
  )
  expect_no_warning(prepare_input_table(pnr, "PNR", NULL, "BEF_OMKOD"))
  # PERSON_IDs are numbers anyway
  expect_no_warning(
    prepare_input_table(data.frame(PERSON_ID = 1), "PERSON_ID", NULL, "BEF_IDSKIFT")
  )
})

test_that("the run table name is used in the PL/SQL and dropped afterwards", {
  withr::local_envvar(USERNAME = "IKX")
  db <- local_fake_psd()
  suppressMessages(
    convert_person_id(procedure = "BEF_OMKOD", in_table_name = pnr, project_id = "X")
  )
  run_table <- sub("^create table (PSDMYTEMP_\\w+) .*", "\\1", grep(
    "^create table PSDMYTEMP_",
    db$statements,
    value = TRUE
  ))
  expect_length(run_table, 1)
  expect_match(db$plsql, paste0("insert into ", run_table, " values"), fixed = TRUE)
  expect_true(paste("drop table", run_table) %in% db$statements)
  expect_length(db$tables, 0)
})

test_that("the registry time is fetched as text", {
  withr::local_envvar(USERNAME = "IKX")
  db <- local_fake_psd()
  suppressMessages(convert_person_id(
    procedure = "BEF_HISTORISK_PNR",
    in_table_name = pid,
    project_id = "X",
    validity_date = 31122021
  ))
  lookup <- grep("bef_leverance_time", db$statements, value = TRUE)
  expect_match(lookup, "TO_CHAR(min(CAST(time_stamp AS TIMESTAMP))", fixed = TRUE)
  expect_match(lookup, "TO_DATE('2021-12-31', 'YYYY-MM-DD')", fixed = TRUE)
  expect_match(
    db$plsql,
    "p_registerdato   => TO_TIMESTAMP('2022-01-16 18:00:00', ",
    fixed = TRUE
  )
})

test_that("'database' still works but is deprecated", {
  withr::local_envvar(USERNAME = "IKX")
  db <- local_fake_psd()
  msgs <- capture_messages(
    convert_person_id(
      procedure = "BEF_OMKOD",
      database = "DB_PSD",
      in_table_name = pnr,
      project_id = "X"
    )
  )
  expect_match(msgs, "'database' is deprecated", all = FALSE)
  expect_length(db$remote_connects, 0)
})

# in_data = "ORACLE" ------------------------------------------------------------

test_that("an Oracle table in DB_PSD is copied with CREATE TABLE AS SELECT", {
  withr::local_envvar(USERNAME = "IKX")
  db <- local_fake_psd(
    source_columns = data.frame(COLUMN_NAME = c("ID", "CPR_NR"), DATA_TYPE = "VARCHAR2")
  )
  msgs <- capture_messages(
    res <- convert_person_id(
      procedure = "BEF_OMKOD",
      in_data = "ORACLE",
      in_table_name = "d222401.persons",
      column_name = "cpr_nr",
      project_id = "X"
    )
  )
  expect_s3_class(res, "data.frame")
  expect_match(msgs, "CPR_NR is uploaded as PNR", all = FALSE)
  expect_true(any(grepl(
    "all_tab_columns WHERE owner = 'D222401' AND table_name = 'PERSONS'",
    db$statements,
    fixed = TRUE
  )))
  expect_true(
    "create table BEF_ID_PROC as select distinct CPR_NR as PNR from D222401.PERSONS" %in%
      db$statements
  )
  expect_length(db$uploads, 0)
  expect_length(db$remote_connects, 0)
  # The procedure still reads BEF_ID_PROC
  expect_match(db$plsql, "p_ind_tabelnavn => 'BEF_ID_PROC'", fixed = TRUE)
  expect_length(db$tables, 0)
})

test_that("an unqualified source table is looked up in the user's schema", {
  withr::local_envvar(USERNAME = "IKX")
  db <- local_fake_psd()
  suppressMessages(convert_person_id(
    procedure = "BEF_OMKOD",
    in_data = "ORACLE",
    in_table_name = "persons",
    project_id = "X"
  ))
  expect_true(any(grepl("owner = USER AND table_name = 'PERSONS'", db$statements)))
})

test_that("an Oracle table in another database is read and uploaded", {
  withr::local_envvar(USERNAME = "IKX")
  db <- local_fake_psd(
    source_columns = data.frame(COLUMN_NAME = "PERSON_ID", DATA_TYPE = "NUMBER"),
    source_rows = data.frame(PERSON_ID = c(1, 2))
  )
  suppressMessages(convert_person_id(
    procedure = "BEF_IDSKIFT",
    in_data = "ORACLE",
    in_table_name = "D222401.PERSONS",
    in_database = "statprod",
    proxy = "D222401",
    project_id = "X"
  ))
  expect_equal(db$remote_connects, "STATPROD[D222401]")
  expect_true(
    "select distinct PERSON_ID as PERSON_ID from D222401.PERSONS" %in%
      db$remote_statements
  )
  expect_equal(db$uploads$BEF_ID_PROC, data.frame(PERSON_ID = c(1, 2)))
  expect_equal(db$remote_disconnects, 1)
  expect_length(db$tables, 0)
})

test_that("a missing or unreadable source fails before anything is uploaded", {
  withr::local_envvar(USERNAME = "IKX")
  db <- local_fake_psd(
    source_columns = data.frame(COLUMN_NAME = character(), DATA_TYPE = character())
  )
  expect_error(
    suppressMessages(convert_person_id(
      procedure = "BEF_OMKOD",
      in_data = "ORACLE",
      in_table_name = "D222401.NOPE",
      project_id = "X"
    )),
    "D222401.NOPE does not exist in DB_PSD, or you do not have access"
  )
  expect_length(db$plsql, 0)

  db <- local_fake_psd(source_columns = data.frame(COLUMN_NAME = "ID", DATA_TYPE = "NUMBER"))
  expect_error(
    suppressMessages(convert_person_id(
      procedure = "BEF_OMKOD",
      in_data = "ORACLE",
      in_table_name = "D222401.PERSONS",
      project_id = "X"
    )),
    "no column PNR in D222401.PERSONS. Columns: ID"
  )
  expect_length(db$plsql, 0)
  expect_length(db$tables, 0)
})

test_that("a numeric PNR column in Oracle gives a warning", {
  withr::local_envvar(USERNAME = "IKX")
  db <- local_fake_psd(source_columns = data.frame(COLUMN_NAME = "PNR", DATA_TYPE = "NUMBER"))
  expect_warning(
    suppressMessages(convert_person_id(
      procedure = "BEF_OMKOD",
      in_data = "ORACLE",
      in_table_name = "D222401.PERSONS",
      project_id = "X"
    )),
    "PNR \\(D222401.PERSONS.PNR\\) is numeric"
  )
})

# out_data = "ORACLE" -----------------------------------------------------------

test_that("output kept in DB_PSD is renamed and not dropped", {
  withr::local_envvar(USERNAME = "IKX")
  db <- local_fake_psd()
  msgs <- capture_messages(
    res <- withVisible(convert_person_id(
      procedure = "BEF_OMKOD",
      in_table_name = pnr,
      project_id = "X",
      out_data = "ORACLE",
      out_table_name = "my_ids"
    ))
  )
  expect_false(res$visible)
  expect_equal(res$value, "MY_IDS")
  expect_match(msgs, "Output saved as IKX.MY_IDS in DB_PSD", all = FALSE)
  expect_true("alter table PNROMKOD4711 rename to MY_IDS" %in% db$statements)
  expect_false(any(grepl("^select \\* from", db$statements)))
  expect_equal(db$tables, "MY_IDS")
  expect_length(db$remote_connects, 0)
})

test_that("an existing target table fails before anything is uploaded", {
  withr::local_envvar(USERNAME = "IKX")
  db <- local_fake_psd(leftover = "MY_IDS")
  expect_error(
    suppressMessages(convert_person_id(
      procedure = "BEF_OMKOD",
      in_table_name = pnr,
      project_id = "X",
      out_data = "ORACLE",
      out_table_name = "MY_IDS"
    )),
    "IKX.MY_IDS already exists in DB_PSD"
  )
  expect_length(db$uploads, 0)
  expect_length(db$plsql, 0)
  expect_equal(db$tables, "MY_IDS")

  db <- local_fake_psd(remote = "STATPROD:MY_IDS")
  expect_error(
    suppressMessages(convert_person_id(
      procedure = "BEF_OMKOD",
      in_table_name = pnr,
      project_id = "X",
      out_data = "ORACLE",
      out_table_name = "MY_IDS",
      out_database = "STATPROD",
      proxy = "D222401"
    )),
    "D222401.MY_IDS already exists in STATPROD"
  )
  expect_length(db$plsql, 0)
})

test_that("output for another database is copied in chunks", {
  withr::local_envvar(USERNAME = "IKX")
  withr::local_options(DSTutils.chunk_size = 2)
  out <- data.frame(GL_PERSON_ID = 1:5, NY_PERSON_ID = 11:15)
  db <- local_fake_psd(output = out)
  msgs <- capture_messages(convert_person_id(
    procedure = "BEF_IDSKIFT",
    in_table_name = pid,
    project_id = "X",
    out_data = "ORACLE",
    out_table_name = "IDSKIFT_2024",
    out_database = "STATPROD",
    proxy = "[D222401]"
  ))
  expect_match(msgs, "Output saved as D222401.IDSKIFT_2024 in STATPROD", all = FALSE)
  expect_equal(db$remote_writes[["STATPROD:IDSKIFT_2024"]], out, ignore_attr = TRUE)
  expect_equal(db$remote, "STATPROD:IDSKIFT_2024")
  expect_true(any(grepl("session_privs", db$remote_statements)))
  # The procedure's table in DB_PSD is dropped
  expect_length(db$tables, 0)
  expect_equal(db$remote_disconnects, 1)
})

test_that("input and output in the same other database share a connection", {
  withr::local_envvar(USERNAME = "IKX")
  db <- local_fake_psd(
    source_columns = data.frame(COLUMN_NAME = "PERSON_ID", DATA_TYPE = "NUMBER"),
    source_rows = data.frame(PERSON_ID = 1)
  )
  suppressMessages(convert_person_id(
    procedure = "BEF_IDSKIFT",
    in_data = "ORACLE",
    in_table_name = "D222401.PERSONS",
    out_data = "ORACLE",
    out_table_name = "IDSKIFT_2024",
    database = "STATPROD",
    proxy = "D222401",
    project_id = "X"
  ))
  expect_equal(db$remote_connects, "STATPROD[D222401]")
  expect_equal(db$remote_disconnects, 1)
})

test_that("a target without CREATE TABLE fails before anything is uploaded", {
  withr::local_envvar(USERNAME = "IKX")
  db <- local_fake_psd(remote_create = FALSE)
  expect_error(
    suppressMessages(convert_person_id(
      procedure = "BEF_OMKOD",
      in_table_name = pnr,
      project_id = "X",
      out_data = "ORACLE",
      out_table_name = "MY_IDS",
      out_database = "STATPROD"
    )),
    "IKX does not have privileges to create tables in STATPROD"
  )
  expect_length(db$uploads, 0)
  expect_length(db$plsql, 0)
})

test_that("a failed copy drops the partly written target and the work tables", {
  withr::local_envvar(USERNAME = "IKX")
  withr::local_options(DSTutils.chunk_size = 2)
  db <- local_fake_psd(
    output = data.frame(PNR = letters[1:5], PERSON_ID = 1:5),
    fail_write_at = 4
  )
  expect_error(
    suppressMessages(convert_person_id(
      procedure = "BEF_OMKOD",
      in_table_name = pnr,
      project_id = "X",
      out_data = "ORACLE",
      out_table_name = "MY_IDS",
      out_database = "STATPROD"
    )),
    "Could not write the output to MY_IDS in STATPROD: ORA-01653"
  )
  expect_true("drop table MY_IDS" %in% db$remote_statements)
  expect_length(db$remote, 0)
  expect_length(db$tables, 0)
})

test_that("db_read_chunked() and db_write_table() copy in chunks with DBI", {
  skip_if_not_installed("RSQLite")
  from <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  to <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer({
    DBI::dbDisconnect(from)
    DBI::dbDisconnect(to)
  })
  DBI::dbWriteTable(from, "OUT", data.frame(A = 1:5, B = letters[1:5]))
  DBI::dbWriteTable(from, "EMPTY", data.frame(A = integer()))

  firsts <- logical()
  n <- db_read_chunked(from, "select * from OUT", 2, function(chunk, first) {
    firsts <<- c(firsts, first)
    db_write_table(to, "COPY", chunk, append = !first)
  })
  expect_equal(n, 5)
  expect_equal(firsts, c(TRUE, FALSE, FALSE))
  expect_equal(DBI::dbReadTable(to, "COPY"), DBI::dbReadTable(from, "OUT"))

  # An empty result still creates the table
  n <- db_read_chunked(from, "select * from EMPTY", 2, function(chunk, first) {
    db_write_table(to, "EMPTY_COPY", chunk, append = !first)
  })
  expect_equal(n, 0)
  expect_true(DBI::dbExistsTable(to, "EMPTY_COPY"))
})

# add_person_id() -----------------------------------------------------------------

test_that("add_person_id() drops PNR unless asked to keep it", {
  withr::local_envvar(USERNAME = "IKX")
  data <- data.frame(pnr = c("0101011234", "0101011234"), x = 1:2)
  db <- local_fake_psd()

  res <- suppressMessages(add_person_id(data))
  expect_named(res, c("X", "PERSON_ID"))
  expect_equal(res$PERSON_ID, c(1, 1))
  # Only the distinct PNRs are uploaded
  expect_equal(db$uploads$BEF_ID_PROC, data.frame(PNR = "0101011234"))

  res <- suppressMessages(add_person_id(data, drop_pnr = FALSE))
  expect_named(res, c("PNR", "X", "PERSON_ID"))
})

# Tests against the real DB_PSD -----------------------------------------------

test_that("BEF_AKTUELLE procedures run successfully", {
  skip_if_no_db()

  x <- tibble::tibble(PERSON_ID = c("1234", "2345"))

  test <- convert_person_id(
    procedure = "BEF_AKTUELLE_PNR",
    in_table_name = x,
    out_table_name = "test"
  )

  expect_s3_class(test, "data.frame")
  expect_true("PNR" %in% names(test))

  test1 <- convert_person_id(
    procedure = "BEF_AKTUELLE_PNR",
    in_table_name = x,
    recipient = NULL
  )

  expect_s3_class(test1, "data.frame")

  x2 <- tibble::tibble(PNR = test$PNR)
  test2 <- convert_person_id(
    procedure = "BEF_AKTUELLE_ID",
    in_table_name = x2
  )

  expect_s3_class(test2, "data.frame")
  expect_true("PERSON_ID" %in% names(test2))
})

test_that("BEF_HISTORISK procedures run successfully", {
  skip_if_no_db()

  x <- tibble::tibble(PERSON_ID = c("1234", "2345"))

  test_h0 <- convert_person_id(
    procedure = "BEF_HISTORISK_PNR",
    in_table_name = x,
    validity_date = 31122021
  )
  expect_s3_class(test_h0, "data.frame")

  test_h <- convert_person_id(
    procedure = "BEF_HISTORISK_PNR",
    in_table_name = x,
    project_id = "MZL",
    validity_date = 31122021,
    registry_time = 16012022
  )
  expect_s3_class(test_h, "data.frame")

  # Setup x2 using actual PNRs from test_h0 if needed, but for simplicity
  # we'll use dummy valid PNR format strings if real DB returns actual data
  if (nrow(test_h0) > 0) {
    x2 <- tibble::tibble(PNR = test_h0$PNR)
    test_h2 <- convert_person_id(
      procedure = "BEF_HISTORISK_ID",
      in_table_name = x2,
      validity_date = 31122021,
      registry_time = "16012022 18:00:00"
    )
    expect_s3_class(test_h2, "data.frame")
  }
})

test_that("BEF_FULD_HISTORIK procedures run successfully", {
  skip_if_no_db()

  x <- tibble::tibble(PERSON_ID = c("1234", "2345"))

  test_f <- convert_person_id(
    procedure = "BEF_FULD_HISTORIK_ID",
    in_table_name = x
  )
  expect_s3_class(test_f, "data.frame")

  test_f3 <- convert_person_id(
    procedure = "BEF_FULD_HISTORIK_ID",
    in_table_name = x,
    registry_start_time = "31122000 120303.232",
    registry_end_time = "31129999 235959.999"
  )
  expect_s3_class(test_f3, "data.frame")
})

test_that("KOEN and FOEDSELSDAG procedures work", {
  skip_if_no_db()

  x <- tibble::tibble(PERSON_ID = c("1234", "2345"))

  test_ks_akt <- convert_person_id(
    procedure = "BEF_AKTUEL_KOEN_FOEDSELSDAG",
    in_table_name = x
  )
  expect_s3_class(test_ks_akt, "data.frame")

  test_ks_his <- convert_person_id(
    procedure = "BEF_HISTORISK_KOEN_FOEDSELSDAG",
    in_table_name = x,
    validity_date = 31122021,
    registry_time = 16012022
  )
  expect_s3_class(test_ks_his, "data.frame")
})

test_that("BEF_OMKOD and BEF_INVALIDE procedures work", {
  skip_if_no_db()

  # Test with one valid and one invalid PNR
  x3 <- tibble::tibble(PNR = c("0000101010", "1234567890"))

  test_omk <- convert_person_id(
    procedure = "BEF_OMKOD",
    in_table_name = x3
  )
  expect_s3_class(test_omk, "data.frame")

  test_inv <- convert_person_id(
    procedure = "BEF_INVALIDE"
  )
  expect_s3_class(test_inv, "data.frame")
})

test_that("Oracle input and output within DB_PSD work", {
  skip_if_no_db()

  psd <- DSTdb::get_conn("DB_PSD")
  withr::defer(DBI::dbDisconnect(psd))
  src <- "DSTUTILS_TEST_SRC"
  out <- "DSTUTILS_TEST_OUT"
  drop_test_tables <- function() {
    for (tbl in c(src, out)) {
      if (DBI::dbExistsTable(psd, tbl)) DBI::dbRemoveTable(psd, tbl)
    }
  }
  drop_test_tables()
  withr::defer(drop_test_tables())
  DBI::dbWriteTable(psd, src, data.frame(PERSON_ID = c("1234", "2345", "1234")))

  name <- convert_person_id(
    procedure = "BEF_AKTUELLE_PNR",
    in_data = "ORACLE",
    in_table_name = src,
    out_data = "ORACLE",
    out_table_name = out
  )
  expect_equal(name, out)
  res <- DBI::dbGetQuery(psd, paste("select * from", out))
  expect_true("PNR" %in% names(res))
  # The output table must not exist twice
  expect_error(
    convert_person_id(
      procedure = "BEF_AKTUELLE_PNR",
      in_data = "ORACLE",
      in_table_name = src,
      out_data = "ORACLE",
      out_table_name = out
    ),
    "already exists"
  )
})
