addCartoTiles <- function(map, mapType = "CartoDB.Positron") {
  # Map basemap names to CARTO tile URLs
  basemap_urls <- list(
    "CartoDB" = "https://basemaps.cartocdn.com/rastertiles/light_all/{z}/{x}/{y}.png",
    "CartoDB.Positron" = "https://basemaps.cartocdn.com/rastertiles/light_all/{z}/{x}/{y}.png",
    "CartoDB.PositronNoLabels" = "https://basemaps.cartocdn.com/rastertiles/light_nolabels/{z}/{x}/{y}.png",
    "CartoDB.PositronOnlyLabels" = "https://basemaps.cartocdn.com/rastertiles/light_only_labels/{z}/{x}/{y}.png",
    "CartoDB.DarkMatter" = "https://basemaps.cartocdn.com/rastertiles/dark_all/{z}/{x}/{y}.png",
    "CartoDB.DarkMatterNoLabels" = "https://basemaps.cartocdn.com/rastertiles/dark_nolabels/{z}/{x}/{y}.png",
    "CartoDB.DarkMatterOnlyLabels" = "https://basemaps.cartocdn.com/rastertiles/dark_only_labels/{z}/{x}/{y}.png",
    "CartoDB.Voyager" = "https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png",
    "CartoDB.VoyagerNoLabels" = "https://basemaps.cartocdn.com/rastertiles/voyager_nolabels/{z}/{x}/{y}.png",
    "CartoDB.VoyagerOnlyLabels" = "https://basemaps.cartocdn.com/rastertiles/voyager_only_labels/{z}/{x}/{y}.png",
    "CartoDB.VoyagerLabelsUnder" = "https://basemaps.cartocdn.com/rastertiles/voyager_labels_under/{z}/{x}/{y}.png"
  )

  # Validate mapType
  if (!mapType %in% names(basemap_urls)) {
    stop("Invalid mapType. Must be one of: ", paste(names(basemap_urls), collapse = ", "))
  }

  # Get the URL for the requested basemap
  url <- basemap_urls[[mapType]]

  # Append API key if available
  api_key <- Sys.getenv("CARTO_MAPS_API_KEY")
  if (nzchar(api_key)) {
    url <- paste0(url, "?key=", api_key)
  }

  # Standard CARTO attribution
  attribution <- paste(
    '&copy; <a href="https://carto.com/attributions">CARTO</a>,',
    '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
  )

  # Add tiles to the map and return
  map %>%
    leaflet::addTiles(
      urlTemplate = url,
      attribution = attribution
    )
}
