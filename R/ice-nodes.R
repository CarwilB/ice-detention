# ice-nodes.R — Functions for fetching and parsing ice.gov/node/* pages
#
# Three entry points:
#   parse_ice_node_page()          — minimal: title + collapsed address string
#   parse_ice_field_office_page()  — structured address fields, only for field_office bundles
#   scan_ice_field_office_nodes()  — bulk scan of a node-ID range → one row per field_office page
#   fetch_ice_node_addresses()     — match a data frame's address column against cached node pages


# Parse a single ice.gov/node/* page: return page_title and collapsed page_address.
# Returns a list with NA values if the page cannot be read.
parse_ice_node_page <- function(html_path) {
  page <- tryCatch(rvest::read_html(html_path), error = \(e) NULL)
  if (is.null(page)) return(list(page_title = NA_character_, page_address = NA_character_))

  page_title <- page |>
    rvest::html_element("h1.margin-0 span, h1 span") |>
    rvest::html_text2() |>
    stringr::str_trim()
  if (length(page_title) == 0 || is.na(page_title)) page_title <- NA_character_

  addr <- page |> rvest::html_element("p.address[translate='no']")

  page_address <- if (!is.null(addr) && !is.na(addr)) {
    line1 <- addr |> rvest::html_element(".address-line1") |> rvest::html_text2()
    line2 <- addr |> rvest::html_element(".address-line2") |> rvest::html_text2()
    city  <- addr |> rvest::html_element(".locality")       |> rvest::html_text2()
    state <- addr |> rvest::html_element(".administrative-area") |> rvest::html_text2()
    zip   <- addr |> rvest::html_element(".postal-code")    |> rvest::html_text2()

    parts <- c(line1, line2, city, state, zip)
    parts <- stringr::str_trim(parts[!is.na(parts) & nzchar(stringr::str_trim(parts))])
    if (length(parts) == 0) NA_character_
    else paste(parts, collapse = ", ")
  } else {
    NA_character_
  }

  list(page_title = page_title, page_address = page_address)
}


# Parse a field_office entity-bundle page, returning structured address fields.
# Checks for entityBundle == "field_office" in the dataLayer JSON.
# Returns NULL if the page is not a field_office page.
parse_ice_field_office_page <- function(html_path) {
  page <- tryCatch(rvest::read_html(html_path), error = \(e) NULL)
  if (is.null(page)) return(NULL)

  scripts   <- page |> rvest::html_elements("script") |> rvest::html_text2()
  dl_script <- scripts[stringr::str_detect(scripts, "entityBundle")] |> dplyr::first()
  if (is.na(dl_script)) return(NULL)
  bundle    <- stringr::str_match(dl_script, '"entityBundle":"([^"]+)"')[, 2]
  if (is.na(bundle) || bundle != "field_office") return(NULL)

  page_title <- page |>
    rvest::html_element("h1.margin-0 span, h1 span") |>
    rvest::html_text2() |>
    stringr::str_trim()

  addr  <- page |> rvest::html_element("p.address[translate='no']")
  line1 <- addr |> rvest::html_element(".address-line1")      |> rvest::html_text2()
  line2 <- addr |> rvest::html_element(".address-line2")      |> rvest::html_text2()
  city  <- addr |> rvest::html_element(".locality")            |> rvest::html_text2()
  state <- addr |> rvest::html_element(".administrative-area") |> rvest::html_text2()
  zip   <- addr |> rvest::html_element(".postal-code")         |> rvest::html_text2()

  parts   <- c(line1, line2, city, state, zip)
  parts   <- stringr::str_trim(parts[!is.na(parts) & nzchar(stringr::str_trim(parts))])
  address <- if (length(parts) == 0) NA_character_ else paste(parts, collapse = ", ")

  field_office_name <- page |>
    rvest::html_element("[class*='field-office-name'] .field__item") |>
    rvest::html_text2()

  list(
    page_title        = page_title,
    page_address      = address,
    address_line1     = if (is.na(line1)) NA_character_ else stringr::str_trim(line1),
    address_line2     = if (is.na(line2)) NA_character_ else stringr::str_trim(line2),
    city              = if (is.na(city))  NA_character_ else stringr::str_trim(city),
    state             = if (is.na(state)) NA_character_ else stringr::str_trim(state),
    zip               = if (is.na(zip))   NA_character_ else stringr::str_trim(zip),
    field_office_name = if (is.na(field_office_name)) NA_character_ else stringr::str_trim(field_office_name)
  )
}


# Scan a range of ice.gov/node/* URLs and return one row per field_office page.
# Downloads missing pages to html_cache_dir and caches an index RDS at
# index_cache_path. Already-cached pages are not re-fetched.
scan_ice_field_office_nodes <- function(node_range        = 62000:62300,
                                        html_cache_dir     = "data/dhs-websites/ice-nodes",
                                        index_cache_path   = "data/dhs-websites/ice-node-index.rds",
                                        url_dir_prefix      = "https://ice.gov/node/",
                                        delay              = 0.5) {
  dir.create(html_cache_dir, showWarnings = FALSE, recursive = TRUE)

  if (file.exists(index_cache_path)) {
    index <- readRDS(index_cache_path)
  } else {
    index <- tibble::tibble(
      node_id     = integer(),
      url         = character(),
      http_status = integer()
    )
  }

  # Fetch any nodes not yet in the cache
  to_fetch <- setdiff(node_range, index$node_id)
  if (length(to_fetch) > 0) {
    message("Fetching ", length(to_fetch), " ice.gov node pages...")

    new_rows <- lapply(to_fetch, function(nid) {
      url       <- paste0(url_dir_prefix, nid)
      html_path <- file.path(html_cache_dir, paste0(nid, ".html"))

      if (!file.exists(html_path)) {
        resp <- tryCatch(
          httr2::request(url) |>
            httr2::req_timeout(10) |>
            httr2::req_error(is_error = \(r) FALSE) |>
            httr2::req_perform(),
          error = \(e) NULL
        )
        Sys.sleep(delay)

        if (is.null(resp)) {
          return(tibble::tibble(node_id = nid, url = url, http_status = NA_integer_))
        }

        status <- httr2::resp_status(resp)
        if (status == 200) writeLines(httr2::resp_body_string(resp), html_path)
        tibble::tibble(node_id = nid, url = url, http_status = status)

      } else {
        tibble::tibble(node_id = nid, url = url, http_status = 200L)
      }
    }) |> dplyr::bind_rows()

    index <- dplyr::bind_rows(index, new_rows) |> dplyr::distinct(node_id, .keep_all = TRUE)
    saveRDS(index, index_cache_path)
  }

  message("Parsing field office pages from ",
          sum(index$http_status == 200, na.rm = TRUE), " cached 200 pages...")

  hits <- dplyr::filter(index, http_status == 200, node_id %in% node_range) |>
    dplyr::pull(node_id) |>
    lapply(function(nid) {
      html_path <- file.path(html_cache_dir, paste0(nid, ".html"))
      result    <- parse_ice_field_office_page(html_path)
      if (is.null(result)) return(NULL)
      tibble::tibble(
        node_id           = nid,
        url               = paste0("https://ice.gov/node/", nid),
        page_title        = result$page_title,
        field_office_name = result$field_office_name,
        address_line1     = result$address_line1,
        address_line2     = result$address_line2,
        city              = result$city,
        state             = result$state,
        zip               = result$zip,
        page_address      = result$page_address
      )
    }) |>
    purrr::compact() |>
    dplyr::bind_rows()

  if (nrow(hits) == 0) {
    message("No field_office pages found in node range.")
    return(tibble::tibble(
      node_id = integer(), url = character(), page_title = character(),
      field_office_name = character(), address_line1 = character(),
      address_line2 = character(), city = character(), state = character(),
      zip = character(), page_address = character()
    ))
  }

  message("Found ", nrow(hits), " field_office pages.")
  hits
}


# Match a data frame's address column against cached ice.gov node pages and
# return the input data frame with an ice_url column added (or updated).
# Rows that already have an ice_url are left unchanged.
fetch_ice_node_addresses <- function(df,
                                     node_range       = 62000:62300,
                                     html_cache_dir   = "data/dhs-websites/ice-nodes",
                                     index_cache_path = "data/dhs-websites/ice-node-index.rds",
                                     delay            = 0.5,
                                     address_col      = "facility_address") {
  dir.create(html_cache_dir, showWarnings = FALSE, recursive = TRUE)

  if (file.exists(index_cache_path)) {
    index <- readRDS(index_cache_path)
  } else {
    index <- tibble::tibble(
      node_id      = integer(),
      url          = character(),
      http_status  = integer(),
      page_title   = character(),
      page_address = character()
    )
  }

  # Fetch uncached nodes
  to_fetch <- setdiff(node_range, index$node_id)
  if (length(to_fetch) > 0) {
    message("Fetching ", length(to_fetch), " ice.gov node pages...")

    new_rows <- lapply(to_fetch, function(nid) {
      url       <- paste0("https://ice.gov/node/", nid)
      html_path <- file.path(html_cache_dir, paste0(nid, ".html"))

      if (!file.exists(html_path)) {
        resp <- tryCatch(
          httr2::request(url) |>
            httr2::req_timeout(10) |>
            httr2::req_error(is_error = \(r) FALSE) |>
            httr2::req_perform(),
          error = \(e) NULL
        )
        Sys.sleep(delay)

        if (is.null(resp)) {
          return(tibble::tibble(node_id = nid, url = url,
                                http_status = NA_integer_,
                                page_title = NA_character_, page_address = NA_character_))
        }

        status <- httr2::resp_status(resp)
        if (status == 200) writeLines(httr2::resp_body_string(resp), html_path)

        tibble::tibble(node_id = nid, url = url, http_status = status,
                       page_title = NA_character_, page_address = NA_character_)

      } else {
        tibble::tibble(node_id = nid, url = url, http_status = 200L,
                       page_title = NA_character_, page_address = NA_character_)
      }
    }) |> dplyr::bind_rows()

    index <- dplyr::bind_rows(index, new_rows)
  }

  # Parse addresses from cached HTML for any unparsed 200 rows
  needs_parse <- dplyr::filter(index, http_status == 200, is.na(page_address))

  if (nrow(needs_parse) > 0) {
    message("Parsing addresses from ", nrow(needs_parse), " cached pages...")

    parsed <- lapply(seq_len(nrow(needs_parse)), function(i) {
      nid       <- needs_parse$node_id[i]
      html_path <- file.path(html_cache_dir, paste0(nid, ".html"))
      result    <- parse_ice_node_page(html_path)
      needs_parse[i, ] |>
        dplyr::mutate(page_title = result$page_title, page_address = result$page_address)
    }) |> dplyr::bind_rows()

    index <- dplyr::filter(index, !node_id %in% parsed$node_id) |>
      dplyr::bind_rows(parsed)

    saveRDS(index, index_cache_path)
  }

  # Match against df rows missing ice_url
  if (!"ice_url" %in% names(df)) {
    df <- df |> dplyr::mutate(ice_url = NA_character_)
  }

  if (!address_col %in% names(df)) {
    stop(
      "Column '", address_col, "' not found in df. ",
      "Available columns: ", paste(names(df), collapse = ", "), ". ",
      "Pass address_col = \"<column_name>\" to specify the address column."
    )
  }
  addr_vec <- df[[address_col]]

  df |>
    dplyr::mutate(ice_url = mapply(function(current_url, addr) {
      if (!is.na(current_url) || is.na(addr)) return(current_url)

      street <- stringr::str_extract(addr, "^[^,]+") |> stringr::str_trim()

      matches <- dplyr::filter(
        index,
        http_status == 200,
        !is.na(page_address),
        stringr::str_detect(
          stringr::str_replace_all(page_address, ",\\s*", " "),
          stringr::fixed(street, ignore_case = TRUE)
        )
      )

      if (nrow(matches) == 1) matches$url else NA_character_
    }, ice_url, addr_vec, SIMPLIFY = TRUE))
}
