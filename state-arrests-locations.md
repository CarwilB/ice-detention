# Assigning counties to arrest data for visualization

This document walks through the county-attribution machinery for ICE arrests, developed across the `aug26-update` (Tennessee, Minnesota) and `state-data-cleaning` (Illinois) lines of work, merged on 2026-11-06, and extended on 2026-11-18 with the `county_state` refactor (resolved counties carry their own state; consumers choose what to plot). All code lives in a single file, `R/state-arrests.R`. See also [GitHub issue 13](https://github.com/CarwilB/ice-detention/issues/13) for the original Tennessee landmark audit and [issue 16 comment](https://github.com/CarwilB/ice-detention/issues/16#issuecomment-6983591229) for the state-by-state rollout plan.

## The data

Arrests come from the [Deportation Data Project](https://deportationdata.org) (FOIA 2026-ICLI-00005). The two fields that carry geography are:

- `apprehension_site_landmark` — free text naming the arrest site (jail, ERO office, airport, street arrest, CAP-program site…). Present in every release, messy: arresting-office codes, state markers, typos.
- `apprehension_city_common_case` — the arrest city (Aug 2026 release only). Filled for \~99% of arrests and, when it matches a Census place, the most precise attribution available.

## Resolution order

Counties are attributed **city-first, landmark-second**. Everything is in `assign_arrest_location()`, which every consumer (the parameterized `state-arrests.qmd` report, the nationwide precomputation, and any exploration script) calls so all analyses share one set of rules.

``` mermaid
flowchart TD
    A[Arrest row: apprehension_site_landmark,<br>apprehension_city_common_case] --> B{Release has city field<br>AND place-county crosswalk<br>covers this state?}
    B -- yes --> C[clean_arrest_city<br>squish, UNKNOWN → NA,<br>typo fixes, aliases]
    C --> D{city matches a<br>Census place?}
    D -- yes --> E[county = place's primary county<br>county_state = report state<br>county_source = City]
    D -- no --> F[county_landmark]
    B -- no --> F
    F --> G{manual audit override<br>.landmark_county_overrides?}
    G -- yes --> H[county = override<br>county_state = report state<br>county_source = Landmark]
    G -- no --> I[.parse_landmark_county_state<br>landmark engine, below]
    I --> J{engine resolves<br>county AND state?}
    J -- yes --> H2[county + county_state kept<br>EVEN when state ≠ report state<br>county_source = Landmark]
    J -- no --> K[county = NA,<br>unassigned_reason recorded]
    E --> L[consumers]
    H --> L
    H2 --> L
    K --> M[unassigned panel:<br>reasons + landmarks]
    L --> N{consumer}
    N -- per-state report --> O[choropleth filters<br>county_state == report state]
    N -- nationwide map --> P[all rows join their<br>own state's polygons<br>via map_id]
```

**The `county_state` data model (2026-11-18).** A resolved county always carries the state it belongs to in `county_state` (uppercase full name, matching the `apprehension_state` vocabulary):

- City-layer matches and manual overrides are in-frame by construction: `county_state` = report state.
- Landmark-engine results keep their **attributed** state: pattern rows with explicit states, ", XX" / "XX STATE" / "XX DOC" suffix markers, and documented out-of-state office-code entries all attribute to their true state. E.g. `EPC GENERAL AREA, NON-SPECIFIC` on a Minnesota report row → El Paso, **TEXAS**; `PRINCE GEORGE'S COUNTY MD` on a DC report row → Prince George's, **MARYLAND**.
- `county` is never discarded for being out-of-frame — only \~520 of 870k rows resolve out-of-frame today, but the nationwide county map gains all of them, keyed on `county_state` via `map_id` (`"texas,el paso"` style). Per-state reports filter `county_state == state` so their coverage denominators and choropleth polygons are unchanged; `build_state_arrests_data()` exposes out-of-frame rows separately as `out_of_frame`.

The landmark engine (`.parse_landmark_county_state()`) resolves in this order, first match wins:

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

Known limitation (unchanged by the refactor): a landmark with **no state marker at all** that names a same-named county in another state still validates in-state (`GREENE COUNTY JAIL` in a report for any state with a Greene County). Landmarks carrying state markers are safe: inline `XX DOC` state-corrections markers (`A - WI DOC - BROWN COUNTY JAIL` → Brown, **WI**) and all other suffix forms are detected by `.landmark_state_markers()` and take priority over the county search.

**Validation source (switched 2026-11-18):** `.validate_county()` now checks county names against the **Census cartographic-boundary county file** (`census_county_file` → `cb_2023_us_county_500k.zip`, read once per session and cached per state), not `maps::county.fips`. The maps table had no entries at all for Alaska, Hawaii, or Puerto Rico and still listed Connecticut's pre-2022 counties, so city-layer matches in CT/HI/AK/PR were nulled to NA after matching. Consequences of the switch:

- CT now validates against the 9 planning regions (Census county-equivalents since 2022); HI/AK/PR against boroughs and municipios. **Virginia independent cities** (Alexandria, Chesapeake, Richmond…) are Census county-equivalents too and were absent from the maps list — fixing them lifted VA coverage 62.9% → **77.2%**.
- Returned spellings are Census spellings ("DeWitt", "DuPage") where maps inserted spaces ("De Witt", "Du Page"). Joins that match county names to `maps` polygons normalize both sides: the nationwide `map_id` strips dots *and spaces* from the county part, and the per-state choropleths join on `.norm_county_key()`.
- Counties in geographies `maps::map("county")` doesn't polygon (CT planning regions, AK boroughs, HI/PR, VA independent cities) are attributed in the data but render transparent on the nationwide county map. Swapping the map polygons to a Census-sourced shapefile would light them up; not done yet.

## The two layers in detail

### City layer (Aug 2026 release)

The city field is entirely new in the 20260806 release: no prior DDP release carries arrest geography below the state/landmark level, and DDP describes the raw "Apprehension city" as ["the most specific ICE arrest location information that we have received to date"](https://deportationdata.org/news/2026-08-24-ICE-release.html). It is hand-entered — spelling and punctuation vary, it is sometimes missing (\~4% of observations since 2025, more before), and it does not always agree with the arrest state. The processed variant `apprehension_city_common_case`, added in DDP's [2026-09-08 update](https://deportationdata.org/news/2026-09-08-detainers-release.html), standardizes case and most punctuation (18,513 distinct values reduced to 11,263) but otherwise leaves spelling variations in place; we therefore match on a letters-only key and a reviewed typo table rather than exact strings.

1.  **`build_place_county()`** overlays each state's Census cartographic-boundary places on counties (EPSG:5070), keeps the county holding the largest share of each place's area, flags places where a second county holds ≥ 10% (`multi_county`), and keeps the incorporated place when two places share a name. Inputs are the zips in `data/census/`. **Since 2026-11 the crosswalk covers all 50 states + DC + PR**, so the city layer applies nationwide.
2.  **`clean_arrest_city()`** squishes whitespace, maps UNKNOWN variants to NA, and applies reviewed spelling fixes (`.city_fixes()` — \~90 Illinois typos, e.g. "Chcago" → "Chicago") and neighbourhood/abbreviation aliases (`.city_aliases()` — "Little Village" → Chicago).
3.  **`.county_from_city()`** looks the cleaned city up by a letters-only key (`.city_key()`: "Mt. Prospect" == "Mount Prospect") in the crosswalk. Unmatched cities (unreviewed typos, local names that aren't Census places) fall through to the landmark layer.

The city key is state-scoped, so a Texas city on a Tennessee report row never resolves to a Tennessee county — it simply fails and falls back to the landmark.

**Caveat: at-large arrests may locate the processing site, not the arrest.** Validation against the landmark field shows the city is genuine municipality-level arrest geography for the bulk of rows: within each "GENERAL AREA, NON-SPECIFIC" office code the reported cities number 34–297, the office's own city accounts for only 21–88%, and the remainder spreads plausibly across the office's area of operations; for landmarks naming a specific county jail, the modal city is that jail's town at \~100%. But for **at-large arrests the city can record the ICE processing point instead**: Broadview, IL — a village of \~8,000 hosting an ICE processing center — accounts for 4.9% of all Chicago-area general-area rows, and 63% of its rows are at-large; **Fort Snelling, MN** (a Census CDP at the MSP airport) is the top reported "city" for St. Paul general-area arrests (28%). County-level conclusions dominated by such sites should be read with that ambiguity in mind.

### Landmark layer

- **Per-state lookup tables** (`state_landmark_tables()`): general-area office codes (`mn_general_area_codes`, `tn_general_area_codes`), exact OTHER landmarks (`mn_other_landmarks`, `tn_other_landmarks`), and regex pattern tables (`mn_landmark_patterns`, `il_landmark_patterns`). Only codes/landmarks whose office actually sits in the report state get a county; out-of-state entries are kept for documentation — since the `county_state` refactor they attribute to their documented state rather than being discarded.
- **`il_landmark_patterns`** maps named facilities: THOMSON → Carroll, ILLINOIS RIVER CORRECTIONAL → Fulton, CHICAGO FIELD OFFICE/MCC/O'HARE → Cook. `CHI GENERAL AREA, NON-SPECIFIC` is deliberately **not** mapped to Cook: the city field shows those arrests are only \~52% Chicago.
- **Suffix-state detection** reads four forms — `, XX`, inline `XX STATE`/`XX STATE DOC`, a bare trailing `XX`, and a trailing full state name (`...MADISON COUNTY, MISSOURI`) — so out-of-state CAP-program jails never leak into the report state; they now keep their true state in `county_state`.
- **Validation** (`.validate_county()`): every generic "X COUNTY" parse must be a real county of the state it would be attributed to, with a small typo map (`.county_typos`: DEWIITT, GALATIN, PUTNAME). This is what fixed the "Cap-York" bug and stops IA/PA county jails from appearing on an Illinois map.

## Coverage (20260806 release, post-refactor rebuild 2026-11-18)

Share of each state's arrests (all rows, Oct 2022 – Aug 2026) with an assigned county (`county` non-NA, any state), split into city-layer vs landmark attributions, and the in-frame share (`county_state` = report state). The state fill chain (`apprehension_state_filled_in`, plus AOR/landmark-suffix fills of 2026-11) leaves 25,988 rows (2.9%) with no state; they cannot be mapped — see the note below the table.

| State | Arrests | County | City | Landmark | In-frame |
|---|---:|---:|---:|---:|---:|
| TEXAS | 226,307 | 94.2% | 84.9% | 9.3% | 94.2% |
| FLORIDA |  82,013 | 93.6% | 90.1% | 3.5% | 93.6% |
| CALIFORNIA |  75,975 | 84.5% | 79.9% | 4.6% | 84.4% |
| NEW YORK |  36,682 | 85.7% | 83.4% | 2.3% | 85.7% |
| NEW JERSEY |  33,941 | 82.2% | 75.5% | 6.7% | 82.2% |
| ARIZONA |  30,002 | 84.8% | 77.8% | 7.0% | 84.8% |
| GEORGIA |  28,262 | 93.3% | 91.8% | 1.5% | 93.3% |
| TENNESSEE |  22,304 | 95.8% | 74.0% | 21.8% | 95.4% |
| VIRGINIA |  20,780 | 77.2% | 75.2% | 2.0% | 77.1% |
| MASSACHUSETTS |  18,270 | 72.2% | 70.3% | 1.9% | 72.1% |
| PENNSYLVANIA |  17,865 | 83.4% | 81.5% | 1.8% | 83.4% |
| ALABAMA |  15,582 | 92.4% | 90.1% | 2.3% | 92.4% |
| LOUISIANA |  15,520 | 93.2% | 90.6% | 2.6% | 93.1% |
| COLORADO |  15,354 | 75.0% | 71.1% | 3.9% | 75.0% |
| NORTH CAROLINA |  14,512 | 96.8% | 93.7% | 3.1% | 96.8% |
| OKLAHOMA |  14,463 | 94.0% | 90.4% | 3.6% | 94.0% |
| ILLINOIS |  13,081 | 95.0% | 94.1% | 0.9% | 94.9% |
| INDIANA |  12,903 | 79.8% | 55.1% | 24.8% | 79.5% |
| MARYLAND |  12,879 | 94.9% | 92.3% | 2.6% | 94.9% |
| SOUTH CAROLINA |  11,670 | 97.1% | 89.0% | 8.1% | 97.1% |
| UTAH |  11,335 | 89.3% | 81.4% | 8.0% | 89.2% |
| WASHINGTON |  11,143 | 89.3% | 89.2% | 0.1% | 89.3% |
| OHIO |  10,689 | 91.3% | 91.0% | 0.3% | 91.3% |
| MINNESOTA |   9,950 | 96.7% | 70.3% | 26.3% | 95.9% |
| ARKANSAS |   9,303 | 96.9% | 92.6% | 4.3% | 96.9% |
| MICHIGAN |   8,969 | 93.9% | 92.8% | 1.2% | 93.9% |
| KENTUCKY |   8,478 | 95.0% | 82.8% | 12.3% | 94.8% |
| MISSISSIPPI |   8,388 | 97.4% | 95.6% | 1.8% | 97.4% |
| MISSOURI |   8,027 | 92.0% | 89.3% | 2.7% | 91.9% |
| NEVADA |   6,940 | 92.6% | 87.3% | 5.3% | 92.6% |
| NEW MEXICO |   6,931 | 98.5% | 94.0% | 4.5% | 98.3% |
| KANSAS |   5,387 | 96.2% | 92.5% | 3.7% | 96.2% |
| WISCONSIN |   5,130 | 98.6% | 98.0% | 0.6% | 98.5% |
| NEBRASKA |   5,091 | 95.1% | 93.8% | 1.3% | 94.9% |
| IOWA |   4,362 | 89.7% | 84.3% | 5.4% | 89.2% |
| IDAHO |   4,292 | 59.4% | 46.9% | 12.5% | 59.4% |
| WEST VIRGINIA |   3,568 | 93.2% | 91.0% | 2.2% | 93.2% |
| OREGON |   3,453 | 80.2% | 80.1% | 0.0% | 80.1% |
| WYOMING |   2,276 | 93.8% | 91.0% | 2.8% | 93.8% |
| PUERTO RICO |   2,144 | 86.6% | 86.6% | 0.0% | 86.6% |
| CONNECTICUT |   2,137 | 78.5% | 78.4% | 0.0% | 78.4% |
| SOUTH DAKOTA |   2,059 | 93.2% | 52.6% | 40.6% | 93.0% |
| DISTRICT OF COLUMBIA |   2,051 | 0.1% | 0.0% | 0.1% | 0.0% |
| MAINE |   1,913 | 41.4% | 41.3% | 0.1% | 41.4% |
| DELAWARE |   1,650 | 96.4% | 96.4% | 0.0% | 96.4% |
| RHODE ISLAND |   1,629 | 92.3% | 92.3% | 0.0% | 92.3% |
| NEW HAMPSHIRE |   1,221 | 92.5% | 76.2% | 16.4% | 92.5% |
| NORTH DAKOTA |     856 | 96.1% | 79.4% | 16.7% | 95.9% |
| MONTANA |     627 | 87.7% | 67.5% | 20.3% | 87.6% |
| HAWAII |     589 | 31.9% | 31.9% | 0.0% | 31.9% |
| VIRGIN ISLANDS |     367 | 0.0% | 0.0% | 0.0% | 0.0% |
| ALASKA |     283 | 95.4% | 95.1% | 0.4% | 95.1% |
| VERMONT |     243 | 89.3% | 89.3% | 0.0% | 89.3% |
| NORTHERN MARIANA ISLANDS |     217 | 0.0% | 0.0% | 0.0% | 0.0% |
| ARMED FORCES - THE AMERICAS |     168 | 7.7% | 0.0% | 7.7% | 0.0% |
| GUAM |     135 | 1.5% | 0.0% | 1.5% | 0.0% |
| FEDERATED STATES OF MICRONESIA |      23 | 13.0% | 0.0% | 13.0% | 0.0% |
| ARMED SERVICES - PACIFIC |       5 | 0.0% | 0.0% | 0.0% | 0.0% |
| ARMED FORCES - EUROPE |       4 | 0.0% | 0.0% | 0.0% | 0.0% |
| OTHER |       3 | 0.0% | 0.0% | 0.0% | 0.0% |
| CHIAPAS |       2 | 50.0% | 0.0% | 50.0% | 0.0% |
| MEXICO |       1 | 0.0% | 0.0% | 0.0% | 0.0% |
| TAMAULIPAS |       1 | 0.0% | 0.0% | 0.0% | 0.0% |

NATIONWIDE: **89.7% of state-tagged arrests have a county** (781,130 of 870,405), 99.9% of them in-frame; the out-of-frame remainder plots in its true state on the nationwide map.

Unassigned reasons (89,275 rows with a state, after the Census county-list switch):

| Reason | Rows | Share | Fix path |
|---|---:|---:|---|
| City not found in state | 37,283 | 41.8% | per-state city typo review → `.city_fixes()` / `.city_aliases()` (largest: NY 4,697 · NJ 4,524 · CA 3,723 · MA 3,608 · VA 3,566 · TX 2,156) |
| Field office area, non-specific | 18,225 | 20.4% | general-area office-code tables (per-state entries; the short-circuit bug is fixed) |
| Other / unresolved | 14,497 | 16.2% | landmark audits (OTHER exact matches, pattern tables) |
| No city or landmark | 9,841 | 11.0% | — |
| Out-of-state landmark, county unresolved | 6,661 | 7.5% | state marker present, county not resolvable |
| Validation drop, no reason recorded | 1,695 | 1.9% | matched county failed the nationwide re-validation |
| Fugitive operations, no county | 828 | 0.9% | statewide-program convention (leave NA) |
| Missing landmark | 245 | 0.3% | — |
| (no state) | 25,988 | — | state fill chain; see below |

The no-state block thins sharply over time and has almost no city data (0.6% filled). The project-level state fill (2026-11) recovered 12,470 of the original 43,431 NA rows — mostly landmark-conditional fills (DAL COUNTY JAIL → Texas, NSV = Nashville → Tennessee, DENVER, CO → Colorado), AOR-based fills for the nine unambiguous AORs, and a ", XX" suffix rule. The remaining 25,988 rows are mostly rows with no landmark at all (23,285) or generic office-area codes whose known-state rows never reach 95% dominance; 31 more are assigned by the curated `nationwide_landmark_states()` table for the nationwide report only.

## Engine fixes (verified and implemented 2026-11-18 unless noted)

Each fix was confirmed by direct `.parse_landmark_county_state()` tests before and after implementation. **Note the shrinkage from the first estimates: the nationwide city layer (all 50 states + DC + PR since 2026-11-07) already resolves most rows these fixes target, so the residual counts are the true upside.**

| Fix | Example landmark | Root cause | Resolution |
|---|---|---|---|
| 1. `{NAME} COUNTY GENERAL AREA` — **FIXED** | `DALLAS COUNTY GENERAL AREA` (4,432 TX); `LOS ANGELES COUNTY GENERAL AREA, NON-SPECIFIC` (3,045 CA); 29 more variants, 7,580 rows | `.county_text_extraction()` extracts the county name fine ("Dallas", and "Ada" validates in ID), but the `case_when`'s `GENERAL AREA` branch (`~ ga_county`, NA for states without tables) fired **before** the validated generic-parse branch and zeroed it | The GENERAL AREA branch now fires only when the state's ga table matched (`!is.na(ga_county)`); validated `{name} COUNTY` results fall through. **~6,700 rows recovered; residual is ~70 rows in non-report-state frames** |
| 2. Abbreviated county names — **FIXED for DAL** | `DAL COUNTY JAIL` (1,610 rows; 1,067 TX unmapped) | Extraction yields "Dal"; `.validate_county()` correctly rejected non-county strings | `.county_abbrevs` map (`DAL`→Dallas, `YRK`→York) expanded inside `.validate_county()`. All 1,067 unmapped TX rows now attribute **Dallas** (county_source = Landmark; verified). The fuller enumeration confirmed the category is small: most `X COUNTY` failures are no-state rows or cross-state same-name cases (CLARK→Clarke GA spelling; WAKE on MA/AZ; PAGE on AZ) |
| 3. Louisiana parishes — **FIXED** | `JEFFERSON PARISH, LA`; `ORLEANS PARISH, LA`; `ST. CHARLES PARISH, LA` | The generic parse matched only `X COUNTY` | `.county_text_extraction()` accepts `X PARISH`; validated against the Census parish names. 4,610 LA parish rows resolved; LA coverage 90.8% → **93.2%**. (PR `X MUNICIPIO` remains open but tiny) |
| 4. `X CO` endings — **FIXED** | `TEXAS DEPT OF CRIMINAL JUSTICE, WALKER CO` (1,618 TX); `W DIST OK OKLAHOMA CITY DIV BECKHAM CO NON CRIM` (210 OK); 2,102 rows total | The trailing `CO` is a county abbreviation misread as a **Colorado state marker** by the bare-trailing-`XX` rule (`WALKER CO`, `MINNEHAHA CO`…). Enumeration: **2,065 of 2,102 (98%) match a county of the report state** (Walker TX 1,619; Minnehaha SD 126; Brazoria TX 77; Lubbock TX 34…) | `.co_county_token()` resolves a word-boundary `X CO` (two-word candidates first, typos/abbrevs expanded) against the report state, then an explicit comma-suffix state; when it hits, the bare trailing-CO marker is suppressed in both the engine and `.landmark_suffix_state()`. `, CO` and `CO STATE`/`CO DOC` forms are never swallowed. **Residual after fix: 34 rows (28 no-state, cross-state names, typos SIMTH/RANDELL)** |
| 5. `.state_county_names()` source — **FIXED** | All city matches in CT/HI/AK/PR; VA independent cities | `maps::county.fips` lacks AK/HI/PR, lists CT's pre-2022 counties, and omits VA independent cities | `.state_county_names()` now reads the Census county shapefile (`census_county_file`), cached per state; spellings are Census style, so polygon joins normalize both sides. Nationwide coverage 88.5% → **89.7%**; CT 0.1% → 78.5%, PR 0% → 86.6%, AK 0.4% → 95.4%, HI 0% → 31.9%, VA 62.9% → 77.2% |

### HAR GENERAL AREA — national check (2026-11-18)

`HAR` is **not one facility**; a national mapping to Hartford, CT would be wrong. By report state (730 rows total):

| Report state | Rows | City-field evidence | Reading |
|---|---:|---|---|
| CONNECTICUT | 554 | Hartford 230, Danbury 30, Bridgeport 28, Waterbury 28, Stamford 22, New Haven 16 — all CT | **Hartford office** — supported |
| NEW YORK | 143 | Jamaica 124 + typos, Queens 9 — ~95% Jamaica, Queens | **Not Hartford** — an office in Jamaica, Queens (identity needs research) |
| MASSACHUSETTS | 19 | East Boston 7, Boston 3, Springfield 2, Milford 2 — spread | Ambiguous — needs research |
| TEXAS | 11 | Harlingen 7, Brownsville 2, Olmito, Mercedez | **Harlingen office** (Rio Grande Valley) |
| FL / NJ / VA | 3 | scattered | incidental |

The city layer already resolves most HAR rows via their city values, so the landmark entries matter only for the residual; add CT→Hartford (Hartford County) and TX→Harlingen (Cameron County) as state-scoped ga_code rows, keep NY/MA as research questions.

## Where to add new entries

### New general-area office code ("XXX GENERAL AREA, NON-SPECIFIC" unassigned)

Add a row to the state's tribble in `R/state-arrests.R` (`tn_general_area_codes`, `mn_general_area_codes`). Only add the county if the office physically sits in the report state; otherwise record the office with its actual state — since the `county_state` refactor, documented out-of-state entries attribute correctly (and plot on the nationwide map in that state), so exact strings still matter.

``` r
"FNV", "Farmington, NM Sub Office", "San Juan", "NM"
```

### New named facility with no county in its name

Add a row to the state's OTHER exact-match table (`tn_other_landmarks`, `mn_other_landmarks`) — full landmark string, uppercase, exactly as it appears in the data — or, if it generalizes (e.g. all CAP sites in a city), a regex row in the state's pattern table (`mn_landmark_patterns`, `il_landmark_patterns`). Pattern rows are first-match-wins in table order, so put more specific patterns (e.g. MSP airport before the generic "ST. PAUL" rule) first.

### A landmark that the engine gets wrong

Add an entry to `.landmark_county_overrides()` — a manual audit table checked before everything else, keyed by `(state, landmark, county)`. County spelling is normalized, so "St Clair", "St. Clair" and "Dupage" all work.

### RA-verified landmark matches (audit CSV)

Research assistants record verified landmark matches in `data/state-arrests/landmark-audit.csv`; **no R code changes are needed**. The `landmark_audit_file`/`landmark_audit` targets track the file by content hash, and `assign_arrest_location()` merges verified entries into the engine at build time — editing the CSV and re-running `tar_make()` is the whole workflow. The CSV is seeded with the 128 Phase-2 proposals from the [rollout-plan comment](https://github.com/CarwilB/ice-detention/issues/16#issuecomment-6983591229) plus the HAR and CAP-YRK ga_code proposals from the national check below (133 rows), each with `status = "proposed"`; the pipeline ignores every row until an RA flips it to `verified`.

Columns: `state` (report state, uppercase full name), `landmark` (full landmark string exactly as in the data for `exact`; the office code alone, e.g. `MTG`, for `ga_code`; ignored for `pattern`), `record_type` (`exact` = case-insensitive full-string match via the override path, checked before the engine; `ga_code` = appended to the state's general-area code table; `pattern` = regex in the `pattern` column, appended after hand-maintained patterns), `county`, `pattern`, `attributed_state` (2-letter abbr; blank = report state — use this for documented out-of-state offices), `status` (`proposed` | `verified` | `rejected`), `verified_by`, `verified_date`, `notes` (verification evidence, decisions, research questions).

Rules for `status`:

- `proposed` — not yet checked; ignored by the pipeline.
- `verified` — the RA completed the four-step checklist (city-field evidence agrees · web-check of the facility/office location · county spelling matches the county list · right `record_type` chosen) and recorded name/date.
- `rejected` — the proposal was wrong (e.g. `DO NOT USE` labels that are real but unmappable, or county checks failing); `notes` records why. Rejected rows are also ignored, and prevent re-proposing the same match.

Rows with a county of NA (`RESEARCH` / `DECISION` rows in the seed) stay `proposed` until the open question is resolved — they are prompts, not matches.

### A misspelled arrest city (city layer)

First check whether it's a Saint/Mount/Fort variant — `.city_key()` already handles those. Otherwise add `variant -> city` to `.city_fixes()` with the state column, and `.city_aliases()` if the name isn't a Census place at all.

### A county-name typo in landmarks

Add it to `.county_typos` (letters-only key → correct letters-only key), e.g. `PUTNAME = "PUTNAM"`.

### A new state

The Census place crosswalk now covers all states; onboarding a state now means:

1.  Review that state's city typos with the stringdist approach in the branch's `il-location-exploration.R` and add them to `.city_fixes()`.
2.  Audit the state's top landmarks (the branch's audit workflow writes `data/il-landmark-audit/`-style tables) and add general-area codes, OTHER landmarks, or a pattern table under `state_landmark_tables()`.
3.  Render: `quarto render state-arrests.qmd -P state:STATENAME`, or add a `tar_quarto` target with a distinct `output_file`.

### Extending the pipeline after a new DDP release

Arrests and stays must come from the same release (`unique_identifier` is hashed per release). Repoint `arrests_file`/`stays_file` in `_targets.R` to the pinned parquet; `place_county` and the reports rebuild automatically.
