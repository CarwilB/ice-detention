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
    dplyr::rows_update(overrides, by = "detloc", unmatched = "ignore") |>
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
  # the facility's own city/state. Require a comma before the city name:
  # a bare word-boundary match would eat street names that contain the
  # city word (e.g. "1675 York Hwy" in York, SC → "1675"). Use word
  # boundary on city to avoid partial matches (e.g. "Albany" in
  # "Albany Shaker Rd").
  has_suffix <- !is.na(out) & !is.na(city) & !is.na(state)
  if (any(has_suffix, na.rm = TRUE)) {
    suffix_pattern <- paste0(
      ",\\s*\\b", stringr::str_escape(city), "\\b",
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
# unchanged. Keyed by DETLOC (see geocode_source_preference() for why not
# canonical_id); facilities without a detloc can't be overridden here — use
# address_patches() in clean.R for those.

.geocode_address_overrides <- function() {
  dplyr::tribble(
    ~detloc, ~facility_address, ~facility_city, ~facility_state, ~facility_zip
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
# Hand-maintained list of DETLOCs where a specific geocoding source should be
# preferred over the default logic. Populate this table as divergent facilities
# are reviewed via the geocoding divergence report.
#
# Keyed by DETLOC (stable external facility code, pinned in
# canonical_id_registry.csv) rather than canonical_id: the ddp_other ID range
# (1054+) was renumbered on every DDP data update before registry pinning was
# introduced in 2026-10, which silently mis-targeted the original
# canonical_id-keyed table. This detloc-keyed table was translated from the
# ID-keyed version via the 2026-04-11 roster snapshot (git 8895dec), with
# corrections for the 12 renumbered IDs, the detloc code fixes for Baker CI
# (FLDADCI → FLBAKCI), CCA Florence (CCADCAZ → CCAFLAZ), and Delaney Hall
# (ESSEXNJ → DHDFNJ), and the post-April mints CLINTPA and GTMODCU.
#
# Valid preferred_source values:
#   "google_maps", "vera_institute", "marshall_project", "manual"
# When preferred_source is "manual", coordinates come from
# geocode_manual_coordinates() below.

geocode_source_preference <- function() {
  dplyr::tribble(
    ~detloc,      ~preferred_source,
    "ADAMSMS", "google_maps",      # Adams County Detention Center (Mississippi)
    "ALBHOLD", "google_maps",      # Albany Holdroom
    "AMTHOLD", "google_maps",      # Amarillo Hold Room
    "APPSCLA", "google_maps",      # Allen Parish Public Safety Complex
    "ASHRSFL", "google_maps",      # Atlantic Shores Hospital
    "BALHOLD", "google_maps",      # Baltimore Field Office
    "BEAVRPA", "google_maps",      # Beaver County Jail
    "BLBNATX", "google_maps",      # Bluebonnet Detention Center
    "BLGHOLD", "google_maps",      # Bowling Green Hold Room
    "BOPCAA",  "google_maps",      # USP Canaan
    "BOPCNV",  "google_maps",      # Nashville Comm. Corr.
    "BOPMIA",  "google_maps",      # Miami FCI (Former MCC)
    "AZSVCPC", "google_maps",      # Arizona State Prison - Yuma (Vera coord is Phoenix, wrong)
    "BOSSRLA", "google_maps",      # Bossier Parish Cor. Center
    "BURLEND", "google_maps",      # Burleigh County Detention Center
    "CACFMES", "google_maps",      # Mesa Verde ICE Processing Center
    "CARDFVA", "google_maps",      # Caroline Detention Facility
    "CATAHLA", "google_maps",      # Catahoula Correctional Center
    "CCAFLAZ", "google_maps",      # Central Arizona Florence Correctional Complex
    "CHAHOLD", "google_maps",      # Charlotte Amalie Holdroom
    "CHRLTFL", "google_maps",      # Charlotte County Jail
    "CHARLSC", "google_maps",      # Charleston County Detention Center
    "CHIHOLD", "google_maps",      # Chicago Field Office
    "CLINTPA", "google_maps",      # Clinton County Correctional Facility
    "CRPHOLD", "google_maps",      # Corpus Christi Eor Hold Room
    "DENHOLD", "google_maps",      # Denver Field Office
    "DENICDF", "google_maps",      # Denver Contract Detention Facility
    "DETHOLD", "google_maps",      # Detroit Field Office
    "DHDFNJ",  "google_maps",      # Delaney Hall Detention Facility
    "EHDLGTX", "google_maps",      # East Hidalgo Detention Center
    "ELVDFTX", "google_maps",      # El Valle Detention Facility
    "ETWHOLD", "google_maps",      # Etowah ERO Hold Room
    "FDLHOLD", "google_maps",      # Ferndale Hold Room
    "FIPCAGA", "google_maps",      # Folkston Annex IPC
    "FLBAKCI", "google_maps",      # Baker Correctional Institution
    "FREEBMN", "google_maps",      # Freeborn County Adult Detention Center
    "GREENMO", "google_maps",      # Greene County Jail
    "GSCHOLD", "google_maps",      # Glenwood Springs Holdroom
    "HARHOLD", "google_maps",      # Hartford Office
    "HOUHOLD", "google_maps",      # Houston Field Office
    "IMPHOLD", "google_maps",      # Imperial Sub Office Hold Room
    "JCRLYTX", "google_maps",      # Joe Corley Processing Center
    "JHRWLTX", "google_maps",      # Jack Harwell Detention Center
    "JKPCCLA", "google_maps",      # Jackson Parish Correctional Center
    "KCOJFOK", "google_maps",      # Kay County Justice Facility
    "KNXHOLD", "google_maps",      # Knoxville Hold Room
    "LASHOLD", "google_maps",      # Las Cruces Hold Room
    "LAWINCI", "google_maps",      # Winn Correctional Center
    "LINCONE", "google_maps",      # Lincoln County Jail (Nebraska)
    "LPAPSAZ", "google_maps",      # La Palma Corr Ctr APSO
    "LRAHOLD", "google_maps",      # Little Rock Hold Room
    "LTVHOLD", "google_maps",      # Lorton, Va Hold Room
    "LVGHOLD", "google_maps",      # Las Vegas Hold Room
    "LVYHOPA", "google_maps",      # Lehigh County Jail (Pennsylvania)
    "MADISMS", "google_maps",      # Madison County Jail
    "MARIOIN", "google_maps",      # Marion County Jail (Indiana)
    "MIAHOLD", "google_maps",      # Miramar Sub Office
    "MRREGVA", "google_maps",      # Middle River Regional Jail
    "MTGPCTX", "google_maps",      # Montgomery ICE Processing Center
    "NOLHOLD", "google_maps",      # New Orleans Field Office
    "NSVHOLD", "google_maps",      # Nashville Hold Room
    "OKCIMMC", "google_maps",      # Cimarron Correctional Facility
    "OLDHAKY", "google_maps",      # Oldham County Detention Center
    "PLATTMO", "google_maps",      # Platte County Detention Center
    "POMHOLD", "google_maps",      # Portland, Me Holdroom
    "PUEHOLD", "google_maps",      # Pueblo Holdroom
    "RADDFGA", "google_maps",      # Robert A. Deyton Detention Center
    "RAPPSVA", "google_maps",      # Rappahannock Regional Jail
    "RIOCCCA", "google_maps",      # Rio Cosumnes Correctional. Center
    "RVRCCLA", "google_maps",      # River Correctional Center
    "RWCCMLA", "google_maps",      # Richwood Correctional Center
    "SGUHOLD", "google_maps",      # St. George, Ut Holdroom
    "SLRDCAZ", "google_maps",      # San Luis Regional Detention Center
    "SLSLCUT", "google_maps",      # Salt Lake County Metro Jail
    "SNAHOLD", "google_maps",      # San Antonio Field Office
    "SNJHOLD", "google_maps",      # Snj Hold Room
    "SPGHOLD", "google_maps",      # ERO Hold Room (Springfield Mo)
    "SPMHOLD", "google_maps",      # St Paul Field Office
    "SYRHOLD", "google_maps",      # Syracuse Hold Room
    "TALLAMS", "google_maps",      # Tallahatchie County Correctional Facility
    "TAYLOTX", "google_maps",      # Taylor County Adult Detention Facility (Vera coord ~3 km west; Google matches MapQuest/county address)
    "TFIHOLD", "google_maps",      # Twin Falls Hold Room
    "WASHOLD", "google_maps",      # Washington Field Office

    "ALAMOTX", "vera_institute",   # Alamo Police Dept.
    "ALBCONY", "vera_institute",   # Albany County Jail
    "BAYAMPR", "vera_institute",   # Bayamon Hospital
    "BOPPHX",  "vera_institute",   # Phoenix Fed.Corr.Inst.
    "BOPTCN",  "vera_institute",   # Tucson Fed.Corr.Inst.
    "CASCAMT", "vera_institute",   # Cascade County Jail, Montana
    "CBENDTX", "vera_institute",   # Coastal Bend Detention Facility
    "CIBOLNM", "vera_institute",   # Cibola County Detention Center
    "CWHCCMP", "vera_institute",   # Commonwealth Healthcare Corp
    "EDNBGTX", "vera_institute",   # Edinburg Police Dept.
    "EROFCB",  "vera_institute",   # Camp East Montana
    "FLDSSFS", "vera_institute",   # Florida Soft-Sided Facility
    "FRANKPA", "vera_institute",   # Franklin County Jail
    "GRAYSKY", "vera_institute",   # Grayson County Jail
    "GTMODCU", "vera_institute",   # Migrant Ops Center Main A
    "HIDALTX", "vera_institute",   # Hidalgo County Jail
    "HMCHOTX", "vera_institute",   # Harlingen Medical Center
    "JACKSTN", "vera_institute",   # Jackson County Sheriff
    "KCCDCTX", "vera_institute",   # Karnes County Residential Center
    "KERCOCA", "vera_institute",   # Kern County Jail (Lerdo)
    "KRNRCTX", "vera_institute",   # Karnes County Immigration Processing Center
    "KRO",     "vera_institute",   # Krome North Service Processing Center
    "LONPDAR", "vera_institute",   # Lonoke Police Department
    "MAVERTX", "vera_institute",   # Maverick County Jail
    "MOAHOLD", "vera_institute",   # Mobile Holdroom
    "MPSIPAN", "vera_institute",   # Saipan Department of Corrections (Susupe)
    "MRYHPMN", "vera_institute",   # Mercy Hospital
    "OLACCLA", "vera_institute",   # Lasalle Correctional Center Olla
    "PRLDCTX", "vera_institute",   # Prairieland Detention Center
    "SJS",     "vera_institute",   # San Juan Staging
    "SROSAFL", "vera_institute",   # Santa Rosa County Jail
    "SWEETWY", "vera_institute",   # Sweetwater County Jail
    "TOORANM", "vera_institute",   # Torrance County Detention Facility
    "VALVETX", "vera_institute",   # Val Verde Correctional Facility
    "WARDCND", "vera_institute",   # Ward County Jail

    "KRHUBFL", "marshall_project", # Krome/Miami Hub
    "KROHOLD", "marshall_project", # Krome Hold Room
    "PCSHOLD", "marshall_project", # Pecos Hold Room
    "PRLHOLD", "marshall_project", # Prairieland Suboffice Hold Room
    "SJUHOLD", "marshall_project", # San Juan Airport Hold Room

    "GTMOACU", "manual"            # JTF Camp Six
  )
}

# ── Manual coordinates for facilities that no automated source gets right ────
# Keyed by DETLOC (see geocode_source_preference() for why not canonical_id).

geocode_manual_coordinates <- function() {
  dplyr::tribble(
    ~detloc,   ~manual_lat, ~manual_lon,
    # JTF Camp Six — Guantanamo Migrant Operations Center (Wikipedia GeoHack)
    "GTMOACU", 19.915,      -75.22
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
    dplyr::select(canonical_id, canonical_name, detloc,
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
    dplyr::left_join(prefs, by = "detloc") |>
    dplyr::left_join(manual_coords, by = "detloc") |>
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


# ── Facilities geocoding lookup for DDP comparison export ──────────────────────
# Builds a detloc-keyed lookup table with facility addresses and coordinates
# for use in export_ddp_comparison_data(). Selects address and coordinate columns
# from facilities_geocoded_all and renames coordinates to match the vera_type_lookup
# schema (lat, lon → latitude, longitude).

build_facilities_geocoding_lookup <- function(facilities_geocoded_all) {
  facilities_geocoded_all |>
    dplyr::select(canonical_id, canonical_name,
                  facility_address, facility_city, facility_state, facility_zip,
                  lat, lon) |>
    dplyr::rename(latitude = lat, longitude = lon)
}

