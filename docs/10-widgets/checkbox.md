# 复选框（checkbox）

## 1. 用途

表示一个独立的开/关选项，或一组选项中"部分选中"的汇总状态。参照 Windows 的 Button（`BS_CHECKBOX` / `BS_AUTOCHECKBOX` / `BS_3STATE`）。

- 立即生效的设置（点一下就应用）→ 用 switch；复选框用于"设置一批值之后再确认"的表单与列表勾选。
- 从多个互斥选项中选一个 → 用 radio。
- 触发动作 → 用 button；仅工具栏里的"锁定态"按钮可用 button 的 `checked`。
- 三态版本只用于父项汇总子项（如"全选"）或"未指定"状态；普通选项**不应**使用三态。

## 2. 解剖

```
        ┌─ 焦点环（仅焦点可见时，位于布局矩形之外）
 ┌────┐
 │ ✓  │  标签文字(助记符下划线)          ← 方框 + 标签；整体是一个点击目标
 └────┘
  方框   └ gap_md ┘
```

- **方框**：`check_size` 见方、圆角 `radius_mark` 的方框，由 `drawCheckBox` 绘制；内部为**标记**（勾 / 横线）。
- **标签**（可选）：单行文字，可含一个助记符。
- 方框与标签共同构成**一个**交互节点；点击标签与点击方框等效。

## 3. 度量与布局

| 项 | 取值（令牌） |
|---|---|
| 高度 | `control_h`（`size = .sm` 时 `control_h_sm`，`.lg` 时 `control_h_lg`） |
| 方框尺寸 | `check_size`，垂直居中，左缘贴节点左缘 |
| 方框圆角 | `radius_mark` |
| 方框与标签间距 | `gap_md` |
| 标签样式 | `font_body` |
| 最小宽度 | `check_size`（无标签时即方框宽） |
| 绘制外延 | `focus_ring_w` |

**REQ-W-CHECKBOX-001**　默认尺寸策略：水平方向 `fit_shrink`，垂直方向 `fixed(高度令牌)`（物理方向，由控件按 `ui.parentAxis()` 映射，见 REQ-W-LABEL-001）。调用方**可以**经通用布局选项覆盖。

**REQ-W-CHECKBOX-002**　适应内容时的期望宽度 = `check_size + (标签非空时 gap_md + 标签文字宽)`，文字宽为去除助记符标记后的文本以 `font_body` 测得的宽度（单行，换行符与制表符按空格）。标签宽度不足时以尾部省略号截断（REQ-THEME-018），方框不缩小；可用于文字的宽度不足一个字符加省略号时只显示方框。

**REQ-W-CHECKBOX-003**　标签文字被截断时，复选框**必须**在悬停时以提示框显示完整文字（去除助记符标记）；调用方另给 `tooltip` 时显示调用方的文本。无标签的复选框**必须**提供 `a11y_name` 或 `tooltip`，调试构建在两者都缺失时记录一条 `warn`。

**REQ-W-CHECKBOX-004**　命中范围是整个布局矩形（方框、间距与标签，不含焦点环外延）。方框与标签垂直居中，标签文字基线按 REQ-THEME-017 与同行其他单行控件对齐。

## 4. 变体与参数

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `size` | `ControlSize` | `md` | 高度档（方框尺寸不随档位变化） |
| `tooltip` | `?[]const u8` | `null` | 提示文本 |
| `a11y_name` | `?[]const u8` | `null` | 无标签时的无障碍名称 |
| `enabled` | `bool` | `true` | |
| `key`、`debug_name`、`layout` | 通用 | | 见模板 |

值不是选项：二值版本传 `*bool`，三值版本传 `*CheckState`（`enum { off, on, mixed }`）。变体只有这两个函数的区别，没有外观变体。

## 5. 状态

### 5.1 状态机

状态变量：`armed ∈ {无, 鼠标, 空格}`（是否处于"已按下待切换"）。悬停、聚焦、禁用由框架维护（08）；勾选值由应用持有的 `*bool`/`*CheckState` 表示，不是控件状态。

| 当前 `armed` | 事件 | 条件 | 下一 `armed` | 动作 |
|---|---|---|---|---|
| 无 | 左键按下于复选框内 | 启用 | 鼠标 | 隐式捕获（REQ-INPUT-013） |
| 鼠标 | 左键释放 | 指针在命中范围内 | 无 | 切换值，报告 `changed` |
| 鼠标 | 左键释放 | 指针在范围外 | 无 | 无 |
| 鼠标 | 捕获被取消（REQ-INPUT-024） | — | 无 | 无 |
| 无 | Space 按下 | 持有焦点，非自动重复 | 空格 | 无 |
| 空格 | Space 释放 | 仍持有焦点 | 无 | 切换值，报告 `changed` |
| 空格 | Esc 按下 / 失去焦点 / 变为禁用 | — | 无 | 无（取消） |
| 无 | 助记符激活 | 启用 | 无 | 切换值，报告 `changed`（`activated = .mnemonic`） |
| 无 | Enter 按下 | 持有焦点 | 无 | 不处理（冒泡到默认按钮，REQ-INPUT-034） |
| 鼠标 | Space 按下 | — | 鼠标 | 忽略 |
| 空格 | 左键按下于复选框内 | — | 空格 | 忽略 |

值的转移（切换值时）：

| 当前值 | 切换后 |
|---|---|
| `false` / `off` | `true` / `on` |
| `true` / `on` | `false` / `off` |
| `mixed` | `on` |

用户操作**永不**产生 `mixed`；`mixed` 只能由应用写入。

### 5.2 视觉表现

"显示为按下" = `armed = 鼠标` 且指针在命中范围内，或 `armed = 空格`。方框随值与状态绘制：

| 状态 | 绘制（基元 + 令牌） |
|---|---|
| 未勾选（`off`） | 方框 `drawCheckBox(方框矩形, off, t, visual)`：`drawSunken` 配方（`surface_sunken` 填充、`border_control` 边框），无标记 |
| 已勾选（`on`） | `drawCheckBox(方框矩形, on, t, visual)`：`accent_fill_top → accent_fill_bottom` 渐变填充、`accent_border` 边框，`text_on_accent` 的 `check` 标记 |
| 部分选中（`mixed`） | `drawCheckBox(方框矩形, mixed, t, visual)`：填充与边框同 `on`，`text_on_accent` 的 `indeterminate` 标记 |
| 悬停 | 方框换悬停变体（边框 `border_control_hover` / 强调色悬停变体） |
| 显示为按下 | `visual.pressed` 传入 `drawCheckBox`，由其配方给出按下外观（REQ-THEME-039）；标签不位移 |
| 焦点可见 | 加 `drawFocusRing(布局矩形, radius_control)` |
| 禁用 | 方框禁用配方（`surface_raised_disabled` + `border_control_disabled`，无体积感），标记 `text_disabled`，标签 `text_disabled`；已勾选的禁用方框**仍**绘制标记，用形状表示值（REQ-THEME-006） |
| 标签 | 启用 `text_primary`，禁用 `text_disabled` |
| 助记符下划线 | 显示时在助记字符下画发丝线（REQ-INPUT-047） |

## 6. 鼠标行为

**REQ-W-CHECKBOX-005**　复选框登记指针兴趣 `click`。左键按下时进入 `armed = 鼠标` 并立即显示为按下（`dur_instant`）；按下瞬间**不**改变值、不报告 `changed`。

**REQ-W-CHECKBOX-006**　`armed = 鼠标` 期间，指针移出命中范围时恢复非按下外观，移回时再次显示为按下；期间其他控件不显示悬停（捕获语义）。`changed` **必须**在左键释放的那一帧报告，且仅当释放时指针位于命中范围内。

**REQ-W-CHECKBOX-007**　快速连续点击：每一次"按下–释放"都切换一次值并报告一次 `changed`，不因落入系统双击时间而合并或丢弃，复选框不区分单击与双击。

**REQ-W-CHECKBOX-008**　右键、中键的按下与释放不改变状态、不报告 `changed`；复选框本身无上下文菜单。滚轮不处理，按 REQ-INPUT-019 冒泡。指针形状恒为箭头（REQ-THEME-032）。

**REQ-W-CHECKBOX-009**　鼠标点击使复选框获得焦点（点击聚焦，REQ-INPUT-022），但不使焦点变为可见。

## 7. 键盘行为

| 键 | 行为 |
|---|---|
| Space | 按下时进入 `armed = 空格` 并显示为按下；释放时切换值并报告 `changed` |
| Enter | 不处理（不是激活键；沿祖先冒泡，可触发所在范围的默认按钮） |
| Esc | 仅 `armed = 空格` 的构建声明处理：取消，且该 Esc 不再向后传递；其余时候不声明，Esc 照常到达取消按钮 |
| Alt+助记字符 | 切换值，报告 `changed`，焦点移到本复选框，焦点变为可见 |
| Tab / Shift+Tab / 方向键 | 不处理（由 08 的导航规则处理）；复选框不是漫游组成员 |

**REQ-W-CHECKBOX-010**　Space 的切换在**释放**时发生；按下到释放之间显示为按下。Space 的自动重复按下被忽略。复选框经 `InteractOpts.handles` 声明处理 Space（⑤ 级），**不**声明 Enter，不预占，因此命令快捷键优先；Esc 仅在 `armed = 空格` 的那些构建中加入 `handles`，其余构建**不**声明 Esc，使 Esc 照常到达所在范围的取消按钮（REQ-INPUT-034）。

**REQ-W-CHECKBOX-011**　`armed = 空格` 期间焦点离开复选框（Tab、鼠标点击别处、窗口失活、程序移走焦点）或复选框变为禁用时，**必须**取消，不切换、不报告 `changed`。

**REQ-W-CHECKBOX-012**　助记符按 REQ-INPUT-046 解析并经 `ui.mnemonic(id, ch, .activate)` 登记；下划线显示遵循 REQ-INPUT-047。禁用的复选框不登记助记符。同一 Alt+字符对应多个匹配节点时只移动焦点而不激活（REQ-INPUT-048）。

## 8. 焦点

**REQ-W-CHECKBOX-013**　复选框可聚焦且为 Tab 停靠。焦点环仅在焦点可见时绘制（REQ-INPUT-040、REQ-THEME-023）；获得、失去焦点不改变值、不产生激活类结果。

## 9. 文本与输入法

显示单行标签文本，不接受文本输入；聚焦时输入法处于禁用状态。

**REQ-W-CHECKBOX-014**　标签中的换行符与制表符按 REQ-TEXT 的单行规则处理为空格；标签为空串合法（只显示方框）。

## 10. 动效

| 属性 | 触发 | 时长令牌 | 缓动 | 影响级别 |
|---|---|---|---|---|
| 容器填充与边框（常态 ↔ 悬停） | 悬停变化 | `dur_fast` | `ease_out` | paint（框架内建，`Visual.hover_t`） |
| 方框（→ 按下） | 显示为按下 | `dur_instant` | — | paint（`Visual.press_t`） |
| 方框（按下 →） | 结束按下 | `dur_fast` | `ease_out` | paint |
| 焦点环 | 焦点变为可见 | `dur_fast` 淡入，消失瞬时 | `ease_out` | paint（`Visual.focus_t`） |
| 勾选标记与方框底色（未勾选 ↔ 勾选/部分选中） | 值变化（用户操作或应用写入） | `dur_normal` | `ease_out` | paint（自有动画槽 0） |

**REQ-W-CHECKBOX-015**　值变化时，自有动画槽 0 以 `ui.animate(id, 0, 目标, .{ .duration = .normal, .easing = .out, .level = .paint })` 在 0（未勾选）与 1（已勾选或部分选中）之间过渡，所得 `t` 作为 `drawCheckBox` 的过渡进度传入：填充与边框颜色在 `off` 与 `on` 之间按 `t` 线性插值，标记按笔画长度的前 `t` 比例显现；**不得**用整体透明度实现（REQ-THEME-039）。首次出现的复选框无入场动画（REQ-FRAME-045）；`mixed ↔ on` 之间只切换标记形状，不经过未勾选（`t` 保持 1）。动画**只**作用于颜色与标记显现，不改变布局矩形（REQ-THEME-020）；`changed` 与新值**必须**在释放事件所在帧立即生效，不等动画。系统关闭动画时直接到达目标值（REQ-FRAME-047）。

## 11. 无障碍

| 项 | 值 |
|---|---|
| UIA 控件类型 | CheckBox |
| 名称来源 | 去除助记符标记的标签；无标签时取 `a11y_name`，再取 `tooltip` |
| 支持的模式 | Toggle |
| 状态属性 | IsEnabled、HasKeyboardFocus、AccessKey（形如 "Alt+S"）、ToggleState（`off`/`on`/`indeterminate` 对应 Off/On/Indeterminate） |

**REQ-W-CHECKBOX-016**　经 UIA Toggle 触发的切换**必须**与 Space 激活等效：值按 5.1 的转移表变化并在下一帧报告一次 `changed`；UIA 对 `mixed` 执行 Toggle 得到 `on`。ToggleState **必须**随 `*bool`/`*CheckState` 的当前值同步，包括应用直接写入的变化。UIA Toggle 由控件直接改值（而不是只报告 `clicked`，与 button 的 REQ-W-BUTTON-021 对照），理由是勾选值由控件写回应用提供的 `*bool`/`*CheckState`，同一次调用内先写入再返回 `changed`，键盘、鼠标、UIA 三条路径的写回行为因此一致。

## 12. API 草案

```zig
// 草案：仅签名
pub const CheckState = enum { off, on, mixed };

pub const CheckboxOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    size: ControlSize = .md,           // 见 button.md
    tooltip: ?[]const u8 = null,       // 借用至本帧结束；框架在需要显示时复制
    a11y_name: ?[]const u8 = null,     // 借用至本帧结束；框架复制
    layout: layout.ItemOptions = .{},  // 各控件共用（07）
};

pub const CheckboxResult = struct {
    // 持续性状态
    hovered: bool,
    pressed: bool,       // 即"显示为按下"
    focused: bool,
    // 激活类结果（触发同帧第二构建遍，REQ-FRAME-030）
    changed: bool,       // 用户操作使值发生了变化（本次调用已写入 *value）
    activated: ?input.ActivateSource,   // changed 由助记符机制触发时非空
};

/// value：应用持有；调用方须保证存活至本次构建结束，框架不保留。
/// 用户操作使值改变的那次调用内，控件先写入 *value 再返回 changed = true，
/// 使应用在同一构建遍之后的代码与第二构建遍中读到新值。label 借用至本帧结束；含 `&` 助记符语法。
pub fn checkbox(ui: *Ui, src: std.builtin.SourceLocation, label: []const u8, value: *bool, opts: CheckboxOptions) CheckboxResult;

/// 三态版本。点击 mixed → on；用户操作永不产生 mixed。
pub fn checkboxTri(ui: *Ui, src: std.builtin.SourceLocation, label: []const u8, value: *CheckState, opts: CheckboxOptions) CheckboxResult;
```

按 15 的统一词汇（REQ-CONV-010），一步即完成的控件只报告 `changed`，不报告 `committed`。`changed` 是激活类结果，为真时触发同帧第二构建遍，在第二遍中为假（REQ-FRAME-033）；`hovered`、`pressed`、`focused` 是持续性状态。控件**不**保留勾选值：每次调用读取 `*value` 作为当前值；应用在 `changed` 之外对 `*value` 的写入（如"全选"）在下一次构建中显示。

## 13. 保留状态

| 字段 | 类型 | 保留级别 | 说明 |
|---|---|---|---|
| `armed_space` | `bool` | transient | Space 已按下待释放 |

勾选值归应用所有，不在状态槽中。标记过渡的进度由框架的动画槽 0 保存（框架内建每节点状态，REQ-FRAME-045）；悬停/按下/焦点过渡为框架内建状态（REQ-FRAME-013）。

## 14. 失效规则

**REQ-W-CHECKBOX-017**　绘制键**必须**由以下各项构成：当前值（`off`/`on`/`mixed`）、标签文字内容、`size`、`enabled`、标签是否被截断。助记符下划线是否显示不进入绘制键：它由绘制函数在绘制时读取，其变化按 REQ-INPUT-047 整窗置 `paint`。布局输入的内容度量键由标签文字内容、`size` 构成。

| 变化 | 置脏级别 | 损伤范围 |
|---|---|---|
| 悬停进入/离开、显示为按下的变化、焦点环显隐 | `paint` | 复选框绘制范围（含外延） |
| 鼠标按下、释放、Space（进入收件列表） | `build` | 由差分决定；若无外观变化则为空 |
| 值变化引起的标记过渡（每个动画帧） | `paint`（动画槽 0） | 方框矩形 |
| 标签文字变化且宽度不变 | `build`（由应用的模型通知引起） | 复选框矩形 |
| 标签文字变化导致期望宽度变化 | `build` | 新旧矩形及受影响的兄弟 |
| 键盘提示下划线显隐（按下 Alt） | `paint`（整窗，REQ-INPUT-047）；绘制函数读取当前的键盘提示可见性 | 整窗 |

**REQ-W-CHECKBOX-018**　仅悬停进入/离开一个复选框所产生的帧**必须**是纯绘制帧（构建遍数 0），且损伤不超出该复选框的绘制范围；标记过渡期间的每个动画帧同样是纯绘制帧，且各帧的布局矩形集合完全相同。

## 15. 边界与错误情况

| 情况 | 规定 |
|---|---|
| 按下期间复选框从树中消失 | 捕获释放（REQ-INPUT-024），不切换、不报告 `changed` |
| 按下期间复选框变为禁用 | 取消，不切换；立即显示禁用外观 |
| 按下期间应用改写了 `*value` | 允许；释放时按改写后的值切换 |
| 按下期间被移动或改变尺寸 | 以释放时的新命中范围判定 |
| 同一帧内同时满足鼠标释放与 Space 释放 | 只切换一次、只报告一次 `changed` |
| 标签为空且无 `a11y_name`/`tooltip` | 见 REQ-W-CHECKBOX-003 |
| `*CheckState` 的值非法（越过枚举范围） | 按 `off` 显示；调试构建断言 |
| 禁用的复选框持有 `mixed` | 显示禁用的部分选中外观（横线），不可操作 |
| 窗口非活动时悬停 | 仍显示悬停外观；点击先激活窗口，该次点击照常作用于复选框 |

## 16. 验收标准

**AC-W-CHECKBOX-001**　`[金图]` 覆盖：REQ-W-CHECKBOX-001、REQ-W-CHECKBOX-002、REQ-W-CHECKBOX-004、REQ-W-CHECKBOX-014。渲染一行复选框：无标签、标签"启用"、标签"保存所有更改的副本"、三档 `size` 各一、一个被固定为 60 lpx 宽的长标签，并与按钮、文本标签同行（文字均含"Hxg中"）；缩放 1.0/1.5/2.0，浅/深。预期：与基准图一致；布局断言——无标签宽 = `check_size`；"启用"宽 = `check_size + gap_md + 文字宽`；各档高度等于令牌；方框恒为 `check_size` 见方且垂直居中；60 lpx 的标签以 `…` 结尾；文字基线与同行按钮的文字基线在同一物理像素行（REQ-THEME-017）。

**AC-W-CHECKBOX-002**　`[金图]` 覆盖：REQ-W-CHECKBOX-005、REQ-W-CHECKBOX-013。状态矩阵：{未勾选, 已勾选, 部分选中} × {常态, 悬停, 显示为按下, 焦点可见, 禁用}，浅/深/高对比度。预期：与基准图一致；显示为按下时标签不位移；`t` = 0.5 时填充色为两端颜色的线性中值（各通道误差 ≤ 1）且画面中无整体半透明混合产生的颜色；焦点环仅出现在"焦点可见"列；已勾选的禁用方框仍含勾，且其用到的颜色集合 ⊆ 禁用令牌 ∪ 表面令牌；未勾选无任何标记像素。

**AC-W-CHECKBOX-003**　`[回放]` 覆盖：REQ-W-CHECKBOX-005、REQ-W-CHECKBOX-006、REQ-W-CHECKBOX-007、REQ-W-CHECKBOX-008、REQ-W-CHECKBOX-009。脚本：在标签文字上按下左键 → `pressed` 真、`changed` 假、`*value` 不变；移出命中范围 → `pressed` 假且相邻控件 `hovered` 假；移回 → `pressed` 真；释放 → 该帧 `changed` 真、`*value` 已翻转，下一帧 `changed` 假。在方框上按下、在范围外释放 → `changed` 全程为假、值不变。以 50 ms 间隔完成 3 次按下–释放 → 值翻转 3 次、`changed` 累计 3 次。右键、中键各一次 → 值不变、`changed` 不变；在可滚动容器内的复选框上滚动滚轮 → 容器偏移变化。点击后复选框持有焦点、金图无焦点环；按一次 Shift 后焦点环出现。指针停在复选框上记录的指针形状为箭头。

**AC-W-CHECKBOX-004**　`[回放]` 覆盖：REQ-W-CHECKBOX-010、REQ-W-CHECKBOX-011、REQ-W-CHECKBOX-013。Tab 聚焦；`key down Space` → `pressed` 真、`changed` 假；`key repeat VK_SPACE 5`（注入 5 次自动重复按下）→ 无变化；`key up Space` → `changed` 真恰一次、值翻转。再次 `key down Space` 后按 Tab → 焦点移走，`key up Space` → `changed` 假。再次聚焦、`key down Space` 后令 `enabled` 置假 → `pressed` 假，`key up` 后 `changed` 假。启用后 `key down Space` 再 `key down Esc` → 取消，且所在对话框的取消按钮未被触发；未处于按下状态时按 Esc → 所在对话框的取消按钮被触发。Enter：焦点在复选框时按 Enter → 复选框 `changed` 假，所在对话框的默认按钮被触发（`activated = .default_button`）。对含 {文本框, 复选框 A, 复选框 B} 的界面连续按 Tab，断言停靠序列依次经过三者，且方向键不在 A、B 之间移动焦点。

**AC-W-CHECKBOX-005**　`[回放]` 覆盖：REQ-W-CHECKBOX-012。标签"保存(&S)"，另一禁用复选框"跳过(&K)"，另有两个复选框都带 `&M`。系统键盘提示设为"默认隐藏"：初始金图无下划线；按 Alt → S 下出现下划线；Alt+S → 第一个复选框 `changed` 真、`activated = .mnemonic`、值翻转、持有焦点且焦点可见。Alt+K → 无任何 `changed`，焦点不变。Alt+M → 不切换任何值，焦点移到先序较前者；再按 Alt+M → 焦点移到另一个，值均未变。标签 "A && B" 显示为 "A & B" 且未登记助记符。

**AC-W-CHECKBOX-006**　`[回放]` 覆盖：REQ-W-CHECKBOX-016、REQ-W-CHECKBOX-015、REQ-W-CHECKBOX-005。三态：初始 `off`，点击 → `on`；点击 → `off`；应用写入 `mixed` 后（金图显示横线）点击 → `on`（不经过 `off`）；`changed` 每次为真且 `*value` 为新值；任何用户操作序列（20 次随机点击/Space 释放）后 `*value` 永不为 `mixed`。二值版本等价。系统动画开启时点击：释放所在帧的 `*value` 与 `changed` 已更新；随后各动画帧传给 `drawCheckBox` 的 `t` 单调增加；首次渲染（含已勾选的初值）无过渡帧；`mixed → on` 的过渡期间方框保持强调色底。

**AC-W-CHECKBOX-007**　`[回放]` 覆盖：REQ-W-CHECKBOX-003。固定宽度导致标签截断的复选框：悬停并推进假时钟超过系统悬停时间 → 出现提示框，文本为完整标签（不含 `&`）。未截断且未给 `tooltip` 的复选框同样操作 → 无提示框。给 `tooltip` → 显示调用方文本。无标签且无 `a11y_name`/`tooltip` → 调试构建产生 1 条 `warn`。

**AC-W-CHECKBOX-008**　`[单元]` 覆盖：REQ-W-CHECKBOX-016、REQ-W-CHECKBOX-014。经假 UIA 入口：控件类型 CheckBox，模式含 Toggle 且不含 Invoke；Name 为去除助记符的标签（无标签时为 `a11y_name`），AccessKey 为 "Alt+S"；ToggleState 随值（含应用直接写入）为 Off/On/Indeterminate；对 Off 执行 Toggle → 下一帧 `changed` 真恰一次且 `*value` 为 `on`；对 Indeterminate 执行 Toggle → `on`。标签含 `\n`、`\t` → 渲染为单行、期望高度不变；空标签 → 仅方框、宽度 = `check_size`。

**AC-W-CHECKBOX-009**　`[计量]` 覆盖：REQ-W-CHECKBOX-017、REQ-W-CHECKBOX-018、REQ-W-CHECKBOX-015。界面含 100 个复选框。回放：指针从空白处移入复选框 X 再移出 → 各帧构建遍数为 0；被绘制的节点集合 ⊆ {X 及其与损伤相交的祖先}；损伤面积 ≤ X 的绘制范围面积。点击 X（系统动画开启）→ 释放帧之后的每个动画帧构建遍数为 0、每帧布局矩形集合相同、损伤 ⊆ X 的方框矩形；动画结束后 `frame.count` 不再增长。系统动画关闭时同样点击 → 动画帧数为 0。仅改变 X 的标签文字（宽度不变）并 `invalidate(.build)` → 损伤恰为 X 矩形；以相同参数再次 `invalidate(.build)` → 损伤为空、`frame.presents` 不变。

**AC-W-CHECKBOX-010**　`[回放]` 覆盖：REQ-W-CHECKBOX-006、REQ-W-CHECKBOX-011。边界：按下期间令应用停止声明该复选框 → 释放后值不变、无 `changed`、捕获者为空。按下期间令 `enabled` 置假 → 取消，释放后值不变，且外观立即为禁用。按下期间把复选框向右移动 200 lpx，在旧位置释放 → 无 `changed`。同一轮消息内注入"左键释放（复选框内）"与"Space 释放"（先按下 Space）→ 值只翻转一次、`changed` 累计 +1。按下期间应用把 `*value` 改写为相反值，释放 → 值翻转为改写前的值。

## 17. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-W-CHECKBOX-01 | 是否在三态复选框上允许用户点击产生 `mixed`（如循环 off → on → mixed） | 不允许（点击 mixed → on，用户操作永不产生 mixed）；`mixed` 只能由应用写入 |
| OPEN-W-CHECKBOX-02 | 焦点环围绕整个节点矩形（方框 + 标签）还是仅标签文字 | 取整个节点矩形，命中范围与焦点范围一致；M3 实机评审 |
