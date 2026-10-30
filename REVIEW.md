# Review of the GPT README and revised development plan

> All conclusions here were tested locally: R 4.4.2 / ggplot2 **4.0.3** / patchwork 1.3.0 / aplot 0.2.4 / cowplot 1.1.3.
> Reproduction script: dev/characterization.R; it does not depend on this package and can run immediately.

---

## 0. Verdict

**The direction is right; the facts are wrong.**

The core intuition—layout first, transform afterward, final = layout + transform—holds. I verified it with the actual example.R:
p_cluster_c moves upward 40 pt while the heatmap, enrichment plot and canvas dimensions stay unchanged. This package is worth building.

---

## Implementation status: 0.1.0, completed

The revised plan in section 5 is **fully implemented** in incantation, covering Phases 0–4 (excluding ComplexHeatmap as requested):

- 12 source files in R/; inc_capture() supports ggplot / patchwork including nesting, inset_element and faceted subplots / aplot / cowplot. Transformation, measurement, diagnostics and serialization have zero backend branches.
- tests/testthat/: **47 tests / 144 assertions, zero failures and skips under R CMD check**; dev/characterization.R adds 13 upstream-fact regression checks.
- R CMD check: **0 ERROR / 0 NOTE**, with one environmental WARNING for missing en_US.UTF-8 locale in WSL, unrelated to the package.
- End-to-end actual example.R: gap=44.89pt → place_below(gap=6) → 6pt; frozen heatmap, zero overlaps, PNG/PDF export and JSON manifests.

**One deliberate deviation from these API examples**: locators now use integers (plot indices) and strings (element IDs),
not plot(3) / id(...) from §9. plot/legend/title/axis would shadow base/graphics
functions and prevent publication-quality R CMD check. Use bbox(scene, 3), gap(scene, 3, 1),
and select_role("title", plot = 1), avoiding collisions and improving serialization.

Yet among the README’s 1,200 lines, **almost every specific technical claim about grid/gtable/patchwork was guessed, and most were wrong**.
It deferred the hardest problems—device consistency and selector semantics—while calling nonexistent multilayer clipping chains a major issue.
Following its Phases 0–4 would stall the MVP in Phase 1.

---

## 1. Empirical findings: five factual errors

### 1.1 Critical: patchwork has no subplot grob

README §§4.2, 8 and 9 assume select_plot(3) selects a grob named plot-3.

**Observed: it does not exist.** patchwork flattens all subplots into one 38×32 gtable:

```
panel-3, axis-l-3, axis-b-3, title-3, xlab-b-3, background-3, ...   # 22 cells total
```

There is no plot-3. A subplot is **22 grobs sharing suffix -3**, each in its own cell.

README §8 therefore calls the prototype select = "-3$" a hack suitable for proof of concept but not a lasting API.
**Only half right.** Public regex should go, but it encodes a real structural fact:
a subplot is an equivalence class, not one object. Replacing it with select_plot(3) requires returning
a grob collection, with the implications in §1.5 and §2.3 that the README overlooked.

### 1.2 Critical: n in select_plot(n) means different plots across backends

This directly contradicts README §6.2’s promise that behavior must not fundamentally differ among ggplot, patchwork and gtable.

Observed with the same p1 (main), p2 (left inset), p3 (top inset):

| gtable suffix | patchwork `p1+p2+p3+plot_spacer()` | aplot `p1 \|> insert_left(p2) \|> insert_top(p3)` |
|---|---|---|
| panel-1 | **p1** | **empty spacer** |
| panel-2 | p2 | p2 |
| panel-3 | p3 | p3 |
| panel-4 | empty spacer | **p1 (main plot!)** |

aplot’s main plot is panel-4, while panel-1 is empty.
**select_plot(1) selects the main plot in patchwork but an empty spacer in aplot, silently doing nothing.**

aplot’s $layout matrix contains plotlist indices, with NA for empty positions:
```
     [,1] [,2]
[1,]   NA    3
[2,]    2    1     # Main p1 at (2,2)
```
gtable suffixes follow column-major positions, unrelated to plotlist indices.

**Each adapter must explicitly map plot_index; identity cannot be assumed.**

### 1.3 Suffix regex accidentally includes inset_element

Observed cell names for p1 + inset_element(p2, .6,.6,1,1) include inset_2-1.

grep("-1$", names) matches both panel-1 and inset_2-1.
Translating subplot 1 therefore drags its inset too: a silent, hard-to-see error.

### 1.4 README §15.2’s multilayer clipping concern is mostly a false problem

The README spends considerable space worrying that parent viewports clip even with target clip=off, recommending overlays in §15.3.

**Observed: among 70 flat patchwork cells, only 7 have clip="on", all containing rect or zeroGrob.**
gtable clipping is per cell: drawing grob i pushes a viewport with clip=layout$clip[i].
Cells are siblings, not ancestors, so there is no ancestral clipping chain.

Only two real issues need handling:
1. Target cell clipping: gt$layout$clip[i] = "off", one line.
2. Device boundaries: canvas-overflow diagnostics, not clipping.

**The real clip chain occurs only in nested patchwork** (§1.5), with panel-nested-patchwork-2 and clip="on".

For README §20 questions 2/3—unified cross-viewport clipping and in-place wrapping versus overlays—
**use in-place wrapping; clipping is not the obstacle.** Overlay adds complexity for a nonexistent problem.
My tested in-place version uses 12 lines and preserves frozen-layout invariants fully.

### 1.5 Nested patchwork breaks the flat model

The top-level gtable for p1 | (p2 / p1) contains only panel-1. The nested half becomes two cells:
```
panel-nested-patchwork-2   (clip = "on")
patchwork-table-2          (a nested gtable grob)
```
patchwork flattens only one level; deeper structure is recursive.

The registry therefore needs tree traversal and paths, not a single suffix scan over layout$name.
README §13’s grob_path column points in the right direction but never explains recursion.

---

## 2. Empirical findings: real problems the README missed

### 2.1 Most important: pt offsets are not portable across devices

README §§7.5/15.4 favor absolute units to preserve physical displacement.
That preserves the transformation amount, whereas agents need consistent results; those are different.

Observed with two vertically stacked plots separated by plot_spacer() (a null row):

| Device dimensions | Gap from panel-1 bottom to panel-2 top |
|---|---|
| 10×8 in | **101.6 pt** |
| 5×4 in | **69.6 pt** |
| 10×16 in | **165.6 pt** |

An agent measures 101.6 pt at 10×8, chooses translate(dy = 95pt), then saves at width=5, height=4.
Only 63 pt is actually needed: **32 pt overshoot sends the plot through the one above.**

Conversely, example.R has a device-independent 44.89 pt gap, observed at both 12×10 and 8×6.7.
Only absolute-unit margin/axis rows separate heatmap and cluster panels; no null rows intervene.

**Observed rules, not guesses:**
- Only absolute-unit rows between elements → device-independent gaps → portable pt offsets.
- Any intervening null row → gaps vary linearly with device size → nonportable pt offsets.
- Element dimensions themselves (null panel height) always change with device size: observed 245 → 101 → 533 pt.

**Design consequences absent from the README:**
1. Bind scenes to device dimensions: incant(p, width = 12, height = 10, units = "in").
   Measure all bboxes/gaps there; render must fail on different dimensions rather than silently proceed.
2. Constraints, not displacements, should be first-class agent operations:
   ```r
   scene |> place_below(plot(3), plot(1), gap = 6, unit = "pt")   # Declarative; resolve at render time; portable
   scene |> translate(plot(3), dy = 38.89, unit = "pt")           # Imperative; correct only at this device size

```
   The README treats align_*/place_* as incidental §9 helpers delayed until Phase 4.
   **This is backward: constraints are device-independent primitives; translate is the escape hatch.**

### 2.2 Worst failure mode: silent no-op

No grep("-3$", names) match → integer(0) → empty loop → unchanged gtable.
The caller receives a successful return while nothing moved.

For agents this is disastrous: assume success, inspect the unchanged render,
increase dy, fail again, and waste tokens indefinitely.

**Every unresolved selector must error, never return the original object.** The README never mentions this.

### 2.3 Moving a subplot moves 22 grobs, including opaque backgrounds

Since a subplot is an equivalence class (§1.1), translate(plot(3)) moves background-3 too.
Under theme_grey it is an opaque white rect spanning the subplot.

Fortunately, observed patchwork backgrounds all have z=0, with contents starting at 1
(subplot-1: z 0–21; subplot-3: z 0–63). background-3 draws early and does not cover panel-1.

The reverse fails: move subplot 1 downward into subplot 3;
subplot 1 contents have z∈[1,21], subplot 3 z∈[43,63], so subplot 3 draws later and covers subplot 1.

example.R avoids this only because the author explicitly sets plot.background = element_blank().
Default themes expose the trap. Required behavior:
- Exclude background-k by default in translate(plot(k)), or provide include_background = FALSE;
- Diagnose z-order conflicts.

### 2.4 Existing tools cover part of this; the README fails to explain differentiation

patchwork::inset_element() and cowplot::draw_plot() already place plots anywhere without affecting layout.
Ignoring them undermines package design: users/reviewers will first ask how this differs from inset_element.

The honest distinction:
- inset_element requires changing composition code and guessing npc positions;
- Incantation works afterward, is measurable and is consistent across backends.

The real advantage is measurement plus diagnostics, not translation: bbox(), gap(), detect_overlap().
Translation takes 12 lines; existing tools do not tell an agent “the gap is 44.89 pt, target 6 pt, so dy=38.89”.

The README reverses priorities by putting translate in MVP and diagnostics in Phase 2.
For agent-native workflows, inspect/measure is the product and translation a thin layer.
Without measurement, translate merely automates manually trying dy=24 and looking again, adding no value.

---

## 3. What the README gets right: retain these

These are valuable and should remain:

1. **Frozen Layout** (§3): verified. In-place viewport wrapping leaves widths/heights/layout identical.
2. **scale_visual() rather than scale()** (§4.3): correctly avoids ggplot2 scale_* naming collisions.
3. **Structured serializable operations** (§4.4): agents should emit constrained instructions rather than arbitrary R code.
4. **Explicit clipping** (§7.3): the multilayer-chain reasoning is wrong, but default clip="off" is right.
5. **Branding in incant(), plain operation names** (§16): appropriately restrained.
6. **Do not begin with npc** (§7.5): correct, with the actual rationale in §2.1.
7. **§20 question 8: how to test unchanged layout**: the document’s most valuable line, directly becoming the core invariant test.

---

## 4. Adapter design: aplot, cowplot and ComplexHeatmap

The README gives backend integration one line in Phase 4. This is a key gap to fill.

### 4.1 Core insight: transformations are shared; locating elements is not

Observed transformation operations are identical across backends:

```r
g = grobTree(g, vp = viewport(y = unit(0.5,"npc") + unit(dy,"pt"),
                              height = unit(1,"npc"), clip = "off"))
```

Only three things differ:
1. Finding the grob collection by path;
2. Disabling container clipping;
3. Mapping user-facing plot(k) indices to internal backend indices.

The adapter layer only needs inc_capture(), returning uniform gtable/registry objects;
translation, bboxes and diagnostics then remain backend-independent. This is the structural basis of the package.

### 4.2 Observed backend structures

| Backend | Capture | Structure | Subplot lookup | plot_index mapping | Difficulty |
|---|---|---|---|---|---|
| ggplot | ggplotGrob(p) | Flat gtable, unsuffixed panel/axis-l names | Cell name | Always 1 | Easy |
| patchwork | patchworkGrob(p) | Flat -k suffixes; recursive patchwork-table-k nesting; inset_j-k insets | Suffix equivalence class | Identity; observed panel-1=p1 | Medium |
| aplot | ggplotify::as.grob(ap) | Isomorphic to patchwork | Suffix equivalence class | Nonidentity; inspect ap$layout | Medium |
| cowplot | ggplotGrob(cg) | One panel cell; subplots are GeomDrawGrob 2/3/4 children | gTree child index | plot_grid order | Medium |
| ComplexHeatmap | grid.grabExpr(draw(ht)) | Pure gTree and named viewports with baked positions | Viewport name | No index concept | Hard; outside MVP |

cowplot is structurally distinct: without subplot gtable cells, plot_grid uses ggdraw()+draw_grob()
to put all subplots in one panel, positioned by viewport npc. Observed:

```
cowplot gtable:  only 1 panel cell
panel$children:  grill, GeomDrawGrob 2, GeomDrawGrob 3, GeomDrawGrob 4, panel.border
```

cowplot registry paths are c(<panel cell idx>, <child idx>), container="gtree-child";
patchwork/aplot use c(<cell idx>), container="gtable-cell".
unclip changes childrenvp/wraps a clip=off viewport for the former, and layout$clip[i]="off" for the latter.

### 4.3 aplot index mapping: do not guess

Do not assume suffix order; derive it by matching positions:

```r
# aplot$layout[r, c] contains plotlist indices; NA denotes an empty position
# gtable panel-k has (t, l); rank these positions to recover (r, c)
map_aplot_index = function(ap, gt) {
  cells = gt$layout |> subset(grepl("^panel-\\d+$", name))
  rows  = sort(unique(cells$t)); cols = sort(unique(cells$l))
  cells$r = match(cells$t, rows); cells$c = match(cells$l, cols)
  cells$plot_index = mapply(\(r, c) ap$layout[r, c], cells$r, cells$c)
  cells   # suffix <-> plot_index; NA means spacer and selection must fail
}
```

Test this mapping (test-backend-aplot.R): it is especially vulnerable to silent breakage after aplot upgrades.

### 4.4 Proposed adapter contract

```r
# Each backend implements only this S3 method
inc_capture = function(x, ...) UseMethod("inc_capture")
# Returns: list(root = <gtable|gTree>, registry = <data.frame>, backend = <chr>)

# Registry columns: stable contract
#   id          chr   "plot-3" / "plot-3/panel" / "plot-3/axis-l"
#   role        chr   "plot" | "panel" | "axis-l" | "title" | "legend" | "background"
#   plot_index  int   User-facing index mapped by the adapter
#   path        list  Integer path from root to grob, supporting recursive nesting
#   container   chr   "gtable-cell" | "gtree-child"
#   is_empty    lgl   zeroGrob / spacer; selection raises an error
```

Transformation, measurement, diagnostics and serialization depend only on registry, with zero backend branches.

---

## 5. Revised development plan

Move the README’s Phase 2 diagnostics into Phase 0: they are the product foundation.

### Phase 0 — Measurement: the foundation, formerly Phase 2

No measurement means no agent feedback loop. Build this first.

```r
scene = incant(p_c, width = 12, height = 10, units = "in")   # Device dimensions are required constructor arguments
inspect(scene)                       # Registry and measured bboxes as a data.frame
bbox(scene, plot(3))                 # Device coordinates in pt
gap(scene, plot(3), plot(1), "vertical")
```

Implementation points verified experimentally:
- Use grid::deviceLoc() for bboxes, not seekViewport.
  After drawing gtable, grid.ls(viewports=TRUE) shows only ROOT/layout/1, no named cell viewports.
  Only grid.force() exposes names such as panel-1.11-9-11-9, formatted <name>.<t>-<r>-<b>-<l>.
  More robustly, bypass viewport lookup entirely: push grid.layout(widths=gt$widths, heights=gt$heights),
  then the target cell and deviceLoc(unit(0,"npc"), unit(0,"npc")). This proved clean, accurate and reproducible.
- Every bbox records the device dimensions used for measurement.

Acceptance: gap(scene, plot(3), plot(1)) returns 44.89 pt for example.R.

### Phase 1 — Selectors and registry

```r
select_plot(scene, 3)     # Resolve to an equivalence class of 22 grobs
select_panel(scene, 3)
select_role(scene, "legend")
```
- Build registry through tree traversal, supporting recursive patchwork-table-k nesting.
- Empty resolution must error (§2.2).
- Each adapter establishes its own plot_index mapping (§4.3).
- Do not expose regex.

### Phase 2 — Transformations

```r
translate(sel, dx = 0, dy = 24, unit = "pt")
place_below(sel, ref, gap = 6, unit = "pt")     # First-class, not deferred to Phase 4
align_top(sel, ref)
```
- In-place grobTree(g, vp=...) wrapping plus layout$clip[i]="off"; no overlay.
- translate(plot(k)) excludes background-k by default.
- place_* resolves against actual device geometry during rendering, enabling device independence.

### Phase 3 — Diagnostics

```r
diagnose(scene)          # Overflow / overlap / z-order occlusion
detect_overlap(scene)
render(scene, debug = TRUE)   # Draw bbox + ID + displacement
```

### Phase 4 — Serialization and backend expansion

```r
write_incantation(scene, "adj.json"); apply_incantation(scene, "adj.json")
```
cowplot and ComplexHeatmap adapters, scale_visual()/rotate_visual() belong here.

### Explicitly outside MVP

- Overlay layers for a false problem;
- undo/redo: scenes are immutable values, so scene0 is undo; favor functional style over mutable history stacks;
- npc/data-space units;
- Selecting geoms, facet strips or individual text elements.

---

## 6. Supplied test cases

See tests/testthat/; each file states which empirical finding it covers.

| File | Coverage | Finding |
|---|---|---|
| test-invariant-frozen-layout.R | Frozen layout; individual sibling-rendered bbox comparisons, stronger than layout-table equality | §3.1 |
| test-selector-silent-noop.R | Unresolved selections error instead of silently returning originals | §2.2, critical |
| test-device-portability.R | Absolute rows are portable; null-row crossings are not and must be detected | §2.1, critical |
| test-backend-aplot.R | Main plot is panel-4; panel-1 is empty | §1.2 |
| test-backend-patchwork-nested.R | Nested recursion and inset regex collisions | §§1.3, 1.5 |
| test-backend-cowplot.R | Single panel with gTree children | §4.2 |
| test-zorder-occlusion.R | Downward moves occluded by higher-z subplots; opaque backgrounds | §2.3 |
| test-measure-gap.R | example.R gap == 44.89 pt | Phase 0 acceptance |

dev/characterization.R independently asserts patchwork/aplot/cowplot behavior without depending on this package,
turning empirical findings into executable regressions that reveal upstream changes.
These checks are especially valuable because the facts belong to dependencies, not our own code.
