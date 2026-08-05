# Result-native SVG snapshots. The SVG string is the source of truth and edits
# are stored as immutable operations, so copying an inc_svg never shares a
# mutable xml_document pointer.

.svg_leaf_xpath = paste0(
  "//*[not(ancestor::*[local-name()='defs']) and (",
  paste(sprintf("local-name()='%s'", c("circle", "ellipse", "line", "polyline",
                                      "polygon", "path", "rect", "text", "image", "use")),
        collapse = " or "),
  ")]"
)

.svg_doc = function(x, edited = TRUE) {
  doc = xml2::read_xml(x$svg)
  if (isTRUE(edited)) doc = .apply_svg_operations(doc, x)
  doc
}

.svg_nodes = function(doc) xml2::xml_find_all(doc, .svg_leaf_xpath)

.assign_svg_ids = function(doc) {
  nodes = .svg_nodes(doc)
  tags = xml2::xml_name(nodes)
  count = integer(0)
  for (i in seq_along(nodes)) {
    tag = tags[[i]]
    n = if (tag %in% names(count)) count[[tag]] + 1L else 1L
    count[[tag]] = n
    xml2::xml_attr(nodes[[i]], "data-inc-id") = sprintf("svg-%s-%04d", tag, n)
  }
  doc
}

.svg_number = function(x, default = NA_real_) {
  if (is.null(x) || is.na(x) || !nzchar(x)) return(default)
  out = suppressWarnings(as.numeric(sub("^\\s*([-+0-9.eE]+).*$", "\\1", x)))
  if (is.na(out)) default else out
}

.svg_attr = function(attrs, name, default = NULL) {
  if (name %in% names(attrs)) attrs[[name]] else default
}

.style_value = function(style, key, default = NA_character_) {
  if (is.na(style) || !nzchar(style)) return(default)
  pieces = trimws(strsplit(style, ";", fixed = TRUE)[[1]])
  pieces = pieces[nzchar(pieces)]
  hit = pieces[startsWith(pieces, paste0(key, ":"))]
  if (!length(hit)) return(default)
  trimws(sub("^[^:]+:", "", hit[[length(hit)]]))
}

.set_style_value = function(style, key, value) {
  pieces = if (is.na(style) || !nzchar(style)) character(0) else
    trimws(strsplit(style, ";", fixed = TRUE)[[1]])
  pieces = pieces[nzchar(pieces) & !startsWith(pieces, paste0(key, ":"))]
  paste(c(pieces, paste0(key, ": ", value)), collapse = "; ")
}

.svg_points = function(x) {
  nums = suppressWarnings(as.numeric(strsplit(trimws(gsub(",", " ", x)), "\\s+")[[1]]))
  nums = nums[!is.na(nums)]
  if (length(nums) < 2) return(matrix(numeric(0), ncol = 2))
  matrix(nums[seq_len(length(nums) - length(nums) %% 2)], ncol = 2, byrow = TRUE)
}

.svg_bbox_node = function(node, height) {
  tag = xml2::xml_name(node)
  at = xml2::xml_attrs(node)
  x1 = y1 = x2 = y2 = NA_real_

  if (tag == "circle") {
    cx = .svg_number(.svg_attr(at, "cx")); cy = .svg_number(.svg_attr(at, "cy")); r = .svg_number(.svg_attr(at, "r"), 0)
    x1 = cx - r; x2 = cx + r; y1 = cy - r; y2 = cy + r
  } else if (tag == "ellipse") {
    cx = .svg_number(.svg_attr(at, "cx")); cy = .svg_number(.svg_attr(at, "cy"))
    rx = .svg_number(.svg_attr(at, "rx"), 0); ry = .svg_number(.svg_attr(at, "ry"), 0)
    x1 = cx - rx; x2 = cx + rx; y1 = cy - ry; y2 = cy + ry
  } else if (tag %in% c("rect", "image")) {
    x1 = .svg_number(.svg_attr(at, "x"), 0); y1 = .svg_number(.svg_attr(at, "y"), 0)
    x2 = x1 + .svg_number(.svg_attr(at, "width"), 0); y2 = y1 + .svg_number(.svg_attr(at, "height"), 0)
  } else if (tag == "line") {
    x1 = .svg_number(.svg_attr(at, "x1")); y1 = .svg_number(.svg_attr(at, "y1"))
    x2 = .svg_number(.svg_attr(at, "x2")); y2 = .svg_number(.svg_attr(at, "y2"))
    xr = range(c(x1, x2)); yr = range(c(y1, y2)); x1 = xr[1]; x2 = xr[2]; y1 = yr[1]; y2 = yr[2]
  } else if (tag %in% c("polyline", "polygon")) {
    pts = .svg_points(.svg_attr(at, "points", ""))
    if (nrow(pts)) {
      x1 = min(pts[, 1]); x2 = max(pts[, 1]); y1 = min(pts[, 2]); y2 = max(pts[, 2])
    }
  } else if (tag == "text") {
    style = .svg_attr(at, "style", "")
    size = .svg_number(.style_value(style, "font-size", "11"), 11)
    width = .svg_number(.svg_attr(at, "textLength"), nchar(xml2::xml_text(node)) * size * 0.55)
    x = .svg_number(.svg_attr(at, "x"), 0); y = .svg_number(.svg_attr(at, "y"), 0)
    anchor = .svg_attr(at, "text-anchor", "start")
    x1 = switch(anchor, middle = x - width / 2, end = x - width, x)
    x2 = x1 + width; y1 = y - size; y2 = y + size * 0.25
  }

  c(left = x1, bottom = height - y2, right = x2, top = height - y1)
}

.svg_shift = function(x, id) {
  ops = Filter(function(op) identical(op$type, "translate") && id %in% op$targets, x$operations)
  c(dx = sum(vapply(ops, `[[`, numeric(1), "dx")),
    dy = sum(vapply(ops, `[[`, numeric(1), "dy")))
}

#' Capture an edited scene as a result-native SVG snapshot
#'
#' Text remains SVG text and every visible leaf primitive receives a stable id
#' within the snapshot. Later SVG operations depend only on this result, not on
#' ggplot layers, data or gtable paths.
#' @param scene An `inc_scene`.
#' @return An immutable `inc_svg`.
#' @export
as_svg = function(scene) {
  dev = scene$device
  width = .to_pt(dev$width, dev$units)
  height = .to_pt(dev$height, dev$units)
  take = svglite::svgstring(width = width / 72, height = height / 72, bg = "transparent")
  device_id = grDevices::dev.cur()
  on.exit(if (grDevices::dev.cur() == device_id) grDevices::dev.off(), add = TRUE)
  grid::grid.newpage()
  grid::grid.draw(as_gtable(scene))
  grDevices::dev.off()
  doc = take() |> as.character() |> xml2::read_xml() |> .assign_svg_ids()
  svg = as.character(doc)
  structure(
    list(svg = svg, width = width, height = height,
         source_hash = digest::digest(svg, algo = "sha256"),
         active = character(0), operations = list()),
    class = "inc_svg"
  )
}

#' Inspect the visible leaf primitives in an SVG snapshot
#' @param x An `inc_svg`.
#' @return A data frame in device points with origin at bottom-left. Bounding
#'   boxes are approximate for basic primitives and text, and unavailable for
#'   arbitrary paths and uses; fixed-size pixels from [verify_svg()] remain the
#'   final authority.
#' @export
svg_manifest = function(x) {
  doc = .svg_doc(x)
  nodes = .svg_nodes(doc)
  ids = xml2::xml_attr(nodes, "data-inc-id")
  boxes = Map(function(node, id) {
    box = .svg_bbox_node(node, x$height)
    shift = .svg_shift(x, id)
    box + c(shift[["dx"]], shift[["dy"]], shift[["dx"]], shift[["dy"]])
  }, as.list(nodes), ids)
  style = xml2::xml_attr(nodes, "style")
  display = vapply(style, .style_value, character(1), key = "display", default = "inline")
  opacity = vapply(style, .style_value, character(1), key = "opacity", default = "1")
  clips = vapply(as.list(nodes), function(node) {
    owner = xml2::xml_find_first(node, "ancestor::*[@clip-path][1]")
    if (inherits(owner, "xml_missing")) NA_character_ else xml2::xml_attr(owner, "clip-path")
  }, character(1))
  data.frame(
    id = ids,
    tag = xml2::xml_name(nodes),
    text = vapply(as.list(nodes), function(node) if (xml2::xml_name(node) == "text") xml2::xml_text(node) else "", character(1)),
    left = vapply(boxes, `[[`, numeric(1), "left"),
    bottom = vapply(boxes, `[[`, numeric(1), "bottom"),
    right = vapply(boxes, `[[`, numeric(1), "right"),
    top = vapply(boxes, `[[`, numeric(1), "top"),
    fill = vapply(style, .style_value, character(1), key = "fill", default = NA_character_),
    stroke = vapply(style, .style_value, character(1), key = "stroke", default = NA_character_),
    opacity = opacity,
    transform = xml2::xml_attr(nodes, "transform"),
    clip = clips,
    visible = display != "none" & suppressWarnings(as.numeric(opacity)) != 0,
    bbox_quality = ifelse(xml2::xml_name(nodes) %in% c("path", "use"), "unavailable", "approximate"),
    order = seq_along(nodes),
    stringsAsFactors = FALSE
  )
}

#' @export
print.inc_svg = function(x, ...) {
  cat(sprintf("<inc_svg> %.0f x %.0f pt  %d element(s), %d operation(s)\n",
              x$width, x$height, nrow(svg_manifest(x)), length(x$operations)))
  if (length(x$active)) cat(sprintf("  active: %s\n", paste(x$active, collapse = ", ")))
  invisible(x)
}
