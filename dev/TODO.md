# Development TODOs

These are the unresolved tasks and questions collected from the original `dev` scripts.

## Extra Features (`EKSTRA`)
- [ ] **Input Data Location:** Implement a variable for whether input data is located in R or Oracle (`in_data`).
  - Add a variable for `in_database`, including a check for read privileges.
  - Requires an indicator for whether data is in `db_psd`, `statprod`, `statudv`, etc. (Note that procedures are in `db_psd`).
  - Verify that the database and data exist (using the `table_exists` function).
- [ ] **Output Data Location:** Implement a variable for whether `out_table` should be returned in R or saved in Oracle (`out_data`).
  - Add a variable for `out_database`, including a check for write privileges.
  - *Question:* In the SAS macro, data is saved upon output to Oracle in `&prefix_name&v_koerselsid` in the ident schema on PSD. Should we do the same here?
- [ ] **Column Names:** Update `column_name` to be provided as an input to the function.
  - *Problem:* Currently, Oracle procedures do not take table name as input.
- [ ] **Data Fetching:** Update code to only fetch unique rows when data passes through the R environment.
- [ ] **Testing:** Test functions on person IDs that have shifts/changes.
- [ ] **Data Locations:** Properly set up and correct for different output and input data and locations (see related inline TODOs).

## Error Handling & Validation (`FEJL OG TJEK`)
- [ ] **Column Validation:** Verify it is the correct column (name, type, length, etc.).
  - Check name (*DONE*).
  - Create a `column_name` variable like in SAS (*DONE*), so it can easily be extracted for checking in Oracle (*Missing*).
  - Check column type (currently character, factor, and integer work in R, but does this apply in Oracle?) and column length (maybe only relevant for Oracle?).
- [ ] **Name Formatting:** Remember to use `toupper()` for all name checks.
- [ ] **Input Updates:** Fully update variables for `database`, `in_data`, `out_data`, and `in_table_name` (must only be fetched from env if `in_data=R`, otherwise character).

## Investigation / Research (`UNDERSØG`)
- [ ] **Datetime Formats:** Investigate what format people typically use when inserting dates and times.
- [ ] **Milliseconds:** Is it a problem that R does not include milliseconds in the datetime format?
  - It is not a problem for fetching, but does anyone use milliseconds for matching?
- [ ] **Parameter Usage:** How do people keep track of when to use `validity_date` + `registry_time` versus `registry_start_time` + `registry_end_time`?
- [ ] **Permissions:** How does the function behave if the user has not been granted access to the conversion tables or to PSD?
- [ ] **Schemas:** Should the permissions check (`CREATE TABLE`) verify the db-schema as well?

## Code Cleanup
- [ ] **Refactoring:** Consider making the handling of character variables (removing quotes) neater, possibly by writing it as a helper function.
- [ ] **Oracle Saving:** When `out_data='ORACLE'`, implement the logic to save data to Oracle and optionally not return anything to R. Currently, the idea is to just save the list of converted IDs to the ident schema in the same database as the original data.

## Omissions from Old Code (`dev/old-code`)
- [ ] **Pseudonymization (Drop Original PNR):** The `add_person_id` function currently retains the original `PNR` column. The legacy SAS macro (`KonverteringAfPersonidSASfraExcel.sas`) strictly emphasizes dropping the original `PNR` identifier upon successful conversion (`drop pnr; /* meget vigtigt */`). This is critical for data privacy and should likely be implemented (perhaps as a default boolean flag `drop_pnr = TRUE`).
- [ ] **Cross-Database Support & Proxy Schemas:** The `bef_idskift_eksempel.R` script demonstrates functionality to fetch data from an alternate database (e.g., `STATPROD`), utilizing project schema proxies in the connection string (e.g., `DSTdb::get_conn('STATPROD', proxy = '[D222401]')`). `convert_person_id` currently lacks the logic to bridge cross-database table fetching and proxy schema connections when `in_data = "ORACLE"`.
- [ ] **Handling `BEF_IDSKIFT` Outputs:** The legacy script explicitly fetches the output table for `IDSKIFT` and selects the `GL_PERSON_ID` and `NY_PERSON_ID` columns. Ensure the `select * from ...` approach in `convert_person_id` cleanly returns the correct columns for `BEF_IDSKIFT` without returning redundant or internal variables.
