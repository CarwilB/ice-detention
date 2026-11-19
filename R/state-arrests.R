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

# datasets::state.abb / state.name exclude DC (and territories). Amplified
# fixed-value vectors with District of Columbia appended; every
# name<->abbreviation conversion and county validation in this file uses
# these, so DC counties survive validation instead of being erased.
.FULL_STATE_NAMES <- c(datasets::state.name, "District of Columbia")
.FULL_STATE_ABBRS <- c(datasets::state.abb, "DC")

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

# ── IL named landmark patterns ────────────────────────────────────────────────
# Pattern rules for Illinois landmarks that name a facility rather than a
# county. CHI GENERAL AREA, NON-SPECIFIC is deliberately NOT mapped to Cook:
# the Aug 2026 release's apprehension_city field shows those arrests are only
# ~52% Chicago (the Chicago ERO office covers the whole state).
il_landmark_patterns <- tibble::tribble(
  ~pattern,                                ~county,     ~state,
  # USP Thomson (federal) and Thomson Correctional Center (IL DOC), both in
  # Carroll County (the prison sits across the Mississippi from Clinton, IA)
  "THOMSON",                               "Carroll",   "report",
  "ILLINOIS RIVER CORRECTIONAL",           "Fulton",    "report",   # Canton, IL
  "CHICAGO (FIELD OFFICE|MCC|O'HARE)",     "Cook",      "report",
  "CHIFUGITIVE OPERATIONS",                "Cook",      "report"
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
# here when a new state's landmarks need county/state attribution. The
# optional `audit` argument appends RA-verified entries from
# data/state-arrests/landmark-audit.csv (see read_landmark_audit()).
state_landmark_tables <- function(state_upper, audit = NULL) {
  base <- if (state_upper == "TENNESSEE") {
    list(patterns = tibble::tibble(pattern = character(),
                                   county  = character(),
                                   state   = character()),
         ga    = tn_general_area_codes,
         other = tn_other_landmarks)
  } else if (state_upper == "ILLINOIS") {
    list(patterns = il_landmark_patterns,
         ga    = tibble::tibble(code   = character(),
                                location = character(),
                                county   = character(),
                                state    = character()),
         other = tibble::tibble(landmark = character(),
                                county   = character(),
                                state    = character()))
  } else {
    list(patterns = mn_landmark_patterns,
         ga    = mn_general_area_codes,
         other = mn_other_landmarks)
  }
  if (!is.null(audit) && nrow(audit) > 0) {
    mine <- audit |> dplyr::filter(state == state_upper)
    ga_rows <- mine |>
      dplyr::filter(record_type == "ga_code") |>
      dplyr::transmute(
        # Accept either the code alone ("MTG") or the full landmark string —
        # the engine joins by the landmark's first word
        code     = stringr::str_to_upper(stringr::word(stringr::str_trim(landmark), 1)),
        location = dplyr::coalesce(notes, ""),
        county,
        state    = attributed_state
      )
    pat_rows <- mine |>
      dplyr::filter(record_type == "pattern", !is.na(pattern)) |>
      dplyr::transmute(pattern, county, state = attributed_state)
    # Audit rows append AFTER the hand-maintained tables: first-match-wins
    # order keeps curated rules ahead of CSV additions
    base$ga       <- dplyr::bind_rows(base$ga, ga_rows)
    base$patterns <- dplyr::bind_rows(base$patterns, pat_rows)
  }
  base
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
  # Other columns dropped in the Aug 2026 release (no replacement available)
  for (col in c("operation", "arresting_agency", "toa_current_duty_site",
                "case_criminality")) {
    if (!col %in% names(arrests)) arrests[[col]] <- NA_character_
  }
  arrests
}

#' Project-level state fill for arrests the DDP fill left blank. Three
#' sources, tried in order:
#' 1. "AOR appears in one state": an AOR whose known-state rows name a single
#'    state at >= 99% share (mirrors the DDP rule; only 9 unambiguous AORs,
#'    most AORs span several states).
#' 2. "Landmark appears in one state (relaxed)": a landmark whose known-state
#'    rows name a single state at >= 95% share with at least 5 known rows.
#'    Catches sites just under the DDP 99% bar (e.g. DAL COUNTY JAIL is
#'    98.4% TEXAS; NSV = Nashville is 98.6% TENNESSEE).
#' 3. A ", XX" state suffix on the landmark ("DENVER, CO"), which DDP's own
#'    abbreviation rule missed.
#' Fills apprehension_state (and apprehension_state_filled_in) in place and
#' records the provenance in apprehension_state_fill_source with a
#' "(project)" suffix, keeping DDP's sources distinguishable from ours.
fill_arrest_states_aor <- function(arrests, aor_share = 0.99, lm_share = 0.95,
                                    lm_min = 5) {
  aor_map <- arrests |>
    dplyr::filter(!is.na(.data$apprehension_aor), .data$apprehension_aor != "",
                  !is.na(.data$apprehension_state)) |>
    dplyr::count(.data$apprehension_aor, .data$apprehension_state) |>
    dplyr::group_by(.data$apprehension_aor) |>
    dplyr::mutate(share = .data$n / sum(.data$n)) |>
    dplyr::slice_max(.data$n, n = 1, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::filter(.data$share >= aor_share) |>
    dplyr::select(apprehension_aor, state = apprehension_state)

  lm_map <- arrests |>
    dplyr::filter(!is.na(.data$apprehension_site_landmark),
                  !is.na(.data$apprehension_state)) |>
    dplyr::count(.data$apprehension_site_landmark, .data$apprehension_state) |>
    dplyr::group_by(.data$apprehension_site_landmark) |>
    dplyr::mutate(share = .data$n / sum(.data$n), n_known = sum(.data$n)) |>
    dplyr::slice_max(.data$n, n = 1, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::filter(.data$share >= lm_share, .data$n_known >= lm_min) |>
    dplyr::select(apprehension_site_landmark, state = apprehension_state)

  need  <- which(is.na(arrests$apprehension_state))
  if (!length(need)) return(arrests)

  aor_st <- aor_map$state[match(arrests$apprehension_aor[need], aor_map$apprehension_aor)]
  lm_st  <- lm_map$state[match(arrests$apprehension_site_landmark[need],
                               lm_map$apprehension_site_landmark)]
  suff    <- .landmark_suffix_state(arrests$apprehension_site_landmark[need])
  suff_st <- stringr::str_to_upper(
    .FULL_STATE_NAMES[match(suff, .FULL_STATE_ABBRS)])

  new_state <- dplyr::coalesce(aor_st, lm_st, suff_st)
  src <- dplyr::case_when(
    !is.na(aor_st)  ~ "AOR appears in one state (project)",
    !is.na(lm_st)   ~ "Landmark appears in one state (project, relaxed)",
    !is.na(suff_st) ~ ", XX suffix in landmark (project)"
  )
  hit <- !is.na(new_state)
  idx <- need[hit]

  arrests$apprehension_state[idx]             <- new_state[hit]
  arrests$apprehension_state_filled_in[idx]   <- new_state[hit]
  arrests$apprehension_state_fill_source[idx] <- src[hit]
  arrests
}

#' Landmark → state assignments for the nationwide report. Sites the DDP
#' fill and fill_arrest_states_aor() leave blank, resolved by hand:
#' >25 total arrests for the landmark and >70% of known-state rows agreeing
#' on one state (or the site is unambiguous by name). Evidence per row in
#' the comments; the rejects and the case list are documented in
#' nationwide-arrests.qmd's Data notes.
nationwide_landmark_states <- function() {
  tibble::tribble(
    ~landmark,                                          ~state,
    "FRD GENERAL AREA, NON-SPECIFIC",                   "COLORADO",            # 894/955 known = 94% CO; Denver AOR 87%
    "SFD GENERAL AREA, NON-SPECIFIC",                   "SOUTH DAKOTA",        # 289/321 = 90% SD; St. Paul AOR 98%
    "STL GENERAL NON-SPECIFIC",                         "MISSOURI",            # 1322/1481 = 89% MO; Chicago AOR 100%
    "CHI GENERAL AREA, NON-SPECIFIC",                   "ILLINOIS",            # 4967/5411 = 92% IL; Chicago AOR 98%
    "EPC GENERAL AREA, NON-SPECIFIC",                   "TEXAS",               # 1966/2437 = 81% TX; El Paso AOR 82%
    "ELP GENERAL AREA, NON-SPECIFIC",                   "TEXAS",               # 524/579 = 91% TX; El Paso AOR 95%
    "WAS GENERAL AREA, NON-SPECIFIC",                   "VIRGINIA",            # 5612/7434 = 76% VA; Washington AOR 99%
    "ABQ GENERAL AREA, NON-SPECIFIC",                   "NEW MEXICO",          # 289/314 = 92% NM; El Paso AOR 91%
    "Spokane CAP",                                      "WASHINGTON",          # 433/458 = 95% WA; Seattle AOR 100%
    "CAP - FCI HERLONG CALIFORNIA",                     "CALIFORNIA",          # 220/240 = 92% CA; state in the name
    "CSP SOLANO",                                       "CALIFORNIA",          # 35/37 = 95% CA; California State Prison Solano
    "PIT GENERAL AREA, NON-SPECIFIC",                   "PENNSYLVANIA",        # 1206/1355 = 89% PA; Philadelphia AOR 100%
    "BOISE ICE OFFICE",                                 "IDAHO",               # 30/32 = 94% ID; Salt Lake City AOR 97%
    "CRI GENERAL AREA, NON-SPECIFIC",                   "IOWA",                # 240/253 = 95% IA; St. Paul AOR 99%
    "POO CAP NON-CUSTODIAL ARREST",                     "OREGON",              # 94/125 = 75% OR; Seattle AOR 97%
    "GRF GENERAL AREA, NON-SPECIFIC",                   "NORTH DAKOTA",        # 185/238 = 78% ND (Grand Forks); St. Paul AOR 100%
    "REN GENERAL AREA, NON-SPECIFIC",                   "NEVADA",              # 445/517 = 86% NV (Reno); Salt Lake City AOR 97%
    "CITY OF CASPER",                                   "WYOMING",             # 409/438 = 93% WY; Denver AOR 95%
    "OAK GENERAL AREA, NON-SPECIFIC",                   "LOUISIANA",           # 271/302 = 90% LA (Oakdale); New Orleans AOR 87%
    "JNA GENERAL AREA, NON-SPECIFIC",                   "LOUISIANA",           # 402/449 = 90% LA (Jennings); New Orleans AOR 93%
    "SHERIDAN FCI",                                     "OREGON",              # 48/54 = 89% OR; Seattle AOR 100% (FCI Sheridan, OR)
    "PORTLAND FUGITIVE OPERATIONS STREET ARREST",       "OREGON",              # 1026/1156 = 89% OR; Seattle AOR 100%; cities Portland/Beaverton/Hillsboro
    "HAR GENERAL AREA, NON-SPECIFIC",                   "CONNECTICUT",         # 504/680 = 74% CT (Hartford); Boston AOR 95%
    "LOU GENERAL AREA, NON-SPECIFIC",                   "KENTUCKY",            # 453/480 = 94% KY (Louisville); Chicago AOR 96%
    "FOK GENERAL AREA, NON-SPECIFIC",                   "GEORGIA",             # 364/433 = 84% GA (Folkston); Atlanta AOR 80%
    "MEM GENERAL AREA, NON-SPECIFIC",                   "TENNESSEE",           # 1118/1404 = 80% TN (Memphis); New Orleans AOR 99%
    "RII GENERAL AREA, NON-SPECIFIC",                   "ILLINOIS",            # 85/95 = 90% IL (Rock Island); Chicago AOR 99%
    "SMITH COUNTY SHERIFFS OFFICE",                     "TEXAS",               # 16/17 = 94% TX; Dallas AOR 100%
    "LIV GENERAL AREA, NON-SPECIFIC",                   "TEXAS",               # 11/13 = 85% TX (Livingston CDF)
    "KANSAS CITY DETENTION AND REMOVAL OPERATIONS",     "TEXAS",               # 437/465 = 94% TX, San Antonio AOR 86% — see qmd note
    "USMS DC SUPERIOR COURT",                           "DISTRICT OF COLUMBIA" # DC Superior Court is in DC by name; known rows DC 23, VA 10
  )
}

#' Build the nationwide located-arrests table for nationwide-arrests.qmd:
#' fills missing states (fill_arrest_states_aor() plus the curated
#' nationwide_landmark_states() table), then runs the
#' assign_arrest_location() engine per state so every report shares the
#' same county rules. Rows with no state (no landmark, no AOR, no suffix)
#' keep NA location columns.
#'
#' Two nationwide safeguards the per-state reports don't need:
#' 1. Attributed counties are re-validated against the attributed state's
#'    (`county_state`) real county list — the landmark engine's general-area
#'    path trusts the report state, so a code like SPM (St. Paul) can
#'    fabricate "Ramsey" for Wisconsin-tagged rows.
#' 2. `map_id` is normalized to maps::map("county") IDs (no periods, no
#'    spaces, no "county"/"parish" suffix: "St. Tammany Parish" →
#'    "louisiana,sttammany"; maps spells it "De Witt" where the Census county
#'    list behind validation says "DeWitt", so spaces must go on both sides)
#'    and keyed on `county_state`, so out-of-frame attributions join to the
#'    correct state's polygons on the nationwide map.
#'
#' @param arrests      Arrests tibble (arrests_raw target).
#' @param place_county Place-county crosswalk (place_county target) or NULL.
#' @param audit        Verified landmark-audit entries (read_landmark_audit())
#'   or NULL, passed to assign_arrest_location() for every state.
#' @return Arrests with landmark_type, city, county_landmark,
#'   county_landmark_state, county, county_state, county_source,
#'   unassigned_reason, map_id appended.
build_nationwide_locations <- function(arrests, place_county = NULL,
                                       audit = NULL) {
  arrests <- fill_arrest_states_aor(arrests)

  lm  <- nationwide_landmark_states()
  new <- lm$state[match(arrests$apprehension_site_landmark, lm$landmark)]
  fill <- is.na(arrests$apprehension_state) & !is.na(new)
  arrests$apprehension_state[fill]           <- new[fill]
  arrests$apprehension_state_filled_in[fill] <- new[fill]

  states <- arrests |>
    dplyr::filter(!is.na(apprehension_state)) |>
    dplyr::distinct(apprehension_state) |>
    dplyr::pull(apprehension_state)

  located <- states |>
    purrr::map(function(st) {
      assign_arrest_location(
        arrests |> dplyr::filter(apprehension_state == st), st, place_county,
        audit = audit)
    }) |>
    purrr::list_rbind()

  # Rows with no state never entered the per-state loop; add them back with
  # NA location columns so the table stays one row per arrest
  if (any(is.na(arrests$apprehension_state))) {
    na_cols <- setdiff(names(located), names(arrests))
    na_part <- arrests |> dplyr::filter(is.na(apprehension_state))
    n_na <- nrow(na_part)
    na_like <- function(x, n) {
      if (is.list(x)) {
        purrr::map(seq_len(n), ~ NA_character_)
      } else if (is.numeric(x)) {
        rep(NA_real_, n)
      } else if (is.logical(x)) {
        rep(NA, n)
      } else {
        rep(NA_character_, n)
      }
    }
    for (col in na_cols) na_part[[col]] <- na_like(located[[col]], n_na)
    located <- dplyr::bind_rows(located, na_part)
  }

  located |>
    dplyr::mutate(
      # Counties may sit in another state than the report (landmark state
      # markers); validate against the attributed state and key map_id on it.
      # county_state is an uppercase full state name, so match case-insensitively
      # against the amplified vectors (state.name itself is title case).
      county_abbr = unname(.FULL_STATE_ABBRS[match(
        stringr::str_to_upper(county_state), toupper(.FULL_STATE_NAMES))]),
      county = dplyr::if_else(is.na(county_abbr), county,
                              purrr::map2_chr(county, county_abbr, .validate_county)),
      county_state = dplyr::if_else(is.na(county), NA_character_, county_state),
      map_id = dplyr::if_else(
        is.na(county),
        NA_character_,
        paste0(stringr::str_to_lower(county_state), ",",
               stringr::str_remove(
                 stringr::str_to_lower(stringr::str_remove_all(county, "[. ]")),
                 " (county|parish)$"))
      )
    ) |>
    dplyr::select(-county_abbr)
}

#' Letters-only uppercase key for matching county names ("St. Clair" == "ST CLAIR",
#' "Du Page" == "DUPAGE").
.county_key <- function(x) {
  x <- stringr::str_to_upper(x)
  x <- stringr::str_replace_all(x, "\\bSAINT\\b", "ST")
  stringr::str_remove_all(x, "[^A-Z]")
}

#' Known misspellings in apprehension_site_landmark, keyed by .county_key().
#' GALATIN (TN landmark typo for Gallatin, IL) and PUTNAME found in the CAP-
#  landmark audit; DEWITT/DeWitt spelling variants.
.county_typos <- c(DEWIITT = "DEWITT", GALATIN = "GALLATIN", PUTNAME = "PUTNAM")

#' County-name abbreviations seen in landmarks ("DAL COUNTY JAIL" = Dallas
#' County), keyed by .county_key(). .validate_county() expands a failed key
#' through this map and retries, so abbreviated county names validate like
#' full names. Add entries as the landmark audits surface them.
.county_abbrevs <- c(DAL = "DALLAS", YRK = "YORK")

.county_names_cache <- new.env(parent = emptyenv())

#' Full county table from the Census cartographic-boundary county file
#' (data/census/cb_2023_us_county_500k.zip, staged by the census_county_file
#' target). Read once per session; one row per county equivalent.
.all_census_counties <- function() {
  if (!is.null(.county_names_cache$all)) return(.county_names_cache$all)
  zip <- here::here("data", "census", "cb_2023_us_county_500k.zip")
  if (!file.exists(zip)) {
    stop("Census county file not found at ", zip,
         " — build the census_county_file target first (see _targets.R).")
  }
  shp <- sf::st_read(paste0("/vsizip/", zip), quiet = TRUE)
  tbl <- sf::st_drop_geometry(shp) |>
    dplyr::transmute(state = as.character(STATE_NAME), county = as.character(NAME)) |>
    dplyr::filter(!is.na(state), !is.na(county))
  .county_names_cache$all <- tbl
  tbl
}

#' Counties of a state, as named by the Census cartographic-boundary county
#' file (Census spelling, e.g. "DeWitt", "DeKalb"), keyed by .county_key().
#' Replaces maps::county.fips, which lacks AK/HI/PR and carries pre-2022
#' Connecticut counties. State may be passed in any case (report states are
#' uppercase; .validate_county() passes state.name title case). Used to
#' validate generic "X COUNTY" parses and normalize county spellings so typos
#' and cross-state name collisions return NA instead of fabricating geography.
#' NOTE: downstream joins that match county names against maps-package polygon
#' IDs must normalize both sides (.norm_county_key() or the map_id
#' dot-and-space stripping), since Census spellings drop the spaces maps
#' inserts ("De Witt" IL is Census "DeWitt"; "Du Page" is "DuPage").
.state_county_names <- function(state_upper) {
  key <- stringr::str_to_upper(state_upper)
  cached <- .county_names_cache[[key]]
  if (!is.null(cached)) return(cached)
  tbl <- .all_census_counties()
  nm <- unique(tbl$county[stringr::str_to_upper(tbl$state) == key])
  out <- stats::setNames(nm, .county_key(nm))
  .county_names_cache[[key]] <- out
  out
}

#' Validate a generically parsed county name against the real county list of
#' the state it would be attributed to. Returns the Census spelling
#' ("DeWitt", "DeKalb") on a hit, NA otherwise — typos and counties that
#' exist only in other states (IA jails leaking into an IL report, "Cap-"
#' debris, "Galatin") return NA instead of fabricating geography.
.validate_county <- function(county, state_abbr) {
  st_name <- .FULL_STATE_NAMES[match(toupper(state_abbr), .FULL_STATE_ABBRS)]
  purrr::pmap_chr(list(county, st_name), function(cty, st) {
    if (is.na(cty) || is.na(st)) return(NA_character_)
    valid <- .state_county_names(st)
    key <- dplyr::coalesce(unname(.county_typos[.county_key(cty)]), .county_key(cty))
    # County abbreviations ("DAL" for Dallas): expand and retry once
    if (!key %in% names(valid)) {
      exp <- .county_abbrevs[key]
      if (!is.na(exp)) key <- .county_key(exp)
    }
    if (key %in% names(valid)) unname(valid[key]) else NA_character_
  })
}

# ── County name extraction from landmark text ────────────────────────────────
# Shared text-extraction step used by .parse_landmark_county_state() and
# .parse_county_landmark(). Landmarks often carry a leading arresting-office
# code ("CAP - GIBSON COUNTY JAIL TN STATE"), sometimes with interior
# segments ("CAP - JUVENILE - MARICOPA COUNTY ...", "A - WI DOC - BROWN
# COUNTY ..."), or a narrative phrase ("FUGITIVE OPERATIONS ON STREET DEWITT
# COUNTY, ILLINOIS", "FRU - ALL AREAS INSIDE KARNES COUNTY"). Peel those
# prefixes so the capture is the county name alone. The extraction is
# non-greedy so it stops at the FIRST "COUNTY" or "PARISH" (Louisiana
# landmarks name parishes; landmarks can name a county twice, e.g. "VOLUSIA
# COUNTY JAIL ... COUNTY FACILITY").
.county_text_extraction <- function(landmark) {
  u <- stringr::str_to_upper(landmark)
  # Peel leading segments until none of the patterns match
  repeat {
    before <- u
    u <- stringr::str_remove(u, "^[A-Z0-9]{1,4}\\s*-\\s*")   # "CAP - " and "CAP-"
    u <- stringr::str_remove(u, "^[A-Z]{1,4}\\s*DOC\\s*-\\s*")
    u <- stringr::str_remove(u, "^CAP\\s+")
    u <- stringr::str_remove(u, "^FUGITIVE OPERATIONS ON STREET ")
    u <- stringr::str_remove(u, "^ALL AREAS IN[SI]{1,2}DE ")  # INSIDE / INISDE typo
    if (identical(u, before)) break
  }
  ext <- stringr::str_remove(
    stringr::str_extract(u, "^([A-Z0-9 .()'-]+?) (COUNTY|PARISH)"),
    " (COUNTY|PARISH)$")
  # Leftover interior " - " segments ("JUVENILE - MARICOPA") — keep the last
  ext <- stringr::str_remove(ext, ".* - ")
  # Leading arrest-program codes with parentheses ("287(G)-KNOX") — drop the
  # code and its trailing hyphen
  stringr::str_to_title(stringr::str_remove(ext, "^[A-Z0-9()]+\\)*-"))
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
#' specific; other states should pass their own tables. The optional `audit`
#' argument appends RA-verified entries from the landmark-audit CSV.
.parse_landmark_county_state <- function(landmark, state_upper,
                                         landmark_patterns = NULL,
                                         ga_codes          = NULL,
                                         other_landmarks   = NULL,
                                         airports          = airport_landmarks,
                                         audit             = NULL) {
  tables <- state_landmark_tables(state_upper, audit)
  if (is.null(landmark_patterns)) landmark_patterns <- tables$patterns
  if (is.null(ga_codes))          ga_codes          <- tables$ga
  if (is.null(other_landmarks))   other_landmarks   <- tables$other

  abbr <- toupper(unname(STATE_ABBREVS[state_upper]))
  general <- .county_text_extraction(landmark)
  # State markers in the landmark text: a trailing/inline state tag ("..., XX",
  # "XX STATE", "XX DOC", a bare trailing "XX", a trailing full state name)
  # names the arrest's actual state even without matching the report state, so
  # out-of-state counties are never attributed to the report state.
  comma_suffix <- stringr::str_remove(
    stringr::str_extract(stringr::str_to_upper(landmark), ", [A-Z]{2}$"), ", ")
  # "X CO" county abbreviations are resolved BEFORE state-marker detection: a
  # trailing/inline "CO" preceded by a county of the report state is a county
  # ("TEXAS DEPT OF CRIMINAL JUSTICE, WALKER CO" = Walker County, TX), not a
  # Colorado marker. The ", CO" comma form never matches the county regex, so
  # genuine Colorado suffixes are untouched.
  co_county <- .co_county_token(landmark, abbr, comma_suffix)
  markers_state <- .landmark_state_markers(stringr::str_to_upper(landmark))$state
  suffix <- dplyr::coalesce(comma_suffix, markers_state)
  # Suppress only a BARE trailing-CO marker that is really a county
  # abbreviation; "CO STATE"/"XX DOC" style markers are kept
  suffix <- dplyr::if_else(
    !is.na(co_county) & is.na(comma_suffix) &
      !is.na(markers_state) & markers_state == "CO",
    NA_character_, suffix)
  co_state <- dplyr::coalesce(suffix, abbr)

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
      # Generic "X COUNTY" parses are validated against the attributed state's
      # county list (suffix state if present, else the report state)
      general_state = dplyr::coalesce(suffix, abbr),
      general       = .validate_county(general, general_state),
      county = dplyr::case_when(
        !is.na(pattern_county)                                           ~ pattern_county,
        !is.na(airport_county)                                           ~ airport_county,
        # Unrecognized airports: state via ", XX" suffix, county unknown
        stringr::str_detect(landmark, "AIRPORT")                         ~ NA_character_,
        # General-area code rows fire only when the state's ga table matched;
        # otherwise "{name} COUNTY GENERAL AREA" falls through to the
        # validated generic parse below (the old code short-circuited here
        # with ga_county = NA and never reached `general`)
        stringr::str_detect(landmark, "GENERAL AREA") & !is.na(ga_county) ~ ga_county,
        !is.na(other_county)                                             ~ other_county,
        # "X CO" county abbreviations ("WALKER CO", "BECKHAM CO")
        !is.na(co_county)                                                ~ co_county,
        !is.na(general)                                                  ~ general,
        TRUE                                                             ~ NA_character_
      ),
      state = dplyr::case_when(
        !is.na(pattern_state)                                            ~ pattern_state,
        !is.na(airport_state)                                            ~ airport_state,
        stringr::str_detect(landmark, "AIRPORT")                         ~ dplyr::coalesce(suffix, abbr),
        stringr::str_detect(landmark, "GENERAL AREA") & !is.na(ga_county) ~ ga_state,
        !is.na(other_state)                                              ~ other_state,
        !is.na(co_county)                                                ~ co_state,
        !is.na(general)                                                  ~ general_state,
        # State marker with no county ("WV DOC- Salem Correctional Center"):
        # still record the marker state so out-of-state rows are labeled
        !is.na(suffix)                                                   ~ suffix,
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

# ── Arrest type column ────────────────────────────────────────────────────────
# From the state-data-cleaning branch. apprehension_method_simple
# (At-Large / Custodial / Other / 287(g)) when available (Aug 2026+),
# otherwise apprehension_type (Targeted / Collateral, March 2026 and earlier).
.arrest_type_col <- function(arr) {
  if ("apprehension_method_simple" %in% names(arr) &&
      any(!is.na(arr$apprehension_method_simple))) {
    "apprehension_method_simple"
  } else {
    "apprehension_type"
  }
}

.count_arrest_type <- function(arr) {
  # Column keeps the historical name `apprehension_type` even when backed by
  # apprehension_method_simple, so the ice-arrests-by-state website and any
  # downstream consumers see a stable schema.
  arr |>
    dplyr::count(apprehension_type = .data[[.arrest_type_col(arr)]], sort = TRUE) |>
    dplyr::mutate(pct = round(n / sum(n) * 100, 1))
}

# ── City -> county (Aug 2026 release: apprehension_city_common_case) ─────────
# Ported from the state-data-cleaning branch (developed in
# il-location-exploration.R). City attribution is tried before the landmark
# parser because the city field is filled for ~99% of Aug-release arrests.

#' Census place-county crosswalk from cartographic boundary files.
#'
#' Overlays each state's places on counties and returns one row per place with
#' its primary county (largest share of area) and whether a second county holds
#' >= 10% of the area (multi_county). Where two places share a name within a
#' state (e.g. Willowbrook village, DuPage / Willowbrook CDP, Will), the
#' incorporated place is kept.
#'
#' @param place_zips  Paths to cb_YYYY_SS_place_500k.zip files (one per state).
#' @param county_zip  Path to cb_YYYY_us_county_500k.zip.
build_place_county <- function(place_zips, county_zip) {
  read_zip_shp <- function(zip) sf::st_read(paste0("/vsizip/", zip), quiet = TRUE)

  counties <- read_zip_shp(county_zip) |>
    sf::st_transform(5070) |>
    dplyr::select(STATEFP, county = NAME)

  purrr::map(place_zips, \(zip) {
    places <- read_zip_shp(zip) |> sf::st_transform(5070)
    st_fp <- unique(places$STATEFP)
    suppressWarnings(sf::st_intersection(
      places |> dplyr::select(place = NAME, place_type = NAMELSAD, place_geoid = GEOID),
      counties |> dplyr::filter(STATEFP %in% st_fp) |> dplyr::select(county))) |>
      dplyr::mutate(state = stringr::str_to_upper(unique(places$STATE_NAME)),
                    area = as.numeric(sf::st_area(geometry))) |>
      sf::st_drop_geometry()
  }) |>
    purrr::list_rbind() |>
    dplyr::group_by(place_geoid) |>
    dplyr::mutate(share = area / sum(area)) |>
    dplyr::ungroup() |>
    # drop slivers from boundary misalignment
    dplyr::filter(share >= 0.01) |>
    dplyr::group_by(state, place_geoid, place, place_type) |>
    dplyr::arrange(dplyr::desc(share), .by_group = TRUE) |>
    dplyr::summarise(
      primary_county = dplyr::first(county),
      primary_share  = round(dplyr::first(share), 3),
      n_counties     = sum(share >= 0.10),
      counties       = paste0(county, " (", round(share * 100), "%)", collapse = ", "),
      .groups = "drop") |>
    dplyr::mutate(city_key     = .city_key(place),
                  multi_county = n_counties > 1,
                  incorporated = !stringr::str_detect(place_type, "CDP$")) |>
    dplyr::group_by(state, city_key) |>
    dplyr::arrange(dplyr::desc(incorporated), .by_group = TRUE) |>
    dplyr::slice_head(n = 1) |>
    dplyr::ungroup()
}

#' Letters-only key for matching city names ("Mt. Prospect" == "Mount Prospect").
.city_key <- function(x) {
  x |>
    stringr::str_to_upper() |>
    stringr::str_replace_all("\\bSAINT\\b", "ST") |>
    stringr::str_replace_all("\\bMOUNT\\b", "MT") |>
    stringr::str_replace_all("\\bFORT\\b", "FT") |>
    stringr::str_remove_all("[^A-Z]")
}

#' Reviewed city spelling fixes (variant -> standard), by state.
#' Saint/Mount/spacing variants are also handled by .city_key(); the Illinois
#' table covers typos found by fuzzy matching in the branch's
#' il-location-exploration.R. Add tables for other states as their cities are
#' reviewed.
.city_fixes <- function() {
  il <- tibble::tribble(
    ~variant,              ~city,
    "Saint Charles",       "St. Charles",
    "Charles",             "St. Charles",
    "St. Charls",          "St. Charles",
    "East Saint Louis",    "East St. Louis",
    "Mt Prospect",         "Mount Prospect",
    "Mt. Prospect",        "Mount Prospect",
    "Desplaines",          "Des Plaines",
    "Des Plains",          "Des Plaines",
    "Downer's Grove",      "Downers Grove",
    "Downers Grokve",      "Downers Grove",
    "Oaklawn",             "Oak Lawn",
    "Roundlake",           "Round Lake",
    "Lasalle",             "La Salle",
    "Laporte",             "La Porte",
    "Bridge Port",         "Bridgeport",
    "O Fallon",            "O'Fallon",
    "Ofallon",             "O'Fallon",
    "Scott Airforce Base", "Scott Air Force Base",
    "Chcago",   "Chicago", "Chgicago", "Chicago", "Chiacgo",  "Chicago",
    "Chiago",   "Chicago", "Chicaco",  "Chicago", "Chicafo",  "Chicago",
    "Chicao",   "Chicago", "Chicgao",  "Chicago", "Chiciago", "Chicago",
    "Chicagogo","Chicago",
    "Cicro",            "Cicero",            "Cisero",            "Cicero",
    "Auarora",          "Aurora",            "Auora",             "Aurora",
    "Elgih",            "Elgin",             "Elginc",            "Elgin",
    "Waukegun",         "Waukegan",          "Waukengan",         "Waukegan",
    "St. Waukegan",     "Waukegan",
    "Joilet",           "Joliet",            "Juliet",            "Joliet",
    "Palantine",        "Palatine",          "Paletine",          "Palatine",
    "Palentine",        "Palatine",
    "Addision",         "Addison",           "Adisson",           "Addison",
    "Benseville",       "Bensenville",       "Bensville",         "Bensenville",
    "Boilingbrook",     "Bolingbrook",       "Bolinsbook",        "Bolingbrook",
    "Springfiled",      "Springfield",
    "Arlinghton Heights","Arlington Heights",
    "Stokie",           "Skokie",
    "Wehaton",          "Wheaton",
    "Beywyn",           "Berwyn",            "Brewin",            "Berwyn",
    "Schamburg",        "Schaumburg",
    "Woodbridge",       "Woodridge",
    "Hlendale Heights", "Glendale Heights",
    "Propspect Heights","Prospect Heights",
    "Brideview",        "Bridgeview",
    "Grantie City",     "Granite City",
    "Kanakee",          "Kankakee",
    "Colllinsville",    "Collinsville",
    "Romeville",        "Romeoville",
    "Cheser",           "Chester",
    "Lamont",           "Lemont",
    "Elk Groove",       "Elk Grove",
    "Algoquin",         "Algonquin",
    "Calument City",    "Calumet City",      "Caulmet City",      "Calumet City",
    "Calument",         "Calumet",
    "Chesterson",       "Chesterton",
    "Villa Groves",     "Villa Grove",
    "Montogomery",      "Montgomery",
    "Caseyvile",        "Caseyville",
    "River Forrest",    "River Forest",
    "Hodgekins",        "Hodgkins",
    "Pinkneyville",     "Pinckneyville",
    "Weswetville",      "Westville",
    "Oak Bar",          "Oak Park"
  )
  dplyr::mutate(il, state = "ILLINOIS", .before = 1)
}

#' Names that aren't Census places but imply one (neighbourhoods,
#' abbreviations, typos), by state. Used only for the county lookup.
.city_aliases <- function() {
  tibble::tribble(
    ~state,     ~city,                ~place,
    "ILLINOIS", "Little Village",     "Chicago",
    "ILLINOIS", "Avondale",           "Chicago",
    "ILLINOIS", "Bucktown",           "Chicago",
    "ILLINOIS", "Ravenswood",         "Chicago",
    "ILLINOIS", "West Elsdon",        "Chicago",
    "ILLINOIS", "Chicago Chi",        "Chicago",
    "ILLINOIS", "Summit Argo",        "Summit",
    "ILLINOIS", "Elk Grove",          "Elk Grove Village",
    "ILLINOIS", "Arlington Hts",      "Arlington Heights",
    "ILLINOIS", "Rolling Meadowschi", "Rolling Meadows",
    "ILLINOIS", "Carpersville",       "Carpentersville",
    "ILLINOIS", "Dixmoore",           "Dixmoor",
    "ILLINOIS", "Lmilemont",          "Lemont"
  )
}

#' Clean apprehension city names: squish, "Unknown" -> NA, reviewed fixes.
clean_arrest_city <- function(city, state) {
  city <- stringr::str_squish(city)
  city[stringr::str_to_upper(city) %in% c("UNKNOWN", "UNKKNOWN", "UNKOWN", "UNSURE")] <- NA_character_
  fixes <- .city_fixes()
  fixed <- fixes$city[match(paste(state, city), paste(fixes$state, fixes$variant))]
  dplyr::coalesce(fixed, city)
}

#' Assign county from cleaned city via the place-county crosswalk.
#' Returns one row per input: matched Census place, its primary county
#' (Census spelling), multi-county flag, and all counties with area shares.
.county_from_city <- function(city, state, place_county) {
  aliases <- .city_aliases()
  place <- aliases$place[match(paste(state, city), paste(aliases$state, aliases$city))]
  key <- .city_key(dplyr::coalesce(place, city))
  idx <- match(paste(state, key), paste(place_county$state, place_county$city_key))
  tibble::tibble(
    place        = place_county$place[idx],
    place_geoid  = place_county$place_geoid[idx],
    county_city  = place_county$primary_county[idx],
    multi_county = dplyr::coalesce(place_county$multi_county[idx], FALSE),
    city_counties = place_county$counties[idx]
  )
}

# ── Location assignment (city-first, landmark fallback) ──────────────────────

#' RA-verified landmark matches, read from data/state-arrests/landmark-audit.csv.
#'
#' Research assistants verify proposed landmark -> county matches (see issue 16)
#' and record them in the audit CSV; this loader is the only way audit entries
#' enter the pipeline. Only rows with `status == "verified"` are used.
#'
#' CSV columns:
#' - `state` — report state, uppercase full name ("TENNESSEE").
#' - `landmark` — for `record_type == "exact"`: the full landmark string exactly
#'   as it appears in the data (matched case-insensitively); for
#'   `"ga_code"`: the office code alone ("MTG"); ignored for `"pattern"`.
#' - `record_type` — "exact" (checked before the engine, via the override
#'   path), "ga_code" (appended to the state's general-area code table), or
#'   "pattern" (regex appended to the state's pattern table; regex goes in
#'   `pattern`).
#' - `county` — county name, Census spelling preferred ("St. Louis");
#'   normalized for the override path.
#' - `pattern` — regex for `record_type == "pattern"` rows.
#' - `attributed_state` — 2-letter abbr of the state the county belongs to;
#'   blank = the report state.
#' - `status` — "proposed" | "verified" | "rejected". Only "verified" rows
#'   load.
#' - `verified_by`, `verified_date`, `notes` — provenance.
#'
#' @param path CSV path (a `format = "file"` target so edits rebuild downstream
#'   targets).
#' @param status Which status to load; "verified" in the pipeline.
#' @return Tibble of verified entries, or NULL when the file is missing or has
#'   no rows of the requested status.
landmark_audit_path <- function() {
  here::here("data", "state-arrests", "landmark-audit.csv")
}

read_landmark_audit <- function(path = landmark_audit_path(), status = "verified") {
  if (!file.exists(path)) return(NULL)
  raw <- readr::read_csv(path, show_col_types = FALSE,
                         col_types = readr::cols(.default = readr::col_character()))
  out <- raw |>
    dplyr::filter(
      status == .env$status,
      !is.na(county),
      # "pattern" rows carry their regex in `pattern`, not a landmark string
      dplyr::if_else(record_type %in% "pattern",
                     !is.na(pattern), !is.na(landmark))
    ) |>
    dplyr::mutate(
      # Uppercase full state name -> 2-letter abbr; blank means report state
      attributed_state = dplyr::if_else(
        is.na(attributed_state) | attributed_state == "",
        .state_name_to_abbr(state),
        stringr::str_to_upper(attributed_state)
      )
    )
  if (nrow(out) == 0) NULL else out
}

#' Uppercase full state name -> 2-letter abbreviation (the inverse of
#' .abbr_to_state_name()). Unknown names (territories) return NA.
.state_name_to_abbr <- function(name) {
  unname(.FULL_STATE_ABBRS[match(stringr::str_to_upper(name),
                                 toupper(.FULL_STATE_NAMES))])
}

#' Manually reviewed landmark -> county assignments: hand-maintained entries
#' below, plus RA-verified "exact" rows from the audit CSV (read_landmark_audit()).
#' Checked before the pattern-table engine in .county_from_landmark(). County
#' spelling is normalized via .state_county_names(), so "St. Clair", "St
#' Clair" and "DuPage" all work.
.landmark_county_overrides <- function(audit = NULL) {
  base <- tibble::tribble(
    ~state, ~landmark, ~county
  )
  if (!is.null(audit) && nrow(audit) > 0) {
    base <- dplyr::bind_rows(
      base,
      audit |>
        dplyr::filter(record_type == "exact") |>
        dplyr::transmute(state, landmark, county)
    )
  }
  base |>
    dplyr::mutate(dplyr::across(dplyr::everything(), as.character))
}

#' County AND attributed state from apprehension_site_landmark: manual audit
#' overrides first, then the full pattern-table engine
#' (.parse_landmark_county_state). Out-of-state landmark hits are NOT
#' discarded: they keep their resolved county and state (e.g.
#' "A - WI DOC - BROWN COUNTY JAIL" on an Illinois report row -> Brown, WI).
#' The report state supplies suffix-less generic parses and manual overrides.
#' Consumers decide what to plot by comparing `state` with the report state.
#' Returns a tibble with `county` (Census spelling) and `state` (2-letter abbr),
#' one row per landmark.
.county_from_landmark <- function(landmark, state, audit = NULL) {
  ov <- .landmark_county_overrides(audit)
  ov <- ov[ov$state == state, ]
  manual <- ov$county[match(stringr::str_to_upper(landmark),
                            stringr::str_to_upper(ov$landmark))]
  valid <- .state_county_names(state)
  manual <- unname(valid[.county_key(manual)])
  geo <- .parse_landmark_county_state(landmark, state, audit = audit)
  report_abbr <- toupper(unname(STATE_ABBREVS[state]))
  tibble::tibble(
    county = dplyr::coalesce(manual, geo$county),
    state  = dplyr::if_else(!is.na(manual), report_abbr, geo$state)
  )
}

#' Uppercase full state name ("TEXAS", "DISTRICT OF COLUMBIA") from a 2-letter
#' abbreviation. Unknown abbreviations (territories: PR, GU, ...) pass through
#' uppercased; NA stays NA. Matches the apprehension_state vocabulary.
.abbr_to_state_name <- function(abbr) {
  dplyr::if_else(
    abbr %in% .FULL_STATE_ABBRS,
    stringr::str_to_upper(
      .FULL_STATE_NAMES[match(abbr, .FULL_STATE_ABBRS)]),
    # Unknown abbreviations (territories) pass through uppercased; NA stays NA
    stringr::str_to_upper(abbr)
  )
}

#' Broad landmark category (from the state-data-cleaning branch).
classify_landmark_type <- function(landmark) {
  lm <- stringr::str_to_upper(landmark)
  dplyr::case_when(
    is.na(lm)                                                     ~ "Missing",
    stringr::str_detect(lm, "FIELD OFFICE|ICE OFFICE|ERO OFFICE") ~ "ICE office",
    stringr::str_detect(lm, "MCC|PENITENTIARY|\\bBOP\\b|\\bFCI\\b") ~ "Federal prison",
    stringr::str_detect(lm, "STATE DOC|\\bDOC\\b|CORRECTIONAL")   ~ "State prison",
    stringr::str_detect(lm, "AIRPORT|O'HARE")                     ~ "Airport",
    stringr::str_detect(lm, "COURT")                              ~ "Court",
    stringr::str_detect(lm, "POLICE")                             ~ "Police department",
    stringr::str_detect(lm, "FUGITIVE OP.*COUNTY")                ~ "Fugitive ops (county named)",
    stringr::str_detect(lm, "FUGITIVE OP")                        ~ "Fugitive ops (no county)",
    stringr::str_detect(lm, "GENERAL (AREA,? )?NON-SPECIFIC")     ~ "Field office area, non-specific",
    stringr::str_detect(lm, "STREET ARREST")                      ~ "Street arrest",
    stringr::str_detect(lm, "COUNTY|JAIL|SHERIFF|DETENTION")      ~ "County jail / sheriff",
    TRUE                                                          ~ "Other"
  )
}

#' County named by a trailing/inline "X CO" abbreviation ("TEXAS DEPT OF
#' CRIMINAL JUSTICE, WALKER CO", "W DIST OK ... BECKHAM CO NON CRIM"), or NA.
#' The token before the word-boundary "CO" is tried as a two-word then
#' one-word county name (with .county_typos/.county_abbrevs expansion) against
#' the report state, then against an explicit comma-suffix state if the
#' landmark carries one ("HUNTSVILLE POLICE DEPT, WALKER CO, TX" on any
#' report). The comma-suffix form ", CO" itself never matches (the regex
#' requires the county name directly before "CO"), so a genuine Colorado
#' suffix is never swallowed. When this returns a county, a bare trailing
#' "CO" must NOT be read as a Colorado state marker.
#'
#' @return The validated county name (maps spelling), or NA. Vectorized: one
#'   value per landmark.
.co_county_token <- function(landmark, report_abbr, comma_suffix = NULL) {
  if (length(landmark) == 0) return(character(0))
  u <- stringr::str_to_upper(landmark)
  # "CO STATE" / "CO DOC" are state-corrections markers, never counties
  m2 <- stringr::str_match(u, "\\b([A-Z]{2,}) ([A-Z]{2,}) CO\\b(?!( STATE| DOC))")
  m1 <- stringr::str_match(u, "\\b([A-Z]{2,}) CO\\b(?!( STATE| DOC))")
  two <- dplyr::if_else(is.na(m2[, 2]) | is.na(m2[, 3]), NA_character_,
                        paste(m2[, 2], m2[, 3]))
  cand <- purrr::pmap(list(two, m1[, 2]), function(a, b)
    unique(na.omit(c(a, b))))
  if (is.null(comma_suffix)) comma_suffix <- rep(NA_character_, length(landmark))
  purrr::pmap_chr(list(cand, report_abbr, comma_suffix), function(cc, rabbr, csuff) {
    states <- unique(c(rabbr, csuff))
    states <- states[!is.na(states)]
    for (cd in cc) {
      for (st in states) {
        hit <- .validate_county(stringr::str_to_title(cd), st)
        if (!is.na(hit)) return(hit)
      }
    }
    NA_character_
  })
}

#' State named by a landmark's state markers — the shared implementation used
#' by .parse_landmark_county_state() and .landmark_suffix_state(). Detects,
#' in priority order (the trailing ", XX" comma suffix is handled by callers):
#' inline/trailing "XX STATE" / "XX STATE DOC" ("CAP-YORK COUNTY PRISON PA
#' STATE", "..., IL STATE DOC"); "XX DOC" state-DOC markers ("A - WI DOC -
#' BROWN COUNTY JAIL", "ORL - ... FL DOC") — the Wisconsin/Florida/etc. DOC
#' facility named in the landmark pins the arrest's state ahead of the county
#' search; a bare trailing 2-letter abbr ("CAP-FRANKLIN COUNTY JAIL PA"); and
#' a trailing full state name ("...MADISON COUNTY, MISSOURI"). Returns
#' 2-letter abbreviations (uppercase) or NA.
.landmark_state_markers <- function(u) {
  full_names <- .FULL_STATE_NAMES
  full_abbrs <- .FULL_STATE_ABBRS

  st <- stringr::str_match(u, "\\b([A-Z]{2}) STATE(?: DOC)?\\b")[, 2]
  doc <- stringr::str_match(u, "\\b([A-Z]{2}) DOC\\b")[, 2]
  doc <- dplyr::if_else(doc %in% unname(full_abbrs), doc, NA_character_)
  bare <- stringr::str_match(u, "\\b([A-Z]{2})$")[, 2]
  bare <- dplyr::if_else(bare %in% unname(full_abbrs), bare, NA_character_)
  full <- stringr::str_match(u, ", ([A-Z ]+)$")[, 2]
  full <- stringr::str_to_title(stringr::str_trim(
    stringr::str_remove(full, "\\s+STATE( DOC)?$")))
  full <- full_abbrs[match(full, full_names)]

  list(state = dplyr::coalesce(st, doc, bare, full))
}

#' State named by a landmark's state markers ("..., XX", "XX STATE", "XX DOC",
#' "..., MISSOURI"), as a 2-letter abbr, or NA if none. Used to label arrests
#' that document an out-of-state location. When `report_state` is supplied, a
#' bare trailing "CO" that is really a county abbreviation of the report state
#' ("WALKER CO" on a Texas report) is suppressed — it is a county, not a
#' Colorado marker.
.landmark_suffix_state <- function(landmark, report_state = NULL) {
  u <- stringr::str_to_upper(landmark)
  comma <- stringr::str_remove(stringr::str_extract(u, ", [A-Z]{2}$"), ", ")
  markers <- .landmark_state_markers(u)$state
  out <- dplyr::coalesce(comma, markers)
  if (!is.null(report_state)) {
    abbr <- toupper(unname(STATE_ABBREVS[report_state]))
    suppress_co <- !is.na(.co_county_token(landmark, abbr))
    out <- dplyr::if_else(suppress_co & is.na(comma) & !is.na(markers) & markers == "CO",
                          NA_character_, out)
  }
  out
}

#' Add location columns to arrests for one state. Used by
#' build_state_arrests_data() so the report and any exploration scripts share
#' the same rules.
#'
#' County comes from the apprehension city when the release has it and a
#' place-county crosswalk exists for the state; otherwise (or when the city
#' doesn't match a place) from the landmark. County names use the maps
#' package spelling ("Du Page") to match the choropleth.
#'
#' @param arrests      Arrests for `state` (standardized column names).
#' @param state        Uppercase state name, e.g. "ILLINOIS".
#' @param place_county Place-county crosswalk (place_county target) or NULL.
#' @param audit        Verified landmark-audit entries (read_landmark_audit())
#'   or NULL.
#' @return `arrests` with landmark_type, city, place, place_geoid,
#'   county_city, multi_county, city_counties, county_landmark,
#'   county_landmark_state, county, county_state, county_source,
#'   unassigned_reason. `county` is filled whenever either layer resolves it,
#'   including landmark attributions in another state; `county_state` names
#'   the state the county belongs to (the report state for city matches and
#'   suffix-less landmark parses). Consumers filter `county_state == state`
#'   for per-state maps; the nationwide map keeps every row.
assign_arrest_location <- function(arrests, state, place_county = NULL,
                                   audit = NULL) {
  has_city <- "apprehension_city_common_case" %in% names(arrests) &&
    !is.null(place_county) && state %in% place_county$state

  lm_geo <- .county_from_landmark(arrests$apprehension_site_landmark, state,
                                  audit = audit)
  out <- arrests |>
    dplyr::mutate(
      landmark_type   = classify_landmark_type(apprehension_site_landmark),
      city            = if (has_city) clean_arrest_city(apprehension_city_common_case, state)
                        else NA_character_,
      county_landmark = lm_geo$county,
      county_landmark_state = .abbr_to_state_name(lm_geo$state)
    )

  if (has_city) {
    out <- dplyr::bind_cols(out, .county_from_city(out$city, state, place_county))
    # Normalize spellings against the state's Census county list
    # ("st clair" -> "St. Clair")
    valid <- .state_county_names(state)
    out$county_city <- unname(valid[.county_key(out$county_city)])
  } else {
    out <- dplyr::mutate(out, place = NA_character_, place_geoid = NA_character_,
                         county_city = NA_character_, multi_county = FALSE,
                         city_counties = NA_character_)
  }

  lm_upper <- stringr::str_to_upper(out$apprehension_site_landmark)
  suffix_state <- .landmark_suffix_state(out$apprehension_site_landmark, state)
  out |>
    dplyr::mutate(
      county = dplyr::coalesce(county_city, county_landmark),
      county_state = dplyr::case_when(
        !is.na(county_city)     ~ state,
        !is.na(county_landmark) ~ county_landmark_state,
        TRUE                    ~ NA_character_
      ),
      county_source = dplyr::case_when(
        !is.na(county_city)     ~ "City",
        !is.na(county_landmark) ~ "Landmark",
        TRUE                    ~ NA_character_
      ),
      unassigned_reason = dplyr::case_when(
        !is.na(county)                                       ~ NA_character_,
        has_city & !is.na(city)                              ~ "City not found in state",
        has_city & is.na(lm_upper)                           ~ "No city or landmark",
        is.na(lm_upper)                                      ~ "Missing landmark",
        stringr::str_detect(lm_upper, "GENERAL (AREA|NON-SPECIFIC)") ~ "Field office area, non-specific",
        stringr::str_detect(lm_upper, "FUGITIVE OP")         ~ "Fugitive operations, no county",
        !is.na(suffix_state) & suffix_state != state         ~ "Out-of-state landmark, county unresolved",
        TRUE                                                 ~ "Other / unresolved"
      )
    )
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
    arrest_type   = .count_arrest_type(minor_arr),
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
#' @param place_county  Place-county crosswalk (place_county target) or NULL;
#'   enables city-based county attribution for the Aug 2026 release.
#' @return Named list of tables and flow data for the QMD.
build_state_arrests_data <- function(arrests, stays, detloc_lookup, geo_all,
                                      state        = "MINNESOTA",
                                      cutoff       = as.Date("2025-01-20"),
                                      place_county = NULL,
                                      audit        = NULL) {
  cutoff <- as.Date(cutoff)

  state_arr <- arrests |>
    dplyr::filter(
      apprehension_state == state,
      apprehension_date  >= cutoff,
      duplicate_likely   == FALSE | is.na(duplicate_likely)
    )

  # City-first county attribution (falls back to the landmark engine)
  locations <- assign_arrest_location(state_arr, state, place_county,
                                      audit = audit)

  state_ids <- state_arr |>
    dplyr::filter(!is.na(unique_identifier)) |>
    dplyr::pull(unique_identifier) |>
    unique()

  state_stays <- stays |>
    dplyr::filter(unique_identifier %in% state_ids,
                  as.Date(stay_book_in_date_time) >= cutoff)

  geo_lkp <- .build_geo_lookup_sa(detloc_lookup, geo_all)

  # County counts for choropleth (city-attributed where possible), with the
  # branch's at-large / multi-county-city detail columns. Out-of-frame
  # attributions (county in another state, via landmark state markers) are
  # excluded so per-state coverage denominators are unchanged; they are
  # reported separately as `out_of_frame`.
  county_counts <- locations |>
    dplyr::filter(county_state == state, !is.na(county)) |>
    dplyr::count(county,
                 at_large = (.data[[.arrest_type_col(locations)]] == "At-Large Arrest"),
                 from_multi_county_city = multi_county) |>
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
    arrest_type        = .count_arrest_type(state_arr),
    criminality        = state_arr |>
      dplyr::count(apprehension_criminality, sort = TRUE) |>
      dplyr::mutate(pct = round(n / sum(n) * 100, 1)),
    county_counts      = county_counts,
    out_of_frame       = locations |>
      dplyr::filter(!is.na(county_state), county_state != state) |>
      dplyr::count(county_state, sort = TRUE),
    city_counts        = locations |>
      dplyr::filter(!is.na(city)) |>
      dplyr::count(city, sort = TRUE) |>
      dplyr::mutate(pct = round(n / sum(n) * 100, 1)),
    county_source      = locations |>
      dplyr::count(county_source, sort = TRUE) |>
      dplyr::mutate(pct = round(n / sum(n) * 100, 1)),
    unassigned_reasons = locations |>
      dplyr::filter(!is.na(unassigned_reason)) |>
      dplyr::count(unassigned_reason, sort = TRUE) |>
      dplyr::mutate(pct = round(n / sum(n) * 100, 1)),
    unassigned_landmarks = locations |>
      dplyr::filter(!is.na(unassigned_reason), !is.na(apprehension_site_landmark)) |>
      dplyr::count(unassigned_reason, apprehension_site_landmark, landmark_type, sort = TRUE),
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
