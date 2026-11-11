# 滚动容器（scroll-view）

## 1. 用途

为超出可用空间的内容提供视口、滚动偏移与滚动条。参照 Windows 的标准滚动条（`SBS_*`/窗口滚动条）与带滚动条的客户区。本文把 07 的 `Scroll` 容器（布局语义）写成**控件的交互行为**：滚动条的绘制与操作、滚轮、键盘、焦点移动时的自动滚入、拖放时的边缘自动滚动。布局语义（滚动条占位、两条滚动条的收敛、偏移夹紧与保持）一律引用 07 的 REQ-LAYOUT-028 至 REQ-LAYOUT-033，不在此重复。

- 内容很长且逐项同构（列表、树、表格）→ 用对应的虚拟化控件（list、tree、table），它们内部复用本控件的滚动条与滚轮规则，但不为不可见项创建节点。
- 只需要两块区域可调大小而不滚动 → 用 splitter。
- 内容需要缩放 → 不适用本控件（本框架不提供缩放容器）。

本控件**不做**平滑滚动动画、惯性滚动、中键自动滚动，见 OPEN-W-SCROLLVIEW-01。

## 2. 解剖

```
┌──────────────────────────┬──┐  ← 视口（裁剪区）
│                          │▲ │
│  内容（一个自动生成的     │█ │  ← 纵向滚动条：槽 + 滑块（无箭头按钮）
│  Column/Row，包住调用方   │█ │
│  声明的全部子节点）       │  │
│                          │  │
├──────────────────────────┼──┤
│ ▒▒▒▒▒▒▒▒▒▒                │■ │  ← 横向滚动条；右下角为角块
└──────────────────────────┴──┘
```

- **视口**：07 的 Scroll 节点内部、扣除滚动条后的矩形，恒裁剪子节点。
- **内容**：滚动视图自动生成的唯一内容容器（Column 或 Row），包住调用方声明的全部子节点；07 要求 Scroll 恰有一个子项，该容器满足之。
- **槽**（track）：滚动条的底，`drawTrack`。
- **滑块**（thumb）：凸起表面，`drawRaised`。
- **角块**：两条滚动条同时显示时右下角 `scrollbar_w × scrollbar_w` 的方块（REQ-LAYOUT-029）。
- 无箭头按钮，无自动隐藏。
- **边框**（可选）：`frame = .sunken` 时在视口外围画内凹表面（`drawSunken`）。

## 3. 度量与布局

| 项 | 取值（令牌） |
|---|---|
| 滚动条宽度（纵向条的宽、横向条的高） | `scrollbar_w` |
| 滑块最小长度 | `scrollbar_thumb_min` |
| 滑块圆角 | `radius_control` |
| 滑块在槽交叉轴上的内缩 | 一个发丝线宽度（REQ-THEME-012），两侧各一 |
| 角块 | `scrollbar_w × scrollbar_w`，纯色 `surface_track` |
| 一"行"的滚动量（`line`） | 选项 `line_step`，缺省 `row_h` |
| 一"页"的滚动量（`page`） | 视口在该轴上的尺寸减去 `line`，且不小于 `line` |
| 拖放边缘带宽度 | `row_h` |
| 绘制外延 | 仅 `focusable` 且无 `frame` 时为 `focus_ring_w`，否则 0 |

**REQ-W-SCROLLVIEW-001**　`beginScrollView`/`endScrollView` 之间声明的全部子节点**必须**被自动包入一个内容容器：`axes = vertical` 或 `both` 时为 Column，`axes = horizontal` 时为 Row（由选项 `content.direction` 覆盖）。内容容器在非滚动轴上 `fill`，在滚动轴上 `fit`（REQ-LAYOUT-028 的无界测量）。`content.padding` 与 `content.gap` 作用于该容器。视口、滚动条、角块的几何一律取自 07 的 `ScrollMetrics`（REQ-LAYOUT-033），本控件不自行求解。

**REQ-W-SCROLLVIEW-002**　默认尺寸策略：主轴 `grow(1)`、交叉轴 `fill`；调用方**可以**经 `layout` 选项覆盖。滚动视图位于对应轴为 `fit` 且无界的父容器内时，其视口随内容增长而永不出现滚动条，调试构建**应当**记录一条 `warn`。

**REQ-W-SCROLLVIEW-003**　滑块长度（ppx 整数）**必须**为：设槽长（滚动条矩形沿滚动方向的长度）`T`、视口尺寸 `V`、内容尺寸 `C`（均为 `ScrollMetrics` 的 ppx 值），`thumb = clamp(round(T × V / C), min(px(scrollbar_thumb_min), T), T)`，`round` 为 0.5 向上；`C ≤ V`（无可滚动量）时不画滑块。即滑块长度与内容比例成正比，且不小于 `scrollbar_thumb_min`（槽短于该值时等于槽长）。

**REQ-W-SCROLLVIEW-004**　滑块位置与偏移的换算**必须**在 ppx 整数上进行：设 `max_off = C − V`、偏移 `off`，滑块起点 `thumb_start = round((T − thumb) × off / max_off)`；反向（拖动换算）`off = round(max_off × thumb_start / (T − thumb))`，`T = thumb` 时偏移恒为 0。两个换算的结果都**必须**夹紧到各自的合法范围。

## 4. 变体与参数

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `axes` | `layout.ScrollAxes` | `vertical` | 可滚动的轴（07） |
| `bar_v`、`bar_h` | `layout.BarPolicy` | `auto` | 滚动条显示策略 `auto`/`always`/`never`（占位规则见 REQ-LAYOUT-029、030） |
| `focusable` | `bool` | `false` | 为真时滚动视图自身可聚焦并响应滚动键（第 7 节） |
| `offset` | `?*core.Vec2` | `null` | 非空时偏移由应用持有（lpx）；空时由框架保留（sticky） |
| `offset_px` | `?*[2]i64` | `null` | 非空时偏移由应用持有（ppx，i64，优先于 `offset`）；虚拟化控件（list、tree、table）用它，使超大内容的偏移精确 |
| `virtual_extent_px` | `?[2]i64` | `null` | 虚拟化内容的总范围（ppx）；非空时内容范围取它而非子节点测量结果 |
| `line_step` | `?f32` | `null` | 一"行"的 lpx 滚动量，空取 `row_h`；内容控件（如 list）按自己的行高指定 |
| `anchor_end` | `bool` | `false` | 透传 `ScrollParams.anchor_end`（REQ-LAYOUT-032），日志类视图跟随末尾 |
| `reveal` | `?core.Rect` | `null` | 本次构建把内容坐标系下的该矩形滚入视口（REQ-LAYOUT-032 的 `reveal`），仅本次构建有效 |
| `report_viewport` | `bool` | `false` | 为真时在 Scroll 节点上设置布局反馈标志，视口尺寸变化触发同帧第二构建遍（REQ-FRAME-031）；虚拟化内容必须置真 |
| `frame` | `enum { none, sunken }` | `none` | 视口外围是否画内凹边框 |
| `content` | `ScrollContent` | `{}` | 内容容器的 `direction`、`padding`、`gap` |
| `layout` | `layout.ItemOptions` | `{}` | 07 |
| `enabled`、`key`、`debug_name` | 通用 | | 见模板 |

变体只有 `frame`，属于结构性选项。滚动条本身没有任何可由实例指定的外观参数。

## 5. 状态

### 5.1 状态机

状态变量：`bar ∈ {无, 拖滑块, 按槽}`（滚动条上的鼠标操作，同一时刻至多一个），`auto ∈ {无, 拖放中}`（边缘自动滚动）。悬停、聚焦、禁用由框架维护（08）。

| 当前 `bar` | 事件 | 条件 | 下一 `bar` | 动作 |
|---|---|---|---|---|
| 无 | 左键按下 | 落在滑块上 | 拖滑块 | 隐式捕获（REQ-INPUT-013）；记下抓取偏移 `grab = 指针沿轴坐标 − thumb_start` |
| 无 | 左键按下 | 落在槽的空白处，无 Shift | 按槽 | 锁定方向；立即滚动一页；登记首次重复定时器 |
| 无 | 左键按下 | 落在槽的空白处，Shift 按住 | 拖滑块 | 滑块中心跳到指针处；`grab = thumb / 2`；此后同"拖滑块" |
| 无 | 左键按下 | 落在角块或不可滚动的槽 | 无 | 无 |
| 拖滑块 | 指针移动 | — | 拖滑块 | 偏移 ← 反向换算（REQ-W-SCROLLVIEW-004），与指针是否仍在滚动条内无关 |
| 拖滑块 | 左键释放 / 捕获取消 / 滚动条消失 / 变为禁用 | — | 无 | 结束 |
| 按槽 | 重复定时器到期 | 指针沿轴坐标仍在滑块的锁定方向一侧 | 按槽 | 再滚动一页 |
| 按槽 | 重复定时器到期 | 指针已落入滑块范围或越过滑块 | 按槽 | 不滚动（不反向） |
| 按槽 | 左键释放 / 捕获取消 / 滚动条消失 / 变为禁用 | — | 无 | 取消定时器 |

| 当前 `auto` | 事件 | 条件 | 下一 `auto` | 动作 |
|---|---|---|---|---|
| 无 | 拖放开始（`ui.dragInfo()` 非空）且指针进入本视图的边缘带（REQ-W-SCROLLVIEW-017） | 该轴上仍可滚动 | 拖放中 | 登记自动滚动定时器 |
| 拖放中 | 定时器到期 | 指针仍在边缘带内 | 拖放中 | 滚动一个自动滚动步长 |
| 拖放中 | 拖放结束/取消，或指针离开边缘带，或该方向已到端点 | — | 无 | 取消定时器 |

### 5.2 视觉表现

| 部件 | 状态 | 绘制（基元 + 令牌） |
|---|---|---|
| 槽 | 常态 | `drawTrack`（`surface_track` + 顶部 `inset_shadow`，圆角 `radius_mark`） |
| 槽 | 有可滚动量与无可滚动量（`always` 策略） | 画法相同；无可滚动量时不画滑块 |
| 滑块 | 常态 | `drawRaised(neutral, radius_control, Visual{})`，沿槽交叉轴两侧各内缩一个发丝线宽度 |
| 滑块 | 拖动中（`bar = 拖滑块`） | 同上，`Visual.pressed` 为真（按下变体 `surface_raised_pressed_*`，顶部内阴影），`dur_instant` 进入、`dur_fast` 退出；按住期间指针移出滑块仍保持按下外观（捕获） |
| 滑块 | 悬停 | `drawRaised(neutral, radius_control, Visual{ hovered })`（悬停变体 `surface_raised_hover_*`，边框 `border_control_hover`），过渡 `dur_fast` |
| 角块 | — | 纯色 `surface_track` 填充 |
| 整体 | 禁用 | 槽照常绘制，滑块不绘制 |
| 焦点 | `focusable` 且焦点可见 | 有 `frame`：`drawSunken` 以 `focused_visible` 绘制（边框换 `accent_mark`）并加 `drawFocusRing`；无 `frame`：对视口外矩形 `drawFocusRing` |

滚动条的颜色与形状不因内容变化而变化；"按槽"期间槽与滑块不加任何额外高亮。

## 6. 鼠标行为

**REQ-W-SCROLLVIEW-005**　滚动条的槽与滑块是 Scroll 下由框架创建的**独立部件节点**（REQ-LAYOUT-055）：槽节点与滑块节点的矩形取自 `ScrollMetrics.bar_v`/`bar_h` 及滑块位置换算，节点 ID 由视图 ID 与固定部件键派生、跨构建稳定；滚动视图对它们调用 `ui.interact`（槽登记 `click`；滑块登记 `click`），因此命中、悬停、按下、捕获都落在各自节点上，滑块有独立的悬停与按下视觉状态（REQ-W-SCROLLVIEW-006、5.2）。内容区域的指针事件由内容子节点接收，不会落到部件节点；角块不是命中目标（命中落到 Scroll 节点本身，无效果）。滚动条未显示时没有部件节点。事件的 `pos` 为相对目标节点左上角的 lpx（08）。

**REQ-W-SCROLLVIEW-006**　**拖动滑块**：在滑块上按下左键时隐式捕获指针；此后每个 `pointer_move` 以 `thumb_start' = clamp(指针沿轴坐标 − 槽起点 − grab, 0, T − thumb)` 重新计算偏移，指针在垂直于滚动轴方向上的位置无关紧要。滑块在 `pressed` 视觉状态下（捕获期间，即使指针移出滑块）保持按下外观；指针移出滚动条区域乃至移出窗口**不得**使滑块弹回原位，也不设"拖远后恢复"的阈值。释放左键、捕获被取消（REQ-INPUT-024）时结束；结束时偏移保持当前值。

**REQ-W-SCROLLVIEW-007**　拖动中内容尺寸变化（滑块长度随之变化）时，下一次移动按新的 `T`、`thumb`、`max_off` 换算；滚动条因内容变短而消失时，拖动结束且不报错。

**REQ-W-SCROLLVIEW-008**　**按槽翻页**：在槽的空白处（滑块之外）按下左键，立即把偏移朝指针所在一侧移动一页（`page`，夹紧到 `[0, max_off]`），并锁定该方向。按住期间按 REQ-W-SCROLLVIEW-009 连发，直到滑块到达指针处：每次定时器到期时，若指针沿轴坐标在滑块锁定方向的一侧外（朝末端：`p ≥ thumb_start + thumb`；朝起始端：`p < thumb_start`）才再滚动一页；否则不滚动，且**不得**反向。释放左键即停止。

**REQ-W-SCROLLVIEW-009**　连发的节奏读取系统键盘重复设置（03，REQ-PLAT-041）：首次重复延迟取 `SystemMetrics.key_repeat_delay_ms`，之后的间隔取 `SystemMetrics.key_repeat_interval_ms`；控件不另设常量。定时器经 `ui.timer(id, interval_ms, .build)` 登记（REQ-FRAME-050），到期时置 `build`。

**REQ-W-SCROLLVIEW-010**　**Shift+按槽**：按下时 Shift 按住（按下瞬间的修饰键状态）则不翻页，而是使滑块中心位于指针处（`thumb_start = clamp(p − 槽起点 − thumb/2, 0, T − thumb)`），偏移按反向换算；随后按 REQ-W-SCROLLVIEW-006 继续作为滑块拖动，`grab = thumb / 2`。

**REQ-W-SCROLLVIEW-011**　**滚轮**：读取系统度量 `SystemMetrics.wheel_lines`（纵向）与 `wheel_chars`（横向）（03，REQ-PLAT-041）。设本次事件累计格数为 `n`（REQ-INPUT-020，浮点；符号与 `WHEEL_DELTA` 及回放命令 `wheel dy` 一致：**`n` 为正表示向上，为负表示向下**）：取 `lines(k)` 时纵向 `offset -= n × k × line`；取 `page` 时 `offset -= n × page`（因此 `wheel -1` 使偏移增大一行数/一页，`wheel +1` 使偏移减小）；取 `lines(0)` 时本视图在该方向上不登记滚轮能力（`WheelCaps` 为假），事件按 REQ-INPUT-019 继续寻找外层或被丢弃。真正的横向滚轮事件（`WM_MOUSEHWHEEL`，`n` 为正表示向右）使 `offset_x += n × k × line`。位移换算为 ppx 后加到偏移并夹紧。

**REQ-W-SCROLLVIEW-012**　**高精度滚轮**：位移在 ppx 上保持累计的小数余数（每轴一个）：每次事件累计 `acc += 位移_px`，实际应用 `round(acc) − 已应用量`（0.5 向上），使任意拆分的小数格（如 4 个 0.25 格）总位移等于整格位移，不因逐次取整而丢失或放大。偏移被夹紧、方向反转或事件间隔不小于 T_chain（REQ-W-SCROLLVIEW-014）时余数清零。本条与 REQ-W-SCROLLVIEW-011、013、014 对两条路径一致：框架保留偏移时由分发阶段直接应用（REQ-INPUT-020、REQ-FRAME-037），应用持有偏移时经收件列表在构建中应用。

**REQ-W-SCROLLVIEW-013**　**Shift+滚轮**横向滚动：08（REQ-INPUT-020）已把按住 Shift 的纵向分量转为横向分量，该分量沿用纵向的符号约定（`wheel -1` 即向下一格），本视图据此 `offset_x −= n × k × line`（`wheel -1` 使横向偏移增大，即内容向左移），位移用 `wheel_chars` 与 `line_step`（横向的"字符"量与"行"量取同一个 `line`）。`axes` 不含横向的视图不登记横向能力，事件继续冒泡。Ctrl+滚轮不处理（`WheelCaps.zoom` 恒假）。

**REQ-W-SCROLLVIEW-014**　**冒泡与边界吸收**：视图按 REQ-INPUT-019 声明 `WheelCaps`：默认依据上一次布局的 `ScrollMetrics`——某方向仍可滚动（偏移未到该方向端点）时对应位为真，因此已在端点的视图把事件让给外层。为避免"刚滚到头的同一手势立即带动外层"，**采用**下述确定规则（边界吸收），其**优先于**上述按可滚动性的声明：当一次滚轮事件使偏移**到达**某方向的端点时，视图进入该方向的"吸收态"，记下该事件的时间戳；吸收态内，只要距上一个同向滚轮事件（被吸收或到达端点者）的间隔**小于** `T_chain`（暂定 150 ms，见 OPEN-W-SCROLLVIEW-02），该方向的 `WheelCaps` **仍声明为真**（即使偏移已在端点），同向事件因此仍以本视图为目标，到达后被**吞掉**（不位移、不冒泡），并刷新时间戳；间隔不小于 `T_chain`（吸收有效期已过）时吸收态结束，该方向的 `WheelCaps` 回到按实际可滚动性声明（端点处为假），事件随之冒泡给外层。反向事件（视图尚可朝反方向滚动）立即结束吸收态并正常滚动。吸收态只由"滚动到达端点"的事件进入：视图在手势开始前就已处于端点（`WheelCaps` 本来为假）时，第一个事件直接冒泡。吸收态以事件时间戳判定，不登记定时器、不置脏（被吞掉的事件不产生帧）；由框架保留偏移时在分发阶段执行，应用持有偏移时由控件在构建中等价执行。

**REQ-W-SCROLLVIEW-015**　滚动条与内容区上的其他鼠标操作：中键、右键的按下与释放在滚动条上不产生任何效果（滚动视图不登记 `context`）；中键**不**触发自动滚动（OPEN-W-SCROLLVIEW-01）；在滚动条上双击与两次单击等价；指针形状恒为箭头（REQ-THEME-032）。在槽或滑块上按下左键时，若 `focusable` 为真，滚动视图按 REQ-INPUT-022 取得焦点（不使焦点变为可见）。

**REQ-W-SCROLLVIEW-016**　滚动视图为禁用（`enabled = false`）时：不响应滚轮、滚动条操作与键盘；滚动条照常占位并以禁用外观绘制（只画槽）；既有偏移保持。

**REQ-W-SCROLLVIEW-017**　**拖放时的边缘自动滚动**（REQ-INPUT-060 把它委托给本文）：应用内拖放进行中（`ui.dragInfo()` 非空），指针位于本视图视口矩形向外扩展 `row_h` 的范围内，且处于某轴方向的边缘带（视口该侧边缘向内 `row_h` 的带，及向外的扩展区）时，按该轴自动滚动。设 `depth` 为指针深入边缘带的距离（0 至 `row_h`，向外扩展区取 `row_h`），则每个定时器周期（取 REQ-W-SCROLLVIEW-009 的间隔）滚动 `max(1, ceil(line_ppx × depth / row_h_ppx / 2))` ppx，方向朝该侧端点。多个嵌套的滚动视图都满足条件时，只有指针所在命中链上**最内层**且在该方向仍可滚动的那一个滚动。该行为与是否存在放置目标无关；拖放结束或取消即停止。

## 7. 键盘行为

滚动视图自身默认**不可聚焦**（`focusable = false`）。键盘用户通过聚焦内容中的控件并依靠自动滚入（REQ-W-SCROLLVIEW-020）访问全部内容。需要无可聚焦子控件的纯阅读区域可滚动时，置 `focusable = true`。

| 键（视图持有焦点，`focusable = true`） | 行为 |
|---|---|
| ↑ / ↓ | 纵向偏移 −/+ 一行（`line`） |
| ← / → | 横向偏移 −/+ 一行（`line`），仅 `axes` 含横向 |
| PageUp / PageDown | 纵向偏移 −/+ 一页（`page`） |
| Home / End | 纵向偏移到 0 / `max_off`；`axes = horizontal` 时对横向 |
| Ctrl+Home / Ctrl+End | 同 Home / End，但 `axes = both` 时到横向的 0 / `max_off`（横纵各一次） |
| 其他键 | 不处理（继续冒泡，Tab 导航照常） |

**REQ-W-SCROLLVIEW-018**　`focusable = true` 时视图可聚焦且为 Tab 停靠；它经 `InteractOpts.handles` 声明处理：键组 `arrows`、`page`、`home_end`（只匹配无修饰或仅 Shift 的按键，REQ-INPUT-028），并在 `extra` 中逐个列出 Ctrl+Home 与 Ctrl+End（带 Ctrl 的组合不被键组匹配）；**不预占**（命令快捷键优先）。`axes` 不含某方向时不声明该方向的键，使之继续向外层冒泡。持有焦点的子控件先于视图处理这些键（REQ-INPUT-030 自焦点节点沿祖先上溯），例如焦点在文本框内时方向键属于文本框。带 Shift 的方向键、PageUp/PageDown 与不带修饰的相同处理；Ctrl+PageUp/PageDown 不声明（留给标签页）。

**REQ-W-SCROLLVIEW-019**　键盘滚动的位移与滚轮使用同一 `line`/`page` 定义，结果夹紧到 `[0, max_off]`；键的自动重复照常重复；到达端点后继续按键无效果且**不**触发边界吸收规则（该规则只针对滚轮）。

**REQ-W-SCROLLVIEW-020**　**焦点滚入**：键盘导航（原因 `tab`、`group`、`mnemonic`）使内部某节点获得焦点后，视图经 `reveal_target` 接收 `reveal{rect}`（REQ-INPUT-044），在该次构建中设置 `ScrollParams.reveal = rect`；07 按"最小位移使其进入视口，矩形大于视口则对齐起始边"处理（REQ-LAYOUT-032）。鼠标点击取得焦点（原因 `pointer`）**不**产生滚入。嵌套的滚动视图各自处理自己的 `reveal`。

**REQ-W-SCROLLVIEW-021**　程序化滚动经 `reveal` 选项（本次构建滚入某矩形）与应用持有的 `offset`（直接改写偏移）完成。二者与用户滚动的先后：同一次构建中 `reveal` 先于用户滚轮的位移生效，位移再叠加其上。

## 8. 焦点

**REQ-W-SCROLLVIEW-022**　`focusable = false` 时视图不是焦点节点、不在 Tab 序中，鼠标点击视图空白处不改变焦点（REQ-INPUT-022：按在不可聚焦区域不清除焦点）。`focusable = true` 时的焦点可见规则、焦点环按 REQ-INPUT-040 与 REQ-THEME-023；获得与失去焦点不产生激活类结果。视图内的焦点控件获得焦点不使视图本身成为焦点节点。

## 9. 文本与输入法

不适用。滚动视图不显示文本、不接受文本输入；聚焦时输入法处于禁用状态。

## 10. 动效

| 属性 | 触发 | 时长令牌 | 缓动 | 影响级别 |
|---|---|---|---|---|
| 滚动位置 | 任何来源的偏移变化 | 无（位置即时到位） | — | 见第 14 节 |
| 滑块（常态 ↔ 悬停） | 指针进入/离开滑块 | `dur_fast` | `ease_out` | paint（`Visual.hover_t`，滑块节点内建） |
| 滑块（→ 按下 / 按下 →） | 拖动开始 / 结束 | `dur_instant` / `dur_fast` | `ease_out` | paint（`Visual.press_t`） |
| 槽 | — | 无 | — | — |
| 焦点环 | 焦点变为可见 | `dur_fast` 淡入，消失瞬时 | `ease_out` | paint（`Visual.focus_t`） |

**REQ-W-SCROLLVIEW-023**　**不做平滑滚动**：所有来源（滚轮、滚动条、键盘、`reveal`、程序化、自动滚动）的偏移变化在**产生它的那一帧**即到位，不经任何时间插值；不做惯性滚动；不响应中键自动滚动。系统动画关闭与否对其无影响。

## 11. 无障碍

| 项 | 值 |
|---|---|
| UIA 控件类型 | 视图：Pane；滚动条：ScrollBar（每条显示的滚动条一个子元素）；滑块不单独暴露 |
| 名称来源 | 视图：`debug_name` 之外由应用经通用的无障碍名称选项提供，缺省无名称；滚动条：固定字符串"垂直滚动条"/"水平滚动条"（取自 `Strings`，11 REQ-APP-042） |
| 支持的模式 | 视图：Scroll；滚动条：RangeValue |
| 状态属性 | 视图：HorizontallyScrollable、VerticallyScrollable、HorizontalScrollPercent、VerticalScrollPercent、HorizontalViewSize、VerticalViewSize（= 视口÷内容，百分数）、IsEnabled、HasKeyboardFocus（`focusable` 时）；滚动条：RangeValue 的 Value = 偏移（lpx）、Minimum = 0、Maximum = `max_off`、SmallChange = `line`、LargeChange = `page`、IsReadOnly = 假 |

**REQ-W-SCROLLVIEW-024**　经 UIA 的 `Scroll(horizontalAmount, verticalAmount)`（`SmallIncrement` = `line`、`LargeIncrement` = `page`、`NoAmount`）、`SetScrollPercent(h, v)`（偏移 = 百分比 × `max_off`）与滚动条的 `RangeValue.SetValue` 所产生的偏移变化，**必须**与用户操作等效：在下一帧生效并夹紧。无该方向可滚动量时 `Scroll` 对应分量被忽略。

## 12. API 草案

```zig
// 草案：仅签名
pub const ScrollFrame = enum { none, sunken };
pub const ContentDirection = enum { column, row };
pub const ScrollContent = struct {
    direction: ?ContentDirection = null,   // null：axes 为 horizontal 时 row，否则 column
    padding: core.Insets = .{ .l = 0, .t = 0, .r = 0, .b = 0 },
    gap: theme.Gap = .none,
};

pub const ScrollViewOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    axes: layout.ScrollAxes = .vertical,
    bar_v: layout.BarPolicy = .auto,
    bar_h: layout.BarPolicy = .auto,
    focusable: bool = false,
    offset: ?*core.Vec2 = null,        // 非空：偏移由应用持有（lpx）；框架读取并在用户滚动时写回
    offset_px: ?*[2]i64 = null,        // 非空：偏移由应用持有（ppx，i64），优先于 offset
    virtual_extent_px: ?[2]i64 = null, // 虚拟化内容的总范围（ppx，REQ-LAYOUT-054）；非空时内容范围取它
    line_step: ?f32 = null,            // lpx；null = row_h
    anchor_end: bool = false,
    reveal: ?core.Rect = null,         // 内容坐标系，lpx；仅本次构建
    report_viewport: bool = false,     // 置布局反馈标志（REQ-FRAME-031）
    frame: ScrollFrame = .none,
    content: ScrollContent = .{},
    layout: layout.ItemOptions = .{},
};

/// 供虚拟化内容在构建时读取（不是结果）：本次构建生效的偏移与上一次布局的视口。
pub const ScrollViewHandle = struct {
    id: ui.WidgetId,
    offset: core.Vec2,                 // lpx，本次构建生效的偏移（已含本帧滚轮/滚动条的位移）
    viewport: ?core.Vec2,              // lpx；首次出现时为 null
    offset_px: [2]i64,                 // ppx，权威偏移（i64，REQ-LAYOUT-054）；虚拟化内容据此定位可见项
    viewport_px: ?[2]i32,              // ppx；首次出现时为 null
    line: f32,                         // lpx，本视图的一"行"
};

pub const ScrollViewResult = struct {
    // 持续性状态
    hovered: bool,
    focused: bool,
    offset: core.Vec2,                 // lpx，上一次布局夹紧后的偏移
    max_offset: core.Vec2,
    viewport: core.Vec2,
    content: core.Vec2,
    // 一次性通知（不触发第二构建遍）
    scrolled: bool,                    // 本帧用户操作使偏移变化
};

pub fn beginScrollView(ui: *Ui, src: std.builtin.SourceLocation, opts: ScrollViewOptions) ScrollViewHandle;
pub fn endScrollView(ui: *Ui) ScrollViewResult;
```

`scrolled` 是一次性通知，**不是**激活类结果，不触发同帧第二构建遍（REQ-FRAME-030 的触发源不含滚动）。`offset` 指针由应用持有，须存活至对应 `endScrollView` 返回；框架只在用户操作时写入。内容容器、滚动条节点由控件内部创建，应用不可见。

## 13. 保留状态

| 字段 | 类型 | 保留级别 | 说明 |
|---|---|---|---|
| `offset` | `core.Vec2`（lpx） | sticky | 应用未提供 `offset` 指针时的滚动位置；被 LRU 回收后回到 0（`anchor_end` 时回到末端） |
| `bar` | `{ part, grab_px, dir, next_due_ms, pointer_axis }` | transient | 拖滑块/按槽的进行状态 |
| `wheel_rem`、`chain_hold` | `{ x, y: f32 }`、`{ dir_v, dir_h, last_ms }` | 框架保留（与 sticky 偏移同槽） | 高精度滚轮余数与边界吸收态；框架保留偏移时由分发阶段维护，应用持有偏移时为 transient |
| `auto` | `{ due_ms }` | transient | 拖放边缘自动滚动 |

滚动视图不是重型控件，不使用保留节点；实际偏移、视口与滚动条矩形取自布局产出的 `ScrollMetrics`（REQ-LAYOUT-033）。控件**应当**在每次构建以 `metrics.offset` 覆盖保存的偏移，防止请求偏移在边界外累积（REQ-LAYOUT-033）。

**REQ-W-SCROLLVIEW-025**　偏移的保存与所有权：应用传入 `offset` 指针时，指针指向的值是唯一事实来源，框架在用户滚动时写回并在下一次构建读取；未传入时偏移保存在 sticky 槽，随窗口生命周期与 LRU 回收（REQ-FRAME-010）。两种情形下 DPI 变化都按 lpx 值重新换算（REQ-LAYOUT-032 末条），内容或视口变化时的保持与夹紧规则取 07，不在本控件重新定义。

## 14. 失效规则

**REQ-W-SCROLLVIEW-026**　滚动相关变化的失效级别与损伤**必须**如下表。**框架保留偏移**（应用未传 `offset` 指针）时，滚轮滚动由分发阶段直接换算并应用到偏移，该事件不进入收件列表，置 `layout`（REQ-INPUT-020、REQ-FRAME-037）；偏移未变（已到端点或被吸收）时不置脏。内容含设置了布局反馈标志的节点（虚拟化控件，或 `report_viewport = true`）时，该节点所在 Scroll 的偏移不同于它构建时所见的值，满足 REQ-FRAME-031 新增的触发条件，升级为一个构建遍（不超过两遍上限）。**应用持有偏移**，以及滑块拖动、按槽、键盘、`reveal` 经收件列表处理，仍为 `build`。因 `layout_hash` 不含 `ScrollParams.offset`（REQ-LAYOUT-045），布局只更新 Scroll 的直接子项位置（REQ-LAYOUT-047）。损伤前节点矩形先与祖先的有效裁剪矩形求交（REQ-FRAME-040），因此内容节点的损伤不超出视口。

| 变化 | 置脏级别 | 损伤范围 |
|---|---|---|
| 滚轮滚动（框架保留偏移；普通内容） | `layout`；构建遍数 0、`layout.measured_nodes` = 0、`layout.arranged_nodes` ≤ 1 | 视口矩形，加上滑块位置变化所涉及的滚动条矩形 |
| 同上，内容含虚拟化子控件 | `layout`，经 REQ-FRAME-031 的"Scroll 内布局反馈节点所见偏移已改变"触发条件升级为**恰 1 个**构建遍 | 视口矩形与滚动条矩形 |
| 滚轮滚动（应用持有偏移） | `build`（收件列表）；布局同第一行 | 视口矩形与滚动条矩形 |
| 滑块拖动中的指针移动、键盘、`reveal` | `build`（被捕获期间的移动/按键，REQ-FRAME-037） | 视口矩形与滚动条矩形 |
| 按槽连发定时器到期 | `build` | 视口与滚动条矩形 |
| 偏移被夹紧后无变化，或滚轮事件被吸收 | 不置脏 | 空 |
| 视图尺寸变化 | `layout` | 整个视图 |
| 悬停进入/离开滑块或槽、滑块按下视觉变化、焦点环显隐 | `paint`（构建遍数 0） | 滑块矩形 / 视图矩形（含外延） |
| 内容变化 | 由应用的模型通知 `build` | 由差分决定 |

（以上为 06 REQ-FRAME-037、040 与 08 REQ-INPUT-020 的落实，不另行定义。）

**REQ-W-SCROLLVIEW-027**　绘制键**必须**由以下各项构成：`axes`、两条滚动条的显示状态与矩形、两条滑块的 `thumb_start` 与 `thumb`（ppx）、滑块是否悬停、是否按下、`enabled`、`frame`、焦点环是否显示。内容节点的绘制键不含偏移（偏移只改变其位置）。布局输入键含 `axes`、`bar_v`、`bar_h`、`anchor_end`（REQ-LAYOUT-045）与内容容器的各项。

**REQ-W-SCROLLVIEW-028**　`report_viewport = true` 的视图在 Scroll 节点上设置布局反馈标志，并经 `ScrollViewHandle.viewport`（即 `ui.lastRect` 所见尺寸，REQ-FRAME-029）把上一次布局的视口提供给内容构建者；视口尺寸变化时同帧执行第二构建遍（REQ-FRAME-031），不超过 REQ-FRAME-032 的两遍上限。滚轮使偏移变化而内容含该标志节点时，依据 REQ-FRAME-031 的新增触发条件（该节点所在 Scroll 的偏移不同于其构建时所见），构建遍数恰为 1。`report_viewport = false` 的视图**不得**设置该标志，使普通内容的尺寸变化与滚轮滚动不额外触发构建。

**REQ-W-SCROLLVIEW-029**　`frame = .sunken` 时视口外围的发丝线边框留位**必须**用 07 的 `Params.border = 1`（REQ-LAYOUT-056：四边各内缩一个发丝线宽度，ppx），不用 lpx 的 `padding` 近似；`frame = .none` 时 `border = 0`。

**REQ-W-SCROLLVIEW-030**　**大内容坐标**：滚动范围与偏移按 REQ-LAYOUT-054 以 64 位整数 ppx 表达。虚拟化内容构建者经 `ScrollViewOptions.virtual_extent_px` 声明内容总范围、经 `ScrollViewHandle.offset_px`（i64 ppx）读取偏移，并以相对视口的整数 ppx 位置（子项的 `virtual_pos_px`）排布可见项；滚动条的滑块长度与位置（REQ-W-SCROLLVIEW-003、004）以 i64 运算，内容范围可达 2^53 ppx 而结果逐像素精确。普通内容不使用该机制。

## 15. 边界与错误情况

| 情况 | 规定 |
|---|---|
| 内容不大于视口 | `auto`：无滚动条；`always`：显示槽、无滑块（禁用外观）；偏移恒 0；滚轮事件不被吸收（能力为假），冒泡 |
| 槽短于 `scrollbar_thumb_min` | 滑块等于槽长，不可拖动，按槽仍翻页（滑块两侧无空白时无处可按） |
| 视口尺寸为 0 | 无滚动条；偏移保持请求值经夹紧后为 0 |
| 按下滑块期间视图消失 | 捕获释放（REQ-INPUT-024），无滚动副作用 |
| 按下期间视图变为禁用 | 取消拖动与连发；偏移保持当前值 |
| 按槽连发期间内容增长/缩短 | 每次到期按最新 `ScrollMetrics` 重新判定"滑块是否到达指针" |
| `offset` 为 NaN 或负数 | 视为 0（REQ-LAYOUT-031） |
| `line_step ≤ 0` | 视为 `row_h`，调试构建记录一条 `warn` |
| `page` 计算结果小于 `line` | 取 `line`（视口小于一行时仍能前进） |
| 嵌套滚动视图方向相同 | 按 REQ-W-SCROLLVIEW-014 在端点处让给外层；键盘滚动只作用于持有焦点的视图 |
| 滚动方向的限制无界（父为 `fit` 无界） | 视口等于内容，无滚动条（见 REQ-W-SCROLLVIEW-002） |
| 滚轮事件同时带 Ctrl | 不处理 |
| DPI 变化 | 偏移按 lpx 重新换算；滑块几何重算 |
| 窗口非活动 | 滚动条外观不变；滚轮仍可作用于悬停的视图（08 的滚轮路由与焦点、活动状态无关） |

## 16. 验收标准

**AC-W-SCROLLVIEW-001**　`[金图]` 覆盖：REQ-W-SCROLLVIEW-003、REQ-W-SCROLLVIEW-005、REQ-W-SCROLLVIEW-006、REQ-W-SCROLLVIEW-015、REQ-W-SCROLLVIEW-016、REQ-W-SCROLLVIEW-029。渲染滚动视图状态矩阵：{仅纵向条, 滑块悬停, 纵横双条（含角块）, `always` 且内容不足（禁用外观）, 滑块拖动中, `enabled=false`, `focusable` 且焦点可见（`frame` 为 `none` 与 `sunken` 各一）}；缩放 1.0/1.5/2.0；浅/深/高对比度。预期：与基准图一致；滚动条宽恒为 `px(scrollbar_w)`；无任何箭头按钮；角块仅在双条时出现；"无可滚动量"状态下无滑块像素；悬停的滑块为悬停变体、拖动中的滑块为按下变体；`frame = .sunken` 的边框内缩为一个发丝线宽度（`Params.border = 1`）；焦点环仅出现在焦点可见的两列。

**AC-W-SCROLLVIEW-002**　`[单元]` 覆盖：REQ-W-SCROLLVIEW-003、REQ-W-SCROLLVIEW-004。`scale` = 1.0，槽长 `T` = 100 ppx，视口 `V` = 100：内容 `C` = 400 → 滑块 25；`C` = 4000 → round(2.5) = 3，夹到 `scrollbar_thumb_min` = 24 → 24；`C` = 100 → 不画滑块。`T` = 100、`V` = 100、`C` = 400（滑块 25，`max_off` = 300）：偏移 0 → `thumb_start` = 0；偏移 150 → round(75 × 150 / 300) = round(37.5) = 38；偏移 300 → 75。反向：`thumb_start` = 38 → round(300 × 38 / 75) = 152。槽长 `T` = 20 < 24：滑块 = 20，任意拖动偏移保持 0。`scale` = 1.5 时 `scrollbar_thumb_min` 换算为 36 ppx，`T` = 150、`V` = 150、`C` = 4500 → 滑块 36。

**AC-W-SCROLLVIEW-003**　`[回放]` 覆盖：REQ-W-SCROLLVIEW-005、REQ-W-SCROLLVIEW-006、REQ-W-SCROLLVIEW-007。前置：纵向视图，视口 200×100 lpx（`scale` 1.0，滚动条宽 12，视口扣除后内容宽 188），内容高 1000，偏移 0；纵向槽长 100、滑块 24（`max_off` 900，可动范围 76）。步骤与预期：在滑块中点 (194, 12) 按下 → 捕获者为视图、`grab` = 12；移到 (194, 50) → `thumb_start` = 38，偏移 = round(900 × 38 / 76) = 450；再移到 (600, 200)（远离滚动条）→ `thumb_start` 被夹紧到 76，偏移 900，无弹回；移回 (194, 40) → `thumb_start` = 28，偏移 round(900 × 28 / 76) = 332（331.6）；释放 → 偏移保持 332，捕获者为空。拖动中令应用把内容高度改为 300（`max_off` 200）→ 下一次移动按新值换算且偏移 ≤ 200；令内容高度改为 50（`auto` 下滚动条消失）→ 拖动结束，捕获者为空，偏移 0。

**AC-W-SCROLLVIEW-004**　`[回放]` 覆盖：REQ-W-SCROLLVIEW-008、REQ-W-SCROLLVIEW-009。前置：同 AC-W-SCROLLVIEW-003 的视图，`line` = 22（`row_h`），`page` = 100 − 22 = 78，使用假时钟，并把 `SystemMetrics.key_repeat_delay_ms` 设为 500、`key_repeat_interval_ms` 设为 33（另做一次设为 250/100 的重复，首次重复与间隔随之改变）。步骤与预期：在槽 y = 90 处按下（滑块 [0, 24)）→ 立即偏移 78；推进 499 ms → 仍为 78；推进到 500 ms → 156；此后每 33 ms 再 +78，直到偏移 858（第 11 次滚动；此时 `thumb_start` = round(76 × 858 / 900) = 72，滑块 [72, 96) 覆盖 y = 90）；再推进 200 ms → 偏移仍为 858，且无定时器登记。另一子用例：偏移 780（`thumb_start` = 66，滑块 [66, 90)）时指针仍在 y = 90 → 该次到期仍滚动（`p ≥ thumb_start + thumb`），到 858 后停止。反向用例：偏移 900，在 y = 5 按下（滑块 [76, 100) 之上）→ 偏移 822，之后每次到期再 −78，在偏移 42（第 11 次滚动；此时 `thumb_start` = 4，指针 `p = 5` 不再小于它）后停止；另一次按住期间把指针移到 y = 95（滑块范围内）→ 不再滚动且不向末端反向。释放后推进时间 → 无变化。

**AC-W-SCROLLVIEW-005**　`[回放]` 覆盖：REQ-W-SCROLLVIEW-010。前置：同 AC-W-SCROLLVIEW-003。步骤与预期：按住 Shift 在槽 y = 50 按下 → 偏移 = round(900 × (50 − 12 = 38) / 76) = 450（`thumb_start` = 38），无翻页；不释放，移到 y = 80 → `thumb_start` = 68，偏移 = round(900 × 68 / 76) = 805；释放。在 y = 3 处 Shift+按下 → `thumb_start` 夹紧到 0，偏移 0。

**AC-W-SCROLLVIEW-006**　`[回放]` 覆盖：REQ-W-SCROLLVIEW-011、REQ-W-SCROLLVIEW-012、REQ-W-SCROLLVIEW-013。前置：视图视口高 100，内容高 2000，`line` = 22，`axes = both` 且横向内容宽 800。步骤与预期：`wheel_lines = lines(3)`：`wheel -1` → 偏移 66（`offset −= (−1) × 3 × 22`）；`wheel 1` → 0。四个 `wheel -0.25` 事件连续 → 累计应用 17、16、17、16（合计 66 ppx，偏移 66）。`wheel_lines = page`：`wheel -1` → 偏移 78。`wheel_lines = lines(0)`：`wheel -1` → 偏移不变，且事件冒泡给外层视图（外层偏移变化）。Shift+`wheel -1` → 横向偏移 = `wheel_chars = lines(3)` × 22 = 66（增大），纵向不变；Shift+`wheel 1` → 横向偏移回到 0。`axes = vertical` 的视图上 Shift+`wheel -1` → 本视图无变化，事件冒泡到外层。Ctrl+`wheel -1` → 无变化。

**AC-W-SCROLLVIEW-007**　`[回放]` 覆盖：REQ-W-SCROLLVIEW-014。前置：外层视图（视口高 200，内容高 1000）内含内层视图（视口高 100，内容高 200，`max_off` = 100），内层偏移 80，`wheel_lines = lines(3)`、`line` = 22（一格 = 66），`T_chain` = 150 ms，假时钟，t = 0 为第 1 个事件。步骤与预期（`wheel -1` 为向下一格）：在 t = 0、50、100、150、200 ms 注入 5 个 `wheel -1`：t = 0 → 内层偏移 80 + 66 夹紧为 100（到达端点，进入吸收态，时间戳 0）、外层偏移 0；t = 50、100、150、200 → 各自距上一个同向事件 50 ms < 150 ms，吸收态内内层 `WheelCaps.down` 仍声明为真，事件到达内层后被吞掉，内层仍为 100、外层仍为 0，时间戳依次刷新到 200。t = 349（距 200 为 149 ms < 150 ms）再注入 1 个 → 仍被吞掉，外层 0，时间戳刷新到 349。t = 499（距 349 为 150 ms，吸收有效期已过）再注入 1 个 → 内层 `WheelCaps.down` 回到按实际可滚动性（端点处为假），事件冒泡，外层偏移 66，内层 100。变体 A（反向）：吸收态内（如 t = 100）注入 `wheel 1` → 内层偏移 100 − 66 = 34，吸收态结束；随后的 `wheel -1` 使内层 34 + 66 = 100 再次到达端点并重新进入吸收态。变体 B（手势前已在端点）：内层偏移 100，且距上次事件已超过 `T_chain` 后的第一个 `wheel -1` → 直接使外层偏移 66，内层不变。变体 C：被吞掉的事件不产生帧（`frame.count` 不变），也不登记任何定时器；吸收态按事件时间戳判定（间隔 149 ms 吸收、150 ms 冒泡）。变体 D：偏移由应用持有（`offset` 指针）时上述各步结果相同。

**AC-W-SCROLLVIEW-008**　`[回放]` 覆盖：REQ-W-SCROLLVIEW-015、REQ-W-SCROLLVIEW-022。前置：`focusable = false` 的视图，视口内有一个文本框 A，焦点在 A。步骤与预期：在滚动条的槽、滑块与内容空白处按下左键 → 焦点保持在 A；中键、右键按下释放各一次 → 偏移不变、无上下文菜单请求；中键按下后移动指针 100 lpx → 偏移不变（无自动滚动）；指针形状在滚动条、内容空白处均为箭头。`focusable = true` 时按下槽 → 视图取得焦点且焦点不可见；Tab 序中含该视图。

**AC-W-SCROLLVIEW-009**　`[回放]` 覆盖：REQ-W-SCROLLVIEW-018、REQ-W-SCROLLVIEW-019、REQ-W-SCROLLVIEW-021。前置：`focusable = true`，视口高 100，内容高 1000，`line` = 22，`page` = 78，`axes = vertical`，视图持有焦点。步骤与预期：↓ → 偏移 22；PageDown → 100；PageUp → 22；End → 900；再按 PageDown → 900（无效果）；Home → 0；→ 键 → 不被视图处理（`axes` 不含横向，键冒泡）；Ctrl+Home 同 Home（它在 `extra` 中逐个列出）；Ctrl+PageDown → 不被视图处理（冒泡，外层标签页可换页）。`axes = both`（横向内容宽 500、视口宽 188）：→ 横向偏移 22；Ctrl+End → 纵向 900、横向 312。焦点在内部文本框时按 ↓ → 视图偏移不变（文本框处理）。已有命令快捷键绑定 PageDown 时按 PageDown → 触发命令而非滚动。

**AC-W-SCROLLVIEW-010**　`[回放]` 覆盖：REQ-W-SCROLLVIEW-020、REQ-W-SCROLLVIEW-021。前置：视口高 100，内容为 30 个高 22 的按钮（节点 B0…B29，无间距），偏移 0，B0 持有焦点。步骤与预期：Tab 到 B5（顶 110、底 132，超出视口）→ 偏移 32（最小位移使底边与视口底对齐）；Tab 到 B6 → 偏移 54；再 Shift+Tab 六次回到 B0 → 偏移 0（矩形整体在视口上方，对齐其起始边）。用鼠标点击 B20（需先经滚轮滚出可见）→ 点击聚焦不产生 `reveal`，偏移不变。另在偏移 0 的构建中把 `reveal` 选项设为内容坐标 (0, 500, 10, 22) → 本次构建偏移 = 522 − 100 = 422（底边对齐视口底）。

**AC-W-SCROLLVIEW-011**　`[回放]` 覆盖：REQ-W-SCROLLVIEW-017。前置：视口高 200 lpx、`row_h` 22，内容高 2000，偏移 500；应用内拖放进行中（任意 payload）。步骤与预期：指针在视口内中部 → 偏移保持；指针位于视口底边向内 22 lpx 的边缘带最深处（`depth` = 22）→ 每 33 ms 偏移 +`max(1, ceil(22 × 22 / 22 / 2))` = +11；指针在 `depth` = 11 → +`ceil(22 × 11 / 22 / 2)` = +6（5.5 向上）；指针在视口底边外 10 lpx（扩展区内，`depth` 取 22）→ +11；指针在底边外 30 lpx（超出扩展区）→ 无滚动；拖放按 Esc 取消 → 立即停止；偏移到达 `max_off` → 停止。嵌套的内层视图在该方向已到端点时，外层视图（指针也在其视口内）接管滚动。

**AC-W-SCROLLVIEW-012**　`[计量]` 覆盖：REQ-W-SCROLLVIEW-023、REQ-W-SCROLLVIEW-026、REQ-W-SCROLLVIEW-027、REQ-W-SCROLLVIEW-028。前置：视图内含 `Column` 200 行（共 601 个节点），已完成一次布局，`report_viewport = false`，偏移由框架保留。步骤与预期：① 注入一个 `wheel -1`（向下一格）→ 恰产生一帧，`frame.build_passes` +0（构建遍数 0），`layout.measured_nodes` = 0，`layout.arranged_nodes` ≤ 1，偏移在该帧即达到目标值（无后续动画帧，`loop.block_waits` 随后 +1），损伤面积 ≤ 视口矩形面积 + 滚动条矩形面积（物理像素）。② 偏移已在端点再滚同向一格（或事件被边界吸收）→ 不置脏，`frame.count` 不变。③ 视图内含设置了布局反馈标志的节点（`report_viewport = true`）→ 一个 `wheel -1` → 恰 1 个构建遍（`frame.build_passes` +1）。④ 应用持有 `offset` 指针 → 一个 `wheel -1` 经收件列表，`frame.build_passes` +1。⑤ 拖动滑块一步、键盘 ↓ 一次 → 各一帧 `build`。⑥ 指针移入/移出滑块、按下滑块 → 构建遍数 0，损伤 ≤ 滑块矩形面积；悬停时滑块为悬停变体（金图）。⑦ 以相同参数重建一次（`invalidate(.build)`）→ 损伤为空，`frame.presents` 不变。⑧ 改变窗口尺寸使视口宽变化 → 不触发第二构建遍；把 `report_viewport` 置真后重复 → 第二遍出现。

**AC-W-SCROLLVIEW-013**　`[单元]` 覆盖：REQ-W-SCROLLVIEW-001、REQ-W-SCROLLVIEW-002、REQ-W-SCROLLVIEW-025。步骤与预期：在视图内声明 3 个子节点 → 内容 Column 恰一个，三个子节点为其子项；`axes = horizontal` → 内容为 Row。传入应用持有的 `offset`（lpx），用户滚动后该值被写回为夹紧值；改写该值 → 下一次构建偏移跟随。不传 `offset` 时：滚动到 300 后把视图移出树一次构建再恢复（sticky 槽保留）→ 偏移仍为 300；使槽被 LRU 回收后恢复 → 偏移 0。`scale` 由 1.0 改为 1.5：偏移 100 lpx 保持 100 lpx（150 ppx）。默认尺寸策略：主轴 `grow(1)`、交叉轴 `fill`。视图置于 `fit` 无界的父内 → 调试构建产生 1 条 `warn`。

**AC-W-SCROLLVIEW-014**　`[单元]` 覆盖：REQ-W-SCROLLVIEW-024。经假 UIA 入口：Pane 类型且 Scroll 模式；`Scroll(NoAmount, LargeIncrement)` → 下一帧纵向偏移 +`page`；`SetScrollPercent(NoAmount, 50)`（`max_off` = 900）→ 偏移 450；对滚动条查询 → ScrollBar 类型、RangeValue：Value 450、Min 0、Max 900、SmallChange `line`、LargeChange `page`；`SetValue(2000)` → 夹紧为 900；`VerticalViewSize` = 视口÷内容 × 100。无可滚动量方向的 `Scroll` 分量被忽略。

**AC-W-SCROLLVIEW-015**　`[回放]` 覆盖：REQ-W-SCROLLVIEW-016。`enabled = false`：滚轮、滚动条拖动、键盘（`focusable = true` 时）均不改变偏移；滚动条仍占位，只画槽；窗口内其他控件不受影响；拖动进行中令 `enabled` 变假 → 拖动取消，捕获者为空，偏移保持。

**AC-W-SCROLLVIEW-016**　`[人工]` 覆盖：REQ-W-SCROLLVIEW-009、REQ-W-SCROLLVIEW-011、REQ-W-SCROLLVIEW-017、REQ-W-SCROLLVIEW-023。在真实 Windows 上：把系统"滚轮一次滚动的行数"依次设为 1、3、20 与"一次一个屏幕"，用实体滚轮与高精度触控板滚动一个长文档视图，确认位移与系统设置一致；按住槽空白处观察连发节奏与系统键盘重复延迟/速度设置一致（`SystemMetrics` 增补之后）；在资源管理器式文件拖放（应用内拖放示例页）时拖到视图边缘确认自动滚动平稳可控；确认滚动无动画过渡、无惯性、中键无自动滚动。观察要点：无拖尾、无回弹、速度与设置对应。

**AC-W-SCROLLVIEW-017**　`[单元]` 覆盖：REQ-W-SCROLLVIEW-005、REQ-W-SCROLLVIEW-030。前置：虚拟化内容（`virtual_extent_px` 高 = 22 000 000 ppx），视口高 660 ppx，纵向槽长 660，`scale` 1.0（仿 AC-LAYOUT-031）。步骤与预期：保留树中该视图下存在槽与滑块两个部件节点，连续两次构建其 ID 不变；指针在滑块上 → 命中滑块节点，在槽空白处 → 命中槽节点，在内容区 → 命中内容子节点。滑块长度 = clamp(round(660 × 660 / 22 000 000) = 0, 24, 660) = 24；偏移 `offset_px.y` = 16 777 217（2^24 + 1）→ `thumb_start` = round(636 × 16 777 217 / 21 999 340) = 485，反向换算 485 → 偏移 16 776 226（拖动换算结果为整数、无 f32 舍入）；偏移 21 999 340（最大）→ `thumb_start` = 636；偏移 0 → 0。拖动滑块使 `thumb_start` 由 485 变为 486 → 偏移变化量 = 34 590（= round(21 999 340 × 486 / 636) − round(21 999 340 × 485 / 636)，取整结果逐步单调、无回退）。树中全部节点矩形坐标绝对值 ≤ 视口尺寸 + 缓冲。

## 17. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-W-SCROLLVIEW-01 | 是否提供平滑滚动动画、惯性滚动、中键自动滚动 | 不提供。理由：位置即时到位使每次滚动只产生一帧、无连续出帧的动画耗电，与被动刷新（ADR 0006）和性能预算一致；平滑滚动在大列表上需要逐帧构建；克制符合 Instrument 的"动效极少"（ADR 0009）。若日后提供，应作为可被系统动画开关关闭的选项 |
| OPEN-W-SCROLLVIEW-02 | 边界吸收的 `T_chain`（暂定 150 ms）是否应与系统度量联动，或可由应用调整 | 先用常量（以事件时间戳判定）；真实设备（高精度触控板的尾部事件）实测后再定 |
| OPEN-W-SCROLLVIEW-03 | （已关闭，见 REQ-W-SCROLLVIEW-009：03 已增补键盘重复字段） | — |
| OPEN-W-SCROLLVIEW-04 | （已关闭，见 REQ-W-SCROLLVIEW-026：06 已规定滚轮 layout 级路径与损伤求交） | — |
| OPEN-W-SCROLLVIEW-05 | （已关闭，见 REQ-W-SCROLLVIEW-005：滑块为独立部件节点，有悬停与按下状态） | — |
| OPEN-W-SCROLLVIEW-06 | （已关闭，见 REQ-W-SCROLLVIEW-029：`Params.border`） | — |
| OPEN-W-SCROLLVIEW-07 | 是否提供滚动条上的上下文菜单（"滚动到此处"等） | 不提供 |
| OPEN-W-SCROLLVIEW-08 | 滚动条是否应支持把 `Shift` 之外的修饰键用于精细拖动 | 不提供 |
