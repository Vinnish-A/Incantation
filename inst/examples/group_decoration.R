suppressPackageStartupMessages({
  library(incantation)
  library(ggplot2)
  library(patchwork)
})

panel_theme = theme_minimal(base_size = 10) +
  theme(
    panel.grid.minor = element_blank(),
    plot.margin = margin(30, 10, 12, 10, "pt"),
    plot.title = element_text(face = "bold")
  )

p1 = ggplot(mtcars, aes(wt, mpg, colour = factor(cyl))) +
  geom_point(size = 2) +
  labs(title = "Pseudotime", x = "UMAP 1", y = "UMAP 2", colour = "Cylinders") +
  panel_theme

p2 = ggplot(mtcars, aes(wt, hp, colour = factor(gear))) +
  geom_point(size = 2) +
  labs(title = "Tumor phase", x = "UMAP 1", y = "UMAP 2", colour = "Phase") +
  panel_theme

p3 = ggplot(mtcars, aes(wt, qsec, colour = factor(am))) +
  geom_point(size = 2) +
  labs(title = "Time point", x = "UMAP 1", y = "UMAP 2", colour = "Transmission") +
  panel_theme

scene = incant(p1 + p2 + p3, width = 11, height = 4.5) |>
  decorate_group(
    plots = 1:3,
    title = "Tumor cell (Stereo-seq)",
    id = "tumor-cell",
    trim = c(5, 8),
    gap = 4,
    title_gap = 5,
    title_face = "bold",
    title_size = 15
  )

draw(scene)
