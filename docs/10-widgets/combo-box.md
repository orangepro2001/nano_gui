# 组合框（combo-box）

> 可编辑变体的文本部分引用 text-input.md 的编辑核心（光标与选区、键位、撤销、剪贴板、输入法、光标闪烁），只写差异。弹出层的通用规则（弹出栈、轻关闭、`PopupSpec`、关闭原因）引用 08；越界翻转与定位引用 07 的 Anchor（`layout.placeAnchored`）。

## 1. 用途

从一组候选项中选一项（**下拉列表**，默认）或"输入或选择"（**可编辑**）。参照 Windows 的 ComboBox（`CBS_DROPDOWNLIST` 与 `CBS_DROPDOWN`）。

- 候选项很少（≤ 4）且需要一眼看全 → 用单选组。
- 一组动作而非值 → 用菜单。
- 需要多选、带图标与多列的项 → 用列表（list）。
- 候选项只是辅助建议、输入应是自由文本 → 可编辑变体（带自动完成）。

两个函数：`comboBox`（下拉列表，值为选中项序号）与 `comboBoxEditable`（可编辑，值为应用持有的 `TextBuf`）。

## 2. 解剖

```
        ┌─ 焦点环（下拉列表仅焦点可见时；可编辑恒显示）
┌─────────────────────────────┬────┐
│ 选中项文字 / 编辑文本区       │ ▾  │   容器 = 下拉列表 drawRaised；可编辑 drawSunken
└─────────────────────────────┴────┘
┌─────────────────────────────┐
│ 项 1                         │   弹出层（PopupKind.dropdown 或 autocomplete）
│▓项 2（高亮）▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│   drawPopupFrame；行高 row_h
│ 项 3                         │   超过 max_rows 时出现滚动条
└─────────────────────────────┘
```

- **容器**：下拉列表为凸起表面（外观近似按钮）；可编辑为内凹表面，其右侧箭头按钮为安静凸起。
- **文字区**：下拉列表显示选中项文字（或占位文字）；可编辑即嵌入的 text-input 编辑部分。
- **箭头**：`chevron_down`，位于右侧箭头区。
- **弹出层**：自绘、独立窗口（ADR 0008），内含项列表（Scroll + 虚拟化行）。

## 3. 度量与布局

| 项 | 取值（令牌） |
|---|---|
| 高度 | `control_h`（`size = .sm` 时 `control_h_sm`，`.lg` 时 `control_h_lg`） |
| 最小宽度 | `button_min_w` |
| 文字区左内边距 | `pad_input_x` |
| 箭头区宽 | `icon_md`；字形 `drawMark(chevron_down)`，字形框边长 `gap_md`，居中 |
| 文字与箭头区间距 | `gap_sm` |
| 弹出层行高 | `row_h` |
| 弹出层行左右内边距 | `pad_item_x` |
| 弹出层上下内边距 | `pad_popup_y` |
| 弹出层最大行数 | 选项 `max_rows`（默认 10） |
| 文字样式 | `font_body` |
| 绘制外延 | `focus_ring_w` |

**REQ-W-COMBOBOX-001**　默认尺寸策略：主轴 `fit`，交叉轴 `fixed(高度令牌)`。期望宽度 = `max(button_min_w, pad_input_x + 文字区所需宽 + gap_sm + icon_md)`，其中"文字区所需宽"取**前 `fit_sample = 100` 个项**与当前选中项（若有）的文字宽度的最大值（项很多时不测量全部）。调用方**可以**经 `layout` 改为 `fixed` 或 `grow`。可编辑变体的右内边距用于箭头区。

**REQ-W-COMBOBOX-002**　关闭态绘制：下拉列表 `drawRaised(neutral, radius_control)`（悬停、按下、禁用按 REQ-THEME-030 的通用表现；"按下"在弹出层打开期间常驻，内容下移 1 ppx），选中项文字 `text_primary` 左对齐，超宽尾部省略号（REQ-THEME-018）；无选中项时显示 `placeholder`（`text_placeholder`）或空。可编辑变体 `drawSunken`，文字区由编辑部分绘制，箭头区左侧一条竖向 `drawSeparator`，箭头按钮为安静凸起（悬停、按下才画容器）。两者的右侧箭头字形 `chevron_down`，颜色 `text_primary`（禁用 `text_disabled`）。

**REQ-W-COMBOBOX-003**　箭头区位于容器内缘（扣除发丝线）右侧，宽 `icon_md`，高为容器内缘高。下拉列表的箭头区只是视觉部件（整个容器都是命中范围）；可编辑变体的箭头区是独立的命中范围（REQ-W-COMBOBOX-012），文本区视口为左内边距之后、箭头区左缘之前减去 `gap_sm` 的区间。

**REQ-W-COMBOBOX-004**　下拉列表的选中项文字被截断时，悬停显示完整文字的提示框（REQ-THEME-018）；调用方给出 `tooltip` 时以调用方的为准。

## 4. 变体与参数

两个函数共用的选项：

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `max_rows` | `u8` | `10` | 弹出层最多显示的行数（≥ 1），超出则滚动 |
| `placeholder` | `?[]const u8` | `null` | 下拉列表无选中项时的提示；可编辑变体为编辑部分的占位文字 |
| `size` | `ControlSize` | `md` | 高度档 |
| `tooltip` | `?[]const u8` | `null` | 悬停提示 |
| `enabled`、`key`、`debug_name`、`layout` | 通用 | | 见模板 |

仅可编辑变体的选项：

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `autocomplete` | `bool` | `true` | 键入时显示前缀匹配的自动完成列表 |
| `max_len` | `?u32` | `null` | 同 text-input.md（字素簇） |
| `commit_on_blur` | `bool` | `true` | 同 text-input.md |

**项来源**：`ItemSource` 取 `slice`（`[]const []const u8`，应用持有，须在被声明期间存活）或 `callback { count, ctx, text_at }`（项数多或文本需按需生成时使用；`text_at(ctx, index, arena)` 返回第 `index` 项的文字，借用至本帧结束，只对可见项与被检索项调用）。项文字是纯文本（不解析助记符）。项数为 0 时控件仍可聚焦，但不打开弹出层。

**REQ-W-COMBOBOX-005**　**值的所有权**：下拉列表的值是应用持有的 `selected: *?u32`（选中项序号，`null` 表示无选中）；可编辑变体的值是应用持有的 `text: *TextBuf`（text-input.md，REQ-W-TEXTINPUT-005）。控件在用户改变值时写入并报告 `changed`；`selected` 超出 `[0, count)` 时显示为无选中并在调试构建记录一条 `warn`（不自动改写）。应用程序性改值在下一次构建生效，不报告 `changed`；弹出层打开期间应用改动值或项集合时，弹出层的高亮序号夹紧到新的 `[0, count)`。

**REQ-W-COMBOBOX-006**　项来源的约束：`count` 与各项文字在同一次构建内必须稳定；项数变化不关闭已打开的弹出层，高亮与滚动位置夹紧。选项 `max_rows` 为 0 时按 1 处理。控件**不得**为不可见项调用 `text_at` 或排版其文字（REQ-W-COMBOBOX-011）。

## 5. 状态

### 5.1 状态机

状态变量：`open ∈ {关, 下拉, 自动完成}`；`hot ∈ {无, 序号}`（弹出层中的高亮项）；`ta`（类型预搜索缓冲：字符串与最近键入时间）。

| 当前 | 事件 | 条件 | 下一状态 | 动作 |
|---|---|---|---|---|
| 关 | 左键按下于下拉列表 / 可编辑的箭头区（`capture_on_press = false`） | 启用，项数 > 0 | 下拉 | 取焦点；打开弹出层；`hot` = 选中项（或匹配文本的项）并滚动到可见；`drag` 会话开始 |
| 下拉（`drag` 会话） | 左键释放于某行 | — | 关 | 值 = 该行（不同则 `changed`），关闭 |
| 下拉（`drag` 会话） | 左键释放于控件本身 | 未移入弹出层 | 下拉 | 点击式打开，会话结束 |
| 下拉（`drag` 会话） | 左键释放于弹出层与控件之外 | — | 关 | 取消，值不变 |
| 关 | F4 / Alt+↓ / Alt+↑ / Space（仅下拉列表） | 持有焦点，项数 > 0 | 下拉 | 同上，`hot` 取首次高亮规则 |
| 关 | ↑ ↓ Home End（仅下拉列表） | — | 关 | 直接改变选中项，`changed` |
| 关 | 字符键（仅下拉列表） | — | 关 | 类型预搜索，命中则改变选中项，`changed` |
| 关 | 键入（可编辑） | `autocomplete` 真、有匹配项 | 自动完成 | 显示匹配列表（不抢占键盘） |
| 下拉 | ↑ ↓ PageUp PageDown Home End | — | 下拉 | 移动 `hot`，滚动到可见；值不变 |
| 下拉 | 指针移动到某行 | 指针实际移动过 | 下拉 | `hot` = 该行；值不变 |
| 下拉 | Enter / 点击某行 / F4 / Alt+↑ / Alt+↓ | `hot` 非空 | 关 | 值 = `hot` 项（不同则 `changed`）；关闭 |
| 下拉 | Esc / 轻关闭（点击外部、窗口失活等） | — | 关 | 值保持打开前的值，关闭，不报告 `changed` |
| 下拉 | 点击锚点（控件自身） | — | 关 | 轻关闭并吞掉该次点击（REQ-INPUT-053），不重新打开 |
| 自动完成 | ↓ / ↑ | — | 自动完成 | 移动 `hot`（↑ 自首项回到"无"） |
| 自动完成 | Enter | `hot` 非空 | 关 | 文本 = 该项，`picked`、`changed`、`committed` |
| 自动完成 | Enter | `hot` 为空 | 关 | 普通提交（`committed`） |
| 自动完成 | Esc | — | 关 | 框架关闭弹出层并消费该键，文本不变 |
| 自动完成 | 失去焦点 / 无匹配 / 文本清空 | — | 关 | 关闭 |
| 自动完成 | Alt+↓ / F4 | — | 下拉 | 关闭自动完成，打开完整列表（抢占键盘） |

### 5.2 视觉表现

| 状态 | 绘制（基元 + 令牌） |
|---|---|
| 下拉列表 常态 / 悬停 / 按下 / 禁用 | `drawRaised(neutral)` 的对应变体；文字 `text_primary`（禁用 `text_disabled`） |
| 打开期间 | 按下外观常驻；焦点环保持 |
| 焦点可见 | `drawFocusRing`（下拉列表在键盘导航后；可编辑恒显示） |
| 可编辑 常态 / 悬停 / 聚焦 / 禁用 | `drawSunken`；聚焦边框 `accent_mark` |
| 弹出层底 | `drawPopupFrame(R, false)`（`surface_popup`） |
| 弹出层行 | 文字 `text_primary`（`font_body`），左内边距 `pad_item_x`，超宽尾部省略号 |
| 高亮行（`hot`） | `drawSelection(row, true)`，文字 `text_on_accent`；**鼠标悬停行与键盘高亮是同一个高亮**，任一时刻只有一行高亮 |
| 选中项（未高亮时） | 在其行右端绘制 `drawMark(check)`，颜色 `text_primary`（仅下拉列表） |

**REQ-W-COMBOBOX-007**　打开时控件经 `ui.beginPopup` 声明弹出层：下拉为 `PopupSpec{ kind = .dropdown, anchor = 控件矩形, anchor_id = 控件 ID, placement = { below, start }, gap = none, match_anchor_width = true, light_dismiss = true, close_on_escape = true, keyboard = .grab }`；自动完成为 `kind = .autocomplete`、`keyboard = .passive`（其余同）。宽度不小于控件宽（`match_anchor_width`），内容更宽时取内容宽度并受工作区限制（超宽项以省略号截断）；越界翻转（改到控件上方）与交叉方向夹紧由 Anchor 的 `placeAnchored` 完成（REQ-LAYOUT-043）；翻转后顶边对齐控件上沿减去弹出高度。弹出层高度 = `min(项数, max_rows) × row_h + 2 × pad_popup_y`，受工作区高度限制（`height_limited` 时内容滚动）。

**REQ-W-COMBOBOX-008**　项数大于可见行数时，弹出层内容为纵向 Scroll（07，滚动条策略 `auto`，宽 `scrollbar_w`，从行宽中扣除）；滚轮（按 `wheel_lines`，`page` 时一页）、拖动滑块、点击槽滚动列表，行为引用 scroll-view.md；滚动不改变 `hot` 与值。

**REQ-W-COMBOBOX-009**　弹出层行的布局：行高 `row_h`，行文字 `font_body`，左缘 `pad_item_x`、右缘 `pad_item_x`（有滚动条时在滚动条之前），在行内按"行框垂直居中"放置（REQ-THEME-017）；超宽以尾部省略号截断（REQ-THEME-018）。第一行的顶边 = 弹出层顶边 + `pad_popup_y`，最后一行底边与弹出层底边相距 `pad_popup_y`（滚动时该内边距属于滚动内容之外，不随滚动移动）。高亮行占满行宽（含左右内边距，不含滚动条），直角（REQ-THEME-027）。

**REQ-W-COMBOBOX-010**　下拉列表的弹出层中，当前选中项（`selected` 对应的行）在**不是**高亮行时于行右端（`pad_item_x` 内）绘制 `drawMark(check)`（`icon_sm`，`text_primary`），使选中项可辨认（形状而非颜色）；高亮行不绘制勾（`text_on_accent` 文字已足以区分）。可编辑变体不绘制勾。

**REQ-W-COMBOBOX-011**　**虚拟化**（弹出层内容的大内容坐标遵循 REQ-LAYOUT-054，虚拟化迭代方式可参照 list.md，按文件名引用）：弹出层只为与视口相交的行（含部分可见者）构建节点；节点数与项总数无关（项数 1 万与 10 万时同一状态的 `frame.nodes` 相等，REQ-PERF-021 的同类约束）。内容高度 = 项数 × `row_h`，可见行区间由滚动偏移推出；`text_at` 只对可见行与类型预搜索正在检索的项调用。

## 6. 鼠标行为

**REQ-W-COMBOBOX-012**　控件登记 `click`，且下拉列表（整个容器）与可编辑变体的箭头区声明 `InteractOpts.capture_on_press = false`（REQ-INPUT-013：按下不建立隐式捕获）。左键在下拉列表的任意处、或可编辑变体的箭头区按下时**打开**（按下即生效，不等释放，与 Windows 一致），并取得焦点（原因 `pointer`）；可编辑变体的文本区（独立节点，保留隐式捕获以便拖动选择）按下按 text-input.md 定位光标，**不**打开弹出层。**按住拖动选择**：因按下不捕获，按下打开后不松开，把指针移到弹出层某行（`hot` 随之移动，REQ-W-COMBOBOX-014）后释放，即选中该行并关闭（同 menu.md 的"按下–拖动–释放"，REQ-W-COMBOBOX-015）；释放时指针仍在控件本身（未移入弹出层）视为"点击式打开"，弹出层保持；释放在弹出层与控件之外则取消并关闭。弹出层已打开时，再次点击控件本身（锚点）关闭它：由 REQ-INPUT-053 的锚点例外保证该点击被吞掉而不会立即重新打开。右键：下拉列表无上下文菜单；可编辑变体的文本区同 text-input.md。中键不处理。指针形状：下拉列表恒为箭头；可编辑变体文本区为 I 形、箭头区为箭头（REQ-THEME-032）。

**REQ-W-COMBOBOX-013**　**滚轮在关闭态不改变值**（有意偏离 Windows 原生，见 OPEN-W-COMBOBOX-01）：关闭态的组合框不声明 `WheelCaps`，滚轮事件按 REQ-INPUT-019 冒泡给外层可滚动容器，使滚动页面经过组合框时不会误改值。弹出层打开时，滚轮只在弹出层内路由（REQ-INPUT-019 末句），滚动列表。

**REQ-W-COMBOBOX-014**　**悬停只移动高亮，不改值**：弹出层内指针移动到某行（`hovered` 变化）时 `hot` = 该行，**仅当指针自上一次构建以来确实移动过**才生效——键盘移动高亮、列表滚动或弹出层刚打开时静止指针所在行不夺走高亮。指针移出所有行（如到滚动条或弹出层之外）时 `hot` 保持不变。行节点置 `hover_rebuild`，使悬停引起的高亮变化作为 `build` 级失效处理。

**REQ-W-COMBOBOX-015**　左键在某行上按下并在**同一行**释放（点击）：值 = 该项（与旧值不同则 `changed`），关闭弹出层，焦点留在控件。**按住拖动选择**：打开弹出层的那次按下尚未释放时（`drag` 会话，由控件上的按下发起），指针移到某行后释放，同样选中该行并关闭（无需在该行上先按下）；该会话中释放于禁用或无行处（滚动条、行间空白）无效果，弹出层保持。除此之外按下于某行、释放于另一处不选中。点击滚动条与弹出层空白不关闭。

## 7. 键盘行为

**关闭态（下拉列表）**：

| 键 | 行为 |
|---|---|
| ↑ / ↓ | 直接选中上一/下一项（不打开）；无选中时 ↓ 选中第一项、↑ 无效果；在首/末项时无效果（不回绕） |
| Home / End | 选中第一/最后一项 |
| F4、Alt+↓、Alt+↑、Space | 打开弹出层（`hot` = 选中项，无选中项时 `hot` = 无） |
| 字符键 | 类型预搜索（REQ-W-COMBOBOX-017） |
| Enter | 不处理（继续路由到默认按钮，REQ-INPUT-034） |
| Esc、Tab | 不处理 |

**打开态（下拉，抢占键盘）**：

| 键 | 行为 |
|---|---|
| ↑ / ↓ | `hot` 上/下移一项（不回绕）；`hot` 为空时 ↓ 到首项、↑ 到末项 |
| PageUp / PageDown | `hot` 移动 `visible_rows − 1`（至少 1）项，保持滚动到可见 |
| Home / End | `hot` 到首/末项 |
| Enter | 确认 `hot` 项并关闭 |
| F4、Alt+↓、Alt+↑ | 确认 `hot` 项并关闭（`hot` 为空则等同取消） |
| Space | 类型预搜索缓冲非空时作为字符；否则同 Enter |
| 字符键 | 类型预搜索，移动 `hot`（不改值） |
| Esc | 取消并关闭，值保持打开前的值 |
| Tab、其余键 | 被弹出层吃掉（REQ-INPUT-027），无效果 |

**REQ-W-COMBOBOX-016**　下拉列表持有焦点且关闭态时，按下表声明输入（`KeyGroups` 只匹配无修饰或仅 Shift 的键；只要 ↑↓、F4、Alt 组合时用 `extra` 逐个列出，**不**用 `groups.arrows`）；不预占 Enter、Esc、Tab、←、→。↑/↓/Home/End 直接改变选中项并立即报告 `changed`（每次按键一次，自动重复照常重复）；改变值后若弹出层关闭则无弹出动作。F4、Alt+↓、Alt+↑、Space 在项数 > 0 时打开弹出层，自动重复的这些键被忽略。完整的输入声明清单见下表（下表）。

**REQ-W-COMBOBOX-017**　**类型预搜索**（下拉列表的关闭态与打开态）：字符键把该字符（`char` 事件，控制字符忽略）追加到缓冲；若距上一个字符的时间超过 `typeahead_timeout` 则先清空缓冲。`typeahead_timeout = 2 × SystemMetrics.double_click_ms`（读取系统度量，03，暂定倍数 2，见 OPEN-W-COMBOBOX-02；默认 500 ms 时为 1000 ms；恰等于超时不清空）。匹配比较按 Unicode 简单大小写折叠、以字素簇为单位的**前缀**匹配。算法：令缓冲簇数为 n；(a) n = 1，或缓冲各簇全部相同（如 "aaa"，视为循环）：从"当前项（关闭态为选中项，打开态为 `hot`）的下一项"起、绕过末尾、至当前项为止，取第一个以该簇为前缀的项；(b) 否则：从当前项**起**（含）按同样次序取第一个匹配项。命中则关闭态改变选中项并报告 `changed`，打开态移动 `hot`；未命中无变化（缓冲保留至超时）。缓冲在超时、↑↓Home End、打开/关闭、失去焦点时清空。

**输入声明清单**（`InteractOpts` 随状态在构建时给出，REQ-INPUT-028、REQ-INPUT-062）：

| 状态 | `preempt` | `handles` | `observes` | `text_input` / `ime` |
|---|---|---|---|---|
| 下拉列表·关闭 | `groups.printable`、`groups.home_end`；`extra` = {↑、↓（无修饰）、F4、Alt+↓、Alt+↑} | 无 | 无 | 假 / 假 |
| 下拉列表·展开（弹出根的面板，键盘由第 ② 级抢占） | `groups.printable`（使 `char` 投递给面板） | 无（第 ② 级把全部键交给面板；Esc 不声明，由框架关闭，REQ-INPUT-027） | 无 | 假 / 假 |
| 可编辑·无弹出层 | text-input.md 的预占集合（REQ-W-TEXTINPUT-031）加 `extra` ∪ {F4、Alt+↓、Alt+↑} | 无 | 无修饰 Enter | 真 / 真 |
| 可编辑·自动完成显示，`hot` 为空 | 上一行加 `extra` ∪ {↑、↓（无修饰）} | 无 | 无修饰 Enter（报告 `committed`，默认按钮照常触发） | 真 / 真 |
| 可编辑·自动完成显示，`hot` 非空 | 上一行再加**无修饰 Enter**（Enter 由 `observes` 移入 `preempt`，REQ-W-COMBOBOX-024） | 无 | 无 | 真 / 真 |
| 可编辑·下拉展开 | 同"下拉列表·展开"（文本部分不收键盘） | 无 | 无 | 真 / 假 |

自动完成弹出层是 `passive`：Esc 由框架在第 ③ 级之前关闭并消费（REQ-INPUT-027 末句），不需要控件声明。

**REQ-W-COMBOBOX-018**　打开时 `hot` = 当前选中项（可编辑变体：与文本逐字相等的第一项，无则为"无"），并把该行滚动到可见：行已在视口内则不动，否则以最小位移使其进入视口（07 的 `ScrollParams.reveal`），滚动初值为 0。无选中项时滚动位置为 0、`hot` 为空。

**REQ-W-COMBOBOX-019**　打开态的键位如上表。`hot` 的移动不回绕；任何 `hot` 移动后保证该行可见（最小位移）；PageUp/PageDown 同时按 `visible_rows − 1` 滚动。Enter 或 F4/Alt+↑/Alt+↓ 确认时：`hot` 非空 → 值 = 该项（与旧值相同则不报告 `changed`）并关闭；`hot` 为空 → 仅关闭。弹出层吃掉未处理的键（REQ-INPUT-027），Tab 无效果，不使宿主失去焦点。

**REQ-W-COMBOBOX-020**　Esc、轻关闭（点击外部、窗口失去激活、宿主移动/缩放、DPI 变化、宿主打开对话框等，REQ-INPUT-054）关闭弹出层时**必须**取消：值保持打开前的值（打开期间控件从不改动值，故无需恢复动作；应用在打开期间程序性改值的结果保留），不报告 `changed`，焦点与滚动位置（宿主）不变。收到 `popup_dismissed` 后控件在下一次构建不再声明弹出层。

## 8. 焦点

**REQ-W-COMBOBOX-021**　禁用的组合框：不可聚焦、不响应点击与键盘、不打开弹出层（已打开则关闭）；外观为禁用配方（下拉列表 `drawRaised` 禁用、可编辑 `drawSunken` 禁用），文字与箭头 `text_disabled`；悬停仍可显示 `tooltip`（REQ-INPUT-009）；鼠标指针为箭头。

**REQ-W-COMBOBOX-022**　下拉列表可聚焦且为 Tab 停靠，`take_focus_on_click = true`；其焦点环遵循焦点可见规则（鼠标点击后不显示，键盘导航后显示，REQ-INPUT-040）；**不**声明 `text_input`（输入法禁用）。可编辑变体的文本部分是文本输入类：焦点环恒显示、`text_input = true`、`ime = true`；因 `tab` 等获得焦点时全选、点击进入不全选（REQ-W-TEXTINPUT-047）。弹出层打开期间宿主焦点节点保持不变（REQ-INPUT-036），键盘由弹出层抢占；关闭后键盘回到控件。禁用的组合框不可聚焦，弹出层打开时变为禁用则关闭弹出层。

## 9. 文本与输入法

**REQ-W-COMBOBOX-023**　**可编辑变体**的文本部分是 text-input 编辑部分（`embed = { reserve_right = icon_md + gap_sm, frame_owner = true }`），支持其全部键位、鼠标、撤销、剪贴板与输入法（REQ-W-TEXTINPUT-051 等）；Enter 经 `observes` **观察而不消费**（REQ-W-TEXTINPUT-040）：报告 `committed`，同时路由继续，所在范围有默认按钮时照常触发；**自动完成显示且 `hot` 非空时**改为预占并接受该项，见 REQ-W-COMBOBOX-024；失去焦点时有变化则 `committed`。箭头区与 F4/Alt+↓/Alt+↑ 打开**完整**列表（抢占键盘；此时文本部分不收键盘，直到关闭）。从列表（下拉或自动完成）选中一项：文本被整体替换为该项文字（一步撤销，独立步），光标置末尾、选区折叠，报告 `changed` 与 `committed`，并在结果中给出 `picked = 序号`。

**REQ-W-COMBOBOX-024**　**自动完成**：`autocomplete` 为真时，用户**键入**（含粘贴、输入法提交）使文本非空后，若存在以文本为前缀（Unicode 简单大小写折叠，字素簇比较）且**不与文本逐字相等**的项，则显示 `PopupKind.autocomplete` 弹出层（REQ-W-COMBOBOX-007），列出这些匹配项（保持原顺序，至多 `max_rows` 行，超出滚动）；`hot` 初始为空（不自动高亮，Enter 默认按普通提交处理）。该弹出层**不抢占键盘**（`keyboard = .passive`，REQ-INPUT-055）：文本框保持焦点与键盘，控件预占 ↑/↓（仅在该弹出层显示期间）：↓ 使 `hot` 下移一项（空 → 首项，末项无效果），↑ 上移一项（首项 → 空）；`hot` 非空期间控件把 Enter **改为预占**（`preempt`，不再是 `observes`）：Enter 接受该项（见 REQ-W-COMBOBOX-023）并**消费**该键，不触发默认按钮；`hot` 为空时 Enter 仍是观察：普通提交（`committed`）并关闭，默认按钮照常触发；Esc 由框架在进入 ③ 之前关闭弹出层并消费（REQ-INPUT-027 末句），文本不变；Tab 移动焦点并关闭（失焦）。文本无匹配、变空、程序性改值、失去焦点时关闭；鼠标点击某匹配行等同接受。自动完成弹出层关闭后（非失焦）按 ↓ 且当前文本仍有匹配项时重新显示并使 `hot` = 首项。

## 10. 动效

| 属性 | 触发 | 时长令牌 | 缓动 | 影响级别 |
|---|---|---|---|---|
| 容器填充与边框（常态 ↔ 悬停） | 悬停变化 | `dur_fast` | `ease_out` | paint（`Visual.hover_t`） |
| 容器（→ 按下） | 打开 | `dur_instant` | — | paint |
| 焦点环 | 焦点变为可见 | `dur_fast` 淡入，消失瞬时 | `ease_out` | paint |
| 弹出层出现 | 打开 | 系统菜单淡入开启（`menu_animation` 且 `menu_fade`）时 `dur_fast` 透明度淡入，否则瞬时；消失一律瞬时 | `ease_out` | paint（REQ-THEME-020） |
| 弹出层高亮行 | 高亮移动 | 无（瞬时） | — | build |

**REQ-W-COMBOBOX-025**　弹出层的出现动画完全遵循系统设置（REQ-THEME-020）：`SystemMetrics.menu_animation` 与 `menu_fade` 同为真时用 `dur_fast` 的透明度淡入（`paint` 级，不改变弹出窗口位置与尺寸）；任一为假、或 `client_animation` 为假时瞬时出现；关闭一律瞬时。动画期间弹出层已可交互（点击在出现动画中立即生效）。

## 11. 无障碍

| 项 | 值 |
|---|---|
| UIA 控件类型 | ComboBox；弹出层内为 List，行为 ListItem |
| 名称来源 | 紧邻其前的 label（`focus_next`）或调用方给出的名称；ListItem 取项文字 |
| 支持的模式 | ExpandCollapse（ComboBox）、Value（下拉列表只读，值 = 选中项文字；可编辑可写）、Selection（下拉列表）；List 的 Selection、ScrollItem；未实际构建的行以 VirtualizedItem 暴露 |
| 状态属性 | IsEnabled、HasKeyboardFocus、ExpandCollapseState（Collapsed/Expanded）、ValueIsReadOnly |

**REQ-W-COMBOBOX-026**　UIA `Expand`/`Collapse` 等同 F4 打开/取消；`SelectionItem.Select` 在 ListItem 上等同点击该行（改值并关闭）；下拉列表的 `Value.SetValue(text)` 若与某项文字逐字相等则选中该项，否则无效果；可编辑的 `Value.SetValue` 等同 `TextBuf.set`（清空撤销栈）。

## 12. API 草案

```zig
// 草案：仅签名
pub const ItemSource = union(enum) {
    slice: []const []const u8,                // 应用持有，须在被声明期间存活
    callback: struct {
        count: u32,
        ctx: ?*const anyopaque = null,        // 须在本次构建期间存活
        /// 返回第 index 项的文字；借用至本帧结束。只对可见项与检索项调用。
        text_at: *const fn (ctx: ?*const anyopaque, index: u32, arena: std.mem.Allocator) []const u8,
    },
};

pub const ComboBoxOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    max_rows: u8 = 10,
    placeholder: ?[]const u8 = null,   // 借用至本帧结束
    size: ControlSize = .md,           // 定义于 button.md
    tooltip: ?[]const u8 = null,
    layout: layout.ItemOptions = .{},
};

pub const ComboBoxEditableOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    max_rows: u8 = 10,
    placeholder: ?[]const u8 = null,
    autocomplete: bool = true,
    max_len: ?u32 = null,
    commit_on_blur: bool = true,
    size: ControlSize = .md,
    tooltip: ?[]const u8 = null,
    layout: layout.ItemOptions = .{},
};

pub const ComboBoxResult = struct {
    id: WidgetId,
    // 持续性状态
    hovered: bool,
    focused: bool,
    open: bool,                  // 弹出层（下拉或自动完成）是否打开
    // 激活类结果（触发同帧第二构建遍，REQ-FRAME-030）
    changed: bool,               // 值被用户改变
    committed: bool,             // 可编辑：Enter、失焦或从列表选中；下拉列表恒为 false
    picked: ?u32,                // 本帧从列表（弹出层或类型预搜索）选中的项序号；可编辑变体键入不产生
};

/// 下拉列表：selected 由应用持有，null 表示无选中项。
pub fn comboBox(ui: *Ui, src: std.builtin.SourceLocation, selected: *?u32, items: ItemSource, opts: ComboBoxOptions) ComboBoxResult;
/// 可编辑：text 由应用持有（TextBuf，见 text-input.md）。
pub fn comboBoxEditable(ui: *Ui, src: std.builtin.SourceLocation, text: *TextBuf, items: ItemSource, opts: ComboBoxEditableOptions) ComboBoxResult;
```

`changed`、`committed`、`picked` 是激活类结果。`items` 的切片与回调上下文须在控件被声明期间存活；值由应用持有（指针）；弹出层状态、高亮、滚动与类型预搜索缓冲由框架保留。

## 13. 保留状态

| 字段 | 类型 | 保留级别 | 说明 |
|---|---|---|---|
| `open` | `enum { closed, dropdown, autocomplete }` | transient | 弹出层是否声明；`popup_dismissed` 后置 `closed` |
| `hot` | `?u32` | transient | 弹出层高亮项（键盘与鼠标共用） |
| `scroll` | `{top_line, top_offset}`（07 的 Scroll 状态） | transient | 每次打开重置并按 REQ-W-COMBOBOX-018 求初值 |
| `last_pointer` | `?Vec2` | transient | 判定指针是否移动过（REQ-W-COMBOBOX-014） |
| `ta` | `{buf: [64]u8, len, last_ms}` | transient | 类型预搜索缓冲 |
| 编辑核心状态（可编辑） | 同 text-input.md | 同 text-input.md | 光标、选区、撤销栈等 |

## 14. 失效规则

**REQ-W-COMBOBOX-027**　控件本体的绘制键**必须**由以下各项构成：选中项文字（或可编辑的文本哈希）、`placeholder`、`open`、`enabled`、`size`、变体、有焦点、焦点可见、窗口是否活动、（可编辑）选区与光标偏移与组字。弹出层根节点的绘制键由 `hot`、滚动偏移、项数、可见行文字哈希构成。布局输入的内容度量键由前 `fit_sample` 项与选中项的文字、字体样式、`size` 构成。

| 变化 | 置脏级别 | 损伤范围 |
|---|---|---|
| 控件悬停进入/离开、焦点环 | `paint` | 控件绘制范围 |
| 弹出层内悬停行变化（行节点 `hover_rebuild`） | `build` | 弹出根内旧、新高亮行的矩形 |
| 键盘移动高亮、滚动 | `build` | 弹出根内相关行矩形（滚动时为弹出根整个可见区） |
| 打开/关闭弹出层 | `build` | 控件矩形与弹出根（新建或销毁整个弹出窗口） |
| 关闭态改变选中项 | `build` | 控件矩形（`fit` 且宽度变化时含受影响的兄弟） |
| 自动完成列表随键入更新 | `build` | 弹出根整个范围 |

**REQ-W-COMBOBOX-028**　仅悬停进入/离开控件本体所产生的帧**必须**是纯绘制帧（构建遍数 0），损伤不超出控件绘制范围；弹出层内仅悬停行变化的帧只重绘弹出窗口，宿主窗口的损伤为空。

## 15. 边界与错误情况

| 情况 | 规定 |
|---|---|
| 项数为 0 | 控件可聚焦；F4/点击不打开；↑↓ 无效果；显示占位或空 |
| 项数为 1 | 正常打开，弹出层 1 行 |
| 项文字为空串 | 显示为空白行，可选中；类型预搜索不匹配 |
| 项文字极长 | 行内尾部省略号；弹出层宽度受工作区限制 |
| 项文字含换行或制表符 | 排版为单行（换行、制表符按 05 的单行规则显示为空格） |
| 打开期间项数减少使 `hot`/选中序号越界 | `hot` 夹紧到新范围；项数变 0 则关闭弹出层 |
| 打开期间控件变为禁用/从树中消失 | 弹出层随声明停止而关闭，不报告 `changed`；宿主焦点按 REQ-INPUT-042 处理 |
| 打开期间窗口缩放/DPI 变化 | 关闭（REQ-INPUT-054），取消语义 |
| 打开期间应用程序性改变 `selected` | 保留；`hot` 不随之移动 |
| 控件在屏幕下边缘 | 弹出层翻转到控件上方（Anchor）；上下都放不下时取较大一侧并限制高度、内容滚动 |
| 多显示器 | 以锚点所在显示器的工作区为边界（REQ-LAYOUT-044） |
| 类型预搜索缓冲满（64 字节） | 超出的字符被忽略 |
| 可编辑变体 `text` 含换行（程序性） | 按 text-input.md 的单行规则显示 |
| 同一帧内 Enter 与失焦 | `committed` 只报告一次 |

## 16. 验收标准

**夹具 F-CB**（除特别注明外）：无头、`fixed` 文本后端（簇宽 6 px，行高 16 px）、缩放 1.0、窗口 400×300（工作区同窗口，窗口位于屏幕 (0,0)）；`@C` 为 `comboBox`，位于 (100,100)、150×24；项 `["Apple","Apricot","Avocado","Banana","Blueberry","Cherry"]`（序号 0–5）；`selected` 初值 `null`；`double_click_ms` = 500、`caret_blink_ms` = 500、`menu_animation` = off。行高取 `font_body` 的令牌行高 16（REQ-THEME-016），与 fixed 后端的自然行高无关（弹出层行高另由令牌 `row_h` = 22 给定）。弹出层矩形取自 `headless.popupRects()`：弹出层顶边 = 控件下沿 124，第 r 行的 y 范围 [128 + 22r, 150 + 22r)（`pad_popup_y` = 4，`row_h` = 22）。回放记号同 text-input.md 第 16 节。

**AC-W-COMBOBOX-001**　`[金图]` 覆盖：REQ-W-COMBOBOX-001、REQ-W-COMBOBOX-002、REQ-W-COMBOBOX-003、REQ-W-COMBOBOX-004、REQ-W-COMBOBOX-007、REQ-W-COMBOBOX-009、REQ-W-COMBOBOX-010、REQ-W-COMBOBOX-011、REQ-W-COMBOBOX-021、REQ-W-COMBOBOX-025。状态矩阵：下拉列表 {常态, 悬停, 打开（按下外观常驻）, 焦点可见, 禁用, 无选中显示占位, 选中项文字被截断} 与可编辑 {常态, 悬停, 聚焦, 聚焦且箭头区悬停, 禁用} × 浅/深/高对比度 × 缩放 1.0/1.5/2.0；弹出层 {高亮第 1 行, 选中项带勾标记, 超过 `max_rows` 出现滚动条, 越界翻转到上方, 自动完成列表} × 浅/深。预期：与基准图一致；弹出层宽度 = 控件宽（`match_anchor_width`）、6 项时矩形 (100,124,150,140)；`max_rows` = 4 时高 96、出现 `scrollbar_w` 滚动条且行宽相应减小；控件位于 y = 270 时弹出层翻转为 (100,130,150,140)（顶边 = 270 − 140）；高亮行为 `drawSelection` 的像素色、文字 `text_on_accent`；选中项（未高亮）右端有勾、高亮行无勾；打开时容器为按下外观；行内文字相对行框垂直居中、第一行顶边 = 弹出顶边 + 4；`setting menu_animation on`、`menu_fade on` 时弹出出现的首帧透明度 < 1、`dur_fast` 后为 1，关闭任一设置则首帧即不透明；禁用列绘制禁用配方且点击不打开弹出层（`expect popup 0`）。

**AC-W-COMBOBOX-002**　`[回放]` 覆盖：REQ-W-COMBOBOX-012、REQ-W-COMBOBOX-015、REQ-W-COMBOBOX-008、REQ-W-COMBOBOX-018。`selected` = 2（Avocado）：点击 (120,112)（控件内）→ `expect popup 1`，`@C` 持有焦点，弹出矩形 (100,124,150,140)，高亮行 2；`changed` 假（打开不改值）。点击弹出层第 3 行 (120,128+44+5 = 177)（Avocado，序号 2）→ 值仍 2、`changed` 假、弹出关闭；重开后点击第 5 行 (120,128+88+5 = 221)（Blueberry，序号 4）→ `selected` = 4、`changed` 恰一帧、弹出关闭、焦点仍在 `@C`。按下于第 1 行、移到第 2 行释放 → 不选中、弹出保持。再次点击控件本身 → 弹出关闭，且该次点击未导致重新打开（`expect popup 0` 恒成立，点击序列只进行一次）。`max_rows` = 4：打开时（`selected` = 5）`scroll` 使第 6 行可见（最小位移：偏移 = 6×22 − 4×22 = 44），`wheel -1`（向下 1 格，13 的符号：负值向下；`wheel_lines` = 3）→ 偏移夹紧到最大 44；拖动滑块滚动。

**AC-W-COMBOBOX-003**　`[回放]` 覆盖：REQ-W-COMBOBOX-012、REQ-W-COMBOBOX-015、REQ-W-COMBOBOX-016。按住拖动选择（`selected` = 0）：`move 120 112`、`down left` → 按下即 `expect popup 1`、`@C` 持有焦点、未捕获（`expect captured none`）；`move 120 221`（移到弹出层第 5 行，Blueberry，序号 4，y ∈ [216,238)）→ `hot` = 4、值仍 0；`up left` → `selected` = 4、`changed` 真、`expect popup 0`。`down left` 于控件、不移动 `up left` → 弹出保持（点击式打开）；再 `move 300 250`、`down left` `up left` 于窗口空白 → 轻关闭、值不变。`down left` 于控件、`move 300 250`、`up left`（释放于弹出层与控件之外）→ 取消并关闭、值不变。`down left` 后移到滚动条/行间空白（`max_rows` = 4 的列表）释放 → 无效果、弹出保持。可编辑变体：按下箭头区 (230,112)、移到第 3 行 (120,177) 释放 → 选中 2；按下文本区 (120,112) 仍保持隐式捕获（`expect captured @E`）并可拖动选择。输入声明（按"输入声明清单"表断言假平台/路由）：下拉列表关闭态按 ↑ 改变选中项而 ← 不被预占（冒泡到外层）；可编辑自动完成 `hot` 为空时 Enter 观察（`committed` 且默认按钮触发），`hot` 非空时 Enter 被预占（接受该项、默认按钮**不**触发）。

**AC-W-COMBOBOX-004**　`[回放]` 覆盖：REQ-W-COMBOBOX-016、REQ-W-COMBOBOX-013、REQ-W-COMBOBOX-022、REQ-W-COMBOBOX-005。`selected` = 0，Tab 聚焦 `@C`：按 ↓ → 1、`changed` 真；按 End → 5；再按 ↓ → 仍 5、`changed` 假；按 Home → 0；按 ↑ → 仍 0。`selected` = `null`：按 ↑ → 仍 `null`；按 ↓ → 0。按 Enter（对话框默认按钮 B）→ B 被触发、`@C` 无变化；按 Esc → 取消按钮被触发；按 Tab → 焦点移走。`@C` 位于可滚动容器内：指针在其上滚动 1 格（关闭态）→ 容器滚动、`selected` 不变；打开态下在弹出层上滚动 → 仅列表滚动。鼠标点击 `@C` 后焦点环不可见，按一次 Shift 后可见；`setImeEnabled(false)`；`selected` 设为 99（越界）→ 显示为空、调试构建 1 条 `warn`、不改写值。

**AC-W-COMBOBOX-005**　`[回放]` 覆盖：REQ-W-COMBOBOX-019、REQ-W-COMBOBOX-020、REQ-W-COMBOBOX-014、REQ-W-COMBOBOX-007。`selected` = 1，Tab 聚焦后按 F4 → 弹出，高亮 1；按 ↓↓ → 高亮 3；按 PageUp → 高亮 0（`visible_rows − 1` ≥ 3 时夹紧）；按 End → 5，再 ↓ → 仍 5；按 Esc → 弹出关闭、`selected` 仍为 1、`changed` 假、弹出关闭后 `@C` 仍持有焦点。再按 Alt+↓ 打开，↓ 后 Enter → `selected` = 2、`changed` 真。再打开，高亮 3 后按 F4 → 确认 3 并关闭（`changed` 真）。打开后指针移动到第 5 行 → 高亮 4、`selected` 不变；随后按 ↑ → 高亮 3（静止的指针不夺回高亮）；再移动指针 → 高亮跟随。打开期间按 Tab、←、→ → 无效果；按 Ctrl+Z（登记为命令快捷键）→ 命令**不**被调用（弹出层吃掉）。点击其他控件（轻关闭）→ 弹出关闭、`selected` 不变、该点击照常作用于被点击的控件；点击窗口外（`popup_dismiss{outside_click}`）→ 同样取消；`activate off` → 取消；打开时宿主 `openDialog` → 取消（`dialog_opened`）。

**AC-W-COMBOBOX-006**　`[回放]` 覆盖：REQ-W-COMBOBOX-017、REQ-W-COMBOBOX-016。`selected` = `null`，聚焦：键入 `a` → 0（Apple，从"当前项的下一项"即 0 起）；200 ms 后再键入 `a` → 缓冲 "aa" 各簇相同视为循环 → 1（Apricot）；再 `a` → 2（Avocado）；再 `a` → 回绕到 0。`advance 1100` 后键入 `a` → 1（缓冲重置后 n = 1，从当前项 0 的下一项起得 Apricot，`changed` 真）；200 ms 后键入 `p` → "ap"：从当前项 1 起含当前项 → Apricot 仍匹配，选中项不变、`changed` 假；再键入 `p` → "app"：Apricot 不匹配，向后绕回 → 0（Apple）、`changed` 真；再键入 `l` → "appl" → 仍 0。`advance 1001` 后键入 `B`（大写）→ 缓冲重置为 "B"，从当前项 0 的下一项起 → 3（Banana）；200 ms 后再 `b` → "Bb"（折叠后各簇相同，视为循环）→ 4（Blueberry）；键入 `z` → 无匹配、选中项不变。恰在 1000 ms 时的第二个字符仍累积，1001 ms 则重置。打开态中键入 `c` → `hot` 移到 5、`selected` 不变，Enter 后才改值。键入空格：缓冲空时在关闭态打开弹出层；缓冲非空时作为字符。设 `double_click_ms` = 300 → 超时变为 600 ms。

**AC-W-COMBOBOX-007**　`[回放]` 覆盖：REQ-W-COMBOBOX-023、REQ-W-COMBOBOX-024、REQ-W-COMBOBOX-012。`@E` 为 `comboBoxEditable`（同位置、同项），`text` = ""。聚焦后键入 `a` → `expect popup 1`，弹出矩形 (100,124,150,74)（匹配 Apple、Apricot、Avocado 三行：3×22 + 8），文本框仍持有焦点（`expect focus @E`），`hot` 空；按 ↓ → 高亮 0；↓ → 1；Enter → 文本 "Apricot"、`picked` = 1、`changed` 与 `committed` 真、弹出关闭、光标 7 且选区折叠；Ctrl+Z → 文本 "a"（列表选中是一步撤销）。清空后键入 `a` 再按 Esc → 弹出关闭、文本 "a" 不变、取消按钮**未**被触发；再按 Esc → 取消按钮被触发。键入 `z` → 无匹配、无弹出；键入 "Apple"（与第 0 项逐字相等，且无其他匹配）→ 无弹出。键入 `a` 后 Backspace 至空 → 弹出关闭。键入 `b` 后 Tab → 弹出关闭、焦点移走、`committed` 真。键入 `a` 后 Alt+↓ → 弹出更换为 `PopupKind.dropdown`（`expect popup 1`，矩形 (100,124,150,140)，抢占键盘），高亮为空（文本 "a" 不与任何项相等）；Esc 关闭；`text` = "Banana" 后 F4 → 高亮 3。点击箭头区 (230,112) → 打开完整列表；点击文本区 (120,112) → 只定位光标、不打开。Tab 进入 → 全选；鼠标点击进入 → 不全选。`autocomplete = false` → 键入不弹出。

**AC-W-COMBOBOX-008**　`[计量]` 覆盖：REQ-W-COMBOBOX-011、REQ-W-COMBOBOX-006、REQ-W-COMBOBOX-008。`@C` 以 `callback` 提供项，`count` 分别为 1 000、10 000、100 000（`text_at` 计数）：同一状态（`max_rows` = 10、`selected` = 0、打开）下 `frame.nodes` 三次读数完全相等；打开与滚动一帧内 `text_at` 调用次数 ≤ 可见行数 + 2（≤ 12）；`selected` = 99 999 打开时 `text_at` 同样 ≤ 12 次，且该行可见；每帧排版的项文字数 ≤ 可见行数 + 1；`count` 在打开期间由 100 000 变为 5 → 无崩溃，`hot`/`selected` 夹紧，弹出层高度随之缩小。

**AC-W-COMBOBOX-009**　`[计量]` 覆盖：REQ-W-COMBOBOX-027、REQ-W-COMBOBOX-028。界面含 100 个组合框。回放：指针移入移出 X → 各帧构建遍数 0，被绘制节点 ⊆ {X 及与损伤相交的祖先}，损伤 ≤ X 的绘制范围；打开 X 后在弹出层内移动指针 → 每个帧的宿主窗口损伤为空、弹出窗口损伤 = 旧高亮行矩形 ∪ 新高亮行矩形；以相同参数再次 `invalidate(.build)` → 损伤为空；仅改变 `placeholder` → 损伤恰为 X 的矩形。

**AC-W-COMBOBOX-010**　`[单元]` 覆盖：REQ-W-COMBOBOX-026、REQ-W-COMBOBOX-004、REQ-W-COMBOBOX-006。经假 UIA 入口：控件类型 ComboBox；`ExpandCollapseState` 随打开/关闭变化；`Expand()` → 弹出打开、`Collapse()` → 关闭且值不变；弹出层中 ListItem 的 `SelectionItem.Select()` → 值改变并关闭；`Value` 为选中项文字，`SetValue("Banana")` → 选中 3，`SetValue("xyz")` 无效果；未构建的行以 VirtualizedItem 暴露。选中项文字被固定宽度截断时悬停超过 `hover_time_ms` → 提示框为完整文字；`max_rows` = 0 按 1 处理；项数为 0 时 F4 不打开。

**AC-W-COMBOBOX-011**　`[人工]` 覆盖：REQ-W-COMBOBOX-007、REQ-W-COMBOBOX-014、REQ-W-COMBOBOX-013、REQ-W-COMBOBOX-017。真实 Windows 10 与 11，多显示器与 125%/150% 缩放：弹出层位置贴合控件下沿，屏幕底部附近翻转到上方，跨显示器时按锚点所在显示器的工作区；弹出层不抢占宿主窗口激活（标题栏保持活动色）；在带滚动条的页面中用滚轮滚过组合框，页面平滑滚动且值不变；对照原生 ComboBox 的类型预搜索节奏与自动完成体验，记录差异。

## 17. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-W-COMBOBOX-01 | **关闭态滚轮不改变值**是有意偏离 Windows 原生（原生下拉列表获得焦点后滚轮会切换选中项） | 保持不改值，避免滚动页面时误改；若用户期望原生行为，可增加选项 `wheel_changes_value`，默认 `false` |
| OPEN-W-COMBOBOX-02 | 类型预搜索超时 = `2 × double_click_ms` 的倍数 | 倾向 2（500 ms 系统下为 1000 ms，与 Windows 列表框类型预搜索节奏接近）；需实机对照 |
| OPEN-W-COMBOBOX-03 | F4、Alt+↑、Alt+↓ 在打开态是"确认高亮项"还是"取消" | 倾向确认（Windows 中选中项随方向键实时移动，关闭即保留）；风险是鼠标悬停造成的高亮被误确认，需评审 |
| OPEN-W-COMBOBOX-04 | 项是否支持禁用、分隔线、图标、分组标题 | 不在本版；需要时扩展 `ItemSource` 为带属性的项 |
| OPEN-W-COMBOBOX-05 | 下拉列表关闭态外观取凸起（按钮式）而非内凹 | 倾向凸起，以区别可编辑的文本框；09 把"下拉"与"输入框"并列在 `pad_input_x` 条下，需 M3 评审确认 |
| OPEN-W-COMBOBOX-06 | 按下-拖动-释放选中（Windows 原生支持） | **已采用**：下拉列表与可编辑箭头区声明 `capture_on_press = false`（08 REQ-INPUT-013），行为见 REQ-W-COMBOBOX-012、REQ-W-COMBOBOX-015 |
| OPEN-W-COMBOBOX-07 | 自动完成采用"前缀匹配"，不含子串/拼音首字母匹配 | 不在本版；匹配策略后续可作回调选项 |
| OPEN-W-COMBOBOX-08 | 自动完成"唯一匹配且等于文本时不显示"的规则 | 保持；避免用户键入完整项后仍遮挡 |
| OPEN-W-COMBOBOX-09 | 弹出层悬停行使用 `hover_rebuild`（build 级）以保存高亮状态 | 倾向接受（仅在弹出层打开期间）；若 12 的预算受影响，改为纯绘制高亮并仅在键盘/点击时写入 `hot` |
