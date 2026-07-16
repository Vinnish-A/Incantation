# 对 GPT 版 README 的评审 + 修正后的开发计划

> 本文所有结论都在本机实测过：R 4.4.2 / ggplot2 **4.0.3** / patchwork 1.3.0 / aplot 0.2.4 / cowplot 1.1.3。
> 复现脚本见 `dev/characterization.R`，它不依赖本包，今天就能跑。

---

## 0. 一句话结论

**方向对，事实错。**

核心直觉（先布局、后变换 = `final = layout + transform`）是成立的，我把它在真实的 `example.R` 上跑通了：
`p_cluster_c` 上移 40pt，热图和富集图纹丝不动，画布尺寸不变。这个包值得做。

---

## 实现状态（0.1.0，已落地）

本文第 5 节的修正计划**已全部实现**为 `incantation` 包，Phase 0–4 齐活（ComplexHeatmap 按要求不做）：

- `R/` 12 个源文件；`inc_capture()` 适配 ggplot / patchwork（含**嵌套**、`inset_element`、**分面子图**）/ aplot / cowplot，变换、测量、诊断、序列化**零后端分支**。
- `tests/testthat/` **47 个测试 / 144 条断言，R CMD check 下 0 失败 0 跳过**；`dev/characterization.R` 另有 13 项上游事实回归。
- `R CMD check`：**0 ERROR / 0 NOTE**，仅 1 个环境性 WARNING（WSL 无 `en_US.UTF-8` locale，与包无关）。
- 真实 `example.R` 上端到端跑通：`gap=44.89pt → place_below(gap=6) → 6pt`，热图冻结、0 重叠、可存 PNG/PDF、可导出 JSON manifest。

**与本文档 API 示例的一处刻意偏差**：定位器改为**整数（plot 序号）+ 字符串（元素 id）**，
不再用 §9 里的 `plot(3)` / `id(...)`。原因：`plot`/`legend`/`title`/`axis` 会遮蔽 base/graphics
的同名函数，`R CMD check` 无法过发表级。现在写 `bbox(scene, 3)`、`gap(scene, 3, 1)`、
`select_role("title", plot = 1)`，既不撞名又更适合序列化。

但 README 的 1200 行里，**几乎每一条关于 grid/gtable/patchwork 的具体技术论断都是猜的，并且大部分是错的**。
它把最难的问题（跨设备一致性、选择器语义）说成"以后再说"，把不存在的问题（多层 clipping 链）说成"最重要的问题之一"。
按它的 Phase 0→4 走，MVP 会在 Phase 1 撞墙。

---

## 1. 实测发现：README 的五个事实错误

### 1.1 致命：patchwork 里根本没有"子图 grob"这个东西

README §4.2、§8、§9 通篇假设 `select_plot(3)` 是"选中那个叫 plot-3 的 grob"。

**实测：不存在。** patchwork 把所有子图**摊平**进一张 38×32 的大 gtable：

```
panel-3, axis-l-3, axis-b-3, title-3, xlab-b-3, background-3, ...   # 共 22 个 cell
```

没有 `plot-3`。一个"子图"是**一组共享后缀 `-3` 的 22 个 grob**，各自待在自己的 cell 里。

所以 README §8 说原型里的 `select = "-3$"` 是"适合验证概念但不适合长期 API 的 hack"——
**这个判断只对了一半**。regex 作为公开 API 确实该removed，但它编码的是一个真实的结构事实：
**subplot 是一个等价类，不是一个对象**。README 想用 `select_plot(3)` 替换它，却完全没意识到
替换物必须返回**一个 grob 集合**，以及随之而来的所有问题（下面 1.5、§2.3）。

### 1.2 致命：`select_plot(n)` 的 n 在不同后端指向不同的图

这一条直接推翻 README §6.2 的核心承诺（"不能因为目标是 ggplot、patchwork 或 gtable 而产生完全不同的行为"）。

实测同样三张图 `p1`(主), `p2`(左插), `p3`(上插)：

| gtable 后缀 | patchwork `p1+p2+p3+plot_spacer()` | aplot `p1 \|> insert_left(p2) \|> insert_top(p3)` |
|---|---|---|
| `panel-1` | **p1** | **空白 spacer** |
| `panel-2` | p2 | p2 |
| `panel-3` | p3 | p3 |
| `panel-4` | 空白 spacer | **p1（主图！）** |

aplot 的主图是 `panel-4`，而 `panel-1` 是个空格子。
**`select_plot(1)` 在 patchwork 里选中主图，在 aplot 里选中一个空 spacer，然后静默什么也不做。**

原因：aplot 的 `$layout` 是个矩阵，值是 plotlist 下标，NA 表示空位：
```
     [,1] [,2]
[1,]   NA    3
[2,]    2    1     # 主图 p1 在 (2,2)
```
gtable 后缀按位置列优先编号，与 plotlist 下标毫无关系。

**结论：`plot_index` 必须由每个 adapter 显式建立映射，不能假设 identity。**

### 1.3 `-3$` regex 会误伤 inset_element

实测 `p1 + inset_element(p2, .6,.6,1,1)` 的 cell 名字里有 `inset_2-1`。

`grep("-1$", names)` 同时匹配 `panel-1` **和** `inset_2-1`。
→ 平移子图 1 会把 inset 一起拖走。静默的、看不出来的错误。

### 1.4 README §15.2 "多层 clipping 是最重要的问题之一" —— 基本上是伪问题

README 花了大篇幅担心"即使目标 grob 的 clip=off，父 viewport 仍可能裁剪"，并据此推荐 overlay 方案（§15.3）。

**实测：扁平 patchwork gtable 里 70 个 cell，只有 7 个 clip="on"，且全部装的是 rect 或 zeroGrob。**
gtable 的 clip 是**逐 cell** 的：画第 i 个 grob 时 push 一个带 `clip=layout$clip[i]` 的 viewport。
这些 cell 之间是**兄弟关系，不是祖先关系**。所以不存在"祖先 viewport 裁我"的链。

真正需要处理的只有两个：
1. 目标自己 cell 的 clip → `gt$layout$clip[i] = "off"`，一行。
2. 设备边缘 → 这是"超出画布"诊断，不是 clipping 问题。

**唯一真实的 clip 链出现在嵌套 patchwork**（见 1.5），那里有个 `panel-nested-patchwork-2` 且 clip="on"。

所以 README §20 的第 2、3 问（"跨 viewport clipping 如何统一处理"、"原地包装还是顶层 overlay"）——
**答案是：原地包装，clip 不是问题。** overlay 是为一个不存在的问题设计的复杂方案。
我实测的原地包装版本 12 行，frozen-layout 不变式完全成立。

### 1.5 嵌套 patchwork 会打破扁平模型

`p1 | (p2 / p1)` 的顶层 gtable 里**只有 `panel-1`**。嵌套的那半边变成两个 cell：
```
panel-nested-patchwork-2   (clip = "on")
patchwork-table-2          (一个嵌套 gtable grob)
```
即 patchwork **只摊平一层**，再往里是递归结构。

所以 registry 必须是**树遍历 + 路径**，不能是"扫一遍 layout$name 抓后缀"。
README §13 的 registry 表里有个 `grob_path` 列，方向是对的，但正文从没说清它是递归的。

---

## 2. 实测发现：README 漏掉的真问题

### 2.1 最重要的：pt 位移**不是**跨设备可移植的

README §7.5 / §15.4 的立场是"优先绝对单位，保证物理位移一致"。
这话本身没错，但它保证的是**变换量**一致，而 agent 要的是**结果**一致。这两者不是一回事。

实测，两图上下堆叠、中间隔一个 `plot_spacer()`（null 行）：

| 设备尺寸 | panel-1 底 到 panel-2 顶的间距 |
|---|---|
| 10×8 in | **101.6 pt** |
| 5×4 in | **69.6 pt** |
| 10×16 in | **165.6 pt** |

agent 在 10×8 上量出 101.6pt、决定 `translate(dy = 95pt)`，然后 `ggsave(width=5, height=4)`
→ 实际只需要 63pt，**过冲 32pt，图直接飞穿上面那张图**。

反过来，`example.R` 这个具体案例里间距是 **44.89pt，与设备无关**（实测 12×10 和 8×6.7 都是 44.89）。
因为热图 panel 和 cluster panel 之间隔的全是绝对单位的行（margin、axis），中间没有 null 行。

**精确的规律**（实测，不是推测）：
- 两元素之间**只隔绝对单位行** → 间距与设备无关 → pt 位移可移植。
- 中间**跨了任何 null 行** → 间距随设备线性变化 → pt 位移不可移植。
- 元素**自身尺寸**（panel 高度是 `null`）**永远**随设备变（实测 245pt → 101pt → 533pt）。

**设计后果（README 完全没有）：**
1. **scene 必须绑定设备尺寸**：`incant(p, width = 12, height = 10, units = "in")`。
   所有 bbox / gap 都是在这个尺寸下量的。`render()` 尺寸不一致必须报错，不能静默。
2. **给 agent 的一等公民应该是约束，不是位移**：
   ```r
   scene |> place_below(plot(3), plot(1), gap = 6, unit = "pt")   # 声明式，render 时再解析 → 可移植
   scene |> translate(plot(3), dy = 38.89, unit = "pt")           # 命令式，只在该设备尺寸下正确
   ```
   README 把 `align_*` / `place_*` 放在 §9 的顺手位置、Phase 4 才实现。
   **这是搞反了：约束才是设备无关的原语，`translate` 是逃生舱。**

### 2.2 最坏的失败模式：静默 no-op

`grep("-3$", names)` 匹配不到 → `integer(0)` → for 循环空转 → 原样返回 gtable。
调用方拿到一个"成功"的返回值，图一点没动。

对 agent 这是**灾难**：它会认为操作成功，进入下一轮，然后在渲染图上看到没变，
再加大 dy，再失败……死循环烧 token。

**任何选择器解析不到目标，必须 error，不能返回原对象。** 这条 README 一个字都没提。

### 2.3 平移一个"子图"要平移 22 个 grob —— 其中包括不透明背景

subplot 是等价类（1.1），所以 `translate(plot(3))` 会把 `background-3` 一起搬走。
实测 `theme_grey` 下 `background-3` 是 `fill="white"` 的不透明 rect，跨越整个子图区域。

运气好的是：实测 patchwork 给每个子图的 background 都是 **z=0**，而内容 z 从 1 往上排
（subplot-1: z 0–21，subplot-3: z 0–63）。所以 background-3 画得很早，不会盖住 panel-1。

运气不好的是：**反向就会出事**。把子图 1 **往下**挪进子图 3 的地盘 →
子图 1 内容 z∈[1,21]，子图 3 内容 z∈[43,63] → 子图 3 画在后面 → **子图 1 被子图 3 盖住**。

`example.R` 侥幸躲过是因为作者手动写了 `plot.background = element_blank()`。
**默认主题下这就是个坑。** 需要：
- `translate(plot(k))` 默认**排除** `background-k`（或提供 `include_background = FALSE`）；
- z 冲突要有诊断。

### 2.4 现有方案已经能干一部分，README 没有交代差异化

`patchwork::inset_element()` 和 `cowplot::draw_plot()` 已经能"不影响布局地放一张图到任意位置"。
README 一句都没提，这在包设计上是硬伤——审稿人/用户第一个问题就是"这和 inset_element 有什么区别"。

诚实的差异化是：
- inset_element 要求你**改构图代码**，且位置是 npc 猜的；
- Incantation 是**事后**的、**可测量**的、**跨后端统一**的。

**真正的护城河不是"平移"，是"测量 + 诊断"**——`bbox()` / `gap()` / `detect_overlap()`。
平移谁都会写（我 12 行就写完了）；能告诉 agent "现在是 44.89pt，你想要 6pt，所以 dy=38.89" 的，没有。

**所以 README 的优先级是反的**：它把 translate 放 MVP、诊断放 Phase 2。
对 agent-native 来说，**inspect/measure 才是产品本体**，translate 是薄薄一层。
没有测量的 translate = 用户今天手工试 `dy=24` 再看一眼的自动化版本，零价值增量。

---

## 3. README 说对了的部分（保留）

这些是真的好，别丢：

1. **Frozen Layout 原则**（§3）——实测成立。原地包 viewport 后 `widths`/`heights`/`layout` 完全恒等。
2. **`scale_visual()` 而不是 `scale()`**（§4.3）——避开 ggplot2 `scale_*` 命名冲突，正确。
3. **操作必须结构化可序列化**（§4.4）——agent 应该产出受限指令集而不是任意 R 代码。这是对的。
4. **clip 必须显式**（§7.3）——虽然理由错了（不是多层链的问题），但结论对：默认 `clip="off"`。
5. **`incant()` 体现品牌、操作函数保持直白**（§16）——克制得很好。
6. **不要一开始就上 npc**（§7.5）——对，但理由要换成 §2.1 的真实理由。
7. **§20 的第 8 问"如何测试布局没有发生改变"**——这是全文最有价值的一句话，直接变成本包的核心不变式测试。

---

## 4. aplot / cowplot / ComplexHeatmap 适配设计

README 只在 Phase 4 给了一行"与 ComplexHeatmap、cowplot 等系统适配"。这是本次要补的重点。

### 4.1 关键洞察：变换是统一的，**定位**不是

实测下来，所有后端的**变换动作完全相同**：

```r
g = grobTree(g, vp = viewport(y = unit(0.5,"npc") + unit(dy,"pt"),
                              height = unit(1,"npc"), clip = "off"))
```

不同的只有三件事：
1. 怎么**找到**那一组 grob（path）；
2. 怎么**关掉**它容器的 clip；
3. 用户说的 `plot(k)` 里的 **k 怎么映射**到后端内部编号。

所以 adapter 层只需要实现一个 `inc_capture()`，产出统一的 `(gtable, registry)`，
后面 translate / bbox / diagnose 全部后端无关。**这是这个包能成立的结构性理由。**

### 4.2 各后端实测结构

| 后端 | 捕获方式 | 结构 | 子图定位 | plot_index 映射 | 难度 |
|---|---|---|---|---|---|
| **ggplot** | `ggplotGrob(p)` | 扁平 gtable，名字**无后缀**（`panel`, `axis-l`） | cell name | 恒为 1 | 易 |
| **patchwork** | `patchworkGrob(p)` | 扁平 gtable，后缀 `-k`；嵌套→`patchwork-table-k` 递归；inset→`inset_j-k` | 后缀等价类 | **identity**（实测 panel-1=p1） | 中 |
| **aplot** | `ggplotify::as.grob(ap)` | 与 patchwork **同构** | 后缀等价类 | **非 identity**，需查 `ap$layout` 矩阵 | 中 |
| **cowplot** | `ggplotGrob(cg)` | **只有一个 `panel` cell**，子图是 panel gTree 的 children（`GeomDrawGrob 2/3/4`） | gTree child index | plot_grid 顺序 | 中 |
| **ComplexHeatmap** | `grid.grabExpr(draw(ht))` | 纯 gTree + 具名 viewport，位置烘焙进 vp | viewport name | 无索引概念 | 难，**MVP 不做** |

**cowplot 是唯一结构性不同的**：它没有 gtable cell 概念，`plot_grid` 用 `ggdraw()+draw_grob()`
把所有子图塞进**同一个 panel** 里，靠 viewport 的 npc 定位。实测：

```
cowplot gtable:  只有 1 个 panel cell
panel$children:  grill, GeomDrawGrob 2, GeomDrawGrob 3, GeomDrawGrob 4, panel.border
```

所以 cowplot 的 registry 项 `path = c(<panel cell idx>, <child idx>)`，`container = "gtree-child"`；
patchwork/aplot 的 `path = c(<cell idx>)`，`container = "gtable-cell"`。
`unclip()` 对前者是改 `childrenvp` / 包一层 clip=off 的 vp，对后者是 `layout$clip[i] = "off"`。

### 4.3 aplot 的 index 映射算法（不能靠猜）

不要假设后缀顺序规则。**用位置匹配反推**：

```r
# aplot$layout[r, c] 的值 = plotlist 下标；NA = 空位
# gtable 的 panel-k 有 (t, l)；把 (t,l) 按大小排序还原成 (r, c)
map_aplot_index = function(ap, gt) {
  cells = gt$layout |> subset(grepl("^panel-\\d+$", name))
  rows  = sort(unique(cells$t)); cols = sort(unique(cells$l))
  cells$r = match(cells$t, rows); cells$c = match(cells$l, cols)
  cells$plot_index = mapply(\(r, c) ap$layout[r, c], cells$r, cells$c)
  cells   # suffix <-> plot_index，NA 的就是 spacer，选中要报错
}
```

**这个映射必须有测试**（见 `test-backend-aplot.R`），因为它是 aplot 版本升级最容易悄悄崩的地方。

### 4.4 建议的 adapter 契约

```r
# 每个后端只实现这一个 S3 方法
inc_capture = function(x, ...) UseMethod("inc_capture")
# 返回: list(root = <gtable|gTree>, registry = <data.frame>, backend = <chr>)

# registry 列（稳定契约）
#   id          chr   "plot-3" / "plot-3/panel" / "plot-3/axis-l"
#   role        chr   "plot" | "panel" | "axis-l" | "title" | "legend" | "background"
#   plot_index  int   用户视角的编号（adapter 负责映射）
#   path        list  从 root 到该 grob 的整数路径，支持递归嵌套
#   container   chr   "gtable-cell" | "gtree-child"
#   is_empty    lgl   zeroGrob / spacer → 选中时报错
```

变换、测量、诊断、序列化全部只依赖 `registry`，**零后端分支**。

---

## 5. 修正后的开发计划

README 的 Phase 0→4 里，Phase 2（诊断）应该整体前移到 Phase 0，因为它是产品本体。

### Phase 0 — 测量（README 里是 Phase 2，实际是地基）

没有测量就没有 agent 闭环。**先做这个。**

```r
scene = incant(p_c, width = 12, height = 10, units = "in")   # 设备尺寸是构造参数，不是可选项
inspect(scene)                       # registry + 实测 bbox 的 data.frame
bbox(scene, plot(3))                 # 设备 pt 坐标
gap(scene, plot(3), plot(1), "vertical")
```

实现要点（实测可行）：
- bbox 用 `grid::deviceLoc()`，不要用 `seekViewport`——
  **实测 gtable 画完后 `grid.ls(viewports=TRUE)` 只有 `ROOT`/`layout`/`1`，没有具名 cell viewport。**
  必须 `grid.force()` 之后才会出现 `panel-1.11-9-11-9` 这种名字（格式 `<name>.<t>-<r>-<b>-<l>`）。
  但更稳的做法是**完全绕开 viewport 查找**：直接 push `grid.layout(widths=gt$widths, heights=gt$heights)`
  再 push 目标 cell，然后 `deviceLoc(unit(0,"npc"), unit(0,"npc"))`。实测这条路干净、准确、可复现。
- 每个 bbox 必须标注它是在哪个设备尺寸下量的。

**验收**：在 `example.R` 上，`gap(scene, plot(3), plot(1))` 返回 **44.89 pt**。

### Phase 1 — 选择器 + registry

```r
select_plot(scene, 3)     # 解析成 22 个 grob 的等价类
select_panel(scene, 3)
select_role(scene, "legend")
```
- 树遍历建 registry，支持嵌套 patchwork（`patchwork-table-k` 递归）。
- **解析为空必须 error**（§2.2）。
- 每个 adapter 建自己的 `plot_index` 映射（§4.3）。
- **不暴露 regex。**

### Phase 2 — 变换

```r
translate(sel, dx = 0, dy = 24, unit = "pt")
place_below(sel, ref, gap = 6, unit = "pt")     # 一等公民，不是 Phase 4
align_top(sel, ref)
```
- 原地 `grobTree(g, vp=...)` 包裹 + `layout$clip[i] = "off"`。**不做 overlay。**
- `translate(plot(k))` 默认排除 `background-k`。
- `place_*` 在 render 时按实际设备重新解析 → 设备无关。

### Phase 3 — 诊断

```r
diagnose(scene)          # 越界 / 重叠 / z 遮挡
detect_overlap(scene)
render(scene, debug = TRUE)   # 画 bbox + id + 位移量
```

### Phase 4 — 序列化 + 后端扩展

```r
write_incantation(scene, "adj.json"); apply_incantation(scene, "adj.json")
```
cowplot adapter、ComplexHeatmap adapter、`scale_visual()`/`rotate_visual()` 放这里。

### 明确不做（MVP）

- overlay 层（为伪问题设计的）
- `undo`/`redo`（scene 是不可变值，`scene0` 就是 undo；函数式优先，别引入可变历史栈）
- npc / data 空间单位
- geom / facet strip / 单个文字的选择

---

## 6. 我提供的测试用例

见 `tests/testthat/`。每个文件顶部都注明**它对应上面哪条实测发现**。

| 文件 | 覆盖 | 对应发现 |
|---|---|---|
| `test-invariant-frozen-layout.R` | 布局冻结；**兄弟元素渲染位置逐一 bbox 比对**（比比对 layout 表强得多） | §3.1 |
| `test-selector-silent-noop.R` | 选不中必须 error，不能静默返回原图 | §2.2 ⚠️最重要 |
| `test-device-portability.R` | 绝对行→可移植 / 跨 null 行→不可移植且必须被检测 | §2.1 ⚠️最重要 |
| `test-backend-aplot.R` | aplot 主图是 panel-4、panel-1 是空位 | §1.2 |
| `test-backend-patchwork-nested.R` | 嵌套 patchwork 递归；inset regex 碰撞 | §1.3 §1.5 |
| `test-backend-cowplot.R` | 单 panel + gTree children 结构 | §4.2 |
| `test-zorder-occlusion.R` | 往下挪被高 z 子图盖住；不透明 background | §2.3 |
| `test-measure-gap.R` | `example.R` 上 gap == 44.89pt | Phase 0 验收 |

另有 `dev/characterization.R`：**不依赖本包**，直接对 patchwork/aplot/cowplot 跑断言，
把上面所有"实测发现"固化成可执行的回归测试。上游一升级就会红——
这比在我们自己包里测有用得多，因为这些事实**是我们的依赖，不是我们的代码**。
