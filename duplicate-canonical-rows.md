# Duplicate canonical rows within single-year ICE spreadsheets

Generated 2026-10-25 from `facilities_all_keyed_interim` (and the raw FY26 snapshot lists). Not a pipeline target — a one-off audit.

## What this is

The crosswalk assigns every (facility_name, city, state) variant a canonical ID. In 8 cases across 6 fiscal years, ICE's own data gives one canonical **two rows within a single year** — either two name variants of the same facility, a main row plus a small line item (staging, TAP-ICE), or two distinct DETLOCs merged into one canonical.

`build_fy_range_union()` (which feeds the era wikitable chains) keeps the **first spreadsheet row** for each canonical within a year and drops the rest; later years in a range also take precedence over earlier ones.

## Summary by year

No doubling in FY10, FY12, FY14–FY16, FY23–FY25, or any FY26 snapshot (the FY26a / FY26b / FY26c raw lists were checked separately).

| Year | Doubled canonicals | Rows dropped | ADP on dropped rows |
|---|---|---|---|
| FY11 | 153 | 1 | 2.0 |
| FY13 | 153 | 1 | 1.2 |
| FY19 | 190, 199 | 2 | 695.7 |
| FY20 | 199, 313 | 2 | 578.2 |
| FY21 | 199 | 1 | 625.8 |
| FY22 | 366 | 1 | 0.9 |

## Full detail — all 16 rows

`Row #` is the row's position within its year's spreadsheet; `Union` marks the row `build_fy_range_union()` keeps.

| Fiscal year | Canonical | Row # | Union | Facility name (spreadsheet) | City | ST | DETLOC | ADP | ICE type | M/F |
|---|---|---|---|---|---|---|---|---|---|---|
| FY11 | 153 Grayson County Jail | 1 | kept | Grayson County Jail | Leitchfield | KY | GRAYSKY | 1.0 | USMS IGA | Female/Male |
| FY11 | 153 Grayson County Jail | 2 | **DROPPED** | Grayson County Detention Center | Leitchfield | KY | GRYDCKY | 2.0 | USMS IGA | Female/Male |
| FY13 | 153 Grayson County Jail | 1 | kept | Grayson County Jail | Leitchfield | KY | GRAYSKY | 4.0 | USMS IGA | Female/Male |
| FY13 | 153 Grayson County Jail | 2 | **DROPPED** | Grayson County Detention Center | Leitchfield | KY | GRYDCKY | 1.2 | USMS IGA | Female/Male |
| FY19 | 190 Karnes County Residential Center | 3 | kept | Karnes County Civil Detention Center | Karnes City | TX | KCCDCTX | 431.5 | FAMILY | Female/Male |
| FY19 | 190 Karnes County Residential Center | 4 | **DROPPED** | Karnes County Residential Center | Karnes City | TX | KCCDCTX | 214.1 | FAMILY | Male |
| FY19 | 199 La Palma Correctional Center | 1 | kept | La Palma Correctional Center | Eloy | AZ | LPLCCAZ | 1221.5 | IGSA | Male |
| FY19 | 199 La Palma Correctional Center | 2 | **DROPPED** | La Palma Correction Center - Apso | Eloy | AZ | LPLCCAZ | 481.6 | IGSA | Male |
| FY20 | 199 La Palma Correctional Center | 1 | kept | La Palma Correctional Center | Eloy | AZ | LPLCCAZ | 973.6 | DIGSA | Male |
| FY20 | 199 La Palma Correctional Center | 3 | **DROPPED** | La Palma Correction Center - Apso | Eloy | AZ | LPLCCAZ | 577.7 | DIGSA | Male |
| FY20 | 313 Port Isabel Detention Center | 2 | kept | Port Isabel | Los Fresnos | TX | PIC | 677.9 | SPC | Female/Male |
| FY20 | 313 Port Isabel Detention Center | 4 | **DROPPED** | Rio Grande Valley Staging | Los Fresnos | TX | PIC | 0.5 | STAGING | Female/Male |
| FY21 | 199 La Palma Correctional Center | 1 | kept | La Palma Correctional Center | Eloy | AZ | LPLCCAZ | 628.6 | DIGSA | Male |
| FY21 | 199 La Palma Correctional Center | 2 | **DROPPED** | La Palma Correction Center - Apso | Eloy | AZ | LPLCCAZ | 625.8 | DIGSA | Male |
| FY22 | 366 Dilley Immigration Processing Center | 1 | kept | South Texas Family Residential Center3 | Dilley | TX | STFRCTX | 737.9 | DIGSA | Female/Male |
| FY22 | 366 Dilley Immigration Processing Center | 2 | **DROPPED** | Trusted Adult South Tex Dilley FSC | Dilley | TX | STFRCTX | 0.9 | TAP-ICE | Female/Male |

## Patterns

- **Two distinct DETLOCs merged into one canonical (Grayson County, KY, canonical 153):** `GRAYSKY` ("Grayson County Jail") and `GRYDCKY` ("Grayson County Detention Center") are separate ICE codes the crosswalk merged. Duplicated in FY11 and FY13; the kept row is always `GRAYSKY`. ADP on both rows is tiny (1–4 detainees).
- **Name-variant duplicates at the same DETLOC (La Palma, AZ, canonical 199):** "La Palma Correctional Center" plus "La Palma Correction Center - Apso" (same DETLOC `LPLCCAZ`), duplicated in FY19, FY20, and FY21. The "- Apso" rows carry **substantial ADP (481–626)**, so this is not a trivial line item — whether the two rows are separate populations or two listings of the same population is unresolved.
- **Main row + small line item (Port Isabel, TX, canonical 313; Dilley, TX, canonical 366):** "Rio Grande Valley Staging" (ADP 0.5, FY20) and "Trusted Adult South Tex Dilley FSC" (ADP 0.9, TAP-ICE, FY22) sit under the main facility's canonical and DETLOC. Dropping them loses almost nothing.
- **Two names for one facility (Karnes, TX, canonical 190, FY19):** "Karnes County Civil Detention Center" (ADP 431.5, Female/Male) and "Karnes County Residential Center" (ADP 214.1, Male) share DETLOC `KCCDCTX`. The second row's ADP is substantial; the male-only gender split suggests the rows may cover different sub-populations.

## What reaches the wikitables

Each era table takes a canonical's values from the **latest year in the era's range where the facility is listed**. Routing for the five affected canonicals:

| Canonical | Era table | Feeding year | Facility name | City | ADP shown | ICE type | M/F | Feeding year has a dup? |
|---|---|---|---|---|---|---|---|---|
| 153 Grayson County Jail | FY10–FY16 | FY16 | Grayson County Jail | Leitchfield | 1 | USMS IGA | Female/Male | no |
| 153 Grayson County Jail | FY17–FY20 | FY17 | Grayson County Jail | Leitchfield | 1 | USMS IGA | Female/Male | no |
| 153 Grayson County Jail | FY21–FY24 | FY24 | Grayson County Jail | Leitchfield | 1 | USMS IGA | Female/Male | no |
| 153 Grayson County Jail | FY25–FY26 union | FY26 | Grayson County Jail | Leitchfield | 160 | USMS IGA | Female/Male | no |
| 190 Karnes County Residential Center | FY17–FY20 | FY20 | Karnes County Residential Center | Karnes City | 211 | FAMILY | Male | no |
| 190 Karnes County Residential Center | FY21–FY24 | FY21 | Karnes County Residential Center | Karnes City | 169 | FAMILY | Female/Male | no |
| 199 La Palma Correctional Center | FY17–FY20 | FY20 | La Palma Correctional Center | Eloy | 974 | DIGSA | Male | yes — kept row shown |
| 199 La Palma Correctional Center | FY21–FY24 | FY22 | La Palma Correctional Center | Eloy | 689 | DIGSA | Female/Male | no |
| 313 Port Isabel Detention Center | FY10–FY16 | FY16 | Port Isabel | Los Fresnos | 1104 | SPC | Female/Male | no |
| 313 Port Isabel Detention Center | FY17–FY20 | FY20 | Port Isabel | Los Fresnos | 678 | SPC | Female/Male | yes — kept row shown |
| 313 Port Isabel Detention Center | FY21–FY24 | FY24 | Port Isabel Detention Center | Los Fresnos | 976 | SPC | Female/Male | no |
| 313 Port Isabel Detention Center | FY25–FY26 union | FY26 | Port Isabel Detention Center | Los Fresnos | 1152 | SPC | Female/Male | no |
| 366 Dilley Immigration Processing Center | FY21–FY24 | FY23 | South Texas Fam Residential Center | Dilley | 1099 | DIGSA | Female/Male | no |
| 366 Dilley Immigration Processing Center | FY25–FY26 union | FY26 | Dilley Immigration Processing Center | Dilley | 426 | FAMILY | Female/Male | no |

Only two doublings actually surface in the current tables — both in the FY17–FY20 section, because only there does a duplicated year end up the feeding year:

| Facility | Wikitable shows | Dropped row would have shown |
|---|---|---|
| La Palma Correctional Center (FY17–FY20) | "La Palma Correctional Center", ADP 974 | "La Palma Correction Center - Apso", ADP 578 |
| Port Isabel Detention Center (FY17–FY20) | "Port Isabel", ADP 678 | "Rio Grande Valley Staging", ADP 0.5 |

The FY21–FY24, FY10–FY16, and FY25–FY26 tables are unaffected: for every other duplicated canonical the feeding year is either not a duplicated year or a later year wins outright.

## Caveat: the main panel still carries the dropped rows

`facilities_panel` / `facilities_panel_interim` are built by `build_panel()` directly from the keyed lists and do **not** dedupe within-year canonical rows. Year-level ADP sums from the panel therefore double-count the dropped variants:

| Year | Dropped rows | Dropped ADP | Year's total panel ADP | Overcount |
|---|---|---|---|---|
| FY11 | 1 | 2.0 | 27067.4 | 0.01% |
| FY13 | 1 | 1.2 | 29421.3 | 0.00% |
| FY19 | 2 | 695.7 | 49142.3 | 1.42% |
| FY20 | 2 | 578.2 | 32979.2 | 1.75% |
| FY21 | 1 | 625.8 | 18292.4 | 3.42% |
| FY22 | 1 | 0.9 | 21343.5 | 0.00% |

The largest effects are FY21 (+626 detainees, 3.4% — the La Palma "- Apso" row) and FY20 (+578, 1.75%). Whether the "- Apso" and Karnes second rows are separate populations (under-count if dropped) or duplicate listings (correct to drop) is unresolved — see the patterns above.

## Status column is unaffected

The presence matrix records canonical-level presence per year, so doubled rows never distort the Active/Closed status labels in any wikitable.
