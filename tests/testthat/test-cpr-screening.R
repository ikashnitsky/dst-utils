test_that("looks_like_cpr handles character shapes and calendar", {
  x <- c("0101901234", "010190-1234", " 010190 1234 ", "9999991234", "123",
         "3202901234", "2902001234", "2902011234", "3104991234", NA, "")
  expect_equal(
    looks_like_cpr(x),
    c(TRUE, TRUE, TRUE, FALSE, FALSE, FALSE, TRUE, FALSE, FALSE, FALSE, FALSE)
  )
})

test_that("looks_like_cpr handles numeric CPR incl. dropped leading zero", {
  expect_true(looks_like_cpr(1501901234))
  expect_true(looks_like_cpr(101901234))
  expect_false(looks_like_cpr(99999999))
  expect_false(looks_like_cpr(1501901234.5))
  expect_false(looks_like_cpr(12345678901))
  expect_equal(looks_like_cpr(c(NA, 101901234)), c(FALSE, TRUE))
})

test_that("looks_like_cpr handles factors and other types", {
  f <- factor(c("0101901234", "abc", "0101901234", NA))
  expect_equal(looks_like_cpr(f), c(TRUE, FALSE, TRUE, FALSE))
  expect_equal(looks_like_cpr(as.Date("2020-01-01")), FALSE)
  expect_equal(looks_like_cpr(logical(0)), logical(0))
})

test_that("decode_stats_vec decodes footer statistics", {
  i32 <- list(writeBin(5L, raw()), writeBin(-3L, raw()), raw(0), NULL)
  expect_equal(decode_stats_vec(i32, "INT32"), c(5, -3, NA, NA))
  dbl <- list(writeBin(1.5e9, raw()), raw(0))
  expect_equal(decode_stats_vec(dbl, "DOUBLE"), c(1.5e9, NA))
  i64 <- list(
    writeBin(c(1501901234L, 0L), raw()),
    writeBin(c(-1L, 2L), raw())
  )
  expect_equal(decode_stats_vec(i64, "INT64"), c(1501901234, 3 * 2^32 - 1))
  expect_equal(decode_stats_vec(list(as.raw(1)), "BYTE_ARRAY"), NA_real_)
})

test_that("parquet scan flags leading-zero numeric CPR and skips small numbers", {
  skip_if_not_installed("nanoparquet")
  df <- data.frame(
    cpr_chr = c("0101901234", "x", "y"),
    cpr_num_lz = c(101901234, 102901234, 103901234),
    cpr_num = c(1501901234, 2, 3),
    small = c(1L, 2L, 3L),
    n8 = c(12345678, 2, 3),
    stringsAsFactors = FALSE
  )
  f <- tempfile(fileext = ".parquet")
  nanoparquet::write_parquet(df, f)

  pre <- prescan_parquet_columns(f)
  got <- stats::setNames(pre$could_hold_cpr, pre$name)
  expect_true(got[["cpr_num_lz"]])
  expect_true(got[["cpr_num"]])
  expect_false(got[["small"]])
  expect_false(got[["n8"]])

  utils::capture.output(r <- scan_for_possible_cpr_parquet(f))
  expect_setequal(r$column, c("cpr_chr", "cpr_num_lz", "cpr_num"))
  expect_equal(r$hits[r$column == "cpr_num_lz"], 3L)
})

test_that("parquet scan does not error on a file with zero rows", {
  skip_if_not_installed("nanoparquet")
  f <- tempfile(fileext = ".parquet")
  nanoparquet::write_parquet(data.frame(a = character(0), b = integer(0)), f)
  expect_no_error(utils::capture.output(r <- scan_for_possible_cpr_parquet(f)))
  expect_equal(nrow(r), 0L)
})
