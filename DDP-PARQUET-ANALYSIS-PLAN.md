# DDP Parquet Integration & Extended Comparison Analysis — Plan

**Date:** April 11, 2026  
**Status:** Planning phase

---

## Task Scope

1. **Summarize the new parquet dataset** in a Quarto document that combines:
   - All information from `ddp-integration-summary.md`
   - Population-level statistics (daily, monthly, fiscal year aggregations)
   - Basic coverage metrics for FY2023–FY2026

2. **Create extended comparison reports** for FY2024 and FY2026 (parallel to existing FY2025 report)

---

## New Parquet File Analysis

### Dataset Overview

- **File:** `data/ddp/facilities-daily-population-latest.parquet`
- **Date range:** 2022-10-01 to 2026-03-10 (1,256 days; Oct 2022 – Mar 2026)
- **Facility codes:** 707 unique codes (vs. 853 in feather file)
- **Rows:** 888,699 facility-day observations
- **Variables:** 9 columns including daily counts, demographics, criminality, age indicators

### Key Differences from Feather File

- **Facility count:** 707 (parquet) vs. 853 (feather)
  - 87 facility codes unique to parquet (new codes)
  - 233 facility codes in feather but not parquet (likely consolidations or stubs)
- **Date coverage:** Parquet extends to Mar 2026 (vs. Oct 25, 2025 in feather)
- **File format:** Parquet (more efficient, better for large datasets)

### Population Summary by Fiscal Year

| Fiscal Year | Mean Daily | Median Daily | Max Daily | Total Person-Days |
|-------------|------------|--------------|-----------|-------------------|
| FY2023      | 41.1       | 0            | 1,776     | 10,611,760        |
| FY2024      | 54.6       | 0            | 2,203     | 14,141,343        |
| FY2025      | 70.7       | 0            | 2,940     | 18,254,136        |
| FY2026 (partial) | 98.2   | 0            | 4,130     | 11,175,237        |

**Note:** Median = 0 reflects many facility codes with very low activity (holding rooms, staging areas). Population trend shows dramatic growth through FY2025 and continued elevation in early FY2026.

---

## Deliverable 1: DDP Parquet Integration Summary Quarto Document

### File: `ddp-parquet-summary.qmd`

**Sections:**

1. **Overview**
   - Dataset source and access (parquet format advantages)
   - Date range and facility coverage
   - Relationship to feather file (same underlying data, extended date range)

2. **Integration Summary** (from `ddp-integration-summary.md`)
   - Functions in `R/ddp.R` (`build_ddp_codes()`, etc.)
   - Pipeline targets and workflow
   - DMCP and DDP matching logic
   - Canonical ID ranges and coverage

3. **Data Structure**
   - 9 variables: facility code, date, daily counts, demographics, facility name
   - Missing value analysis (none expected)
   - Facility code standardization

4. **Population Statistics**
   - Daily aggregate trend plot (2022–2026)
   - Fiscal year breakdown table (mean, median, max, total person-days)
   - Demographic composition by gender, criminal status, age
   - Top 20 facilities by peak daily population

5. **Facility Coverage**
   - Unique facility codes by source (707 total)
   - Breakdown: non-detained jails, federal, dedicated, family, medical, other
   - Geographic distribution by state/region (pie chart or table)
   - Comparison: parquet vs. feather facility count

6. **Data Quality Notes**
   - Zero-day observations (median = 0 due to holding rooms)
   - Facility code name mapping
   - Known data quirks and caveats

---

## Deliverable 2: Extended DDP-ICE Comparison Reports

### Structure

Replicate the existing **FY2025 comparison report** (`posts/ddp-comparison/index.qmd`) for **FY2024** and **FY2026**.

Each report will follow the same analytical structure:

#### **Part A: Aggregate Comparison**

| Metric | FY2024 | FY2025 | FY2026 |
|--------|--------|--------|--------|
| ICE annual stats facilities | 225 | 189 | (TBD) |
| DDP facility codes | XXX | 393 | XXX |
| ICE total ADP | (from annual stats) | 47,550 | (from annual stats) |
| DDP mean daily population | (computed) | 47,XXX | (computed) |
| Difference | (computed) | +1,038 | (computed) |

**Visualizations:**
- Daily population trend line (FY only)
- Facility count comparison
- Aggregate ADP bars (ICE vs. DDP)

#### **Part B: Facility-level Matching**

- Canonical ID matching via `detloc_lookup_full`
- Summary table: facilities in both sources, ICE-only, DDP-only
- Scatter plot: ICE vs. DDP ADP by facility (log scale)
- Agreement bands (facilities within ±10%, ±25%, ±50%, etc.)

#### **Part C: DDP-Only (Unreported) Facilities**

- Facilities appearing in DDP but not in ICE annual stats
- Count by facility type (hold, medical, federal, jails, etc.)
- Total unreported population
- Geographic distribution
- Monthly trend for unreported population
- Table: top 20 unreported facilities by peak population

#### **Part D: Data Quality & Caveats**

- DETLOC coverage and matching confidence
- Known gaps (e.g., CY 2018 data unavailable for ICE annual stats)
- Facilities with significant discrepancies
- Notes on facility consolidation and closure

---

## Implementation Plan

### Phase 1: Data Preparation

- [ ] Load parquet file and validate structure
- [ ] Compute fiscal year aggregations (daily, monthly, yearly)
- [ ] Merge with ICE annual stats for FY2024 and FY2026
- [ ] Apply facility crosswalk and canonical IDs
- [ ] Pre-compute comparison tables (exact/fuzzy matches, unmatched)
- [ ] Export pre-computed RDS files for report rendering (like FY2025)

### Phase 2: Summarize New Parquet Data

- [ ] Write `ddp-parquet-summary.qmd` with all sections above
- [ ] Include population trend plots and demographic breakdowns
- [ ] Add facility coverage tables and geographic analysis
- [ ] Render and review locally

### Phase 3: Create FY2024 Comparison Report

- [ ] Create `ddp-comparison-fy24.qmd` in report directory
- [ ] Adapt structure from FY2025 report
- [ ] Subset data to Oct 1, 2023 – Sep 30, 2024
- [ ] Compute all aggregate and facility-level comparisons
- [ ] Render and review
- [ ] Export pre-computed RDS files for possible deployment

### Phase 4: Create FY2026 Comparison Report

- [ ] Create `ddp-comparison-fy26.qmd` in report directory
- [ ] Subset data to Oct 1, 2025 – Mar 10, 2026 (partial year)
- [ ] Same analytical structure as FY2024 and FY2025
- [ ] Add note about partial year data
- [ ] Render and review

### Phase 5: Archive & Deploy (optional)

- [ ] Decide which reports to deploy to website
- [ ] Use RDS export + `copy-data.sh` workflow
- [ ] Update website repo links

---

## Data Pipeline Integration (Future)

Currently, **do not modify `_targets.R`**. The plan above uses existing functions:

- `build_ddp_codes()` — Already wired
- `detloc_lookup_full` — Already available
- Canonical facility data — Available from pipeline

If parquet becomes the primary source:

1. Add `tar_target(ddp_parquet_file, ...)` (format = "file", cue = "never")
2. Replace `ddp_raw` target to read parquet instead of feather
3. All downstream targets remain unchanged

---

## Deliverables Summary

| Deliverable | File | Type | Status |
|-------------|------|------|--------|
| DDP Parquet Summary | `ddp-parquet-summary.qmd` | Quarto report | Not started |
| FY2024 Comparison | `ddp-comparison-fy24.qmd` | Quarto report | Not started |
| FY2026 Comparison | `ddp-comparison-fy26.qmd` | Quarto report | Not started |
| Pre-computed RDS files | `data/ddp-comparison-export-fy24/` | RDS + CSVs | Pending |
| Pre-computed RDS files | `data/ddp-comparison-export-fy26/` | RDS + CSVs | Pending |

---

## Notes

- **Facility consolidation:** The parquet has 707 unique codes vs. 853 in the feather. This discrepancy should be investigated before finalizing.
- **FY2026 partial year:** Reports for FY2026 should be flagged as incomplete (data runs through Mar 10, not full fiscal year end).
- **Backwards compatibility:** Existing FY2025 report and all targets remain unchanged unless explicitly modified.
- **Metadata:** All three comparison reports should include identical data dictionaries and method descriptions.
