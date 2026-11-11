# 开关（switch）

## 1. 用途

表示一个**立即生效**的开/关设置：状态一变，应用就应当应用它，没有"确定/应用"的确认步骤。参照 Windows 11 设置页中的 ToggleSwitch。

- 设置要等用户点"确定"后才应用 → 用 checkbox。
- 从多个互斥选项中选一个 → 用 radio。
- 触发一次动作 → 用 button。
- 开关只表达二值，没有三态；需要"部分"状态时用 checkbox 的三态版本。

## 2. 解剖

```
        ┌─ 焦点环（仅焦点可见时，位于布局矩形之外）
 标签文字 (助记符)   ┌───────────┐
                     │ ▓▓ │      │  开      ← 标签 + 滑轨(含滑块) + 状态文字
                     └───────────┘
 └──────── gap_md ───┘└ gap_sm ┘
```

- **标签**（可选）：位于最左，单行文字，可含一个助记符。
- **滑轨**：`switch_w × switch_h` 的小圆角矩形（`radius_mark`），**不是**胶囊形（REQ-THEME-006）；滑轨与滑块由 `drawSwitch` 一并绘制。
- **滑块**：滑轨内的凸起方块，边长 `switch_h − 2 × 发丝线`；关时贴滑轨左端，开时贴右端。
- **状态文字**（可选）：位于滑轨之后，显示"开"或"关"。
- 标签、滑轨、状态文字共同构成**一个**交互节点；点击其中任何部分等效。

## 3. 度量与布局

| 项 | 取值（令牌） |
|---|---|
| 高度 | `control_h`（`size = .sm` 时 `control_h_sm`，`.lg` 时 `control_h_lg`） |
| 滑轨尺寸 | `switch_w` × `switch_h`，垂直居中 |
| 滑轨圆角 / 滑块圆角 | `radius_mark` / `radius_mark` |
| 滑块尺寸 | `switch_h − 2 × 发丝线` 见方（REQ-THEME-039） |
| 标签与滑轨间距 | `gap_md`（无标签时无间距） |
| 滑轨与状态文字间距 | `gap_sm`（无状态文字时无间距） |
| 文字样式 | 标签 `font_body`；状态文字 `font_body`，`text_secondary` |
| 最小宽度 | `switch_w` |
| 绘制外延 | `focus_ring_w` |

**REQ-W-SWITCH-001**　默认尺寸策略：水平方向 `fit_shrink`，垂直方向 `fixed(高度令牌)`（物理方向，由控件按 `ui.parentAxis()` 映射，见 REQ-W-LABEL-001）。调用方**可以**经通用布局选项覆盖。

**REQ-W-SWITCH-002**　适应内容时的期望宽度 = `(标签非空时 标签文字宽 + gap_md) + switch_w + (有状态文字时 gap_sm + 状态文字宽)`。状态文字宽取"开"与"关"（或调用方给出的两段文字）两者测得宽度的较大值，使切换时布局不发生变化。标签宽度不足时标签以尾部省略号截断（REQ-THEME-018），滑轨与状态文字不缩小；可用于标签的宽度不足一个字符加省略号时只显示滑轨（及状态文字）。

**REQ-W-SWITCH-003**　滑轨是小圆角矩形：外形圆角取 `radius_mark`，**不得**为胶囊形（REQ-THEME-006）；滑块同取 `radius_mark`。滑块在关/开两端的位置由 `drawSwitch` 给出：`t = 0`（关）贴滑轨内侧左端，`t = 1`（开）贴内侧右端，`t = 0.5` 居中；中间位置只在过渡动画期间出现（REQ-W-SWITCH-013）。

**REQ-W-SWITCH-004**　命中范围是整个布局矩形（标签、间距、滑轨、状态文字，不含焦点环外延）。滑轨垂直居中，标签与状态文字基线按 REQ-THEME-017 与同行其他单行控件对齐。

**REQ-W-SWITCH-005**　标签被截断时，开关**必须**在悬停时以提示框显示完整标签（去除助记符标记）；调用方另给 `tooltip` 时显示调用方的文本。无标签的开关**必须**提供 `a11y_name` 或 `tooltip`，调试构建在两者都缺失时记录一条 `warn`。

## 4. 变体与参数

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `size` | `ControlSize` | `md` | 高度档（滑轨尺寸不随档位变化） |
| `state_text` | `?SwitchStateText` | `null` | 非空时在滑轨之后显示状态文字；`.{}` 取默认的"开"/"关" |
| `tooltip` | `?[]const u8` | `null` | 提示文本 |
| `a11y_name` | `?[]const u8` | `null` | 无标签时的无障碍名称 |
| `enabled` | `bool` | `true` | |
| `key`、`debug_name`、`layout` | 通用 | | 见模板 |

`SwitchStateText = struct { on: []const u8 = "开", off: []const u8 = "关" }`。值不是选项：传 `*bool`，`true` 为开。

## 5. 状态

### 5.1 状态机

状态变量：`armed ∈ {无, 鼠标, 空格}`。悬停、聚焦、禁用由框架维护（08）；开/关由应用持有的 `*bool` 表示。

| 当前 `armed` | 事件 | 条件 | 下一 `armed` | 动作 |
|---|---|---|---|---|
| 无 | 左键按下于开关内 | 启用 | 鼠标 | 隐式捕获（REQ-INPUT-013） |
| 鼠标 | 左键释放 | 指针在命中范围内 | 无 | `*value` 取反，报告 `changed` |
| 鼠标 | 左键释放 | 指针在范围外 | 无 | 无 |
| 鼠标 | 捕获被取消（REQ-INPUT-024） | — | 无 | 无 |
| 鼠标 | 指针移动 | 捕获期间 | 鼠标 | 无（不拖动滑块，REQ-W-SWITCH-007） |
| 无 | Space 按下 | 持有焦点，非自动重复 | 空格 | 无 |
| 空格 | Space 释放 | 仍持有焦点 | 无 | `*value` 取反，报告 `changed` |
| 空格 | Esc 按下 / 失去焦点 / 变为禁用 | — | 无 | 无（取消） |
| 无 | 助记符激活 | 启用 | 无 | `*value` 取反，报告 `changed`（`activated = .mnemonic`） |
| 无 | Enter 按下 | 持有焦点 | 无 | 不处理（冒泡到默认按钮） |
| 鼠标 | Space 按下 | — | 鼠标 | 忽略 |
| 空格 | 左键按下于开关内 | — | 空格 | 忽略 |

### 5.2 视觉表现

"显示为按下" = `armed = 鼠标` 且指针在命中范围内，或 `armed = 空格`。滑轨与滑块的外观取决于 `*value` 与过渡进度 t（REQ-W-SWITCH-013，t = 0 关、t = 1 开）：

| 状态 | 绘制（基元 + 令牌） |
|---|---|
| 关 | `drawSwitch(滑轨矩形, false, t, visual)`：滑轨 `surface_track` 填充 + 顶部 `inset_shadow` + `border_control` 边框；滑块（`drawRaised(neutral)` 配方）贴内侧左端 |
| 开 | `drawSwitch(滑轨矩形, true, t, visual)`：滑轨 `accent_mark` 填充 + `accent_border` 边框；滑块贴内侧右端 |
| 悬停 | `visual.hovered` 传入 `drawSwitch`：滑块换悬停变体，关态滑轨边框换 `border_control_hover` |
| 显示为按下 | `visual.pressed` 传入 `drawSwitch`：滑块换按下变体；滑块内无内容故不位移；滑轨不变 |
| 焦点可见 | 加 `drawFocusRing(布局矩形, radius_control)` |
| 禁用 | `visual.disabled` 传入 `drawSwitch`：滑轨 `surface_sunken_disabled` + `border_control_disabled`，滑块用凸起禁用配方；开/关**仅**由滑块位置（左/右）与状态文字区分（形状，REQ-THEME-006），标签与状态文字 `text_disabled` |
| 标签 | 启用 `text_primary`，禁用 `text_disabled` |
| 状态文字 | 启用 `text_secondary`，禁用 `text_disabled` |
| 助记符下划线 | 显示时在助记字符下画发丝线（REQ-INPUT-047） |

## 6. 鼠标行为

**REQ-W-SWITCH-006**　开关登记指针兴趣 `click`。左键按下时进入 `armed = 鼠标` 并滑块立即显示为按下（`dur_instant`）；按下瞬间**不**改变值。`armed = 鼠标` 期间指针移出命中范围时恢复非按下外观，移回时再次显示为按下；期间其他控件不显示悬停（捕获语义）。`changed` **必须**在左键释放的那一帧报告，且仅当释放时指针位于命中范围内；释放时 `*value` 取反并立即写入。

**REQ-W-SWITCH-007**　**不支持拖动滑块**：按下后在命中范围内移动指针不移动滑块、不改变值；释放位置仍在命中范围内时按点击切换。开关不登记 `drag`。

**REQ-W-SWITCH-008**　快速连续点击：每一次"按下–释放"都切换一次并报告一次 `changed`，不因系统双击时间而合并或丢弃，开关不区分单击与双击。右键、中键的按下与释放不改变状态、不报告 `changed`，无上下文菜单；滚轮不处理，按 REQ-INPUT-019 冒泡；指针形状恒为箭头（REQ-THEME-032）。鼠标点击使开关获得焦点但不使焦点变为可见（REQ-INPUT-022）。

## 7. 键盘行为

| 键 | 行为 |
|---|---|
| Space | 按下时进入 `armed = 空格`；释放时切换并报告 `changed` |
| Enter | 不处理（不是激活键；沿祖先冒泡，可触发所在范围的默认按钮） |
| Esc | 仅 `armed = 空格` 的构建声明处理：取消，且该 Esc 不再向后传递；其余时候不声明，Esc 照常到达取消按钮 |
| Alt+助记字符 | 切换，报告 `changed`，焦点移到本开关，焦点变为可见 |
| ← / → | 不处理（不改变值，不移动焦点，除非开关位于漫游组内） |
| Tab / Shift+Tab | 不处理（08 的导航规则） |

**REQ-W-SWITCH-009**　Space 的切换在**释放**时发生；按下到释放之间滑块显示为按下。Space 自动重复被忽略；`armed = 空格` 期间焦点离开开关或开关变为禁用时**必须**取消，不切换。开关经 `InteractOpts.handles` 声明处理 Space（⑤ 级），**不**声明 Enter 与方向键，不预占，命令快捷键优先；Esc 仅在 `armed = 空格` 的那些构建中加入 `handles`，其余构建**不**声明 Esc，使 Esc 照常到达所在范围的取消按钮（REQ-INPUT-034）。

**REQ-W-SWITCH-010**　助记符按 REQ-INPUT-046 解析并经 `ui.mnemonic(id, ch, .activate)` 登记；下划线显示遵循 REQ-INPUT-047；禁用的开关不登记助记符；同一 Alt+字符对应多个匹配节点时只移动焦点而不激活（REQ-INPUT-048）。

## 8. 焦点

**REQ-W-SWITCH-011**　开关可聚焦且为 Tab 停靠。焦点环仅在焦点可见时绘制（REQ-INPUT-040、REQ-THEME-023）；获得、失去焦点不改变值、不产生激活类结果。

## 9. 文本与输入法

显示单行标签与可选的状态文字，不接受文本输入；聚焦时输入法处于禁用状态。

**REQ-W-SWITCH-012**　标签与状态文字中的换行符与制表符按 REQ-TEXT 的单行规则处理为空格；标签为空串合法（只显示滑轨及可选的状态文字）。`state_text` 非空时，状态文字**必须**随当前值显示 `on` 或 `off` 的文字，二者之一，不同时显示；切换发生时状态文字在释放事件所在帧立即更换（不参与动画）。

## 10. 动效

| 属性 | 触发 | 时长令牌 | 缓动 | 影响级别 |
|---|---|---|---|---|
| 滑块边框与填充（常态 ↔ 悬停） | 悬停变化 | `dur_fast` | `ease_out` | paint（框架内建，`Visual.hover_t`） |
| 滑块（→ 按下） | 显示为按下 | `dur_instant` | — | paint（`Visual.press_t`） |
| 滑块（按下 →） | 结束按下 | `dur_fast` | `ease_out` | paint |
| 焦点环 | 焦点变为可见 | `dur_fast` 淡入，消失瞬时 | `ease_out` | paint（`Visual.focus_t`） |
| 滑块位置与滑轨底色（关 ↔ 开） | `*value` 变化（用户操作或应用写入） | `dur_normal` | `ease_out` | paint（自有动画槽 0） |

**REQ-W-SWITCH-013**　值变化时，自有动画槽 0 以 `ui.animate(id, 0, 目标, .{ .duration = .normal, .easing = .out, .level = .paint })` 在 0（关）与 1（开）之间过渡，所得 `t` 传入 `drawSwitch`：滑块位置在滑轨内侧左端与右端之间随 `t` 线性移动（位移小于 16 lpx，REQ-THEME-020），滑轨填充与边框颜色按 `t` 线性插值，**不得**用整体透明度实现（REQ-THEME-039）。首次出现无入场动画（REQ-FRAME-045）；过渡期间再次切换时从当前 t 反向过渡，不跳变。动画**只**作用于滑块位置与颜色，不改变布局矩形；`changed` 与新值在释放事件所在帧立即生效，不等动画；系统关闭动画时直接到达目标值（REQ-FRAME-047）。

## 11. 无障碍

| 项 | 值 |
|---|---|
| UIA 控件类型 | Button（本地化类型名"开关"） |
| 名称来源 | 去除助记符标记的标签；无标签时取 `a11y_name`，再取 `tooltip` |
| 支持的模式 | Toggle |
| 状态属性 | IsEnabled、HasKeyboardFocus、AccessKey（形如 "Alt+W"）、ToggleState（On/Off） |

**REQ-W-SWITCH-014**　经 UIA Toggle 触发的切换**必须**与 Space 激活等效：在下一帧报告一次 `changed`，ToggleState **必须**随 `*value` 同步（含应用直接写入的变化）。UIA Toggle 由控件直接改值，理由同 REQ-W-CHECKBOX-016：值由控件写回应用提供的 `*value`。状态文字不并入 Name，而作为 Value 属性提供。

## 12. API 草案

```zig
// 草案：仅签名
pub const SwitchStateText = struct {
    on: []const u8 = "开",             // 借用至本帧结束；框架复制
    off: []const u8 = "关",
};

pub const SwitchOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    size: ControlSize = .md,           // 见 button.md
    state_text: ?SwitchStateText = null,
    tooltip: ?[]const u8 = null,       // 借用至本帧结束；框架在需要显示时复制
    a11y_name: ?[]const u8 = null,     // 借用至本帧结束；框架复制
    layout: layout.ItemOptions = .{},  // 各控件共用（07）
};

pub const SwitchResult = struct {
    // 持续性状态
    hovered: bool,
    pressed: bool,       // 即"显示为按下"
    focused: bool,
    // 激活类结果（触发同帧第二构建遍，REQ-FRAME-030）
    changed: bool,       // 用户操作使值发生了变化（本次调用已写入 *value）
    activated: ?input.ActivateSource,
};

/// value：应用持有；调用方须保证存活至本次构建结束，框架不保留。
/// 用户操作使值改变的那次调用内，控件先写入 *value 再返回 changed = true；应用应当在 changed 时立即应用该设置。
/// label 借用至本帧结束；含 `&` 助记符语法；可为空串（须提供 a11y_name 或 tooltip）。
pub fn switchBox(ui: *Ui, src: std.builtin.SourceLocation, label: []const u8, value: *bool, opts: SwitchOptions) SwitchResult;
```

函数名为 `switchBox`：`switch` 是 Zig 关键字，不能作标识符。按 15 的统一词汇（REQ-CONV-010），一步即完成的控件只报告 `changed`，不报告 `committed`。`changed` 是激活类结果，为真时触发同帧第二构建遍，在第二遍中为假（REQ-FRAME-033）；`hovered`、`pressed`、`focused` 是持续性状态。控件**不**保留开/关值。

## 13. 保留状态

| 字段 | 类型 | 保留级别 | 说明 |
|---|---|---|---|
| `armed_space` | `bool` | transient | Space 已按下待释放 |

开/关值归应用所有。滑块位置过渡由框架动画槽 0 保存（REQ-FRAME-045）；悬停/按下/焦点过渡为框架内建状态（REQ-FRAME-013）。

## 14. 失效规则

**REQ-W-SWITCH-015**　绘制键**必须**由以下各项构成：当前值、标签文字内容、`state_text` 的两段文字、`size`、`enabled`、标签是否被截断。助记符下划线是否显示不进入绘制键：它由绘制函数在绘制时读取，其变化按 REQ-INPUT-047 整窗置 `paint`。布局输入的内容度量键由标签文字内容、`state_text` 两段文字、`size` 构成。

| 变化 | 置脏级别 | 损伤范围 |
|---|---|---|
| 悬停进入/离开、显示为按下的变化、焦点环显隐 | `paint` | 开关绘制范围（含外延） |
| 鼠标按下、释放、Space（进入收件列表） | `build` | 由差分决定；若无外观变化则为空 |
| 值变化引起的滑块过渡（每个动画帧） | `paint`（动画槽 0） | 滑轨矩形 |
| 值变化引起的状态文字更换 | `build` | 状态文字矩形 |
| 标签文字变化且宽度不变 | `build`（由应用的模型通知引起） | 开关矩形 |
| 标签文字变化导致期望宽度变化 | `build` | 新旧矩形及受影响的兄弟 |
| 键盘提示下划线显隐（按下 Alt） | `paint`（整窗，REQ-INPUT-047）；绘制函数读取当前的键盘提示可见性 | 整窗 |

**REQ-W-SWITCH-016**　仅悬停进入/离开一个开关所产生的帧**必须**是纯绘制帧（构建遍数 0），且损伤不超出该开关的绘制范围；滑块过渡期间的每个动画帧同样是纯绘制帧，各帧布局矩形集合完全相同。切换值不改变期望宽度（REQ-W-SWITCH-002 的状态文字取两者较大宽度），因此切换**不得**触发布局阶段中的重新测量（`layout.measured_nodes` 不含该开关节点以外的新增项）。

## 15. 边界与错误情况

| 情况 | 规定 |
|---|---|
| 按下期间开关从树中消失 | 捕获释放（REQ-INPUT-024），不切换、不报告 `changed` |
| 按下期间开关变为禁用 | 取消，不切换；立即显示禁用外观 |
| 按下期间应用改写了 `*value` | 允许；释放时按改写后的值取反 |
| 按下期间被移动或改变尺寸 | 以释放时的新命中范围判定 |
| 同一帧内同时满足鼠标释放与 Space 释放 | 只切换一次、只报告一次 `changed` |
| 过渡期间值被应用改回 | 从当前 t 反向过渡（REQ-W-SWITCH-013） |
| 滑轨宽度小于 `switch_w`（被外部约束压缩） | 滑轨不缩小，内容越界按 REQ-LAYOUT-019 裁剪 |
| 标签为空且无 `a11y_name`/`tooltip` | 见 REQ-W-SWITCH-005 |
| 窗口非活动时悬停 | 仍显示悬停外观；点击先激活窗口，该次点击照常作用于开关 |

## 16. 验收标准

**AC-W-SWITCH-001**　`[金图]` 覆盖：REQ-W-SWITCH-001、REQ-W-SWITCH-002、REQ-W-SWITCH-003、REQ-W-SWITCH-004、REQ-W-SWITCH-012。渲染一行开关：无标签、标签"自动保存"、标签+状态文字（默认开/关）、自定义状态文字（"启用"/"停用"）、三档 `size` 各一、一个被固定为 70 lpx 宽的长标签，并与按钮、文本标签同行（文字均含"Hxg中"）；开/关各一份；缩放 1.0/1.5/2.0，浅/深。预期：与基准图一致；布局断言——无标签宽 = `switch_w`；"自动保存"宽 = 文字宽 + `gap_md` + `switch_w`；带状态文字的宽度在开与关两种值下**相同**且 = 上式 + `gap_sm` + max(两段文字宽)；滑轨恒为 `switch_w × switch_h` 且垂直居中；滑轨圆角半径 = `round(radius_mark × scale)`、小于 `switch_h` 的一半（非胶囊）；70 lpx 标签以 `…` 结尾；文字基线与同行按钮文字基线在同一物理像素行（REQ-THEME-017）。

**AC-W-SWITCH-002**　`[金图]` 覆盖：REQ-W-SWITCH-003、REQ-W-SWITCH-011。状态矩阵：{关, 开} × {常态, 悬停, 显示为按下, 焦点可见, 禁用}，浅/深/高对比度。预期：与基准图一致；关态滑块贴滑轨内侧左端，开态贴内侧右端；焦点环仅出现在"焦点可见"列；禁用态用到的颜色集合 ⊆ 禁用令牌 ∪ 表面令牌，且开/关两种禁用外观可仅凭滑块位置区分（把两张图灰度化并逐像素比较，差异像素中包含滑块位置变化）。

**AC-W-SWITCH-003**　`[回放]` 覆盖：REQ-W-SWITCH-006、REQ-W-SWITCH-007、REQ-W-SWITCH-008。脚本：在标签文字上按下左键 → `pressed` 真、`changed` 假、`*value` 不变；移出命中范围 → `pressed` 假且相邻控件 `hovered` 假；移回 → 真；释放 → 该帧 `changed` 真、`*value` 已取反，下一帧假。在滑轨上按下后水平拖动至滑轨另一端并在命中范围内释放 → 期间滑块位置不随指针变化，释放时恰切换一次。在范围外释放 → `changed` 全程假。以 50 ms 间隔完成 3 次按下–释放 → 值切换 3 次、`changed` 累计 3 次。右键、中键各一次 → 值不变；可滚动容器内的开关上滚动滚轮 → 容器偏移变化。点击后开关持有焦点、金图无焦点环；按一次 Shift 后焦点环出现。指针停在开关上记录的指针形状为箭头。

**AC-W-SWITCH-004**　`[回放]` 覆盖：REQ-W-SWITCH-009、REQ-W-SWITCH-011。Tab 聚焦；`key down Space` → `pressed` 真、`changed` 假；`key repeat VK_SPACE 5`（注入 5 次自动重复按下）→ 无变化；`key up Space` → `changed` 真恰一次、值取反。再次 `key down Space` 后按 Tab → 焦点移走，`key up Space` → `changed` 假。再次聚焦、`key down Space` 后令 `enabled` 置假 → `pressed` 假，`key up` 后 `changed` 假。启用后 `key down Space` 再 `key down Esc` → 取消，且所在对话框的取消按钮未被触发；未处于按下状态时按 Esc → 所在对话框的取消按钮被触发。Enter：焦点在开关时按 Enter → `changed` 假，所在对话框的默认按钮被触发。按 ←、→ → 值与焦点均不变。含 {文本框, 开关 A, 开关 B} 的界面连续按 Tab → 依次停靠三者。

**AC-W-SWITCH-005**　`[回放]` 覆盖：REQ-W-SWITCH-010。标签"自动保存(&A)"，另一禁用开关"离线(&O)"，另有两个开关都带 `&M`。系统键盘提示设为"默认隐藏"：初始金图无下划线；按 Alt → A 下出现下划线；Alt+A → 第一个开关 `changed` 真、`activated = .mnemonic`、值取反、持有焦点且焦点可见。Alt+O → 无任何 `changed`，焦点不变。Alt+M → 不切换任何值，焦点移到先序较前者；再按 Alt+M → 移到另一个。标签 "A && B" 显示为 "A & B" 且未登记助记符。

**AC-W-SWITCH-006**　`[回放]` 覆盖：REQ-W-SWITCH-005。固定宽度导致标签截断的开关：悬停并推进假时钟超过系统悬停时间 → 出现提示框，文本为完整标签（不含 `&`）。未截断且无 `tooltip` 的开关同样操作 → 无提示框；给 `tooltip` → 显示调用方文本。无标签且无 `a11y_name`/`tooltip` → 调试构建产生 1 条 `warn`。

**AC-W-SWITCH-007**　`[单元]` 覆盖：REQ-W-SWITCH-014、REQ-W-SWITCH-012、REQ-W-SWITCH-013。经假 UIA 入口：控件类型 Button、模式含 Toggle 且不含 Invoke；Name 为去除助记符的标签（无标签时为 `a11y_name`），AccessKey 为 "Alt+A"，Value 为当前状态文字；ToggleState 随值（含应用直接写入）为 On/Off；Toggle → 下一帧 `changed` 真恰一次且值取反。状态文字：值为真时仅显示 `on` 文字、为假时仅显示 `off` 文字。过渡：系统动画开启时点击——释放所在帧 `*value` 与 `changed` 已更新；其后各动画帧滑块位置在 [左端, 右端] 内单调变化；动画途中再点击 → 位置从当前值反向，相邻帧位置差不为跳变（≤ 单帧最大步长）；首次渲染（含开的初值）无过渡帧。

**AC-W-SWITCH-008**　`[计量]` 覆盖：REQ-W-SWITCH-015、REQ-W-SWITCH-016、REQ-W-SWITCH-013。界面含 100 个开关。回放：指针从空白处移入开关 X 再移出 → 各帧构建遍数均为 0；被绘制的节点集合 ⊆ {X 及其与损伤相交的祖先}；损伤面积 ≤ X 的绘制范围面积。点击 X（系统动画开启）→ 释放帧之后的每个动画帧构建遍数为 0、各帧布局矩形集合相同、损伤 ⊆ X 的滑轨矩形；动画结束后 `frame.count` 不再增长；X 以外节点的 `layout.measured_nodes` 增量为 0。系统动画关闭时同样点击 → 动画帧数为 0。仅改变 X 的标签文字（宽度不变）并 `invalidate(.build)` → 损伤恰为 X 矩形；以相同参数再次 `invalidate(.build)` → 损伤为空、`frame.presents` 不变。

**AC-W-SWITCH-009**　`[回放]` 覆盖：REQ-W-SWITCH-006、REQ-W-SWITCH-009。边界：按下期间令应用停止声明该开关 → 释放后值不变、无 `changed`、捕获者为空。按下期间令 `enabled` 置假 → 取消，释放后值不变，外观立即为禁用。按下期间把开关向右移动 200 lpx，在旧位置释放 → 无 `changed`。同一轮消息内注入"左键释放（开关内）"与"Space 释放"（先按下 Space）→ 值只取反一次、`changed` 累计 +1。按下期间应用把 `*value` 改写为相反值，释放 → 值取反为改写前的值。

## 17. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-W-SWITCH-01 | 标签是否可置于滑轨右侧（`label_side`） | 不提供；表单对齐用 Form 容器，开关标签留空 |
| OPEN-W-SWITCH-02 | UIA 是否需要独立的 ToggleSwitch 控件类型 | 沿用 Button + Toggle（与 WinUI ToggleSwitch 的暴露方式一致） |
| OPEN-W-SWITCH-03 | 滑块方块（`switch_h − 2 × 发丝线` 见方）视觉是否过于"块状" | M3 实机评审 |
