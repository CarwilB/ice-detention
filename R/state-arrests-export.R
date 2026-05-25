# R/state-arrests-export.R
# Functions for pre-computing and exporting state arrest data for web deployment.
# Entry point: export_state_arrests(arrests, stays, detloc_lookup, geo_all,
#                                    census_file, pew_file, cutoff, data_end,
#                                    export_dir)

# ── Nationwide outcomes summary (efficient single-pass) ───────────────────────

#' Compute removal outcomes per state from arrests + stays in one pass.
#' Returns a tibble with state_lower, n_stays_outcomes, removed, released,
#' pending, pct_removed, pct_released, pct_pending.
build_state_outcomes <- function(arr_post, stays, cutoff) {
  # One row per person, keeping their arrest state
  arr_id_state <- arr_post |>
    dplyr::filter(!is.na(unique_identifier), !is.na(apprehension_state)) |>
    dplyr::select(unique_identifier, apprehension_state) |>
    dplyr::distinct(unique_identifier, .keep_all = TRUE)

  all_ids <- arr_id_state$unique_identifier

  stays |>
    dplyr::filter(
      unique_identifier %in% all_ids,
      as.Date(stay_book_in_date_time) >= cutoff
    ) |>
    dplyr::left_join(arr_id_state, by = "unique_identifier") |>
    dplyr::filter(!is.na(apprehension_state)) |>
    dplyr::mutate(
      outcome = dplyr::case_when(
        stay_release_reason == "Removed" ~ "removed",
        is.na(stay_release_reason)       ~ "pending",
        TRUE                             ~ "released"
      )
    ) |>
    dplyr::count(apprehension_state, outcome) |>
    tidyr::pivot_wider(names_from = outcome, values_from = n, values_fill = 0L) |>
    dplyr::mutate(
      # Ensure all three columns exist even if a state has no entries for a category
      removed  = if (exists("removed",  inherits = FALSE)) removed  else 0L,
      released = if (exists("released", inherits = FALSE)) released else 0L,
      pending  = if (exists("pending",  inherits = FALSE)) pending  else 0L
    ) |>
    dplyr::mutate(
      n_stays_outcomes = removed + released + pending,
      pct_removed      = round(removed  / n_stays_outcomes * 100, 1),
      pct_released     = round(released / n_stays_outcomes * 100, 1),
      pct_pending      = round(pending  / n_stays_outcomes * 100, 1),
      state_lower      = stringr::str_to_lower(apprehension_state)
    ) |>
    dplyr::select(-apprehension_state)
}

# ── Nationwide reactable summary tibble ───────────────────────────────────────

#' Build one-row-per-state summary for the nationwide reactable and bubble map.
#' Joins arrests ratio data, Census/Pew denominators, and removal outcomes.
#'
#' @param arrests    Raw arrests tibble (arrests_raw).
#' @param stays      Raw stays tibble (stays_raw).
#' @param census_file Path to NST-EST2025-POP.xlsx.
#' @param pew_file   Path to Pew unauthorized immigrants xlsx.
#' @param cutoff     Analysis start date (Date).
#' @param data_end   Last valid data date (Date).
#' @return Tibble with one row per state, all summary columns.
build_nationwide_summary <- function(arrests, stays, census_file, pew_file,
                                      cutoff, data_end) {
  cutoff   <- as.Date(cutoff)
  data_end <- as.Date(data_end)

  # Filtered post-cutoff arrests
  arr <- arrests |>
    dplyr::filter(
      duplicate_likely == FALSE | is.na(duplicate_likely),
      apprehension_date >= cutoff,
      apprehension_date <= data_end
    )

  # State arrest counts (post-cutoff)
  state_counts <- arr |>
    dplyr::filter(!is.na(apprehension_state)) |>
    dplyr::mutate(state_lower = stringr::str_to_lower(apprehension_state)) |>
    dplyr::count(state_lower, name = "n_arrests")

  # Before/after rate ratio
  before_days <- as.numeric(cutoff - as.Date("2022-10-01"))
  after_days  <- as.numeric(data_end + 1 - cutoff)

  arr_all_clean <- arrests |>
    dplyr::filter(
      !is.na(apprehension_state),
      duplicate_likely == FALSE | is.na(duplicate_likely),
      apprehension_date <= data_end
    ) |>
    dplyr::mutate(
      state_lower = stringr::str_to_lower(apprehension_state),
      period      = dplyr::if_else(apprehension_date < cutoff, "before", "after")
    )

  state_ratio <- arr_all_clean |>
    dplyr::count(state_lower, period) |>
    tidyr::pivot_wider(names_from = period, values_from = n, values_fill = 0L) |>
    dplyr::mutate(
      before           = dplyr::coalesce(before, 0L),
      after            = dplyr::coalesce(after,  0L),
      rate_before      = round(before / before_days, 3),
      rate_after       = round(after  / after_days,  3),
      ratio            = dplyr::if_else(
        rate_before > 0, round(rate_after / rate_before, 2), NA_real_
      )
    )

  # Census 2025 population
  census_pops <- readxl::read_xlsx(census_file, col_names = FALSE) |>
    dplyr::select(geo_area = 1, pop_2025 = 8) |>
    dplyr::filter(!is.na(geo_area), stringr::str_starts(geo_area, "\\.")) |>
    dplyr::mutate(
      state_lower = stringr::str_to_lower(stringr::str_remove(geo_area, "^\\.")),
      pop_2025    = as.numeric(pop_2025)
    ) |>
    dplyr::select(state_lower, pop_2025)

  # Pew 2023 undocumented estimates
  pew_undoc <- readxl::read_xlsx(pew_file,
    sheet = "Population Characteristics", col_names = FALSE, skip = 4
  ) |>
    dplyr::select(state_name = 2, undoc_pop = 3, undoc_pct_pop = 4) |>
    dplyr::filter(!is.na(state_name), state_name != "U.S., total",
                  !stringr::str_starts(state_name, "Note")) |>
    dplyr::mutate(
      state_lower   = stringr::str_to_lower(state_name),
      undoc_pop     = as.numeric(gsub("[<,]", "", undoc_pop)),
      undoc_pct_pop = as.numeric(undoc_pct_pop)
    ) |>
    dplyr::select(state_lower, undoc_pop, undoc_pct_pop)

  # Removal outcomes
  outcomes <- build_state_outcomes(arr, stays, cutoff)

  # Join everything
  dplyr::left_join(state_ratio, state_counts,  by = "state_lower") |>
    dplyr::left_join(census_pops,  by = "state_lower") |>
    dplyr::left_join(pew_undoc,    by = "state_lower") |>
    dplyr::left_join(outcomes,     by = "state_lower") |>
    dplyr::mutate(
      state_title          = stringr::str_to_title(state_lower),
      state_abbr           = unname(STATE_ABBREVS[stringr::str_to_upper(state_lower)]),
      arrests_per_1k_undoc = dplyr::if_else(
        !is.na(undoc_pop) & undoc_pop > 0,
        round(n_arrests / undoc_pop * 1000, 2), NA_real_
      ),
      arrests_per_100k_pop = dplyr::if_else(
        !is.na(pop_2025) & pop_2025 > 0,
        round(n_arrests / pop_2025 * 1e5, 1), NA_real_
      )
    ) |>
    dplyr::filter(!is.na(state_abbr)) |>    # keep only 50 states + DC
    dplyr::arrange(dplyr::desc(n_arrests))
}

# ── Per-state RDS export ──────────────────────────────────────────────────────

#' Build and export per-state RDS files + nationwide summary.
#' Runs build_state_arrests_data() for every state in STATE_ABBREVS.
#'
#' @param arrests      Raw arrests tibble.
#' @param stays        Raw stays tibble.
#' @param detloc_lookup Full DETLOC → canonical_id lookup.
#' @param geo_all      Geocoded facility data tibble.
#' @param census_file  Path to Census XLSX.
#' @param pew_file     Path to Pew XLSX.
#' @param cutoff       Analysis start date.
#' @param data_end     Last valid data date.
#' @param export_dir   Directory to write RDS files into.
#' @return Character vector of file paths written (suitable for format = "file").
export_state_arrests <- function(arrests, stays, detloc_lookup, geo_all,
                                  census_file, pew_file,
                                  cutoff   = as.Date("2025-01-20"),
                                  data_end = as.Date("2026-03-31"),
                                  export_dir) {
  dir.create(export_dir, showWarnings = FALSE, recursive = TRUE)
  cutoff <- as.Date(cutoff)

  files_written <- character(0)

  # 1. Nationwide summary
  message("Building nationwide summary...")
  nationwide <- build_nationwide_summary(
    arrests, stays, census_file, pew_file, cutoff, data_end
  )
  nw_path <- file.path(export_dir, "nationwide.rds")
  saveRDS(nationwide, nw_path)
  files_written <- c(files_written, nw_path)
  message("  Saved nationwide.rds (", nrow(nationwide), " states)")

  # 2. Per-state data
  all_states <- names(STATE_ABBREVS)

  for (state in all_states) {
    abbr <- STATE_ABBREVS[[state]]
    message("Building ", state, " (", abbr, ")...")

    d <- tryCatch(
      build_state_arrests_data(
        arrests      = arrests,
        stays        = stays,
        detloc_lookup = detloc_lookup,
        geo_all      = geo_all,
        state        = state,
        cutoff       = cutoff
      ),
      error = function(e) {
        message("  ERROR: ", e$message)
        NULL
      }
    )

    if (!is.null(d)) {
      rds_path <- file.path(export_dir, paste0(abbr, ".rds"))
      saveRDS(d, rds_path)
      files_written <- c(files_written, rds_path)
    }
  }

  message("Export complete: ", length(files_written), " files written to ", export_dir)
  files_written
}
