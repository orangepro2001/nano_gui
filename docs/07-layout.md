# 07 布局

## 1. 范围

定义节点的尺寸策略、两遍求解算法（测量、排布）、整数像素规则、权重分配、专用容器（Scroll、Splitter、Table、Form、Anchor）的布局语义、增量复用、自定义容器接口、DPI 与窗口最小尺寸。依据 ADR 0007。

本文只定义**布局语义**。Scroll、Splitter、Table 等作为控件的交互行为（拖动、键盘、绘制）由 10 的控件规范定义；命中测试与裁剪的使用方式见 08；增量复用与帧阶段的关系见 06。

## 2. 术语

| 术语 | 定义 |
|---|---|
| 主轴 / 交叉轴 | Row 的主轴为水平、交叉轴为垂直；Column 相反。Stack 及其他非线性父容器中，子项的"主轴"指水平、"交叉轴"指垂直。子项的 `main`/`cross` 总是相对**其父容器**而言。 |
| 在流 / 出流 | 在流子项参与父容器的尺寸计算与 gap；出流子项（仅 Anchor）不参与。 |
| 限制 (`Limit`) | 测量的输入：宽、高两个整数 ppx 上限，及每个轴上的"确定"标志。 |
| 确定限制 | 父容器保证子项最终在该轴上恰好取这个尺寸（子项为 fixed、grow 的份额、fill 或收缩后的值）。非确定限制只是上界。 |
| 期望尺寸 | 测量的输出：节点在给定限制下希望取得的整数 ppx 尺寸，已按其 min/max 夹紧。 |
| 基础尺寸 | 分配前子项在主轴上的尺寸：fixed 取其值，fit/fit_shrink 取期望尺寸，grow 取 0。 |
| 最大余数法 | 把整数总量按权重分配：各份取下整，余量逐 1 ppx 发给小数部分最大者（并列取序号小者）。 |
| 窗格 | Splitter 的两个子项之一。 |
| 内容固有尺寸 | 叶节点自带的、由控件在构建时用文字度量等得出的 lpx 尺寸（`Content.size`）。 |

## 3. 规范条款

### 3.1 总则

**REQ-LAYOUT-001**　布局**必须**是两遍求解：自底向上的**测量**（输入限制，输出期望尺寸）与自顶向下的**排布**（输入最终矩形，输出各子项矩形）。测量与排布函数**不得**读取兄弟节点的排布结果，**不得**多轮迭代求同一节点的尺寸。除 REQ-LAYOUT-027 的 height-for-width 回调与自定义容器（REQ-LAYOUT-050）外，求解过程中**不得**调用控件代码。

**REQ-LAYOUT-002**　布局**必须**在物理像素整数上进行。进入求解前，所有 lpx 量按下列规则换算为 ppx，之后求解中不再出现浮点：
- 令牌（`theme.px`，REQ-THEME-013）与 `fixed(v)`、`main_min/max`、`cross_min/max`、`padding`、`gap`：取 `round(v × scale)`（0.5 向上），**正值不小于 1**；显式的 0 保持 0。
- `Content.size`（内容固有尺寸）：取 `ceil(v × scale − 0.001)`，以免文字度量的浮点误差把 100.0000001 进位成 101。
- 无上界（`inf`）换算为常量 `layout.unbounded`（1 << 28 ppx），任何参与加法的量都不得使其溢出 `i32`。

**REQ-LAYOUT-003**　排布结果**必须**是整数 ppx 矩形，坐标相对**父节点的原点**（父节点矩形左上角，不含父节点自身 padding 之外的偏移），根节点的原点为其所在平台窗口客户区的左上角。同时以 lpx 报告：`ui.lastRect(id)` 返回 `ppx / scale`（06，REQ-FRAME-029），`ui.lastRectPx(id)` 返回原始整数。节点的绝对矩形 = 逐级累加祖先偏移（滚动偏移已含在内容子项的位置中）。

**REQ-LAYOUT-004**　测量的限制 `Limit` 是一对 `(w, h)` 整数 ppx 上界，加上每轴的"确定"标志。父容器在下列情形给出**确定**限制：子项为 `fixed`；`grow` 子项在分配后得到的份额；`fit_shrink` 子项被收缩后的值；`fill` 且容器该轴自身为确定限制；Scroll 内容在非滚动轴上；Splitter 窗格；Table/Form 的单元格列宽。其余情形（fit、非确定容器内的 fill）只给上界。子项**不得**依赖限制是否确定来改变自身语义，限制是否确定只影响容器内部是否对 `grow` 子项做分配（REQ-LAYOUT-020 第 3 步）。

**REQ-LAYOUT-005**　可见性只有两种表达：**不声明即不存在**（构建函数不调用该控件，节点不进入树，不占空间、不参与 gap、不可聚焦）；`NodeFlags.hidden`（节点存在并**占位**，参与布局与 gap，但不绘制、不可命中、不可聚焦，其子树同样）。布局不提供 `display: none` 之外的第三种可见性。

**REQ-LAYOUT-006**　以下能力**不得**提供，也不得以隐藏参数形式出现：流式换行容器（wrap）、百分比尺寸、margin（含折叠）、z-index、绝对定位的任意嵌套（Anchor 是唯一的出流容器，见 REQ-LAYOUT-042）、通用基线对齐、基于内容的列自动均衡、按子项内容的 flex-basis。

**REQ-LAYOUT-007**　上条所列需求的规定替代做法：margin 用父容器的 `padding` 或在子项间插入 `ui.spacer`；wrap 用溢出菜单（工具栏）或 Scroll；百分比用 `grow` 权重（如 1:3）；同一行内文字基线一致由 REQ-THEME-017 保证，不由布局保证；真二维对齐用 Table 或 Form；其余需求由应用自写自定义容器（REQ-LAYOUT-050）。

### 3.2 布局参数

**REQ-LAYOUT-008**　每个节点的 `NodeSpec.layout` 是一个 `layout.Params`（见第 4 节），字段及默认值如下，默认值为规范性内容：

| 字段 | 含义 | 默认 |
|---|---|---|
| `kind` | 本节点作为容器的种类：`leaf`、`row`、`column`、`stack`、`scroll`、`splitter`、`table`、`table_row`、`form`、`anchor`、`custom` | `leaf` |
| `main` / `cross` | 本节点在**父容器**主轴/交叉轴上的尺寸策略 | `fit` / `fit` |
| `main_min` `main_max` `cross_min` `cross_max` | lpx 夹紧范围 | 0 / inf / 0 / inf |
| `padding` | 四边内边距，lpx | 全 0 |
| `gap` | 在流子项之间的间距，`theme.Gap` 阶梯 | `none` |
| `justify` | 主轴剩余空间的分配 | `start` |
| `cross_align` | 子项在交叉轴上的默认对齐 | `start` |
| `self_align` | 本节点覆盖父容器的 `cross_align` | 无 |
| `self_main_align` | 仅在 Stack/Form/Table 单元格中有意义：本节点在主轴上的对齐 | 无 |
| `form_span` | 仅 Form 子项：独占一整行 | 假 |
| `content` | 叶节点的内容固有尺寸、内容度量键、height-for-width 回调 | 空 |

**REQ-LAYOUT-009**　尺寸策略语义**必须**如下：

| 策略 | 轴 | 含义 |
|---|---|---|
| `fixed(v)` | 主/交叉 | 取 `px(v)`，再按 min/max 夹紧；与内容无关 |
| `fit` | 主/交叉 | 取测量得出的期望尺寸（内容或子项所需），再夹紧；永不被收缩 |
| `fit_shrink` | 主 | 同 `fit`，但容器主轴溢出时可被收缩，下限为 `main_min`（REQ-LAYOUT-018） |
| `grow(weight)` | 主 | 基础尺寸 0；剩余空间按权重分配（REQ-LAYOUT-016）；在非确定的主轴限制下（容器自身 fit）只取 `main_min` |
| `fill` | 交叉 | 取容器内部交叉轴尺寸（经夹紧）；容器交叉轴为非确定且无界时，退化为 `fit` 的期望尺寸，排布时再扩展到容器内部交叉轴尺寸 |

`grow` 的 `weight` 为有限正数；零或负数视为 0（仅得 `main_min`），调试构建断言并报告。

**REQ-LAYOUT-010**　`main_min/max`、`cross_min/max` 对**所有**策略生效（包括 fixed 与 fill）。夹紧顺序为先 max 后 min；若 `min > max`，视为 `max = min`，调试构建报告一条 `warn`。夹紧发生在 ppx 整数上。

**REQ-LAYOUT-011**　`fit_shrink` 只对 `kind = leaf` 的节点有意义（可省略的文本、标签）。容器节点声明 `fit_shrink` 时按 `fit` 处理，调试构建报告一条 `warn`。理由：保证收缩后的重新测量只涉及单个叶节点（REQ-LAYOUT-021）。

**REQ-LAYOUT-012**　`padding` 位于节点矩形**内部**，减少子项可用空间；`gap` 只出现在**相邻的在流子项**之间（含 `hidden` 子项，不含未声明与出流子项），首尾无 gap。`gap` 取自 `theme.Gap`，换算为 `px(gap)`；`none` 为 0。

**REQ-LAYOUT-013**　对齐语义**必须**如下：
- `justify`（`start`/`center`/`end`/`space_between`）：只作用于线性容器在**分配之后仍有剩余**的主轴空间（REQ-LAYOUT-023）。
- `cross_align`（`start`/`center`/`end`）：子项交叉轴尺寸小于容器内部交叉轴尺寸时的放置；子项可用 `self_align` 覆盖。
- 居中偏移取 `floor((空间 − 尺寸) / 2)`，使结果确定；子项大于空间时偏移取 0（向起始侧对齐、溢出一侧被裁剪）。

**REQ-LAYOUT-014**　叶节点的内容固有尺寸由控件通过 `Content` 提供：`size`（lpx，不含 padding）、`key`（内容度量键，任何会改变 `size` 的输入的 64 位摘要，如文本哈希与字体样式）、可选的 `hfw`（REQ-LAYOUT-027）。叶节点测量得出的自然尺寸 = `ceil(content.size × scale) + padding`，再夹紧。

### 3.3 主轴分配

**REQ-LAYOUT-015**　权重**必须**先量化再参与运算：`wq = max(1, round(weight × 1024))`（`weight > 0` 时），其余为 0。按权重分配整数总量时**必须**使用最大余数法（`layout.apportion`）：设总量 `T`、权重 `wq_i`、总权 `W`，则份额 `s_i = floor(T × wq_i / W)`，余量 `R = T − Σ s_i` 依次给小数部分（`T × wq_i mod W`）最大者各加 1，并列时序号小者优先。运算使用 64 位整数，结果与浮点实现无关，Σ s_i 恰等于 `T`。

**REQ-LAYOUT-016**　线性容器的主轴分配（`layout.distribute`）**必须**按下列步骤，输入为可分配总量 `avail`（容器内部主轴尺寸减去全部 gap；非负）与各在流子项的 (策略, 基础尺寸 b, min, max, wq)：
1. **夹紧基础尺寸**：对 fixed/fit/fit_shrink 子项，`b_i = clamp(b_i, min_i, max_i)`；这些子项的尺寸暂定为 `b_i`。grow 子项暂定为未确定。
2. **溢出判定**：`used = Σ b_i(非 grow) + Σ min_i(grow)`；`overflow = used − avail`。
3. 若 `overflow > 0`：grow 子项一律取 `min_i`；转 REQ-LAYOUT-018 的收缩步骤；结束。
4. 否则进入 REQ-LAYOUT-017 的冻结法，分配 `avail − Σ b_i(非 grow)` 给 grow 子项；结束。
5. 结束后 `leftover = avail − Σ 最终尺寸`（≥ 0，仅当所有 grow 子项被 max 封顶或没有 grow 子项时 > 0），交给 `justify`。

**REQ-LAYOUT-017**　grow 子项的**冻结法**：令 `active` 为全部 `wq > 0` 的 grow 子项，`remaining = avail − Σ b_i(非 grow) − Σ(已冻结尺寸)`。`wq = 0` 的 grow 子项直接冻结为 `min_i`。循环：
1. 若 `active` 为空，结束。
2. 用精确有理数计算各项的理想份额 `ideal_i = remaining × wq_i / W`（比较时用交叉相乘的 64 位整数，不做除法）。
3. 违规项：`ideal_i < min_i`（下违规）或 `ideal_i > max_i`（上违规）。无违规项则按 REQ-LAYOUT-015 把 `remaining` 分给 `active`，结束。
4. 令 `V = Σ (夹紧后尺寸 − ideal_i)` 取遍违规项。`V > 0`：冻结全部下违规项于其 `min`；`V < 0`：冻结全部上违规项于其 `max`；`V = 0`：冻结全部违规项。
5. 从 `remaining` 中扣除被冻结项的尺寸，把它们移出 `active`，回到 1。

每轮至少冻结一项，故迭代次数 ≤ grow 子项数；总复杂度 O(n²) 且 n 为同一容器的子项数（实践中 n ≤ 数十）。

**REQ-LAYOUT-018**　溢出时的收缩：令候选为全部 `fit_shrink` 子项，各自的"可收缩量"`slack_i = b_i − main_min_i`（≥ 0）；总可收缩量 `S = Σ slack_i`。实际收缩总量 `take = min(overflow, S)`，按 `slack_i` 为权重用最大余数法分配（每项不超过自身 `slack_i`），`size_i = b_i − reduction_i`。收缩后的 `fit_shrink` 子项**必须**以确定的新主轴限制重新测量一次（REQ-LAYOUT-021）。

**REQ-LAYOUT-019**　收缩之后仍有 `overflow − take > 0`（作为 `DistributeResult.overflow` 返回）时，**不得**缩小 fixed、fit 或取 min 的 grow 子项；子项保持其尺寸，内容越过容器内部区域的末端。越界部分是否被裁剪由所在容器的 `NodeFlags.clip_children` 决定，根节点恒按窗口客户区裁剪；Scroll 的内容区、Splitter 窗格、Table 单元格恒置 `clip_children`。

### 3.4 线性容器与 Stack

**REQ-LAYOUT-020**　Row/Column 的**测量**`measure(n, limit)` **必须**按下列步骤（以 Row 为例，Column 交换轴）：
1. **准备**：`P` = padding（ppx），`g` = `px(gap)`，`V` = 在流子项（含 hidden），`G = g × max(|V|−1, 0)`；内部限制 `Lm = limit.w − P_w − G`（无界保持无界，下限 0），`Lc = limit.h − P_h`。
2. **非 grow 子项**：对每个主轴策略为 fixed/fit/fit_shrink 的子项，按顺序调用一次 `measure(child, ·)`：主轴限制 fixed 取其值、其余取 `Lm`（非确定）；交叉轴限制 fixed 取其值、其余取 `Lc`。记录基础尺寸 `b` 与交叉轴尺寸 `x`（交叉轴 fixed 取其值，fit 取期望交叉尺寸，fill 取 `Lc`，`Lc` 无界时取期望交叉尺寸）。
3. **主轴尺寸**：若 `limit.w` 为确定限制，调用 `distribute(Lm, …)` 得到全部子项的最终主轴尺寸 `m_i`；否则 `m_i = b_i`（grow 取 `main_min`）。
4. **grow 子项与被收缩的叶子**：对每个 grow 子项以确定主轴限制 `m_i`、交叉限制 `Lc` 调用一次 `measure`，得其交叉轴尺寸；对被收缩的 `fit_shrink` 叶子以确定限制 `m_i` 重新测量一次。
5. **汇总**：期望主轴尺寸 = `P_w + G + Σ m_i`；期望交叉尺寸 = `P_h + max x_i`（无子项为 `P_h`）。两者再按本节点的 min/max 夹紧后返回。

出流子项（Anchor）不参与以上任何一步。

**REQ-LAYOUT-021**　测量**必须**记忆化：缓存键为 (节点, 模式, 限制)。命中规则：限制逐分量相等；或两次限制均为非确定、缓存的限制在每个分量上 ≥ 请求的限制，且缓存的结果在每个分量上 ≤ 请求的限制（此时内容不受该限制约束，结果必然相同）。确定限制必须逐分量相等才命中。一次完整求解中，同一节点的测量调用（含缓存未命中）**不得**超过 2 次：1 次为首次测量，1 次为 REQ-LAYOUT-018 的收缩重测；Scroll 的重测（REQ-LAYOUT-030）使其内容子树整体再测一次，因此嵌套 k 层 auto Scroll 时最深节点上限为 2^k 次。

**REQ-LAYOUT-022**　Row/Column 的**排布**`arrange(n, rect)` **必须**按下列步骤：
1. 内部矩形 = `rect` 去掉 padding（各边下限 0）。
2. 取各在流子项的基础尺寸：fixed 取其值，fit/fit_shrink 取测量缓存（按 REQ-LAYOUT-021 命中，未命中则就地测量），grow 取 0。
3. 以内部主轴尺寸减 gap 为 `avail` 调用 `distribute`，得最终主轴尺寸 `m_i` 与 `leftover`。
4. 子项交叉轴尺寸：fixed 取其值，fit 取以确定主轴限制 `m_i` 测量得到的交叉轴期望尺寸（对 grow 与被收缩的叶子，命中 REQ-LAYOUT-020 第 4 步的缓存），fill 取内部交叉轴尺寸；均按交叉轴 min/max 夹紧。
5. 按 `justify` 与 `leftover` 确定首个子项的主轴起点与额外间距（REQ-LAYOUT-023），按交叉轴对齐确定交叉轴偏移（REQ-LAYOUT-013），为每个子项（含 hidden）写入矩形，递归 `arrange`。
6. hidden 子项占位并参与上述计算；出流子项按其种类处理（REQ-LAYOUT-042）。

**REQ-LAYOUT-023**　`leftover > 0` 时：`start` 起点为内部起点；`center` 起点偏移 `floor(leftover / 2)`；`end` 起点偏移 `leftover`；`space_between` 在 `|V| ≥ 2` 时把 `leftover` 平均分给 `|V|−1` 个间隙，每个间隙 `floor(leftover / (|V|−1))`，余数从第一个间隙起每个多 1 ppx；`|V| < 2` 时等同 `start`。`leftover = 0`（含存在未封顶的 grow 子项）时 `justify` 无效果。

**REQ-LAYOUT-024**　交叉轴上子项的矩形：偏移取自 `self_align`（无则取容器 `cross_align`）；`fill` 子项占满内部交叉轴尺寸（经 min/max 夹紧后，若小于内部尺寸则仍按对齐放置）。Row 的子项垂直方向、Column 的子项水平方向遵循同一规则。

**REQ-LAYOUT-025**　Stack 把所有在流子项叠放在内部矩形内，按先序绘制（后者在上）。子项尺寸：fixed 取其值；fit 取期望尺寸；fit_shrink 取 `max(main_min, min(期望, 内部尺寸))`；`grow`（任意权重，仅 Stack 内的含义）与 `fill` 取内部尺寸；均经 min/max 夹紧。水平位置由 `self_main_align`（无则取容器 `justify` 中的 `start/center/end`，`space_between` 视为 `start`），垂直位置由 `self_align`（无则取 `cross_align`）。Stack 的期望尺寸为 padding 加各子项（grow、fill 按期望尺寸计）水平与垂直方向的最大值。

**REQ-LAYOUT-026**　测量有两个模式：`natural`（默认，上述各条）与 `min`（最小期望尺寸，仅用于 REQ-LAYOUT-053，限制无界且非确定）。`min` 模式与 `natural` 的差异仅限：`fit_shrink` 叶子取 `main_min`；`grow` 取 `main_min`（本来如此）；Scroll 在其滚动轴上只贡献自身的 `main_min`/`cross_min`（内容不计），非滚动轴贡献内容的 `min` 期望尺寸；Splitter 取两侧 min 之和。`min` 模式对每个节点至多测量一次，其结果不与 `natural` 共用缓存。

### 3.5 Height-for-width

**REQ-LAYOUT-027**　带 `Content.hfw` 的叶节点（自动换行文本）测量时：宽度 `w = min(自然宽度, limit.w − padding, main/cross 上的 max)`（自然宽度即 `content.size.w` 换算值）；以 `hfw(ctx, w_lpx)` 回调**一次**取得高度（返回 lpx，框架按 REQ-LAYOUT-002 换算）。该回调：
- 是测量遍内唯一被允许的回调，**必须**是纯函数（输出只取决于 `ctx` 指向的不可变数据与 `w_lpx`）；
- 每个节点每次求解至多调用 1 次，被 REQ-LAYOUT-018 收缩后的重测至多再调用 1 次，合计 ≤ 2 次；`min` 模式下 ≤ 1 次；
- **不得**在排布遍调用（排布只读测量缓存，命中规则见 REQ-LAYOUT-021）；
- 回调相同 `(content.key, w)` 的结果可被框架缓存，缓存命中不算调用。

### 3.6 Scroll

**REQ-LAYOUT-028**　Scroll 恰有一个子项（内容），多于一个时调试构建断言，发布构建忽略其余。内容在**滚动轴方向**上以无界、非确定限制测量（可任意大）；在**非滚动轴**上以视口尺寸为确定限制测量。`ScrollParams.axes` 取 `vertical`、`horizontal`、`both`。Scroll 恒置 `clip_children`，裁剪区为视口。

**REQ-LAYOUT-029**　滚动条**常驻式占位**：滚动条显示时占据 `scrollbar_w`（`px(.scrollbar_w)`）宽度，从视口中扣除，不叠加在内容之上。显示策略 `bar_v`、`bar_h` 各取：
- `always`：始终占位，内容不足时滚动条为禁用外观；
- `auto`：仅当内容在该轴上大于视口时占位；
- `never`：不占位、不显示，但滚轮、键盘与程序化滚动仍可用。

两条滚动条同时显示时，右下角留 `scrollbar_w × scrollbar_w` 的角块。滚动轴不在 `axes` 内的方向不显示滚动条。

**REQ-LAYOUT-030**　`auto` 策略下滚动条的出现会减少内容可用宽度，从而可能改变内容高度。**收敛规则**必须如下：
1. 先按"无滚动条"（`always` 的轴先扣除）确定视口 `(W, H)`，测量内容得 `(cw, ch)`。
2. 单轴滚动（如仅 `vertical`）：若 `ch > H` 且该轴策略为 `auto` 且尚未占位，则扣除滚动条宽度，以新的非滚动轴限制**重测内容一次**。此后滚动条的显示状态**锁定**：即使重测后 `ch' ≤ H`，滚动条也保持显示，偏移范围为 0。
3. 双轴滚动（`both`）：内容在两轴均无界测量，不重测。依次计算 `needV = ch > H`；`needH = cw > W − (needV ? bw : 0)`；`needV = ch > H − (needH ? bh : 0)`（至多再算一次，单调不回退）。
4. 每个 Scroll 节点每次求解至多重测内容一次。

**REQ-LAYOUT-031**　滚动偏移以 ppx 整数在内部保存。最终视口 `V`、内容尺寸 `C`（滚动轴取内容的期望尺寸，若内容在该轴策略为 `fill` 则取 `max(期望, V)`；非滚动轴 `fill` 取 `V`）确定后，每个轴的最大偏移 `max_off = max(0, C − V)`。请求偏移 `ScrollParams.offset`（lpx）换算为 `round(offset × scale)` 后**夹紧**到 `[0, max_off]`；负数与 NaN 视为 0。内容子项的位置 = `padding_origin − 夹紧后的偏移`。

**REQ-LAYOUT-032**　内容尺寸或视口变化时偏移的保持规则：
- 默认保持**偏移绝对值**（ppx）不变，再按 REQ-LAYOUT-031 夹紧（内容变短时偏移随之减小）。
- `ScrollParams.anchor_end = true` 时，若上一次布局的请求偏移等于当时的 `max_off`（即位于末端），则新的偏移取新的 `max_off`（用于日志类视图跟随末尾）；否则按默认规则。
- `ScrollParams.reveal` 非空（内容坐标系下的 lpx 矩形）时，在夹紧前先调整偏移使该矩形尽可能完整进入视口：矩形已在视口内则不动；否则以**最小位移**使其进入；矩形大于视口时对齐其起始边。`reveal` 仅在提出它的那一次构建的布局中生效。
- DPI 变化时偏移按 lpx 值重新换算，不是按 ppx 缩放。

**REQ-LAYOUT-033**　布局**必须**把滚动的实际结果报告给下一次构建：`ui.scrollMetrics(id) ?ScrollMetrics`（lpx 与 ppx 双份）含夹紧后的偏移、`max_off`、视口矩形、内容尺寸、两条滚动条是否显示及其矩形。Scroll 控件**应当**在下一次构建以 `metrics.offset` 覆盖其保存的偏移，以免请求偏移在边界外累积。

### 3.7 Splitter

**REQ-LAYOUT-034**　Splitter 恰有两个子项（窗格），多于两个时调试构建断言。分隔条占 `px(.splitter_w)` 主轴尺寸，位于两窗格之间。窗格的尺寸策略被**忽略**，一律填满分配到的矩形（含交叉轴）；窗格置 `clip_children`。`orientation` 取 `horizontal`（两窗格左右排列，分隔条竖直）或 `vertical`（上下排列）。

**REQ-LAYOUT-035**　分隔条位置 `SplitPos` 取三种表示之一，由控件在构建时给出：`ratio(r)`（0..1，第一窗格占 `avail` 的比例）、`fixed_first(v)`（第一窗格固定 `px(v)`）、`fixed_second(v)`（第二窗格固定 `px(v)`）。其中 `avail = 内部主轴尺寸 − splitter_w`。解析：`ratio` → `first = round(avail × r)`（0.5 向上）；`fixed_first` → `first = px(v)`；`fixed_second` → `first = avail − px(v)`。`second = avail − first`。

**REQ-LAYOUT-036**　解析后**夹紧**：每侧有 `min_first`、`min_second`（lpx，默认 0）；`first = clamp(first, min1, avail − min2)`。当 `min1 + min2 > avail` 时不可能同时满足，改为按两个 min 的比例分配：`first = floor(avail × min1 / (min1 + min2))`，`second = avail − first`。`avail < 0` 时按 0。Splitter 的期望尺寸：主轴 = `P + min1 + splitter_w + min2`，交叉轴 = `P + max(两窗格的 cross_min)`；窗格内容不参与 Splitter 的期望尺寸。

**REQ-LAYOUT-037**　窗口缩放（Splitter 自身尺寸变化）时的分配规则：`ratio` 模式保持比例，`first` 随 `avail` 线性变化后取整并夹紧；`fixed_first` 保持第一窗格不变、第二窗格吸收全部变化；`fixed_second` 相反。夹紧后若与请求位置不同，布局**不得**改写控件保存的位置；控件在下一次构建通过 `ui.splitMetrics(id)` 读取实际 `first` 与分隔条矩形，决定是否采纳（拖动时才改写保存位置）。

### 3.8 Table 与 Form

**REQ-LAYOUT-038**　Table 的子项是**行**（`kind = table_row` 的节点），行的子项是**单元格**。第 i 个单元格占用列 i 的横向区间，所有行共享同一组列矩形（由 Table 求解一次）。行的 `main` 策略被忽略（占满 Table 内部宽度）；行高由行的 `cross` 策略决定：`fixed`（如 `row_h`）或 `fit`（单元格期望高度的最大值，单元格以确定的列宽测量）。单元格数少于列数时余列为空，多于列数的单元格被忽略并在调试构建报告。Table 恒置 `clip_children`。

**REQ-LAYOUT-039**　列宽策略 `ColumnWidth` 取三种之一：`fixed(v)`、`grow(weight)`、`auto_header`（取表头行——前 `header_rows` 行，默认 1——中该列单元格的自然宽度的最大值，**不**读取表头以外的行），均可带 min/max（lpx）。列宽按 REQ-LAYOUT-016 求解：`auto_header` 视同 fit 的基础尺寸（不可收缩），`fixed` 视同 fixed，列间距 `col_gap`（`theme.Gap`，默认 `none`）视同 gap；内部宽度非确定时 grow 列取 `min`。求解入口 `layout.solveColumns` 是纯函数，供重型表格控件（虚拟化，不声明全部行）复用同一列宽结果。

**REQ-LAYOUT-040**　单元格在其列矩形与行矩形内的放置：单元格的 `main` 策略为 `grow` 时占满列宽；`fixed`/`fit`/`fit_shrink` 时取相应宽度（`fit_shrink` 不超过列宽），水平位置由 `self_main_align`（默认 `start`）决定；垂直方向按行的 `cross_align`（单元格可用 `self_align` 覆盖，单元格 `cross = fill` 占满行高）。Table 的期望尺寸：宽 = 各列基础宽度之和 + 列间距 + padding；高 = 各行高度之和 + 行间距（`Params.gap`）+ padding。

**REQ-LAYOUT-041**　Form 的子项按先序两两配对为（标签, 字段）行；`form_span = true` 的子项独占一行并横跨两列。落单的最后一个非 span 子项视为字段，标签列留空。**标签列宽**取全部标签单元格自然宽度的最大值，并受上限 `min(label_max, floor(内部宽度 / 2))` 约束（`label_max` 默认为 240 lpx；超出者由标签自身的 `fit_shrink`/省略处理）；字段列宽 = 内部宽度 − 标签列宽 − `px(col_gap)`（`col_gap` 默认 `gap_md`），不足 0 时取 0；内部宽度无界时字段列取字段自然宽度的最大值。行高 = 标签与字段高度的较大者，行间距为 `Params.gap`。单元格的放置与 REQ-LAYOUT-040 相同，其默认垂直对齐为 `center`；多行字段（如文本区）的标签与字段用 `self_align = start` 顶端对齐。

### 3.9 Anchor

**REQ-LAYOUT-042**　Anchor 是**出流**容器：它不参与父容器的测量、gap 与分配，只出现在 Row/Column/Stack 内（或作为弹出根，见 REQ-LAYOUT-044）。其节点矩形被指派为**父节点的内部矩形**，使其子项与父节点处于同一坐标空间；它的（唯一）子项被摆放在锚矩形旁。`AnchorParams` 含：`target`（`parent` 即父节点内部矩形，或 `rect(r)` 即父节点坐标系下的显式 lpx 矩形）、`placement`、`gap`（`theme.Gap`）、`bounds`（`parent` 或 `root`，摆放结果必须落入的边界）。Anchor 应当声明为其父容器的最后一个子项（绘制在其他兄弟之上，不存在 z-index）。

**REQ-LAYOUT-043**　摆放算法 `layout.placeAnchored(anchor, size, placement, gap, bounds)`（全部整数 ppx 的纯函数，Anchor 与弹出层共用）**必须**按下列确定性步骤，`size = (w, h)` 为子项期望尺寸（先以 `limit = bounds` 尺寸测量得出），`placement = (side, align)`，`side ∈ {below, above, right, left}`，`align ∈ {start, center, end}`： **交叉轴翻转**：`placement.flip_cross` 为真时，在"平移夹紧"之前增加一步——若按 `align_` 对齐的结果在交叉轴上越出 `bounds`，改用相反的对齐（`start` ↔ `end`）重算，仅当其不越界时采用；否则回到原对齐再夹紧。上下文菜单以指针处的零尺寸矩形为锚并置 `flip_cross`，从而在右侧放不下时改为出现在指针左侧而不是盖住指针。
1. **宽度夹紧**：`w = min(w, bounds.w)`；`h` 的限制在第 6 步处理。
2. **候选位置**（`gap` 已为 ppx）：`below`：`y = anchor.bottom + gap`；`above`：`y = anchor.top − gap − h`；`right`：`x = anchor.right + gap`；`left`：`x = anchor.left − gap − w`。垂直方位的 `x` 由 `align` 定：`start` → `anchor.left`；`end` → `anchor.right − w`；`center` → `anchor.left + floor((anchor.w − w) / 2)`。水平方位的 `y` 同理（`start` → `anchor.top`，`end` → `anchor.bottom − h`，`center` 同上规则）。
3. **主方向适配判定**：垂直方位看 `y ≥ bounds.top 且 y + h ≤ bounds.bottom`；水平方位看 `x ≥ bounds.left 且 x + w ≤ bounds.right`。
4. 首选 `side` 适配则采用；否则**翻转**到对侧（`below↔above`，`right↔left`，`align` 不变），对侧适配则采用。
5. 两侧均不适配：取主方向空间较大的一侧（空间 = 锚矩形边到 bounds 对应边的距离 − `gap`；相等取首选侧），在该侧位置上**平移夹紧**主方向坐标到 bounds 内（此时允许覆盖锚矩形）。
6. **高度限制**：若 `h > bounds.h`，`h = bounds.h` 且 `y = bounds.top`；`h` 被限制的结果标记 `height_limited`（内容由弹出层自己的 Scroll 处理）。水平方位下同理处理 `w`。
7. **交叉方向平移夹紧**：垂直方位的 `x` 夹紧到 `[bounds.left, bounds.right − w]`，水平方位的 `y` 同理；与候选位置不同则标记 `clamped`。
结果为 `(rect, side_used, clamped, height_limited)`。算法不得读取除参数外的任何状态。

**REQ-LAYOUT-044**　弹出根（06，REQ-FRAME-016）的布局：弹出根的根节点以 `limit = 显示器工作区尺寸`（非确定）测量，其宽度可被 `PopupSpec.match_anchor_width` 与 `min_width` 抬高（但不超过工作区宽度），随后调用 `placeAnchored`，`anchor` 为 `PopupSpec.anchor` 换算到屏幕坐标的矩形，`bounds` 为锚点所在显示器的工作区（由 03 提供）。`height_limited` 时弹出根按被限制的高度排布，其内容**应当**包在 Scroll 中。弹出根的位置与尺寸随后交给平台层（03）移动其窗口。锚矩形的来源是宿主保留树中的 `lastRect`，因此锚点移动后弹出层在下一次布局跟随。

### 3.10 增量复用与反馈

**REQ-LAYOUT-045**　**布局输入哈希** `layout_hash(n)` 是 64 位 Merkle 式哈希，**必须**由下列各项依次折叠构成：`scale`（位模式）与主题度量表的版本号；`kind` 标签及其种类参数中影响测量/排布的字段（`ScrollParams.axes/bar_v/bar_h/anchor_end`、`SplitterParams.orientation/min_first/min_second`、`TableParams.columns/header_rows/col_gap`、`FormParams.label_max/col_gap`、`AnchorParams.placement/gap/bounds`、`CustomLayout.key`）；`main`、`cross`、四个 min/max；`padding`、`gap`、`justify`、`cross_align`、`self_align`、`self_main_align`、`form_span`；`NodeFlags.hidden`；`content.key` 与 `content.size`；子项个数；按顺序每个在流子项的 (WidgetId, `layout_hash(child)`)。**不得**纳入：`ScrollParams.offset/reveal`、`SplitPos`、`AnchorParams.target`（它们只影响本节点自己的排布，不影响子树内部的相对布局）、绘制键、`paint_outset`、交互状态。

**REQ-LAYOUT-046**　测量复用（REQ-FRAME-039 的精确化）：新树节点若在旧树中存在同 ID 节点，且两者 `layout_hash` 相等，且本次请求能命中旧节点缓存的 (模式, 限制)（命中规则同 REQ-LAYOUT-021），则**必须**直接沿用其期望尺寸，不进入其子树；子树内全部节点计入"复用"。复用判定只发生在测量入口，自顶向下每个节点至多判定一次。

**REQ-LAYOUT-047**　排布跳过：新树节点的测量被复用，且指派给它的矩形**尺寸**等于旧矩形尺寸，且其子树内不含 `layout_feedback` 标志节点的变化，则其整棵子树的相对矩形沿用旧值，不再递归排布（子节点矩形相对父节点原点，所以父节点的平移不影响子树）。Scroll 的内容偏移、Splitter 的分隔位置、Anchor 的目标变化只更新本节点直接子项的位置，其子树按本条判定。

**REQ-LAYOUT-048**　布局阶段**必须**通过 `core.stats` 暴露下列**计量**（每次布局结束时设为本次布局的值；计量与计数器的区别见 REQ-ARCH-021）：`layout.measured_nodes`（实际进入测量函数的节点数）、`layout.arranged_nodes`、`layout.hfw_calls`、`layout.scroll_remeasures`。被复用度量的节点数使用 12 登记的 `frame.nodes_measure_reused`（口径：沿用旧测量结果的节点数，含被整体跳过的复用子树内的全部后代），本模块负责更新它，不另设名字。

**REQ-LAYOUT-049**　布局反馈（REQ-FRAME-029/031）的检查点：每个根在其排布遍结束、损伤计算之前，遍历该根内设置了 `layout_feedback` 标志的节点，比较其最终尺寸（ppx 整数）与构建时 `lastRect` 所见尺寸（首次出现视为不同）。任一不同且本帧尚未执行第二构建遍，则回到构建阶段；否则以当前结果完成本帧并按 REQ-FRAME-032 置构建脏。`lastRect` 的调用**必须**登记"所见尺寸"，未调用 `lastRect` 的反馈节点视为所见尺寸为空。

### 3.11 自定义容器

**REQ-LAYOUT-050**　应用**可以**用 `kind = custom` 提供自己的容器算法，由 `CustomLayout{ measure, arrange, key }` 两个回调与一个算法标识 `key`（纳入哈希）构成，签名见第 4 节：
- `measure(ctx, node, mode, limit) SizeI`：返回期望尺寸；经 `ctx.measureChild(index, limit)` 测量子项，**每个子项最多调用一次**。
- `arrange(ctx, node, rect)`：经 `ctx.placeChild(index, rect_in_node_coords)` 为**每个**在流子项恰好指派一次矩形（整数 ppx，相对本节点原点）；可经 `ctx.measureChild` 取（已缓存的）子项期望尺寸。
`ctx` 还提供 `scale`、子项个数、子项的 `layout.Params`（只读）与 `theme.px`。

**REQ-LAYOUT-051**　自定义容器的约束：回调**不得**读取兄弟（含非子项的任何节点）的排布结果，**不得**多轮迭代同一子项（即不能对同一子项以不同限制反复测量求不动点），**不得**有副作用，**必须**是仅依赖 `ctx` 的纯函数；未指派矩形的子项得到零矩形，调试构建断言。自定义容器的子项与内建容器的子项完全等价：同样参与哈希、复用与 `hidden`。

### 3.12 DPI 与窗口

**REQ-LAYOUT-052**　`scale` 变化（DPI 变化，REQ-FRAME-037）时，因 `layout_hash` 含 `scale`，所有节点的测量缓存失效，布局**必须**全量重新求解。同一 lpx 描述在不同 `scale` 下各自独立取整，**不得**由某一 `scale` 的结果缩放得出。

**REQ-LAYOUT-053**　根节点的矩形被指派为其平台窗口的客户区（弹出根见 REQ-LAYOUT-044），其自身的 `main/cross` 策略被忽略。主根在每次布局后**必须**以 `min` 模式测量一次（缓存复用，REQ-LAYOUT-026），得到**最小期望尺寸**，经 `ui.minWindowSize()` 以 lpx 提供给平台层，平台层加上非客户区后用于 `WM_GETMINMAXINFO`（03）。该值与 `WindowOptions.min_size`（11）取各分量较大者。最小期望尺寸变化时才通知平台层。

**REQ-LAYOUT-054**　**大内容坐标**：Scroll 的内容范围与滚动偏移**必须**以 64 位整数物理像素保存与运算（`ScrollMetrics.offset_px`、`content_px`），不受 `f32` 精度限制；`offset`（lpx）只是其换算后的便捷值。虚拟化控件（list/tree/table/text-area）**不得**为全部内容创建节点，而是经 `ScrollParams.virtual_extent_px` 声明内容总范围，并用 `ScrollParams.offset_px` 请求偏移；它为可见项创建的子节点以**相对视口**的整数 ppx 位置排布（`Extent.fixed_px`、子项的 `virtual_pos_px`），因此任何节点矩形的坐标量级都不超过视口尺寸加缓冲，`f32` 可精确表示。内容范围的上限为 2^53 ppx。

**REQ-LAYOUT-055**　**内部部件节点**：Scroll 与 Splitter 由框架在其节点下自动创建部件叶节点——Scroll 的每条可见滚动条有"槽"与"滑块"两个节点，Splitter 在两个窗格之间有一个"分隔条"节点（主轴尺寸为 `splitter_w`，两窗格各让出一半）。部件节点的 ID 由容器 ID 与固定的部件键派生，在保留树中是普通节点，可被命中、可有悬停与按下状态；容器控件对它们调用 `ui.interact`。"Splitter 恰有两个子项"等对子项数量的规定只计应用声明的子项。

**REQ-LAYOUT-056**　**发丝线内缩**：`Params.border`（`u8`，默认 0）使容器的内容区在 `padding` 之外四边各再内缩 `border × 发丝线宽度`（ppx，REQ-THEME-012）。带发丝线边框的容器控件用它为边框留位，而不是用 lpx 的 `padding` 近似。


## 4. 接口草案

```zig
// 草案：仅签名
pub const unbounded: i32 = 1 << 28;

pub const Align = enum { start, center, end };
pub const Justify = enum { start, center, end, space_between };

pub const Extent = union(enum) {   // 主轴
    fixed: f32,                    // lpx
    fit,
    fit_shrink,                    // 仅叶子
    grow: f32,                     // 权重
};
pub const CrossExtent = union(enum) {
    fixed: f32,
    fit,
    fill,
};

pub const HeightForWidthFn = *const fn (ctx: ?*const anyopaque, width_lpx: f32) f32; // 纯函数
pub const Content = struct {
    size: Vec2 = .{ .x = 0, .y = 0 },   // lpx，不含 padding
    key: u64 = 0,                       // 内容度量键
    hfw: ?HeightForWidthFn = null,
    hfw_ctx: ?*const anyopaque = null,  // 须在树竞技场
};

pub const SizeI = struct { w: i32, h: i32 };
pub const Limit = struct { w: i32, h: i32, definite_w: bool = false, definite_h: bool = false };
pub const MeasureMode = enum { natural, min };

pub const BarPolicy = enum { auto, always, never };
pub const ScrollAxes = enum { vertical, horizontal, both };
pub const ScrollParams = struct {
    axes: ScrollAxes = .vertical,
    bar_v: BarPolicy = .auto,
    bar_h: BarPolicy = .auto,
    offset: Vec2 = .{ .x = 0, .y = 0 },   // lpx，请求值
    offset_px: ?[2]i64 = null,             // ppx，请求值；非空时优先于 offset（REQ-LAYOUT-054）
    virtual_extent_px: ?[2]i64 = null,     // 虚拟化内容的总范围；非空时内容范围取它而非子节点的测量结果
    anchor_end: bool = false,
    reveal: ?Rect = null,                  // 内容坐标系，lpx
};
pub const ScrollMetrics = struct {
    offset_px: [2]i64,       // ppx，夹紧后（权威值）
    content_px: [2]i64,      // ppx，内容总范围
    viewport_px: [2]i32,     // ppx，视口尺寸
    offset: Vec2,            // lpx，夹紧后（由 offset_px 换算的便捷值）
    max_offset: Vec2,        // lpx
    viewport: Rect,          // lpx，相对 Scroll 节点
    content: Vec2,           // lpx
    bar_v: ?RectI,           // ppx，相对 Scroll 节点；未显示为 null
    bar_h: ?RectI,
};

pub const Orientation = enum { horizontal, vertical };
pub const SplitPos = union(enum) {
    ratio: f32,
    fixed_first: f32,      // lpx
    fixed_second: f32,
};
pub const SplitterParams = struct {
    orientation: Orientation = .horizontal,
    pos: SplitPos = .{ .ratio = 0.5 },
    min_first: f32 = 0,    // lpx
    min_second: f32 = 0,
};
pub const SplitMetrics = struct { first_px: i32, second_px: i32, divider: RectI };

pub const ColumnWidth = union(enum) { fixed: f32, grow: f32, auto_header };
pub const Column = struct { width: ColumnWidth, min: f32 = 0, max: f32 = std.math.inf(f32) };
pub const TableParams = struct {
    columns: []const Column,     // 须在树竞技场
    header_rows: u8 = 1,
    col_gap: theme.Gap = .none,
};
pub const FormParams = struct { label_max: f32 = 240, col_gap: theme.Gap = .md };

pub const Side = enum { below, above, right, left };
pub const Placement = struct { side: Side = .below, align_: Align = .start, flip_cross: bool = false };
pub const AnchorTarget = union(enum) { parent, rect: Rect };
pub const AnchorBounds = enum { parent, root };
pub const AnchorParams = struct {
    target: AnchorTarget = .parent,
    placement: Placement = .{},
    gap: theme.Gap = .none,
    bounds: AnchorBounds = .parent,
};
pub const PlaceResult = struct { rect: RectI, side_used: Side, clamped: bool, height_limited: bool };
pub fn placeAnchored(anchor: RectI, size: SizeI, placement: Placement, gap: i32, bounds: RectI) PlaceResult;

pub const MeasureCtx = struct {
    scale: f32,
    pub fn childCount(self: *const MeasureCtx) usize;
    pub fn childParams(self: *const MeasureCtx, index: usize) *const Params;
    pub fn measureChild(self: *MeasureCtx, index: usize, limit: Limit) SizeI;
    pub fn px(self: *const MeasureCtx, lpx: f32) i32;
};
pub const ArrangeCtx = struct {
    scale: f32,
    pub fn childCount(self: *const ArrangeCtx) usize;
    pub fn childParams(self: *const ArrangeCtx, index: usize) *const Params;
    pub fn measureChild(self: *ArrangeCtx, index: usize, limit: Limit) SizeI; // 命中缓存
    pub fn placeChild(self: *ArrangeCtx, index: usize, rect: RectI) void;
    pub fn px(self: *const ArrangeCtx, lpx: f32) i32;
};
pub const CustomLayout = struct {
    key: u64,
    measure: *const fn (ctx: *MeasureCtx, mode: MeasureMode, limit: Limit) SizeI,
    arrange: *const fn (ctx: *ArrangeCtx, rect: RectI) void,
};

pub const Kind = union(enum) {
    leaf, row, column, stack,
    scroll: ScrollParams,
    splitter: SplitterParams,
    table: TableParams,
    table_row,
    form: FormParams,
    anchor: AnchorParams,
    custom: CustomLayout,
};

pub const Params = struct {
    kind: Kind = .leaf,
    border: u8 = 0,                 // 四边各内缩的发丝线条数（REQ-LAYOUT-056）
    virtual_pos_px: ?[2]i32 = null, // 仅虚拟化容器的子项：相对视口的位置（REQ-LAYOUT-054）
    main: Extent = .fit,
    cross: CrossExtent = .fit,
    main_min: f32 = 0,
    main_max: f32 = std.math.inf(f32),
    cross_min: f32 = 0,
    cross_max: f32 = std.math.inf(f32),
    padding: core.Insets = .{ .l = 0, .t = 0, .r = 0, .b = 0 },
    gap: theme.Gap = .none,
    justify: Justify = .start,
    cross_align: Align = .start,
    self_align: ?Align = null,
    self_main_align: ?Align = null,
    form_span: bool = false,
    content: Content = .{},
};

// 纯函数（便于单元测试与重型控件复用）
pub fn quantizeWeight(weight: f32) u32;
pub fn apportion(total: i32, weights: []const u64, out: []i32) void;       // 最大余数法
pub const FlexKind = enum { fixed, fit, shrink, grow };
pub const FlexItem = struct { kind: FlexKind, base: i32, min: i32, max: i32, wq: u32 };
pub const DistributeResult = struct { overflow: i32, leftover: i32 };   // overflow：收缩后仍越界的量
pub fn distribute(items: []const FlexItem, avail: i32, out: []i32) DistributeResult;
pub fn solveColumns(cols: []const Column, header_widths: []const i32, inner_w: i32, definite: bool, gap: i32, scale: f32, out: []i32) void;

// 对 06 中 NodeFlags 的增补（本文定义的位）
//   hidden: bool = false,        // 占位但不绘制、不可命中、不可聚焦；子树同
// 对 Ui 的增补
pub const ContainerOptions = struct {
    key: ?Key = null,
    debug_name: ?[]const u8 = null, // 供回放脚本与节点检视定位（13）
    main: Extent = .fit,
    cross: CrossExtent = .fit,
    main_min: f32 = 0, main_max: f32 = std.math.inf(f32),
    cross_min: f32 = 0, cross_max: f32 = std.math.inf(f32),
    padding: core.Insets = .{ .l = 0, .t = 0, .r = 0, .b = 0 },
    gap: theme.Gap = .none,
    justify: Justify = .start,
    cross_align: Align = .start,
    self_align: ?Align = null,
    clip: bool = false,
    hidden: bool = false,
};
/// 叶子控件通用的布局覆盖项。各控件选项结构以 `layout: layout.ItemOptions = .{}` 字段携带；
/// 为 null 的项沿用该控件规范第 3 节规定的默认尺寸策略。
pub const ItemOptions = struct {
    main: ?Extent = null,
    cross: ?CrossExtent = null,
    main_min: ?f32 = null, main_max: ?f32 = null,
    cross_min: ?f32 = null, cross_max: ?f32 = null,
    self_align: ?Align = null,
    hidden: bool = false,
};
// 以下以命名空间集中列出，它们是 `Ui` 的方法（属 ui 模块的公开接口，语义由本文规定）。
pub const UiLayout = struct {
    pub fn beginRow(ui: *Ui, src: std.builtin.SourceLocation, o: ContainerOptions) WidgetId;
    pub fn endRow(ui: *Ui) void;
    pub fn beginColumn(ui: *Ui, src: std.builtin.SourceLocation, o: ContainerOptions) WidgetId;
    pub fn endColumn(ui: *Ui) void;
    pub fn beginStack(ui: *Ui, src: std.builtin.SourceLocation, o: ContainerOptions) WidgetId;
    pub fn endStack(ui: *Ui) void;
    pub fn beginScroll(ui: *Ui, src: std.builtin.SourceLocation, o: ContainerOptions, s: ScrollParams) WidgetId;
    pub fn endScroll(ui: *Ui) void;
    pub fn beginSplitter(ui: *Ui, src: std.builtin.SourceLocation, o: ContainerOptions, s: SplitterParams) WidgetId;
    pub fn endSplitter(ui: *Ui) void;
    pub fn beginTable(ui: *Ui, src: std.builtin.SourceLocation, o: ContainerOptions, t: TableParams) WidgetId;
    pub fn beginTableRow(ui: *Ui, src: std.builtin.SourceLocation, o: ContainerOptions) WidgetId;
    pub fn endTableRow(ui: *Ui) void;
    pub fn endTable(ui: *Ui) void;
    pub fn beginForm(ui: *Ui, src: std.builtin.SourceLocation, o: ContainerOptions, f: FormParams) WidgetId;
    pub fn endForm(ui: *Ui) void;
    pub fn beginAnchor(ui: *Ui, src: std.builtin.SourceLocation, a: AnchorParams) WidgetId;
    pub fn endAnchor(ui: *Ui) void;
    pub fn beginCustom(ui: *Ui, src: std.builtin.SourceLocation, o: ContainerOptions, c: CustomLayout) WidgetId;
    pub fn endCustom(ui: *Ui) void;
    pub fn spacer(ui: *Ui, src: std.builtin.SourceLocation, weight: f32) WidgetId;   // grow 叶子

    pub fn lastRectPx(ui: *const Ui, id: WidgetId) ?RectI;
    pub fn scrollMetrics(ui: *const Ui, id: WidgetId) ?ScrollMetrics;
    pub fn splitMetrics(ui: *const Ui, id: WidgetId) ?SplitMetrics;
    pub fn minWindowSize(ui: *const Ui) Vec2;      // lpx，REQ-LAYOUT-053
    pub fn parentAxis(ui: *const Ui) Axis;         // 当前最内层容器的主轴：row → horizontal，column → vertical，其余 → horizontal。
                                                   // 控件规范以物理方向（宽/高）描述默认尺寸，控件据此映射到 main/cross（Axis = enum { horizontal, vertical }）
};
```

## 5. 边界与错误情况

| 情况 | 规定 |
|---|---|
| 容器可用空间为 0 或负数 | 内部尺寸取 0；fixed/fit 子项保持其尺寸并越界；grow 取 `main_min`；不报错 |
| 无子项的容器 | 期望尺寸 = padding；Scroll、Splitter 无内容/窗格时按 0 尺寸处理，调试构建对 Splitter 少于两个窗格断言 |
| `fixed(0)` | 尺寸为 0，节点仍存在（可聚焦的 0 尺寸控件不可命中） |
| 所有 grow 子项被 max 封顶 | 剩余空间交给 `justify` |
| grow 子项数为 0 且 `leftover > 0` | 交给 `justify`；默认 `start` 即留空在末端 |
| 主轴溢出且无 `fit_shrink` | 内容越界，按 REQ-LAYOUT-019 裁剪；不报错 |
| 文字度量返回 NaN/负数 | 当作 0，调试构建断言 |
| Scroll 内容为空 | `C = 0`，`max_off = 0`，auto 滚动条不显示 |
| Scroll `fit` 且被 `main_max` 限制 | Scroll 的测量期望尺寸在滚动轴被夹紧；若因此需要滚动条，期望宽度（垂直滚动时）额外加上 `scrollbar_w`，不重测内容 |
| Splitter 窗格内容比窗格大 | 裁剪，不影响分隔位置 |
| Table 列数为 0 | 行高按 `fixed`/0 计算，单元格全部忽略，调试构建报告 |
| Form 的 `label_max` 小于某标签自然宽度 | 标签单元格以确定宽度 `label_max` 重新放置，文字省略由标签控件按 REQ-THEME-018 处理 |
| Anchor 的锚矩形整个在 bounds 之外 | 按算法先平移夹紧到 bounds 内；仍可能与锚矩形不相邻 |
| Anchor 位于弹出根以外且 `bounds = root` | bounds 取该根的客户区 |
| `placeAnchored` 的 `size` 为 0 | 返回按位置规则得出的零尺寸矩形，不翻转 |
| 构建中途改变同一节点的 `kind` | 视为不同节点（哈希不同），旧缓存不复用 |
| 非线性父容器内的 `grow/fill` | 在 Stack 内取内部尺寸；在 Scroll 内容轴上 `grow` 取 `main_min`；在 Table/Form 单元格内见 REQ-LAYOUT-040 |
| 缩放系数极端（< 0.5 或 > 8） | 不保证；`px` 的"不小于 1"规则保证正值尺寸不消失 |
| 单窗口根节点 `kind` 为 `leaf` | 允许；矩形仍为客户区 |

## 6. 验收标准

除特别注明外，以下测试以无头方式、`scale = 1.0` 运行，长度单位为 ppx。

**AC-LAYOUT-001**　`[单元]` 覆盖：REQ-LAYOUT-015、REQ-LAYOUT-016。前置：调用 `layout.distribute`，三个 grow 子项均 min = 0、max = 无界。步骤与预期：权重 1:1:1，`avail` = 300 → 100/100/100；301 → 101/100/100；302 → 101/101/100；303 → 101/101/101。权重 1:2，`avail` = 100 → 33/67。权重 `[0.5, 0.5]`（量化为 512:512），`avail` = 7 → 4/3。任一情形下各份之和恰等于 `avail`，且以浮点权重 `1/3` 为输入时结果与整数权重 1:1:1 相同。

**AC-LAYOUT-002**　`[单元]` 覆盖：REQ-LAYOUT-016、REQ-LAYOUT-017。前置同上。步骤与预期：① `avail` = 300，权重 1:1:1，第 1 项 max = 50 → 50/125/125。② `avail` = 300，权重 1:1，第 1 项 min = 200 → 200/100。③ `avail` = 300，权重 1:1:1，第 1 项 min = 150、第 2 项 max = 60 → 150/60/90（冻结轮次 ≤ 3，可由测试钩子读取）。④ 两项 grow 均 max = 40，`avail` = 300 → 40/40，`leftover` = 220。⑤ 权重为 0 的 grow 项取其 min。

**AC-LAYOUT-003**　`[单元]` 覆盖：REQ-LAYOUT-018、REQ-LAYOUT-019。前置：`avail` = 300；A 为 fit_shrink（基础 200、min 80），B 为 fit_shrink（基础 150、min 50），C 为 fixed 100。预期：A/B/C = 118/82/100（收缩总量 150 按可收缩量 120:100 分配为 82 与 68），返回的剩余越界量 `overflow` = 0。变体一：C 改为 fixed 250 → 总基础 600，A、B 均收缩到各自 min（80、50），C = 250，合计 380，`overflow` = 80，C 未被缩小。变体二：无 fit_shrink 子项（fixed 200、fit 150），`avail` = 300 → 200/150，`overflow` = 50。变体三：一个 grow（min 80）与 fixed 250 → grow = 80，`overflow` = 30。

**AC-LAYOUT-004**　`[单元]` 覆盖：REQ-LAYOUT-002、REQ-LAYOUT-010。步骤与预期：`scale` = 1.25：`fixed(10.5)` → 13；`fixed(0.3)` → 1；`fixed(0)` → 0；`padding` 8 lpx → 10；`gap md`（8）→ 10。`scale` = 1.5：`Content.size.w` = 100.0000001 lpx → 150（不是 151）；`Content.size.w` = 100.4 → 151（`ceil(150.6)`）。夹紧：`fixed(50)` 且 `main_min` = 80 → 80；`main_min` = 80、`main_max` = 60 → 有效范围 [80, 80] 且调试构建产生 1 条 `warn`。

**AC-LAYOUT-005**　`[单元]` 覆盖：REQ-LAYOUT-003、REQ-LAYOUT-008、REQ-LAYOUT-012、REQ-LAYOUT-020、REQ-LAYOUT-022。前置：`scale` = 1.25，Row 矩形 500×100 ppx，`padding` 8 lpx，`gap md`；子项依次为 `fixed(40)`、`grow(1)`、`grow(1)`，交叉轴均 `fill`。预期：内部宽度 480，gap 总计 20，可分配 460，减去 fixed（50）得 410 → 205/205；子项 x 依次为 10、70、285，宽依次为 50、205、205，高均为 80（内部高度）；末项右缘 = 490 = 500 − 10。`ui.lastRect` 返回的 lpx 宽为 40、164、164（`ppx / 1.25`）；`lastRectPx` 返回整数。无子项的 Row 期望尺寸 = padding 之和。

**AC-LAYOUT-006**　`[单元]` 覆盖：REQ-LAYOUT-013、REQ-LAYOUT-023。前置：Row 内部宽 300，三个 `fixed(50)` 子项，gap = none。预期起点 x：`start` → 0/50/100；`center` → 75/125/175；`end` → 150/200/250；`space_between` → 0/125/250。内部宽改为 301：`space_between` → 0/126/251（余数给第一个间隙）。单个子项时 `space_between` 等同 `start`。增加一个 `grow(1)` 子项时 `justify` 不起作用（该项吸收全部剩余）。

**AC-LAYOUT-007**　`[单元]` 覆盖：REQ-LAYOUT-013、REQ-LAYOUT-024。前置：Row 内部高 40，子项高度（fit）15。预期交叉轴 y：容器 `cross_align` 为 `start` → 0；`center` → 12（`floor(25/2)`）；`end` → 25；子项 `cross = fill` → 高 40；子项 `self_align = end` 覆盖容器 `center` → 25；子项高 50 的 `center`/`end` → 0（溢出向起始侧）；`cross_max` = 30 的 fill 子项在容器 `center` 下 → 高 30、y = 5。

**AC-LAYOUT-008**　`[单元]` 覆盖：REQ-LAYOUT-025。前置：Stack 内部 200×100，按先序有三个子项：A 为 fixed 80×30（`self_main_align = end`、`self_align = end`）；B 为 fit_shrink 叶子，自然 300×20、`main_min` = 40；C 为 `grow`/`fill` 且无内容。预期：A 矩形 (120, 70, 80, 30)；B 宽 200（`min(300, 200)`）、高 20；C 矩形 (0, 0, 200, 100)；绘制顺序为 A、B、C，C 在最上。无限制测量 Stack 的期望尺寸 = (300, 30)（宽取 A、B、C 期望宽 80、300、0 的最大值，高取 30、20、0 的最大值）。

**AC-LAYOUT-009**　`[单元]` 覆盖：REQ-LAYOUT-009、REQ-LAYOUT-020、REQ-LAYOUT-021。前置：Column（`fit`）含三个叶子：fixed 高 20、fit 高 30、grow 且 `main_min` = 10。步骤与预期：① 以无界非确定限制测量 → 期望高 = 20 + 30 + 10 = 60，`measured_nodes` = 4（Column 与 3 个叶子各 1 次）。② 以相同限制再测一次 → `measured_nodes` 增量 0。③ 以非确定限制高 100 请求：缓存限制（无界）≥ 100 且结果 60 ≤ 100 → 命中，增量 0。④ 以非确定限制高 40 请求：结果 60 > 40 → 不命中，重新测量。⑤ 以**确定**限制高 200 请求：不命中（确定限制须逐分量相等），grow 子项得 200 − 50 = 150，其交叉轴尺寸以该确定限制测量；再以确定限制高 200 请求一次 → 命中。

**AC-LAYOUT-010**　`[单元]` 覆盖：REQ-LAYOUT-011。前置：在 Column 容器节点上声明 `main = fit_shrink`，其父 Row 内部宽 100，子项自然宽 150。预期：该容器按 fit 处理（宽 150，不被收缩），调试构建产生 1 条 `warn`；同样位置的叶子 fit_shrink（`main_min` = 30）则收缩到 100。

**AC-LAYOUT-011**　`[单元]` 覆盖：REQ-LAYOUT-014、REQ-LAYOUT-027、REQ-LAYOUT-021。前置：叶子带 `hfw`，`hfw(w) = ceil(30000 / w)`（w 为 lpx，`scale` = 1.0），自然宽度 400。情形一：叶子位于 Column 内，交叉轴 `fill`，Column 内部宽确定为 200。预期：测量后叶子高 150（`hfw(200)`），`layout.hfw_calls` = 1；排布遍 `hfw_calls` 增量为 0。情形二：叶子位于 Row 内，主轴 `fit_shrink`、`main_min` = 100，Row 内部宽 250，另有 fixed 100 的兄弟。预期：叶子先以限制 250 测量（`hfw(250)` = 120），基础宽 250，合计 350 > 250，溢出 100，叶子可收缩 150，收缩到宽 150，以确定宽 150 重测（`hfw(150)` = 200），`hfw_calls` 合计 2，最终高 200。情形三：`min` 模式测量同一叶子 → `hfw_calls` ≤ 1。

**AC-LAYOUT-012**　`[单元]` 覆盖：REQ-LAYOUT-001、REQ-LAYOUT-050、REQ-LAYOUT-051。用自定义容器实现"所有子项等宽排列"。预期：回调中对每个子项 `measureChild` 调用次数 ≤ 1、`placeChild` 恰好 1 次；故意写一个对同一子项调用两次 `measureChild`（不同限制）的容器，调试构建断言；故意漏调 `placeChild` 的子项得到零矩形且断言；自定义容器与等价的内建 Row 对同一输入产生相同矩形；改变 `CustomLayout.key` 使 `layout_hash` 变化。

**AC-LAYOUT-013**　`[单元]` 覆盖：REQ-LAYOUT-026、REQ-LAYOUT-053。前置：`scale` = 1.0，根为 Row，`padding` 12 lpx，`gap sm`（4），子项依次为 fixed 80×24、fit_shrink 叶子（自然宽 200、`main_min` = 40、高 24）、`spacer`（grow，min 0）、fixed 60×24。预期：`natural` 期望尺寸 = (376, 48)，`ui.minWindowSize()` = (216, 48)；`scale` = 1.5 时 ppx 值分别为 (564, 72) 与 (324, 72)，lpx 报告仍为 (216, 48)；`WindowOptions.min_size` = (300, 40) 时有效最小尺寸 = (300, 48)；先做 `min` 模式测量再做 `natural` 测量，`natural` 结果仍为 (376, 48)（两种模式缓存互不影响）；最小期望尺寸未变化的后续布局不再通知平台层（通知计数不增）。

**AC-LAYOUT-014**　`[单元]` 覆盖：REQ-LAYOUT-028、REQ-LAYOUT-029。前置：垂直 Scroll，视口 200×100，内容为 `fill` 宽的 Column，其中一个固定高 300 的叶子。步骤与预期：`bar_v = auto` → 滚动条显示，视口宽 188（200 − 12），内容宽 188，`bar_v` 矩形 (188, 0, 12, 100)；`bar_v = never` → 无滚动条，内容宽 200，滚轮仍可改变偏移（请求偏移 50 → 生效 50）；`bar_v = always` 且内容高 80 → 滚动条占位，视口宽 188，`max_offset` = 0；`bar_h` 在 `axes = vertical` 时恒不显示；`axes = both` 且两条均显示时角块为 12×12。内容在滚动轴被以无界限制测量（测试钩子记录限制高 ≥ `unbounded`）。

**AC-LAYOUT-015**　`[单元]` 覆盖：REQ-LAYOUT-030。前置：垂直 Scroll `auto`，视口 200×100，内容含带 `hfw` 的叶子，`hfw(w) = ceil(30000 / w)`，自然宽 400，叶子交叉轴 `fill`。预期：首次测量宽 200 → 高 150 > 100，需要滚动条；重测宽 188 → 高 160；最终内容 188×160，`max_offset` = 60，`scroll_remeasures` = 1。变体（防回退）：`hfw(200)` = 101、`hfw(188)` = 95（非单调夹具）→ 重测后内容高 95 ≤ 100，但滚动条**仍显示**，视口宽 188，`max_offset` = 0，`scroll_remeasures` = 1，且不再有第二次重测。双轴 `both`：内容 250×130、视口 200×100 → `needV`/`needH` 均真，视口缩为 188×88，`scroll_remeasures` = 0。边界：内容 195×95，视口 200×100，`both` → 两条均不显示。

**AC-LAYOUT-016**　`[单元]` 覆盖：REQ-LAYOUT-031、REQ-LAYOUT-032、REQ-LAYOUT-033。前置：垂直 Scroll，`scale` = 1.0，视口高 100，`padding` = 0，内容为一个固定高度的叶子。下表每行独立执行，"内容高"为本次布局的内容高，`max_off` = 内容高 − 100，"请求偏移"为 `ScrollParams.offset`，"上次"为上一次布局的请求偏移与当时的 `max_off`。

| 步骤 | 内容高 | `max_off` | 上次（请求/`max_off`） | 请求偏移 | 选项 | 预期偏移 |
|---|---|---|---|---|---|---|
| a | 160 | 60 | — | 80 | — | 60（夹紧） |
| b | 160 | 60 | — | −5 | — | 0 |
| c | 160 | 60 | — | NaN | — | 0 |
| d | 160 | 60 | — | 30 | — | 30 |
| e | 120 | 20 | 60/60 | 60 | — | 20（内容变短，偏移随之减小） |
| f | 200 | 100 | 60/60 | 60 | `anchor_end = true` | 100（上次在末端，跟随新末端） |
| g | 200 | 100 | 60/60 | 60 | `anchor_end = false` | 60 |
| h | 200 | 100 | 30/60 | 30 | `anchor_end = true` | 30（上次不在末端，保持） |
| i | 200 | 100 | — | 0 | `reveal` = 内容矩形 y∈[150,170) | 70（最小位移：偏移 + 100 = 170） |
| j | 200 | 100 | — | 80 | `reveal` = y∈[150,170)（可见范围 [80,180) 已包含） | 80（不动） |
| k | 200 | 100 | — | 80 | `reveal` = y∈[20,40) | 20（顶边对齐） |
| l | 200 | 100 | — | 0 | `reveal` = y∈[40,160)（高 120 > 视口 100） | 40（对齐起始边） |

`scale` = 1.5 的补充用例（同一夹具：视口 100 lpx = 150 ppx，内容高 160 lpx = 240 ppx，`max_off` = 90 ppx）：请求偏移 40 lpx → 60 ppx，`ScrollMetrics.offset` = 40 lpx、`offset_px.y` = 60；请求偏移 70 lpx → 105 ppx，夹紧为 90 ppx，`ScrollMetrics.offset` = 60 lpx；下一帧控件以 `metrics.offset` 覆盖其保存值（60 lpx）后再请求，偏移无进一步变化。`scrollMetrics(id)` 的 `viewport`、`content`、`max_offset`、`bar_v` 与上述各行一致（内容高 > 100 时垂直滚动条显示）。

**AC-LAYOUT-017**　`[单元]` 覆盖：REQ-LAYOUT-034、REQ-LAYOUT-035、REQ-LAYOUT-036。前置：水平 Splitter，矩形宽 805、`splitter_w` = 5（`avail` = 800），`scale` = 1.0。预期：`ratio(0.25)` → first/second = 200/600，分隔条矩形 x = 200、宽 5；`ratio(0.1)` 且 `min_first` = 150 → 150/650；`ratio(0.9)` 且 `min_second` = 100 → 700/100；`fixed_first(120)` 在 `scale` = 1.25（`splitter_w` 换算为 6 ppx，矩形宽 1006，`avail` = 1000）→ 150/850；`scale` = 1.0 下 `fixed_second(300)`（`avail` = 800）→ 500/300；`avail` = 100、`min_first` = 150、`min_second` = 50 → 75/25（按 min 比例）；窗格子项声明 `fixed(30)` 宽仍被填满；窗格的 `clip_children` 为真。Splitter 期望尺寸（`min_first` = 150、`min_second` = 50）主轴 = 205。

**AC-LAYOUT-018**　`[单元]` 覆盖：REQ-LAYOUT-037。前置：水平 Splitter，初始 `avail` = 800，`scale` = 1.0，`min_first` = 100、`min_second` = 100。步骤与预期：`ratio(0.25)`：初始 first = 200；缩放到 `avail` = 1000 → 250；缩小到 `avail` = 300 → 75，夹紧为 100（second = 200）。`fixed_first(150)`：缩放到 1000 → first 150、second 850。`fixed_second(300)`：初始 500/300；缩放到 1000 → 700/300；缩小到 `avail` = 350 → 请求 first = 50，夹紧为 100（second = 250）。上述缩放中控件保存的 `SplitPos` 未被布局改写（读取前后相等），`splitMetrics` 报告夹紧后的实际值。

**AC-LAYOUT-019**　`[单元]` 覆盖：REQ-LAYOUT-038、REQ-LAYOUT-039、REQ-LAYOUT-040。前置：Table 宽 600，列：`fixed(100)`、`auto_header`、`grow(1)`、`grow(2)`；表头第 2 列单元格自然宽 80，第 2 行以后该列单元格自然宽 200（不应影响列宽）；`col_gap` = none。预期：列宽 100/80/140/280（剩余 420 按 1:2 分配）；三行的第 3 列矩形 x 完全相同（= 180）。行 `cross = fixed(22)` → 行高 22；行 `cross = fit`，单元格高 18/30/24 → 行高 30；`gap` md 时行间距 8。单元格 `main = fixed(50)`、`self_main_align = end` 在 140 宽的列中 x = 绝对列起点 + 90；单元格 `cross = fill` 占满行高；少于列数的行仅放置已有单元格；多于列数的单元格被忽略且调试构建报告 1 条。`solveColumns` 对同一输入返回相同的 100/80/140/280。宽度 500 且第 2 列 `min` = 120 → 100/120/93/187（剩余 280 按 1:2：93.33/186.67 → 93/187，余数给小数部分大者）。

**AC-LAYOUT-020**　`[单元]` 覆盖：REQ-LAYOUT-041。前置：Form 内部宽 400，`col_gap` = md（8），三行标签自然宽 40/90/60，字段 `grow`；第四项 `form_span`。预期：标签列宽 90，字段列宽 302（400 − 90 − 8）；三行标签 x = 0，字段 x = 98；span 项 x = 0、宽 400；`label_max` = 64 → 标签列 64，字段列 328；内部宽 100 时标签列上限 `min(240, 50)` = 50；行高取标签与字段高较大者，标签 20、字段 24 → 行高 24，标签垂直居中 y = 2；字段 `self_align = start` 且标签亦 start 时均为 y = 0；子项总数为奇数（5 个非 span 项）时最后一项作为字段，标签列留空。

**AC-LAYOUT-021**　`[单元]` 覆盖：REQ-LAYOUT-042、REQ-LAYOUT-005。前置：Stack 矩形 200×100，内含 Row（fit，高 20）与一个 Anchor（`target = parent`，`placement = (below, start)`，`bounds = parent`），Anchor 的子项为 40×16 的徽标。步骤与预期：Row 的期望尺寸与有无 Anchor 无关，Anchor 不产生 gap。锚矩形 = 父内部矩形 (0, 0, 200, 100)：below 候选 y = 100 越界，above 候选 y = −16 越界，两侧空间均为 0，取首选 below，平移夹紧后徽标矩形 (0, 84, 40, 16)。`target = rect(10, 10, 20, 20)` → 徽标 (10, 30, 40, 16)。在 Row 内放 Anchor 不改变相邻子项的位置。`hidden` 的 Row 子项：占位（后继兄弟位置不变）、不绘制、命中测试跳过；未声明的子项：后继兄弟前移且 gap 少一个。

**AC-LAYOUT-022**　`[单元]` 覆盖：REQ-LAYOUT-043。前置：`placeAnchored` 的 `bounds` = (0, 0, 1000, 800)，`gap` = 0，除注明外 `placement = (below, start)`。预期：① 锚 (100, 100, 80, 24)，size 200×300 → (100, 124, 200, 300)，`side_used = below`，`clamped = false`。② 锚 (100, 600, 80, 24)，size 200×300 → below 溢出，翻转 → (100, 300, 200, 300)，`side_used = above`。③ 锚 (950, 100, 40, 24)，size 200×300 → x 夹紧到 800 → (800, 124, …)，`clamped = true`。④ 锚 (100, 380, 80, 24)，size 200×500：below 与 above 均不适配，空间 below = 396 大于 above = 380，取 below，平移夹紧到 y = 300 → (100, 300, 200, 500)，`clamped = true`。⑤ size 200×900 → h = 800、y = 0，`height_limited = true`。⑥ `gap` = 4，锚 (100, 100, 80, 24) → y = 128。⑦ `(below, end)`：锚 (100, 100, 80, 24)，w = 200 → x = −20 夹紧为 0。⑧ `(below, center)` → x = 40。⑨ `(right, start)` 锚 (400, 100, 100, 22)，size 180×200 → (500, 100, …)；锚 (850, 100, 100, 22) → 右侧溢出，翻转 → (670, 100, …)，`side_used = left`。⑩ bounds 宽 300、锚 (100, 100, 100, 22)、`(right, start)`、size 280×50：右（x = 200）与左（x = −180）均不适配，空间各 100，相等取首选 right，平移夹紧 x = 20。⑪ 全部结果相同输入重复调用 1000 次，输出逐字段一致。 交叉轴翻转算例：`bounds` = (0, 0, 1000, 800)，锚 = (950, 100, 0, 0)，尺寸 200×100，`side = below`、`align_ = start`、`gap` 0。`flip_cross = false` → 矩形 (800, 100, 200, 100)，`clamped = true`；`flip_cross = true` → 矩形 (750, 100, 200, 100)（右缘对齐锚点），`clamped = false`；锚改为 (100, 100, 0, 0)、`flip_cross = true` → (100, 100, 200, 100)（不越界，不翻转）。

**AC-LAYOUT-023**　`[回放]` 覆盖：REQ-LAYOUT-044。前置：宿主窗口内一个下拉按钮（屏幕坐标 (100, 700, 120, 24)），显示器工作区 (0, 0, 1920, 1040)，弹出层内容为 Scroll 包裹的列表（自然高 600、自然宽 100），`match_anchor_width = true`。预期：弹出根宽 120；below 候选 y = 724，724 + 600 > 1040 不适配，翻转到 above → 矩形 (100, 100, 120, 600)，`height_limited = false`。把按钮移到 y = 520：below（y = 544，空间 496）与 above（y = −80，空间 520）均不适配，取空间较大的 above，平移夹紧 → (100, 0, 120, 600)，`clamped = true`。工作区改为 (0, 0, 1920, 400)、按钮 (100, 200, 120, 24)：两侧均不适配，取 above（空间 200 > 176），高度 600 > 400 → 弹出根矩形 (100, 0, 120, 400)，`height_limited = true`，内部 Scroll 出现垂直滚动条。按钮在宿主中被移动后，下一次布局弹出层随之重定位。

**AC-LAYOUT-024**　`[计量]` 覆盖：REQ-LAYOUT-045、REQ-LAYOUT-046、REQ-LAYOUT-048。前置：Column 含 200 个 Row，每个 Row 含 2 个叶子（共 601 个节点），已完成一次布局。步骤与预期：① 无任何变化重建 → `measured_nodes` = 0，`frame.nodes_measure_reused` 的增量 = 601。② 仅改变第 100 个 Row 的第 1 个叶子的 `content.key`（尺寸不变）→ `measured_nodes` = 3（该叶子、其 Row、Column），`frame.nodes_measure_reused` 的增量 = 598（其余 199 个 Row 的 597 个节点加兄弟叶子 1 个）。③ 改变某叶子的 `padding` → `layout_hash` 变化，行为同②。④ `scale` 由 1.0 变 1.25 → `frame.nodes_measure_reused` 的增量 = 0，`measured_nodes` = 601。⑤ 仅改变某 Scroll 的 `offset` 或某 Splitter 的 `SplitPos` → 该节点及其祖先的 `layout_hash` 不变。⑥ 仅改变某叶子的 `paint_key` 或使其悬停 → `layout_hash` 不变，`measured_nodes` = 0。

**AC-LAYOUT-025**　`[单元]` 覆盖：REQ-LAYOUT-047。前置：Scroll（1 个）内含 Column，Column 含 200 个 Row，每个 Row 含 2 个尺寸为 fixed 的叶子（共 602 个节点），已完成一次布局。步骤与预期：只改变 Scroll 的请求偏移 → `arranged_nodes` = 1（仅 Scroll 更新其内容子项的位置，Column 的子树沿用）。Scroll 的指派宽度减少 1 ppx → `arranged_nodes` = 202（Scroll、Column、200 个 Row；叶子尺寸不变而被沿用）。某叶子 `content.key` 变化（尺寸不变）→ `arranged_nodes` = 4（该叶子、其 Row、Column、Scroll，因 Merkle 哈希使这些祖先的测量重新进行），其余沿用。

**AC-LAYOUT-026**　`[单元]` 覆盖：REQ-LAYOUT-049。前置：一个设置 `layout_feedback` 的节点按 `lastRect` 宽度决定子项数。步骤与预期：首帧（`lastRect` 为 null）→ 布局后检查点判定"不同"，执行第二构建遍，之后再次布局；宽度改变后的帧同样一次第二遍；宽度不变的帧 → 构建遍数 0；第二遍布局后宽度仍与所见不同 → 不再执行第三遍，`build` 脏被置位；未调用 `lastRect` 的反馈节点视为所见为空；`layout_feedback` 的检查发生在损伤计算之前（用阶段日志验证，与 AC-FRAME-017 联合）。

**AC-LAYOUT-027**　`[回放]` 覆盖：REQ-LAYOUT-052。前置：含 Row/Column/Scroll/Splitter 的界面，`scale` 1.0，其中一个节点为 `fixed(100)` 宽。步骤：把窗口缩放因子依次改为 1.25、1.5、1.75、2.0 并改回 1.0。预期：每次 DPI 变化所在的帧 `frame.nodes_measure_reused` 的增量 = 0；该节点宽依次为 125/150/175/200 ppx，回到 1.0 后为 100；回到 1.0 后全部矩形与首次逐一相同；任一 `scale` 下各节点矩形的 ppx 值与"以该 scale 直接新建窗口"的结果相同。

**AC-LAYOUT-028**　`[金图]` 覆盖：REQ-LAYOUT-002、REQ-LAYOUT-003、REQ-LAYOUT-019、REQ-LAYOUT-024。渲染"布局标尺页"（含 Row/Column/Stack/Scroll/Splitter/Table/Form 各一，子项以发丝线描边的色块表示）在 `scale` 1.0/1.25/1.5/2.0。预期：与基准图一致；每个色块的四条边落在整数像素边界（逐像素检查无半透明边）；溢出的子项在容器边界处被裁剪（无绘制到容器外）；兄弟色块之间的缝隙宽度在同一 `scale` 下处处相同。

**AC-LAYOUT-029**　`[单元]` 覆盖：REQ-LAYOUT-006、REQ-LAYOUT-007、REQ-LAYOUT-008。扫描 `layout.Params`、`ContainerOptions` 与全部种类参数的字段名与类型。预期：不存在名为 `wrap`、`margin`、`z_index`、`baseline`、`percent` 的字段，也不存在百分比类型的 `Extent`；`Params` 默认值与第 3.2 节表一致（逐字段断言）；`ui.spacer` 产生 `main = grow(w)` 的叶子。

**AC-LAYOUT-030**　`[单元]` 覆盖：REQ-LAYOUT-004、REQ-LAYOUT-009。构造三个容器：Row（fit，内部宽无界）含 `grow(1)` 子项（`main_min` = 30）；同一 Row 以确定限制宽 300 测量；Row 位于 fit 的 Column 内，含 `fill` 交叉轴子项且 Row 自身高度无界。预期：第一种情形 grow 子项宽 30；第二种为 300 − 其他子项；第三种 fill 子项的期望高度等于其自然高度，排布时扩展到 Row 内部高度；`grow(0)` 与 `grow(-1)` 均只得 `main_min`，调试构建断言。

**AC-LAYOUT-031**　`[单元]` 覆盖：REQ-LAYOUT-054。前置：虚拟化 Scroll，视口高 660 ppx，行高 22 ppx，`virtual_extent_px` 高 = 22 000 000（100 万行），`scale` 1.0。步骤与预期：① 请求 `offset_px.y = 21 999 340` → 夹紧后 `offset_px.y = 21 999 340`（= 内容高 − 视口高），首个可见行下标 = 999 970，其 `virtual_pos_px.y` = 0，末行底边恰在 660。② 请求 `offset_px.y = 16 777 217`（2^24 + 1）→ 夹紧后原值不变；首个可见行下标 = 762 600，其 `virtual_pos_px.y` = −17；再请求 +1 → 该行位置为 −18（逐像素精确，无跳变）。③ 遍历此时树中全部节点，矩形坐标的绝对值均 ≤ 视口尺寸 + 缓冲行高度。④ `scale` 1.5、行高 33 ppx、3300 万内容高下重复①，结果按相同公式成立。

**AC-LAYOUT-032**　`[回放]` 覆盖：REQ-LAYOUT-055。前置：纵向 Scroll（内容高于视口）与一个水平 Splitter（应用声明两个窗格）。预期：保留树中 Scroll 节点下存在槽与滑块两个部件节点，Splitter 节点下存在一个分隔条节点，其主轴尺寸 = `splitter_w` 换算值，且恰位于两窗格之间；连续两次构建部件节点 ID 不变；指针移到滑块上 → 命中节点为滑块节点，移到分隔条上 → 命中分隔条节点，移到窗格空白处 → 命中的不是 Splitter 的分隔条；应用为 Splitter 声明 3 个子项 → 调试构建断言中止。

**AC-LAYOUT-033**　`[单元]` 覆盖：REQ-LAYOUT-056。前置：容器 100×100 ppx，`padding` 0，`border = 1`，一个 `fill` 子项。预期：`scale` 1.0 / 1.5 / 2.0 / 3.0 下子项矩形相对容器四边各内缩 1 / 1 / 2 / 3 ppx；`border = 2`、`scale` 1.5 → 内缩 2 ppx；`border` 与 `padding = 4 lpx` 并用、`scale` 1.5 → 内缩 1 + 6 = 7 ppx。

## 7. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-LAYOUT-01 | 是否提供 Scroll 内部的子项吸附（snap）与"固定头部"（sticky header） | 不提供；重型表格/列表控件自行处理表头 |
| OPEN-LAYOUT-02 | 弹出层 `match_anchor_width` 之外是否需要按内容的最小宽度夹紧到锚矩形宽度的倍数 | 否；`min_width` 足够 |
| OPEN-LAYOUT-03 | Form 的标签列是否允许跨多个 Form 对齐（同一页面的多个分组框共享标签列宽） | 先不做；用单个 Form 加 `form_span` 小标题代替 |
| OPEN-LAYOUT-04 | 子项 `fit_shrink` 是否扩展到容器（目前只有叶子） | 先不做；见 REQ-LAYOUT-011 的理由 |
| OPEN-LAYOUT-05 | 弹出根测量时工作区边距（避开任务栏阴影）是否额外内缩 | 取 03 提供的工作区原值 |
