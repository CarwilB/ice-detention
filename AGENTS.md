# ice-detention project memory

## Related projects

The **wiki-graph** project at `~/Dropbox (Personal)/R/wiki-graph/` is the original source for `import-ice-detention.qmd`, from which this pipeline was extracted and refactored. Agents should feel free to read files in that folder for reference (e.g., original Qmd code, `AGENTS.md`, conversation plans).

## Project overview

`targets`-based R pipeline for importing, cleaning, harmonizing, and analyzing U.S. ICE detention facility data across multiple government and independent sources. The pipeline produces two tiers of output:

1.  **ICE annual statistics panel (\~390 facilities, FY10–FY26):** Facility-level average daily population breakdowns from ICE's published annual detention statistics (FY19–FY26 XLSX spreadsheets) and DMCP authorization listings (FY10–FY17 summaries). FY18 data is unavailable.

2.  **Full facility roster (\~960 facilities):** Integrates Deportation Data Project (DDP) daily population data (Sep 2023–Oct 2025), which covers a much broader set of facilities — including county jails, hold rooms, staging facilities, ERO field offices, and medical facilities not reported in ICE annual statistics. Location data from the Vera Institute of Justice and The Marshall Project supplements the roster with addresses and geocoded coordinates.

New facilities are added to the roster as detention population data becomes available, with location and metadata drawn from prior researchers (Vera, Marshall) where possible. Extracted and refactored from `import-ice-detention.qmd` in the `wiki-graph` project.

## File system conventions

-   Project root: `~/Dropbox (Personal)/R/ice-detention/`
-   Raw downloaded files organized by source in `data/` subdirectories:
    -   `data/ice/` — ICE annual detention stats XLSX files, DMCP facility listing XLSX/PDF, and other ICE-sourced files
    -   `data/ddp/` — Deportation Data Project daily population feather file and ICE office data
    -   `data/marshall/` — The Marshall Project facility locations CSV
    -   `data/dhs-websites/` — Saved DHS/DOJ web pages for reference
    -   `data/citations/`, `data/footnotes/`, `data/wikitext/` — Reference materials
    -   `data/vera-institute/` — Vera Institute facility data
-   Processed/derived outputs (RDS, CSV, YML sidecars, datapackage.json) remain in `data/` root
-   All pipeline functions in `R/` (auto-sourced by `tar_source()`)
-   Use `here::here()` for paths in scripts outside `_targets.R`

## Data sources

All raw ICE spreadsheets live in `data/ice/`:

| File                                        | Fiscal Year |
|---------------------------------------------|-------------|
| `data/ice/FY19-detentionstats.xlsx`         | FY 2019     |
| `data/ice/FY20-detentionstats.xlsx`         | FY 2020     |
| `data/ice/FY21-detentionstats.xlsx`         | FY 2021     |
| `data/ice/FY22-detentionStats.xlsx`         | FY 2022     |
| `data/ice/FY23_detentionStats.xlsx`         | FY 2023     |
| `data/ice/FY24_detentionStats.xlsx`         | FY 2024     |
| `data/ice/FY25_detentionStats09242025.xlsx` | FY 2025     |
| `data/ice/FY26_detentionStats02022026.xlsx` | FY 2026     |

Source URL pattern: `https://www.ice.gov/doclib/detention/FY{nn}-detentionstats.xlsx`

Each file has a "Facilities FY{nn}" sheet with a 2-row merged header. Header row positions and rightmost data column vary by year — all encoded in `build_data_file_info()`.

### The Marshall Project facility locations (1978–2017)

Source: [github.com/themarshallproject/dhs_immigration_detention](https://github.com/themarshallproject/dhs_immigration_detention) — originally obtained via FOIA by the National Immigrant Justice Center.

1,479 facilities with DETLOCs, addresses, AOR assignments, first/last use dates, and geocoded lat/lon. Covers CY 1978–Nov 2017. Raw data in `data/marshall/themarshallproject_locations.csv`. Import script: `themarshallproject-locations.R`; targets: `marshall_locations_file` → `marshall_locations_raw` → `marshall_locations`. Key uses: (1) DETLOC lookup for facilities not in DMCP or DDP sources (e.g., IEPHOLD for El Paso ERO Field Office); (2) addresses and geocoding for hold facilities via `build_hold_canonical()`.

## Derived data outputs (in `data/`)

| File | Description |
|----|----|
| `facility_crosswalk.rds/.csv` | Maps every (name, city, state) variant to `canonical_id` / `canonical_name` |
| `facility_presence.rds/.csv` | One row per canonical facility; FY19–FY26 booleans + trajectory classification |
| `facilities_panel.rds/.csv` | Long panel: one row per facility per year, all \~30 measurement variables |
| `canonical_id_registry.csv` | **Frozen** registry of canonical IDs 1–398 (FY19–FY26 facilities). Append-only. New annual stats extend from 399; DMCP-sourced new facilities start at 1001. |
| `facilities_fy26_wiki_matches.rds` | FY26 rows with Wikipedia slug and management columns added |
| `contractors-patch-fy26.csv` | Manual management company corrections for 98 FY26 facilities |
| `ice-detention-data-dictionary-FY26.md/.csv` | Variable definitions and acronym guide |
| `ero-field-offices-canonical.csv` | 25 ERO field offices with canonical IDs 2001–2025, DETLOCs, geocoding |
| `ero-field-offices-geocoded.csv` | 25 ERO field offices with geocoded coordinates |
| `hold-facilities-canonical.csv` | \~161 hold facilities with canonical IDs 2026–2186; \~125 with Marshall Project addresses/geocoding, \~36 DDP-only stubs. Count varies after pipeline rerun with Vera Hold/Staging expansion. |
| `facility_roster.rds/.csv` | Full roster: one row per canonical facility (~962) with address, type, DETLOC, `type_detailed_corrected`, and `type_grouped_corrected` (no geocoding; see `facilities_geocoded_all`) |
| `source_presence.rds/.csv` | One row per canonical facility with boolean flags for each data source (ICE stats, DMCP, DDP, Marshall, Vera, geocoded) |
| `facilities-geocoded-all.csv` | Unified geocoded coordinates from Google Maps API, Vera, and Marshall Project, with divergence flags |
| `ddp-fy25-summary.csv` | DDP daily population summarized per facility for FY25 (853 facility codes × 15 columns) |
| `ddp-comparison-export/*.rds` | 11 pre-computed RDS files for the DDP comparison blog post |
| `targets-catalog.md` | Auto-generated pipeline documentation with target descriptions and dimensions |

## `_targets.R` pipeline targets

### Core annual stats pipeline

| Target | Function | Description |
|----|----|----|
| `data_file_info` | `build_data_file_info()` | Tibble of file paths, sheet names, header row positions |
| `raw_xlsx_files` | `download_ice_spreadsheets()` | Downloads missing files (cue = "never") |
| `clean_names_list` | `build_clean_names()` | Named list of variable name vectors, one per year |
| `facilities_raw` | `import_all_years()` | Named list of raw tibbles, one per year |
| `facilities_clean` | `clean_all_years()` | Name/city standardization, type coercion, Guantanamo patch |
| `facilities_aggregated` | `aggregate_all_years()` | Row-level ADP sums, `share_non_crim`, `share_no_threat`, `facility_type_wiki` |
| `id_registry_file` | — | Tracks `data/canonical_id_registry.csv` (format = "file") |
| `id_registry` | `readr::read_csv()` | Reads canonical ID registry as tibble |
| `facility_crosswalk` | `build_facility_crosswalk()` | Exact + fuzzy address matching → canonical IDs |
| `facilities_keyed` | `attach_canonical_ids()` | FY19–26 panel data with `canonical_id`, `canonical_name`, and `detloc` joined |
| `facilities_all_keyed` | `merge_keyed_lists()` | Merges FY19–26 keyed data with FY10–17 annual sums; adds `adp` column to FY19–26 tables |
| `facility_presence` | `build_facility_presence()` | Per-facility year presence + trajectory label (FY10–FY26, minus FY18) |
| `facilities_panel` | `build_panel()` | Long format panel dataset (FY10–FY26, minus FY18) |
| `panel_facilities` | `build_panel_facilities()` | One row per panel facility (IDs 1–398) with most recent address columns |
| `facility_roster` | `build_facility_roster()` | Full roster: one row per canonical facility (~962) with address, type, DETLOC |
| `source_presence` | `build_source_presence()` | One row per canonical facility (all ID ranges) with boolean flags for each data source |
| `facilities_google_geocoded` | `geocode_roster()` | Google Maps API geocoding for all roster facilities (cue = "never") |
| `facilities_geocoded_all` | `build_geocoded_all()` | Merges Google + source coords (Marshall, Vera), flags divergences > 1 km and address quality |
| `ddp_comparison_report` | `tar_quarto()` | Renders `ddp-comparison.qmd` locally for review |
| `ddp_comparison_export` | `export_ddp_comparison_data()` | Exports 11 RDS files to `data/ddp-comparison-export/` for deployment (cue = "never") |
| `saved_files` | `save_outputs()` | Writes RDS + CSV to `data/`; format = "file" |
| `targets_catalog` | `generate_targets_catalog()` | Auto-generates `data/targets-catalog.md` with descriptions and dimensions |

### DMCP supplemental listings

| Target | Function | Description |
|----|----|----|
| `faclist15_file` | `download_faclist15()` | Downloads 2015 XLSX (cue = "never") |
| `faclist17_file` | `download_faclist17()` | Downloads 2017 PDF (cue = "never") |
| `faclist15_raw` | `import_faclist15()` | Raw import of 2015 XLSX |
| `faclist17_raw` | `import_faclist17()` | Raw import of 2017 PDF via tabulapdf |
| `faclist15` | `rename_dmcp_columns() \|> clean_dmcp_data()` | Cleaned 2015 roster |
| `faclist17` | `rename_dmcp_columns() \|> clean_dmcp_data()` | Cleaned 2017 roster |
| `dmcp_canonical_map` | `build_dmcp_canonical_map()` | Maps 230 DMCP detlocs to canonical IDs (3-pass: exact/manual/new) |
| `faclist15_keyed` | `attach_dmcp_canonical_ids()` | faclist15 with canonical_id + match_type |
| `faclist17_keyed` | `attach_dmcp_canonical_ids()` | faclist17 with canonical_id + match_type |
| `facilities_annual_sums` | `build_annual_sums()` | Named list of per-FY tables (FY10–FY17); one row per facility with non-zero ADP |

### DDP daily population data

| Target | Function | Description |
|----|----|----|
| `ddp_file` | — | Tracks the feather file (format = "file") |
| `ddp_raw` | `arrow::read_feather()` | Raw import of daily population data |
| `ddp_codes` | `build_ddp_codes()` | 853 distinct cleaned facility codes |
| `ddp_facility_canonical` | `build_ddp_facility_canonical()` | 376 new DDP facilities with canonical IDs: 150 non-medical (1054–1203), 226 medical (3001–3226) |
| `ddp_fy25_summary` | `build_ddp_fy_summary()` | DDP daily population summarized per facility for FY25 |
| `ddp_fy25_summary_file` | — | Exports ddp_fy25_summary to `data/ddp-fy25-summary.csv` (format = "file") |
| `ddp_canonical_map` | `build_ddp_canonical_map()` | Maps DDP detlocs to canonical facilities not in DMCP (3-tier: fuzzy/county/keyword) |

### Unified DETLOC lookup

| Target | Function | Description |
|----|----|----|
| `detloc_lookup` | `build_detloc_lookup()` | 1:1 detloc → canonical_id; DDP \> DMCP \> hold/ERO |
| `detloc_lookup_full` | `build_detloc_lookup_full()` | Multi-row reference preserving all source variants |

### Hold facility integration

| Target | Function | Description |
|----|----|----|
| `ero_canonical_file` | — | Tracks `data/ero-field-offices-canonical.csv` (format = "file") |
| `ero_canonical` | `readr::read_csv()` | 25 ERO field offices with canonical IDs, DETLOCs |
| `hold_canonical_data` | `build_hold_canonical()` | Classifies DDP hold codes, cross-refs Marshall for addresses, assigns IDs 2026+; also maps 23 ERO DETLOCs to IDs 2001–2025 |

### Vera Institute facility metadata

Targets: `vera_facilities_file` (format = "file") → `vera_facilities_raw` (`import_vera_facilities()`) → `vera_facilities` (`clean_vera_facilities()`). 1,464 facility codes with geocoded locations, addresses, county, AOR, and type classifications.

### Wikipedia harmonization

| Target | Function | Description |
|----|----|----|
| `wiki_detention_table` | `scrape_wiki_detention_table()` | Scraped pinned Wikipedia "List of immigrant detention sites" wikitable (cue = "never") |
| `wiki_detention_table_current` | `scrape_wiki_detention_table()` | Current live version of the Wikipedia table (cue = "never") |
| `wiki_match_table` | `build_wiki_match_table()` | City/state alias matches between ICE FY26 names and Wikipedia names |
| `facilities_fy26_wiki_search` | `add_wikipedia_matches()` | Wikipedia API search results for each FY26 facility name (cue = "never") |
| `contractors_patch_file` | — | Tracks `data/contractors-patch-fy26.csv` (format = "file") |
| `facilities_fy26_wiki` | `add_wiki_columns() \|> backfill_wiki_slugs() \|> apply_wiki_slug_overrides() \|> apply_contractors_patch() \|> apply_fl17_management() \|> standardize_management()` | FY26 facilities with `wiki_match`, `wiki_slug`, and `management` columns |
| `canonical_wiki_match` | `build_canonical_wiki_match()` | All canonical facilities matched to Wikipedia articles (4-pass) |
| `fy26_wikitable` | `generate_fy26_wikitable()` | MediaWiki table markup for the Wikipedia list article |

## R/ function files

| File | Key functions |
|----|----|
| `metadata.R` | `build_data_file_info()` |
| `download.R` | `download_ice_spreadsheets()` |
| `import.R` | `header_rows()`, `clean_variable_names_from_header()`, `build_clean_names()`, `read_facilities_data()`, `import_all_years()` |
| `clean.R` | `clean_facility_names()`, `fix_city_names()`, `clean_facilities_data()`, `clean_all_years()`, `repair_fl17_date_bleed()` |
| `aggregate.R` | `classify_vera_category()`, `classify_facility_type()`, `classify_facility_type_combined()`, `.classify_detailed()`, `aggregate_facilities_data()`, `aggregate_all_years()` |
| `crosswalk.R` | `build_facility_crosswalk()`, `attach_canonical_ids()`, `merge_keyed_lists()`, `build_facility_presence()`, `build_panel()`, `build_panel_facilities()`, `build_facility_roster()`, `save_outputs()` |
| `integrate.R` | `build_dmcp_canonical_map()`, `attach_dmcp_canonical_ids()`, `build_annual_sums()`, `build_detloc_lookup()`, `build_detloc_lookup_full()` |
| `ddp.R` | `build_ddp_codes()`, `build_ddp_canonical_map()`, `ddp_manual_strong_matches()`, `ddp_facility_summary()`, `build_ddp_fy_summary()`, `build_ddp_facility_canonical()`, `ddp_average_population()` (deprecated) |
| `geocode.R` | `geocode_roster()`, `build_geocoded_all()`, `.haversine_km()` |
| `wiki-match.R` | `scrape_wiki_detention_table()`, `build_wiki_match_table()`, `add_wiki_columns()`, `backfill_wiki_slugs()`, `apply_wiki_slug_overrides()`, `apply_contractors_patch()`, `apply_fl17_management()`, `standardize_management()`, `management_lookup()`, `check_wiki_articles()`, `build_canonical_wiki_match()`, plus exclusion/override helpers `wiki_does_not_match()`, `canonical_wiki_does_not_match()`, `wiki_slug_overrides()`, `canonical_wiki_manual_matches()`, `canonical_wiki_external_matches()` |
| `wikipedia.R` | `generate_infobox()`, `generate_population_wikitable()`, `dedup_refs()`, `build_wiki_list_table()`, `build_closed_wiki_list_table()`, `generate_wikitable()`, `generate_fy26_wikitable()`, `generate_closed_wikitable()` — wikitext generation for individual facility articles and the Wikipedia list article |
| `add-wikipedia-matches.R` | `add_wikipedia_matches(df, name_col, lang="en")` — generic Wikipedia API search utility, rate-limited |
| `vera-institute.R` | `import_vera_facilities()`, `clean_vera_facilities()`, `vera_type_overrides()`, `vera_detloc_matches()` |
| `themarshallproject-locations.R` | `download_marshall_locations()`, `import_marshall_locations()`, `clean_marshall_locations()`, `build_hold_canonical()`, `hold_stub_address_patches()` |
| `str-equivalent.R` | `str_equivalent()`, `normalize_join_key()` — custom string comparison functions that test equivalence ignoring case, accents, and whitespace |
| `catalog.R` | `target_descriptions()`, `generate_targets_catalog()` — auto-generates `data/targets-catalog.md` with hand-maintained descriptions and current dimensions |
| `gh-copy-assets.R` | JS copy-to-clipboard helper for HTML output |

## Key variables

All column names are snake_case derived from the 2-row Excel headers.

| Variable | Description |
|----|----|
| `facility_name`, `facility_city`, `facility_state`, `facility_zip`, `facility_address` | Facility identity |
| `facility_type_detailed` | Raw ICE type code (IGSA, DIGSA, SPC, BOP, CDF, etc.) |
| `facility_type_wiki` | Derived readable type for Wikipedia use |
| `facility_average_length_of_stay_alos` | Average length of stay |
| `adp_detainee_classification_level_{a-d}` | ADP by security level |
| `adp_criminality_male_crim/non_crim`, `adp_criminality_female_crim/non_crim` | ADP by criminality × gender |
| `adp_ice_threat_level_{1-3}`, `adp_no_ice_threat_level` | ADP by ICE threat level |
| `adp_mandatory` | Mandatory detention ADP |
| `inspections_guaranteed_minimum` | Contracted bed capacity (integer) |
| `inspections_last_inspection_type`, `..._end_date`, `..._standard`, `..._final_rating` | Inspection info |
| `adp` | Total average daily population; from DMCP single ADP (FY10–17) or `sum_classification_levels` (FY19–26) |
| `share_non_crim`, `share_no_threat` | Derived: non-criminal / no-threat shares (FY19–26 only) |
| `canonical_id`, `canonical_name` | Post-crosswalk facility identifiers |
| `detloc` | ICE facility code (e.g. STCDFTX); joined from `detloc_lookup` |

## Facility type classification

Four type variables are used across the pipeline. See `data/facility-type-variables.md` for the full mapping table.

-   **`facility_type_detailed`**: Raw ICE facility type code from annual stats and DMCP listings (e.g., IGSA, CDF, SPC, BOP). For hold facilities, carries internal project codes (hold_room, staging, sub_office, etc.).
-   **`type_detailed_corrected`**: Vera's `type_detailed` with 42 project overrides applied via `vera_type_overrides()`. Uses ICE codes (uppercase: BOP, SPC, CDF, STATE) when known, or internal project codes (lowercase: county_jail, ero_hold, sub_office) when the ICE classification is unknown. For non-overridden facilities, equals Vera's original `type_detailed`.
-   **`type_grouped_corrected`**: Vera's `type_grouped` (8-category vocabulary) with the same 42 overrides applied. For non-overridden facilities, equals Vera's original `type_grouped`.
-   **`facility_type_wiki`**: Human-readable classification derived by `classify_facility_type_combined()` in `R/aggregate.R` through a 4-tier priority system: (1) `facility_type_detailed`, (2) name-based overrides, (3) `type_detailed_corrected`, (4) `type_grouped_corrected`. Used for Wikipedia and reporting.

### ICE annual stats type mapping (`facility_type_detailed` → `facility_type_wiki`)

| `facility_type_detailed` | `facility_type_wiki`                    |
|--------------------------|-----------------------------------------|
| IGSA                     | Jail                                    |
| USMS IGA                 | Jail                                    |
| DIGSA                    | Dedicated Migrant Detention Center      |
| STATE                    | State Migrant Detention Center          |
| BOP                      | Federal Prison                          |
| FAMILY / FAMILY STAGING  | Family Detention Center                 |
| CDF / USMS CDF           | Private Migrant Detention Center        |
| SPC                      | ICE Migrant Detention Center            |
| STAGING                  | ICE Short-Term Migrant Detention Center |
| DOD                      | Military Detention Center               |
| JUVENILE                 | Juvenile Detention Center               |

### Additional facility types (from DDP/Vera, not in ICE annual stats)

| Type | Source | Description |
|----|----|----|
| Hold/Staging | DDP daily data, Vera | Hold rooms at ERO field offices and short-term staging facilities |
| Medical | DDP daily data, Vera | Hospitals, clinics, and medical transport |
| Hotel | Vera | Hotels used for temporary ICE detention (none currently in DDP data) |
| Other/Unknown | Vera | Unclassified facilities |

Facilities can change `facility_type_detailed` across fiscal years. Of 346 panel facilities, 55 (16%) have more than one value across the FY19–FY26 period.

## Crosswalk logic

**Pass 1:** Exact match on `(facility_name, facility_city, facility_state)` → provisional `facility_id`.

**Pass 2:** Within the same ZIP code, compute OSA string similarity on `facility_address`. Pairs with similarity ≥ 0.80 are merged via union-find, except for pairs in `do_not_merge_pairs()`.

**Canonical name:** Most recent year's name for each cluster (ties broken by `year_order`).

**Manual overrides:** `canonical_name_overrides_table()` in `crosswalk.R` — 7 entries correcting ambiguous state suffixes, punctuation, etc.

**Trajectory labels** (in `facility_presence`): - `continuous` — present every year FY10–FY26 (minus FY18 gap) - `persistent_gaps` — present in FY10 and FY26 but with gaps - `closed` — present in FY10, absent from FY26 - `new` — absent from FY10, present in FY26 - `transient` — absent from both FY10 and FY26

`year_order` covers FY10–FY17 and FY19–FY26 (16 years; FY18 omitted — no data source). The FY18 gap means a facility present in FY17 and FY19 is classified as `persistent_gaps` rather than `continuous`.

## Canonical ID space

| Range | Purpose |
|----|----|
| 1–398 | FY19–FY26 facilities — **frozen** in `data/canonical_id_registry.csv` (347 distinct after merges) |
| 399–1000 | Reserved for future annual stats (FY27+), continuing sequentially |
| 1001–1053 | Facilities sourced from faclist15/faclist17 only (not in FY19–FY26 panel) |
| 1054–1203 | DDP non-hold, non-medical facilities (150: 109 Non-Dedicated jails, 28 Federal, 9 Dedicated, 3 Family/Youth, 1 Other/Unknown) |
| 1204–2000 | Reserved for future supplemental detention facility sources |
| 2001–2025 | ERO field offices (25 offices, from `ero-field-offices.qmd`) |
| 2026–2186 | Hold facilities (161: Marshall Project addresses + DDP hold/staging stubs) |
| 2187–3000 | Reserved for future hold/staging expansion |
| 3001–3226 | Medical facilities from DDP/Vera (226 hospitals, clinics, medical transport) |
| 3227–4000 | Reserved for future medical facilities |
| 4001+ | Reserved for hotels (none currently in DDP data) |

`build_facility_crosswalk()` accepts `id_registry` as a second argument and looks up existing IDs from the registry by `(canonical_name, canonical_city, canonical_state)`. New facilities (no registry match) get IDs from `max(id_registry$canonical_id) + 1` with a message to append them. Two new targets — `id_registry_file` (format = "file", tracks CSV changes) and `id_registry` (reads it as a tibble) — are threaded into `facility_crosswalk` in `_targets.R`.

`build_dmcp_canonical_map()` is idempotent: it looks up existing DMCP-range IDs by (name, city, state) before assigning new ones, and deduplicates the registry on write.

## DMCP integration status

`dmcp-listings.qmd` documents the two DMCP data sources, dataset summaries, overlap analysis, and visual confirmation tables.

**DMCP → canonical matching (Section 4):** 230 combined DMCP facilities (201 from faclist17 + 29 faclist15-only) matched against the FY19–FY26 canonical list: - **164 exact** — name+city+state match against crosswalk variants - **13 manual** — confirmed by address (6 original renames/truncations + 7 retitled facilities that were initially assigned IDs 1001+) - **53 new** — IDs 1001–1053; 27 of these had zero ADP in their most recent two fiscal years

Two facilities (JAMESGA, OTROPNM) share a road/ZIP with canonical facilities but have distinct street addresses (separate buildings in adjacent complexes); left as new IDs. STCDFTX was originally in this group but was confirmed as canonical 343 (South Texas ICE Processing Center).

**Pipeline targets (in `R/integrate.R`):** - `dmcp_canonical_map` — one row per detloc; columns: `detloc`, `source`, `canonical_id`, `canonical_name`, `canonical_city`, `canonical_state`, `match_type` - `faclist15_keyed`, `faclist17_keyed` — faclists with `canonical_id`, `canonical_name`, `match_type` prepended

**Data quality fixes applied to `clean_dmcp_data()` / `fix_city_names()` / `.dmcp_pdf_col_breaks`:** - ZIP zero-padding (both sources) - `"Kearney"` → `"Kearny"` (NJ city, faclist15 XLSX error) - `"Colorado Spring"` → `"Colorado Springs"` (truncated value in faclist15 XLSX) - `"Cottonwood Fall\b"` → `"Cottonwood Falls"` (regex was over-matching "Falls" → "Fallss") - State bleed fix: strip non-alpha prefix in `facility_state` (PDF county cell could overflow) - Column boundary corrections in `.dmcp_pdf_col_breaks`: zip/type/type_detailed/male_female boundaries shifted right by 4–14 points to match actual PDF glyph positions (ZIP was being truncated to 3 digits)

**fl17 digit-bleed repair (`repair_fl17_date_bleed()` in `clean.R`):**

The 2017 PDF column boundaries are slightly too narrow in two zones, causing the last digit of a date field to bleed into the adjacent column to its right. The function `repair_fl17_date_bleed()` runs *before* `clean_dmcp_data()` in the `faclist17` target and uses a shared `fix_bleed_pair(left, right)` helper to reassemble the truncated values.

| Zone | Left column (truncated) | Right column (receives bleed digit) |
|----|----|----|
| 1 | `contract_initiation_date` | `contract_expiration_date` |
| 1 | `contract_expiration_date` | `per_diem_rate_detailed` |
| 2 | `inspections_last_inspection_date` | `cy16_rating` |

Example before repair: init=`"6/30/200"`, exp=`"6 7/31/201"`, rate=`"7 1600 (GM)…"` Example after repair: init=`2006-06-30`, exp=`2017-07-31`, rate=`"1600 (GM)…"`

After reassembly, all three date columns (`contract_initiation_date`, `contract_expiration_date`, `inspections_last_inspection_date`) are converted to `Date` type. The repair is safe to call on fl15 data (returns unchanged if columns are absent or already well-formed). Only fl17 is affected; fl15 comes from an XLSX and does not have this artifact.

Remaining truncation: `cy16_rating` has 9 values reading `"Special Review - Pre-Oc"` (truncated from "Pre-Occupancy"); this is a text-width truncation in the PDF, not a bleed artifact.

## DDP daily population data integration

**Data source:** Deportation Data Project daily detainee counts (Sep 2023–Oct 2025), 853 distinct facility codes, imported as a feather file.

**Pipeline targets:** See the DDP and DETLOC sections of the pipeline targets table above. Core functions are in `R/ddp.R`; manual strong matches are in `ddp_manual_strong_matches()`.

**DDP → canonical matching:** Of the 178 canonical FY19–FY26 facilities NOT in DMCP data, `build_ddp_canonical_map()` uses three tiers: - **114 exact** (92 fuzzy OSA ≥ 0.85 + 22 manually verified) — high-confidence matches - **19 partial: county name** — word before "county" required in DDP facility name - **6 partial: keyword** — confirmed non-county keyword matches (visually verified; 25 low-confidence rejected) - **39 fully unmatched** — no DDP code found; mostly jails (26), hotels/staging (7), and other specialized facilities

## Unified DETLOC (facility code) coverage

Both DMCP and DDP use the same ICE DETLOC system. The unified `detloc_lookup` target combines all sources (priority: DDP \> DMCP \> hold/ERO).

| Metric                                         | Count      |
|------------------------------------------------|------------|
| DMCP detlocs (faclist15 + faclist17)           | 226        |
| DDP detlocs (non-DMCP canonical matches)       | 135        |
| ERO field office hold DETLOCs                  | 23         |
| Marshall-sourced hold facility DETLOCs         | 148        |
| Total unique detloc → canonical_id mappings    | 532        |
| Canonical facilities (IDs 1–398) with a DETLOC | 308 of 347 |
| Canonical facilities with no DETLOC            | 39         |

The `detloc` column is propagated through `facilities_keyed` → `facilities_panel` → `panel_facilities` / `facility_roster` → saved CSV/RDS outputs.

### Hold facility integration

DDP data contains hold-type facility codes identified by two methods: (1) DETLOC contains HOLD, STAGING, or CPC; (2) Vera `type_grouped_corrected == "Hold/Staging"`. The second method catches short-code staging facilities (STK, AGC, VRK, RGS, KRHUBFL) that don't follow the standard DETLOC naming pattern. These are cross-referenced against Marshall Project locations for addresses and geocoding.

Function: `build_hold_canonical()` in `themarshallproject-locations.R`. Accepts optional `vera_facilities` parameter (passed from `_targets.R`). Output saved as `data/hold-facilities-canonical.csv`.

### Vera Institute facility metadata

Source: [github.com/vera-institute/ice-detention-trends](https://github.com/vera-institute/ice-detention-trends). 1,464 facility codes with geocoded locations, addresses, county, AOR, and facility type classifications (`type_grouped`, `type_detailed`). Raw data in `data/vera-institute/facilities.csv`. Import/clean functions in `vera-institute.R`; targets: `vera_facilities_file` → `vera_facilities_raw` → `vera_facilities`.

### Vera facility type groupings (Table 2)

Source: Table 2 of the Vera Institute "ICE Detention Trends: Technical Appendix" (Smart & Lawrence, 2023). Archived at `https://web.archive.org/web/20250711155006/https://www.vera.org/ice-detention-trends/files/dashboard_appendix.pdf`. Manually transcribed as `data/vera-institute/vera-type-coding.R`. Provenance metadata in `data/vera-type-coding.yml`; schema in `data/datapackage.json`.

Maps ICE `facility_type_detailed` codes to Vera's 8-category vocabulary (Non-Dedicated, Dedicated, Federal, Hold/Staging, Family/Youth, Medical, Hotel, Other/Unknown). Implemented as `classify_vera_category()` in `R/aggregate.R`, with three project extensions for ICE codes not in Table 2: TAP-ICE → Family/Youth, FAMILY STAGING → Hotel, STATE → Dedicated. See `data/facility-type-variables.md` for the full mapping table.

**`type_detailed_corrected` and `type_grouped_corrected` columns**: `clean_vera_facilities()` joins `vera_type_overrides()` (also in `vera-institute.R`) to produce corrected versions of both `type_detailed` and `type_grouped`. All 42 overridden facilities had `type_detailed` of "Other" or "Unknown" and `type_grouped` of "Other/Unknown" in Vera's original data. The overrides correct both levels:

| Override category | `type_detailed_corrected` | `type_grouped_corrected` | Count |
|---|---|---|---|
| County jails | `county_jail` | Non-Dedicated | 32 |
| ICE dedicated facilities | `SPC`, `CDF` | Dedicated | 3 |
| State immigration facility | `STATE` | Dedicated | 1 |
| Federal prisons | `BOP` | Federal | 2 |
| Hold/staging | `ero_hold`, `sub_office` | Hold/Staging | 2 |
| Medical | `Hospital` | Medical | 1 |
| Family/youth | `Juvenile` | Family/Youth | 1 |

Uppercase `type_detailed_corrected` values are known ICE codes. Lowercase values are internal project codes used when the ICE classification is unknown (e.g., county jails could be IGSA or USMS IGA depending on the contract arrangement).

Use `type_grouped_corrected` (not `type_grouped`) and `type_detailed_corrected` (not `type_detailed`) in all analysis. The originals are preserved for reference.

## Wikipedia article matching architecture

The pipeline connects ICE detention facilities to Wikipedia articles through two parallel paths that share a unified `wiki_slug_overrides()` table:

### FY26-specific matching (→ `facilities_fy26_wiki`)

Three-layer matching against the scraped Wikipedia detention sites table, plus backfill from a current scrape and Wikipedia API search:

1.  **Direct name match** against the pinned wiki table
2.  **City/state alias** via `build_wiki_match_table()`
3.  **Wikipedia API search** via `add_wikipedia_matches()` (cached, cue = "never")
4.  **Backfill** from `wiki_detention_table_current` via `backfill_wiki_slugs()`
5.  **Override cleanup** via `apply_wiki_slug_overrides()`

Produces two columns: `wiki_match` (any Wikipedia name, 82 of 225 FY26 facilities) and `wiki_slug` (confirmed article link, 42 of 225).

### Canonical-level matching (→ `canonical_wiki_match`)

Four-pass matching of all 390 canonical facilities against linked wiki table rows only:

| Pass | Method | Count |
|----|----|----|
| 1 | Direct name match (exact + parenthetical-stripped base name) | 26 |
| 2 | City/state alias (1:1 linked pairs, excluding false positives) | 13 |
| 3 | Manual resolutions (multi-facility cities, renames, BOP, historical nicknames) | 12 |
| 4 | External matches (Wikipedia API search + category members) | 7 |
| — | **Total after overrides** | **58** |

Every match has a verified, non-redirect `wiki_slug` (overrides resolve 5 redirects and clear 1 bad redirect).

### `wiki_slug_overrides()` — unified redirect handling

Applied by both `facilities_fy26_wiki` and `build_canonical_wiki_match()`:

| From (redirect) | To (canonical article) |
|----|----|
| T. Don Hutto Family Residential Facility | T. Don Hutto Residential Center |
| Wyatt Detention Center | Donald W. Wyatt Detention Facility |
| Otay Detention Facility | Otay Mesa Detention Center |
| Douglas County Correctional | Douglas County Correctional Center |
| Willacy Detention Center | Willacy County Regional Detention Center |
| Wayne County Jail | *(cleared — redirects to county article)* |

### `check_wiki_articles()` — diagnostic utility

Batch-queries the MediaWiki API (up to 50 titles per request) to check article existence and redirect status. Not wired into the pipeline; used interactively for validation.

### Coverage (as of 2026-03-22)

| Dataset                   | Linked to Wikipedia    | Total | \%        |
|---------------------------|------------------------|-------|-----------|
| FY26 facilities           | 42 (slug) / 82 (match) | 225   | 19% / 36% |
| Canonical list            | 58                     | 390   | 15%       |
| Wiki table linked entries | 53 matched             | 102   | 52%       |

Remaining 49 unmatched wiki table entries exported to `data/unmatched-wiki-facilities.txt` (wikitext format).

### Wikitext table generation (→ `fy26_wikitable`)

`generate_fy26_wikitable()` in `R/wikipedia.R` produces a complete MediaWiki table for the Wikipedia "List of immigrant detention sites" article. The original `get_wikitable()` / `facilities_wikitable_from_merged()` from `import-ice-detention.qmd` has been refactored into:

-   `build_wiki_list_table(df, year_name, facility_presence)` — transforms FY26 data into 9-column wiki-formatted tibble. When `facility_presence` is supplied, the status column shows `"Active (FYxx – FY26)"` based on each facility's continuous backward streak from FY26 (walking backward through available year columns; the FY18 data gap is transparent since FY18 is absent from the column set). When `facility_presence` is NULL, status defaults to `"In use (FY26)"`.
-   `build_closed_wiki_list_table(facilities_panel, facility_presence, canonical_wiki_match)` — builds a matching 9-column tibble for facilities absent from the most recent year. Status reads `"Closed (Active FYxx – FYxx)"` using `first_seen`/`last_seen` from the presence matrix. Wikipedia links come from `canonical_wiki_match` (canonical-level matches) rather than FY26-specific `wiki_slug`/`wiki_match`.
-   `generate_wikitable(df, caption, class, column_names)` — general-purpose data frame → MediaWiki markup converter
-   `generate_fy26_wikitable(df, year_name, facility_presence)` — end-to-end wrapper for active facilities
-   `generate_closed_wikitable(facilities_panel, facility_presence, canonical_wiki_match)` — end-to-end wrapper for closed facilities

Facility name links use a 3-tier hierarchy: `wiki_slug` (confirmed article) → `wiki_match` (red link) → plain text. City/state values are wikilinked with two disambiguation overrides (Philipsburg, PA; Greenwood, WV).

The FY26 table has **82 facility name wikilinks** (up from \~23 in the original qmd pipeline), with 42 pointing to confirmed Wikipedia articles. The closed facilities table covers 166 facilities with 11 wikilinks from canonical-level matches.

## Quarto reports

The pipeline renders analytical reports as HTML documents. Some are wired as `tar_quarto()` targets (re-render automatically when upstream data changes); the rest are rendered manually.

| Report | Pipeline target? | Description |
|--------|-----------------|-------------|
| `facility-summary.qmd` | Yes (`facility_summary_report`) | Facility counts by ID range, source coverage, trajectory statistics |
| `geocoding-divergence.qmd` | Yes (`geocoding_divergence_report`) | Maps and tables comparing geocoded coordinates across sources |
| `ddp-comparison.qmd` | Yes (`ddp_comparison_report`) | DDP daily population vs. ICE FY25 annual statistics; unreported facility analysis |
| `missing-addresses.qmd` | No | Identifies roster facilities missing address information |
| `dmcp-listings.qmd` | No | Documentation of the 2015/2017 DMCP facility authorization data |
| `ero-field-offices.qmd` | No | ERO field offices as informal detention sites |
| `infobox-generator.qmd` | No | Wikipedia {{Infobox prison}} wikitext generator |
| `detention-list-wikitables.qmd` | No | Copyable MediaWiki table markup for Wikipedia list article |

### Spin-off blog posts

Two reports are published as posts in a separate quarto-website repository (`~/Dropbox (Personal)/R/quarto-website/posts/`):

| Post directory | Description |
|----------------|-------------|
| `ddp-comparison/` | DDP vs ICE FY25 annual statistics comparison |
| `ice-detention-map/` | Interactive Leaflet map of ~390 panel facilities |

The DDP comparison post follows a render-locally-then-deploy workflow:

1. `tar_make(ddp_comparison_report)` — renders `ddp-comparison.qmd` locally (reads pipeline targets directly via `tar_read()`).
2. Review the local HTML output.
3. `tar_make(ddp_comparison_export)` — exports 11 pre-computed RDS files to `data/ddp-comparison-export/` (cue = "never"; only runs when explicitly requested).
4. Run `copy-data.sh` in the website post directory to deploy.

The website version (`posts/ddp-comparison/index.qmd`) reads the pre-computed RDS files rather than pipeline targets directly.

### Development workflow

Each stage of development leads from experiments to standalone Quarto reports, whose data should be automatically updated by the pipeline. Even manual corrections are managed in a functional way (e.g., `wiki_slug_overrides()`, `vera_type_overrides()`, `do_not_merge_pairs()`) that allows them to be extended without editing data files directly.

## Future work: Extend canonical Wikipedia matching

- Run Wikipedia API search (`add_wikipedia_matches`) against unmatched canonical facilities (partially done; 7 external matches in `canonical_wiki_external_matches()`)
- Fetch Wikipedia category "Immigration detention centers and prisons in the United States" and match members against unmatched canonicals
- Add confirmed new matches to `canonical_wiki_external_matches()`

## R package installation guidance

This project uses **renv** for reproducibility. Agents should follow these rules when packages are relevant:

1.  **Always suggest the best R package for a job**, even if it isn't currently installed. Do not avoid recommending a package just because it may require installation.

2.  **Before suggesting installation**, check whether the package is already available in the current renv library (`find.package("pkg", quiet = TRUE)`) and also in the system R library, which on this machine is `/Library/Frameworks/R.framework/Versions/4.5-arm64/Resources/library` — this directory is **not** used by this project due to renv, but packages found there may already be compiled and installable quickly via `renv::install()`. Check with: `find.package("pkg", lib.loc = "/Library/Frameworks/R.framework/Versions/4.5-arm64/Resources/library", quiet = TRUE)`.

3.  **If the package exists outside renv** (system or user library), tell the user — they may be able to use `renv::install()` quickly without a full CRAN download, or they may want to note it's already compiled.

4.  **Always tell the user to install via renv**, not `install.packages()`, since this project uses renv. The standard command is:

    ``` r
    renv::install("pkg")
    ```

    After installing, the user should run `renv::snapshot()` to record the dependency.

5.  For packages with system-level dependencies (e.g., `pdftools` requires `poppler`, `sf` requires `GDAL/PROJ`), note the system library requirement alongside the install command.

## Dependencies

Core: `readxl`, `dplyr`, `stringr`, `tidyr`, `purrr`, `tibble`, `httr`, `stringdist`, `glue`, `targets`

For DMCP listings: `tabulapdf` (requires Java / rJava; replaces the earlier `pdftools::pdf_data()` bounding-box parser)

For DDP daily population data: `arrow` (feather file I/O)

For geocoding: `ggmap` (Google Maps API; requires API key in `.Renviron` and `register_google()`)

For Wikipedia matching/harmonization: `rvest`, `WikipediR` (optional fallback in `add_wikipedia_matches()`)

For Quarto reports and visualization: `tarchetypes` (`tar_quarto()`), `ggplot2`, `sf`, `leaflet`, `leafpop`

## Metadata convention for imported data tables

### Sources that contribute to the main annual stats pipeline

For data sources that contribute to the main annual stats pipeline (e.g. authorization lists that include summary data from multiple prior fiscal years), the project uses a three-part convention:

1.  **Pipeline targets**: No standalone import script. Each source has dedicated functions across three files, plus targets in `_targets.R`:

    -   `R/download.R` — `download_{source}()`: downloads the file if absent, returns the local path. Used as a `format = "file"`, `cue = "never"` target.
    -   `R/import.R` — `import_{source}(path)`: accepts the file path and returns a raw tibble with minimal transformation.
    -   `R/clean.R` — `rename_{source}_columns()` and `clean_{source}_data()`: harmonize column names to project schema and apply type coercion and string cleaning.
    -   `_targets.R` targets follow the naming convention `{source}_file` (download), `{source}_raw` (import), `{source}` (cleaned), grouped in a clearly commented supplemental section.

2.  **YAML sidecar** (`data/<source-name>.yml`): Structured provenance metadata including bibliographic citation, data currency dates, raw file description, parsing method, filtering decisions, and a list of pipeline targets and outputs.

3.  **Frictionless Data package descriptor** (`data/datapackage.json`): Column-level schemas for CSV outputs, following the [Frictionless Data](https://frictionlessdata.io/) `datapackage.json` spec. Includes source citation and license info. All field definitions are written out fully in each resource — do not use `$ref` cross-references, which are not part of the Frictionless spec.

#### Current instances

| Source | Targets | YAML | datapackage resources |
|----|----|----|----|
| ICE DMCP Facility Listings (2015 XLSX, 2017 PDF) | `faclist15`, `faclist17` | `data/dmcp-listings.yml` | `faclist15`, `faclist17` |
| The Marshall Project Facility Locations (1978–2017) | `marshall_locations` | `data/themarshallproject-locations.yml` | — |

------------------------------------------------------------------------

### When data sources are added

For future data sources that are supplemental to the main annual stats pipeline (e.g. manually transcribed tables, external reference files), the project uses the same three-part convention, but with a different structure for item 1:

1.  **Supplemental import script** (`<source-name>-<year>.R`): A single self-contained R script in the project root containing all import and processing functions for that source. Any file downloading must be done once manually and should not be wired to run automatically. The script is imported into the pipeline by adding a dedicated supplemental section to `_targets.R`.

2.  **YAML sidecar** (`data/<source-name>.yml`): Same as above.

3.  **Frictionless Data package descriptor** (`data/datapackage.json`): Same as above. New resources are appended to the existing `datapackage.json`.
