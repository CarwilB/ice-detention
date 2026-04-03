# Download ICE detention spreadsheets and supplemental DMCP listings.
#
# Only downloads files that don't already exist locally.
# All functions return local file path(s) for targets file tracking.

download_ice_spreadsheets <- function(data_file_info) {
  for (i in seq_len(nrow(data_file_info))) {
    local <- data_file_info$local_file[i]
    if (!file.exists(local)) {
      message("Downloading ", basename(local), " ...")
      tmp <- tempfile(fileext = ".xlsx")
      resp <- httr::GET(data_file_info$url[i], httr::write_disk(tmp))
      if (httr::status_code(resp) != 200L) {
        unlink(tmp)
        warning("HTTP ", httr::status_code(resp), " for ", basename(local),
                " — skipping (URL may be stale)")
        next
      }
      file.rename(tmp, local)
    } else {
      message("Already exists: ", basename(local))
    }
  }
  data_file_info$local_file
}

# ── DMCP listing downloads ────────────────────────────────────────────────────

download_faclist15 <- function() {
  path <- here::here("data/ice/2015IceDetentionFacilityListing.xlsx")
  if (!file.exists(path)) {
    message("Downloading ", basename(path), " ...")
    httr::GET(
      "https://www.ice.gov/doclib/foia/dfs/2015IceDetentionFacilityListing.xlsx",
      httr::write_disk(path, overwrite = FALSE)
    )
  } else {
    message("Already exists: ", basename(path))
  }
  path
}

download_faclist17 <- function() {
  path <- here::here("data/ice/ICE_DMCP_Facility_List_2017.pdf")
  if (!file.exists(path)) {
    message("Downloading ", basename(path), " ...")
    download.file(
      "https://www.prisonlegalnews.org/media/publications/ICE_DMCP_Facility_List_ERO_Custody_Management_Division_2017.pdf",
      path, mode = "wb", quiet = TRUE
    )
  } else {
    message("Already exists: ", basename(path))
  }
  path
}
