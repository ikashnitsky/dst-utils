test_that("BEF_AKTUELLE procedures run successfully", {
  skip_if_no_db()

  x <- tibble::tibble(PERSON_ID = c("1234", "2345"))

  test <- convert_person_id(
    procedure = "BEF_AKTUELLE_PNR",
    in_table_name = x,
    out_table_name = "test"
  )

  expect_s3_class(test, "data.frame")
  expect_true("PNR" %in% names(test))

  test1 <- convert_person_id(
    procedure = "BEF_AKTUELLE_PNR",
    in_table_name = x,
    recipient = NULL
  )

  expect_s3_class(test1, "data.frame")

  x2 <- tibble::tibble(PNR = test$PNR)
  test2 <- convert_person_id(
    procedure = "BEF_AKTUELLE_ID",
    in_table_name = x2
  )

  expect_s3_class(test2, "data.frame")
  expect_true("PERSON_ID" %in% names(test2))
})

test_that("BEF_HISTORISK procedures run successfully", {
  skip_if_no_db()

  x <- tibble::tibble(PERSON_ID = c("1234", "2345"))

  test_h0 <- convert_person_id(
    procedure = "BEF_HISTORISK_PNR",
    in_table_name = x,
    validity_date = 31122021
  )
  expect_s3_class(test_h0, "data.frame")

  test_h <- convert_person_id(
    procedure = "BEF_HISTORISK_PNR",
    in_table_name = x,
    project_id = "MZL",
    validity_date = 31122021,
    registry_time = 16012022
  )
  expect_s3_class(test_h, "data.frame")

  # Setup x2 using actual PNRs from test_h0 if needed, but for simplicity
  # we'll use dummy valid PNR format strings if real DB returns actual data
  if (nrow(test_h0) > 0) {
    x2 <- tibble::tibble(PNR = test_h0$PNR)
    test_h2 <- convert_person_id(
      procedure = "BEF_HISTORISK_ID",
      in_table_name = x2,
      validity_date = 31122021,
      registry_time = "16012022 18:00:00"
    )
    expect_s3_class(test_h2, "data.frame")
  }
})

test_that("BEF_FULD_HISTORIK procedures run successfully", {
  skip_if_no_db()

  x <- tibble::tibble(PERSON_ID = c("1234", "2345"))

  test_f <- convert_person_id(
    procedure = "BEF_FULD_HISTORIK_ID",
    in_table_name = x
  )
  expect_s3_class(test_f, "data.frame")

  test_f3 <- convert_person_id(
    procedure = "BEF_FULD_HISTORIK_ID",
    in_table_name = x,
    registry_start_time = "31122000 120303.232",
    registry_end_time = "31129999 235959.999"
  )
  expect_s3_class(test_f3, "data.frame")
})

test_that("KOEN and FOEDSELSDAG procedures work", {
  skip_if_no_db()

  x <- tibble::tibble(PERSON_ID = c("1234", "2345"))

  test_ks_akt <- convert_person_id(
    procedure = "BEF_AKTUEL_KOEN_FOEDSELSDAG",
    in_table_name = x
  )
  expect_s3_class(test_ks_akt, "data.frame")

  test_ks_his <- convert_person_id(
    procedure = "BEF_HISTORISK_KOEN_FOEDSELSDAG",
    in_table_name = x,
    validity_date = 31122021,
    registry_time = 16012022
  )
  expect_s3_class(test_ks_his, "data.frame")
})

test_that("BEF_OMKOD and BEF_INVALIDE procedures work", {
  skip_if_no_db()

  # Test with one valid and one invalid PNR
  x3 <- tibble::tibble(PNR = c("0000101010", "1234567890"))

  test_omk <- convert_person_id(
    procedure = "BEF_OMKOD",
    in_table_name = x3
  )
  expect_s3_class(test_omk, "data.frame")

  test_inv <- convert_person_id(
    procedure = "BEF_INVALIDE"
  )
  expect_s3_class(test_inv, "data.frame")
})
