# Measurement is the product (REVIEW Phase 0): it turns "too far below the
# heatmap" into a number an agent can act on. A reference is either an integer
# (plot index) or a string (element id) -- no base-masking locator functions.

.resolve = function(scene, ref) {
  if (inherits(ref, "inc_scene")) {          # a piped selection: use its anchor
    if (is.null(ref$active)) inc_abort("no active selection to measure", class = "inc_error_no_selection")
    return(.el(ref, ref$active$ids[1]))
  }
  if (is.numeric(ref)) {
    id = paste0("plot-", as.integer(ref))
    el = scene$registry[[id]]
    if (is.null(el)) {
      idx = vapply(Filter(function(e) e$role == "plot", scene$registry), `[[`, integer(1), "plot_index")
      err_no_match(sprintf("plot index %s", ref), sort(idx))
    }
    return(el)
  }
  .el(scene, as.character(ref))
}

# Anchor may be one part (normal panel) or several (facet panels) -> union.
.anchor_rect = function(scene, el) {
  rects = lapply(el$parts[el$anchor], function(part) .part_rect(scene, part))
  rect_union(rects)
}

#' Bounding box of an element, in device points
#'
#' @param scene An `inc_scene`.
#' @param ref A plot index (integer) or element id (string). For a whole plot the
#'   box is its panel -- the data region, the useful visual anchor.
#' @return A list with `left`, `bottom`, `right`, `top` (pt) and a `device` attr.
#' @export
bbox = function(scene, ref) {
  el = .resolve(scene, ref)
  r = .anchor_rect(scene, el)
  structure(
    list(left = unname(r["left"]), bottom = unname(r["bottom"]),
         right = unname(r["right"]), top = unname(r["top"])),
    device = scene$device,
    class = "inc_bbox"
  )
}

#' @export
print.inc_bbox = function(x, ...) {
  cat(sprintf("<inc_bbox> l=%.2f b=%.2f r=%.2f t=%.2f pt  (@ %g x %g %s)\n",
              x$left, x$bottom, x$right, x$top,
              attr(x, "device")$width, attr(x, "device")$height, attr(x, "device")$units))
  invisible(x)
}

# Does the span between two cells cross a null (device-dependent) track?
# This is what lets gap() warn that a pt offset is not portable (REVIEW s2.1).
.spans_null = function(scene, a, b, direction) {
  el_a = .resolve(scene, a); el_b = .resolve(scene, b)
  pa = el_a$parts[[el_a$anchor[1]]]; pb = el_b$parts[[el_b$anchor[1]]]
  # only decidable when both live at the top level of the same gtable
  if (length(pa$grob_path) != 1 || length(pb$grob_path) != 1) return(FALSE)
  gt = scene$base
  fa = pa$frames[[1]]; fb = pb$frames[[1]]
  if (direction == "vertical") {
    tracks = gt$heights
    lo = min(fa$b, fb$b); hi = max(fa$t, fb$t)
    between = seq_len(length(tracks))[seq_len(length(tracks)) > lo & seq_len(length(tracks)) < hi]
  } else {
    tracks = gt$widths
    lo = min(fa$r, fb$r); hi = max(fa$l, fb$l)
    between = seq_len(length(tracks))[seq_len(length(tracks)) > lo & seq_len(length(tracks)) < hi]
  }
  if (length(between) == 0) return(FALSE)
  any(grid::unitType(tracks[between]) == "null")
}

#' Signed gap between two elements, in device points
#'
#' Positive means separated; negative means overlapping. For two plots the gap is
#' measured panel-to-panel. The result carries a `device_dependent` attribute:
#' when the span crosses a null track, the same pt value will not reproduce at a
#' different device size (REVIEW s2.1) -- use [place_below()] instead.
#'
#' @param scene An `inc_scene`.
#' @param a,b Plot indices or element ids.
#' @param direction "vertical" or "horizontal".
#' @export
gap = function(scene, a, b, direction = "vertical") {
  ra = bbox(scene, a); rb = bbox(scene, b)
  if (direction == "vertical") {
    # positive = separated. If a sits above b, gap = a.bottom - b.top; if a sits
    # below b, gap = b.bottom - a.top.
    g = if (ra$bottom >= rb$bottom) ra$bottom - rb$top else rb$bottom - ra$top
  } else {
    g = if (ra$left >= rb$left) ra$left - rb$right else rb$left - ra$right
  }
  dep = .spans_null(scene, a, b, direction)
  structure(g, unit = "pt", device = scene$device,
            device_dependent = dep,
            reason = if (dep) "span crosses a null (device-dependent) track" else "span is all absolute tracks",
            class = "inc_gap")
}

#' @export
print.inc_gap = function(x, ...) {
  cat(sprintf("<inc_gap> %.2f pt  [%s]\n", unclass(x),
              if (isTRUE(attr(x, "device_dependent"))) "device-dependent: not a portable offset" else "portable"))
  invisible(x)
}

#' @export
as.numeric.inc_gap = function(x, ...) unclass(x)[[1]]

#' Registry of a scene as a data frame
#'
#' One row per addressable element, with current device coordinates.
#' @param scene An `inc_scene`.
#' @export
inspect = function(scene) {
  els = scene$registry
  rect = lapply(els, function(el) {
    if (isTRUE(el$is_empty)) return(c(left = NA, bottom = NA, right = NA, top = NA))
    .anchor_rect(scene, el)
  })
  data.frame(
    id = vapply(els, `[[`, character(1), "id"),
    role = vapply(els, `[[`, character(1), "role"),
    plot_index = vapply(els, function(e) as.integer(e$plot_index), integer(1)),
    grob_name = vapply(els, function(e) {
      if (.is_decoration_element(e)) return(e$id)
      p = e$parts[[e$anchor[1]]]
      nm = scene$base$layout$name
      if (length(p$grob_path) == 1) nm[p$grob_path] else "<nested>"
    }, character(1)),
    container = vapply(els, `[[`, character(1), "container"),
    is_empty = vapply(els, function(e) isTRUE(e$is_empty), logical(1)),
    left = vapply(rect, function(r) unname(r["left"]), numeric(1)),
    bottom = vapply(rect, function(r) unname(r["bottom"]), numeric(1)),
    right = vapply(rect, function(r) unname(r["right"]), numeric(1)),
    top = vapply(rect, function(r) unname(r["top"]), numeric(1)),
    path = I(lapply(els, function(e) e$parts[[e$anchor[1]]]$grob_path)),
    row.names = NULL,
    stringsAsFactors = FALSE
  )
}

#' Is an element empty (a spacer or blank grob)?
#' @param scene An `inc_scene`.
#' @param id Element id.
#' @export
is_empty_element = function(scene, id) isTRUE(.el(scene, id)$is_empty)

#' The y-axis title text of a plot, used to identify which plot an index points to
#' @param scene An `inc_scene`.
#' @param ref Plot index or element id.
#' @export
plot_label = function(scene, ref) {
  el = .resolve(scene, ref)
  # find the ylab-l element belonging to the same plot
  ylab_id = paste0("plot-", el$plot_index, "/ylab-l")
  ye = scene$registry[[ylab_id]]
  if (is.null(ye)) return(NA_character_)
  g = grob_at(scene$base, ye$parts[[1]]$grob_path)
  .grob_text(g)
}

.grob_text = function(g) {
  if (is_blank_grob(g)) return("<empty>")
  lab = tryCatch(g$children[[1]]$label, error = function(e) NULL)
  if (is.null(lab)) lab = tryCatch(g$label, error = function(e) NULL)
  if (is.null(lab) || length(lab) == 0) return("<no label>")
  paste(lab, collapse = ",")
}
