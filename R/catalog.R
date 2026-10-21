# Pipeline targets catalog generator.
# Produces data/targets-catalog.md with hand-maintained descriptions
# and auto-populated dimensions from tar_meta() / tar_read_raw().

# ── Target descriptions ──────────────────────────────────────────────────────
# Hand-maintained. Each target has a section (for grouping) and a description.
# Add new entries here when adding targets to _targets.R.

target_descriptions <- function() {
  tibble::tribble(
    ~target, ~section, ~description,

    # Core annual stats pipeline
    "data_file_info", "Core annual stats pipeline",
    "Spreadsheet URLs, sheet names, header row positions, and rightmost data columns for each FY19--FY26 XLSX file.",

    "raw_xlsx_files", "Core annual stats pipeline",
    "Local paths to downloaded ICE annual stats XLSX files. **cue = \"never\"**.",

    "clean_names_list", "Core annual stats pipeline",
    "Clean variable name vectors (one per fiscal year), derived from the 2-row merged Excel headers.",

    "facilities_raw", "Core annual stats pipeline",
    "Raw tibbles imported from each XLSX file, one per fiscal year (FY19--FY26).",

    "facilities_clean", "Core annual stats pipeline",
    "Cleaned tibbles with standardized facility names, city corrections, type coercion, and Guantanamo patch.",

    "facilities_aggregated", "Core annual stats pipeline",
    "Aggregated tibbles with row-level ADP sums, `share_non_crim`, `share_no_threat`, and `facility_type_wiki` classification.",

    "id_registry_file", "Core annual stats pipeline",
    "Tracks `data/canonical_id_registry.csv` for changes.",

    "id_registry", "Core annual stats pipeline",
    "Frozen registry of canonical IDs 1--398 (FY19--FY26 facilities). Append-only; new annual stats extend from 399.",

    "facility_crosswalk", "Core annual stats pipeline",
    "Maps every (name, city, state) variant observed across FY19--FY26 to a `canonical_id` and `canonical_name`. Built via exact + fuzzy address matching.",

    "facilities_keyed", "Core annual stats pipeline",
    "FY19--FY26 aggregated data with `canonical_id`, `canonical_name`, and `detloc` joined from the crosswalk and DETLOC lookup.",

    "facilities_all_keyed", "Core annual stats pipeline",
    "Merged FY10--FY26 (minus FY18). Combines `facilities_keyed` (FY19--26) with `facilities_annual_sums` (FY10--17); adds `adp` column to FY19--26.",

    "facility_presence", "Core annual stats pipeline",
    "One row per canonical facility with FY10--FY26 boolean presence columns and a trajectory label (`continuous`, `persistent_gaps`, `closed`, `new`, `transient`).",

    "facilities_panel", "Core annual stats pipeline",
    "Long-format panel: one row per facility per year (FY10--FY26, minus FY18). All ~30 measurement variables plus canonical IDs and DETLOCs. The primary analytical dataset.",

    "panel_facilities", "Core annual stats pipeline",
    "One row per panel facility (IDs 1--398) with the most recent address, city, state, ZIP, DETLOC, and facility_type_wiki. Input for geocoding and wiki matching.",

    "facility_roster", "Core annual stats pipeline",
    "Full roster: one row per canonical facility (~962) across all ID ranges with best-available address, type, DETLOC, and geocoding.",

    # Geocoding
    "facilities_geocoded", "Geocoding",
    "Google Maps API geocoded coordinates for FY19--FY26 canonical facilities (IDs 1--398). **cue = \"never\"**.",

    "facilities_geocoded_full", "Geocoding",
    "Extends geocoding to DMCP-only facilities (IDs 1001+) using faclist15/faclist17 addresses. **cue = \"never\"**.",

    "facilities_geocoded_all", "Geocoding",
    "Unified geocoded table merging Google Maps, ERO, Marshall Project, and Vera coordinates with a `geocode_source` column.",

    # DMCP supplemental listings
    "faclist15_file", "DMCP supplemental listings",
    "Path to the 2015 DMCP XLSX. **cue = \"never\"**.",

    "faclist17_file", "DMCP supplemental listings",
    "Path to the 2017 DMCP PDF. **cue = \"never\"**.",

    "faclist15_raw", "DMCP supplemental listings",
    "Raw import of the 2015 DMCP facility listing XLSX.",

    "faclist17_raw", "DMCP supplemental listings",
    "Raw import of the 2017 DMCP facility listing PDF (via tabulapdf).",

    "faclist15", "DMCP supplemental listings",
    "Cleaned 2015 DMCP roster with project-schema column names, ZIP zero-padding, and city corrections.",

    "faclist17", "DMCP supplemental listings",
    "Cleaned 2017 DMCP roster with digit-bleed repair, column renames, and city corrections.",

    "dmcp_canonical_map", "DMCP supplemental listings",
    "Maps every DMCP DETLOC to a canonical_id via 3-pass matching (exact, manual, new IDs from 1001+).",

    "faclist15_keyed", "DMCP supplemental listings",
    "faclist15 with `canonical_id`, `canonical_name`, and `match_type` prepended.",

    "faclist17_keyed", "DMCP supplemental listings",
    "faclist17 with `canonical_id`, `canonical_name`, and `match_type` prepended.",

    "facilities_annual_sums", "DMCP supplemental listings",
    "Per-fiscal-year tables (FY10--FY17) with one row per facility with non-zero ADP. Built from faclist15/faclist17 data.",

    # DDP daily population data
    "ddp_file", "DDP daily population data",
    "Tracks the DDP feather file for changes.",

    "ddp_raw", "DDP daily population data",
    "Raw daily detention population data from the Deportation Data Project (Sep 2023--Oct 2025). One row per facility per day.",

    "ddp_codes", "DDP daily population data",
    "Distinct cleaned facility codes extracted from `ddp_raw`.",

    "ddp_facility_canonical", "DDP daily population data",
    "Assigns canonical IDs to 376 unmapped DDP facility codes: 150 non-medical (IDs 1054--1203) and 226 medical (IDs 3001--3226). Uses Vera Institute metadata for addresses and types.",

    "ddp_fy25_summary", "DDP daily population data",
    "DDP daily population summarized to one row per facility for FY25 (Oct 2024--Sep 2025). ADP by sex/criminality/age, peak population, and derived shares.",

    "ddp_fy25_summary_file", "DDP daily population data",
    "Exports `ddp_fy25_summary` to `data/ddp-fy25-summary.csv`. format = \"file\".",

    "ddp_canonical_map", "DDP daily population data",
    "Maps DDP DETLOCs to canonical facilities not already in DMCP data. Three-tier matching: fuzzy OSA, county name, confirmed keyword.",

    "ddp_parquet_file", "DDP daily population data",
    "Tracks the DDP 20260330 daily-population parquet (Oct 2022--Mar 2026, DDP's last published release, renamed with version suffix) for changes.",

    "ddp_new", "DDP daily population data",
    "DDP daily population from parquet, frozen 20260330 release (Oct 2022--Mar 2026, 707 facilities). Feeds `ddp_codes_new`, `ddp_annual_panel`, facility profiles/directory, and the archived through-March FY26 comparison.",

    "facilities_daily_population_file", "DDP daily population data",
    "Recreated DDP daily-population parquet (Oct 2022--Aug 5 2026, 740 facilities) written to `data/ddp/` from the 20260806 stints via `build_ddp_daily_population()`. DDP no longer publishes this file.",

    "facilities_daily_population", "DDP daily population data",
    "Current DDP daily population (Oct 2022--Aug 5 2026, 740 facility codes), recreated from the 20260806 stints; source for the current FY26 comparison chain. Validated: the same method reproduces the published 20260330 file exactly.",

    # FY26 comparison pipeline (DDP daily population vs Feb 2026 ICE release)
    "fy26b", "FY26 comparison pipeline",
    "Feb 12 2026 ICE spreadsheet: 220 facilities cleaned, aggregated, and keyed; 3 known IDs patched; 4 genuinely new.",

    "ddp_fy26_keyed", "FY26 comparison pipeline",
    "DDP FY26 facility summary (Oct 2025--Feb 5 2026) keyed via detloc_lookup; `in_ice_fy26` flag marks matches to the ICE FY26 spreadsheet. Uses current (20260806) DDP data.",

    "daily_totals_fy26", "FY26 comparison pipeline",
    "DDP total detained population per day, Jan 2025--Aug 5 2026 (current 20260806 data).",

    "unmatched_fy26", "FY26 comparison pipeline",
    "DDP FY26 facilities not in ICE FY26 annual statistics, with type and address from `facility_roster`.",

    "peak_fy26", "FY26 comparison pipeline",
    "Peak population summary for FY26 unmatched facilities with geocoding; sparklines added separately at export time.",

    "ddp_fy26_comparison_export", "FY26 comparison pipeline",
    "Exports 8 RDS files + `_provenance.json` to `data/ddp-comparison-export-fy26/` for the FY26 comparison report (Oct 2025--Feb 5 2026; current 20260806 DDP data). Each RDS carries a `provenance` attribute.",

    "ddp_fy26_comparison_report", "FY26 comparison pipeline",
    "Rendered DDP vs ICE FY26 comparison report (current 20260806 DDP data); review locally before deploying to quarto website.",

    "ddp_fy26_keyed_20260330", "FY26 comparison pipeline",
    "Archived through-March DDP FY26 keyed summary (Oct 2025--Feb 5 2026) from the frozen 20260330 parquet.",

    "daily_totals_fy26_20260330", "FY26 comparison pipeline",
    "Archived through-March daily totals (Jan 2025--Mar 10 2026) from the frozen 20260330 parquet.",

    "unmatched_fy26_20260330", "FY26 comparison pipeline",
    "Archived through-March unmatched DDP FY26 facilities (frozen 20260330 data).",

    "peak_fy26_20260330", "FY26 comparison pipeline",
    "Archived through-March peak population summary for unmatched facilities (frozen 20260330 data).",

    "ddp_fy26_comparison_export_20260330", "FY26 comparison pipeline",
    "Archived through-March FY26 comparison export (8 RDS files to `data/ddp-comparison-export-fy26-20260330/`); frozen reference.",

    "ddp_fy26_comparison_20260330_report", "FY26 comparison pipeline",
    "Archived through-March FY26 comparison report (`ddp-comparison-26-20260330.qmd`, frozen DDP 20260330 data); preserved snapshot of the pre-20260806 analysis.",

    # Unified DETLOC lookup
    "detloc_lookup", "Unified DETLOC lookup",
    "Deduplicated 1:1 mapping of DETLOC to `canonical_id`. Each DETLOC and each canonical_id appears at most once. Source priority: DDP > DMCP > hold/ERO > Vera.",

    "detloc_lookup_full", "Unified DETLOC lookup",
    "Multi-row reference preserving all DETLOC variants from all sources, including `ddp_role` (sole/primary/component). Use when matching all known codes for a facility.",

    # Hold facility and ERO integration
    "ero_canonical_file", "Hold facility and ERO integration",
    "Tracks `data/ero-field-offices-canonical.csv`.",

    "ero_geocoded_file", "Hold facility and ERO integration",
    "Tracks `data/ero-field-offices-geocoded.csv`.",

    "ero_canonical", "Hold facility and ERO integration",
    "25 ERO field offices with canonical IDs (2001--2025), DETLOCs, and addresses.",

    "hold_canonical_data", "Hold facility and ERO integration",
    "Hold facility integration results: `hold_canonical` (148 hold facilities, IDs 2026--2173), `ero_hold_map` (23 ERO DETLOC mappings), and summary statistics.",

    # Marshall Project locations
    "marshall_locations_file", "Marshall Project locations",
    "Path to downloaded CSV. **cue = \"never\"**.",

    "marshall_locations_raw", "Marshall Project locations",
    "Raw import of Marshall Project facility locations (CY 1978--Nov 2017).",

    "marshall_locations", "Marshall Project locations",
    "Cleaned Marshall Project data with DETLOCs, addresses, AOR, first/last use dates, and geocoded lat/lon.",

    # Vera Institute facility metadata
    "vera_facilities_file", "Vera Institute facility metadata",
    "Tracks `data/vera-institute/facilities.csv`.",

    "vera_facilities_raw", "Vera Institute facility metadata",
    "Raw import of Vera Institute facility metadata.",

    "vera_facilities", "Vera Institute facility metadata",
    "Cleaned Vera facility data with geocoded locations, addresses, county, AOR, and type classifications (`type_grouped`, `type_detailed`).",

    # Wikipedia harmonization
    "wiki_detention_table", "Wikipedia harmonization",
    "Scraped pinned revision of the Wikipedia \"List of immigrant detention sites\" wikitable. Broad historical table. **cue = \"never\"**.",

    "wiki_detention_table_current", "Wikipedia harmonization",
    "Current live revision of the Wikipedia table. **cue = \"never\"**; update oldid in `_targets.R` after article edits.",

    "wiki_match_table", "Wikipedia harmonization",
    "City/state alias matches between ICE FY26 facility names and Wikipedia table names.",

    "facilities_fy26_wiki_search", "Wikipedia harmonization",
    "Wikipedia API search results for each FY26 facility name. **cue = \"never\"**.",

    "contractors_patch_file", "Wikipedia harmonization",
    "Tracks `data/contractors-patch-fy26.csv` for changes.",

    "facilities_fy26_wiki", "Wikipedia harmonization",
    "FY26 facilities with `wiki_match`, `wiki_slug`, and `management` columns. Applies slug overrides, contractors patch, fl17 management backfill, and standardization.",

    "canonical_wiki_match", "Wikipedia harmonization",
    "All canonical facilities matched to Wikipedia articles via 4-pass matching (direct name, city/state alias, manual, external API).",

    "fy26_wikitable", "Wikipedia harmonization",
    "MediaWiki table markup for active facilities in the Wikipedia list article.",

    "closed_wikitable", "Wikipedia harmonization",
    "MediaWiki table markup for closed facilities in the Wikipedia list article.",

    # Source presence and outputs
    "source_presence", "Source presence and outputs",
    "One row per canonical facility (all ID ranges) with boolean flags for each data source (ICE stats, DMCP, DDP, Marshall, Vera, geocoded, etc.).",

    "saved_files", "Source presence and outputs",
    "Exported RDS + CSV files written to `data/` (crosswalk, presence, panel, source_presence).",

    "facility_summary_report", "Source presence and outputs",
    "Rendered `facility-summary.qmd` Quarto report. Re-renders when upstream targets change.",

    "geocoding_divergence_report", "Source presence and outputs",
    "Rendered `geocoding-divergence.qmd`; maps and tables of Google vs. source coordinate divergences.",

    "ddp_comparison_report", "Source presence and outputs",
    "Rendered `ddp-comparison.qmd` locally; review before deploying to quarto website.",

    "ddp_comparison_export", "Source presence and outputs",
    "Exports 11 RDS files to `data/ddp-comparison-export/` for deploying the DDP comparison blog post. **cue = \"never\"**.",

    "targets_catalog", "Source presence and outputs",
    "Auto-generates `data/targets-catalog.md` with hand-maintained descriptions and current dimensions."
  )
}

# ── Section ordering ─────────────────────────────────────────────────────────

catalog_section_order <- function() {
  c("Core annual stats pipeline",
    "Geocoding",
    "DMCP supplemental listings",
    "DDP daily population data",
    "Unified DETLOC lookup",
    "Hold facility and ERO integration",
    "Marshall Project locations",
    "Vera Institute facility metadata",
    "Wikipedia harmonization",
    "Source presence and outputs")
}

# ── Dimension helper ─────────────────────────────────────────────────────────

target_dimensions <- function(name) {
  obj <- tryCatch(targets::tar_read_raw(name), error = function(e) NULL)
  if (is.null(obj)) return("")
  if (is.data.frame(obj)) return(paste0(nrow(obj), " \u00d7 ", ncol(obj)))
  if (is.list(obj))       return(paste0("list (", length(obj), ")"))
  if (is.character(obj))  return(paste0("char (", length(obj), ")"))
  paste0(class(obj)[1])
}

# ── Generate catalog ─────────────────────────────────────────────────────────

generate_targets_catalog <- function(path = here::here("data/targets-catalog.md")) {
  descs     <- target_descriptions()
  sections  <- catalog_section_order()
  manifest  <- targets::tar_manifest()

  # Flag targets not yet described
  undescribed <- setdiff(manifest$name, descs$target)
  if (length(undescribed) > 0) {
    # Exclude the catalog target itself
    undescribed <- setdiff(undescribed, "targets_catalog")
    if (length(undescribed) > 0) {
      message("Targets missing from catalog descriptions: ",
              paste(undescribed, collapse = ", "))
    }
  }

  # Build dimensions column
  descs$size <- vapply(descs$target, target_dimensions, character(1))

  # Enforce section ordering
  descs$section <- factor(descs$section, levels = sections)

  # YAML front matter gives the file a title so that rendering it inside the
  # quarto website project resolves the `{{< meta title >}}` in the project's
  # `pagetitle` setting instead of emitting "Unknown meta key title" warnings.
  lines <- c(lines,
    "---",
    'title: "Pipeline Targets Catalog"',
    "---",
    "",
    "# Pipeline Targets Catalog",
    "",
    paste0("*Auto-generated on ", Sys.Date(),
           ". Descriptions are hand-maintained in `R/catalog.R`.*"),
    "",
    "All targets can be loaded with `tar_load(target_name)` or `tar_read(target_name)`.",
    "Run the pipeline with `tar_make()`. Visualize dependencies with `tar_visnetwork()`.",
    ""
  )

  for (sec in sections) {
    sec_rows <- descs[descs$section == sec, , drop = FALSE]
    if (nrow(sec_rows) == 0) next

    lines <- c(lines,
      paste0("## ", sec),
      "",
      "| Target | Size | Description |",
      "|--------|------|-------------|"
    )

    for (i in seq_len(nrow(sec_rows))) {
      row <- sec_rows[i, ]
      lines <- c(lines, paste0(
        "| `", row$target, "` | ", row$size, " | ", row$description, " |"
      ))
    }

    lines <- c(lines, "")
  }

  writeLines(lines, path)
  message("Wrote ", path)
  path
}
