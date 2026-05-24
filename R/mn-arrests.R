# R/mn-arrests.R
# Data builder for the Minnesota post-inauguration arrests analysis.
# Entry point: build_mn_arrests_data(arrests, stays, detloc_lookup, geo_all)

# ── County parsing ────────────────────────────────────────────────────────────

#' Parse Minnesota county name from apprehension_site_landmark field.
.parse_mn_county <- function(landmark) {
  dplyr::case_when(
    is.na(landmark)                                                   ~ NA_character_,
    stringr::str_detect(landmark, "DAKOTA COUNTY")                    ~ "Dakota",
    stringr::str_detect(landmark, "OLMSTED COUNTY|ROCHESTER")         ~ "Olmsted",
    stringr::str_detect(landmark, "STEARNS COUNTY")                   ~ "Stearns",
    stringr::str_detect(landmark, "SHERBURNE COUNTY")                 ~ "Sherburne",
    stringr::str_detect(landmark, "MOWER COUNTY")                     ~ "Mower",
    stringr::str_detect(landmark, "WASHINGTON COUNTY")                ~ "Washington",
    stringr::str_detect(landmark, "SCOTT COUNTY")                     ~ "Scott",
    stringr::str_detect(landmark, "RICE COUNTY|FARIBAULT")            ~ "Rice",
    stringr::str_detect(landmark, "TODD COUNTY")                      ~ "Todd",
    stringr::str_detect(landmark, "CROW WING")                        ~ "Crow Wing",
    stringr::str_detect(landmark, "SANDSTONE")                        ~ "Pine",
    stringr::str_detect(landmark, "FREEBORN")                         ~ "Freeborn",
    stringr::str_detect(landmark, "WASECA")                           ~ "Waseca",
    stringr::str_detect(landmark, "BLUE EARTH")                       ~ "Blue Earth",
    stringr::str_detect(landmark, "BLOOMINGTON|MINNEAPOLIS|HENNEPIN") ~ "Hennepin",
    stringr::str_detect(landmark, "US MARSHALS|SPM GENERAL|ST.? PAUL|WHIPPLE") ~ "Ramsey",
    TRUE                                                               ~ NA_character_
  )
}

# ── Sankey label helpers ──────────────────────────────────────────────────────

.label_first_fac <- function(code) {
  dplyr::case_when(
    code == "SPMHOLD" ~ "SPMHOLD\n(Bishop Whipple)",
    code == "SHERBMN" ~ "Sherburne\nCounty Jail",
    code == "FREEBMN" ~ "Freeborn\nCounty Jail",
    code == "KANDIMN" ~ "Kandiyohi\nCounty Jail",
    code == "DOUGLWI" ~ "Douglas Co. WI",
    code == "EROFCB"  ~ "ERO El Paso\nCamp Montana",
    TRUE              ~ "Other"
  )
}

.label_last_fac <- function(code) {
  dplyr::case_when(
    code == "EROFCB"  ~ "ERO El Paso\nCamp Montana",
    code == "SPMHOLD" ~ "SPMHOLD\n(final stop)",
    code == "JENATLA" ~ "Alexandria\nStaging Fac.",
    code == "PIC"     ~ "Port Isabel\nSPC",
    code == "PINEPLA" ~ "Pine Prairie\nProc. Ctr",
    code == "SHERBMN" ~ "Sherburne\nCounty Jail",
    code == "ADAMSMS" ~ "Adams County\nCorr. Ctr",
    code == "KRNRCTX" ~ "Karnes County\nProc. Ctr",
    TRUE              ~ "Other"
  )
}

.label_outcome <- function(reason) {
  dplyr::case_when(
    reason == "Removed" ~ "Removed",
    is.na(reason)       ~ "Pending / Unknown",
    TRUE                ~ "Released"
  )
}

# ── Geocoding lookup ──────────────────────────────────────────────────────────

.build_geo_lookup <- function(detloc_lookup, geo_all) {
  detloc_lookup |>
    dplyr::distinct(detloc, canonical_id) |>
    dplyr::inner_join(
      geo_all |>
        dplyr::select(canonical_id, canonical_name,
                      facility_city, facility_state, lat, lon),
      by = "canonical_id"
    ) |>
    dplyr::filter(!is.na(lat), !is.na(lon))
}

# ── Facility summary with geocoding ──────────────────────────────────────────

.fac_with_geo <- function(stays_df, code_col, name_col, geo_lkp) {
  stays_df |>
    dplyr::count(
      code     = .data[[code_col]],
      name_raw = .data[[name_col]]
    ) |>
    dplyr::left_join(geo_lkp, by = c("code" = "detloc")) |>
    dplyr::filter(!is.na(lat)) |>
    dplyr::arrange(dplyr::desc(n))
}

# ── Minors sub-analysis ───────────────────────────────────────────────────────

.build_minors <- function(mn_arr, stays, cutoff) {
  minor_arr <- mn_arr |>
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
    dplyr::filter(
      unique_identifier %in% minor_ids,
      as.Date(stay_book_in_date_time) >= cutoff
    )

  list(
    n_arrests   = nrow(minor_arr),
    n_persons   = length(minor_ids),
    n_stays     = nrow(minor_stays),
    age_dist    = minor_arr |>
      dplyr::count(age_at_arrest) |>
      dplyr::arrange(age_at_arrest),
    nationalities = minor_arr |>
      dplyr::count(citizenship_country, sort = TRUE) |>
      dplyr::mutate(pct = round(n / sum(n) * 100, 1)),
    arrest_type = minor_arr |>
      dplyr::count(apprehension_type, sort = TRUE) |>
      dplyr::mutate(pct = round(n / sum(n) * 100, 1)),
    criminality = minor_arr |>
      dplyr::count(apprehension_criminality, sort = TRUE) |>
      dplyr::mutate(pct = round(n / sum(n) * 100, 1)),
    first_fac   = minor_stays |>
      dplyr::count(
        code     = detention_facility_code_first,
        facility = detention_facility_first,
        sort     = TRUE
      ) |>
      dplyr::mutate(pct = round(n / sum(n) * 100, 1)),
    last_fac    = minor_stays |>
      dplyr::count(
        code     = detention_facility_code_last,
        facility = detention_facility_last,
        sort     = TRUE
      ) |>
      dplyr::mutate(pct = round(n / sum(n) * 100, 1)),
    outcomes    = minor_stays |>
      dplyr::count(stay_release_reason, sort = TRUE) |>
      dplyr::mutate(pct = round(n / sum(n) * 100, 1))
  )
}

# ── Main entry point ──────────────────────────────────────────────────────────

#' Build all data for the mn-arrests.qmd report.
#'
#' @param arrests        Raw arrests tibble (arrests_raw target).
#' @param stays          Raw stays tibble (stays_raw target).
#' @param detloc_lookup  Full DETLOC → canonical_id lookup (detloc_lookup_complete).
#' @param geo_all        Geocoded facility data (read from facilities-geocoded-all.csv).
#' @param cutoff         Inauguration date split (default 2025-01-20).
#' @return Named list of pre-computed tables ready for the QMD.
build_mn_arrests_data <- function(arrests, stays, detloc_lookup, geo_all,
                                   cutoff = as.Date("2025-01-20")) {

  # Filter arrests to MN, post-inauguration, deduplicated
  mn_arr <- arrests |>
    dplyr::filter(
      apprehension_state == "MINNESOTA",
      apprehension_date  >= cutoff,
      duplicate_likely   == FALSE | is.na(duplicate_likely)
    )

  mn_ids <- mn_arr |>
    dplyr::filter(!is.na(unique_identifier)) |>
    dplyr::pull(unique_identifier) |>
    unique()

  # Stays for these persons that started on/after the cutoff
  mn_stays <- stays |>
    dplyr::filter(
      unique_identifier %in% mn_ids,
      as.Date(stay_book_in_date_time) >= cutoff
    )

  geo_lkp <- .build_geo_lookup(detloc_lookup, geo_all)

  # County arrest counts (for choropleth)
  county_counts <- mn_arr |>
    dplyr::mutate(county = .parse_mn_county(apprehension_site_landmark)) |>
    dplyr::count(county) |>
    dplyr::filter(!is.na(county)) |>
    dplyr::arrange(dplyr::desc(n))

  # All facilities appearing in itineraries
  all_facs <- mn_stays |>
    dplyr::mutate(codes = stringr::str_split(detention_facility_codes_all, "; ")) |>
    tidyr::unnest(codes) |>
    dplyr::count(codes, sort = TRUE) |>
    dplyr::mutate(pct_of_stays = round(n / nrow(mn_stays) * 100, 1))

  # Sankey flow data
  sankey_data <- mn_stays |>
    dplyr::mutate(
      stage1        = "MN Arrest",
      first_label   = .label_first_fac(detention_facility_code_first),
      last_label    = .label_last_fac(detention_facility_code_last),
      outcome_label = .label_outcome(stay_release_reason)
    ) |>
    dplyr::count(stage1, first_label, last_label, outcome_label, name = "n")

  list(
    cutoff       = cutoff,
    n_arrests    = nrow(mn_arr),
    n_persons    = length(mn_ids),
    n_stays      = nrow(mn_stays),
    monthly_vol  = mn_arr |>
      dplyr::mutate(month = format(apprehension_date, "%Y-%m")) |>
      dplyr::count(month),
    nationalities = mn_arr |>
      dplyr::count(citizenship_country, sort = TRUE) |>
      dplyr::mutate(pct = round(n / sum(n) * 100, 1)),
    arrest_type   = mn_arr |>
      dplyr::count(apprehension_type, sort = TRUE) |>
      dplyr::mutate(pct = round(n / sum(n) * 100, 1)),
    criminality   = mn_arr |>
      dplyr::count(apprehension_criminality, sort = TRUE) |>
      dplyr::mutate(pct = round(n / sum(n) * 100, 1)),
    county_counts = county_counts,
    first_fac     = .fac_with_geo(mn_stays, "detention_facility_code_first",
                                   "detention_facility_first", geo_lkp),
    last_fac      = .fac_with_geo(mn_stays, "detention_facility_code_last",
                                   "detention_facility_last", geo_lkp),
    sankey_data   = sankey_data,
    all_facs      = all_facs,
    outcomes      = mn_stays |>
      dplyr::count(stay_release_reason, sort = TRUE) |>
      dplyr::mutate(pct = round(n / sum(n) * 100, 1)),
    minors        = .build_minors(mn_arr, stays, cutoff)
  )
}
