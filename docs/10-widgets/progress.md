# 进度条（progress）

## 1. 用途

向用户展示一项耗时操作的进展：**确定**进度（已知完成比例 0–1）或**不确定**进度（时长未知，只表示"仍在工作"）。控件只读，用户不能与之交互。参照 Windows 的 Progress Bar（`PBS_SMOOTH` / `PBS_MARQUEE`）。

- 由用户设定数值 → 用 slider。
- 只是告知结果（成功/失败）而非进展 → 用带状态图标的 label。
- 整个窗口或区域在等待 → 本控件放入该区域，不提供全窗口遮罩。
- 垂直进度条不支持；窗口任务栏进度不在本控件范围（见 11 的窗口集成）。

## 2. 解剖

```
 ┌──────────────────────────────────┐
 │▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░│  [状态图标]  42%      ← 条（槽 + 填充） + 可选图标 + 可选文字
 └──────────────────────────────────┘
   槽 = drawTrack      填充 = 强调色（或状态色）
   不确定：循环移动的条纹（drawTrackStripes）/ 静态条纹或整槽状态色
```

- **条**：槽（`drawTrack(R, disabled)`）与其上的**填充**（`drawTrackFill(R, tone)`），厚 `progress_h`，占满可用宽度。
- **状态图标**（可选，`state ≠ normal` 时自动出现）：位于条之后。
- **文字**（可选）：位于图标（若有）之后，`font_small`。
- 条之外的部分不含可交互元素。

## 3. 度量与布局

| 项 | 取值（令牌） |
|---|---|
| 条厚度 | `progress_h`，在节点高度内垂直居中 |
| 节点高度 | `max(progress_h, 文字行高, 有图标时 icon_sm)`；无文字无图标时 = `progress_h` |
| 条圆角 | `radius_mark`（槽与填充相同） |
| 条与图标/文字间距 | `gap_sm` |
| 图标尺寸 | `icon_sm` |
| 文字样式 | `font_small`，`text_secondary` |
| 最小宽度 | 0 |
| 绘制外延 | 0（无焦点环） |

**REQ-W-PROGRESS-001**　默认尺寸策略：水平方向占满可用宽度（父为 Row 时主轴 `grow(1)`，父为 Column 时交叉轴 `fill`；物理方向由控件按 `ui.parentAxis()` 映射，见 REQ-W-LABEL-001），垂直方向 `fit`（= 节点高度）。调用方**可以**经通用布局选项改为 `fixed` 宽度。节点高度不随值与状态变化。

**REQ-W-PROGRESS-002**　条的水平范围：自节点左缘起，宽度 = 节点宽度 − (有图标时 `icon_sm + gap_sm`) − (有文字时 `文字宽 + gap_sm`)，不小于 0。文字宽取当前文字以 `font_small` 测得的宽度（`text = .percent` 时取 "100%" 的宽度，使数值变化不引起布局变化）。图标与文字相对条垂直居中，文字基线按 REQ-THEME-017 与同行其他单行控件对齐。文字宽度不足以放下时文字以尾部省略号截断（REQ-THEME-018），条与图标不缩小。

**REQ-W-PROGRESS-003**　确定进度的几何与取值：显示值 `d` 先夹紧到 [0, 1]（`NaN` 视为 0）；填充自槽左缘起，宽度 = `round(d × 槽宽)`（整数 ppx），高度与槽相同，圆角 `radius_mark`（宽度小于 2 × 圆角时按 09 第 5 节夹紧）。`d = 0` 不绘制填充；`0 < d` 而换算宽度为 0 时**应当**至少绘制 1 个发丝线宽（REQ-THEME-012）的填充，使"已开始"可见；`d = 1` 填充占满槽。`value` 越界时夹紧并在调试构建记录一条 `warn`，`NaN` 在调试构建断言。

## 4. 变体与参数

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `state` | `enum { normal, paused, error }` | `normal` | 状态；`paused` 与 `error` 使填充换为状态色并自动显示状态图标（REQ-W-PROGRESS-004） |
| `text` | `ProgressText` | `.none` | `.none` 不显示；`.percent` 显示 "N%"（N = 当前值四舍五入的整数百分比）；`.custom` 显示调用方给出的文字 |
| `tooltip` | `?[]const u8` | `null` | 悬停提示；非空时才登记 `hover` 兴趣（`hover_visual = false`） |
| `a11y_name` | `?[]const u8` | `null` | 无障碍名称（如"正在复制文件"） |
| `enabled` | `bool` | `true` | 为假时填充改用禁用色，且不播放动画 |
| `key`、`debug_name`、`layout` | 通用 | | 见模板 |

`ProgressText = union(enum) { none, percent, custom: []const u8 }`。值不是选项：`progress(ui, src, value, opts)` 的 `value` 为 `?f32`，非空为确定进度（0–1），`null` 为不确定进度。

## 5. 状态

### 5.1 状态机

进度条没有交互状态，不响应任何输入。其显示状态由参数决定：

| 模式 | 条件 | 显示 |
|---|---|---|
| 确定 | `value` 非空 | 填充长度追赶 `value`（REQ-W-PROGRESS-008） |
| 不确定·动画 | `value = null`、`state = normal`、`enabled`、系统动画开启 | 条纹循环移动（REQ-W-PROGRESS-009） |
| 不确定·静态 | `value = null` 且（`state ≠ normal` 或 `enabled = false` 或系统动画关闭） | 静态图样（REQ-W-PROGRESS-010） |

| 当前模式 | 事件 | 下一模式 | 动作 |
|---|---|---|---|
| 确定 | 应用传入 `value = null` | 不确定 | 填充立即清除，不确定图样自相位 0 开始 |
| 不确定 | 应用传入非空 `value` | 确定 | 显示值自 0 起追赶（REQ-W-PROGRESS-008），不保留之前的相位 |
| 任意 | 指针、键盘、滚轮、焦点事件 | 不变 | 无（REQ-W-PROGRESS-006） |

### 5.2 视觉表现

| 状态 | 绘制（基元 + 令牌） |
|---|---|
| 槽 | `drawTrack(槽矩形, disabled)`：启用为 `surface_track` + 顶部 `inset_shadow`；禁用为 `surface_sunken_disabled`、无内阴影（REQ-THEME-040）；圆角 `radius_mark` |
| 确定·填充（`normal`） | `drawTrackFill(填充矩形, accent)`（`accent_mark`），自槽左缘起 |
| 确定·填充（`paused`） | `drawTrackFill(填充矩形, warning)`（`status_warning`）；条后显示 `warning` 图标（`status_warning`） |
| 确定·填充（`error`） | `drawTrackFill(填充矩形, danger)`（`status_danger`）；条后显示 `error` 图标（`status_danger`） |
| 不确定·动画 | `drawTrackStripes(槽矩形, phase)`：`phase` 由 `ui.animateLoop(id, 1, .indeterminate, .paint)` 给出，条纹随 `phase` 水平移动 |
| 不确定·静态 | `state = normal` 且 `enabled`（系统动画关闭）：`drawTrackStripes(槽矩形, 0)`；`state = paused/error` 或禁用：整槽 `drawTrackFill(槽矩形, warning / danger / disabled)`，并显示状态图标 |
| 禁用 | 槽 `drawTrack(槽矩形, true)`，填充 `drawTrackFill(…, disabled)`（`text_disabled`）；图标（若有）与文字 `text_disabled`；不播放动画 |
| 文字 | `font_small`，启用 `text_secondary`，禁用 `text_disabled` |

**REQ-W-PROGRESS-004**　**状态色与图标**：`state = paused` 时填充（或不确定图样）换为 `status_warning`，`state = error` 时换为 `status_danger`；二者**必须**同时在条之后显示对应的状态图标（`paused` 用 `warning` 标记，`error` 用 `error` 标记，边长 `icon_sm`，颜色同填充），使状态不只靠颜色区分（REQ-THEME-006）。`paused` 与 `error` 的确定进度照常显示并追赶 `value`；不确定进度不播放动画，整槽以状态色填满（REQ-W-PROGRESS-010）。`state = normal` 时不显示状态图标。

## 6. 鼠标行为

**REQ-W-PROGRESS-005**　进度条**不可交互**：不登记 `click`/`drag`/`context`/`wheel`，不取得焦点，不在 Tab 序内，不响应键盘，不吞鼠标事件。左键、右键、双击、拖拽、滚轮在其上发生时按未命中该控件处理（沿祖先冒泡，REQ-INPUT-019）。仅当 `tooltip` 非空时登记 `hover` 兴趣以显示提示框，置 `hover_visual = false`（悬停变化不置脏，REQ-FRAME-037），此时仍不处理任何点击。指针形状恒为箭头（REQ-THEME-032）。

## 7. 键盘行为

无键位：进度条不可聚焦，不处理任何键，也不登记助记符。

| 键 | 行为 |
|---|---|
| （任何键） | 不处理 |

**REQ-W-PROGRESS-006**　任何键盘、指针与焦点事件**不得**改变进度条的状态、显示或收件列表；进度条不影响 Tab 序与焦点转移（REQ-INPUT-042）。

## 8. 焦点

不适用：进度条不可聚焦、不是 Tab 停靠，因而没有焦点环与焦点可见规则。需要键盘用户获知进度时，由无障碍的 RangeValue 属性提供（第 11 节）。

## 9. 文本与输入法

可选显示单行文字（`text`），不接受文本输入；文字中的换行符与制表符按 REQ-TEXT 的单行规则处理为空格。

**REQ-W-PROGRESS-007**　`text = .percent` 时显示 "N%"，N = `round(clamp(显示值) × 100)`，显示值指追赶动画中的当前值，使文字与填充同步；`text = .custom` 时显示调用方文字，不随动画变化。无 `.percent` 时不自动显示数值。

## 10. 动效

| 属性 | 触发 | 时长令牌 | 缓动 | 影响级别 |
|---|---|---|---|---|
| 确定填充长度 | `value` 增大 | `dur_slow` | `ease_linear` | paint（自有动画槽 0） |
| 不确定条纹相位 | 持续循环（模式为"不确定·动画"） | `dur_indeterminate`（一个循环周期） | 线性 | paint（`ui.animateLoop`，自有动画槽 1） |

进度条没有悬停/按下/焦点过渡（不可交互）。

**REQ-W-PROGRESS-008**　**确定进度的追赶**：显示值 = `ui.animate(id, 0, value, .{ .duration = .slow, .easing = .linear, .level = .paint })`。`value` 增大时显示值在 `dur_slow`（200 ms）内线性追赶到新值；追赶途中收到新的目标时，从当前显示值起重新开始一段 `dur_slow` 的追赶（REQ-FRAME-045）。`value` **减小**（如任务重新开始）时显示值**立即**跳到新值，不倒退动画。首次出现的进度条无入场动画。系统关闭动画时显示值立即等于目标（REQ-FRAME-047）。追赶只改变填充长度，不改变布局矩形（REQ-THEME-020）。

**REQ-W-PROGRESS-009**　**不确定进度的动画**：模式为"不确定·动画"时，以 `phase = ui.animateLoop(id, 1, .indeterminate, .paint)`（`Duration.indeterminate` 即令牌 `dur_indeterminate`）得到相位 `[0,1)`（= `(本帧时间戳 mod dur_indeterminate) / dur_indeterminate`，线性，REQ-FRAME-045），传入 `drawTrackStripes(槽矩形, phase)`：条纹（条宽与间隔均为 `gap_sm`，裁剪到槽的圆角内）随 `phase` 水平移动，`phase` 回绕时图样恰好重合。`animateLoop` 使该节点保持为活动动画（REQ-FRAME-048），每个动画帧**不**执行构建与布局；相位只取决于本帧时间戳（REQ-FRAME-021），绘制函数保持纯函数。

**REQ-W-PROGRESS-010**　**静态图样**：系统关闭界面动画（`client_animation = false`，REQ-THEME-020、REQ-FRAME-047）时，`animateLoop` 恒返回 0 且不登记活动动画，不确定进度（`state = normal`）显示 `drawTrackStripes(槽矩形, 0)` 的静态条纹，不产生任何帧。`state ≠ normal` 或 `enabled = false` 的不确定进度不播放动画：整槽以 `drawTrackFill` 的 `warning`/`danger`/`disabled` tone 填满，并显示状态图标（REQ-W-PROGRESS-004），同样不登记动画、不产生帧。

**REQ-W-PROGRESS-011**　窗口最小化或完全不可见时，不确定进度的动画**必须**暂停出帧（REQ-FRAME-049）：不可见期间 `frame.count` 不增长；恢复可见时产生一次整根绘制，相位由当时的时间戳得出，不补播。窗口可见但被其他窗口遮挡的部分不影响该规则。

## 11. 无障碍

| 项 | 值 |
|---|---|
| UIA 控件类型 | ProgressBar |
| 名称来源 | `a11y_name`；无则取 `text = .custom` 的文字；再无则取 `tooltip` |
| 支持的模式 | RangeValue（只读，Minimum 0、Maximum 100、Value = `round(value × 100)`、IsReadOnly = 真）；不确定进度**不**提供 RangeValue（缺省即表示"不确定"） |
| 状态属性 | IsEnabled；ItemStatus（`state = paused` 取显示文字，无文字时为"已暂停"；`error` 同理为"出错"；`normal` 为空） |

**REQ-W-PROGRESS-012**　辅助技术读到的 Value **必须**随 `value` 的变化立即更新（取目标值而非动画中的显示值）；`state` 变化**必须**更新 ItemStatus。进度条不可聚焦、不可调用，不提供 Invoke/Toggle/Value 写入。

## 12. API 草案

```zig
// 草案：仅签名
pub const ProgressState = enum { normal, paused, error };
pub const ProgressText = union(enum) {
    none,
    percent,
    custom: []const u8,                // 借用至本帧结束；框架复制
};

pub const ProgressOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    state: ProgressState = .normal,
    text: ProgressText = .none,
    tooltip: ?[]const u8 = null,       // 借用至本帧结束；框架在需要显示时复制
    a11y_name: ?[]const u8 = null,     // 借用至本帧结束；框架复制
    layout: layout.ItemOptions = .{},  // 各控件共用（07）
};

pub const ProgressResult = struct {
    // 持续性状态（进度条没有激活类结果）
    hovered: bool,                     // 仅 tooltip 非空时可能为真
    display_value: ?f32,               // 确定进度当前的显示值（追赶中）；不确定进度为 null
    animating: bool,                   // 是否仍有活动动画（追赶中，或"不确定·动画"模式）
};

/// value：应用按值传入，框架不保留。非空：确定进度，取值范围 0–1，越界夹紧，NaN 视为 0；null：不确定进度。
pub fn progress(ui: *Ui, src: std.builtin.SourceLocation, value: ?f32, opts: ProgressOptions) ProgressResult;
```

进度条是只读控件：结果中没有激活类结果，不触发第二构建遍。值由应用每次构建传入，控件不持有也不写入应用的值。

## 13. 保留状态

| 字段 | 类型 | 保留级别 | 说明 |
|---|---|---|---|
| （无自有状态槽） | — | — | 追赶用框架动画槽 0（框架内建每节点状态，REQ-FRAME-045）；不确定相位由 `ui.animateLoop`（动画槽 1）给出，无需保存 |

## 14. 失效规则

**REQ-W-PROGRESS-013**　绘制键**必须**由以下各项构成：`value` 的目标值（不确定为空）、`state`、`text` 及其当前显示字符串、`enabled`、系统动画开关、是否被截断（文字）。布局输入的内容度量键由 `text` 的显示字符串（`.percent` 为 "100%"）、有无图标（由 `state` 决定）构成。

| 变化 | 置脏级别 | 损伤范围 |
|---|---|---|
| `value` 目标值变化 | `build`（由应用的模型通知引起） | 进度条矩形（含文字） |
| 追赶动画的每一帧 | `paint`（动画槽 0） | 条的矩形（文字变化时并上文字矩形） |
| 不确定·动画的每一帧 | `paint`（`animateLoop`） | 条的矩形 |
| `state`、`text` 变化 | `build` | 进度条矩形 |
| 指针移动、悬停（含有 `tooltip` 时） | 不置脏（无视觉变化） | 空 |

**REQ-W-PROGRESS-014**　进度条上的指针移动与悬停**不得**置脏、不产生帧（REQ-FRAME-037）；追赶与不确定动画的每一帧是纯绘制帧（构建遍数 0），损伤不超出该进度条的绘制范围。动画结束（追赶到位，或进入静态模式）后，该进度条不再产生帧。

## 15. 边界与错误情况

| 情况 | 规定 |
|---|---|
| `value` < 0 或 > 1 | 夹紧到 [0, 1]；调试构建记录一条 `warn` |
| `value` 为 NaN | 视为 0；调试构建断言 |
| 填充长度换算为 0 ppx（极小值） | 不绘制填充；`value > 0` 时**应当**至少绘制 1 个发丝线宽的填充，使"已开始"可见 |
| `value` = 1 | 填充占满槽；无"完成"特效；应用需要完成提示时自行切换 UI |
| 宽度为 0 或槽宽小于 `progress_h` | 不绘制条（只可能有图标与文字）；圆角按 09 第 5 节夹紧 |
| 追赶中 `state` 变化 | 状态色即时更换，追赶继续 |
| 追赶中模式由确定变不确定 | 立即切换（5.1），丢弃追赶 |
| 窗口不可见时 `value` 变化 | 不出帧；恢复可见时显示值直接跳到目标（REQ-FRAME-049） |
| 同一窗口含多个不确定进度条 | 各自按同一时间戳取相位，彼此同步；不额外增加帧率 |
| 缩放变化（DPI） | 条纹与填充按新缩放重新取整；`value` 不变 |
| 窗口非活动 | 不确定动画照常播放（不整体变灰，REQ-THEME 第 5 节） |

## 16. 验收标准

**AC-W-PROGRESS-001**　`[金图]` 覆盖：REQ-W-PROGRESS-001、REQ-W-PROGRESS-002、REQ-W-PROGRESS-003、REQ-W-PROGRESS-007、REQ-W-PROGRESS-008。渲染一列进度条（宽 200 lpx）：确定 0%、37%、100%；`.percent` 文字的 37% 与 100%；`.custom` 文字；带图标（`paused`/`error`）的 60%；被固定为 60 lpx 宽且带长 `.custom` 文字的一条；缩放 1.0/1.25/1.5/2.0，浅/深。预期：与基准图一致；几何断言——条厚 = `px(progress_h)`、垂直居中；填充宽 = `round(v × 槽宽)`（v 为显示值，追赶已完成）；0% 无填充像素；`.percent` 的条宽在 37% 与 100% 两种值下**相同**（文字宽取 "100%"）；图标位于条之后、边长 `px(icon_sm)`；长文字以 `…` 结尾；无文字无图标时节点高度 = `px(progress_h)`；`.percent` 文字与同行标签文字基线相同（REQ-THEME-017）。

**AC-W-PROGRESS-002**　`[金图]` 覆盖：REQ-W-PROGRESS-010、REQ-W-PROGRESS-004。状态矩阵：{normal, paused, error, 禁用} × {确定 60%, 不确定·静态条纹}，浅/深/高对比度。预期：与基准图一致；`paused` 与 `error` 的填充分别为 `status_warning`、`status_danger` 且各自带 `warning`、`error` 图标，将图像灰度化后 normal / paused / error 三者仍可凭图标形状区分；禁用填充为 `text_disabled`、禁用槽填充为 `surface_sunken_disabled`；静态条纹（`state = normal`、系统动画关闭）为 `drawTrackStripes(·, 0)`，竖直条的条宽与间隔均为 `px(gap_sm)`，与时间无关；`paused`/`error`/禁用的不确定进度为整槽状态色填充加图标（相隔 1 s 的两次渲染逐像素相同）。

**AC-W-PROGRESS-003**　`[回放]` 覆盖：REQ-W-PROGRESS-005、REQ-W-PROGRESS-006。确认不响应输入。进度条位于可滚动容器内，外层面板登记了 `click`。脚本：在进度条上依次左键单击、双击、按下后拖动、右键、中键；滚动滚轮；按 Tab 五次、Space、Enter、Esc、方向键。预期：进度条无焦点、不在 Tab 序中（序列不含它）；左键单击被外层面板接收；滚轮 → 容器偏移变化；平台层记录的指针形状全程为箭头；上述输入期间进度条的 `display_value` 与 `animating` 不变、其绘制节点计数为 0；Tab 序与焦点转移结果与移除该进度条后相同。给出 `tooltip` 的进度条悬停推进假时钟超过系统悬停时间 → 出现提示框，点击仍由外层面板接收。

**AC-W-PROGRESS-004**　`[回放]` 覆盖：REQ-W-PROGRESS-008。假时钟。系统动画开启。首次出现 `value = 0.5` → 显示值 0.5（无入场动画，首帧即到位）。`value` 改为 0.9 → 帧时间 +0、+100、+200 ms 时显示值依次为 0.5、0.7、0.9（线性，误差 ≤ 1 ppx 对应的比例）；追赶途中（+100 ms）改为 1.0 → 其后 200 ms 内从 0.7 线性到 1.0。`value` 由 0.9 改为 0.2 → 同一帧显示值即为 0.2。应用每帧小幅递增 `value`（0.01/帧）→ 显示值单调不减且不超过目标。系统动画关闭 → 改值后同一帧显示值 = 目标，动画帧数为 0。动画期间各帧的布局矩形集合相同。

**AC-W-PROGRESS-005**　`[回放]` 覆盖：REQ-W-PROGRESS-009、REQ-W-PROGRESS-010。假时钟，`dur_indeterminate` = 1600 ms。不确定·动画：时间 0、400、800、1600 ms 时传给 `drawTrackStripes` 的 `phase` 依次为 0、0.25、0.5、0（回绕），条纹像素相位随之移动，`phase` 0 与 1 的图样逐像素相同；条纹裁剪在槽的圆角内（槽外像素无条纹色）；两个同窗口的不确定进度条在同一帧 `phase` 相同。系统动画关闭 → 同一进度条显示 `phase = 0` 的静态条纹，3 秒假时间内 `frame.count` 增量为 0；`state = paused`、`enabled = false` 时整槽状态色填充且同样无动画帧。

**AC-W-PROGRESS-006**　`[回放]` 覆盖：REQ-W-PROGRESS-011。不确定·动画运行中：令窗口最小化并推进假时钟 3 秒 → `frame.count` 增量为 0；窗口被完全遮挡/不可见同理。恢复可见 → 产生恰一次整根绘制，此时 `phase` 等于由当时时间戳算得的相位；其后恢复正常逐帧动画。确定进度在不可见期间改值（0.2 → 0.8）→ 恢复可见后的首帧显示值直接为 0.8。

**AC-W-PROGRESS-007**　`[单元]` 覆盖：REQ-W-PROGRESS-012、REQ-W-PROGRESS-007、REQ-W-PROGRESS-003。经假 UIA 入口：确定进度 `value = 0.372` → 控件类型 ProgressBar，RangeValue 为 Min 0、Max 100、Value 37、IsReadOnly 真；追赶动画期间 Value 已为目标值 37（不是显示值）；不确定进度 → 不提供 RangeValue；`state = paused` 无文字 → ItemStatus "已暂停"，`error` → "出错"，`normal` → 空；Name 取自 `a11y_name`；进度条不提供 Invoke/Toggle/Value 写入，亦不可聚焦。`.percent` 文字：显示值 0.373 → "37%"，0.375 → "38%"（四舍五入），追赶中文字与填充同步。输入 `value = 1.7` → 夹紧为 1 且调试构建 1 条 `warn`；`NaN` → 视为 0 并断言。

**AC-W-PROGRESS-008**　`[计量]` 覆盖：REQ-W-PROGRESS-013、REQ-W-PROGRESS-014。界面含 50 个进度条。回放：指针移过全部进度条（其中 10 个带 `tooltip`，在其上停留不足悬停时间）→ `frame.count` 增量为 0（REQ-FRAME-037）。把进度条 X 的 `value` 由 0.1 改为 0.6（系统动画开启）→ 释放该次构建后，每个追赶动画帧 `frame.build_passes` 增量为 0，被绘制的节点集合 ⊆ {X 及其与损伤相交的祖先}，损伤 ⊆ X 的条矩形（与文字矩形）；追赶结束后 `frame.count` 不再增长。不确定进度条 Y 运行 3 秒 → 每帧 `frame.build_passes` 增量为 0，损伤 ⊆ Y 的条矩形，`frame.nodes_painted` 每帧 ≤ Y 及其相交祖先数；Y 停止声明后 `frame.count` 不再增长。以相同参数再次 `invalidate(.build)` → 损伤为空、`frame.presents` 不变。

## 17. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-W-PROGRESS-01 | 是否提供垂直进度条与环形进度 | 不提供 |
| OPEN-W-PROGRESS-02 | 是否与任务栏进度（`ITaskbarList3`）联动 | 不在本控件内；由 11 的窗口集成决定 |
| OPEN-W-PROGRESS-03 | 条纹是否应为斜纹 | 不为：09 的绘制基元只有轴对齐矩形（裁剪仅支持矩形，REQ-GFX-024），竖直条满足"静态条纹" |
| OPEN-W-PROGRESS-04 | `paused`/`error` 的状态文字（"已暂停"/"出错"）是内置中文串还是由应用提供 | 内置默认值，应用以 `text = .custom` 覆盖；本地化机制未定（超出本阶段） |
