# Person ID conversion via the BEF procedures in DB_PSD ----------------------
#
# For names and explanations of the procedures see "Metodevejledning
# konvertering mellem cpr og person_id..." in
# "G:\k22\01 Metode\Diskretionering\Pseudonymisering". A copy is in the source
# repo (not in the built package):
# inst/docs/Metodevejledning-konvertering-mellem-cpr-og-person_id-240817.pdf.
#
# The Oracle side is not under our control. What is sent to it must stay
# compatible with the procedures, in particular:
# * the Danish PL/SQL parameter names: p_projektnummer, p_bruger,
#   p_ind_tabelnavn, p_gyldighedsdato, p_registerdato, p_registerstarttid,
#   p_registersluttid, p_resultat, p_koerselsid;
# * the package names, the output-table prefixes and the date-argument
#   combinations each procedure accepts (`bef_procedures` below);
# * the input work table BEF_ID_PROC (p_ind_tabelnavn).
# The run table PSDMYTEMP_<time>_<pid> is only used by our own PL/SQL block.
# The generated PL/SQL is snapshot-tested in
# tests/testthat/_snaps/convert_person_id.md, so any change to it shows up in
# review.
#
# Open work is planned in dev/TODO.md.

# Procedure specification -----------------------------------------------------

# `call`: package the procedure is called through.
# `grant`: package the EXECUTE privilege is checked on.
bef_packages <- list(
  laes = list(
    call = "BEF01_pck_laes_personnummer",
    grant = "BEF_PCK_LAES_PERSONNUMMER"
  ),
  omkod = list(
    call = "BEF01_pck_omkodning",
    grant = "BEF_PCK_OMKODNING"
  )
)

# Date modes (which date arguments are sent to the procedure):
# * "none":     no date arguments
# * "validity": p_gyldighedsdato
# * "historic": p_gyldighedsdato + p_registerdato (looked up when not given)
# * "range":    p_registerstarttid + p_registersluttid
bef_proc <- function(prefix, id_column, date_modes, package = "laes") {
  list(
    prefix = prefix,
    id_column = id_column,
    date_modes = date_modes,
    package = bef_packages[[package]]
  )
}

bef_procedures <- list(
  # PNR -> PERSON_ID
  BEF_OMKOD = bef_proc("PNROMKOD", "PNR", c("none", "validity"), "omkod"),
  BEF_AKTUELLE_ID = bef_proc("AKT_ID", "PNR", c("none", "validity")),
  BEF_HISTORISK_ID = bef_proc("HIS_ID", "PNR", "historic"),
  BEF_FULD_HISTORIK_PNR = bef_proc("FULDHISPNR", "PNR", c("none", "range")),
  # PERSON_ID -> PNR
  BEF_AKTUELLE_PNR = bef_proc("AKTPNR", "PERSON_ID", c("none", "validity")),
  BEF_HISTORISK_PNR = bef_proc("HISPNR", "PERSON_ID", "historic"),
  BEF_FULD_HISTORIK_ID = bef_proc("FULDHISID", "PERSON_ID", c("none", "range")),
  # PERSON_ID -> sex and birthday
  BEF_AKTUEL_KOEN_FOEDSELSDAG = bef_proc(
    "AKTKONFOD",
    "PERSON_ID",
    c("none", "validity")
  ),
  BEF_HISTORISK_KOEN_FOEDSELSDAG = bef_proc("HISKONFOD", "PERSON_ID", "historic"),
  BEF_FULD_HIS_KOEN_FOEDSELSDAG = bef_proc(
    "FULDHISKON",
    "PERSON_ID",
    c("none", "range")
  ),
  # PERSON_ID shifts
  BEF_IDSKIFT = bef_proc("IDSKIFT", "PERSON_ID", "none"),
  # Invalid ids; takes no input table
  BEF_INVALIDE = bef_proc("INVALIDE", NA_character_, c("none", "range"))
)

# Main function -----------------------------------------------------------------

#' @title Convert between CPR and PERSON_ID
#'
#' @description Runs one of the BEF conversion procedures in `DB_PSD`
#'   (Oracle) on a set of `PNR`s or `PERSON_ID`s and returns the procedure's
#'   output table, or saves it as an Oracle table.
#'
#' @details
#' **Procedures and their input column**
#'
#' | Procedure | Input column | Date arguments |
#' |---|---|---|
#' | `BEF_OMKOD`, `BEF_AKTUELLE_ID` | `PNR` | none, or `validity_date` |
#' | `BEF_HISTORISK_ID` | `PNR` | `validity_date`, optionally `registry_time` |
#' | `BEF_FULD_HISTORIK_PNR` | `PNR` | none, or `registry_start_time` + `registry_end_time` |
#' | `BEF_AKTUELLE_PNR`, `BEF_AKTUEL_KOEN_FOEDSELSDAG` | `PERSON_ID` | none, or `validity_date` |
#' | `BEF_HISTORISK_PNR`, `BEF_HISTORISK_KOEN_FOEDSELSDAG` | `PERSON_ID` | `validity_date`, optionally `registry_time` |
#' | `BEF_FULD_HISTORIK_ID`, `BEF_FULD_HIS_KOEN_FOEDSELSDAG` | `PERSON_ID` | none, or `registry_start_time` + `registry_end_time` |
#' | `BEF_IDSKIFT` | `PERSON_ID` | none |
#' | `BEF_INVALIDE` | (no input table) | none, or `registry_start_time` + `registry_end_time` |
#'
#' Any other combination of date arguments is an error. For the historic
#' procedures, a missing `registry_time` is looked up in
#' `D101200.bef_leverance_time` (the first delivery covering
#' `validity_date`).
#'
#' **Ids that cannot be found** come back as `PNR = "Ukendt-PNR"` or
#' `PERSON_ID = 999999999999999` (15 nines). A `PNR` stored as a number has
#' lost the leading zero of days 01-09 and will not be found, so a numeric
#' `PNR` column gives a warning. Convert it first, e.g.
#' `sprintf("%010.0f", PNR)`.
#'
#' **Where the input comes from** (`in_data`)
#'
#' * `"R"`: `in_table_name` is a data frame. It is uploaded as it is.
#' * `"ORACLE"`: `in_table_name` is a table name, `"SCHEMA.TABLE"` or
#'   `"TABLE"` (your own schema), in `in_database`. Only the distinct values
#'   of the id column are used. In `DB_PSD` they are copied with
#'   `CREATE TABLE ... AS SELECT`, so nothing passes through R. In other
#'   databases they are read into R and uploaded to `DB_PSD`. Either way, you
#'   need read access to the table.
#'
#' **Where the output goes** (`out_data`)
#'
#' * `"R"`: the output table is returned as a data frame.
#' * `"ORACLE"` with `out_database = "DB_PSD"`: the procedure's output table
#'   is renamed to `out_table_name` and kept in your own schema in `DB_PSD`.
#'   Nothing passes through R. Drop it when you no longer need it.
#' * `"ORACLE"` with another `out_database`: the output is copied in chunks to
#'   a new table `out_table_name` in that database, in your schema or in the
#'   `proxy` schema. Chunk size is set with
#'   `options(DSTutils.chunk_size = )` (default 100 000 rows).
#'
#' `out_table_name` must be a plain Oracle name (letters, digits, `_`, `$`,
#' `#`; starting with a letter) and must not exist yet. You need CREATE TABLE
#' on the target. All these checks are made before anything is uploaded.
#'
#' **Dates and times** are parsed with [lubridate::parse_date_time()] using the
#' orders `ymd HMS`, `dmy HMS`, `mdy HMS`, `ymd HM`, `dmy HM`, `mdy HM`, `ymd`,
#' `dmy` and `mdy`. Each one must be a single value, not a column. A number
#' works for plain dates (`31122021`). Anything with a time must be a string,
#' e.g. `"31-12-2021 12:00:00"`. Milliseconds are kept
#' (`"31129999 235959.999"`).
#'
#' **Character arguments** (`procedure`, `in_data`, `out_data`, `recipient`,
#' `out_table_name`, `project_id`, `in_database`, `out_database`, `proxy`) can
#' be quoted (`procedure = "BEF_OMKOD"`), a bare word
#' (`procedure = BEF_OMKOD`) or a variable holding a string
#' (`procedure = my_proc`).
#'
#' **Side effects in DB_PSD.** The function writes the input to `BEF_ID_PROC`
#' and the run id to `PSDMYTEMP_<time>_<process id>` in your own schema, and
#' the procedure writes its output table there too. All three are dropped when
#' the function exits, also on error, except the output table when it is kept
#' with `out_data = "ORACLE"`. If an earlier, interrupted run left
#' `BEF_ID_PROC` behind, it is dropped first, and so are run tables older than
#' one day. Do not run two conversions at the same time under the same user,
#' because they share `BEF_ID_PROC`.
#'
#' @param procedure Name of the Oracle procedure, e.g. `"BEF_HISTORISK_ID"`
#'   (case-insensitive). See Details.
#' @param database Deprecated. Use `in_database` and `out_database`. If given,
#'   it is the default for both.
#' @param in_data Where the input data is: `"R"` (a data frame) or
#'   `"ORACLE"` (a table in `in_database`). See Details.
#' @param out_data Where the output should go: `"R"` (returned) or `"ORACLE"`
#'   (saved as `out_table_name` in `out_database`). See Details.
#' @param column_name Optional name of the id column in the input, if it is
#'   not already called `PNR`/`PERSON_ID` as the procedure requires. It is
#'   renamed before upload.
#' @param recipient User ident passed to the procedure (`p_bruger`). Defaults
#'   to the Windows user name. `NULL` sends an empty value.
#' @param in_table_name The input: a data frame with the id column the
#'   procedure needs (`PNR` or `PERSON_ID`, any case) when `in_data = "R"`, or
#'   a table name such as `"D222401.MY_TABLE"` when `in_data = "ORACLE"`. Not
#'   used by `BEF_INVALIDE`.
#' @param out_table_name Name of the table to create when
#'   `out_data = "ORACLE"`. Ignored otherwise.
#' @param project_id Project that runs the conversion (`p_projektnummer`),
#'   e.g. `"D101200"`. Only used for logging on the Oracle side. Defaults to the
#'   user ident.
#' @param validity_date Validity date: returns rows where this date lies
#'   between `VFRA` and `VTIL`, e.g. `31122021` or `"2021-12-31"`.
#' @param registry_time Registry time: returns rows where this time lies
#'   between `RFRA` and `RTIL`. Requires `validity_date`.
#' @param registry_start_time,registry_end_time Registry interval, both or
#'   neither: returns rows where `RTIL > registry_start_time` and
#'   `RFRA <= registry_end_time`, e.g. `"01011900 00:00:00"`.
#' @param in_database,out_database Database the input table is read from and
#'   the output table is written to, when `in_data`/`out_data = "ORACLE"`.
#'   Default `"DB_PSD"`. The procedures themselves always run in `DB_PSD`.
#' @param proxy Optional proxy schema for connecting to `in_database` and
#'   `out_database` when they are not `DB_PSD`, e.g. `"D222401"` or
#'   `"[D222401]"` (see `DSTdb::get_conn()`). `DB_PSD` is always used with your
#'   own ident.
#'
#' @return With `out_data = "R"`, a data frame: the output table of the
#'   procedure. With `out_data = "ORACLE"`, the name of the created table,
#'   invisibly.
#'
#' @seealso [add_person_id()] for the common PNR -> PERSON_ID case.
#'
#' @examples
#' \dontrun{
#' # Current PERSON_ID for a set of PNRs
#' pnr <- data.frame(PNR = c("0101011234", "0202024321"))
#' ids <- convert_person_id(
#'   procedure = "BEF_AKTUELLE_ID",
#'   in_table_name = pnr,
#'   project_id = "D101200"
#' )
#'
#' # PNR valid on 31 December 2021 (registry time looked up automatically)
#' pid <- data.frame(PERSON_ID = ids$PERSON_ID)
#' convert_person_id(
#'   procedure = "BEF_HISTORISK_PNR",
#'   in_table_name = pid,
#'   validity_date = 31122021
#' )
#'
#' # Full history within a registry interval
#' convert_person_id(
#'   procedure = "BEF_FULD_HISTORIK_ID",
#'   in_table_name = pid,
#'   registry_start_time = "01011900 00:00:00",
#'   registry_end_time = "31122100 23:59:59"
#' )
#'
#' # PERSON_ID shifts for a table in a project schema on STATPROD, written
#' # back to the same schema
#' convert_person_id(
#'   procedure = "BEF_IDSKIFT",
#'   in_data = "ORACLE",
#'   in_table_name = "D222401.PERSON_ID_TABEL",
#'   in_database = "STATPROD",
#'   out_data = "ORACLE",
#'   out_table_name = "IDSKIFT_2024",
#'   out_database = "STATPROD",
#'   proxy = "D222401",
#'   project_id = "D222401"
#' )
#' }
#' @export
convert_person_id <- function(
  procedure = NULL,
  database = 'DB_PSD',
  in_data = "R",
  out_data = "R",
  column_name = NULL,
  recipient = Sys.getenv("USERNAME"),
  in_table_name = NULL,
  out_table_name = NULL,
  project_id = NULL,
  validity_date = NULL,
  registry_time = NULL,
  registry_start_time = NULL,
  registry_end_time = NULL,
  in_database = NULL,
  out_database = NULL,
  proxy = NULL
) {
  # READ CHARACTER ARGUMENTS ####
  # Quoted, bare word, or a variable holding a string
  caller <- parent.frame()
  database_given <- !missing(database)
  procedure <- arg_as_string(substitute(procedure), caller, "procedure")
  database <- arg_as_string(substitute(database), caller, "database")
  in_data <- arg_as_string(substitute(in_data), caller, "in_data")
  out_data <- arg_as_string(substitute(out_data), caller, "out_data")
  if (!missing(recipient)) {
    recipient <- arg_as_string(substitute(recipient), caller, "recipient")
  }
  out_table_name <- arg_as_string(
    substitute(out_table_name),
    caller,
    "out_table_name"
  )
  project_id <- arg_as_string(substitute(project_id), caller, "project_id")
  in_database <- arg_as_string(substitute(in_database), caller, "in_database")
  out_database <- arg_as_string(substitute(out_database), caller, "out_database")
  proxy <- arg_as_string(substitute(proxy), caller, "proxy")

  # VALIDATE INPUT (before touching the database) ####
  spec <- bef_procedure(procedure)
  procedure <- spec$name

  in_data <- check_location(in_data, "in_data")
  out_data <- check_location(out_data, "out_data")

  if (database_given) {
    message(
      "NOTE: 'database' is deprecated. Use in_database= and out_database=."
    )
  }
  in_database <- check_database(in_database %||% database, "in_database")
  out_database <- check_database(out_database %||% database, "out_database")
  if (!is.null(proxy)) {
    proxy <- check_proxy(proxy)
  }

  input <- NULL
  source <- NULL
  if (!is.na(spec$id_column)) {
    if (is.null(in_table_name)) {
      stop("Angiv navnet p\u00e5 input-tabellen (in_table_name=).", call. = FALSE)
    }
    if (in_data == "R") {
      input <- prepare_input_table(
        in_table_name,
        spec$id_column,
        column_name,
        procedure
      )
    } else {
      source <- parse_source_table(in_table_name, column_name, spec$id_column)
    }
  } else if (!is.null(in_table_name)) {
    message("NOTE: ", procedure, " takes no input table; 'in_table_name' is ignored.")
  }

  if (out_data == "ORACLE") {
    out_table_name <- check_out_table_name(out_table_name)
  } else if (!is.null(out_table_name)) {
    message(
      "NOTE: Variablen 'out_table_name' ignoreres, da output-tabellen returneres i R (out_data=R)."
    )
  }

  date_mode <- resolve_date_mode(
    spec,
    validity_date = validity_date,
    registry_time = registry_time,
    registry_start_time = registry_start_time,
    registry_end_time = registry_end_time
  )
  dates <- parse_conversion_dates(
    date_mode,
    validity_date = validity_date,
    registry_time = registry_time,
    registry_start_time = registry_start_time,
    registry_end_time = registry_end_time
  )

  user <- Sys.getenv("USERNAME")
  if (is.null(project_id)) {
    project_id <- user
    message(paste0(
      "NOTE: Der er ikke angivet et navn for det projekt, der kalder proceduren (ex. project_id='D101200'), derfor anvendes user-ident ",
      user,
      "."
    ))
  }

  # CONNECT; ALL WORK TABLES ARE DROPPED ON EXIT, ALSO ON ERROR ####
  psd <- connect_psd()
  schema <- NULL
  created_tables <- character()
  on.exit(cleanup_psd(psd, created_tables, schema), add = TRUE)

  # Connections to other databases, opened once each when needed
  other_conns <- list()
  on.exit(disconnect_all(other_conns), add = TRUE)
  conn_to <- function(database) {
    if (database == "DB_PSD") {
      return(psd)
    }
    if (is.null(other_conns[[database]])) {
      other_conns[[database]] <<- connect_db(database, proxy)
    }
    other_conns[[database]]
  }

  schema <- db_user(psd)
  check_psd_privileges(psd, spec, user)
  drop_leftover_tables(psd, schema)

  # CHECK SOURCE AND TARGET BEFORE UPLOADING ANYTHING ####
  if (!is.null(source)) {
    in_conn <- conn_to(in_database)
    check_source_table(in_conn, source, in_database)
  }
  if (out_data == "ORACLE") {
    out_conn <- conn_to(out_database)
    out_schema <- if (out_database == "DB_PSD") schema else db_user(out_conn)
    if (out_database != "DB_PSD") {
      check_create_privilege(out_conn, out_database, user)
    }
    if (table_exists(out_conn, out_table_name, out_schema)) {
      stop(
        "The table ",
        out_schema,
        ".",
        out_table_name,
        " already exists in ",
        out_database,
        ". Choose another out_table_name or drop the table first.",
        call. = FALSE
      )
    }
  }

  # UPLOAD INPUT AND RUN THE PROCEDURE ####
  if (!is.null(input) || !is.null(source)) {
    created_tables <- c(created_tables, "BEF_ID_PROC")
  }
  if (!is.null(input)) {
    db_write_table(psd, "BEF_ID_PROC", input)
  } else if (!is.null(source)) {
    copy_source_to_psd(psd, in_conn, source, in_database)
  }

  # The run table receives the procedure's OUT values (result text and run id)
  run_table <- run_table_name()
  created_tables <- c(created_tables, run_table)
  db_execute(
    psd,
    paste0(
      "create table ",
      run_table,
      " (v_resultat VARCHAR2(200), v_koerselsid NUMBER)"
    )
  )

  if (date_mode == "historic" && is.null(dates$registry)) {
    dates$registry <- lookup_registry_time(psd, dates$validity)
  }

  plsql <- build_bef_plsql(
    spec,
    project_id = project_id,
    recipient = recipient,
    date_mode = date_mode,
    dates = dates,
    run_table = run_table
  )
  psd_run_plsql(psd, plsql)

  # COLLECT THE OUTPUT TABLE ####
  run <- read_run_info(psd, run_table)
  message(run$result)

  # The procedure saves its output as <prefix><run id> in the user's schema
  out_name <- paste0(spec$prefix, run$id)
  created_tables <- c(created_tables, out_name)
  if (!table_exists(psd, out_name, schema)) {
    stop(
      "Something went wrong during execution: the output table ",
      out_name,
      " was not created. Procedure result: ",
      run$result,
      call. = FALSE
    )
  }

  if (out_data == "R") {
    return(db_query(psd, paste0("select * from ", out_name)))
  }

  if (out_database == "DB_PSD") {
    # Keep the procedure's table under the requested name
    db_execute(
      psd,
      paste0("alter table ", out_name, " rename to ", out_table_name)
    )
    created_tables <- setdiff(created_tables, out_name)
  } else {
    copy_output(psd, out_name, out_conn, out_table_name, out_schema, out_database)
  }
  message(
    "Output saved as ",
    out_schema,
    ".",
    out_table_name,
    " in ",
    out_database,
    "."
  )
  invisible(out_table_name)
}

# Input handling (no database) ------------------------------------------------

#' Read a character argument given quoted, as a bare word or as a variable
#'
#' Keeps the historical interface where `procedure = BEF_OMKOD` (unquoted)
#' works, while also allowing `procedure = my_proc` and
#' `project_id = paste0(...)`, which the old `deparse(substitute())` approach
#' silently turned into the literal text "my_proc" / "paste0(...)".
#' A bare word is taken as a variable only if a character (or NULL) object of
#' that name exists; otherwise the word itself is used.
#' @noRd
arg_as_string <- function(expr, env, arg) {
  value <- if (is.symbol(expr)) {
    name <- as.character(expr)
    obj <- if (exists(name, envir = env)) get(name, envir = env) else name
    if (is.null(obj) || is.character(obj) || is.factor(obj)) obj else name
  } else {
    eval(expr, env)
  }

  if (is.null(value)) {
    return(NULL)
  }
  if (is.factor(value)) {
    value <- as.character(value)
  }
  if (is.numeric(value) && length(value) == 1) {
    value <- format(value, scientific = FALSE, trim = TRUE)
  }
  if (!is.character(value) || length(value) != 1 || is.na(value)) {
    stop("'", arg, "' must be a single character string.", call. = FALSE)
  }
  value
}

#' Look up the specification of a BEF procedure
#' @noRd
bef_procedure <- function(procedure) {
  if (is.null(procedure)) {
    stop(
      "Specify the name of the Oracle procedure you want to execute (procedure=).",
      call. = FALSE
    )
  }
  name <- toupper(procedure)
  if (!name %in% names(bef_procedures)) {
    stop(
      "The specified Oracle procedure is not recognized: ",
      procedure,
      ". Known procedures: ",
      paste(names(bef_procedures), collapse = ", "),
      ".",
      call. = FALSE
    )
  }
  c(list(name = name), bef_procedures[[name]])
}

#' Validate `in_data` / `out_data`
#' @noRd
check_location <- function(x, arg) {
  if (is.null(x) || !toupper(x) %in% c("R", "ORACLE")) {
    stop("'", arg, "' must be \"R\" or \"ORACLE\".", call. = FALSE)
  }
  toupper(x)
}

# Work-table names that user tables must not collide with
reserved_table_pattern <- "^(BEF_ID_PROC|PSDMYTEMP.*)$"

#' Validate an unquoted Oracle identifier and return it in upper case
#' @noRd
check_identifier <- function(x, what) {
  x <- toupper(x)
  if (!grepl("^[A-Z][A-Z0-9_$#]{0,127}$", x)) {
    stop(
      what,
      " '",
      x,
      "' is not a valid Oracle name: use letters, digits, _, $ and #, ",
      "starting with a letter.",
      call. = FALSE
    )
  }
  x
}

#' Validate a database name (it is passed on to DSTdb::get_conn())
#' @noRd
check_database <- function(x, arg) {
  if (is.null(x)) {
    stop("'", arg, "' must be a database name.", call. = FALSE)
  }
  check_identifier(x, paste0("'", arg, "'"))
}

#' Validate a proxy schema; accepts `D222401` and `[D222401]`
#' @noRd
check_proxy <- function(x) {
  name <- check_identifier(gsub("^\\[|\\]$", "", x), "'proxy'")
  paste0("[", name, "]")
}

#' Validate `out_table_name` for out_data = "ORACLE"
#' @noRd
check_out_table_name <- function(x) {
  if (is.null(x)) {
    stop(
      "Specify the name of the table to create (out_table_name=) when out_data = 'ORACLE'.",
      call. = FALSE
    )
  }
  x <- check_identifier(x, "out_table_name")
  if (grepl(reserved_table_pattern, x)) {
    stop("out_table_name ", x, " is used for a work table. Choose another name.", call. = FALSE)
  }
  x
}

#' Parse "SCHEMA.TABLE" or "TABLE" for in_data = "ORACLE"
#'
#' Returns the schema (NULL for the user's own), the table, the qualified name
#' and the source column, which is uploaded as `id_column`.
#' @noRd
parse_source_table <- function(x, column_name, id_column) {
  if (!is.character(x) || length(x) != 1 || is.na(x)) {
    stop(
      "With in_data = 'ORACLE', 'in_table_name' must be a table name such as \"D222401.MY_TABLE\".",
      call. = FALSE
    )
  }
  parts <- strsplit(x, ".", fixed = TRUE)[[1]]
  if (length(parts) > 2) {
    stop("in_table_name '", x, "' must be \"SCHEMA.TABLE\" or \"TABLE\".", call. = FALSE)
  }
  table <- check_identifier(parts[length(parts)], "in_table_name")
  schema <- if (length(parts) == 2) check_identifier(parts[1], "The schema in in_table_name")
  if (grepl(reserved_table_pattern, table)) {
    stop(
      "in_table_name ",
      table,
      " has the name of a work table, which is replaced during the run. ",
      "Copy it to another name first.",
      call. = FALSE
    )
  }
  column <- check_identifier(column_name %||% id_column, "column_name")
  list(
    schema = schema,
    table = table,
    qualified = paste(c(schema, table), collapse = "."),
    column = column,
    id_column = id_column
  )
}

#' Check the input data frame and give the id column the required name
#' @noRd
prepare_input_table <- function(data, id_column, column_name, procedure) {
  if (!is.data.frame(data)) {
    stop(
      "'in_table_name' must be a data frame with a ",
      id_column,
      " column. ",
      "To read the input from an Oracle table, use in_data = 'ORACLE'.",
      call. = FALSE
    )
  }

  names(data) <- toupper(names(data))
  dups <- unique(names(data)[duplicated(names(data))])
  if (length(dups) > 0) {
    stop(
      "Column names in the input table must be unique regardless of case. ",
      "Duplicated: ",
      paste(dups, collapse = ", "),
      call. = FALSE
    )
  }

  if (!is.null(column_name)) {
    column_name <- toupper(column_name)
    if (!column_name %in% names(data)) {
      stop(
        "There is no column ",
        column_name,
        " (column_name=) in the input table.",
        call. = FALSE
      )
    }
    if (column_name != id_column) {
      if (id_column %in% names(data)) {
        stop(
          "The input table has both ",
          column_name,
          " (column_name=) and ",
          id_column,
          ". Drop or rename one of them.",
          call. = FALSE
        )
      }
      names(data)[names(data) == column_name] <- id_column
      message(
        "NOTE: Column ",
        column_name,
        " is uploaded as ",
        id_column,
        ", the name ",
        procedure,
        " requires."
      )
    }
  }

  if (!id_column %in% names(data)) {
    stop(
      paste0("There is no column ", id_column, " in the input table."),
      call. = FALSE
    )
  }
  warn_numeric_pnr(is.numeric(data[[id_column]]), id_column)
  data
}

#' Warn that numeric PNRs have lost their leading zero
#' @noRd
warn_numeric_pnr <- function(is_numeric, id_column, where = "") {
  if (id_column == "PNR" && is_numeric) {
    warning(
      "PNR",
      where,
      " is numeric. PNRs with day 01-09 have lost their leading zero ",
      "and will not be found. Convert them to 10-character strings first, ",
      "e.g. sprintf(\"%010.0f\", PNR) in R or TO_CHAR(PNR, 'FM0000000000') in Oracle.",
      call. = FALSE
    )
  }
}

#' Decide which date arguments are sent to the procedure
#'
#' Returns one of "none", "validity", "historic" or "range"; see
#' `bef_procedures`.
#' @noRd
resolve_date_mode <- function(
  spec,
  validity_date = NULL,
  registry_time = NULL,
  registry_start_time = NULL,
  registry_end_time = NULL
) {
  has_validity <- !is.null(validity_date)
  has_registry <- !is.null(registry_time)
  has_start <- !is.null(registry_start_time)
  has_end <- !is.null(registry_end_time)

  if (xor(has_start, has_end)) {
    stop(
      "En af parameterene registry_start_time eller registry_end_time er udfyldt, enten skal begge eller ingen v\u00e6re udfyldt.",
      call. = FALSE
    )
  }

  supplied <- if (has_start) {
    if (has_validity || has_registry) "invalid" else "range"
  } else if (has_validity) {
    if (has_registry) "validity+registry" else "validity"
  } else if (has_registry) {
    "invalid"
  } else {
    "none"
  }

  modes <- spec$date_modes
  mode <- switch(
    supplied,
    none = if ("none" %in% modes) "none",
    validity = if ("validity" %in% modes) {
      "validity"
    } else if ("historic" %in% modes) {
      "historic"
    },
    `validity+registry` = if ("historic" %in% modes) "historic",
    range = if ("range" %in% modes) "range",
    invalid = NULL
  )

  if (is.null(mode)) {
    allowed <- c(
      none = "no date arguments",
      validity = "validity_date",
      historic = "validity_date (optionally with registry_time)",
      range = "registry_start_time + registry_end_time"
    )[modes]
    stop(
      "Der er et problem med kombinationen af procedure og de angivne dato- og tidsparametre.\n",
      spec$name,
      " accepts: ",
      paste(allowed, collapse = "; or "),
      ".",
      call. = FALSE
    )
  }
  mode
}

#' Parse a single date/time argument into Oracle-ready strings
#' @noRd
parse_datetime_arg <- function(x, arg) {
  if (length(x) != 1) {
    stop(
      "'",
      arg,
      "' must be a single value; a column of dates is not supported.",
      call. = FALSE
    )
  }
  parsed <- suppressWarnings(extract_date_time(x))
  if (is.na(parsed$date) || is.na(parsed$time)) {
    stop("Ukendt format for '", arg, "'.", call. = FALSE)
  }
  date <- format(parsed$date, "%Y-%m-%d")
  list(date = date, datetime = paste(date, parsed$time))
}

#' Parse the date arguments that the chosen date mode uses
#' @noRd
parse_conversion_dates <- function(
  date_mode,
  validity_date = NULL,
  registry_time = NULL,
  registry_start_time = NULL,
  registry_end_time = NULL
) {
  dates <- list()
  if (date_mode %in% c("validity", "historic")) {
    dates$validity <- parse_datetime_arg(validity_date, "validity_date")$date
  }
  if (date_mode == "historic" && !is.null(registry_time)) {
    dates$registry <- parse_datetime_arg(registry_time, "registry_time")$datetime
  }
  if (date_mode == "range") {
    dates$start <- parse_datetime_arg(
      registry_start_time,
      "registry_start_time"
    )$datetime
    dates$end <- parse_datetime_arg(registry_end_time, "registry_end_time")$datetime
  }
  dates
}

# PL/SQL ------------------------------------------------------------------------

#' Quote a value as an Oracle string literal; NULL becomes ''
#' @noRd
sql_string <- function(x) {
  if (is.null(x)) {
    return("''")
  }
  paste0("'", gsub("'", "''", x, fixed = TRUE), "'")
}

sql_date <- function(x) {
  paste0("TO_DATE(", sql_string(x), ", 'YYYY-MM-DD')")
}

sql_timestamp <- function(x) {
  paste0("TO_TIMESTAMP(", sql_string(x), ", 'YYYY-MM-DD HH24:MI:SS.FF')")
}

#' Name of the table that receives the procedure's OUT values
#'
#' Unique per process and second, so concurrent runs (and a SAS job using the
#' old fixed name PSDMYTEMP) do not share it. At most 28 characters, within
#' the 30-character limit of older Oracle versions.
#' @noRd
run_table_name <- function(time = Sys.time(), pid = Sys.getpid()) {
  paste0("PSDMYTEMP_", format(time, "%y%m%d%H%M%S"), "_", pid %% 100000)
}

#' Build the anonymous PL/SQL block that runs a BEF procedure
#'
#' The procedure creates its output table <prefix><run id> in the user's
#' schema. Its OUT values are stored in `run_table` so R can find that table.
#' @noRd
build_bef_plsql <- function(spec, project_id, recipient, date_mode, dates, run_table) {
  args <- c(
    p_projektnummer = sql_string(project_id),
    p_bruger = sql_string(recipient),
    if (!is.na(spec$id_column)) c(p_ind_tabelnavn = "'BEF_ID_PROC'"),
    switch(
      date_mode,
      none = NULL,
      validity = c(p_gyldighedsdato = sql_date(dates$validity)),
      historic = c(
        p_gyldighedsdato = sql_date(dates$validity),
        p_registerdato = sql_timestamp(dates$registry)
      ),
      range = c(
        p_registerstarttid = sql_timestamp(dates$start),
        p_registersluttid = sql_timestamp(dates$end)
      )
    ),
    p_resultat = "v_resultat",
    p_koerselsid = "v_koerselsid"
  )
  arg_names <- formatC(names(args), width = -max(nchar(names(args))))

  paste0(
    "DECLARE\n",
    "  v_resultat   VARCHAR2(200);\n",
    "  v_koerselsid NUMBER;\n",
    "BEGIN\n",
    "  ",
    spec$package$call,
    ".",
    spec$name,
    "(\n",
    paste0("    ", arg_names, " => ", args, collapse = ",\n"),
    "\n  );\n",
    "  -- Store the OUT values so R can find the output table\n",
    "  insert into ",
    run_table,
    " values (v_resultat, v_koerselsid);\n",
    "  COMMIT;\n",
    "END;"
  )
}

#' Format the run id for use in a table name (never scientific notation)
#' @noRd
format_run_id <- function(id) {
  sprintf("%.0f", as.numeric(id))
}

# Database steps ----------------------------------------------------------------
# Thin wrappers so the flow can be tested with a fake database.

psd_connect <- function() {
  DSTdb::get_conn('DB_PSD', namespace = "bef_personnummer")
}

db_connect <- function(database, proxy = NULL) {
  args <- list(database, namespace = "bef_personnummer")
  if (!is.null(proxy)) {
    args$proxy <- proxy
  }
  do.call(DSTdb::get_conn, args)
}

db_query <- function(conn, sql) {
  DBI::dbGetQuery(conn, sql)
}

db_execute <- function(conn, sql) {
  res <- DBI::dbSendQuery(conn, sql)
  DBI::dbClearResult(res)
  invisible(TRUE)
}

db_write_table <- function(conn, name, data, append = FALSE) {
  DBI::dbWriteTable(conn, name, data, append = append)
}

#' Run a query and pass the result to `write_chunk()` in chunks
#'
#' `write_chunk(chunk, first)` is called at least once, so a zero-row result
#' still creates the target table. Returns the number of rows.
#' @noRd
db_read_chunked <- function(conn, sql, chunk_size, write_chunk) {
  res <- DBI::dbSendQuery(conn, sql)
  on.exit(DBI::dbClearResult(res), add = TRUE)
  n <- 0
  repeat {
    chunk <- DBI::dbFetch(res, n = chunk_size)
    if (n > 0 && nrow(chunk) == 0) {
      break
    }
    write_chunk(chunk, first = n == 0)
    n <- n + nrow(chunk)
    if (DBI::dbHasCompleted(res)) {
      break
    }
  }
  n
}

psd_run_plsql <- function(conn, plsql) {
  ROracle::oracleProc(conn, plsql)
}

db_disconnect <- function(conn) {
  DBI::dbDisconnect(conn)
}

#' The Oracle user (schema) of a connection
#' @noRd
db_user <- function(conn) {
  db_query(conn, "SELECT USER AS SCHEMA_NAME FROM DUAL")$SCHEMA_NAME
}

#' Connect to DB_PSD with a readable error if that is not possible
#' @noRd
connect_psd <- function() {
  tryCatch(
    psd_connect(),
    error = function(e) {
      stop(
        "Could not connect to DB_PSD. Check that you have been granted access to PSD.\n",
        conditionMessage(e),
        call. = FALSE
      )
    }
  )
}

#' Connect to a database other than DB_PSD, optionally through a proxy schema
#' @noRd
connect_db <- function(database, proxy = NULL) {
  tryCatch(
    db_connect(database, proxy),
    error = function(e) {
      stop(
        "Could not connect to ",
        database,
        if (!is.null(proxy)) paste0(" with proxy ", proxy),
        ".\n",
        conditionMessage(e),
        call. = FALSE
      )
    }
  )
}

#' Close connections, ignoring errors (runs from on.exit())
#' @noRd
disconnect_all <- function(conns) {
  for (conn in conns) {
    tryCatch(db_disconnect(conn), error = function(e) invisible(NULL))
  }
}

#' Check CREATE TABLE on a connection
#'
#' `session_privs` includes privileges granted through roles, which
#' `user_sys_privs` misses.
#' @noRd
check_create_privilege <- function(conn, database, user) {
  create_rights <- db_query(
    conn,
    "SELECT privilege FROM session_privs WHERE privilege = 'CREATE TABLE'"
  )
  if (nrow(create_rights) == 0) {
    stop(
      user,
      " does not have privileges to create tables in ",
      database,
      ".",
      call. = FALSE
    )
  }
}

#' Check CREATE TABLE in DB_PSD and EXECUTE on the procedure's package
#'
#' `all_tab_privs` includes privileges granted through roles and to PUBLIC,
#' which `user_tab_privs` misses.
#' @noRd
check_psd_privileges <- function(conn, spec, user) {
  check_create_privilege(conn, "DB_PSD", user)

  proc_rights <- db_query(
    conn,
    paste0(
      "SELECT privilege FROM all_tab_privs WHERE table_name = '",
      spec$package$grant,
      "'"
    )
  )
  if (nrow(proc_rights) == 0) {
    stop(
      user,
      " does not have privileges to execute the procedure ",
      spec$name,
      call. = FALSE
    )
  }
}

#' Check that the source table exists, is readable and has the id column
#'
#' `all_tab_columns` lists the tables and views the user can read.
#' @noRd
check_source_table <- function(conn, source, database) {
  owner <- if (is.null(source$schema)) "USER" else sql_string(source$schema)
  cols <- db_query(
    conn,
    paste0(
      "SELECT column_name, data_type FROM all_tab_columns WHERE owner = ",
      owner,
      " AND table_name = ",
      sql_string(source$table)
    )
  )
  names(cols) <- toupper(names(cols))
  if (nrow(cols) == 0) {
    stop(
      "The table ",
      source$qualified,
      " does not exist in ",
      database,
      ", or you do not have access to read it.",
      call. = FALSE
    )
  }
  if (!source$column %in% cols$COLUMN_NAME) {
    stop(
      "There is no column ",
      source$column,
      " in ",
      source$qualified,
      ". Columns: ",
      paste(cols$COLUMN_NAME, collapse = ", "),
      ". Use column_name= for the id column.",
      call. = FALSE
    )
  }
  type <- cols$DATA_TYPE[cols$COLUMN_NAME == source$column][1]
  warn_numeric_pnr(
    identical(type, "NUMBER"),
    source$id_column,
    paste0(" (", source$qualified, ".", source$column, ")")
  )
  invisible(TRUE)
}

#' Create BEF_ID_PROC in DB_PSD from the distinct ids of an Oracle table
#'
#' Within DB_PSD the copy is made by Oracle; from other databases the ids are
#' read into R and uploaded.
#' @noRd
copy_source_to_psd <- function(psd, in_conn, source, database) {
  select <- paste0(
    "select distinct ",
    source$column,
    " as ",
    source$id_column,
    " from ",
    source$qualified
  )
  if (database == "DB_PSD") {
    db_execute(psd, paste0("create table BEF_ID_PROC as ", select))
  } else {
    ids <- db_query(in_conn, select)
    names(ids) <- toupper(names(ids))
    warn_numeric_pnr(is.numeric(ids[[source$id_column]]), source$id_column)
    db_write_table(psd, "BEF_ID_PROC", ids)
  }
  if (source$column != source$id_column) {
    message(
      "NOTE: Column ",
      source$column,
      " is uploaded as ",
      source$id_column,
      "."
    )
  }
}

#' Copy the output table from DB_PSD to a new table in another database
#'
#' Reads and writes in chunks. If writing fails, the partly written target is
#' dropped.
#' @noRd
copy_output <- function(psd, from, to_conn, to, to_schema, database) {
  chunk_size <- getOption("DSTutils.chunk_size", 100000)
  tryCatch(
    db_read_chunked(
      psd,
      paste0("select * from ", from),
      chunk_size,
      function(chunk, first) {
        db_write_table(to_conn, to, chunk, append = !first)
      }
    ),
    error = function(e) {
      tryCatch(
        if (table_exists(to_conn, to, to_schema)) {
          db_execute(to_conn, paste0("drop table ", to))
        },
        error = function(e2) {
          warning(
            "Could not drop the partly written table ",
            to,
            " in ",
            database,
            "; drop it manually. ",
            conditionMessage(e2),
            call. = FALSE
          )
        }
      )
      stop(
        "Could not write the output to ",
        to,
        " in ",
        database,
        ": ",
        conditionMessage(e),
        call. = FALSE
      )
    }
  )
}

#' Drop work tables left behind by an interrupted earlier run
#'
#' BEF_ID_PROC would make the upload fail. Run tables are unique per run, so
#' only those older than a day are dropped; a newer one may belong to a run
#' that is still going.
#' @noRd
drop_leftover_tables <- function(conn, schema) {
  if (table_exists(conn, "BEF_ID_PROC", schema)) {
    message(
      "NOTE: Dropping table BEF_ID_PROC left in DB_PSD by an earlier, interrupted run."
    )
    db_execute(conn, "drop table BEF_ID_PROC")
  }

  tryCatch(
    {
      stale <- db_query(
        conn,
        paste0(
          "SELECT object_name FROM user_objects WHERE object_type = 'TABLE' ",
          "AND object_name LIKE 'PSDMYTEMP\\_%' ESCAPE '\\' ",
          "AND created < SYSDATE - 1"
        )
      )
      for (tbl in stale[[1]]) {
        db_execute(conn, paste0("drop table ", tbl))
      }
    },
    error = function(e) {
      warning(
        "Could not drop old PSDMYTEMP_ tables in DB_PSD. ",
        conditionMessage(e),
        call. = FALSE
      )
    }
  )
}

#' Find the registry time for a validity date in D101200.bef_leverance_time
#'
#' Fetched as text, so the value is not shifted by a time-zone round trip
#' through POSIXct. Trailing zeros of the fraction are removed
#' ("18:00:00.000000" becomes "18:00:00").
#' @noRd
lookup_registry_time <- function(conn, validity_date) {
  tid <- db_query(
    conn,
    paste0(
      "select TO_CHAR(min(CAST(time_stamp AS TIMESTAMP)), ",
      "'YYYY-MM-DD HH24:MI:SS.FF6') as TID ",
      "from D101200.bef_leverance_time ",
      "where trunc(cpr_slut) >= ",
      sql_date(validity_date)
    )
  )$TID
  if (length(tid) == 0 || is.na(tid[1])) {
    stop(
      paste(
        "Gyldighedsdato",
        validity_date,
        "findes ikke i PSD registry_time tabellen."
      ),
      call. = FALSE
    )
  }
  tid <- trim_fraction(as.character(tid[1]))
  message(paste(
    "The registry datetime used is =",
    tid,
    "fetched from the PSD table D101200.bef_leverance_time."
  ))
  tid
}

#' Drop trailing zeros from the fractional seconds of a timestamp string
#' @noRd
trim_fraction <- function(x) {
  sub("\\.0+$", "", sub("(\\.[0-9]*[1-9])0+$", "\\1", x))
}

#' Read the procedure's result text and run id from the run table
#' @noRd
read_run_info <- function(conn, run_table) {
  run <- db_query(
    conn,
    paste0(
      "select v_resultat as RESULTAT, v_koerselsid as KOERSELSID from ",
      run_table
    )
  )
  if (nrow(run) == 0 || all(is.na(run$KOERSELSID))) {
    stop(
      "Something went wrong during execution: the procedure returned no run id.",
      if (nrow(run) > 0) paste0(" Procedure result: ", run$RESULTAT[1]),
      call. = FALSE
    )
  }
  i <- which.max(run$KOERSELSID)
  list(result = run$RESULTAT[i], id = format_run_id(run$KOERSELSID[i]))
}

#' Drop the work tables this call created, then disconnect
#'
#' Runs from on.exit(), so it must not throw: failures become warnings.
#' @noRd
cleanup_psd <- function(conn, tables, schema) {
  for (tbl in rev(unique(tables))) {
    tryCatch(
      if (table_exists(conn, tbl, schema)) {
        db_execute(conn, paste0("drop table ", tbl))
      },
      error = function(e) {
        warning(
          "Could not drop the table ",
          tbl,
          " in DB_PSD; drop it manually. ",
          conditionMessage(e),
          call. = FALSE
        )
      }
    )
  }
  tryCatch(db_disconnect(conn), error = function(e) invisible(NULL))
}
