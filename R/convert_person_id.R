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
# * the work tables BEF_ID_PROC (input) and PSDMYTEMP (run id).
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
#'   (Oracle) on a data frame of `PNR`s or `PERSON_ID`s and returns the
#'   procedure's output table.
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
#' `PERSON_ID = 999999999999999` (15 nines).
#'
#' **Dates and times** are parsed with [lubridate::parse_date_time()] using the
#' orders `ymd HMS`, `dmy HMS`, `mdy HMS`, `ymd HM`, `dmy HM`, `mdy HM`, `ymd`,
#' `dmy` and `mdy`. Each one must be a single value, not a column. A number
#' works for plain dates (`31122021`). Anything with a time must be a string,
#' e.g. `"31-12-2021 12:00:00"`. Milliseconds are kept
#' (`"31129999 235959.999"`).
#'
#' **Character arguments** (`procedure`, `database`, `in_data`, `out_data`,
#' `recipient`, `out_table_name`, `project_id`) can be quoted
#' (`procedure = "BEF_OMKOD"`), a bare word (`procedure = BEF_OMKOD`) or a
#' variable holding a string (`procedure = my_proc`).
#'
#' **Side effects in DB_PSD.** The function writes the input to `BEF_ID_PROC`
#' and the run id to `PSDMYTEMP` in your own schema, and the procedure writes
#' its output table there too. All three are dropped when the function exits,
#' also on error. If an earlier, interrupted run left `BEF_ID_PROC` or
#' `PSDMYTEMP` behind, they are dropped first. Do not run two conversions at
#' the same time under the same user, because they share these table names.
#'
#' @param procedure Name of the Oracle procedure, e.g. `"BEF_HISTORISK_ID"`
#'   (case-insensitive). See Details.
#' @param database Reserved for reading/writing data in other databases once
#'   `in_data`/`out_data = "ORACLE"` is implemented. The procedures always run
#'   in `DB_PSD`.
#' @param in_data Where the input data is: `"R"`. `"ORACLE"` is not
#'   implemented yet.
#' @param out_data Where the output should go: `"R"` (returned). `"ORACLE"` is
#'   not implemented yet.
#' @param column_name Optional name of the id column in `in_table_name`, if it
#'   is not already called `PNR`/`PERSON_ID` as the procedure requires. It is
#'   renamed before upload.
#' @param recipient User ident passed to the procedure (`p_bruger`). Defaults
#'   to the Windows user name. `NULL` sends an empty value.
#' @param in_table_name A data frame with the id column the procedure needs
#'   (`PNR` or `PERSON_ID`, any case). Not used by `BEF_INVALIDE`.
#' @param out_table_name Name of the output table when `out_data = "ORACLE"`
#'   (not implemented yet). Ignored otherwise.
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
#'
#' @return A data frame: the output table of the procedure.
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
  registry_end_time = NULL
) {
  # READ CHARACTER ARGUMENTS ####
  # Quoted, bare word, or a variable holding a string
  caller <- parent.frame()
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

  # VALIDATE INPUT (before touching the database) ####
  spec <- bef_procedure(procedure)
  procedure <- spec$name

  in_data <- check_location(in_data, "in_data")
  out_data <- check_location(out_data, "out_data")
  if (in_data == "ORACLE") {
    stop(
      "in_data = 'ORACLE' is not implemented yet. ",
      "Read the table into R and pass it as a data frame (in_table_name=).",
      call. = FALSE
    )
  }
  if (out_data == "ORACLE") {
    stop(
      "out_data = 'ORACLE' is not implemented yet. ",
      "Use out_data = 'R' and write the returned data frame yourself.",
      call. = FALSE
    )
  }
  if (!is.null(out_table_name)) {
    message(
      "NOTE: Variablen 'out_table_name' ignoreres, da output-tabellen returneres i R (out_data=R)."
    )
  }

  input <- NULL
  if (!is.na(spec$id_column)) {
    if (is.null(in_table_name)) {
      stop("Angiv navnet p\u00e5 input-tabellen (in_table_name=).", call. = FALSE)
    }
    input <- prepare_input_table(
      in_table_name,
      spec$id_column,
      column_name,
      procedure
    )
  } else if (!is.null(in_table_name)) {
    message("NOTE: ", procedure, " takes no input table; 'in_table_name' is ignored.")
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

  schema <- psd_query(psd, "SELECT USER AS SCHEMA_NAME FROM DUAL")$SCHEMA_NAME
  check_psd_privileges(psd, spec, user)
  drop_leftover_tables(psd, schema)

  # UPLOAD INPUT AND RUN THE PROCEDURE ####
  if (!is.null(input)) {
    created_tables <- c(created_tables, "BEF_ID_PROC")
    psd_write_table(psd, "BEF_ID_PROC", input)
  }

  # PSDMYTEMP receives the procedure's OUT values (result text and run id)
  created_tables <- c(created_tables, "PSDMYTEMP")
  psd_execute(
    psd,
    "create table PSDMYTEMP (v_resultat VARCHAR2(200), v_koerselsid NUMBER)"
  )

  if (date_mode == "historic" && is.null(dates$registry)) {
    dates$registry <- lookup_registry_time(psd, dates$validity)
  }

  plsql <- build_bef_plsql(
    spec,
    project_id = project_id,
    recipient = recipient,
    date_mode = date_mode,
    dates = dates
  )
  psd_run_plsql(psd, plsql)

  # COLLECT THE OUTPUT TABLE ####
  run <- read_run_info(psd)
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

  psd_query(psd, paste0("select * from ", out_name))
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

#' Check the input data frame and give the id column the required name
#' @noRd
prepare_input_table <- function(data, id_column, column_name, procedure) {
  if (!is.data.frame(data)) {
    stop(
      "'in_table_name' must be a data frame with a ",
      id_column,
      " column. ",
      "(Reading the input from an Oracle table, in_data = 'ORACLE', is not implemented yet.)",
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
  data
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

#' Build the anonymous PL/SQL block that runs a BEF procedure
#'
#' The procedure creates its output table <prefix><run id> in the user's
#' schema. Its OUT values are stored in PSDMYTEMP so R can find that table.
#' @noRd
build_bef_plsql <- function(spec, project_id, recipient, date_mode, dates) {
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
    "  insert into psdmytemp values (v_resultat, v_koerselsid);\n",
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

psd_query <- function(conn, sql) {
  DBI::dbGetQuery(conn, sql)
}

psd_execute <- function(conn, sql) {
  res <- DBI::dbSendQuery(conn, sql)
  DBI::dbClearResult(res)
  invisible(TRUE)
}

psd_write_table <- function(conn, name, data) {
  DBI::dbWriteTable(conn, name, data)
}

psd_run_plsql <- function(conn, plsql) {
  ROracle::oracleProc(conn, plsql)
}

psd_disconnect <- function(conn) {
  DBI::dbDisconnect(conn)
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

#' Check CREATE TABLE in DB_PSD and EXECUTE on the procedure's package
#'
#' `session_privs` and `all_tab_privs` include privileges granted through
#' roles and to PUBLIC, which `user_sys_privs` / `user_tab_privs` miss.
#' @noRd
check_psd_privileges <- function(conn, spec, user) {
  create_rights <- psd_query(
    conn,
    "SELECT privilege FROM session_privs WHERE privilege = 'CREATE TABLE'"
  )
  if (nrow(create_rights) == 0) {
    stop(
      user,
      " does not have privileges to create tables in DB_PSD.",
      call. = FALSE
    )
  }

  proc_rights <- psd_query(
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

#' Drop work tables left behind by an interrupted earlier run
#'
#' Otherwise creating them fails, and a stale PSDMYTEMP row could point to the
#' wrong output table.
#' @noRd
drop_leftover_tables <- function(conn, schema) {
  for (tbl in c("BEF_ID_PROC", "PSDMYTEMP")) {
    if (table_exists(conn, tbl, schema)) {
      message(
        "NOTE: Dropping table ",
        tbl,
        " left in DB_PSD by an earlier, interrupted run."
      )
      psd_execute(conn, paste0("drop table ", tbl))
    }
  }
}

#' Find the registry time for a validity date in D101200.bef_leverance_time
#' @noRd
lookup_registry_time <- function(conn, validity_date) {
  tid <- psd_query(
    conn,
    paste0(
      "select tid from (select min(time_stamp) as tid ",
      "from D101200.bef_leverance_time ",
      "where trunc(cpr_slut) >= TO_DATE('",
      validity_date,
      "','YYYY-MM-DD'))"
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
  tid <- as.character(tid[1])
  message(paste(
    "The registry datetime used is =",
    tid,
    "fetched from the PSD table D101200.bef_leverance_time."
  ))
  tid
}

#' Read the procedure's result text and run id from PSDMYTEMP
#' @noRd
read_run_info <- function(conn) {
  run <- psd_query(
    conn,
    "select v_resultat as RESULTAT, v_koerselsid as KOERSELSID from psdmytemp"
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
        psd_execute(conn, paste0("drop table ", tbl))
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
  tryCatch(psd_disconnect(conn), error = function(e) invisible(NULL))
}
