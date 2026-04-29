test_that("Integration logic from DNS workflow functions properly", {
  skip_if_no_db()

  # Skip if the specific network drive file doesn't exist on this user's machine
  sas_file_path <- "K:/DSL_datadepot/EHE/Social ulighed i adgang til semaglutid/DNS2021/dns2021.sas7bdat"
  skip_if_not(file.exists(sas_file_path), message = "DNS SAS file is not accessible from this environment")

  has_haven <- requireNamespace("haven", quietly = TRUE)
  skip_if_not(has_haven, message = "haven package required to read SAS data")

  # Read SAS data
  dns2021 <- haven::read_sas(sas_file_path)

  # Create table of just PNR
  pnr <- as.data.frame(dns2021) |>
    dplyr::mutate(PNR = v_pnr) |>
    dplyr::select(PNR) |>
    dplyr::arrange(PNR) |>
    dplyr::distinct()

  # Run conversion
  pnr_idents <- convert_person_id(
    procedure = "BEF_HISTORISK_ID",
    in_table_name = pnr,
    validity_date = "01012021"
  )

  expect_s3_class(pnr_idents, "data.frame")

  # Look at invalid id's
  invalid_person <- pnr_idents |> dplyr::filter(PERSON_ID == 999999999999999)

  # Look at valid id's
  valid_person <- pnr_idents |>
    dplyr::filter(PERSON_ID != 999999999999999) |>
    dplyr::distinct(PERSON_ID, .keep_all = TRUE)

  # Ensure everything partitioned correctly
  expect_equal(nrow(invalid_person) + nrow(valid_person), nrow(pnr_idents))

  # Collecting newer information on the pnr's with missing personid
  if (nrow(invalid_person) > 0) {
    pnr_idents2 <- convert_person_id(
      procedure = "BEF_HISTORISK_ID",
      in_table_name = invalid_person,
      validity_date = "31122021"
    )
    expect_s3_class(pnr_idents2, "data.frame")
  }

  # Test full history
  pnr_idents_full <- convert_person_id(
    procedure = "BEF_FULD_HISTORIK_PNR",
    in_table_name = pnr
  )
  expect_s3_class(pnr_idents_full, "data.frame")

  person_id_full <- tibble::tibble(PERSON_ID = pnr_idents_full$PERSON_ID)

  # look at id changes
  id_shift_full <- convert_person_id(
    procedure = "BEF_IDSKIFT",
    in_table_name = person_id_full
  )
  expect_s3_class(id_shift_full, "data.frame")
})
