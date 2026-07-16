# REVIEW §2.1 -- the flaw the GPT README does not know it has.
#
# The README says "prefer absolute units, guarantee consistent physical
# displacement". That guarantees the SIZE OF THE MOVE is stable. It does not
# guarantee the RESULT is stable, because what the agent measured to pick dy
# may itself be device-dependent.
#
# Measured facts (dev/characterization.R):
#   - gap spanning only absolute rows : 37.39pt at 10x8, 5x4 and 10x16.  portable
#   - gap spanning a null row         : 69.6 / 101.6 / 165.6 pt.         NOT portable
#   - any element's own size (null)   : 101 / 245 / 533 pt.              NOT portable
#
# So: a scene MUST bind a device size, render MUST match it, and the
# device-independent primitive must be a CONSTRAINT (place_below), not an offset.

test_that("scene construction requires an explicit device size", {
  # Without a device size, every measurement below is meaningless.
  expect_error(incant(fx_panel_row()), class = "inc_error_no_device")
})

test_that("bbox and gap are reported together with the device they were measured at", {
  scene = incant(fx_panel_row(), width = 12, height = 10, units = "in")
  b = bbox(scene, 3)

  expect_equal(attr(b, "device"), list(width = 12, height = 10, units = "in"))
})

test_that("rendering at a different size than the scene was measured at is refused", {
  scene = incant(fx_panel_row(), width = 12, height = 10, units = "in") |>
    select_plot(3) |>
    translate(dy = 38.89, unit = "pt")

  # Silently honouring this is how the agent's 38.89pt becomes an overshoot.
  expect_error(
    ggsave_incant(scene, tempfile(fileext = ".png"), width = 8, height = 6),
    class = "inc_error_device_mismatch"
  )

  # Same size: fine.
  expect_no_error(
    ggsave_incant(scene, tempfile(fileext = ".png"), width = 12, height = 10)
  )
})

test_that("gap() across only absolute rows is stable across device sizes", {
  p = (ggplot(mtcars, aes(wt, mpg)) + geom_point()) /
    (ggplot(mtcars, aes(wt, hp)) + geom_point())

  g_big = gap(incant(p, width = 10, height = 8, units = "in"), 2, 1)
  g_small = gap(incant(p, width = 5, height = 4, units = "in"), 2, 1)

  expect_equal(as.numeric(g_big), as.numeric(g_small), tolerance = 1e-6)
})

test_that("gap() across a null row is NOT stable, and incantation says so", {
  p = ((ggplot(mtcars, aes(wt, mpg)) + geom_point()) /
         plot_spacer() /
         (ggplot(mtcars, aes(wt, hp)) + geom_point())) +
    plot_layout(heights = c(4, 1, 4))

  g_big = gap(incant(p, width = 10, height = 8, units = "in"), 3, 1)
  g_small = gap(incant(p, width = 5, height = 4, units = "in"), 3, 1)

  expect_gt(as.numeric(g_big), as.numeric(g_small) + 10)

  # The agent has no way to know this from the number alone, so the measurement
  # must carry the warning with it.
  expect_true(attr(g_big, "device_dependent"))
  expect_match(attr(g_big, "reason"), "null")
})

test_that("place_below() is device-independent where a raw translate() is not", {
  # This is the whole argument for making constraints a Phase-2 primitive
  # instead of a Phase-4 convenience.
  p = ((ggplot(mtcars, aes(wt, mpg)) + geom_point()) /
         plot_spacer() /
         (ggplot(mtcars, aes(wt, hp)) + geom_point())) +
    plot_layout(heights = c(4, 1, 4))

  render_gap = function(w, h) {
    s = incant(p, width = w, height = h, units = "in") |>
      place_below(3, 1, gap = 6, unit = "pt")
    as.numeric(gap(s, 3, 1))
  }

  # Re-resolved at each device size -> the RESULT is 6pt either way.
  expect_equal(render_gap(10, 8), 6, tolerance = 0.01)
  expect_equal(render_gap(5, 4), 6, tolerance = 0.01)
})

test_that("unit conversion is exact across pt / mm / cm / in", {
  base = incant(fx_panel_row(), width = 12, height = 10, units = "in")
  dy_of = function(v, u) {
    s = base |> select_plot(3) |> translate(dy = v, unit = u)
    bbox(s, 3)$bottom - bbox(base, 3)$bottom
  }
  expect_equal(dy_of(72, "pt"), dy_of(1, "in"), tolerance = 1e-6)
  expect_equal(dy_of(72, "pt"), dy_of(25.4, "mm"), tolerance = 1e-6)
  expect_equal(dy_of(72, "pt"), dy_of(2.54, "cm"), tolerance = 1e-6)
})
