# facility-table.R
# Data prep and reactable builder for the facility directory table.
# Sourced from facility-table.qmd.

library(dplyr)
library(tidyr)
library(purrr)
library(reactable)
library(reactablefmtr)
library(htmltools)
library(crosstalk)

# ── Year constants ────────────────────────────────────────────────────────────

.year_order <- c("FY10","FY11","FY12","FY13","FY14","FY15","FY16","FY17",
                 "FY19","FY20","FY21","FY22","FY23","FY24","FY25","FY26")

# Ordered year sequence including FY18 placeholder slot
.year_seq_gap <- c("FY10","FY11","FY12","FY13","FY14","FY15","FY16","FY17",
                   "FY18","FY19","FY20","FY21","FY22","FY23","FY24","FY25","FY26")

# ── Build facility table ──────────────────────────────────────────────────────

#' Assemble one-row-per-facility data frame for the facility directory table.
#'
#' @param expanded_map_geocoded  Output of build_expanded_map_geocoded().
#' @param expanded_map_presence  Output of build_expanded_map_presence().
#' @param expanded_map_panel     Output of build_expanded_map_panel().
#' @param ddp_raw                Raw DDP daily population tibble.
#' @param detloc_lookup_complete Full DETLOC → canonical_id lookup.
#' @return Tibble: one row per canonical facility with list columns for
#'   adp_values (named numeric vector, FY10–FY26 incl. FY18 NA) and
#'   ddp_sparkline (numeric vector of weekly averages).
build_facility_table_data <- function(expanded_map_geocoded,
                                       expanded_map_presence,
                                       expanded_map_panel,
                                       ddp_raw,
                                       detloc_lookup_complete,
                                       ddp_sparkline_src = ddp_raw) {

  # ── Base metadata ───────────────────────────────────────────────────────────
  geo <- expanded_map_geocoded |>
    select(canonical_id, canonical_name, facility_city, facility_state,
           facility_type_wiki, detloc)

  pres <- expanded_map_presence |>
    select(canonical_id, first_seen, last_seen, trajectory, n_years_current)

  # ── ADP panel ───────────────────────────────────────────────────────────────
  panel <- expanded_map_panel |>
    filter(!is.na(canonical_id)) |>
    group_by(canonical_id, fiscal_year) |>
    summarise(
      adp      = sum(adp, na.rm = TRUE),
      ddp_peak = suppressWarnings(max(peak_population, na.rm = TRUE)),
      .groups  = "drop"
    ) |>
    mutate(ddp_peak = if_else(is.finite(ddp_peak), ddp_peak, NA_real_))

  latest_adp <- panel |>
    filter(!is.na(adp), adp > 0) |>
    arrange(canonical_id, desc(match(fiscal_year, .year_order))) |>
    distinct(canonical_id, .keep_all = TRUE) |>
    transmute(canonical_id, latest_adp = round(adp), adp_fy = fiscal_year)

  ddp_peak_summary <- panel |>
    filter(!is.na(ddp_peak)) |>
    arrange(canonical_id, desc(ddp_peak), desc(match(fiscal_year, .year_order))) |>
    distinct(canonical_id, .keep_all = TRUE) |>
    transmute(canonical_id, ddp_peak = round(ddp_peak), ddp_peak_fy = fiscal_year)

  # ADP named vector per facility (NA slot for FY18)
  adp_vec <- panel |>
    select(canonical_id, fiscal_year, adp) |>
    group_by(canonical_id) |>
    summarise(
      adp_values = list({
        vals <- setNames(rep(NA_real_, length(.year_seq_gap)), .year_seq_gap)
        vals[fiscal_year] <- adp
        vals
      }),
      .groups = "drop"
    )

  # Effective peak for the slider
  effective_peak <- panel |>
    group_by(canonical_id) |>
    summarise(
      ddp_peak_eff = suppressWarnings(max(ddp_peak, na.rm = TRUE)),
      max_ice_adp  = suppressWarnings(max(adp, na.rm = TRUE)),
      has_ice      = any(!is.na(adp)),
      .groups      = "drop"
    ) |>
    mutate(
      ddp_peak_eff   = if_else(is.finite(ddp_peak_eff), ddp_peak_eff, NA_real_),
      max_ice_adp    = if_else(is.finite(max_ice_adp),  max_ice_adp,  NA_real_),
      effective_peak = coalesce(ddp_peak_eff, max_ice_adp)
    ) |>
    select(canonical_id, effective_peak)

  # ── DDP daily sparkline (weekly averages) ───────────────────────────────────
  detloc_key <- detloc_lookup_complete |>
    arrange(canonical_id) |>
    distinct(detloc, .keep_all = TRUE) |>
    select(detloc, canonical_id)

  ddp_weekly <- ddp_sparkline_src |>
    left_join(detloc_key, by = c("detention_facility_code" = "detloc")) |>
    filter(!is.na(canonical_id)) |>
    mutate(week = as.Date(cut(date, "week"))) |>
    group_by(canonical_id, week) |>
    summarise(pop = mean(n_detained, na.rm = TRUE), .groups = "drop") |>
    arrange(canonical_id, week) |>
    group_by(canonical_id) |>
    summarise(
      ddp_sparkline = list({
        v <- round(pop, 1)
        names(v) <- as.character(week)
        v
      }),
      .groups = "drop"
    )

  # ── Join ────────────────────────────────────────────────────────────────────
  most_recent_fy <- tail(.year_order, 1)

  geo |>
    left_join(pres,             by = "canonical_id") |>
    left_join(latest_adp,       by = "canonical_id") |>
    left_join(ddp_peak_summary, by = "canonical_id") |>
    left_join(adp_vec,          by = "canonical_id") |>
    left_join(ddp_weekly,       by = "canonical_id") |>
    left_join(effective_peak,   by = "canonical_id") |>
    # Ensure ddp_sparkline is always a list (empty numeric for facilities with no DDP)
    mutate(ddp_sparkline = map(ddp_sparkline,
                               ~if (is.null(.x)) numeric(0) else .x)) |>
    mutate(
      location = case_when(
        !is.na(facility_city) & !is.na(facility_state) ~
          paste0(facility_city, ", ", facility_state),
        TRUE ~ coalesce(facility_city, facility_state, "")
      ),
      status_label = if_else(last_seen == most_recent_fy, "Active", "Closed"),
      adp_label    = if_else(!is.na(latest_adp),
        paste0(format(latest_adp, big.mark = ","), "\u00a0(", adp_fy, ")"),
        NA_character_),
      peak_label   = if_else(!is.na(ddp_peak),
        paste0(format(ddp_peak,   big.mark = ","), "\u00a0(", ddp_peak_fy, ")"),
        NA_character_),
      span_label   = paste0(coalesce(first_seen, "?"), "\u2013", coalesce(last_seen, "?"))
    )
}

# ── SVG sparkline cell renderer ──────────────────────────────────────────────

#' Render a named numeric vector as an SVG area sparkline.
#' Names should be ISO date strings (week start dates); used for axis labels.
sparkline_svg <- function(values, width = 140, line_height = 26,
                           color = "#4682b4", area_opacity = 0.15) {
  if (is.null(values) || length(values) == 0 || all(is.na(values))) return("")
  values[is.na(values)] <- 0
  n <- length(values)
  if (n < 2) return("")
  max_v <- max(values)
  if (max_v == 0) return("")

  label_h <- 9
  total_h <- line_height + label_h

  xs <- (seq_len(n) - 1) / (n - 1) * width
  ys <- line_height - values / max_v * line_height

  pts      <- paste(sprintf("%.1f,%.1f", xs, ys), collapse = " ")
  area_pts <- paste0(
    sprintf("0,%.1f ", line_height), pts,
    sprintf(" %.1f,%.1f", width, line_height)
  )

  # Jan 1 reference lines (white, drawn over the fill)
  jan_lines <- ""
  if (!is.null(names(values)) && !anyNA(names(values))) {
    start_date <- as.Date(names(values)[1])
    end_date   <- as.Date(tail(names(values), 1))
    span_days  <- as.numeric(end_date - start_date)
    if (span_days > 0) {
      # All Jan 1 dates strictly within the data range
      jan1s <- seq(
        as.Date(paste0(as.integer(format(start_date, "%Y")) + 1L, "-01-01")),
        as.Date(paste0(as.integer(format(end_date,   "%Y")),       "-01-01")),
        by = "year"
      )
      jan1s <- jan1s[jan1s > start_date & jan1s < end_date]
      jan_lines <- paste(vapply(jan1s, function(d) {
        xp <- as.numeric(d - start_date) / span_days * width
        sprintf(
          '<line x1="%.1f" x2="%.1f" y1="0" y2="%d" stroke="white" stroke-width="0.8" opacity="0.7"/>',
          xp, xp, line_height
        )
      }, character(1)), collapse = "")
    }
  }

  # Date labels: format week date as "MonYY" (e.g. "Sep23", "Mar26")
  fmt_date  <- function(d) format(as.Date(d), "%b%y")
  start_lbl <- if (!is.null(names(values))) fmt_date(names(values)[1])   else ""
  end_lbl   <- if (!is.null(names(values))) fmt_date(tail(names(values), 1)) else ""

  lbl_y  <- line_height + label_h - 1
  labels <- paste0(
    sprintf('<text x="0" y="%d" font-size="6.5" font-family="sans-serif" fill="#888" text-anchor="start">%s</text>',
            lbl_y, start_lbl),
    sprintf('<text x="%d" y="%d" font-size="6.5" font-family="sans-serif" fill="#888" text-anchor="end">%s</text>',
            width, lbl_y, end_lbl)
  )

  paste0(
    sprintf('<svg width="%d" height="%d" style="display:block;overflow:visible;">',
            width, total_h),
    sprintf('<polygon points="%s" fill="%s" opacity="%.2f"/>',
            area_pts, color, area_opacity),
    sprintf('<polyline points="%s" fill="none" stroke="%s" stroke-width="1.2"/>',
            pts, color),
    jan_lines,
    labels,
    "</svg>"
  ) |> HTML()
}

# ── ADP bar chart SVG cell renderer ──────────────────────────────────────────

#' Render a named ADP vector as an SVG bar chart with a half-width FY18 gap.
#' Labels the first and last bars that contain data with their FY name.
adp_bars_svg <- function(values, width = 140, bar_h_max = 26, gap = 1.2) {
  if (is.null(values) || all(is.na(values))) return("")
  max_v <- max(values, na.rm = TRUE)
  if (!is.finite(max_v) || max_v == 0) return("")

  n       <- length(values)
  nms     <- names(values)
  total_w <- width - gap * (n - 1)
  bar_w   <- total_w / (n - 0.5)
  half_w  <- bar_w / 2

  label_h <- 9
  total_h <- bar_h_max + label_h

  # Pre-compute x positions and widths for every slot
  bar_x <- numeric(n)
  bar_w_each <- numeric(n)
  x <- 0
  for (i in seq_len(n)) {
    bar_x[i]     <- x
    bar_w_each[i] <- if (nms[i] == "FY18") half_w else bar_w
    x <- x + bar_w_each[i] + gap
  }

  has_data <- !is.na(values) & values > 0
  first_i  <- which(has_data)[1]
  last_i   <- tail(which(has_data), 1)

  rects <- character(n)
  for (i in seq_len(n)) {
    v <- values[[i]]
    if (has_data[i]) {
      h <- max(1.5, v / max_v * bar_h_max)
      y <- bar_h_max - h
      rects[i] <- sprintf(
        '<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="#888" rx="0.5"/>',
        bar_x[i], y, bar_w_each[i], h
      )
    }
  }

  # FY labels beneath first and last data bars
  lbl_y  <- bar_h_max + label_h - 1
  labels <- character(0)
  if (!is.na(first_i)) {
    cx <- bar_x[first_i] + bar_w_each[first_i] / 2
    labels <- c(labels, sprintf(
      '<text x="%.1f" y="%d" font-size="5.5" font-family="sans-serif" fill="#888" text-anchor="middle">%s</text>',
      cx, lbl_y, nms[first_i]
    ))
  }
  if (!is.na(last_i) && !identical(last_i, first_i)) {
    cx <- bar_x[last_i] + bar_w_each[last_i] / 2
    labels <- c(labels, sprintf(
      '<text x="%.1f" y="%d" font-size="5.5" font-family="sans-serif" fill="#888" text-anchor="middle">%s</text>',
      cx, lbl_y, nms[last_i]
    ))
  }

  paste0(
    sprintf('<svg width="%d" height="%d" style="display:block;overflow:visible;">',
            width, total_h),
    paste(c(rects, labels), collapse = ""),
    "</svg>"
  ) |> HTML()
}

# ── Reactable builder ─────────────────────────────────────────────────────────

#' Build a filterable reactable of ICE detention facilities.
#'
#' @param df       Output of build_facility_table_data().
#' @param columns  Character vector of column keys to include. Available keys:
#'   "facility", "type", "status", "adp", "ddp_peak", "detloc",
#'   "adp_bars", "ddp_sparkline".
#' @param min_peak Minimum effective peak population to include (default 2).
#'   Passed as SharedData filter_slider default; set NULL to skip slider.
#' @return A tagList of (optional slider +) reactable htmlwidget.
make_facility_table <- function(df,
                                 columns   = c("facility", "type", "status",
                                               "adp", "ddp_peak", "detloc",
                                               "adp_bars", "ddp_sparkline"),
                                 min_peak  = 2) {

  df <- df |> filter(is.na(effective_peak) | effective_peak >= min_peak)
  sd <- SharedData$new(df, ~canonical_id)

  # Map friendly column keys → actual data column names
  key_map <- c(
    facility     = "canonical_name",
    type         = "facility_type_wiki",
    status       = "status_label",
    adp          = "adp_label",
    ddp_peak     = "peak_label",
    detloc       = "detloc",
    adp_bars     = "adp_values",
    ddp_sparkline = "ddp_sparkline"
  )
  selected_data_cols <- unname(key_map[columns])

  # ── All possible column definitions (keyed by data column name) ─────────────
  all_col_defs <- list(

    canonical_name = colDef(
      name     = "Facility",
      minWidth = 210,
      filterable = TRUE,
      filterMethod = JS("function(rows, columnId, filterValue) {
        var lc = filterValue.toLowerCase();
        return rows.filter(function(row) {
          var v = (row.values['canonical_name'] || '') + ' ' +
                  (row.values['location'] || '');
          return v.toLowerCase().indexOf(lc) >= 0;
        });
      }"),
      cell = function(value, index) {
        row <- df[index, ]
        div(
          style = "line-height:1.3;",
          div(style = "font-weight:600; font-size:0.88em;", row$canonical_name),
          div(style = "color:#666; font-size:0.78em;", row$location)
        )
      },
      html = TRUE
    ),

    facility_type_wiki = colDef(
      name       = "Type",
      minWidth   = 160,
      filterable = TRUE,
      style      = list(fontSize = "0.82em", color = "#444")
    ),

    status_label = colDef(
      name     = "Status",
      minWidth = 130,
      filterable = TRUE,
      cell = function(value, index) {
        row <- df[index, ]
        div(
          style = "font-size:0.82em; line-height:1.5;",
          div(span(
            style = paste0("font-weight:600; color:",
                           if (isTRUE(row$status_label == "Active")) "#2a7a2a"
                           else "#888", ";"),
            row$status_label
          )),
          div(style = "color:#666;", row$span_label)
        )
      },
      html = TRUE
    ),

    adp_label = colDef(
      name       = "ADP",
      minWidth   = 105,
      filterable = FALSE,
      style      = list(fontSize = "0.82em", fontVariantNumeric = "tabular-nums",
                        textAlign = "right")
    ),

    peak_label = colDef(
      name       = "DDP Peak",
      minWidth   = 105,
      filterable = FALSE,
      style      = list(fontSize = "0.82em", fontVariantNumeric = "tabular-nums",
                        textAlign = "right")
    ),

    detloc = colDef(
      name       = "DETLOC",
      minWidth   = 85,
      filterable = TRUE,
      style      = list(fontSize = "0.80em", fontFamily = "monospace",
                        color = "#555")
    ),

    adp_values = colDef(
      name       = "ADP by year",
      minWidth   = 155,
      filterable = FALSE,
      sortable   = FALSE,
      html       = TRUE,
      cell       = function(value, index) adp_bars_svg(df$adp_values[[index]])
    ),

    ddp_sparkline = colDef(
      name       = "Daily pop. (DDP)",
      minWidth   = 145,
      filterable = FALSE,
      sortable   = FALSE,
      html       = TRUE,
      cell       = function(value, index) sparkline_svg(df$ddp_sparkline[[index]])
    )
  )

  # All other data columns are hidden; only selected ones are shown
  all_data_cols <- names(df)
  hidden_data_cols <- setdiff(all_data_cols, selected_data_cols)
  hidden_col_defs  <- setNames(
    lapply(hidden_data_cols, function(.) colDef(show = FALSE)),
    hidden_data_cols
  )

  selected_cols <- c(all_col_defs[selected_data_cols], hidden_col_defs)

  slider <- filter_slider(
    "peak_slider", "Minimum peak population",
    sd, ~effective_peak,
    min = 0, step = 1, width = "300px"
  )

  tbl <- reactable(
    sd,
    theme      = nytimes(font_size = 13),
    columns    = selected_cols,
    searchable = FALSE,
    sortable   = TRUE,
    pagination = TRUE,
    defaultPageSize = 25,
    showPageSizeOptions = TRUE,
    pageSizeOptions = c(25, 50, 100),
    striped    = FALSE,
    highlight  = TRUE,
    compact    = TRUE,
    defaultSorted = list(effective_peak = "desc")
  )

  tagList(
    div(style = "margin-bottom:12px;", slider),
    tbl
  )
}

# ── Export ────────────────────────────────────────────────────────────────────

#' Build and export facility_tbl.rds for the facility-directory post.
#' Returns the output file path (for use as a targets "file" target).
export_facility_directory_data <- function(expanded_map_geocoded,
                                            expanded_map_presence,
                                            expanded_map_panel,
                                            ddp_raw,
                                            detloc_lookup_complete,
                                            ddp_new) {
  out_dir <- here::here("data", "facility-directory-export")
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  out_path <- file.path(out_dir, "facility_tbl.rds")

  facility_tbl <- build_facility_table_data(
    expanded_map_geocoded  = expanded_map_geocoded,
    expanded_map_presence  = expanded_map_presence,
    expanded_map_panel     = expanded_map_panel,
    ddp_raw                = ddp_raw,
    detloc_lookup_complete = detloc_lookup_complete,
    ddp_sparkline_src      = ddp_new
  )

  saveRDS(facility_tbl, out_path)
  cli::cli_inform("Exported facility_tbl.rds ({nrow(facility_tbl)} rows) to {.path {out_path}}")
  out_path
}
