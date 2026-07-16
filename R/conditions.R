# Structured conditions. Every failure an agent can provoke gets its own class,
# so the loop can branch on the class instead of parsing a message string.

inc_abort = function(message, class, ..., call = NULL) {
  structure(
    class = c(class, "inc_error", "error", "condition"),
    list(message = message, call = call, ...)
  ) |>
    stop()
}

# The single most important guard in the package (REVIEW s2.2): a selector that
# resolves to nothing must never return the input unchanged.
err_no_match = function(what, available) {
  inc_abort(
    sprintf("%s matched no element. available: %s.",
            what, paste(available, collapse = ", ")),
    class = "inc_error_no_match",
    available = available
  )
}

err_empty_target = function(id) {
  inc_abort(
    sprintf("`%s` resolves only to empty/zero grobs (a spacer or blank slot); there is nothing to move.", id),
    class = "inc_error_empty_target",
    id = id
  )
}

err_no_device = function() {
  inc_abort(
    "incant() needs an explicit device size: incant(x, width = , height = , units = ). Every measurement is meaningless without one (REVIEW s2.1).",
    class = "inc_error_no_device"
  )
}

err_device_mismatch = function(scene_dev, render_dev) {
  inc_abort(
    sprintf(
      "device mismatch: scene was measured at %g x %g %s but you asked to render at %g x %g %s. A pt offset picked at one size overshoots at another; re-run incant() at the target size.",
      scene_dev$width, scene_dev$height, scene_dev$units,
      render_dev$width, render_dev$height, render_dev$units
    ),
    class = "inc_error_device_mismatch"
  )
}

err_no_selection = function(fn) {
  inc_abort(
    sprintf("`%s()` needs an active selection. Pipe a select_*() first, e.g. scene |> select_plot(3) |> %s(...).", fn, fn),
    class = "inc_error_no_selection"
  )
}
