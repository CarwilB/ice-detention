# themarshallproject-locations.R
# Supplemental import script for The Marshall Project detention facility
# locations dataset (1978–2017).
#
# Source: https://github.com/themarshallproject/dhs_immigration_detention
# File:   locations.csv (1,479 facilities with DETLOCs, addresses, AOR, dates)
#
# Download is manual (one-time); this script provides import and cleaning
# functions wired into the targets pipeline.

library(dplyr)
library(readr)
library(stringr)


#' Download The Marshall Project locations CSV
#'
#' Downloads the file from GitHub if not already present locally.
#' @param dest_path Local file path (default: data/themarshallproject_locations.csv)
#' @return The local file path (invisibly).
download_marshall_locations <- function(
    dest_path = here::here("data", "themarshallproject_locations.csv")) {
  if (!file.exists(dest_path)) {
    url <- paste0(
      "https://raw.githubusercontent.com/themarshallproject/",
      "dhs_immigration_detention/master/locations.csv"
    )
    download.file(url, dest_path, quiet = TRUE)
    message("Downloaded Marshall Project locations to ", dest_path)
  }
  dest_path
}


#' Import The Marshall Project locations CSV
#'
#' Reads the raw CSV and returns it with minimal transformation.
#' @param path File path to the CSV.
#' @return A tibble with 12 columns matching the raw file schema.
import_marshall_locations <- function(path) {
  readr::read_csv(path, show_col_types = FALSE)
}


#' Clean The Marshall Project locations data
#'
#' Standardizes column names to snake_case, parses dates from DD/MM/YYYY
#' strings, zero-pads ZIP codes, and trims whitespace from text fields.
#' @param df Raw tibble from `import_marshall_locations()`.
#' @return Cleaned tibble with standardized column names and types.
clean_marshall_locations <- function(df) {
  df |>
    rename(
      detloc         = DETLOC,
      facility_name  = Name,
      facility_address = Address,
      facility_city  = City,
      facility_county = County,
      facility_state = State,
      facility_zip   = Zip,
      aor            = AOR,
      date_last_use  = `Date of Last Use`,
      date_first_use = `Date of First Use`,
      lat            = Lat,
      lon            = Lng
    ) |>
    mutate(
      # Parse DD/MM/YY or DD/MM/YYYY date strings
      date_first_use = parse_marshall_date(date_first_use),
      date_last_use  = parse_marshall_date(date_last_use),
      # Zero-pad ZIP codes
      facility_zip = stringr::str_pad(
        as.character(facility_zip), width = 5, side = "left", pad = "0"
      ),
      # Fix encoding, then trim whitespace
      across(where(is.character), ~ trimws(iconv(.x, to = "UTF-8", sub = "")))
    )
}


#' Parse Marshall Project date strings
#'
#' Handles DD/MM/YY, DD/MM/YYYY, Mon-YY, and year-only formats.
#' Uses sequential assignment rather than case_when to avoid
#' type-coercion issues between Date branches.
#' @param x Character vector of date strings.
#' @return Date vector.
parse_marshall_date <- function(x) {
  x <- trimws(x)
  result <- rep(as.Date(NA), length(x))

  ok <- !is.na(x) & x != ""

  is_year_only  <- ok & grepl("^\\d{4}$", x)
  is_dd_mm_yy   <- ok & grepl("^\\d{1,2}/\\d{1,2}/\\d{2}$", x)
  is_dd_mm_yyyy <- ok & grepl("^\\d{1,2}/\\d{1,2}/\\d{4}$", x)
  # e.g. "Oct-82"
  is_mon_yy     <- ok & grepl("^[A-Za-z]{3}-\\d{2}$", x)

  result[is_year_only]  <- as.Date(paste0(x[is_year_only], "-01-01"))
  result[is_dd_mm_yy]   <- as.Date(x[is_dd_mm_yy], format = "%d/%m/%y")
  result[is_dd_mm_yyyy] <- as.Date(x[is_dd_mm_yyyy], format = "%d/%m/%Y")
  result[is_mon_yy]     <- as.Date(paste0("01-", x[is_mon_yy]), format = "%d-%b-%y")

  unmatched <- ok & is.na(result)
  if (any(unmatched)) {
    warning("Unparsed date values: ", paste(unique(x[unmatched]), collapse = ", "))
  }

  result
}


# ── Hold facility: manual address patches for stubs ──────────────────────────

#' Manual address patches for hold facility stubs
#'
#' Returns a tibble of address information for DDP hold codes that were not
#' matched to Marshall Project locations by DETLOC, but were confirmed by
#' city/state matching against the ERO office directory or Marshall Project.
#'
#' @return A tibble with columns: detention_facility_code, address_source,
#'   facility_address, facility_city, facility_zip, facility_county, lat, lon,
#'   aor, date_first_use, date_last_use.
hold_stub_address_patches <- function() {
  tibble::tribble(
    ~detention_facility_code, ~address_source, ~facility_address,
    ~facility_city, ~facility_zip, ~facility_county,
    ~lat, ~lon, ~aor, ~date_first_use, ~date_last_use,

    # ERO directory matches (city-level; addresses are ERO sub-office locations)
    "IMPHOLD",  "manual", "2409 La Brucherie Road, Suite 3",
    "Imperial",    "92251", NA_character_,
    NA_real_, NA_real_, NA_character_, as.Date(NA), as.Date(NA),

    "CINHOLD",  "ero_directory", "9875 Redhill Drive",
    "Blue Ash",    "45242", NA_character_,
    NA_real_, NA_real_, NA_character_, as.Date(NA), as.Date(NA),

    "PROHOLD",  "ero_directory", "443 Jefferson Blvd North Suite",
    "Warwick",     "02886", NA_character_,
    NA_real_, NA_real_, NA_character_, as.Date(NA), as.Date(NA),

    # ERO field office matches
    "CBPHOLD",  "ero_directory", "250 Delaware Avenue Floor 7",
    "Buffalo",     "14202", NA_character_,
    NA_real_, NA_real_, NA_character_, as.Date(NA), as.Date(NA),

    "EPCPCTX",  "ero_directory", "11541 Montana Ave Suite E",
    "El Paso",     "79936", NA_character_,
    NA_real_, NA_real_, NA_character_, as.Date(NA), as.Date(NA),

    # Marshall Project match (city-level: Batavia, NY → BTV at 4250 Federal Dr)
    "CMDHOLD",  "marshall_city_match", "4250 FEDERAL DRIVE",
    "Batavia",     NA_character_, NA_character_,
    43.0, -78.2, NA_character_, as.Date(NA), as.Date(NA),

    # Manual address lookups for hold rooms with UNAVAILABLE addresses
    "ETWHOLDAL", "manual", "800 Forrest Avenue, 3rd Floor",
    "Gadsden",     "35901", NA_character_,
    NA_real_, NA_real_, NA_character_, as.Date(NA), as.Date(NA),

    "KNXHOLDTN", "manual", "324 Prosperity Drive",
    "Knoxville",   "37923", NA_character_,
    NA_real_, NA_real_, NA_character_, as.Date(NA), as.Date(NA),

    "SGUHOLDUT", "manual", "389 N. Industrial Road, Suite 4",
    "St. George",  "84770", NA_character_,
    NA_real_, NA_real_, NA_character_, as.Date(NA), as.Date(NA),

    "LVHOLDNV", "manual", "501 S. Las Vegas Boulevard, Suite 100",
    "Las Vegas",   "89101", NA_character_,
    NA_real_, NA_real_, NA_character_, as.Date(NA), as.Date(NA)
  )
}


# ── Hold facility canonical integration ──────────────────────────────────────

#' Build canonical records for hold facilities
#'
#' Classifies DDP hold-type facility codes, cross-references against Marshall
#' Project locations for addresses/geocoding, and assigns canonical IDs:
#' - IDs 2026+ for hold facilities with Marshall addresses
#' - Continuing sequentially for stubs (DDP name/state only, no address)
#' Also identifies hold codes that overlap with ERO field offices (2001–2025).
#'
#' @param ddp_codes Cleaned DDP codes tibble (detention_facility_code, detention_facility, state).
#' @param marshall_locations Cleaned Marshall Project locations tibble.
#' @param ero_canonical ERO field offices canonical tibble (must have detloc, canonical_id).
#' @param detloc_lookup Current DETLOC lookup (to exclude facilities already canonical).
#' @param vera_facilities Optional cleaned Vera facilities tibble. When provided, DDP codes
#'   classified as Hold/Staging in `vera_type_corrected` are included alongside the
#'   DETLOC-pattern filter. This catches short-code staging facilities (STK, AGC, etc.)
#'   that don't contain HOLD/STAGING/CPC in their DETLOC.
#' @return A list with three elements:
#'   - `hold_canonical`: tibble of new canonical hold facility records
#'   - `ero_detloc_map`: tibble mapping 22 ERO hold DETLOCs to canonical_ids 2001–2025
#'   - `hold_summary`: named list of counts for diagnostics
build_hold_canonical <- function(ddp_codes, marshall_locations, ero_canonical,
                                 detloc_lookup, vera_facilities = NULL) {
  # ── Step 1: Classify hold-type DDP codes ──────────────────────────────────
  # Primary filter: DETLOC contains HOLD, STAGING, or CPC
  regex_codes <- ddp_codes |>
    dplyr::filter(grepl("HOLD|STAGING|CPC", detention_facility_code))

  # Secondary filter: Vera classifies as Hold/Staging (catches short codes)
  if (!is.null(vera_facilities)) {
    vera_hold_codes <- vera_facilities |>
      dplyr::filter(vera_type_corrected == "Hold/Staging") |>
      dplyr::pull(detloc)
    vera_extra <- ddp_codes |>
      dplyr::filter(detention_facility_code %in% vera_hold_codes,
                    !detention_facility_code %in% regex_codes$detention_facility_code)
    if (nrow(vera_extra) > 0) {
      message(glue::glue(
        "Including {nrow(vera_extra)} Vera Hold/Staging codes not matched by DETLOC pattern: ",
        "{paste(vera_extra$detention_facility_code, collapse = ', ')}"
      ))
    }
  } else {
    vera_extra <- ddp_codes |> dplyr::filter(FALSE)
  }

  hold_codes <- dplyr::bind_rows(regex_codes, vera_extra) |>
    dplyr::mutate(
      facility_type = dplyr::case_when(
        grepl("SUB.?OFFICE|SUB.?OFF",  detention_facility, ignore.case = TRUE) ~ "sub_office",
        grepl("FIELD.?OFFICE|DIST.?OFF", detention_facility, ignore.case = TRUE) ~ "field_office",
        grepl("ERO HOLD",              detention_facility, ignore.case = TRUE) ~ "ero_hold",
        grepl("STAGING|STAGE",         detention_facility, ignore.case = TRUE) ~ "staging",
        grepl("COMMAND.?CENTER",       detention_facility, ignore.case = TRUE) ~ "command_center",
        grepl("CBP|USBP|BORDER.?PATROL", detention_facility, ignore.case = TRUE) ~ "cbp",
        grepl("CUSTODY|CASE",          detention_facility, ignore.case = TRUE) ~ "custody_case",
        TRUE ~ "hold_room"
      )
    )

  # ── Step 2: Match against Marshall data for addresses ─────────────────────
  hold_marshall <- hold_codes |>
    dplyr::left_join(
      marshall_locations |>
        dplyr::select(detloc, facility_address, facility_city, facility_county,
                      facility_zip, lat, lon, aor, date_first_use, date_last_use),
      by = c("detention_facility_code" = "detloc")
    )

  # ── Step 3: Identify ERO overlaps (already canonical at 2001–2025) ────────
  ero_detlocs <- ero_canonical$detloc[!is.na(ero_canonical$detloc)]

  ero_detloc_map <- hold_codes |>
    dplyr::filter(detention_facility_code %in% ero_detlocs) |>
    dplyr::left_join(
      ero_canonical |> dplyr::select(detloc, canonical_id),
      by = c("detention_facility_code" = "detloc")
    ) |>
    dplyr::select(detloc = detention_facility_code, canonical_id) |>
    dplyr::mutate(detloc_source = "ero")

  # ── Step 4: Exclude already-canonical facilities ──────────────────────────
  already_canonical <- unique(c(
    detloc_lookup$detloc,
    ero_detlocs
  ))

  hold_new <- hold_marshall |>
    dplyr::filter(!detention_facility_code %in% already_canonical)

  # ── Step 5: Split into addressed (Marshall) vs stubs (DDP only) ───────────
  # Ensure address_source column exists for downstream patching
  if (!"address_source" %in% names(hold_new)) {
    hold_new <- hold_new |> dplyr::mutate(address_source = NA_character_)
  }

  hold_with_addr <- hold_new |>
    dplyr::filter(!is.na(facility_address), !is.na(facility_city))
  hold_stubs <- hold_new |>
    dplyr::filter(is.na(facility_address) | is.na(facility_city))

  # ── Step 5b: Apply manual address patches to promote stubs ────────────────
  patches <- hold_stub_address_patches()
  patched_codes <- intersect(hold_stubs$detention_facility_code,
                             patches$detention_facility_code)
  if (length(patched_codes) > 0) {
    # Overwrite address fields on matched stubs
    patched <- hold_stubs |>
      dplyr::filter(detention_facility_code %in% patched_codes) |>
      dplyr::select(-facility_address, -facility_city, -facility_zip,
                    -facility_county, -lat, -lon, -aor,
                    -date_first_use, -date_last_use, -address_source) |>
      dplyr::left_join(patches, by = "detention_facility_code")

    hold_with_addr <- dplyr::bind_rows(hold_with_addr, patched)
    hold_stubs <- hold_stubs |>
      dplyr::filter(!detention_facility_code %in% patched_codes)

    message(glue::glue(
      "Applied {length(patched_codes)} manual address patches: ",
      "{paste(patched_codes, collapse = ', ')}"
    ))
  }

  # ── Step 6: Assign canonical IDs ──────────────────────────────────────────
  n_addr <- nrow(hold_with_addr)
  n_stubs <- nrow(hold_stubs)

  hold_with_addr <- hold_with_addr |>
    dplyr::arrange(state, detention_facility_code) |>
    dplyr::mutate(canonical_id = 2026L + dplyr::row_number() - 1L)

  hold_stubs <- hold_stubs |>
    dplyr::arrange(state, detention_facility_code) |>
    dplyr::mutate(canonical_id = 2026L + n_addr + dplyr::row_number() - 1L)

  # ── Step 7: Standardize to canonical schema ───────────────────────────────
  format_canonical <- function(df, has_address = TRUE) {
    result <- df |>
      dplyr::transmute(
        canonical_id,
        canonical_name = detention_facility,
        detloc = detention_facility_code,
        facility_type = facility_type,
        facility_type_wiki = dplyr::case_when(
          facility_type == "field_office" ~ "ICE ERO Field Office",
          facility_type == "sub_office"   ~ "ICE ERO Sub-Office",
          facility_type == "ero_hold"     ~ "ICE ERO Hold Room",
          facility_type == "staging"      ~ "ICE Staging Facility",
          facility_type == "command_center" ~ "ICE Command Center",
          facility_type == "cbp"          ~ "CBP Hold Facility",
          facility_type == "custody_case" ~ "ICE Custody/Case Facility",
          TRUE                            ~ "ICE Hold Room"
        ),
        state = state
      )
    if (has_address) {
      result <- result |>
        dplyr::mutate(
          address = df$facility_address,
          city = df$facility_city,
          zip = df$facility_zip,
          county = df$facility_county,
          lat = df$lat,
          lon = df$lon,
          aor = df$aor,
          date_first_use = df$date_first_use,
          date_last_use = df$date_last_use,
          address_source = dplyr::if_else(
            is.na(df$address_source),
            "marshall_project",
            df$address_source
          )
        )
    } else {
      result <- result |>
        dplyr::mutate(
          address = NA_character_,
          city = NA_character_,
          zip = NA_character_,
          county = NA_character_,
          lat = NA_real_,
          lon = NA_real_,
          aor = NA_character_,
          date_first_use = as.Date(NA),
          date_last_use = as.Date(NA),
          address_source = "ddp_stub"
        )
    }
    result
  }

  hold_canonical <- dplyr::bind_rows(
    format_canonical(hold_with_addr, has_address = TRUE),
    format_canonical(hold_stubs, has_address = FALSE)
  )

  # ── Summary ───────────────────────────────────────────────────────────────
  summary <- list(
    total_hold_codes = nrow(hold_codes),
    ero_overlap = nrow(ero_detloc_map),
    already_canonical = sum(hold_codes$detention_facility_code %in% detloc_lookup$detloc),
    new_with_address = n_addr,
    new_stubs = n_stubs,
    id_range = c(min(hold_canonical$canonical_id), max(hold_canonical$canonical_id))
  )

  message(glue::glue(
    "Hold facility canonical map: {nrow(hold_canonical)} new records ",
    "(IDs {summary$id_range[1]}\u2013{summary$id_range[2]}), ",
    "{n_addr} with Marshall addresses, {n_stubs} stubs. ",
    "{nrow(ero_detloc_map)} ERO DETLOC mappings."
  ))

  list(
    hold_canonical = hold_canonical,
    ero_detloc_map = ero_detloc_map,
    hold_summary = summary
  )
}
