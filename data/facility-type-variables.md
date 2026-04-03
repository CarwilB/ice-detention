# Facility Type Variables

## Overview

There are two facility type variables used across the pipeline:

- **`facility_type_detailed`**: The raw ICE facility type code as it appears in the annual detention statistics spreadsheets (FY19–FY26) and DMCP authorization listings (FY15, FY17). This is the most granular type classification available. Values are short uppercase codes.

- **`facility_type_wiki`**: A human-readable classification derived from `facility_type_detailed` (via `classify_facility_type()` in `R/aggregate.R`) and from Vera Institute type classifications (via `.vera_type_to_wiki` in `R/crosswalk.R`). Used for Wikipedia article generation and general reporting.

## Source availability

| Source | `facility_type_detailed` | `facility_type_wiki` | `vera_type_corrected` | Other type columns |
|---|---|---|---|---|
| Panel (FY19–FY26 annual stats) | ICE code | Derived via `classify_facility_type()` | Joined via DETLOC in `build_facility_roster()` | — |
| DMCP (fl15, fl17 authorization lists) | ICE code (same vocabulary) | Derived via `classify_facility_type_combined()` | Joined via DETLOC in `build_facility_roster()` | `facility_type` (broader 4-value grouping) |
| Vera Institute | `type_detailed` (25 values; overlaps ICE codes, adds Hospital, Hotel, etc.) | — | Native (with project overrides via `vera_type_overrides()`) | — |
| DDP new facilities | — | Derived via `classify_facility_type_combined()` | Joined via DETLOC in `build_facility_roster()` | — |
| ERO field offices | `ero_office` (set in roster builder) | Derived via `classify_facility_type_combined()` | Joined via DETLOC in `build_facility_roster()` | — |
| Hold facilities | Internal codes (hold_room, staging, etc.) | Derived via `classify_facility_type_combined()` | Joined via DETLOC in `build_facility_roster()` | — |
| Marshall Project | — | — | — | — |

In the facility roster, `vera_type_corrected` is joined from `vera_facilities` via DETLOC. Of 962 roster facilities, 942 have a Vera type match; the 20 without are facilities with no DETLOC or DETLOCs absent from Vera's data.

## `facility_type_detailed` values (ICE annual stats, FY19–FY26)

| Code | Description | Typical `facility_type_wiki` mapping |
|---|---|---|
| IGSA | Intergovernmental Service Agreement | Jail |
| USMS IGA | U.S. Marshals Service Intergovernmental Agreement | Jail |
| DIGSA | Dedicated Intergovernmental Service Agreement | Dedicated Migrant Detention Center |
| CDF | Contract Detention Facility | Private Migrant Detention Center |
| USMS CDF | USMS Contract Detention Facility | Private Migrant Detention Center |
| SPC | Service Processing Center | ICE Migrant Detention Center |
| BOP | Bureau of Prisons | Federal Prison |
| STAGING | Staging facility | ICE Short-Term Migrant Detention Center |
| FAMILY | Family residential center | Family Detention Center |
| FAMILY STAGING | Family staging facility | Family Detention Center |
| JUVENILE | Juvenile facility | Juvenile Detention Center |
| DOD | Department of Defense | Military Detention Center |
| STATE | State-operated facility | State Migrant Detention Center |
| TAP-ICE | Trusted Adult Program | Other (currently) |
| Other | Unclassified by ICE | Other |

Facilities can change `facility_type_detailed` across fiscal years. Of 346 panel facilities, 55 (16%) have more than one value across the FY19–FY26 period. Common transitions include IGSA ↔ USMS IGA (contract vehicle changes) and IGSA → DIGSA (conversion to dedicated use).

## `facility_type_wiki` values

| Value | Sources that produce it |
|---|---|
| Jail | Panel (IGSA, USMS IGA), DMCP, Vera (Non-Dedicated) |
| Dedicated Migrant Detention Center | Panel (DIGSA) |
| Private Migrant Detention Center | Panel (CDF, USMS CDF), DMCP (DIGSA, CDF) |
| ICE Migrant Detention Center | Panel (SPC), DMCP (SPC) |
| ICE Short-Term Migrant Detention Center | Panel (STAGING) |
| Federal Prison | Panel (BOP), Vera (Federal) |
| Family Detention Center | Panel (FAMILY, FAMILY STAGING), Vera (Family/Youth) |
| Juvenile Detention Center | Panel (JUVENILE) |
| State Migrant Detention Center | Panel (STATE) |
| Military Detention Center | Panel (DOD) |
| Medical Facility | Vera (Medical) |
| ICE Hold Room | Hold facilities (hold_room, ero_hold) |
| ICE ERO Sub-Office | Hold facilities (sub_office) |
| ICE ERO Hold Room | Hold facilities (ero_hold) |
| ICE Custody/Case Facility | Hold facilities (custody_case) |
| ICE Staging Facility | Hold facilities (staging) |
| CBP Hold Facility | Hold facilities (cbp) |
| ICE Command Center | Hold facilities (command_center) |
| ICE ERO Field Office | ERO canonical (hardcoded) |
| Other | Fallthrough from any source |

## Vera Institute type vocabulary

Vera provides two levels of type classification:

### `vera_type_corrected` (8 values, after project overrides)

| Value | Count | Notes |
|---|---|---|
| Non-Dedicated | 467 | County jails with ICE contracts |
| Medical | 279 | Hospitals, clinics, medical transport |
| Federal | 271 | BOP facilities, federal detention centers |
| Hold/Staging | 207 | ICE hold rooms, staging areas |
| Other/Unknown | 83 | Unclassified |
| Dedicated | 60 | Dedicated ICE contract facilities |
| Hotel | 54 | Hotels used for ICE detention |
| Family/Youth | 43 | Family residential centers, shelters |

### `type_detailed` (25 values)

More granular; includes IGSA, USMS IGA, DIGSA, CDF, SPC, BOP, Hospital, Hotel, Hold, Unknown, and others. Overlaps substantially with the ICE `facility_type_detailed` vocabulary but extends it with medical, hotel, and hold subtypes.

## DMCP `facility_type` (broader grouping)

The DMCP authorization listings have a broader `facility_type` column alongside `facility_type_detailed`. It is a 4-value grouping present in the raw DMCP source data (both the 2015 XLSX and 2017 PDF). It is retained in the `faclist15` and `faclist17` target outputs (and their RDS/CSV exports) but **not propagated into downstream pipeline products** (annual sums, panel, roster, crosswalk). Only `facility_type_detailed` is carried forward. The broad grouping is fully derivable from `facility_type_detailed` — it simply collapses DIGSA into IGSA:

| `facility_type` | Covers `facility_type_detailed` values |
|---|---|
| IGSA | IGSA, DIGSA |
| USMS IGA | USMS IGA |
| CDF | CDF, USMS CDF |
| SPC | SPC |

## `classify_vera_category()` — Vera 8-category grouping

`classify_vera_category()` in `R/aggregate.R` maps `facility_type_detailed` to Vera's 8-value facility type vocabulary, based on Table 2 of the Vera Institute "ICE Detention Trends: Technical Appendix" (Smart & Lawrence, 2023). See `data/vera-type-coding.yml` for provenance.

| `category_vera` | ICE codes (Table 2) | Extensions beyond Table 2 |
|---|---|---|
| Non-Dedicated | IGSA | — |
| Dedicated | DIGSA, CDF, SPC | STATE |
| Federal | BOP, USMS CDF, USMS IGA, DOD, MOC | — |
| Hold/Staging | Hold, Staging | — |
| Family/Youth | Family, Juvenile | TAP-ICE |
| Medical | Hospital | — |
| Hotel | Hotel | FAMILY STAGING |
| Other/Unknown | Other, Unknown | *(fallthrough)* |

Three ICE codes appear in the FY19–FY26 panel but are absent from Vera's Table 2:

- **TAP-ICE → Family/Youth**: "Trusted Adult Program" sub-contracts at family detention facilities (Karnes FSC, Dilley IPC; FY22 only, ADP < 1).
- **FAMILY STAGING → Hotel**: FY21 hotels (Best Western, Comfort Suites, Holiday Inn Express, La Quinta, Suites on Scottsdale, Wingate) used for family staging in Arizona. Physical facilities are hotels; the FAMILY prefix reflects their use for families.
- **STATE → Dedicated**: State-operated facilities dedicated to immigration detention. Not in Vera's vocabulary; closest Vera category is Dedicated.

Note: Vera's Table 2 codes **USMS IGA as Federal**, which is the rule `classify_vera_category()` follows. The separate `vera_type_overrides()` in `vera-institute.R` reclassifies 16 specific USMS IGA county jails from Federal → Non-Dedicated in Vera's own data — that is a facility-level correction, not a change to the coding rule.

## Classification pipeline

1. **Panel data (FY19–FY26)**: `classify_facility_type()` in `R/aggregate.R` maps `facility_type_detailed` → `facility_type_wiki` via exact matching.
2. **DMCP-only facilities**: `build_facility_roster()` in `R/crosswalk.R` applies the same `classify_facility_type()`.
3. **DDP new facilities**: `build_facility_roster()` maps `vera_type_corrected` → `facility_type_wiki` via the `.vera_type_to_wiki` lookup vector.
4. **Hold and ERO**: Types are assigned during canonical data construction (`build_hold_canonical()`, ERO canonical CSV).

### `classify_facility_type_combined()` — unified classification

`classify_facility_type_combined(facility_type_detailed, vera_type_corrected)` in `R/aggregate.R` provides a single classification function suitable for the full roster across all ID ranges. It uses `facility_type_detailed` when available (recognizing both ICE panel codes and hold facility internal codes), then falls back to `vera_type_corrected` for facilities that only have Vera metadata. The `vera_type_corrected` column is joined into `facility_roster` via DETLOC from `vera_facilities`.

Coverage: of 962 roster facilities, 942 have a Vera type match. The 20 without are facilities with no DETLOC or DETLOCs absent from Vera's data. The combined function classifies all but 1 facility as a specific type (down from 10 "Other" in the previous approach). The remaining "Other" is LIRS - LFSRM Fort Collins (a refugee resettlement agency, Vera also codes as Other/Unknown).

The function uses three layers in priority order:
1. **`facility_type_detailed`**: ICE panel codes, hold facility internal codes (hold_room, staging, etc.), and `ero_office` for ERO field offices.
2. **Name-based overrides**: `.family_staging_hotels` (6 FY21 hotels classified as Hotel rather than Family) and `.other_type_overrides` (4 ICE "Other" facilities reclassified by name: 2 CBP facilities, Tornillo, Sunny Glen).
3. **`vera_type_corrected`**: Vera's 8-category vocabulary mapped to wiki types for facilities without ICE codes.

## Known issues

- **11 facilities classified as "Other"** in the roster need reclassification. These include 3 hotels, 2 CBP facilities, 1 county jail, 1 hospital, 1 children's shelter, 1 temporary tent facility (Tornillo), 1 TAP-ICE program facility, and 1 foster care facility.
- **`facility_type_detailed` is not currently in `facility_roster`** — only `facility_type_wiki` is present. Adding it requires choosing the most recent year's value for panel facilities (since 55 facilities change type over time).
- The DMCP `facility_type_detailed` vocabulary is a strict subset of the panel vocabulary (no Other, STAGING, FAMILY, etc.).
