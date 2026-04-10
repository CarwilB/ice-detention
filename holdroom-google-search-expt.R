# Write code to run a google search for these ICE holdrooms in webpages that begin with www.ice.gov/node/ and return values for facility_address, facility_city, and facility_zip that can be used as a patch.

#
#
library(dplyr)
library(stringr)
library(purrr)
library(httr2)
library(rvest)
library(tidyr)

serpapi_search <- function(q, api_key, num = 5) {
  # https://serpapi.com/search-api
  req <- request("https://serpapi.com/search.json") |>
    req_url_query(
      engine = "google",
      q = q,
      api_key = api_key,
      num = num
    )

  resp <- req_perform(req)
  js <- resp_body_json(resp)

  if (is.null(js$organic_results)) return(tibble(url = character(), title = character()))
  tibble(
    url   = map_chr(js$organic_results, ~ .x$link %||% NA_character_),
    title = map_chr(js$organic_results, ~ .x$title %||% NA_character_)
  ) |>
    filter(!is.na(url))
}

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

extract_ice_address <- function(url) {
  # fetch
  html <- request(url) |>
    req_user_agent("R address patch script (contact: you@example.com)") |>
    req_perform() |>
    resp_body_html()

  text <- html |>
    html_element("body") |>
    html_text2()

  text <- str_squish(text)

  # Try to capture something like "... City, ST 12345"
  m <- str_match(
    text,
    "(?i)(\\d{1,6}\\s+[^,\\n]{3,80})\\s*,\\s*([A-Za-z .'-]{2,40})\\s*,\\s*([A-Z]{2})\\s+(\\d{5}(?:-\\d{4})?)"
  )

  if (!is.na(m[1,1])) {
    return(tibble(
      facility_address = m[1,2],
      facility_city    = m[1,3],
      facility_zip     = m[1,5]
    ))
  }

  # Fallback: look for ZIP first, then back up a bit
  m2 <- str_match(text, "(\\d{5}(?:-\\d{4})?)")
  if (!is.na(m2[1,1])) {
    return(tibble(
      facility_address = NA_character_,
      facility_city    = NA_character_,
      facility_zip     = m2[1,2]
    ))
  }

  tibble(facility_address = NA_character_, facility_city = NA_character_, facility_zip = NA_character_)
}

holds_missing <- facilities_geocoded_all |>
  filter(is.na(facility_address)) |>
  filter(str_detect(canonical_name, "Hold")) |>
  select(canonical_name, facility_state) |>
  distinct()

# Put your SerpAPI key in an env var:
# Sys.setenv(SERPAPI_KEY = "...")
SERPAPI_KEY <- Sys.getenv("SERPAPI_KEY")
stopifnot(nzchar(SERPAPI_KEY))

patch <- holds_missing |>
  mutate(
    google_q = paste0(
      'site:www.ice.gov inurl:"/node/" "',
      canonical_name,
      '" ',
      facility_state,
      " address"
    )
  ) |>
  mutate(
    results = map(google_q, ~ serpapi_search(.x, api_key = SERPAPI_KEY, num = 5))
  ) |>
  unnest(results) |>
  # keep only the pages that match your constraint
  filter(str_detect(url, "^https?://www\\.ice\\.gov/node/")) |>
  group_by(canonical_name, facility_state) |>
  slice_head(n = 1) |>
  ungroup() |>
  mutate(addr = map(url, extract_ice_address)) |>
  unnest(addr) |>
  # this is the "patch" table you can join back
  select(canonical_name, facility_state, facility_address, facility_city, facility_zip, ice_node_url = url)

patch
