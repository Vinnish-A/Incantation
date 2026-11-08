# Check rendered device coordinates, independently of bbox's transform arithmetic.
fx_rendered_points = function(scene, colour) {
  svg = as_svg(scene)
  doc = xml2::read_xml(svg$svg)
  nodes = xml2::xml_find_all(doc, sprintf(
    "//*[local-name()='circle' and contains(@style, '%s')]", colour
  ))
  data.frame(x = as.numeric(xml2::xml_attr(nodes, "cx")),
             y = as.numeric(xml2::xml_attr(nodes, "cy")))
}

fx_edge_points = function(colour) {
  ggplot(data.frame(x = .5, y = c(0, 1)), aes(x, y)) +
    geom_point(colour = colour, size = 1) +
    scale_x_continuous(limits = c(0, 1), expand = c(0, 0)) +
    scale_y_continuous(limits = c(0, 1), expand = c(0, 0)) +
    theme_void() + theme(plot.margin = margin(2, 2, 2, 2, "mm"))
}

test_that("physical translations use 72 rendered points per inch", {
  displacement = fx_on_device(4, 4, function() {
    probe = gTree(children = gList(rectGrob()), vp = viewport(name = "physical-probe"))
    grid.draw(probe)
    seekViewport("physical-probe")
    before = deviceLoc(unit(.5, "npc"), unit(.5, "npc"), valueOnly = TRUE)$x
    grid.newpage()
    grid.draw(incantation:::wrap_translate(probe, 72, 0))
    seekViewport("physical-probe")
    after = deviceLoc(unit(.5, "npc"), unit(.5, "npc"), valueOnly = TRUE)$x
    after - before
  })
  expect_equal(displacement, 1, tolerance = 1e-9)
  expect_equal(incantation:::.to_pt(unit(25.4, "mm"), "mm"), 72, tolerance = 1e-9)
})

test_that("cowplot aligns rendered data edges rather than outer slots", {
  skip_if_not_installed("cowplot")
  p = fx_edge_points("#D92D20")
  q = fx_edge_points("#175CD3") + theme(plot.margin = margin(15, 2, 2, 25, "mm"))
  base = incant(cowplot::plot_grid(p, q, nrow = 1, align = "none"),
                width = 180, height = 90, units = "mm", device = "svglite")
  before_red = fx_rendered_points(base, "#D92D20")
  before_blue = fx_rendered_points(base, "#175CD3")
  expect_equal(nrow(before_red), 2)
  expect_gt(abs(min(before_red$y) - min(before_blue$y)), 30)

  edited = align_top(base, 2, 1)
  expect_equal(min(fx_rendered_points(edited, "#175CD3")$y),
               min(before_red$y), tolerance = .02)
  expect_equal(fx_rendered_points(edited, "#D92D20"), before_red, tolerance = .001)
  expect_equal(bbox(edited, 2)$top, bbox(edited, 1)$top, tolerance = 1e-8)
  expect_identical(as_gtable(base)$widths, as_gtable(edited)$widths)
  expect_true(all(inspect(base)$anchor_type == "data-panel"))

  panel_only = base |> select_panel(2) |> translate(dy = 3)
  expect_equal(bbox(panel_only, 2)$top - bbox(base, 2)$top, 3, tolerance = 1e-8)
})

test_that("directional placement works from the wrong side and overlapping starts", {
  p = fx_edge_points("#D92D20")
  q = fx_edge_points("#175CD3")
  base = incant((p / q / plot_spacer()) + plot_layout(heights = c(1, 1, 2)),
                width = 180, height = 180, units = "mm", device = "svglite")
  below = place_below(base, 1, 2, gap = 6, unit = "mm")
  red = fx_rendered_points(below, "#D92D20")
  blue = fx_rendered_points(below, "#175CD3")
  expect_equal(min(red$y) - max(blue$y), 6 * 72 / 25.4, tolerance = .02)
  expect_equal(fx_rendered_points(base, "#175CD3"), blue, tolerance = .001)

  for (start in list(base, base |> select_plot(1) |> translate(dy = -70, unit = "mm"))) {
    below = place_below(start, 1, 2, gap = 6)
    expect_equal(bbox(below, 2)$bottom - bbox(below, 1)$top, 6, tolerance = 1e-8)
    above = place_above(start, 2, 1, gap = 6)
    expect_equal(bbox(above, 2)$bottom - bbox(above, 1)$top, 6, tolerance = 1e-8)
  }
})

test_that("Arial can be measured and exported on Cairo without substitution warnings", {
  skip_if_not(capabilities("cairo"))
  p = fx_edge_points("#D92D20") + labs(title = "Arial publication figure") +
    theme(text = element_text(family = "Arial"))
  expect_warning({ scene = incant(p, width = 90, height = 70, units = "mm") }, NA)
  for (ext in c("pdf", "png", "svg")) {
    path = tempfile(fileext = paste0(".", ext))
    expect_warning(ggsave_incant(scene, path), NA)
    expect_gt(file.info(path)$size, 100)
  }
})

test_that("scene replay checks semantic identity but allows fresh data", {
  p = fx_edge_points("#D92D20") + theme_classic() + labs(y = "First")
  q = fx_edge_points("#175CD3") + theme_classic() + labs(y = "Second")
  scene = incant(p / q, width = 8, height = 6) |> select_plot(2) |> translate(dx = 3)
  path = tempfile(fileext = ".json")
  write_incantation(scene, path)
  expect_error(apply_incantation(incant(q / p, width = 8, height = 6), path),
               class = "inc_error_plot_identity")
  fresh = q
  fresh$data$y = c(.1, .9)
  expect_no_error(apply_incantation(incant(p / fresh, width = 8, height = 6), path))

  explicit = incant(p / q, width = 8, height = 6, plot_ids = c("A", "B")) |>
    select_plot(2) |> translate(dy = .123456789)
  write_incantation(explicit, path)
  expect_error(apply_incantation(incant(q / p, width = 8, height = 6,
                                      plot_ids = c("B", "A")), path),
               class = "inc_error_plot_identity")
  expect_equal(bbox(apply_incantation(incant(p / q, width = 8, height = 6,
                                            plot_ids = c("A", "B")), path), 2),
               bbox(explicit, 2), tolerance = 1e-10)
})

test_that("arbitrary cowplot grobs identify their viewport-only anchors", {
  skip_if_not_installed("cowplot")
  p = cowplot::ggdraw() + cowplot::draw_grob(grid::rectGrob())
  scene = incant(p, width = 6, height = 4)
  expect_true(all(inspect(scene)$anchor_type == "plot-viewport"))
  expect_no_error(scene |> select_plot(1) |> translate(dx = 2) |> as_gtable())
})

test_that("ragg resolution and device-bound replay retain measurement settings", {
  skip_if_not_installed("ragg")
  scene = incant(fx_edge_points("#D92D20"), width = 3, height = 2,
                 device = "ragg", res = 144) |> select_plot(1) |> translate(dx = 2)
  expect_no_warning(ggsave_incant(scene, tempfile(fileext = ".png")))
  expect_error(ggsave_incant(scene, tempfile(fileext = ".png"), res = 72),
               class = "inc_error_render_device_mismatch")
  path = tempfile(fileext = ".json")
  write_incantation(scene, path)
  other = incant(fx_edge_points("#D92D20"), width = 3, height = 2, device = "cairo_pdf")
  expect_error(apply_incantation(other, path), class = "inc_error_render_device_mismatch")
})
