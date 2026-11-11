# 08 输入与焦点

## 1. 范围

定义输入事件的归一化形式、命中测试、事件分发与路由、鼠标语义（悬停、捕获、点击、多击、拖拽、右键、滚轮、指针形状）、键盘路由的优先级、焦点与焦点导航、助记符、禁用、弹出层的输入规则、应用内拖放、以及文本输入类控件与输入法的通用契约。依据 ADR 0005、ADR 0008。

分发发生在帧的第 2 阶段（REQ-FRAME-020），使用上一次构建保留的节点树；控件在第 3 阶段构建时通过 `ui.interact` / `ui.events` 取得结果。各控件特有的键位与鼠标行为由控件规范定义，本文只写通用机制。快捷键所绑定的命令见 11；布局与裁剪见 07；平台事件的来源见 03。

## 2. 术语

| 术语 | 定义 |
|---|---|
| 收件列表 (inbox) | 分发阶段为某个目标 ID 排入的、本帧第一构建遍内可读取的原始事件序列。 |
| 目标 | 事件被投递到的节点 ID。 |
| 命中表 (hit list) | 构建完成并布局后，从保留树中抽取的、按先序排列的"可参与命中"节点数组，每项带绝对矩形与有效裁剪矩形。 |
| 捕获 | 指针事件被强制路由到某个节点，直到捕获被释放。 |
| 预占 (preempt) | 焦点节点声明"这组按键由我处理"，使其先于快捷键表获得这些按键。 |
| 处理声明 (handles) | 节点声明"这组按键我会处理"，使其在快捷键表之后、沿焦点祖先链冒泡时获得这些按键。 |
| 焦点范围 (scope) | Tab 循环不逃逸的节点子集：每个根有一个隐含的根范围；子树可再声明范围。 |
| 漫游组 (group) | 整组占一个 Tab 停靠、方向键在组内移动焦点的节点集合（单选组、工具栏、标签页、菜单栏）。 |
| 焦点可见 | 同 09：由键盘导航获得，或控件是文本输入类，才绘制焦点环。本文定义其状态机。 |
| 助记符 (mnemonic) | 标签中 `&` 标记的字符，Alt+该字符激活对应控件。 |
| 弹出栈 | 一个 `Ui` 内当前打开的非提示框弹出层，按打开次序排列，末项为最上层。 |
| 轻关闭 | 点击所有弹出层之外的区域即关闭弹出栈。 |
| 回投命中 | 分发中以最后已知指针位置重新做的命中测试，用于布局变化后更新悬停。 |

## 3. 规范条款

### 3.1 总则

**REQ-INPUT-001**　事件分发**必须**在帧的第 2 阶段、使用最近一次构建与布局完成后保留的节点树（命中表）进行，**不得**在分发过程中执行构建函数或任何控件代码。分发只更新框架自有的状态（悬停、按下、捕获、焦点、弹出栈、拖放状态）、调用快捷键表所绑定的命令处理函数（REQ-INPUT-029）、并把事件排入收件列表。

**REQ-INPUT-002**　分发**直接消费** 03 的 `platform.Event`（REQ-PLAT-026），不另设事件类型；进入分发前仅做下列换算：指针坐标由客户区 ppx 除以窗口 `scale` 得根局部 lpx（保留 `screen_pos` ppx 用于弹出根与主根的比较）；`key` 事件按 `down` 拆为本文的 `key_down`/`key_up`（`repeat` 透传）；`text` 事件拆为逐码点的 `char`；`wheel` 按 REQ-INPUT-020 换算；`mods` 即 `platform.Mods`；`time_ms` 是同一单调时钟（REQ-FRAME-021）。`Event` 的 `window` 经 `Ui` 的根表映射到所属根。本文只定义分发之后、投递给节点的 `NodeEvent`。

**REQ-INPUT-003**　分发**必须**只做路由，其全部工作限于：(1) 确定目标；(2) 更新悬停/按下/焦点/捕获状态；(3) 处理快捷键、助记符、默认/取消按钮与 Tab 导航；(4) 把事件排入目标 ID 的收件列表；(5) 按 REQ-FRAME-037 置脏。

**REQ-INPUT-004**　控件**必须**在构建时通过 `ui.interact(id, opts)` 登记其输入兴趣并取得汇总结果 `Interaction`；需要原始事件序列时再通过 `ui.events(id)` 读取收件列表。未经 `interact` 登记的节点不参与命中、焦点（`NodeFlags.focusable` 仍须置位）以外的任何输入路由，`ui.events` 对其调试构建断言。同一节点在一次构建遍内多次调用 `interact` 时，以第一次的 `opts` 为准，结果相同。登记信息随节点树保留，供下一轮分发使用。

**REQ-INPUT-005**　`Interaction` 的字段分三类：
- **持续性状态**：悬停、按下、捕获、拖动中、焦点、焦点可见、有效禁用状态、指针相对位置、拖动位移。在第二构建遍中保持不变。
- **激活类结果**：`clicked`、`double_clicked`、`triple_clicked`、`right_clicked`、`middle_clicked`、`context_menu`、`drag_started`、`drag_ended`、`drag_cancelled`、`activated`。一次性；它们在第一构建遍中为真会触发同帧第二构建遍（REQ-FRAME-030），在第二遍中全部为假（REQ-FRAME-033）。
- **一次性通知**：`focus_gained`、`focus_lost`、`wheel`（未被消费的滚轮增量）、`popup_dismissed`。一次性，第二遍中为假，但**不**触发第二构建遍。

**REQ-INPUT-006**　事件**只投递一次**（REQ-FRAME-033）：收件列表在第一构建遍结束时清空，第二遍读到空列表。同一轮消息内的事件**必须**保序投递，且按下列规则处理：没有捕获时的纯悬停 `pointer_move` 不进入任何收件列表、不置脏（REQ-FRAME-037），只更新悬停结算所用的最后指针位置（连续多个只保留最后一个）；有捕获时的 `pointer_move` 全部保留；同一目标上连续的 `wheel` 累加为一个事件（增量相加，修饰键取最后一个）；键盘与字符事件从不合并。悬停的进入/离开只体现为 `Interaction.hovered` 的变化，不产生收件事件。

### 3.2 命中测试

**REQ-INPUT-007**　命中测试**必须**在命中表上进行：命中表由登记了指针兴趣（`Sense` 任一位为真，含 `hover`）的节点按先序排列而成。给定根局部点 `p`，**逆先序**（后绘制者优先）遍历命中表，返回第一个满足下列全部条件的节点，否则无命中：
1. 节点及其任一祖先均未 `hidden`；
2. 节点未标记 `hit_passthrough`；
3. `p` 落在节点布局矩形与其有效裁剪矩形的交集内。有效裁剪矩形 = 所有置 `clip_children` 的祖先的矩形之交（Scroll 的视口、Splitter 窗格等，07），在布局阶段末尾为命中表一次性算出。

命中范围就是布局矩形，不含 `paint_outset`。

**REQ-INPUT-008**　`hit_passthrough` 只作用于带该标志的节点本身，不作用于其后代；`hidden` 作用于整棵子树。覆盖层（REQ-FRAME-017）**不得**进入命中表，不参与任何命中测试。

**REQ-INPUT-009**　**禁用节点可被命中但吞掉事件**：命中的节点（或其任一祖先）处于有效禁用状态时，命中结果仍是该节点（使悬停与提示框可用），但不产生按下、捕获、点击、拖拽、上下文菜单、聚焦；事件**不得**穿透到其下方被遮挡的节点。例外：滚轮可经禁用节点向其启用的祖先冒泡（REQ-INPUT-019）。有效禁用 = 节点自身或任一祖先 `NodeFlags.disabled`。

**REQ-INPUT-010**　`Ui` 有多个根时：弹出根优先于主根。指针（以屏幕坐标判断）落在某个非提示框弹出窗口的范围内时，**只**测试该弹出根（多个重叠时取最后打开者）；该弹出根内无命中时目标为无，**不得**落到其下方的宿主根。提示框弹出层（`PopupKind.tooltip`）不参与命中，指针在其上时命中结果等同于它不存在。指针不在任何弹出窗口范围内时测试主根（受 REQ-INPUT-052 的轻关闭约束）。

**REQ-INPUT-011**　每次构建与布局完成后、损伤计算之前，**必须**用最后已知的指针位置重新做一次命中测试（回投命中），按 REQ-INPUT-012 更新悬停。悬停目标变化时对新旧目标置 `paint`（若带 `hover_rebuild` 则置 `build`，REQ-FRAME-037）。窗口内没有已知指针位置（指针从未进入或已离开）时不做。

### 3.3 鼠标

**REQ-INPUT-012**　悬停目标 = 无捕获时命中测试的结果。`Interaction.hovered` 对悬停目标为真；`hovered_within` 对悬停目标及其全部祖先为真，并对拥有该悬停目标所在弹出根的 `owner` 链上的节点也为真（子菜单打开时，其父菜单项 `hovered_within` 为真）。指针离开窗口（`pointer_leave`）使悬停清空，除非存在捕获。指针从宿主窗口移入其弹出窗口（或相反）时，两个窗口的离开/进入**必须**在同一轮分发后合并结算，不得产生中间"无悬停"的一帧。

**REQ-INPUT-013**　**隐式捕获**：在登记了 `click` 或 `drag` 的启用节点上按下任一鼠标键，该节点**必须**立即捕获指针，直到**所有**按键释放；捕获期间全部 `pointer_move` 与 `pointer_up` 都投递给捕获者，不论指针位置，悬停目标被捕获者固定（其他节点的 `hovered` 为假）。捕获释放后，下一次回投命中更新悬停。 节点在 `InteractOpts` 中置 `capture_on_press = false` 时按下不建立隐式捕获：其后的移动与释放按命中测试正常路由（包括路由到按下后才出现的弹出根），该节点自身不会得到"点击"，只得到 `press`。用途：菜单栏顶层项的"按下–拖动–释放"激活。

**REQ-INPUT-014**　`Interaction.pressed` **必须**仅在节点持有由主键（左键）按下产生的捕获**且**指针当前位于节点命中范围内时为真；指针拖出后变假，拖回后变真。`captured` 则只要持有捕获即为真。命中范围指 REQ-INPUT-007 第 3 条的矩形判断，不再要求该节点是最上层命中结果。

**REQ-INPUT-015**　**点击**定义为同一节点上的按下与释放：同一按键在节点 N 上按下并被 N 捕获，释放时指针仍在 N 的命中范围内，且期间没有开始拖拽（若 N 登记了 `drag`，REQ-INPUT-017）、捕获未被取消（REQ-INPUT-024）。满足时在释放所在的分发中使 N 的 `clicked`（左键）、`right_clicked`、`middle_clicked` 为真，并附 `click_count`（REQ-INPUT-016）与 `click_button`。点击在**释放**时产生；按下时的反馈（按下外观、聚焦）由持续性状态与 REQ-INPUT-022 提供。

**REQ-INPUT-016**　**多击**：连续两次同一按键的按下，若间隔 ≤ 系统双击时间（`GetDoubleClickTime`）、第二次位置落在以上一次按下位置为中心、宽高为 `SM_CXDOUBLECLK`×`SM_CYDOUBLECLK` 的矩形内、且命中同一节点，则点击计数加 1。计数取 1、2、3，第 4 次按下重新从 1 开始；任一条件不满足则重置为 1。三个系统值经 03 读取，**不得**写死。`Interaction.click_count` 为触发 `clicked` 那次按下的计数；`double_clicked` 与 `triple_clicked` 分别等价于 `clicked && click_count == 2/3`；按下事件本身也携带 `clicks`，供文本选择（按下即选词/选行）使用。

**REQ-INPUT-017**　**拖拽**：仅登记了 `drag` 的节点。按下后指针离开以按下点为中心、宽高为 `SM_CXDRAG`×`SM_CYDRAG`（经 03 读取）的矩形时，拖拽开始：`drag_started` 为真（激活类）、`dragging` 为真，`drag_delta` = 当前指针 − 按下点（lpx），并**取消**该次按下的点击。拖拽期间 `drag_delta` 随每个 `pointer_move` 更新；全部按键释放时 `drag_ended` 为真、`dragging` 为假。未登记 `drag` 的节点不做拖拽检测，其点击按 REQ-INPUT-015 判定（指针拖出再拖回仍可点击）。

**REQ-INPUT-018**　**右键与上下文菜单**：右键点击按 REQ-INPUT-015 判定，`right_clicked` 在释放时为真；同一次释放同时产生 `context_menu = ContextRequest{ pos, anchor, from_keyboard = false }`（`pos` 为指针位置、`anchor` 为以其为原点的 1×1 lpx 矩形），仅投递给登记了 `context` 的、命中链上最近的节点（命中节点自身起沿祖先上溯）。键盘触发：焦点位于某节点时，`Shift+F10` 与菜单键（`platform.VirtualKey.apps`）向焦点节点自身起沿祖先上溯、最近的登记了 `context` 的节点投递 `ContextRequest{ pos = 焦点节点矩形左下角, anchor = 焦点节点矩形, from_keyboard = true }`；控件可经文本光标等信息在构建时自行调整位置。这两个键是框架内建键位，**不受**预占（REQ-INPUT-028）影响。

**REQ-INPUT-019**　**滚轮路由**：滚轮事件的目标由**指针位置**决定，与键盘焦点无关。从命中目标（含被禁用者）起沿祖先上溯，取第一个登记了 `wheel` 且其 `WheelCaps` 在事件方向上为真的未禁用节点；`WheelCaps`（`up`/`down`/`left`/`right`）由控件在构建时依据上一次布局的 `ScrollMetrics`（07）声明"仍可朝该方向滚动"。无这样的节点时事件被丢弃，**不得**改投主根或弹出根之外的节点。纵向与横向分量各自独立解析目标。弹出根上的滚轮只在该弹出根内路由。

**REQ-INPUT-020**　滚轮的数值与修饰：投递给节点的增量以"格"为单位的浮点数，**格 = `platform.Event.wheel.raw / 120.0`**（高分辨率滚轮产生小数；平台层的整数 `steps` 不使用）。`Interaction.wheel` 与 `NodeEvent.wheel` 给出累计的格数。每格滚动多少行/字符由控件读取 `SystemMetrics.wheel_lines`/`wheel_chars`（03，REQ-PLAT-047）：本文按其值设置事件的 `page` 标志（值为 `page` 时 `page = true`），**平台层不做行数换算**。按住 Shift 时，纵向分量转为横向分量参与解析。按住 Ctrl 时只投递给 `WheelCaps.zoom` 为真的节点（不与滚动混用）。 目标是由框架保留偏移的 Scroll 容器时，分发阶段**直接**把该滚轮量换算并应用到其滚动偏移（夹紧），该事件不进入收件列表，置脏级别按 REQ-FRAME-037 为 `layout`；偏移由应用持有的 Scroll 容器仍经收件列表在构建中处理。

**REQ-INPUT-021**　**指针形状**由悬停节点声明（`InteractOpts.cursor`，类型为 03 的 `platform.CursorShape`）；存在捕获时由捕获者声明。有效禁用的节点一律为 `arrow`；无悬停目标时为 `arrow`。形状在每轮分发末尾与每次回投命中后重新求值，变化时调用 `Window.setCursor`，**不**置脏、不产生帧。"键入时隐藏指针"（`CursorShape.hidden`）是平台层的职责，本文不规定其触发与恢复。

**REQ-INPUT-022**　**点击聚焦**：在按下时（而非释放时），从命中目标起沿祖先上溯第一个 `focusable` 且未禁用且 `InteractOpts.take_focus_on_click` 为真的节点获得焦点（原因 `pointer`）。按在不可聚焦区域（含无命中）**不得**清除当前焦点。工具栏按钮等"不取焦点"的控件置 `take_focus_on_click = false`。按下被禁用节点吞掉时不改变焦点。

**REQ-INPUT-023**　**触摸与笔**仅作为鼠标（REQ-VIS-008）：平台层只依赖系统把触摸/笔提升为鼠标消息（REQ-PLAT-030），分发看到的就是普通的 `mouse_move`/`mouse_button`，不区分来源，不设专门的悬停语义；`mouse_leave` 的处理与鼠标相同。不实现多点触控、手势、惯性滚动。

**REQ-INPUT-024**　捕获的终止：下列任一情形**必须**释放捕获并**取消**进行中的点击/拖拽（不产生 `clicked`；拖拽产生 `drag_cancelled` 而非 `drag_ended`），随后做回投命中：节点在新树中消失；节点变为有效禁用；窗口失去激活；平台报告捕获丢失（`capture_lost`，如 `WM_CAPTURECHANGED`）；弹出栈因轻关闭而清空且捕获者属于被关闭的弹出根。控件可经 `ui.capturePointer(id)` 显式获取捕获（用于一个控件由多个节点组成时，例如滚动条滑块），只能在该节点持有按下状态的分发之后的构建中调用，并经 `ui.releaseCapture()` 释放；`ui.capturedId()` 读取当前捕获者。

### 3.4 键盘路由

**REQ-INPUT-025**　键盘事件（`key_down`）的路由**必须**按下列八级优先级逐级判断，前级处理（消费）了该键则停止，后级不再看到它：

| 级 | 名称 | 规则 |
|---|---|---|
| ① | 输入法 | 输入法组字期间，全部键盘与字符事件只交给输入法与焦点文本节点（REQ-INPUT-026） |
| ② | 弹出层 | 存在打开的、抢占键盘的弹出层时交给最上层弹出根（REQ-INPUT-027） |
| ③ | 预占 | 焦点节点声明预占的键，投递给它（REQ-INPUT-028） |
| ④ | 快捷键 | 命令快捷键表（REQ-INPUT-029） |
| ⑤ | 冒泡 | 焦点节点及其祖先中声明了处理该键者（REQ-INPUT-030） |
| ⑥ | 助记符 | Alt+字符（REQ-INPUT-033） |
| ⑦ | 默认/取消 | 所在范围的默认按钮（Enter）与取消按钮（Esc）（REQ-INPUT-034） |
| ⑧ | 焦点导航 | Tab / Shift+Tab（REQ-INPUT-035） |

没有节点消费的键被丢弃，**不得**回流给平台层的默认处理（系统菜单键 Alt+Space 等 03 另行规定的除外）。

**REQ-INPUT-026**　**①**：输入法处于组字状态时，到达的 `key_down`/`key_up`/`char` **只**投递给持有焦点的文本输入类节点，**不得**进入 ②–⑧ 任一级（快捷键、Tab、Enter 默认按钮、Esc 取消均不触发）。**组字状态**以 03 的事件界定：收到 `ime_start` 后进入，收到 `ime_end` 后退出；`ime_end` 在提交之后与取消之后都会到达，是组字状态结束的**唯一**标志（`ime_commit` 本身不结束组字状态）。输入法自己消费的键不会作为 `key` 事件出现（REQ-PLAT-031，平台层的责任）。

**REQ-INPUT-027**　**②**：弹出栈非空时，若最上层弹出根的 `keyboard = grab`，则全部 `key_down`/`key_up`/`char` 投递给该弹出根的弹出焦点节点（REQ-INPUT-036）；无弹出焦点节点时投递给弹出根的 `owner`。弹出根未消费的键被丢弃（**不得**漏给宿主根），唯一例外是 Esc：弹出根内无节点声明处理 Esc 时，框架**关闭**最上层弹出层（原因 `escape`，REQ-INPUT-054）。最上层弹出根为 `keyboard = passive` 时，键盘不进入该级，但若按下 Esc 且弹出层 `close_on_escape` 为真，框架在进入 ③ 之前关闭它并消费该键。 例外：Alt 单键释放与 `F10` 产生的"激活菜单栏"通知不受弹出根抢占影响，始终投递给主根中登记了菜单栏的节点（菜单据此在展开状态下关闭全部菜单并退出菜单栏模式）。

**REQ-INPUT-028**　**③**：焦点节点经 `InteractOpts.preempt`（`KeyMask`）声明预占的键，**先于**快捷键表投递给它。文本输入类控件**必须**预占：字符键（`printable`）、方向键、Home/End、PageUp/PageDown、Backspace/Delete、`Ctrl+A/C/V/X/Z/Y`、`Ctrl+Insert`、`Shift+Insert`、`Shift+Delete`；多行文本再预占 Enter 与 Tab 的使用方式由控件规范规定。精确清单由各控件规范列出，不在预占清单内的键继续向后级传递。框架内建的上下文菜单键（REQ-INPUT-018）与 `F10`/`Alt` 单键（菜单栏激活）不可被预占。 `KeyGroups` 中的各键组只匹配**无修饰或仅带 Shift** 的按键；带 Ctrl 或 Alt 的组合必须在 `KeyMask.extra` 中逐个列出才被预占，未列出的修饰组合继续走第 ④ 级及以后（例如文本框不列 Ctrl+PageUp/PageDown，则标签页切换仍然有效）。 **观察**：焦点节点经 `InteractOpts.observes` 声明的键在第 ③ 级被放入其收件列表但**不消费**，路由照常继续到后续各级。用途：文本框观察 Enter 以报告 `committed`，同时 Enter 仍会触发所在范围的默认按钮（第 ⑦ 级）。同一个键不得同时出现在 `preempt` 与 `observes` 中。 `KeyMask.extra` 可以列出任意和弦，含不带修饰键的单键（如仅预占 ↑ 与 ↓ 而不要整个方向键组、小键盘的 `*`）。

**REQ-INPUT-029**　**④**：快捷键表由 11 的命令系统提供，以 `ShortcutSource` 接口接入。对一个**非自动重复**的 `key_down`，以 `Chord{key, mods}` 查表：命中且命令**启用**时，立即在分发阶段调用该命令的处理函数（11），置 `build` 脏并消费该键；命中但命令**禁用**时消费该键而**不**执行；未命中则继续。修饰键匹配为精确匹配（Shift/Ctrl/Alt/Win 四位全相等；Caps Lock、Num Lock 不参与）。平台标记为 AltGr 的组合（`Mods.altgr`）**不得**匹配快捷键表，按字符输入处理。被 ④ 消费的 `key_down` 随后产生的 `char` 事件**必须**被丢弃（REQ-INPUT-031）。

**REQ-INPUT-030**　**⑤**：从焦点节点起沿祖先链逐个检查，第一个其 `InteractOpts.handles`（`KeyMask`）包含该键的节点获得该键的 `key_down` 事件并消费之。到达根仍无人声明时，若焦点位于漫游组内且该键是组的导航键（REQ-INPUT-038），由框架在组内移动焦点。没有焦点节点时 ⑤ 无事发生。控件对"我处理了这个键"的声明必须在构建时通过 `handles` 给出（分发时不运行控件代码），声明过宽（声明了却不处理）会吞键，属于控件缺陷。

**REQ-INPUT-031**　`char` 事件**必须**只投递给持有焦点且其 `preempt.printable` 为真（或 `text_input` 为真）的节点；其余情形丢弃（含 Ctrl+字母产生的控制字符 U+0001–U+001F，以及被 ④–⑧ 消费的 `key_down` 所对应的字符）。`char` 紧随其对应的 `key_down` 到达，两者在同一轮分发内保序投递给同一目标。 "可打印键"的精确定义：凡会由当前键盘布局产生 `char` 事件的按键（含 Shift 与 AltGr 层），其 `key_down` 视为被 `preempt.printable` 预占；带 Ctrl 或 Alt（非 AltGr）的按键不产生 `char`，不属于可打印键，按 REQ-INPUT-028 的规则须在 `extra` 中逐个列出才被预占。

**REQ-INPUT-032**　`key_up` **必须**投递给收到了对应 `key_down` 的节点（框架记住每个键最近一次 `key_down` 的接收者，节点消失则丢弃该 `key_up`）；未被任何节点接收的 `key_down` 的 `key_up` 被丢弃。自动重复的 `key_down` 带 `repeat = true`，按相同的路由规则投递，但**不**触发 ④ 的快捷键、⑥ 的助记符与 ⑦ 的默认/取消按钮。

**REQ-INPUT-033**　**⑥ 助记符**：`Alt+字符键`（Alt 单独为修饰，不含 Ctrl）在 ③–⑤ 均未消费时，于焦点所在的根内查找登记了该字符助记符（REQ-INPUT-048）的、可见且启用的节点；行为见 REQ-INPUT-048。单独按下并释放 Alt 的处理：切换键盘提示可见（REQ-INPUT-047），并向主根登记了菜单栏的节点投递 `activate_menu_bar` 事件（具体见菜单栏控件规范）。 `F10` 单键（无修饰）与 Alt 单键等效：产生同样的"激活菜单栏"通知；`F10` 不可被 `preempt` 预占。

**REQ-INPUT-034**　**⑦ 默认与取消**：Enter（无修饰）在前级均未消费时，找到焦点节点所在的最内层范围（REQ-INPUT-039）的 `default_button`；该节点存在、可见、启用时，向它投递一次 `activate{source = default_button}` 并使其 `Interaction.activated` 为真，消费该键。Esc 同理对应 `cancel_button`（`source = cancel_button`）。无此类范围或按钮不可用时，Enter/Esc 丢弃。获得焦点的普通按钮对 Enter/Space 的响应属于 ⑤（按钮声明 `handles` 这两个键），故 Enter 在按钮上激活按钮自身而不是默认按钮。

**REQ-INPUT-035**　**⑧ Tab 导航**：`Tab` / `Shift+Tab` 在前级均未消费时移动焦点：以当前焦点节点的**先序位置**为基准，取所在范围内 Tab 序的下一个/上一个停靠点（REQ-INPUT-037）；到末尾回绕到开头，反之亦然；焦点节点本身不在 Tab 序内（如 `tab_stop = false`）时同样以其先序位置为基准。范围内没有 Tab 停靠点时无事发生。导航产生的焦点变化原因为 `tab`。 `Ctrl+Tab` / `Ctrl+Shift+Tab` 先按第 ⑤ 级交给焦点节点的祖先处理（标签页用它切换页）；无人处理时在本级按 `Tab` / `Shift+Tab` 的规则移动焦点，使预占了 `Tab` 的多行文本框仍可用键盘离开。

### 3.5 焦点

**REQ-INPUT-036**　每个 `Ui` **至多一个**焦点节点（`ui.focusedId()`）。每个抢占键盘的弹出根另有各自的**弹出焦点**，由弹出根内的 `ui.setFocus` 设置；弹出打开期间宿主的焦点节点保持不变（不丢失、不重绘为非焦点），只是键盘被 ② 截走；弹出栈清空后键盘回到宿主焦点节点。`Interaction.focused` 对宿主焦点节点在其窗口激活期间为真，对弹出焦点节点在其弹出根存在期间为真。

**REQ-INPUT-037**　**Tab 序** = 节点树先序中同时满足"`focusable`、`tab_stop`、未禁用、本身与祖先均未 `hidden`"的节点序列，范围由 REQ-INPUT-039 限定。`NodeFlags.tab_stop` 默认为真；设为假的可聚焦节点只能由鼠标、方向键组导航或程序设置焦点。Tab 序**不**随视觉位置重排；滚出视口但未隐藏的节点仍在序内，获得焦点时由 REQ-INPUT-044 使其可见。

**REQ-INPUT-038**　**组内漫游**：控件经 `ui.focusGroup(id, GroupSpec)` 声明一个漫游组（单选组、工具栏、标签页、菜单栏）。组的后代中的可聚焦节点为成员；整组在 Tab 序中只有**一个**停靠点：`GroupSpec.current` 指定的成员（`none` 时取组内最近一次获得焦点的成员，再无则第一个启用的成员），其余成员的 `tab_stop` 被框架视为假。组内的方向键（`horizontal`：←/→；`vertical`：↑/↓；`both`：四个方向键，←/↑ 为前一个、→/↓ 为后一个）在成员间移动焦点，跳过禁用与 hidden 成员，`wrap` 为真时首尾回绕；`home_end` 为真时 Home/End 到首/末成员。组导航发生在 ⑤ 的末端（成员自身未声明处理这些键时），焦点变化原因为 `group`。成员获得焦点即成为组的当前成员。 补充规则：(a) `ui.focusGroup` **可以**在容器的 `begin` 与 `end` 之间的任意时刻调用（含全部子项声明之后），框架在本次构建完成时解析组成员与 `current`；(b) 组容器子树内声明了 `text_input` 或预占了方向键的节点（文本框、下拉框等）**自动排除**出漫游组：它们各自是独立的 Tab 停靠，方向键在其上按自身规则处理，Tab 序仍按先序穿插在组的停靠点前后。 (c) `GroupSpec.tab_stop = false` 的组**没有** Tab 停靠点，只能通过助记符、程序设置焦点或专用按键进入（菜单栏经 Alt / F10 进入）。

**REQ-INPUT-039**　**焦点范围**：每个根有一个隐含的根范围；`ui.rootScope(ScopeSpec)` 配置当前根的范围，`ui.focusScope(id, ScopeSpec)` 声明子树内的嵌套范围。`ScopeSpec` 含 `default_button`、`cancel_button`、`initial_focus`、`trap_tab`。`trap_tab` 为真（根范围恒为真，嵌套范围默认为假）的范围内 Tab 循环**不逃逸**：到达范围内末尾回绕到开头，**不得**进入范围外的节点或其他根。对话框窗口（11）、弹出根均为独立的根，因此各自 Tab 循环；弹出层内的 Tab 不进入宿主。⑦ 取焦点节点所在的最内层声明了 `default_button`/`cancel_button` 的范围。

**REQ-INPUT-040**　**焦点可见**：`Ui` 维护布尔状态 `focus_visible`，初值假。**任一** `key_down`（含单独的修饰键）到达时置真；**任一**指针按下（`pointer_down`，任意按键、任意来源）到达时置假；程序化设置焦点不改变它。`Interaction.focus_visible` = `focused && window_active && (focus_visible || 节点是文本输入类)`，文本输入类由 `InteractOpts.text_input` 声明。控件仅在 `focus_visible` 为真时绘制焦点环（09，REQ-THEME-023）。因此：鼠标点击按钮不画焦点环；Tab 到按钮或按键后画；点击文本框始终画。该状态变化对当前焦点节点置 `paint`。窗口失去激活时不画焦点环（但状态保留）。

**REQ-INPUT-041**　窗口失去激活时：焦点节点**被记住**（`focused` 不变，但按 REQ-INPUT-040 不画环）；进行中的捕获、点击、拖拽被取消（REQ-INPUT-024）；键盘提示恢复默认隐藏（REQ-INPUT-047）；弹出栈按 REQ-INPUT-054 关闭。重新激活时焦点恢复到被记住的节点；若该节点已不可聚焦，按 REQ-INPUT-042 转移。激活窗口的那一次鼠标点击正常投递给其命中目标（不被吞掉）。窗口激活状态变化按 REQ-FRAME-037 对整窗置 `paint`。

**REQ-INPUT-042**　**焦点节点消失或失格时的转移**（确定性算法）。失格 = 在新树中不存在，或存在但未禁用/hidden/可聚焦三者之一不满足。在每次构建完成、布局之前执行，旧树仍可访问：
1. 设旧焦点节点为 F，范围为 S（F 所在最内层范围；若 S 也不存在则取 F 所在根的根范围；若该根已消失，取主根的根范围）。
2. 在**旧树**的先序中从 F 向前（先序前驱方向）找到第一个在新树中仍存在的节点 Q；若不存在，Q 取 S 的起点。
3. 候选集 C = 新树中范围 S 内的 Tab 停靠节点（REQ-INPUT-037）。取 C 中先序位置在 Q **之后**的第一个节点；若无，取 C 中先序位置在 Q **之前或等于 Q** 的最后一个节点；若 C 为空，焦点置空。
4. 转移的原因为 `transfer`；不改变 `focus_visible`。

**REQ-INPUT-043**　焦点的程序设置：`ui.setFocus(id)` 在构建中调用，在**本次构建完成后**（REQ-INPUT-042 之前）对新树生效；目标节点不存在、不可聚焦或被禁用时请求被丢弃并在调试构建报告 `warn`。`ui.clearFocus()` 同样延迟生效。**初始焦点**：根的首次构建完成后，若无焦点，则取 `ScopeSpec.initial_focus`，其次取根范围内 Tab 序的第一个节点；弹出根打开时同理（`keyboard = grab` 者）。`ui.autoFocus(id)` 登记"该节点首次出现的那次构建完成后获得焦点"，之后不再生效；同一构建内多个 `autoFocus` 取先序最先者。以上原因均为 `programmatic`。 `ui.setFocusReason(id, reason)` 与 `setFocus` 相同但由调用方指定 `FocusReason`（例如微调框的箭头按钮在按下时把焦点交给其文本区，原因为 `pointer`，从而不触发"程序设置焦点时全选"）。对话框的初始焦点：`ScopeSpec.initial_focus` 为空时取 Tab 序第一个节点；`w.dialogButtons` 在对话框首次构建时按 dialog.md 的优先级（指定者 > 第一个可聚焦的非按钮控件 > 默认按钮）算出目标并设置 `initial_focus`，所以对话框不落入"Tab 序第一个"的缺省。

**REQ-INPUT-044**　键盘导航（原因 `tab`、`group`、`mnemonic`）使节点获得焦点后，框架**必须**向该节点的每个祖先中登记了 `reveal_target` 的节点（Scroll）投递 `reveal{rect}` 事件（`rect` 为焦点节点矩形在该祖先内容坐标系下的 lpx 矩形），Scroll 控件据此设置 `ScrollParams.reveal`（07，REQ-LAYOUT-032）。鼠标点击获得焦点（原因 `pointer`）不产生该事件。

**REQ-INPUT-045**　`FocusReason` 取 `pointer`、`tab`、`group`、`mnemonic`、`programmatic`、`restore`（窗口重新激活）、`transfer`、`initial`。焦点变化时，旧节点的 `focus_lost` 与新节点的 `focus_gained = reason` 在同一次分发（或构建后处理）中成对产生，二者均为一次性通知；焦点变化对两个节点置 `paint`（REQ-FRAME-037）；两个事件进入收件列表，故该帧同时置 `build`（REQ-FRAME-037 首行）。

### 3.6 助记符

**REQ-INPUT-046**　标签文本中的助记符语法：`&` 后紧跟的字符是助记字符；`&&` 表示字面量 `&`；`&` 位于字符串末尾时被忽略；一个标签中第一个 `&x`（x 非 `&`）标记助记字符，其后的 `&x` 只移除 `&`、保留 `x`，不标记。助记字符的比较按 Unicode 简单大小写折叠不区分大小写。`input.parseMnemonic(arena, label)` 返回去掉 `&` 的显示文本、被标记字符在显示文本中的字节范围（无则为空）与折叠后的字符。控件显示文本**必须**使用解析后的显示文本；命令标题（11）的助记符同此语法。

**REQ-INPUT-047**　助记符下划线的显示遵循系统设置：`SPI_GETKEYBOARDCUES` 为真时始终显示；为假时默认隐藏，任一 `key_down` 为 Alt（及随后的 Alt 组合）时显示，窗口失去激活时重新隐藏。`ui.keyboardCuesVisible()` 给出当前值；其变化对整窗置 `paint`。

**REQ-INPUT-048**　助记符的登记与激活：控件经 `ui.mnemonic(id, ch, action)` 登记，`action` 取 `activate`（聚焦并触发点击语义，按钮、复选框、单选）、`focus`（仅聚焦，如输入框的自带标签）、`focus_next`（静态标签：聚焦先序上其后第一个可聚焦节点）。Alt+字符时，在焦点所在的根内收集登记了该字符的、可见且启用的节点，按先序排列： `focus_within` 把焦点移到登记节点子树内按 Tab 序的第一个可聚焦、未禁用节点（原因 `mnemonic`），子树内没有这样的节点时不做任何事；用于分组框标题等"容器标签"。
- 恰好一个：执行其 `action`；`activate` 产生 `activated = mnemonic`（原因 `mnemonic`）。
- 多于一个：**不激活**，焦点移到先序上位于当前焦点节点**之后**的第一个匹配节点（当前焦点不在匹配集内时取第一个），末尾回绕。
- 为零：丢弃，继续 ⑦。
弹出层（菜单）内的助记符只在其弹出根内查找（REQ-INPUT-027）。

### 3.7 禁用

**REQ-INPUT-049**　**禁用语义**：有效禁用的节点及其后代（1）不可聚焦、不在 Tab 序与组导航中；（2）不产生任何激活类结果，持续性状态中除 `hovered`、`hovered_within`、`disabled` 外全为假，`pointer` 为空；（3）其命中仍吞掉事件（REQ-INPUT-009）；（4）不响应助记符、默认/取消按钮；（5）指针形状为 `arrow`。禁用状态由控件在节点上置 `NodeFlags.disabled`；禁用控件的 `ui.events` 返回空列表。

**REQ-INPUT-050**　禁用发生在节点持有焦点或捕获期间：持有**焦点**的节点变为有效禁用时按 REQ-INPUT-042 转移焦点（视同失格）；持有**捕获**的节点变为有效禁用时按 REQ-INPUT-024 释放捕获并取消点击/拖拽；禁用节点上仍在进行的输入法组字**提交**当前组字文本后再失去焦点（REQ-INPUT-063）。

### 3.8 弹出层的输入规则

**REQ-INPUT-051**　**弹出栈**：`ui.beginPopup(id, PopupSpec)`（06）声明的、`kind` 不是 `tooltip` 的弹出层，按首次出现于树中的先后顺序排入弹出栈，末项为最上层；连续构建中保持其位置。子菜单声明在其父菜单的内容内，`PopupSpec.parent_popup` 指向父弹出层。某弹出层在新树中不再被声明即从栈中移除（同时移除其全部不再被声明的子级）。`PopupSpec` 字段见第 4 节；`PopupSpec.defaults(kind, anchor)` 给出各 `kind` 的缺省：`menu`/`dropdown`/`context_menu`/`autocomplete` 取轻关闭与 Esc 关闭，其中前三者 `keyboard = grab`、`autocomplete` 与 `tooltip` 为 `passive`；`tooltip` 取 `light_dismiss = false`、`close_on_escape = false`，且不可命中。`PopupSpec` 是框架层类型，创建平台弹出窗口时只把 `kind` 映射为 03 的 `platform.PopupWindowKind`：`menu`、`context_menu` → `menu`；`dropdown`、`autocomplete` → `dropdown`；`tooltip` → `tooltip`。`keyboard`、`light_dismiss` 等字段不下沉到平台层。

**REQ-INPUT-052**　**轻关闭**：弹出栈非空时，下列三种点击都构成轻关闭：
(a) **落在本进程窗口之外**（其他应用的窗口、桌面）：平台层以 `popup_dismiss{outside_click}` 通知（REQ-PLAT-069），该点击**不会**转发给被点击的窗口，因此没有"继续投递"；
(b) **落在宿主窗口内、所有弹出窗口之外**：弹出会话期间宿主持有鼠标捕获，该点击以带 `via_popup_capture = true` 的普通 `mouse_button` 事件到达，按屏幕坐标判定不在任何弹出窗口范围内即为外部点击。
(c) **落在本进程的其他窗口内**（另一个应用窗口、对话框）：同样以带 `via_popup_capture = true` 的事件到达宿主（REQ-PLAT-069），按屏幕坐标判定不在宿主窗口与任何弹出窗口范围内。此时只关闭、**丢弃该点击**（不投递给任何节点，也不转给那个窗口；用户需再点一次）。
处理顺序：
1. 对栈中每个 `light_dismiss` 为真的弹出层，向其 `owner` 节点投递 `popup_dismissed{reason = outside_click}`（自上而下），owner 在下一次构建中不再声明它即关闭；
2. 对 (b)，该点击**继续投递**：按 REQ-INPUT-007 在宿主根上做命中测试，按下及其后的释放/点击照常投递给命中节点（同一次分发内，在第 1 步之后）；
3. 落在任一弹出窗口内的按下不是外部点击，包括子菜单与其祖先菜单的窗口。

**REQ-INPUT-053**　**锚点例外**：轻关闭的点击若命中节点就是栈中某个弹出层的 `anchor_id`，则只关闭（第 1 步）并**吞掉**该次按下（该情形必为 REQ-INPUT-052 的 (b)）及其后续的释放/点击（该次按键序列不投递给任何节点，`hovered` 状态不受影响），使"点击打开它的按钮"不会立即重新打开。点击栈中某弹出层的其他内容（如菜单栏中另一个菜单项）不属此例，按 REQ-INPUT-052 正常继续投递。

**REQ-INPUT-054**　**其他关闭情形**（均通过向 `owner` 投递 `popup_dismissed`，原因取 `input.DismissReason` 的下列值）：`Esc`（`escape`，只关最上层一个，REQ-INPUT-027）；宿主窗口失去激活（`host_deactivated`）、被移动（`host_moved`）、被缩放（`host_resized`）、最小化或隐藏（`host_hidden`）、销毁（`host_destroyed`）、系统取消模式（`cancel_mode`）、捕获被本会话之外夺走（`capture_lost`）、DPI 变化（`dpi_changed`），以及**宿主窗口打开应用内模态对话框**（`dialog_opened`，对应 11 的 REQ-APP-017）时，关闭**全部**弹出层（`close_on_host_change` 为假者除外，其仅在 `host_destroyed` 与 `dialog_opened` 时关闭）；应用代码主动关闭属 `programmatic`（只用于诊断，不经此通知）。平台层来源的原因按 REQ-INPUT-064 的映射表转换。关闭弹出层不改变宿主的焦点节点。

**REQ-INPUT-055**　**弹出层不取得窗口激活**（Win32：`WS_EX_NOACTIVATE`，ADR 0008）：弹出层的打开、点击均**不得**使宿主产生窗口去激活事件，宿主的 `window_active` 保持真，宿主焦点节点的 `focused` 保持真。`keyboard = grab` 的弹出层经 ② 取得键盘；`passive` 的弹出层不影响键盘路由（宿主焦点节点仍按 ③–⑧ 处理按键，如带自动完成列表的输入框）。

**REQ-INPUT-056**　**子菜单与悬停延迟**：框架提供 `ui.hoverFor(id, delay)` 与 `ui.notHoverFor(id, delay)`，`delay ∈ {menu, tooltip}`：前者在节点连续被悬停（含 `hovered_within`）满延迟后为真，后者在节点连续未被悬停满延迟后为真；延迟值读取系统度量（`menu` → `SPI_GETMENUSHOWDELAY`；`tooltip` → `SPI_GETMOUSEHOVERTIME`）。两者在未达到时登记一个 `build` 级定时器（REQ-FRAME-050）于到期时刻唤醒，无轮询。子菜单规则：指针悬停于有子菜单的菜单项连续 `menu` 延迟后展开；指针移到同一菜单的其他项后，已展开的子菜单在 `menu` 延迟后收起（期间指针进入该子菜单则取消收起）。键盘展开/收起（→/←）立即生效。

**REQ-INPUT-057**　**提示框**（`ui.tooltip(owner, text)`，其内部使用 `PopupKind.tooltip` 弹出层）：出现条件 = 同时满足：`owner` 已被悬停连续 `tooltip` 延迟（`SPI_GETMOUSEHOVERTIME`，默认 400 ms）；指针在该期间一直位于以其静止点为中心、宽高为 `SPI_GETMOUSEHOVERWIDTH`×`SPI_GETMOUSEHOVERHEIGHT` 的矩形内；无捕获；窗口处于激活状态；弹出栈中无非提示框弹出层；无按键按下。已有提示框显示（或刚在 `tooltip` 延迟的 1/5 时间内消失）时，指针移入另一个带提示的节点，延迟缩短为 `tooltip` 延迟的 1/5。消失条件 = 任一：任一 `key_down`、任一 `wheel`、任一 `pointer_down`、指针离开上述矩形（或悬停目标改变）、窗口失去激活、显示满 10 倍 `tooltip` 延迟（默认 4000 ms）。提示框**不可命中**（REQ-INPUT-010）、不取得激活、不进入弹出栈、不抢占键盘。 控件**可以**不经 `ui.tooltip` 而直接以 `beginPopup` 声明 `kind = .tooltip` 的弹出层（例如滑块拖动中的数值提示），此时出现与消失完全由控件决定，不受"无捕获"与延迟规则约束，其余属性（不可命中、不参与轻关闭）相同。溢出省略文本的提示使用 `ui.tooltipIfTruncated`，判定发生在将要显示的时刻，因此窗口缩放后无需重新构建即可得到正确结果。 **键盘触发**：登记了 `ui.tooltip` 的节点经键盘导航获得焦点且焦点可见时，同样在系统悬停时间后显示提示框，位置在该节点矩形下方（左对齐，越界翻转）；焦点离开、任意按键或指针按下即消失。

**REQ-INPUT-058**　`popup_dismissed` 由 `owner` 节点经 `Interaction.popup_dismissed`（或 `ui.events`）读取，携带 `DismissInfo{ popup: WidgetId, reason: DismissReason }`；**关闭的决定权在应用状态**：owner 把"已展开"状态置假后下一次构建不再声明该弹出层，框架才将其移出栈。owner 忽略该通知并继续声明，则弹出层保持。`owner` 默认为声明 `beginPopup` 时 ID 栈顶的节点，可在 `PopupSpec.owner` 显式指定。

### 3.9 应用内拖放

**REQ-INPUT-059**　**应用内拖放**的生命周期：拖拽源控件在 `Interaction.drag_started` 为真的那次构建中调用 `ui.beginDrag(source_id, payload)`（`DragPayload{ kind: u32, data: u64, ptr: ?*const anyopaque, external: ?*platform.DataObject }`，`ptr` 由调用方保证存活至拖放结束）；此后 `ui.dragInfo()` 返回 `DragInfo{ source, payload, pos, over }`，拖放状态属于 `Ui`，直至结束。拖放期间悬停与点击照常对其他节点停止（捕获仍在拖拽源）；指针形状取拖拽源的声明，被放置目标接受时取目标声明。结束时源收到 `drag_ended`（成功放置或在无目标处释放）或 `drag_cancelled`（REQ-INPUT-024、Esc）。

**REQ-INPUT-060**　**放置目标**：控件经 `ui.dropTarget(id, DropAccept)` 登记，返回 `DropState{ over, acceptable, pos, dropped, payload, effect }`。目标判定与 REQ-INPUT-007 同一套命中规则（逆先序、裁剪、hidden、禁用），仅在拖放进行中、候选限于已登记放置目标的节点。`acceptable` = 载荷的 `kind` 在 `DropAccept.kinds` 内（或外部载荷类型被接受）；`dropped` 在释放那一刻对目标为真（激活类，触发第二遍）。**放置指示**（插入线、高亮框）**必须**画在覆盖层：控件在 `over` 为真时调用 `ui.overlay(id, OverlaySpec)`；覆盖层不参与布局与命中（REQ-FRAME-017）。`Esc` 取消拖放：源收到 `drag_cancelled`，目标收不到 `dropped`，覆盖层指示随下一次构建消失。拖放期间若指针靠近 Scroll 容器边缘的自动滚动由 Scroll 控件规范定义。

**REQ-INPUT-061**　**与 OLE 拖放（03）的衔接**：(1) **出**：载荷带 `external`（`allow_external`）且指针离开本窗口所有根的范围时，框架登记一个 `afterFrame` 动作（REQ-FRAME-027）在帧后调用 `platform.startDrag`（REQ-PLAT-063），此后内部拖放结束（源在该调用返回后收到 `drag_ended`/`drag_cancelled`）；(2) **入**：平台的 `drag_enter/drag_over/drag_leave/drop` 事件（OLE `IDropTarget`）进入同一套放置目标判定，`DropAccept.external_files`/`external_text` 声明可接受的外部类型，`DropState.effect` 的结果由框架经 `Window.setDropEffect` 回报给平台层（REQ-PLAT-061 的"上一决定"模型）；(3) 外部拖入期间不产生 `drag_started`，目标只通过 `DropState` 感知。

### 3.10 输入法与文本输入

**REQ-INPUT-062**　文本输入类控件与输入法的**通用契约**：(1) 控件在 `InteractOpts` 中置 `text_input = true`，框架在其获得焦点时调用 `Window.setImeEnabled(true)`，焦点落在非文本节点时调用 `setImeEnabled(false)`；(2) 组字过程以 03 的事件投递给焦点节点：`ime_start`、`ime_update{ text, segments: []platform.ImeSegment, cursor }`（`text` 为组字串 UTF-8，`cursor` 为其中的字节位置，`segments` 为按 UTF-8 字节范围划分的子句及其样式）、`ime_commit{ text }`、`ime_end`；(3) 光标矩形**由框架统一换算**：控件在构建时调用 `ui.imeCaret(id, caret, exclude)`，`caret` 为相对节点的 lpx 光标矩形（覆盖组字串当前插入位置），`exclude` 为可选的相对节点的 lpx 目标子句矩形（候选窗应避开的区域，无则为 `null`）；（换算规则：矩形四条边各自乘以 `scale` 后四舍五入到整数 ppx，宽高取对边之差，且宽度不小于 1 ppx）框架在布局完成后加上节点的绝对位置、乘以 `scale` 取整为客户区 ppx，调用 `Window.setImeCaretRect(caret, exclude)`（03）；光标、滚动、窗口位置、DPI 变化与每次 `ime_update` 之后的重新报告由框架在布局后负责；(4) 候选窗由系统绘制；(5) 具体编辑行为（组字串的显示、替换选区）由文本输入控件规范定义。非文本输入类的节点不会收到 `ime_*` 事件。 输入法的启用由 `InteractOpts.ime` 决定（缺省跟随 `text_input`）：`text_input = true, ime = false` 的节点（密码框、只读文本框）仍接收 `char`、焦点环恒可见，但聚焦时框架调用 `setImeEnabled(false)`。

**REQ-INPUT-063**　组字与焦点/指针的交互：组字期间焦点即将离开该节点（鼠标点击别处、程序设置、节点失格；Tab 被 ① 拦截故不适用）时，框架**先**调用 03 的 `Window.commitComposition()` 提交当前组字串，将产生的 `ime_commit` 与随后的 `ime_end` 投递给原节点，**然后**才改变焦点；节点消失导致无法投递时丢弃该提交。组字期间指针事件照常路由（点击其他位置即触发上述提交）。取消组字（`ime_end` 之前没有 `ime_commit`）后恢复到组字前的内容由控件负责。

**REQ-INPUT-064**　**关闭原因映射**：框架层 `input.DismissReason` = `{ outside_click, escape, host_deactivated, host_moved, host_resized, host_hidden, host_destroyed, cancel_mode, capture_lost, dpi_changed, dialog_opened, programmatic }`。03 的 `platform.DismissReason`（`outside_click`、`deactivated`、`host_moved`、`host_resized`、`host_hidden`、`cancel_mode`、`capture_lost`、`dpi_changed`）经 `popup_dismiss` 事件到达时，**必须**按下表转换后投递给各弹出层的 `owner`；框架自身产生的原因不经平台层：

| `platform.DismissReason` | `input.DismissReason` | 说明 |
|---|---|---|
| `outside_click` | `outside_click` | |
| `deactivated` | `host_deactivated` | |
| `host_moved` | `host_moved` | 宿主被移动或开始移动 |
| `host_resized` | `host_resized` | 宿主客户区尺寸变化 |
| `host_hidden` | `host_hidden` | 最小化或隐藏 |
| `cancel_mode` | `cancel_mode` | |
| `capture_lost` | `capture_lost` | |
| `dpi_changed` | `dpi_changed` | |
| （框架产生） | `escape`、`host_destroyed`、`dialog_opened`、`programmatic` | `escape` 见 REQ-INPUT-027，`dialog_opened` 见 REQ-INPUT-054 |

## 4. 接口草案

```zig
// 草案：仅签名
// input 模块位于 ui 之前，本节类型不引用 ui 的任何类型（Node、PaintCtx、PaintFn、RootId 等）。
// 平台输入类型直接引用 03：platform.Event、platform.Mods（含 altgr）、platform.VirtualKey、
// platform.MouseButton、platform.CursorShape、platform.ImeSegment、platform.DataObject。
pub const Chord = struct { key: platform.VirtualKey, mods: platform.Mods = .{} };

pub const CommandId = enum(u32) { _ };                  // 运行时命令句柄；命令系统见 11
pub const EditCommand = enum { undo, redo, cut, copy, paste, delete, select_all };   // 标准编辑命令的路由载荷

pub const ImeCaret = struct { caret: Rect, exclude: ?Rect = null };   // 相对节点的 lpx 矩形

pub const FocusReason = enum { pointer, tab, group, mnemonic, programmatic, restore, transfer, initial };
pub const ActivateSource = enum { default_button, cancel_button, mnemonic };
pub const DismissReason = enum {
    outside_click, escape, host_deactivated, host_moved, host_resized, host_hidden,
    host_destroyed, cancel_mode, capture_lost, dpi_changed, dialog_opened, programmatic,
};
pub const DismissInfo = struct { popup: WidgetId, reason: DismissReason };
pub const ContextRequest = struct { pos: Vec2, anchor: Rect, from_keyboard: bool };

pub const KeyGroups = packed struct {
    printable: bool = false, arrows: bool = false, home_end: bool = false, page: bool = false,
    enter: bool = false, space: bool = false, escape: bool = false, tab: bool = false,
    backspace_delete: bool = false, edit_chords: bool = false,   // Ctrl+A/C/V/X/Z/Y、Ctrl+Insert、Shift+Insert、Shift+Delete
    function_keys: bool = false,
};
pub const KeyMask = struct { groups: KeyGroups = .{}, extra: []const Chord = &.{} };

pub const Sense = packed struct { hover: bool = true, click: bool = false, drag: bool = false, wheel: bool = false, context: bool = false };
pub const WheelCaps = packed struct { up: bool = false, down: bool = false, left: bool = false, right: bool = false, zoom: bool = false };
pub const EditCaps = packed struct { undo: bool = false, redo: bool = false, cut: bool = false, copy: bool = false, paste: bool = false, delete: bool = false, select_all: bool = false };

pub const InteractOpts = struct {
    sense: Sense = .{},
    cursor: platform.CursorShape = .arrow,
    take_focus_on_click: bool = true,
    text_input: bool = false,
    ime: ?bool = null,              // 是否启用输入法；null 表示跟随 text_input。密码与只读文本框置 false
    capture_on_press: bool = true,  // 假时按下不建立隐式捕获（REQ-INPUT-013）
    preempt: KeyMask = .{},
    handles: KeyMask = .{},
    observes: KeyMask = .{},        // 观察：收到事件但不消费，路由继续（REQ-INPUT-028）
    wheel_caps: WheelCaps = .{},
    edit: EditCaps = .{},
    reveal_target: bool = false,
};

pub const Interaction = struct {
    // 持续性状态
    hovered: bool, hovered_within: bool,
    pressed: bool, captured: bool, dragging: bool,
    focused: bool, focus_visible: bool, disabled: bool,
    pointer: ?Vec2,               // 悬停或被捕获时，相对节点矩形左上角，lpx
    press_origin: ?Vec2,          // 持有捕获时的按下点，相对节点
    drag_delta: Vec2,             // dragging 时 = 指针 − 按下点；否则 0
    // 激活类结果（触发同帧第二构建遍，REQ-FRAME-030）
    clicked: bool, click_count: u8, click_button: platform.MouseButton,
    double_clicked: bool, triple_clicked: bool,
    right_clicked: bool, middle_clicked: bool,
    context_menu: ?ContextRequest,
    drag_started: bool, drag_ended: bool, drag_cancelled: bool,
    activated: ?ActivateSource,
    // 一次性通知（不触发第二遍）
    focus_gained: ?FocusReason, focus_lost: bool,
    wheel: Vec2,                  // 未被其他节点消费的累计格数
    popup_dismissed: ?DismissInfo,
};

// 各事件的 pos 均为相对目标节点布局矩形左上角的 lpx 坐标。
pub const NodeEvent = union(enum) {
    pointer_move: struct { pos: Vec2, mods: platform.Mods },
    press: struct { button: platform.MouseButton, pos: Vec2, mods: platform.Mods, clicks: u8 },
    release: struct { button: platform.MouseButton, pos: Vec2, mods: platform.Mods, inside: bool },
    click: struct { button: platform.MouseButton, pos: Vec2, mods: platform.Mods, count: u8 },
    drag_start: struct { pos: Vec2 }, drag_move: struct { pos: Vec2, delta: Vec2 },
    drag_end: struct { cancelled: bool },
    wheel: struct { delta: Vec2, page: bool, mods: platform.Mods, pos: Vec2 },
    key_down: struct { key: platform.VirtualKey, mods: platform.Mods, repeat: bool },
    key_up: struct { key: platform.VirtualKey, mods: platform.Mods },
    char: u21,
    ime_start,
    ime_update: struct { text: []const u8, cursor: usize, segments: []const platform.ImeSegment },
    ime_commit: []const u8,
    ime_end,
    focus_gained: FocusReason, focus_lost,
    context_menu: ContextRequest,
    reveal: Rect,
    activate: ActivateSource,
    activate_menu_bar,
    popup_dismissed: DismissInfo,
    edit_command: EditCommand,
    dropped: DropState,
};

pub const GroupOrientation = enum { horizontal, vertical, both };
pub const GroupSpec = struct { orientation: GroupOrientation, wrap: bool = true, home_end: bool = true, current: WidgetId = .none, tab_stop: bool = true };
pub const ScopeSpec = struct { default_button: WidgetId = .none, cancel_button: WidgetId = .none, initial_focus: WidgetId = .none, trap_tab: bool = false };   // 根范围恒为 true，忽略此字段

pub const MnemonicAction = enum { activate, focus, focus_next, focus_within }; // focus_within：聚焦 id 子树内按 Tab 序的第一个可聚焦节点
pub const Mnemonic = struct { text: []const u8, underline: ?struct { start: u32, len: u32 }, key: ?u21 };
pub fn parseMnemonic(arena: std.mem.Allocator, label: []const u8) Mnemonic;

pub const PopupKind = enum { menu, dropdown, context_menu, autocomplete, tooltip };
pub const KeyboardMode = enum { grab, passive };
pub const PopupSpec = struct {
    kind: PopupKind,
    anchor: Rect,                          // 宿主根坐标，lpx
    anchor_id: WidgetId = .none,           // REQ-INPUT-053
    placement: layout.Placement = .{},     // 07
    gap: theme.Gap = .none,
    match_anchor_width: bool = false,
    min_width: f32 = 0,                    // lpx
    max_height: ?f32 = null,               // lpx；null = 工作区高度
    light_dismiss: bool = true,
    close_on_escape: bool = true,
    close_on_host_change: bool = true,
    keyboard: KeyboardMode = .grab,
    owner: WidgetId = .none,               // none = 声明时 ID 栈顶节点
    parent_popup: WidgetId = .none,
    pub fn defaults(kind: PopupKind, anchor: Rect) PopupSpec;
};

pub const HoverDelay = enum { menu, tooltip };

pub const DragPayload = struct { kind: u32, data: u64 = 0, ptr: ?*const anyopaque = null, external: ?*platform.DataObject = null };   // DataObject 由 03 定义
pub const DragInfo = struct { source: WidgetId, payload: DragPayload, pos: Vec2, over: WidgetId };
pub const DropAccept = struct { kinds: []const u32 = &.{}, external_files: bool = false, external_text: bool = false };
pub const DropState = struct { over: bool, acceptable: bool, pos: Vec2, dropped: bool, payload: ?DragPayload, effect: platform.DropEffect };

pub const ShortcutHit = struct { command: CommandId, enabled: bool };
pub const ShortcutSource = struct {
    ctx: *anyopaque,
    lookup: *const fn (ctx: *anyopaque, chord: Chord) ?ShortcutHit,
    invoke: *const fn (ctx: *anyopaque, command: CommandId) void,
};

// NodeFlags 的 `tab_stop`、`hit_passthrough`、`hidden` 位已在 06 的草案中给出，语义由本文（前两者）与 07（hidden）规定。

// 下列函数挂在 ui 模块的 `Ui` 上，属于 ui 模块的公开接口，只是其语义由本文规定；
// 此处以 UiInput 命名空间集中列出，签名中的 `ui: *Ui` 即 06 的 `Ui`。
pub const UiInput = struct {
    // —— 交互 ——
    pub fn interact(ui: *Ui, id: WidgetId, opts: InteractOpts) Interaction;
    pub fn events(ui: *Ui, id: WidgetId) []const NodeEvent;      // 帧竞技场；第二遍为空

    // —— 焦点 ——
    pub fn focusedId(ui: *const Ui) WidgetId;
    pub fn setFocus(ui: *Ui, id: WidgetId) void;                  // 构建完成后生效
    pub fn setFocusReason(ui: *Ui, id: WidgetId, reason: FocusReason) void;
    pub fn clearFocus(ui: *Ui) void;
    pub fn autoFocus(ui: *Ui, id: WidgetId) void;
    pub fn focusGroup(ui: *Ui, id: WidgetId, spec: GroupSpec) void;
    pub fn focusScope(ui: *Ui, id: WidgetId, spec: ScopeSpec) void;
    pub fn rootScope(ui: *Ui, spec: ScopeSpec) void;
    pub fn isFocusVisible(ui: *const Ui) bool;

    // —— 捕获 ——
    pub fn capturePointer(ui: *Ui, id: WidgetId) void;
    pub fn releaseCapture(ui: *Ui) void;
    pub fn capturedId(ui: *const Ui) WidgetId;

    // —— 助记符 ——
    pub fn mnemonic(ui: *Ui, id: WidgetId, ch: u21, action: MnemonicAction) void;
    pub fn keyboardCuesVisible(ui: *const Ui) bool;

    // —— 延迟与提示 ——
    pub fn hoverFor(ui: *Ui, id: WidgetId, delay: HoverDelay) bool;
    pub fn notHoverFor(ui: *Ui, id: WidgetId, delay: HoverDelay) bool;
    pub fn tooltip(ui: *Ui, owner: WidgetId, text: []const u8) void;   // 框架复制 text
    pub fn tooltipIfTruncated(ui: *Ui, owner: WidgetId, text: []const u8, style: text.Style) void; // 同 tooltip，但在将要显示的时刻以 owner 的当前内容宽度调用 text.isTruncated 判定，未截断则不显示

    // —— 拖放与覆盖层 ——
    pub fn beginDrag(ui: *Ui, source: WidgetId, payload: DragPayload) void;
    pub fn dragInfo(ui: *const Ui) ?DragInfo;
    pub fn dropTarget(ui: *Ui, id: WidgetId, accept: DropAccept) DropState;
    pub fn overlay(ui: *Ui, id: WidgetId, spec: OverlaySpec) void;   // OverlaySpec 定义于 06

    // —— 输入法 ——
    pub fn imeCaret(ui: *Ui, id: WidgetId, caret: Rect, exclude: ?Rect) void;   // REQ-INPUT-062

    // —— 快捷键源（由 Window 在创建时设置，11）——
    pub fn setShortcutSource(ui: *Ui, src: ?ShortcutSource) void;
};
```

## 5. 边界与错误情况

| 情况 | 规定 |
|---|---|
| 首帧、尚无保留树 | 命中表为空，所有指针事件无目标；键盘事件仍按 ①–⑧ 路由（无焦点节点时 ③⑤ 空过） |
| 指针事件到达时目标节点已在上一次构建中消失 | 事件基于命中表的旧节点；若该 ID 不在新树，收件列表丢弃，不重投 |
| 同一帧内同一节点既点击又被禁用 | 按构建时的禁用状态：点击事件已在分发时排入，本次构建中该控件为禁用则 `Interaction` 全为假 |
| 按下后窗口尺寸变化使节点移位 | 捕获保持；点击判定用释放时的保留树矩形 |
| 滚轮事件到达时无可滚动目标 | 丢弃，不置脏，不产生帧 |
| 多个节点同时声明预占同一键 | 只有焦点节点的预占有效 |
| 助记符字符为空格或控制字符 | 忽略，视为无助记符 |
| `autoFocus` 的目标首次出现时被禁用 | 请求丢弃，调试构建 `warn` |
| 焦点节点所在的弹出根被关闭 | 弹出焦点丢弃；宿主焦点不变（REQ-INPUT-036） |
| 对话框与宿主同时存在 | 各自独立的 `Ui` 与焦点；宿主被禁用时（11）不收任何输入事件 |
| 拖放中窗口失去激活 | 视同 `capture_lost`（03 的 `capture_lost` 事件），拖放取消 |
| 拖放源节点在拖放中消失 | 拖放取消，不触发 `dropped` |
| 外部（OLE）拖入时没有任何目标可接受 | 回报 `DropEffect.none`，指针显示不可放置 |
| 快捷键命中后命令处理函数内再次触发失效 | 合并（REQ-FRAME-038），不嵌套 |
| 极快的连续点击导致计数跳过 | 以时间戳判定，不依赖帧数 |
| `ime_commit`/`ime_end` 到达时焦点节点已不是文本输入类 | 丢弃并在调试构建报告 |
| 平台层不支持弹出窗口外的点击通知（降级后端） | 03 降级矩阵规定；轻关闭仅能响应宿主窗口内的点击 |

## 6. 验收标准

除特别注明外，以下测试以无头方式运行，使用可注入的假时钟、假系统度量（双击时间 500 ms、双击矩形 4×4、拖拽矩形 4×4、菜单延迟 400 ms、悬停时间 400 ms、悬停矩形 4×4）与输入回放。

**AC-INPUT-001**　`[单元]` 覆盖：REQ-INPUT-001、REQ-INPUT-003、REQ-INPUT-004。前置：构建一个含按钮的界面，构建函数内置调用计数。步骤：回放一次按钮上的按下与释放，阶段桩记录分发阶段的行为。预期：分发阶段内构建函数调用计数不变；分发后按钮的收件列表含 `press`、`release`、`click` 三个事件，顺序固定；对未调用 `interact` 的节点调用 `ui.events` 在调试构建断言中止；同一节点同帧第二次 `interact` 传入不同 `opts` 时，返回值与第一次相同。

**AC-INPUT-002**　`[回放]` 覆盖：REQ-INPUT-005、REQ-INPUT-006。前置：一个界面含按钮 B 与焦点文本框。步骤与预期：① 点击 B：该帧构建遍数 = 2；第一遍 `clicked` = 真、第二遍 = 假；`hovered` 两遍均为真。② 在一轮消息内注入 20 个无捕获的悬停移动（悬停目标不变）：B 的收件列表无 `pointer_move`，帧数 = 0；注入 20 个有捕获的移动：收到 20 个，顺序不变；注入 3 个同向滚轮事件（0.5 格、0.5 格、1 格）：收到 1 个累计 2.0 格的 `wheel`。③ Tab 使焦点移动：该帧构建遍数 = 1（`focus_gained` 事件进入收件列表引起构建），而不是 2（一次性通知不触发第二遍）。

**AC-INPUT-003**　`[回放]` 覆盖：REQ-INPUT-007、REQ-INPUT-008。前置：Stack 内先后声明 A (0,0,100,100)、B (50,50,100,100)，均登记 `click`。步骤与预期：点 (75,75) → 目标 B；点 (25,25) → A；点 (125,125) → B；给 B 置 `hit_passthrough` 后点 (75,75) → A；给 B 置 `hidden` 后点 (125,125) → 无命中；A 置 `hidden` 且 A 含子节点 C → 点 C 的位置无命中（`hidden` 作用于子树）；C 置 `hit_passthrough`、其父 A 不置：点 C 的位置命中 A（该标志不作用于后代，但作用于 C 本身）。一个 Scroll 视口 (0,0,100,50) 内的子节点 D 矩形 (0,0,100,200)：点 (10,80)（视口之外）无命中，点 (10,30) 命中 D。覆盖层中画一个矩形并点其上：命中的是其下的内容层节点。

**AC-INPUT-004**　`[回放]` 覆盖：REQ-INPUT-009、REQ-INPUT-049。前置：节点 A (0,0,100,100) 启用，其上方后声明的同位置节点 D 禁用，均登记 `click`；A 先于 D。步骤：在 D 上按下并释放。预期：目标为 D（`D.hovered` = 真）；A 与 D 的 `clicked`、`pressed`、`captured` 全为假，焦点不变；D 的 `ui.events` 为空；其后代的 `Interaction.disabled` = 真。滚轮：D 位于启用的 Scroll S 内，在 D 上滚动一格 → S 的偏移变化（滚轮可经禁用节点冒泡到启用的祖先）；S 本身禁用时在其上滚动无效果。

**AC-INPUT-005**　`[回放]` 覆盖：REQ-INPUT-010、REQ-INPUT-052。前置：宿主窗口含按钮 H (0,0,100,30)；一个菜单弹出窗口覆盖屏幕矩形 (0,10,100,100)，其内菜单项 N 覆盖屏幕矩形 (0,40,100,22)；一个提示框弹出窗口覆盖屏幕矩形 (0,45,50,20)（位于菜单窗口之上）。步骤与预期：指针在 (80,15)（菜单窗口内的空白处，与 H 重叠）→ 命中只在菜单根上做，无命中，H 的 `hovered` = 假；指针在 (10,50)（同时在提示框与菜单项 N 范围内）→ 命中 N（等同提示框不存在）；指针在 (150,15)（所有弹出窗口之外）→ 命中测试宿主根；弹出栈清空后，(80,15) 命中 H。

**AC-INPUT-006**　`[回放]` 覆盖：REQ-INPUT-011、REQ-INPUT-012。前置：两个相邻按钮 P (0,0,100,30)、Q (0,40,100,30)，指针静止于 (50,15)（悬停 P）。步骤：令一次构建使 P 与 Q 的位置交换而指针不动。预期：布局后同一帧内回投命中使悬停从 P 变到 Q；该帧损伤 ⊇ P、Q 的新旧矩形；帧统计构建遍数 = 1（由模型变化引起）；不产生额外的下一帧。另：指针从宿主按钮移入菜单窗口：整个过渡只产生 1 次分发后的结算，`P.hovered` 变假与菜单项 `hovered` 变真出现在同一帧。

**AC-INPUT-007**　`[回放]` 覆盖：REQ-INPUT-013、REQ-INPUT-014、REQ-INPUT-015。前置：按钮 K (100,100,80,24) 登记 `click`。步骤与预期：① 在 K 内按下 → `captured` = 真、`pressed` = 真。② 指针移到 (400,400) → 捕获者仍收到移动事件（带该坐标），`pressed` = 假，K 之外的任何节点 `hovered` = 假；移回 K 内 → `pressed` = 真。③ 在 K 内释放 → `clicked` = 真，`click_count` = 1，`click_button` = left。④ 重做但在 (400,400) 释放 → `clicked` = 假，捕获释放，随后回投命中使悬停更新。⑤ 左键按下期间再按右键，先释放左键 → 捕获保持，`clicked` 按左键判定为真；全部按键释放后捕获释放。⑥ 在 K 上按下后将 K 的位置挪走（指针不动、释放时已在 K 之外）→ 无点击。⑦ 在 A 上按下，在 B 内释放 → A、B 均无点击。

**AC-INPUT-008**　`[回放]` 覆盖：REQ-INPUT-016。前置：节点 L 登记 `click`，系统双击 500 ms、矩形 4×4。步骤（每步为一次"按下+释放"，时间戳 t，位置 p）：t=0 p=(10,10) → `click_count` = 1；t=300 p=(11,10) → 2 且 `double_clicked` = 真；t=600 p=(11,11) → 3 且 `triple_clicked` = 真；t=800 p=(11,11) → 1（第 4 次重置）；t=1400（间隔 600）→ 1；t=1600 p=(10,10)、t=1700 p=(13,10)（偏移 3 > 2）→ 第二次为 1；t=2000、t=2200 在相邻的另一个节点上 → 为 1。按下事件的 `clicks` 字段与对应点击的 `click_count` 一致。把假系统双击时间改为 200 ms，t=0、t=300 → 第二次为 1（证明读取系统度量）。

**AC-INPUT-009**　`[回放]` 覆盖：REQ-INPUT-017。前置：节点 M 登记 `click` 与 `drag`，拖拽矩形 4×4（半宽 2）。步骤与预期：按下 (50,50)，移到 (52,50)：`drag_started` = 假；移到 (53,50)：`drag_started` = 真（激活类，该帧构建遍数 = 2）、`dragging` = 真、`drag_delta` = (3,0)；移到 (60,70) → `drag_delta` = (10,20)；释放 → `drag_ended` = 真，`dragging` = 假，且**没有** `clicked`。另一个只登记 `click` 的节点 N：按下后拖出 100 px 再拖回其内释放 → `clicked` = 真。把假拖拽矩形改为 16×16 后 (53,50) 不触发（读取系统度量）。

**AC-INPUT-010**　`[回放]` 覆盖：REQ-INPUT-018。前置：节点 R 登记 `context`，焦点在节点 F（矩形 (20,200,100,24)，登记 `context`）。步骤与预期：鼠标右键在 R 上按下：`right_clicked` 尚为假、`context_menu` 为空；释放：二者同帧产生，`context_menu.pos` 为指针位置、`from_keyboard` = 假。`Shift+F10`：F 的 `context_menu` = `{ pos=(20,224), anchor=F 矩形, from_keyboard=真 }`；菜单键同；F 为文本输入类并预占了全部编辑键时上述两键仍然生效；F 未登记 `context` 而其祖先登记了 → 祖先收到。右键在无 `context` 登记的链上释放 → 仅 `right_clicked`。

**AC-INPUT-011**　`[回放]` 覆盖：REQ-INPUT-019、REQ-INPUT-020。前置：外层 Scroll O 内含内层 Scroll I，I 内容可纵向滚动；O 也可纵向滚动；二者按 `ScrollMetrics` 声明 `WheelCaps`。步骤与预期：指针在 I 内，I 偏移位于中间：向上滚一格 → I 收到、O 不收；I 偏移为 0（`up` 为假）再向上滚 → O 收到；I 偏移位于末端（`down` 为假）向下滚 → O 收到；键盘焦点在页面另一个文本框时结果相同（与焦点无关）；Shift+向下滚一格 → 作为向右滚动解析，I 无横向则 O 的横向 `right` 为真时 O 收到，否则丢弃；Ctrl+滚轮 → 仅 `zoom` 为真的节点收到，否则丢弃；`page = true` 的事件携带该标志；`raw` = 30 的事件四次累加为 1.0 格（30/120 = 0.25）。弹出根上的滚轮：菜单窗口内滚动不会令宿主 O 滚动。

**AC-INPUT-012**　`[回放]` 覆盖：REQ-INPUT-021。前置：文本框 T（`ibeam`）、链接 L（`hand`）、分隔条 S（`size_we`）、禁用的 T2。步骤与预期：指针依次移入 T、L、S、T2、空白，平台层（假）记录的设置光标序列为 `ibeam`、`hand`、`size_we`、`arrow`、`arrow`；在 S 上按下并拖到 S 之外时形状保持 `size_we`（捕获者声明）；这些变化不产生任何帧（帧计数不变）。

**AC-INPUT-013**　`[回放]` 覆盖：REQ-INPUT-022、REQ-INPUT-023。前置：可聚焦按钮 B1、不取焦点的工具栏按钮 TB（`take_focus_on_click = false`）、不可聚焦标签 X、禁用的可聚焦按钮 B2；焦点在文本框 T。步骤与预期：按下 B1 → 焦点移到 B1（按下时，尚未释放，原因 `pointer`）；按下 TB → 焦点不变；按下 X 或空白 → 焦点不变（不清除）；按下 B2 → 焦点不变；触摸与笔：假平台层以系统提升后的 `mouse_move` + 左键 `mouse_button` 按下/释放模拟一次轻点 B1 → `click` 产生，行为与左键相同（无触摸专属分支）；轻点后平台层若产出 `mouse_leave`，`hovered` = 假。

**AC-INPUT-014**　`[回放]` 覆盖：REQ-INPUT-024。前置：节点 A 登记 `click`、`drag`。分别在下列时刻触发并断言：在按下后使 A 从树中消失 → 捕获立即释放，无 `clicked`；按下后令 A 变为禁用 → 同；按下后窗口失去激活 → 同，且激活后悬停重新结算；拖拽进行中平台报告 `capture_lost` → `drag_cancelled` = 真、`drag_ended` = 假；以上各情形都没有 `clicked`。`ui.capturePointer(id)` 于按下后的构建中调用 → `capturedId()` = id；`releaseCapture()` 后 = none。

**AC-INPUT-015**　`[回放]` 覆盖：REQ-INPUT-025、REQ-INPUT-026、REQ-INPUT-027、REQ-INPUT-028。前置：同一界面含：文本框 T（预占字符与方向键与 `edit_chords`）、一个绑定 `Ctrl+S` 的命令、一个打开的菜单弹出层（`grab`）、组字状态可注入。逐项回放并断言键的最终接收者：① 无弹出、T 聚焦、按 `a` → T 收到 `key_down(a)` 与 `char('a')`；② 同上，按 `Ctrl+S` → T 未预占，命令处理函数被调用 1 次，T 收不到；③ 菜单打开，按 `Ctrl+S` → 菜单根收到，命令未调用；④ 菜单打开，按 `Esc` 且菜单内无节点声明 Esc → 菜单收到 `popup_dismissed(escape)`，宿主 T 未收到任何键；⑤ 组字进行中按 `Ctrl+S` 与 `Tab` 与 `Enter` → 只有 T 收到，命令未调用、焦点未移动、默认按钮未触发；⑥ T 预占 `Ctrl+Z`：按下后只有 T 收到，即使存在绑定 `Ctrl+Z` 的命令也未调用。被丢弃的键（无人消费）不产生任何可观察效果。

**AC-INPUT-016**　`[回放]` 覆盖：REQ-INPUT-029。前置：命令 C1（`Ctrl+Shift+S`，启用）、C2（`F5`，禁用）、焦点在不预占这些键的按钮上。步骤与预期：按 `Ctrl+Shift+S` → C1 处理函数调用 1 次，调用发生在该帧的分发阶段（早于构建），`build` 脏，按钮收不到该键；按 `Ctrl+S`（未绑定）→ 向后级传递；按 `F5` → 被吞掉，C2 未调用，按钮未收到；按住 `Ctrl+Shift+S` 产生自动重复 5 次 → C1 总共调用 1 次；`Mods.altgr` 为真的 `Ctrl+Alt+Q` 不匹配绑定了 `Ctrl+Alt+Q` 的命令；`Shift+Ctrl+S` 与 `Ctrl+S` 互不匹配（精确匹配）；Caps Lock 开启时 `Ctrl+S` 仍匹配。被 C1 消费的 `key_down` 之后的 `char` 不进入任何节点。

**AC-INPUT-017**　`[回放]` 覆盖：REQ-INPUT-030、REQ-INPUT-031、REQ-INPUT-032。前置：焦点在列表 LI（`handles` 方向键与 Home/End），其祖先面板 PA `handles` 的 `Esc`，父级再上有无声明节点。步骤与预期：按 ↓ → LI 收到；按 `Esc` → PA 收到（LI 未声明）；按 `F9`（无人声明）→ 丢弃；`Ctrl+A` 在 LI 上产生的 `char(U+0001)` 被丢弃；LI 未预占 printable 时按 `x` → `char` 被丢弃；焦点节点在 `key_down` 与 `key_up` 之间消失 → `key_up` 被丢弃，不报错；`key_down(x)` 无人接收则其 `key_up` 被丢弃；自动重复的 ↓ 带 `repeat = true` 并投递给 LI 5 次。

**AC-INPUT-018**　`[回放]` 覆盖：REQ-INPUT-033、REQ-INPUT-034、REQ-INPUT-035。前置：对话框根含：文本框 T（单行，预占字符/方向键/编辑键，未预占 Enter/Esc）、多行文本框 M（另预占 Enter）、按钮 OK（默认）、Cancel（取消）、普通按钮 X（`handles` Enter/Space）、复选框带助记符 `&Mail`。步骤与预期：焦点 T，按 Enter → OK 收到 `activate(default_button)`，`OK.Interaction.activated` = 真（该帧构建遍数 = 2）；焦点 M，按 Enter → M 收到（预占），OK 未被激活；焦点 X，按 Enter → X 收到，OK 不激活；焦点 T，按 Esc → Cancel 收到 `activate(cancel_button)`；根范围未配置默认按钮时 Enter 被丢弃；OK 被禁用时 Enter 被丢弃；Tab：先序位置 T→M→OK→Cancel→X→复选框 逐次移动，末尾回绕到 T；Shift+Tab 反向；焦点在 `tab_stop = false` 的节点 Z（先序位于 M 与 OK 之间）时按 Tab → 焦点到 OK；Alt+M → 复选框被聚焦并切换（`activate` 语义，`activated = mnemonic`）。

**AC-INPUT-019**　`[回放]` 覆盖：REQ-INPUT-036、REQ-INPUT-037、REQ-INPUT-039。前置：主窗口含 8 个按钮 B1..B8（先序）；B3 禁用，B4 `hidden`；`focusScope` 包住 B5、B6。步骤与预期：① 该范围 `trap_tab = false`：从 B1 连按 Tab 得 B2、B5、B6、B7、B8、B1（B3、B4 不可达，范围外回绕）。② 该范围 `trap_tab = true`：从 B2 按 Tab → B5（进入范围）；连按 Tab → B6、B5、B6……不逃逸；Shift+Tab 同样在范围内循环。③ 弹出根（含 3 个按钮）内连按 Tab 3 次回到原点，宿主焦点节点始终不变。④ 把 B7 的布局位置移到最上方，Tab 序不变（只取决于先序）。⑤ 一个滚出视口但未隐藏的按钮仍在 Tab 序内。

**AC-INPUT-020**　`[回放]` 覆盖：REQ-INPUT-038。前置：Tab 序中有按钮 A、单选组 G（3 个成员 G1..G3，G2 当前，`horizontal`，`wrap`）、按钮 Z。步骤与预期：从 A 按 Tab → G2（整组一个停靠）；再按 Tab → Z；Shift+Tab 回到 G2；在 G2 上按 → → G3（原因 `group`，`focus_gained = group`）；再按 → → G1（回绕）；← → G3；Home → G1，End → G3；跳过禁用的成员（禁用 G2 后在 G1 按 → 到 G3）；离开再回来时焦点落在最近获得焦点的成员（G3）；`wrap = false` 时 G3 上按 → 无效果；纵向组忽略 ←/→ 而使用 ↑/↓；成员自己 `handles` 了 → 时由成员处理，组不移动。

**AC-INPUT-021**　`[回放]` 覆盖：REQ-INPUT-040、REQ-INPUT-041。前置：按钮 B 与文本框 T。步骤与预期：初始 `focus_visible` = 假；鼠标点击 B → B.`focused` = 真、`focus_visible` = 假（不画环）；按 Tab（焦点到 T）→ `focus_visible` = 真，T 画环；按下任一单独修饰键（Shift）→ 置真；再点击 B → 置假，且 T.`Interaction.focus_visible` 随焦点移走；点击 T → T 的 `Interaction.focus_visible` = 真（文本输入类始终）；程序 `setFocus(B)` 不改变 `focus_visible`；窗口失去激活 → B.`focused` 保持真但 `Interaction.focus_visible` = 假，重新激活焦点仍在 B，`focus_visible` 保持原值，重新激活的原因为 `restore`；激活窗口的那次点击（点击一个按钮）正常投递（该按钮 `clicked` = 真）。焦点环显隐对焦点节点置 `paint`；焦点变化的帧另因收件事件构建 1 遍。

**AC-INPUT-022**　`[单元]` 覆盖：REQ-INPUT-042、REQ-INPUT-050。前置：Column 内按钮 B1..B5，焦点 B3。步骤与预期：下一次构建不声明 B3 → 焦点到 B4；不声明 B3、B4、B5 → B2；声明 B3 但置禁用 → B4；不声明 B2、B3 → B4；仅留 B1（其余全消失）→ B1；全部消失 → 焦点置空，之后按 Tab 得到范围内第一个停靠点（若有）；B3 所在的整个 Column 被不声明且 B3 之后无其他节点 → 取范围内先序最后一个存活停靠点；弹出根内的焦点节点随弹出根关闭 → 宿主焦点不变；每种情形原因均为 `transfer`，`focus_visible` 不变，转移发生在布局之前（阶段日志验证）。

**AC-INPUT-023**　`[单元]` 覆盖：REQ-INPUT-043、REQ-INPUT-044、REQ-INPUT-045。步骤与预期：构建中 `setFocus(X)`，X 在同一构建声明 → 构建完成后焦点为 X（原因 `programmatic`），X.`focus_gained = programmatic`、旧节点 `focus_lost` 在同一帧；X 不存在 → 丢弃并产生 1 条 `warn`；首次构建后无焦点且 `ScopeSpec.initial_focus = Y` → 焦点 Y（原因 `programmatic`，初始）；无 `initial_focus` → Tab 序第一个；`autoFocus(P)` 与 `autoFocus(Q)` 同一构建（P 先序在前）→ P 获得焦点，之后 P 重新出现不再抢焦点。滚动容器内：Tab 把焦点移到视口外的按钮 → 其 Scroll 祖先收到 `reveal`，布局后该按钮完全落入视口（`ScrollMetrics` 与按钮矩形断言）；鼠标点击获得焦点则不产生 `reveal`。

**AC-INPUT-024**　`[单元]` 覆盖：REQ-INPUT-046。`parseMnemonic`：`"&File"` → 文本 `File`、下划线 [0,1)、键 `f`；`"Save && Exit"` → `Save & Exit`、无下划线；`"A&&&B"` → `A&B`、下划线 [2,3)、键 `b`；`"Trailing&"` → `Trailing`、无；`"&a&b"` → `ab`、下划线 [0,1)、键 `a`；`"文件(&F)"` → `文件(F)`、下划线 [7,8)、键 `f`；`"&"` → 空串、无；`"&Ä"` → 键 `ä`；`"x&é"` 的 `é` 与 `É` 比较相等。

**AC-INPUT-025**　`[回放]` 覆盖：REQ-INPUT-047、REQ-INPUT-048。前置：按钮 `&Save`、`&Send`、`&Search`（先序）与复选框 `&Mail`，假系统 `SPI_GETKEYBOARDCUES` = 假。步骤与预期：初始 `keyboardCuesVisible` = 假；按下 Alt → 真（整窗 `paint`）；窗口失去激活 → 假；系统设置为真时始终为真。Alt+M → 唯一匹配，复选框被聚焦并切换；Alt+S（焦点在别处）→ 焦点到 Save，**无**激活；再次 Alt+S → Send；再 → Search；再 → Save（回绕）；焦点在 Send 时 Alt+S → Search；任一冲突情形 `activated` 均为假；Alt+Z（无登记）→ 丢弃；按下 Alt 之后再按其他键的组合不改变 Alt 单键处理；弹出菜单打开时 Alt+S 只在菜单根内查找。

**AC-INPUT-026**　`[单元]` 覆盖：REQ-INPUT-049。禁用一个包含按钮与文本框的面板。预期：其内全部节点 `Interaction.disabled` = 真；`focus_*` 为假；`ui.events` 为空；Tab 序中不含它们；Alt+助记符不激活它们；默认按钮禁用时 Enter 丢弃；悬停时 `hovered` = 真（可显示提示框），指针形状 `arrow`；点击它们不改变焦点。

**AC-INPUT-027**　`[回放]` 覆盖：REQ-INPUT-051、REQ-INPUT-052、REQ-INPUT-053、REQ-INPUT-058。前置：宿主按钮 H1（打开菜单 M，`anchor_id = H1`）、宿主按钮 H2、菜单 M 含项 M1（有子菜单 S）。步骤与预期：打开 M 与 S（栈长 2，S 在上）；① 在 S 内点击 → 栈不变，无 `popup_dismissed`；在 M 的窗口内点击 → 不是外部点击；② 点击 H2（宿主窗口内、弹出窗口外，以带 `via_popup_capture = true` 的 `mouse_button` 到达）：M 与 S 的 owner 先后收到 `popup_dismissed(outside_click)`（S 先），**同一帧**内 H2 收到按下，释放后 `clicked` = 真；owner 在该帧构建把展开状态置假 → 栈清空；③ 重新打开，点击 H1（锚点）→ M、S 的 owner 收到 `popup_dismissed`，H1 **未**收到按下/释放/点击，`H1.hovered` 仍为真，且菜单没有被重新打开（H1 的状态机在该帧未收到 `clicked`）；④ 假平台层注入 `popup_dismiss{outside_click}`（模拟点击其他应用窗口）→ M、S 的 owner 同样收到 `popup_dismissed(outside_click)`，**无**任何继续投递（宿主无任何节点收到按下）；⑤ 菜单项 M1 的 owner 忽略通知并继续声明 → 弹出层保持；⑥ 提示框弹出层不在栈中（栈长不计）。 另：打开 M 后，在本进程的另一个应用窗口 W2 内点击（以 `via_popup_capture` 事件、屏幕坐标位于 W2 内注入）→ M 的 owner 收到 `popup_dismissed(outside_click)`；宿主根与 W2 的任何节点都未收到该次按下/释放，`clicked` 计数不变。

**AC-INPUT-028**　`[回放]` 覆盖：REQ-INPUT-054、REQ-INPUT-055、REQ-INPUT-036。前置：打开菜单 M 与子菜单 S，宿主焦点在文本框 T。步骤与预期：Esc（菜单内未声明）→ S 的 owner 收到 `popup_dismissed(escape)`，M 的 owner 未收到；再 Esc → M 的 owner 收到；宿主失去激活 → 全部弹出层 owner 收到 `host_deactivated`；宿主窗口被移动 → `host_moved`；被缩放 → `host_resized`；`close_on_host_change = false` 的弹出层在移动时不收到。打开期间宿主窗口去激活事件计数 = 0，宿主 `window_active` 保持真，T.`focused` 保持真；弹出栈清空后键盘回到 T（按 `a` 的 `char` 由 T 收到）。`keyboard = passive` 的自动完成列表打开时，T 仍收到字符与方向键。

**AC-INPUT-029**　`[单元]` 覆盖：REQ-INPUT-056。假时钟：菜单延迟 400 ms。步骤与预期：指针进入菜单项 I 后，t=399 `hoverFor(I, menu)` = 假、t=400 = 真；t=399 离开再 t=450 回来则重新计时；`hoverFor` 未达到时已登记一个 `build` 级定时器，到期时刻（t=400）唤醒一帧，无轮询（0–400 ms 期间帧数 = 0，除指针移动本身）。子菜单：悬停 I 400 ms 后展开；移到同菜单另一项 J，S 在 400 ms 后收起，若 399 ms 时指针进入 S 则不收起；键盘 → 立即展开、← 立即收起。将假菜单延迟改为 100 ms 后上述阈值变为 100（读取系统度量）。

**AC-INPUT-030**　`[回放]` 覆盖：REQ-INPUT-057、REQ-INPUT-010。前置：带提示的按钮 TP1、TP2，悬停时间 400 ms，悬停矩形 4×4（半宽 2）。步骤与预期：指针静止在 TP1：t=399 无提示框，t=400 出现；指针移动 1 px（仍在矩形内）→ 提示框保持，移动 3 px（离开矩形）→ 消失；出现后按任一键 / 滚轮 / 按下 → 消失；静止 4000 ms 自动消失；窗口失去激活 → 消失；出现提示框后立即移入 TP2 → 延迟变为 80 ms；有菜单打开 / 有按键按住 / 有捕获 / 窗口非激活 → 不出现；提示框出现时在提示框所覆盖的位置点击 → 命中并点击其下的宿主节点；提示框不取得激活、不进入弹出栈、不改变键盘路由。禁用的按钮 TP3（悬停时 `hovered` = 真）仍出现提示框。

**AC-INPUT-031**　`[回放]` 覆盖：REQ-INPUT-059、REQ-INPUT-060。前置：列表含 5 行（拖拽源 `kind = 7`），每行也是放置目标（接受 `kind` 7），覆盖层插入线。步骤与预期：在第 2 行按下并拖出 3 px → `drag_started` = 真；控件调用 `beginDrag` 后 `dragInfo().source` = 第 2 行；指针移到第 5 行 → 其 `DropState.over` = 真、`acceptable` = 真，覆盖层出现插入线（金图含该线；命中测试在该线上命中的仍是内容层节点）；释放 → 第 5 行 `dropped` = 真（该帧构建遍数 = 2），源 `drag_ended` = 真，`dragInfo()` 为空，覆盖层插入线随下一次构建消失。变体：拖动中按 Esc → 源 `drag_cancelled`、目标无 `dropped`、插入线消失；放置目标为 `kind = 9` 的区域上 `acceptable` = 假，释放无 `dropped`；拖动中源节点消失 → 取消；拖动中窗口失去激活 → 取消。

**AC-INPUT-032**　`[单元]` 覆盖：REQ-INPUT-061。使用假平台层。步骤与预期：载荷带 `external` 且指针离开窗口 → 帧后动作被登记并调用 `platform.startDrag` 恰好 1 次，调用发生在提交之后（阶段日志），返回后源收到 `drag_ended`（效果 move）或 `drag_cancelled`（效果 none）；构建函数内直接调用 `startDrag` 在调试构建断言中止。外部拖入：注入 `drag_enter(files)` → 声明 `external_files` 的目标 `over` = 真、其余不是；`drag_over` 位置变化更新 `pos`；目标可接受时假平台层收到 `setDropEffect(copy)`，无目标接受 → 收到 `setDropEffect(none)`；`drop` → 目标 `dropped` = 真；外部拖入全程不产生 `drag_started`。

**AC-INPUT-033**　`[回放]` 覆盖：REQ-INPUT-062、REQ-INPUT-063、REQ-INPUT-026。前置：文本框 T（`text_input`）与普通按钮 B，假平台层记录 `setImeEnabled`、`setImeCaretRect`、`commitComposition` 调用。步骤与预期：T 获得焦点 → `setImeEnabled(true)` 1 次，失去 → `setImeEnabled(false)` 1 次，B 获得焦点时输入法为禁用；注入 `ime_start`、`ime_update("ni", cursor 2)`、`ime_update("你", cursor 3)`、`ime_commit("你")`、`ime_end` → T 的收件列表按此顺序收到 5 个事件，B 收不到；`ime_commit` 之后、`ime_end` 之前，按 `Ctrl+S` 仍只投递给 T（组字状态到 `ime_end` 才结束）；T 调用 `imeCaret(T, caret=rect(10,0,1,18), exclude=rect(10,0,30,18))`，T 位于窗口 (100,50) → 假平台层收到的客户区 ppx 光标矩形为 (110,50,1,18)、排除矩形 (110,50,30,18)（`scale` 1.0），`scale` 1.5 时光标矩形 (165,75,2,27)（按取整规则）；`exclude` 传 `null` 时平台层收到的排除矩形为空；组字中点击 B → 框架先调用 `commitComposition()`（调用计数 1），T 先收到 `ime_commit` 与 `ime_end` 再失去焦点（事件顺序断言）；组字中 T 被禁用 → 同样先提交后失去焦点；组字中 `Ctrl+S`、Tab、Enter、Esc 不触发命令/导航/默认/取消。

**AC-INPUT-034**　`[单元]` 覆盖：REQ-INPUT-002、REQ-INPUT-020、REQ-INPUT-023。向分发注入 03 的 `platform.Event` 各变体，并检查换算：`scale` 1.5 时客户区 ppx (150,90) 得根局部 (100,60) lpx 且保留屏幕坐标；`key{down=false}` 成为 `key_down`/`key_up` 之一，`repeat` 透传；`text` 事件 "é" 得 1 个 `char(U+00E9)`；`wheel` 的 `raw` = 240 → 2.0 格，`raw` = 30 连续四次 → 累计 1.0 格（不使用 `steps`）；`SystemMetrics.wheel_lines` 为 `page` 时事件 `page = true`，为 `lines(3)` 时 `page = false`；`mods` 的 `altgr` 透传；触摸/笔以系统提升的鼠标消息到达，产生与鼠标相同的点击结果；搜索公开 API，不存在多点触控、手势、惯性滚动相关的事件类型。

**AC-INPUT-035**　`[人工]` 覆盖：REQ-INPUT-016、REQ-INPUT-017、REQ-INPUT-020、REQ-INPUT-055、REQ-INPUT-056、REQ-INPUT-057。在真实 Windows 上把控制面板的双击速度、鼠标悬停时间、菜单延迟、滚轮行数改为非默认值后（部分需注销生效，注销后复测），逐项操作：快速双击一个列表项；悬停提示框；展开子菜单；滚动长列表。观察要点：双击判定与系统设置一致；提示框出现延迟与设置一致；子菜单展开延迟与设置一致；滚轮每格滚动行数与设置一致；打开菜单时宿主窗口标题栏保持激活外观（不变灰）。

**AC-INPUT-036**　`[回放]` 覆盖：REQ-INPUT-025、REQ-INPUT-029、REQ-INPUT-034。八级优先级汇总：构造焦点节点 T（单行文本，预占字符与 `Ctrl+Z`）、绑定 `Enter` 的命令 CE、默认按钮 OK。按 Enter：快捷键表命中 CE（④ 先于 ⑦）→ CE 处理函数调用，OK 未被激活；将 CE 置禁用 → Enter 被吞掉，OK 仍未激活；去掉 CE 的绑定 → OK 被激活。证明级序 ④ 先于 ⑤、⑦；再验证 ⑥ 先于 ⑦（Alt+字符与默认按钮不冲突）与 ⑧ 最后（Tab 在 ⑤ 的 `handles Tab` 声明存在时由该节点处理而不移动焦点）。

**AC-INPUT-037**　`[回放]` 覆盖：REQ-INPUT-054、REQ-INPUT-064。前置：宿主窗口 W 打开菜单 M，其 owner 为 H1；另有 `close_on_host_change = false` 的弹出层 X。步骤与预期：假平台层依次注入 `popup_dismiss` 并断言 H1 收到的 `DismissInfo.reason`：`outside_click` → `outside_click`；`deactivated` → `host_deactivated`；`host_moved` → `host_moved`；`host_resized` → `host_resized`；`host_hidden` → `host_hidden`；`cancel_mode` → `cancel_mode`；`capture_lost` → `capture_lost`；`dpi_changed` → `dpi_changed`；每次都是全部弹出层的 owner 收到（X 除外的情形见下）。Esc → `escape`（只最上层）；销毁宿主 → `host_destroyed`（X 也收到）；宿主调用 `app.openDialog` → 全部弹出层 owner 收到 `dialog_opened`，X 同样收到；X 在 `host_moved`、`host_deactivated` 时不收到。映射表之外的 03 原因（若 03 新增）在调试构建断言。

## 7. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-INPUT-01 | （已解决）弹出窗口之外的点击通知方式 | 见 03 的 REQ-PLAT-069：宿主持有鼠标捕获 |
| OPEN-INPUT-02 | 是否提供类型预输入（type-ahead）的通用实现（列表/树/菜单按字符跳转） | 先由控件规范各自实现，若出现三处以上重复再提取为框架设施 |
| OPEN-INPUT-03 | RTL 语言下方向键组导航是否镜像 | 当前不做（REQ-VIS-008 排除 RTL 界面镜像） |
| OPEN-INPUT-04 | 一次性通知类字段（`focus_gained` 等）是否应归入激活类以便应用在同帧响应 | 当前不归入，避免焦点移动引发第二遍构建；有实际需求时再议 |
| OPEN-INPUT-05 | 拖放期间向 Scroll 容器边缘自动滚动的节奏与速度 | 由 Scroll 控件规范定义，读取系统度量（`SPI_GETWHEELSCROLLLINES` 之外无现成值，需定常量并写入 09） |
| OPEN-INPUT-06 | 提示框"再次显示"延迟取 1/5、自动消失取 10 倍的来源是 Windows 工具提示默认比例的经验值 | 在真实 Windows 上对照原生行为复核（AC-INPUT-035 的观察项扩展） |
