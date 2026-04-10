library(dplyr)
library(stringr)

parse_md_table_lines <- function(tbl_lines) {
  # Drop separator lines (|---|---|)
  tbl_lines <- tbl_lines[!grepl("^\\|[-:\\s|]+\\|?\\s*$", tbl_lines)]

  # Split each line on | and trim whitespace, dropping empty first/last elements
  rows <- lapply(tbl_lines, function(line) {
    parts <- str_split(line, "\\|")[[1]]
    parts <- str_trim(parts)
    parts <- parts[parts != ""]  # drop empty edge elements
    parts
  })

  # First row is header
  headers <- rows[[1]]
  data_rows <- rows[-1]

  as_tibble(
    setNames(
      as.data.frame(do.call(rbind, data_rows), stringsAsFactors = FALSE),
      headers
    )
  )
}

parse_ero_locations <- function(path = "ero-locations.md") {
  lines <- readLines(path)

  # Identify table line runs
  is_table <- grepl("^\\|", lines)
  block_id <- cumsum(c(TRUE, diff(is_table) != 0))
  blocks   <- split(seq_along(lines), block_id)
  table_blocks <- blocks[sapply(blocks, \(idx) is_table[idx[1]])]

  stopifnot(length(table_blocks) == 5)

  # Tables 1-4: numbered names with state in parentheses
  parse_numbered <- function(idx) {
    parse_md_table_lines(lines[idx]) |>
      rename(facility_raw = Facility, address = Address, notes = Notes) |>
      mutate(
        facility_raw   = str_remove_all(facility_raw, "\\*\\*"),
        line_number    = as.integer(str_extract(facility_raw, "^\\d+")),
        state          = str_extract(facility_raw, "\\(([A-Z]{2})\\)$", group = 1),
        canonical_name = facility_raw |>
          str_remove("^\\d+\\.\\s*") |>
          str_remove("\\s*\\([A-Z]{2}\\)$") |>
          str_trim()
      ) |>
      select(line_number, canonical_name, state, address, notes)
  }

  # Table 5: already has canonical_name and state columns
  parse_named <- function(idx) {
    parse_md_table_lines(lines[idx]) |>
      rename(address = Address, notes = Notes) |>
      mutate(
        canonical_name = str_remove_all(canonical_name, "\\*\\*") |> str_trim(),
        state          = str_trim(state),
        line_number    = NA_integer_
      ) |>
      select(line_number, canonical_name, state, address, notes)
  }

  list(
    numbered = bind_rows(lapply(table_blocks[1:4], parse_numbered)),
    named    = parse_named(table_blocks[[5]])
  )
}

parse_address_components <- function(df) {
  result <- df |>
    mutate(
      # ZIP: last 5 (or 5+4) digits at end of address
      facility_zip     = str_extract(address, "\\d{5}(?:-\\d{4})?$"),
      # State in address: two uppercase letters before the ZIP
      facility_state   = str_extract(address, "([A-Z]{2})\\s+\\d{5}(?:-\\d{4})?$", group = 1),
      # City: segment immediately before ", ST ZIP"
      facility_city    = str_extract(address, ",\\s*([^,]+),\\s*[A-Z]{2}\\s+\\d{5}", group = 1) |>
        str_trim(),
      # Street address: everything before the city
      facility_address = str_extract(address, "^(.+?)(?=,\\s*[^,]+,\\s*[A-Z]{2}\\s+\\d{5})", group = 1) |>
        str_trim(),
      # ice.gov/node URL from notes, if present
      ice_url = str_extract(notes, "ice\\.gov/node/\\d+") |>
        (\(x) ifelse(is.na(x), NA_character_, paste0("https://", x)))()
    )

  # Warn for any rows where facility_state != state
  mismatches <- result |>
    filter(!is.na(state), !is.na(facility_state), state != facility_state)

  if (nrow(mismatches) > 0) {
    warning(
      nrow(mismatches), " row(s) have mismatched states:\n",
      paste0(
        "  - ", mismatches$canonical_name,
        ": state='", mismatches$state,
        "' but address state='", mismatches$facility_state, "'",
        collapse = "\n"
      )
    )
  }

  result |>
    select(line_number, canonical_name, state,
           facility_address, facility_city, facility_state, facility_zip,
           ice_url, notes)
}



ero_tables <- parse_ero_locations("ero-locations.md")
ero_numbered <- ero_tables$numbered
ero_named    <- ero_tables$named

ero_numbered <- filter(ero_numbered, !is.na(line_number))
ero_named <- filter(ero_named, canonical_name != ":---")
ero_holdroom_addresses_ext <- bind_rows(ero_numbered, ero_named)

parse_address_components(ero_holdroom_addresses_ext) -> ero_holdroom_ext

ero_holdroom_ext

ero_tables <- parse_ero_locations("ero-locations-fixed.md")
ero_numbered <- ero_tables$numbered
ero_named    <- ero_tables$named

ero_numbered <- filter(ero_numbered, !is.na(line_number))
ero_named <- filter(ero_named, canonical_name != ":---")
ero_holdroom_addresses_ext_2 <- bind_rows(ero_numbered, ero_named)

parse_address_components(ero_holdroom_addresses_ext_2) -> ero_holdroom_ext_2


# Testing: Take only rows that already have a known ice_url
# known <- ero_holdroom_ext |>
#   filter(!is.na(ice_url))
#
# # Blank the ice_url, run the matcher, then compare
# recovered <- known |>
#   mutate(ice_url_prior = ice_url, ice_url = NA_character_) |>
#   fetch_ice_node_addresses(
#     node_range = as.integer(str_extract(known$ice_url, "\\d+$")),
#     delay = 0  # already cached, no need to wait
#   ) |>
#   mutate(
#     ice_url_recovered = ice_url,
#     matched   = ice_url_prior == ice_url_recovered,
#   ) |>
#   select(canonical_name, facility_address, ice_url, ice_url_recovered, matched)
#
# recovered

Full scan — adjust range as needed
ero_holdroom_addresses_scan <- fetch_ice_node_addresses(
  df         = bind_rows(ero_numbered, ero_named),
  node_range = 62000:62300,
  delay      = 0.5
)


missing_hold_gemini_addresses <- ero_holdroom_ext_2 |>
  # Get canonical_id and detloc from missing_hold by name match
  left_join(
    missing_hold |> select(canonical_id, detloc, canonical_name),
    by = "canonical_name"
  ) |>
  mutate(
    node_id = as.integer(str_extract(ice_url, "(?<=node/)\\d+")),
    url     = ice_url,
    city_dist = 0L,
    # Pull everything before the first comma
    address_line1 = str_split_i(facility_address, ",", 1) |> str_trim(),
    # Pull everything after the first comma (if it exists)
    address_line2 = str_extract(facility_address, "(?<=,).*") |> str_trim(),
    city = facility_city,
    zip  = facility_zip,
    page_address = str_c(facility_address, facility_city, facility_state, facility_zip, sep = ", ")
  ) |>
  select(
    canonical_id, detloc, canonical_name, facility_state,
    city_dist, node_id, url,
    field_office_name = notes,   # closest available; set to NA below if preferred
    address_line1, address_line2, city, zip, page_address
  )

# field_office_name doesn't map naturally — set to NA to match the schema cleanly
missing_hold_gemini_addresses <- missing_hold_gemini_addresses |>
  mutate(field_office_name = NA_character_)

glimpse(missing_hold_gemini_addresses)


# Unified missing hold addresses ------------------------------------------
# Prefer ice_node data for the 10 facilities covered by both sources;
# use gemini-only rows for the remaining 17 facilities.

missing_hold_addresses <- bind_rows(
  missing_hold_ice_node_match |> mutate(source = "ice_node"),
  missing_hold_gemini_addresses |>
    mutate(source = case_when(
      detloc %in% c("LASHOLD", "RSWHOLD", "FDLHOLD",
                    "CRPHOLD", "MCAHOLD") ~ "aclu",
      detloc %in% c("CIPHOLD", "NBGHOLD", "SYRHOLD", "WPOHOLD",
                    "FDLHOLD", "REDHOLD", "CSDHOLD", "DULHOLD") ~ "media",
      detloc %in% c("MTGHOLD", "LTVHOLD", "RMKHOLD", "BLGHOLD") ~ "ice_doc",
      detloc %in% c("MOAHOLD") ~ "ice_node",
      TRUE ~ "gemini"))
) |>
  # Keep first occurrence per canonical_id — ice_node rows come first
  distinct(canonical_id, .keep_all = TRUE) |>
  arrange(canonical_id)

missing_hold_addresses |> count(source)

# Save outputs
readr::write_csv(missing_hold_addresses, here::here("data/missing-hold-addresses.csv"))
saveRDS(missing_hold_addresses, here::here("data/missing-hold-addresses.rds"))

message("Saved missing_hold_addresses: ", nrow(missing_hold_addresses), " facilities")
