# DDP (Deportation Data Project) facility code import and cleaning.
# Extracts distinct facility codes from the DDP daily population feather file,
# cleans facility names according to project standards.

# ── Extract unique DDP facility codes ──────────────────────────────────────────

import_ddp_codes <- function(dp_data) {
  # Extract distinct detention facility codes and names from DDP daily population data
  # Args:
  #   dp_data: tibble from feather file (detention_facility_code, detention_facility, state)
  # Returns:
  #   tibble with columns: detention_facility_code, detention_facility, state

  dp_data |>
    dplyr::select(detention_facility_code, detention_facility, state) |>
    dplyr::distinct() |>
    dplyr::arrange(state, detention_facility_code)
}

# ── Clean DDP facility names ──────────────────────────────────────────────────

clean_ddp_facility_names <- function(df) {
  # Apply project-standard cleaning rules to DDP facility names.
  # Uses the same clean_facility_names() function from clean.R
  # Args:
  #   df: tibble with column 'detention_facility'
  # Returns:
  #   df with cleaned 'detention_facility' column

  df |>
    dplyr::mutate(
      detention_facility = clean_facility_names(detention_facility)
    )
}

# ── Build DDP codes table ─────────────────────────────────────────────────────

build_ddp_codes <- function(dp_data) {
  # Full pipeline: import, clean, and organize DDP facility codes
  # Args:
  #   dp_data: raw DDP daily population tibble
  # Returns:
  #   cleaned tibble of unique detention facility codes

  import_ddp_codes(dp_data) |>
    clean_ddp_facility_names()
}

# ── Manual strong DDP matches ────────────────────────────────────────────────
# Verified by visual inspection of facility names, codes, and locations.
# ── Component unit matches ───────────────────────────────────────────────────
# DDP detlocs that represent sub-units of a canonical facility rather than
# independent facilities (e.g. a gender-specific wing, an annex on the same
# campus). Each component detloc is attributed to the parent canonical_id so
# its population is counted alongside the main facility.
# Add new entries here when a DDP code is clearly a sub-unit, not a new site.

ddp_component_matches <- function() {
  tibble::tribble(
    ~canonical_id, ~detloc, ~ddp_name,
    # Guantánamo Bay: East component stays under JTF Camp Six (176).
    # Main A (GTMODCU) is now canonical 404 with its own sole entry.
    176L, "GTMOBCU", "MIGRANT OPS CENTER EAST"
  )
}

# ── Manual strong matches ────────────────────────────────────────────────────
# Canonical facilities where the fuzzy OSA matcher fails or is unreliable
# (score < 0.85, ambiguous, or excluded via ddp_exclude_fuzzy). Each entry is
# a confirmed 1:1 "sole" match. Component units belong in ddp_component_matches().

ddp_manual_strong_matches <- function() {
  tibble::tribble(
    ~canonical_id, ~detloc, ~ddp_name, ~similarity,
    233L, "BOPMIM",  "MIAMI FED.DET.CENTER",               0.97,
    103L, "GUDOCHG", "GUADELOUPE DON'T CHANGE",             NA,
    77L,  "CLARKIN", "CLARK COUNTY JAIL",                    1.0,
    324L, "MPSIPAN", "SAIPAN DEPT CORRECTIONS",              NA,
    3L,   "ADAMSMS", "ADAMS COUNTY CORRECTIONAL CENTER",     0.95,
    5L,   "ALAMCNC", "ALAMANCE CO. DET. FACILITY",           1.0,
    39L,  "BURLEND", "BURLEIGH CO. JAIL",                    NA,
    23L,  "BOPBER",  "FCI BERLIN",                           0.85,
    68L,  "CHAVENM", "CHAVEZ DET CRT",                       1.0,
    88L,  "OHNORWE", "NORTHWEST REGIONAL CORRECTIONS",       NA,
    25L,  "BLBNATX", "BLUEBONNET DET FCLTY",                 1.0,
    44L,  "CACHEUT", "CACHE CO. JAIL",                       1.0,
    97L,  "DAVISUT", "DAVIS COUNTY JAIL",                    NA,
    318L, "RADDFGA", "ROBERT A DEYTON DETENTION FAC",        NA,
    48L,  "CACTYCA", "CAL CITY ICE PROCESSING CENTER",       0.62,
    # 102 (Denver CDF II, 11901 E 30th Ave) closed after FY21; DENICDF now refers
    # solely to 101 (3130 Oakland St). 102 retains no DETLOC — it was a separate
    # building that shared the same ICE facility code while active.
    129L, "BOPATL",  "ATLANTA U.S. PEN.",                    NA,
    326L, "SLSLCUT", "Salt Lake County Jail",                 NA,
    327L, "SNDHOLD", "SND DISTRICT STAGING",                 NA,
    136L, "FLDSSFS", "FLORIDA SOFT-SIDED FACILITY-SOUTH",    NA,
    221L, "LICEPLA", "LOUISIANA ICE PROCESSING CENTER",      NA,
    366L, "STFRCTX", "SOUTH TEXAS FAM RESIDENTIAL CENTER",   NA,
    71L,  "VTCHTDN", "CHITTENDEN REG. C.",                   0.92,
    # Adelanto: main facility ADLNTCA is matched via DMCP; annex has its own canonical
    400L, "CADESVI", "DESERT VIEW ANNEX",                    NA,
    # Karnes County family facility at FM 1144: KCCDCTX is the older "Civil Detention"
    # code for canonical 190 (Residential Center). The active code is KRNRCTX → 191.
    190L, "KCCDCTX", "KARNES COUNTY CIVIL DET. FACILITY",    NA,
    # Guantánamo Bay: primary DDP code; component codes are in ddp_component_matches()
    176L, "GTMOACU", "WINDWARD HOLDING FACILITY",            NA,
    # Joe Corley: DMCP uses MONTGTX (Montgomery County, TX); DDP uses JCRLYTX
    182L, "JCRLYTX", "JOE CORLEY PROCESSING CTR",            NA,
    # Vera name "Baker C. I." doesn't fuzzy-match "Baker Correctional Institution"
     14L, "FLBAKCI", "BAKER C. I.",                          NA,
    # WV regional jails: DDP codes discovered Oct 2025–Feb 2026; fuzzy matching
    # fails due to partial name overlap across multiple WV jail names
    258L, "WVNCENT", "NORTH CENTRAL REGIONAL JAIL",          NA,
    344L, "WVSOUTH", "SOUTHERN REGIONAL JAIL",               NA,
    345L, "WVSWEST", "SOUTHWESTERN REGIONAL JAIL",           NA,
    386L, "WVWESTR", "WESTERN REGIONAL JAIL",                NA,
    # Daviess County Detention Center (KY)
    231L, "DVCSDKY", "DAVIESS COUNTY DETENTION CENTER",      NA,
    # Diamondback Correctional Facility (OK): fuzzy match fails (score < 0.85)
    106L, "OKDBACK", "DIAMONDBACK CORR FACILITY",             NA,
    # Lewisburg US Penitentiary (PA): new in Feb 12 FY26 ICE spreadsheet
    403L, "BOPLEW",  "LEWISBURG U.S. PEN.",                  NA,
    # Dilley Processing Single Adult Female (TX): reported separately in Feb 12
    # ICE spreadsheet; was previously treated as a component of 366.
    401L, "DILLSAF", "DILLEY PROCESSING SINGLE FEMALE",      NA,
    # Migrant Ops Center Main A (FPO FL): new Guantánamo facility in Feb 12;
    # GTMODCU is its primary DDP code; GTMOBCU (East) stays as component of 176.
    404L, "GTMODCU", "MIGRANT OPS CENTER MAIN AV622",        NA
    # NOTE: EPSSFTX ("El Paso Soft Sided Facility") was previously mapped here
    # to canonical 108 (Camp East Montana). Removed: these are distinct facilities.
    # EPSSFTX is a tent camp at 12501 Gateway Blvd S; canonical 108 is the
    # DOD/CDF facility at 6920 Digital Rd. EPSSFTX gets its own DDP-range ID.
  )
}

# ── Excluded DDP fuzzy matches ──────────────────────────────────────────────
# Canonical IDs where the DDP fuzzy match is incorrect. These are skipped during
# Tier 1 matching so the correct DMCP mapping (or another match) takes precedence.

ddp_exclude_fuzzy <- function() {
  c(
    # "South Central Regional Jail" (WVSCENT) fuzzy-matches to 258 (North Central
    # Regional Jail, Greenwood WV) at 0.85+, but WVSCENT is actually 337 (South
    # Central Regional Jail, Charleston WV) via DMCP.
    258L,
    # "South Texas Family Residential Center" (STFRCTX) fuzzy-matches to 341,
    # but 341 is the old canonical for that building (FY19–FY21). The same building
    # is now 366 (Dilley Immigration Processing Center), which is the correct
    # manual match already in ddp_manual_strong_matches().
    341L,
    # "Karnes County Residential Center" (190) county-matches to KARNETX, but
    # KARNETX is actually 188 (Karnes County Correctional Center, 810 Commerce St)
    # via DMCP. 190 is the family facility at FM 1144 — its correct code is KCCDCTX,
    # added as a manual match.
    190L
  )
}

# ── Confirmed keyword match IDs ─────────────────────────────────────────────
# Visually confirmed non-county keyword matches (the rest are false positives).

ddp_confirmed_keyword_ids <- function() {
  c(211L, 207L, 253L, 310L, 268L, 316L)
}

# ── Build DDP → canonical map ───────────────────────────────────────────────
# Three-tier matching of DDP DETLOCs to canonical facilities not in DMCP data.
#
# Returns one row per (canonical_id, detloc) pair:
#   canonical_id | detloc | ddp_name | match_type | ddp_role

build_ddp_canonical_map <- function(id_registry, dmcp_canonical_map,
                                     ddp_codes) {
  # Scope: canonical facilities NOT already matched via DMCP.
  # Uses id_registry (not panel_facilities) to avoid a circular dependency
  # in the targets pipeline: detloc_lookup → ddp_canonical_map → here,
  # while panel_facilities depends on facilities_keyed which needs detloc_lookup.
  dmcp_matched_ids <- unique(dmcp_canonical_map$canonical_id)
  canonical_no_dmcp <- id_registry |>
    dplyr::filter(!(canonical_id %in% dmcp_matched_ids)) |>
    dplyr::rename(facility_state = canonical_state)

  ddp_unique <- ddp_codes |>
    dplyr::select(detention_facility_code, detention_facility, state) |>
    dplyr::distinct()

  manual  <- ddp_manual_strong_matches()
  exclude <- ddp_exclude_fuzzy()

  # ── Tier 1: Fuzzy OSA ≥ 0.85 + manual strong matches ─────────────────────
  fuzzy_matches <- list()

  for (i in seq_len(nrow(canonical_no_dmcp))) {
    can_id    <- canonical_no_dmcp$canonical_id[i]
    can_name  <- canonical_no_dmcp$canonical_name[i]
    can_state <- canonical_no_dmcp$facility_state[i]

    if (can_id %in% manual$canonical_id || can_id %in% exclude) next

    ddp_state <- ddp_unique |> dplyr::filter(state == can_state)
    if (nrow(ddp_state) == 0) next

    sims <- stringdist::stringsim(
      tolower(can_name), tolower(ddp_state$detention_facility), method = "osa"
    )
    max_sim <- max(sims)
    if (max_sim >= 0.85) {
      best <- which.max(sims)
      fuzzy_matches[[length(fuzzy_matches) + 1]] <- tibble::tibble(
        canonical_id = can_id,
        detloc       = ddp_state$detention_facility_code[best],
        ddp_name     = ddp_state$detention_facility[best],
        similarity   = max_sim,
        ddp_role     = "sole"
      )
    }
  }

  components <- ddp_component_matches() |>
    dplyr::mutate(similarity = NA_real_, ddp_role = "component", match_type = "exact")

  exact_all <- dplyr::bind_rows(
    dplyr::bind_rows(fuzzy_matches),
    manual |> dplyr::mutate(ddp_role = "sole") |>
      dplyr::select(canonical_id, detloc, ddp_name, similarity, ddp_role),
    components |> dplyr::select(canonical_id, detloc, ddp_name, similarity, ddp_role)
  ) |>
    dplyr::mutate(match_type = "exact")

  already_matched <- unique(exact_all$canonical_id)

  # ── Tier 2: County-name matches ──────────────────────────────────────────
  remaining <- canonical_no_dmcp |>
    dplyr::filter(!(canonical_id %in% already_matched)) |>
    dplyr::filter(grepl("\\bcounty\\b", canonical_name, ignore.case = TRUE))

  county_matches <- list()
  for (i in seq_len(nrow(remaining))) {
    can_id    <- remaining$canonical_id[i]
    can_name  <- remaining$canonical_name[i]
    can_state <- remaining$facility_state[i]

    ddp_in_state <- ddp_unique |> dplyr::filter(state == can_state)
    if (nrow(ddp_in_state) == 0) next

    m <- regmatches(tolower(can_name),
                    regexec("(\\b[a-z]+)\\s+county\\b", tolower(can_name)))
    if (length(m[[1]]) < 2) next
    county_word <- m[[1]][2]

    for (j in seq_len(nrow(ddp_in_state))) {
      if (grepl(county_word, tolower(ddp_in_state$detention_facility[j]))) {
        county_matches[[length(county_matches) + 1]] <- tibble::tibble(
          canonical_id = can_id,
          detloc       = ddp_in_state$detention_facility_code[j],
          ddp_name     = ddp_in_state$detention_facility[j],
          similarity   = NA_real_,
          ddp_role     = "sole"
        )
        break
      }
    }
  }

  county_all <- dplyr::bind_rows(county_matches) |>
    dplyr::mutate(match_type = "partial_county")

  # ── Tier 3: Keyword matches (confirmed only) ─────────────────────────────
  confirmed_ids <- ddp_confirmed_keyword_ids()
  remaining2 <- canonical_no_dmcp |>
    dplyr::filter(!(canonical_id %in% c(already_matched, county_all$canonical_id)),
                  !grepl("\\bcounty\\b", canonical_name, ignore.case = TRUE))

  exclude_words <- c("detention", "center", "facility", "correctional",
                     "institution", "department", "jail", "processing",
                     "federal", "state", "prison", "adult")

  keyword_matches <- list()
  for (i in seq_len(nrow(remaining2))) {
    can_id    <- remaining2$canonical_id[i]
    if (!(can_id %in% confirmed_ids)) next
    can_name  <- remaining2$canonical_name[i]
    can_state <- remaining2$facility_state[i]

    ddp_in_state <- ddp_unique |> dplyr::filter(state == can_state)
    if (nrow(ddp_in_state) == 0) next

    words <- strsplit(tolower(can_name), "[^a-z0-9]+")[[1]]
    words <- words[nchar(words) >= 4]
    words <- setdiff(words, exclude_words)
    if (length(words) == 0) next

    done <- FALSE
    for (kw in words) {
      if (done) break
      for (j in seq_len(nrow(ddp_in_state))) {
        if (grepl(kw, tolower(ddp_in_state$detention_facility[j]))) {
          keyword_matches[[length(keyword_matches) + 1]] <- tibble::tibble(
            canonical_id = can_id,
            detloc       = ddp_in_state$detention_facility_code[j],
            ddp_name     = ddp_in_state$detention_facility[j],
            similarity   = NA_real_,
            ddp_role     = "sole"
          )
          done <- TRUE
          break
        }
      }
    }
  }

  keyword_all <- dplyr::bind_rows(keyword_matches) |>
    dplyr::mutate(match_type = "partial_keyword")

  # ── Combine ──────────────────────────────────────────────────────────────
  ddp_map <- dplyr::bind_rows(exact_all, county_all, keyword_all) |>
    dplyr::mutate(ddp_role = dplyr::coalesce(ddp_role, "sole")) |>
    dplyr::select(canonical_id, detloc, ddp_name, match_type, ddp_role)

  n_fac <- dplyr::n_distinct(ddp_map$canonical_id)
  message(glue::glue(
    "DDP canonical map: {nrow(ddp_map)} rows, {n_fac} unique facilities \u2014 ",
    "{sum(ddp_map$match_type == 'exact')} exact, ",
    "{sum(ddp_map$match_type == 'partial_county')} county, ",
    "{sum(ddp_map$match_type == 'partial_keyword')} keyword."
  ))

  ddp_map
}

# ── Facility-level summary of DDP daily population data ──────────────────────

ddp_facility_summary <- function(ddp_raw,
                                 from = NULL,
                                 to = NULL,
                                 codes = NULL,
                                 population_col = "n_detained") {
  # Summarise DDP daily population data to one row per facility.
  # Args:
  #   ddp_raw: full DDP daily population tibble (feather or parquet; state
  #            column is optional — present in the feather, absent in parquet)
  #   from, to: optional date bounds (Date or coercible string)
  #   codes: optional character vector of detention_facility_code values to include
  #   population_col: column to summarise (default "n_detained")
  # Returns:
  #   tibble with one row per facility: code, name, (state if present),
  #   date range, n_days, mean_pop, peak_pop, peak_date

  df <- ddp_raw

  if (!is.null(codes)) {
    df <- df |> dplyr::filter(detention_facility_code %in% codes)
  }
  if (!is.null(from)) df <- df |> dplyr::filter(date >= as.Date(from))
  if (!is.null(to))   df <- df |> dplyr::filter(date <= as.Date(to))

  if (nrow(df) == 0) {
    cli::cli_warn("No rows remain after filtering.")
    empty <- tibble::tibble(
      detention_facility_code = character(),
      detention_facility      = character(),
      n_days    = integer(),
      mean_pop  = double(),
      peak_pop  = double(),
      peak_date = as.Date(character()),
      date_from = as.Date(character()),
      date_to   = as.Date(character())
    )
    if ("state" %in% names(ddp_raw)) {
      empty <- tibble::add_column(empty, state = character(), .after = "detention_facility")
    }
    return(empty)
  }

  pop_sym    <- rlang::sym(population_col)
  has_state  <- "state" %in% names(df)
  group_vars <- c("detention_facility_code", "detention_facility")
  if (has_state) group_vars <- c(group_vars, "state")

  df |>
    dplyr::group_by(dplyr::across(dplyr::all_of(group_vars))) |>
    dplyr::summarise(
      n_days    = dplyr::n(),
      mean_pop  = mean(!!pop_sym, na.rm = TRUE),
      peak_pop  = max(!!pop_sym, na.rm = TRUE),
      peak_date = date[which.max(!!pop_sym)],
      date_from = min(date),
      date_to   = max(date),
      .groups   = "drop"
    )
}

# ── Average detained population for a facility code (deprecated) ─────────────
# Use ddp_facility_summary() instead.

ddp_average_population <- function(dp, code,
                                   from = NULL, to = NULL,
                                   population_col = "n_detained") {
  # Compute average daily detained population for one or more DDP facility codes.
  # Args:
  #   dp: DDP daily population data (must have detention_facility_code, date,
  #       detention_facility, and the column named in population_col)
  #   code: character vector of DDP detention_facility_code(s)
  #   from, to: optional date bounds (Date or coercible string)
  #   population_col: column to average (default "n_detained")
  # Returns:
  #   tibble with one row per code: code, name, date range, n_days,
  #   mean_population

  facility <- dp |>
    dplyr::filter(detention_facility_code %in% code)

  if (nrow(facility) == 0) {
    cli::cli_abort("No rows found for code(s): {.val {code}}")
  }

  if (!is.null(from)) facility <- facility |> dplyr::filter(date >= as.Date(from))
  if (!is.null(to))   facility <- facility |> dplyr::filter(date <= as.Date(to))

  facility |>
    dplyr::summarise(
      detention_facility = dplyr::first(detention_facility),
      date_from = min(date),
      date_to   = max(date),
      n_days    = dplyr::n(),
      mean_population = mean(.data[[population_col]], na.rm = TRUE),
      .by = detention_facility_code
    )
}

# ── DDP fiscal-year facility summary ─────────────────────────────────────────
# Summarizes all daily population columns to one row per facility for a given
# fiscal year. Returns ADP (mean) for each breakdown, peak population, and
# derived shares.

build_ddp_fy_summary <- function(ddp_raw, fy_start, fy_end) {
  # Args:
  #   ddp_raw: full DDP daily population tibble

  #   fy_start, fy_end: date bounds (inclusive), e.g. "2024-10-01", "2025-09-30"
  # Returns:
  #   tibble with 15 columns, one row per facility code

  df <- ddp_raw |>
    dplyr::filter(date >= as.Date(fy_start), date <= as.Date(fy_end))

  if (nrow(df) == 0) {
    cli::cli_abort("No rows in DDP data for {fy_start} to {fy_end}.")
  }

  df |>
    dplyr::group_by(detention_facility_code, detention_facility, state) |>
    dplyr::summarise(
      n_days                 = dplyr::n(),
      adp_total              = mean(n_detained, na.rm = TRUE),
      adp_midnight           = mean(n_detained_at_midnight, na.rm = TRUE),
      adp_male               = mean(n_detained_male, na.rm = TRUE),
      adp_female             = mean(n_detained_female, na.rm = TRUE),
      adp_convicted_criminal = mean(n_detained_convicted_criminal, na.rm = TRUE),
      adp_possibly_under_18  = mean(n_detained_possibly_under_18, na.rm = TRUE),
      peak_population        = max(n_detained, na.rm = TRUE),
      peak_date              = date[which.max(n_detained)],
      .groups = "drop"
    ) |>
    dplyr::mutate(
      adp_non_criminal = adp_total - adp_convicted_criminal,
      share_non_crim   = dplyr::if_else(adp_total > 0,
                                         adp_non_criminal / adp_total, NA_real_),
      share_female     = dplyr::if_else(adp_total > 0,
                                         adp_female / adp_total, NA_real_)
    )
}

# ── Assign canonical IDs to unmapped DDP facilities ──────────────────────────
# DDP facility codes not in detloc_lookup_full are assigned new canonical IDs
# in type-based blocks:
#   1054+  Non-hold, non-medical (jails, federal, dedicated, family/youth)
#   3001+  Medical facilities
#   4001+  Hotels (reserved, currently empty)

build_ddp_facility_canonical <- function(ddp_codes, detloc_lookup_full,
                                         vera_facilities) {
  mapped_detlocs <- unique(detloc_lookup_full$detloc)

  unmapped <- ddp_codes |>
    dplyr::filter(!detention_facility_code %in% mapped_detlocs) |>
    dplyr::left_join(
      vera_facilities |>
        dplyr::select(detloc, facility_name, facility_address, facility_city,
                       facility_state, facility_zip,
                       type_detailed_corrected, type_grouped_corrected,
                       latitude, longitude) |>
        dplyr::distinct(detloc, .keep_all = TRUE),
      by = c("detention_facility_code" = "detloc")
    )

  if (nrow(unmapped) == 0) {
    cli::cli_warn("No unmapped DDP facility codes found.")
    return(tibble::tibble())
  }

  # Use Vera name/address when available, fall back to DDP name
  unmapped <- unmapped |>
    dplyr::mutate(
      canonical_name = dplyr::coalesce(facility_name, detention_facility),
      facility_state = dplyr::coalesce(facility_state, state)
    )

  # Split by type block
  medical <- unmapped |>
    dplyr::filter(type_grouped_corrected == "Medical") |>
    dplyr::arrange(facility_state, detention_facility_code)

  remaining <- unmapped |>
    dplyr::filter(type_grouped_corrected != "Medical") |>
    dplyr::arrange(facility_state, detention_facility_code)

  # Assign IDs
  if (nrow(remaining) > 0) {
    ids <- setdiff(seq(1054L, 1054L + nrow(remaining)), c(1182L))
                                               # preserve previously assigned IDs
    remaining$canonical_id <- ids[seq_len(nrow(remaining))]
  }
  if (nrow(medical) > 0) {
    medical$canonical_id <- seq(3001L, length.out = nrow(medical))
  }

  result <- dplyr::bind_rows(remaining, medical) |>
    dplyr::mutate(
      id_range = dplyr::case_when(
        canonical_id >= 3001 ~ "medical",
        canonical_id >= 1054 ~ "ddp_other",
        TRUE                 ~ NA_character_
      )
    ) |>
    dplyr::select(
      canonical_id, canonical_name,
      detloc = detention_facility_code,
      facility_address, facility_city, facility_state, facility_zip,
      type_detailed_corrected, type_grouped_corrected,
      lat = latitude, lon = longitude, id_range
    ) |>
    dplyr::arrange(canonical_id)

  # Apply name/address patches for DDP facilities
  patches <- .ddp_facility_patches()
  if (nrow(patches) > 0) {
    result <- result |>
      dplyr::rows_update(patches, by = "detloc", unmatched = "ignore")
  }

  cli::cli_inform(c(
    "DDP facility canonical: {nrow(result)} new facilities",
    "*" = "{sum(result$id_range == 'ddp_other')} non-medical (IDs 1054\u2013{max(result$canonical_id[result$id_range == 'ddp_other'])})",
    "*" = "{sum(result$id_range == 'medical')} medical (IDs 3001\u2013{max(result$canonical_id[result$id_range == 'medical'])})"
  ))

  result
}


# ── DDP facility name/address patches ────────────────────────────────────────
# Hand-maintained corrections for DDP-range facilities whose Vera-sourced
# name or address is truncated or incorrect.

.ddp_facility_patches <- function() {
  dplyr::tribble(
    ~detloc,    ~canonical_name,                ~facility_address,  ~facility_zip,
    "RAPPSVA",  "Rappahannock Regional Jail",   "1745 Richmond Hwy", "22554"
  )
}

# ── Export pre-computed data for DDP comparison blog post ───────────────────

export_ddp_comparison_data <- function(ddp_raw, facilities_keyed,
                                       detloc_lookup_full, vera_facilities,
                                       facility_roster,
                                       facilities_geocoding_lookup) {

  # Pre-computes and exports RDS files to data/ddp-comparison-export/ for
  # the DDP vs ICE FY25 comparison post on the quarto website.
  # Returns: character vector of written file paths (for format = "file").

  # ── detloc-keyed type + geocoding lookup ───────────────────────────────────
  # Types from facility_roster (most authoritative: ICE panel codes → Vera
  # corrected → classify_facility_type_combined). Coordinates and addresses
  # from facilities_geocoding_lookup (facilities_geocoded_all).
  detloc_to_canonical <- detloc_lookup_full |>
    dplyr::distinct(detloc, canonical_id)

  detloc_type_lookup <- detloc_to_canonical |>
    dplyr::left_join(
      facility_roster |>
        dplyr::select(canonical_id,
                      type_grouped  = type_grouped_corrected,
                      type_detailed = type_detailed_corrected),
      by = "canonical_id"
    ) |>
    dplyr::left_join(
      facilities_geocoding_lookup,
      by = "canonical_id"
    )



  # ICE FY25
  ice_fy25 <- facilities_keyed[["FY25"]] |>
    dplyr::select(canonical_id, canonical_name, detloc, facility_name,
                  facility_city, facility_state, sum_classification_levels) |>
    dplyr::rename(ice_adp = sum_classification_levels)
  ice_fy25_ids <- unique(ice_fy25$canonical_id)

  # ICE Annual summaries
  ice_annual_adp_by_facility <- facilities_keyed |>
    dplyr::bind_rows(.id = "fiscal_year") |>
    dplyr::select(fiscal_year, canonical_id, adp) |>
    dplyr::rename(ice_adp = adp)

  ice_annual_adp_totals <- ice_annual_adp_by_facility |>
    dplyr::group_by(fiscal_year) |>
    dplyr::summarise(total_ice_adp = sum(ice_adp, na.rm = TRUE), .groups = "drop")

  # DDP FY25 summary
  ddp_fy25 <- ddp_facility_summary(ddp_raw,
                                    from = "2024-10-01", to = "2025-09-24") |>
    dplyr::filter(peak_pop > 0) |>
    dplyr::rename(ddp_adp = mean_pop)

  ddp_detloc_map <- detloc_lookup_full |> dplyr::distinct(detloc, canonical_id)

  ddp_fy25_keyed <- ddp_fy25 |>
    dplyr::left_join(ddp_detloc_map,
                     by = c("detention_facility_code" = "detloc")) |>
    dplyr::mutate(in_ice_fy25 = !is.na(canonical_id) &
                    canonical_id %in% ice_fy25_ids)

  # Daily totals
  daily_totals <- ddp_raw |>
    dplyr::group_by(date) |>
    dplyr::summarise(total_pop = sum(n_detained, na.rm = TRUE),
                     .groups = "drop") |>
    dplyr::mutate(fiscal_year = dplyr::if_else(
      as.integer(format(date, "%m")) >= 10,
      paste0("FY", as.integer(format(date, "%Y")) + 1 - 2000),
      paste0("FY", as.integer(format(date, "%Y")) - 2000)
    ))

  # Unmatched facilities
  unmatched <- ddp_fy25_keyed |>
    dplyr::filter(!in_ice_fy25) |>
    dplyr::left_join(detloc_type_lookup |> dplyr::select(detloc, type_grouped,
                                                        type_detailed),
                     by = c("detention_facility_code" = "detloc")) |>
    dplyr::mutate(
      type_grouped = dplyr::if_else(is.na(type_grouped), "Unclassified",
                                    type_grouped),
      adp_class = dplyr::if_else(ddp_adp >= 2, "ADP \u2265 2", "ADP < 2"),
      peak_class = dplyr::if_else(peak_pop >= 2, "Peak \u2265 2", "Peak < 2")
    )
  unmatched_codes <- unmatched$detention_facility_code

  # Daily unmatched (FY25 window)
  daily_unmatched <- ddp_raw |>
    dplyr::filter(detention_facility_code %in% unmatched_codes,
                  date >= as.Date("2024-10-01"),
                  date <= as.Date("2025-09-24")) |>
    dplyr::group_by(date) |>
    dplyr::summarise(total_pop = sum(n_detained, na.rm = TRUE),
                     .groups = "drop")

  # Monthly unmatched
  monthly_unmatched <- ddp_raw |>
    dplyr::filter(detention_facility_code %in% unmatched_codes,
                  date >= as.Date("2024-10-01"),
                  date <= as.Date("2025-09-24")) |>
    dplyr::left_join(detloc_type_lookup |> dplyr::select(detloc, type_grouped),
                     by = c("detention_facility_code" = "detloc")) |>
    dplyr::mutate(
      type_grouped = dplyr::if_else(is.na(type_grouped), "Unclassified",
                                    type_grouped),
      month = as.Date(format(date, "%Y-%m-01"))
    )

  # Peak FY25 with geocoded coords
  peak_fy25 <- ddp_facility_summary(ddp_raw,
                                     from = "2024-10-01", to = "2025-09-24",
                                     codes = unmatched_codes) |>
    dplyr::mutate(
      mean_pop = round(mean_pop, 1),
      adp_class = dplyr::if_else(mean_pop >= 2, "ADP \u2265 2", "ADP < 2"),
      peak_class = dplyr::if_else(peak_pop >= 2, "Peak \u2265 2", "Peak < 2")
    ) |>
    dplyr::left_join(detloc_type_lookup,
                     by = c("detention_facility_code" = "detloc")) |>
    dplyr::mutate(type_grouped = dplyr::if_else(is.na(type_grouped),
                                                 "Unclassified", type_grouped))

  # Period comparisons
  biden_from <- as.Date("2024-10-20")
  biden_to   <- as.Date("2025-01-19")
  trump_from <- as.Date("2025-07-17")
  trump_to   <- as.Date("2025-10-15")

  biden_unmatched <- ddp_facility_summary(ddp_raw,
                                           from = biden_from, to = biden_to,
                                           codes = unmatched_codes) |>
    dplyr::left_join(detloc_type_lookup |> dplyr::select(detloc, type_grouped),
                     by = c("detention_facility_code" = "detloc")) |>
    dplyr::mutate(
      type_grouped = dplyr::if_else(is.na(type_grouped), "Unclassified",
                                    type_grouped),
      adp_class = dplyr::if_else(mean_pop >= 2, "ADP \u2265 2", "ADP < 2"),
      peak_class = dplyr::if_else(peak_pop >= 2, "Peak \u2265 2", "Peak < 2"),
      period = "Biden"
    )

  trump_unmatched <- ddp_facility_summary(ddp_raw,
                                           from = trump_from, to = trump_to,
                                           codes = unmatched_codes) |>
    dplyr::left_join(detloc_type_lookup |> dplyr::select(detloc, type_grouped),
                     by = c("detention_facility_code" = "detloc")) |>
    dplyr::mutate(
      type_grouped = dplyr::if_else(is.na(type_grouped), "Unclassified",
                                    type_grouped),
      adp_class = dplyr::if_else(mean_pop >= 2, "ADP \u2265 2", "ADP < 2"),
      peak_class = dplyr::if_else(peak_pop >= 2, "Peak \u2265 2", "Peak < 2"),
      period = "Trump"
    )

  # Daily unreported (both comparison periods)
  biden_active <- biden_unmatched |>
    dplyr::filter(peak_pop > 0, peak_class == "Peak \u2265 2")
  trump_active <- trump_unmatched |>
    dplyr::filter(peak_pop > 0, peak_class == "Peak \u2265 2")
  substantive_codes <- union(biden_active$detention_facility_code,
                              trump_active$detention_facility_code)

  daily_unreported <- ddp_raw |>
    dplyr::filter(
      detention_facility_code %in% substantive_codes,
      (date >= biden_from & date <= biden_to) |
        (date >= trump_from & date <= trump_to)
    ) |>
    dplyr::left_join(detloc_type_lookup |> dplyr::select(detloc, type_grouped),
                     by = c("detention_facility_code" = "detloc")) |>
    dplyr::mutate(
      type_grouped = dplyr::if_else(is.na(type_grouped), "Unclassified",
                                    type_grouped),
      period = dplyr::case_when(
        date >= biden_from & date <= biden_to ~ "Biden final quarter",
        date >= trump_from & date <= trump_to ~ "Trump recent quarter"
      )
    ) |>
    dplyr::group_by(period, date, type_grouped) |>
    dplyr::summarise(total_pop = sum(n_detained, na.rm = TRUE),
                     .groups = "drop")

  # Write all files
  export_dir <- here::here("data", "ddp-comparison-export")
  dir.create(export_dir, showWarnings = FALSE)

  files <- list(
    ice_fy25          = ice_fy25,
    ddp_fy25          = ddp_fy25,
    ddp_fy25_keyed    = ddp_fy25_keyed,
    daily_totals      = daily_totals,
    unmatched         = unmatched,
    daily_unmatched   = daily_unmatched,
    monthly_unmatched = monthly_unmatched,
    peak_fy25         = peak_fy25,
    biden_unmatched   = biden_unmatched,
    trump_unmatched   = trump_unmatched,
    daily_unreported  = daily_unreported,
    ice_annual_adp_by_facility = ice_annual_adp_by_facility,
    ice_annual_adp_totals = ice_annual_adp_totals
  )

  paths <- vapply(names(files), function(nm) {
    path <- file.path(export_dir, paste0(nm, ".rds"))
    saveRDS(files[[nm]], path)
    path
  }, character(1), USE.NAMES = FALSE)

  cli::cli_inform(c(
    "v" = "Exported {length(paths)} RDS files to {export_dir}",
    "i" = "Run copy-data.sh in the quarto website post directory to deploy."
  ))

  paths
}

# ── SVG sparkline for daily detention population ─────────────────────────────
# Generates a tiny SVG line chart showing daily population for one facility
# over a contiguous date window. Designed for embedding in Leaflet popups.
#
# Returns an empty string for facilities with all-zero population.

make_daily_sparkline <- function(dates, values,
                                 width = 300, height = 75,
                                 pad_l = 4, pad_r = 6, pad_t = 6, pad_b = 16) {
  values[is.na(values)] <- 0L
  if (max(values) == 0L) return("")

  n       <- length(dates)
  max_val <- max(values)

  plot_w <- width  - pad_l - pad_r
  plot_h <- height - pad_t - pad_b

  # x positions spread evenly across plot width
  xs <- pad_l + (seq_len(n) - 1) / (n - 1) * plot_w
  # y positions: 0 at bottom, max at top
  ys <- pad_t + (1 - values / max_val) * plot_h

  points_str <- paste(sprintf("%.1f,%.1f", xs, ys), collapse = " ")

  # Month-boundary tick marks and labels
  months       <- format(dates, "%Y-%m")
  month_change <- which(!duplicated(months))
  tick_marks   <- vapply(month_change, function(i) {
    x <- xs[i]
    sprintf('<line x1="%.1f" y1="%d" x2="%.1f" y2="%d" stroke="#bbb" stroke-width="1"/>',
            x, height - pad_b, x, height - pad_b + 3)
  }, character(1))
  month_labels <- vapply(month_change, function(i) {
    x <- xs[i]
    lbl <- format(dates[i], "%b")
    sprintf('<text x="%.1f" y="%d" font-size="8" font-family="sans-serif" fill="#666" text-anchor="middle">%s</text>',
            x, height - 2, lbl)
  }, character(1))

  # Peak annotation (value at top-right of chart)
  peak_label <- sprintf(
    '<text x="%d" y="%d" font-size="8" font-family="sans-serif" fill="#555" text-anchor="end">peak %s</text>',
    width - 1, pad_t - 1, format(max_val, big.mark = ",")
  )

  sprintf(
    '<svg width="%d" height="%d" xmlns="http://www.w3.org/2000/svg">%s%s%s<polyline points="%s" fill="none" stroke="#4682B4" stroke-width="1.2"/></svg>',
    width, height,
    peak_label,
    paste(tick_marks, collapse = ""),
    paste(month_labels, collapse = ""),
    points_str
  )
}

# ── Import, clean, and key the Feb 12 2026 ICE spreadsheet ──────────────────
# Uses the same import/clean/aggregate/attach pipeline as the main FY19–FY26
# targets, but kept separate so it doesn't disturb the frozen FY26 panel entry.
# Three facilities whose canonical IDs are known but not in the crosswalk are
# patched in by name after the join.

build_fy26b <- function(data_file_info, clean_names_list,
                        facility_crosswalk, detloc_lookup) {
  LETTERS_PLUS <- c(LETTERS, paste0("A", LETTERS), paste0("B", LETTERS))

  fy26b_info <- tibble::tibble(
    year_name         = "FY26b",
    year              = 2026L,
    url               = NA_character_,
    local_file        = here::here("data/ice/FY26_detentionStats_02122026.xlsx"),
    sheet_name        = "Facilities FY26",
    first_header_row  = 9L,
    second_header_row = 10L,
    first_data_row    = 11L,
    right_column      = "AA",
    right_column_num  = which(LETTERS_PLUS == "AA")
  )

  # Structure is identical to the existing FY26 file — reuse its column names.
  col_names <- list(FY26b = clean_names_list[["FY26"]])

  raw    <- read_facilities_data(fy26b_info, col_names)
  clean  <- clean_all_years(list(FY26b = raw))
  agg    <- aggregate_all_years(clean)
  keyed  <- attach_canonical_ids(agg, facility_crosswalk, detloc_lookup)
  result <- keyed[["FY26b"]]

  # Patches for facilities whose canonical IDs are known but whose names differ
  # slightly from the FY19–FY26 crosswalk variants (new entries in this release).
  # fill_only: only applied when canonical_id is NA (crosswalk missed them).
  fill_only_patches <- tibble::tribble(
    ~facility_name,                      ~patch_id,
    "Sarasota County Jail",              1107L,
    "Scott County Detention. Facility",  1118L,
    "Tom Green County Jail",             1022L,
    "Mccook Detention Center",           229L,
    "Fulton County Jail Indiana",        146L
  )
  for (i in seq_len(nrow(fill_only_patches))) {
    idx <- which(tolower(result$facility_name) == tolower(fill_only_patches$facility_name[i]))
    if (length(idx) == 1L && is.na(result$canonical_id[idx])) {
      result$canonical_id[idx] <- fill_only_patches$patch_id[i]
    }
  }

  # force_patches: override even when the crosswalk assigned a wrong ID
  # (e.g. a new facility fuzzy-matched to an existing one with a similar name).
  force_patches <- tibble::tribble(
    ~facility_name,                          ~patch_id,
    "Dilley Processing Single Adult Female", 401L
  )
  for (i in seq_len(nrow(force_patches))) {
    idx <- which(tolower(result$facility_name) == tolower(force_patches$facility_name[i]))
    if (length(idx) == 1L) {
      result$canonical_id[idx] <- force_patches$patch_id[i]
    }
  }

  n_unmatched <- sum(is.na(result$canonical_id))
  cli::cli_inform("FY26b: {nrow(result)} facilities, {n_unmatched} unmatched after patches.")

  result
}

# ── FY26 DDP comparison: component pipeline functions ────────────────────────
# These produce the main targets for the FY26 DDP vs. ICE comparison.
# All use facility_roster as the canonical detloc → canonical_id lookup,
# which is more complete than detloc_lookup_full alone.
# Comparison period: Oct 1 2025 – Feb 5 2026 (ICE data-source cutoff).

build_ddp_fy26_keyed <- function(ddp_new, fy26b, detloc_lookup, detloc_lookup_full) {
  fy_start     <- "2025-10-01"
  fy_end       <- "2026-02-05"
  ice_fy26_ids <- unique(stats::na.omit(fy26b$canonical_id))

  # Use detloc_lookup_full so component codes (e.g. GTMOBCU) also resolve to a
  # canonical_id; sole/primary entries still take precedence after distinct().
  detloc_to_canonical <- detloc_lookup_full |>
    dplyr::distinct(detloc, canonical_id)

  ddp_facility_summary(ddp_new, from = fy_start, to = fy_end) |>
    dplyr::filter(peak_pop > 0) |>
    dplyr::rename(ddp_adp = mean_pop) |>
    dplyr::left_join(
      detloc_to_canonical,
      by = c("detention_facility_code" = "detloc")
    ) |>
    dplyr::mutate(in_ice_fy26 = !is.na(canonical_id) &
                    canonical_id %in% ice_fy26_ids)
}

build_daily_totals_fy26 <- function(ddp_new) {
  ddp_new |>
    dplyr::filter(date >= as.Date("2025-01-01"), # back to January 2025 for context
                  date <= as.Date( "2026-03-10")) |>  # Just for the graph,
                                # go all the way to the end of the dataset
                                # comparative analysis only goes to
                                # "2026-02-05"
    dplyr::group_by(date) |>
    dplyr::summarise(total_pop = sum(n_detained, na.rm = TRUE), .groups = "drop")
}

build_unmatched_fy26 <- function(ddp_fy26_keyed, facility_roster) {
  roster_by_detloc <- facility_roster |>
    dplyr::filter(!is.na(detloc)) |>
    dplyr::select(detloc, facility_type_wiki,
                  type_grouped  = type_grouped_corrected,
                  type_detailed = type_detailed_corrected,
                  facility_address, facility_city, facility_state)

  ddp_fy26_keyed |>
    dplyr::filter(!in_ice_fy26) |>
    dplyr::left_join(roster_by_detloc,
                     by = c("detention_facility_code" = "detloc")) |>
    dplyr::mutate(
      type_grouped = dplyr::if_else(is.na(type_grouped), "Unclassified", type_grouped),
      adp_class    = dplyr::if_else(ddp_adp >= 2, "ADP \u2265 2", "ADP < 2"),
      peak_class   = dplyr::if_else(peak_pop >= 2, "Peak \u2265 2", "Peak < 2")
    )
}

build_peak_fy26 <- function(ddp_new, unmatched_fy26, facility_roster,
                            facilities_geocoding_lookup) {
  fy_start        <- "2025-10-01"
  fy_end          <- "2026-02-05"
  unmatched_codes <- unmatched_fy26$detention_facility_code

  roster_by_detloc <- facility_roster |>
    dplyr::filter(!is.na(detloc)) |>
    dplyr::select(detloc, canonical_id, facility_type_wiki,
                  type_grouped  = type_grouped_corrected,
                  type_detailed = type_detailed_corrected,
                  facility_address, facility_city, facility_state)

  # Geocoding lookup: select only geocoding columns + zip (not address/city/state)
  geo_cols <- facilities_geocoding_lookup |>
    dplyr::select(canonical_id, facility_zip, latitude, longitude,
                  geo_city = facility_city, geo_state = facility_state)

  # Check for city/state divergence between roster and geocoding sources
  geo_addr_check <- facilities_geocoding_lookup |>
    dplyr::select(canonical_id, geo_city = facility_city, geo_state = facility_state)

  roster_addr_check <- roster_by_detloc |>
    dplyr::select(canonical_id, roster_city = facility_city, roster_state = facility_state) |>
    dplyr::distinct()

  divergence <- roster_addr_check |>
    dplyr::inner_join(geo_addr_check, by = "canonical_id") |>
    dplyr::filter(roster_city != geo_city | roster_state != geo_state)

  if (nrow(divergence) > 0) {
    cli::cli_warn(c(
      "!" = "{nrow(divergence)} canonical_id(s) have city/state divergence between facility_roster and facilities_geocoding_lookup:",
      paste0("  ", paste0(divergence$canonical_id, collapse = ", "))
    ))
  }

  ddp_facility_summary(ddp_new, from = fy_start, to = fy_end,
                       codes = unmatched_codes) |>
    dplyr::mutate(
      mean_pop   = round(mean_pop, 1),
      adp_class  = dplyr::if_else(mean_pop >= 2, "ADP \u2265 2", "ADP < 2"),
      peak_class = dplyr::if_else(peak_pop >= 2, "Peak \u2265 2", "Peak < 2")
    ) |>
    dplyr::left_join(roster_by_detloc,
                     by = c("detention_facility_code" = "detloc")) |>
    dplyr::left_join(
      geo_cols |> dplyr::select(canonical_id, facility_zip, latitude, longitude),
      by = "canonical_id"
    ) |>
    dplyr::mutate(type_grouped = dplyr::if_else(is.na(type_grouped),
                                                 "Unclassified", type_grouped))
}

# Adds pre-computed SVG sparklines (daily population time series) to peak_fy26
# for use in Leaflet map popups. Kept separate from build_peak_fy26() so the
# sparkline computation only runs at export time, not on every pipeline rebuild.
build_peak_fy26_w_sparklines <- function(ddp_new, peak_fy26) {
  fy_start        <- "2025-06-01" # Experiment: Just for the sparkline,
                                  # start with the uptick
  fy_end          <- "2026-03-10" # Just for the sparklines, go all the way to
                                  # the end of the dataset
  unmatched_codes <- peak_fy26$detention_facility_code

  sparklines <- ddp_new |>
    dplyr::filter(detention_facility_code %in% unmatched_codes,
                  date >= as.Date(fy_start),
                  date <= as.Date(fy_end)) |>
    dplyr::arrange(detention_facility_code, date) |>
    dplyr::group_by(detention_facility_code) |>
    dplyr::summarise(
      sparkline_svg = make_daily_sparkline(date, n_detained),
      .groups = "drop"
    )

  peak_fy26 |>
    dplyr::left_join(sparklines, by = "detention_facility_code")
}

# ── Export pre-computed data for DDP vs ICE FY26 comparison report ───────────
# Receives the four main pipeline targets (ddp_fy26_keyed, daily_totals_fy26,
# unmatched_fy26, peak_fy26) as arguments; adds sparklines, computes
# daily/monthly unmatched series, and writes 8 RDS files for deployment.

export_ddp_fy26_comparison_data <- function(ddp_new, fy26b,
                                            ddp_fy26_keyed, daily_totals_fy26,
                                            unmatched_fy26, peak_fy26) {
  fy_start <- "2025-10-01"
  fy_end   <- "2026-02-05"

  # ── ICE FY26 ───────────────────────────────────────────────────────────────
  ice_fy26 <- fy26b |>
    dplyr::select(canonical_id, canonical_name, detloc, facility_name,
                  facility_city, facility_state, sum_classification_levels) |>
    dplyr::rename(ice_adp = sum_classification_levels)

  # ── DDP FY26 summary (all facilities) ─────────────────────────────────────
  ddp_fy26 <- ddp_fy26_keyed |>
    dplyr::select(-canonical_id, -in_ice_fy26)

  # ── Unmatched facility codes ───────────────────────────────────────────────
  unmatched_codes <- unmatched_fy26$detention_facility_code

  # ── Daily unmatched ────────────────────────────────────────────────────────
  daily_unmatched_fy26 <- ddp_new |>
    dplyr::filter(detention_facility_code %in% unmatched_codes,
                  date >= as.Date(fy_start),
                  date <= as.Date(fy_end)) |>
    dplyr::group_by(date) |>
    dplyr::summarise(total_pop = sum(n_detained, na.rm = TRUE), .groups = "drop")

  # ── Monthly unmatched ─────────────────────────────────────────────────────
  monthly_unmatched_fy26 <- ddp_new |>
    dplyr::filter(detention_facility_code %in% unmatched_codes,
                  date >= as.Date(fy_start),
                  date <= as.Date(fy_end)) |>
    dplyr::left_join(
      unmatched_fy26 |> dplyr::select(detention_facility_code, type_grouped),
      by = "detention_facility_code"
    ) |>
    dplyr::mutate(
      type_grouped = dplyr::if_else(is.na(type_grouped), "Unclassified", type_grouped),
      month        = as.Date(format(date, "%Y-%m-01"))
    )

  # ── Peak summary with sparklines ───────────────────────────────────────────
  peak_fy26_w_sparklines <- build_peak_fy26_w_sparklines(ddp_new, peak_fy26)

  # ── Export ────────────────────────────────────────────────────────────────
  export_dir <- here::here("data", "ddp-comparison-export-fy26")
  dir.create(export_dir, showWarnings = FALSE)

  files <- list(
    ice_fy26               = ice_fy26,
    ddp_fy26               = ddp_fy26,
    ddp_fy26_keyed         = ddp_fy26_keyed,
    daily_totals_fy26      = daily_totals_fy26,
    unmatched_fy26         = unmatched_fy26,
    daily_unmatched_fy26   = daily_unmatched_fy26,
    monthly_unmatched_fy26 = monthly_unmatched_fy26,
    peak_fy26_w_sparklines = peak_fy26_w_sparklines
  )

  paths <- vapply(names(files), function(nm) {
    path <- file.path(export_dir, paste0(nm, ".rds"))
    saveRDS(files[[nm]], path)
    path
  }, character(1), USE.NAMES = FALSE)

  cli::cli_inform(c("v" = "Exported {length(paths)} RDS files to {export_dir}"))

  paths
}
