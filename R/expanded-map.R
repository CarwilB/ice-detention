# Expanded map: presence matrix and geocoded facility table.
# These are parallel outputs to facility_presence and facilities_geocoded_all;
# neither replaces the ICE-only versions.

build_expanded_map_presence <- function(expanded_map_panel, facility_presence) {
  # Builds a wide-format presence matrix for all canonical facilities in the
  # expanded panel. One row per canonical_id; one boolean column per fiscal year.
  #
  # Trajectory labels:
  #   Panel facilities (canonical_id ≤ 1000): inherited from facility_presence
  #     (continuous / persistent_gaps / new / closed / transient)
  #   Non-panel facilities: "ddp_only" — present only in DDP data (FY23–FY26)

  # Ordered years present in the expanded panel
  all_years <- year_order[year_order %in% unique(expanded_map_panel$fiscal_year)]
  first_year       <- all_years[1]
  most_recent_year <- all_years[length(all_years)]

  # One row per (canonical_id, fiscal_year) with any data
  presence_long <- expanded_map_panel |>
    dplyr::filter(!is.na(canonical_id)) |>
    dplyr::distinct(canonical_id, canonical_name, fiscal_year) |>
    dplyr::mutate(present = TRUE)

  # Pivot to wide, fill missing years with FALSE
  presence <- presence_long |>
    tidyr::pivot_wider(
      names_from  = fiscal_year,
      values_from = present,
      values_fill = FALSE
    )

  # Ensure all year columns exist in canonical order
  for (yr in all_years) {
    if (!yr %in% names(presence)) {
      presence[[yr]] <- FALSE
    }
  }
  presence <- presence |>
    dplyr::select(canonical_id, canonical_name,
                  dplyr::all_of(all_years))

  # Derived summary columns
  presence <- presence |>
    dplyr::mutate(
      n_years = rowSums(dplyr::across(dplyr::all_of(all_years)))
    ) |>
    dplyr::rowwise() |>
    dplyr::mutate(
      yrs       = list(all_years[dplyr::c_across(dplyr::all_of(all_years))]),
      first_seen = yrs[[1]],
      last_seen  = tail(yrs, 1)[[1]]
    ) |>
    dplyr::select(-yrs) |>
    dplyr::ungroup()

  # Consecutive years ending at most_recent_year (for sparkbar "Active FYxx–FY26")
  year_mat <- as.matrix(presence[, all_years])
  presence$n_years_current <- apply(year_mat, 1, function(row) {
    if (!isTRUE(row[most_recent_year])) return(0L)
    count <- 0L
    for (yr in rev(all_years)) {
      if (isTRUE(row[yr])) count <- count + 1L else break
    }
    count
  })

  # Trajectory: inherit from facility_presence for panel IDs; "ddp_only" otherwise
  panel_trajectory <- facility_presence |>
    dplyr::select(canonical_id, trajectory)

  presence |>
    dplyr::left_join(panel_trajectory, by = "canonical_id") |>
    dplyr::mutate(
      trajectory = dplyr::coalesce(trajectory, "ddp_only")
    ) |>
    dplyr::arrange(canonical_id)
}

# Display name overrides for the expanded map.
# canonical_name is used as-is everywhere else in the pipeline; this table
# only affects what the map popup shows.
# Display name overrides: canonical_name only. Applied via rows_update() so
# these overwrite whatever the pipeline produced (including NAs for 401/403/404).
expanded_map_display_name_overrides <- function() {
  tibble::tribble(
    ~canonical_id, ~canonical_name,
     136L, "Florida Soft-Sided Facility (Alligator Alcatraz)",
     176L, "JTF Camp Six (Windward Holding Facility)",
     401L, "Dilley Processing Single Adult Female",
     403L, "Lewisburg US Penitentiary",
     404L, "Migrant Ops Center Main (Guantanamo)",
    1184L, "Southwest Virginia Regional Jail Authority Abingdon Facility",
    2024L, "St Paul Field Office (Whipple Federal Building)",
    2032L, "Arizona Removal Operations Coordination Center (AROCC)"
  )
}

# Type overrides for facilities absent from facility_roster (401/403/404).
# Applied via rows_patch() so they only fill where facility_type_wiki is NA.
expanded_map_display_type_overrides <- function() {
  tibble::tribble(
    ~canonical_id, ~facility_type_wiki,
    401L, "Family Detention Center",
    403L, "Federal Prison",
    404L, "Military Detention Center"
  )
}

build_expanded_map_geocoded <- function(expanded_map_panel, facilities_geocoded_all) {
  # Returns one row per canonical facility in the expanded panel, with
  # geocoded coordinates from facilities_geocoded_all. Facilities missing
  # from geocoded_all (e.g. newly added DDP codes with no address) are
  # retained with lat = NA / lon = NA so the map can handle them gracefully.
  #
  # Facility metadata (name, city, state, type) comes from the most recent
  # year's entry in expanded_map_panel, preferring ICE-sourced rows.

  # Most recent metadata per facility: prefer ICE data over DDP
  meta <- expanded_map_panel |>
    dplyr::filter(!is.na(canonical_id)) |>
    dplyr::mutate(
      source_rank = dplyr::case_when(
        data_source == "ice_only"             ~ 1L,
        data_source %in% c("ice_ddp_agree",
                           "ice_ddp_diverge_high",
                           "ice_ddp_diverge_low") ~ 2L,
        TRUE                                  ~ 3L   # ddp_only
      ),
      year_rank = match(fiscal_year, rev(year_order))
    ) |>
    dplyr::arrange(canonical_id, source_rank, year_rank) |>
    dplyr::distinct(canonical_id, .keep_all = TRUE) |>
    dplyr::select(
      canonical_id, canonical_name,
      facility_city, facility_state, facility_address, facility_zip,
      facility_type_detailed, facility_type_wiki, detloc
    )

  meta |>
    dplyr::left_join(
      facilities_geocoded_all |>
        dplyr::select(canonical_id, lat, lon, geocode_source,
                      address_quality, divergent),
      by = "canonical_id"
    ) |>
    dplyr::left_join(
      canonical_type_overrides() |>
        dplyr::mutate(canonical_id = as.double(canonical_id)) |>
        dplyr::rename(type_override = facility_type_wiki),
      by = "canonical_id"
    ) |>
    dplyr::mutate(
      facility_type_wiki = dplyr::coalesce(type_override, facility_type_wiki)
    ) |>
    dplyr::select(-type_override) |>
    dplyr::rows_update(
      expanded_map_display_name_overrides(),
      by = "canonical_id",
      unmatched = "ignore"
    ) |>
    dplyr::rows_patch(
      expanded_map_display_type_overrides(),
      by = "canonical_id",
      unmatched = "ignore"
    ) |>
    dplyr::arrange(canonical_id)
}

# Expanded map panel: merges ICE annual stats panel with DDP annual panel.
#
# Produces a long-format dataset covering all canonical facilities across all
# available fiscal years, with a five-level data_source flag recording the
# relationship between the two sources for each (facility × year) combination.
#
# data_source values:
#   "ice_only"            — ICE annual stats only; no DDP data for this year
#   "ddp_only"            — DDP data only; facility absent from ICE annual stats
#   "ice_ddp_agree"       — both sources, ADP within threshold of each other
#   "ice_ddp_diverge_high"— both sources, DDP ADP > ICE ADP by > threshold
#   "ice_ddp_diverge_low" — both sources, ICE ADP > DDP ADP by > threshold
#
# ICE data is authoritative where both exist (adp = ice_adp).
# DDP-specific columns (peak_population, peak_date, n_days, adp_male, etc.)
# are NA for ice_only rows. ICE-specific columns (inspections, classification
# levels, threat levels) are NA for ddp_only rows.

build_expanded_map_panel <- function(facilities_panel, ddp_annual_panel,
                                      threshold = 0.25) {
  # ── Prep ICE side ─────────────────────────────────────────────────────────
  # Drop the per-source 'source' column (DMCP / annual_stats) to avoid
  # collision with our new 'data_source' flag.
  ice <- facilities_panel |>
    dplyr::rename(ice_source = source) |>
    dplyr::select(
      fiscal_year, canonical_id, canonical_name,
      facility_name, facility_city, facility_state,
      facility_address, facility_zip,
      facility_type_detailed, facility_type_wiki,
      facility_aor, facility_average_length_of_stay_alos,
      detloc, ice_source,
      ice_adp = adp,
      share_non_crim, share_no_threat,
      adp_criminality_male_crim, adp_criminality_male_non_crim,
      adp_criminality_female_crim, adp_criminality_female_non_crim,
      adp_ice_threat_level_1, adp_ice_threat_level_2,
      adp_ice_threat_level_3, adp_no_ice_threat_level,
      adp_mandatory, inspections_guaranteed_minimum,
      inspections_last_inspection_rating_final
    )

  # ── Prep DDP side (DDP-unique columns only — no shared metadata) ──────────
  # Some canonical IDs have multiple DETLOCs (e.g., Guantánamo components,
  # facility/alias pairs). Sum ADP columns across DETLOCs per canonical/year;
  # take max for peak, recompute shares from summed values.
  ddp_join <- ddp_annual_panel |>
    dplyr::filter(!is.na(canonical_id)) |>
    dplyr::group_by(canonical_id, fiscal_year) |>
    dplyr::summarise(
      ddp_adp          = sum(adp,       na.rm = TRUE),
      adp_male         = sum(adp_male,  na.rm = TRUE),
      adp_female       = sum(adp_female, na.rm = TRUE),
      adp_crim         = sum(adp_crim,  na.rm = TRUE),
      adp_non_crim     = sum(adp_non_crim, na.rm = TRUE),
      peak_population  = max(peak_population, na.rm = TRUE),
      peak_date        = peak_date[which.max(peak_population)],
      n_days           = max(n_days, na.rm = TRUE),
      partial_year     = any(partial_year, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      ddp_share_non_crim = dplyr::if_else(
        ddp_adp > 0, adp_non_crim / ddp_adp, NA_real_),
      share_female = dplyr::if_else(
        ddp_adp > 0, adp_female  / ddp_adp, NA_real_)
    )

  # ── Deduplicate ICE side ─────────────────────────────────────────────────
  # A small number of (canonical_id, fiscal_year) pairs appear twice in
  # facilities_panel (DMCP + annual-stats overlap, or crosswalk edge cases).
  # Sum ADP components; keep remaining metadata from the first row.
  ice <- ice |>
    dplyr::group_by(canonical_id, fiscal_year) |>
    dplyr::mutate(dplyr::across(
      c(ice_adp, share_non_crim, share_no_threat,
        dplyr::starts_with("adp_"), adp_mandatory,
        inspections_guaranteed_minimum),
      \(x) if (dplyr::n() > 1L) sum(x, na.rm = TRUE) else x
    )) |>
    dplyr::slice(1L) |>
    dplyr::ungroup()

  # ── DDP-only rows: bring full metadata from ddp_annual_panel ─────────────
  ddp_meta <- ddp_annual_panel |>
    dplyr::filter(!is.na(canonical_id)) |>
    dplyr::select(
      canonical_id, fiscal_year,
      canonical_name, facility_city, facility_state,
      facility_address, facility_zip,
      facility_type_detailed, facility_type_wiki,
      detloc
    )

  # ── Join keys ────────────────────────────────────────────────────────────
  ice_keys <- ice |> dplyr::distinct(canonical_id, fiscal_year)
  ddp_keys <- ddp_join |> dplyr::distinct(canonical_id, fiscal_year)

  # ── Group 1: both ICE and DDP ─────────────────────────────────────────────
  both <- ice |>
    dplyr::inner_join(ddp_join, by = c("canonical_id", "fiscal_year")) |>
    dplyr::mutate(
      divergence  = abs(ice_adp - ddp_adp) / pmax(ice_adp, 1),
      data_source = dplyr::case_when(
        ice_adp == 0 & ddp_adp > 0          ~ "ice_ddp_diverge_high",
        divergence > threshold & ddp_adp > ice_adp ~ "ice_ddp_diverge_high",
        divergence > threshold & ice_adp > ddp_adp ~ "ice_ddp_diverge_low",
        TRUE                                 ~ "ice_ddp_agree"
      ),
      adp = ice_adp
    )

  # ── Group 2: ICE only (no DDP in this year) ───────────────────────────────
  ice_only <- ice |>
    dplyr::anti_join(ddp_keys, by = c("canonical_id", "fiscal_year")) |>
    dplyr::mutate(
      adp              = ice_adp,
      data_source      = "ice_only",
      ddp_adp          = NA_real_,
      divergence       = NA_real_,
      adp_male         = NA_real_,
      adp_female       = NA_real_,
      adp_crim         = NA_real_,
      adp_non_crim     = NA_real_,
      ddp_share_non_crim = NA_real_,
      share_female     = NA_real_,
      peak_population  = NA_integer_,
      peak_date        = as.Date(NA),
      n_days           = NA_integer_,
      partial_year     = NA
    )

  # ── Group 3: DDP only (facility absent from ICE annual stats) ────────────
  ddp_only <- ddp_join |>
    dplyr::anti_join(ice_keys, by = c("canonical_id", "fiscal_year")) |>
    dplyr::left_join(ddp_meta, by = c("canonical_id", "fiscal_year")) |>
    dplyr::mutate(
      adp              = ddp_adp,
      ice_adp          = NA_real_,
      divergence       = NA_real_,
      data_source      = "ddp_only",
      ice_source       = NA_character_,
      facility_name    = NA_character_,
      facility_aor     = NA_character_,
      facility_average_length_of_stay_alos = NA_real_,
      share_non_crim   = ddp_share_non_crim,
      share_no_threat  = NA_real_,
      adp_criminality_male_crim        = NA_real_,
      adp_criminality_male_non_crim    = NA_real_,
      adp_criminality_female_crim      = NA_real_,
      adp_criminality_female_non_crim  = NA_real_,
      adp_ice_threat_level_1           = NA_real_,
      adp_ice_threat_level_2           = NA_real_,
      adp_ice_threat_level_3           = NA_real_,
      adp_no_ice_threat_level          = NA_real_,
      adp_mandatory                    = NA_real_,
      inspections_guaranteed_minimum   = NA_real_,
      inspections_last_inspection_rating_final = NA_character_
    )

  # ── Combine and standardise column order ─────────────────────────────────
  result <- dplyr::bind_rows(both, ice_only, ddp_only) |>
    dplyr::select(
      # Identity
      fiscal_year, canonical_id, canonical_name,
      facility_name, facility_city, facility_state,
      facility_address, facility_zip,
      facility_type_detailed, facility_type_wiki,
      facility_aor, detloc,
      # Source flags
      data_source, ice_source, partial_year,
      # ADP — primary (ice where available, ddp otherwise)
      adp,
      # ADP comparison
      ice_adp, ddp_adp, divergence,
      # DDP-specific breakdowns
      peak_population, peak_date, n_days,
      adp_male, adp_female, share_female,
      adp_crim, adp_non_crim,
      # Shares (ice preferred, ddp fallback)
      share_non_crim, ddp_share_non_crim, share_no_threat,
      facility_average_length_of_stay_alos,
      # ICE classification breakdowns
      adp_criminality_male_crim, adp_criminality_male_non_crim,
      adp_criminality_female_crim, adp_criminality_female_non_crim,
      adp_ice_threat_level_1, adp_ice_threat_level_2,
      adp_ice_threat_level_3, adp_no_ice_threat_level,
      adp_mandatory,
      # Inspections
      inspections_guaranteed_minimum,
      inspections_last_inspection_rating_final
    ) |>
    dplyr::arrange(canonical_id, fiscal_year)

  # ── Report ────────────────────────────────────────────────────────────────
  sc <- result |> dplyr::count(data_source)
  .n <- function(x) {
    v <- sc$n[sc$data_source == x]
    if (length(v) == 0L) 0L else v
  }

  cli::cli_inform(c(
    "Expanded map panel: {nrow(result)} rows across {n_distinct(result$canonical_id)} facilities",
    "*" = "{(.n('ice_only'))} ice_only",
    "*" = "{(.n('ddp_only'))} ddp_only",
    "*" = "{(.n('ice_ddp_agree'))} ice_ddp_agree",
    "*" = "{(.n('ice_ddp_diverge_high'))} ice_ddp_diverge_high",
    "*" = "{(.n('ice_ddp_diverge_low'))} ice_ddp_diverge_low"
  ))

  result
}

# ── Export expanded map data ─────────────────────────────────────────────────

#' Export expanded map RDS files for deployment
#'
#' Writes three RDS files to `data/expanded-map-export/`. Run
#' `copy-data.sh` in the quarto-website post directory to deploy them.
#'
#' @return Character vector of written file paths (for `format = "file"`).
export_expanded_map_data <- function(expanded_map_panel, expanded_map_presence,
                                      expanded_map_geocoded) {
  export_dir <- here::here("data", "expanded-map-export")
  dir.create(export_dir, showWarnings = FALSE, recursive = TRUE)

  files <- c(
    file.path(export_dir, "expanded_panel.rds"),
    file.path(export_dir, "expanded_presence.rds"),
    file.path(export_dir, "expanded_geocoded.rds")
  )

  saveRDS(expanded_map_panel,    files[1])
  saveRDS(expanded_map_presence, files[2])
  saveRDS(expanded_map_geocoded, files[3])

  cli::cli_inform(c(
    "Expanded map export: {nrow(expanded_map_geocoded)} facilities",
    "*" = "{nrow(expanded_map_panel)} panel rows ({length(unique(expanded_map_panel$fiscal_year))} fiscal years)",
    "*" = "Written to {.path {export_dir}}"
  ))

  files
}
