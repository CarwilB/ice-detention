# This script refines the overrides list in vera-institute.R
#
# My diagnostic tools ofr this are in vera-overrides-purrr-list.R
#
# Current goal is to parse out the items with type_grouped of "Other/Unknown"
#
# We're working on a universe of 141 entries
#
# At the start, there are 42 already overriden
vera_facilities |> filter(type_grouped=="Other/Unknown") |> filter((detloc %in% vera_overrides$all)) |> nrow()
# Here's the breakdown
cat("Don't forget to tar_load(vera_facilties)")
vera_facilities |> filter(type_grouped=="Other/Unknown")  |> count(type_grouped_corrected)
# type_grouped_corrected     n
# <chr>                  <int>
#   1 Dedicated                  4
# 2 Family/Youth               1
# 3 Federal                    2
# 4 Hold/Staging               2
# 5 Medical                    1
# 6 Non-Dedicated             32
# 7 Other/Unknown             99

# How many still Other/Unknown
vera_facilities |> filter(type_grouped_corrected=="Other/Unknown") |> nrow()

# Here's the code to generate new code (metacoding) for
# all facilities with "Jail" in the name:
vera_facilities |> filter(type_grouped=="Other/Unknown") |>
  filter(str_detect(facility_name, "Jail")) |>
  filter(!(detloc %in% vera_overrides$all)) |>
  mutate(override_line = str_glue("   \"{detloc}\", \"county_jail\", \"Non-Dedicated\",")) |>
  pull(override_line)
# This generates 26 rows of code, which are added to vera-instute under the comment
# The following were caught by the word 'jail' and inspected manually.

# From here on out we keep excluding prior searches so that our search
# is additive.

# Police as keyword
vera_facilities |> filter(type_grouped=="Other/Unknown") |>
  filter(!str_detect(facility_name, "Jail")) |>  # negate prior rule 1
  filter(str_detect(facility_name, "Police")) |>
  filter(!(detloc %in% vera_overrides$all)) |>
  pull(facility_name)

vera_facilities |> filter(type_grouped=="Other/Unknown") |>
  filter(!str_detect(facility_name, "Jail")) |>  # negate prior rule 1
  filter(str_detect(facility_name, "Police")) |>
  filter(!(detloc %in% vera_overrides$all)) |>
  mutate(override_line = str_glue("   \"{detloc}\", \"police_dept\", \"Non-Dedicated\",")) |>
  pull(override_line)
# nrow = 15

# Fed.Corr.Inst. as keyword
vera_facilities |> filter(type_grouped=="Other/Unknown") |>
  filter(!str_detect(facility_name, "Jail")) |>  # negate prior rule 1
  filter(!str_detect(facility_name, "Police")) |>
  filter(str_detect(facility_name, "Fed.Corr.Inst.")) |>
  filter(!(detloc %in% vera_overrides$all)) |>
  pull(facility_name)
# nrow = 0

# check in on whether any unknown facilities are
# in the canonical list
vera_facilities_unknown <- vera_facilities |> filter(type_grouped_corrected=="Other/Unknown")
# Match with FY19-26 list
vera_facilities_unknown |> select(detloc, facility_name, facility_city, facility_state, type_grouped_corrected) |>
  left_join(canonical_facilities)|> filter(!is.na(canonical_name)) |>
  select(detloc, facility_name, canonical_name, canonical_id, type_grouped_corrected) |>
  arrange(canonical_id) -> vera_canonical_matched
vera_canonical_matched
# nrow = 12
# It turns out we missed these in the matching up.

# Corr[ection] as keyword
vera_facilities |> filter(type_grouped=="Other/Unknown") |>
  filter(!str_detect(facility_name, "Jail")) |>  # negate prior rule 1
  filter(!str_detect(facility_name, "Police")) |>
  filter(str_detect(facility_name, "Corr|CI")) |>
  filter(!(detloc %in% vera_overrides$all)) |>
  select(detloc, facility_name, facility_address, facility_city, facility_state)

vera_facilities |> filter(type_grouped=="Other/Unknown") |>
  filter(!str_detect(facility_name, "Jail")) |>  # negate prior rule 1
  filter(!str_detect(facility_name, "Police")) |>
  filter(!(detloc %in% vera_overrides$all)) |>
  filter(str_detect(facility_name, "Corr|CI")) |>
  mutate(override_line = str_glue("   \"{detloc}\", \"county_jail\", \"Non-Dedicated\",")) |>
  mutate(override_line_2 = str_glue("   \"{detloc}\", \"state_prison\", \"Non-Dedicated\",")) |>
  pull(override_line_2)

# Correctional facility
vera_facilities |> filter(type_grouped=="Other/Unknown") |>
  filter(!str_detect(facility_name, "Jail")) |>  # negate prior rule 1
  filter(!str_detect(facility_name, "Police")) |>
  filter(str_detect(facility_name, "CF|C.F|C.I")) |>
  filter(!(detloc %in% vera_overrides$all)) |>
  select(detloc, facility_name, facility_address, facility_city, facility_state) -> vf_ci

vera_facilities |> filter(type_grouped=="Other/Unknown") |>
  filter(!str_detect(facility_name, "Jail")) |>  # negate prior rule 1
  filter(!str_detect(facility_name, "Police")) |>
  filter(str_detect(facility_name, "CF|C.F|C.I")) |>
  filter(!(detloc %in% vera_overrides$all)) |>
  mutate(override_line = str_glue("   \"{detloc}\", \"county_jail\", \"Non-Dedicated\",")) |>
  mutate(override_line_2 = str_glue("   \"{detloc}\", \"state_prison\", \"Non-Dedicated\",")) |>
  pull(override_line_2)

# Prison
vera_facilities |> filter(type_grouped=="Other/Unknown") |>
  filter(!str_detect(facility_name, "Jail")) |>  # negate prior rule 1
  filter(!str_detect(facility_name, "Police")) |>
  filter(!str_detect(facility_name, "CF|C.F|C.I")) |>
  filter(str_detect(facility_name, "Prison")) |>
  filter(!(detloc %in% vera_overrides$all)) |>
  select(detloc, facility_name, facility_address, facility_city, facility_state)

vera_facilities |> filter(type_grouped=="Other/Unknown") |>
  filter(!str_detect(facility_name, "Jail")) |>  # negate prior rule 1
  filter(!str_detect(facility_name, "Police")) |>
  filter(!str_detect(facility_name, "CF|C.F|C.I")) |>
  filter(str_detect(facility_name, "Prison")) |>
  filter(!(detloc %in% vera_overrides$all)) |>
  mutate(override_line_2 = str_glue("   \"{detloc}\", \"state_prison\", \"Non-Dedicated\",")) |>
  pull(override_line_2)

# County
vera_facilities |> filter(type_grouped=="Other/Unknown") |>
  filter(!str_detect(facility_name, "Jail")) |>  # negate prior rule 1
  filter(!str_detect(facility_name, "Police")) |>
  filter(!str_detect(facility_name, "CF|C.F|C.I|Corr")) |>
  filter(!str_detect(facility_name, "Prison")) |>
  filter(str_detect(facility_name, "County")) |>
  filter(!(detloc %in% vera_overrides$all)) |>
  pull(facility_name)

vera_facilities |> filter(type_grouped=="Other/Unknown") |>
  filter(!str_detect(facility_name, "Jail")) |>  # negate prior rule 1
  filter(!str_detect(facility_name, "Police")) |>
  filter(!str_detect(facility_name, "CF|C.F|C.I|Corr")) |>
  filter(!str_detect(facility_name, "Prison")) |>
  filter(str_detect(facility_name, "County")) |>
  filter(!(detloc %in% vera_overrides$all)) |>
  mutate(override_line = str_glue("   \"{detloc}\", \"county_jail\", \"Non-Dedicated\",")) |>
  pull(override_line)

# Further police pattern
vera_facilities |> filter(type_grouped=="Other/Unknown") |>
  filter(!str_detect(facility_name, "Jail")) |>  # negate prior rule 1
  filter(!str_detect(facility_name, "Police")) |>
  filter(!str_detect(facility_name, "CF|C.F|C.I|Corr")) |>
  filter(!str_detect(facility_name, "Prison")) |>
  filter(!str_detect(facility_name, "County")) |>
  filter(str_detect(facility_name, "PD|P.D"))

vera_facilities |> filter(type_grouped=="Other/Unknown") |>
  filter(!str_detect(facility_name, "Jail")) |>  # negate prior rule 1
  filter(!str_detect(facility_name, "Police")) |>
  filter(!str_detect(facility_name, "CF|C.F|C.I|Corr")) |>
  filter(!str_detect(facility_name, "Prison")) |>
  filter(!str_detect(facility_name, "County")) |>
  filter(str_detect(facility_name, "PD|P.D")) |>
  mutate(override_line = str_glue("   \"{detloc}\", \"police_dept\", \"Non-Dedicated\",")) |>
  pull(override_line)

# Some prison patterns…
vera_facilities |> filter(type_grouped=="Other/Unknown") |>
  filter(!str_detect(facility_name, "Jail")) |>  # negate prior rule 1
  filter(!str_detect(facility_name, "Police")) |>
  filter(!str_detect(facility_name, "CF|C.F|C.I|Corr")) |>
  filter(!str_detect(facility_name, "Prison")) |>
  filter(!str_detect(facility_name, "County")) |>
  filter(!str_detect(facility_name, "PD|P.D")) |>
  filter(str_detect(facility_name, "Men Colony|SCC/Jamestown|Charlotte CI|St. Pris.")) |>
  filter(!(detloc %in% vera_overrides$all)) |> pull(facility_name)

vera_facilities |> filter(type_grouped=="Other/Unknown") |>
  filter(!str_detect(facility_name, "Jail")) |>  # negate prior rule 1
  filter(!str_detect(facility_name, "Police")) |>
  filter(!str_detect(facility_name, "CF|C.F|C.I|Corr")) |>
  filter(!str_detect(facility_name, "Prison")) |>
  filter(!str_detect(facility_name, "County")) |>
  filter(!str_detect(facility_name, "PD|P.D")) |>
  filter(str_detect(facility_name, "Men Colony|SCC/Jamestown|Charlotte CI|St. Pris.")) |>
  filter(!(detloc %in% vera_overrides$all)) |>
  mutate(override_line_2 = str_glue("   \"{detloc}\", \"state_prison\", \"Non-Dedicated\",")) |>
  pull(override_line_2)

# everything else
# I named four of these acounty jails
vera_facilities |> filter(type_grouped=="Other/Unknown") |>
  filter(!str_detect(facility_name, "Jail")) |>  # negate prior rule 1
  filter(!str_detect(facility_name, "Police")) |>
  filter(!str_detect(facility_name, "CF|C.F|C.I|Corr")) |>
  filter(!str_detect(facility_name, "Prison")) |>
  filter(!str_detect(facility_name, "County")) |>
  filter(!str_detect(facility_name, "PD|P.D")) |>
  filter(!str_detect(facility_name, "Men Colony|SCC/Jamestown|Charlotte CI|St. Pris.")) |>
  filter(!(detloc %in% vera_overrides$all)) |>
  mutate(override_line = str_glue("   \"{detloc}\", \"county_jail\", \"Non-Dedicated\",")) |>
  pull(override_line)
