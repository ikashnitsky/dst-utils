

library(ROracle)
library(tidyverse)
library(DSTdb)
library(dbplyr)

source("K:/DSL/Konvertering til person-id/bef_personnummer.R")

# Return the original table with extra columns PERSON_ID and STATUS

# Converts from PNR to PERSON_ID using BEF_OMKOD

# Note: output table still includes variable PNR to check further if missing etc.

DSL_personid <- function(tabel){
  # Get PNR from table
  names(tabel) <- toupper(names(tabel))
  cpr <- tabel |> select(PNR) |> distinct()
  
  # Convert id using bef_personnummer
  cpr_id <- bef_personnummer(projektid="K22DSL",procedure="bef_omkod",ind_tabelnavn=cpr)
  
  # Create full output table
  tabel_id <- tabel |> left_join(cpr_id, by = "PNR") 
  
  return(tabel_id)
  
}


# Lav template-dokument for konvertering hver vej med tjek for dubletter, missing 
# og fjern af pnr-variabel (hvis pnr til person_id)
# Skal have eksempel på at hente data fra både SAS, csv og Oracle
