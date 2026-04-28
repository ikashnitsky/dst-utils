library(ROracle)
library(tidyverse)
library(DSTdb)
library(dbplyr)
library(rlang)

source("K:/DSL/Konvertering til person-id/bef_personnummer.R")
source("H:/DevOps/Konvertering/Eksempler på konvertering/bef_personnummer.R")


# TEST: BEF_AKTUELLE_PNR OG BEF_AKTUELLE_ID (simpel) -----

# KØRER BEF_AKTUELLE_PNR (FRA PERSON_ID TIL PNR)
# KØRER BEF_AKTUELLE_ID (FRA PNR TIL PERSON_ID)

# Data set with only person_id or pnr (depending on procedure)
x <- tibble(PERSON_ID = c("1234", "2345"))
# OBS: variable name needs to be PERSON_ID or PNR

# x <- tibble(PERSON_ID = c("1234", "2345")) |> mutate(PERSON_ID = as.factor(PERSON_ID))
# still works

# x <- tibble(PERSON_ID = c("abcd", "bcde"))
# udtræk afsluttes med fejl

# x <- tibble(PERSON_ID = c("1234", "2345"),ALFABET = c("abcd", "bcde"))
# still works - data just needs to include the right column

# x <- tibble(person_id = c("1234", "2345"))
# still works - names can be lowercase

# x <- tibble(PERSON_ID2 = c("1234", "2345"))
# udtræk afsluttes med fejl

test <- bef_personnummer(
  procedure = 'bef_aktuelle_pnr',
  ind_tabelnavn = x,
  ud_tabelnavn = "test"
)

test1 <- bef_personnummer(
  procedure = bef_aktuelle_pnr,
  ind_tabelnavn = x,
  postmodtager = NULL
)

x2 <- tibble(PNR = test$PNR)

test2 <- bef_personnummer(procedure = 'BEF_AKTUELLE_ID', ind_tabelnavn = x2)

# DSL_personid (fra pnr til person_id m. bef_omkod) #############

# Whatever file this would be located in should also source bef_personnummer
#source("K:/DSL/Konvertering til person-id/DSL_personid.R")

#x3 <- tibble(PNR = test$PNR,ALFABET = c("abcd", "bcde"))
#test_DSL <- DSL_personid(x3)

# TEST: BEF_HISTORISK_PNR OG BEF_HISTORISK_ID (simpel) -----

# KØRER BEF_HISTORISK_PNR (FRA PERSON_ID TIL PNR)
# KØRER BEF_HISTORISK_ID (FRA PNR TIL PERSON_ID)

# data fra test af BEF_AKTUELLE_PNR

testH0 <- bef_personnummer(
  procedure = 'BEF_HISTORISK_PNR',
  ind_tabelnavn = x,
  gyldighedsdato = 31122021
)


testH <- bef_personnummer(
  procedure = 'BEF_HISTORISK_PNR',
  ind_tabelnavn = x,
  projektid = MZL,
  gyldighedsdato = 31122021,
  registertid = 16012022
)

testH2 <- bef_personnummer(
  procedure = 'BEF_HISTORISK_ID',
  ind_tabelnavn = x2,
  gyldighedsdato = 31122021,
  registertid = "16012022 18:00:00"
)


# TEST: BEF_FULD_HISTORIK_PNR OG BEF_FULD_HISTORIK_ID (multiple different time versions) -----

# KØRER BEF_FULD_HISTORIK_ID (FRA PERSON_ID TIL PNR)
# KØRER BEF_FULD_HISTORIK_PNR (FRA PNR TIL PERSON_ID)

# data fra test af BEF_AKTUELLE_PNR

# notice: switch in procedure names for some reason
testF <- bef_personnummer(procedure = 'BEF_FULD_HISTORIK_ID', ind_tabelnavn = x)

testF2 <- bef_personnummer(
  procedure = 'BEF_FULD_HISTORIK_PNR',
  ind_tabelnavn = x3
)

testF3 <- bef_personnummer(
  procedure = 'BEF_FULD_HISTORIK_ID',
  ind_tabelnavn = x,
  registerstarttid = '31122000 120303.232',
  registersluttid = '31129999 235959.999'
)

testF4 <- bef_personnummer(
  procedure = 'BEF_FULD_HISTORIK_PNR',
  ind_tabelnavn = x2,
  registerstarttid = '01011900',
  registersluttid = 01012100
)

testF5 <- bef_personnummer(
  procedure = 'BEF_FULD_HISTORIK_ID',
  ind_tabelnavn = x,
  registerstarttid = '01-01-1900 12:00',
  registersluttid = '01012100 12:00:00'
)

testF6 <- bef_personnummer(
  procedure = 'BEF_FULD_HISTORIK_PNR',
  ind_tabelnavn = x2,
  registerstarttid = '01011900 12',
  registersluttid = '01-01-2100 12:00:00'
)

testF7 <- bef_personnummer(
  procedure = 'BEF_FULD_HISTORIK_ID',
  ind_tabelnavn = x,
  registerstarttid = '01-01-2010 12:00',
  registersluttid = '01012100 12:00:00'
)

testF8 <- bef_personnummer(
  procedure = 'BEF_FULD_HISTORIK_PNR',
  ind_tabelnavn = x2,
  ud_tabelnavn = 'testF8',
  registerstarttid = '01011900 12',
  registersluttid = '01-01-2000 12:00:00'
)
# OBS: ingen fejlmeddelelse her
# Person_id bliver 1e+15 - som forventet

testF9 <- bef_personnummer(
  procedure = 'BEF_FULD_HISTORIK_ID',
  ind_tabelnavn = x,
  ud_tabelnavn = 'testF9',
  registerstarttid = '01011900 12',
  registersluttid = '01-01-2000 12:00:00'
)
# PNR bliver "Ukendt-PNR"

# TEST: bef_aktuel_koen_foedselsdag, bef_historisk_koen_foedselsdag, bef_fuld_his_koen_foedselsdag -----

# KØRER FUNKTIONER FRA PERSON_ID TIL KOEN OG OG FOEDSELSDAG
# data fra test af BEF_AKTUELLE_PNR

testKSakt <- bef_personnummer(
  procedure = 'bef_aktuel_koen_foedselsdag',
  ind_tabelnavn = x
)

testKShis <- bef_personnummer(
  procedure = 'bef_historisk_koen_foedselsdag',
  ind_tabelnavn = x,
  gyldighedsdato = 31122021,
  registertid = 16012022
)

testKSfhis <- bef_personnummer(
  procedure = 'bef_fuld_his_koen_foedselsdag',
  ind_tabelnavn = x,
  registerstarttid = '01011900',
  registersluttid = '01012100'
)


# TEST: BEF_IDSKIFT ------------------------------------------------------------

# KØRER BEF_IDSKIFT (PERSON_ID TIL PNR)
# data fra test af BEF_AKTUELLE_PNR

testSkift <- bef_personnummer(procedure = 'BEF_IDSKIFT', ind_tabelnavn = x)

# OBS: find id med skift

# TEST: BEF_OMKOD ------------------------------------------------------------

# KØRER BEF_OMKOD (PNR TIL PERSON_ID - DANNER STATUS=2)

# data med ét validt og ét invalidt pnr
x3 <- tibble(PNR = c("0000101010", x2$PNR[2]))


testOmk <- bef_personnummer(procedure = 'BEF_OMKOD', ind_tabelnavn = x3)

# Til test af invalide
testOmk2 <- bef_personnummer(
  procedure = 'BEF_OMKOD',
  ind_tabelnavn = x3,
  projektid = "ABC"
)


# TEST: BEF_INVALIDE ------------------------------------------------------------

# KØRER BEF_INVALIDE (finder alle invalide genereret af projektid)
# intet input data

# BEMÆRK: proceduren henter ikke invalide person-id'er, der ligger på projektid'et,
#         den henter de invalde id'er, der er DANNET af projektid'et

testInv <- bef_personnummer(procedure = 'bef_invalide')
# henter id med status 2 dannet af bruger-ident med BEF_OMKOD

testInv2 <- bef_personnummer(procedure = 'bef_invalide', projektid = "D222011")
# On the 'pregDK' schema there are 100,623 invalid ids converted

testInv3 <- bef_personnummer(procedure = 'bef_invalide', projektid = "ABC")
# projektid kan være hvad som helst
