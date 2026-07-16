# REVIEW §4.2 -- cowplot is the one structurally different backend.
#
# MEASURED: plot_grid() returns a ggplot whose gtable has exactly ONE "panel"
# cell. Every subplot lives INSIDE that panel gTree as a child:
#
#   panel$children:  grill, GeomDrawGrob 2, GeomDrawGrob 3, GeomDrawGrob 4, ...
#
# There are no per-subplot cells, no "-k" suffixes, no gtable layout rows to
# unclip. So the registry entry is path = c(panel_cell, child_idx) and
# container = "gtree-child".
#
# This is the test that proves the adapter contract is real: if translate(),
# bbox(), gap() and diagnose() all work here without a single backend branch
# outside inc_capture(), the abstraction holds. If they don't, the package is
# three packages wearing a trench coat.

fx_cow = function() {
  cowplot::plot_grid(
    ggplot(mtcars, aes(wt, mpg)) + geom_point(),
    ggplot(mtcars, aes(wt, hp)) + geom_point(),
    ggplot(mtcars, aes(factor(cyl))) + geom_bar(),
    NULL,
    ncol = 2, rel_widths = c(2, 1), rel_heights = c(9, 1)
  )
}

test_that("cowplot subplots are discovered despite living inside one panel", {
  fx_skip_unless_backend("cowplot")
  scene = incant(fx_cow(), width = 12, height = 10, units = "in")

  expect_equal(sum(inspect(scene)$role == "plot"), 3)
  expect_true(all(c("plot-1", "plot-2", "plot-3") %in% inspect(scene)$id))
})

test_that("cowplot registry entries record a gtree-child path", {
  fx_skip_unless_backend("cowplot")
  reg = inspect(incant(fx_cow(), width = 12, height = 10, units = "in"))
  r3 = reg |> subset(id == "plot-3")

  expect_equal(r3$container, "gtree-child")
  expect_gte(length(r3$path[[1]]), 2)   # descend into the panel, then the child
})

test_that("translate() on cowplot uses the same semantics as on patchwork", {
  fx_skip_unless_backend("cowplot")
  s0 = incant(fx_cow(), width = 12, height = 10, units = "in")
  s1 = s0 |> select_plot(3) |> translate(dy = 24, unit = "pt")

  # same contract as test-invariant-frozen-layout.R, different backend
  expect_equal(bbox(s1, 3)$bottom - bbox(s0, 3)$bottom, 24,
               tolerance = 1e-6)
  expect_equal(bbox(s0, 1), bbox(s1, 1), tolerance = 1e-9)
  expect_equal(canvas_size(s0), canvas_size(s1))
})

test_that("cowplot's single panel cell does not clip a translated child", {
  fx_skip_unless_backend("cowplot")
  # Everything is inside one panel; moving a child far enough hits that panel's
  # boundary, not the gtable's. Unclipping layout$clip is a no-op here -- the
  # adapter has to handle the gTree's own vp.
  s0 = incant(fx_cow(), width = 12, height = 10, units = "in")
  s1 = s0 |> select_plot(3) |> translate(dy = 120, unit = "pt", clip = "off")

  expect_equal(bbox(s1, 3)$bottom - bbox(s0, 3)$bottom, 120,
               tolerance = 1e-6)
  expect_false(any(grepl("clipped", diagnose(s1)$issues)))
})

test_that("plain ggplot (no compositor) is a degenerate one-plot backend", {
  # MEASURED: a bare ggplotGrob has UNSUFFIXED names ("panel", "axis-l"),
  # unlike patchwork's "panel-1". An adapter that assumes the suffix breaks here.
  scene = incant(ggplot(mtcars, aes(wt, mpg)) + geom_point() + labs(title = "T"),
                 width = 6, height = 5, units = "in")

  expect_equal(sum(inspect(scene)$role == "plot"), 1)
  expect_true("plot-1/panel" %in% inspect(scene)$id)

  s1 = scene |> select_role("title", plot = 1) |> translate(dy = -6, unit = "pt")
  expect_equal(bbox(s1, "plot-1/title")$bottom -
                 bbox(scene, "plot-1/title")$bottom, -6, tolerance = 1e-6)
})
