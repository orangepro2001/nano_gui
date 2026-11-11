# 状态栏（status-bar）

## 1. 用途

窗口底部的一行信息条：显示当前状态文字、光标位置、编码、缩放、后台任务进度等次要信息。它由若干**窗格**并排构成，窗格之间有细分隔线。状态栏是只读的信息区，不可聚焦、不处理输入；窗格中放入的按钮等控件各自独立工作。参照 Windows 的 Status Bar（`msctls_statusbar32`）。

- 需要用户操作的命令 → 放工具栏或菜单；状态栏窗格中的可点击项（如点击切换编码）应使用 quiet 按钮并放入自定义窗格。
- 重要或需要确认的提示 → 用对话框，不要只放在状态栏。
- 窗口缩放由系统边框负责，状态栏**不画**右下角的尺寸手柄。

## 2. 解剖

```
 ───────────────────────────────────────────────────────────────────    ← 顶边：结构性分隔线 drawSeparator(structural)
 │ 就绪                      │ 行 12，列 5 │ UTF-8 │ [▓▓▓░░░░░] 42% │    ← 窗格 + 窗格间细分隔线
 └ 伸展窗格（吸收剩余宽度）    ┘ 适应内容    ┘ 固定宽 ┘ 自定义窗格（含进度条）
   容器 = surface_panel；文字 font_small
```

- **窗格**：一个文字窗格（可带前置图标），或一个自定义窗格（内含其他控件，如进度条、quiet 按钮）。
- **分隔线**：相邻窗格之间一条竖直发丝线，自动绘制。
- **背景与顶边**：背景 `surface_panel`，顶边一条结构性分隔线（窗口内容区与状态栏的交界）。

## 3. 度量与布局

| 项 | 取值（令牌） |
|---|---|
| 状态栏高度 | `control_h_sm`（含顶边分隔线所占的发丝线高度） |
| 窗格左右内边距 | `pad_item_x` |
| 文字样式 | `font_small`，`text_primary`（`muted` 时 `text_secondary`） |
| 图标 | `icon_sm`，与文字间距 `gap_sm` |
| 窗格间分隔线 | 节点宽 `gap_xs`，线为发丝线 `border_subtle`，上下各缩进 `gap_xs`，居中 |
| 背景 / 顶边 | `surface_panel` / `drawSeparator(structural = true)`（`border_strong`） |
| 窗格最小宽度 | `2 × pad_item_x + 省略号宽度`（有图标时再加 `icon_sm + gap_sm`） |
| 绘制外延 | 0 |

**REQ-W-STATUSBAR-001**　默认尺寸策略：水平方向 `fill`，垂直方向 `fixed(control_h_sm)`（物理方向，由控件按 `ui.parentAxis()` 映射，见 REQ-W-LABEL-001）。状态栏是 Row 型容器：窗格按声明顺序自左向右排列，垂直居中。状态栏通常作为窗口根 Column 的最后一个子项，位于窗口底部。调用方**可以**经通用布局选项覆盖。

**REQ-W-STATUSBAR-002**　**外观**：以 `surface_panel` 填满状态栏矩形；顶边画一条 `drawSeparator(a, b, structural = true)`（REQ-THEME-026，`border_strong`，发丝线宽，位于矩形最顶部的像素行）。状态栏没有边框、圆角与凸起/内凹效果，也不绘制任何尺寸手柄（REQ-W-STATUSBAR-010）。

**REQ-W-STATUSBAR-003**　**窗格宽度的三种方式**（`StatusPaneOptions.width`）：
- `fit`（默认）：适应内容，宽度 = `2 × pad_item_x + (有图标时 icon_sm + gap_sm) + 文字宽`，文字宽为以 `font_small` 测得的单行宽度；
- `fixed(v)`：固定宽 `v` lpx（含内边距）；
- `stretch(w)`：伸展，权重 `w`（有限正数，默认 1），吸收其余窗格分配后剩余的宽度（REQ-LAYOUT-016），多个伸展窗格按权重分配。

三种方式分别对应 07 的 `fit_shrink`（仅叶子）、`fixed`、`grow`；自定义窗格（REQ-W-STATUSBAR-008）的 `fit` 取其内容的期望宽度加内边距。

**REQ-W-STATUSBAR-004**　**空间不足时的收缩顺序**（由 07 的分配算法决定，REQ-LAYOUT-016、REQ-LAYOUT-018、REQ-LAYOUT-019）：先是 `stretch` 窗格被压缩到各自的最小宽度；仍不足时 `fit` 的文字窗格（`fit_shrink`）按可收缩量成比例收缩，直到其最小宽度（`2 × pad_item_x + 省略号宽度`，文字以尾部省略号截断）；`fixed` 窗格与自定义窗格的 `fit` 不收缩；仍不足时越界部分被状态栏右缘裁剪（REQ-LAYOUT-019），分隔线随窗格一起被裁剪。窗格总宽恰好等于状态栏内部宽度时不产生省略。

**REQ-W-STATUSBAR-005**　**窗格间分隔线**：相邻两个窗格之间自动绘制一条竖直分隔线（节点宽 `px(gap_xs)`，线为发丝线 `drawSeparator(…, structural = false)`，颜色 `border_subtle`，在节点内水平居中，上下各缩进 `px(gap_xs)`），首窗格之前与末窗格之后**不**画。分隔线是状态栏的内建部分，不是窗格，不可被应用声明或隐藏；只有一个窗格时没有分隔线。

**REQ-W-STATUSBAR-006**　**文字窗格的显示**：文字以 `font_small` 单行显示，换行符与制表符按空格（REQ-TEXT-004 的 `as_space`），颜色 `text_primary`（`muted = true` 时 `text_secondary`），`text_align`（`left` 默认、`center`、`right`）决定文字在窗格内容区（窗格宽度减去两侧 `pad_item_x`）内的位置；有图标时图标位于文字之前，随文字块一起对齐。文字在状态栏高度内垂直居中，基线按 REQ-THEME-017。文字宽度超出窗格内容区时以尾部省略号截断（REQ-THEME-018），**不得**裁出半个字形，也不得渐隐；图标不缩小。空字符串合法（空窗格，仍占据其宽度策略所给的宽度；`fit` 的空窗格宽度 = `2 × pad_item_x`）。

**REQ-W-STATUSBAR-007**　**截断提示**：文字被截断时，窗格**必须**在悬停时以提示框显示完整文字；窗格给出 `tooltip` 时显示调用方文本，无论是否截断都显示。未截断且无 `tooltip` 的窗格**不得**出现提示框；文字窗格（可能被截断者）登记 `hover` 兴趣以便判定（REQ-W-STATUSBAR-009），置 `hover_visual = false`（悬停变化不置脏，REQ-FRAME-037），此时仍不处理任何点击。截断提示经 `ui.tooltipIfTruncated(窗格 ID, 完整文字, 样式)` 声明，由框架在提示框将要显示的时刻以窗格当前内容宽度判定是否截断（REQ-INPUT-057 的补充规则）；`StatusPaneResult.truncated` 仅是基于最近一次布局的参考值。

**REQ-W-STATUSBAR-008**　**自定义窗格**：`beginStatusPane` … `endStatusPane` 之间可声明任意控件（进度条、quiet 按钮、标签、图标等）。自定义窗格是 Row 型容器，左右内边距 `pad_item_x`，子项垂直居中、间距 `gap_sm`；其宽度方式同 REQ-W-STATUSBAR-003（`fit` 取内容的期望宽度加内边距）。窗格内控件各自按自己的规范工作：状态栏不接管其焦点、输入与绘制；窗格内的进度条按其规范水平方向占满（`grow(1)`），因此放进 `fixed` 或 `stretch` 窗格；其中的 quiet 按钮因不在漫游焦点组内而**必须**为 Tab 停靠（REQ-W-BUTTON-018）。窗格内容的高度超过状态栏内部高度时被裁剪。

## 4. 变体与参数

状态栏：

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `enabled` | `bool` | `true` | 为假时文字窗格的文字与图标换 `text_disabled`，自定义窗格内的控件一并有效禁用（REQ-INPUT-049） |
| `a11y_name` | `?[]const u8` | `null` | 无障碍名称（如"状态栏"） |
| `key`、`debug_name`、`layout` | 通用 | | 见模板 |

窗格（`statusPane` / `beginStatusPane`）：

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `width` | `PaneWidth` | `.fit` | `fit` / `fixed(v)` / `stretch(w)`（REQ-W-STATUSBAR-003） |
| `text_align` | `text.Align` | `left` | 文字窗格的行内对齐 |
| `muted` | `bool` | `false` | 文字用 `text_secondary` |
| `icon` | `?theme.Icon` | `null` | 文字窗格的前置图标（状态标记取对应 `status_*` 色，其余取文字色） |
| `tooltip` | `?[]const u8` | `null` | 悬停提示；无论是否截断都显示 |
| `announce` | `bool` | `false` | 为真时窗格文字变化会作为礼貌的实时区域通知辅助技术（REQ-W-STATUSBAR-012） |
| `enabled` | `bool` | `true` | 为假时该窗格文字换 `text_disabled`（自定义窗格内的控件一并禁用） |
| `key`、`debug_name`、`layout` | 通用 | | 见模板；`width` 优先于 `layout.main` |

`PaneWidth = union(enum) { fit, fixed: f32, stretch: f32 }`。文字窗格的文字是 `statusPane` 的位置参数，不是选项。状态栏没有外观变体。

## 5. 状态

### 5.1 状态机

不适用：状态栏与窗格没有交互状态，不响应任何输入。其显示仅由参数决定；窗格宽度随可用宽度在 5.2 之外的"收缩"过程中变化：

| 当前 | 事件 | 下一 | 动作 |
|---|---|---|---|
| 窗格宽度充足 | 状态栏宽度减小 | 收缩 | 按 REQ-W-STATUSBAR-004 的顺序收缩，文字窗格出现省略 |
| 收缩 | 状态栏宽度增大 | 窗格宽度充足 | 恢复，省略消失 |
| 任意 | 应用把 `enabled` 置假 | 禁用 | 文字窗格变灰；自定义窗格内控件一并禁用 |

### 5.2 视觉表现

| 状态 | 绘制（基元 + 令牌） |
|---|---|
| 状态栏 | 背景 `surface_panel`；顶边 `drawSeparator(structural = true)` |
| 窗格间分隔线 | `drawSeparator`，`border_subtle`，上下缩进 `gap_xs` |
| 文字窗格 | 文字 `font_small`，`text_primary`；`muted` 为 `text_secondary` |
| 窗格图标 | `drawMark`，`icon_sm`；状态标记（`info`、`warning`、`error`、`success`）取 `status_info`、`status_warning`、`status_danger`、`status_success`，其余标记取文字色 |
| 禁用 | 文字与图标 `text_disabled`；背景、分隔线不变 |
| 自定义窗格 | 无自有绘制；内容控件各自绘制 |

状态栏没有悬停、按下、焦点外观。

## 6. 鼠标行为

**REQ-W-STATUSBAR-009**　状态栏与文字窗格**不可交互**：不登记 `click`/`drag`/`context`/`wheel`，不取得焦点，不吞鼠标事件。其上（含窗格、分隔线、空白处）的左键、右键、双击、拖拽、滚轮按未命中该控件处理，沿祖先冒泡（REQ-INPUT-019）；指针形状恒为箭头。文字窗格登记 `hover` 兴趣以显示提示框（截断提示或 `tooltip`，REQ-W-STATUSBAR-007），置 `hover_visual = false`，此时仍不处理任何点击。自定义窗格内的控件按各自规范响应指针。

**REQ-W-STATUSBAR-010**　**不画尺寸手柄**：窗口缩放由系统边框负责（窗口使用系统非客户区，ADR 0008），状态栏**不得**在右下角或任何位置绘制尺寸手柄（`grip`），也不为右下角设置缩放命中区、不改变该处的指针形状；无论窗口是否最大化、状态栏是否位于窗口最底部，行为一致。

## 7. 键盘行为

无键位：状态栏与文字窗格不可聚焦，不处理任何键，不登记助记符。

| 键 | 行为 |
|---|---|
| （任何键） | 不处理 |

## 8. 焦点

不适用：状态栏、窗格不可聚焦、不是 Tab 停靠、不是焦点范围、不是漫游组；它们不进入 Tab 序，也不影响焦点转移（REQ-INPUT-037、REQ-INPUT-042）。自定义窗格内的可聚焦控件按其自身规则参与 Tab 序（按先序，状态栏通常位于窗口末尾故其控件排在末端）。

**REQ-W-STATUSBAR-011**　**禁用**：状态栏 `enabled = false`，或某窗格 `enabled = false`，或状态栏位于被禁用的容器内时，文字窗格的文字与图标换 `text_disabled`（背景、顶边、分隔线不变，不整体变灰、不加透明度，REQ-THEME-005）；自定义窗格内的控件一并有效禁用（REQ-INPUT-049），焦点在其内时按 REQ-INPUT-042 转移。禁用不改变窗格宽度，也不影响悬停提示。

## 9. 文本与输入法

显示单行只读文字，不接受文本输入，不显示输入法组字；省略与提示规则见 REQ-W-STATUSBAR-006、REQ-W-STATUSBAR-007。文字超过 `max_layout_bytes`（REQ-TEXT-005）时按该条截取；非法 UTF-8 按 REQ-TEXT-003 显示。

## 10. 动效

不适用：状态栏与文字窗格没有动效（只读信息，文字变化瞬时更换）。窗格内的进度条等控件的动效由其自身规范规定；状态栏不因其动画而重绘自身（进度条的动画帧损伤限于该进度条的绘制范围）。

## 11. 无障碍

| 项 | 值 |
|---|---|
| UIA 控件类型 | 状态栏：StatusBar；文字窗格：Text；自定义窗格：Group |
| 名称来源 | 状态栏：`a11y_name`；文字窗格：窗格文字（无文字时取 `tooltip`）；自定义窗格：`tooltip`（无则无名称，其内控件各有名称） |
| 支持的模式 | 无（窗格内控件按其自身类型提供模式） |
| 状态属性 | IsEnabled；`announce = 真` 的文字窗格 LiveSetting = Polite，其文字变化时触发 LiveRegionChanged 事件 |

**REQ-W-STATUSBAR-012**　文字窗格**必须**作为状态栏的子元素以 Text 类型暴露其文字（含被省略的完整文字，而非显示出来的截断文字）；`announce = 真` 的窗格文字变化时**必须**通知辅助技术（礼貌级，不打断当前朗读）。状态栏与窗格不可聚焦、不可调用、不提供任何模式；分隔线不暴露。

## 12. API 草案

```zig
// 草案：仅签名
pub const PaneWidth = union(enum) {
    fit,
    fixed: f32,                        // lpx，含内边距
    stretch: f32,                      // 权重，有限正数
};

pub const StatusBarOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    a11y_name: ?[]const u8 = null,     // 借用至本帧结束；框架复制
    layout: layout.ItemOptions = .{},  // 各控件共用（07）
};

pub const StatusPaneOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    width: PaneWidth = .fit,
    text_align: text.Align = .left,
    muted: bool = false,
    icon: ?theme.Icon = null,
    tooltip: ?[]const u8 = null,       // 借用至本帧结束；框架在需要显示时复制
    announce: bool = false,
    layout: layout.ItemOptions = .{},  // width 优先于 layout.main
};

pub const StatusPaneResult = struct {
    // 持续性状态（窗格没有激活类结果）
    hovered: bool,                     // 文字窗格登记 hover 兴趣，故可能为真
    truncated: bool,                   // 文字当前是否被省略（基于最近一次布局）
};

/// 容器类控件：beginStatusBar / endStatusBar 成对出现（REQ-CONV-009、REQ-FRAME-028）。
/// 其间只能声明窗格（statusPane 或 beginStatusPane/endStatusPane）。
pub fn beginStatusBar(ui: *Ui, src: std.builtin.SourceLocation, opts: StatusBarOptions) ui.WidgetId;
pub fn endStatusBar(ui: *Ui) void;

/// 文字窗格。text 借用至本帧结束；框架在布局与绘制时使用其排版缓存，不保留引用。
pub fn statusPane(ui: *Ui, src: std.builtin.SourceLocation, text: []const u8, opts: StatusPaneOptions) StatusPaneResult;

/// 自定义窗格：begin/end 之间可声明任意控件（进度条、quiet 按钮等）。
pub fn beginStatusPane(ui: *Ui, src: std.builtin.SourceLocation, opts: StatusPaneOptions) ui.WidgetId;
pub fn endStatusPane(ui: *Ui) void;
```

状态栏没有激活类结果，不触发第二构建遍；`hovered`、`truncated` 是持续性状态。状态栏不持有任何应用值；窗格文字与提示由应用每次构建传入。自定义窗格内控件的结果由各控件自己的 `Result` 返回。

## 13. 保留状态

不适用：状态栏与文字窗格没有状态槽（登记 `hover` 兴趣时的悬停状态为框架内建，REQ-FRAME-013）。窗格宽度由布局求解，不保存；截断判定读取 `ui.lastRect`，不保存。

## 14. 失效规则

**REQ-W-STATUSBAR-013**　绘制键**必须**由以下各项构成。状态栏：窗格数量与各窗格的宽度方式、`enabled`。文字窗格：文字内容、`text_align`、`muted`、`icon`、`enabled`、文字是否被截断。布局输入的内容度量键由文字内容、有无图标、`width` 构成（`fixed` 与 `stretch` 窗格的尺寸与文字无关，文字变化不引起其布局变化）。

| 变化 | 置脏级别 | 损伤范围 |
|---|---|---|
| `fixed` 或 `stretch` 窗格的文字变化 | `build`（由应用的模型通知引起） | 仅该窗格矩形 |
| `fit` 窗格的文字变化导致宽度变化 | `build` | 状态栏矩形（后续窗格位置变化） |
| `fit` 窗格的文字变化且宽度不变 | `build` | 仅该窗格矩形 |
| 窗口宽度变化 | `layout` | 状态栏矩形 |
| 被截断窗格的悬停（有提示框时）、指针在状态栏上移动 | 不置脏（无视觉变化） | 空 |
| `enabled` 变化 | `build` | 状态栏矩形及自定义窗格内的控件 |

**REQ-W-STATUSBAR-014**　状态栏上的指针移动与悬停**不得**置脏、不产生帧（窗格的悬停兴趣 `hover_visual = false`，REQ-FRAME-037）；高频更新某个 `fixed`/`stretch` 窗格的文字时，每次更新产生的损伤**不得**超出该窗格矩形，且不引起其他窗格的重新测量；以相同参数重复声明的窗格不产生损伤。

## 15. 边界与错误情况

| 情况 | 规定 |
|---|---|
| 状态栏内没有窗格 | 仍占高度与顶边；无分隔线 |
| 在状态栏内直接声明窗格以外的控件 | 编程错误：调试构建断言；发布构建照常布局 |
| `stretch` 权重 ≤ 0 或非有限 | 视为 0（仅得最小宽度），调试构建断言（REQ-LAYOUT-009） |
| `fixed(v)` 小于窗格最小宽度 | 取 `v`（不夹紧）；文字按可用宽度省略，可能只剩省略号 |
| 状态栏宽度为 0 或所有窗格都放不下 | 按 REQ-W-STATUSBAR-004；不报错 |
| 文字窗格无文字且无图标 | 合法，空窗格 |
| 窗格内容高度超过 `control_h_sm` | 裁剪到状态栏内部（REQ-W-STATUSBAR-008） |
| 窗口缩放（DPI） | 令牌重新换算，窗格宽度重新求解，文字省略重新判定 |
| 窗口非活动 | 外观不变（不整体变灰） |
| 状态栏位于被禁用的容器内 | 与 `enabled = false` 同样的有效禁用表现（后代控件一并禁用） |
| 窗口最大化或全屏 | 无特殊处理；状态栏仍位于窗口客户区底部，不画尺寸手柄 |

## 16. 验收标准

**AC-W-STATUSBAR-001**　`[金图]` 覆盖：REQ-W-STATUSBAR-001、REQ-W-STATUSBAR-002、REQ-W-STATUSBAR-003、REQ-W-STATUSBAR-005、REQ-W-STATUSBAR-006、REQ-W-STATUSBAR-010。渲染一个宽 600 lpx 的状态栏：伸展窗格（"就绪"）、`fit` 窗格（"行 12，列 5"）、带 `info` 图标的 `fit` 窗格、`fixed(80)` 窗格（"UTF-8"，居中）、右对齐窗格、自定义窗格（`fixed(150)` 内含进度条与"42%"）；缩放 1.0/1.25/1.5/2.0，浅/深/高对比度。预期：与基准图一致；几何断言——高 = `control_h_sm`；背景 `surface_panel`；顶边为 `border_strong` 的一条发丝线且位于最顶部像素行；`fit` 窗格宽 = `2 × pad_item_x + (图标 + gap_sm) + 文字宽`；`fixed(80)` 窗格宽恰为 `px(80)`；伸展窗格宽 = 内部宽度 − 其余窗格宽 − 分隔线宽；相邻窗格间恰一条分隔线（宽 `gap_xs`、线 `border_subtle`、上下各缩进 `gap_xs`），首窗格之前与末窗格之后无分隔线；文字为 `font_small` 且垂直居中、基线与同行标签一致（REQ-THEME-017）；对齐 left/center/right 三种文字位置正确；状态栏右下角区域（尺寸手柄位置）无任何手柄像素，与背景色一致。

**AC-W-STATUSBAR-002**　`[金图]` 覆盖：REQ-W-STATUSBAR-004、REQ-W-STATUSBAR-006、REQ-W-STATUSBAR-011、REQ-W-STATUSBAR-013。同一状态栏（伸展窗格、两个 `fit` 窗格、一个 `fixed` 窗格）依次压窄到 600、300、200、120 lpx；另渲染 `enabled = false`；浅/深/高对比度。预期：与基准图一致；窄到不足时先是伸展窗格缩到最小宽度（`2 × pad_item_x`），再是 `fit` 窗格按比例收缩并以 `…` 结尾（最后一个字形完整），`fixed` 窗格宽度始终为 `px(固定值)`；最窄时越界部分被右缘裁剪；窗格总宽恰等于内部宽度时无省略号；禁用态文字与图标为 `text_disabled`，背景与分隔线不变；禁用态用到的颜色集合 ⊆ 禁用令牌 ∪ 表面令牌 ∪ 边框令牌。

**AC-W-STATUSBAR-003**　`[回放]` 覆盖：REQ-W-STATUSBAR-009、REQ-W-STATUSBAR-010。确认不响应输入。状态栏位于外层面板（登记了 `click`）内；窗格文字均未被截断、无 `tooltip`。脚本：在窗格、分隔线、空白处与右下角（尺寸手柄的常见位置）依次左键单击、双击、右键、按下后拖动；滚动滚轮（外层为可滚动容器）；按 Tab 五次、Space、Enter。预期：状态栏与窗格无焦点、Tab 序列不含状态栏（窗口其余控件的序列与移除状态栏后相同）；单击被外层面板接收；滚轮 → 容器偏移变化；平台层记录的指针形状全程为箭头；上述输入期间状态栏的 `frame.count` 增量为 0、其绘制节点计数为 0。

**AC-W-STATUSBAR-004**　`[回放]` 覆盖：REQ-W-STATUSBAR-007。窗格文字被截断（状态栏压窄）：悬停并推进假时钟超过系统悬停时间 → 出现提示框，文本为窗格完整文字；窗口失活后提示消失。未截断且无 `tooltip` 的窗格同样操作 → 无提示框（未截断时 `tooltipIfTruncated` 不显示）。给出 `tooltip` 的未截断窗格 → 显示调用方文本；截断窗格同时给 `tooltip` → 显示调用方文本。

**AC-W-STATUSBAR-005**　`[回放]` 覆盖：REQ-W-STATUSBAR-008、REQ-W-STATUSBAR-009、REQ-W-STATUSBAR-011。自定义窗格（`fixed(200)`）内含进度条（`value` 为 0.3）与一个 quiet 按钮 B；窗口另含文本框 T。预期：点击 B → `clicked` 真、B 因 quiet 不取得焦点（焦点仍在 T）；Tab 序列依次为 T → B（独立的 Tab 停靠，不是漫游组成员，REQ-W-BUTTON-018）；进度条不可聚焦、点击其上由外层处理；`enabled = false` → B 与进度条一并有效禁用，B 不再响应点击与 Tab；进度条内容高度（`progress_h`）在状态栏内垂直居中；窗格内容高度被人为设为 40 lpx → 裁剪到状态栏内部。

**AC-W-STATUSBAR-006**　`[单元]` 覆盖：REQ-W-STATUSBAR-003、REQ-W-STATUSBAR-004、REQ-W-STATUSBAR-012。宽度求解的纯逻辑：给定 `fit`、`fixed`、`stretch` 窗格及内部宽度，断言各窗格宽度与 07 的 `layout.distribute` 结果一致（含权重 2:1 的两个伸展窗格按最大余数法分配）。经假 UIA 入口：状态栏类型 StatusBar、不提供任何模式；文字窗格类型 Text、Name 为完整文字（被省略时仍是完整文字）；`announce = 真` 的窗格 LiveSetting = Polite，其文字变化产生一次 LiveRegionChanged；自定义窗格类型 Group；分隔线不暴露；状态栏与窗格不可聚焦。窗格声明在状态栏之外 → 调试构建断言中止；`stretch(0)` → 断言。

**AC-W-STATUSBAR-007**　`[计量]` 覆盖：REQ-W-STATUSBAR-013、REQ-W-STATUSBAR-014。界面含一个状态栏（伸展窗格、`fixed(80)` 窗格、`fit` 窗格、自定义窗格含进度条）与 100 个其他控件。回放：指针移过状态栏全部窗格与分隔线 → `frame.count` 增量为 0（REQ-FRAME-037）。连续 100 次改变 `fixed(80)` 窗格的文字（各 `invalidate(.build)`）→ 每帧损伤恰为该窗格矩形，`layout.measured_nodes` 增量不含其他窗格，`frame.presents` 每帧 +1；以相同文字再次 `invalidate(.build)` → 损伤为空、`frame.presents` 不变。改变 `fit` 窗格文字使宽度变化 → 损伤 ⊆ 状态栏矩形；宽度不变的文字变化 → 损伤恰为该窗格矩形。进度条动画期间（进度条 `value` 追赶）→ 每帧构建遍数为 0、损伤 ⊆ 进度条的绘制范围。窗口宽度逐 1 ppx 改变 → 仅布局帧，构建遍数 0。

## 17. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-W-STATUSBAR-01 | 是否提供"简单模式"（整条只显示一段文字，如菜单项说明） | 不提供；应用在构建函数里改用单个伸展窗格即可 |
| OPEN-W-STATUSBAR-02 | 是否支持窗格内容超出时从右向左省略或中间省略（路径文字） | 不提供；09/05 只有尾部省略 |
| OPEN-W-STATUSBAR-03 | 状态栏高度 `control_h_sm`（20 lpx）与 `font_small` 行高（15 lpx）之间的内边距是否足够（放入 quiet 按钮时按钮高度 `control_h` = 24 超出状态栏） | 自定义窗格内的 quiet 按钮应使用 `size = .sm`（`control_h_sm`）；M3 实机评审 |
| OPEN-W-STATUSBAR-04 | 状态栏是否需要把自动分隔线按窗格类型控制（如图标窗格不画） | 不提供；统一规则 |
