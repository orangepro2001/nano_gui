# 分隔条（splitter）

## 1. 用途

把一块区域分成恰好两个窗格，并让用户拖动（或用键盘）中间的分隔条来调整两侧的分配。参照 Windows 资源管理器左右窗格之间的分隔条与常见的 `Splitter` 控件（Win32 本身没有标准控件）。布局语义（`SplitPos` 三种表示、最小尺寸夹紧、窗口缩放时的分配、`splitMetrics`）引用 07 的 REQ-LAYOUT-034 至 REQ-LAYOUT-037，不在此重复；本文写作为控件的交互、绘制与持久化。

- 需要两个以上窗格 → 嵌套多个 splitter。
- 内容可折叠/展开而不是调整大小 → 不适用本控件（折叠吸附列为待定，不写入条款）。
- 调整的是表格列宽 → 用 table 自带的列边界。
- 两块固定比例、不需要用户调整的区域 → 用 07 的 Row/Column，不要用 splitter。

## 2. 解剖

```
水平（左右两窗格）：
┌─────────────┬┬──────────────┐
│             ││              │
│  窗格 1     ││   窗格 2     │   ← 窗格：由调用方声明，恒裁剪
│             ││              │
└─────────────┴┴──────────────┘
              └ 分隔条：命中宽 splitter_w，中间一条发丝线
```

- **窗格 1、窗格 2**：调用方声明的两个子节点，被指派的矩形即它们的矩形（07 REQ-LAYOUT-034）。
- **分隔条**：两窗格之间 `splitter_w` 宽（水平方向时）或高（垂直方向时）的条带；它是框架在两窗格之间创建的**独立部件节点**（REQ-LAYOUT-055），可命中、可聚焦、有自己的悬停与按下状态。
- **发丝线**：分隔条正中的一条发丝线，结构性分隔。
- **焦点环**：分隔条聚焦且焦点可见时的外环（画在覆盖层）。

## 3. 度量与布局

| 项 | 取值（令牌） |
|---|---|
| 分隔条命中宽度 | `splitter_w`（主轴方向） |
| 可见线 | 发丝线（REQ-THEME-012），居中，颜色 `border_strong`（`drawSeparator`，结构性） |
| 键盘步长 | `gap_lg` |
| 悬停/拖动时的条带色 | 悬停 `surface_row_hover`；拖动 `surface_raised_pressed_top` |
| 窗格最小尺寸 | `SplitterParams.min_first`、`min_second`（lpx，07） |
| 绘制外延 | `focus_ring_w`（仅焦点环，画在覆盖层） |

**REQ-W-SPLITTER-001**　`beginSplitter`/`endSplitter` 之间**必须**恰声明两个子节点作为窗格（框架创建的分隔条节点不计入）；多于两个时调试构建断言（REQ-LAYOUT-034、055），少于两个时缺失的窗格视为空窗格并记录一条 `warn`。窗格的尺寸策略被忽略，窗格**不得**依赖自己的期望尺寸决定分配。水平（`horizontal`）两窗格左右排列、分隔条竖直，垂直（`vertical`）两窗格上下排列、分隔条水平。

**REQ-W-SPLITTER-002**　默认尺寸策略：主轴 `grow(1)`、交叉轴 `fill`；调用方**可以**经 `layout` 选项覆盖。期望尺寸按 REQ-LAYOUT-036。

**REQ-W-SPLITTER-003**　**分隔条节点**：分隔条是 Splitter 下由框架创建的部件叶节点（REQ-LAYOUT-055），主轴尺寸 `px(splitter_w)`、位于两窗格之间（两窗格各让出一半），ID 由 Splitter ID 与固定部件键派生、跨构建稳定；它的矩形与 `ui.splitMetrics(id).divider` 一致，不含焦点环外延。分隔条的命中、悬停、按下、捕获、指针形状（`InteractOpts.cursor`）、焦点与键盘处理**全部落在该节点上**，Splitter 节点本身与窗格节点不参与；因此窗格区域内的指针不会显示分隔条指针形状、不会开始拖动、不会触发悬停高亮。"Splitter 恰有两个子项"只计应用声明的窗格（REQ-W-SPLITTER-001）。

**REQ-W-SPLITTER-004**　分隔条的可见线是位于条带正中的一条发丝线（宽 `Theme.hairline(scale)`），其起止坐标对齐物理像素（REQ-THEME-012）；条带宽度为偶数 ppx 而发丝线为奇数 ppx 时，发丝线偏向第一窗格一侧（取 `floor((条带宽 − 线宽) / 2)`，与 REQ-LAYOUT-013 的居中取整一致）。发丝线贯穿整个交叉轴尺寸。

## 4. 变体与参数

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `orientation` | `layout.Orientation` | `horizontal` | 窗格排列方向（07） |
| `default_pos` | `layout.SplitPos` | `.{ .ratio = 0.5 }` | 初始位置，同时是"恢复默认位置"的目标 |
| `pos` | `?*layout.SplitPos` | `null` | 非空时位置由应用持有；空时由框架保留（sticky） |
| `min_first`、`min_second` | `f32`（lpx） | `0` | 两侧最小尺寸（07） |
| `persist` | `?[]const u8` | `null` | 持久化名（11 REQ-APP-037）；空则不持久化 |
| `enabled`、`key`、`debug_name` | 通用 | | 见模板 |

变体只有方向（结构性）。外观没有实例级参数。

## 5. 状态

### 5.1 状态机

状态变量：`drag ∈ {空闲, 拖动, 已取消}`。悬停、聚焦、禁用由框架维护（08）。"位置"指 `SplitPos`（REQ-LAYOUT-035），"有效 first"指 `splitMetrics` 夹紧后的 `first_px`。

| 当前 `drag` | 事件 | 条件 | 下一 `drag` | 动作 |
|---|---|---|---|---|
| 空闲 | 左键按下于分隔条 | 启用 | 拖动 | 隐式捕获（REQ-INPUT-013）；取得焦点（点击聚焦，焦点不可见）；记下 `press_pos`（按下时的 `SplitPos` 值）与 `grab = 指针沿轴坐标 − 分隔条起点`；不等待拖拽阈值 |
| 拖动 | 指针移动 | — | 拖动 | 按 REQ-W-SPLITTER-006 更新位置，报告 `moved` |
| 拖动 | 左键释放 | 释放仍在分隔条内且构成双击（`click_count = 2`，REQ-INPUT-016） | 空闲 | 位置 ← `default_pos`（覆盖此前拖动的结果）；位置与 `press_pos` 不同则报告 `committed` 并持久化 |
| 拖动 | 左键释放 | 不构成双击，位置与 `press_pos` 不同 | 空闲 | 报告 `committed`；持久化写入 |
| 拖动 | 左键释放 | 不构成双击，位置未变 | 空闲 | 无 |
| 拖动 | Esc 按下（分隔条持有焦点） | — | 已取消 | 位置恢复为 `press_pos`；释放捕获（`ui.releaseCapture()`）；Esc 被消费 |
| 拖动 | 捕获被取消（窗口失活、节点消失等，REQ-INPUT-024）/ 变为禁用 | — | 空闲 | 位置恢复为 `press_pos`；不报告 `committed` |
| 拖动 | 方向键、Home/End、双击 | — | 拖动 | 忽略 |
| 已取消 | 指针移动 / 释放 | — | 已取消；全部按键释放后 → 空闲 | 忽略，不改位置 |
| 空闲 | 方向键/Home/End | 持有焦点 | 空闲 | 按键盘规则移动位置，报告 `moved` 与 `committed` |
| 空闲 | 右键/中键按下释放 | — | 空闲 | 无 |

### 5.2 视觉表现

| 状态 | 绘制（基元 + 令牌） |
|---|---|
| 常态 | 条带无填充（透出所在表面）；居中 `drawSeparator(structural = true)`（`border_strong` 发丝线） |
| 悬停（含键盘无关） | 条带填充 `surface_row_hover`，发丝线照常 |
| 拖动中 | 条带填充 `surface_raised_pressed_top`，发丝线照常；实时调整，**不**画虚影 |
| 焦点可见 | 在覆盖层对条带矩形画 `drawFocusRing(R, radius_mark)`（外环 `focus_ring_w`，`accent_halo`）；条带边框换 `accent_mark` 的发丝线描边 |
| 禁用 | 只画发丝线，颜色 `border_subtle`；无悬停与焦点表现 |

悬停与拖动的条带色是确定的：悬停 `surface_row_hover`、拖动 `surface_raised_pressed_top`；不引入强调色填充（REQ-THEME-004）。

## 6. 鼠标行为

**REQ-W-SPLITTER-005**　分隔条登记指针兴趣 `click`（不登记 `drag`）：左键在分隔条上按下的**同一次分发**就进入 `drag = 拖动` 并捕获指针，不需要超过拖拽阈值（`SystemMetrics.drag_size` 不适用）。点击聚焦按 REQ-INPUT-022：分隔条获得焦点，焦点不可见。按下本身不改变位置。

**REQ-W-SPLITTER-006**　**实时调整**（指针事件的 `pos` 为相对分隔条节点左上角的 lpx，08）：拖动期间每个 `pointer_move` 都立即重新计算位置，使下一帧的布局反映新分配；不画虚影、不延迟到释放。计算：设拖动轴的指针坐标（根局部，换算为 ppx）为 `p`，Splitter 内部起点为 `s`，`first' = p − s − grab`，再按 REQ-LAYOUT-036 夹紧（`first' = clamp(first', px(min_first), avail − px(min_second))`）。得到的 `first'` 按**当前位置的表示**写回：`ratio` → `first' / avail`；`fixed_first` → `first' / scale`（lpx）；`fixed_second` → `(avail − first') / scale`。拖动**不改变**位置的表示方式。`avail ≤ 0` 或两侧最小值之和超过 `avail`（无处可动）时拖动不产生位置变化。

**REQ-W-SPLITTER-007**　位置的写入**只**由用户操作（拖动、键盘、双击恢复）产生；窗口缩放等使有效 `first` 因夹紧而与请求位置不同时，控件**不得**把有效值写回保存的位置（REQ-LAYOUT-037）。控件在每次构建通过 `ui.splitMetrics(id)` 读取有效 `first_px` 作为键盘与拖动的起点。

**REQ-W-SPLITTER-008**　**双击恢复**：由于按下即进入拖动（REQ-W-SPLITTER-005），双击在**第二次按下之后的释放**时判定：处于"拖动"状态的左键释放若构成双击（释放仍在分隔条内、`click_count = 2`，REQ-INPUT-016），位置设为 `default_pos`（含其表示方式；覆盖第二次按下后可能发生的微小拖动），位置与第二次按下前相比确有变化则报告 `committed` 并持久化。第一次点击（`click_count = 1`，未移动）不改变位置。恢复的是代码给出的默认值，而不是持久化读入的值。

**REQ-W-SPLITTER-009**　**Esc 取消**：拖动中分隔条持有焦点时，Esc 取消拖动：位置恢复为按下时的 `press_pos`（含表示方式），捕获释放，该 Esc **不**再向后传递（不触发取消按钮），不报告 `committed`；此后到全部按键释放前的指针移动与释放被忽略。分隔条仅在 `drag = 拖动` 时声明 Esc 为其处理的键（`InteractOpts.handles` 含 `escape`），其余时候 Esc 不被消费。捕获因其他原因被取消（REQ-INPUT-024）时同样恢复 `press_pos`。

**REQ-W-SPLITTER-010**　指针形状：水平分隔条为 `size_we`，垂直分隔条为 `size_ns`（REQ-THEME-032）；在分隔条上悬停与拖动期间（捕获者声明，REQ-INPUT-021）均如此，拖动时即使指针移出分隔条范围也保持；禁用时为箭头。

**REQ-W-SPLITTER-011**　其他鼠标输入：右键、中键在分隔条上的按下释放不改变状态，分隔条不登记 `context`；滚轮事件不登记 `wheel`，按 REQ-INPUT-019 冒泡到外层滚动容器；双击之外没有多击语义（三击按双击处理一次，不重复恢复）。

## 7. 键盘行为

| 键（分隔条持有焦点） | 行为 |
|---|---|
| ← / →（水平分隔条） | 分隔条左移/右移一个步长（有效 `first` −/+ `px(gap_lg)`） |
| ↑ / ↓（垂直分隔条） | 分隔条上移/下移一个步长 |
| Home | 有效 `first` 取最小值 `px(min_first)`（第一窗格最小） |
| End | 有效 `first` 取 `avail − px(min_second)`（第二窗格最小） |
| Enter | 无作用（不被消费，继续按 08 的默认按钮规则） |
| Esc | 仅拖动中处理（见 REQ-W-SPLITTER-009），否则不处理 |
| Tab / Shift+Tab | 不处理（08 的导航） |
| 与方向轴垂直的方向键 | 不处理（继续冒泡） |

**REQ-W-SPLITTER-012**　分隔条可聚焦且为 Tab 停靠。它经 `InteractOpts.handles` 声明处理与其方向对应的两个方向键与 Home/End，不预占（命令快捷键优先）；不声明 Enter、Space、字符键。

**REQ-W-SPLITTER-013**　键盘移动的计算：以有效 `first_px` 为起点，方向键 `first' = first ± px(gap_lg)`，Home `first' = px(min_first)`，End `first' = avail − px(min_second)`，再夹紧并按当前表示写回（同 REQ-W-SPLITTER-006）；键的自动重复照常重复。每次键盘移动报告 `moved` 与 `committed`（位置有变化时），并持久化写入。到达端点后继续按键无效果。

## 8. 焦点

**REQ-W-SPLITTER-014**　分隔条可聚焦、是 Tab 停靠，点击聚焦（REQ-INPUT-022）。焦点环仅在焦点可见时绘制，且画在覆盖层（REQ-FRAME-017），使它不被窗格内容遮挡；窗口非活动时不画。获得与失去焦点不产生激活类结果。禁用的分隔条不可聚焦。窗格内部的焦点控件不受分隔条影响。

## 9. 文本与输入法

不适用。分隔条不显示文本、不接受文本输入；聚焦时输入法处于禁用状态。

## 10. 动效

| 属性 | 触发 | 时长令牌 | 缓动 | 影响级别 |
|---|---|---|---|---|
| 条带填充（常态 ↔ 悬停/拖动） | 悬停、拖动变化 | `dur_fast` | `ease_out` | paint（`Visual.hover_t`、`press_t`） |
| 焦点环 | 焦点变为可见 | `dur_fast` 淡入，消失瞬时 | `ease_out` | paint（`Visual.focus_t`） |
| 分隔位置 | 任何来源 | 无（实时到位） | — | 见第 14 节 |

分隔条没有自有动画槽；位置变化不做过渡（与"实时调整"一致）。

## 11. 无障碍

| 项 | 值 |
|---|---|
| UIA 控件类型 | Thumb（分隔条）；窗格内容各自独立 |
| 名称来源 | 应用经通用的无障碍名称选项提供；缺省取固定字符串"分隔条"（`Strings`，11 REQ-APP-042） |
| 支持的模式 | RangeValue |
| 状态属性 | IsEnabled、HasKeyboardFocus、Orientation（水平/垂直）、RangeValue：Value = 有效 `first`（lpx）、Minimum = `min_first`、Maximum = `(avail − px(min_second)) / scale`、SmallChange = `gap_lg`、LargeChange = 同 SmallChange |

**REQ-W-SPLITTER-015**　经 UIA 的 `RangeValue.SetValue` 改变位置**必须**与键盘移动等效：在下一帧生效、夹紧、按当前表示写回并报告 `committed`。

## 12. API 草案

```zig
// 草案：仅签名
pub const SplitterOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    orientation: layout.Orientation = .horizontal,
    default_pos: layout.SplitPos = .{ .ratio = 0.5 },
    pos: ?*layout.SplitPos = null,       // 非空：位置由应用持有；框架在用户操作时写回
    min_first: f32 = 0,                  // lpx
    min_second: f32 = 0,
    persist: ?[]const u8 = null,         // 控件名；窗口名取自所在窗口的 persist_name（11）
    layout: layout.ItemOptions = .{},
};

pub const SplitterResult = struct {
    // 持续性状态
    hovered: bool,
    dragging: bool,
    focused: bool,
    pos: layout.SplitPos,                // 当前保存的位置（请求值）
    first: f32,                          // lpx，上一次布局的有效 first
    // 一次性通知（不触发第二构建遍）
    moved: bool,                         // 本帧位置因用户操作变化（每个拖动移动一次）
    // 激活类结果（触发同帧第二构建遍，REQ-FRAME-030）
    committed: bool,                     // 一次完整的用户调整结束：拖动释放、键盘一步、双击恢复
};

/// 之后恰好声明两个子节点作为窗格，再调用 endSplitter。返回的 id 用于 ui.splitMetrics。
pub fn beginSplitter(ui: *Ui, src: std.builtin.SourceLocation, opts: SplitterOptions) ui.WidgetId;
pub fn endSplitter(ui: *Ui) SplitterResult;
```

`committed` 是激活类结果：应用在其为真时可以保存或联动其他状态；`moved` 是一次性通知，**不触发**第二构建遍（拖动中每次移动都触发第二遍会使每帧构建两次）。`pos` 指针由应用持有时须存活至对应 `endSplitter` 返回。窗格内容由调用方在两次 `begin…`/`end…` 之间声明。

## 13. 保留状态

| 字段 | 类型 | 保留级别 | 说明 |
|---|---|---|---|
| `pos` | `layout.SplitPos` | sticky | 应用未提供 `pos` 指针时的位置；首次出现按 `persist` 读取，缺失或越界取 `default_pos` |
| `drag` | `enum { idle, drag, cancelled }` | transient | 拖动状态机（捕获即框架的捕获状态） |
| `press_pos`、`grab_px` | `SplitPos`、`i32` | transient | 按下时的位置与抓取偏移 |

**REQ-W-SPLITTER-016**　**持久化**（11 REQ-APP-037，`UiStateStore.splitter`/`setSplitter`）：`persist` 与所在窗口的 `persist_name` 均非空时，控件首次出现读取一次 `SplitState{ mode, value }`（`mode` 对应三种 `SplitPos`）；`ratio` 不在 0 至 1 之间、`value` 为负或非有限数时忽略该条目并取 `default_pos`。在 `committed` 发生时写入（拖动释放、键盘一步、双击恢复），不在每个拖动移动时写入；Esc 取消不写入。应用持有 `pos` 时仍可同时设置 `persist`：首次出现的读入值写入应用的 `pos`。

**REQ-W-SPLITTER-017**　位置的所有权：应用传入 `pos` 指针时，指针所指的值是唯一事实来源，框架只在用户操作时写回；未传入时保存在 sticky 槽（REQ-FRAME-010），被 LRU 回收后回到 `default_pos`（或持久化值）。

## 14. 失效规则

**REQ-W-SPLITTER-018**　绘制键**必须**由以下各项构成：`orientation`、分隔条矩形（ppx）、是否悬停、是否拖动、焦点环是否显示、`enabled`。布局输入键含 `orientation`、`min_first`、`min_second`（REQ-LAYOUT-045）；`SplitPos` **不**入哈希，它只影响本节点对两个窗格的指派。

| 变化 | 置脏级别 | 损伤范围 |
|---|---|---|
| 悬停进入/离开分隔条、焦点环显隐 | `paint` | 分隔条矩形（焦点环在覆盖层：含外延） |
| 拖动中的指针移动、键盘移动、双击恢复 | `build`（REQ-FRAME-037：被捕获期间的移动与按键）；布局：两个窗格被重新指派矩形 | 旧、新两个分隔条矩形与两个窗格的新旧矩形并集，不超出 Splitter 矩形 |
| 位置未变的重复按键（已到端点） | 无损伤 | 空 |
| 窗口缩放 | `layout` | 整个 Splitter |
| 窗格内容变化 | 由应用的模型通知 `build` | 由差分决定 |

**REQ-W-SPLITTER-019**　仅悬停进入/离开分隔条所产生的帧**必须**是纯绘制帧（构建遍数 0），损伤不超出分隔条矩形。拖动一帧中，Splitter 之外的节点**必须**全部沿用上一帧的测量与排布（`frame.nodes_measure_reused` 的增量不小于这些节点数，REQ-LAYOUT-048）；窗格内的子树按各自的限制变化重新测量（REQ-LAYOUT-046）。

## 15. 边界与错误情况

| 情况 | 规定 |
|---|---|
| `min_first + min_second > avail` | 按 REQ-LAYOUT-036 以比例分配；拖动与键盘无位置变化 |
| 窗格内容比窗格大 | 窗格恒裁剪（REQ-LAYOUT-034），不影响分隔条 |
| Splitter 尺寸为 0 或 `avail ≤ 0` | 两窗格均为 0，分隔条仍占其 `splitter_w`（被裁剪）；不可拖动 |
| 拖动期间窗口缩放 | 以新的 `avail` 继续计算，`grab` 不变；夹紧后的有效 `first` 为准 |
| 拖动期间 `pos` 由应用改写（应用持有时） | 下一次移动以指针重新计算并覆盖；Esc 恢复的是按下时的值 |
| 拖动期间 Splitter 从树中消失 | 捕获释放（REQ-INPUT-024），位置不写入（应用持有时保持最后一次写入值） |
| 持久化读入越界 | 忽略，取 `default_pos`（REQ-W-SPLITTER-016） |
| DPI 变化 | `fixed_first`/`fixed_second` 的 lpx 值按新 `scale` 重新取整；`ratio` 不变 |
| 窗格数不为 2 | 见 REQ-W-SPLITTER-001 |
| 同一帧内拖动移动与 Esc | 先到先处理；Esc 之后的移动忽略 |

## 16. 验收标准

**AC-W-SPLITTER-001**　`[金图]` 覆盖：REQ-W-SPLITTER-004、REQ-W-SPLITTER-014。渲染状态矩阵：{水平, 垂直} × {常态, 悬停, 拖动中, 焦点可见, 禁用}，窗格内各放一个有填充的面板；缩放 1.0/1.25/1.5/2.0；浅/深/高对比度。预期：与基准图一致；发丝线恒居条带正中并对齐整数像素（1.25、1.5 下条带 6 与 8 ppx，线宽 1 ppx，偏移分别为 2 与 3）；拖动中不出现虚影；焦点环仅出现在"焦点可见"列且不被窗格内容遮挡（覆盖层）；禁用列只有 `border_subtle` 发丝线。

**AC-W-SPLITTER-002**　`[回放]` 覆盖：REQ-W-SPLITTER-005、REQ-W-SPLITTER-006、REQ-W-SPLITTER-010。前置：水平 Splitter，矩形宽 805、`splitter_w` = 5（`avail` = 800）、`scale` = 1.0，`pos = ratio(0.25)`（first = 200，分隔条 [200, 205)），`min_first = 0`、`min_second = 0`。步骤与预期：在 x = 202 按下（`grab` = 2）→ 同一次分发内 `dragging` 真、捕获者为 Splitter、位置不变、焦点不可见地落在分隔条；移到 x = 302 → first = 300，位置 `ratio(0.375)`，下一帧窗格宽 300/500；移到 x = 1200 → first = 800（`ratio(1.0)`）；重设 `min_second = 100` 后移到 x = 1200 → first = 700（`ratio(0.875)`）；设 `min_first = 150` 后移到 x = −50 → first = 150（`ratio(0.1875)`）；释放 → `committed` 真（下一帧假）。指针在拖动全程的形状为 `size_we`（含指针移出分隔条后）；垂直 Splitter 为 `size_ns`；释放后指针在窗格上为箭头。表示方式保持：`fixed_first(120)` 起点 first = 120（分隔条 [120, 125)），在 x = 122 按下移到 x = 202 → 位置 `fixed_first(200)`；`fixed_second(100)`（first = 700）在 x = 702 按下移到 x = 652 → `fixed_second(150)`。无处可动：`min_first = 500`、`min_second = 400`（`avail` = 800）→ 拖动无位置变化。

**AC-W-SPLITTER-003**　`[回放]` 覆盖：REQ-W-SPLITTER-003、REQ-W-SPLITTER-011。前置：同 AC-W-SPLITTER-002，位置 `ratio(0.25)`。步骤与预期：保留树中 Splitter 下存在恰一个分隔条部件节点（矩形 [200, 205)，连续构建 ID 不变），指针在其上时命中节点为该节点；指针在窗格 1 内（x = 100）、窗格 2 内（x = 500）移动并按下左键 → 形状为箭头、Splitter 不进入拖动、窗格内按钮可正常点击；在 x = 200 与 x = 204（分隔条首尾）按下 → 进入拖动；在 x = 199 与 x = 205 按下 → 不进入。右键、中键在分隔条上按下释放 → 位置不变、无上下文菜单请求；滚轮在分隔条上滚动（外层为滚动视图）→ 外层偏移变化。

**AC-W-SPLITTER-004**　`[回放]` 覆盖：REQ-W-SPLITTER-007、REQ-W-SPLITTER-008、REQ-W-SPLITTER-009。前置：`min_first = min_second = 100`，`ratio(0.25)`，默认位置 `ratio(0.5)`。步骤与预期：双击分隔条（按下、释放、再按下、再释放，间隔 200 ms，位置同一点）→ 第一次释放无变化（`click_count = 1`，`committed` 假）；第二次释放构成双击 → first = 400，位置 `ratio(0.5)`，`committed` 真；按住拖到 first = 600 后按 Esc → 位置恢复 `ratio(0.5)`（first = 400），捕获者为空，`committed` 假，Esc 未触发所在对话框的取消按钮；Esc 之后继续移动指针（按键仍按住）→ 位置不变；全部按键释放后再按下 → 正常拖动。拖动中令窗口失活（捕获被取消）→ 位置恢复到按下时的值。缩放用例：位置 `ratio(0.25)`，窗口缩小使 `avail` = 300 → 有效 first = 100（夹紧），保存的位置仍为 `ratio(0.25)`，`moved` 与 `committed` 均为假；窗口恢复到 `avail` = 800 → first 回到 200。无 Esc 时 Esc 不被消费：空闲时按 Esc → 所在对话框的取消按钮被触发。

**AC-W-SPLITTER-005**　`[回放]` 覆盖：REQ-W-SPLITTER-012、REQ-W-SPLITTER-013、REQ-W-SPLITTER-014。前置：水平 Splitter，`ratio(0.25)`（first = 200），`min_first = 150`、`min_second = 100`，`scale` = 1.0；Tab 到分隔条（焦点可见）。步骤与预期：→ → first = 212（`ratio(0.265)`，212/800）；← 两次 → 188；Home → 150；End → 700；Enter → 所在范围的默认按钮被触发（Enter 未被分隔条消费）；↑、↓ → 无变化且键被冒泡；另从 first = 188 起注入 5 个自动重复的 → → first 依次为 200、212、224、236、248。`scale` = 1.5：一次 → 移动 18 ppx。垂直 Splitter：↑/↓ 起作用，←/→ 不起作用。每次有变化的按键 `committed` 真；到端点后重复按键 `committed` 假。焦点环出现；鼠标点击分隔条获得焦点但焦点不可见。Tab 序：文本框 → 分隔条 → 窗格内按钮。

**AC-W-SPLITTER-006**　`[单元]` 覆盖：REQ-W-SPLITTER-016、REQ-W-SPLITTER-017。窗口 `persist_name` = "main"，Splitter `persist` = "side"。步骤与预期：首次运行无记录 → 位置取 `default_pos`；拖动释放到 first = 300（`avail` 800）→ `ui.splitters["main/side"]` = `{mode: "ratio", value: 0.375}`，拖动中的各次移动没有写入（写入次数 1）；重启后首次出现读入并应用；记录 `value` = 1.5（越界）、−0.1、NaN → 忽略并取 `default_pos`；`persist` 或窗口名为空 → 不产生条目；Esc 取消不写入。应用持有 `pos`（`fixed_first(120)`）：用户拖动后指针所指值为 `fixed_first(200)`，应用改写为 `fixed_first(90)` 后下一次构建采用；未传入 `pos` 时视图移出树一次构建后恢复 → 位置保留；槽被 LRU 回收后恢复 → `default_pos`。

**AC-W-SPLITTER-007**　`[计量]` 覆盖：REQ-W-SPLITTER-018、REQ-W-SPLITTER-019。前置：界面含一个 Splitter（两窗格内各 100 个节点）和 Splitter 之外的 200 个节点，已稳定。步骤与预期：指针从窗格移入再移出分隔条 → 各帧构建遍数 0，损伤面积 ≤ 分隔条矩形面积（含焦点环外延时 ≤ 其外延后的矩形）；拖动移动一个 20 lpx 步 → 恰一帧、`frame.build_passes` +1（`moved` 不触发第二遍）、Splitter 之外节点全部为复用（`frame.nodes_measure_reused` 的增量 ≥ 200）、损伤 ⊆ Splitter 矩形；对已在端点的键盘重复 → 损伤为空，`frame.presents` 不变；以相同参数 `invalidate(.build)` → 损伤为空。拖动释放那一帧 `committed` 触发第二遍（`frame.build_passes` +2）。

**AC-W-SPLITTER-008**　`[回放]` 覆盖：REQ-W-SPLITTER-001、REQ-W-SPLITTER-002、REQ-W-SPLITTER-015。窗格数：声明 3 个子节点 → 调试构建断言；声明 1 个 → 第二窗格为空且 1 条 `warn`。默认尺寸：置于 Column 内的 Splitter 主轴 `grow(1)`、交叉轴 `fill`。经假 UIA 入口：控件类型 Thumb、RangeValue：Value 200、Min 150、Max 700（`avail` 800、`min_second` 100）、SmallChange 12；`SetValue(300)` → 下一帧 first = 300 且 `committed` 真；`SetValue(900)` → 夹紧为 700。

**AC-W-SPLITTER-009**　`[回放]` 覆盖：REQ-W-SPLITTER-005、REQ-W-SPLITTER-014。`enabled = false`：按下分隔条、方向键、双击均无效；指针为箭头；不在 Tab 序中；金图为禁用外观。拖动进行中令 `enabled` 变假 → 位置恢复为按下时的值，捕获者为空。

**AC-W-SPLITTER-010**　`[人工]` 覆盖：REQ-W-SPLITTER-006、REQ-W-SPLITTER-009、REQ-W-SPLITTER-010。在真实 Windows 上，示例应用的"分隔条"页：用鼠标拖动分隔条，确认窗格内容实时随之重排、无虚影、无需先移动数像素才起动；拖出窗口外后回到窗口内仍连续；在高 DPI（150%、200%）显示器上确认分隔条命中带宽度与发丝线位置；按 Esc 取消；双击恢复；确认指针形状切换及时。观察要点：拖动无卡顿（窗格含 1000 行列表时）、无闪烁、释放后位置不跳变。

## 17. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-W-SPLITTER-01 | 某侧窗格可折叠（拖过最小尺寸一半时吸附为 0，再拖回展开） | 暂不写入条款；先观察实际使用需求。若提供，需新增选项 `collapsible`、折叠态的持久化字段（11 的 `SplitState`）与键盘折叠键 |
| OPEN-W-SPLITTER-02 | （已关闭，见 REQ-W-SPLITTER-013：键盘步长确定为 `gap_lg`） | — |
| OPEN-W-SPLITTER-03 | （已关闭，见 5.2 与 REQ-W-SPLITTER-014：条带色确定为 `surface_row_hover` 与 `surface_raised_pressed_top`） | — |
| OPEN-W-SPLITTER-04 | （已关闭，见 REQ-W-SPLITTER-003：分隔条为框架创建的独立部件节点） | — |
| OPEN-W-SPLITTER-05 | 垂直方向的 Home/End 在从右到左（RTL）布局下的方向 | 本框架无 RTL（REQ-TEXT-034 固定从左到右）；不处理 |
| OPEN-W-SPLITTER-06 | `moved` 是否应提供给应用用于"拖动中联动"（如实时预览） | 先提供为一次性通知；应用需要逐步联动时读取 `SplitterResult.first` |
