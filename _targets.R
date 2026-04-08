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
  # Frozen mapping of canonical IDs 1–398 (FY19–FY26 facilities).
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
    description = "Frozen registry of canonical IDs 1-398 (FY19-FY26 facilities); append-only, new annual stats extend from 399"
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
    description = "One row per panel facility (IDs 1-398) with most recent address, city, state, ZIP, and DETLOC; input for geocoding and wiki matching"
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
  # ── DDP facility canonical IDs ──────────────────────────────────────────
  # Assigns canonical IDs to 376 DDP facility codes not in detloc_lookup_full.
  # Medical → 3001+; non-medical remainder → 1054+.
  tar_target(
    ddp_facility_canonical,
    build_ddp_facility_canonical(ddp_codes, detloc_lookup_full, vera_facilities),
    description = "Assigns canonical IDs to unmapped DDP facilities: non-medical at 1054+, medical at 3001+"
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
                         vera_facilities = vera_facilities),
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
                               detloc_lookup_full, vera_facilities),
    description = "Exports 11 RDS files to data/ddp-comparison-export/ for deploying the DDP comparison blog post",
    format = "file",
    cue = tar_cue("never")
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
