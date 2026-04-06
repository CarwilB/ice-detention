# Diagnostic views of vera_type_overrides() applied to vera_facilities.
# Run interactively after `tar_load(vera_facilities)` or sourcing vera-institute.R.

# ── Structured list of override detloc codes by category ──────────────────

# vera_overrides <- list()
#
# vera_overrides$county_jail <- c(
#   "ABIRJVA", "ANDERSC", "BARTOGA", "BAYCOFL", "BREVDFL", "BROWNWI",
#   "CHFLDVA", "COLUMFL", "EPCDFTX", "FCLT8CA", "FLGLRFL", "FNDDUWI",
#   "FRANKPA", "GCPFCKS", "GOODCID", "JACKSTN", "LASALTX", "MRREGVA",
#   "NASTRNY", "OSCEOFL", "PIERCND", "POTTRTX", "PUTMAFL", "SALINNE",
#   "SMNOLFL", "SROSAFL", "STJONFL", "SUMTEFL", "SUWANFL", "TGKJLFL",
#   "UVALDTX", "WALTNFL"
# )
#
# vera_overrides$federal_prison <- c("BOPPET", "BOPMRG")
#
# vera_overrides$dedicated <- c("FLBAKCI", "BPC", "BIINCCO", "CVANXCA")
#
# vera_overrides$hold_staging <- c("IBPSMIA", "SMAHOLD")
#
# vera_overrides$medical <- c("UPMCAPA")
#
# vera_overrides$family <- c("NRJDCVA")
#
# vera_overrides$all <- unlist(vera_overrides, use.names = FALSE)

vera_overrides <- list()

vto <- vera_type_overrides()
vera_overrides <- vto |>
  mutate(
    list_name = case_when(
      type_grouped_corrected == "Non-Dedicated" ~ "county_jail",
      type_grouped_corrected == "Federal"       ~ "federal_prison",
      type_grouped_corrected == "Dedicated"     ~ "dedicated",
      type_grouped_corrected == "Hold/Staging"  ~ "hold_staging",
      type_grouped_corrected == "Medical"       ~ "medical",
      type_grouped_corrected == "Family/Youth"  ~ "family",
      .default = type_grouped_corrected
    )
  ) |>
  with(split(detloc, list_name))

vera_overrides$all <- unlist(vera_overrides, use.names = FALSE)


# ── Filtered views per category ───────────────────────────────────────────

vera_override_views <- vera_overrides |>
  purrr::discard_at("all") |>
  purrr::map(~ {
    vera_facilities |>
      dplyr::filter(detloc %in% .x) |>
      dplyr::select(detloc, type_detailed, type_grouped,
                    type_detailed_corrected, type_grouped_corrected,
                    facility_name)
  })

# Print all categories
purrr::iwalk(vera_override_views, ~ {
  cat("\n=== ", .y, " (", nrow(.x), " facilities) ===\n", sep = "")
  print(.x)
})


# ── Diagnostic grid: original types × override categories ─────────────────

vera_override_grid <- vera_facilities |>
  dplyr::filter(detloc %in% vera_overrides$all) |>
  dplyr::select(detloc, type_detailed, type_grouped,
                type_detailed_corrected, type_grouped_corrected) |>
  dplyr::mutate(
    override_category = purrr::map_chr(detloc, ~ {
      for (cat_name in names(vera_overrides)) {
        if (cat_name == "all") next
        if (.x %in% vera_overrides[[cat_name]]) return(cat_name)
      }
      return(NA_character_)
    })
  ) |>
  dplyr::mutate(
    orig_combo = paste(type_detailed, "|", type_grouped),
    corrected_combo = paste(type_detailed_corrected, "|", type_grouped_corrected)
  ) |>
  dplyr::count(orig_combo, corrected_combo, override_category) |>
  tidyr::pivot_wider(
    names_from = override_category,
    values_from = n,
    values_fill = 0
  ) |>
  tidyr::separate(orig_combo, into = c("type_detailed", "type_grouped"), sep = " \\| ") |>
  tidyr::separate(corrected_combo, into = c("type_detailed_corrected", "type_grouped_corrected"), sep = " \\| ") |>
  dplyr::arrange(type_grouped_corrected, type_detailed_corrected)

print(vera_override_grid, n = Inf)

cat("\n=== Summary ===\n")
cat("Total overridden facilities:", sum(vera_override_grid[, -(1:4)]), "\n")
