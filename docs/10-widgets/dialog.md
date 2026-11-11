# 对话框（dialog）

> 对话框**窗口本身**由 11 的 `app.openDialog` 创建（系统标题栏、宿主被禁用、非阻塞、独立的 `Ui` 与焦点，REQ-APP-016 至 REQ-APP-020）。本文规范它的**客户区**：内容区与底部按钮行的布局、按钮约定、焦点范围、尺寸与位置、结果的取得，以及建立在其上的**标准对话框**（消息、确认、单行输入提示）。

## 1. 用途

在应用内向用户提问或提示，并要求其先处理再继续：确认删除、保存更改、输入名称、报告错误。参照 Windows 的 `MessageBox`、`DialogBox` 与 `TaskDialog` 的行为约定。

- 不要求立即处理的状态通知 → 用状态栏或行内提示，不用对话框。
- 需要持续停留、可与宿主并行操作的面板 → 用停靠面板或另开窗口。
- **应用内流程用自绘对话框，系统级提示可用原生**（取舍见 REQ-W-DIALOG-017）。

## 2. 解剖

```
┌─ 系统标题栏（原生，含关闭按钮）─────────────────────┐
│ ┌─ 客户区（内边距 pad_dialog，底色 surface_window）─┐ │
│ │ [图标]  主指令（font_title）                      │ │   ← 消息对话框的内容区
│ │         正文（font_body，自动换行）               │ │
│ │                                                   │ │   ← gap_lg
│ │              [ 确定 ] [ 取消 ]                    │ │   ← 按钮行：右对齐，等宽，间距 gap_md
│ └───────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────┘
```

- **客户区**：由框架提供内边距与底色（REQ-APP-019）。
- **内容区**：应用内容（标准对话框为图标 + 主指令 + 正文，或输入提示的标签 + 文本框）。
- **按钮行**：底部一行按钮，右对齐。
- **默认按钮**：`accent` 变体，响应 Enter。
- **取消按钮**：响应 Esc、标题栏关闭按钮与 Alt+F4。

## 3. 度量与布局

| 项 | 取值（令牌） |
|---|---|
| 客户区内边距 | `pad_dialog`（四边） |
| 内容区与按钮行的间距 | `gap_lg` |
| 按钮高度 | `control_h` |
| 按钮间距 | `gap_md` |
| 按钮宽度 | 全体等宽 = `max(button_min_w, 最宽按钮的自然宽)`（REQ-W-BUTTON-002） |
| 消息图标 | `icon_lg`（09 规定仅用于消息对话框的严重程度图标），颜色 `status_info`/`status_warning`/`status_danger`/`status_success` |
| 图标与文字栏间距 | `gap_md` |
| 主指令样式 | `font_title`，`text_primary` |
| 正文样式 | `font_body`，`text_primary` |
| 主指令与正文间距 | `gap_sm` |
| 文字栏最大宽度 | `dialog_text_max_w` |
| 输入提示的标签与文本框间距 | `gap_sm` |
| 底色 | `surface_window` |

**REQ-W-DIALOG-001**　对话框根是一个 Column：自上而下为**内容区**（`main = fit`，`cross = fill`）、间距 `gap_lg`、**按钮行**（`cross = fixed(control_h)`）；根的四边内边距即客户区 `pad_dialog`（REQ-APP-019）。`w.beginDialogBody`/`w.endDialogBody` 声明内容区（容纳应用内容，内部按应用选择 Column/Form 等容器布局，07），`w.dialogButtons` 声明按钮行。内容区宽度为内容的期望宽度，但不小于按钮行的期望宽度；对话框客户区期望宽度 = `2 × pad_dialog + max(内容区期望宽, 按钮行期望宽)`，期望高度 = `2 × pad_dialog + 内容区高 + gap_lg + control_h`。内容区的内容较宽/较高时以工作区尺寸为限制测量（REQ-APP-019），超出工作区时内容自行换行或滚动（应用负责，标准对话框的文字栏按 `dialog_text_max_w` 换行，不会超出）。

**REQ-W-DIALOG-002**　**按钮行**（`w.dialogButtons(ui, src, buttons) ?u32`，属 `widgets` 模块，11 的 REQ-APP-020 引用）：按钮自左至右按**声明顺序**排列，整行**右对齐**（`justify = end`），间距 `gap_md`；全体按钮**等宽**，宽度 = `max(button_min_w, 全部按钮中最宽自然宽)`；高度 `control_h`。按钮标题取 `DialogButton.label`（可含助记符，REQ-INPUT-046）。返回本帧被激活的按钮的 `code`（激活类结果，无则 `null`）。至多一个承担默认角色的按钮（`role = default` 或 `default_and_cancel`，用 `accent` 变体绘制，其余 `neutral`，见 button.md 的变体约定）与一个承担取消角色的按钮（`role = cancel` 或 `default_and_cancel`；同一个按钮可以同时是默认与取消）；多于一个时调试构建断言，发布构建取先声明者；按钮数为 0 是编程错误（调试构建断言，发布构建显示空按钮行）。

**REQ-W-DIALOG-003**　**按钮顺序遵循 Windows 约定**：确定类（肯定、继续）在左，取消（否定、放弃）在右；"是/否/取消"三者依次为 是、否、取消；"保存/不保存/取消"依次为 保存、不保存、取消；"重试/取消"依次为 重试、取消；"确定/取消"依次为 确定、取消；仅有一个按钮时它是默认按钮。标准对话框的按钮组按此顺序生成（REQ-W-DIALOG-013）；应用自定义按钮组由应用按同一约定排序，`dialogButtons` 不重排。

**REQ-W-DIALOG-004**　`dialogButtons` 调用 `ui.rootScope(ScopeSpec{ default_button, cancel_button, trap_tab = true })`（REQ-INPUT-039），把 `role = default`（或 `default_and_cancel`）的按钮设为范围的默认按钮、`role = cancel`（或 `default_and_cancel`）的设为取消按钮；`default_and_cancel` 使同一个按钮既响应 Enter 又响应 Esc。因此：焦点在非按钮控件（文本框、复选框）上时按 **Enter** 触发默认按钮（`activated = .default_button`，REQ-INPUT-034）；焦点在某个按钮上时 Enter 触发**该按钮**（REQ-W-BUTTON-016）；按 **Esc** 触发取消按钮（`activated = .cancel_button`）。默认按钮被禁用（应用传入的某按钮 `enabled` 为假）时 Enter 无效果、Esc 同理。需要禁用某按钮时应用经 `DialogButton.enabled`（11）传入。

**REQ-W-DIALOG-005**　**关闭的等效性**：(1) **Esc**：声明了取消按钮（`role = cancel` 或 `default_and_cancel`）时等效于取消——对话框收到 `activate(cancel_button)`，`dialogButtons` 返回取消按钮的 `code`（应用据此调用 `dlg.close(code)`）；**未声明取消按钮时 Esc 无效果**（Esc 被丢弃，REQ-INPUT-034）。(2) **标题栏关闭按钮与 Alt+F4**（平台的关闭请求，13 的 `close` 指令注入同一请求）：恒以取消码关闭——声明了取消按钮时与点击它完全相同（返回其 `code`），未声明时以 `DialogCode.cancel`（2）关闭（REQ-APP-018）。仅有"确定"一个按钮的消息对话框使用 `ButtonRole.default_and_cancel`（11）：该按钮既是默认按钮又是取消按钮，因此 Esc、关闭、Alt+F4 得到 `DialogCode.ok` 而不是 `cancel`。

## 4. 变体与参数

对话框内容区的约定函数 `w.beginDialogBody` 的选项：

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `gap` | `theme.Gap` | `.md` | 内容区子项之间的间距 |
| `min_width` | `?f32`（lpx） | `null` | 内容区期望宽度的下限（应用提供的数值） |
| `key`、`debug_name`、`enabled`、`layout` | 通用 | | 见模板 |

`DialogButton`（11）：`label`、`code`、`role ∈ {normal, default, cancel, default_and_cancel}`、`enabled: bool = true`；本文不重复定义。

标准对话框选项见第 12 节：

| 对话框 | 关键参数 | 结果 |
|---|---|---|
| 消息 `showMessage` | `icon`（`none/info/warning/error/success`）、`instruction`（主指令）、`body`、`buttons`（`MessageButtons`）、`default` | `DialogCode`（按所点按钮） |
| 确认 `confirm` | `instruction`、`body`、`confirm_label`、`cancel_label`、`destructive` | `DialogCode.ok` 或 `DialogCode.cancel` |
| 输入提示 `prompt` | `instruction`、`label`、`initial`、`placeholder`、`max_len`、`password`、`validate`、`ok_label` | `DialogCode.ok` 加文本，或 `DialogCode.cancel` |

**REQ-W-DIALOG-006**　`w.beginDialogBody` 返回内容区容器 ID：它是一个 Column（`main = fit`，`cross = fill`），子项间距 `gap`，设置 `min_width` 时内容区的 `cross_min` 取该值；`endDialogBody` 配对（REQ-FRAME-028）。一个对话框至多一个内容区与一个按钮行（调试构建对第二个断言）；按钮行必须声明在内容区之后。不使用 `beginDialogBody` 的应用自定义对话框可直接用 07 的容器自行布局，但**仍须**用 `w.dialogButtons` 声明按钮行，以获得 REQ-W-DIALOG-002、REQ-W-DIALOG-004 与 REQ-W-DIALOG-005 的行为。

## 5. 状态

### 5.1 状态机

状态变量：对话框生命周期 `lifecycle ∈ {打开中, 已关闭}`；`result ∈ {无, 结果码}`；宿主被禁用（由 11 维护）。

| 当前 | 事件 | 条件 | 下一状态 | 动作 |
|---|---|---|---|---|
| 无 | `app.openDialog` | 宿主窗口有效 | 打开中 | 宿主关闭其全部弹出层（`dialog_opened`）并被禁用；对话框窗口居中显示，初始焦点按 REQ-W-DIALOG-009 |
| 打开中 | 某按钮被激活（鼠标、Space、Enter、助记符） | 按钮启用 | 已关闭 | `dialogButtons` 返回其 `code`；应用调用 `dlg.close(code)` |
| 打开中 | Esc | 声明了取消按钮（含 `default_and_cancel`） | 已关闭 | 等效取消（REQ-W-DIALOG-005） |
| 打开中 | Esc | 未声明取消按钮 | 打开中 | 无效果 |
| 打开中 | 标题栏关闭 / Alt+F4（`close` 关闭请求） | — | 已关闭 | 恒以取消码关闭：有取消按钮时为其 `code`，否则 `DialogCode.cancel` |
| 打开中 | Enter | 焦点在非按钮控件，默认按钮启用 | 已关闭 | 触发默认按钮 |
| 打开中 | 宿主被销毁 | — | 已关闭 | 以 `owner_closed` 关闭，**不**调用 `on_result`（REQ-APP-018） |
| 已关闭 | 关闭完成 | — | — | 先启用宿主再销毁对话框窗口；经 `post` 恰好调用一次 `on_result(ctx, code)` |

### 5.2 视觉表现

| 部件 | 绘制 |
|---|---|
| 客户区底 | `surface_window` |
| 消息图标 | `drawMark(info / warning / error / success, icon_lg, status_*)`；`none` 时不占位 |
| 按钮 | button.md：默认按钮 `accent`，其余 `neutral`；焦点环按焦点可见规则 |
| 文本框（输入提示） | text-input.md，`invalid` 状态按其规则 |

标题栏与边框由系统绘制（ADR 0008），框架通过 DWM 属性同步深浅色（03）。

## 6. 鼠标行为

对话框内容区的鼠标行为由各内部控件规定（按钮、文本框等）。对话框窗口本身：

**REQ-W-DIALOG-007**　对话框打开期间宿主窗口被禁用（REQ-APP-017）：宿主不接收任何鼠标与键盘输入（点击宿主得到系统的提示音与闪烁对话框的反馈，不属框架职责），但仍重绘与响应尺寸变化。宿主的全部弹出层（菜单、下拉、提示框）在对话框打开时以 `dialog_opened` 关闭（REQ-INPUT-054）。对话框内的点击只作用于对话框；点击内容区的非可交互区域不改变焦点（REQ-INPUT-022）。

## 7. 键盘行为

| 键 | 行为 |
|---|---|
| Tab / Shift+Tab | 在对话框根范围内循环，不逃逸（`trap_tab`，REQ-INPUT-039） |
| Enter | 焦点在按钮上：触发该按钮；焦点在非按钮控件上：触发默认按钮 |
| Space | 焦点在按钮上：释放时触发该按钮（button.md） |
| Esc | 声明了取消按钮（含 `default_and_cancel`）时触发它（等效取消）；未声明则无效果；文本框组字期间由输入法处理 |
| Alt+助记符 | 触发标题中含该助记符的按钮（button.md、REQ-INPUT-048）；多个匹配按 08 循环 |
| Alt+F4 | 等效取消 |
| 其余键 | 交给焦点控件（文本框的编辑键等） |

**REQ-W-DIALOG-008**　对话框是独立的根，有各自的根范围与 `Ui`（REQ-INPUT-039）：Tab 循环**不逃逸**——在范围内末尾回绕到开头，不进入宿主窗口或其他根；弹出层（如组合框的下拉）内的 Tab 不进入对话框。对话框**不继承**宿主的快捷键表（REQ-APP-019），宿主的命令快捷键在对话框中无效。

## 8. 焦点

**REQ-W-DIALOG-009**　**初始焦点**：焦点按下列优先级给：(1) `ScopeSpec.initial_focus`（应用指定者）；(2) 范围内 Tab 序中第一个**非按钮**的可聚焦控件（文本框、复选框、列表等）；(3) 默认按钮；(4) 无默认按钮时 Tab 序第一个停靠点。**实现途径**：`w.dialogButtons` 在对话框**首次构建**中按上述优先级算出目标（应用已指定 `initial_focus` 则尊重之；否则取本次构建中先于按钮行声明的第一个可聚焦非按钮控件，无则取默认按钮，再无则取第一个按钮），把它写入根范围的 `ScopeSpec.initial_focus`（`ui.rootScope`，REQ-INPUT-043 的初始焦点点：首次构建完成后若无焦点则取 `initial_focus`）；因此 `destructive` 确认对话框（默认按钮是"取消"、无其他可聚焦控件）的初始焦点是"取消"。若获得焦点的是文本输入类控件，因原因 `initial` 而全选其内容（text-input.md 的 REQ-W-TEXTINPUT-047）。对话框关闭时不需要额外处理焦点。（与 11 的 REQ-APP-020(3) 一致。）

**REQ-W-DIALOG-010**　**关闭后焦点回到宿主打开前的焦点节点**：宿主窗口在被禁用与失去激活期间，其焦点节点**被记住**（REQ-INPUT-041）；对话框关闭后系统把激活还给宿主（先启用宿主再销毁对话框，REQ-APP-017），宿主以原因 `restore` 恢复该焦点节点——框架**不**另行设置焦点。若该节点在对话框打开期间已消失或不可聚焦，按 REQ-INPUT-042 转移。链式嵌套时（对话框 A 打开对话框 B），B 关闭后焦点回到 A 的对话框内记住的节点，A 关闭后回到最初宿主的节点。

**REQ-W-DIALOG-011**　**嵌套对话框的宿主链**：对话框可以以另一个对话框为宿主（`app.openDialog(owner = 对话框窗口, …)`）；只有链的末端启用，其余各级被禁用（REQ-APP-017）。打开子对话框时宿主对话框的弹出层同样以 `dialog_opened` 关闭。宿主被销毁时其全部子对话框先被关闭（`owner_closed`）；中间一级对话框被应用关闭（`dlg.close`）时其子对话框同样先关闭。

## 9. 文本与输入法

对话框内显示的文字（主指令、正文、按钮标题）为纯文本，不可选择、不可复制；换行与制表符在正文中按 05 的规则处理（正文中的 `\n` 是硬换行，保留）。输入提示的文本框是 text-input.md 的文本输入控件，输入法按其规则启用；组字期间 Enter、Esc、Tab 由输入法处理，不触发默认/取消按钮/导航（REQ-INPUT-026）。

**REQ-W-DIALOG-012**　**消息对话框内容区**：自左至右为图标（`icon != .none` 时，`icon_lg` 见方、`status_*` 着色、顶部与主指令第一行对齐）、间距 `gap_md`、文字栏；文字栏自上而下为主指令（`font_title`，必选，超出文字栏宽度时换行）、`gap_sm`、正文（`font_body`，可选，`wrap = .word`，保留 `\n`）。文字栏最大宽度 `dialog_text_max_w`，其期望宽度 = 主指令与正文在该上限内排版后的最宽行宽。主指令为空串是编程错误（调试构建断言，发布构建只显示正文）。无图标时不留图标列。

**REQ-W-DIALOG-013**　`MessageButtons` 与按钮组（自左至右、默认按钮标 ★、取消按钮标 ✕；标签取 11 的内建字符串表 `Strings.ok/cancel/yes/no/retry/close/save/dont_save`）：`ok` = [确定★✕]（单一按钮用 `ButtonRole.default_and_cancel`）；`ok_cancel` = [确定★、取消✕]；`yes_no` = [是★、否✕]；`yes_no_cancel` = [是★、否、取消✕]；`retry_cancel` = [重试★、取消✕]；`save_dontsave_cancel` = [保存★、不保存、取消✕]；`close` = [关闭★✕]（同为 `default_and_cancel`）。结果码依次为 `ok`、`cancel`、`yes`、`no`、`retry`（≥ 100 的自定义码 `custom_base + 1`，因 `DialogCode` 无 `retry`）、`save`（`custom_base + 2`）、`dont_save`（`custom_base + 3`）、`close`（`custom_base + 4`）。`MessageOptions.default` 非空时改以该码对应的按钮为默认按钮（其余不变）；`yes_no` 的取消角色落在"否"上：Esc、关闭、Alt+F4 得到 `DialogCode.no`。

**REQ-W-DIALOG-014**　**确认对话框** `confirm` = 以 `ok_cancel` 按钮组（标签可由 `confirm_label`、`cancel_label` 改写，如"删除"/"取消"）的消息对话框，默认 `icon = .warning`；`destructive = true` 时默认按钮改为**取消**（Enter 触发取消，需要鼠标或 Tab 到确认按钮才能确认）。结果仅 `DialogCode.ok` 或 `DialogCode.cancel`（Esc、关闭、Alt+F4 得 `cancel`）。

**REQ-W-DIALOG-015**　**输入提示对话框** `prompt` 的内容区：主指令（可选）、标签（`label`，可含助记符并以 `focus_next` 关联文本框）、文本框（text-input.md，Enter 经 `observes` 观察而不消费，因此同时触发默认按钮；`max_len`、`password`、`placeholder`、`initial` 由选项给出）；按钮 [确定★、取消✕]。初始焦点在文本框并全选 `initial`（REQ-W-DIALOG-009）。`validate` 非空时每次构建对当前文本调用：返回非空说明则文本框 `invalid = true`、`invalid_message` 为该说明、"确定"按钮禁用（Enter 因默认按钮禁用而无效果）；返回 `null` 则允许确认。点击"确定"或在文本框中按 Enter（默认按钮）关闭并给出 `DialogCode.ok` 与文本；取消、Esc、关闭给出 `DialogCode.cancel`（文本参数为空串）。回调中的文本切片只在回调期间有效，应用须自行复制。

**REQ-W-DIALOG-016**　**结果的取得**：应用内对话框是非阻塞的（REQ-APP-016）：(1) 回调——`on_result(ctx, code)`（`prompt` 为 `on_result(ctx, code, text)`）在对话框关闭完成后经 `post` 在一个独立的消息循环轮次中**恰好调用一次**，不在对话框的帧内；(2) 轮询——宿主在构建函数中调用 `dlg.result() ?u32`（未关闭为 `null`），两种方式可并用。宿主已被销毁时不调用回调。结果码为 `DialogCode` 的标准值（`ok = 1`、`cancel = 2`、`yes = 6`、`no = 7`）或 ≥ 100 的自定义码。

**REQ-W-DIALOG-017**　**与原生 `TaskDialog` 的取舍**：应用内的流程（保存前确认、输入名称、业务错误提示）**应当**用本文的自绘对话框——外观随主题与深浅色、尺寸随 DPI、非阻塞、可在无头测试中断言、不依赖平台；以下系统级场景**可以**使用原生 `app.native.taskDialog`（11 的 REQ-APP-021，阻塞，只能在帧后动作内调用）：尚无宿主窗口时（启动失败、致命错误）、会话结束或崩溃前的最后提示、需要系统提供的复选"不再提示"、命令链接、展开的详细信息、进度条、需要与其他应用一致的系统样式时。本文的标准对话框**不是**原生控件，不提供上述 `TaskDialog` 特性。

## 10. 动效

对话框客户区没有自有动画：内容与按钮遵循各控件的动效（悬停、焦点环）；窗口的显示与关闭动画由系统窗口管理器决定，框架不干预。

| 属性 | 触发 | 时长令牌 | 缓动 | 影响级别 |
|---|---|---|---|---|
| 按钮悬停/按下、焦点环、文本框边框 | 状态变化 | 各控件规定（`dur_fast`、`dur_instant`） | `ease_out` | paint |

## 11. 无障碍

| 项 | 值 |
|---|---|
| UIA 控件类型 | Window（对话框窗口），`IsDialog` 真 |
| 名称来源 | `DialogOptions.title` |
| 支持的模式 | Window（`IsModal` 真） |
| 状态属性 | IsEnabled、HasKeyboardFocus；描述（FullDescription）= 主指令加正文（标准对话框） |

**REQ-W-DIALOG-018**　对话框窗口的 UIA 控件类型为 Window，`IsDialog` 为真，`WindowPattern.IsModal` 为真（宿主被禁用期间），Name = 对话框标题；标准消息对话框的 `FullDescription` 为"主指令 + 换行 + 正文"。窗口打开时辅助技术收到窗口打开事件并读出标题与描述；初始焦点控件朗读其自身名称。严重程度图标暴露为独立元素，其无障碍名称取内建字符串 `Strings.severity_info`、`severity_warning`、`severity_error`（`success` 与 `none` 无名称，视为装饰性）。按钮的 Name 取去除助记符的标题，默认按钮的 `IsDefault`（无对应 UIA 属性时以 `HelpText` 附"默认"字样，见待定问题）可被读出。

## 12. API 草案

```zig
// 草案：仅签名
// —— widgets：内容区约定与按钮行 ——
pub const DialogBodyOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    gap: theme.Gap = .md,
    min_width: ?f32 = null,                // lpx，内容区期望宽度下限
    layout: layout.ItemOptions = .{},
};
pub fn beginDialogBody(ui: *Ui, src: std.builtin.SourceLocation, opts: DialogBodyOptions) WidgetId;
pub fn endDialogBody(ui: *Ui) void;

/// DialogButton 与 ButtonRole（含 default_and_cancel）、enabled 定义于 11，本文引用：
///   app.DialogButton{ label, code, role: app.ButtonRole = .normal, enabled: bool = true }
/// 声明按钮行并设置根范围的默认/取消按钮（11 的 REQ-APP-020 引用本函数）。label 借用至本帧结束。返回本帧被激活的按钮的 code。
pub fn dialogButtons(ui: *Ui, src: std.builtin.SourceLocation, buttons: []const app.DialogButton) ?u32;   // 激活类结果

// —— app：标准对话框 ——
pub const MessageIcon = enum { none, info, warning, @"error", success };
pub const MessageButtons = enum { ok, ok_cancel, yes_no, yes_no_cancel, retry_cancel, save_dontsave_cancel, close };

pub const MessageOptions = struct {
    title: []const u8,                     // 框架复制
    icon: MessageIcon = .info,
    instruction: []const u8,               // 主指令，必选；框架复制
    body: ?[]const u8 = null,              // 正文；框架复制
    buttons: MessageButtons = .ok,
    default: ?u32 = null,                  // 默认按钮的结果码；null = 按钮组的默认
    persist_name: ?[]const u8 = null,      // 仅持久化位置（11）
};
pub const ConfirmOptions = struct {
    title: []const u8,
    icon: MessageIcon = .warning,
    instruction: []const u8,
    body: ?[]const u8 = null,
    confirm_label: ?[]const u8 = null,     // null = Strings.ok
    cancel_label: ?[]const u8 = null,      // null = Strings.cancel
    destructive: bool = false,             // 真：默认按钮为取消
    persist_name: ?[]const u8 = null,
};
pub const ValidateFn = *const fn (ctx: ?*anyopaque, text: []const u8) ?[]const u8;   // 返回错误说明，null 表示合法；说明借用至下次调用前
pub const PromptOptions = struct {
    title: []const u8,
    instruction: ?[]const u8 = null,
    label: ?[]const u8 = null,             // 含助记符
    initial: []const u8 = "",
    placeholder: ?[]const u8 = null,
    max_len: ?u32 = null,                  // 字素簇
    password: bool = false,
    validate: ?ValidateFn = null,
    validate_ctx: ?*anyopaque = null,
    ok_label: ?[]const u8 = null,
    persist_name: ?[]const u8 = null,
};
pub const PromptResultFn = *const fn (ctx: ?*anyopaque, code: u32, text: []const u8) void;   // text 仅在回调期间有效

pub const dialogs = struct {
    pub fn message(app: *App, owner: *Window, opts: MessageOptions, ctx: ?*anyopaque, on_result: ?ResultFn) OpenDialogError!*Dialog;
    pub fn confirm(app: *App, owner: *Window, opts: ConfirmOptions, ctx: ?*anyopaque, on_result: ?ResultFn) OpenDialogError!*Dialog;
    pub fn prompt(app: *App, owner: *Window, opts: PromptOptions, ctx: ?*anyopaque, on_result: ?PromptResultFn) OpenDialogError!*Dialog;
};
// ResultFn、Dialog、DialogCode、DialogOptions、OpenDialogError、App.openDialog 定义于 11。
```

`dialogButtons` 的返回值是激活类结果（触发同帧第二构建遍，REQ-FRAME-030）。传入的字符串借用至本帧结束（`dialogButtons`、`beginDialogBody`）或由框架复制（标准对话框的选项）；`on_result` 的 `ctx` 须在对话框关闭前存活。对话框窗口由 11 的 `app.openDialog` 创建，本文不重复其签名。

## 13. 保留状态

| 字段 | 类型 | 保留级别 | 说明 |
|---|---|---|---|
| 对话框 `Ui` 的焦点、悬停、各控件状态 | 框架内建 / 各控件 | transient / 各控件 | 对话框关闭即销毁 |
| 标准对话框的输入文本 | `TextBuf`（`prompt` 内部持有） | 对话框存活期间 | 回调时以切片交出 |
| 窗口位置 | 持久化设置（11，`persist_name`） | 跨进程 | 仅位置，不含尺寸 |

## 14. 失效规则

**REQ-W-DIALOG-019**　标准对话框内容区各节点的绘制键由文字内容、图标、各按钮的标题/角色/启用状态、文本框状态构成；布局输入的内容度量键由文字内容与字体样式、按钮标题构成。对话框是独立的 `Ui`：其失效只影响对话框窗口，不引起宿主 `Ui` 的任何帧；宿主在对话框打开期间的失效（重绘、尺寸变化、`invalidate`）只绘制宿主窗口。

| 变化 | 置脏级别 | 损伤范围 |
|---|---|---|
| 按钮悬停进入/离开、焦点环 | `paint` | 该按钮绘制范围（对话框窗口内） |
| 键入文本、`validate` 结果变化 | `build` | 文本框、说明与"确定"按钮 |
| 内容变化导致期望尺寸变化 | `layout` + 窗口重新适配（11：保持左上角） | 整个对话框窗口 |
| 打开/关闭对话框 | 宿主 `paint`（被禁用状态不改变外观） | 宿主无损伤 |

**REQ-W-DIALOG-020**　对话框静置、无输入、无动画、无定时器（光标闪烁除外）时**必须**无帧（REQ-FRAME-053）；仅按钮悬停进入/离开所产生的帧**必须**是纯绘制帧（构建遍数 0），损伤不超出该按钮的绘制范围。

## 15. 边界与错误情况

| 情况 | 规定 |
|---|---|
| 标题为空串 | 允许（系统标题栏为空）；调试构建 `warn` |
| 主指令为空串（消息对话框） | 调试构建断言，发布构建只显示正文 |
| 文字极长 | 文字栏按 `dialog_text_max_w` 换行；高度超过工作区时对话框高度夹紧到工作区并使正文可滚动（应用自定义对话框由应用负责） |
| 按钮标题极长 | 等宽取最宽者；总宽超过工作区时按钮行不换行，对话框宽度夹紧到工作区、按钮在 `fit_shrink` 下以省略号截断标题（REQ-THEME-018） |
| 无按钮 / 多个默认 / 多个取消 | REQ-W-DIALOG-002 |
| 无取消角色 | Esc 无效果；标题栏关闭/Alt+F4 以 `DialogCode.cancel` 关闭（REQ-APP-018） |
| 默认按钮被禁用 | Enter 无效果 |
| 对话框打开时宿主已销毁 | 不打开（`OpenDialogError`，11） |
| 宿主在对话框期间被应用关闭 | 对话框先关闭（`owner_closed`），不调用 `on_result` |
| 对话框内再打开对话框 | 允许，形成宿主链（REQ-W-DIALOG-011） |
| 在对话框的构建中调用 `app.native.*` | 只能在 `afterFrame` 内（REQ-APP-021） |
| `validate` 回调阻塞或副作用 | 违反构建函数契约（REQ-FRAME-025/026），应为纯函数 |
| 窗口位置的持久化坐标不在任何显示器工作区 | 由 03 的校验规则回退为居中于宿主（REQ-PLAT-014） |
| 对话框首次出现于宿主跨多个显示器时 | 居中于宿主窗口所在显示器的工作区内（夹紧） |
| DPI 变化（拖到另一缩放的显示器） | 客户区尺寸按新 scale 重新测量适配（REQ-LAYOUT-052） |
| 高对比度 | 按钮、文本框、图标按各控件的高对比度映射；图标的 `status_*` 映射到系统文字色（REQ-THEME-035） |

**REQ-W-DIALOG-021**　**尺寸**：对话框客户区尺寸（`DialogOptions.size = null`，默认）为根节点的期望尺寸（REQ-W-DIALOG-001），以工作区尺寸为限制测量，窗口创建时即取该尺寸并**固定**——默认**不可缩放**（`resizable = false`，REQ-APP-019），系统不显示最大化按钮与缩放边框。内容的期望尺寸在对话框存续期间变化（如输入提示出现多行说明）时，客户区自动重新适配（保持左上角不动，REQ-APP-019）。`DialogOptions.resizable = true`（可选）时对话框可缩放：**最小客户区尺寸**为根节点的最小期望尺寸（REQ-LAYOUT-053，由 `min` 测量模式得出，不小于按钮行的期望宽度加 `2 × pad_dialog`），用户拖动窗口边框不得小于该尺寸，内容区随之伸展（按钮行保持右下对齐）；可缩放对话框的尺寸**不**被持久化（仅位置，REQ-APP-014）。客户区尺寸不超过宿主所在显示器的工作区。

**REQ-W-DIALOG-022**　**位置**：首次出现时居中于宿主窗口（窗口矩形的中心，非客户区）并夹紧到宿主所在显示器的工作区内（不被任务栏遮挡，不超出工作区）；`DialogOptions.persist_name` 非空时，若设置存储中有该名称的位置且通过 03 的校验（与某显示器工作区的交集不小于 25%，REQ-PLAT-014、REQ-APP-015），则恢复该位置（位置按桌面坐标保存，不随宿主移动），否则居中；关闭时保存当前位置。对话框每次打开都重新居中（无 `persist_name` 时）。多显示器下"居中于宿主"取宿主窗口中心所在显示器。

## 16. 验收标准

**夹具 F-DG**（除特别注明外）：行高取 `font_body` 的令牌行高 16（REQ-THEME-016），`font_title` 的令牌行高 19（`round(14 × 4/3)`），与 fixed 后端的自然行高无关；无头、`fixed` 文本后端（正文簇宽 6 px，行高 16 px；`font_title` 字号 B + 2 = 14，簇宽 7 px，行高 19 px）、缩放 1.0、B = 12；宿主窗口 600×400（位于屏幕 (100,100)，屏幕工作区 1280×720）；应用经 `model` 钩子打开各对话框；回放以 `window @对话框调试名` 切换到对话框窗口、以 `window main` 切回宿主（13 的 `window` 指令）；`Strings` 取 zh_cn（确定、取消、是、否、重试、保存、不保存、关闭）。回放记号同 text-input.md 第 16 节；"对话框客户区"尺寸取自假平台窗口客户区。

**几何基准（由 REQ-W-DIALOG-001、REQ-W-DIALOG-002、REQ-W-DIALOG-012 推得）**：确认对话框——图标 `.warning`、主指令 "确认删除？"（5 簇 × 7 = 35 px）、正文 "此操作无法撤销。"（8 簇 × 6 = 48 px）、按钮 [确定、取消]：文字栏宽 = max(35, 48) = 48，高 = 19 + `gap_sm` 4 + 16 = 39；图标行宽 = `icon_lg` 32 + 8 + 48 = 88；按钮宽均为 `button_min_w` 72，按钮行宽 = 72 + 8 + 72 = 152；内容区宽 = max(88, 152) = 152；客户区 = **(176, 99)**（宽 = 12 + 152 + 12；高 = 12 + 39 + 12 + 24 + 12）；按钮 y ∈ [63,87)，取消 x ∈ [92,164)、确定 x ∈ [12,84)；图标 (12,12,32,32)，主指令基线对齐首行。窗口位置：对话框窗口矩形（客户区加系统非客户区，尺寸以假平台为准）的中心 = 宿主窗口中心 (100 + 300, 100 + 200) = (400,300)。

**AC-W-DIALOG-001**　`[金图]` 覆盖：REQ-W-DIALOG-012、REQ-W-DIALOG-013、REQ-W-DIALOG-014、REQ-W-DIALOG-015、REQ-W-DIALOG-002、REQ-W-DIALOG-003、REQ-W-DIALOG-001。状态矩阵（对话框客户区）：消息 {info, warning, error, success, 无图标} × 按钮组 {ok, ok_cancel, yes_no, yes_no_cancel, retry_cancel, save_dontsave_cancel}；确认（含 `destructive`，默认按钮为取消）；输入提示 {空文本、有 `placeholder`、`validate` 失败（文本框 `invalid`、说明提示、"确定"禁用）、密码}；自定义对话框（`beginDialogBody` 加 `dialogButtons`，含禁用按钮）；浅/深/高对比度 × 缩放 1.0/1.5/2.0；长正文换行、长按钮标题。预期：与基准图一致；默认按钮为 `accent` 变体且初始焦点环按焦点可见规则；按钮等宽、右对齐、间距 `gap_md`、顺序为 确定 在左、取消 在右（`yes_no_cancel` 为 是、否、取消）；图标色为对应 `status_*` 且 `none` 时无图标列；主指令 `font_title`、正文 `font_body`；`validate` 失败时文本框边框 `status_danger` 且有错误图标。

**AC-W-DIALOG-002**　`[单元]` 覆盖：REQ-W-DIALOG-001、REQ-W-DIALOG-002、REQ-W-DIALOG-012、REQ-W-DIALOG-021、REQ-W-DIALOG-006。几何（夹具同上）：确认对话框客户区 (176,99)，按钮取消 [92,164)、确定 [12,84)，y ∈ [63,87)。按钮标题 "保存"、"不保存全部更改"（7 簇 = 42，自然宽 42 + 2 × 10 = 62，小于 72）、"取消" → 全体宽 `button_min_w` 72，三按钮行宽 = 3 × 72 + 2 × 8 = 232；标题改为 "Don't save my changes"（21 簇 = 126 + 20 = 146）→ 全体宽 146，行宽 = 3 × 146 + 16 = 454、客户区宽 478。正文 120 个 "a"（无空格，图标 `.warning`）→ 文字栏以 `dialog_text_max_w` 420 为上限排版，每行 70 簇（420 px）、2 行（70、50），文字栏宽 420、客户区宽 = 12 + (32 + 8 + 420) + 12 = 484（按钮行更宽时取较大者）。内容区 `min_width` = 300 → 客户区宽 ≥ 324。默认不可缩放：窗口无最大化按钮、拖动边框不改变尺寸；`resizable = true`：最小客户区 = 按钮行宽 + 24，拖到更小被夹紧；内容变化（输入提示增加一行说明）→ 客户区高度增加且左上角不动。`beginDialogBody` 第二次调用与按钮行早于内容区在调试构建断言。

**AC-W-DIALOG-003**　`[回放]` 覆盖：REQ-W-DIALOG-004、REQ-W-DIALOG-005、REQ-W-DIALOG-008、REQ-W-DIALOG-007。打开 `ok_cancel` 消息对话框（宿主中有展开的菜单与组合框弹出层）：宿主弹出层全部关闭（`dialog_opened`，`expect popup 0`）；点击宿主窗口内任一位置 → 宿主无任何输入反应（无 `clicked`、无焦点变化）；宿主的命令快捷键（登记 Ctrl+S 命令）在对话框中按下 → 命令未被调用。在对话框中：Tab → 焦点循环 [确定 → 取消 → 确定]，不进入宿主；Shift+Tab 反向；焦点在"取消"时按 Enter → 触发"取消"（`code` = 2），**不**触发默认按钮；焦点在"确定"时按 Space → 释放时触发"确定"（`code` = 1）；按 Esc → 返回取消码 2；`close` 指令（标题栏关闭与 Alt+F4 的关闭请求）→ 同样返回 2。`yes_no`：Esc 与 `close` → 返回 `no`（7）；`ok`（仅确定，`default_and_cancel`）：Esc 与 `close` → 返回 `DialogCode.ok`（1）；自定义对话框无取消角色：Esc **无效果**（对话框保持打开），`close` → 以 `DialogCode.cancel`（2）关闭。含文本框的对话框（焦点在文本框）：Enter → 默认按钮触发，Esc → 取消按钮触发；默认按钮被禁用时 Enter 无效果。

**AC-W-DIALOG-004**　`[回放]` 覆盖：REQ-W-DIALOG-009、REQ-W-DIALOG-010、REQ-W-DIALOG-011、REQ-W-DIALOG-016。（1）初始焦点：消息对话框 → 默认按钮"确定"持有焦点；含 [复选框 C, 文本框 T] 与 [确定★, 取消✕] 的自定义对话框 → 焦点在 C（第一个非按钮控件）；`initial_focus` 指定 T → 焦点在 T 且文本全选；`prompt`（`initial` = "新建文件"）→ 焦点在文本框、选区 (0,12)。（2）焦点归还：宿主中文本框 `@HT` 持有焦点（光标 2）时打开对话框；对话框关闭后 → `expect focus @HT`、`HT` 选区与光标不变（原因 `restore`，**不**全选）；对话框打开期间宿主焦点节点被应用移除 → 关闭后焦点按 REQ-INPUT-042 转移。（3）嵌套：对话框 A 中打开对话框 B → A 被禁用、B 启用，A 的弹出层以 `dialog_opened` 关闭；关闭 B → A 重新启用且焦点回到 A 内打开 B 前的节点；关闭宿主窗口 → A 与 B 先关闭（`owner_closed`），两者的 `on_result` 均**未**调用。（4）结果：回调形式 → 点击"确定"后 `on_result` 恰好调用 1 次，参数为 1，调用发生在对话框帧之外（关闭后的下一个消息轮次）；轮询形式 → 关闭前 `dlg.result()` 为 `null`，关闭后为 1；两种并用时回调与轮询一致；`yes_no_cancel` 点击"是/否/取消"分别得 6、7、2；自定义码 ≥ 100 原样返回。

**AC-W-DIALOG-005**　`[回放]` 覆盖：REQ-W-DIALOG-013、REQ-W-DIALOG-014、REQ-W-DIALOG-012。消息对话框各按钮组：`ok` → [确定]；`ok_cancel` → [确定★、取消]；`yes_no` → [是★、否]；`yes_no_cancel` → [是★、否、取消]；`retry_cancel` → [重试★、取消]；`save_dontsave_cancel` → [保存★、不保存、取消]；`close` → [关闭]；Enter 触发带★的默认按钮，结果码依次为 1 / 1 或 2 / 6 或 7 / 6、7、2 / 100 + 1 或 2 / 100 + 2、100 + 3、2 / 100 + 4。`default` 选项改默认：`yes_no` 设 `default` = 7 → 初始焦点在"否"、Enter 返回 7。确认对话框 `destructive = true` → 默认按钮为"取消"，`w.dialogButtons` 在首次构建把 `initial_focus` 设为它（无其他可聚焦控件，优先级 (3)），故初始焦点为"取消"、Enter 返回 2；Tab 到"确定"后按 Enter 返回 1；`confirm_label` = "删除" → 按钮显示 "删除"、结果码仍为 1。主指令为空串 → 调试构建断言。无图标 → 文字栏左对齐到内边距。

**AC-W-DIALOG-006**　`[回放]` 覆盖：REQ-W-DIALOG-015、REQ-W-DIALOG-016、REQ-W-DIALOG-004。`prompt`（`label` = "名称(&N)"、`initial` = "新建文件"、`max_len` = 8、`validate` 要求非空且不含 "/"）：打开 → 文本全选；键入 "报告" → 文本 "报告"；按 Enter → 默认按钮"确定"触发（文本框的 Enter 是观察、不消费），回调 `(code = 1, text = "报告")`。键入 "a/b" → `validate` 返回说明 → 文本框 `invalid`（边框 `status_danger`、错误图标、提示 `invalid_message`）、"确定"禁用、Enter 无效果；改正后恢复。清空文本 → 非空校验失败 → "确定"禁用。`max_len` = 8：键入第 9 个字素簇被忽略。取消、Esc、标题栏关闭 → 回调 `(code = 2, text = "")`。Alt+N（标签助记符）→ 焦点移到文本框（`focus_next`）并全选。`password` = true → 文本框显示圆点、Ctrl+C 无效。回调中的 `text` 在回调返回后不再使用（应用复制）。

**AC-W-DIALOG-007**　`[回放]` 覆盖：REQ-W-DIALOG-022、REQ-W-DIALOG-021。宿主窗口 (100,100,600,400)，工作区 (0,0,1280,720)：对话框（客户区 176×99，窗口矩形含系统非客户区，尺寸以假平台为准）首次出现 → 窗口矩形中心 = 宿主窗口中心 (400,300)，且完全在工作区内；宿主靠近屏幕左上角 (0,0,300,200) 时对话框夹紧到工作区内（左上角 ≥ (0,0)）；宿主在副显示器上 → 居中于宿主所在显示器工作区内；`persist_name` = "dlg.confirm"：用户把对话框拖到 (700,500) 后关闭 → 下次打开出现在 (700,500)；保存的位置不在任何显示器工作区内（拔掉副屏）→ 回退居中；不设 `persist_name` → 每次居中。`resizable = true` 的尺寸不被持久化。DPI 变化 `dpi 144` → 客户区按新 scale 重新适配。

**AC-W-DIALOG-008**　`[单元]` 覆盖：REQ-W-DIALOG-018、REQ-W-DIALOG-017、REQ-W-DIALOG-002、REQ-W-DIALOG-012。经假 UIA 入口：对话框窗口 Window、`IsDialog` 真、`IsModal` 真（宿主禁用期间）、Name = 标题；`FullDescription` = "主指令\n正文"；按钮 Name 为去除助记符的标题。API 契约：`dialogButtons` 空数组、双默认、双取消在调试构建断言；`MessageOptions.instruction` 为空串断言；`DialogCode` 自定义码 < 100 不被框架占用；在构建函数内调用 `app.native.taskDialog` → 调试构建断言中止（REQ-APP-021），帧后动作内调用成功。

**AC-W-DIALOG-009**　`[计量]` 覆盖：REQ-W-DIALOG-019、REQ-W-DIALOG-020。对话框打开后静置 60 秒 → 对话框与宿主的 `frame.count` 增量均为 0、进程 CPU 时间增量 < 10 ms（文本框光标闪烁的对话框除外：仅光标矩形的纯绘制帧）；指针移入移出"取消"按钮 → 各帧构建遍数 0、损伤 ≤ 该按钮绘制范围；宿主在对话框打开期间 `invalidate(.build)` → 只绘制宿主窗口、对话框无帧；`prompt` 中键入一个字符 → 对话框 `build`，宿主无帧；以相同参数再次 `invalidate(.build)` → 对话框损伤为空。

**AC-W-DIALOG-010**　`[人工]` 覆盖：REQ-W-DIALOG-007、REQ-W-DIALOG-010、REQ-W-DIALOG-005、REQ-W-DIALOG-022、REQ-W-DIALOG-017、REQ-W-DIALOG-018。真实 Windows 10 与 11，浅/深色与高对比度，100%/150%/200% 缩放，双显示器：打开后点击宿主应得到系统的"模态窗口闪烁"反馈且宿主不响应；标题栏深浅色与系统一致、无最大化与最小化按钮；Alt+F4 与标题栏关闭按钮恒以取消码关闭，Esc 仅在有取消按钮时生效；任务栏中对话框不单独出现按钮（owner 关系），Alt+Tab 行为合理；关闭后焦点回到宿主打开前的控件；对话框拖到另一缩放的显示器后尺寸与文字重新适配；Narrator 打开对话框时朗读标题、主指令与正文，初始焦点按钮可读；与原生 `TaskDialog`、`MessageBox` 对照按钮顺序、默认按钮与 Esc 行为，记录差异。

## 17. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-W-DIALOG-07 | 标准对话框不支持"不再提示"复选框、命令链接、展开详情、进度条 | 不在本版；这些需求用原生 `TaskDialog`（REQ-W-DIALOG-017）或自定义对话框 |
| OPEN-W-DIALOG-08 | 点击被禁用的宿主时的系统反馈（提示音/标题栏闪烁）由系统产生 | 不由框架处理；记入人工验收 |
| OPEN-W-DIALOG-09 | `yes_no` 以"否"为取消角色（Esc 得到 7）与 Windows 的 `MessageBox`（Yes/No 时 Esc 被忽略、关闭按钮禁用）不同 | 倾向保持（可关闭且结果明确）；如需更严格语义，应用用自定义对话框并省略取消角色 |
| OPEN-W-DIALOG-10 | 对话框底部按钮行与内容区之间是否加分隔线或底部色带（Windows 经典对话框为灰色底带） | 倾向不加，保持扁平（REQ-THEME-004）；M3 评审 |
