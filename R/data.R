# R/data.R ----

# R/data.R ----

#' Synthetic Sample of Danish Population Registry Data (BEFOLKNING)
#'
#' A synthetic sample of 50,000 records derived from the Statistics Denmark
#' population registry table (`PSD_BEFOLKNING`), referenced at 2025-12-31.
#'
#' @format A data frame with 50,000 rows and 33 variables:
#' \describe{
#'   \item{ALDER}{Age in completed years.}
#'   \item{ANTBOERNF}{Number of children living in family.}
#'   \item{ANTBOERNH}{Number of children living in household.}
#'   \item{ANTEFAM}{Number of single-parent families.}
#'   \item{ANTPERSF}{Number of persons in family.}
#'   \item{ANTPERSH}{Number of persons in household.}
#'   \item{BETALINGSKOM}{Municipality responsible for payment.}
#'   \item{BOP_VFRA}{Date address registration is valid from.}
#'   \item{CIVST}{Marital status code.}
#'   \item{CIV_VFRA}{Date marital status is valid from.}
#'   \item{DATOPRET}{Date of record creation in the database register.}
#'   \item{FAMILIE_TYPE}{Family composition type code.}
#'   \item{FAM_KOEN}{Gender composition of the family unit.}
#'   \item{FKIRK}{Danish National Church membership indicator.}
#'   \item{FM_MARK}{Parent/guardian marker.}
#'   \item{FOEDREG_KODE}{Parish/authority code of birth registration.}
#'   \item{FOED_DAG}{Day/date of birth.}
#'   \item{FOERSTE_INDVANDRING}{Date of first immigration to Denmark.}
#'   \item{HUSTYPE}{Dwelling and household type category.}
#'   \item{IE_TYPE}{Immigration/origin categorization.}
#'   \item{KOEN}{Gender code.}
#'   \item{KOM}{Municipality code of residence.}
#'   \item{OPHOLDMD_DK}{Months of cumulative residence in Denmark.}
#'   \item{OPR_LAND}{Country of origin code.}
#'   \item{PERSON_ID}{Integer surrogate key generated after row shuffle.}
#'   \item{PLADS}{Position/role in household structure.}
#'   \item{REFERENCETID}{Date scalar indicating reference date (`2025-12-31`).}
#'   \item{REFERENCETYPE}{Type indicator for the reference date window.}
#'   \item{REG}{Registration status code.}
#'   \item{SENESTE_INDVANDRING}{Date of most recent immigration to Denmark.}
#'   \item{STATSB}{Citizenship/nationality country code.}
#'   \item{VERSION}{Register extract version tag.}
#' }
#' @source Statistics Denmark (\emph{Danmarks Statistik}), registry `D101200.PSD_BEFOLKNING`.
#' @keywords datasets
"PSD_BEFOLKNING"


#' Synthetic Sample of Danish Educational Attainment Data (UDD_STATUS)
#'
#' A synthetic sample of 50,000 records derived from the Statistics Denmark
#' education registry table (`PSD_UDD_STATUS`), referenced at 2025-09-30.
#'
#' @format A data frame with 50,000 rows and 18 variables:
#' \describe{
#'   \item{ALMAUDD}{General education attainment code.}
#'   \item{ALMINSTNR}{Institution code for general education.}
#'   \item{ALM_VFRA}{Date general education status is valid from.}
#'   \item{DATOPRET}{Date of record creation in the database register.}
#'   \item{ERHAUDD}{Vocational education attainment code.}
#'   \item{ERHINSTNR}{Institution code for vocational education.}
#'   \item{ERH_VFRA}{Date vocational education status is valid from.}
#'   \item{HFAUDD}{Highest completed education code.}
#'   \item{HFINSTNR}{Institution code for highest completed education.}
#'   \item{HF_KILDE}{Source register for highest completed education.}
#'   \item{HF_VFRA}{Date highest completed education is valid from.}
#'   \item{IGINSTNR}{Institution code for ongoing education.}
#'   \item{IG_VFRA}{Date ongoing education is valid from.}
#'   \item{PERSON_ID}{Integer surrogate key generated after row shuffle.}
#'   \item{REFERENCETID}{Date scalar indicating reference date (`2025-09-30`).}
#'   \item{REFERENCETYPE}{Type indicator for the reference date window.}
#'   \item{UDD}{Current educational enrolment program code.}
#'   \item{VERSION}{Register extract version tag.}
#' }
#' @source Statistics Denmark (\emph{Danmarks Statistik}), registry `D400600.PSD_UDD_STATUS`.
#' @keywords datasets
"PSD_UDD_STATUS"


#' Sample KRIN 1995 Extract with Trailing CPR Sequences (Parquet)
#'
#' A raw benchmarking extract of ~1,000 records sourced from the historical
#' 1995 Criminal Register (`KRIN`) dataset (`krin1995.sas7bdat`), serialized as
#' an Apache Parquet binary file with column-chunk metadata.
#'
#' @details
#' This dataset acts as a test fixture for metadata-accelerated screening
#' routines like [scan_for_possible_cpr_parquet()]. It contains a curated mix of:
#' \itemize{
#'   \item Positive matches: Records containing genuine trailing 10-digit CPR
#'     sequences with valid calendar dates (`DDMMYY`).
#'   \item False alarms: Records matching 10-digit numeric patterns that fail
#'     calendar date validation.
#'   \item Baseline noise: Clean historical registry observations.
#' }
#' Stored in `inst/extdata/trailing_cpr_dataset.parquet`. Retrieve its runtime
#' path using `system.file("extdata", "trailing_cpr_dataset.parquet", package = "DSTutils")`.
#'
#' @format A Parquet file readable into a `tibble` or `data.frame` via
#'   [nanoparquet::read_parquet()], retaining original SAS column types and names.
#' @source Statistics Denmark (\emph{Danmarks Statistik}), historical research extract `krin1995.sas7bdat`.
#' @keywords datasets
#' @name trailing_cpr_dataset.parquet
NULL


#' Sample KRIN 1995 Extract with Trailing CPR Sequences (SAS7BDAT)
#'
#' A raw benchmarking extract of ~1,000 records sourced from the historical
#' 1995 Criminal Register (`KRIN`) dataset (`krin1995.sas7bdat`), formatted as
#' a native SAS binary database (`.sas7bdat`).
#'
#' @details
#' Used to evaluate two-tier SAS pre-screening functions like
#' [scan_for_possible_cpr_sas7bdat()]. Because SAS files store schema types
#' without chunk min/max statistics, this fixture tests the zero-row metadata
#' gate (`n_max = 0`) combined with downstream in-memory column filtering.
#' Contains validated CPR hits, calendar false positives, and unflagged rows.
#'
#' Stored in `inst/extdata/trailing_cpr_dataset.sas7bdat`. Retrieve its runtime
#' path using `system.file("extdata", "trailing_cpr_dataset.sas7bdat", package = "DSTutils")`.
#'
#' @format A binary SAS dataset readable via [haven::read_sas()].
#' @source Statistics Denmark (\emph{Danmarks Statistik}), historical research extract `krin1995.sas7bdat`.
#' @keywords datasets
#' @name trailing_cpr_dataset.sas7bdat
NULL
