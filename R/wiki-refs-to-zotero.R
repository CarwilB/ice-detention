# wiki-refs-to-zotero.R
# Extract references from a Wikipedia article and import into Zotero.
#
# Handles two Wikipedia citation styles:
#   1. Inline <ref>{{Cite book|...}}</ref> tags
#   2. Author-date {{sfn}} with full entries in Sources/Works Cited sections
#   3. Mixed (both in the same article)

# Ported from ~/Dropbox/R/wiki-graph/wiki-refs-to-zotero.R (2026-11-06) so the
# ice-detention pipeline can use it without a cross-project source() call.
# Header adapted: individual tidyverse packages instead of the meta-package,
# which is not part of this project's renv library.

library(dplyr)
library(stringr)
library(tidyr)
library(purrr)
library(tibble)
library(stringi)
library(httr2)
library(c2z)

# =============================================================================
# 1. Fetch wikitext
# =============================================================================

#' Fetch the wikitext source of a Wikipedia page.
#'
#' Calls the MediaWiki \code{parse} API directly via \pkg{httr2} and returns
#' the raw wikitext string.  Uses \code{formatversion=2} so the wikitext is
#' returned as a plain string (no \code{$`*`} wrapper).  Note that this
#' function always hits the network — there is no local cache.
#'
#' This implementation has no dependency on \pkg{WikipediR} and works in
#' browser-based WebR/Shinylive environments where Wikipedia's CORS headers
#' permit the request.
#'
#' @param page_name Page title as it appears in the URL
#'   (e.g. \code{"Human_genetic_variation"}).  Spaces may be written as
#'   underscores or left as literal spaces.
#' @param language Two-letter language code for the Wikipedia edition.
#'   Default \code{"en"}.
#' @param project MediaWiki project name.  Default \code{"wikipedia"}.
#' @return A single character string containing the raw wikitext of the page.
#' @examples
#' \dontrun{
#' wikitext <- fetch_wikitext("Meiō_incident")
#' }
fetch_wikitext <- function(page_name, language = "en", project = "wikipedia") {
  # Retry on 429 (burst rate limit) / 503, honoring Retry-After.
  # Only wait out the penalty once per article — the resumable cache makes
  # deferred retries cheap, and repeated in-request retries just re-trigger
  # the limiter.
  .retry_on_429 <- function(req) {
    req_retry(
      req,
      max_tries    = 2,
      is_transient = \(r) resp_status(r) %in% c(429, 503),
      after        = \(r) {
        val <- resp_header(r, "Retry-After")
        if (!is.null(val)) as.numeric(val) else 5
      }
    )
  }

  # MediaWiki REST API first (much more generous rate limits than api.php);
  # fall back to the classic action API if REST fails.
  rest <- request(paste0("https://", language, ".", project,
                         ".org/w/rest.php/v1/page/",
                         URLencode(page_name, reserved = TRUE))) |>
    req_user_agent("ice-detention-research/1.0 (academic research)") |>
    req_error(is_error = \(r) FALSE) |>
    .retry_on_429() |>
    req_perform()

  if (resp_status(rest) == 200L) {
    return(resp_body_json(rest)$source)
  }

  resp <- request(paste0("https://", language, ".", project, ".org/w/api.php")) |>
    req_url_query(
      action        = "parse",
      page          = page_name,
      prop          = "wikitext",
      format        = "json",
      formatversion = "2"
    ) |>
    req_error(is_error = \(r) FALSE) |>
    .retry_on_429() |>
    req_perform()

  if (resp_status(resp) != 200L) {
    stop("MediaWiki API returned HTTP ", resp_status(resp), " for: ", page_name)
  }

  body <- resp_body_json(resp)

  if (!is.null(body$error)) {
    stop("MediaWiki API error (", body$error$code, "): ", body$error$info)
  }

  body$parse$wikitext   # formatversion=2 returns a plain string
}

# =============================================================================
# 2. Template parser
# =============================================================================

#' Find the closing \code{\}\}} for a wikitext template.
#'
#' Scans \code{text} from character position \code{start}, tracking brace depth
#' to correctly handle nested templates, and returns the position immediately
#' after the matching \code{\}\}}.
#'
#' @param text The full wikitext string.
#' @param start Integer; position of the first \code{\{} of the opening
#'   \code{\{\{}.
#' @return Integer position of the character immediately after the closing
#'   \code{\}\}}, or \code{NA_integer_} if the braces are unmatched.
#' @keywords internal
find_template_end <- function(text, start) {
  n <- nchar(text)
  depth <- 0
  i <- start
  while (i <= n) {
    ch <- substr(text, i, i)
    ch2 <- substr(text, i, i + 1)
    if (ch2 == "{{") {
      depth <- depth + 1
      i <- i + 2
    } else if (ch2 == "}}") {
      depth <- depth - 1
      if (depth == 0) return(i + 1) # position of char after `}}`
      i <- i + 2
    } else {
      i <- i + 1
    }
  }
  NA_integer_ # unmatched
}

#' Extract top-level wikitext templates matching a regex pattern.
#'
#' Finds all occurrences of \code{pattern} in \code{text}, then uses
#' \code{\link{find_template_end}} to locate the matching closing \code{\}\}}
#' for each, correctly handling nested templates.
#'
#' @param text Wikitext string to search.
#' @param pattern Regular expression matched against the opening of each
#'   template.  Default matches any \code{\{\{Cite }} or \code{\{\{cite }}
#'   variant.
#' @return Character vector of complete template strings, each including the
#'   outer \code{\{\{} and \code{\}\}}.
#' @keywords internal
extract_templates <- function(text, pattern = "\\{\\{\\s*[Cc]ite\\s") {
  matches <- gregexpr(pattern, text, perl = TRUE, ignore.case = TRUE)[[1]]
  if (matches[1] == -1) return(character(0))

  # For each match, find the `{{` that starts just before
  templates <- character(length(matches))
  for (idx in seq_along(matches)) {
    pos <- matches[idx]
    # Walk back to find the opening `{{`
    start <- pos
    end_pos <- find_template_end(text, start)
    if (is.na(end_pos)) next
    templates[idx] <- substr(text, start, end_pos)
  }
  templates[nzchar(templates)]
}

#' Parse a wikitext template string into a named list.
#'
#' Splits the template on top-level \code{|} delimiters (ignoring pipes inside
#' nested \code{\{\{\}\}} or \code{[[\,]]} structures) and parses each
#' \code{key = value} pair into a named list element.  The template name is
#' stored as \code{.template} (lowercased).  Positional (unnamed) parameters
#' are stored as \code{.unnamed_1}, \code{.unnamed_2}, etc.
#'
#' @param template_str A single complete template string, e.g.
#'   \code{"\{\{Cite book|last=Smith|first=J.|year=2020\}\}"}.
#' @return A named list.  Always includes \code{.template} (character).  All
#'   other keys correspond to template parameter names (lowercased).
#' @keywords internal
parse_template_params <- function(template_str) {
  # Strip outer {{ and }}
  inner <- sub("^\\{\\{\\s*", "", template_str)
  inner <- sub("\\s*\\}\\}$", "", inner)

  # The template name is everything before the first `|`
  # But we need to handle nested templates in default/unnamed params
  # Strategy: split on `|` only at depth 0

  chars <- strsplit(inner, "")[[1]]
  n <- length(chars)
  brace_depth  <- 0L  # depth inside {{ }}
  bracket_depth <- 0L  # depth inside [[ ]]
  parts <- character(0)
  current <- ""

  for (i in seq_len(n)) {
    ch <- chars[i]
    ch_prev <- if (i > 1) chars[i - 1] else ""
    ch_next <- if (i < n) chars[i + 1] else ""

    if      (ch == "{" && ch_next == "{") { brace_depth  <- brace_depth  + 1L; current <- paste0(current, ch)
    } else if (ch == "{" && ch_prev == "{") {                                    current <- paste0(current, ch)
    } else if (ch == "}" && ch_next == "}") { brace_depth  <- brace_depth  - 1L; current <- paste0(current, ch)
    } else if (ch == "}" && ch_prev == "}") {                                    current <- paste0(current, ch)
    } else if (ch == "[" && ch_next == "[") { bracket_depth <- bracket_depth + 1L; current <- paste0(current, ch)
    } else if (ch == "[" && ch_prev == "[") {                                    current <- paste0(current, ch)
    } else if (ch == "]" && ch_next == "]") { bracket_depth <- bracket_depth - 1L; current <- paste0(current, ch)
    } else if (ch == "]" && ch_prev == "]") {                                    current <- paste0(current, ch)
    } else if (ch == "|" && brace_depth == 0L && bracket_depth == 0L) {
      parts <- c(parts, current)
      current <- ""
    } else {
      current <- paste0(current, ch)
    }
  }
  parts <- c(parts, current)

  template_name <- trimws(parts[1])
  params <- parts[-1]

  # Parse key=value pairs
  result <- list(.template = tolower(template_name))
  unnamed_idx <- 1
  for (p in params) {
    p <- trimws(p)
    if (p == "") next
    eq_pos <- regexpr("=", p, fixed = TRUE)
    if (eq_pos > 0) {
      key <- trimws(substr(p, 1, eq_pos - 1))
      val <- trimws(substr(p, eq_pos + 1, nchar(p)))
      result[[tolower(key)]] <- val
    } else {
      result[[paste0(".unnamed_", unnamed_idx)]] <- p
      unnamed_idx <- unnamed_idx + 1
    }
  }
  result
}

# =============================================================================
# 3. Extract all citation templates from wikitext
# =============================================================================

# Citation template names we recognize
cite_patterns <- c(
  "cite book", "cite journal", "cite web", "cite news",
  "cite encyclopedia", "cite odnb", "cite magazine", "cite thesis",
  "cite conference", "cite report", "cite press release",
  "cite av media", "cite podcast", "cite speech",
  "Citation",
  "Cite EB1911",
  "harvc"
)

#' Extract all recognised citation templates from wikitext.
#'
#' Scans the wikitext for any of the supported Wikipedia citation template
#' names: Cite book, Cite journal, Cite web, Cite news, Cite encyclopedia,
#' Cite magazine, Cite thesis, Cite conference, Cite report, Cite press
#' release, Cite av media, Cite podcast, Cite speech, and harvc.
#'
#' @param wikitext Raw wikitext string as returned by
#'   \code{\link{fetch_wikitext}}.
#' @return Character vector of complete template strings (each including
#'   its outer \code{\{\{} and \code{\}\}}).
#' @keywords internal
extract_all_citations <- function(wikitext) {
  # Pattern matches {{Cite book, {{cite journal, {{harvc, etc.
  # Case insensitive
  pattern <- paste0(
    "\\{\\{\\s*(",
    paste(gsub(" ", "\\\\s+", cite_patterns), collapse = "|"),
    ")\\s*\\|"
  )
  extract_templates(wikitext, pattern)
}

#' Extract \code{<ref>} contents that contain no citation template.
#'
#' Finds all \code{<ref>...</ref>} blocks whose content does not include a
#' \code{\{\{Cite }} template.  These are typically plain-text footnotes or
#' explanatory notes rather than bibliographic references.
#'
#' @param wikitext Raw wikitext string.
#' @return Character vector of raw (untemplated) \code{<ref>} content strings.
#' @keywords internal
extract_bare_refs <- function(wikitext) {
  # Find all <ref...>...</ref> blocks
  ref_pattern <- "<ref[^>]*>(.*?)</ref>"
  refs <- str_match_all(wikitext, regex(ref_pattern, dotall = TRUE))[[1]]
  if (nrow(refs) == 0) return(character(0))

  ref_contents <- refs[, 2]
  # Filter to those that don't contain a recognised citation template
  is_bare <- !str_detect(ref_contents, regex("\\{\\{\\s*(cite\\s|citation\\s*\\|)", ignore_case = TRUE))
  ref_contents[is_bare & nzchar(trimws(ref_contents))]
}

# =============================================================================
# 4. Map parsed templates → reference tibble
# =============================================================================

#' Strip Wikipedia markup from a string.
#'
#' Removes or unwraps common wikitext constructs:
#' \itemize{
#'   \item \code{[[Link|Display]]} and \code{[[Display]]} wikilinks →
#'     display text only
#'   \item \code{''italic''} → plain text
#'   \item Inline display templates \code{\{\{Name|arg|display\}\}} →
#'     display text
#'   \item Remaining bare templates → empty string
#'   \item \code{\{\{!\}\}} and \code{\{\{=\}\}} escape sequences →
#'     literal \code{|} and \code{=}
#' }
#'
#' @param x A character string, or \code{NULL}.
#' @return A trimmed character string, or \code{NA_character_} if the input is
#'   \code{NULL} or blank after stripping.
#' @keywords internal
clean_wiki <- function(x) {
  if (is.null(x) || !nzchar(trimws(x))) return(NA_character_)
  x <- str_replace_all(x, "\\{\\{!\\}\\}", "|")          # {{!}} → literal pipe
  x <- str_replace_all(x, "\\{\\{=\\}\\}", "=")          # {{=}} → literal equals
  # Inline display templates: {{Name|arg1|display text|...}} → display text (2nd positional arg)
  # If no 2nd positional arg, try 1st; if none, strip entirely.
  x <- str_replace_all(x,
    "\\{\\{[^|{}]+\\|[^|{}]+\\|([^|{}]+)(?:\\|[^{}]*)?\\}\\}",
    "\\1")
  x <- str_replace_all(x,
    "\\{\\{[^|{}]+\\|([^|{}]+)\\}\\}",
    "\\1")
  x <- str_replace_all(x, "\\{\\{[^{}]*\\}\\}", "")      # remaining bare templates
  x <- str_replace_all(x, "\\[\\[([^\\]|]+\\|)?([^\\]]+)\\]\\]", "\\2")  # wikilinks
  x <- str_replace_all(x, "''", "")                       # italic markup
  trimws(x)
}

#' Map a Wikipedia citation template name to a Zotero item type.
#'
#' @param tpl_name Character; template name as stored in \code{.template}
#'   (already lowercased by \code{\link{parse_template_params}}).
#' @return One of the Zotero item type strings: \code{"book"},
#'   \code{"bookSection"}, \code{"journalArticle"}, \code{"webpage"},
#'   \code{"newspaperArticle"}, \code{"encyclopediaArticle"},
#'   \code{"magazineArticle"}, \code{"thesis"}, \code{"conferencePaper"},
#'   \code{"report"}, \code{"videoRecording"}, or \code{"document"}.
#' @keywords internal
template_to_itemtype <- function(tpl_name, params = NULL) {
  tpl <- tolower(trimws(tpl_name))
  case_when(
    str_detect(tpl, "^(cite )?book$") ~ "book",
    str_detect(tpl, "harvc")          ~ "bookSection",
    str_detect(tpl, "journal")        ~ "journalArticle",
    str_detect(tpl, "web")            ~ "webpage",
    str_detect(tpl, "news")           ~ "newspaperArticle",
    str_detect(tpl, "encyclopedia")   ~ "encyclopediaArticle",
    str_detect(tpl, "odnb")           ~ "encyclopediaArticle",
    str_detect(tpl, "eb1911")         ~ "encyclopediaArticle",
    str_detect(tpl, "magazine")       ~ "magazineArticle",
    str_detect(tpl, "thesis")         ~ "thesis",
    str_detect(tpl, "conference")     ~ "conferencePaper",
    str_detect(tpl, "report")         ~ "report",
    str_detect(tpl, "press release")  ~ "newspaperArticle",
    str_detect(tpl, "av media")       ~ "videoRecording",
    # {{Citation}} is generic: infer type from parameters
    str_detect(tpl, "^citation$")     ~ .citation_itemtype(params),
    TRUE                              ~ "document"
  )
}

# Infer item type for the generic {{Citation}} template based on which
# parameters are present.
.citation_itemtype <- function(params) {
  if (is.null(params)) return("book")
  has <- function(k) !is.null(params[[k]])
  if (has("chapter") || has("chapter-url")) "bookSection"
  else if (has("journal") || has("periodical")) "journalArticle"
  else if (has("newspaper")) "newspaperArticle"
  else if (has("magazine")) "magazineArticle"
  else if (has("encyclopedia")) "encyclopediaArticle"
  else "book"
}

#' Extract creator metadata from parsed template parameters.
#'
#' Handles Wikipedia's various author-naming conventions:
#' \code{last}/\code{first}, \code{last1}/\code{first1}, \ldots up to
#' \code{last10}/\code{first10}, as well as single-string \code{author=}
#' parameters.  Also extracts editors (\code{editor-last}/\code{editor-first})
#' and translators.
#'
#' @param params Named list as returned by \code{\link{parse_template_params}}.
#' @return A tibble with columns \code{creatorType} (\code{"author"},
#'   \code{"editor"}, or \code{"translator"}), \code{lastName}, and
#'   \code{firstName}.  Always has at least one row; uses empty strings for
#'   unknown names.
#' @keywords internal
extract_authors <- function(params) {
  authors <- tibble(creatorType = character(), lastName = character(), firstName = character())

  # Check for author/author1, last/first, last1/first1, ...
  # Also handle editor, translator
  for (role_prefix in c("", "editor", "translator")) {
    creator_type <- if (role_prefix == "") "author" else role_prefix

    # Wikipedia naming: last/first or last1/first1 etc.
    param_last <- if (role_prefix == "") "last" else paste0(role_prefix, "-last")
    param_first <- if (role_prefix == "") "first" else paste0(role_prefix, "-first")

    for (i in c("", as.character(1:10))) {
      lkey <- paste0(param_last, i)
      fkey <- paste0(param_first, i)

      # Also try lastN/firstN without hyphen for editors
      if (role_prefix != "" && is.null(params[[lkey]])) {
        lkey2 <- paste0(role_prefix, "-last", i)
        fkey2 <- paste0(role_prefix, "-first", i)
        if (!is.null(params[[lkey2]])) {
          lkey <- lkey2
          fkey <- fkey2
        }
      }

      last_val <- params[[lkey]]
      first_val <- params[[fkey]] %||% ""

      if (!is.null(last_val) && nzchar(last_val)) {
        authors <- bind_rows(authors, tibble(
          creatorType = creator_type,
          lastName  = clean_wiki(last_val)  %||% "",
          firstName = clean_wiki(first_val) %||% ""
        ))
      }
    }

    # Handle combined "author" param (single string)
    author_key <- if (role_prefix == "") "author" else role_prefix
    if (is.null(params[["last"]]) && is.null(params[["last1"]]) && !is.null(params[[author_key]])) {
      # Don't override if we already got last/first
      if (nrow(authors) == 0 || creator_type != "author") {
        val <- clean_wiki(params[[author_key]]) %||% params[[author_key]]
        # clean_wiki() can return NA for blank values — skip those
        if (!is.null(val) && !is.na(val) && nzchar(val)) {
        # Try to split "Last, First" or just use as lastName
        if (str_detect(val, ",")) {
          parts <- str_split(val, ",\\s*", n = 2)[[1]]
          authors <- bind_rows(authors, tibble(
            creatorType = creator_type, lastName = parts[1], firstName = parts[2] %||% ""
          ))
        } else {
          authors <- bind_rows(authors, tibble(
            creatorType = creator_type, lastName = val, firstName = ""
          ))
        }
        } # end !is.null(val) guard
      }
    }
  }

  # Handle "others" param (translators, illustrators, etc.)
  if (!is.null(params[["others"]]) && nzchar(params[["others"]])) {
    authors <- bind_rows(authors, tibble(
      creatorType = "contributor",
      lastName = params[["others"]],
      firstName = ""
    ))
  }

  if (nrow(authors) == 0) {
    authors <- tibble(creatorType = "author", lastName = "", firstName = "")
  }
  authors
}

#' Convert a parsed citation template to a one-row reference tibble.
#'
#' Maps template parameter names to the internal reference schema used
#' throughout this script.  Strips Wikipedia markup from string fields via
#' \code{\link{clean_wiki}}.  For \code{harvc} (book-section) templates, maps
#' \code{chapter} to title and \code{in} to \code{bookTitle}.  When both
#' \code{title} and \code{trans-title} are present, appends the translation in
#' brackets.
#'
#' @param params Named list as returned by \code{\link{parse_template_params}}.
#' @return A one-row tibble with columns \code{itemType}, \code{title},
#'   \code{creators}, \code{date}, \code{year}, \code{publisher}, \code{place},
#'   \code{publicationTitle}, \code{volume}, \code{issue}, \code{pages},
#'   \code{ISBN}, \code{ISSN}, \code{DOI}, \code{url}, \code{language},
#'   \code{edition}, \code{series}, \code{accessDate}, \code{bookTitle},
#'   \code{chapter}, \code{.template_name}, \code{.raw_template}.
#' @keywords internal
template_to_ref <- function(params) {
  item_type <- template_to_itemtype(params$.template, params)
  authors <- extract_authors(params)

  # Extract year from date field
  extract_year <- function(params) {
    yr <- params[["year"]] %||% params[["date"]]
    if (is.null(yr)) return(NA_character_)
    # Try to extract a 4-digit year
    m <- str_extract(yr, "\\d{4}")
    if (!is.na(m)) return(m)
    yr
  }

  # Helper: coalesce that treats NA as missing (unlike %||%)
  na_coalesce <- function(...) {
    args <- list(...)
    for (a in args) if (!is.na(a)) return(a)
    NA_character_
  }

  tpl_lower <- tolower(trimws(params$.template))

  # {{Cite EB1911}}: wstitle → title, fixed encyclopediaTitle
  if (str_detect(tpl_lower, "eb1911")) {
    title <- clean_wiki(params[["wstitle"]]) %||% NA_character_
    chapter <- NA_character_
    book_title <- "Encyclop\u00e6dia Britannica (11th ed.)"
  } else {
    # Title: prefer title, fall back to script-title (for Japanese etc.)
    title <- na_coalesce(clean_wiki(params[["title"]]), clean_wiki(params[["script-title"]]))
    # For script-title, strip the language prefix like "ja:"
    if (!is.na(title)) title <- str_remove(title, "^[a-z]{2}:")

    # Trans-title: use if present
    trans_title <- clean_wiki(params[["trans-title"]])
    if (!is.na(trans_title) && !is.na(title)) {
      title <- paste0(title, " [", trans_title, "]")
    }

    # Chapter (for harvc / bookSection / Citation with chapter=)
    chapter <- na_coalesce(clean_wiki(params[["chapter"]]), clean_wiki(params[["script-chapter"]]))
    if (!is.na(chapter)) chapter <- str_remove(chapter, "^[a-z]{2}:")

    # For bookSection, the chapter name is the item title and the book title
    # is the container.  Applies to harvc and {{Citation}} with chapter=.
    if (item_type == "bookSection" && !is.na(chapter)) {
      book_title <- title  # the {{Citation}} title= is the book
      title <- chapter
      chapter <- NA_character_
    } else if (item_type == "bookSection" && is.na(chapter) && is.na(title)) {
      book_title <- NA_character_
    } else {
      book_title <- if (item_type == "bookSection") {
        clean_wiki(params[["in"]]) %||% NA_character_
      } else NA_character_
    }
  }

  tibble(
    itemType         = item_type,
    title            = title %||% NA_character_,
    creators         = list(authors),
    date             = params[["date"]] %||% params[["year"]] %||% NA_character_,
    year             = extract_year(params),
    publisher        = clean_wiki(params[["publisher"]]) %||% NA_character_,
    place            = clean_wiki(params[["location"]]) %||% NA_character_,
    publicationTitle = clean_wiki(params[["journal"]] %||% params[["website"]] %||%
                                    params[["work"]] %||% params[["newspaper"]]) %||% NA_character_,
    volume           = params[["volume"]] %||% NA_character_,
    issue            = params[["issue"]] %||% NA_character_,
    pages            = params[["pages"]] %||% params[["page"]] %||%
                         params[["at"]] %||% NA_character_,
    ISBN             = params[["isbn"]] %||% NA_character_,
    ISSN             = params[["issn"]] %||% NA_character_,
    DOI              = params[["doi"]] %||% NA_character_,
    url              = params[["url"]] %||% params[["chapter-url"]] %||% NA_character_,
    language         = params[["language"]] %||% NA_character_,
    edition          = params[["edition"]] %||% NA_character_,
    series           = clean_wiki(params[["series"]]) %||% NA_character_,
    accessDate       = params[["access-date"]] %||% NA_character_,
    bookTitle        = book_title %||% NA_character_,
    chapter          = chapter %||% NA_character_,
    # Raw template for debugging
    .template_name   = params$.template,
    .raw_template    = NA_character_
  )
}

# =============================================================================
# 5. Build reference data frame from wikitext
# =============================================================================

#' Extract all citations from a wikitext string into a reference tibble.
#'
#' Combines \code{\link{extract_all_citations}} (template-based references) and
#' \code{\link{extract_bare_refs}} (plain \code{<ref>} notes), parses each
#' template, and adds a convenience \code{first_author} column for inspection.
#' Issues a warning if no citation templates are found.
#'
#' @param wikitext Raw wikitext string as returned by
#'   \code{\link{fetch_wikitext}}.
#' @return A tibble with one row per citation template found.  Columns follow
#'   the schema described in \code{\link{template_to_ref}}, plus
#'   \code{first_author} (character, for display only).
#' @examples
#' \dontrun{
#' wikitext <- fetch_wikitext("Meiō_incident")
#' refs_raw <- extract_refs_from_wikitext(wikitext)
#' }
extract_refs_from_wikitext <- function(wikitext) {
  # Extract all citation templates
  cite_strings <- extract_all_citations(wikitext)

  if (length(cite_strings) == 0) {
    warning("No citation templates found in wikitext.")
    return(tibble())
  }

  # Parse each template
  parsed <- map(cite_strings, parse_template_params)

  # Convert to tibble rows
  refs <- map2_dfr(parsed, cite_strings, function(params, raw) {
    ref <- template_to_ref(params)
    ref$.raw_template <- raw
    ref
  })

  # Extract bare refs (non-template)
  bare <- extract_bare_refs(wikitext)
  if (length(bare) > 0) {
    bare_df <- tibble(
      itemType = "document",
      title = map_chr(bare, clean_wiki),
      creators = map(bare, ~ tibble(creatorType = "author", lastName = "", firstName = "")),
      date = NA_character_, year = NA_character_, publisher = NA_character_,
      place = NA_character_, publicationTitle = NA_character_,
      volume = NA_character_, issue = NA_character_, pages = NA_character_,
      ISBN = NA_character_, ISSN = NA_character_, DOI = NA_character_,
      url = NA_character_, language = NA_character_, edition = NA_character_,
      series = NA_character_, accessDate = NA_character_,
      bookTitle = NA_character_, chapter = NA_character_,
      .template_name = "bare_ref", .raw_template = bare
    )
    refs <- bind_rows(refs, bare_df)
  }

  # Add human-readable first_author for visual inspection (not used downstream)
  refs |>
    mutate(
      first_author = map_chr(creators, function(cr) {
        if (nrow(cr) == 0) return(NA_character_)
        last  <- cr$lastName[1]  %||% ""
        first <- cr$firstName[1] %||% ""
        if (!nzchar(last) && !nzchar(first)) return(NA_character_)
        if (nzchar(first)) paste0(last, ", ", first) else last
      }),
      .before = creators
    )
}

# =============================================================================
# 6. Deduplication
# =============================================================================

#' Build a normalised deduplication key for a reference.
#'
#' Concatenates the first author's last name, publication year, and title after
#' lowercasing, stripping diacritics (via \pkg{stringi}), and removing all
#' non-alphanumeric characters.
#'
#' @param title Character; reference title.
#' @param year  Character; four-digit year string, or \code{NA}.
#' @param last1 Character; first author's last name, or \code{NA}.
#' @return A character string of the form \code{"lastname|year|title"}.
#' @keywords internal
dedup_key <- function(title, year, last1) {
  # Normalize: decode HTML entities, lowercase, strip diacritics,
  # strip punctuation, collapse whitespace
  norm <- function(x) {
    x <- x %||% ""
    x <- str_replace_all(x, "&nbsp;", " ")
    x <- str_replace_all(x, "&#\\d+;", " ")
    x <- tolower(x)
    x <- stri_trans_general(x, "Latin-ASCII")
    x <- str_replace_all(x, "[^a-z0-9 ]", "")
    str_squish(x)
  }
  paste(norm(last1), norm(year), norm(title), sep = "|")
}

#' Remove duplicate citations from a reference tibble.
#'
#' References sharing the same \code{\link{dedup_key}} (normalised last name +
#' year + title) are considered duplicates.  The first occurrence is retained
#' and a \code{n_citations} column records how many times that reference
#' appeared in the wikitext.
#'
#' @param refs A tibble as returned by \code{\link{extract_refs_from_wikitext}}.
#' @return The deduplicated tibble with two extra columns: \code{.dedup_key}
#'   (character) and \code{n_citations} (integer).
deduplicate_refs <- function(refs) {
  refs <- refs |>
    mutate(
      .last1 = map_chr(creators, ~ .x$lastName[1]),
      .dedup_key = dedup_key(title, year, .last1)
    )

  # Group by dedup key, keep first occurrence, count citations
  refs |>
    group_by(.dedup_key) |>
    mutate(n_citations = n()) |>
    slice(1) |>
    ungroup()
}

# =============================================================================
# 7. RIS export  (uses enriched refs if enrichment has been run)
# =============================================================================

#' Convert a Zotero item type string to a RIS type code.
#'
#' @param it Character; a Zotero item type such as \code{"book"} or
#'   \code{"journalArticle"}.
#' @return A RIS \code{TY} code string.  Unrecognised types return
#'   \code{"GEN"}.
#' @keywords internal
itemtype_to_ris <- function(it) {
  switch(it,
    "book"                = "BOOK",
    "bookSection"         = "CHAP",
    "journalArticle"      = "JOUR",
    "webpage"             = "ELEC",
    "newspaperArticle"    = "NEWS",
    "encyclopediaArticle" = "ENCYC",
    "magazineArticle"     = "MGZN",
    "thesis"              = "THES",
    "conferencePaper"     = "CONF",
    "report"              = "RPRT",
    "videoRecording"      = "VIDEO",
    "document"            = "GEN",
    "GEN"
  )
}

#' Serialise one reference row to RIS-format lines.
#'
#' Produces a character vector of \code{TAG  - value} lines (plus a closing
#' \code{ER  - } record) suitable for writing to a \code{.ris} file.
#' Page ranges with an en-dash or hyphen are split into \code{SP}/\code{EP}
#' tags.
#'
#' @param row A one-row tibble from a refs data frame.
#' @return Character vector of RIS lines for this reference.
#' @keywords internal
ref_to_ris_lines <- function(row) {
  lines <- character(0)
  add <- function(tag, val) {
    if (!is.na(val) && nzchar(val)) {
      lines <<- c(lines, paste0(tag, "  - ", val))
    }
  }

  add("TY", itemtype_to_ris(row$itemType))
  add("TI", row$title)

  # Authors
  for (i in seq_len(nrow(row$creators[[1]]))) {
    cr <- row$creators[[1]][i, ]
    name <- if (nzchar(cr$firstName)) {
      paste0(cr$lastName, ", ", cr$firstName)
    } else {
      cr$lastName
    }
    tag <- switch(cr$creatorType,
      "editor" = "ED",
      "translator" = "A3",
      "AU"
    )
    if (nzchar(name)) add(tag, name)
  }

  add("PY", row$year)
  add("DA", row$date)
  add("PB", row$publisher)
  add("CY", row$place)
  add("JO", row$publicationTitle)
  add("T2", row$publicationTitle)
  add("VL", row$volume)
  add("IS", row$issue)

  # Pages: try to split "123–456" into SP/EP
  if (!is.na(row$pages)) {
    pg <- str_split(row$pages, "[–—-]", n = 2)[[1]]
    add("SP", trimws(pg[1]))
    if (length(pg) > 1) add("EP", trimws(pg[2]))
  }

  add("SN", row$ISBN)
  add("SN", row$ISSN)
  add("DO", row$DOI)
  add("UR", row$url)
  add("LA", row$language)
  add("ET", row$edition)
  add("T3", row$series)
  add("Y2", row$accessDate)

  if (row$itemType == "bookSection") {
    add("BT", row$bookTitle)
    add("T2", row$chapter)
  }

  lines <- c(lines, "ER  - ")
  lines
}

#' Write a reference tibble to a RIS file.
#'
#' Converts each row to RIS format via \code{\link{ref_to_ris_lines}} and
#' writes all records to \code{file}, separated by blank lines.
#'
#' @param refs A refs tibble (e.g. from \code{\link{deduplicate_refs}} or
#'   \code{\link{enrich_refs}}).
#' @param file Path to the output \code{.ris} file.  Created or overwritten.
#' @return \code{NULL}, invisibly.  Emits a message with the count of
#'   references written.
#' @examples
#' \dontrun{
#' refs <- wiki_refs_pipeline("Meiō_incident", enrich = FALSE)
#' export_ris(refs, "meio_incident.ris")
#' }
export_ris <- function(refs, file) {
  all_lines <- character(0)
  for (i in seq_len(nrow(refs))) {
    all_lines <- c(all_lines, ref_to_ris_lines(refs[i, ]), "")
  }
  writeLines(all_lines, file)
  message("Wrote ", nrow(refs), " references to ", file)
}

# =============================================================================
# 8. DOI / ISBN enrichment via c2z
# =============================================================================

#' Merge metadata from a c2z enrichment result into a ref row.
#'
#' Prefers non-empty values from \code{enriched_row} (a row of the
#' \code{$data} tibble returned by \code{ZoteroDoi} or \code{ZoteroIsbn})
#' over the wiki-parsed values in \code{ref_row}, falling back to the wiki
#' value for any field the enriched source leaves blank.
#'
#' @param ref_row One-row tibble from the refs data frame.
#' @param enriched_row One-row tibble from a c2z \code{$data} result.
#' @return The updated \code{ref_row} with enriched fields overlaid.
#' @keywords internal
.merge_enriched <- function(ref_row, enriched_row) {
  prefer <- function(new_val, old_val) {
    new_str <- if (is.null(new_val) || length(new_val) == 0) NA_character_
               else as.character(new_val[[1]])
    old_str <- if (is.null(old_val) || length(old_val) == 0) NA_character_
               else as.character(old_val[[1]])
    if (!is.na(new_str) && nzchar(new_str)) new_str else old_str
  }

  # Use [[ rather than $ to silently return NULL for columns absent from enriched_row
  # (item-type-specific columns like publicationTitle don't exist on book rows, etc.)
  ecol <- function(col) enriched_row[[col]]

  # creators: prefer enriched if it has at least one real author
  new_creators <- ecol("creators")[[1]]
  old_creators <- ref_row$creators[[1]]
  use_creators <- if (!is.null(new_creators) && nrow(new_creators) > 0 &&
                      any(nzchar(new_creators$lastName %||% ""))) {
    new_creators
  } else {
    old_creators
  }

  ref_row$itemType         <- prefer(ecol("itemType"),         ref_row$itemType)
  ref_row$title            <- prefer(ecol("title"),            ref_row$title)
  ref_row$creators         <- list(use_creators)
  ref_row$date             <- prefer(ecol("date"),             ref_row$date)
  ref_row$year             <- prefer(
    list(str_extract(as.character(ecol("date") %||% ""), "\\d{4}")),
    ref_row$year
  )
  ref_row$publisher        <- prefer(ecol("publisher"),        ref_row$publisher)
  ref_row$place            <- prefer(ecol("place"),            ref_row$place)
  ref_row$publicationTitle <- prefer(ecol("publicationTitle"), ref_row$publicationTitle)
  ref_row$volume           <- prefer(ecol("volume"),           ref_row$volume)
  ref_row$issue            <- prefer(ecol("issue"),            ref_row$issue)
  ref_row$ISBN             <- prefer(ecol("ISBN"),             ref_row$ISBN)
  ref_row$ISSN             <- prefer(ecol("ISSN"),             ref_row$ISSN)
  ref_row$DOI              <- prefer(ecol("DOI"),              ref_row$DOI)
  ref_row$url              <- prefer(ecol("url"),              ref_row$url)
  ref_row$language         <- prefer(ecol("language"),         ref_row$language)
  ref_row$edition          <- prefer(ecol("edition"),          ref_row$edition)
  ref_row$accessDate       <- prefer(ecol("accessDate"),       ref_row$accessDate)

  ref_row
}

#' Enrich a single reference row via DOI or ISBN lookup.
#'
#' Attempts a DOI lookup first (via \code{c2z::ZoteroDoi}), then falls back to
#' an ISBN lookup (via \code{c2z::ZoteroIsbn}).  On success, overlays the
#' richer metadata using \code{\link{.merge_enriched}}.
#'
#' @param ref_row A one-row tibble from the refs data frame.
#' @return The same row with fields updated where enrichment succeeded, plus a
#'   new character column \code{.enrich_status}: \code{"doi"}, \code{"isbn"},
#'   \code{"failed"} (identifier present but lookup returned no data), or
#'   \code{"skipped"} (no DOI or ISBN present).
#' @keywords internal
enrich_ref <- function(ref_row) {
  doi  <- ref_row$DOI
  isbn <- ref_row$ISBN

  # Skip if neither identifier is present
  if ((is.na(doi) || !nzchar(doi)) && (is.na(isbn) || !nzchar(isbn))) {
    ref_row$.enrich_status <- "skipped"
    return(ref_row)
  }

  # Try DOI first
  if (!is.na(doi) && nzchar(doi)) {
    result <- tryCatch(
      ZoteroDoi(doi, silent = TRUE),
      error = function(e) NULL
    )
    if (!is.null(result) && is.data.frame(result[["data"]]) && NROW(result[["data"]]) > 0) {
      ref_row <- .merge_enriched(ref_row, result[["data"]][1, ])
      ref_row$.enrich_status <- "doi"
      return(ref_row)
    }
  }

  # Fall back to ISBN
  if (!is.na(isbn) && nzchar(isbn)) {
    result <- tryCatch(
      ZoteroIsbn(isbn, silent = TRUE),
      error = function(e) NULL
    )
    if (!is.null(result) && is.data.frame(result[["data"]]) && NROW(result[["data"]]) > 0) {
      ref_row <- .merge_enriched(ref_row, result[["data"]][1, ])
      ref_row$.enrich_status <- "isbn"
      return(ref_row)
    }
  }

  ref_row$.enrich_status <- "failed"
  ref_row
}

#' Enrich all references in a tibble via DOI and ISBN lookups.
#'
#' Iterates over every row, calling \code{\link{enrich_ref}} for each, with a
#' progress bar.  Emits a summary message showing how many references were
#' enriched via DOI, ISBN, failed, or skipped.
#'
#' @param refs A refs tibble (e.g. from \code{\link{deduplicate_refs}}).
#' @return The same tibble with enriched field values where lookups succeeded,
#'   and a new \code{.enrich_status} column added.
#' @seealso \code{\link{enrich_ref}}
enrich_refs <- function(refs) {
  n_doi  <- sum(!is.na(refs$DOI)  & nzchar(refs$DOI  %||% ""), na.rm = TRUE)
  n_isbn <- sum(!is.na(refs$ISBN) & nzchar(refs$ISBN %||% ""), na.rm = TRUE)
  message("Enriching via c2z: ", n_doi, " DOI(s), ", n_isbn, " ISBN(s) to look up")

  enriched <- map(
    seq_len(nrow(refs)),
    \(i) enrich_ref(refs[i, ]),
    .progress = list(
      type  = "iterator",
      name  = "Enriching references",
      clear = FALSE
    )
  )

  result <- bind_rows(enriched)

  tab <- table(result$.enrich_status)
  get_n <- function(k) if (!is.na(tab[k])) tab[k] else 0L
  message(sprintf(
    "Enrichment: %d via DOI, %d via ISBN, %d failed, %d skipped (no identifier)",
    get_n("doi"), get_n("isbn"), get_n("failed"), get_n("skipped")
  ))

  result
}

# =============================================================================
# 10. Zotero import
# =============================================================================

#' Format an access date string for the Zotero API.
#'
#' Attempts to parse common date formats (\code{"\%d \%B \%Y"},
#' \code{"\%B \%d, \%Y"}, \code{"\%Y-\%m-\%d"}, \code{"\%Y/\%m/\%d"}) and
#' returns the result in ISO 8601 (\code{YYYY-MM-DD}) format, as required by
#' the Zotero REST API.
#'
#' @param x Character; raw access-date string from a citation template.
#' @return An ISO 8601 date string, or \code{""} if \code{x} is \code{NA},
#'   blank, or cannot be parsed.
#' @keywords internal
.format_access_date <- function(x) {
  if (is.na(x) || !nzchar(x)) return("")
  fmts <- c("%d %B %Y", "%B %d, %Y", "%Y-%m-%d", "%Y/%m/%d")
  for (fmt in fmts) {
    d <- tryCatch(as.Date(x, format = fmt), error = function(e) NA)
    if (!is.na(d)) return(format(d, "%Y-%m-%d"))
  }
  "" # can't parse — omit rather than send a bad value
}

#' Convert one ref row to a Zotero API item tibble.
#'
#' Builds a tibble whose column names and field semantics match the Zotero REST
#' API for the specific \code{itemType} of the reference.  Key schema
#' differences from the internal ref schema:
#' \itemize{
#'   \item \code{book} and \code{thesis}: \code{pages} → \code{numPages}
#'   \item \code{webpage}: \code{publicationTitle} → \code{websiteTitle}
#'   \item \code{encyclopediaArticle}: \code{publicationTitle} →
#'     \code{encyclopediaTitle}
#'   \item \code{thesis}: \code{publisher} → \code{university}
#'   \item \code{report}: \code{publisher} → \code{institution}
#'   \item \code{conferencePaper}: \code{publicationTitle} →
#'     \code{proceedingsTitle}
#' }
#' A fresh Zotero item key is generated via \code{c2z::ZoteroKey()}.
#'
#' @param row A one-row tibble from the refs data frame.
#' @return A one-row tibble formatted for the Zotero REST API.
#' @keywords internal
ref_to_zotero_item <- function(row) {
  acc <- .format_access_date(row$accessDate %||% "")


  # Convert creators to a list-of-lists for the Zotero API.  Creators with a
  # non-empty firstName get {creatorType, lastName, firstName}; those without
  # (institutional authors) get {creatorType, name} — the two formats are
  # mutually exclusive per the API spec.
  creators_tbl <- row$creators[[1]]
  creators <- if (!is.null(creators_tbl) && nrow(creators_tbl) > 0) {
    lapply(seq_len(nrow(creators_tbl)), \(j) {
      cr <- creators_tbl[j, ]
      if (nzchar(cr$firstName)) {
        list(creatorType = cr$creatorType, lastName = cr$lastName, firstName = cr$firstName)
      } else {
        list(creatorType = cr$creatorType, name = cr$lastName)
      }
    })
  } else {
    list(list(creatorType = "author", name = ""))
  }

  # Fields present on every item type
  base <- list(
    key        = ZoteroKey(),
    version    = 0L,
    itemType   = row$itemType,
    title      = row$title    %||% "",
    creators   = list(creators),
    date       = row$date     %||% "",
    language   = row$language %||% "",
    url        = row$url      %||% "",
    accessDate = acc
  )

  # Type-specific fields (only include what the API allows for each type)
  extra <- switch(row$itemType,

    book = list(
      publisher = row$publisher %||% "",
      place     = row$place     %||% "",
      ISBN      = row$ISBN      %||% "",
      ISSN      = row$ISSN      %||% "",   # added: now valid for books
      DOI       = row$DOI       %||% "",   # added: now valid for books
      edition   = row$edition   %||% "",
      series    = row$series    %||% "",
      volume    = row$volume    %||% "",
      numPages  = row$pages     %||% ""    # pages → numPages for books
    ),

    bookSection = list(
      bookTitle = row$bookTitle %||% "",
      publisher = row$publisher %||% "",
      place     = row$place     %||% "",
      ISBN      = row$ISBN      %||% "",
      ISSN      = row$ISSN      %||% "",   # added
      DOI       = row$DOI       %||% "",   # added
      pages     = row$pages     %||% "",
      edition   = row$edition   %||% "",
      series    = row$series    %||% "",
      volume    = row$volume    %||% ""
    ),

    journalArticle = list(
      publicationTitle = row$publicationTitle %||% "",
      volume           = row$volume           %||% "",
      issue            = row$issue            %||% "",
      pages            = row$pages            %||% "",
      DOI              = row$DOI              %||% "",
      ISSN             = row$ISSN             %||% "",
      series           = row$series           %||% ""
    ),

    webpage = list(
      websiteTitle = row$publicationTitle %||% "",  # publicationTitle → websiteTitle
      publisher    = row$publisher        %||% "",  # added
      place        = row$place            %||% "",  # added
      DOI          = row$DOI              %||% ""   # added
    ),

    newspaperArticle = list(
      publicationTitle = row$publicationTitle %||% "",
      publisher        = row$publisher        %||% "",  # added
      place            = row$place            %||% "",
      volume           = row$volume           %||% "",  # added
      issue            = row$issue            %||% "",  # added
      edition          = row$edition          %||% "",  # added
      pages            = row$pages            %||% "",
      ISSN             = row$ISSN             %||% "",
      DOI              = row$DOI              %||% ""   # added
    ),

    encyclopediaArticle = list(
      encyclopediaTitle = row$publicationTitle %||% "",  # publicationTitle → encyclopediaTitle
      publisher         = row$publisher        %||% "",
      place             = row$place            %||% "",
      ISBN              = row$ISBN             %||% "",
      DOI               = row$DOI              %||% "",  # added
      pages             = row$pages            %||% "",
      edition           = row$edition          %||% "",
      series            = row$series           %||% "",
      volume            = row$volume           %||% ""
    ),

    magazineArticle = list(
      publicationTitle = row$publicationTitle %||% "",
      publisher        = row$publisher        %||% "",  # added
      place            = row$place            %||% "",  # added
      volume           = row$volume           %||% "",
      issue            = row$issue            %||% "",
      pages            = row$pages            %||% "",
      ISSN             = row$ISSN             %||% "",
      DOI              = row$DOI              %||% ""   # added
    ),

    thesis = list(
      university = row$publisher %||% "",   # publisher → university for theses
      place      = row$place     %||% "",
      numPages   = row$pages     %||% "",
      DOI        = row$DOI       %||% "",   # added
      ISBN       = row$ISBN      %||% "",   # added
      ISSN       = row$ISSN      %||% "",   # added
      series     = row$series    %||% ""    # added
    ),

    conferencePaper = list(
      proceedingsTitle = row$publicationTitle %||% "",  # publicationTitle → proceedingsTitle
      publisher        = row$publisher        %||% "",
      place            = row$place            %||% "",
      pages            = row$pages            %||% "",
      volume           = row$volume           %||% "",
      DOI              = row$DOI              %||% "",
      ISBN             = row$ISBN             %||% "",
      ISSN             = row$ISSN             %||% "",  # added
      series           = row$series           %||% ""
    ),

    report = list(
      institution = row$publisher %||% "",  # publisher → institution for reports
      place       = row$place     %||% "",
      pages       = row$pages     %||% "",
      DOI         = row$DOI       %||% "",  # added
      ISBN        = row$ISBN      %||% "",  # added
      ISSN        = row$ISSN      %||% ""   # added
    ),

    # document and any unrecognised type
    list(
      publisher = row$publisher %||% "",
      place     = row$place     %||% "",  # added
      DOI       = row$DOI       %||% ""   # added
    )
  )

  as_tibble(c(base, extra))
}

#' Convert a full reference tibble to Zotero API items.
#'
#' Applies \code{\link{ref_to_zotero_item}} to every row and row-binds the
#' results.
#'
#' @param refs A refs tibble (e.g. from \code{\link{enrich_refs}} or
#'   \code{\link{deduplicate_refs}}).
#' @return A tibble of Zotero API items, one row per reference.
#' @keywords internal
refs_to_zotero_items <- function(refs) {
  map_dfr(seq_len(nrow(refs)), function(i) ref_to_zotero_item(refs[i, ]))
}

#' Import a reference tibble into a new Zotero collection.
#'
#' Creates a new Zotero collection named \code{collection_name} and posts all
#' new items to it.  If \code{\link{check_library_for_refs}} has been run
#' beforehand, references already in the library (\code{import_action ==
#' "add_to_collection"}) are moved into the new collection instead of being
#' re-created.
#'
#' @param refs A refs tibble, optionally with \code{import_action} and
#'   \code{existing_key} columns from \code{\link{check_library_for_refs}}.
#' @param collection_name Name for the new Zotero collection.
#' @param user_id Zotero user ID (character or numeric).
#' @param api_key Zotero API key with write access.
#' @param user Logical; if \code{FALSE} treat \code{user_id} as a group ID.
#'   Default \code{TRUE}.
#' @param group_id Group ID, used when \code{user = FALSE}.
#' @param dry_run If \code{TRUE}, print what would be posted but do not call
#'   the Zotero API.  Returns the pre-built c2z Zotero list.  Default
#'   \code{FALSE}.
#' @return The c2z Zotero list returned by \code{ZoteroPost()}, or (dry run)
#'   the pre-built list without posting.
#' @seealso \code{\link{post_refs_to_zotero}}, \code{\link{wiki_refs_pipeline}}
import_to_zotero <- function(refs, collection_name,
                              user_id = NULL, api_key = NULL,
                              user = TRUE, group_id = NULL,
                              dry_run = FALSE) {
  # If check_library_for_refs has been run, split refs by import_action.
  # Otherwise treat all refs as new items.
  if ("import_action" %in% names(refs)) {
    new_refs      <- filter(refs, import_action == "create_new")
    existing_keys <- refs |>
      filter(import_action == "add_to_collection") |>
      pull(existing_key) |>
      na.omit() |>
      as.character()
  } else {
    new_refs      <- refs
    existing_keys <- character(0)
  }

  id     <- if (user) user_id else group_id
  zotero <- Zotero(user = user, id = id, api = api_key)

  collection_key <- ZoteroKey()

  zotero$collections <- tibble(
    key              = collection_key,
    version          = 0L,
    name             = collection_name,
    parentCollection = "FALSE"
  )

  # Convert new refs to Zotero items, each assigned to the new collection.
  # The Zotero API requires each item to carry the key(s) of its collection(s).
  zotero$items <- if (nrow(new_refs) > 0) {
    refs_to_zotero_items(new_refs) |>
      mutate(collections = map(seq_len(n()), \(i) collection_key))
  } else {
    NULL
  }

  if (dry_run) {
    message(sprintf(
      "DRY RUN: Would create collection '%s' with %d new item(s) and %d moved item(s).",
      collection_name, nrow(new_refs), length(existing_keys)
    ))
    return(zotero)
  }

  result <- ZoteroPost(
    zotero,
    post.collections = TRUE,
    post.items       = !is.null(zotero$items),
    post.attachments = FALSE
  )

  # Move accepted existing items into the new collection
  if (length(existing_keys) > 0) {
    message("Moving ", length(existing_keys), " existing item(s) into collection...")
    add_items_to_collection(existing_keys, collection_key,
                            user_id = user_id, api_key = api_key, user = user)
  }

  result
}

# =============================================================================
# 11. Standalone Zotero post (use after a dry run)
# =============================================================================

#' Post a refs tibble to Zotero without re-running the full pipeline.
#'
#' Use this when you have already built and inspected a refs tibble (e.g. from
#' a previous `wiki_refs_pipeline()` call with `dry_run = TRUE`) and want to
#' push it to Zotero without fetching Wikipedia again.
#'
#' @param refs A refs tibble as returned by `wiki_refs_pipeline()`.
#' @param collection_name Name for the new Zotero collection.
#' @param user_id Zotero user ID.
#' @param api_key Zotero API key.
#' @param user If FALSE, treat `user_id` as a group ID. Default TRUE.
#' @return The c2z zotero list returned by `ZoteroPost()`.
post_refs_to_zotero <- function(refs, collection_name,
                                 user_id = NULL, api_key = NULL,
                                 user = TRUE) {
  import_to_zotero(refs, collection_name,
                   user_id  = user_id,
                   api_key  = api_key,
                   user     = user,
                   dry_run  = FALSE)
}

# =============================================================================
# 12. Library deduplication check
# =============================================================================

#' Fetch top-level items from a Zotero library or collection.
#'
#' Paginates through the Zotero REST API (100 items per page), handling
#' \code{429}/\code{503} rate-limit responses via \pkg{httr2}'s retry
#' mechanism.  Returns a normalised lookup tibble used internally by
#' \code{\link{check_library_for_refs}} and \code{\link{fetch_zotero_keys}}.
#'
#' @param user_id Zotero user ID.
#' @param api_key Zotero API key (read access sufficient).
#' @param user Logical; if \code{FALSE} treat \code{user_id} as a group ID.
#'   Default \code{TRUE}.
#' @param collection_key Optional 8-character Zotero collection key.  If
#'   supplied, only items in that collection are fetched.
#' @return A tibble with columns \code{key}, \code{title}, \code{DOI},
#'   \code{ISBN}, \code{date}, \code{publisher}, \code{first_author}, and
#'   normalised lookup columns \code{doi_norm}, \code{isbn_norm},
#'   \code{title_norm}, \code{year_norm}.
#' @keywords internal
.fetch_zotero_items <- function(user_id, api_key, user = TRUE,
                                 collection_key = NULL) {
  entity    <- if (user) "users" else "groups"
  item_path <- if (!is.null(collection_key))
    paste0("collections/", collection_key, "/items/top")
  else
    "items/top"
  endpoint <- paste0(
    "https://api.zotero.org/", entity, "/", user_id, "/", item_path
  )

  base_req <- request(endpoint) |>
    req_headers(
      "Zotero-API-Key"     = api_key,
      "Zotero-API-Version" = "3"
    ) |>
    req_retry(
      max_tries    = 4,
      is_transient = \(r) resp_status(r) %in% c(429, 503),
      after        = \(r) {
        val <- resp_header(r, "Backoff") %||% resp_header(r, "Retry-After")
        if (!is.null(val)) as.numeric(val) else NULL
      }
    )

  fetch_page <- function(start) {
    base_req |>
      req_url_query(limit = 100, start = start) |>
      req_perform() |>
      resp_body_json(simplifyVector = FALSE)
  }

  first_resp <- base_req |>
    req_url_query(limit = 100, start = 0) |>
    req_perform()

  total <- as.integer(resp_header(first_resp, "Total-Results") %||% "0")
  raw   <- resp_body_json(first_resp, simplifyVector = FALSE)

  if (total > 100) {
    offsets <- seq(100, total - 1, by = 100)
    raw <- c(raw, list_flatten(map(offsets, fetch_page)))
  }

  if (length(raw) == 0) return(tibble())

  pluck_field <- function(item, field) {
    v <- item$data[[field]]
    if (is.null(v) || !nzchar(as.character(v))) NA_character_ else as.character(v)
  }

  first_author_name <- function(item) {
    cr <- item$data$creators
    if (is.null(cr) || length(cr) == 0) return(NA_character_)
    authors <- Filter(\(c) identical(c$creatorType, "author"), cr)
    if (length(authors) == 0) authors <- cr[1]
    a     <- authors[[1]]
    last  <- a$lastName  %||% ""
    first <- a$firstName %||% ""
    if (nzchar(last) && nzchar(first)) paste0(last, ", ", first)
    else if (nzchar(last)) last
    else NA_character_
  }

  norm <- function(x) {
    x <- tolower(coalesce(as.character(x), ""))
    x <- stri_trans_general(x, "Latin-ASCII")
    str_replace_all(x, "[^a-z0-9]", "")
  }

  tibble(
    key          = map_chr(raw, \(x) x$key),
    title        = map_chr(raw, \(x) pluck_field(x, "title")),
    DOI          = map_chr(raw, \(x) pluck_field(x, "DOI")),
    ISBN         = map_chr(raw, \(x) pluck_field(x, "ISBN")),
    date         = map_chr(raw, \(x) pluck_field(x, "date")),
    publisher    = map_chr(raw, \(x) pluck_field(x, "publisher")),
    first_author = map_chr(raw, first_author_name)
  ) |>
    mutate(
      doi_norm   = norm(DOI),
      isbn_norm  = norm(ISBN),
      title_norm = norm(title),
      year_norm  = coalesce(str_extract(coalesce(date, ""), "\\d{4}"), "")
    )
}

#' Add existing Zotero items to a collection via the REST API.
#'
#' Uses PATCH semantics: for each item, adds the collection key to the item's
#' `collections` array.  Items are batched into groups of up to 50 and POSTed
#' with `collections` set to include the target collection key.
#'
#' @param item_keys Character vector of Zotero item keys.
#' @param collection_key Destination collection key.
#' @param user_id Zotero user ID.
#' @param api_key Zotero API key (write access).
#' @param user Logical; if FALSE treat user_id as group ID.
add_items_to_collection <- function(item_keys, collection_key,
                                     user_id, api_key, user = TRUE) {
  entity   <- if (user) "users" else "groups"
  prefix   <- paste0("https://api.zotero.org/", entity, "/", user_id)

  base_req <- request(paste0(prefix, "/items")) |>
    req_headers(
      "Zotero-API-Key"     = api_key,
      "Zotero-API-Version" = "3"
    ) |>
    req_retry(
      max_tries    = 3,
      is_transient = \(r) resp_status(r) %in% c(429, 503)
    )

  # First, fetch current version and collections for each item so we don't
  # clobber existing collection memberships.
  fetch_req <- request(prefix) |>
    req_headers(
      "Zotero-API-Key"     = api_key,
      "Zotero-API-Version" = "3"
    )

  # Fetch items in batches of 50 (API limit for itemKey filter)
  key_chunks <- split(item_keys, ceiling(seq_along(item_keys) / 50))
  item_data <- list()
  for (chunk in key_chunks) {
    resp <- fetch_req |>
      req_url_path_append("items") |>
      req_url_query(itemKey = paste(chunk, collapse = ","), limit = 50) |>
      req_perform() |>
      resp_body_json(simplifyVector = FALSE)
    item_data <- c(item_data, resp)
  }

  # Build PATCH payloads: add collection_key to each item's collections
  patches <- map(item_data, \(item) {
    existing_cols <- item$data$collections %||% list()
    all_cols <- unique(c(as.character(existing_cols), collection_key))
    list(
      key         = item$key,
      version     = item$version,
      collections = all_cols
    )
  })

  # POST batches of up to 50 (POST with key+version = PATCH semantics)
  patch_chunks <- split(patches, ceiling(seq_along(patches) / 50))
  for (chunk in patch_chunks) {
    base_req |>
      req_body_json(chunk) |>
      req_perform()
  }

  invisible(item_keys)
}

#' Check a refs tibble against the existing Zotero library for duplicates.
#'
#' For each ref that matches an existing Zotero item (by DOI, ISBN, or
#' normalised title + year), records the match and reports it to the user via
#' \code{message()}.  All matches are automatically accepted: the existing item
#' will be added to the new collection rather than re-created.  No interactive
#' prompting is performed, so this function is safe to use in non-interactive
#' contexts (scripts, WebR, Shinylive, etc.).
#'
#' @param refs A refs tibble (as returned by \code{\link{wiki_refs_pipeline}}
#'   or \code{\link{extract_refs_from_wikitext}}).
#' @param user_id Zotero user ID.
#' @param api_key Zotero API key (read access sufficient).
#' @param user Logical; if \code{FALSE} treat \code{user_id} as a group ID.
#'   Default \code{TRUE}.
#' @return \code{refs} with three new columns:
#'   \describe{
#'     \item{\code{existing_key}}{Key of the matching Zotero item, or
#'       \code{NA}.}
#'     \item{\code{import_action}}{\code{"add_to_collection"} when a match was
#'       found; \code{"create_new"} otherwise.}
#'     \item{\code{duplicate_how}}{How the match was found: \code{"DOI"},
#'       \code{"ISBN"}, \code{"title + year"}, or \code{NA}.}
#'   }
check_library_for_refs <- function(refs, user_id, api_key, user = TRUE) {
  message("Fetching library items for duplicate check...")
  library_items <- .fetch_zotero_items(user_id = user_id, api_key = api_key,
                                        user = user)
  message(nrow(library_items), " existing item(s) in library.")

  refs$existing_key  <- NA_character_
  refs$import_action <- "create_new"
  refs$duplicate_how <- NA_character_

  if (nrow(library_items) == 0) return(refs)

  norm <- function(x) {
    x <- tolower(coalesce(as.character(x), ""))
    x <- stri_trans_general(x, "Latin-ASCII")
    str_replace_all(x, "[^a-z0-9]", "")
  }

  find_candidate <- function(ref) {
    doi  <- norm(ref$DOI)
    isbn <- norm(ref$ISBN)
    titl <- norm(ref$title)
    yr   <- ref$year %||% ""

    if (nzchar(doi)) {
      hit <- filter(library_items, doi_norm == doi)
      if (nrow(hit)) return(list(item = hit[1, ], how = "DOI"))
    }
    if (nzchar(isbn)) {
      hit <- filter(library_items, isbn_norm == isbn)
      if (nrow(hit)) return(list(item = hit[1, ], how = "ISBN"))
    }
    if (nzchar(titl) && nzchar(yr)) {
      hit <- filter(library_items, title_norm == titl, year_norm == yr)
      if (nrow(hit)) return(list(item = hit[1, ], how = "title + year"))
    }
    NULL
  }

  fmt_field <- function(x, w = 48) {
    x <- if (is.na(x) || !nzchar(x %||% "")) "(none)" else as.character(x)
    if (nchar(x) > w) paste0(substr(x, 1, w - 1), "\u2026") else x
  }

  report_match <- function(ref, zot, how, idx, total) {
    rule <- strrep("\u2500", 105)
    msg_lines <- c(
      rule,
      sprintf(" [%d/%d] Duplicate found via %s \u2192 will add to collection instead of re-creating", idx, total, how),
      rule,
      sprintf("  %-18s  %-48s  %-48s", "Field", "Wikipedia ref", "Existing Zotero item"),
      sprintf("  %-18s  %-48s  %-48s", strrep("-", 18), strrep("-", 48), strrep("-", 48)),
      sprintf("  %-18s  %-48s  %-48s", "Title",     fmt_field(ref$title),        fmt_field(zot$title)),
      sprintf("  %-18s  %-48s  %-48s", "Author(s)", fmt_field(ref$first_author), fmt_field(zot$first_author)),
      sprintf("  %-18s  %-48s  %-48s", "Year",      fmt_field(ref$year),         fmt_field(zot$year_norm)),
      sprintf("  %-18s  %-48s  %-48s", "Publisher", fmt_field(ref$publisher),    fmt_field(zot$publisher)),
      sprintf("  %-18s  %-48s  %-48s", "DOI",       fmt_field(ref$DOI),          fmt_field(zot$DOI)),
      sprintf("  %-18s  %-48s  %-48s", "ISBN",      fmt_field(ref$ISBN),         fmt_field(zot$ISBN)),
      sprintf("  %-18s  %-48s",        "Zotero key", fmt_field(zot$key)),
      rule
    )
    message(paste(msg_lines, collapse = "\n"))
  }

  candidates   <- map(seq_len(nrow(refs)), \(i) find_candidate(refs[i, ]))
  n_candidates <- sum(map_lgl(candidates, Negate(is.null)))

  if (n_candidates == 0) {
    message("No duplicates found — all references will be created as new items.")
    return(refs)
  }

  message(n_candidates, " duplicate(s) found in your Zotero library:")

  match_count <- 0L
  for (i in seq_len(nrow(refs))) {
    cand <- candidates[[i]]
    if (is.null(cand)) next
    match_count <- match_count + 1L
    report_match(refs[i, ], cand$item, cand$how, match_count, n_candidates)
    refs$existing_key[i]  <- cand$item$key
    refs$import_action[i] <- "add_to_collection"
    refs$duplicate_how[i] <- cand$how
  }

  message(sprintf(
    "Result: %d existing item(s) will be added to the new collection, %d new item(s) will be created.",
    sum(refs$import_action == "add_to_collection"),
    sum(refs$import_action == "create_new")
  ))

  refs
}

# =============================================================================
# 13. Fetch citation keys from Zotero
# =============================================================================

#' Look up Zotero item keys for each row in a refs tibble.
#'
#' Fetches top-level items from the Zotero library or a specific collection
#' (via `.fetch_zotero_items()`) and matches each row back using
#' DOI → ISBN → normalised title + year. Typically called automatically by
#' `wiki_refs_pipeline()` after a successful import.
#'
#' @param refs A refs tibble (as returned by `wiki_refs_pipeline()` or
#'   `extract_refs_from_wikitext()`).
#' @param user_id Zotero user ID (character or numeric).
#' @param api_key Zotero API key.
#' @param user Logical; if FALSE treat `user_id` as a group ID. Default TRUE.
#' @param collection_key Optional Zotero collection key (8-char string). If
#'   supplied, only items in that collection are fetched; otherwise the whole
#'   library is searched.
#' @return `refs` with `zotero_key` and `zotero_match` columns added.
#'   `zotero_match` is one of "doi", "isbn", "title_year", or "unmatched".
fetch_zotero_keys <- function(refs,
                               user_id = NULL, api_key = NULL,
                               user = TRUE, collection_key = NULL) {
  message(
    "Fetching Zotero items",
    if (!is.null(collection_key)) paste0(" (collection: ", collection_key, ")")
    else " (full library)", "..."
  )

  lookup <- .fetch_zotero_items(user_id       = user_id,
                                 api_key       = api_key,
                                 user          = user,
                                 collection_key = collection_key)

  message("Fetched ", nrow(lookup), " item(s).")

  if (nrow(lookup) == 0) {
    warning("No items returned from Zotero; all rows will be unmatched.")
    return(mutate(refs, zotero_key = NA_character_, zotero_match = "unmatched"))
  }

  norm <- function(x) {
    x <- tolower(coalesce(as.character(x), ""))
    x <- stri_trans_general(x, "Latin-ASCII")
    str_replace_all(x, "[^a-z0-9]", "")
  }

  match_row <- function(ref) {
    doi  <- norm(ref$DOI)
    isbn <- norm(ref$ISBN)
    titl <- norm(ref$title)
    yr   <- ref$year %||% ""

    if (nzchar(doi)) {
      hit <- filter(lookup, doi_norm == doi)
      if (nrow(hit)) return(c(hit$key[1], "doi"))
    }
    if (nzchar(isbn)) {
      hit <- filter(lookup, isbn_norm == isbn)
      if (nrow(hit)) return(c(hit$key[1], "isbn"))
    }
    if (nzchar(titl)) {
      hit <- filter(lookup, title_norm == titl)
      if (nrow(hit)) {
        if (nzchar(yr)) {
          hit_yr <- filter(hit, year_norm == yr)
          if (nrow(hit_yr)) return(c(hit_yr$key[1], "title_year"))
        }
        return(c(hit$key[1], "title_year"))
      }
    }
    c(NA_character_, "unmatched")
  }

  results <- map(seq_len(nrow(refs)), \(i) match_row(refs[i, ]))

  refs$zotero_key   <- map_chr(results, 1)
  refs$zotero_match <- map_chr(results, 2)

  tab  <- table(refs$zotero_match)
  getn <- function(k) if (k %in% names(tab)) tab[[k]] else 0L
  message(sprintf(
    "Matched %d / %d refs  (doi: %d, isbn: %d, title_year: %d, unmatched: %d)",
    sum(refs$zotero_match != "unmatched"), nrow(refs),
    getn("doi"), getn("isbn"), getn("title_year"), getn("unmatched")
  ))

  refs
}

# =============================================================================
# 14. Main pipeline
# =============================================================================

#' Extract Wikipedia references and optionally import to Zotero.
#'
#' The main entry point for the pipeline.  Fetches wikitext for
#' \code{page_name}, extracts and deduplicates all citation templates,
#' optionally enriches metadata via DOI/ISBN lookups, optionally exports to
#' RIS, and optionally imports to a Zotero collection.
#'
#' \strong{Typical two-step workflow:}
#' Run first with \code{dry_run = TRUE} (the default) to inspect parsed
#' references.  Then pass the returned tibble to
#' \code{\link{post_refs_to_zotero}} to complete the import without fetching
#' Wikipedia again.
#'
#' @param page_name Wikipedia page title as it appears in the URL (e.g.
#'   \code{"Elizabeth_Lyon_(criminal)"}).  Underscores and spaces are both
#'   accepted.
#' @param language Two-letter Wikipedia language code.  Default \code{"en"}.
#' @param ris_file Path to write a RIS export file.  \code{NULL} to skip.
#'   Default \code{NULL}.
#' @param enrich Logical; if \code{TRUE} (default), enrich metadata via DOI
#'   and ISBN lookups using \code{c2z::ZoteroDoi} / \code{c2z::ZoteroIsbn}.
#' @param zotero_import Logical; if \code{TRUE}, create a Zotero collection and
#'   post items.  Requires \code{user_id} and \code{api_key}.  Default
#'   \code{FALSE}.
#' @param check_existing Logical; if \code{TRUE} (default) and
#'   \code{zotero_import = TRUE}, query the library for duplicates via
#'   \code{\link{check_library_for_refs}}.  Matches are reported to the user
#'   via \code{message()} and automatically accepted: the existing Zotero item
#'   is added to the new collection instead of being re-created.
#' @param collection_name Name for the new Zotero collection.  Defaults to the
#'   page title with underscores replaced by spaces.
#' @param user_id Zotero user ID (character or numeric).
#' @param api_key Zotero API key with write access.
#' @param read_api_key Zotero API key for read-only operations (duplicate check
#'   and key fetch).  Falls back to \code{api_key} if \code{NULL}.
#' @param fetch_keys Logical; if \code{TRUE} (default) and
#'   \code{zotero_import = TRUE} and \code{dry_run = FALSE}, call
#'   \code{\link{fetch_zotero_keys}} after import to add \code{zotero_key} and
#'   \code{zotero_match} columns to the returned tibble.
#' @param dry_run Logical; if \code{TRUE} (default), skip all Zotero API
#'   writes.  The pipeline still fetches Wikipedia, parses refs, and optionally
#'   enriches them.
#' @return A tibble of deduplicated (and optionally enriched) references.
#'   Additional columns are present depending on options:
#'   \code{zotero_key} and \code{zotero_match} (when \code{fetch_keys = TRUE}),
#'   \code{existing_key} and \code{import_action} (when
#'   \code{check_existing = TRUE}).
#' @examples
#' \dontrun{
#' # Step 1: dry run to inspect
#' refs <- wiki_refs_pipeline(
#'   "Meiō_incident",
#'   enrich       = TRUE,
#'   zotero_import = TRUE,
#'   user_id      = Sys.getenv("ZOTERO_USER_ID"),
#'   api_key      = Sys.getenv("ZOTERO_API_KEY"),
#'   dry_run      = TRUE
#' )
#'
#' # Step 2: satisfied? post without re-fetching Wikipedia
#' post_refs_to_zotero(
#'   refs,
#'   collection_name = "Meiō incident",
#'   user_id         = Sys.getenv("ZOTERO_USER_ID"),
#'   api_key         = Sys.getenv("ZOTERO_API_KEY")
#' )
#' }
#' @seealso \code{\link{post_refs_to_zotero}}, \code{\link{export_ris}},
#'   \code{\link{check_library_for_refs}}, \code{\link{fetch_zotero_keys}}
wiki_refs_pipeline <- function(page_name = NULL,
                                language = "en",
                                wikitext = NULL,
                                ris_file = NULL,
                                enrich = TRUE,
                                zotero_import = FALSE,
                                check_existing = TRUE,
                                collection_name = NULL,
                                user_id = NULL,
                                api_key = NULL,
                                read_api_key = NULL,
                                fetch_keys = TRUE,
                                dry_run = TRUE) {

  # Track which stages completed; attached to the result as an attribute
  status <- list(
    extract    = FALSE,
    dedup      = FALSE,
    enrich     = FALSE,
    ris_export = FALSE,
    check_existing = FALSE,
    zotero_import  = FALSE,
    fetch_keys     = FALSE,
    errors     = character()
  )

  # Helper: run a pipeline stage, updating `refs` on success and recording

  # errors on failure.  On error, emits a warning and returns `refs` unchanged.

  safe_stage <- function(stage_name, expr) {
    tryCatch(
      {
        result <- expr
        status[[stage_name]] <<- TRUE
        result
      },
      error = function(e) {
        msg <- sprintf("Pipeline stage '%s' failed: %s", stage_name, conditionMessage(e))
        warning(msg, call. = FALSE, immediate. = TRUE)
        status$errors <<- c(status$errors, msg)
        NULL
      }
    )
  }

  if (is.null(wikitext)) {
    if (is.null(page_name)) stop("Either `page_name` or `wikitext` must be provided.")
    message("Fetching wikitext for: ", page_name)
    wikitext <- fetch_wikitext(page_name, language = language)
  } else {
    message("Using supplied wikitext (", nchar(wikitext), " characters)")
  }

  message("Extracting citations...")
  refs <- safe_stage("extract", extract_refs_from_wikitext(wikitext))
  if (is.null(refs)) {
    warning("Extraction failed — nothing to return.", call. = FALSE, immediate. = TRUE)
    return(structure(tibble(), .pipeline_status = status))
  }
  message("Found ", nrow(refs), " citation templates (before dedup)")

  message("Deduplicating...")
  deduped <- safe_stage("dedup", deduplicate_refs(refs))
  if (!is.null(deduped)) refs <- deduped
  message("Unique references: ", nrow(refs))

  message("\nReference types:")
  print(count(refs, itemType, sort = TRUE))

  if (enrich) {
    message("\nEnriching metadata via DOI/ISBN...")
    enriched <- safe_stage("enrich", enrich_refs(refs))
    if (!is.null(enriched)) refs <- enriched
  }

  if (!is.null(ris_file)) {
    safe_stage("ris_export", export_ris(refs, ris_file))
  }

  if (zotero_import && check_existing) {
    message("\nChecking for existing items in Zotero library...")
    checked <- safe_stage("check_existing", check_library_for_refs(
      refs,
      user_id = user_id,
      api_key = read_api_key %||% api_key,
      user    = TRUE
    ))
    if (!is.null(checked)) refs <- checked
  }

  imported_collection_key <- NULL

  if (zotero_import) {
    cname <- collection_name %||% str_replace_all(page_name, "_", " ")
    message("\nImporting to Zotero collection: ", cname)
    result <- safe_stage("zotero_import", import_to_zotero(
      refs, cname,
      user_id = user_id, api_key = api_key,
      dry_run = dry_run
    ))
    if (!is.null(result) && !dry_run && !is.null(result$collections)) {
      imported_collection_key <- result$collections$key[1]
    }
  }

  if (fetch_keys && !dry_run && !is.null(imported_collection_key)) {
    message("\nFetching Zotero keys for imported items...")
    keyed <- safe_stage("fetch_keys", fetch_zotero_keys(
      refs,
      user_id        = user_id,
      api_key        = read_api_key %||% api_key,
      collection_key = imported_collection_key
    ))
    if (!is.null(keyed)) refs <- keyed
  }

  if (length(status$errors) > 0) {
    message("\nPipeline completed with ", length(status$errors), " error(s). ",
            "Returning refs as of last successful stage.")
  }

  structure(refs, .pipeline_status = status)
}
