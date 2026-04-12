# Handling DETLOC and Canonical ID Edge Cases

This note documents two recurring edge cases that arise when a new ICE data release (annual stats spreadsheet or DDP update) introduces facilities that the pipeline can't resolve automatically. Both require small code edits followed by a pipeline rebuild.

---

## Case A — Missing DETLOC (examples: canonical IDs 146, 229)

**What happens:** A facility appears in the ICE annual stats with a canonical ID correctly assigned by the crosswalk, but its `detloc` column is `NA` in `fy26b` and downstream outputs. This occurs when the DDP detention facility code exists (e.g., `FULCJIN`, `NEMCCOI`) but the DDP facility name differs too much from the ICE annual stats name for the fuzzy matcher to link them, and neither Vera nor DMCP provided a DETLOC for that facility.

**How to detect:**
```r
fy26b |>
  dplyr::filter(is.na(detloc)) |>
  dplyr::select(canonical_id, facility_name, facility_city, facility_state)

# Then check whether a DDP code exists:
ddp_new |>
  dplyr::distinct(detention_facility_code, detention_facility) |>
  dplyr::filter(stringr::str_detect(tolower(detention_facility), "keyword"))
```

**How to fix:**

1. **`R/crosswalk.R` — `build_facility_roster()`:** Add the confirmed (`canonical_id`, `detloc`) pair to the `detloc_fills` tribble (the "DETLOC fills" section around line 591):

    ```r
    146L, "FULCJIN",   # Fulton County Jail Indiana
    229L, "NEMCCOI",   # Mccook Detention Center (NE)
    ```

2. **`R/vera-institute.R` — `vera_detloc_matches()`:** Add the same pair with source `"ddp_name"` so Vera facility data also picks it up:

    ```r
    146L, "FULCJIN", "ddp_name",
    229L, "NEMCCOI", "ddp_name",
    ```

3. **Rebuild:**

    ```r
    targets::tar_invalidate("detloc_lookup")
    targets::tar_make()
    ```

    `tar_invalidate("detloc_lookup")` is sufficient because `detloc_lookup` depends on `build_detloc_lookup()` which draws from `detloc_lookup_full`, which in turn pulls `ddp_facility_canonical` and `hold_canonical_data`. The DETLOC fill in `build_facility_roster()` is upstream of `facility_roster` and the saved CSV/RDS outputs; those rebuild automatically when `detloc_lookup` is invalidated.

---

## Case B — False canonical-ID merge (example: canonical ID 401, Dilley Processing Single Adult Female)

**What happens:** A genuinely new facility at an address ICE already reports gets fuzzy-merged with an existing facility by the crosswalk (because address similarity ≥ 0.80), so `fy26b` assigns it the wrong canonical ID. In this case, "Dilley Processing Single Adult Female" (DILLSAF, a new single-adult facility on the Dilley campus) was collapsed into canonical ID 366 (South Texas Family Residential Center, STFRCTX) because both share the same address.

The DDP side already had DILLSAF registered correctly as canonical 401 in `ddp_manual_strong_matches()`; only the ICE annual stats side was wrong.

**How to detect:**
```r
# Does the ICE name appear in fy26b under a different canonical ID than expected?
fy26b |>
  dplyr::filter(stringr::str_detect(tolower(facility_name), "keyword")) |>
  dplyr::select(facility_name, canonical_id, detloc)

# Does the DDP side already have a separate canonical ID?
ddp_canonical_map |>
  dplyr::filter(detloc == "DILLSAF") |>
  dplyr::select(detloc, canonical_id, match_type)
```

**How to fix:**

1. **`R/ddp.R` — `ddp_manual_strong_matches()`:** Confirm the DDP entry exists (or add it) so the DETLOC is registered under the correct canonical ID:

    ```r
    401L, "DILLSAF", "DILLEY PROCESSING SINGLE FEMALE", NA,
    ```

2. **`R/ddp.R` — `build_fy26b()`, `force_patches` tribble:** Add an entry to override the crosswalk's ID assignment even when the crosswalk has already assigned an ID (use `force_patches`, not `fill_only_patches`, which only fires when `canonical_id` is NA):

    ```r
    "Dilley Processing Single Adult Female", 401L
    ```

3. **`R/vera-institute.R` — `vera_detloc_matches()`:** Register the DDP-sourced DETLOC so Vera metadata also resolves correctly:

    ```r
    401L, "DILLSAF", "ddp_name",
    ```

4. **Rebuild:**

    ```r
    targets::tar_invalidate("detloc_lookup")
    targets::tar_make()
    ```

    This rebuilds `detloc_lookup` and all downstream targets including `fy26b`, `unmatched_fy26`, `facility_roster`, and saved outputs.

---

## Choosing `fill_only_patches` vs `force_patches`

Both live in `build_fy26b()` in `R/ddp.R` and accept `(facility_name, patch_id)` rows.

| Situation | Use |
|---|---|
| Crosswalk assigned `NA` (facility not in the frozen registry) | `fill_only_patches` — fires only when `canonical_id` is NA |
| Crosswalk assigned the **wrong** ID (e.g., merged with a same-address neighbor) | `force_patches` — overwrites regardless of current value |

Prefer `fill_only_patches` unless you have confirmed a bad merge; `force_patches` is a stronger override and should be paired with a comment explaining why the crosswalk was wrong.
