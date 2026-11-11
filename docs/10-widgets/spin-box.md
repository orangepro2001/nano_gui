# 数值微调框（spin-box）

> 编辑部分引用 text-input.md 的编辑核心（光标与选区、键位、撤销、剪贴板、输入法、光标闪烁、横向滚动），本文只写差异。凡未提及者，按 text-input.md 执行；其"缓冲"在本文是控件内部持有的编辑缓冲，应用持有的是**数值**。

## 1. 用途

输入一个有范围的数值：端口号、数量、缩放比例、阈值。参照 Windows 的 Up-Down（spinner）加伙伴 Edit。

- 范围很大或需要精确文本（如任意长度的数字串）→ 用 text-input 加应用校验。
- 在少量离散选项中选择 → 用 combo-box。
- 连续量的粗调 → 用 slider。

提供两个函数：`spinBoxInt`（`i64`）与 `spinBoxFloat`（`f64`）。数值由应用持有（传指针），框架保留编辑过程中的文本、光标与连发状态。

## 2. 解剖

```
        ┌─ 焦点环（恒显示）
┌───────────────────────────────┬────┐
│ 12.50   文本区（视口，裁剪）   │ ▲  │   容器 = drawSunken（整体）
│                               ├────┤   分隔线 = drawSeparator
│                               │ ▼  │   箭头按钮 = 安静凸起
└───────────────────────────────┴────┘
  └ pad_input_x             箭头列 ┘
```

- **容器**：内凹表面，含文本区与箭头列。
- **文本区**：即嵌入的 text-input 编辑部分（`embed.frame_owner = true`）。
- **箭头列**：上箭头按钮与下箭头按钮，左侧一条竖向分隔线，两按钮之间一条横向分隔线。

## 3. 度量与布局

| 项 | 取值（令牌） |
|---|---|
| 高度 | `control_h`（`size = .sm` 时 `control_h_sm`，`.lg` 时 `control_h_lg`） |
| 最小宽度 | `button_min_w` |
| 文本区左内边距 | `pad_input_x` |
| 箭头列宽 | `icon_md` |
| 箭头列与文本区间距 | `gap_sm` |
| 箭头字形 | `drawMark(chevron_up / chevron_down)`，字形框边长 `gap_md`，居中于各自按钮 |
| 文字样式 | `font_body` |
| 绘制外延 | `focus_ring_w` |

**REQ-W-SPINBOX-001**　默认尺寸策略：主轴 `fit`，交叉轴 `fixed(高度令牌)`。期望宽度 = `max(button_min_w, pad_input_x + max(格式化后的 min 文本宽, 格式化后的 max 文本宽, 当前值文本宽) + gap_sm + icon_md + 1 个发丝线)`；`show_arrows = false` 时不计箭头列与间距，右内边距取 `pad_input_x`。调用方**可以**经 `layout` 改为 `fixed` 或 `grow`。

**REQ-W-SPINBOX-002**　箭头列位于容器内缘（扣除发丝线边框）的右侧，宽 `icon_md`；其高度（容器内缘高）自上而下对半分：上按钮高 `floor(内缘高 / 2)`，下按钮占其余。两按钮的命中范围即各自矩形。文本区视口为容器左内边距之后、箭头列左缘之前减去 `gap_sm` 的区间。上按钮绘制 `chevron_up`，下按钮绘制 `chevron_down`，颜色 `text_primary`；按钮不可用时（REQ-W-SPINBOX-006）为 `text_disabled`。

## 4. 变体与参数

两个函数共用的参数：

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `min`、`max` | `i64`/`f64` | `i64` 的全范围 / `-1.0e15`、`1.0e15` | 闭区间范围 |
| `step` | `i64`/`f64` | `1` / `1.0` | 上下键、箭头与滚轮的步长，必须 > 0 |
| `big_step` | `?i64`/`?f64` | `null`（取 10 × `step`） | PageUp/PageDown 的步长 |
| `decimals` | `u8`（仅 `f64`） | `2` | 小数位数（0–9）；同时是显示位数与取整位数 |
| `read_only` | `bool` | `false` | 只读：可聚焦、可选择、可复制，不可修改；箭头列不可用 |
| `show_arrows` | `bool` | `true` | 显示箭头列 |
| `size` | `ControlSize` | `md` | 高度档 |
| `tooltip` | `?[]const u8` | `null` | 悬停提示 |
| `enabled`、`key`、`debug_name`、`layout` | 通用 | | 见模板 |

**REQ-W-SPINBOX-003**　数值由应用持有：`value: *i64`（或 `*f64`），控件在值改变时写入该指针并报告 `changed`。每次构建开始，若 `value.*` 不同于控件上次写入或读到的值（应用程序性改值），则**必须**：放弃进行中的编辑（若有）、清空编辑撤销栈、按 REQ-W-SPINBOX-004 重新格式化显示；程序性改值**不**自动夹紧到 `[min, max]`（显示按原值，下一次用户操作时夹紧），不报告 `changed`。`min > max` 是编程错误：调试构建断言，发布构建交换二者。`step ≤ 0` 同样断言，发布构建取默认步长。

**REQ-W-SPINBOX-004**　**格式化**：`i64` 显示为十进制整数（负数前缀 `-`，无分组分隔符，无前导 `+`）；`f64` 显示为固定 `decimals` 位小数的十进制数，小数点恒为 `.`，不使用科学计数法，`-0` 显示为 `0`（带相应位数的零）。未处于编辑状态时，文本区显示 `value.*` 的格式化结果；每次值变化后（步进、提交、程序性改值）立即重新格式化。

**REQ-W-SPINBOX-005**　**输入字符集**：编辑部分经 text-input.md 的 `accept` 机制（REQ-W-TEXTINPUT-013）只接受合法字符，对键入、粘贴、输入法提交逐码点判定候选文本：`i64`——候选文本匹配 `^-?[0-9]*$`，且 `-` 只在 `min < 0` 时允许；`f64`——匹配 `^-?[0-9]*\.?[0-9]*$`，`-` 同上，小数点最多一个，小数点之后的数字不超过 `decimals` 位（`decimals = 0` 时不接受小数点）。预处理：全角数字 U+FF10–U+FF19 映射为 ASCII 数字、U+FF0D（全角减号）与 U+2212 映射为 `-`、U+FF0E 与 U+3002 映射为 `.`，映射后再判定；其余字符（字母、空格、千分位逗号、`+`、`e`）被丢弃。不接受的字符被静默忽略，不产生提示音，不改变光标。

## 5. 状态

### 5.1 状态机

状态变量：`editing ∈ {否, 是}`（文本区内容是否被用户改过、尚未提交）；`arrow_armed ∈ {无, 上, 下}`（鼠标按住的箭头）；`repeat ∈ {空闲, 等待首次延迟, 连发}`。

| 当前 | 事件 | 条件 | 下一状态 | 动作 |
|---|---|---|---|---|
| editing 否 | Enter | — | editing 否 | 报告 `committed`，文本区重新格式化为 `value.*` 的格式化文本，**不改值**（Enter 经 `observes` 观察，路由继续） |
| editing 否 | 用户编辑文本（键入、粘贴、删除、输入法提交） | 可编辑 | editing 是 | 文本区更新；**不**改 `value.*` |
| editing 是 | Enter | — | editing 否 | 提交（REQ-W-SPINBOX-013），报告 `committed` |
| editing 是 | 失去焦点 | — | editing 否 | 提交，报告 `committed` |
| editing 是 | Esc | — | editing 否 | 恢复显示为 `value.*` 的格式化文本；Esc 被消费 |
| 任意 | ↑ / ↓ / PageUp / PageDown | 可编辑，值未在边界 | 同 / editing 否 | 若 editing 则先提交；再按步长改值，`changed` |
| repeat 空闲 | 左键按下于可用的箭头按钮 | 可编辑 | 等待首次延迟 / arrow_armed = 该箭头 | 取文本区焦点；若 editing 先提交；立即步进一次；登记首次延迟定时器 |
| 等待首次延迟 | 定时器到期（首次延迟） | 指针仍在该按钮内 | 连发 | 步进一次；改登记重复间隔定时器 |
| 连发 | 定时器到期（重复间隔） | 指针在按钮内，值未达边界 | 连发 | 步进一次 |
| 等待首次延迟 / 连发 | 指针移出该按钮 | 按键仍按住 | 暂停 | 停止步进；移回按钮后从重复间隔重新计时 |
| 任意 | 左键释放 / 捕获取消 / 变为禁用或只读 | — | 空闲 / arrow_armed 无 | 取消定时器 |
| 任意 | 滚轮 | 持有焦点，可编辑 | 同 | 每整格步进一次 |

### 5.2 视觉表现

| 状态 | 绘制（基元 + 令牌） |
|---|---|
| 容器 | `drawSunken(R, radius_control, visual, false)`；聚焦时边框 `accent_mark` 与 `drawFocusRing` |
| 箭头按钮常态 | 不画容器（安静凸起，REQ-THEME-031），字形 `text_primary` |
| 箭头按钮悬停 | `drawRaised(quiet 悬停)`，圆角 `radius_mark`，范围为该按钮矩形内缩发丝线 |
| 箭头按钮按下 | `drawRaised(quiet 按下)`，字形下移 1 ppx |
| 箭头按钮不可用 | 不画容器、不响应悬停，字形 `text_disabled` |
| 分隔线 | 竖线与横线 `drawSeparator`（`border_subtle`） |
| 禁用 | 容器禁用配方，文字与字形 `text_disabled` |
| 文本区的选区、光标、组字 | 同 text-input.md |

**REQ-W-SPINBOX-006**　上按钮在 `value.* ≥ max`、下按钮在 `value.* ≤ min` 时不可用；`read_only`、禁用时两按钮都不可用。不可用的按钮不响应悬停与点击（点击落在其上被吞掉，不取焦点）。值变化使按钮由可用变为不可用时，进行中的连发立即停止。

## 6. 鼠标行为

**REQ-W-SPINBOX-007**　文本区的鼠标行为（单击定位、Shift+单击、拖动选择与自动滚动、双击选词、三击全选、右键与上下文菜单、中键）同 text-input.md，指针形状 `ibeam`；右键菜单项同 REQ-W-TEXTINPUT-027（"撤销"针对当前编辑会话）。箭头列上指针形状为箭头。

**REQ-W-SPINBOX-008**　左键在可用的箭头按钮上按下：控件立即捕获指针；若文本区正在编辑，先提交（REQ-W-SPINBOX-013）；使文本区获得焦点：按下时调用 `ui.setFocusReason(文本区, .pointer)`（08 REQ-INPUT-043），原因为 `pointer`，因此**不全选**（若已持有焦点则不变）；立即按 `step` 步进一次（上按钮增、下按钮减，结果夹紧到 `[min, max]`），报告 `changed`。步进发生在**按下**时，不等释放。按钮的点击不使焦点变为可见之外的任何变化（文本区恒为焦点可见）。

**REQ-W-SPINBOX-009**　**按住连发**：箭头按钮被按住时，经 `build` 级定时器连发。首次连发延迟读取系统度量 `SystemMetrics.key_repeat_delay_ms`，重复间隔读取 `SystemMetrics.key_repeat_interval_ms`（03，来源 `SPI_GETKEYBOARDDELAY`/`SPI_GETKEYBOARDSPEED`）。按下后经首次延迟开始连发，之后每个间隔步进一次；指针移出该按钮时停止，移回后从重复间隔重新计时；释放、捕获被取消、按钮不可用、窗口失去激活时取消。连发步进不加速。

**REQ-W-SPINBOX-010**　**滚轮仅在文本区持有焦点时生效**：持有焦点、可编辑、启用时，控件声明 `WheelCaps.up/down`，滚轮每整格步进一次（向上滚增、向下滚减，不足一格的小数累积到下一次；不读取 `wheel_lines`）；若 editing 先提交。未持有焦点（或只读、禁用）时 `WheelCaps` 为空，滚轮事件按 REQ-INPUT-019 冒泡给外层可滚动容器。Ctrl+滚轮不处理。

## 7. 键盘行为

| 键 | 行为 |
|---|---|
| ↑ / ↓ | 值 + / − `step`（先提交编辑），夹紧到范围；已在边界时无效果 |
| PageUp / PageDown | 值 + / − `big_step`（默认 10 × `step`），夹紧 |
| Enter | 提交文本（`committed`）；不插入字符；观察而不消费，所在范围有默认按钮时同时触发之 |
| Esc | 正在编辑时恢复显示并消费；否则不处理（冒泡到取消按钮） |
| ← → Home End Ctrl+←/→、Shift 组合 | 文本区内的光标与选区移动（text-input.md） |
| Ctrl+A、Backspace/Delete、Ctrl+Backspace/Delete、Ctrl+C/X/V 及 Insert 变体、Ctrl+Z/Y | 文本区编辑（text-input.md），受 REQ-W-SPINBOX-005 约束 |
| Tab / Shift+Tab | 不处理（焦点导航）；失焦时提交 |
| Alt+助记符 | 由与其关联的 label 经 `focus` 聚焦，不由本控件登记 |

**REQ-W-SPINBOX-011**　控件预占：text-input.md 的预占集合（REQ-W-TEXTINPUT-031）与 `extra` 逐个列出的无修饰 ↑、↓、PageUp、PageDown（**不**用 `groups.arrows`/`groups.page`，以免连带 Shift 变体与←→）；Enter 经 `observes` **观察而不消费**（报告 `committed` 并提交解析，同时路由继续，所在范围有默认按钮时照常触发，REQ-W-TEXTINPUT-040）；`handles` 在 `editing` 为真时加入 Esc。其余不预占。`text_input = true`，`ime` 在可编辑时为 `true`、只读时为 `false`。

**REQ-W-SPINBOX-012**　**步进算法**：`i64` 以饱和算术计算 `value ± step` 后夹紧到 `[min, max]`；`f64` 先计算 `value ± step`，再取整到 `decimals` 位（四舍五入，中点远离零），再夹紧，使重复步进不累积二进制浮点误差（例：从 `0.0` 以 `step = 0.1`、`decimals = 1` 步进 10 次得到恰为 `1.0`）。步进后若结果等于原值则不报告 `changed`。步进后文本区的光标置末尾，选区折叠，且不进入撤销栈（编辑会话结束）。

**REQ-W-SPINBOX-013**　**提交**（Enter 或失去焦点，且 `editing` 为真）：对文本区内容解析——`i64`：十进制整数，空串、单个 `-` 为非法；`f64`：十进制小数，允许 `12.`、`.5`、`-.5`，空串、单个 `-`、单个 `.` 为非法；数值超出 `i64` 时饱和。合法时：`f64` 取整到 `decimals` 位，夹紧到 `[min, max]`，写入 `value.*`（与原值不同则报告 `changed`），文本区重新格式化；**非法时恢复**：不改 `value.*`，文本区恢复为 `value.*` 的格式化文本。无论结果如何都报告 `committed` 并结束编辑会话（清空撤销栈）。提交后光标置末尾（Enter）或随失焦隐藏。`editing` 为假时 Enter 仍报告 `committed`（并重新格式化显示）。

## 8. 焦点

**REQ-W-SPINBOX-014**　文本区可聚焦且为 Tab 停靠；箭头按钮不可聚焦、不是 Tab 停靠、`take_focus_on_click = false`（点击时由控件把焦点交给文本区，REQ-W-SPINBOX-008）。因 `tab`、`mnemonic`、`initial`、`programmatic`、`transfer` 获得焦点时全选文本；因鼠标点击获得焦点（原因 `pointer`）时不全选；由箭头点击转移焦点时经 `ui.setFocusReason(文本区, .pointer)`（REQ-INPUT-043）使原因为 `pointer`，同样不全选；失去焦点时提交并隐藏选区与光标（REQ-W-TEXTINPUT-048），横向滚动回到行首。焦点环恒显示（文本输入类）。

## 9. 文本与输入法

**REQ-W-SPINBOX-015**　输入法在文本区持有焦点、可编辑时启用（`text_input = true`，`ime = true`）；组字串按 REQ-W-TEXTINPUT-051 内联显示（不过滤），提交串经预处理与 REQ-W-SPINBOX-005 过滤后才进入编辑缓冲（因此中文输入法下输入全角数字 "１２" 得到 "12"，输入汉字被丢弃）。只读时 `ime = false`，输入法不启用。

## 10. 动效

| 属性 | 触发 | 时长令牌 | 缓动 | 影响级别 |
|---|---|---|---|---|
| 容器边框 | 悬停变化 | `dur_fast` | `ease_out` | paint（`Visual.hover_t`） |
| 焦点环 | 焦点变为可见 | `dur_fast` 淡入，消失瞬时 | `ease_out` | paint |
| 箭头按钮悬停/按下 | 悬停、按下变化 | 悬停 `dur_fast`；按下 `dur_instant`，释放 `dur_fast` | `ease_out` | paint |
| 光标 | 闪烁 | 无 | — | paint（定时器） |

数值变化瞬时生效，无计数动画。

## 11. 无障碍

| 项 | 值 |
|---|---|
| UIA 控件类型 | Spinner |
| 名称来源 | 紧邻其前的 label（`focus_next`）或调用方给出的名称 |
| 支持的模式 | RangeValue（Value、Minimum、Maximum、SmallChange = `step`、LargeChange = `big_step`）、Value（文本形式） |
| 状态属性 | IsEnabled、HasKeyboardFocus、ValueIsReadOnly（RangeValue 的 IsReadOnly） |

**REQ-W-SPINBOX-016**　经 UIA `RangeValue.SetValue(v)` 设置时等同于步进后的提交：夹紧、取整、写入 `value.*` 并在下一帧报告 `changed`；`Value.SetValue("12.5")` 等同于把文本写入编辑部分并提交（非法则无效果）。

## 12. API 草案

```zig
// 草案：仅签名
pub const SpinBoxIntOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    min: i64 = std.math.minInt(i64),
    max: i64 = std.math.maxInt(i64),
    step: i64 = 1,
    big_step: ?i64 = null,           // null = 10 × step
    read_only: bool = false,
    show_arrows: bool = true,
    size: ControlSize = .md,         // 定义于 button.md
    tooltip: ?[]const u8 = null,
    layout: layout.ItemOptions = .{},
};

pub const SpinBoxFloatOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    min: f64 = -1.0e15,
    max: f64 = 1.0e15,
    step: f64 = 1.0,
    big_step: ?f64 = null,
    decimals: u8 = 2,                // 0–9
    read_only: bool = false,
    show_arrows: bool = true,
    size: ControlSize = .md,
    tooltip: ?[]const u8 = null,
    layout: layout.ItemOptions = .{},
};

pub const SpinBoxResult = struct {
    id: WidgetId,
    // 持续性状态
    hovered: bool,
    focused: bool,
    editing: bool,        // 文本区内容已被改过、尚未提交
    // 激活类结果（触发同帧第二构建遍，REQ-FRAME-030）
    changed: bool,        // value.* 在本帧被控件改变
    committed: bool,      // Enter 或失焦提交（含非法恢复）
};

/// value 由应用持有，须在控件被声明的整个期间存活；控件在第一构建遍内写入。
pub fn spinBoxInt(ui: *Ui, src: std.builtin.SourceLocation, value: *i64, opts: SpinBoxIntOptions) SpinBoxResult;
pub fn spinBoxFloat(ui: *Ui, src: std.builtin.SourceLocation, value: *f64, opts: SpinBoxFloatOptions) SpinBoxResult;
```

`changed`、`committed` 是激活类结果。数值由应用持有（指针）；文本区的编辑缓冲与选区、光标由框架保留。

## 13. 保留状态

| 字段 | 类型 | 保留级别 | 说明 |
|---|---|---|---|
| 编辑缓冲 `buf` | `TextBuf`（内部持有） | transient | 显示与编辑的文本 |
| 编辑核心状态 | 同 text-input.md 的 `anchor`、`caret`、`scroll_x`、`undo`/`redo`、`blink_epoch`、`comp` | `anchor`、`caret`、`scroll_x`、撤销栈为 sticky；其余 transient | 编辑会话结束时撤销栈清空 |
| `editing` | `bool` | transient | |
| `last_value` | `i64`/`f64` | transient | 识别程序性改值 |
| `repeat` | `{phase, armed}` | transient | 连发相位与按住的箭头 |
| `wheel_frac` | `f32` | transient | 滚轮不足一格的累积 |

箭头按钮的悬停/按下与捕获是框架内建状态。

## 14. 失效规则

**REQ-W-SPINBOX-017**　绘制键**必须**由以下各项构成：格式化显示文本（编辑中为编辑缓冲）、选区与光标偏移、横向滚动偏移、组字串、`editing`、上下按钮的可用性、`read_only`、`enabled`、`show_arrows`、`size`、有焦点、窗口是否活动、焦点可见。不含光标相位与箭头按钮的悬停/按下进度（框架内建 `Visual`）。布局输入的内容度量键由 `min`/`max`/当前值的格式化宽度、`decimals`、`show_arrows`、`size` 构成。

| 变化 | 置脏级别 | 损伤范围 |
|---|---|---|
| 悬停进入/离开容器或某个箭头按钮 | `paint` | 控件绘制范围（箭头按钮悬停只需其矩形） |
| 光标闪烁 | `paint` | 光标矩形 |
| 键入、步进、提交（经收件列表或定时器） | `build` | 控件矩形；格式化宽度变化且 `fit` 时含受影响的兄弟 |
| 连发定时器到期 | `build` | 控件矩形 |

**REQ-W-SPINBOX-018**　仅悬停进入/离开或仅光标闪烁产生的帧**必须**是纯绘制帧（构建遍数 0），损伤分别不超出控件绘制范围与光标矩形；连发期间的每个步进帧损伤为控件矩形。

## 15. 边界与错误情况

| 情况 | 规定 |
|---|---|
| `value.*` 在范围之外（程序性） | 显示原值；首次用户步进时先夹紧再步进（从夹紧值 ± step 后再夹紧） |
| `value.*` 为 NaN 或 ±∞（`f64`） | 视为编程错误：调试构建断言，发布构建当作 `min` 显示并写回 |
| `min = max` | 两按钮恒不可用，提交总夹紧为该值 |
| 提交时解析溢出（`i64` 之外的数字串） | 饱和后夹紧 |
| `decimals = 0`（`f64`） | 不接受小数点，格式化无小数部分 |
| `f64` 步长小于 `10^-decimals` | 步进取整后可能无变化，不报告 `changed`；调试构建对 `step < 10^-decimals` 记录一条 `warn` |
| 连发期间值被应用程序性改变 | 连发继续按新值步进；若新值已在边界则停止 |
| 编辑中变为只读/禁用 | 放弃编辑并恢复显示；连发取消；焦点按 REQ-INPUT-050 转移 |
| 按下箭头期间控件消失 | 捕获释放，连发定时器随节点消失，不报告 `changed`（已发生的步进保留） |
| 窗口失去激活 | 连发取消；`editing` 保持，不提交 |
| 粘贴 "1,234.5" 于 `i64` | 逐码点过滤（REQ-W-SPINBOX-005），不做数字语义解析：`,` 与 `.` 被丢弃，得 "12345" |
| 极窄控件 | 文本视口夹紧到 ≥ 0；箭头列保持 |

## 16. 验收标准

**夹具 F-SP**（除特别注明外）：无头、`fixed` 文本后端（簇宽 6 px，行高 16 px）、缩放 1.0；`@S` 为 `spinBoxInt`，位于 (100,100)、120×24，`value` = 5，`min` = 0、`max` = 10、`step` = 1；`caret_blink_ms` = 500。容器内缘 x ∈ [101,219)，箭头列 [199,219)，上按钮 y ∈ [101,112)、下按钮 y ∈ [112,123)；文本视口 [106,195]。回放记号同 text-input.md 第 16 节。行高取 `font_body` 的令牌行高 16（REQ-THEME-016），与 fixed 后端的自然行高无关。`@F` 为 `spinBoxFloat`，`value` = 1.5，`min` = 0、`max` = 10、`step` = 0.25、`decimals` = 2。

**AC-W-SPINBOX-001**　`[金图]` 覆盖：REQ-W-SPINBOX-001、REQ-W-SPINBOX-002、REQ-W-SPINBOX-006、REQ-W-SPINBOX-004。状态矩阵：{常态, 悬停容器, 悬停上按钮, 按住下按钮, 聚焦, 聚焦且选区非空, 值 = max（上按钮不可用）, 值 = min（下按钮不可用）, 只读, 禁用, `show_arrows = false`, `i64` 与 `f64`（`decimals` = 0/2）} × 浅/深/高对比度 × 缩放 1.0/1.5/2.0。预期：与基准图一致；期望宽度满足 REQ-W-SPINBOX-001 的公式（`i64`、min = 0、max = 10、值 5：6 + 12（"10" 两簇）+ 4 + 20 + 1 = 43 → 取 `button_min_w` = 72）；不可用箭头的字形为 `text_disabled` 且悬停无容器像素；按住按钮的字形下移恰 1 ppx；分隔线为 `border_subtle`。

**AC-W-SPINBOX-002**　`[回放]` 覆盖：REQ-W-SPINBOX-008、REQ-W-SPINBOX-007、REQ-W-SPINBOX-003。点击上按钮 (209,106) 按下 → 该帧 `value` = 6、`changed` 真（按下时即生效），文本区持有焦点且**未**全选；释放 → 无变化。点击下按钮 (209,117) → 5。`expect cursor`：文本区 `ibeam`、箭头列 `arrow`。文本区双击选中 "5"、三击全选；右键菜单可用。把应用中的 `value` 程序性改为 8 → 下一构建显示 "8"、`changed` 假；改为 99 → 显示 "99"（不夹紧），随后点击下按钮 → 夹紧为 10 后再减 1 得 9。

**AC-W-SPINBOX-003**　`[回放]` 覆盖：REQ-W-SPINBOX-009、REQ-W-SPINBOX-006。注入 `setting key_repeat_delay_ms 500`、`setting key_repeat_interval_ms 50`（03 的 `SystemMetrics` 字段，13 的 `setting` 名字表）。在 t0 按住上按钮：`value` 5 → 6；`advance 499` → 仍 6；`advance 1` → 7（t0 + 500）；`advance 100` → 9（550、600 两次）；`advance 50` → 10（达 max，上按钮变为不可用，定时器取消，`expect timers` 不含该定时器）；`advance 500` → 仍 10。释放。另将 `value` 置 8：按住下按钮 → 7；`advance 500` → 6；把指针移出按钮并 `advance 500` → 仍 6；移回按钮并 `advance 50` → 5。窗口 `activate off` → 连发取消。

**AC-W-SPINBOX-004**　`[回放]` 覆盖：REQ-W-SPINBOX-012、REQ-W-SPINBOX-011、REQ-W-SPINBOX-014。`@S` 聚焦（Tab，全选）：按 ↑ → 6；按 PageUp → 10（6 + 10 夹紧）；按 ↑ → 仍 10、`changed` 假；按 PageDown → 0（10 − 10）；按 ↓ → 仍 0；`big_step = 3` 时按 PageUp → 3。`@F`：按 ↑ → "1.75"；连按 ↑ 至 10 → "10.00"；`value` = 0.0、`step` = 0.1、`decimals` = 1：按 ↑ 10 次 → 恰为 1.0，显示 "1.0"。聚焦时 ↑/↓/PageUp/PageDown 不被外层 Scroll 容器的键盘滚动取走（预占）；Alt+↑（登记为命令快捷键）仍调用该命令。Tab 离开后 `@S` 不再响应 ↑。

**AC-W-SPINBOX-005**　`[回放]` 覆盖：REQ-W-SPINBOX-005、REQ-W-SPINBOX-015。`@S`（min = 0）：全选后 `text "abc12"` → 编辑缓冲 "12"（字母被丢弃）；`text "-5"` → '-' 被拒（min ≥ 0），得到 "125"；min = -10 时 '-' 仅允许在开头：输入 "-5-3" 得 "-53"。`@F`（decimals = 2）：`text "2.345"` → "2.34"；`text "1.2.3"` → "1.23"（第二个 '.' 被拒）；`decimals = 0` 时 `.` 被拒。粘贴 "1,234.5" 于 `i64` → "12345"。输入法：`ime start`、`ime update "yi" 2` → 显示 "yi"（不过滤）、缓冲不变；`ime commit "１２"`（全角）→ 编辑缓冲 "12"；`ime commit "你"` → 被丢弃、缓冲不变；只读时 `setImeEnabled(false)`。

**AC-W-SPINBOX-006**　`[回放]` 覆盖：REQ-W-SPINBOX-013、REQ-W-SPINBOX-014、REQ-W-SPINBOX-011。`@S` 聚焦：全选后 `text "99"`、按 Enter → `value` = 10（夹紧）、`changed` 真、`committed` 真、显示 "10"；Ctrl+A、`text "7"`、Tab 离开 → `value` = 7、`committed` 真；全选后按 Backspace 使文本为空、Enter → `value` 不变、显示恢复为格式化值、`committed` 真、`changed` 假；（min = -10）全选后输入 "-" 单字符再 Enter → 恢复；Esc（`editing` 真）→ 显示恢复且该 Esc 未触发取消按钮；再次 Esc（未编辑）→ 触发取消按钮。`@F` 全选后输入 ".5" 再 Enter → 0.5（显示 "0.50"）；输入 "12." → 夹紧 10 → "10.00"；输入 "3.4" → 3.40。`editing` 中先输入 "8" 再按 ↑ → 先提交 8 再步进为 9。`editing` 中应用把 `value` 改为 2 → 编辑被放弃，显示 "2"。

**AC-W-SPINBOX-007**　`[回放]` 覆盖：REQ-W-SPINBOX-010、REQ-W-SPINBOX-007。`@S` 位于可滚动容器内：未聚焦时指针在其上滚动 1 格 → 容器滚动、`value` 不变；聚焦后 `wheel 1`（向上 1 格，13 的符号：正值向上）→ `value` +1，容器不滚动；`wheel -1`（向下）→ −1；`wheel 0.5` 两次 → 恰一步；编辑中（输入了 "9" 未提交）滚轮 → 先提交 9 再步进；只读或禁用时滚轮冒泡给容器；Ctrl+滚轮不步进。

**AC-W-SPINBOX-008**　`[单元]` 覆盖：REQ-W-SPINBOX-005、REQ-W-SPINBOX-013、REQ-W-SPINBOX-012、REQ-W-SPINBOX-003、REQ-W-SPINBOX-004。解析与格式化表：`i64`：""→非法，"-"→非法，"007"→7，"-0"→0，"9223372036854775808"→饱和 `maxInt` 后夹紧；`f64`（decimals = 2）："12."→12.00、".5"→0.50、"-.5"→-0.50（min 为负时）、"."→非法、"1e3"→不可输入；格式化：`-0.0` → "0.00"；中点远离零取整：`0.125`（decimals = 2）→ "0.13"、`0.375` → "0.38"、`2.5`（decimals = 0）→ "3"、`-2.5` → "-3"；全角映射表 "１２．５" → "12.5"、"－３" → "-3"。`min > max` 调试构建断言中止。`step ≤ 0` 调试构建断言中止。

**AC-W-SPINBOX-009**　`[回放]` 覆盖：REQ-W-SPINBOX-016、REQ-W-SPINBOX-006。经假 UIA 入口：控件类型 Spinner；RangeValue 的 Minimum/Maximum/SmallChange/LargeChange 等于选项；`SetValue(7)` → 下一帧 `value` = 7、`changed` 真；`SetValue(99)` → 夹紧为 10；`Value.SetValue("abc")` → 无效果；只读时 `IsReadOnly` 真。

**AC-W-SPINBOX-010**　`[计量]` 覆盖：REQ-W-SPINBOX-017、REQ-W-SPINBOX-018。界面含 100 个微调框。回放：指针从空白处移入 X 的容器再移到其上按钮再移出 → 各帧构建遍数 0，被绘制节点 ⊆ {X 及与损伤相交的祖先}，损伤 ≤ X 的绘制范围；聚焦 X、`advance 5000` → 10 帧、构建遍数 0、损伤面积 ≤ 54 ppx²；仅改变 `step` → 无损伤；改变 `max`（使不可用状态变化）→ 损伤恰为 X 的矩形；以相同参数再次 `invalidate(.build)` → 损伤为空。

**AC-W-SPINBOX-011**　`[人工]` 覆盖：REQ-W-SPINBOX-009、REQ-W-SPINBOX-015、REQ-W-SPINBOX-010、REQ-W-SPINBOX-005。真实 Windows 10 与 11：用微软拼音在微调框中键入 "12"（全角与半角两种）与汉字，组字串内联显示，提交后得到 "12" 而汉字被丢弃；按住箭头按钮观察首次延迟与重复速度，并在"控制面板 → 键盘 → 字符重复"中调整延迟与速度后再试，确认连发节奏随之变化；在带滚动条的页面中，微调框未聚焦时滚动滚轮应滚动页面，聚焦后滚动滚轮应改变数值；与记事本的 Edit 控件对照光标、选择与剪贴板行为。

## 17. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-W-SPINBOX-02 | 小数点是否按系统区域设置（逗号）显示与接受 | 本版固定 `.`；03 无区域小数分隔符字段，需要时增补 |
| OPEN-W-SPINBOX-03 | 滚轮每整格步进一次而不读取 `wheel_lines` | 倾向保持（滚轮用于微调而非滚动）；Windows 原生 Up-Down 无滚轮支持，属有意扩展 |
| OPEN-W-SPINBOX-04 | 数值分组分隔符、单位后缀（如 "px"）显示 | 不在本版；单位由应用在旁用 label 显示 |
| OPEN-W-SPINBOX-05 | 连发是否随按住时间加速 | 不加速（可预期）；原生控件有加速，需实机对照后定 |
| OPEN-W-SPINBOX-06 | 箭头点击"按下即步进"与"释放步进"的取舍 | 按下即步进，与 Windows 微调按钮一致 |
| OPEN-W-SPINBOX-07 | 提交时是否在值被夹紧时给出视觉提示 | 不提示（显示变为夹紧后的值即反馈） |
