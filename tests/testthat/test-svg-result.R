fx_svg_labels = function() {
  ggplot(mtcars, aes(wt, mpg, label = rownames(mtcars))) +
    geom_point() +
    geom_text()
}

test_that("SVG capture exposes result primitives and preserves text", {
  svg = incant(fx_svg_labels(), width = 6, height = 4) |> as_svg()
  man = svg_manifest(svg)

  expect_s3_class(svg, "inc_svg")
  expect_equal(sum(man$tag == "circle"), nrow(mtcars))
  expect_true(all(rownames(mtcars) %in% man$text))
  expect_true(all(nzchar(man$id)))
  expect_true(all(c("transform", "clip", "visible", "bbox_quality") %in% names(man)))
  expect_identical(svg_manifest(svg)$id, svg_manifest(svg)$id)
})

test_that("one SVG text node moves without changing sibling geometry", {
  svg = incant(fx_svg_labels(), width = 6, height = 4) |> as_svg()
  before = svg_manifest(svg)
  edited = svg |>
    select_svg_text("Mazda RX4") |>
    svg_translate(dy = 6) |>
    svg_style(fill = "#FF0000")
  after = svg_manifest(edited)
  id = before$id[before$text == "Mazda RX4"]

  expect_length(svg$operations, 0)
  expect_equal(after$bottom[after$id == id] - before$bottom[before$id == id], 6)
  expect_equal(after$fill[after$id == id], "#FF0000")
  other = before$id != id & !is.na(before$left)
  expect_equal(after[other, c("left", "bottom", "right", "top")],
               before[other, c("left", "bottom", "right", "top")])
})

test_that("SVG selectors reject missing and ambiguous matches", {
  svg = incant(fx_svg_labels(), width = 6, height = 4) |> as_svg()
  expect_error(select_svg_text(svg, "not present"), class = "inc_error_no_match")
  expect_error(select_svg_text(svg, "Merc", fixed = FALSE), class = "inc_error_ambiguous")
  expect_gt(length(select_svg_text(svg, "Merc", fixed = FALSE, all = TRUE)$active), 1)
})

test_that("SVG scale, rotation, hiding and z-order produce valid SVG", {
  svg = incant(fx_svg_labels(), width = 6, height = 4) |> as_svg()
  selected = svg |> select_svg_text("Mazda RX4")
  variants = list(
    selected |> svg_scale(1.2),
    selected |> svg_rotate(15),
    selected |> svg_hide(),
    selected |> svg_zorder("front"),
    selected |> svg_zorder("back")
  )
  for (variant in variants) expect_s3_class(xml2::read_xml(incantation:::.svg_text(variant)), "xml_document")
})

test_that("pixel verification distinguishes edits from no-ops", {
  skip_if_not_installed("rsvg")
  svg = incant(fx_svg_labels(), width = 6, height = 4) |> as_svg()
  edited = svg |> select_svg_text("Mazda RX4") |> svg_translate(dy = 6)

  expect_equal(verify_svg(svg, svg, width = 600, height = 400)$status, "no_change")
  report = verify_svg(svg, edited, width = 600, height = 400)
  expect_equal(report$status, "changed")
  expect_gt(report$changed_pixels, 100)
  expect_equal(report$unexpected_changed_pixels, 0)
  expect_equal(report$targets, "svg-text-0001")
})

test_that("scene SVG export uses editable text rather than glyph outlines", {
  scene = incant(fx_svg_labels(), width = 6, height = 4)
  path = tempfile(fileext = ".svg")
  ggsave_incant(scene, path)
  output = paste(readLines(path, warn = FALSE), collapse = "\n")
  expect_match(output, "<text ")
  expect_match(output, "Mazda RX4")
})

test_that("edited SVG can be written as a standalone result", {
  svg = incant(fx_svg_labels(), width = 6, height = 4) |>
    as_svg() |>
    select_svg_text("Mazda RX4") |>
    svg_translate(dy = 6)
  path = tempfile(fileext = ".svg")
  write_svg(svg, path)
  expect_true(file.exists(path))
  expect_s3_class(xml2::read_xml(path), "xml_document")
})

test_that("SVG operations serialise and replay only on the same snapshot", {
  svg = incant(fx_svg_labels(), width = 6, height = 4) |> as_svg()
  edited = svg |>
    select_svg_text("Mazda RX4") |>
    svg_translate(dy = 6) |>
    svg_style(fill = "#FF0000")
  path = tempfile(fileext = ".json")
  write_incantation(edited, path)
  replayed = apply_incantation(svg, path)

  expect_equal(incantation:::.svg_text(replayed), incantation:::.svg_text(edited))
  other = incant(fx_svg_labels() + labs(title = "different"), width = 6, height = 4) |> as_svg()
  expect_error(apply_incantation(other, path), class = "inc_error_svg_source")
})
