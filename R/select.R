# Selection. Every select_* verb resolves to a concrete element id, errors if it
# resolves to nothing (REVIEW s2.2: no silent no-op) or to an empty grob, and
# stores the target on the scene for the next verb in the pipe.

`%||%` = function(a, b) if (is.null(a)) b else a

# friendly role -> how to find it in the registry
.role_vocab = c("panel", "axis-l", "axis-r", "axis-t", "axis-b",
                "title", "subtitle", "caption", "xlab", "ylab",
                "legend", "background")

.set_active = function(scene, target, spec) {
  el = scene$registry[[target]]
  if (is.null(el)) err_no_match(sprintf("`%s`", target), names(scene$registry))
  if (isTRUE(el$is_empty)) err_empty_target(target)
  scene$active = list(target = target, ids = target, spec = spec)
  scene
}

#' Select a whole subplot by its plot index
#' @param scene An `inc_scene`.
#' @param index Integer plot index as the user composed it.
#' @export
select_plot = function(scene, index) {
  id = paste0("plot-", as.integer(index))
  if (is.null(scene$registry[[id]])) {
    idx = sort(vapply(Filter(function(e) e$role == "plot", scene$registry),
                      `[[`, integer(1), "plot_index"))
    err_no_match(sprintf("plot index %s", index), idx)
  }
  .set_active(scene, id, list(type = "plot", index = as.integer(index)))
}

#' Select a subplot's panel (its data region)
#' @inheritParams select_plot
#' @export
select_panel = function(scene, index) {
  .set_active(scene, paste0("plot-", as.integer(index), "/panel"),
              list(type = "panel", index = as.integer(index)))
}

#' Select an element by semantic role
#' @param scene An `inc_scene`.
#' @param role One of `r paste(incantation:::.role_vocab, collapse = ", ")`.
#' @param plot Plot index the role belongs to (defaults to the only plot).
#' @export
select_role = function(scene, role, plot = NULL) {
  if (!role %in% c(.role_vocab, .atomic_roles)) {
    err_no_match(sprintf("role `%s`", role), .role_vocab)
  }
  if (is.null(plot)) {
    idx = unique(stats::na.omit(vapply(scene$registry, function(e) as.integer(e$plot_index), integer(1))))
    plot = if (length(idx) == 1) idx else
      inc_abort("this figure has several plots; pass `plot =`.", class = "inc_error_ambiguous")
  }
  raw = .resolve_role(scene, role, plot)
  .set_active(scene, raw, list(type = "role", role = role, index = as.integer(plot)))
}

.resolve_role = function(scene, role, plot) {
  pref = paste0("plot-", plot, "/")
  cand = switch(role,
    legend = {
      boxes = paste0(pref, c("guide-box-right", "guide-box-left",
                             "guide-box-top", "guide-box-bottom", "guide-box-inside"))
      live = Filter(function(id) !is.null(scene$registry[[id]]) && !isTRUE(scene$registry[[id]]$is_empty), boxes)
      if (length(live)) live[[1]] else paste0(pref, "guide-box-right")
    },
    xlab = { c(paste0(pref, "xlab-b"), paste0(pref, "xlab-t")) },
    ylab = { c(paste0(pref, "ylab-l"), paste0(pref, "ylab-r")) },
    paste0(pref, role)
  )
  hit = Filter(function(id) !is.null(scene$registry[[id]]), cand)
  if (length(hit) == 0) {
    avail = grep(paste0("^plot-", plot, "/"), names(scene$registry), value = TRUE)
    err_no_match(sprintf("role `%s` on plot %s", role, plot), sub(paste0("plot-", plot, "/"), "", avail))
  }
  hit[[1]]
}

#' Select an element by its exact id
#' @param scene An `inc_scene`.
#' @param id Element id, e.g. "plot-3/panel" or "inset-2".
#' @export
select_id = function(scene, id) {
  .set_active(scene, id, list(type = "id", id = id))
}

#' The structured spec of the active selection (never a regex)
#' @param scene An `inc_scene` with an active selection.
#' @export
selection_spec = function(scene) {
  if (is.null(scene$active)) err_no_selection("selection_spec")
  scene$active$spec
}
