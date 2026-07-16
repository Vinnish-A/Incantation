# REVIEW §3.1 / README §7.1 -- the Frozen Layout Principle.
#
# The README proposes testing this by comparing widths/heights/layout. That is
# necessary but far too weak: it compares the RECIPE, not the RESULT. A bug that
# leaves the gtable table identical while shifting a sibling's rendered position
# (e.g. by wrapping the wrong grob, or by mutating a shared vp) sails straight
# through. So we assert on measured device coordinates too.

test_that("translate does not touch the layout recipe", {
  scene0 = incant(fx_panel_row(), width = 12, height = 10, units = "in")
  scene1 = scene0 |> select_plot(3) |> translate(dy = 40, unit = "pt")

  g0 = as_gtable(scene0)
  g1 = as_gtable(scene1)

  expect_identical(g0$widths, g1$widths)
  expect_identical(g0$heights, g1$heights)
  expect_identical(dim(g0), dim(g1))
  expect_identical(length(g0$grobs), length(g1$grobs))

  # clip is the ONE column translate is allowed to touch.
  expect_identical(
    g0$layout[setdiff(names(g0$layout), "clip")],
    g1$layout[setdiff(names(g1$layout), "clip")]
  )
})

test_that("translate does not move any sibling ON THE DEVICE", {
  # The real invariant. Every element that was not selected must land on the
  # exact same device pixel.
  scene0 = incant(fx_panel_row(), width = 12, height = 10, units = "in")
  scene1 = scene0 |> select_plot(3) |> translate(dy = 40, unit = "pt")

  moved = inspect(scene1) |> subset(plot_index == 3, "id", drop = TRUE)
  untouched = inspect(scene0) |> subset(!(id %in% moved), "id", drop = TRUE)

  for (el in untouched) {
    expect_equal(
      bbox(scene0, el), bbox(scene1, el),
      tolerance = 1e-9,
      info = paste("sibling moved:", el)
    )
  }
})

test_that("translate does not change the canvas size", {
  scene0 = incant(fx_panel_row(), width = 12, height = 10, units = "in")
  # plot-3 (bottom row) sits ~107pt up on a 720pt canvas; push it clear off the top.
  scene1 = scene0 |> select_plot(3) |> translate(dy = 700, unit = "pt")

  expect_equal(canvas_size(scene0), canvas_size(scene1))

  # Off-canvas is allowed (clip = "off" is the default) but must be diagnosed,
  # never fixed by growing the canvas.
  expect_equal(diagnose(scene1)$status, "warning")
  expect_match(
    paste(diagnose(scene1)$issues, collapse = " "),
    "outside canvas"
  )
})

test_that("the target moves by exactly dy and not by dx", {
  scene0 = incant(fx_panel_row(), width = 12, height = 10, units = "in")
  scene1 = scene0 |> select_plot(3) |> translate(dy = 40, unit = "pt")

  b0 = bbox(scene0, 3)
  b1 = bbox(scene1, 3)

  expect_equal(b1$bottom - b0$bottom, 40, tolerance = 1e-6)
  expect_equal(b1$top - b0$top, 40, tolerance = 1e-6)
  expect_equal(b1$left, b0$left, tolerance = 1e-9)
  expect_equal(b1$right, b0$right, tolerance = 1e-9)
})

test_that("positive dy means UP, consistently with grid (documented convention)", {
  # grid's y grows upward; CSS/Photoshop's grows downward. Whichever we pick,
  # it must never silently differ between backends. Pin it.
  scene0 = incant(fx_panel_row(), width = 12, height = 10, units = "in")
  scene1 = scene0 |> select_plot(3) |> translate(dy = 10, unit = "pt")

  expect_gt(bbox(scene1, 3)$bottom, bbox(scene0, 3)$bottom)
})

test_that("translations compose additively", {
  scene0 = incant(fx_panel_row(), width = 12, height = 10, units = "in")

  twice = scene0 |>
    select_plot(3) |> translate(dy = 10, unit = "pt") |>
    select_plot(3) |> translate(dy = 14, unit = "pt")
  once = scene0 |> select_plot(3) |> translate(dy = 24, unit = "pt")

  expect_equal(bbox(twice, 3), bbox(once, 3), tolerance = 1e-6)
})

test_that("a scene is an immutable value -- the input is never mutated", {
  # This is why the MVP does not need undo/redo: `scene0` IS the undo.
  # Assign-by-reference bugs in grid code are easy to write and hard to see.
  scene0 = incant(fx_panel_row(), width = 12, height = 10, units = "in")
  b_before = bbox(scene0, 3)

  invisible(scene0 |> select_plot(3) |> translate(dy = 40, unit = "pt"))

  expect_equal(bbox(scene0, 3), b_before, tolerance = 1e-12)
})
