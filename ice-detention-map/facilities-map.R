# facilities-map.R
# Standalone script: Interactive Leaflet map of ICE detention facilities.
#
# Color encodes facility type; circle size encodes ADP.
# Open facilities use saturated colors (sized by most recent ADP).
# Closed facilities use desaturated versions (sized by max-ever ADP).
# Popups include facility metadata and an inline SVG bar chart of ADP history.
#
# Requires: targets pipeline to have been run (tar_make()).
# Packages: leaflet, sf, scales, htmltools, dplyr, tidyr, purrr, stringr, targets
#
# Usage:
#   source("facilities-map.R")
#   # Opens interactive map in RStudio Viewer.
#   # Optionally export:
#   htmlwidgets::saveWidget(facilities_map, "facilities_map.html", selfcontained = TRUE)

library(dplyr)
library(tidyr)
library(purrr)
library(stringr)
library(sf)
library(leaflet)
library(scales)
library(htmltools)
library(targets)

# ── Load pipeline data ──────────────────────────────────────────────────────

tar_load(c(facilities_geocoded_full, facility_presence, facilities_panel))

# ── Color palette: facility type ────────────────────────────────────────────

type_colors <- c(
  "Jail"                                  = "#377eb8",
  "Private Migrant Detention Center"      = "#e41a1c",
  "Dedicated Migrant Detention Center"    = "#4daf4a",
  "ICE Migrant Detention Center"          = "#984ea3",
  "ICE Short-Term Migrant Detention Center" = "#ff7f00",
  "Private Family Detention Center"       = "#a65628",
  "Federal Prison"                        = "#f781bf",
  "State Migrant Detention Center"        = "#e6ab02",
  "Military Detention Center"             = "#66c2a5",
  "Other"                                 = "#1b9e77"
)

# Desaturated (greyed) versions for closed facilities
desaturate_hex <- function(hex, amount = 0.65) {
  rgb_mat <- col2rgb(hex) / 255
  grey <- 0.299 * rgb_mat[1, ] + 0.587 * rgb_mat[2, ] + 0.114 * rgb_mat[3, ]
  blended <- rgb_mat * (1 - amount) + grey * amount
  rgb(blended[1, ], blended[2, ], blended[3, ])
}

type_colors_closed <- desaturate_hex(type_colors)
names(type_colors_closed) <- names(type_colors)

# ── Prepare ADP data ────────────────────────────────────────────────────────

# Sum ADP across detlocs when multiple map to the same canonical_id
adp_by_year <- facilities_panel |>
  summarise(adp = sum(adp, na.rm = TRUE), .by = c(canonical_id, fiscal_year))

# Wide table for popup bar charts
adp_wide <- adp_by_year |>
  pivot_wider(names_from = fiscal_year, values_from = adp, names_sort = TRUE)

fy_cols <- grep("^FY", names(adp_wide), value = TRUE)

# Most recent ADP (for open facility sizing)
most_recent_fy <- tail(fy_cols, 1)
current_adp <- adp_by_year |>
  filter(fiscal_year == most_recent_fy, adp > 0) |>
  transmute(canonical_id, current_adp = adp)

# Max-ever ADP (for closed facility sizing)
max_adp <- adp_by_year |>
  summarise(max_adp = max(adp, na.rm = TRUE), .by = canonical_id)

# Latest non-zero ADP + fiscal year for popup headline
latest_adp <- adp_by_year |>
  filter(!is.na(adp), adp > 0) |>
  arrange(canonical_id, desc(fiscal_year)) |>
  distinct(canonical_id, .keep_all = TRUE) |>
  transmute(canonical_id, latest_adp = round(adp), adp_fy = fiscal_year)

# ── Build SVG bar chart for popup ───────────────────────────────────────────

make_adp_sparkbar <- function(adp_values, fy_labels, chart_width = 260,
                               bar_height = 11, gap = 2) {
  n <- length(adp_values)
  adp_values[is.na(adp_values)] <- 0
  max_adp <- max(adp_values, na.rm = TRUE)
  if (max_adp == 0) return("")

  label_width <- 30
  # Reserve space for the value label after the longest bar
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

# ── Build popup HTML ────────────────────────────────────────────────────────

build_popup_html <- function(row, adp_wide_joined, fy_cols) {
  cid <- row$canonical_id

  header <- sprintf(
    '<div style="min-width:280px; font-family:sans-serif; font-size:12px;">
     <b style="font-size:13px;">%s</b><br>
     %s, %s<br>
     <span style="color:#666;">Type: %s</span><br>
     <span style="color:#666;">%s | First seen: %s | Last seen: %s</span>',
    htmlEscape(row$canonical_name),
    htmlEscape(row$facility_city), htmlEscape(row$facility_state),
    htmlEscape(row$facility_type_wiki %||% "Unknown"),
    ifelse(row$status == "open",
           '<span style="color:#2a7;font-weight:bold;">Open</span>',
           '<span style="color:#a55;">Closed</span>'),
    row$first_seen, row$last_seen
  )

  adp_line <- if (!is.na(row$latest_adp) && row$latest_adp > 0) {
    sprintf('<br><b>ADP: %s</b> (%s)',
            format(row$latest_adp, big.mark = ","), row$adp_fy)
  } else {
    '<br><span style="color:#999;">No ADP data</span>'
  }

  adp_row <- adp_wide_joined |> filter(canonical_id == cid)
  if (nrow(adp_row) == 1) {
    vals <- as.numeric(adp_row[1, fy_cols])
    chart <- make_adp_sparkbar(vals, fy_cols)
    chart_html <- sprintf(
      '<div style="margin-top:6px; border-top:1px solid #ddd; padding-top:4px;">
       <span style="font-size:10px; color:#666;">ADP by fiscal year</span><br>%s</div>',
      chart
    )
  } else {
    chart_html <- ""
  }

  paste0(header, adp_line, chart_html, '</div>')
}

# ── Assemble map data ───────────────────────────────────────────────────────

fy_levels <- grep("^FY", names(facility_presence), value = TRUE)

map_df <- facilities_geocoded_full |>
  filter(!is.na(lat), !is.na(lon)) |>
  left_join(
    facility_presence |> select(canonical_id, first_seen, last_seen),
    by = "canonical_id"
  ) |>
  left_join(latest_adp, by = "canonical_id") |>
  left_join(current_adp, by = "canonical_id") |>
  left_join(max_adp, by = "canonical_id") |>
  left_join(
    # Get the most recent facility_type_wiki per facility
    facilities_panel |>
      filter(!is.na(facility_type_wiki)) |>
      arrange(canonical_id, desc(fiscal_year)) |>
      distinct(canonical_id, .keep_all = TRUE) |>
      select(canonical_id, facility_type_wiki),
    by = "canonical_id"
  ) |>
  mutate(
    facility_type_wiki = replace_na(facility_type_wiki, "Other"),
    # Facilities without presence data (geocoded but not in panel) treated as closed
    status = case_when(
      is.na(last_seen) ~ "closed",
      last_seen == tail(fy_levels, 1) ~ "open",
      TRUE ~ "closed"
    ),
    # Sizing: open → current ADP; closed → max-ever ADP
    size_adp = if_else(status == "open",
                       replace_na(current_adp, 0),
                       replace_na(max_adp, 0)),
    # Colors
    fill_color = if_else(
      status == "open",
      unname(type_colors[facility_type_wiki]),
      unname(type_colors_closed[facility_type_wiki])
    ),
    label = paste0(canonical_name, " (", facility_city, ", ", facility_state, ")")
  )

# Scale radius: sqrt transform so circle area is proportional to ADP
map_df <- map_df |>
  mutate(
    radius = rescale(sqrt(pmax(size_adp, 1)), to = c(5, 32))
  )

# Convert to sf
map_sf <- st_as_sf(map_df, coords = c("lon", "lat"), crs = 4326)

# Join ADP wide data for bar charts
adp_wide_joined <- adp_wide |> filter(canonical_id %in% map_df$canonical_id)

# Build popups row by row
map_data <- map_sf |> st_drop_geometry()
popup_html <- map_chr(seq_len(nrow(map_data)), \(i) {
  build_popup_html(as.list(map_data[i, ]), adp_wide_joined, fy_cols)
})

# ── Build leaflet map ───────────────────────────────────────────────────────

# Separate open/closed for layering (open on top)
is_open <- map_sf$status == "open"

# Legend entries: unique types present in the data
legend_types <- sort(unique(map_df$facility_type_wiki))
legend_colors <- unname(type_colors[legend_types])

# Continental US + Puerto Rico bounding box
facilities_map <- leaflet() |>
  fitBounds(lng1 = -125, lat1 = 17.5, lng2 = -65, lat2 = 49.5) |>
  addProviderTiles(providers$CartoDB.Positron) |>
  # Closed facilities first (underneath)
  addCircleMarkers(
    data = map_sf[!is_open, ],
    radius = ~radius,
    color = "#666",
    weight = 0.5,
    fillColor = ~fill_color,
    fillOpacity = 0.5,
    popup = popup_html[!is_open],
    label = ~label,
    group = "Closed"
  ) |>
  # Open facilities on top
  addCircleMarkers(
    data = map_sf[is_open, ],
    radius = ~radius,
    color = "#333",
    weight = 0.8,
    fillColor = ~fill_color,
    fillOpacity = 0.8,
    popup = popup_html[is_open],
    label = ~label,
    group = "Open"
  ) |>
  addLegend(
    position = "bottomright",
    colors = legend_colors,
    labels = legend_types,
    title = "Facility Type",
    opacity = 0.8
  ) |>
  addLayersControl(
    overlayGroups = c("Open", "Closed"),
    options = layersControlOptions(collapsed = FALSE)
  )

# Display
facilities_map

# Export as self-contained HTML
htmlwidgets::saveWidget(facilities_map, "facilities_map.html", selfcontained = TRUE)
