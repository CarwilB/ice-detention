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
    F --> IKnown limitation: a landmark with **no state marker at all** that names a same-named county in another state still validates in-state (`GREENE COUNTY JAIL` in a report for any state with a Greene County). Landmarks carrying state markers are safe, though: inline `XX DOC` state-corrections markers (`A - WI DOC - BROWN COUNTY JAIL` → Brown, **WI**) and all other suffix forms (`XX STATE`, bare trailing `XX`, `, FULL STATE NAME`) are detected by `.landmark_state_markers()` and take priority over the county search; 541 such landmarks exist in the 20260806 release (FL 342, WI 153, VA, WV, AZ, IN, PA).
```

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
