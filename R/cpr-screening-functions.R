utils::globalVariables(c("hits", "name"))

# ..........................................................
# 2026-09-24 -- DSTutils
# screen dataset for CPR                -----------
# IKX, LWH, SDN
# Patched 2026-11-23: faster looks_like_cpr() (stringfish), leading-zero
# numeric CPR detection gap fixed, zero-row parquet guard.
# ..........................................................

# dependencies to declare in DESCRIPTION:
# Imports: collapse, haven, kit, nanoparquet, purrr, stringfish, tictoc, tidyselect

# one vector -------------------------------------------------------------

#' Check Vector Elements for CPR Number Shape and Valid Birthdate
#'
#' @description
#' Tests whether character or numeric inputs match the structural layout of a
#' Danish Personal Identification Number (CPR: *Det Centrale Personregister*).
#' Character inputs are stripped of non-digit characters and evaluated for an
#' exact 10-digit length alongside a valid `DDMMYY` calendar prefix (leap days
#' included).
#'
#' Numeric input is treated as a CPR stored as a number. A CPR with a day
#' between 01 and 09 loses its leading zero when stored numerically and then
#' has only 9 digits, so integer-valued numbers from `1e8` up to `9999999999`
#' are zero-padded to 10 digits before the calendar check. This favours
#' sensitivity over specificity, since the function is used for leak screening.
#'
#' @param x A vector (typically character, numeric, or factor) to evaluate.
#' @param nthreads Integer. Threads used by the string operations.
#'
#' @return A logical vector of identical length to `x`, containing `TRUE` for elements
#'   matching CPR structural and calendar criteria, `FALSE` otherwise. `NA` values
#'   in `x` evaluate to `FALSE`.
#'
#' @export
#' @examples
#' looks_like_cpr(c("0101901234", "010190-1234", "9999991234", "123", NA))
#' # numeric CPR that lost its leading zero (01 01 90 1234)
#' looks_like_cpr(101901234)
looks_like_cpr <- function(x, nthreads = 1L) {
  if (is.factor(x)) {
    lv <- looks_like_cpr(levels(x), nthreads = nthreads)
    return(lv[as.integer(x)] %in% TRUE)
  }
  out <- logical(length(x))
  if (is.character(x)) {
    # >= 10 characters is necessary for >= 10 digits; cheap gate before regex
    cand <- which(stringfish::sf_nchar(x, nthreads = nthreads) >= 10L)
    if (length(cand) == 0L) {
      return(out)
    }
    s <- stringfish::sf_gsub(x[cand], "[^0-9]", "", nthreads = nthreads)
    keep <- which(stringfish::sf_nchar(s, nthreads = nthreads) == 10L)
    if (length(keep) > 0L) {
      out[cand[keep]] <- cpr_date_ok(as.numeric(s[keep]))
    }
  } else if (is.numeric(x)) {
    cand <- which(x >= 1e8 & x < 1e10 & x == floor(x))
    if (length(cand) > 0L) {
      out[cand] <- cpr_date_ok(as.numeric(x[cand]))
    }
  } else {
    return(looks_like_cpr(as.character(x), nthreads = nthreads))
  }
  out
}

#' DDMMYY Calendar Check on Numeric CPR Values
#'
#' @param n Numeric vector of values in `[1e8, 1e10)` (leading zeros implied).
#' @return Logical vector; `TRUE` when `DDMMYY` is a real calendar date.
#' @details `yy` divisible by 4 (including `00`, i.e. 2000) is treated as a
#'   leap year, matching the `%y` century mapping of `clock::date_parse()`
#'   (00-68 -> 20xx, 69-99 -> 19xx) used previously.
#' @noRd
cpr_date_ok <- function(n) {
  dd <- n %/% 1e8
  mm <- (n %/% 1e6) %% 100
  yy <- (n %/% 1e4) %% 100
  days <- integer(100)
  days[2:13] <- c(31L, 28L, 31L, 30L, 31L, 30L, 31L, 31L, 30L, 31L, 30L, 31L)
  max_dd <- days[mm + 1L] + (mm == 2 & yy %% 4 == 0)
  dd >= 1 & dd <= max_dd
}


# purrr function to apply to the whole dataset ---------------------------

#' Scan All Data Frame Columns for CPR-like Values
#'
#' @description
#' Iterates across every column in a data frame or tibble, executing [looks_like_cpr()]
#' across each vector without prior metadata screening.
#'
#' @param df A `data.frame` or `tibble` to scan.
#'
#' @return A named list of logical vectors corresponding to each column in `df`.
#'
#' @export
#' @examples
#' test_df <- data.frame(
#'   id = 1:2,
#'   cpr = c("010190-1234", "invalid"),
#'   stringsAsFactors = FALSE
#' )
#' check_cpr_df(test_df)
check_cpr_df <- function(df) {
  df |>
    purrr::map(looks_like_cpr)
}


# pre-screen parquet metadata --------------------------------------------

#' Decode Raw Parquet Metadata Statistics
#'
#' @description
#' Vectorised decoding of binary little-endian min/max values stored in Parquet
#' column chunk metadata. All elements must share one physical type.
#'
#' @param raw_list A list of `raw` vectors (footer statistics).
#' @param ptype Character scalar, physical Parquet type (`"INT32"`, `"INT64"`,
#'   `"FLOAT"`, `"DOUBLE"`).
#'
#' @return A numeric vector the length of `raw_list`; `NA_real_` where a
#'   statistic is missing or cannot be decoded.
#' @noRd
decode_stats_vec <- function(raw_list, ptype) {
  res <- rep(NA_real_, length(raw_list))
  w <- switch(ptype, INT32 = 4L, FLOAT = 4L, INT64 = 8L, DOUBLE = 8L, NULL)
  if (is.null(w)) {
    return(res)
  }
  ok <- lengths(raw_list) == w
  k <- sum(ok)
  if (k == 0L) {
    return(res)
  }
  b <- unlist(raw_list[ok], use.names = FALSE)
  res[ok] <- switch(
    ptype,
    INT32 = as.numeric(readBin(b, "integer", k, 4L, endian = "little")),
    FLOAT = readBin(b, "double", k, 4L, endian = "little"),
    DOUBLE = readBin(b, "double", k, 8L, endian = "little"),
    INT64 = {
      i <- matrix(readBin(b, "integer", 2L * k, 4L, endian = "little"), nrow = 2L)
      lo <- i[1L, ]
      lo <- lo + (lo < 0) * 2^32
      lo + i[2L, ] * 2^32
    }
  )
  res
}

#' Pre-screen Parquet Metadata for CPR-Candidate Columns
#'
#' @description
#' Inspects the Parquet file schema and footer summary statistics (min/max chunks)
#' via [nanoparquet::read_parquet_metadata()] to rule out columns that cannot contain
#' a 10-digit CPR sequence without reading row data into memory.
#'
#' Numeric columns are ruled out only when every row group reports a maximum
#' below `1e8` (a CPR with a dropped leading zero has 9 digits). A numeric
#' column with a missing statistic in any row group is kept as a candidate.
#'
#' @param path Character scalar. Path to the Parquet file on disk.
#'
#' @return A `data.frame` with two columns:
#'   * `name`: Column identifier (`character`).
#'   * `could_hold_cpr`: Logical flag indicating if the column requires deep inspection.
#'
#' @export
#' @examples
#' \dontrun{
#' prescan_parquet_columns("data/trailing_cpr_dataset.parquet")
#' }
prescan_parquet_columns <- function(path) {
  meta <- nanoparquet::read_parquet_metadata(path)

  leaf <- meta$schema[
    is.na(meta$schema$num_children),
    c("name", "r_type", "type")
  ]
  leaf$column <- seq_len(nrow(leaf)) - 1L

  # no row groups (zero-row file): nothing can hold a CPR
  if (nrow(meta$column_chunks) == 0L) {
    return(data.frame(
      name = leaf$name,
      could_hold_cpr = FALSE,
      row.names = NULL
    ))
  }

  chunks <- collapse::join(
    meta$column_chunks,
    leaf,
    on = "column",
    how = "left",
    verbose = 0
  )

  numeric_types <- c("INT32", "INT64", "FLOAT", "DOUBLE")

  chunks$max_num <- NA_real_
  for (tp in intersect(unique(chunks$type), numeric_types)) {
    i <- which(chunks$type == tp)
    chunks$max_num[i] <- decode_stats_vec(chunks$max_value[i], tp)
  }

  g <- collapse::GRP(chunks$name)

  max_by_col <- collapse::fmax(chunks$max_num, g = g, na.rm = TRUE)
  # a chunk without statistics means the column maximum is unknown
  any_unknown <- collapse::fsum(is.na(chunks$max_num), g = g) > 0
  rtype_by_col <- collapse::ffirst(chunks$r_type, g = g)
  ptype_by_col <- collapse::ffirst(chunks$type, g = g)

  excluded_rtype <- rtype_by_col %in% c("logical", "Date", "POSIXct", "POSIXt")
  is_numeric_col <- ptype_by_col %in% numeric_types

  # 1e8, not 1e9: a numeric CPR with day 01-09 has lost its leading zero
  could_hold_cpr <- kit::iif(
    excluded_rtype,
    FALSE,
    kit::iif(
      is_numeric_col,
      any_unknown | !is.finite(max_by_col) | max_by_col >= 1e8,
      TRUE
    )
  )

  data.frame(name = g$groups, could_hold_cpr = could_hold_cpr, row.names = NULL)
}


# scan parquet -----------------------------------------------------------

#' Scan a Parquet File for CPR Number Matches
#'
#' @description
#' Runs a metadata-accelerated audit on a Parquet file. Columns that cannot mathematically
#' contain a 10-digit CPR are pruned in the footer scan, while remaining candidate
#' columns are ingested selectively and screened row-by-row.
#'
#' @param path Character scalar. Path to the target Parquet file.
#'
#' @return A `data.frame` containing:
#'   * `column`: Name of the flagged column (`character`).
#'   * `hits`: Count of verified CPR occurrences (`integer`).
#'   * `row_ids`: Integer indices of matching records (`list` column).
#'   Only columns containing `hits > 0` are returned.
#'
#' @export
#' @examples
#' \dontrun{
#' scan_for_possible_cpr_parquet("data/trailing_cpr_dataset.parquet")
#' }
scan_for_possible_cpr_parquet <- function(path) {
  tictoc::tic(msg = "Parquet file metadata scanned in")
  scan <- prescan_parquet_columns(path)
  tictoc::toc()

  tictoc::tic(msg = "Suspect columns screened in")
  candidate_cols <- collapse::fsubset(scan, could_hold_cpr, name)$name
  skipped_cols <- collapse::fsubset(scan, !could_hold_cpr, name)$name

  if (length(skipped_cols) > 0) {
    cat(sprintf(
      "  Skipped %d columns that cannot hold a CPR: %s\n",
      length(skipped_cols),
      paste(skipped_cols, collapse = ", ")
    ))
  }
  if (length(candidate_cols) == 0) {
    return(data.frame(column = character(0), hits = integer(0)))
  }

  df <- nanoparquet::read_parquet(path, col_select = candidate_cols)

  row_id_list <- lapply(df, function(col) which(looks_like_cpr(col)))
  hit_counts <- collapse::vlengths(row_id_list)

  result <- data.frame(
    column = names(row_id_list),
    hits = as.integer(hit_counts),
    row.names = NULL
  )
  result$row_ids <- row_id_list

  tictoc::toc()
  collapse::fsubset(result, hits > 0)
}


# SAS functions ----------------------------------------------------------

#' Pre-screen SAS7BDAT Metadata for CPR-Candidate Columns
#'
#' @description
#' Reads SAS dataset metadata without parsing data rows (`n_max = 0`) to detect and
#' prune non-eligible column classes (such as native dates and booleans).
#'
#' @param path Character scalar. File path to the `.sas7bdat` dataset.
#' @param encoding Character scalar. Target file encoding passed to [haven::read_sas()].
#'   Defaults to `"WINDOWS-1252"`.
#'
#' @return A `data.frame` with two columns:
#'   * `name`: Column name (`character`).
#'   * `could_hold_cpr`: Logical flag indicating whether the column requires data ingestion.
#'
#' @export
#' @examples
#' \dontrun{
#' prescan_sas_columns("data/trailing_cpr_dataset.sas7bdat")
#' }
prescan_sas_columns <- function(path, encoding = "WINDOWS-1252") {
  meta_df <- haven::read_sas(path, encoding = encoding, n_max = 0L)
  classes <- vapply(meta_df, function(col) class(col)[1], character(1))

  data.frame(
    name = names(meta_df),
    could_hold_cpr = !classes %in% c("Date", "POSIXct", "POSIXt", "logical"),
    row.names = NULL
  )
}

#' In-Memory Vector Gate for CPR Candidates
#'
#' @description
#' Evaluates whether an in-memory vector has string lengths or numerical limits
#' capable of housing a 10-digit CPR sequence (9 digits for numeric values,
#' which lose a leading zero).
#'
#' @param col A vector to evaluate.
#'
#' @return Logical scalar; `FALSE` if ruled out, `TRUE` if eligible for full screening.
#' @noRd
could_hold_cpr <- function(col) {
  if (inherits(col, c("Date", "POSIXt", "logical"))) {
    return(FALSE)
  }
  if (is.character(col)) {
    return(suppressWarnings(max(nchar(col), na.rm = TRUE)) >= 10)
  }
  if (is.numeric(col)) {
    mx <- suppressWarnings(max(col, na.rm = TRUE))
    return(!is.finite(mx) || mx >= 1e8)
  }
  TRUE
}

#' Scan a SAS7BDAT File for CPR Number Matches
#'
#' @description
#' Two-tier scanner for SAS datasets. Discards non-candidate classes at the metadata
#' level, ingests suspect columns using [haven::read_sas()], applies an in-memory
#' length/range gate, and evaluates candidate vectors via [looks_like_cpr()].
#'
#' @param path Character scalar. File path to the `.sas7bdat` dataset.
#' @param encoding Character scalar. Encoding for SAS string decoding.
#'   Defaults to `"WINDOWS-1252"`.
#'
#' @return A `data.frame` containing:
#'   * `column`: Name of the flagged column (`character`).
#'   * `hits`: Count of verified CPR occurrences (`integer`).
#'   * `row_ids`: Integer indices of matching records (`list` column).
#'   Only columns containing `hits > 0` are returned.
#'
#' @export
#' @examples
#' \dontrun{
#' scan_for_possible_cpr_sas7bdat("data/trailing_cpr_dataset.sas7bdat")
#' }
scan_for_possible_cpr_sas7bdat <- function(path, encoding = "WINDOWS-1252") {
  tictoc::tic(msg = "SAS file metadata scanned in")
  scan <- prescan_sas_columns(path, encoding = encoding)
  tictoc::toc()

  tictoc::tic(msg = "Suspect columns screened in")
  candidate_cols <- collapse::fsubset(scan, could_hold_cpr, name)$name
  skipped_cols <- collapse::fsubset(scan, !could_hold_cpr, name)$name

  if (length(skipped_cols) > 0) {
    cat(sprintf(
      "  Skipped %d columns that cannot hold a CPR: %s\n",
      length(skipped_cols),
      paste(skipped_cols, collapse = ", ")
    ))
  }
  if (length(candidate_cols) == 0) {
    return(data.frame(column = character(0), hits = integer(0)))
  }

  df <- haven::read_sas(
    path,
    encoding = encoding,
    col_select = tidyselect::all_of(candidate_cols)
  )

  still_candidate <- names(df)[vapply(df, could_hold_cpr, logical(1))]
  newly_skipped <- setdiff(names(df), still_candidate)
  if (length(newly_skipped) > 0) {
    cat(sprintf(
      "  Additionally skipped %d columns after reading (value range/length excludes CPR): %s\n",
      length(newly_skipped),
      paste(newly_skipped, collapse = ", ")
    ))
  }
  df <- df[still_candidate]

  row_id_list <- lapply(df, function(col) which(looks_like_cpr(col)))
  hit_counts <- collapse::vlengths(row_id_list)

  result <- data.frame(
    column = names(row_id_list),
    hits = as.integer(hit_counts),
    row.names = NULL
  )
  result$row_ids <- row_id_list

  tictoc::toc()
  collapse::fsubset(result, hits > 0)
}
