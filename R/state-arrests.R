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

# ── County name parsing ───────────────────────────────────────────────────────

#' Letters-only uppercase key for matching county names ("St. Clair" == "ST CLAIR").
.county_key <- function(x) {
  x <- stringr::str_to_upper(x)
  x <- stringr::str_replace_all(x, "\\bSAINT\\b", "ST")
  stringr::str_remove_all(x, "[^A-Z]")
}

#' Known misspellings in apprehension_site_landmark, keyed by .county_key().
.county_typos <- c(DEWIITT = "DEWITT")

#' Counties of a state as named by maps::map("county"), title-cased to match
#' the choropleth join in state-arrests.qmd (e.g. "St Clair", "Du Page").
.state_county_names <- function(state_upper) {
  poly <- maps::county.fips$polyname
  poly <- poly[startsWith(poly, paste0(stringr::str_to_lower(state_upper), ","))]
  nm <- unique(stringr::str_remove(stringr::str_remove(poly, "^[^,]+,"), ":.*$"))
  stats::setNames(stringr::str_to_title(nm), .county_key(nm))
}

#' State named in a trailing ", XX" / ", STATE NAME" suffix, or NA if none.
.landmark_suffix_state <- function(landmark) {
  suffix <- stringr::str_to_upper(stringr::str_match(landmark, ",\\s*([^,]+)$")[, 2])
  suffix <- stringr::str_trim(stringr::str_remove(suffix, "\\s+STATE( DOC)?$"))
  full <- stringr::str_to_upper(c(datasets::state.name, "District of Columbia"))
  abb  <- c(datasets::state.abb, "DC")
  dplyr::case_when(
    suffix %in% full ~ suffix,
    suffix %in% abb  ~ full[match(suffix, abb)],
    TRUE             ~ NA_character_
  )
}

#' Generic "<NAME> COUNTY" parse, validated against the state's county list.
#' Tries the longest run of up to 4 words before "COUNTY" first, so prefixes
#' like "FUGITIVE OPERATIONS ON STREET" are dropped and "LAKE OF THE WOODS"
#' survives. Landmarks whose suffix names a different state return NA.
.parse_county_generic <- function(landmark, state_upper) {
  valid <- .state_county_names(state_upper)
  suffix_state <- .landmark_suffix_state(landmark)

  parse_one <- function(lm, sfx) {
    if (is.na(lm) || (!is.na(sfx) && sfx != state_upper)) return(NA_character_)
    before <- stringr::str_match(stringr::str_to_upper(lm), "^(.*?)\\s+COUNTY\\b")[, 2]
    if (is.na(before)) return(NA_character_)
    words <- stringr::str_split(stringr::str_trim(
      stringr::str_replace_all(before, "[^A-Z' .]", " ")), "\\s+")[[1]]
    for (k in rev(seq_len(min(4L, length(words))))) {
      key <- .county_key(paste(utils::tail(words, k), collapse = " "))
      key <- dplyr::coalesce(unname(.county_typos[key]), key)
      if (key %in% names(valid)) return(unname(valid[key]))
    }
    NA_character_
  }

  u <- unique(data.frame(landmark, suffix_state))
  u$county <- mapply(parse_one, u$landmark, u$suffix_state, USE.NAMES = FALSE)
  u$county[match(paste(landmark, suffix_state), paste(u$landmark, u$suffix_state))]
}

#' Extract county name from apprehension_site_landmark.
#' Uses a validated generic "XXXXX COUNTY" parse, plus state-specific rules for
#' named places (field offices, prisons, airports) that imply a county.
#' Field-office-wide landmarks (e.g. "CHI GENERAL AREA, NON-SPECIFIC") cover
#' several states and are deliberately left NA.
.parse_county_landmark <- function(landmark, state_upper = NULL) {
  if (is.null(state_upper)) {
    return(stringr::str_to_title(stringr::str_remove(
      stringr::str_extract(stringr::str_to_upper(landmark), "^([A-Z .'-]+) COUNTY"),
      " COUNTY$")))
  }
  general <- .parse_county_generic(landmark, state_upper)
  lm <- stringr::str_to_upper(landmark)

  if (state_upper == "MINNESOTA") {
    dplyr::case_when(
      stringr::str_detect(lm, "SPM GENERAL|ST\\.? PAUL|US MARSHALS, MN|WHIPPLE") ~ "Ramsey",
      stringr::str_detect(lm, "BLOOMINGTON|MINNEAPOLIS|HENNEPIN")                ~ "Hennepin",
      TRUE                                                                       ~ general
    )
  } else if (state_upper == "ILLINOIS") {
    dplyr::case_when(
      # USP Thomson (federal) and Thomson Correctional Center (IL DOC)
      stringr::str_detect(lm, "THOMSON")                                         ~ "Carroll",
      # Canton, IL
      stringr::str_detect(lm, "ILLINOIS RIVER CORRECTIONAL")                     ~ "Fulton",
      # Chicago field office (101 W Congress Pkwy), MCC Chicago, O'Hare
      stringr::str_detect(lm, "CHICAGO (FIELD OFFICE|MCC|O'HARE)")               ~ "Cook",
      TRUE                                                                       ~ general
    )
  } else {
    general
  }
}

# ── Arrests schema ────────────────────────────────────────────────────────────

#' Normalize DDP arrests releases to one schema.
#'
#' The Aug 2026 release renamed apprehension_site_landmark -> event_landmark
#' and replaced apprehension_state with apprehension_state_filled_in /
#' apprehension_state_original; it dropped apprehension_type, operation,
#' arresting_agency, toa_current_duty_site and case_criminality. This maps the
#' new names back to the old ones (keeping the new columns) and adds dropped
#' columns as NA so downstream code written for the March release still runs.
standardize_ddp_arrests <- function(arrests) {
  if (!"apprehension_site_landmark" %in% names(arrests) &&
      "event_landmark" %in% names(arrests)) {
    arrests$apprehension_site_landmark <- arrests$event_landmark
  }
  if (!"apprehension_state" %in% names(arrests) &&
      "apprehension_state_filled_in" %in% names(arrests)) {
    # filled_in agrees with _original wherever both exist and covers more rows
    arrests$apprehension_state <- arrests$apprehension_state_filled_in
  }
  for (col in c("apprehension_type", "operation", "arresting_agency",
                "toa_current_duty_site", "case_criminality")) {
    if (!col %in% names(arrests)) arrests[[col]] <- NA_character_
  }
  arrests
}

#' Arrest type column for summary tables: apprehension_method_simple
#' (At-Large / Custodial / Other / 287(g)) when available (Aug 2026+),
#' otherwise apprehension_type (Targeted / Collateral, March 2026 and earlier).
.arrest_type_col <- function(arr) {
  if ("apprehension_method_simple" %in% names(arr) &&
      any(!is.na(arr$apprehension_method_simple))) {
    "apprehension_method_simple"
  } else {
    "apprehension_type"
  }
}

.count_arrest_type <- function(arr) {
  arr |>
    dplyr::count(arrest_type = .data[[.arrest_type_col(arr)]], sort = TRUE) |>
    dplyr::mutate(pct = round(n / sum(n) * 100, 1))
}

# ── City -> county (Aug 2026 release: apprehension_city_common_case) ─────────
# Developed in il-location-exploration.R.

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
#' Saint/Mount/spacing variants are also handled by .city_key(); this table
#' covers typos found by fuzzy matching in il-location-exploration.R.
#' Left alone on purpose: Palestine (real IL village), Elk Grove vs Elk Grove
#' Village (unclear), out-of-state towns.
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

# ── Single location parser (report + il-location-exploration.R) ─────────────

#' Manually reviewed landmark -> county assignments from the landmark audit
#' (data/il-landmark-audit/, GitHub issue). Checked before the regex rules in
#' .parse_county_landmark(). County spelling is normalized, so "St. Clair",
#' "St Clair" and "DuPage" all work.
.landmark_county_overrides <- function() {
  tibble::tribble(
    ~state, ~landmark, ~county
  ) |>
    dplyr::mutate(dplyr::across(dplyr::everything(), as.character))
}

#' County from landmark: manual audit overrides first, then the regex parser.
#' Returns maps-package county names ("Du Page", "St Clair").
.county_from_landmark <- function(landmark, state) {
  ov <- .landmark_county_overrides()
  ov <- ov[ov$state == state, ]
  manual <- ov$county[match(stringr::str_to_upper(landmark), stringr::str_to_upper(ov$landmark))]
  valid <- .state_county_names(state)
  manual <- unname(valid[.county_key(manual)])
  dplyr::coalesce(manual, .parse_county_landmark(landmark, state))
}

#' Broad landmark category (developed in il-location-exploration.R).
classify_landmark_type <- function(landmark) {
  lm <- stringr::str_to_upper(landmark)
  dplyr::case_when(
    is.na(lm)                                                   ~ "Missing",
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

#' Add location columns to arrests for one state. Used by
#' build_state_arrests_data() and il-location-exploration.R so both use the
#' same rules.
#'
#' County comes from the apprehension city when the release has it and a
#' place-county crosswalk exists for the state; otherwise (or when the city
#' doesn't match a place) from the landmark. County names use the maps
#' package spelling ("Du Page") to match the choropleth.
#'
#' @param arrests      Arrests for `state` (standardized column names).
#' @param state        Uppercase state name, e.g. "ILLINOIS".
#' @param place_county Place-county crosswalk (place_county target) or NULL.
#' @return `arrests` with landmark_type, city, place, place_geoid,
#'   county_city, multi_county, city_counties, county_landmark, county,
#'   county_source, unassigned_reason.
assign_arrest_location <- function(arrests, state, place_county = NULL) {
  has_city <- "apprehension_city_common_case" %in% names(arrests) &&
    !is.null(place_county) && state %in% place_county$state

  out <- arrests |>
    dplyr::mutate(
      landmark_type   = classify_landmark_type(apprehension_site_landmark),
      city            = if (has_city) clean_arrest_city(apprehension_city_common_case, state)
                        else NA_character_,
      county_landmark = .county_from_landmark(apprehension_site_landmark, state)
    )

  if (has_city) {
    out <- dplyr::bind_cols(out, .county_from_city(out$city, state, place_county))
    # Census names ("DuPage", "McHenry") -> maps names ("Du Page", "Mchenry")
    valid <- .state_county_names(state)
    out$county_city <- unname(valid[.county_key(out$county_city)])
  } else {
    out <- dplyr::mutate(out, place = NA_character_, place_geoid = NA_character_,
                         county_city = NA_character_, multi_county = FALSE,
                         city_counties = NA_character_)
  }

  lm_upper <- stringr::str_to_upper(out$apprehension_site_landmark)
  suffix_state <- .landmark_suffix_state(out$apprehension_site_landmark)
  out |>
    dplyr::mutate(
      county = dplyr::coalesce(county_city, county_landmark),
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
        !is.na(suffix_state) & suffix_state != state         ~ "Located in another state",
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
#' @param place_county  Optional place-county crosswalk (place_county target).
#'   When supplied and the arrests have apprehension_city_common_case, county
#'   comes from the city, falling back to the landmark parser.
#' @return Named list of tables and flow data for the QMD.
build_state_arrests_data <- function(arrests, stays, detloc_lookup, geo_all,
                                      state  = "MINNESOTA",
                                      cutoff = as.Date("2025-01-20"),
                                      place_county = NULL) {
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

  # County for the choropleth (city first, then landmark); see assign_arrest_location()
  arr_county <- assign_arrest_location(state_arr, state, place_county)
  type_col <- .arrest_type_col(state_arr)
  county_counts <- arr_county |>
    dplyr::filter(!is.na(county)) |>
    dplyr::group_by(county) |>
    dplyr::summarise(
      n = dplyr::n(),
      at_large = sum(.data[[type_col]] %in% "At-Large Arrest"),
      from_multi_county_city = sum(multi_county & county_source %in% "City"),
      .groups = "drop") |>
    dplyr::arrange(dplyr::desc(n))
  county_source_counts <- arr_county |>
    dplyr::count(county_source) |>
    dplyr::mutate(pct = round(n / sum(n) * 100, 1))
  city_counts <- arr_county |>
    dplyr::filter(!is.na(city)) |>
    dplyr::count(city, county_city, multi_county, sort = TRUE)

  # Arrests the choropleth can't place, by reason; pct is of all state arrests
  unassigned <- arr_county |>
    dplyr::filter(is.na(county)) |>
    dplyr::mutate(reason = unassigned_reason)
  n_all <- nrow(state_arr)
  unassigned_reasons <- unassigned |>
    dplyr::count(reason, sort = TRUE) |>
    dplyr::mutate(pct = round(n / n_all * 100, 1))
  unassigned_landmarks <- unassigned |>
    dplyr::mutate(apprehension_site_landmark = dplyr::coalesce(city, apprehension_site_landmark)) |>
    dplyr::count(apprehension_site_landmark, reason, sort = TRUE) |>
    dplyr::mutate(pct = round(n / n_all * 100, 1))

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
    county_source      = county_source_counts,
    city_counts        = city_counts,
    unassigned_reasons   = unassigned_reasons,
    unassigned_landmarks = unassigned_landmarks,
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
