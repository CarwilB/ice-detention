# vera-institute.R
# Import functions for the Vera Institute ICE Detention Trends facility metadata.
#
# Source: https://github.com/vera-institute/ice-detention-trends
# Raw file: data/vera-institute/facilities.csv (downloaded manually)
#
# Provides 1,464 facility codes with geocoded locations, addresses, county,
# AOR, and facility type classifications.

# ── Import ───────────────────────────────────────────────────────────────────

import_vera_facilities <- function(path) {
  readr::read_csv(path, show_col_types = FALSE, col_types = readr::cols(
    detention_facility_code = readr::col_character(),
    detention_facility_name = readr::col_character(),
    address                 = readr::col_character(),
    city                    = readr::col_character(),
    county                  = readr::col_character(),
    state                   = readr::col_character(),
    zip                     = readr::col_character(),
    aor                     = readr::col_character(),
    latitude                = readr::col_double(),
    longitude               = readr::col_double(),
    type_detailed           = readr::col_character(),
    type_grouped            = readr::col_character()
  ))
}

# ── Clean ────────────────────────────────────────────────────────────────────

clean_vera_facilities <- function(vera_raw) {
  vera_raw |>
    dplyr::rename(
      detloc         = detention_facility_code,
      facility_name  = detention_facility_name,
      facility_city  = city,
      facility_state = state,
      facility_zip   = zip,
      facility_address = address
    ) |>
    dplyr::mutate(
      facility_zip = stringr::str_pad(facility_zip, width = 5, side = "left", pad = "0"),
      facility_name = stringr::str_squish(facility_name),
      facility_city = stringr::str_squish(facility_city)
    ) |>
    # Apply manual type corrections; preserve original type_grouped
    dplyr::left_join(vera_type_overrides(), by = "detloc") |>
    dplyr::mutate(
      vera_type_corrected = dplyr::coalesce(type_corrected, type_grouped)
    ) |>
    dplyr::select(-type_corrected)
}

# ── Vera → canonical DETLOC matches ─────────────────────────────────────────
# Manual matches for 28 canonical facilities that had no DETLOC from any other
# source. Matched by fuzzy name + city (21), address confirmation (3), and
# ZIP/city lookup (4). The 11 remaining no-DETLOC facilities are genuinely
# absent from Vera's data (CBP facilities, closed WV jails, etc.).

# ── Vera type corrections ──────────────────────────────────────────────────
# Manual corrections to Vera's type_grouped classification.
# Vera's original values are preserved in type_grouped; corrections are
# applied as vera_type_corrected in clean_vera_facilities().
#
# Two classes of error:
#   1. "Other/Unknown" facilities identifiable from their names (58 cases)
#   2. "Federal" county jails misclassified due to USMS IGA contract (16 cases)

vera_type_overrides <- function() {
  tibble::tribble(
    ~detloc,    ~type_corrected,

    # ── Other/Unknown → Non-Dedicated (county jails) ──────────────────────
    "ABIRJVA",  "Non-Dedicated",
    "ANDERSC",  "Non-Dedicated",
    "BARTOGA",  "Non-Dedicated",
    "BAYCOFL",  "Non-Dedicated",
    "BREVDFL",  "Non-Dedicated",
    "BROWNWI",  "Non-Dedicated",
    "CHFLDVA",  "Non-Dedicated",
    "COLUMFL",  "Non-Dedicated",
    "EPCDFTX",  "Non-Dedicated",
    "FLGLRFL",  "Non-Dedicated",
    "FNDDUWI",  "Non-Dedicated",
    "FRANKPA",  "Non-Dedicated",
    "GOODCID",  "Non-Dedicated",
    "JACKSTN",  "Non-Dedicated",
    "LASALTX",  "Non-Dedicated",
    "MRREGVA",  "Non-Dedicated",
    "NASTRNY",  "Non-Dedicated",
    "OSCEOFL",  "Non-Dedicated",
    "PIERCND",  "Non-Dedicated",
    "POTTRTX",  "Non-Dedicated",
    "PUTMAFL",  "Non-Dedicated",
    "SALINNE",  "Non-Dedicated",
    "SMNOLFL",  "Non-Dedicated",
    "SROSAFL",  "Non-Dedicated",
    "STJONFL",  "Non-Dedicated",
    "SUMTEFL",  "Non-Dedicated",
    "SUWANFL",  "Non-Dedicated",
    "TGKJLFL",  "Non-Dedicated",
    "UVALDTX",  "Non-Dedicated",
    "WALTNFL",  "Non-Dedicated",

    # ── Other/Unknown → Federal (state/federal prisons) ───────────────────
    "AZSVCPC",  "Federal",
    "BOPPET",   "Federal",
    "BOPMRG",   "Federal",
    "CAMENCW",  "Federal",
    "FLDADCI",  "Federal",
    "FLCHACI",  "Federal",
    "AKGSCCC",  "Federal",
    "NYGREAC",  "Federal",
    "NYGROVC",  "Federal",
    "NYFISHC",  "Federal",
    "NYMARCC",  "Federal",

    # ── Other/Unknown → Dedicated ─────────────────────────────────────────
    # Baker C.I.: Florida state immigration detention facility
    "FLBAKCI",  "Dedicated",
    # ICE processing / dedicated facilities
    "BPC",      "Dedicated",
    "BIINCCO",  "Dedicated",
    "CVANXCA",  "Dedicated",
    "FCLT8CA",  "Dedicated",
    "GCPFCKS",  "Dedicated",

    # ── Other/Unknown → Hold/Staging ──────────────────────────────────────
    "ALAMOTX",  "Hold/Staging",
    "CHMCINY",  "Hold/Staging",
    "EDNBGTX",  "Hold/Staging",
    "HRLGNTX",  "Hold/Staging",
    "IBPSMIA",  "Hold/Staging",
    "JFKTSNY",  "Hold/Staging",
    "LPD77CA",  "Hold/Staging",
    "PBDPDMA",  "Hold/Staging",
    "SMAHOLD",  "Hold/Staging",

    # ── Other/Unknown → Medical ───────────────────────────────────────────
    "UPMCAPA",  "Medical",

    # ── Other/Unknown → Family/Youth ──────────────────────────────────────
    "NRJDCVA",  "Family/Youth",

    # ── Federal → Non-Dedicated (county jails with USMS IGA contracts) ────
    "DENVECO",  "Non-Dedicated",
    "LACKAPA",  "Non-Dedicated",
    "LEXFCKY",  "Non-Dedicated",
    "LOUCOVA",  "Non-Dedicated",
    "MARIOFL",  "Non-Dedicated",
    "MESJACO",  "Non-Dedicated",
    "NORFOVA",  "Non-Dedicated",
    "RAPPSVA",  "Non-Dedicated",
    "SCOTTIA",  "Non-Dedicated",
    "SCOTTNE",  "Non-Dedicated",
    "SLSLCUT",  "Non-Dedicated",
    "SUFFONY",  "Non-Dedicated",
    "UNIONSD",  "Non-Dedicated",
    "VENTUCA",  "Non-Dedicated",
    "WAJAIMN",  "Non-Dedicated",
    "YELLOMT",  "Non-Dedicated"
  )
}

vera_detloc_matches <- function() {
  tibble::tribble(
    ~canonical_id, ~detloc,    ~match_type,
    # Name + city matches (fuzzy name >= 0.85, same city)
    9L,   "ALLENIN", "name_city",
    22L,  "BCORCPA", "name_city",
    24L,  "BWEPATX", "name_city",
    58L,  "CATAHLA", "name_city",
    87L,  "CISEPTX", "name_city",
    116L, "EMESACA", "name_city",
    160L, "HENDETX", "name_city",
    164L, "HIESATX", "name_city",
    165L, "HESPCAZ", "name_city",
    195L, "KITTIWA", "name_city",
    199L, "LPLCCAZ", "name_city",
    201L, "LQSNATX", "name_city",
    202L, "CSCLQTX", "name_city",
    272L, "OGLECIL", "name_city",
    307L, "RRFINWA", "name_city",
    311L, "RIOGRCO", "name_city",
    315L, "RIVERCA", "name_city",
    349L, "STORYIA", "name_city",
    352L, "ALESSAZ", "name_city",
    365L, "TAKARTX", "name_city",
    390L, "WINWYAZ", "name_city",
    # Address-confirmed (same street address, abbreviated name)
    12L,  "AAORDMD", "address",
    251L, "NATCHLA", "address",
    264L, "NOJUVOR", "address",
    # ZIP/city recovered (name match failed, ZIP or city lookup succeeded)
    89L,  "COWJVWA", "zip_city",
    111L, "DORCHMD", "zip_city",
    308L, "RENSSNY", "zip_city",
    396L, "YANCOSD", "zip_city"
  )
}
