# REVIEW §2.2 -- THE most important test in this suite.
#
# The prototype does `for (i in grep(pattern, names))`. When the pattern matches
# nothing, grep returns integer(0), the loop body never runs, and the function
# returns the gtable UNCHANGED. The caller gets a success value and a plot that
# did not move.
#
# For a human that is a wasted minute. For an agent it is a token bonfire:
# it renders, sees no change, assumes dy was too small, doubles it, fails again,
# forever. A selector that resolves to nothing MUST be an error.

test_that("selecting a non-existent plot index errors instead of returning unchanged", {
  scene = incant(fx_panel_row(), width = 12, height = 10, units = "in")

  expect_error(scene |> select_plot(99), class = "inc_error_no_match")
  expect_error(scene |> select_plot(0), class = "inc_error_no_match")

  # And the message must name what WAS available, so an agent can self-correct
  # from the condition alone instead of guessing again.
  err = tryCatch(scene |> select_plot(99), error = function(e) e)
  expect_match(conditionMessage(err), "available")
  expect_true(all(vapply(1:3, \(i) grepl(i, conditionMessage(err)), logical(1))))
})

test_that("selecting an EXPLICIT plot_spacer errors as empty, not as missing", {
  # The user wrote plot_spacer() as the 4th element of the composition, so
  # index 4 is a legitimate address -- it just has nothing in it. That is a
  # different condition from "there is no plot 4", and an agent needs to tell
  # them apart: one means "fix your index", the other means "fix your figure".
  #
  # (MEASURED: patchwork names the spacer's cells panel_patch-4 / background-4,
  # so it has no "panel-4" -- the registry must still expose it as index 4.)
  #
  # Contrast with test-backend-aplot.R, where aplot's spacer is an IMPLICIT
  # filler the user never wrote: that one gets no plot_index at all.
  scene = incant(fx_panel_row(), width = 12, height = 10, units = "in")

  expect_error(scene |> select_plot(4), class = "inc_error_empty_target")
})

test_that("a selection that resolves to only zeroGrobs errors", {
  scene = incant(fx_panel_row(), width = 12, height = 10, units = "in")

  # fx_cluster() has no axis text at all -> axis-l-3 is a zeroGrob.
  expect_error(
    scene |> select_role("axis-l", plot = 3),
    class = "inc_error_empty_target"
  )
})

test_that("translate() on a live selection actually changes the rendered position", {
  # The positive control for every test above: prove the no-op detector is not
  # simply rejecting everything.
  scene = incant(fx_panel_row(), width = 12, height = 10, units = "in")

  before = bbox(scene, 3)
  after = scene |> select_plot(3) |> translate(dy = 24, unit = "pt") |> bbox(3)

  expect_equal(after$bottom - before$bottom, 24, tolerance = 0.01)
})

test_that("select_role() with an unknown role errors and lists valid roles", {
  scene = incant(fx_panel_row(), width = 12, height = 10, units = "in")

  err = tryCatch(scene |> select_role("legendd"), error = function(e) e)
  expect_s3_class(err, "inc_error_no_match")
  expect_match(conditionMessage(err), "legend")   # did you mean ...
})
