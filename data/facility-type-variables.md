# Facility Type Variables

## Overview

There are four facility type variables used across the pipeline:

- **`facility_type_detailed`**: The raw ICE facility type code as it appears in the annual detention statistics spreadsheets (FY19–FY26) and DMCP authorization listings (FY15, FY17). For hold facilities, this column carries internal project codes (hold_room, staging, sub_office, etc.). Values are short uppercase codes (ICE) or lowercase codes (internal).

- **`type_detailed_corrected`**: Vera Institute's `type_detailed` with project overrides applied via `vera_type_overrides()` in `vera-institute.R`. For the 42 overridden facilities, this corrects "Other" or "Unknown" to the appropriate code. For non-overridden facilities, this equals Vera's original `type_detailed`. Uses both ICE codes (uppercase: BOP, SPC, CDF, STATE) and internal project codes (lowercase: county_jail, ero_hold, sub_office) when the ICE classification is unknown.

- **`type_grouped_corrected`**: Vera Institute's `type_grouped` (8-category vocabulary) with project overrides applied. For the 42 overridden facilities, this corrects "Other/Unknown" to the appropriate category. For non-overridden facilities, equals Vera's original `type_grouped`.

- **`facility_type_wiki`**: A human-readable classification derived by `classify_facility_type_combined()` in `R/aggregate.R`. This function resolves types through a 4-tier priority system (see below). Used for Wikipedia article generation and general reporting.

## Source availability

| Source | `facility_type_detailed` | `type_detailed_corrected` | `type_grouped_corrected` | `facility_type_wiki` |
|---|---|---|---|---|
| Panel (FY19–FY26 annual stats) | ICE code | Joined via DETLOC | Joined via DETLOC | Derived via `classify_facility_type()` |
| DMCP (fl15, fl17 authorization lists) | ICE code (same vocabulary) | Joined via DETLOC | Joined via DETLOC | Derived via `classify_facility_type_combined()` |
| Vera Institute | — | Native (with project overrides) | Native (with project overrides) | — |
| DDP new facilities | — | Joined via DETLOC | Joined via DETLOC | Derived via `classify_facility_type_combined()` |
| ERO field offices | `ero_office` (set in roster builder) | Joined via DETLOC | Joined via DETLOC | Derived via `classify_facility_type_combined()` |
| Hold facilities | Internal codes (hold_room, staging, etc.) | Joined via DETLOC | Joined via DETLOC | Derived via `classify_facility_type_combined()` |
| Marshall Project | — | — | — | — |

In the facility roster, `type_detailed_corrected` and `type_grouped_corrected` are joined from `vera_facilities` via DETLOC. Of 962 roster facilities, 942 have a Vera type match; the 20 without are facilities with no DETLOC or DETLOCs absent from Vera's data.

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
| STAGING | Staging facility | ICE Staging Facility |
| FAMILY | Family residential center | Family Detention Center |
| FAMILY STAGING | Family staging facility | Family Detention Center |
| JUVENILE | Juvenile facility | Juvenile Detention Center |
| DOD | Department of Defense | Military Detention Center |
| STATE | State-operated facility | State Migrant Detention Center |
| TAP-ICE | Trusted Adult Program | Family Detention Center |
| Other | Unclassified by ICE | Other |

Facilities can change `facility_type_detailed` across fiscal years. Of 346 panel facilities, 55 (16%) have more than one value across the FY19–FY26 period. Common transitions include IGSA ↔ USMS IGA (contract vehicle changes) and IGSA → DIGSA (conversion to dedicated use).

## Internal project codes (lowercase)

These are used in `facility_type_detailed` (for hold/ERO facilities) and in `type_detailed_corrected` (for Vera overrides where the ICE code is unknown).

| Code | Used in | Description | `facility_type_wiki` mapping |
|---|---|---|---|
| county_jail | `type_detailed_corrected` | County jail (ICE contract type unknown) | Jail |
| hold_room | `facility_type_detailed` | ICE hold room | ICE Hold Room |
| ero_hold | Both | ERO hold facility | ICE ERO Hold Room |
| sub_office | Both | ICE ERO sub-office | ICE ERO Sub-Office |
| custody_case | `facility_type_detailed` | Custody/case management facility | ICE Custody/Case Facility |
| staging | `facility_type_detailed` | Staging facility | ICE Staging Facility |
| cbp | `facility_type_detailed` | CBP hold facility | CBP Hold Facility |
| command_center | `facility_type_detailed` | ICE command center | ICE Command Center |
| ero_office | `facility_type_detailed` | ERO field office | ICE ERO Field Office |

## `facility_type_wiki` values

| Value | Sources that produce it |
|---|---|
| Jail | Panel (IGSA, USMS IGA), Vera detailed (USMS IGA, county_jail), Vera grouped (Non-Dedicated) |
| Dedicated Migrant Detention Center | Panel (DIGSA), Vera detailed (DIGSA) |
| Private Migrant Detention Center | Panel (CDF, USMS CDF), Vera detailed (CDF), Vera grouped (Dedicated) |
| ICE Migrant Detention Center | Panel (SPC), Vera detailed (SPC) |
| ICE Staging Facility | Panel (STAGING), Hold facilities (staging), Vera detailed (Staging) |
| Federal Prison | Panel (BOP), Vera detailed (BOP), Vera grouped (Federal) |
| Family Detention Center | Panel (FAMILY, FAMILY STAGING), Vera detailed (Family), Vera grouped (Family/Youth) |
| Juvenile Detention Center | Panel (JUVENILE), Vera detailed (Juvenile) |
| State Migrant Detention Center | Panel (STATE), Vera detailed (STATE) |
| Military Detention Center | Panel (DOD) |
| Medical Facility | Vera detailed (Hospital), Vera grouped (Medical) |
| Hotel | Panel (FAMILY STAGING for known hotels), Vera detailed (Hotel), Vera grouped (Hotel) |
| ICE Hold Room | Hold facilities (hold_room), Vera detailed (Hold), Vera grouped (Hold/Staging) |
| ICE ERO Hold Room | Hold facilities (ero_hold), Vera detailed (ero_hold) |
| ICE ERO Sub-Office | Hold facilities (sub_office), Vera detailed (sub_office) |
| ICE Custody/Case Facility | Hold facilities (custody_case) |
| CBP Hold Facility | Hold facilities (cbp), name overrides |
| ICE Command Center | Hold facilities (command_center) |
| ICE ERO Field Office | ERO canonical (hardcoded) |
| Other | Fallthrough from any source |

## Vera Institute type vocabulary

Vera provides two levels of type classification. The project applies overrides to both via `vera_type_overrides()` in `vera-institute.R`, producing `type_detailed_corrected` and `type_grouped_corrected`. The originals are preserved as `type_detailed` and `type_grouped`.

### `type_grouped_corrected` (8 values, after project overrides)

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

### `type_detailed_corrected` (25+ values)

More granular; includes IGSA, USMS IGA, DIGSA, CDF, SPC, BOP, Hospital, Hotel, Hold, Unknown, and others. Overlaps substantially with the ICE `facility_type_detailed` vocabulary but extends it with medical, hotel, and hold subtypes. For 42 overridden facilities, includes internal project codes (county_jail, ero_hold, sub_office) and known ICE codes (BOP, SPC, CDF, STATE).

### `vera_type_overrides()` — 42 project corrections

All 42 overridden facilities had `type_detailed` of "Other" or "Unknown" and `type_grouped` of "Other/Unknown" in Vera's original data. The overrides correct both levels:

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

Note: Vera's Table 2 codes **USMS IGA as Federal**, which is the rule `classify_vera_category()` follows. The separate `vera_type_overrides()` in `vera-institute.R` corrects 42 specific facilities with wrong type classifications in Vera's data — that is a facility-level correction, not a change to the coding rule.

## `classify_facility_type_combined()` — unified classification

`classify_facility_type_combined()` in `R/aggregate.R` provides a single classification function suitable for the full roster across all ID ranges. It resolves `facility_type_wiki` through a 4-tier priority system, using the shared `.classify_detailed()` helper for tiers 1 and 3:

### Tier 1: `facility_type_detailed` (ICE panel codes + hold facility internal codes)

The primary source. Handles all ICE uppercase codes (IGSA, USMS IGA, DIGSA, CDF, SPC, BOP, etc.) and internal lowercase codes from the hold facility pipeline (hold_room, ero_hold, sub_office, staging, cbp, command_center, ero_office). Also handles project codes like county_jail.

### Tier 2: Name-based overrides

`.family_staging_hotels` (6 FY21 hotels classified as Hotel rather than Family) and `.other_type_overrides` (4 ICE "Other" facilities reclassified by name: 2 CBP facilities, Tornillo, Sunny Glen).

### Tier 3: `type_detailed_corrected` (Vera-corrected detailed codes)

Uses the same `.classify_detailed()` mapping as tier 1, applied to the Vera-corrected detailed type. This catches facilities where `facility_type_detailed` is NA but Vera has a meaningful detailed code — either from Vera's original data (e.g., USMS IGA, DIGSA, Juvenile) or from project overrides (e.g., STATE, SPC, CDF, county_jail). This tier produces more specific classifications than the grouped fallback: for example, USMS IGA → Jail (rather than Federal → Federal Prison), and Juvenile → Juvenile Detention Center (rather than Family/Youth → Family Detention Center).

### Tier 4: `type_grouped_corrected` (Vera grouped category fallback)

Maps Vera's 8 categories to wiki types. This is the fallback for facilities where both `facility_type_detailed` and `type_detailed_corrected` are NA or unrecognized:

| `type_grouped_corrected` | `facility_type_wiki` |
|---|---|
| Non-Dedicated | Jail |
| Dedicated | Private Migrant Detention Center |
| Federal | Federal Prison |
| Family/Youth | Family Detention Center |
| Medical | Medical Facility |
| Hotel | Hotel |
| Hold/Staging | ICE Hold Room |
| Other/Unknown | Other |

### Function signature

```r
classify_facility_type_combined(
  facility_type_detailed,
  type_grouped_corrected,
  facility_name = NULL,
  type_detailed_corrected = NULL
)
```

All parameters accept vectors (for use inside `dplyr::mutate()`). The `type_detailed_corrected` parameter is optional; when NULL, tier 3 is skipped and the function behaves as a 3-tier system.

## Classification pipeline

1. **Panel data (FY19–FY26)**: `classify_facility_type()` in `R/aggregate.R` maps `facility_type_detailed` → `facility_type_wiki` via exact matching.
2. **DMCP-only facilities**: `build_facility_roster()` in `R/crosswalk.R` applies `classify_facility_type_combined()`.
3. **DDP new facilities**: `build_facility_roster()` applies `classify_facility_type_combined()` with all four tiers.
4. **Hold and ERO**: Types are assigned during canonical data construction (`build_hold_canonical()`, ERO canonical CSV).

## Known issues

- **`facility_type_detailed` is not currently in `facility_roster`** — only `facility_type_wiki` is present. Adding it requires choosing the most recent year's value for panel facilities (since 55 facilities change type over time).
- The DMCP `facility_type_detailed` vocabulary is a strict subset of the panel vocabulary (no Other, STAGING, FAMILY, etc.).
