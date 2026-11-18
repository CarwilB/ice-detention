# zotero-json.R
# Read a Zotero CSL-JSON export of the ICE detention group library
# (group 6462728) into R. The export is a one-way snapshot: File > Export
# Library > CSL JSON, notes and attachments excluded. Live reads and writes go
# through the Zotero Web API instead (see zotero-harvest.R).
#
# Base R + jsonlite only, so it runs without the tidyverse stack.

#' Read a Zotero CSL-JSON export
#'
#' @param path Path to the exported `.json` file.
#' @param raw If TRUE, return the parsed list of CSL items unchanged (each item
#'   a named list, exactly as exported) instead of a data frame.
#' @return A data frame with one row per item (`raw = FALSE`), or a list of
#'   CSL-JSON items (`raw = TRUE`).
read_zotero_csl_json <- function(path, raw = FALSE) {
  items <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  if (raw) return(items)
  csl_items_to_df(items)
}

#' Flatten a list of CSL-JSON items to a data frame
#'
#' @param items List of CSL-JSON items, as returned by
#'   `read_zotero_csl_json(path, raw = TRUE)`.
#' @return One row per item: `citation_key`, `item_type`, `title`, `title_short`,
#'   `container_title`, `publisher`, `publisher_place`, `issued` (ISO-style
#'   date or the literal string), `year`, `authors` and `editors` ("Family,
#'   Given; ..."), `n_authors`, `url`, `doi`, `isbn`, `issn`, `language`,
#'   `accessed`. Abstracts and other fields remain available via `raw = TRUE`.
csl_items_to_df <- function(items) {
  issued <- vapply(items, function(x) csl_date(x[["issued"]]), character(1))
  data.frame(
    citation_key = csl_scalar(items, "citation-key"),
    item_type = csl_scalar(items, "type"),
    title = csl_scalar(items, "title"),
    title_short = csl_scalar(items, "title-short"),
    container_title = csl_scalar(items, "container-title"),
    publisher = csl_scalar(items, "publisher"),
    publisher_place = csl_scalar(items, "publisher-place"),
    issued = issued,
    year = vapply(issued, csl_year, integer(1), USE.NAMES = FALSE),
    authors = vapply(items, function(x) csl_names(x[["author"]]), character(1)),
    editors = vapply(items, function(x) csl_names(x[["editor"]]), character(1)),
    n_authors = vapply(items, function(x) length(x[["author"]]), integer(1)),
    url = csl_scalar(items, "URL"),
    doi = csl_scalar(items, "DOI"),
    isbn = csl_scalar(items, "ISBN"),
    issn = csl_scalar(items, "ISSN"),
    language = csl_scalar(items, "language"),
    accessed = vapply(items, function(x) csl_date(x[["accessed"]]), character(1)),
    stringsAsFactors = FALSE
  )
}

# One character value per item for a scalar or multi-valued CSL field.
csl_scalar <- function(items, field) {
  vapply(items, function(x) {
    v <- x[[field]]
    if (is.null(v)) NA_character_ else paste(unlist(v), collapse = "; ")
  }, character(1), USE.NAMES = FALSE)
}

# CSL date: date-parts ("2025-12-20", "2025-12", "2025") or literal/raw text.
csl_date <- function(d) {
  if (is.null(d)) return(NA_character_)
  dp <- d[["date-parts"]]
  if (!is.null(dp) && length(dp[[1]]) > 0) {
    p <- as.integer(unlist(dp[[1]]))
    return(switch(
      as.character(min(length(p), 3L)),
      "1" = sprintf("%04d", p[1]),
      "2" = sprintf("%04d-%02d", p[1], p[2]),
      sprintf("%04d-%02d-%02d", p[1], p[2], p[3])
    ))
  }
  txt <- if (!is.null(d[["literal"]])) d[["literal"]] else d[["raw"]]
  if (is.null(txt)) NA_character_ else as.character(txt)
}

# First four-digit run in the date string; NA for "n.d." and similar.
csl_year <- function(issued) {
  if (is.na(issued)) return(NA_integer_)
  yr <- regmatches(issued, regexpr("[0-9]{4}", issued))
  if (length(yr)) as.integer(yr) else NA_integer_
}

# "Family, Given; Family, Given" from CSL name lists; literal names kept as-is.
csl_names <- function(people) {
  if (length(people) == 0) return(NA_character_)
  nm <- vapply(people, function(p) {
    if (!is.null(p[["literal"]])) return(p[["literal"]])
    fam <- if (is.null(p[["family"]])) "" else p[["family"]]
    giv <- if (is.null(p[["given"]])) "" else p[["given"]]
    if (nzchar(fam) && nzchar(giv)) paste0(fam, ", ", giv) else paste0(fam, giv)
  }, character(1))
  paste(nm, collapse = "; ")
}
