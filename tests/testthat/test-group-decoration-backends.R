test_that("group decorations render through every source adapter", {
  fx_skip_unless_backend("aplot")
  fx_skip_unless_backend("cowplot")

  p1 = fx_decoration_plot("Main") + labs(y = "MAIN")
  p2 = fx_decoration_plot("Companion") + labs(y = "COMPANION")
  sources = list(
    ggplot = p1,
    aplot = p1 |> aplot::insert_right(p2, width = .5),
    cowplot = cowplot::plot_grid(p1, p2),
    gtable = fx_on_device(8, 4, function() ggplotGrob(p1))
  )

  lapply(names(sources), function(source) {
    base = incant(sources[[source]], width = 8, height = 4)
    targets = inspect(base) |>
      subset(role == "plot" & !is_empty) |>
      getElement("id")
    line_gap = if (identical(base$backend, "cowplot")) -24 else 3
    scene = base |>
      decorate_group(targets, paste("Decorated", source), id = source,
                     gap = line_gap, title_gap = 3, trim = c(2, 4))
    geometry = incantation:::.decoration_geometry(scene, scene$decorations[[source]])
    panels = lapply(targets, function(id) bbox(scene, id))

    expect_equal(geometry$line[["x0"]],
                 min(vapply(panels, `[[`, numeric(1), "left")) + 2,
                 tolerance = 0.01, info = source)
    expect_equal(geometry$line[["x1"]],
                 max(vapply(panels, `[[`, numeric(1), "right")) - 4,
                 tolerance = 0.01, info = source)
    expect_equal(geometry$line[["y0"]], geometry$outer + line_gap,
                 tolerance = 0.01, info = source)
    expect_identical(as_gtable(base)$widths, as_gtable(scene)$widths)
    expect_identical(as_gtable(base)$heights, as_gtable(scene)$heights)
    expect_silent(as_gtable(scene))

    moved = scene |>
      select_id(paste0(source, "/title")) |>
      translate(dx = 3, dy = -2)
    expect_equal(bbox(moved, paste0(source, "/title"))$left -
                   bbox(scene, paste0(source, "/title"))$left,
                 3, tolerance = 1e-6, info = source)
  })
})

test_that("raw gtables are classified by structure before decoration", {
  fx_skip_unless_backend("cowplot")

  p = fx_decoration_plot("Raw")
  sources = list(
    ggplot = fx_on_device(8, 4, function() ggplotGrob(p + facet_wrap(~cyl))),
    patchwork = fx_on_device(8, 4, function() patchwork::patchworkGrob(p + p)),
    cowplot = fx_on_device(8, 4, function() ggplotGrob(cowplot::plot_grid(p, p)))
  )
  expected_plots = c(ggplot = 1L, patchwork = 2L, cowplot = 2L)

  lapply(names(sources), function(backend) {
    base = incant(sources[[backend]], width = 8, height = 4)
    plots = inspect(base) |> subset(role == "plot" & !is_empty)
    scene = base |>
      decorate_group(plots$id, paste("Raw", backend), id = paste0("raw-", backend),
                     gap = if (identical(backend, "cowplot")) -24 else 2)

    expect_identical(base$source, "gtable")
    expect_identical(base$backend, backend)
    expect_equal(nrow(plots), expected_plots[[backend]])
    expect_silent(as_gtable(scene))
  })
})

test_that("aplot and cowplot decorations replay semantically across devices", {
  fx_skip_unless_backend("aplot")
  fx_skip_unless_backend("cowplot")
  fx_skip_unless_backend("jsonlite")

  p1 = fx_decoration_plot("One")
  p2 = fx_decoration_plot("Two")
  sources = list(
    aplot = p1 |> aplot::insert_left(p2, width = .5),
    cowplot = cowplot::plot_grid(p1, p2)
  )

  lapply(names(sources), function(source) {
    line_gap = if (identical(source, "cowplot")) -24 else 5
    original = incant(sources[[source]], width = 10, height = 5)
    targets = inspect(original) |>
      subset(role == "plot" & !is_empty) |>
      getElement("id")
    decorated = original |>
      decorate_group(targets, paste("Portable", source), id = paste0("portable-", source),
                     gap = line_gap, trim = c(4, 7))
    path = tempfile(fileext = ".json")
    write_incantation(decorated, path)

    restored = apply_incantation(
      incant(sources[[source]], width = 7, height = 4),
      path
    )
    id = paste0("portable-", source)
    geometry = incantation:::.decoration_geometry(restored, restored$decorations[[id]])
    panels = lapply(targets, function(target) bbox(restored, target))

    expect_equal(geometry$line[["x0"]],
                 min(vapply(panels, `[[`, numeric(1), "left")) + 4,
                 tolerance = 0.01, info = source)
    expect_equal(geometry$line[["x1"]],
                 max(vapply(panels, `[[`, numeric(1), "right")) - 7,
                 tolerance = 0.01, info = source)
    expect_equal(geometry$line[["y0"]], geometry$outer + line_gap,
                 tolerance = 0.01, info = source)
    expect_silent(as_gtable(restored))
  })
})
