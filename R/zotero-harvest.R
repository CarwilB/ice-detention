# zotero-harvest.R
# Harvest references from Wikipedia facility articles into the shared Zotero
# group library (https://www.zotero.org/groups/6462728/ice_detention/library).
#
# Extraction, deduplication, enrichment, item conversion, and posting reuse the
# wiki-refs-to-zotero system developed in the wiki-graph project:
#   ~/Dropbox/R/wiki-graph/wiki-refs-to-zotero.R
# (parses {{cite ...}} templates from wikitext directly — more complete than
# COINS, which only covers citation templates that emit COINS metadata; the
# archived CRAN `wikitools` package is not used.)
#
# Extraction, deduplication, enrichment, item conversion, and posting come from
# R/wiki-refs-to-zotero.R (ported from the wiki-graph project).
#
# Zotero write targets a GROUP library: c2z's Zotero(user = FALSE, id = <gid>)
# and Zotero API paths /groups/<gid>/...
#
# All loops are resumable, following the per-entry cache pattern of the user's
# wikitools package (cache_wikitext / resume_*): article wikitext cached as
# .txt files, per-article refs saved as .rds immediately after extraction, and
# an append-only import log so interrupted harvest runs continue where they
# left off. Cache lives in data/cache/wiki-refs/; delete it (or individual
# files) to force a re-fetch.

ZOTERO_GROUP_ID <- 6462728L
ZOTERO_PARENT_COLLECTION <- "ICE detention facility references"
ZOTERO_HARVEST_CACHE <- here::here("data", "cache", "wiki-refs")


# ── Article → collection mapping ─────────────────────────────────────────────

#' Map list-article links to facility collections.
#'
#' Resolves each linked slug to its target article (redirect targets win),
#' matches resolved articles against `canonical_wiki_match` to recover the
#' canonical facility name, and names every extant article's collection
#' (canonical name where matched, article title otherwise).
#'
#' @param extant Output of `build_wiki_list_extant_articles()`.
#' @param canonical_match Output of `build_canonical_wiki_match()`.
#' @return One row per distinct extant article: `article_title` (resolved),
#'   `collection_name`, `canonical_name` (NA if unmatched), `n_listed_rows`,
#'   `linked_facilities`.
build_wiki_article_collection_map <- function(extant, canonical_match) {
  match_lookup <- canonical_match |>
    dplyr::select(wiki_slug, canonical_name) |>
    dplyr::distinct()

  extant |>
    dplyr::filter(exists) |>
    dplyr::mutate(
      # Slugs scraped from hrefs carry percent-encoding (e.g. %27 for
      # apostrophes); decode so titles work as API parameters and filenames.
      article_title = utils::URLdecode(dplyr::if_else(
        redirect, dplyr::coalesce(redirect_target, title), title
      ))
    ) |>
    dplyr::left_join(match_lookup, by = c("article_title" = "wiki_slug"),
                     relationship = "many-to-many") |>
    dplyr::group_by(article_title) |>
    dplyr::summarise(
      # A few articles match more than one canonical facility; take the
      # first alphabetically and record how many matched.
      canonical_name = dplyr::first(sort(unique(
        canonical_name[!is.na(canonical_name)]))),
      n_canonical_matches = dplyr::n_distinct(canonical_name[!is.na(canonical_name)]),
      n_listed_rows = sum(n_listed_rows),
      linked_facilities = paste(sort(unique(
        stringr::str_split(linked_facilities, "; ", simplify = TRUE)
      )), collapse = "; "),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      collection_name = dplyr::coalesce(canonical_name, article_title)
    ) |>
    dplyr::arrange(article_title)
}


# ── Reference extraction (no Zotero access) ──────────────────────────────────

# Cache file naming follows wikitools::cache_wikitext(): characters illegal in
# filenames are replaced with underscores.
.wiki_cache_filename <- function(title) {
  paste0(gsub("[/:*?\"<>|]", "_", title))
}

.wikitext_cache_path <- function(title, cache_dir) {
  file.path(cache_dir, "wikitext", paste0(.wiki_cache_filename(title), ".txt"))
}

.refs_cache_path <- function(title, cache_dir) {
  file.path(cache_dir, "refs", paste0(.wiki_cache_filename(title), ".rds"))
}

#' Fetch article wikitext through a .txt cache.
#'
#' Mirrors `wikitools::cache_wikitext()` but keeps the retry/backoff from
#' `fetch_wikitext()`, since `wikitools::get_wikitext_by_name()` returns NULL
#' silently on HTTP errors (which would mask rate-limit failures).
.fetch_cached_wikitext <- function(title, language, cache_dir) {
  path <- .wikitext_cache_path(title, cache_dir)
  if (file.exists(path)) {
    return(paste(readLines(path, warn = FALSE), collapse = "\n"))
  }
  wikitext <- fetch_wikitext(title, language = language)
  writeLines(wikitext, path)
  wikitext
}

#' Extract and deduplicate references from every mapped article.
#'
#' Resumable: wikitext is cached as `.txt` under `<cache_dir>/wikitext/` and
#' the extracted refs are saved as `.rds` under `<cache_dir>/refs/`
#' immediately after each article, so an interrupted run (or a re-run after
#' adding articles) skips everything already extracted. Failed articles are
#' NOT cached — they leave no refs file and are retried on the next run — but
#' they get an empty tibble in the returned list so the name set always
#' matches `article_map`.
#'
#' @param article_map Output of `build_wiki_article_collection_map()`.
#' @param language Wikipedia language code.
#' @param cache_dir Cache directory (wikitext and refs subdirectories).
#' @return Named list of refs tibbles (names = article titles), plus a
#'   `.extraction_errors` attribute (named character vector) when any article
#'   failed, and a `.n_fetched` attribute counting articles fetched this run.
harvest_wiki_article_refs <- function(article_map, language = "en",
                                      cache_dir = ZOTERO_HARVEST_CACHE) {
  dir.create(file.path(cache_dir, "wikitext"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(cache_dir, "refs"), recursive = TRUE, showWarnings = FALSE)
  titles <- article_map$article_title
  refs_list <- stats::setNames(vector("list", length(titles)), titles)
  errors <- character(0)
  n_fetched <- 0L

  for (title in titles) {
    rpath <- .refs_cache_path(title, cache_dir)
    if (file.exists(rpath)) {
      refs_list[[title]] <- readRDS(rpath)
      message(sprintf("[%d/%d] %s: %d (cached)",
                      match(title, titles), length(titles), title,
                      nrow(refs_list[[title]])))
      next
    }
    ok <- tryCatch(
      {
        wikitext <- .fetch_cached_wikitext(title, language, cache_dir)
        refs <- extract_refs_from_wikitext(wikitext)
        # deduplicate_refs() errors on zero-row input; template-less articles
        # stay as empty tibbles and are cached as such
        if (nrow(refs) > 0) refs <- deduplicate_refs(refs)
        saveRDS(refs, rpath) # save immediately so the loop stays resumable
        refs_list[[title]] <- refs
        n_fetched <<- n_fetched + 1L
        TRUE
      },
      error = function(e) {
        errors[title] <<- conditionMessage(e)
        FALSE
      }
    )
    if (!ok) refs_list[[title]] <- tibble::tibble()
    message(sprintf("[%d/%d] %s: %d%s",
                    match(title, titles), length(titles), title,
                    nrow(refs_list[[title]]),
                    if (!ok) " (FAILED — will retry on next run)" else ""))
    # Pace only actual network fetches; cached titles cost nothing
    if (ok) Sys.sleep(0.5)
  }

  if (length(errors) > 0) attr(refs_list, ".extraction_errors") <- errors
  attr(refs_list, ".n_fetched") <- n_fetched
  refs_list
}


# ── Zotero group-library helpers ─────────────────────────────────────────────

.zotero_headers <- function(api_key) {
  httr2::request("https://api.zotero.org") |>
    httr2::req_headers(
      "Zotero-API-Key"     = api_key,
      "Zotero-API-Version" = "3"
    ) |>
    httr2::req_retry(
      max_tries    = 4,
      is_transient = \(r) httr2::resp_status(r) %in% c(429, 503),
      after        = \(r) {
        val <- httr2::resp_header(r, "Backoff") %||%
          httr2::resp_header(r, "Retry-After")
        if (!is.null(val)) as.numeric(val) else NULL
      }
    )
}

#' Fetch all collections in the Zotero group library (paginated).
#'
#' @param group_id Zotero group ID.
#' @param api_key Zotero API key (read access sufficient).
#' @return Tibble: `key`, `version`, `name`, `parent` (NA at top level).
zotero_group_collections <- function(group_id = ZOTERO_GROUP_ID, api_key) {
  base <- .zotero_headers(api_key) |>
    httr2::req_url_path_append("groups", group_id, "collections")

  first <- base |>
    httr2::req_url_query(limit = 100, start = 0) |>
    httr2::req_perform()
  total <- as.integer(httr2::resp_header(first, "Total-Results") %||% "0")
  raw <- httr2::resp_body_json(first, simplifyVector = FALSE)

  if (total > 100) {
    raw <- c(raw, purrr::list_flatten(purrr::map(seq(100, total - 1, by = 100),
      function(start) {
        base |>
          httr2::req_url_query(limit = 100, start = start) |>
          httr2::req_perform() |>
          httr2::resp_body_json(simplifyVector = FALSE)
      })))
  }

  tibble::tibble(
    key      = purrr::map_chr(raw, "key"),
    version  = purrr::map_int(raw, "version"),
    name     = purrr::map_chr(raw, function(x) x$data$name),
    # parentCollection is FALSE (JSON boolean) at the top level, a key string
    # for subcollections
    parent   = purrr::map_chr(raw, function(x) {
      p <- x$data$parentCollection
      if (is.null(p) || is.logical(p)) NA_character_ else as.character(p)
    })
  )
}

#' Find or create a Zotero collection, optionally under a parent.
#'
#' @param name Collection name.
#' @param parent_key Parent collection key, or `FALSE` for top level.
#' @param group_id Zotero group ID.
#' @param api_key Zotero API key (write access required).
#' @param existing Optional pre-fetched collections tibble (from
#'   `zotero_group_collections()`); fetched if not supplied.
#' @return The collection's 8-character key.
zotero_ensure_collection <- function(name, parent_key = FALSE,
                                     group_id = ZOTERO_GROUP_ID, api_key,
                                     existing = NULL) {
  existing <- existing %||% zotero_group_collections(group_id, api_key)
  parent_lookup <- if (isFALSE(parent_key)) NA_character_ else parent_key
  hit <- existing |>
    dplyr::filter(name == .env$name,
                  (is.na(parent) & is.na(parent_lookup)) | parent == parent_lookup)
  if (nrow(hit) > 0) return(hit$key[1])

  body <- list(list(name = name, parentCollection = parent_key))
  resp <- .zotero_headers(api_key) |>
    httr2::req_url_path_append("groups", group_id, "collections") |>
    httr2::req_body_json(body) |>
    httr2::req_perform()
  json <- httr2::resp_body_json(resp, simplifyVector = FALSE)
  if (length(json$failed) > 0) {
    stop("Zotero collection creation failed for '", name, "'")
  }
  unlist(json$success, use.names = FALSE)[1]
}

# Deduplicate refs against a pre-fetched library (same DOI → ISBN →
# title+year cascade as check_library_for_refs, but the library is fetched
# once per harvest run rather than once per article).
.check_refs_against_library <- function(refs, library_items) {
  refs$existing_key  <- NA_character_
  refs$import_action <- "create_new"
  refs$duplicate_how <- NA_character_
  if (nrow(library_items) == 0) return(refs)

  norm <- function(x) {
    x <- tolower(dplyr::coalesce(as.character(x), ""))
    x <- stringi::stri_trans_general(x, "Latin-ASCII")
    stringr::str_replace_all(x, "[^a-z0-9]", "")
  }

  for (i in seq_len(nrow(refs))) {
    doi  <- norm(refs$DOI[i])
    isbn <- norm(refs$ISBN[i])
    titl <- norm(refs$title[i])
    yr   <- refs$year[i] %||% ""

    hit <- NULL
    if (nzchar(doi)) {
      hit <- dplyr::filter(library_items, doi_norm == doi)
      if (nrow(hit)) refs$duplicate_how[i] <- "DOI"
    }
    if (is.null(hit) || nrow(hit) == 0) {
      if (nzchar(isbn)) {
        hit <- dplyr::filter(library_items, isbn_norm == isbn)
        if (nrow(hit)) refs$duplicate_how[i] <- "ISBN"
      }
    }
    if ((is.null(hit) || nrow(hit) == 0) && nzchar(titl) && nzchar(yr)) {
      hit <- dplyr::filter(library_items,
                           title_norm == titl, year_norm == yr)
      if (nrow(hit)) refs$duplicate_how[i] <- "title + year"
    }
    if (!is.null(hit) && nrow(hit) > 0) {
      refs$existing_key[i]  <- hit$key[1]
      refs$import_action[i] <- "add_to_collection"
    }
  }
  refs
}


# ── Harvest driver ───────────────────────────────────────────────────────────

# Raw Zotero item posting. c2z's ZoteroPost was dropped because it dropped
# the collections assignment on posted items and swallowed failed batches
# (returning NULL with a bogus progress readout). This posts each item
# explicitly with its collection membership and verifies every batch.

# Convert one row of the refs_to_zotero_items() output into a Zotero API item
# object (named list with explicitly unboxed scalars so that `creators` and
# `collections` stay JSON arrays).
.zotero_item_object <- function(row, collection_key) {
  fields <- lapply(names(row), function(nm) {
    v <- row[[nm]]
    if (is.list(v)) {
      cell <- if (length(v) > 0) v[[1]] else NULL
      if (nm == "creators") {
        # cell = list of creator objects. Zotero requires either
        # {creatorType, lastName, firstName} or {creatorType, name} — never
        # firstName: null. Institutional authors (firstName missing/NA/"")
        # switch to the name-only form.
        return(lapply(cell %||% list(), function(cr) {
          fn <- cr$firstName
          ln <- cr$lastName
          bad_fn <- is.null(fn) || (length(fn) == 1 && (is.na(fn) || !nzchar(fn)))
          if (bad_fn) {
            list(
              creatorType = jsonlite::unbox(cr$creatorType),
              name = jsonlite::unbox(ifelse(is.null(ln) || (length(ln) == 1 && is.na(ln)), "", ln))
            )
          } else {
            lapply(cr, function(x) jsonlite::unbox(ifelse(length(x) == 1 && is.na(x), "", x)))
          }
        }))
      }
      return(cell %||% list())
    }
    if (length(v) == 1 && is.na(v)) return(jsonlite::unbox(""))
    jsonlite::unbox(v)
  })
  names(fields) <- names(row)
  fields$collections <- list(jsonlite::unbox(collection_key))
  fields$tags <- list()
  fields
}

#' POST new items (with collection membership) to the Zotero group library.
#'
#' Batches of up to 50 items per request (the API maximum), with retry on
#' 429/503. Every batch's response is verified: any failed item aborts with
#' an informative error instead of failing silently.
#'
#' @param items Output of `refs_to_zotero_items()`.
#' @param collection_key Key of the collection to file every item into.
#' @param group_id Zotero group ID.
#' @param api_key Zotero API key (write access required).
#' @return Character vector of created item keys, in input order.
.zotero_post_items <- function(items, collection_key, group_id, api_key) {
  objects <- lapply(seq_len(nrow(items)), function(i)
    .zotero_item_object(items[i, ], collection_key))

  .post_batch <- function(batch) {
    resp <- .zotero_headers(api_key) |>
      httr2::req_url_path_append("groups", group_id, "items") |>
      httr2::req_body_json(batch, auto_unbox = FALSE) |>
      httr2::req_perform()
    httr2::resp_body_json(resp, simplifyVector = FALSE)
  }

  # Zotero rejects some creator types per item type (e.g. 'editor' on
  # 'webpage'). Retry just the rejected items with editor → contributor.
  .sanitize_creators <- function(obj) {
    obj$creators <- lapply(obj$creators, function(cr) {
      if (identical(as.character(cr$creatorType), "editor")) {
        cr$creatorType <- jsonlite::unbox("contributor")
      }
      cr
    })
    obj
  }

  batches <- split(objects, ceiling(seq_along(objects) / 50))
  created <- character(0)
  for (batch in batches) {
    json <- .post_batch(batch)
    n_ok <- length(json$success %||% list())
    n_failed <- length(json$failed %||% list())
    if (n_failed > 0 || n_ok < length(batch)) {
      failed_idx <- as.integer(names(json$failed %||% list())) + 1L
      creator_issues <- purrr::map_lgl(json$failed, function(f)
        f$code == 400 && grepl("valid creator type", f$message %||% ""))
      if (!all(creator_issues)) {
        stop(sprintf(
          "Zotero item POST incomplete: %d succeeded, %d failed of %d sent. First failure: %s",
          n_ok, n_failed, length(batch),
          paste(capture.output(str(json$failed[[1]])), collapse = " ")))
      }
      message("Retrying ", length(failed_idx),
              " item(s) with editor creators as contributors...")
      fixed <- lapply(batch[failed_idx], .sanitize_creators)
      json2 <- .post_batch(fixed)
      n_ok2 <- length(json2$success %||% list())
      if (n_ok2 < length(fixed) || length(json2$failed %||% list()) > 0) {
        stop("Zotero item POST failed even after creator sanitization: ",
             paste(capture.output(str(json2$failed[[1]])), collapse = " "))
      }
      json$success <- c(json$success, json2$success)
    }
    created <- c(created, unlist(json$success, use.names = FALSE))
  }
  created
}

.import_log_path <- function(cache_dir) file.path(cache_dir, "import-log.csv")

# Append one row to the import log after each article completes, so an
# interrupted run resumes from where it stopped.
.append_import_log <- function(row, cache_dir) {
  readr::write_csv(row, .import_log_path(cache_dir),
                   append = file.exists(.import_log_path(cache_dir)))
}

#' Import facility references into the Zotero group library.
#'
#' For each mapped article: ensures its subcollection exists under the parent
#' collection, enriches the parsed refs via DOI/ISBN (optional), checks the
#' group library for duplicates, posts new items into the subcollection, and
#' moves already-existing items into it.
#'
#' Resumable at two levels. Extraction (when `refs_list` is NULL) uses the
#' per-article wikitext/refs cache. The import itself appends one row per
#' completed article to `<cache_dir>/import-log.csv`; with `resume = TRUE`
#' (the default) articles already marked `imported` in the log are skipped,
#' so an interrupted run continues where it stopped. `resume = FALSE`
#' reprocesses every article — still safe, because library duplicates are
#' attached to collections rather than re-created.
#'
#' @param article_map Output of `build_wiki_article_collection_map()`.
#' @param refs_list Named list of refs tibbles, from
#'   `harvest_wiki_article_refs()`; names must match `article_map$article_title`.
#'   If NULL, references are extracted (from cache where possible) inside the
#'   loop.
#' @param group_id Zotero group ID.
#' @param parent_collection Name of the parent collection (created if absent).
#' @param enrich Enrich metadata via DOI/ISBN lookups (default TRUE).
#' @param dry_run Do everything except writing to Zotero (default FALSE).
#' @param resume Skip articles already logged as imported (default TRUE).
#' @param cache_dir Cache directory for wikitext, refs, and the import log.
#' @param api_key Zotero API key (write access to the group).
#' @return Tibble, one row per article: `article_title`, `collection_name`,
#'   `collection_key`, `n_refs`, `n_new`, `n_existing`, `status`.
harvest_wiki_refs_to_zotero <- function(article_map, refs_list = NULL,
                                        group_id = ZOTERO_GROUP_ID,
                                        parent_collection = ZOTERO_PARENT_COLLECTION,
                                        enrich = TRUE, dry_run = FALSE,
                                        resume = TRUE,
                                        cache_dir = ZOTERO_HARVEST_CACHE,
                                        api_key = Sys.getenv("zotero_access_key_write")) {
  if (!nzchar(api_key)) {
    stop("`zotero_access_key_write` not set. Add it to ~/.Renviron and restart R.")
  }

  if (is.null(refs_list)) {
    refs_list <- harvest_wiki_article_refs(article_map, cache_dir = cache_dir)
  }
  stopifnot(setequal(names(refs_list), article_map$article_title))
  extraction_errors <- attr(refs_list, ".extraction_errors") %||% character(0)

  # Resume: skip articles already imported in a previous run
  log_path <- .import_log_path(cache_dir)
  previous <- tibble::tibble()
  skip_titles <- character(0)
  if (resume && file.exists(log_path)) {
    previous <- readr::read_csv(log_path, show_col_types = FALSE)
    skip_titles <- previous$article_title[previous$status == "imported"]
    if (length(skip_titles) > 0) {
      message("Resuming: ", length(skip_titles),
              " article(s) already imported in a previous run will be skipped.")
    }
  }

  message("Fetching group collections and library items...")
  existing_collections <- zotero_group_collections(group_id, api_key)
  library_items <- .fetch_zotero_items(user_id = group_id, api_key = api_key,
                                       user = FALSE)

  if (dry_run) {
    parent_key <- "(dry run)"
    message("DRY RUN: would ensure parent collection '", parent_collection, "'")
  } else {
    parent_key <- zotero_ensure_collection(
      parent_collection, FALSE, group_id = group_id, api_key = api_key,
      existing = existing_collections)
  }

  todo <- article_map |> dplyr::filter(!article_title %in% skip_titles)

  results <- purrr::pmap_dfr(
    list(todo$article_title, todo$collection_name),
    function(article_title, collection_name) {
      refs <- refs_list[[article_title]]
      if (nrow(refs) == 0) {
        return(tibble::tibble(
          article_title, collection_name, collection_key = NA_character_,
          n_refs = 0L, n_new = 0L, n_existing = 0L,
          status = if (article_title %in% extraction_errors)
            "extraction_failed" else "no_refs"))
      }

      if (enrich) {
        refs <- tryCatch(enrich_refs(refs),
                         error = function(e) {
                           message("Enrichment failed for ", article_title,
                                   ": ", conditionMessage(e))
                           refs
                         })
      }
      refs <- .check_refs_against_library(refs, library_items)

      n_new <- sum(refs$import_action == "create_new")
      n_existing <- sum(refs$import_action == "add_to_collection")

      if (dry_run) {
        message(sprintf("DRY RUN %-55s %3d new / %3d existing",
                        collection_name, n_new, n_existing))
        return(tibble::tibble(
          article_title, collection_name, collection_key = NA_character_,
          n_refs = nrow(refs), n_new = n_new, n_existing = n_existing,
          status = "dry_run"))
      }

      collection_key <- zotero_ensure_collection(
        collection_name, parent_key, group_id = group_id, api_key = api_key,
        existing = existing_collections)
      existing_collections <<- dplyr::bind_rows(
        existing_collections,
        tibble::tibble(
          key = collection_key, version = 0L, name = collection_name,
          parent = parent_key)
      )

      new_refs <- dplyr::filter(refs, import_action == "create_new")
      if (nrow(new_refs) > 0) {
        .zotero_post_items(refs_to_zotero_items(new_refs), collection_key,
                           group_id, api_key)
      }

      existing_keys <- refs |>
        dplyr::filter(import_action == "add_to_collection") |>
        dplyr::pull(existing_key) |>
        stats::na.omit() |>
        as.character()
      if (length(existing_keys) > 0) {
        add_items_to_collection(existing_keys, collection_key,
                                user_id = group_id, api_key = api_key,
                                user = FALSE)
      }

      message(sprintf("IMPORTED %-55s %3d new / %3d existing",
                      collection_name, n_new, n_existing))
      row <- tibble::tibble(
        article_title, collection_name, collection_key = collection_key,
        n_refs = nrow(refs), n_new = n_new, n_existing = n_existing,
        status = "imported")
      .append_import_log(row, cache_dir)
      row
    })

  # Include previously imported articles so the result always covers the map
  if (nrow(previous) > 0) {
    results <- dplyr::bind_rows(
      dplyr::filter(previous, status == "imported"),
      results) |>
      dplyr::arrange(article_title) |>
      dplyr::distinct(article_title, .keep_all = TRUE)
  }

  if (dry_run) attr(results, ".parent_key_dry_run") <- parent_collection
  results
}
