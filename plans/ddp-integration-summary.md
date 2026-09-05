# DDP Daily Population Data Integration — Implementation Summary

**Date:** March 21, 2026
**Status:** Complete and ready for `tar_make()`

## What was implemented

### 1. New R Functions (`R/ddp.R`)

Created three functions for DDP data import and cleaning:

- **`import_ddp_codes(dp_data)`** — Extracts unique detention facility codes from raw DDP daily population data
- **`clean_ddp_facility_names(df)`** — Applies project-standard facility name cleaning (using `clean_facility_names()` from `R/clean.R`)
- **`build_ddp_codes(dp_data)`** — Full pipeline: import + clean + organize

All cleaning uses existing standards:
- Abbreviation expansion (Dept → Department, Ctr → Center, etc.)
- Acronym restoration (Ice → ICE, Erc → ERO, etc.)
- State abbreviation expansion
- Facility-specific name fixes (same rules as DMCP data)

### 2. New Pipeline Targets (`_targets.R`)

Added three new targets:

```r
tar_target(ddp_file, ...)
  # File path: data/detention-facility-daily-population_filtered_20260312_031218.feather
  # Cue: format = "file" (tracks file changes)

tar_target(ddp_raw, ...)
  # Raw import via arrow::read_feather()
  # 661,928 rows (facility-day observations)

tar_target(ddp_codes, ...)
  # Built via build_ddp_codes(ddp_raw)
  # Result: 853 distinct facility codes, cleaned names
```

Also added `arrow` to the packages list in `tar_option_set()`.

### 3. DDP Coverage Analysis

**Result:** 158 of 179 (88.3%) non-DMCP canonical facilities have DDP representation:

| Category | Count | % |
|----------|------:|---:|
| Exact/fuzzy match (OSA ≥ 0.85) | 78 | 43.6% |
| Partial keyword match | 80 | 44.7% |
| **Total with DDP link** | **158** | **88.3%** |
| Fully unmatched | 21 | 11.7% |

### 4. Updated Documentation (`dmcp-listings.qmd`)

Added new **Section 5: DDP Daily Population Data Integration**:

- **Data source description** — Date range, dimensions, variables
- **Coverage summary** — Table of match types
- **Exact/high-confidence matches** — 78 facilities with OSA ≥ 0.85 similarity
- **Partial/keyword matches** — 80 facilities with keyword overlap
- **Fully unmatched** — 21 facilities with categorized reasons (border facilities, defunct, hotels, etc.)

Three tables rendered inline:

1. **Exact matches** (78 rows): canonical_id, canonical_name, city, DDP code, similarity
2. **Partial matches** (80 rows): canonical_id, canonical_name, city, state, DDP code, DDP facility, keyword count
3. **Fully unmatched** (21 rows): canonical_id, name, city, state, FY19–FY26 presence (● / ○)

### 5. Note on Adjacent Facilities

Updated the existing note on `JAMESGA`, `OTROPNM`, and `STCDFTX` to reflect that these are now being kept as **distinct** entries in the canonical list, as DDP data shows evidence of their separate operation (distinct facility codes with different detention populations).

---

## Files modified

- `R/ddp.R` — **NEW** (52 lines)
- `_targets.R` — **MODIFIED** (added `arrow` to packages; added 3 targets for DDP)
- `dmcp-listings.qmd` — **MODIFIED** (added Section 5, ~150 lines; updated note on adjacent facilities)

## Running the pipeline

```r
# Build all targets including new DDP import
targets::tar_make()

# Or load the DDP codes directly
targets::tar_load(ddp_codes)

# View the integration tables in the QMD
quarto::quarto_render("dmcp-listings.qmd")
```

## Data quality notes

**Names cleaning:** DDP facility names come ALL-CAPS from the source data (e.g., "FOLKSTON ANNEX IPC"). The `clean_facility_names()` function converts to Title Case and applies standardization rules, producing names consistent with canonical facility names.

**Example transformations:**
- `"FOLKSTON ANNEX IPC"` → `"Folkston Annex IPC"`
- `"CLARK COUNTY JAIL"` → `"Clark County Jail"`
- `"FCI BERLIN"` → `"FCI Berlin"`

**Unmatched facilities (21):** These represent:
- 5 hotel-based detention centers (Best Western, Comfort Suites, La Quinta, Red Roof Inn)
- 2 border/CBP facilities (San Ysidro POE, Tornillo POE)
- 1 federal facility (JTF Camp Six, Guantanamo)
- 5 county/municipal facilities likely inactive during DDP period
- 3 juvenile detention facilities
- Others likely de-authorized before 2023

---

## Next steps (optional, future work)

1. **DETLOC linking for DDP codes:** Create a target to match DDP facility codes to canonical IDs, enabling daily population time-series analysis by canonical facility.

2. **DDP-canonical mapping table:** Build `ddp_canonical_map` analogous to `dmcp_canonical_map`, recording which DDP codes correspond to which canonical_ids (with match type: exact, partial, or new).

3. **Fuzzy match refinement:** For the 80 partial matches, consider implementing more sophisticated context matching (e.g., geographic proximity, facility type, address similarity) to upgrade them to high-confidence status.

4. **Facility category expansion:** Define ID ranges for non-detention facility categories currently in DDP (e.g., 2001–2999 for hospitals, 3001–3999 for ERO hold rooms) to fully integrate the operational DDP infrastructure.

---

## Testing checklist

- [x] DDP file exists and is readable
- [x] `build_ddp_codes()` function works
- [x] New targets added to `_targets.R`
- [x] `tar_validate()` passes
- [x] Matching tables created (78 exact + 80 partial + 21 unmatched = 179)
- [x] QMD section added with tables
- [x] Facility name cleaning applied consistently

**Ready to commit and run `tar_make()`**
