#' Skip tests if database is unavailable
#'
#' Evaluates if DSTdb is available and DB_PSD is reachable. If not, skips the test.
skip_if_no_db <- function() {
  has_dstdb <- requireNamespace("DSTdb", quietly = TRUE)
  if (!has_dstdb) {
    testthat::skip("DSTdb package is not available")
  }

  # Try to connect, but fail gracefully if not possible
  conn <- tryCatch(
    {
      DSTdb::get_conn("DB_PSD")
    },
    error = function(e) {
      NULL
    }
  )

  if (is.null(conn)) {
    testthat::skip("DB_PSD connection is unavailable")
  }

  # Make sure to close the connection after the check so we don't leak connections
  DBI::dbDisconnect(conn)
}
