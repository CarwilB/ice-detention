# Download ICE detention spreadsheets from ice.gov.
#
# Only downloads files that don't already exist locally.
# Returns the vector of local file paths (for targets file tracking).

download_ice_spreadsheets <- function(data_file_info) {
  for (i in seq_len(nrow(data_file_info))) {
    local <- data_file_info$local_file[i]
    if (!file.exists(local)) {
      message("Downloading ", basename(local), " ...")
      httr::GET(
        data_file_info$url[i],
        httr::write_disk(local, overwrite = FALSE)
      )
    } else {
      message("Already exists: ", basename(local))
    }
  }
  # Return paths so targets can track them as files
  data_file_info$local_file
}
