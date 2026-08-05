# Fixtures for the incantation spec suite.
#
# fx_panel_row() is a compact structural analogue of example.R's `p_c`:
# a tall "heatmap" on the left, a companion plot on the right, and a short
# marker row underneath carrying a large bottom margin -- which is exactly the
# geometry that makes p_cluster_c sit too far below the heatmap.

suppressPackageStartupMessages({
  library(ggplot2)
  library(patchwork)
  library(grid)
})

# --- device-size measurement helpers (mirror what incant() must do) -----------

fx_on_device = function(w, h, f) {
  grDevices::pdf(NULL, width = w, height = h)
  on.exit(grDevices::dev.off(), add = TRUE)
  grid::grid.newpage()
  f()
}

fx_bbox_cell = function(gt, name) {
  i = which(gt$layout$name == name)[1]
  if (is.na(i)) stop("no cell named ", name)
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

# --- fixtures ----------------------------------------------------------------

fx_heat = function() {
  d = expand.grid(x = letters[1:9], y = paste0("f", 1:20))
  d$v = as.numeric(seq_len(nrow(d))) %% 7
  ggplot2::ggplot(d, ggplot2::aes(x, y, fill = v)) +
    ggplot2::geom_tile(color = "white") +
    ggplot2::labs(x = NULL, y = NULL) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      legend.position = "top",
      axis.text.x = ggplot2::element_blank(),
      axis.ticks.x = ggplot2::element_blank(),
      plot.margin = ggplot2::margin(0.2, 0.2, 0, 0.2, "cm")
    )
}

fx_enrich = function() {
  d = data.frame(k = paste0("i", 1:9), v = 1:9, g = letters[1:9])
  ggplot2::ggplot(d, ggplot2::aes(reorder(k, v), v, fill = g)) +
    ggplot2::geom_col(show.legend = FALSE) +
    ggplot2::coord_flip() +
    ggplot2::labs(x = NULL, y = "-Log10(Relevance)") +
    ggplot2::theme_bw()
}

# The problem child: a one-row marker strip with a 45pt bottom margin.
fx_cluster = function() {
  d = data.frame(x = letters[1:9], lab = LETTERS[1:9])
  ggplot2::ggplot(d, ggplot2::aes(x, color = x)) +
    ggplot2::geom_point(ggplot2::aes(y = 1), size = 6, show.legend = FALSE) +
    ggplot2::geom_text(ggplot2::aes(y = 1, label = lab), angle = 30, hjust = 1, vjust = 2,
                       color = "black", show.legend = FALSE) +
    ggplot2::coord_cartesian(clip = "off") +
    ggplot2::theme(
      legend.position = "none",
      panel.background = ggplot2::element_blank(),
      plot.background = ggplot2::element_blank(),
      plot.margin = ggplot2::margin(0, 0, 45, 0, "pt"),
      axis.text = ggplot2::element_blank(), axis.title = ggplot2::element_blank(),
      axis.ticks = ggplot2::element_blank(), axis.line = ggplot2::element_blank(),
      panel.grid = ggplot2::element_blank()
    )
}

# Same 2x2 shape as example.R's p_c: subplot 3 is the one we want to move up.
fx_panel_row = function() {
  (fx_heat() + fx_enrich() + fx_cluster() + patchwork::plot_spacer()) +
    patchwork::plot_layout(widths = c(2, 1), heights = c(9, 1))
}

# Two stacked subplots on the DEFAULT theme, so each carries an opaque white
# plot.background rect -- the occlusion hazard example.R dodges by hand.
fx_opaque_stack = function() {
  (ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg)) + ggplot2::geom_point()) /
    (ggplot2::ggplot(mtcars, ggplot2::aes(wt, hp)) + ggplot2::geom_point())
}

fx_decoration_plot = function(title = NULL, right = FALSE, facets = FALSE) {
  p = ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg)) +
    ggplot2::geom_point() +
    ggplot2::labs(title = title) +
    ggplot2::theme(plot.margin = ggplot2::margin(26, 26, 26, 26, "pt"))
  if (right) {
    p = p + ggplot2::scale_y_continuous(position = "right") +
      ggplot2::labs(y = "Right axis")
  }
  if (facets) p = p + ggplot2::facet_wrap(~cyl)
  p
}

fx_skip_unless_backend = function(pkg) {
  testthat::skip_if_not_installed(pkg)
}
