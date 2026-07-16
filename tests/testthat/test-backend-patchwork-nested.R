# REVIEW §1.1 / §1.3 / §1.5 -- patchwork's structure is flat-then-recursive,
# and its cell names are not selectors.

test_that("a patchwork subplot is a grob SET, and translate moves all of it", {
  # REVIEW §1.1: there is no "plot-3" grob. Selecting plot 3 must resolve to
  # ~22 cells sharing the -3 suffix, and every one of them must move together,
  # or the subplot tears apart (panel moves, axis stays).
  scene = incant(fx_panel_row(), width = 12, height = 10, units = "in")

  members = inspect(scene) |> subset(plot_index == 3, "id", drop = TRUE)
  expect_gt(length(members), 5)

  s1 = scene |> select_plot(3) |> translate(dy = 24, unit = "pt")
  for (el in members) {
    if (is_empty_element(scene, el)) next
    d = bbox(s1, el)$bottom - bbox(scene, el)$bottom
    expect_equal(d, 24, tolerance = 1e-6, info = paste("torn:", el))
  }
})

test_that("inset_element is NOT captured by the plot-1 selection", {
  # REVIEW §1.3, MEASURED: the cell is named "inset_2-1", so the prototype's
  # grep("-1$") drags the inset along with subplot 1. Silent, invisible, wrong.
  p1 = ggplot(mtcars, aes(wt, mpg)) + geom_point()
  p2 = ggplot(mtcars, aes(wt, hp)) + geom_point()
  scene = incant(p1 + patchwork::inset_element(p2, .6, .6, 1, 1),
                 width = 10, height = 8, units = "in")

  inset_before = bbox(scene, "inset-2")
  s1 = scene |> select_plot(1) |> translate(dy = 30, unit = "pt")

  expect_equal(bbox(s1, "inset-2"), inset_before, tolerance = 1e-9)
})

test_that("an inset is addressable in its own right", {
  p1 = ggplot(mtcars, aes(wt, mpg)) + geom_point()
  p2 = ggplot(mtcars, aes(wt, hp)) + geom_point()
  scene = incant(p1 + patchwork::inset_element(p2, .6, .6, 1, 1),
                 width = 10, height = 8, units = "in")

  expect_true("inset-2" %in% inspect(scene)$id)
  s1 = scene |> select_id("inset-2") |> translate(dy = -20, unit = "pt")
  expect_equal(bbox(s1, "inset-2")$bottom - bbox(scene, "inset-2")$bottom,
               -20, tolerance = 1e-6)
})

test_that("nested patchwork subplots are reachable via path, not via suffix", {
  # REVIEW §1.5, MEASURED: `p1 | (p2 / p3)` has only ONE top-level panel-1.
  # The nested half is a "patchwork-table-2" gtable grob. A registry built by
  # scanning layout$name finds 1 plot where the user sees 3.
  p1 = ggplot(mtcars, aes(wt, mpg)) + geom_point() + labs(y = "L")
  p2 = ggplot(mtcars, aes(wt, hp)) + geom_point() + labs(y = "TR")
  p3 = ggplot(mtcars, aes(factor(cyl))) + geom_bar() + labs(y = "BR")

  scene = incant(p1 | (p2 / p3), width = 10, height = 8, units = "in")

  expect_equal(sum(inspect(scene)$role == "plot"), 3)
  expect_equal(plot_label(scene, 1), "L")
  expect_equal(plot_label(scene, 2), "TR")
  expect_equal(plot_label(scene, 3), "BR")

  # The path must record the descent through the nested table.
  path3 = inspect(scene) |> subset(id == "plot-3", "path", drop = TRUE)
  expect_gt(length(path3[[1]]), 1)
})

test_that("translating inside a nested patchwork defeats the nested clip", {
  # REVIEW §1.4/§1.5: the ONE real clip="on" container in the whole system is
  # "panel-nested-patchwork-2". A subplot moved out of a nested table gets cut
  # off there unless the adapter unclips the ancestor too.
  p1 = ggplot(mtcars, aes(wt, mpg)) + geom_point()
  p2 = ggplot(mtcars, aes(wt, hp)) + geom_point()
  p3 = ggplot(mtcars, aes(factor(cyl))) + geom_bar()

  scene = incant(p1 | (p2 / p3), width = 10, height = 8, units = "in")
  s1 = scene |> select_plot(3) |> translate(dy = 60, unit = "pt", clip = "off")

  expect_equal(bbox(s1, 3)$bottom - bbox(scene, 3)$bottom, 60,
               tolerance = 1e-6)
  expect_false(any(grepl("clipped", diagnose(s1)$issues)))
})

test_that("select_plot() never returns a regex to the caller", {
  # README §8 is right about this much: grob names are ggplot2/patchwork
  # implementation details and change between versions. They must not leak.
  scene = incant(fx_panel_row(), width = 12, height = 10, units = "in")
  sel = scene |> select_plot(3)

  expect_false(any(grepl("\\$|\\^|\\[", as.character(selection_spec(sel)))))
  expect_equal(selection_spec(sel)$type, "plot")
  expect_equal(selection_spec(sel)$index, 3)
})
