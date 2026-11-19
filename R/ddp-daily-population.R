# Recreate DDP's facilities-daily-population-latest.parquet from
# detention-stints-latest.parquet, following DDP's methodology
# (code/facilities-daily-population-latest.R, last version commit c19668375f,
# 2026-03-30, since removed from the deportationdata/ice repository).
#
# DDP semantics replicated here:
# - Each stint expands to one row per day from as.Date(book_in_date_time)
#   through as.Date(book_out_date_time); open-ended stints are capped at
#   `end_date` (DDP's data-through date). end before start is recoded to start.
# - Counts are of DISTINCT persons (unique_identifier; NA identifiers get
#   unique synthetic ids, i.e. each NA row counts as one person) per
#   facility code x date:
#   n_detained, n_detained_at_midnight (booked in on or before date AND
#   booked out after date, i.e. out date >= date + 1, or still open),
#   n_detained_male, n_detained_female, n_detained_convicted_criminal
#   (book_in_criminality == "1 Convicted Criminal"),
#   n_detained_possibly_under_18 (date < (birth_year + 18)-01-01).
# - Duplicate-flagged stints are NOT filtered (matches both DDP scripts).
# - The result is a complete facility-code x date grid from start_date to
#   end_date, zeros filled, with the facility name from each code's most
#   recent book-in.

#' Build the DDP facilities daily population table from detention stints
#'
#' Recreates `facilities-daily-population-latest.parquet` from
#' `detention-stints-latest.parquet` following the Deportation Data
#' Project's published methodology. DDP removed the generating script
#' from their repository in July 2026, so this function preserves it.
#' The heavy day-expansion and distinct-count steps use data.table.
#'
#' @param stints A data frame of DDP detention stints (any columns beyond
#'   the eight required are ignored). Required columns: `unique_identifier`,
#'   `detention_facility_code`, `detention_facility`, `book_in_date_time`,
#'   `book_out_date_time`, `gender`, `book_in_criminality`, `birth_year`.
#' @param start_date First date of the output grid (DDP: 2022-10-01).
#' @param end_date Last date of the output grid; also the census date for
#'   open-ended stints (DDP uses their data-through date, one day before
#'   the release date).
#' @param codes_per_chunk Facilities processed per chunk; controls peak
#'   memory during the day-expansion step.
#' @return A tibble: complete `detention_facility_code` x `date` grid
#'   (`start_date` to `end_date`) with the seven `n_detained*` count
#'   columns and `detention_facility`, matching DDP's published schema.
#' @export
build_ddp_daily_population <- function(stints,
                                       start_date = as.Date("2022-10-01"),
                                       end_date,
                                       codes_per_chunk = 30L) {
  required_cols <- c(
    "unique_identifier", "detention_facility_code", "detention_facility",
    "book_in_date_time", "book_out_date_time", "gender",
    "book_in_criminality", "birth_year"
  )
  missing <- setdiff(required_cols, names(stints))
  if (length(missing) > 0) {
    stop("stints is missing required columns: ", paste(missing, collapse = ", "))
  }
  if (any(is.na(stints$book_in_date_time))) {
    stop("stints contains NA book_in_date_time; DDP's method cannot place these rows on a date")
  }

  start_int <- as.integer(start_date)
  end_int <- as.integer(end_date)

  # --- prep: integer keys, clamped expansion windows -----------------------
  prep <- stints |>
    dplyr::select(dplyr::all_of(required_cols)) |>
    dplyr::mutate(
      uid = dplyr::if_else(
        is.na(unique_identifier),
        paste0("noid_", dplyr::row_number()),
        unique_identifier
      ),
      s = as.integer(as.Date(book_in_date_time)),
      out_int = as.integer(as.Date(book_out_date_time)),
      is_open = is.na(book_out_date_time),
      e = dplyr::if_else(is_open, end_int, out_int),
      # recode end-before-start to start (data-quality artifacts)
      e = pmax(s, e),
      # clamp expansion to the output window; drop rows outside it
      s_c = pmax(s, start_int),
      e_c = pmin(e, end_int),
      is_male = gender == "Male",
      is_female = gender == "Female",
      is_convicted = book_in_criminality == "1 Convicted Criminal",
      under18_cutoff = dplyr::if_else(
        is.na(birth_year),
        NA_integer_,
        as.integer(as.Date(sprintf("%d-01-01", as.integer(birth_year) + 18L)))
      )
    ) |>
    dplyr::filter(e_c >= s_c) |>
    dplyr::select(
      uid, code = detention_facility_code, s, out_int, is_open,
      s_c, e_c, is_male, is_female, is_convicted, under18_cutoff
    ) |>
    data.table::as.data.table()

  # integer keys: much faster grouping than raw strings
  prep[, uid_id := match(uid, unique(prep$uid))]
  prep[, code_id := match(code, unique(prep$code))]
  prep[, n_days := e_c - s_c + 1L]

  code_levels <- unique(prep[, .(code_id, detention_facility_code = code)]) |>
    (\(x) x[order(x$code_id), ])()

  code_chunks <- split(unique(prep$code_id),
                       (seq_along(unique(prep$code_id)) - 1L) %/% codes_per_chunk)

  # --- per-chunk: expand to person-days, distinct counts per facility-date --
  chunk_counts <- lapply(code_chunks, function(chunk_code_ids) {
    d <- prep[code_id %in% chunk_code_ids]

    # expand each stint to one row per in-window day (vectorized);
    # rep.int expands row i n_days times contiguously and sequence()
    # yields the matching 1..n_days offsets in the same order
    idx <- rep.int(seq_len(nrow(d)), d$n_days)
    offsets <- sequence(d$n_days)
    dt <- d[idx, .(uid_id, code_id, out_int, is_open,
                   s_c, is_male, is_female, is_convicted, under18_cutoff)]
    dt[, date := s_c + offsets - 1L]
    dt[, at_midnight := is_open | (out_int >= date + 1L)]
    dt[, under18 := !is.na(under18_cutoff) & (date < under18_cutoff)]

    dt[, .(
      n_detained = data.table::uniqueN(uid_id),
      n_detained_at_midnight = data.table::uniqueN(uid_id[at_midnight]),
      n_detained_male = data.table::uniqueN(uid_id[is_male]),
      n_detained_female = data.table::uniqueN(uid_id[is_female]),
      n_detained_convicted_criminal = data.table::uniqueN(uid_id[is_convicted]),
      n_detained_possibly_under_18 = data.table::uniqueN(uid_id[under18])
    ), by = .(code_id, date)]
  })

  counts <- data.table::rbindlist(chunk_counts)

  # --- facility names: most recent book-in per code (from full stints) ------
  facility_names <- data.table::as.data.table(stints)[
    order(-as.integer(as.POSIXct(book_in_date_time))),
    .(detention_facility = detention_facility[1L]),
    by = detention_facility_code
  ]

  # --- complete grid, join names --------------------------------------------
  grid <- data.table::CJ(
    code_id = code_levels$code_id,
    date = start_int:end_int
  )
  counts <- counts[grid, on = c("code_id", "date")]  # left join: all grid rows
  count_cols <- c(
    "n_detained", "n_detained_at_midnight", "n_detained_male",
    "n_detained_female", "n_detained_convicted_criminal",
    "n_detained_possibly_under_18"
  )
  for (cc in count_cols) {
    data.table::set(counts, which(is.na(counts[[cc]])), cc, 0L)
  }
  counts <- code_levels[counts, on = "code_id"]
  counts <- facility_names[counts, on = "detention_facility_code"]
  counts <- counts[order(code_id, date)]

  tibble::as_tibble(counts) |>
    dplyr::mutate(
      date = as.Date(date, origin = "1970-01-01"),
      dplyr::across(dplyr::starts_with("n_detained"), as.integer)
    ) |>
    dplyr::select(
      detention_facility_code, date,
      n_detained, n_detained_at_midnight, n_detained_male,
      n_detained_female, n_detained_convicted_criminal,
      n_detained_possibly_under_18, detention_facility
    )
}
