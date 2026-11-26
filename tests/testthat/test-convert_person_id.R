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
    cat(build_bef_plsql(bef_procedure(proc), project_id, recipient, mode, dates))
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
    "not implemented"
  )
  expect_error(
    convert_person_id(procedure = "BEF_OMKOD", in_table_name = pnr, out_data = "ORACLE"),
    "not implemented"
  )
  expect_error(
    convert_person_id(procedure = "BEF_OMKOD", in_table_name = pnr, in_data = "SAS"),
    "must be \"R\" or \"ORACLE\""
  )
  expect_equal(db$connects, 0)
})

test_that("leftovers from an interrupted run are dropped first", {
  withr::local_envvar(USERNAME = "IKX")
  db <- local_fake_psd(leftover = c("BEF_ID_PROC", "PSDMYTEMP"))
  msgs <- capture_messages(
    convert_person_id(procedure = "BEF_OMKOD", in_table_name = pnr, project_id = "X")
  )
  expect_equal(sum(grepl("left in DB_PSD by an earlier", msgs)), 2)
  expect_length(db$tables, 0)
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
