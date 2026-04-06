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
# ddp_role: "sole" = 1:1; "primary"/"component" = one canonical facility
# maps to multiple DDP DETLOCs (sum components for facility-level totals).

ddp_manual_strong_matches <- function() {
  tibble::tribble(
    ~canonical_id, ~detloc, ~ddp_name, ~similarity, ~ddp_role,
    233L, "BOPMIM",  "MIAMI FED.DET.CENTER",               0.97, "sole",
    103L, "GUDOCHG", "GUADELOUPE DON'T CHANGE",             NA,   "sole",
    77L,  "CLARKIN", "CLARK COUNTY JAIL",                    1.0,  "sole",
    324L, "MPSIPAN", "SAIPAN DEPT CORRECTIONS",              NA,   "sole",
    3L,   "ADAMSMS", "ADAMS COUNTY CORRECTIONAL CENTER",     0.95, "sole",
    5L,   "ALAMCNC", "ALAMANCE CO. DET. FACILITY",           1.0,  "sole",
    39L,  "BURLEND", "BURLEIGH CO. JAIL",                    NA,   "sole",
    23L,  "BOPBER",  "FCI BERLIN",                           0.85, "sole",
    68L,  "CHAVENM", "CHAVEZ DET CRT",                       1.0,  "sole",
    88L,  "OHNORWE", "NORTHWEST REGIONAL CORRECTIONS",       NA,   "sole",
    25L,  "BLBNATX", "BLUEBONNET DET FCLTY",                 1.0,  "sole",
    44L,  "CACHEUT", "CACHE CO. JAIL",                       1.0,  "sole",
    97L,  "DAVISUT", "DAVIS COUNTY JAIL",                    NA,   "sole",
    318L, "RADDFGA", "ROBERT A DEYTON DETENTION FAC",        NA,   "sole",
    48L,  "CACTYCA", "CAL CITY ICE PROCESSING CENTER",       0.62, "sole",
    # 102 (Denver CDF II, 11901 E 30th Ave) closed after FY21; DENICDF now refers
    # solely to 101 (3130 Oakland St). 102 retains no DETLOC — it was a separate
    # building that shared the same ICE facility code while active.
    129L, "BOPATL",  "ATLANTA U.S. PEN.",                    NA,   "sole",
    327L, "SNDHOLD", "SND DISTRICT STAGING",                 NA,   "sole",
    136L, "FLDSSFS", "FLORIDA SOFT-SIDED FACILITY-SOUTH",    NA,   "sole",
    221L, "LICEPLA", "LOUISIANA ICE PROCESSING CENTER",      NA,   "sole",
    366L, "STFRCTX", "SOUTH TEXAS FAM RESIDENTIAL CENTER",   NA,   "sole",
    71L,  "VTCHTDN", "CHITTENDEN REG. C.",                   0.92, "sole",
    # Adelanto: main facility ADLNTCA is matched via DMCP; annex has a separate DDP code
    105L, "CADESVI", "DESERT VIEW ANNEX",                     NA,   "component",
    # Karnes County family facility at FM 1144: KCCDCTX is the older "Civil Detention"
    # code for canonical 190 (Residential Center). The active code is KRNRCTX → 191.
    190L, "KCCDCTX", "KARNES COUNTY CIVIL DET. FACILITY",     NA,   "sole",
    # Guantánamo Bay: one canonical facility (JTF Camp Six) → three DETLOCs
    176L, "GTMOACU", "WINDWARD HOLDING FACILITY",            NA,   "primary",
    176L, "GTMOBCU", "MIGRANT OPS CENTER EAST",              NA,   "component",
    176L, "GTMODCU", "MIGRANT OPS CENTER MAIN AV622",        NA,   "component",
    # Joe Corley: DMCP uses MONTGTX (Montgomery County, TX); DDP uses JCRLYTX
    182L, "JCRLYTX", "JOE CORLEY PROCESSING CTR",            NA,   "sole"
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

  exact_all <- dplyr::bind_rows(
    dplyr::bind_rows(fuzzy_matches),
    manual |> dplyr::select(canonical_id, detloc, ddp_name, similarity, ddp_role)
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
  #   ddp_raw: full DDP daily population tibble
  #   from, to: optional date bounds (Date or coercible string)
  #   codes: optional character vector of detention_facility_code values to include
  #   population_col: column to summarise (default "n_detained")
  # Returns:
  #   tibble with one row per facility: code, name, state, date range,

  #   n_days, mean_pop, peak_pop, peak_date

  df <- ddp_raw

  if (!is.null(codes)) {
    df <- df |> dplyr::filter(detention_facility_code %in% codes)
  }
  if (!is.null(from)) df <- df |> dplyr::filter(date >= as.Date(from))
  if (!is.null(to))   df <- df |> dplyr::filter(date <= as.Date(to))

  if (nrow(df) == 0) {
    cli::cli_warn("No rows remain after filtering.")
    return(tibble::tibble(
      detention_facility_code = character(),
      detention_facility = character(),
      state = character(),
      n_days = integer(),
      mean_pop = double(),
      peak_pop = double(),
      peak_date = as.Date(character()),
      date_from = as.Date(character()),
      date_to = as.Date(character())
    ))
  }

  pop_sym <- rlang::sym(population_col)

  df |>
    dplyr::group_by(detention_facility_code, detention_facility, state) |>
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
    remaining$canonical_id <- seq(1054L, length.out = nrow(remaining))
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
    ~detloc,    ~canonical_name,                ~facility_address,
    "RAPPSVA",  "Rappahannock Regional Jail",   "1745 Jefferson Davis Highway"
  )
}

# ── Export pre-computed data for DDP comparison blog post ───────────────────

export_ddp_comparison_data <- function(ddp_raw, facilities_keyed,
                                       detloc_lookup_full, vera_facilities) {
  # Pre-computes and exports 11 RDS files to data/ddp-comparison-export/ for

  # the DDP vs ICE FY25 comparison post on the quarto website.
  # Returns: character vector of written file paths (for format = "file").

  vera_type_lookup <- vera_facilities |>
    dplyr::select(detloc, type_grouped = type_grouped_corrected,
                  type_detailed = type_detailed_corrected,
                  latitude, longitude) |>
    dplyr::distinct(detloc, .keep_all = TRUE)

  # ICE FY25
  ice_fy25 <- facilities_keyed[["FY25"]] |>
    dplyr::select(canonical_id, canonical_name, detloc, facility_name,
                  facility_city, facility_state, sum_classification_levels) |>
    dplyr::rename(ice_adp = sum_classification_levels)
  ice_fy25_ids <- unique(ice_fy25$canonical_id)

  # DDP FY25 summary
  ddp_fy25 <- ddp_facility_summary(ddp_raw,
                                    from = "2024-10-01", to = "2025-09-24") |>
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
    dplyr::left_join(vera_type_lookup |> dplyr::select(detloc, type_grouped,
                                                        type_detailed),
                     by = c("detention_facility_code" = "detloc")) |>
    dplyr::mutate(
      type_grouped = dplyr::if_else(is.na(type_grouped), "Unclassified",
                                    type_grouped),
      adp_class = dplyr::if_else(ddp_adp >= 2, "ADP \u2265 2", "ADP < 2")
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
    dplyr::left_join(vera_type_lookup |> dplyr::select(detloc, type_grouped),
                     by = c("detention_facility_code" = "detloc")) |>
    dplyr::mutate(
      type_grouped = dplyr::if_else(is.na(type_grouped), "Unclassified",
                                    type_grouped),
      month = as.Date(format(date, "%Y-%m-01"))
    )

  # Peak FY25 with Vera coords
  peak_fy25 <- ddp_facility_summary(ddp_raw,
                                     from = "2024-10-01", to = "2025-09-24",
                                     codes = unmatched_codes) |>
    dplyr::mutate(
      mean_pop = round(mean_pop, 1),
      adp_class = dplyr::if_else(mean_pop >= 2, "ADP \u2265 2", "ADP < 2")
    ) |>
    dplyr::left_join(vera_type_lookup,
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
    dplyr::left_join(vera_type_lookup |> dplyr::select(detloc, type_grouped),
                     by = c("detention_facility_code" = "detloc")) |>
    dplyr::mutate(
      type_grouped = dplyr::if_else(is.na(type_grouped), "Unclassified",
                                    type_grouped),
      adp_class = dplyr::if_else(mean_pop >= 2, "ADP \u2265 2", "ADP < 2"),
      period = "Biden"
    )

  trump_unmatched <- ddp_facility_summary(ddp_raw,
                                           from = trump_from, to = trump_to,
                                           codes = unmatched_codes) |>
    dplyr::left_join(vera_type_lookup |> dplyr::select(detloc, type_grouped),
                     by = c("detention_facility_code" = "detloc")) |>
    dplyr::mutate(
      type_grouped = dplyr::if_else(is.na(type_grouped), "Unclassified",
                                    type_grouped),
      adp_class = dplyr::if_else(mean_pop >= 2, "ADP \u2265 2", "ADP < 2"),
      period = "Trump"
    )

  # Daily unreported (both comparison periods)
  biden_active <- biden_unmatched |>
    dplyr::filter(peak_pop > 0, adp_class == "ADP \u2265 2")
  trump_active <- trump_unmatched |>
    dplyr::filter(peak_pop > 0, adp_class == "ADP \u2265 2")
  substantive_codes <- union(biden_active$detention_facility_code,
                              trump_active$detention_facility_code)

  daily_unreported <- ddp_raw |>
    dplyr::filter(
      detention_facility_code %in% substantive_codes,
      (date >= biden_from & date <= biden_to) |
        (date >= trump_from & date <= trump_to)
    ) |>
    dplyr::left_join(vera_type_lookup |> dplyr::select(detloc, type_grouped),
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
    daily_unreported  = daily_unreported
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
