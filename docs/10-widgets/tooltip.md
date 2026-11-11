# 提示框（tooltip）

> 本文规范提示框的外观、位置、时序与键盘触发，建立在 08 的 `ui.tooltip(owner, text)`（REQ-INPUT-057，内部使用 `PopupKind.tooltip` 弹出层）之上：触发与消失条件的通用机制引用 08，本文给出控件层面的可判定细则，并补充 08 未覆盖的键盘焦点触发。弹出窗口的创建、不激活、鼠标穿透引用 03（REQ-PLAT-067、REQ-PLAT-068）；定位与翻转引用 07 的 Anchor。

## 1. 用途

给一个控件提供简短的补充说明：图标按钮的名称、被截断文字的全文、快捷键提示。参照 Windows 的 tooltip（`TOOLTIPS_CLASS`）。

- 提示框**只含文本**，不可交互；需要可点击、可选择的内容 → 用弹出层面板或对话框。
- 重要的错误或状态信息**不得**只放在提示框里（它只在悬停或键盘聚焦后才出现）；应同时有可见的图标或文字（REQ-THEME-006）。
- 纯图标且无文字的操作**必须**有提示框与无障碍名称（REQ-THEME-006）。

多数控件通过自己的 `tooltip` 选项使用本控件（如 button.md）；应用也可对任意节点直接调用 `w.tooltip`。

## 2. 解剖

```
  ● 指针（热点）
     ┌──────────────────────┐
     │ 保存 (Ctrl+S)         │   提示框 = drawPopupFrame(tooltip)
     └──────────────────────┘   主文本 text_primary + 次要文本 text_secondary
```

- **提示框**：独立的无边框弹出窗口，`surface_tooltip` 底。
- **主文本**：控件说明，`text_primary`。
- **次要文本**（可选）：快捷键提示，括号内，`text_secondary`，接在主文本之后同一文本流。

## 3. 度量与布局

| 项 | 取值（令牌） |
|---|---|
| 底与边框 | `drawPopupFrame(R, tooltip = true)`（`surface_tooltip`、`border_strong` 发丝线） |
| 内边距 | 水平 `pad_tooltip_x`，垂直 `pad_tooltip_y` |
| 文字样式 | `font_body`（次要文本同字体，色 `text_secondary`） |
| 最大宽度 | `tooltip_max_w`（含内边距） |
| 指针触发的偏移 | 提示框上缘相对指针热点下移 `tooltip_offset_y`（`ui.tooltip` 的位置，REQ-INPUT-057 与 09） |
| 键盘触发的位置 | 所属控件矩形下方，左对齐，间距 `gap_xs`；越界翻转（`ui.tooltip` 的键盘触发，REQ-INPUT-057） |
| 圆角与阴影 | 由系统弹出窗口提供（REQ-THEME-025） |

**REQ-W-TOOLTIP-001**　提示框尺寸：内容宽 = 文本在 `wrap = .word`、可用宽度 `tooltip_max_w − 2 × pad_tooltip_x` 下排版的最宽行宽，窗口宽 = 内容宽 + `2 × pad_tooltip_x`（不超过 `tooltip_max_w`）；窗口高 = 行数 × 行高 + `2 × pad_tooltip_y`。文本中的 `\n` 是硬换行；无空格的超长串在字素簇边界强制断行（REQ-TEXT-016）；制表符按 05 展开。内容高度超过锚点所在显示器工作区高度时，以 `max_lines` 截断并在末行加省略号（REQ-TEXT-015）。提示框不可滚动。

**REQ-W-TOOLTIP-002**　内容**仅文本**：主文本，加可选的快捷键提示——`opts.shortcut_text` 非空时在主文本之后追加一个空格与 `(` + 快捷键文本 + `)`（与 REQ-APP-025 的"标题（快捷键）"格式一致），追加部分以 `text_secondary` 着色。文本为空串（且无快捷键文本）时**不显示**提示框。文本被框架复制（`ui.tooltip` 的所有权约定，REQ-INPUT-057 接口），调用方的切片只需借用至本帧结束。不解析助记符、不支持图标与富文本。

**REQ-W-TOOLTIP-003**　**指针触发**的位置由 `ui.tooltip`（08，REQ-INPUT-057）给出：提示框以显示时指针的静止点为准，**上缘在指针热点下方 `tooltip_offset_y` 处、左缘与指针同 x**（等价于锚矩形 (指针 x, 指针 y, 1, `tooltip_offset_y`)、`placement = { below, start }`、间距 0；宿主根 lpx）。越界处理由 `placeAnchored` 完成（REQ-LAYOUT-043）：下方放不下时翻转到锚矩形上方（提示框底边落在指针 y 处），左右超出工作区时平移夹紧到工作区内，边界取指针所在显示器的工作区（REQ-LAYOUT-044）。提示框显示后**不**随指针移动（静止在原位）。控件**不**自行以 `beginPopup` 声明提示框。

**REQ-W-TOOLTIP-004**　**键盘触发**的位置同样由 `ui.tooltip` 给出（REQ-INPUT-057）：提示框位于所属控件矩形**下方**、左缘与控件左缘对齐，间距 `gap_xs`，放不下时翻到控件上方，其余同指针触发。

## 4. 变体与参数

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `shortcut_text` | `?[]const u8` | `null` | 快捷键提示，格式见 REQ-APP-029（如 `Ctrl+S`）；框架复制 |
| `enabled` | `bool` | `true` | 为假时不显示（等同未声明） |
| `key`、`debug_name`、`layout` | 通用 | | `layout` 被忽略（提示框是弹出层，不参与布局）；`debug_name` 用于回放定位弹出根 |

提示框没有外观变体。

**REQ-W-TOOLTIP-005**　`w.tooltip(ui, src, owner, text, opts)` 在构建中为节点 `owner`（须为本次构建中已声明的节点）登记提示框：全部经 `ui.tooltip(owner, text)`（08；它同时覆盖指针悬停路径与键盘焦点路径，REQ-W-TOOLTIP-012）；两条路径显示的是同一个提示框，**同一时刻整个窗口至多一个提示框**（后触发者替换前者）；同一帧内对同一 `owner` 重复调用时以第一次为准（调试构建记录一条 `warn`）。每次构建都须调用（与 `ui.tooltip` 一致，不调用即视为该节点无提示）。`owner` 为禁用节点时提示框**仍然显示**（禁用节点可被命中以支持提示框，REQ-INPUT-009）。

## 5. 状态

### 5.1 状态机

状态变量：`state ∈ {空闲, 计时中, 显示, 抑制}`；`source ∈ {指针, 键盘}`；`rest`（指针静止点与时间）。

| 当前 | 事件 | 条件 | 下一状态 | 动作 |
|---|---|---|---|---|
| 空闲 | 悬停目标变为带提示的 `owner` | 满足显示前提（REQ-W-TOOLTIP-006） | 计时中（指针） | 记静止点，登记 `build` 级定时器，延迟取 REQ-W-TOOLTIP-006/REQ-W-TOOLTIP-007 |
| 计时中（指针） | 指针离开以静止点为中心的 `hover_size` 矩形 | 仍在 `owner` 内 | 计时中 | 以新位置为静止点重新计时 |
| 计时中（指针） | 指针离开 `owner` / 任一 `key_down`、`pointer_down`、`wheel` / 前提不再满足 | — | 空闲 | 取消定时器 |
| 计时中（指针） | 定时器到期 | 前提仍满足 | 显示 | 声明弹出层，位置按 REQ-W-TOOLTIP-003 |
| 空闲 | `owner` 获得焦点且焦点可见 | `owner` 有提示 | 计时中（键盘） | 登记 `build` 级定时器，延迟取 `hover_time_ms` |
| 计时中（键盘） | 到期 | 焦点仍在 `owner` 且无按键 | 显示 | 位置按 REQ-W-TOOLTIP-004 |
| 计时中（键盘） | 焦点离开 / 任一 `key_down` / `pointer_down` | — | 空闲 | 取消 |
| 显示 | 任一 `key_down`、`wheel`、`pointer_down` | — | 抑制 | 关闭 |
| 显示 | 指针离开 `hover_size` 矩形（指针路径）/ 悬停目标改变 | — | 空闲 | 关闭 |
| 显示 | 显示满 `10 × hover_time_ms`（读取系统度量） | — | 抑制 | 关闭 |
| 显示 | 窗口失去激活 / 非提示框弹出层打开 / `owner` 消失或被禁用以外的失格 | — | 空闲 | 关闭 |
| 抑制 | 指针离开 `owner`（悬停目标改变） / 焦点离开 `owner` | — | 空闲 | — |

### 5.2 视觉表现

| 状态 | 绘制（基元 + 令牌） |
|---|---|
| 显示 | `drawPopupFrame(R, true)`；主文本 `text_primary`，快捷键提示 `text_secondary`；`font_body` |
| 出现动画 | 系统菜单淡入开启时 `dur_fast` 透明度淡入，否则瞬时（REQ-W-TOOLTIP-014） |
| 消失 | 瞬时 |

## 6. 鼠标行为

**REQ-W-TOOLTIP-006**　**出现延迟与前提**：读取系统度量 `SystemMetrics.hover_time_ms`（`SPI_GETMOUSEHOVERTIME`，03）、`hover_size`（`SPI_GETMOUSEHOVERWIDTH/HEIGHT`）。指针路径要求同时满足：`owner` 被连续悬停达到延迟（经 `ui.hoverFor(owner, .tooltip)`，REQ-INPUT-056）；期间指针一直位于以其静止点为中心、宽高为 `hover_size` 的矩形内（**指针在悬停矩形内静止才计时**，离开该矩形则以新位置重新计时）；无指针捕获；窗口处于激活状态；弹出栈中无非提示框弹出层；无按键按下；文本非空。不满足任一项则不出现。未到期期间无轮询（定时器到期唤醒）。

**REQ-W-TOOLTIP-007**　**相邻控件缩短延迟**：已有提示框显示、或刚在 `hover_time_ms / 5` 时间内消失时，指针移入另一个带提示的 `owner`，延迟缩短为 `hover_time_ms / 5`（默认 400 ms 时为 80 ms）。该比例取自 08 的 REQ-INPUT-057，倾向保持并在真实 Windows 上复核（见 OPEN-W-TOOLTIP-02）。除此之外无"曾经显示过"的记忆：指针离开提示区域超过该时间后再进入，按完整延迟计。

**REQ-W-TOOLTIP-008**　**消失条件**（任一）：任一 `key_down`（含单独的修饰键与自动重复）、任一 `wheel`、任一 `pointer_down`（任意键）、指针离开静止点的 `hover_size` 矩形或悬停目标改变、窗口失去激活、非提示框弹出层打开（弹出栈非空）、显示满自动消失时间（REQ-W-TOOLTIP-009）、`owner` 在新树中消失或其提示文本变空；键盘路径另在焦点离开 `owner` 时消失，且**不**因指针移动而消失（指针移动只影响指针路径）。消失一律瞬时。因按键、滚轮、按下而消失后进入抑制（REQ-W-TOOLTIP-010）。

**REQ-W-TOOLTIP-009**　**自动消失时间** = `10 × hover_time_ms`（读取系统度量，默认 400 ms 时为 4000 ms，取自 08 的 REQ-INPUT-057；见 OPEN-W-TOOLTIP-02）。到期时关闭并进入抑制，不会在原地重新出现。

**REQ-W-TOOLTIP-010**　**抑制**：因按键、滚轮、按下、自动消失而消失后，同一 `owner` 的提示框在指针离开该 `owner`（悬停目标改变）再重新进入之前**不再出现**；因"指针离开 `hover_size` 矩形但仍在 `owner` 内"而消失的，从新的静止点重新计时（可再次出现）。键盘路径的抑制在焦点离开 `owner` 时解除。

**REQ-W-TOOLTIP-011**　提示框**不可命中**：平台层对其 `WM_NCHITTEST` 返回 `HTTRANSPARENT`（REQ-PLAT-068），框架命中测试把它当作不存在（REQ-INPUT-010），指针在其上时悬停与点击作用于其下方的节点；不取得窗口激活、不取得焦点、**不进入弹出栈**、不参与轻关闭（`light_dismiss = false`）、不抢占键盘（`keyboard = passive`）、Esc 不关闭它（`close_on_escape = false`，它的消失由 REQ-W-TOOLTIP-008 管理）。指针形状不由提示框声明。

## 7. 键盘行为

提示框**不处理任何键**，也不可聚焦；键盘只影响其显示：任何 `key_down` 都使其消失（REQ-W-TOOLTIP-008），键盘焦点获得（焦点可见）时可触发它。

| 键 | 行为 |
|---|---|
| 任一键 | 若提示框显示或计时中：消失/取消，进入抑制；该键照常按 08 的八级路由处理（提示框不消费键） |
| Tab / 方向键等使焦点可见地进入带提示的控件 | 触发键盘路径的计时（REQ-W-TOOLTIP-012） |

**REQ-W-TOOLTIP-012**　**键盘焦点触发**由 `ui.tooltip` 的键盘触发提供（REQ-INPUT-057）：带提示的 `owner` 获得焦点且焦点可见（`Interaction.focus_visible`，即由键盘导航、助记符或程序设置使焦点可见，REQ-INPUT-040）时，在**该次获得焦点之后**连续经过 `hover_time_ms` 且期间无任何 `key_down`、焦点未离开、窗口激活、弹出栈为空时显示提示框，位置按 REQ-W-TOOLTIP-004；显示后任一 `key_down` 使其消失并进入抑制，同一次焦点持有期内不再出现。鼠标点击获得焦点（焦点不可见）**不**触发键盘路径。`owner` 同时被指针悬停时只有一个提示框（以先满足条件者为准）。

## 8. 焦点

提示框不可聚焦、不是 Tab 停靠，不改变宿主焦点节点与窗口激活（REQ-INPUT-055）；它的出现与消失不产生 `focus_gained`/`focus_lost`。

**REQ-W-TOOLTIP-013**　提示框的打开与关闭**不得**改变宿主的焦点节点、`focus_visible` 状态或窗口激活状态；提示框显示期间宿主窗口的 `window_active` 保持为真。

## 9. 文本与输入法

仅显示文本，不接受输入，输入法处于所在焦点节点的状态（提示框不改变）。文本中的非法 UTF-8 按 REQ-TEXT-003 显示；空串不显示（REQ-W-TOOLTIP-002）。文本在提示框显示期间变化（应用改了 `text`）：就地更新内容并按新尺寸重新定位（仍以原锚点），不重新计时。

## 10. 动效

| 属性 | 触发 | 时长令牌 | 缓动 | 影响级别 |
|---|---|---|---|---|
| 提示框透明度 | 出现 | 系统菜单淡入开启时 `dur_fast`，否则无 | `ease_out` | paint |
| 消失 | 任一 | 无（瞬时） | — | — |

**REQ-W-TOOLTIP-014**　出现动画完全遵循系统设置（REQ-THEME-020）：`menu_animation`、`menu_fade`、`client_animation` 均为真时，弹出窗口内容以 `dur_fast` 透明度淡入（`paint` 级，窗口位置与尺寸不变）；否则一帧内完整出现。消失一律瞬时。

## 11. 无障碍

| 项 | 值 |
|---|---|
| UIA 控件类型 | ToolTip |
| 名称来源 | 提示文本（含快捷键提示） |
| 支持的模式 | 无 |
| 状态属性 | IsOffscreen（假）；通过 `ToolTipOpened`/`ToolTipClosed` 事件通知 |

**REQ-W-TOOLTIP-015**　提示框显示时向 UIA 发出以 `owner` 为源的 `ToolTipOpened` 事件，消失时发出 `ToolTipClosed`；ToolTip 元素的 Name 为完整提示文本。提示文本**不得**是 `owner` 唯一的无障碍名称来源（`owner` 须有自己的 Name，REQ-THEME-006）；`owner` 的 `HelpText` 不重复该文本。

## 12. API 草案

```zig
// 草案：仅签名
pub const TooltipOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,      // 用于回放定位弹出根（`@名字`）
    enabled: bool = true,
    shortcut_text: ?[]const u8 = null,   // 借用至本帧结束；框架复制
    layout: layout.ItemOptions = .{},    // 被忽略：提示框不参与布局，保留字段以与其他控件选项一致
};

pub const TooltipResult = struct {
    shown: bool,    // 提示框当前是否显示（持续性状态）
    // 无激活类结果
};

/// 为节点 owner 登记提示框。text 借用至本帧结束（框架复制）。每次构建都需调用。
pub fn tooltip(ui: *Ui, src: std.builtin.SourceLocation, owner: WidgetId, text: []const u8, opts: TooltipOptions) TooltipResult;
/// 溢出省略文本的提示：仅在将要显示的时刻文本被截断才显示（08 的 ui.tooltipIfTruncated）。
pub fn tooltipIfTruncated(ui: *Ui, src: std.builtin.SourceLocation, owner: WidgetId, text: []const u8, style: text.Style, opts: TooltipOptions) TooltipResult;
```

底层的 `ui.tooltip(owner, text)` 与 `ui.tooltipIfTruncated`（08，含键盘触发）由本函数使用。`TooltipResult` 只有持续性状态，没有触发第二构建遍的结果。

## 13. 保留状态

| 字段 | 类型 | 保留级别 | 说明 |
|---|---|---|---|
| `state`、`source` | 枚举 | transient | 随 `owner` 的提示登记存活 |
| `rest` | `{pos, since_ms}` | transient | 指针静止点与时刻 |
| `shown_at_ms` | `u64` | transient | 显示起点（用于自动消失与"刚消失"判定） |
| `last_hidden_ms` | `u64` | transient（属于整个 `Ui`，不属于某个 `owner`） | 用于相邻控件缩短延迟 |
| `suppressed` | `bool` | transient | REQ-W-TOOLTIP-010 |
| 文本副本 | 框架拥有的字符串 | transient | 框架复制 |

悬停时长由 `ui.hoverFor` 的框架内建计时维护。

## 14. 失效规则

**REQ-W-TOOLTIP-016**　提示框弹出根的绘制键**必须**由文本内容（含快捷键提示）、排版宽度、淡入进度是否完成构成；布局输入的内容度量键由文本内容、字体样式与最大宽度构成。

| 变化 | 置脏级别 | 损伤范围 |
|---|---|---|
| 出现/消失（定时器到期、按键、按下、滚轮等） | `build`（弹出根被声明/不再声明） | 仅提示框弹出窗口；宿主窗口损伤为空 |
| 淡入动画推进 | `paint` | 仅提示框弹出窗口 |
| 提示文本变化 | `build` | 仅提示框弹出窗口（尺寸变化时重新定位） |

**REQ-W-TOOLTIP-017**　提示框的出现、消失与淡入**不得**造成宿主窗口的任何损伤与绘制（宿主 `Ui` 的损伤为空）；悬停计时的定时器只在"悬停在带提示的节点上且未到期"期间登记，到期或条件消失即取消，不轮询；提示框显示期间无其他持续定时器之外无帧（自动消失定时器除外）。

**REQ-W-TOOLTIP-018**　**溢出省略文本的提示**：`w.tooltipIfTruncated(ui, src, owner, text, style, opts)` 经 `ui.tooltipIfTruncated(owner, text, style)`（08）登记提示框：是否显示的判定发生在**将要显示的时刻**，以 `owner` 当前的内容宽度调用 `text.isTruncated(text, style, scale, 内容宽)`，未被截断则不显示（计时与消失规则同 REQ-W-TOOLTIP-006、REQ-W-TOOLTIP-008）；窗口缩放使截断状态改变后无需重新构建即可得到正确结果。内容（全文）、位置、外观同普通提示框。

## 15. 边界与错误情况

| 情况 | 规定 |
|---|---|
| 文本为空串 | 不显示，不计时 |
| `owner` 被禁用 | 照常显示（REQ-INPUT-009） |
| `owner` 在计时或显示期间消失 | 取消/关闭 |
| 提示文本在显示期间改变 | 就地更新并重新定位，不重新计时 |
| 指针静止点贴近屏幕边缘 | 由 Anchor 翻转/夹紧（REQ-W-TOOLTIP-003） |
| 多显示器 | 取指针所在显示器工作区作边界（REQ-LAYOUT-044） |
| 提示框尺寸大于工作区 | 宽度夹紧 `tooltip_max_w`；高度以 `max_lines` 截断并加省略号 |
| 弹出层（菜单、下拉）打开 | 不出现；已显示的提示框在弹出层打开时关闭 |
| 指针捕获进行中（拖动滑块、选择文本） | 不出现；已显示则关闭（`pointer_down`） |
| 窗口非活动 | 不出现；已显示则关闭 |
| 系统悬停时间为 0 或极小 | 延迟取 0，指针到达即出现（仍须满足静止与其他前提）；`10 × 0` 的自动消失视为不消失，由其他条件关闭 |
| 同一时刻多个 `owner` 请求 | 至多一个提示框，后触发者替换前者 |
| 触摸与笔 | 视为鼠标（REQ-INPUT-023），无专门悬停语义 |
| 降级后端（GLFW） | 弹出层退化为宿主窗口内覆盖层（03 降级矩阵），位置与时序规则不变 |

## 16. 验收标准

**夹具 F-TT**（除特别注明外）：无头、`fixed` 文本后端（簇宽 6 px，行高 16 px）、缩放 1.0、窗口 400×300（工作区同窗口，窗口位于屏幕 (0,0)）；`hover_time_ms` = 400、`hover_size` = 4×4 ppx、`menu_animation` = off。按钮 `@A`（(100,100,80,24)，提示 "保存"）、`@B`（(200,100,80,24)，提示 "打开"）、`@D`（(300,100,80,24)，禁用，提示 "不可用"），文本框 `@T`（(100,160,200,24)，无提示）、最底层的整窗面板 `@P`（(0,0,400,300)，登记 `click`、无提示）。Tab 序为 `@T` → `@A` → `@B` → `@T`（`@D` 禁用，跳过）。行高取 `font_body` 的令牌行高 16（REQ-THEME-016），与 fixed 后端的自然行高无关。提示框弹出层矩形取自 `headless.popupRects()`；内边距水平 `pad_tooltip_x` 6、垂直 `pad_tooltip_y` 3，单行高 16 + 6 = 22。回放记号同 text-input.md 第 16 节。

**AC-W-TOOLTIP-001**　`[金图]` 覆盖：REQ-W-TOOLTIP-001、REQ-W-TOOLTIP-002、REQ-W-TOOLTIP-003、REQ-W-TOOLTIP-004、REQ-W-TOOLTIP-014。状态矩阵：提示框 {单行, 主文本加快捷键提示 "保存 (Ctrl+S)"（括号部分 `text_secondary`）, 多行（含 `\n`）, 达最大宽度换行, 无空格超长串强制断行, 翻转到指针上方, 贴右边缘夹紧} × 浅/深/高对比度 × 缩放 1.0/1.5/2.0。预期：与基准图一致；底 `surface_tooltip`、边框 `border_strong`（高对比度映射 REQ-THEME-035）；"保存" 单行矩形尺寸 = (12 + 12) × 22 = 24×22；"保存 (Ctrl+S)"（11 簇）宽 66 + 12 = 78；120 个 "a" 的提示 → 每行 51 簇（可用宽 320 − 12 = 308，308 / 6 取 51）、共 3 行（51、51、18）、矩形 318×54（宽 = 51 × 6 + 12，高 = 3 × 16 + 6）；指针静止点 (150,112) → 矩形左上 (150,132)（112 + `tooltip_offset_y` 20）；静止点在窗口右缘 (390,112) → x 夹紧为 400 − 24 = 376；静止点 (150,290) → 翻到上方，底边 = 290（顶边 290 − 22 = 268）。

**AC-W-TOOLTIP-002**　`[回放]` 覆盖：REQ-W-TOOLTIP-006、REQ-W-TOOLTIP-011、REQ-W-TOOLTIP-013、REQ-W-TOOLTIP-005。`move 150 112`（进入 `@A`，t0）：`advance 399` → `expect popup 0`；`advance 1` → `expect popup 1`，矩形 (150,132,24,22)，`TooltipResult.shown` 真。抖动：`move 150 112`、`advance 300`、`move 151 113`（仍在 4×4 矩形内）、`advance 99` → 无提示框；`advance 1` → 出现（以首个静止点计）；另一次：`move 150 112`、`advance 300`、`move 160 112`（离开 4×4 矩形）、`advance 399` → 无；`advance 1` → 出现（从新静止点重新计时，矩形 (160,132,24,22)）。前提：指针捕获中（在 `@A` 上按下不放）`advance 1000` → 不出现；窗口 `activate off` → 不出现；弹出栈非空（先展开一个菜单）→ 不出现；有按键按下（`key down VK_SHIFT` 未释放）→ 不出现。设 `hover_time_ms` = 100 → 100 ms 后出现；设 `hover_size` 为 20×20 → 在 20×20 内移动不重计时。不可命中的断言见键盘路径的用例（指针路径的提示框位于指针下方，指针无法在不离开静止矩形的前提下进入它）。提示框出现与消失期间 `@A` 的 `expect focus`、窗口激活状态与 `focus_visible` 均不变；`@D`（禁用）悬停 400 ms 后同样出现 "不可用"；文本为 `""` 的提示不出现；同一时刻进入 `@B` 的提示替换 `@A` 的提示（`expect popup 1`）。

**AC-W-TOOLTIP-003**　`[回放]` 覆盖：REQ-W-TOOLTIP-008、REQ-W-TOOLTIP-009、REQ-W-TOOLTIP-010。提示框已显示（`@A` 的 "保存"，t0 出现）：（1）`key down VK_SHIFT` → 立即消失（`expect popup 0`），该键照常路由（焦点可见变真）；之后 `advance 5000` → 不再出现（抑制），把指针移出 `@A` 再移回 `advance 400` → 重新出现。（2）滚轮 1 格 → 消失。（3）任意鼠标键按下 → 消失，不再出现直到离开再进入。（4）指针移到 `@A` 内的 (170,112)（离开原静止点的 4×4 矩形、仍在 `@A` 内）→ 消失，并从新的静止点重新计时，400 ms 后再次出现。（5）指针移到 `@T`（无提示）→ 消失。（6）`activate off` → 消失。（7）显示后 `advance 3999` → 仍显示；`advance 1`（t0 + 4000）→ 消失；其后 `advance 5000` → 不再出现。（8）`hover_time_ms` = 200 → 自动消失在显示后 2000 ms。（9）显示期间展开一个下拉菜单 → 提示框消失；菜单关闭后不自动再出现。（10）`@A` 在显示期间从树中移除 → 提示框在下一次构建关闭。

**AC-W-TOOLTIP-004**　`[回放]` 覆盖：REQ-W-TOOLTIP-007、REQ-W-TOOLTIP-006。`@A` 的提示显示后，指针直接移入 `@B`（`move 220 112`，t1）：`advance 79` → 无提示框；`advance 1`（t1 + 80）→ `@B` 的 "打开" 出现（缩短延迟 400 / 5 = 80 ms）。`@A` 的提示因离开而消失后在 60 ms 内移入 `@B` → 80 ms 延迟；超过 80 ms（如 100 ms）后移入 → 完整 400 ms。`@A` 的提示因按键（抑制）消失后移入 `@B` → 80 ms（"刚消失"）。从未显示过提示时进入 `@B` → 400 ms。设 `hover_time_ms` = 1000 → 缩短延迟为 200 ms。

**AC-W-TOOLTIP-005**　`[回放]` 覆盖：REQ-W-TOOLTIP-012、REQ-W-TOOLTIP-004、REQ-W-TOOLTIP-008、REQ-W-TOOLTIP-010。`@T` 聚焦后按 Tab → `@A` 获得焦点且焦点可见：`advance 399` → 无提示框；`advance 1` → 出现，矩形 (100,126,24,22)（控件下沿 124 + `gap_xs` 2，左缘与控件左缘对齐）。再按任意键（如 Shift）→ 消失，之后 `advance 5000` → 不再出现（同一次焦点持有内抑制）；按 Tab 到 `@B` → 400 ms 后其提示出现（位置 (200,126,24,22)）。鼠标点击 `@A` 获得焦点（焦点不可见）→ 悬停 400 ms 出现的是**指针**路径的提示框（位置 (指针 x, 指针 y + `tooltip_offset_y` 20)；如指针 (150,112) 时为 (150,132)），不是键盘路径；键盘路径不触发。焦点可见的 `@A` 同时被指针悬停 → 至多一个提示框。不可命中：键盘提示框 (100,126,24,22) 显示时 `move 110 135`（落在提示框内）→ 指针移动不使键盘路径的提示框消失，悬停目标为其下方的 `@P`（`expect visual @P hovered true`）；此时 `down left`、`up left` → `@P` `clicked`（点击作用于提示框下方的节点），且该次按下使提示框消失；`expect focus` 与窗口激活状态在提示框出现/消失前后不变。键盘计时期间焦点离开 → 取消。弹出栈非空时键盘路径不触发。

**AC-W-TOOLTIP-006**　`[回放]` 覆盖：REQ-W-TOOLTIP-002、REQ-W-TOOLTIP-001、REQ-W-TOOLTIP-003。提示文本在显示期间由 "保存" 改为 "保存全部"（4 簇）→ 同一帧内矩形变为 (150,132,36,22)（就地更新、不重新计时、`expect popup 1` 不变）；提示 `shortcut_text` = "Ctrl+S" → 文本 "保存 (Ctrl+S)"；`shortcut_text` 为空串时不追加括号；文本含 `\n`（"第一行\n第二行"）→ 2 行，高 16×2 + 6 = 38；制表符展开；超长文本（> 工作区高度所容纳行数）→ 以 `max_lines` 截断并以 `…` 结尾；文本非法 UTF-8 → 显示 U+FFFD。

**AC-W-TOOLTIP-007**　`[回放]` 覆盖：REQ-W-TOOLTIP-014、REQ-W-TOOLTIP-011。`setting menu_animation on`、`menu_fade on`、`client_animation on`：提示框出现首帧透明度 < 1，`advance 80` 后为 1，动画帧构建遍数 0、仅提示窗口损伤；任一设置关闭 → 首帧即完全不透明；消失恒瞬时。降级后端（GLFW 无头）下提示框为宿主窗口内覆盖层：位置与时序断言与上相同。

**AC-W-TOOLTIP-008**　`[单元]` 覆盖：REQ-W-TOOLTIP-015、REQ-W-TOOLTIP-005、REQ-W-TOOLTIP-002、REQ-W-TOOLTIP-018。经假 UIA 入口：提示框出现时产生 `ToolTipOpened`（源为 `@A`），元素类型 ToolTip、Name = "保存 (Ctrl+S)"；消失产生 `ToolTipClosed`；`@A` 自己的 Name 不取自提示文本（图标按钮缺少名称时调试构建 1 条 `warn`，仅检查 API 契约）；`opts.enabled = false` 时不出现；`text = ""` 不出现；同一帧对同一 `owner` 重复调用 `w.tooltip` → 以第一次为准（调试构建 1 条 `warn`）。`w.tooltipIfTruncated`：按钮宽度足以容纳 "保存全部更改" 时悬停 400 ms → 不显示；把宽度压到 40 lpx（截断）后无需重建、悬停 400 ms → 显示完整文字；缩放窗口使其再次容纳 → 不显示。

**AC-W-TOOLTIP-009**　`[计量]` 覆盖：REQ-W-TOOLTIP-016、REQ-W-TOOLTIP-017。界面含 100 个按钮，每个带提示，指针从空白处依次移入 `@A` 并静置 400 ms：悬停进入帧的构建遍数 0；提示框出现的帧宿主窗口损伤为空、弹出窗口损伤 = 其整个矩形；静置期间（计时中）`expect timers 1`、帧数 0；提示框显示期间再静置至自动消失，除自动消失时刻外帧数 0；淡入动画帧构建遍数 0；以相同参数再次 `invalidate(.build)` → 宿主损伤为空；仅改变提示文本 → 损伤仅为提示窗口。

**AC-W-TOOLTIP-010**　`[人工]` 覆盖：REQ-W-TOOLTIP-006、REQ-W-TOOLTIP-007、REQ-W-TOOLTIP-009、REQ-W-TOOLTIP-003、REQ-W-TOOLTIP-012、REQ-W-TOOLTIP-014。真实 Windows 10 与 11：把"鼠标属性 → 指针停留时间"注册表值改为 200 与 1000 ms，确认出现延迟随之变化；与资源管理器工具栏提示对照出现位置（指针下方偏移）、相邻按钮间的再显示延迟与自动消失时长，记录差异；屏幕底部/右侧、多显示器与 125%/150% 缩放下的翻转与夹紧；提示框不抢走窗口激活（标题栏保持活动色），鼠标可穿透其到下方控件；键盘 Tab 到图标按钮后提示框出现，按任意键消失；Narrator 在提示框出现时朗读其内容。

## 17. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-W-TOOLTIP-02 | 再显示延迟取 `hover_time_ms / 5`、自动消失取 `10 × hover_time_ms` 是经验比例（08 的 OPEN-INPUT-06） | 倾向保持；在真实 Windows 上对照资源管理器与记事本工具栏后复核（Windows 默认为初始 500 ms、再显示 100 ms、自动消失 5000 ms） |
| OPEN-W-TOOLTIP-05 | 触摸与笔没有悬停，无法触发提示框 | 不处理（REQ-VIS-008）；关键信息不得只放在提示框里 |
| OPEN-W-TOOLTIP-06 | 提示框是否应在指针移动较小距离时跟随 | 不跟随（Windows 默认行为）；保持 |
| OPEN-W-TOOLTIP-07 | 键盘路径与 `hover_time_ms` 共用延迟（原生键盘焦点提示通常更短或无延迟） | 倾向保持共用；实机评估后可单独调整 |
| OPEN-W-TOOLTIP-08 | 其他控件的被截断文字提示 | 已有 `ui.tooltipIfTruncated`（08）与本控件的 `w.tooltipIfTruncated`（REQ-W-TOOLTIP-018）；各控件按 REQ-THEME-018 调用 |
