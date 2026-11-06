# Plan: Expanded ICE Detention Map Dataset

## Goal

Build an expanded version of `ice-detention-map` that adds facilities excluded from
ICE annual statistics — primarily hold rooms, ERO field offices, county jails, and
medical facilities visible in DDP daily data — by annualizing DDP records into
fiscal-year averages and merging with the existing `facilities_panel`.

The ICE-only map (`ice-detention-map`) remains a separate, unchanged pipeline output.
The expanded map is a parallel output sharing the same upstream targets.

---

## Context

### Current map
- ~390 facilities (canonical IDs 1–398), ICE annual stats only
- Data files: `facilities_geocoded_full.rds`, `facility_presence.rds`, `facilities_panel.rds`
- Served from `quarto-website/posts/ice-detention-map/`

### DDP coverage
- FY24 (Oct 1 2023 – Sep 30 2024): nearly complete (DDP starts late Sep 2023)
- FY25 (Oct 1 2024 – Sep 30 2025): complete
- FY26 (Oct 1 2025 – ~Mar 2026): partial; should be flexible since we will get
  more recent ICE stats in the future — don't hard-code a cutoff

### Facilities to potentially add (~476 non-panel facilities with canonical IDs)
- Hold/staging (IDs 2026–2186): ~161 hold rooms at ERO offices. ERO offices
  moved to longer-term holds in 2025 — include.
- ERO field offices (IDs 2001–2025): 25 offices — include.
- DDP non-medical jails/federal (IDs 1054–1203): 150 facilities — include.
- DMCP-only (IDs 1001–1053): 53 facilities — include if they appear in DDP.
- Medical (IDs 3001–3226): 226 hospitals/clinics — include (not noise if
  substantial ADP; controlled by ADP toggle on the map).
- Facilities in DDP without a canonical ID: do not drop; work through assigning IDs.

### Geocoding
`facilities_geocoded_all` already covers all canonical ID ranges — no new
geocoding pass needed for facilities that have IDs.

---

## Steps

### Step 1: Annualize DDP data → `build_ddp_annual_panel()`

New function in `R/ddp.R`. Calls existing `build_ddp_fy_summary()` for each
fiscal year in DDP coverage, joins to `detloc_lookup_full` for canonical IDs,
and stacks into a long-format table with a `fiscal_year` column.

Facilities without a canonical ID are NOT dropped — they are retained with
`canonical_id = NA` and flagged for follow-up ID assignment. A separate review
step will work through which facilities these are.

**Output columns** (mirrors `facilities_panel` structure):
- `canonical_id` (NA if not yet in `detloc_lookup_full`)
- `fiscal_year` (e.g. `"FY24"`, `"FY25"`, `"FY26"`)
- `detloc`
- `adp` (= `adp_total`)
- `adp_male`, `adp_female`
- `adp_criminality_noncrim` (= `adp_non_criminal`)
- `share_non_crim`, `share_female`
- `peak_population`, `peak_date`, `n_days`
- `data_source = "ddp"`

**New targets:**
- `ddp_annual_panel` — calls `build_ddp_annual_panel(ddp_raw, detloc_lookup_full)`
  for FY24, FY25, and partial FY26

---

### Step 2: Build combined panel → `build_expanded_map_panel()`

New function in new `R/expanded-map.R`. Merges `facilities_panel` (ICE) with
`ddp_annual_panel` (DDP). Retains one geographic point per facility — no duplicate
markers; discrepancy is recorded in the data and displayed in popup charts.

**Merge logic for each `(canonical_id, fiscal_year)` pair:**
1. **ICE only** → `data_source = "ice_only"`; note as "no DDP match" in popup
2. **DDP only** → `data_source = "ddp_only"`
3. **Both, ADP within threshold** → `data_source = "ice_ddp_agree"`;
   attach `ddp_adp` as comparison column
4. **Both, DDP substantially larger** (above threshold) → `data_source = "ice_ddp_diverge_high"`;
   retain both ADP values for popup display
5. **Both, ICE substantially larger** → `data_source = "ice_ddp_diverge_low"`

**ADP threshold:** parameter (default 25%); final value TBD during build.

**No type exclusions from the map.** Instead, map includes a toggle to
show/hide facilities with peak population < 2 (matching the pattern in `ddp-comparison-26/`).
Peak population is the threshold throughout — not mean ADP.

**Flag for ICE-only facilities**: Report which canonical facilities appear in
ICE annual stats but have no matching DDP code — a useful diagnostic for
understanding DDP coverage gaps.

**New target:**
- `expanded_map_panel` — calls `build_expanded_map_panel(facilities_panel, ddp_annual_panel, threshold = 0.25)`

---

### Step 3: Presence matrix, geocoding, and exports for expanded set

The expanded outputs are parallel to the ICE-only outputs; both remain active
pipeline targets and neither replaces the other.

- **`expanded_map_presence`**: Rebuild presence matrix from `expanded_map_panel`
  across all canonical ID ranges. Trajectory labels apply to panel facilities
  (IDs 1–398); DDP-only facilities get trajectory `"ddp_only"`.

- **`expanded_map_geocoded`**: Join `facilities_geocoded_all` to canonical IDs
  in `expanded_map_panel`. No new geocoding pass needed.

**New targets:**
- `expanded_map_presence`
- `expanded_map_geocoded`

---

### Step 4: Export → `expanded_map_export`

cue = "never" target. Writes RDS files to
`quarto-website/posts/ice-detention-map-expanded/data/`:
- `expanded_panel.rds` (long format, all sources and ID ranges)
- `expanded_presence.rds`
- `expanded_geocoded.rds`

---

### Step 5: New map post (`ice-detention-map-expanded/`)

Copy/extend `facilities-map-post.R`. Key additions:

- **Peak population toggle**: Show/hide facilities with peak population < 2, matching `ddp-comparison-26/` pattern. Peak (not mean ADP) is the threshold throughout — a facility that briefly held 2+ people is substantively different from one that never did.
- **All facility types included**: Hold/Staging, Medical, ERO Field Office in color
  palette and legend.
- **Data source flags drive popup content**:
  - `ice_only`: note no DDP match found
  - `ddp_only`: note absent from ICE annual stats; show FY coverage (FY24/FY25/partial FY26)
  - `ice_ddp_agree`: show single ADP bar chart
  - `ice_ddp_diverge_*`: show dual bars in popup sparkbar chart (ICE vs. DDP side by side)
    to make the discrepancy visible — same geographic point, richer popup
- **Sparkbars for DDP-only** rows show bars only for FY24/FY25 (and partial FY26);
  gap vs. ICE-only facilities' full FY10–FY26 history is visually apparent.
- FY26 partial handling: flexible cutoff; adapt as new ICE stats become available.

---

## Design decisions (resolved)

1. **Peak population threshold**: No hard exclude; use peak ≥ 2 as a map toggle
   (user-controlled), not a data filter. Peak population throughout — not mean ADP.
2. **Medical facilities**: Include. Not noise if substantial ADP.
3. **ERO field offices**: Include. Moved to longer-term holds in 2025.
4. **Divergence behavior**: Show discrepancy in popup bar chart; same geographic
   point — not separate markers.
5. **Partial FY26**: Flexible cutoff; do not hard-code. Pipeline adapts as new
   ICE stats arrive.

---

## File checklist

### New pipeline files
- [ ] Add `build_ddp_annual_panel()` to `R/ddp.R`
- [ ] Create `R/expanded-map.R` with `build_expanded_map_panel()`,
      `build_expanded_map_presence()`, `build_expanded_map_geocoded()`
- [ ] Add targets `ddp_annual_panel`, `expanded_map_panel`, `expanded_map_presence`,
      `expanded_map_geocoded`, `expanded_map_export` to `_targets.R`

### Review / ID assignment
- [ ] Extend `ddp_facility_canonical` (or add parallel target) to process
      `ddp_new`-only codes — 27 facilities with peak ≥ 2 currently have no
      canonical ID because they appear in the parquet source but not the feather
      source that `ddp_codes` is built from. Groups: 5 hold rooms (EDNHOLD peak=53,
      SAVHOLD peak=23, MGAHOLD peak=12, BRKHOLD, CHSHOLD), 4 BOP facilities,
      17 jails/other (incl. OAK, CRYCCTX, LAFAYLA).
- [ ] Identify ICE facilities with no DDP match (ICE-only diagnostic)

### New map post
- [ ] Create `quarto-website/posts/ice-detention-map-expanded/`
- [ ] Copy and adapt `facilities-map-post.R`
- [ ] Create `index.qmd`
- [ ] Create `copy-data.sh`

---

## Progress

- [x] Plan drafted and saved
- [x] Plan revised per scope review
- [x] Step 1: `build_ddp_annual_panel()`
- [x] Step 2: `build_expanded_map_panel()`
- [x] Step 3: Presence matrix + geocoded join
- [x] Step 4: Export target
- [x] Step 5: New map post
