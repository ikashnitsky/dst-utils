utils::globalVariables("PNR")

#' @title Convert PNR to PERSON_ID
#' @description Takes a table with a `PNR` column and adds the matching
#'   `PERSON_ID` (procedure `BEF_OMKOD`). Only the distinct PNRs are sent to
#'   `DB_PSD`.
#' @param data A data.frame containing a PNR column (any case).
#' @param drop_pnr Drop the `PNR` column from the result, as the SAS macro
#'   does (default). Use `FALSE` to keep it.
#' @return `data` with column names in upper case, joined with `PERSON_ID`,
#'   without `PNR` unless `drop_pnr = FALSE`.
#' @export
add_person_id <- function(data, drop_pnr = TRUE) {
  # Get PNR from table
  data <- data |> dplyr::rename_with(toupper)
  cpr <- data |> dplyr::select(PNR) |> dplyr::distinct()

  # Convert id using convert_person_id
  cpr_id <- convert_person_id(
    project_id = "K22DSL",
    procedure = "bef_omkod",
    in_table_name = cpr
  )

  # Create full output table
  table_id <- data |> dplyr::left_join(cpr_id, by = "PNR")

  # Pseudonymise: the SAS macro drops PNR after conversion ("meget vigtigt")
  if (drop_pnr) {
    table_id <- table_id |> dplyr::select(-PNR)
  }

  return(table_id)
}

# Create a template document for conversion both ways with a check for duplicates, missing
# and removal of the pnr-variable (if pnr to person_id)
# Must have an example of fetching data from SAS, csv, and Oracle
