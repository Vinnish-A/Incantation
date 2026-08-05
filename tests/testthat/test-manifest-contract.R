test_that("declarative constraints survive manifest round trips across devices", {
  p = ((ggplot(mtcars, aes(wt, mpg)) + geom_point()) /
         plot_spacer() /
         (ggplot(mtcars, aes(wt, hp)) + geom_point())) +
    plot_layout(heights = c(4, 1, 4))

  big = incant(p, width = 10, height = 8) |> place_below(3, 1, gap = 6)
  man = as_manifest(big)
  expect_equal(man$incantation_version, 2L)
  expect_equal(man$operations[[1]]$type, "place_below")
  expect_equal(man$operations[[1]]$gap, 6)

  path = tempfile(fileext = ".json")
  write_incantation(big, path)
  small = apply_incantation(incant(p, width = 5, height = 4), path)
  expect_equal(as.numeric(gap(small, 3, 1)), 6, tolerance = 0.01)
})

test_that("raw translations remain bound to their measured device", {
  scene = incant(fx_opaque_stack(), width = 10, height = 8) |>
    select_plot(2) |>
    translate(dy = 12)
  path = tempfile(fileext = ".json")
  write_incantation(scene, path)

  expect_error(
    apply_incantation(incant(fx_opaque_stack(), width = 5, height = 4), path),
    class = "inc_error_device_mismatch"
  )
})

test_that("manifest operations validate version and targets before rendering", {
  scene = incant(fx_opaque_stack(), width = 10, height = 8)
  path = tempfile(fileext = ".json")
  jsonlite::write_json(
    list(incantation_version = 2L, device = scene$device,
         operations = list(list(type = "translate", target = "plot-99",
                                dx = 1, dy = 0, clip = "off",
                                include_background = FALSE))),
    path, auto_unbox = TRUE
  )
  expect_error(apply_incantation(scene, path), class = "inc_error_no_match")

  jsonlite::write_json(
    list(incantation_version = 1L, device = scene$device, operations = list()),
    path, auto_unbox = TRUE
  )
  expect_error(apply_incantation(scene, path), class = "inc_error_manifest_version")
})
