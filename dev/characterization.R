# Characterization tests for Incantation's UPSTREAM ASSUMPTIONS.
#
# These do NOT depend on the incantation package. They pin down facts about
# patchwork / aplot / cowplot / grid that our design rests on. If an upstream
# package changes any of these, this file goes red BEFORE our own tests do —
# which is what we want, because these facts are our dependency, not our code.
#
# Run:  Rscript dev/characterization.R
#
# Verified on: R 4.4.2, ggplot2 4.0.3, patchwork 1.3.0, aplot 0.2.4, cowplot 1.1.3

options(warn = -1)
suppressPackageStartupMessages({
  library(ggplot2)
  library(patchwork)
  library(aplot)
  library(cowplot)
  library(gtable)
  library(grid)
  library(testthat)
})

p1 = ggplot(mtcars, aes(wt, mpg)) + geom_point() + labs(y = "MPG_MAIN")
p2 = ggplot(mtcars, aes(wt, hp)) + geom_point() + labs(y = "HP_LEFT")
p3 = ggplot(mtcars, aes(factor(cyl))) + geom_bar() + labs(y = "BAR_TOP")

# --- shared helpers (kept deliberately thin; see AGENTS.md) -------------------

bbox_cell = function(gt, name) {
  i = which(gt$layout$name == name)[1]
  lay = gt$layout[i, ]
  pushViewport(viewport(layout = grid.layout(
    nrow(gt), ncol(gt), widths = gt$widths, heights = gt$heights
  )))
  pushViewport(viewport(layout.pos.row = lay$t:lay$b, layout.pos.col = lay$l:lay$r))
  bl = grid::deviceLoc(unit(0, "npc"), unit(0, "npc"), valueOnly = TRUE)
  tr = grid::deviceLoc(unit(1, "npc"), unit(1, "npc"), valueOnly = TRUE)
  popViewport(2)
  c(left = bl$x * 72, bottom = bl$y * 72, right = tr$x * 72, top = tr$y * 72)
}

on_device = function(w, h, f) {
  pdf(NULL, width = w, height = h)
  on.exit({ dev.off() }, add = TRUE)
  grid.newpage()
  f()
}

ylab_of = function(gt, suffix) {
  i = which(gt$layout$name == paste0("ylab-l-", suffix))
  if (!length(i)) return(NA_character_)
  g = gt$grobs[[i]]
  if (inherits(g, "zeroGrob")) return("<empty>")
  tryCatch(g$children[[1]]$label, error = function(e) NA_character_)
}

# =============================================================================
test_that("REVIEW 1.1 — patchwork FLATTENS: a subplot is a grob-set, not a grob", {
  gt = patchworkGrob((p1 + p2 + p3 + plot_spacer()) +
                       plot_layout(widths = c(2, 1), heights = c(9, 1)))

  # There is no single grob representing subplot 3.
  expect_false(any(gt$layout$name == "plot-3"))

  # Instead: ~22 cells share the "-3" suffix.
  expect_gt(sum(grepl("-3$", gt$layout$name)), 15)
  expect_true(all(c("panel-3", "axis-l-3", "background-3", "title-3") %in% gt$layout$name))

  # => select_plot(3) MUST resolve to a set. Any design assuming a single
  #    grob is wrong at the first line.
})

# =============================================================================
test_that("REVIEW 1.4 — clip='on' cells are SIBLINGS holding rects/zeroGrobs, not ancestors", {
  gt = patchworkGrob((p1 + p2 + p3 + plot_spacer()) +
                       plot_layout(widths = c(2, 1), heights = c(9, 1)))

  clipped = gt$layout$clip == "on"
  expect_lt(sum(clipped), 10)   # only a handful, out of ~70

  # Every clipped cell holds a rect or a zeroGrob -> clipping them harms nothing.
  cls = vapply(gt$grobs[clipped], \(g) class(g)[1], character(1))
  expect_true(all(cls %in% c("rect", "zeroGrob")))

  # => README's "multi-layer clipping chain" is a non-problem for flat gtables.
  #    In-place wrapping + layout$clip[i]="off" is sufficient. No overlay needed.
})

# =============================================================================
test_that("REVIEW 1.2 — aplot's plot_index is NOT identity; main plot is panel-4", {
  ap = p1 |> insert_left(p2, width = .5) |> insert_top(p3, height = .3)
  gt = ggplotify::as.grob(ap)

  # The trap, stated as plainly as possible:
  expect_equal(ylab_of(gt, 1), "<empty>")     # panel-1 is a SPACER
  expect_equal(ylab_of(gt, 2), "HP_LEFT")
  expect_equal(ylab_of(gt, 3), "BAR_TOP")
  expect_equal(ylab_of(gt, 4), "MPG_MAIN")    # the MAIN plot is panel-4

  # Contrast: plain patchwork IS identity.
  gtp = patchworkGrob((p1 + p2 + p3 + plot_spacer()) +
                        plot_layout(widths = c(2, 1), heights = c(9, 1)))
  expect_equal(ylab_of(gtp, 1), "MPG_MAIN")   # here panel-1 IS the main plot

  # => select_plot(1) means two different things in two backends.
  #    Every adapter must build its own index map. Never assume identity.
})

test_that("REVIEW 4.3 — aplot index map can be recovered from $layout by position", {
  ap = p1 |> insert_left(p2, width = .5) |> insert_top(p3, height = .3)
  gt = ggplotify::as.grob(ap)

  cells = subset(gt$layout, grepl("^panel-\\d+$", name))
  rows = sort(unique(cells$t))
  cols = sort(unique(cells$l))
  cells$plot_index = mapply(
    \(t, l) ap$layout[match(t, rows), match(l, cols)],
    cells$t, cells$l
  )
  cells$suffix = as.integer(sub("^panel-", "", cells$name))

  got = setNames(cells$plot_index, cells$suffix)
  expect_true(is.na(got[["1"]]))     # spacer
  expect_equal(got[["2"]], 2)
  expect_equal(got[["3"]], 3)
  expect_equal(got[["4"]], 1)        # main plot -> plotlist[[1]]
})

# =============================================================================
test_that("REVIEW 1.3 — '-1$' regex collides with inset_element names", {
  gt = patchworkGrob(p1 + inset_element(p2, .6, .6, 1, 1))

  expect_true("inset_2-1" %in% gt$layout$name)

  hit = grep("-1$", gt$layout$name, value = TRUE)
  expect_true("panel-1" %in% hit)
  expect_true("inset_2-1" %in% hit)   # <- the bug: inset gets dragged along

  # => a suffix regex is not a selector. Translating "plot 1" would silently
  #    also move the inset.
})

# =============================================================================
test_that("REVIEW 1.5 — nested patchwork is RECURSIVE, not flat", {
  gt = patchworkGrob(p1 | (p2 / p3))

  panels = grep("^panel-\\d+$", gt$layout$name, value = TRUE)
  expect_equal(panels, "panel-1")   # only ONE panel at top level

  # The nested half becomes a nested gtable + a clipped marker cell.
  expect_true("patchwork-table-2" %in% gt$layout$name)
  expect_true("panel-nested-patchwork-2" %in% gt$layout$name)

  nested = gt$grobs[[which(gt$layout$name == "patchwork-table-2")]]
  expect_s3_class(nested, "gtable")
  expect_true(any(grepl("^panel-\\d+$", nested$layout$name)))

  # The one place a real clip DOES appear:
  expect_equal(gt$layout$clip[gt$layout$name == "panel-nested-patchwork-2"], "on")

  # => registry must be a tree walk with paths, not a scan of layout$name.
})

# =============================================================================
test_that("REVIEW 4.2 — cowplot is structurally different: one panel, gTree children", {
  cg = plot_grid(p1, p2, p3, NULL, ncol = 2, rel_widths = c(2, 1), rel_heights = c(9, 1))
  gt = ggplotGrob(cg)

  # cowplot returns a ggplot, whose gtable has exactly ONE panel cell...
  expect_true(inherits(cg, "ggplot"))
  expect_equal(sum(gt$layout$name == "panel"), 1)
  expect_false(any(grepl("^panel-\\d+$", gt$layout$name)))   # no per-subplot cells

  # ...and all subplots live INSIDE that panel as gTree children.
  panel = gt$grobs[[which(gt$layout$name == "panel")[1]]]
  expect_s3_class(panel, "gTree")
  expect_gte(sum(grepl("GeomDrawGrob", names(panel$children))), 3)

  # => cowplot registry: path = c(panel_cell, child_idx), container="gtree-child".
  #    patchwork/aplot:   path = c(cell),               container="gtable-cell".
})

# =============================================================================
test_that("REVIEW 2.1 — gap across ABSOLUTE rows is device-independent", {
  gt = patchworkGrob(p1 / p2)
  gap_at = function(w, h) on_device(w, h, function() {
    unname(bbox_cell(gt, "panel-1")["bottom"] - bbox_cell(gt, "panel-2")["top"])
  })
  g1 = gap_at(10, 8); g2 = gap_at(5, 4); g3 = gap_at(10, 16)
  expect_equal(g1, g2, tolerance = 1e-6)
  expect_equal(g1, g3, tolerance = 1e-6)
})

test_that("REVIEW 2.1 — gap across a NULL row is device-DEPENDENT (pt is not portable)", {
  gt = patchworkGrob((p1 / plot_spacer() / p2) + plot_layout(heights = c(4, 1, 4)))
  gap_at = function(w, h) on_device(w, h, function() {
    unname(bbox_cell(gt, "panel-1")["bottom"] - bbox_cell(gt, "panel-3")["top"])
  })
  small = gap_at(5, 4); mid = gap_at(10, 8); tall = gap_at(10, 16)

  expect_gt(mid, small + 10)    # 101.6 vs 69.6
  expect_gt(tall, mid + 10)     # 165.6 vs 101.6

  # An agent measuring at 10x8 and saving at 5x4 overshoots by ~32pt.
  # => scene MUST bind a device size; place_below() must re-resolve at render.
})

test_that("REVIEW 2.1 — element SIZE is always device-dependent (panels are null units)", {
  gt = patchworkGrob(p1 / p2)
  h_at = function(w, h) on_device(w, h, function() {
    b = bbox_cell(gt, "panel-1"); unname(b["top"] - b["bottom"])
  })
  expect_gt(h_at(10, 16), h_at(10, 8))
  expect_gt(h_at(10, 8), h_at(5, 4))
})

# =============================================================================
test_that("REVIEW Phase 0 — gtable draws NO named cell viewports until grid.force()", {
  gt = patchworkGrob(p1 / p2)

  pdf(NULL, width = 10, height = 8); grid.newpage(); grid.draw(gt)
  before = unique(grid.ls(viewports = TRUE, grobs = FALSE, print = FALSE)$name)
  grid.force()
  after = unique(grid.ls(viewports = TRUE, grobs = FALSE, print = FALSE)$name)
  dev.off()

  expect_lt(length(before), 5)                       # ROOT / layout / 1
  expect_false(any(grepl("^panel-1", before)))       # seekViewport("panel-1") FAILS
  expect_gt(length(after), 20)
  expect_true(any(grepl("^panel-1\\.", after)))      # "panel-1.11-9-11-9"

  # => don't build bbox on seekViewport. Push grid.layout + deviceLoc instead.
})

# =============================================================================
test_that("REVIEW 2.3 — z-order lets a later subplot occlude an earlier one", {
  gt = patchworkGrob(p1 / p3)

  z1 = range(gt$layout$z[grepl("-1$", gt$layout$name)])
  z2 = range(gt$layout$z[grepl("-2$", gt$layout$name)])
  expect_lt(z1[2], z2[2])   # subplot 2's content draws ON TOP of subplot 1's

  # And subplot backgrounds are opaque rects spanning the whole subplot.
  bg = gt$grobs[[which(gt$layout$name == "background-2")]]
  expect_s3_class(bg, "rect")
  expect_equal(bg$gp$fill, "white")

  # Saved by luck: patchwork puts every background at z=0, so it draws early.
  expect_equal(gt$layout$z[gt$layout$name == "background-2"], 0)

  # => moving subplot 1 DOWN into subplot 2's area hides it behind subplot 2.
  #    translate(plot(k)) must exclude background-k and diagnose z conflicts.
})

# =============================================================================
test_that("REVIEW 3.1 — in-place vp wrapping preserves the frozen-layout invariant", {
  gt0 = patchworkGrob((p1 + p2 + p3 + plot_spacer()) +
                        plot_layout(widths = c(2, 1), heights = c(9, 1)))

  gt1 = gt0
  for (i in grep("-3$", gt1$layout$name)) {
    if (inherits(gt1$grobs[[i]], "zeroGrob")) next
    gt1$grobs[[i]] = grobTree(gt1$grobs[[i]], vp = viewport(
      y = unit(0.5, "npc") + unit(24, "pt"), height = unit(1, "npc"), clip = "off"
    ))
    gt1$layout$clip[i] = "off"
  }

  expect_identical(gt0$widths, gt1$widths)
  expect_identical(gt0$heights, gt1$heights)
  expect_identical(dim(gt0), dim(gt1))
  expect_identical(length(gt0$grobs), length(gt1$grobs))
  expect_identical(
    gt0$layout[setdiff(names(gt0$layout), "clip")],
    gt1$layout[setdiff(names(gt1$layout), "clip")]
  )

  # Siblings must not move ON THE DEVICE either -- stronger than table equality.
  on_device(10, 8, function() {
    for (nm in c("panel-1", "panel-2")) {
      expect_equal(bbox_cell(gt0, nm), bbox_cell(gt1, nm), tolerance = 1e-9)
    }
  })
})

cat("\n[characterization] all upstream assumptions verified.\n")
