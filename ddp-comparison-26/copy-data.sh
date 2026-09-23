#!/bin/bash
# copy-data.sh
# Copies pre-computed data files needed to render the FY26 DDP comparison post.
# Run from the post directory: posts/ddp-comparison-26/
#
# To regenerate the export files, run in the ice-detention project:
#   targets::tar_invalidate(ddp_fy26_comparison_export); targets::tar_make(names = ddp_fy26_comparison_export)
#
# Source: ice-detention project at ~/Dropbox/R/ice-detention/

SRC="$HOME/Dropbox/R/ice-detention/data/ddp-comparison-export-fy26"
DEST="$(dirname "$0")/data"

mkdir -p "$DEST"

for f in "$SRC"/*.rds; do
  cp "$f" "$DEST/"
done

echo "Copied RDS files to $DEST/"
ls -lh "$DEST/"*.rds
