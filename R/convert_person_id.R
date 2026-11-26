# NOTES:
# - Input data has to be a data set with one column named either PNR or PERSON_ID (depending on procedure)
#   - The column type can be numbers or characters (or factor) it just has to have a form that the Oracle-procedure recognizes
# - The function returns the converted data so it has to be run as "data_id <- bef_personnummer(procedure,data,...)"
# - When an id cannot be found, PNR becomes "Ukendt-PNR" and person_id becomes 999999999999999 (15 nines)
# - The variable 'projekt_id' is only used to indicate which project ran the conversion. Per default
#   this function inputs user ident. It can in principle be any random sequence of characters.
# - The variable 'registry_time' requires 'validity_date' to be input but 'validity_date' does not require 'registry_time'
# - The variables 'registry_start_time' and 'registry_end_time' need to both be input to work (or neither)
# - The function is not strict about datetime format
#   - see lubridate::parse_date_time and list of orders in function call for accepted formats
#   - all other formats than 01012021 need to be written as a character - e.g. '01-01-1900 12:00:00'
# - The datetime variables cannot take a column of dates as input, only one value
# - The SAS macro has 'database' as an option for where the procedures are located, in this function
#   'database' is where data is located. This function only takes conversion procedures from db_psd

# TODO (EKSTRA):
# - implement variable for whether input data is located in R or Oracle (in_data)
#   - variabel for in_database, inkl. tjek for lÃ¦se-rettigheder
#   - also requires indicator for whether data is in db_psd, statprod, statudv etc
#     - note that procedures are in db_psd
#   - check that database and data exist (use table_exists function)
# - implement variable for whether out_table should be returned in R or saved in Oracle (out_data)
#   - tilfÃ¸j variabel for out_database, inkl. tjek for skrive-rettigheder
#   - i SAS-makroen gemmes data ved output til Oracle blot i &prefix_name&v_koerselsid i ident-skema pÃ¥ PSD
#     - do the same here?
# - opdatÃ©r 'column_name' til at tages som input i funktion
#   - problem: right now Oracle procedures do not take table name as input
# - update code to only fetch unique rows when data passes through the environment
# - test functions on person IDs with shifts

# TODO (FEJL OG TJEK):
# - check that it is the correct column (name, type, length etc)
#   - check name (DONE)
#   - lav en variabel 'column_name' som i SAS (DONE), sÃ¥ det let kan udtages til tjek i Oracle (mangler)
#   - also check column type (right now character, factor, and integer work - but does this also apply in Oracle) and column length (maybe only relevant for Oracle?)
# - remember to have toupper() for all name checks

# TODO (UNDERSÃ˜G):
# - investigate: which format do people typically insert for dates and times?
# - is it a problem that R does not include milliseconds in the datetime format?
#   - dte er ikke et problem i at hente, men er der nogen, der user millisekunder til at matche?
# - hvordan holder folk styr pÃ¥, hvornÃ¥r man skal bruge validity_date+registry_time eller registry_start_time+registry_end_time?
# - how does the function behave if one has not gained access to the conversion tables or to PSD?

# Create function -------------------------------------------------------------

# For names and explanations of procedures see "Metodevejledning konvertering mellem cpr og person_id..."
# in "G:\k22\01 Metode\Diskretionering\Pseudonymisering"

#' @title Convert between CPR and PERSON_ID
#' @description This function converts between CPR and PERSON_ID.
#' @param procedure Name of Oracle-procedure (e.g. "BEF_HISTORISK_ID").
#' @param database Location of input data (e.g. 'DB_PSD').
#' @param in_data 'R' or 'ORACLE'.
#' @param out_data 'R' or 'ORACLE'.
#' @param column_name Name of the column, if specific.
#' @param recipient User ident.
#' @param in_table_name Name of input table.
#' @param out_table_name Name of output table.
#' @param project_id Project ID, e.g. "D101200".
#' @param validity_date Validity date.
#' @param registry_time Registry time.
#' @param registry_start_time Registry start time.
#' @param registry_end_time Registry end time.
#' @return A data.frame with converted IDs, if out_data='R'.
#' @export
convert_person_id <- function(
  procedure = NULL, # Name of procedure e.g. "BEF_HISTORISK_ID"
  database = 'DB_PSD', # Location of input data if in Oracle
  # change to in_database and out_database?
  in_data = "R", # "R" or "ORACLE" depending on where input data is located
  out_data = "R", # "R" or "ORACLE" depending on where output data should be located
  column_name = NULL,
  recipient = Sys.getenv("USERNAME"),
  in_table_name = NULL, # Name of input data (needs to be character if in_data="ORACLE")
  out_table_name = NULL, # Only relevant if 'data="Oracle"' since output in R is returned
  project_id = NULL, # E.g. "D101200" - default is user ident if nothing is input
  validity_date = NULL, # Returns data where this date is between VFRA and VTIL e.g. 01012021  or '01-01-2021 12:00:00'
  registry_time = NULL, # Returns data where this date is between RFRA and RTIL e.g. 01012021  or '01-01-2021 12:00:00'
  registry_start_time = NULL, # e.g. 01011900 or '01-01-1900 12:00:00'
  registry_end_time = NULL # e.g. 01012100 or '01-01-2100 12:00:00'
  # Returns data where RTIL>registry_start_time and RFRA<=registry_end_time
) {
  # TODO: INPUT UPDATED VARIABLES FULLY
  # database
  # in_data and out_data if ="ORACLE"
  # in_table_name (skal kun hentes fra env, hvis in_data=R, ellers character)

  # HANDLE CHARACTER VARIABLE ####
  # Ensure that character variables can be input both with and without quotations

  # TODO: make neater/write as a function?

  procedure <- stringr::str_remove_all(deparse(substitute(procedure)), '^"|"$')
  database <- stringr::str_remove_all(deparse(substitute(database)), '^"|"$')
  in_data <- stringr::str_remove_all(deparse(substitute(in_data)), '^"|"$')
  out_data <- stringr::str_remove_all(deparse(substitute(out_data)), '^"|"$')
  recipient <- if (deparse(substitute(recipient)) == "Sys.getenv(\"USERNAME\")") {
    recipient # only update if it is input, otherwise keep username command
  } else {
    stringr::str_remove_all(deparse(substitute(recipient)), '^"|"$')
  }
  out_table_name <- stringr::str_remove_all(
    deparse(substitute(out_table_name)),
    '^"|"$'
  )
  project_id <- stringr::str_remove_all(
    deparse(substitute(project_id)),
    '^"|"$'
  )

  if (procedure == "NULL") {
    procedure <- NULL
  }
  if (database == "NULL") {
    database <- NULL
  }
  if (in_data == "NULL") {
    in_data <- NULL
  }
  if (out_data == "NULL") {
    out_data <- NULL
  }
  if (recipient == "NULL") {
    recipient <- NULL
  }
  if (out_table_name == "NULL") {
    out_table_name <- NULL
  }
  if (project_id == "NULL") {
    project_id <- NULL
  }

  # ESTABLISH CONNECTIONS ####

  # Connections
  psd <- DSTdb::get_conn('DB_PSD', namespace = "bef_personnummer")

  if (!is.null(database)) {
    conn <- DSTdb::get_conn(
      paste(toupper(database)),
      namespace = "bef_personnummer"
    )
  }

  # User
  user <- Sys.getenv("USERNAME")

  # Define project_id as user if not given
  if (is.null(project_id)) {
    project_id <- user
    message(paste0(
      "NOTE: Der er ikke angivet et navn for det projekt, der kalder proceduren (ex. project_id='D101200'), derfor anvendes user-ident ",
      user,
      "."
    ))
  }

  # Check rights to write in DB_PSD (required for all procedures)
  psd_rights <- DBI::dbGetQuery(
    psd,
    "select * from user_sys_privs
                                     where privilege = 'CREATE TABLE'"
  )
  if (nrow(psd_rights) == 0) {
    stop(paste0(
      user,
      " does not have privileges to create tables in DB_PSD."
    ))
  }

  # TODO: should this be the db-schema as well?

  # Check rights to write in database where database should be written to
  if (toupper(out_data) == "ORACLE") {
    database_rights <- DBI::dbGetQuery(
      conn,
      "select * from user_sys_privs
                                       where privilege = 'CREATE TABLE'"
    )
    if (nrow(database_rights) == 0) {
      stop(paste0(
        user,
        " does not have privileges to create tables in the database ",
        database
      ))
    }
  }

  # SET FUNCTIONS TO RUN ON EXIT ####

  # Ensure that temporary tables are dropped even if an error occurs in the script
  on.exit(
    # Drop temporary table for output of procedure
    if (table_exists(psd, "PSDMYTEMP", user)) {
      DBI::dbSendQuery(psd, "drop table PSDMYTEMP")
    }
  )
  on.exit(
    if (table_exists(psd, "BEF_ID_PROC", user)) {
      # Drop temporary table for input data
      DBI::dbSendQuery(psd, "drop table BEF_ID_PROC")
    },
    add = TRUE
  )
  # Close connection to psd
  on.exit(
    DBI::dbDisconnect(psd),
    add = TRUE
  )
  # Close connection to database
  on.exit(
    if (!is.null(database) & database != "DB_PSD") {
      DBI::dbDisconnect(conn)
    },
    add = TRUE
  )

  # CHECK PROCEDURE ####

  # Error message if no/wrong procedure is given
  if (is.null(procedure)) {
    stop(
      "Specify the name of the Oracle procedure you want to execute (procedure=)."
    )
  } else if (
    !(toupper(procedure) %in%
      c(
        'BEF_AKTUELLE_PNR',
        'BEF_HISTORISK_PNR',
        'BEF_FULD_HISTORIK_ID',
        'BEF_IDSKIFT',
        'BEF_AKTUEL_KOEN_FOEDSELSDAG',
        'BEF_HISTORISK_KOEN_FOEDSELSDAG',
        'BEF_FULD_HIS_KOEN_FOEDSELSDAG',
        'BEF_OMKOD',
        'BEF_AKTUELLE_ID',
        'BEF_HISTORISK_ID',
        'BEF_FULD_HISTORIK_PNR',
        'BEF_INVALIDE'
      ))
  ) {
    stop("The specified Oracle procedure is not recognized.")
  }

  # Name of created table (when adding v_koerselsid) for given procedure
  prefix_name = dplyr::case_when(
    toupper(procedure) == 'BEF_OMKOD' ~ 'PNROMKOD',
    toupper(procedure) == 'BEF_AKTUELLE_ID' ~ 'AKT_ID',
    toupper(procedure) == 'BEF_HISTORISK_ID' ~ 'HIS_ID',
    toupper(procedure) == 'BEF_FULD_HISTORIK_PNR' ~ 'FULDHISPNR',
    toupper(procedure) == 'BEF_AKTUELLE_PNR' ~ 'AKTPNR',
    toupper(procedure) == 'BEF_HISTORISK_PNR' ~ 'HISPNR',
    toupper(procedure) == 'BEF_FULD_HISTORIK_ID' ~ 'FULDHISID',
    toupper(procedure) == 'BEF_AKTUEL_KOEN_FOEDSELSDAG' ~ 'AKTKONFOD',
    toupper(procedure) == 'BEF_HISTORISK_KOEN_FOEDSELSDAG' ~ 'HISKONFOD',
    toupper(procedure) == 'BEF_FULD_HIS_KOEN_FOEDSELSDAG' ~ 'FULDHISKON',
    toupper(procedure) == 'BEF_IDSKIFT' ~ 'IDSKIFT',
    toupper(procedure) == 'BEF_INVALIDE' ~ 'INVALIDE'
  )

  # Select different pack for BEF_OMKOD
  package01 = dplyr::if_else(
    toupper(procedure) == 'BEF_OMKOD',
    'BEF01_pck_omkodning',
    'BEF01_pck_laes_personnummer'
  )
  package = dplyr::if_else(
    toupper(procedure) == 'BEF_OMKOD',
    'BEF_PCK_OMKODNING',
    'BEF_PCK_LAES_PERSONNUMMER'
  )

  # Define required column name for each procedure (except 'BEF_INVALIDE')
  if (
    toupper(procedure) %in%
      c(
        'BEF_OMKOD',
        'BEF_AKTUELLE_ID',
        'BEF_HISTORISK_ID',
        'BEF_FULD_HISTORIK_PNR'
      )
  ) {
    column_name = "PNR"
  } else if (
    toupper(procedure) %in%
      c(
        'BEF_AKTUELLE_PNR',
        'BEF_HISTORISK_PNR',
        'BEF_FULD_HISTORIK_ID',
        'BEF_IDSKIFT',
        'BEF_AKTUEL_KOEN_FOEDSELSDAG',
        'BEF_HISTORISK_KOEN_FOEDSELSDAG',
        'BEF_FULD_HIS_KOEN_FOEDSELSDAG'
      )
  ) {
    column_name = "PERSON_ID"
  }

  # Check if user has the rights to run the procedure
  proc_rights <- DBI::dbGetQuery(
    psd,
    paste0(
      "SELECT privilege FROM user_tab_privs
                                      WHERE table_name = '",
      package,
      "'"
    )
  )
  if (nrow(proc_rights) == 0) {
    stop(paste0(
      user,
      " does not have privileges to execute the procedure ",
      procedure
    ))
  }

  # CHECK INPUT DATA AND CREATE ORACLE TABLES ####

  # Check data is input
  if (is.null(in_table_name) & toupper(procedure) != "BEF_INVALIDE") {
    stop("Angiv navnet p\u00e5 input-tabellen (in_table_name=).")
  }

  #####TODO: set up and correct for different output and input data and locations

  if (is.null(out_table_name) & toupper(out_data) == "ORACLE") {
    stop(
      "Angiv navnet p\u00e5 output-tabellen (out_table_name=), der gemmes i Oracle (out_data=ORACLE)."
    )
  }

  if (!is.null(out_table_name) & toupper(out_data) == "R") {
    message(
      "NOTE: Variablen 'out_table_name' ignoreres, da output-tabellen returneres i R (out_data=R)."
    )
  }

  # Check column names and save data to Oracle
  if (!is.null(in_table_name)) {
    names(in_table_name) <- toupper(names(in_table_name))

    # Does data include a column with the required column name
    if (!(column_name %in% names(in_table_name))) {
      stop(paste0(
        "There is no column ",
        column_name,
        " in the input table."
      ))
    }

    DBI::dbWriteTable(psd, "BEF_ID_PROC", in_table_name)
  }

  # Create table 'PSDMYTEMP' on ident schema in dp_psd to store temporary data
  DBI::dbSendQuery(
    psd,
    "create table PSDMYTEMP
                            (v_resultat   VARCHAR2(200),
                            v_koerselsid NUMBER)"
  )

  # HANDLE DATETIME VARIABLES ####

  if (!is.null(validity_date)) {
    validity_date <- extract_date_time(validity_date)$date
    if (is.na(validity_date)) {
      stop("Ukendt format for 'validity_date'.")
    }
  }

  if (!is.null(registry_start_time)) {
    date_start <- extract_date_time(registry_start_time)$date
    time_start <- extract_date_time(registry_start_time)$time
    if (is.na(date_start) | is.na(time_start)) {
      stop("Ukendt format for 'registry_start_time'.")
    }
  }

  if (!is.null(registry_end_time)) {
    date_end <- extract_date_time(registry_end_time)$date
    time_end <- extract_date_time(registry_end_time)$time
    if (is.na(date_end) | is.na(time_end)) {
      stop("Ukendt format for 'registry_end_time'.")
    }
  }

  # RUN PROCEDURES ####

  # Run procedure - procedures without dates
  if (
    toupper(procedure) %in%
      c(
        'BEF_OMKOD',
        'BEF_AKTUELLE_ID',
        'BEF_AKTUELLE_PNR',
        'BEF_AKTUEL_KOEN_FOEDSELSDAG',
        'BEF_FULD_HISTORIK_ID',
        'BEF_FULD_HISTORIK_PNR',
        'BEF_FULD_HIS_KOEN_FOEDSELSDAG',
        'BEF_IDSKIFT'
      ) &
      is.null(validity_date) &
      is.null(registry_time) &
      is.null(registry_start_time) &
      is.null(registry_end_time)
  ) {
    # Run procedure - automatically saves table in ident schema and saves the run id in psdmytemp
    ROracle::oracleProc(
      psd,
      paste0(
        "DECLARE  v_resultat VARCHAR2(200);
                                   v_koerselsid NUMBER;\n",
        "BEGIN ",
        package01,
        ".",
        procedure,
        "
                                  (p_projektnummer => '",
        project_id,
        "',
                                  p_bruger => '",
        recipient,
        "',
                                  p_ind_tabelnavn => 'BEF_ID_PROC',
                                  p_resultat => v_resultat,
                                  p_koerselsid => v_koerselsid);

                                  -- Insert values into mytemp to identify output table later
                                  insert into psdmytemp values (v_resultat,V_koerselsid);
                              COMMIT;
                             END;"
      )
    )
  } else if (
    toupper(procedure) %in%
      c(
        'BEF_OMKOD',
        'BEF_AKTUELLE_ID',
        'BEF_AKTUELLE_PNR',
        'BEF_AKTUEL_KOEN_FOEDSELSDAG'
      ) &
      !is.null(validity_date) &
      is.null(registry_time) &
      is.null(registry_start_time) &
      is.null(registry_end_time)
  ) {
    # Run procedure - procedures with a date
    # Run procedure - automatically saves table in ident schema and saves the run id in psdmytemp
    ROracle::oracleProc(
      psd,
      paste0(
        "DECLARE  v_resultat VARCHAR2(200);
                                   v_koerselsid NUMBER;\n",
        "BEGIN ",
        package01,
        ".",
        procedure,
        "
                                  (p_projektnummer => '",
        project_id,
        "',
                                  p_bruger => '",
        recipient,
        "',
                                  p_ind_tabelnavn => 'BEF_ID_PROC',
                                  p_gyldighedsdato=> TO_DATE('",
        validity_date,
        "','YYYY-MM-DD'),
                                  p_resultat => v_resultat,
                                  p_koerselsid => v_koerselsid);

                                  -- Insert values into mytemp to identify output table later
                                  insert into psdmytemp values (v_resultat,V_koerselsid);
                              COMMIT;
                             END;"
      )
    )
  } else if (
    toupper(procedure) %in%
      c(
        'BEF_HISTORISK_ID',
        'BEF_HISTORISK_PNR',
        'BEF_HISTORISK_KOEN_FOEDSELSDAG'
      ) &
      !is.null(validity_date) &
      is.null(registry_start_time) &
      is.null(registry_end_time)
  ) {
    # Run procedure - procedures with a date and time (historisk)
    # find 'registry_time' if it isn't given as input
    if (is.null(registry_time)) {
      registry_time <- DBI::dbGetQuery(
        psd,
        paste0(
          "select tid from
				(select min(time_stamp) as tid
				 from D101200.bef_leverance_time
				 where trunc(cpr_slut) >= TO_DATE('",
          validity_date,
          "','YYYY-MM-DD'))"
        )
      )$TID
      if (is.na(registry_time)) {
        stop(paste(
          "Gyldighedsdato",
          validity_date,
          "findes ikke i PSD registry_time tabellen."
        ))
      } else {
        print(paste(
          "The registry datetime used is =",
          registry_time,
          "fetched from the PSD table D101200.bef_leverance_time."
        ))
      }
    } else {
      date_registry <- extract_date_time(registry_time)$date
      time_registry <- extract_date_time(registry_time)$time
      if (is.na(date_registry) | is.na(time_registry)) {
        stop("Ukendt format for 'registry_time'.")
      }
      registry_time <- paste(date_registry, time_registry)
    }

    # Run procedure - automatically saves table in ident schema and saves the run id in psdmytemp
    ROracle::oracleProc(
      psd,
      paste0(
        "DECLARE  v_resultat VARCHAR2(200);
                                   v_koerselsid NUMBER;\n",
        "BEGIN ",
        package01,
        ".",
        procedure,
        "
                                  (p_projektnummer => '",
        project_id,
        "',
                                  p_bruger => '",
        recipient,
        "',
                                  p_ind_tabelnavn => 'BEF_ID_PROC',
                                  p_gyldighedsdato=> TO_DATE('",
        validity_date,
        "','YYYY-MM-DD'),
                                  p_registerdato => TO_TIMESTAMP ('",
        registry_time,
        "','YYYY-MM-DD HH24:MI:SS.FF'),
                                  p_resultat => v_resultat,
                                  p_koerselsid => v_koerselsid);

                                  -- Insert values into mytemp to identify output table later
                                  insert into psdmytemp values (v_resultat,V_koerselsid);
                              COMMIT;
                             END;"
      )
    )
  } else if (
    toupper(procedure) %in%
      c(
        'BEF_FULD_HISTORIK_ID',
        'BEF_FULD_HISTORIK_PNR',
        'BEF_FULD_HIS_KOEN_FOEDSELSDAG'
      ) &
      !is.null(registry_start_time) &
      !is.null(registry_end_time) &
      is.null(validity_date) &
      is.null(registry_time)
  ) {
    # Run procedure - procedures with dates and time (fuld historisk)
    # Run procedure - automatically saves table in ident schema and saves the run id in psdmytemp
    ROracle::oracleProc(
      psd,
      paste0(
        "DECLARE  v_resultat VARCHAR2(200);
                                   v_koerselsid NUMBER;\n",
        "BEGIN ",
        package01,
        ".",
        procedure,
        "
                                  (p_projektnummer => '",
        project_id,
        "',
                                  p_bruger => '",
        recipient,
        "',
                                  p_ind_tabelnavn => 'BEF_ID_PROC',
                								  p_registerstarttid => TO_TIMESTAMP ('",
        date_start,
        " ",
        time_start,
        "','YYYY-MM-DD HH24:MI:SS.FF'),
                								  p_registersluttid => TO_TIMESTAMP ('",
        date_end,
        " ",
        time_end,
        "','YYYY-MM-DD HH24:MI:SS.FF'),
                                  p_resultat => v_resultat,
                                  p_koerselsid => v_koerselsid);

                                  -- Insert values into mytemp to identify output table later
                                  insert into psdmytemp values (v_resultat,V_koerselsid);
                              COMMIT;
                             END;"
      )
    )
  } else if (
    toupper(procedure) %in%
      c('BEF_INVALIDE') &
      is.null(registry_start_time) &
      is.null(registry_end_time) &
      is.null(validity_date) &
      is.null(registry_time)
  ) {
    # Run procedure - bef_invalide without dates (no input table)
    # Run procedure - automatically saves table in ident schema and saves the run id in psdmytemp
    ROracle::oracleProc(
      psd,
      paste0(
        "DECLARE  v_resultat VARCHAR2(200);
                                   v_koerselsid NUMBER;\n",
        "BEGIN ",
        package01,
        ".",
        procedure,
        "
                                  (p_projektnummer => '",
        project_id,
        "',
                                  p_bruger => '",
        recipient,
        "',
                                  p_resultat => v_resultat,
                                  p_koerselsid => v_koerselsid);

                                  -- Insert values into mytemp to identify output table later
                                  insert into psdmytemp values (v_resultat,V_koerselsid);
                              COMMIT;
                             END;"
      )
    )
  } else if (
    toupper(procedure) %in%
      c('BEF_INVALIDE') &
      !is.null(registry_start_time) &
      !is.null(registry_end_time) &
      is.null(validity_date) &
      is.null(registry_time)
  ) {
    # Run procedure - bef_invalide with dates (no input table)
    # Run procedure - automatically saves table in ident schema and saves the run id in psdmytemp
    ROracle::oracleProc(
      psd,
      paste0(
        "DECLARE  v_resultat VARCHAR2(200);
                                   v_koerselsid NUMBER;\n",
        "BEGIN ",
        package01,
        ".",
        procedure,
        "
                                  (p_projektnummer => '",
        project_id,
        "',
                                  p_bruger => '",
        recipient,
        "',
                								  p_registerstarttid => TO_TIMESTAMP ('",
        date_start,
        " ",
        time_start,
        "','YYYY-MM-DD HH24:MI:SS.FF'),
                								  p_registersluttid => TO_TIMESTAMP ('",
        date_end,
        " ",
        time_end,
        "','YYYY-MM-DD HH24:MI:SS.FF'),
                                  p_resultat => v_resultat,
                                  p_koerselsid => v_koerselsid);

                                  -- Insert values into mytemp to identify output table later
                                  insert into psdmytemp values (v_resultat,V_koerselsid);
                              COMMIT;
                             END;"
      )
    )
  } else if (
    (!is.null(registry_start_time) & is.null(registry_end_time)) |
      (is.null(registry_start_time) & !is.null(registry_end_time))
  ) {
    stop(
      "En af parameterene registry_start_time eller registry_end_time er udfyldt, enten skal begge eller ingen v\u00e6re udfyldt."
    )
  } else {
    stop(
      "Der er et problem med kombinationen af procedure og de angivne dato- og tidsparametre.
         Tjek, hvilke dato- og tidsparametre den angivne procedure benytter."
    )
  }

  # CREATE OUTPUT TABLE ####

  if (table_exists(psd, "PSDMYTEMP", user)) {
    # Collect v_koerselsid from temporary table
    v_koerselsid <- DBI::dbGetQuery(
      psd,
      "select max(v_koerselsid) as X from psdmytemp"
    )$X[1]

    # Print result of process (successfully run or not)
    print(DBI::dbGetQuery(psd, "select v_resultat as X from psdmytemp")$X[1])
  } else {
    stop("Something went wrong during execution.")
  }

  if (table_exists(psd, toupper(paste0(prefix_name, v_koerselsid)), user)) {
    # Create output table
    out_table <- DBI::dbGetQuery(
      psd,
      paste0("select * from ", prefix_name, v_koerselsid)
    )

    # Drop id table from ident schema
    DBI::dbSendQuery(psd, paste0("drop table ", prefix_name, v_koerselsid))
  } else {
    stop("Something went wrong during execution.")
  }

  # Save or return output table:
  if (toupper(out_data) == "R") {
    # return the output table
    return(out_table)
  } else if (toupper(out_data) == "ORACLE") {
    # TODO
    # Save data to Oracle and don't return anything to R?
    # Just save the list of converted id's to the ident chema in the same database as original data
  }
}
