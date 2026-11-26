# Jumpstart: verifying and finishing `convert_person_id()` on DST

You are picking up work on the R package **DSTutils** (Statistics Denmark).
The previous work was done **off DST**, without database access. `DSTdb`
and `ROracle` were replaced by empty stubs. Everything that talks to Oracle
was tested only against an in-memory fake. You are on the DST server, with
the real packages and access to `DB_PSD`. Your job is to:

1. verify the untested changes against the real database,
2. collect the facts the open TODO items depend on, and
3. implement the follow-ups those facts allow.

Read this file fully before running anything.

## 1. Safety rules (production environment)

These matter more than finishing the task. If in doubt, stop and ask the
user.

- **No real CPR numbers in anything you write.** Use the dummy ids already
  in the scripts (`"1234"`, `"2345"`, `"0101011234"`, ...). Don't paste
  query output that may contain real PNRs or PERSON_IDs into files, commits,
  PR text, issues or chat. Report counts, column names and types, never
  values.
- **Only drop tables you created**: `DSTUTILS_T_*` from the verification
  script, the work tables `BEF_ID_PROC` and `PSDMYTEMP_<time>_<pid>`, and the
  procedure output tables of your own test runs. Never drop or alter the
  legacy table `PSDMYTEMP`. A SAS job may use it.
- **Never run `PURGE RECYCLEBIN`** or touch other users' or project schemas.
  The only exception is the proxy checks, after the user has named a schema
  you may write test tables to.
- **Don't grant or revoke privileges**, and don't use the privilege app
  (`dst_db_privilege_management()`).
- **Anything that changes what the BEF procedures receive** (parameter names,
  values, input table name, package names, the PL/SQL block) needs a passing
  run against the real `DB_PSD` before it is committed. See the ground rule
  at the top of `dev/TODO.md`.
- Decisions marked **ask the user** below are for the user or the PSD team
  (K22), not for you.

## 2. Orientation: read these first

| File | What it is |
|---|---|
| `dev/TODO.md` | The plan: ground rule, the "Before merging: run on DST" checklist, done items, open items. **Main reference.** |
| `R/convert_person_id.R` | The function, its validation helpers, the PL/SQL builder and thin DB wrappers (`db_query`, `db_execute`, `db_write_table`, `db_read_chunked`, `db_connect`, `psd_connect`, `psd_run_plsql`). |
| `tests/testthat/test-convert_person_id.R` | Offline tests (top), fake-DB orchestration tests (middle), real-DB tests guarded by `skip_if_no_db()` (bottom). |
| `tests/testthat/helper-fake-psd.R` | `local_fake_psd()`: mocks the wrappers above. Extend it when you change DB calls. |
| `tests/testthat/_snaps/convert_person_id.md` | Snapshot of the generated PL/SQL. A diff here means the procedure input changed. |
| `dev/dst-verification.R` | Script that answers the open "verify on DST" questions. **Written blind; it may need fixes.** |
| `vignettes/convert-person-id.Rmd`, `NEWS.md` | User docs and changelog. Keep them in sync with any change. |
| `dev/old-code/bef_idskift_eksempel.R` | Legacy script; source of the proxy and `p_bruger` assumptions. |

How the code works, in short:
1. All input is validated before connecting.
2. The id column is uploaded to `BEF_ID_PROC` in the user's `DB_PSD` schema.
   For Oracle input, a `CREATE TABLE ... AS SELECT DISTINCT` is used instead.
3. A run table `PSDMYTEMP_<yymmddHHMMSS>_<pid>` is created.
4. An anonymous PL/SQL block calls the procedure and inserts its OUT values
   (`v_resultat`, `v_koerselsid`) into the run table.
5. The output table `<prefix><run id>` is read back, renamed (`out_data =
   "ORACLE"` in `DB_PSD`) or copied in chunks to another database.
6. Every table the call created is tracked in `created_tables` and dropped in
   `on.exit()`.

Conventions:
- New messages are in English. Keep the existing Danish messages as they are,
  because users and tests match on them.
- Every DB call goes through a wrapper, so it can be mocked.
- Every Oracle name built into SQL is validated with `check_identifier()` or
  quoted with `sql_string()`.

## 3. Step 1: set up and run the tests

```r
# In the package source directory, on a branch, never on master:
#   git checkout -b dst-verification
devtools::load_all()
devtools::test(filter = "convert_person_id")
```

- `skip_if_no_db()` must **not** skip now. If the real-DB tests skip, fix the
  connection first (`DSTdb::get_conn("DB_PSD")`).
- Expected: everything passes, including the new real-DB test "Oracle input
  and output within DB_PSD work".
- If something fails, find out whether the code or the test is wrong. Use
  the real DB as the reference, not the fake. Then fix the fake
  (`helper-fake-psd.R`) as well, so the offline tests model reality.

Most likely failure points, all written without a DB:

| Code | Assumption to check |
|---|---|
| `build_bef_plsql()` | The run table is now `PSDMYTEMP_<time>_<pid>` (snapshot changed in the `insert into` line only). |
| `lookup_registry_time()` | `TO_CHAR(min(CAST(time_stamp AS TIMESTAMP)), 'YYYY-MM-DD HH24:MI:SS.FF6')` works on `D101200.bef_leverance_time`. |
| `drop_leftover_tables()` | The `user_objects ... LIKE 'PSDMYTEMP\_%' ESCAPE '\'` query works. |
| `copy_source_to_psd()` | `create table BEF_ID_PROC as select distinct ...` is allowed. |
| `convert_person_id()`, `out_data = "ORACLE"` in `DB_PSD` | `alter table <out> rename to <name>` works on the procedure's output table. |
| `db_execute()` | `dbSendQuery()` + `dbClearResult()` works for DDL on ROracle (it did before). |
| `db_read_chunked()`, `db_write_table(append =)` | `dbFetch(n =)`, `dbHasCompleted()` and `dbWriteTable(append = TRUE)` behave on ROracle. |
| `db_connect()` | `DSTdb::get_conn(db, namespace = "bef_personnummer", proxy = "[SCHEMA]")` is a valid call. |

## 4. Step 2: run the verification script

1. Read `dev/dst-verification.R` first. Fix obvious bugs before running it;
   it has never been executed.
2. Ask the user for the settings at the top:
   - `other_user`: another ident to pass as `p_bruger`, or leave `NULL`;
   - `proxy_database` and `proxy_schema`: a database and project schema where
     test tables `DSTUTILS_T_*` may be created and dropped, or leave `NULL`.
3. Run it with `source("dev/dst-verification.R")`. The script ends with a
   Markdown summary.
4. Paste the summary into `dev/TODO.md` under a new heading
   `## DST verification results (<date>)`, after checking it contains no
   real ids.

Also find out the Oracle version (`select version from
product_component_version`, or ask the user). `check_identifier()` allows
names up to 128 characters, which needs Oracle 12.2 or later. On older
versions, change the limit to 30 (`{0,29}`) and update the tests.

## 5. Step 3: act on the results

Do one item at a time. For each:
1. make the change and update the fake and the tests;
2. run the offline tests and the real-DB tests;
3. update `dev/TODO.md` (move the item to Done) and `NEWS.md`;
4. commit.

Accept a snapshot change (`testthat::snapshot_accept("convert_person_id")`)
only after the real-DB tests pass with it.

| Check in the summary | If the result is... | Then |
|---|---|---|
| **3** output columns with `EXTRA_COL` | not passed through | For R input, upload only `dplyr::distinct(input[id_column])` in `convert_person_id()`. Add a fake test that only the id column is uploaded, and a NEWS entry (faster, sends less data). |
| | passed through | Keep the current upload. Say in `?convert_person_id` and the vignette that extra columns are passed through for R input but not for Oracle input (which uses distinct ids only). |
| **5b** input table not called `BEF_ID_PROC` | accepted | Give the input table a unique name, like `run_table_name()`. `BEF_ID_PROC_` + 12 + `_` + 5 is exactly 30 characters, so check the length. Pass it as `p_ind_tabelnavn` (snapshot change). Clean up leftovers like the run tables (older than one day). Keep dropping a legacy `BEF_ID_PROC`. Remove "do not run two conversions at the same time" from the docs and vignette. |
| | rejected | Leave as is. Record in TODO that the name is fixed. |
| **5b** schema-qualified `p_ind_tabelnavn` | accepted for your own schema | Before using it, also test a table in **another** schema the user can read. The procedure probably runs with its owner's rights, so the BEF package owner may need SELECT on that table. Only if that works: for `in_data = "ORACLE"` in `DB_PSD`, pass the qualified name directly instead of copying. **Ask the user** first; it changes the procedure input. |
| **p_bruger** owner of the output table | always your own schema | Nothing to change. Record it in TODO. |
| | the recipient's schema | Look the output table up in that schema (`table_exists(psd, out_name, recipient)`) and read it schema-qualified. For `out_data = "ORACLE"` in `DB_PSD`, the rename cannot cross schemas, so either error when `recipient != USER`, or use `CREATE TABLE <name> AS SELECT * FROM <schema>.<out>` and drop the original. **Ask the user** which. |
| **BEF_IDSKIFT** output columns | only `GL_PERSON_ID`, `NY_PERSON_ID` (plus obvious data) | Leave `select *`. Record the columns in `?convert_person_id`. |
| | internal or technical columns | **Ask the user** whether to select only the data columns for `BEF_IDSKIFT`. |
| **4b** column types | any result | Record the types in TODO. If the procedures rely on `VARCHAR2` PNRs, keep the numeric-PNR warning. Automatic zero-padding is a design decision: **ask the user**. A NUMBER `PERSON_ID` being accepted means no change is needed for PERSON_ID. |
| **Registry time** old vs. new | identical | Nothing to do. Tick the checklist item. |
| | different | The text value from Oracle is authoritative: the old `POSIXct` value went through a time-zone conversion. Confirm by comparing with `TO_CHAR(min(time_stamp), ...)` run by hand. Write in NEWS that historic runs without `registry_time` may now use a slightly different (correct) time, and say by how much. |
| **user_objects** query | error | Replace it, e.g. with `user_tables` (no creation date). In that case, don't drop old run tables automatically; only warn about them. |
| **Recycle bin** keeps dropped tables | yes | Dropped work tables with CPR stay recoverable. Using `DROP ... PURGE` is for the PSD team to decide: **ask the user** and don't implement it yourself. Record in TODO whether PURGE is allowed. |
| **OUT binds** via `oracleProc()` | works | Optional improvement, **ask the user** first: read `v_resultat`/`v_koerselsid` as OUT binds and drop the run table (and its cleanup) completely. Snapshot change, so run the real-DB tests. |
| | error | The bind syntax in the script was a guess. Try ROracle's documented form once (`?ROracle::oracleProc`). If that fails too, keep the run table and record it in TODO. |
| **Proxy**: plain connection after a proxy one | different users | Nothing to do. |
| | both are the proxy user | `DSTdb` caches by namespace. In `db_connect()`, use a namespace per proxy, e.g. `paste0("bef_personnummer_", proxy)`. Re-run the check. |
| **Chunked copy** / end-to-end proxy | error | Fix `db_read_chunked()`/`db_write_table()` for ROracle. A likely issue is case or quoting of table names in `dbWriteTable()`. Re-run. |

Also open in `dev/TODO.md`, but not yours to decide: the test set with known
PERSON_ID shifts (ask K22 via the user) and the open questions at the end of
TODO. If the verification answers any of them, write the answer there.

## 6. Definition of done

- `devtools::test()` passes on DST with no `DB_PSD` skips.
- `devtools::check()` gives 0 errors, 0 warnings and 0 notes, or every note
  is explained.
- Every checklist item in "Before merging: run on DST" in `dev/TODO.md` is
  ticked, or annotated with why not.
- The verification summary (without real ids) is in `dev/TODO.md`.
- `NEWS.md`, `?convert_person_id` (`devtools::document()`) and the vignette
  match the code.
- One commit per item on the branch. Don't push or open a PR until the user
  says so.
- A short report to the user covering:
  - what passed;
  - what you changed;
  - which decisions are waiting for them or the PSD team.
