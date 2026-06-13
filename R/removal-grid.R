# R/removal-grid.R
# General-purpose removal destination frequency grid.
# build_removal_grid(stays, state_label, min_n = 5)
# plot_removal_grid(rg)

#' Build a nationality × departure-country frequency grid for removed stays.
#'
#' @param stays       A stays-level tibble with `stay_release_reason`,
#'                    `departure_country`, and `citizenship_country` columns.
#' @param state_label Display name for the location (used in the plot title).
#' @param min_n       Minimum number of removals for a nationality or destination
#'                    country to appear in the grid.
#' @return Named list: `grid` (long tibble), `state_label`, `n_total`,
#'         `n_third_country`.
build_removal_grid <- function(stays, state_label = "Nationwide", min_n = 5) {
  removed <- stays |>
    dplyr::filter(stay_release_reason == "Removed", !is.na(departure_country))

  # Unified country list: union of countries meeting min_n on either axis,
  # ranked by max(cit_total, dep_total) so the same order applies to both axes
  # and same-country cells fall on the diagonal.
  cit_counts <- removed |>
    dplyr::count(citizenship_country, name = "cit_total")
  dep_counts <- removed |>
    dplyr::count(departure_country, name = "dep_total")

  country_order <- dplyr::full_join(
    cit_counts, dep_counts,
    by = c("citizenship_country" = "departure_country")
  ) |>
    dplyr::rename(country = citizenship_country) |>
    dplyr::mutate(
      cit_total = tidyr::replace_na(cit_total, 0L),
      dep_total = tidyr::replace_na(dep_total, 0L),
      combined  = pmax(cit_total, dep_total)
    ) |>
    dplyr::filter(combined >= min_n) |>
    dplyr::arrange(dplyr::desc(combined)) |>
    dplyr::pull(country)

  # Square cross-join with the same country list on both axes
  grid <- tidyr::expand_grid(
    citizenship_country = country_order,
    departure_country   = country_order
  ) |>
    dplyr::left_join(
      removed |> dplyr::count(citizenship_country, departure_country),
      by = c("citizenship_country", "departure_country")
    ) |>
    dplyr::mutate(
      n = tidyr::replace_na(n, 0L),
      # Apply the same order to both axes: descending on y, ascending on x
      citizenship_country = factor(citizenship_country, levels = rev(country_order)),
      departure_country   = factor(departure_country,   levels = country_order)
    )

  list(
    grid            = grid,
    state_label     = state_label,
    n_total         = nrow(removed),
    n_third_country = removed |>
      dplyr::filter(citizenship_country != departure_country) |>
      nrow()
  )
}

#' Plot a removal destination frequency grid.
#'
#' @param rg  The list returned by `build_removal_grid()`.
#' @return A ggplot object.
plot_removal_grid <- function(rg) {
  lbl <- function(x) ifelse(x == 0, "", as.character(x))

  ggplot2::ggplot(
    rg$grid,
    ggplot2::aes(x = departure_country, y = citizenship_country, fill = log1p(n))
  ) +
    ggplot2::geom_tile(color = "white", linewidth = 0.4) +
    ggplot2::geom_text(
      ggplot2::aes(label = lbl(n), color = n > 20),
      size = 2.7
    ) +
    ggplot2::scale_fill_gradient(
      low    = "#d9eaf7",
      high   = "#1a4f7a",
      name   = "Count\n(log scale)",
      labels = function(x) round(expm1(x))
    ) +
    ggplot2::scale_color_manual(
      values = c("FALSE" = "#555", "TRUE" = "white"),
      guide  = "none"
    ) +
    ggplot2::labs(
      x     = "Removed to (departure country)",
      y     = "Citizenship country",
      title = paste0(
        "Nationality vs. removal destination \u2014 ",
        rg$state_label, " ICE arrests"
      )
    ) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      # Center title over the full figure (including y-axis labels), not just panel
      plot.title          = ggplot2::element_text(hjust = 0.5),
      plot.title.position = "plot",
      axis.text.x         = ggplot2::element_text(angle = 40, hjust = 1, size = 9),
      axis.text.y         = ggplot2::element_text(size = 9),
      panel.grid          = ggplot2::element_blank(),
      legend.position     = "right"
    )
}
