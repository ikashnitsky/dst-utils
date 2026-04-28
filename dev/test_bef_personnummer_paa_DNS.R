# in order to read sas data
library(haven)

# code for conversion of id
source("K:/DSL/Konvertering til person-id/bef_personnummer.R")

# read sas data
dns2021 <- read_sas(
  "K:/DSL_datadepot/EHE/Social ulighed i adgang til semaglutid/DNS2021/dns2021.sas7bdat"
)

# create table of just PNR
pnr <- as.data.frame(dns2021) |>
  mutate(PNR = v_pnr) |>
  select(PNR) |>
  arrange(PNR) |>
  distinct()


# Replicating code from SAS ############

# It matches output from SAS!
# OBS: this is slow, collecting too much data into environment?

# run conversion
pnr_identer <- bef_personnummer(
  #projektid="d101200",
  procedure = "BEF_HISTORISK_ID",
  ind_tabelnavn = pnr,
  gyldighedsdato = 01012021
)


# look at invalid id's
invalid_person <- pnr_identer |> filter(PERSON_ID == 999999999999999)

# look at valid id's
valid_person <- pnr_identer |>
  filter(PERSON_ID != 999999999999999) |>
  distinct(PERSON_ID, .keep_all = TRUE)
# no duplicates!

# Note: error in SAS code when finding invalid id's using duplicates rather than 999999999999999

# Collecting newer information on the pnr's with missing personid
pnr_identer2 <- bef_personnummer(
  #projektid=d101200,
  procedure = "BEF_HISTORISK_ID",
  ind_tabelnavn = invalid_person,
  gyldighedsdato = 31122021
)
# all found

# Test of other procedures #########

# full history rather than historic from specific time
pnr_identer_fuld <- bef_personnummer(
  procedure = "BEF_FULD_HISTORIK_PNR",
  ind_tabelnavn = pnr
)

# looking at duplicates
pnr_identer_fuld_dup <- pnr_identer_fuld |>
  group_by(PNR) |>
  filter(n() > 1) |>
  ungroup()
# for all duplicates, nothing has changed...

#person_id data including duplicates
person_id_fuld <- tibble(PERSON_ID = pnr_identer_fuld$PERSON_ID)

# looking at id changes
id_skift_fuld <- bef_personnummer(
  procedure = "BEF_IDSKIFT",
  ind_tabelnavn = person_id_fuld
)
# none for these data
