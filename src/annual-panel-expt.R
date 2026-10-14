ddp_annual_panel |>
     dplyr::filter(fiscal_year == "FY25", is.na(canonical_id)) |>
    dplyr::select(detloc, detention_facility, facility_state, adp, peak_population) |>
     dplyr::arrange(dplyr::desc(adp))  |>
  arrange(desc(peak_population)) |>
  print(n = 30)

ddp_annual_panel |>
  dplyr::filter(fiscal_year == "FY26", is.na(canonical_id)) |>
  dplyr::select(detloc, detention_facility, facility_state, adp, peak_population) |>
  dplyr::arrange(dplyr::desc(adp))  |>
  arrange(desc(peak_population)) |>
  print(n = 30)

ddp_annual_panel |>
  dplyr::filter(fiscal_year == "FY24", is.na(canonical_id)) |>
  dplyr::select(detloc, detention_facility, facility_state, adp, peak_population) |>
  dplyr::arrange(dplyr::desc(adp))  |>
  arrange(desc(peak_population)) |>
  print(n = 30)

ddp_annual_panel |>
     dplyr::filter(fiscal_year == "FY25", is.na(canonical_id)) |>
     dplyr::summarise(
         adp_gt2  = sum(adp >= 2),
         adp_lt2  = sum(adp < 2),
         adp_max  = max(adp),
         adp_median = median(adp)
       )
