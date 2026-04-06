# Geocode facilities using Google Maps via ggmap, then merge with
# source-provided coordinates (Marshall Project, Vera Institute) and
# flag divergences.
#
# Three pipeline functions:
#   geocode_roster()              — sends all roster addresses to Google Maps API
#   geocode_source_preference()   — hand-maintained per-facility source preferences
#   build_geocoded_all()          — merges Google + source coords, flags issues
#
# Requires: register_google(key = Sys.getenv("google_maps_api_key")) called
# before tar_make(), or set in _targets.R.

# ── Haversine distance (km) ──────────────────────────────────────────────────
# Vectorized great-circle distance between two (lat, lon) pairs.

.haversine_km <- function(lat1, lon1, lat2, lon2) {
  R <- 6371
  to_rad <- pi / 180
  dlat <- (lat2 - lat1) * to_rad
  dlon <- (lon2 - lon1) * to_rad
  a <- sin(dlat / 2)^2 +
    cos(lat1 * to_rad) * cos(lat2 * to_rad) * sin(dlon / 2)^2
  R * 2 * atan2(sqrt(a), sqrt(1 - a))
}

# ── Google Maps geocoding for entire roster ──────────────────────────────────
# Geocodes facilities in facility_roster that have at least a city.
# Returns a table with canonical_id, address_string, google_lat, google_lon.
#
# **Incremental:** reads the existing geocode CSV cache from disk and only
# sends new or changed addresses to the Google Maps API. Facilities whose
# address_string matches the cache are returned from cache without an API call.
# If no cache file exists, all facilities are geocoded (first run).
#
# To force a full re-geocode: delete data/google-geocoded-facilities.csv and
# targets::tar_invalidate(facilities_google_geocoded); tar_make()

geocode_roster <- function(facility_roster,
                           cache_path = here::here("data",
                                                   "google-geocoded-facilities.csv")) {
  ggmap::register_google(key = Sys.getenv("google_maps_api_key"), write = FALSE)

  overrides <- .geocode_address_overrides()

  all_addresses <- facility_roster |>
    dplyr::filter(!is.na(facility_city)) |>
    dplyr::rows_update(overrides, by = "canonical_id", unmatched = "ignore") |>
    dplyr::mutate(
      clean_address = .clean_address_for_geocoding(
        facility_address, facility_city, facility_state
      ),
      address_string = .build_address_string(
        clean_address, facility_city, facility_state, facility_zip
      )
    ) |>
    dplyr::select(canonical_id, address_string)

  # ── Read cache ──
  cache <- if (file.exists(cache_path)) {
    readr::read_csv(cache_path, col_types = readr::cols(
      canonical_id = readr::col_double(),
      address_string = readr::col_character(),
      google_lat = readr::col_double(),
      google_lon = readr::col_double()
    ))
  } else {
    dplyr::tibble(canonical_id = double(), address_string = character(),
                  google_lat = double(), google_lon = double())
  }

  # ── Diff: identify rows that need (re-)geocoding ──
  current <- all_addresses |>
    dplyr::left_join(
      cache |> dplyr::select(canonical_id, cached_address = address_string,
                              google_lat, google_lon),
      by = "canonical_id"
    ) |>
    dplyr::mutate(
      needs_geocoding = is.na(cached_address) |
        address_string != cached_address |
        is.na(google_lat)
    )

  cached_rows <- current |>
    dplyr::filter(!needs_geocoding) |>
    dplyr::select(canonical_id, address_string, google_lat, google_lon)

  to_geocode <- current |>
    dplyr::filter(needs_geocoding) |>
    dplyr::select(canonical_id, address_string)

  n_cached <- nrow(cached_rows)
  n_new    <- nrow(to_geocode)

  cli::cli_inform(c(
    "i" = "{n_cached} facilities from cache (address unchanged)",
    "i" = "{n_new} facilities to geocode via Google Maps API"
  ))

  if (n_new > 0) {
    fresh <- ggmap::mutate_geocode(to_geocode, address_string) |>
      dplyr::transmute(canonical_id, address_string,
                       google_lat = lat, google_lon = lon)
  } else {
    fresh <- dplyr::tibble(canonical_id = double(), address_string = character(),
                           google_lat = double(), google_lon = double())
  }

  dplyr::bind_rows(cached_rows, fresh) |>
    dplyr::arrange(canonical_id)
}


# ── Clean addresses before geocoding ────────────────────────────────────────
# Strips redundant city/state/ZIP from addresses that contain full mailing
# addresses (common in Marshall Project hold facility data), and removes
# spurious commas after street numbers.

.clean_address_for_geocoding <- function(address, city, state) {
  out <- address

  # Strip ", City, ST ZIP..." or ", City ST ZIP..." suffix when it matches
  # the facility's own city/state. Use word boundary on city to avoid
  # partial matches (e.g. "Albany" in "Albany Shaker Rd").
  has_suffix <- !is.na(out) & !is.na(city) & !is.na(state)
  if (any(has_suffix, na.rm = TRUE)) {
    suffix_pattern <- paste0(
      ",?\\s*\\b", stringr::str_escape(city), "\\b",
      "(?:[,\\s]+(?:", stringr::str_escape(state), "|\\d{5}))*",
      ".*$"
    )
    cleaned <- stringr::str_replace(
      out[has_suffix],
      stringr::regex(suffix_pattern[has_suffix], ignore_case = TRUE),
      ""
    )
    cleaned <- trimws(cleaned)
    keep <- nchar(cleaned) > 0
    out[has_suffix][keep] <- cleaned[keep]
  }

  # Fallback: strip generic ", <words>, <2-letter state> <5-digit ZIP>..." at
  # end, even when the embedded city doesn't match facility_city (e.g. hold
  # rooms where address city differs from roster city).
  out <- stringr::str_replace(
    out,
    ",\\s+[A-Za-z .'-]+,\\s+[A-Z]{2}\\s+\\d{5}.*$",
    ""
  )

  # Remove spurious comma after leading street number ("5500, Veterans Dr")
  out <- stringr::str_replace(out, "^(\\d+),\\s+", "\\1 ")

  out
}


# ── Manual address overrides for geocoding ────────────────────────────────────
# Provides corrected address components for facilities whose roster address
# is missing, incorrect, or produces bad Google Maps results (e.g. US centroid).
# These override the roster values only for geocoding; the roster itself is
# unchanged.

.geocode_address_overrides <- function() {
  dplyr::tribble(
    ~canonical_id, ~facility_address, ~facility_city, ~facility_state, ~facility_zip
    # Add rows here for facilities that need geocoding-only address fixes
    # (i.e. roster address is acceptable but Google can't resolve it).
    # Prefer adding to address_patches() in clean.R when the fix should
    # propagate through the entire pipeline.
  )
}


# ── Build geocode address string ─────────────────────────────────────────────
# Assembles address components into a single string for the Google Maps API.
# Omits NA ZIP codes and uses territory-appropriate country suffixes instead
# of "USA" for PR, VI, GU, MP, AS, and Cuba.

.build_address_string <- function(address, city, state, zip) {
  territory_map <- c(
    PR = "Puerto Rico", VI = "U.S. Virgin Islands",
    GU = "Guam", MP = "Northern Mariana Islands",
    AS = "American Samoa", Cuba = "Cuba"
  )

  country <- dplyr::if_else(
    state %in% names(territory_map),
    territory_map[state],
    "USA"
  )

  # For territories, omit the state abbreviation (redundant with country name)
  is_territory <- state %in% names(territory_map)

  dplyr::case_when(
    !is.na(address) & !is.na(zip) & !is_territory ~
      paste(address, city, state, zip, country, sep = ", "),
    !is.na(address) & is.na(zip) & !is_territory ~
      paste(address, city, state, country, sep = ", "),
    !is.na(address) & !is.na(zip) & is_territory ~
      paste(address, city, zip, country, sep = ", "),
    !is.na(address) & is.na(zip) & is_territory ~
      paste(address, city, country, sep = ", "),
    !is_territory ~
      paste(city, state, country, sep = ", "),
    TRUE ~
      paste(city, country, sep = ", ")
  )
}


# ── Per-facility geocode source preferences ──────────────────────────────────
# Hand-maintained list of canonical IDs where a specific geocoding source
# should be preferred over the default logic. Populate this table as
# divergent facilities are reviewed via the geocoding divergence report.
#
# Valid preferred_source values:
#   "google_maps", "vera_institute", "marshall_project", "manual"
# When preferred_source is "manual", coordinates come from
# geocode_manual_coordinates() below.

geocode_source_preference <- function() {
  google <- c(
    2005, 14, 212, 18, 2025, 2002,     # from hand-checked list
    76, 154, 223, 274, 358, 58,     # from hand-checked list
    294, 326, 329, 1064, 1004, 1158,    # from hand-checked list
    1193, 2011, 2020, 2024, 2041, 2052,
    391, 3, 182, 244, 101, 178, 310,
    25, 120, 314, 231, 53, 138, 10, 192,
    125, 115, 2014, 125, 115,
    81, 212, 61, 2007, 145,
    2037, 1162, 2094, 1199, 2008,
    3047, 2050, 27, 177, 64, 2013,
    318, 2145, # from hand-checked list
    # plus these newly given addresses:
    2141, 1199, 2027, 2122, 2119, 39, 2077
  )
  vera <- c(
    3109, 324, 3155, 328, 1165, 143,    # from hand-checked list
    56, 1063, 84, 207, 354, 371,        # from hand-checked list
    75, 136, 1075, 1168, 1164, 153,
    197, 108, 190, 364, 191, 302,
    1164, 136, 220, 56, 3109,
    1170, 377, 2122, 6, 1109
    )
  marshall <- c(
    2111, 2057, 2028, 2056, 2134                   # from hand-checked list
  )
  manual <- c(
    176                                 # JTF Camp Six (Wikipedia GeoHack)
  )

  dplyr::tribble(~canonical_id, ~preferred_source) |>
    dplyr::bind_rows(
      dplyr::tibble(canonical_id = google,   preferred_source = "google_maps"),
      dplyr::tibble(canonical_id = vera,     preferred_source = "vera_institute"),
      dplyr::tibble(canonical_id = marshall, preferred_source = "marshall_project"),
      dplyr::tibble(canonical_id = manual,   preferred_source = "manual")
    ) |>
    dplyr::distinct(canonical_id, .keep_all = TRUE)
}

# ── Manual coordinates for facilities that no automated source gets right ────

geocode_manual_coordinates <- function() {
  dplyr::tribble(
    ~canonical_id, ~manual_lat,   ~manual_lon,
    # JTF Camp Six — Guantanamo Migrant Operations Center (Wikipedia GeoHack)
    176,            19.915,        -75.22
  )
}

# ── Unified geocoded table with divergence flags ─────────────────────────────
# Merges Google geocoding results with source-provided coordinates from
# Marshall Project and Vera Institute. Flags address quality issues and
# divergences between sources.
#
# For facilities where Google and a source agree within 1 km, lat/lon are set
# from Google. Divergences between 1–3 km are auto-accepted using Google
# (geocode_source = "auto:google_maps+..."). Divergences >= 3 km get lat/lon
# set to NA unless resolved by geocode_source_preference().
#
# Returns one row per canonical_id with columns:
#   canonical_id, google_lat, google_lon, source_lat, source_lon, source_name,
#   lat, lon, geocode_source, divergence_km, address_quality

build_geocoded_all <- function(facility_roster,
                               facilities_google_geocoded,
                               hold_canonical_data,
                               vera_facilities,
                               detloc_lookup) {

  DIVERGENCE_THRESHOLD_KM <- 1
  AUTO_ACCEPT_THRESHOLD_KM <- 3

  # ── Classify address quality ──
  quality <- facility_roster |>
    dplyr::transmute(
      canonical_id,
      address_quality = dplyr::case_when(
        is.na(facility_address) & is.na(facility_city) ~ "no_address",
        is.na(facility_address) ~ "city_only",
        grepl("^P\\.?\\s*O\\.?\\s*Box", facility_address, ignore.case = TRUE) ~
          "po_box",
        TRUE ~ "full"
      )
    )

  # ── Collect source-provided coordinates ──
  # Marshall Project: hold facilities
  marshall <- hold_canonical_data$hold_canonical |>
    dplyr::filter(!is.na(lat)) |>
    dplyr::transmute(canonical_id, source_lat = lat, source_lon = lon,
                     source_name = "marshall_project")

  # Vera Institute: via detloc
  vera_coords <- vera_facilities |>
    dplyr::filter(!is.na(latitude), !is.na(longitude)) |>
    dplyr::select(detloc, vera_lat = latitude, vera_lon = longitude) |>
    dplyr::distinct(detloc, .keep_all = TRUE)

  vera_via_detloc <- facility_roster |>
    dplyr::filter(!is.na(detloc)) |>
    dplyr::select(canonical_id, detloc) |>
    dplyr::inner_join(vera_coords, by = "detloc") |>
    dplyr::transmute(canonical_id, source_lat = vera_lat, source_lon = vera_lon,
                     source_name = "vera_institute")

  # Combine sources; prefer Marshall over Vera when both exist for same ID
  source_coords <- dplyr::bind_rows(marshall, vera_via_detloc) |>
    dplyr::arrange(canonical_id,
                   match(source_name, c("marshall_project", "vera_institute"))) |>
    dplyr::distinct(canonical_id, .keep_all = TRUE)

  # ── Merge everything ──
  result <- facility_roster |>
    dplyr::select(canonical_id, canonical_name,
                  facility_address, facility_city, facility_state, facility_zip) |>
    dplyr::left_join(quality, by = "canonical_id") |>
    dplyr::left_join(
      facilities_google_geocoded |>
        dplyr::select(canonical_id, google_lat, google_lon),
      by = "canonical_id"
    ) |>
    dplyr::left_join(source_coords, by = "canonical_id")

  # ── Compute divergence ──
  has_both <- !is.na(result$google_lat) & !is.na(result$source_lat)

  result$divergence_km <- NA_real_
  result$divergence_km[has_both] <- .haversine_km(
    result$google_lat[has_both], result$google_lon[has_both],
    result$source_lat[has_both], result$source_lon[has_both]
  )

  # ── Apply manual source preferences ──
  prefs <- geocode_source_preference()
  manual_coords <- geocode_manual_coordinates()

  # ── Assign lat/lon ──
  # Priority: (1) manual preference, (2) auto-accept divergence < 3 km → Google,
  # (3) agreement within 1 km → Google, (4) single source, (5) divergent ≥ 3 km → NA.
  # The `divergent` flag stays TRUE for all > 1 km (the report uses it), but

  # lat/lon are only left NA for divergences ≥ AUTO_ACCEPT_THRESHOLD_KM.
  result <- result |>
    dplyr::left_join(prefs, by = "canonical_id") |>
    dplyr::left_join(manual_coords, by = "canonical_id") |>
    dplyr::mutate(
      divergent = !is.na(divergence_km) & divergence_km > DIVERGENCE_THRESHOLD_KM,
      lat = dplyr::case_when(
        preferred_source == "manual"            ~ manual_lat,
        preferred_source == "google_maps"       ~ google_lat,
        preferred_source == "vera_institute"    ~ source_lat,
        preferred_source == "marshall_project"  ~ source_lat,
        # Auto-accept small divergences using Google
        divergent & divergence_km < AUTO_ACCEPT_THRESHOLD_KM ~ google_lat,
        divergent ~ NA_real_,
        !is.na(google_lat) ~ google_lat,
        !is.na(source_lat) ~ source_lat,
        TRUE ~ NA_real_
      ),
      lon = dplyr::case_when(
        preferred_source == "manual"            ~ manual_lon,
        preferred_source == "google_maps"       ~ google_lon,
        preferred_source == "vera_institute"    ~ source_lon,
        preferred_source == "marshall_project"  ~ source_lon,
        divergent & divergence_km < AUTO_ACCEPT_THRESHOLD_KM ~ google_lon,
        divergent ~ NA_real_,
        !is.na(google_lon) ~ google_lon,
        !is.na(source_lon) ~ source_lon,
        TRUE ~ NA_real_
      ),
      geocode_source = dplyr::case_when(
        !is.na(preferred_source) ~ paste0("preference:", preferred_source),
        divergent & divergence_km < AUTO_ACCEPT_THRESHOLD_KM ~
          paste0("auto:google_maps+", source_name),
        divergent ~ "divergent",
        !is.na(google_lat) & !is.na(source_lat) ~ paste0("google_maps+", source_name),
        !is.na(google_lat) ~ "google_maps",
        !is.na(source_lat) ~ source_name,
        TRUE ~ NA_character_
      )
    ) |>
    dplyr::select(-preferred_source, -manual_lat, -manual_lon)

  # ── Console reporting ──
  n_total       <- nrow(result)
  n_no_address  <- sum(result$address_quality == "no_address", na.rm = TRUE)
  n_city_only   <- sum(result$address_quality == "city_only", na.rm = TRUE)
  n_po_box      <- sum(result$address_quality == "po_box", na.rm = TRUE)
  n_divergent   <- sum(result$divergent, na.rm = TRUE)
  n_auto_accept <- sum(grepl("^auto:", result$geocode_source), na.rm = TRUE)
  n_preferred   <- sum(grepl("^preference:", result$geocode_source), na.rm = TRUE)
  n_unresolved  <- sum(result$geocode_source == "divergent", na.rm = TRUE)
  n_geocoded    <- sum(!is.na(result$lat))

  cli::cli_inform(c(
    "i" = "Geocoded {n_geocoded} of {n_total} facilities",
    "i" = "{n_divergent} with Google vs. source divergence > {DIVERGENCE_THRESHOLD_KM} km",
    "i" = "  {n_preferred} resolved by manual preference",
    "i" = "  {n_auto_accept} auto-accepted (< {AUTO_ACCEPT_THRESHOLD_KM} km, using Google)",
    "i" = "  {n_unresolved} unresolved (>= {AUTO_ACCEPT_THRESHOLD_KM} km, lat/lon = NA)",
    "!" = "{n_no_address} with no address or city",
    "!" = "{n_city_only} with city only (no street address)",
    "!" = "{n_po_box} with P.O. Box addresses"
  ))

  if (n_unresolved > 0) {
    div_rows <- result |>
      dplyr::filter(geocode_source == "divergent") |>
      dplyr::arrange(dplyr::desc(divergence_km))
    cli::cli_inform("Unresolved divergent facilities (>= {AUTO_ACCEPT_THRESHOLD_KM} km):")
    for (i in seq_len(nrow(div_rows))) {
      cli::cli_inform(c("*" = "{div_rows$canonical_name[i]} (ID {div_rows$canonical_id[i]}): {round(div_rows$divergence_km[i], 1)} km — source: {div_rows$source_name[i]}"))
    }
  }

  result |>
    dplyr::select(canonical_id, canonical_name,
                  facility_address, facility_city, facility_state, facility_zip,
                  lat, lon, geocode_source,
                  google_lat, google_lon, source_lat, source_lon, source_name,
                  divergence_km, address_quality, divergent)
}


