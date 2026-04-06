# Build a canonical facility crosswalk across all years.
#
# Matching strategy (two passes):
#   1. Exact match on facility_name + facility_city + facility_state
#   2. Within the same ZIP code, fuzzy address string similarity (OSA >= 0.80)
#      resolves cases where the same physical facility appears under a different
#      name in different years.
#
# Returns a list with two elements:
#   $crosswalk  — maps every (name, city, state) variant to canonical_id/name
#   $presence   — one row per canonical facility; TRUE/FALSE for each fiscal year

year_order <- c("FY10", "FY11", "FY12", "FY13", "FY14", "FY15", "FY16", "FY17",
                "FY19", "FY20", "FY21", "FY22", "FY23", "FY24", "FY25", "FY26")

# ── Do-not-merge pairs ──────────────────────────────────────────────────────
# Genuinely distinct facilities that share a ZIP and similar addresses.

do_not_merge_pairs <- function() {
  tibble::tribble(
    ~name_a,                              ~name_b,
    "Folkston Main IPC",                  "Annex - Folkston IPC",
    "Folkston Main IPC",                  "Folkston Annex IPC",
    "Main - Folkston IPC (D Ray James)",  "Annex - Folkston IPC",
    "Main - Folkston IPC (D Ray James)",  "Folkston Annex IPC",
    "Joe Corley Processing Center",       "Montgomery ICE Processing Center",
    "Joe Corley ICE Processing Center",   "Montgomery ICE Processing Center"
  )
}

# ── Force-merge pairs ─────────────────────────────────────────────────────────
# Facilities that the crosswalk fails to merge automatically (e.g., because the
# address similarity falls below 0.80 after normalization, or because the names
# share no address at all). Each row names two facility_name values that should
# be unioned into the same canonical cluster.

force_merge_pairs <- function() {
  tibble::tribble(
    ~name_a,                                ~name_b,
    # Same building in Lovejoy GA; renamed between FY23 and FY24
    "Robert A. Deyton Detention Center",    "Robert A. Deyton Detention Facility"
  )
}

# ── Canonical name overrides ─────────────────────────────────────────────────

canonical_name_overrides_table <- function() {
  tibble::tribble(
    ~lookup_name,                                          ~canonical_name,                                        ~canonical_city,  ~canonical_state,
    "Adams County Detention Center",                       "Adams County Detention Center (Mississippi)",           "Natchez",        "MS",
    "Phelps County Jail",                                  "Phelps County Jail (Nebraska)",                         "Holdrege",       "NE",
    "Nye County Detention Center, Southern (Pahrump)",     "Nye County Detention Center (Nevada)",                  "Pahrump",        "NV",
    "Baker County Sheriff Department.",                    "Baker County Sheriff's Office",                         "Macclenny",      "FL",
    "Buffalo (Batavia) Service Processing Center",         "Buffalo (Batavia) Service Processing Center",           "Batavia",        "NY",
    "Farmville Detention Center",                          "Farmville Detention Center",                            "Farmville",      "VA",
    "Northwest ICE Processing Center",                     "Northwest ICE Processing Center",                       "Tacoma",         "WA"
  )
}

# ── Union-Find helpers ───────────────────────────────────────────────────────

new_union_find <- function(ids) {
  parent <- stats::setNames(ids, ids)
  env <- new.env(parent = emptyenv())
  env$parent <- parent
  env
}

uf_find <- function(uf, x) {
  while (uf$parent[as.character(x)] != x) x <- uf$parent[as.character(x)]
  x
}

uf_union <- function(uf, a, b) {
  ra <- uf_find(uf, a)
  rb <- uf_find(uf, b)
  if (ra != rb) uf$parent[as.character(ra)] <- rb
}

# ── Main crosswalk builder ───────────────────────────────────────────────────

build_facility_crosswalk <- function(facilities_data_list, id_registry) {
  # Pool all distinct (name, city, state, address, zip) combos
  all_facilities_norm <- facilities_data_list |>
    purrr::imap_dfr(\(df, yr) df |>
      dplyr::select(facility_name, facility_city, facility_state,
                    facility_address, facility_zip) |>
      dplyr::mutate(year = yr)) |>
    dplyr::mutate(
      zip5      = stringr::str_pad(facility_zip, width = 5, side = "left", pad = "0"),
      addr_norm = stringr::str_to_upper(stringr::str_trim(stringr::str_squish(facility_address)))
    )

  # Pass 1: provisional ID per exact name+city+state combo
  facility_key_exact <- all_facilities_norm |>
    dplyr::select(facility_name, facility_city, facility_state, addr_norm, zip5) |>
    dplyr::distinct() |>
    dplyr::group_by(facility_name, facility_city, facility_state) |>
    dplyr::summarise(addr_norm = dplyr::first(addr_norm),
                     zip5 = dplyr::first(zip5),
                     .groups = "drop") |>
    dplyr::mutate(facility_id = dplyr::row_number())

  # Pass 2: fuzzy address merge within same ZIP
  merge_candidates <- facility_key_exact |>
    dplyr::filter(!is.na(addr_norm), !is.na(zip5)) |>
    dplyr::group_by(zip5) |>
    dplyr::filter(dplyr::n() > 1) |>
    dplyr::group_modify(\(grp, key) {
      n <- nrow(grp)
      pairs <- expand.grid(i = seq_len(n), j = seq_len(n)) |> dplyr::filter(i < j)
      pairs |> dplyr::transmute(
        facility_id_a = grp$facility_id[i],
        facility_id_b = grp$facility_id[j],
        addr_a        = grp$addr_norm[i],
        addr_b        = grp$addr_norm[j],
        addr_dist     = stringdist::stringdist(addr_a, addr_b, method = "osa"),
        addr_sim      = 1 - addr_dist / pmax(nchar(addr_a), nchar(addr_b))
      )
    }) |>
    dplyr::ungroup()

  strong_addr_matches <- merge_candidates |> dplyr::filter(addr_sim >= 0.80)

  # Apply do-not-merge exclusions (normalized for case-insensitivity)
  fke_lookup <- facility_key_exact |>
    dplyr::mutate(.join_key = normalize_join_key(facility_name)) |>
    dplyr::select(.join_key, facility_id)

  dnm <- do_not_merge_pairs() |>
    dplyr::mutate(.join_a = normalize_join_key(name_a),
                  .join_b = normalize_join_key(name_b)) |>
    dplyr::left_join(fke_lookup, by = c(".join_a" = ".join_key")) |>
    dplyr::rename(id_a = facility_id) |>
    dplyr::left_join(fke_lookup, by = c(".join_b" = ".join_key")) |>
    dplyr::rename(id_b = facility_id) |>
    dplyr::select(-starts_with(".join_"))

  strong_addr_matches <- strong_addr_matches |>
    dplyr::anti_join(dnm, by = c("facility_id_a" = "id_a", "facility_id_b" = "id_b")) |>
    dplyr::anti_join(dnm, by = c("facility_id_a" = "id_b", "facility_id_b" = "id_a"))

  # Union-Find to cluster facility_ids
  uf <- new_union_find(facility_key_exact$facility_id)
  for (i in seq_len(nrow(strong_addr_matches))) {
    uf_union(uf, strong_addr_matches$facility_id_a[i],
             strong_addr_matches$facility_id_b[i])
  }

  # Apply force-merge pairs (normalized for case-insensitivity)
  fmp <- force_merge_pairs() |>
    dplyr::mutate(.join_a = normalize_join_key(name_a),
                  .join_b = normalize_join_key(name_b)) |>
    dplyr::left_join(fke_lookup, by = c(".join_a" = ".join_key")) |>
    dplyr::rename(id_a = facility_id) |>
    dplyr::left_join(fke_lookup, by = c(".join_b" = ".join_key")) |>
    dplyr::rename(id_b = facility_id) |>
    dplyr::select(-starts_with(".join_")) |>
    dplyr::filter(!is.na(id_a), !is.na(id_b))

  for (i in seq_len(nrow(fmp))) {
    uf_union(uf, fmp$id_a[i], fmp$id_b[i])
  }

  canonical_map <- tibble::tibble(facility_id = facility_key_exact$facility_id) |>
    dplyr::mutate(canonical_id = purrr::map_int(facility_id, \(x) uf_find(uf, x)))

  # Choose canonical name: most-recent year's name per cluster
  all_facilities_keyed <- all_facilities_norm |>
    dplyr::left_join(
      facility_key_exact |> dplyr::select(facility_name, facility_city, facility_state, facility_id),
      by = c("facility_name", "facility_city", "facility_state")
    ) |>
    dplyr::left_join(canonical_map, by = "facility_id")

  canonical_names <- all_facilities_keyed |>
    dplyr::mutate(year_rank = match(year, year_order)) |>
    dplyr::group_by(canonical_id) |>
    dplyr::slice_max(year_rank, n = 1, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::select(canonical_id,
                  canonical_name = facility_name,
                  canonical_city = facility_city,
                  canonical_state = facility_state)

  # Apply manual overrides (normalized join for case-insensitivity)
  overrides <- canonical_name_overrides_table() |>
    dplyr::mutate(.join_key = normalize_join_key(lookup_name)) |>
    dplyr::left_join(
      facility_key_exact |>
        dplyr::mutate(.join_key = normalize_join_key(facility_name)) |>
        dplyr::select(.join_key, facility_id),
      by = ".join_key"
    ) |>
    dplyr::select(-.join_key) |>
    dplyr::left_join(canonical_map, by = "facility_id") |>
    dplyr::select(canonical_id, canonical_name, canonical_city, canonical_state) |>
    dplyr::filter(!is.na(canonical_id))

  canonical_names <- canonical_names |>
    dplyr::rows_update(overrides, by = "canonical_id", unmatched = "ignore")

  # ── Freeze canonical IDs from registry ──────────────────────────────────────
  # Match computed canonical identities against the frozen registry by
  # (canonical_name, canonical_city, canonical_state). Uses normalized join
  # keys (case-insensitive, accent-stripped) so that capitalization changes in

  # clean.R do not break matches against the frozen registry.

  canonical_names_frozen <- canonical_names |>
    dplyr::mutate(
      .join_name  = normalize_join_key(canonical_name),
      .join_city  = normalize_join_key(canonical_city),
      .join_state = normalize_join_key(canonical_state)
    ) |>
    dplyr::left_join(
      id_registry |>
        dplyr::mutate(
          .join_name  = normalize_join_key(canonical_name),
          .join_city  = normalize_join_key(canonical_city),
          .join_state = normalize_join_key(canonical_state)
        ) |>
        dplyr::select(frozen_id = canonical_id,
                       .join_name, .join_city, .join_state),
      by = c(".join_name", ".join_city", ".join_state")
    ) |>
    dplyr::select(-starts_with(".join_"))

  n_new <- sum(is.na(canonical_names_frozen$frozen_id))
  if (n_new > 0) {
    new_start <- max(id_registry$canonical_id) + 1L
    is_new    <- is.na(canonical_names_frozen$frozen_id)
    canonical_names_frozen$frozen_id[is_new] <-
      seq.int(new_start, new_start + n_new - 1L)
    message(glue::glue(
      "{n_new} new canonical facilit{ifelse(n_new == 1L, 'y', 'ies')} not found in ",
      "id_registry. Assigned ID{ifelse(n_new == 1L, '', 's')} ",
      "{new_start}{ifelse(n_new > 1L, paste0('\u2013', new_start + n_new - 1L), '')}. ",
      "Append to data/canonical_id_registry.csv to freeze."
    ))
  }

  # Build remap: provisional canonical_id -> frozen canonical_id
  id_remap <- canonical_names_frozen |>
    dplyr::select(canonical_id, frozen_id)

  canonical_names <- canonical_names_frozen |>
    dplyr::mutate(canonical_id = frozen_id) |>
    dplyr::select(canonical_id, canonical_name, canonical_city, canonical_state)

  canonical_map <- canonical_map |>
    dplyr::left_join(id_remap, by = "canonical_id") |>
    dplyr::mutate(canonical_id = frozen_id) |>
    dplyr::select(facility_id, canonical_id)

  # Final crosswalk
  facility_crosswalk <- facility_key_exact |>
    dplyr::left_join(canonical_map, by = "facility_id") |>
    dplyr::left_join(canonical_names, by = "canonical_id") |>
    dplyr::select(facility_id, canonical_id, canonical_name, canonical_city, canonical_state,
                  facility_name, facility_city, facility_state)

  message(glue::glue(
    "Canonical facilities: {dplyr::n_distinct(facility_crosswalk$canonical_id)}",
    " (from {nrow(facility_key_exact)} exact name+city+state variants,",
    " {nrow(strong_addr_matches)} address-based merges)"
  ))

  # Warn if any panel facilities received IDs outside the frozen <400 block.
  # This usually means the registry name doesn't match the cleaned name
  # (e.g. abbreviation expansion in clean_facility_names()).
  max_panel_id <- max(id_registry$canonical_id[id_registry$canonical_id < 399])
  leaked <- facility_crosswalk |>
    dplyr::filter(canonical_id > max_panel_id) |>
    dplyr::distinct(canonical_id, canonical_name, canonical_city, canonical_state)
  if (nrow(leaked) > 0) {
    warning(
      "Panel facilities mapped outside the frozen <400 ID block!\n",
      "These facilities failed to match the registry (likely a name mismatch):\n",
      paste0("  ID ", leaked$canonical_id, ": ", leaked$canonical_name,
             " (", leaked$canonical_city, ", ", leaked$canonical_state, ")",
             collapse = "\n"),
      "\nUpdate data/canonical_id_registry.csv to fix.",
      call. = FALSE
    )
  }

  facility_crosswalk
}

# ── Attach canonical IDs to each year's data ────────────────────────────────

attach_canonical_ids <- function(facilities_data_list, facility_crosswalk,
                                 detloc_lookup = NULL) {
  xwalk_cols <- facility_crosswalk |>
    dplyr::select(facility_name, facility_city, facility_state,
                  canonical_id, canonical_name)

  # Optionally attach DETLOC via a second join on canonical_id
  if (!is.null(detloc_lookup)) {
    xwalk_cols <- xwalk_cols |>
      dplyr::left_join(
        detloc_lookup |> dplyr::select(canonical_id, detloc),
        by = "canonical_id"
      )
  }

  purrr::imap(facilities_data_list, \(df, yr) {
    df |>
      dplyr::left_join(
        xwalk_cols,
        by = c("facility_name", "facility_city", "facility_state")
      )
  })
}

# ── Facility presence and trajectory ─────────────────────────────────────────

build_facility_presence <- function(facilities_keyed) {
  year_cols_present <- year_order[year_order %in% names(facilities_keyed)]
  if (length(year_cols_present) == 0) {
    year_cols_present <- year_order
  }
  first_year       <- head(year_cols_present, 1)
  most_recent_year <- tail(year_cols_present, 1)

  presence <- facilities_keyed |>
    purrr::imap_dfr(\(df, yr) df |>
      dplyr::select(canonical_id, canonical_name) |>
      dplyr::distinct() |>
      dplyr::mutate(year = yr)) |>
    dplyr::mutate(present = TRUE) |>
    tidyr::pivot_wider(names_from = year, values_from = present,
                       values_fill = FALSE, names_sort = FALSE) |>
    dplyr::select(canonical_id, canonical_name, dplyr::any_of(year_cols_present)) |>
    dplyr::mutate(n_years = rowSums(dplyr::across(dplyr::any_of(year_cols_present))))

  # first_seen / last_seen
  presence <- presence |>
    dplyr::rowwise() |>
    dplyr::mutate(
      first_seen = year_cols_present[dplyr::c_across(dplyr::any_of(year_cols_present))][1],
      last_seen  = tail(year_cols_present[dplyr::c_across(dplyr::any_of(year_cols_present))], 1)
    ) |>
    dplyr::ungroup()

  # trajectory
  presence <- presence |>
    dplyr::mutate(
      trajectory = dplyr::case_when(
        first_seen == first_year & last_seen == most_recent_year &
          n_years == length(year_cols_present) ~ "continuous",
        first_seen == first_year & last_seen == most_recent_year ~ "persistent_gaps",
        first_seen == first_year & last_seen != most_recent_year ~ "closed",
        first_seen != first_year & last_seen == most_recent_year ~ "new",
        TRUE ~ "transient"
      )
    )

  # n_years_current: consecutive years ending at most_recent_year
  presence <- presence |>
    dplyr::mutate(
      n_years_current = apply(
        dplyr::pick(dplyr::all_of(year_order[year_order %in% names(presence)])),
        1, function(row) {
          if (!isTRUE(row[most_recent_year])) return(0L)
          count <- 0L
          for (yr in rev(year_order[year_order %in% names(presence)])) {
            if (isTRUE(row[yr])) count <- count + 1L else break
          }
          count
        })
    )

  # n_years_initial: consecutive years from first_year
  presence <- presence |>
    dplyr::mutate(
      n_years_initial = apply(
        dplyr::pick(dplyr::all_of(year_order[year_order %in% names(presence)])),
        1, function(row) {
          if (!isTRUE(row[first_year])) return(0L)
          count <- 0L
          for (yr in year_order[year_order %in% names(presence)]) {
            if (isTRUE(row[yr])) count <- count + 1L else break
          }
          count
        })
    )

  presence
}

# ── Merge FY19–26 keyed data with FY10–17 annual sums ────────────────────────
#
# Adds an `adp` column to the FY19–26 tables (from sum_classification_levels)
# so that every element of the combined list carries a comparable total ADP.
# Returns a single named list sorted by year_order.

merge_keyed_lists <- function(facilities_keyed, facilities_annual_sums) {
  keyed_with_adp <- purrr::imap(facilities_keyed, \(df, yr) {
    df |> dplyr::mutate(adp = sum_classification_levels)
  })
  # Add facility_type_wiki to DMCP-era tables using same classification
  sums_with_type <- purrr::map(facilities_annual_sums, \(df) {
    df |> dplyr::mutate(facility_type_wiki = classify_facility_type(facility_type_detailed))
  })
  combined <- c(sums_with_type, keyed_with_adp)
  combined[intersect(year_order, names(combined))]
}

# ── Build panel dataset ──────────────────────────────────────────────────────

build_panel <- function(facilities_keyed) {
  facilities_keyed |>
    purrr::imap_dfr(\(df, yr) df |> dplyr::mutate(fiscal_year = yr)) |>
    dplyr::relocate(fiscal_year, canonical_id, canonical_name,
                    facility_name, facility_city, facility_state)
}

# ── Canonical facility list ──────────────────────────────────────────────────
# One row per canonical facility: the most recent year's address columns,
# plus canonical_id and canonical_name from the crosswalk.
# This is the authoritative input for geocoding — kept separate from the
# full panel so downstream steps never have to reduce it themselves.

build_panel_facilities <- function(facilities_panel) {
  cols <- c("canonical_id", "canonical_name",
            "facility_address", "facility_city", "facility_state", "facility_zip",
            "facility_type_detailed", "facility_type_wiki")
  if ("detloc" %in% names(facilities_panel)) cols <- c(cols, "detloc")

  facilities_panel |>
    dplyr::mutate(year_rank = match(fiscal_year, year_order)) |>
    dplyr::group_by(canonical_id) |>
    dplyr::slice_max(year_rank, n = 1, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::select(dplyr::any_of(cols))
}

# ── Full facility roster ─────────────────────────────────────────────────────
# One row per canonical facility across ALL ID ranges, with best-available
# address, type, and location from the appropriate source.

.vera_type_to_wiki <- c(
  "Non-Dedicated" = "Jail",
  "Dedicated"     = "Private Migrant Detention Center",
  "Federal"       = "Federal Prison",
  "Family/Youth"  = "Family Detention Center",
  "Medical"       = "Medical Facility",
  "Other/Unknown" = "Other",
  "Hold/Staging"  = "ICE Hold Room"
)

.id_range_label <- function(id) {
  dplyr::case_when(
    id <= 398               ~ "panel",
    id >= 1001 & id <= 1053 ~ "dmcp_only",
    id >= 1054 & id <= 2000 ~ "ddp_other",
    id >= 2001 & id <= 2025 ~ "ero",
    id >= 2026 & id <= 3000 ~ "hold",
    id >= 3001 & id <= 4000 ~ "medical",
    id >= 4001              ~ "hotel",
    TRUE                    ~ NA_character_
  )
}

build_facility_roster <- function(panel_facilities,
                                   faclist15_keyed, faclist17_keyed,
                                   ero_canonical, hold_canonical_data,
                                   ddp_facility_canonical,
                                   detloc_lookup,
                                   vera_facilities = NULL) {

  std_cols <- c("canonical_id", "canonical_name", "detloc",
                "facility_address", "facility_city", "facility_state",
                "facility_zip", "facility_type_detailed", "facility_type_wiki")

  # ── Panel facilities (IDs 1-398) ──
  panel <- panel_facilities |>
    dplyr::select(dplyr::any_of(std_cols))

  # ── DMCP-only facilities (IDs 1001-1053) ──
  # Use fl17 preferentially, fill gaps from fl15
  dmcp_ids <- unique(c(faclist15_keyed$canonical_id, faclist17_keyed$canonical_id))
  dmcp_ids <- dmcp_ids[dmcp_ids >= 1001 & dmcp_ids <= 1053]

  dmcp <- dplyr::bind_rows(
    faclist17_keyed |>
      dplyr::filter(canonical_id %in% dmcp_ids) |>
      dplyr::mutate(src_priority = 1L),
    faclist15_keyed |>
      dplyr::filter(canonical_id %in% dmcp_ids) |>
      dplyr::mutate(src_priority = 2L)
  ) |>
    dplyr::arrange(canonical_id, src_priority) |>
    dplyr::distinct(canonical_id, .keep_all = TRUE) |>
    dplyr::select(dplyr::any_of(c(std_cols, "facility_type_detailed")))

  dmcp <- dmcp |> dplyr::select(dplyr::any_of(std_cols))

  # ── ERO field offices (IDs 2001-2025) ──
  ero <- ero_canonical |>
    dplyr::transmute(
      canonical_id, canonical_name, detloc,
      facility_address = address, facility_city = city,
      facility_state = state, facility_zip = zip,
      facility_type_detailed = "ero_office",
      facility_type_wiki
    )

  # ── Hold facilities (IDs 2026+) ──
  hold <- hold_canonical_data$hold_canonical |>
    dplyr::transmute(
      canonical_id, canonical_name, detloc,
      facility_address = address, facility_city = city,
      facility_state = state, facility_zip = zip,
      # Preserve the internal type code (hold_room, staging, etc.)
      facility_type_detailed = facility_type,
      facility_type_wiki
    )

  # ── DDP new facilities (IDs 1054-1203, 3001-3226) ──
  ddp_new <- ddp_facility_canonical |>
    dplyr::select(dplyr::any_of(std_cols))

  # ── Combine ──
  roster <- dplyr::bind_rows(panel, dmcp, ero, hold, ddp_new) |>
    dplyr::distinct(canonical_id, .keep_all = TRUE) |>
    dplyr::mutate(id_range = .id_range_label(canonical_id))

  # Fill in DETLOCs from detloc_lookup where missing
  missing_detloc <- is.na(roster$detloc)
  if (any(missing_detloc)) {
    dl_map <- detloc_lookup |>
      dplyr::distinct(canonical_id, .keep_all = TRUE) |>
      dplyr::select(canonical_id, detloc_fill = detloc)
    roster <- roster |>
      dplyr::left_join(dl_map, by = "canonical_id") |>
      dplyr::mutate(detloc = dplyr::coalesce(detloc, detloc_fill)) |>
      dplyr::select(-detloc_fill)
  }

  # Join Vera corrected types via DETLOC where available

  if (!is.null(vera_facilities)) {
    vera_types <- vera_facilities |>
      dplyr::distinct(detloc, .keep_all = TRUE) |>
      dplyr::select(detloc, type_detailed_corrected, type_grouped_corrected)
    roster <- roster |>
      dplyr::left_join(vera_types, by = "detloc")
  } else {
    roster <- roster |>
      dplyr::mutate(
        type_detailed_corrected = NA_character_,
        type_grouped_corrected  = NA_character_
      )
  }

  # Unified facility_type_wiki using combined classification
  roster <- roster |>
    dplyr::mutate(
      facility_type_wiki = classify_facility_type_combined(
        facility_type_detailed, type_grouped_corrected, canonical_name,
        type_detailed_corrected
      )
    ) |>
    dplyr::arrange(canonical_id)

  cli::cli_inform(c(
    "Facility roster: {nrow(roster)} facilities",
    "*" = "panel: {sum(roster$id_range == 'panel', na.rm = TRUE)}",
    "*" = "dmcp_only: {sum(roster$id_range == 'dmcp_only', na.rm = TRUE)}",
    "*" = "ddp_other: {sum(roster$id_range == 'ddp_other', na.rm = TRUE)}",
    "*" = "ero: {sum(roster$id_range == 'ero', na.rm = TRUE)}",
    "*" = "hold: {sum(roster$id_range == 'hold', na.rm = TRUE)}",
    "*" = "medical: {sum(roster$id_range == 'medical', na.rm = TRUE)}"
  ))

  roster
}

# ── Source presence matrix ────────────────────────────────────────────────────
# One row per canonical facility (all ID ranges), with boolean columns
# indicating which data sources contain information about each facility.

build_source_presence <- function(facility_presence, faclist15_keyed,
                                  faclist17_keyed, ddp_canonical_map,
                                  detloc_lookup, marshall_locations,
                                  facilities_geocoded_all,
                                  hold_canonical_data, ero_canonical,
                                  vera_facilities = NULL,
                                  ddp_codes = NULL,
                                  ddp_facility_canonical = NULL) {

  # Build a unified roster of all canonical facilities across all ID ranges
  panel_ids <- facility_presence |>
    dplyr::select(canonical_id, canonical_name)

  dmcp_only_ids <- dplyr::bind_rows(
    faclist15_keyed |> dplyr::select(canonical_id, canonical_name),
    faclist17_keyed |> dplyr::select(canonical_id, canonical_name)
  ) |>
    dplyr::distinct() |>
    dplyr::filter(!(canonical_id %in% panel_ids$canonical_id))

  ero_ids <- ero_canonical |>
    dplyr::select(canonical_id, canonical_name)

  hold_ids <- hold_canonical_data$hold_canonical |>
    dplyr::select(canonical_id, canonical_name)

  # New DDP-only facilities (IDs 1054+ and 3001+)
  ddp_new_ids <- if (!is.null(ddp_facility_canonical)) {
    ddp_facility_canonical |>
      dplyr::select(canonical_id, canonical_name)
  } else {
    tibble::tibble(canonical_id = integer(), canonical_name = character())
  }

  roster <- dplyr::bind_rows(panel_ids, dmcp_only_ids, ero_ids, hold_ids,
                              ddp_new_ids) |>
    dplyr::distinct(canonical_id, .keep_all = TRUE) |>
    dplyr::arrange(canonical_id)

  roster <- roster |>
    dplyr::mutate(id_range = .id_range_label(canonical_id))

  # Source presence flags
  marshall_detlocs <- unique(marshall_locations$detloc)
  vera_detlocs <- if (!is.null(vera_facilities)) unique(vera_facilities$detloc) else character()
  # DDP detlocs: use ddp_codes if provided (all 853 facility codes from the raw

  # DDP data), falling back to ddp_canonical_map only (undercounts — misses
  # DMCP-mapped facilities that also appear in DDP).
  ddp_detlocs <- if (!is.null(ddp_codes)) {
    unique(ddp_codes$detention_facility_code)
  } else {
    character()
  }

  roster <- roster |>
    dplyr::mutate(
      in_fy_panel   = canonical_id %in% facility_presence$canonical_id,
      in_faclist15  = canonical_id %in% unique(faclist15_keyed$canonical_id),
      in_faclist17  = canonical_id %in% unique(faclist17_keyed$canonical_id),
      has_detloc    = canonical_id %in% unique(detloc_lookup$canonical_id),
      # A facility is "in DDP" if: (a) matched via ddp_canonical_map, or
      # (b) its DETLOC appears in DDP facility codes, or (c) it was assigned
      # a canonical ID from ddp_facility_canonical (IDs 1054+ and 3001+).
      in_ddp        = canonical_id %in% unique(ddp_canonical_map$canonical_id) |
        canonical_id %in% ddp_new_ids$canonical_id |
        (has_detloc &
           dplyr::coalesce(
             detloc_lookup$detloc[match(canonical_id, detloc_lookup$canonical_id)],
             ""
           ) %in% ddp_detlocs),
      in_marshall   = has_detloc &
        dplyr::coalesce(
          detloc_lookup$detloc[match(canonical_id, detloc_lookup$canonical_id)],
          ""
        ) %in% marshall_detlocs,
      # in_vera: DETLOC in Vera, OR facility was sourced from ddp_facility_canonical
      # (which always has Vera metadata by construction).
      in_vera       = (has_detloc &
        dplyr::coalesce(
          detloc_lookup$detloc[match(canonical_id, detloc_lookup$canonical_id)],
          ""
        ) %in% vera_detlocs) |
        canonical_id %in% ddp_new_ids$canonical_id,
      is_geocoded   = canonical_id %in% unique(facilities_geocoded_all$canonical_id),
      geocode_source = facilities_geocoded_all$geocode_source[
        match(canonical_id, facilities_geocoded_all$canonical_id)
      ],
      n_sources     = in_fy_panel + in_faclist15 + in_faclist17 + in_ddp +
                      in_marshall + in_vera
    )

  message(glue::glue(
    "Source presence matrix: {nrow(roster)} canonical facilities, ",
    "{sum(roster$in_fy_panel)} in FY panel, ",
    "{sum(roster$in_faclist15)} in faclist15, ",
    "{sum(roster$in_faclist17)} in faclist17, ",
    "{sum(roster$in_ddp)} in DDP, ",
    "{sum(roster$in_marshall)} in Marshall Project, ",
    "{sum(roster$in_vera)} in Vera Institute"
  ))

  roster
}

# ── Save outputs to data/ ───────────────────────────────────────────────────

save_outputs <- function(facility_crosswalk, facility_presence,
                         facilities_panel, source_presence,
                         facility_roster) {
  paths <- c(
    "data/facility_crosswalk.rds",
    "data/facility_crosswalk.csv",
    "data/facility_presence.rds",
    "data/facility_presence.csv",
    "data/facilities_panel.rds",
    "data/facilities_panel.csv",
    "data/source_presence.rds",
    "data/source_presence.csv",
    "data/facility_roster.rds",
    "data/facility_roster.csv"
  )
  saveRDS(facility_crosswalk, paths[1])
  write.csv(facility_crosswalk, paths[2], row.names = FALSE)
  saveRDS(facility_presence, paths[3])
  write.csv(facility_presence, paths[4], row.names = FALSE)
  saveRDS(facilities_panel, paths[5])
  write.csv(facilities_panel, paths[6], row.names = FALSE)
  saveRDS(source_presence, paths[7])
  write.csv(source_presence, paths[8], row.names = FALSE)
  saveRDS(facility_roster, paths[9])
  write.csv(facility_roster, paths[10], row.names = FALSE)
  message("Saved: ", paste(basename(paths), collapse = ", "))
  paths
}
