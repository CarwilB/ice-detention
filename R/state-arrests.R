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

# ── MN general-area apprehension codes ────────────────────────────────────────
# Three-letter arresting-office codes that appear in apprehension_site_landmark
# as "XXX GENERAL AREA, NON-SPECIFIC". Locations inferred from each code's modal
# toa_current_duty_site across all arrests (DDP 20260806 release); e.g. STC is
# South Texas (Pearsall), not St. Cloud. Only Minnesota-located codes are
# mapped to counties by .parse_county_landmark(): on rows where the code's
# office sits outside MN, apprehension_state = "MINNESOTA" conflicts with the
# office's actual state, so assigning that state's county to an MN arrest would
# fabricate geography.
mn_general_area_codes <- tibble::tribble(
  ~code, ~location,                                     ~county,         ~state,
  "SPM", "St. Paul ERO",                                "Ramsey",        "MN",
  "XMS", "HSI St. Paul",                                "Ramsey",        "MN",
  "XDU", "HSI RA Duluth",                               "St. Louis",     "MN",
  "INT", "HSI RA Duluth (International Falls)",         "Koochiching",   "MN",
  "GPM", "HSI RA Duluth (Grand Portage)",               "Cook",          "MN",
  "GRF", "Grand Forks ERO sub-office",                  "Grand Forks",   "ND",
  "SFD", "Sioux Falls sub-office",                      "Minnehaha",     "SD",
  "EPC", "El Paso, TX (SPC sub-office)",                "El Paso",       "TX",
  "ELP", "El Paso, TX",                                 "El Paso",       "TX",
  "SNA", "San Antonio ERO",                             "Bexar",         "TX",
  "STC", "South Texas Detention Facility (Pearsall)",   "Frio",          "TX",
  "KCD", "Karnes City sub-office",                      "Karnes",        "TX",
  "HLG", "Harlingen",                                   "Cameron",       "TX",
  "EDN", "Edinburg sub-office",                         "Hidalgo",       "TX",
  "PIC", "Port Isabel",                                 "Cameron",       "TX",
  "SPG", "Springfield, MO sub-office",                  "Greene",        "MO",
  "CHI", "Chicago",                                     "Cook",          "IL",
  "AUS", "Austin, TX",                                  "Travis",        "TX",
  "ABQ", "Albuquerque",                                 "Bernalillo",    "NM",
  "SAC", "Sacramento sub-office",                       "Sacramento",    "CA",
  "SMA", "Santa Maria sub-office",                      "Santa Barbara", "CA",
  "LVG", "Las Vegas",                                   "Clark",         "NV"
)

# ── MN OTHER apprehension-site landmarks ──────────────────────────────────────
# Exact-match lookup for loc_type == "OTHER" landmarks in Minnesota arrests:
# state correctional facilities, federal facilities, county jails, police
# departments, and probation offices. State is MN unless noted; out-of-state
# entries are kept for documentation but mapped to NA county for the MN
# choropleth (same rule as mn_general_area_codes).
mn_other_landmarks <- tibble::tribble(
  ~landmark,                                                          ~county,     ~state,
  "APPLE VALLEY, MN POLICE DEPARTMENT",                               "Dakota",    "MN",
  "BEADLE CO REGIONAL CORR. CENT., HURON, SD",                        "Beadle",    "SD",
  "BLOOMINGTON POLICE DEPARTMENT, MN",                                "Hennepin",  "MN",
  "COTTONWOOD CO JAIL, WINDOM, MN",                                   "Cottonwood", "MN",
  "FCI SANDSTONE- MN",                                                "Pine",      "MN",
  "FCI WASECA- MN",                                                   "Waseca",    "MN",
  "FMC ROCHESTER- MN",                                                "Olmsted",   "MN",
  "GRAND FORKS ICE ERO OFFICE",                                       "Grand Forks", "ND",
  "GRAND FORKS COUNTY JAIL",                                          "Grand Forks", "ND",
  "LAKE REGIONAL LAW ENFORCEMENT CENTER, ND",                         "Ramsey",    "ND",
  "MINNETONKA PD, MN",                                                "Hennepin",  "MN",
  "MN CORR FACILITY - SHAKOPEE, MN",                                  "Scott",     "MN",
  "MN CORR FACILITY FARIBAULT, MN",                                   "Rice",      "MN",
  "MN CORR FACILITY MOOSE LAKE, MN",                                  "Carlton",   "MN",
  "MN CORR FACILITY OAK PARK HEIGHTS, MN",                            "Washington", "MN",
  "MN CORR FACILITY RUSH CITY, MN",                                   "Chisago",   "MN",
  "MN CORR FACILITY, MN",                                             NA,          "MN",
  "MN CORR FACILITY-LINO LAKES, MN",                                  "Anoka",     "MN",
  "MN CORR FACILITY-ST. CLOUD, MN",                                   "Stearns",   "MN",
  "MN OCRR FACILITY STILLWATER, MN",                                  "Washington", "MN",
  "MN PROBATION - CO - HENNEPIN CO COMM CORR REHAB - MPLS, MN",       "Hennepin",  "MN",
  "MN PROBATION - CO - KANDIYOHI CO COMM CORR - WILLMAR, MN",         "Kandiyohi", "MN",
  "MN PROBATION - CO - MOWER CO CORR SERV - AUSTIN, MN",              "Mower",     "MN",
  "MN PROBATION - CO - ROCK-NOBLES COMM CORR - WORTHINGTON, MN",      "Nobles",    "MN",
  "MN PROBATION - CO - STEELE CO CRT SERV - OWATONNA, MN",            "Steele",    "MN",
  "MN PROBATION - CO - WRIGHT CO COURT SERV - BUFFALO, MN",           "Wright",    "MN",
  "MN PROBATION - FED - FEDERAL COURTHOUSE - HENNEPIN CO - MPLS, MN", "Hennepin",  "MN",
  "MN PROBATION - FED - FEDERAL COURTHOUSE - RAMSEY CO - ST PAUL, MN", "Ramsey",   "MN",
  "MN PROBATION - STATE - 6 W COMM CORR - MONTEVIDEO, MN",            "Chippewa",  "MN",
  "MN PROBATION - STATE - MN DEPT OF CORR - CHASKA, MN",              "Carver",    "MN",
  "MN PROBATION - STATE - MN DEPT OF CORR - LYON CO - MARSHALL, MN",  "Lyon",      "MN",
  "MOOSE LAKE CORR FACILITY, MN",                                     "Carlton",   "MN",
  "NOBLES CO JAIL, WORTHINGTON, MN",                                  "Nobles",    "MN",
  "PIPESTONE CO JAIL, PIPESTONE, MN",                                 "Pipestone", "MN",
  "RICHFIELD POLICE DEPARTMENT, MN",                                  "Hennepin",  "MN",
  "ROSEAU CO JAIL, ROSEAU, MN",                                       "Roseau",    "MN",
  # Values first seen in the 20260806 release
  "WILLMAR, MN AREA",                                                 "Kandiyohi", "MN",
  "STEVENS CO JAIL, MN",                                              "Stevens",   "MN",
  "CRYSTAL PD, MN",                                                   "Hennepin",  "MN",
  "NORTHEAST REGIONAL CORRECTIONAL CENTER, MN",                       "St. Louis", "MN",
  "MN PROBATION - CO - SHERBURNE CO PROB DEPT - ELK RIVER, MN",       "Sherburne", "MN",
  "BROOKINGS CO JAIL, BROOKINGS, SD",                                 "Brookings", "SD",
  "ST. TAMMANY PARISH, LA",                                           "St. Tammany Parish", "LA",
  "US MARSHAL SERVICE, SIOUX FALLS, SD",                              "Minnehaha", "SD",
  "US MARSHALS SERVICE, ND",                                          NA,          "ND",
  "US MARSHALS, MN",                                                  NA,          "MN",
  "WILLIAMSBURG FEDERAL CORRECTIONAL INSTITUTION",                    "Williamsburg County", "SC"
)

# ── Named landmark regex patterns ─────────────────────────────────────────────
# Regex patterns matched (first match wins, in table order) against
# apprehension_site_landmark before the general-area / OTHER / "X COUNTY"
# fallbacks in .parse_landmark_county_state(). One row per pattern with the
# county and state it implies; NA county means the pattern pins the state but
# not the county. state = "report" means the report's own state (the only
# sensible attribution for MN-report landmarks); state = "suffix" means the
# ", XX" state suffix in the landmark, falling back to the report state; a
# 2-letter abbr pins a specific state. Extend or replace this table per
# state as needed.
mn_landmark_patterns <- tibble::tribble(
  ~pattern,                                            ~county,     ~state,
  # MSP airport sits in Hennepin County — must precede the "ST. PAUL" arm
  "MINNEAPOLIS.*INTERNATIONAL AIRPORT",                "Hennepin",  "suffix",
  "SPM GENERAL|ST\\.? PAUL",                           "Ramsey",    "report",
  # Whipple Federal Building is in Minneapolis (Hennepin), not Ramsey
  "WHIPPLE",                                           "Hennepin",  "report",
  "BLOOMINGTON|MINNEAPOLIS|HENNEPIN",                  "Hennepin",  "report",
  "US MARSHALS, MN",                                   NA,          "report"
)

# ── TN general-area apprehension codes ────────────────────────────────────────
# Three-letter arresting-office codes that appear in Tennessee arrests as
# "XXX GENERAL AREA, NON-SPECIFIC". Only codes whose modal toa_current_duty_site
# (from the 20260330 arrests release, the last with that column) sits in
# Tennessee are mapped to counties — when the office sits outside TN,
# apprehension_state = "TENNESSEE" conflicts with the office's actual state,
# so assigning that state's county would fabricate geography (same rule as
# mn_general_area_codes). Office locations are confirmed by the duty-site
# strings themselves, which name the city.
tn_general_area_codes <- tibble::tribble(
  ~code, ~location,                           ~county,         ~state,
  "NSV", "Nashville ERO Sub-Office",          "Davidson",      "TN",
  "KNX", "Knoxville ERO Sub-Office",          "Knox",          "TN",
  "XKI", "Knoxville ERO Sub-Office",          "Knox",          "TN",
  "MEM", "Memphis ERO Sub-Office",            "Shelby",        "TN",
  "XME", "Memphis ERO / HSI RAC",             "Shelby",        "TN",
  "CNG", "Chattanooga ERO Sub-Office",        "Hamilton",      "TN",
  # Out-of-state offices (kept for documentation, as in the MN table; the
  # county choropleth filters to the report state so these never plot).
  # Modal share from toa_current_duty_site (20260330 arrests release):
  # OAK/XOX combine alias strings (see notes below); all >= 0.60.
  "MTG", "Montgomery County, TX Sub Office",  "Montgomery",    "TX",
  "SNA", "San Antonio ERO",                   "Bexar",         "TX",
  "AUS", "Austin, TX Sub Office",             "Travis",        "TX",
  "DLR", "Del Rio, TX Sub Office",            "Val Verde",     "TX",
  "SBD", "San Bernardino, CA Sub Office",     "San Bernardino", "CA",
  "CIP", "Central Islip, NY Sub Office",      "Suffolk",       "NY",
  "PHI", "Philadelphia, PA Docket Control",   "Philadelphia",  "PA",
  "RDU", "Raleigh/Durham, NC Sub-Office",     "Wake",          "NC",
  "ETW", "Etowah, AL Sub Office",             "Etowah",        "AL",
  "BIL", "Billings, MT Sub Office",           "Yellowstone",   "MT",
  "NOL", "New Orleans, LA Docket Control",    "Orleans Parish", "LA",
  # Duty string says "Gulfport, LA" but Gulfport sits in Harrison County, MS;
  # ICE's Gulfport sub-office is a Mississippi office under the New Orleans
  # (LA) field office, hence the string's state tag.
  "GUL", "Gulfport Sub-Office",               "Harrison",      "MS",
  "JNA", "Jena, LA Sub Office",               "La Salle Parish", "LA",
  "WNF", "Winnfield, LA Sub-Office",          "Winn Parish",   "LA",
  "OAK", "Oakdale, LA Sub-Office / Oakdale Processing Center (87.9% combined; NOT Oakland)", "Allen Parish", "LA",
  "XOX", "Ventura, CA Sub Office / HSI RAC Ventura (83.3% combined; NOT Oxnard)", "Ventura", "CA",
  "GRN", "Greensboro, NC Sub Office",         "Guilford",      "NC",
  "BSC", "Big Spring, TX IRP Sub-Office",     "Howard",        "TX",
  "MID", "Midland, TX Sub-Office",            "Midland",       "TX",
  "PCS", "Pecos, TX IHP Sub-Office",          "Reeves",        "TX",
  "WCT", "Waco, TX Sub Office",               "McLennan",      "TX",
  "PKE", "Pike County, PA Sub Office",        "Pike",          "PA",
  "XWK", "HSI RAC Wichita, KS",               "Sedgwick",      "KS",
  "TOD", "Newark, NJ Docket Control Office",  "Essex",         "NJ"
)

# ── TN OTHER apprehension-site landmarks ──────────────────────────────────────
# Exact-match lookup for loc_type == "OTHER" landmarks in Tennessee arrests:
# CAP program sites (police departments, probation offices, BOP/county
# facilities). All are in the Memphis area except the two state prisons.
tn_other_landmarks <- tibble::tribble(
  ~landmark,                                                  ~county,    ~state,
  "ARLINGTON POLICE DEPARTMENT",                              "Shelby",   "TN",
  "CAP - BARTLETT POLICE DEPARTMENT TN STATE",                "Shelby",   "TN",
  "CAP - BOP FCI MEMPHIS TN STATE",                           "Shelby",   "TN",
  "CAP - COLLIERVILLE POLICE DEPARTMENT TN STATE",            "Shelby",   "TN",
  "CAP - GERMANTOWN POLICE DEPARTMENT TN STATE",              "Shelby",   "TN",
  "CAP - JAIL EAST TN STATE",                                 "Shelby",   "TN",
  "CAP - MEMPHIS POLICE DEPARTMENT TN STATE",                 "Shelby",   "TN",
  "CAP - NORTHWEST CORRECTIONAL COMPLEX TN STATE",            "Lake",     "TN",
  "CAP - PROBATION OFFICE MEMPHIS CRUMP BLVD TN STATE",       "Shelby",   "TN",
  "CAP - PROBATION OFFICE MEMPHIS OVERTON TN STATE",          "Shelby",   "TN",
  "CAP - SHELBY CO CORRECTION CENTER (PENAL FARM) TN STATE",  "Shelby",   "TN",
  "CAP - WEST TENNESSEE STATE PENITENTIARY TN STATE",         "Shelby",   "TN",
  "CAP - WHITEVILLE CORRECTIONAL FACILITY TN STATE",          "Hardeman", "TN"
)

# Per-state lookup tables for .parse_landmark_county_state(). Add an entry
# here when a new state's landmarks need county/state attribution.
state_landmark_tables <- function(state_upper) {
  if (state_upper == "TENNESSEE") {
    list(patterns = tibble::tibble(pattern = character(),
                                   county  = character(),
                                   state   = character()),
         ga    = tn_general_area_codes,
         other = tn_other_landmarks)
  } else {
    list(patterns = mn_landmark_patterns,
         ga    = mn_general_area_codes,
         other = mn_other_landmarks)
  }
}

# ── Airport landmark locations ────────────────────────────────────────────────
# Exact-match lookup for named airports appearing in apprehension_site_landmark
# (airport arrests can happen in any state's report, so this table is
# location-independent rather than per-report). County is where the airport
# physically sits; DFW straddles county lines and is attributed to Tarrant,
# where most of the airport lies.
airport_landmarks <- tibble::tribble(
  ~landmark,                                                            ~county,        ~state,
  "BOSTON LOGAN AIRPORT",                                               "Suffolk",      "MA",
  "CAP TUCSON INTERNATIONAL AIRPORT AZ STATE",                          "Pima",         "AZ",
  "CHARLOTTE AIRPORT",                                                  "Mecklenburg",  "NC",
  "CHI O'HARE INTERNATIONAL AIRPORT",                                   "Cook",         "IL",
  "CHICAGO O'HARE AIRPORT",                                             "Cook",         "IL",
  "CINCINNATI/KENTUCKY INT AIRPORT",                                    "Boone",        "KY",
  "DFW AIRPORT",                                                        "Tarrant",      "TX",
  "HARTSFIELD (AIRPORT) OFFICE (FEDERAL PROBATION & PAROLE)",           "Fulton",       "GA",
  "LEAR - SKY HARBOR AIRPORT",                                          "Maricopa",     "AZ",
  "MINNEAPOLIS ST. PAUL INTERNATIONAL AIRPORT, MN",                     "Hennepin",     "MN",
  "ORLANDO INTERNATIONAL AIRPORT",                                      "Orange",       "FL",
  "PORTLAND INTERNATIONAL AIRPORT",                                     "Multnomah",    "OR",
  "SAN BERNARDINO INTERNATIONAL AIRPORT",                               "San Bernardino", "CA",
  "SANFORD ORLANDO INTERNATIONAL AIRPORT",                              "Seminole",     "FL"
)

# ── Arrests schema compatibility ──────────────────────────────────────────────
# DDP reworked the arrests schema in the 20260806 release: apprehension_state
# became the apprehension_state_filled_in/_original/_fill_source trio, and
# apprehension_site_landmark was renamed event_landmark. This shim restores
# the old column names ( preferring original fields when present) so all
# builders and reports can consume either schema. apprehension_type and
# other dropped columns have no replacement and are recreated as all-NA.
.normalize_arrests_schema <- function(arrests, quiet = FALSE) {
  fallbacks <- c(
    apprehension_state         = "apprehension_state_filled_in",
    apprehension_site_landmark = "event_landmark"
  )
  for (old in names(fallbacks)) {
    new <- fallbacks[[old]]
    if (!old %in% names(arrests) && new %in% names(arrests)) {
      if (!quiet) message(glue::glue("arrests: '{old}' not present; using '{new}'"))
      arrests[[old]] <- arrests[[new]]
    }
  }
  if (!"apprehension_type" %in% names(arrests)) {
    arrests$apprehension_type <- NA_character_
  }
  arrests
}

# ── County name extraction from landmark text ────────────────────────────────
# Shared text-extraction step used by .parse_landmark_county_state() and
# .parse_county_landmark(). Landmarks often carry a leading arresting-office
# code ("CAP - GIBSON COUNTY JAIL TN STATE"), sometimes with interior
# segments ("CAP - JUVENILE - MARICOPA COUNTY ...", "A - WI DOC - BROWN
# COUNTY ..."), or a narrative phrase ("FUGITIVE OPERATIONS ON STREET DEWITT
# COUNTY, ILLINOIS", "FRU - ALL AREAS INSIDE KARNES COUNTY"). Peel those
# prefixes so the capture is the county name alone. The extraction is
# non-greedy so it stops at the FIRST "COUNTY" (landmarks can name a county
# twice, e.g. "VOLUSIA COUNTY JAIL ... COUNTY FACILITY").
.county_text_extraction <- function(landmark) {
  u <- stringr::str_to_upper(landmark)
  # Peel leading segments until none of the patterns match
  repeat {
    before <- u
    u <- stringr::str_remove(u, "^[A-Z0-9]{1,4} - ")
    u <- stringr::str_remove(u, "^[A-Z]{1,4} DOC - ")
    u <- stringr::str_remove(u, "^CAP ")
    u <- stringr::str_remove(u, "^FUGITIVE OPERATIONS ON STREET ")
    u <- stringr::str_remove(u, "^ALL AREAS IN[SI]{1,2}DE ")  # INSIDE / INISDE typo
    if (identical(u, before)) break
  }
  ext <- stringr::str_remove(
    stringr::str_extract(u, "^([A-Z .'-]+?) COUNTY"),
    " COUNTY$")
  # Leftover interior " - " segments ("JUVENILE - MARICOPA") — keep the last
  stringr::str_to_title(stringr::str_remove(ext, ".* - "))
}

# ── County name parsing ───────────────────────────────────────────────────────

#' Parse county AND state from apprehension_site_landmark values.
#'
#' Returns one row per landmark with `county` and `state` (2-letter abbr),
#' including out-of-state locations so they can be mapped separately.
#' Resolution order: named regex patterns (`landmark_patterns`, first match
#' wins), airport exact-match lookup (`airport_landmarks`), then a generic
#' "AIRPORT" arm attributing state via the ", XX" suffix (falling back to the
#' report state; county unknown), general-area code lookup (`GENERAL AREA`
#' landmarks), OTHER landmark exact-match lookup, then the general "X COUNTY"
#' regex attributed to the ", XX" state suffix (falling back to the report
#' state; NA if neither is available). The default lookup tables are MN-report
#' specific; other states should pass their own tables.
.parse_landmark_county_state <- function(landmark, state_upper,
                                         landmark_patterns = NULL,
                                         ga_codes          = NULL,
                                         other_landmarks   = NULL,
                                         airports          = airport_landmarks) {
  tables <- state_landmark_tables(state_upper)
  if (is.null(landmark_patterns)) landmark_patterns <- tables$patterns
  if (is.null(ga_codes))          ga_codes          <- tables$ga
  if (is.null(other_landmarks))   other_landmarks   <- tables$other

  abbr <- toupper(unname(STATE_ABBREVS[state_upper]))
  general <- .county_text_extraction(landmark)
  suffix <- sub(", ", "", stringr::str_to_upper(
    stringr::str_extract(stringr::str_to_upper(landmark), ", [A-Z]{2}$")
  ))

  # First matching pattern row (in table order) supplies county/state;
  # state == "report" defers to the report's state.
  n <- length(landmark)
  matched <- rep(FALSE, n)
  pattern_county <- rep(NA_character_, n)
  pattern_state  <- rep(NA_character_, n)
  for (i in seq_len(nrow(landmark_patterns))) {
    hit <- stringr::str_detect(landmark, landmark_patterns$pattern[i]) & !matched
    matched <- matched | hit
    st <- if (landmark_patterns$state[i] == "report") {
      abbr
    } else if (landmark_patterns$state[i] == "suffix") {
      dplyr::coalesce(suffix, abbr)
    } else {
      landmark_patterns$state[i]
    }
    pattern_county <- dplyr::if_else(hit, landmark_patterns$county[i], pattern_county)
    pattern_state  <- dplyr::if_else(hit, st, pattern_state)
  }

  tibble::tibble(landmark = landmark) |>
    dplyr::mutate(code = stringr::word(stringr::str_to_upper(landmark), 1)) |>
    dplyr::left_join(
      ga_codes |> dplyr::select(code, ga_county = county, ga_state = state),
      by = "code"
    ) |>
    dplyr::left_join(
      other_landmarks |>
        dplyr::select(landmark, other_county = county, other_state = state),
      by = "landmark"
    ) |>
    dplyr::left_join(
      airports |>
        dplyr::select(landmark, airport_county = county, airport_state = state),
      by = "landmark"
    ) |>
    dplyr::mutate(
      county = dplyr::case_when(
        !is.na(pattern_county)                                           ~ pattern_county,
        !is.na(airport_county)                                           ~ airport_county,
        # Unrecognized airports: state via ", XX" suffix, county unknown
        stringr::str_detect(landmark, "AIRPORT")                         ~ NA_character_,
        stringr::str_detect(landmark, "GENERAL AREA")                    ~ ga_county,
        !is.na(other_county)                                             ~ other_county,
        # "X COUNTY" landmarks must carry an explicit ", XX" state suffix —
        # otherwise out-of-state jails (e.g. ADAMS COUNTY JAIL, IA) leak in
        !is.na(general)                                                  ~ general,
        TRUE                                                             ~ NA_character_
      ),
      state = dplyr::case_when(
        !is.na(pattern_state)                                            ~ pattern_state,
        !is.na(airport_state)                                            ~ airport_state,
        stringr::str_detect(landmark, "AIRPORT")                         ~ dplyr::coalesce(suffix, abbr),
        stringr::str_detect(landmark, "GENERAL AREA")                    ~ ga_state,
        !is.na(other_state)                                              ~ other_state,
        !is.na(general)                                                  ~ dplyr::coalesce(suffix, abbr),
        TRUE                                                             ~ NA_character_
      )
    ) |>
    dplyr::select(landmark, county, state)
}

#' Extract county name from apprehension_site_landmark (report state only).
#' Out-of-state locations return NA; see .parse_landmark_county_state() when
#' the state attribution is also needed.
.parse_county_landmark <- function(landmark, state_upper = NULL) {
  general <- stringr::str_to_title(
    stringr::str_remove(
      stringr::str_extract(stringr::str_to_upper(landmark),
                           "^([A-Z .'-]+) COUNTY"),
      " COUNTY$"
    )
  )

  if (!is.null(state_upper)) {
    abbr <- toupper(unname(STATE_ABBREVS[state_upper]))
    if (!is.na(abbr)) {
      geo <- .parse_landmark_county_state(landmark, state_upper)
      # Keep only in-state attributions; out-of-state office counties are
      # documented in the lookup tables but never plotted on the report map.
      return(dplyr::if_else(geo$state == abbr, geo$county, NA_character_))
    }
  }
  general
}

# ── County choropleth (leaflet) ───────────────────────────────────────────────

# Lower bounds of non-overlapping count bands: 1; 2–9; 10–49; 50–99;
# 100–499; 500–999; 1,000–4,999; 5,000–9,999; ... The last returned low is the
# floor of the open-ended top band and is <= max_n.
.county_band_lows <- function(max_n) {
  lows <- c(1, 2, 10, 50, 100, 500, 1000, 5000, 10000, 50000, 100000,
            500000, 1000000, 5000000, 10000000)
  lows[lows <= max_n]
}

.county_band_labels <- function(lows, max_n) {
  fmt <- function(x) format(x, big.mark = ",", trim = TRUE, scientific = FALSE)
  vapply(seq_along(lows), function(i) {
    if (i < length(lows)) {
      upper <- lows[i + 1] - 1
      if (upper == lows[i]) fmt(lows[i]) else paste0(fmt(lows[i]), "\u2013", fmt(upper))
    } else if (max_n == lows[i]) {
      fmt(lows[i])
    } else {
      paste0(fmt(lows[i]), "+")
    }
  }, character(1))
}

# Band index per count: i-th band is [lows[i], lows[i+1] - 1], top band is
# [lows[end], max_n]. n < lows[1] (i.e. 0) gets NA.
.county_band_index <- function(n, lows, max_n) {
  idx <- rep(NA_integer_, length(n))
  for (i in seq_along(lows)) {
    upper <- if (i < length(lows)) lows[i + 1] - 1 else max_n
    idx[n >= lows[i] & n <= upper] <- i
  }
  idx
}

# Normalize a county name for joining maps-package polygons to parsed counts
# (case, periods, spaces, "Saint" -> "St").
.norm_county_key <- function(x) {
  x <- tolower(x)
  x <- gsub("[. ']", "", x)
  sub("^saint", "st", x)
}

#' County choropleth of arrests with landmark hover detail.
#'
#' Zero-arrest counties in the report state render as transparent outlines;
#' counties with one arrest share the lightest fill; legend labels are
#' non-overlapping (1, 2–9, 10–49, 50–99, ...). Hovering a county shows its
#' bold arrest count and the top apprehension-site landmarks within it.
#' Counties in states adjoining the report state (rows in `county_counts`
#' with a different `state`) are overlaid on the same map, outlined with a
#' heavier border to set them apart.
#'
#' @param county_counts    Tibble with `county` and `n`; an optional `state`
#'   column (2-letter abbr) adds out-of-state counties to the map.
#' @param county_landmarks Tibble with `county`, `landmark`, `n` (and optional
#'   `state`); landmark counts within each county; optional.
#' @param state_name       Uppercase report-state name.
#' @param include_states   2-letter abbreviations of additional states to draw
#'   (e.g. states adjoining the report state). NULL draws every state present
#'   in `county_counts`.
#' @param n_top_landmarks  Number of landmark lines in the hover label.
#' @param fill_palette     ColorBrewer palette for positive counts.
#' @param zoom             Initial leaflet zoom.
county_choropleth <- function(county_counts,
                              county_landmarks = NULL,
                              state_name       = "MINNESOTA",
                              include_states   = NULL,
                              n_top_landmarks  = 3,
                              fill_palette     = "YlOrRd",
                              zoom             = 6) {
  base_abbr <- toupper(unname(STATE_ABBREVS[state_name]))
  if (!"state" %in% names(county_counts)) county_counts$state <- base_abbr
  county_counts$state <- toupper(county_counts$state)

  states_to_draw <- sort(unique(county_counts$state))
  if (!is.null(include_states)) {
    states_to_draw <- intersect(states_to_draw, c(base_abbr, toupper(include_states)))
  }

  abbr_to_name <- function(abbr) {
    tolower(names(STATE_ABBREVS)[match(abbr, toupper(unname(STATE_ABBREVS)))])
  }

  sf_by_state <- lapply(states_to_draw, function(ab) {
    sf <- sf::st_as_sf(
      maps::map("county", abbr_to_name(ab), fill = TRUE, plot = FALSE)
    ) |>
      dplyr::mutate(
        # strip everything before the first comma ("north dakota,", "minnesota,")
        county = tools::toTitleCase(sub("^[^,]+,", "", ID)),
        key    = paste(ab, .norm_county_key(county)),
        state  = ab
      ) |>
      dplyr::left_join(
        county_counts |>
          dplyr::filter(state == ab) |>
          dplyr::mutate(key = paste(ab, .norm_county_key(county))) |>
          dplyr::select(key, n),
        by = "key"
      ) |>
      dplyr::mutate(n = dplyr::coalesce(n, 0L))
    # adjoining states: only counties with arrests, drawn with a heavier outline
    if (ab != base_abbr) sf <- sf |> dplyr::filter(n > 0)
    sf
  })
  county_sf <- do.call(rbind, sf_by_state)

  if (!is.null(county_landmarks) && nrow(county_landmarks) > 0) {
    if (!"state" %in% names(county_landmarks)) county_landmarks$state <- base_abbr
    county_landmarks$state <- toupper(county_landmarks$state)
    lm_detail <- county_landmarks |>
      dplyr::mutate(key = paste(state, .norm_county_key(county))) |>
      dplyr::group_by(key) |>
      dplyr::slice_max(n, n = n_top_landmarks) |>
      dplyr::summarise(
        detail = paste(paste0(landmark, " ", n), collapse = "<br>"),
        .groups = "drop"
      )
    county_sf <- county_sf |> dplyr::left_join(lm_detail, by = "key")
  } else {
    county_sf$detail <- NA_character_
  }

  max_n <- max(county_sf$n, 1L)
  lows  <- .county_band_lows(max_n)
  pal   <- leaflet::colorBin(fill_palette, domain = c(0, max_n),
                             bins = c(0, lows[-1], max_n))
  band_idx <- .county_band_index(county_sf$n, lows, max_n)

  county_sf <- county_sf |>
    dplyr::mutate(
      display_name = dplyr::if_else(state == base_abbr,
                                    paste0(county, " County"),
                                    paste0(county, " County, ", state)),
      fill_col  = dplyr::if_else(n == 0, "transparent", unname(pal(lows)[band_idx])),
      line_col  = dplyr::if_else(state == base_abbr, "#888", "#444"),
      line_w    = dplyr::if_else(n == 0, 0.4, dplyr::if_else(state == base_abbr, 0.8, 1.4)),
      hover = dplyr::case_when(
        n == 0 ~ sprintf("<b>%s: 0</b>", display_name),
        is.na(detail) ~ sprintf("<b>%s: %s</b>", display_name, format(n, big.mark = ",", trim = TRUE)),
        TRUE ~ sprintf(
          "<b>%s: %s</b><br>%s",
          display_name, format(n, big.mark = ",", trim = TRUE), detail
        )
      )
    )

  # Legend: one entry per non-empty band, colors sampled at band lower bounds
  present   <- sort(unique(band_idx[!is.na(band_idx)]))
  band_lab  <- .county_band_labels(lows, max_n)
  legend_cols <- unname(pal(lows)[present])
  legend_labs <- band_lab[present]

  base_sf <- sf_by_state[[match(base_abbr, states_to_draw)]]
  bb      <- sf::st_bbox(base_sf)
  center  <- c((bb[["xmin"]] + bb[["xmax"]]) / 2, (bb[["ymin"]] + bb[["ymax"]]) / 2)
  hover_html <- lapply(county_sf$hover, htmltools::HTML)

  leaflet::leaflet(county_sf, options = leaflet::leafletOptions(minZoom = 5)) |>
    leaflet::addPolygons(
      fillColor  = ~fill_col,
      fillOpacity = 0.8,
      color      = ~line_col,
      weight     = ~line_w,
      label      = hover_html,
      labelOptions = leaflet::labelOptions(direction = "top", sticky = TRUE)
    ) |>
    leaflet::addLegend(
      colors   = legend_cols,
      labels   = legend_labs,
      values   = ~n,
      title    = "Arrests",
      position = "bottomright",
      opacity  = 0.9
    ) |>
    leaflet::setView(lng = center[1], lat = center[2], zoom = zoom)
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
