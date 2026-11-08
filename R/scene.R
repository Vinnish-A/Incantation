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
#' @param device Measurement device: "cairo_pdf" (default), "pdf", "svglite"
#'   or "ragg". Use the device matching the intended final format for exact text metrics.
#' @param family Default font family on the bound device. Plot font settings take precedence.
#' @param res Raster resolution for a ragg measurement device, in pixels per inch.
#' @param plot_ids Optional unique semantic identities in subplot order, retained
#'   in edit manifests to detect replay against reordered or replaced plots.
#' @return An `inc_scene`.
#' @export
incant = function(x, width = NULL, height = NULL, units = "in",
                  device = c("cairo_pdf", "pdf", "svglite", "ragg"),
                  family = "sans", res = 300, plot_ids = NULL) {
  if (is.null(width) || is.null(height)) err_no_device()
  renderer = list(type = match.arg(device), family = family, res = res)
  device = list(width = width, height = height, units = units)

  # Everything happens inside the bound offscreen device: building the gtable needs a
  # device for text metrics (otherwise ggplot2/patchwork open Rplots.pdf), and
  # measuring each part's base rectangle needs the same one. Downstream
  # bbox()/gap() are then pure arithmetic over these + the transform log.
  built = with_scene_device(device, function() {
    cap = inc_capture(x)
    elements = build_elements(cap$root, cap$backend, cap$index_map)
    elements = lapply(elements, function(el) {
      measure_part = function(p) {
        p$base = tryCatch(rect_from_frames(p$frames),
                          error = function(e) c(left = NA, bottom = NA, right = NA, top = NA))
        p
      }
      el$parts = lapply(el$parts, measure_part)
      if (!is.null(el$anchor_parts)) el$anchor_parts = lapply(el$anchor_parts, measure_part)
      el
    })
    list(cap = cap, elements = elements)
  }, renderer = renderer)
  cap = built$cap
  registry = stats::setNames(built$elements, vapply(built$elements, `[[`, character(1), "id"))

  scene = structure(
    list(
      base = cap$root,
      backend = cap$backend,
      source = cap$source,
      capabilities = list(
        decoration_outer = if (identical(cap$backend, "cowplot")) {
          "plot-viewport"
        } else {
          "layout-cells"
        }
      ),
      device = device,
      renderer = renderer,
      registry = registry,
      transforms = list(),
      decorations = list(),
      active = NULL
    ),
    class = "inc_scene"
  )
  plots = Filter(function(e) identical(e$role, "plot"), registry)
  if (!is.null(plot_ids) && (length(plot_ids) != length(plots) ||
      anyNA(plot_ids) || any(!nzchar(plot_ids)) || anyDuplicated(plot_ids))) {
    inc_abort("`plot_ids` must give one unique, non-empty identity per subplot.",
              class = "inc_error_plot_identity")
  }
  scene$plot_identities = stats::setNames(lapply(seq_along(plots), function(i) {
    el = plots[[i]]
    if (!is.null(plot_ids)) return(list(id = as.character(plot_ids[[i]])))
    roles = c("title", "subtitle", "xlab-b", "ylab-l")
    labels = lapply(roles, function(role) {
      atomic = registry[[paste0(el$id, "/", role)]]
      if (is.null(atomic)) return(NULL)
      .grob_text(grob_at(scene$base, atomic$parts[[1]]$grob_path))
    })
    list(roles = sort(unique(vapply(el$parts, `[[`, character(1), "role"))),
         labels = stats::setNames(labels, roles))
  }), vapply(plots, `[[`, character(1), "id"))
  scene
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
    if (any(vapply(moved, function(path) {
      length(path) <= length(grob_path) &&
        identical(path, grob_path[seq_along(path)])
    }, logical(1)))) {
      dx = dx + tr$dx; dy = dy + tr$dy
    }
  }
  list(dx = dx, dy = dy)
}

.moved_paths = function(scene, tr) {
  el = scene$registry[[tr$target]]
  if (is.null(el)) err_no_match(sprintf("id `%s`", tr$target), names(scene$registry))
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
