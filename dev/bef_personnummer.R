
library(ROracle)
library(tidyverse)
library(DSTdb)
library(dbplyr) # maybe not used
library(rlang) # maybe not used

# NOTES:
# - Input data has to be a data set with one column named either PNR or PERSON_ID (depending on procedure)
#   - The column type can be numbers or characters (or factor) it just has to have a form that the Oracle-procedure recognizes
# - The function returns the converted data so it has to be run as "data_id <- bef_personnummer(procedure,data,...)"
# - When an id cannot be found, PNR becomes "Ukendt-PNR" and person_id becomes 999999999999999 (15 nines)
# - The variable 'projekt_id' is only used to indicate which project ran the conversion. Per default
#   this function inputs user ident. It can in principle be any random sequence of characters.
# - The variable 'registertid' requires 'gyldighedsdato' to be input but 'gyldighedsdato' does not require 'registertid'
# - The variables 'registerstarttid' and 'registersluttid' need to both be input to work (or neither)
# - The function is not strict about datetime format
#   - see lubridate::parse_date_time and list of orders in function call for accepted formats
#   - all other formats than 01012021 need to be written as a character - e.g. '01-01-1900 12:00:00'
# - The datetime variables cannot take a column of dates as input, only one value
# - The SAS macro has 'database' as an option for where the procedures are located, in this function
#   'database' is where data is located. This function only takes conversion procedures from db_psd

# TODO (EKSTRA): 
# - implementér variabel for, om input-data ligger i R eller Oracle (ind_data)
#   - variabel for ind_database, inkl. tjek for læse-rettigheder 
#   - kræver også indikator for, om data er i db_psd, statprod, statudv etc
#     - bem. at procedurer er i db_psd
#   - tjek, at databse og data findes (brug table_exists-funktion)
# - implementér variabel for, om out_tabel skal returneres i R eller gemmes i Oracle (ud_data)
#   - tilføj variabel for ud_database, inkl. tjek for skrive-rettigheder 
#   - i SAS-makroen gemmes data ved output til Oracle blot i &praenavn&v_koerselsid i ident-skema på PSD
#     - gør det samme her?
# - opdatér 'kolonneNavn' til at tages som input i funktion
#   - problem: lige nu tager Oracle-procedurer ikke tabelnavn som input
# - opdatér kode til kun at hente unikke rækker ned, når data kommer forbi environment
# - test funktioner på person-id'er med skift

# TODO (FEJL OG TJEK):
# - check, at det er den rigtige kolonne (navn, type, længde etc)
#   - check navn (DONE)
#   - lav en variabel 'kolonneNavn' som i SAS (DONE), så det let kan udtages til tjek i Oracle (mangler)
#   - tjek også kolonnetype (lige nu fungerer character, faktor og integer - men gælder det også i Oracle) og kolonnelængde (måske kun relevant for Oracle?)
# - husk at have toupper() ved alle tjek af navne

# TODO (UNDERSØG):
# - undersøg: hvilket format indsætter folk typisk for datoer og tidspunkter?
# - er det et problem, at R ikke inkluderer millisekunder i datetime-formatet?
#   - dte er ikke et problem i at hente, men er der nogen, der bruger millisekunder til at matche?
# - hvordan holder folk styr på, hvornår man skal bruge gyldighedsdato+registertid eller registerstarttid+registersluttid?
# - hvordan opfører funktionen sig, hvis man ikke har fået adgang til konverterings-tabellerne eller til psd?

# Create function -------------------------------------------------------------


# For names and explanations of procedures see "Metodevejledning konvertering mellem cpr og person_id..." 
# in "G:\k22\01 Metode\Diskretionering\Pseudonymisering"

bef_personnummer <- function(procedure = NULL # Name of procedure e.g. "BEF_HISTORISK_ID"
                             , database = 'DB_PSD' # Location of input data if in Oracle
                             # change to ind_database and ud_database?
                             , ind_data = "R" # "R" or "ORACLE" depending on where input data is located
                             , ud_data = "R" # "R" or "ORACLE" depending on where output data should be located
                             , kolonneNavn = NULL
                             , postmodtager = Sys.getenv("USERNAME")
                             , ind_tabelnavn = NULL # Name of input data (needs to be character if ind_data="ORACLE")
                             , ud_tabelnavn = NULL # Only relevant if 'data="Oracle"' since output in R is returned
                             , projektid = NULL # E.g. "D101200" - default is user ident if nothing is input
                             , gyldighedsdato = NULL # Returns data where this date is between VFRA and VTIL e.g. 01012021  or '01-01-2021 12:00:00'
                             , registertid = NULL # Returns data where this date is between RFRA and RTIL e.g. 01012021  or '01-01-2021 12:00:00'
                             , registerstarttid = NULL # e.g. 01011900 or '01-01-1900 12:00:00'
                             , registersluttid = NULL # e.g. 01012100 or '01-01-2100 12:00:00'
                             # Returns data where RTIL>registerstarttid and RFRA<=registersluttid
){
  
  # TODO: INPUT UPDATED VARIABLES FULLY
    # database
    # ind_data and ud_data if ="ORACLE"
    # ind_tabelnavn (skal kun hentes fra env, hvis ind_data=R, ellers character)
  
  
  # HANDLE CHARACTER VARIABLE ####
  # Ensure that character variables can be input both with and without quotations
  
  # TODO: make neater/write as a function?
  
  procedure <- gsub('^"|"$', '', deparse(substitute(procedure)))
  database <- gsub('^"|"$', '', deparse(substitute(database)))
  ind_data <- gsub('^"|"$', '', deparse(substitute(ind_data)))
  ud_data <- gsub('^"|"$', '', deparse(substitute(ud_data)))
  postmodtager <- ifelse(deparse(substitute(postmodtager))=="Sys.getenv(\"USERNAME\")"
                         ,postmodtager, # only update if it is input, otherwise keep username command
                         gsub('^"|"$', '', deparse(substitute(postmodtager))))
  ud_tabelnavn <- gsub('^"|"$', '', deparse(substitute(ud_tabelnavn)))
  projektid <- gsub('^"|"$', '', deparse(substitute(projektid)))

  if(procedure=="NULL"){
    procedure <- NULL
  }
  if(database=="NULL"){
    database <- NULL
  }
  if(ind_data=="NULL"){
    ind_data <- NULL
  }
  if(ud_data=="NULL"){
    ud_data <- NULL
  }
  if(postmodtager=="NULL"){
    postmodtager <- NULL
  }
  if(ud_tabelnavn=="NULL"){
    ud_tabelnavn <- NULL
  }
  if(projektid=="NULL"){
    projektid <- NULL
  }

  # ESTABLISH CONNECTIONS ####
  
  # Connections
  psd <- DSTdb::get_conn('DB_PSD', namespace="bef_personnummer")
  
  if (!is.null(database)){
  conn <- DSTdb::get_conn(paste(toupper(database)), namespace="bef_personnummer")
  }
  
  # User
  bruger <- Sys.getenv("USERNAME")
  
  # Define projektid as user if not given
  if ( is.null(projektid)){
    projektid <- bruger
    message(paste0("NOTE: Der er ikke angivet et navn for det projekt, der kalder proceduren (ex. projektid='D101200'), derfor anvendes bruger-ident ",bruger,"."))
  }
  
  # Check rights to write in DB_PSD (required for all procedures)
  psd_rettigheder <- dbGetQuery(psd,"select * from user_sys_privs
                                     where privilege = 'CREATE TABLE'")
  if (nrow(psd_rettigheder)==0){
    stop(paste0(bruger," har ikke rettigheder til at oprette tabeller i DB_psd."))
  }
  
  # TODO: should this be the db-schema as well?
  
  # Check rights to write in database where database should be written to 
  if (toupper(ud_data)=="ORACLE"){
    database_rettigheder <- dbGetQuery(conn,"select * from user_sys_privs
                                       where privilege = 'CREATE TABLE'")
    if (nrow(database_rettigheder)==0){
      stop(paste0(bruger," har ikke rettigheder til at oprette tabeller i databasen ",database))
    }
  }
  
  # SET FUNCTIONS TO RUN ON EXIT ####
  
  # Function to check if a table exists
  table_exists <- function(conn, table_name, schema_name) {
    query <- paste0("SELECT COUNT(*) AS COUNT FROM all_tables WHERE table_name = '",table_name,"' AND owner = '",schema_name,"'")
    result <- dbGetQuery(conn, query)
    
    return(result$COUNT > 0)  # Returns TRUE if the table exists, otherwise FALSE
  }
  
  # Ensure that temporary tables are dropped even if an error occurs in the script
  on.exit(
    # Drop temporary table for output of procedure
    if (table_exists(psd,"PSDMYTEMP",bruger)){
      dbSendQuery(psd,"drop table PSDMYTEMP")
    }
  )
  on.exit(
    if (table_exists(psd,"BEF_ID_PROC",bruger)){
      # Drop temporary table for input data
      dbSendQuery(psd,"drop table BEF_ID_PROC")
    }
    , add=TRUE
  )
  # Close connection to psd
  on.exit(
    dbDisconnect(psd)
    , add=TRUE
  )
  # Close connection to database
  on.exit(
    if (!is.null(database) & database!="DB_PSD"){dbDisconnect(conn)}
    , add=TRUE
  )
  
  # CHECK PROCEDURE ####
  
  # Error message if no/wrong procedure is given
  if (is.null(procedure)){
    stop("Angiv navnet på den Oracle-procedure du ønsker at afvikle (Procedure=).")
  }
  else if ( !(toupper(procedure) %in% c('BEF_AKTUELLE_PNR','BEF_HISTORISK_PNR',
                                        'BEF_FULD_HISTORIK_ID','BEF_IDSKIFT',
                                        'BEF_AKTUEL_KOEN_FOEDSELSDAG',
                                        'BEF_HISTORISK_KOEN_FOEDSELSDAG',
                                        'BEF_FULD_HIS_KOEN_FOEDSELSDAG','BEF_OMKOD',
                                        'BEF_AKTUELLE_ID','BEF_HISTORISK_ID',
                                        'BEF_FULD_HISTORIK_PNR','BEF_INVALIDE')) ){
    stop("Den angivne Oracle-procedure genkendes ikke.")
  }
  
  # Name of created table (when adding v_koerselsid) for given procedure
  praenavn = case_when(
    toupper(procedure) == 'BEF_OMKOD' ~ 'PNROMKOD'
    , toupper(procedure) == 'BEF_AKTUELLE_ID' ~ 'AKT_ID'
    , toupper(procedure) == 'BEF_HISTORISK_ID' ~ 'HIS_ID'
    , toupper(procedure) == 'BEF_FULD_HISTORIK_PNR' ~ 'FULDHISPNR'
    , toupper(procedure) == 'BEF_AKTUELLE_PNR' ~ 'AKTPNR'
    , toupper(procedure) == 'BEF_HISTORISK_PNR' ~ 'HISPNR'
    , toupper(procedure) == 'BEF_FULD_HISTORIK_ID' ~ 'FULDHISID'
    , toupper(procedure) == 'BEF_AKTUEL_KOEN_FOEDSELSDAG' ~ 'AKTKONFOD'
    , toupper(procedure) == 'BEF_HISTORISK_KOEN_FOEDSELSDAG' ~ 'HISKONFOD'
    , toupper(procedure) == 'BEF_FULD_HIS_KOEN_FOEDSELSDAG' ~ 'FULDHISKON'
    , toupper(procedure) == 'BEF_IDSKIFT' ~ 'IDSKIFT'
    , toupper(procedure) == 'BEF_INVALIDE' ~ 'INVALIDE'
  )
  
  # Select different pack for BEF_OMKOD
  pakke01 = if_else(toupper(procedure) == 'BEF_OMKOD', 'BEF01_pck_omkodning', 'BEF01_pck_laes_personnummer')
  pakke = if_else(toupper(procedure) == 'BEF_OMKOD', 'BEF_PCK_OMKODNING', 'BEF_PCK_LAES_PERSONNUMMER')
  
  # Define required column name for each procedure (except 'BEF_INVALIDE')
  if (toupper(procedure) %in% c('BEF_OMKOD','BEF_AKTUELLE_ID','BEF_HISTORISK_ID',
                                'BEF_FULD_HISTORIK_PNR')){
    kolonneNavn = "PNR"
  }
  else if (toupper(procedure) %in% c('BEF_AKTUELLE_PNR','BEF_HISTORISK_PNR',
                                     'BEF_FULD_HISTORIK_ID','BEF_IDSKIFT',
                                     'BEF_AKTUEL_KOEN_FOEDSELSDAG',
                                     'BEF_HISTORISK_KOEN_FOEDSELSDAG',
                                     'BEF_FULD_HIS_KOEN_FOEDSELSDAG')){
    kolonneNavn = "PERSON_ID"
  }
  
  # Check if user has the rights to run the procedure
  proc_rettigheder <- dbGetQuery(psd,paste0("SELECT privilege FROM user_tab_privs 
                                      WHERE table_name = '",pakke,"'"))
  if (nrow(proc_rettigheder)==0){
    stop(paste0(bruger," har ikke rettigheder til at afvikle proceduren ",procedure))
  }
  
  # CHECK INPUT DATA AND CREATE ORACLE TABLES ####
  
  # Check data is input
  if (is.null(ind_tabelnavn) & toupper(procedure)!="BEF_INVALIDE"){
    stop("Angiv navnet på input-tabellen (ind_tabelnavn=).")
  }
  
  #####TODO: set up and correct for different output and input data and locations
  
  if (is.null(ud_tabelnavn) & toupper(ud_data)=="ORACLE"){
    stop("Angiv navnet på output-tabellen (ud_tabelnavn=), der gemmes i Oracle (ud_data=ORACLE).")
  }
  
  if (!is.null(ud_tabelnavn) & toupper(ud_data)=="R"){
    message("NOTE: Variablen 'ud_tabelnavn' ignoreres, da output-tabellen returneres i R (ud_data=R).")
  }
  
  # Check column names and save data to Oracle
  if (!is.null(ind_tabelnavn)){
    names(ind_tabelnavn) <- toupper(names(ind_tabelnavn))
    
    # Does data include a column with the required column name
    if (!(kolonneNavn %in% names(ind_tabelnavn))){
      stop(paste0("Der findes ikke en kolonne ",kolonneNavn," i input-tabellen."))
    }
    
    dbWriteTable(psd, "BEF_ID_PROC", ind_tabelnavn)
  }
  
  # Create table 'PSDMYTEMP' on ident schema in dp_psd to store temporary data
  dbSendQuery(psd,"create table PSDMYTEMP
                            (v_resultat   VARCHAR2(200),
                            v_koerselsid NUMBER)")
  
  # HANDLE DATETIME VARIABLES ####
  
  # Function to parse and extract date and time from dates and times
  extract_date_time <- function(datetime) {
    # Try different formats
    parsed_datetime <- parse_date_time(datetime, orders = c("ymd HMS", "dmy HMS", "mdy HMS", "ymd HM", "dmy HM", "mdy HM", "ymd", "dmy", "mdy"))
    
    # Extract date and time
    date_part <- as_date(parsed_datetime)
    time_part <- format(parsed_datetime, "%H:%M:%S")
    
    return(list(date = date_part, time = time_part))
  }
  
  if (!is.null(gyldighedsdato)){
    gyldighedsdato <- extract_date_time(gyldighedsdato)$date
    if (is.na(gyldighedsdato)){
      stop("Ukendt format for 'gyldighedsdato'.")
    }
  }
  
  if (!is.null(registerstarttid)){
    datostart <- extract_date_time(registerstarttid)$date
    tidstart <- extract_date_time(registerstarttid)$time
    if (is.na(datostart) | is.na(tidstart)){
      stop("Ukendt format for 'registerstarttid'.")
    }
  }
  
  if (!is.null(registersluttid)){
    datoslut <- extract_date_time(registersluttid)$date
    tidslut <- extract_date_time(registersluttid)$time
    if (is.na(datoslut) | is.na(tidslut)){
      stop("Ukendt format for 'registersluttid'.")
    }
  }
  
  # RUN PROCEDURES ####
  
  # Run procedure - procedures without dates
  if(toupper(procedure) %in% c('BEF_OMKOD','BEF_AKTUELLE_ID','BEF_AKTUELLE_PNR',
                               'BEF_AKTUEL_KOEN_FOEDSELSDAG','BEF_FULD_HISTORIK_ID',
                               'BEF_FULD_HISTORIK_PNR','BEF_FULD_HIS_KOEN_FOEDSELSDAG',
                               'BEF_IDSKIFT')
     & is.null(gyldighedsdato)  & is.null(registertid) & is.null(registerstarttid) 
     & is.null(registersluttid)){
    # Run procedure - automatically saves table in ident schema and saves the run id in psdmytemp
    oracleProc(psd, paste0("DECLARE  v_resultat VARCHAR2(200); 
                                   v_koerselsid NUMBER;\n",
                           "BEGIN ",pakke01,".",procedure,"
                                  (p_projektnummer => '", projektid,"', 
                                  p_bruger => '", postmodtager, "', 
                                  p_ind_tabelnavn => 'BEF_ID_PROC', 
                                  p_resultat => v_resultat, 
                                  p_koerselsid => v_koerselsid);
  
                                  -- Insert values into mytemp to identify output table later
                                  insert into psdmytemp values (v_resultat,V_koerselsid);
                              COMMIT;
                             END;"))
  }
  # Run procedure - procedures with a date
  else if (toupper(procedure) %in% c('BEF_OMKOD','BEF_AKTUELLE_ID','BEF_AKTUELLE_PNR',
                                     'BEF_AKTUEL_KOEN_FOEDSELSDAG')
           & !is.null(gyldighedsdato) & is.null(registertid) & is.null(registerstarttid) 
           & is.null(registersluttid)){
    # Run procedure - automatically saves table in ident schema and saves the run id in psdmytemp
    oracleProc(psd, paste0("DECLARE  v_resultat VARCHAR2(200); 
                                   v_koerselsid NUMBER;\n",
                           "BEGIN ",pakke01,".",procedure,"
                                  (p_projektnummer => '", projektid,"', 
                                  p_bruger => '", postmodtager,"', 
                                  p_ind_tabelnavn => 'BEF_ID_PROC',
                                  p_gyldighedsdato => TO_DATE('",gyldighedsdato,"','YYYY-MM-DD'),
                                  p_resultat => v_resultat, 
                                  p_koerselsid => v_koerselsid);
  
                                  -- Insert values into mytemp to identify output table later
                                  insert into psdmytemp values (v_resultat,V_koerselsid);
                              COMMIT;
                             END;"))
  }
  # Run procedure - procedures with a date and time (historisk)
  else if (toupper(procedure) %in% c('BEF_HISTORISK_ID','BEF_HISTORISK_PNR',
                                     'BEF_HISTORISK_KOEN_FOEDSELSDAG')
           & !is.null(gyldighedsdato) & is.null(registerstarttid) 
           & is.null(registersluttid)){
    
    # find 'registertid' if it isn't given as input
    if (is.null(registertid)) {
      registertid <- dbGetQuery(psd,paste0("select tid from
				(select min(time_stamp) as tid
				 from D101200.bef_leverance_time
				 where trunc(cpr_slut) >= TO_DATE('",gyldighedsdato,"','YYYY-MM-DD'))"))$TID
      if(is.na(registertid)){
        stop(paste("Gyldighedsdato", gyldighedsdato, "findes ikke i PSD registertid tabellen."))
      }
      else {
        print(paste("Der er brugt register datetime =",registertid,"hentet fra PSD tabellen D101200.bef_leverance_time."))
      }
    }
    else {
      datoregister <- extract_date_time(registertid)$date
      tidregister <- extract_date_time(registertid)$time
      if (is.na(datoregister) | is.na(tidregister)){
        stop("Ukendt format for 'registertid'.")
      }
      registertid <- paste(datoregister,tidregister)
    }
    
    # Run procedure - automatically saves table in ident schema and saves the run id in psdmytemp
    oracleProc(psd, paste0("DECLARE  v_resultat VARCHAR2(200); 
                                   v_koerselsid NUMBER;\n",
                           "BEGIN ",pakke01,".",procedure,"
                                  (p_projektnummer => '", projektid,"', 
                                  p_bruger => '", postmodtager,"', 
                                  p_ind_tabelnavn => 'BEF_ID_PROC',
                                  p_gyldighedsdato => TO_DATE('",gyldighedsdato,"','YYYY-MM-DD'),
                                  p_registerdato => TO_TIMESTAMP ('",registertid,"','YYYY-MM-DD HH24:MI:SS.FF'),
                                  p_resultat => v_resultat, 
                                  p_koerselsid => v_koerselsid);
  
                                  -- Insert values into mytemp to identify output table later
                                  insert into psdmytemp values (v_resultat,V_koerselsid);
                              COMMIT;
                             END;"))
  } 
  # Run procedure - procedures with dates and time (fuld historisk)
  else if (toupper(procedure) %in% c('BEF_FULD_HISTORIK_ID','BEF_FULD_HISTORIK_PNR',
                                     'BEF_FULD_HIS_KOEN_FOEDSELSDAG')
           & !is.null(registerstarttid) & !is.null(registersluttid)
           & is.null(gyldighedsdato)  & is.null(registertid)){
    # Run procedure - automatically saves table in ident schema and saves the run id in psdmytemp
    oracleProc(psd, paste0("DECLARE  v_resultat VARCHAR2(200); 
                                   v_koerselsid NUMBER;\n",
                           "BEGIN ",pakke01,".",procedure,"
                                  (p_projektnummer => '", projektid,"', 
                                  p_bruger => '", postmodtager,"', 
                                  p_ind_tabelnavn => 'BEF_ID_PROC',
                								  p_registerstarttid => TO_TIMESTAMP ('",datostart," ",tidstart,"','YYYY-MM-DD HH24:MI:SS.FF'),
                								  p_registersluttid => TO_TIMESTAMP ('",datoslut," ",tidslut,"','YYYY-MM-DD HH24:MI:SS.FF'),
                                  p_resultat => v_resultat, 
                                  p_koerselsid => v_koerselsid);
  
                                  -- Insert values into mytemp to identify output table later
                                  insert into psdmytemp values (v_resultat,V_koerselsid);
                              COMMIT;
                             END;"))
  }
  # Run procedure - bef_invalide without dates (no input table)
  else if (toupper(procedure) %in% c('BEF_INVALIDE')
           & is.null(registerstarttid) & is.null(registersluttid)
           & is.null(gyldighedsdato)  & is.null(registertid)){
    # Run procedure - automatically saves table in ident schema and saves the run id in psdmytemp
    oracleProc(psd, paste0("DECLARE  v_resultat VARCHAR2(200); 
                                   v_koerselsid NUMBER;\n",
                           "BEGIN ",pakke01,".",procedure,"
                                  (p_projektnummer => '", projektid,"', 
                                  p_bruger => '", postmodtager,"', 
                                  p_resultat => v_resultat, 
                                  p_koerselsid => v_koerselsid);
  
                                  -- Insert values into mytemp to identify output table later
                                  insert into psdmytemp values (v_resultat,V_koerselsid);
                              COMMIT;
                             END;"))
  }
  # Run procedure - bef_invalide with dates (no input table)
  else if (toupper(procedure) %in% c('BEF_INVALIDE')
           & !is.null(registerstarttid) & !is.null(registersluttid)
           & is.null(gyldighedsdato)  & is.null(registertid)){
    # Run procedure - automatically saves table in ident schema and saves the run id in psdmytemp
    oracleProc(psd, paste0("DECLARE  v_resultat VARCHAR2(200); 
                                   v_koerselsid NUMBER;\n",
                           "BEGIN ",pakke01,".",procedure,"
                                  (p_projektnummer => '", projektid,"', 
                                  p_bruger => '", postmodtager,"', 
                								  p_registerstarttid => TO_TIMESTAMP ('",datostart," ",tidstart,"','YYYY-MM-DD HH24:MI:SS.FF'),
                								  p_registersluttid => TO_TIMESTAMP ('",datoslut," ",tidslut,"','YYYY-MM-DD HH24:MI:SS.FF'),
                                  p_resultat => v_resultat, 
                                  p_koerselsid => v_koerselsid);
  
                                  -- Insert values into mytemp to identify output table later
                                  insert into psdmytemp values (v_resultat,V_koerselsid);
                              COMMIT;
                             END;"))
  }
  else if ( (!is.null(registerstarttid) & is.null(registersluttid)) | (is.null(registerstarttid) & !is.null(registersluttid)) ) {
    stop("En af parameterene registerstarttid eller registersluttid er udfyldt, enten skal begge eller ingen være udfyldt.")
  }
  else {
    stop("Der er et problem med kombinationen af procedure og de angivne dato- og tidsparametre.
         Tjek, hvilke dato- og tidsparametre den angivne procedure benytter.")
  }
  
  # CREATE OUTPUT TABLE ####
  
  if(table_exists(psd,"PSDMYTEMP",bruger)){
    # Collect v_koerselsid from temporary table
    v_koerselsid <- dbGetQuery(psd, "select max(v_koerselsid) as X from psdmytemp")$X[1]
  
    # Print result of process (successfully run or not)
    print(dbGetQuery(psd, "select v_resultat as X from psdmytemp")$X[1])
  }
  else {
    stop("Noget er gået galt i kørslen.")
  }
  
  if (table_exists(psd,toupper(paste0(praenavn,v_koerselsid)),bruger)){
    # Create output table
    out_table <- dbGetQuery(psd,paste0("select * from ",praenavn,v_koerselsid))
    
    # Drop id table from ident schema
    dbSendQuery(psd,paste0("drop table ",praenavn,v_koerselsid))
  }
  else {
    stop("Noget er gået galt i kørslen.")
  }
  
  # Save or return output table:
  if (toupper(ud_data)=="R"){
    # return the output table
    return(out_table)
  }
  else if (toupper(ud_data)=="ORACLE"){
    # TODO
    # Save data to Oracle and don't return anything to R?
    # Just save the list of converted id's to the ident chema in the same database as original data
  }
  
}



