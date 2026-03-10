# _targets.R — ICE Detention Data Pipeline
#
# Run with: targets::tar_make()
# Visualize: targets::tar_visnetwork()
# Load a result: targets::tar_read(facilities_panel)

library(targets)

tar_option_set(
  packages = c("readxl", "dplyr", "stringr", "tidyr", "purrr",
               "tibble", "httr", "stringdist", "glue")
)

# Auto-source all functions in R/
tar_source()

list(
  # ── Metadata ───────────────────────────────────────────────────────────────
  # Spreadsheet URLs, sheet names, header positions, etc.
  tar_target(data_file_info, build_data_file_info()),

  # ── Download (rarely run) ──────────────────────────────────────────────────
  # Downloads files that don't already exist locally.
  # Set to cue = "never" so it only runs when you explicitly invalidate it:
  #   tar_invalidate(raw_xlsx_files); tar_make()
  tar_target(
    raw_xlsx_files,
    download_ice_spreadsheets(data_file_info),
    format = "file",
    cue = tar_cue(mode = "never")
  ),

  # ── Import headers ─────────────────────────────────────────────────────────
  # Reads the two-row headers from each spreadsheet and produces
  # a named list of clean variable name vectors.
  tar_target(
    clean_names_list,
    build_clean_names(data_file_info)
  ),

  # ── Import raw data ────────────────────────────────────────────────────────
  # Returns a named list of tibbles, one per fiscal year.
  tar_target(
    facilities_raw,
    import_all_years(data_file_info, clean_names_list)
  ),

  # ── Clean ──────────────────────────────────────────────────────────────────
  # Name standardization, type coercion, Guantanamo patch.
  tar_target(
    facilities_clean,
    clean_all_years(facilities_raw)
  ),

  # ── Aggregate ──────────────────────────────────────────────────────────────
  # Row-level sums (ADP by classification, criminality, threat level)
  # and facility_type_wiki classification.
  tar_target(
    facilities_aggregated,
    aggregate_all_years(facilities_clean)
  ),

  # ── Facility crosswalk ─────────────────────────────────────────────────────
  # Exact + fuzzy address matching across years → canonical facility IDs.
  tar_target(
    facility_crosswalk,
    build_facility_crosswalk(facilities_aggregated)
  ),

  # ── Attach canonical IDs ───────────────────────────────────────────────────
  tar_target(
    facilities_keyed,
    attach_canonical_ids(facilities_aggregated, facility_crosswalk)
  ),

  # ── Facility presence / trajectory ─────────────────────────────────────────
  tar_target(
    facility_presence,
    build_facility_presence(facilities_keyed)
  ),

  # ── Panel dataset ──────────────────────────────────────────────────────────
  tar_target(
    facilities_panel,
    build_panel(facilities_keyed)
  ),

  # ── Save outputs to data/ ─────────────────────────────────────────────────
  # Exports RDS + CSV files for external use.
  tar_target(
    saved_files,
    save_outputs(facility_crosswalk, facility_presence, facilities_panel),
    format = "file"
  )
)
