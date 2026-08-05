# Replay the transform log onto a fresh copy of the base gtable. Because we only
# wrap grobs and flip clip/z, the layout tracks (widths/heights/t/l/b/r) are
# never touched -- the Frozen Layout invariant (REVIEW s3.1) holds by construction.

#' The edited figure as a gtable
#' @param scene An `inc_scene`.
#' @export
as_gtable = function(scene) {
  gt = scene$base
  for (tr in .resolved_transforms(scene)) {
    if (identical(tr$type, "decorate_group")) {
      next
    } else if (identical(tr$type, "translate")) {
      el = scene$registry[[tr$target]]
      if (.is_decoration_element(el)) next
      parts = el$parts
      if (!isTRUE(tr$include_background)) {
        parts = parts[!vapply(parts, `[[`, logical(1), "is_background")]
      }
      for (p in parts) {
        gt = modify_grob_at(gt, p$grob_path, function(g) wrap_translate(g, tr$dx, tr$dy, tr$clip))
        gt = unclip_along(gt, p$grob_path)
      }
    } else if (identical(tr$type, "z")) {
      el = scene$registry[[tr$target]]
      if (.is_decoration_element(el)) next
      for (p in el$parts) {
        if (length(p$grob_path) != 1) next          # top-level restack only
        row = p$grob_path
        gt$layout$z[row] = if (identical(tr$z, "front")) max(gt$layout$z) + 1L else min(gt$layout$z) - 1L
      }
    }
  }
  for (op in scene$decorations) {
    for (item in .decoration_grobs(scene, op)) {
      gt = gtable::gtable_add_grob(
        gt, item$grob, t = 1, l = 1, b = nrow(gt), r = ncol(gt),
        z = item$z, name = item$name, clip = "off"
      )
    }
  }
  gt
}

#' Render the edited figure (optionally with debug boxes) as a drawable gtable
#' @param scene An `inc_scene`.
#' @param debug Draw element bounding boxes and ids for inspection?
#' @export
render = function(scene, debug = FALSE) {
  gt = as_gtable(scene)
  if (!isTRUE(debug)) return(gt)
  reg = inspect(scene)
  reg = reg[!reg$is_empty & reg$role == "plot", , drop = FALSE]
  cv = .canvas_pt(scene)
  overlay = grid::gTree(children = do.call(grid::gList, lapply(seq_len(nrow(reg)), function(i) {
    grid::rectGrob(
      x = grid::unit(reg$left[i], "pt"), y = grid::unit(reg$bottom[i], "pt"),
      width = grid::unit(reg$right[i] - reg$left[i], "pt"),
      height = grid::unit(reg$top[i] - reg$bottom[i], "pt"),
      just = c("left", "bottom"),
      gp = grid::gpar(col = "red", fill = NA, lwd = 0.5)
    )
  })))
  gtable::gtable_add_grob(gt, overlay, t = 1, l = 1, b = nrow(gt), r = ncol(gt),
                          z = Inf, name = "incant-debug", clip = "off")
}

#' Draw the edited figure on the current device
#' @param scene An `inc_scene`.
#' @export
draw = function(scene) {
  grid::grid.newpage()
  grid::grid.draw(as_gtable(scene))
  invisible(scene)
}

#' Save the edited figure, refusing a device size other than the scene's
#'
#' A pt offset chosen at the scene's device size overshoots at another, so saving
#' at a different size is refused rather than silently honoured (REVIEW s2.1).
#' @param scene An `inc_scene`.
#' @param filename Output path (.png, .pdf or .svg).
#' @param width,height,units Optional; must match the scene if given.
#' @param res PNG resolution.
#' @export
ggsave_incant = function(scene, filename, width = NULL, height = NULL,
                         units = NULL, res = 300) {
  dev = scene$device
  if (!is.null(width) || !is.null(height) || !is.null(units)) {
    rd = list(width = width %||% dev$width, height = height %||% dev$height,
              units = units %||% dev$units)
    same = isTRUE(all.equal(.to_pt(rd$width, rd$units), .to_pt(dev$width, dev$units))) &&
      isTRUE(all.equal(.to_pt(rd$height, rd$units), .to_pt(dev$height, dev$units)))
    if (!same) err_device_mismatch(dev, rd)
  }
  win = .units_to_inches(dev$width, dev$units)
  hin = .units_to_inches(dev$height, dev$units)
  ext = tolower(tools::file_ext(filename))
  switch(ext,
    png = grDevices::png(filename, width = win, height = hin, units = "in", res = res),
    pdf = grDevices::pdf(filename, width = win, height = hin),
    svg = svglite::svglite(filename, width = win, height = hin),
    inc_abort(sprintf("unsupported output extension: .%s", ext), class = "inc_error_bad_ext")
  )
  on.exit(grDevices::dev.off(), add = TRUE)
  grid::grid.newpage()
  grid::grid.draw(as_gtable(scene))
  invisible(filename)
}
