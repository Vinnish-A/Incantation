# Group decorations are semantic overlays. Their placement is resolved from the
# final transformed plot geometry, while component nudges remain ordinary scene
# translations against stable synthetic ids.

.decoration_path = function(id, component) paste0("@", id, "/", component)

.is_decoration_element = function(el) identical(el$kind, "decoration")

.decoration_pair = function(x, labels, unit, nonnegative = FALSE) {
  x = as.numeric(unlist(x, use.names = FALSE))
  if (length(x) == 1) x = rep(x, 2)
  if (length(x) != 2 || any(!is.finite(x))) {
    inc_abort(sprintf("`%s` must contain one or two finite numbers.", labels[[1]]),
              class = "inc_error_bad_decoration")
  }
  x = .to_pt(x, unit)
  if (nonnegative && any(x < 0)) {
    inc_abort(sprintf("`%s` cannot be negative.", labels[[1]]),
              class = "inc_error_bad_decoration")
  }
  stats::setNames(x, labels)
}

.decoration_targets = function(scene, plots) {
  ids = if (is.numeric(plots)) paste0("plot-", as.integer(plots)) else as.character(plots)
  ids = unique(ids)
  if (!length(ids) || anyNA(ids) || any(!nzchar(ids))) {
    inc_abort("`plots` must identify at least one subplot.", class = "inc_error_bad_decoration")
  }
  for (id in ids) {
    el = scene$registry[[id]]
    if (is.null(el)) err_no_match(sprintf("decoration plot `%s`", id), names(scene$registry))
    if (!identical(el$role, "plot")) {
      inc_abort(sprintf("decoration target `%s` is not a plot.", id),
                class = "inc_error_bad_decoration")
    }
    if (isTRUE(el$is_empty)) err_empty_target(id)
  }
  ids
}

.next_decoration_id = function(scene) {
  i = length(scene$decorations) + 1L
  id = paste0("decoration-", i)
  while (id %in% names(scene$registry)) {
    i = i + 1L
    id = paste0("decoration-", i)
  }
  id
}

.decoration_part = function(id, component, z) {
  list(
    role = paste0("decoration-", component),
    grob_path = .decoration_path(id, component),
    frames = list(),
    is_background = FALSE,
    is_blank = FALSE,
    z = z,
    decoration_id = id,
    component = component
  )
}

.decoration_element = function(id, role, parts, anchor, component = "group") {
  list(
    id = id,
    role = role,
    plot_index = NA_integer_,
    parts = parts,
    anchor = anchor,
    container = "overlay",
    is_empty = FALSE,
    kind = "decoration",
    decoration_id = sub("/(line|title)$", "", id),
    component = component
  )
}

.register_decoration = function(scene, op) {
  ordinal = length(scene$decorations) + 1L
  line = .decoration_part(op$id, "line", 1e5 + ordinal * 10)
  parts = list(line)
  if (!is.null(op$title)) {
    parts = c(parts, list(.decoration_part(op$id, "title", 1e5 + ordinal * 10 + 1)))
  }

  elements = list(
    .decoration_element(op$id, "decoration", parts, seq_along(parts)),
    .decoration_element(paste0(op$id, "/line"), "decoration-line", list(parts[[1]]), 1L, "line")
  )
  if (!is.null(op$title)) {
    elements = c(elements, list(
      .decoration_element(paste0(op$id, "/title"), "decoration-title", list(parts[[2]]), 1L, "title")
    ))
  }
  ids = vapply(elements, `[[`, character(1), "id")
  scene$registry[ids] = stats::setNames(elements, ids)
  scene
}

.scalar_value = function(x, mode = "character") {
  value = unlist(x, use.names = FALSE)
  if (!length(value)) return(NULL)
  switch(mode,
    character = as.character(value[[1]]),
    numeric = as.numeric(value[[1]]),
    logical = as.logical(value[[1]])
  )
}

.normalize_decoration_op = function(op) {
  op$id = .scalar_value(op$id)
  op$targets = as.character(unlist(op$targets, use.names = FALSE))
  op$side = .scalar_value(op$side)
  op$reference = .scalar_value(op$reference)
  op$span$type = .scalar_value(op$span$type)
  if (identical(op$span$type, "absolute")) {
    op$span$start = .scalar_value(op$span$start, "numeric")
    op$span$end = .scalar_value(op$span$end, "numeric")
  }
  op$trim$start = .scalar_value(op$trim$start, "numeric")
  op$trim$end = .scalar_value(op$trim$end, "numeric")
  op$gap = .scalar_value(op$gap, "numeric")
  op$title = if (is.null(op$title)) NULL else .scalar_value(op$title)
  op$title_gap = .scalar_value(op$title_gap, "numeric")
  op$align = .scalar_value(op$align)
  op$nudge$along = .scalar_value(op$nudge$along, "numeric")
  op$nudge$outward = .scalar_value(op$nudge$outward, "numeric")
  op$title_nudge$along = .scalar_value(op$title_nudge$along, "numeric")
  op$title_nudge$outward = .scalar_value(op$title_nudge$outward, "numeric")
  op$title_angle = .scalar_value(op$title_angle, "numeric")
  op$style$line_colour = .scalar_value(op$style$line_colour)
  op$style$line_width = .scalar_value(op$style$line_width, "numeric")
  op$style$line_linetype = .scalar_value(op$style$line_linetype)
  op$style$title_colour = .scalar_value(op$style$title_colour)
  op$style$title_size = .scalar_value(op$style$title_size, "numeric")
  op$style$title_face = .scalar_value(op$style$title_face)
  op$style$title_family = .scalar_value(op$style$title_family)
  op
}

.validate_decoration_op = function(scene, op) {
  required = c("id", "targets", "side", "reference", "span", "trim", "gap",
               "title_gap", "align", "nudge", "title_nudge", "title_angle", "style")
  missing = setdiff(required, names(op))
  if (length(missing)) {
    inc_abort(sprintf("decoration operation is missing `%s`.", missing[[1]]),
              class = "inc_error_manifest_operation")
  }
  op = .normalize_decoration_op(op)
  if (is.null(op$id) || !nzchar(op$id) || grepl("/", op$id, fixed = TRUE)) {
    inc_abort("decoration `id` must be one non-empty string without `/`.",
              class = "inc_error_bad_decoration")
  }
  collision = c(op$id, paste0(op$id, "/line"), paste0(op$id, "/title"))
  if (any(collision %in% names(scene$registry))) {
    inc_abort(sprintf("decoration id `%s` already exists.", op$id),
              class = "inc_error_duplicate_id")
  }
  op$targets = .decoration_targets(scene, op$targets)
  if (!op$side %in% c("top", "bottom", "left", "right")) {
    inc_abort("decoration `side` must be top, bottom, left or right.",
              class = "inc_error_bad_decoration")
  }
  if (!op$reference %in% c("layout_outer", "panel")) {
    inc_abort("decoration `reference` must be layout_outer or panel.",
              class = "inc_error_bad_decoration")
  }
  if (!op$span$type %in% c("panel", "absolute")) {
    inc_abort("decoration span must be panel-relative or absolute.",
              class = "inc_error_bad_decoration")
  }
  numbers = c(op$trim$start, op$trim$end, op$gap, op$title_gap,
              op$nudge$along, op$nudge$outward,
              op$title_nudge$along, op$title_nudge$outward,
              op$title_angle, op$style$line_width, op$style$title_size)
  if (any(!is.finite(numbers)) || any(c(op$trim$start, op$trim$end) < 0) ||
      op$style$line_width <= 0 || op$style$title_size <= 0) {
    inc_abort("decoration numeric parameters are invalid.", class = "inc_error_bad_decoration")
  }
  if (!op$align %in% c("start", "center", "end")) {
    inc_abort("decoration `align` must be start, center or end.",
              class = "inc_error_bad_decoration")
  }
  if (identical(op$span$type, "absolute")) {
    endpoints = c(op$span$start, op$span$end)
    if (length(endpoints) != 2 || any(!is.finite(endpoints))) {
      inc_abort("absolute decoration span needs two finite coordinates.",
                class = "inc_error_bad_decoration")
    }
  }
  op
}

.add_decoration = function(scene, op, activate) {
  op = .validate_decoration_op(scene, op)
  scene = .register_decoration(scene, op)
  scene$decorations[[op$id]] = op
  invisible(.decoration_geometry(scene, op))
  scene$transforms = c(scene$transforms, list(op))
  if (activate) {
    scene$active = list(target = op$id, ids = op$id,
                        spec = list(type = "decoration", id = op$id, part = "group"))
  }
  scene
}

#' Add a line and title around a group of plots
#'
#' The default span follows the union of target panel edges. Placement follows
#' the outermost non-empty layout cell on `side`; hidden axes therefore retain a
#' virtual anchor at the corresponding panel edge. For cowplot, whose subplots
#' are viewport children rather than separate layout cells, `layout_outer`
#' resolves to each target plot viewport. The original layout and canvas remain
#' fixed.
#'
#' @param scene An `inc_scene` captured from a ggplot, patchwork, aplot, cowplot
#'   or gtable.
#' @param plots Plot indices or stable `plot-k` ids.
#' @param title Optional group title. `NULL` draws only the line.
#' @param side One of "top", "bottom", "left" or "right".
#' @param id Stable decoration id. Generated when omitted.
#' @param span "panel" for semantic panel anchors, or two absolute device
#'   coordinates in `unit`. Horizontal sides use x; vertical sides use y from top
#'   to bottom. Absolute spans are device-bound.
#' @param reference "layout_outer" or "panel".
#' @param gap Distance from the reference frontier to the line.
#' @param title_gap Distance from the line to the nearest title edge.
#' @param trim One value for equal trimming or start/end values.
#' @param align Title alignment along the trimmed line.
#' @param nudge,title_nudge Along/outward initial offsets.
#' @param unit Physical unit for positions: pt, mm, cm or in.
#' @param line_colour,line_width,line_linetype Line appearance.
#' @param title_colour,title_size,title_face,title_family,title_angle Title appearance.
#' @return The scene with the decoration selected.
#' @export
decorate_group = function(scene, plots, title = NULL, side = "top", id = NULL,
                           span = "panel", reference = "layout_outer",
                           gap = 4, title_gap = 5, trim = 0,
                           align = "center", nudge = c(0, 0),
                           title_nudge = c(0, 0), unit = "pt",
                           line_colour = "black", line_width = 1,
                           line_linetype = "solid", title_colour = "black",
                           title_size = 14, title_face = "plain",
                           title_family = "", title_angle = NULL) {
  side = match.arg(side, c("top", "bottom", "left", "right"))
  reference = match.arg(reference, c("layout_outer", "panel"))
  align = match.arg(align, c("start", "center", "end"))
  targets = .decoration_targets(scene, plots)
  id = id %||% .next_decoration_id(scene)
  if (!is.null(title)) {
    title = as.character(title)
    if (length(title) != 1 || is.na(title) || !nzchar(title)) {
      inc_abort("decoration `title` must be one non-empty string or NULL.",
                class = "inc_error_bad_decoration")
    }
  }
  trim = .decoration_pair(trim, c("start", "end"), unit, nonnegative = TRUE)
  nudge = .decoration_pair(nudge, c("along", "outward"), unit)
  title_nudge = .decoration_pair(title_nudge, c("along", "outward"), unit)
  gap = .to_pt(gap, unit)
  title_gap = .to_pt(title_gap, unit)
  if (length(gap) != 1 || length(title_gap) != 1 || any(!is.finite(c(gap, title_gap)))) {
    inc_abort("decoration gaps must be finite scalar values.", class = "inc_error_bad_decoration")
  }
  span_spec = if (is.character(span) && length(span) == 1 && identical(span, "panel")) {
    list(type = "panel")
  } else if (is.numeric(span) && length(span) == 2 && all(is.finite(span))) {
    span_pt = .to_pt(span, unit)
    list(type = "absolute", start = span_pt[[1]], end = span_pt[[2]])
  } else {
    inc_abort("`span` must be \"panel\" or two finite coordinates.",
              class = "inc_error_bad_decoration")
  }
  title_angle = title_angle %||% switch(side, left = 90, right = -90, 0)
  op = list(
    type = "decorate_group", id = as.character(id), targets = targets,
    side = side, reference = reference, span = span_spec,
    trim = as.list(trim), gap = gap, title = title, title_gap = title_gap,
    align = align, nudge = as.list(nudge), title_nudge = as.list(title_nudge),
    title_angle = as.numeric(title_angle),
    style = list(line_colour = as.character(line_colour),
                 line_width = as.numeric(line_width),
                 line_linetype = as.character(line_linetype),
                 title_colour = as.character(title_colour),
                 title_size = as.numeric(title_size),
                 title_face = as.character(title_face),
                 title_family = as.character(title_family))
  )
  .add_decoration(scene, op, activate = TRUE)
}

.decoration_basis = function(side) {
  switch(side,
    top = list(along = c(x = 1, y = 0), outward = c(x = 0, y = 1)),
    bottom = list(along = c(x = 1, y = 0), outward = c(x = 0, y = -1)),
    left = list(along = c(x = 0, y = -1), outward = c(x = -1, y = 0)),
    right = list(along = c(x = 0, y = -1), outward = c(x = 1, y = 0))
  )
}

.project_rect = function(rect, direction) {
  points = rbind(
    c(x = rect[["left"]], y = rect[["bottom"]]),
    c(x = rect[["left"]], y = rect[["top"]]),
    c(x = rect[["right"]], y = rect[["bottom"]]),
    c(x = rect[["right"]], y = rect[["top"]])
  )
  range(drop(points %*% direction))
}

.decoration_point = function(along, outward, basis) {
  basis$along * along + basis$outward * outward
}

.decoration_text_gp = function(op) {
  grid::gpar(col = op$style$title_colour, fontsize = op$style$title_size,
             fontface = op$style$title_face, fontfamily = op$style$title_family)
}

.decoration_text_size = function(scene, op) {
  if (is.null(op$title)) return(c(width = 0, height = 0))
  with_scene_device(scene$device, function() {
    grob = grid::textGrob(op$title, rot = op$title_angle,
                          gp = .decoration_text_gp(op))
    c(width = grid::convertWidth(grid::grobWidth(grob), "pt", valueOnly = TRUE),
      height = grid::convertHeight(grid::grobHeight(grob), "pt", valueOnly = TRUE))
  })
}

.decoration_geometry = function(scene, op) {
  op = .normalize_decoration_op(op)
  plots = lapply(op$targets, function(id) scene$registry[[id]])
  panels = lapply(plots, function(el) .anchor_rect(scene, el))
  visible = unlist(lapply(plots, function(el) {
    parts = Filter(function(part) !isTRUE(part$is_background) && !isTRUE(part$is_blank), el$parts)
    lapply(parts, function(part) .part_rect(scene, part))
  }), recursive = FALSE)
  if (!length(visible) || identical(op$reference, "panel")) visible = panels

  basis = .decoration_basis(op$side)
  panel_along = lapply(panels, .project_rect, direction = basis$along)
  outer = lapply(visible, .project_rect, direction = basis$outward)
  u0 = min(vapply(panel_along, `[[`, numeric(1), 1))
  u1 = max(vapply(panel_along, `[[`, numeric(1), 2))
  if (identical(op$span$type, "absolute")) {
    if (op$side %in% c("top", "bottom")) {
      u0 = op$span$start
      u1 = op$span$end
    } else {
      u0 = -op$span$start
      u1 = -op$span$end
    }
  }
  u_start = u0 + op$trim$start + op$nudge$along
  u_end = u1 - op$trim$end + op$nudge$along
  if (!is.finite(u_start) || !is.finite(u_end) || u_start >= u_end) {
    inc_abort("decoration trim leaves no positive line span.", class = "inc_error_bad_decoration")
  }
  v_outer = max(vapply(outer, `[[`, numeric(1), 2))
  v_line = v_outer + op$gap + op$nudge$outward
  start = .decoration_point(u_start, v_line, basis)
  end = .decoration_point(u_end, v_line, basis)
  line_shift = .net_shift(scene, .decoration_path(op$id, "line"))
  start = start + c(x = line_shift$dx, y = line_shift$dy)
  end = end + c(x = line_shift$dx, y = line_shift$dy)
  pad = op$style$line_width / 2
  line_rect = c(left = min(start[["x"]], end[["x"]]) - pad,
                bottom = min(start[["y"]], end[["y"]]) - pad,
                right = max(start[["x"]], end[["x"]]) + pad,
                top = max(start[["y"]], end[["y"]]) + pad)

  title = NULL
  title_rect = NULL
  if (!is.null(op$title)) {
    size = .decoration_text_size(scene, op)
    along_size = if (op$side %in% c("top", "bottom")) size[["width"]] else size[["height"]]
    normal_size = if (op$side %in% c("top", "bottom")) size[["height"]] else size[["width"]]
    u_title = switch(op$align,
      start = u_start + along_size / 2,
      center = (u_start + u_end) / 2,
      end = u_end - along_size / 2
    ) + op$title_nudge$along
    v_title = v_line + op$title_gap + normal_size / 2 + op$title_nudge$outward
    center = .decoration_point(u_title, v_title, basis)
    title_shift = .net_shift(scene, .decoration_path(op$id, "title"))
    center = center + c(x = title_shift$dx, y = title_shift$dy)
    title = c(x = center[["x"]], y = center[["y"]],
              width = size[["width"]], height = size[["height"]])
    title_rect = c(left = title[["x"]] - title[["width"]] / 2,
                   bottom = title[["y"]] - title[["height"]] / 2,
                   right = title[["x"]] + title[["width"]] / 2,
                   top = title[["y"]] + title[["height"]] / 2)
  }
  boxes = if (is.null(title_rect)) list(line_rect) else list(line_rect, title_rect)
  list(
    line = c(x0 = start[["x"]], y0 = start[["y"]],
             x1 = end[["x"]], y1 = end[["y"]]),
    line_rect = line_rect,
    title = title,
    title_rect = title_rect,
    group_rect = rect_union(boxes),
    outer = v_outer,
    along = c(start = u_start, end = u_end),
    basis = basis
  )
}

.decoration_component_rect = function(scene, id, component) {
  geometry = .decoration_geometry(scene, scene$decorations[[id]])
  switch(component,
    group = geometry$group_rect,
    line = geometry$line_rect,
    title = geometry$title_rect
  )
}

.decoration_component_z = function(scene, id, component, z) {
  targets = c(id, paste0(id, "/", component))
  for (op in scene$transforms) {
    if (identical(op$type, "z") && op$target %in% targets) {
      z = z + if (identical(op$z, "front")) 1e6 else -1e6
    }
  }
  z
}

.decoration_grobs = function(scene, op) {
  geometry = .decoration_geometry(scene, op)
  ordinal = match(op$id, names(scene$decorations))
  line = grid::segmentsGrob(
    x0 = grid::unit(geometry$line[["x0"]], "pt"),
    y0 = grid::unit(geometry$line[["y0"]], "pt"),
    x1 = grid::unit(geometry$line[["x1"]], "pt"),
    y1 = grid::unit(geometry$line[["y1"]], "pt"),
    gp = grid::gpar(col = op$style$line_colour, lwd = op$style$line_width,
                    lty = op$style$line_linetype, lineend = "butt"),
    name = paste0("incant-", op$id, "-line")
  )
  out = list(list(grob = line,
                  z = .decoration_component_z(scene, op$id, "line", 1e5 + ordinal * 10),
                  name = paste0("incant-", op$id, "-line")))
  if (!is.null(op$title)) {
    title = grid::textGrob(
      op$title,
      x = grid::unit(geometry$title[["x"]], "pt"),
      y = grid::unit(geometry$title[["y"]], "pt"),
      just = "centre", rot = op$title_angle,
      gp = .decoration_text_gp(op),
      name = paste0("incant-", op$id, "-title")
    )
    out = c(out, list(list(
      grob = title,
      z = .decoration_component_z(scene, op$id, "title", 1e5 + ordinal * 10 + 1),
      name = paste0("incant-", op$id, "-title")
    )))
  }
  out
}
