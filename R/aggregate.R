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

# Combined classification: uses facility_type_detailed when available
# (including ICE panel codes and hold facility internal codes), then falls
# back to vera_type_corrected for facilities that only have Vera metadata.
# Name-based overrides resolve ICE "Other" facilities where possible.
# Suitable for the full roster across all ID ranges.
classify_facility_type_combined <- function(facility_type_detailed,
                                            vera_type_corrected,
                                            facility_name = NULL) {
  # Primary: ICE panel codes + hold facility internal codes
  from_type <- dplyr::case_when(
    # ── ICE panel codes ──
    facility_type_detailed == "IGSA"           ~ "Jail",
    facility_type_detailed == "USMS IGA"       ~ "Jail",
    facility_type_detailed == "DIGSA"          ~ "Dedicated Migrant Detention Center",
    facility_type_detailed == "STATE"          ~ "State Migrant Detention Center",
    facility_type_detailed == "BOP"            ~ "Federal Prison",
    facility_type_detailed == "FAMILY"         ~ "Family Detention Center",
    # FAMILY STAGING: Hotel if name is in known hotel list, else Family
    facility_type_detailed == "FAMILY STAGING" &
      !is.null(facility_name) &
      facility_name %in% .family_staging_hotels          ~ "Hotel",
    facility_type_detailed == "FAMILY STAGING"            ~ "Family Detention Center",
    facility_type_detailed == "JUVENILE"       ~ "Juvenile Detention Center",
    facility_type_detailed == "CDF"            ~ "Private Migrant Detention Center",
    facility_type_detailed == "USMS CDF"       ~ "Private Migrant Detention Center",
    facility_type_detailed == "SPC"            ~ "ICE Migrant Detention Center",
    facility_type_detailed == "STAGING"        ~ "ICE Staging Facility",
    facility_type_detailed == "DOD"            ~ "Military Detention Center",
    facility_type_detailed == "TAP-ICE"        ~ "Family Detention Center",
    # ── Hold facility internal codes ──
    facility_type_detailed == "hold_room"      ~ "ICE Hold Room",
    facility_type_detailed == "ero_hold"       ~ "ICE ERO Hold Room",
    facility_type_detailed == "sub_office"     ~ "ICE ERO Sub-Office",
    facility_type_detailed == "custody_case"   ~ "ICE Custody/Case Facility",
    facility_type_detailed == "staging"        ~ "ICE Staging Facility",
    facility_type_detailed == "cbp"            ~ "CBP Hold Facility",
    facility_type_detailed == "command_center" ~ "ICE Command Center",
    facility_type_detailed == "ero_office"     ~ "ICE ERO Field Office",
    TRUE                                       ~ NA_character_
  )
  # Name-based overrides for ICE "Other" facilities
  from_name <- if (!is.null(facility_name)) {
    dplyr::if_else(
      is.na(from_type) & facility_name %in% names(.other_type_overrides),
      .other_type_overrides[facility_name],
      NA_character_
    )
  } else {
    NA_character_
  }
  # Fallback: Vera category → wiki type
  from_vera <- dplyr::case_when(
    vera_type_corrected == "Non-Dedicated" ~ "Jail",
    vera_type_corrected == "Dedicated"     ~ "Private Migrant Detention Center",
    vera_type_corrected == "Federal"       ~ "Federal Prison",
    vera_type_corrected == "Family/Youth"  ~ "Family Detention Center",
    vera_type_corrected == "Medical"       ~ "Medical Facility",
    vera_type_corrected == "Hotel"         ~ "Hotel",
    vera_type_corrected == "Hold/Staging"  ~ "ICE Hold Room",
    vera_type_corrected == "Other/Unknown" ~ "Other",
    TRUE                                   ~ NA_character_
  )
  dplyr::coalesce(from_type, from_name, from_vera, "Other")
}

# Shared classification: maps facility_type_detailed → readable wiki type.
# Used by aggregate_facilities_data() and merge_keyed_lists().
classify_facility_type <- function(facility_type_detailed, .verbose=FALSE) {
  result <- dplyr::case_when(
    facility_type_detailed == "IGSA"           ~ "Jail",
    facility_type_detailed == "USMS IGA"       ~ "Jail",
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
