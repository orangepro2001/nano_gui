# 滑块（slider）

## 1. 用途

在一个连续区间或按固定步长离散的区间内选取一个数值：音量、缩放、阈值、透明度。值由应用持有，滑块只在用户操作时改写它。参照 Windows 的 Trackbar（`TBS_HORZ` / `TBS_VERT`、`TBS_AUTOTICKS`、`TBS_TOOLTIPS`）。

- 需要输入精确数值（可键入）→ 用 spin-box 或文本框，滑块可与之并排使用但互不替代。
- 选定的是少数几个命名选项 → 用 radio 或 combo-box。
- 显示进度（只读）→ 用 progress。
- 区间选择（两个手柄）→ 不支持。

## 2. 解剖

```
        ┌─ 焦点环（仅焦点可见时，围绕滑块手柄）
        ▼
 ━━━━━━━┃▮┃━━━━━━━━━━━━        轨道（drawTrack，全长）；已选段（drawTrackFill，起点到手柄中心）
        ▮                       手柄（drawRaised）
 ╷    ╷    ╷    ╷    ╷         刻度（可选，位于轨道下方）
  ┌────┐
  │ 42 │                        值提示框（可选，仅拖动中，位于手柄上方）
  └────┘
```

- **轨道**：`slider_track_h` 厚的内凹槽，沿滑块全长；其中起点到手柄中心为**已选段**（强调色）。
- **手柄**：`slider_thumb_w × slider_thumb_h`（水平滑块；垂直滑块两者互换）的凸起方块，沿轨道移动。
- **刻度**（可选）：轨道一侧的若干发丝线短线。
- **值提示框**（可选）：拖动期间显示当前值的小提示框。
- 轨道、手柄、刻度共同构成**一个**交互节点；整个节点矩形都是点击目标。

## 3. 度量与布局

| 项 | 取值（令牌） |
|---|---|
| 厚度（交叉方向） | `control_h` |
| 最小长度（沿轨道方向） | `slider_min_len` |
| 轨道厚度 / 圆角 | `slider_track_h` / `radius_mark` |
| 手柄尺寸 / 圆角 | `slider_thumb_w` × `slider_thumb_h`（垂直时互换）/ `radius_control` |
| 刻度长度 / 刻度与手柄间距 | `gap_sm` / `gap_xs` |
| 值提示框 | 外框 `drawPopupFrame(tooltip = true)`，文字 `font_small`，与手柄间距 `gap_xs` |
| 绘制外延 | `focus_ring_w` |

**REQ-W-SLIDER-001**　默认尺寸策略：沿轨道方向 `grow(1)`（父为 Row 的水平滑块；父为 Column 时该方向是交叉轴，取 `fill`），垂直于轨道方向 `fixed(control_h)`（物理方向，由控件按 `ui.parentAxis()` 映射，见 REQ-W-LABEL-001）。垂直滑块的轨道方向为竖直。沿轨道方向的最小长度为 `slider_min_len`（`main_min` 默认值）。调用方**可以**经通用布局选项覆盖。沿轨道方向被约束到小于手柄尺寸时，手柄的可移动长度取 0（REQ-W-SLIDER-002）。

**REQ-W-SLIDER-002**　**几何（以水平滑块为例，单位 ppx，全部取整）**。设节点宽 `W`，手柄宽 `tw = px(slider_thumb_w)`，手柄可移动长度 `L = W − tw`（`L < 0` 时取 0）；归一化值 `t = (v − min) / (max − min)`（`v` 先夹紧到 `[min, max]`，`max = min` 时 `t = 0`）。手柄左缘 `x = round(t × L)`，手柄中心 `x + tw/2`（整数 ppx，向下取整）。轨道占满 `W`，厚 `px(slider_track_h)`，垂直中心与手柄垂直中心对齐；已选段为轨道自左缘到手柄中心。手柄的垂直尺寸 `px(slider_thumb_h)`，无刻度时在节点高度内居中。同一值在同一缩放下手柄位置恒定，且单调不减于 `t`。

**REQ-W-SLIDER-003**　垂直滑块（`orientation = .vertical`）的几何与上条相同，坐标轴互换：最小值在**下端**，最大值在**上端**（值向上增加）；已选段为轨道自下端到手柄中心。`inverted = true` 时方向取反（水平：最大值在左；垂直：最大值在下），已选段仍是"从最小值端到手柄"。

**REQ-W-SLIDER-004**　**刻度**：`tick_every` 非空时，在 `min + k × tick_every`（k = 0, 1, …，不超过 `max`）及 `max` 处各画一条；`k × tick_every` 恰与 `max` 重合时去重，只画一条垂直于轨道、长 `gap_sm` 的发丝线（颜色 `border_strong`，起点在手柄边缘外 `gap_xs` 处，水平滑块在轨道下方、垂直滑块在轨道右侧）。有刻度时，手柄、轨道与刻度整体（高度 = `slider_thumb_h + gap_xs + gap_sm`）在节点厚度内居中，且该高度**必须** ≤ 节点厚度。刻度只是视觉辅助，不吸附：吸附由 `step` 决定（REQ-W-SLIDER-008）。相邻刻度的像素间距小于 `px(gap_md)` 时**不**绘制任何刻度，调试构建记录一条 `warn`。

**REQ-W-SLIDER-005**　命中范围是整个布局矩形（不含焦点环外延）。"手柄命中"是手柄矩形（含其圆角外接矩形）；落在节点矩形内、手柄之外的点称"轨道命中"（含刻度区与轨道两侧的空白）。

## 4. 变体与参数

| 参数 | 类型（`slider`） | 默认 | 含义 |
|---|---|---|---|
| `orientation` | `layout.Orientation` | `.horizontal` | 水平或垂直 |
| `inverted` | `bool` | `false` | 反转方向（REQ-W-SLIDER-003） |
| `step` | `f32` | `0` | 吸附步长；`0` 为连续；大于 0 时值只取 `min + k × step` 或 `max` |
| `key_step` | `?f32` | `null` | 方向键一次的变化量；`null` 时取 `step`（`step > 0`）否则 `(max − min) / 100` |
| `page_step` | `?f32` | `null` | PageUp/PageDown 与"页"滚轮的变化量；`null` 时取 `10 × key_step`，且不超过 `max − min` |
| `tick_every` | `?f32` | `null` | 刻度间隔（值的单位）；`null` 无刻度 |
| `value_tip` | `?ValueTip` | `null` | 非空时拖动中显示值提示框 |
| `tooltip` | `?[]const u8` | `null` | 悬停提示 |
| `a11y_name` | `?[]const u8` | `null` | 无障碍名称；也可由 label 的 `for_id` 关联（REQ-W-SLIDER-015） |
| `enabled` | `bool` | `true` | |
| `key`、`debug_name`、`layout` | 通用 | | 见模板 |

`sliderInt` 的 `SliderIntOptions` 与上表相同，但 `step`、`key_step`、`page_step`、`tick_every` 的类型为整数（`step` 默认 `1`，且 ≥ 1；`key_step` 的 `null` 取 `step`；`page_step` 的 `null` 取 `max(10 × key_step, 1)`）。`ValueTip = struct { decimals: u8 = 0, suffix: []const u8 = "" }`（整数滑块忽略 `decimals`）。值与区间不是选项：`value: *f32` 或 `*i32` 由应用持有，`min`、`max` 为函数参数。滑块没有外观变体。

## 5. 状态

### 5.1 状态机

状态变量：`drag ∈ {无, 拖动, 已取消}`（鼠标手势阶段）。悬停、聚焦、禁用由框架维护（08）；值由应用持有的 `*value` 表示。进入"拖动"时记下**原始值** `origin`（按下瞬间的 `*value`）与**抓取偏移** `grab`（见 REQ-W-SLIDER-006）。

| 当前 `drag` | 事件 | 条件 | 下一 `drag` | 动作 |
|---|---|---|---|---|
| 无 | 左键按下于滑块内 | 启用，`max > min` | 拖动 | 隐式捕获（REQ-INPUT-013）；记 `origin`；手柄命中则 `grab` = 指针到手柄中心的偏移，轨道命中则 `grab` = 0 并把值设为指针位置对应值（报告 `changed`，若值有变） |
| 拖动 | 指针移动（捕获期间，含移出节点矩形） | — | 拖动 | 值 = 指针位置换算（REQ-W-SLIDER-007）；有变则报告 `changed` |
| 拖动 | 左键释放 | 值 ≠ `origin` | 无 | 报告 `committed` |
| 拖动 | 左键释放 | 值 = `origin` | 无 | 无 |
| 拖动 | Esc 按下 | 持有焦点 | 已取消 | `*value = origin`，报告 `cancelled`，值有变则同时报告 `changed` |
| 拖动 | 捕获被取消（REQ-INPUT-024）、变为禁用 | — | 已取消 | 同上（恢复 `origin`，报告 `cancelled`，值有变则报告 `changed`） |
| 已取消 | 指针移动 | — | 已取消 | 忽略 |
| 已取消 | 左键释放 | — | 无 | 无（不报告 `committed`） |
| 无 | 方向键 / PageUp / PageDown / Home / End | 持有焦点 | 无 | 值变化（REQ-W-SLIDER-012），有变则报告 `changed` 与 `committed` |
| 无 | 滚轮 | 持有焦点（REQ-W-SLIDER-014） | 无 | 值变化，有变则报告 `changed` 与 `committed` |
| 拖动 / 已取消 | 方向键、滚轮 | — | 不变 | 忽略 |
| 任意 | 右键 / 中键按下 | — | 不变 | 忽略 |

### 5.2 视觉表现

"拖动中" = `drag = 拖动`（不论指针是否仍在节点矩形内）。

| 状态 | 绘制（基元 + 令牌） |
|---|---|
| 常态 | 轨道 `drawTrack(轨道矩形, false)`；已选段 `drawTrackFill(已选段矩形, accent)`（宽度 0 时不画）；手柄 `drawRaised(neutral)`（`radius_control`） |
| 悬停 | 手柄换悬停变体（整个滑块被悬停即变化，不限于指针在手柄上） |
| 拖动中 | 手柄换按下变体；手柄内无内容故不位移；值提示框（若启用）显示 |
| 焦点可见 | 加 `drawFocusRing(手柄矩形, radius_control)`；手柄边框换 `accent_mark`（REQ-THEME-023） |
| 禁用 | 手柄 `drawRaised` 禁用配方；轨道 `drawTrack(轨道矩形, true)`；已选段 `drawTrackFill(已选段矩形, disabled)`；刻度颜色 `border_subtle` |
| 刻度 | 发丝线 `border_strong`，禁用时 `border_subtle` |
| 值提示框 | `drawPopupFrame(tooltip = true)`，文字 `font_small`、`text_primary` |

## 6. 鼠标行为

**REQ-W-SLIDER-006**　**点击轨道跳到该位置并开始拖动（不翻页）**：在启用的滑块上按下左键时，若为"轨道命中"，值**立即**设为指针位置对应的值（经 REQ-W-SLIDER-008 吸附），`grab = 0`（即手柄中心跳到指针处），并开始拖动，同一次按下继续移动即拖动手柄；若为"手柄命中"，值**不**因按下而改变，`grab` = 按下点到手柄中心的偏移（沿轨道方向），之后手柄随指针移动而保持该偏移。两种情形都在按下时取得捕获、聚焦，并使手柄显示为按下（`dur_instant`）。`max ≤ min` 时按下不开始拖动。

**REQ-W-SLIDER-007**　**拖动**：不使用拖拽阈值（不读 `drag_size`）；按下即开始，指针移动的每个事件都重新换算。值对应的归一化位置 `t = clamp((p − (起点 + tw/2) − grab) / L, 0, 1)`，其中 `p` 是指针沿轨道方向的坐标（ppx）；垂直方向的换算取反使上端为最大。换算只使用沿轨道方向的分量：指针在垂直于轨道方向上移出节点矩形任意远，仍按其沿轨道方向的位置更新，超出两端时值取端点。每次换算后值与 `*value` 不同则写入，并在该帧报告 `changed`（同一帧内多个移动事件只报告一次，值为最后一次换算的结果）。`L = 0` 时值恒为 `min`。

**REQ-W-SLIDER-008**　**吸附**：`step > 0` 时，换算得到的原始值 `r` 取离它最近的候选点，候选点集合为 `{min + k × step | k ≥ 0, ≤ max} ∪ {max}`；与两候选点等距时取较小者。整数滑块同理（`step ≥ 1`）。`step = 0` 时不吸附，值取换算结果夹紧到 `[min, max]`。吸附适用于鼠标、键盘（键盘增量之后再吸附）、滚轮与 UIA 设值。

**REQ-W-SLIDER-009**　**`changed` 与 `committed`**：`changed` 是值发生了变化的每一帧的激活类结果（拖动中可连续多帧为真）；`committed` 是"一次编辑手势结束"的激活类结果（15 的统一词汇，REQ-CONV-010：`changed` 为每次变化，`committed` 为拖动释放等手势结束，`cancelled` 为取消），**必须**在下列时刻报告：鼠标左键**释放**且值 ≠ 按下时的 `origin`（释放帧）；键盘或滚轮引起的每一次值变化（与该帧的 `changed` 同帧）；UIA 设值（同帧）。拖动中、以及拖动被取消时**不**报告 `committed`。仅按下未改变值、或拖动后回到 `origin` 的释放不报告 `committed`。

**REQ-W-SLIDER-010**　**取消**：拖动中按 Esc，或捕获被取消（窗口失活、应用 `releaseCapture`、REQ-INPUT-024）、或滑块变为禁用时，`*value` **必须**恢复为 `origin`，报告 `cancelled`（激活类结果）；恢复使值发生变化时同帧也报告 `changed`；之后直到左键释放为止的指针移动被忽略，释放时不报告 `committed`。拖动中的 Esc **不**再向后传递（不触发所在对话框的取消按钮）；非拖动状态下 Esc 不处理，沿 ⑦ 级触发取消按钮。按下期间滑块从树中消失：捕获释放，不改变应用此时的 `*value`，不报告任何结果。

**REQ-W-SLIDER-011**　右键、中键的按下与释放不改变状态、不报告任何结果，无上下文菜单；滑块不处理双击（连续点击按各自的按下—释放独立处理）。指针形状恒为箭头（REQ-THEME-032）。鼠标点击使滑块获得焦点（REQ-INPUT-022），但不使焦点变为可见。

## 7. 键盘行为

| 键 | 行为 |
|---|---|
| → / ↑ | 值增加 `key_step`（`inverted` 时减少） |
| ← / ↓ | 值减少 `key_step`（`inverted` 时增加） |
| PageUp | 值增加 `page_step` |
| PageDown | 值减少 `page_step` |
| Home | 值取 `min`（`inverted` 时仍为 `min`，不随方向变化） |
| End | 值取 `max` |
| Esc | 拖动中：取消并恢复原值（REQ-W-SLIDER-010）；否则不处理 |
| Alt+助记字符 | 滑块自身无标签、不登记助记符；由关联的 label 经 `for_id` 登记（REQ-W-SLIDER-015） |
| Enter / Space | 不处理 |
| Tab / Shift+Tab | 不处理（08 的导航规则） |

**REQ-W-SLIDER-012**　键盘改值：每个 `key_down`（包括自动重复）按上表改变值，改变量先按 REQ-W-SLIDER-008 吸附，再夹紧到 `[min, max]`；值未变化（已在端点）时不报告任何结果。每次有变化的按键在该帧报告 `changed` 与 `committed`。滑块经 `InteractOpts.handles` 声明处理方向键、PageUp/PageDown、Home/End（`arrows`、`page`、`home_end` 键组），拖动中另声明 `escape`；不预占，命令快捷键优先。方向键**不**用于在控件间导航（滑块不是漫游组成员）。

**REQ-W-SLIDER-013**　数值键盘增量的计算：`key_step` 与 `page_step` 的默认值见第 4 节；`key_step ≤ 0` 或 `page_step ≤ 0` 时按默认值处理并在调试构建记录 `warn`。浮点增量累加不得产生 `min + k × step` 之外的值（吸附后再比较是否变化）。

**REQ-W-SLIDER-014**　**滚轮仅在持有焦点时改变值**：滑块在持有焦点时才声明 `wheel_caps`（向上/向下），不持有焦点时不声明，滚轮事件按 REQ-INPUT-019 冒泡给外层的滚动容器。持有焦点时，每累计 1 格（REQ-INPUT-020）向上滚动值增加 `key_step`、向下减少 `key_step`（`inverted` 时反向）；小数格累加到 transient 的累加器，满 1 格才应用，且累加器在滑块失焦时清零。系统滚轮设置（读取系统度量，03 的 `wheel_lines`）为 `.page` 时每格改变 `page_step`，为 `lines(0)` 时滚轮不改变值。滚轮造成的每次变化报告 `changed` 与 `committed`；拖动中滚轮被忽略。

## 8. 焦点

**REQ-W-SLIDER-015**　滑块可聚焦且为 Tab 停靠（`tab_stop = true`）；不是漫游组成员。焦点环围绕**手柄**，仅在焦点可见时绘制（REQ-INPUT-040、REQ-THEME-023）；获得、失去焦点不改变值、不产生激活类结果。滑块自身没有文字，因此**不**登记助记符；需要 Alt+字母聚焦滑块时，在其前放置 label 并令 `for_id` 指向它（`MnemonicAction.focus`，REQ-W-LABEL-014）。

## 9. 文本与输入法

不显示文本（除拖动中的值提示框），不接受文本输入；聚焦时输入法处于禁用状态。

**REQ-W-SLIDER-016**　**值提示框**：`value_tip` 非空且 `drag = 拖动` 期间，滑块声明一个 `PopupKind.tooltip` 弹出层（06 的 `beginPopup`，`keyboard = .passive`，不进入弹出栈、不可命中，REQ-INPUT-057），锚点为手柄矩形：水平滑块位于手柄正上方、水平居中，垂直滑块位于手柄左侧、垂直居中（`layout.Placement`，间距 `gap_xs`，空间不足时按 07 的翻转规则）。文本为当前值：浮点按 `decimals` 位小数（四舍五入）加 `suffix`，整数直接格式化加 `suffix`；随值每帧更新并跟随手柄。拖动结束、取消、失焦或窗口失活时立即消失。键盘与滚轮改值**不**显示值提示框。值提示框不使用 `ui.tooltip` 的悬停延迟与"无捕获"条件（REQ-INPUT-057 的补充规则允许控件直接以 `beginPopup(kind = .tooltip)` 自行控制提示框）。

**REQ-W-SLIDER-017**　**退化输入**：`max < min` 时按交换处理并在调试构建断言；`max = min` 时滑块可显示（手柄在起点）但不可操作（按下不拖动、键盘与滚轮不改值）；`NaN` 或无穷的 `*value`、`min`、`max` 视为 `min` 并在调试构建断言；`*value` 越界时只在**显示**上夹紧，**不**写回应用的值，直到用户操作；`step` 大于区间长度时候选点只有 `min` 与 `max`；整数区间的跨度以 64 位计算，不得溢出。

## 10. 动效

| 属性 | 触发 | 时长令牌 | 缓动 | 影响级别 |
|---|---|---|---|---|
| 手柄填充与边框（常态 ↔ 悬停） | 悬停变化 | `dur_fast` | `ease_out` | paint（框架内建，`Visual.hover_t`） |
| 手柄（→ 拖动中） | 进入拖动 | `dur_instant` | — | paint（`Visual.press_t`） |
| 手柄（拖动中 →） | 结束拖动 | `dur_fast` | `ease_out` | paint |
| 焦点环 | 焦点变为可见 | `dur_fast` 淡入，消失瞬时 | `ease_out` | paint（`Visual.focus_t`） |

**REQ-W-SLIDER-018**　手柄位置**不得**有过渡动画：无论值因拖动、键盘、滚轮还是应用写入而变，手柄在该值生效的那一帧即处于目标位置（拖动必须跟手；动效令牌中没有适用的时长）。值提示框的出现与消失同样是瞬时的。滑块没有自有动画槽。

## 11. 无障碍

| 项 | 值 |
|---|---|
| UIA 控件类型 | Slider |
| 名称来源 | `a11y_name`；无则取经 `for_id` 关联的 label 文字（LabeledBy）；再无则取 `tooltip` |
| 支持的模式 | RangeValue |
| 状态属性 | IsEnabled、HasKeyboardFocus、RangeValue.Value / Minimum / Maximum / SmallChange（= `key_step`）/ LargeChange（= `page_step`）、IsReadOnly（= 禁用）、Orientation |

**REQ-W-SLIDER-019**　经 UIA RangeValue.SetValue 设值**必须**与键盘改值等效：先按 REQ-W-SLIDER-008 吸附并夹紧，值有变化时在下一帧报告 `changed` 与 `committed`；Value、Minimum、Maximum **必须**随 `*value` 与参数同步（含应用直接写入的变化）。

## 12. API 草案

```zig
// 草案：仅签名
pub const ValueTip = struct {
    decimals: u8 = 0,                  // 浮点滑块的小数位数
    suffix: []const u8 = "",           // 借用至本帧结束；框架复制
};

pub const SliderOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    orientation: layout.Orientation = .horizontal,
    inverted: bool = false,
    step: f32 = 0,                     // 0 = 连续
    key_step: ?f32 = null,
    page_step: ?f32 = null,
    tick_every: ?f32 = null,
    value_tip: ?ValueTip = null,
    tooltip: ?[]const u8 = null,       // 借用至本帧结束；框架在需要显示时复制
    a11y_name: ?[]const u8 = null,     // 借用至本帧结束；框架复制
    layout: layout.ItemOptions = .{},  // 各控件共用（07）
};

pub const SliderIntOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    orientation: layout.Orientation = .horizontal,
    inverted: bool = false,
    step: i32 = 1,                     // ≥ 1
    key_step: ?i32 = null,
    page_step: ?i32 = null,
    tick_every: ?i32 = null,
    value_tip: ?ValueTip = null,
    tooltip: ?[]const u8 = null,
    a11y_name: ?[]const u8 = null,
    layout: layout.ItemOptions = .{},
};

pub const SliderResult = struct {
    // 持续性状态
    hovered: bool,
    focused: bool,
    dragging: bool,      // drag = 拖动
    // 激活类结果（触发同帧第二构建遍，REQ-FRAME-030）
    changed: bool,       // 值在本帧被用户操作改变（本次调用已写入 *value）；拖动中可连续多帧为真
    committed: bool,     // 用户完成了一次改值手势（REQ-W-SLIDER-009）
    cancelled: bool,     // 拖动被 Esc 或捕获取消并已恢复原值
};

/// value：应用持有；调用方须保证存活至本次构建结束，框架不保留。
/// 用户操作使值改变的那次调用内，控件先写入 *value 再返回 changed = true。
/// min、max 为区间端点（闭区间）；step 等参数见 SliderOptions。
pub fn slider(ui: *Ui, src: std.builtin.SourceLocation, value: *f32, min: f32, max: f32, opts: SliderOptions) SliderResult;
pub fn sliderInt(ui: *Ui, src: std.builtin.SourceLocation, value: *i32, min: i32, max: i32, opts: SliderIntOptions) SliderResult;
```

`changed`、`committed`、`cancelled` 是激活类结果，为真时触发同帧第二构建遍，在第二遍中为假（REQ-FRAME-033）；`hovered`、`focused`、`dragging` 是持续性状态。控件**不**保留值。`slider` 与 `sliderInt` 是两个具体函数，不使用泛型。

## 13. 保留状态

| 字段 | 类型 | 保留级别 | 说明 |
|---|---|---|---|
| `drag` | `enum { none, active, cancelled }` | transient | 鼠标手势阶段（其中"拖动"期间同时是框架的捕获状态） |
| `origin` | `f32`（整数滑块为 `i32`） | transient | 按下瞬间的原始值，供取消恢复与 `committed` 判定 |
| `grab` | `f32`（ppx） | transient | 抓取偏移 |
| `wheel_accum` | `f32` | transient | 滚轮小数格累加器，失焦清零 |

值与区间归应用所有，不在状态槽中。悬停/按下/焦点过渡为框架内建状态（REQ-FRAME-013）。

## 14. 失效规则

**REQ-W-SLIDER-020**　绘制键**必须**由以下各项构成：夹紧后的值、`min`、`max`、`orientation`、`inverted`、`step`（影响刻度对齐）、`tick_every`、`enabled`。布局输入的内容度量键由 `orientation`、有无刻度构成。值提示框的绘制键由其文本与锚点矩形构成。

| 变化 | 置脏级别 | 损伤范围 |
|---|---|---|
| 悬停进入/离开、拖动中显隐（按下视觉）、焦点环显隐 | `paint` | 滑块绘制范围（含外延） |
| 鼠标按下、拖动中的指针移动、释放、键盘、滚轮（进入收件列表） | `build` | 由差分决定；若无外观变化则为空 |
| 值变化（任意来源） | `build` | 滑块节点矩形（含外延）；值提示框的新旧矩形 |
| `min`/`max`/`orientation`/`tick_every` 变化 | `build` | 滑块矩形 |

**REQ-W-SLIDER-021**　仅悬停进入/离开一个滑块所产生的帧**必须**是纯绘制帧（构建遍数 0），且损伤不超出该滑块的绘制范围。拖动中每个因指针移动产生的帧，构建遍数 ≤ 2（第一遍之后因 `changed` 触发第二遍），损伤 ⊆ 滑块的绘制范围 ∪ 值提示框的新旧矩形；手势结束（释放）后不产生持续帧（`frame.count` 不再增长）。

## 15. 边界与错误情况

| 情况 | 规定 |
|---|---|
| 按下期间滑块从树中消失 | 捕获释放（REQ-INPUT-024），不改变 `*value`，不报告任何结果 |
| 按下期间滑块变为禁用 | 按取消处理（REQ-W-SLIDER-010）：恢复 `origin`，报告 `cancelled` |
| 按下期间应用改写了 `*value` | 允许；之后的拖动以指针位置为准覆盖；`committed` 与 `origin` 比较（`origin` 仍为按下瞬间的值） |
| 按下期间滑块被移动或改变尺寸 | 以最新的几何换算 `t`；`grab` 保持 |
| 拖动中窗口失活 | 取消（捕获丢失），恢复原值 |
| `max ≤ min`、`NaN`、越界 | 见 REQ-W-SLIDER-017 |
| `step` 不整除区间 | 候选点含 `max`（REQ-W-SLIDER-008），末段可短于 `step` |
| 缩放变化（DPI） | 以新缩放重新换算手柄位置；值不变 |
| 刻度过密 | 见 REQ-W-SLIDER-004 |
| 同一帧内鼠标释放与方向键 | 先后按事件序处理；`changed` 合并为一次，`committed` 各自独立判定后合并为真 |
| 窗口非活动时悬停 | 仍显示悬停外观；点击先激活窗口，该次点击照常作用于滑块（并开始拖动） |

## 16. 验收标准

**AC-W-SLIDER-001**　`[金图]` 覆盖：REQ-W-SLIDER-001、REQ-W-SLIDER-002、REQ-W-SLIDER-003、REQ-W-SLIDER-004。渲染：水平与垂直滑块（200 lpx 长），值取 0%、25%、100%；带刻度（`tick_every` 为区间的 1/4）与不带刻度；`inverted` 一份；缩放 1.0/1.25/1.5/2.0，浅/深。预期：与基准图一致；几何断言——手柄左缘 = `round(t × (W − tw))`；轨道厚 = `px(slider_track_h)`、手柄为 `px(slider_thumb_w) × px(slider_thumb_h)`（垂直互换）；垂直滑块 100% 时手柄贴上端、0% 时贴下端；已选段自最小值端到手柄中心；节点厚度 = `control_h`；刻度数 = 5（`tick_every` 为区间 1/4 时 `k × tick_every` 的 k = 4 与 `max` 重合，去重后恰 5 条；另取 `tick_every` 为区间 0.3 倍时为 0、0.3、0.6、0.9 与 `max` 共 5 条），长度 `px(gap_sm)`，位于轨道下方（水平）或右侧（垂直）；刻度间距小于 `px(gap_md)` 的配置不画刻度。

**AC-W-SLIDER-002**　`[金图]` 覆盖：REQ-W-SLIDER-015、REQ-W-SLIDER-005。状态矩阵：{常态, 悬停, 拖动中, 焦点可见, 禁用} × {水平, 垂直}，值 40%，浅/深/高对比度。预期：与基准图一致；拖动中手柄为按下配方；焦点环围绕手柄且仅出现在"焦点可见"列；禁用态已选段颜色为 `text_disabled`（`drawTrackFill` 的 `disabled` tone）、轨道填充为 `surface_sunken_disabled`，用到的颜色集合 ⊆ 禁用令牌 ∪ 表面令牌 ∪ 轨道令牌；悬停态在指针位于远离手柄的轨道上时手柄也为悬停配方。

**AC-W-SLIDER-003**　`[回放]` 覆盖：REQ-W-SLIDER-006、REQ-W-SLIDER-007、REQ-W-SLIDER-008、REQ-W-SLIDER-009、REQ-W-SLIDER-011。滑块区间 [0, 100]，`step = 0`，初值 20，L 已知。脚本：在手柄中心偏右 3 lpx 处按下 → `changed` 假、`*value` 仍为 20、`dragging` 真、持有焦点且无焦点环；向右移动 +40 lpx → 手柄中心与指针的偏移保持 3 lpx（值 = 对应换算），`changed` 真；指针上移到节点外 200 lpx 同时沿轨道方向再移动 → 值仍随沿轨道方向的位置变化；指针移到轨道端点之外 → 值 = 100；释放 → `committed` 真（释放帧）、`dragging` 假。重复：在远离手柄的轨道位置（对应 80%）按下 → 同一次按下的帧 `changed` 真、值 = 80、`committed` 假；不移动直接释放 → `committed` 真（80 ≠ 20）。在手柄上按下并原地释放 → 无 `changed`、无 `committed`。拖动后回到原值再释放 → 无 `committed`。`step = 10`：拖动经过 34、36 → 值依次为 30、40，区间 [0, 95]、`step = 10` 时离 `max` 近于半步的 93 取 `max`，即 95（不是 100）。右键、中键各一次 → 值不变、无任何结果。点击后金图无焦点环，按 Shift 后焦点环出现；指针形状为箭头。

**AC-W-SLIDER-004**　`[回放]` 覆盖：REQ-W-SLIDER-010。初值 30：在手柄上按下并拖到 70（应用在每次 `changed` 时即时应用该值）→ 按 Esc → 该帧 `*value = 30`、`cancelled` 真、`changed` 真（值变回）、`committed` 假，所在对话框的取消按钮未被触发；其后继续移动指针并释放 → 值保持 30、无 `committed`。按下后未移动就按 Esc → `cancelled` 真、`changed` 假。拖动中令窗口失活 → 值恢复为 30、`cancelled` 真。拖动中令应用把 `enabled` 置假 → 值恢复、`cancelled` 真、外观立即禁用。非拖动状态按 Esc → 滑块无反应，对话框取消按钮被触发。按下期间令应用停止声明该滑块 → 释放后 `*value` 为应用当时的值，无任何结果。

**AC-W-SLIDER-005**　`[回放]` 覆盖：REQ-W-SLIDER-012、REQ-W-SLIDER-013、REQ-W-SLIDER-015。Tab 聚焦（区间 [0, 100]，`key_step = 5`，`page_step = 20`，初值 50）。→ → 55，`changed` 与 `committed` 同帧真；← → 50；↑ → 55；↓ → 50；PageUp → 70；PageDown → 50；End → 100；再按 → → 值不变、无任何结果；Home → 0；`key repeat VK_RIGHT 10` → 值依次 5…50、每次均 `changed` 且 `committed`。`inverted = true` 时 → 减少、← 增加，Home 仍为 `min`。垂直滑块 ↑ 增加。`key_step = 0` 与 `page_step = -1` → 按默认值（`step` 为 0 时 `key_step` = 1，`page_step` = 10）并产生 `warn`。Enter、Space → 无反应；Enter 触发所在对话框的默认按钮。对含 {文本框, 滑块, 按钮} 的界面连续按 Tab，序列依次经过三者，方向键不在控件间移动焦点。把单键 → 登记为命令快捷键后，按 → 触发该命令而不是改变滑块的值。

**AC-W-SLIDER-006**　`[回放]` 覆盖：REQ-W-SLIDER-014。滑块位于一个垂直滚动容器内；系统 `wheel_lines = lines(3)`。滑块未持有焦点：在其上滚动 1 格 → 滚动容器偏移变化、滑块值不变。Tab 聚焦滑块后滚动 +1 格 → 值 + `key_step`、`changed` 与 `committed` 同帧真，容器偏移不变；−1 格 → 值 − `key_step`。注入 0.4 格、0.4 格、0.4 格（各事件分属不同的消息轮次）→ 仅在第三个事件后值变化一次（累计 1.2 格应用 1 格，余 0.2）；失焦后再聚焦累加器为 0。`wheel_lines = .page` → 每格 ± `page_step`；`lines(0)` → 值不变。拖动中滚轮 → 无变化。

**AC-W-SLIDER-007**　`[回放]` 覆盖：REQ-W-SLIDER-015。标签"音量(&V)"以 `for_id` 指向滑块（同一 `SourceLocation` 取 ID）；系统键盘提示设为"默认隐藏"。Alt+V → 焦点移到滑块、焦点可见（焦点环在手柄上）、值不变、无任何激活类结果。滑块自身未登记助记符（节点检视中 `mnemonic` 登记数为 1，且属于该标签对滑块的登记）。

**AC-W-SLIDER-008**　`[回放]` 覆盖：REQ-W-SLIDER-016。`value_tip = .{ .decimals = 1, .suffix = "%" }`。在手柄上按下并拖动 → 出现提示框，文本随值更新（如 "42.3%"），位于手柄上方且水平居中，整个拖动期间位置跟随手柄；释放 → 提示框消失；Esc 取消 → 消失；窗口失活 → 消失。垂直滑块的提示框位于手柄左侧。键盘改值与滚轮改值 → 不出现提示框。整数滑块忽略 `decimals`（"42%"）。提示框不进入弹出栈（弹出栈深度恒为 0）、不可命中。

**AC-W-SLIDER-009**　`[单元]` 覆盖：REQ-W-SLIDER-008、REQ-W-SLIDER-017、REQ-W-SLIDER-019。吸附：区间 [0, 95]、`step = 10`，输入 4.9 → 0；5.0 → 0（等距取较小者）；5.1 → 10；92 → 90；93 → 95；区间 [0, 100]、`step = 30`：89 → 90，96 → 100。整数滑块 [−2147483648, 2147483647] 的跨度计算不溢出。退化输入：`max < min` → 调试构建断言；`max = min` → 按下不拖动、键盘与滚轮不改值、无结果；`NaN` 值 → 视为 `min`；`*value` = 150 且区间 [0, 100] → 显示夹紧到 100 而 `*value` 仍为 150，直到用户操作。经假 UIA 入口：控件类型 Slider，模式含 RangeValue；Value/Minimum/Maximum/SmallChange/LargeChange 与参数一致；`SetValue(37.2)` 在 `step = 5` 时 → 下一帧 `changed` 与 `committed` 同真、值为 35；`SetValue` 越界 → 夹紧；IsReadOnly 随 `enabled`；Name 取自 `a11y_name`，无则取 LabeledBy 的 label 文字。

**AC-W-SLIDER-010**　`[计量]` 覆盖：REQ-W-SLIDER-020、REQ-W-SLIDER-021、REQ-W-SLIDER-018。界面含 50 个滑块。回放：指针从空白处移入滑块 X 再移出 → 各帧构建遍数均为 0；被绘制的节点集合 ⊆ {X 及其与损伤相交的祖先}；损伤面积 ≤ X 的绘制范围面积。在 X 上按下并以每帧一次的节奏拖动 20 个位置 → 每个拖动帧 `frame.build_passes` 增量 ≤ 2；损伤 ⊆ X 的绘制范围（含值提示框时再并上其新旧矩形）；手柄在每个拖动帧的位置等于该帧值的换算位置（无滞后、无过渡帧）；释放后 `frame.count` 不再增长。仅改变 X 的 `max` 并 `invalidate(.build)` → 损伤恰为 X 的矩形；以相同参数再次 `invalidate(.build)` → 损伤为空、`frame.presents` 不变。应用直接写入 `*value` 并 `invalidate(.build)` → 手柄在该帧即处于新位置（无动画帧）。

## 17. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-W-SLIDER-01 | 是否提供区间滑块（双手柄）与"从中点向两侧填充"的双向滑块 | 不提供 |
| OPEN-W-SLIDER-02 | 方向键方向与 Windows Trackbar 不同：Windows 水平 Trackbar 为 ←/↑ 减、→/↓ 增，垂直 Trackbar 的最小值在上端；本文垂直滑块最大值在上端、↑ 增加 | 有意偏离，使方向键与视觉方向一致 |
| OPEN-W-SLIDER-03 | 拖动期间每帧两个构建遍（`changed` 触发第二遍）的成本 | 待 12 的基准场景评估；若超预算，考虑拖动中只报告 `changed` 的最终值（本文已合并同帧多次移动） |
| OPEN-W-SLIDER-04 | 垂直滑块在 Column 中的默认长度（`grow(1)` 需要父容器有确定高度） | 应用在 `layout` 中给 `fixed`；父为 `fit` 时退化为 `main_min = slider_min_len` |
