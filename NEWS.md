# DSTutils 0.2.1

* CPR screening: the numeric gate is lowered from `1e9` to `1e8`, so numeric CPRs with day 01-09 (which lose their leading zero) are detected.
* `looks_like_cpr()` now uses `stringfish` (faster) and gains an `nthreads` argument; numeric input in [1e8, 1e10) is zero-padded before the calendar check.
* Numeric parquet columns with a missing footer statistic in any row group are kept as candidates.
* `decode_stats_vec()` replaces per-chunk `decode_numeric_stat()`.
* Zero-row parquet files are handled without error in the parquet scan.
* Skip message reworded to "Skipped N columns that cannot hold a CPR".
* `clock` removed from Imports; `stringfish` added.

# DSTutils 0.2.0

### New Features: CPR Screening Suite

* Added `looks_like_cpr()` to validate whether character or numeric vectors contain 10-digit sequences matching Danish CPR number structure alongside valid `DDMMYY` calendar birthdates using `clock::date_parse()`[cite: 1].
* Added `check_cpr_df_fast()` to scan all columns of an in-memory `data.frame` or `tibble` using `purrr::map()`[cite: 1].
* Introduced zero-row metadata pre-screening routines:
  * `prescan_parquet_columns()`: Inspects Parquet schema types and column chunk min/max values via `nanoparquet::read_parquet_metadata()` using `collapse` grouping and `kit::iif()` to rule out non-CPR columns prior to reading[cite: 1].
  * `prescan_sas_columns()`: Reads metadata headers (`n_max = 0`) via `haven::read_sas()` to prune incompatible column classes from SAS datasets[cite: 1].
* Added accelerated end-to-end file scanners:
  * `scan_for_possible_cpr_parquet()`: Selectively ingests candidate columns from Parquet files and locates row indices matching valid CPR patterns[cite: 1].
  * `scan_for_possible_cpr_sas7bdat()`: Evaluates suspect SAS columns using a two-tier gate (metadata type filter followed by an in-memory range/length check)[cite: 1].

### Package Data & Fixtures

* Added synthetic benchmarking register samples `PSD_BEFOLKNING` (50,000 rows) and `PSD_UDD_STATUS` (50,000 rows) with jittered dates and permuted attributes[cite: 2].
* Shipped external historical test fixtures `trailing_cpr_dataset.parquet` and `trailing_cpr_dataset.sas7bdat` in `inst/extdata/` for audit validation.