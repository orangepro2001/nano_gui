# 单选框（radio）

## 1. 用途

在一组互斥的选项中选定一个。一组单选框共享**一个**由应用持有的值，每个单选框对应该值的一个取值。参照 Windows 的 Button（`BS_AUTORADIOBUTTON`）及其组内方向键选中的行为。

- 选项多于约 7 个，或需要节省空间 → 用 combo-box 或列表。
- 独立的开/关 → 用 checkbox；立即生效的开/关 → 用 switch。
- 允许"都不选" → 单选框不支持用户取消选中；应用需要该语义时增加一个"无"选项，或改用 checkbox。
- 单选框**必须**处于一个单选组内（`beginRadioGroup` / `endRadioGroup`）。

## 2. 解剖

```
 ┌─ 单选组（漫游焦点组，整组一个 Tab 停靠）
 │    ( ● )  选项一(助记符下划线)      ← 圆 + 标签；整体是一个点击目标
 │    (   )  选项二
 │    (   )  选项三
 └
   圆        └ gap_md ┘
```

- **圆**：边长 `check_size` 正方形的内切正圆，由 `drawRadio` 绘制；选中时中心为**点**。
- **标签**（可选）：单行文字，可含一个助记符。
- **单选组**：不可见的容器，声明成员范围与焦点漫游；默认纵向排列。

## 3. 度量与布局

| 项 | 取值（令牌） |
|---|---|
| 高度 | `control_h`（`size = .sm` 时 `control_h_sm`，`.lg` 时 `control_h_lg`） |
| 圆的直径 | `check_size`，垂直居中，左缘贴节点左缘 |
| 圆与标签间距 | `gap_md` |
| 标签样式 | `font_body` |
| 最小宽度 | `check_size` |
| 组内子项间距 | 默认 `gap_sm`（`RadioGroupOptions.gap`） |
| 绘制外延 | `focus_ring_w` |

**REQ-W-RADIO-001**　单选框的默认尺寸策略与度量同 checkbox：水平方向 `fit_shrink`，垂直方向 `fixed(高度令牌)`（物理方向，由控件按 `ui.parentAxis()` 映射，见 REQ-W-LABEL-001）；期望宽度 = `check_size + (标签非空时 gap_md + 标签文字宽)`；标签宽度不足时以尾部省略号截断，圆不缩小。

**REQ-W-RADIO-002**　标签文字被截断时，单选框**必须**在悬停时以提示框显示完整文字（去除助记符标记）；调用方另给 `tooltip` 时显示调用方的文本。无标签的单选框**必须**提供 `a11y_name` 或 `tooltip`，调试构建在两者都缺失时记录一条 `warn`。

**REQ-W-RADIO-003**　命中范围是整个布局矩形（圆、间距与标签，不含焦点环外延，不因圆形而排除四角）。圆与标签垂直居中，标签文字基线按 REQ-THEME-017 与同行其他单行控件对齐。

**REQ-W-RADIO-004**　单选组容器默认纵向排列子项（`direction = .vertical`），`gap` 默认 `gap_sm`，宽度 `fit`，高度 `fit`；`direction = .horizontal` 时横向排列，`gap` 建议取 `gap_lg`。组容器本身无外观、不绘制、不进入命中表，其节点只承载焦点组与禁用标志。

## 4. 变体与参数

单选框：

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `size` | `ControlSize` | `md` | 高度档（圆的直径不随档位变化） |
| `tooltip` | `?[]const u8` | `null` | 提示文本 |
| `a11y_name` | `?[]const u8` | `null` | 无标签时的无障碍名称 |
| `enabled` | `bool` | `true` | |
| `key`、`debug_name`、`layout` | 通用 | | 见模板 |

单选组：

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `direction` | `layout.Orientation` | `.vertical` | 子项排列方向 |
| `gap` | `theme.Gap` | `.sm` | 子项间距 |
| `enabled` | `bool` | `true` | 为假时整组禁用，所有成员一并禁用（REQ-INPUT-049） |
| `key`、`debug_name`、`layout` | 通用 | | 见模板 |

值不是选项：`radio(…, value, this_value, …)` 的 `value` 是应用持有的指针，指向枚举或整数；`this_value` 是该单选框代表的取值。`value.* == this_value` 即为选中。

## 5. 状态

### 5.1 状态机

状态变量：`armed ∈ {无, 鼠标, 空格}`。悬停、聚焦、禁用由框架维护（08）；选中与否由 `*value` 决定，不是控件状态。

| 当前 `armed` | 事件 | 条件 | 下一 `armed` | 动作 |
|---|---|---|---|---|
| 无 | 左键按下于单选框内 | 启用 | 鼠标 | 隐式捕获（REQ-INPUT-013） |
| 鼠标 | 左键释放 | 指针在命中范围内，未选中 | 无 | `*value = this_value`，报告 `changed` |
| 鼠标 | 左键释放 | 指针在命中范围内，已选中 | 无 | 无 |
| 鼠标 | 左键释放 | 指针在范围外 | 无 | 无 |
| 鼠标 | 捕获被取消（REQ-INPUT-024） | — | 无 | 无 |
| 无 | 获得焦点，原因为 `group`（方向键组内移动） | 启用，未选中 | 无 | `*value = this_value`，报告 `changed` |
| 无 | 获得焦点，原因为 `tab`、`pointer`、`programmatic`、`restore`、`transfer`、`initial` | — | 无 | 无（只移动焦点，不选中） |
| 无 | Space 按下 | 持有焦点，非自动重复 | 空格 | 无 |
| 空格 | Space 释放 | 仍持有焦点，未选中 | 无 | `*value = this_value`，报告 `changed` |
| 空格 | Space 释放 | 仍持有焦点，已选中 | 无 | 无 |
| 空格 | Esc 按下 / 失去焦点 / 变为禁用 | — | 无 | 无（取消） |
| 无 | 助记符激活 | 启用 | 无 | 选中（若未选中则 `*value = this_value`，报告 `changed`），`activated = .mnemonic` |
| 无 | Enter 按下 | 持有焦点 | 无 | 不处理（冒泡到默认按钮） |
| 鼠标 | Space 按下 | — | 鼠标 | 忽略 |
| 空格 | 左键按下于单选框内 | — | 空格 | 忽略 |

### 5.2 视觉表现

"显示为按下" = `armed = 鼠标` 且指针在命中范围内，或 `armed = 空格`。圆形外观见 REQ-W-RADIO-016。

| 状态 | 绘制（基元 + 令牌） |
|---|---|
| 未选中 | `drawRadio(圆矩形, false, t, visual)`：圆形内凹表面（`surface_sunken`、`border_control`），无点 |
| 选中 | `drawRadio(圆矩形, true, t, visual)`：强调色渐变填充、`accent_border` 边框，中心 `text_on_accent` 的 `radio_dot` 点 |
| 悬停 | 圆换悬停变体 |
| 显示为按下 | `visual.pressed` 传入 `drawRadio`，由其配方给出按下外观；标签不位移 |
| 焦点可见 | 加 `drawFocusRing(布局矩形, radius_control)`（圆自身的焦点环为同心圆环，REQ-THEME-039） |
| 禁用 | 圆禁用配方（`surface_raised_disabled` + `border_control_disabled`），点 `text_disabled`，标签 `text_disabled`；选中的禁用圆**仍**绘制点（形状表示值） |
| 标签 | 启用 `text_primary`，禁用 `text_disabled` |
| 助记符下划线 | 显示时在助记字符下画发丝线（REQ-INPUT-047） |

## 6. 鼠标行为

**REQ-W-RADIO-005**　单选框登记指针兴趣 `click`。左键按下时进入 `armed = 鼠标` 并立即显示为按下（`dur_instant`）；按下瞬间**不**改变值。指针移出命中范围时恢复非按下外观，移回时再次显示为按下；期间其他控件不显示悬停（捕获语义）。

**REQ-W-RADIO-006**　选中在左键**释放**的那一帧生效：仅当释放时指针位于命中范围内且该单选框尚未选中时，`*value = this_value` 并报告 `changed`。点击已选中的单选框**不**报告 `changed`、不改变值。用户操作**不能**使组内所有单选框都处于未选中。

**REQ-W-RADIO-007**　快速连续点击不因系统双击时间而合并；单选框不区分单击与双击。右键、中键的按下与释放不改变状态、不报告 `changed`，无上下文菜单。滚轮不处理，按 REQ-INPUT-019 冒泡。指针形状恒为箭头（REQ-THEME-032）。

**REQ-W-RADIO-008**　鼠标点击使单选框获得焦点（点击聚焦，REQ-INPUT-022），但不使焦点变为可见。点击聚焦**不**触发"获得焦点即选中"（REQ-W-RADIO-012）；选中仅由释放时的点击语义产生。

## 7. 键盘行为

| 键 | 行为 |
|---|---|
| ← ↑ | 组内焦点移到前一个启用成员并**选中它**；首项再前进则回绕到末项 |
| → ↓ | 组内焦点移到后一个启用成员并**选中它**；末项再前进则回绕到首项 |
| Space | 按下时进入 `armed = 空格`；释放时选中当前（若未选中） |
| Enter | 不处理（不是激活键；沿祖先冒泡，可触发所在范围的默认按钮） |
| Esc | 仅 `armed = 空格` 的构建声明处理：取消，且该 Esc 不再向后传递；其余时候不声明，Esc 照常到达取消按钮 |
| Alt+助记字符 | 选中该单选框，焦点移到它，焦点变为可见 |
| Tab / Shift+Tab | 整组为**一个**停靠点（REQ-W-RADIO-010）；Tab 离开整组 |
| Home / End / PageUp / PageDown | 不处理（本控件的组不启用 Home/End） |

**REQ-W-RADIO-009**　单选组声明为漫游焦点组：`ui.focusGroup(组 ID, .{ .orientation = .both, .wrap = true, .home_end = false, .current = 当前停靠成员 })`（REQ-INPUT-038）。成员 = 组节点的全部后代中的可聚焦单选框（任意嵌套层级，如放在 Row 内）。`.both` 表示四个方向键均导航：← ↑ 为前一个，→ ↓ 为后一个。单选框自身**不**声明处理方向键（不占用 `handles.arrows`），使其落到组导航（REQ-INPUT-030）。组导航跳过禁用与隐藏的成员。

**REQ-W-RADIO-010**　整组在 Tab 序中只有**一个**停靠点：`current` 取选中的、启用的成员；没有选中成员（`*value` 不等于任何 `this_value`，或选中的成员被禁用）时取组内第一个启用的成员。成员获得焦点后即成为组的当前成员（REQ-INPUT-038），但此后若选中项变化，`current` 以新的选中项为准。`current` 的计算在组声明结束处（`endRadioGroup`）完成，因为此时全部成员已声明。

**REQ-W-RADIO-011**　Space 的选中在**释放**时发生，自动重复的 Space 按下被忽略；`armed = 空格` 期间焦点离开（Tab、方向键、鼠标点击别处、窗口失活、程序移走焦点）或单选框变为禁用时，**必须**取消，不选中。单选框经 `InteractOpts.handles` 声明处理 Space（⑤ 级），不预占，命令快捷键优先；Esc 仅在 `armed = 空格` 的那些构建中加入 `handles`，其余构建**不**声明 Esc，使 Esc 照常到达所在范围的取消按钮（REQ-INPUT-034）。

**REQ-W-RADIO-012**　**方向键移动焦点的同时选中**：单选框在 `Interaction.focus_gained` 的原因为 `group` 时，于同一次构建遍内把 `*value` 置为 `this_value` 并报告 `changed`（若此前已选中则不报告）。其他原因（`tab`、`pointer`、`programmatic`、`restore`、`transfer`、`initial`）获得焦点**不**选中。例如 Tab 进入没有选中项的组时，焦点落在第一项但不选中。

**REQ-W-RADIO-013**　助记符按 REQ-INPUT-046 解析并经 `ui.mnemonic(id, ch, .activate)` 登记；激活时聚焦并按"选中"语义处理，`activated = .mnemonic`；下划线显示遵循 REQ-INPUT-047。禁用的单选框不登记助记符。同一 Alt+字符对应多个匹配节点时只移动焦点而不激活（REQ-INPUT-048）。

## 8. 焦点

**REQ-W-RADIO-014**　单选框可聚焦；其 Tab 停靠身份完全由所在组决定（REQ-W-RADIO-010），自身的 `tab_stop` 视为假。焦点环仅在焦点可见时绘制（REQ-INPUT-040、REQ-THEME-023）；获得、失去焦点本身不产生激活类结果（选中见 REQ-W-RADIO-012）。位于组外的单选框是编程错误：调试构建断言，发布构建把它当作只有一个成员的组（自身为 Tab 停靠，点击与 Space 仍可选中）。

## 9. 文本与输入法

显示单行标签文本，不接受文本输入；聚焦时输入法处于禁用状态。

**REQ-W-RADIO-015**　标签中的换行符与制表符按 REQ-TEXT 的单行规则处理为空格；标签为空串合法（只显示圆）。

## 10. 动效

| 属性 | 触发 | 时长令牌 | 缓动 | 影响级别 |
|---|---|---|---|---|
| 容器填充与边框（常态 ↔ 悬停） | 悬停变化 | `dur_fast` | `ease_out` | paint（框架内建，`Visual.hover_t`） |
| 圆（→ 按下） | 显示为按下 | `dur_instant` | — | paint（`Visual.press_t`） |
| 圆（按下 →） | 结束按下 | `dur_fast` | `ease_out` | paint |
| 焦点环 | 焦点变为可见 | `dur_fast` 淡入，消失瞬时 | `ease_out` | paint（`Visual.focus_t`） |
| 点与圆底色（未选中 ↔ 选中） | `*value` 变化 | `dur_normal` | `ease_out` | paint（自有动画槽 0） |

**REQ-W-RADIO-016**　圆形外观：圆是边长 `check_size` 的正圆，由 `drawRadio` 绘制，是 REQ-THEME-006"圆角 > 4 lpx"的明文例外（REQ-THEME-039）。选中变化时，自有动画槽 0 以 `ui.animate(id, 0, 目标, .{ .duration = .normal, .easing = .out, .level = .paint })` 在 0 与 1 之间过渡，所得 `t` 传入 `drawRadio`：填充与边框颜色按 `t` 线性插值，圆点半径按 `t` 从 0 增至标称值；**不得**用整体透明度实现。首次出现无入场动画；选中状态与 `changed` 在事件所在帧立即生效，不等动画；系统关闭动画时直接到达目标值（REQ-FRAME-047）。动画只作用于颜色与圆点大小，不改变布局矩形。

## 11. 无障碍

| 项 | 值 |
|---|---|
| UIA 控件类型 | 单选框：RadioButton；单选组：Group |
| 名称来源 | 去除助记符标记的标签；无标签时取 `a11y_name`，再取 `tooltip`；单选组无名称（可由前置 label 经 `for_id` 关联为其 LabeledBy） |
| 支持的模式 | 单选框：SelectionItem（Select、IsSelected、SelectionContainer 指向所在组）；单选组：Selection（GetSelection；CanSelectMultiple = 假；IsSelectionRequired = 假） |
| 状态属性 | IsEnabled、HasKeyboardFocus、AccessKey（形如 "Alt+A"）、IsSelected |

**REQ-W-RADIO-017**　经 UIA SelectionItem.Select 触发的选中**必须**与 Space 激活等效：未选中时在下一帧报告一次 `changed` 且 `*value = this_value`；已选中时无变化。`IsSelected` **必须**随 `*value` 的当前值同步，包括应用直接写入的变化；组的 Selection.GetSelection 返回当前选中成员，无选中时返回空集。

## 12. API 草案

```zig
// 草案：仅签名
pub const RadioOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    size: ControlSize = .md,           // 见 button.md
    tooltip: ?[]const u8 = null,       // 借用至本帧结束；框架在需要显示时复制
    a11y_name: ?[]const u8 = null,     // 借用至本帧结束；框架复制
    layout: layout.ItemOptions = .{},  // 各控件共用（07）
};

pub const RadioResult = struct {
    // 持续性状态
    hovered: bool,
    pressed: bool,       // 即"显示为按下"
    focused: bool,
    selected: bool,      // 本次调用结束时 *value == this_value
    // 激活类结果（触发同帧第二构建遍，REQ-FRAME-030）
    changed: bool,       // 用户操作使 *value 变成了 this_value（本次调用已写入）
    activated: ?input.ActivateSource,
};

pub const RadioGroupOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    direction: layout.Orientation = .vertical,
    gap: theme.Gap = .sm,
    layout: layout.ItemOptions = .{},
};

/// 声明一个单选组（漫游焦点组）。组内的 radio 调用共享其焦点漫游与禁用。
pub fn beginRadioGroup(ui: *Ui, src: std.builtin.SourceLocation, opts: RadioGroupOptions) ui.WidgetId;
pub fn endRadioGroup(ui: *Ui) void;     // 在此计算 GroupSpec.current 并调用 ui.focusGroup（REQ-INPUT-038 补充规则：可在子项声明之后调用）

/// value：应用持有的 *T（T 为枚举或整数类型），调用方须保证存活至本次构建结束，框架不保留。
/// this_value：该单选框代表的取值（T）。value.* == this_value 即为选中。
/// 用户操作使该单选框被选中的那次调用内，控件先写入 value.* 再返回 changed = true。
/// label 借用至本帧结束；含 `&` 助记符语法。
pub fn radio(ui: *Ui, src: std.builtin.SourceLocation, label: []const u8, value: anytype, this_value: anytype, opts: RadioOptions) RadioResult;
```

按 15 的统一词汇（REQ-CONV-010），一步即完成的控件只报告 `changed`，不报告 `committed`。`changed` 是激活类结果，为真时触发同帧第二构建遍，在第二遍中为假（REQ-FRAME-033）；`hovered`、`pressed`、`focused`、`selected` 是持续性状态。控件**不**保留选中值；一组中至多一个 `selected` 为真（`*value` 与各 `this_value` 比较）。`radio` 对 `T` 使用 `anytype` 以同时接受枚举与整数，仅此两种用法。

## 13. 保留状态

| 字段 | 类型 | 保留级别 | 说明 |
|---|---|---|---|
| `armed_space` | `bool` | transient | Space 已按下待释放 |

选中值归应用所有。组节点上无状态槽；`GroupSpec.current` 每次构建重新计算（REQ-W-RADIO-010）。点的过渡进度由框架动画槽 0 保存。

## 14. 失效规则

**REQ-W-RADIO-018**　单选框的绘制键**必须**由以下各项构成：`selected`、标签文字内容、`size`、`enabled`（含继承自组的有效禁用）、标签是否被截断。助记符下划线是否显示不进入绘制键：它由绘制函数在绘制时读取，其变化按 REQ-INPUT-047 整窗置 `paint`。布局输入的内容度量键由标签文字内容、`size` 构成。组节点无绘制键（不绘制）；其布局输入由 `direction`、`gap` 构成。

| 变化 | 置脏级别 | 损伤范围 |
|---|---|---|
| 悬停进入/离开、显示为按下的变化、焦点环显隐 | `paint` | 该单选框绘制范围（含外延） |
| 鼠标按下、释放、Space、方向键（进入收件列表） | `build` | 由差分决定；若无外观变化则为空 |
| 选中项变化 | `build` | 旧选中项与新选中项两个单选框的圆的矩形，其余不受损 |
| 选中变化引起的点过渡（每个动画帧） | `paint`（动画槽 0） | 相应单选框的圆矩形 |
| 键盘提示下划线显隐（按下 Alt） | `paint`（整窗，REQ-INPUT-047）；绘制函数读取当前的键盘提示可见性 | 整窗 |

**REQ-W-RADIO-019**　仅悬停进入/离开一个单选框所产生的帧**必须**是纯绘制帧（构建遍数 0），且损伤不超出该单选框的绘制范围；选中变化引起的动画帧同样是纯绘制帧，且各帧布局矩形集合完全相同。

## 15. 边界与错误情况

| 情况 | 规定 |
|---|---|
| `*value` 不等于组内任何 `this_value` | 全部显示未选中；Tab 停靠在第一个启用成员（REQ-W-RADIO-010）；不自动写入 `*value` |
| 两个单选框的 `this_value` 相同 | 二者同时显示选中；调试构建记录一条 `warn` |
| 选中的成员被禁用 | `*value` 不变；该成员保持选中外观（禁用配方）；Tab 停靠与方向键从第一个启用成员开始 |
| 整组禁用（`enabled = false`） | 全部成员不可聚焦、不可操作；选中外观保留 |
| 组内只有一个启用成员 | 方向键无事发生（回绕到自身，不报告 `changed`） |
| 组内没有启用成员 | 组不产生 Tab 停靠；不报告任何结果 |
| 按下期间单选框从树中消失 | 捕获释放（REQ-INPUT-024），不选中 |
| 按下期间单选框变为禁用 | 取消，不选中；立即显示禁用外观 |
| 方向键选中的同一帧内应用也改写了 `*value` | 以应用最后一次写入为准；下一次构建按该值显示 |
| 单选框在同一构建中被声明多次且 ID 冲突 | 按 REQ-FRAME-005 处理（调试构建中止） |
| 窗口非活动时悬停 | 仍显示悬停外观；点击先激活窗口，该次点击照常作用于单选框 |

## 16. 验收标准

**AC-W-RADIO-001**　`[金图]` 覆盖：REQ-W-RADIO-001、REQ-W-RADIO-003、REQ-W-RADIO-004、REQ-W-RADIO-015。渲染纵向与横向两个单选组：各含 3 个选项（标签"选项一"、"保存所有更改的副本"、无标签），三档 `size` 各一组，另有一个被固定为 60 lpx 宽的长标签，并与按钮同行；缩放 1.0/1.5/2.0，浅/深。预期：与基准图一致；布局断言——无标签宽 = `check_size`；其余宽 = `check_size + gap_md + 文字宽`；纵向组内相邻项间距 = `gap_sm`；圆恒为 `check_size` 直径正圆且垂直居中；60 lpx 的标签以 `…` 结尾；标签文字基线与同行按钮文字基线在同一物理像素行（REQ-THEME-017）；组节点在节点检视中无绘制记录。

**AC-W-RADIO-002**　`[金图]` 覆盖：REQ-W-RADIO-005、REQ-W-RADIO-014、REQ-W-RADIO-016。状态矩阵：{未选中, 选中} × {常态, 悬停, 显示为按下, 焦点可见, 禁用}，浅/深/高对比度。预期：与基准图一致；显示为按下时标签不位移；`t` = 0.5 时填充色为两端颜色的线性中值（各通道误差 ≤ 1），圆点半径介于 0 与标称值之间；焦点环仅出现在"焦点可见"列；选中的禁用圆仍含点且其颜色集合 ⊆ 禁用令牌 ∪ 表面令牌；未选中无点像素；圆的外轮廓为正圆（以 8 个方向的半径相等且等于 `check_size / 2` 换算值 ±0.5 ppx 断言）。

**AC-W-RADIO-003**　`[回放]` 覆盖：REQ-W-RADIO-005、REQ-W-RADIO-006、REQ-W-RADIO-007、REQ-W-RADIO-008。三个选项 A（选中）、B、C。脚本：在 B 的标签上按下左键 → B `pressed` 真、`changed` 假、`*value` 仍为 A；移出 → `pressed` 假且 C 的 `hovered` 假；移回 → 真；释放 → 该帧 B `changed` 真、`*value = B`，下一帧假。在 B 范围外释放 → `changed` 全程假、值不变。点击已选中的 B → `changed` 假。以 50 ms 间隔在 C 上完成 3 次按下–释放 → `changed` 累计 1 次（只有第一次改变值）。右键、中键各一次 → 值不变；滚轮在可滚动容器内的单选框上滚动 → 容器偏移变化。点击 C 后 C 持有焦点、金图无焦点环；按一次 Shift 后焦点环出现；点击聚焦不触发"获得焦点即选中"（按下 C 的期间焦点已在 C，但 `*value` 在释放前仍为旧值）。指针停在单选框上记录的指针形状为箭头。

**AC-W-RADIO-004**　`[回放]` 覆盖：REQ-W-RADIO-009、REQ-W-RADIO-010、REQ-W-RADIO-012、REQ-W-RADIO-014。界面：文本框 T、含 A/B/C 的单选组（B 选中，C 被禁用）、按钮 X。连续按 Tab：序列为 T → B（组仅一次停靠）→ X；再 Shift+Tab 回到 B。B 持有焦点时：按 ↓ → 焦点跳过禁用的 C 回绕到 A，A `changed` 真、`*value = A`、A 获得焦点且焦点可见；按 → → 焦点到 B 并选中；按 ← → 回到 A；按 ↑ → 回绕到 B（跳过 C）。方向键期间每次移动恰产生一次 `changed`。Home、End、PageUp、PageDown 不改变焦点与值。将 `*value` 置为不匹配任何选项后：Tab 进入组 → 焦点落在 A 且 `*value` 不变、`changed` 假；按 Space 后释放 → A 被选中。选中项为被禁用的 C 时：Tab 停靠在 A（第一个启用成员）。组外的单选框 → 调试构建断言中止。

**AC-W-RADIO-005**　`[回放]` 覆盖：REQ-W-RADIO-011。A、B 两项，焦点在未选中的 B：`key down Space` → B `pressed` 真、`changed` 假；`key repeat VK_SPACE 5`（注入 5 次自动重复按下）→ 无变化；`key up Space` → `changed` 真恰一次、`*value = B`。再次回到 A 选中后：`key down Space` 于 B 后按 Tab → 焦点移走，`key up Space` → `changed` 假；`key down Space` 后令 B `enabled` 置假 → `pressed` 假，`key up` 后 `changed` 假；`key down Space` 后 `key down Esc` → 取消且所在对话框的取消按钮未被触发；未处于按下状态时按 Esc → 所在对话框的取消按钮被触发。Enter：焦点在单选框时按 Enter → `changed` 假，所在对话框的默认按钮被触发。

**AC-W-RADIO-006**　`[回放]` 覆盖：REQ-W-RADIO-013。标签"保存(&S)"、"跳过(&K)"（禁用）、另两个选项都带 `&M`。系统键盘提示设为"默认隐藏"：初始金图无下划线；按 Alt → S 下出现下划线；Alt+S → 该项 `changed` 真、`activated = .mnemonic`、`*value` 更新、持有焦点且焦点可见。Alt+K → 无任何 `changed`，焦点不变。Alt+M → 不改变 `*value`，焦点移到先序较前者；再按 Alt+M → 移到另一个。"A && B" 显示为 "A & B" 且未登记助记符。

**AC-W-RADIO-007**　`[回放]` 覆盖：REQ-W-RADIO-002。固定宽度导致标签截断的单选框：悬停并推进假时钟超过系统悬停时间 → 出现提示框，文本为完整标签（不含 `&`）。未截断且无 `tooltip` 的单选框同样操作 → 无提示框；给 `tooltip` → 显示调用方文本。无标签且无 `a11y_name`/`tooltip` → 调试构建产生 1 条 `warn`。

**AC-W-RADIO-008**　`[单元]` 覆盖：REQ-W-RADIO-017、REQ-W-RADIO-016。经假 UIA 入口：单选框类型 RadioButton，模式含 SelectionItem；组类型 Group，模式含 Selection（CanSelectMultiple 假、IsSelectionRequired 假）；Name 为去除助记符的标签；AccessKey 为 "Alt+S"；`IsSelected` 随 `*value`（含应用直接写入）变化；对未选中项 Select → 下一帧 `changed` 真恰一次、`*value` 更新；对已选中项 Select → 无 `changed`。系统动画开启时点击未选中项：释放所在帧 `*value` 与 `changed` 已更新；其后各动画帧传给 `drawRadio` 的 `t` 单调增加；首次渲染（含选中初值）无过渡帧。

**AC-W-RADIO-009**　`[计量]` 覆盖：REQ-W-RADIO-018、REQ-W-RADIO-019、REQ-W-RADIO-016。界面含 10 个单选组共 50 个单选框。回放：指针从空白处移入单选框 X 再移出 → 各帧构建遍数均为 0；被绘制的节点集合 ⊆ {X 及其与损伤相交的祖先}；损伤面积 ≤ X 的绘制范围面积。点击同组另一选项 Y（系统动画开启）→ 损伤 ⊆ 旧选中项与 Y 两个圆矩形之并；释放帧之后的每个动画帧构建遍数为 0、各帧布局矩形集合相同；动画结束后 `frame.count` 不再增长。系统动画关闭时同样点击 → 动画帧数为 0。仅改变 Y 的标签文字（宽度不变）并 `invalidate(.build)` → 损伤恰为 Y 矩形；以相同参数再次 `invalidate(.build)` → 损伤为空、`frame.presents` 不变。

**AC-W-RADIO-010**　`[回放]` 覆盖：REQ-W-RADIO-006、REQ-W-RADIO-011、REQ-W-RADIO-014。边界：按下期间令应用停止声明 B → 释放后无 `changed`、捕获者为空。按下期间令 B 的 `enabled` 置假 → 取消、值不变、外观立即为禁用。按下期间把 B 移动 200 lpx，在旧位置释放 → 无 `changed`。整组 `enabled = false`：Tab 序列跳过该组，方向键与点击均无效，选中项外观保留。两个选项 `this_value` 相同 → 调试构建产生 1 条 `warn`，二者同时显示选中。同一轮消息内注入"左键释放（B 内）"与方向键移到 B → 只报告一次 `changed`。

## 17. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-W-RADIO-01 | 是否提供 Home/End 到首/末项 | 不提供（对齐 Windows 单选组）；`GroupSpec.home_end = false` |
| OPEN-W-RADIO-02 | 是否允许"取消选中"（再点一次清空） | 不允许；需要时由应用增加"无"选项 |
