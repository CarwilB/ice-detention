# _targets.R — ICE Detention Data Pipeline
#
# Run with: targets::tar_make()
# Visualize: targets::tar_visnetwork()
# Load a result: targets::tar_read(facilities_panel)

library(targets)
library(tarchetypes)

tar_option_set(
  packages = c("readxl", "readr", "dplyr", "stringr", "tidyr", "purrr",
               "tibble", "httr", "stringdist", "glue", "here", "tabulapdf", "arrow",
               "rvest")
)

# Auto-source all functions in R/
tar_source()
# Supplemental import scripts (not in R/)
source("themarshallproject-locations.R")
# source("vera-institute.R") # moved to R/

list(
  # ── Metadata ───────────────────────────────────────────────────────────────
  # Spreadsheet URLs, sheet names, header positions, etc.
  tar_target(
    data_file_info,
    build_data_file_info(),
    description = "Spreadsheet URLs, sheet names, header row positions, and rightmost data columns for each FY19-FY26 XLSX file"
  ),

  # ── Download (rarely run) ──────────────────────────────────────────────────
  # Downloads files that don't already exist locally.
  # Set to cue = "never" so it only runs when you explicitly invalidate it:
  #   tar_invalidate(raw_xlsx_files); tar_make()
  tar_target(
    raw_xlsx_files,
    download_ice_spreadsheets(data_file_info),
    description = "Local paths to downloaded ICE annual stats XLSX files",
    format = "file",
    cue = tar_cue(mode = "never")
  ),

  # ── Import headers ─────────────────────────────────────────────────────────
  # Reads the two-row headers from each spreadsheet and produces
  # a named list of clean variable name vectors.
  tar_target(
    clean_names_list,
    build_clean_names(data_file_info),
    description = "Clean variable name vectors (one per fiscal year), derived from the 2-row merged Excel headers"
  ),

  # ── Import raw data ────────────────────────────────────────────────────────
  # Returns a named list of tibbles, one per fiscal year.
  tar_target(
    facilities_raw,
    import_all_years(data_file_info, clean_names_list),
    description = "Raw tibbles imported from each XLSX file, one per fiscal year (FY19-FY26)"
  ),

  # ── Clean ──────────────────────────────────────────────────────────────────
  # Name standardization, type coercion, Guantanamo patch.
  tar_target(
    facilities_clean,
    clean_all_years(facilities_raw),
    description = "Cleaned tibbles with standardized facility names, city corrections, type coercion, and Guantanamo patch"
  ),

  # ── Aggregate ──────────────────────────────────────────────────────────────
  # Row-level sums (ADP by classification, criminality, threat level)
  # and facility_type_wiki classification.
  tar_target(
    facilities_aggregated,
    aggregate_all_years(facilities_clean),
    description = "Aggregated tibbles with row-level ADP sums, share_non_crim, share_no_threat, and facility_type_wiki classification"
  ),

  # ── Canonical ID registry ─────────────────────────────────────────────────
  # Frozen mapping of canonical IDs 1–404 (FY19–FY26 facilities; 405–1000 reserved for future annual stats).
  # Tracking the file means the crosswalk reruns automatically if the registry
  # is updated (e.g. new IDs appended after a FY27 import).
  tar_target(
    id_registry_file,
    here::here("data/canonical_id_registry.csv"),
    description = "Tracks data/canonical_id_registry.csv for changes",
    format = "file"
  ),
  tar_target(
    id_registry,
    readr::read_csv(id_registry_file,
                    col_types = readr::cols(canonical_id   = readr::col_integer(),
                                            canonical_name  = readr::col_character(),
                                            canonical_city  = readr::col_character(),
                                            canonical_state = readr::col_character())),
    description = "Frozen registry of canonical IDs 1-404 (FY19-FY26 facilities); append-only, new annual stats extend from 405"
  ),

  # ── Facility crosswalk ─────────────────────────────────────────────────────
  # Exact + fuzzy address matching across years → canonical facility IDs.
  # IDs are looked up from id_registry; new facilities get IDs from 399+.
  tar_target(
    facility_crosswalk,
    build_facility_crosswalk(facilities_aggregated, id_registry),
    description = "Maps every (name, city, state) variant across FY19-FY26 to canonical_id/canonical_name via exact + fuzzy address matching"
  ),

  # ── Attach canonical IDs + DETLOCs ─────────────────────────────────────────
  # Adds canonical_id, canonical_name, and detloc to the aggregated data.
  tar_target(
    facilities_keyed,
    attach_canonical_ids(facilities_aggregated, facility_crosswalk, detloc_lookup),
    description = "FY19-FY26 aggregated data with canonical_id, canonical_name, and detloc joined from crosswalk and DETLOC lookup"
  ),

  # ── Merge FY10–17 + FY19–26 ───────────────────────────────────────────────
  # Combines annual sums (DMCP-era) with keyed data (ICE stats era) into one
  # named list spanning FY10–FY26 (minus FY18, no data). Adds an `adp` column
  # to FY19–26 tables from sum_classification_levels for comparability.
  tar_target(
    facilities_all_keyed,
    merge_keyed_lists(facilities_keyed, facilities_annual_sums),
    description = "Merged FY10-FY26 (minus FY18); combines facilities_keyed (FY19-26) with facilities_annual_sums (FY10-17); adds adp column to FY19-26"
  ),

  # ── Facility presence / trajectory ─────────────────────────────────────────
  # For each facility, which years was it present in the data? When did it open/close?
  tar_target(
    facility_presence,
    build_facility_presence(facilities_all_keyed),
    description = "One row per canonical facility with FY10-FY26 boolean presence columns and trajectory label (continuous, persistent_gaps, closed, new, transient)"
  ),

  # ── Panel dataset ──────────────────────────────────────────────────────────
  tar_target(
    facilities_panel,
    build_panel(facilities_all_keyed),
    description = "Long-format panel: one row per facility per year (FY10-FY26, minus FY18); all measurement variables plus canonical IDs and DETLOCs"
  ),

  # ── Canonical facility list ────────────────────────────────────────────────
  # One row per canonical facility with most recent address columns.
  # This is the authoritative input for geocoding and infobox generation.
  tar_target(
    panel_facilities,
    build_panel_facilities(facilities_panel),
    description = "One row per panel facility (IDs 1-1000) with most recent address, city, state, ZIP, and DETLOC; input for geocoding and wiki matching"
  ),

  # ── Geocode facilities ─────────────────────────────────────────────────────
  # Incremental: reads cached results from data/google-geocoded-facilities.csv
  # and only sends new/changed addresses to the Google Maps API.
  # To force full re-geocode: delete the CSV cache and invalidate the target.
  # Requires google_maps_api_key in .Renviron.
  tar_target(
    facilities_google_geocoded,
    geocode_roster(facility_roster),
    description = "Google Maps API geocoded coordinates for all roster facilities (incremental)"
  ),
  # Merges Google results with source-provided coords (Marshall, Vera).
  # Flags address quality issues and divergences > 1 km.
  # Manual preferences in geocode_source_preference() override divergent rows.
  tar_target(
    facilities_geocoded_all,
    build_geocoded_all(facility_roster, facilities_google_geocoded,
                       hold_canonical_data, vera_facilities, detloc_lookup),
    description = "Unified geocoded table with Google + source coords, divergence flags, and address quality"
  ),

  # Extract addresses and geocoding for DDP comparison export
  tar_target(
    facilities_geocoding_lookup,
    build_facilities_geocoding_lookup(facilities_geocoded_all),
    description = "Facility addresses and geocoding lookup for DDP comparison export"
  ),

  # Archive Google geocoding results as CSV (parallels Vera facilities.csv)
  tar_target(
    google_geocoded_file,
    { path <- "data/google-geocoded-facilities.csv"
      readr::write_csv(facilities_google_geocoded, path)
      path },
    format = "file",
    description = "Archived Google Maps geocoding results (CSV)"
  ),

  # Archive unified geocoded output with all sources and resolved coordinates
  tar_target(
    facilities_geocoded_all_file,
    { path <- "data/facilities-geocoded-all.csv"
      readr::write_csv(facilities_geocoded_all, path)
      path },
    format = "file",
    description = "Archived unified geocoded facility list with all sources and preferred coordinates (CSV)"
  ),

  # ── Wikipedia harmonization ──────────────────────────────────────────────
  # Scrapes the Wikipedia "List of immigrant detention sites" article and
  # matches FY26 ICE facilities to Wikipedia rows by name, city/state alias,
  # and Wikipedia API search. Adds wiki_slug, management, and contractors patch.

  # Pinned (old) revision — broad table with 395 rows, historical links
  tar_target(
    wiki_detention_table,
    scrape_wiki_detention_table(),
    description = "Scraped pinned revision of the Wikipedia 'List of immigrant detention sites' wikitable; broad historical table",
    cue = tar_cue(mode = "never")
  ),

  # Current revision — your exported FY26 table with edits from other editors.
  # Re-scrape via tar_invalidate(wiki_detention_table_current) when the article
  # is updated; update the oldid URL accordingly.
  tar_target(
    wiki_detention_table_current,
    scrape_wiki_detention_table(
      url = "https://en.wikipedia.org/w/index.php?title=List_of_immigrant_detention_sites_in_the_United_States&oldid=1341823085"
    ),
    description = "Current live revision of the Wikipedia table; update oldid after article edits",
    cue = tar_cue(mode = "never")
  ),

  # City/state alias matches between ICE names and Wikipedia names
  tar_target(
    wiki_match_table,
    build_wiki_match_table(facilities_keyed[["FY26"]], wiki_detention_table),
    description = "City/state alias matches between ICE FY26 facility names and Wikipedia table names"
  ),

  # Wikipedia API search for each facility name (~2 min at 0.5s delay)
  # Re-run via tar_invalidate(facilities_fy26_wiki_search)
  tar_target(
    facilities_fy26_wiki_search,
    add_wikipedia_matches(facilities_keyed[["FY26"]], name_col = "facility_name"),
    description = "Wikipedia API search results for each FY26 facility name",
    cue = tar_cue(mode = "never")
  ),

  # Track the contractors management patch CSV
  tar_target(
    contractors_patch_file,
    here::here("data/contractors-patch-fy26.csv"),
    description = "Tracks data/contractors-patch-fy26.csv for changes",
    format = "file"
  ),

  # FY26 facilities with wiki_match, wiki_slug, and management columns
  tar_target(
    facilities_fy26_wiki,
    add_wiki_columns(facilities_keyed[["FY26"]], wiki_detention_table,
                     wiki_match_table, facilities_fy26_wiki_search) |>
      backfill_wiki_slugs(wiki_detention_table_current) |>
      apply_wiki_slug_overrides() |>
      apply_contractors_patch(contractors_patch_file) |>
      apply_fl17_management(faclist17_keyed) |>
      standardize_management(),
    description = "FY26 facilities with wiki_match, wiki_slug, and management columns; applies slug overrides, contractors patch, fl17 backfill, and standardization"
  ),

  # Match all canonical facilities (incl. historical) against the wiki table.
  # Four passes: direct name, city/state alias, manual, external (API/category).
  tar_target(
    canonical_wiki_match,
    build_canonical_wiki_match(panel_facilities, wiki_detention_table),
    description = "All canonical facilities matched to Wikipedia articles via 4-pass matching (direct name, city/state alias, manual, external API)"
  ),

  # Generate the FY26 MediaWiki table for the Wikipedia list article.
  tar_target(
    fy26_wikitable,
    generate_fy26_wikitable(facilities_fy26_wiki, year_name = "FY26",
                             facility_presence = facility_presence),
    description = "MediaWiki table markup for active facilities in the Wikipedia list article"
  ),

  # Generate the closed-facilities MediaWiki table.
  tar_target(
    closed_wikitable,
    generate_closed_wikitable(facilities_panel, facility_presence,
                               canonical_wiki_match = canonical_wiki_match),
    description = "MediaWiki table markup for closed facilities in the Wikipedia list article"
  ),

  # ── Full facility roster ────────────────────────────────────────────────────
  # One row per canonical facility across all ID ranges with best-available
  # address, type, and DETLOC. Geocoding is joined downstream via
  # facilities_geocoded_all.
  tar_target(
    facility_roster,
    build_facility_roster(panel_facilities, faclist15_keyed, faclist17_keyed,
                          ero_canonical, hold_canonical_data,
                          ddp_facility_canonical, detloc_lookup,
                          vera_facilities),
    description = "Full facility roster: one row per canonical facility (~962) with address, type, and DETLOC"
  ),

  # ── Source presence matrix ─────────────────────────────────────────────────
  # One row per canonical facility (all ID ranges), with boolean source flags.
  tar_target(
    source_presence,
    build_source_presence(facility_presence, faclist15_keyed, faclist17_keyed,
                          ddp_canonical_map, detloc_lookup, marshall_locations,
                          facilities_geocoded_all, hold_canonical_data,
                          ero_canonical, vera_facilities,
                          ddp_codes = ddp_codes,
                          ddp_facility_canonical = ddp_facility_canonical),
    description = "One row per canonical facility (all ID ranges) with boolean flags for each data source (ICE stats, DMCP, DDP, Marshall, Vera, geocoded, etc.)"
  ),

  # ── Save outputs to data/ ─────────────────────────────────────────────────
  # Exports RDS + CSV files for external use.
  tar_target(
    saved_files,
    save_outputs(facility_crosswalk, facility_presence, facilities_panel,
                 source_presence, facility_roster),
    description = "Exported RDS + CSV files written to data/ (crosswalk, presence, panel, source_presence, roster)",
    format = "file"
  ),

  # ── DMCP canonical integration ─────────────────────────────────────────────
  # Maps every DMCP facility (detloc) to a canonical_id. Three passes:
  #   1. Exact name+city+state match against facility_crosswalk variants.
  #   2. Manual overrides for confirmed renames/truncations (see integrate.R).
  #   3. New IDs from 1001+ for facilities not in the FY19–FY26 panel.
  # Also appends new IDs to canonical_id_registry.csv (tracked by id_registry_file).
  tar_target(
    dmcp_canonical_map,
    build_dmcp_canonical_map(faclist15, faclist17, facility_crosswalk, id_registry),
    description = "Maps every DMCP DETLOC to a canonical_id via 3-pass matching (exact, manual, new IDs from 1001+)"
  ),
  tar_target(faclist15_keyed, attach_dmcp_canonical_ids(faclist15, dmcp_canonical_map),
    description = "faclist15 with canonical_id, canonical_name, and match_type prepended"),
  tar_target(faclist17_keyed, attach_dmcp_canonical_ids(faclist17, dmcp_canonical_map),
    description = "faclist17 with canonical_id, canonical_name, and match_type prepended"),

  # Per-fiscal-year ADP tables (FY10–FY17), parallel to facilities_keyed.
  # FL17 is authoritative for all years; FL15 supplements FY10–FY15 for 28
  # FL15-only facilities. Each list element has one row per facility with
  # non-zero ADP that year.
  tar_target(
    facilities_annual_sums,
    build_annual_sums(faclist15_keyed, faclist17_keyed),
    description = "Per-fiscal-year tables (FY10-FY17) with one row per facility with non-zero ADP; built from faclist15/faclist17 data"
  ),

  # ── DDP → canonical map ──────────────────────────────────────────────────
  # Maps DDP DETLOCs to canonical facilities not in DMCP data.
  # Three-tier matching: fuzzy OSA + county name + confirmed keyword.
  tar_target(
    ddp_canonical_map,
    build_ddp_canonical_map(id_registry, dmcp_canonical_map, ddp_codes),
    description = "Maps DDP DETLOCs to canonical facilities not already in DMCP data; three-tier matching: fuzzy OSA, county name, confirmed keyword"
  ),

  # ── Unified DETLOC lookup ────────────────────────────────────────────────
  # Combines DMCP, DDP, hold facility, and ERO sources into one table.
  # DDP (2023–2025) takes precedence over DMCP (2015–2017).
  # Hold/ERO mappings added after hold_canonical_data is built.
  tar_target(
    detloc_lookup,
    build_detloc_lookup(dmcp_canonical_map, ddp_canonical_map, hold_canonical_data,
                        vera_facilities),
    description = "Deduplicated 1:1 DETLOC-to-canonical_id mapping; source priority: DDP > DMCP > hold/ERO > Vera"
  ),
  tar_target(
    detloc_lookup_full,
    build_detloc_lookup_full(dmcp_canonical_map, ddp_canonical_map, hold_canonical_data,
                             vera_facilities),
    description = "Multi-row reference preserving all DETLOC variants from all sources, including ddp_role (sole/primary/component)"
  ),

  # ── DMCP supplemental listings ─────────────────────────────────────────────
  # Point-in-time authorization rosters with contract, operator, and
  # multi-year ADP data. Two sources: 2015 XLSX from ice.gov and 2017 PDF
  # from Prison Legal News. These are separate document types from the annual
  # FY stats files and are not merged into the main panel.

  # Download (cue = "never": re-run only via tar_invalidate())
  tar_target(
    faclist15_file,
    download_faclist15(),
    description = "Path to the 2015 DMCP XLSX",
    format = "file",
    cue = tar_cue(mode = "never")
  ),
  tar_target(
    faclist17_file,
    download_faclist17(),
    description = "Path to the 2017 DMCP PDF",
    format = "file",
    cue = tar_cue(mode = "never")
  ),

  # Raw import
  tar_target(faclist15_raw, import_faclist15(faclist15_file),
    description = "Raw import of the 2015 DMCP facility listing XLSX"),
  tar_target(faclist17_raw, import_faclist17(faclist17_file),
    description = "Raw import of the 2017 DMCP facility listing PDF (via tabulapdf)"),

  # Rename columns to project schema + clean
  tar_target(faclist15, rename_dmcp_columns(faclist15_raw) |> clean_dmcp_data(),
    description = "Cleaned 2015 DMCP roster with project-schema column names, ZIP zero-padding, and city corrections"),
  tar_target(faclist17, rename_dmcp_columns(faclist17_raw) |> repair_fl17_date_bleed() |> clean_dmcp_data(),
    description = "Cleaned 2017 DMCP roster with digit-bleed repair, column renames, and city corrections"),

  # ── The Marshall Project facility locations (1978–2017) ────────────────────
  # 1,479 facilities with DETLOCs, addresses, AOR, first/last use dates.
  # Import script: themarshallproject-locations.R
  tar_target(
    marshall_locations_file,
    download_marshall_locations(),
    description = "Path to downloaded Marshall Project CSV",
    format = "file",
    cue = tar_cue(mode = "never")
  ),
  tar_target(marshall_locations_raw, import_marshall_locations(marshall_locations_file),
    description = "Raw import of Marshall Project facility locations (CY 1978-Nov 2017)"),
  tar_target(marshall_locations, clean_marshall_locations(marshall_locations_raw),
    description = "Cleaned Marshall Project data with DETLOCs, addresses, AOR, first/last use dates, and geocoded lat/lon"),

  # ── DDP Daily Population Data ──────────────────────────────────────────────
  # Deportation Data Project: daily population data by facility, 2023-09-01 to 2025-10-15.
  # Provides operational detention facility codes and daily detention counts.
  tar_target(
    ddp_file,
    here::here("data/ddp/detention-facility-daily-population_filtered_20260312_031218.feather"),
    description = "Tracks the DDP feather file for changes",
    format = "file"
  ),
  tar_target(
    ddp_raw,
    arrow::read_feather(ddp_file)
  ),
  tar_target(
    ddp_codes,
    build_ddp_codes(ddp_raw)
  ),
  # Codes that appear in ddp_new (parquet, Oct 2022–Mar 2026) but not in
  # ddp_raw (feather, Sep 2023–Oct 2025). These were absent when the original
  # ddp_facility_canonical was built and need a separate ID-assignment pass.
  tar_target(
    ddp_codes_new,
    build_ddp_codes_new(ddp_new, ddp_raw),
    description = "DDP facility codes present in ddp_new (parquet) but not in ddp_raw (feather); input for extending ddp_facility_canonical"
  ),
  # ── DDP facility canonical IDs ──────────────────────────────────────────
  # Pass 1 (ddp_codes / ddp_raw): stable IDs 1054–1209 ddp_other, 3001–3226 medical.
  # Pass 2 (ddp_codes_new): hold/CBP → 2181+; other jails → 1210+; medical → 3227+.
  tar_target(
    ddp_facility_canonical,
    build_ddp_facility_canonical(ddp_codes, detloc_lookup_full, vera_facilities,
                                  ddp_codes_new),
    description = "Canonical IDs for all unmapped DDP facilities: ddp_raw-derived (1054+, 3001+) plus ddp_new-only codes (hold/CBP 2181+, jails 1210+, medical 3227+)"
  ),
  # ── Complete DETLOC lookup (all 962 canonical IDs) ───────────────────────
  # Extends detloc_lookup_full with ddp_facility_canonical (IDs 1054–1209 and
  # 3001–3226). Built after both to avoid the circular dependency where
  # ddp_facility_canonical itself depends on detloc_lookup_full.
  # Use this (not detloc_lookup_full) for any join that must cover all
  # canonical ID ranges, including DDP-only and medical facilities.
  tar_target(
    detloc_lookup_complete,
    build_detloc_lookup_complete(detloc_lookup_full, ddp_facility_canonical),
    description = "Full DETLOC lookup covering all 962 canonical IDs; adds ddp_facility_canonical (1054–1209, 3001–3226) to detloc_lookup_full"
  ),

  # ── DDP annual panel (FY23–FY26) ────────────────────────────────────────
  # Long-format panel: one row per (facility code × fiscal year) for all
  # fiscal years covered by ddp_new (Oct 2022–Mar 2026). Joins canonical IDs
  # via detloc_lookup_complete and facility metadata via facility_roster.
  # Rows with canonical_id = NA are retained for review.
  # Uses ddp_new (parquet) rather than ddp_raw (feather) for wider FY coverage.
  tar_target(
    ddp_annual_panel,
    build_ddp_annual_panel(ddp_new, detloc_lookup_complete, facility_roster),
    description = "DDP ADP panel: one row per (facility code x fiscal year) for FY23-FY26; canonical_id NA rows retained for review"
  ),

  # ── Expanded map panel ──────────────────────────────────────────────────
  # Merges facilities_panel (ICE annual stats, FY10–FY26) with ddp_annual_panel
  # (DDP, FY23–FY26). One row per (canonical_id × fiscal_year). Five-level
  # data_source flag: ice_only / ddp_only / ice_ddp_agree /
  # ice_ddp_diverge_high / ice_ddp_diverge_low. ICE is authoritative where
  # both exist. DDP-specific columns (peak, sex, n_days) are NA for ice_only
  # rows; ICE-specific columns (inspections, threat levels) are NA for ddp_only.
  tar_target(
    expanded_map_panel,
    build_expanded_map_panel(facilities_panel, ddp_annual_panel, threshold = 0.25),
    description = "Combined ICE + DDP panel: one row per (canonical_id x fiscal_year), data_source flag, ice_adp vs ddp_adp comparison"
  ),

  # ── Expanded map presence matrix ────────────────────────────────────────
  # Wide-format presence matrix for all canonical facilities in the expanded
  # panel. Inherits ICE trajectory labels for panel IDs (≤ 1000); non-panel
  # facilities get trajectory = "ddp_only".
  tar_target(
    expanded_map_presence,
    build_expanded_map_presence(expanded_map_panel, facility_presence),
    description = "Presence matrix for all expanded-panel facilities; trajectory inherited from facility_presence for panel IDs, 'ddp_only' for DDP-only ranges"
  ),

  # ── Expanded map geocoded facilities ─────────────────────────────────────
  # One row per canonical facility in the expanded panel with lat/lon from
  # facilities_geocoded_all. Facilities missing coordinates are retained with
  # lat/lon = NA. Metadata (name, city, type) from most recent ICE-preferred row.
  tar_target(
    expanded_map_geocoded,
    build_expanded_map_geocoded(expanded_map_panel, facilities_geocoded_all),
    description = "One row per canonical facility in expanded panel; lat/lon from facilities_geocoded_all, NA for ungeocoded facilities"
  ),

  # ── Expanded map export ───────────────────────────────────────────────────
  # cue = "never": run tar_make(expanded_map_export) explicitly to deploy.
  # Writes expanded_panel.rds, expanded_presence.rds, expanded_geocoded.rds
  # to data/expanded-map-export/; then run copy-data.sh in the post directory.
  tar_target(
    expanded_map_export,
    export_expanded_map_data(expanded_map_panel, expanded_map_presence,
                              expanded_map_geocoded),
    format = "file",
    cue   = tar_cue(mode = "never"),
    description = "Exports expanded_panel.rds, expanded_presence.rds, expanded_geocoded.rds to data/expanded-map-export/ for deployment"
  ),

  # ── Facility directory export ─────────────────────────────────────────────
  # cue = "never": run tar_make(facility_directory_export) explicitly to deploy.
  # Writes facility_tbl.rds to data/facility-directory-export/;
  # then run copy-data.sh in posts/facility-directory/.
  tar_target(
    facility_directory_export,
    export_facility_directory_data(
      expanded_map_geocoded, expanded_map_presence, expanded_map_panel,
      ddp_raw, detloc_lookup_complete, ddp_new
    ),
    format = "file",
    cue    = tar_cue(mode = "never"),
    description = "Exports facility_tbl.rds to data/facility-directory-export/ for the facility directory post"
  ),

  # ── DDP FY25 facility summary ────────────────────────────────────────────
  # One row per facility code with ADP breakdowns (total, midnight, sex,

  # criminality, age), peak population, and derived shares.
  tar_target(
    ddp_fy25_summary,
    build_ddp_fy_summary(ddp_raw, fy_start = "2024-10-01", fy_end = "2025-09-30"),
    description = "DDP daily population summarized to one row per facility for FY25; ADP by sex/criminality/age, peak population, and derived shares"
  ),
  tar_target(
    ddp_fy25_summary_file,
    {
      path <- here::here("data/ddp-fy25-summary.csv")
      readr::write_csv(ddp_fy25_summary, path)
      path
    },
    description = "Exports ddp_fy25_summary to data/ddp-fy25-summary.csv",
    format = "file"
  ),

  # ── ICE office node scan ────────────────────────────────────────────────────
  # Parses ice.gov/node/* pages for field_office entity bundles, yielding one
  # row per sub-office location (110 offices across 25 ERO field offices in
  # node range 62000-62300). HTML pages are cached to data/dhs-websites/ice-nodes/.
  # Re-run via tar_invalidate(ice_office_nodes) to fetch any new node range.
  tar_target(
    ice_office_nodes,
    scan_ice_field_office_nodes(
      node_range       = 62000:62300,
      html_cache_dir   = here::here("data/dhs-websites/ice-nodes"),
      index_cache_path = here::here("data/dhs-websites/ice-node-index.rds"),
      delay            = 0.5
    ),
    description = "110 ICE sub-office locations parsed from cached ice.gov/node/* pages (field_office entity bundles, node range 62000-62300)",
    cue = tar_cue(mode = "never")
  ),

  tar_target(
    ice_office_nodes_es,
    scan_ice_field_office_nodes(
      node_range       = 62000:62300,
      html_cache_dir   = here::here("data/dhs-websites/ice-nodes-es/"),
      index_cache_path = here::here("data/dhs-websites/ice-node-es-index.rds"),
      url_dir_prefix      = "https://ice.gov/es/node/",
      delay            = 0.5
    ),
    description = "110 ICE sub-office locations parsed from cached ice.gov/node/* pages (field_office entity bundles, node range 62000-62300)",
    cue = tar_cue(mode = "never")
  ),

  # ── Hold facility canonical integration ────────────────────────────────────
  # Classifies DDP hold-type facility codes, cross-references Marshall Project
  # for addresses/geocoding, assigns canonical IDs 2026+, and maps ERO hold
  # DETLOCs to their field office canonical IDs (2001–2025).
  tar_target(
    ero_canonical_file,
    here::here("data/ero-field-offices-canonical.csv"),
    description = "Tracks data/ero-field-offices-canonical.csv",
    format = "file"
  ),
  tar_target(
    ero_geocoded_file,
    here::here("data/ero-field-offices-geocoded.csv"),
    description = "Tracks data/ero-field-offices-geocoded.csv",
    format = "file"
  ),
  tar_target(
    ero_canonical,
    readr::read_csv(ero_canonical_file, show_col_types = FALSE),
    description = "25 ERO field offices with canonical IDs (2001-2025), DETLOCs, and addresses"
  ),
  tar_target(
    missing_hold_addresses_file,
    here::here("data/missing-hold-addresses.csv"),
    description = "Tracks data/missing-hold-addresses.csv for changes",
    format = "file"
  ),
  tar_target(
    missing_hold_addresses,
    readr::read_csv(missing_hold_addresses_file, show_col_types = FALSE),
    description = "Unified missing hold facility addresses from ICE node pages and Gemini (27 facilities)"
  ),
  tar_target(
    hold_canonical_registry_file,
    here::here("data/hold-canonical-registry.csv"),
    description = "Tracks data/hold-canonical-registry.csv for changes (frozen hold facility IDs)",
    format = "file"
  ),
  tar_target(
    hold_canonical_registry,
    readr::read_csv(hold_canonical_registry_file, show_col_types = FALSE),
    description = "Frozen registry of hold facility canonical IDs (2026+), keyed by detloc"
  ),
  tar_target(
    hold_canonical_data,
    build_hold_canonical(ddp_codes, marshall_locations, ero_canonical,
                         build_detloc_lookup(dmcp_canonical_map, ddp_canonical_map),
                         hold_canonical_registry,
                         vera_facilities = vera_facilities,
                         missing_hold_addresses = missing_hold_addresses),
    description = "Hold facility integration: hold_canonical (148+ facilities, IDs 2026+), ero_hold_map (23 ERO DETLOC mappings), and summary stats"
  ),

  # ── Vera Institute facility metadata ──────────────────────────────────────
  # 1,464 facility codes with geocoded locations, addresses, county, AOR,
  # and facility type classifications. Source: Vera ICE Detention Trends.
  tar_target(
    vera_facilities_file,
    here::here("data/vera-institute/facilities.csv"),
    description = "Tracks data/vera-institute/facilities.csv",
    format = "file"
  ),
  tar_target(
    vera_facilities_raw,
    import_vera_facilities(vera_facilities_file),
    description = "Raw import of Vera Institute facility metadata"
  ),
  tar_target(
    vera_facilities,
    clean_vera_facilities(vera_facilities_raw),
    description = "Cleaned Vera facility data with geocoded locations, addresses, county, AOR, and type classifications"
  ),

  # ── DDP comparison report ─────────────────────────────────────────────────
  # Renders ddp-comparison.qmd locally so changes can be reviewed before
  # deploying to the quarto website. The qmd reads pipeline targets directly
  # via tar_read(). After review, run the ddp_comparison_export target to
  # produce the pre-computed RDS files, then copy-data.sh to deploy.
  tar_quarto(
    ddp_comparison_report,
    "ddp-comparison.qmd",
    description = "Rendered DDP vs ICE FY25 comparison report; review locally before deploying to quarto website"
  ),

  tar_target(
    ddp_comparison_export,
    export_ddp_comparison_data(ddp_raw, facilities_all_keyed,
                               detloc_lookup_full, vera_facilities,
                               facility_roster,
                               facilities_geocoding_lookup),
    description = "Exports 11 RDS files to data/ddp-comparison-export/ for deploying the DDP comparison blog post",
    format = "file"
  ),

  # ── FY26 comparison data (parquet DDP vs Feb 2026 ICE release) ────────────
  # Uses the Feb 12 2026 ICE spreadsheet (data through 2026-02-05) and the
  # new parquet-format DDP file. Kept entirely separate from the main FY19–FY26
  # panel pipeline. Export target is cue = "never"; run explicitly when ready.

  tar_target(
    ddp_parquet_file,
    here::here("data/ddp/facilities-daily-population-latest.parquet"),
    description = "Tracks the DDP parquet file (Oct 2022 – Mar 2026) for changes",
    format = "file"
  ),
  tar_target(
    ddp_new,
    arrow::read_parquet(ddp_parquet_file),
    description = "Raw DDP daily population data from parquet (Oct 2022 – Mar 2026, 707 facilities)"
  ),

  tar_target(
    fy26b,
    build_fy26b(data_file_info, clean_names_list, facility_crosswalk, detloc_lookup),
    description = "Feb 12 2026 ICE spreadsheet: 220 facilities cleaned, aggregated, and keyed; 3 known IDs patched; 4 genuinely new"
  ),

  tar_target(
    ddp_fy26_keyed,
    build_ddp_fy26_keyed(ddp_new, fy26b, detloc_lookup, detloc_lookup_full),
    description = "DDP FY26 facility summary (Oct 2025 – Feb 5 2026) keyed via detloc_lookup; in_ice_fy26 flag marks matches to ICE FY26 spreadsheet"
  ),

  tar_target(
    daily_totals_fy26,
    build_daily_totals_fy26(ddp_new),
    description = "DDP total detained population per day for FY26 comparison period (Oct 2025 – Feb 5 2026)"
  ),

  tar_target(
    unmatched_fy26,
    build_unmatched_fy26(ddp_fy26_keyed, facility_roster),
    description = "DDP FY26 facilities not in ICE FY26 annual statistics, with type and address from facility_roster"
  ),

  tar_target(
    peak_fy26,
    build_peak_fy26(ddp_new, unmatched_fy26, facility_roster, facilities_geocoding_lookup),
    description = "Peak population summary for FY26 unmatched facilities with geocoding; sparklines added separately at export time"
  ),

  tar_target(
    ddp_fy26_comparison_export,
    export_ddp_fy26_comparison_data(
      ddp_new, fy26b, ddp_fy26_keyed, daily_totals_fy26, unmatched_fy26, peak_fy26
    ),
    description = "Exports 8 RDS files to data/ddp-comparison-export-fy26/ for FY26 comparison report (Oct 2025 – Feb 5 2026)",
    format = "file"
  ),

  # Renders ddp-comparison-26.qmd locally so changes can be reviewed before
  # deploying to the quarto website (posts/ddp-comparison-26/). The qmd reads
  # pipeline targets directly via tar_read(). After review, run the
  # ddp_fy26_comparison_export target to produce the pre-computed RDS files,
  # then copy-data.sh in the post directory to deploy.
  tar_quarto(
    ddp_fy26_comparison_report,
    "ddp-comparison-26.qmd",
    description = "Rendered DDP vs ICE FY26 comparison report; review locally before deploying to quarto website"
  ),

  # ── DDP stays dataset (one row per detention stay, incl. full facility chain) ─
  tar_target(
    stays_file,
    here::here("data/ddp/detention-stays-latest.parquet"),
    format = "file",
    description = "Tracks the DDP detention stays parquet file for changes"
  ),
  tar_target(
    stays_raw,
    arrow::read_parquet(stays_file),
    description = "Raw DDP detention stays (1.09M rows x 70 cols; one row per stay with detention_facility_codes_all chain)"
  ),

  # ── DDP arrests dataset ────────────────────────────────────────────────────
  tar_target(
    arrests_file,
    here::here("data/ddp/arrests-latest.parquet"),
    format = "file",
    description = "Tracks the DDP arrests parquet file for changes"
  ),
  tar_target(
    arrests_raw,
    arrow::read_parquet(arrests_file),
    description = "Raw DDP arrests (713k rows x 28 cols; one row per arrest event with apprehension_state, date, unique_identifier)"
  ),

  # ── Minnesota post-inauguration arrest analysis ────────────────────────────
  tar_target(
    mn_arrests_data,
    build_mn_arrests_data(
      arrests      = arrests_raw,
      stays        = stays_raw,
      detloc_lookup = detloc_lookup_complete,
      geo_all      = readr::read_csv(
        here::here("data/facilities-geocoded-all.csv"),
        show_col_types = FALSE
      )
    ),
    description = "Pre-computed tables for mn-arrests.qmd: MN post-2025-01-20 arrest itineraries, county choropleth, Sankey, minors"
  ),
  tar_quarto(
    state_arrests_report,
    "state-arrests.qmd",
    execute_params = list(state = "MINNESOTA", cutoff = "2025-01-20"),
    description = "Rendered state-arrests.qmd for Minnesota post-2025-01-20 (parameterized; render for other states with quarto render state-arrests.qmd -P state:TEXAS)"
  ),
  tar_quarto(
    nationwide_arrests_report,
    "nationwide-arrests.qmd",
    execute_params = list(cutoff = "2025-01-20"),
    description = "Rendered nationwide-arrests.qmd: state + county choropleths of post-2025-01-20 ICE arrests"
  ),

  # ── State arrests web export (cue = "never") ───────────────────────────────
  # Pre-computes nationwide.rds + one {abbr}.rds per state for the
  # ice-arrests-by-state Quarto website. Run tar_make(state_arrests_export)
  # explicitly, then run copy-data.sh in the website directory.
  tar_target(
    state_arrests_export,
    export_state_arrests(
      arrests      = arrests_raw,
      stays        = stays_raw,
      detloc_lookup = detloc_lookup_complete,
      geo_all      = readr::read_csv(
        here::here("data/facilities-geocoded-all.csv"), show_col_types = FALSE
      ),
      census_file  = here::here("data/census/NST-EST2025-POP.xlsx"),
      pew_file     = here::here("data/pew/RE_2025.08.21_Unauthorized-immigrants_detailed-tables_characteristics-for-states.xlsx"),
      cutoff       = as.Date("2025-01-20"),
      data_end     = as.Date("2026-03-31"),
      export_dir   = here::here("data/state-arrests-export")
    ),
    cue    = tar_cue("never"),
    format = "file",
    description = "Exports nationwide.rds + 51 per-state RDS files for ice-arrests-by-state website (cue=never)"
  ),

  # ── Detention stints data (DDP individual-level) ───────────────────────────
  # Individual-level FOIA data: one row per detention stint (one continuous
  # period at one facility within a stay). Source: DDP FOIA 2026-ICLI-00005.
  # Re-download via tar_invalidate(stints_file) when a new release is available.
  tar_target(
    stints_file,
    here::here("data/ddp/detention-stints-latest.parquet"),
    description = "Tracks the DDP detention stints parquet file for changes",
    format = "file"
  ),
  tar_target(
    stints_raw,
    arrow::read_parquet(stints_file),
    description = "Raw DDP detention stints (2.6M rows x 61 cols; FY23-FY26, one row per facility stint)"
  ),

  # ── Facility profiles (before/after Trump inauguration) ─────────────────────
  # Pre-computes all summary tables for the facility-profiles.qmd report.
  # Covers five facility groups split at 2025-01-20 (inauguration day).
  tar_target(
    facility_profiles_data,
    build_facility_profiles_data(
      stints          = stints_raw,
      ddp_pop         = ddp_new,
      facilities_panel = facilities_panel,
      detloc_lookup   = detloc_lookup_complete
    ),
    description = "Before/after 2025-01-20 facility profiles for IWAHOLD, SPMHOLD, PINEPLA, DILLEY, NWDC"
  ),
  tar_quarto(
    facility_profiles_report,
    "facility-profiles.qmd",
    description = "Rendered facility-profiles.qmd: before/after inauguration profiles for five facility groups"
  ),

  # ── Facility summary report ────────────────────────────────────────────────
  # Quarto report summarizing facility counts, types, and source coverage.
  # Re-renders when any upstream target it reads changes.
  tar_quarto(
    facility_summary_report,
    "facility-summary.qmd",
    description = "Rendered facility-summary.qmd Quarto report; re-renders when upstream targets change"
  ),

  # ── Geocoding divergence  report ────────────────────────────────────────
  # Quarto report summarizing geocoding divergences between Google results
  # and source-provided coordinates, with maps and tables. Re-renders when
  # facilities_geocoded_all changes.
  tar_quarto(
    geocoding_divergence_report,
    "geocoding-divergence.qmd",
    description = "Rendered geocoding-divergence.qmd; maps and tables of Google vs. source coordinate divergences"
  ),

  # ── Targets catalog ──────────────────────────────────────────────────────
  # Auto-generates data/targets-catalog.md with hand-maintained descriptions
  # (in R/catalog.R) and current dimensions from tar_read_raw().
  # Depends on saved_files so all data targets are built first.
  tar_target(
    targets_catalog,
    generate_targets_catalog(),
    description = "Auto-generates data/targets-catalog.md with hand-maintained descriptions and current dimensions",
    format = "file"
  )
)
