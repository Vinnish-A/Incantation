# REVIEW Phase 0 -- measurement is the product, so it gets the acceptance test.
#
# The whole point of the package is turning the user's sentence
#   "p_cluster_c is too far below the heatmap"
# into a number an agent can act on. Everything else (translate, place_below,
# diagnose) is a thin layer over this.
#
# MEASURED on the real example.R, at BOTH 12x10in and 8x6.7in:
#   heatmap panel bottom  ->  cluster panel top   =   44.89 pt
#
# It is device-independent here because the intervening gtable rows are all
# absolute (the 45pt bottom margin + axis rows). That is a property of THIS
# figure, not a general guarantee -- see test-device-portability.R.

# The real target figure ships in inst/examples so this acceptance test runs
# against it under R CMD check, not just in the dev tree.
fx_example_p_c = function() {
  skip_if_not_installed("tidyverse")
  path = system.file("examples", "panel_figure.R", package = "incantation")
  if (!nzchar(path)) path = "../../inst/examples/panel_figure.R"   # dev-tree fallback
  skip_if_not(file.exists(path), "panel_figure.R not found")
  # the figure asks for Arial and writes ./result/ ; neutralise both.
  if (!"Arial" %in% names(grDevices::pdfFonts())) {
    grDevices::pdfFonts(Arial = grDevices::pdfFonts()$Helvetica)
  }
  old = setwd(tempdir()); on.exit(setwd(old), add = TRUE)
  env = new.env()
  suppressWarnings(sys.source(normalizePath(path), env))
  env$p_c
}

test_that("gap() answers the user's actual question in points", {
  skip_if_not_installed("tidyverse")
  scene = incant(fx_example_p_c(), width = 12, height = 10, units = "in")

  g = gap(scene, 3, 1, direction = "vertical")

  expect_equal(as.numeric(g), 44.89, tolerance = 0.05)
  expect_equal(attr(g, "unit"), "pt")
})

test_that("this figure's gap happens to be device-independent, and gap() knows it", {
  skip_if_not_installed("tidyverse")
  p_c = fx_example_p_c()

  g_big = gap(incant(p_c, width = 12, height = 10, units = "in"), 3, 1)
  g_small = gap(incant(p_c, width = 8, height = 6.7, units = "in"), 3, 1)

  expect_equal(as.numeric(g_big), as.numeric(g_small), tolerance = 0.05)
  expect_false(attr(g_big, "device_dependent"))
})

test_that("the README §19 success criterion holds end to end", {
  # "incant(p_c) |> select_plot(3) |> translate(dy=24) |> render()" with:
  #   heatmap unmoved, enrichment unmoved, row heights unchanged,
  #   canvas unchanged, p_cluster_c moved up, allowed to enter the heatmap cell.
  skip_if_not_installed("tidyverse")
  s0 = incant(fx_example_p_c(), width = 12, height = 10, units = "in")
  s1 = s0 |> select_plot(3) |> translate(dy = 24, unit = "pt")

  expect_equal(bbox(s0, 1), bbox(s1, 1), tolerance = 1e-9)  # heat
  expect_equal(bbox(s0, 2), bbox(s1, 2), tolerance = 1e-9)  # enrich
  expect_identical(as_gtable(s0)$heights, as_gtable(s1)$heights)
  expect_equal(canvas_size(s0), canvas_size(s1))
  expect_equal(as.numeric(gap(s1, 3, 1)), 44.89 - 24, tolerance = 0.05)

  expect_s3_class(render(s1), "gtable")
})

test_that("place_below() closes the gap to a stated target without arithmetic", {
  # What the agent SHOULD be able to say. No dy, no measuring, no overshoot.
  skip_if_not_installed("tidyverse")
  s1 = incant(fx_example_p_c(), width = 12, height = 10, units = "in") |>
    place_below(3, 1, gap = 6, unit = "pt")

  expect_equal(as.numeric(gap(s1, 3, 1)), 6, tolerance = 0.05)
})

test_that("gap() is signed and directional", {
  skip_if_not_installed("tidyverse")
  scene = incant(fx_example_p_c(), width = 12, height = 10, units = "in")

  # Overlapping elements must report a NEGATIVE gap, not an absolute distance,
  # or the agent cannot tell "too far" from "on top of each other".
  s1 = scene |> select_plot(3) |> translate(dy = 80, unit = "pt")
  expect_lt(as.numeric(gap(s1, 3, 1)), 0)
})

test_that("inspect() gives an agent everything it needs in one table", {
  skip_if_not_installed("tidyverse")
  reg = inspect(incant(fx_example_p_c(), width = 12, height = 10, units = "in"))

  expect_true(all(c("id", "role", "plot_index", "left", "bottom", "right",
                    "top", "container", "path", "is_empty") %in% names(reg)))
  expect_true(all(c("plot-1", "plot-2", "plot-3") %in% reg$id))
  expect_false(any(is.na(reg$left[!reg$is_empty])))
})
