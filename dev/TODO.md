# Development TODOs — `convert_person_id()`

Collected from the inline TODOs of the original `bef_personnummer()` (see
`dev/bef_personnummer.R`) and from the review of `dev/old-code`.

**Ground rule for all items below:** nothing may change what the BEF procedures
receive without a DB test on DST. That covers the Danish PL/SQL parameter
names (`p_projektnummer`, `p_bruger`, `p_ind_tabelnavn`, `p_gyldighedsdato`,
`p_registerdato`, `p_registerstarttid`, `p_registersluttid`, `p_resultat`,
`p_koerselsid`), the package names and the output-table prefixes. The PL/SQL
is snapshot-tested in `tests/testthat/_snaps/convert_person_id.md`. If a
snapshot changes, run `tests/testthat/test-convert_person_id.R` against the
real `DB_PSD` before merging.

## Done

- [x] **Character arguments:** `arg_as_string()` replaces the
  `deparse(substitute())` copies. Quoted and bare words work as before;
  variables and expressions now work too.
- [x] **`toupper()` for name checks:** procedure names, column names and
  `in_data`/`out_data` are upper-cased. The owner check uses the Oracle
  `USER`, not the Windows `USERNAME`.
- [x] **`column_name` as input:** the column is renamed to `PNR`/`PERSON_ID`
  in R before upload. The Oracle procedures still take no column name.
- [x] **`in_table_name` only from R:** must be a data frame.
  `in_data`/`out_data = "ORACLE"` now fail at once with "not implemented".
  Before, `out_data = "ORACLE"` ran the conversion and returned `NULL`.
- [x] **Milliseconds:** kept when given (`"235959.999"` → `23:59:59.999`).
  Before, they were dropped silently. Values without milliseconds produce
  exactly the same PL/SQL as before.
- [x] **No PSD access:** connection failure now gives a clear error.
  Privileges granted through roles are counted (`session_privs`,
  `all_tab_privs`).
- [x] **Robustness:** all input is validated before connecting. Work tables
  are dropped on every exit. Fixed the leaked second connection and run ids in
  scientific notation (`HIS_ID3e+06`). Values in the PL/SQL are quoted.

## Next steps (planned)

### 1. `out_data = "ORACLE"`
Decide first: keep the result on `DB_PSD`, or write it to another database?
- **Option A (cheap, like the SAS macro):** keep the output table in the ident
  schema on `DB_PSD`, i.e. `ALTER TABLE <prefix><run id> RENAME TO
  <out_table_name>`, and do not drop it. Return the name invisibly.
- **Option B (other database):** read the output into R and write it with
  `DBI::dbWriteTable()` on a connection to the target database. Use chunks for
  large tables.
- Both options need: `out_table_name` validated as an Oracle identifier
  (`^[A-Z][A-Z0-9_$#]{0,127}$`), an error if the table already exists
  (`table_exists()`), and a CREATE TABLE check on the target
  (`session_privs`). The old `user_sys_privs` check for this was removed
  together with the unused second connection.
- Tests: extend `local_fake_psd()`, then one manual run on DST.

### 2. `in_data = "ORACLE"` and other databases
- Interface: `in_table_name = "SCHEMA.TABLE"`, plus `database` and an
  optional proxy schema (`DSTdb::get_conn(database, proxy = "[D222401]")`,
  see `dev/old-code/bef_idskift_eksempel.R`). Consider splitting `database`
  into `in_database`/`out_database`. Keep `database` working for a while with a
  deprecation message.
- If the table is in `DB_PSD`: try
  `CREATE TABLE BEF_ID_PROC AS SELECT DISTINCT <id> FROM schema.table`, which
  needs the user to be able to read the table. **Verify** whether
  `p_ind_tabelnavn` accepts a schema-qualified name. If it does, nothing needs
  copying.
- Other databases: read with `dplyr::tbl(in_schema()) |> distinct() |>
  collect()` and upload. Check the table exists and is readable
  (`all_tables` / `all_tab_privs`) before starting.

### 3. Upload only the distinct id column (needs a DB check)
At the moment the whole input data frame is uploaded to `DB_PSD`, as before.
**Verify on DST** whether the procedure output contains columns from the input
other than the id:
- If it does not: upload `dplyr::distinct(input, <id>)` only. That is faster
  and sends less data. `add_person_id()` already does this.
- If it does: keep the current behaviour and document it.

### 4. Id column type and length
- Numeric PNRs lose their leading zero (day 01–09), and Oracle will not
  match them. Warn when `PNR` is numeric, and offer zero-padding
  (`sprintf("%010.0f", x)`) or validation with `looks_like_cpr()`.
- After upload, `user_tab_columns` for `BEF_ID_PROC` could check the Oracle
  type. Ask the PSD team which types the procedures expect.

### 5. Concurrent runs
The fixed names `BEF_ID_PROC` and `PSDMYTEMP` mean two simultaneous runs by
the same user clobber each other. This also affects a SAS job that uses the
same names, if there is one.
- `PSDMYTEMP` is only used inside our own PL/SQL, so it can get a unique name
  now. Better still, drop it and read `v_resultat`/`v_koerselsid` as OUT binds
  via `ROracle::oracleProc()`.
- A unique input table (`BEF_ID_PROC_<random>`) needs verification that the
  procedures accept any `p_ind_tabelnavn`. `bef_idskift_eksempel.R` suggests
  they do.

### 6. Smaller items
- **`DROP TABLE ... PURGE`** for work tables, so CPR data does not stay in
  the recycle bin. Check with the PSD team first.
- **Registry-time lookup:** fetch `min(time_stamp)` as text
  (`TO_CHAR(CAST(... AS TIMESTAMP), 'YYYY-MM-DD HH24:MI:SS.FF6')`). This
  avoids the ROracle time-zone round trip through `POSIXct`. Today the
  `POSIXct` value is pasted back as before.
- **`p_bruger` / `recipient`:** **verify** in which schema the output table is
  created when `recipient` is not the user. `bef_idskift_eksempel.R` reads it
  from the `p_bruger` schema. If so, look for the table there and use a
  qualified name.
- **`BEF_IDSKIFT` output:** inspect the columns on DST. The legacy script
  keeps only `GL_PERSON_ID`, `NY_PERSON_ID`. Leave `select *` unless internal
  columns turn up.
- **Testing on ids with shifts:** add a DB test with known shifted
  `PERSON_ID`s (ask K22 for a test set).
- **Pseudonymisation in `add_person_id()`:** the SAS macro drops `PNR` after
  conversion (`drop pnr; /* meget vigtigt */`). Add `drop_pnr = TRUE`. This
  is a behaviour change for existing callers, so announce it in NEWS.

## Open questions (need input from users / the PSD team)

- Which date and time formats do people actually type? The parser accepts
  `ymd`, `dmy` and `mdy`, with or without `HMS`/`HM`. A string like
  `"02012021"` is read as `dmy` (2 January).
- Does anyone match on milliseconds? They are now kept, but nobody has
  confirmed this matters.
- How do users know when to use `validity_date` + `registry_time` and when
  `registry_start_time` + `registry_end_time`? The Details table in
  `?convert_person_id` now lists the combinations. A short vignette with one
  example per procedure family would help.
- What happens when a user has access to PSD but not to the underlying
  conversion tables? Presumably the procedure reports this in `v_resultat`,
  which is now part of the error message. Confirm on DST.
- Should privilege checks also cover the database or schema the data comes
  from or goes to? Relevant for items 1–2.
