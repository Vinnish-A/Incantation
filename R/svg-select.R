.set_svg_active = function(x, ids, what, all = FALSE) {
  ids = unique(ids)
  available = svg_manifest(x)$id
  if (!length(ids)) err_no_match(what, available)
  if (!all && length(ids) > 1) {
    inc_abort(sprintf("%s matched %d SVG elements; refine the selector or pass `all = TRUE`.", what, length(ids)),
              class = "inc_error_ambiguous", available = ids)
  }
  x$active = if (all) ids else ids[[1]]
  x
}

#' Select SVG result primitives
#'
#' Selectors operate only on the rendered SVG snapshot. An empty match is always
#' an error; ambiguous matches require `all = TRUE`.
#' @param x An `inc_svg`.
#' @param id Snapshot-local element id.
#' @param all Select every match?
#' @name svg-select
NULL

#' @rdname svg-select
#' @export
select_svg_id = function(x, id, all = FALSE) {
  hit = intersect(as.character(id), svg_manifest(x)$id)
  .set_svg_active(x, hit, sprintf("SVG id `%s`", paste(id, collapse = ", ")), all)
}

#' @param text Text to match.
#' @param fixed Use exact matching rather than a regular expression?
#' @rdname svg-select
#' @export
select_svg_text = function(x, text, fixed = TRUE, all = FALSE) {
  man = svg_manifest(x)
  keep = man$tag == "text" & if (fixed) man$text == text else grepl(text, man$text)
  .set_svg_active(x, man$id[keep], sprintf("SVG text `%s`", text), all)
}

#' @param x_pt,y_pt Device coordinates in points, with origin at bottom-left.
#' @rdname svg-select
#' @export
select_svg_at = function(x, x_pt, y_pt, all = FALSE) {
  man = svg_manifest(x)
  keep = !is.na(man$left) & x_pt >= man$left & x_pt <= man$right &
    y_pt >= man$bottom & y_pt <= man$top
  hit = man[keep, , drop = FALSE]
  if (!all && nrow(hit) > 1) hit = hit[which.max(hit$order), , drop = FALSE]
  .set_svg_active(x, hit$id, sprintf("SVG point (%.2f, %.2f)", x_pt, y_pt), all)
}

#' @param left,bottom,right,top Query rectangle in device points.
#' @rdname svg-select
#' @export
select_svg_bbox = function(x, left, bottom, right, top, all = TRUE) {
  man = svg_manifest(x)
  keep = !is.na(man$left) & man$right >= left & man$left <= right &
    man$top >= bottom & man$bottom <= top
  .set_svg_active(x, man$id[keep], "SVG bounding box", all)
}
