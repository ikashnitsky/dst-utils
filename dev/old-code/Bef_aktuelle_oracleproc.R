library(ROracle)
library(tidyverse)
library(DSTdb)
library(dbplyr)

# KØRER BEF_AKTUELLE_PNR (FRA PERSON_ID TIL PNR)
# HENTER FRA TEST_PID_PROC
# INDSÆTTER I AKTPNR453427 (HVOR KOMMER NAVN FRA?)

psd <- DSTdb::get_conn("DB_PSD")

bruger <- Sys.getenv("USERNAME")

x <- tibble(PERSON_ID = c(1234, 2345))

data_navn <- "TEST_PID_PROC"

dbWriteTable(psd, data_navn, x)


oracleProc(
  psd,
  paste0(
    "DECLARE v_projektnummer VARCHAR2(200); v_bruger VARCHAR2(3); 
                       v_ind_tabelnavn VARCHAR2(30); v_resultat VARCHAR2(200); v_koerselsid NUMBER;\n",
    "BEGIN BEF01_pck_laes_personnummer.bef_aktuelle_pnr(p_projektnummer => '",
    bruger,
    "', p_bruger => '",
    bruger,
    "', p_ind_tabelnavn => '",
    data_navn,
    "', p_resultat => v_resultat, p_koerselsid => v_koerselsid);\nEND;"
  )
)

dbListTables(psd)
