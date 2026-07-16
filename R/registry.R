# Build the element registry from a laid-out gtable.
#
# The core fact (REVIEW s1.1): a "subplot" is not a grob, it is an equivalence
# class of gtable cells sharing a suffix. So every plot becomes an aggregate
# element `plot-k` whose `parts` are those cells, plus one atomic element per
# addressable role (`plot-k/panel`, `plot-k/axis-l`, ...). Nested patchwork
# (REVIEW s1.5) is handled by recursing into `patchwork-table-k` grobs and
# carrying a path + measurement frames down each level.

# roles we expose as individually addressable atomic elements
.atomic_roles = c(
  "panel", "background", "title", "subtitle", "caption",
  "axis-l", "axis-r", "axis-t", "axis-b",
  "xlab-t", "xlab-b", "ylab-l", "ylab-r",
  "guide-box-right", "guide-box-left", "guide-box-top",
  "guide-box-bottom", "guide-box-inside"
)

parse_cell = function(name, backend) {
  if (grepl("^inset_[0-9]+-[0-9]+$", name)) {
    m = regmatches(name, regexec("^inset_([0-9]+)-([0-9]+)$", name))[[1]]
    return(list(role = "inset", suffix = as.integer(m[3]),
                inset_id = as.integer(m[2]), inset = TRUE))
  }
  if (identical(backend, "ggplot")) {
    return(list(role = name, suffix = 1L))
  }
  g = regmatches(name, regexec("^(.+)-([0-9]+)$", name))[[1]]
  if (length(g) == 0) return(NULL)      # unsuffixed chrome: background, panel-area
  list(role = g[2], suffix = as.integer(g[3]))
}

# One gtable cell -> one part descriptor (position, path, measurement frames).
.make_part = function(gt, row, role, frames_prefix, grob_prefix) {
  lay = gt$layout[row, ]
  frame = list(widths = gt$widths, heights = gt$heights,
               t = lay$t, l = lay$l, b = lay$b, r = lay$r)
  list(
    role = role,
    grob_path = c(grob_prefix, row),
    frames = c(frames_prefix, list(frame)),
    is_background = role %in% c("background", "panel_patch"),
    is_blank = is_blank_grob(gt$grobs[[row]]),
    z = lay$z
  )
}

# A subplot's "panel" is any cell whose role starts with panel, EXCEPT the
# spacer placeholder / area chrome. A faceted subplot collapses its whole panel
# block into one nested cell whose role still starts with "panel" (its auto name
# is "panel; panel-1-1, ..."), so prefix-matching catches facets and plain panels
# alike; a multi-facet plot yields several, whose union is the data region.
.is_panel_role = function(role) {
  grepl("^panel", role) & !grepl("^panel_patch$|^panel-area$|^panel-nested", role)
}

.plot_elements = function(gt, rows, roles, user_index, frames_prefix, grob_prefix) {
  parts = Map(function(row, role) .make_part(gt, row, role, frames_prefix, grob_prefix),
              rows, roles)
  names(parts) = roles

  panel_i = which(.is_panel_role(roles))
  anchor_i = if (length(panel_i)) panel_i else which(!vapply(parts, `[[`, logical(1), "is_background"))[1]
  if (length(anchor_i) == 0 || anyNA(anchor_i)) anchor_i = 1L
  is_empty = length(panel_i) == 0 || all(vapply(parts[panel_i], `[[`, logical(1), "is_blank"))

  pid = paste0("plot-", user_index)
  aggregate = list(
    id = pid, role = "plot", plot_index = user_index,
    parts = unname(parts), anchor = anchor_i,
    container = if (length(grob_prefix)) "nested" else "gtable-cell",
    is_empty = is_empty
  )

  atomics = list()
  for (role in intersect(.atomic_roles, roles)) {
    if (sum(roles == role) != 1) next
    p = parts[[role]]
    atomics[[length(atomics) + 1]] = list(
      id = paste0(pid, "/", role), role = role, plot_index = user_index,
      parts = list(p), anchor = 1L,
      container = if (length(grob_prefix)) "nested" else "gtable-cell",
      is_empty = isTRUE(p$is_blank)
    )
  }
  c(list(aggregate), atomics)
}

build_elements = function(root, backend, index_map = NULL) {
  if (identical(backend, "cowplot")) return(build_elements_cowplot(root))

  els = list()
  counter = 0L

  walk = function(gt, frames_prefix, grob_prefix) {
    parsed = lapply(gt$layout$name, parse_cell, backend = backend)
    suffix_of = vapply(parsed, function(p) {
      if (is.null(p) || isTRUE(p$inset)) NA_integer_ else p$suffix
    }, integer(1))

    for (s in sort(unique(stats::na.omit(suffix_of)))) {
      rows = which(!is.na(suffix_of) & suffix_of == s)
      roles = vapply(parsed[rows], `[[`, character(1), "role")

      if ("patchwork-table" %in% roles) {                 # nested container
        trow = rows[roles == "patchwork-table"]
        lay = gt$layout[trow, ]
        frame = list(widths = gt$widths, heights = gt$heights,
                     t = lay$t, l = lay$l, b = lay$b, r = lay$r)
        walk(gt$grobs[[trow]], c(frames_prefix, list(frame)), c(grob_prefix, trow))
        next
      }

      if (is.null(index_map)) {                           # patchwork / ggplot
        counter <<- counter + 1L
        user_index = counter
      } else {                                            # aplot
        user_index = index_map(gt, s)
        if (is.na(user_index)) next                       # implicit spacer slot
      }
      els <<- c(els, .plot_elements(gt, rows, roles, user_index, frames_prefix, grob_prefix))
    }

    # insets live at their attachment level and are addressable on their own
    inset_rows = which(vapply(parsed, function(p) !is.null(p) && isTRUE(p$inset), logical(1)))
    for (ir in inset_rows) {
      part = .make_part(gt, ir, "inset", frames_prefix, grob_prefix)
      els[[length(els) + 1]] <<- list(
        id = paste0("inset-", parsed[[ir]]$inset_id), role = "inset",
        plot_index = NA_integer_, parts = list(part), anchor = 1L,
        container = if (length(grob_prefix)) "nested" else "gtable-cell",
        is_empty = isTRUE(part$is_blank)
      )
    }
  }

  walk(root, list(), integer(0))
  els
}

# cowplot (REVIEW s4.2): one "panel" cell; subplots are GeomDrawGrob children of
# that panel gTree, each positioned by its own viewport.
build_elements_cowplot = function(root) {
  panel_row = which(root$layout$name == "panel")[1]
  panel = root$grobs[[panel_row]]
  lay = root$layout[panel_row, ]
  panel_frame = list(widths = root$widths, heights = root$heights,
                     t = lay$t, l = lay$l, b = lay$b, r = lay$r)

  child_idx = grep("GeomDrawGrob", names(panel$children))
  els = list()
  for (k in seq_along(child_idx)) {
    ci = child_idx[k]
    child = panel$children[[ci]]
    vp = child$vp
    frames = list(panel_frame, list(vp = vp))
    part = list(role = "panel", grob_path = c(panel_row, ci), frames = frames,
                is_background = FALSE, is_blank = is_blank_grob(child), z = k)
    pid = paste0("plot-", k)
    els[[length(els) + 1]] = list(
      id = pid, role = "plot", plot_index = k,
      parts = list(part), anchor = 1L, container = "gtree-child",
      is_empty = isTRUE(part$is_blank)
    )
    els[[length(els) + 1]] = list(
      id = paste0(pid, "/panel"), role = "panel", plot_index = k,
      parts = list(part), anchor = 1L, container = "gtree-child",
      is_empty = isTRUE(part$is_blank)
    )
  }
  els
}
