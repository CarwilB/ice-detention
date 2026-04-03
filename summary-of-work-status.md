Here's the full picture of the 853 DDP facility codes:

| Status | Count | Notes |
|--------------------------|----------------------:|-----------------------|
| **Matched via DETLOC** | 160 | Direct code match against `dmcp_canonical_map`; canonical IDs already assigned |
| Unmatched detention facility | 238 | Facilities likely opened after 2017 or never in DMCP authorization lists |
| Hospital / medical facility | 186 | New category; not in DMCP or annual stats — facilities where detainees receive medical care |
| ERO hold room | 171 | Short-term holding rooms at field offices; a different document type |
| **High-conf name match (FY19-26)** | 66 | DDP codes for facilities in the annual stats panel that don't have a DETLOC in the crosswalk yet — these 66 are likely an easy win |
| BOP federal prison | 23 | Federal prisons housing ICE detainees |
| SPC / Staging — unmatched | 8 | ICE's own SPCs missing from DMCP (added after 2017) |
| 6-char other | 1 |  |

The `detention_facility_code` field is structurally identical to DETLOC — the 160 direct matches confirm this. The **66 high-confidence name matches** are particularly actionable: these are FY19-26 canonical facilities (already in the panel) that just need their DETLOC codes recorded. Committing those 66 would bring matched coverage to 226 of the 457 regular detention facilities in DDP (49%), with the remaining 238 being genuinely newer or non-DMCP facilities.

I'll suggest some questions below.

[Commit the 66 high-confidence name matches by adding their DDP codes to the canonical map, then produce a `ddp_canonical_map` table analogous to `dmcp_canonical_map`.]{.suggestion}

[Investigate what the 238 unmatched detention facilities are — whether they're post-2017 openings, facilities that appear only briefly, or facilities outside the ICE detention statistics system entirely.]{.suggestion}

[Treat hospitals, hold rooms, and BOP facilities as separate categories with their own canonical ID ranges (e.g. 2001+ for hospitals, 3001+ for hold rooms) rather than mixing them with detention facility IDs.]{.suggestion}

## User

/compact

## Databot

This conversation is being continued from a previous conversation that was compacted to reduce token use. The conversation is summarized below:

## Project Context

**ice-detention** is a `targets`-based R pipeline for importing, cleaning, and harmonizing U.S. ICE detention facility statistics across FY2019–FY2026, extracted and refactored from an earlier Quarto document in the wiki-graph project. The project maps detention facility identities across multiple data sources with distinct naming conventions and temporal coverage.

## Data Sources

The pipeline integrates three major data source tiers:

1.  **FY Annual Stats (FY19–FY26)** — 8 official ICE detention statistics spreadsheets, one per fiscal year. These form the core `facilities_panel` with \~30 measurement variables per facility per year.

2.  **DMCP Facility Listings (faclist15 and faclist17)** — Two point-in-time authorization rosters:

    -   `faclist15` — December 2015 XLSX (209 facilities, FY2010–FY2016 ADP data)
    -   `faclist17` — July 2017 PDF (201 facilities, FY2010–FY2017 ADP data)
    -   Combined: 230 unique facilities (180 shared, 29 faclist15-only, 21 faclist17-only)

3.  **DDP Daily Population Data** — Deportation Data Project feather file (`detention-facility-daily-population_filtered_20260312_031218.feather`): 661,928 rows covering 2023-09-01 to 2025-10-15, one row per facility-day, with 853 distinct facility codes representing the operational ICE detention infrastructure.

## Canonical Facility Identification System

**Canonical IDs** uniquely identify each distinct physical detention facility across all data sources:

| Range | Purpose |
|--------------------------------|----------------------------------------|
| 1–398 | FY19–FY26 facilities — **frozen** in `data/canonical_id_registry.csv` (348 actual distinct facilities; IDs are non-contiguous due to union-find clustering) |
| 399–1000 | Reserved for future annual stats (FY27+), continuing sequentially |
| 1001–1060 | DMCP-sourced new facilities (60 facilities not in FY19–FY26 panel) |
| 2001+ | Placeholder range for future categories (hospitals, hold rooms, etc.) |

The registry is frozen to ensure ID stability across pipeline runs. `build_facility_crosswalk()` now accepts `id_registry` as a parameter and looks up existing IDs by `(canonical_name, canonical_city, canonical_state)` rather than regenerating from `row_number()`.

## DMCP Integration (Completed)

### Data Quality Fixes Applied

Fixed five bugs in DMCP data parsing/cleaning:

1.  **City name corrections** — Added `"Kearny"` (NJ) and `"Colorado Springs"` (CO) to `fix_city_names()` in `R/clean.R`
2.  **ZIP zero-padding** — Already in `clean_dmcp_data()`; fixed truncation from leading-zero stripping in faclist15 XLSX
3.  **PDF column boundaries** — Corrected `.dmcp_pdf_col_breaks` in `R/import.R` (ZIP/type/type_detailed/male_female columns were 4–14 points too narrow, truncating ZIP codes to 3 digits)
4.  **Regex over-matching** — Fixed `"Cottonwood Fall\b"` regex to avoid `"Falls"` → `"Fallss"` corruption
5.  **State bleed fix** — Added `str_extract("[A-Z]{2}$")` to strip county name overflow into state column (e.g., `"Y VA"` from "ROCKINGHAM COUNTY")

### Matching Strategy (Three Passes)

**Pass 1: Exact name+city+state** — 164 matches against all facility_crosswalk variants

**Pass 2: Manual overrides** — 6 additional matches confirmed by address inspection: - `CCANOOH` → canonical 262 (Northeast Ohio Correctional Center) - `WASHCUT` → canonical 380 (Washington County Jail, Purgatory Correctional Facility) - `CSCNWWA` → canonical 357 (Northwest Detention Center) - `JENADLA` → canonical 208 (Central Louisiana ICE Processing Center / CLIPC) - `JOHNSTX` → canonical 183 (Johnson County Corrections Center) - `POLKCTX` → canonical 171 (IAH Secure Adult Detention Facility — Polk)

Three facilities (`JAMESGA`, `OTROPNM`, `STCDFTX`) share a road/ZIP with canonical facilities but have distinct street addresses (separate buildings in adjacent complexes); deliberately left unmatched pending confirmation of separate DETLOC codes for companion buildings.

**Pass 3: New IDs** — 60 facilities with no FY19–FY26 match assigned new canonical IDs 1001–1060

**Result:** 170 total matched (164 + 6), 60 new

### New Pipeline Artifacts

**File:** `R/integrate.R` — Contains three functions: - `dmcp_manual_matches()` — Hardcoded table of 6 manual match decisions - `build_dmcp_canonical_map()` — Three-pass matching engine; appends new IDs to `canonical_id_registry.csv` and emits message with new ID range - `attach_dmcp_canonical_ids()` — Joins `dmcp_canonical_map` onto a faclist tibble by DETLOC

**New targets in `_targets.R`:** - `dmcp_canonical_map` — One row per DETLOC (detloc, source, canonical_id, canonical_name, canonical_city, canonical_state, match_type) - `faclist15_keyed`, `faclist17_keyed` — Faclists with canonical_id/canonical_name/match_type columns prepended

**Documentation:** `dmcp-listings.qmd` (Quarto document) - Section 1: Data source overview (FY2015 XLSX vs. FY2017 PDF) - Section 2: Dataset summaries (row/column counts, type breakdowns) - Section 3: Overlap analysis (Venn summary: 180 shared, 29 faclist15-only, 21 faclist17-only; location consistency verification; 5 legitimate renames) - Section 4: Integration with canonical facility list (matching results, manual confirmation table, new facilities list, unmatched adjacent-facility note) - Placeholder: DMCP fiscal-year ADP tables (future work to pivot wide ADP columns into long format per facility per year, FY2010–FY2017)

### Registry Status

`data/canonical_id_registry.csv` — Frozen at 408 entries: - 348 entries for IDs 1–398 (FY19–FY26) - 60 entries for IDs 1001–1060 (DMCP-only)

## DDP Daily Population Integration (In Progress)

### Data Structure and Classification

**File:** `detention-facility-daily-population_filtered_20260312_031218.feather`

**Dimensions:** 661,928 rows (facility-days) × 12 columns **Date range:** 2023-09-01 to 2025-10-15 **Distinct facility codes:** 853 (DETLOC-format codes)

**Column schema:** \| Column \| Type \| Description \| \|--------\|------\|-------------\| \| `detention_facility_code` \| char \| ICE internal facility code (3–7 chars) — primary key \| \| `detention_facility` \| char \| All-caps facility name \| \| `state` \| char \| 2-letter state \| \| `date` \| date \| Observation date \| \| `n_detained` \| int \| People detained at any point that day \| \| `n_detained_at_midnight` \| int \| People held overnight \| \| `n_detained_male/female` \| int \| Gender breakdown \| \| `n_detained_convicted_criminal` \| int \| With ICE-recorded prior conviction \| \| `n_detained_possibly_under_18` \| int \| Age flag (based on birth year) \| \| `source_state` / `date_state` \| char / date \| Provenance (which FOIA release) \|

### Code Structure and Classification

All 853 codes are active (non-zero detention at some point). Classified by structure and facility type:

| Category | Count | Examples | Notes |
|--------------------|----------------:|--------------------|-----------------|
| **Matched via DETLOC** | 160 | STWRTGA, ADLNTCA, CSCNWWA | Direct match against dmcp_canonical_map |
| Hospital / medical facility | 186 | ADVHBCA, STJOSAZ, MCMEDAZ | New category; not in DMCP/annual stats |
| ERO hold room | 171 | ATLHOLD, DENHOLD, ALMHOLD | Short-term holding rooms at field offices (suffix "HOLD") |
| BOP federal prison | 23 | BOPBRO, BOPGUA, BOPSFO | Bureau of Prisons facilities (prefix "BOP") |
| SPC / Staging | 14 | BTV, PIC, KRO, EAZ | ICE Service Processing Centers (3-char codes) |
| 6-char other | 2 | DHDFNJ, EROFCB | Outliers outside standard patterns |
| **Unmatched detention facilities** | 238 | See below | Likely post-2017 openings or non-DMCP authorized |
| **High-conf name match (FY19-26)** | 66 | ABRXSPA→1, BOSSRLA→27, etc. | DDP codes for canonical facilities without recorded DETLOC |

### Matching Results

**Direct DETLOC matches:** 160 facilities from `dmcp_canonical_map` (both 1–398 FY19–FY26 range and 1001–1060 DMCP-only new facilities)

**High-confidence name matches:** 66 additional facilities in the FY19–FY26 canonical list (canonical IDs 1–398) that have DDP codes but lack recorded DETLOC codes. All achieved OSA name similarity ≥0.85 (mostly perfect 1.0) via fuzzy matching of DDP all-caps names against canonical title-case names within matching states. Examples: - `ABRXSPA` → canonical 1 (Abraxas Academy Detention Center) - `FIPCMGA` → canonical 225 (Folkston Main IPC) - `LAWINCI` → canonical 391 (Winn Correctional Center) - `MSVPCPA` → canonical 248 (Moshannon Valley Processing Center)

**Unmatched detention facilities:** 238 facilities with no match in either DMCP or FY19–26 canonical lists. Likely represent: - Facilities opened after 2017 (post-DMCP) - Facilities active only during specific periods - Facilities not included in official ICE detention statistics during FY2019–FY2026

**Hospitals/medical facilities:** 186 distinct codes representing hospitals and medical centers where detainees receive care (not primary detention locations). Examples: Banner Health facilities in Arizona, St. Joseph's Hospital, Valley Wise Health Medical Center. These constitute a new category requiring separate handling.

**Hold rooms:** 171 facilities at ERO field offices (HOLD suffix), representing informal short-term detention infrastructure. These are documented in the Guardian article and are a key focus of the DDP data.

## Key Decisions and Conventions

1.  **Naming consistency:** All DMCP and derivative tables renamed from `fy15_dmcp`/`fy17_dmcp` to `faclist15`/`faclist17` throughout, with `_raw`, `_keyed`, etc. applied consistently.

2.  **Data quality:** All cleaning applied uniformly to both DMCP sources; no facility-type differences are dropped.

3.  **Canonical ID freeze:** IDs 1–398 are immutable. Future annual stats (FY27+) begin at 399. DMCP-only facilities start at 1001 to keep ID spaces separate.

4.  **DETLOC as linking key:** The `detention_facility_code` in DDP is structurally identical to DETLOC codes in DMCP, enabling direct code-based joins for 160 facilities.

5.  **Unmatched pending categories:** Hospitals, hold rooms, and BOP facilities are not yet integrated into the canonical system; placeholders exist for future ID ranges (e.g., 2001+).

## Next Steps (Suggested)

1.  **Commit high-confidence matches:** Add the 66 DDP-only DETLOC codes to the canonical facilities that lack them, updating the registry and canonical_facilities table.

2.  **Investigate unmatched detention facilities:** Determine whether the 238 unmatched facilities are post-2017 openings, temporary facilities, or non-detention-statistics entries. Consider assigning new canonical IDs 1061–1298 (continuing from 1060).

3.  **Create `ddp_canonical_map` target:** Analogous to `dmcp_canonical_map`; consolidates DDP code→canonical_id mappings (160 direct + 66 name-matched).

4.  **Separate facility category ID spaces:** Assign ranges for hospitals (2001+), hold rooms (3001+), BOP (4001+) rather than mixing with detention facility IDs 1–1298.

5.  **Build DDP joining infrastructure:** Create target to attach canonical_id to the DDP daily population data, enabling facility-level aggregations and comparison with panel data.

6.  **Document hospital/hold room infrastructure:** Create accompanying QMD (analogous to `dmcp-listings.qmd`) explaining the DDP data sources, categories, and integration decisions.

## File System Summary

**Key modified/new files:** - `R/integrate.R` — New; DMCP canonical matching functions - `R/clean.R` — Updated city name and state cleaning - `R/import.R` — Updated PDF column boundaries - `R/crosswalk.R` — Updated to accept and use `id_registry` parameter - `_targets.R` — Added `id_registry_file`, `id_registry`, `dmcp_canonical_map`, `faclist15_keyed`, `faclist17_keyed` - `dmcp-listings.qmd` — New; comprehensive documentation of DMCP sources and matching - `data/canonical_id_registry.csv` — New; frozen registry of all canonical IDs assigned - `AGENTS.md` — Updated with DMCP integration status, canonical ID space definition, new targets

All targets run cleanly. The pipeline is ready for the next phase of DDP integration.

## User

Save this last response as a markdown file.

## Databot

<div>

<thinking id="thinking-1774125980135-mo7he"> The user wants to save the last response (the conversation summary/compacted context) as a markdown file. I can see there's already a file open called `conversation-export-2026-03-21.md`. Let me check if they want me to create a new file or append to the existing one.

The user said "save this last response" - I think they mean the summary that was provided at the start of this conversation (the compacted summary). Let me write it as a markdown file. I'll save it to a new file since `conversation-export-2026-03-21.md` already exists and is open.

Actually, looking at the context more carefully - the conversation was compacted and the summary was provided at the top.

I'll create a new markdown file with the summary content, using a filename like `conversation-summary-2026-03-21.md` to avoid overwriting the existing export file. </thinking>

</div>

[Response canceled by user]

</div>

</div>

</div>
