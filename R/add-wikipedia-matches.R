# Add Wikipedia search results to a tibble of place names.
#
# - Uses the WikipediR package if available; falls back to the MediaWiki API via httr if not.
# - Adds columns:
#     wikipedia_found   (logical)  : whether any search result was returned
#     wikipedia_match   (logical)  : whether the top result's title is an exact match (ignores case/space)
#     wikipedia_title   (chr / NA) : title of the top search result
#     wikipedia_url     (chr / NA) : URL to the top result page
#     wikipedia_snippet (chr / NA) : snippet returned by the search (may contain HTML)
#
# Usage:
#   result_aug <- add_wikipedia_matches(result, name_col = "name", lang = "en", delay = 0.5)
#
add_wikipedia_matches <- function(df, name_col = "name", lang = "en", delay = 0.5, limit = 5) {
  stopifnot(is.data.frame(df), name_col %in% names(df))
  names_vec <- as.character(df[[name_col]])
  
  # Helper: use WikipediR if available, otherwise fallback to httr.
  search_wikipedia_one <- function(query, lang = "en", limit = 5) {
    # Normalize NA/empty
    if (is.na(query) || nzchar(trimws(query)) == FALSE) {
      return(list(found = FALSE, title = NA_character_, url = NA_character_, snippet = NA_character_))
    }
    
    # Try WikipediR first
    res <- NULL
    if (requireNamespace("WikipediR", quietly = TRUE)) {
      try({
        res <- WikipediR::page_search(language = lang, project = "wikipedia",
                                      query = query, limit = limit)
      }, silent = TRUE)
    }
    
    # If WikipediR didn't return a usable structure, use the raw API
    if (is.null(res) || !is.list(res) || is.null(res$query) || is.null(res$query$search)) {
      if (!requireNamespace("httr", quietly = TRUE) || !requireNamespace("jsonlite", quietly = TRUE)) {
        stop("WikipediR not available and httr/jsonlite not installed for fallback. ",
             "Install one of these: install.packages('WikipediR') or install.packages(c('httr','jsonlite')).")
      }
      # Call MediaWiki API
      api_url <- paste0("https://", lang, ".wikipedia.org/w/api.php")
      resp <- httr::GET(api_url, query = list(
        action = "query",
        list = "search",
        srsearch = query,
        srlimit = limit,
        format = "json"
      ))
      if (httr::status_code(resp) >= 400) {
        return(list(found = FALSE, title = NA_character_, url = NA_character_, snippet = NA_character_))
      }
      txt <- httr::content(resp, as = "text", encoding = "UTF-8")
      json <- jsonlite::fromJSON(txt, simplifyVector = FALSE)
      res <- json
    }
    
    # Extract top search result if present
    search_hits <- NULL
    if (!is.null(res$query$search)) {
      search_hits <- res$query$search
    } else if (!is.null(res$search)) {
      # some variants might place the array under res$search
      search_hits <- res$search
    }
    
    if (is.null(search_hits) || length(search_hits) == 0) {
      return(list(found = FALSE, title = NA_character_, url = NA_character_, snippet = NA_character_))
    }
    
    top <- search_hits[[1]]
    # top may be a named list with elements title, pageid, snippet
    top_title <- if (!is.null(top$title)) as.character(top$title) else NA_character_
    top_snippet <- if (!is.null(top$snippet)) as.character(top$snippet) else NA_character_
    
    # Construct URL safely (use underscore for spaces and urlencode)
    title_for_url <- gsub(" ", "_", top_title)
    # URLencode but preserve slashes, etc.
    url <- paste0("https://", lang, ".wikipedia.org/wiki/", utils::URLencode(title_for_url, reserved = TRUE))
    
    list(found = TRUE, title = top_title, url = url, snippet = top_snippet)
  }
  
  # Row-wise loop with mild delay to avoid hitting rate limits.
  results <- vector("list", length(names_vec))
  for (i in seq_along(names_vec)) {
    nm <- names_vec[i]
    # Respect a small delay between requests
    if (i > 1 && delay > 0) Sys.sleep(delay)
    
    res_i <- tryCatch(
      search_wikipedia_one(nm, lang = lang, limit = limit),
      error = function(e) list(found = FALSE, title = NA_character_, url = NA_character_, snippet = NA_character_)
    )
    
    # Determine whether top title is an "exact" match: compare lowercase after removing spaces
    matched <- FALSE
    if (isTRUE(res_i$found) && !is.na(res_i$title)) {
      norm_query <- tolower(gsub("\\s+", "", nm))
      norm_title <- tolower(gsub("\\s+", "", res_i$title))
      matched <- nzchar(norm_query) && nzchar(norm_title) && identical(norm_query, norm_title)
    }
    
    results[[i]] <- list(
      wikipedia_found   = isTRUE(res_i$found),
      wikipedia_match   = isTRUE(matched),
      wikipedia_title   = if (isTRUE(res_i$found)) res_i$title else NA_character_,
      wikipedia_url     = if (isTRUE(res_i$found)) res_i$url else NA_character_,
      wikipedia_snippet = if (isTRUE(res_i$found)) res_i$snippet else NA_character_
    )
  }
  
  # Bind results into a data.frame/tibble and cbind to original df
  results_df <- do.call(rbind, lapply(results, function(x) as.data.frame(x, stringsAsFactors = FALSE)))
  # Preserve tibble class if input was tibble
  if (inherits(df, "tbl_df") && requireNamespace("tibble", quietly = TRUE)) {
    results_tbl <- tibble::as_tibble(results_df)
  } else {
    results_tbl <- results_df
  }
  
  # Combine and return
  out <- cbind(df, results_tbl)
  # ensure logical columns are logical type
  out$wikipedia_found <- as.logical(out$wikipedia_found)
  out$wikipedia_match <- as.logical(out$wikipedia_match)
  out
}

# Example usage (assuming `result` is your tibble):
# result_augmented <- add_wikipedia_matches(result, name_col = "name", lang = "en", delay = 0.5)
# print(result_augmented)