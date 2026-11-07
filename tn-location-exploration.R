library(dplyr)

tar_load(arrests_raw)
arrests_raw |> dplyr::filter(apprehension_state=="TENNESSEE") -> tn_arrests_raw

tn_arrests_raw |> count(apprehension_site_landmark) |> arrange(desc(n)) |> print(n=50)

tn_arrests_raw |> count(apprehension_site_landmark) |> arrange(desc(n)) |> mutate(notes = " ") |> head(30) |> kableExtra::kable()

tn_arrests_raw |> dplyr::filter(str_detect(apprehension_site_landmark, "NON-SPECIFIC")) |> nrow()

tn_arrests_raw |> dplyr::filter(str_detect(apprehension_site_landmark, "NON-SPECIFIC")) |>
  count(apprehension_site_landmark) |> arrange(desc(n)) |> print(n=15)

tn_arrests_raw |>
  dplyr::filter(str_detect(apprehension_site_landmark, "NON-SPECIFIC")) |>
  count(apprehension_site_landmark) |>
  mutate(aor_code = str_sub(apprehension_site_landmark, 1,3)) |>
  arrange(desc(n)) -> tn_general_areas
pull(tn_general_areas, aor_code) -> tn_general_area_codes


# FUGITIVE OPERATIONS ON STREET
# GENERAL AREA, NON-SPECIFIC
# US Penitentiary
# ICE OFFICE
# STREET ARREST
# FUGITIVE OPERATIONS ON STREET

tn_arrests_raw <- tn_arrests_raw |>
  dplyr::mutate(loc_type = case_when(
    str_detect(apprehension_site_landmark, "FUGITIVE OPERATION") ~ "FUGITIVE OPS",
    str_detect(apprehension_site_landmark, "GENERAL AREA, NON-SPECIFIC") ~ "GENERAL AREA, NON-SPECIFIC",
    str_detect(apprehension_site_landmark, "COUNTY JAIL, TN") ~ "COUNTY JAIL (TN)",
    str_detect(apprehension_site_landmark, "COUNTY JAIL MS STATE") ~ "COUNTY JAIL (MS)",
    str_detect(apprehension_site_landmark, "COUNTY JAIL") ~ "COUNTY JAIL (unmatched)",
    str_detect(apprehension_site_landmark, "ERO OFFICE") ~ "ERO OFFICE",
    str_detect(apprehension_site_landmark, "POLICE DEPARTMENT") ~ "POLICE",
    str_detect(apprehension_site_landmark, "US Penitentiary") ~ "US Penitentiary",
    str_detect(apprehension_site_landmark, "IL STATE DOC") ~ "State Prison",
    str_detect(apprehension_site_landmark, "ICE OFFICE") ~ "ICE OFFICE",
    str_detect(apprehension_site_landmark, "STREET ARREST") ~ "STREET ARREST",
    str_detect(toupper(apprehension_site_landmark), "COUNTY") ~ "COUNTY",
    TRUE ~ "OTHER"
  ))

tn_arrests_raw |> count(loc_type) |> arrange(desc(n)) |> print(n=50)
tn_arrests_raw |> dplyr::filter(loc_type == "OTHER") |> count(apprehension_site_landmark) |> arrange(desc(n)) |> print(n=50)

tn_arrests_raw |> dplyr::filter(loc_type == "FUGITIVE OPS") |> count(apprehension_site_landmark) |> arrange(desc(n)) |> print(n=50)

tn_arrests_raw |> dplyr::filter(loc_type == "State Prison") |> count(apprehension_site_landmark) |> arrange(desc(n)) |> print(n=50)

arrests_raw |>
  dplyr::mutate(loc_type = case_when(
    str_detect(apprehension_site_landmark, "FUGITIVE OPERATIONS ON STREET") ~ "FUGITIVE OPS",
    str_detect(apprehension_site_landmark, "GENERAL AREA, NON-SPECIFIC") ~ "GENERAL AREA, NON-SPECIFIC",
    str_detect(apprehension_site_landmark, "GENERAL AREA NON-SPECIFIC") ~ "GENERAL AREA, NON-SPECIFIC",
    str_detect(apprehension_site_landmark, "US Penitentiary") ~ "US Penitentiary",
    str_detect(apprehension_site_landmark, "IL STATE DOC") ~ "State Prison",
    str_detect(apprehension_site_landmark, "ICE OFFICE") ~ "ICE OFFICE",
    str_detect(apprehension_site_landmark, "STREET ARREST") ~ "STREET ARREST",
    str_detect(toupper(apprehension_site_landmark), "COUNTY") ~ "COUNTY",
    TRUE ~ "OTHER"
  )) |> count(loc_type)

# Minnesota; 8235 arrests
arrests_raw |> dplyr::filter(apprehension_state=="MINNESOTA") -> mn_arrests_raw
mn_arrests_raw |> count(apprehension_site_landmark) |> arrange(desc(n)) |> print(n=50)

mn_arrests_raw <- mn_arrests_raw |>
  dplyr::mutate(loc_type = case_when(
    str_detect(apprehension_site_landmark, "FUGITIVE OPERATIONS ON STREET") ~ "FUGITIVE OPS",
    str_detect(apprehension_site_landmark, "GENERAL AREA, NON-SPECIFIC") ~ "GENERAL AREA, NON-SPECIFIC",
    str_detect(apprehension_site_landmark, "GENERAL AREA NON-SPECIFIC") ~ "GENERAL AREA, NON-SPECIFIC",
    str_detect(apprehension_site_landmark, "US Penitentiary") ~ "US Penitentiary",
    str_detect(apprehension_site_landmark, "IL STATE DOC") ~ "State Prison",
    str_detect(apprehension_site_landmark, "ICE OFFICE") ~ "ICE OFFICE",
    str_detect(apprehension_site_landmark, "STREET ARREST") ~ "STREET ARREST",
    str_detect(toupper(apprehension_site_landmark), "COUNTY JAIL") ~ "COUNTY JAIL",
    str_detect(toupper(apprehension_site_landmark), "COUNTY") ~ "COUNTY",
    TRUE ~ "OTHER"
  ))
mn_arrests_raw |> count(loc_type)
mn_arrests_raw |> distinct(apprehension_site_landmark, loc_type) |> count(loc_type) |> rename(n_distinct = n)

mn_arrests_raw |> dplyr::filter(loc_type=="OTHER") |> count(apprehension_site_landmark)

tn_arrests_raw |> count(apprehension_site_landmark) |> arrange(desc(n)) |> mutate(notes = " ") |> head(30) |> kableExtra::kable()



tn_arrests_raw |> dplyr::filter(str_detect(apprehension_site_landmark, "NON-SPECIFIC")) |> nrow()

tn_arrests_raw |> dplyr::filter(str_detect(apprehension_site_landmark, "NON-SPECIFIC")) |> count(apprehension_site_landmark) |> arrange(desc(n)) |> print(n=50)

tn_arrests_raw |>
  dplyr::filter(str_detect(apprehension_site_landmark, "NON-SPECIFIC")) |>
  count(apprehension_site_landmark) |>
  mutate(aor_code = str_sub(apprehension_site_landmark, 1,3)) |>
  arrange(desc(n)) -> tn_general_areas
pull(tn_general_areas, aor_code) -> tn_general_area_codes
