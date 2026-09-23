#!/bin/bash
# copy-data.sh
# Copies pre-computed data files needed to render the DDP comparison post.
# Run from the post directory: posts/ddp-comparison/
#
# To regenerate the export files, run the export-ddp-comparison-data.R script
# in the ice-detention project first.
#
# Source: ice-detention project at ~/Dropbox (Personal)/R/ice-detention/

SRC="$HOME/Dropbox/R/ice-detention/data/ddp-comparison-export"
DEST="$(dirname "$0")/data"
echo "SRC=$SRC"
echo "DEST=$DEST"

mkdir -p "$DEST"

for f in "$SRC"/*.rds; do
  cp "$f" "$DEST/"
done

echo "Copied RDS files to $DEST/"
ls -lh "$DEST/"*.rds
