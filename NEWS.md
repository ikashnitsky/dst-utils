# DSTutils (development version)

* `convert_person_id()` can read its input from and write its output to Oracle:
  * `in_data = "ORACLE"` takes `in_table_name = "SCHEMA.TABLE"` from `in_database`. Within `DB_PSD` the distinct ids are copied with `CREATE TABLE ... AS SELECT`. From other databases they are read into R and uploaded. The table and id column are checked (`all_tab_columns`) before anything is uploaded.
  * `out_data = "ORACLE"` saves the output as `out_table_name`. In `DB_PSD` the procedure's table is renamed and kept in your schema. For other databases it is copied in chunks (`options(DSTutils.chunk_size =)`), and a partly written table is dropped on error. The name is checked, the table must not exist, and CREATE TABLE is checked on the target, all before the upload. The table name is returned invisibly.
  * New arguments `in_database`, `out_database` and `proxy` (proxy schema for databases other than `DB_PSD`). `database` is deprecated; if given, it is the default for both.
  * The run-id table is now `PSDMYTEMP_<time>_<process id>` instead of `PSDMYTEMP`, so it no longer clashes with other runs or a SAS job. The old `PSDMYTEMP` is no longer dropped; run tables older than one day are. **This changes the PL/SQL block** (the `insert into` line only; the procedure call is unchanged).
  * The registry time for the historic procedures is fetched as text, not as `POSIXct`. This avoids a time-zone round trip.
  * A numeric `PNR` column gives a warning, because PNRs with day 01-09 have lost their leading zero.

* New vignette `vignette("convert-person-id")`: one example per procedure family, and when to use validity vs. registry time.

* **Breaking:** `add_person_id()` now drops the `PNR` column after conversion, as the SAS macro does. Use `drop_pnr = FALSE` to keep it.

* `convert_person_id()` is restructured; its arguments and the PL/SQL sent to the BEF procedures are unchanged:
  * Inputs are checked before connecting, so bad procedure/date combinations no longer upload data to `DB_PSD` first. The combination error lists what the procedure accepts.
  * Work tables (`BEF_ID_PROC`, `PSDMYTEMP` and the output table) are dropped on every exit, including when a privilege check fails. Tables left by an interrupted run are dropped before the next run.
  * Fixed: each call leaked a second connection to `DB_PSD`.
  * Fixed: run ids such as 3000000 were turned into `"3e+06"`. The output table was then not found, and the PNR mapping was left in the user's schema.
  * Fixed: `procedure = my_var` and `project_id = paste0(...)` sent the literal text to Oracle. Variables and expressions are now evaluated. Quoted strings and bare words work as before.
  * Milliseconds in `registry_time`, `registry_start_time` and `registry_end_time` are kept instead of being dropped.
  * `column_name` now works: it names the id column to upload as `PNR`/`PERSON_ID`.
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