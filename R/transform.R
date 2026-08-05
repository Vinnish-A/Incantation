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

# Resolve a public reference once, while preserving a semantic constraint in the
# operation log. Raw translations stay device-bound; constraints are re-measured
# against whichever scene receives the manifest.
.target_id = function(scene, ref) .resolve(scene, ref)$id

.push_constraint = function(scene, type, a, b, gap = NULL, unit = NULL) {
  op = list(type = type, target = .target_id(scene, a), reference = .target_id(scene, b))
  if (!is.null(gap)) op$gap = .to_pt(gap, unit)
  .push(scene, op)
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
  .push_constraint(scene, "place_below", a, b, gap, unit)
}

#' Place plot `a` a stated gap above plot `b`
#' @inheritParams place_below
#' @export
place_above = function(scene, a, b, gap = 0, unit = "pt") {
  .push_constraint(scene, "place_above", a, b, gap, unit)
}

#' Align the top / bottom / left / right edge of `a` to `b`
#' @param scene An `inc_scene`.
#' @param a,b Plot indices or element ids.
#' @name align
#' @export
align_top = function(scene, a, b) .push_constraint(scene, "align_top", a, b)
#' @rdname align
#' @export
align_bottom = function(scene, a, b) .push_constraint(scene, "align_bottom", a, b)
#' @rdname align
#' @export
align_left = function(scene, a, b) .push_constraint(scene, "align_left", a, b)
#' @rdname align
#' @export
align_right = function(scene, a, b) .push_constraint(scene, "align_right", a, b)

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

.translate_op = function(target, dx = 0, dy = 0) {
  list(type = "translate", target = target, dx = dx, dy = dy,
       clip = "off", include_background = FALSE)
}

.resolve_constraint = function(scene, op) {
  a = op$target
  b = op$reference
  ba = bbox(scene, a)
  bb = bbox(scene, b)

  switch(op$type,
    place_below = {
      cur = as.numeric(gap(scene, a, b, "vertical"))
      dy = if (ba$bottom < bb$bottom) cur - op$gap else op$gap - cur
      .translate_op(a, dy = dy)
    },
    place_above = {
      cur = as.numeric(gap(scene, a, b, "vertical"))
      dy = if (ba$bottom > bb$bottom) op$gap - cur else cur - op$gap
      .translate_op(a, dy = dy)
    },
    align_top = .translate_op(a, dy = bb$top - ba$top),
    align_bottom = .translate_op(a, dy = bb$bottom - ba$bottom),
    align_left = .translate_op(a, dx = bb$left - ba$left),
    align_right = .translate_op(a, dx = bb$right - ba$right)
  )
}

.constraint_types = c("place_below", "place_above", "align_top", "align_bottom",
                      "align_left", "align_right")

.resolved_transforms = function(scene) {
  out = list()
  for (op in scene$transforms) {
    if (op$type %in% .constraint_types) {
      current = scene
      current$transforms = out
      out = c(out, list(.resolve_constraint(current, op)))
    } else {
      out = c(out, list(op))
    }
  }
  out
}
