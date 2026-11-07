# ice-detention project memory

## Related projects

The **wiki-graph** project at `~/Dropbox/R/wiki-graph/` is the original source for `import-ice-detention.qmd`, from which this pipeline was extracted and refactored. Agents should feel free to read files in that folder for reference (e.g., original Qmd code, `AGENTS.md`, conversation plans).

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
| `data/ice/FY26_detentionStats02022026.xlsx` | FY 2026 snapshot a (Feb 2) |
| `data/ice/FY26_detentionStats_02122026.xlsx` | FY 2026 snapshot b (Feb 12) |
| `data/ice/FY26_detentionStats07202026.xlsx` | FY 2026 snapshot c (July 20) |

Source URL pattern: `https://www.ice.gov/doclib/detention/FY{nn}-detentionstats.xlsx`

Each file has a "Facilities FY{nn}" sheet with a 2-row merged header. Header row positions and rightmost data column vary by year — all encoded in `build_data_file_info()`.

### The Marshall Project facility locations (1978–2017)

Source: [github.com/themarshallproject/dhs_immigration_detention](https://github.com/themarshallproject/dhs_immigration_detention) — originally obtained via FOIA by the National Immigrant Justice Center.

1,479 facilities with DETLOCs, addresses, AOR assignments, first/last use dates, and geocoded lat/lon. Covers CY 1978–Nov 2017. Raw data in `data/marshall/themarshallproject_locations.csv`. Import script: `themarshallproject-locations.R`; targets: `marshall_locations_file` → `marshall_locations_raw` → `marshall_locations`. Key uses: (1) DETLOC lookup for facilities not in DMCP or DDP sources (e.g., IEPHOLD for El Paso ERO Field Office); (2) addresses and geocoding for hold facilities via `build_hold_canonical()`.

## Project skills

- [.posit/assistant/skills/updating-ddp-data/SKILL.md](.posit/assistant/skills/updating-ddp-data/SKILL.md) — Workflow for updating DDP (Deportation Data Project) data: release detection via the deportationdata/ice repo, versioned file pinning (`{dataset}-latest_{YYYYMMDD}.parquet`, suffix = DDP release date), recreating the discontinued facilities-daily-population parquet from stints with exact-match validation, repointing `_targets.R` targets, archiving frozen analyses, and provenance metadata. Use whenever refreshing or adding DDP data.

## Derived data outputs (in `data/`)

| File | Description |
|----|----|
| `facility_crosswalk.rds/.csv` | Maps every (name, city, state) variant to `canonical_id` / `canonical_name` |
| `facility_presence.rds/.csv` | One row per canonical facility; FY10–FY26 booleans + trajectory classification (FY26 = any of the three snapshots) |
| `facilities_panel.rds/.csv` | Long panel: one row per facility per year, all \~30 measurement variables. FY26 = July 20 snapshot only. |
| `facilities_panel_interim.rds/.csv` | Panel variant in which FY26 follows the snapshot cascade (July → Feb 12 → Feb 2); `fy26_snapshot` marks the source |
| `canonical_id_registry.csv` | **Frozen** registry of canonical identities across all ranges, with a `detloc` column pinning every DDP-assigned code (see "Registry pinning"). Append-only. |
| `facilities_fy26_wiki_matches.rds` | FY26 rows with Wikipedia slug and management columns added |
| `contractors-patch-fy26.csv` | Manual management company corrections for 98 FY26 facilities |
| `ice-detention-data-dictionary-FY26.md/.csv` | Variable definitions and acronym guide |
| `ero-field-offices-canonical.csv` | 25 ERO field offices with canonical IDs 2001–2025, DETLOCs, geocoding |
| `ero-field-offices-geocoded.csv` | 25 ERO field offices with geocoded coordinates |
| `hold-facilities-canonical.csv` | \~164 hold facilities with canonical IDs 2026–2189; \~150 with Marshall Project addresses/geocoding, \~5 DDP-only stubs, \~9 hold/CBP from the DDP parquet. Count varies after pipeline rerun with Vera Hold/Staging expansion. |
| `facility_roster.rds/.csv` | Full roster: one row per canonical facility (~1029) with address, type, DETLOC, `type_detailed_corrected`, and `type_grouped_corrected` (no geocoding; see `facilities_geocoded_all`) |
| `source_presence.rds/.csv` | One row per canonical facility with boolean flags for each data source (ICE stats, DMCP, DDP, Marshall, Vera, geocoded) |
| `facilities-geocoded-all.csv` | Unified geocoded coordinates from Google Maps API, Vera, and Marshall Project, with divergence flags. Resolved 2026-11: 344 Southern Regional Jail geocoded via `roster_address_patches()` (1200 Airport Rd, Beaver WV); 1030 Taylor County resolved to Google via TAYLOTX in `geocode_source_preference()` (Vera coordinate ~3 km west, wrong) |
| `ddp-fy25-summary.csv` | DDP daily population summarized per facility for FY25 (853 facility codes × 15 columns) |
| `ddp-comparison-export/*.rds` | 11 pre-computed RDS files for the DDP comparison blog post |
| `wiki-editor-changes.csv` | Cell-level record of other editors' changes to the Wikipedia list article since our last upload (written by the `wiki_editor_changes_file` target); check before every re-upload |
| `targets-catalog.md` | Auto-generated pipeline documentation with target descriptions and dimensions |

## `_targets.R` pipeline targets

For a complete, auto-generated list of targets with descriptions and current dimensions, see [`data/targets-catalog.md`](data/targets-catalog.md). The catalog is regenerated by the `targets_catalog` target each pipeline run. Target groups in the catalog: Core annual stats · Geocoding · DMCP supplemental listings · DDP daily population · DDP arrests and stints · Unified DETLOC lookup · Hold facility and ERO integration · Marshall Project locations · Vera Institute facility metadata · Wikipedia harmonization · Expanded map and directory · Source presence and outputs.

**Catalog coverage (as of 2026-11-06):** All targets in `_targets.R` have descriptions in `target_descriptions()` (`R/catalog.R`) — including the FY25–FY26 union chain, the Wikipedia change-tracking targets (2026-10-25), and the Zotero-harvest targets `wiki_list_extant_articles` (cue never, MediaWiki API) and `wiki_article_collection_map` (local only) added 2026-11-06. The two stale entries `facilities_geocoded` and `facilities_geocoded_full` are retained in the catalog with *RENAMED — no longer wired in* annotations pointing to `facilities_google_geocoded`, which geocodes the full roster. To add descriptions for new targets, extend `target_descriptions()` in `R/catalog.R` and run `tar_make(targets_catalog)`.

## R/ function files

| File | Key functions |
|----|----|
| `metadata.R` | `build_data_file_info()` |
| `download.R` | `download_ice_spreadsheets()` |
| `import.R` | `header_rows()`, `clean_variable_names_from_header()`, `build_clean_names()`, `read_facilities_data()`, `import_all_years()` |
| `clean.R` | `clean_facility_names()`, `fix_city_names()`, `clean_facilities_data()`, `clean_all_years()`, `repair_fl17_date_bleed()` |
| `aggregate.R` | `classify_vera_category()`, `classify_facility_type()`, `classify_facility_type_combined()`, `.classify_detailed()`, `canonical_type_overrides()`, `canonical_vera_type_overrides()`, `aggregate_facilities_data()`, `aggregate_all_years()` |
| `crosswalk.R` | `build_facility_crosswalk()`, `attach_canonical_ids()`, `merge_keyed_lists()`, `resolve_fy26_snapshots()` (3-snapshot cascade), `build_fy_range_union()` (generalized era union), `build_fy25_26_union()`, `build_fy26b()`, `build_facility_presence()`, `build_panel()`, `build_panel_facilities()`, `build_facility_roster()`, `roster_address_patches()` (canonical-ID-keyed address patches applied in `build_facility_roster()`, for DDP-revived facilities with no keyed row — e.g. 344 Southern Regional Jail), `save_outputs()` |
| `integrate.R` | `build_dmcp_canonical_map()`, `attach_dmcp_canonical_ids()`, `build_annual_sums()`, `build_detloc_lookup()`, `build_detloc_lookup_full()` |
| `ddp.R` | `build_ddp_codes()`, `build_ddp_canonical_map()`, `ddp_manual_strong_matches()`, `ddp_facility_summary()`, `build_ddp_fy_summary()`, `build_ddp_facility_canonical()`, `ddp_average_population()` (deprecated) |
| `geocode.R` | `geocode_roster()` (incremental, CSV-cached), `geocode_source_preference()` (per-DETLOC source preference for divergences), `build_geocoded_all()`, `.haversine_km()` |
| `wiki-match.R` | `scrape_wiki_detention_table()`, `build_wiki_match_table()`, `add_wiki_columns()`, `backfill_wiki_slugs()`, `apply_wiki_slug_overrides()`, `apply_contractors_patch()`, `apply_fl17_management()`, `backfill_fl17_capacity()`, `standardize_management()`, `management_lookup()`, `check_wiki_articles()` (exists/redirect/disambiguation status), `extract_wikilink_targets()`, `check_wiki_city_links()` (city-link scan for the generated wikitables), `build_canonical_wiki_match()`, plus exclusion/override helpers `wiki_does_not_match()`, `canonical_wiki_does_not_match()`, `wiki_slug_overrides()`, `canonical_wiki_manual_matches()`, `canonical_wiki_external_matches()`, and **editor-preservation helpers** `wiki_editor_cell_overrides()`, `wiki_editor_extra_rows()`, `apply_wiki_editor_overrides()` |
| `wiki-article.R` | `fetch_wiki_wikitext()` (MediaWiki API fetch by oldid), `parse_wiki_facility_table()` (parses the article's facility table, 9- and 10-column layouts, both cell styles), `build_wiki_revision_diff()` (cell-level diff of two revisions with `cell_change`/`added_row`/`removed_row`/`article_row_not_in_data` record types and prefix-based near-miss rescue for renamed rows), `build_wiki_list_extant_articles()` (existence/redirect/dab status of every article linked from the list tables, incl. redirect-target verification) |
| `wiki-refs-to-zotero.R` | **Ported from wiki-graph 2026-11-06** (header switched from the tidyverse meta-package to individual packages). Wikipedia reference extraction: `fetch_wikitext()` (with 429/503 retry + backoff), template parser (`extract_templates`, `parse_template_params`), `extract_refs_from_wikitext()`, `deduplicate_refs()`, DOI/ISBN enrichment (`enrich_refs`), Zotero item building and posting (`refs_to_zotero_items`, `import_to_zotero`, `check_library_for_refs`, `add_items_to_collection`, `wiki_refs_pipeline`). |
| `zotero-harvest.R` | Zotero reference harvest for the group library (group 6462728): `build_wiki_article_collection_map()` (extant articles → collection names; canonical name where matched, article title otherwise), `harvest_wiki_article_refs()` (extract+dedup refs per article, paced 0.5 s/request), `zotero_group_collections()`, `zotero_ensure_collection()` (subcollections under a parent), `harvest_wiki_refs_to_zotero()` (incremental import driver). Driven on demand by `zotero-harvest-workflow.R` — NOT a pipeline target (Wikipedia rate limits). |
| `wikipedia.R` | `generate_infobox()`, `generate_population_wikitable()`, `dedup_refs()`, `build_wiki_list_table()` (with `status_window` for era tables, editor-extra-rows and row-id-anchor switches), `build_closed_wiki_list_table()`, `generate_wikitable()` (supports a `.row_id` column for `|- id="..."` anchors), `generate_fy26_wikitable()`, `generate_fy25_26_wikitable()`, `generate_era_wikitable()`, `generate_closed_wikitable()`, era source notes `fy25_26_source_note()` / `fy21_24_source_note()` / `fy17_20_source_note()` / `fy10_16_source_note()`, the ADP data-quality note table `wiki_adp_notes()`, plus display-convention maps `.wiki_type_display`, `.management_wikilinks`, `.city_link_overrides`, and the **state link reference** `state_article_titles()` / `wiki_state_link()` — wikitext generation for individual facility articles and the Wikipedia list article |
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

Two roster-level override tables in `R/aggregate.R`, both applied in `build_facility_roster()` keyed by `canonical_id`:

-   **`canonical_vera_type_overrides()`** — sets `type_detailed_corrected`/`type_grouped_corrected` for facilities **absent from Vera** (DDP-only jails, hold rooms, the WV regional jails 258/344/345/386 — kept as `county_jail`/Non-Dedicated by decision 2026-10 — and the Dilley SAF line item 401 as DIGSA/Dedicated); applied BEFORE classification so the corrected columns are non-NA downstream. This is the fix for "Unclassified" `type_grouped` values in the DDP comparison analyses.
-   **`canonical_type_overrides()`** — sets `facility_type_wiki` after classification; verified against current DDP assignments 2026-10 (the earlier version was written against a shifted ID map and mislabeled several facilities).

Use `canonical_vera_type_overrides()` (not `vera_type_overrides()`) when a facility isn't in Vera at all — `vera_type_overrides()` only patches rows inside `vera_facilities`.

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

**Pass 2:** Within the same ZIP code, compute OSA string similarity on `facility_address`. Pairs with similarity ≥ 0.80 are merged via union-find, except for pairs in `do_not_merge_pairs()`. Note: exclusions must block **every** same-address name variant or the merge returns transitively — the Dilley SAF line item ("Dilley Processing Single Adult Female", canonical 401, DDP code DILLSAF) required five exclusion pairs to keep it separate from the Dilley IPC cluster (366; 341 is a stale FY19–FY20 duplicate of 366 that never merged because pass 1 keeps only the first address per name group).

**Canonical name:** Most recent year's name for each cluster (ties broken by `year_order`).

**Manual overrides:** `canonical_name_overrides_table()` in `crosswalk.R` — 7 entries correcting ambiguous state suffixes, punctuation, etc.

**Trajectory labels** (in `facility_presence`): - `continuous` — present every year FY10–FY26 (minus FY18 gap) - `persistent_gaps` — present in FY10 and FY26 but with gaps - `closed` — present in FY10, absent from FY26 - `new` — absent from FY10, present in FY26 - `transient` — absent from both FY10 and FY26

`year_order` covers FY10–FY17, FY19–FY25, FY26a, FY26b, and FY26 (FY18 omitted — no data source). The FY18 gap means a facility present in FY17 and FY19 is classified as `persistent_gaps` rather than `continuous`.

## FY26 snapshots and the two panels

FY26 has **three** imported ICE snapshots, all wired as first-class years in `build_data_file_info()` (`snapshot` column: `"a"`/`"b"`/`"c"`):

- **FY26a** — `data/ice/FY26_detentionStats02022026.xlsx` (Feb 2 file). Same layout as the later snapshots (sheet "Facilities FY26", header rows 9–10, rightmost column AA). Added 2026-10-25.
- **FY26b** — `data/ice/FY26_detentionStats_02122026.xlsx` (Feb 12 file, data through Feb 5, 2026).
- **FY26** — `data/ice/FY26_detentionStats07202026.xlsx` (July 20 file). The July file dropped 32 facilities that the Feb files listed.

All snapshots are imported, cleaned, aggregated, and pooled in the crosswalk (so facilities dropped mid-year keep their canonical clusters and registry IDs). `resolve_fy26_snapshots(facilities_all_keyed, interim =)` in `crosswalk.R` is a **cascade**: with `interim = TRUE`, each facility takes its row from the highest-priority snapshot where it appears (July → Feb 12 → Feb 2), and the FY26 fiscal-year code stays `"FY26"` for all three (distinguished by `fy26_snapshot` = `"a"`/`"b"`/`"c"`, NA before FY26):

- **`facilities_all_keyed_interim` → `facilities_panel_interim`**: full cascade. Used for the **registry, roster, presence matrix, canonical list (`panel_facilities`), facility profiles, the expanded map, and the FY25–FY26 union**. The Feb 2 snapshot revived 7 facilities with frozen registry IDs that the July file dropped and DDP had kept alive only as pins: Chavez (68), Cumberland County Jail (91), Daviess County Detention (95), Finney County Jail (133), Kansas City Holdroom (186), Marion County Jail (226), Southern Regional (344). No new IDs were minted for the Feb 2 file.
- **`facilities_panel`**: July entries only — what ICE reports as of the July snapshot. Used for the **"reported by ICE" side of the DDP comparison analyses**.

`save_outputs()` writes both panels to `data/`. Caveat: `closed_wikitable` still consumes the July-only panel, so Feb-only drops appear there as "Closed (Active FY26–FY26)".

The `fy26b` target (used by the DDP comparison chain for the `in_ice_fy26` flag) is just `facilities_keyed[["FY26b"]]` plus the known-ID patches in `build_fy26b()` — one import, one set of IDs.

## Registry pinning (canonical identity)

`data/canonical_id_registry.csv` now has a **`detloc` column** and pins **every DDP-assigned canonical** (431 + later appends): code → ID is frozen, so shifting the set of name-matched codes never renumbers facilities. Assignment rules:

- `build_ddp_facility_canonical()` (in `R/ddp.R`) is registry-aware: pinned codes keep their IDs; unpinned unmapped codes append after the block maximum (ddp_other after ~1263, hold after 2189, medical after 3226); new assignments are **written back** to the registry CSV (mirroring `build_dmcp_canonical_map()`). It receives `crosswalk` and excludes codes pinned to crosswalk-rostered canonicals (the panel row wins); if that cluster later dies, the pin returns the code to the DDP pool with its ID intact — this is how rosterless panel canonicals (e.g. 133 Finney, 186 Kansas City Holdroom, 344 Southern Regional) are revived from DDP data.
- `build_ddp_canonical_map()` emits a `match_type = "pinned"` row for every pin (with `ddp_role = "sole"` so it flows through `build_detloc_lookup()`), and its fuzzy/county/keyword search excludes pinned canonicals (prevents spurious cross-matches).
- `build_hold_canonical()` (in `themarshallproject-locations.R`) excludes detlocs already in `detloc_lookup`, so pinned hold codes (e.g. KANHOLD→186) are not re-minted in the 2181+ hold range.

Pins with living DDP codes whose panel clusters died restore roster rows from the DDP side. Since 2026-10-25 the Feb 2 file (0202) **is imported** as snapshot FY26a, so its seven facilities (see "FY26 snapshots") have real ICE FY26 ADP rows in the interim panel and union rather than DDP-only revival.

## Canonical ID space

| Range | Purpose |
|----|----|
| 1–405 | FY19–FY26 panel facilities — **frozen** in `data/canonical_id_registry.csv` (1–398 original freeze; 399–404 added 2026-04; 405 Midwest Regional Reception Center) |
| 406–1000 | Next free IDs for future annual-stats facilities (continues sequentially) |
| 1001–1053 | Facilities sourced from faclist15/faclist17 only (not in FY19–FY26 panel) |
| 1054–1257 | DDP non-hold, non-medical facilities — **pinned** in the registry with `detloc` (gaps: 1182 reserved) |
| 1258–2000 | Appends for new DDP-assigned facilities (1258–1263 assigned 2026-10-22); then reserved |
| 2001–2025 | ERO field offices (25 offices, from `ero-field-offices.qmd`) |
| 2026–2180 | Hold facilities (155: Marshall Project addresses + DDP hold/staging stubs) |
| 2181–2189 | Hold/CBP facilities from the DDP parquet (9, pinned; also frozen in `data/hold-canonical-registry.csv` since 2026-10-23 so `build_hold_canonical()` mints new IDs at 2190+, not 2181) |
| 2190–3000 | Reserved for future hold/staging expansion |
| 3001–3226 | Medical facilities from DDP/Vera (226, pinned) |
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

**Updates:** For downloading new DDP releases, versioned file naming, recreating the discontinued facilities-daily-population parquet, wiring releases into the pipeline, and provenance metadata, follow the `updating-ddp-data` project skill (`.posit/assistant/skills/updating-ddp-data/SKILL.md`). Full log of the 20260806 update: `agent/conversation-ddp-update-20261003.md`.

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
| Canonical facilities (IDs 1–404) with a DETLOC | 308+ of 344 (via detloc_lookup); all 962 covered via detloc_lookup_complete |
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

Facility name links use a 3-tier hierarchy: `wiki_slug` (confirmed article) → `wiki_match` (red link) → plain text. City/state values are wikilinked with `.city_link_overrides` (Philipsburg, PA; Greenwood, WV; and Fpo, FL → Guantánamo Bay Naval Base for the Migrant Operations Center's Fleet Post Office address).

The FY26 table has **82 facility name wikilinks** (up from \~23 in the original qmd pipeline), with 42 pointing to confirmed Wikipedia articles. The closed facilities table covers 166 facilities with 11 wikilinks from canonical-level matches.

### FY25–FY26 union wikitable (→ `fy25_26_wikitable`) — current upload artifact

The live Wikipedia list article now needs to cover **every facility listed in the FY25 spreadsheet or any FY26 snapshot (Feb 2 / Feb 12 / July 20)**, not just the July FY26 rows. A dedicated target chain does this:

- `facilities_fy25_26_union` — `build_fy25_26_union(facilities_all_keyed_interim)` in `crosswalk.R`: one row per union facility (currently **247**, no duplicate canonical IDs). FY26 values win via the cascade (July → Feb 12 → Feb 2); FY25-only facilities fall back to their FY25 rows.
- `wiki_match_table_fy25_26` — city/state alias matches for union names.
- `facilities_fy25_26_new_search` (cue = "never") — Wikipedia API search for union names not covered by the FY26 search target (FY25-only, Feb-only, renamed).
- `facilities_fy25_26_wiki` — same enrichment chain as `facilities_fy26_wiki` (slug overrides, contractors patch, fl17 management backfill, standardization), drawing on both search targets.
- `fy25_26_wikitable` — `generate_fy25_26_wikitable()` in `R/wikipedia.R`.

Output properties (as of 2026-10-25): the output is a full article-section block — `==Centers active in Fiscal Years 2025 and 2026==` heading, blank line, then the table (247 rows, sorted alphabetically; header `{| class="wikitable sortable"`, caption `|+ICE Detention Facilities in FY25–FY26`, **10 columns**: Facility Name, Status (year), City, State, Facility Type, Authority, Management, Average Daily Population, Minimum Capacity, Demographics), then the data-provenance note `fy25_26_source_note()` closing the table (composed from `ice_citation(2019:2026)` and the faclist17 citation, wrapped in named refs `ice-detention-fy19-fy26` / `ice-dmcp-faclist17`; the ice citation's ` }}` is normalized to `}}` to match the live article). Cells one per line with leading `|`; row separators `|-`; the Krome row carries `|- id="krome_north_service_processing_center"` via the `.row_id` mechanism. The user diffs regenerated output against `fy25_26_wikitable.txt` in the project root (a manual dump of the target). Status labels use the **"Active" style** — "Active (FYxx – FY26)", "Closed (Active FYxx – FY25)", "In use (FY26)" for one edge case — deliberately not the article's "In use (FY26)" phrasing; the user has confirmed this preference.

### Historical era wikitables (→ `fy21_24_wikitable`, `fy17_20_wikitable`, `fy10_16_wikitable`) — added 2026-10-25

Three more article sections, one target chain each (union → alias match → new API search → enrich → generate → city-link check), 18 targets total. Decisions confirmed by the user 2026-10-25:

- **Ranges:** FY21–FY24 (175 facilities), FY17–FY20 (250; FY18 has no data source and is skipped), FY10–FY16 (208; starts at FY10 because the DMCP listings cover it — the user had said FY11 but approved FY10). Era language (e.g. "Biden administration") is deliberately NOT used in headings.
- **Headings:** `==Centers active in Fiscal Years 2021 through 2024==`, `==...2017 through 2020==`, `==...2010 through 2016==`; captions `|+ICE Detention Facilities in FYxx–FYyy`.
- **Status semantics (user decision):** spans and Active/Closed are computed within the era's window via `build_wiki_list_table(status_window =)`: present in the window's final year → "Active (FYxx – FYyy)"; ended within the window AND never listed again → "Closed (Active FYxx – FYyy)"; ended within the window but listed again later (16–30 facilities per era) → "Active (FYxx – FYyy)" ending inside the window, NOT "Closed".
- **Era tables get no editor extra rows and no `.row_id` anchors** (`generate_era_wikitable()` passes `editor_extra_rows = NULL`, `editor_row_id_anchors = FALSE`): the AROCC row belongs to the current era, and anchor ids must be unique per page while a facility can appear in several sections. Cell overrides (refs, management, link fixes) still apply.
- **Data provenance:** FY21–FY24 and FY19–FY20 rows come from the annual spreadsheets; FY17 and FY10–FY16 rows come from `facilities_annual_sums` (DMCP listings, reduced schema). ADP falls back to the panel `adp` column when `sum_criminality_levels` is absent; capacity is backfilled from fl17 `facility_capacity` by canonical_id via `backfill_fl17_capacity()`. **FY17 ADP is partial-year (~9.5 months)** — not noted in the source note yet.
- **Source notes:** `fy21_24_source_note()` / `fy17_20_source_note()` / `fy10_16_source_note()` in `R/wikipedia.R` — drafted to parallel the FY25–FY26 note, each with era-specific named refs (`ice-detention-fy21-fy24`, `ice-detention-fy19-fy20`, `ice-dmcp-faclist17`, `ice-dmcp-faclist15`). **Wording is a draft — review against the live article before upload.**
- `build_fy25_26_union()` now delegates to the generalized `build_fy_range_union(keyed, years)` (later years win; FY18 skipped with a message; within-year duplicate canonical rows keep their first row — some spreadsheets list a facility twice under name variants, e.g. Port Isabel + "Rio Grande Valley Staging" both → canonical 313).
- **Within-year canonical duplication (audit: `duplicate-canonical-rows.md`, project root, 2026-10-25):** 8 cases across FY11, FY13, FY19 (×2), FY20 (×2), FY21, FY22 involving 5 canonicals (153 Grayson — two DETLOCs merged; 199 La Palma — "La Palma Correction Center - Apso" variant with substantial ADP 481–626; 190 Karnes — "Karnes County Residential Center" second row, ADP 214, male-only; 313 Port Isabel and 366 Dilley — tiny staging/TAP-ICE line items). Only La Palma (FY20 row) and Port Isabel (FY20 row) surface in the current tables, both in the FY17–FY20 section. Whether the La Palma "- Apso" and Karnes second rows are subpopulations or duplicate listings is **unresolved**. **The user decided NOT to alter `build_panel()` or other charts** — the panel still carries the dropped rows (year-level ADP sums overcount: FY21 +3.4%, FY20 +1.75%, FY19 +1.4%).
- **ADP data-quality notes:** `wiki_adp_notes()` in `R/wikipedia.R` appends a note to the Average Daily Population cell of the La Palma (FY17–FY20: "FY19 and FY20"; FY21–FY24: "FY21") and Karnes (FY17–FY20: "FY19") rows, stating that the spreadsheet also shows the variant name (in raw ICE caps) and that its data has been skipped. Notes fire when `build_wiki_list_table()`'s `year_name` matches the note's `window_end`, before the editor-override pass. Karnes/La Palma also appear in `closed_wikitable`, which does NOT carry the notes (not requested).
- Search pooling: each era's `*_new_search` anti-joins against all earlier search targets, so no name is queried twice. Search targets are cue = "never".
- City-link scans (`fy21_24_city_link_check`, `fy17_20_city_link_check`, `fy10_16_city_link_check`): all 0 problems after the `.city_link_overrides` additions.
- The FY25–FY26 wikitable is unchanged by the refactor (verified: 247 rows, 244 Active / 3 Closed / 1 In use).

### Zotero reference harvest (added 2026-11-06)

**Known-bad match (user-verified 2026-11-06, not yet fixed):** `canonical_wiki_external_matches()` maps canonical "Jefferson County Jail" to the Wikipedia article "Jefferson County Jail" — wrong. None of our Jefferson County Jail canonicals (check `facility_roster$facility_city`/`$facility_state`) corresponds to any Jefferson County Jail article on Wikipedia. Remove this entry before any re-harvest so its references don't land in a mismatched collection (the article extracted 0 `{{cite}}` templates anyway, so no harm was done in the first harvest). The other flagged pass-3/4 matches were user-verified as correct: Florence Correctional Center → Central Arizona Florence CC, Guantanamo MOC → JTF Camp Six, Louisiana State Penitentiary → Louisiana ICE Processing.

**First harvest completed 2026-11-06** into group 6462728 (parent "ICE detention facility references", key 8RVFQVPQ): 108 subcollections, 2,613 items all filed in collections (2,564 created + attached duplicates incl. cross-article matches), 96 pre-existing library items untouched. The 4 template-less articles (Bergen County Jail, Broward Transitional Center, Children's Village, Jefferson County Jail) have zero `{{cite}}` refs — status `no_refs`, not errors. `harvest_wiki_refs_to_zotero()` posts items via a raw API batch poster (`.zotero_post_items()`, 50/batch, verifies every response, retries editor→contributor for item types that reject editors) — c2z's `ZoteroPost()` was dropped after it silently dropped collection assignments and swallowed failed batches. All loops are resumable under `data/cache/wiki-refs/` (`wikitext/*.txt` via REST endpoint, `refs/*.rds` saved per article, `import-log.csv` appended per import; the failed c2z attempt's log is archived as `import-log-aborted-2026-11-06.csv`). Credential: `zotero_access_key_write` in `~/.Renviron` (write access granted 2026-11-06). `fetch_wikitext()` prefers the MediaWiki REST endpoint (`/w/rest.php/v1/page/`) over the action API — api.php 429s hard on bursts; retries honor `Retry-After`, max 2 tries per article. `c2z` + tidyverse subpackages were installed into renv 2026-11-06 (`renv::snapshot()` still pending).

Targets `wiki_list_extant_articles` (cue never; 3 API calls) and `wiki_article_collection_map` (local only) are in the pipeline. The heavy extraction is deliberately NOT a target: `zotero-harvest-workflow.R` (project root) runs the whole harvest on demand — fetches ~112 wikitexts, extracts/dedups refs, enriches via DOI/ISBN, creates one subcollection per facility under parent "ICE detention facility references" in group library 6462728, posts new items, attaches library duplicates. Incremental: re-runs reuse collections and never re-create matched items (DOI → ISBN → title+year cascade). Requires `ZOTERO_API_KEY` in `~/.Renviron` with write access to the group; `c2z` and tidyverse components were installed into renv 2026-11-06 (run `renv::snapshot()`). Alligator Alcatraz → Florida Soft-Sided Facility (canonical 136) was corrected in `canonical_wiki_manual_matches()` at the user's request.

### Non-destructive editing: editor preservation and change tracking

**Only non-destructive edits to the live article are acceptable.** Other editors' additions are carried into the generator so regenerated output reproduces them, and a diff chain records every change between our uploads:

- `wiki_editor_cell_overrides()` / `wiki_editor_extra_rows()` / `apply_wiki_editor_overrides()` (in `R/wiki-match.R`) — cell-level overrides and verbatim extra rows applied by `build_wiki_list_table()`. Currently covers Krome management (Akima, with ref), Alexandria Staging management/city, Camp East Montana management/capacity/type (with refs), renamed links for California City, Denver, Miami Correctional, and McCook, the Adelanto label decapitalization, the Northwest Ohio name cleanup, the Krome `.row_id` anchor, and the **AROCC row** (Arizona Removal Operations Coordination Center) — an editor-added facility that exists in no ICE spreadsheet, appended verbatim including its refs.
- **Editor errors are deliberately not adopted**: `[[Arizona|AR]]` on Arkansas rows, `[[Master of Arts|MA]]` for Massachusetts, red links `[[OK]]`, `[[WV]]`, `[[NJ]]` — recorded in the diff CSV but not carried into generated output.
- **State links** follow [Template:United States political divisions](https://en.wikipedia.org/wiki/Template:United_States_political_divisions): `state_article_titles` in `R/wikipedia.R` maps every state abbreviation to its article title, disambiguating GA (`Georgia (U.S. state)`), NY (`New York (state)`), and WA (`Washington (state)`); `wiki_state_link()` renders the State cell. Two of those titles are redirects on Wikipedia — that is what the template links, so it is what we emit. Replaces the old two-entry `.state_link_overrides` (GA/WA learned from editor diffs); `[[New York (state)|NY]]` matches the live article.
- `fy25_26_city_link_check` target: scans every distinct City wikilink in the generated FY25–FY26 table via `check_wiki_city_links()` (two-level: link target, then redirect destination). Most "City, ST" links go through Wikipedia's standard comma-state redirects — reported but not flagged. `problem` = non-existent article, disambiguation page, or redirect landing on a dab page / double redirect. First run (2026-10-25): 231 distinct city links, 226 standard redirects, 0 dab pages, 1 red link — `[[Fpo, FL]]` (Migrant Operations Center Main, Guantanamo, canonical 404; "Fpo" is a Fleet Post Office military mailing address). Fixed via `.city_link_overrides` → `[[Guantánamo Bay Naval Base|Fpo, FL]]`. `.city_link_overrides` also expands ICE's abbreviated city names that lack comma-state redirects (Thornton, PA; Bedford Hts, OH; St Johns, AZ — found by the era-table scans). Current scan: 0 problems across all four tables.
- Change-tracking targets in `_targets.R`: `wiki_last_upload_oldid` (currently 1356058855, our last upload), `wiki_article_current_oldid` (currently 1372812418), `wiki_last_upload_wikitext` / `wiki_article_current_wikitext` (both cue = "never", fetched via `fetch_wiki_wikitext()` in `R/wiki-article.R`), `wiki_editor_changes` (diff via `build_wiki_revision_diff()`), `wiki_editor_changes_file` (writes `data/wiki-editor-changes.csv`). Most recent run (2026-10-25): 45 cell changes, 6 added rows, 6 removed rows, 1 at-risk row ("Cimmarron Correctional Facility" — the article's misspelling of our Cimarron, canonical 76; false positive).
- `scrape_wiki_detention_table()` splits the Location column into City/State only when those columns are absent (robustness fix for the 10-column layout).
- `parse_wiki_facility_table()` in `R/wiki-article.R` handles both 9- and 10-column article layouts and both cell styles.

**Upload workflow:** (1) `tar_invalidate(wiki_article_current_wikitext)` and update `wiki_article_current_oldid` to the current revision; (2) `tar_make(names = c("wiki_article_current_wikitext", "wiki_editor_changes", "wiki_editor_changes_file", "fy25_26_wikitable", "fy25_26_city_link_check"))`; (3) review `data/wiki-editor-changes.csv` and `tar_read(fy25_26_city_link_check)` — fold any new editor additions into `wiki_editor_cell_overrides()`/`wiki_editor_extra_rows()` and fix flagged city links in `.city_link_overrides()` before pasting; (4) after uploading, update `wiki_last_upload_oldid` to the new revision ID. Note `tar_make(names = ...)` syntax, not `tar_make(target1, target2)`.

## Quarto reports

The pipeline renders analytical reports as HTML documents. Some are wired as `tar_quarto()` targets (re-render automatically when upstream data changes); the rest are rendered manually.

| Report | Pipeline target? | Description |
|--------|-----------------|-------------|
| `facility-summary.qmd` | Yes (`facility_summary_report`) | Facility counts by ID range, source coverage, trajectory statistics |
| `geocoding-divergence.qmd` | Yes (`geocoding_divergence_report`) | Maps and tables comparing geocoded coordinates across sources |
| `ddp-comparison.qmd` | Yes (`ddp_comparison_report`) | DDP daily population vs. ICE FY25 annual statistics; unreported facility analysis |
| `ddp-comparison-26.qmd` | Yes (`ddp_fy26_comparison_report`) | DDP (parquet) vs. ICE FY26 annual statistics (Oct 2025–Feb 5 2026); pipeline-side version of the ddp-comparison-26 post |
| `ddp-throughput.qmd` | Yes (`ddp_throughput_report`) | Person-level detention throughput from DDP stints: daily population/removals/book-ins, cumulative distinct individuals, re-detention, double removals; equal-length Biden/Trump presidential comparison windows |
| `missing-addresses.qmd` | No | Identifies roster facilities missing address information |
| `dmcp-listings.qmd` | No | Documentation of the 2015/2017 DMCP facility authorization data |
| `ero-field-offices.qmd` | No | ERO field offices as informal detention sites |
| `infobox-generator.qmd` | No | Wikipedia {{Infobox prison}} wikitext generator |
| `detention-list-wikitables.qmd` | No | Copyable MediaWiki table markup for Wikipedia list article |

### Spin-off blog posts

Four posts are published in `~/Dropbox (Personal)/R/quarto-website/posts/`:

| Post directory | Pipeline export target | Description |
|---|---|---|
| `ddp-comparison/` | `ddp_comparison_export` | DDP (Sep 2023–Oct 2025, feather) vs. ICE FY25 annual statistics; unreported facility analysis. Exports 11 RDS files to `data/ddp-comparison-export/`. |
| `ddp-comparison-26/` | `ddp_fy26_comparison_export` | DDP (Oct 2022–Mar 2026, parquet) vs. ICE FY26 annual statistics; comparison period Oct 2025–Feb 5 2026. Exports 8 RDS files to `data/ddp-comparison-export-fy26/`. |
| `ice-detention-map/` | *(none — rendered from data/ CSVs directly)* | Interactive Leaflet map of ~390 panel facilities (FY19–FY26 ICE annual stats only). |
| `ice-detention-map-expanded/` | `expanded_map_export` | Expanded Leaflet map including DDP-only facilities (792 facilities across all canonical ID ranges as of 2026-11-06). Exports `expanded_panel.rds`, `expanded_presence.rds`, `expanded_geocoded.rds` to `data/expanded-map-export/`. |
| `facility-directory/` | `facility_directory_export` | Reactable facility directory table with ADP bar charts and DDP sparklines for ~618 facilities (peak ≥ 2). Exports `facility_tbl.rds` to `data/facility-directory-export/`. |

**Cue convention (fixed 2026-11-06):** the deploy-export targets — `expanded_map_export`, `facility_directory_export`, `state_arrests_export` — use `cue = tar_cue(mode = "always")`, so every `tar_make()` re-stages their files. (A bare `tar_cue(mode = "never")` does **not** mean "never skip": per the targets docs, a "never"-cue target runs only on first build or after an error, and otherwise skips forever. The old convention had silently disabled all export updates since May 2026.) Publishing is the manual step. The general deploy workflow for each post:

1. `tar_make(<export_target>)` (or just a full `tar_make()`) — write/update pre-computed RDS files in the export directory.
2. For DDP comparison posts, review the local Quarto render first (`ddp_comparison_report` target).
3. Run `copy-data.sh` in the post directory to copy files to `posts/<post>/data/`.
4. Render and publish via the quarto-website project.

Targets that genuinely should never auto-run (downloads, rate-limited Wikipedia API searches, ICE node scans, pinned wiki revisions, the frozen `ddp_fy26_comparison_export_20260330` archive) keep `cue = tar_cue(mode = "never")`; re-run them with `tar_invalidate(<target>)` followed by `tar_make(<target>)` — a bare `tar_make()` will not do it.

The website versions of each post read pre-computed RDS files (not pipeline targets directly) so they can be rendered independently of the ice-detention pipeline.

**Mirrored copies (2026-09-22):** The finalized website versions of both DDP comparison posts are mirrored back into this repo at `ddp-comparison/` and `ddp-comparison-26/` (each containing the published `index.qmd`, `data/` RDS files, and supporting scripts). These are snapshots for reference — the website versions remain authoritative. The superseded local drafts (`ddp-comparison-old.qmd`, `ddp-comparison-index.qmd`, `ddp-comparison-index-modified.qmd`) were deleted at the same time.

**Pipeline-side FY26 report:** `ddp-comparison-26.qmd` (project root) is the pipeline-side counterpart of the FY26 post, mirroring the FY25 setup: it `tar_read()`s `ddp_new`, `fy26b`, `ddp_fy26_keyed`, `daily_totals_fy26`, `unmatched_fy26`, `peak_fy26` and derives the export tables inline (matching `export_ddp_fy26_comparison_data()`). Rendered via the `tar_quarto(ddp_fy26_comparison_report, "ddp-comparison-26.qmd")` target.

### Development workflow

Each stage of development leads from experiments to standalone Quarto reports, whose data should be automatically updated by the pipeline. Even manual corrections are managed in a functional way (e.g., `wiki_slug_overrides()`, `vera_type_overrides()`, `do_not_merge_pairs()`) that allows them to be extended without editing data files directly.

## Future work: Extend canonical Wikipedia matching

- Run Wikipedia API search (`add_wikipedia_matches`) against unmatched canonical facilities (partially done; 7 external matches in `canonical_wiki_external_matches()`)
- Fetch Wikipedia category "Immigration detention centers and prisons in the United States" and match members against unmatched canonicals
- Add confirmed new matches to `canonical_wiki_external_matches()`
- Review editor-added rows that exist only on Wikipedia (currently just AROCC in `wiki_editor_extra_rows()`) against the live article before each upload
- Review the drafted era source notes (`fy21_24_source_note()`, `fy17_20_source_note()`, `fy10_16_source_note()`) against the live article wording before uploading era sections; decide whether FY17's partial-year ADP needs a caveat
- Run `tar_make()` to reconcile the pipeline and re-render the non-data Quarto reports (as of 2026-11-06: `facility_summary_report` outdated; the 2026-10-26 full run already built `ddp_fy26_keyed` and `daily_totals_fy26`)
- Open question: whether the Feb 2 snapshot stays in the panel variants (currently in the interim cascade and the union, affecting 7 facilities)

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

Wikipedia/Zotero tooling (added 2026-11-06): `httr2` (REST fetch + Zotero raw API with retry), `stringi`, `readr` (import log), `c2z` (`ZoteroKey()` for item keys; `ZoteroPost()` is NOT used — see the Zotero harvest section), plus tidyverse subpackages. Installed into renv 2026-11-06; `renv::snapshot()` still pending.

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
