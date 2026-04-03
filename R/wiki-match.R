# R/wiki-match.R — Match ICE detention facilities to Wikipedia article rows
#
# Scrapes the Wikipedia "List of immigrant detention sites" article,
# matches ICE facilities to Wikipedia rows by name and city/state,
# and merges wiki_slug + management data onto the facilities data.
#
# Future: Extend canonical matching — see "Future work" in AGENTS.md

# ── Management operator lookup ────────────────────────────────────────────────

#' Lookup table mapping raw operator strings to standardized management names
#' and ownership categories.
#'
#' Covers fl17 facility_operator codes, existing contractors patch values, and
#' Wikipedia-sourced management strings. Category is "public" (government-run)
#' or "private" (corporate contractor).
management_lookup <- function() {
  tibble::tribble(
    ~raw_operator,                                    ~management,                               ~category,
    # fl17 public operators
    "COUNTY",                                         "County",                                  "public",
    "COUNTY (SHERIFF)",                               "County (Sheriff)",                        "public",
    "COUNTY (CORRECTIONS)",                           "County (Corrections)",                    "public",
    "COUNTY (JAILER)",                                "County (Jailer)",                         "public",
    "COUNTY (PRISON)",                                "County (Prison)",                         "public",
    "CITY",                                           "City",                                    "public",
    # fl17 private operators
    "GEO",                                            "GEO Group",                               "private",
    "CCA",                                            "CoreCivic",                               "private",
    "LASALLE CORRECTIONS",                            "LaSalle Corrections",                     "private",
    "M&TC",                                           "Management & Training Corp (MTC)",        "private",
    "AGS",                                            "Ahtna Global Services",                   "private",
    "CEC",                                            "Community Education Centers Inc.",         "private",
    "ICA",                                            "Immigration Centers of America",          "private",
    "AHTNA (GUARD)",                                  "Ahtna Global Services",                   "private",
    "ASSET (GUARD)",                                  "Asset Protection & Security Services",    "private",
    "GPS-ASSET",                                      "Asset Protection & Security Services",    "private",
    # Wikipedia / contractors patch (already title case)
    "CoreCivic",                                      "CoreCivic",                               "private",
    "GEO Group",                                      "GEO Group",                               "private",
    "The GEO Group",                                  "GEO Group",                               "private",
    "Geo Group/ICE Detention and Removal Operations", "GEO Group",                               "private",
    "LaSalle Corrections",                            "LaSalle Corrections",                     "private",
    "Management & Training Corp (MTC)",               "Management & Training Corp (MTC)",        "private",
    "Management and Training Corporation",            "Management & Training Corp (MTC)",        "private",
    "Community Education Centers Inc.",                "Community Education Centers Inc.",         "private",
    "Acquisition Logistics LLC",                      "Acquisition Logistics LLC",               "private",
    "Central Falls Detention Facility Corporation",   "Central Falls Detention Facility Corp.",   "private",
    "ICE",                                            "ICE",                                     "public",
    "Federal Bureau of Prisons",                      "Federal Bureau of Prisons",               "public",
    "New York State Commission of Correction",        "New York State Commission of Correction", "public"
  )
}


# ── Exclusion lists ──────────────────────────────────────────────────────────

# Hand-verified ICE facility names that share a city/state with a Wikipedia
# entry but are confirmed to be different facilities.
# Used by build_wiki_match_table() for FY26-specific matching.
wiki_does_not_match <- function() {
  c(
    "Farmville Detention Center",
    "Dallas County Jail - Lew Sterrett Justice Center",
    "Leavenworth US Penitentiary",
    "IAH Secure Adult Detention Facility (Polk)",
    "FDC Philadelphia",
    "El Valle Detention Facility",
    "Greene County Jail"
  )
}

# Extended exclusion list for canonical-level matching (includes the above plus
# additional false positives found when matching the full canonical facility list).
canonical_wiki_does_not_match <- function() {
  c(
    wiki_does_not_match(),
    # Carver County Jail (adult) ≠ Carver County Juvenile Detention (wiki row)
    "Carver County Jail",
    # Hotel staging facility ≠ Devereux behavioral health facility
    "Suites On Scottsdale-Casa De Alegr\u00eda",
    # Current port of entry ≠ demolished 2018 tent city
    "Tornillo-Guadalupe Poe",
    # La Palma Correctional Center (CoreCivic) ≠ Eloy Detention Center (same city)
    "La Palma Correctional Center",
    # Mahoning County Jail ≠ Northeast Ohio Correctional Center (same city)
    "Mahoning County Jail",
    # Plymouth House of Correction redirects to MCI Plymouth — a different facility
    "Plymouth County Correctional Facility"
  )
}

# Wikipedia article links found via API search or category membership, for
# canonical facilities that are not in the scraped wiki detention table.
# Each entry maps one canonical_name to a confirmed Wikipedia article title.
# Verified with check_wiki_articles().
canonical_wiki_external_matches <- function() {
  tibble::tribble(
    ~canonical_name,                                ~wiki_slug,
    "Baker Correctional Institution",                "Baker Correctional Institution",
    "Bluebonnet Detention Center",                   "Bluebonnet Detention Center",
    "California City Immigration Processing Center", "California City Correctional Facility",
    "Delaney Hall Detention Facility",               "Delaney Hall",
    "Camp East Montana",                             "Camp East Montana",
    "Jefferson County Jail",                         "Jefferson County Jail",
    "Miami Correctional Center",                     "Miami Correctional Facility"
  )
}

# Hand-verified resolutions for city/state pairs with multiple canonical
# facilities or name mismatches that automated passes can't resolve.
# Each entry maps one canonical name to one wiki table name.
# Only include entries where the wiki row has a non-empty wiki_slug.
canonical_wiki_manual_matches <- function() {
  tibble::tribble(
    ~canonical_name,                                ~wiki_name,
    # Multi-wiki-row cities
    "Willacy County Regional Detention Facility",    "Willacy Detention Center( Willacy County Processing Center)",
    "Northwest ICE Processing Center",               "Northwest Detention Center(Tacoma Contract Detention Facility)",
    "South Texas ICE Processing Center",             "South Texas Detention Facility(formerly Pearsall Immigration Detention Center)",
    "Otay Mesa Detention Center",                    "Otay Detention Facility(San Diego Correctional Facility)",
    "Port Isabel Detention Center",                  "Port Isabel Service Processing Center(Port Isabel Detention Center)",
    # Florence, AZ — only Florence Correctional Center has a slug
    "Central Arizona Florence Correctional Complex", "Florence Correctional Center",
    # Canonical name includes "(Mississippi)" disambiguation suffix
    "Adams County Detention Center (Mississippi)",   "Adams County Correctional Center",
    # BOP facilities — ICE short names vs Wikipedia formal names
    "Brooklyn MDC",                                  "Metropolitan Detention Center, Brooklyn",
    "Guaynabo MDC (San Juan)",                       "Metropolitan Detention Center - Guaynabo",
    # Historical names / nicknames linking to facility articles
    "JTF Camp Six",                                  "Guantanamo Bay Migrant Operations Center",
    "Mccook Detention Center",                       "Cornhusker Clink",
    "Louisiana ICE Processing",                      "Louisiana State Penitentiary (Louisiana Lockup)",
    "East Mesa Detention Facility",                  "Alligator Alcatraz",
    # Bad-redirect wiki links that user confirmed should be kept
    "Plymouth County Correctional Facility",         "Plymouth County Correctional(Plymouth House of Corrections)",
    "Pinellas County Jail",                          "Pinellas County Jail"
  )
}

# Facility names whose Wikipedia API search results are false positives.
wiki_search_exclude_list <- function() {
  c(
    "Boone County Jail",
    "Davis County",
    "Douglas County",
    "Franklin County Jail",
    "Jefferson County Jail",
    "Lawrence County",
    "Pottawattamie County Jail",
    "Southern Regional"
  )
}

# Name fixes for the contractors patch CSV: patch names that don't exactly
# match ICE facility names.
contractors_patch_name_fixes <- function() {
  tibble::tibble(
    facility_name = c(
      "Dallas Transitional Center",
      "West Tennessee Detention Facility"
    ),
    matched_ice_facility = c(
      "Dallas County Jail - Lew Sterrett Justice Center",
      "Western Tennessee Detention Facility"
    )
  )
}

# Hand-verified wiki_slug corrections for cases where the scraped link is a
# redirect and the canonical article title differs. These are applied after
# backfill_wiki_slugs() via apply_wiki_slug_overrides().
wiki_slug_overrides <- function() {
  tibble::tribble(
    ~wiki_slug_from,                                      ~wiki_slug_to,
    # Redirects → canonical article titles (verified with check_wiki_articles)
    "T. Don Hutto Family Residential Facility",            "T. Don Hutto Residential Center",
    "Wyatt Detention Center",                              "Donald W. Wyatt Detention Facility",
    "Otay Detention Facility",                             "Otay Mesa Detention Center",
    "Douglas County Correctional",                         "Douglas County Correctional Center",
    "Willacy Detention Center",                            "Willacy County Regional Detention Center",
    # Bad redirects → clear (redirect target is not a facility article)
    "Wayne County Jail",                                   NA_character_
  )
}


#' Apply hand-verified wiki_slug corrections
#'
#' Replaces redirect-based wiki_slug values with the canonical Wikipedia
#' article title, or clears slugs that redirect to non-facility pages.
#' Overrides are specified in `wiki_slug_overrides()`.
#'
#' @param df Facilities tibble with a `wiki_slug` column.
#' @return df with corrected wiki_slug values.
apply_wiki_slug_overrides <- function(df) {
  overrides <- wiki_slug_overrides()
  for (i in seq_len(nrow(overrides))) {
    target <- overrides$wiki_slug_to[i]
    df <- df |>
      dplyr::mutate(
        wiki_slug = dplyr::if_else(
          !is.na(wiki_slug) & wiki_slug == overrides$wiki_slug_from[i],
          target %||% "",
          wiki_slug
        )
      )
  }
  df
}


# ── Layer 1: Scrape Wikipedia table ──────────────────────────────────────────

#' Scrape the Wikipedia "List of immigrant detention sites" table
#'
#' Fetches a pinned revision of the Wikipedia article, extracts the first
#' wikitable, parses facility names, wiki slugs (from hrefs), and other
#' columns. Returns a cleaned tibble.
#'
#' @param url URL of the Wikipedia article revision.
#' @return A tibble with columns: name, link, city, state, wiki_slug,
#'   management, and other wiki table columns (snake_case).
scrape_wiki_detention_table <- function(
    url = "https://en.wikipedia.org/w/index.php?title=List_of_immigrant_detention_sites_in_the_United_States&oldid=1334453072"
) {
  response <- httr::GET(url)
  httr::stop_for_status(response)

  page <- rvest::read_html(httr::content(response, as = "text"))

  table_node <- rvest::html_element(page, "table.wikitable")
  tbl <- rvest::html_table(table_node)

  # Extract hrefs from the first <td> of each row
  rows <- rvest::html_elements(table_node, "tr")
  links <- purrr::map_chr(rows, function(row) {
    link_node <- rvest::html_element(row, "td:first-child a")
    href <- rvest::html_attr(link_node, "href")
    if (is.na(href)) NA_character_ else paste0("https://en.wikipedia.org", href)
  })

  # Align links vector with table rows (header row may add an extra)
  if (length(links) > nrow(tbl)) {
    links <- links[(length(links) - nrow(tbl) + 1):length(links)]
  }

  tbl <- tibble::add_column(tbl, link = links, .after = 1)

  # Clean column names to snake_case
  tbl <- tbl |>
    dplyr::rename_with(~ stringr::str_replace_all(., "[^a-zA-Z0-9]+", "_")) |>
    dplyr::rename_with(~ stringr::str_remove_all(., "^_+|_+$")) |>
    dplyr::rename_with(tolower)

  # Derive wiki_slug from link
  tbl <- tbl |>
    dplyr::mutate(
      wiki_slug = dplyr::case_when(
        stringr::str_detect(link, "/wiki/") ~ {
          slug <- stringr::str_extract(link, "(?<=/wiki/).*")
          stringr::str_replace_all(slug, "_", " ")
        },
        TRUE ~ ""
      )
    )

  # Separate location into city/state
  tbl <- tbl |>
    tidyr::separate(location, into = c("city", "state"),
                    sep = ",\\s*", extra = "merge", fill = "right")

  # Normalize the facility name column to "name" regardless of table version.
  # The old revision used "Name" (→ "name"); the current table uses
  # "Facility Name" (→ "facility_name").
  if ("facility_name" %in% names(tbl) && !"name" %in% names(tbl)) {
    tbl <- dplyr::rename(tbl, name = facility_name)
  }

  # Strip Wikipedia reference brackets like [1], [23]
  tbl <- tbl |>
    dplyr::mutate(dplyr::across(
      dplyr::where(is.character),
      ~ gsub("\\[\\d+\\]", "", .)
    ))

  tbl
}


# ── Layer 2: Build match table ───────────────────────────────────────────────

#' Compare ICE and Wikipedia facility names by city/state
#'
#' Identifies (city, state) locations present in both data sources where the
#' facility names differ, then filters to cases where the Wikipedia entry has
#' a wiki link or management info. Applies the does_not_match exclusion list.
#'
#' @param facilities_df ICE facilities tibble with facility_name, facility_city,
#'   facility_state (2-letter abbreviation).
#' @param wiki_table Output of scrape_wiki_detention_table().
#' @return A tibble of matched pairs: ice_name, wiki_name, location,
#'   has_wiki_link, has_management_info.
build_wiki_match_table <- function(facilities_df, wiki_table) {
  ice_clean <- facilities_df |>
    dplyr::transmute(
      original_name = facility_name,
      clean_name  = stringr::str_to_upper(stringr::str_trim(facility_name)),
      clean_city  = stringr::str_to_upper(stringr::str_trim(facility_city)),
      clean_state = stringr::str_to_upper(state.name[match(facility_state, state.abb)]),
      source = "ICE"
    )

  wiki_clean <- wiki_table |>
    dplyr::transmute(
      original_name = name,
      clean_name  = stringr::str_to_upper(stringr::str_trim(name)),
      clean_city  = stringr::str_to_upper(stringr::str_trim(city)),
      clean_state = stringr::str_to_upper(stringr::str_trim(state)),
      source = "Wiki"
    )

  names_with_wikilinks <- wiki_table |>
    dplyr::filter(wiki_slug != "") |>
    dplyr::pull(name)

  names_with_management <- wiki_table |>
    dplyr::filter(management != "") |>
    dplyr::pull(name)

  comparison <- dplyr::bind_rows(ice_clean, wiki_clean) |>
    dplyr::filter(!is.na(clean_city), !is.na(clean_state)) |>
    dplyr::group_by(clean_city, clean_state) |>
    dplyr::summarise(
      num_variants  = dplyr::n_distinct(clean_name),
      in_both       = all(c("ICE", "Wiki") %in% source),
      ice_variants  = paste(unique(original_name[source == "ICE"]), collapse = " | "),
      wiki_variants = paste(unique(original_name[source == "Wiki"]), collapse = " | "),
      .groups = "drop"
    ) |>
    dplyr::filter(num_variants > 1, in_both)

  # Require exactly one ICE name and one wiki name, with useful wiki info
  match_table <- comparison |>
    dplyr::filter(
      !stringr::str_detect(ice_variants, "\\|"),
      !stringr::str_detect(wiki_variants, "\\|")
    ) |>
    dplyr::mutate(
      has_wiki_link       = stringr::str_trim(wiki_variants) %in% names_with_wikilinks,
      has_management_info = stringr::str_trim(wiki_variants) %in% names_with_management
    ) |>
    dplyr::filter(has_wiki_link | has_management_info) |>
    dplyr::filter(!(ice_variants %in% wiki_does_not_match())) |>
    dplyr::mutate(location = paste(clean_city, clean_state, sep = ", ")) |>
    dplyr::select(ice_name = ice_variants, wiki_name = wiki_variants,
                  location, has_wiki_link, has_management_info)

  match_table
}


# ── Layer 3: Merge Wikipedia info onto facilities ────────────────────────────

#' Add wiki_match, wiki_slug, and management columns to facilities data
#'
#' Three-pass matching: (1) direct name match against wiki table, (2) city/state
#' alias lookup via match_table, (3) Wikipedia API search results. Then joins
#' wiki_slug and management from the wiki table.
#'
#' @param facilities_df ICE facilities tibble (must have facility_name, facility_state).
#' @param wiki_table Output of scrape_wiki_detention_table().
#' @param match_table Output of build_wiki_match_table().
#' @param search_matches Output of add_wikipedia_matches() on the same facilities_df.
#' @return facilities_df with wiki_match, wiki_slug, and management columns added.
add_wiki_columns <- function(facilities_df, wiki_table, match_table, search_matches) {


  # Build the filtered search match list: exact API matches, minus exclusions.
  # If search_matches was run on data that already had wiki_match from passes
  # 1/2, keep only genuinely new matches (wiki_match was NA). If wiki_match
  # doesn't exist (API search ran on raw data), keep all exact matches.
  search_match_list <- search_matches |>
    dplyr::filter(wikipedia_match) |>
    dplyr::filter(!(facility_name %in% wiki_search_exclude_list()))
  if ("wiki_match" %in% names(search_match_list)) {
    search_match_list <- search_match_list |> dplyr::filter(is.na(wiki_match))
  }
  search_match_list <- search_match_list |>
    dplyr::select(facility_name, wikipedia_title)

  result <- facilities_df |>
    dplyr::mutate(
      clean_state = state.name[match(facility_state, state.abb)]
    ) |>
    dplyr::mutate(
      wiki_match = dplyr::case_when(
        # Pass 1: direct name match
        facility_name %in% wiki_table$name ~ facility_name,
        # Pass 2: city/state alias lookup
        facility_name %in% match_table$ice_name ~
          match_table$wiki_name[match(facility_name, match_table$ice_name)],
        # Pass 3: Wikipedia API search
        facility_name %in% search_match_list$facility_name ~
          search_match_list$wikipedia_title[match(facility_name,
                                                   search_match_list$facility_name)],
        TRUE ~ NA_character_
      )
    ) |>
    dplyr::left_join(
      dplyr::select(wiki_table, name, state, wiki_slug, management),
      by = c("wiki_match" = "name", "clean_state" = "state")
    )

  result
}


#' Backfill wiki_slug from a newer scrape of the Wikipedia article
#'
#' Other editors may add article links after our initial scrape. This function
#' matches facilities by wiki_match (or facility_name) against a newer wiki
#' table and fills in wiki_slug where it was previously empty. Also picks up
#' new management values.
#'
#' @param df Facilities tibble with wiki_match and wiki_slug columns.
#' @param wiki_table_new Output of scrape_wiki_detention_table() on a newer revision.
#' @return df with wiki_slug and management backfilled where possible.
backfill_wiki_slugs <- function(df, wiki_table_new) {
  # Build a lookup from the new table: name → slug, management

  new_links <- wiki_table_new |>
    dplyr::filter(wiki_slug != "") |>
    dplyr::select(name, new_slug = wiki_slug, new_management = management)

  df |>
    # Join on wiki_match (the Wikipedia name we've already identified)
    dplyr::left_join(new_links, by = c("wiki_match" = "name")) |>
    dplyr::mutate(
      wiki_slug = dplyr::if_else(
        is.na(wiki_slug) | wiki_slug == "",
        dplyr::coalesce(new_slug, wiki_slug),
        wiki_slug
      ),
      management = dplyr::if_else(
        is.na(management) | management == "",
        dplyr::coalesce(new_management, management),
        management
      )
    ) |>
    dplyr::select(-new_slug, -new_management)
}


# ── Canonical-level matching ─────────────────────────────────────────────────

#' Match canonical facilities to Wikipedia articles via the wiki detention table
#'
#' Only matches against wiki table rows that have a non-empty `wiki_slug` (i.e.
#' an outgoing link to a Wikipedia article). A name appearing in the table
#' without a link does not signify that a Wikipedia article exists.
#'
#' Three-pass matching:
#'
#' 1. **Direct name match** — canonical_name matches a linked wiki row's `name`
#'    or base name (after stripping parenthetical suffixes).
#' 2. **City/state alias** — 1:1 city/state pairs with different names, where
#'    the wiki row has a link. Excludes known false positives.
#' 3. **Manual resolutions** — hand-verified matches for multi-facility cities,
#'    renames, or disambiguation suffixes.
#'
#' @param canonical_df Canonical facilities tibble with canonical_name,
#'   facility_city, facility_state (2-letter abbreviation).
#' @param wiki_table Output of scrape_wiki_detention_table().
#' @return A tibble with columns: canonical_name, wiki_name, wiki_slug,
#'   management, match_pass (1/2/3).
build_canonical_wiki_match <- function(canonical_df, wiki_table) {

  canon_state_full <- function(abbr) {
    stringr::str_to_upper(state.name[match(abbr, state.abb)])
  }

  # Only consider wiki rows with an outgoing article link
  wiki_linked <- wiki_table |>
    dplyr::filter(wiki_slug != "") |>
    dplyr::mutate(
      base_name = stringr::str_trim(stringr::str_remove(name, "\\(.*"))
    )

  # ── Pass 1: Direct name match ──────────────────────────────────────────
  pass1 <- canonical_df |>
    dplyr::transmute(
      canonical_name,
      wiki_name = dplyr::case_when(
        canonical_name %in% wiki_linked$name      ~ canonical_name,
        canonical_name %in% wiki_linked$base_name ~
          wiki_linked$name[match(canonical_name, wiki_linked$base_name)],
        TRUE ~ NA_character_
      ),
      match_pass = 1L
    ) |>
    dplyr::filter(!is.na(wiki_name))

  matched_canon <- pass1$canonical_name

  # ── Pass 2: City/state alias (1:1 linked pairs) ───────────────────────
  exclude_list <- canonical_wiki_does_not_match()

  canon_clean <- canonical_df |>
    dplyr::filter(!(canonical_name %in% matched_canon)) |>
    dplyr::transmute(
      original_name = canonical_name,
      clean_name  = stringr::str_to_upper(stringr::str_trim(canonical_name)),
      clean_city  = stringr::str_to_upper(stringr::str_trim(facility_city)),
      clean_state = canon_state_full(facility_state),
      source = "canon"
    )

  wiki_clean <- wiki_linked |>
    dplyr::transmute(
      original_name = name,
      clean_name  = stringr::str_to_upper(stringr::str_trim(name)),
      clean_city  = stringr::str_to_upper(stringr::str_trim(city)),
      clean_state = stringr::str_to_upper(stringr::str_trim(state)),
      source = "wiki"
    )

  comparison <- dplyr::bind_rows(canon_clean, wiki_clean) |>
    dplyr::filter(!is.na(clean_city), !is.na(clean_state)) |>
    dplyr::group_by(clean_city, clean_state) |>
    dplyr::summarise(
      num_variants = dplyr::n_distinct(clean_name),
      in_both      = all(c("canon", "wiki") %in% source),
      canon_names  = paste(unique(original_name[source == "canon"]), collapse = " | "),
      wiki_names   = paste(unique(original_name[source == "wiki"]), collapse = " | "),
      .groups = "drop"
    ) |>
    dplyr::filter(num_variants > 1, in_both,
                  !stringr::str_detect(canon_names, "\\|"),
                  !stringr::str_detect(wiki_names, "\\|")) |>
    dplyr::filter(!(canon_names %in% exclude_list))

  pass2 <- comparison |>
    dplyr::transmute(
      canonical_name = canon_names,
      wiki_name      = wiki_names,
      match_pass     = 2L
    )

  matched_canon <- c(matched_canon, pass2$canonical_name)

  # ── Pass 3: Manual multi-facility resolutions ──────────────────────────
  manual <- canonical_wiki_manual_matches() |>
    dplyr::filter(!(canonical_name %in% matched_canon)) |>
    dplyr::transmute(canonical_name, wiki_name, match_pass = 3L)

  # ── Pass 4: External matches (API search / category members) ─────────
  external <- canonical_wiki_external_matches() |>
    dplyr::filter(!(canonical_name %in% c(matched_canon, manual$canonical_name))) |>
    dplyr::transmute(
      canonical_name,
      wiki_name = NA_character_,
      match_pass = 4L,
      wiki_slug,
      management = NA_character_
    )

  # ── Combine, join wiki info, apply overrides ─────────────────────────
  table_matches <- dplyr::bind_rows(pass1, pass2, manual) |>
    dplyr::left_join(
      wiki_linked |> dplyr::select(name, wiki_slug, management),
      by = c("wiki_name" = "name")
    )

  all_matches <- dplyr::bind_rows(table_matches, external) |>
    apply_wiki_slug_overrides() |>
    dplyr::filter(wiki_slug != "")

  message(sprintf(
    "canonical wiki match: %d pass-1, %d pass-2, %d pass-3, %d pass-4, %d after overrides (%d of %d)",
    nrow(pass1), nrow(pass2), nrow(manual), nrow(external),
    nrow(all_matches), nrow(all_matches), nrow(canonical_df)
  ))

  all_matches
}


#' Apply the contractors management patch
#'
#' Reads the contractors CSV, applies name fixes to align with ICE facility
#' names, then updates the management column via rows_update().
#'
#' @param df Facilities tibble with facility_name and management columns.
#' @param patch_path Path to the contractors-patch CSV file.
#' @return df with management column updated for matching facilities.
apply_contractors_patch <- function(df, patch_path) {
  patch <- utils::read.csv(patch_path)
  names(patch) <- c("facility_name", "location", "management")

  name_fixes <- contractors_patch_name_fixes()

  patch <- patch |>
    dplyr::left_join(name_fixes, by = "facility_name") |>
    dplyr::mutate(facility_name = dplyr::coalesce(matched_ice_facility, facility_name)) |>
    dplyr::select(-matched_ice_facility)

  df |>
    dplyr::rows_update(
      dplyr::select(patch, facility_name, management),
      by = "facility_name",
      unmatched = "ignore"
    )
}


#' Standardize management strings using the management lookup table
#'
#' Replaces known variant management strings with their canonical form.
#' Strings not in the lookup are left unchanged.
#'
#' @param df Facilities tibble with a management column.
#' @return df with management values standardized.
standardize_management <- function(df) {
  lookup <- management_lookup() |>
    dplyr::distinct(raw_operator, management)

  df |>
    dplyr::left_join(lookup, by = c("management" = "raw_operator")) |>
    dplyr::mutate(
      management = dplyr::coalesce(management.y, management)
    ) |>
    dplyr::select(-management.y)
}


# ── Validation: Check Wikipedia article existence/redirects ────────────────

#' Check whether Wikipedia article(s) exist and whether they are redirects
#'
#' Queries the Wikipedia API for one or more page titles in batch (up to 50 per
#' request). Returns a tibble with one row per title indicating whether the page
#' exists, whether it is a redirect, and (if so) the resolved target article.
#'
#' @param titles Character vector of Wikipedia article titles to check.
#' @param lang Language code (default `"en"`).
#' @param batch_size Number of titles per API request (max 50).
#' @return A tibble with columns `title`, `exists` (logical), `redirect`
#'   (logical), and `redirect_target` (character, NA if not a redirect).
check_wiki_articles <- function(titles, lang = "en", batch_size = 50) {
  api_url <- sprintf("https://%s.wikipedia.org/w/api.php", lang)

  batches <- split(titles, ceiling(seq_along(titles) / batch_size))

  purrr::map(batches, function(batch) {
    # First pass: page info without following redirects
    resp_info <- httr::GET(api_url, query = list(
      action = "query",
      titles = paste(batch, collapse = "|"),
      prop   = "info",
      format = "json"
    ))
    pages_info <- httr::content(resp_info)$query$pages

    info_map <- purrr::map(pages_info, function(p) {
      list(
        title    = p$title,
        exists   = is.null(p$missing),
        redirect = !is.null(p$redirect)
      )
    }) |> purrr::set_names(purrr::map_chr(pages_info, "title"))

    # Second pass: resolve redirect targets
    redirects_in_batch <- purrr::keep(info_map, ~ .x$redirect)
    redirect_targets <- character(0)

    if (length(redirects_in_batch) > 0) {
      redirect_titles <- purrr::map_chr(redirects_in_batch, "title")
      resp_redir <- httr::GET(api_url, query = list(
        action    = "query",
        titles    = paste(redirect_titles, collapse = "|"),
        redirects = 1,
        format    = "json"
      ))
      redir_list <- httr::content(resp_redir)$query$redirects
      if (!is.null(redir_list)) {
        redirect_targets <- purrr::set_names(
          purrr::map_chr(redir_list, "to"),
          purrr::map_chr(redir_list, "from")
        )
      }
    }

    # Assemble per-title results in input order
    purrr::map(batch, function(t) {
      info <- info_map[[t]]
      if (is.null(info)) {
        # Title may have been normalized by the API (e.g. underscores → spaces)
        resp_norm <- httr::GET(api_url, query = list(
          action = "query", titles = t, prop = "info", format = "json"
        ))
        normalized <- httr::content(resp_norm)$query
        if (!is.null(normalized$normalized)) {
          norm_to <- normalized$normalized[[1]]$to
          info <- info_map[[norm_to]]
        }
        if (is.null(info)) {
          info <- list(title = t, exists = FALSE, redirect = FALSE)
        }
      }

      tibble::tibble(
        title           = t,
        exists          = info$exists,
        redirect        = info$redirect,
        redirect_target = unname(redirect_targets[info$title]) %||% NA_character_
      )
    }) |> purrr::list_rbind()
  }) |> purrr::list_rbind()
}


#' Fill missing management data from fl17 operator field
#'
#' For facilities that still lack a management value after wiki matching and the
#' contractors patch, looks up the fl17 facility_operator via canonical_id and
#' translates it to a standardized management string using management_lookup().
#'
#' @param df Facilities tibble with canonical_id and management columns.
#' @param fl17_keyed faclist17_keyed tibble with canonical_id and facility_operator.
#' @return df with management filled in where possible from fl17.
apply_fl17_management <- function(df, fl17_keyed) {
  lookup <- management_lookup()

  fl17_mgmt <- fl17_keyed |>
    dplyr::filter(!is.na(facility_operator), facility_operator != "") |>
    dplyr::distinct(canonical_id, facility_operator) |>
    dplyr::left_join(lookup, by = c("facility_operator" = "raw_operator")) |>
    dplyr::select(canonical_id, fl17_management = management)

  df |>
    dplyr::left_join(fl17_mgmt, by = "canonical_id") |>
    dplyr::mutate(
      management = dplyr::coalesce(
        dplyr::if_else(is.na(management) | management == "", NA_character_, management),
        fl17_management
      )
    ) |>
    dplyr::select(-fl17_management)
}
