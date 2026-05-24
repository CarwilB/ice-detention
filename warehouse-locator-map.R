library(rvest)
library(dplyr)
library(stringr)
library(purrr)

# 1. Scrape the table from the ICE detention expansion plan page
url <- "https://en.wikipedia.org/wiki/ICE_detention_expansion_plan"
page <- read_html(url)

table_node <- html_nodes(page, "table.wikitable")[1]

# Parse all rows
all_rows <- html_nodes(table_node, "tr")

# Skip the header (row 1) and the final source row (length(all_rows))
rows <- all_rows[2:(length(all_rows) - 1)]

# 2. Extract Location, Link, and Status
locations <- map_dfr(rows, function(row) {
  cells <- html_nodes(row, "td")

  if (length(cells) >= 2) {
    location_node <- html_node(cells[[1]], "a")

    # html_text2() strips HTML tags nicely, replacing <br> with newlines if present
    status_raw <- html_text2(cells[[4]])

    tibble(
      name = html_text(location_node),
      link = html_attr(location_node, "href"),
      status = status_raw
    )
  } else {
    tibble(name = NA_character_, link = NA_character_, status = NA_character_)
  }
}) |>
  filter(!is.na(link))

# 3. Clean the status column and map to MediaWiki marker images
locations <- locations |>
  mutate(
    # Clean out Wikipedia citation brackets like "[42]" and trim whitespace
    status_clean = str_remove_all(status, "\\[\\d+\\]") |> str_trim(),

    # Order matters here! "Purchased, but paused" must come before "Purchased"
    mark_image = case_when(
      str_detect(status_clean, "(?i)Purchased, but paused") ~ "Yellow pog.svg",
      str_detect(status_clean, "(?i)Purchased")             ~ "Green pog.svg",
      str_detect(status_clean, "(?i)Proposed")              ~ "Blue pog.svg",
      str_detect(status_clean, "(?i)Cancelled")             ~ "Red pog.svg",
      str_detect(status_clean, "(?i)Withdrawn")             ~ "Red pog.svg",
      TRUE                                                  ~ "Blue pog.svg" # Default fallback
    )
  )

# 4. Function to safely extract decimal coordinates
get_coords <- function(wiki_path) {
  if (is.na(wiki_path) || !str_starts(wiki_path, "/wiki/")) {
    return(tibble(lat = NA_real_, lon = NA_real_))
  }

  full_url <- paste0("https://en.wikipedia.org", wiki_path)

  tryCatch({
    city_page <- read_html(full_url)
    geo_text <- city_page |> html_node(".geo") |> html_text()

    if (!is.na(geo_text)) {
      coords <- str_split(geo_text, ";", simplify = TRUE)
      tibble(
        lat = round(as.numeric(str_trim(coords[1])), 4),
        lon = round(as.numeric(str_trim(coords[2])), 4)
      )
    } else {
      tibble(lat = NA_real_, lon = NA_real_)
    }
  }, error = function(e) {
    tibble(lat = NA_real_, lon = NA_real_)
  })
}

# 5. Map over the locations to fetch coordinates
location_data <- locations |>
  mutate(coords = map(link, get_coords)) |>
  unnest(coords) |>
  filter(!is.na(lat) & !is.na(lon))

# 6. Construct the Wikitext using the new 'mark' variable
generate_location_map <- function(df) {
  places_wikitext <- df |>
    mutate(
      row_text = str_glue("  {{{{Location map~ |USA |mark={mark_image} |marksize=9 |lat_deg={lat} |lon_deg={lon} |position=bottom |label={name} |link={name}}}}")
    ) |>
    pull(row_text) |>
    paste(collapse = "\n")

  map_wikitext <- str_glue("{{{{Location map+ | USA| caption = Proposed ICE warehouse locations.  | places =\n{places_wikitext}\n}}}}")

  return(map_wikitext)
}

final_wikitext <- generate_location_map(location_data)
cat(final_wikitext)
