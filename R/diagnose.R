# Diagnostics close the agent loop (REVIEW s6.3): after an edit, report in
# machine-readable form what went wrong -- element off canvas, a moved element
# hidden behind a higher-z neighbour, or an opaque background dragged over a
# sibling.

.part_rect = function(scene, part) {
  if (!is.null(part$decoration_id)) {
    return(.decoration_component_rect(scene, part$decoration_id, part$component))
  }
  sh = .net_shift(scene, part$grob_path)
  b = part$base
  c(left = b[["left"]] + sh$dx, right = b[["right"]] + sh$dx,
    bottom = b[["bottom"]] + sh$dy, top = b[["top"]] + sh$dy)
}

.plot_rect = function(scene, el) {
  r = .anchor_rect(scene, el)
  c(left = unname(r["left"]), right = unname(r["right"]),
    bottom = unname(r["bottom"]), top = unname(r["top"]))
}

.is_moved = function(scene, el) {
  s = .net_shift(scene, el$parts[[el$anchor[1]]]$grob_path)
  s$dx != 0 || s$dy != 0
}

#' Machine-readable diagnostics for the current scene
#'
#' @param scene An `inc_scene`.
#' @return A list with `status` ("ok" or "warning") and a character vector of `issues`.
#' @export
diagnose = function(scene) {
  issues = character(0)
  cv = .canvas_pt(scene)
  plots = Filter(function(e) e$role == "plot" && !isTRUE(e$is_empty), scene$registry)
  if (length(plots) == 0) return(list(status = "ok", issues = issues))

  rects = lapply(plots, function(e) .plot_rect(scene, e))
  zeff = vapply(plots, function(e) .effective_z(scene, e), numeric(1))
  moved = vapply(plots, function(e) .is_moved(scene, e), logical(1))
  ids = vapply(plots, `[[`, character(1), "id")

  # off canvas (only worth flagging for things the user moved)
  for (i in which(moved)) {
    r = rects[[i]]
    if (r["left"] < -0.5 || r["bottom"] < -0.5 || r["right"] > cv["width"] + 0.5 || r["top"] > cv["height"] + 0.5) {
      issues = c(issues, sprintf("%s is partially outside canvas", ids[i]))
    }
  }

  # a moved plot hidden behind a higher-z overlapping neighbour
  for (i in which(moved)) {
    for (j in seq_along(plots)) {
      if (j == i) next
      ov = rect_overlap(rects[[i]], rects[[j]])
      if (ov["x"] > 0.5 && ov["y"] > 0.5 && zeff[j] > zeff[i]) {
        issues = c(issues, sprintf("%s is covered by %s (behind in z-order)", ids[i], ids[j]))
      }
    }
  }

  # an opaque background dragged over a sibling
  for (tr in scene$transforms) {
    if (!identical(tr$type, "translate") || !isTRUE(tr$include_background)) next
    el = scene$registry[[tr$target]]
    for (p in el$parts) {
      if (!isTRUE(p$is_background) || isTRUE(p$is_blank)) next
      br = .part_rect(scene, p)
      for (j in seq_along(plots)) {
        if (identical(ids[[j]], tr$target)) next
        ov = rect_overlap(br, rects[[j]])
        if (ov["x"] > 0.5 && ov["y"] > 0.5) {
          issues = c(issues, sprintf("opaque background of %s occludes %s", tr$target, ids[j]))
        }
      }
    }
  }

  # Decorations are fixed-canvas overlays. Report overflow instead of growing
  # the canvas or silently clipping a title at the device edge.
  for (id in names(scene$decorations)) {
    geometry = .decoration_geometry(scene, scene$decorations[[id]])
    components = list(line = geometry$line_rect)
    if (!is.null(geometry$title_rect)) components$title = geometry$title_rect
    for (component in names(components)) {
      r = components[[component]]
      if (r["left"] < -0.5 || r["bottom"] < -0.5 ||
          r["right"] > cv["width"] + 0.5 || r["top"] > cv["height"] + 0.5) {
        issues = c(issues, sprintf("%s/%s is partially outside canvas", id, component))
      }
    }
  }

  list(status = if (length(issues)) "warning" else "ok", issues = unique(issues))
}

#' Pairwise panel overlaps after editing
#'
#' @param scene An `inc_scene`.
#' @return A data frame with `a`, `b`, `overlap_pt` and `axis`.
#' @export
detect_overlap = function(scene) {
  plots = Filter(function(e) e$role == "plot" && !isTRUE(e$is_empty), scene$registry)
  ids = vapply(plots, `[[`, character(1), "id")
  rects = lapply(plots, function(e) .plot_rect(scene, e))
  out = list()
  if (length(plots) >= 2) {
    for (i in seq_len(length(plots) - 1)) {
      for (j in (i + 1):length(plots)) {
        ov = rect_overlap(rects[[i]], rects[[j]])
        if (ov["x"] > 0.5 && ov["y"] > 0.5) {
          out[[length(out) + 1]] = data.frame(
            a = ids[i], b = ids[j],
            overlap_pt = unname(min(ov["x"], ov["y"])),
            axis = if (ov["y"] <= ov["x"]) "vertical" else "horizontal",
            stringsAsFactors = FALSE
          )
        }
      }
    }
  }
  if (length(out)) do.call(rbind, out)
  else data.frame(a = character(0), b = character(0), overlap_pt = numeric(0), axis = character(0))
}
