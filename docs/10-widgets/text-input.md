# 单行文本框（text-input）

> 本文同时是"文本编辑核心"（下称**编辑核心**）的定义处：光标与选区模型、键位语义、撤销栈、剪贴板净化、输入法组字、横向滚动、光标闪烁。多行文本区（text-area.md）、数值微调框（spin-box.md）、可编辑组合框（combo-box.md）与对话框的输入提示（dialog.md）都引用本文的条款，只写差异。

## 1. 用途

编辑一行文本：名称、路径、搜索词、口令。参照 Windows 的 Edit（`ES_AUTOHSCROLL`，单行）。

- 多行或需要换行符 → 用 text-area。
- 只允许输入数值 → 用 spin-box。
- 从候选项中选择或"输入或选择" → 用 combo-box。
- 只显示、不需要编辑与选择 → 用 label，不要用只读文本框。

值由应用持有：应用传入框架提供的可增长 UTF-8 缓冲 `TextBuf`；框架只保留光标、选区、横向滚动偏移与撤销栈（ADR 0005：重型控件是保留节点，应用持有数据）。

## 2. 解剖

```
        ┌─ 焦点环（仅焦点可见时；文本框恒为焦点可见，REQ-INPUT-040）
┌────────────────────────────────────────────┐
│ [前置图标] 文本区（视口，裁剪）  [无效图标] [×] │   容器 = drawSunken
└────────────────────────────────────────────┘
  └ pad_input_x                          pad_input_x ┘
```

- **容器**：内凹表面，含边框。
- **前置图标**（可选）：位于文本区之前。
- **文本区**：显示文本、选区高亮、光标、组字串；超宽时按横向滚动偏移显示一个视口。
- **占位文字**（可选）：内容为空时显示在文本区。
- **无效图标**（`invalid` 为真时）：错误图标，位于文本区之后。
- **清除按钮**（可选）：`×`，位于最右。

## 3. 度量与布局

| 项 | 取值（令牌） |
|---|---|
| 高度 | `control_h`（`size = .sm` 时 `control_h_sm`，`.lg` 时 `control_h_lg`） |
| 最小宽度 | `button_min_w` |
| 左右内边距 | `pad_input_x`（从容器外缘量起，边框含在内） |
| 前置图标 | `icon_sm`，与文本区间距 `gap_sm` |
| 无效图标 | `icon_sm`，与文本区间距 `gap_sm` |
| 清除按钮 | 命中区为 `icon_md` 见方，垂直居中；其中 `drawMark(.close)` 用 `icon_sm` |
| 文字样式 | `font_body`；占位文字 `font_body` 着色 `text_placeholder` |
| 光标宽度 | 发丝线宽度（REQ-THEME-012） |
| 绘制外延 | `focus_ring_w` |

**REQ-W-TEXTINPUT-001**　默认尺寸策略：主轴 `grow(1)`，交叉轴 `fixed(高度令牌)`；主轴最小值为 `button_min_w`。调用方**可以**经 `layout` 改为 `fixed` 或 `fit`。

**REQ-W-TEXTINPUT-002**　主轴为 `fit` 时的期望宽度 = `max(button_min_w, 2 × pad_input_x + 前置图标宽 + 无效图标宽 + 清除按钮宽 + 各相邻部件间的 gap_sm + 文本宽)`，其中文本宽为缓冲内容（密码模式为圆点串）以 `font_body` 测得的单行宽度（`newlines = .as_space`）；缓冲为空时取占位文字宽度。部件仅在存在时计入。

**REQ-W-TEXTINPUT-003**　文本区**视口**为容器内缩 `pad_input_x`、并扣除前置图标、无效图标与清除按钮（及各自间距）后的横向区间，纵向为整个容器高度；文本在视口内按"行框垂直居中"放置（REQ-THEME-017）。视口恒置裁剪，文本、选区、光标、组字下划线都不得画到视口之外。

**REQ-W-TEXTINPUT-004**　无效图标仅在 `invalid` 为真时出现；清除按钮仅在 `clearable` 为真、缓冲非空、控件启用且非只读、并且（持有焦点或被悬停）时出现。两者出现与否**不得**改变视口的宽度之外的任何布局（容器不变，视口宽度随之变化，并按 REQ-W-TEXTINPUT-019 重新保证光标可见）。

## 4. 变体与参数

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `read_only` | `bool` | `false` | 只读：可聚焦、可选择、可复制，不可修改 |
| `password` | `bool` | `false` | 密码模式 |
| `invalid` | `bool` | `false` | 校验失败标志 |
| `invalid_message` | `?[]const u8` | `null` | 失败说明，作为无效图标的提示框文本与无障碍帮助文本 |
| `placeholder` | `?[]const u8` | `null` | 占位文字 |
| `max_len` | `?u32` | `null` | 最大长度，单位为**字素簇**；`null` 不限 |
| `icon` | `?theme.Icon` | `null` | 前置图标 |
| `clearable` | `bool` | `false` | 显示清除按钮 |
| `clear_label` | `?[]const u8` | `null` | 清除按钮的提示文本与无障碍名称；`null` 时取内建字符串 `Strings.clear`（11） |
| `commit_on_blur` | `bool` | `true` | 失去焦点时若内容自上次提交后有变化则报告 `committed` |
| `commit_unchanged` | `bool` | `true` | Enter 是否在内容无变化时也报告 `committed`（搜索框需要；为假则仅在有变化时报告） |
| `accept` | `?AcceptFn` | `null` | 候选文本过滤，供 spin-box 等派生控件使用（REQ-W-TEXTINPUT-013） |
| `size` | `ControlSize` | `md` | 高度档（类型定义于 button.md） |
| `tooltip` | `?[]const u8` | `null` | 悬停提示 |
| `embed` | `?EmbedSpec` | `null` | 被 spin-box、combo-box 嵌入时使用：右侧让出的宽度、是否由外层绘制容器 |
| `enabled`、`key`、`debug_name`、`layout` | 通用 | | 见模板 |

**REQ-W-TEXTINPUT-005**　值由应用持有，类型为框架提供的 `TextBuf`（见第 12 节）：一个可增长的 UTF-8 缓冲，持有它自己的分配器，对外提供只读切片与 `set`/`replace`/`clear` 修改函数。`TextBuf` 带两个只增计数：`serial`（创建时分配的进程内唯一编号）与 `revision`（每次内容实际改变时加一；`set` 传入与现内容逐字节相同的串时不改变）。控件经 `TextBuf` 的修改函数写入编辑结果；控件**不得**保存 `TextBuf` 的切片跨构建。

**REQ-W-TEXTINPUT-006**　**程序性改值**：控件在每次构建开始记下所见 `TextBuf` 的 `(serial, revision)`。当它与上次编辑结束时控件自己留下的值不同（应用直接改了缓冲，或换了另一个 `TextBuf`），视为程序性改值，**必须**：清空撤销栈与重做栈；把光标与选区的两端各夹紧到不大于缓冲长度的最近字素簇边界（选区两端相等则折叠）；重新保证光标可见（REQ-W-TEXTINPUT-019）；放弃进行中的拖动选择；不报告 `changed`，且把"自上次提交后有变化"标志清除。

**REQ-W-TEXTINPUT-007**　最大长度按**字素簇**计（05 的 `nextGrapheme`），不按字节：一个 emoji 序列、一个"基字加组合符"都算 1。键入、粘贴、输入法提交使结果的簇数超过 `max_len` 时，只插入能容纳的前若干个簇（在字素簇边界截断）；容量为 0 时键入被忽略。选区被替换时容量按"现有簇数 − 选区簇数"计。程序性写入缓冲不受限，但缓冲超限期间键入与粘贴一律被忽略，删除不受影响。

**REQ-W-TEXTINPUT-008**　不论 `max_len`，缓冲总字节数**不得**因用户编辑而超过 `text.max_layout_bytes`（262 144，REQ-TEXT-005）；超出部分同样在字素簇边界截断。应用程序性写入了更长的内容时，控件只排版前 262 144 字节（回退到簇边界），并拒绝一切插入类编辑（删除与导航仍可用），调试构建记录一条 `warn`。

**REQ-W-TEXTINPUT-009**　`read_only` 为真：键盘与鼠标的选择、导航、复制照常；一切会修改缓冲的编辑（键入、删除、剪切、粘贴、撤销、重做、清除按钮、输入法）被忽略，输入法不启用，清除按钮不显示；右键菜单中仅"复制"与"全选"可用。只读文本框**可**聚焦且为 Tab 停靠。外观不同于禁用：文字仍为 `text_primary`，容器仍为 `drawSunken` 常态。

**REQ-W-TEXTINPUT-010**　`password` 为真：(1) 文本区以圆点显示——每个字素簇显示一个 U+2022，圆点数等于簇数，宽度由 `font_body` 的 U+2022 决定；显示串与缓冲之间的偏移映射由控件维护（第 k 个簇对应第 k 个圆点）；(2) Ctrl+C、Ctrl+Insert、Ctrl+X、Shift+Delete 与 `edit.copy`/`edit.cut` 无效，右键菜单的"剪切""复制"禁用，剪贴板内容不被改变；(3) Ctrl+Left/Right、Ctrl+Backspace/Delete 把整个内容视为一个词：分别移到开头/末尾、删到开头/末尾；双击与三击都全选；(4) `ime = false`，输入法不启用（REQ-W-TEXTINPUT-050），`text_input` 仍为真；(5) 占位文字照常显示；(6) 无障碍不暴露值（REQ-W-TEXTINPUT-056）。

**REQ-W-TEXTINPUT-011**　`invalid` 为真：容器以 `drawSunken(..., invalid = true)` 绘制（边框 `status_danger`，REQ-THEME-022），**并且**在文本区右侧显示错误图标（`drawMark(.@"error", icon_sm, status_danger)`，即使 `invalid_message` 为空）——颜色不是唯一的区分手段（REQ-THEME-006）。`invalid_message` 非空时，悬停无效图标显示以它为文本的提示框，并写入无障碍帮助文本。持有焦点时边框仍为 `status_danger`（焦点环照常画在其外）。

**REQ-W-TEXTINPUT-012**　缓冲为空且无组字串时显示占位文字（`text_placeholder`，单行，超宽尾部省略号），持有焦点时也显示，直到出现第一个字符或组字串；占位文字不可选、不参与命中、不计入横向滚动范围。

**REQ-W-TEXTINPUT-013**　`accept` 非空时，每个将被插入的码点（键入、粘贴净化后、输入法提交）按序独立判定：把该码点按当前插入位置并入"替换选区后的结果文本"得到候选文本，调用 `accept(ctx, 候选文本)`，为假则丢弃该码点，继续判定下一个。删除与撤销不经过 `accept`。输入法组字串期间不过滤（显示原样），提交时才过滤。

**REQ-W-TEXTINPUT-014**　缓冲中若含换行（应用程序性写入），按 `newlines = .as_space` 排版（REQ-TEXT-004，每个换行显示为一个空格，偏移仍以缓冲为准）；制表符按 05 的制表位展开；其他控制字符不可见、宽度 0。这些字符仍各占一个字素簇，可被光标跨越与删除。

## 5. 状态

### 5.1 状态机

状态变量：`focus ∈ {无, 有}`；`mode ∈ {空闲, 鼠标选择(字符), 鼠标选择(词), 组字}`；`menu ∈ {关, 开}`。

| 当前 | 事件 | 条件 | 下一状态 | 动作 |
|---|---|---|---|---|
| 无焦点 | 左键按下于文本区 | 启用 | 有焦点 / 鼠标选择(字符 或 词) | 取焦点（原因 `pointer`，不全选）；按 `clicks` 定位光标、选词或全选；隐式捕获 |
| 无焦点 | 焦点获得 | 原因 ∈ {tab, mnemonic, initial, programmatic, transfer} | 有焦点 / 空闲 | 全选；光标置亮 |
| 无焦点 | 焦点获得 | 原因 ∈ {pointer, restore, group} | 有焦点 / 空闲 | 选区与光标保持 |
| 鼠标选择 | `pointer_move` | 指针在视口内 | 同 | 以 `hitTest` 更新光标（词模式按词单位扩展） |
| 鼠标选择 | `pointer_move` / 定时器到期 | 指针在视口左/右外 | 同 | 按距离横向自动滚动，并把光标推到可见边缘（REQ-W-TEXTINPUT-023） |
| 鼠标选择 | 左键释放 / 捕获被取消 | — | 空闲 | 结束选择；选区保持 |
| 空闲 | `ime_start` | 持有焦点、启用输入法 | 组字 | 组字串为空；选区被"虚拟替换" |
| 组字 | `ime_update` | — | 组字 | 更新组字串、片段、组字内光标 |
| 组字 | `ime_commit` | — | 组字 | 在被虚拟替换的选区处插入提交串（一步撤销）；`changed` |
| 组字 | `ime_end` | — | 空闲 | 清除组字状态；无提交时选区原样恢复 |
| 空闲 | 右键按下 | 落在非空选区之外 | 空闲 | 光标移到点击处并折叠选区 |
| 空闲 | 右键释放（`context_menu`）/ Shift+F10 / 菜单键 | — | 空闲 / 菜单开 | 打开右键菜单 |
| 有焦点 | Enter（经 `observes`，不消费） | 非自动重复 | 同 | 报告 `committed`（见 REQ-W-TEXTINPUT-040）；路由继续，所在范围的默认按钮照常被触发 |
| 有焦点 | 失去焦点（`focus_lost`） | 组字中先提交（REQ-INPUT-063） | 无焦点 | 隐藏选区与光标；横向滚动回到行首；若 `commit_on_blur` 且有未提交变化，报告 `committed` |
| 任意 | 窗口失去激活 | — | 同（不变） | 不画焦点环、选区与光标；不提交；组字由平台层取消（REQ-PLAT-055） |
| 任意 | 变为禁用 | — | 无焦点 | 按 REQ-INPUT-050 转移焦点；组字先提交 |

### 5.2 视觉表现

| 状态 | 绘制（基元 + 令牌） |
|---|---|
| 常态 | `drawSunken(R, radius_control, visual, invalid)`；文字 `text_primary`（`font_body`） |
| 悬停 | 边框 `border_control_hover`（`drawSunken` 内建） |
| 持有焦点 | 边框 `accent_mark` + `drawFocusRing`（文本框恒为焦点可见，窗口激活时） |
| 选区（有焦点且窗口活动） | 对 `selectionRects` 的每个矩形 `drawSelection(rect, true)`，选区内文字重绘为 `text_on_accent` |
| 选区（无焦点或窗口非活动） | **不显示**（单行文本框不显示非活动选区） |
| 光标 | 独立的子叶节点：竖线，宽发丝线、高为行高，`text_primary`；闪烁见 REQ-W-TEXTINPUT-017 |
| 组字串 | 文字 `text_primary`，`drawComposition`：`underline` = `text_primary`、`target_underline` = `text_primary`、`error_underline` = `status_danger`、`target_bg` = `surface_row_hover` |
| 占位文字 | `text_placeholder` |
| 只读 | 同常态；光标照常 |
| 禁用 | `drawSunken` 禁用配方；文字 `text_disabled`；无选区、无光标、无占位以外的交互 |
| `invalid` | 见 REQ-W-TEXTINPUT-011 |

**REQ-W-TEXTINPUT-015**　选区高亮在文字之下绘制，选区内文字以 `text_on_accent` 重绘（文字分两段绘制：选区外 `text_primary`，选区内 `text_on_accent`）。选区矩形取自 `layout.selectionRects(start, end, .{}, out)`，被视口裁剪。选区非空时**不**绘制光标。

**REQ-W-TEXTINPUT-016**　光标矩形的 `x`、`y`、`h` 取自 `layout.caretRect`（`x` 已对齐整数 ppx），宽度取发丝线宽度（`Theme.hairline`），颜色 `text_primary`；只在持有焦点、窗口活动、选区为空、且处于"亮"相位时绘制。光标宽度在 200% 缩放下为 2 ppx。

**REQ-W-TEXTINPUT-017**　光标是文本区的一个**独立的子叶节点**（REQ-FRAME-050：需要窄损伤的闪烁元素必须是独立叶节点）：节点矩形 = 光标矩形（宽发丝线、高行高），位置由控件在构建时随光标给出，不参与布局，不可命中。闪烁按 REQ-FRAME-051：控件为该叶节点登记 `ui.timer(caret_id, caret_blink_ms, .paint)`，周期（每个相位的时长）读取系统度量 `SystemMetrics.caret_blink_ms`（03）；该值为 `null` 时光标常亮且**不登记**定时器。定时器仅在"持有焦点、窗口活动、选区为空"时登记。"亮/灭"相位由该叶节点的绘制函数依据本帧时间戳与节点属性中的 `blink_epoch` 计算（`((now − blink_epoch) / caret_blink_ms) 为偶数 → 亮`）。因此闪烁帧是**纯绘制帧**：构建遍数 0，布局不执行，**损伤恰为光标叶节点的矩形**（宽 × 高 = 发丝线宽 × 行高，已为整数 ppx）。

**REQ-W-TEXTINPUT-018**　任何编辑、光标或选区移动（单纯的横向滚动不算）、获得焦点、窗口重新激活之后，光标**必须**立即为"亮"并重新计时：控件把光标叶节点的 `blink_epoch` 置为该帧时间戳并调用 `ui.timerRestart(caret_id)`（REQ-FRAME-050），之后第一次翻转在 `caret_blink_ms` 之后。窗口非活动时光标不显示、不登记定时器（09 第 5 节）。

**REQ-W-TEXTINPUT-019**　**横向滚动**：文本总宽（含组字串）不超过视口宽时偏移恒为 0。超过时，每次构建在编辑、光标移动、选区扩展、组字更新、视口宽度变化之后保证光标矩形可见：令光标在文本坐标系中的 `x` 为 `cx`，边距 `m = gap_sm`（换算为 ppx），若 `cx − 偏移 < m` 则偏移 = `cx − m`；若 `cx + 光标宽 − 偏移 > 视口宽 − m` 则偏移 = `cx + 光标宽 + m − 视口宽`；否则不动（最小位移）；最后夹紧到 `[0, max(0, 文本宽 + 光标宽 − 视口宽)]`。偏移以**整数 ppx**保存，使文字与光标始终对齐物理像素。此外：失去焦点时横向滚动偏移回到 0（显示行首）；保留的光标与选区不变。重新获得焦点时按 REQ-W-TEXTINPUT-019 重新求偏移。窗口失去激活但焦点仍在时偏移不变。

## 6. 鼠标行为

文本区登记指针兴趣 `click`、`drag`、`context`；指针形状为 I 形（`ibeam`，REQ-THEME-032）。

**REQ-W-TEXTINPUT-020**　左键在文本区按下：若按下事件的 `clicks` 为 1，取 `layout.hitTest` 在文本坐标（视口坐标加偏移）上的 `caret.offset`，把光标与选区锚点都置于该偏移（选区折叠）；密码模式下命中的是圆点串，按簇序号映射回缓冲偏移。按下即生效，不等释放。点击聚焦不全选（REQ-W-TEXTINPUT-047）。

**REQ-W-TEXTINPUT-021**　按住 Shift 左键按下（`clicks` 为 1）：保持选区锚点不变，把光标移到命中偏移，选区为锚点与光标之间。若原选区为空，锚点为按下前的光标位置。

**REQ-W-TEXTINPUT-022**　左键按下后拖动：控件持有隐式捕获（REQ-INPUT-013），每次 `pointer_move` 以指针的 x 做 `hitTest`，把光标（选区的活动端）移到命中偏移，锚点不变；指针的 y 不影响结果（单行）。释放后选区保持。拖动选择不需要越过系统拖拽阈值才开始（选择从按下即开始，按下点即锚点）。

**REQ-W-TEXTINPUT-023**　拖动选择时指针在视口左侧或右侧之外，令超出距离为 `d`（lpx，> 0）：控件登记一个 `build` 级定时器，节拍取令牌 `dur_autoscroll`（50 ms，09）；每次到期把横向偏移向该侧移动 `min(d, 视口宽 / 2)` lpx（至少 1 ppx，换算为整数 ppx），并把光标推到该侧可见边缘处的命中偏移；指针静止在视口外时到期照常滚动，直到偏移到达边界。指针回到视口内或释放时取消定时器。鼠标选择进行期间，REQ-W-TEXTINPUT-019 的"保证光标可见"暂停，横向偏移只由自动滚动改变；释放时再保证光标可见。

**REQ-W-TEXTINPUT-024**　`clicks` 为 2（双击）：选中包含命中偏移的词单元（`text.wordRange`，REQ-TEXT-022），锚点为词起点、光标为词终点；空白也可被选中，不附带尾随空白。此后不释放而拖动：选区按**词单元**扩展——并集于初始词与指针所在词，向右拖时光标在指针所在词的终点，向左拖时光标在指针所在词的起点，锚点保持在初始词的相应另一端。密码模式双击全选。

**REQ-W-TEXTINPUT-025**　`clicks` 为 3（三击）：全选（单行文本框的"段"就是全部内容）。第 4 次按下重新计为 1（REQ-INPUT-016）。

**REQ-W-TEXTINPUT-026**　右键按下：若命中偏移落在非空选区的字节范围 `[start, end)` 内（含起点、不含终点；且该点位于选区高亮矩形内），不改变选区与光标；否则把光标移到命中偏移并折叠选区。无论哪种，右键按下都使文本框取得焦点（REQ-INPUT-022，不全选）。右键**释放**时（`context_menu` 请求，REQ-INPUT-018）打开上下文菜单，位置为请求的 `pos`。

**REQ-W-TEXTINPUT-027**　上下文菜单（menu.md 的 `PopupKind.context_menu`）依次为：撤销、分隔线、剪切、复制、粘贴、删除、分隔线、全选；文案取 11 的内建字符串表 `Strings.edit_undo/…/edit_select_all`，快捷键文本取标准编辑命令当前绑定（`edit.undo` 等，REQ-APP-029）。各项启用状态：撤销 = 撤销栈非空且可编辑；剪切 = 选区非空且可编辑且非密码；复制 = 选区非空且非密码；粘贴 = 可编辑且 `platform.clipboard.hasText()`；删除 = 选区非空且可编辑；全选 = 缓冲非空且选区不是全部内容。点击某项执行与对应键位相同的操作后关闭菜单，焦点留在文本框。键盘（Shift+F10、菜单键）触发时位置为光标矩形的左下角（控件据 REQ-INPUT-018 调整），且菜单的第一个启用项被高亮。

**REQ-W-TEXTINPUT-028**　滚轮事件不处理，按 REQ-INPUT-019 冒泡（`WheelCaps` 全空）。中键按下与释放不改变光标、选区或焦点之外的任何状态（不做中键粘贴、不做自动滚动）。

**REQ-W-TEXTINPUT-029**　清除按钮是独立节点，登记 `click`、不可聚焦、`take_focus_on_click = false`，指针形状为箭头，带提示框与无障碍名称 `clear_label`（缺省取 `Strings.clear`）。左键在其上释放时：把缓冲整体替换为空（一步撤销，REQ-W-TEXTINPUT-043 的"独立步"），光标置 0，使文本框取得焦点（若尚未持有；不触发全选），报告 `changed`；若 `commit_on_blur` 则下次失焦或 Enter 时报告 `committed`。按下于其上不改变文本框的选区。

**REQ-W-TEXTINPUT-030**　不支持把选中文本拖出或拖入（选区内按下后拖动是重新选择，不是拖放）；外部 OLE 拖入文本不接受。见待定问题。

## 7. 键盘行为

下表"有选区"指选区非空。`锚点`为选区固定端，`光标`为活动端；移动类键在**无 Shift** 时折叠选区，**有 Shift** 时只移动光标、锚点不变。"按词"取 `text.nextWord`/`text.prevWord`（REQ-TEXT-022），"按簇"取 `text.nextGrapheme`/`text.prevGrapheme`（REQ-TEXT-021）。

| 键 | 行为 |
|---|---|
| ← / → | 无选区：光标按簇左/右移一个；有选区：折叠到选区**起点**（←）/ **终点**（→），光标不再多移 |
| Ctrl+← / Ctrl+→ | 从光标起按词移到上一/下一个词起点（`prevWord`/`nextWord`），折叠选区 |
| Home / End（含 Ctrl+Home / Ctrl+End） | 光标移到 0 / 缓冲末尾，折叠选区（单行下 Ctrl 无区别） |
| Shift + 上述各键 | 同上移动光标但不折叠，选区为锚点到光标 |
| Ctrl+A | 全选：锚点 0、光标末尾 |
| Backspace | 有选区：删除选区；否则向前删一个簇（组合序列规则见 REQ-W-TEXTINPUT-034） |
| Delete | 有选区：删除选区；否则向后删一个簇 |
| Ctrl+Backspace | 有选区：删除选区；否则删到上一个词起点（`prevWord`） |
| Ctrl+Delete | 有选区：删除选区；否则删到下一个词起点（`nextWord`，含其间的空白） |
| Ctrl+C / Ctrl+Insert | 复制选区 |
| Ctrl+X / Shift+Delete | 剪切选区 |
| Ctrl+V / Shift+Insert | 粘贴 |
| Ctrl+Z | 撤销 |
| Ctrl+Y / Ctrl+Shift+Z | 重做 |
| Enter | 观察而不消费：报告 `committed`，不插入任何字符；键继续向后级传递，所在范围有默认按钮时触发之（REQ-INPUT-034） |
| 字符键 | 在光标处插入（有选区则替换选区） |
| Esc | 不处理（冒泡，触发所在范围的取消按钮，REQ-INPUT-034）；组字期间由输入法处理 |
| Tab / Shift+Tab | 不处理（焦点导航，REQ-INPUT-035） |
| Insert（单独） | 不处理；**不支持改写模式** |
| Shift+F10、菜单键 | 框架内建，打开上下文菜单（REQ-INPUT-018） |
| 其他带 Ctrl/Alt 的组合 | 不属于预占范围的继续向后级传递 |

**REQ-W-TEXTINPUT-031**　控件经 `InteractOpts` 声明键位（路由第 ③ 级，REQ-INPUT-028；`KeyGroups` 只匹配无修饰或仅带 Shift 的键，Ctrl/Alt 组合须在 `extra` 逐个列出）。**预占**（`preempt`）：`groups.printable = true`（字符键，含 Shift 层与 AltGr 层，REQ-INPUT-031 的精确定义）、`groups.home_end`、`groups.backspace_delete`；`extra` 逐个列出——←、→ 各自与 {无修饰, Shift, Ctrl, Ctrl+Shift}；Ctrl+Home、Ctrl+End 及其 Shift 变体；Ctrl+Backspace、Ctrl+Delete；Ctrl+A、Ctrl+C、Ctrl+V、Ctrl+X、Ctrl+Z、Ctrl+Y、Ctrl+Shift+Z、Ctrl+Insert、Shift+Insert、Shift+Delete。**观察**（`observes`）：无修饰的 Enter（REQ-W-TEXTINPUT-040）。表外的键（Alt+←、Ctrl+Alt+Home、↑、↓、PageUp、PageDown、Ctrl+PageUp/PageDown、Esc、Tab、单独的 Insert、功能键）不被预占，继续向后级传递。`text_input = true`（文本输入类：焦点环恒显示、`char` 投递），`ime` 在可编辑且非密码时为 `true`，密码与只读模式为 `false`（输入法不启用，REQ-W-TEXTINPUT-050）。此外：Esc、Tab、Shift+Tab、单独的 Insert 不被控件预占或声明处理，按 08 的路由继续向后级传递：Esc 触发所在范围的取消按钮（REQ-INPUT-034），Tab 移动焦点；Insert 被丢弃。**不**提供改写（覆盖）模式，也没有改写光标。

**REQ-W-TEXTINPUT-032**　移动类键的语义如上表：折叠规则（无 Shift 时 ←/→ 折叠到选区相应端且**不**再移动）、按词移动、Home/End。自动重复的移动键照常重复生效。所有移动之后：光标亲和性恒为 `downstream`（单行无软换行）；按 REQ-W-TEXTINPUT-018 重置闪烁；按 REQ-W-TEXTINPUT-019 保证光标可见；并结束当前撤销合并（REQ-W-TEXTINPUT-043）。此外：Shift 加移动键只移动光标：`Shift+←/→` 按簇，`Shift+Ctrl+←/→` 按词，`Shift+Home/End` 到两端；锚点不变，光标与锚点重合时选区为空。

**REQ-W-TEXTINPUT-033**　Ctrl+A 与 `edit.select_all`：锚点置 0、光标置缓冲末尾；缓冲为空时无效果；不改变内容，不进入撤销栈。

**REQ-W-TEXTINPUT-034**　Backspace 无选区时的删除单位（05 的待定 TEXT-OPEN-02 在此定稿）：令 `p = prevGrapheme(光标)`，被考察簇为 `[p, 光标)`。若该簇含不止一个码点，且其**最后一个码点**的 Grapheme_Cluster_Break 属性为 Extend（组合符），而簇内**不含** U+200D（ZWJ）、U+FE0F（emoji 呈现选择符）、U+20E3（键帽）、emoji 肤色修饰符（U+1F3FB–U+1F3FF）、区域指示符（U+1F1E6–U+1F1FF）、emoji 标签序列的 tag 字符（U+E0020–U+E007F，如英格兰、苏格兰等子区域旗帜）——即它是"基字加组合符"——则只删除最后一个码点；其余一律删除整个簇（emoji ZWJ 序列、旗帜含子区域旗帜、键帽、带肤色的 emoji、韩文音节都整体删除）。光标在 0 时无效果。此外：Delete 无选区时向后删除整个字素簇（任何簇都整体删除，不拆分组合符）；光标在末尾时无效果。

**REQ-W-TEXTINPUT-035**　Ctrl+Backspace 无选区时删除 `[prevWord(光标), 光标)`，Ctrl+Delete 无选区时删除 `[光标, nextWord(光标))`；有选区时两者都只删除选区。词边界遵循 REQ-TEXT-022（汉字逐字，故中文下一次删一个字，其后的空白一并删除）。

**REQ-W-TEXTINPUT-036**　每个删除/插入类编辑完成后：光标置于编辑点，选区折叠，结果入撤销栈（REQ-W-TEXTINPUT-043），置"自上次提交后有变化"，向应用报告 `changed`，并按 REQ-W-TEXTINPUT-019、REQ-W-TEXTINPUT-018 处理。一次编辑未使缓冲内容实际改变（如光标在 0 处 Backspace）时不报告 `changed`、不入栈。

**REQ-W-TEXTINPUT-037**　字符键（`char` 事件）：码点为控制字符（U+0000–U+001F、U+007F、U+0080–U+009F）时忽略；否则经 `accept`（若有）、`max_len` 与字节上限判定后，在光标处插入，有选区则替换选区（整个替换作为一步撤销，其后同光标处的连续键入合并进该步）。组字期间不收到 `char`（REQ-INPUT-026）。`char` 事件按到达顺序逐个处理。

**REQ-W-TEXTINPUT-038**　Ctrl+C / Ctrl+Insert：选区非空且非密码时把选区文本写入 `platform.clipboard.setText`（缓冲中的换行按 03 的规则转换），不改变缓冲；选区为空时无效果，**不**改动剪贴板。Ctrl+X / Shift+Delete：先复制，写入成功后再删除选区（一步撤销）；剪贴板写入失败（`ClipboardBusy`）时不删除，调试构建记录 `warn`。Ctrl+V / Shift+Insert：读取 `getText`，按 REQ-W-TEXTINPUT-039 净化后替换选区（一步撤销，不与前后合并）；剪贴板无文本或净化后为空时无效果。此外：剪贴板读写经 03 的 `platform.clipboard`（`getText`、`setText`、`hasText`）。读写中的 `error.ClipboardBusy` 使该次操作无效果（不弹错误提示），调试构建记录 `warn`。粘贴内容的净化见 REQ-W-TEXTINPUT-039；复制内容为缓冲中选区的原始字节（含程序性写入的换行）。

**REQ-W-TEXTINPUT-039**　**粘贴净化**：对剪贴板文本按序：(1) 每个换行（`\n`；亦含 U+0085、U+2028、U+2029）替换为一个空格；(2) 删除其余控制字符（U+0000–U+001F 含制表符、U+007F、U+0080–U+009F）；(3) 非法 UTF-8 序列按 REQ-TEXT-003 以 U+FFFD 替代；(4) 经 `accept` 逐码点判定；(5) 按 `max_len` 与字节上限在字素簇边界截断。输入法提交串经过相同的 (1)–(5)。

**REQ-W-TEXTINPUT-040**　**Enter 经 `observes` 观察、不消费**：控件在 `InteractOpts.observes` 中声明无修饰的 Enter（不进入 `preempt`，REQ-INPUT-028）。Enter 按下（非自动重复）时，控件在收件列表中看到该键，报告 `committed`（`commit_unchanged` 为真时总是；为假时仅当"自上次提交后有变化"），清除该标志，**不**插入字符；同时该键**照常继续**向后级传递：焦点所在范围有默认按钮时触发它（第 ⑦ 级，`activated = .default_button`），无则被丢弃。因此对话框里的文本框按 Enter 既报告 `committed` 又触发默认按钮（与 button.md 的 AC-W-BUTTON-007 一致）；自动重复的 Enter 被控件忽略（也不触发默认按钮，REQ-INPUT-032）。

**REQ-W-TEXTINPUT-041**　控件在 `InteractOpts.edit`（`EditCaps`）中如实声明当前能力：`undo`/`redo` = 对应栈非空且可编辑，`cut` = 选区非空且可编辑且非密码，`copy` = 选区非空且非密码，`paste` = 可编辑且剪贴板有文本，`delete` = 选区非空且可编辑，`select_all` = 缓冲非空。收到 `edit_command` 事件（来自菜单、工具栏等，REQ-APP-030）时执行与对应键位完全相同的操作。

**撤销栈**

**REQ-W-TEXTINPUT-042**　撤销栈的每一步记录一次编辑：`{ 起点, 被删除的字节, 插入的字节, 编辑前光标与选区, 编辑后光标 }`。Ctrl+Z 撤销栈顶一步：恢复被删除的内容、移除插入的内容，光标与选区恢复为**编辑前**的状态；该步移入重做栈。Ctrl+Y/Ctrl+Shift+Z 重做重做栈顶一步，光标置于编辑后位置。任何新的编辑清空重做栈。撤销与重做报告 `changed`，不重置"自上次提交后有变化"标志。

**REQ-W-TEXTINPUT-043**　**操作合并**：同时满足下列条件的编辑并入栈顶步，而不新开一步——(a) 都是键入字符，且新字符插入在栈顶步插入内容的末尾紧邻处；或都是 Backspace，且删除点紧邻栈顶步的删除起点之前；或都是 Delete，且删除点与栈顶步相同；(b) 上一次编辑与本次之间没有光标或选区的移动（键盘或鼠标）；(c) 两次编辑的时间间隔不超过 `undo_merge_pause`（暂定 1000 ms，见 OPEN-W-TEXTINPUT-01）；(d) 栈顶步不是粘贴、剪切、输入法提交、清除按钮、替换选区的键入或程序性操作产生的"独立步"。下列情形**断开**合并（下一次编辑新开一步）：光标或选区移动、删除方向改变（Backspace ↔ Delete）、键入与删除互换、粘贴、剪切、输入法提交、清除、停顿超时、失去焦点。替换选区的键入本身是独立步，其后在同一光标处的连续键入并入该步。

**REQ-W-TEXTINPUT-044**　撤销栈容量上限为 `undo_max_steps = 256` 步，且各步所存字节（被删除加插入）合计不超过 `undo_max_bytes = 256 KiB`；超限时丢弃最旧的步。单步字节数本身超过 `undo_max_bytes` 时该步不入栈且撤销栈被清空（如粘贴一个超大文本）。重做栈随新编辑清空。

**REQ-W-TEXTINPUT-045**　撤销栈与重做栈属于 `sticky` 保留状态（REQ-FRAME-010）：文本框暂时不被声明（如切换到别的标签页）后再声明，撤销历史仍在；被 LRU 回收后清空。失去焦点**不**清空撤销栈。

## 8. 焦点

**REQ-W-TEXTINPUT-046**　文本框可聚焦且为 Tab 停靠（`tab_stop = true`），`take_focus_on_click = true`；禁用的文本框不可聚焦。只读文本框可聚焦。控件**恒**声明 `InteractOpts.text_input = true`（文本输入类：焦点环恒显示、`char` 投递，REQ-INPUT-040），密码与只读模式另声明 `ime = false` 以禁用输入法（REQ-INPUT-062）；不需要控件自行判定焦点可见。

**REQ-W-TEXTINPUT-047**　因 `tab`、`mnemonic`、`initial`、`programmatic`、`transfer` 原因获得焦点（`focus_gained`）时**全选**（锚点 0、光标末尾）；因 `pointer`（鼠标点击）获得焦点时**不**全选，光标与选区由该次点击决定；因 `restore`（窗口重新激活）或 `group` 获得焦点时选区与光标保持不变。此外：鼠标点击进入时，首次按下既取得焦点又按 REQ-W-TEXTINPUT-020 定位光标；双击、三击在已持有焦点时同样生效。

**REQ-W-TEXTINPUT-048**　失去焦点（`focus_lost`）时：隐藏选区高亮与光标（单行文本框不显示非活动选区）；横向滚动回到行首（REQ-W-TEXTINPUT-019）；组字中则先提交（REQ-INPUT-063）；`commit_on_blur` 为真且"自上次提交后有变化"时报告 `committed` 并清除该标志。窗口失去激活而焦点仍在时，焦点节点被记住，不视为失去焦点，不报告 `committed`。

**REQ-W-TEXTINPUT-049**　"自上次提交后有变化"标志：任何用户编辑（含撤销、重做、清除按钮、输入法提交）置位；`committed`（Enter 或失焦）与程序性改值（REQ-W-TEXTINPUT-006）清除。内容与上次提交时相同（如键入后又删回）仍视为有变化，不做内容比较。

## 9. 文本与输入法

**REQ-W-TEXTINPUT-050**　`text_input = true` 且 `ime` 不为假时框架在获得焦点时启用输入法（REQ-INPUT-062）。密码模式与只读模式声明 `ime = false`，输入法不启用，但仍是文本输入类。

**REQ-W-TEXTINPUT-051**　**组字**：收到 `ime_update` 时控件在**显示**文本中临时插入组字串（REQ-TEXT-039）：显示文本 = 缓冲在选区起点之前的部分 + 组字串 + 缓冲在选区终点之后的部分；缓冲本身在组字期间**不被修改**，不报告 `changed`。组字串以 `text_primary` 绘制，并用 `text.drawComposition` 画下划线与目标子句底色（颜色按 5.2 节）；组字内光标（`ime_update.cursor`）处绘制光标。

**REQ-W-TEXTINPUT-052**　**组字期间选区被替换的规则**：选区非空时，组字串显示为替换选区——选区的内容与高亮在组字期间不显示（视为被虚拟删除）；提交时以提交串替换该选区（一步撤销，独立步）；**取消**（`ime_end` 之前没有 `ime_commit`）时缓冲与选区原样恢复，无任何撤销栈变化（REQ-INPUT-063 的"恢复到组字前的内容由控件负责"在此成立）。选区为空时组字串插入光标处。

**REQ-W-TEXTINPUT-053**　`ime_commit{text}`：提交串经 REQ-W-TEXTINPUT-039 的 (1)–(5) 处理后，替换被虚拟删除的选区（或插入光标处），光标置于插入内容之后，报告 `changed`；随后的 `ime_update`（同一消息内可能紧随）开始新的组字。提交串的长度受 `max_len` 与字节上限截断。无组字状态时到达的 `ime_commit` 同样处理。

**REQ-W-TEXTINPUT-054**　控件**每次构建**（持有焦点时，不论是否在组字）调用 `ui.imeCaret(id, caret, exclude)`（REQ-INPUT-062）：`caret` 为组字内光标处（无组字时为编辑光标）相对节点的光标矩形（含视口偏移与横向滚动，取自 `layout.imeRects`/`caretRect`），`exclude` 为目标子句的第一个矩形（无则 `null`）。滚动、窗口移动、DPI 变化后的重新报告由框架负责。

**REQ-W-TEXTINPUT-055**　焦点即将离开组字中的文本框时按 REQ-INPUT-063 先提交：控件先后收到 `ime_commit`、`ime_end`，把提交串写入缓冲后才失去焦点；因 Tab 在组字期间被输入法拦截（REQ-INPUT-026），不存在 Tab 引起的失焦。`ime_end` 之外不得认为组字已结束。

## 10. 动效

| 属性 | 触发 | 时长令牌 | 缓动 | 影响级别 |
|---|---|---|---|---|
| 容器边框（常态 ↔ 悬停） | 悬停变化 | `dur_fast` | `ease_out` | paint（`Visual.hover_t`） |
| 焦点环 | 焦点变为可见 | `dur_fast` 淡入，消失瞬时 | `ease_out` | paint（`Visual.focus_t`） |
| 光标 | 闪烁 | 无（按系统光标闪烁周期整相位翻转，不渐变） | — | paint（定时器） |
| 选区高亮 | 选区变化 | 无（瞬时） | — | build |

文本框没有自有动画槽；横向滚动是瞬时的（不做平滑滚动）。

## 11. 无障碍

| 项 | 值 |
|---|---|
| UIA 控件类型 | Edit |
| 名称来源 | 紧邻其前的 label（经 `focus_next` 助记符关联）或调用方给出的无障碍名称；无则取 `placeholder` |
| 支持的模式 | Value、Text |
| 状态属性 | IsEnabled、HasKeyboardFocus、IsPassword、ValueIsReadOnly、HelpText（取 `invalid_message`）、IsRequiredForForm（不适用） |

**REQ-W-TEXTINPUT-056**　**Value 模式**：`Value` 为缓冲全文；`IsReadOnly` = `read_only` 或禁用；经 `SetValue` 设置时等同于应用程序性改值经 `TextBuf.set`（清空撤销栈，报告 `changed`，次帧生效）。密码模式 `IsPassword` 为真且 `Value` 返回空串（不暴露内容）。此外：**Text 模式**：文档范围为整个缓冲；支持当前选区（`GetSelection`，为空时为光标处的退化范围）、可见范围（视口内的字素簇区间）、按字素簇/词/行移动文本范围，`GetBoundingRectangles` 取自 `layout.selectionRects` 加节点绝对位置；`Select`/`ScrollIntoView` 经 `setSelection` 延迟生效。密码模式不提供 Text 模式。

## 12. API 草案

```zig
// 草案：仅签名
/// 框架提供的可增长 UTF-8 缓冲，值由应用持有（应用自己的结构里放一个 TextBuf）。
pub const TextBuf = struct {
    pub fn init(allocator: std.mem.Allocator) TextBuf;
    pub fn initFrom(allocator: std.mem.Allocator, bytes: []const u8) error{OutOfMemory}!TextBuf;
    pub fn deinit(self: *TextBuf) void;
    pub fn slice(self: *const TextBuf) []const u8;          // 至下次修改前有效
    pub fn len(self: *const TextBuf) usize;
    pub fn set(self: *TextBuf, bytes: []const u8) error{OutOfMemory}!void;       // 程序性整体改值；内容相同则 revision 不变
    pub fn replace(self: *TextBuf, start: usize, end: usize, bytes: []const u8) error{OutOfMemory}!void;
    pub fn clear(self: *TextBuf) void;
    pub fn serial(self: *const TextBuf) u64;                 // 创建时分配，进程内唯一
    pub fn revision(self: *const TextBuf) u32;               // 内容每次实际改变加一
};

pub const AcceptFn = *const fn (ctx: ?*const anyopaque, candidate: []const u8) bool;
pub const EmbedSpec = struct {
    reserve_right: f32 = 0,       // lpx，视口右侧让给外层控件的宽度
    frame_owner: bool = false,    // 为真时容器由外层绘制，本控件只画文本区
};

pub const TextInputOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    read_only: bool = false,
    password: bool = false,
    invalid: bool = false,
    invalid_message: ?[]const u8 = null,   // 借用至本帧结束
    placeholder: ?[]const u8 = null,       // 借用至本帧结束
    max_len: ?u32 = null,                  // 字素簇
    icon: ?theme.Icon = null,
    clearable: bool = false,
    clear_label: ?[]const u8 = null,       // null = Strings.clear
    commit_on_blur: bool = true,
    commit_unchanged: bool = true,         // Enter 在内容无变化时是否也报告 committed
    accept: ?AcceptFn = null,
    accept_ctx: ?*const anyopaque = null,  // 须在本次构建期间存活
    size: ControlSize = .md,               // 定义于 button.md
    tooltip: ?[]const u8 = null,
    embed: ?EmbedSpec = null,
    layout: layout.ItemOptions = .{},
};

pub const TextInputResult = struct {
    id: WidgetId,
    // 持续性状态
    hovered: bool,
    focused: bool,
    composing: bool,
    selection: text.Range,    // 只读，已按 start ≤ end 排好；无焦点时为保留值
    caret: u32,               // 活动端的字节偏移
    // 激活类结果（触发同帧第二构建遍，REQ-FRAME-030）
    changed: bool,            // 内容被用户编辑改变（含撤销、重做、清除、输入法提交）
    committed: bool,          // Enter（经 observes 观察，不消费）或失去焦点（commit_on_blur）
};

/// buf 由应用持有，须在控件被声明的整个期间存活；控件在第一构建遍内把编辑写入 buf。
pub fn textInput(ui: *Ui, src: std.builtin.SourceLocation, buf: *TextBuf, opts: TextInputOptions) TextInputResult;

/// 程序性设置选区与光标，在本次构建完成后生效；偏移被夹紧到合法簇边界。不清空撤销栈。
pub fn textInputSetSelection(ui: *Ui, id: WidgetId, anchor: u32, caret: u32) void;
```

`changed`、`committed` 是激活类结果；其余为持续性状态。第二构建遍中 `changed`/`committed` 为假，但缓冲已含本帧的编辑结果。

## 13. 保留状态

| 字段 | 类型 | 保留级别 | 说明 |
|---|---|---|---|
| `anchor`、`caret` | `u32` | sticky | 选区锚点与光标，字节偏移，恒在字素簇边界 |
| `scroll_x` | `i32`（ppx） | sticky | 横向滚动偏移 |
| `undo`、`redo` | 步序列（`{start, removed, inserted, sel_before, caret_after}`） | sticky（保留节点，持有自己的分配器） | 撤销与重做栈，容量见 REQ-W-TEXTINPUT-044 |
| `merge` | `{kind, last_time_ms, last_end}` | sticky | 当前可合并的栈顶步信息 |
| `seen_serial`、`seen_revision` | `u64`、`u32` | sticky | 上次编辑结束时所见缓冲的标识，用于识别程序性改值 |
| `dirty_since_commit` | `bool` | sticky | REQ-W-TEXTINPUT-049 |
| `blink_epoch` | `u64`（ms） | transient（属于光标叶节点） | 光标闪烁相位起点，随 `ui.timerRestart` 重置 |
| `comp` | `{text, cursor, segments}` | transient | 组字状态；组字串存于帧竞技场 |
| `drag` | `{mode, word_anchor}` | transient | 鼠标选择的方式与词模式的初始词 |
| `autoscroll` | `{dir, d}` | transient | 拖动选择时的自动滚动方向与距离 |

悬停、聚焦与过渡进度是框架内建状态（REQ-FRAME-013），无需槽。鼠标选择的捕获即框架捕获状态。

## 14. 失效规则

**REQ-W-TEXTINPUT-057**　绘制键**必须**由以下各项构成：缓冲内容的哈希（密码模式为簇数）、锚点与光标偏移、横向滚动偏移、组字串与其片段、`placeholder`、`read_only`、`password`、`invalid`、`enabled`、`size`、`icon`、`clearable`（及清除按钮是否出现）、有焦点、窗口是否活动、焦点可见。**不含**光标亮灭相位（相位由绘制函数据 `blink_epoch` 与帧时间戳计算）。布局输入的内容度量键由缓冲内容（或占位）、字体样式、`size`、图标与清除按钮是否存在构成。

| 变化 | 置脏级别 | 损伤范围 |
|---|---|---|
| 悬停进入/离开、焦点环显隐 | `paint` | 文本框绘制范围（含外延） |
| 光标闪烁翻转（光标叶节点的 `paint` 级定时器） | `paint` | 光标叶节点矩形（发丝线宽 × 行高） |
| 键入、删除、粘贴、撤销（经收件列表） | `build` | 文本框矩形；若期望宽度因 `fit` 改变则含受影响的兄弟 |
| 选区移动（键盘或鼠标） | `build` | 新旧选区与光标所在的文本区矩形 |
| 拖动选择时的自动滚动定时器 | `build` | 文本区矩形 |
| 组字更新 | `build` | 文本框矩形 |
| 程序性改值（应用 `invalidate(.build)`） | `build` | 文本框矩形；内容哈希不变时损伤为空 |

**REQ-W-TEXTINPUT-058**　仅光标闪烁产生的帧**必须**是纯绘制帧：构建遍数 0，布局不执行，被绘制的节点只有光标叶节点及与损伤相交的祖先背景，**损伤面积恰为光标叶节点矩形的面积**（发丝线宽 × 行高，缩放 1.0 时为 1×16 = 16 ppx²）；该帧的 `time.frame_cpu` 满足 REQ-PERF-018（P99 ≤ 0.1 ms）。此外：仅悬停进入/离开文本框所产生的帧**必须**是纯绘制帧，损伤不超出文本框的绘制范围；同一参数的重复 `invalidate(.build)` 不产生损伤、不提交（REQ-FRAME-043）。

## 15. 边界与错误情况

| 情况 | 规定 |
|---|---|
| 缓冲为空 | 显示占位（若有）；Backspace/Delete/Ctrl+C/X 无效果；光标在 0；全选无效果 |
| 缓冲含非法 UTF-8 | 按 REQ-TEXT-003 显示为 U+FFFD；每个最大非法子序列为一个簇，可被光标跨越与删除；复制得到原始字节 |
| 超长缓冲（> 262 144 字节） | REQ-W-TEXTINPUT-008 |
| 应用在构建中途改缓冲 | 视为程序性改值，下一次构建开始时识别（REQ-W-TEXTINPUT-006） |
| 缓冲分配失败（`OutOfMemory`） | 该次编辑被放弃，缓冲与撤销栈不变，不报告 `changed`，记录一条 `warn` |
| 控件宽度小于 `button_min_w`（外部约束压缩） | 视口宽度夹紧到 ≥ 0；光标保持可见规则在视口宽 < 2 × `gap_sm` 时退化为让光标左对齐 |
| 视口宽度为 0 | 不绘制文本与光标；编辑与导航仍按缓冲进行 |
| 禁用中途发生 | 立即显示禁用外观；按 REQ-INPUT-050 转移焦点，组字先提交；进行中的拖动选择被取消（REQ-INPUT-024） |
| 按下期间控件消失 | 捕获释放，选择结束；组字中的提交丢弃（REQ-INPUT-063） |
| 窗口失去激活 | 选区、光标、焦点环不画；不提交 `committed`；重新激活后恢复（REQ-INPUT-041），原因 `restore` 不全选 |
| 控件失去声明（不再出现在构建中） | 有未提交变化时**不**报告 `committed`（应用在移除前自行读取缓冲）；撤销栈随 `sticky` 规则保留 |
| 系统不闪烁光标（`caret_blink_ms = null`） | 光标常亮，不登记定时器 |
| 缩放 125%/150%/175% | 光标宽取发丝线（1 ppx），`x` 对齐整数 ppx；选区矩形对齐整数 ppx（REQ-TEXT-020） |
| 包含 RTL 运行的文本 | 光标左右移动按逻辑顺序步进（REQ-TEXT-024 现状，TEXT-OPEN-01 未定）；选区可由多个矩形组成 |
| `max_len` 为 0 | 任何插入被忽略；允许删除 |
| 清除按钮出现时视口变窄 | 光标可见规则重新求值 |
| 同一帧内同时有 Enter 与失焦 | `committed` 只报告一次 |

## 16. 验收标准

**夹具 F-TI**（除特别注明外）：行高取 `font_body` 的令牌行高 16（REQ-THEME-016，`round(12 × 4/3)`），与 fixed 后端的自然行高无关；行框、光标高度、选区高度都等于 16；无头、`fixed` 文本后端（REQ-TEXT-038：每个字素簇宽 6 px，行高 16 px）、缩放 1.0、B = 12 lpx；窗口客户区 400×200；文本框 `@T` 位于 (100, 100)、200×24、无图标（视口 x ∈ [106, 294]，即簇 k 占 [106 + 6k, 112 + 6k)，光标 x = 106 + 6k − 偏移，竖向光标矩形 y = 104、高 16）；`caret_blink_ms` = 500；假剪贴板为空；`double_click_ms` = 500。回放中，`按 X` 表示该键（及其修饰键）的按下与释放，如"按 Ctrl+→"即 `key down VK_CONTROL`、`key down VK_RIGHT`、`key up VK_RIGHT`、`key up VK_CONTROL`；坐标均为客户区 lpx；点击 `(x, 112)` 命中簇 k 前半（x = 106 + 6k + 1）得光标 k，命中后半（x = 106 + 6k + 4）得光标 k + 1；"选区 (a, b)" 指 `TextInputResult.selection`，"光标 c" 指 `caret`；偏移均为字节。

**AC-W-TEXTINPUT-001**　`[金图]` 覆盖：REQ-W-TEXTINPUT-001、REQ-W-TEXTINPUT-003、REQ-W-TEXTINPUT-011、REQ-W-TEXTINPUT-012、REQ-W-TEXTINPUT-010、REQ-W-TEXTINPUT-009、REQ-W-TEXTINPUT-015。状态矩阵：{常态, 悬停, 持有焦点（含焦点环）, 持有焦点且选区非空, 无焦点但选区保留, 只读, 禁用, `invalid`（带与不带 `invalid_message`）, 占位文字, 密码, 前置图标 + 清除按钮, 窗口非活动} × 浅/深/高对比度 × 缩放 1.0/1.5/2.0；内容 "hello 你好"。预期：与基准图一致；并断言——常态边框 `border_control`、悬停 `border_control_hover`、聚焦 `accent_mark` 且有 `focus_ring_w` 外环、`invalid` 边框 `status_danger` 且右侧有错误图标像素、禁用无顶部内阴影且文字 `text_disabled`；选区行像素中选区内文字为 `text_on_accent`、其外为 `text_primary`；"无焦点但选区保留"与"窗口非活动"两列**无**任何选区高亮像素与光标像素；密码列为圆点且无字母像素；占位列颜色 `text_placeholder`。

**AC-W-TEXTINPUT-002**　`[单元]` 覆盖：REQ-W-TEXTINPUT-001、REQ-W-TEXTINPUT-002、REQ-W-TEXTINPUT-003、REQ-W-TEXTINPUT-004。以 `fit` 与默认 `grow(1)` 在 400 lpx 宽的行中布局：空缓冲、无占位 → `fit` 宽 = `button_min_w` = 72；内容 "hello world"（66 px）→ `fit` 宽 = 2×6 + 66 = 78；加前置图标 → 78 + 16 + 4 = 98；加 `invalid` → 再 + 16 + 4 = 118；`clearable` 且缓冲非空且聚焦 → 再 + 20 + 4 = 142；默认策略宽度 = 行内剩余宽度、高度 24（`size = .sm` 为 20、`.lg` 为 28）；视口左缘 = 外缘 + 6、右缘 = 外缘右 − 6（无附加部件时）；失去焦点且不悬停时清除按钮消失，视口随之变宽。

**AC-W-TEXTINPUT-003**　`[回放]` 覆盖：REQ-W-TEXTINPUT-020、REQ-W-TEXTINPUT-021、REQ-W-TEXTINPUT-022、REQ-W-TEXTINPUT-047、REQ-W-TEXTINPUT-030。缓冲 "hello world"，`@T` 无焦点。点击 (137,112) → 持有焦点，光标 5，选区 (5,5)，**未全选**。点击 (140,112) → 光标 6。Shift+点击 (172,112)（越过文本末端）→ 选区 (6,11)，光标 11。按下 (107,112)、移到 (125,112)、再移到 (128,112)、释放 → 先后得选区 (0,3)、(0,4)；释放后选区 (0,4)、光标 4；期间 `expect captured @T`，释放后 `none`。拖动时指针 y 移到 300（窗口外下方）x 不变 → 选区不变。另：选区 (0,4) 存在时在其内 (115,112) 按下并拖到 (200,112) → 这是一次重新选择（选区变为从按下点起的新选区），缓冲不变，`expect cursor ibeam`，不发生文本拖放。

**AC-W-TEXTINPUT-004**　`[回放]` 覆盖：REQ-W-TEXTINPUT-023、REQ-W-TEXTINPUT-019。缓冲为 "0123456789" 重复 6 次（60 簇，宽 360 px），`@T` 失焦。按下 (107,112)；移到 (300,112)（超出视口右缘 6）→ 光标 31（右缘处命中），横向偏移 0；`advance 50` → 偏移 6、光标 32；`advance 50` → 偏移 12、光标 33；再 `advance 50` → 偏移 18、光标 34；`expect timers 1`。再把指针移到视口左缘外 (60,112)（d = 46）→ 光标 3（左缘处命中簇 3 前半），`advance 50` → 偏移 max(0, 18 − min(46, 94)) = 0、光标 0。把指针移回 (200,112)（视口内）→ 光标 16（文本 x = 94，簇 15 后半）；`advance 400` → 偏移与光标不变，`expect timers` 不含该定时器。释放后选区 (0,16)。

**AC-W-TEXTINPUT-005**　`[回放]` 覆盖：REQ-W-TEXTINPUT-024、REQ-W-TEXTINPUT-025、REQ-W-TEXTINPUT-010。缓冲 "hello world"：在 (155,112) 间隔 100 ms 内双击 → 选区 (6,11)；在 (137,112) 双击 → 选区 (5,6)（空格被单独选中、不附带尾随空白）；在 (155,112) 三击 → (0,11)；第 4 次连击（间隔均 ≤ 500 ms）在 (155,112) 按下 → 计数回到 1，按单击规则光标 8、选区 (8,8)。双击 (143,112) 得 (6,11) 后**不释放**拖到 (112,112) → 选区 (0,11)、光标 0（初始词 "world" 与光标所在词 "hello" 的并集，锚点 11）。缓冲 "你好，世界"：双击簇 1（(113,112)）→ (3,6)；双击簇 2（(119,112)）→ (6,9)。缓冲 "a👨‍👩‍👧b"（20 字节）：双击 (113,112) → (1,19)。密码模式缓冲 "hello world"：双击任意位置 → 选区 (0,11)。

**AC-W-TEXTINPUT-006**　`[回放]` 覆盖：REQ-W-TEXTINPUT-026、REQ-W-TEXTINPUT-027、REQ-W-TEXTINPUT-020。缓冲 "hello world"，先双击 (155,112) 得选区 (6,11)；右键按下 (155,112)（选区内）→ 选区仍 (6,11)、持有焦点；右键释放 → `expect popup 1`，菜单项依次为 撤销、— 、剪切、复制、粘贴、删除、—、全选，文案等于 `Strings.edit_*`，其中 撤销（栈空）禁用、粘贴（剪贴板空）禁用、其余启用；按 Esc 关闭 → `expect popup 0`，焦点仍在 `@T`、选区仍 (6,11)。再右键按下 (112,112)（选区外）→ 选区 (1,1)；释放 → 菜单中 剪切、复制、删除 禁用。点击"全选"→ 菜单关闭，选区 (0,11)。假剪贴板置 "x" 后重开 → "粘贴"启用。按 Esc 后按 Shift+F10（光标 1）→ 菜单出现，弹出矩形左上角为 (112,120)，第一个启用项被高亮。

**AC-W-TEXTINPUT-007**　`[回放]` 覆盖：REQ-W-TEXTINPUT-028、REQ-W-TEXTINPUT-029、REQ-W-TEXTINPUT-020。`@T`（位于一个可滚动容器内，`clearable`、`clear_label` = "清除"）缓冲 "abc"：指针移到文本区 → `expect cursor ibeam`；移到清除按钮 → `expect cursor arrow`；滚轮 1 格 → 容器滚动偏移变化、文本框无变化；中键按下释放 → 光标、选区、`changed` 均无变化。点击清除按钮（失焦状态下）→ 缓冲 ""、光标 0、`changed` 真（恰一帧）、`@T` 持有焦点、选区 (0,0)（未触发全选）；按 Ctrl+Z → 缓冲 "abc"（清除是一步撤销）；清除按钮在缓冲为空时不显示（`expect rect` 失败/不存在）。悬停清除按钮超过 `hover_time_ms` → 提示框 "清除"。

**AC-W-TEXTINPUT-008**　`[回放]` 覆盖：REQ-W-TEXTINPUT-031、REQ-W-TEXTINPUT-032、REQ-W-TEXTINPUT-033、REQ-W-TEXTINPUT-047。缓冲 "hello world"。Tab 使 `@T` 获得焦点 → 选区 (0,11)、光标 11。按 ← → 选区 (0,0)（折叠到起点，未多移）；按 → → 光标 1；按 Ctrl+→ → 6；再按 Ctrl+→ → 11；按 Ctrl+← → 6；再按 Ctrl+← → 0；按 End → 11；按 Home → 0；按 Shift+→ 三次 → 选区 (0,3)、光标 3；按 → → 折叠到终点，光标 3、选区 (3,3)；按 Shift+Ctrl+→ → 选区 (3,6)、光标 6；按 Shift+Home → 选区 (0,3)、光标 0（锚点 3）；按 Ctrl+A → (0,11)；按 → → 光标 11。缓冲 "你好，世界"：光标 0，连按 Ctrl+→ → 依次 3、6、9、12、15。缓冲 "a👨‍👩‍👧b"：光标 0，连按 → → 1、19、20；连按 ← → 19、1。

**AC-W-TEXTINPUT-009**　`[回放]` 覆盖：REQ-W-TEXTINPUT-034、REQ-W-TEXTINPUT-035、REQ-W-TEXTINPUT-036。（1）"hello world"，光标 11：Backspace → "hello worl"、光标 10、`changed` 真。（2）"hello world" 选区 (6,11)：Delete → "hello "、光标 6。（3）"hello world" 光标 11：Ctrl+Backspace → "hello "、光标 6；再按 Ctrl+Backspace → ""、光标 0。（4）"hello world" 光标 0：Ctrl+Delete → "world"。（5）"hello world" 选区 (6,11) 按 Ctrl+Backspace → "hello "（只删选区）。（6）"你好，世界" 光标 15：Ctrl+Backspace → "你好，世"、光标 12；光标 9 处 Backspace → "你好世"、光标 6。（7）`"éx"`（4 字节），光标 3：Backspace → "ex"、光标 1（只删组合符）；另在光标 0 处 Delete → "x"（整个簇 3 字节）。（8）"a👨‍👩‍👧b" 光标 19：Backspace → "ab"、光标 1；"🇨🇳"（8 字节）光标 8：Backspace → ""；子区域旗帜 "🏴󠁧󠁢󠁥󠁮󠁧󠁿"（U+1F3F4 加 tag 字符 U+E0067 U+E0062 U+E0065 U+E006E U+E0067 与结束标签 U+E007F：4 + 6 × 4 = 28 字节，一个簇）光标 28：Backspace → ""、光标 0；Delete 于光标 0 同样整体删除。（9）光标 0 处 Backspace、末尾处 Delete、空缓冲 Ctrl+Backspace → `changed` 假、撤销栈不变。

**AC-W-TEXTINPUT-010**　`[回放]` 覆盖：REQ-W-TEXTINPUT-037、REQ-W-TEXTINPUT-038、REQ-W-TEXTINPUT-039、REQ-W-TEXTINPUT-010。（1）空缓冲 `text "ab你"` → "ab你"、光标 5；`text "\u{1F600}"` → 追加 4 字节；控制字符 `text "\u{7}"` 被忽略。（2）"hello world" 选区 (6,11)：Ctrl+C → 剪贴板 "world"、缓冲不变；Ctrl+Insert 同；光标折叠后（无选区）Ctrl+C → 剪贴板仍为 "world" 且 `sequenceNumber` 不变。（3）选区 (0,5)：Ctrl+X → 剪贴板 "hello"、缓冲 " world"、光标 0；Shift+Delete 同效。（4）剪贴板置 "line1\nline2\tx\u{7}y"（含 BEL）：在空缓冲 Ctrl+V → "line1 line2xy"、光标 13；Shift+Insert 同。（5）`max_len` = 8：同剪贴板粘贴 → "line1 li"、光标 8；`max_len` = 5 时 `text "ab你👨‍👩‍👧cd"` → "ab你👨‍👩‍👧c"（24 字节）、"d" 被忽略；已满时选区 (0,1) 键入 "x" → 允许替换。（6）模拟 `ClipboardBusy`：Ctrl+X 不删除、剪贴板不变。（7）密码模式缓冲 "secret" 全选：Ctrl+C、Ctrl+Insert、Ctrl+X、Shift+Delete → 剪贴板与缓冲均不变；Ctrl+V 照常可粘贴。

**AC-W-TEXTINPUT-011**　`[回放]` 覆盖：REQ-W-TEXTINPUT-042、REQ-W-TEXTINPUT-043、REQ-W-TEXTINPUT-044、REQ-W-TEXTINPUT-045、REQ-W-TEXTINPUT-049。（1）空缓冲 `text "abc"`（一次注入）→ Ctrl+Z → ""、光标 0；Ctrl+Y → "abc"、光标 3；Ctrl+Shift+Z 在再次撤销后同样重做。（2）`text "ab"`、`advance 1100`、`text "c"` → Ctrl+Z → "ab"；再 Ctrl+Z → ""。（3）`text "abc"`、按 ←、`text "X"` → "abXc"；Ctrl+Z → "abc"；Ctrl+Z → ""。（4）"abcdef" 光标 3：Backspace ×2 → "adef"；Delete → "aef"；Ctrl+Z → "adef"；Ctrl+Z → "abcdef"（方向改变断开合并）。（5）"hello" 全选，键入 "x" 再键入 "y" → "xy"；Ctrl+Z → "hello"、选区 (0,5)（替换选区的键入与其后连续键入同属一步）。（6）粘贴不合并：`text "a"`、粘贴 "b"、`text "c"` → 三步。（7）新编辑清空重做栈：撤销后键入 → Ctrl+Y 无效果。（8）容量：对 "x" 执行 300 次相互独立的粘贴（每次后按 ←→ 断开）→ 可连续撤销 256 次，第 257 次无效果。（9）撤销后 `changed` 真；失去焦点再获得焦点后撤销栈仍在；`@T` 在 5 次构建中不被声明、之后重新声明 → 撤销栈仍在。（10）`dirty`：键入再删回原内容后失焦仍报告 `committed`；Enter 后立即失焦不再报告。

**AC-W-TEXTINPUT-012**　`[回放]` 覆盖：REQ-W-TEXTINPUT-040、REQ-W-TEXTINPUT-031、REQ-W-TEXTINPUT-048。对话框范围内有 `@T`、默认按钮 B、取消按钮 C。`@T` 聚焦按 Enter → `@T.committed` 真恰一次、缓冲无 `\n`、**同时** B `clicked` 真且 `activated = .default_button`（Enter 经 `observes` 观察而不消费，路由继续到第 ⑦ 级）；`key down VK_RETURN` 后 `key repeat VK_RETURN 5`（13 的自动重复指令）→ `committed` 累计 1、B 的 `clicked` 累计 1。无默认按钮的范围（独立搜索框）按 Enter → `committed` 真、无其他效果。内容无变化：`commit_unchanged` 为真（默认）时 Enter 仍报告 `committed`；为假时不报告。按 Esc → C 被激活（`activated = .cancel_button`）。按 Tab → 焦点移到下一个停靠点。`@T` 缓冲 "abc" 光标 0：按 Insert，再 `text "X"` → "Xabc"（非改写）。登记命令 Alt+← 与 Ctrl+Alt+Home、Ctrl+PageDown 快捷键：焦点在 `@T` 时按之 → 命令被调用（未被预占）；登记命令 Ctrl+Z、Ctrl+A、Ctrl+Y：焦点在 `@T` 时按之 → 命令**未**调用，文本框执行撤销/全选/重做；焦点移到按钮后按 Ctrl+Z → 命令被调用。

**AC-W-TEXTINPUT-013**　`[回放]` 覆盖：REQ-W-TEXTINPUT-047、REQ-W-TEXTINPUT-048、REQ-W-TEXTINPUT-046、REQ-W-TEXTINPUT-049。（1）`@T` 缓冲 "hello world"：Tab 进入 → 选区 (0,11)；点击进入（先失焦再点击 (137,112)）→ 选区 (5,5)；程序 `setFocus` → 全选；窗口 `activate off` 再 `on`（原因 `restore`）→ 选区不变。（2）失焦：键入 "x" → `changed`；Tab 离开 → 该帧 `committed` 真；金图/绘制日志中 `@T` 无选区矩形、无光标；`expect focus` 为下一个控件。内容无变化时 Tab 离开 → `committed` 假；`commit_on_blur = false` 时键入后 Tab 离开 → `committed` 假。（3）`activate off`（窗口失去激活）→ 焦点仍在 `@T`、不报告 `committed`、无焦点环与光标。（4）只读 `@T` 与密码 `@T` 点击聚焦后 `expect visual @T focused_visible true`。（5）禁用 `@T`：Tab 跳过；点击不聚焦。

**AC-W-TEXTINPUT-014**　`[回放]` 覆盖：REQ-W-TEXTINPUT-016、REQ-W-TEXTINPUT-017、REQ-W-TEXTINPUT-018、REQ-W-TEXTINPUT-058。`@T` 缓冲 "ab"，点击 (118,112) 得光标 2，`caret_blink_ms` = 500，在时刻 t0：`expect timers 1`；绘制日志显示 t0 帧有光标；`advance 499` → 无新帧；`advance 1`（t0 + 500）→ 恰一帧、该帧无光标；`advance 500` → 有光标。该两帧的构建遍数均为 0、`expect damage == 16`（损伤恰为光标叶节点矩形 1×16 ppx）。在灭相位（t0 + 700）`text "c"` → 光标立即出现（控件调用 `ui.timerRestart`），下一次翻转在 t0 + 1200（`advance 499` 无新帧，再 `advance 1` 有帧）。`setting caret_blink_ms none` → 光标常亮、`expect timers 0`。选区非空（Ctrl+A）→ 无光标、`expect timers 0`。`activate off` → 无光标、`expect timers 0`。缩放 2.0 下光标宽 2 ppx。

**AC-W-TEXTINPUT-015**　`[回放]` 覆盖：REQ-W-TEXTINPUT-019、REQ-W-TEXTINPUT-004。缓冲 60 簇（宽 360 px，最大偏移 360 + 1 − 188 = 173）。聚焦、按 Home → 偏移 0；连按 → 30 次 → 偏移仍 0；第 31 次 → 偏移 3；第 32 次 → 9；第 33 次 → 15（每多一簇 +6，最小位移）。按 End → 偏移 173（夹紧）、光标绘制于视口右缘内。按 Home → 偏移 0。失焦（Tab 离开）→ 偏移 0（以绘制日志中文本原点 x = 106 确认）；Tab 回来（全选，光标在末尾）→ 偏移 173。`@T` 开启 `invalid` 使视口变窄 20 px 后 → 光标仍可见（偏移重新求值）。

**AC-W-TEXTINPUT-016**　`[回放]` 覆盖：REQ-W-TEXTINPUT-050、REQ-W-TEXTINPUT-051、REQ-W-TEXTINPUT-053、REQ-W-TEXTINPUT-054、REQ-W-TEXTINPUT-055。缓冲 "ab"，点击 (160,112) 得光标 2，`expect`：假平台 `setImeEnabled(true)`。`ime start`；`ime update "ni" 2` → `expect text @T "abni"`、缓冲仍 "ab"、`changed` 假、`composing` 真、绘制日志含点线下划线（`unconverted`）、假平台 `imeCaretRect` = (130,104,1,16)（客户区 ppx，缩放 1.0）、排除矩形为空；`ime update "你" 3` → 显示 "ab你"、`imeCaretRect` = (124,104,1,16)；`ime commit "你"` → 缓冲 "ab你"、光标 5、`changed` 真（该帧）；`composing` 假（`ime commit` 已包含其后的 `ime_end`，无单独的 `ime end` 指令）。Ctrl+Z → "ab"。`ime update` 带目标子句片段（`target_converted`）→ 排除矩形非空且等于该子句首矩形。组字中点击另一按钮 B → `commitComposition` 调用 1 次，`@T` 先收到 `ime_commit`（缓冲含组字串）与 `ime_end` 再失焦。密码模式聚焦 → `setImeEnabled(false)`。缩放 1.5 下 `imeCaretRect` 按 REQ-INPUT-062 取整换算。

**AC-W-TEXTINPUT-017**　`[回放]` 覆盖：REQ-W-TEXTINPUT-052、REQ-W-TEXTINPUT-053、REQ-W-TEXTINPUT-042。缓冲 "hello"，选区 (1,4)（Home、→、Shift+→×3）：`ime start`、`ime update "x" 1` → `expect text @T "hxo"`、选区高亮不显示、缓冲仍 "hello"。（a）`ime cancel`（只有 `ime_end`）→ 显示 "hello"、选区 (1,4) 恢复、Ctrl+Z 无效果、`changed` 假。（b）改为 `ime commit "x"`（含其后的 `ime_end`）→ 缓冲 "hxo"、光标 2、`changed` 真；Ctrl+Z → "hello"、选区 (1,4)（一步撤销）。

**AC-W-TEXTINPUT-018**　`[人工]` 覆盖：REQ-W-TEXTINPUT-051、REQ-W-TEXTINPUT-054、REQ-W-TEXTINPUT-052、REQ-W-TEXTINPUT-017、REQ-W-TEXTINPUT-038。真实 Windows 10 与 11，微软拼音与微软日文输入法：在文本框键入 "nihao"，观察组字串内联、未转换部分点线、目标子句粗实线加底色、候选窗出现在组字串下方且不遮挡之；改变横向滚动、移动窗口、切换 150% 缩放后候选窗位置仍跟随；选区非空时开始组字，选区被替换，按 Esc 取消后原选区恢复；修改系统"光标闪烁速度"（控制面板 → 键盘）后光标闪烁周期随之变化（可能需重启，记录结果）；用记事本复制含换行文本后粘贴，换行变为空格。

**AC-W-TEXTINPUT-019**　`[单元]` 覆盖：REQ-W-TEXTINPUT-005、REQ-W-TEXTINPUT-006、REQ-W-TEXTINPUT-007、REQ-W-TEXTINPUT-008、REQ-W-TEXTINPUT-013、REQ-W-TEXTINPUT-014。（1）`TextBuf.set` 传入相同内容 → `revision` 不变；不同内容 → +1；两个 `TextBuf` 的 `serial` 不同。（2）`@T` 键入 "abc"（撤销栈 1 步），应用 `set("abc")` → 撤销栈保留；`set("zzz")` → 撤销栈清空、Ctrl+Z 无效果、`changed` 假；光标 5 时 `set("hi")` → 光标 2；选区 (6,11) 时 `set("héllo")`（héllo 为 6 字节，h-é(2)-l-l-o）→ 选区夹紧为 (6,6)；缓冲换成另一个 `TextBuf` 实例 → 同样清空撤销栈。（3）`accept` 仅数字：`text "a1b2"` → "12"；粘贴 "1,234" → "1234"；`accept` 不影响 Backspace 与撤销。（4）`max_len` = 3 且缓冲（程序性写入）"abcde"：键入、粘贴被忽略，Backspace 可用；删到 2 簇后键入 "x" 成功；`max_len` = 0 时一切插入被忽略。（6）缓冲程序性写入 "a\nb\tc" → `expect text` 显示换行为空格、制表符按 4 个空格宽展开，光标可跨越各字符，Delete 可删除换行簇，复制得到原始字节。（5）缓冲程序性写入 262 144 个 "a"：键入 "b" 被忽略、Backspace 可用；写入 262 145 个 "a"：键入被拒、排版只取前 262 144 字节、调试构建记录 1 条 `warn`。

**AC-W-TEXTINPUT-020**　`[回放]` 覆盖：REQ-W-TEXTINPUT-010、REQ-W-TEXTINPUT-020、REQ-W-TEXTINPUT-035、REQ-W-TEXTINPUT-050。密码模式缓冲 "pw你"（5 字节）：`expect text @T` 显示 3 个 U+2022；点击 (119,112)（圆点 2 前半）→ 光标 2；点击 (123,112)（圆点 2 后半）→ 光标 5；Home 后 Ctrl+→ → 5（整个内容视为一个词）；光标 5 处 Ctrl+Backspace → ""；Ctrl+Z → "pw你"；右键菜单"剪切""复制"禁用、"粘贴"可用；聚焦时 `setImeEnabled(false)`。

**AC-W-TEXTINPUT-021**　`[回放]` 覆盖：REQ-W-TEXTINPUT-009、REQ-W-TEXTINPUT-046、REQ-W-TEXTINPUT-041。只读 `@T` 缓冲 "hello"：Tab 可聚焦；Tab 进入后全选；`text "x"`、Backspace、Ctrl+V、Ctrl+X、Ctrl+Z 均无效果且 `changed` 假；Ctrl+C 有效；右键菜单仅"复制""全选"可用；不显示清除按钮；`setImeEnabled(false)`。登记标准编辑命令：焦点在可编辑 `@T`（选区 (0,2)，剪贴板有文本）时，`edit.cut`、`edit.copy`、`edit.delete`、`edit.paste`、`edit.select_all` 启用，`edit.undo` 在栈空时禁用；经 `app.commands.invoke` 调用 `edit.select_all` → 选区 (0,5)；`edit.cut` → 与 Ctrl+X 同效；焦点移到按钮后全部 `edit.*` 禁用。

**AC-W-TEXTINPUT-022**　`[回放]` 覆盖：REQ-W-TEXTINPUT-056、REQ-W-TEXTINPUT-011。经假 UIA 入口：控件类型 Edit；Value = 缓冲全文；`SetValue("new")` → 下一帧缓冲 "new"、撤销栈清空；只读时 `IsReadOnly` 真；密码模式 `IsPassword` 真、Value 为空串、不提供 Text 模式；`invalid_message` 非空时 HelpText 等于该文本；Text 模式 `GetSelection` 在选区 (6,11) 时返回该范围，`GetBoundingRectangles` 与 `selectionRects` 加节点位置一致；`Select` 一个范围后选区更新。

**AC-W-TEXTINPUT-023**　`[计量]` 覆盖：REQ-W-TEXTINPUT-057、REQ-W-TEXTINPUT-058、REQ-W-TEXTINPUT-036。界面含 100 个文本框，其中一个聚焦。回放：指针从空白处移入文本框 X 再移出 → 各帧构建遍数 0，被绘制节点 ⊆ {X 及其相交的祖先}，损伤面积 ≤ X 的绘制范围面积；聚焦 X 后推进 `advance 5000` → 10 帧，每帧构建遍数 0、损伤面积 = 16 ppx²（光标叶节点矩形）、`time.frame_cpu` P99 ≤ 0.1 ms（S-CARET 场景）；在 X 键入一个字符 → 构建遍数 2（第二遍因 `changed`）、损伤 = X 的矩形；以相同参数再次 `invalidate(.build)` → 损伤为空、提交次数不变；仅改变 `placeholder` → 损伤恰为 X 的矩形；Backspace 在光标 0 处 → 无损伤。

## 17. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-W-TEXTINPUT-01 | 撤销合并的停顿时长 `undo_merge_pause` | 倾向 1000 ms（经验值：略长于连续键入的自然停顿）；需与记事本、Word 的撤销粒度实机对照后定稿 |
| OPEN-W-TEXTINPUT-03 | 拖放选中文本（拖出、拖入、移动/复制） | 不支持；需要时与 08 的应用内拖放（REQ-INPUT-059）及 OLE 对接，另立条款 |
| OPEN-W-TEXTINPUT-09 | 失去窗口激活时（而非失去焦点）是否提交 | 现为不提交（焦点仍在）；应用在窗口关闭前自行读取缓冲 |
| OPEN-W-TEXTINPUT-10 | 粘贴时制表符删除（而非转空格）是否过于激进 | 现按需求删除；备选为转为单个空格，需实机对照 Edit 控件 |
| OPEN-W-TEXTINPUT-11 | 密码圆点字符与是否允许显示明文切换（眼睛图标） | 现固定 U+2022；明文切换不在本版范围 |
| OPEN-W-TEXTINPUT-12 | 失效风险：非活动窗口中 Alt 单键与 F10 的菜单栏激活不得被文本框预占 | 本文已不预占 F10 与单独的 Alt；记录以便与 menu.md 对照 |
