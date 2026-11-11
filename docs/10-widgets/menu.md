# 菜单（menu）

> 本文覆盖菜单栏、下拉菜单、子菜单与上下文菜单。弹出层通用规则（弹出栈、轻关闭、锚点例外、`PopupSpec`、关闭原因映射、悬停延迟 `hoverFor`）引用 08；定位与翻转引用 07 的 Anchor（`layout.placeAnchored`）；命令系统引用 11；弹出窗口的创建与系统阴影引用 03 与 ADR 0008。

## 1. 用途

呈现应用的命令集合：窗口顶部的**菜单栏**、由菜单栏项或子菜单项展开的**下拉菜单**与**子菜单**、在某个对象上按右键或 Shift+F10 弹出的**上下文菜单**。参照 Windows 的 `HMENU` 菜单（`TrackPopupMenu`、菜单栏）。

- 从候选项中选择一个**值**（不是动作）→ 用 combo-box。
- 一个按钮旁的少量动作 → 可用按钮加上下文菜单；不提供分裂按钮（见 button.md 的待定问题）。
- 工具栏上的常用动作 → 用 `quiet` 按钮，二者共享同一批命令（REQ-APP-025）。

API 为即时风格：`beginMenuBar`/`endMenuBar`、`beginMenu`/`endMenu`、`menuItem`、`menuSeparator`、`beginContextMenu`/`endContextMenu`。菜单项可绑定命令（11 的 `CommandId`）：标题、图标、快捷键文本、启用与勾选状态由命令提供，触发时调用命令。

## 2. 解剖

```
┌──────────────────────────────────────────────┐
│ 文件(F)  编辑(E)  视图(V)                      │   菜单栏（Row，surface_panel）
├──────────────────────────────────────────────┤   ← 结构性分隔线（border_strong）
        ┌───────────────────────────────┐
        │ ✓ [图标] 标题        Ctrl+N    │       下拉菜单（drawPopupFrame）
        │   [图标] 标题（禁用） Ctrl+S    │       行高 row_h
        │ ─────────────────────────────  │       分隔线
        │   标题                      ▸  │ ───┐  子菜单箭头
        └───────────────────────────────┘    │
                    ┌────────────────────────┘
                    │ 子菜单项 …  │
                    └─────────────┘
```

- **菜单栏**：一行**顶层菜单项**（`beginMenu` 在 `beginMenuBar` 内声明）。
- **顶层菜单项**：标题（含助记符），展开其下拉菜单。
- **下拉菜单**：弹出层（`PopupKind.menu`），内含若干**菜单项**与**分隔线**。
- **菜单项**行：自左至右为 标记列（勾选/单选）、图标列、标题、（弹性间隔）、快捷键文本、子菜单箭头列。
- **子菜单**：由带 `beginMenu` 的菜单项展开的、位于其右侧的下一级弹出层。
- **上下文菜单**：弹出层（`PopupKind.context_menu`），内部同下拉菜单。
- **滚动提示条**：菜单高于可用空间时位于弹出层上、下端的 `row_h` 高度条。

## 3. 度量与布局

| 项 | 取值（令牌） |
|---|---|
| 菜单栏高度 | `control_h` |
| 菜单栏背景 / 底边 | `surface_panel` / `drawSeparator(structural = true)` |
| 顶层项左右内边距 | `pad_item_x` |
| 顶层项文字 | `font_body`，`text_primary`（禁用 `text_disabled`） |
| 菜单项行高 | `row_h` |
| 弹出层上下内边距 | `pad_popup_y` |
| 菜单项左右内边距 | `pad_item_x` |
| 标记列 | 宽 `check_size`，其后间距 `gap_sm`；仅当本菜单有任一项带勾选/单选时存在 |
| 图标列 | 宽 `icon_sm`，其后间距 `gap_sm`；仅当本菜单有任一项带图标时存在 |
| 标题与快捷键文本最小间距 | `gap_lg` |
| 快捷键文本 | `font_body`，`text_secondary`（禁用 `text_disabled`），右对齐 |
| 子菜单箭头列 | 间距 `gap_sm` + 宽 `icon_sm`；仅当本菜单有任一子菜单项时存在；字形 `drawMark(chevron_right)` |
| 分隔线行高 | `gap_md`，线居中，左右各内缩 `pad_item_x` |
| 滚动提示条 | 高 `row_h`，字形 `chevron_up`/`chevron_down` |
| 弹出层最大宽度 | `menu_max_w` |
| 弹出层底 | `drawPopupFrame(R, false)` |
| 绘制外延 | 菜单栏顶层项的焦点环 `focus_ring_w` |

**REQ-W-MENU-001**　菜单栏是一个 Row 容器：默认主轴 `fill`（占满父容器宽）、交叉轴 `fixed(control_h)`；背景 `surface_panel`，底边一条结构性分隔线（REQ-THEME-026）。顶层项自左向右顺序排列，间距 0。每个顶层项宽 = `2 × pad_item_x + 去除助记符标记后的标题宽`，高 = 菜单栏高。菜单栏是**漫游组**（`ui.focusGroup`，水平方向，`wrap`、`home_end` 为真，REQ-INPUT-038），但**不是 Tab 停靠**：菜单栏声明 `GroupSpec.tab_stop = false`（整组无 Tab 停靠，REQ-INPUT-038），Tab 序列不经过菜单栏。可见性仅有两种表达（REQ-LAYOUT-005）：不声明或 `layout.hidden`；`enabled = false` 时整条菜单栏禁用。

**REQ-W-MENU-002**　每个展开的菜单经 `ui.beginPopup` 声明弹出层：
- 顶层下拉菜单：`PopupSpec{ kind = .menu, anchor = 其顶层项的矩形, anchor_id = 其顶层项 ID, placement = { below, start }, gap = none, match_anchor_width = true, light_dismiss = true, close_on_escape = true, keyboard = .grab, max_height = 锚点上、下两侧可用空间中的较大者 }`；
- 子菜单：`PopupSpec{ kind = .menu, anchor = 父菜单项矩形, anchor_id = none, placement = { right, start }, gap = none, parent_popup = 父弹出层, max_height = null, …其余同上 }`；
- 上下文菜单：`PopupSpec{ kind = .context_menu, anchor = ContextRequest.anchor, anchor_id = none, placement = { below, start, flip_cross = true }, gap = none, max_height = 上、下两侧较大者, …其余同上 }`。
越界翻转由 `placeAnchored` 完成：顶层与上下文菜单下方放不下时翻到锚点上方；子菜单右侧放不下时翻到父菜单左侧；交叉方向超出时：上下文菜单（`flip_cross = true`）先改用相反对齐（`start` ↔ `end`，即菜单右缘对齐锚矩形右缘，出现在指针左侧）、仍越界才平移夹紧；其他菜单直接平移夹紧到工作区内（REQ-LAYOUT-043）。子菜单的顶边与其父菜单项的顶边对齐。弹出窗口由平台层创建为不激活的独立窗口，宿主保持激活（REQ-INPUT-055）。

**REQ-W-MENU-003**　**菜单项行**的横向布局自左至右：左内边距 `pad_item_x` → 标记列（若存在）→ 图标列（若存在）→ 标题 → 弹性空白 → 快捷键文本 → 子菜单箭头列（若存在）→ 右内边距 `pad_item_x`；行内文字按"行框垂直居中"放置（REQ-THEME-017）。仅当本菜单某项需要某一列时该列才对**全体**项保留（使各项标题左对齐）。勾选项 `checked = true` 在标记列绘制 `drawMark(check)`，单选项（`radio`）选中时绘制 `drawMark(radio_dot)`，均为 `text_primary`（禁用 `text_disabled`），未选中不绘制。图标项在图标列绘制其 `icon`（`icon_sm`，`text_primary`，禁用 `text_disabled`）。

**REQ-W-MENU-004**　**列式宽度**：弹出层内各列的宽度为——标记/图标列（存在时，见 REQ-W-MENU-003）；**标题列宽** = 本菜单全体菜单项（含子菜单项）去除助记符标记后的标题宽度的最大值；**快捷键列宽** = 全体菜单项快捷键文本宽度的最大值（没有任何项带快捷键文本的菜单为 0，且此时**不留** `gap_lg`）；**箭头列** = `gap_sm + icon_sm`（仅当本菜单有子菜单项）。**行宽** = 左内边距 `pad_item_x` + 标记列 + 图标列 + 标题列 +（快捷键列非 0 时）`gap_lg` + 快捷键列 + 箭头列 + 右内边距 `pad_item_x`，上限为 `menu_max_w` 与工作区宽度；顶层菜单另取不小于锚点（顶层项）宽度。内容超出上限时标题以尾部省略号截断（REQ-THEME-018），快捷键文本不截断。所有行等宽，不随项数变化。例：File 菜单（标题最宽 "Recent" 36、快捷键最宽 "Ctrl+N" 36、有子菜单项）= 8 + 36 + 12 + 36 + (4 + 16) + 8 = 120；Edit 菜单（无快捷键、无子菜单，标题最宽 "Another" 42）= 8 + 42 + 8 = 58（无 `gap_lg`）。

**REQ-W-MENU-005**　`menuSeparator` 声明一条分隔线：行高 `gap_md`，以 `drawSeparator`（`border_subtle`）画水平发丝线，垂直居中，两端内缩 `pad_item_x`。分隔线不可高亮、不可聚焦、被上下键与 Home/End 跳过、不参与助记符。连续的分隔线、首尾的分隔线按声明原样绘制（框架不合并也不隐藏）。

**REQ-W-MENU-006**　**过高的菜单**：内容高度（行高之和加 `2 × pad_popup_y`）超过弹出层可用高度（`max_height` 与工作区限制后的高度，`height_limited`，REQ-LAYOUT-043）时，弹出层内容为无滚动条的纵向 Scroll（`bar_v = never`），并在弹出层上、下端各保留一条 `row_h` 高的**滚动提示条**：可视行区间 = 弹出层高 − `2 × pad_popup_y` − `2 × row_h`。向上（下）还有内容时对应提示条绘制 `chevron_up`（`chevron_down`），否则为空；指针悬停在有内容可滚的提示条上时，每隔 `dur_autoscroll`（50 ms，`build` 级定时器）向该方向滚动一个 `row_h`，指针离开或到达边界时停止；滚轮（`wheel_lines`，`page` 为一页）在弹出层上滚动；键盘高亮移动时按最小位移使高亮行进入可视行区间。滚动不改变高亮项。

**REQ-W-MENU-007**　菜单项行的视觉状态：常态——无底，文字 `text_primary`；**高亮**（鼠标悬停或键盘移动到的行，任一时刻每个菜单只有一行高亮）——行底 `surface_row_hover`（占满行宽，直角），文字不变；**禁用**——文字、图标、快捷键、箭头 `text_disabled`；**禁用且高亮**——行底 `surface_row_hover`，文字仍为 `text_disabled`（禁用项可获得高亮但不可激活，与 Windows 一致）；打开了子菜单的菜单项在子菜单存在期间保持高亮。经**键盘**移动到的高亮项（`from_keyboard` 为真，焦点可见）在行底之上另画 `drawRowFocus(R, false)`（REQ-THEME-038）作为焦点指示；鼠标悬停产生的高亮不画。禁用项上鼠标指针为箭头。

**REQ-W-MENU-008**　顶层项的视觉：常态——无容器，文字 `text_primary`；悬停——`drawRaised(quiet)` 悬停变体；其菜单展开期间——按下变体（`drawRaised(quiet)` 按下，内容下移 1 ppx）；菜单栏模式下获得焦点的项——悬停变体加 `drawFocusRing`（焦点可见）；禁用（`beginMenu` 的 `enabled = false`）——文字 `text_disabled`、不画容器、不响应悬停。

**REQ-W-MENU-009**　标题中的助记符按 REQ-INPUT-046 解析：显示文本去除 `&`，被标记字符以下划线显示。顶层项与菜单项的下划线在下列任一条件成立时显示：`ui.keyboardCuesVisible()` 为真（REQ-INPUT-047）；菜单栏处于菜单栏模式；本菜单是经键盘打开的（`from_keyboard`）。其余时候不画下划线（但助记符仍然有效）。`&&` 显示为 `&`；标题中没有 `&` 的项无助记符。

**REQ-W-MENU-010**　**命令绑定**：`MenuItemOptions.command` 非空时，菜单项的标题取 `app.commands.titleOf(cmd)`（含助记符）、图标取 `app.commands.iconOf(cmd)`、快捷键文本取 `formatChord(shortcutOf(cmd))`（REQ-APP-029；命令无快捷键则无文本；改绑后下一次构建更新）、启用与勾选经 `ui.commandState(cmd)` 读取本窗口本次构建中最近一次 `ui.command(cmd, CommandState)` 声明的状态（未声明取注册时的 `default_state`，REQ-APP-024）——勾选非空时按勾选项绘制。此时 `label` 参数与 `icon`、`shortcut_text`、`checked`、`enabled` 选项被忽略。菜单项被激活时调用 `ui.invoke(cmd, .menu)`（REQ-APP-026），同时 `MenuItemResult.clicked` 为真。未绑定命令的菜单项由调用方给出 `label`、`icon`、`shortcut_text`、`checked`、`enabled`，激活时只报告 `clicked`。

## 4. 变体与参数

菜单没有外观变体。选项：

| 参数 | 所属 | 类型 | 默认 | 含义 |
|---|---|---|---|---|
| `enabled` | 菜单栏、菜单、菜单项 | `bool` | `true` | 禁用 |
| `icon` | 菜单项 | `?theme.Icon` | `null` | 图标 |
| `shortcut_text` | 菜单项 | `?[]const u8` | `null` | 快捷键文本（仅展示；真正的快捷键由命令系统处理） |
| `checked` | 菜单项 | `?bool` | `null` | 非空时为可勾选项；`true` 画标记 |
| `radio` | 菜单项 | `bool` | `false` | 与 `checked` 同用：选中以圆点而非勾表示 |
| `command` | 菜单项 | `?input.CommandId` | `null` | 绑定命令（REQ-W-MENU-010） |
| `debug_name`、`key` | 通用 | | | 见模板 |
| `layout` | 菜单栏、菜单项 | `layout.ItemOptions` | `.{}` | 仅对菜单栏有意义；菜单项忽略除 `hidden` 外的字段 |

**REQ-W-MENU-011**　`beginMenu` 返回该菜单当前**是否展开**；**仅当返回真时**调用方才声明其内容并必须调用 `endMenu`（返回假时不得调用 `endMenu`）。`beginMenuBar` 之后、`endMenuBar` 之前的直接子项是顶层 `beginMenu`；菜单内的 `beginMenu` 是子菜单。菜单内容在弹出层声明期间才被构建（REQ-FRAME-016）：菜单未展开时其内容函数不运行，没有节点开销。`menuItem` 的 `clicked` 是激活类结果（触发同帧第二构建遍）。顶层项与菜单项的 ID 由 `@src()` 与可选 `key` 决定；动态生成的菜单项**必须**使用 `key`（REQ-FRAME-004）。

**REQ-W-MENU-012**　没有任何项的菜单（`beginMenu` 展开后无 `menuItem`/子菜单）展开时显示一个高 `row_h` 的占位行（禁用外观、无文字），不崩溃；全部项均为分隔线或全部禁用的菜单可正常展开，Up/Down 在其中仍按 REQ-W-MENU-025 在可高亮项间移动。

## 5. 状态

### 5.1 状态机

菜单会话状态（对菜单栏或上下文菜单的所有者保留，REQ-W-MENU-038）：`path`（已展开的菜单序列，`path[0]` 为顶层菜单，其后为逐级子菜单，空表示全部关闭）；`hot[level]`（各级高亮项）；`bar_mode ∈ {否, 是}`；`drag ∈ {无, 按下于菜单栏}`；`from_keyboard ∈ {否, 是}`；`restore_focus`（进入菜单栏模式前的焦点节点）。

| 当前 | 事件 | 条件 | 下一状态 | 动作 |
|---|---|---|---|---|
| `path` 空，`bar_mode` 否 | 左键按下于启用的顶层项 | — | `path = [该菜单]`，`drag = 按下于菜单栏` | 展开菜单（顶层项 `capture_on_press = false`，后续指针事件按位置路由到弹出层）；`hot[0]` 空；`from_keyboard = 否` |
| `path` 非空 | 点击顶层项本身 | 即锚点 | `path` 空 | 轻关闭并吞掉该次点击（REQ-INPUT-053） |
| `path` 非空 | 指针悬停（移动到）另一个启用的顶层项 | — | `path = [那个菜单]` | 立即切换（不等延迟）；`hot[0]` 空 |
| `path` 非空 | 左键按下于另一个顶层项 | — | `path = [那个菜单]` | 轻关闭后该点击继续投递，打开新菜单 |
| `path` 非空 | 指针移动到某项 | 指针确实移动过 | 同 | `hot[level]` = 该项（若是有子菜单的项则启动 `hoverFor(menu)`） |
| 有子菜单项为 `hot` | 悬停连续 `menu_show_delay_ms` | 项启用 | `path` 追加子菜单 | 展开子菜单（`hot[level+1]` 空） |
| 有子菜单项 | 点击 / → / Enter / Space | 项启用 | `path` 追加子菜单 | 立即展开；键盘触发时 `hot[level+1]` = 首个启用项 |
| 某级有子菜单展开 | 指针连续 `menu_show_delay_ms` 停留在同级其他项上 | — | `path` 截断到该级 | 收起子菜单；期间指针进入子菜单则取消（REQ-W-MENU-019） |
| `path` 非空 | 左键释放于启用的非子菜单项 | `drag = 按下于菜单栏`，或该项上先有按下 | `path` 空 | 激活（REQ-W-MENU-039） |
| `path` 非空，`drag` 为是 | 左键释放于其他处 | 在发起项上 | `drag = 无` | 菜单保持展开（点击式打开） |
| `path` 非空，`drag` 为是 | 左键释放 | 在全部菜单与菜单栏之外 | `path` 空 | 关闭 |
| 任意 | Alt 单键 / F10 | `bar_mode` 否 | `bar_mode` 是 | 记 `restore_focus`，焦点移到首个启用顶层项（REQ-W-MENU-021） |
| `bar_mode` 是，`path` 空 | Alt 单键 / F10 / Esc | — | `bar_mode` 否 | 焦点回 `restore_focus`（REQ-W-MENU-022） |
| `bar_mode` 是，`path` 空 | ↓ / Enter / Space，或助记字符 | 焦点顶层项启用 | `path = [该菜单]`，`from_keyboard = 是` | 展开并高亮首个启用项 |
| 任意，无 `bar_mode` | Alt+顶层助记符（⑥） | 该顶层项启用，且为唯一匹配 | `bar_mode` 是，`path = [该菜单]` | 记 `restore_focus`，展开并高亮首个启用项 |
| 任意，无 `bar_mode` | Alt+顶层助记符（⑥） | 多个顶层项同助记符 | `bar_mode` 是，`path` 空 | 记 `restore_focus`，进入菜单栏模式，焦点移到先序上当前焦点之后的第一个匹配项，重复按下在匹配项间循环；**不展开**菜单 |
| `path` 非空 | ↑ / ↓ / Home / End / PageUp / PageDown | — | 同 | 移动 `hot[末级]`（REQ-W-MENU-025、REQ-W-MENU-026） |
| `path` 长度 ≥ 2 | ← / Esc | — | `path` 弹出末级 | 关闭最上一级，高亮留在其父菜单项 |
| `path` 长度 1，`bar_mode` 是 | ← / → 于顶层菜单 | 无子菜单可展 | `path = [相邻顶层菜单]` | 切换到相邻菜单并展开 |
| `path` 长度 1 | Esc | — | `path` 空 | 关闭；`bar_mode` 是则回到菜单栏模式（焦点留在该顶层项），否则焦点不动 |
| `path` 非空 | Enter / Space | `hot` 项启用且非子菜单 | `path` 空 | 激活 |
| `path` 非空 | 助记字符 | 唯一匹配且启用 | `path` 空 | 激活；多个匹配循环高亮（REQ-W-MENU-029） |
| `path` 非空 | Alt 单键 / F10 | — | `path` 空，`bar_mode` 否 | 关闭全部，焦点回 `restore_focus`（若有） |
| `path` 非空 | 轻关闭 / 宿主失活等（REQ-INPUT-054） | — | `path` 空 | 关闭全部；`bar_mode` 否 |
| 任意 | 菜单栏子树消失 / 变为禁用 | — | 全部清空 | 关闭全部 |

### 5.2 视觉表现

见 REQ-W-MENU-007、REQ-W-MENU-008、REQ-W-MENU-003、REQ-W-MENU-005、REQ-W-MENU-006。弹出层底 `drawPopupFrame(R, false)`（`surface_popup` 与 `border_strong` 发丝线描边；圆角与阴影由系统，REQ-THEME-025）。

## 6. 鼠标行为

**REQ-W-MENU-013**　顶层项登记 `click`（并 `hover_rebuild` 仅在有菜单展开时置位）。左键在启用的顶层项上**按下**即展开其菜单（不等释放，与 Windows 一致）。顶层项登记 `click` 且声明 `InteractOpts.capture_on_press = false`（REQ-INPUT-013：按下不建立隐式捕获），因此按下之后的 `pointer_move`/`pointer_up` 不被顶层项捕获，而是按位置路由到弹出层（REQ-INPUT-010），这是"按下–拖动–释放"（REQ-W-MENU-015）的基础；控件**不**调用 `ui.releaseCapture()`。再次点击已展开菜单的顶层项（锚点）关闭菜单，该次点击被吞掉，不会立即重新打开（REQ-INPUT-053）。顶层项上的右键、中键不处理，指针形状恒为箭头。禁用的顶层项吞掉点击（REQ-INPUT-009）。点击不使焦点离开原控件（顶层项 `take_focus_on_click = false`）。

**REQ-W-MENU-014**　某个顶层菜单展开期间，指针悬停到**另一个**启用的顶层项（命中该项且指针确实移动过）时，**立即**关闭当前菜单并展开那一项的菜单，无延迟；新菜单不高亮任何项（`hot` 空）。没有菜单展开时，悬停顶层项只改变其悬停外观（纯绘制），不展开菜单。

**REQ-W-MENU-015**　**按下–拖动–释放**：在顶层项上按下左键展开菜单后不释放，把指针移到某个菜单项上（`hot` 随之移动）后释放，该项若启用且不是子菜单项则**直接激活**（REQ-W-MENU-039）；释放时指针在禁用项、分隔线、子菜单项上无效果且菜单保持展开；在发起的顶层项自身上释放（未移动到菜单项上）视为"点击式打开"，菜单保持展开；在全部菜单与菜单栏之外释放则关闭全部菜单。仅当该次展开由菜单栏上的按下发起时才存在此"直接激活"；之后展开的菜单中，激活仍须在同一项上完成按下与释放（REQ-W-MENU-016）。

**REQ-W-MENU-016**　菜单项登记 `click`。**左键**在启用的非子菜单项上按下并在**同一项**上释放（点击，REQ-INPUT-015）即激活；按下后移到别处释放不激活；右键、中键的按下与释放无效果（不激活、不关闭菜单）。禁用项、分隔线上的点击被吞掉，菜单保持展开，不取得焦点。点击有子菜单的项（启用）立即展开其子菜单（不等延迟）并不激活；再次点击已展开子菜单的项保持展开。点击弹出层的空白（行之外、滚动提示条之外）无效果。

**REQ-W-MENU-017**　指针在某菜单项上移动使其成为该级高亮项（`hot`），仅当指针自上一次构建以来确实移动过才生效——键盘移动高亮、弹出层滚动或刚展开时静止的指针所在项不夺走高亮。菜单项节点置 `hover_rebuild`，使悬停引起的高亮变化作为 `build` 级失效处理，损伤限于旧、新高亮行。指针离开所有菜单项（如到分隔线、弹出层外）时高亮保持不变。

**REQ-W-MENU-018**　**子菜单展开**：指针悬停在**启用的**有子菜单项上连续 `SystemMetrics.menu_show_delay_ms`（读取系统度量，03；经 `ui.hoverFor(id, .menu)`，REQ-INPUT-056）后展开其子菜单，不展开期间无轮询（`build` 级定时器到期唤醒）；点击、→、Enter、Space 立即展开。展开的子菜单不高亮任何项（键盘触发时高亮首个启用项）。禁用的子菜单项不展开。

**REQ-W-MENU-019**　**子菜单收起与斜向移动**（确定性规则）：设某级菜单 M 中的项 P 的子菜单 S 已展开。当且仅当指针**位于 M 的其他项上**并连续停留 `menu_show_delay_ms`（读取系统度量；经 `ui.notHoverFor(P, .menu)` 且指针悬停在 M 的非 P 项上）时收起 S，并截断其下全部更深的子菜单；停留不足延迟就进入 S（或回到 P）则计时作废。因此鼠标斜向移向子菜单途中经过 P 的下一个兄弟项不会立即收起 S。若那个兄弟项本身有子菜单，它的展开计时与 S 的收起计时同时开始，到期同一帧内先收起 S 再展开新子菜单。指针移出全部菜单窗口不触发收起。键盘 ← 或 Esc 立即收起最上一级。

**REQ-W-MENU-020**　弹出层上的滚轮只在该弹出根内路由（REQ-INPUT-019）：菜单高度未超限时滚轮被丢弃；超限时按 REQ-W-MENU-006 滚动。菜单栏上的滚轮不处理，冒泡。指针形状在所有菜单与菜单栏内恒为箭头（REQ-THEME-032）。

## 7. 键盘行为

| 键 | 场景 | 行为 |
|---|---|---|
| Alt（单独按下并释放）、F10 | 任意 | 进入菜单栏模式；再按一次（或 Esc）退出，焦点还给原控件 |
| Alt+助记字符 | 任意（⑥） | 展开对应顶层菜单并高亮首个启用项；进入菜单栏模式 |
| ← / → | 菜单栏模式（菜单未展开） | 在顶层项间移动焦点（跳过禁用，首尾回绕） |
| Home / End | 菜单栏模式 | 首个 / 最后一个启用顶层项 |
| ↓ / Enter / Space | 菜单栏模式，焦点在顶层项 | 展开该菜单并高亮首个启用项 |
| 助记字符 | 菜单栏模式 | 唯一匹配的顶层项展开其菜单；多个匹配则循环移动焦点 |
| ← / → | 某顶层菜单展开，高亮项无子菜单可展 | 切换到相邻顶层菜单并展开（首尾回绕），高亮首个启用项 |
| ↑ / ↓ | 菜单展开 | 在可高亮项间循环移动，跳过分隔线（禁用项可被高亮） |
| Home / End | 菜单展开 | 第一个 / 最后一个可高亮项 |
| PageUp / PageDown | 菜单展开 | 高亮移动 `可视行数 − 1`（至少 1）项，夹紧到首/末项（不回绕） |
| → | 高亮项是启用的子菜单项 | 展开子菜单并高亮其首个启用项 |
| ← | 子菜单 | 关闭该子菜单，高亮回到父菜单项 |
| Enter / Space | 菜单展开 | 激活高亮项（启用且非子菜单）；子菜单项则展开；禁用项无效果 |
| 助记字符 | 菜单展开 | 唯一匹配且启用 → 激活；唯一匹配但禁用 → 仅高亮；多个匹配 → 循环高亮，不激活 |
| Esc | 菜单展开 | 只关闭最上一级；关闭顶层菜单后若在菜单栏模式则停在该顶层项，否则不动 |
| Alt（单键）、F10 | 菜单展开 | 关闭全部菜单并退出菜单栏模式（`activate_menu_bar` 经 REQ-INPUT-027 的例外投递给菜单栏节点，即使弹出根已抢占键盘） |
| Tab、其余键 | 菜单展开 | 被弹出层吃掉（REQ-INPUT-027），无效果 |
| Shift+F10、菜单键 | 焦点在登记了上下文菜单的控件上 | 在焦点节点处展开上下文菜单（REQ-INPUT-018），高亮首个启用项 |

**REQ-W-MENU-021**　**进入菜单栏模式**：菜单栏的节点登记并处理框架的 `activate_menu_bar` 事件（Alt 单独按下并释放，或 F10 单键——二者等效，REQ-INPUT-033；这两个键不可被预占，REQ-INPUT-028；该通知不受弹出根的键盘抢占影响，始终投递给主根的菜单栏节点，REQ-INPUT-027 的例外）。菜单栏模式未激活时收到该事件：记录 `restore_focus` = 当前焦点节点，`bar_mode` 置真，焦点移到首个启用的顶层项（`ui.setFocus`，原因 `programmatic`），顶层项的助记符下划线显示（REQ-W-MENU-009），并按 REQ-INPUT-044 不触发滚动。菜单栏中无启用项时忽略。窗口内有多个菜单栏时，由 `activate_menu_bar` 的投递规则（08：向主根登记了菜单栏的节点）决定，本文规定每个窗口至多一个菜单栏（调试构建对第二个断言）。

**REQ-W-MENU-022**　**退出菜单栏模式**：菜单栏模式下（无菜单展开时）再次收到 `activate_menu_bar`（Alt 或 F10）、或按 Esc、或焦点因点击离开菜单栏（`focus_lost`）：`bar_mode` 置假，助记符下划线按 REQ-INPUT-047 恢复；Alt/F10/Esc 引起的退出把焦点还给 `restore_focus`（若该节点仍存在、启用且可聚焦；否则按 REQ-INPUT-042 转移）。该 Esc 被消费，**不**触发取消按钮。菜单栏模式下的其他键：不在 ← → Home End ↓ Enter Space 与助记字符之内的键继续按 08 路由（菜单栏成员仅声明处理这些键）。

**REQ-W-MENU-023**　菜单栏模式下顶层项持有真实焦点：← → 与 Home/End 由漫游组的组导航完成（REQ-INPUT-038，原因 `group`），跳过禁用项，`wrap` 为真；顶层项声明 `handles`：`arrows` 中的 ↓、Enter、Space 与 Esc，以及 `printable`（用于助记字符）。组导航不触发 REQ-INPUT-044 的滚动。Tab/Shift+Tab 在菜单栏模式下离开菜单栏并退出该模式（原因 `tab`，焦点按 Tab 序转移）。

**REQ-W-MENU-024**　**Alt+助记符**：每个启用的顶层项经 `ui.mnemonic(id, ch, .activate)` 登记其助记符（REQ-INPUT-048）。Alt+字符：唯一匹配 → 展开该菜单（进入菜单栏模式，`restore_focus` = 当前焦点，高亮首个启用项）；多个顶层项同一助记符 → 不展开，焦点（进入菜单栏模式）移到先序上当前焦点之后的第一个匹配项，重复按下循环；零匹配 → 不处理，继续 ⑦。Alt 作为组合修饰使用（Alt+字符）时，随后的 Alt 释放**不**构成"Alt 单独按下并释放"，不触发进入/退出。禁用的顶层项不登记助记符。

**REQ-W-MENU-025**　菜单展开时 ↑/↓ 作用于最上一级菜单：移动到上一个/下一个**可高亮项**（非分隔线的项，含禁用项），首尾**循环**（末项 ↓ 到首项，首项 ↑ 到末项）；`hot` 为空时 ↓ 到首个可高亮项、↑ 到最后一个。移动后保证该行可见（REQ-W-MENU-006）。自动重复照常生效。高亮的移动不激活、不展开子菜单。

**REQ-W-MENU-026**　Home/End 把高亮移到第一个/最后一个可高亮项；PageUp/PageDown 把高亮移动 `可视行数 − 1`（至少 1）个可高亮项，夹紧到首/末项、不回绕；高亮保证可见。

**REQ-W-MENU-027**　→ 在高亮项为启用的子菜单项时展开其子菜单并高亮其首个启用项；若高亮项不是子菜单项且当前菜单是由菜单栏展开的**顶层菜单**，则切换到下一个启用的顶层菜单（首尾回绕）并展开，高亮其首个启用项；子菜单或上下文菜单内的 → 在非子菜单项上无效果。← 在子菜单内关闭该子菜单，高亮回到其父菜单项；在由菜单栏展开的顶层菜单内切换到上一个启用的顶层菜单；在上下文菜单的顶层内无效果。Enter、Space 在子菜单项上展开子菜单（不激活）。

**REQ-W-MENU-028**　Enter 或 Space 在高亮项上：项启用且非子菜单 → 激活（REQ-W-MENU-039）；禁用 → 无效果（菜单保持）；子菜单项 → 展开。`hot` 为空时 Enter/Space 无效果。自动重复的 Enter/Space 被忽略（只激活一次）。

**REQ-W-MENU-029**　**菜单内的助记字符**（`char` 事件，无需 Alt；弹出根的焦点面板声明 `preempt.printable`）：对当前最上一级菜单，按 REQ-INPUT-046 的折叠规则收集标题助记字符等于该字符的全部项（含禁用项，不含分隔线）：恰好一个且启用 → 激活（子菜单项则展开）；恰好一个但禁用 → 仅高亮，不激活；多于一个 → **不激活**，高亮先序上位于当前高亮项**之后**的第一个匹配项（`hot` 空时取第一个），首尾回绕，重复按键循环；零个 → 无效果。助记符只在本菜单的弹出根内查找（REQ-INPUT-048 末句）。

**REQ-W-MENU-030**　Esc 在菜单展开时由框架在弹出根内无处理者时关闭最上层弹出层（REQ-INPUT-027，原因 `escape`），**只关最上一级**：子菜单内关闭子菜单；顶层菜单内关闭该菜单。关闭后的状态：由菜单栏键盘展开（`bar_mode` 为真）→ 停在该顶层项上、仍处菜单栏模式；由鼠标展开或上下文菜单 → 全部关闭、焦点不动。Esc 不触发所在范围的取消按钮。

**REQ-W-MENU-031**　经键盘展开的菜单（Alt+助记符、菜单栏模式下 ↓/Enter/Space、→ 展开子菜单、菜单栏左右切换、Shift+F10/菜单键）**必须**高亮其首个启用项（全部禁用时高亮第一个可高亮项）；经鼠标展开的菜单不高亮任何项，直到指针移动到某项或按键。键盘展开使 `from_keyboard` 置真，直至该会话结束。

## 8. 焦点

**REQ-W-MENU-032**　**菜单栏**：顶层项可聚焦（`focusable`），但 `take_focus_on_click = false`，且菜单栏漫游组声明 `GroupSpec.tab_stop = false`：只有菜单栏模式（Alt/F10/Alt+助记符）能使其获得焦点，Tab 序不经过菜单栏；漫游组声明为水平方向。菜单栏模式下焦点环按焦点可见规则绘制（Alt/F10 是 `key_down`，故焦点可见恒为真）。**弹出菜单**：每个展开的菜单弹出根的**弹出焦点**是其内容面板节点（`ui.setFocus`，REQ-INPUT-036），面板接收该级的全部键盘事件；宿主的焦点节点保持不变（不丢失、不重绘为非焦点），弹出层全部关闭后键盘回到宿主焦点节点。菜单栏模式下进入菜单时，顶层项仍是宿主焦点（菜单栏模式的一部分）。

**REQ-W-MENU-033**　**焦点归还**：菜单会话结束时——激活某项、Esc 逐级关闭至退出、Alt/F10 退出、轻关闭——凡会话经菜单栏模式进行（`restore_focus` 非空），宿主焦点在会话结束的那次构建完成后被设回 `restore_focus`（`ui.setFocus`；节点已不存在或不可聚焦则按 REQ-INPUT-042 转移）；鼠标直接展开且从未进入菜单栏模式的会话不改变宿主焦点。激活命令的处理函数在焦点归还**之前**不运行（命令执行时机见 REQ-W-MENU-039），因此命令处理函数看到的焦点节点已是原控件。窗口失去激活时 `restore_focus` 被丢弃，焦点按 REQ-INPUT-041 恢复到被记住的节点。

## 9. 文本与输入法

菜单标题与快捷键文本为单行显示文本，不接受文本输入；弹出菜单聚焦期间输入法处于禁用状态（面板与顶层项不声明 `text_input`）。字符键用于助记符（REQ-W-MENU-029），不是文本输入。标题中的换行与制表符按 05 的单行规则显示为空格；空标题且无图标（非命令项）是编程错误（调试构建断言，发布构建显示空白行）。

## 10. 动效

| 属性 | 触发 | 时长令牌 | 缓动 | 影响级别 |
|---|---|---|---|---|
| 顶层项容器（常态 ↔ 悬停） | 悬停变化 | `dur_fast` | `ease_out` | paint（`Visual.hover_t`） |
| 顶层项容器（→ 按下） | 菜单展开 | `dur_instant` | — | paint |
| 弹出层出现 | 展开 | 系统菜单淡入开启时 `dur_fast` 透明度淡入，否则瞬时 | `ease_out` | paint |
| 弹出层消失 | 关闭 | 瞬时 | — | — |
| 菜单项高亮 | 高亮移动 | 无（瞬时） | — | build |

**REQ-W-MENU-034**　弹出层的出现动画完全遵循系统设置（REQ-THEME-020）：`SystemMetrics.menu_animation` 与 `menu_fade` 均为真，且 `client_animation` 为真时，菜单与子菜单、上下文菜单的弹出窗口内容以 `dur_fast` 透明度从 0 淡入到 1（`paint` 级，窗口位置与尺寸不变）；否则一帧内完整出现。消失一律瞬时。淡入期间菜单已可交互：该期间的点击与按键立即生效，不排队。

## 11. 无障碍

| 项 | 值 |
|---|---|
| UIA 控件类型 | 菜单栏：MenuBar；弹出菜单：Menu；菜单项与顶层项：MenuItem；分隔线：Separator |
| 名称来源 | 去除助记符标记的标题（命令绑定项取命令标题） |
| 支持的模式 | 顶层项与子菜单项：ExpandCollapse；叶子项：Invoke；勾选/单选项：Toggle（单选项的选中亦以 Toggle 的 On 表示）；Menu 与 MenuBar 的子项经 UIA 树导航 |
| 状态属性 | IsEnabled（禁用项仍可被高亮与聚焦读取）、HasKeyboardFocus（高亮项）、AccessKey（形如 "Alt+F"，顶层项；菜单内为字符本身）、AcceleratorKey（快捷键文本，如 "Ctrl+N"）、ExpandCollapseState、ToggleState、IsOffscreen（滚动出可视区的项） |

**REQ-W-MENU-035**　经 UIA：对顶层项 `Expand` 等同点击展开（进入菜单栏模式，`from_keyboard` 为真）、`Collapse` 等同 Esc；对叶子项 `Invoke` 等同 Enter 激活（关闭整个菜单栈，调用命令，下一帧报告 `clicked`）；对勾选项 `Toggle` 等同激活；禁用项的模式调用返回 `ElementNotEnabled`。菜单展开与关闭产生 UIA 的 `MenuOpened`/`MenuClosed` 事件；菜单栏模式的进入与退出产生 `MenuModeStart`/`MenuModeEnd`。

## 12. API 草案

```zig
// 草案：仅签名
pub const MenuBarOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    layout: layout.ItemOptions = .{},
};

pub const MenuOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,     // 也用于其弹出根的定位（回放 `@名字`）
    enabled: bool = true,
    icon: ?theme.Icon = null,           // 仅子菜单项：图标列
    layout: layout.ItemOptions = .{},   // 对顶层项仅 hidden 有意义；子菜单项忽略
};

pub const MenuItemOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    icon: ?theme.Icon = null,
    shortcut_text: ?[]const u8 = null,  // 借用至本帧结束
    checked: ?bool = null,              // 非空 = 可勾选项
    radio: bool = false,                // 与 checked 同用：选中以圆点表示
    command: ?input.CommandId = null,   // 非空时 label/icon/shortcut_text/checked/enabled 取自命令（REQ-W-MENU-010）
    layout: layout.ItemOptions = .{},   // 仅 hidden 有意义
};

pub const MenuItemResult = struct {
    // 持续性状态
    hovered: bool,
    highlighted: bool,   // 该项是其菜单当前的高亮项
    // 激活类结果（触发同帧第二构建遍，REQ-FRAME-030）
    clicked: bool,       // 被激活（鼠标、键盘、助记符、UIA）；命令绑定项同时已排入命令调用
};

pub const ContextMenuOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
};

/// 菜单栏：返回其 ID。beginMenuBar/endMenuBar 严格配对。
pub fn beginMenuBar(ui: *Ui, src: std.builtin.SourceLocation, opts: MenuBarOptions) WidgetId;
pub fn endMenuBar(ui: *Ui) void;

/// 顶层菜单（在 beginMenuBar 内）或子菜单（在菜单内）。返回是否展开；仅返回 true 时声明内容并调用 endMenu。
/// label 含助记符（REQ-INPUT-046），借用至本帧结束。
pub fn beginMenu(ui: *Ui, src: std.builtin.SourceLocation, label: []const u8, opts: MenuOptions) bool;
pub fn endMenu(ui: *Ui) void;

/// 菜单项（须在 beginMenu 为 true 的内容或上下文菜单内）。label 对命令绑定项被忽略。
pub fn menuItem(ui: *Ui, src: std.builtin.SourceLocation, label: []const u8, opts: MenuItemOptions) MenuItemResult;
pub fn menuSeparator(ui: *Ui, src: std.builtin.SourceLocation) void;

/// 上下文菜单：所有者在收到 Interaction.context_menu 的那次构建中调用 openContextMenu 记录请求；
/// 之后每次构建调用 beginContextMenu（owner 为所有者节点 ID），返回是否展开；仅为 true 时声明内容并调用 endContextMenu。
/// 菜单关闭（激活、Esc、轻关闭）后下一次 beginContextMenu 返回 false。
pub fn openContextMenu(ui: *Ui, owner: WidgetId, request: input.ContextRequest) void;
pub fn beginContextMenu(ui: *Ui, src: std.builtin.SourceLocation, owner: WidgetId, opts: ContextMenuOptions) bool;
pub fn endContextMenu(ui: *Ui) void;
```

`clicked` 是激活类结果；`hovered`、`highlighted` 为持续性状态。传入的字符串借用至本帧结束；菜单会话状态由框架保留。

## 13. 保留状态

| 字段 | 类型 | 保留级别 | 说明 |
|---|---|---|---|
| `path` | `[8]WidgetId` + 长度（已展开的菜单 ID 序列；最大深度 8） | transient（属于菜单栏或上下文菜单所有者；会话期间每次构建被触达） | 超出深度的子菜单不展开并在调试构建 `warn` |
| `hot` | 每级 `?WidgetId` | transient | 各级高亮项 |
| `bar_mode`、`from_keyboard`、`drag` | `bool`、`bool`、枚举 | transient | |
| `restore_focus` | `WidgetId` | transient | |
| `last_pointer` | `?Vec2` | transient | 判定指针是否移动（REQ-W-MENU-017） |
| `scroll` | 每级 Scroll 偏移 | transient | 过高菜单 |
| `context_request` | `?ContextRequest` | transient（属于所有者） | `openContextMenu` 记录 |

菜单栏的 `transient` 会话状态在菜单栏停止声明的下一次构建被回收，因此菜单栏消失即关闭全部菜单。悬停、按下、焦点是框架内建状态。

## 14. 失效规则

**REQ-W-MENU-036**　顶层项的绘制键**必须**由标题、`enabled`、是否展开、是否悬停之外的框架内建状态、菜单栏模式与焦点可见、助记符下划线是否显示构成。菜单项行的绘制键由标题、各列内容（图标、勾选状态、快捷键文本、有无子菜单）、`enabled`、是否高亮、助记符下划线是否显示构成；弹出根的绘制键由项数、滚动偏移、可视行区间、提示条状态构成。布局输入的内容度量键：顶层项由标题与字体；菜单项由标题、快捷键文本、各列有无与字体。

| 变化 | 置脏级别 | 损伤范围 |
|---|---|---|
| 无菜单展开时顶层项悬停进入/离开 | `paint` | 该顶层项绘制范围 |
| 菜单展开时顶层项悬停（切换菜单） | `build` | 菜单栏相关项矩形与新旧弹出根 |
| 弹出层内悬停项变化（行 `hover_rebuild`） | `build` | 弹出根内旧、新高亮行矩形；宿主窗口损伤为空 |
| 键盘移动高亮 | `build` | 弹出根内旧、新高亮行矩形（滚动时为可视行区间） |
| 展开/关闭菜单、展开/收起子菜单 | `build` | 顶层项矩形与对应弹出根（新建或销毁整个弹出窗口） |
| 悬停延迟定时器到期（子菜单展开/收起、提示条滚动） | `build` | 对应弹出根 |
| 命令状态（启用/勾选/标题）变化 | `build` | 受影响的菜单项行（菜单未展开则无损伤） |

**REQ-W-MENU-037**　菜单展开且无输入、无定时器待决时，应用**必须**无帧（被动刷新，REQ-FRAME-053）：悬停延迟定时器只在"指针悬停在有子菜单的项上且尚未到期"或"提示条悬停滚动"期间登记，到期或条件消失即取消，无轮询。仅无菜单展开时顶层项的悬停进入/离开所产生的帧**必须**是纯绘制帧（构建遍数 0），损伤不超出该顶层项的绘制范围。

## 15. 边界与错误情况

| 情况 | 规定 |
|---|---|
| 菜单栏无项 / 全部项禁用 | 菜单栏照常绘制；Alt/F10 在无启用项时忽略；助记符无匹配 |
| 菜单项标题为空且无图标（非命令项） | 见本文第 9 节：调试构建断言，发布构建显示空白行 |
| 菜单展开期间其 `beginMenu` 不再被调用（应用状态变化） | 该弹出根在下一次构建关闭（REQ-INPUT-051），`path` 截断 |
| 展开的菜单项被应用移除（动态菜单） | `hot` 夹紧或置空；该项上的悬停/按下被取消（REQ-INPUT-024） |
| 按下顶层项期间菜单栏消失 | 会话回收，无激活，弹出层关闭 |
| 激活的命令禁用（`ui.invoke` 作用于禁用命令） | 禁用命令的项在菜单中为禁用，不会被激活；经 UIA/程序直接调用时忽略并 `warn`（REQ-APP-026） |
| 激活时处理函数打开对话框或调用 `app.quit` | 菜单已先关闭（REQ-W-MENU-039），随后命令按 11 执行 |
| 子菜单深度 > 8 | 不展开并 `warn` |
| 屏幕边缘 | 翻转与夹紧由 Anchor 完成（REQ-W-MENU-002）；放不下时高度受限并滚动（REQ-W-MENU-006） |
| 宿主窗口失去激活、被移动、缩放、最小化、DPI 变化、系统取消模式、宿主打开对话框 | 全部菜单关闭（`popup_dismissed`，REQ-INPUT-054），菜单栏模式退出；`dialog_opened` 同样关闭 |
| 菜单展开时系统菜单（Alt+空格） | 03 另行规定；菜单随宿主失活关闭 |
| 同一帧内左键释放（激活）与 Enter | 只激活一次 |
| 上下文菜单所有者在菜单展开期间消失/禁用 | 菜单随所有者的 `beginContextMenu` 不再被调用而关闭 |
| 高对比度 | 高亮行底用系统高亮色映射（REQ-THEME-035，`surface_row_hover` 的映射），文字对比保持 |
| 同一菜单项被点击期间标题变化 | 允许；不影响点击判定 |
| 菜单项 `checked` 与 `command` 同时给出 | 以命令的勾选状态为准（REQ-W-MENU-010） |

**REQ-W-MENU-038**　菜单会话状态属于所有者：菜单栏的会话状态键为菜单栏的 ID，上下文菜单的键为其所有者的 ID。同一时刻整个窗口至多一个会话在进行：新会话开始（如在展开的菜单栏菜单期间右键点击控件）时，先关闭旧会话（旧会话的弹出层因轻关闭而关闭，REQ-INPUT-052）。会话的所有状态在会话结束（`path` 为空且 `bar_mode` 为假）时清除，不跨会话保留（下次展开从头开始：无高亮、滚动偏移 0）。

**REQ-W-MENU-039**　**激活**：激活一个菜单项（点击、拖动释放、Enter/Space、助记符、UIA）时依次：(1) 把会话的 `path` 清空（**关闭整个菜单栈**，各级弹出层在下一次声明时被移除）；(2) 若菜单项绑定了命令，调用 `ui.invoke(cmd, .menu)`，处理函数在本次构建遍结束后**立即**执行，早于同帧的第二构建遍（REQ-APP-026）；(3) 该项的 `MenuItemResult.clicked` 在激活的那一次构建遍中为真（激活类结果，触发同帧第二构建遍），第二遍中为假。因此"关闭"先于"报告"，二者在**同一帧**内完成：该帧提交时菜单窗口已不存在、模型已被命令更新。菜单**不提供**"激活后保持打开"（如勾选项）的选项，勾选项激活后同样关闭整个菜单栈（见 OPEN-W-MENU-04）。

**REQ-W-MENU-040**　**上下文菜单的触发**：所有者控件在 `Interaction.context_menu` 非空（右键释放，或 Shift+F10/菜单键，REQ-INPUT-018）的那次构建中调用 `openContextMenu(ui, owner, request)`；`request.pos` 为指针位置（鼠标）或焦点节点矩形左下角（键盘），`request.anchor` 为以指针为原点的 1×1 lpx 矩形（鼠标）或焦点节点矩形（键盘），所有者**可以**在传入前调整 `anchor`（如文本框改为光标矩形）。菜单展开位置按 REQ-W-MENU-002：弹出层的左上角对齐锚矩形的左缘、下沿（鼠标时即指针右下 1 lpx）；右侧放不下时因 `flip_cross` 改为出现在指针左侧（菜单右缘对齐锚矩形右缘，不盖住指针；改对齐后仍越界才平移夹紧），下方放不下时翻转到锚矩形上方。`request.from_keyboard` 为真时按 REQ-W-MENU-031 高亮首个启用项并显示助记符下划线；鼠标触发则不高亮。上下文菜单其余行为（项、导航、助记符、激活、子菜单、关闭）与下拉菜单相同；它没有菜单栏模式与 `restore_focus`，关闭后宿主焦点不变。右键**按下**不展开菜单，释放时才展开（与 REQ-INPUT-018 一致）。

## 16. 验收标准

**夹具 F-MN**（除特别注明外）：行高取 `font_body` 的令牌行高 16（REQ-THEME-016），与 fixed 后端的自然行高无关（菜单行高另由令牌 `row_h` = 22 给定）；无头、`fixed` 文本后端（簇宽 6 px，行高 16 px）、缩放 1.0、窗口 400×300（屏幕工作区同窗口，窗口位于屏幕 (0,0)）；`menu_show_delay_ms` = 400、`hover_time_ms` = 400、`keyboard_cues` = off、`menu_animation` = off。窗口内 (0,0) 起为菜单栏 `@bar`（400×24），其下 (0,24) 起为文本框 `@T`（后接按钮 `@B`，Tab 序 @T → @B），菜单栏顶层项依次为（括号内为 `debug_name`）：`&File`（`@File`，x ∈ [0,40)）、`&Edit`（`@Edit`，[40,80)）、`&View`（`@View`，[80,120)），y ∈ [0,24)；顶层项宽 = 16 + 标题宽（4 簇 = 24）= 40。**File** 菜单项依次：0 `&New`（快捷键文本 "Ctrl+N"，`@New`）、1 `&Open`（"Ctrl+O"，`@Open`）、2 `&Save`（"Ctrl+S"，**禁用**，`@Save`）、3 分隔线、4 `&Recent`（子菜单，`@Recent`；子项 `one.txt`、`two.txt`）、5 分隔线、6 `E&xit`（`@Exit`）。**Edit** 菜单项：0 `&Alpha`、1 `&Another`、2 `B&eta`（`@Beta`）、3 `&Gamma`（**禁用**）。**View** 菜单项：0 `&Status Bar`（`checked` = true）、1 `&Compact`（`radio`，选中）、2 `&Normal`（`radio`，未选中）。回放记号：`按 X` 为键的按下与释放；`Alt` 为 `VK_MENU`；"点击 (x,y)" 为 `move` + `down left` + `up left`。弹出层矩形取自 `headless.popupRects()`（屏幕坐标）。

**弹出层几何（由 REQ-W-MENU-004、REQ-W-MENU-003、REQ-W-MENU-005 推得）**：File 菜单——行起点 y = 24 + `pad_popup_y` = 28；项 0 [28,50)、项 1 [50,72)、项 2 [72,94)、分隔线 [94,102)、项 4 [102,124)、分隔线 [124,132)、项 6 [132,154)；高 = 4 + 5×22 + 2×8 + 4 = 134；宽 = 8 + 标题最宽（"Recent" 36）+ `gap_lg` 12 + 快捷键最宽（"Ctrl+N" 36）+ 箭头列（4 + 16）+ 8 = 120；矩形 **(0,24,120,134)**。`Recent` 子菜单——矩形 **(120,102,58,52)**（顶边对齐父项顶边 102；宽 = 8 + "one.txt" 42 + 8；高 = 4 + 2×22 + 4），其项 `one.txt` [106,128)、`two.txt` [128,150)。Edit 菜单——矩形 **(40,24,58,96)**（宽 = 8 + "Another" 42 + 8）。View 菜单——有标记列：宽 = 8 + 14 + 4 + "Status Bar" 60 + 8 = 94，矩形 **(80,24,94,74)**，标题左缘 x = 80 + 26。

**AC-W-MENU-001**　`[金图]` 覆盖：REQ-W-MENU-001、REQ-W-MENU-008、REQ-W-MENU-007、REQ-W-MENU-003、REQ-W-MENU-005、REQ-W-MENU-009、REQ-W-MENU-006、REQ-W-MENU-012。状态矩阵：菜单栏 {常态, 悬停 `@Edit`, `@File` 展开（按下外观）, 菜单栏模式（焦点环 + 下划线）, 禁用 `@Edit`, 全栏禁用}；弹出层 {File 菜单：高亮项 0, 高亮禁用项 2, 分隔线, 带快捷键文本, 子菜单箭头, 子菜单展开, 全部下划线显示/隐藏；View 菜单：勾选、单选选中/未选中；带图标项；长标题被省略；30 项过高菜单（上端禁用提示条、下端可滚动提示条）；空菜单占位行}，浅/深/高对比度，缩放 1.0/1.5/2.0。预期：与基准图一致；菜单栏高 24、底边为 `border_strong` 的结构性分隔线；顶层项展开时容器为按下外观、内容下移 1 ppx；高亮行底 `surface_row_hover` 占满行宽，键盘导航到的高亮行另有 `drawRowFocus` 的发丝线框；禁用且高亮的行文字仍为 `text_disabled`；快捷键文本为 `text_secondary`；勾为 `text_primary`、选中的单选为圆点；分隔线 `border_subtle` 两端内缩 8；下划线仅在 `keyboard_cues` 为真、菜单栏模式或键盘展开时出现；过高菜单的提示条各高 22、可视行区间 = 弹出高 − 8 − 44。

**AC-W-MENU-002**　`[单元]` 覆盖：REQ-W-MENU-002、REQ-W-MENU-004、REQ-W-MENU-003、REQ-W-MENU-006。几何（夹具同上）：File 菜单矩形 (0,24,120,134)；Recent 子菜单 (120,102,58,52)；将菜单栏移到窗口底部（y = 270 起）使下方放不下 → File 菜单翻到上方，顶边 = 270 − 134 = 136（矩形 (0,136,120,134)）；`@View` 位于窗口右缘使弹出层超出右边界 → x 平移夹紧到 400 − 94 = 306；把 File 菜单移到屏幕右缘使 Recent 子菜单右侧放不下 → 子菜单翻到父菜单左侧（x = 父菜单左缘 − 58）；长标题（比 `menu_max_w` 360 更宽）→ 菜单宽夹紧 360、标题尾部 `…`。30 项（每项 22，总高 4 + 660 + 4 = 668）的 File 菜单：弹出层 `max_height` = 工作区下方空间 300 − 24 = 276，矩形 (0,24,w,276)；上提示条 [28,50)、下提示条 [274,296)、可视行区间 [50,274)（224 px）；最大滚动偏移 = 660 − 224 = 436；子菜单嵌套达到第 9 级时该级不展开，调试构建记录 1 条 `warn`。

**AC-W-MENU-003**　`[回放]` 覆盖：REQ-W-MENU-013、REQ-W-MENU-014、REQ-W-MENU-016、REQ-W-MENU-017。（1）指针移到 `@File`（20,12）→ `expect visual @File hovered true`、`expect popup 0`（无菜单展开时悬停不展开）；点击 `@File` → 按下即 `expect popup 1`（`@File` 存在，矩形 (0,24,120,134)）、`@T` 仍持有焦点；再次点击 `@File` → `expect popup 0`（锚点例外：该次点击被吞掉，序列中无重新打开）。（2）展开 `@File` 后把指针移到 `@Edit`（60,12）→ File 弹出消失、Edit 弹出出现（同一轮分发内无"无菜单"的中间帧），矩形 (40,24,58,96)，无高亮；移到 `@View` → 同样切换。（3）展开 `@File`，指针移到项 0（20,35）→ `@New` `highlighted` 真、未激活；移到 (20,60)（项 1）→ 高亮项 1。在项 0 上按下、移到项 1 释放 → 无激活；在项 0 上按下并释放 → `@New` `clicked` 真且 `expect popup 0`。（4）禁用项 `@Save`（20,83）：点击 → 无激活、菜单保持展开、`@T` 焦点不变。分隔线（20,98）点击 → 无效果。（5）右键、中键在项上按下释放 → 无激活、菜单保持。（6）键盘移动高亮后（↓ 到项 1）静止的指针所在项（项 0）不夺回高亮；再移动指针 → 高亮跟随。（7）点击 `@Recent`（20,110）→ 立即展开子菜单（矩形 (120,102,58,52)），无高亮；再点击 `@Recent` → 保持展开。（8）点击 `@T`（菜单展开时，轻关闭）→ 菜单关闭、`@T` 获得焦点（点击继续投递）；点击窗口外 → `popup_dismiss{outside_click}` 关闭；点击另一个顶层项 `@Edit` 按下 → File 关闭并同一次点击展开 Edit。（9）`expect cursor arrow` 于菜单栏与各项；顶层项右键、中键无效果。

**AC-W-MENU-004**　`[回放]` 覆盖：REQ-W-MENU-015、REQ-W-MENU-013、REQ-W-MENU-039。（1）`move 20 12`、`down left` → `@File` 展开（按下即展开），`move 30 62`（项 1 "Open"）→ 高亮项 1，`up left` → `@Open` `clicked` 真、`expect popup 0`；该帧构建遍数 = 2（第二遍 `clicked` 假、菜单未再声明）。（2）`down left` 于 `@File`、`move 20 83`（禁用项 `@Save`）、`up left` → 无激活、菜单仍展开、高亮在 `@Save`。（3）`move 20 110`（子菜单项 `@Recent`）释放 → 无激活，菜单保持展开，高亮在 `@Recent`。（4）`down left` 于 `@File`、`up left` 于 `@File`（未移动）→ 菜单保持展开；其后在 `@New` 上按下并在 `@Open` 上释放 → 无激活。（5）`down left` 于 `@File`、`move 300 200`、`up left` → `expect popup 0`。（6）展开后经点击式打开的菜单，再从菜单项上按下、拖动到另一项释放 → 无激活（"直接激活"仅限菜单栏发起的那次按下）。

**AC-W-MENU-005**　`[回放]` 覆盖：REQ-W-MENU-018、REQ-W-MENU-019、REQ-W-MENU-017。展开 `@File`；`move 20 110`（`@Recent`，t0）：`advance 399` → `expect popup 1`（无子菜单）；`advance 1` → `expect popup 2`，子菜单矩形 (120,102,58,52)，无高亮。斜向移动：子菜单已展开，`move 20 140`（兄弟项 `@Exit`，t1）→ 高亮 `@Exit`，子菜单仍在；`advance 399` → 仍 `popup 2`；`advance 1` → `popup 1`（收起）。再展开子菜单后，`move 20 140`、`advance 300`、`move 130 115`（进入子菜单项 `one.txt`）→ `advance 1000` 后仍 `popup 2`（计时作废）。指针移出全部菜单窗口（300,250）`advance 1000` → 子菜单仍展开。回到父项：从子菜单 `move 20 110` → 子菜单保持。禁用子菜单项（另设一个禁用的 `beginMenu`）悬停 `advance 1000` → 不展开。设 `setting menu_show_delay_ms 200` → 展开与收起的延迟变为 200 ms；展开期间 `expect timers` 在悬停未到期时为 1、到期后为 0；`expect popup` 在静置 60 秒内帧数为 0（被动刷新）。

**AC-W-MENU-006**　`[回放]` 覆盖：REQ-W-MENU-021、REQ-W-MENU-022、REQ-W-MENU-023、REQ-W-MENU-032、REQ-W-MENU-033。`@T` 持有焦点。按 Alt（按下并释放，无其他键）→ `expect focus @File`、助记符下划线出现（金图/绘制日志）、`@File` 悬停变体 + 焦点环；按 → → `@Edit`；→ → `@View`；→ → 回绕 `@File`；按 End → `@View`；按 Home → `@File`；按 Esc → 退出，`expect focus @T`，下划线消失，**取消按钮未被触发**。按 F10 → `@File`；再按 F10 → 退出、焦点 `@T`。Alt（进入）后按 Alt → 退出。Alt 进入后 ↓ → `@File` 展开、`@New` 高亮；按 Esc → 菜单关闭、`expect focus @File`（仍在菜单栏模式）；再按 Esc → 退出、`expect focus @T`。Alt 进入后点击 `@T` → `focus_lost` 使退出（焦点在 `@T`，不再回到先前节点）。Tab 序列：从 `@T` 起 Tab → `@B` → 回绕 `@T`，菜单栏任何项均不在序列中；全栏禁用时 Alt 无效。菜单栏模式下按 Tab → 退出并按 Tab 序转移。

**AC-W-MENU-007**　`[回放]` 覆盖：REQ-W-MENU-024、REQ-W-MENU-031、REQ-W-MENU-030。`@T` 持有焦点：按 Alt+F（`key down VK_MENU`、`key down VK_F`、`key up VK_F`、`key up VK_MENU`）→ `@File` 展开，`@New` 高亮，之后 Alt 的释放不退出模式；Esc → 关闭并停在 `@File`；Esc → 退出，焦点回 `@T`。Alt+E → Edit 展开，高亮 `@Alpha`。Alt+Z（无匹配）→ 无事发生并继续 ⑦（按 Enter 前后默认按钮语义不变）。两个顶层项同助记符（另设 `&Export` 与 `&Edit`）：Alt+E → 不展开，焦点（进入菜单栏模式）到先序上当前焦点之后的第一个匹配项，再次 Alt+E → 循环到另一个；禁用的顶层项不登记助记符。鼠标展开的菜单（点击 `@File`）：无高亮、无下划线（`keyboard_cues` 关）、Esc → 全部关闭、焦点仍 `@T`（未进入菜单栏模式）。`setting keyboard_cues on` → 鼠标展开的菜单也显示下划线。

**AC-W-MENU-008**　`[回放]` 覆盖：REQ-W-MENU-025、REQ-W-MENU-026、REQ-W-MENU-028、REQ-W-MENU-007。Alt、↓ 展开 File，`@New` 高亮（项 0）。↓ → 项 1；↓ → 项 2（禁用项 `@Save`，高亮显示、`highlighted` 真）；↓ → 项 4（跳过分隔线）；↓ → 项 6；↓ → 回绕项 0；↑ → 回绕项 6；Home → 项 0；End → 项 6；PageDown → 项 6（夹紧）；PageUp → 项 0。在 `@Save`（禁用）上按 Enter → 无激活、菜单保持；按 Space → 同；在 `@New` 上按 Enter → `@New` `clicked` 真、菜单关闭、焦点回 `@T`；`key down VK_RETURN` 后 `key repeat VK_RETURN 5`（13 的自动重复指令）→ 只激活 1 次。`@Recent` 高亮时按 Enter → 展开子菜单，**不**激活，首个启用项 `one.txt` 高亮。全部禁用的菜单（另设）：Up/Down 在可高亮项间移动；全为分隔线的菜单：高亮保持空。

**AC-W-MENU-009**　`[回放]` 覆盖：REQ-W-MENU-027、REQ-W-MENU-030、REQ-W-MENU-023。Alt、↓ 展开 File；↓↓↓ 高亮 `@Recent`（项 4）；→ → 子菜单展开且 `one.txt` 高亮；← → 子菜单关闭、高亮回 `@Recent`、File 保持；再 → ，Esc → **只**关闭子菜单（File 保持）；Esc → 关闭 File（菜单栏模式，焦点 `@File`）；再 Esc → 退出。File 展开、高亮 `@New`（叶子）：→ → 切换到 Edit 并展开，`@Alpha` 高亮；→ → View；→ → 回绕 File；← → 回绕 View；Edit 展开时 ← → File 展开。子菜单内 → 于叶子项 → 无效果。上下文菜单顶层内 ←/→ 无效果（见上下文菜单用例）。

**AC-W-MENU-010**　`[回放]` 覆盖：REQ-W-MENU-029、REQ-W-MENU-039、REQ-W-MENU-010。Alt、↓ 展开 File：键入 `n`（`text "n"`）→ `@New` 激活（唯一匹配），菜单关闭；重开：键入 `s` → 唯一匹配 `@Save` 但禁用 → 仅高亮、无激活、菜单保持；键入 `x` → `@Exit` 激活；键入 `r` → `@Recent` 子菜单展开（唯一匹配，启用子菜单项展开）。Edit 展开：`a`（无需 Alt）→ 两个匹配（Alpha、Another）→ 高亮 `@Alpha`、不激活；再 `a` → `@Another`；再 `a` → 回绕 `@Alpha`；`e` → `@Beta` 唯一且启用 → 激活；`g` → `@Gamma` 禁用 → 仅高亮；`q` → 无效果。大小写：`N`（大写）同 `n`。命令绑定：`@New` 绑定命令 `file.new`（标题 `新建(&N)`、快捷键 Ctrl+N、`ui.command` 声明 `enabled = true`）：菜单项显示 "新建" 与 "Ctrl+N"、下划线于 N；激活 → 命令处理函数在**第一构建遍之后、第二遍之前**被调用恰一次（计数断言），第二遍中菜单已不声明（`expect popup 0`），`@New` `clicked` 在第一遍真、第二遍假；`ui.command("file.new", .{ .enabled = false })` → 该项为禁用外观（可高亮不可激活）；`checked = true` → 勾选项外观；`app.commands.setShortcut` 改绑为 Ctrl+Shift+N → 下一构建显示 "Ctrl+Shift+N"。

**AC-W-MENU-011**　`[回放]` 覆盖：REQ-W-MENU-040、REQ-W-MENU-002、REQ-W-MENU-038、REQ-W-MENU-031。窗口内有一个自定义节点 `@Pane`（登记 `context`，所有者），其上下文菜单项 `Cut`、`Copy`、`Paste`（宽 = 8 + 30 + 8 = 46，高 = 4 + 66 + 4 = 74）。右键按下 (200,150) → `expect popup 0`（按下不展开）；右键释放 → `expect popup 1`，矩形 (200,151,46,74)，无高亮。点击 `Copy` → 激活并关闭，菜单栈清空。右键释放于 (380,150) → 右侧放不下，`flip_cross` 使菜单出现在指针左侧：矩形 (335,151,46,74)（x = 锚矩形右缘 381 − 46）；右键释放于 (200,290) → 翻到上方：矩形 (200,216,46,74)。`@Pane` 聚焦后按 Shift+F10（`@Pane` 矩形 (300,150,60,20)）→ 矩形 (300,170,46,74)，`Cut` 高亮、助记符下划线显示；按菜单键 `VK_APPS` 同。Esc → 关闭、焦点不变。上下文菜单展开时右键点击 `@Pane` 另一处 → 旧菜单关闭并在新位置展开新菜单（至多一个会话）；在展开的菜单栏菜单期间右键 `@Pane` → 菜单栏菜单关闭、上下文菜单展开。上下文菜单项含子菜单时同下拉菜单行为。

**AC-W-MENU-012**　`[回放]` 覆盖：REQ-W-MENU-002、REQ-W-MENU-038、REQ-W-MENU-032、REQ-W-MENU-033。弹出层关闭情形（均以 `@T` 持有焦点、菜单经鼠标或键盘展开）：`activate off`（宿主失活）→ 全部关闭、菜单栏模式退出、不激活；`resize 300 200` → 关闭；窗口移动事件 → 关闭；`dpi 144` → 关闭；应用 `openDialog` → 关闭（原因 `dialog_opened`），宿主随后被禁用；系统取消模式（假平台 `popup_dismiss{cancel_mode}`）→ 关闭；点击窗口外 → 关闭。关闭不改变 `@T` 的焦点节点（鼠标展开情形），键盘/菜单栏模式展开的会话关闭后焦点回到进入前的节点（`@T`）；`activate off` 后 `activate on`：焦点按"恢复被记住的节点"回到 `@T`。菜单栏在菜单展开时被应用停止声明 → 菜单在下一次构建关闭。弹出层展开期间窗口内的文本框 `@T` 的光标仍显示/闪烁规则不变（宿主 `focused` 保持，REQ-INPUT-055）。

**AC-W-MENU-013**　`[回放]` 覆盖：REQ-W-MENU-006、REQ-W-MENU-026、REQ-W-MENU-020。设一个 30 项的 File 菜单（项 `Item 00`–`Item 29`，全部启用）：展开 → 矩形 (0,24,w,276)，上提示条无 `chevron_up`、下提示条有 `chevron_down`；`move` 到下提示条（`advance 50` ×2）→ 滚动偏移 44（每 `dur_autoscroll` 50 ms 滚动 22）；离开提示条 → 停止；`wheel -1`（向下 1 格，13 的符号：负值向下、偏移增大；`wheel_lines` = 3）→ 偏移 +66；设 `wheel_lines` 为 `page` → 滚动一页；键盘 End → 高亮项 29，偏移 = 最大 436、下提示条空、上提示条有箭头；Home → 偏移 0；PageDown 一次 → 高亮移动 `可视行数 − 1` = 9 项（224/22 向下取整 10，减 1）。滚动不改变高亮项；悬停在上提示条且偏移为 0 时无滚动、`expect timers` 无该定时器。

**AC-W-MENU-014**　`[回放]` 覆盖：REQ-W-MENU-039、REQ-W-MENU-016、REQ-W-MENU-003。View 菜单（勾选项与单选项）：点击 `&Status Bar`（`checked` = true，应用在 `clicked` 时翻转为 false）→ 菜单**关闭**（不保持打开），该帧内第二遍中应用状态已翻转，重新展开时标记消失；点击 `&Normal`（单选）→ 应用把选中移到 Normal，重开时圆点在 Normal 上；两项均**没有**"保持打开"行为。激活命令时序：命令处理函数中打开对话框 → 菜单在命令执行前已关闭。

**AC-W-MENU-015**　`[单元]` 覆盖：REQ-W-MENU-011、REQ-W-MENU-009、REQ-W-MENU-010、REQ-W-MENU-012。`parseMnemonic`：`&File` → 显示 "File"、助记符 F（范围 [0,1)）；`E&xit` → "Exit"、x；`A && B` → "A & B"、无助记符；`&A&B` → 显示 "AB"、助记符 A。调用形状：`beginMenu` 返回假时调用 `endMenu` 在调试构建断言；`beginMenuBar` 与 `endMenuBar` 未配对在构建遍结束时断言（REQ-FRAME-028）；第二个菜单栏断言；菜单展开后无项 → 占位行（高 22、禁用外观）；动态菜单项不带 `key` 的重复 ID 在调试构建中止（REQ-FRAME-005）。命令绑定的取值表：命令标题含 `&`、`default_state`、`checked = null`/`true`/`false` → 菜单项的标题、启用、勾选外观。

**AC-W-MENU-016**　`[单元]` 覆盖：REQ-W-MENU-035、REQ-W-MENU-001、REQ-W-MENU-029。经假 UIA 入口：菜单栏 MenuBar；顶层项 MenuItem + ExpandCollapse，`AccessKey` = "Alt+F"，`Expand()` → File 展开且 `ExpandCollapseState` 为 Expanded、`from_keyboard` 为真（`@New` 高亮），`Collapse()` → 关闭；`@New` 的 `Invoke()` → 下一帧 `clicked` 真恰一次、菜单栈关闭、命令被调用；`AcceleratorKey` = "Ctrl+N"；View 的 `&Status Bar` 提供 Toggle，`ToggleState` 与 `checked` 一致；禁用项 `@Save` 的 `Invoke()` 返回 `ElementNotEnabled`；名称为去除 `&` 的标题；Separator 类型存在；滚动出可视区的项 `IsOffscreen` 为真。事件：展开产生 `MenuOpened`、关闭产生 `MenuClosed`，Alt 进入/退出产生 `MenuModeStart`/`MenuModeEnd`。

**AC-W-MENU-017**　`[回放]` 覆盖：REQ-W-MENU-034、REQ-W-MENU-002。`setting menu_animation on`、`setting menu_fade on`、`setting client_animation on`：点击 `@File` → 弹出窗口内容首帧透明度 < 1，`advance 80` 后为 1（`dur_fast`），动画帧构建遍数 0、仅弹出根损伤；淡入中的 30 ms 时点击项 0 → 立即激活（不排队）；关闭 `menu_fade`、`menu_animation` 或 `client_animation` 任一 → 首帧即完全不透明；关闭时恒瞬时（无淡出帧）。

**AC-W-MENU-018**　`[计量]` 覆盖：REQ-W-MENU-036、REQ-W-MENU-037、REQ-W-MENU-017。（1）无菜单展开：指针从空白处移入顶层项 `@Edit` 再移出 → 各帧构建遍数 0，被绘制节点 ⊆ {`@Edit` 及与损伤相交的祖先}，损伤 ≤ `@Edit` 的绘制范围面积。（2）展开 `@File` 后，指针在项 0、项 1 之间移动 → 每帧宿主窗口损伤为空、弹出窗口损伤 = 旧高亮行矩形 ∪ 新高亮行矩形；以相同参数再次 `invalidate(.build)` → 损伤为空；仅改变 `@New` 的快捷键文本 → 损伤恰为该行矩形（弹出根内）。（3）静置：展开 `@File` 并将指针放在非子菜单项上、静置 60 秒 → `frame.count` 增量 = 0、进程 CPU 时间增量 < 10 ms（S-IDLE 同类约束，REQ-PERF-010）；指针悬停在 `@Recent` 上尚未到期时 `expect timers 1`，到期后为 0。（4）界面含 50 个顶层菜单（动态）：未展开时构建节点数不含任何菜单内容（`frame.nodes` 与无菜单时相同）。

**AC-W-MENU-019**　`[人工]` 覆盖：REQ-W-MENU-015、REQ-W-MENU-019、REQ-W-MENU-018、REQ-W-MENU-021、REQ-W-MENU-034、REQ-W-MENU-002、REQ-W-MENU-035。真实 Windows 10 与 11，浅/深色与高对比度，100%/150% 缩放，双显示器：对照记事本菜单——按下–拖动–释放直接激活的手感；子菜单展开与收起延迟（把"鼠标属性 → 菜单显示延迟"注册表值改为 0 与 800 ms 各试一次）；斜向移向子菜单的容错；Alt、F10、Alt+F 的菜单栏模式与记事本一致（含下划线时机）；菜单在屏幕右/下边缘的翻转、在副显示器上弹出；Windows 11 的圆角与阴影、Windows 10 的阴影；"显示动画"与"淡入淡出"选项开关对菜单出现的影响；宿主标题栏在弹出菜单期间保持活动色（弹出层不抢激活）；Narrator 朗读菜单栏、菜单项、勾选状态与快捷键。记录差异并回填待定问题。

## 17. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-W-MENU-04 | 勾选项激活后**不提供**保持菜单打开的选项（Windows 原生默认也是关闭） | 保持不提供；如需要（如连续切换多个选项），应用用面板或对话框代替 |
| OPEN-W-MENU-06 | 子菜单的收起延迟与展开延迟共用 `menu_show_delay_ms`（08 REQ-INPUT-056 同），原生菜单另有一个独立的收起容错 | 倾向沿用 08；斜向移动的实机体验需对照记事本，必要时增加几何容错（指针朝向子菜单运动的三角形区域） |
| OPEN-W-MENU-07 | 过高菜单的滚动提示条占据固定的 `row_h` 高度，视觉上与原生的滚动箭头略有差异 | 倾向保持；节拍已取 `dur_autoscroll` |
| OPEN-W-MENU-09 | 菜单项不提供图标之外的复合内容（如滑块、颜色块）、不提供项级 `tooltip`、不支持多列菜单 | 不在本版 |
| OPEN-W-MENU-10 | 鼠标展开的菜单是否显示助记符下划线（Windows 默认隐藏，除非系统"键盘提示"开启） | 保持与系统一致（REQ-W-MENU-009） |
| OPEN-W-MENU-11 | 菜单展开期间点击窗口标题栏/最大化等非客户区动作的关闭行为 | 取决于 03 的 `popup_dismiss` 覆盖范围（捕获被夺走 / 取消模式）；需实机确认 |
| OPEN-W-MENU-12 | 命令处理函数运行前焦点已归还原控件，若命令希望作用于"菜单栏模式前的焦点"则成立；若命令需要知道来自菜单栏则无此信息 | 倾向保持；命令来源已由 `InvokeSource.menu` 给出 |
