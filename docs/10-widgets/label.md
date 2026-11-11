# 标签（label）

## 1. 用途

显示一段不可编辑的静态文字，可选前置图标；另有两个结构性扩展：**链接变体**（可点击、可聚焦，用于导航到别处或触发低强调的动作）与**助记符关联**（让 Alt+字母把焦点移到相邻的某个控件，如输入框的自带标签）。参照 Windows 的 Static（`SS_LEFT`）、`SysLink` 与对话框中标签的助记符行为。

- 触发一个动作 → 用 button；链接只用于"去别处"或行内的低强调动作。
- 文字需要被选择或复制 → 用只读的文本框（text-box，`read_only`），本控件的文字**不可选择**。
- 勾选框、单选框、开关自带标签，不需要另放 label。
- 多行富文本、行内混排不同样式 → 不支持；用多个 label 在 Row 中组合。

## 2. 解剖

```
        ┌─ 焦点环（仅链接变体、焦点可见时，位于布局矩形之外）
 [图标] 文字(助记符下划线)           ← 容器 = 布局矩形，无背景、无边框
  └ gap_sm ┘
 链接变体：文字全程带下划线
```

- **图标**（可选）：位于文字之前，边长 `icon_sm`。
- **文字**：单行（默认）或自动换行。可含一个助记符。
- 标签没有容器填充与边框；它不是可交互元素（链接变体除外，其"边界"是焦点环与下划线）。

## 3. 度量与布局

| 项 | 取值（令牌） |
|---|---|
| 高度（单行） | 所用文字样式的行高（`font_*` 的行高列）；有图标时取 `max(行高, icon_sm)` |
| 高度（换行） | 由宽度定后求高度（REQ-LAYOUT-027），行数 × 行高 |
| 最小宽度 | 0（单行时可被收缩直至只剩省略号） |
| 内边距 | 无 |
| 图标尺寸 / 图标与文字间距 | `icon_sm` / `gap_sm` |
| 文字样式 | `font_body`（默认）、`font_body_strong`、`font_small`、`font_title`、`font_mono` 五选一 |
| 绘制外延 | 链接变体：`focus_ring_w`；其余 0 |

**REQ-W-LABEL-001**　默认尺寸策略：水平方向 `fit_shrink`（单行与换行均然，使其在容器收窄时先于其他控件让出宽度），垂直方向 `fit`（单行为行高，换行为 height-for-width 的结果）。该默认按物理方向（宽/高）给出，由控件按 `ui.parentAxis()`（07：当前最内层容器的主轴，Row 为水平、Column 为垂直）映射到 `layout.ItemOptions` 的主轴/交叉轴：`parentAxis` 为水平时水平方向是主轴，取 `fit_shrink`；为垂直时水平方向是交叉轴，取 `fill`（交叉轴没有 `fit_shrink`）。调用方**可以**经通用布局选项覆盖。

**REQ-W-LABEL-002**　单行适应内容时的期望宽度 = `图标宽 + (图标与文字并存时 gap_sm) + 文字宽`，文字宽为去除助记符标记后的文本以所用样式测得的宽度（`text.measure`，`newlines = .as_space`）。换算到物理像素按 REQ-LAYOUT-014。

**REQ-W-LABEL-003**　单行模式下文字中的换行符与制表符按 `newlines = .as_space` 处理为空格；可用宽度小于期望宽度时，文字以尾部省略号截断（REQ-THEME-018、REQ-TEXT-015），图标不缩小；可用宽度不足一个字符加省略号时只显示图标（若有）或只显示省略号。标签**不得**裁出半个字形，也**不得**渐隐。

**REQ-W-LABEL-004**　文字被截断时，标签**必须**在悬停时以提示框显示完整文字（去除助记符标记）；调用方给出 `tooltip` 时显示调用方的文本，且无论是否截断都显示。未截断且无 `tooltip` 时**不得**出现提示框。截断提示经 `ui.tooltipIfTruncated(自身 ID, 完整文字, 样式)` 声明：框架在提示框将要显示的时刻以该节点当前的内容宽度调用 `text.isTruncated` 判定，未截断则不显示（REQ-INPUT-057 的补充规则），因此窗口缩放后无需重建即可得到正确结果。`LabelResult.truncated` 仅是基于最近一次布局（`ui.lastRect`）的参考值，首次出现时为假。

**REQ-W-LABEL-005**　换行模式（`wrap = .word`）：文字按 REQ-TEXT-016 的词界规则折行，硬换行（`\n` 等）保留为换行；高度经 `Content.hfw` 回调一次求得。`max_lines` 非空时超出的内容以省略号结束于第 `max_lines` 行（REQ-TEXT-015 第 6 条），并按 REQ-W-LABEL-004 提供完整文字的提示框。`max_lines` 为空时不截断、不产生省略号。

**REQ-W-LABEL-006**　`text_align`（`left`/`center`/`right`）作用于每一行在标签宽度内的对齐（REQ-TEXT-017）。标签宽度大于文字宽度时（如在 `fill` 下），对齐决定文字在标签内的位置；图标始终紧邻文字之前，随文字块一起对齐。

## 4. 变体与参数

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `style` | `enum { body, body_strong, small, title, mono }` | `body` | 文字样式，一一对应 09 的 `font_*` 令牌；不允许逐实例指定字号字重 |
| `color` | `enum { primary, secondary, disabled, danger, warning, success, info }` | `primary` | 颜色角色，见 5.2；`danger/warning/success/info` 为状态色，须配图标（REQ-W-LABEL-009）；对链接变体无效（链接恒为 `accent_text`） |
| `variant` | `enum { text, link }` | `text` | `link`：链接变体 |
| `wrap` | `enum { none, word }` | `none` | 单行（省略）或自动换行 |
| `max_lines` | `?u32` | `null` | 仅 `wrap = .word` 有意义；非空时限制行数并省略 |
| `text_align` | `text.Align` | `left` | 行内对齐 |
| `icon` | `?theme.Icon` | `null` | 前置图标 |
| `tooltip` | `?[]const u8` | `null` | 提示文本；链接变体常用于显示目标地址 |
| `for_id` | `?WidgetId` | `null` | 助记符关联目标，见 REQ-W-LABEL-014；仅 `variant = .text` 有意义 |
| `enabled` | `bool` | `true` | 为假时一律按 `color = .disabled` 绘制，链接变体同时失去交互 |
| `key`、`debug_name`、`layout` | 通用 | | 见模板 |

## 5. 状态

### 5.1 状态机

文字变体（`variant = .text`）没有交互状态。以下状态机仅适用于链接变体；状态变量 `armed ∈ {无, 鼠标, 空格}`，悬停、聚焦、禁用由框架维护（08）。

| 当前 `armed` | 事件 | 条件 | 下一 `armed` | 动作 |
|---|---|---|---|---|
| 无 | 左键按下于链接内 | 启用 | 鼠标 | 隐式捕获（REQ-INPUT-013） |
| 鼠标 | 左键释放 | 指针在命中范围内 | 无 | 报告 `clicked` |
| 鼠标 | 左键释放 | 指针在范围外 | 无 | 无 |
| 鼠标 | 捕获被取消（REQ-INPUT-024） | — | 无 | 无 |
| 无 | Space 按下 | 持有焦点，非自动重复 | 空格 | 无 |
| 空格 | Space 释放 | 仍持有焦点 | 无 | 报告 `clicked` |
| 空格 | Esc 按下 / 失去焦点 / 变为禁用 | — | 无 | 无（取消） |
| 无 | Enter 按下 | 持有焦点，非自动重复 | 无 | 报告 `clicked` |
| 无 | 助记符激活 | 启用，链接文字含助记符 | 无 | 报告 `clicked`（`activated = .mnemonic`） |
| 鼠标 | Space/Enter 按下 | — | 鼠标 | 忽略 |
| 空格 | 左键按下于链接内 | — | 空格 | 忽略 |

### 5.2 视觉表现

"显示为按下" = 链接 `armed = 鼠标` 且指针在命中范围内，或 `armed = 空格`。

| 状态 | 绘制（基元 + 令牌） |
|---|---|
| 文字变体 | 文字与图标按 `color`：`primary` → `text_primary`；`secondary` → `text_secondary`；`disabled` → `text_disabled`；`danger/warning/success/info` → `status_danger/status_warning/status_success/status_info`。图标以同一颜色着色（REQ-THEME-033） |
| 链接·常态 | 文字与图标 `accent_text`，文字下方一条发丝线下划线（颜色同文字，位于基线下 1 个发丝线宽处，多行时每行各一条） |
| 链接·悬停 | 外观同常态（悬停的区分靠手形指针，不靠颜色，避免对比度不足） |
| 链接·显示为按下 | 文字、图标与下划线换 `text_primary`；`dur_instant` 进入，`dur_fast` 退出 |
| 链接·焦点可见 | 加 `drawFocusRing(布局矩形, radius_control)` |
| 禁用（两种变体） | 文字、图标 `text_disabled`；链接的下划线保留（形状区分，REQ-THEME-006）；指针为箭头 |
| 助记符下划线 | 显示时在助记字符下画一条发丝线，颜色同文字（REQ-INPUT-047） |

## 6. 鼠标行为

**REQ-W-LABEL-007**　文字变体**不得**响应任何鼠标输入：不登记 `click`/`drag`/`context`，不取得焦点，不产生 I 形指针，不提供选择、复制或上下文菜单。左键、右键、双击、拖拽在其上发生时按未命中该标签处理（沿祖先冒泡）；滚轮按 REQ-INPUT-019 冒泡。仅当存在 `tooltip`，或为单行（`wrap = .none`，可能被截断，REQ-W-LABEL-004）时，才登记 `hover` 兴趣以显示提示框，且置 `hover_visual = false`（悬停变化不置脏，REQ-FRAME-037），此时指针形状仍为箭头；换行且无 `tooltip` 的标签（`max_lines` 为空时不会被截断）不登记任何指针兴趣。

**REQ-W-LABEL-008**　链接变体登记指针兴趣 `click`。左键按下时进入 `armed = 鼠标` 并立即显示为按下（`dur_instant`）；指针移出命中范围时恢复非按下外观，移回时再次显示为按下；`clicked` **必须**在左键释放的那一帧报告，且仅当释放时指针位于命中范围内。命中范围是标签的布局矩形（含图标，不含焦点环外延）。快速连续点击每次都报告 `clicked`，不区分单击与双击。

**REQ-W-LABEL-009**　使用状态色（`danger/warning/success/info`）的标签**必须**同时提供 `icon`，使状态不只靠颜色区分（REQ-THEME-006）；缺失时调试构建记录一条 `warn`，发布构建照常绘制。状态图标**应当**取 `info`、`warning`、`error`、`success` 标记，颜色同文字。

**REQ-W-LABEL-010**　链接变体的右键、中键按下与释放不改变状态、不报告 `clicked`，无上下文菜单；滚轮冒泡。指针形状：启用的链接为手形（REQ-THEME-032），禁用的链接与文字变体恒为箭头。鼠标点击链接使其获得焦点但不使焦点可见（REQ-INPUT-022、REQ-INPUT-040）。

## 7. 键盘行为

链接变体的键位（文字变体不处理任何键）：

| 键 | 行为 |
|---|---|
| Space | 按下时进入 `armed = 空格` 并显示为按下；释放时报告 `clicked` |
| Enter | 持有焦点时，按下即报告 `clicked`；自动重复忽略 |
| Esc | 仅 `armed = 空格` 的构建声明处理：取消，且该 Esc 不再向后传递；其余时候不声明，Esc 照常到达取消按钮 |
| Alt+助记字符 | 链接文字含助记符时，报告 `clicked`，焦点移到该链接并可见 |
| Tab / Shift+Tab | 不处理（08 的导航规则） |

**REQ-W-LABEL-011**　链接的 Space 激活在**释放**时发生，Space 自动重复被忽略；`armed = 空格` 期间焦点离开、窗口失活或链接变为禁用时**必须**取消，不报告 `clicked`。Enter 的激活在**按下**时发生，自动重复被忽略。链接经 `InteractOpts.handles` 声明处理 Space 与 Enter（⑤ 级，不预占），命令快捷键优先；Esc 仅在 `armed = 空格` 的那些构建中加入 `handles`，其余构建**不**声明 Esc，使 Esc 照常到达所在范围的取消按钮（REQ-INPUT-034）。

**REQ-W-LABEL-012**　持有焦点的链接对 Enter 的响应优先于所在焦点范围的默认按钮（同 REQ-W-BUTTON-016 的规则）：焦点在链接上时，Enter 触发该链接而不是默认按钮。

**REQ-W-LABEL-013**　助记符语法与下划线显示遵循 REQ-INPUT-046、REQ-INPUT-047：`&x` 标记助记字符，`&&` 显示字面量 `&`；显示文本**必须**使用去掉 `&` 的结果。助记符的登记按下列三种情形，禁用的标签不登记：
- 文字变体且 `for_id` 非空：`ui.mnemonic(for_id, ch, .focus)`，登记在**目标**节点上（REQ-W-LABEL-014）。
- 文字变体且 `for_id` 为空：`ui.mnemonic(自身 ID, ch, .focus_next)`（REQ-W-LABEL-015）。
- 链接变体：`ui.mnemonic(自身 ID, ch, .activate)`。

## 8. 焦点

**REQ-W-LABEL-014**　**助记符关联**：`for_id` 指向另一控件时，Alt+助记字符把键盘焦点移到该控件，焦点变为可见（原因 `mnemonic`），**不**触发目标的激活（`MnemonicAction.focus`，REQ-INPUT-048）。目标不存在、被隐藏或被禁用时，助记符不生效（按 REQ-INPUT-048 视为未登记，继续后级路由）。`for_id` 由应用以 `ui.id(src, key)` 取得：应用把同一个 `SourceLocation` 值（及 `key`）既传给 `ui.id` 又传给目标控件，使两处得到同一 ID（06，REQ-FRAME-001）。同一 Alt+字符对应多个匹配节点时按 REQ-INPUT-048 轮转焦点。标签自身不可聚焦。

**REQ-W-LABEL-015**　文字变体含助记符且 `for_id` 为空时，登记 `focus_next`：焦点移到先序上其后第一个可聚焦节点（REQ-INPUT-048）。该形式用于"标签紧挨在控件之前声明"的场景；`for_id` 非空时一律以 `for_id` 为准。

**REQ-W-LABEL-016**　文字变体**不可聚焦**、不在 Tab 序内、不参与组导航。链接变体可聚焦且为 Tab 停靠（`tab_stop = true`）；焦点环仅在焦点可见时绘制（REQ-INPUT-040、REQ-THEME-023）；获得、失去焦点不产生激活类结果。链接位于漫游焦点组内时（如工具栏）遵循该组的规则（REQ-INPUT-038）。

## 9. 文本与输入法

显示文本，不接受文本输入；聚焦（链接）时输入法处于禁用状态（未声明 `text_input`，REQ-INPUT-062 的反面）。省略与提示规则见 REQ-W-LABEL-003 至 REQ-W-LABEL-005。

**REQ-W-LABEL-017**　空字符串且无图标时，调试构建断言，发布构建显示一个宽度为 0、高度为行高的空标签。文字超过 `max_layout_bytes`（REQ-TEXT-005）时按该条截取。非法 UTF-8 按 REQ-TEXT-003 显示。文字中的双向控制字符与 RTL 片段按 REQ-TEXT-041 显示，`text_align = .left` 不因此改变。

## 10. 动效

| 属性 | 触发 | 时长令牌 | 缓动 | 影响级别（paint/build） |
|---|---|---|---|---|
| 链接文字色（常态 → 按下） | 显示为按下 | `dur_instant` | — | paint（`Visual.press_t`） |
| 链接文字色（按下 → 常态） | 结束按下 | `dur_fast` | `ease_out` | paint |
| 焦点环 | 焦点变为可见 | `dur_fast` 淡入，消失瞬时 | `ease_out` | paint（`Visual.focus_t`） |

文字变体无动效。标签没有自有动画槽。

## 11. 无障碍

| 项 | 值 |
|---|---|
| UIA 控件类型 | 文字变体：Text；链接变体：Hyperlink |
| 名称来源 | 去除助记符标记的文字；链接无文字时取 `tooltip` |
| 支持的模式 | 文字变体：无；链接变体：Invoke |
| 状态属性 | IsEnabled；链接另有 HasKeyboardFocus、AccessKey（形如 "Alt+L"）；`for_id` 非空时，目标控件的 LabeledBy 指向本标签（目标自身无名称时以本标签文字作为其名称） |

**REQ-W-LABEL-018**　经 UIA Invoke 触发的链接激活**必须**与键盘 Enter 激活等效：在下一帧报告一次 `clicked`。`for_id` 关联**必须**暴露为目标节点的 LabeledBy 关系。文字变体对辅助技术只读，不可聚焦、不可调用。

## 12. API 草案

```zig
// 草案：仅签名
pub const LabelStyle = enum { body, body_strong, small, title, mono };       // 对应 theme.FontToken
pub const LabelColor = enum { primary, secondary, disabled, danger, warning, success, info };
pub const LabelVariant = enum { text, link };
pub const LabelWrap = enum { none, word };

pub const LabelOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    style: LabelStyle = .body,
    color: LabelColor = .primary,
    variant: LabelVariant = .text,
    wrap: LabelWrap = .none,
    max_lines: ?u32 = null,
    text_align: text.Align = .left,
    icon: ?theme.Icon = null,
    tooltip: ?[]const u8 = null,      // 借用至本帧结束；框架在需要显示时复制
    for_id: ?ui.WidgetId = null,      // 仅 variant == .text；由 ui.id(src, key) 取得
    layout: layout.ItemOptions = .{}, // 各控件共用（07）
};

pub const LabelResult = struct {
    // 持续性状态
    hovered: bool,
    pressed: bool,       // 仅链接：即"显示为按下"
    focused: bool,       // 仅链接
    truncated: bool,     // 文字当前是否被省略（基于最近一次布局）
    // 激活类结果（触发同帧第二构建遍，REQ-FRAME-030）；仅链接
    clicked: bool,
    activated: ?input.ActivateSource,
};

/// text 借用至本帧结束；含 `&` 助记符语法（REQ-INPUT-046）。text 为空串时必须提供 icon。
pub fn label(ui: *Ui, src: std.builtin.SourceLocation, text: []const u8, opts: LabelOptions) LabelResult;
```

`clicked` 是激活类结果，为真时触发同帧第二构建遍（REQ-FRAME-030），在第二遍中为假（REQ-FRAME-033）；`hovered`、`pressed`、`focused`、`truncated` 是持续性状态。`text` 与 `tooltip` 由调用方持有，框架不保留。标签不持有任何应用值。

## 13. 保留状态

| 字段 | 类型 | 保留级别 | 说明 |
|---|---|---|---|
| `armed_space` | `bool` | transient | 仅链接：Space 已按下待释放 |

鼠标的 `armed` 即框架的捕获状态；悬停/按下/焦点过渡为框架内建状态（REQ-FRAME-013）。文字变体无状态槽。

## 14. 失效规则

**REQ-W-LABEL-019**　绘制键**必须**由以下各项构成：文字内容、`style`、`color`、`variant`、`wrap`、`max_lines`、`text_align`、`icon`、`enabled`、文字是否被截断。助记符下划线是否显示不进入绘制键：它由绘制函数在绘制时读取，其变化按 REQ-INPUT-047 整窗置 `paint`。布局输入的内容度量键由文字内容、字体样式、`wrap`、`max_lines`、有无图标构成。

| 变化 | 置脏级别 | 损伤范围 |
|---|---|---|
| 链接的悬停进入/离开、显示为按下的变化、焦点环显隐 | `paint` | 标签绘制范围（含外延） |
| 链接的鼠标按下、释放、Space/Enter（进入收件列表） | `build` | 由差分决定；若无外观变化则为空 |
| 文字内容变化且宽度不变 | `build`（由应用的模型通知引起） | 标签矩形 |
| 文字内容变化导致期望宽度或行数变化 | `build` | 新旧矩形及受影响的兄弟 |
| 键盘提示下划线显隐（按下 Alt） | `paint`（整窗，REQ-INPUT-047）；绘制函数读取当前的键盘提示可见性 | 整窗 |

**REQ-W-LABEL-020**　文字变体上的指针移动与悬停变化不置脏、不产生帧（该节点 `hover_visual = false`，仅为提示框登记悬停，REQ-FRAME-037）；悬停进入/离开一个链接所产生的帧**必须**是纯绘制帧（构建遍数 0），且损伤不超出该链接的绘制范围。

## 15. 边界与错误情况

| 情况 | 规定 |
|---|---|
| 空文字且无图标 | 见 REQ-W-LABEL-017 |
| 容器宽度为 0 或负 | 单行：只显示图标或省略号（REQ-W-LABEL-003），仍保留行高；换行：每行至少一个字素簇，不无限循环 |
| 超长文字（单个词长于宽度） | 单行：省略；换行：`wrap = .word` 在无断行机会处按簇强制断行（REQ-TEXT-016） |
| 按下期间链接从树中消失 | 捕获释放（REQ-INPUT-024），不报告 `clicked` |
| 按下期间链接变为禁用 | 取消，不报告 `clicked`；立即显示禁用外观 |
| `for_id` 指向自身或指向不存在的节点 | 助记符不生效；调试构建记录一条 `warn` |
| `variant = .link` 且 `for_id` 非空 | 不支持的组合；调试构建断言，发布构建忽略 `for_id` |
| `color` 为状态色且无 `icon` | 见 REQ-W-LABEL-009 |
| `wrap = .none` 且 `max_lines` 非空 | `max_lines` 被忽略，调试构建记录一条 `warn` |
| 同一帧内同时满足鼠标释放与 Enter | 链接只报告一次 `clicked` |
| 窗口非活动时悬停链接 | 手形与提示框的显示遵循 REQ-INPUT-057；点击先激活窗口，该次点击照常作用于链接 |

## 16. 验收标准

**AC-W-LABEL-001**　`[金图]` 覆盖：REQ-W-LABEL-001、REQ-W-LABEL-002、REQ-W-LABEL-003、REQ-W-LABEL-006。渲染：五种 `style` 的单行标签各一；图标+文字；文字"A\nB\tC"；一个被固定为 40 lpx 宽的长文字标签；`text_align` 三档（标签 `fill` 到 200 lpx）。缩放 1.0/1.5/2.0，浅/深。预期：与基准图一致；布局断言——各样式高度等于对应行高；图标+文字宽度 = `icon_sm + gap_sm + 文字宽`；"A\nB\tC" 渲染为单行且高度不变；40 lpx 标签文字以 `…` 结尾且无半个字形；三档对齐下文字左缘分别位于 0、`floor((W − 文字宽)/2)`、`W − 文字宽`。另在 Row 中并排放置按钮、勾选框与本标签（`cross_align = center`，文字均为"Hxg中"），断言文字基线在同一条物理像素行（REQ-THEME-017）。

**AC-W-LABEL-002**　`[金图]` 覆盖：REQ-W-LABEL-005、REQ-W-LABEL-009。渲染换行标签：宽度 120 lpx 的一段含硬换行的中英文混排文字（`max_lines` 为空）；同一文字 `max_lines = 2`；状态色四种各带对应图标，另一个状态色缺图标的标签（调试构建断言警告计数 +1）。浅/深/高对比度。预期：与基准图一致；`max_lines = 2` 时第二行以 `…` 结尾，最后一个可见字形完整；硬换行处必换行；高度 = 行数 × 行高；四种状态色在灰度化后图标形状仍两两可区分。

**AC-W-LABEL-003**　`[金图]` 覆盖：REQ-W-LABEL-008、REQ-W-LABEL-016。链接变体的状态矩阵：{常态, 悬停, 显示为按下, 焦点可见, 禁用} × {单行, 换行两行}，浅/深/高对比度。预期：与基准图一致；所有状态下文字均带下划线（换行时每行一条）；常态与悬停的像素完全相同（仅指针形状不同）；按下时文字色为 `text_primary`；焦点环仅出现在"焦点可见"列；禁用态用到的颜色集合 ⊆ 禁用令牌 ∪ 表面令牌。

**AC-W-LABEL-004**　`[回放]` 覆盖：REQ-W-LABEL-007、REQ-W-LABEL-016。确认不响应输入。界面含一个文字变体标签（位于可滚动容器内，外层有一个登记了 `click` 的面板）、一个按钮。脚本：在标签上依次左键单击、双击、按下后拖过文字、右键单击、中键单击；按 Tab 五次、按 Space、按 Enter、按 Ctrl+C。预期：标签始终无焦点、`Tab` 序列中不含标签；左键单击被外层面板接收（标签不吞）；拖拽后无选择高亮（金图不变）、剪贴板内容不变；平台层记录的指针形状全程为箭头；滚轮在标签上滚动 → 外层滚动容器偏移变化；上述输入期间标签的绘制节点计数为 0。

**AC-W-LABEL-005**　`[回放]` 覆盖：REQ-W-LABEL-008、REQ-W-LABEL-010。链接：在其内按下左键 → `pressed` 真、`clicked` 假；移出 → `pressed` 假；移回 → 真；释放 → 该帧 `clicked` 真，下一帧假。重复一次但在链接外释放 → 全程 `clicked` 假。以 50 ms 间隔完成 3 次按下–释放 → `clicked` 累计 3。右键、中键各一次 → `clicked` 不变。指针停在启用的链接上记录的指针形状为手形，停在禁用的链接上为箭头。点击链接 → 它持有焦点、金图无焦点环；随后按一次 Shift 键 → 焦点环出现。

**AC-W-LABEL-006**　`[回放]` 覆盖：REQ-W-LABEL-011、REQ-W-LABEL-012。Tab 聚焦链接。`key down Space` → `pressed` 真、`clicked` 假；`key repeat VK_SPACE 5`（注入 5 次自动重复按下）→ 无变化；`key up Space` → `clicked` 真（恰一次）。再次 `key down Space` 后按 Tab → 焦点移走，`key up Space` → `clicked` 假；再次聚焦、`key down Space` 后令 `enabled` 置假 → `pressed` 假、`key up` 后 `clicked` 假；`key down Space` 后 `key down Esc` → 取消，且所在对话框的取消按钮未被触发；未处于按下状态时按 Esc → 所在对话框的取消按钮被触发。Enter：按下 → `clicked` 真；`key repeat VK_RETURN 10` → 累计恰 1 次。对话框含默认按钮 B（`accent`）：焦点在链接上按 Enter → 链接 `clicked`、B 无反应；焦点在文本框时按 Enter → B 触发。

**AC-W-LABEL-007**　`[回放]` 覆盖：REQ-W-LABEL-013、REQ-W-LABEL-014、REQ-W-LABEL-015。三个场景。（一）标签"用户名(&U)"，`for_id` 指向后面的文本框（以同一 `SourceLocation` 取 ID）：系统键盘提示设为"默认隐藏"，初始金图无下划线；按下 Alt → U 下出现下划线；Alt+U → 焦点在文本框、焦点可见、文本框无激活类结果，标签自身未获得焦点。目标被禁用时 Alt+U → 焦点不变。（二）两个标签都以 `&N` 关联到不同控件：Alt+N → 焦点移到先序较前者；再按 Alt+N → 移到另一个；第三次回到第一个。（三）无 `for_id` 的标签"名称(&N)"后紧跟一个文本框：Alt+N → 焦点移到该文本框。另：文字"A && B"显示为"A & B"且未登记助记符；链接文字"打开(&O)"：Alt+O → `clicked` 真且 `activated = .mnemonic`、链接持有焦点。

**AC-W-LABEL-008**　`[回放]` 覆盖：REQ-W-LABEL-004、REQ-W-LABEL-005。固定窄宽导致文字截断的标签：悬停并推进假时钟超过系统悬停时间 → 出现提示框，文本为完整文字（不含 `&`）；窗口失活后提示消失。未截断且无 `tooltip` 的标签同样操作 → 无提示框。给出 `tooltip` 的未截断标签 → 提示框显示调用方文本。截断标签同时给出 `tooltip` → 显示调用方文本。`wrap = .word`、`max_lines = 2` 且被截断的标签 → 提示框显示完整文字；未被截断时无提示框。

**AC-W-LABEL-009**　`[单元]` 覆盖：REQ-W-LABEL-017、REQ-W-LABEL-018、REQ-W-LABEL-009。空文字且无图标 → 调试构建断言中止。文字含字节 0xFF（非法 UTF-8 序列）→ 显示一个 U+FFFD，期望宽度与 `text.measure` 一致。经假 UIA 入口：文字变体 Name 为去除助记符的文字、控件类型 Text、不提供任何模式；链接变体控件类型 Hyperlink，对其 Invoke → 下一帧 `clicked` 真恰一次，AccessKey 为 "Alt+O"；`for_id` 关联的目标控件的 LabeledBy 指向该标签。状态色标签缺图标 → 调试构建产生 1 条 `warn`。

**AC-W-LABEL-010**　`[计量]` 覆盖：REQ-W-LABEL-019、REQ-W-LABEL-020。界面含 100 个标签（其中 10 个为链接）。回放：指针从空白处移入某链接 L 再移出 → 各帧构建遍数均为 0，每帧被绘制的节点集合 ⊆ {L 及其与损伤相交的祖先}，损伤面积 ≤ L 的绘制范围面积。指针移过 90 个文字变体标签（含单行、可能被截断者，均未显示提示框）→ `frame.count` 增量为 0（REQ-FRAME-037：仅为提示框登记悬停的节点悬停变化不置脏）。仅改变某标签的文字内容（宽度不变）并 `invalidate(.build)` → 损伤恰为该标签矩形；以相同内容再次 `invalidate(.build)` → 损伤为空、`frame.presents` 不变。按下 Alt（`SPI_GETKEYBOARDCUES` 为假）→ 构建遍数 0，仅置整窗 `paint`（REQ-INPUT-047），无构建、无布局。

## 17. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-W-LABEL-01 | 是否提供"已访问"链接外观 | 不提供；应用需要时自行换用 `secondary` 色并保留下划线（当前 `color` 对链接变体无效，如需支持再增补） |
| OPEN-W-LABEL-02 | 是否支持文字选择与复制 | 不支持；静态文字需要复制时用只读文本框（`text-box` 规范待写） |
