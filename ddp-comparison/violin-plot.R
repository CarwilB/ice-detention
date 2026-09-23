
df <- bind_rows(
  biden_unmatched |> filter(peak_pop > 1) |> mutate(admin = "Biden (unmatched)"),
  trump_unmatched |> filter(peak_pop > 1) |> mutate(admin = "Trump (unmatched)")
)

# Quartiles + fences + "upper whisker" (max non-outlier) per group
stats <- df |>
  group_by(admin) |>
  summarise(
    q25 = unname(quantile(peak_pop, 0.25, na.rm = TRUE, type = 7)),
    q75 = unname(quantile(peak_pop, 0.75, na.rm = TRUE, type = 7)),
    .groups = "drop"
  ) |>
  mutate(
    iqr = q75 - q25,
    hi  = q75 + 1.5 * iqr
  )

upper_whisker <- df |>
  inner_join(stats, by = "admin") |>
  filter(peak_pop <= hi) |>
  group_by(admin) |>
  summarise(upper_whisker = max(peak_pop, na.rm = TRUE), .groups = "drop")

# Choose the 5 "right-side" and 5 "left-side" outliers from the upper tail (above 75th percentile)
# - Right: the largest 5
# - Left:  the next-largest 5 (so we can label 10 total, 5 per side)
q75 <- stats$q75
hi <- stats$hi

top6_upper <- df |>
  inner_join(stats, by = "admin") |>
  filter(peak_pop > q75) |>
  arrange(admin, desc(peak_pop)) |>
  group_by(admin) |>
  slice_head(n = 6) |>
  mutate(rank_desc = row_number()) |>
  ungroup()

out_right3 <- top6_upper |>
  filter(rank_desc <= 3) |>
  mutate(
    side = "right",
    label_txt = paste0(comma(round(peak_pop)), " ", detention_facility),
    nudge_x = 0.05,
    hjust = 0
  )

out_left3 <- top6_upper |>
  filter(rank_desc > 3) |>
  mutate(
    side = "left",
    label_txt = paste0(detention_facility, " ", comma(round(peak_pop))),
    nudge_x = -0.05,
    hjust = 1
  )

outliers_labeled <- bind_rows(out_left3, out_right3)

# "and X other facilities" where X = (# above 75%) - 10 labeled
other_count <- df |>
  inner_join(stats, by = "admin") |>
  group_by(admin) |>
  summarise(
    n_above_q75 = sum(peak_pop > q75, na.rm = TRUE),
    .groups = "drop"
  ) |>
  mutate(
    labeled = pmin(n_above_q75, 10L),
    other = pmax(n_above_q75 - labeled, 0L)
  ) |>
  inner_join(upper_whisker, by = "admin") |>
  mutate(
    y_annot = 2* sqrt(q75 * hi),  # halfway on a log scale (geometric mean)
    annot_txt = paste0("and ", other, " other facilities\nwith peak population > 75th percentile")
  )

violin_plot <- ggplot(df, aes(x = admin, y = peak_pop, fill = admin)) +
  geom_violin(trim = FALSE, alpha = 0.45, color = NA) +
  geom_boxplot(width = 0.15, outlier.shape = NA, alpha = 0.55) +

  # points for the labeled outliers (10 total, 5 on each side)
  geom_point(
    data = outliers_labeled,
    aes(x = admin, y = peak_pop),
    inherit.aes = FALSE,
    shape = 21,
    size = 2.4,
    stroke = 0.25,
    color = "black",
    fill = "white"
  ) +

  # detention_facility labels, alternating sides via nudge + hjust
  ggrepel::geom_text_repel(
    data = outliers_labeled,
    aes(x = admin, y = peak_pop, label = label_txt, hjust = hjust),
    inherit.aes = FALSE,
    nudge_x = outliers_labeled$nudge_x,
    size = 3.0,
    color = "grey10"
  ) +

  # quartile labels (values on original scale)
  geom_text(
    data = stats,
    aes(x = admin, y = q25, label = paste0("25%: ", comma(round(q25)))),
    inherit.aes = FALSE,
    vjust = 1.4,
    size = 3.2,
    color = "grey20"
  ) +
  geom_text(
    data = stats,
    aes(x = admin, y = q75, label = paste0("75%: ", comma(round(q75)))),
    inherit.aes = FALSE,
    vjust = -0.6,
    size = 3.2,
    color = "grey20"
  ) +

  # "and X other facilities" annotation halfway up the top whisker
  geom_text(
    data = other_count,
    aes(x = admin, y = y_annot, label = annot_txt),
    inherit.aes = FALSE,
    size = 3.1,
    color = "grey25"
  ) +

  scale_y_log10(labels = comma) +
  # add horizontal room so left/right labels have space
  scale_x_discrete(expand = expansion(mult = c(0.35, 0.35))) +
  labs(x = NULL, y = "Peak detained population (log10 scale)") +
  theme_minimal(base_size = 12) +
  theme(legend.position = "none") +
  scale_fill_manual(
    values = c(
      "Biden (unmatched)" = "#377EB8",  # put the color you want here
      "Trump (unmatched)" = "#E41A1C"
    )
  )
