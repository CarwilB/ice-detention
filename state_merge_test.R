targets::tar_source()

arrests_raw <- targets::tar_read(arrests_raw)
stays_raw   <- targets::tar_read(stays_raw)
detloc_lkp  <- targets::tar_read(detloc_lookup_complete)
geo_all     <- readr::read_csv("data/facilities-geocoded-all.csv", show_col_types = FALSE)

d_il <- build_state_arrests_data(arrests_raw, stays_raw, detloc_lkp, geo_all,
                                 state = "ILLINOIS")

cat("IL county_counts:", nrow(d_il$county_counts), "rows |", "n_arrests:", d_il$n_arrests, "\n")

arrests_raw  <- targets::tar_read(arrests_aug_raw)
stays_raw    <- targets::tar_read(stays_aug_raw)
place_county <- targets::tar_read(place_county)

d_il <- build_state_arrests_data(arrests_raw, stays_raw, detloc_lkp, geo_all,
                                 state = "ILLINOIS", place_county = place_county)
