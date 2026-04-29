# in order to read sas data
library(haven)

# code for conversion of id
source("K:/DSL/Konvertering til person-id/convert_person_id.R")

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
pnr_idents <- convert_person_id(
  #project_id="d101200",
  procedure = "BEF_HISTORISK_ID",
  in_table_name = pnr,
  validity_date = 01012021
)


# look at invalid id's
invalid_person <- pnr_idents |> filter(PERSON_ID == 999999999999999)

# look at valid id's
valid_person <- pnr_idents |>
  filter(PERSON_ID != 999999999999999) |>
  distinct(PERSON_ID, .keep_all = TRUE)
# no duplicates!

# Note: error in SAS code when finding invalid id's using duplicates rather than 999999999999999

# Collecting newer information on the pnr's with missing personid
pnr_idents2 <- convert_person_id(
  #project_id=d101200,
  procedure = "BEF_HISTORISK_ID",
  in_table_name = invalid_person,
  validity_date = 31122021
)
# all found

# Test of other procedures #########

# full history rather than historic from specific time
pnr_idents_full <- convert_person_id(
  procedure = "BEF_FULD_HISTORIK_PNR",
  in_table_name = pnr
)

# looking at duplicates
pnr_idents_full_dup <- pnr_idents_full |>
  group_by(PNR) |>
  filter(n() > 1) |>
  ungroup()
# for all duplicates, nothing has changed...

#person_id data including duplicates
person_id_full <- tibble(PERSON_ID = pnr_idents_full$PERSON_ID)

# looking at id changes
id_shift_full <- convert_person_id(
  procedure = "BEF_IDSKIFT",
  in_table_name = person_id_full
)
# none for these data
