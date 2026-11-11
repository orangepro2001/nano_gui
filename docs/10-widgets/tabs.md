# 标签页（tabs）

## 1. 用途

用一排标签在同一块区域内切换若干页内容，一次只显示一页。标签条在上，当前页的内容区在下。参照 Windows 的 Tab Control（`SysTabControl32`）与属性页（Property Sheet）。

- 页数固定且很少、需要同时比较内容 → 用并排的 group-box。
- 文档式的、可关闭可增删的标签 → 本控件的 `closable`；标签的**拖动重排**不在本版（OPEN-W-TABS-01）。
- 页数很多（几十页）→ 用列表或树导航，而不是标签页；本控件在标签放不下时把溢出的标签收进末端的溢出菜单（ADR 0007，不换行、不滚动），不适合作为大量页的主导航。
- 需要多行标签 → 不支持（ADR 0007 不做 wrap）。

## 2. 解剖

```
 ┌──────────────┐┌──────────┐┌────────────┐                 ┌────┐
 │▀▀▀▀▀▀▀▀▀▀▀▀▀▀││  常规    ││ 高级(&A) ✕ │                 │ ⋯  │   ← 标签条：标签 + 末端溢出按钮
 │  外观 (当前)  │└──────────┘└────────────┘                 └────┘
 ├──────┴───────┴───────────────────────────────────────────────────┐
 │                                                                  │   ← 内容区（drawPanel）；
 │  当前页内容（只构建当前页）                                          │      当前标签处上缘不画线
 └──────────────────────────────────────────────────────────────────┘
   ▀▀▀ = 当前标签顶部的 accent_mark 指示条（滑动）
```

- **标签条**：一排**标签**，位于内容区之上；末端可有**溢出按钮**。
- **标签**：文字（可选图标、可选关闭按钮）；当前标签为粗体并带指示条。
- **指示条**：当前标签顶部的强调色条，切换时滑动。
- **溢出按钮 / 溢出菜单**：标签放不下时出现。
- **内容区**：`drawPanel` 的面板，只承载当前页的内容。

## 3. 度量与布局

| 项 | 取值（令牌） |
|---|---|
| 标签高度 | `control_h` |
| 标签左右内边距 | `pad_control_x` |
| 标签图标 / 关闭标记 | `icon_sm` / `icon_sm`（`close` 标记） |
| 标签内部间距（图标—文字—关闭按钮） | `gap_sm` |
| 标签之间的间距 | `gap_xs` |
| 标签文字样式 | 当前 `font_body_strong`，其余 `font_body`（宽度一律按 `font_body_strong` 测量，REQ-W-TABS-006） |
| 指示条厚度 | `tab_indicator_h` |
| 溢出按钮 | 宽 `control_h`、高 `control_h`，`more` 标记 |
| 标签 / 内容区 | 标签 `drawTab`；内容区 `drawPanel`，圆角 `radius_container`，内边距 `pad_panel` |
| 绘制外延 | 标签：`focus_ring_w` |

**REQ-W-TABS-001**　默认尺寸策略：水平方向 `fill`，垂直方向 `grow(1)`（物理方向，由控件按 `ui.parentAxis()` 映射，见 REQ-W-LABEL-001；父容器在垂直方向为 `fit` 且无确定高度时退化为内容的期望高度）。标签条高度固定为 `control_h`；内容区占标签条以下的全部高度。调用方**可以**经通用布局选项覆盖。内容区的期望尺寸取**当前页**内容的期望尺寸加内边距，因此页间内容高度不同时，在非 `grow` 的父容器中布局会随页切换而变化（建议调用方指定 `grow` 或 `fixed`）。

**REQ-W-TABS-002**　**结构（两遍声明）**：应用调用 `const t = w.beginTabs(ui, @src(), tabs: []const TabSpec, current: *usize, opts)`，**一次性**给出全部标签（`TabSpec{ label, icon, closable, enabled, key }`）；框架据此创建一个 Column 型的标签页根节点，其下依次是：**标签条节点**（独立的 Row 型节点，子节点为各可见标签与末端的溢出按钮，标签与溢出按钮的节点由框架在构建期创建）和**内容区容器**（`drawPanel` 面板）。随后应用在 `beginTabs` 与 `endTabs` 之间只声明**当前页**的内容（通常 `switch (t.current) { … }`），这些节点是内容区容器的子节点，其 ID 种子取**当前页的键**（`TabSpec.key`，缺省为页索引）（REQ-FRAME-003），使不同页中相同调用点的控件得到不同的 ID；最后 `w.endTabs(ui)`。标签条节点在先序中位于内容区容器之前，故 Tab 序为：标签条（一个停靠点）→ 当前页内容。`beginTabs`/`endTabs` 不配对是编程错误（REQ-FRAME-028）。

**REQ-W-TABS-003**　**页的标识与当前页**：页由 `tabs` 切片的顺序（0 起的索引）标识，页键为 `TabSpec.key`（缺省取索引）；同一切片内页键**必须**互不相同，否则调试构建断言。`TabsResult.current` 是当前页索引。当前页索引 ≥ `tabs.len`（如关闭了最后一页但应用未更正）时视为**没有当前页**：全部标签显示为非当前、内容区为空，调试构建记录一条 `warn`；控件**不**自行改写应用的索引。

**REQ-W-TABS-004**　**两种持有方式**：（一）**应用持有**：`beginTabs(ui, src, tabs, current: *usize, opts)`，当前页索引存放在应用的变量中；用户切换页时，控件在报告 `changed` 的那次调用内先写入 `current.*` 再返回，应用在同帧第二构建遍中读到新值。（二）**框架保留**：`beginTabsRetained(ui, src, tabs, initial: usize, opts)`，当前页索引由框架保存在 sticky 状态槽（REQ-FRAME-010），首次出现时取 `initial`，之后由用户切换改变；应用通过 `TabsResult.current` 读取。两者在外观与行为上完全相同。`TabsResult` 给出 `current`、`changed`、`close_requested: ?usize`。

**REQ-W-TABS-005**　**只构建当前页的内容；其他页的 sticky 状态保留**：应用只在 `beginTabs`/`endTabs` 之间声明当前页的内容。未被声明的页的 transient 状态槽与悬停/按下/焦点状态按 REQ-FRAME-010 在该次构建结束时回收；其 sticky 状态槽（滚动位置、文本框的撤销栈、树的展开集合等）**不**立即回收，进入 LRU 队列，因此切回该页时内容状态仍在（队列满 4096 槽后最久未触达者被回收）。页内容被切走时，持有焦点的页内控件按 REQ-INPUT-042 转移焦点（见 REQ-W-TABS-015）。标签条节点与溢出按钮不属于页内容，不随页切换而重建。

**REQ-W-TABS-006**　**标签条几何**：标签自左向右排列，间距 `gap_xs`，标签条左缘与内容区左缘对齐。标签宽度 = `max(control_h, 2 × pad_control_x + (有图标时 icon_sm + gap_sm) + 文字宽 + (可关闭时 gap_sm + icon_sm))`，文字宽为去除助记符标记后的文本以 **`font_body_strong`** 测得的宽度（所有标签，不论是否为当前页，使切换当前页时标签宽度与位置不变）。当前标签与非当前标签的文字均垂直居中，基线按 REQ-THEME-017。文字、图标与关闭按钮在标签内依次排列，文字区可被截断（REQ-W-TABS-018）。

**REQ-W-TABS-007**　**内容区几何与当前标签的"接合"**：标签页根节点是 Column：标签条（高 `control_h`）在上，内容区容器占剩余高度与全宽，以 `drawPanel(内容区矩形, radius_container)` 绘制；页内容节点按 Column 排列，内边距 `pad_panel`，间距 `gap_md`。当前标签由 `drawTab(标签矩形, true, visual)` 绘制，其 `surface_panel` 填充向下延伸到内容区上缘；**接合不依赖声明顺序覆盖**：内容区容器的绘制函数在画面板时**不画**上边线中与当前标签水平区间对应的一段（区间由当前标签节点的最终矩形给出，缩进一个发丝线宽），使当前标签与内容区连成一体（REQ-THEME-041）；非当前标签下方保留该上缘线。没有当前页或当前标签被溢出而不可见时，上边线完整绘制。

**REQ-W-TABS-008**　**当前标签的表现**：当前标签文字使用 `font_body_strong`，其标签背景由 `drawTab(…, true, …)` 绘制；并在其**顶边内侧**画 `accent_mark` 的**指示条**（`drawTrackFill(…, accent)`，厚 `tab_indicator_h`，宽 = 标签宽度，REQ-THEME-041）；非当前标签使用 `font_body`、`drawTab(…, false, …)`（无填充无边框，悬停时 `surface_row_hover`）、不画指示条。切换当前页时指示条从旧标签的位置**滑动**到新标签（水平位移与宽度同时过渡，`dur_normal`、`ease_out`，paint 级，REQ-W-TABS-019）；其间新旧文字样式在切换事件所在帧即更换，不参与动画。

**REQ-W-TABS-009**　**标签过多时的溢出**：标签条**不换行、不滚动**（ADR 0007）。可用宽度 `W` = 标签条宽度。若全部标签的总宽（含间距）≤ `W`，全部显示、无溢出按钮。否则末端出现**溢出按钮**（宽 `control_h`，与最后一个标签间隔 `gap_xs`），标签可用宽度 `Wt = W − control_h − gap_xs`；显示的标签是一个**含当前标签的连续区间** `[s, e]`：`s` 取使"自 `s` 到当前标签的总宽 ≤ `Wt`"成立的最小值（当前页为 0 时 `s = 0`，即标签前缀），`e` 取使总宽仍 ≤ `Wt` 的最大值。可见区间在构建期（`beginTabs` 内）以 `text.measure` 得到全部标签的宽度后判定，据此只为可见标签创建节点。不在 `[s, e]` 内的标签不显示，它们的标签**不声明为节点**，改由溢出菜单承载（REQ-W-TABS-010）。当前标签单独就比 `Wt` 宽时只显示它并将其文字截断（REQ-W-TABS-018）。没有当前页时按 `s = 0` 取最大前缀。

**REQ-W-TABS-010**　**溢出按钮与菜单**：溢出按钮外观为 quiet 按钮（button 的 `quiet` 变体，`more` 标记，提示"更多标签"）；点击或持有焦点时按 Enter/Space 打开**溢出菜单**（`ui.beginPopup`，`kind = .menu`，锚点为该按钮，向下对齐，ADR 0008）。菜单列出**所有被隐藏的**标签（按声明顺序，含其图标、文字，已禁用的标签显示为禁用项）；选中一项等于切换到该页（报告 `changed`），菜单随即关闭，且该页因 REQ-W-TABS-009 而出现在可见区间内。菜单的键盘导航、延迟与关闭规则遵循 menu 控件规范（menu.md）。溢出按钮是标签条的**最后一个子节点**，属于标签条的漫游焦点组（REQ-W-TABS-014），不是独立的 Tab 停靠；Tab 序与视觉位置一致（标签 → 溢出按钮，随后是页内容）。

**REQ-W-TABS-011**　**溢出的判定在同一帧内收敛**：溢出判定在构建期完成：以 `text.measure` 得到全部标签宽度（REQ-W-TABS-006）与标签条可用宽度 `W`。标签条节点设布局反馈标志（`layout_feedback`），构建时以 `ui.lastRect` 读取其宽度 `W`；首次出现（`lastRect` 为 `null`）视为 `W = ∞`（全部显示），布局后因宽度不同触发同帧第二构建遍并按真实宽度重判（REQ-FRAME-031）。窗口宽度变化使可见区间变化的那一帧，构建遍数 ≤ 2（REQ-FRAME-032）；宽度变化而可见区间不变的帧构建遍数 ≤ 1；宽度不变的帧构建遍数不因溢出判定而增加。

## 4. 变体与参数

整体（`beginTabs` / `beginTabsRetained` 的 `TabsOptions`）：

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `enabled` | `bool` | `true` | 为假时整个控件（标签条与内容区）禁用，后代一并有效禁用（REQ-INPUT-049） |
| `a11y_name` | `?[]const u8` | `null` | 无障碍名称 |
| `key`、`debug_name`、`layout` | 通用 | | 见模板 |

单个标签（`TabSpec` 的字段，随 `tabs` 切片一次性给出）：

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `icon` | `?theme.Icon` | `null` | 前置图标 |
| `closable` | `bool` | `false` | 为真时标签带关闭按钮，并响应中键、Delete、Ctrl+F4 关闭请求 |
| `label` | `[]const u8` | — | 标签文字，含 `&` 助记符语法；借用至本帧结束 |
| `enabled` | `bool` | `true` | 为假的标签不可选中、不可聚焦，被循环切换与方向键跳过 |
| `key` | `?ui.Key` | `null` | 页键：页内容的 ID 种子与标签节点 ID 的组成部分；缺省取页索引；标签会增删或重排时**应当**给稳定的键（REQ-FRAME-004） |

当前页索引不是选项（REQ-W-TABS-004）。控件没有外观变体；标签条只在内容区上方（不提供底部、侧边标签条）。

## 5. 状态

### 5.1 状态机

状态变量（每个标签）：`armed_close ∈ {无, 鼠标}`（关闭按钮的"已按下待释放"）。当前页、悬停、聚焦、禁用分别由 `*usize`（或框架保留槽）与框架维护；标签本身**按下即选中**。

| 当前 | 事件 | 条件 | 下一 | 动作 |
|---|---|---|---|---|
| — | 左键按下于某标签（非关闭按钮区） | 标签启用 | — | 该标签成为当前页（若原来不是）：写入索引，报告 `changed`；获得焦点（不可见）；隐式捕获 |
| — | 左键按下于当前标签 | — | — | 无页切换；获得焦点 |
| `armed_close = 无` | 左键按下于关闭按钮 | 标签启用 | 鼠标 | 隐式捕获；**不**选中该标签 |
| `armed_close = 鼠标` | 左键释放 | 指针在关闭按钮内 | 无 | 报告 `close_requested = 该索引` |
| `armed_close = 鼠标` | 左键释放于按钮外 / 捕获取消 | — | 无 | 无 |
| — | 中键释放于某可关闭标签 | 按下与释放均在同一标签内 | — | 报告 `close_requested = 该索引` |
| — | 焦点经 `group` 方向键移到某启用标签 | — | — | 该标签成为当前页，报告 `changed`（REQ-W-TABS-014） |
| — | Ctrl+Tab 等页循环键 | 启用标签 ≥ 2 | — | 切到下一/上一个启用标签，报告 `changed`，焦点移到它（REQ-W-TABS-014） |
| — | 选中溢出菜单某项 | — | — | 切到该页，报告 `changed` |
| — | Delete / Ctrl+F4 | 焦点在可关闭的标签上 | — | 报告 `close_requested = 该索引` |
| — | 助记符激活 | 标签启用 | — | 切到该页，报告 `changed`，焦点移到该标签 |

### 5.2 视觉表现

"显示为按下" = 指针在标签上按住左键。

| 状态 | 绘制（基元 + 令牌） |
|---|---|
| 非当前标签·常态 | `drawTab(标签矩形, false, visual)`：无填充无边框（位于标签条底边线之上）；文字、图标 `text_primary`，`font_body` |
| 非当前标签·悬停 | `drawTab` 悬停：填充 `surface_row_hover` |
| 非当前标签·显示为按下 | `visual.pressed` 传入 `drawTab`；内容下移 1 ppx（REQ-THEME-030） |
| 当前标签 | `drawTab(标签矩形, true, visual)`：填充 `surface_panel`、左右与上方 `border_strong` 发丝线、上方圆角 `radius_control`，底缘与内容区上缘线接合（REQ-W-TABS-007）；文字 `font_body_strong`、`text_primary`；顶边内侧指示条 `drawTrackFill(指示条矩形, accent)`（厚 `tab_indicator_h`） |
| 焦点可见 | 加 `drawFocusRing(标签矩形, radius_control)`；焦点环**只**在持有焦点的标签上 |
| 禁用标签 | 标签换禁用配方（`surface_raised_disabled`、`border_control_disabled`），文字、图标 `text_disabled`；当前标签被禁用时仍保留指示条与接合（形状表示选中） |
| 关闭按钮 | 位于标签右端，`close` 标记，`icon_sm`；常态 `text_secondary`；悬停时该标记区域以 `drawRaised(neutral)` 的悬停变体显示（quiet 凸起，REQ-THEME-031），按下换按下变体 |
| 溢出按钮 | quiet 按钮外观，`more` 标记 |
| 内容区 | `drawPanel`；禁用时外观不变，后代各自禁用 |
| 助记符下划线 | 显示时在标签的助记字符下画发丝线，颜色同文字（REQ-INPUT-047） |

## 6. 鼠标行为

**REQ-W-TABS-012**　**切换**：标签登记指针兴趣 `click`。左键在**启用**标签上**按下**时即切换：该标签成为当前页（写入索引、报告 `changed`），并立即显示为按下（`dur_instant`），不等释放（有意区别于按钮，对应 Windows 标签控件在按下时切换）；点击当前标签不报告 `changed`。按下即取得焦点，但焦点不可见（REQ-INPUT-022）。按下后拖出标签再释放不撤销切换。禁用标签上按下无效果。右键按下与释放不改变状态、不报告任何结果（标签无上下文菜单）；双击不特殊处理（按各次按下独立处理）；标签条与内容区的滚轮不处理，按 REQ-INPUT-019 冒泡；指针形状恒为箭头。

**REQ-W-TABS-013**　**关闭**：可关闭标签的关闭按钮登记 `click`，命中范围是 `icon_sm` 见方外加四周 `gap_xs`（不得超出标签矩形）。在其上按下进入 `armed_close = 鼠标`，**不**选中该标签；仅当释放时指针仍在关闭按钮内才报告 `close_requested`（激活类结果，携带索引）；**中键**在可关闭标签上的按下与释放均落在同一标签内时同样报告 `close_requested`；不可关闭的标签上中键无效果。控件**不**自行移除标签：应用据 `close_requested` 修改自己的数据并在下一次构建停止声明该标签（及按需更正当前页索引）。

## 7. 键盘行为

| 键 | 行为 |
|---|---|
| ← / → | 焦点在标签组内移动到前一个/后一个**启用且可见**的标签，并**立即切换**到它；首尾回绕 |
| Home / End | 焦点移到第一个/最后一个可见的启用标签并立即切换 |
| Ctrl+Tab / Ctrl+Shift+Tab | 切到下一页/上一页（启用标签中循环，含隐藏的标签），焦点移到新当前标签；焦点在标签页内**任意位置**都有效 |
| Ctrl+PageDown / Ctrl+PageUp | 同 Ctrl+Tab / Ctrl+Shift+Tab |
| Delete、Ctrl+F4 | 焦点在可关闭的标签上时，报告 `close_requested` |
| Alt+助记字符 | 标签文字含助记符时：切到该页，焦点移到该标签，焦点变为可见 |
| Enter / Space / Esc | 标签不处理（选中随焦点发生；Enter 可触发所在范围的默认按钮） |
| Tab / Shift+Tab | 标签条整体为一个停靠点（REQ-W-TABS-015，含溢出按钮）；Tab 离开标签条后进入当前页内容区内的控件 |

**REQ-W-TABS-014**　**方向键与页循环键**：**标签条节点**是漫游焦点组：`ui.focusGroup(标签条 ID, .{ .orientation = .horizontal, .wrap = true, .home_end = true, .current = 当前标签 ID })`（REQ-INPUT-038）。成员**只有**标签与溢出按钮（二者是标签条的子节点），**不含**页内容中的控件（内容区容器在标签条之外）。方向键在成员间移动：标签自身不声明处理方向键，落到组导航；标签在 `Interaction.focus_gained` 的原因为 `group` 时**立即切换**到自己（报告 `changed`），原因为 `tab`、`pointer`、`programmatic`、`restore`、`transfer`、`initial` 时不切换（Tab 进入组总落在当前标签）；焦点经方向键到达溢出按钮时不切换页，也不打开菜单（Enter/Space 才打开）。`Ctrl+Tab` / `Ctrl+Shift+Tab` / `Ctrl+PageDown` / `Ctrl+PageUp` 由标签页**根节点**经 `InteractOpts.handles.extra` 逐个列出这四个 Ctrl 组合并声明处理（⑤ 级，冒泡，REQ-INPUT-030），因此焦点位于标签条或内容区内任意后代时均有效；仅当启用的标签 ≥ 2 时声明；最内层的标签页先处理（嵌套时内层优先）。切换后下一次构建中新当前标签以 `ui.setFocus` 获得焦点（原因 `programmatic`，焦点可见保持原值）。方向键只在**可见**标签间移动；要到达隐藏的标签用溢出菜单或页循环键（OPEN-W-TABS-03）。

**REQ-W-TABS-015**　**焦点**：标签条在 Tab 序中只有**一个**停靠点（当前标签；无当前页时第一个启用的标签），溢出按钮是同一漫游组的成员而非独立停靠点；当前页内容区内的控件按其自身规则排在标签条之后（先序与视觉位置一致）。标签条不是焦点范围。页切换使原页内持有焦点的控件失格时，焦点按 REQ-INPUT-042 的确定性算法转移（旧页中的控件消失，焦点落到先序前驱存活节点之后的第一个停靠点，通常是新页内的第一个控件）；经页循环键切换时焦点另被设置到新当前标签（REQ-W-TABS-014）。焦点环仅在焦点可见时绘制（REQ-INPUT-040、REQ-THEME-023）。获得、失去焦点本身不产生激活类结果（切换见 REQ-W-TABS-014）。

**REQ-W-TABS-016**　**助记符**：标签文字中的助记符按 REQ-INPUT-046 解析并经 `ui.mnemonic(标签 ID, ch, .activate)` 登记；激活时切到该页并聚焦该标签，`activated = .mnemonic`；下划线显示遵循 REQ-INPUT-047；禁用的标签不登记助记符；同一 Alt+字符对应多个匹配节点时只移动焦点而不激活（REQ-INPUT-048）。被隐藏（溢出）的标签不声明为节点，因而**不**登记助记符。

## 8. 焦点

见 REQ-W-TABS-014、REQ-W-TABS-015；标签页内部的"内部焦点"即上述标签组的漫游。内容区内的控件按其自身规范处理焦点。

**REQ-W-TABS-017**　**禁用**：`enabled = false`（整体）时标签条与内容区一并禁用，标签组与溢出按钮不再是停靠点，页循环键不声明；当前标签仍显示为选中。某个标签 `enabled = false` 时该标签不可选中、不可聚焦、不参与方向键与页循环，但保持其选中状态（若为当前页）。当前页被禁用而用户无法离开时，应用负责启用或切换。

## 9. 文本与输入法

标签显示单行文字，不接受文本输入；聚焦时输入法处于禁用状态。

**REQ-W-TABS-018**　**截断与提示**：标签文字中的换行符与制表符按空格；某标签因 REQ-W-TABS-009 的"当前标签单独就比 `Wt` 宽"而被截断时，文字以尾部省略号截断（REQ-THEME-018），图标与关闭按钮不缩小；被截断的标签悬停时以提示框显示完整文字（去除助记符标记），经 `ui.tooltipIfTruncated(标签节点 ID, 完整文字, 样式)` 声明（REQ-INPUT-057 的补充规则）。关闭按钮的提示固定为"关闭"。未截断的标签不出现提示框。标签文字为空串且无图标是编程错误（调试构建断言，发布构建显示最小宽度的空标签）。

## 10. 动效

| 属性 | 触发 | 时长令牌 | 缓动 | 影响级别 |
|---|---|---|---|---|
| 非当前标签填充与边框（常态 ↔ 悬停） | 悬停变化 | `dur_fast` | `ease_out` | paint（框架内建，`Visual.hover_t`） |
| 标签（→ 按下） | 显示为按下 | `dur_instant` | — | paint（`Visual.press_t`） |
| 标签（按下 →） | 结束按下 | `dur_fast` | `ease_out` | paint |
| 焦点环 | 焦点变为可见 | `dur_fast` 淡入，消失瞬时 | `ease_out` | paint（`Visual.focus_t`） |
| 指示条位置与宽度 | 当前页变化 | `dur_normal` | `ease_out` | paint（自有动画槽 0 = 位置，1 = 宽度） |

**REQ-W-TABS-019**　指示条以 `ui.animate(根 ID, 0, 目标 x, .{ .duration = .normal, .easing = .out, .level = .paint })` 与 `ui.animate(根 ID, 1, 目标宽, …)` 过渡位置与宽度（位移可能大于 16 lpx 时仍只作用于指示条这一小范围的位移，REQ-THEME-020）；首次出现无入场动画；过渡途中再次切换从当前值重新开始；**当前页**、内容区的显示与 `changed` 在事件所在帧立即生效，不等动画；标签的布局矩形在动画期间不变。系统关闭动画时直接到达目标（REQ-FRAME-047）。溢出区间变化（REQ-W-TABS-009）导致指示条目标标签换位时同样直接取新位置并不过渡。

## 11. 无障碍

| 项 | 值 |
|---|---|
| UIA 控件类型 | 整体：Tab；标签：TabItem；溢出按钮、关闭按钮：Button |
| 名称来源 | 整体：`a11y_name`；标签：去除助记符标记的文字；关闭按钮："关闭 " + 标签名；溢出按钮："更多标签" |
| 支持的模式 | 整体：Selection（CanSelectMultiple 假、IsSelectionRequired 真）；标签：SelectionItem（Select、IsSelected、SelectionContainer 指向整体）；关闭、溢出按钮：Invoke |
| 状态属性 | IsEnabled、HasKeyboardFocus、AccessKey（形如 "Alt+A"）、IsSelected；被溢出隐藏的标签仍作为 TabItem 暴露，其 `IsOffscreen` 为真，Select 仍有效（等价于经溢出菜单切换） |

**REQ-W-TABS-020**　经 UIA SelectionItem.Select 触发的切换**必须**与点击等效：在下一帧报告一次 `changed` 并写入索引；对隐藏标签的 Select 同样有效且使其出现在可见区间内。经 UIA Invoke 触发的关闭按钮等效于一次点击：下一帧报告 `close_requested`。IsSelected **必须**随当前页索引同步（含应用直接写入的变化）；当前页之外的页内容不在无障碍树中。

## 12. API 草案

```zig
// 草案：仅签名
pub const TabsOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    a11y_name: ?[]const u8 = null,     // 借用至本帧结束；框架复制
    layout: layout.ItemOptions = .{},  // 各控件共用（07）
};

pub const TabSpec = struct {
    label: []const u8,                 // 借用至本帧结束；含 `&` 助记符语法；框架复制所需部分
    icon: ?theme.Icon = null,
    closable: bool = false,
    enabled: bool = true,
    key: ?ui.Key = null,               // 页键：页内容 ID 种子；null = 页索引
};

pub const TabsResult = struct {
    // 持续性状态
    current: usize,                    // 当前页索引（用户本帧切换后由第二构建遍给出新值）
    focused: bool,                     // 焦点是否在标签条内
    overflowing: bool,                 // 当前是否有标签被收进溢出菜单
    // 激活类结果（触发同帧第二构建遍，REQ-FRAME-030）
    changed: bool,                     // 用户切换了当前页（新索引即 current.* / TabsResult.current）；一步即完成，不报告 committed（REQ-CONV-010）
    close_requested: ?usize,           // 用户请求关闭该索引的标签（应用负责移除）
    activated: ?input.ActivateSource,  // changed 由助记符机制触发时非空
};

/// 应用持有当前页索引：tabs 切片借用至本帧结束（框架复制所需部分）；current 由调用方持有并须存活至 endTabs，框架不保留；
/// 用户切换页的那次调用内控件先写入 current.* 再报告 changed。
/// 框架创建标签条节点（漫游组，子节点为各可见标签与溢出按钮）与内容区容器；
/// 之后应用只声明当前页的内容（ID 种子取当前页的键），最后 endTabs。
pub fn beginTabs(ui: *Ui, src: std.builtin.SourceLocation, tabs: []const TabSpec, current: *usize, opts: TabsOptions) TabsResult;

/// 框架保留当前页索引（sticky 状态槽）：首次出现取 initial，之后由用户切换改变。
pub fn beginTabsRetained(ui: *Ui, src: std.builtin.SourceLocation, tabs: []const TabSpec, initial: usize, opts: TabsOptions) TabsResult;

pub fn endTabs(ui: *Ui) void;
```

`changed`、`close_requested`、`activated` 是激活类结果，为真时触发同帧第二构建遍，在第二遍中为假（REQ-FRAME-033），当前页索引在第二遍中已是新值；`current`、`focused`、`overflowing` 是持续性状态。当前页索引由应用持有（`beginTabs`）或框架保留（`beginTabsRetained`），不会同时由两者持有。典型用法：

```zig
const specs = [_]w.TabSpec{
    .{ .label = "常规(&G)" },
    .{ .label = "高级(&A)", .closable = true },
};
const t = w.beginTabs(ui, @src(), &specs, &model.page, .{});
switch (t.current) {            // 只声明当前页的内容
    0 => { /* 第 0 页内容 */ },
    1 => { /* 第 1 页内容 */ },
    else => {},
}
w.endTabs(ui);
```

## 13. 保留状态

| 字段 | 类型 | 保留级别 | 说明 |
|---|---|---|---|
| `selected` | `usize` | sticky | 仅 `beginTabsRetained`：当前页索引 |
| `armed_close` | `?usize` | transient | 关闭按钮已按下待释放的标签索引（即框架的捕获状态） |
| `focus_pending` | `?usize` | transient | 页循环键切换后待获得焦点的标签索引 |
| 各页内容的状态槽 | — | 由内容控件各自决定 | 非当前页的 sticky 槽保留、transient 槽回收（REQ-W-TABS-005） |

悬停/按下/焦点过渡为框架内建状态（REQ-FRAME-013）；指示条位置与宽度由框架动画槽 0 与 1 保存（REQ-FRAME-045）。应用持有版本中当前页索引归应用所有。

## 14. 失效规则

**REQ-W-TABS-021**　绘制键**必须**由以下各项构成：各可见标签的文字内容、图标、`closable`、`enabled`、是否为当前页、可见区间 `[s, e]`、是否有溢出按钮、是否被截断。标签页根节点的助记符下划线是否显示不进入绘制键：它由绘制函数在绘制时读取，其变化按 REQ-INPUT-047 整窗置 `paint`。布局输入哈希由当前页索引与各标签的文字内容构成（内容区期望尺寸取决于当前页）；内容区子项由各自的哈希折叠（REQ-LAYOUT-045）。

| 变化 | 置脏级别 | 损伤范围 |
|---|---|---|
| 标签的悬停进入/离开、显示为按下的变化、焦点环显隐 | `paint` | 该标签绘制范围（含外延） |
| 鼠标按下、释放、方向键（进入收件列表） | `build` | 由差分决定；若无外观变化则为空 |
| 当前页变化 | `build` | 新旧当前标签矩形、指示条所经范围、内容区 |
| 指示条过渡的每个动画帧 | `paint`（动画槽 0、1） | 指示条所在的标签条矩形 |
| 标签文字变化且宽度不变 | `build`（由应用的模型通知引起） | 该标签矩形 |
| 标签文字变化导致宽度或可见区间变化 | `build` | 标签条矩形 |
| 窗口宽度变化使可见区间变化 | `layout`，布局反馈触发第二构建遍（REQ-W-TABS-011） | 标签条矩形 |
| 键盘提示下划线显隐（按下 Alt） | `paint`（整窗，REQ-INPUT-047）；绘制函数读取当前的键盘提示可见性 | 整窗 |

**REQ-W-TABS-022**　仅悬停进入/离开一个标签所产生的帧**必须**是纯绘制帧（构建遍数 0），且损伤不超出该标签的绘制范围；指示条过渡期间的每个动画帧同样是纯绘制帧，且各帧的布局矩形集合完全相同。切换当前页只重建当前页的内容：被切走的页的节点不进入新树，切回时其 sticky 状态仍在。

## 15. 边界与错误情况

| 情况 | 规定 |
|---|---|
| 标签数为 0 | 标签条高度保持 `control_h`，无标签；内容区为空；调试构建记录一条 `warn` |
| 当前页索引越界 | 见 REQ-W-TABS-003：无当前页，不改写应用索引 |
| 关闭当前页（应用移除该标签并改索引） | 由应用更正索引；若应用未更正，按越界处理 |
| 按下期间标签从树中消失 | 捕获释放（REQ-INPUT-024）；若已切换则切换保留；未报告 `close_requested` |
| 按下关闭按钮期间标签变为禁用 | 取消，不报告 `close_requested` |
| 同一帧内鼠标按下切换与 Ctrl+Tab | 按事件序依次处理；`changed` 合并为一次，以最后的结果为准 |
| 切换页的同一帧内页内控件的激活类结果 | 事件只投递一次；页内控件若已不在第二遍树中，其结果随之丢弃 |
| `beginTabsRetained` 的 `initial` 越界 | 按越界处理（无当前页）并调试构建 `warn` |
| 所有标签均被禁用 | 保持当前页；无停靠点，页循环键与方向键不声明；溢出菜单项均为禁用 |
| 窗口缩小到连溢出按钮也放不下 | 只保留溢出按钮（或其被裁剪的部分），当前标签不显示；内容区仍显示当前页 |
| `tabs` 切片内页键重复 | 调试构建断言（REQ-W-TABS-003）；发布构建后出现者复用前者的状态槽并记录 `err` |
| 窗口非活动时悬停 | 仍显示悬停外观；点击先激活窗口，该次点击照常作用于标签 |

## 16. 验收标准

**AC-W-TABS-001**　`[金图]` 覆盖：REQ-W-TABS-001、REQ-W-TABS-006、REQ-W-TABS-007、REQ-W-TABS-008。渲染一个 400×200 lpx 的标签页：三个标签（"常规"、带图标的"外观"、带关闭按钮的"高级"），当前页分别取第 0、1、2 个；缩放 1.0/1.25/1.5/2.0，浅/深/高对比度。预期：与基准图一致；几何断言——标签高 = `control_h`；标签宽 = `max(control_h, 2×pad_control_x + [icon_sm + gap_sm] + 文字宽(font_body_strong) + [gap_sm + icon_sm])`；相邻标签间距 = `gap_xs`；切换当前页时各标签的位置与宽度**完全不变**；当前标签文字为 `font_body_strong`、顶边内侧有厚 `tab_indicator_h` 的 `accent_mark` 指示条，非当前标签为 `font_body` 且无指示条；内容区为 `drawPanel` 且在当前标签的水平区间内上缘线被接合（该区间内无 `border_strong` 像素）；内容区内边距 = `pad_panel`。

**AC-W-TABS-002**　`[金图]` 覆盖：REQ-W-TABS-008、REQ-W-TABS-015、REQ-W-TABS-017、REQ-W-TABS-018。状态矩阵：标签 {当前, 非当前} × {常态, 悬停, 显示为按下, 焦点可见, 禁用}，另有关闭按钮 {常态, 悬停, 按下}，浅/深/高对比度。预期：与基准图一致；焦点环仅出现在"焦点可见"列且只围绕持有焦点的标签；显示为按下时非当前标签内容下移恰 1 ppx；禁用的当前标签仍有指示条与接合；禁用态颜色集合 ⊆ 禁用令牌 ∪ 表面令牌 ∪ 边框令牌；另渲染一个被压窄到比其文字窄的当前标签（以 `…` 结尾，最后一个字形完整，关闭按钮与图标不缩小）。

**AC-W-TABS-003**　`[金图]` 覆盖：REQ-W-TABS-009、REQ-W-TABS-010。标签 10 个（各约 80 lpx 宽），标签条宽度依次取 1000、600、300 lpx，当前页取第 0 页、第 7 页。预期：与基准图一致；1000 lpx 时全部显示、无溢出按钮；600 lpx 时出现溢出按钮（宽 `control_h`），可见标签为含当前标签的连续区间且总宽 ≤ `600 − control_h − gap_xs`；当前页为第 7 页时可见区间含它，且区间起点 `s` 是使其可见的最小值；被隐藏的标签没有节点（节点检视中无其 ID）；不出现换行、滚动条或滚动偏移；300 lpx 时仅少数标签可见；当前标签单独比可用宽度宽时仅显示它且文字被截断。

**AC-W-TABS-004**　`[回放]` 覆盖：REQ-W-TABS-012、REQ-W-TABS-013。三个标签 A（当前）、B、C（可关闭）。脚本：在 B 上按下左键 → 该帧 `changed` 真、`current.* = 1`、B 为当前（按下即切换，未释放）、B 持有焦点且金图无焦点环；释放 → 无新的 `changed`；在 A 上按下并拖到 A 外释放 → 切换保留。点击当前标签 → `changed` 假。右键、中键（B 不可关闭）各一次 → 无任何结果；在内容区滚动滚轮（外层为可滚动容器）→ 容器偏移变化。在 C 的关闭按钮上按下 → C 未被选中、`close_requested` 假；释放 → `close_requested = 2`；按下后移出关闭按钮再释放 → 无 `close_requested`；中键在 C 上按下释放 → `close_requested = 2`。控件本身不移除标签（直到应用停止声明）。禁用的标签上按下 → 无效果。指针形状恒为箭头。

**AC-W-TABS-005**　`[回放]` 覆盖：REQ-W-TABS-014、REQ-W-TABS-015。界面：文本框 T0、标签页（A、B、C，B 被禁用，B 当前页内容为按钮 X）、溢出按钮不出现、按钮 Z。连续按 Tab：序列为 T0 → 当前标签（组仅一次停靠）→ 页内第一个控件 → Z；Shift+Tab 反向对应。焦点在当前标签 A：按 → → 跳过禁用的 B 到 C，C `changed` 真、成为当前页；再按 → → 回绕到 A；← 回到 C；Home → A，End → C；各次切换恰产生一次 `changed`。Tab 进入没有当前页（索引越界）的标签组 → 焦点落在第一个启用标签、不切换。内容区内焦点在 X：按 Ctrl+Tab → 切到下一个启用页（跳过 B）、焦点移到新当前标签、焦点可见；Ctrl+Shift+Tab 反向；Ctrl+PageDown、Ctrl+PageUp 同；焦点在标签页内的文本框中（该文本框预占字符与方向键；按 REQ-INPUT-028 补充规则 `KeyGroups` 只匹配无修饰或仅 Shift 的按键，Ctrl 组合不被预占）时这些键同样有效；仅有 1 个启用标签时这些键不被消费（落到后级）。溢出按钮：当宽度不足而出现时，它是标签条的最后一个子节点、属于同一漫游组：Tab 序中不单独停靠（标签条一次停靠后即进入页内容），方向键可把焦点从最后一个可见标签移到溢出按钮（不切换页），再按 → 回绕到第一个标签。嵌套的内层标签页内 Ctrl+Tab 切换的是内层。

**AC-W-TABS-006**　`[回放]` 覆盖：REQ-W-TABS-016、REQ-W-TABS-017。标签文字"常规(&G)""高级(&A)"，另一禁用标签"只读(&R)"，另两个标签都带 `&M`。系统键盘提示设为"默认隐藏"：初始金图无下划线；按 Alt → G、A、R、M 下出现下划线；Alt+A → "高级" 成为当前页（`changed` 真、`activated = .mnemonic`）、焦点在该标签且可见。Alt+R → 无任何结果，焦点与当前页不变。Alt+M → 不切换，焦点移到先序较前者；再按 Alt+M → 移到另一个。"A && B" 显示为 "A & B" 且未登记助记符。整体 `enabled = false`：Tab 序不含标签组与溢出按钮、页循环键被丢弃（落到后级）、点击无效、当前标签仍显示选中。

**AC-W-TABS-007**　`[回放]` 覆盖：REQ-W-TABS-002、REQ-W-TABS-003、REQ-W-TABS-004、REQ-W-TABS-005。应用持有版本与框架保留版本各做一遍：（一）三个标签，页 0 内含滚动容器（滚到偏移 120）、页 1 内含文本框（输入"abc"，光标位置 3）。切到页 1 → 页 0 的内容节点不在树中（节点检视无其 ID）；再切回页 0 → 滚动偏移仍为 120（sticky 保留）；页 1 的文本框内容由应用持有故仍为"abc"，其撤销栈保留。（二）同一调用点在不同页中声明的按钮得到**不同**的 ID（ID 种子为当前页的键），其悬停状态不串页。（三）框架保留版本：首次出现取 `initial`，用户切换后 `TabsResult.current` 更新，应用的构建函数在第二遍看到新值。（四）当前页索引越界 → 全部标签非当前、内容区为空、调试构建 1 条 `warn`、`current.*` 不被改写。（五）`tabs` 切片内页键重复 → 调试构建断言中止；`beginTabs` 与 `endTabs` 不配对 → 调试构建断言中止。（六）sticky 槽超过上限后最久未触达者被回收，其页回到初始状态。

**AC-W-TABS-008**　`[回放]` 覆盖：REQ-W-TABS-010、REQ-W-TABS-011。10 个标签，窗口宽度使 4 个标签被隐藏。点击溢出按钮 → 弹出菜单（弹出层，`kind = menu`），按声明顺序列出 4 个被隐藏标签的图标与文字（禁用标签为禁用项）；选中第 3 项 → `changed` 真、当前页为该标签、菜单关闭、该标签出现在可见区间内。点击菜单外 → 菜单关闭、当前页不变。首帧：构建遍数 = 2（布局反馈）；随后窗口宽度逐 1 ppx 改变使可见区间变化的帧 → 构建遍数 ≤ 2；宽度改变但可见区间不变的帧 → 构建遍数 0（纯布局帧）。窗口放大到全部可见 → 溢出按钮消失，菜单（若打开）随之关闭。

**AC-W-TABS-009**　`[回放]` 覆盖：REQ-W-TABS-019、REQ-W-TABS-012。系统动画开启：点击非当前标签 → 释放所在帧 `current.*` 与 `changed` 已更新、内容区已显示新页；其后各动画帧中指示条的位置与宽度单调趋向目标，各帧所有标签的布局矩形集合完全相同，构建遍数为 0；动画结束后 `frame.count` 不再增长。途中再点击另一标签 → 指示条从当前位置重新开始。首次渲染无动画帧。系统动画关闭 → 动画帧数为 0。窗口宽度变化使可见区间换位 → 指示条直接取新位置，无过渡帧。

**AC-W-TABS-010**　`[回放]` 覆盖：REQ-W-TABS-013、REQ-W-TABS-014、REQ-W-TABS-018。焦点在可关闭标签 C：按 Delete → `close_requested = 该索引`；Ctrl+F4 同；不可关闭的标签上按 Delete → 无结果。截断：当前标签被压到比其文字窄 → 悬停并推进假时钟超过系统悬停时间 → 提示框显示完整文字（不含 `&`）；未截断 → 无提示框；悬停关闭按钮 → 提示"关闭"。空标签文字且无图标 → 调试构建断言中止。

**AC-W-TABS-011**　`[单元]` 覆盖：REQ-W-TABS-020、REQ-W-TABS-004。经假 UIA 入口：整体类型 Tab，模式含 Selection（CanSelectMultiple 假、IsSelectionRequired 真）；标签类型 TabItem，模式含 SelectionItem；Name 为去除助记符的文字，AccessKey 为 "Alt+G"；`IsSelected` 随当前页索引（含应用直接写入）变化；对非当前标签 Select → 下一帧 `changed` 真恰一次、索引更新；对被溢出隐藏的标签 Select → 同样切换且其 `IsOffscreen` 由真变假；关闭按钮类型 Button、模式含 Invoke，Invoke → 下一帧 `close_requested`；溢出按钮 Name 为"更多标签"。

**AC-W-TABS-012**　`[计量]` 覆盖：REQ-W-TABS-021、REQ-W-TABS-022、REQ-W-TABS-019。界面含一个有 20 个标签的标签页（部分溢出）与另 5 个标签页。回放：指针从空白处移入标签 X 再移出 → 各帧构建遍数均为 0；被绘制的节点集合 ⊆ {X 及其与损伤相交的祖先}；损伤面积 ≤ X 的绘制范围面积。点击另一标签切换页（系统动画开启）→ 释放帧之后的动画帧构建遍数为 0、损伤 ⊆ 标签条矩形。仅改变标签 X 的文字（宽度不变、不改变可见区间）并 `invalidate(.build)` → 损伤恰为 X 的矩形；以相同参数再次 `invalidate(.build)` → 损伤为空、`frame.presents` 不变。切换页后被切走页的节点数不计入 `frame.nodes`（节点数 = 其余界面 + 新页内容）。

## 17. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-W-TABS-01 | 标签拖动重排（含拖出为新窗口） | 本版不做（待定）；若做，沿用 08 的应用内拖放（`beginDrag`/`dropTarget`）与关闭请求同样由应用最终重排数据 |
| OPEN-W-TABS-02 | 溢出菜单只列隐藏的标签，是否改为列出全部标签并勾出当前页 | 先只列隐藏者；评审时再定 |
| OPEN-W-TABS-03 | 隐藏标签不声明节点，因而无助记符、方向键不可达（REQ-W-TABS-014、REQ-W-TABS-016） | 先接受：用溢出菜单与页循环键；若不可接受，改为隐藏标签也声明零尺寸的 `hidden` 节点 |
| OPEN-W-TABS-04 | 标签条是否允许放在内容区下方或侧边 | 不提供 |
