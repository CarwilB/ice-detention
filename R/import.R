# Import facility data from ICE spreadsheets and supplemental DMCP listings.
#
# Annual FY stats (FY19–FY26): two-step process:
#   1. Read the two-row headers and combine into clean variable names.
#   2. Read the data rows using those names.
#
# Supplemental DMCP listings (2015 XLSX, 2017 PDF): each is a separate
# point-in-time roster of authorized facilities with contract and historical
# ADP data across multiple fiscal years per row. See rename_dmcp_columns()
# in clean.R for the column harmonization step.

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

# ── Supplemental DMCP facility listings ──────────────────────────────────────
#
# The DMCP (Detention Management Compliance Program) lists are authorization
# rosters that capture contract, operator, and multi-year ADP data for each
# facility in a single row. They are a different document type from the annual
# FY stats files and are handled by their own import functions.
#
# Both functions return raw data with minimal transformation. Apply
# rename_dmcp_columns() + clean_dmcp_data() (from clean.R) as the next step.

# ── Import December 2015 DMCP facility listing (XLSX) ────────────────────────
# Snapshot dated 2015-12-08. Contains FY2010–FY2016 ADP history per facility.
# Named for the snapshot date, not a fiscal year, because it covers 70+ days
# of FY2016 (Oct 1–Dec 8, 2015) as well as end-of-year data for FY2010–FY2015.

import_faclist15 <- function(path) {
  # Rows 1–6 are document title/metadata. Row 7 is the column header row.
  # Row 8+ is facility data.
  readxl::read_xlsx(
    path,
    sheet = "Facility List - Main",
    skip  = 6,
    col_names = TRUE
  ) |>
    # Drop blank trailing rows (no state or city)
    dplyr::filter(!is.na(State), !is.na(City))
}

# ── Column names for the 2017 DMCP PDF ───────────────────────────────────────

.dmcp_pdf_col_names <- c(
  "detloc", "name", "address", "city", "county", "state", "zip",
  "type", "type_detailed", "male_female", "levels",
  "capacity", "population_count",
  "fy17_adp", "fy16_adp", "fy15_adp", "fy14_adp", "fy13_adp",
  "fy12_adp", "fy11_adp", "fy10_adp",
  "facility_operator", "facility_owner",
  "contract_initiation_date", "contract_expiration_date",
  "per_diem_rate_detailed", "authorizing_authority",
  "over_under_72", "last_inspection_type", "last_inspection_standard",
  "last_inspection_rating_final", "last_inspection_date",
  "cy16_rating", "cy15_rating", "cy14_rating", "cy13_rating",
  "cy12_rating", "cy11_rating", "cy10_rating", "dsm_assigned"
)

# Column x-positions used as tabulapdf boundaries (inherited from the original
# pdftools/bounding-box analysis of header tokens; coordinates are in points
# from the top-left of the page).
.dmcp_pdf_col_breaks <- c(
   34, 101, 151, 179, 206, 218, 232, 246, 263, 286,
  302,   # capacity
  320,   # population_count
  341,   # fy17_adp
  353,   # fy16_adp
  365,   # fy15_adp
  377,   # fy14_adp
  389,   # fy13_adp
  401,   # fy12_adp
  413,   # fy11_adp
  426,   # fy10_adp
  437,   # facility_operator
  469, 483, 510, 536, 622, 642, 669, 687, 706, 734,
  754, 782, 811, 840, 869, 898, 920, 944
)

# ── Import 2017 DMCP facility list (PDF) ─────────────────────────────────────
#
# Uses tabulapdf::extract_tables() with explicit column boundaries to extract
# the facility table from pages 1–2. Column positions are passed directly so
# Tabula does not attempt to guess boundaries, which previously caused 4 narrow
# ADP columns to be merged into one on page 1.

import_faclist17 <- function(path) {
  tabs <- tabulapdf::extract_tables(
    path,
    pages   = 1:2,
    columns = list(.dmcp_pdf_col_breaks),
    guess   = FALSE,
    output  = "matrix"
  )

  do.call(rbind, tabs) |>
    tibble::as_tibble(.name_repair = "minimal") |>
    stats::setNames(.dmcp_pdf_col_names) |>
    # Keep only rows with a valid DETLOC code (all-caps alphanumeric, no spaces)
    # and a non-missing state; filters out page headers/footers/footnotes.
    dplyr::filter(grepl("^[A-Z0-9]+$", detloc), !is.na(state), detloc != "DETLOC")
}
