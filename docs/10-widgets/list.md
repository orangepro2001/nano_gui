# 虚拟化列表（list）

> 本文同时是 list、tree、table 三个控件共用的**选择模型**的定义处（见 5.3 节）。tree.md 与 table.md 引用本文的选择模型，只写差异。

## 1. 用途

展示一列长度固定高度一致的条目，让用户浏览、选择并激活其中之一或多项。参照 Windows 的 ListBox 与 ListView 的列表/报表视图（单列）。本控件**必须**做虚拟化：只为可见行（外加少量缓冲行）创建节点，总行数可达数十万乃至百万（REQ-PERF-020、REQ-PERF-021、REQ-PERF-035）。

- 条目少（几十项以内）、每行内容复杂且不需要选择模型 → 用 07 的 Column 加普通控件（`for` 循环声明），不必虚拟化。
- 有层级 → 用 tree；有多列与表头 → 用 table。
- 从一组选项中选一个并收起 → 用 combo-box。
- 行高不固定 → 本版不支持（列为待定）。

## 2. 解剖

```
┌────────────────────────────────────┬──┐  ← 框：drawSunken（内凹表面）
│ ▌ 行 0（交替行底色，可选）           │▲ │
│   行 1                              │█ │  ← 滚动条：见 scroll-view.md
│ ■ 行 2（选中：drawSelection）        │█ │
│ ┌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┐  │  │
│ ╎ 行 3（焦点行，焦点可见时的指示）  ╎  │  │
│ └╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┘  │  │
│   行 4（悬停：surface_row_hover）    │  │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┤  │  ← 拖动重排时的放置指示线（覆盖层）
└────────────────────────────────────┴──┘
   └ pad_item_x ┘[图标] 文字（尾部省略）  ← 行内容
```

- **框**：整个控件的外缘，`drawSunken`。
- **视口**：框内部的滚动区域，由 scroll-view 提供滚动条、滚轮与滚动规则。
- **行**：固定高度的条带；只有可见行与缓冲行存在节点。
- **行内容**：调用方在迭代中声明（常用 `listLabel`）。
- **焦点行指示**：焦点行上的发丝线描边。
- **放置指示线**：拖动重排时画在覆盖层。
- **空状态文字**：无条目时显示的占位文本。

## 3. 度量与布局

| 项 | 取值（令牌） |
|---|---|
| 行高 | `row_h`；选项 `row_height` 指定固定值（lpx） |
| 行内左右内边距 | `pad_item_x` |
| 图标尺寸 | `icon_sm` |
| 图标与文字间距 | `gap_sm` |
| 文字样式 | `font_body` |
| 框圆角 | `radius_control` |
| 框内缩 | `Params.border = 1`（一个发丝线宽度，REQ-LAYOUT-056） |
| 滚动条 | `scrollbar_w`、`scrollbar_thumb_min`（scroll-view） |
| 缓冲行 | 视口上下各 5 行（常量 `list_buffer_rows`，与 REQ-PERF-035 的预取边距一致） |
| 首次出现的回退行数 | 32 行（常量，视口尚未知时） |
| 绘制外延 | 0（焦点指示在行内） |

**REQ-W-LIST-001**　默认尺寸策略：主轴 `grow(1)`、交叉轴 `fill`，最小高度 `row_h`；调用方**可以**经 `layout` 选项覆盖。列表只在竖直方向滚动，行宽恒等于视口宽度；行内容超出行宽时按 REQ-W-LIST-046 省略，**不**产生横向滚动。

**REQ-W-LIST-002**　控件由三层节点构成：根（框，`drawSunken`，`Params.border = 1` 为发丝线边框留位（REQ-LAYOUT-056），登记 `click`、`context`，可聚焦）→ 滚动视图（scroll-view，`axes = vertical`、`bar_v` 取选项 `scrollbar`、`report_viewport = true`、`line_step` = 行高、`virtual_extent_px` = 总范围、偏移由列表持有：`offset_px` 指向保留节点内的 i64 偏移）→ 虚拟内容容器（子项为若干行节点，位置由 `virtual_pos_px` 给定，REQ-LAYOUT-054）。滚动条的槽与滑块是 Scroll 下由框架创建的部件节点（scroll-view REQ-W-SCROLLVIEW-005）。滚动条显示策略由选项 `scrollbar`（默认 `auto`）决定：`auto` 时仅当 `count × 行高 > 视口高` 时出现（REQ-LAYOUT-029、030）。

**REQ-W-LIST-003**　行高**必须**为固定值：`row_px = theme.px(row_h, scale)`（或选项 `row_height` 经 REQ-LAYOUT-002 换算），整数 ppx。第 `i` 行的内容坐标起点 = `i × row_px`，内容总范围 = `count × row_px`，经 `ScrollParams.virtual_extent_px`（i64 ppx）声明，滚动偏移以 `offset_px`（i64 ppx）保存与请求（REQ-LAYOUT-054）；内容范围上限 2^53 ppx，超过时调试构建断言，发布构建只显示前 `floor(2^53 / row_px)` 行并记录 `warn`。

**REQ-W-LIST-053**　**行位置逐像素精确**：行节点用相对视口的整数 ppx 位置排布：第 `i` 行的 `virtual_pos_px.y = i × row_px − off_px`（i64 运算后落入 i32），因此无论 `count`（含 100 万行及以上）与偏移多大，每一行的位置都精确到 1 ppx，相邻行恒相距恰 `row_px`，偏移每增加 1 ppx 所有可见行恰好上移 1 ppx（无跳变、无累计误差）；树中任何节点矩形的坐标绝对值不超过视口高度加缓冲行高度。

**REQ-W-LIST-004**　**可见窗口**：设视口高 `vp_px`、保留偏移 `off_px`（ppx），则 `first_vis = floor(off_px / row_px)`，`last_vis = min(count − 1, floor((off_px + vp_px − 1) / row_px))`；迭代器产出的行下标范围为 `first = max(0, first_vis − 5)` 至 `last = min(count − 1, last_vis + 5)`（含两端）。`count = 0` 时不产出任何行。

**REQ-W-LIST-005**　**不可见行不创建节点**：下标不在 `[first, last]` 内的行**不得**有节点（REQ-PERF-035）。虚拟内容容器的子项只有 `last − first + 1` 个行节点，**没有**前导占位叶子；总范围由 `virtual_extent_px` 保证，使滚动条与偏移范围与总行数一致。每次 `endList` 后控件**必须**把当前行节点数写入计量 `list.virtual_nodes`（12 的埋点登记）。

**REQ-W-LIST-006**　**迭代协议**：`var it = w.beginList(ui, @src(), count, opts); while (it.next()) |row| { … } const res = w.endList(ui);`。`next()` 结束上一行（若有）并开始下一行：创建行节点（固定高 `row_px`、`fill` 宽的 Row 容器）、以该行稳定键为种子压入 ID 栈（REQ-FRAME-003 的 `pushId`）、返回 `ListRow`；耗尽时结束最后一行并返回 `null`。应用在两次 `next()` 之间用 `row.index` 声明该行内容；**不得**在迭代中 `break`（会使 `begin`/`end` 失配，调试构建断言，REQ-FRAME-028），**不得**为同一 `row.index` 声明多于一个顶层内容。

**REQ-W-LIST-007**　首次出现（视口未知，`ScrollViewHandle.viewport = null`）时，迭代器按视口 32 行产出 `[0, min(count − 1, 31)]`；视口随后经布局反馈（`report_viewport`，REQ-W-SCROLLVIEW-028、REQ-FRAME-031）得知并触发同帧第二构建遍，之后按 REQ-W-LIST-004 产出。视口高度变化（窗口缩放、分隔条拖动）同样经布局反馈在同帧补齐新增的可见行，不得出现一帧空白行。

**REQ-W-LIST-008**　**行的稳定键**：选项 `data.key_of(index)` 返回行的稳定标识 `ItemKey`（`u64`，应用保证在同一列表内唯一、不随排序/增删改变）。行内部全部控件的 ID 以它为种子，因此行内状态（文本框、展开态）、选择、焦点与锚点都按键关联。缺省（`key_of = null`）时键取行下标：**行重排、插入、删除后，键与行的对应关系错位**——选中与焦点会停留在下标上而不是原来的条目，行内控件状态也会串到别的条目上；仅当数据只在末尾追加时缺省是安全的。调试构建在缺省键且 `count` 变小或 `reorder = true` 时记录一条 `warn`（`reorder = true` 且无 `key_of` 为断言失败）。

**REQ-W-LIST-009**　构建函数内的代价**必须**与总行数无关：`beginList`、迭代与 `endList` 的每次构建工作量 O(可见行数 + 缓冲行数)；`Selection.contains` 为 O(1) 期望；不得遍历全部行（唯一的例外是用户触发的一次性操作：全选、类型预搜索无 `prefix_search` 时的线性扫描，REQ-W-LIST-037、REQ-W-LIST-039）。此条是 REQ-PERF-036 的控件级落实。

**REQ-W-LIST-010**　**行内容容器**：行节点是水平 Row，左右内边距 `pad_item_x`，子项在交叉轴居中，子项间距 `gap_sm`，高度固定，裁剪子项。行内容由应用声明；常用的 `w.listLabel(ui, @src(), row, text, .{ .icon = … })` 在行内放置可选图标（`icon_sm`）与单行文字（`fit_shrink`，`font_body`），文字色由 `row.text_color` 决定（REQ-W-LIST-045），省略与提示按 REQ-W-LIST-046。应用也可声明任意控件（如行内的 `quiet` 按钮、复选框），它们先于行本身接收指针事件（命中后者优先，REQ-INPUT-007）。

**REQ-W-LIST-011**　**空状态**：`count = 0` 时列表仍绘制框，并在视口内垂直居中、水平居中绘制 `opts.empty_text`（`font_body`、`text_secondary`，单行，超宽尾部省略）；`empty_text` 为空时不绘制文字。空状态下列表仍可聚焦，方向键无效果，滚动条按 `scrollbar` 策略（`always` 时为禁用外观）。

**REQ-W-LIST-012**　**滚动**（偏移由列表持有，故滚轮经收件列表在一次构建中处理，不再多出第二遍；视口尺寸变化经布局反馈补齐）复用 scroll-view 的全部规则（REQ-W-SCROLLVIEW-005 至 REQ-W-SCROLLVIEW-017、REQ-W-SCROLLVIEW-023），其中一"行"的滚动量 `line` 取行高（`line_step = row_px / scale`），一"页"为视口高减一行（至少一行）。滚轮读取系统度量 `wheel_lines`（03）：`lines(3)` 时一格滚动三行；`page` 时一格滚动一页。滚轮到达端点后按 scroll-view 的边界吸收规则冒泡。偏移保存在列表的保留节点中（REQ-W-LIST-049）。

## 4. 变体与参数

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `mode` | `SelectionMode` | `single` | `none`/`single`/`multi`（5.3） |
| `selection` | `?*Selection` | `null` | 非空：选中集合由应用持有；空：框架在保留节点内持有（经 `ListResult.selection` 只读访问） |
| `data` | `ListData` | `{}` | 回调：`key_of`、`index_of`、`item_text`、`prefix_search`，及其 `ctx` |
| `row_height` | `?f32`（lpx） | `null` | 固定行高；空取 `row_h` |
| `alternate_rows` | `bool` | `false` | 奇数行（下标为奇）画 `surface_row_alt` 底色 |
| `empty_text` | `?[]const u8` | `null` | 空状态文本 |
| `scrollbar` | `layout.BarPolicy` | `auto` | 纵向滚动条显示策略 |
| `reorder` | `bool` | `false` | 允许拖动重排（应用内拖放，REQ-INPUT-059/060） |
| `tooltip_on_truncate` | `bool` | `true` | 行文字被截断时悬停显示全文（`listLabel`） |
| `enabled`、`key`、`debug_name`、`layout` | 通用 | | 见模板 |

变体只有 `mode`（结构性）与两个外观开关（`alternate_rows`、`scrollbar`）；颜色与尺寸不可逐实例指定。

## 5. 状态

### 5.1 状态机

状态变量：`press ∈ {无, 待折叠, 拖动重排}`（鼠标按下后的待定动作）、`search`（前缀搜索缓冲与最后击键时间）。悬停、聚焦、禁用由框架维护（08）。下表中"按下"指左键按下事件（`NodeEvent.press`），"点击"指按下与释放在同一行节点上完成（REQ-INPUT-015）。选择与焦点的具体变更按 5.3 的记号：`Sel` 选中集合、`F` 焦点行、`A` 锚点行。

| 当前 `press` | 事件 | 条件 | 下一 `press` | 动作 |
|---|---|---|---|---|
| 无 | 左键按下于行 r，无修饰 | `multi`，r 已选中且 `|Sel| > 1` | 待折叠 | `F` ← r；`Sel`、`A` 不变（REQ-W-LIST-023） |
| 无 | 左键按下于行 r，无修饰 | 其他 | 无 | `Sel` ← {r}；`F`、`A` ← r（REQ-W-LIST-019） |
| 无 | 左键按下于行 r，Ctrl | `multi` | 无 | 切换 r；`F`、`A` ← r（REQ-W-LIST-020） |
| 无 | 左键按下于行 r，Shift | `multi` | 无 | `Sel` ← 区间 [A, r]；`F` ← r（REQ-W-LIST-021） |
| 无 | 左键按下于行 r，Ctrl+Shift | `multi` | 无 | `Sel` ← `Sel` ∪ [A, r]；`F` ← r（REQ-W-LIST-022） |
| 无 | 左键按下于行 r | `reorder` 且 r 已选中 | 无（拖拽阈值内按普通规则，越过则 → 拖动重排） | 见 REQ-W-LIST-042 |
| 待折叠 | 左键释放（点击成立） | — | 无 | `Sel` ← {r}；`A` ← r（r 为按下的行） |
| 待折叠 | 拖拽开始（`reorder` 且越过拖拽阈值） | — | 拖动重排 | `Sel`、`A` 不变 |
| 待折叠 | 捕获取消 / 释放在行外 | — | 无 | `Sel`、`A` 不变 |
| 拖动重排 | 释放于有效放置位置 | — | 无 | 报告 `reordered`（REQ-W-LIST-044） |
| 拖动重排 | Esc / 捕获取消 / 释放于无效位置 | — | 无 | 无 |
| 无 | 右键按下于行 r | r 未选中 | 无 | `Sel` ← {r}；`F`、`A` ← r（REQ-W-LIST-025） |
| 无 | 右键按下于行 r | r 已选中 | 无 | `F` ← r；`Sel`、`A` 不变 |
| 无 | 右键点击（释放） | 行或空白 | 无 | 报告 `context_menu` |
| 无 | 左键按下于空白 | `multi` | 无 | `Sel` ← ∅；`F`、`A` 不变（REQ-W-LIST-026） |
| 无 | 左键按下于空白 | `single`、`none` | 无 | 无变化 |
| 无 | 第二次点击（`click_count = 2`）于行 r | 无 Ctrl/Shift | 无 | 报告 `activated`（r）（REQ-W-LIST-027） |

键盘导航不改变 `press`；键盘规则见第 7 节。

### 5.2 视觉表现

| 状态 | 绘制（基元 + 令牌） |
|---|---|
| 框 | `drawSunken(R, radius_control, visual, invalid = false)`；禁用 `surface_sunken_disabled` |
| 奇数行（`alternate_rows`） | 行矩形填充 `surface_row_alt`，直角，占满行宽 |
| 悬停行（未选中） | 行矩形填充 `surface_row_hover`，过渡 `dur_fast`（`Visual.hover_t`） |
| 选中行 | `drawSelection(R_row, active)`；`active` = 列表持有焦点 **且** 窗口活动；否则 `active = false`（`surface_selection_inactive`）。选中行不再画悬停与交替底色 |
| 行文字 | 默认 `text_primary`；选中且 `active` 时 `text_on_accent`；禁用 `text_disabled` |
| 焦点行指示 | 列表持有焦点、焦点可见（REQ-INPUT-040）且为焦点行：调用 `drawRowFocus(R_row, on_selection)`（REQ-THEME-038；`on_selection` = 该行选中且 `active`）。窗口非活动或焦点不可见时不画 |
| 放置指示线（重排） | 覆盖层水平线，宽 2 个发丝线，颜色 `accent_mark`，横跨视口宽 |
| 空状态文字 | `font_body`、`text_secondary` |
| 禁用 | 框用禁用配方，文字 `text_disabled`，选中行始终 `active = false`，无悬停、无焦点指示 |

**REQ-W-LIST-045**　行的绘制顺序与颜色**必须**按下列规则：(1) 框（`drawSunken`）；(2) 行底：奇数行且 `alternate_rows` 填 `surface_row_alt`；(3) 悬停且未选中的行填 `surface_row_hover`；(4) 选中行 `drawSelection(R_row, active)` 覆盖前两层，`active` = 列表持有焦点 **且** 窗口活动（`DrawCtx.window_active`）；(5) 行内容；(6) 焦点行指示。行底均占满视口宽度（含滚动条之外的整行）。`ListRow.text_color`：禁用 → `text_disabled`；选中且 `active` → `text_on_accent`；其余 → `text_primary`。图标与文字同色，不单独着色。

**REQ-W-LIST-047**　**禁用**（`enabled = false`）：框用禁用配方（`surface_sunken_disabled`、`border_control_disabled`、不画顶部内阴影）；行文字 `text_disabled`；选中行始终以 `active = false` 绘制；无悬停底、无焦点指示；列表不可聚焦、不响应鼠标与键盘（命中仍吞掉事件，REQ-INPUT-009）；滚动条按 scroll-view 的禁用外观；既有选中、焦点行、偏移保持不变。持有焦点期间被禁用时按 REQ-INPUT-042 转移焦点；待折叠与拖动重排被取消。

### 5.3 选择模型（list、tree、table 共用）

本节定义选择模型的概念与类型；鼠标与键盘规则分别在第 6、7 节。tree 与 table 引用本节，只写差异。

**概念**

| 名称 | 定义 |
|---|---|
| 选中集合 `Sel` | 一组 `ItemKey`，由应用持有（或框架代持），表示"被选中的条目"。**按稳定键**，不按下标 |
| 焦点行 `F` | 键盘光标所在的行；至多一个；与选中独立（Ctrl+方向键只移动焦点）。保存为 `(index, key)` |
| 锚点行 `A` | 区间选择的起点；至多一个；保存为 `(index, key)`。普通单击、Ctrl+单击、Space、方向键（无 Shift）都把锚点设在当前行；Shift 类操作不改变锚点 |
| 区间 `[A, r]` | 下标介于锚点下标与 r 之间（含端点，顺序无关）的全部行；tree、table 中指当前可见行序上的区间 |
| 模式 | `none`：不可选，`Sel` 恒为空，焦点行仍可移动、可激活；`single`：至多一个；`multi`：任意多个 |

**REQ-W-LIST-013**　选择类型由框架提供（`widgets` 模块，见第 12 节）：`ItemKey = u64`、`SelectionMode`、`Selection`（按键的集合）、`KeyView`（把下标映射为键的只读视图）。`Selection` 的操作为：`contains(key)`（O(1) 期望）、`len()`、`clear()`、`add(key)`、`remove(key)`、`toggle(key)`、`setOnly(key)`、`addRange(view, a, b)`（把下标 `a..b` 闭区间内各行的键加入，`a`、`b` 顺序无关，O(区间长度)）、`pruneTo(view)`（移除不在当前数据中的键）与迭代。应用经 `opts.selection` 传入自己持有的 `Selection`；控件在**输入事件处理时**直接修改它（这是控件对"选择改变"这一激活类结果的落实，不违反 REQ-FRAME-025），并在改变时报告 `selection_changed`。应用也可在构建函数之外自行修改它，下一次构建生效。

**REQ-W-LIST-014**　选中**按键而不按下标**：数据重排、插入、删除后，已选中的条目仍选中，选中的高亮跟随条目移动。键缺省为下标时（REQ-W-LIST-008）选中等价于按下标，重排后停留在下标上。选中集合中可以含有当前数据里不存在的键（已被删除的条目或在未加载范围内的条目）：控件**不**自动清理，它们既不显示也不计入 `ListResult.selected_visible`；应用在删除条目时应当 `remove` 对应键，或调用 `pruneTo`。

**REQ-W-LIST-015**　**焦点行与锚点的保持与校正**：每次 `beginList` 先校正：`count = 0` 时焦点与锚点清空；否则若保存的 `index ≥ count` 则取 `count − 1`；若 `key_of(index)` 与保存的键不同（数据重排）：提供了 `data.index_of` 时按键重新查找下标（键已不存在则焦点取原下标夹紧后的行、锚点清空）；未提供时保持下标并更新保存的键。校正**不**改变选中集合，也不报告 `selection_changed`。

**REQ-W-LIST-016**　模式约束：`none` 下 `Sel` 视为空（应用传入的非空集合被忽略并在调试构建记录一条 `warn`），所有修改选择的操作无效果，但焦点移动、激活、前缀搜索移动焦点照常。`single` 下控件的每次选择修改最终至多一个键；应用传入多于一个键的集合时，控件显示全部但在首次修改时收敛为一个。修饰键在 `single` 下的作用见 REQ-W-LIST-024。

**REQ-W-LIST-017**　`selection_changed` 仅当一次操作使选中集合的内容（键的集合）**确实改变**时为真（激活类结果，触发同帧第二构建遍）；只移动焦点（Ctrl+方向键、点击已单选的同一行、`none` 模式）不报告。控件同时在 `ListResult` 中给出持续性的 `focus_index`（`?usize`）。区间、全选、清空等一次操作无论改了多少键，该帧只报告一次。

**REQ-W-LIST-018**　**初始焦点行**：列表以键盘（原因 `tab`/`group`/`mnemonic`）获得焦点且无焦点行时，焦点行取"选中集合中下标最小的可见行"，没有选中行则取第 0 行；该操作不改变选中集合与锚点。以鼠标获得焦点（原因 `pointer`）时焦点行由该次点击决定。窗口重新激活（`restore`）时恢复原焦点行。

## 6. 鼠标行为

列表登记指针兴趣：根节点 `click`、`context`；每个行节点 `click`、`context`，`reorder = true` 时另登记 `drag`；滚轮由内部的滚动视图登记。下列行号均为数据行下标，指针事件的 `pos` 为相对目标节点左上角的 lpx（08），`r` 为被按下的行，修饰键取按下事件的修饰状态（`NodeEvent.press.mods`）。`multi` 之外的模式见 REQ-W-LIST-024。

**REQ-W-LIST-019**　**单击**：无修饰键、左键在行 r 上**按下**时（不等释放），`Sel ← {r}`、`F ← r`、`A ← r`，并使 r 滚入视野（REQ-W-LIST-029）。例外见 REQ-W-LIST-023。

**REQ-W-LIST-020**　**Ctrl+单击**（`multi`）：按下时切换 r 的选中状态（已选则取消，未选则加入），其余选中保持；`F ← r`、`A ← r`。

**REQ-W-LIST-021**　**Shift+单击**（`multi`）：按下时 `Sel ← 区间 [A, r]`——**替换**原有的全部选择（含不在区间内的已选项）；`F ← r`；`A` 不变。尚无锚点时先把 `A` 设为 r（区间为 {r}）。

**REQ-W-LIST-022**　**Ctrl+Shift+单击**（`multi`）：按下时 `Sel ← Sel ∪ 区间 [A, r]`；`F ← r`；`A` 不变；尚无锚点时同 REQ-W-LIST-021。

**REQ-W-LIST-023**　**在已选中的多行之一上按下不立即改变选择**：`multi` 下无修饰键地按下已选中的行 r 且 `|Sel| > 1` 时，只设 `F ← r`，`Sel` 与 `A` 不变，进入 `press = 待折叠`（便于随后拖动这些行）。左键释放且点击成立（释放在同一行内、未开始拖拽）时才折叠：`Sel ← {r}`、`A ← r`；若期间开始了拖拽（`reorder` 开启、越过拖拽阈值，REQ-INPUT-017）或释放在行外或捕获被取消，则不折叠。Ctrl、Shift 修饰的按下不适用本条（按 REQ-W-LIST-020 至 022 立即生效）。

**REQ-W-LIST-024**　**`single` 与 `none` 下的修饰键**：`single` 下 Shift 被忽略（按无修饰处理），Ctrl+单击切换该行（已选则取消，使选择可以清空；未选则 `Sel ← {r}`）；`F`、`A` 随点击行设置。`none` 下左键点击只设 `F ← r`、`A ← r`（焦点指示可见时可见），不修改选择，不报告 `selection_changed`；双击仍激活（REQ-W-LIST-027）。

**REQ-W-LIST-025**　**右键**：右键**按下**于行 r 时，r 未选中则等同无修饰单击（`Sel ← {r}`、`F`、`A ← r`），r 已选中则只设 `F ← r`、不改变 `Sel` 与 `A`；右键忽略 Ctrl、Shift 修饰；`none` 下只设焦点。右键**释放**（点击成立，REQ-INPUT-018）时报告 `context_menu`，携带被点击的行下标与指针位置。

**REQ-W-LIST-026**　**点击空白处**（视口内最后一行之下、不在任何行节点内的区域，左键按下）：`multi` 下 `Sel ← ∅`（原集合非空时报告 `selection_changed`），`F` 与 `A` 不变；`single`、`none` 下不改变选择。右键点击空白处：不改变选择，报告 `context_menu`，行下标为 `null`。

**REQ-W-LIST-027**　**双击激活**：同一行上第二次点击（`click_count = 2`，REQ-INPUT-016，间隔与位置读取系统双击设置）在**第二次释放**时报告 `activated`（该行下标）；第二次按下的选择效果按 REQ-W-LIST-019 至 023 照常发生。带 Ctrl 或 Shift 的点击不构成激活。空白处的双击不激活。

**REQ-W-LIST-028**　**悬停与其他输入**：指针所在行显示悬停底色（REQ-THEME-030 的悬停维度，选中行不变）；指针形状恒为箭头；中键按下释放无效果（无自动滚动）；滚轮按 REQ-W-LIST-012 处理；拖动框选（橡皮筋）不提供（OPEN-W-LIST-03）。禁用的列表可被命中但不产生任何选择或激活（REQ-INPUT-009）。

**REQ-W-LIST-029**　**点击聚焦与滚入**：任何左键或右键按下都使列表取得焦点（点击聚焦，REQ-INPUT-022；焦点不可见）。按下使 `F` 变为一个未被完整显示的行时，列表以最小位移把它滚入视口（REQ-W-LIST-040 的规则）；按下已完整可见的行不滚动。

**REQ-W-LIST-030**　**上下文菜单请求**：结果 `context_menu: ?ListContext{ index: ?usize, pos, anchor, from_keyboard }`。鼠标触发见 REQ-W-LIST-025、026（`from_keyboard = false`，`anchor` 为 1×1 lpx 的指针处矩形）。键盘触发（Shift+F10 或菜单键，08 REQ-INPUT-018 的内建键位，不受预占影响）时，`index = F`，`anchor` 为焦点行在根坐标系下的矩形（已裁剪到视口），`pos` 为其左下角；无焦点行时 `index = null`、`anchor` 取列表矩形，`pos` 取其左上角内移 `pad_item_x`。上下文菜单本身由应用弹出（控件不绘制菜单）。

### 6.1 拖动重排（可选）

**REQ-W-LIST-042**　`reorder = true` 时行节点登记 `drag`。左键在行上按下后指针离开按下点的拖拽阈值矩形（读取系统度量 `drag_size`，03；REQ-INPUT-017）时拖拽开始，控件在该次构建调用 `ui.beginDrag(list_id, DragPayload{ kind = list_reorder_kind, data = 本列表的 WidgetId 数值 })`。被拖动的行 = 当前选中集合（按下的行此时必为选中，REQ-W-LIST-019、023）。`reorder` 要求 `data.key_of` 非空且 `mode ≠ none`，否则调试构建断言，发布构建忽略 `reorder`。拖拽开始即取消点击（不折叠选择，REQ-W-LIST-023）。

**REQ-W-LIST-043**　列表经 `ui.dropTarget(list_id, DropAccept{ kinds = &.{ list_reorder_kind } })` 登记放置目标，且仅当载荷的 `data` 等于本列表 ID 时视为可接受（其他列表的拖动不被接受）。设指针在视口内的竖直坐标换算到内容坐标为 `y`（含偏移），插入边界 `ins = clamp(floor((y + row_px / 2) / row_px), 0, count)`，即离指针最近的行间边界。可接受且指针在列表内时，列表在覆盖层（`ui.overlay`，REQ-FRAME-017，REQ-INPUT-060）画放置指示线：竖直位置 `ins × row_px − 偏移`（落在视口外则不画），横跨视口宽，粗 2 个发丝线（REQ-THEME-012），颜色 `accent_mark`。被拖动的行本身不隐藏、不半透明。指针形状取箭头。边缘自动滚动按 REQ-W-SCROLLVIEW-017。

**REQ-W-LIST-044**　**放置结果**：在可接受位置释放时报告 `reordered = ReorderRequest{ keys, insert_at = ins }`，`keys` 为被拖动行的键，按当前下标升序。设被拖动下标集合为 D：若 D 是连续的一段且 `min(D) ≤ ins ≤ max(D) + 1`（移动后顺序不变），则视为无操作，**不**报告；D 不连续时一律报告（结果是把它们集中到 `ins` 处）。数据的实际重排由应用执行；控件**不**修改选中集合（键不变）。Esc（REQ-INPUT-059）、捕获被取消、在列表外或无效位置释放时不报告，覆盖层指示线随下一次构建消失。

## 7. 键盘行为

下表为列表持有焦点时的键位。"移动并选中" = `F ← 新行`，`Sel ← {新行}`，`A ← 新行`；"区间" = `Sel ← [A, 新行]`（替换），`F ← 新行`，`A` 不变；"并入区间" = `Sel ← Sel ∪ [A, 新行]`；"仅移动" = 只改 `F`。`none` 下所有改变选择的列都退化为"仅移动"。`single` 下带 Shift 的列按无 Shift 处理。

| 键 | 无修饰 | Ctrl | Shift | Ctrl+Shift |
|---|---|---|---|---|
| ↓ / ↑ | 移动并选中（下一/上一行） | 仅移动 | 区间 | 并入区间 |
| Home / End | 移动并选中（首/末行） | 仅移动 | 区间 | 并入区间 |
| PageDown / PageUp | 移动并选中（±`page_rows` 行） | 不处理（冒泡，让给外层标签页换页） | 区间 | 不处理（冒泡） |
| Space | `Sel ← {F}`，`A ← F` | 切换 `F` 的选中，`A ← F` | 同无修饰 | 同 Ctrl+Space |
| Ctrl+A | — | `multi`：全选，`F`、`A` 不变 | — | — |
| Enter | 激活 `F`（`activated`） | — | — | — |
| 可打印字符 | 前缀搜索（见 REQ-W-LIST-039） | 不处理 | 同无修饰（大小写不敏感） | — |
| Shift+F10 / 菜单键 | 上下文菜单请求（REQ-W-LIST-030） | — | — | — |
| Esc、Tab、←、→ | 不处理（Tab 由 08 导航；←、→ 不被列表声明） | | | |

`page_rows = max(1, floor(vp_px / row_px) − 1)`（视口可容纳整行数减一，至少 1）。

**REQ-W-LIST-031**　列表经 `InteractOpts` 声明：`handles` 的键组含 `arrows`、`home_end`、`page`、`space`、`enter`（键组只匹配无修饰或仅带 Shift 的按键，REQ-INPUT-028）；带 Ctrl 的组合必须在 `handles.extra` 中**逐个列出**：Ctrl+↑、Ctrl+↓、Ctrl+Shift+↑、Ctrl+Shift+↓、Ctrl+Home、Ctrl+End、Ctrl+Shift+Home、Ctrl+Shift+End、Ctrl+Space、Ctrl+Shift+Space，以及（仅 `multi`）Ctrl+A；**不**列入也不使用 Ctrl+PageUp/PageDown 与 Ctrl+Shift+PageUp/PageDown，它们冒泡给外层标签页换页；`preempt.printable = true`（以便接收前缀搜索的 `char`，REQ-INPUT-031）；**不**预占其他键，命令快捷键优先（REQ-INPUT-029）。含 Alt 的组合键不处理（让给助记符与系统）。←、→、Esc、Tab 不声明，继续冒泡。

**REQ-W-LIST-032**　**↓/↑**：`F` 移动一行并按"移动并选中"处理（`single`、`multi` 均如此）；已在首/末行时无效果且不改变选择；无焦点行时（空数据除外）先设 `F` 为第 0 行（↓）或末行（↑）再按移动处理的结果显示（即第一次按键落在第 0 行/末行）。自动重复照常重复。

**REQ-W-LIST-033**　**Shift/Ctrl/Ctrl+Shift 与方向键**（`multi`）：Shift+↓/↑ 移动 `F` 一行并把 `Sel` 设为 `[A, F]`，`A` 不变（无锚点时 `A ← 移动前的 F`）；Ctrl+↓/↑ 只移动 `F`，`Sel` 与 `A` 不变；Ctrl+Shift+↓/↑ 移动 `F` 并并入 `[A, F]`。

**REQ-W-LIST-034**　**Home/End**：`F` 到第 0 行/末行；无修饰为"移动并选中"，Shift 为区间，Ctrl 仅移动，Ctrl+Shift 并入区间。

**REQ-W-LIST-035**　**PageDown/PageUp**：`F` 移动 `page_rows` 行并夹紧到 `[0, count − 1]`（偏移同样滚入，REQ-W-LIST-040）；无修饰为"移动并选中"，Shift 为区间；带 Ctrl 的组合（Ctrl+PageUp/PageDown、Ctrl+Shift+PageUp/PageDown）**不处理**，键继续冒泡（外层标签页的换页由此可用）。

**REQ-W-LIST-036**　**Space**：`F` 存在时，无修饰（或 Shift）把 `Sel` 设为 `{F}`、`A ← F`；Ctrl+Space 切换 `F` 的选中、`A ← F`（`single` 下为切换，可清空）。前缀搜索缓冲非空且未超时（REQ-W-LIST-039）时，Space 作为字符追加到缓冲而不选中。`none` 下 Space 无效果。

**REQ-W-LIST-037**　**Ctrl+A**（仅 `multi`）：`Sel` 设为全部行（`addRange(0, count − 1)`，一次性 O(count) 的用户触发操作，不在每帧执行）；`F`、`A` 不变；已全部选中时不报告 `selection_changed`。

**REQ-W-LIST-038**　**Enter**：`F` 存在时报告 `activated`（`F` 的下标）；不改变选择；自动重复的 Enter 被忽略（只激活一次）。无焦点行时不处理（让给默认按钮，REQ-INPUT-034）。

**REQ-W-LIST-039**　**前缀搜索**：持有焦点时收到可打印字符（`char` 事件，无 Ctrl、无 Alt）：若距上次击键超过 `T_ta`（暂定 1000 ms，见 OPEN-W-LIST-02）则先清空缓冲；追加该字符（Space 经 REQ-W-LIST-036）；以缓冲为前缀（Unicode 简单大小写折叠，REQ-TEXT 的比较规则）在 `data.item_text(i)` 中搜索，起点为：缓冲仅一个字符时 `F + 1`，多于一个字符时 `F`（含）；到末尾回绕到开头，至多扫描 `count` 行。命中则按"移动并选中"处理（`none` 下仅移动焦点）；未命中则不变（缓冲保留）。`data.prefix_search` 非空时用它代替线性扫描（大数据集）；`item_text` 与 `prefix_search` 都为空时前缀搜索关闭（字符不被消费）。IME 组字期间不触发（REQ-INPUT-026）。

**REQ-W-LIST-040**　**焦点行始终滚入视野**：任何使 `F` 改变的输入（键盘移动、前缀搜索、点击）之后，列表以**最小位移**调整偏移使 `F` 行完整可见：行顶在视口顶之上则对齐行顶；行底在视口底之下则对齐行底；已完整可见则不动。结果夹紧到 `[0, max_off]`。该规则由列表按行下标直接计算（行节点可能尚未创建，所以不依赖 REQ-INPUT-044 的 `reveal`）。

## 8. 焦点

**REQ-W-LIST-041**　列表是**单个 Tab 停靠**，内部用方向键等移动焦点行（不是漫游组，REQ-INPUT-038 不适用）；可聚焦、点击聚焦、禁用时不可聚焦。焦点指示按 5.2：列表持有焦点且焦点可见时在焦点行画发丝线描边；焦点不可见（鼠标点击所得）时只有选中底，没有描边。列表失去焦点时选中底改为 `active = false` 的非活动色，焦点行指示消失，保留 `F`、`A`、`Sel`。内部行控件（如行内按钮、文本框）获得焦点时列表本身不是焦点节点，选中底按失焦绘制。焦点获得与失去不产生激活类结果。

## 9. 文本与输入法

行文字单行显示，不接受文本输入；列表不是文本输入类节点，聚焦时输入法禁用。前缀搜索使用 `char` 事件而非输入法组字。

**REQ-W-LIST-046**　行文字超出可用宽度时尾部省略（REQ-THEME-018，05 的 `ellipsis = end`）。可用宽度 = 行宽 − 2 × `pad_item_x` − 图标与间距。文字被截断时，悬停该行（`ui.hoverFor(id, .tooltip)`，延迟读取系统 `hover_time_ms`）以提示框显示完整文字（`tooltip_on_truncate = true` 且 `text.isTruncated` 为真时）；提示框的锚点是该行矩形。未截断时不显示提示框。拖动重排或滚动进行中不显示。

## 10. 动效

| 属性 | 触发 | 时长令牌 | 缓动 | 影响级别 |
|---|---|---|---|---|
| 行悬停底色 | 悬停进入/离开行 | `dur_fast` | `ease_out` | paint（`Visual.hover_t`，行节点内建） |
| 选中底、焦点行指示 | 选择/焦点变化 | 无（瞬时） | — | build（输入事件引起） |
| 滚动位置 | 任何来源 | 无（即时） | — | 见第 14 节 |

列表没有自有动画槽；选中变化不做过渡。

## 11. 无障碍

| 项 | 值 |
|---|---|
| UIA 控件类型 | 列表：List；行：ListItem |
| 名称来源 | 列表：应用经通用无障碍名称选项提供；行：`data.item_text(index)`，缺失时为空串 |
| 支持的模式 | 列表：Selection、Scroll（经 scroll-view）；行：SelectionItem、ScrollItem、Invoke |
| 状态属性 | 列表：CanSelectMultiple（`multi`）、IsSelectionRequired = 假、IsEnabled、HasKeyboardFocus；行：IsSelected、SelectionContainer、IsEnabled、HasKeyboardFocus（`F` 且列表持焦） |

**REQ-W-LIST-048**　UIA 操作**必须**与用户操作等效且在下一帧生效：`SelectionItem.Select` ≡ 单击该行；`AddToSelection` ≡ Ctrl+单击使其选中（`multi`；`single` 时同 `Select`）；`RemoveFromSelection` ≡ Ctrl+单击使其取消；`ScrollItem.ScrollIntoView` ≡ REQ-W-LIST-040 的最小位移滚入；`Invoke` ≡ 激活（`activated`）；`Selection.GetSelection` 只返回当前**已创建节点**的已选中行（虚拟化下未创建的行的提供方式见 OPEN-W-LIST-05）。

## 12. API 草案

```zig
// 草案：仅签名
pub const ItemKey = u64;
pub const SelectionMode = enum { none, single, multi };

/// 把下标映射为稳定键的只读视图；key_of 为 null 时键取下标。
pub const KeyView = struct {
    ctx: ?*anyopaque = null,
    count: usize,
    key_of: ?*const fn (ctx: ?*anyopaque, index: usize) ItemKey = null,
};

/// 选中集合：按键的集合。list、tree、table 共用。
pub const Selection = struct {
    pub fn init(allocator: std.mem.Allocator) Selection;
    pub fn deinit(self: *Selection) void;
    pub fn contains(self: *const Selection, key: ItemKey) bool;
    pub fn len(self: *const Selection) usize;
    pub fn clear(self: *Selection) void;
    pub fn add(self: *Selection, key: ItemKey) error{OutOfMemory}!void;
    pub fn remove(self: *Selection, key: ItemKey) void;
    pub fn toggle(self: *Selection, key: ItemKey) error{OutOfMemory}!bool;   // 返回切换后是否选中
    pub fn setOnly(self: *Selection, key: ItemKey) error{OutOfMemory}!void;
    pub fn addRange(self: *Selection, view: KeyView, a: usize, b: usize) error{OutOfMemory}!void;  // 闭区间，a、b 顺序无关
    pub fn pruneTo(self: *Selection, view: KeyView) void;                    // 移除不在 view 中的键，O(count)
    pub fn iterator(self: *const Selection) Iterator;
    pub const Iterator = struct { pub fn next(self: *Iterator) ?ItemKey; };
};

pub const ListData = struct {
    ctx: ?*anyopaque = null,
    key_of: ?*const fn (ctx: ?*anyopaque, index: usize) ItemKey = null,
    index_of: ?*const fn (ctx: ?*anyopaque, key: ItemKey) ?usize = null,
    item_text: ?*const fn (ctx: ?*anyopaque, index: usize) []const u8 = null,      // 返回值只需存活至下一次调用
    prefix_search: ?*const fn (ctx: ?*anyopaque, prefix: []const u8, start: usize) ?usize = null,
};

pub const ListOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    mode: SelectionMode = .single,
    selection: ?*Selection = null,
    data: ListData = .{},
    row_height: ?f32 = null,
    alternate_rows: bool = false,
    empty_text: ?[]const u8 = null,        // 借用至本帧结束
    scrollbar: layout.BarPolicy = .auto,
    reorder: bool = false,
    tooltip_on_truncate: bool = true,
    layout: layout.ItemOptions = .{},
};

/// 迭代中提供给应用的行信息。
pub const ListRow = struct {
    index: usize,
    key: ItemKey,
    selected: bool,
    focused: bool,                         // 是焦点行（不等于焦点可见）
    hovered: bool,
    text_color: theme.ColorToken,          // 行内文字应使用的颜色令牌（REQ-W-LIST-045）
};

pub const ListIter = struct {
    pub fn next(self: *ListIter) ?ListRow;
};

pub const list_reorder_kind: u32 = 0x4C535452;   // 拖动重排的拖放载荷 kind（框架保留，'LSTR'）
pub const ReorderRequest = struct {
    keys: []const ItemKey,                 // 被拖动的行的键，按当前下标升序；帧竞技场
    insert_at: usize,                      // 插入边界，0..count，相对未移动前的顺序
};
pub const ListContext = struct { index: ?usize, pos: core.Vec2, anchor: core.Rect, from_keyboard: bool };

pub const ListResult = struct {
    // 持续性状态
    hovered: bool,
    focused: bool,
    focus_index: ?usize,
    selection: *const Selection,
    selected_visible: usize,               // 已创建节点（可见行与缓冲行）中的选中行数
    // 激活类结果（触发同帧第二构建遍，REQ-FRAME-030）
    selection_changed: bool,
    activated: ?usize,
    context_menu: ?ListContext,
    reordered: ?ReorderRequest,
};

pub fn beginList(ui: *Ui, src: std.builtin.SourceLocation, count: usize, opts: ListOptions) ListIter;
pub fn endList(ui: *Ui) ListResult;

/// 行内的图标 + 单行文字，处理文字色、省略与截断提示。text 借用至本帧结束。
pub const ListLabelOptions = struct { icon: ?theme.Icon = null };
pub fn listLabel(ui: *Ui, src: std.builtin.SourceLocation, row: ListRow, text: []const u8, opts: ListLabelOptions) void;
```

`selection_changed`、`activated`、`context_menu`、`reordered` 是激活类结果，在其为真的帧触发同帧第二构建遍，并在第二遍为假（REQ-FRAME-033）。`ListRow` 的 `text_color` 反映本帧已处理完事件之后的选中与焦点状态。`opts.selection` 指针由应用持有，须存活至 `endList` 返回；`empty_text` 借用至本帧结束；`ReorderRequest.keys` 在帧竞技场，应用须在本帧内处理。`ListData` 的各回调在构建函数内同步调用，**不得**阻塞（REQ-FRAME-026）。

## 13. 保留状态

| 字段 | 类型 | 保留级别 | 说明 |
|---|---|---|---|
| `ListState`（整体） | 保留节点（`ui.retained(ListState, id, .sticky)`） | 保留节点 | 滚动位置、焦点、锚点、搜索缓冲；切换页面后保留 |
| `offset_px` | `[2]i64` | 保留节点 | 滚动偏移（ppx，i64，REQ-LAYOUT-054；x 分量恒为 0），由列表持有，其地址作为 `ScrollViewOptions.offset_px` 传给 scroll-view |
| `focus`、`anchor` | `?struct { index: usize, key: ItemKey }` | 保留节点 | 焦点行与锚点（REQ-W-LIST-015） |
| `search` | `{ buf: [32]u8, len: u8, last_ms: u64 }` | 保留节点 | 前缀搜索缓冲与最后击键的时间戳（`ui.now()`）；超时在下一次击键时惰性清空，无定时器 |
| `own_selection` | `Selection` | 保留节点 | 仅当应用未提供 `selection` 时使用 |
| `press` | `enum { none, pending_collapse, drag_reorder }` 与被按下的行键 | 保留节点（跨构建遍的待定动作） | 鼠标按下后的待定动作 |
| `last_count` | `usize` | 保留节点 | 用于数据缩小时的校正与告警 |
| 行节点的悬停/动画 | 框架内建 | transient | 无需槽 |

保留节点内存取自状态存储池，`deinit` 释放 `own_selection` 与搜索缓冲。

**REQ-W-LIST-049**　列表的保留节点为 sticky：窗口关闭或被 LRU 回收（REQ-FRAME-010）后偏移、焦点、锚点、搜索缓冲重置为初始值（偏移 0、无焦点、无锚点）；应用持有的 `Selection` 不受影响。

## 14. 失效规则

**REQ-W-LIST-050**　绘制键与布局输入键**必须**如下：行节点的绘制键 = (是否选中、`active`、是否焦点行且焦点指示显示、是否奇数行且 `alternate_rows`、`enabled`、行内容的绘制键)；悬停经 `Visual.hover_t` 而非绘制键。列表根的绘制键 = (`enabled`、焦点是否可见且持有焦点（框的边框色）、`count = 0` 时的 `empty_text` 内容)。虚拟内容容器的布局输入含 `virtual_extent_px`；行节点的布局输入恒为（固定高、`fill` 宽），其 `virtual_pos_px` 只影响自身排布、不入哈希（REQ-LAYOUT-045），因此滚动时行节点的测量被复用。

| 变化 | 置脏级别 | 损伤范围 |
|---|---|---|
| 悬停进入/离开某行 | `paint`（构建遍数 0） | 该行矩形 |
| 单击/Ctrl+单击/键盘移动使选择或焦点变化 | `build`（输入事件，REQ-FRAME-037） | 选中状态或焦点指示变化的各行矩形（通常 ≤ 2 行；区间选择为区间内变化的行） |
| 滚轮/滚动条/键盘使偏移变化 | `build`；按 REQ-W-SCROLLVIEW-026 | 视口矩形与滚动条矩形 |
| 滚动一行 | `build`；被创建的行节点数 ≤ 可见行数 + 缓冲行数（见下） | 视口矩形 |
| 数据变化（应用模型通知） | `build` | 由差分决定（按键关联的行逐一比较绘制键） |
| 列表尺寸变化 | `layout`；经布局反馈同帧第二构建遍补齐可见行 | 整个列表 |
| 窗口激活状态变化、列表焦点变化 | `paint`/`build` 视事件源；选中行颜色改变 | 选中行与焦点行矩形 |
| 拖动重排中的指针移动 | `build`（被捕获期间的移动） | 旧新放置指示线矩形（覆盖层） |

**REQ-W-LIST-051**　**可计量断言**：
(1) 任意稳定帧，`list.virtual_nodes ≤ 可见行数 + 2 × 5`，其中可见行数 ≤ `ceil(vp_px / row_px) + 1`；该数与 `count` 无关（REQ-PERF-021：1 万、10 万、100 万行在相同视口下 `frame.nodes` 相等）。
(2) 滚动一行（或任意行数）的帧：被构建的行节点数 ≤ 可见行数 + 缓冲行数；`layout.measured_nodes` 只包含新进入窗口的行节点及其内容（已留在窗口内的行节点测量被复用）。
(3) S-VLIST-100K（10 万行、视口固定、每帧 `wheel -1`）：`time.frame_cpu` 的 P99 ≤ 2.0 ms（REQ-PERF-020）；规模从 1 万行增至 100 万行时 `time.build` 的 P99 增长 ≤ 1.5 倍（REQ-PERF-036）。
(4) 仅悬停变化的帧构建遍数为 0，损伤 ≤ 该行矩形面积。
(5) 无任何变化的重复 `invalidate(.build)` 损伤为空，`frame.presents` 不变（REQ-FRAME-043）。

## 15. 边界与错误情况

**REQ-W-LIST-052**　**数据变化时的校正**：`count` 变小使偏移越界时，偏移夹紧到新的 `max_off`；`F`、`A` 按 REQ-W-LIST-015 校正；选中集合不改（REQ-W-LIST-014）。`count` 变大时偏移不变（`anchor_end` 不用于列表）。按下期间（`press = 待折叠`）被按下的行消失：待定动作取消，选择不变。

| 情况 | 规定 |
|---|---|
| `count = 0` | 空状态（REQ-W-LIST-011）；`F`、`A` 清空；Ctrl+A、Enter、方向键无效果 |
| `count = 1` | 方向键无效果；Home/End 仍把 `F` 设为该行并选中 |
| 视口高 < 一行 | `page_rows = 1`；仍产出 1 + 缓冲行；滚动条按 scroll-view 的槽过短规则 |
| `key_of` 返回重复键 | 调试构建断言（同一构建遍内相同 ID，REQ-FRAME-005）；发布构建后出现者复用前者的状态 |
| 迭代中应用未声明行内容 | 行节点仍存在（空行，可选中） |
| 迭代器未耗尽就 `endList` | 调试构建断言；发布构建补齐剩余行为空行并记录 `err`（REQ-FRAME-028） |
| 应用传入的 `selection` 在 `none` 模式下非空 | 忽略并告警（REQ-W-LIST-016） |
| 禁用中途发生 | 取消待折叠与拖动重排；保持 `Sel`、`F`；立即显示禁用外观；持有焦点则按 REQ-INPUT-042 转移 |
| 按下期间列表消失 | 捕获释放（REQ-INPUT-024），无选择变化 |
| 超长行文字 | 按 05 的 `max_layout_bytes` 截取并省略（REQ-TEXT-005） |
| 行内控件捕获了指针（如行内滑块） | 列表不处理该次按下，选择不变 |
| 窗口非活动 | 悬停照常；选中底为非活动色；点击先激活窗口，该次点击照常作用于列表 |
| `count × row_px` 越界 | 见 REQ-W-LIST-003 |

## 16. 验收标准

下列夹具 `S10`：模式 `multi`，10 行（下标 0 至 9），键缺省取下标，`row_h` = 22，`scale` = 1.0，视口高 220 lpx（恰容纳 10 行，行 `i` 占 y ∈ [22i, 22i+22)，坐标相对视口），`scrollbar = auto`，列表已持有焦点之外的操作均先以鼠标点击获得焦点（焦点不可见）。"状态"一律写作 选中集合 `Sel`、锚点 `A`、焦点行 `F`。

**AC-W-LIST-001**　`[金图]` 覆盖：REQ-W-LIST-001、REQ-W-LIST-010、REQ-W-LIST-011、REQ-W-LIST-041、REQ-W-LIST-045、REQ-W-LIST-046、REQ-W-LIST-047。渲染 12 行列表（视口显示 8 行）：行 1 悬停、行 2–3 选中、行 4 为焦点行；组合 {列表持焦且焦点可见, 持焦但焦点不可见, 失焦, 窗口非活动, 禁用} × {`alternate_rows` 开/关} × 浅/深/高对比度 × 缩放 1.0/1.25/1.5/2.0；另含一行超长文字（被省略）、一行带图标、`count = 0` 的空状态（含 `empty_text` 与无 `empty_text`）、有滚动条与无滚动条（`scrollbar = never`）。预期：与基准图一致；选中底仅在持焦且窗口活动时为强调色（`text_on_accent` 文字），其余为 `surface_selection_inactive`；焦点行指示仅出现在"持焦且焦点可见"列，选中且 active 的焦点行用 `text_on_accent` 描边；悬停行底为 `surface_row_hover` 而选中行不变；省略号结尾无半个字形；禁用列文字为 `text_disabled` 且无悬停/焦点；框为内凹表面，内缩一个发丝线。

**AC-W-LIST-002**　`[单元]` 覆盖：REQ-W-LIST-013、REQ-W-LIST-014、REQ-W-LIST-016、REQ-W-LIST-017。`Selection` 单元测试：`add(5)`、`add(5)` → `len` 1；`toggle(5)` → 返回假、`len` 0；`addRange(view{count=10}, 7, 3)` → 键 {3,4,5,6,7}（顺序无关）；`setOnly(2)` → {2}；`clear()` → 空；`pruneTo(view{count=5})` 作用于 {1,3,8} → {1,3}。键映射：`key_of(i) = 100 + i`，`addRange(view, 2, 4)` → {102,103,104}；数据重排（模型把原下标 2 的条目移到下标 7）后用同一个键仍选中该条目，而 `key_of = null` 时选中停留在下标 2。`single` 模式：应用传入 {1,2} → 控件显示两项；首次点击行 5 → {5}。`none` 模式：传入非空集合 → 调试构建 1 条 `warn`，点击/Space/Ctrl+A 后选中集合仍为 ∅（或应用原样）且 `selection_changed` 恒假。`selection_changed` 判定：`multi` 下 {3} 时点击行 3 → 假；{3,4} 时点击行 3 且 `|Sel| > 1` 的折叠 → 真。

**AC-W-LIST-003**　`[回放]` 覆盖：REQ-W-LIST-019、REQ-W-LIST-020、REQ-W-LIST-021、REQ-W-LIST-022、REQ-W-LIST-017。夹具 S10，初始 `Sel` = ∅，无 `F`、`A`。依次执行并逐步断言（每步格式：操作 → `Sel`；`A`；`F`；`selection_changed`）：① 单击行 3 → {3}；3；3；真。② Shift+单击行 7 → {3,4,5,6,7}；3；7；真。③ Ctrl+单击行 5 → {3,4,6,7}；5；5；真。④ Ctrl+单击行 9 → {3,4,6,7,9}；9；9；真。⑤ Ctrl+Shift+单击行 1 → {1,2,3,4,5,6,7,8,9}；9；1；真。⑥ Shift+单击行 6 → {6,7,8,9}（替换，原选择中的 1–5 被清除）；9；6；真。⑦ Ctrl+单击行 6 → {7,8,9}；6；6；真。⑧ 单击行 0 → {0}；0；0；真；再单击行 0 → {0}；0；0；假。⑨ 承接 ⑧（锚点仍为 0，清除选择不清除锚点）：Shift+单击行 4 → {0,1,2,3,4}；0；4；真。⑩ 无锚点用例（新建列表，`Sel` ∅，无 `F`、`A`）：Shift+单击行 4 → {4}；4；4；真。每一步选择在**按下**那一帧即生效（不等释放）；①处释放后选择不变；`selection_changed` 在下一帧回到假。

**AC-W-LIST-004**　`[回放]` 覆盖：REQ-W-LIST-023。夹具 S10 并通过点击/Shift+单击得到 `Sel` = {2,3,4,5}，`A` = 2，`F` = 5。① 在行 3 按下（不释放）→ {2,3,4,5}；A 2；F 3；`selection_changed` 假；释放（未移动）→ {3}；A 3；F 3；真。② 恢复 {2,3,4,5}，在行 3 按下后移到行 6 并在行 6 释放 → 选择保持 {2,3,4,5}（无点击、无折叠），F 3。③ 开启 `reorder`：恢复后在行 3 按下，指针移动 10 lpx（大于 `drag_size` 的 4 ppx）→ 拖拽开始、选择仍为 {2,3,4,5}；在无效位置释放 → 选择仍为 {2,3,4,5}（不折叠）。④ Ctrl+在已选中的行 3 按下 → 立即切换为 {2,4,5}，A 3，F 3（不适用延迟）。⑤ 恢复 {2,3,4,5} 后在**未选中**的行 8 按下 → 立即 {8}；A 8；F 8。⑥ `Sel` = {3}（只选中一行）时在行 3 按下 → 立即 {3}（无待折叠），`selection_changed` 假。

**AC-W-LIST-005**　`[回放]` 覆盖：REQ-W-LIST-016、REQ-W-LIST-024、REQ-W-LIST-036、REQ-W-LIST-037。`single`：单击 3 → {3}；单击 5 → {5}；Shift+单击 8 → {8}（Shift 被忽略，`A` 8，`F` 8）；Ctrl+单击 8 → ∅（切换取消），A 8，F 8，`selection_changed` 真；Ctrl+单击 2 → {2}；↓ → {3}，F 3；Ctrl+Space → ∅（切换取消）；Ctrl+A 不被列表处理（键冒泡，`Sel` 不变）。`none`：单击 3 → `Sel` ∅，A 3，F 3，`selection_changed` 假，焦点指示可见时画在行 3；↓ → F 4，Sel ∅；Space、Ctrl+A → 无变化；双击行 5 → `activated` = 5；Enter（F 5）→ `activated` = 5。

**AC-W-LIST-006**　`[回放]` 覆盖：REQ-W-LIST-025、REQ-W-LIST-026、REQ-W-LIST-030。夹具 S10，`multi`，`Sel` = {2,3}，A 2，F 3。① 右键按下行 8 → {8}；A 8；F 8（按下即变）；释放 → `context_menu` = {index 8, from_keyboard 假, pos 为指针位置}。② 恢复 {2,3}，右键行 3 → 选择不变 {2,3}，A 2，F 3，`context_menu.index` = 3。③ Ctrl+右键行 8 → 同①（忽略修饰键）。④ 左键点击空白处（`count` 改为 5，视口仍 10 行，点击 y = 150）→ `multi`：{2,3} → ∅，A、F 不变，`selection_changed` 真；已为 ∅ 时再点击 → 假；`single` 模式点击空白 → 选择不变。右键空白 y = 150 → 选择不变，`context_menu.index` = null。⑤ 键盘：F = 4，按 Shift+F10 → `context_menu` = {index 4, from_keyboard 真, anchor = 行 4 的矩形 (0, 88, 视口宽, 22), pos = 其左下角}；菜单键同；`F` 为空且按菜单键 → index = null。⑥ 右键点击并按住，将指针拖出再释放于行外 → 不报告 `context_menu`（点击不成立）。

**AC-W-LIST-007**　`[回放]` 覆盖：REQ-W-LIST-027、REQ-W-LIST-028、REQ-W-LIST-029。夹具 S10，`multi`，系统双击时间 500 ms。① 在行 4 双击（间隔 200 ms、同位置）→ 第二次释放时 `activated` = 4；`Sel` = {4}；第一次点击时无 `activated`。② 间隔 600 ms 的两次点击 → 无 `activated`。③ Ctrl+双击行 4、Shift+双击 → 无 `activated`。④ 空白处双击 → 无。⑤ 悬停行 6 → 构建遍数 0，行 6 悬停底，指针形状为箭头；移到选中行 → 底色不变。⑥ 中键按下、移动 100 lpx、释放 → 无选择变化、偏移不变。⑦ 点击后 `F` 存在但焦点不可见（金图无描边）；随后按一次 Shift → 描边出现。⑧ 另用 100 行夹具（视口 220 lpx，最大偏移 100 × 22 − 220 = 1980）：偏移 11（行 0 露出下半）时单击行 0 的可见部分 → 偏移变为 0（滚入）；行 5 完整可见时单击 → 偏移不变。

**AC-W-LIST-008**　`[回放]` 覆盖：REQ-W-LIST-031、REQ-W-LIST-032、REQ-W-LIST-033、REQ-W-LIST-018、REQ-W-LIST-041。夹具 S10，`multi`，`Sel` = ∅，无 `F`；Tab 序：文本框 → 列表 → 按钮。① Tab 到列表 → F 0（描边可见），`Sel` ∅，`selection_changed` 假；Tab 离开后重新 Tab 回来 → F 仍为 0（保留）。另用从未获得过焦点的新列表、应用预设 `Sel` = {4,5}：Tab 进入 → F 4（选中集合中下标最小的行），`Sel` 不变。② 从 F 0：↓ → F 1，{1}，A 1，真；↓↓ → F 3，{3}，A 3；↑ → F 2，{2}，A 2；在 F 0 按 ↑ → 无变化。③ 回到 {3}，A 3，F 3：Shift+↓↓ → F 5，{3,4,5}，A 3；Shift+↑×3 → F 2，{2,3}，A 3（区间 [2,3]）。④ 在此状态 Ctrl+↓×3 → F 5，`Sel` {2,3}、A 3 不变，`selection_changed` 假。⑤ `Sel` = {1,5}，A 5，F 5：Ctrl+Shift+↑×2 → F 3，`Sel` {1,3,4,5}，A 5。⑥ 自动重复：按住 ↓ 注入 10 个重复 → F 每次 +1 直到 9 后不变。⑦ 已设命令快捷键 ↓ → 触发命令而非移动。⑧ 带 Alt 的 ↓ → 列表不处理。⑨ Tab 离开列表后选中底变为非活动色，F、A、Sel 保留；Shift+Tab 回来 → F 不变。⑩ 列表内部按钮获得焦点时选中底为失焦色。

**AC-W-LIST-009**　`[回放]` 覆盖：REQ-W-LIST-034、REQ-W-LIST-035。夹具：20 行，视口高 132 lpx（6 行）、`multi`，`page_rows` = 5。① F 0 {0}：PageDown → F 5，{5}，A 5；PageDown → F 10；PageUp → F 5；在 F 3 按 PageUp → F 0（夹紧）；在 F 17 按 PageDown → F 19（夹紧）。② `Sel` {5}，A 5，F 5：Shift+PageDown → F 10，{5..10}，A 5；再 Shift+PageDown → F 15，{5..15}，A 5；Ctrl+PageDown 与 Ctrl+Shift+PageDown → 列表不处理（`F`、`Sel` 不变，键冒泡；外层放一个标签页控件时它换页）。③ Home → F 0，{0}；End → F 19，{19}，A 19；Shift+Home → F 0，{0..19}；Ctrl+Home 自 F 19 → F 0，`Sel` 不变；Ctrl+Shift+End 自 `Sel` {2}、A 2、F 2 → F 19，{2..19}。④ 视口 20 lpx（小于一行）时 `page_rows` = 1：PageDown 等同 ↓。

**AC-W-LIST-010**　`[回放]` 覆盖：REQ-W-LIST-036、REQ-W-LIST-037、REQ-W-LIST-038。夹具 S10，`multi`。① F 4、`Sel` {1,2}：Space → {4}，A 4；Ctrl+Space → {4} 切换取消 → ∅，A 4；再 Ctrl+Space → {4}；Shift+Space 与 Space 相同。② Ctrl+A → {0..9}，A、F 不变，`selection_changed` 真；再按 Ctrl+A → 假。③ Enter（F 4）→ `activated` = 4，`Sel` 不变；注入 Enter 按下 + 10 个自动重复 → `activated` 累计恰 1 次。④ 无 `F`（空列表 `count` = 0）：Enter、Ctrl+A、↓ → 无效果，Enter 冒泡为默认按钮的激活。⑤ 单行列表（`count` = 1）：↓ 无效果，Home → F 0 且 {0}。

**AC-W-LIST-011**　`[回放]` 覆盖：REQ-W-LIST-039。夹具：10 行文本 "Apple, Apricot, Banana, Blueberry, Cherry, Date, Elderberry, Fig, Grape, Honeydew"，`item_text` 已提供，`T_ta` = 1000 ms（假时钟），`multi`，F 0。① 输入 'b' → F 2（Banana），{2}，A 2；300 ms 后输入 'l' → 缓冲 "bl"，从 F 2 起（含）搜索 → F 3（Blueberry），{3}。② 推进 1001 ms 后输入 'b' → 缓冲 "b"，从 F + 1 = 4 起搜索，回绕 → F 2。③ 输入 'z' → 无变化，F 2，缓冲保留为 "bz"（无匹配）。④ 推进 1001 ms（≥ `T_ta`，缓冲已过期）后输入 'B'（Shift）→ 缓冲 "B"，大小写不敏感，从 F + 1 = 3 起搜索 → Blueberry，F 3，{3}。⑤ Ctrl+'b' → 不触发搜索（不被消费，命令快捷键机制优先）。⑥ 缓冲 "a" 时按 Space（300 ms 内）→ 缓冲 "a "，不选中；缓冲为空时 Space 选中 F。⑦ `none` 模式：输入 'c' → F 4，`Sel` ∅。⑧ `item_text` 与 `prefix_search` 都为空 → 输入字符无效果、字符不被列表消费。⑨ 提供 `prefix_search`（10 万行）→ 搜索调用该回调而不是逐行调用 `item_text`（计数 `item_text` 调用次数 = 0）。

**AC-W-LIST-012**　`[回放]` 覆盖：REQ-W-LIST-040、REQ-W-LIST-029。夹具：100 行，视口高 220 lpx（10 行），`row_h` 22，偏移 0，F 0，`multi`。① ↓ ×10 → F 10（行 10 占 [220, 242)），偏移 22（`off_px`）；↓ → F 11，偏移 44。② End → F 99，偏移 = 100 × 22 − 220 = 1980；Home → F 0，偏移 0。③ PageDown（`page_rows` 9）→ F 9，偏移 0（行 9 占 [198, 220) 已完整可见）；再 PageDown → F 18，偏移 = 418 − 220 = 198。④ 前缀搜索使 F 到远处（如行 60）→ 偏移使行 60 完整可见（行 60 占 [1320, 1342) → 偏移 1122）。⑤ Ctrl+↓ 仅移动 F 到视口外 → 同样滚入。⑥ 鼠标滚轮把 F 滚出视口后再按 ↓ → 偏移变为使新 F 可见（最小位移）。

**AC-W-LIST-013**　`[单元]` 覆盖：REQ-W-LIST-001、REQ-W-LIST-002、REQ-W-LIST-003、REQ-W-LIST-004、REQ-W-LIST-005、REQ-W-LIST-006、REQ-W-LIST-007、REQ-W-LIST-009。夹具：`count` = 100000，`row_h` = 22，`scale` = 1.0，视口高 660 lpx（`vp_px` 660），`scrollbar = auto`，已稳定。预期（下标范围为含两端，节点数 = 行节点数）：偏移 0 → 产出 [0, 34]（35 个）；偏移 22000（行 1000 对齐）→ [995, 1034]（40 个）；偏移 22011 → `first_vis` 1000、`last_vis` = floor((22011 + 659) / 22) = 1030 → [995, 1035]（41 个）；最大偏移 = 100000 × 22 − 660 = 2199340 → `first_vis` 99970、`last_vis` 99999 → [99965, 99999]（35 个）。内容总范围 `virtual_extent_px` 高 = 2 200 000 ppx 精确；无前导占位节点，各行 `virtual_pos_px.y = i × 22 − off_px`（如偏移 22011 时行 995 的位置为 −121）。`scale` = 1.25：`row_px` = round(27.5) = 28，视口 825 ppx → 偏移 0 时 `last_vis` = floor(824 / 28) = 29 → [0, 34]。首次出现（`viewport = null`）：产出 [0, 31] 共 32 行，布局后经反馈第二遍变为 [0, 34]；`frame.build_passes` 该帧 +2。`count` = 0 → 无行节点；`count` = 3 → 产出 [0, 2]。虚拟内容容器的子项只有行节点；行节点高恒为 22 lpx。在迭代中 `break` → 调试构建断言中止；`begin`/`end` 平衡检查通过于正常耗尽。内容范围超过 2^53 ppx（如 `count` = 2^50、`row_px` = 22）→ 调试构建断言。

**AC-W-LIST-014**　`[计量]` 覆盖：REQ-W-LIST-005、REQ-W-LIST-009、REQ-W-LIST-051。前置：S-VLIST-SCALE 夹具，视口 660 lpx，`row_h` 22，相同偏移（行 1000 对齐）。步骤与预期：`count` 分别为 1 万、10 万、100 万 → 稳定帧 `frame.nodes` 三次读数完全相等，`list.virtual_nodes` 均为 40；视口改为 330 lpx（15 行可见）→ `list.virtual_nodes` = 25（15 + 10），`frame.nodes` 随可见行数线性变化（两点间比例误差 ≤ 5%）；滚动一行（偏移 +22）→ 该帧 `list.virtual_nodes` 仍为 40，`layout.measured_nodes` ≤ 1 行节点及其内容；滚动前后读数相等。

**AC-W-LIST-015**　`[单元]` 覆盖：REQ-W-LIST-008、REQ-W-LIST-014、REQ-W-LIST-015、REQ-W-LIST-052。夹具：10 行，`key_of(i)` = 稳定键（初始顺序 A..J，A 为 0），`index_of` 已提供，`Sel` = {C, D}，F = D（下标 3），A = C（下标 2）。① 数据变为顺序 D, C, A, B, E…（C、D 前移）→ 选中仍为 {C, D}（下标 1、0），F 键 D 下标 0，A 键 C 下标 1，不报告 `selection_changed`。② 删除 D → F 取下标 3 夹紧后（原下标 3 对应的新行），A 保持 C；`Sel` 仍含 D 的键，`selected_visible` 不计入；`pruneTo` 后移除 D。③ 未提供 `index_of`：重排后 F、A 保持原下标 3、2（键更新为新行的键）。④ `key_of = null`：数据重排后选中停留在下标 {2,3}；且 `reorder = true` 时调试构建断言；`count` 变小时 1 条 `warn`。⑤ 删除到 `count` = 0 → F、A 清空；偏移夹紧；恢复数据后偏移不自动恢复。⑥ `count` 从 100 变为 20 且偏移 1000（行 45）→ 偏移夹紧为 max(0, 440 − 视口)。⑦ `key_of` 返回重复键 → 调试构建中止并报告两处调用点。

**AC-W-LIST-016**　`[回放]` 覆盖：REQ-W-LIST-042、REQ-W-LIST-043、REQ-W-LIST-044。夹具 S10 并 `reorder = true`，`key_of` 已提供，`Sel` = {2,3}，系统 `drag_size` 4 ppx。① 在选中行 3 按下并垂直移动 10 lpx 以上 → 拖拽开始（`beginDrag` 载荷 `kind = list_reorder_kind`，源为列表）；`Sel` 不变。② 拖到 y = 149（`ins` = floor((149 + 11) / 22) = 7）→ 覆盖层放置指示线位于 y = 154（= 7 × 22）、宽 = 视口宽、厚 2 个发丝线；释放 → `reordered` = {keys [2,3], insert_at 7}，选择不变；构建后数据按此重排（应用执行）→ 条目 2,3 位于新下标 5,6，选中仍为这两个键。③ 放置在 y = 50（`ins` 2）、y = 80（`ins` 4）→ 无 `reordered`（连续块边界之内）；y = 91（`ins` 4）同；y = 113（`ins` 5）→ `reordered` = {[2,3], 5}。④ `Sel` = {1,5}：拖动行 5，放置于 `ins` 3 → `reordered` = {[1,5], 3}。⑤ 拖动中按 Esc → 无 `reordered`，指示线下一帧消失，选择不变；指针移出列表后释放 → 无 `reordered`。⑥ 另用 100 行夹具（视口 220 lpx，偏移 0）：拖动过程中指针靠近视口底边（深入 22 lpx）→ 每 33 ms 偏移 +11（REQ-W-SCROLLVIEW-017），指示线随偏移更新。⑦ 另一个列表的拖动载荷（`data` 不同）不被本列表接受：不画指示线，不报告。⑧ `reorder = false` 时拖动行 → 无拖拽开始，指针按普通点击处理。

**AC-W-LIST-017**　`[回放]` 覆盖：REQ-W-LIST-012。夹具：100 行，视口 220 lpx，`row_h` 22，`wheel_lines = lines(3)`。步骤与预期：`wheel -1` → 偏移 66（3 行，`offset −= n × 3 × line`）；`wheel 1` → 回到 0；`page` 设置：`wheel -1` → 偏移 198（视口 220 − 22）；`lines(0)`：滚轮无变化；高精度 4 个 `wheel -0.25` → 累计 66；滚到末端后继续滚轮（外层为滚动视图）按 scroll-view 的边界吸收规则冒泡。列表自身无横向滚动：Shift+`wheel -1` → 冒泡到外层。滚动条拖动、按槽翻页与 scroll-view 一致：按槽一页 = 198。

**AC-W-LIST-018**　`[计量]` 覆盖：REQ-W-LIST-049、REQ-W-LIST-050、REQ-W-LIST-051。夹具：10 万行，视口 30 行，已稳定。步骤与预期：指针移入/移出行 X → 构建遍数 0，损伤 ≤ 行 X 矩形面积；单击使选中从行 3 变为行 7 → 损伤 = 行 3 ∪ 行 7（两个矩形，面积 ≤ 2 行）；Shift+单击区间 [3,7] 自 {3}→{3..7} → 损伤为变化的 4 行；以相同参数 `invalidate(.build)` → 损伤为空，`frame.presents` 不变；列表失焦（Tab 走）→ 选中行与焦点行损伤、非选中行无损伤；改变应用传入的 `empty_text`（`count` = 0 时）→ 损伤仅为列表矩形；`alternate_rows` 切换 → 损伤为列表矩形。S-VLIST-100K 回放（1010 帧，每帧 `wheel -1`）→ `time.frame_cpu` P99 ≤ 2.0 ms；1 万与 100 万行的 `time.build` P99 之比 ≤ 1.5。

**AC-W-LIST-019**　`[单元]` 覆盖：REQ-W-LIST-048。经假 UIA 入口：列表 ControlType List，Selection 的 CanSelectMultiple 与 `mode` 一致，IsSelectionRequired 假；行 ControlType ListItem，Name = `item_text(i)`；`SelectionItem.Select` 于行 3 → 下一帧 {3}；`AddToSelection` 于行 5（`multi`）→ {3,5}；`RemoveFromSelection` 于行 3 → {5}；`single` 下 `AddToSelection` 同 `Select`；`ScrollItem.ScrollIntoView` 于远处行 → 偏移为使其完整可见的最小位移；`Invoke` → 下一帧 `activated` 恰一次；`GetSelection` 只含已创建节点的已选行（虚拟化下，选中行 60 而视口显示 0–29 时返回不含它）。

**AC-W-LIST-020**　`[回放]` 覆盖：REQ-W-LIST-011、REQ-W-LIST-047、REQ-W-LIST-052。`count` = 0：空状态文字居中；Tab 可聚焦；方向键、Enter、Space、Ctrl+A 均无变化（`selection_changed` 假）；`count` 由 0 变 5 → 行出现，F 仍为空。禁用：`enabled = false` 时点击、键盘均无选择变化，悬停行无底色，选中行为非活动色；按下行（待折叠）期间令列表禁用 → 取消，`Sel` 不变；按下期间令该行从数据中消失 → 选择不变；焦点在列表时令其禁用 → 焦点按 REQ-INPUT-042 转移到 Tab 序中的下一个节点。

**AC-W-LIST-021**　`[回放]` 覆盖：REQ-W-LIST-046。行文字 "非常长的文件名.txt" 在窄行中被省略：悬停并推进假时钟超过系统悬停时间 → 出现提示框，文字为完整文本；未截断的行悬停 → 无提示框；`tooltip_on_truncate = false` → 无；滚动进行中（滚轮事件连续注入）→ 无提示框；提示框锚点矩形 = 该行矩形。

**AC-W-LIST-022**　`[人工]` 覆盖：REQ-W-LIST-012、REQ-W-LIST-019、REQ-W-LIST-023、REQ-W-LIST-039、REQ-W-LIST-051。在真实 Windows 上的示例应用"列表"页（10 万行、100 万行两个数据集，行文本为英文词）：用鼠标与键盘依次验证单击、Ctrl+单击、Shift+单击、在多选上按下后拖动、右键菜单、双击打开；用滚轮与滚动条拖到末端，确认滚动流畅、无空白行闪现；快速拖动滑块与连续按 PageDown 时观察是否有行缺失或重复；输入前缀字符验证搜索与超时；切换系统"滚轮行数"与"整页"设置、深浅色与 150%/200% 缩放。观察要点：选中底色（活动/非活动）、焦点描边、无选择闪烁、拖动 100 万行滑块时 CPU 占用与帧率。

**AC-W-LIST-023**　`[单元]` 覆盖：REQ-W-LIST-003、REQ-W-LIST-053。仿 AC-LAYOUT-031：`count` = 1 000 000，`row_h` = 22，`scale` 1.0，视口高 660 ppx，`virtual_extent_px` 高 = 22 000 000。步骤与预期：① 偏移 `offset_px.y` = 21 999 340（最大）→ 首个可见行下标 999 970，其 `virtual_pos_px.y` = 0，末行（999 999）底边恰在 660；产出范围 [999 965, 999 999]（35 行），行 999 965 的位置 = −110。② 偏移 16 777 217（2^24 + 1）→ 首个可见行 762 600，位置 −17；再 +1 → −18（逐像素精确，无跳变）；相邻两行位置之差恒为 22。③ 遍历树中全部节点，矩形坐标绝对值均 ≤ 660 + 5 × 22。④ `scale` 1.5、行高 33 ppx、`virtual_extent_px` = 33 000 000 重复 ①，结果按相同公式成立。⑤ 键盘 End → 偏移 = 22 000 000 − 660，F = 999 999；Home → 0。滚动条槽/滑块按 scroll-view AC-W-SCROLLVIEW-017 的算例换算。

## 17. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-W-LIST-01 | 可变行高（每行高度由内容决定） | 本版不支持：固定行高是虚拟化 O(1) 定位与 O(可见行) 构建的前提。若要支持，需要应用提供 `height_of(index)` 与前缀和索引（如 Fenwick 树），并改写 REQ-W-LIST-004 的窗口公式 |
| OPEN-W-LIST-02 | 前缀搜索的累积超时 `T_ta` | 倾向 1000 ms 常量（与 Windows 列表的数量级一致）；可改为读取系统"键盘延迟"并加倍，待 03 增补键盘重复字段后再定 |
| OPEN-W-LIST-03 | 鼠标拖动框选（橡皮筋）、`multi` 下按住左键上下拖动扩展选择 | 不提供；与拖动重排冲突且需要空白区域；用 Shift+单击与 Shift+方向键代替 |
| OPEN-W-LIST-04 | PageUp/PageDown 的原生行为是"先到视口首/末可见行、再翻页" | 本文采用固定的 `page_rows` 行位移（确定、可回放），有意偏离原生 |
| OPEN-W-LIST-05 | 虚拟化下 UIA 项的提供方式 | 倾向 ItemContainer + VirtualizedItem 模式：未创建的行经 `FindItemByProperty`（按 `item_text`/下标）与 `Realize`（触发滚入）按需实现；M6 细化 |
| OPEN-W-LIST-06 | 全选 100 万行的 O(count) 成本与内存 | 先接受（用户触发的一次性操作）；若成为问题，改为"全选标志 + 排除集"的紧凑表示，接口不变 |
| OPEN-W-LIST-07 | （已关闭，见 REQ-W-LIST-003、REQ-W-LIST-053：07 REQ-LAYOUT-054 的大内容坐标机制） | — |
| OPEN-W-LIST-08 | （已关闭，见 5.2：`drawRowFocus`（REQ-THEME-038）） | — |
| OPEN-W-LIST-09 | 列表项的交替行与分隔线（行间 `border_subtle`）是否同时提供 | 仅提供交替行；行间分隔线留给 table 的网格线选项 |
| OPEN-W-LIST-10 | 拖动重排是否支持跨列表拖放与外部拖出（OLE，08 REQ-INPUT-061） | 不支持；`DragPayload.external` 保持空 |
| OPEN-W-LIST-11 | （已关闭，见 table.md REQ-W-TABLE-034：12 已登记 `list.virtual_cells`） | — |
