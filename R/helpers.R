# Function to check if a table exists
table_exists <- function(conn, table_name, schema_name) {
  query <- paste0(
    "SELECT COUNT(*) AS COUNT FROM all_tables WHERE table_name = '",
    table_name,
    "' AND owner = '",
    schema_name,
    "'"
  )
  result <- DBI::dbGetQuery(conn, query)

  return(result$COUNT > 0) # Returns TRUE if the table exists, otherwise FALSE
}

# Function to parse and extract date and time from dates and times
extract_date_time <- function(datetime) {
  # Try different formats
  parsed_datetime <- lubridate::parse_date_time(
    datetime,
    orders = c(
      "ymd HMS",
      "dmy HMS",
      "mdy HMS",
      "ymd HM",
      "dmy HM",
      "mdy HM",
      "ymd",
      "dmy",
      "mdy"
    )
  )

  # Extract date and time
  date_part <- lubridate::as_date(parsed_datetime)
  time_part <- format(parsed_datetime, "%H:%M:%S")

  return(list(date = date_part, time = time_part))
}
