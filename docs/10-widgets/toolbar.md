# 工具栏（toolbar）

## 1. 用途

把一组常用动作排成一行图标按钮（可含文字），放在窗口或面板顶部，供鼠标快速点击、键盘用方向键遍历。工具栏内可放**安静按钮**（quiet）、分隔符，以及固定的下拉框、文本框等；放不下的项收进末端的**溢出菜单**，不换行。参照 Windows 的 ToolBar（`ToolbarWindow32`）与 Win32 应用的命令栏。

- 动作很少且需要突出 → 直接用 button（`neutral`/`accent`），不要放进工具栏。
- 需要层级与文字说明的大量动作 → 用菜单栏与菜单（menu 控件，见 menu.md）；工具栏与菜单栏**共用同一批命令**（11 的 `ui.command`）。
- 竖直的工具栏、多行工具栏、可拖动浮动工具栏 → 不支持（ADR 0007：不做 wrap；见 OPEN-W-TOOLBAR-01）。
- 工具栏按钮的外观与行为遵循 button 的 `quiet` 变体（button.md），本文只写工具栏特有的部分。

## 2. 解剖

```
 ┌─────────────────────────────────────────────────────────────────┐
 │ [▓] [▓] [▓]│[▓ 文字] [▓]│ [下拉框 ▾] [文本框        ]        [⋯] │   ← 容器 = surface_panel
 └─────────────────────────────────────────────────────────────────┘
 ───────────────────────────────────────────────────────────────────    ← 底边：结构性分隔线 drawSeparator(structural)
   按钮          分隔符       固定项（pinned）                    溢出按钮
```

- **按钮**：quiet 按钮，图标（必有）与可选文字。
- **分隔符**：竖直发丝线。
- **固定项**：下拉框、文本框等任意控件，用 `beginToolbarItem` 包裹；不进入溢出菜单。
- **溢出按钮**：位于末端，`more` 标记；放不下的按钮与分隔符收入其菜单。
- **背景与底边**：背景 `surface_panel`，底边一条结构性分隔线。

## 3. 度量与布局

| 项 | 取值（令牌） |
|---|---|
| 工具栏高度 | `control_h + 2 × gap_xs`（含底边分隔线） |
| 左右内边距 / 上下内边距 | `gap_sm` / `gap_xs` |
| 项之间的间距 | `gap_xs` |
| 按钮尺寸 | 高 `control_h`；仅图标：宽 = `control_h`；带文字：同 button 的公式（quiet，`size = md`） |
| 图标 | `icon_sm` |
| 分隔符 | 宽 `gap_md`，线为发丝线 `border_subtle`，长 `control_h − 2 × gap_xs`，居中 |
| 溢出按钮 | 宽 = 高 = `control_h`，`more` 标记 |
| 背景 | `surface_panel`；底边 `drawSeparator(structural = true)`（`border_strong`） |
| 绘制外延 | 按钮：`focus_ring_w` |

**REQ-W-TOOLBAR-001**　默认尺寸策略：水平方向 `fill`，垂直方向 `fixed(control_h + 2 × gap_xs)`（物理方向，由控件按 `ui.parentAxis()` 映射，见 REQ-W-LABEL-001）。工具栏是 Row 型容器：项按声明顺序自左向右排列，垂直居中。调用方**可以**经通用布局选项覆盖。

**REQ-W-TOOLBAR-002**　**外观**：以 `surface_panel` 填满工具栏矩形；底边画一条 `drawSeparator(a, b, structural = true)`（REQ-THEME-026，`border_strong`，发丝线宽，位于矩形最底部的像素行）。工具栏没有边框、圆角与内凹/凸起效果。

**REQ-W-TOOLBAR-003**　**项的种类与声明位置**：`beginToolbar` … `endToolbar` 之间**只能**直接声明下列四种项，且按声明顺序排列：（一）`toolbarButton`：普通按钮项；（二）`toolbarCommand`：绑定命令的按钮项；（三）`toolbarSeparator`：分隔符；（四）`beginToolbarItem` … `endToolbarItem`：固定项，包裹任意控件；另有 `toolbarSpacer`（伸展空白，`grow(1)`，使其后的项靠右；不进入溢出菜单，不计入宽度判定）。在工具栏内直接声明其他控件（未经 `beginToolbarItem` 包裹）是编程错误，调试构建断言。

**REQ-W-TOOLBAR-004**　**按钮项**：外观与行为是 button 的 `quiet` 变体（`size = .md`，REQ-THEME-031）：常态不画容器，悬停与按下时才按 `drawRaised` 完整绘制；图标 `icon_sm`；`show_text = true` 时在图标之后以 `gap_sm` 间隔显示去除助记符的文字（`font_body`），此时宽度同 button 的公式（REQ-W-BUTTON-002，`quiet` 无 `button_min_w` 之外的特例）；`show_text = false` 时为 `control_h` 见方。按钮项**必须**有图标（`toolbarButton` 的 `icon` 非空；`toolbarCommand` 的命令须带图标），缺失时调试构建断言，发布构建显示文字（`show_text` 视为真）。`checked` 非空时为"锁定态"按钮（button 的 `checked` 语义，应用在 `clicked` 时更新自己的状态）。

**REQ-W-TOOLBAR-005**　**分隔符**：`toolbarSeparator` 在工具栏内是竖直线，宽 `px(gap_md)`、线长 `px(control_h − 2 × gap_xs)`、在节点内居中，颜色 `border_subtle`（`drawSeparator`，非结构性）。紧邻工具栏起点、终点的分隔符，以及相邻的多个分隔符，在显示时**折叠**（只保留一条或不显示），使可见项之间至多一条分隔符；折叠只影响显示，不影响应用的声明。

**REQ-W-TOOLBAR-006**　**固定项**：`beginToolbarItem` 包裹的控件（下拉框、文本框等）按其自身的尺寸策略与行为工作，垂直居中于工具栏；它们**不进入溢出菜单**，且在判定溢出时先于可折叠项占用宽度（REQ-W-TOOLBAR-007）。固定项内声明了 `text_input` 或预占方向键的控件（文本框、可编辑下拉框等）按 REQ-INPUT-038 的补充规则**自动排除出**工具栏的漫游焦点组：它们各自保持自己的 Tab 停靠，照常预占方向键（REQ-INPUT-028），无需工具栏额外处理；不预占方向键的固定项控件（如只读下拉按钮）仍是组成员。按钮项的 `overflow = .pinned` 同样使其成为固定项（但仍属于漫游组）。

**REQ-W-TOOLBAR-007**　**溢出的判定**：设工具栏内部宽度 `W = 工具栏宽度 − 2 × gap_sm`（`px` 换算后）。收集全部项（含固定项）的宽度与间距得总宽 `T`。
- `T ≤ W`：全部显示，没有溢出按钮。
- 否则：末端出现溢出按钮（宽 `control_h`，与前一个可见项间隔 `gap_xs`），**可折叠项**（`overflow = .menu` 的按钮项与分隔符）的可用宽度 `Wc = W − control_h − gap_xs − Σ(固定项宽度及其间距)`；按声明顺序取可折叠项的**最长前缀**，使其总宽（含间距）≤ `Wc`；前缀之后的全部可折叠项（及其间的分隔符）不显示，改由溢出菜单承载。固定项始终显示在其声明的位置，不因溢出而移动或隐藏；固定项自身已超出 `W` 时被裁剪（REQ-LAYOUT-019），溢出按钮仍显示。
- 被隐藏的项**不声明为节点**，但其 `toolbarButton`/`toolbarCommand` 函数仍被调用并返回结果（`in_overflow = true`，`clicked` 来自溢出菜单，REQ-W-TOOLBAR-009）。
- 溢出判定每次构建重算，没有滞回；`T` 恰等于 `W` 时全部显示。

**REQ-W-TOOLBAR-008**　**溢出判定在同一帧内收敛**：工具栏根节点设布局反馈标志，构建时以 `ui.lastRect` 读取其宽度；首次出现（`lastRect` 为 `null`）视为 `W = ∞`，布局后因宽度不同触发同帧第二构建遍并按真实宽度重判（REQ-FRAME-031）。窗口宽度变化使可见项集合变化的那一帧，构建遍数 ≤ 2（REQ-FRAME-032）；宽度变化而可见项集合不变的帧构建遍数 ≤ 1；宽度不变的帧不因溢出判定增加构建遍数。

**REQ-W-TOOLBAR-009**　**溢出按钮与溢出菜单**：溢出按钮外观为 quiet 按钮（`more` 标记），提示"更多"；点击，或持有焦点时按 Enter/Space 打开溢出菜单（`ui.beginPopup`，`kind = .menu`，锚点为该按钮，向下、右对齐，ADR 0008）。菜单按声明顺序列出被隐藏的按钮项：图标、文字（`toolbarButton` 的 `label` 去除助记符标记；`toolbarCommand` 取命令标题）、勾选状态（`checked = true` 显示勾，`false` 或 `null` 不显示）、禁用状态、命令的快捷键文本（右对齐）；被隐藏的分隔符在菜单中为分隔线（首尾与相邻者折叠）。选中一项等于点击该按钮项：在下一帧其函数调用返回 `clicked = true`（`toolbarCommand` 另调用 `ui.invoke(cmd, .toolbar)`），菜单随即关闭。菜单的键盘导航、延迟与关闭规则遵循 menu 控件规范（menu.md）。溢出按钮在漫游组内，是组的**最后一个成员**；组内无被隐藏项时它不声明。

**REQ-W-TOOLBAR-010**　**命令绑定**：`toolbarCommand(cmd)` 的按钮项取自命令（11，REQ-APP-025）：标题取 `commands.titleOf(cmd)`（去除助记符，用于提示框与无障碍名称；`show_text = true` 时显示为按钮文字）；图标取 `app.commands.iconOf(cmd)`（缺失时按 REQ-W-TOOLBAR-004 处理）；启用与勾选经 `ui.commandState(cmd)` 读取本窗口本次构建中最近一次 `ui.command(cmd, state)` 声明的 `CommandState`（未声明取注册时的 `default_state`，REQ-APP-024）：`enabled = false` 时按钮为禁用外观，`checked` 非空时为"锁定态"按钮（点击后由应用的命令处理函数更新其状态，控件不自动翻转）；快捷键文本取 `commands.formatChord(commands.shortcutOf(cmd))`，用于提示框与溢出菜单（REQ-W-TOOLBAR-016、REQ-W-TOOLBAR-009）。点击按钮项（含经溢出菜单选中）调用 `ui.invoke(cmd, .toolbar)`；对禁用的命令忽略并在调试构建记录一条 `warn`（REQ-APP-026）。同一命令在菜单项与工具栏按钮上显示的启用/勾选状态来自同一份声明。

## 4. 变体与参数

工具栏：

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `enabled` | `bool` | `true` | 为假时整条禁用，所有项一并有效禁用（REQ-INPUT-049） |
| `a11y_name` | `?[]const u8` | `null` | 无障碍名称（如"主工具栏"） |
| `key`、`debug_name`、`layout` | 通用 | | 见模板 |

按钮项（`toolbarButton`）：

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `icon` | `?theme.Icon` | `null` | 图标；**必须**非空（REQ-W-TOOLBAR-004） |
| `show_text` | `bool` | `false` | 在图标之后显示文字 |
| `checked` | `?bool` | `null` | 非空时为"锁定态"按钮 |
| `tooltip` | `?[]const u8` | `null` | 提示文本；缺省取 `label`（REQ-W-TOOLBAR-016） |
| `overflow` | `enum { menu, pinned }` | `menu` | `pinned` 则不进入溢出菜单 |
| `enabled` | `bool` | `true` | |
| `key`、`debug_name` | 通用 | | 见模板 |

命令按钮项（`toolbarCommand`）：`show_text`、`overflow`、`key`、`debug_name`，含义同上；`enabled`、`checked`、图标、标题、快捷键文本**不是**选项，全部取自命令（REQ-W-TOOLBAR-010）。固定项（`beginToolbarItem`）：`enabled`、`key`、`debug_name`、`layout`。工具栏没有外观变体。

## 5. 状态

### 5.1 状态机

工具栏本身没有交互状态；按钮项的状态机同 button 的 5.1（`armed ∈ {无, 鼠标, 空格}`），区别只有两点：`quiet` 变体**不因鼠标点击取得焦点**（REQ-W-TOOLBAR-011）；Enter 在持有焦点时按下即触发。溢出菜单项的选中见 REQ-W-TOOLBAR-009。下表补充工具栏层面的转移：

| 当前 | 事件 | 条件 | 下一 | 动作 |
|---|---|---|---|---|
| 无溢出 | 工具栏宽度减小到 `T > W` | — | 有溢出 | 末端出现溢出按钮；尾部可折叠项收入菜单（REQ-W-TOOLBAR-007） |
| 有溢出 | 宽度增大到 `T ≤ W` | — | 无溢出 | 溢出按钮消失，菜单（若打开）关闭 |
| 溢出菜单关闭 | 点击溢出按钮 / 焦点在其上按 Enter、Space | 存在隐藏项 | 菜单打开 | 打开弹出层 |
| 溢出菜单打开 | 选中菜单项 / Esc / 点击菜单外 / 宿主失活 | — | 关闭 | 选中则触发对应按钮项的 `clicked`（REQ-W-TOOLBAR-009） |
| 任意 | 应用把 `enabled` 置假 | — | 禁用 | 项一并禁用；焦点在组内时按 REQ-INPUT-042 转移；打开的菜单关闭 |

### 5.2 视觉表现

"显示为按下"含义同 button（`armed = 鼠标` 且指针在命中范围内，或 `armed = 空格`，或 `checked = true`）。

| 状态 | 绘制（基元 + 令牌） |
|---|---|
| 工具栏 | 背景 `surface_panel`；底边 `drawSeparator(structural = true)` |
| 按钮项·常态 | `quiet`：不画容器；图标（及文字）`text_primary` |
| 按钮项·悬停 | `drawRaised(neutral, radius_control)` 悬停变体（`quiet` 此时才画出容器，REQ-THEME-031） |
| 按钮项·显示为按下 | 按下变体；内容下移 1 ppx（REQ-THEME-030） |
| 按钮项·`checked = true` 且未被按住 | 同"显示为按下"，但内容不下移 |
| 按钮项·焦点可见 | 加 `drawFocusRing(按钮矩形, radius_control)` |
| 按钮项·禁用 | 不画容器；图标与文字 `text_disabled` |
| 分隔符 | `drawSeparator`，`border_subtle` |
| 溢出按钮 | 同按钮项（`more` 标记，`text_primary`） |

## 6. 鼠标行为

**REQ-W-TOOLBAR-011**　**点击工具栏按钮不夺走焦点**：按钮项（含命令按钮项与溢出按钮）按 REQ-W-BUTTON-011 的规则，鼠标点击**不**使其获得焦点（`take_focus_on_click = false`），焦点留在原处（如正在编辑的文本框）；但悬停、按下、释放时的 `clicked` 判定与 button 相同：左键按下进入 `armed = 鼠标` 并立即显示为按下（`dur_instant`），按下期间移出命中范围则恢复、移回再次显示为按下（捕获语义），`clicked` 仅在释放时指针位于命中范围内时于释放帧报告，快速连续点击每次都报告。命中范围是按钮的布局矩形（不含焦点环外延）。

**REQ-W-TOOLBAR-012**　右键、中键的按下与释放不改变按钮状态、不报告 `clicked`；工具栏与按钮项没有上下文菜单；滚轮不处理，按 REQ-INPUT-019 冒泡；指针形状恒为箭头（REQ-THEME-032）。工具栏的空白处（按钮之间、末端空白）不可交互，不吞鼠标事件（沿祖先冒泡）。

## 7. 键盘行为

| 键 | 行为 |
|---|---|
| ← / → | 焦点在工具栏内移动到前一个/后一个启用成员（跳过禁用与隐藏项）；**不**回绕 |
| Home / End | 焦点移到第一个/最后一个启用成员 |
| Space | 焦点所在按钮项：按下进入 `armed = 空格`；释放时报告 `clicked` |
| Enter | 焦点所在按钮项：按下即报告 `clicked`（自动重复忽略） |
| Esc | `armed = 空格` 时取消，且该 Esc 不再向后传递；否则不处理 |
| Alt+字母 | 工具栏按钮**不**登记助记符（助记符属于菜单与对话框，REQ-W-TOOLBAR-014） |
| Tab / Shift+Tab | 工具栏作为**一个**停靠点（REQ-W-TOOLBAR-013）；Tab 离开整条工具栏 |

**REQ-W-TOOLBAR-013**　**漫游焦点组**：整条工具栏声明为一个漫游焦点组：`ui.focusGroup(工具栏 ID, .{ .orientation = .horizontal, .wrap = false, .home_end = true })`（REQ-INPUT-038）；`current` 取默认（组内最近一次获得焦点的成员，再无则第一个启用成员）。成员 = 工具栏内的可聚焦按钮项与溢出按钮（固定项除外，REQ-W-TOOLBAR-006）。整组在 Tab 序中只有一个停靠点；方向键与 Home/End 在成员间移动焦点（原因 `group`），**只移动焦点、不激活**。按钮项不声明处理方向键，落到组导航（REQ-INPUT-030）。焦点移到成员上时，若工具栏位于 Scroll 内则按 REQ-INPUT-044 使其可见。工具栏中所有按钮项均为 quiet 变体，因而**依赖**这个漫游组获得键盘可达性（REQ-W-BUTTON-018）。

**REQ-W-TOOLBAR-014**　按钮项经 `InteractOpts.handles` 声明处理 Space、Enter 与 Esc（⑤ 级，不预占），命令快捷键优先；Space 的自动重复按下被忽略，`armed = 空格` 期间焦点离开或按钮变为禁用时取消，不报告 `clicked`（同 REQ-W-BUTTON-013、REQ-W-BUTTON-014）。持有焦点的工具栏按钮在其焦点范围内临时成为 Enter 的目标，优先于范围指定的默认按钮（REQ-W-BUTTON-016）。工具栏按钮的文字中的 `&` 按 REQ-INPUT-046 只用于去除标记显示，不登记助记符。

## 8. 焦点

**REQ-W-TOOLBAR-015**　工具栏本身不可聚焦；它的成员可聚焦。焦点环仅在焦点可见时绘制于持有焦点的成员（REQ-INPUT-040、REQ-THEME-023）；获得、失去焦点不产生激活类结果。焦点离开工具栏后再回来（Tab 或 Shift+Tab）落在最近一次持有焦点的成员上。禁用的成员、被隐藏（溢出）的项不是停靠点，也不是方向键的目标。

## 9. 文本与输入法

按钮项的文字（`show_text = true` 时）为单行，不接受文本输入；固定项内的文本输入控件按其自身规范处理输入法，与工具栏无关。

**REQ-W-TOOLBAR-016**　**每个图标按钮必须有提示**（REQ-THEME-006）：`toolbarButton` 的 `label` **必须**非空，提示文本取 `tooltip`，缺省取 `label` 去除助记符标记后的文字；悬停达到系统悬停时间（读取系统度量 `hover_time_ms`，REQ-INPUT-057）时显示提示框。仅图标的按钮同时以该文字为无障碍名称。`toolbarCommand` 的提示文本为"命令标题（去助记符）+ 空格 + 括号内的快捷键文本"，命令无快捷键时只有标题（REQ-APP-025）。按钮项带文字（`show_text = true`）且文字未被截断时提示框**仍**显示（工具栏的提示不受截断限制）。`label` 为空（`toolbarButton`）时调试构建断言。

## 10. 动效

工具栏没有自有动效；按钮项使用框架内建的悬停/按下/焦点过渡：

| 属性 | 触发 | 时长令牌 | 缓动 | 影响级别 |
|---|---|---|---|---|
| 容器填充与边框（`quiet` 常态 ↔ 悬停） | 悬停变化 | `dur_fast` | `ease_out` | paint（框架内建，`Visual.hover_t`） |
| 容器（→ 按下） | 显示为按下 | `dur_instant` | — | paint（`Visual.press_t`） |
| 容器（按下 →） | 结束按下 | `dur_fast` | `ease_out` | paint |
| 焦点环 | 焦点变为可见 | `dur_fast` 淡入，消失瞬时 | `ease_out` | paint（`Visual.focus_t`） |

溢出菜单的出现遵循系统菜单动画设置（REQ-THEME-020、ADR 0008），消失瞬时。溢出按钮的出现与消失、可见项集合的变化都是**瞬时**的（不动画，REQ-THEME-020：不改变布局尺寸的过渡）。

## 11. 无障碍

| 项 | 值 |
|---|---|
| UIA 控件类型 | 工具栏：ToolBar；按钮项：Button；分隔符：Separator；溢出按钮：Button；固定项内的控件按其自身类型 |
| 名称来源 | 工具栏：`a11y_name`；按钮项：`label`（`toolbarCommand` 取命令标题，去除助记符）；溢出按钮："更多" |
| 支持的模式 | 按钮项：Invoke（`checked` 非空时改为 Toggle）；溢出按钮：Invoke 与 ExpandCollapse |
| 状态属性 | IsEnabled、HasKeyboardFocus、ToggleState（`checked` 非空时）、AcceleratorKey（命令的快捷键文本）；被溢出隐藏的项 `IsOffscreen` 为真 |

**REQ-W-TOOLBAR-017**　经 UIA Invoke/Toggle 触发的按钮项**必须**与键盘 Enter 激活等效：在下一帧报告一次 `clicked`（命令按钮项另经 `ui.invoke(cmd, .toolbar)`）。被溢出隐藏的项**必须**仍作为工具栏的子元素暴露（`IsOffscreen = 真`），其 Invoke 同样有效。工具栏本身对辅助技术只暴露为 ToolBar 容器，不可聚焦。

## 12. API 草案

```zig
// 草案：仅签名
pub const ToolbarOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    a11y_name: ?[]const u8 = null,     // 借用至本帧结束；框架复制
    layout: layout.ItemOptions = .{},  // 各控件共用（07）
};

pub const ToolbarOverflow = enum { menu, pinned };

pub const ToolbarButtonOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    icon: ?theme.Icon = null,          // 必须非空（REQ-W-TOOLBAR-004）
    show_text: bool = false,
    checked: ?bool = null,             // 非空为"锁定态"；点击不自动翻转，由应用更新
    tooltip: ?[]const u8 = null,       // 借用至本帧结束；框架在需要显示时复制；缺省取 label
    overflow: ToolbarOverflow = .menu,
};

pub const ToolbarCommandOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    show_text: bool = false,
    overflow: ToolbarOverflow = .menu,
};

pub const ToolbarItemOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    layout: layout.ItemOptions = .{},
};

pub const ToolbarSeparatorOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
};

pub const ToolbarButtonResult = struct {
    // 持续性状态
    hovered: bool,
    pressed: bool,                     // 即"显示为按下"（不含 checked 造成的外观）
    focused: bool,
    in_overflow: bool,                 // 当前被收进溢出菜单（此时 hovered/pressed/focused 恒为假）
    // 激活类结果（触发同帧第二构建遍，REQ-FRAME-030）
    clicked: bool,                     // 含经溢出菜单选中产生的点击
    activated: ?input.ActivateSource,  // clicked 由助记符/默认按钮机制触发时非空（工具栏按钮恒为 null）
};

/// 容器类控件：beginToolbar / endToolbar 成对出现（REQ-CONV-009、REQ-FRAME-028）。
/// 其间只能声明工具栏项（REQ-W-TOOLBAR-003）。
pub fn beginToolbar(ui: *Ui, src: std.builtin.SourceLocation, opts: ToolbarOptions) ui.WidgetId;
pub fn endToolbar(ui: *Ui) void;

/// label 借用至本帧结束；必须非空，用作提示与无障碍名称；含 `&` 时仅去除标记。
pub fn toolbarButton(ui: *Ui, src: std.builtin.SourceLocation, label: []const u8, opts: ToolbarButtonOptions) ToolbarButtonResult;

/// 绑定命令：标题、图标、启用/勾选、快捷键提示均取自命令（11）；点击时调用 ui.invoke(cmd, .toolbar)。
pub fn toolbarCommand(ui: *Ui, src: std.builtin.SourceLocation, cmd: input.CommandId, opts: ToolbarCommandOptions) ToolbarButtonResult;

pub fn toolbarSeparator(ui: *Ui, src: std.builtin.SourceLocation, opts: ToolbarSeparatorOptions) void;
pub fn toolbarSpacer(ui: *Ui, src: std.builtin.SourceLocation) void;      // grow(1) 空白；不进溢出菜单

/// 固定项：包裹任意控件，不进入溢出菜单，不属于漫游焦点组。
pub fn beginToolbarItem(ui: *Ui, src: std.builtin.SourceLocation, opts: ToolbarItemOptions) ui.WidgetId;
pub fn endToolbarItem(ui: *Ui) void;
```

`clicked` 是激活类结果，为真时触发同帧第二构建遍，在第二遍中为假（REQ-FRAME-033）；`hovered`、`pressed`、`focused`、`in_overflow` 是持续性状态。`checked` 的值与命令状态归应用所有，控件不保留。传入的 `label`、`tooltip` 借用至本帧结束；框架在需要显示提示框时复制。工具栏不持有任何应用值。

## 13. 保留状态

| 字段 | 类型 | 保留级别 | 说明 |
|---|---|---|---|
| `armed_space`（每个按钮项） | `bool` | transient | Space 已按下待释放 |
| `menu_open` | `bool` | transient | 溢出菜单是否打开（打开的弹出层由应用状态驱动：收到 `popup_dismissed` 后下一次构建停止声明，REQ-INPUT-058） |
| 漫游组"最近一次获得焦点的成员" | — | 框架内建（REQ-INPUT-038） | 无需控件槽 |

悬停/按下/焦点过渡为框架内建状态（REQ-FRAME-013）。工具栏宽度由布局反馈经 `lastRect` 读取，不保存。

## 14. 失效规则

**REQ-W-TOOLBAR-018**　绘制键**必须**由以下各项构成。工具栏：可见项集合（决定溢出按钮有无与各项位置）、`enabled`。按钮项：图标、`show_text` 与文字内容、`checked`、`enabled`（含命令状态与继承自工具栏的有效禁用）、是否被收入溢出菜单。分隔符：是否被折叠。布局输入的内容度量键由各项的图标/文字、`show_text` 构成；工具栏根节点设布局反馈标志（REQ-W-TOOLBAR-008）。

| 变化 | 置脏级别 | 损伤范围 |
|---|---|---|
| 按钮项悬停进入/离开、显示为按下的变化、焦点环显隐 | `paint` | 该按钮绘制范围（含外延） |
| 鼠标按下、释放、Space/Enter（进入收件列表） | `build` | 由差分决定；若无外观变化则为空 |
| 命令状态（`enabled`/`checked`）变化 | `build`（由应用的模型通知引起） | 相应按钮项矩形 |
| 窗口宽度变化使可见项集合变化 | `layout`，布局反馈触发第二构建遍（REQ-W-TOOLBAR-008） | 工具栏矩形 |
| 窗口宽度变化而可见项集合不变 | `layout` | 由差分决定（仅位置变化的项） |
| `enabled` 变化 | `build` | 工具栏矩形 |

**REQ-W-TOOLBAR-019**　仅悬停进入/离开一个工具栏按钮所产生的帧**必须**是纯绘制帧（构建遍数 0），且损伤不超出该按钮的绘制范围；工具栏的空白处与分隔符上的指针移动不产生任何帧。点击一个按钮（不改变任何应用状态）所产生的帧，损伤 ⊆ 该按钮的绘制范围。

## 15. 边界与错误情况

| 情况 | 规定 |
|---|---|
| 工具栏内没有任何项 | 仍占高度；无溢出按钮；组内无成员，不产生 Tab 停靠 |
| 全部可折叠项都放不下（`Wc` < 第一项宽度） | 全部可折叠项进入溢出菜单，只显示固定项与溢出按钮 |
| 溢出菜单打开期间窗口缩放使隐藏项集合变化 | 菜单内容随之更新；打开状态保持；若隐藏项变为 0，菜单关闭 |
| 溢出菜单打开期间对应项被应用移除或禁用 | 菜单项按下一次构建的状态显示（禁用则不可选）；移除则不再出现 |
| 命令按钮项的命令被禁用时被点击 | 忽略，不调用处理函数，调试构建记录一条 `warn`（REQ-APP-026）；`clicked` 为假 |
| 按下期间按钮从树中消失（如被溢出收走） | 捕获释放（REQ-INPUT-024），不报告 `clicked` |
| 按下期间按钮变为禁用 | 取消，不报告 `clicked`；立即显示禁用外观 |
| 焦点在被溢出收走的按钮上 | 视同失格，按 REQ-INPUT-042 转移（通常落到溢出按钮或相邻成员） |
| 同一帧内同时满足鼠标释放与 Enter | 只报告一次 `clicked` |
| `toolbarButton` 的 `icon` 缺失 / `label` 为空 | 见 REQ-W-TOOLBAR-004、REQ-W-TOOLBAR-016 |
| 工具栏直接声明了非工具栏项 | 调试构建断言（REQ-W-TOOLBAR-003） |
| 窗口非活动时悬停 | 仍显示悬停外观；点击先激活窗口，该次点击照常作用于按钮 |

## 16. 验收标准

**AC-W-TOOLBAR-001**　`[金图]` 覆盖：REQ-W-TOOLBAR-001、REQ-W-TOOLBAR-002、REQ-W-TOOLBAR-004、REQ-W-TOOLBAR-005、REQ-W-TOOLBAR-006。渲染一条宽 600 lpx 的工具栏：3 个仅图标按钮、分隔符、带文字的按钮、分隔符、固定的下拉框与文本框、伸展空白、1 个 `checked = true` 的按钮；另渲染两个连续分隔符与首位分隔符的折叠；缩放 1.0/1.25/1.5/2.0，浅/深/高对比度。预期：与基准图一致；几何断言——工具栏高 = `control_h + 2 × gap_xs`；背景 `surface_panel`；底边为 `border_strong` 的一条发丝线且位于最底部像素行；左右内边距 `gap_sm`、项间距 `gap_xs`；仅图标按钮宽 = 高 = `control_h`；带文字按钮宽按 button 的公式；分隔符宽 = `gap_md`、线色 `border_subtle`、线长 = `control_h − 2 × gap_xs` 且居中；折叠后相邻可见项之间至多一条分隔符；固定项垂直居中；无边框无圆角的工具栏轮廓。

**AC-W-TOOLBAR-002**　`[金图]` 覆盖：REQ-W-TOOLBAR-004、REQ-W-TOOLBAR-015。状态矩阵：按钮项 {常态, 悬停, 显示为按下, `checked = true`, 焦点可见, 禁用} 与溢出按钮 {常态, 悬停}，浅/深/高对比度。预期：与基准图一致；常态与禁用态**无**容器像素（仅图标）；悬停与按下才出现 `drawRaised` 容器；显示为按下时内容相对常态下移恰 1 ppx，而 `checked = true` 未按住时不下移；焦点环仅出现在"焦点可见"列；禁用图标颜色为 `text_disabled`。

**AC-W-TOOLBAR-003**　`[回放]` 覆盖：REQ-W-TOOLBAR-011、REQ-W-TOOLBAR-012。界面含文本框 T（持有焦点）与工具栏按钮 B、C。脚本：在 B 上按下左键 → B `pressed` 真、`clicked` 假、**焦点仍在 T**；移出命中范围 → `pressed` 假且 C 的 `hovered` 假；移回 → 真；释放 → 该帧 B `clicked` 真，下一帧假，焦点仍在 T。在 B 外释放 → 全程 `clicked` 假。以 50 ms 间隔完成 3 次按下–释放 → `clicked` 累计 3。右键、中键各一次 → 无任何结果；工具栏位于可滚动容器内时在其上滚动滚轮 → 容器偏移变化；工具栏空白处单击被外层面板接收。指针停在按钮上记录的指针形状为箭头。点击后金图无焦点环。

**AC-W-TOOLBAR-004**　`[回放]` 覆盖：REQ-W-TOOLBAR-013、REQ-W-TOOLBAR-014、REQ-W-TOOLBAR-015、REQ-W-TOOLBAR-006。界面：文本框 T1、工具栏（按钮 A、B（禁用）、C，固定的文本框 T2，按钮 D）、按钮 Z。连续按 Tab：序列为 T1 → 工具栏（一次停靠，落在首个启用成员 A）→ T2（固定项自身的停靠）→ Z；Shift+Tab 反向。焦点在 A：按 → → 跳过禁用的 B 到 C（只移动、`clicked` 假）；按 → → D（不回绕，再按 → 仍在 D）；← 回到 C；Home → A，End → D。焦点在 T2 内按 ←、→ → 由文本框编辑，焦点不离开 T2。焦点在 C：`key down Space` → `pressed` 真、`clicked` 假；`key repeat VK_SPACE 5` → 无变化；`key up Space` → `clicked` 真恰一次；`key down Space` 后 Tab → 取消；`key down Space` 后 Esc → 取消且所在对话框取消按钮未被触发。Enter：按下 → `clicked` 真，`key repeat VK_RETURN 10` → 累计恰 1；对话框含默认按钮时焦点在 C 按 Enter → C 触发而非默认按钮。离开工具栏再 Shift+Tab 回来 → 落在最近持有焦点的 C。按钮文字 "保存(&S)"：Alt+S → 无任何反应（未登记助记符）。

**AC-W-TOOLBAR-005**　`[回放]` 覆盖：REQ-W-TOOLBAR-007、REQ-W-TOOLBAR-008、REQ-W-TOOLBAR-009、REQ-W-TOOLBAR-006。工具栏含：按钮 1–8（各 `control_h` 宽，`overflow = .menu`）、其中第 4、5 之间有分隔符、末尾有固定项 P（宽 100 lpx）。宽度逐步缩小：全部放得下 → 无溢出按钮；缩小使总宽超过 `W` → 出现溢出按钮，可见的是最长前缀，P 始终显示且位置不变；前缀末尾的分隔符不显示；节点检视中被隐藏的项无节点；`in_overflow` 为真。点击溢出按钮 → 弹出菜单列出被隐藏的按钮（图标、去助记符的文字、勾选、禁用、命令快捷键文本右对齐），其中被隐藏的分隔符为分隔线；选中第 2 项 → 对应按钮的函数调用在下一帧返回 `clicked` 真恰一次，菜单关闭；点击菜单外 → 关闭无结果。首帧：构建遍数 = 2；随后窗口宽度逐 1 ppx 改变使可见集合变化的帧 → 构建遍数 ≤ 2；宽度改变但可见集合不变的帧 → 构建遍数 ≤ 1（纯布局帧时为 0）。放大窗口到全部可见 → 溢出按钮消失，菜单关闭。焦点在被收走的按钮上时缩小窗口 → 焦点按 REQ-INPUT-042 转移。

**AC-W-TOOLBAR-006**　`[回放]` 覆盖：REQ-W-TOOLBAR-003、REQ-W-TOOLBAR-004、REQ-W-TOOLBAR-005。结构规则：在工具栏内直接声明一个普通 button → 调试构建断言中止；经 `beginToolbarItem` 包裹后合法。`toolbarButton` 的 `icon` 为空 → 调试构建断言，发布构建改为显示文字。`toolbarSpacer` 使其后的项靠右，溢出判定不计其宽度；`toolbarSeparator` 的显示折叠规则（首、尾、相邻）逐一断言；`checked` 非空的按钮点击后值不自动翻转（应用在 `clicked` 时更新后下一帧外观才变）。

**AC-W-TOOLBAR-007**　`[回放]` 覆盖：REQ-W-TOOLBAR-010、REQ-W-TOOLBAR-011、REQ-W-TOOLBAR-014。命令 `file.save`（标题 "保存(&S)"，图标取 `info` 标记，快捷键 `Ctrl+S`），窗口构建函数声明 `ui.command(cmd, .{ .enabled = model.dirty })`；命令 `view.grid`（`checked = true`）。工具栏含这两个命令按钮：`dirty` 为假时 `file.save` 按钮为禁用外观、点击无反应、处理函数未被调用且调试构建 1 条 `warn`；置真后下一次构建启用，点击 → 处理函数被调用，`source = .toolbar`，且在同帧可见其效果（REQ-APP-026）；`view.grid` 按钮显示为"锁定态"；Ctrl+S 快捷键与按钮点击触发同一处理函数；菜单与工具栏对同一命令显示的启用/勾选状态一致。按钮不重复登记助记符。

**AC-W-TOOLBAR-008**　`[回放]` 覆盖：REQ-W-TOOLBAR-016。仅图标按钮悬停并推进假时钟超过系统悬停时间 → 提示框文本为 `tooltip`，缺省时为 `label`（去除 `&`）；`toolbarCommand`：提示为 "保存 (Ctrl+S)"（标题去助记符 + 空格 + 括号内快捷键文本），无快捷键的命令只有标题；带文字且未截断的按钮也显示提示框；窗口失活后提示消失。`label` 为空的 `toolbarButton` → 调试构建断言中止。

**AC-W-TOOLBAR-009**　`[单元]` 覆盖：REQ-W-TOOLBAR-017、REQ-W-TOOLBAR-007。经假 UIA 入口：工具栏类型 ToolBar；普通按钮类型 Button、模式含 Invoke；`checked` 非空的按钮模式含 Toggle 且 ToggleState 与 `checked` 一致；Name 为去除助记符的 `label`/命令标题；AcceleratorKey 为命令快捷键文本；分隔符类型 Separator；溢出按钮 Name 为"更多"，模式含 Invoke 与 ExpandCollapse；被溢出收走的按钮仍为工具栏的子元素、`IsOffscreen` 真，对其 Invoke → 下一帧 `clicked` 真恰一次。溢出判定的纯逻辑：给定各项宽度、`W`，断言可见前缀与菜单项集合（含 `T = W` 时全部显示、固定项占宽先于可折叠项、固定项自身超宽时仍有溢出按钮、`Wc` 小于首项宽度时可折叠项全进菜单）。

**AC-W-TOOLBAR-010**　`[计量]` 覆盖：REQ-W-TOOLBAR-018、REQ-W-TOOLBAR-019、REQ-W-TOOLBAR-008。界面含一条有 40 个按钮的工具栏（部分溢出）。回放：指针从空白处移入按钮 X 再移出 → 各帧构建遍数均为 0；被绘制的节点集合 ⊆ {X 及其与损伤相交的祖先}；损伤面积 ≤ X 的绘制范围面积。指针在工具栏空白处与分隔符上移动 → `frame.count` 增量为 0。点击 X（不改变应用状态）→ 损伤 ⊆ X 的绘制范围。仅改变 X 的 `checked` 并 `invalidate(.build)` → 损伤恰为 X 的矩形；以相同参数再次 `invalidate(.build)` → 损伤为空、`frame.presents` 不变。宽度不变的帧 `frame.build_passes` 增量不因溢出判定而增加。

## 17. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-W-TOOLBAR-01 | 竖直工具栏、多行工具栏、可浮动/拖动重排工具栏 | 本版不做；ADR 0007 不做 wrap |
| OPEN-W-TOOLBAR-02 | 溢出判定的"最长前缀"可能使较窄的后项让位给较宽的前项；是否改为尽量多显示项（跳过放不下的宽项继续放入窄项） | 先用前缀规则（顺序可预测）；评审时再定 |
| OPEN-W-TOOLBAR-03 | 溢出菜单依赖 menu.md 的弹出菜单项外观与键盘行为 | 以 menu.md 为准；本文仅规定其内容与激活语义 |
| OPEN-W-TOOLBAR-04 | 是否在 Esc 时把焦点还给进入工具栏前的控件 | 不处理（保持与 button 一致，Esc 不处理） |
| OPEN-W-TOOLBAR-05 | 工具栏按钮是否登记助记符 | 不登记；助记符属于菜单与对话框内的控件，避免与菜单栏的 Alt 助记符冲突 |
