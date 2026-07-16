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
  # 关键：先完成整个 patchwork 的布局
  gt <- .as_laid_out_gtable(x)
  
  dx <- if (grid::is.unit(dx)) dx else grid::unit(dx, unit)
  dy <- if (grid::is.unit(dy)) dy else grid::unit(dy, unit)
  
  # select:
  # NULL      = 移动全部 grob
  # character = 用正则表达式匹配 gt$layout$name
  # numeric   = 直接指定 grob 下标
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
  
  # 只替换绘制对象，不改变布局表的 t/l/b/r 和 widths/heights
  gt$grobs[idx] <- lapply(
    gt$grobs[idx],
    translate_one
  )
  
  # 允许被移动的对象伸入相邻 patchwork 单元格
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

