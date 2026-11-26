# ┌─────────────────────────────────────────────────────────────────────────────┐
# │  Oracle DBA Privilege Manager — Shiny App                                   │
# │  Author: wrapping functions by Ilya Kashnitsky                              │
# │  Deps: shiny, DBI, DT, glue, readr, dplyr, tidyr, purrr, DSTdb            │
# └─────────────────────────────────────────────────────────────────────────────┘

library(shiny)
library(DBI)
library(DT)
library(glue)
library(readr)
library(dplyr)
library(tidyr)
library(purrr)

# DSTdb is an internal DST package — load only if not already attached
# (it will already be loaded when running from within RStudio at DST)
if (!requireNamespace("DSTdb", quietly = TRUE)) {
  stop(
    "Package 'DSTdb' is required but not installed.\n",
    "Please run this app from an RStudio session where DSTdb is available."
  )
}
library(DSTdb)

# Source core privilege-management functions
source("functions-privilege-management.R")

LOG_PATH <- "privilege_log.csv"

# Ensure log file exists on startup
init_privilege_log(LOG_PATH)

# ── Helper: check single table access ─────────────────────────────────────────
check_table_access_safe <- function(conn, schema_name, table_name) {
  tryCatch(
    {
      dbGetQuery(
        conn,
        glue("SELECT * FROM {schema_name}.{table_name} WHERE ROWNUM = 1")
      )
      TRUE
    },
    error = function(e) FALSE
  )
}

# ── UI ────────────────────────────────────────────────────────────────────────
ui <- tagList(
  tags$head(
    tags$title("Oracle DBA Manager"),
    tags$link(rel = "preconnect", href = "https://fonts.googleapis.com"),
    tags$link(
      rel = "stylesheet",
      href = "https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap"
    ),
    tags$link(rel = "stylesheet", href = "styles.css")
  ),

  div(
    class = "app-wrapper",

    # ── Sidebar ──────────────────────────────────────────────────────────────
    div(
      class = "sidebar",

      div(
        class = "sidebar-header",
        div(class = "logo-icon", "\U0001f5c4"),
        div(
          tags$h1("DBA Manager", class = "app-title"),
          tags$p("Oracle Privilege Control", class = "app-subtitle")
        )
      ),

      tags$hr(class = "divider"),

      div(
        class = "connection-panel",
        tags$p("DATABASE CONNECTION", class = "section-label"),

        div(
          class = "form-group",
          tags$label("Database", class = "field-label"),
          textInput(
            "db_name",
            NULL,
            value = "STATPROD",
            placeholder = "e.g. STATPROD"
          )
        ),

        div(
          class = "form-group",
          tags$label("Proxy Schema", class = "field-label"),
          textInput(
            "proxy_schema",
            NULL,
            value = "D221911",
            placeholder = "e.g. D221911"
          )
        ),

        actionButton(
          "btn_connect",
          "Connect",
          class = "btn-connect",
          icon = icon("plug")
        ),

        uiOutput("connection_status")
      ),

      tags$hr(class = "divider"),

      div(
        class = "nav-menu",
        tags$p("NAVIGATION", class = "section-label"),

        div(
          id = "nav_grant",
          class = "nav-item active",
          onclick = "switchTab('grant')",
          tags$span("\U0001f511"),
          "Grant Privilege"
        ),

        div(
          id = "nav_log",
          class = "nav-item",
          onclick = "switchTab('log')",
          tags$span("\U0001f4cb"),
          "Privilege Log"
        )

        # div(id = "nav_check", class = "nav-item",
        #     onclick = "switchTab('check')",
        #     tags$span("\U0001f50d"), "Check Access")
      )
    ),

    # ── Main Content ──────────────────────────────────────────────────────────
    div(
      class = "main-content",

      # ── Tab: Grant Privilege ──────────────────────────────────────────────
      div(
        id = "tab_grant",
        class = "tab-content active",

        div(
          class = "page-header",
          tags$h2("Grant Privilege", class = "page-title"),
          tags$p(
            "Grant Oracle read/select privileges to one or more users on schema tables.",
            class = "page-desc"
          )
        ),

        div(
          class = "card-grid-2",

          # Left: inputs
          div(
            class = "card",
            tags$h3("Grant Parameters", class = "card-title"),

            div(
              class = "form-group",
              tags$label("Grantee ID(s)", class = "field-label"),
              tags$small(
                "Comma-separated for batch grants",
                class = "field-hint"
              ),
              textInput(
                "grant_grantee",
                NULL,
                placeholder = "e.g. IKX, X00, X01"
              )
            ),

            div(
              class = "form-row-2",
              div(
                class = "form-group",
                tags$label("Schema", class = "field-label"),
                textInput(
                  "grant_schema",
                  NULL,
                  value = "D221911",
                  placeholder = "D221911"
                )
              ),
              div(
                class = "form-group",
                tags$label("Privilege", class = "field-label"),
                selectInput(
                  "grant_privilege",
                  NULL,
                  choices = c("READ", "SELECT", "INSERT", "UPDATE"),
                  selected = "READ"
                )
              )
            ),

            div(
              class = "form-group",
              tags$label("Table Name(s)", class = "field-label"),
              tags$small(
                "Comma-separated for batch grants",
                class = "field-hint"
              ),
              textInput(
                "grant_table",
                NULL,
                placeholder = "e.g. LIFELINES, LIFELINES_KOEN"
              )
            ),

            div(
              class = "form-group",
              tags$label("Note", class = "field-label"),
              textInput(
                "grant_note",
                NULL,
                placeholder = "e.g. requested by XXX via email"
              )
            ),

            div(
              class = "form-group",
              tags$label("Granted By", class = "field-label"),
              textInput(
                "grant_by",
                NULL,
                value = Sys.getenv("USERNAME"),
                placeholder = "IKX"
              )
            ),

            tags$hr(class = "divider"),

            div(
              class = "action-row",
              div(
                class = "dry-run-toggle",
                checkboxInput(
                  "dry_run",
                  "Dry Run (preview SQL — no DB write)",
                  value = FALSE
                )
              ),
              actionButton(
                "btn_grant",
                "Execute Grant",
                class = "btn-primary",
                icon = icon("check-circle")
              )
            )
          ),

          # Right: output log
          div(
            class = "card",
            tags$h3("Execution Log", class = "card-title"),
            div(class = "log-output", uiOutput("grant_log"))
          )
        )
      ),

      # ── Tab: Privilege Log ────────────────────────────────────────────────
      div(
        id = "tab_log",
        class = "tab-content",

        div(
          class = "page-header",
          tags$h2("Privilege Log", class = "page-title"),
          tags$p(
            "Browse and filter the local audit log of all granted privileges.",
            class = "page-desc"
          )
        ),

        # Stat boxes
        div(
          class = "stat-grid",
          div(
            class = "stat-box",
            div(class = "stat-value", textOutput("stat_total")),
            div(class = "stat-label", "Total Grants")
          ),
          div(
            class = "stat-box",
            div(class = "stat-value", textOutput("stat_grantees")),
            div(class = "stat-label", "Unique Grantees")
          ),
          div(
            class = "stat-box",
            div(class = "stat-value", textOutput("stat_tables")),
            div(class = "stat-label", "Unique Tables")
          ),
          div(
            class = "stat-box",
            div(class = "stat-value", textOutput("stat_schemas")),
            div(class = "stat-label", "Schemas")
          )
        ),

        div(
          class = "card",
          div(
            class = "filter-row",
            div(
              class = "form-group",
              tags$label("Grantee", class = "field-label"),
              uiOutput("filter_grantee_ui")
            ),
            div(
              class = "form-group",
              tags$label("Schema", class = "field-label"),
              uiOutput("filter_schema_ui")
            ),
            div(
              class = "form-group",
              tags$label("Date Range", class = "field-label"),
              dateRangeInput(
                "filter_dates",
                NULL,
                start = Sys.Date() - 365,
                end = Sys.Date()
              )
            ),
            div(
              class = "filter-actions",
              actionButton(
                "btn_refresh_log",
                "Refresh",
                class = "btn-secondary",
                icon = icon("rotate-right")
              ),
              downloadButton(
                "btn_download",
                "Export CSV",
                class = "btn-secondary"
              )
            )
          ),

          DT::dataTableOutput("privilege_table")
        ),

        # Live Oracle comparison panel
        div(
          class = "card",
          div(
            class = "card-header-row",
            tags$h3("Live Oracle Privileges", class = "card-title"),
            actionButton(
              "btn_query_live",
              "Query Live DB",
              class = "btn-secondary",
              icon = icon("database")
            )
          ),
          uiOutput("live_priv_panel")
        )
      ),
    ) # end main-content
  ), # end app-wrapper

  # ── JavaScript: tab switching ─────────────────────────────────────────────
  tags$script(HTML(
    "
    function switchTab(tabName) {
      document.querySelectorAll('.tab-content').forEach(function(el) {
        el.classList.remove('active');
      });
      document.querySelectorAll('.nav-item').forEach(function(el) {
        el.classList.remove('active');
      });
      document.getElementById('tab_' + tabName).classList.add('active');
      document.getElementById('nav_' + tabName).classList.add('active');
    }
  "
  ))
)

# ── Server ────────────────────────────────────────────────────────────────────
server <- function(input, output, session) {
  rv <- reactiveValues(
    conn = NULL,
    conn_status = "disconnected", # disconnected | connecting | connected | error
    conn_label = "",
    grant_messages = list(),
    log_data = NULL,
    live_data = NULL,
    check_results = NULL
  )

  # ── Load log on startup ───────────────────────────────────────────────────
  observe({
    rv$log_data <- tryCatch(
      read_privilege_log(LOG_PATH),
      error = function(e) {
        tibble(
          timestamp = character(),
          grantee = character(),
          table_name = character(),
          schema = character(),
          privilege = character(),
          granted_by = character(),
          note = character()
        )
      }
    )
  })

  # ── Connection ────────────────────────────────────────────────────────────
  observeEvent(input$btn_connect, {
    rv$conn_status <- "connecting"
    rv$conn <- NULL
    rv$conn_label <- ""

    tryCatch(
      {
        proxy_raw <- trimws(input$proxy_schema)
        # Accept both "D221911" and "[D221911]"
        proxy_fmt <- if (startsWith(proxy_raw, "[")) {
          proxy_raw
        } else {
          paste0("[", proxy_raw, "]")
        }

        conn <- get_conn(trimws(input$db_name), proxy = proxy_fmt)

        # Verify with a lightweight Oracle ping
        dbGetQuery(conn, "SELECT 1 FROM DUAL")

        rv$conn <- conn
        rv$conn_status <- "connected"
        rv$conn_label <- paste0(
          trimws(input$db_name),
          " / ",
          trimws(input$proxy_schema)
        )

        showNotification(
          paste("\u2713 Connected to", rv$conn_label),
          type = "message",
          duration = 4
        )
      },
      error = function(e) {
        rv$conn_status <- "error"
        rv$conn <- NULL
        showNotification(
          paste("Connection failed:", conditionMessage(e)),
          type = "error",
          duration = 10
        )
      }
    )
  })

  output$connection_status <- renderUI({
    s <- rv$conn_status
    if (s == "connected") {
      div(
        class = "conn-status connected",
        tags$span(class = "status-dot"),
        rv$conn_label
      )
    } else if (s == "connecting") {
      div(
        class = "conn-status connecting",
        tags$span(class = "status-dot"),
        "Connecting\u2026"
      )
    } else if (s == "error") {
      div(
        class = "conn-status error",
        tags$span(class = "status-dot"),
        "Connection failed"
      )
    } else {
      div(
        class = "conn-status disconnected",
        tags$span(class = "status-dot"),
        "Not connected"
      )
    }
  })

  # ── Grant Tab ─────────────────────────────────────────────────────────────
  observeEvent(input$btn_grant, {
    req(nzchar(trimws(input$grant_grantee)), nzchar(trimws(input$grant_table)))

    grantees <- trimws(strsplit(input$grant_grantee, ",")[[1]])
    grantees <- grantees[nzchar(grantees)]
    tables <- trimws(strsplit(input$grant_table, ",")[[1]])
    tables <- tables[nzchar(tables)]

    if (!input$dry_run && is.null(rv$conn)) {
      rv$grant_messages <- list(
        list(
          type = "error",
          text = "\u274c No active database connection. Please connect first."
        )
      )
      return()
    }

    messages <- list()

    for (tbl in tables) {
      for (grantee in grantees) {
        result <- tryCatch(
          {
            if (input$dry_run) {
              sql_preview <- glue(
                "GRANT {input$grant_privilege} ON {input$grant_schema}.{tbl} TO {grantee}"
              )
              list(type = "dryrun", text = paste("[DRY RUN]", sql_preview))
            } else {
              grant_privilege(
                conn = rv$conn,
                grantee = grantee,
                table_name = tbl,
                privilege = input$grant_privilege,
                schema = input$grant_schema,
                granted_by = input$grant_by,
                note = input$grant_note,
                log_path = LOG_PATH,
                dry_run = FALSE
              )
              list(
                type = "success",
                text = glue(
                  "\u2705 GRANT {input$grant_privilege} ON ",
                  "{input$grant_schema}.{tbl} TO {grantee} \u2014 logged."
                )
              )
            }
          },
          error = function(e) {
            list(
              type = "error",
              text = paste("\u274c Error:", conditionMessage(e))
            )
          }
        )

        messages <- c(messages, list(result))
      }
    }

    rv$grant_messages <- messages

    # Refresh the log data after real grants
    if (!input$dry_run) {
      rv$log_data <- tryCatch(
        read_privilege_log(LOG_PATH),
        error = function(e) rv$log_data
      )
    }
  })

  output$grant_log <- renderUI({
    msgs <- rv$grant_messages

    if (length(msgs) == 0) {
      return(div(
        class = "log-empty",
        "Execution output will appear here after clicking Execute Grant."
      ))
    }

    ts <- format(Sys.time(), "%H:%M:%S")

    do.call(
      div,
      c(
        list(class = "log-messages"),
        lapply(msgs, function(m) {
          div(
            class = paste("log-entry", m$type),
            tags$span(class = "log-time", ts),
            tags$span(class = "log-text font-mono", m$text)
          )
        })
      )
    )
  })

  # ── Log Tab ───────────────────────────────────────────────────────────────
  observeEvent(input$btn_refresh_log, {
    rv$log_data <- tryCatch(
      read_privilege_log(LOG_PATH),
      error = function(e) rv$log_data
    )
  })

  output$filter_grantee_ui <- renderUI({
    df <- req(rv$log_data)
    choices <- sort(unique(df$grantee))
    selectInput(
      "filter_grantee",
      NULL,
      choices = choices,
      selected = NULL,
      multiple = TRUE
    )
  })

  output$filter_schema_ui <- renderUI({
    df <- req(rv$log_data)
    choices <- sort(unique(df$schema))
    selectInput(
      "filter_schema",
      NULL,
      choices = choices,
      selected = NULL,
      multiple = TRUE
    )
  })

  filtered_log <- reactive({
    df <- req(rv$log_data)
    if (nrow(df) == 0) {
      return(df)
    }

    df$date <- as.Date(substr(df$timestamp, 1, 10))

    # Date filter
    if (!is.null(input$filter_dates) && !anyNA(input$filter_dates)) {
      df <- filter(
        df,
        date >= input$filter_dates[1],
        date <= input$filter_dates[2]
      )
    }

    # Grantee filter (NULL / empty = show all)
    if (!is.null(input$filter_grantee) && length(input$filter_grantee) > 0) {
      df <- filter(df, grantee %in% input$filter_grantee)
    }

    # Schema filter
    if (!is.null(input$filter_schema) && length(input$filter_schema) > 0) {
      df <- filter(df, schema %in% input$filter_schema)
    }

    select(df, -date)
  })

  output$stat_total <- renderText({
    nrow(rv$log_data)
  })
  output$stat_grantees <- renderText({
    length(unique(rv$log_data$grantee))
  })
  output$stat_tables <- renderText({
    length(unique(rv$log_data$table_name))
  })
  output$stat_schemas <- renderText({
    length(unique(rv$log_data$schema))
  })

  output$privilege_table <- DT::renderDataTable({
    df <- filtered_log()
    DT::datatable(
      df,
      options = list(
        pageLength = 15,
        scrollX = TRUE,
        dom = "tip",
        columnDefs = list(
          list(className = "dt-left", targets = "_all")
        )
      ),
      rownames = FALSE,
      class = "display compact"
    )
  })

  output$btn_download <- downloadHandler(
    filename = function() paste0("privilege_log_", Sys.Date(), ".csv"),
    content = function(file) write_csv(filtered_log(), file)
  )

  # Live Oracle privileges
  observeEvent(input$btn_query_live, {
    if (is.null(rv$conn)) {
      showNotification(
        "No active connection. Please connect first.",
        type = "warning"
      )
      return()
    }

    tryCatch(
      {
        rv$live_data <- query_live_privileges(
          rv$conn,
          schema = trimws(input$proxy_schema)
        )
      },
      error = function(e) {
        showNotification(
          paste("Error querying live privileges:", conditionMessage(e)),
          type = "error",
          duration = 8
        )
      }
    )
  })

  output$live_priv_panel <- renderUI({
    if (is.null(rv$live_data)) {
      return(div(
        class = "placeholder-msg",
        "Click \u2018Query Live DB\u2019 to compare the log against the current Oracle state."
      ))
    }
    DT::dataTableOutput("live_priv_table")
  })

  output$live_priv_table <- DT::renderDataTable({
    req(rv$live_data)
    DT::datatable(
      rv$live_data,
      options = list(pageLength = 15, scrollX = TRUE, dom = "tip"),
      rownames = FALSE,
      class = "display compact"
    )
  })

  # ── Cleanup ───────────────────────────────────────────────────────────────
  session$onSessionEnded(function() {
    conn <- isolate(rv$conn)
    if (!is.null(conn)) {
      tryCatch(DBI::dbDisconnect(conn), error = function(e) NULL)
    }
  })
}

# ── Launch ────────────────────────────────────────────────────────────────────
shinyApp(ui, server)
