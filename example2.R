.as_laid_out_gtable <- function(x) {
  if (inherits(x, "patchwork")) {
    patchwork::patchworkGrob(x)
  } else if (inherits(x, "ggplot")) {
    ggplot2::ggplotGrob(x)
  } else if (inherits(x, "gtable")) {
    x
  } else {
    stop(
      "`x` must be a ggplot, patchwork, or gtable.",
      call. = FALSE
    )
  }
}


nudge_after_layout <- function(
    x,
    select = NULL,
    dx = 0,
    dy = 0,
    unit = "pt",
    clip = "off"
) {
  # Key: finish the complete patchwork layout first
  gt <- .as_laid_out_gtable(x)
  
  dx <- if (grid::is.unit(dx)) dx else grid::unit(dx, unit)
  dy <- if (grid::is.unit(dy)) dy else grid::unit(dy, unit)
  
  # select:
  # NULL      = Move all grobs
  # character = Match gt$layout$name with a regular expression
  # numeric   = Specify grob indices directly
  idx <- if (is.null(select)) {
    seq_along(gt$grobs)
  } else if (is.character(select)) {
    grep(select, gt$layout$name)
  } else if (is.numeric(select)) {
    as.integer(select)
  } else {
    stop(
      "`select` must be NULL, a regex string, or numeric indices.",
      call. = FALSE
    )
  }
  
  if (!length(idx)) {
    stop(
      paste0(
        "No grobs matched `select`. ",
        "Inspect `patchwork::patchworkGrob(x)$layout$name`."
      ),
      call. = FALSE
    )
  }
  
  translate_one <- function(g) {
    grid::grobTree(
      g,
      vp = grid::viewport(
        x = grid::unit(0.5, "npc") + dx,
        y = grid::unit(0.5, "npc") + dy,
        width = grid::unit(1, "npc"),
        height = grid::unit(1, "npc"),
        just = c("center", "center"),
        clip = clip
      ),
      name = "postlayout-translated-grob"
    )
  }
  
  # Replace drawing objects only; preserve layout t/l/b/r and widths/heights
  gt$grobs[idx] <- lapply(
    gt$grobs[idx],
    translate_one
  )
  
  # Allow moved objects to extend into adjacent patchwork cells
  gt$layout$clip[idx] <- clip
  
  attr(gt, "nudged_layout_names") <- gt$layout$name[idx]
  
  gt
}

p_c_shifted <- nudge_after_layout(
  p_c,
  select = "-3$",
  dy = 50,
  unit = "pt"
)

grid::grid.newpage()
grid::grid.draw(p_c_shifted)

