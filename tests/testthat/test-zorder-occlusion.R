# REVIEW §2.3 -- the hazard example.R only dodges by accident.
#
# A patchwork subplot is a grob SET, and that set includes background-k: an
# OPAQUE white rect spanning the entire subplot region (MEASURED: rect,
# fill="white", z=0). Translating "the subplot" drags the background along.
#
# MEASURED z ranges for p1/p2:  subplot-1 = [0,21], subplot-2 = [0,42].
# Backgrounds sit at z=0, so they draw early and rarely bite. But content z
# grows with subplot order, so moving an EARLIER subplot toward a LATER one
# puts it underneath. example.R survives only because its author happened to
# write plot.background = element_blank() by hand.

test_that("translate(k) excludes the subplot background by default", {
  scene = incant(fx_opaque_stack(), width = 10, height = 8, units = "in")

  bg_before = bbox(scene, "plot-2/background")
  s1 = scene |> select_plot(2) |> translate(dy = 60, unit = "pt")

  # The visible content moves; the opaque backdrop stays in its cell.
  expect_equal(bbox(s1, "plot-2/panel")$bottom -
                 bbox(scene, "plot-2/panel")$bottom, 60, tolerance = 1e-6)
  expect_equal(bbox(s1, "plot-2/background"), bg_before, tolerance = 1e-9)
})

test_that("the background can be moved along on request", {
  scene = incant(fx_opaque_stack(), width = 10, height = 8, units = "in")
  s1 = scene |> select_plot(2) |>
    translate(dy = 60, unit = "pt", include_background = TRUE)

  expect_equal(bbox(s1, "plot-2/background")$bottom -
                 bbox(scene, "plot-2/background")$bottom, 60,
               tolerance = 1e-6)
})

test_that("moving an opaque background over a sibling is diagnosed", {
  scene = incant(fx_opaque_stack(), width = 10, height = 8, units = "in")
  s1 = scene |> select_plot(2) |>
    translate(dy = 60, unit = "pt", include_background = TRUE)

  d = diagnose(s1)
  expect_equal(d$status, "warning")
  expect_match(paste(d$issues, collapse = " "), "opaque|occlud|cover")
})

test_that("moving a low-z subplot under a high-z one is diagnosed, not silently wrong", {
  # The reverse direction: subplot 1 (z<=21) pushed DOWN into subplot 2's
  # territory (z<=42) is drawn FIRST and ends up hidden behind it. The pixels
  # are correct per grid's rules and completely surprising to the user.
  scene = incant(fx_opaque_stack(), width = 10, height = 8, units = "in")
  s1 = scene |> select_plot(1) |> translate(dy = -60, unit = "pt")

  d = diagnose(s1)
  expect_equal(d$status, "warning")
  expect_match(paste(d$issues, collapse = " "), "covered by|behind|z-order")
})

test_that("bring_to_front() resolves the occlusion it reported", {
  scene = incant(fx_opaque_stack(), width = 10, height = 8, units = "in")
  s1 = scene |> select_plot(1) |>
    translate(dy = -60, unit = "pt") |>
    bring_to_front()

  expect_false(any(grepl("covered by|behind", diagnose(s1)$issues)))
  # ...and z-order is a DRAW-order change only: layout stays frozen.
  expect_identical(as_gtable(scene)$heights, as_gtable(s1)$heights)
  expect_equal(bbox(s1, 2), bbox(scene, 2), tolerance = 1e-9)
})

test_that("detect_overlap reports the overlapping pair and the amount", {
  # An agent cannot act on "there is an overlap". It needs to know what
  # overlaps what, by how much, so it can decide the next dy.
  scene = incant(fx_panel_row(), width = 12, height = 10, units = "in")
  s1 = scene |> select_plot(3) |> translate(dy = 80, unit = "pt")

  ov = detect_overlap(s1)
  expect_true(nrow(ov) >= 1)
  expect_true(all(c("a", "b", "overlap_pt", "axis") %in% names(ov)))
  expect_true(any(ov$a == "plot-3" | ov$b == "plot-3"))
  expect_true(all(ov$overlap_pt > 0))
})
