# DDP 20260806 update: recreated the discontinued daily-population parquet (validated exactly), wired it into the targets pipeline with archived through-March analyses, renamed and documented versioned DDP files, analyzed facility vs national daily population maxima, and added provenance metadata to FY26 comparison exports while checking local DDP files against current upstream versions.

> Compacted 2026-10-03 (Posit Assistant) from the ~880 KB session transcript, after the session's `/compact` failed ("No available summary model can accept the finalized compaction request"). User messages preserved verbatim; assistant work summarized. Established workflow is codified in the project skill `.posit/assistant/skills/updating-ddp-data/SKILL.md`.

## Request 1 — Recreate facilities-daily-population-latest.parquet from detention stints

> The Deportation Data Project provided facilities-daily-population-latest.parquet, with daily data on those detained by facility. They state online that this dataset was constructed from detention-stints-latest.parquet.
>
> However in their latest data update (signaled by _20260806), there is no facilities-daily-population-latest.
>
> Drawing on our existing import and use of detention-stints*, see if there is a straightforward way to recreate facilities-daily-population-latest.parquet through calculation. Allow some small tolerance rather than a byte-for-byte match.
>
> DDP's code base is here: https://github.com/deportationdata/ice/tree/main, and you might want to work with that first. Should I download it to a ../ice ?

**Work done:**

- Cloned the DDP repo to `~/Dropbox/R/ice` (sparse checkout of `code/` only; a full checkout fails on the multi-GB LFS parquets).
- Found that DDP **removed** the generating script `code/facilities-daily-population-latest.R` from the repo on 2026-07-06 (commit `bfc8b3fa76`, "joined arrests-detention stays (#9)"). Recovered the last version from commit `c19668375f` (2026-03-30) and preserved it with a provenance header at [data/ddp/facilities-daily-population-latest.R](../data/ddp/facilities-daily-population-latest.R).
- Wrote `build_ddp_daily_population()` in [R/ddp-daily-population.R](../R/ddp-daily-population.R) — data.table-based (~40–55 s runtime), replicating DDP semantics: day-expansion of each stint from book-in date through book-out date (open stints capped at the data-through date); distinct-person counts per facility-code × date across six metrics (`n_detained`, `n_detained_at_midnight`, `n_detained_male`, `n_detained_female`, `n_detained_convicted_criminal`, `n_detained_possibly_under_18`); NA identifiers each count as one person; duplicate-flagged stints are NOT filtered; complete facility × date grid with zeros; facility name from each code's most recent book-in.
- **Validation:** rebuilding DDP's published 20260330 daily-population file from the 20260515 stints reproduced all 888,699 rows (707 codes × 1,257 days), all six count columns, and all facility names **exactly** — stronger than the "small tolerance" requested.
- Produced [data/ddp/facilities-daily-population-latest_20260806.parquet](../data/ddp/facilities-daily-population-latest_20260806.parquet): 740 codes × 1,405 days = 1,039,700 rows (2022-10-01 through 2026-08-05, following DDP's cap = release date − 1 convention), zstd, 2.4 MB.
- **Overlap caveat:** vs the old published file (through 2026-03-10), ~91% of cells identical; mean |diff| ≈ 0.3 detainees; totals ~0.2% lower. 36 new facility codes, 2 dropped (ECC, YORCOPA). Since the method reproduced the old file exactly, these are DDP's own retroactive data revisions between stints releases, not method error.

## Request 2 — Wire into pipeline, archive, rename, document versions, update qmd

> Wire the recreation into the pipeline: add a `facilities_daily_population` target (or repoint `ddp_parquet_file`) that builds from the 20260806 stints, so the FY26 comparison analyses use the current data.
>
> Archive the through-March analysis rather than replacing it.
>
> Rename the older -latest.parquet files to match the _20260806 file naming convention and alter the pipeline so that it uses them correctly.
>
> Update the data/ddp-detention*.yml files to describe versioning and the changes between versions.
>
> Update `ddp-parquet-summary.qmd` to cover (adding, not replacing) the 20260806 daily-population file and document the overlap-period revisions vs the old release.

**Work done:**

- **Renames** (suffix = DDP release date from GitHub commit history, not download date): `facilities-daily-population-latest.parquet` → `_20260330`, `detention-stints-latest.parquet` → `_20260515`, `detention-stays-latest.parquet` → `_20260514`, `arrests-latest.parquet` → `_20260330`. Old versions are never deleted; they remain frozen inputs to archived analyses.
- **[_targets.R](../_targets.R) wiring** (107 targets total after edits):
  - New current chain: `facilities_daily_population_file` (builds from `stints_raw` via `build_ddp_daily_population()`, writes the `_20260806` parquet, zstd) → `facilities_daily_population` → `ddp_fy26_keyed`, `daily_totals_fy26`, `unmatched_fy26`, `peak_fy26`, `ddp_fy26_comparison_export`, `ddp_fy26_comparison_report` (tar_quarto on `ddp-comparison-26.qmd`).
  - `ddp_parquet_file` / `ddp_new` repointed to the frozen `_20260330` published file (still feeds the expanded map, facility profiles/directory, and FY25-era analyses).
  - Archived through-March chain added: `ddp_fy26_keyed_20260330`, `daily_totals_fy26_20260330`, `unmatched_fy26_20260330`, `peak_fy26_20260330`, `ddp_fy26_comparison_export_20260330` (writes `data/ddp-comparison-export-fy26-20260330/`), `ddp_fy26_comparison_20260330_report` (tar_quarto on the frozen `ddp-comparison-26-20260330.qmd`).
- Fixed two `_targets.R` syntax errors introduced during editing (stray `),,` and a missing comma after the current report's `tar_quarto` block); pipeline then parsed cleanly and targets built.
- **YML sidecars** rewritten with `versions:` sections documenting each release and changes between them:
  - [data/ddp-detention-stints.yml](../data/ddp-detention-stints.yml): 20260806 current (3,202,317 rows × 59 cols, 740 codes, data through 2026-08-06); 20260515 frozen (2,617,844 × 61, 707 codes — validated reproduction input); 20260330 documented but not retained locally. Schema overhaul in 20260806: added age-at-book-in, stint/stay length days, 60/90-day release flags, conviction flag, CBSA and federal court district/circuit columns, three-column duplicate-flag family (46,428–46,430 flagged rows, none removed); dropped 20 columns (incl. race, birth_country, book_in_site, likely_duplicate); `initial_bond_set_amount` double → string.
  - [data/ddp-detention-stays.yml](../data/ddp-detention-stays.yml): 20260514 frozen pipeline input; 20260806 on disk but not wired (schema change: no `detention_facility_code` column).
  - [data/ddp-daily-population.yml](../data/ddp-daily-population.yml): new sidecar covering the published-through-20260330 file and the recreated 20260806 file.
  - [data/ddp-arrests.yml](../data/ddp-arrests.yml): 20260330 version documented.
- **[ddp-parquet-summary.qmd](../ddp-parquet-summary.qmd)** updated by adding, not replacing: new "The 20260806 release" section (`#sec-20260806`) with live-computed dataset basics, population-by-fiscal-year table, overlap revisions vs the 20260330 release (~90–91% cells exact, totals ~0.2% lower), and added/dropped facility codes; overview, pipeline targets, FY26 export, and related-files sections updated to describe both versions and the archived 20260330 analysis.

## Request 3 — Max daily population: single facility or national?

> What's going on with the max daily population in ddp-parquet-summary?: is that in one facility? How about nationally?

**Answer:** every "Max Daily" figure in that table is the largest count at a **single facility on a single day** (`max(n_detained)` over facility-day rows), not a national total.

Largest single facility-day per fiscal year (20260806 data):

| FY | Max facility-day | Facility | Date |
|---|---|---|---|
| 2023 | 1,775 | STCDFTX — South Texas ICE Processing Center | 2023-09-09 |
| 2024 | 2,201 | ADAMSMS — Adams County Correctional Center | 2024-09-13 |
| 2025 | 2,926 | EROFCB — ERO El Paso Camp East Montana | 2025-09-30 |
| 2026 | 4,098 | EROFCB — ERO El Paso Camp East Montana | 2026-01-15 |

Largest national daily total per fiscal year:

| FY | Max daily (booked) | Max daily (midnight) | Date |
|---|---|---|---|
| 2023 | 38,209 | 35,965 | 2023-09-27 |
| 2024 | 41,390 | 39,263 | 2023-11-07 |
| 2025 | 65,370 | 60,808 | 2025-08-22 |
| 2026 | 75,970 | 70,821 | 2026-01-16 |

Notes: the old hardcoded table (1,776 / 2,203 / 2,940 / 4,130) shows the same facilities with slightly higher numbers — 20260330 data state; DDP's retroactive revisions shave a few records. The FY25–FY26 record-holder is not a detention center but an ERO field-office code — EROFCB, the El Paso "Camp East Montana" staging site — the clearest single-facility signature of the post-inauguration surge. National "booked" totals double-count people on transfer days (~5% above the midnight census); the midnight figures are the better national headcount. FY26 national peak date (2026-01-16) matches the comparison report's daily-totals chart.

## Request 4 — Provenance metadata on FY26 comparison exports

> Add metadata to the files exported in data/ddp-comparison-export-fy26 indicating provenance (which file, what dates are covered, source to DDP with URLs) and date of computation. Do this both retroactively and include code to do so in the future in the pipeline. Add files for the March data release.

**Work done:**

- Added `build_fy26_export_provenance()` to [R/ddp.R](../R/ddp.R); `export_ddp_fy26_comparison_data()` now attaches a `provenance` attribute to every exported RDS (source file, publisher + DDP/ICE URLs, dates covered, DDP release, comparison window, pipeline target, computation timestamp) and writes a companion `_provenance.json` in each export directory.
- **Retroactive annotation** of the frozen March export (`data/ddp-comparison-export-fy26-20260330/`) via the documented one-off [annotate-20260330-export-provenance.R](../annotate-20260330-export-provenance.R), reusing the same builder: all 9 RDS files annotated (including the pre-sparkline `peak_fy26.rds`), with the commit-pinned historical URL for the now-deleted DDP file and computed date 2026-04-13 (from deployed post file timestamps; flagged approximate).
- **Current export** regenerated via `tar_make(ddp_fy26_comparison_export)`: 8 RDS + `_provenance.json` in `data/ddp-comparison-export-fy26/`, each carrying 20260806 provenance with the computation timestamp. Verified by reading attributes back from both directories.
- ddp-parquet-summary.qmd's export section updated to mention the provenance attribute and `_provenance.json`.

**Currency check against DDP's page** (download links point at GitHub repos, so repo main = current site version; compared content hashes with local files):

| Local file | Upstream current | Status |
|---|---|---|
| detention-stints-latest_**20260806**.parquet | sha256 identical to repo main | **Current** |
| detention-stays-latest_**20260806**.parquet | sha256 identical to repo main | **Current** (unwired) |
| facilities-daily-population (20260806) | discontinued by DDP | Current by construction (recreated) |
| arrests-latest_**20260330**.parquet (27.9 MB) | 36.4 MB, commits Sep 8/10/**22** | **Outdated** — feeds arrest analyses |
| facilities-latest_**20260430**.parquet | DDP bot auto-updates every few days (last Sep 30) | **Outdated** — reference only |
| ice-offices.xlsx/.feather | xlsx updated Apr 21; parquet now also offered | **Outdated** (minor) — reference only |
| stints/stays 20260515/20260514, daily-pop 20260330, old feather | — | Intentionally frozen archives |

Observations: the DDP page's prose ("most recent release covers enforcement actions through March 6, 2026") is stale relative to its own download links (enforcement files last committed Sep 22). The page now hosts two datasets not held locally: detainers-latest (new, Sep) and joined-arrests-detention-stays-latest (new, Jul).

## Close

> /compact

The session's own compaction attempt failed ("No available summary model can accept the finalized compaction request"); this file is the manual compaction.

**Outstanding suggestions from the session** (not yet acted on at compaction):

- Relabel the qmd table columns ("Max single facility-day") and add a national daily totals row.
- Plot the EROFCB (El Paso Camp East Montana) daily series to document the staging-facility surge.
- Use the midnight-census national total wherever a national headcount is quoted.
- Download the updated arrests-latest and rewire the arrest analyses, checking the documented schema changes first. **Note:** as of compaction, `data/ddp/arrests-latest_20260806.parquet` (36.4 MB) and `joined-arrests-detention-stays-latest_20260806.parquet` (102 MB) are present on disk, but `_targets.R`'s `arrests_file` still points to the 20260330 file — the arrests rewiring is incomplete.
- Refresh the reference files `facilities-latest` and `ice-offices` from DDP's dedicated repos (drop-in, not pipeline inputs).
- Consider adding the new DDP detainers and joined-arrests-detention-stays datasets for transfer-itinerary and arrest-linkage work.
