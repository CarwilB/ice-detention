# zotero-harvest-workflow.R
# Harvest references from the Wikipedia facility articles linked from
# "List of immigrant detention sites in the United States" into the shared
# Zotero group library:
#   https://www.zotero.org/groups/6462728/ice_detention/library
#
# One subcollection per facility, under a parent collection. Collection
# names come from canonical facility names where the article matches our
# database, otherwise from the article title.
#
# THIS IS NOT A PIPELINE TARGET. It fetches ~110 articles of wikitext from
# the Wikipedia API and writes to Zotero. Run it only when you intend to sync.
#
# Everything is resumable (wikitools-style per-entry caches under
# data/cache/wiki-refs/):
#   wikitext/<article>.txt  — wikitext, fetched once ever
#   refs/<article>.rds      — extracted references, saved after each article
#   import-log.csv          — one row per imported article (appended live)
# Interrupting a run loses nothing: re-run the same command and it continues
# from where it stopped. Re-runs also reuse existing subcollections and attach
# library duplicates (DOI / ISBN / title+year match) instead of re-creating.

library(dplyr)
library(here)
library(targets)

source(here("R", "wiki-refs-to-zotero.R"))
source(here("R", "zotero-harvest.R"))

# ── Configuration ────────────────────────────────────────────────────────────

ZOTERO_API_KEY <- Sys.getenv("zotero_access_key_write")
if (!nzchar(ZOTERO_API_KEY)) {
  stop(
    "`zotero_access_key_write` is not set.\n",
    "Add it to ~/.Renviron (a key with write access to group 6462728), ",
    "then restart R."
  )
}

# ── Article → collection mapping (from the pipeline, no API access) ─────────

article_map <- tar_read(wiki_article_collection_map)
cat(sprintf("%d extant articles to harvest (%d matched to canonical facilities)\n",
            nrow(article_map), sum(!is.na(article_map$canonical_name))))

# ── Step 1: Dry run (fetches wikitext, counts refs, touches nothing) ────────

# Set enrich = FALSE here for a fast preview of counts; the real run below
# enriches via DOI/ISBN lookups.
dry <- harvest_wiki_refs_to_zotero(
  article_map,
  enrich  = FALSE,
  dry_run = TRUE
)

cat("\n--- Dry-run summary ---\n")
print(dry |>
        count(status) |>
        mutate(n = as.character(n)) |>
        tidyr::pivot_wider(names_from = status, values_from = n))
cat("\nArticles with zero refs after extraction:\n")
print(dry |> filter(n_refs == 0) |> pull(article_title))

# Inspect any extraction failures (recorded as errors during the run):
# attr(dry, ".extraction_errors")  # set on the refs list, not the summary

# ── Step 2: Real run ─────────────────────────────────────────────────────────

# Uncomment to write to Zotero. Safe to re-run any time (incremental).
#
# results <- harvest_wiki_refs_to_zotero(
#   article_map,
#   enrich  = TRUE,
#   dry_run = FALSE
# )
# print(results)
