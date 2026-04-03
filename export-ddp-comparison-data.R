# export-ddp-comparison-data.R
#
# DEPRECATED: This export is now a pipeline target (ddp_comparison_export).
#
# Workflow:
#   1. tar_make(ddp_comparison_report)  — renders ddp-comparison.qmd locally
#   2. Review the local HTML output
#   3. tar_make(ddp_comparison_export)  — exports 11 RDS files to data/ddp-comparison-export/
#   4. Run copy-data.sh in the quarto website post directory to deploy
#
# The export function lives in R/ddp.R as export_ddp_comparison_data().

message("This script is deprecated. Use the pipeline targets instead:")
message("  targets::tar_make(ddp_comparison_report)   # render locally")
message("  targets::tar_make(ddp_comparison_export)    # export RDS for deployment")
