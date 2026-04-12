# vera-institute.R
# Import functions for the Vera Institute ICE Detention Trends facility metadata.
#
# Source: https://github.com/vera-institute/ice-detention-trends
# Raw file: data/vera-institute/facilities.csv (downloaded manually)
#
# Provides 1,464 facility codes with geocoded locations, addresses, county,
# AOR, and facility type classifications.

# -- Definitions ──────────────────────────────────────────────────────────────────────

# Facility types categorized by Vera
facility_types_vera <- tibble::tribble(
  ~category_vera, ~type_detailed_ice, ~description_ice,
  "Non-Dedicated", "IGSA", "Inter-governmental Service Agreement: a facility operated by state/local government(s) or private contractors and falls under public ownership.",
  "Dedicated",     "DIGSA", "Dedicated IGSA.",
  "Dedicated",     "CDF",   "Contract Detention Facility: a facility that is owned by a private company and contracted directly with the government.",
  "Dedicated",     "SPC",   "Service Processing Center: a facility that is owned by the government and staffed by a combination of federal and contract employees.",
  "Federal",       "BOP",   "Bureau of Prisons: a facility operated by/under the management of the Bureau of Prisons.",
  "Federal",       "USMS CDF", "Private facility contracted with USMS.",
  "Federal",       "USMS IGA", "Intergovernment agreement in which ICE agrees to utilize an already established US Marshal Service contract.",
  "Federal",       "DOD",   "Department of Defense",
  "Federal",       "MOC",   "Migrant Operations Center",
  "Hold/Staging",  "Hold",  "Hold: a holding facility.",
  "Hold/Staging",  "Staging", "A facility used for Staging purposes.",
  "Family/Youth",  "Family", "Family: a facility in which families are able to remain together while awaiting their proceedings.",
  "Family/Youth",  "Juvenile", "Juvenile: an IGSA facility capable of housing juveniles (separate from adults) for a temporary period of time.",
  "Medical",       "Hospital", "Hospital: a medical facility.",
  "Hotel",         "Hotel",    "N/A: facilities coded by Vera.",
  "Other/Unknown", "Other",    "Other: facilities including but not limited to transportation-related facilities, hotels and/or other facilities.",
  "Other/Unknown", "Unknown",  "N/A: facilities for which Vera could not identify a facility type."
)

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
    # Apply manual type corrections; preserve originals in type_detailed / type_grouped
    dplyr::left_join(vera_type_overrides(), by = "detloc") |>
    dplyr::mutate(
      type_detailed_corrected = dplyr::coalesce(type_detailed_corrected, type_detailed),
      type_grouped_corrected  = dplyr::coalesce(type_grouped_corrected, type_grouped)
    )
}

# ── Vera → canonical DETLOC matches ─────────────────────────────────────────
# Manual matches for 28 canonical facilities that had no DETLOC from any other
# source. Matched by fuzzy name + city (21), address confirmation (3), and
# ZIP/city lookup (4). The 11 remaining no-DETLOC facilities are genuinely
# absent from Vera's data (CBP facilities, closed WV jails, etc.).

# ── Vera type corrections ──────────────────────────────────────────────────
# Manual corrections to Vera's type_detailed and type_grouped classifications.
# All overridden facilities had type_detailed of "Other" or "Unknown" and
# type_grouped of "Other/Unknown" in the original Vera data.
#
# Uppercase type_detailed_corrected values (BOP, SPC, CDF, STATE) are known
# ICE codes from the facility_types_vera vocabulary. Lowercase values
# (county_jail, ero_hold, sub_office) are internal project codes used when
# the ICE classification is unknown (e.g., county jails could be IGSA or
# USMS IGA depending on the contract arrangement).
#
# 42 facilities corrected. 7 former hold/staging overrides removed (police
# departments, courthouses, airport terminals) — insufficient evidence to
# reclassify.

vera_type_overrides <- function() {
  tibble::tribble(
    ~detloc,    ~type_detailed_corrected, ~type_grouped_corrected,

    # ── Other/Unknown → county_jail / Non-Dedicated ──────────────────────
    "ABIRJVA",  "county_jail", "Non-Dedicated",
    "ANDERSC",  "county_jail", "Non-Dedicated",
    "BARTOGA",  "county_jail", "Non-Dedicated",
    "BAYCOFL",  "county_jail", "Non-Dedicated",
    "BREVDFL",  "county_jail", "Non-Dedicated",
    "BROWNWI",  "county_jail", "Non-Dedicated",
    "CHFLDVA",  "county_jail", "Non-Dedicated",
    "COLUMFL",  "county_jail", "Non-Dedicated",
    # ICE annual stats: IGSA
    "EPCDFTX",  "IGSA",        "Non-Dedicated",
    "FCLT8CA",  "county_jail", "Non-Dedicated", # Facility 8, San Diego
    "FLGLRFL",  "county_jail", "Non-Dedicated",
    "FNDDUWI",  "county_jail", "Non-Dedicated",
    # ICE annual stats: USMS IGA
    "FRANKPA",  "USMS IGA",    "Federal",
#    "GCPFCKS",  "county_jail", "Non-Dedicated", # Garden City Processing @ Finney County Jail
    "GOODCID",  "county_jail", "Non-Dedicated",
    "JACKSTN",  "county_jail", "Non-Dedicated",
    "LASALTX",  "county_jail", "Non-Dedicated",
    "MRREGVA",  "county_jail", "Non-Dedicated",
#    "NASTRNY",  "county_jail", "Non-Dedicated", # "Nassau County [Detention Facility] ICE Trailer"
    "OSCEOFL",  "county_jail", "Non-Dedicated",
    "PIERCND",  "county_jail", "Non-Dedicated",
    "POTTRTX",  "county_jail", "Non-Dedicated",
    "PUTMAFL",  "county_jail", "Non-Dedicated",
    "SALINNE",  "county_jail", "Non-Dedicated",
    "SMNOLFL",  "county_jail", "Non-Dedicated",
    "SROSAFL",  "county_jail", "Non-Dedicated",
    "STJONFL",  "county_jail", "Non-Dedicated",
    "SUMTEFL",  "county_jail", "Non-Dedicated",
    "SUWANFL",  "county_jail", "Non-Dedicated",
    # ICE annual stats: IGSA
    "TGKJLFL",  "IGSA",        "Non-Dedicated",
    "UVALDTX",  "county_jail", "Non-Dedicated",
    "WALTNFL",  "county_jail", "Non-Dedicated",
    # The following were caught by the word 'jail' and inspected manually
   "ADAIRKY", "county_jail", "Non-Dedicated",
   "ALAMOCO", "county_jail", "Non-Dedicated",
   "ALEXAAL", "county_jail", "Non-Dedicated",
   "ANDRWTX", "county_jail", "Non-Dedicated",
   "ARTESNM", "county_jail", "Non-Dedicated",
   "ASHECNC", "county_jail", "Non-Dedicated",
   "BELMOOH", "county_jail", "Non-Dedicated",
   "CHENANY", "county_jail", "Non-Dedicated",
   "CHEROOK", "county_jail", "Non-Dedicated",
   "DAUPHPA", "county_jail", "Non-Dedicated",
   "DEKALGA", "county_jail", "Non-Dedicated",
   "ELKHAIN", "county_jail", "Non-Dedicated",
   "GRAHAAZ", "county_jail", "Non-Dedicated",
   "HAMILTX", "county_jail", "Non-Dedicated",
   "HARDEFL", "county_jail", "Non-Dedicated",
   "KANECIL", "county_jail", "Non-Dedicated",
   "LAKCOFL", "county_jail", "Non-Dedicated",
   "LAVACTX", "county_jail", "Non-Dedicated",
   "LIMCJTX", "county_jail", "Non-Dedicated",
   "MARTNTX", "county_jail", "Non-Dedicated",
   "MSKGNMI", "county_jail", "Non-Dedicated",
   "NASHUMA", "county_jail", "Non-Dedicated",
   "NRVRJVA", "county_jail", "Non-Dedicated",
   "PENDRNC", "county_jail", "Non-Dedicated",
   "SBARBCA", "county_jail", "Non-Dedicated",
   "SLOBICA", "county_jail", "Non-Dedicated",
   "ALAMOTX", "county_jail", "Non-Dedicated",
   "BRWNSTX", "county_jail", "Non-Dedicated",
   "EDNBGTX", "county_jail", "Non-Dedicated",
   "HDLGOTX", "county_jail", "Non-Dedicated",
   "HRLGNTX", "county_jail", "Non-Dedicated",
   "LAFERTX", "county_jail", "Non-Dedicated",
   "LFRESTX", "county_jail", "Non-Dedicated",
   "LPD77CA", "county_jail", "Non-Dedicated",
   "LUFKNTX", "county_jail", "Non-Dedicated",
   "MRCDSTX", "county_jail", "Non-Dedicated",
   "PLMVWTX", "county_jail", "Non-Dedicated",
   "PTISBTX", "county_jail", "Non-Dedicated",
   "SBNTOTX", "county_jail", "Non-Dedicated",
   "SJUANTX", "county_jail", "Non-Dedicated",
   "SPIPDTX", "county_jail", "Non-Dedicated",
   # The following were caught by the word 'Police' and inspected manually
   "ALAMOTX", "police_dept", "Non-Dedicated",
   "BRWNSTX", "police_dept", "Non-Dedicated",
   "EDNBGTX", "police_dept", "Non-Dedicated",
   "HDLGOTX", "police_dept", "Non-Dedicated",
   "HRLGNTX", "police_dept", "Non-Dedicated",
   "LAFERTX", "police_dept", "Non-Dedicated",
   "LFRESTX", "police_dept", "Non-Dedicated",
   "LPD77CA", "police_dept", "Non-Dedicated",
   "LUFKNTX", "police_dept", "Non-Dedicated",
   "MRCDSTX", "police_dept", "Non-Dedicated",
   "PLMVWTX", "police_dept", "Non-Dedicated",
   "PTISBTX", "police_dept", "Non-Dedicated",
   "SBNTOTX", "police_dept", "Non-Dedicated",
   "SJUANTX", "police_dept", "Non-Dedicated",
   "SPIPDTX", "police_dept", "Non-Dedicated",
"INDMPIN", "police_dept", "Non-Dedicated",
"PBDPDMA", "police_dept", "Non-Dedicated",
   # The following were caught by Corr or CI
   "FLBREVC", "county_jail", "Non-Dedicated",
   "HACTCND", "county_jail", "Non-Dedicated",
   "MERCEIL", "county_jail", "Non-Dedicated",
   "CACFLEO", "county_jail", "Non-Dedicated",
   "CACFDON", "state_prison", "Non-Dedicated",
   "DECCSMY", "state_prison", "Non-Dedicated",
   "FLBREVC", "state_prison", "Non-Dedicated",
   "FLCHACI", "state_prison", "Non-Dedicated",
   "FLMARIC", "state_prison", "Non-Dedicated",
   "ILPICKN", "state_prison", "Non-Dedicated",
   "INDCMIC", "state_prison", "Non-Dedicated",
   "NYLIVIC", "state_prison", "Non-Dedicated",
   "NYMARCC", "state_prison", "Non-Dedicated",
   "NYMDSTC", "state_prison", "Non-Dedicated",
   "NYMOHOC", "state_prison", "Non-Dedicated",
   "NYADIRC", "state_prison", "Non-Dedicated",
   "NYEASTC", "state_prison", "Non-Dedicated",
   "NYFISHC", "state_prison", "Non-Dedicated",
   "NYGREAC", "state_prison", "Non-Dedicated",
   "NYGROVC", "state_prison", "Non-Dedicated",
   "NYULSTC", "state_prison", "Non-Dedicated",
    # Name includes state prison
"AZSPFLO", "state_prison", "Non-Dedicated",
"AZSVCPC", "state_prison", "Non-Dedicated",
"CAIRONW", "state_prison", "Non-Dedicated",
"CASPCAL", "state_prison", "Non-Dedicated",
    # Individual state prisons
"CACCJAM", "state_prison", "Non-Dedicated",
"CAMENCE", "state_prison", "Non-Dedicated",
"CAMENCW", "state_prison", "Non-Dedicated",
"FLCHACI", "state_prison", "Non-Dedicated",
"FLSPSTA", "state_prison", "Non-Dedicated",
    # Name includes "County"
"BSQUETX", "county_jail", "Non-Dedicated",
"ECLECTX", "county_jail", "Non-Dedicated",
"GCLECOK", "county_jail", "Non-Dedicated",
"NASTRNY", "county_jail", "Non-Dedicated",
"SDPROCA", "county_jail", "Non-Dedicated",
"SMRVLTX", "county_jail", "Non-Dedicated",
    # other county centers
"ARTSINM", "county_jail", "Non-Dedicated",
"BRANCMI", "county_jail", "Non-Dedicated",
"CAWVALL", "county_jail", "Non-Dedicated",
"SONMACA", "county_jail", "Non-Dedicated",

    # ── Other/Unknown → BOP / Federal (from ICE annual stats) ─────────────
    "BOPATL",   "BOP",         "Federal",       # Atlanta U.S. Pen.
    "BOPLVN",   "BOP",         "Federal",       # Leavenworth USP
    "BOPPET",   "BOP",         "Federal",
    "BOPMRG",   "BOP",         "Federal",

    # ── Other/Unknown → USMS IGA / Federal (from ICE annual stats) ──────
    "EDNDCTX",  "USMS IGA",    "Federal",       # Eden Detention Ctr
    "NLSCOLA",  "USMS IGA",    "Federal",       # Nelson Coleman Corrections Center
    "SAUKCWI",  "USMS IGA",    "Federal",       # Sauk County Sheriff

    # ── Other/Unknown → IGSA / Non-Dedicated (from ICE annual stats) ────
    "BOURBKY",  "IGSA",        "Non-Dedicated", # Bourbon Co Det Center
    "LAKCOFL",  "IGSA",        "Non-Dedicated", # Lake County Jail

    # ── Other/Unknown → Dedicated (from ICE annual stats) ───────────────
    "FLBAKCI",  "STATE",       "Dedicated",     # Baker C.I.: FL state immigration facility (ICE: STATE)
    "FLDADCI",  "STATE",       "Dedicated",     # Dade Correctional Inst (ICE: STATE)
    "BPC",      "SPC",         "Dedicated",     # Boston SPC
    "BIINCCO",  "CDF",         "Dedicated",     # BI Inc (GEO Group subsidiary)
    "CVANXCA",  "CDF",         "Dedicated",     # Central Valley Annex
    "BOPNEO", "CDF",         "Dedicated", # Northeast Ohio Correctional Center (GEO Group)

    # ── Other/Unknown → TAP-ICE / Family/Youth (from ICE annual stats) ──
    "TAKARTX",  "TAP-ICE",     "Family/Youth",  # Trusted Adult Karnes FSC

    # ── Other/Unknown → Hold/Staging ─────────────────────────────────────
    "IBPSMIA",  "ero_hold",    "Hold/Staging",  # Miami Border Patrol
    "SMAHOLD",  "sub_office",  "Hold/Staging",  # Santa Maria Sub Office ERO

    # ── Other/Unknown → Hospital / Medical ───────────────────────────────
    "UPMCAPA",  "Hospital",    "Medical",

    # ── Other/Unknown → Juvenile / Family/Youth ──────────────────────────
    "NRJDCVA",  "Juvenile",    "Family/Youth"
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
    396L, "YANCOSD", "zip_city",
    # DDP-only matches (no DMCP entry; confirmed from DDP detention_facility_code)
    146L, "FULCJIN", "ddp_name",
    229L, "NEMCCOI", "ddp_name",
    401L, "DILLSAF", "ddp_name"
  )
}
