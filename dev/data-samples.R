# ..........................................................
# 2026-09-24 -- DSTutils
# data samples --------
# Ilya Kashnitsky, ikx@dst.dk
# ..........................................................

library(tidyverse)
library(dbplyr)
library(DSTdb)
library(tictoc)

library(collapse)
library(kit)


# sync timezones
Sys.setenv(TZ = "Europe/Copenhagen")
Sys.setenv(ORA_SDTZ = "Europe/Copenhagen")

# ROracle connection
conn <- get_conn("db_psd")


# Add 50k BEF and UDD data sample, imported from DSTudtraek ----------------------

# seed for permutation
set.seed(1337)

tic()
## PSD_BEFOLKNING
BEFDATA <- conn |>
  tbl(in_schema("D101200", "PSD_BEFOLKNING")) |>
  filter(REFERENCETID == as.Date("2025-12-31")) |>
  collect() |>
  mutate(across(where(is.POSIXct), as_date))
toc() # 170 sec

BEFOLKNING_REL <- BEFDATA

tic()
BEFOLKNING_REMIX <- BEFOLKNING_REL |>
  mutate(across(
    !where(is.Date) & !ends_with("_ID") & !KOEN,
    ~ sample(.x, length(.x))
  )) |>
  mutate(across(
    where(is.Date) & !any_of(c("REFERENCETID", "DATOPRET")),
    ~ .x + floor(runif(length(.x), min = -3 * 365, max = 3 * 365))
  )) |>
  select(-ends_with("_ID")) %>%
  sample_n(size = nrow(.)) %>%
  mutate(PERSON_ID = row_number())
toc() # 30 sec

PSD_BEFOLKNING <- BEFOLKNING_REMIX %>%
  head(50000)

tic()
UDDDATA <- conn |>
  tbl(in_schema("D400600", "PSD_UDD_STATUS")) |>
  filter(REFERENCETID == as.Date("2025-09-30")) |>
  collect() |>
  mutate(across(where(is.POSIXct), as_date))
toc() # 90 sec

tic()
UDDDATA_REMIX <- UDDDATA |>
  mutate(across(
    !where(is.Date) & !ends_with("_ID"),
    ~ sample(.x, length(.x))
  )) |>
  mutate(across(
    where(is.Date) & !any_of(c("REFERENCETID", "DATOPRET")),
    ~ .x + floor(runif(length(.x), min = -3 * 365, max = 3 * 365))
  )) |>
  select(-ends_with("_ID")) %>%
  sample_n(size = nrow(.)) %>%
  mutate(PERSON_ID = row_number())
toc() # 15 sec


PSD_UDD_STATUS <- UDDDATA_REMIX %>%
  head(50000)

usethis::use_data(
  PSD_BEFOLKNING,
  PSD_UDD_STATUS,
  internal = FALSE,
  overwrite = TRUE
)


# trailing CPR entries ---------------------------------------------------

# one of the datasets from 1995
trailing_cpr_dataset_raw <- haven::read_sas(
  "K:/DSL_Gefion/CAISA/Signe/KRIN/krin1995.sas7bdat"
)

# problematic rows
like_cpr <- scan_for_possible_cpr_sas7bdat(
  "K:/DSL_Gefion/CAISA/Signe/KRIN/krin1995.sas7bdat"
)

# filter the known problematic rows + several more to have 1k
set.seed(911)
trailing_cpr_dataset <- trailing_cpr_dataset_raw |>
  filter(
    # real problematic variable
    seq_along(JOURNR) %in%
      like_cpr$row_ids[[2]] |
      # false alarm
      seq_along(JOURNR) %in%
        {
          like_cpr$row_ids[[1]] |> sample(10)
        } |
      # just add more clean rows
      seq_along(JOURNR) %in% sample(1:nrow(trailing_cpr_dataset_raw), 975)
  ) |>
  # just in case we randomly selected duplicating rows
  distinct()

# save back as parquet
trailing_cpr_dataset |>
  nanoparquet::write_parquet("inst/extdata/trailing_cpr_dataset.parquet")

# save back as sas7bdat
trailing_cpr_dataset |>
  haven::write_sas("inst/extdata/trailing_cpr_dataset.sas7bdat")
