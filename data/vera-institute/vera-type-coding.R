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
