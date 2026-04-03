# update-versioned-archive.R
# Created by Carwil Bjork-James on April 1, 2021
#
# This script handles archiving each version of the dataset that we import.
#
# Known issues:
# 1. [FIXED] Granularity is one archive per day — upgraded to datetime (HH:MM:SS),
#    so multiple updates on the same day each get a distinct archive file.
# 2. [FIXED] Assumes that the most recent dated version is equal to the current
#    version. Now verified explicitly: if the undated file has drifted from its
#    newest dated archive (e.g. manual edit), the undated file is re-archived.
# 3. [FIXED] No metadata stored other than the date. A sidecar .txt file is now
#    written alongside each new dated archive with timestamp, dimensions, column
#    names, and MD5 hash.
# 4. We haven't yet created any functional tools to load and verify data from
#    these RDS files, though readr::read_rds() may be adequate.

# ── Helpers ──────────────────────────────────────────────────────────────────

# Inserts a datetime stamp into a filepath before the extension, ensuring the
# result is a filename that does not already exist. If the plain timestamped
# name is taken (two calls in the same second), appends -2, -3, etc.
# e.g. "data/panel.rds" → "data/panel-2026-03-10-21h.rds"
#       or   "data/panel.rds" → "data/panel-2026-03-10-21h-b.rds" (collision)
append_current_datetime <- function(filename = "filename.ext") {
  path      <- tools::file_path_sans_ext(filename)
  extension <- tools::file_ext(filename)
  stamp     <- format(Sys.time(), "%Y-%m-%d-%Hh")
  candidate <- paste0(path, "-", stamp, ".", extension)
  suffix    <- letters
  i <- 1
  while (file.exists(candidate)) {
    candidate <- paste0(path, "-", stamp, "-", suffix[i], ".", extension)
    i <- i + 1
  }
  candidate
}

# Writes a plain-text sidecar metadata file alongside a newly dated archive.
write_archive_metadata <- function(df, filename_dated) {
  meta_path <- paste0(tools::file_path_sans_ext(filename_dated), ".txt")
  lines <- c(
    paste("Archived:    ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    paste("File:        ", basename(filename_dated)),
    paste("Rows:        ", nrow(df)),
    paste("Columns:     ", ncol(df)),
    paste("Column names:", paste(names(df), collapse = ", ")),
    paste("MD5:         ", tools::md5sum(filename_dated))
  )
  writeLines(lines, meta_path)
  invisible(meta_path)
}

# ── Main function ─────────────────────────────────────────────────────────────

# Checks if df differs from its saved version, and if so, overwrites the
# canonical file and saves a new dated archive with a sidecar metadata file.
#
# Returns the path to the dated archive file (relative to project root),
# suitable for use in reproducibility metadata.

update_versioned_archive <- function(df, filename = "data/filename.ext",
                                     compress = "gz") {
  path          <- dirname(filename)
  filename_base <- basename(filename)
  filename_ext  <- tools::file_ext(filename)
  filename_full <- here::here(path, filename_base)

  if (tolower(filename_ext) != "rds") {
    warning("update_versioned_archive is designed to work with RDS files only.")
    return(paste0(filename, " (archive unsuccessful)"))
  }

  # Write undated + dated archive, plus metadata sidecar. Returns dated path.
  archive_new <- function(df) {
    readr::write_rds(df, file = filename_full, compress = compress)
    filename_dated <- append_current_datetime(filename_full)
    readr::write_rds(df, file = filename_dated, compress = compress)
    write_archive_metadata(df, filename_dated)
    filename_dated
  }

  # Find existing dated .rds archives for this file (not sidecar .txt files).
  find_dated_archives <- function() {
    stem  <- tools::file_path_sans_ext(filename_base)
    files <- list.files(
      dirname(filename_full),
      pattern    = paste0("^", stem, "-\\d{4}-\\d{2}-\\d{2}"),
      full.names = TRUE
    )
    files[tools::file_ext(files) == "rds"]
  }

  if (!file.exists(filename_full)) {
    # No file yet — create the first archive.
    filename_dated <- archive_new(df)

  } else {
    df_saved <- readr::read_rds(filename_full)

    if (isTRUE(all.equal(df, df_saved))) {
      # Data matches the undated file. Now verify the undated file also matches
      # its newest dated archive (guards against manual edits — issue 2).
      dated <- find_dated_archives()

      if (length(dated) == 0) {
        # Undated file exists but has no dated archive — create one now.
        filename_dated <- append_current_datetime(filename_full)
        readr::write_rds(df, file = filename_dated, compress = compress)
        write_archive_metadata(df, filename_dated)

      } else {
        newest_dated <- dated[which.max(file.info(dated)$mtime)]
        df_newest    <- readr::read_rds(newest_dated)

        if (!isTRUE(all.equal(df_saved, df_newest))) {
          # Undated file has drifted from its newest archive — re-archive it.
          filename_dated <- append_current_datetime(filename_full)
          readr::write_rds(df, file = filename_dated, compress = compress)
          write_archive_metadata(df, filename_dated)
        } else {
          # Everything consistent — return the existing newest dated archive.
          filename_dated <- newest_dated
        }
        rm(df_newest)
      }

    } else {
      # Data changed — overwrite undated file and create new dated archive.
      filename_dated <- archive_new(df)
    }

    rm(df_saved)
  }

  # Return path relative to project root (consistent with input convention).
  file.path(path, basename(filename_dated))
}
