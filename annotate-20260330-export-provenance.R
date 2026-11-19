# One-off (2026-10-03): retroactively attach provenance metadata to the
# frozen through-March FY26 comparison export
# (data/ddp-comparison-export-fy26-20260330/), restored from the deployed post
# mirror (posts/ddp-comparison-26/, data files finalized 2026-04-13).
#
# Uses build_fy26_export_provenance() from R/ddp.R — the same builder that
# export_ddp_fy26_comparison_data() applies at export time for future runs.
# Re-saves each RDS with a `provenance` attribute (inspect with
# attributes(obj)$provenance) and writes a companion _provenance.json.

library(here)
source(here::here("R/ddp.R"))

export_dir <- here::here("data", "ddp-comparison-export-fy26-20260330")

provenance <- build_fy26_export_provenance(
  ddp_source_file   = "data/ddp/facilities-daily-population-latest_20260330.parquet",
  ddp_release        = "20260330",
  ddp_data_coverage  = "2022-10-01 to 2026-03-10",
  pipeline_target    = "ddp_fy26_comparison_export_20260330",
  sparkline_end      = "2026-03-10",
  ddp_source_note    = "DDP-published daily-population file (20260330 release, data through 2026-03-10)",
  ddp_file_url       = "https://github.com/deportationdata/ice/blob/a63d3d9428/data/facilities-daily-population-latest.parquet",
  computed           = "2026-04-13 (original export for the published post; approximate - data files finalized 2026-04-13)"
)

# The archived directory also holds peak_fy26.rds, the pre-sparkline version
# saved by earlier export runs; describe it alongside the current 8 datasets
peak_meta <- provenance$files$peak_fy26_w_sparklines
peak_meta$file        <- "peak_fy26.rds"
peak_meta$dataset     <- "peak_fy26"
peak_meta$description <- paste(
  peak_meta$description,
  "(pre-sparkline version; superseded by peak_fy26_w_sparklines in current exports)"
)
provenance$files$peak_fy26 <- peak_meta

rds_names <- sub("\\.rds$", "", list.files(export_dir, pattern = "\\.rds$"))
stopifnot(all(rds_names %in% names(provenance$files)))

for (nm in rds_names) {
  path <- file.path(export_dir, paste0(nm, ".rds"))
  obj <- readRDS(path)
  attr(obj, "provenance") <- provenance$files[[nm]]
  saveRDS(obj, path)
}

jsonlite::write_json(
  provenance,
  file.path(export_dir, "_provenance.json"),
  auto_unbox = TRUE, pretty = TRUE
)

message("Annotated ", length(rds_names), " RDS files + wrote _provenance.json in ", export_dir)
