# R/wiki-article.R — Fetch and diff the Wikipedia list article wikitext
#
# Records what other editors changed on the live article since our last
# upload: cell-level edits (link fixes, refs, management updates) and rows
# added or removed. Also flags article rows absent from our generated data,
# which a wholesale table replacement would destroy.

# ── Fetch ─────────────────────────────────────────────────────────────────────

#' Fetch the raw wikitext of a pinned revision of the list article
#'
#' @param oldid Integer revision ID to fetch.
#' @param title Article title (underscore form).
#' @return Character scalar of the page wikitext.
fetch_wiki_wikitext <- function(oldid,
    title = "List_of_immigrant_detention_sites_in_the_United_States") {
  resp <- httr::GET("https://en.wikipedia.org/w/index.php",
                    query = list(title = title, oldid = oldid, action = "raw"))
  httr::stop_for_status(resp)
  httr::content(resp, as = "text", encoding = "UTF-8")
}

# ── Parse ─────────────────────────────────────────────────────────────────────

#' Strip refs, tags, and wikilink markup from a table cell
#'
#' Leaves visible text only (link labels, not targets), so cells can be
#' compared across revisions.
clean_wiki_cell <- function(x) {
  x |>
    stringr::str_remove_all("<ref[^>]*>.*?</ref>|<ref[^>]*/>") |>
    stringr::str_replace_all("\\[\\[(?:[^|\\]]*\\|)?([^\\]|]*)\\]\\]", "\\1") |>
    stringr::str_remove_all("<[^>]+>") |>
    stringr::str_squish()
}

#' Row key: cleaned cell text, lowercased, trailing punctuation removed
wiki_row_key <- function(x) {
  clean_wiki_cell(x) |>
    tolower() |>
    stringr::str_remove_all("[.,;:]+$") |>
    stringr::str_squish()
}

#' Parse the first wikitable (active facilities) from the article wikitext
#'
#' Handles both the 9-column layout (combined Location) and the 10-column
#' layout (City + State), and both row styles: one cell per line, and
#' single-line rows with `||` or space-pipe separators.
#'
#' @param wikitext Character scalar of page wikitext.
#' @return A tibble with one row per facility: `row_id`, `facility` (raw
#'   first cell), `key` (cleaned comparison key), and one column per table
#'   column (`status`, `city`, `state`, `type`, `authority`, `management`,
#'   `adp`, `capacity`, `demographics`) holding raw cell wikitext.
parse_wiki_facility_table <- function(wikitext) {
  lines <- strsplit(wikitext, "\n", fixed = TRUE)[[1]]
  start <- which(startsWith(lines, "{|"))[1]
  if (is.na(start)) stop("No wikitable found in wikitext")
  ends <- which(startsWith(lines, "|}"))
  end <- ends[ends > start][1]
  if (is.na(end)) stop("Unterminated wikitable")
  block <- lines[start:end]

  headers <- character(0)
  rows <- list()
  current <- list()
  flush_row <- function() {
    if (length(current) > 0) {
      rows[[length(rows) + 1]] <<- current
      current <<- list()
    }
  }

  for (l in block[-1]) {
    if (startsWith(l, "|}")) { flush_row(); break }
    if (startsWith(l, "|+")) next                     # caption
    if (startsWith(l, "|-")) { flush_row(); next }    # row separator
    if (startsWith(l, "!")) {                          # header line(s)
      parts <- trimws(strsplit(l, "!!", fixed = TRUE)[[1]])
      headers <- c(headers, trimws(sub("^!+", "", parts)))
      next
    }
    if (startsWith(l, "|")) {
      current[[length(current) + 1]] <- sub("^\\|", "", l)
      next
    }
    # Continuation of the previous cell (rare)
    if (length(current) > 0) {
      current[[length(current)]] <- paste(current[[length(current)]], l)
    }
  }
  headers <- headers[nzchar(headers)]
  n_col <- length(headers)

  # Expand single-line rows into cells. Try `||` first (inline separator),
  # then a single space-pipe; accept only if the piece count matches the
  # header, so ref/cite markup containing pipes is never mis-split.
  cell_rows <- lapply(rows, function(cells) {
    if (length(cells) > 1) return(as.character(cells))
    parts <- trimws(strsplit(cells, "||", fixed = TRUE)[[1]])
    if (length(parts) == n_col) return(parts)
    parts <- trimws(strsplit(cells, " |", fixed = TRUE)[[1]])
    if (length(parts) == n_col) return(parts)
    as.character(cells)
  })

  col_key <- dplyr::case_when(
    headers == "Facility Name"             ~ "facility",
    headers == "Status (year)"              ~ "status",
    headers == "Location"                   ~ "city",
    headers == "City"                       ~ "city",
    headers == "State"                      ~ "state",
    headers == "Facility Type"              ~ "type",
    headers == "Authority"                  ~ "authority",
    headers == "Management"                 ~ "management",
    headers == "Average Daily Population"   ~ "adp",
    headers == "Minimum Capacity"           ~ "capacity",
    headers == "Demographics"               ~ "demographics",
    TRUE                                    ~ NA_character_
  )
  if (anyDuplicated(na.omit(col_key))) {
    stop("Unrecognized or duplicate table headers: ",
         paste(headers, collapse = " / "))
  }

  vals <- lapply(cell_rows, function(cells) {
    v <- rep(NA_character_, n_col)
    n <- min(length(cells), n_col)
    v[seq_len(n)] <- as.character(cells)[seq_len(n)]
    v
  })
  m <- matrix(unlist(vals), ncol = n_col, byrow = TRUE)
  colnames(m) <- col_key

  out <- tibble::as_tibble(m) |>
    dplyr::mutate(row_id = dplyr::row_number(), .before = 1) |>
    dplyr::mutate(key = wiki_row_key(facility))
  out
}

# ── Extant linked articles ───────────────────────────────────────────────────

#' Check existence of every Wikipedia article linked from the list-article
#' facility tables.
#'
#' Unions the wiki slugs linked from the pinned and current scrapes of the
#' "List of immigrant detention sites" article (the two scrapes cover different
#' table layouts), then runs `check_wiki_articles()` to record existence,
#' redirect, and disambiguation status for each. Redirect targets are kept in
#' `redirect_target`, so the set of actual articles is
#' `title[!redirect] \cup redirect_target[redirect]`.
#'
#' @param wiki_table Output of `scrape_wiki_detention_table()` (pinned revision).
#' @param wiki_table_current Optional second scrape (current revision).
#' @return A tibble, one row per unique linked slug: `title`, `exists`,
#'   `redirect`, `disambiguation`, `redirect_target`, `n_listed_rows` (number
#'   of facility rows in the two tables linking to it), and `linked_facilities`
#'   (semicolon-joined distinct facility names from the table rows).
build_wiki_list_extant_articles <- function(wiki_table, wiki_table_current = NULL) {
  name_col <- if ("name" %in% names(wiki_table)) "name" else "facility_name"
  scrapes <- list(wiki_table, wiki_table_current)
  scrapes <- scrapes[!vapply(scrapes, is.null, logical(1))]

  links <- purrr::map_dfr(scrapes, function(tbl) {
    tbl |>
      dplyr::filter(!is.na(.data$wiki_slug), .data$wiki_slug != "") |>
      dplyr::transmute(title = .data$wiki_slug, facility = .data[[name_col]])
  })

  slugs <- sort(unique(links$title))
  chk <- check_wiki_articles(slugs)

  # Verify redirect targets too: existence, double-redirect, disambiguation
  rtargets <- unique(chk$redirect_target[chk$redirect & !is.na(chk$redirect_target)])
  if (length(rtargets) > 0) {
    rchk <- check_wiki_articles(rtargets) |>
      dplyr::rename(
        redirect_target_exists = exists,
        redirect_target_redirect = redirect,
        redirect_target_dab = disambiguation
      )
    chk <- chk |>
      dplyr::left_join(rchk, by = c("redirect_target" = "title"))
  } else {
    chk <- chk |>
      dplyr::mutate(
        redirect_target_exists = NA,
        redirect_target_redirect = NA,
        redirect_target_dab = NA
      )
  }

  links |>
    dplyr::group_by(title) |>
    dplyr::summarise(
      n_listed_rows = dplyr::n(),
      linked_facilities = paste(sort(unique(facility)), collapse = "; "),
      .groups = "drop"
    ) |>
    dplyr::left_join(chk, by = "title") |>
    dplyr::arrange(title)
}


# ── Diff ──────────────────────────────────────────────────────────────────────

#' Record editor changes between two revisions of the article table
#'
#' Aligns rows by cleaned facility name (so alphabetical re-sorting and
#' position moves are not flagged) and reports:
#' - `added_row` / `removed_row`: rows appearing in only one revision
#' - `cell_change`: cell-level differences in shared columns (raw wikitext,
#'   old and new)
#' - `article_row_not_in_data`: rows in the current article that are absent
#'   from `current_facilities` (our generated table) — these would be
#'   destroyed by a wholesale table replacement
#'
#' @param wikitext_old Wikitext of the base revision (our last upload).
#' @param wikitext_new Wikitext of the current revision.
#' @param current_facilities Optional character vector of facility names from
#'   our generated table (e.g. `facilities_fy25_26_wiki$facility_name`).
#' @return A tibble: change_type, facility, column, old_value, new_value.
build_wiki_revision_diff <- function(wikitext_old, wikitext_new,
                                     current_facilities = NULL) {
  old_tbl <- parse_wiki_facility_table(wikitext_old)
  new_tbl <- parse_wiki_facility_table(wikitext_new)

  blank <- function(x) is.na(x) || trimws(x) == ""

  cell_changes <- purrr::map_dfr(intersect(old_tbl$key, new_tbl$key),
    function(k) {
      o <- old_tbl[old_tbl$key == k, ][1, ]
      n <- new_tbl[new_tbl$key == k, ][1, ]
      cols <- setdiff(intersect(names(o), names(n)),
                      c("row_id", "key", "facility", "state"))
      purrr::map_dfr(cols, function(col) {
        oc <- clean_wiki_cell(o[[col]])
        nc <- clean_wiki_cell(n[[col]])
        if (blank(oc) && blank(nc)) return(NULL)
        if (!is.na(oc) && !is.na(nc) && identical(oc, nc)) return(NULL)
        tibble::tibble(
          change_type = "cell_change",
          facility    = clean_wiki_cell(n$facility),
          column      = col,
          old_value   = as.character(o[[col]]),
          new_value   = as.character(n[[col]])
        )
      })
    }
  )

  added_keys <- setdiff(new_tbl$key, old_tbl$key)
  removed_keys <- setdiff(old_tbl$key, new_tbl$key)
  added_rows <- tibble::tibble(
    change_type = "added_row",
    facility    = clean_wiki_cell(new_tbl$facility[match(added_keys, new_tbl$key)]),
    column      = "row",
    old_value   = NA_character_,
    new_value   = new_tbl$facility[match(added_keys, new_tbl$key)]
  )
  removed_rows <- tibble::tibble(
    change_type = "removed_row",
    facility    = clean_wiki_cell(old_tbl$facility[match(removed_keys, old_tbl$key)]),
    column      = "row",
    old_value   = old_tbl$facility[match(removed_keys, old_tbl$key)],
    new_value   = NA_character_
  )

  at_risk <- NULL
  if (!is.null(current_facilities)) {
    cur_keys <- wiki_row_key(current_facilities)
    risk <- setdiff(new_tbl$key, cur_keys)
    # Near-miss rescue: rows our table carries under a truncated or renamed
    # display name ("Burleigh County" / "Burleigh County Detention Center")
    # are safe — only flag rows with no prefix relationship to our data.
    risk <- purrr::keep(risk, function(k) {
      !any(nzchar(cur_keys) &
           pmin(nchar(cur_keys), nchar(k)) >= 8 &
           (startsWith(cur_keys, k) | startsWith(k, cur_keys)))
    })
    at_risk <- tibble::tibble(
      change_type = "article_row_not_in_data",
      facility    = clean_wiki_cell(new_tbl$facility[match(risk, new_tbl$key)]),
      column      = "row",
      old_value   = NA_character_,
      new_value   = new_tbl$facility[match(risk, new_tbl$key)]
    )
  }

  dplyr::bind_rows(cell_changes, added_rows, removed_rows, at_risk) |>
    dplyr::arrange(change_type, facility, column)
}
