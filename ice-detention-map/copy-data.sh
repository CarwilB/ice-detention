#!/bin/bash
# copy-data.sh
# Copies the minimum data files needed to render the ICE detention map post.
# Run from the post directory: posts/ice-detention-map/
#
# Source: ice-detention project at ~/Dropbox (Personal)/R/ice-detention/

SRC="$HOME/Dropbox/R/ice-detention"
DEST="$(dirname "$0")/data"

mkdir -p "$DEST"

cp "$SRC/data/facilities_geocoded_full.rds" "$DEST/"
cp "$SRC/data/facility_presence.rds"        "$DEST/"
cp "$SRC/data/facilities_panel.rds"         "$DEST/"

echo "Copied 3 RDS files to $DEST/"
ls -lh "$DEST/"*.rds
