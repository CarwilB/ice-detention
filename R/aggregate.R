# Aggregate facility data: row-level sums and derived classifications.

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
      facility_type_wiki = dplyr::case_when(
        stringr::str_detect(facility_type_detailed, "IGSA") ~ "Jail",
        stringr::str_detect(facility_type_detailed, "USMS IGA") ~ "Jail",
        stringr::str_detect(facility_type_detailed, "DIGSA") ~ "Dedicated Migrant Detention Center",
        stringr::str_detect(facility_type_detailed, "STATE") ~ "State Migrant Detention Center",
        stringr::str_detect(facility_type_detailed, "BOP") ~ "Federal Prison",
        stringr::str_detect(facility_type_detailed, "Family") ~ "Private Family Detention Center",
        stringr::str_detect(facility_type_detailed, "CDF") ~ "Private Migrant Detention Center",
        stringr::str_detect(facility_type_detailed, "USMS CDF") ~ "Private Migrant Detention Center",
        stringr::str_detect(facility_type_detailed, "SPC") ~ "ICE Migrant Detention Center",
        stringr::str_detect(facility_type_detailed, "STAGING") ~ "ICE Short-Term Migrant Detention Center",
        stringr::str_detect(facility_type_detailed, "DOD") ~ "Military Detention Center",
        TRUE ~ "Other"
      )
    )
}

aggregate_all_years <- function(facilities_data_list) {
  purrr::map(facilities_data_list, aggregate_facilities_data)
}
