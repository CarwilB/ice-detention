# R/facility-profiles.R
# Functions to build before/after facility profile data from DDP detention stints.
# Entry point: build_facility_profiles_data(stints)

# ── Facility group configuration ─────────────────────────────────────────────

#' Named list of facility groups.
#' Each entry: list(label = "...", codes = c("DETLOC1", ...))
facility_group_config <- function() {
  list(
    IWAHOLD = list(
      label = "AZ Removal Ops Coordination Center / AROCC (Phoenix AOR)",
      codes = "IWAHOLD"
    ),
    SPMHOLD = list(
      label = "Bishop Henry Whipple Federal Building hold room (St. Paul AOR)",
      codes = "SPMHOLD"
    ),
    PINEPLA = list(
      label = "Pine Prairie ICE Processing Center (New Orleans AOR)",
      codes = "PINEPLA"
    ),
    DILLEY = list(
      label = "Dilley South Texas Family Residential Center / STFRCTX + DILLSAF (San Antonio AOR)",
      codes = c("STFRCTX", "DILLSAF")
    ),
    NWDC = list(
      label = "Northwest ICE Processing Center / NWDC (Seattle AOR)",
      codes = "CSCNWWA"
    )
  )
}

# ── Data preparation ──────────────────────────────────────────────────────────

#' Filter stints to target facilities, add group/period labels and derived columns.
#' @param stints  Raw stints data frame (detention-stints-latest.parquet).
#' @param groups  Output of facility_group_config().
#' @param cutoff  Date or POSIXct splitting "before" vs "after" periods.
prepare_stints <- function(stints, groups,
                           cutoff = as.Date("2025-01-20")) {
  cutoff <- as.Date(cutoff)

  # Build a lookup: detloc -> group key
  code_to_group <- purrr::map_dfr(
    names(groups),
    function(k) tibble::tibble(
      detention_facility_code = groups[[k]]$codes,
      facility_group  = k,
      facility_label  = groups[[k]]$label
    )
  )

  stints |>
    dplyr::filter(
      detention_facility_code %in% code_to_group$detention_facility_code,
      likely_duplicate == FALSE | is.na(likely_duplicate)
    ) |>
    dplyr::left_join(code_to_group, by = "detention_facility_code") |>
    dplyr::mutate(
      book_in_date   = as.Date(book_in_date_time),
      period         = dplyr::if_else(book_in_date < cutoff, "Before", "After"),
      period         = factor(period, levels = c("Before", "After")),
      stint_days     = as.numeric(difftime(book_out_date_time,
                                           book_in_date_time, units = "days")),
      age_at_bookin  = as.integer(format(book_in_date_time, "%Y")) - birth_year,
      # Clean up the "NA" string in case_threat_level
      threat_level_clean = dplyr::case_when(
        is.na(case_threat_level)     ~ NA_character_,
        case_threat_level == "NA"    ~ "None (non-criminal)",
        TRUE                          ~ paste0("Level ", case_threat_level)
      )
    )
}

# ── Summary helpers ───────────────────────────────────────────────────────────

#' Overview table: one row per facility_group × period.
profile_overview <- function(base) {
  base |>
    dplyr::group_by(facility_group, facility_label, period) |>
    dplyr::summarise(
      n_stints         = dplyr::n(),
      n_with_bookout   = sum(!is.na(stint_days)),
      median_days      = round(median(stint_days, na.rm = TRUE), 1),
      mean_days        = round(mean(stint_days, na.rm = TRUE), 1),
      p90_days         = round(quantile(stint_days, 0.90, na.rm = TRUE), 1),
      pct_male         = round(mean(gender == "Male", na.rm = TRUE) * 100, 1),
      median_age       = round(median(age_at_bookin, na.rm = TRUE), 1),
      pct_under18      = round(mean(age_at_bookin < 18, na.rm = TRUE) * 100, 2),
      pct_criminal     = round(mean(book_in_criminality %in%
                                    c("1 Convicted Criminal",
                                      "2 Pending Criminal Charges"),
                                    na.rm = TRUE) * 100, 1),
      pct_final_order  = round(mean(final_order_yes_no == "YES",
                                    na.rm = TRUE) * 100, 1),
      pct_removed      = round(mean(detention_release_reason == "Removed",
                                    na.rm = TRUE) * 100, 1),
      pct_transferred  = round(mean(detention_release_reason == "Transferred",
                                    na.rm = TRUE) * 100, 1),
      .groups = "drop"
    )
}

#' Generic counts table for a categorical column.
#' Returns n and pct per facility_group × period × value.
profile_counts <- function(base, col, top_n = NULL) {
  out <- base |>
    dplyr::mutate(value = .data[[col]]) |>
    dplyr::count(facility_group, facility_label, period, value, name = "n") |>
    dplyr::group_by(facility_group, period) |>
    dplyr::mutate(pct = round(n / sum(n) * 100, 1)) |>
    dplyr::ungroup() |>
    dplyr::arrange(facility_group, period, dplyr::desc(n))

  if (!is.null(top_n)) {
    top_vals <- out |>
      dplyr::group_by(facility_group, value) |>
      dplyr::summarise(total = sum(n), .groups = "drop") |>
      dplyr::group_by(facility_group) |>
      dplyr::slice_max(total, n = top_n) |>
      dplyr::pull(value) |>
      unique()
    out <- out |> dplyr::filter(value %in% top_vals)
  }
  out
}

#' Top nationalities: top 12 per facility group (union across periods).
profile_nationalities <- function(base, n = 12) {
  profile_counts(base, "citizenship_country", top_n = n)
}

#' Age distribution in bands.
profile_age_bands <- function(base) {
  base |>
    dplyr::mutate(
      age_band = dplyr::case_when(
        is.na(age_at_bookin)      ~ NA_character_,
        age_at_bookin < 18        ~ "Under 18",
        age_at_bookin < 25        ~ "18–24",
        age_at_bookin < 35        ~ "25–34",
        age_at_bookin < 45        ~ "35–44",
        age_at_bookin < 55        ~ "45–54",
        TRUE                      ~ "55+"
      ),
      age_band = factor(age_band,
                        levels = c("Under 18","18–24","25–34",
                                   "35–44","45–54","55+"))
    ) |>
    dplyr::count(facility_group, facility_label, period, age_band) |>
    dplyr::group_by(facility_group, period) |>
    dplyr::mutate(pct = round(n / sum(n) * 100, 1)) |>
    dplyr::ungroup()
}

# ── ADP and totals (from stints, clipped to period windows) ──────────────────

#' Compute ADP and throughput totals for each facility group × period.
#'
#' ADP is computed via person-days: every stint overlapping the period
#' contributes (min(book_out, period_end) − max(book_in, period_start)) days.
#' Totals (n_stints, unique persons) count stints *booked in* during the period.
#'
#' @param stints         Raw stints data frame.
#' @param facility_groups Output of facility_group_config().
#' @param cutoff         Period split date.
profile_adp_and_totals <- function(stints, facility_groups,
                                   cutoff = as.Date("2025-01-20")) {
  cutoff     <- as.Date(cutoff)
  data_start <- as.Date("2022-10-01")   # earliest reliable data in dataset
  data_end   <- as.Date("2026-03-11")   # last date in dataset

  periods <- list(
    Before = c(data_start, cutoff - 1),
    After  = c(cutoff,     data_end)
  )

  code_to_group <- purrr::map_dfr(names(facility_groups), function(k) {
    tibble::tibble(
      detention_facility_code = facility_groups[[k]]$codes,
      facility_group  = k,
      facility_label  = facility_groups[[k]]$label
    )
  })

  s <- stints |>
    dplyr::filter(
      detention_facility_code %in% code_to_group$detention_facility_code,
      likely_duplicate == FALSE | is.na(likely_duplicate)
    ) |>
    dplyr::left_join(code_to_group, by = "detention_facility_code") |>
    dplyr::mutate(
      book_in_date  = as.Date(book_in_date_time),
      book_out_date = as.Date(book_out_date_time)
    )

  purrr::map_dfr(names(periods), function(pname) {
    p_start <- periods[[pname]][1]
    p_end   <- periods[[pname]][2]
    p_days  <- as.numeric(p_end - p_start + 1)

    # ADP via person-days (all stints overlapping the period)
    adp_by_group <- s |>
      dplyr::filter(book_in_date <= p_end,
                    is.na(book_out_date) | book_out_date > p_start) |>
      dplyr::mutate(
        eff_out     = pmin(dplyr::coalesce(book_out_date, data_end), p_end),
        eff_start   = pmax(book_in_date, p_start),
        person_days = pmax(0, as.numeric(eff_out - eff_start))
      ) |>
      dplyr::group_by(facility_group) |>
      dplyr::summarise(
        adp_stints = round(sum(person_days, na.rm = TRUE) / p_days, 1),
        .groups    = "drop"
      )

    # Throughput totals (stints booked in during period)
    totals_by_group <- s |>
      dplyr::filter(book_in_date >= p_start, book_in_date <= p_end) |>
      dplyr::group_by(facility_group) |>
      dplyr::summarise(
        n_stints         = dplyr::n(),
        n_unique_persons = dplyr::n_distinct(unique_identifier, na.rm = TRUE),
        .groups          = "drop"
      ) |>
      dplyr::mutate(
        period_days      = p_days,
        stints_per_year  = round(n_stints / (p_days / 365.25)),
        persons_per_year = round(n_unique_persons / (p_days / 365.25))
      )

    dplyr::left_join(adp_by_group, totals_by_group, by = "facility_group") |>
      dplyr::mutate(period = factor(pname, levels = c("Before", "After")))
  })
}

# ── SVG chart helpers (character output, no htmltools dependency) ─────────────

#' SVG area sparkline from a named numeric vector of weekly populations.
#' Returns a plain SVG character string suitable for embedding in HTML.
.profile_sparkline_svg <- function(values, width = 500, line_height = 55,
                                   color = "#4682b4", area_opacity = 0.15) {
  if (is.null(values) || length(values) == 0 || all(is.na(values))) return("")
  values[is.na(values)] <- 0
  n <- length(values)
  if (n < 2 || max(values) == 0) return("")

  label_h <- 11
  total_h <- line_height + label_h
  xs <- (seq_len(n) - 1) / (n - 1) * width
  ys <- line_height - values / max(values) * line_height
  pts      <- paste(sprintf("%.1f,%.1f", xs, ys), collapse = " ")
  area_pts <- paste0(sprintf("0,%.1f ", line_height), pts,
                     sprintf(" %.1f,%.1f", width, line_height))

  # Jan 1 reference lines
  jan_lines <- ""
  if (!is.null(names(values)) && !anyNA(names(values))) {
    start_d <- as.Date(names(values)[1])
    end_d   <- as.Date(tail(names(values), 1))
    span_d  <- as.numeric(end_d - start_d)
    if (span_d > 0) {
      jan1s <- seq(
        as.Date(paste0(as.integer(format(start_d, "%Y")) + 1L, "-01-01")),
        as.Date(paste0(as.integer(format(end_d,   "%Y")),       "-01-01")),
        by = "year"
      )
      jan1s <- jan1s[jan1s > start_d & jan1s < end_d]
      jan_lines <- paste(vapply(jan1s, function(d) {
        xp <- as.numeric(d - start_d) / span_d * width
        sprintf('<line x1="%.1f" x2="%.1f" y1="0" y2="%d" stroke="white" stroke-width="1" opacity="0.6"/>',
                xp, xp, line_height)
      }, character(1)), collapse = "")
    }
  }

  fmt_d   <- function(d) format(as.Date(d), "%b %Y")
  s_lbl   <- if (!is.null(names(values))) fmt_d(names(values)[1])          else ""
  e_lbl   <- if (!is.null(names(values))) fmt_d(tail(names(values), 1))    else ""
  lbl_y   <- line_height + label_h - 1

  paste0(
    sprintf('<svg width="%d" height="%d" style="display:block;overflow:visible;">',
            width, total_h),
    sprintf('<polygon points="%s" fill="%s" opacity="%.2f"/>',
            area_pts, color, area_opacity),
    sprintf('<polyline points="%s" fill="none" stroke="%s" stroke-width="1.4"/>',
            pts, color),
    jan_lines,
    sprintf('<text x="0" y="%d" font-size="8" font-family="sans-serif" fill="#888">%s</text>',
            lbl_y, s_lbl),
    sprintf('<text x="%d" y="%d" font-size="8" font-family="sans-serif" fill="#888" text-anchor="end">%s</text>',
            width, lbl_y, e_lbl),
    "</svg>"
  )
}

#' SVG bar chart from a named FY ADP vector (FY10..FY26 with FY18 half-gap).
#' Returns a plain SVG character string.
.profile_bars_svg <- function(values, width = 500, bar_h_max = 55, gap = 1.5) {
  if (is.null(values) || all(is.na(values))) return("")
  max_v <- max(values, na.rm = TRUE)
  if (!is.finite(max_v) || max_v == 0) return("")

  n       <- length(values)
  nms     <- names(values)
  total_w <- width - gap * (n - 1)
  bar_w   <- total_w / (n - 0.5)
  half_w  <- bar_w / 2
  label_h <- 11
  total_h <- bar_h_max + label_h

  bar_x <- numeric(n); bar_w_each <- numeric(n); x <- 0
  for (i in seq_len(n)) {
    bar_x[i]      <- x
    bar_w_each[i] <- if (!is.null(nms) && nms[i] == "FY18") half_w else bar_w
    x <- x + bar_w_each[i] + gap
  }

  has_data <- !is.na(values) & values > 0
  first_i  <- which(has_data)[1]
  last_i   <- tail(which(has_data), 1)

  rects <- vapply(seq_len(n), function(i) {
    if (!has_data[i]) return("")
    h <- max(2, values[[i]] / max_v * bar_h_max)
    y <- bar_h_max - h
    sprintf('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="#888" rx="0.5"/>',
            bar_x[i], y, bar_w_each[i], h)
  }, character(1))

  lbl_y  <- bar_h_max + label_h - 1
  labels <- character(0)
  if (length(first_i) && !is.na(first_i)) {
    cx <- bar_x[first_i] + bar_w_each[first_i] / 2
    labels <- c(labels, sprintf(
      '<text x="%.1f" y="%d" font-size="7" font-family="sans-serif" fill="#888" text-anchor="middle">%s</text>',
      cx, lbl_y, nms[first_i]))
  }
  if (length(last_i) && !is.na(last_i) && !identical(last_i, first_i)) {
    cx <- bar_x[last_i] + bar_w_each[last_i] / 2
    labels <- c(labels, sprintf(
      '<text x="%.1f" y="%d" font-size="7" font-family="sans-serif" fill="#888" text-anchor="middle">%s</text>',
      cx, lbl_y, nms[last_i]))
  }

  paste0(
    sprintf('<svg width="%d" height="%d" style="display:block;overflow:visible;">',
            width, total_h),
    paste(c(rects, labels), collapse = ""),
    "</svg>"
  )
}

# ── Visualization data (sparklines + ADP bar charts) ─────────────────────────

.year_seq_gap_fp <- c("FY10","FY11","FY12","FY13","FY14","FY15","FY16","FY17",
                      "FY18","FY19","FY20","FY21","FY22","FY23","FY24","FY25","FY26")

#' Build sparkline and ADP bar chart data for each facility group.
#'
#' @param facility_groups  Output of facility_group_config().
#' @param ddp_pop          Daily population parquet (ddp_new target): date, detention_facility_code, n_detained.
#' @param facilities_panel Long-format ICE annual stats panel (facilities_panel target).
#' @param detloc_lookup    DETLOC → canonical_id lookup (detloc_lookup_complete target).
#' @return Named list (one element per facility group) of list(sparkline_svg, adp_bars_svg, adp_years).
profile_viz_data <- function(facility_groups, ddp_pop, facilities_panel,
                              detloc_lookup) {
  purrr::imap(facility_groups, function(grp, key) {
    codes <- grp$codes

    # DDP daily population sparkline (weekly averages, summed across multi-code groups)
    daily <- ddp_pop |>
      dplyr::filter(detention_facility_code %in% codes) |>
      dplyr::group_by(date) |>
      dplyr::summarise(n_detained = sum(n_detained, na.rm = TRUE), .groups = "drop") |>
      dplyr::mutate(week = as.Date(cut(date, "week"))) |>
      dplyr::group_by(week) |>
      dplyr::summarise(pop = mean(n_detained, na.rm = TRUE), .groups = "drop") |>
      dplyr::arrange(week)

    sparkline_vals <- if (nrow(daily) > 0) {
      setNames(round(daily$pop, 1), as.character(daily$week))
    } else { numeric(0) }

    # ICE annual stats ADP bars (from facilities_panel)
    canon_ids <- detloc_lookup |>
      dplyr::filter(detloc %in% codes) |>
      dplyr::pull(canonical_id) |>
      unique()

    if (length(canon_ids) > 0) {
      adp_data <- facilities_panel |>
        dplyr::filter(canonical_id %in% canon_ids, !is.na(adp)) |>
        dplyr::group_by(fiscal_year) |>
        dplyr::summarise(adp = sum(adp, na.rm = TRUE), .groups = "drop")
      bar_vals <- setNames(rep(NA_real_, length(.year_seq_gap_fp)), .year_seq_gap_fp)
      bar_vals[adp_data$fiscal_year] <- adp_data$adp
    } else {
      bar_vals <- NULL
    }

    list(
      sparkline_svg = .profile_sparkline_svg(sparkline_vals),
      adp_bars_svg  = .profile_bars_svg(bar_vals),
      # Also store raw values for any further computation
      sparkline_vals = sparkline_vals,
      adp_bar_vals   = bar_vals
    )
  })
}

# ── Main entry point ──────────────────────────────────────────────────────────

#' Build all facility profile summary tables (before/after inauguration split).
#'
#' @param stints           Raw stints (detention-stints-latest.parquet).
#' @param ddp_pop          Daily population parquet (ddp_new target).
#' @param facilities_panel ICE annual stats panel (facilities_panel target).
#' @param detloc_lookup    Full DETLOC → canonical_id lookup (detloc_lookup_complete).
#' @param cutoff           Split date (default: 2025-01-20, Trump inauguration).
#' @return Named list of summary tibbles and SVG strings ready for reporting.
build_facility_profiles_data <- function(stints,
                                         ddp_pop,
                                         facilities_panel,
                                         detloc_lookup,
                                         cutoff = as.Date("2025-01-20")) {
  groups <- facility_group_config()
  base   <- prepare_stints(stints, groups, cutoff)

  list(
    cutoff         = cutoff,
    groups         = tibble::tibble(
      facility_group = names(groups),
      facility_label = purrr::map_chr(groups, "label"),
      codes          = purrr::map_chr(groups, ~ paste(.x$codes, collapse = " + "))
    ),
    adp_and_totals = profile_adp_and_totals(stints, groups, cutoff),
    viz            = profile_viz_data(groups, ddp_pop, facilities_panel, detloc_lookup),
    overview       = profile_overview(base),
    nationalities  = profile_nationalities(base, n = 12),
    criminality    = profile_counts(base, "book_in_criminality"),
    classification = profile_counts(base, "detainee_classification"),
    threat_level   = profile_counts(base, "threat_level_clean"),
    release_reason = profile_counts(base, "detention_release_reason"),
    entry_status   = profile_counts(base, "entry_status"),
    final_order    = profile_counts(base, "final_order_yes_no"),
    ina_236c       = profile_counts(base, "case_ina_236c_yes_no"),
    age_bands      = profile_age_bands(base)
  )
}
