# incantation 0.1.0

First release: a post-layout visual editing layer for ggplot2, patchwork, aplot
and cowplot figures.

## Measure (the product)

* `incant(x, width, height, units)` binds a figure to a device size and measures
  every element once. A device size is **required** — a point offset chosen at
  one size overshoots at another.
* `bbox()`, `gap()`, `inspect()`, `canvas_size()`, `plot_label()`. `gap()` is
  signed and carries a `device_dependent` flag: when the span crosses a null
  track, the same pt value will not reproduce at another size.

## Select (structured, never a regex)

* `select_plot()`, `select_panel()`, `select_role()`, `select_id()`,
  `selection_spec()`. A selector that resolves to nothing, or to an empty grob,
  is an **error** — no silent no-op.

## Transform (frozen layout)

* `translate()` moves after layout without touching widths/heights/positions;
  the opaque subplot background is left behind by default.
* `place_below()` / `place_above()` state a target gap and re-resolve it at
  render time, so the result is device-independent.
* `align_top()` / `align_bottom()` / `align_left()` / `align_right()`,
  `bring_to_front()` / `send_to_back()`.

## Diagnose & render

* `diagnose()`, `detect_overlap()` for the agent feedback loop.
* `render()` (with `debug`), `draw()`, `as_gtable()`, `ggsave_incant()` (refuses
  a device size other than the scene's).

## Serialise

* `as_manifest()`, `write_incantation()`, `apply_incantation()`.

## Backends

ggplot2, patchwork (including nested compositions, `inset_element` and faceted
subplots), aplot (with its non-identity plot indexing) and cowplot. Reference
targets are a plot index (integer) or an element id (string); there are no
`plot()` / `id()` locators, which would mask base functions.
