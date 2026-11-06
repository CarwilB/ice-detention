# TODO: After figuring out relationships in location exploration script,
# put into state-arrest script a new parse county landmark (using those if statements)

library(dplyr)
library(stringr)
targets::tar_load(arrests_raw)

# Match the report's cutoff
il_arrests_raw <- arrests_raw |>
  dplyr::filter(apprehension_state == "ILLINOIS",
                apprehension_date >= as.Date("2025-01-20"))

il_arrests_raw |>
  count(apprehension_site_landmark) |>
  arrange(desc(n)) |>
  print(n=50)
il_arrests_raw |>
  count(apprehension_site_landmark) |>
  arrange(desc(n)) |> mutate(notes = " ") |>
  head(30) |>
  kableExtra::kable()

il_arrests_raw |>
  dplyr::filter(str_detect(apprehension_site_landmark, "NON-SPECIFIC")) |>
  nrow()

il_arrests_raw |> dplyr::filter(str_detect(apprehension_site_landmark, "NON-SPECIFIC")) |> count(apprehension_site_landmark) |>
  arrange(desc(n)) |>
  print(n=50)

il_arrests_raw |>
  dplyr::filter(str_detect(apprehension_site_landmark, "NON-SPECIFIC")) |>
  count(apprehension_site_landmark) |>
  mutate(aor_code = str_sub(apprehension_site_landmark, 1,3)) |>
  arrange(desc(n)) -> il_general_areas
pull(il_general_areas, aor_code) -> il_general_area_codes


# FUGITIVE OPERATIONS ON STREET
# GENERAL AREA, NON-SPECIFIC
# US Penitentiary
# ICE OFFICE
# STREET ARREST
# FUGITIVE OPERATIONS ON STREET

il_arrests_raw <- il_arrests_raw |>
  dplyr::mutate(loc_type = case_when(
    str_detect(apprehension_site_landmark, "FUGITIVE OPERATIONS ON STREET") ~ "FUGITIVE OPS",
    str_detect(apprehension_site_landmark, "GENERAL AREA, NON-SPECIFIC") ~ "GENERAL AREA, NON-SPECIFIC",
    str_detect(apprehension_site_landmark, "GENERAL AREA NON-SPECIFIC") ~ "GENERAL AREA, NON-SPECIFIC",
    str_detect(apprehension_site_landmark, "US Penitentiary") ~ "US Penitentiary",
    str_detect(apprehension_site_landmark, "IL STATE DOC") ~ "State Prison",
    str_detect(apprehension_site_landmark, "ICE OFFICE") ~ "ICE OFFICE",
    str_detect(apprehension_site_landmark, "STREET ARREST") ~ "STREET ARREST",
    str_detect(toupper(apprehension_site_landmark), "COUNTY") ~ "COUNTY",
    TRUE ~ "OTHER"
  ))

il_arrests_raw |>
  count(loc_type) |>
  arrange(desc(n)) |>
  print(n=50)

il_arrests_raw |>
  dplyr::filter(loc_type == "OTHER") |>
  count(apprehension_site_landmark) |>
  arrange(desc(n)) |>
  print(n=50)

il_arrests_raw |>
  dplyr::filter(loc_type == "FUGITIVE OPS") |>
  count(apprehension_site_landmark) |>
  arrange(desc(n)) |>
  print(n=50)

il_arrests_raw |>
  dplyr::filter(loc_type == "State Prison") |>
  count(apprehension_site_landmark) |>
  arrange(desc(n)) |>
  print(n=50)


# EDA cont.

il_arrests_raw <- il_arrests_raw |>
  dplyr::mutate(
    lm = toupper(apprehension_site_landmark),
    loc_type = case_when(
      is.na(lm)                                        ~ "MISSING",
      str_detect(lm, "CHICAGO FIELD OFFICE|ICE OFFICE") ~ "ICE OFFICE",
      str_detect(lm, "MCC|PENITENTIARY|THOMSON")       ~ "Federal Prison",
      str_detect(lm, "STATE DOC")                      ~ "State Prison",
      str_detect(lm, "O'HARE")                         ~ "Airport",
      str_detect(lm, "DISTRICT COURT")                 ~ "Court",
      str_detect(lm, "FUGITIVE OP.*COUNTY")            ~ "FUGITIVE OPS (county named)",
      str_detect(lm, "FUGITIVE OP")                    ~ "FUGITIVE OPS (no county)",
      str_detect(lm, "GENERAL (AREA,? )?NON-SPECIFIC") ~ "GENERAL AREA, NON-SPECIFIC",
      str_detect(lm, "STREET ARREST")                  ~ "STREET ARREST",
      str_detect(lm, "COUNTY")                         ~ "COUNTY",
      TRUE                                             ~ "OTHER"
    )
  )

il_arrests_raw |>
  count(loc_type) |>
  arrange(desc(n)) |>
  print(n=50)

# ── August 2026 release: apprehension city ─────────────────────────────────
# The Aug 2026 DDP arrests release adds apprehension_city_* (see
# https://deportationdata.org/docs/ice.html). Renamed columns vs. March:
# apprehension_site_landmark -> event_landmark,
# apprehension_state -> apprehension_state_filled_in.
# IDs link to detention-stays-latest_20260806.parquet (same release).
arr8 <- arrow::read_parquet(here::here("data/ddp/arrests-latest_20260806.parquet"))

il8 <- arr8 |>
  dplyr::filter(apprehension_state_filled_in == "ILLINOIS",
                apprehension_date >= as.Date("2025-01-20"))
nrow(il8)

# Landmark is blank far more often in this release; city is nearly complete
il8 |> count(event_landmark, sort = TRUE) |> mutate(pct = round(n / sum(n) * 100, 1)) |> head(10)
mean(is.na(il8$event_landmark))
mean(is.na(il8$apprehension_city_common_case))

# Cities behind "CHI GENERAL AREA, NON-SPECIFIC"
chi8 <- il8 |> dplyr::filter(str_detect(toupper(event_landmark), "^CHI GENERAL"))
chi8 |> count(apprehension_city_common_case, sort = TRUE) |>
  mutate(pct = round(n / sum(n) * 100, 1)) |> print(n = 30)

# ── City spelling variants ─────────────────────────────────────────────────
cities <- il8 |> count(apprehension_city_common_case, sort = TRUE)
nrow(cities)
# Candidate duplicates: same letters-only key after normalizing Saint/St, Mount/Mt, Fort/Ft
key <- function(x) x |> toupper() |>
  str_replace_all("\\bSAINT\\b", "ST") |> str_replace_all("\\bMOUNT\\b", "MT") |>
  str_replace_all("\\bFORT\\b", "FT") |> str_remove_all("[^A-Z]")
cities |> mutate(k = key(apprehension_city_common_case)) |>
  group_by(k) |> filter(n() > 1) |> arrange(k, desc(n)) |> print(n = 60)

# Typos: fuzzy-match the normalized keys. Edit distance 1 is almost always a
# typo; distance 2 also pairs real, different towns (Darien/Marion,
# East/West Chicago, Burbank/Urbana), so every pair was reviewed by hand.
city_keys <- cities |>
  mutate(k = key(apprehension_city_common_case)) |>
  group_by(k) |>
  summarise(name = first(apprehension_city_common_case), n = sum(n), .groups = "drop") |>
  dplyr::filter(!is.na(k), k != "")
tidyr::expand_grid(a = city_keys$k, b = city_keys$k) |>
  dplyr::filter(a < b) |>
  mutate(d = stringdist::stringdist(a, b, method = "osa")) |>
  dplyr::filter(d <= 2, nchar(a) >= 5) |>
  left_join(select(city_keys, a = k, name_a = name, n_a = n), by = "a") |>
  left_join(select(city_keys, b = k, name_b = name, n_b = n), by = "b") |>
  arrange(d, desc(pmax(n_a, n_b))) |>
  select(name_a, n_a, name_b, n_b, d) |>
  print(n = 150)

# Reviewed fixes: variant -> standard spelling. Left alone on purpose:
# Palestine (real IL village), Elk Grove vs Elk Grove Village (unclear),
# Indiana towns (La Porte, East Chicago, Chesterton) - a state issue, not spelling.
city_fixes <- tibble::tribble(
  ~variant,              ~city,
  # Saint/Mount/spacing/punctuation variants
  "Saint Charles",       "St. Charles",
  "Charles",             "St. Charles",
  "St. Charls",          "St. Charles",
  "East Saint Louis",    "East St. Louis",
  "Mt Prospect",         "Mount Prospect",
  "Mt. Prospect",        "Mount Prospect",
  "Desplaines",          "Des Plaines",
  "Des Plains",          "Des Plaines",
  "Downer's Grove",      "Downers Grove",
  "Downers Grokve",      "Downers Grove",
  "Oaklawn",             "Oak Lawn",
  "Roundlake",           "Round Lake",
  "Lasalle",             "La Salle",
  "Laporte",             "La Porte",
  "Bridge Port",         "Bridgeport",
  "O Fallon",            "O'Fallon",
  "Ofallon",             "O'Fallon",
  "Scott Airforce Base", "Scott Air Force Base",
  # Chicago
  "Chcago",   "Chicago", "Chgicago", "Chicago", "Chiacgo",  "Chicago",
  "Chiago",   "Chicago", "Chicaco",  "Chicago", "Chicafo",  "Chicago",
  "Chicao",   "Chicago", "Chicgao",  "Chicago", "Chiciago", "Chicago",
  "Chicagogo","Chicago",
  # Suburbs and downstate
  "Cicro",            "Cicero",            "Cisero",            "Cicero",
  "Auarora",          "Aurora",            "Auora",             "Aurora",
  "Elgih",            "Elgin",             "Elginc",            "Elgin",
  "Waukegun",         "Waukegan",          "Waukengan",         "Waukegan",
  "St. Waukegan",     "Waukegan",
  "Joilet",           "Joliet",            "Juliet",            "Joliet",
  "Palantine",        "Palatine",          "Paletine",          "Palatine",
  "Palentine",        "Palatine",
  "Addision",         "Addison",           "Adisson",           "Addison",
  "Benseville",       "Bensenville",       "Bensville",         "Bensenville",
  "Boilingbrook",     "Bolingbrook",       "Bolinsbook",        "Bolingbrook",
  "Springfiled",      "Springfield",
  "Arlinghton Heights","Arlington Heights",
  "Stokie",           "Skokie",
  "Wehaton",          "Wheaton",
  "Beywyn",           "Berwyn",            "Brewin",            "Berwyn",
  "Schamburg",        "Schaumburg",
  "Woodbridge",       "Woodridge",
  "Hlendale Heights", "Glendale Heights",
  "Propspect Heights","Prospect Heights",
  "Brideview",        "Bridgeview",
  "Grantie City",     "Granite City",
  "Kanakee",          "Kankakee",
  "Colllinsville",    "Collinsville",
  "Romeville",        "Romeoville",
  "Cheser",           "Chester",
  "Lamont",           "Lemont",
  "Elk Groove",       "Elk Grove",
  "Algoquin",         "Algonquin",
  "Calument City",    "Calumet City",      "Caulmet City",      "Calumet City",
  "Calument",         "Calumet",
  "Chesterson",       "Chesterton",
  "Villa Groves",     "Villa Grove",
  "Montogomery",      "Montgomery",
  "Caseyvile",        "Caseyville",
  "River Forrest",    "River Forest",
  "Hodgekins",        "Hodgkins",
  "Pinkneyville",     "Pinckneyville",
  "Weswetville",      "Westville",
  "Oak Bar",          "Oak Park"
)
stopifnot(!anyDuplicated(city_fixes$variant))

clean_il_city <- function(x) {
  x <- str_squish(x)
  x[toupper(x) %in% c("UNKNOWN", "UNKKNOWN", "UNKOWN")] <- NA_character_
  dplyr::coalesce(city_fixes$city[match(x, city_fixes$variant)], x)
}

il8 <- il8 |> mutate(city = clean_il_city(apprehension_city_common_case))

# Before vs after
c(raw = n_distinct(il8$apprehension_city_common_case), clean = n_distinct(il8$city))
il8 |> count(city, sort = TRUE) |> mutate(pct = round(n / sum(n) * 100, 1)) |> print(n = 30)

# Re-run the variant checks on the cleaned names; anything left needs review
il8 |> count(city) |> mutate(k = key(city)) |>
  group_by(k) |> dplyr::filter(n() > 1) |> arrange(k)

# ── Thomson and Broadview: custody transfers or community arrests? ─────────
# Thomson = USP Thomson (federal prison); Broadview = ICE processing center.
# apprehension_method_simple groups methods into At-Large / Custodial / Other / 287(g).
il8 |> count(apprehension_method_simple, sort = TRUE)

il8 |>
  dplyr::filter(city %in% c("Thomson", "Broadview")) |>
  count(city, apprehension_method, apprehension_method_simple) |>
  group_by(city) |>
  mutate(pct = round(n / sum(n) * 100, 1)) |>
  arrange(city, desc(n)) |>
  print(n = 30)

il8 |>
  dplyr::filter(city %in% c("Thomson", "Broadview")) |>
  count(city, event_landmark, sort = TRUE) |>
  group_by(city) |>
  slice_head(n = 5)

# Broadview "at-large" arrests: when did they happen?
il8 |>
  dplyr::filter(city == "Broadview", apprehension_method_simple == "At-Large Arrest") |>
  count(month = format(apprehension_date, "%Y-%m")) |>
  print(n = 20)

# Findings (Aug 2026 release, IL since 2025-01-20):
# Thomson (354): 99% custodial (Custodial Arrest 243, CAP Federal Incarceration 106)
#   -> transfers from USP Thomson, not community arrests.
# Broadview (367): 63% Non-Custodial (at-large), 36% Custodial. At-large ones
#   cluster in Oct 2025 (82) and Jan-Feb 2026 (91). 230 at-large arrests in a
#   village of ~8k (vs. 128 in Cicero, ~85k) suggests city may record the
#   processing site rather than the arrest location. Unresolved; flag to PI.

# ── Cities -> counties ─────────────────────────────────────────────────────
# Census 2023 cartographic boundary files, downloaded once by hand into
# data/census/ (not re-downloaded by this script):
#   https://www2.census.gov/geo/tiger/GENZ2023/shp/cb_2023_17_place_500k.zip
#   https://www2.census.gov/geo/tiger/GENZ2023/shp/cb_2023_us_county_500k.zip
# Overlaying places on counties gives each place's share of area by county.
library(sf)
read_zip_shp <- function(zip) {
  sf::st_read(paste0("/vsizip/", here::here("data/census", zip)), quiet = TRUE)
}
il_places   <- read_zip_shp("cb_2023_17_place_500k.zip") |> st_transform(5070)
il_counties <- read_zip_shp("cb_2023_us_county_500k.zip") |>
  dplyr::filter(STATEFP == "17") |>
  st_transform(5070)

place_county <- suppressWarnings(st_intersection(
    il_places |> select(place = NAME, place_type = NAMELSAD, place_geoid = GEOID),
    il_counties |> select(county = NAME))) |>
  mutate(area = as.numeric(st_area(geometry))) |>
  st_drop_geometry() |>
  group_by(place_geoid) |>
  mutate(share = area / sum(area)) |>
  ungroup() |>
  # drop slivers from boundary misalignment
  dplyr::filter(share >= 0.01)

# One row per place. multi_county = a second county holds >= 10% of the area
# (so Chicago, 99% Cook / 1% DuPage at O'Hare, counts as single-county).
city_county <- place_county |>
  group_by(place_geoid, place, place_type) |>
  arrange(desc(share), .by_group = TRUE) |>
  summarise(
    primary_county = first(county),
    primary_share  = round(first(share), 3),
    n_counties     = sum(share >= 0.10),
    counties       = paste0(county, " (", round(share * 100), "%)", collapse = ", "),
    .groups = "drop") |>
  mutate(k = key(place),
         multi_county = n_counties > 1,
         incorporated = !str_detect(place_type, "CDP$")) |>
  # Same name twice in IL (e.g. Willowbrook village, DuPage / Willowbrook CDP,
  # Will): prefer the incorporated place; flag if still tied
  group_by(k) |>
  arrange(desc(incorporated), .by_group = TRUE) |>
  mutate(name_tie = sum(incorporated == first(incorporated)) > 1) |>
  slice_head(n = 1) |>
  ungroup()

# Unmatched names worth fixing for the county lookup only: Chicago
# neighbourhoods, abbreviations, typos. Indiana/Missouri towns stay unmatched.
city_aliases <- tibble::tribble(
  ~city,                ~place,
  "Little Village",     "Chicago",
  "Avondale",           "Chicago",
  "Bucktown",           "Chicago",
  "Ravenswood",         "Chicago",
  "West Elsdon",        "Chicago",
  "Chicago Chi",        "Chicago",
  "Summit Argo",        "Summit",
  "Elk Grove",          "Elk Grove Village",
  "Arlington Hts",      "Arlington Heights",
  "Rolling Meadowschi", "Rolling Meadows",
  "Carpersville",       "Carpentersville",
  "Dixmoore",           "Dixmoor",
  "Lmilemont",          "Lemont"
)

il_city_county <- il8 |>
  count(city, sort = TRUE) |>
  left_join(city_aliases, by = "city") |>
  mutate(k = key(dplyr::coalesce(place, city))) |>
  select(-place) |>
  left_join(select(city_county, k, place, primary_county, primary_share,
                   multi_county, counties, name_tie), by = "k")
stopifnot(sum(il_city_county$n) == nrow(il8))

# Coverage
il_city_county |>
  summarise(arrests = sum(n),
            matched_pct = round(sum(n[!is.na(primary_county)]) / sum(n) * 100, 1),
            multi_county_pct = round(sum(n[multi_county %in% TRUE]) / sum(n) * 100, 1))

# Still unmatched (mostly out-of-state towns and vague entries)
il_city_counts_unmatched <- il_city_county |>
  dplyr::filter(is.na(primary_county), !is.na(city)) |>
  select(city, n)
il_city_counts_unmatched |> print(n = 50)

# Multi-county cities, by arrests
il_city_county |>
  dplyr::filter(multi_county %in% TRUE) |>
  select(city, n, counties) |>
  print(n = 40)

# Arrests by primary county
il_city_county |>
  dplyr::filter(!is.na(primary_county)) |>
  count(primary_county, wt = n, sort = TRUE) |>
  mutate(pct = round(n / sum(n) * 100, 1)) |>
  print(n = 20)

# ── Dot map: at-large arrests by city ──────────────────────────────────────
# Excludes custodial transfers (prisons/jails, e.g. USP Thomson), 287(g), and
# "Other". Each dot sits at a point inside the Census place.
library(ggplot2)

place_points <- il_places |>
  select(place_geoid = GEOID) |>
  st_point_on_surface()

at_large_by_city <- il8 |>
  dplyr::filter(apprehension_method_simple == "At-Large Arrest") |>
  count(city, name = "arrests") |>
  left_join(city_aliases, by = "city") |>
  mutate(k = key(dplyr::coalesce(place, city))) |>
  select(-place) |>
  left_join(select(city_county, k, place, place_geoid), by = "k")

# At-large arrests that can't be placed on the map
at_large_by_city |>
  summarise(total = sum(arrests),
            unplaced = sum(arrests[is.na(place_geoid)]),
            unplaced_pct = round(unplaced / total * 100, 1))

at_large_points <- place_points |>
  inner_join(dplyr::filter(at_large_by_city, !is.na(place_geoid)), by = "place_geoid") |>
  arrange(desc(arrests))

map_caption <- paste(
  "Custodial transfers excluded. Broadview (ICE processing center) may reflect",
  "processing rather than arrest location.\nSource: Deportation Data Project,",
  "Aug 2026 ICE arrests release; Census 2023 places."
)

# Statewide
ggplot() +
  geom_sf(data = il_counties, fill = NA, colour = "grey75", linewidth = 0.2) +
  geom_sf(data = at_large_points, aes(size = arrests), alpha = 0.5) +
  scale_size_area(max_size = 14, breaks = c(10, 100, 500, 2000)) +
  labs(title = "ICE at-large arrests in Illinois by city",
       subtitle = "Jan 20, 2025 - Aug 6, 2026",
       size = "Arrests", caption = map_caption) +
  theme(plot.caption.position = "plot", plot.caption = element_text(hjust = 0))

# Chicago area zoom (Cook + collar counties):
metro <- il_counties |>
  dplyr::filter(NAME %in% c("Cook", "DuPage", "Kane", "Lake", "McHenry", "Will", "Kendall"))
metro_box <- st_bbox(metro)

ggplot() +
  geom_sf(data = il_counties, fill = NA, colour = "grey75", linewidth = 0.3) +
  geom_sf(data = at_large_points, aes(size = arrests), alpha = 0.5) +
  ggrepel::geom_text_repel(
    data = head(at_large_points, 12), aes(label = place, geometry = geometry),
    stat = "sf_coordinates", size = 3, min.segment.length = 0, box.padding = 0.4) +
  scale_size_area(max_size = 20, breaks = c(10, 50, 200, 1000, 3000)) +
  coord_sf(xlim = metro_box[c("xmin", "xmax")], ylim = metro_box[c("ymin", "ymax")]) +
  labs(title = "ICE at-large arrests, Chicago area, by city",
       subtitle = "Jan 20, 2025 - Aug 6, 2026; 12 cities with the most arrests labeled",
       x = NULL, y = NULL, size = "Arrests", caption = map_caption) +
  theme(axis.text = element_blank(), axis.ticks = element_blank(),
        plot.caption.position = "plot", plot.caption = element_text(hjust = 0))

# County choropleth from city-based counties
library(leaflet)
source(here::here("R/add-carto-tiles.R"))

city_lookup <- il_city_county |>
  select(city, primary_county, multi_county)

il8_county <- il8 |>
  left_join(city_lookup, by = "city")
stopifnot(nrow(il8_county) == nrow(il8))

county_counts_city <- il8_county |>
  dplyr::filter(!is.na(primary_county)) |>
  group_by(county = primary_county) |>
  summarise(
    n = n(),
    at_large = sum(apprehension_method_simple == "At-Large Arrest", na.rm = TRUE),
    from_multi_county_city = sum(multi_county %in% TRUE),
    .groups = "drop")

# Coverage, for comparison with the report's ~10%
round(sum(county_counts_city$n) / nrow(il8) * 100, 1)

county_sf_city <- il_counties |>
  st_transform(4326) |>
  select(county = NAME) |>
  left_join(county_counts_city, by = "county") |>
  tidyr::replace_na(list(n = 0L, at_large = 0L, from_multi_county_city = 0L)) |>
  mutate(
    n_map = dplyr::if_else(n <= 1, NA_real_, as.double(n)),
    label = paste0(
      "<b>", county, " County</b><br>Arrests: ", n,
      "<br>At-large: ", at_large,
      dplyr::if_else(from_multi_county_city > 0,
                     paste0("<br>From multi-county cities: ", from_multi_county_city), ""))
  )

max_n_city <- max(county_sf_city$n, na.rm = TRUE)
bins_city <- c(1, 5, 20, 100, 500, max_n_city + 1)
bins_city <- unique(bins_city[bins_city <= max_n_city + 1])
pal_city <- colorBin("YlOrRd", county_sf_city$n_map, bins = bins_city, na.color = "transparent")

leaflet(county_sf_city) |>
  addCartoTiles("CartoDB.Positron") |>
  addPolygons(
    fillColor = ~pal_city(n_map), fillOpacity = 0.75,
    color = "#999", weight = 0.4,
    popup = ~label, label = ~paste0(county, ": ", n)
  ) |>
  addLegend(pal = pal_city, values = ~n_map, title = "Arrests",
            position = "bottomright")


# Findings
# CHI GENERAL AREA" arrests turn out to be about half Chicago and half spread across 270+ suburbs and towns (Cicero, Elgin, Aurora, Waukegan, Joliet, etc.)
# Merged ~90 reviewed misspellings and variants (e.g. "Chcago", "Saint Charles"), reducing distinct names from 439 to 358. Ambiguous cases were left as they are for now (Palestine, Elk Grove vs. Elk Grove Village)
# Matched cities to Census place and county boundaries places 98% of Illinois arrests in a county. 25 cities cross county lines (6% of arrests). Each is assigned to the county with most of its area
## DuPage, Kane, Lake, McHenry, and Will

# ── Landmark audit (PI's Tennessee format) + landmark vs city check ────────
# Uses the pipeline's Aug 2026 targets and the cleaning functions in
# R/state-arrests.R, so results match the report (duplicates excluded).
source(here::here("R/state-arrests.R"))
targets::tar_load(c(arrests_aug_raw, place_county))

il_audit <- arrests_aug_raw |>
  dplyr::filter(apprehension_state == "ILLINOIS",
                apprehension_date >= as.Date("2025-01-20"),
                duplicate_likely %in% FALSE | is.na(duplicate_likely)) |>
  mutate(lm = str_to_upper(apprehension_site_landmark),
         county_landmark = .parse_county_landmark(apprehension_site_landmark, "ILLINOIS"),
         city = clean_arrest_city(apprehension_city_common_case, "ILLINOIS"),
         county_city = .county_from_city(city, "ILLINOIS", place_county)$county_city)
nrow(il_audit)

# 1. Top landmarks with a notes column
il_audit |>
  count(apprehension_site_landmark, county_landmark, sort = TRUE) |>
  mutate(notes = "") |>
  print(n = 60)

# 2. County jails / sheriffs the parser rejected (out of state or not an IL county)
il_audit |>
  dplyr::filter(str_detect(lm, "COUNTY|JAIL|SHERIFF"), is.na(county_landmark)) |>
  count(apprehension_site_landmark, sort = TRUE) |>
  print(n = 40)

# 3. Landmarks that imply a county without naming one
il_audit |>
  dplyr::filter(str_detect(lm, "POLICE|PRISON|CORRECTIONAL|PENITENTIARY|MCC|AIRPORT|COURT|OFFICE")) |>
  count(county_landmark, apprehension_site_landmark, sort = TRUE) |>
  print(n = 40)

# 4. Landmark county vs city county, where both exist
landmark_vs_city <- il_audit |>
  dplyr::filter(!is.na(county_landmark), !is.na(county_city)) |>
  mutate(agree = .county_key(county_landmark) == .county_key(county_city))
landmark_vs_city |> count(agree) |> mutate(pct = round(n / sum(n) * 100, 1))
landmark_vs_city |>
  dplyr::filter(!agree) |>
  count(apprehension_site_landmark, county_landmark, city, county_city, sort = TRUE) |>
  print(n = 50)

# ── Audit tables for manual review (PI's Tennessee format) ─────────────────
# Written to data/il-landmark-audit/ as CSVs. Open in Excel/Sheets and fill the
# blank `notes` cells; rows the code already resolves are pre-filled.
audit_dir <- here::here("data/il-landmark-audit")
dir.create(audit_dir, showWarnings = FALSE)

# Table 1: top landmarks
top_landmarks <- il_audit |>
  count(apprehension_site_landmark, county_landmark, sort = TRUE) |>
  head(60) |>
  mutate(notes = dplyr::if_else(!is.na(county_landmark), paste("->", county_landmark), "")) |>
  select(apprehension_site_landmark, n, notes)
readr::write_csv(top_landmarks, file.path(audit_dir, "il-top-landmarks.csv"), na = "NA")

# Table 2: out-of-state county jails (county-type landmarks the parser rejected)
out_of_state <- il_audit |>
  dplyr::filter(str_detect(lm, "COUNTY|JAIL|SHERIFF"), is.na(county_landmark)) |>
  count(apprehension_site_landmark, sort = TRUE) |>
  mutate(notes = "")
readr::write_csv(out_of_state, file.path(audit_dir, "il-out-of-state-jails.csv"))

# Table 3: landmarks that imply a county without naming one
implied_county <- il_audit |>
  dplyr::filter(str_detect(lm, "POLICE|PRISON|CORRECTIONAL|PENITENTIARY|MCC|AIRPORT|COURT|OFFICE")) |>
  count(county_landmark, apprehension_site_landmark, sort = TRUE) |>
  mutate(notes = dplyr::if_else(!is.na(county_landmark), paste("->", county_landmark), "")) |>
  select(apprehension_site_landmark, n, notes)
readr::write_csv(implied_county, file.path(audit_dir, "il-implied-county.csv"))

list.files(audit_dir)

# Outputting these tables
to_md <- function(df, title) {
  df <- df |> mutate(apprehension_site_landmark = dplyr::coalesce(apprehension_site_landmark, "(no landmark)"))
  c(paste("###", title), "",
    knitr::kable(df, format = "pipe", col.names = c("apprehension_site_landmark", "n", "notes")), "")
}
issue_md <- c(
  "Illinois arrests since 2025-01-20 (DDP Aug 2026 release, duplicates excluded; 7,745 arrests).",
  "Same format as the Tennessee landmark audit. Notes starting with `->` are counties the code already assigns; blank notes still need checking.", "",
  to_md(top_landmarks, "Top landmarks"),
  to_md(out_of_state, "Out-of-state county jails"),
  to_md(implied_county, "Landmarks that imply a county")
)
writeLines(issue_md, file.path(audit_dir, "il-landmark-audit-issue.md"))
