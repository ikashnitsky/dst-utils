library(ROracle)
library(tidyverse)
library(DSTdb)
library(dbplyr)
library(rlang)

source("K:/DSL/Konvertering til person-id/convert_person_id.R")
source("H:/DevOps/Konvertering/Eksempler på konvertering/convert_person_id.R")


# TEST: BEF_AKTUELLE_PNR AND BEF_AKTUELLE_ID (simple) -----

# RUNS BEF_AKTUELLE_PNR (FROM PERSON_ID TO PNR)
# RUNS BEF_AKTUELLE_ID (FROM PNR TO PERSON_ID)

# Data set with only person_id or pnr (depending on procedure)
x <- tibble(PERSON_ID = c("1234", "2345"))
# NOTE: variable name needs to be PERSON_ID or PNR

# x <- tibble(PERSON_ID = c("1234", "2345")) |> mutate(PERSON_ID = as.factor(PERSON_ID))
# still works

# x <- tibble(PERSON_ID = c("abcd", "bcde"))
# extraction fails with error

# x <- tibble(PERSON_ID = c("1234", "2345"),ALFABET = c("abcd", "bcde"))
# still works - data just needs to include the right column

# x <- tibble(person_id = c("1234", "2345"))
# still works - names can be lowercase

# x <- tibble(PERSON_ID2 = c("1234", "2345"))
# extraction fails with error

test <- convert_person_id(
  procedure = 'bef_aktuelle_pnr',
  in_table_name = x,
  out_table_name = "test"
)

test1 <- convert_person_id(
  procedure = 'BEF_AKTUELLE_PNR',
  in_table_name = x,
  recipient = NULL
)

x2 <- tibble(PNR = test$PNR)

test2 <- convert_person_id(procedure = 'BEF_AKTUELLE_ID', in_table_name = x2)

# add_person_id (from PNR to PERSON_ID with BEF_OMKOD) #############

# Whatever file this would be located in should also source convert_person_id
#source("K:/DSL/Konvertering til person-id/add_person_id.R")

#x3 <- tibble(PNR = test$PNR,ALFABET = c("abcd", "bcde"))
#test_DSL <- add_person_id(x3)

# TEST: BEF_HISTORISK_PNR AND BEF_HISTORISK_ID (simple) -----

# RUNS BEF_HISTORISK_PNR (FROM PERSON_ID TO PNR)
# RUNS BEF_HISTORISK_ID (FROM PNR TO PERSON_ID)

# data from test of BEF_AKTUELLE_PNR

testH0 <- convert_person_id(
  procedure = 'BEF_HISTORISK_PNR',
  in_table_name = x,
  validity_date = 31122021
)


testH <- convert_person_id(
  procedure = 'BEF_HISTORISK_PNR',
  in_table_name = x,
  project_id = MZL,
  validity_date = 31122021,
  registry_time = 16012022
)

testH2 <- convert_person_id(
  procedure = 'BEF_HISTORISK_ID',
  in_table_name = x2,
  validity_date = 31122021,
  registry_time = "16012022 18:00:00"
)


# TEST: BEF_FULD_HISTORIK_PNR OG BEF_FULD_HISTORIK_ID (multiple different time versions) -----

# RUNS BEF_FULD_HISTORIK_ID (FROM PERSON_ID TO PNR)
# RUNS BEF_FULD_HISTORIK_PNR (FROM PNR TO PERSON_ID)

# data from test of BEF_AKTUELLE_PNR

# notice: switch in procedure names for some reason
testF <- convert_person_id(procedure = 'BEF_FULD_HISTORIK_ID', in_table_name = x)

testF2 <- convert_person_id(
  procedure = 'BEF_FULD_HISTORIK_PNR',
  in_table_name = x3
)

testF3 <- convert_person_id(
  procedure = 'BEF_FULD_HISTORIK_ID',
  in_table_name = x,
  registry_start_time = '31122000 120303.232',
  registry_end_time = '31129999 235959.999'
)

testF4 <- convert_person_id(
  procedure = 'BEF_FULD_HISTORIK_PNR',
  in_table_name = x2,
  registry_start_time = '01011900',
  registry_end_time = 01012100
)

testF5 <- convert_person_id(
  procedure = 'BEF_FULD_HISTORIK_ID',
  in_table_name = x,
  registry_start_time = '01-01-1900 12:00',
  registry_end_time = '01012100 12:00:00'
)

testF6 <- convert_person_id(
  procedure = 'BEF_FULD_HISTORIK_PNR',
  in_table_name = x2,
  registry_start_time = '01011900 12',
  registry_end_time = '01-01-2100 12:00:00'
)

testF7 <- convert_person_id(
  procedure = 'BEF_FULD_HISTORIK_ID',
  in_table_name = x,
  registry_start_time = '01-01-2010 12:00',
  registry_end_time = '01012100 12:00:00'
)

testF8 <- convert_person_id(
  procedure = 'BEF_FULD_HISTORIK_PNR',
  in_table_name = x2,
  out_table_name = 'testF8',
  registry_start_time = '01011900 12',
  registry_end_time = '01-01-2000 12:00:00'
)
# NOTE: no error message here
# PERSON_ID becomes 1e+15 - as expected

testF9 <- convert_person_id(
  procedure = 'BEF_FULD_HISTORIK_ID',
  in_table_name = x,
  out_table_name = 'testF9',
  registry_start_time = '01011900 12',
  registry_end_time = '01-01-2000 12:00:00'
)
# PNR becomes "Ukendt-PNR"

# TEST: BEF_AKTUEL_KOEN_FOEDSELSDAG, BEF_HISTORISK_KOEN_FOEDSELSDAG, BEF_FULD_HIS_KOEN_FOEDSELSDAG -----

# RUNS FUNCTIONS FROM PERSON_ID TO SEX AND BIRTHDAY
# data from test of BEF_AKTUELLE_PNR

testKSakt <- convert_person_id(
  procedure = 'bef_aktuel_koen_foedselsdag',
  in_table_name = x
)

testKShis <- convert_person_id(
  procedure = 'bef_historisk_koen_foedselsdag',
  in_table_name = x,
  validity_date = 31122021,
  registry_time = 16012022
)

testKSfhis <- convert_person_id(
  procedure = 'bef_fuld_his_koen_foedselsdag',
  in_table_name = x,
  registry_start_time = '01011900',
  registry_end_time = '01012100'
)


# TEST: BEF_IDSKIFT ------------------------------------------------------------

# RUNS BEF_IDSKIFT (PERSON_ID TO PNR)
# data from test of BEF_AKTUELLE_PNR

testSkift <- convert_person_id(procedure = 'BEF_IDSKIFT', in_table_name = x)

# NOTE: find id with shift

# TEST: BEF_OMKOD ------------------------------------------------------------

# RUNS BEF_OMKOD (PNR TO PERSON_ID - CREATES STATUS=2)

# data with one valid and one invalid PNR
x3 <- tibble(PNR = c("0000101010", x2$PNR[2]))


testOmk <- convert_person_id(procedure = 'BEF_OMKOD', in_table_name = x3)

# For testing invalid
testOmk2 <- convert_person_id(
  procedure = 'BEF_OMKOD',
  in_table_name = x3,
  project_id = "ABC"
)


# TEST: BEF_INVALIDE ------------------------------------------------------------

# KØRER BEF_INVALIDE (finder alle invalide genereret af project_id)
# no input data

# BEMÆRK: proceduren henter ikke invalide person-id'er, der ligger på project_id'et,
#         den henter de invalde id'er, der er DANNET af project_id'et

testInv <- convert_person_id(procedure = 'bef_invalide')
# fetches id with status 2 created by user-ident with BEF_OMKOD

testInv2 <- convert_person_id(procedure = 'bef_invalide', project_id = "D222011")
# On the 'pregDK' schema there are 100,623 invalid ids converted

testInv3 <- convert_person_id(procedure = 'bef_invalide', project_id = "ABC")
# project_id kan være hvad som helst
