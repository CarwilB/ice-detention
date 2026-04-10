parse_ice_node_page <- function(html_path) {
  page <- tryCatch(read_html(html_path), error = \(e) NULL)
  if (is.null(page)) return(list(page_title = NA_character_, page_address = NA_character_))

  # Title is in <h1 class="margin-0"><span>...</span></h1>
  page_title <- page |>
    html_element("h1.margin-0 span, h1 span") |>
    html_text2() |>
    str_trim()
  if (length(page_title) == 0 || is.na(page_title)) page_title <- NA_character_

  # Address spans are inside p.address within the field-office-location field
  addr <- page |> html_element("p.address[translate='no']")

  page_address <- if (!is.null(addr) && !is.na(addr)) {
    line1 <- addr |> html_element(".address-line1") |> html_text2()
    line2 <- addr |> html_element(".address-line2") |> html_text2()
    city  <- addr |> html_element(".locality")       |> html_text2()
    state <- addr |> html_element(".administrative-area") |> html_text2()
    zip   <- addr |> html_element(".postal-code")    |> html_text2()

    parts <- c(line1, line2, city, state, zip)
    parts <- str_trim(parts[!is.na(parts) & nzchar(str_trim(parts))])
    if (length(parts) == 0) NA_character_
    else paste(parts, collapse = ", ")
  } else {
    NA_character_
  }

  list(page_title = page_title, page_address = page_address)
}

# Parse a field_office node page, returning all structured fields.
# Returns NULL if the page is not a field office page.
parse_ice_field_office_page <- function(html_path) {
  page <- tryCatch(read_html(html_path), error = \(e) NULL)
  if (is.null(page)) return(NULL)

  # Reliable signal: entityBundle == "field_office" in the dataLayer JSON
  scripts   <- page |> html_elements("script") |> html_text2()
  dl_script <- scripts[str_detect(scripts, "entityBundle")] |> first()
  if (is.na(dl_script)) return(NULL)
  bundle    <- str_match(dl_script, '"entityBundle":"([^"]+)"')[, 2]
  if (is.na(bundle) || bundle != "field_office") return(NULL)

  page_title <- page |>
    html_element("h1.margin-0 span, h1 span") |>
    html_text2() |>
    str_trim()

  addr  <- page |> html_element("p.address[translate='no']")
  line1 <- addr |> html_element(".address-line1")      |> html_text2()
  line2 <- addr |> html_element(".address-line2")      |> html_text2()
  city  <- addr |> html_element(".locality")            |> html_text2()
  state <- addr |> html_element(".administrative-area") |> html_text2()
  zip   <- addr |> html_element(".postal-code")         |> html_text2()

  parts   <- c(line1, line2, city, state, zip)
  parts   <- str_trim(parts[!is.na(parts) & nzchar(str_trim(parts))])
  address <- if (length(parts) == 0) NA_character_ else paste(parts, collapse = ", ")

  field_office_name <- page |>
    html_element("[class*='field-office-name'] .field__item") |>
    html_text2()

  list(
    page_title        = page_title,
    page_address      = address,
    address_line1     = if (is.na(line1)) NA_character_ else str_trim(line1),
    address_line2     = if (is.na(line2)) NA_character_ else str_trim(line2),
    city              = if (is.na(city))  NA_character_ else str_trim(city),
    state             = if (is.na(state)) NA_character_ else str_trim(state),
    zip               = if (is.na(zip))   NA_character_ else str_trim(zip),
    field_office_name = if (is.na(field_office_name)) NA_character_ else str_trim(field_office_name)
  )
}

# Scan a range of ice.gov/node/* URLs and return one row per field_office page,
# with the structured address fields extracted.
scan_ice_field_office_nodes <- function(node_range = 62000:62300,
                                        html_cache_dir   = "data/dhs-websites/ice-nodes",
                                        index_cache_path = "data/dhs-websites/ice-node-index.rds",
                                        delay = 0.5) {
  library(httr2)
  library(rvest)

  dir.create(html_cache_dir, showWarnings = FALSE, recursive = TRUE)

  if (file.exists(index_cache_path)) {
    index <- readRDS(index_cache_path)
  } else {
    index <- tibble(
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
      url       <- paste0("https://ice.gov/node/", nid)
      html_path <- file.path(html_cache_dir, paste0(nid, ".html"))

      if (!file.exists(html_path)) {
        resp <- tryCatch(
          request(url) |>
            req_timeout(10) |>
            req_error(is_error = \(r) FALSE) |>
            req_perform(),
          error = \(e) NULL
        )
        Sys.sleep(delay)

        if (is.null(resp)) {
          return(tibble(node_id = nid, url = url, http_status = NA_integer_))
        }

        status <- resp_status(resp)
        if (status == 200) writeLines(resp_body_string(resp), html_path)
        tibble(node_id = nid, url = url, http_status = status)

      } else {
        tibble(node_id = nid, url = url, http_status = 200L)
      }
    }) |> bind_rows()

    index <- bind_rows(index, new_rows) |> distinct(node_id, .keep_all = TRUE)
    saveRDS(index, index_cache_path)
  }

  # Parse only 200-status pages as field_office nodes
  message("Parsing field office pages from ", sum(index$http_status == 200, na.rm = TRUE),
          " cached 200 pages...")

  hits <- index |>
    filter(http_status == 200, node_id %in% node_range) |>
    pull(node_id) |>
    lapply(function(nid) {
      html_path <- file.path(html_cache_dir, paste0(nid, ".html"))
      result    <- parse_ice_field_office_page(html_path)
      if (is.null(result)) return(NULL)
      tibble(
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
    Filter(Negate(is.null), x = _) |>
    bind_rows()

  if (nrow(hits) == 0) {
    message("No field_office pages found in node range.")
    return(tibble(
      node_id = integer(), url = character(), page_title = character(),
      field_office_name = character(), address_line1 = character(),
      address_line2 = character(), city = character(), state = character(),
      zip = character(), page_address = character()
    ))
  }

  message("Found ", nrow(hits), " field_office pages.")
  hits
}

fetch_ice_node_addresses <- function(df,
                                     node_range = 62000:62300,
                                     html_cache_dir = "data/dhs-websites/ice-nodes",
                                     index_cache_path = "data/dhs-websites/ice-node-index.rds",
                                     delay = 0.5,
                                     address_col = "facility_address") {
  library(httr2)
  library(rvest)

  dir.create(html_cache_dir, showWarnings = FALSE, recursive = TRUE)

  # Load or initialize index cache (node_id -> status + parsed fields)
  if (file.exists(index_cache_path)) {
    index <- readRDS(index_cache_path)
  } else {
    index <- tibble(
      node_id      = integer(),
      url          = character(),
      http_status  = integer(),
      page_title   = character(),
      page_address = character()
    )
  }

  # --- Fetch uncached nodes --------------------------------------------------
  to_fetch <- setdiff(node_range, index$node_id)
  if (length(to_fetch) > 0) {
    message("Fetching ", length(to_fetch), " ice.gov node pages...")

    new_rows <- lapply(to_fetch, function(node_id) {
      url       <- paste0("https://ice.gov/node/", node_id)
      html_path <- file.path(html_cache_dir, paste0(node_id, ".html"))

      # Fetch if not already on disk
      if (!file.exists(html_path)) {
        resp <- tryCatch(
          request(url) |>
            req_timeout(10) |>
            req_error(is_error = \(r) FALSE) |>
            req_perform(),
          error = \(e) NULL
        )
        Sys.sleep(delay)

        if (is.null(resp)) {
          return(tibble(node_id = node_id, url = url,
                        http_status = NA_integer_,
                        page_title = NA_character_, page_address = NA_character_))
        }

        status <- resp_status(resp)
        if (status == 200) {
          writeLines(resp_body_string(resp), html_path)
        }

        tibble(node_id = node_id, url = url, http_status = status,
               page_title = NA_character_, page_address = NA_character_)

      } else {
        tibble(node_id = node_id, url = url, http_status = 200L,
               page_title = NA_character_, page_address = NA_character_)
      }
    }) |> bind_rows()

    index <- bind_rows(index, new_rows)
  }

  # --- Parse address from cached HTML for any unparsed 200 rows --------------
  needs_parse <- index |>
    filter(http_status == 200, is.na(page_address))

  if (nrow(needs_parse) > 0) {
    message("Parsing addresses from ", nrow(needs_parse), " cached pages...")

    parsed <- lapply(seq_len(nrow(needs_parse)), function(i) {
      node_id   <- needs_parse$node_id[i]
      html_path <- file.path(html_cache_dir, paste0(node_id, ".html"))
      result    <- parse_ice_node_page(html_path)
      needs_parse[i, ] |>
        mutate(page_title = result$page_title, page_address = result$page_address)
    }) |> bind_rows()

    index <- index |>
      filter(!node_id %in% parsed$node_id) |>
      bind_rows(parsed)

    saveRDS(index, index_cache_path)
  }

  # --- Match against df rows missing ice_url ---------------------------------
  if (!"ice_url" %in% names(df)) {
    df <- df |> mutate(ice_url = NA_character_)
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
    mutate(ice_url = mapply(function(current_url, addr) {
      if (!is.na(current_url) || is.na(addr)) return(current_url)

      street <- str_extract(addr, "^[^,]+") |> str_trim()

      matches <- index |>
        filter(
          http_status == 200,
          !is.na(page_address),
          str_detect(
            str_replace_all(page_address, ",\\s*", " "),
            fixed(street, ignore_case = TRUE)
          )
        )

      if (nrow(matches) == 1) matches$url else NA_character_
    }, ice_url, addr_vec, SIMPLIFY = TRUE))
}
