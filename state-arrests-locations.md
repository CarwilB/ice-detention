# Assigning counties to arrest data for visualization

This document walks through the county-attribution machinery for ICE arrests, developed across the `aug26-update` (Tennessee, Minnesota) and `state-data-cleaning` (Illinois) lines of work and merged on 2026-11-06. All code lives in a single file, `R/state-arrests.R`. See also [GitHub issue 13](https://github.com/CarwilB/ice-detention/issues/13) for the original Tennessee landmark audit.

## The data

Arrests come from the [Deportation Data Project](https://deportationdata.org) (FOIA 2026-ICLI-00005). The two fields that carry geography are:

- `apprehension_site_landmark` — free text naming the arrest site (jail, ERO office, airport, street arrest, CAP-program site…). Present in every release, messy: arresting-office codes, state markers, typos.
- `apprehension_city_common_case` — the arrest city (Aug 2026 release only). Filled for \~99% of arrests and, when it matches a Census place, the most precise attribution available.

## Resolution order

Counties are attributed **city-first, landmark-second**. Everything is in `assign_arrest_location()`, which every consumer (the parameterized `state-arrests.qmd` report and any exploration script) calls so all analyses share one set of rules.

``` mermaid
flowchart TD
    A[Arrest row: apprehension_site_landmark,<br>apprehension_city_common_case] --> B{Release has city field<br>AND place-county crosswalk<br>covers this state?}
    B -- yes --> C[clean_arrest_city<br>squish, UNKNOWN → NA,<br>typo fixes, aliases]
    C --> D{city matches a<br>Census place?}
    D -- yes --> E[county = place's primary county<br>county_source = City]
    D -- no --> F[county_landmark]
    B -- no --> F
    F --> G{manual audit override<br>.landmark_county_overrides?}
    G -- yes --> H[county = override<br>county_source = Landmark]
    G -- no --> I[.parse_landmark_county_state<br>landmark engine, below]
    I --> J{engine returns an<br>in-state county?}
    J -- yes --> H
    J -- no --> K[county = NA,<br>unassigned_reason recorded]
    E --> L[county counts,<br>choropleth]
    H --> L
    K --> M[unassigned panel:<br>reasons + landmarks]
```

The landmark engine itself (`.parse_landmark_county_state()`) resolves in this order, first match wins:

``` mermaid
flowchart TD
    A[landmark text] --> B[.county_text_extraction<br>peel CAP - / CAP- / XX DOC - prefixes,<br>program phrases, interior segments]
    A --> C[named pattern tables<br>state-specific regex rules,<br>first match wins]
    A --> D[airport exact-match table<br>airport_landmarks]
    A --> E[general-area code<br>XXX GENERAL AREA, NON-SPECIFIC<br>→ office county if in state]
    A --> F[OTHER exact-match table<br>state-specific landmark lists]
    A --> G[generic X COUNTY parse]
    G --> H[.validate_county<br>must be a real county of the<br>suffix state or report state]
    H -- valid --> I[county, state]
    H -- invalid --> J[NA — no fabricated geography]
    C --> I
    D --> I
    E --> I
    F --> I
```

Known limitation: a landmark with **no state marker at all** that names a same-named county in another state still validates in-state (`GREENE COUNTY JAIL` in a report for any state with a Greene County). Landmarks carrying state markers are safe, though: inline `XX DOC` state-corrections markers (`A - WI DOC - BROWN COUNTY JAIL` → Brown, **WI**) and all other suffix forms (`XX STATE`, bare trailing `XX`, `, FULL STATE NAME`) are detected by `.landmark_state_markers()` and take priority over the county search; 541 such landmarks exist in the 20260806 release (FL 342, WI 153, VA, WV, AZ, IN, PA).

## The two layers in detail

### City layer (Aug 2026 release)

The city field is entirely new in the 20260806 release: no prior DDP release carries arrest geography below the state/landmark level, and DDP describes the raw "Apprehension city" as ["the most specific ICE arrest location information that we have received to date"](https://deportationdata.org/news/2026-08-24-ICE-release.html). It is hand-entered — spelling and punctuation vary, it is sometimes missing (\~4% of observations since 2025, more before), and it does not always agree with the arrest state. The processed variant `apprehension_city_common_case`, added in DDP's [2026-09-08 update](https://deportationdata.org/news/2026-09-08-detainers-release.html), standardizes case and most punctuation (18,513 distinct values reduced to 11,263) but otherwise leaves spelling variations in place; we therefore match on a letters-only key and a reviewed typo table rather than exact strings.

1.  **`build_place_county()`** overlays each state's Census cartographic-boundary places on counties (EPSG:5070), keeps the county holding the largest share of each place's area, flags places where a second county holds ≥ 10% (`multi_county`), and keeps the incorporated place when two places share a name. Inputs are the zips in `data/census/`.
2.  **`clean_arrest_city()`** squishes whitespace, maps UNKNOWN variants to NA, and applies reviewed spelling fixes (`.city_fixes()` — \~90 Illinois typos, e.g. "Chcago" → "Chicago") and neighbourhood/abbreviation aliases (`.city_aliases()` — "Little Village" → Chicago).
3.  **`.county_from_city()`** looks the cleaned city up by a letters-only key (`.city_key()`: "Mt. Prospect" == "Mount Prospect") in the crosswalk.

The city key is state-scoped, so a Texas city on a Tennessee report row never resolves to a Tennessee county — it simply fails and falls back to the landmark.

**Caveat: at-large arrests may locate the processing site, not the arrest.** Validation against the landmark field shows the city is genuine municipality-level arrest geography for the bulk of rows: within each "GENERAL AREA, NON-SPECIFIC" office code the reported cities number 34–297, the office's own city accounts for only 21–88%, and the remainder spreads plausibly across the office's area of operations; for landmarks naming a specific county jail, the modal city is that jail's town at \~100%. But for **at-large arrests the city can record the ICE processing point instead**: Broadview, IL — a village of \~8,000 hosting an ICE processing center — accounts for 4.9% of all Chicago-area general-area rows, and 63% of its rows are at-large; **Fort Snelling, MN** (a Census CDP at the MSP airport) is the top reported "city" for St. Paul general-area arrests (28%). County-level conclusions dominated by such sites should be read with that ambiguity in mind.

### Landmark layer

- **Per-state lookup tables** (`state_landmark_tables()`): general-area office codes (`mn_general_area_codes`, `tn_general_area_codes`), exact OTHER landmarks (`mn_other_landmarks`, `tn_other_landmarks`), and regex pattern tables (`mn_landmark_patterns`, `il_landmark_patterns`). Only codes/landmarks whose office actually sits in the report state get a county; out-of-state entries are kept for documentation and never plotted.
- **`il_landmark_patterns`** maps named facilities: THOMSON → Carroll, ILLINOIS RIVER CORRECTIONAL → Fulton, CHICAGO FIELD OFFICE/MCC/O'HARE → Cook. `CHI GENERAL AREA, NON-SPECIFIC` is deliberately **not** mapped to Cook: the city field shows those arrests are only \~52% Chicago.
- **Suffix-state detection** reads four forms — `, XX`, inline `XX STATE`/`XX STATE DOC`, a bare trailing `XX`, and a trailing full state name (`...MADISON COUNTY, MISSOURI`) — so out-of-state CAP-program jails never leak into the report state.
- **Validation** (`.validate_county()`): every generic "X COUNTY" parse must be a real county of the state it would be attributed to, with a small typo map (`.county_typos`: DEWIITT, GALATIN, PUTNAME). This is what fixed the "Cap-York" bug and stops IA/PA county jails from appearing on an Illinois map.

### Coverage (20260806 release, post-2025-01-20 arrests)

| State     | City | Landmark | Total mapped |
|-----------|------|----------|--------------|
| Tennessee | 83%  | 13%      | 96.2%        |
| Minnesota | 87%  | 9%       | 95.6%        |
| Illinois  | 99%  | 0.1%     | 99.0%        |

Known blind spot (both lines of work): a suffix-less landmark naming a same-named county in another state still validates in-state (`A - WI DOC - BROWN COUNTY JAIL` → Brown, IL).

## Field coverage by state

Share of arrests in each state (all rows in the 20260806 release, Oct 2022 – Aug 2026) with a non-missing `apprehension_site_landmark`, `apprehension_city_common_case`, and an assigned county from `assign_arrest_location()` (city-first where a place crosswalk exists, otherwise the landmark engine). The state fill chain (`apprehension_state_filled_in`, plus the project-level AOR/landmark-suffix fills of 2026-11) leaves 25,988 rows (2.9% of the dataset) with no state; they appear as NA and cannot be mapped — see the note below the table.

| State                          | Arrests | Landmark |  City | County |
|--------------------------------|--------:|---------:|------:|-------:|
| TEXAS                          | 226,307 |    80.3% | 87.5% |  33.2% |
| FLORIDA                        |  82,013 |    82.9% | 92.3% |  27.3% |
| CALIFORNIA                     |  75,975 |    66.9% | 86.1% |   2.5% |
| NEW YORK                       |  36,682 |    80.5% | 98.4% |    14% |
| NEW JERSEY                     |  33,941 |    92.5% | 90.4% |  16.1% |
| ARIZONA                        |  30,002 |    49.7% | 78.7% |  22.2% |
| GEORGIA                        |  28,262 |    66.7% | 94.7% |  23.3% |
| NA                             |  25,988 |    10.4% |  0.6% |     0% |
| TENNESSEE                      |  22,304 |    91.1% | 94.5% |  95.4% |
| VIRGINIA                       |  20,780 |    77.8% | 93.4% |   7.6% |
| MASSACHUSETTS                  |  18,270 |    74.5% | 91.9% |   2.9% |
| PENNSYLVANIA                   |  17,865 |    84.7% | 91.5% |  17.3% |
| ALABAMA                        |  15,582 |    89.7% | 92.3% |  22.4% |
| LOUISIANA                      |  15,520 |    86.9% | 96.3% |     0% |
| COLORADO                       |  15,354 |    78.2% | 73.6% |  37.1% |
| NORTH CAROLINA                 |  14,512 |    90.1% | 96.4% |    54% |
| OKLAHOMA                       |  14,463 |    80.8% | 93.5% |  18.6% |
| ILLINOIS                       |  13,081 |    71.9% | 94.9% |  94.9% |
| INDIANA                        |  12,903 |    95.6% | 88.8% |  52.2% |
| MARYLAND                       |  12,879 |    85.5% | 97.8% |    28% |
| SOUTH CAROLINA                 |  11,670 |    85.1% | 95.8% |  56.3% |
| UTAH                           |  11,335 |    80.1% | 89.1% |  28.4% |
| WASHINGTON                     |  11,143 |    76.1% | 90.5% |   0.1% |
| OHIO                           |  10,689 |    81.3% | 93.3% |  10.8% |
| MINNESOTA                      |   9,950 |    80.7% | 91.4% |  95.9% |
| ARKANSAS                       |   9,303 |    91.4% | 93.9% |  51.2% |
| MICHIGAN                       |   8,969 |    86.8% | 98.7% |  20.6% |
| KENTUCKY                       |   8,478 |    82.8% | 95.6% |  45.3% |
| MISSISSIPPI                    |   8,388 |    95.6% | 98.5% |  47.4% |
| MISSOURI                       |   8,027 |      81% | 91.8% |  31.7% |
| NEVADA                         |   6,940 |    89.8% | 88.1% |  42.3% |
| NEW MEXICO                     |   6,931 |    31.4% | 94.7% |     9% |
| KANSAS                         |   5,387 |    88.7% | 97.9% |  29.5% |
| WISCONSIN                      |   5,130 |    93.5% | 98.9% |  29.4% |
| NEBRASKA                       |   5,091 |    91.1% | 95.3% |  26.6% |
| IOWA                           |   4,362 |    95.3% | 86.8% |  59.2% |
| IDAHO                          |   4,292 |    87.2% | 58.8% |  26.7% |
| WEST VIRGINIA                  |   3,568 |      86% | 98.3% |  25.1% |
| OREGON                         |   3,453 |    68.1% | 82.6% |   0.9% |
| WYOMING                        |   2,276 |    87.3% |   93% |  34.8% |
| PUERTO RICO                    |   2,144 |    81.6% | 96.5% |     0% |
| CONNECTICUT                    |   2,137 |    75.6% |   87% |     0% |
| SOUTH DAKOTA                   |   2,059 |    96.6% | 53.5% |  55.4% |
| DISTRICT OF COLUMBIA           |   2,051 |    72.7% | 94.1% |     0% |
| MAINE                          |   1,913 |    89.3% | 98.8% |   7.3% |
| DELAWARE                       |   1,650 |    88.8% | 98.4% |   0.2% |
| RHODE ISLAND                   |   1,629 |    81.4% |   98% |   1.7% |
| NEW HAMPSHIRE                  |   1,221 |    86.9% | 93.5% |    43% |
| NORTH DAKOTA                     |   856 |    84.9% | 81.5% |  72.9% |
| MONTANA                         |   627 |      88% | 70.7% |  44.8% |
| HAWAII                          |   589 |      72% | 90.2% |     0% |
| VIRGIN ISLANDS                  |   367 |      67% | 90.7% |     0% |
| ALASKA                          |   283 |    82.3% | 98.2% |     0% |
| VERMONT                         |   243 |      58% | 99.2% |     0% |
| NORTHERN MARIANA ISLANDS        |   217 |    71.4% | 99.1% |     0% |
| ARMED FORCES - THE AMERICAS     |   168 |    75.6% | 99.4% |     0% |
| GUAM                            |   135 |    88.9% |   77% |     0% |
| FEDERATED STATES OF MICRONESIA  |    23 |    91.3% | 91.3% |     0% |
| ARMED SERVICES - PACIFIC        |     5 |      60% |  100% |     0% |
| ARMED FORCES - EUROPE           |     4 |      75% |  100% |     0% |
| OTHER                           |     3 |     100% |  100% |     0% |
| CHIAPAS                         |     2 |      50% |  100% |     0% |
| MEXICO                          |     1 |     100% |  100% |     0% |
| TAMAULIPAS                      |     1 |     100% |  100% |     0% |

The no-state block thins sharply over time and has almost no city data (0.6% filled). The project-level state fill (2026-11) recovered 12,470 of the original 43,431 NA rows — mostly landmark-conditional fills (DAL COUNTY JAIL → Texas, NSV = Nashville → Tennessee, DENVER, CO → Colorado), AOR-based fills for the nine unambiguous AORs, and a ", XX" suffix rule. The remaining 25,988 rows are mostly rows with no landmark at all (23,285) or generic office-area codes whose known-state rows never reach 95% dominance; 31 more are assigned by the curated `nationwide_landmark_states()` table for the nationwide report only.

## Where to add new entries

### New general-area office code ("XXX GENERAL AREA, NON-SPECIFIC" unassigned)

Add a row to the state's tribble in `R/state-arrests.R` (`tn_general_area_codes`, `mn_general_area_codes`). Only add the county if the office physically sits in the report state; otherwise record the office with its actual state so the row is documented but never mapped.

``` r
"FNV", "Farmington, NM Sub Office", "San Juan", "NM"
```

### New named facility with no county in its name

Add a row to the state's OTHER exact-match table (`tn_other_landmarks`, `mn_other_landmarks`) — full landmark string, uppercase, exactly as it appears in the data — or, if it generalizes (e.g. all CAP sites in a city), a regex row in the state's pattern table (`mn_landmark_patterns`, `il_landmark_patterns`). Pattern rows are first-match-wins in table order, so put more specific patterns (e.g. MSP airport before the generic "ST. PAUL" rule) first.

### A landmark that the engine gets wrong

Add an entry to `.landmark_county_overrides()` — a manual audit table checked before everything else, keyed by `(state, landmark, county)`. County spelling is normalized, so "St Clair", "St. Clair" and "Dupage" all work.

### A misspelled arrest city (city layer)

First check whether it's a Saint/Mount/Fort variant — `.city_key()` already handles those. Otherwise add `variant -> city` to `.city_fixes()` with the state column, and `.city_aliases()` if the name isn't a Census place at all.

### A county-name typo in landmarks

Add it to `.county_typos` (letters-only key → correct letters-only key), e.g. `PUTNAME = "PUTNAM"`.

### A new state

1.  Download the state's Census place zip `cb_2023_SS_place_500k.zip` (from the [GENZ2023 shapefiles](https://www.census.gov/cgi-bin/geo/shapefiles/index.php)) into `data/census/` — `census_place_files` picks it up automatically.
2.  Review that state's city typos with the stringdist approach in the branch's `il-location-exploration.R` and add them to `.city_fixes()`.
3.  Audit the state's top landmarks (the branch's audit workflow writes `data/il-landmark-audit/`-style tables) and add general-area codes, OTHER landmarks, or a pattern table under `state_landmark_tables()`.
4.  Render: `quarto render state-arrests.qmd -P state:STATENAME`, or add a `tar_quarto` target with a distinct `output_file`.

### Extending the pipeline after a new DDP release

Arrests and stays must come from the same release (`unique_identifier` is hashed per release). Repoint `arrests_file`/`stays_file` in `_targets.R` to the pinned parquet; `place_county` and the reports rebuild automatically.
