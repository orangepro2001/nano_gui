# 按钮（button）

> 本文是控件规范的范本。其余控件文档的详略、条款粒度与验收写法以本文为准。

## 1. 用途

触发一个立即执行的动作。参照 Windows 的 Button（`BS_PUSHBUTTON` / `BS_DEFPUSHBUTTON`）与工具栏按钮。

- 在两个状态间切换且状态需要持续可见 → 用 checkbox 或 switch；仅工具栏里的"锁定态"按钮可用本控件的 `checked` 参数。
- 导航到别处 → 用链接样式的 label。
- 从多个动作中选一个 → 用 menu 或 combo-box。

## 2. 解剖

```
        ┌─ 焦点环（仅焦点可见时，位于容器之外）
┌───────────────────────────┐
│ ▓ 图标   文字(助记符下划线) │   容器 = drawRaised
└───────────────────────────┘
  └ pad_control_x          ┘
```

- **容器**：凸起表面。
- **图标**（可选）：位于文字之前。
- **文字**（可选）：单行；可含一个助记符。
- 图标与文字至少有其一。

## 3. 度量与布局

| 项 | 取值（令牌） |
|---|---|
| 高度 | `control_h`（`size = .sm` 时 `control_h_sm`，`.lg` 时 `control_h_lg`） |
| 最小宽度 | 有文字：`button_min_w`；仅图标：等于高度（正方形） |
| 左右内边距 | 有文字：`pad_control_x`；仅图标：居中，无内边距要求 |
| 图标尺寸 | `icon_sm` |
| 图标与文字间距 | `gap_sm` |
| 文字样式 | `font_body`；`variant = .accent` 时 `font_body_strong` |
| 绘制外延 | `focus_ring_w` |

**REQ-W-BUTTON-001**　默认尺寸策略：主轴 `fit`，交叉轴 `fixed(高度令牌)`。调用方**可以**经通用布局选项改为 `fixed` 或 `grow`。

**REQ-W-BUTTON-002**　适应内容时的期望宽度：有文字时 = `max(button_min_w, 2 × pad_control_x + 图标宽 + (图标与文字并存时 gap_sm) + 文字宽)`，其中文字宽为去除助记符标记后的文本以所用字体样式测得的宽度；仅图标时 = 高度令牌（正方形），不套用该公式。换算到物理像素按 REQ-LAYOUT-014 的规则。

**REQ-W-BUTTON-003**　内容（图标 + 间距 + 文字）作为一个整体在容器内水平居中、垂直按 REQ-THEME-017 放置。实际宽度小于期望宽度时，文字以尾部省略号截断（REQ-THEME-018），图标不缩小；可用于文字的宽度不足一个字符加省略号时只显示图标（若有）或只显示省略号。

**REQ-W-BUTTON-004**　文字被截断时，按钮**必须**在悬停时以提示框显示完整文字（去除助记符标记）；调用方另行给出 `tooltip` 时显示调用方的文本。仅图标的按钮**必须**提供 `tooltip`（REQ-THEME-006），调试构建在缺失时记录一条 `warn`。

## 4. 变体与参数

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `variant` | `enum { neutral, accent, quiet }` | `neutral` | `accent`：强调色填充，表示所在范围的首要动作，一个对话框/面板内至多一个；`quiet`：安静凸起（REQ-THEME-031），仅用于工具栏与行内操作 |
| `size` | `enum { sm, md, lg }` | `md` | 高度档 |
| `icon` | `?theme.Icon` | `null` | 前置图标 |
| `checked` | `?bool` | `null` | 非空时为"锁定态"按钮：`true` 以按下外观常驻显示。点击不自动翻转，由应用在 `clicked` 时更新自己的状态 |
| `tooltip` | `?[]const u8` | `null` | 提示文本 |
| `enabled` | `bool` | `true` | |
| `key`、`debug_name` | 通用 | | 见模板 |

"默认按钮"（Enter 触发）不是按钮的参数，而是由所在焦点范围指定（`ScopeSpec.default_button`，REQ-INPUT-034）。被指定为默认按钮的按钮**应当**使用 `accent` 变体。

## 5. 状态

### 5.1 状态机

状态变量：`armed ∈ {无, 鼠标, 空格}`（是否处于"已按下待释放"）。悬停、聚焦、禁用由框架维护（08）。

| 当前 `armed` | 事件 | 条件 | 下一 `armed` | 动作 |
|---|---|---|---|---|
| 无 | 左键按下于按钮内 | 启用 | 鼠标 | 隐式捕获（REQ-INPUT-013） |
| 鼠标 | 左键释放 | 指针在按钮命中范围内 | 无 | 报告 `clicked` |
| 鼠标 | 左键释放 | 指针在范围外 | 无 | 无 |
| 鼠标 | 捕获被取消（REQ-INPUT-024） | — | 无 | 无 |
| 无 | Space 按下 | 持有焦点，非自动重复 | 空格 | 无 |
| 空格 | Space 释放 | 仍持有焦点 | 无 | 报告 `clicked` |
| 空格 | Esc 按下 / 失去焦点 / 变为禁用 | — | 无 | 无（取消） |
| 无 | Enter 按下 | 持有焦点，非自动重复 | 无 | 报告 `clicked` |
| 无 | 助记符激活 / 作为默认按钮被 Enter 触发 | 启用 | 无 | 报告 `clicked`（`activated` 非空） |
| 鼠标 | Space/Enter 按下 | — | 鼠标 | 忽略 |
| 空格 | 左键按下于按钮内 | — | 空格 | 忽略 |

### 5.2 视觉表现

"显示为按下" = `armed = 鼠标` 且指针在命中范围内，或 `armed = 空格`，或 `checked = true`。

| 状态 | 绘制（基元 + 令牌） |
|---|---|
| 常态 | `neutral`：`drawRaised(neutral)`，文字/图标 `text_primary`。`accent`：`drawRaised(accent)`，文字/图标 `text_on_accent`。`quiet`：不画容器，文字/图标 `text_primary` |
| 悬停 | 容器换悬停变体（`quiet` 此时才画出 `neutral` 容器） |
| 显示为按下 | 容器换按下变体；内容下移 1 ppx（REQ-THEME-030） |
| `checked = true` 且未被按住 | 同"显示为按下"，但内容不下移 |
| 焦点可见 | 加 `drawFocusRing` |
| 禁用 | 容器禁用配方（`quiet` 不画容器），文字/图标 `text_disabled` |

## 6. 鼠标行为

**REQ-W-BUTTON-005**　按钮登记指针兴趣 `click`。左键按下时进入 `armed = 鼠标` 并立即显示为按下（`dur_instant`）。

**REQ-W-BUTTON-006**　`armed = 鼠标` 期间，指针移出命中范围时按钮恢复为非按下外观，移回时再次显示为按下；期间其他控件不显示悬停（捕获语义）。

**REQ-W-BUTTON-007**　`clicked` **必须**在左键释放的那一帧报告，且仅当释放时指针位于命中范围内。按下瞬间不报告。

**REQ-W-BUTTON-008**　命中范围是按钮的布局矩形（不含焦点环外延，不因圆角而排除四角）。

**REQ-W-BUTTON-009**　快速连续点击：每一次"按下–释放"都报告一次 `clicked`，不因落入系统双击时间而合并或丢弃。按钮不区分单击与双击。

**REQ-W-BUTTON-010**　右键、中键的按下与释放不改变按钮状态、不报告 `clicked`；按钮本身无上下文菜单。滚轮事件不处理，按 REQ-INPUT-019 冒泡。

**REQ-W-BUTTON-011**　鼠标点击可使按钮获得焦点（点击聚焦，REQ-INPUT-022），但不使焦点变为可见。`quiet` 变体**不得**因鼠标点击取得焦点（工具栏按钮点击后焦点留在原处）。

**REQ-W-BUTTON-012**　指针形状恒为箭头（REQ-THEME-032）。

## 7. 键盘行为

| 键 | 行为 |
|---|---|
| Space | 按下时进入 `armed = 空格` 并显示为按下；释放时报告 `clicked` |
| Enter | 持有焦点时，按下即报告 `clicked` |
| Esc | `armed = 空格` 时取消，且该 Esc **不**再向后传递（不触发取消按钮）；否则不处理 |
| Alt+助记字符 | 报告 `clicked`，焦点移到本按钮，焦点变为可见 |
| Tab / Shift+Tab / 方向键 | 不处理（由 08 的导航规则处理） |

**REQ-W-BUTTON-013**　Space 的激活在**释放**时发生；按下到释放之间按钮显示为按下。Space 的自动重复按下被忽略。

**REQ-W-BUTTON-014**　`armed = 空格` 期间焦点离开按钮（Tab、鼠标点击别处、窗口失活、程序移走焦点）或按钮变为禁用时，**必须**取消，不报告 `clicked`。

**REQ-W-BUTTON-015**　Enter 的激活在**按下**时发生，自动重复的 Enter 被忽略（按住 Enter 只触发一次）。按钮通过 `InteractOpts.handles` 声明处理 Space 与 Enter（路由第 ⑤ 级），不预占，因此命令快捷键优先。 Esc **仅在** `armed = 空格` 的那些构建中加入 `handles`（按 `armed_space` 状态条件声明），其余时候不声明，使 Esc 照常到达所在范围的取消按钮（REQ-INPUT-030 禁止声明了却不处理）。

**REQ-W-BUTTON-016**　持有焦点的按钮在其焦点范围内**必须**临时成为 Enter 的目标：只要焦点在某个按钮上，Enter 触发该按钮而非范围指定的默认按钮。焦点范围指定的默认按钮在焦点位于非按钮控件时由 Enter 触发（REQ-INPUT-034），此时 `Result.activated = .default_button`。

**REQ-W-BUTTON-017**　文字中的助记符按 REQ-INPUT-046 解析并经 `ui.mnemonic(id, ch, .activate)` 登记；下划线的显示遵循 REQ-INPUT-047。禁用的按钮不登记助记符。

## 8. 焦点

**REQ-W-BUTTON-018**　`neutral` 与 `accent` 变体可聚焦且为 Tab 停靠。`quiet` 变体可聚焦但自身不是 Tab 停靠：它依赖所在工具栏的漫游组（REQ-INPUT-038）获得键盘可达性；不在任何漫游组内的 `quiet` 按钮**必须**为 Tab 停靠。

**REQ-W-BUTTON-019**　焦点环仅在焦点可见时绘制（REQ-INPUT-040、REQ-THEME-023）。获得、失去焦点不产生激活类结果。

## 9. 文本与输入法

显示单行文本，不接受文本输入；聚焦时输入法处于禁用状态（REQ-INPUT-062 的反面：未声明 `text_input`）。

**REQ-W-BUTTON-020**　文字中的换行符与制表符按 REQ-TEXT 的单行规则处理为空格；空字符串且无图标是编程错误（调试构建断言，发布构建显示一个最小宽度的空按钮）。

## 10. 动效

| 属性 | 触发 | 时长令牌 | 缓动 | 影响级别 |
|---|---|---|---|---|
| 容器填充与边框（常态 ↔ 悬停） | 悬停变化 | `dur_fast` | `ease_out` | paint（框架内建，`Visual.hover_t`） |
| 容器（→ 按下） | 显示为按下 | `dur_instant` | — | paint（`Visual.press_t`） |
| 容器（按下 →） | 结束按下 | `dur_fast` | `ease_out` | paint |
| 焦点环 | 焦点变为可见 | `dur_fast` 淡入，消失瞬时 | `ease_out` | paint（`Visual.focus_t`） |

按钮没有自有动画槽。

## 11. 无障碍

| 项 | 值 |
|---|---|
| UIA 控件类型 | Button |
| 名称来源 | 去除助记符标记的文字；无文字时取 `tooltip` |
| 支持的模式 | Invoke；`checked` 非空时改为 Toggle |
| 状态属性 | IsEnabled、HasKeyboardFocus、AccessKey（助记符，形如 "Alt+S"）、ToggleState（如适用） |

**REQ-W-BUTTON-021**　经 UIA Invoke/Toggle 触发的激活**必须**与键盘 Enter 激活等效：在下一帧报告一次 `clicked`。 `checked` 非空的按钮经 Toggle 触发时同样只报告 `clicked`、不自行翻转——它的状态由应用持有且点击不自动翻转（见第 4 节），这一点与值由控件直接写回的 checkbox 不同。

## 12. API 草案

```zig
// 草案：仅签名
pub const ButtonVariant = enum { neutral, accent, quiet };
pub const ControlSize = enum { sm, md, lg };   // 各单行控件共用

pub const ButtonOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    variant: ButtonVariant = .neutral,
    size: ControlSize = .md,
    icon: ?theme.Icon = null,
    checked: ?bool = null,
    tooltip: ?[]const u8 = null,      // 借用至本帧结束；框架在需要显示时复制
    layout: layout.ItemOptions = .{}, // 主轴/交叉轴尺寸策略与 min/max 的覆盖，各控件共用（07）
};

pub const ButtonResult = struct {
    // 持续性状态
    hovered: bool,
    pressed: bool,       // 即"显示为按下"（不含 checked 造成的外观）
    focused: bool,
    // 激活类结果
    clicked: bool,
    activated: ?input.ActivateSource, // clicked 由默认按钮/助记符机制触发时非空
};

/// label 借用至本帧结束。label 为空串时必须提供 icon。
pub fn button(ui: *Ui, src: std.builtin.SourceLocation, label: []const u8, opts: ButtonOptions) ButtonResult;
```

`clicked` 是激活类结果，为真时触发同帧第二构建遍（REQ-FRAME-030）；在第二遍中为假（REQ-FRAME-033）。

## 13. 保留状态

| 字段 | 类型 | 保留级别 | 说明 |
|---|---|---|---|
| `armed_space` | `bool` | transient | Space 已按下待释放 |

鼠标的 `armed` 即框架的捕获状态，悬停/按下/焦点过渡为框架内建状态（REQ-FRAME-013），均无需槽。

## 14. 失效规则

**REQ-W-BUTTON-022**　绘制键**必须**由以下各项构成：文字内容、`variant`、`size`、`icon`、`checked`、`enabled`、文字是否被截断。助记符下划线是否显示不进入绘制键：它由绘制函数在绘制时读取，其变化按 REQ-INPUT-047 整窗置 `paint`。布局输入的内容度量键由文字内容、字体样式、`size`、有无图标构成。

| 变化 | 置脏级别 | 损伤范围 |
|---|---|---|
| 悬停进入/离开、显示为按下的变化、焦点环显隐 | `paint` | 按钮绘制范围（含外延） |
| 鼠标按下、释放、Space/Enter（进入收件列表） | `build` | 由差分决定；若无外观变化则为空 |
| 文字内容变化且宽度不变 | `build`（由应用的模型通知引起） | 按钮矩形 |
| 文字内容变化导致期望宽度变化 | `build` | 新旧矩形及受影响的兄弟 |
| 键盘提示下划线显隐（按下 Alt） | `paint`（整窗，REQ-INPUT-047）；绘制函数读取当前的键盘提示可见性 | 整窗 |

**REQ-W-BUTTON-023**　仅悬停进入/离开一个按钮所产生的帧**必须**是纯绘制帧（构建遍数 0），且损伤不超出该按钮的绘制范围。

## 15. 边界与错误情况

| 情况 | 规定 |
|---|---|
| 按下期间按钮从树中消失 | 捕获释放（REQ-INPUT-024），不报告 `clicked` |
| 按下期间按钮变为禁用 | 取消，不报告 `clicked`；立即显示禁用外观 |
| 按下期间按钮被移动或改变尺寸 | 以释放时的新命中范围判定 |
| 按下期间文字变化 | 允许；不影响 `armed` |
| 同一帧内同时满足鼠标释放与 Enter | 只报告一次 `clicked` |
| 按钮宽度小于高度（被外部约束压缩） | 圆角按 09 第 5 节夹紧；内容按 REQ-W-BUTTON-003 退化 |
| `accent` 变体在一个焦点范围内出现多个 | 允许但违背用法；调试构建记录一条 `warn` |
| `checked` 非空且 `variant = .accent` | 不支持的组合；调试构建断言，发布构建忽略 `checked` |
| 窗口非活动时悬停 | 仍显示悬停外观（与 Windows 一致）；点击先激活窗口，该次点击照常作用于按钮 |

## 16. 验收标准

**AC-W-BUTTON-001**　`[金图]` 覆盖：REQ-W-BUTTON-001、REQ-W-BUTTON-002、REQ-W-BUTTON-003。渲染一行按钮：文字"OK"、文字"保存所有更改"、图标+文字、仅图标、三档 `size` 各一、一个被固定为 40 lpx 宽的"保存所有更改"；缩放 1.0/1.5/2.0，浅/深。预期：与基准图一致；并以布局断言确认——"OK" 的宽度 = `button_min_w`；长文字按钮宽度 = 2×`pad_control_x` + 文字宽；仅图标按钮宽 = 高；各档高度等于对应令牌；40 lpx 的按钮文字以 `…` 结尾且无半个字形。

**AC-W-BUTTON-002**　`[金图]` 覆盖：REQ-W-BUTTON-005、REQ-W-BUTTON-019。三种变体 × {常态, 悬停, 显示为按下, 焦点可见, 禁用, `checked=true`} 的状态矩阵（`accent` 无 `checked` 列），浅/深/高对比度。预期：与基准图一致；显示为按下时内容相对常态下移恰 1 ppx 而 `checked=true` 未按住时不下移；`quiet` 常态无容器像素；焦点环仅出现在"焦点可见"列。

**AC-W-BUTTON-003**　`[回放]` 覆盖：REQ-W-BUTTON-006、REQ-W-BUTTON-007、REQ-W-BUTTON-008。脚本：在按钮内按下左键 → 断言 `pressed` 真、`clicked` 假；移到按钮外 → `pressed` 假，且相邻按钮的 `hovered` 为假；移回 → `pressed` 真；释放 → 该帧 `clicked` 真，下一帧假。重复一次但在按钮外释放 → 全程 `clicked` 为假。另在按钮矩形左上角 (0,0) 像素处（圆角之外）完成一次按下释放 → `clicked` 真；在矩形外 1 ppx（焦点环外延内）按下 → 按钮无反应。

**AC-W-BUTTON-004**　`[回放]` 覆盖：REQ-W-BUTTON-009、REQ-W-BUTTON-010。以 50 ms 间隔完成 3 次左键按下–释放 → `clicked` 累计 3 次。右键、中键各完成一次按下–释放 → `clicked` 累计不变、`pressed` 始终为假。在按钮上滚动滚轮（按钮位于一个可滚动容器内）→ 容器滚动偏移变化。

**AC-W-BUTTON-005**　`[回放]` 覆盖：REQ-W-BUTTON-011、REQ-W-BUTTON-012、REQ-W-BUTTON-018。点击 `neutral` 按钮 → 它持有焦点、焦点不可见（金图无焦点环）；随后按一次 Shift 键 → 焦点环出现。焦点在文本框时点击 `quiet` 工具栏按钮 → `clicked` 真且焦点仍在文本框。指针位于各变体按钮上时平台层记录的指针形状均为箭头。对含 {文本框, `neutral` 按钮, 工具栏内两个 `quiet` 按钮, 独立的 `quiet` 按钮} 的界面连续按 Tab，断言停靠序列为：文本框 → `neutral` 按钮 → 工具栏（一次停靠）→ 独立 `quiet` 按钮。

**AC-W-BUTTON-006**　`[回放]` 覆盖：REQ-W-BUTTON-013、REQ-W-BUTTON-014。Tab 聚焦按钮；`key down Space` → `pressed` 真、`clicked` 假；注入 5 个自动重复的 Space 按下 → 无变化；`key up Space` → `clicked` 真（恰一次）。再次 `key down Space` 后按 Tab → 焦点移走，随后 `key up Space` → `clicked` 假。再次聚焦并 `key down Space` 后令应用把 `enabled` 置假 → `pressed` 假，`key up Space` 后 `clicked` 假。再次（启用）`key down Space` 后 `key down Esc` → 取消，且所在对话框的取消按钮未被触发。

**AC-W-BUTTON-007**　`[回放]` 覆盖：REQ-W-BUTTON-015、REQ-W-BUTTON-016。对话框范围内有文本框、按钮 A、默认按钮 B（`accent`）。焦点在文本框时按 Enter → B 的 `clicked` 真且 `activated = .default_button`，A 无反应。Tab 到 A 后按 Enter → A 的 `clicked` 真，B 无反应。焦点在 A 时注入 Enter 按下 + 10 个自动重复 → A 的 `clicked` 累计恰 1 次。另登记一个快捷键为 Enter 的命令 → 焦点在 A 时按 Enter 触发的是命令而非 A。

**AC-W-BUTTON-008**　`[回放]` 覆盖：REQ-W-BUTTON-017。按钮文字 "保存(&S)"，另一禁用按钮文字 "跳过(&K)"。系统键盘提示设为"默认隐藏"：初始金图无下划线；按下 Alt → S 下出现下划线；Alt+S → 第一个按钮 `clicked` 真、`activated = .mnemonic`、持有焦点且焦点可见。Alt+K → 无任何 `clicked`，焦点不变。文字 "A && B" 的按钮显示为 "A & B" 且未登记助记符。

**AC-W-BUTTON-009**　`[回放]` 覆盖：REQ-W-BUTTON-004。固定宽度导致文字截断的按钮：悬停并推进假时钟超过系统悬停时间 → 出现提示框，文本为完整文字（不含 `&`）。未截断且未给 `tooltip` 的按钮同样操作 → 无提示框。仅图标且未给 `tooltip` 的按钮 → 调试构建产生 1 条 `warn`。

**AC-W-BUTTON-010**　`[单元]` 覆盖：REQ-W-BUTTON-020、REQ-W-BUTTON-021。文字含 `\n` 与 `\t` → 渲染为单行、期望高度不变。空文字且无图标 → 调试构建断言中止。经假 UIA 入口对按钮执行 Invoke → 下一帧 `clicked` 真恰一次；对 `checked` 非空的按钮查询模式 → 提供 Toggle 而非 Invoke，ToggleState 与 `checked` 一致；Name 为去除助记符的文字，AccessKey 为 "Alt+S"。

**AC-W-BUTTON-011**　`[计量]` 覆盖：REQ-W-BUTTON-022、REQ-W-BUTTON-023。界面含 100 个按钮。回放：指针从空白处移入按钮 X 再移出。预期：产生的各帧构建遍数均为 0；每帧被绘制的节点集合 ⊆ {X 及其与损伤相交的祖先}；损伤面积 ≤ X 的绘制范围面积。随后仅改变 X 的 `checked` 并 `invalidate(.build)` → 损伤恰为 X 的矩形；以相同参数再次 `invalidate(.build)` → 损伤为空、提交次数不变。

**AC-W-BUTTON-012**　`[回放]` 覆盖：REQ-W-BUTTON-007、REQ-W-BUTTON-014。边界情况：按下期间令应用停止声明该按钮 → 释放后无 `clicked`，捕获者为空；按下期间把按钮向右移动 200 lpx，在旧位置释放 → 无 `clicked`；在同一轮消息内注入"左键释放（按钮内）"与"Enter 按下" → 该帧 `clicked` 为真，累计计数只 +1。

## 17. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-W-BUTTON-01 | 按住 Enter 是否应像原生按钮那样连续触发 | 不连续触发（REQ-W-BUTTON-015）；这是有意偏离，避免误触发重复动作 |
| OPEN-W-BUTTON-02 | 是否提供"按住连发"参数（供微调箭头、滚动条箭头使用） | 不放在 button；由 spin-box 与 scrollbar 各自实现，重复节奏读系统键盘重复设置 |
| OPEN-W-BUTTON-03 | 是否提供带下拉箭头的分裂按钮 | 不提供；用按钮 + 菜单组合 |
