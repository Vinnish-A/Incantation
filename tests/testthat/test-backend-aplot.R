# REVIEW §1.2 -- the aplot index trap.
#
# MEASURED (dev/characterization.R), for
#   ap = p1 |> insert_left(p2) |> insert_top(p3)
#
#   gtable cell   what's actually in it
#   -----------   ---------------------
#   panel-1       EMPTY SPACER
#   panel-2       p2  (insert_left)
#   panel-3       p3  (insert_top)
#   panel-4       p1  (THE MAIN PLOT)
#
# whereas plain patchwork gives panel-1 == p1.
#
# So README §6.2's promise -- "behaviour must not differ just because the target
# is a ggplot / patchwork / gtable" -- is already broken at the INDEX level
# before any transform runs. select_plot(1) selects the main plot in one backend
# and an empty cell in the other. The adapter must map the index explicitly.

fx_aplot = function() {
  p1 = ggplot(mtcars, aes(wt, mpg)) + geom_point() + labs(y = "MPG_MAIN")
  p2 = ggplot(mtcars, aes(wt, hp)) + geom_point() + labs(y = "HP_LEFT")
  p3 = ggplot(mtcars, aes(factor(cyl))) + geom_bar() + labs(y = "BAR_TOP")
  p1 |> aplot::insert_left(p2, width = .5) |> aplot::insert_top(p3, height = .3)
}

test_that("select_plot(1) on an aplot selects the MAIN plot, not gtable panel-1", {
  fx_skip_unless_backend("aplot")
  scene = incant(fx_aplot(), width = 10, height = 8, units = "in")

  # The user's mental model: plot 1 is the plot they started the pipe with.
  reg = inspect(scene) |> subset(role == "panel" & plot_index == 1)

  expect_equal(nrow(reg), 1)
  expect_equal(reg$id, "plot-1/panel")

  # ...and it must resolve to the gtable cell holding MPG_MAIN, i.e. panel-4.
  expect_equal(reg$grob_name, "panel-4")
})

test_that("the aplot spacer slot is not addressable as a plot index", {
  fx_skip_unless_backend("aplot")
  scene = incant(fx_aplot(), width = 10, height = 8, units = "in")

  # gtable panel-1 is an empty slot. It has no user-facing index at all, and
  # must never be silently handed back for select_plot(1).
  expect_false(any(inspect(scene)$grob_name == "panel-1" &
                     !is.na(inspect(scene)$plot_index)))
})

test_that("aplot and patchwork agree on what select_plot(1) MEANS", {
  fx_skip_unless_backend("aplot")
  p1 = ggplot(mtcars, aes(wt, mpg)) + geom_point() + labs(y = "MPG_MAIN")
  p2 = ggplot(mtcars, aes(wt, hp)) + geom_point() + labs(y = "HP_LEFT")

  s_ap = incant(p1 |> aplot::insert_left(p2, width = .5),
                width = 10, height = 8, units = "in")
  s_pw = incant(p1 + p2, width = 10, height = 8, units = "in")

  # Both must point at the plot the user called p1. This is the cross-backend
  # contract the README claims but never secures.
  expect_equal(plot_label(s_ap, 1), plot_label(s_pw, 1))
})

test_that("the aplot index map is derived from $layout, not assumed", {
  fx_skip_unless_backend("aplot")
  # A layout whose spacer sits somewhere else, to catch an adapter that
  # hardcodes "main plot == last panel" from the fixture above.
  p1 = ggplot(mtcars, aes(wt, mpg)) + geom_point() + labs(y = "MAIN")
  p2 = ggplot(mtcars, aes(wt, hp)) + geom_point() + labs(y = "RIGHT")
  ap = p1 |> aplot::insert_right(p2, width = .5)

  scene = incant(ap, width = 10, height = 8, units = "in")
  expect_equal(plot_label(scene, 1), "MAIN")
  expect_equal(plot_label(scene, 2), "RIGHT")
})

test_that("translating an aplot subplot keeps the aplot layout frozen", {
  fx_skip_unless_backend("aplot")
  s0 = incant(fx_aplot(), width = 10, height = 8, units = "in")
  s1 = s0 |> select_plot(2) |> translate(dy = 12, unit = "pt")

  expect_identical(as_gtable(s0)$heights, as_gtable(s1)$heights)
  expect_equal(bbox(s0, 1), bbox(s1, 1), tolerance = 1e-9)
  expect_equal(bbox(s1, 2)$bottom - bbox(s0, 2)$bottom, 12,
               tolerance = 1e-6)
})
