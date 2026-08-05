.svg_text = function(x) as.character(.svg_doc(x))

#' Write an edited SVG snapshot
#' @param x An `inc_svg`.
#' @param path Output SVG path.
#' @export
write_svg = function(x, path) {
  writeLines(.svg_text(x), path, useBytes = TRUE)
  invisible(path)
}

#' Verify the rendered pixel effect of SVG edits
#'
#' Both snapshots are rasterised by librsvg at one fixed size. The report is
#' machine-readable and treats zero changed pixels as a failed edit.
#' @param before,after `inc_svg` snapshots sharing the same source hash.
#' @param width,height Raster dimensions in pixels.
#' @param tolerance Maximum per-channel difference ignored.
#' @return An `inc_svg_verification` list.
#' @export
verify_svg = function(before, after, width = 1600, height = 1200, tolerance = 0) {
  if (!requireNamespace("rsvg", quietly = TRUE)) {
    inc_abort("verify_svg() needs the 'rsvg' package.", class = "inc_error_missing_pkg")
  }
  if (!identical(before$source_hash, after$source_hash)) {
    inc_abort("SVG snapshots have different source hashes.", class = "inc_error_svg_source")
  }
  a = rsvg::rsvg(charToRaw(.svg_text(before)), width = width, height = height)
  b = rsvg::rsvg(charToRaw(.svg_text(after)), width = width, height = height)
  delta = abs(a - b)
  changed = apply(delta, c(1, 2), max) > tolerance
  pos = which(changed, arr.ind = TRUE)
  box = if (nrow(pos)) {
    list(left = min(pos[, 2]), top = min(pos[, 1]),
         right = max(pos[, 2]), bottom = max(pos[, 1]))
  } else {
    list(left = NA_integer_, top = NA_integer_, right = NA_integer_, bottom = NA_integer_)
  }
  targets = unique(unlist(lapply(after$operations, `[[`, "targets"), use.names = FALSE))
  man_before = svg_manifest(before)
  man = svg_manifest(after)
  hit = man[man$id %in% targets & !is.na(man$left), , drop = FALSE]
  outside = nrow(hit) > 0 && any(hit$left < 0 | hit$bottom < 0 |
                                hit$right > after$width | hit$top > after$height)
  expected_boxes = rbind(
    man_before[man_before$id %in% targets, c("left", "bottom", "right", "top"), drop = FALSE],
    man[man$id %in% targets, c("left", "bottom", "right", "top"), drop = FALSE]
  )
  expected_known = nrow(expected_boxes) > 0 && !anyNA(expected_boxes)
  unexpected = NA_integer_
  if (expected_known) {
    expected = matrix(FALSE, nrow = height, ncol = width)
    for (i in seq_len(nrow(expected_boxes))) {
      box_i = expected_boxes[i, ]
      c1 = max(1, min(width, floor(box_i$left / after$width * width) - 2))
      c2 = max(1, min(width, ceiling(box_i$right / after$width * width) + 2))
      r1 = max(1, min(height, floor((after$height - box_i$top) / after$height * height) - 2))
      r2 = max(1, min(height, ceiling((after$height - box_i$bottom) / after$height * height) + 2))
      if (c1 <= c2 && r1 <= r2) expected[r1:r2, c1:c2] = TRUE
    }
    unexpected = sum(changed & !expected)
  }
  structure(
    list(status = if (nrow(pos)) "changed" else "no_change",
         changed_pixels = nrow(pos), change_bbox_px = box,
         unexpected_changed_pixels = unexpected,
         outside_canvas = outside, width = width, height = height,
         targets = targets),
    class = "inc_svg_verification"
  )
}

#' @export
print.inc_svg_verification = function(x, ...) {
  cat(sprintf("<inc_svg_verification> %s  changed_pixels=%d  unexpected=%s  outside_canvas=%s\n",
              x$status, x$changed_pixels,
              if (is.na(x$unexpected_changed_pixels)) "unknown" else x$unexpected_changed_pixels,
              x$outside_canvas))
  invisible(x)
}
