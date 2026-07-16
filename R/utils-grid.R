# Device + geometry helpers. Everything here is deterministic and offline: no
# on-screen device is ever opened. We measure on a null pdf() device whose size
# is the scene's bound device size, because element geometry is only resolvable
# once a device of a known size exists (REVIEW s2.1, Phase 0).

.units_to_inches = function(x, units) {
  switch(units,
    "in" = x, "inches" = x,
    "cm" = x / 2.54,
    "mm" = x / 25.4,
    "pt" = x / 72,
    stop("unsupported device unit: ", units, call. = FALSE)
  )
}

.to_pt = function(x, unit) {
  if (grid::is.unit(x)) return(grid::convertUnit(x, "pt", valueOnly = TRUE))
  switch(unit,
    "pt" = x,
    "mm" = x * 72 / 25.4,
    "cm" = x * 72 / 2.54,
    "in" = x * 72, "inches" = x * 72,
    stop("unsupported unit: ", unit, call. = FALSE)
  )
}

# Open a null device of the scene size, run `fun()`, always close. Returns the
# value of fun(). Callers do all their grid measurement inside `fun`.
with_scene_device = function(device, fun) {
  win = .units_to_inches(device$width, device$units)
  hin = .units_to_inches(device$height, device$units)
  grDevices::pdf(NULL, width = win, height = hin)
  on.exit(grDevices::dev.off(), add = TRUE)
  grid::grid.newpage()
  fun()
}

# A "frame" is one push onto the viewport stack. Two shapes:
#   * a gtable cell:  list(widths=, heights=, t=, l=, b=, r=)
#   * a raw viewport: list(vp = <viewport>)   [cowplot child placement]
# Pushing the whole frame list leaves the target's own viewport current; we then
# read its device rectangle. deviceLoc() returns inches on a pdf device, so x72.
rect_from_frames = function(frames) {
  pushed = 0L
  # Always unwind exactly what we pushed, even if a bad frame errors mid-way, so
  # one un-measurable element cannot corrupt the stack for the whole registry.
  on.exit(if (pushed > 0) grid::popViewport(pushed), add = TRUE)
  for (fr in frames) {
    if (!is.null(fr$vp)) {
      grid::pushViewport(fr$vp)
      pushed = pushed + 1L
    } else {
      grid::pushViewport(grid::viewport(layout = grid::grid.layout(
        length(fr$heights), length(fr$widths),
        widths = fr$widths, heights = fr$heights
      )))
      grid::pushViewport(grid::viewport(
        layout.pos.row = fr$t:fr$b, layout.pos.col = fr$l:fr$r
      ))
      pushed = pushed + 2L
    }
  }
  bl = grid::deviceLoc(grid::unit(0, "npc"), grid::unit(0, "npc"), valueOnly = TRUE)
  tr = grid::deviceLoc(grid::unit(1, "npc"), grid::unit(1, "npc"), valueOnly = TRUE)
  c(left = bl$x * 72, bottom = bl$y * 72, right = tr$x * 72, top = tr$y * 72)
}

# Union of several rectangles (for a plot whose panel is split across facets).
rect_union = function(rects) {
  ok = Filter(function(r) !any(is.na(r)), rects)
  if (length(ok) == 0) return(c(left = NA, bottom = NA, right = NA, top = NA))
  c(left = min(vapply(ok, `[[`, numeric(1), "left")),
    bottom = min(vapply(ok, `[[`, numeric(1), "bottom")),
    right = max(vapply(ok, `[[`, numeric(1), "right")),
    top = max(vapply(ok, `[[`, numeric(1), "top")))
}

# Fetch / replace a grob reached by an integer path. gtable levels index $grobs;
# gTree levels (cowplot's single panel) index $children. We detect which by
# class at each hop, so one walker serves patchwork, nested patchwork and cowplot.
grob_at = function(x, path) {
  if (length(path) == 0) return(x)
  child = if (inherits(x, "gtable")) x$grobs[[path[1]]] else x$children[[path[1]]]
  grob_at(child, path[-1])
}

modify_grob_at = function(x, path, f) {
  if (length(path) == 1) {
    if (inherits(x, "gtable")) x$grobs[[path]] = f(x$grobs[[path]])
    else x$children[[path]] = f(x$children[[path]])
    return(x)
  }
  i = path[1]
  if (inherits(x, "gtable")) {
    x$grobs[[i]] = modify_grob_at(x$grobs[[i]], path[-1], f)
  } else {
    x$children[[i]] = modify_grob_at(x$children[[i]], path[-1], f)
  }
  x
}

# Turn off clipping at every gtable level along a path, so a moved grob can cross
# the boundary of its own cell AND of any nested table it lives in (REVIEW s1.5:
# the one real clip chain is inside nested patchwork).
unclip_along = function(x, path) {
  if (length(path) >= 1 && inherits(x, "gtable")) {
    x$layout$clip[path[1]] = "off"
  }
  if (length(path) > 1) {
    i = path[1]
    if (inherits(x, "gtable")) x$grobs[[i]] = unclip_along(x$grobs[[i]], path[-1])
    else x$children[[i]] = unclip_along(x$children[[i]], path[-1])
  }
  x
}

# The one visual transform. Wrap g in a translated viewport; composing wraps adds
# offsets, which is exactly additive translation. clip defaults off because the
# whole point is to cross the original cell boundary (REVIEW s7.3).
wrap_translate = function(g, dx_pt, dy_pt, clip = "off") {
  grid::grobTree(
    g,
    vp = grid::viewport(
      x = grid::unit(0.5, "npc") + grid::unit(dx_pt, "pt"),
      y = grid::unit(0.5, "npc") + grid::unit(dy_pt, "pt"),
      width = grid::unit(1, "npc"),
      height = grid::unit(1, "npc"),
      clip = clip
    ),
    name = "incant-translated"
  )
}

# Is this grob effectively nothing to draw? Recurse, because ggplot renders a
# blank axis/title as a non-empty absoluteGrob whose leaves are all zeroGrobs
# (that is what makes plot-3/axis-l an "empty target" in the cluster subplot).
is_blank_grob = function(g) {
  if (is.null(g)) return(TRUE)
  if (inherits(g, "zeroGrob")) return(TRUE)
  kids = if (inherits(g, "gtable")) g$grobs else g$children
  if (is.null(kids) || length(kids) == 0) return(FALSE)  # a real leaf: rect/text/points
  all(vapply(kids, is_blank_grob, logical(1)))
}

# Rectangles overlap? Return signed overlap on each axis (positive = overlapping).
rect_overlap = function(a, b) {
  ox = min(a["right"], b["right"]) - max(a["left"], b["left"])
  oy = min(a["top"], b["top"]) - max(a["bottom"], b["bottom"])
  c(x = unname(ox), y = unname(oy))
}
