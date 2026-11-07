# Pipeline targets catalog generator.
# Produces data/targets-catalog.md with hand-maintained descriptions
# and auto-populated dimensions from tar_meta() / tar_read_raw().

# ── Target descriptions ──────────────────────────────────────────────────────
# Hand-maintained. Each target has a section (for grouping) and a description.
# Add new entries here when adding targets to _targets.R.

target_descriptions <- function() {
  tibble::tribble(
    ~target, ~section, ~description,

    # Core annual stats pipeline
    "data_file_info", "Core annual stats pipeline",
    "Spreadsheet URLs, sheet names, header row positions, and rightmost data columns for each FY19--FY26 XLSX file.",

    "raw_xlsx_files", "Core annual stats pipeline",
    "Local paths to downloaded ICE annual stats XLSX files. **cue = \"never\"**.",

    "clean_names_list", "Core annual stats pipeline",
    "Clean variable name vectors (one per fiscal year), derived from the 2-row merged Excel headers.",

    "facilities_raw", "Core annual stats pipeline",
    "Raw tibbles imported from each XLSX file, one per fiscal year (FY19--FY26).",

    "facilities_clean", "Core annual stats pipeline",
    "Cleaned tibbles with standardized facility names, city corrections, type coercion, and Guantanamo patch.",

    "facilities_aggregated", "Core annual stats pipeline",
    "Aggregated tibbles with row-level ADP sums, `share_non_crim`, `share_no_threat`, and `facility_type_wiki` classification.",

    "id_registry_file", "Core annual stats pipeline",
    "Tracks `data/canonical_id_registry.csv` for changes.",

    "id_registry", "Core annual stats pipeline",
    "Frozen registry of canonical IDs 1--398 (FY19--FY26 facilities). Append-only; new annual stats extend from 399.",

    "facility_crosswalk", "Core annual stats pipeline",
    "Maps every (name, city, state) variant observed across FY19--FY26 to a `canonical_id` and `canonical_name`. Built via exact + fuzzy address matching.",

    "facilities_keyed", "Core annual stats pipeline",
    "FY19--FY26 aggregated data with `canonical_id`, `canonical_name`, and `detloc` joined from the crosswalk and DETLOC lookup.",

    "facilities_all_keyed", "Core annual stats pipeline",
    "Merged FY10--FY26 (minus FY18). Combines `facilities_keyed` (FY19--26, including both FY26 snapshots) with `facilities_annual_sums` (FY10--17); adds `adp` column to FY19--26.",

    "facilities_all_keyed_interim", "Core annual stats pipeline",
    "`facilities_all_keyed` with the three FY26 snapshots resolved in a cascade: July values win, Feb 12 rows fill in for facilities dropped from the July file, Feb 2 rows fill in for facilities dropped from both. Basis for the registry, roster, presence, and canonical list.",

    "facility_presence", "Core annual stats pipeline",
    "One row per canonical facility with FY10--FY26 boolean presence columns and a trajectory label (`continuous`, `persistent_gaps`, `closed`, `new`, `transient`). Built from the interim lists; FY26 presence = any snapshot.",

    "facilities_panel", "Core annual stats pipeline",
    "Long-format panel: one row per facility per year (FY10--FY26, minus FY18). All ~30 measurement variables plus canonical IDs and DETLOCs. FY26 = July 20 snapshot only; used for the \"reported by ICE\" side of the DDP comparison analyses. `fy26_snapshot` column (b/c) follows `fiscal_year`.",

    "facilities_panel_interim", "Core annual stats pipeline",
    "`facilities_panel` variant in which FY26 also includes Feb 12 and Feb 2 rows for facilities dropped from the July file. Used for the registry, roster, canonical list, profiles, and expanded map. `fy26_snapshot` column marks each FY26 row's source.",

    "panel_facilities", "Core annual stats pipeline",
    "One row per panel facility (IDs 1--405) with the most recent address, city, state, ZIP, DETLOC, and facility_type_wiki; built from the interim panel. Input for geocoding and wiki matching.",

    "facility_roster", "Core annual stats pipeline",
    "Full roster: one row per canonical facility (~962) across all ID ranges with best-available address, type, DETLOC, and geocoding.",

    # Geocoding
    "facilities_geocoded", "Geocoding",
    "*RENAMED — no longer wired in.* Superseded by `facilities_google_geocoded`, which geocodes the full roster (all ID ranges) with an incremental cache rather than only IDs 1--398. **cue = \"never\"**.",

    "facilities_geocoded_full", "Geocoding",
    "*RENAMED — no longer wired in.* Superseded by `facilities_google_geocoded`: Google geocoding now covers DMCP-only and hold facilities directly via the roster, so the two-stage split no longer exists. **cue = \"never\"**.",

    "facilities_geocoded_all", "Geocoding",
    "Unified geocoded table merging Google Maps, ERO, Marshall Project, and Vera coordinates with a `geocode_source` column.",

    "facilities_google_geocoded", "Geocoding",
    "Google Maps API geocoded coordinates for all roster facilities (~962, all ID ranges), with an incremental CSV cache so only new/changed addresses hit the API. Renamed from the former `facilities_geocoded`.",

    "facilities_geocoding_lookup", "Geocoding",
    "Compact address + coordinates lookup derived from `facilities_geocoded_all`, used by the DDP comparison exports.",

    "google_geocoded_file", "Geocoding",
    "Archives `facilities_google_geocoded` to `data/google-geocoded-facilities.csv` (format = \"file\").",

    "facilities_geocoded_all_file", "Geocoding",
    "Tracks `data/facilities-geocoded-all.csv` for changes (format = \"file\").",

    # DMCP supplemental listings
    "faclist15_file", "DMCP supplemental listings",
    "Path to the 2015 DMCP XLSX. **cue = \"never\"**.",

    "faclist17_file", "DMCP supplemental listings",
    "Path to the 2017 DMCP PDF. **cue = \"never\"**.",

    "faclist15_raw", "DMCP supplemental listings",
    "Raw import of the 2015 DMCP facility listing XLSX.",

    "faclist17_raw", "DMCP supplemental listings",
    "Raw import of the 2017 DMCP facility listing PDF (via tabulapdf).",

    "faclist15", "DMCP supplemental listings",
    "Cleaned 2015 DMCP roster with project-schema column names, ZIP zero-padding, and city corrections.",

    "faclist17", "DMCP supplemental listings",
    "Cleaned 2017 DMCP roster with digit-bleed repair, column renames, and city corrections.",

    "dmcp_canonical_map", "DMCP supplemental listings",
    "Maps every DMCP DETLOC to a canonical_id via 3-pass matching (exact, manual, new IDs from 1001+).",

    "faclist15_keyed", "DMCP supplemental listings",
    "faclist15 with `canonical_id`, `canonical_name`, and `match_type` prepended.",

    "faclist17_keyed", "DMCP supplemental listings",
    "faclist17 with `canonical_id`, `canonical_name`, and `match_type` prepended.",

    "facilities_annual_sums", "DMCP supplemental listings",
    "Per-fiscal-year tables (FY10--FY17) with one row per facility with non-zero ADP. Built from faclist15/faclist17 data.",

    # DDP daily population data
    "ddp_file", "DDP daily population data",
    "Tracks the DDP feather file for changes.",

    "ddp_raw", "DDP daily population data",
    "Raw daily detention population data from the Deportation Data Project (Sep 2023--Oct 2025). One row per facility per day.",

    "ddp_codes", "DDP daily population data",
    "Distinct cleaned facility codes extracted from `ddp_raw`.",

    "ddp_facility_canonical", "DDP daily population data",
    "Assigns canonical IDs to 376 unmapped DDP facility codes: 150 non-medical (IDs 1054--1203) and 226 medical (IDs 3001--3226). Uses Vera Institute metadata for addresses and types.",

    "ddp_fy25_summary", "DDP daily population data",
    "DDP daily population summarized to one row per facility for FY25 (Oct 2024--Sep 2025). ADP by sex/criminality/age, peak population, and derived shares.",

    "ddp_fy25_summary_file", "DDP daily population data",
    "Exports `ddp_fy25_summary` to `data/ddp-fy25-summary.csv`. format = \"file\".",

    "ddp_canonical_map", "DDP daily population data",
    "Maps DDP DETLOCs to canonical facilities not already in DMCP data. Three-tier matching: fuzzy OSA, county name, confirmed keyword.",

    "ddp_codes_new", "DDP daily population data",
    "Facility codes present in the 20260806 parquet (`ddp_new`) but absent from the legacy feather (`ddp_raw`). Feeds pass 2 of `ddp_facility_canonical` (hold/CBP → 2181+, other jails → 1210+, medical → 3227+).",

    # DDP arrests and stints
    "arrests_file", "DDP arrests and stints",
    "Tracks the DDP arrests parquet (`data/ddp/arrests-latest_20260806.parquet`) for changes. This value is hard-coded and needs to be updated when new releases are published and downloaded.",

    "arrests_raw", "DDP arrests and stints",
    "Raw DDP arrests (20260806 release: ~896k rows, Oct 2022--Aug 2026; one row per arrest event), schema-normalized back to the pre-20260806 column names (`apprehension_state`, `apprehension_site_landmark`; `apprehension_type` restored as all-NA).",

    "stays_file", "DDP arrests and stints",
    "Tracks the DDP detention stays parquet (`data/ddp/detention-stays-latest_20260806.parquet`) for changes. Wired 2026-10-21; the 20260514 release remains on disk as a frozen archive.",

    "stays_raw", "DDP arrests and stints",
    "Raw DDP detention stays (20260806 release: ~1.26M rows x 77 cols; one row per stay with the `detention_facility_codes_all` chain). Source for mn-arrests, state-arrests, nationwide-arrests, and the per-state website export.",

    "stints_file", "DDP arrests and stints",
    "Tracks the DDP detention stints parquet (`data/ddp/detention-stints-latest_20260806.parquet`) for changes.",

    "stints_raw", "DDP arrests and stints",
    "Raw DDP detention stints (20260806 release: ~3.2M rows; one row per facility stint, book-ins Oct 2021--Aug 2026). Source for the recreated daily-population file, throughput report, and facility profiles.",

    "mn_arrests_data", "DDP arrests and stints",
    "Pre-computed tables for `mn-arrests.qmd`: Minnesota post-2025-01-20 arrest itineraries, county choropleth, facility map, Sankey, removal grid, and minors sub-analysis.",

    "nationwide_arrests_report", "DDP arrests and stints",
    "Rendered `nationwide-arrests.qmd`: state and county choropleths of post-2025-01-20 ICE arrests.",

    "state_arrests_export", "DDP arrests and stints",
    "Exports `nationwide.rds` + 51 per-state RDS files to `data/state-arrests-export/` for the ice-arrests-by-state website. **cue = \"never\"**.",

    "ddp_throughput_report", "DDP arrests and stints",
    "Rendered `ddp-throughput.qmd`: person-level detention throughput from stints (daily population/removals/book-ins, cumulative distinct individuals, re-detention, presidential comparison windows).",

    "facility_profiles_data", "DDP arrests and stints",
    "Before/after 2025-01-20 facility profiles (ADP, nationalities, criminality, outcomes, age bands) for selected facility groups, built from stints. **cue = \"never\"**.",

    "facility_profiles_report", "DDP arrests and stints",
    "Rendered `facility-profiles.qmd` Quarto report. **cue = \"never\"**.",

    "ddp_parquet_file", "DDP daily population data",
    "Tracks the DDP 20260330 daily-population parquet (Oct 2022--Mar 2026, DDP's last published release, renamed with version suffix) for changes.",

    "ddp_new", "DDP daily population data",
    "DDP daily population from parquet, frozen 20260330 release (Oct 2022--Mar 2026, 707 facilities). Feeds `ddp_codes_new`, `ddp_annual_panel`, facility profiles/directory, and the archived through-March FY26 comparison.",

    "facilities_daily_population_file", "DDP daily population data",
    "Recreated DDP daily-population parquet (Oct 2022--Aug 5 2026, 740 facilities) written to `data/ddp/` from the 20260806 stints via `build_ddp_daily_population()`. DDP no longer publishes this file.",

    "facilities_daily_population", "DDP daily population data",
    "Current DDP daily population (Oct 2022--Aug 5 2026, 740 facility codes), recreated from the 20260806 stints; source for the current FY26 comparison chain. Validated: the same method reproduces the published 20260330 file exactly.",

    # FY26 comparison pipeline (DDP daily population vs Feb 2026 ICE release)
    "fy26b", "FY26 comparison pipeline",
    "Feb 12 2026 ICE snapshot (the FY26b element of `facilities_keyed`) with the known-ID patches applied; basis for the `in_ice_fy26` flag.",

    "ddp_fy26_keyed", "FY26 comparison pipeline",
    "DDP FY26 facility summary (Oct 2025--Feb 5 2026) keyed via detloc_lookup; `in_ice_fy26` flag marks matches to the ICE FY26 spreadsheet. Uses current (20260806) DDP data.",

    "daily_totals_fy26", "FY26 comparison pipeline",
    "DDP total detained population per day, Jan 2025--Aug 5 2026 (current 20260806 data).",

    "unmatched_fy26", "FY26 comparison pipeline",
    "DDP FY26 facilities not in ICE FY26 annual statistics, with type and address from `facility_roster`.",

    "peak_fy26", "FY26 comparison pipeline",
    "Peak population summary for FY26 unmatched facilities with geocoding; sparklines added separately at export time.",

    "ddp_fy26_comparison_export", "FY26 comparison pipeline",
    "Exports 8 RDS files + `_provenance.json` to `data/ddp-comparison-export-fy26/` for the FY26 comparison report (Oct 2025--Feb 5 2026; current 20260806 DDP data). Each RDS carries a `provenance` attribute.",

    "ddp_fy26_comparison_report", "FY26 comparison pipeline",
    "Rendered DDP vs ICE FY26 comparison report (current 20260806 DDP data); review locally before deploying to quarto website.",

    "ddp_fy26_keyed_20260330", "FY26 comparison pipeline",
    "Archived through-March DDP FY26 keyed summary (Oct 2025--Feb 5 2026) from the frozen 20260330 parquet.",

    "daily_totals_fy26_20260330", "FY26 comparison pipeline",
    "Archived through-March daily totals (Jan 2025--Mar 10 2026) from the frozen 20260330 parquet.",

    "unmatched_fy26_20260330", "FY26 comparison pipeline",
    "Archived through-March unmatched DDP FY26 facilities (frozen 20260330 data).",

    "peak_fy26_20260330", "FY26 comparison pipeline",
    "Archived through-March peak population summary for unmatched facilities (frozen 20260330 data).",

    "ddp_fy26_comparison_export_20260330", "FY26 comparison pipeline",
    "Archived through-March FY26 comparison export (8 RDS files to `data/ddp-comparison-export-fy26-20260330/`); frozen reference.",

    "ddp_fy26_comparison_20260330_report", "FY26 comparison pipeline",
    "Archived through-March FY26 comparison report (`ddp-comparison-26-20260330.qmd`, frozen DDP 20260330 data); preserved snapshot of the pre-20260806 analysis.",

    # Unified DETLOC lookup
    "detloc_lookup", "Unified DETLOC lookup",
    "Deduplicated 1:1 mapping of DETLOC to `canonical_id`. Each DETLOC and each canonical_id appears at most once. Source priority: DDP > DMCP > hold/ERO > Vera.",

    "detloc_lookup_full", "Unified DETLOC lookup",
    "Multi-row reference preserving all DETLOC variants from all sources, including `ddp_role` (sole/primary/component). Use when matching all known codes for a facility.",

    "detloc_lookup_complete", "Unified DETLOC lookup",
    "Extends `detloc_lookup_full` with `ddp_facility_canonical` mappings (IDs 1054--1209, 3001--3226), covering all ~962 canonical facilities.",

    # Hold facility and ERO integration
    "ero_canonical_file", "Hold facility and ERO integration",
    "Tracks `data/ero-field-offices-canonical.csv`.",

    "ero_geocoded_file", "Hold facility and ERO integration",
    "Tracks `data/ero-field-offices-geocoded.csv`.",

    "ero_canonical", "Hold facility and ERO integration",
    "25 ERO field offices with canonical IDs (2001--2025), DETLOCs, and addresses.",

    "hold_canonical_data", "Hold facility and ERO integration",
    "Hold facility integration results: `hold_canonical` (148 hold facilities, IDs 2026--2173), `ero_hold_map` (23 ERO DETLOC mappings), and summary statistics.",

    "hold_canonical_registry_file", "Hold facility and ERO integration",
    "Tracks `data/hold-canonical-registry.csv` for changes: frozen hold-facility canonical IDs, append-only.",

    "hold_canonical_registry", "Hold facility and ERO integration",
    "Frozen registry of hold facility canonical IDs (2026+), keyed by detloc. Read by `build_hold_canonical()` so existing IDs are preserved on reruns.",

    "missing_hold_addresses_file", "Hold facility and ERO integration",
    "Tracks `data/missing-hold-addresses.csv` for changes.",

    "missing_hold_addresses", "Hold facility and ERO integration",
    "Addresses for 27 hold facilities missing from the Marshall Project data, gathered from ICE node pages and Gemini, fed to `build_hold_canonical()`.",

    "ice_office_nodes", "Hold facility and ERO integration",
    "110 ICE sub-office locations parsed from cached ice.gov/node/* pages (field_office entity bundles, node range 62000--62300). **cue = \"never\"**; re-fetch new node ranges with `tar_invalidate(ice_office_nodes)`.",

    "ice_office_nodes_es", "Hold facility and ERO integration",
    "Spanish-language variant of `ice_office_nodes`, parsed from cached ice.gov/es/node/* pages. **cue = \"never\"**.",

    # Marshall Project locations
    "marshall_locations_file", "Marshall Project locations",
    "Path to downloaded CSV. **cue = \"never\"**.",

    "marshall_locations_raw", "Marshall Project locations",
    "Raw import of Marshall Project facility locations (CY 1978--Nov 2017).",

    "marshall_locations", "Marshall Project locations",
    "Cleaned Marshall Project data with DETLOCs, addresses, AOR, first/last use dates, and geocoded lat/lon.",

    # Vera Institute facility metadata
    "vera_facilities_file", "Vera Institute facility metadata",
    "Tracks `data/vera-institute/facilities.csv`.",

    "vera_facilities_raw", "Vera Institute facility metadata",
    "Raw import of Vera Institute facility metadata.",

    "vera_facilities", "Vera Institute facility metadata",
    "Cleaned Vera facility data with geocoded locations, addresses, county, AOR, and type classifications (`type_grouped`, `type_detailed`).",

    # Wikipedia harmonization
    "wiki_detention_table", "Wikipedia harmonization",
    "Scraped pinned revision of the Wikipedia \"List of immigrant detention sites\" wikitable. Broad historical table. **cue = \"never\"**.",

    "wiki_detention_table_current", "Wikipedia harmonization",
    "Current live revision of the Wikipedia table. **cue = \"never\"**; update oldid in `_targets.R` after article edits.",

    "wiki_match_table", "Wikipedia harmonization",
    "City/state alias matches between ICE FY26 facility names and Wikipedia table names.",

    "facilities_fy26_wiki_search", "Wikipedia harmonization",
    "Wikipedia API search results for each FY26 facility name. **cue = \"never\"**.",

    "contractors_patch_file", "Wikipedia harmonization",
    "Tracks `data/contractors-patch-fy26.csv` for changes.",

    "facilities_fy26_wiki", "Wikipedia harmonization",
    "FY26 facilities with `wiki_match`, `wiki_slug`, and `management` columns. Applies slug overrides, contractors patch, fl17 management backfill, and standardization.",

    "canonical_wiki_match", "Wikipedia harmonization",
    "All canonical facilities matched to Wikipedia articles via 4-pass matching (direct name, city/state alias, manual, external API).",

    "fy26_wikitable", "Wikipedia harmonization",
    "MediaWiki table markup for active facilities in the Wikipedia list article.",

    "closed_wikitable", "Wikipedia harmonization",
    "MediaWiki table markup for closed facilities in the Wikipedia list article.",

    "facilities_fy25_26_union", "Wikipedia harmonization",
    "Union of the FY25 and FY26 ICE spreadsheets (all three FY26 snapshots; July values win, then Feb 12, then Feb 2, then FY25 rows): one row per listed facility.",

    "wiki_match_table_fy25_26", "Wikipedia harmonization",
    "City/state alias matches between FY25--FY26 union facility names and Wikipedia table names.",

    "facilities_fy25_26_new_search", "Wikipedia harmonization",
    "Wikipedia API search results for union facility names not already covered by the FY26 search. **cue = \"never\"**.",

    "facilities_fy25_26_wiki", "Wikipedia harmonization",
    "FY25--FY26 union facilities with `wiki_match`, `wiki_slug`, and `management` columns; same enrichment chain as `facilities_fy26_wiki`.",

    "fy25_26_wikitable", "Wikipedia harmonization",
    "MediaWiki markup for the FY25--FY26 section of the Wikipedia list article: `==Centers active in Fiscal Years 2025 and 2026==` heading, the full wikitable (all facilities listed in the FY25 or FY26 ICE spreadsheets; \"Active (FYxx -- FY26)\" / \"Closed (Active ... -- FY25)\" status), and the data-provenance source note with named refs.",

    "fy25_26_city_link_check", "Wikipedia harmonization",
    "City-link scan for the FY25--FY26 wikitable: one row per distinct City wikilink target, checked against the live Wikipedia API for existence, redirect, and disambiguation-page status; problem rows sorted first. Review before each upload.",

    "facilities_fy21_24_union", "Wikipedia harmonization",
    "Union of FY21--FY24 ICE annual-stats rows for the FY21--FY24 era section: one row per listed facility, latest year's values win, within-year duplicate canonical rows keep their first (main) row.",

    "wiki_match_table_fy21_24", "Wikipedia harmonization",
    "City/state alias matches between FY21--FY24 union facility names and Wikipedia table names.",

    "facilities_fy21_24_new_search", "Wikipedia harmonization",
    "Wikipedia API search results for FY21--FY24 union names not covered by the FY26/FY25--FY26 searches. **cue = \"never\"**.",

    "facilities_fy21_24_wiki", "Wikipedia harmonization",
    "FY21--FY24 union facilities with wiki columns; same enrichment chain as `facilities_fy25_26_wiki` plus fl17 capacity backfill.",

    "fy21_24_wikitable", "Wikipedia harmonization",
    "MediaWiki markup for the `==Centers active in Fiscal Years 2021 through 2024==` section: heading, wikitable (status capped at FY24), and source note.",

    "fy21_24_city_link_check", "Wikipedia harmonization",
    "City-link scan for the FY21--FY24 wikitable.",

    "facilities_fy17_20_union", "Wikipedia harmonization",
    "Union of FY17, FY19, and FY20 ICE rows for the FY17--FY20 era section (FY18 unavailable). FY17 ADP is partial-year (~9.5 months, from the 2017 DMCP listing).",

    "wiki_match_table_fy17_20", "Wikipedia harmonization",
    "City/state alias matches between FY17--FY20 union facility names and Wikipedia table names.",

    "facilities_fy17_20_new_search", "Wikipedia harmonization",
    "Wikipedia API search results for FY17--FY20 union names not covered by earlier searches. **cue = \"never\"**.",

    "facilities_fy17_20_wiki", "Wikipedia harmonization",
    "FY17--FY20 union facilities with wiki columns; same enrichment chain as `facilities_fy25_26_wiki` plus fl17 capacity backfill.",

    "fy17_20_wikitable", "Wikipedia harmonization",
    "MediaWiki markup for the `==Centers active in Fiscal Years 2017 through 2020==` section: heading, wikitable (status capped at FY20), and source note.",

    "fy17_20_city_link_check", "Wikipedia harmonization",
    "City-link scan for the FY17--FY20 wikitable.",

    "facilities_fy10_16_union", "Wikipedia harmonization",
    "Union of FY10--FY16 DMCP-derived rows (from `facilities_annual_sums`) for the FY10--FY16 era section; one row per listed facility, latest year's values win.",

    "wiki_match_table_fy10_16", "Wikipedia harmonization",
    "City/state alias matches between FY10--FY16 union facility names and Wikipedia table names.",

    "facilities_fy10_16_new_search", "Wikipedia harmonization",
    "Wikipedia API search results for FY10--FY16 union names not covered by earlier searches. **cue = \"never\"**.",

    "facilities_fy10_16_wiki", "Wikipedia harmonization",
    "FY10--FY16 union facilities with wiki columns; same enrichment chain as `facilities_fy25_26_wiki` plus fl17 capacity backfill.",

    "fy10_16_wikitable", "Wikipedia harmonization",
    "MediaWiki markup for the `==Centers active in Fiscal Years 2010 through 2016==` section: heading, wikitable (status capped at FY16), and source note.",

    "fy10_16_city_link_check", "Wikipedia harmonization",
    "City-link scan for the FY10--FY16 wikitable.",

    "wiki_last_upload_oldid", "Wikipedia harmonization",
    "Revision ID of our last upload of the Wikipedia list article (diff base for recording editor changes).",

    "wiki_article_current_oldid", "Wikipedia harmonization",
    "Pinned current revision ID of the Wikipedia list article; update when re-scraping.",

    "wiki_last_upload_wikitext", "Wikipedia harmonization",
    "Wikitext of our last uploaded article revision. **cue = \"never\"**.",

    "wiki_article_current_wikitext", "Wikipedia harmonization",
    "Wikitext of the current pinned article revision. **cue = \"never\"**.",

    "wiki_editor_changes", "Wikipedia harmonization",
    "Cell-level record of editor changes to the article table since our last upload (cell edits, refs, link fixes, added/removed rows), plus article rows absent from our FY25--FY26 data.",

    "wiki_list_extant_articles", "Wikipedia harmonization",
    "Existence, redirect, and disambiguation status of every Wikipedia article linked from the list-article facility tables (pinned and current scrapes, with redirect-target verification). **cue = \"never\"**.",

    "wiki_article_collection_map", "Wikipedia harmonization",
    "Maps each extant article linked from the list-article tables to a Zotero collection name (canonical facility name where matched, article title otherwise).",

    "wiki_editor_changes_file", "Wikipedia harmonization",
    "Writes `data/wiki-editor-changes.csv` (record of editor changes since last upload).",

    # Expanded map and directory
    "ddp_annual_panel", "Expanded map and directory",
    "Annual (fiscal-year) ADP panel built from the DDP 20260806 parquet, keyed to canonical IDs via `detloc_lookup_complete`. Input for the expanded map.",

    "expanded_map_panel", "Expanded map and directory",
    "Long panel merging the ICE annual stats panel with `ddp_annual_panel` for the expanded Leaflet map; includes facilities with DDP presence at a 25% coverage threshold.",

    "expanded_map_presence", "Expanded map and directory",
    "Presence matrix (first/last seen, years covered) for expanded map facilities, combining annual-stats and DDP coverage.",

    "expanded_map_geocoded", "Expanded map and directory",
    "Geocoded coordinates for expanded map facilities, joined from `facilities_geocoded_all`.",

    "expanded_map_export", "Expanded map and directory",
    "Exports `expanded_panel.rds`, `expanded_presence.rds`, `expanded_geocoded.rds` to `data/expanded-map-export/` for the ice-detention-map-expanded website post. **cue = \"never\"**.",

    "facility_directory_export", "Expanded map and directory",
    "Exports `facility_tbl.rds` to `data/facility-directory-export/` for the reactable facility directory post (~618 facilities with peak ADP >= 2, sparklines from DDP daily data). **cue = \"never\"**.",

    # Source presence and outputs
    "source_presence", "Source presence and outputs",
    "One row per canonical facility (all ID ranges) with boolean flags for each data source (ICE stats, DMCP, DDP, Marshall, Vera, geocoded, etc.).",

    "saved_files", "Source presence and outputs",
    "Exported RDS + CSV files written to `data/` (crosswalk, presence, panel, source_presence).",

    "facility_summary_report", "Source presence and outputs",
    "Rendered `facility-summary.qmd` Quarto report. Re-renders when upstream targets change.",

    "geocoding_divergence_report", "Source presence and outputs",
    "Rendered `geocoding-divergence.qmd`; maps and tables of Google vs. source coordinate divergences.",

    "ddp_comparison_report", "Source presence and outputs",
    "Rendered `ddp-comparison.qmd` locally; review before deploying to quarto website.",

    "ddp_comparison_export", "Source presence and outputs",
    "Exports 11 RDS files to `data/ddp-comparison-export/` for deploying the DDP comparison blog post. **cue = \"never\"**.",

    "targets_catalog", "Source presence and outputs",
    "Auto-generates `data/targets-catalog.md` with hand-maintained descriptions and current dimensions."
  )
}

# ── Section ordering ─────────────────────────────────────────────────────────

catalog_section_order <- function() {
  c("Core annual stats pipeline",
    "Geocoding",
    "DMCP supplemental listings",
    "DDP daily population data",
    "DDP arrests and stints",
    "Unified DETLOC lookup",
    "Hold facility and ERO integration",
    "Marshall Project locations",
    "Vera Institute facility metadata",
    "Wikipedia harmonization",
    "Expanded map and directory",
    "Source presence and outputs")
}

# ── Dimension helper ─────────────────────────────────────────────────────────

target_dimensions <- function(name) {
  obj <- tryCatch(targets::tar_read_raw(name), error = function(e) NULL)
  if (is.null(obj)) return("")
  if (is.data.frame(obj)) return(paste0(nrow(obj), " \u00d7 ", ncol(obj)))
  if (is.list(obj))       return(paste0("list (", length(obj), ")"))
  if (is.character(obj))  return(paste0("char (", length(obj), ")"))
  paste0(class(obj)[1])
}

# ── Generate catalog ─────────────────────────────────────────────────────────

generate_targets_catalog <- function(path = here::here("data/targets-catalog.md")) {
  descs     <- target_descriptions()
  sections  <- catalog_section_order()
  manifest  <- targets::tar_manifest()

  # Flag targets not yet described
  undescribed <- setdiff(manifest$name, descs$target)
  if (length(undescribed) > 0) {
    # Exclude the catalog target itself
    undescribed <- setdiff(undescribed, "targets_catalog")
    if (length(undescribed) > 0) {
      message("Targets missing from catalog descriptions: ",
              paste(undescribed, collapse = ", "))
    }
  }

  # Build dimensions column
  descs$size <- vapply(descs$target, target_dimensions, character(1))

  # Enforce section ordering
  descs$section <- factor(descs$section, levels = sections)

  # YAML front matter gives the file a title so that rendering it inside the
  # quarto website project resolves the `{{< meta title >}}` in the project's
  # `pagetitle` setting instead of emitting "Unknown meta key title" warnings.
  lines <- c(
    "---",
    'title: "Pipeline Targets Catalog"',
    "---",
    "",
    "# Pipeline Targets Catalog",
    "",
    paste0("*Auto-generated on ", Sys.Date(),
           ". Descriptions are hand-maintained in `R/catalog.R`.*"),
    "",
    "All targets can be loaded with `tar_load(target_name)` or `tar_read(target_name)`.",
    "Run the pipeline with `tar_make()`. Visualize dependencies with `tar_visnetwork()`.",
    ""
  )

  for (sec in sections) {
    sec_rows <- descs[descs$section == sec, , drop = FALSE]
    if (nrow(sec_rows) == 0) next

    lines <- c(lines,
      paste0("## ", sec),
      "",
      "| Target | Size | Description |",
      "|--------|------|-------------|"
    )

    for (i in seq_len(nrow(sec_rows))) {
      row <- sec_rows[i, ]
      lines <- c(lines, paste0(
        "| `", row$target, "` | ", row$size, " | ", row$description, " |"
      ))
    }

    lines <- c(lines, "")
  }

  writeLines(lines, path)
  message("Wrote ", path)
  path
}
