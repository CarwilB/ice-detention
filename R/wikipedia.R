# Wikipedia wikitext generation for ICE detention facilities.
# Produces {{Infobox prison}} and population wikitable wikitext for individual facility articles.

# ── State reference tables ───────────────────────────────────────────────────

state_full_names <- c(
  "AL" = "Alabama",        "AK" = "Alaska",         "AZ" = "Arizona",
  "AR" = "Arkansas",       "CA" = "California",     "CO" = "Colorado",
  "CT" = "Connecticut",    "DE" = "Delaware",        "FL" = "Florida",
  "GA" = "Georgia",        "HI" = "Hawaii",          "ID" = "Idaho",
  "IL" = "Illinois",       "IN" = "Indiana",         "IA" = "Iowa",
  "KS" = "Kansas",         "KY" = "Kentucky",        "LA" = "Louisiana",
  "ME" = "Maine",          "MD" = "Maryland",        "MA" = "Massachusetts",
  "MI" = "Michigan",       "MN" = "Minnesota",       "MS" = "Mississippi",
  "MO" = "Missouri",       "MT" = "Montana",         "NE" = "Nebraska",
  "NV" = "Nevada",         "NH" = "New Hampshire",   "NJ" = "New Jersey",
  "NM" = "New Mexico",     "NY" = "New York",        "NC" = "North Carolina",
  "ND" = "North Dakota",   "OH" = "Ohio",            "OK" = "Oklahoma",
  "OR" = "Oregon",         "PA" = "Pennsylvania",    "RI" = "Rhode Island",
  "SC" = "South Carolina", "SD" = "South Dakota",    "TN" = "Tennessee",
  "TX" = "Texas",          "UT" = "Utah",            "VT" = "Vermont",
  "VA" = "Virginia",       "WA" = "Washington",      "WV" = "West Virginia",
  "WI" = "Wisconsin",      "WY" = "Wyoming",         "DC" = "Washington, D.C.",
  "PR" = "Puerto Rico",    "GU" = "Guam",            "Cuba" = "Cuba"
)

# Maps 2-letter state codes to the {{location map}} name used in pushpin_map.
# Territories and special cases fall through to the "USA" national map.
state_pushpin_map <- dplyr::coalesce(
  paste("USA", state_full_names),
  "USA"
)
names(state_pushpin_map) <- names(state_full_names)
# Overrides for non-standard map names
state_pushpin_map["DC"]   <- "USA Washington DC"
state_pushpin_map["PR"]   <- "Puerto Rico"
state_pushpin_map["GU"]   <- "Guam"
state_pushpin_map["Cuba"] <- "Cuba"

# ── Source metadata and citation templates ──────────────────────────────────

#' Per-file metadata for ICE annual detention stats (FY19–FY26).
#'
#' One row per fiscal year with local file path, download URL, data-as-of date,
#' and a Wikipedia {{Cite web}} template string.
ice_source_info <- tibble::tibble(
  year_name = c("FY19", "FY20", "FY21", "FY22", "FY23", "FY24", "FY25", "FY26"),
  fiscal_year = 2019:2026,
  local_file = c(
    "data/ice/FY19-detentionstats.xlsx",
    "data/ice/FY20-detentionstats.xlsx",
    "data/ice/FY21-detentionstats.xlsx",
    "data/ice/FY22-detentionStats.xlsx",
    "data/ice/FY23_detentionStats.xlsx",
    "data/ice/FY24_detentionStats.xlsx",
    "data/ice/FY25_detentionStats09242025.xlsx",
    "data/ice/FY26_detentionStats02022026.xlsx"
  ),
  url = c(
    "https://www.ice.gov/doclib/detention/FY19-detentionstats.xlsx",
    "https://www.ice.gov/doclib/detention/FY20-detentionstats.xlsx",
    "https://www.ice.gov/doclib/detention/FY21-detentionstats.xlsx",
    "https://www.ice.gov/doclib/detention/FY22-detentionStats.xlsx",
    "https://www.ice.gov/doclib/detention/FY23_detentionStats.xlsx",
    "https://www.ice.gov/doclib/detention/FY24_detentionStats.xlsx",
    "https://www.ice.gov/doclib/detention/FY25_detentionStats09242025.xlsx",
    "https://www.ice.gov/doclib/detention/FY26_detentionStats02022026.xlsx"
  ),
  data_as_of = as.Date(c(
    "2019-09-30", "2020-09-30", "2021-09-30", "2022-09-30",
    "2023-09-30", "2024-09-30", "2025-09-24", "2026-02-02"
  )),
  raw_target = paste0("facilities_raw$", year_name),
  clean_target = paste0("facilities_clean$", year_name),
  aggregated_target = paste0("facilities_aggregated$", year_name),
  keyed_target = paste0("facilities_keyed$", year_name),
  citation = glue::glue(
    '{{{{Cite web | publisher = U.S. Department of Homeland Security',
    ' | last = U.S. Immigration and Customs Enforcement',
    ' | title = ICE Detention Statistics FY {fiscal_year}',
    ' | date = {data_as_of}',
    ' | url = {url}}}}}'
  )
)

#' Per-source metadata for DMCP facility listings (covering FY10–FY17).
#'
#' Two rows: faclist15 (Dec 2015 XLSX, FY10–FY16) and faclist17 (Jul 2017 PDF,
#' FY10–FY17). The faclist17 citation is used for FY10–FY17; faclist15 is used
#' only for the 28 facilities absent from faclist17.
dmcp_source_info <- tibble::tibble(
  source_id = c("faclist15", "faclist17"),
  title = c(
    "ICE Detention Facility Data \u2014 December 8, 2015 Snapshot",
    "ICE DMCP Facility List \u2014 ERO Custody Management Division, FY2017"
  ),
  url = c(
    "https://www.ice.gov/doclib/foia/dfs/2015IceDetentionFacilityListing.xlsx",
    "https://www.prisonlegalnews.org/media/publications/ICE_DMCP_Facility_List_ERO_Custody_Management_Division_2017.pdf"
  ),
  data_as_of = as.Date(c("2015-12-08", "2017-07-10")),
  fiscal_years_covered = list(2010:2016, 2010:2017),
  citation = c(
    paste0(
      "{{Cite web | publisher = U.S. Department of Homeland Security",
      " | last = U.S. Immigration and Customs Enforcement",
      " | title = ICE Detention Facility Data \u2014 December 8, 2015",
      " | date = 2015-12-08",
      " | url = https://www.ice.gov/doclib/foia/dfs/2015IceDetentionFacilityListing.xlsx}}"
    ),
    paste0(
      "{{Cite web | publisher = U.S. Department of Homeland Security",
      " | last = U.S. Immigration and Customs Enforcement",
      " | title = ICE DMCP Facility List \u2014 ERO Custody Management Division, FY2017",
      " | date = 2017-07-10",
      " | url = https://www.prisonlegalnews.org/media/publications/",
      "ICE_DMCP_Facility_List_ERO_Custody_Management_Division_2017.pdf}}"
    )
  )
)

#' Build a combined Wikipedia citation footnote for ICE detention stats.
#'
#' The first year in the sequence gets the full {{Cite web}} template.
#' Remaining years are appended as "Additional fiscal year data:" with
#' external-link syntax: [url FYxx].
#'
#' @param years Integer vector of fiscal years (e.g. c(2019, 2021, 2023))
#'   or character vector of year labels (e.g. c("FY19", "FY21", "FY23")).
#'   Must be a subset of FY19–FY26.
#' @param source_info Tibble with columns year_name, fiscal_year, url, citation.
#'   Defaults to ice_source_info.
#' @return A single character string with the combined footnote wikitext.
ice_citation <- function(years, source_info = ice_source_info) {
  if (is.numeric(years)) {
    labels <- paste0("FY", years %% 100)
  } else {
    labels <- as.character(years)
  }

  valid <- source_info$year_name
  bad <- setdiff(labels, valid)
  if (length(bad) > 0) {
    stop("Unknown year(s): ", paste(bad, collapse = ", "),
         ". Valid: ", paste(valid, collapse = ", "))
  }

  rows <- source_info[match(labels, source_info$year_name), ]

  out <- rows$citation[1]

  if (nrow(rows) > 1) {
    links <- paste0("[", rows$url[-1], " ", rows$year_name[-1], "]")
    out <- paste0(out, " Additional fiscal year data: ",
                  paste(links, collapse = ", "), ".")
  }

  out
}


#' Look up the citation for a fiscal year label (FYxx string).
#'
#' Returns the appropriate {{Cite web}} template for any year in FY10–FY26.
#' FY19–FY26 use the annual ICE stats citations. FY10–FY17 use the DMCP
#' faclist17 citation (primary source) with faclist15 as a fallback note.
#'
#' @param fy Character fiscal year label, e.g. "FY26" or "FY10".
#' @return Character scalar: the citation template string, or NA if unknown.
citation_for_fy <- function(fy) {
  # FY19–FY26: annual stats
  ice_row <- ice_source_info[ice_source_info$year_name == fy, ]
  if (nrow(ice_row) > 0) return(ice_row$citation[1])

  # FY10–FY17: DMCP listings (faclist17 is primary for all years)
  fy_num <- as.integer(paste0("20", sub("^FY", "", fy)))
  dmcp_row <- dmcp_source_info[
    purrr::map_lgl(dmcp_source_info$fiscal_years_covered, ~ fy_num %in% .x),
  ]
  # Prefer faclist17
  if ("faclist17" %in% dmcp_row$source_id) {
    return(dmcp_row$citation[dmcp_row$source_id == "faclist17"])
  }
  if (nrow(dmcp_row) > 0) return(dmcp_row$citation[1])

  NA_character_
}


# ── Field-level helpers ──────────────────────────────────────────────────────

# Convert compact FY labels ("FY26") to display format ("FY 2026").
format_fy <- function(fy) {
  if (is.null(fy) || is.na(fy) || fy == "") return(fy)
  yy <- sub("^FY", "", fy)
  full <- ifelse(as.integer(yy) >= 50, paste0("19", yy), paste0("20", yy))
  paste0("FY ", full)
}

# Render one {{Infobox prison}} parameter line; returns NULL if value is blank.
ib_field <- function(key, value) {
  if (is.null(value) || is.na(value) || trimws(as.character(value)) == "")
    return(NULL)
  sprintf("| %-22s = %s", key, value)
}

# Format decimal lat/lon as a {{coord}} template.
format_coord <- function(lat, lon) {
  if (is.na(lat) || is.na(lon)) return(NULL)
  glue::glue("{{{{coord|{round(lat, 5)}|{round(lon, 5)}|type:landmark|display=inline,title}}}}")
}

# Format city + state abbreviation as a wikilinked location string.
format_location <- function(city, state) {
  state_full <- dplyr::coalesce(state_full_names[state], state)
  glue::glue("[[{city}, {state_full}]]")
}

# ── Main infobox generator ───────────────────────────────────────────────────

#' Generate {{Infobox prison}} wikitext for one canonical ICE facility.
#'
#' @param cid                  canonical_id integer
#' @param panel_facilities one-row-per-facility table from build_panel_facilities()
#' @param presence             facility_presence data frame
#' @param geocoded             facilities_geocoded data frame
#' @param panel                facilities_panel data frame (used for ADP, capacity, type)
#' @param crosswalk            facility_crosswalk data frame (used for former names)
#' @param wiki_matches         optional data frame with wiki_slug and management columns,
#'                             keyed on facility_name (from facilities_fy26_wiki_matches.rds)
#' @return Character scalar containing the complete {{Infobox prison}} wikitext.
generate_infobox <- function(cid, panel_facilities, presence, geocoded,
                              panel = NULL, crosswalk = NULL, wiki_matches = NULL,
                              include_capacity = FALSE) {

  # ── Identity row from canonical list ──────────────────────────────────
  row <- panel_facilities |> dplyr::filter(canonical_id == cid)
  if (nrow(row) == 0) stop("canonical_id ", cid, " not found in panel_facilities")

  # ── Most recent panel row (for ADP, capacity, facility type) ──────────
  if (!is.null(panel)) {
    panel_row <- panel |>
      dplyr::filter(canonical_id == cid) |>
      dplyr::mutate(year_rank = match(fiscal_year, year_order)) |>
      dplyr::slice_max(year_rank, n = 1, with_ties = FALSE)
  } else {
    panel_row <- dplyr::tibble()
  }

  get_panel <- function(col) {
    if (nrow(panel_row) == 0 || !col %in% names(panel_row)) return(NA)
    panel_row[[col]][1]
  }

  # ── Status (operational vs. closed) ───────────────────────────────────
  pres      <- presence |> dplyr::filter(canonical_id == cid)
  last_year <- tail(year_order[year_order %in% names(pres)], 1)
  is_open   <- isTRUE(pres[[last_year]])
  status    <- if (is_open) "Operational" else "Closed"

  # ── Coordinates and pushpin map ────────────────────────────────────────
  geo    <- geocoded |> dplyr::filter(canonical_id == cid)
  coords <- if (nrow(geo) > 0) format_coord(geo$lat[1], geo$lon[1]) else NULL
  pmap   <- dplyr::coalesce(state_pushpin_map[row$facility_state], "USA")

  # ── Former names (other name variants for the same canonical_id) ───────
  former <- NULL
  if (!is.null(crosswalk)) {
    alt_names <- crosswalk |>
      dplyr::filter(canonical_id == cid,
                    facility_name != row$canonical_name) |>
      dplyr::pull(facility_name) |>
      unique()
    if (length(alt_names) > 0)
      former <- paste(alt_names, collapse = "<br>")
  }

  # ── Management (from Wikipedia-matched data, keyed on canonical_id) ───
  managed_by <- NULL
  if (!is.null(wiki_matches) && "canonical_id" %in% names(wiki_matches)) {
    mgmt <- wiki_matches |>
      dplyr::filter(canonical_id == cid,
                    !is.na(management), management != "") |>
      dplyr::pull(management)
    if (length(mgmt) > 0) managed_by <- mgmt[1]
  }

  # ── Population (total ADP) and capacity ───────────────────────────────
  adp_val  <- get_panel("sum_criminality_levels")
  fy       <- get_panel("fiscal_year")

  # Build <ref> for the most recent year's ADP citation
  adp_ref <- ""
  if (!is.na(fy)) {
    cite <- citation_for_fy(fy)
    if (!is.na(cite)) {
      ref_name <- paste0("ice-detention-", tolower(fy))
      adp_ref  <- paste0('<ref name="', ref_name, '">', cite, "</ref>")
    }
  }

  adp <- if (!is.na(adp_val) && adp_val > 0) {
    paste0(as.character(round(adp_val)), adp_ref)
  } else {
    NULL
  }

  pop_as_of <- if (!is.na(fy) && fy %in% c("FY25", "FY26"))
    paste0(format_fy(fy), " (YTD)") else format_fy(fy)

  capacity <- NULL
  if (include_capacity) {
    cap_val  <- get_panel("inspections_guaranteed_minimum")
    capacity <- if (!is.na(cap_val) && cap_val > 0) as.character(cap_val) else NULL
  }

  ftype    <- get_panel("facility_type_wiki")

  # ── Assemble wikitext ──────────────────────────────────────────────────
  fields <- purrr::compact(list(
    ib_field("name",                row$canonical_name),
    ib_field("location",            format_location(row$facility_city,
                                                    row$facility_state)),
    ib_field("coordinates",         coords),
    ib_field("pushpin_map",         pmap),
    ib_field("pushpin_map_caption", paste("Location in",
                                          dplyr::coalesce(state_full_names[row$facility_state],
                                                          row$facility_state))),
    ib_field("status",              status),
    ib_field("classification",      ftype),
    ib_field("capacity",            capacity),
    ib_field("population",          adp),
    ib_field("population_as_of",    pop_as_of),
    ib_field("opened", {
      opened_fy  <- pres$first_seen
      opened_txt <- format_fy(opened_fy)
      if (!is.null(opened_txt) && !is.na(opened_txt) && opened_txt != "") {
        opened_cite <- citation_for_fy(opened_fy)
        if (!is.na(opened_cite)) {
          opened_ref_name <- paste0("ice-detention-", tolower(opened_fy))
          # Reuse existing ref if same as ADP ref; otherwise define it
          if (!is.na(fy) && tolower(opened_fy) == tolower(fy)) {
            opened_txt <- paste0(opened_txt, '<ref name="', opened_ref_name, '"/>')
          } else {
            opened_txt <- paste0(opened_txt, '<ref name="', opened_ref_name, '">',
                                 opened_cite, "</ref>")
          }
        }
      }
      opened_txt
    }),
    if (!is_open) ib_field("closed", format_fy(pres$last_seen)) else NULL,
    if (!is.null(former)) ib_field("former_name", former) else NULL,
    ib_field("managed_by",          managed_by),
    ib_field("street-address",      row$facility_address),
    ib_field("city",                row$facility_city),
    ib_field("state",               row$facility_state),
    ib_field("zip",                 row$facility_zip),
    ib_field("country",             "USA")
  ))

  paste(c("{{Infobox prison", fields, "}}"), collapse = "\n")
}

# ── ADP bar chart ──────────────────────────────────────────────────────────

#' Generate a {{Bar chart}} wikitext for one canonical ICE facility's ADP history.
#'
#' Produces a horizontal bar chart template showing average daily population
#' across all fiscal years the facility appears in the panel. Years where ADP
#' is zero or the facility is absent are omitted.
#'
#' @param cid               canonical_id integer
#' @param facilities_panel  long panel data frame (one row per facility per year)
#' @param facility_presence one row per facility with first_seen, last_seen, canonical_name
#' @return Character scalar containing the complete {{Bar chart}} wikitext.
generate_adp_bar_chart <- function(cid, facilities_panel, facility_presence) {
  pres <- facility_presence |> dplyr::filter(canonical_id == cid)
  if (nrow(pres) == 0) stop("canonical_id ", cid, " not found in facility_presence")

  fname <- pres$canonical_name

  # Aggregate to one row per fiscal year (some facilities have sub-entries)
  panel_fac <- facilities_panel |>
    dplyr::filter(canonical_id == cid, !is.na(adp), adp > 0) |>
    dplyr::summarise(adp = sum(adp), .by = fiscal_year) |>
    dplyr::mutate(year_rank = match(fiscal_year, year_order)) |>
    dplyr::arrange(year_rank) |>
    dplyr::select(fiscal_year, adp)

  if (nrow(panel_fac) == 0) return("")

  data_max <- ceiling(max(panel_fac$adp) * 1.05)

  # ── Build citation ref tags for the years covered ──────────────────────
  fy_present <- panel_fac$fiscal_year
  ice_fys  <- intersect(fy_present, ice_source_info$year_name)
  dmcp_fys <- setdiff(fy_present, ice_source_info$year_name)

  refs <- character(0)

  if (length(ice_fys) > 0) {
    ref_name <- paste0("ice-detention-",
                       tolower(ice_fys[1]), "-", tolower(ice_fys[length(ice_fys)]))
    cite <- ice_citation(ice_fys)
    refs <- c(refs, paste0('<ref name="', ref_name, '">', cite, "</ref>"))
  }

  if (length(dmcp_fys) > 0) {
    # All DMCP years use the faclist17 citation
    ref_name <- "ice-dmcp-faclist17"
    cite <- dmcp_source_info$citation[dmcp_source_info$source_id == "faclist17"]
    refs <- c(refs, paste0('<ref name="', ref_name, '">', cite, "</ref>"))
  }

  ref_str <- paste(refs, collapse = "")

  # Build numbered label/data lines
  lines <- purrr::imap_chr(seq_len(nrow(panel_fac)), function(i, idx) {
    fy <- panel_fac$fiscal_year[i]
    val <- formatC(round(panel_fac$adp[i]), format = "d", big.mark = ",")
    sprintf("| label%-5s = %s | data%-5s = %s",
            idx, format_fy(fy), idx, val)
  })

  parts <- c(
    "{{Bar chart",
    sprintf("| title      = Average daily population at %s%s", fname, ref_str),
    "| bar_width  = 35",
    sprintf("| data_max   = %s",
            formatC(data_max, format = "d", big.mark = ",")),
    "| label_type = Fiscal year",
    "| data_type  = ADP",
    lines,
    "}}"
  )

  paste(parts, collapse = "\n")
}


# ── Ref deduplication ────────────────────────────────────────────────────────

#' Deduplicate named <ref> definitions across combined wikitext.
#'
#' When multiple wikitables are placed on a single page, each may independently
#' define the same <ref name="...">...</ref>. Wikipedia treats repeated
#' definitions of the same named ref as an error. This function scans the
#' combined wikitext in order, keeps the first full definition of each named
#' ref, and replaces all subsequent occurrences with a self-closing
#' <ref name="..."/> tag.
#'
#' Not needed for individual facility article pages (where each ref appears
#' once). Apply to the concatenated output when combining multiple tables.
#'
#' @param text Character scalar of combined wikitext.
#' @return Character scalar with duplicate ref definitions collapsed.
dedup_refs <- function(text) {
  pattern <- '<ref name="([^"]+)">.*?</ref>'
  seen    <- character(0)

  matches <- gregexpr(pattern, text, perl = TRUE)
  m_text  <- regmatches(text, matches)[[1]]

  replacements <- purrr::map_chr(m_text, function(m) {
    nm <- sub('<ref name="([^"]+)">.*', "\\1", m, perl = TRUE)
    if (nm %in% seen) {
      paste0('<ref name="', nm, '"/>')
    } else {
      seen <<- c(seen, nm)
      m
    }
  })

  regmatches(text, matches)[[1]] <- replacements
  text
}

# ── Population wikitable ─────────────────────────────────────────────────────

#' Generate a Wikipedia horizontal population table for one canonical ICE facility.
#'
#' Columns span the facility's active years only (trimmed at both ends by
#' first_seen / last_seen from facility_presence). Gaps in the middle are
#' shown as an em dash. Each column header carries a full inline citation
#' sourced from ris_records$wiki_citation.
#'
#' @param cid               canonical_id integer
#' @param facilities_panel  long panel data frame (one row per facility per year)
#' @param facility_presence one row per facility with FY boolean columns,
#'                          first_seen, last_seen, canonical_name
#' @param ris_records       tibble with columns fiscal_year and wiki_citation
#'                          (e.g. from data/citations/ris_records.rds)
#' @return Character scalar containing the complete wikitable wikitext.
generate_population_wikitable <- function(cid, facilities_panel, facility_presence,
                                          ris_records) {
  all_years <- c("FY19","FY20","FY21","FY22","FY23","FY24","FY25","FY26")
  ytd_years <- c("FY21","FY25","FY26")

  # ── Presence info ────────────────────────────────────────────────────
  pres <- facility_presence |> dplyr::filter(canonical_id == cid)
  if (nrow(pres) == 0) stop("canonical_id ", cid, " not found in facility_presence")

  fname      <- pres$canonical_name
  first_fy   <- pres$first_seen
  last_fy    <- pres$last_seen
  first_idx  <- match(first_fy, all_years)
  last_idx   <- match(last_fy,  all_years)
  active_years <- all_years[first_idx:last_idx]

  # ── Panel rows for this facility ─────────────────────────────────────
  panel_fac <- facilities_panel |>
    dplyr::filter(canonical_id == cid) |>
    dplyr::mutate(
      total    = sum_criminality_levels,
      crim     = adp_criminality_male_crim     + adp_criminality_female_crim,
      non_crim = adp_criminality_male_non_crim  + adp_criminality_female_non_crim,
      male     = adp_criminality_male_crim     + adp_criminality_male_non_crim,
      female   = adp_criminality_female_crim   + adp_criminality_female_non_crim
    ) |>
    dplyr::select(fiscal_year, total, crim, non_crim, male, female)

  # ── Helpers ──────────────────────────────────────────────────────────
  fy_label <- function(fy) paste("FY", as.integer(paste0("20", sub("FY", "", fy))))

  fmt_val <- function(x) {
    if (is.null(x) || length(x) == 0 || is.na(x)) return("\u2014")
    formatC(round(x), format = "d", big.mark = ",")
  }

  get_val <- function(metric, fy) {
    row <- panel_fac |> dplyr::filter(fiscal_year == fy)
    if (nrow(row) == 0) return("\u2014")
    fmt_val(row[[metric]][1])
  }

  # Build <ref name="...">{{citation}}</ref> for a given fiscal year
  make_ref <- function(fy) {
    rec <- ris_records |> dplyr::filter(fiscal_year == fy)
    if (nrow(rec) == 0) return("")
    ref_name <- paste0("ice-detention-", tolower(fy))
    paste0('<ref name="', ref_name, '">', rec$wiki_citation[1], "</ref>")
  }

  # ── Header row ───────────────────────────────────────────────────────
  has_ytd <- any(active_years %in% ytd_years)
  ncols   <- length(active_years)

  header_cells <- purrr::map_chr(active_years, function(fy) {
    ytd <- if (fy %in% ytd_years) "{{efn|YTD snapshot}}" else ""
    paste0(fy_label(fy), ytd, make_ref(fy))
  })

  header_row <- paste0(
    "! style=\"text-align:left\" | Fiscal year !! ",
    paste(header_cells, collapse = " !! ")
  )

  # ── Caption ──────────────────────────────────────────────────────────
  yr_range <- if (first_fy == last_fy) {
    fy_label(first_fy)
  } else {
    paste0(fy_label(first_fy), "\u2013", fy_label(last_fy))
  }
  caption <- paste0("|+ Average daily detainee population at ", fname, ", ", yr_range)

  # ── Data rows ────────────────────────────────────────────────────────
  make_row <- function(label, metric) {
    vals <- purrr::map_chr(active_years, ~ get_val(metric, .x))
    paste0(
      "| style=\"text-align:left\" | ", label, "\n",
      paste(paste0("| ", vals), collapse = "\n")
    )
  }

  data_rows <- list(
    make_row("Total detainee population",      "total"),
    make_row("\u2026 with a criminal record",  "crim"),
    make_row("\u2026 with no criminal record", "non_crim"),
    make_row("Male detainees",                 "male"),
    make_row("Female detainees",               "female")
  )

  # ── Assemble table ───────────────────────────────────────────────────
  notelist_row <- if (has_ytd) {
    paste0('| colspan="', ncols + 1,
           '" style="font-size:90%;text-align:left" | {{notelist}}')
  } else NULL

  parts <- c(
    '{| class="wikitable" style="text-align:right"',
    caption,
    "|-",
    header_row,
    purrr::map(data_rows, ~ c("|-", .x)) |> purrr::list_c(),
    if (!is.null(notelist_row)) c("|-", notelist_row),
    "|}"
  )

  paste(parts, collapse = "\n")
}


# ── FY26 Wikipedia list-article table generation ────────────────────────────

# Column headers for the Wikipedia "List of immigrant detention sites" table
.wiki_list_column_names <- c(
  "Facility Name",
  "Status (year)",
  "Location",
  "Facility Type",
  "Authority",
  "Management",
  "Average Daily Population",
  "Minimum Capacity",
  "Demographics"
)

# Two city-link disambiguations needed for the Wikipedia table
.city_link_overrides <- c(
  "Philipsburg, PA" = "Philipsburg, Centre County, Pennsylvania",
  "Greenwood, WV"   = "Greenwood, Doddridge County, West Virginia"
)


#' Prepare FY26 facilities data for Wikipedia list-article table
#'
#' Transforms the FY26 wiki-enriched facilities data into the 9-column format
#' used by the Wikipedia "List of immigrant detention sites" article. Generates
#' wikitext links for facility names (using wiki_slug/wiki_match) and
#' city/state locations.
#'
#' @param df FY26 facilities tibble with wiki_match, wiki_slug, management,
#'   facility_type_wiki, facility_type_detailed, sum_criminality_levels,
#'   inspections_guaranteed_minimum, facility_male_female columns.
#' @param year_name Year label for the status column (default "FY26").
#' @param facility_presence Optional facility presence matrix (from
#'   `build_facility_presence()`). When supplied, the status column shows
#'   "Active (FYxx \u2013 FY26)" based on each facility's continuous backward
#'   streak from FY26. When NULL, all facilities get "In use (FY26)".
#' @param include_redlinks If TRUE, every facility name becomes a wikilink
#'   even when there is no wiki_slug or wiki_match. Unmatched names get bare
#'   `[[facility_name]]` links, which render as red links on Wikipedia.
#' @param validate_slugs If TRUE (the default when `include_redlinks` is FALSE),
#'   query the Wikipedia API via `check_wiki_articles()` to verify that each
#'   wiki_slug and wiki_match actually exists. Non-existent titles are cleared
#'   before building links, so they fall through to plain text (or red links
#'   when `include_redlinks` is TRUE). Set to FALSE to skip the API call.
#' @return A 9-column tibble with wikitext-formatted values.
build_wiki_list_table <- function(df, year_name = "FY26",
                                  facility_presence = NULL,
                                  include_redlinks = FALSE,
                                  validate_slugs = !include_redlinks) {

  # ── Optionally validate wiki_slug / wiki_match against live Wikipedia ──
  if (validate_slugs) {
    slug_titles  <- unique(stats::na.omit(df$wiki_slug[df$wiki_slug != ""]))
    match_titles <- unique(stats::na.omit(df$wiki_match[df$wiki_match != ""]))
    all_titles   <- unique(c(slug_titles, match_titles))

    if (length(all_titles) > 0) {
      validation <- check_wiki_articles(all_titles)
      bad_titles <- validation$title[!validation$exists]
      if (length(bad_titles) > 0) {
        message("validate_slugs: clearing ", length(bad_titles),
                " non-existent Wikipedia title(s): ",
                paste(bad_titles, collapse = ", "))
        df <- df |>
          dplyr::mutate(
            wiki_slug  = dplyr::if_else(wiki_slug %in% bad_titles,
                                        NA_character_, wiki_slug),
            wiki_match = dplyr::if_else(wiki_match %in% bad_titles,
                                        NA_character_, wiki_match)
          )
      }
    }
  }

  # ── Compute continuous backward streak from the final year ──
  if (!is.null(facility_presence)) {
    year_cols <- grep("^FY\\d+$", names(facility_presence), value = TRUE)
    # Sort chronologically (FY10, FY11, ..., FY26)
    year_cols <- year_cols[order(as.integer(sub("^FY", "", year_cols)))]

    streak_info <- facility_presence |>
      dplyr::filter(.data[[year_cols[length(year_cols)]]] == TRUE) |>
      dplyr::select(canonical_id, dplyr::all_of(year_cols)) |>
      dplyr::rowwise() |>
      dplyr::mutate(
        streak_start_fy = {
          vals <- dplyr::c_across(dplyr::all_of(year_cols))
          start <- year_cols[length(year_cols)]
          for (i in rev(seq_along(year_cols)[-length(year_cols)])) {
            if (vals[i]) start <- year_cols[i] else break
          }
          start
        }
      ) |>
      dplyr::ungroup() |>
      dplyr::select(canonical_id, streak_start_fy)

    df <- df |>
      dplyr::left_join(streak_info, by = "canonical_id") |>
      dplyr::mutate(
        status = dplyr::if_else(
          streak_start_fy == year_name,
          paste0("Active (", year_name, ")"),
          paste0("Active (", streak_start_fy, " \u2013 ", year_name, ")")
        )
      ) |>
      dplyr::select(-streak_start_fy)
  } else {
    df <- df |>
      dplyr::mutate(status = paste0("In use (", year_name, ")"))
  }

  df |>
    dplyr::mutate(
      # Facility name wikilink hierarchy: slug > match > redlink/plain text
      facility_name_wiki = dplyr::case_when(
        !is.na(wiki_slug) & wiki_slug != "" & facility_name == wiki_slug ~
          paste0("[[", facility_name, "]]"),
        !is.na(wiki_slug) & wiki_slug != "" ~
          paste0("[[", wiki_slug, "|", facility_name, "]]"),
        !is.na(wiki_match) & wiki_match != "" ~
          paste0("[[", wiki_match, "|", facility_name, "]]"),
        include_redlinks ~ paste0("[[", facility_name, "]]"),
        TRUE ~ facility_name
      ),
      # City/state wikilinks with disambiguation overrides
      city_state = paste0(facility_city, ", ", facility_state),
      city_state_wiki = dplyr::if_else(
        city_state %in% names(.city_link_overrides),
        paste0("[[", .city_link_overrides[city_state], "|", city_state, "]]"),
        paste0("[[", city_state, "]]")
      ),
      location           = city_state_wiki,
      authority          = facility_type_detailed,
      average_daily_population = round(sum_criminality_levels),
      minimum_capacity   = inspections_guaranteed_minimum,
      demographics       = facility_male_female
    ) |>
    dplyr::select(
      facility_name_wiki, status, location, facility_type_wiki,
      authority, management, average_daily_population,
      minimum_capacity, demographics
    )
}


#' Prepare closed facilities data for Wikipedia list-article table
#'
#' Builds a wikitable-formatted tibble of facilities no longer active in the
#' most recent fiscal year. Uses the most recent year's data from the panel
#' and computes status as "Closed (Active FYxx \u2013 FYxx)".
#'
#' @param facilities_panel Long-format panel data (from `build_panel()`).
#' @param facility_presence Facility presence matrix (from
#'   `build_facility_presence()`).
#' @param canonical_wiki_match Optional canonical-level Wikipedia matches (from
#'   `build_canonical_wiki_match()`). When supplied, matched facilities get
#'   wikilinked names.
#' @param include_redlinks If TRUE, unmatched facility names get bare
#'   `[[facility_name]]` red links.
#' @return A 9-column tibble with wikitext-formatted values matching the
#'   `.wiki_list_column_names` schema.
build_closed_wiki_list_table <- function(facilities_panel,
                                         facility_presence,
                                         canonical_wiki_match = NULL,
                                         include_redlinks = FALSE) {

  year_cols <- grep("^FY\\d+$", names(facility_presence), value = TRUE)
  year_cols <- year_cols[order(as.integer(sub("^FY", "", year_cols)))]
  final_year <- year_cols[length(year_cols)]

  # Identify closed facilities and compute their active span
  closed_info <- facility_presence |>
    dplyr::filter(.data[[final_year]] == FALSE) |>
    dplyr::select(canonical_id, canonical_name, first_seen, last_seen)

  # Most recent year's data for each closed facility
  closed_data <- facilities_panel |>
    dplyr::filter(canonical_id %in% closed_info$canonical_id) |>
    dplyr::group_by(canonical_id) |>
    dplyr::slice_max(fiscal_year, n = 1, with_ties = FALSE) |>
    dplyr::ungroup()

  # Join presence span
 closed_data <- closed_data |>
    dplyr::left_join(
      closed_info |> dplyr::select(canonical_id, first_seen, last_seen),
      by = "canonical_id"
    ) |>
    dplyr::mutate(
      status = dplyr::if_else(
        first_seen == last_seen,
        paste0("Closed (Active ", first_seen, ")"),
        paste0("Closed (Active ", first_seen, " \u2013 ", last_seen, ")")
      )
    )

  # Attach wiki slugs if available
  if (!is.null(canonical_wiki_match)) {
    closed_data <- closed_data |>
      dplyr::left_join(
        canonical_wiki_match |>
          dplyr::select(canonical_name, wiki_slug),
        by = "canonical_name"
      )
  } else {
    closed_data <- closed_data |>
      dplyr::mutate(wiki_slug = NA_character_)
  }

  closed_data |>
    dplyr::mutate(
      facility_name_wiki = dplyr::case_when(
        !is.na(wiki_slug) & wiki_slug != "" & facility_name == wiki_slug ~
          paste0("[[", facility_name, "]]"),
        !is.na(wiki_slug) & wiki_slug != "" ~
          paste0("[[", wiki_slug, "|", facility_name, "]]"),
        include_redlinks ~ paste0("[[", facility_name, "]]"),
        TRUE ~ facility_name
      ),
      city_state = paste0(facility_city, ", ", facility_state),
      city_state_wiki = dplyr::if_else(
        city_state %in% names(.city_link_overrides),
        paste0("[[", .city_link_overrides[city_state], "|", city_state, "]]"),
        paste0("[[", city_state, "]]")
      ),
      location           = city_state_wiki,
      authority          = facility_type_detailed,
      average_daily_population = round(adp),
      minimum_capacity   = inspections_guaranteed_minimum,
      demographics       = facility_male_female,
      management = if ("management" %in% names(closed_data))
        management else NA_character_
    ) |>
    dplyr::select(
      facility_name_wiki, status, location, facility_type_wiki,
      authority, management, average_daily_population,
      minimum_capacity, demographics
    )
}


#' Generate the closed-facilities Wikipedia wikitable
#'
#' End-to-end wrapper: prepares closed facility data with
#' `build_closed_wiki_list_table()`, then converts to MediaWiki markup.
#'
#' @inheritParams build_closed_wiki_list_table
#' @return A single character string of MediaWiki table markup.
generate_closed_wikitable <- function(facilities_panel,
                                       facility_presence,
                                       canonical_wiki_match = NULL,
                                       include_redlinks = FALSE) {
  wiki_df <- build_closed_wiki_list_table(
    facilities_panel, facility_presence,
    canonical_wiki_match = canonical_wiki_match,
    include_redlinks = include_redlinks
  )
  generate_wikitable(
    wiki_df,
    caption      = "Closed ICE Detention Facilities",
    column_names = .wiki_list_column_names
  )
}


#' Convert a data frame to MediaWiki table markup
#'
#' General-purpose function that generates a complete `{| class="wikitable" |}`
#' block from a data frame. NA values are replaced with empty strings.
#'
#' @param df Data frame to convert.
#' @param caption Optional table caption.
#' @param class CSS class string (default "wikitable sortable").
#' @param column_names Custom header names; if NULL uses names(df).
#' @return A single character string containing the MediaWiki table markup.
generate_wikitable <- function(df, caption = NULL,
                               class = "wikitable sortable",
                               column_names = NULL) {
  out <- paste0('{| class="', class, '"')

  if (!is.null(caption)) {
    out <- c(out, paste0("|+ ", caption))
  }

  if (is.null(column_names)) {
    column_names <- names(df)
  }
  out <- c(out, paste0("! ", paste(column_names, collapse = " !! ")))

  formatted_rows <- apply(df, 1, function(row) {
    row_clean <- as.character(row)
    row_clean[is.na(row_clean)] <- ""
    paste0("| ", paste(row_clean, collapse = " || "))
  })

  out <- c(out, paste0("|-\n", formatted_rows))
  out <- c(out, "|}")

  paste(out, collapse = "\n")
}


#' Generate the complete FY26 Wikipedia list-article wikitable
#'
#' End-to-end wrapper: prepares the data with `build_wiki_list_table()`,
#' then converts to MediaWiki markup with `generate_wikitable()`.
#'
#' @param df FY26 facilities tibble (output of the `facilities_fy26_wiki` target).
#' @param year_name Year label (default "FY26").
#' @param facility_presence Optional facility presence matrix, passed through
#'   to `build_wiki_list_table()`.
#' @param include_redlinks If TRUE, passed through to `build_wiki_list_table()`.
#' @param validate_slugs Passed through to `build_wiki_list_table()`.
#' @return A single character string of MediaWiki table markup.
generate_fy26_wikitable <- function(df, year_name = "FY26",
                                    facility_presence = NULL,
                                    include_redlinks = FALSE,
                                    validate_slugs = !include_redlinks) {
  wiki_df <- build_wiki_list_table(df, year_name,
                                   facility_presence = facility_presence,
                                   include_redlinks = include_redlinks,
                                   validate_slugs = validate_slugs)
  generate_wikitable(
    wiki_df,
    caption      = paste0("ICE Detention Facilities in ", year_name),
    column_names = .wiki_list_column_names
  )
}
