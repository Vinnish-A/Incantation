suppressPackageStartupMessages({
  library(pkgload)
  load_all(".", quiet = TRUE)
  library(ggplot2)
  library(patchwork)
  library(grid)
})

output_dir = "man/figures"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

readme_theme = theme_minimal(base_size = 11) +
  theme(
    plot.title = element_text(face = "bold", size = 12),
    plot.subtitle = element_text(colour = "#667085", size = 9),
    panel.grid.minor = element_blank(),
    plot.margin = margin(14, 14, 14, 14, "pt")
  )

save_scene = function(scene, filename, debug = FALSE, res = 150) {
  device = scene$device
  width = incantation:::.units_to_inches(device$width, device$units)
  height = incantation:::.units_to_inches(device$height, device$units)
  grDevices::png(filename, width = width, height = height, units = "in",
                 res = res, bg = "white")
  on.exit(grDevices::dev.off(), add = TRUE)
  grid::grid.newpage()
  grid::grid.draw(render(scene, debug = debug))
  invisible(filename)
}

save_row = function(scenes, labels, filename, width, height, res = 150) {
  count = length(scenes)
  grDevices::png(filename, width = width * count, height = height + 0.34,
                 units = "in", res = res, bg = "white")
  on.exit(grDevices::dev.off(), add = TRUE)
  grid::grid.newpage()
  grid::pushViewport(grid::viewport(layout = grid::grid.layout(
    2, count,
    widths = grid::unit(rep(width, count), "in"),
    heights = grid::unit(c(0.34, height), "in")
  )))
  lapply(seq_len(count), function(i) {
    grid::pushViewport(grid::viewport(layout.pos.row = 1, layout.pos.col = i))
    grid::grid.text(labels[[i]], gp = grid::gpar(
      fontsize = 12, fontface = "bold", col = "#344054"
    ))
    grid::popViewport()
    grid::pushViewport(grid::viewport(layout.pos.row = 2, layout.pos.col = i))
    grid::grid.draw(render(scenes[[i]]))
    grid::popViewport()
  })
  grid::popViewport()
  invisible(filename)
}

save_backend_grid = function(scenes, labels, filename, width, height, res = 150) {
  grDevices::png(filename, width = width * 2, height = (height + 0.3) * 2,
                 units = "in", res = res, bg = "white")
  on.exit(grDevices::dev.off(), add = TRUE)
  grid::grid.newpage()
  grid::pushViewport(grid::viewport(layout = grid::grid.layout(
    4, 2,
    widths = grid::unit(rep(width, 2), "in"),
    heights = grid::unit(rep(c(0.3, height), 2), "in")
  )))
  lapply(seq_along(scenes), function(i) {
    column = (i - 1) %% 2 + 1
    title_row = if (i <= 2) 1 else 3
    plot_row = title_row + 1
    grid::pushViewport(grid::viewport(layout.pos.row = title_row, layout.pos.col = column))
    grid::grid.text(labels[[i]], gp = grid::gpar(
      fontsize = 11, fontface = "bold", col = "#344054"
    ))
    grid::popViewport()
    grid::pushViewport(grid::viewport(layout.pos.row = plot_row, layout.pos.col = column))
    grid::grid.draw(render(scenes[[i]]))
    grid::popViewport()
  })
  grid::popViewport()
  invisible(filename)
}

base_scatter = function(y, colour, title) {
  ggplot(mtcars, aes(wt, {{ y }})) +
    geom_point(size = 2.1, colour = colour, alpha = 0.85) +
    labs(title = title, x = "Weight") +
    readme_theme
}

blue = "#2F6B9A"
red = "#B5475A"
purple = "#6941C6"
green = "#17816F"

p_mpg = base_scatter(mpg, blue, "Fuel economy") + labs(y = "MPG")
p_hp = base_scatter(hp, red, "Engine power") + labs(y = "Horsepower")
p_qsec = base_scatter(qsec, green, "Quarter mile") + labs(y = "Seconds")

# Hero and group decoration ---------------------------------------------------
triptych = (p_mpg + p_hp + p_qsec) &
  theme(plot.margin = margin(34, 12, 12, 12, "pt"))
hero = incant(triptych, width = 11.4, height = 3.8) |>
  decorate_group(
    1:3, "Post-layout group decoration", id = "hero-group",
    gap = 3, title_gap = 4, trim = c(6, 10),
    line_colour = purple, title_colour = purple, title_face = "bold"
  )
save_scene(hero, file.path(output_dir, "readme-decoration.png"))

# Inspect and measure ---------------------------------------------------------
inspect_plot = (p_mpg + p_hp) /
  (p_qsec + patchwork::plot_spacer()) +
  plot_layout(heights = c(1, 0.7))
inspect_scene = incant(inspect_plot, width = 8.4, height = 5.6)
save_scene(inspect_scene, file.path(output_dir, "readme-inspect.png"), debug = TRUE)

# Select and translate --------------------------------------------------------
markers = data.frame(x = factor(c(4, 6, 8)), y = 1, label = c("A", "B", "C"))
p_markers = ggplot(markers, aes(x, y, colour = x)) +
  geom_point(size = 5, show.legend = FALSE) +
  geom_text(aes(label = label), colour = "white", fontface = "bold") +
  coord_cartesian(ylim = c(0.8, 1.2), clip = "off") +
  labs(x = "Cylinders", y = NULL) +
  readme_theme +
  theme(
    axis.text.y = element_blank(), axis.ticks.y = element_blank(),
    panel.grid = element_blank(), plot.title = element_blank(),
    plot.margin = margin(8, 14, 34, 14, "pt")
  )
stack_top = p_mpg +
  labs(x = NULL) +
  theme(axis.text.x = element_blank(), axis.ticks.x = element_blank())
translate_plot = stack_top / p_markers + plot_layout(heights = c(4, 1))
translate_before = incant(translate_plot, width = 5.2, height = 4.2)
translate_after = translate_before |>
  select_plot(2) |>
  translate(dy = 26, unit = "pt")
save_row(
  list(translate_before, translate_after), c("Before", "translate(dy = 26)"),
  file.path(output_dir, "readme-translate.png"), 5.2, 4.2
)

# Semantic constraints --------------------------------------------------------
constraint_before = incant(translate_plot, width = 5.2, height = 4.2)
constraint_after = constraint_before |>
  place_below(2, 1, gap = 5, unit = "pt")
save_row(
  list(constraint_before, constraint_after), c("Original gap", "place_below(gap = 5)"),
  file.path(output_dir, "readme-constraints.png"), 5.2, 4.2
)

# Z order ---------------------------------------------------------------------
z_blue = p_mpg + theme(
  panel.background = element_rect(fill = "#EAF2F8", colour = NA),
  plot.background = element_rect(fill = "white", colour = NA),
  plot.title = element_blank(), axis.title = element_blank()
)
z_red = p_hp + theme(
  panel.background = element_rect(fill = "#FCECEF", colour = NA),
  plot.background = element_rect(fill = "white", colour = NA),
  plot.title = element_blank(), axis.title = element_blank()
)
z_base = incant(z_blue + z_red, width = 6.6, height = 3.5)
z_overlap = z_base |>
  select_plot(2) |>
  translate(dx = -105, include_background = TRUE)
z_front = z_overlap |>
  select_plot(1) |>
  bring_to_front()
save_row(
  list(z_overlap, z_front), c("Plot 2 covers plot 1", "bring_to_front(plot 1)"),
  file.path(output_dir, "readme-zorder.png"), 6.6, 3.5
)

# Diagnostics -----------------------------------------------------------------
diagnostic = diagnose(z_overlap)
overlaps = detect_overlap(z_overlap)
diagnostic_text = paste(
  c(
    paste0("diagnose(): ", diagnostic$status),
    diagnostic$issues,
    if (nrow(overlaps)) paste0("detect_overlap(): ", round(overlaps$overlap_pt[[1]], 1), " pt")
  ),
  collapse = "  |  "
)
grDevices::png(
  file.path(output_dir, "readme-diagnose.png"),
  width = 7.8, height = 4.35, units = "in", res = 150, bg = "white"
)
grid::grid.newpage()
grid::pushViewport(grid::viewport(layout = grid::grid.layout(
  2, 1, heights = grid::unit(c(3.7, 0.65), "in")
)))
grid::pushViewport(grid::viewport(layout.pos.row = 1))
grid::grid.draw(render(z_overlap, debug = TRUE))
grid::popViewport()
grid::pushViewport(grid::viewport(layout.pos.row = 2))
grid::grid.rect(gp = grid::gpar(fill = "#FFF4E5", col = "#F79009"))
grid::grid.text(diagnostic_text, x = grid::unit(10, "pt"), just = "left",
                gp = grid::gpar(fontsize = 9, col = "#7A2E0E"))
grid::popViewport(2)
grDevices::dev.off()

# Manifest replay -------------------------------------------------------------
manifest_original = incant(translate_plot, width = 4.6, height = 3.8)
manifest_edited = manifest_original |>
  place_below(2, 1, gap = 4, unit = "pt")
manifest_path = tempfile(fileext = ".json")
write_incantation(manifest_edited, manifest_path)
manifest_replayed = apply_incantation(
  incant(translate_plot, width = 4.6, height = 3.8),
  manifest_path
)
save_row(
  list(manifest_original, manifest_edited, manifest_replayed),
  c("Original", "Edited", "Manifest replay"),
  file.path(output_dir, "readme-manifest.png"), 4.6, 3.8
)

# Result-native SVG editing ---------------------------------------------------
cars = mtcars[c("Mazda RX4", "Datsun 710", "Hornet 4 Drive", "Valiant"), ]
cars$name = rownames(cars)
svg_plot = ggplot(cars, aes(wt, mpg, label = name)) +
  geom_point(size = 3, colour = blue) +
  geom_text(vjust = -0.9, size = 3.6) +
  expand_limits(y = max(cars$mpg) + 2) +
  scale_x_continuous(expand = expansion(mult = c(0.18, 0.08))) +
  labs(title = "Rendered SVG primitives", x = "Weight", y = "MPG") +
  readme_theme
svg_before = incant(svg_plot, width = 5.2, height = 3.8) |>
  as_svg()
svg_after = svg_before |>
  select_svg_text("Mazda RX4") |>
  svg_translate(dx = 12, dy = 8) |>
  svg_style(fill = "#D92D20", font_size = 17)
svg_before_path = tempfile(fileext = ".svg")
svg_after_path = tempfile(fileext = ".svg")
svg_before_png = tempfile(fileext = ".png")
svg_after_png = tempfile(fileext = ".png")
write_svg(svg_before, svg_before_path)
write_svg(svg_after, svg_after_path)
rsvg::rsvg_png(svg_before_path, svg_before_png, width = 780, height = 570)
rsvg::rsvg_png(svg_after_path, svg_after_png, width = 780, height = 570)
svg_rasters = lapply(c(svg_before_png, svg_after_png), png::readPNG)
grDevices::png(
  file.path(output_dir, "readme-svg.png"),
  width = 10.4, height = 4.15, units = "in", res = 150, bg = "white"
)
grid::grid.newpage()
grid::pushViewport(grid::viewport(layout = grid::grid.layout(
  2, 2,
  widths = grid::unit(c(5.2, 5.2), "in"),
  heights = grid::unit(c(0.35, 3.8), "in")
)))
lapply(seq_along(svg_rasters), function(i) {
  grid::pushViewport(grid::viewport(layout.pos.row = 1, layout.pos.col = i))
  grid::grid.text(c("SVG snapshot", "Text moved + restyled")[[i]],
                  gp = grid::gpar(fontsize = 12, fontface = "bold", col = "#344054"))
  grid::popViewport()
  grid::pushViewport(grid::viewport(layout.pos.row = 2, layout.pos.col = i))
  grid::grid.raster(svg_rasters[[i]], width = grid::unit(1, "npc"),
                    height = grid::unit(1, "npc"))
  grid::popViewport()
})
grid::popViewport()
grDevices::dev.off()

# Supported backends ----------------------------------------------------------
backend_plot = function(plot, backend, id, gap) {
  scene = incant(plot, width = 4.4, height = 2.8)
  targets = inspect(scene) |>
    subset(role == "plot" & !is_empty) |>
    getElement("id")
  scene |>
    decorate_group(
      targets, backend, id = id, gap = gap, title_gap = 3,
      trim = c(4, 6), title_size = 11,
      line_colour = purple, title_colour = purple
    )
}
backend_p1 = p_mpg + theme(plot.title = element_blank(), axis.title = element_blank())
backend_p2 = p_hp + theme(plot.title = element_blank(), axis.title = element_blank())
backend_p3 = p_qsec + theme(plot.title = element_blank(), axis.title = element_blank())
backend_scenes = list(
  backend_plot(backend_p1, "ggplot", "backend-ggplot", -24),
  backend_plot(backend_p1 + backend_p2, "patchwork", "backend-patchwork", -24),
  backend_plot(
    backend_p1 |> aplot::insert_right(backend_p3, width = .55),
    "aplot", "backend-aplot", -24
  ),
  backend_plot(
    cowplot::plot_grid(backend_p1, backend_p2),
    "cowplot", "backend-cowplot", -24
  )
)
save_backend_grid(
  backend_scenes, c("ggplot", "patchwork", "aplot", "cowplot"),
  file.path(output_dir, "readme-backends.png"), 4.4, 2.8
)

invisible(lapply(
  file.path(output_dir, c(
    "readme-decoration.png", "readme-inspect.png", "readme-translate.png",
    "readme-constraints.png", "readme-zorder.png", "readme-diagnose.png",
    "readme-manifest.png", "readme-svg.png", "readme-backends.png"
  )),
  function(path) stopifnot(file.exists(path), file.info(path)$size > 1000)
))
