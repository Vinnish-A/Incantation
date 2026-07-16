# incantation：面向 Agent 的 R 图形后布局编辑系统

> 下面是可运行的快速上手；本文其余部分是设计文档。
> 实现进度、评审与实测见 [`REVIEW.md`](REVIEW.md)，测试见 `tests/testthat/` 与 `dev/characterization.R`。

## 快速上手

```r
# install.packages("incantation")  # 或 R CMD INSTALL .
library(incantation)
library(ggplot2); library(patchwork)

p <- (ggplot(mtcars, aes(wt, mpg)) + geom_point()) /
     (ggplot(mtcars, aes(wt, hp))  + geom_point())

# 1) 绑定设备尺寸并测量（尺寸是必填项：pt 位移只在给定尺寸下成立）
scene <- incant(p, width = 8, height = 6, units = "in")
gap(scene, 2, 1)                 # 下图顶到上图底的间距，单位 pt

# 2a) 命令式：把 plot 2 往上挪 15pt（热图/兄弟图/画布都不动）
scene |> select_plot(2) |> translate(dy = 15, unit = "pt") |> draw()

# 2b) 声明式（推荐，跨设备尺寸稳定）：让 plot 2 距 plot 1 只留 6pt
fixed <- scene |> place_below(2, 1, gap = 6, unit = "pt")

# 3) 验证并保存
diagnose(fixed)                  # 越界 / 重叠 / 遮挡
detect_overlap(fixed)
ggsave_incant(fixed, "figure.pdf")   # 尺寸必须与 scene 一致，否则报错

# 4) 序列化：编辑是结构化指令，可审计、可复现
write_incantation(fixed, "edit.json")
```

参照目标用**整数**（plot 序号）或**字符串**（元素 id，如 `"plot-2/panel"`、`"inset-2"`）指定；
不提供 `plot()` / `id()` 这类会遮蔽 base 函数的定位器。支持后端：ggplot2、patchwork（含嵌套、
`inset_element`、分面子图）、aplot、cowplot。

---

## 1. 一句话定位

**Incantation 允许用户或视觉 Agent 在图形完成布局后，选中任意图形元素或整块 grob，对其进行平移、缩放、对齐和重叠调整，同时保持原始画布和布局不变。**

它解决的不是“如何重新排版”，而是更朴素的问题：

> 这部分已经基本画好了，我只想让它往上挪一点。

---

## 2. Intuition

### 2.1 当前绘图系统的问题

在 ggplot2、patchwork、cowplot 和 grid 中，图形的位置通常由以下因素共同决定：

* 数据坐标；
* scale 的范围；
* panel 的大小；
* plot margin；
* patchwork 的行高和列宽；
* gtable 的布局；
* grid viewport；
* clipping 规则。

这些机制适合生成结构严谨的图，但不适合最后阶段的视觉微调。

用户看到的是：

> `p_cluster_c` 离上面的热图太远。

绘图系统看到的却是：

> 需要修改坐标范围、panel 高度、margin、布局权重或 viewport。

这使得一个直观的视觉操作，变成了对底层布局机制的反复试探。

在当前硬编码案例中，`p_cluster_c` 本身已经正确生成，问题只出现在最终拼图中的视觉位置。

Incantation 的核心直觉是：

> **布局和绘制应该可以分成两个阶段。**

---

## 3. 核心原则：Frozen Layout

Incantation 最重要的语义是：

### 先布局，后变换

第一阶段，ggplot2、patchwork 或其他系统正常完成：

* panel 尺寸计算；
* 行高和列宽计算；
* 坐标轴和图例布局；
* grob 的原始位置计算；
* 整体画布大小计算。

第二阶段，Incantation 才对指定元素应用视觉变换。

例如：

```r
p2 <- incant(p_c) |>
  select_plot(3) |>
  translate(dy = 24, unit = "pt")
```

这一步不应改变：

* `p_c` 的总宽度和总高度；
* patchwork 的 `widths` 和 `heights`；
* 其他子图的位置；
* 原始 grob 占据的布局单元；
* 保存图片时的画布大小。

它只改变最终绘制的位置。

可以将其形式化为：

```text
final_position = layout_position + visual_transform
```

而不是：

```text
final_position = recompute_layout(modified_object)
```

这可以称为 **Frozen Layout Principle**：

> 一旦进入 Incantation 的后布局编辑阶段，布局几何保持冻结；所有操作只作用于可见图形，不反向参与布局计算。

---

## 4. Incantation 的核心抽象

Incantation 可以由四个基本对象组成。

### 4.1 Scene

一个已经完成布局的图形场景。

```r
scene <- incant(p_c)
```

它内部包含：

* 原始 ggplot、patchwork 或 gtable；
* 完成布局后的 gtable；
* 场景中的 grob 树；
* 每个元素的边界框；
* 元素来源；
* 当前应用的变换；
* 操作历史。

建议使用 S3 类：

```r
class(scene)
# [1] "inc_scene"
```

---

### 4.2 Target

被选中的图形元素。

Target 可以是：

* 整个 patchwork 子图；
* panel；
* 坐标轴；
* 图例；
* 标题；
* geom 生成的 grob；
* annotation；
* 文本；
* 任意匹配的 grob；
* 一组元素。

例如：

```r
select_plot(scene, 3)
select_panel(scene, plot = 3)
select_grob(scene, name = "panel-3")
select_role(scene, "legend")
```

更成熟时还可以支持空间选择：

```r
select_at(scene, x = 0.3, y = 0.8)
select_near(scene, target = plot(1), side = "bottom")
select_overlapping(scene)
```

---

### 4.3 Transform

应用在 Target 上的视觉变换。

MVP 首先只需要：

```r
translate()
```

后续可以增加：

```r
scale_visual()
rotate_visual()
align_visual()
distribute_visual()
set_z()
set_clip()
```

这里建议使用 `scale_visual()`，而不是直接使用 `scale()`，避免和 ggplot2 scale 混淆。

---

### 4.4 Operation log

所有操作都应是结构化和可序列化的。

例如：

```json
{
  "operation": "translate",
  "target": {
    "type": "plot",
    "index": 3
  },
  "dx": 0,
  "dy": 24,
  "unit": "pt",
  "layout": "frozen",
  "clip": "off"
}
```

这对于 Agent 很重要，因为 Agent 不应只生成难以检查的任意 R 代码，而应生成有限、明确、可验证的图形操作。

---

## 5. 在当前案例上的理想接口

你的原始代码可以保持不变：

```r
p_c <- (
  p_heat_c +
    p_enrich_c +
    p_cluster_c +
    plot_spacer()
) +
  plot_layout(
    widths = c(2, 1),
    heights = c(9, 1)
  )
```

Incantation 的调用可以设计为：

```r
p_c_adjusted <- incant(p_c) |>
  select_plot(3) |>
  translate(
    dy = 24,
    unit = "pt",
    clip = "off"
  ) |>
  render()
```

或者采用单函数形式：

```r
p_c_adjusted <- translate_grob(
  p_c,
  target = plot(3),
  dy = 24,
  unit = "pt",
  layout = "frozen",
  clip = "off"
)
```

第一种更适合交互式工作和 Agent 操作，第二种更适合普通 R 用户。

---

## 6. Agent-native 的含义

Agent-native 不只是“Agent 可以调用这个函数”。

真正适合 Agent 的接口需要具备以下性质。

### 6.1 可检查

Agent 必须能读取图形的结构，而不只是看到一张 PNG。

```r
inspect(scene)
```

可以返回：

```r
# A tibble
  id        role        plot_index  x      y      width  height
  <chr>     <chr>            <int>  <unit> <unit> <unit> <unit>
1 plot-1    plot                 1   ...
2 panel-1   panel                1   ...
3 plot-2    plot                 2   ...
4 plot-3    plot                 3   ...
5 panel-3   panel                3   ...
```

Agent 需要知道：

* 当前有哪些元素；
* 它们分别属于哪个子图；
* 每个元素在哪里；
* 哪些元素会被某次操作影响；
* 元素是否超出画布；
* 元素之间是否发生重叠。

---

### 6.2 可预测

每个操作必须有严格语义。

例如：

```r
translate(target, dy = 20)
```

应始终意味着：

* 正值向上；
* 默认使用绝对设备单位；
* 不重新计算布局；
* 不改变兄弟元素；
* 不改变画布尺寸；
* 默认保留操作历史。

不能因为目标是 ggplot、patchwork 或 gtable 而产生完全不同的行为。

---

### 6.3 可验证

每次操作后应提供机器可读的诊断结果：

```r
diagnose(scene)
```

例如：

```r
$status
# "warning"

$issues
# target partially outside canvas
# target overlaps plot-1 by 8 pt
# target is covered by another grob
```

这样 Agent 可以形成闭环：

```text
检查图形
→ 识别视觉问题
→ 选择元素
→ 应用平移
→ 重新渲染
→ 检查间距和重叠
→ 继续微调
```

---

### 6.4 可撤销

Agent 的视觉调整通常需要试错，因此必须支持：

```r
undo(scene)
redo(scene)
history(scene)
reset(scene)
```

---

### 6.5 可序列化

调整结果应保存为独立指令，而不是只能保存修改后的 grob：

```r
write_incantation(scene, "panel-c-adjustment.json")
```

之后可以重新应用：

```r
scene <- incant(p_c) |>
  apply_incantation("panel-c-adjustment.json")
```

这能够保证：

* 调整过程可复现；
* Agent 的操作可审计；
* 原始绘图代码和视觉修饰可以分开维护。

---

## 7. 最重要的语义约束

### 7.1 平移不改变布局

这是第一原则。

修改前后的以下内容必须相等：

```r
before$widths  == after$widths
before$heights == after$heights
before$layout  == after$layout
```

允许变化的只有 grob 的绘制变换。

---

### 7.2 平移不改变目标的占位

例如将 `p_cluster_c` 向上移动后，它在 patchwork 中原本的布局单元仍然保留。

因此：

* 下方不会自动增加空白；
* 上方热图不会自动移动；
* 其他面板不会重新扩张；
* 移动后的元素可以覆盖到相邻单元。

这是用户预期的“像 Photoshop 一样移动”，而不是重新排版。

---

### 7.3 clipping 必须显式

移动元素后，它可能超出原 viewport。

因此接口必须明确：

```r
translate(..., clip = "off")
translate(..., clip = "on")
translate(..., clip = "inherit")
```

建议默认值为：

```r
clip = "off"
```

因为 Incantation 的典型用途就是跨越原布局边界。

不过诊断系统应提示超出最终画布的内容。

---

### 7.4 z-order 必须明确

当一个元素进入相邻区域时，会涉及绘制顺序。

例如：

* 聚类标签应覆盖热图背景；
* 但可能不应覆盖图例；
* 某些 annotation 应位于 panel 上方；
* 某些背景 grob 应位于下方。

因此后续需要：

```r
bring_forward()
send_backward()
set_z()
```

---

### 7.5 绝对单位优先

MVP 建议优先支持：

* `"pt"`
* `"mm"`
* `"cm"`
* `"in"`

例如：

```r
translate(dy = 3, unit = "mm")
```

不建议一开始就把 `"npc"` 作为默认单位，因为相同的 `0.05 npc` 在不同 viewport 中代表不同物理距离，Agent 很难稳定控制。

后续可以明确区分：

```r
space = "device"
space = "parent"
space = "panel"
space = "data"
```

---

## 8. 选择系统是包的关键难点

当前原型使用类似：

```r
select = "-3$"
```

去匹配 gtable grob 名称。

这适合验证概念，但不适合作为长期公开 API，因为：

* grob 名称可能随 ggplot2 版本变化；
* patchwork 内部命名可能变化；
* 用户不知道 `"panel-3"` 的含义；
* 嵌套 patchwork 会让编号复杂；
* 同一个子图包含多个 grob；
* 部分 grob 位于更深层的 children 中。

正式包需要建立稳定的 selector 层。

建议支持三层选择方式。

### 高层语义选择

```r
plot(3)
panel(plot = 3)
legend(plot = 1)
title(plot = 2)
axis(plot = 1, side = "left")
```

### 中层角色选择

```r
role("panel")
role("axis-label")
role("strip")
role("guide-box")
```

### 底层 grob 选择

```r
grob_name("^panel-3$")
grob_path("layout::plot-3::panel")
```

普通用户使用高层选择，Agent 主要使用结构化选择，开发者可以使用底层选择。

---

## 9. 建议的用户 API

### 创建场景

```r
scene <- incant(p)
```

### 检查场景

```r
inspect(scene)
plot_tree(scene)
show_boxes(scene)
show_ids(scene)
```

### 选择元素

```r
scene |> select_plot(3)
scene |> select_panel(plot = 3)
scene |> select_role("legend")
scene |> select_id("panel-3")
```

### 变换

```r
translate(dx = 2, dy = 4, unit = "mm")
scale_visual(x = 1.1, y = 1)
rotate_visual(angle = 5)
```

### 对齐

```r
align_top(target, reference)
align_left(target, reference)
place_above(target, reference, gap = 2, unit = "mm")
place_below(target, reference, gap = 0)
```

### 图层顺序

```r
bring_to_front()
send_to_back()
set_z(10)
```

### 输出

```r
render(scene)
draw(scene)
ggsave_incant(scene, "figure.pdf")
```

### 操作记录

```r
history(scene)
undo(scene)
redo(scene)
reset(scene)
```

---

## 10. 与视觉 Agent 配合的理想流程

### 第一步：生成原始图形

Agent 或用户生成：

```r
p <- make_plot(data)
```

### 第二步：构建场景描述

```r
scene <- incant(p)
```

### 第三步：输出检查图

```r
render(scene, annotate = TRUE)
```

检查图可以为每个元素显示：

* ID；
* 边界框；
* 子图编号；
* 当前层级；
* anchor 点。

### 第四步：Agent 识别问题

例如 Agent 判断：

```text
plot-3 的顶部距离 plot-1 底部约为 31 pt，
理想距离约为 6 pt，
因此 plot-3 应向上移动约 25 pt。
```

### 第五步：生成结构化操作

```r
scene <- scene |>
  select_plot(3) |>
  translate(dy = 25, unit = "pt")
```

### 第六步：重新渲染并评估

```r
render(scene)
measure_gap(scene, plot(3), plot(1))
detect_overlap(scene)
```

### 第七步：保存操作

```r
write_incantation(scene, "adjustments.json")
```

---

## 11. MVP 应该做到什么

第一版不要试图解决所有图形编辑问题。

### MVP 范围

支持输入：

* ggplot；
* patchwork；
* gtable。

支持目标：

* 完整图形；
* patchwork 子图；
* 顶层 panel；
* 顶层 legend、title 和 axis。

支持操作：

* `translate()`；
* `set_clip()`；
* `set_z()`。

支持单位：

* pt；
* mm；
* cm；
* inch。

支持输出：

* grid 绘制；
* gtable；
* PNG；
* PDF；
* SVG。

支持检查：

* grob 列表；
* 元素 ID；
* 元素 bounding box；
* 操作历史；
* 超出画布警告；
* 重叠警告。

---

## 12. 推荐的包内部结构

```text
R/
├── incant.R
├── scene.R
├── inspect.R
├── selectors.R
├── transform-translate.R
├── transform-z.R
├── clipping.R
├── render.R
├── diagnostics.R
├── history.R
├── serialize.R
└── utils-grid.R
```

建议的核心 S3 类：

```r
inc_scene
inc_selection
inc_operation
inc_selector
inc_diagnostic
```

一个 `inc_scene` 可以包含：

```r
list(
  source = original_plot,
  gtable = laid_out_gtable,
  registry = element_registry,
  transforms = operation_list,
  diagnostics = diagnostic_list,
  metadata = metadata
)
```

---

## 13. 元素 registry

正式实现不应直接依赖临时的 grob 名称。

在 `incant()` 阶段，需要建立一个元素注册表：

```r
scene$registry
```

示意：

```r
# A tibble
  id          parent_id  role       plot_index grob_path
  <chr>       <chr>      <chr>           <int> <list>
1 plot-1      root       plot                1 ...
2 panel-1     plot-1     panel               1 ...
3 axis-l-1    plot-1     axis-left           1 ...
4 plot-3      root       plot                3 ...
5 panel-3     plot-3     panel               3 ...
```

每个 ID 在同一个 scene 生命周期中必须保持稳定。

如果图形重新构建，则可以基于以下信息尝试重新解析：

* plot index；
* semantic role；
* grob path；
  -原始对象来源；
  -邻接关系。

---

## 14. 视觉检查还需要补充的能力

### 14.1 Bounding box 测量

必须能够测量元素在最终设备中的真实边界：

```r
bbox(scene, plot(3))
```

返回：

```r
list(
  left = unit(...),
  right = unit(...),
  bottom = unit(...),
  top = unit(...)
)
```

---

### 14.2 间距测量

```r
gap(
  scene,
  target = plot(3),
  reference = plot(1),
  direction = "vertical"
)
```

这能让 Agent 从“看起来太远”转化为“距离是 28 pt”。

---

### 14.3 碰撞检测

```r
detect_overlap(scene)
detect_clipping(scene)
detect_outside_canvas(scene)
```

---

### 14.4 标注模式

```r
render(scene, debug = TRUE)
```

调试图中可以显示：

* 红色边界框；
* 元素 ID；
* viewport 边界；
* clipping 边界；
* anchor；
* 当前位移量。

这对 Agent 和人类开发者都非常重要。

---

## 15. 需要特别处理的技术问题

### 15.1 嵌套 viewport

一个 grob 可能已经带有自己的 viewport。

不能简单覆盖：

```r
g$vp <- new_viewport
```

否则可能破坏原始坐标系统。

更安全的方法通常是用外层 `grobTree()` 包裹：

```r
grobTree(
  original_grob,
  vp = translation_viewport
)
```

这样变换作用在外层，内部绘图逻辑保持不变。

---

### 15.2 多层 clipping

即使目标 grob 的 `clip = "off"`，它的父 viewport 仍可能裁剪。

因此 Incantation 需要：

* 定位所有祖先 viewport；
* 检查 clipping 链；
* 必要时创建独立 overlay 层；
* 或把被移动对象重新挂载到更高层容器。

这是从原型走向稳定实现时最重要的问题之一。

---

### 15.3 overlay 层

更可靠的实现可能不是直接修改原位置的 grob，而是：

1. 保留原始布局；
2. 将目标 grob 从原位置隐藏；
3. 在顶层建立 overlay viewport；
4. 按原始位置加位移重新绘制目标；
5. 保持原始布局占位不变。

这种方法更接近网页中的：

```css
position: relative;
transform: translateY(-20px);
```

它也更容易控制 z-order 和跨单元格移动。

---

### 15.4 输出设备差异

PNG、PDF 和 SVG 对文字尺寸、字体度量及单位转换可能略有差异。

因此需要明确：

* 位移使用物理单位还是像素；
* 渲染前是否需要打开实际设备；
* bounding box 在哪个设备上测量；
* 相同操作在不同设备上是否保证物理距离一致。

建议语义是：

> 使用 pt、mm 等物理单位时，保证物理位移一致，不保证像素数一致。

---

### 15.5 facet 和 geom 内部元素

选择整个 plot 相对容易。

但如果要选择单个 geom、单个 facet strip 或某个文字标签，需要递归遍历 panel 内部的 grob tree。

后续接口可以是：

```r
select_geom(plot = 1, layer = 2)
select_strip(plot = 1, facet = 3)
select_text(label = "P2RY12")
```

这不建议放入第一版 MVP。

---

## 16. 包名和语言设计

Incantation 的名字很贴合概念：

> 通过一个简短指令，让图形去它应该去的位置。

可以使用少量带有主题感的命名：

```r
incant()
inspect()
invoke()
undo()
```

但核心操作建议仍保持直白：

```r
translate()
align()
scale_visual()
rotate_visual()
```

不建议所有函数都使用魔法隐喻，否则会降低 API 的可发现性。

一个合适的平衡是：

```r
scene <- incant(p)

scene |>
  select_plot(3) |>
  translate(dy = 20, unit = "pt") |>
  render()
```

其中 `incant()` 体现品牌，操作函数保持专业、明确。

---

## 17. README 中可以使用的项目描述

> Incantation is a post-layout graphics manipulation system for R.
>
> It allows users and visual agents to select complete plots or individual graphical elements and move them after layout has been resolved. Transforms do not alter the original canvas, panel sizes, sibling positions, or patchwork layout.
>
> Incantation is designed for the final stage of figure construction, where the correct operation is often not to recompute the layout, but simply to move an element a few points.

中文版本：

> Incantation 是一个用于 R 图形后布局编辑的工具。它允许用户或视觉 Agent 在布局已经完成后，选中完整子图或单独图形元素，并对其进行平移、缩放、对齐或层级调整。
>
> 所有操作默认保持原始画布、panel 尺寸、兄弟元素位置和拼图布局不变。Incantation 面向图形制作的最后阶段：很多时候，正确的操作不是重新计算布局，而只是把某个元素移动几个点。

---

## 18. 建议的开发路线

### Phase 0：概念验证

基于当前函数完成：

```r
translate_grob(
  x,
  select,
  dx,
  dy,
  unit,
  clip
)
```

目标：

* 确认 post-layout translation 可行；
* 在当前 `p_cluster_c` 案例中稳定工作；
* 支持保存 PNG 和 PDF；
* 编写 frozen-layout 单元测试。

### Phase 1：稳定 Scene API

实现：

```r
incant()
inspect()
select_plot()
translate()
render()
history()
undo()
```

目标：

* 不再暴露正则表达式；
* 建立元素 registry；
* 提供稳定 ID；
* 支持 patchwork 子图选择。

### Phase 2：视觉诊断

实现：

```r
show_boxes()
measure_gap()
detect_overlap()
detect_clipping()
```

目标：

* 为 Agent 提供结构化视觉信息；
* 支持自动判断需要移动多少。

### Phase 3：完整 Agent 接口

实现：

```r
as_manifest()
apply_manifest()
write_incantation()
read_incantation()
```

目标：

* Agent 输出 JSON 操作；
* 操作可审计、可复现；
* 支持自动视觉调整循环。

### Phase 4：高级变换

实现：

* 缩放；
* 旋转；
* 对齐；
* 分布；
* z-order；
* 局部文字和 geom 选择；
* 与 ComplexHeatmap、cowplot 等系统适配。

---

## 19. 第一版成功标准

Incantation 第一版不需要成为完整的图形编辑器。

只要它能够稳定完成下面这件事，就已经有明确价值：

```r
incant(p_c) |>
  select_plot(3) |>
  translate(dy = 24, unit = "pt") |>
  render()
```

并保证：

* 热图不动；
* 富集图不动；
* 拼图行高不变；
* 画布大小不变；
* `p_cluster_c` 整体向上移动；
* 移动部分可以进入热图原来的布局区域；
* 操作可撤销；
* 操作可以保存和复现。

这就是 Incantation 最核心、最有辨识度的能力。

---

## 20. 当前最需要补充的内容

开发下一步应优先回答以下问题：

1. **目标选择如何稳定实现？**
   不能长期依赖 grob 名称正则。

2. **跨 viewport 的 clipping 如何统一处理？**
   这是实现“想去哪去哪”的关键。

3. **采用原地包装，还是顶层 overlay？**
   overlay 可能更可靠，但需要处理隐藏原对象和层级。

4. **如何定义统一坐标系？**
   MVP 建议使用设备物理单位。

5. **如何获得真实 bounding box？**
   部分尺寸只有在图形设备打开后才能解析。

6. **如何保证跨输出设备的一致性？**
   特别是 PDF、SVG 和不同字体环境。

7. **Agent 如何定位目标？**
   需要稳定 ID、语义角色和调试渲染。

8. **如何测试布局没有发生改变？**
   应建立 widths、heights、布局表和画布尺寸的不变量测试。

9. **如何记录和复现修改？**
   建议使用独立 JSON manifest。

10. **包名是否可用？**
    发布前需要检查 CRAN、GitHub、R-universe 和商标或命名冲突。

Incantation 的核心并不是增加另一套复杂布局系统，而是在现有布局系统之后增加一个可靠的视觉编辑层：

> **布局系统负责决定图形原本在哪里；Incantation 负责让它最终出现在用户想要的位置。**

