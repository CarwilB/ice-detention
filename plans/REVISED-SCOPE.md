# DDP Parquet Analysis — Revised Scope & Implementation Summary

**Date:** April 11, 2026  
**Status:** Planning complete; ready for Phase 3

---

## Executive Summary

The DDP parquet file extends detention population data from October 2022 through March 2026 (1,256 days) across 707 facility codes. The analysis plan has been revised to:

1. **Reverse FY phases:** Build FY2026 comparison first, then FY2024
2. **Simplify structure:** Remove presidential quarter splits (both years had single administration)
3. **Enhance visualization:** Add sparkline charts in facility popups, integrate address/city/state
4. **Standardize appearance:** Use facility type color scheme from `posts/ice-detention-map`

---

## Deliverables

### 1. ddp-parquet-summary.qmd ✓ COMPLETE DRAFT

**Status:** Draft complete; ready to render

**Contents:**
- Overview and dataset basics (888k rows, 707 facilities, Oct 2022 – Mar 2026)
- Pipeline functions and targets
- DDP–canonical facility matching (DETLOC, canonical ID ranges)
- Population statistics by fiscal year with **first/last nonzero dates**
- Facility type classification with **11-color palette** from ice-detention-map
- Facility code distribution by type and geography
- Data structure documentation and quality notes
- Access instructions for in-pipeline and standalone use
- Integration notes for FY2024 and FY2026 comparison reports

**Population Summary Table Update:**

| FY | First Nonzero | Last Nonzero | Min | Max | Mean | Median | Total Person-Days |
|----|---|---|---|---|---|---|---|
| 2023 | 2022-10-01 | 2023-09-30 | 0 | 1,776 | 41.1 | 0 | 10,611,760 |
| 2024 | 2023-10-01 | 2024-09-30 | 0 | 2,203 | 54.6 | 0 | 14,141,343 |
| 2025 | 2024-10-01 | 2025-09-30 | 0 | 2,940 | 70.7 | 0 | 18,254,136 |
| 2026 (partial) | 2025-10-01 | 2026-03-10 | 0 | 4,130 | 98.2 | 0 | 11,175,237 |

---

### 2. ddp-comparison-fy26.qmd (PHASE 3)

**Status:** Not started; specification complete

**Fiscal Year:** October 1, 2025 – March 10, 2026 (partial year; 162 days)

**Sections:**

#### Aggregate Comparison
- DDP facility count vs. ICE FY26 facility count
- Total ADP: ICE annual stats vs. DDP mean daily population
- Daily population trend (Oct 2025 – Mar 2026)
- Aggregate difference and percentage

#### Facility-level Matching
- Canonical ID matching via `detloc_lookup_full`
- Facilities in both sources (exact match table)
- ICE–DDP agreement scatter plot (log scale)
- Agreement bands (±10%, ±25%, ±50%)

#### DDP-Only (Unreported) Facilities
- Facility count by type with `facility_type_wiki`
- Total unreported population by type
- Table: Top 20 unreported facilities by peak daily population
  - Columns: Name, Type, Address, City, State, Peak Pop, First Seen, Last Seen
  - Type colored per palette
- Monthly trend for unreported population

#### Data Quality Notes
- DETLOC coverage and matching confidence
- FY2026 partial-year limitations
- Facility consolidation notes

#### Interactive Visualizations
- Facility popups with:
  - Name, address, city, state
  - Type (colored dot)
  - Status (open/closed)
  - Peak population and date
  - **SVG sparkline** showing daily population Oct 2025 – Mar 2026
- Type distribution pie/bar chart (colored per palette)

---

### 3. ddp-comparison-fy24.qmd (PHASE 4)

**Status:** Not started; specification complete

**Fiscal Year:** October 1, 2023 – September 30, 2024 (full year; 365 days)

**Sections:** Identical structure to FY2026, but:
- Full fiscal year (Oct 2023 – Sep 2024)
- ICE FY24 annual statistics comparison
- Sparkline shows full 12-month trend

---

## Technical Specifications

### Color Palette

All facility type visualizations use this 11-color scheme (from `posts/ice-detention-map/facilities-map-post.R`):

```r
type_colors <- c(
  "Jail" = "#377eb8",
  "Jail/Prison" = "#377eb8",
  "Private Migrant Detention Center" = "#e41a1c",
  "Dedicated Migrant Detention Center" = "#4daf4a",
  "ICE Migrant Detention Center" = "#984ea3",
  "ICE Short-Term Migrant Detention Center" = "#ff7f00",
  "Family Detention Center" = "#a65628",
  "Juvenile Detention Center" = "#543005",
  "Federal Prison" = "#f781bf",
  "State Migrant Detention Center" = "#e6ab02",
  "Military Detention Center" = "#66c2a5",
  "Other" = "#1b9e77"
)
```

### Facility Data Integration

All facility tables and popups include:

| Field | Source | Notes |
|-------|--------|-------|
| `canonical_name` | facility_roster | Canonical facility name |
| `facility_address` | facility_roster | Street address |
| `facility_city` | facility_roster | City name |
| `facility_state` | facility_roster | State abbreviation (2-letter) |
| `facility_type_wiki` | aggregate.R classif. | 11-category type system |
| `canonical_id` | detloc_lookup | Unique facility ID 1–398 or supplemental |
| `detloc` | detloc_lookup | ICE facility code (e.g., "STCDFTX") |

Joins via `detloc_lookup_full` (DDP facility code → canonical_id → roster data)

### Sparkline Visualization

**Pre-computed SVG embedded in facility popups:**

```
Inputs:
  • ddp_new: Daily population Oct 2025 – Mar 2026 (FY2026)
            or Oct 2023 – Sep 2024 (FY2024)
  • by: canonical_id, facility_type_wiki

Process:
  1. Group by facility, compute daily totals
  2. Compute min/max for axis scaling
  3. Generate SVG markup with:
     - Line chart (date vs. population)
     - Simple axis labels (month abbreviations)
     - Title with facility name
     - Minimal styling (black line, gray grid)
  4. Cache SVG HTML as column in pre-computed RDS
  5. Embed via htmltools::HTML() in Quarto

Output:
  • Width: 250–300 px
  • Height: 80–100 px
  • Font: 9–10pt sans-serif
```

**Example SVG structure:**
```html
<svg width="280" height="90" xmlns="http://www.w3.org/2000/svg">
  <!-- Grid lines -->
  <!-- Axes with month labels (Oct, Nov, Dec, Jan, Feb, Mar) -->
  <!-- Polyline with daily population data points -->
</svg>
```

### Data Preparation (Phase 1)

Tasks before creating comparison reports:

1. **Load and subset data**
   - FY2026: Oct 1, 2025 – Mar 10, 2026
   - FY2024: Oct 1, 2023 – Sep 30, 2024

2. **Merge with ICE annual stats**
   - ICE FY26 from `facilities_keyed`
   - ICE FY24 from `facilities_keyed`
   - Match via `detloc_lookup`

3. **Join with facility roster**
   - Add address, city, state, facility_type_wiki
   - Add geocoded coordinates (optional for popup)

4. **Compute facility-level statistics**
   - Peak daily population and date
   - Mean daily population
   - First/last nonzero dates
   - Type distribution

5. **Build sparkline HTML**
   - For each canonical facility
   - Daily population data over fiscal year
   - Generate SVG markup (reuse code from map post if possible)
   - Cache in RDS

6. **Generate popup HTML**
   - Name, address, city, state, type
   - Status, dates, peak population
   - Embed sparkline SVG

7. **Export pre-computed RDS files**
   - `ice_fy26.rds` — ICE annual stats FY26
   - `ddp_fy26.rds` — DDP summary FY26
   - `ddp_fy26_keyed.rds` — DDP with canonical IDs
   - `unmatched_fy26.rds` — DDP-only facilities
   - `daily_totals_fy26.rds` — Daily aggregate population
   - Similar for FY24: `ice_fy24.rds`, `ddp_fy24.rds`, etc.

---

## Implementation Workflow

### Phase 1: Data Preparation

- [ ] Load parquet and ICE annual stats for FY2026 and FY2024
- [ ] Filter to fiscal year date ranges
- [ ] Join via detloc_lookup to get canonical IDs
- [ ] Join with facility_roster for addresses and types
- [ ] Compute facility-level aggregates
- [ ] Build sparkline HTML for each facility-FY pair
- [ ] Export pre-computed RDS files

### Phase 2: Summary Document ✓ COMPLETE

- [x] Draft ddp-parquet-summary.qmd with all sections
- [ ] Render and review locally
- [ ] Verify tables display correctly

### Phase 3: FY2026 Comparison (Do First)

- [ ] Create ddp-comparison-fy26.qmd
- [ ] Implement aggregate comparison section
- [ ] Implement facility-level matching
- [ ] Implement unreported facilities analysis
- [ ] Add facility type color coding
- [ ] Embed sparkline charts in popups
- [ ] Render and review
- [ ] Export pre-computed RDS for FY2026

### Phase 4: FY2024 Comparison (Do Second)

- [ ] Create ddp-comparison-fy24.qmd
- [ ] Mirror FY2026 structure (code reuse)
- [ ] Adjust for full-year data range
- [ ] Render and review
- [ ] Export pre-computed RDS for FY2024

### Phase 5: Deploy (Optional)

- [ ] Copy RDS/CSV files to website post directory
- [ ] Update website post index pages
- [ ] Test links and rendering

---

## Key Differences from FY2025 Report

| Aspect | FY2025 (Existing) | FY2024/FY2026 (New) |
|--------|------|---------|
| **Presidential splits** | Biden (Oct 2024–Sep 2025) / Trump (Oct 2025–end) | Single admin (FY24: Biden; FY26: Trump only) |
| **Facility data** | Limited to DDP matches | Full address, city, state in tables |
| **Type coloring** | Not applied | 11-color palette from ice-detention-map |
| **Sparkline charts** | Not present | SVG embedded in facility popups |
| **First/last dates** | Summary only | Tracked per facility |

---

## Dependencies & Data Sources

### From ice-detention pipeline (targets):
- `facilities_keyed` (FY19–FY26 with canonical IDs)
- `facility_roster` (canonical facilities with addresses, types)
- `facilities_geocoded_all` (geocoded coordinates)
- `detloc_lookup_full` (DETLOC → canonical_id reference)

### From parquet:
- `data/ddp/facilities-daily-population-latest.parquet` (Oct 2022 – Mar 2026)

### From ice-detention-map post:
- Color palette code (`facilities-map-post.R` lines 23–36)
- Sparkline/popup HTML generation patterns (optional reuse)

---

## Notes

- **FY2026 partial year:** Only 162 days of data (Oct 2025 – Mar 10, 2026). Mark as partial in all visualizations and notes.
- **No presidential splits:** Both FY24 and FY26 had single administrations, simplifying the report structure.
- **Sparkline reuse:** Can adapt SVG generation code from existing map post (`make_adp_sparkbar`) or use simpler line-based approach.
- **Backward compatibility:** FY2025 report remains unchanged; these are new analyses alongside existing post.
