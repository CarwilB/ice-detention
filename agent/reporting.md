` tag per the skill instructions, but since this is a pipeline element that needs to use `tar_read()`, let me write it directly as a file.Let me verify the pipeline parses correctly before you run it.`tarchetypes` isn't installed anywhere. It's listed in `renv.lock` as a dependency but hasn't been installed yet. You'll need to install it:

```r
renv::install("tarchetypes")
```

In the meantime, let me verify the rest of the pipeline parses by temporarily commenting out the `tar_quarto()` call and the `library(tarchetypes)` line.The FY26 Dropbox placeholder is still blocking the import functions from loading. Let me check if the functions loaded before the error:Both functions are loaded correctly. `save_outputs` now takes 4 arguments including `source_presence`, and `build_source_presence` exists.

The FY26 Dropbox placeholder is a separate issue — once that file syncs, everything should work. Let me also check that the `.qmd` references the right target names:Here's what was created/modified:

**New files:**
- `facility-summary.qmd` — Quarto report with 6 sections: overview, active/closed, facility types (table + bar chart + stacked time series), source coverage summary, sources-per-facility histogram, source overlap by ID range, and coverage gaps

**Modified files:**
- `R/crosswalk.R` — added `build_source_presence()` (builds the canonical ID × source boolean matrix) and extended `save_outputs()` to write `source_presence.rds/.csv`
- `_targets.R` — added `library(tarchetypes)`, `source_presence` target, updated `saved_files` to pass `source_presence`, and added `tar_quarto(facility_summary_report, "facility-summary.qmd")`

**Before running `tar_make()`**, two things need resolving:

1. **Install tarchetypes**: `renv::install("tarchetypes")` then `renv::snapshot()`
2. **FY26 Dropbox placeholder**: the 10-byte stub at `data/ice/FY26_detentionStats02022026.xlsx` needs to sync to the full file

Implemented facility summary report: `build_source_presence()`, `source_presence` target, and `facility-summary.qmd`

Captured the `data/` directory listing and updated all file path references across 10 files after reorganizing raw data into source-specific subdirectories (`data/ice/`, `data/ddp/`, `data/marshall/`). Discussed `data-raw/` and CRAN conventions. Diagnosed a `tar_make()` error caused by a Dropbox smart sync placeholder on the FY26 XLSX. Planned and implemented a facility summary Quarto report as a targets pipeline element: added `build_source_presence()` to `R/crosswalk.R`, a `source_presence` target to `_targets.R`, extended `save_outputs()`, and created `facility-summary.qmd` wired in via `tar_quarto()`.