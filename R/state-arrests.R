# R/state-arrests.R
# Parameterized data builder for the state-arrests.qmd report.
# Entry point: build_state_arrests_data(arrests, stays, detloc_lookup, geo_all,
#                                        state = "MINNESOTA", cutoff = "2025-01-20")

# ── State abbreviation lookup ─────────────────────────────────────────────────
# Maps uppercase state names (as they appear in arrests$apprehension_state)
# to lowercase 2-letter abbreviations used in page URLs.
STATE_ABBREVS <- c(
  "ALABAMA" = "al", "ALASKA" = "ak", "ARIZONA" = "az", "ARKANSAS" = "ar",
  "CALIFORNIA" = "ca", "COLORADO" = "co", "CONNECTICUT" = "ct",
  "DELAWARE" = "de", "DISTRICT OF COLUMBIA" = "dc", "FLORIDA" = "fl",
  "GEORGIA" = "ga", "HAWAII" = "hi", "IDAHO" = "id", "ILLINOIS" = "il",
  "INDIANA" = "in", "IOWA" = "ia", "KANSAS" = "ks", "KENTUCKY" = "ky",
  "LOUISIANA" = "la", "MAINE" = "me", "MARYLAND" = "md",
  "MASSACHUSETTS" = "ma", "MICHIGAN" = "mi", "MINNESOTA" = "mn",
  "MISSISSIPPI" = "ms", "MISSOURI" = "mo", "MONTANA" = "mt",
  "NEBRASKA" = "ne", "NEVADA" = "nv", "NEW HAMPSHIRE" = "nh",
  "NEW JERSEY" = "nj", "NEW MEXICO" = "nm", "NEW YORK" = "ny",
  "NORTH CAROLINA" = "nc", "NORTH DAKOTA" = "nd", "OHIO" = "oh",
  "OKLAHOMA" = "ok", "OREGON" = "or", "PENNSYLVANIA" = "pa",
  "RHODE ISLAND" = "ri", "SOUTH CAROLINA" = "sc", "SOUTH DAKOTA" = "sd",
  "TENNESSEE" = "tn", "TEXAS" = "tx", "UTAH" = "ut", "VERMONT" = "vt",
  "VIRGINIA" = "va", "WASHINGTON" = "wa", "WEST VIRGINIA" = "wv",
  "WISCONSIN" = "wi", "WYOMING" = "wy"
)

# ── County name parsing ───────────────────────────────────────────────────────

#' Extract county name from apprehension_site_landmark.
#' Uses a regex for the general "XXXXX COUNTY" pattern, plus state-specific
#' augmentations for states with large non-specific landmark categories.
.parse_county_landmark <- function(landmark, state_upper = NULL) {
  general <- stringr::str_to_title(
    stringr::str_remove(
      stringr::str_extract(stringr::str_to_upper(landmark),
                           "^([A-Z .'-]+) COUNTY"),
      " COUNTY$"
    )
  )

  if (!is.null(state_upper) && state_upper == "MINNESOTA") {
    dplyr::case_when(
      stringr::str_detect(landmark, "SPM GENERAL|ST\\.? PAUL|US MARSHALS, MN|WHIPPLE") ~ "Ramsey",
      stringr::str_detect(landmark, "BLOOMINGTON|MINNEAPOLIS|HENNEPIN")                ~ "Hennepin",
      !is.na(general)                                                                  ~ general,
      TRUE                                                                             ~ NA_character_
    )
  } else {
    general
  }
}

# ── Geocoding lookup ──────────────────────────────────────────────────────────

.build_geo_lookup_sa <- function(detloc_lookup, geo_all) {
  # detloc_lookup_complete may have multiple canonical_ids per detloc (different
  # sources: DDP > DMCP > hold/ERO). distinct(detloc, canonical_id) preserves
  # those duplicate detloc rows, which then produce many-to-many warnings in
  # downstream joins where the same detloc appears on multiple flow pairs.
  # We need exactly one row per detloc — keep whichever canonical_id comes first
  # (highest-priority source order is already set in detloc_lookup_complete).
  detloc_lookup |>
    dplyr::distinct(detloc, canonical_id) |>
    dplyr::inner_join(
      geo_all |>
        dplyr::select(canonical_id, canonical_name,
                      facility_city, facility_state, lat, lon),
      by = "canonical_id"
    ) |>
    dplyr::filter(!is.na(lat), !is.na(lon)) |>
    dplyr::distinct(detloc, .keep_all = TRUE)   # one row per DETLOC
}

# ── Flow arrows (consecutive facility transfers) ──────────────────────────────

#' Build a tibble of facility-to-facility transfer flows, with geocoding.
#' Returns one row per (from, to) pair with n transfers, lat/lon endpoints,
#' and a log-scaled line weight for leaflet rendering.
#'
#' @param stays_df  Stays data frame filtered to the state of interest.
#' @param geo_lkp   Output of .build_geo_lookup_sa().
#' @param min_n     Minimum transfers to include a flow (default 5).
build_flow_arrows <- function(stays_df, geo_lkp, min_n = 5) {
  pairs <- stays_df |>
    dplyr::filter(n_stints > 1) |>
    dplyr::mutate(codes = stringr::str_split(detention_facility_codes_all, "; ")) |>
    dplyr::select(codes) |>
    dplyr::mutate(
      from = purrr::map(codes, utils::head, -1),
      to   = purrr::map(codes, utils::tail, -1)
    ) |>
    dplyr::select(-codes) |>
    tidyr::unnest(c(from, to)) |>
    dplyr::filter(from != to) |>
    dplyr::count(from, to, sort = TRUE) |>
    dplyr::filter(n >= min_n)

  pairs |>
    dplyr::left_join(
      geo_lkp |> dplyr::select(detloc, from_name = canonical_name,
                                 from_city = facility_city, from_state = facility_state,
                                 from_lat = lat, from_lon = lon),
      by = c("from" = "detloc")
    ) |>
    dplyr::left_join(
      geo_lkp |> dplyr::select(detloc, to_name = canonical_name,
                                 to_city = facility_city, to_state = facility_state,
                                 to_lat = lat, to_lon = lon),
      by = c("to" = "detloc")
    ) |>
    dplyr::filter(!is.na(from_lat), !is.na(to_lat)) |>
    dplyr::mutate(
      weight = pmax(1, pmin(10, log2(n + 1) * 1.5)),
      label  = paste0(
        "<b>", from, " \u2192 ", to, "</b><br>",
        from_name, "<br>\u2192 ", to_name, "<br>",
        "<b>", format(n, big.mark = ","), "</b> transfers"
      )
    )
}

# ── Facility summary with geocoding ──────────────────────────────────────────

.fac_with_geo_sa <- function(stays_df, code_col, name_col, geo_lkp) {
  stays_df |>
    dplyr::count(code     = .data[[code_col]],
                 name_raw = .data[[name_col]]) |>
    dplyr::left_join(geo_lkp, by = c("code" = "detloc")) |>
    dplyr::filter(!is.na(lat)) |>
    dplyr::arrange(dplyr::desc(n))
}

# ── Sankey label helpers ──────────────────────────────────────────────────────

.label_first_fac_sa <- function(code, top_codes) {
  dplyr::if_else(code %in% top_codes, code, "Other")
}

.label_last_fac_sa <- function(code, top_codes) {
  dplyr::if_else(code %in% top_codes, code, "Other")
}

.label_outcome_sa <- function(reason) {
  dplyr::case_when(
    reason == "Removed" ~ "Removed",
    is.na(reason)       ~ "Pending / Unknown",
    TRUE                ~ "Released"
  )
}

# ── Minors sub-analysis ───────────────────────────────────────────────────────

.build_minors_sa <- function(state_arr, stays, cutoff) {
  minor_arr <- state_arr |>
    dplyr::filter(!is.na(birth_year)) |>
    dplyr::mutate(
      age_at_arrest = as.integer(format(apprehension_date, "%Y")) - birth_year
    ) |>
    dplyr::filter(age_at_arrest < 18)

  minor_ids <- minor_arr |>
    dplyr::filter(!is.na(unique_identifier)) |>
    dplyr::pull(unique_identifier) |>
    unique()

  minor_stays <- stays |>
    dplyr::filter(unique_identifier %in% minor_ids,
                  as.Date(stay_book_in_date_time) >= cutoff)

  list(
    n_arrests     = nrow(minor_arr),
    n_persons     = length(minor_ids),
    n_stays       = nrow(minor_stays),
    age_dist      = minor_arr |>
      dplyr::mutate(age = as.integer(format(apprehension_date, "%Y")) - birth_year) |>
      dplyr::count(age) |>
      dplyr::arrange(age),
    nationalities = minor_arr |>
      dplyr::count(citizenship_country, sort = TRUE) |>
      dplyr::mutate(pct = round(n / sum(n) * 100, 1)),
    arrest_type   = minor_arr |>
      dplyr::count(apprehension_type, sort = TRUE) |>
      dplyr::mutate(pct = round(n / sum(n) * 100, 1)),
    criminality   = minor_arr |>
      dplyr::count(apprehension_criminality, sort = TRUE) |>
      dplyr::mutate(pct = round(n / sum(n) * 100, 1)),
    first_fac     = minor_stays |>
      dplyr::count(code     = detention_facility_code_first,
                   facility = detention_facility_first, sort = TRUE) |>
      dplyr::mutate(pct = round(n / sum(n) * 100, 1)),
    last_fac      = minor_stays |>
      dplyr::count(code     = detention_facility_code_last,
                   facility = detention_facility_last, sort = TRUE) |>
      dplyr::mutate(pct = round(n / sum(n) * 100, 1)),
    outcomes      = minor_stays |>
      dplyr::count(stay_release_reason, sort = TRUE) |>
      dplyr::mutate(pct = round(n / sum(n) * 100, 1))
  )
}

# ── Main entry point ──────────────────────────────────────────────────────────

#' Build all data for state-arrests.qmd.
#'
#' @param arrests       Raw arrests tibble (arrests_raw target).
#' @param stays         Raw stays tibble (stays_raw target).
#' @param detloc_lookup Full DETLOC → canonical_id lookup (detloc_lookup_complete).
#' @param geo_all       Geocoded facility data (facilities-geocoded-all.csv).
#' @param state         Uppercase state name, e.g. "MINNESOTA".
#' @param cutoff        Analysis start date (default 2025-01-20).
#' @return Named list of tables and flow data for the QMD.
build_state_arrests_data <- function(arrests, stays, detloc_lookup, geo_all,
                                      state  = "MINNESOTA",
                                      cutoff = as.Date("2025-01-20")) {
  cutoff <- as.Date(cutoff)

  state_arr <- arrests |>
    dplyr::filter(
      apprehension_state == state,
      apprehension_date  >= cutoff,
      duplicate_likely   == FALSE | is.na(duplicate_likely)
    )

  state_ids <- state_arr |>
    dplyr::filter(!is.na(unique_identifier)) |>
    dplyr::pull(unique_identifier) |>
    unique()

  state_stays <- stays |>
    dplyr::filter(unique_identifier %in% state_ids,
                  as.Date(stay_book_in_date_time) >= cutoff)

  geo_lkp <- .build_geo_lookup_sa(detloc_lookup, geo_all)

  # County counts for choropleth
  county_counts <- state_arr |>
    dplyr::mutate(county = .parse_county_landmark(apprehension_site_landmark, state)) |>
    dplyr::count(county) |>
    dplyr::filter(!is.na(county)) |>
    dplyr::arrange(dplyr::desc(n))

  # Facility transfer flow arrows
  flow_arrows <- build_flow_arrows(state_stays, geo_lkp,
                                    min_n = max(5L, as.integer(nrow(state_stays) * 0.001)))

  # Sankey: top-6 first and last facilities by volume
  top_first <- dplyr::count(state_stays, detention_facility_code_first, sort = TRUE) |>
    utils::head(6) |> dplyr::pull(detention_facility_code_first)
  top_last  <- dplyr::count(state_stays, detention_facility_code_last,  sort = TRUE) |>
    utils::head(7) |> dplyr::pull(detention_facility_code_last)

  sankey_data <- state_stays |>
    dplyr::mutate(
      stage1        = paste0(stringr::str_to_title(stringr::str_to_lower(state)), " Arrest"),
      first_label   = dplyr::if_else(
        detention_facility_code_first %in% top_first,
        detention_facility_code_first, "Other"),
      last_label    = dplyr::if_else(
        detention_facility_code_last %in% top_last,
        detention_facility_code_last, "Other"),
      outcome_label = .label_outcome_sa(stay_release_reason)
    ) |>
    dplyr::count(stage1, first_label, last_label, outcome_label, name = "n")

  # Departure countries for removed stays
  removal_countries <- state_stays |>
    dplyr::filter(stay_release_reason == "Removed", !is.na(departure_country)) |>
    dplyr::count(departure_country, sort = TRUE) |>
    dplyr::mutate(pct = round(n / sum(n) * 100, 1))

  # All facilities in itineraries
  all_facs <- state_stays |>
    dplyr::mutate(codes = stringr::str_split(detention_facility_codes_all, "; ")) |>
    tidyr::unnest(codes) |>
    dplyr::count(codes, sort = TRUE) |>
    dplyr::mutate(pct_of_stays = round(n / nrow(state_stays) * 100, 1))

  # Top apprehension_site_landmark values (fallback when county coverage is low)
  landmark_counts <- state_arr |>
    dplyr::filter(!is.na(apprehension_site_landmark)) |>
    dplyr::count(apprehension_site_landmark, sort = TRUE) |>
    dplyr::mutate(pct = round(n / sum(n) * 100, 1))

  # Citizenship × removal destination heatmap data
  # stays_raw already carries citizenship_country as a person-level field
  removal_heatmap <- state_stays |>
    dplyr::filter(
      stay_release_reason == "Removed",
      !is.na(departure_country),
      !is.na(citizenship_country)
    ) |>
    dplyr::count(departure_country, citizenship_country) |>
    dplyr::group_by(departure_country) |>
    dplyr::mutate(row_pct = round(n / sum(n) * 100, 1)) |>
    dplyr::ungroup()

  list(
    state              = state,
    cutoff             = cutoff,
    n_arrests          = nrow(state_arr),
    n_persons          = length(state_ids),
    n_stays            = nrow(state_stays),
    monthly_vol        = state_arr |>
      dplyr::mutate(month = format(apprehension_date, "%Y-%m")) |>
      dplyr::count(month),
    nationalities      = state_arr |>
      dplyr::count(citizenship_country, sort = TRUE) |>
      dplyr::mutate(pct = round(n / sum(n) * 100, 1)),
    arrest_type        = state_arr |>
      dplyr::count(apprehension_type, sort = TRUE) |>
      dplyr::mutate(pct = round(n / sum(n) * 100, 1)),
    criminality        = state_arr |>
      dplyr::count(apprehension_criminality, sort = TRUE) |>
      dplyr::mutate(pct = round(n / sum(n) * 100, 1)),
    county_counts      = county_counts,
    first_fac          = .fac_with_geo_sa(state_stays, "detention_facility_code_first",
                                           "detention_facility_first", geo_lkp),
    last_fac           = .fac_with_geo_sa(state_stays, "detention_facility_code_last",
                                           "detention_facility_last", geo_lkp),
    flow_arrows        = flow_arrows,
    sankey_data        = sankey_data,
    top_first          = top_first,
    top_last           = top_last,
    all_facs           = all_facs,
    outcomes           = state_stays |>
      dplyr::count(stay_release_reason, sort = TRUE) |>
      dplyr::mutate(pct = round(n / sum(n) * 100, 1)),
    removal_countries  = removal_countries,
    removal_heatmap    = removal_heatmap,
    landmark_counts    = landmark_counts,
    minors             = .build_minors_sa(state_arr, stays, cutoff)
  )
}
