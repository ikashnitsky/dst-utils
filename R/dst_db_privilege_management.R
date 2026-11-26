#' Interactive DB Privilege management
#'
#' An interactive shiny app to manage database privileges at DST.
#'
#' @return Opens a shiny app session.
#'
#' @export
dst_db_privilege_management <- function() {
  app_dir <- system.file('shiny', package = 'DSTutils')
  if (app_dir == '') {
    stop(
      "Could not find example directory. Try re-installing 'DSTutils'.",
      call. = FALSE
    )
  }
  shiny::runApp(app_dir, display.mode = 'normal')
}
