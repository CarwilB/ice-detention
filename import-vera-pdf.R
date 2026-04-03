# 1. Load libraries
# install.packages("tabulapdf")
library(tabulapdf)
library(dplyr)
library(purrr)

# 2. Define the file path
pdf_path <- "data/vera-institute/dashboard_appendix.pdf"

# 3. Extract tables from the first two pages
# pages = c(1, 2) tells tabula to look at those specific pages
# output = "data.frame" converts the matrices into frames immediately
raw_tables <- extract_tables(file = pdf_path, pages = c(8, 9), output = "tibble")

# 4. Process and combine the rows
# We map through the extracted list, selecting:
# Column 1 (DETLOC) and the Contract columns (usually the last 5-6 columns)
ice_contract_data <- map_df(raw_tables, function(df) {

  # Note: Depending on how the PDF renders, column indices might shift.
  # We select the 1st column and the columns specifically under "Contract"
  # Based on the 2017 layout, these are typically columns 1 and 15:19
  df %>%
    select(1, contains("Operator"), contains("Owner"), contains("Initiation"), contains("Expiration")) %>%
    # Clean up column names
    setNames(c("detloc", "operator", "owner", "initiation", "expiration"))
})

# 5. Clean Data Types
ice_contract_data <- ice_contract_data %>%
  mutate(
    initiation = as.Date(initiation, format = "%m/%d/%Y"),
    expiration = as.Date(expiration, format = "%m/%d/%Y")
  ) %>%
  filter(!is.na(detloc) & detloc != "") # Remove header/empty rows

# View results
head(ice_contract_data)
