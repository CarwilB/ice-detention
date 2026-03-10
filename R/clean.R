# Clean facility data: name standardization, type coercion, and patches.

# ── Facility name cleaning ───────────────────────────────────────────────────

clean_facility_names <- function(x) {
  x <- stringr::str_to_title(x)

  # Typos and truncations
  x <- stringr::str_replace_all(x, "Facili\\b", "Facility")
  x <- stringr::str_replace_all(x, "Processsing", "Processing")

  # Abbreviation expansions
  expansions <- c(
    "\\bDept\\.?\\b" = "Department",
    "\\bCtr\\.?\\b"  = "Center",
    "\\bCorr\\.?\\b" = "Correctional",
    "\\bInst\\.?\\b" = "Institution",
    "\\bFed\\.?\\b"  = "Federal",
    "\\bDet\\.?\\b"  = "Detention",
    "\\bFac\\.?\\b"  = "Facility",
    "\\bCo\\.?\\b"   = "County"
  )
  x <- stringr::str_replace_all(x, expansions)

  # Acronym restoration
  acronyms <- c(
    "\\bOf\\b" = "of",
    "\\bUs\\b" = "US",
    "\\bIce\\b" = "ICE",
    "\\bEro\\b" = "ERO",
    "\\bMdc\\b" = "MDC",
    "\\bCca\\b" = "CCA",
    "\\bFci\\b" = "FCI",
    "\\bFdc\\b" = "FDC",
    "\\bJtf\\b" = "JTF",
    "\\bSsm\\b" = "SSM",
    "\\bTgk\\b" = "TGK",
    "\\bIpc\\b" = "IPC",
    "\\bSpc\\b" = "SPC",
    "\\bIah\\b" = "IAH",
    "\\bClipc\\b" = "CLIPC",
    "\\bDigsa\\b" = "DIGSA",
    "\\bIgsa\\b"  = "IGSA"
  )
  x <- stringr::str_replace_all(x, acronyms)

  # State abbreviation expansions
  states <- c(
    "\\(Fl\\)" = "(Florida)",
    "\\(In\\)" = "(Indiana)",
    "\\(Mo\\)" = "(Missouri)",
    "\\(Mt\\)" = "(Montana)",
    "\\(Ne\\)" = "(Nebraska)",
    "\\(Ny\\)" = "(New York)",
    "\\(Tx\\)" = "(Texas)",
    "\\(Ut\\)" = "(Utah)",
    ", Nm\\b"  = ", New Mexico",
    ", Mt\\b"  = ", Montana"
  )
  x <- stringr::str_replace_all(x, states)

  # Facility-specific name fixes
  names_map <- c(
    "CCA, Florence Correctional Center" = "Central Arizona Florence Correctional Complex",
    "Eloy Federal Contract Facility" = "Eloy Detention Center",
    "T Don Hutto Detention Center" = "T. Don Hutto Detention Center",
    "Torrance/Estancia, New Mexico" = "Torrance County Detention Facility",
    "Houston Contract Detention Facility" = "Houston Processing Center",
    "Elizabeth Contract Detention Facility" = "Elizabeth Detention Center",
    "Folkston D Ray ICE Processing Center" = "Folkston ICE Processing Center",
    "Robert A Deyton Detention Facility" = "Robert A. Deyton Detention Center",
    "ERO El Paso Camp East Montana" = "Camp East Montana",
    "Port Isabel SPC" = "Port Isabel Detention Center",
    "Bluebonnet Detention Facility" = "Bluebonnet Detention Center"
  )
  x <- stringr::str_replace_all(x, names_map)

  x
}

# ── City name fixes ──────────────────────────────────────────────────────────

fix_city_names <- function(x) {
  x <- stringr::str_replace_all(x, "Ft.lauderdale", "Fort Lauderdale")
  x <- stringr::str_replace_all(x, "Ft. Lauderdale", "Fort Lauderdale")
  x <- stringr::str_replace_all(x, "Cottonwood Fall", "Cottonwood Falls")
  x <- stringr::str_replace_all(x, "Sault Ste Marie", "Sault Ste. Marie")
  x <- stringr::str_replace_all(x, "Bunkerhill", "Bunker Hill")
  x <- stringr::str_replace_all(x, "Mcelhattan", "McElhattan")
  x <- stringr::str_replace_all(x, "Mcfarland", "McFarland")
  x <- stringr::str_replace_all(x, "Mccook", "McCook")
  x <- stringr::str_replace_all(x, "Mccall", "McCall")
  x
}

# ── Main cleaning function ───────────────────────────────────────────────────

clean_facilities_data <- function(facilities_data) {
  numerical_columns <- c(
    "facility_average_length_of_stay_alos",
    "adp_detainee_classification_level_a",
    "adp_detainee_classification_level_b",
    "adp_detainee_classification_level_c",
    "adp_detainee_classification_level_d",
    "adp_criminality_male_crim",
    "adp_criminality_male_non_crim",
    "adp_criminality_female_crim",
    "adp_criminality_female_non_crim",
    "adp_ice_threat_level_1",
    "adp_ice_threat_level_2",
    "adp_ice_threat_level_3",
    "adp_no_ice_threat_level",
    "adp_mandatory",
    "inspections_guaranteed_minimum"
  )
  numerical_columns_present <- numerical_columns[numerical_columns %in% names(facilities_data)]

  facilities_data_clean <- facilities_data |>
    dplyr::mutate(
      dplyr::across(
        .cols = facility_average_length_of_stay_alos:adp_mandatory,
        .fns = ~ round(as.numeric(.), 1)
      ),
      inspections_guaranteed_minimum = as.integer(inspections_guaranteed_minimum),
      inspections_last_inspection_type = dplyr::case_when(
        inspections_last_inspection_type %in% c("PRE-OCCUPANCY", "Pre-Occupancy") ~ "PREOCC",
        TRUE ~ inspections_last_inspection_type
      ),
      facility_name = clean_facility_names(facility_name),
      facility_city = stringr::str_to_title(facility_city),
      facility_address = stringr::str_to_title(facility_address),
      facility_male_female = stringr::str_to_title(facility_male_female),
      facility_city = fix_city_names(facility_city),
      dplyr::across(
        .cols = -dplyr::all_of(numerical_columns_present),
        .fns = as.character
      )
    )

  # Guantanamo patch
  guantanamo_patch <- tibble::tibble(
    facility_name = "JTF Camp Six",
    facility_city = "Guantanamo Bay",
    facility_state = "Cuba",
    facility_address = "Bldg 2144, U.S. Naval Station Guantanamo Bay"
  )
  facilities_data_clean <- facilities_data_clean |>
    dplyr::rows_update(guantanamo_patch, by = "facility_name", unmatched = "ignore")

  facilities_data_clean
}

# ── Clean all years ──────────────────────────────────────────────────────────

clean_all_years <- function(facilities_data_list) {
  purrr::map(facilities_data_list, clean_facilities_data)
}
