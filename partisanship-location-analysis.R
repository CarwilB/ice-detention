# partisanship-location-analysis.R
# Analyzes ICE detention facility locations against county-level
# partisanship (2016 Trump vote share) and population density.
#
# Requires: facilities_geocoded_full, facilities_panel, facility_presence,
#           canonical_facilities (from targets pipeline or saved RDS files)
# Installs needed: maps, plotly, scales, htmltools

library(dplyr)
library(tidyr)
library(purrr)
library(stringr)
library(readr)
library(scales)
library(plotly)
library(htmltools)
library(maps, lib.loc = if (nzchar(find.package("maps", quiet = TRUE))) .libPaths()
  else "/Library/Frameworks/R.framework/Versions/4.5-arm64/Resources/library")

# ── Load pipeline data ───────────────────────────────────────────────────────
# If running outside targets, load from saved RDS files:
if (!exists("facilities_geocoded_full")) {
  facilities_geocoded_full <- readRDS(here::here("data", "facilities_geocoded_full.rds"))
}
if (!exists("facilities_panel")) {
  facilities_panel <- readRDS(here::here("data", "facilities_panel.rds"))
}
if (!exists("facility_presence")) {
  facility_presence <- readRDS(here::here("data", "facility_presence.rds"))
}
if (!exists("canonical_facilities")) {
  canonical_facilities <- readRDS(here::here("data", "canonical_facilities.rds"))
}

year_order <- facilities_panel |>
  distinct(fiscal_year) |>
  pull(fiscal_year) |>
  sort()

# ══════════════════════════════════════════════════════════════════════════════
# Section 1: County assignment via point-in-polygon
# ══════════════════════════════════════════════════════════════════════════════

facility_counties <- facilities_geocoded_full |>
  filter(!is.na(lat), !is.na(lon)) |>
  mutate(
    county_raw = maps::map.where("county", x = lon, y = lat),
    county_state = str_extract(county_raw, "^[^,]+"),
    county_name  = str_extract(county_raw, "(?<=,).+") |> str_to_title()
  ) |>
  select(canonical_id, lat, lon, facility_state, county_raw, county_state, county_name)

# Manual fixes for facilities near coastlines, borders, and in territories
manual_counties <- tibble::tribble(
  ~canonical_id, ~county_state, ~county_name,
  11,  "alaska",     "Anchorage",
  60,  "california", "San Diego",
  70,  "michigan",   "Chippewa",
  166, "hawaii",     "Honolulu",
  233, "florida",    "Miami-Dade",
  234, "florida",    "Miami-Dade",
  239, "florida",    "Monroe",
  346, "michigan",   "St Clair",
  1003, "california", "Contra Costa"
) |>
  mutate(county_raw = paste0(county_state, ",", tolower(county_name)))

facility_counties <- facility_counties |>
  rows_update(
    manual_counties |> select(canonical_id, county_raw, county_state, county_name),
    by = "canonical_id"
  )

# Join FIPS codes from maps::county.fips
data(county.fips, package = "maps")

county_fips_clean <- county.fips |>
  tibble::as_tibble() |>
  separate_rows(polyname, sep = ":") |>
  distinct(fips, polyname)

facility_counties <- facility_counties |>
  left_join(county_fips_clean, by = c("county_raw" = "polyname")) |>
  mutate(fips = sprintf("%05d", fips))

# AK and HI FIPS not in maps::county.fips
facility_counties <- facility_counties |>
  rows_update(
    tibble::tribble(
      ~canonical_id, ~fips,
      11,  "02020",
      166, "15003"
    ),
    by = "canonical_id"
  )

cat("County assigned:", sum(!is.na(facility_counties$fips) & facility_counties$fips != "   NA"),
    "of", nrow(facility_counties), "\n")

# ══════════════════════════════════════════════════════════════════════════════
# Section 2: County-level population, area, and election data
# ══════════════════════════════════════════════════════════════════════════════

# --- 2a: Population from 2020 Census redistricting data ---
pop_url <- "https://api.census.gov/data/2020/dec/pl?get=P1_001N,NAME&for=county:*"
pop_json <- jsonlite::fromJSON(httr::content(httr::GET(pop_url), "text", encoding = "UTF-8"))
county_pop <- tibble::as_tibble(pop_json[-1, ], .name_repair = "minimal")
names(county_pop) <- pop_json[1, ]

county_pop <- county_pop |>
  transmute(
    fips = paste0(state, county),
    county_name_census = NAME,
    population = as.integer(P1_001N)
  ) |>
  select(fips, county_name_census, population)

# --- 2b: Land area from Census county area file ---
area_url <- "https://www2.census.gov/library/publications/2011/compendia/usa-counties/excel/LND01.xls"
tmp_xls <- tempfile(fileext = ".xls")
writeBin(httr::content(httr::GET(area_url), "raw"), tmp_xls)
county_area <- readxl::read_xls(tmp_xls)

county_area_clean <- county_area |>
  filter(nchar(STCOU) == 5, !grepl("000$", STCOU)) |>
  transmute(fips = STCOU, land_area_sqmi = LND110210D)

# --- 2c: Merge population + area → density ---
county_data <- county_pop |>
  inner_join(county_area_clean, by = "fips") |>
  mutate(pop_density = population / land_area_sqmi)

# --- 2d: 2016 county presidential election results ---
election_url <- "https://raw.githubusercontent.com/tonmcg/US_County_Level_Election_Results_08-20/master/2016_US_County_Level_Presidential_Results.csv"
election_raw <- read_csv(httr::content(httr::GET(election_url), "text", encoding = "UTF-8"),
                         show_col_types = FALSE)

election <- election_raw |>
  transmute(
    fips = sprintf("%05d", combined_fips),
    trump_share = per_gop,
    clinton_share = per_dem,
    total_votes
  )

# --- 2e: Combined county reference table ---
county_full <- county_data |>
  inner_join(election, by = "fips")

cat("County reference table:", nrow(county_full), "counties\n")

# ══════════════════════════════════════════════════════════════════════════════
# Section 3: Facility–county join with ADP and type
# ══════════════════════════════════════════════════════════════════════════════

# Most recent facility type per canonical facility
facility_type_latest <- facilities_panel |>
  filter(!is.na(facility_type_wiki)) |>
  arrange(canonical_id, desc(match(fiscal_year, year_order))) |>
  distinct(canonical_id, .keep_all = TRUE) |>
  select(canonical_id, facility_type_wiki)

# ADP summaries
adp_by_year <- facilities_panel |>
  summarise(adp = sum(adp, na.rm = TRUE), .by = c(canonical_id, fiscal_year))

adp_wide <- adp_by_year |>
  pivot_wider(names_from = fiscal_year, values_from = adp, names_sort = TRUE)

fy_cols <- grep("^FY", names(adp_wide), value = TRUE)

latest_adp <- adp_by_year |>
  filter(!is.na(adp), adp > 0) |>
  arrange(canonical_id, desc(fiscal_year)) |>
  distinct(canonical_id, .keep_all = TRUE) |>
  transmute(canonical_id, latest_adp = round(adp), adp_fy = fiscal_year)

# FY26 active facility IDs
fy26_ids <- facilities_panel |>
  filter(fiscal_year == "FY26", !is.na(adp), adp > 0) |>
  pull(canonical_id)

# FY26-active facilities with county + election data
facility_county_fy26 <- facility_counties |>
  filter(!is.na(fips), fips != "   NA") |>
  filter(canonical_id %in% fy26_ids) |>
  inner_join(
    facilities_panel |> filter(fiscal_year == "FY26") |> select(canonical_id, adp),
    by = "canonical_id"
  ) |>
  inner_join(county_full |> select(fips, population, pop_density, trump_share), by = "fips")

cat("FY26 facilities with county data:", nrow(facility_county_fy26), "\n")

# ══════════════════════════════════════════════════════════════════════════════
# Section 4: Sparkbar builder (reused from facilities-map-post.R)
# ══════════════════════════════════════════════════════════════════════════════

make_adp_sparkbar <- function(adp_values, fy_labels, chart_width = 260,
                               bar_height = 11, gap = 2) {
  n <- length(adp_values)
  adp_values[is.na(adp_values)] <- 0
  max_adp <- max(adp_values, na.rm = TRUE)
  if (max_adp == 0) return("")

  label_width <- 30
  val_label_width <- nchar(format(round(max_adp), big.mark = ",")) * 6 + 8
  bar_area <- chart_width - label_width - val_label_width
  total_height <- n * (bar_height + gap)

  bars <- map_chr(seq_len(n), \(i) {
    val <- adp_values[i]
    w <- if (val > 0) max(2, val / max_adp * bar_area) else 0
    y <- (i - 1) * (bar_height + gap)
    fill <- if (val > 0) "#4682B4" else "none"

    label <- sprintf(
      '<text x="%d" y="%.1f" font-size="9" font-family="sans-serif" fill="#333" text-anchor="end" dominant-baseline="central">%s</text>',
      label_width - 3, y + bar_height / 2, fy_labels[i]
    )
    bar <- if (val > 0) {
      sprintf(
        '<rect x="%d" y="%.1f" width="%.1f" height="%d" fill="%s" rx="1"/>',
        label_width, y, w, bar_height, fill
      )
    } else ""
    val_label <- if (val > 0) {
      sprintf(
        '<text x="%.1f" y="%.1f" font-size="8" font-family="sans-serif" fill="#333" dominant-baseline="central">%s</text>',
        label_width + w + 3, y + bar_height / 2, format(round(val), big.mark = ",")
      )
    } else ""

    paste0(label, bar, val_label)
  })

  sprintf(
    '<svg width="%d" height="%d" xmlns="http://www.w3.org/2000/svg">%s</svg>',
    chart_width, total_height, paste0(bars, collapse = "")
  )
}

# ══════════════════════════════════════════════════════════════════════════════
# Section 5: Jail scatter plot (partisanship × density)
# ══════════════════════════════════════════════════════════════════════════════

# All jails with county data (active + closed)
jail_counties <- facility_counties |>
  filter(!is.na(fips), fips != "   NA") |>
  inner_join(facility_type_latest, by = "canonical_id") |>
  filter(facility_type_wiki == "Jail") |>
  inner_join(county_full |> select(fips, population, pop_density, trump_share), by = "fips")

jail_plot <- jail_counties |>
  inner_join(
    canonical_facilities |>
      transmute(canonical_id, canonical_name, facility_city,
                fac_state = facility_state, facility_address),
    by = "canonical_id"
  ) |>
  left_join(facility_presence |> select(canonical_id, first_seen, last_seen),
            by = "canonical_id") |>
  left_join(latest_adp, by = "canonical_id") |>
  left_join(
    # Aggregate FY26 ADP to avoid duplicates from sub-entries
    facilities_panel |>
      filter(fiscal_year == "FY26") |>
      summarise(fy26_adp = sum(adp, na.rm = TRUE), .by = canonical_id),
    by = "canonical_id"
  ) |>
  left_join(
    adp_by_year |> summarise(peak_adp = max(adp, na.rm = TRUE), .by = canonical_id),
    by = "canonical_id"
  ) |>
  mutate(
    is_open = canonical_id %in% fy26_ids,
    is_new = first_seen %in% c("FY25", "FY26") & is_open,
    status_label = factor(
      case_when(
        is_new  ~ "New (FY25\u2013FY26)",
        is_open ~ "Active",
        TRUE    ~ "Closed"
      ),
      levels = c("Closed", "Active", "New (FY25\u2013FY26)")
    ),
    plot_adp = if_else(is_open, replace_na(fy26_adp, 0), replace_na(peak_adp, 0)),
    size_val = plot_adp^2,
    hover_text = paste0(
      canonical_name, "\n",
      facility_city, ", ", fac_state, "\n",
      if_else(is_open, "Open", "Closed"),
      " | First seen: ", first_seen, " | Last seen: ", last_seen, "\n",
      "ADP: ", format(round(plot_adp), big.mark = ","),
      " (", if_else(is_open, "FY26", paste0("peak, ", adp_fy)), ")"
    )
  )

# ADP-weighted centroids per status category
centroids_jail <- jail_plot |>
  summarise(
    wtd_trump = weighted.mean(trump_share, w = plot_adp),
    wtd_density = weighted.mean(pop_density, w = plot_adp),
    total_adp = sum(plot_adp),
    n = n(),
    .by = status_label
  ) |>
  mutate(
    label = paste0(status_label, "\n(",
                   format(round(total_adp), big.mark = ","), " ADP)")
  )

centroid_colors <- c("Closed" = "grey40", "Active" = "#8b0000",
                     "New (FY25\u2013FY26)" = "#cc0000")

# Build the plotly scatter
p_jail <- plot_ly() |>
  add_trace(
    data = jail_plot |> filter(status_label == "Closed"),
    x = ~trump_share, y = ~pop_density,
    size = ~size_val, sizes = c(16, 160),
    type = "scatter", mode = "markers",
    marker = list(color = "rgba(180,180,180,0.4)",
                  line = list(color = "rgba(120,120,120,0.5)", width = 0.5),
                  sizemode = "area"),
    text = ~hover_text, hoverinfo = "text",
    name = "Closed"
  ) |>
  add_trace(
    data = jail_plot |> filter(status_label == "Active"),
    x = ~trump_share, y = ~pop_density,
    size = ~size_val, sizes = c(16, 160),
    type = "scatter", mode = "markers",
    marker = list(color = "rgba(178,34,34,0.55)",
                  line = list(color = "rgba(120,20,20,0.6)", width = 0.5),
                  sizemode = "area"),
    text = ~hover_text, hoverinfo = "text",
    name = "Active"
  ) |>
  add_trace(
    data = jail_plot |> filter(status_label == "New (FY25\u2013FY26)"),
    x = ~trump_share, y = ~pop_density,
    size = ~size_val, sizes = c(16, 160),
    type = "scatter", mode = "markers",
    marker = list(color = "rgba(255,0,0,0.65)",
                  line = list(color = "rgba(200,0,0,0.7)", width = 0.8),
                  sizemode = "area"),
    text = ~hover_text, hoverinfo = "text",
    name = "New (FY25\u2013FY26)"
  ) |>
  add_trace(
    data = centroids_jail,
    x = ~wtd_trump, y = ~wtd_density,
    type = "scatter", mode = "markers+text",
    marker = list(
      size = 16, color = "white",
      line = list(color = centroid_colors[as.character(centroids_jail$status_label)],
                  width = 3),
      symbol = "diamond"
    ),
    text = ~label,
    textposition = "top right",
    textfont = list(size = 11,
                    color = centroid_colors[as.character(centroids_jail$status_label)]),
    hovertext = ~paste0(
      status_label,
      "\nWeighted avg Trump share: ", percent(wtd_trump, .1),
      "\nWeighted avg density: ", round(wtd_density), "/sq mi",
      "\nTotal ADP: ", format(round(total_adp), big.mark = ",")),
    hoverinfo = "text",
    showlegend = FALSE
  ) |>
  layout(
    title = list(text = "ICE detention in county jails by partisanship and density"),
    xaxis = list(title = "2016 Trump vote share", tickformat = ".0%",
                 range = c(0, 1)),
    yaxis = list(title = "Population density (per sq mi)", type = "log",
                 tickformat = ","),
    legend = list(x = 0.02, y = 0.02, bgcolor = "rgba(255,255,255,0.8)"),
    hoverlabel = list(bgcolor = "white", font = list(size = 12))
  )

p_jail

# ══════════════════════════════════════════════════════════════════════════════
# Section 6: Non-jail facilities scatter plot (partisanship × density)
# ══════════════════════════════════════════════════════════════════════════════

nonjail_counties <- facility_counties |>
  filter(!is.na(fips), fips != "   NA") |>
  inner_join(facility_type_latest, by = "canonical_id") |>
  filter(facility_type_wiki != "Jail") |>
  inner_join(county_full |> select(fips, population, pop_density, trump_share), by = "fips")

nonjail_plot <- nonjail_counties |>
  inner_join(
    canonical_facilities |>
      transmute(canonical_id, canonical_name, facility_city,
                fac_state = facility_state, facility_address),
    by = "canonical_id"
  ) |>
  left_join(facility_presence |> select(canonical_id, first_seen, last_seen),
            by = "canonical_id") |>
  left_join(latest_adp, by = "canonical_id") |>
  left_join(
    # Aggregate FY26 ADP to avoid duplicates from sub-entries
    facilities_panel |>
      filter(fiscal_year == "FY26") |>
      summarise(fy26_adp = sum(adp, na.rm = TRUE), .by = canonical_id),
    by = "canonical_id"
  ) |>
  left_join(
    adp_by_year |> summarise(peak_adp = max(adp, na.rm = TRUE), .by = canonical_id),
    by = "canonical_id"
  ) |>
  mutate(
    is_open = canonical_id %in% fy26_ids,
    is_new = first_seen %in% c("FY25", "FY26") & is_open,
    status_label = factor(
      case_when(
        is_new  ~ "New (FY25\u2013FY26)",
        is_open ~ "Active",
        TRUE    ~ "Closed"
      ),
      levels = c("Closed", "Active", "New (FY25\u2013FY26)")
    ),
    plot_adp = if_else(is_open, replace_na(fy26_adp, 0), replace_na(peak_adp, 0)),
    size_val = plot_adp^2,
    hover_text = paste0(
      canonical_name, "\n",
      facility_city, ", ", fac_state, "\n",
      facility_type_wiki, "\n",
      if_else(is_open, "Open", "Closed"),
      " | First seen: ", first_seen, " | Last seen: ", last_seen, "\n",
      "ADP: ", format(round(plot_adp), big.mark = ","),
      " (", if_else(is_open, "FY26", paste0("peak, ", adp_fy)), ")"
    )
  )

# Color by facility type
type_colors <- c(
  "Private Migrant Detention Center"         = "rgba(228,26,28,0.7)",
  "Dedicated Migrant Detention Center"       = "rgba(77,175,74,0.7)",
  "ICE Migrant Detention Center"             = "rgba(152,78,163,0.7)",
  "ICE Short-Term Migrant Detention Center"  = "rgba(255,127,0,0.7)",
  "Family Detention Center"                  = "rgba(166,86,40,0.7)",
  "Federal Prison"                           = "rgba(247,129,191,0.7)",
  "State Migrant Detention Center"           = "rgba(230,171,2,0.7)",
  "Military Detention Center"                = "rgba(102,194,165,0.7)",
  "Juvenile Detention Center"                = "rgba(84,48,5,0.7)",
  "Other"                                    = "rgba(27,158,119,0.7)"
)

type_line_colors <- c(
  "Private Migrant Detention Center"         = "rgba(180,20,20,0.8)",
  "Dedicated Migrant Detention Center"       = "rgba(50,140,50,0.8)",
  "ICE Migrant Detention Center"             = "rgba(120,60,130,0.8)",
  "ICE Short-Term Migrant Detention Center"  = "rgba(200,100,0,0.8)",
  "Family Detention Center"                  = "rgba(130,68,30,0.8)",
  "Federal Prison"                           = "rgba(200,100,150,0.8)",
  "State Migrant Detention Center"           = "rgba(180,135,2,0.8)",
  "Military Detention Center"                = "rgba(80,150,130,0.8)",
  "Juvenile Detention Center"                = "rgba(60,30,3,0.8)",
  "Other"                                    = "rgba(20,120,90,0.8)"
)

# Build one trace per facility type
nonjail_types <- nonjail_plot |>
  filter(plot_adp > 0) |>
  distinct(facility_type_wiki) |>
  pull() |>
  sort()

p_nonjail <- plot_ly()

for (ftype in nonjail_types) {
  d <- nonjail_plot |> filter(facility_type_wiki == ftype, plot_adp > 0)
  fill_col <- type_colors[[ftype]] %||% "rgba(100,100,100,0.5)"
  line_col <- type_line_colors[[ftype]] %||% "rgba(70,70,70,0.7)"

  # Desaturate closed facilities
  d_closed <- d |> filter(!is_open)
  d_open   <- d |> filter(is_open)

  if (nrow(d_open) > 0) {
    p_nonjail <- p_nonjail |>
      add_trace(
        data = d_open,
        x = ~trump_share, y = ~pop_density,
        size = ~size_val, sizes = c(16, 200),
        type = "scatter", mode = "markers",
        marker = list(color = fill_col,
                      line = list(color = line_col, width = 0.8),
                      sizemode = "area"),
        text = ~hover_text, hoverinfo = "text",
        name = ftype,
        legendgroup = ftype
      )
  }

  if (nrow(d_closed) > 0) {
    p_nonjail <- p_nonjail |>
      add_trace(
        data = d_closed,
        x = ~trump_share, y = ~pop_density,
        size = ~size_val, sizes = c(16, 200),
        type = "scatter", mode = "markers",
        marker = list(color = "rgba(180,180,180,0.35)",
                      line = list(color = "rgba(120,120,120,0.4)", width = 0.5),
                      sizemode = "area"),
        text = ~hover_text, hoverinfo = "text",
        name = paste0(ftype, " (closed)"),
        legendgroup = ftype,
        showlegend = FALSE
      )
  }
}

p_nonjail <- p_nonjail |>
  layout(
    title = list(text = "Non-jail ICE detention facilities by partisanship and density"),
    xaxis = list(title = "2016 Trump vote share", tickformat = ".0%",
                 range = c(0, 1)),
    yaxis = list(title = "Population density (per sq mi)", type = "log",
                 tickformat = ","),
    legend = list(x = 0.02, y = 0.98, bgcolor = "rgba(255,255,255,0.8)"),
    hoverlabel = list(bgcolor = "white", font = list(size = 12))
  )

p_nonjail
