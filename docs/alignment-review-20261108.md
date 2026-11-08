# Alignment and refinement audit — 2026-11-08

Status: the four reproduced defects below have now been repaired and tested in
the local working tree. Scene identity checks and explicit `plot_ids` also address
the replay risk, with documented limits for default labels and legacy manifests.
The original observations below describe the baseline, not the repaired behavior.
Baseline: local Incantation 0.3.0, commit `3c42891`, R 4.4.2,
ggplot2 4.0.2, patchwork 1.3.0 and cowplot 1.1.3.

## Evidence and scope

Inspected the UC Figure 6 baseline and compact225 outputs, their saved native panel
objects, geometry-only reviews and preservation checks, the UC authorial reflow
scripts, and the archived CXCL12 refinement observations and rejected Figure 4.
These are project figures and editing records, not a new reading of a paper.

Recurring tasks include aligning actual matrix/axis boundaries despite unequal
labels, moving finished modules without changing their bodies, keeping accepted
regions fixed, and replaying localized edits. The UC compact225 change moved
Figure 6 G/H upward by 58 mm while preserving panel bodies. Later source-context
revisions changed native patient/image displays; those are distinct operations.
Reserved experimental space is intentional and is not a layout defect by itself.

The inspected UC R scripts did not invoke Incantation. Their manual composition
does not establish an Incantation failure. Four problems below were separately
reproduced against the package, rather than inferred from those scripts.

## Improvements supported by reproductions

### 1. Use one physical point convention at rendering boundaries

[`rect_from_frames()` and `.to_pt()`](../R/utils-grid.R) use 72 points per inch;
`wrap_translate()` passes offsets to grid's `"pt"`, which uses 72.27 per inch.
An independent `deviceLoc()` measurement gives 0.99626401 inches for a 72-point
horizontal translation instead of the scene convention's 1 inch.

The existing unit tests compare scene coordinates with one another. They do not
independently measure this rendered displacement. Repair should retain a clear
public point convention and consistently convert at grid boundaries, including
other overlays using scene coordinates. Test both rendered displacement and
unselected-object preservation. This small difference does not explain historical
misalignments of several millimetres.

Minimal reproduction after loading this checkout:

```r
grDevices::pdf(NULL, width = 4, height = 4)
probe = grid::gTree(
  children = grid::gList(grid::rectGrob()),
  vp = grid::viewport(name = "inc-review-probe")
)
grid::grid.newpage()
grid::grid.draw(probe)
grid::seekViewport("inc-review-probe")
x0 = grid::deviceLoc(grid::unit(0.5, "npc"), grid::unit(0.5, "npc"),
                     valueOnly = TRUE)$x
grid::grid.newpage()
grid::grid.draw(incantation:::wrap_translate(probe, 72, 0))
grid::seekViewport("inc-review-probe")
x1 = grid::deviceLoc(grid::unit(0.5, "npc"), grid::unit(0.5, "npc"),
                     valueOnly = TRUE)$x
grDevices::dev.off()
x1 - x0
# Observed: 0.99626401; expected under scene convention: 1.
```

### 2. Distinguish cowplot placement slots from actual data anchors

[`build_elements_cowplot()`](../R/registry.R) uses each GeomDrawGrob viewport for
both `plot-k` and `plot-k/panel`. It does not descend into the contained ggplot's
data panel. Thus names suggest a data anchor while coordinates describe a slot.

For two equal-height cowplot slots with unequal margins, reported top edges both
equal 255.1181 points. Measuring the contained data panels gives 249.6387 versus
212.5984 points: a 13.06697 mm mismatch. `align_top(scene, 2, 1)` applies zero
displacement. The real saved UC Figure 6 C is also detected as a cowplot scene
with viewport anchors; this compatibility path is relevant to actual work.

```r
library(ggplot2)
library(cowplot)
p = ggplot(mtcars, aes(wt, mpg)) + geom_point() + theme_classic()
q = p + theme(axis.text.y = element_text(size = 20),
              plot.margin = margin(15, 2, 2, 25, "mm"))
scene = incantation::incant(
  cowplot::plot_grid(p, q, nrow = 1, align = "none"),
  width = 180, height = 90, units = "mm"
)
incantation::bbox(scene, 1)
incantation::bbox(scene, 2)
edited = incantation::align_top(scene, 2, 1)
# The reported tops already match; actual data-panel tops do not.
```

Repair should measure contained ggplot/recognized-gtable panels while retaining
whole-subplot movement and a separate outer-slot boundary. Nested composites may
contain several meaningful bodies; expose that limitation rather than silently
calling a slot a data panel. Verify against unequal-label/margin examples and
real saved composites. Until then, align native bodies before capture or use a
supported backend whose data anchors have been verified.

### 3. Make place_below/above enforce the requested side

[`.resolve_constraint()`](../R/transform.R) derives offsets from a signed gap and
current ordering. Moving an already-upper object below a lower one leaves it
above, despite reporting the requested gap.

```r
library(patchwork)
scene = incantation::incant(p / p, width = 180, height = 160, units = "mm")
edited = incantation::place_below(scene, 1, 2, gap = 6, unit = "mm")
incantation::bbox(edited, 1)$top < incantation::bbox(edited, 2)$bottom
# Observed: FALSE; expected: TRUE.
as.numeric(incantation::gap(edited, 1, 2))
# Observed: 17.00787 points, even though the side is wrong.
```

Repair should solve from the target's named edge and reference's named edge,
regardless of initial order or overlap. Check both vertical directions, wrong-side
starting positions, overlapping starts, and rendered rather than only reported
positions. Keep raw translation available; no new general layout engine is needed.

### 4. Match font measurement and export to the real plotting device

[`with_scene_device()`](../R/utils-grid.R) always measures on base `pdf(NULL)`;
[`ggsave_incant()`](../R/render.R) uses base `pdf()` for PDF export. In this
environment, Arial is available to native Cairo PDF but absent from the base
PostScript font database.

The saved real UC Figure 6 A produced 38 capture warnings and failed PDF export
with `invalid font type`. Its SVG and PNG exports succeeded. A synthetic ggplot
using `theme_classic(base_family = "Arial")` reproduced the PDF failure, while
native `ggsave(..., device = grDevices::cairo_pdf)` succeeded.

This is relevant because the actual project scripts measure with ragg and export
PDF with Cairo. Scene geometry obtained through substitute font metrics should
not be treated as exact for those exports. A repair should allow a consistently
bound measurement/export device and its font settings, with only the device
choices needed by existing workflows. Accept with the real font and actual
PDF/PNG/SVG outputs; do not silently change the publication font to avoid failure.

## A replay risk, separate from a reproduced contract failure

Scene manifests bind dimensions and target IDs, but do not identify the meaning
of `plot-2`. Saving an edit for `p_first / p_second` and replaying on
`p_second / p_first` succeeds and changes the other semantic panel. SVG manifests
already bind a source hash. This experiment establishes a risk, not evidence that
an earlier delivered project figure was corrupted by replay.

The immediate workflow remedy is to retain a letter/object/element mapping and
recheck it when layout structure changes. A later package improvement could bind
target identity or a suitable structure signature without preventing legitimate
fresh-data replay. A whole-object content hash is not automatically the right
solution. This has lower priority than the four observable failures above.

## Existing capabilities to use, and changes not justified by this audit

Use measurement, edge alignment, spacing constraints, explicit selections,
operation manifests and limited final-SVG edits before adding another API. Font
sizes, mark proportions, patient/gene ordering, scale domains and body dimensions
belong in native plotting. Group bodies with letters and keys before moving a
finished module when they must remain together; do not expect automatic discovery
of scientific group membership from separate cowplot text layers.

Text collisions occurred in historical refinement, but a universal automatic
text-layout engine is not justified here. Existing SVG/text inspection and actual
final-output review can address local cases. Likewise, the evidence does not
justify a new plotting package, automatic scientific interpretation, an automatic
whole-page aesthetic optimizer, or additional analysis frameworks in Incantation.

The baseline recommendations above were implemented without adding a layout
engine. Measurement now defaults to Cairo PDF, with explicit base-PDF, svglite and
ragg choices plus bound family/resolution. Recognized cowplot bodies use native
data anchors; arbitrary-grob viewport fallbacks are identified in `inspect()`.
Scene manifests check referenced semantic identities, retain full precision and
allow fresh numeric data. Explicit `plot_ids` are needed where labels/structure
cannot distinguish objects; legacy manifests remain manually verifiable.

## Actual validation of the repaired implementation

Rendered regression tests in `tests/testthat/test-rendered-alignment.R` measure
physical displacement independently, compare actual SVG point positions after
cowplot alignment and wrong-side placement, exercise Arial export, and check
reordered identities versus fresh numeric data. The full suite also covers aplot,
nested patchwork, decorations, fixed layouts, SVG edits and pixel verification.

The completed suite passed 84 tests and 333 assertions, with zero failures,
errors, warnings or skips. The package built successfully and its separate
`R CMD check --no-manual --no-tests --no-examples` completed with `Status: OK`;
tests were run in full separately, rather than claimed from that static check.

`dev/validate-real-panels.R` was run against saved actual UC Figure 6 A/C native
objects using both the source checkout and the installed R package. It exported
PDF/PNG/SVG, exercised ragg measurement, moved one C subplot by 0.7 mm, replayed
the operation and restored alignment. `dev/validate-real-panels.py` independently
checked the output pixels and PDF text:

* 54,670 pixels changed for the local edit, with zero changed pixels outside its
  target region; source objects and sibling coordinates remained unchanged.
* Replay was pixel-identical to the edit. Alignment recovery was pixel-identical
  to the original render.
* Capturing the actual C object on ragg reproduced the project's original saved
  C PNG pixel for pixel at its original physical dimensions and resolution.
* PDF text, font sizes and colors were preserved. Actual embedded fonts were
  ArialMT/Arial-BoldMT; all formats exported without warnings.
* Actual PNG and PDF previews were opened for inspection. These are package
  usability checks, not new biological analyses or acceptance of the manuscript.

For a matching saved bundle, reproduce with:

```sh
Rscript dev/validate-real-panels.R /path/to/panel_objects.rds /path/to/validation
python dev/validate-real-panels.py /path/to/validation
# Optional third argument: the original C PNG, to verify native ragg fidelity.
```

The bundle-specific integration script expects Figure 6 A/C and the documented
six C components; it is not a general figure importer. Formal research artwork
was not overwritten. Remote publication is separate from local implementation.
