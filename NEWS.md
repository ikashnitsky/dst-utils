# DSTutils (development version)

* `convert_person_id()` is restructured; its arguments and the PL/SQL sent to the BEF procedures are unchanged:
  * Inputs are checked before connecting, so bad procedure/date combinations no longer upload data to `DB_PSD` first. The combination error lists what the procedure accepts.
  * Work tables (`BEF_ID_PROC`, `PSDMYTEMP` and the output table) are dropped on every exit, including when a privilege check fails. Tables left by an interrupted run are dropped before the next run.
  * Fixed: each call leaked a second connection to `DB_PSD`.
  * Fixed: run ids such as 3000000 were turned into `"3e+06"`. The output table was then not found, and the PNR mapping was left in the user's schema.
  * Fixed: `procedure = my_var` and `project_id = paste0(...)` sent the literal text to Oracle. Variables and expressions are now evaluated. Quoted strings and bare words work as before.
  * Milliseconds in `registry_time`, `registry_start_time` and `registry_end_time` are kept instead of being dropped.
  * `column_name` now works: it names the id column to upload as `PNR`/`PERSON_ID`.
  * `in_data = "ORACLE"` and `out_data = "ORACLE"` fail at once with "not implemented". Before, `out_data = "ORACLE"` ran the conversion and returned `NULL`.
  * Privilege checks now count privileges granted through roles (`session_privs`, `all_tab_privs`).
  * The procedure's result text and the registry time used are shown with `message()` instead of `print()`.
  * The PL/SQL for every date mode is snapshot-tested, and the call sequence is tested against a fake database.

* `dst_db_privilege_management()` is rewritten:
  * New `dry_run = TRUE` mode runs the full app against a simulated schema, without `DSTdb` or a database.
  * The log no longer lives inside the installed package (where it was lost on reinstall and usually not writable). It is resolved from the `log_dir` argument, the `DSTutils.privilege_log_dir` option, the `DSTUTILS_PRIVILEGE_LOG_DIR` environment variable, or a per-user default. Writes use a lock, so a team can share one log.
  * Each attempt is logged straight away, failures included, with the login of the person who ran it (no longer typed in) and a required reason. Logs written by the old app are upgraded automatically, and a backup is kept.
  * Statements are listed for review before they run. Revoking is now supported. Names are checked before any SQL is built, and grants to `PUBLIC` are blocked.
  * A new "Current access" tab compares the database's privileges with the log.
  * Built with `bslib`; no external fonts or CSS (`bslib` and `DT` added to Imports).

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