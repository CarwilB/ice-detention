library(targets)
library(dplyr)
library(stringdist)

# DDP distinct names per detloc
ddp_names <- tar_read(ddp_raw) |>
  distinct(detloc = detention_facility_code, ddp_name = detention_facility)

# Map display names (canonical_name shown in popups)
map_names <- expanded_map_geocoded |>
  select(canonical_id, map_name = canonical_name, detloc)

# Join via detloc
ddp_map_name_diffs <- tar_read(detloc_lookup_complete) |>
  select(canonical_id, detloc) |>
  inner_join(ddp_names, by = "detloc") |>
  inner_join(map_names, by = c("canonical_id", "detloc")) |>
  mutate(
    osa_dist = stringdist(tolower(ddp_name), tolower(map_name), method = "osa"),
    lv_pct   = round(osa_dist / pmax(nchar(ddp_name), nchar(map_name)), 2)
  ) |>
  filter(ddp_name != map_name) |>
  arrange(desc(osa_dist)) |>
  select(detloc, canonical_id, ddp_name, map_name, osa_dist, lv_pct)

dpp_map_name_diffs

library(dplyr)
library(stringdist)

word_jaccard_dist <- function(a, b) {
  wa <- strsplit(tolower(a), "\\s+")[[1]]
  wb <- strsplit(tolower(b), "\\s+")[[1]]
  n_intersect <- length(intersect(wa, wb))
  n_union     <- length(union(wa, wb))
  if (n_union == 0) return(0)
  1 - n_intersect / n_union
}

ddp_map_j_diffs <- tar_read(detloc_lookup_complete) |>
  select(canonical_id, detloc) |>
  inner_join(ddp_names, by = "detloc") |>
  inner_join(map_names, by = c("canonical_id", "detloc")) |>
  filter(tolower(ddp_name) != tolower(map_name)) |>
  rowwise() |>
  mutate(word_jaccard = round(word_jaccard_dist(ddp_name, map_name), 2)) |>
  ungroup() |>
  arrange(desc(word_jaccard)) |>
  select(detloc, canonical_id, ddp_name, map_name, word_jaccard)
