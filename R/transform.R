# Transforms. Each appends a structured operation to the scene's log and returns
# the scene; the log is replayed onto a fresh gtable at render time. The active
# selection is retained so z-ops can chain after a translate.

.require_active = function(scene, fn) {
  if (is.null(scene$active)) err_no_selection(fn)
  scene$active$target
}

.push = function(scene, op) {
  scene$transforms = c(scene$transforms, list(op))
  scene
}

#' Move the selected element after layout
#'
#' Positive `dy` moves up, positive `dx` moves right (grid convention). The move
#' is device-absolute: it is correct only at the scene's bound device size. For a
#' device-independent result, state the target gap with [place_below()] instead
#' (REVIEW s2.1). For a whole plot the opaque background is left behind unless
#' `include_background = TRUE` (REVIEW s2.3).
#'
#' @param scene An `inc_scene` with an active selection.
#' @param dx,dy Offsets.
#' @param unit One of "pt", "mm", "cm", "in".
#' @param clip "off" (default), "on" or "inherit".
#' @param include_background Move the subplot's opaque background too?
#' @export
translate = function(scene, dx = 0, dy = 0, unit = "pt", clip = "off",
                     include_background = FALSE) {
  target = .require_active(scene, "translate")
  .push(scene, list(type = "translate", target = target,
                    dx = .to_pt(dx, unit), dy = .to_pt(dy, unit),
                    clip = clip, include_background = include_background))
}

# shared helper: move plot `a` vertically/horizontally by dy/dx pt
.move_plot = function(scene, a, dx = 0, dy = 0, clip = "off") {
  target = if (is.numeric(a)) paste0("plot-", as.integer(a)) else as.character(a)
  if (is.null(scene$registry[[target]])) err_no_match(sprintf("`%s`", target), names(scene$registry))
  .push(scene, list(type = "translate", target = target, dx = dx, dy = dy,
                    clip = clip, include_background = FALSE))
}

#' Place plot `a` a stated gap below plot `b` (device-independent)
#'
#' Unlike a raw [translate()], this resolves the offset from the *current*
#' geometry at render time, so the resulting gap is the same at any device size.
#' @param scene An `inc_scene`.
#' @param a,b Plot indices or element ids; `a` is placed relative to `b`.
#' @param gap,unit Target gap.
#' @export
place_below = function(scene, a, b, gap = 0, unit = "pt") {
  g = .to_pt(gap, unit)
  cur = as.numeric(gap(scene, a, b, "vertical"))
  a_below = bbox(scene, a)$bottom < bbox(scene, b)$bottom
  dy = if (a_below) cur - g else g - cur
  .move_plot(scene, a, dy = dy)
}

#' Place plot `a` a stated gap above plot `b`
#' @inheritParams place_below
#' @export
place_above = function(scene, a, b, gap = 0, unit = "pt") {
  g = .to_pt(gap, unit)
  cur = as.numeric(gap(scene, a, b, "vertical"))
  a_above = bbox(scene, a)$bottom > bbox(scene, b)$bottom
  dy = if (a_above) g - cur else cur - g
  .move_plot(scene, a, dy = dy)
}

#' Align the top / bottom / left / right edge of `a` to `b`
#' @param scene An `inc_scene`.
#' @param a,b Plot indices or element ids.
#' @name align
#' @export
align_top = function(scene, a, b) .move_plot(scene, a, dy = bbox(scene, b)$top - bbox(scene, a)$top)
#' @rdname align
#' @export
align_bottom = function(scene, a, b) .move_plot(scene, a, dy = bbox(scene, b)$bottom - bbox(scene, a)$bottom)
#' @rdname align
#' @export
align_left = function(scene, a, b) .move_plot(scene, a, dx = bbox(scene, b)$left - bbox(scene, a)$left)
#' @rdname align
#' @export
align_right = function(scene, a, b) .move_plot(scene, a, dx = bbox(scene, b)$right - bbox(scene, a)$right)

#' Raise the selected plot to the front / send it to the back
#'
#' A draw-order change only: the layout stays frozen (REVIEW s2.4).
#' @param scene An `inc_scene` with an active selection.
#' @name zorder
#' @export
bring_to_front = function(scene) {
  target = .require_active(scene, "bring_to_front")
  .push(scene, list(type = "z", target = target, z = "front"))
}
#' @rdname zorder
#' @export
send_to_back = function(scene) {
  target = .require_active(scene, "send_to_back")
  .push(scene, list(type = "z", target = target, z = "back"))
}

# effective z of a plot element = base z (+/- a large offset if restacked)
.effective_z = function(scene, el) {
  z = max(vapply(el$parts, `[[`, numeric(1), "z"))
  for (tr in scene$transforms) {
    if (identical(tr$type, "z") && identical(tr$target, el$id)) {
      z = z + switch(tr$z, front = 1e6, back = -1e6, 0)
    }
  }
  z
}
