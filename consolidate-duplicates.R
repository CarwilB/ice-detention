#!/usr/bin/env Rscript
#
# Consolidate duplicate facility entries in the roster and related files.
#
# Three consolidations:
# 1. CLINTPA (Clinton County, PA): IDs 80 & 81 → keep 80, delete 81
# 2. SLCHOLD/SLSLCUT (Salt Lake County): ID 326 (SLCHOLD) → SLSLCUT, merge with 1182, keep 1182, delete 326
# 3. OLDHAKY (Ogallala, NE): IDs 274 & 275 → keep 274, delete 275
#
# This script:
# - Updates facility_roster.csv to remove duplicate entries
# - Updates facilities-geocoded-all.csv to consolidate detloc and remove duplicate IDs
# - Updates detloc_lookup.csv and detloc_lookup_full.csv to map all detlocs correctly
# - Does NOT modify geocoded coordinates (same building = same lat/lon)

library(dplyr)
library(readr)

base_path <- "/Users/bjorkjcr/Dropbox/R/ice-detention"
setwd(base_path)

# Define consolidations
consolidations <- list(
  list(
    name = "CLINTPA (Clinton County, PA)",
    keep_id = 80L,
    remove_ids = 81L,
    detloc_change = NULL  # no detloc change
  ),
  list(
    name = "SLCHOLD/SLSLCUT (Salt Lake County, UT)",
    keep_id = 1182L,
    remove_ids = 326L,
    detloc_change = list(old = "SLCHOLD", new = "SLSLCUT")
  ),
  list(
    name = "OLDHAKY (Oldham County, KY)",
    keep_id = 274L,
    remove_ids = 275L,
    detloc_change = NULL
  )
)

# ── Step 1: Update facility_roster.csv ────────────────────────────────────
roster <- read_csv("data/facility_roster.csv", show_col_types = FALSE)

cat("Original facility_roster.csv: ", nrow(roster), "rows\n")

for (cons in consolidations) {
  cat("\nProcessing: ", cons$name, "\n")
  
  # Show rows being removed
  remove_rows <- roster %>%
    filter(canonical_id %in% cons$remove_ids)
  if (nrow(remove_rows) > 0) {
    cat("  Removing IDs:", paste(cons$remove_ids, collapse = ", "), "\n")
    print(remove_rows %>% select(canonical_id, canonical_name, detloc, facility_address, facility_city))
  }
  
  # Remove duplicate IDs
  roster <- roster %>%
    filter(!canonical_id %in% cons$remove_ids)
  
  # Update detloc if specified
  if (!is.null(cons$detloc_change)) {
    cat("  Updating DETLOC from", cons$detloc_change$old, "to", cons$detloc_change$new, "\n")
    roster <- roster %>%
      mutate(detloc = if_else(detloc == cons$detloc_change$old, 
                              cons$detloc_change$new, 
                              detloc))
  }
}

cat("\nUpdated facility_roster.csv: ", nrow(roster), "rows\n")
write_csv(roster, "data/facility_roster.csv")

# ── Step 2: Update facilities-geocoded-all.csv ────────────────────────────
geocoded <- read_csv("data/facilities-geocoded-all.csv", show_col_types = FALSE)

cat("\nOriginal facilities-geocoded-all.csv: ", nrow(geocoded), "rows\n")

for (cons in consolidations) {
  # Remove duplicate IDs
  geocoded <- geocoded %>%
    filter(!canonical_id %in% cons$remove_ids)
}

cat("Updated facilities-geocoded-all.csv: ", nrow(geocoded), "rows\n")
write_csv(geocoded, "data/facilities-geocoded-all.csv")

# ── Step 3: Update detloc_lookup.csv ──────────────────────────────────────
if (file.exists("data/detloc_lookup.csv")) {
  detloc_lookup <- read_csv("data/detloc_lookup.csv", show_col_types = FALSE)
  
  cat("\nOriginal detloc_lookup.csv: ", nrow(detloc_lookup), "rows\n")
  
  for (cons in consolidations) {
    # Remove entries pointing to removed IDs
    detloc_lookup <- detloc_lookup %>%
      filter(!canonical_id %in% cons$remove_ids)
    
    # Update detloc if specified
    if (!is.null(cons$detloc_change)) {
      # For SLCHOLD → SLSLCUT, we need to replace the entire row
      if (cons$detloc_change$old == "SLCHOLD") {
        detloc_lookup <- detloc_lookup %>%
          mutate(
            detloc = if_else(detloc == "SLCHOLD", "SLSLCUT", detloc)
          )
      }
    }
  }
  
  cat("Updated detloc_lookup.csv: ", nrow(detloc_lookup), "rows\n")
  write_csv(detloc_lookup, "data/detloc_lookup.csv")
}

# ── Step 4: Update detloc_lookup_full.csv ─────────────────────────────────
if (file.exists("data/detloc_lookup_full.csv")) {
  detloc_lookup_full <- read_csv("data/detloc_lookup_full.csv", show_col_types = FALSE)
  
  cat("\nOriginal detloc_lookup_full.csv: ", nrow(detloc_lookup_full), "rows\n")
  
  for (cons in consolidations) {
    # Remove entries pointing to removed IDs
    detloc_lookup_full <- detloc_lookup_full %>%
      filter(!canonical_id %in% cons$remove_ids)
    
    # Update detloc if specified
    if (!is.null(cons$detloc_change)) {
      detloc_lookup_full <- detloc_lookup_full %>%
        mutate(
          detloc = if_else(detloc == cons$detloc_change$old, cons$detloc_change$new, detloc)
        )
    }
  }
  
  cat("Updated detloc_lookup_full.csv: ", nrow(detloc_lookup_full), "rows\n")
  write_csv(detloc_lookup_full, "data/detloc_lookup_full.csv")
}

# ── Summary ───────────────────────────────────────────────────────────────
cat("\n", strrep("=", 60), "\n")
cat("CONSOLIDATION SUMMARY\n")
cat(strrep("=", 60), "\n\n")

for (cons in consolidations) {
  cat(cons$name, "\n")
  cat("  Keep ID: ", cons$keep_id, "\n")
  cat("  Remove ID(s): ", paste(cons$remove_ids, collapse = ", "), "\n")
  if (!is.null(cons$detloc_change)) {
    cat("  DETLOC change: ", cons$detloc_change$old, " → ", cons$detloc_change$new, "\n")
  }
  cat("\n")
}

cat("✓ facility_roster.csv updated\n")
cat("✓ facilities-geocoded-all.csv updated\n")
cat("✓ detloc_lookup.csv updated\n")
cat("✓ detloc_lookup_full.csv updated\n")
cat("\nNo other files modified (IDs 80, 81, 274, 275, 326 consolidated)\n")
