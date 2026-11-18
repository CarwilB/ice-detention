# Google web search restricted to a fixed allowlist of domains.
#
# No Google search API credentials are available in this project, so results
# are scraped from google.com/search with httr2, following the same
# rate-limiting conventions as add_wikipedia_matches() in add-wikipedia-matches.R.
#
# The allowlist is enforced two ways: (1) the query carries an OR-chain of
# `site:` operators; (2) returned links are filtered to the allowlist
# client-side, since Google occasionally ignores part of a long site: chain.

.google_search_url_domains <- c(
  "google.com", "google.ad", "google.ae", "googleapis.com", "gstatic.com",
  "googleusercontent.com", "youtube.com", "youtu.be", "gg.gg", "goo.gl"
)

.resolve_google_href <- function(href) {
  # Legacy "/url?q=..." redirect wrappers carry the real target in `q`
  if (str_detect(href, "^/url\\?")) {
    q <- httr2::url_parse(paste0("https://www.google.com", href))$query$q
    return(q %||% NA_character_)
  }
  if (str_detect(href, "^https?://")) href else NA_character_
}

google_search_facility <- function(facility_name,
                                   domains = NULL,
                                   max_results = 20,
                                   pause = 2,
                                   strict = TRUE,
                                   verbose = FALSE) {
  if (is.null(domains)) {
    domains <- get0("top40domains", envir = globalenv(), ifnotfound = NULL)
    if (is.null(domains)) {
      cli::cli_abort("Provide {.arg domains} or define {.var top40domains}.")
    }
  }

  site_chain <- paste0("site:", domains, collapse = " OR ")
  query <- paste0('"', facility_name, '" (', site_chain, ")")

  resp <- httr2::request("https://www.google.com/search") |>
    httr2::req_url_query(q = query, num = max_results, hl = "en", pws = 0) |>
    httr2::req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36") |>
    httr2::req_perform()

  html <- httr2::resp_body_html(resp)

  hrefs <- rvest::html_elements(html, "a") |>
    rvest::html_attr("href")
  texts <- rvest::html_elements(html, "a") |>
    rvest::html_text2()

  urls <- map_chr(hrefs, .resolve_google_href)
  hosts <- map_chr(urls, function(u) {
    if (is.na(u)) return(NA_character_)
    tryCatch(httr2::url_parse(u)$hostname, error = function(e) NA_character_)
  })

  hits <- tibble(
    url = urls,
    link_text = texts,
    host = hosts
  ) |>
    filter(!is.na(url), !is.na(host)) |>
    # Drop Google's own navigation / cache / translate links
    filter(!str_detect(host, paste(.google_search_url_domains, collapse = "|"))) |>
    # Allowlist filter: exact host, subdomain, or bare-apex variant
    filter(map_lgl(host, function(h) {
      any(h == domains | str_ends(h, paste0(".", domains)) |
            paste0("www.", domains) == h)
    })) |>
    distinct(url, .keep_all = TRUE) |>
    slice_head(n = max_results) |>
    mutate(rank = row_number())

  if (verbose) {
    dropped <- sum(!is.na(hosts) & !map_lgl(hosts, function(h) {
      any(h == domains | str_ends(h, paste0(".", domains)))
    }), na.rm = TRUE)
    cli::cli_inform("{length(hits)} allowlisted result(s) for {.val {facility_name}}; {dropped} link(s) dropped by the allowlist filter.")
  }

  if (!strict) {
    # Keep allowlisted hits first, non-allowlisted after (still no Google links)
    nonlisted <- tibble(url = hrefs |> map_chr(.resolve_google_href),
                        link_text = texts, host = hosts) |>
      filter(!is.na(url), !is.na(host)) |>
      filter(!str_detect(host, paste(.google_search_url_domains, collapse = "|"))) |>
      filter(!url %in% hits$url) |>
      distinct(url, .keep_all = TRUE) |>
      mutate(rank = NA_integer_)
    hits <- bind_rows(hits, nonlisted) |> slice_head(n = max_results)
  }

  if (nrow(hits) > 0) hits <- mutate(hits, facility_name = facility_name, .before = 1)
  Sys.sleep(pause)
  hits
}

google_search_facilities <- function(facility_names, ...) {
  safe_search <- function(n) {
    tryCatch(google_search_facility(n, ...), error = function(e) {
      cli::cli_warn("Search failed for {.val {n}}: {e$message}")
      NULL
    })
  }
  map(facility_names, safe_search) |>
    compact() |>
    list_rbind()
}
