# Capture: turn a user object into a laid-out gtable + a backend tag + (for
# aplot) an index map. This is the ONLY backend-aware layer; everything
# downstream reads the registry (REVIEW s4.1: the transform is uniform, only
# locating differs).

# Building the gtable re-runs exactly the layout the user already rendered, so
# geom/axis warnings here are redundant echoes (aplot's shared-axis alignment in
# particular warns on empty ranges). Muffle them at this boundary only.
.lay_out = function(expr) suppressWarnings(expr)

inc_capture = function(x) {
  if (inherits(x, "aplot")) return(capture_aplot(x))
  if (inherits(x, "patchwork")) {
    if (!requireNamespace("patchwork", quietly = TRUE)) {
      inc_abort("patchwork support needs the 'patchwork' package.", class = "inc_error_missing_pkg")
    }
    return(list(root = .lay_out(patchwork::patchworkGrob(x)), backend = "patchwork", index_map = NULL))
  }
  if (inherits(x, "ggplot")) {
    root = .lay_out(ggplot2::ggplotGrob(x))
    backend = if (.looks_like_cowplot(root)) "cowplot" else "ggplot"
    return(list(root = root, backend = backend, index_map = NULL))
  }
  if (inherits(x, "gtable")) {
    return(list(root = x, backend = "patchwork", index_map = NULL))
  }
  inc_abort("`x` must be a ggplot, patchwork, aplot, cowplot or gtable.",
            class = "inc_error_unsupported_input")
}

# cowplot::plot_grid() returns a ggplot, so we detect it structurally: a single
# panel whose children are GeomDrawGrobs (REVIEW s4.2).
.looks_like_cowplot = function(root) {
  pr = which(root$layout$name == "panel")
  if (length(pr) != 1) return(FALSE)
  panel = root$grobs[[pr]]
  !is.null(panel$children) && any(grepl("GeomDrawGrob", names(panel$children)))
}

# aplot renders to a patchwork-style flat gtable, but its plot indices are NOT
# the cell suffixes (REVIEW s1.2). Recover the map from $layout by matching each
# panel cell's (t, l) position back to the layout matrix.
capture_aplot = function(x) {
  if (!requireNamespace("ggplotify", quietly = TRUE)) {
    inc_abort("aplot support needs the 'ggplotify' package.", class = "inc_error_missing_pkg")
  }
  root = .lay_out(ggplotify::as.grob(x))
  layout_matrix = x$layout

  index_map = function(gt, suffix) {
    cells = gt$layout[grepl("^panel-[0-9]+$", gt$layout$name), , drop = FALSE]
    rows = sort(unique(cells$t))
    cols = sort(unique(cells$l))
    this = cells[cells$name == paste0("panel-", suffix), , drop = FALSE]
    if (nrow(this) == 0) return(NA_integer_)
    r = match(this$t, rows)
    c = match(this$l, cols)
    val = layout_matrix[r, c]
    if (is.na(val)) NA_integer_ else as.integer(val)
  }
  list(root = root, backend = "aplot", index_map = index_map)
}
