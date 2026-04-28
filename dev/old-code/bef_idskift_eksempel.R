library(DSTdb)
library(DBI)

library(tidyverse)
library(dbplyr)

project_schema = "D222401"
run_id <- "JOC"

person_id_tab_name = "PERSON_ID_OPDATERING_TEST_20240802"

conn_project_laese <- DSTdb::get_conn('STATPROD')
conn_project_udvikler <- DSTdb::get_conn(
  'STATPROD',
  proxy = paste("[", project_schema, "]", sep = "")
)
conn_id_skift <- DSTdb::get_conn('DB_PSD')

# get list of all person_ids
person_id_tab <- conn_project_udvikler |>
  tbl(in_schema(project_schema, person_id_tab_name)) |>
  collect()

# write to DB_PSD
dbWriteTable(conn_id_skift, person_id_tab_name, person_id_tab, append = TRUE)

bef_idskift <- function(run_id, person_id_tab_name) {
  sql <- paste0(
    "DECLARE\r\n    v_resultat   VARCHAR2(200);\r\n    v_koerselsid NUMBER;\r\nBEGIN\r\n    BEF01_pck_laes_personnummer.bef_idskift\r\n    (p_projektnummer => '",
    run_id,
    "',\r\n     p_bruger => '",
    run_id,
    "',\r\n     p_ind_tabelnavn => '",
    person_id_tab_name,
    "',\r\n     p_resultat => v_resultat,\r\n     p_koerselsid => v_koerselsid);\r\nend;\r\n"
  )
  dbSendStatement(conn_id_skift, sql)
}

#run idskift procedure
bef_idskift(run_id, person_id_tab_name)

#get output table from procedure
all_tab <- dbListTables(conn_id_skift) #list all tables
IDSKIFT_tab <- all_tab[startsWith(all_tab, "IDSKIFT")] # take all tables starting with IDSKIFT
koer_id <- max(as.numeric(str_remove(IDSKIFT_tab, "IDSKIFT")))
latest_IDSKIFT <- paste0("IDSKIFT", koer_id) #Get the one with highest run-id

idskift <- conn_id_skift |>
  tbl(in_schema(run_id, latest_IDSKIFT)) |>
  select(GL_PERSON_ID, NY_PERSON_ID) |>
  collect()

close_connections()
