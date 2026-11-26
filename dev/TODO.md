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

## Before merging: run on DST

The latest changes were tested offline only, against the fake database in
`tests/testthat/helper-fake-psd.R`. `DSTdb` and `ROracle` were not available.
On DST with access to `DB_PSD`:

1. Run `devtools::test(filter = "convert_person_id")`.
2. Source `dev/dst-verification.R` (set `other_user`, `proxy_database` and
   `proxy_schema` at the top first). It runs the checks below and the
   "verify" items further down with dummy ids, cleans up, and prints a
   summary. Paste it here and act on it.

Checklist:

- [ ] **Run table** `PSDMYTEMP_<yymmddHHMMSS>_<pid>`: the PL/SQL snapshot
  changed in the `insert into` line only. Check that the procedure runs and
  the run id is read back. Check that `user_objects` can be queried for the
  cleanup of run tables older than a day.
- [ ] **Registry time as text:** `BEF_HISTORISK_*` without `registry_time`.
  The message should show the same time as `min(time_stamp)` in
  `D101200.bef_leverance_time`, and the output should match a run with that
  time given explicitly.
- [ ] **`in_data = "ORACLE"` in DB_PSD** (`CREATE TABLE BEF_ID_PROC AS SELECT
  DISTINCT ...`): covered by the new DB test with a table in your own schema.
  Also try a table in another schema you can read.
- [ ] **`out_data = "ORACLE"` in DB_PSD** (`ALTER TABLE ... RENAME TO`):
  covered by the new DB test. Check that the kept table is in your schema.
- [ ] **Other databases:** one manual run with
  `in_database`/`out_database = "STATPROD"` and a project `proxy`, as in
  the `BEF_IDSKIFT` example in `?convert_person_id`. Check that
  `DSTdb::get_conn(db, namespace = "bef_personnummer", proxy = "[D...]")`
  gives a connection as the proxy user and does not reuse a cached
  non-proxy connection. Check also that `dbWriteTable(append = TRUE)` and
  `dbFetch(n =)` work in chunks with ROracle.

## Done

- [x] **Character arguments:** `arg_as_string()` replaces the
  `deparse(substitute())` copies. Quoted and bare words work as before;
  variables and expressions now work too.
- [x] **`toupper()` for name checks:** procedure names, column names and
  `in_data`/`out_data` are upper-cased. The owner check uses the Oracle
  `USER`, not the Windows `USERNAME`.
- [x] **`column_name` as input:** the column is renamed to `PNR`/`PERSON_ID`
  in R before upload, or aliased in the `SELECT` for Oracle input. The
  Oracle procedures still take no column name.
- [x] **Milliseconds:** kept when given (`"235959.999"` → `23:59:59.999`).
  Before, they were dropped silently. Values without milliseconds produce
  exactly the same PL/SQL as before.
- [x] **No PSD access:** connection failure now gives a clear error.
  Privileges granted through roles are counted (`session_privs`,
  `all_tab_privs`).
- [x] **Robustness:** all input is validated before connecting. Work tables
  are dropped on every exit. Fixed the leaked second connection and run ids in
  scientific notation (`HIS_ID3e+06`). Values in the PL/SQL are quoted.
- [x] **1. `out_data = "ORACLE"`:** both options, chosen by `out_database`.
  `DB_PSD` → the output table is renamed and kept (option A). Other
  databases → copied in chunks with `dbFetch()`/`dbWriteTable(append =)`
  (option B), and a partly written table is dropped on error.
  `out_table_name` is validated as an Oracle name. The target must not exist,
  and CREATE TABLE is checked on it (`session_privs`), all before upload.
- [x] **2. `in_data = "ORACLE"`:** `in_table_name = "SCHEMA.TABLE"` (or
  `"TABLE"` for your own schema), new `in_database`, `out_database` and
  `proxy`. `database` is deprecated with a message and is the default for
  both. In `DB_PSD`: `CREATE TABLE BEF_ID_PROC AS SELECT DISTINCT`. Other
  databases: `SELECT DISTINCT` into R, then upload. Plain SQL is used rather
  than `dbplyr::in_schema()`, so `dbplyr` is not needed. Existence, read access
  and the id column are checked in `all_tab_columns` first.
- [x] **4. Numeric PNR warning** (R input, and `NUMBER` columns in Oracle
  input). Not converted automatically, because that would change the type
  uploaded to `BEF_ID_PROC`.
- [x] **5a. Unique run table** `PSDMYTEMP_<yymmddHHMMSS>_<pid>` (≤ 30
  characters). The legacy `PSDMYTEMP` is no longer touched. Run tables older
  than one day are dropped as leftovers.
- [x] **Registry-time lookup** fetched as text (`TO_CHAR(... 'FF6')`),
  trailing zeros trimmed, so the common case gives the same PL/SQL string as
  before.
- [x] **`add_person_id(drop_pnr = TRUE)`**: announced in NEWS as breaking.
- [x] **Vignette** `vignettes/convert-person-id.Rmd`: one example per
  procedure family, and when to use validity vs. registry time.
- [x] **Privilege checks on source/target** (open question for items 1–2):
  read access to the source via `all_tab_columns`, CREATE TABLE on the target.

## Next steps (need DST or the PSD team)

### 3. Upload only the distinct id column (needs a DB check)
R input: the whole data frame is still uploaded to `DB_PSD`, as before.
Oracle input already uses only the distinct ids.
**Verify on DST** whether the procedure output contains columns from the input
other than the id:
- If it does not: upload `dplyr::distinct(input, <id>)` only. That is faster
  and sends less data. `add_person_id()` already does this.
- If it does: keep the current behaviour and document that Oracle input
  gives only the id columns.

### 4b. Id column type
- After upload, `user_tab_columns` for `BEF_ID_PROC` could check the Oracle
  type. Ask the PSD team which types the procedures expect. Then decide
  whether to zero-pad numeric PNRs automatically.

### 5b. Concurrent runs
`BEF_ID_PROC` is still a fixed name, so two simultaneous runs by the same user
clobber each other. The run table is unique now.
- A unique input table (`BEF_ID_PROC_<random>`) needs verification that the
  procedures accept any `p_ind_tabelnavn`. `bef_idskift_eksempel.R` suggests
  they do. Also verify whether `p_ind_tabelnavn` accepts a schema-qualified
  name; if it does, Oracle input in `DB_PSD` needs no copy at all.
- Better still for the run table: drop it and read `v_resultat`/`v_koerselsid`
  as OUT binds via `ROracle::oracleProc()`. Needs a test on DST.

### 6. Smaller items
- **`DROP TABLE ... PURGE`** for work tables, so CPR data does not stay in
  the recycle bin. Check with the PSD team first. Also applies to a target
  table dropped after a failed copy.
- **`p_bruger` / `recipient`:** **verify** in which schema the output table is
  created when `recipient` is not the user. `bef_idskift_eksempel.R` reads it
  from the `p_bruger` schema. If so, look for the table there and use a
  qualified name. This also affects `out_data = "ORACLE"` in `DB_PSD` (the
  rename assumes your own schema).
- **`BEF_IDSKIFT` output:** inspect the columns on DST. The legacy script
  keeps only `GL_PERSON_ID`, `NY_PERSON_ID`. Leave `select *` unless internal
  columns turn up.
- **Testing on ids with shifts:** add a DB test with known shifted
  `PERSON_ID`s (ask K22 for a test set).

## Open questions (need input from users / the PSD team)

- Which date and time formats do people actually type? The parser accepts
  `ymd`, `dmy` and `mdy`, with or without `HMS`/`HM`. A string like
  `"02012021"` is read as `dmy` (2 January).
- Does anyone match on milliseconds? They are now kept, but nobody has
  confirmed this matters.
- Is the vignette's explanation of validity vs. registry time right, and
  does it match how K22 explains it? Have someone from K22 read it.
- What happens when a user has access to PSD but not to the underlying
  conversion tables? Presumably the procedure reports this in `v_resultat`,
  which is now part of the error message. Confirm on DST.
- Should `out_data = "ORACLE"` in `DB_PSD` be allowed for procedures that
  return PNRs? The table with CPR numbers then stays in the user's schema
  until they drop it.
