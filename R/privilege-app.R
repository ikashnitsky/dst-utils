# Shiny UI and server for dst_db_privilege_management()

privilege_app <- function(dry_run, database, schema, log_file) {
  shiny::shinyApp(
    ui = privilege_app_ui(dry_run, database, schema, log_file),
    server = privilege_app_server(dry_run, log_file)
  )
}

privilege_app_ui <- function(dry_run, database, schema, log_file) {
  mode_banner <- if (dry_run) {
    shiny::div(
      class = "alert alert-warning mb-0",
      shiny::strong("DRY-RUN MODE. "),
      "No database is contacted: the schema, its tables and privileges are ",
      "simulated, and actions are written to a temporary sandbox log that ",
      "disappears when R closes. Grantees starting with ZZ simulate a user ",
      "that does not exist."
    )
  }

  sidebar <- bslib::sidebar(
    width = 300,
    shiny::h6("Connection"),
    shiny::textInput("database", "Database", value = database),
    shiny::textInput(
      "schema",
      "Project schema (proxy)",
      value = schema,
      placeholder = "e.g. D221911"
    ),
    shiny::actionButton(
      "connect",
      if (dry_run) "Connect (simulated)" else "Connect",
      class = "btn-primary",
      icon = shiny::icon("plug")
    ),
    shiny::uiOutput("connection_status"),
    shiny::hr(),
    shiny::h6("Audit log"),
    shiny::p(
      class = "small mb-1",
      "Actions are logged as ",
      shiny::strong(shiny::textOutput("performed_by", inline = TRUE)),
      " to:"
    ),
    shiny::tags$code(class = "small text-break", log_file)
  )

  grant_panel <- bslib::nav_panel(
    "Grant / revoke",
    bslib::layout_columns(
      col_widths = c(5, 7),
      bslib::card(
        bslib::card_header("What to do"),
        shiny::radioButtons(
          "action",
          NULL,
          choices = c("Grant" = "GRANT", "Revoke" = "REVOKE"),
          inline = TRUE
        ),
        shiny::selectInput(
          "privilege",
          "Privilege",
          width = "100%",
          choices = privilege_choices,
          selected = "READ"
        ),
        shiny::helpText(
          "READ is enough for analysis and, unlike SELECT, does not let the ",
          "grantee lock rows."
        ),
        shiny::selectizeInput(
          "tables",
          "Tables",
          width = "100%",
          choices = NULL,
          multiple = TRUE,
          options = list(placeholder = "Connect first, then pick tables")
        ),
        shiny::textAreaInput(
          "grantees",
          "Grantees",
          width = "100%",
          rows = 3,
          placeholder = "User IDs separated by commas, spaces or new lines, e.g. IKX, X00"
        ),
        shiny::textInput(
          "note",
          "Reason / reference (required)",
          width = "100%",
          placeholder = "e.g. request from ABC by e-mail 2026-11-20"
        ),
        shiny::actionButton(
          "review",
          "Review statements…",
          class = "btn-primary",
          icon = shiny::icon("list-check")
        )
      ),
      bslib::card(
        bslib::card_header("Result of the last batch"),
        shiny::uiOutput("result_summary"),
        DT::DTOutput("result_table")
      )
    )
  )

  access_panel <- bslib::nav_panel(
    "Current access",
    bslib::card(
      bslib::card_header(
        class = "d-flex justify-content-between align-items-center",
        "Privileges on the connected schema, as reported by the database",
        shiny::actionButton(
          "refresh_access",
          "Refresh",
          class = "btn-sm btn-outline-secondary",
          icon = shiny::icon("rotate-right")
        )
      ),
      shiny::p(
        class = "small text-muted",
        "'NOT IN LOG' means the privilege exists but was not granted through ",
        "this app (or the log is kept elsewhere). The note shown is from the ",
        "latest logged grant."
      ),
      DT::DTOutput("access_table")
    ),
    shiny::uiOutput("missing_card")
  )

  log_panel <- bslib::nav_panel(
    "Log",
    bslib::card(
      bslib::card_header(
        class = "d-flex justify-content-between align-items-center",
        "All logged actions (newest first). Use the boxes under the headers to filter.",
        shiny::downloadButton(
          "download_log",
          "Download CSV",
          class = "btn-sm btn-outline-secondary"
        )
      ),
      DT::DTOutput("log_table")
    )
  )

  bslib::page_sidebar(
    title = "DST DB privilege management",
    window_title = "DB privileges",
    theme = bslib::bs_theme(version = 5, preset = "bootstrap"),
    sidebar = sidebar,
    mode_banner,
    bslib::navset_card_underline(grant_panel, access_panel, log_panel)
  )
}

privilege_app_server <- function(dry_run, log_file) {
  function(input, output, session) {
    rv <- shiny::reactiveValues(
      backend = NULL,
      tables = character(),
      grants = NULL,
      plan = NULL,
      plan_note = NULL,
      result = NULL,
      log_version = 0
    )
    performed_by <- current_user(session)
    output$performed_by <- shiny::renderText(performed_by)

    # Re-read whenever the file changes, including writes by colleagues
    # sharing the same log directory.
    log_changed <- shiny::reactivePoll(
      2000,
      session,
      checkFunc = function() unlist(file.info(log_file)[c("mtime", "size")]),
      valueFunc = function() Sys.time()
    )
    log_data <- shiny::reactive({
      log_changed()
      rv$log_version
      read_privilege_log(log_file)
    })

    refresh_db_state <- function() {
      b <- rv$backend
      rv$grants <- tryCatch(b$list_grants(), error = function(e) {
        shiny::showNotification(
          paste("Could not read privileges:", conditionMessage(e)),
          type = "error",
          duration = NULL
        )
        NULL
      })
    }

    # -- Connection ----------------------------------------------------------
    shiny::observeEvent(input$connect, {
      database <- toupper(trimws(input$database))
      schema <- toupper(gsub("[][[:space:]]", "", input$schema))
      if (!is_oracle_identifier(database) || !is_oracle_identifier(schema)) {
        shiny::showNotification(
          "Enter a valid database and schema name.",
          type = "error"
        )
        return()
      }
      if (!is.null(rv$backend)) {
        rv$backend$disconnect()
        rv$backend <- NULL
      }
      backend <- tryCatch(
        shiny::withProgress(message = "Connecting…", {
          if (dry_run) {
            new_dry_run_backend(database, schema)
          } else {
            new_oracle_backend(database, schema)
          }
        }),
        error = function(e) {
          shiny::showNotification(
            paste("Connection failed:", conditionMessage(e)),
            type = "error",
            duration = NULL
          )
          NULL
        }
      )
      shiny::req(backend)
      rv$backend <- backend
      rv$tables <- tryCatch(backend$list_tables(), error = function(e) character())
      shiny::updateTextInput(session, "schema", value = schema)
      shiny::updateSelectizeInput(
        session,
        "tables",
        choices = rv$tables,
        selected = character(),
        options = list(placeholder = "Pick one or more tables")
      )
      refresh_db_state()
    })

    output$connection_status <- shiny::renderUI({
      b <- rv$backend
      if (is.null(b)) {
        return(shiny::span(class = "badge text-bg-secondary", "Not connected"))
      }
      shiny::div(
        shiny::span(
          class = if (b$mode == "dry_run") "badge text-bg-warning" else "badge text-bg-success",
          if (b$mode == "dry_run") "Simulated" else "Connected"
        ),
        shiny::span(class = "small ms-1", paste0(b$database, " / ", b$schema)),
        shiny::div(class = "small text-muted", length(rv$tables), " tables/views")
      )
    })

    # -- Review & execute ------------------------------------------------------
    shiny::observeEvent(input$review, {
      if (is.null(rv$backend)) {
        shiny::showNotification("Connect to a schema first.", type = "warning")
        return()
      }
      res <- build_privilege_plan(
        action = input$action,
        privilege = input$privilege,
        tables = input$tables,
        grantees = input$grantees,
        schema = rv$backend$schema,
        note = input$note,
        current_grants = rv$grants
      )
      if (length(res$problems) > 0) {
        shiny::showModal(shiny::modalDialog(
          title = "Please fix the following",
          shiny::tags$ul(purrr::map(res$problems, shiny::tags$li)),
          easyClose = TRUE
        ))
        return()
      }
      rv$plan <- res$plan
      rv$plan_note <- trimws(input$note)
      shiny::showModal(review_modal(res$plan, input$action, rv$backend))
    })

    output$plan_table <- DT::renderDT({
      plan <- shiny::req(rv$plan)
      shown <- data.frame(
        statement = plan$sql,
        `already granted?` = ifelse(
          is.na(plan$currently_granted),
          "unknown",
          ifelse(plan$currently_granted, "yes", "no")
        ),
        check.names = FALSE
      )
      DT::datatable(
        shown,
        rownames = FALSE,
        class = "compact stripe nowrap",
        options = list(dom = "tp", pageLength = 10)
      )
    })

    shiny::observeEvent(input$confirm, {
      plan <- shiny::req(rv$plan)
      shiny::removeModal()
      rv$plan <- NULL
      rv$result <- shiny::withProgress(
        message = "Executing statements…",
        execute_privilege_plan(
          backend = rv$backend,
          plan = plan,
          note = rv$plan_note,
          performed_by = performed_by,
          log_file = log_file
        )
      )
      rv$log_version <- rv$log_version + 1
      refresh_db_state()
      if (any(grepl("NOT LOGGED", rv$result$status))) {
        shiny::showModal(shiny::modalDialog(
          title = "Log write failed - batch stopped",
          "The last statement was executed but could not be written to the ",
          "log, so the remaining statements were not run. Record it manually:",
          shiny::tags$pre(utils::tail(rv$result$sql[rv$result$status != "NOT RUN"], 1)),
          shiny::tags$pre(utils::tail(rv$result$error[rv$result$status != "NOT RUN"], 1))
        ))
      } else if (all(rv$result$status == "OK")) {
        shiny::updateTextAreaInput(session, "grantees", value = "")
      }
    })

    output$result_summary <- shiny::renderUI({
      res <- rv$result
      if (is.null(res)) {
        return(shiny::p(class = "text-muted", "Nothing executed yet in this session."))
      }
      n_ok <- sum(res$status == "OK")
      n_bad <- nrow(res) - n_ok
      shiny::div(
        class = if (n_bad == 0) "alert alert-success" else "alert alert-danger",
        if (identical(rv$backend$mode, "dry_run")) "[simulated] ",
        paste0(
          n_ok, " of ", nrow(res), " statements succeeded",
          if (n_bad > 0) paste0("; ", n_bad, " did not (see the error column)"),
          ". All attempts are in the log."
        )
      )
    })

    output$result_table <- DT::renderDT({
      res <- shiny::req(rv$result)
      DT::datatable(
        res[c("status", "sql", "error")],
        rownames = FALSE,
        class = "compact stripe",
        options = list(dom = "tp", pageLength = 10)
      ) |>
        DT::formatStyle(
          "status",
          color = DT::styleEqual("OK", "#146c43", default = "#b02a37"),
          fontWeight = "bold"
        )
    })

    # -- Current access --------------------------------------------------------
    shiny::observeEvent(input$refresh_access, {
      shiny::req(rv$backend)
      refresh_db_state()
    })

    reconciled <- shiny::reactive({
      b <- shiny::req(rv$backend)
      reconcile_grants(
        shiny::req(rv$grants),
        log_data(),
        database = b$database,
        schema = b$schema
      )
    })

    output$access_table <- DT::renderDT({
      shiny::validate(shiny::need(rv$backend, "Connect to a schema to see who has access."))
      DT::datatable(
        reconciled()$live,
        rownames = FALSE,
        class = "compact stripe nowrap",
        filter = "top",
        options = list(pageLength = 25, scrollX = TRUE, dom = "tip")
      ) |>
        DT::formatStyle(
          "logged",
          color = DT::styleEqual("NOT IN LOG", "#b02a37"),
          fontWeight = DT::styleEqual("NOT IN LOG", "bold")
        )
    })

    output$missing_card <- shiny::renderUI({
      shiny::req(rv$backend)
      missing <- reconciled()$missing
      if (nrow(missing) == 0) {
        return(NULL)
      }
      bslib::card(
        bslib::card_header(
          class = "text-bg-warning",
          "Logged as granted, but not present in the database (revoked outside the app?)"
        ),
        DT::renderDT(DT::datatable(
          missing,
          rownames = FALSE,
          class = "compact stripe nowrap",
          options = list(dom = "tp", scrollX = TRUE)
        ))
      )
    })

    # -- Log -------------------------------------------------------------------
    output$log_table <- DT::renderDT({
      DT::datatable(
        log_data(),
        rownames = FALSE,
        class = "compact stripe nowrap",
        filter = "top",
        options = list(pageLength = 25, scrollX = TRUE, dom = "tip")
      )
    })

    output$download_log <- shiny::downloadHandler(
      filename = function() paste0("privilege_log_", Sys.Date(), ".csv"),
      content = function(file) {
        utils::write.csv(log_data(), file, row.names = FALSE, fileEncoding = "UTF-8")
      }
    )

    session$onSessionEnded(function() {
      b <- shiny::isolate(rv$backend)
      if (!is.null(b)) b$disconnect()
    })
  }
}

review_modal <- function(plan, action, backend) {
  n <- nrow(plan)
  verb <- if (action == "GRANT") "Grant" else "Revoke"
  shiny::modalDialog(
    title = paste0(verb, ": ", n, " statement", if (n > 1) "s", " on ", backend$database, " / ", backend$schema),
    size = "l",
    if (backend$mode == "dry_run") {
      shiny::div(class = "alert alert-warning", "Dry run: execution is simulated.")
    },
    shiny::p(
      "These statements will be executed one by one; each attempt is logged ",
      "immediately, including failures."
    ),
    DT::DTOutput("plan_table"),
    footer = shiny::tagList(
      shiny::modalButton("Cancel"),
      shiny::actionButton(
        "confirm",
        paste0("Execute ", n, " statement", if (n > 1) "s"),
        class = if (action == "GRANT") "btn-primary" else "btn-danger"
      )
    )
  )
}
