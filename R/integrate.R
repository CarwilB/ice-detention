# Integrate DMCP facility listings with the canonical facility list.
#
# Matching strategy (three passes):
#   1. Exact match on (facility_name, facility_city, facility_state) against
#      all name variants in the FY19–FY26 facility_crosswalk.
#   2. Manual overrides: six facilities confirmed by address inspection where
#      the DMCP name differs from the canonical name (renames, truncations).
#   3. Remaining unmatched facilities get new canonical IDs starting at 1001,
#      keeping DMCP-sourced IDs separate from the FY19–FY26 range (1–398) and
#      the future annual-stats range (399+).

# ── Manual match overrides ────────────────────────────────────────────────────
#
# Populated from the interactive matching session (2026-03-21). Each row is a
# DMCP facility that didn't match in Pass 1 but was confirmed by address review.
# Two facilities with different street addresses in adjacent complexes
# (JAMESGA, OTROPNM) are deliberately left unmatched pending confirmation of
# separate DETLOC codes for their companion buildings.

dmcp_manual_matches <- function() {
  tibble::tribble(
    ~detloc,   ~canonical_id, ~match_basis,
    # Original 6 — name truncation or rename
    "CCANOOH",  262L, "name truncation in PDF — same facility",
    "WASHCUT",  380L, "name truncation in PDF — same facility",
    "CSCNWWA",  357L, "address identical — Northwest Detention Center → Northwest ICE Processing Center",
    "JENADLA",  208L, "address identical — Jena/LaSalle → Central Louisiana ICE Processing Center",
    "JOHNSTX",  183L, "address identical — Johnson County LECC → Johnson County Corrections Center",
    "POLKCTX",  171L, "address identical — Polk County → IAH Secure Adult Detention Facility (Polk)",
    # 7 more confirmed by address — were initially assigned IDs 1001+
    "CACFMES", 231L, "address identical — Mesa Verde Detention Facility → Mesa Verde ICE Processing Center",
    "GRYDCKY", 153L, "address identical — Grayson County Detention Center → Grayson County Jail",
    "MONTGTX", 182L, "address identical — Joe Corley Detention Facility → Joe Corley Processing Center",
    "PINEPLA", 292L, "address identical — Pine Prairie Correctional Center → Pine Prairie ICE Processing Center",
    "TRICOIL", 304L, "address identical — Tri-County Detention Center → Pulaski County Jail",
    "STCDFTX", 343L, "address identical — South Texas Detention Complex → South Texas ICE Processing Center",
    "CCADCAZ",  61L, "same complex — CCA Central Arizona Detention Center → Central Arizona Florence Correctional Complex"
  )
}

# ── Build DMCP canonical map ──────────────────────────────────────────────────
#
# Returns a tibble with one row per DMCP facility (identified by detloc):
#   detloc | canonical_id | canonical_name | canonical_city | canonical_state | match_type
#
# match_type values:
#   "exact"    — Pass 1 exact name+city+state match
#   "manual"   — Pass 2 manually confirmed match
#   "new"      — no match; assigned a new canonical ID from 1001+
#
# Also appends new canonical IDs to id_registry and writes the updated registry
# to data/canonical_id_registry.csv (with a message listing the new rows).

build_dmcp_canonical_map <- function(faclist15, faclist17, facility_crosswalk,
                                     id_registry) {
  # Combined DMCP list: one row per detloc.
  # Use faclist17 for the 180 shared facilities (more recent); supplement with
  # faclist15-only facilities.
  only15 <- setdiff(faclist15$detloc, faclist17$detloc)

  dmcp_all <- dplyr::bind_rows(
    faclist17 |>
      dplyr::select(detloc, facility_name, facility_city, facility_state,
                    facility_zip, facility_address) |>
      dplyr::mutate(source = "faclist17"),
    faclist15 |>
      dplyr::filter(detloc %in% only15) |>
      dplyr::select(detloc, facility_name, facility_city, facility_state,
                    facility_zip, facility_address) |>
      dplyr::mutate(source = "faclist15")
  )

  # Pass 1: match (facility_name, facility_city, facility_state) against all
  # crosswalk variants, using normalized join keys for case insensitivity.
  xwalk_variants <- facility_crosswalk |>
    dplyr::select(facility_name, facility_city, facility_state,
                  canonical_id, canonical_name, canonical_city, canonical_state) |>
    dplyr::distinct() |>
    dplyr::mutate(
      .join_name  = normalize_join_key(facility_name),
      .join_city  = normalize_join_key(facility_city),
      .join_state = normalize_join_key(facility_state)
    )

  pass1 <- dmcp_all |>
    dplyr::mutate(
      .join_name  = normalize_join_key(facility_name),
      .join_city  = normalize_join_key(facility_city),
      .join_state = normalize_join_key(facility_state)
    ) |>
    dplyr::left_join(xwalk_variants |>
                       dplyr::select(.join_name, .join_city, .join_state,
                                     canonical_id, canonical_name,
                                     canonical_city, canonical_state),
                     by = c(".join_name", ".join_city", ".join_state")) |>
    dplyr::select(-starts_with(".join_"))

  matched   <- pass1 |>
    dplyr::filter(!is.na(canonical_id)) |>
    dplyr::select(detloc, source, canonical_id, canonical_name,
                  canonical_city, canonical_state) |>
    dplyr::mutate(match_type = "exact")

  unmatched <- pass1 |>
    dplyr::filter(is.na(canonical_id)) |>
    dplyr::select(detloc, source, facility_name, facility_city, facility_state)

  # Pass 2: apply manual overrides.
  manual  <- dmcp_manual_matches()
  manual_resolved <- unmatched |>
    dplyr::inner_join(manual |> dplyr::select(detloc, canonical_id),
                      by = "detloc") |>
    dplyr::left_join(
      id_registry |>
        dplyr::select(canonical_id, canonical_name, canonical_city, canonical_state),
      by = "canonical_id"
    ) |>
    dplyr::select(detloc, source, canonical_id, canonical_name,
                  canonical_city, canonical_state) |>
    dplyr::mutate(match_type = "manual")

  still_unmatched <- unmatched |>
    dplyr::anti_join(manual, by = "detloc")

  # Pass 3: assign canonical IDs to truly new facilities.
  # Look up any existing registry entries in the 1001+ range that match by
  # (name, city, state) using normalized keys to avoid case-sensitivity issues.
  existing_dmcp <- id_registry |>
    dplyr::filter(canonical_id >= 1001L) |>
    dplyr::mutate(
      .join_name  = normalize_join_key(canonical_name),
      .join_city  = normalize_join_key(canonical_city),
      .join_state = normalize_join_key(canonical_state)
    )

  still_unmatched <- still_unmatched |>
    dplyr::mutate(
      .join_name  = normalize_join_key(facility_name),
      .join_city  = normalize_join_key(facility_city),
      .join_state = normalize_join_key(facility_state)
    ) |>
    dplyr::left_join(
      existing_dmcp |>
        dplyr::select(canonical_id, canonical_name, canonical_city,
                       canonical_state, .join_name, .join_city, .join_state),
      by = c(".join_name", ".join_city", ".join_state")
    ) |>
    dplyr::select(-starts_with(".join_"))

  already_registered <- still_unmatched |> dplyr::filter(!is.na(canonical_id))
  truly_new          <- still_unmatched |> dplyr::filter(is.na(canonical_id))

  # Assign new IDs starting after the current max in the registry's DMCP range.
  if (nrow(truly_new) > 0) {
    new_start <- if (nrow(existing_dmcp) > 0) max(existing_dmcp$canonical_id) + 1L else 1001L
    truly_new <- truly_new |>
      dplyr::mutate(canonical_id = seq.int(new_start, new_start + dplyr::n() - 1L))
  }

  new_facilities <- dplyr::bind_rows(already_registered, truly_new) |>
    dplyr::mutate(
      canonical_name  = facility_name,
      canonical_city  = facility_city,
      canonical_state = facility_state,
      match_type      = "new"
    ) |>
    dplyr::select(detloc, source, canonical_id, canonical_name,
                  canonical_city, canonical_state, match_type)

  # Update registry: append only truly new rows, then deduplicate for safety.
  new_registry_rows <- truly_new |>
    dplyr::transmute(canonical_id, canonical_name = facility_name,
                     canonical_city = facility_city, canonical_state = facility_state)

  updated_registry <- dplyr::bind_rows(id_registry, new_registry_rows) |>
    dplyr::distinct() |>
    dplyr::arrange(canonical_id)

  registry_path <- here::here("data/canonical_id_registry.csv")
  readr::write_csv(updated_registry, registry_path)

  message(glue::glue(
    "DMCP Pass 3: {nrow(already_registered)} existing + {nrow(truly_new)} new. ",
    "Registry written to {registry_path} ({nrow(updated_registry)} rows)."
  ))

  # Combine all three passes.
  dmcp_canonical_map <- dplyr::bind_rows(matched, manual_resolved, new_facilities) |>
    dplyr::arrange(detloc)

  message(glue::glue(
    "DMCP canonical map: {nrow(dmcp_canonical_map)} facilities — ",
    "{sum(dmcp_canonical_map$match_type == 'exact')} exact, ",
    "{sum(dmcp_canonical_map$match_type == 'manual')} manual, ",
    "{sum(dmcp_canonical_map$match_type == 'new')} new."
  ))

  dmcp_canonical_map
}

# ── Attach canonical IDs to a DMCP listing ───────────────────────────────────
#
# Joins the dmcp_canonical_map onto a faclist tibble by detloc, adding
# canonical_id, canonical_name, and match_type columns.

attach_dmcp_canonical_ids <- function(faclist, dmcp_canonical_map) {
  faclist |>
    dplyr::left_join(
      dmcp_canonical_map |>
        dplyr::select(detloc, canonical_id, canonical_name, match_type),
      by = "detloc"
    ) |>
    dplyr::relocate(detloc, canonical_id, canonical_name, match_type)
}

# ── Build annual ADP summary tables from DMCP listings ──────────────────────
#
# Converts DMCP per-facility ADP columns into a named list of per-year tables,
# parallel to the `facilities_keyed` list for FY19–FY26. Each element is a
# tibble with one row per facility that had non-zero ADP that year.
#
# Source priority:
#   - FL17 is primary for all years (FY10–FY17). It has full-year ADP for
#     FY10–FY16 and partial-year (~9.5 months) for FY17.
#   - FL15 supplements FY10–FY15 only for facilities present in FL15 but not
#     FL17 (28 facilities). FL15's FY16 is partial-year (~70 days) and excluded.
#
# ADP column mapping: the single DMCP `fyXX_adp` is the facility's total ADP,
# corresponding to `sum_classification_levels` ≈ `sum_criminality_levels` ≈
# `sum_threat_levels` in FY19–FY26 data (which differ by at most 0.3 due to
# rounding in the component breakdowns).

build_annual_sums <- function(faclist15_keyed, faclist17_keyed) {
  # Identity columns to carry into each yearly table
  id_cols <- c("canonical_id", "canonical_name", "detloc",
               "facility_name", "facility_address", "facility_city",
               "facility_state", "facility_zip",
               "facility_type_detailed", "facility_male_female")

  # FL17 is primary for all years (FY10–FY17)
  fl17_long <- faclist17_keyed |>
    dplyr::select(dplyr::all_of(id_cols),
                  dplyr::matches("^fy1[0-7]_adp$")) |>
    tidyr::pivot_longer(
      cols = dplyr::matches("^fy1[0-7]_adp$"),
      names_to = "fy_col",
      values_to = "adp"
    ) |>
    dplyr::mutate(
      fiscal_year = paste0("FY", stringr::str_extract(fy_col, "\\d+")),
      source = "faclist17"
    ) |>
    dplyr::select(-fy_col)

  # FL15 supplements FY10–FY15 for the 28 FL15-only facilities
  fl15_only_detlocs <- setdiff(faclist15_keyed$detloc, faclist17_keyed$detloc)

  fl15_long <- faclist15_keyed |>
    dplyr::filter(detloc %in% fl15_only_detlocs) |>
    dplyr::select(dplyr::all_of(id_cols),
                  dplyr::matches("^fy1[0-5]_adp$")) |>
    tidyr::pivot_longer(
      cols = dplyr::matches("^fy1[0-5]_adp$"),
      names_to = "fy_col",
      values_to = "adp"
    ) |>
    dplyr::mutate(
      fiscal_year = paste0("FY", stringr::str_extract(fy_col, "\\d+")),
      source = "faclist15"
    ) |>
    dplyr::select(-fy_col)

  combined <- dplyr::bind_rows(fl17_long, fl15_long) |>
    dplyr::filter(!is.na(adp), adp > 0)

  # Split into per-year tables
  annual_sums <- combined |>
    dplyr::group_split(fiscal_year) |>
    purrr::set_names(purrr::map_chr(
      dplyr::group_split(combined, fiscal_year),
      \(x) x$fiscal_year[1]
    ))

  # Drop grouping columns, sort by canonical_id
  annual_sums <- purrr::map(annual_sums, \(df) {
    df |>
      dplyr::select(-fiscal_year) |>
      dplyr::arrange(canonical_id)
  })

  # Sort list by fiscal year
  annual_sums <- annual_sums[sort(names(annual_sums))]

  n_fac <- purrr::map_int(annual_sums, nrow)
  message(glue::glue(
    "Annual sums: {length(annual_sums)} fiscal years ",
    "(FY{min(stringr::str_extract(names(annual_sums), '\\\\d+'))}",
    "\u2013FY{max(stringr::str_extract(names(annual_sums), '\\\\d+'))}), ",
    "{sum(n_fac)} total facility-years. ",
    "Per year: {paste(paste0(names(annual_sums), '=', n_fac), collapse = ', ')}"
  ))

  annual_sums
}

# ── Build DETLOC lookup tables ───────────────────────────────────────────────
#
# Combines DMCP and DDP sources into a unified DETLOC lookup.
# Both are ICE data dumps using the same DETLOC identifier system.
# DDP codes (2023–2025) take precedence over DMCP (2015–2017) when both exist,
# since DETLOCs can be reassigned on facility rename.

build_detloc_lookup <- function(dmcp_canonical_map, ddp_canonical_map,
                                hold_canonical_data = NULL,
                                vera_facilities = NULL) {
  # 1:1 canonical_id → detloc.
  # Priority: DDP > DMCP > hold/ERO. For multi-code cases (Guantánamo), use the primary.
  # For DMCP IDs with 2 detlocs, pick the one from the more recent source.

  # DDP: one row per canonical_id (primary only for multi-code)
  ddp_1to1 <- ddp_canonical_map |>
    dplyr::filter(ddp_role %in% c("sole", "primary")) |>
    dplyr::select(canonical_id, detloc) |>
    dplyr::mutate(detloc_source = "ddp")

  # DMCP: prefer fl17 source for facilities with 2 detlocs
  dmcp_1to1 <- dmcp_canonical_map |>
    dplyr::arrange(canonical_id, dplyr::desc(source)) |>
    dplyr::distinct(canonical_id, .keep_all = TRUE) |>
    dplyr::select(canonical_id, detloc) |>
    dplyr::mutate(detloc_source = "dmcp")

  # Hold facilities + ERO DETLOC mappings
  hold_rows <- if (!is.null(hold_canonical_data)) {
    dplyr::bind_rows(
      hold_canonical_data$hold_canonical |>
        dplyr::select(canonical_id, detloc) |>
        dplyr::mutate(detloc_source = "marshall"),
      hold_canonical_data$ero_detloc_map |>
        dplyr::select(canonical_id, detloc) |>
        dplyr::mutate(detloc_source = "ero")
    )
  }

  # Vera: manual matches for canonical facilities with no DETLOC from other sources

  vera_rows <- if (!is.null(vera_facilities)) {
    vera_detloc_matches() |>
      dplyr::select(canonical_id, detloc) |>
      dplyr::mutate(detloc_source = "vera")
  }

  # Combine: DDP > DMCP > hold/ERO > Vera
  # Two dedup passes:
  #   1. Per canonical_id: keep highest-priority source (DDP > DMCP > hold > ERO > Vera)
  #   2. Per detloc: when the same detloc is assigned to multiple canonical_ids,
  #      keep the DDP mapping (more current) over the DMCP mapping (older).
  source_rank <- c(ddp = 1L, dmcp = 2L, marshall = 3L, ero = 4L, vera = 5L)

  result <- dplyr::bind_rows(ddp_1to1, dmcp_1to1, hold_rows, vera_rows) |>
    dplyr::mutate(.rank = source_rank[detloc_source]) |>
    dplyr::arrange(canonical_id, .rank) |>
    dplyr::distinct(canonical_id, .keep_all = TRUE) |>
    # Resolve duplicate detlocs: keep the lower-ranked (higher-priority) source
    dplyr::arrange(detloc, .rank) |>
    dplyr::distinct(detloc, .keep_all = TRUE) |>
    dplyr::select(-".rank") |>
    dplyr::arrange(canonical_id)

  dup_report <- result |>
    dplyr::add_count(detloc) |>
    dplyr::filter(n > 1)
  if (nrow(dup_report) > 0) {
    warning("Duplicate detlocs remain after dedup: ",
            paste(unique(dup_report$detloc), collapse = ", "))
  }

  result
}

build_detloc_lookup_full <- function(dmcp_canonical_map, ddp_canonical_map,
                                     hold_canonical_data = NULL,
                                     vera_facilities = NULL) {
  # Multi-row reference table preserving all DETLOC variants from all sources.

  dmcp_rows <- dmcp_canonical_map |>
    dplyr::select(canonical_id, detloc) |>
    dplyr::mutate(detloc_source = "dmcp", ddp_role = NA_character_)

  ddp_rows <- ddp_canonical_map |>
    dplyr::select(canonical_id, detloc, ddp_role) |>
    dplyr::mutate(detloc_source = "ddp")

  hold_rows <- if (!is.null(hold_canonical_data)) {
    dplyr::bind_rows(
      hold_canonical_data$hold_canonical |>
        dplyr::select(canonical_id, detloc) |>
        dplyr::mutate(detloc_source = "marshall", ddp_role = NA_character_),
      hold_canonical_data$ero_detloc_map |>
        dplyr::select(canonical_id, detloc) |>
        dplyr::mutate(detloc_source = "ero", ddp_role = NA_character_)
    )
  }

  vera_rows <- if (!is.null(vera_facilities)) {
    vera_detloc_matches() |>
      dplyr::select(canonical_id, detloc) |>
      dplyr::mutate(detloc_source = "vera", ddp_role = NA_character_)
  }

  dplyr::bind_rows(dmcp_rows, ddp_rows, hold_rows, vera_rows) |>
    dplyr::distinct() |>
    dplyr::arrange(canonical_id, detloc_source, detloc)
}
