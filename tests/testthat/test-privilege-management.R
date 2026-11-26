new_log_file <- function() {
  file.path(withr_tempdir(), "privilege_log.csv")
}

withr_tempdir <- function() {
  dir <- tempfile("privlog-")
  dir.create(dir)
  dir
}

test_that("ID lists are split on commas, spaces and new lines", {
  expect_equal(parse_id_list("ikx, x00\nX01;x02  ikx"), c("IKX", "X00", "X01", "X02"))
  expect_equal(parse_id_list(c("A", "B")), c("A", "B"))
  expect_equal(parse_id_list(NULL), character())
  expect_equal(parse_id_list(" , "), character())
})

test_that("plans expand tables x grantees into SQL", {
  res <- build_privilege_plan(
    "GRANT", "READ", c("T1", "T2"), "ikx, x00", "d123456", "ticket 1"
  )
  expect_length(res$problems, 0)
  expect_equal(nrow(res$plan), 4)
  expect_true("GRANT READ ON D123456.T1 TO IKX" %in% res$plan$sql)

  rev <- build_privilege_plan("REVOKE", "READ", "T1", "IKX", "D123456", "x")
  expect_equal(rev$plan$sql, "REVOKE READ ON D123456.T1 FROM IKX")
})

test_that("unsafe or incomplete input is rejected", {
  problems <- function(...) build_privilege_plan(...)$problems

  expect_match(problems("GRANT", "READ", "T1", "IKX", "S1", ""), "reason", all = FALSE)
  expect_match(problems("GRANT", "READ", "T1", "PUBLIC", "S1", "n"), "PUBLIC", all = FALSE)
  expect_match(problems("GRANT", "READ", "T1", "S1", "S1", "n"), "owns", all = FALSE)
  expect_match(problems("GRANT", "DROP", "T1", "IKX", "S1", "n"), "Unsupported", all = FALSE)
  expect_match(
    problems("GRANT", "READ", "T1", "IKX'--", "S1", "n"),
    "Not a valid Oracle name",
    all = FALSE
  )
  expect_match(problems("GRANT", "READ", NULL, "IKX", "S1", "n"), "table", all = FALSE)
})

test_that("plans flag privileges that already exist", {
  current <- data.frame(grantee = "IKX", table_name = "T1", privilege = "READ")
  res <- build_privilege_plan("GRANT", "READ", "T1", "IKX, X00", "S1", "n", current)
  expect_equal(res$plan$currently_granted[res$plan$grantee == "IKX"], TRUE)
  expect_equal(res$plan$currently_granted[res$plan$grantee == "X00"], FALSE)
})

test_that("the log round-trips awkward notes and lists newest first", {
  log_file <- new_log_file()
  expect_equal(nrow(read_privilege_log(log_file)), 0)

  append_privilege_log(log_file, data.frame(
    timestamp = "2026-01-01 10:00:00 +0100", action = "GRANT",
    note = "comma, \"quote\"\nnew line", status = "OK"
  ))
  append_privilege_log(log_file, data.frame(
    timestamp = "2026-02-01 10:00:00 +0100", action = "REVOKE", status = "OK"
  ))

  log <- read_privilege_log(log_file)
  expect_named(log, privilege_log_columns)
  expect_equal(log$action, c("REVOKE", "GRANT"))
  expect_equal(log$note[2], "comma, \"quote\" new line")
  expect_false(file.exists(paste0(log_file, ".lock")))
})

test_that("a log from the first app version is upgraded with a backup", {
  log_file <- new_log_file()
  writeLines(
    c(
      "timestamp,grantee,table_name,schema,privilege,granted_by,note",
      "2026-03-17 11:04:56,IKX,LIFELINES,D221911,READ,IKX,test"
    ),
    log_file
  )
  legacy <- read_privilege_log(log_file)
  expect_equal(legacy$performed_by, "IKX")
  expect_equal(legacy$action, "GRANT")

  append_privilege_log(log_file, data.frame(timestamp = "2026-11-26 09:00:00", action = "GRANT"))
  expect_length(list.files(dirname(log_file), pattern = "\\.bak-"), 1)
  log <- read_privilege_log(log_file)
  expect_equal(nrow(log), 2)
  expect_equal(log$table_name[2], "LIFELINES")
})

test_that("file locks time out, and stale locks are cleared", {
  log_file <- new_log_file()
  lock <- paste0(log_file, ".lock")
  dir.create(lock)
  expect_error(with_file_lock(log_file, 1, timeout = 0.3), "Could not lock")
  Sys.setFileTime(lock, Sys.time() - 600)
  expect_equal(with_file_lock(log_file, 42), 42)
  expect_false(dir.exists(lock))
})

test_that("an unwritable log directory is caught before the app starts", {
  skip_on_os("windows")
  dir <- withr_tempdir()
  Sys.chmod(dir, "0555")
  on.exit(Sys.chmod(dir, "0755"))
  skip_if(file.access(dir, 2) == 0, "running as a user that ignores permissions")
  expect_error(privilege_log_prepare(dir), "not writable")
})

test_that("log directory falls back from argument to option to env var to user dir", {
  old <- options(DSTutils.privilege_log_dir = NULL)
  on.exit(options(old))
  withr_env <- Sys.getenv("DSTUTILS_PRIVILEGE_LOG_DIR", unset = NA)
  on.exit(
    if (is.na(withr_env)) Sys.unsetenv("DSTUTILS_PRIVILEGE_LOG_DIR") else Sys.setenv(DSTUTILS_PRIVILEGE_LOG_DIR = withr_env),
    add = TRUE
  )
  Sys.unsetenv("DSTUTILS_PRIVILEGE_LOG_DIR")

  expect_match(privilege_log_dir(), "DSTutils")
  Sys.setenv(DSTUTILS_PRIVILEGE_LOG_DIR = "/env/dir")
  expect_equal(privilege_log_dir(), "/env/dir")
  options(DSTutils.privilege_log_dir = "/opt/dir")
  expect_equal(privilege_log_dir(), "/opt/dir")
  expect_equal(privilege_log_dir("/arg/dir"), "/arg/dir")
})

test_that("executing a plan logs every attempt, including failures", {
  log_file <- new_log_file()
  backend <- new_dry_run_backend("STATPROD", "D123456")
  plan <- build_privilege_plan(
    "GRANT", "READ", c("LIFELINES", "NO_SUCH_TABLE"), "X00, ZZTOP", "D123456", "req 7"
  )$plan

  res <- execute_privilege_plan(backend, plan, "req 7", "TESTER", log_file)
  expect_equal(sum(res$status == "OK"), 1)
  expect_match(res$error[res$grantee == "ZZTOP" & res$table_name == "LIFELINES"], "ORA-01917")
  expect_match(res$error[res$table_name == "NO_SUCH_TABLE"][1], "ORA-00942")

  log <- read_privilege_log(log_file)
  expect_equal(nrow(log), 4)
  expect_setequal(log$status, c("OK", "FAILED"))
  expect_true(all(log$performed_by == "TESTER"))
  expect_true(all(log$note == "req 7"))
  expect_length(unique(log$batch_id), 1)
  expect_true("X00|LIFELINES|READ" %in% grant_key(backend$list_grants()))

  rev <- build_privilege_plan("REVOKE", "READ", "LIFELINES", "X00, Y99", "D123456", "done")$plan
  res <- execute_privilege_plan(backend, rev, "done", "TESTER", log_file)
  expect_equal(res$status, c("OK", "FAILED"))
  expect_false("X00|LIFELINES|READ" %in% grant_key(backend$list_grants()))
})

test_that("a failing log write stops the batch", {
  backend <- new_dry_run_backend("STATPROD", "D123456")
  plan <- build_privilege_plan("GRANT", "READ", "LIFELINES", "A1, A2, A3", "D123456", "n")$plan
  bad_log <- file.path(tempfile(), "missing-dir", "privilege_log.csv")

  res <- suppressWarnings(execute_privilege_plan(backend, plan, "n", "TESTER", bad_log))
  expect_equal(res$status, c("OK - NOT LOGGED", "NOT RUN", "NOT RUN"))
})

test_that("reconciliation flags grants missing from the log and vice versa", {
  live <- data.frame(
    grantee = c("IKX", "X01"),
    table_name = c("T1", "T2"),
    privilege = "READ",
    grantor = "S1"
  )
  log <- standardize_privilege_log(data.frame(
    timestamp = c("2026-03-01", "2026-02-01", "2026-01-01"),
    database = "DB",
    schema = "S1",
    action = c("GRANT", "GRANT", "GRANT"),
    privilege = "READ",
    table_name = c("T1", "T9", "T2"),
    grantee = c("IKX", "OLD", "X01"),
    status = c("OK", "OK", "FAILED"),
    note = c("why", "gone", "failed one")
  ))

  res <- reconcile_grants(live, log, "DB", "S1")
  expect_equal(res$live$logged[res$live$grantee == "IKX"], "yes")
  expect_equal(res$live$note[res$live$grantee == "IKX"], "why")
  expect_equal(res$live$logged[res$live$grantee == "X01"], "NOT IN LOG")
  expect_equal(res$missing$grantee, "OLD")
})

test_that("the app runs end to end in dry-run mode", {
  log_file <- new_log_file()
  server <- privilege_app_server(dry_run = TRUE, log_file = log_file)

  shiny::testServer(server, {
    session$setInputs(database = "STATPROD", schema = " [d123456] ", connect = 1)
    expect_equal(rv$backend$schema, "D123456")
    expect_true("LIFELINES" %in% rv$tables)

    session$setInputs(
      action = "GRANT",
      privilege = "READ",
      tables = c("LIFELINES", "BEF_2020"),
      grantees = "x00\nx02",
      note = "request by mail"
    )
    session$setInputs(review = 1)
    expect_equal(nrow(rv$plan), 4)

    session$setInputs(confirm = 1)
    expect_true(all(rv$result$status == "OK"))
    expect_null(rv$plan)

    log <- read_privilege_log(log_file)
    expect_equal(nrow(log), 4)
    expect_true(all(log$schema == "D123456"))
    expect_true(all(log$performed_by == current_user()))

    # X01 was granted in the simulated DB but never through the app
    rec <- reconciled()
    expect_equal(rec$live$logged[rec$live$grantee == "X01"], "NOT IN LOG")
    expect_equal(sum(rec$live$logged == "yes"), 4)

    # Missing reason: no plan is created
    session$setInputs(note = "  ", review = 2)
    expect_null(rv$plan)
  })
})
