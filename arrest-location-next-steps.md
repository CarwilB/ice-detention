# Recommended next steps: nationwide county attribution rollout

Companion to the discussion body above ("Assigning counties to arrest data for visualization") and [issue 13](https://github.com/CarwilB/ice-detention/issues/13). Numbers below are computed from `nationwide_arrests_located` (20260806 release, 896,393 rows) on 2026-11-18. **Every proposed landmark→county match below needs human verification before it enters `R/state-arrests.R`** — the city-field evidence column is provided as the first check, not the last.

## Current coverage snapshot

| State | Arrests | Mapped | Pct | Unmapped | Unmapped with city filled |
|---|---:|---:|---:|---:|---:|
| TEXAS | 226,307 | 75,200 | 33.2% | 151,107 | 133,052 (88%) |
| CALIFORNIA | 75,975 | 1,871 | 2.5% | 74,104 | 63,655 (86%) |
| FLORIDA | 82,013 | 22,384 | 27.3% | 59,629 | 56,023 (94%) |
| NEW YORK | 36,682 | 5,150 | 14.0% | 31,532 | 30,966 (98%) |
| NEW JERSEY | 33,941 | 5,458 | 16.1% | 28,483 | 26,961 (95%) |
| ARIZONA | 30,002 | 6,664 | 22.2% | 23,338 | 19,018 (81%) |
| GEORGIA | 28,262 | 6,594 | 23.3% | 21,668 | 20,520 (95%) |
| VIRGINIA | 20,780 | 1,589 | 7.6% | 19,191 | 18,011 (94%) |
| MASSACHUSETTS | 18,270 | 534 | 2.9% | 17,736 | 16,266 (92%) |
| LOUISIANA | 15,520 | 3 | ~0% | 15,517 | 14,940 (96%) |
| PENNSYLVANIA | 17,865 | 3,088 | 17.3% | 14,777 | 13,400 (91%) |
| ALABAMA | 15,582 | 3,496 | 22.4% | 12,086 | 11,216 (93%) |
| OKLAHOMA | 14,463 | 2,696 | 18.6% | 11,767 | 11,161 (95%) |
| WASHINGTON | 11,143 | 15 | 0.1% | 11,128 | 10,068 (90%) |

Key structural finding: **the top 20 unassigned landmarks cover 77–97% of unmapped landmark rows in every state** (TX 84%, CA 77%, FL 92%, NY 97%, NJ 83%, VA 92%, LA 84%, MA 95%, PA 91%, AL 97%, OK 96%). A 20–40 landmark audit per state captures most of the gain.

## Phase 0 — generic engine fixes (no per-state tables, ~37k+ rows)

Verified gaps in the landmark engine, each confirmed by direct `.parse_landmark_county_state()` tests on 2026-11-18. Fix in `R/state-arrests.R`, then re-run coverage.

| Fix | Example landmark (unmapped rows) | Root cause | Proposed fix |
|---|---|---|---|
| 1. `{NAME} COUNTY GENERAL AREA` | `LOS ANGELES COUNTY GENERAL AREA, NON-SPECIFIC` (12,125 CA); `DALLAS COUNTY GENERAL AREA` (24,394 TX) | `.county_text_extraction()` peels `COUNTY GENERAL AREA, NON-SPECIFIC` as a program phrase, leaving bare "Los Angeles"; generic X-COUNTY parse then has no "COUNTY" token | Recognize `{name} COUNTY GENERAL AREA` as county + office-county before peeling, or treat "GENERAL AREA" phrases as peelable suffix while keeping `X COUNTY` intact. **~37,200 rows** |
| 2. Abbreviated county names | `DAL COUNTY JAIL` (1,602 TX); `CAP-YRK GENERAL AREA, NON-SPECIFIC PA STATE` (1,422 PA) | Extraction yields "Dal"/"Yrk"; `.validate_county()` correctly rejects non-county strings | County-abbreviation map (`DAL`→Dallas, `YRK`→York, …) or require full county names with per-state abbreviation tables |
| 3. Louisiana parishes | `JEFFERSON PARISH, LA` (1,223 LA); `ORLEANS PARISH, LA` (441); `ST. TAMMANY PARISH, LA` (384) | Generic parse matches only `X COUNTY`; state suffix `, LA` is detected but no parish rule fires | Extend generic parse to `X PARISH` (LA) and `X MUNICIPIO` (PR); confirm keys match `maps::county.fips` parish spellings via `.county_key()` |
| 4. `X CO` federal-district landmarks | `W DIST OK OKLAHOMA CITY DIV BECKHAM CO NON CRIM` (210); `... CUSTER CO ...` (132); `E DIST OK MUSKOGEE DIV SEQUOYAH CO NON CRIM` (82) | Generic parse doesn't accept the `CO` abbreviation | Accept `X CO` in the generic parse (validated against the state's county list, same as `X COUNTY`) |

## Phase 1 — city-layer onboarding (cheapest large gain per state)

Per state: (1) download `cb_2023_SS_place_500k.zip` into `data/census/` (auto-picked up by `census_place_files`); (2) review city typos with the stringdist approach from the branch's `il-location-exploration.R` → `.city_fixes()` / `.city_aliases()`; (3) re-run and add the coverage row to `state-arrests-locations.md`.

Recommended order (volume × city-fill rate × compactness):

1. **NEW YORK** — city filled on 98.4% of arrests; `ATD NY STATE` / `FUGITIVE OPERATIONS NY STATE` (3,199 rows) are statewide-program landmarks that will resolve **via the city field** rather than the landmark engine.
2. **NEW JERSEY** — 90% city fill, ~1,200 Census places.
3. **GEORGIA** — 94.7% city fill.
4. **FLORIDA** — 92.3% city fill; top 9 cities cover ~89% of unmapped rows.
5. **VIRGINIA, MASSACHUSETTS** — 93–98% city fill; MA's statewide-program rows also resolve via city.
6. **TEXAS, CALIFORNIA** — largest absolute gains but heaviest typo review (large, multi-office states). Read the processing-point caveat on Border-Patrol-heavy rows before publishing county maps.
7. **ARIZONA** (78.7% city fill; BP-dominated — same caveat).

## Phase 2 — landmark audits with verification (proposals below)

### Verification checklist (for each row)

1. **City-field evidence agrees** — the modal `apprehension_city_common_case` among that landmark's rows should match the proposed county.
2. **Web check** — the ERO sub-office / facility is physically in the proposed county (use `data/ero-field-offices-canonical.csv` for the 25 field offices; e.g. "DUTY WINDOW 126 NORTHPOINT" = Houston FO, 126 Northpoint Drive, Houston = Harris County).
3. **County spelling** matches `maps::county.fips` (via `.county_key()`); add typos to `.county_typos`.
4. **Record the confirmed match** in the right table: general-area code table (`XXX GENERAL AREA, NON-SPECIFIC`), OTHER exact-match table (named facility), pattern table (generalizable regex), or `.landmark_county_overrides()` (engine gets it wrong). Then tick the box in this issue.

### NEW YORK (24,377 unmapped landmark rows; top 15 = 97%)

| Landmark | Rows | Proposed county | City-field evidence | Status |
|---|---:|---|---|---|
| NDD - 26 FEDERAL PLAZA NY, NY | 14,069 | New York | New York ~100% | high confidence; NYC FO at 26 Federal Plaza (Manhattan) |
| CIP GENERAL AREA, NON-SPECIFIC | 3,655 | Suffolk | Central Islip ~99% | high confidence (sub-office in Central Islip) |
| ATD NY STATE | 1,703 | *(leave NA)* | spread, NYC-heavy | statewide program — city layer handles |
| FUGITIVE OPERATIONS NY STATE (+ `NY State` variant, 1,914 total) | 1,687 | *(leave NA)* | spread | statewide program — city layer handles |
| NBG GENERAL AREA, NON-SPECIFIC | 884 | Rockland | Spring Valley | verify: Nanuet/Spring Valley sub-office, Rockland County |
| CHAMPLAIN POE | 258 | Clinton | Champlain | high confidence (port of entry) |
| WENDE CORRECTIONAL FACILITY | 202 | Erie | Alden 88% | high confidence (Alden, Erie County) |
| FEDERAL CORRECTIONAL INSTITUTE RAY BROOK | 201 | Franklin | Ray Brook | high confidence |
| CAP - BOP BROOKLYN NY STATE | 190 | Kings | Brooklyn | high confidence (suffix `NY STATE` detected) |
| HAR GENERAL AREA, NON-SPECIFIC | 143 | Queens? | Jamaica 8x% | **verify** — which office is HAR? (Jamaica, Queens?) |
| CAP - OTISVILLE FEDERAL CORRECTIONAL FACILITY NY STATE | 88 | Orange | Otisville | high confidence |
| CHM GENERAL AREA, NON-SPECIFIC | 78 | Clinton | Champlain | verify = Champlain sub-office |
| SYR GENERAL AREA, NON-SPECIFIC | 75 | Onondaga | Syracuse | verify = Syracuse sub-office |
| BUFFALO GENERAL - Do Not Use | 86 | Erie | Buffalo 5x% | "Do Not Use" label — confirm rows are still real arrests |

### NEW JERSEY (25,933 unmapped landmark rows; top 15 = 83%)

| Landmark | Rows | Proposed county | City-field evidence | Status |
|---|---:|---|---|---|
| ICE ERO NEWARK | 12,936 | Essex | Newark 91% | high confidence (Newark FO, 970 Broad St) |
| ICE ERO MOUNT LAUREL | 2,466 | Burlington | Mount Laurel 39% | high confidence |
| NEWARK PD | 923 | Essex | Newark 92% | high confidence |
| NEW GENERAL AREA, NON-SPECIFIC | 849 | Essex | Newark 35% | verify = Newark office code |
| FORT DIX EAST, NEW JERSEY | 702 | Burlington | Fort Dix / Joint Base MDL | high confidence |
| ELIZABETH PD | 701 | Union | Elizabeth 84% | high confidence |
| MLN GENERAL AREA, NON-SPECIFIC | 406 | Burlington | Mount Laurel 27% | verify = Mount Laurel code |
| PLAINFIELD PD | 392 | Union | Plainfield 91% | high confidence |
| FORT DIX WEST, NEW JERSEY | 295 | Burlington | Joint Base MDL 37% | high confidence |
| NORTH BERGEN PD | 251 | Hudson | North Bergen 88% | high confidence |
| FAIRVIEW PD | 210 | Bergen | Fairview 92% | verify: Fairview NJ is Bergen County |
| S.C.I SOUTHWOODS, NEW JERSEY | 195 | Cumberland | Bridgeton 57% | high confidence (Southwoods, Bridgeton) |
| TRENTON CITY POLICE DEPARTMENT | 192 | Mercer | Trenton 93% | high confidence |
| PASSAIC PD | 175 | Passaic | Passaic 91% | high confidence |
| PALISADES PARK PD | 160 | Bergen | Palisades Park 88% | high confidence |

### GEORGIA (12,267 unmapped landmark rows; top 15 = 87%)

| Landmark | Rows | Proposed county | City-field evidence | Status |
|---|---:|---|---|---|
| ATLANTA, GA | 4,624 | Fulton | Atlanta 58% | city landmark — city layer handles; pattern fallback to Fulton |
| STG GENERAL AREA, NON-SPECIFIC | 1,168 | Stewart | Lumpkin 46% | verify: STG = Stewart County (Stewart Detention Center, Lumpkin) |
| DTN GENERAL AREA, NON-SPECIFIC | 814 | Whitfield | Dalton 97% | high confidence |
| SAV GENERAL AREA, NON-SPECIFIC | 814 | Chatham | Savannah 50% | verify (Savannah office) |
| GNS GENERAL AREA, NON-SPECIFIC | 716 | Hall | Gainesville 97% | high confidence |
| FOK GENERAL AREA, NON-SPECIFIC | 404 | Charlton? | Ellabell 38% / Folkston 25% | **verify** — Folkston office (Charlton) vs Ellabell (Bryan, new facility); city split suggests the code spans both |
| USP ATLANTA, ATLANTA, GA | 337 | Fulton | Atlanta 93% | high confidence |
| FCI JESUP, GA | 263 | Wayne | Jesup 97% | high confidence |
| GDC GENERAL AREA, NON-SPECIFIC | 246 | Butts? | Jackson 38% | verify (Jackson = Butts County) |
| FCS GENERAL AREA, NON-SPECIFIC | 236 | Floyd | Rome 94% | high confidence |
| NORCROSS / MARIETTA / LAWRENCEVILLE / JONESBORO, GA | 575 | — | match themselves | city layer handles |

### LOUISIANA (13,487 unmapped landmark rows; top 15 = 84%)

Parish caution: county values must be parish names that validate against `maps::county.fips` (Phase 0 fix #3 first).

| Landmark | Rows | Proposed parish | City-field evidence | Status |
|---|---:|---|---|---|
| NOL GENERAL AREA, NON-SPECIFIC | 1,420 | St. Charles vs Orleans — **decision** | New Orleans 54% | New Orleans FO physically sits in St. Rose, **St. Charles Parish**; TN precedent maps general-area codes to the office's county. Decide which convention applies |
| ASF GENERAL AREA, NON-SPECIFIC | 1,238 | Rapides | Alexandria 31% | verify = Alexandria sub-office |
| JEFFERSON PARISH, LA | 1,223 | Jefferson | Gretna 68% | Phase 0 fix #3 (parish parse) |
| FEDERAL CORRECTIONAL INSTITUTE - OAKDALE | 887 | Allen | Oakdale 96% | high confidence |
| BTN GENERAL AREA, NON-SPECIFIC | 770 | East Baton Rouge | Baton Rouge 51% | verify = Baton Rouge office |
| KENNER, LA | 614 | Jefferson | Kenner 96% | high confidence |
| LAF GENERAL AREA, NON-SPECIFIC | 605 | Lafayette | Lafayette 49% | verify |
| FCI Pollock | 521 | Grant | Pollock 94% | high confidence |
| ST. CHARLES PARISH, LA / ORLEANS PARISH, LA / ST. TAMMANY PARISH, LA | 1,344 | same-named parish | match themselves | Phase 0 fix #3 |
| VVS GENERAL AREA, NON-SPECIFIC | 470 | Bossier | Bossier City 50% | verify = Bossier City sub-office |
| JNA GENERAL AREA, NON-SPECIFIC | 462 | LaSalle | Jena 24% | verify (Jena = LaSalle Parish) |
| OAK GENERAL AREA, NON-SPECIFIC | 340 | Allen | Oakdale 58% | verify |
| FEDERAL DETENTION CENTER - OAKDALE | 322 | Allen | Oakdale 88% | high confidence |

### WASHINGTON (8,460 unmapped landmark rows; top 15 = ~90%)

| Landmark | Rows | Proposed county | City-field evidence | Status |
|---|---:|---|---|---|
| SEATTLE NON-DETAINED DOCKET | 2,929 | King | Tukwila 44% | high confidence (Seattle FO is in Tukwila, King County) |
| SEATTLE FUG OPS | 1,165 | King | Seattle/Kent spread | verify — fug-ops rows are at-large; consider office-county convention |
| YAKIMA NON DETAINED DOCKET / YAKIMA Fug Ops | 1,172 | Yakima | Yakima 69–83% | high confidence |
| Spokane CAP | 669 | Spokane | Spokane 59% | high confidence |
| FEDERAL DETENTION CENTER (FDC) | 598 | King | Seatac 70% | verify: SEA FDC at SeaTac |
| TAC GENERAL AREA, NON-SPECIFIC | 446 | Pierce | Tacoma 60% | verify = Tacoma sub-office |
| FDL GENERAL AREA, NON-SPECIFIC | 342 | Whatcom | Bellingham 24% | verify = Ferndale/Bellingham sub-office |
| SEA CAP | 222 | King | Seattle/SeaTac | high confidence |
| PORTLAND FUGITIVE OPERATIONS STREET ARREST | 125 | Clark? | Vancouver 60% | **decision** — landmark says Portland, OR but report state is WA; office is Portland FO. Attribute to Vancouver/Clark (city evidence), leave NA, or exclude |
| Richland CAP | 100 | Benton | Richland 52% | high confidence |
| WASHINGTON CORRECTIONS CENTER (Shelton) | 99 | Mason | Shelton 41% | high confidence |
| COYOTE RIDGE CORRECTIONS | 77 | Franklin | Connell 57% | high confidence |
| Wenatchee CAP | 67 | Chelan | Wenatchee 99% | high confidence |

### MASSACHUSETTS (13,069 unmapped landmark rows; top 20 = 95%)

Mostly statewide program landmarks — deliberately NA; the city layer resolves them.

| Landmark | Rows | Proposed county | City-field evidence | Status |
|---|---:|---|---|---|
| FUGITIVE OPERATIONS MA | 5,019 | *(leave NA)* | spread (Lynn 5%…) | statewide program |
| NON-DETAINED AND JUVENILE | 4,642 | *(leave NA)* | spread | statewide program |
| ATD MA STATE | 1,748 | *(leave NA)* | spread | statewide program |
| US DISTRICT COURT | 174 | Suffolk | Boston 81% | verify convention (court = Suffolk) |
| MDM GENERAL AREA, NON-SPECIFIC | 165 | Middlesex? | Shirley | verify (Shirley = Middlesex) |
| FEDERAL MEDICAL CENTER-DEVENS | 157 | Middlesex/Worcester | Devens 60% | **multi-county**: Devens spans both; decide primary |
| BOS GENERAL AREA, NON-SPECIFIC | 82 | Middlesex | Plymouth?? | **verify** — BOS = Boston FO (Burlington, Middlesex); odd city evidence |
| {CITY} DISTRICT COURT landmarks | ~300 | court's county | match themselves | pattern table row (court → county), or city layer |

### ALABAMA (10,475 unmapped landmark rows; top 10 = 97%)

| Landmark | Rows | Proposed county | City-field evidence | Status |
|---|---:|---|---|---|
| ETW GENERAL AREA, NON-SPECIFIC | 3,049 | **needs research** | Albertville 12% / Huntsville… spread | which office is ETW? |
| Mobile, AL General Non-specific AOR | 2,318 | Mobile | Mobile 14%, spread | verify convention |
| BHM GENERAL AREA, NON-SPECIFIC | 1,669 | Jefferson | Birmingham 47% | verify = Birmingham office |
| MGA GENERAL AREA, NON-SPECIFIC | 1,409 | Montgomery | Montgomery 19% | verify |
| FUGITIVE OPERATIONS, AL STATE | 476 | *(leave NA)* | spread | statewide program |
| FOLEY PD, AL | 170 | Baldwin | Foley 64% | high confidence |
| Aliceville FCI | 141 | Pickens | Aliceville 88% | high confidence |
| MOBILE METRO JAIL, AL | 136 | Mobile | Mobile 75% | high confidence |
| CAP - ALBERTVILLE CITY JAIL, AL STATE | 130 | Marshall | Albertville 92% | high confidence |
| CAP - MONTGOMERY CITY JAIL, AL STATE | 100 | Montgomery | Montgomery 84% | high confidence |

### PENNSYLVANIA (12,038 unmapped landmark rows; top 10 = 91%)

| Landmark | Rows | Proposed county | City-field evidence | Status |
|---|---:|---|---|---|
| PHI GENERAL AREA, NON-SPECIFIC | 3,021 | Philadelphia | Philadelphia 60% | high confidence |
| CAP-YRK GENERAL AREA, NON-SPECIFIC PA STATE | 1,422 | York | York 70% | Phase 0 fix #2 (CAP-YRK) + verify |
| PIT GENERAL AREA, NON-SPECIFIC | 1,370 | Allegheny | Pittsburgh 23% | verify |
| PHI AOR FUGITIVE OPERATIONS / FUG / AT-LARGE IN PHILADELPHIA, PA | 1,754 | Philadelphia | Philadelphia 79% | verify: Philadelphia-only fug ops can map; AOR-wide should be NA |
| WPO GENERAL AREA, NON-SPECIFIC | 666 | Lycoming | Williamsport 12% | verify = Williamsport sub-office |
| PITTSBURGH STREET ARREST | 532 | Allegheny | Pittsburgh 39% | high confidence |
| PKE GENERAL AREA, NON-SPECIFIC | 393 | **needs research** | Scranton 18% | which office is PKE? (Pittston?) |
| Allenwood Low | 328 | Union | Allenwood 42% | verify (FCI Allenwood, Union County) |
| PKE AOR FUGITIVE OPERATIONS | 226 | Allentown? | Allentown 38% | needs research + fug-ops convention |

### OKLAHOMA (8,983 unmapped landmark rows; top 10 = 96%)

| Landmark | Rows | Proposed county | City-field evidence | Status |
|---|---:|---|---|---|
| TLS GENERAL AREA, NON-SPECIFIC | 3,300 | Tulsa | Tulsa 73% | verify = Tulsa office |
| OKLAHOMA CITY ICE ERO SUB-OFFICE | 2,624 | Oklahoma | Oklahoma City 88% | high confidence |
| OKLAHOMA CITY METRO AREA (FUGOPS) | 1,271 | Oklahoma | Oklahoma City 94% | verify fug-ops convention |
| W DIST OK OKC DIV {X} CO NON CRIM (Beckham/Custer/Blaine/Oklahoma…) | ~530+ | same-named county | 100% single-county | Phase 0 fix #4 (`X CO`) |
| FTC CI (Federal Transfer Center) | 200 | Oklahoma | Oklahoma City | high confidence (Will Rogers Airport FTC) |
| DO NOT USE | 199 | skip | Tulsa 99% | labeled do-not-use — confirm rows are real arrests |

### TEXAS and CALIFORNIA (city layer first; landmark backstop sketched)

Texas — 106,606 unmapped landmark rows, but 34% have **no landmark at all** (city-only):

| Landmark | Rows | Proposed county | Evidence | Status |
|---|---:|---|---|---|
| MTG GENERAL AREA, NON-SPECIFIC | 26,910 | Montgomery | Conroe = 20% of TX unmapped city rows | verify = Conroe sub-office |
| DALLAS COUNTY GENERAL AREA | 24,394 | Dallas | Dallas = 22% of TX unmapped city rows | Phase 0 fix #1 |
| LRD GENERAL AREA, NON-SPECIFIC | 6,967 | Webb | Laredo 12.7% | verify = Laredo office |
| DLR GENERAL AREA, NON-SPECIFIC | 6,436 | Val Verde | Del Rio 4.6% | verify = Del Rio office |
| DUTY WINDOW 126 NORTHPOINT | 3,689 | Harris | Houston 11.2% | confirmed: Houston FO, 126 Northpoint Dr |
| WALKINS AT SAN ANTONIO | 3,619 | Bexar | San Antonio 5.8% | high confidence |
| TEXAS DEPT OF CRIMINAL JUSTICE, WALKER CO | 3,013 | Walker | — | county in landmark (Phase 0 fix #2-style) |
| Coastal Bend Detention Center | 2,723 | Nueces | Robstown 2.5% | verify (Robstown, Nueces County) |
| HDF GENERAL AREA, NON-SPECIFIC | 1,730 | **needs research** | — | which office? |
| Eden Detention Center-Eden, Texas | 1,599 | Concho? | — | verify (Eden is in Concho County) |
| Big Spring BOP | 1,130 | Howard | — | verify |
| SEGOVIA STATE JAIL- PRE-RELEASE, TX | 1,024 | **needs research** | — | locate this facility |

California — 48,944 unmapped landmark rows, 43% with no landmark:

| Landmark | Rows | Proposed county | Evidence | Status |
|---|---:|---|---|---|
| LOS ANGELES COUNTY GENERAL AREA, NON-SPECIFIC | 12,039 | Los Angeles | Los Angeles 21% of unmapped city rows | Phase 0 fix #1 |
| SBD GENERAL AREA, NON-SPECIFIC | 3,012 | San Bernardino | San Bernardino 4.2% | verify |
| San Diego, CA | 2,583 | San Diego | San Diego 24% | suffix `, CA` handled |
| SAA GENERAL AREA, NON-SPECIFIC | 2,508 | Orange | Santa Ana 4.7% | verify |
| FRE GENERAL AREA, NON-SPECIFIC | 1,891 | Fresno | Fresno 3% | verify |
| FUG OPS - LOS ANGELES, CA STATE | 1,773 | Los Angeles | — | `, CA` suffix; fug-ops convention |
| SFR GENERAL AREA, NON-SPECIFIC | 1,659 | San Francisco | San Francisco 6.6% | verify |
| IMP GENERAL AREA, NON-SPECIFIC | 1,606 | Imperial | El Centro 4.4% | verify = El Centro office |
| VEN GENERAL AREA, NON-SPECIFIC | 1,475 | Ventura | — | verify |
| FUGITIVE OPERATIONS CA STATE | 1,195 | *(leave NA)* | spread | statewide program |
| Federal Prison Lompoc FCI II | 1,037 | Santa Barbara | Lompoc 5.9% | high confidence |
| BKI GENERAL AREA, NON-SPECIFIC | 1,009 | Kern | — | verify = Bakersfield |
| DVA GENERAL AREA, NON-SPECIFIC | 818 | **needs research** | — | which office? |
| LOM GENERAL AREA, NON-SPECIFIC | 812 | Santa Barbara | Lompoc 5.9% | verify = Lompoc office |

### Standing conventions to settle once (apply to every state)

- **FUGITIVE OPERATIONS / ATD / NON-DETAINED DOCKET rows**: state-suffixed ones (`NY STATE`, `AL STATE`) are statewide — leave NA and let the city layer resolve; city-named ones (`SEATTLE FUG OPS`, `FUG / AT-LARGE IN PHILADELPHIA`) get the office's county.
- **GENERAL AREA codes**: map to the office's county only when the office sits in the report state (existing TN/MN rule); record out-of-state codes for documentation.
- **`Do Not Use` landmarks**: verify the rows are genuine arrests before either mapping or skipping.
- **Multi-county sites** (Devens MA; possible FL/OK cases): pick the primary county and flag in reports, consistent with `multi_county` handling in `build_place_county()`.

## Phase 3 — wiring, validation, documentation

Per confirmed state:

1. Add table rows to `state_landmark_tables()` in `R/state-arrests.R` (general-area / OTHER / pattern tables) and any `.landmark_county_overrides()` entries.
2. Re-run `nationwide_arrests_located`; check the unassigned panel for regressions (especially cross-state leakage through the generic parses).
3. Render the state report: `quarto render state-arrests.qmd -P state:STATENAME` (or add a `tar_quarto` target with a distinct `output_file`).
4. Update the coverage table and "Where to add new entries" notes in `state-arrests-locations.md`; post the updated body to [Discussion #15](https://github.com/CarwilB/ice-detention/discussions/15) per the documented `gh_gql` workflow.
5. Tick the corresponding rows above when each match is verified and merged.

## Expected coverage after Phases 0–1 (order-of-magnitude)

| State | Now | Phase 0 (landmark fixes only) | + city layer (at IL-like match rates) |
|---|---:|---:|---:|
| Texas | 33% | ~44% | ~75–85% |
| California | 2.5% | ~16% | ~70–80% |
| Florida | 27% | — | ~75–85% |
| New York | 14% | — | ~90%+ |
| New Jersey | 16% | — | ~80%+ |
| Georgia | 23% | — | ~80%+ |
| Louisiana | ~0% | ~25% | ~85%+ |
| Washington | 0.1% | ~1% | ~60–75% |
| Massachusetts | 3% | — | ~70%+ |
