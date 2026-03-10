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

year_order <- c("FY19", "FY20", "FY21", "FY22", "FY23", "FY24", "FY25", "FY26")

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

build_facility_crosswalk <- function(facilities_data_list) {
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

  # Apply do-not-merge exclusions
  dnm <- do_not_merge_pairs() |>
    dplyr::left_join(facility_key_exact |> dplyr::select(facility_name, facility_id),
                     by = c("name_a" = "facility_name")) |>
    dplyr::rename(id_a = facility_id) |>
    dplyr::left_join(facility_key_exact |> dplyr::select(facility_name, facility_id),
                     by = c("name_b" = "facility_name")) |>
    dplyr::rename(id_b = facility_id)

  strong_addr_matches <- strong_addr_matches |>
    dplyr::anti_join(dnm, by = c("facility_id_a" = "id_a", "facility_id_b" = "id_b")) |>
    dplyr::anti_join(dnm, by = c("facility_id_a" = "id_b", "facility_id_b" = "id_a"))

  # Union-Find to cluster facility_ids
  uf <- new_union_find(facility_key_exact$facility_id)
  for (i in seq_len(nrow(strong_addr_matches))) {
    uf_union(uf, strong_addr_matches$facility_id_a[i],
             strong_addr_matches$facility_id_b[i])
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

  # Apply manual overrides
  overrides <- canonical_name_overrides_table() |>
    dplyr::left_join(facility_key_exact |> dplyr::select(facility_name, facility_id),
                     by = c("lookup_name" = "facility_name")) |>
    dplyr::left_join(canonical_map, by = "facility_id") |>
    dplyr::select(canonical_id, canonical_name, canonical_city, canonical_state) |>
    dplyr::filter(!is.na(canonical_id))

  canonical_names <- canonical_names |>
    dplyr::rows_update(overrides, by = "canonical_id", unmatched = "ignore")

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

  facility_crosswalk
}

# ── Attach canonical IDs to each year's data ────────────────────────────────

attach_canonical_ids <- function(facilities_data_list, facility_crosswalk) {
  purrr::imap(facilities_data_list, \(df, yr) {
    df |>
      dplyr::left_join(
        facility_crosswalk |>
          dplyr::select(facility_name, facility_city, facility_state,
                        canonical_id, canonical_name),
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

# ── Build panel dataset ──────────────────────────────────────────────────────

build_panel <- function(facilities_keyed) {
  facilities_keyed |>
    purrr::imap_dfr(\(df, yr) df |> dplyr::mutate(fiscal_year = yr)) |>
    dplyr::relocate(fiscal_year, canonical_id, canonical_name,
                    facility_name, facility_city, facility_state)
}

# ── Save outputs to data/ ───────────────────────────────────────────────────

save_outputs <- function(facility_crosswalk, facility_presence, facilities_panel) {
  paths <- c(
    "data/facility_crosswalk.rds",
    "data/facility_crosswalk.csv",
    "data/facility_presence.rds",
    "data/facility_presence.csv",
    "data/facilities_panel.rds",
    "data/facilities_panel.csv"
  )
  saveRDS(facility_crosswalk, paths[1])
  write.csv(facility_crosswalk, paths[2], row.names = FALSE)
  saveRDS(facility_presence, paths[3])
  write.csv(facility_presence, paths[4], row.names = FALSE)
  saveRDS(facilities_panel, paths[5])
  write.csv(facilities_panel, paths[6], row.names = FALSE)
  message("Saved: ", paste(basename(paths), collapse = ", "))
  paths
}
