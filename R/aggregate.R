# Aggregate facility data: row-level sums and derived classifications.

# Maps facility_type_detailed → Vera's 8-category grouping.
# Source: Table 2 of Vera Institute "ICE Detention Trends: Technical Appendix"
# (Smart & Lawrence, 2023). See data/vera-type-coding.yml for provenance.
# Three ICE codes not in Table 2 are extended: TAP-ICE → Family/Youth,
# FAMILY STAGING → Hotel, STATE → Dedicated.
classify_vera_category <- function(facility_type_detailed) {
  dplyr::case_when(
    # ── Table 2 exact mappings ──
    facility_type_detailed == "IGSA"     ~ "Non-Dedicated",
    facility_type_detailed == "DIGSA"    ~ "Dedicated",
    facility_type_detailed == "CDF"      ~ "Dedicated",
    facility_type_detailed == "SPC"      ~ "Dedicated",
    facility_type_detailed == "BOP"      ~ "Federal",
    facility_type_detailed == "USMS CDF" ~ "Federal",
    facility_type_detailed == "USMS IGA" ~ "Federal",
    facility_type_detailed == "DOD"      ~ "Federal",
    facility_type_detailed == "MOC"      ~ "Federal",
    facility_type_detailed == "STAGING"  ~ "Hold/Staging",
    stringr::str_detect(facility_type_detailed, "(?i)^hold") ~ "Hold/Staging",
    facility_type_detailed == "FAMILY"   ~ "Family/Youth",
    facility_type_detailed == "JUVENILE" ~ "Family/Youth",
    # ── Extensions beyond Table 2 ──
    facility_type_detailed == "TAP-ICE"        ~ "Family/Youth",
    facility_type_detailed == "FAMILY STAGING" ~ "Hotel",
    facility_type_detailed == "STATE"          ~ "Dedicated",
    TRUE                                       ~ "Other/Unknown"
  )
}

# Known hotel names among FAMILY STAGING facilities. FAMILY STAGING is
# classified as Hotel only when the facility name matches this list;
# unknown FAMILY STAGING facilities default to Family Detention Center.
.family_staging_hotels <- c(
  "Best Western-Casa De Estrella",
  "Comfort Suites-Casa Consuelo",
  "Holiday Inn Express-Casa De La Luz",
  "La Quinta-Wyndham-Casa De Paz",
  "Suites On Scottsdale-Casa De Alegría",
  "Wingate-Wyndham Casa Esperanza"
)

# Name-based overrides for facilities ICE codes as "Other". These are
# identifiable from their names but have no specific ICE type code.
.other_type_overrides <- c(
  "CBP Chula Vista BPS"            = "CBP Hold Facility",
  "CBP San Ysidro POE"             = "CBP Hold Facility",
  "Tornillo-Guadalupe POE"         = "ICE Short-Term Migrant Detention Center",
  "Sunny Glen Cld Home NDR Center" = "Juvenile Detention Center"
)

# Combined classification: maps facility type codes to human-readable wiki types.
#
# Resolution order:
#   1. facility_type_detailed — ICE panel codes + hold facility internal codes
#   2. facility_name — name-based overrides for ICE "Other" facilities
#   3. type_detailed_corrected — Vera-corrected detailed codes (same vocabulary
#      as tier 1; catches codes like county_jail, STATE, BOP from overrides)
#   4. type_grouped_corrected — Vera grouped category fallback
#
# All parameters accept vectors (for use inside dplyr::mutate). The column name
# parameters default to the roster's standard column names.
classify_facility_type_combined <- function(facility_type_detailed,
                                            type_grouped_corrected,
                                            facility_name = NULL,
                                            type_detailed_corrected = NULL) {
  # ── Tier 1: ICE panel codes + hold facility internal codes ──
  from_type <- .classify_detailed(facility_type_detailed, facility_name)

  # ── Tier 2: Name-based overrides for ICE "Other" facilities ──
  from_name <- if (!is.null(facility_name)) {
    dplyr::if_else(
      is.na(from_type) & facility_name %in% names(.other_type_overrides),
      .other_type_overrides[facility_name],
      NA_character_
    )
  } else {
    NA_character_
  }

  # ── Tier 3: Vera-corrected detailed codes ──
  # Same vocabulary as tier 1 (ICE codes + internal codes), applied to
  # type_detailed_corrected from Vera overrides.
  from_vera_detailed <- if (!is.null(type_detailed_corrected)) {
    .classify_detailed(type_detailed_corrected, facility_name)
  } else {
    NA_character_
  }

  # ── Tier 4: Vera grouped category fallback ──
  from_vera_grouped <- dplyr::case_when(
    type_grouped_corrected == "Non-Dedicated" ~ "Jail/Prison",
    type_grouped_corrected == "Dedicated"     ~ "Private Migrant Detention Center",
    type_grouped_corrected == "Federal"       ~ "Federal Prison",
    type_grouped_corrected == "Family/Youth"  ~ "Family Detention Center",
    type_grouped_corrected == "Medical"       ~ "Medical Facility",
    type_grouped_corrected == "Hotel"         ~ "Hotel",
    type_grouped_corrected == "Hold/Staging"  ~ "ICE Hold Room",
    type_grouped_corrected == "Other/Unknown" ~ "Other",
    TRUE                                      ~ NA_character_
  )
  dplyr::coalesce(from_type, from_name, from_vera_detailed, from_vera_grouped, "Other")
}

# Shared detailed-code → wiki-type mapping used by classify_facility_type_combined.
# Handles both ICE panel codes (uppercase) and internal project codes (lowercase).
.classify_detailed <- function(type_code, facility_name = NULL) {
  dplyr::case_when(
    # ── ICE panel codes ──
    type_code == "IGSA"           ~ "Jail/Prison",
    type_code == "USMS IGA"       ~ "Jail/Prison",
    type_code == "DIGSA"          ~ "Dedicated Migrant Detention Center",
    type_code == "STATE"          ~ "State Migrant Detention Center",
    type_code == "BOP"            ~ "Federal Prison",
    type_code == "FAMILY"         ~ "Family Detention Center",
    type_code == "FAMILY STAGING" &
      !is.null(facility_name) &
      facility_name %in% .family_staging_hotels ~ "Hotel",
    type_code == "FAMILY STAGING" ~ "Family Detention Center",
    type_code == "JUVENILE"       ~ "Juvenile Detention Center",
    type_code == "CDF"            ~ "Private Migrant Detention Center",
    type_code == "USMS CDF"       ~ "Private Migrant Detention Center",
    type_code == "SPC"            ~ "ICE Migrant Detention Center",
    type_code == "STAGING"        ~ "ICE Staging Facility",
    type_code == "DOD"            ~ "Military Detention Center",
    type_code == "TAP-ICE"        ~ "Family Detention Center",
    # ── Internal project codes ──
    type_code == "county_jail"    ~ "Jail/Prison",
    type_code == "state_prison"   ~ "State Prison",
    type_code == "hold_room"      ~ "ICE Hold Room",
    type_code == "ero_hold"       ~ "ICE ERO Hold Room",
    type_code == "sub_office"     ~ "ICE ERO Sub-Office",
    type_code == "custody_case"   ~ "ICE Custody/Case Facility",
    type_code == "staging"        ~ "ICE Staging Facility",
    type_code == "cbp"            ~ "CBP Hold Facility",
    type_code == "command_center" ~ "ICE Command Center",
    type_code == "ero_office"     ~ "ICE ERO Field Office",
    # ── Vera-only detailed codes ──
    type_code == "Hospital"       ~ "Medical Facility",
    type_code == "Juvenile"       ~ "Juvenile Detention Center",
    type_code == "Hotel"          ~ "Hotel",
    type_code == "Hold"           ~ "ICE Hold Room",
    type_code == "Staging"        ~ "ICE Staging Facility",
    type_code == "Family"         ~ "Family Detention Center",
    TRUE                          ~ NA_character_
  )
}

# Shared classification: maps facility_type_detailed → readable wiki type.
# Used by aggregate_facilities_data() and merge_keyed_lists().
classify_facility_type <- function(facility_type_detailed, .verbose=FALSE) {
  result <- dplyr::case_when(
    facility_type_detailed == "IGSA"           ~ "Jail/Prison",
    facility_type_detailed == "USMS IGA"       ~ "Jail/Prison",
    facility_type_detailed == "DIGSA"          ~ "Dedicated Migrant Detention Center",
    facility_type_detailed == "STATE"          ~ "State Migrant Detention Center",
    facility_type_detailed == "BOP"            ~ "Federal Prison",
    facility_type_detailed == "FAMILY"         ~ "Family Detention Center",
    facility_type_detailed == "FAMILY STAGING" ~ "Family Detention Center",
    facility_type_detailed == "JUVENILE"       ~ "Juvenile Detention Center",
    facility_type_detailed == "CDF"            ~ "Private Migrant Detention Center",
    facility_type_detailed == "USMS CDF"       ~ "Private Migrant Detention Center",
    facility_type_detailed == "SPC"            ~ "ICE Migrant Detention Center",
    facility_type_detailed == "STAGING"        ~ "ICE Short-Term Migrant Detention Center",
    facility_type_detailed == "DOD"            ~ "Military Detention Center",
    facility_type_detailed == "TAP-ICE"        ~ "Family Detention Center",
    TRUE ~ "Other"
  )
  if(.verbose){
    cat("Assigning facility_type_wiki classifications based on facility_type_detailed...\n")
    result |> forcats::fct_count() |> print(n = 20)
    # Assigned to other
    cat("Facilities classified as 'Other':\n")
    other_values <- facility_type_detailed[which(result == "Other")]
    other_values |> forcats::fct_count() |> print(n=30)
  }

  result
}

aggregate_facilities_data <- function(facilities_data) {
  facilities_data |>
    dplyr::mutate(
      sum_classification_levels = rowSums(
        dplyr::select(dplyr::pick(dplyr::everything()),
                      dplyr::starts_with("adp_detainee_classification_level_")),
        na.rm = TRUE
      ),
      sum_criminality_levels = rowSums(
        dplyr::select(dplyr::pick(dplyr::everything()),
                      dplyr::starts_with("adp_criminality_")),
        na.rm = TRUE
      ),
      sum_threat_levels = rowSums(
        dplyr::select(dplyr::pick(dplyr::everything()),
                      dplyr::starts_with("adp_ice_threat_level_") |
                        dplyr::starts_with("adp_no_ice_threat_level")),
        na.rm = TRUE
      )
    ) |>
    dplyr::mutate(
      share_non_crim = (adp_criminality_male_non_crim + adp_criminality_female_non_crim) /
        sum_criminality_levels,
      share_no_threat = adp_no_ice_threat_level / sum_threat_levels
    ) |>
    dplyr::mutate(
      facility_type_wiki = classify_facility_type(facility_type_detailed)
    )
}

aggregate_all_years <- function(facilities_data_list) {
  purrr::map(facilities_data_list, aggregate_facilities_data)
}
