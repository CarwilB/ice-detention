# Import a Zotero Better BibTeX (CSL JSON) export as a flat tibble.
#
# Bibliographic fields only: name arrays are joined to "Family, Given" strings,
# date-parts are collapsed to ISO-style "YYYY-MM-DD" strings, and hyphenated
# CSL keys are renamed to snake_case.

import_zotero_csl_json <- function(path) {
  items <- jsonlite::fromJSON(path, simplifyVector = FALSE)

  format_name_list <- function(x) {
    if (is.null(x)) return(NA_character_)
    map_chr(x, function(p) {
      if (is.null(p$family) && is.null(p$given)) return(NA_character_)
      if (is.null(p$given)) p$family else paste(p$family, p$given, sep = ", ")
    }) |>
      paste(collapse = "; ")
  }

  format_date <- function(x) {
    if (is.null(x) || is.null(x$`date-parts`)) return(NA_character_)
    x$`date-parts`[[1]][[1]] |> paste(collapse = "-")
  }

  simple_field <- function(x, field) {
    v <- x[[field]]
    if (is.null(v)) return(NA_character_)
    if (length(v) > 1) paste(unlist(v), collapse = "; ") else as.character(v)
  }

  fields <- c(
    "title", "title-short", "container-title", "container-title-short",
    "publisher", "publisher-place", "page", "volume", "issue", "number",
    "edition", "language", "ISSN", "ISBN", "DOI", "URL", "abstract",
    "source", "archive", "section", "license", "number-of-pages"
  )

  map_dfr(items, function(x) {
    tibble(
      id            = x$id,
      citation_key  = x[["citation-key"]] %||% NA_character_,
      item_type     = x$type %||% NA_character_,
      author        = format_name_list(x$author),
      editor        = format_name_list(x$editor),
      issued        = format_date(x$issued),
      accessed      = format_date(x$accessed),
      year          = suppressWarnings(as.integer(substr(issued, 1, 4)))
    ) |>
      bind_cols(map_dfc(set_names(fields), function(f) tibble(!!f := simple_field(x, f))))
  }) |>
    rename_with(~ str_replace_all(.x, "-", "_"))
}
