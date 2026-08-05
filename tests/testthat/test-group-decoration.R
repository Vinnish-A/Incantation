fx_visible_rects = function(scene, ids) {
  unlist(lapply(ids, function(id) {
    el = scene$registry[[id]]
    parts = Filter(function(part) !isTRUE(part$is_background) && !isTRUE(part$is_blank), el$parts)
    lapply(parts, function(part) incantation:::.part_rect(scene, part))
  }), recursive = FALSE)
}

test_that("top decoration uses panel span and current layout frontier", {
  p = fx_decoration_plot("Pseudotime") +
    fx_decoration_plot("Tumor phase", facets = TRUE) +
    fx_decoration_plot("Time point", right = TRUE)
  scene = incant(p, width = 12, height = 5) |>
    decorate_group(1:3, "Tumor cell (Stereo-seq)", id = "tumor",
                   gap = 4, title_gap = 5, trim = c(6, 10))
  geometry = incantation:::.decoration_geometry(scene, scene$decorations$tumor)
  panels = lapply(1:3, function(i) bbox(scene, i))
  visible = fx_visible_rects(scene, paste0("plot-", 1:3))

  expect_equal(geometry$line[["x0"]], min(vapply(panels, `[[`, numeric(1), "left")) + 6,
               tolerance = 0.01)
  expect_equal(geometry$line[["x1"]], max(vapply(panels, `[[`, numeric(1), "right")) - 10,
               tolerance = 0.01)
  expect_equal(geometry$line[["y0"]], max(vapply(visible, `[[`, numeric(1), "top")) + 4,
               tolerance = 0.01)
  expect_equal(geometry$title_rect[["bottom"]] - geometry$line[["y0"]], 5,
               tolerance = 0.01)
})

test_that("four sides share start-end and outward conventions", {
  p = fx_decoration_plot() / fx_decoration_plot()
  base = incant(p, width = 7, height = 8)
  for (side in c("top", "bottom", "left", "right")) {
    scene = decorate_group(base, 1:2, paste("Group", side), side = side,
                           id = side, gap = 3, trim = c(4, 8))
    op = scene$decorations[[side]]
    geometry = incantation:::.decoration_geometry(scene, op)
    basis = incantation:::.decoration_basis(side)
    start = c(x = geometry$line[["x0"]], y = geometry$line[["y0"]])
    end = c(x = geometry$line[["x1"]], y = geometry$line[["y1"]])
    expect_lt(sum(start * basis$along), sum(end * basis$along))
    expect_equal(sum(start * basis$outward), geometry$outer + 3,
                 tolerance = 0.01, info = side)
    expect_equal(sum(end * basis$outward), geometry$outer + 3,
                 tolerance = 0.01, info = side)
    expect_silent(as_gtable(scene))
  }
})

test_that("hidden axes fall back to panel edges while visible outer roles clear the line", {
  plain = fx_decoration_plot() + fx_decoration_plot()
  scene_plain = incant(plain, width = 8, height = 4) |>
    decorate_group(1:2, "Plain", id = "plain", gap = 3)
  geometry_plain = incantation:::.decoration_geometry(scene_plain, scene_plain$decorations$plain)
  expect_equal(geometry_plain$outer,
               max(vapply(1:2, function(i) bbox(scene_plain, i)$top, numeric(1))),
               tolerance = 0.01)

  special = fx_decoration_plot(facets = TRUE) + fx_decoration_plot(right = TRUE)
  top = incant(special, width = 8, height = 4) |>
    decorate_group(1:2, "Facets", id = "facets", side = "top")
  right = incant(special, width = 8, height = 4) |>
    decorate_group(1:2, "Right", id = "right-axis", side = "right")
  top_geometry = incantation:::.decoration_geometry(top, top$decorations$facets)
  right_geometry = incantation:::.decoration_geometry(right, right$decorations$`right-axis`)
  expect_gt(top_geometry$outer, max(vapply(1:2, function(i) bbox(top, i)$top, numeric(1))))
  expect_gt(right_geometry$outer, max(vapply(1:2, function(i) bbox(right, i)$right, numeric(1))))
})

test_that("title alignment is relative to the trimmed line", {
  p = fx_decoration_plot() + fx_decoration_plot()
  base = incant(p, width = 8, height = 4)
  for (align in c("start", "center", "end")) {
    scene = decorate_group(base, 1:2, "Aligned title", id = align,
                           align = align, trim = c(5, 9))
    geometry = incantation:::.decoration_geometry(scene, scene$decorations[[align]])
    observed = switch(align,
      start = geometry$title_rect[["left"]],
      center = (geometry$title_rect[["left"]] + geometry$title_rect[["right"]]) / 2,
      end = geometry$title_rect[["right"]]
    )
    expected = switch(align,
      start = geometry$line[["x0"]],
      center = (geometry$line[["x0"]] + geometry$line[["x1"]]) / 2,
      end = geometry$line[["x1"]]
    )
    expect_equal(observed, expected, tolerance = 0.01, info = align)
  }
})

test_that("decoration group, line and title are first-class editable elements", {
  p = fx_decoration_plot() + fx_decoration_plot()
  scene = incant(p, width = 8, height = 4) |>
    decorate_group(1:2, "Editable", id = "editable")
  expect_true(all(c("editable", "editable/line", "editable/title") %in% inspect(scene)$id))

  moved_group = scene |> select_id("editable") |> translate(dx = 3, dy = -2)
  for (component in c("line", "title")) {
    before = bbox(scene, paste0("editable/", component))
    after = bbox(moved_group, paste0("editable/", component))
    expect_equal(after$left - before$left, 3, tolerance = 1e-6)
    expect_equal(after$bottom - before$bottom, -2, tolerance = 1e-6)
  }

  moved_title = scene |> select_id("editable/title") |> translate(dx = 2, dy = 1)
  expect_equal(bbox(moved_title, "editable/title")$left - bbox(scene, "editable/title")$left,
               2, tolerance = 1e-6)
  expect_equal(bbox(moved_title, "editable/line"), bbox(scene, "editable/line"),
               tolerance = 1e-9)
  front = as_gtable(moved_title |> bring_to_front())
  back = as_gtable(scene |> select_id("editable/line") |> send_to_back())
  expect_gt(front$layout$z[front$layout$name == "incant-editable-title"],
            front$layout$z[front$layout$name == "incant-editable-line"])
  expect_lt(back$layout$z[back$layout$name == "incant-editable-line"],
            min(scene$base$layout$z))
})

test_that("semantic anchors bind to plot geometry after later transforms", {
  p = fx_decoration_plot("One") + fx_decoration_plot("Two")
  scene = incant(p, width = 8, height = 4) |>
    decorate_group(1:2, "Late bound", id = "late")
  before = incantation:::.decoration_geometry(scene, scene$decorations$late)
  moved = scene |> select_plot(1) |> translate(dy = 12)
  after = incantation:::.decoration_geometry(moved, moved$decorations$late)
  expect_equal(after$line[["y0"]] - before$line[["y0"]], 12, tolerance = 0.01)
})

test_that("initial along/outward nudges use side coordinates", {
  p = fx_decoration_plot() + fx_decoration_plot()
  base = incant(p, width = 8, height = 4) |>
    decorate_group(1:2, "Base", id = "base-nudge")
  nudged = incant(p, width = 8, height = 4) |>
    decorate_group(1:2, "Base", id = "with-nudge",
                   nudge = c(3, 4), title_nudge = c(2, 1))
  a = incantation:::.decoration_geometry(base, base$decorations$`base-nudge`)
  b = incantation:::.decoration_geometry(nudged, nudged$decorations$`with-nudge`)
  expect_equal(b$line[["x0"]] - a$line[["x0"]], 3, tolerance = 0.01)
  expect_equal(b$line[["y0"]] - a$line[["y0"]], 4, tolerance = 0.01)
  expect_equal(b$title[["x"]] - a$title[["x"]], 5, tolerance = 0.01)
  expect_equal(b$title_rect[["bottom"]] - a$title_rect[["bottom"]], 5, tolerance = 0.01)
})

test_that("decorations preserve the frozen layout and all original plot geometry", {
  p = fx_decoration_plot() + fx_decoration_plot()
  base = incant(p, width = 8, height = 4)
  decorated = decorate_group(base, 1:2, "Frozen", id = "frozen")
  g0 = as_gtable(base)
  g1 = as_gtable(decorated)

  expect_identical(g0$widths, g1$widths)
  expect_identical(g0$heights, g1$heights)
  expect_identical(dim(g0), dim(g1))
  expect_equal(canvas_size(base), canvas_size(decorated))
  for (i in 1:2) expect_equal(bbox(base, i), bbox(decorated, i), tolerance = 1e-9)
})

test_that("absolute spans are exact and device-bound", {
  p = fx_decoration_plot() + fx_decoration_plot()
  scene = incant(p, width = 8, height = 4) |>
    decorate_group(1:2, "Absolute", id = "absolute", span = c(80, 420), trim = 0)
  geometry = incantation:::.decoration_geometry(scene, scene$decorations$absolute)
  expect_equal(geometry$line[c("x0", "x1")], c(x0 = 80, x1 = 420), tolerance = 0.01)

  path = tempfile(fileext = ".json")
  write_incantation(scene, path)
  expect_error(
    apply_incantation(incant(p, width = 6, height = 3), path),
    class = "inc_error_device_mismatch"
  )
})

test_that("vertical absolute spans use top-to-bottom device coordinates", {
  p = fx_decoration_plot() / fx_decoration_plot()
  scene = incant(p, width = 6, height = 8) |>
    decorate_group(1:2, "Vertical", id = "vertical", side = "right",
                   span = c(500, 80), trim = 0)
  geometry = incantation:::.decoration_geometry(scene, scene$decorations$vertical)
  expect_equal(geometry$line[["y0"]], 500, tolerance = 0.01)
  expect_equal(geometry$line[["y1"]], 80, tolerance = 0.01)
})

test_that("semantic decorations round-trip and re-resolve across devices", {
  p = fx_decoration_plot() + fx_decoration_plot()
  big = incant(p, width = 10, height = 5) |>
    decorate_group(1:2, "Portable", id = "portable", gap = 7, trim = c(5, 11))
  path = tempfile(fileext = ".json")
  write_incantation(big, path)
  small = apply_incantation(incant(p, width = 7, height = 4), path)
  geometry = incantation:::.decoration_geometry(small, small$decorations$portable)
  panels = lapply(1:2, function(i) bbox(small, i))

  expect_equal(geometry$line[["x0"]], min(vapply(panels, `[[`, numeric(1), "left")) + 5,
               tolerance = 0.01)
  expect_equal(geometry$line[["x1"]], max(vapply(panels, `[[`, numeric(1), "right")) - 11,
               tolerance = 0.01)
  expect_equal(geometry$line[["y0"]], geometry$outer + 7, tolerance = 0.01)
  expect_true(all(c("portable", "portable/line", "portable/title") %in% inspect(small)$id))
})

test_that("manifest can replay later component translations", {
  p = fx_decoration_plot() + fx_decoration_plot()
  scene = incant(p, width = 8, height = 4) |>
    decorate_group(1:2, "Replay", id = "replay") |>
    select_id("replay/title") |>
    translate(dx = 3, dy = -2)
  path = tempfile(fileext = ".json")
  write_incantation(scene, path)
  restored = apply_incantation(incant(p, width = 8, height = 4), path)
  expect_equal(bbox(restored, "replay/title"), bbox(scene, "replay/title"), tolerance = 1e-6)
})

test_that("multiple, nested and non-contiguous patchwork targets use explicit hulls", {
  p1 = fx_decoration_plot("One")
  p2 = fx_decoration_plot("Two")
  p3 = fx_decoration_plot("Three")
  scene = incant(p1 | (p2 / p3), width = 9, height = 6) |>
    decorate_group(c(1, 3), "Outer hull", id = "outer") |>
    decorate_group(c(2, 3), "Nested column", side = "right", id = "nested")
  expect_equal(length(scene$decorations), 2)
  expect_silent(as_gtable(scene))
  outer = incantation:::.decoration_geometry(scene, scene$decorations$outer)
  expect_equal(outer$line[["x0"]], min(bbox(scene, 1)$left, bbox(scene, 3)$left), tolerance = 0.01)
  expect_equal(outer$line[["x1"]], max(bbox(scene, 1)$right, bbox(scene, 3)$right), tolerance = 0.01)
})

test_that("line-only decorations and invalid specifications are explicit", {
  p = fx_decoration_plot() + fx_decoration_plot()
  base = incant(p, width = 8, height = 4)
  line_only = decorate_group(base, 1:2, title = NULL, id = "line-only")
  expect_true("line-only/line" %in% inspect(line_only)$id)
  expect_false("line-only/title" %in% inspect(line_only)$id)
  expect_silent(as_gtable(line_only))

  expect_error(decorate_group(base, 1:2, "Bad", trim = 1e4),
               class = "inc_error_bad_decoration")
  expect_error(decorate_group(base, 99, "Bad"), class = "inc_error_no_match")
  expect_error(decorate_group(base, 1:2, "Bad", span = c(400, 100)),
               class = "inc_error_bad_decoration")
  expect_error(decorate_group(base, 1:2, "One", id = "same") |>
                 decorate_group(1:2, "Two", id = "same"),
               class = "inc_error_duplicate_id")
})

test_that("fixed-canvas overflow is diagnosed rather than repaired", {
  p = ggplot(mtcars, aes(wt, mpg)) + geom_point()
  scene = incant(p + p, width = 8, height = 4) |>
    decorate_group(1:2, "Outside", id = "outside", gap = 4, title_gap = 5)
  expect_equal(canvas_size(scene), c(width = 8 * 72, height = 4 * 72))
  expect_equal(diagnose(scene)$status, "warning")
  expect_match(paste(diagnose(scene)$issues, collapse = " "), "outside/title.*outside canvas")
})

test_that("SVG output keeps the decoration line and title editable", {
  p = fx_decoration_plot() + fx_decoration_plot()
  scene = incant(p, width = 8, height = 4) |>
    decorate_group(1:2, "SVG group title", id = "svg-title")
  grDevices::pdf(NULL)
  external_device = grDevices::dev.cur()
  on.exit({
    devices = grDevices::dev.list()
    if (!is.null(devices) && external_device %in% devices) {
      grDevices::dev.off(external_device)
    }
  }, add = TRUE)
  svg = as_svg(scene)
  manifest = svg_manifest(svg)
  expect_equal(grDevices::dev.cur(), external_device)
  expect_true(any(manifest$tag == "line"))
  expect_true(any(manifest$tag == "text" & manifest$text == "SVG group title"))
})
