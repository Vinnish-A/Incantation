.require_svg_active = function(x, fn) {
  if (!length(x$active)) err_no_selection(fn)
  x$active
}

.push_svg = function(x, op) {
  x$operations = c(x$operations, list(op))
  x
}

#' Move selected SVG primitives
#'
#' Positive `dy` moves up, matching the grid-facing API even though SVG's raw y
#' coordinate grows downward.
#' @param x An `inc_svg` with an active selection.
#' @param dx,dy Offsets.
#' @param unit One of "pt", "mm", "cm", "in".
#' @export
svg_translate = function(x, dx = 0, dy = 0, unit = "pt") {
  targets = .require_svg_active(x, "svg_translate")
  .push_svg(x, list(type = "translate", targets = targets,
                    dx = .to_pt(dx, unit), dy = .to_pt(dy, unit)))
}

.svg_selection_center = function(x) {
  man = svg_manifest(x)
  hit = man[man$id %in% .require_svg_active(x, "SVG transform"), , drop = FALSE]
  c(x = mean(range(c(hit$left, hit$right), na.rm = TRUE)),
    y = mean(range(c(hit$bottom, hit$top), na.rm = TRUE)))
}

#' Scale selected SVG primitives around their collective centre
#' @param x An `inc_svg` with an active selection.
#' @param sx,sy Horizontal and vertical scale factors.
#' @export
svg_scale = function(x, sx = 1, sy = sx) {
  targets = .require_svg_active(x, "svg_scale")
  origin = .svg_selection_center(x)
  .push_svg(x, list(type = "scale", targets = targets, sx = sx, sy = sy,
                    origin_x = origin[["x"]], origin_y = origin[["y"]]))
}

#' Rotate selected SVG primitives around their collective centre
#' @param x An `inc_svg` with an active selection.
#' @param angle Clockwise angle in degrees.
#' @export
svg_rotate = function(x, angle) {
  targets = .require_svg_active(x, "svg_rotate")
  origin = .svg_selection_center(x)
  .push_svg(x, list(type = "rotate", targets = targets, angle = angle,
                    origin_x = origin[["x"]], origin_y = origin[["y"]]))
}

#' Change presentation properties of selected SVG primitives
#' @param x An `inc_svg` with an active selection.
#' @param fill,stroke,opacity,font_size Values to set; `NULL` leaves a property unchanged.
#' @export
svg_style = function(x, fill = NULL, stroke = NULL, opacity = NULL, font_size = NULL) {
  targets = .require_svg_active(x, "svg_style")
  values = list(fill = fill, stroke = stroke, opacity = opacity, `font-size` = font_size)
  values = values[!vapply(values, is.null, logical(1))]
  if (!length(values)) {
    inc_abort("svg_style() needs at least one property to change.", class = "inc_error_no_effect")
  }
  .push_svg(x, list(type = "style", targets = targets, values = values))
}

#' Hide selected SVG primitives
#' @param x An `inc_svg` with an active selection.
#' @export
svg_hide = function(x) {
  targets = .require_svg_active(x, "svg_hide")
  .push_svg(x, list(type = "style", targets = targets, values = list(display = "none")))
}

#' Move selected SVG primitives to the front or back of their parent
#' @param x An `inc_svg` with an active selection.
#' @param where "front" or "back".
#' @export
svg_zorder = function(x, where = c("front", "back")) {
  targets = .require_svg_active(x, "svg_zorder")
  .push_svg(x, list(type = "z", targets = targets, where = match.arg(where)))
}

.svg_find_id = function(doc, id) {
  xml2::xml_find_first(doc, sprintf("//*[@data-inc-id='%s']", id))
}

.svg_add_transform = function(node, value) {
  old = xml2::xml_attr(node, "transform")
  xml2::xml_attr(node, "transform") = paste(c(old[!is.na(old)], value), collapse = " ")
}

.apply_svg_operations = function(doc, x) {
  for (op in x$operations) {
    for (id in op$targets) {
      node = .svg_find_id(doc, id)
      if (inherits(node, "xml_missing")) err_no_match(sprintf("SVG operation target `%s`", id), xml2::xml_attr(.svg_nodes(doc), "data-inc-id"))
      if (op$type == "translate") {
        .svg_add_transform(node, sprintf("translate(%.12g %.12g)", op$dx, -op$dy))
      } else if (op$type == "scale") {
        oy = x$height - op$origin_y
        .svg_add_transform(node, sprintf("translate(%.12g %.12g) scale(%.12g %.12g) translate(%.12g %.12g)",
                                         op$origin_x, oy, op$sx, op$sy, -op$origin_x, -oy))
      } else if (op$type == "rotate") {
        oy = x$height - op$origin_y
        .svg_add_transform(node, sprintf("rotate(%.12g %.12g %.12g)", op$angle, op$origin_x, oy))
      } else if (op$type == "style") {
        style = xml2::xml_attr(node, "style")
        for (key in names(op$values)) style = .set_style_value(style, key, op$values[[key]])
        xml2::xml_attr(node, "style") = style
      } else if (op$type == "z") {
        parent = xml2::xml_parent(node)
        if (op$where == "front") {
          xml2::xml_add_child(parent, node, .copy = TRUE)
        } else {
          first = xml2::xml_children(parent)[[1]]
          xml2::xml_add_sibling(first, node, .where = "before", .copy = TRUE)
        }
        xml2::xml_remove(node)
      }
    }
  }
  doc
}
