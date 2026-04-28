#' @title Convert PNR to PERSON_ID
#' @description This function takes a table with a PNR column and adds a PERSON_ID column.
#' @param data A data.frame containing a PNR column.
#' @return The original data.frame joined with PERSON_ID.
#' @export
add_person_id <- function(data) {
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

  return(table_id)
}

# Create a template document for conversion both ways with a check for duplicates, missing
# and removal of the pnr-variable (if pnr to person_id)
# Must have an example of fetching data from SAS, csv, and Oracle
