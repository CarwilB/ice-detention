# Pipeline Targets Catalog

*Auto-generated on 2026-04-08. Descriptions are hand-maintained in `R/catalog.R`.*

All targets can be loaded with `tar_load(target_name)` or `tar_read(target_name)`.
Run the pipeline with `tar_make()`. Visualize dependencies with `tar_visnetwork()`.

## Core annual stats pipeline

| Target | Size | Description |
|--------|------|-------------|
| `data_file_info` | 8 × 10 | Spreadsheet URLs, sheet names, header row positions, and rightmost data columns for each FY19--FY26 XLSX file. |
| `raw_xlsx_files` | char (8) | Local paths to downloaded ICE annual stats XLSX files. **cue = "never"**. |
| `clean_names_list` | list (8) | Clean variable name vectors (one per fiscal year), derived from the 2-row merged Excel headers. |
| `facilities_raw` | list (8) | Raw tibbles imported from each XLSX file, one per fiscal year (FY19--FY26). |
| `facilities_clean` | list (8) | Cleaned tibbles with standardized facility names, city corrections, type coercion, and Guantanamo patch. |
| `facilities_aggregated` | list (8) | Aggregated tibbles with row-level ADP sums, `share_non_crim`, `share_no_threat`, and `facility_type_wiki` classification. |
| `id_registry_file` | char (1) | Tracks `data/canonical_id_registry.csv` for changes. |
| `id_registry` | 400 × 4 | Frozen registry of canonical IDs 1--398 (FY19--FY26 facilities). Append-only; new annual stats extend from 399. |
| `facility_crosswalk` | 398 × 8 | Maps every (name, city, state) variant observed across FY19--FY26 to a `canonical_id` and `canonical_name`. Built via exact + fuzzy address matching. |
| `facilities_keyed` | list (8) | FY19--FY26 aggregated data with `canonical_id`, `canonical_name`, and `detloc` joined from the crosswalk and DETLOC lookup. |
| `facilities_all_keyed` | list (16) | Merged FY10--FY26 (minus FY18). Combines `facilities_keyed` (FY19--26) with `facilities_annual_sums` (FY10--17); adds `adp` column to FY19--26. |
| `facility_presence` | 390 × 24 | One row per canonical facility with FY10--FY26 boolean presence columns and a trajectory label (`continuous`, `persistent_gaps`, `closed`, `new`, `transient`). |
| `facilities_panel` | 2667 × 55 | Long-format panel: one row per facility per year (FY10--FY26, minus FY18). All ~30 measurement variables plus canonical IDs and DETLOCs. The primary analytical dataset. |
| `panel_facilities` | 390 × 9 | One row per panel facility (IDs 1--398) with the most recent address, city, state, ZIP, DETLOC, and facility_type_wiki. Input for geocoding and wiki matching. |
| `facility_roster` | 962 × 12 | Full roster: one row per canonical facility (~962) across all ID ranges with best-available address, type, DETLOC, and geocoding. |

## Geocoding

| Target | Size | Description |
|--------|------|-------------|
| `facilities_geocoded` | 348 × 7 | Google Maps API geocoded coordinates for FY19--FY26 canonical facilities (IDs 1--398). **cue = "never"**. |
| `facilities_geocoded_full` | 401 × 9 | Extends geocoding to DMCP-only facilities (IDs 1001+) using faclist15/faclist17 addresses. **cue = "never"**. |
| `facilities_geocoded_all` | 962 × 17 | Unified geocoded table merging Google Maps, ERO, Marshall Project, and Vera coordinates with a `geocode_source` column. |

## DMCP supplemental listings

| Target | Size | Description |
|--------|------|-------------|
| `faclist15_file` | char (1) | Path to the 2015 DMCP XLSX. **cue = "never"**. |
| `faclist17_file` | char (1) | Path to the 2017 DMCP PDF. **cue = "never"**. |
| `faclist15_raw` | 209 × 38 | Raw import of the 2015 DMCP facility listing XLSX. |
| `faclist17_raw` | 201 × 40 | Raw import of the 2017 DMCP facility listing PDF (via tabulapdf). |
| `faclist15` | 209 × 39 | Cleaned 2015 DMCP roster with project-schema column names, ZIP zero-padding, and city corrections. |
| `faclist17` | 201 × 41 | Cleaned 2017 DMCP roster with digit-bleed repair, column renames, and city corrections. |
| `dmcp_canonical_map` | 230 × 7 | Maps every DMCP DETLOC to a canonical_id via 3-pass matching (exact, manual, new IDs from 1001+). |
| `faclist15_keyed` | 209 × 42 | faclist15 with `canonical_id`, `canonical_name`, and `match_type` prepended. |
| `faclist17_keyed` | 201 × 44 | faclist17 with `canonical_id`, `canonical_name`, and `match_type` prepended. |
| `facilities_annual_sums` | list (8) | Per-fiscal-year tables (FY10--FY17) with one row per facility with non-zero ADP. Built from faclist15/faclist17 data. |

## DDP daily population data

| Target | Size | Description |
|--------|------|-------------|
| `ddp_file` | char (1) | Tracks the DDP feather file for changes. |
| `ddp_raw` | 661928 × 12 | Raw daily detention population data from the Deportation Data Project (Sep 2023--Oct 2025). One row per facility per day. |
| `ddp_codes` | 853 × 3 | Distinct cleaned facility codes extracted from `ddp_raw`. |
| `ddp_facility_canonical` | 382 × 12 | Assigns canonical IDs to 376 unmapped DDP facility codes: 150 non-medical (IDs 1054--1203) and 226 medical (IDs 3001--3226). Uses Vera Institute metadata for addresses and types. |
| `ddp_fy25_summary` | 853 × 15 | DDP daily population summarized to one row per facility for FY25 (Oct 2024--Sep 2025). ADP by sex/criminality/age, peak population, and derived shares. |
| `ddp_fy25_summary_file` | char (1) | Exports `ddp_fy25_summary` to `data/ddp-fy25-summary.csv`. format = "file". |
| `ddp_canonical_map` | 136 × 5 | Maps DDP DETLOCs to canonical facilities not already in DMCP data. Three-tier matching: fuzzy OSA, county name, confirmed keyword. |

## Unified DETLOC lookup

| Target | Size | Description |
|--------|------|-------------|
| `detloc_lookup` | 561 × 3 | Deduplicated 1:1 mapping of DETLOC to `canonical_id`. Each DETLOC and each canonical_id appears at most once. Source priority: DDP > DMCP > hold/ERO > Vera. |
| `detloc_lookup_full` | 572 × 4 | Multi-row reference preserving all DETLOC variants from all sources, including `ddp_role` (sole/primary/component). Use when matching all known codes for a facility. |

## Hold facility and ERO integration

| Target | Size | Description |
|--------|------|-------------|
| `ero_canonical_file` | char (1) | Tracks `data/ero-field-offices-canonical.csv`. |
| `ero_geocoded_file` | char (1) | Tracks `data/ero-field-offices-geocoded.csv`. |
| `ero_canonical` | 25 × 11 | 25 ERO field offices with canonical IDs (2001--2025), DETLOCs, and addresses. |
| `hold_canonical_data` | list (3) | Hold facility integration results: `hold_canonical` (148 hold facilities, IDs 2026--2173), `ero_hold_map` (23 ERO DETLOC mappings), and summary statistics. |

## Marshall Project locations

| Target | Size | Description |
|--------|------|-------------|
| `marshall_locations_file` | char (1) | Path to downloaded CSV. **cue = "never"**. |
| `marshall_locations_raw` | 1479 × 12 | Raw import of Marshall Project facility locations (CY 1978--Nov 2017). |
| `marshall_locations` | 1479 × 12 | Cleaned Marshall Project data with DETLOCs, addresses, AOR, first/last use dates, and geocoded lat/lon. |

## Vera Institute facility metadata

| Target | Size | Description |
|--------|------|-------------|
| `vera_facilities_file` | char (1) | Tracks `data/vera-institute/facilities.csv`. |
| `vera_facilities_raw` | 1464 × 12 | Raw import of Vera Institute facility metadata. |
| `vera_facilities` | 1482 × 14 | Cleaned Vera facility data with geocoded locations, addresses, county, AOR, and type classifications (`type_grouped`, `type_detailed`). |

## Wikipedia harmonization

| Target | Size | Description |
|--------|------|-------------|
| `wiki_detention_table` | 395 × 13 | Scraped pinned revision of the Wikipedia "List of immigrant detention sites" wikitable. Broad historical table. **cue = "never"**. |
| `wiki_detention_table_current` | 225 × 12 | Current live revision of the Wikipedia table. **cue = "never"**; update oldid in `_targets.R` after article edits. |
| `wiki_match_table` | 21 × 5 | City/state alias matches between ICE FY26 facility names and Wikipedia table names. |
| `facilities_fy26_wiki_search` | 225 × 41 | Wikipedia API search results for each FY26 facility name. **cue = "never"**. |
| `contractors_patch_file` | char (1) | Tracks `data/contractors-patch-fy26.csv` for changes. |
| `facilities_fy26_wiki` | 225 × 40 | FY26 facilities with `wiki_match`, `wiki_slug`, and `management` columns. Applies slug overrides, contractors patch, fl17 management backfill, and standardization. |
| `canonical_wiki_match` | 59 × 5 | All canonical facilities matched to Wikipedia articles via 4-pass matching (direct name, city/state alias, manual, external API). |
| `fy26_wikitable` | char (1) | MediaWiki table markup for active facilities in the Wikipedia list article. |
| `closed_wikitable` | char (1) | MediaWiki table markup for closed facilities in the Wikipedia list article. |

## Source presence and outputs

| Target | Size | Description |
|--------|------|-------------|
| `source_presence` | 962 × 13 | One row per canonical facility (all ID ranges) with boolean flags for each data source (ICE stats, DMCP, DDP, Marshall, Vera, geocoded, etc.). |
| `saved_files` | char (10) | Exported RDS + CSV files written to `data/` (crosswalk, presence, panel, source_presence). |
| `facility_summary_report` | char (3) | Rendered `facility-summary.qmd` Quarto report. Re-renders when upstream targets change. |
| `geocoding_divergence_report` | char (3) | Rendered `geocoding-divergence.qmd`; maps and tables of Google vs. source coordinate divergences. |
| `ddp_comparison_report` | char (3) | Rendered `ddp-comparison.qmd` locally; review before deploying to quarto website. |
| `ddp_comparison_export` | char (11) | Exports 11 RDS files to `data/ddp-comparison-export/` for deploying the DDP comparison blog post. **cue = "never"**. |
| `targets_catalog` | char (1) | Auto-generates `data/targets-catalog.md` with hand-maintained descriptions and current dimensions. |

