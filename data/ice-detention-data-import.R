library(readxl)
library(libr)
library(httr)
library(dplyr)
library(stringr)
library(tidyr)
library(purrr)

data_url <- "https://www.ice.gov/doclib/detention/FY26_detentionStats02022026.xlsx"
local_file <- "data/FY26_detentionStats02022026.xlsx"
sheet_name <- "Facilities FY26"

httr::GET(data_url, write_disk(local_file, overwrite = TRUE))

# Tibble with multiple years
data_file_info <- tibble(
  year_name = c("FY19", "FY20", "FY21", "FY22", "FY23",
    "FY24", "FY25", "FY26"),
  year = c(2019:2026),
  local_file = c("data/FY19-detentionstats.xlsx",
    "data/FY20-detentionstats.xlsx",
    "data/FY21-detentionstats.xlsx",
    "data/FY22-detentionStats.xlsx",
    "data/FY23_detentionStats.xlsx",
    "data/FY24_detentionStats.xlsx",
    "data/FY25_detentionStats09242025.xlsx",
    "data/FY26_detentionStats02022026.xlsx"),
  sheet_name = c("Facilities FY19", "Facilities EOYFY20 ", "Facilities FY21 YTD",
    "Facilities FY22", "Facilities EOFY23",
    "Facilities EOFY24", "Facilities FY25", "Facilities FY26"),
  header_rows = list(c(5,7), c(5,7), c(5,7), c(5,7), c(4,6),
                  c(5,7), c(5,7), c(9,10)),
  right_column= c("AE", "AE", "AE", "AD", "AG",
    "AB", "AB", "AA")
)

LETTERS_PLUS <- c(LETTERS, paste0("A", LETTERS), paste0("B", LETTERS))

data_file_info <- data_file_info %>%
  rowwise() %>%
  mutate(
    first_header_row = unlist(header_rows)[[1]],
    second_header_row = unlist(header_rows)[[2]],
    first_data_row = max(unlist(header_rows)) + 1,
    right_column_num = which(LETTERS_PLUS == right_column)) %>%
  select(-header_rows)


# 1. Read the header rows (Row 9 and 10) specifically
#    We limit to column 27 (AA) to match your range request
raw_headers <- read_excel(
  local_file,
  sheet = sheet_name,
  range = "A9:AA10",
  col_names = FALSE
)


header_rows <- function(data_file_info_row){
  with(data_file_info_row, {
    first_row <- read_excel(
      local_file,
      sheet = sheet_name,
      range = cell_limits(
        ul = c(first_header_row, 1),
        lr = c(first_header_row, right_column_num)
      ),
      col_names = FALSE
    )
    second_row <- read_excel(
      local_file,
      sheet = sheet_name,
      range = cell_limits(
        ul = c(second_header_row, 1),
        lr = c(second_header_row, right_column_num)
      ),
      col_names = FALSE
    )
    rbind(first_row, second_row)
  })
}

raw_headers <- header_rows(data_file_info %>% filter(year_name == "FY26"))

# Create a list of headers for each spreadsheet
raw_headers_list <- map(1:nrow(data_file_info), function(i) {
  header_rows(data_file_info[i, ])
})
names(raw_headers_list) <- data_file_info$year_name

# 2. Create Clean Variable Names
#    - Transpose headers to columns for easier filling
#    - Fill the top header row (Row 9) downward to cover merged cells
#    - Remove "FY26"
#    - Combine Top and Bottom headers
#    - Format to snake_case (lowercase with underscores)
clean_variable_names_from_header <- function(raw_headers) {
  clean_names <- raw_headers %>%
    t() %>%
    as.data.frame() %>%
    fill(V1) %>%                                     # Propagate Row 9 headers
    mutate(
      # Remove "FY26" and extra whitespace from both header parts
      V1 = str_trim(str_remove_all(V1, "FY\\d\\d")),
      V1 = str_remove_all(V1, ":"), # Remove colons if present
      V2 = str_trim(str_remove_all(V2, "FY\\d\\d")),
      V2 = str_remove_all(V2, ":"),

      V1 = case_when( # clean extra words
        str_detect(V1, "This list") ~ "Facility",
        V1 == "Facility Information" ~ "Facility",
#        str_detect(V1, "Average Length of Stay") ~ "ALOS",
        V1 == "ADP Detainee Classification Level" ~ "ADP Detainee Classification",
        V1 == "ADP Detainee Security Level" ~ "ADP Detainee Security",
        V1 == "ADP ICE Threat Level" ~ "ADP",
        V1 == "ADP Mandatory" ~ "ADP",
        V1 == "Contract Facility Inspections Information" ~ "Inspections",

        TRUE ~ V1
      ),

      # Combine Row 9 (V1) and Row 10 (V2)
      combined = paste(V1, V2),

      # Clean: Lowercase, replace special chars with _, remove duplicates
      var_name = tolower(combined),
      var_name = str_replace_all(var_name, "[^a-z0-9]+", "_"),
      var_name = str_remove_all(var_name, "^_+|_+$") # Remove leading/trailing _
    ) %>%
    pull(var_name)
  clean_names
}

clean_names <- clean_variable_names_from_header(raw_headers)

clean_names_list <- map(raw_headers_list, clean_variable_names_from_header)
names(clean_names_list) <- data_file_info$year_name
clean_names_list$FY24

# Side analysis with UpSetR to see overlaps

library(UpSetR)
upset_plot <- upset(fromList(clean_names_list),
                    sets = names(clean_names_list),
                    order.by = "freq")  # Visual intersection analysis
upset_plot

# Create a dataframe showing which variables are in which lists
presence_matrix <- clean_names_list %>%
  imap_dfr(~ tibble(variable = .x, list_name = .y)) %>%
  mutate(present = TRUE) %>%
  pivot_wider(names_from = list_name, values_from = present, values_fill = FALSE)



# Find FY23-only variables
vars_in_all <- presence_matrix %>%
  filter(rowSums(select(., -variable)) == ncol(select(., -variable))) %>%
  pull(variable)
setdiff(unlist(clean_names_list), vars_in_all)

fy23_only <- presence_matrix %>%
  filter(FY23 == TRUE & rowSums(select(., -variable, -FY23)) == 0) %>%
  pull(variable)
not_in_fy23_22 <- presence_matrix %>%
  filter(FY23 == FALSE) %>%
  filter(FY22 == FALSE) %>%
  pull(variable)
not_in_fy23 <- presence_matrix %>%
  filter(FY23 == FALSE) %>%
  pull(variable)

clean_facility_names <- function(x) {
  # 1. Base conversion to Title Case
  x <- str_to_title(x)

  # 2. Typos and Truncations found in your specific list
  x <- str_replace_all(x, "Facili\\b", "Facility")       # Fixes #3
  x <- str_replace_all(x, "Processsing", "Processing")   # Fixes #155

  # 3. Expansion Map (Abbreviations -> Full Words)
  #    Using word boundaries (\\b) to prevent replacing inside other words.
  expansions <- c(
    "\\bDept\\.?\\b" = "Department",
    "\\bCtr\\.?\\b"  = "Center",
    "\\bCorr\\.?\\b" = "Correctional",
    "\\bInst\\.?\\b" = "Institution",
    "\\bFed\\.?\\b"  = "Federal",
    "\\bDet\\.?\\b"  = "Detention",
    "\\bFac\\.?\\b"  = "Facility",
    "\\bCo\\.?\\b"   = "County"
  )

  x <- str_replace_all(x, expansions)

  # 4. Acronym Restoration (Re-capitalizing)
  #    These were turned into "Ice", "Mdc" etc. by str_to_title
  acronyms <- c(
    "\\bOf\\b" = "of", # keep "of" lowercase
    "\\bUs\\b" = "US", # keep "US" uppercase; this would'nt work on general text
    "\\bIce\\b" = "ICE",
    "\\bEro\\b" = "ERO",
    "\\bMdc\\b" = "MDC",
    "\\bCca\\b" = "CCA",
    "\\bFci\\b" = "FCI",
    "\\bFdc\\b" = "FDC",
    "\\bJtf\\b" = "JTF",
    "\\bSsm\\b" = "SSM",
    "\\bTgk\\b" = "TGK",
    "\\bIpc\\b" = "IPC",
    "\\bSpc\\b" = "SPC",
    "\\bIah\\b" = "IAH",
    "\\bClipc\\b" = "CLIPC",
    "\\bDigsa\\b" = "DIGSA",
    "\\bIgsa\\b" = "IGSA"
  )

  x <- str_replace_all(x, acronyms)

  # 5. State Abbreviation Expansions
  #    Handles both (FL) and comma formats like ", NM"
  states <- c(
    "\\(Fl\\)" = "(Florida)",
    "\\(In\\)" = "(Indiana)",
    "\\(Mo\\)" = "(Missouri)",
    "\\(Mt\\)" = "(Montana)",
    "\\(Ne\\)" = "(Nebraska)",
    "\\(Ny\\)" = "(New York)",
    "\\(Tx\\)" = "(Texas)",
    "\\(Ut\\)" = "(Utah)",
    ", Nm\\b"  = ", New Mexico",
    ", Mt\\b"  = ", Montana"
  )

  x <- str_replace_all(x, states)

  return(x)
}


# 4. Import the "Facilities" sheet
# facilities_data <- read_xlsx(local_file, sheet = sheet_name)

facilities_data <- read_xlsx(
  local_file,
  sheet = sheet_name,
  range = cell_limits(ul = c(11, 1), lr = c(NA, 27)),
  col_names = clean_names
)

read_facilities_data <- function(data_file_info_row){
  with(data_file_info_row, {
    read_xlsx(
      local_file,
      sheet = sheet_name,
      range = cell_limits(ul = c(first_data_row, 1), lr = c(NA, right_column_num)),
      col_names = clean_names_list[[year_name]] # Use precomputed clean names
                                                # A more elegant programming approach,
                                                # might incorporate them into data_file_info
    )
  })
}

clean_facilities_data <- function(facilities_data) {
  numerical_columns = c("facility_average_length_of_stay_alos", "adp_detainee_classification_level_a",
                        "adp_detainee_classification_level_b", "adp_detainee_classification_level_c",
                        "adp_detainee_classification_level_d", "adp_criminality_male_crim",
                        "adp_criminality_male_non_crim", "adp_criminality_female_crim",
                        "adp_criminality_female_non_crim", "adp_ice_threat_level_1",
                        "adp_ice_threat_level_2", "adp_ice_threat_level_3", "adp_no_ice_threat_level",
                        "adp_mandatory", "inspections_guaranteed_minimum")
  numerical_columns_present <- numerical_columns[numerical_columns %in% names(facilities_data)]

  facilities_data_clean <- facilities_data %>%
    mutate(
      # 1. Convert specific columns to Numeric and round to 1 decimal
      across(
        .cols = facility_average_length_of_stay_alos:adp_mandatory,
        .fns = ~ round(as.numeric(.), 1)
      ),

      # 2. Convert Guaranteed Minimum to Integer
      inspections_guaranteed_minimum = as.integer(inspections_guaranteed_minimum),

      # Standardize Last Inspection Type values
      inspections_last_inspection_type = case_when(
        inspections_last_inspection_type %in% c("PRE-OCCUPANCY", "Pre-Occupancy") ~
          "PREOCC", # Standardize Pre-Occupancy
        TRUE ~ inspections_last_inspection_type
      ),

      # Adjust capitalization
      facility_name = clean_facility_names(facility_name),
      facility_city = str_to_title(facility_city),
      facility_address = str_to_title(facility_address),
      facility_male_female = str_to_title(facility_male_female),


      # 4. Ensure all other columns are Characters (as requested)
      #    We exclude the columns we just processed to avoid overwriting them
      across(
        .cols = -numerical_columns_present,
        .fns = as.character
      )
    )
}

aggregate_facilties_data <- function(facilities_data) {
  facilities_data <- facilities_data %>%
    mutate(
      sum_classification_levels = rowSums(
        select(., starts_with("adp_detainee_classification_level_")),
        na.rm = TRUE
      ),
      sum_criminality_levels = rowSums(
        select(., starts_with("adp_criminality_")),
        na.rm = TRUE
      ),
      sum_threat_levels = rowSums(
        select(., starts_with("adp_ice_threat_level_")|(starts_with("adp_no_ice_threat_level"))),
        na.rm = TRUE
      )
    ) %>%
    mutate(
      share_non_crim = (adp_criminality_male_non_crim + adp_criminality_female_non_crim) / sum_criminality_levels,
      share_no_threat = ( adp_no_ice_threat_level) / sum_threat_levels
    ) %>%
  # Assign type
    mutate(
      facility_type_wiki = case_when(
        str_detect(facility_type_detailed, "IGSA") ~ "Jail",
        str_detect(facility_type_detailed, "USMS IGA") ~ "Jail",
        str_detect(facility_type_detailed, "DIGSA") ~ "Dedicated Migrant Detention Center",
        str_detect(facility_type_detailed, "STATE") ~ "State Migrant Detention Center",
        str_detect(facility_type_detailed, "BOP") ~ "Federal Prison",
        str_detect(facility_type_detailed, "Family") ~ "Private Family Detention Center",
        str_detect(facility_type_detailed, "CDF") ~ "Private Migrant Detention Center",
        str_detect(facility_type_detailed, "USMS CDF") ~ "Private Migrant Detention Center",
        str_detect(facility_type_detailed, "SPC") ~ "ICE Migrant Detention Center",
        str_detect(facility_type_detailed, "STAGING") ~ "ICE Short-Term Migrant Detention Center",
        str_detect(facility_type_detailed, "DOD") ~ "Military Detention Center",
        TRUE ~ "Other"
      )
    )
}

facilities_data_list <- map(1:nrow(data_file_info), function(i)
  read_facilities_data(data_file_info[i, ])
)

facilities_data_list <- map(1:nrow(data_file_info), function(i)
  read_facilities_data(data_file_info[i, ]) %>%
    clean_facilities_data() %>%
    aggregate_facilties_data()
)

# Get unique facility names from each tibble
facility_names_list <- map(facilities_data_list, ~ {
  if ("facility_name" %in% names(.x)) {
    unique(.x$facility_name)
  } else {
    character(0)
  }
})

names(facility_names_list) <- names(clean_names_list)

upset_plot_2 <- upset(fromList(facility_names_list),
                    sets = names(facility_names_list),
                    keep.order = T,
                    order.by = "degree")  # Visual intersection analysis
upset_plot_2

presence_matrix_facilities <- facility_names_list %>%
  imap_dfr(~ tibble(facility_name = .x, list_name = .y)) %>%
  mutate(present = TRUE) %>%
  pivot_wider(names_from = list_name, values_from = present, values_fill = FALSE)

presence_matrix_facilities <- presence_matrix_facilities %>%
  mutate(num_lists_present = rowSums(select(., -facility_name)))

presence_matrix_facilities %>% count(num_lists_present)

presence_matrix_facilities %>%
  filter((num_lists_present == 1) & (FY26)) %>%
  pull(facility_name)

all_facility_names <- unlist(facility_names_list, use.names = FALSE)

facilities_wikitable_from_merged <- function(facilties_data_list, year_name) {
  facilties_data %>%
    mutate(
      facility_name_wiki = case_when(
        facility_name == wiki_slug ~ paste0("[[", facility_name, "]]"),
        wiki_slug != "" ~ paste0("[[", wiki_slug, "|", facility_name, "]]"),
        TRUE ~ facility_name
      ),
      city_state = paste0(facility_city, ", ", facility_state),
      city_state_wiki = paste0("[[", city_state, "]]"),
      status = paste0("In use (", year_name, ")"),
      location = city_state_wiki,
      authority = facility_type_detailed,
      #           management = "",
      average_daily_population = round(sum_criminality_levels),
      minimum_capacity = inspections_guaranteed_minimum,
      demographics = facility_male_female) %>%
    select(
      facility_name_wiki,
      status,
      location,
      facility_type_wiki,
      authority,
      management,
      average_daily_population,
      minimum_capacity,
      demographics)

  table_column_names <- c(
    "Facility Name",
    "Status (year)",
    "Location",
    "Facility Type",
    "Authority",
    "Management",
    "Average Daily Population",
    "Minimum Capacity",
    "Demographics"
  )
}



# Function to print a data frame as a MediaWiki table

print_wikitable <- function(df, caption = NULL, class = "wikitable sortable",
                            column_names = NULL) {
  # 1. Start Table
  cat(paste0('{| class="', class, '"\n'))

  # 2. Add Caption (Optional)
  if (!is.null(caption)) {
    cat(paste0("|+ ", caption, "\n"))
  }

  # 3. Header Row
  if (!is.null(column_names)) {
    column_names <- names(df)
  }
  #    Use ! for headers, separating with !!
  cat("! ", paste(column_names, collapse = " !! "), "\n")

  # 4. Data Rows
  #    Loop through rows; start each with |-, separate cells with ||
  #    We apply a helper to escape any existing pipes '|' in the text to '{{!}}'
  #    so they don't break the wiki markup.

  formatted_rows <- apply(df, 1, function(row) {
    # Convert to character and escape pipes
    row_clean <- gsub("\\|", "{{!}}", as.character(row))
    # Replace NAs with empty string or specific text
    row_clean[is.na(row_clean)] <- ""

    paste0("| ", paste(row_clean, collapse = " || "))
  })

  # Print rows preceded by row separator
  cat(paste0("|-\n", formatted_rows, collapse = "\n"), "\n")

  # 5. End Table
  cat("|}\n")
}

print_wikitable(facilities_wikitable, column_names = table_column_names)

# 5. Create the Data Dictionary using libr
# The dictionary function returns a data frame describing the columns,
# types, and attributes of the dataset.
definitions <- c(
  "Name of the detention facility.",
  "Street address of the facility.",
  "City where the facility is located.",
  "State abbreviation.",
  "Zip code.",
  "Area of Responsibility (AOR): The local ICE field office with jurisdiction.",
  "Facility Type: The operational classification (e.g., IGSA, CDF, BOP, SPC).",
  "Gender composition of the facility (Male, Female, or Mixed).",
  "Average Length of Stay (ALOS): The average number of days a detainee spends in this facility.",
  "ADP - Level A: Low security risk classification.",
  "ADP - Level B: Medium-low security risk classification.",
  "ADP - Level C: Medium-high security risk classification.",
  "ADP - Level D: High security risk classification.",
  "ADP - Male detainees with a known criminal conviction.",
  "ADP - Male detainees with no criminal conviction.",
  "ADP - Female detainees with a known criminal conviction.",
  "ADP - Female detainees with no criminal conviction.",
  "ADP - Threat Level 1: Primary conviction of aggravated felony or 2+ felonies.",
  "ADP - Threat Level 2: Primary conviction of felony or 3+ misdemeanors.",
  "ADP - Threat Level 3: Primary conviction of misdemeanor (<3).",
  "ADP - No ICE Threat Level: Detainees with no prior known criminal conviction.",
  "ADP - Mandatory: Detainees subject to mandatory detention statutes.",
  "Guaranteed Minimum: The minimum number of beds paid for by ICE regardless of usage.",
  "Last Inspection Type: The specific inspection protocol used (e.g., ODO, Pre-Occupancy).",
  "Last Inspection End Date: The date the most recent inspection concluded.",
  "Last Inspection Standard: The set of standards applied (e.g., PBNDS 2011, NDS 2019).",
  "Last Final Rating: Result of inspection (e.g., Acceptable, Deficient, At-Risk).",
  "Scheduled Inspection: Notes on the next planned inspection (usually present only when not yet inspected).",
  "Sum of average daily population across all classification levels.",
  "Sum of average daily population across criminal and non-criminal counts.",
  "Sum of average daily population across all threat levels.",
  "Share of non-criminal detainees in the facility.",
  "Share of detainees with no ICE threat level in the facility.",
  "Facility type as inferred from facility type field above (e.g., Jail, Migrant Detention Center)."
)

# 3. Create the Data Dictionary Data Frame
data_dictionary_1 <- tibble(
  variable_name = clean_names,
  description = definitions[1:27]
)

data_dictionary_2 <- tibble(
  variable_name = names(facilities_data_clean_aggregate),
  description = definitions
)

# View the dictionary
print(data_dictionary, n=30)

# libr dictionary not yet created

# # Optional: Export to CSV for reference
# # write_csv(data_dictionary, "facilities_data_dictionary.csv")
#
# facilities_dict <- dictionary(facilities_data)
#
# # View the dictionary
# print(facilities_dict)
#
# # Optional: Export the dictionary to a CSV for documentation
# write.csv(facilities_dict, "facilities_data_dictionary.csv", row.names = FALSE)
