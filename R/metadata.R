# Spreadsheet metadata for all ICE detention facility files.
#
# Each row describes one fiscal year's Excel file: its URL, local path,
# sheet name, header row positions, and rightmost data column.

build_data_file_info <- function() {
  LETTERS_PLUS <- c(LETTERS, paste0("A", LETTERS), paste0("B", LETTERS))

  # FY26 has three snapshots: FY26a (Feb 2 file, data through ~Jan 22),
  # FY26b (Feb 12 file, data through Feb 5), and FY26 (July 20 file). All are
  # imported; `snapshot` distinguishes them. The crosswalk pools all three so
  # facilities dropped mid-year keep their canonical rows;
  # resolve_fy26_snapshots() builds the panel variants.
  info <- tibble::tibble(
    year_name = c("FY19", "FY20", "FY21", "FY22", "FY23",
                  "FY24", "FY25", "FY26a", "FY26b", "FY26"),
    year = c(2019:2025, 2026, 2026, 2026),
    snapshot = c(NA_character_, NA_character_, NA_character_, NA_character_,
                 NA_character_, NA_character_, NA_character_,
                 "a", "b", "c"),
    url = c(
      "https://www.ice.gov/doclib/detention/FY19-detentionstats.xlsx",
      "https://www.ice.gov/doclib/detention/FY20-detentionstats.xlsx",
      "https://www.ice.gov/doclib/detention/FY21-detentionstats.xlsx",
      "https://www.ice.gov/doclib/detention/FY22-detentionStats.xlsx",
      "https://www.ice.gov/doclib/detention/FY23_detentionStats.xlsx",
      "https://www.ice.gov/doclib/detention/FY24_detentionStats.xlsx",
      "https://www.ice.gov/doclib/detention/FY25_detentionStats09242025.xlsx",
      "https://www.ice.gov/doclib/detention/FY26_detentionStats02022026.xlsx",
      "https://www.ice.gov/doclib/detention/FY26_detentionStats02122026.xlsx",
      "https://www.ice.gov/doclib/detention/FY26_detentionStats07202026.xlsx"
    ),
    local_file = c(
      "data/ice/FY19-detentionstats.xlsx",
      "data/ice/FY20-detentionstats.xlsx",
      "data/ice/FY21-detentionstats.xlsx",
      "data/ice/FY22-detentionStats.xlsx",
      "data/ice/FY23_detentionStats.xlsx",
      "data/ice/FY24_detentionStats.xlsx",
      "data/ice/FY25_detentionStats09242025.xlsx",
      "data/ice/FY26_detentionStats02022026.xlsx",
      "data/ice/FY26_detentionStats_02122026.xlsx",
      "data/ice/FY26_detentionStats07202026.xlsx"
    ),
    sheet_name = c(
      "Facilities FY19", "Facilities EOYFY20 ", "Facilities FY21 YTD",
      "Facilities FY22", "Facilities EOFY23",
      "Facilities EOFY24", "Facilities FY25", "Facilities FY26",
      "Facilities FY26", "Facilities FY26"
    ),
    header_rows = list(
      c(5, 7), c(5, 7), c(5, 7), c(5, 7), c(4, 6),
      c(5, 7), c(5, 7), c(9, 10), c(9, 10), c(9, 10)
    ),
    right_column = c("AE", "AE", "AE", "AD", "AG", "AB", "AB", "AA", "AA", "AA")
  )

  info |>
    dplyr::rowwise() |>
    dplyr::mutate(
      first_header_row  = unlist(header_rows)[[1]],
      second_header_row = unlist(header_rows)[[2]],
      first_data_row    = max(unlist(header_rows)) + 1,
      right_column_num  = which(LETTERS_PLUS == right_column)
    ) |>
    dplyr::select(-header_rows) |>
    dplyr::ungroup()
}
