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

  # Extract date and time. Milliseconds are kept when given, e.g.
  # "235959.999" -> "23:59:59.999". They are rounded from the numeric seconds,
  # because format(x, "%OS3") truncates (03.232 would become 03.231).
  date_part <- lubridate::as_date(parsed_datetime)
  time_part <- format(parsed_datetime, "%H:%M:%S")
  millis <- round((lubridate::second(parsed_datetime) %% 1) * 1000)
  has_millis <- !is.na(millis) & millis > 0 & millis < 1000
  time_part[has_millis] <- sprintf(
    "%s.%03d",
    time_part[has_millis],
    as.integer(millis[has_millis])
  )

  return(list(date = date_part, time = time_part))
}
