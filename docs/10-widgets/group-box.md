# 分组框（group-box）

## 1. 用途

用一圈带标题的边框把一组相关控件框起来，表示它们属于同一个主题（如"连接设置"）。分组框是**容器**：自身不可交互，但对内部控件有两个作用——标题的助记符把焦点送入组内，禁用分组框即禁用整组。参照 Windows 的 Group Box（`BS_GROUPBOX`），本规范只取其经典形态：**标题嵌在上边框线上**。

- 只需要一条分界线 → 用 separator。
- 需要折叠/展开 → 不支持；用应用自己的 button + 条件声明。
- 需要标题条（实心条加标题）的面板 → 不提供该变体（REQ-W-GROUPBOX-006）。
- 一组互斥单选框 → 单选组（radio）本身不画边框，常把它放进分组框里。

## 2. 解剖

```
   ┌─ 标题(助记符) ─────────────────────┐   ← 标题嵌在上边框线上，两侧各留 gap_sm 的"缺口"
   │                                    │
   │  内容区（Column）                    │   ← 左右下内边距 pad_panel；上边距见 REQ-W-GROUPBOX-003
   │                                    │
   └────────────────────────────────────┘
   容器 = drawPanel（surface_panel + border_strong 发丝线）
```

- **边框与底**：`drawPanel`（面板）。
- **标题**（可选）：单行文字，可含一个助记符；位于上边框线上，边框在标题所占区间内断开。
- **内容区**：默认纵向排列的子项容器。

## 3. 度量与布局

| 项 | 取值（令牌） |
|---|---|
| 标题样式 | `font_body_strong`，`text_primary` |
| 标题行高 `H` | `font_body_strong` 的行高（B = 12 时 16 lpx） |
| 标题起点 | 自节点左缘起 `gap_lg + gap_sm` |
| 标题两侧缺口 | 各 `gap_sm` |
| 边框 | `drawPanel`，圆角 `radius_container`；边框上缘位于节点顶向下 `floor(H / 2)` 处（有标题时） |
| 内边距 | 左、右、下：`pad_panel`；上：见 REQ-W-GROUPBOX-003 |
| 子项间距 | `gap_md`（可经 `gap` 修改） |
| 绘制外延 | 0 |

**REQ-W-GROUPBOX-001**　默认尺寸策略：水平方向 `fill`（父为 Row 时主轴 `grow(1)`，父为 Column 时交叉轴 `fill`；物理方向由控件按 `ui.parentAxis()` 映射，见 REQ-W-LABEL-001），垂直方向 `fit`（内容高度 + 内边距）。调用方**可以**经通用布局选项覆盖。最小宽度 = `2 × (gap_lg + gap_sm) + 标题宽度（被截断时取一个字符加省略号的宽度）`与内容期望宽度 + `2 × pad_panel` 的较大者。

**REQ-W-GROUPBOX-002**　**几何（有标题）**：节点矩形自上而下依次为：标题行（高 `H`，位于节点顶部）；边框矩形的上缘位于节点顶向下 `floor(H / 2)`（整数 ppx），左右下缘即节点的左右下缘。标题文字起点 x = 节点左缘 + `px(gap_lg + gap_sm)`，垂直居中于标题行（基线按 REQ-THEME-017）。边框上缘线在 `[标题起点 − px(gap_sm), 标题终点 + px(gap_sm)]` 区间内**不显示**（以 `surface_panel` 填充该段，覆盖上缘线，高度为发丝线宽），使标题"嵌"在线上。标题区间超出节点宽度时见 REQ-W-GROUPBOX-004。

**REQ-W-GROUPBOX-003**　**内容区与内边距**：分组框容器设 `Params.border = 1`（REQ-LAYOUT-056）为发丝线边框留位，内容区矩形 = 节点矩形向内缩：左、右、下各 `border`（一条发丝线）加 `px(pad_panel)`，上方自节点顶向下 `H + px(gap_xs)`（`padding.top` 取 `H + gap_xs` 减去 `border` 在上边已内缩的一条发丝线）。无标题时（REQ-W-GROUPBOX-005）上缘取 `px(pad_panel)`。子项按 `direction`（默认纵向，即 Column）排列，间距 `gap`（默认 `gap_md`），子项在交叉轴上的对齐取 `cross_align`（默认 `start`）。内容区超出节点时按 07 的规则裁剪（`clip` 默认关闭，不额外裁剪）。

**REQ-W-GROUPBOX-004**　**标题的截断**：标题宽度超过可用宽度（节点宽度 − `2 × px(gap_lg + gap_sm)`）时以尾部省略号截断（REQ-THEME-018），悬停标题区间时以提示框显示完整标题（去除助记符标记）；截断提示经 `ui.tooltipIfTruncated(标题节点 ID, 完整标题, 样式)` 声明（REQ-INPUT-057 的补充规则，由框架在提示框将要显示时判定是否截断）；标题区间在标题非空时登记 `hover` 兴趣，仅用于提示，置 `hover_visual = false`（悬停变化不置脏，REQ-FRAME-037），不处理点击。截断提示的 owner 是**标题节点**的 ID（分组框的一个子节点，不是分组框节点本身）。标题的换行符与制表符按空格。

**REQ-W-GROUPBOX-005**　**无标题**：标题为空串时不画缺口，边框上缘位于节点顶，内容区上边距取 `px(pad_panel)`；此时分组框仍是一个有边框的面板容器。

**REQ-W-GROUPBOX-006**　**只提供一种变体**：标题嵌在上边框线上的经典分组框。标题条（实心表头条）变体**不提供**，`header_h` 令牌不用于本控件。分组框没有结构性变体参数。

## 4. 变体与参数

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `direction` | `layout.Orientation` | `.vertical` | 内容区子项排列方向 |
| `gap` | `theme.Gap` | `.md` | 子项间距 |
| `cross_align` | `layout.Align` | `.start` | 子项交叉轴对齐 |
| `tooltip` | `?[]const u8` | `null` | 标题区间的悬停提示 |
| `enabled` | `bool` | `true` | 为假时整组禁用，所有后代一并有效禁用（REQ-INPUT-049） |
| `key`、`debug_name`、`layout` | 通用 | | 见模板 |

标题是 `beginGroupBox` 的位置参数，不是选项。

## 5. 状态

### 5.1 状态机

不适用：分组框没有交互状态。仅有"启用/禁用"两种静态模式，由 `enabled` 决定：

| 当前 | 事件 | 下一 | 动作 |
|---|---|---|---|
| 启用 | 应用传入 `enabled = false` | 禁用 | 后代有效禁用；焦点在后代内时按 REQ-INPUT-042 转移；后代持有的捕获按 REQ-INPUT-050 释放；标题助记符不再登记 |
| 禁用 | 应用传入 `enabled = true` | 启用 | 后代恢复各自的启用状态（受其自身 `enabled` 控制） |

### 5.2 视觉表现

| 状态 | 绘制（基元 + 令牌） |
|---|---|
| 启用 | `drawPanel(边框矩形, radius_container)`；标题 `font_body_strong`、`text_primary`；标题缺口按 REQ-W-GROUPBOX-002 |
| 禁用 | 面板与边框外观不变（`drawPanel` 无禁用变体）；标题 `text_disabled`；子控件各自按禁用配方绘制 |
| 助记符下划线 | 显示时在标题的助记字符下画发丝线，颜色同标题（REQ-INPUT-047） |

分组框没有悬停、按下、焦点外观。

## 6. 鼠标行为

**REQ-W-GROUPBOX-007**　分组框**不可交互**：不登记 `click`/`drag`/`context`/`wheel`，不取得焦点，不吞鼠标事件，不显示悬停外观。落在分组框空白处（边框、标题、内边距、子项之间）的左键、右键、双击、拖拽、滚轮按未命中该控件处理，沿祖先冒泡（REQ-INPUT-019）；指针形状为箭头。分组框的子控件按各自的规则响应，不受分组框影响（禁用时除外，见 REQ-W-GROUPBOX-010）。

## 7. 键盘行为

| 键 | 行为 |
|---|---|
| Alt+标题助记字符 | 焦点移到组内第一个可聚焦且启用的控件，焦点变为可见 |
| （其他键） | 不处理 |

**REQ-W-GROUPBOX-008**　**标题助记符**：标题中的助记符按 REQ-INPUT-046 解析，下划线显示遵循 REQ-INPUT-047，经 `ui.mnemonic(分组框 ID, ch, .focus_within)` 登记（REQ-INPUT-048）。激活时焦点移到分组框子树内按 Tab 序的第一个可聚焦、启用、未隐藏的节点，原因 `mnemonic`；该控件**不**被激活（只聚焦）。组内没有这样的节点时助记符不生效（`focus_within` 不越出子树）。禁用的分组框不登记助记符。

## 8. 焦点

**REQ-W-GROUPBOX-009**　分组框**不可聚焦**、不是 Tab 停靠，不是漫游组成员，也不是焦点范围（`ui.focusScope` 不由它声明）；Tab 序与焦点转移完全由其内部控件决定。焦点环不适用。

**REQ-W-GROUPBOX-010**　**禁用整组**：`enabled = false` 时分组框节点置 `NodeFlags.disabled`，其全部后代成为有效禁用（REQ-INPUT-049）：不可聚焦、不在 Tab 序与组导航中、不产生任何激活类结果、不响应助记符与默认/取消按钮、指针形状为箭头；后代自身的 `enabled = true` 不能覆盖祖先的禁用。禁用发生时，组内持有焦点者按 REQ-INPUT-042 转移（原因 `transfer`），持有捕获者按 REQ-INPUT-050 释放并取消点击/拖拽。标题改用 `text_disabled` 且不登记助记符；面板与边框外观不变。重新启用后后代恢复其各自的 `enabled`。

## 9. 文本与输入法

标题是单行文字，不接受文本输入。省略与提示规则见 REQ-W-GROUPBOX-004。标题为空串合法（REQ-W-GROUPBOX-005）。

## 10. 动效

不适用：分组框没有动效（无悬停、按下、焦点、展开状态可过渡）。

## 11. 无障碍

| 项 | 值 |
|---|---|
| UIA 控件类型 | Group |
| 名称来源 | 去除助记符标记的标题；无标题时取 `tooltip`，再无则无名称 |
| 支持的模式 | 无 |
| 状态属性 | IsEnabled（禁用时为假，其后代的 IsEnabled 亦为假）；AccessKey（形如 "Alt+G"） |

**REQ-W-GROUPBOX-011**　组内控件**必须**作为分组框 UIA 元素的子元素暴露，使读屏器在进入组内控件时能读出分组名称（标题）；禁用分组框时，其全部后代的 IsEnabled 为假。

## 12. API 草案

```zig
// 草案：仅签名
pub const GroupBoxOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    direction: layout.Orientation = .vertical,
    gap: theme.Gap = .md,
    cross_align: layout.Align = .start,
    tooltip: ?[]const u8 = null,       // 借用至本帧结束；框架在需要显示时复制
    layout: layout.ItemOptions = .{},  // 各控件共用（07）
};

/// 容器类控件：beginGroupBox / endGroupBox 成对出现（REQ-CONV-009、REQ-FRAME-028）。
/// title 借用至本帧结束；含 `&` 助记符语法；可为空串（无标题，REQ-W-GROUPBOX-005）。
/// 返回分组框的 WidgetId（可作为 label 的 for_id 以外的用途，如 ui.lastRect）。
/// 分组框没有结果：没有激活类结果，也没有持续性状态；内容由调用方在 begin/end 之间声明。
pub fn beginGroupBox(ui: *Ui, src: std.builtin.SourceLocation, title: []const u8, opts: GroupBoxOptions) ui.WidgetId;
pub fn endGroupBox(ui: *Ui) void;
```

分组框不持有任何应用值。`begin`/`end` 之间的控件各自遵循其规范；ID 种子按 REQ-FRAME-003 自动压入。

## 13. 保留状态

不适用：分组框没有状态槽，也不登记指针兴趣（标题的悬停兴趣仅在被截断或有 `tooltip` 时登记，由框架内建状态管理，无需槽）。

## 14. 失效规则

**REQ-W-GROUPBOX-012**　绘制键**必须**由以下各项构成：标题文字内容、标题是否被截断、`enabled`。助记符下划线是否显示不进入绘制键：它由绘制函数在绘制时读取，其变化按 REQ-INPUT-047 整窗置 `paint`。布局输入的哈希由 `direction`、`gap`、`cross_align`、标题文字内容（决定 `H` 与最小宽度）、有无标题构成；子项由各自的哈希折叠（REQ-LAYOUT-045）。

| 变化 | 置脏级别 | 损伤范围 |
|---|---|---|
| 标题文字变化且宽度不变 | `build`（由应用的模型通知引起） | 标题区间矩形 |
| 标题文字变化导致缺口宽度变化 | `build` | 分组框上缘带（标题行）矩形 |
| `enabled` 变化 | `build` | 分组框矩形及其后代（后代外观随之变化） |
| 键盘提示下划线显隐（按下 Alt） | `paint`（整窗，REQ-INPUT-047）；绘制函数读取当前的键盘提示可见性 | 整窗 |
| 指针经过、点击（落在空白处） | 不置脏 | 空 |

**REQ-W-GROUPBOX-013**　指针在分组框的空白处（边框、标题、内边距）移动与悬停变化**不得**置脏、不产生帧（标题的悬停兴趣 `hover_visual = false`，REQ-FRAME-037）；仅其内部某子控件的悬停变化所产生的帧，损伤不得超出该子控件的绘制范围（分组框自身不因子控件的悬停而重绘）。

## 15. 边界与错误情况

| 情况 | 规定 |
|---|---|
| 空标题 | 见 REQ-W-GROUPBOX-005 |
| 标题宽于节点 | 见 REQ-W-GROUPBOX-004；缺口不超出边框两端圆角之内 |
| 组内无子控件 | 内容区高度 0；分组框高度 = `H + gap_xs + pad_panel`；助记符不生效 |
| 分组框嵌套 | 允许；内层分组框按其父容器（外层内容区，Column）决定宽度；各层标题各自嵌在自己的上缘 |
| 禁用分组框时焦点在组内 | 按 REQ-INPUT-042 转移（原因 `transfer`）；组内捕获按 REQ-INPUT-050 释放 |
| 组内某子控件自身 `enabled = true` 而分组框禁用 | 仍为有效禁用（禁用由祖先传递，REQ-INPUT-049） |
| 助记符与组内某控件的助记符相同 | 多个匹配节点时只移动焦点（REQ-INPUT-048）；按先序，分组框先于其后代 |
| 按下期间分组框内的子控件所属分组框被禁用 | 子控件的捕获按 REQ-INPUT-050 释放，点击取消 |
| 窗口非活动 | 外观不变 |

## 16. 验收标准

**AC-W-GROUPBOX-001**　`[金图]` 覆盖：REQ-W-GROUPBOX-001、REQ-W-GROUPBOX-002、REQ-W-GROUPBOX-003、REQ-W-GROUPBOX-005、REQ-W-GROUPBOX-006。渲染：标题"连接设置"、内含三行（标签+文本框）的分组框；标题为空的分组框；标题含助记符的分组框（提示下划线显示）；内含按钮与单选组的分组框；嵌套一层；缩放 1.0/1.25/1.5/2.0，浅/深/高对比度。预期：与基准图一致；几何断言——边框上缘位于节点顶向下 `floor(H / 2)`；标题起点 x = `px(gap_lg + gap_sm)`；标题两侧缺口各 `px(gap_sm)` 且缺口内无边框像素（上缘线被 `surface_panel` 覆盖）；缺口之外上缘线连续；内容区左、右、下内边距 = 一条发丝线（`border`）加 `px(pad_panel)`，上边距 = `H + px(gap_xs)`（无标题时 `px(pad_panel)`）；子项间距 = `px(gap_md)`；边框与底为 `drawPanel`（`surface_panel` + `border_strong`，圆角 `radius_container`）；无标题条变体的像素（无 `header_h` 高的实心条）。

**AC-W-GROUPBOX-002**　`[金图]` 覆盖：REQ-W-GROUPBOX-004、REQ-W-GROUPBOX-010。渲染：标题被压到宽度一半（以 `…` 结尾，最后一个字形完整，缺口随之缩短）；整组禁用（标题 `text_disabled`，内含的按钮、文本框、复选框均为禁用配方，其中一个子控件自身 `enabled = true`）；浅/深/高对比度。预期：与基准图一致；禁用态下面板与边框像素与启用态相同；所有后代呈禁用外观；禁用态用到的颜色集合 ⊆ 禁用令牌 ∪ 表面令牌 ∪ 边框令牌。

**AC-W-GROUPBOX-003**　`[回放]` 覆盖：REQ-W-GROUPBOX-007、REQ-W-GROUPBOX-009。确认不响应输入。分组框位于可滚动容器内，外层面板登记了 `click`；组内含按钮 B 与文本框 T。脚本：在分组框的边框上、标题上、内边距空白处依次左键单击、双击、右键、按下后拖动；滚动滚轮；Tab 三次。预期：分组框无焦点、Tab 序列依次为 T → B 等组内控件（不含分组框）；空白处单击被外层面板接收；滚轮 → 容器偏移变化；指针形状为箭头；这些输入期间分组框自身的绘制节点计数为 0；点击组内按钮 B 仍正常 `clicked`（子控件不受影响）。

**AC-W-GROUPBOX-004**　`[回放]` 覆盖：REQ-W-GROUPBOX-008、REQ-W-GROUPBOX-004。分组框标题"常规(&G)"，组内先后有文本框 T1、按钮 B；其后（组外）有文本框 T2。系统键盘提示设为"默认隐藏"：初始金图无下划线；按 Alt → G 下出现下划线；Alt+G → 焦点移到 T1、焦点可见、T1 无激活类结果；组内第一个控件被禁用时 → 焦点移到 B。组内无可聚焦控件时 Alt+G → 焦点不变（不落到 T2）。禁用分组框时 Alt+G → 焦点不变。标题被截断：悬停并推进假时钟超过系统悬停时间 → 提示框显示完整标题（不含 `&`）；未截断且无 `tooltip` → 无提示框；给 `tooltip` → 显示调用方文本。

**AC-W-GROUPBOX-005**　`[回放]` 覆盖：REQ-W-GROUPBOX-010。组内含文本框 T（持有焦点）、按钮 B、一个 slider（拖动中）。令分组框 `enabled` 置假：焦点按 REQ-INPUT-042 转移出组（原因 `transfer`；若组外无可聚焦控件则焦点置空）；拖动中的 slider 按取消处理（捕获释放、恢复原值）；此后 B、T、slider 的 `hovered` 以外的持续性状态全为假，点击与 Space/Enter 均不产生激活类结果，Tab 序列不含组内控件，助记符不响应。再把 `enabled` 置真 → 后代恢复可聚焦；组内一个自身 `enabled = false` 的控件仍为禁用。

**AC-W-GROUPBOX-006**　`[单元]` 覆盖：REQ-W-GROUPBOX-011、REQ-W-GROUPBOX-008、REQ-W-GROUPBOX-005。经假 UIA 入口：控件类型 Group、不提供任何模式；Name 为去除助记符的标题，AccessKey 为 "Alt+G"；无标题时 Name 取 `tooltip`，再无则为空；组内按钮的 UIA 父元素为该分组框；禁用分组框后其全部后代 IsEnabled 为假。空标题 → 无缺口、上边距 `px(pad_panel)`。标题含 `\n`、`\t` → 渲染为单行。`"A && B"` → 显示 "A & B" 且未登记助记符。

**AC-W-GROUPBOX-007**　`[计量]` 覆盖：REQ-W-GROUPBOX-012、REQ-W-GROUPBOX-013。界面含 20 个分组框（各含若干控件）。回放：指针在某分组框 G 的边框、标题、空白处移动 → `frame.count` 增量为 0（REQ-FRAME-037）；指针移入 G 内的按钮 X 再移出 → 各帧构建遍数为 0，被绘制的节点集合 ⊆ {X 及其与损伤相交的祖先}，损伤面积 ≤ X 的绘制范围面积（G 本身作为祖先可被重绘但损伤仅限 X）。仅改变 G 的标题文字（宽度不变）并 `invalidate(.build)` → 损伤 ⊆ G 的标题区间矩形；以相同参数再次 `invalidate(.build)` → 损伤为空、`frame.presents` 不变。`enabled` 由真改假 → 损伤覆盖 G 的矩形。按下 Alt（`SPI_GETKEYBOARDCUES` 为假）→ 构建遍数 0，仅置整窗 `paint`（REQ-INPUT-047）。

## 17. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-W-GROUPBOX-01 | 禁用的分组框边框没有禁用令牌（`drawPanel` 无禁用变体） | 沿用 `border_strong`；仅标题与后代变灰，足以表达禁用 |
| OPEN-W-GROUPBOX-02 | 标题缺口用 `surface_panel` 覆盖边框线，依赖分组框自身底色就是 `surface_panel`（由 `drawPanel` 保证） | 若将来 `drawPanel` 允许透明底，需改为裁剪方式绘制缺口 |
| OPEN-W-GROUPBOX-03 | 是否提供折叠式分组框（标题带展开箭头） | 不提供 |
