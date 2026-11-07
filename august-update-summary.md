This conversation is being continued from a previous conversation that was compacted to reduce token use. The conversation is summarized below:

## Project and setup

- Working directory: `/Users/bjorkjcr/Dropbox/R/ice-detention` (RStudio, R 4.5.2, renv, `targets` pipeline).
- User memory: use `library(gh)` for GitHub access, not the gh CLI.
- Project memory (`AGENTS.md`) documents the pipeline, canonical ID scheme, facility type classification, and the rule to suggest `renv::install()` rather than `install.packages()`. I updated the FY26, registry pinning, canonical ID, and type override sections this session.
- Conventions: use `here::here()` for paths, base R pipe `|>`, ggplot2 with `theme_ice()` and `scale_y_pop()` in the FY26 report, and no `magrittr`.

## Earlier work (prior summary, still relevant)

- Report aesthetics for `ddp-comparison-26.qmd`, a "dropped from ICE roster" table, and an interim `fill_only_patches` stopgap in `build_fy26b()`.
- Tiered registry freeze in `build_facility_crosswalk()` (tiers 0–3: exact canonical, any variant, name+state unique, fuzzy name+city+state unique).
- Midwest Regional Reception Center assigned canonical 405 (CCALEKS, Leavenworth KS).
- New panel IDs allocate in the 40x block.
- `facility_profiles_data` schema fixes (`duplicate_likely`, `case_category`, removed `case_ina_236c_yes_no`).

## This session

### 1. Diagnosis of the expanded "Unclassified" list

The user asked whether the fix begins with `vera_type_overrides()`. The answer was no. The 30 "Unclassified" DDP codes in `monthly_unmatched` failed for three distinct reasons:

- **Group B (15 codes):** on the roster but absent from Vera (AKANVIL, ALLEGVA, AMHERVA, BLOJVTN, BOPLAT, BRYANGA, CBPORIL, CHTHMGA, EPCPCTX, FRANKNC, KFMANTX, LBRTYFL, LYNRJVA, ONSLONC, SAVHOLD). `vera_type_overrides()` cannot reach them because it only patches rows inside `vera_facilities`. The right mechanism is a canonical-ID-keyed override.
- **Group A2 (3 codes):** COLUMFL, MARIOFL, LEXFCKY, mapped to canonicals 1092, 1097, 1118 whose roster detloc differs. `build_unmatched_fy26()` joined on raw detloc, which missed them.
- **Group A1 (12 codes):** facilities that vanished from the panel because the July FY26 file replaced the Feb file. These are FY26-only panel members such as Dona Ana, El Paso County DF, Finney, Hillsborough, Miami Staging, Kansas City Holdroom, Southern Regional, and the WV regional jails. Dona Ana appears in no FY19–FY25 file.

### 2. Architecture decision (user-specified)

- **FY26b** = Feb 12 file (`data/ice/FY26_detentionStats_02122026.xlsx`, data through Feb 5). There is no March file. Flag this naming if it matters.
- **FY26c / FY26 (July)** = `data/ice/FY26_detentionStats07202026.xlsx`.
- Both snapshots are imported as first-class years in `build_data_file_info()` with a `snapshot` column (`"b"`, `"c"`). `import_all_years()` adds `fy26_snapshot`. The fiscal-year code stays `"FY26"` in the July file.
- `resolve_fy26_snapshots(facilities_all_keyed, interim)` in `R/crosswalk.R` builds:
  - `facilities_all_keyed_interim` → `facilities_panel_interim`: July wins, Feb fills drops. Drives the registry, roster, presence, `panel_facilities`, profiles, and the expanded map.
  - `facilities_panel`: July only. Drives the "reported by ICE" side of the DDP comparisons.
- `fy26_snapshot` sits right after `fiscal_year` in both panels. `save_outputs()` writes both panels.
- `year_order` is now `…FY25, FY26b, FY26`, so July ranks higher for canonical naming.
- `build_fy26b(facilities_keyed)` now just reads the keyed element. The `fill_only_patches` / `force_patches` logic remains for FY26b.

### 3. Registry and identity fixes

- **Liberty County duplicate:** registry 1259 was a duplicate of 1253 (12499 NW Pogo St, Bristol FL). Removed 1259; 1253 is the canonical.
- **Sarasota County Jail:** the pre-existing roster has it at **1104** (1107 = St. John's County Jail). The `fy26b` patch and registry now use 1104. A brief 1107 pin was reverted.
- **Stale manual match:** `DVCSDKY → 231` (Mesa Verde, Bakersfield) was removed from `ddp_manual_strong_matches()`. DVCSDKY belongs to canonical 96 (Daviess County Detention Center, Owensboro KY). The duplicate `231L` line in `crosswalk.R` `fill_only_patches` was also removed.
- **Override table drift:** `canonical_type_overrides()` had IDs written against a shifted ID map. Examples: 1252 is Kaufman County Jail, not a federal prison. Rewritten and verified against current DDP assignments. It now only covers IDs confirmed in the current roster. Note that it sets `facility_type_wiki`, not the Vera-corrected columns.
- **New `canonical_vera_type_overrides()`** in `R/aggregate.R`: keyed by canonical ID, sets `type_detailed_corrected` / `type_grouped_corrected`. Applied in `build_facility_roster()` before classification. It covers 1243–1257 (DDP-only jails, Alaska state prison at 1243, BOP at 1247, juvenile at 1246 and 1256, hold rooms 1250, 2127, 2187–2189), and the WV regional jails 258, 344, 345, 386.

### 4. Root cause of renumbering: DDP-range IDs

DDP-range IDs (1054+, 2181+, 3001+) were assigned by sequential position over the unmapped code set. Any upstream change, such as a registry unification removing a code, shifted every later ID. This is what silently moved AKANVIL and others by one, and briefly collided Columbia/Charlotte and Marion/Flagger.

### 5. Registry-aware DDP assignment (implemented)

- The registry CSV now has a `detloc` column (844–849 rows during this session; currently about 849).
- Pinned codes keep their registry ID. In `build_ddp_facility_canonical(ddp_codes, detloc_lookup_full, vera_facilities, id_registry, crosswalk, ddp_codes_new)`:
  - `.assign_block(df, block_max)` gives pinned codes their pinned IDs and assigns unpinned codes above `block_max`. Block maxima account for pins from both feather- and parquet-era codes.
  - Codes are excluded from the pool if they are mapped by `detloc_lookup_full` (non-pin) or pinned to a canonical the crosswalk rosters (the panel row wins).
  - Pass 2 (`ddp_codes_new`) appends hold/CBP after the hold maximum, medical after the medical maximum, and other after the ddp_other maximum.
  - New assignments are written back to the registry. A warning fires if a pin disagrees with the mapped canonical.
- `build_ddp_canonical_map()` now excludes pinned canonicals from fuzzy/county/keyword search and adds explicit `match_type = "pinned"`, `ddp_role = "sole"` rows. It logged 440 pinned rows.
- The `build_ddp_facility_canonical` call in `_targets.R` passes `id_registry` and `facility_crosswalk`.
- Verification: all 430 current DDP rows that match the pre-session roster artifact (`data/facilities-geocoded-all.csv`, last modified Oct 21 23:02) have identical IDs. The 10 unmatched rows are the six restored or newly pinned codes (COLUMFL, MARIOFL, BARTOGA, LEXFCKY, FCLT8CA, HERNAFL), the two Finney and Kansas City revivals (133, 186), Southern Regional (344, WVSOUTH), and CCADCAZ (1210, which lacked a roster match in the old artifact).
- Revived rosterless panel canonicals via pins: FINNEKS→133, KANHOLD→186, WVSOUTH→344.

### 6. Results

- Crosswalk: 355 canonical facilities. The two fuzzy audit matches are Cimarron→76 (tier 1) and Tex Health Huguley→360 (tier 3).
- Roster: 1027 facilities (panel 350, dmcp_only 53, ddp_other 209, ero 25, hold 164, medical 226).
- `unmatched_fy26`: 337 rows, **0 Unclassified** (was 30 among the monthly subset).
- Full `tar_make()` completed with 42 targets run and 68 skipped, with no errors. All reports rendered, including `ddp_fy26_comparison_report` and `ddp_fy26_comparison_20260330_report`.

### 7. Documentation updates in `AGENTS.md`

Updated: derived outputs table (interim panel, registry description), hold/roster counts, R/function file table, canonical ID space (1054–1257 pinned, 1258+ appended), type classification section (both override tables), and a new "FY26 snapshots and the two panels" section and "Registry pinning" section.

## Open issues and caveats

- **Pass-2 hold/medical assignments not yet exercised.** The current run has 0 medical in pass 2 and 9 hold/CBP already pinned.
- **Hold registry warning.** `build_hold_canonical` reported "1 new hold facility not in registry. Assigned ID 2181." On the last run it printed 155 records (2026–2180), so this warning is intermittent. Check `hold-canonical-registry.csv`, since the AGENTS.md entry references `data/hold-canonical-registry.csv`.
- **Google geocoding triggered** for about 20 restored facilities (`facilities_google_geocoded`). Some geocoded results are divergent by more than 3 km; `facilities_geocoded_all` reports 16 unresolved. Migrant Ops Center Main A (404) diverges 662 km from its Vera source and is unresolved.
- **`closed_wikitable`** still uses the July-only panel, so Feb-only drops appear as "Closed (Active FY26–FY26)." This is a known caveat.
- **0202 file not imported.** Finney, Kansas City Holdroom, and Southern Regional have no ICE FY26 rows from the Feb 2 file. Their roster presence comes from DDP pins. Adding the 0202 file as a third snapshot is a possible future step.
- **Tex Health Huguley duplicate.** Canonical 1211 (DDP-side) has the same Burleson address as 360. Unaddressed.
- **Pre-existing `WVSOUTH` ADP.** Southern Regional (344) shows DDP ADP 1.4 and ICE Feb ADP from the 0202 era is absent. Verify before publishing.
- **Stale `facility_type_wiki` for 344.** The roster classifies 344 as `county_jail` (Non-Dedicated) via `canonical_vera_type_overrides()`, but it is a regional jail. Review.
- **`canonical_type_overrides` vs `canonical_vera_type_overrides` duplication.** Both tables assign types to some of the same IDs at different levels. The intended division is that the Vera table sets the grouped/detailed columns and the wiki table sets the display label. Worth consolidating later.
- **Renumbering history.** Some DDP-range IDs in older AGENTS.md text (e.g. "1054–1209", "2026–2186") are outdated. The new text is in place, but other documents may still cite old ranges.
- **Git state.** Many files are modified and uncommitted, including `R/facility-profiles.R` and `R/state-arrests.R`, which I did not edit this session.
- **Stray tool error.** A `read` of `themarshallproject-locations.R` at the root path succeeded, but the `grep` calls against `R/` missed it because `build_hold_canonical` lives at the project root, not in `R/`.

## Next steps

1.  Review the rendered `ddp-comparison-26.qmd` unmatched and roster-churn sections.
2.  Decide on the 344 classification and the 1211/360 duplicate.
3.  Check the hold registry warning and whether `data/hold-canonical-registry.csv` matches the AGENTS.md reference.
4.  Consider consolidating the two canonical type override tables.
5.  Commit the working tree once the user is satisfied, given the broad changes.
