# Import facility data from ICE Excel spreadsheets.
#
# Two-step process:
#   1. Read the two-row headers and combine into clean variable names.
#   2. Read the data rows using those names.

# ── Header extraction ────────────────────────────────────────────────────────

header_rows <- function(data_file_info_row) {
  with(data_file_info_row, {
    first_row <- readxl::read_excel(
      local_file,
      sheet = sheet_name,
      range = readxl::cell_limits(
        ul = c(first_header_row, 1),
        lr = c(first_header_row, right_column_num)
      ),
      col_names = FALSE
    )
    second_row <- readxl::read_excel(
      local_file,
      sheet = sheet_name,
      range = readxl::cell_limits(
        ul = c(second_header_row, 1),
        lr = c(second_header_row, right_column_num)
      ),
      col_names = FALSE
    )
    rbind(first_row, second_row)
  })
}

# ── Variable name cleaning ───────────────────────────────────────────────────

clean_variable_names_from_header <- function(raw_headers) {
  clean_names <- raw_headers |>
    t() |>
    as.data.frame() |>
    tidyr::fill(V1) |>
    dplyr::mutate(
      V1 = stringr::str_trim(stringr::str_remove_all(V1, "FY\\d\\d")),
      V1 = stringr::str_remove_all(V1, ":"),
      V2 = stringr::str_trim(stringr::str_remove_all(V2, "FY\\d\\d")),
      V2 = stringr::str_remove_all(V2, ":"),
      V1 = dplyr::case_when(
        stringr::str_detect(V1, "This list") ~ "Facility",
        V1 == "Facility Information" ~ "Facility",
        V1 == "ADP Detainee Classification Level" ~ "ADP Detainee Classification",
        V1 == "ADP Detainee Security Level" ~ "ADP Detainee Security",
        V1 == "ADP ICE Threat Level" ~ "ADP",
        V1 == "ADP Mandatory" ~ "ADP",
        V1 == "Contract Facility Inspections Information" ~ "Inspections",
        TRUE ~ V1
      ),
      combined = paste(V1, V2),
      var_name = tolower(combined),
      var_name = stringr::str_replace_all(var_name, "[^a-z0-9]+", "_"),
      var_name = stringr::str_remove_all(var_name, "^_+|_+$")
    ) |>
    dplyr::pull(var_name)

  clean_names
}

# ── Build clean names for all years ──────────────────────────────────────────

build_clean_names <- function(data_file_info) {
  raw_headers_list <- purrr::map(seq_len(nrow(data_file_info)), function(i) {
    header_rows(data_file_info[i, ])
  })
  names(raw_headers_list) <- data_file_info$year_name

  clean_names_list <- purrr::map(raw_headers_list, clean_variable_names_from_header)
  names(clean_names_list) <- data_file_info$year_name
  clean_names_list
}

# ── Read facility data for one year ──────────────────────────────────────────

read_facilities_data <- function(data_file_info_row, clean_names_list) {
  with(data_file_info_row, {
    readxl::read_xlsx(
      local_file,
      sheet = sheet_name,
      range = readxl::cell_limits(
        ul = c(first_data_row, 1),
        lr = c(NA, right_column_num)
      ),
      col_names = clean_names_list[[year_name]]
    )
  })
}

# ── Import all years ─────────────────────────────────────────────────────────

import_all_years <- function(data_file_info, clean_names_list) {
  facilities_data_list <- purrr::map(seq_len(nrow(data_file_info)), function(i) {
    read_facilities_data(data_file_info[i, ], clean_names_list)
  })
  names(facilities_data_list) <- data_file_info$year_name
  facilities_data_list
}
