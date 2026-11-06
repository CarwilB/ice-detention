# install-packages.R
# Installs all R packages needed to render the ICE detention map post.
# Run once before rendering: source("install-packages.R")

packages <- c(
  "dplyr",
  "tidyr",
  "purrr",
  "stringr",
  "sf",
  "leaflet",
  "scales",
  "htmltools",
  "htmlwidgets"
)

installed <- rownames(installed.packages())
to_install <- setdiff(packages, installed)

if (length(to_install) > 0) {
  cat("Installing:", paste(to_install, collapse = ", "), "\n")
  install.packages(to_install)
} else {
  cat("All packages already installed.\n")
}

# sf requires system libraries (GDAL, GEOS, PROJ).
# On macOS: brew install gdal proj geos
# On Ubuntu: sudo apt-get install libgdal-dev libgeos-dev libproj-dev
