# The scene: a laid-out figure bound to a device size, with a measured registry.
# It is a plain list (never an environment) so that copy-on-modify gives us
# immutability for free -- `scene0` is its own undo (REVIEW: no undo/redo stack
# needed for the MVP).

#' Capture a laid-out figure for post-layout editing
#'
#' @param x A ggplot, patchwork, aplot, cowplot or gtable object.
#' @param width,height,units Device size the scene is measured against. Required:
#'   element geometry is only meaningful once a device of a known size exists, and
#'   a point offset chosen at one size overshoots at another (REVIEW s2.1).
#' @return An `inc_scene`.
#' @export
incant = function(x, width = NULL, height = NULL, units = "in") {
  if (is.null(width) || is.null(height)) err_no_device()
  device = list(width = width, height = height, units = units)

  # Everything happens inside the bound null device: building the gtable needs a
  # device for text metrics (otherwise ggplot2/patchwork open Rplots.pdf), and
  # measuring each part's base rectangle needs the same one. Downstream
  # bbox()/gap() are then pure arithmetic over these + the transform log.
  built = with_scene_device(device, function() {
    cap = inc_capture(x)
    elements = build_elements(cap$root, cap$backend, cap$index_map)
    elements = lapply(elements, function(el) {
      el$parts = lapply(el$parts, function(p) {
        p$base = tryCatch(rect_from_frames(p$frames),
                          error = function(e) c(left = NA, bottom = NA, right = NA, top = NA))
        p
      })
      el
    })
    list(cap = cap, elements = elements)
  })
  cap = built$cap
  registry = stats::setNames(built$elements, vapply(built$elements, `[[`, character(1), "id"))

  structure(
    list(
      base = cap$root,
      backend = cap$backend,
      device = device,
      registry = registry,
      transforms = list(),
      active = NULL
    ),
    class = "inc_scene"
  )
}

# --- internal accessors ------------------------------------------------------

.el = function(scene, id) {
  el = scene$registry[[id]]
  if (is.null(el)) err_no_match(sprintf("id `%s`", id), names(scene$registry))
  el
}

# Net (dx, dy) in pt applied to a given grob_path across the transform log. A
# transform moves a path iff that path is among its target's moved parts.
.net_shift = function(scene, grob_path) {
  dx = 0; dy = 0
  for (tr in .resolved_transforms(scene)) {
    if (is.null(tr$dx) && is.null(tr$dy)) next
    moved = .moved_paths(scene, tr)
    if (any(vapply(moved, identical, logical(1), grob_path))) {
      dx = dx + tr$dx; dy = dy + tr$dy
    }
  }
  list(dx = dx, dy = dy)
}

.moved_paths = function(scene, tr) {
  el = scene$registry[[tr$target]]
  parts = el$parts
  if (!isTRUE(tr$include_background)) parts = parts[!vapply(parts, `[[`, logical(1), "is_background")]
  lapply(parts, `[[`, "grob_path")
}

.canvas_pt = function(scene) {
  c(width = .to_pt(scene$device$width, scene$device$units),
    height = .to_pt(scene$device$height, scene$device$units))
}

#' Canvas size of a scene, in points
#' @param scene An `inc_scene`.
#' @export
canvas_size = function(scene) .canvas_pt(scene)

#' @export
print.inc_scene = function(x, ...) {
  plots = Filter(function(e) e$role == "plot", x$registry)
  cat(sprintf("<inc_scene> backend=%s  device=%g x %g %s\n",
              x$backend, x$device$width, x$device$height, x$device$units))
  cat(sprintf("  %d plot(s), %d element(s), %d transform(s)\n",
              length(plots), length(x$registry), length(x$transforms)))
  if (!is.null(x$active)) {
    cat(sprintf("  active selection: %s (%d element(s))\n",
                x$active$spec$type, length(x$active$ids)))
  }
  invisible(x)
}
