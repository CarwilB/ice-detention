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
    "\\bCo\\.?\\b"   = "County",
    "\\bTex Health Huguley Hosp\\b" = "Texas Health Huguley Hospital"
  )
  x <- stringr::str_replace_all(x, expansions)

  # Acronym restoration
  acronyms <- c(
    "\\bOf\\b" = "of",
    "\\bUs\\b" = "US",
    "\\bIce\\b" = "ICE",
    "\\bEro\\b" = "ERO",
    "\\bMdc\\b" = "MDC",
    "\\bCbp\\b" = "CBP",
    "\\bBps\\b" = "BPS",
    "\\bCca\\b" = "CCA",
    "\\bFci\\b" = "FCI",
    "\\bFdc\\b" = "FDC",
    "\\bFsc\\b" = "FSC",
    "\\bJtf\\b" = "JTF",
    "\\bNdr\\b" = "NDR", # one-time acronym for "New Day Resiliency" Center
    "\\bPoe\\b" = "POE",
    "\\bSsm\\b" = "SSM",
    "\\bSna\\b" = "SNA",
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
    "Berlin Federal. Correctional. Institution." = "Berlin Federal Correctional Institution",
    "Burleigh County" = "Burleigh County Detention Center",
    "ERO El Paso Camp East Montana" = "Camp East Montana",
    "Port Isabel SPC" = "Port Isabel Detention Center",
    "Bluebonnet Detention Facility" = "Bluebonnet Detention Center",
    "Berlin Federal. Correctional. Institution." = "Berlin Federal Correctional Institution"
  )
  x <- stringr::str_replace_all(x, names_map)

  x
}

# ── City name fixes ──────────────────────────────────────────────────────────

fix_city_names <- function(x) {
  x <- stringr::str_replace_all(x, "Ft.lauderdale", "Fort Lauderdale")
  x <- stringr::str_replace_all(x, "Ft. Lauderdale", "Fort Lauderdale")
  x <- stringr::str_replace_all(x, "Cottonwood Fall\\b", "Cottonwood Falls")
  x <- stringr::str_replace_all(x, "Sault Ste Marie", "Sault Ste. Marie")
  x <- stringr::str_replace_all(x, "Bunkerhill", "Bunker Hill")
  x <- stringr::str_replace_all(x, "Mcelhattan", "McElhattan")
  x <- stringr::str_replace_all(x, "Mcfarland", "McFarland")
  x <- stringr::str_replace_all(x, "Mccook", "McCook")
  x <- stringr::str_replace_all(x, "Mccall", "McCall")
  # DMCP source corrections
  x <- stringr::str_replace_all(x, "^Kearney$", "Kearny")       # NJ city; misspelled in faclist15 XLSX
  x <- stringr::str_replace_all(x, "^Colorado Spring$", "Colorado Springs")  # truncated in faclist15 XLSX
  x
}

# —— Address fixes ──────────────────────────────────────────────────────────

clean_addresses <- function(x) {
  x <- stringr::str_to_title(x)
  x <- stringr::str_replace_all(x, "\\bNe\\b", "NE")
  x <- stringr::str_replace_all(x, "\\bNw\\b", "NW")
  x <- stringr::str_replace_all(x, "\\bSe\\b", "SE")
  x <- stringr::str_replace_all(x, "\\bSw\\b", "SW")
  x
}

# ── Address patches ───────────────────────────────────────────────────────────
# Hand-maintained corrections for facility addresses that are missing, wrong,
# or contain non-address text in the ICE spreadsheets. Matched by facility_name
# via rows_update() in clean_facilities_data().

address_patches <- function() {
  dplyr::tribble(
    ~facility_name,                 ~facility_address,         ~facility_city,    ~facility_state, ~facility_zip,
    "JTF Camp Six",                 "Bldg 2144, U.S. Naval Station Guantanamo Bay", "Guantanamo Bay", "Cuba", "34009",
    "San Diego District Staging",   "880 Front Street",        "San Diego",       "CA",            "92101",
    "Burleigh County Detention Center", "4000 Apple Creek Road", "Bismarck",       "ND",            "58504",
    "Lincoln County Jail",          "302 N Jeffers",           "North Platte",    "NE",            "69101",
    "Otero County Detention",       "1958 Dr M.L.K. Jr. Dr",  "Alamogordo",      "NM",            "88310",
    "Winn Correctional Center",     "180 Cca Blvd",            "Winnfield",       "LA",            "71483",
    "East Hidalgo Detention Center", "1300 TX-107",             "La Villa",        "TX",            "78562"
  )
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
      facility_address = clean_addresses(facility_address),
      facility_male_female = stringr::str_to_title(facility_male_female),
      facility_city = fix_city_names(facility_city),
      dplyr::across(
        .cols = -dplyr::all_of(numerical_columns_present),
        .fns = as.character
      )
    )

  # Address patches — correct facility addresses that are missing, wrong, or

  # contain non-address text in the ICE spreadsheets.
  facilities_data_clean <- facilities_data_clean |>
    dplyr::rows_update(address_patches(), by = "facility_name", unmatched = "ignore")

  facilities_data_clean
}

# ── DMCP column renaming ─────────────────────────────────────────────────────
#
# Harmonizes column names for both DMCP listing sources to the project schema.
# Handles the 2015 XLSX (raw human-readable names with spaces) and the 2017 PDF
# (snake_case names from the PDF parser) with a single function.
#
# Call this immediately after import_faclist15() / import_faclist17(), before
# clean_dmcp_data().

rename_dmcp_columns <- function(df) {
  # Step 1: Normalize all names to snake_case (handles the xlsx source;
  # is a no-op for names already in snake_case from the PDF parser).
  df <- dplyr::rename_with(
    df,
    ~ tolower(.x) |>
      stringr::str_replace_all("[^a-z0-9]+", "_") |>
      stringr::str_remove_all("^_+|_+$")
  )

  # Step 2: Strip "best_known_" prefix present in the xlsx source.
  df <- dplyr::rename_with(
    df,
    ~ stringr::str_remove(.x, "^best_known_"),
    dplyr::any_of(c(
      "best_known_contract_initiation_date",
      "best_known_contract_expiration_date"
    ))
  )

  # Step 3: Unify the levels column name (xlsx produces "levels_a_b_c_d"
  # after snake_case conversion; pdf parser produces "levels").
  if ("levels_a_b_c_d" %in% names(df)) {
    df <- dplyr::rename(df, levels = levels_a_b_c_d)
  }

  # Step 4: Apply project schema prefixes and harmonized names.
  rename_map <- c(
    facility_name                            = "name",
    facility_address                         = "address",
    facility_city                            = "city",
    facility_county                          = "county",
    facility_state                           = "state",
    facility_zip                             = "zip",
    facility_type                            = "type",
    facility_type_detailed                   = "type_detailed",
    facility_male_female                     = "male_female",
    facility_levels                          = "levels",
    facility_capacity                        = "capacity",
    facility_population_count               = "population_count",
    inspections_last_inspection_type         = "last_inspection_type",
    inspections_last_inspection_standard     = "last_inspection_standard",
    inspections_last_inspection_rating_final = "last_inspection_rating_final",
    inspections_last_inspection_date         = "last_inspection_date"
  )

  dplyr::rename(df, dplyr::any_of(rename_map))
}

# ── DMCP data cleaning ────────────────────────────────────────────────────────
#
# Applies facility/city name standardization and numeric type coercion to a
# DMCP listing that has already been through rename_dmcp_columns().
# Reuses clean_facility_names() and fix_city_names() from this file.

#' Repair digit-bleed misalignment in fl17 PDF-parsed columns
#'
#' The 2017 PDF column boundaries are slightly too narrow, causing the last
#' digit of each date field to bleed into the next column. Two bleed zones:
#'
#' Zone 1: contract_initiation_date → contract_expiration_date → per_diem_rate_detailed
#' Zone 2: inspections_last_inspection_date → cy16_rating
#'
#' After reassembling truncated dates, converts date columns to Date type.
#' Safe to call on fl15 data (returns unchanged if the columns are absent or
#' already well-formed).
repair_fl17_date_bleed <- function(df) {
  # Helper: reassemble a bleed pair. Returns df with `left` completed and

  # `right` stripped of its leading bleed digit.
  fix_bleed_pair <- function(df, left, right) {
    if (!all(c(left, right) %in% names(df))) return(df)

    bleed <- stringr::str_extract(df[[right]], "^\\d(?=\\s|$)")

    # Append bleed digit to truncated column on the left
    df[[left]] <- dplyr::if_else(
      !is.na(bleed) & df[[left]] != "",
      paste0(df[[left]], bleed),
      df[[left]]
    )

    # Strip bleed from right column
    df[[right]] <- dplyr::case_when(
      !is.na(bleed) & stringr::str_detect(df[[right]], "^\\d\\s+\\S") ~
        stringr::str_remove(df[[right]], "^\\d\\s+"),
      !is.na(bleed) ~ "",
      TRUE ~ df[[right]]
    )

    df
  }

  # Zone 1: contract dates + per diem
  df <- fix_bleed_pair(df, "contract_initiation_date", "contract_expiration_date")
  df <- fix_bleed_pair(df, "contract_expiration_date", "per_diem_rate_detailed")

  # Zone 2: inspection date + cy16 rating
  df <- fix_bleed_pair(df, "inspections_last_inspection_date", "cy16_rating")

  # Convert date columns to Date type
  date_cols <- intersect(
    c("contract_initiation_date", "contract_expiration_date",
      "inspections_last_inspection_date"),
    names(df)
  )
  for (col in date_cols) {
    df[[col]] <- as.Date(
      dplyr::if_else(df[[col]] == "", NA_character_, df[[col]]),
      format = "%m/%d/%Y"
    )
  }

  df
}


clean_dmcp_data <- function(df) {
  # ADP columns arrive as numeric (xlsx, already parsed by readxl) or as
  # character strings with commas (pdf). This helper handles both.
  parse_adp <- function(x) {
    if (is.numeric(x)) return(round(x, 1))
    as.numeric(stringr::str_remove_all(as.character(x), ","))
  }

  adp_cols <- dplyr::intersect(
    names(df),
    c("fy17_adp", "fy16_adp", "fy15_adp", "fy14_adp",
      "fy13_adp", "fy12_adp", "fy11_adp", "fy10_adp",
      "facility_population_count")
  )

  df |>
    dplyr::mutate(
      dplyr::across(dplyr::all_of(adp_cols), parse_adp),
      facility_capacity_as_needed = grepl(
        "^as needed$", as.character(facility_capacity), ignore.case = TRUE
      ),
      facility_capacity = as.integer(
        dplyr::if_else(
          facility_capacity_as_needed,
          NA_character_,
          stringr::str_remove_all(as.character(facility_capacity), ",")
        )
      ),
      facility_name    = clean_facility_names(facility_name),
      facility_city    = stringr::str_to_title(facility_city),
      facility_address = stringr::str_to_title(facility_address),
      facility_county  = stringr::str_to_title(facility_county),
      facility_city    = fix_city_names(facility_city),
      # PDF parsing artifact: county cell's final character(s) can bleed into
      # the state cell (e.g. "Y VA" from "ROCKINGHAM COUNTY"). Extract the
      # canonical 2-letter code from the tail of the string.
      facility_state   = stringr::str_extract(facility_state, "[A-Z]{2}$"),
      # Zero-pad ZIP codes to 5 digits. readxl parses numeric cells as
      # doubles, silently dropping leading zeros (e.g. 07001 → 7001).
      # The PDF parser produces character strings without this issue, but
      # as.integer() + str_pad handles both sources uniformly.
      facility_zip = stringr::str_pad(
        as.character(as.integer(facility_zip)), 5, side = "left", pad = "0"
      ),
      # Normalize whitespace in all remaining character columns
      dplyr::across(where(is.character), stringr::str_squish)
    ) |>
    dplyr::filter(!is.na(facility_city), !is.na(facility_state)) |>
    # Enforce canonical column order (any_of() silently drops absent cols,
    # so this works for both the 38-column FY15 and 40-column FY17 sources).
    dplyr::select(dplyr::any_of(.dmcp_col_order))
}

# Canonical DMCP column order. FY15 has 38 of these; FY17 adds fy17_adp
# and cy16_rating (40 total).
.dmcp_col_order <- c(
  "detloc", "facility_name", "facility_address", "facility_city",
  "facility_county", "facility_state", "facility_zip",
  "facility_type", "facility_type_detailed", "facility_male_female",
  "facility_levels", "facility_capacity", "facility_capacity_as_needed", "facility_population_count",
  "fy17_adp", "fy16_adp", "fy15_adp", "fy14_adp", "fy13_adp",
  "fy12_adp", "fy11_adp", "fy10_adp",
  "facility_operator", "facility_owner",
  "contract_initiation_date", "contract_expiration_date",
  "per_diem_rate_detailed", "authorizing_authority", "over_under_72",
  "inspections_last_inspection_type", "inspections_last_inspection_standard",
  "inspections_last_inspection_rating_final", "inspections_last_inspection_date",
  "cy16_rating", "cy15_rating", "cy14_rating", "cy13_rating",
  "cy12_rating", "cy11_rating", "cy10_rating", "dsm_assigned"
)

# ── Footnote extraction and saving ───────────────────────────────────────────
# Footnote/non-facility rows are identified before cleaning by the absence of
# facility_city and facility_state, which are always present for real rows.
# They are written to data/footnotes/{year}-footnotes.txt for reference.

save_year_footnotes <- function(raw_df, year_name) {
  footnotes <- raw_df[is.na(raw_df$facility_city) | is.na(raw_df$facility_state), ]
  if (nrow(footnotes) == 0) return(invisible(NULL))

  dir.create("data/footnotes", showWarnings = FALSE, recursive = TRUE)
  path <- file.path("data/footnotes", paste0(year_name, "-footnotes.txt"))

  lines <- c(
    paste("Non-facility rows extracted from", year_name, "spreadsheet"),
    paste("Extracted:", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    "",
    purrr::map_chr(seq_len(nrow(footnotes)), \(i) {
      name <- footnotes$facility_name[[i]]
      if (is.na(name)) "<empty row>" else name
    })
  )
  writeLines(lines, path)
  invisible(path)
}

# ── Clean all years ──────────────────────────────────────────────────────────

clean_all_years <- function(facilities_data_list) {
  purrr::imap(facilities_data_list, \(df, yr) {
    # Save any footnote rows from the raw data before cleaning garbles them
    save_year_footnotes(df, yr)
    # Drop footnote rows (no city/state), then clean
    df |>
      dplyr::filter(!is.na(facility_city), !is.na(facility_state)) |>
      clean_facilities_data()
  })
}
