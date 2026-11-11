# 多行文本区（text-area）

> 本文引用 text-input.md 的编辑核心（光标与选区模型、键位语义、撤销栈规则、剪贴板净化、输入法组字、光标绘制与闪烁），**只写差异**。凡本文未提及者，按 text-input.md 的对应条款执行；条款中的"缓冲"在本文均指文档（`TextDoc`），"光标/选区偏移"均为文档的字节偏移。

## 1. 用途

编辑多行文本：备注、日志、脚本、配置文件、聊天输入。参照 Windows 的 Edit（`ES_MULTILINE`）。

- 单行输入 → 用 text-input。
- 只读的大段文字展示且无需光标 → 用 label 的多行形式或带滚动的容器。
- 语法高亮、代码折叠、多光标不在范围；行号栏列为待定问题。

**值的所有权与"为何不由应用持有整块缓冲"**：text-input 的值是应用持有的 `TextBuf`，因为单行文本短、每次构建把整块缓冲交给控件代价可忽略。多行文本区不同：(1) 文档可达 10 MB、20 万行（12 的预算 REQ-PERF-023、REQ-PERF-024），一次按键只改一行，若由应用持有一整块连续缓冲，则每次插入都需要移动其后的全部字节（均摊 O(n)），且控件无法维护"行起点索引、行高缓存、撤销栈"与缓冲的一致性——应用任意改缓冲都使这些缓存整体失效；(2) 应用每帧把大缓冲的切片传给控件，既没有变更范围信息，也无法做增量重排；(3) 撤销栈要引用被删除的文本，由控件持有文档才能保证引用有效。因此**文档由保留节点持有**（ADR 0005：重型控件拥有长寿命对象，应用只通过句柄读写），应用以句柄做载入、读取、范围替换与变更监听。

## 2. 解剖

```
        ┌─ 焦点环（恒显示）
┌───────────────────────────────────┬─┐
│ 文本区（视口，裁剪）                  │▲│   容器 = drawSunken
│ 第 1 行 …                            │ │   滚动条（纵向，auto：内容超出时出现，
│ 第 2 行 …（自动换行时折为多个视觉行）  │ │   不换行时另有横向滚动条）
│                                      │▼│
└───────────────────────────────────┴─┘
```

- **容器**：内凹表面。
- **文本区**：视口 + 滚动内容，内容为文档的可见行。
- **滚动条**：纵向，不自动换行时另有横向；行为见 scroll-view.md。
- **占位文字**（可选）：文档为空时显示。

## 3. 度量与布局

| 项 | 取值（令牌） |
|---|---|
| 最小高度 | `control_h`（单行高度）加垂直内边距；通常由调用方指定 |
| 最小宽度 | `button_min_w` |
| 内边距 | 水平 `pad_input_x`，垂直 `gap_sm`（相对视口内缘） |
| 文字样式 | `font_body`；`mono = true` 时 `font_mono` |
| 行高 | 所用文字样式的令牌行高（`font_body` 在 B = 12 时为 16） |
| 滚动条 | 显示策略 `auto`（07）：内容超出视口时出现并占用 `scrollbar_w`（从视口中扣除，不覆盖内容），否则不占位 |
| 绘制外延 | `focus_ring_w` |

**REQ-W-TEXTAREA-001**　默认尺寸策略：主轴 `grow(1)`，交叉轴 `fill`，最小尺寸 `button_min_w × control_h`。调用方**可以**经 `layout` 覆盖。文本区的内容节点位于一个 Scroll 容器内（07），Scroll 的视口为容器内缩一个发丝线边框；纵向滚动条显示策略 `auto`（内容超出时出现并占用 `scrollbar_w`，否则不占位），不自动换行时横向滚动条同为 `auto`，自动换行时横向不滚动。滚动条与滚轮、拖拽滑块、点击槽等行为引用 scroll-view.md。

**REQ-W-TEXTAREA-002**　自动换行（`wrap = .word`）的排版宽度 = 视口宽度（已扣除纵向滚动条占位）− 2 × `pad_input_x`；视口宽度变化（含滚动条出现或消失）时重排。换行规则遵循 REQ-TEXT-016（含超长无空格串在字素簇边界强制断行）。`wrap = .none` 时排版宽度不限，内容宽度取已测量各行的最大宽度（REQ-W-TEXTAREA-010）。

## 4. 变体与参数

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `wrap` | `enum { none, word }` | `.word` | 是否自动换行 |
| `accepts_tab` | `bool` | `false` | 为真时 Tab 插入制表符，Ctrl+Tab 仍做焦点导航 |
| `read_only` | `bool` | `false` | 同 text-input.md 的只读 |
| `placeholder` | `?[]const u8` | `null` | 占位文字（文档为空时显示） |
| `mono` | `bool` | `false` | 使用 `font_mono` |
| `tab_width` | `u8` | `4` | 制表位宽（空格数，05 的 `tab_width`） |
| `max_bytes` | `?u64` | `null` | 文档字节数上限（本文不按字素簇计，避免 O(n) 计数） |
| `tooltip` | `?[]const u8` | `null` | 悬停提示 |
| `enabled`、`key`、`debug_name`、`layout` | 通用 | | 见模板 |

无 `password`、`clearable`、`invalid`、`commit_on_blur`、`commit_unchanged`、`accept`、`max_len`：多行文本区没有这些行为（`invalid` 的图标布局与单行绑定，见待定问题）。

**REQ-W-TEXTAREA-003**　文本由**保留节点** `TextDoc` 持有（`ui.retained(TextDoc, id, .pinned)`，REQ-FRAME-011：`pinned` 级槽**不**参与 sticky 的 LRU 回收）。`TextDoc` 提供：载入、取全文、取范围、替换范围、监听变更（第 12 节）。应用不持有文本缓冲；应用要读取或修改文本，经 `TextAreaHandle`（即该文本区的 `WidgetId`）调用 `w.textArea*` 函数，这些函数在界面线程、构建遍或命令处理函数内调用均可。文档槽在文本区暂时不被声明期间保留。`pinned` 槽只在两种情形回收：应用调用 `ui.forget(id)`，或窗口关闭。**何时由应用 `ui.forget`**：应用关闭该文档（如关闭标签页或编辑器面板）且已保存或决定丢弃时，应用在调用 `textAreaText` 取走内容并确认 `modified` 为假（或用户选择不保存）之后调用 `ui.forget(id)` 释放文档；文本区只是暂时不被声明（如切换到别的标签页）时**不得**调用。未调用 `forget` 的文档在窗口关闭前一直占用内存，由应用负责。

**REQ-W-TEXTAREA-004**　**存储结构**：文档为**按行分块**的结构。每块（chunk）存储连续若干逻辑行的文本（UTF-8，行间以单个 `\n` 分隔），块内行数不超过 `chunk_max_lines = 128` 且字节数不超过 `chunk_max_bytes = 16 KiB`（单行超过 `chunk_max_bytes` 时该行独占一块）；每块附带行起点偏移表与摘要 `{字节数, 行数, 高度和, 最长行字节数}`。各块摘要由一棵平衡树（或等价的 Fenwick 索引）索引，使"偏移 → 行""行 → 偏移""行 → 纵向位置""纵向位置 → 行"均为 O(log 块数)。块内插入/删除只移动该块内的字节（≤ `chunk_max_bytes`）；块超限时分裂，过小（< 1/4 容量）且相邻块可并时合并。

**REQ-W-TEXTAREA-005**　**换行符**：内部统一为 LF。载入时扫描全文：把 `\r\n` 与孤立 `\r` 都规范为 `\n`，同时统计三种风格出现次数，记住出现最多者为 `eol`（`lf`/`crlf`/`cr`，平局取 `lf`），三种并存时置 `mixed = true`；无任何换行时 `eol = lf`。开头的 UTF-8 BOM 被剥离并记为 `had_bom`。取全文（`textAreaText`）默认以记住的 `eol` 还原换行（并按 `bom` 选项决定是否加回 BOM），也可显式指定。用户键入的换行恒为 `\n`；粘贴内容中的 `\r\n`、`\r`（03 已规范为 `\n`）同样按 `\n` 处理；Unicode 行分隔符 U+2028、U+2029、U+0085 不是文档的行分隔符，按普通字符保存，排版时每个显示为一个空格（`newlines = .as_space`，每个逻辑行单独排版）。

**REQ-W-TEXTAREA-006**　`textAreaLoad(bytes)` 取代文档全部内容：清空撤销栈与重做栈，选区与光标置 0，`modified` 置假，滚动回到顶部，向监听者报告一次 `source = .load` 的变更。载入**必须**满足 12 的预算：10 MB、20 万行的文档 ≤ 200 ms（REQ-PERF-024，计时器 `time.text_load`，计载入调用从进入到返回，不含首次排版与绘制）。实现约束：单趟扫描（用向量化的换行搜索）切块、规范换行与统计 `eol`；**不**在载入时验证 UTF-8、**不**排版任何行、**不**为每行分配对象；非法 UTF-8 保持原样，显示时按 REQ-TEXT-003 替换。文档字节数超过 `max_doc_bytes = 1 GiB` 或 `max_bytes` 时返回 `error.TooLarge` 且文档不变。

**REQ-W-TEXTAREA-007**　**只对可见行排版**：每帧只对与视口相交的逻辑行（含部分可见的行）调用排版（`text.layoutOwned`，按行为段，REQ-TEXT-005 的"按段落分段排版"），结果存入文本区自己的**行排版缓存**（容量上限 `layout_cache_lines = 512` 行，LRU）；不在视口内的行不排版。行的文本变化或排版宽度变化使对应缓存项失效。段（一个逻辑行）长度超过 `text.max_layout_bytes` 时，在字素簇边界按 262 144 字节切成多个排版段，显示为连续的多个视觉行。

**REQ-W-TEXTAREA-008**　**行高缓存**：不换行时每个逻辑行恰一个视觉行，高度 = 行高，无需缓存。自动换行时每个逻辑行的视觉行数取决于排版宽度；块摘要的"高度和"保存各行视觉行数之和：已排版过的行取精确值；**未排版**的行取估计值 `1 + floor(行字节数 × 平均簇宽估计 / 排版宽度)`（平均簇宽估计取已排版行的运行均值，初值为 `font_body` 的 "0" 字宽）。排版宽度变化使所有精确值降级为估计值（只对可见行立即重新精确化）。可见行排版后，若其精确值与估计值不同，更新摘要。

**REQ-W-TEXTAREA-009**　**滚动锚定**：滚动位置的内在表示为 `{top_line, top_offset}`（视口顶端所对应的逻辑行与行内视觉偏移，lpx），而不是总像素偏移；总高度与像素偏移由块摘要推出。因此当上方未排版行的估计高度被精确值替换时，视口显示的内容不跳动（按 `top_line` 重新定位）。滚动条滑块位置与长度基于摘要（估计值）计算，允许在行高精确化后有小幅变化。**大内容坐标与行虚拟化**（REQ-LAYOUT-054）：文本区内容总高度可达 20 万行 × 行高以上乃至更大，因此文本区经 `ScrollParams.virtual_extent_px` 声明内容总范围（由块摘要推出，64 位 ppx，上限 2^53），用 `ScrollParams.offset_px`（由 `top_line`/`top_offset` 换算）请求偏移，并从 `ScrollMetrics.offset_px` 取权威偏移；只为与视口相交的可见行创建节点，各行节点以**相对视口**的整数 ppx 位置（子项的 `virtual_pos_px`）排布，使节点矩形坐标量级不超过视口尺寸加缓冲、`f32` 可精确表示。节点数与文档行数无关。

**REQ-W-TEXTAREA-010**　`wrap = .none` 时内容宽度（横向滚动范围）= 已排版过的各行宽度的最大值，与块摘要中"最长行字节数"对应的那一行的宽度（该行在文档载入或编辑后首次被视口需要时、或在帧空闲时单独排版一次）二者中较大者，并且只增不减（直到下次载入）；因此未滚到最长行之前横向滚动范围可能略小，滚到之后扩大。

**REQ-W-TEXTAREA-011**　**增量重排范围**：一次编辑只使被编辑的逻辑行（及被合并/拆分出的相邻行）的排版缓存失效，并重新排版其中与视口相交的部分；其下各行的内容与排版不变，只是纵向位置整体平移。编辑使该行视觉行数不变时，损伤为该行的视觉行矩形（行内换行时该逻辑行的全部视觉行）；视觉行数改变或插入/删除了换行时，损伤为从该行起到视口底部。滚动范围、滚动条随摘要更新。

**REQ-W-TEXTAREA-012**　在 S-TEXT-KEY 场景（10 MB、20 万行、已聚焦、每帧一次字符键按下与释放）中，每次按键产生的帧的 `time.frame_cpu` 的 P99 **必须** ≤ 2.0 ms（REQ-PERF-023）。为此：每次按键的帧**至多**对 2 个逻辑行排版（被编辑行与其紧邻的、因光标跨行而需要的相邻行）；块内字节移动 ≤ `chunk_max_bytes`；摘要更新 O(log 块数)；撤销步的记录（REQ-W-TEXTAREA-028）O(插入/删除字节数)；绘制只触及与损伤相交的可见行。

## 5. 状态

### 5.1 状态机

状态变量同 text-input.md 的状态机（焦点、鼠标选择、组字、菜单），差异如下：

| 当前 | 事件 | 条件 | 下一状态 | 动作 |
|---|---|---|---|---|
| 无焦点 | 左键按下 | 启用 | 有焦点 / 鼠标选择（字符、词或段） | 取焦点（不全选）；`clicks` 为 1/2/3 分别定位光标、选词、选段落 |
| 鼠标选择 | `pointer_move` / 定时器到期 | 指针在视口外 | 同 | 纵向与（不换行时）横向自动滚动并推动光标（REQ-W-TEXTAREA-017） |
| 有焦点 | 失去焦点 | — | 无焦点 | 光标隐藏；**选区保留**并以非活动色显示；**不**报告任何提交 |
| 有焦点 | Enter | — | 同 | 在光标处插入 `\n`（替换选区），`changed` |
| 有焦点 | Tab | `accepts_tab` 真 | 同 | 插入 `\t`（替换选区） |
| 有焦点 | Tab | `accepts_tab` 假 | 无焦点 | 焦点导航（REQ-INPUT-035） |

### 5.2 视觉表现

| 状态 | 绘制（基元 + 令牌） |
|---|---|
| 常态 / 悬停 / 聚焦 / 禁用 / 只读 | 同 text-input.md（`drawSunken`、`text_primary`、`accent_mark` 边框与 `drawFocusRing`、`text_disabled`） |
| 选区（有焦点且窗口活动） | `drawSelection(rect, true)`，选区内文字 `text_on_accent` |
| 选区（无焦点或窗口非活动） | **保留显示**：`drawSelection(rect, false)`（`surface_selection_inactive`），文字保持 `text_primary` |
| 光标 | 同 text-input.md，只在有焦点、窗口活动、选区为空时显示 |
| 行尾换行符 | 选区跨越换行时，该行矩形向右延伸一个空格宽度（`SelectionOpts.extend_line_breaks = true`） |
| 占位文字 | `text_placeholder`，从文本区左上角起、按排版宽度换行 |

**REQ-W-TEXTAREA-013**　失去焦点或窗口失去激活时，**保留**并显示选区（`drawSelection(…, false)`），不显示光标；这与单行文本框相反（后者不显示非活动选区）。选区矩形取自 `layout.selectionRects`，逐可见行计算，不可见行不计算。

**REQ-W-TEXTAREA-014**　光标与光标闪烁、编辑后重置为"亮"的规则同 REQ-W-TEXTINPUT-016、REQ-W-TEXTINPUT-017、REQ-W-TEXTINPUT-018：光标是文本区的**独立子叶节点**，闪烁用 `paint` 级 `ui.timer(caret_id, caret_blink_ms, .paint)`，每次编辑或光标移动后调用 `ui.timerRestart(caret_id)`；光标矩形取自当前行排版的 `caretRect` 加行位置（相对视口），在软换行位置遵循亲和性（REQ-TEXT-019）。闪烁帧是纯绘制帧，**损伤恰为光标叶节点矩形**（发丝线宽 × 行高）。

## 6. 鼠标行为

文本区登记 `click`、`drag`、`context`、`wheel`；指针形状为 `ibeam`。

**REQ-W-TEXTAREA-015**　单击、Shift+单击、拖动选择、右键与上下文菜单、中键遵循 REQ-W-TEXTINPUT-020、REQ-W-TEXTINPUT-021、REQ-W-TEXTINPUT-022、REQ-W-TEXTINPUT-026、REQ-W-TEXTINPUT-028，差异：定位用二维 `hitTest`（先按 y 选视觉行，再按 x 选簇）；不换行时按 y 超出文本末行取末行、低于首行取首行；中键仍不处理。上下文菜单项同 REQ-W-TEXTINPUT-027（"撤销"以文档撤销栈为准）。

**REQ-W-TEXTAREA-016**　双击选词（`text.wordRange`，在所在逻辑行的文本内求）并按词扩展拖动，同 REQ-W-TEXTINPUT-024；**三击选段落**：选中所在**逻辑行**，包含其行尾的换行符（末行无换行符则到文末）；三击后拖动按段落为单位扩展。第 4 次按下重新计 1。

**REQ-W-TEXTAREA-017**　拖动选择时指针在视口上/下/左/右之外，按 REQ-W-TEXTINPUT-023 的规则（节拍取令牌 `dur_autoscroll`（50 ms），每拍移动 `min(d, 视口该轴尺寸 / 2)`，至少 1 ppx）在相应轴向自动滚动并推动光标；自动滚动经 scroll-view.md 的程序化滚动接口施加偏移。

**REQ-W-TEXTAREA-018**　滚轮事件由文本区作为滚动容器处理：纵向按 `SystemMetrics.wheel_lines`（取 `.page` 时滚动视口高度减一行）每格滚动，Shift+滚轮或横向滚轮在可横向滚动时按 `wheel_chars` 滚动；滚动到边界后不再消费（继续冒泡）。滚动不移动光标。细节（惯性无、最小单位 1 ppx、禁用时的行为）见 scroll-view.md。

## 7. 键盘行为

编辑核心的全部键位按 text-input.md 第 7 节执行（← → Ctrl+← Ctrl+→ Home End Shift 扩展、Ctrl+A、Backspace/Delete、Ctrl+Backspace/Delete、剪贴板键、撤销与重做），差异与新增如下：

| 键 | 行为 |
|---|---|
| Enter、Shift+Enter | 在光标处插入 `\n`（有选区则替换选区） |
| Ctrl+Enter | **不预占、不处理**：继续向后级传递（冒泡，可被应用登记为"提交"之类的命令快捷键，第 ④ 级）；不插入换行 |
| ↑ / ↓ | 按**视觉行**上/下移动光标，保持目标列（`goal_x`）；首行 ↑ 到偏移 0，末行 ↓ 到文末；有选区且无 Shift 时折叠到选区起点/终点后再移动一行 |
| Shift+↑ / Shift+↓ | 同上但扩展选区 |
| Home / End | 移到**视觉行**行首/行末（软换行行的行末取最后一个非悬挂空白簇之后）；Shift 扩展 |
| Ctrl+Home / Ctrl+End | 移到文档开头/末尾；Shift 扩展 |
| PageUp / PageDown | 光标与视口各移动 `page_rows = max(1, floor(视口高 / 行高) − 1)` 个视觉行，保持目标列；Shift 扩展 |
| Ctrl+↑ / Ctrl+↓ | 视口上/下滚动一个行高，光标不动 |
| Tab | `accepts_tab` 真：插入制表符（替换选区），Shift+Tab 与 Ctrl+Tab、Ctrl+Shift+Tab 仍为焦点导航；假：焦点导航 |
| Esc | 不处理（冒泡到取消按钮）；组字期间由输入法处理 |
| Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z | 撤销/重做文档编辑 |
| Insert（单独） | 不处理，不支持改写模式 |

**REQ-W-TEXTAREA-019**　控件的预占（REQ-INPUT-028；`KeyGroups` 只匹配无修饰或仅带 Shift 的键，Ctrl/Alt 组合须在 `extra` 逐个列出）：`groups.printable`、`arrows`、`home_end`、`page`、`enter`、`backspace_delete`；`extra` 逐个列出——←、→、↑、↓ 的 Ctrl 变体（Ctrl+←→ 按词，Ctrl+↑↓ 滚动）及 Ctrl+Shift 变体（←→）；Ctrl+Home、Ctrl+End 及其 Shift 变体；Ctrl+Backspace、Ctrl+Delete；Ctrl+A、Ctrl+C、Ctrl+V、Ctrl+X、Ctrl+Z、Ctrl+Y、Ctrl+Shift+Z、Ctrl+Insert、Shift+Insert、Shift+Delete；`accepts_tab` 真时再在 `extra` 加**无修饰**的 Tab（不用 `groups.tab`，因其会连带 Shift+Tab）。**不预占**：Esc、Ctrl+Enter、Shift+Tab、Ctrl+Tab、Ctrl+Shift+Tab、Insert、功能键、Ctrl+PageUp/PageDown。`text_input = true`，`ime` 在可编辑时为 `true`、只读时为 `false`。无修饰的 Enter 与 Shift+Enter（`groups.enter`）是预占（插入换行），不是观察；**Ctrl+Enter 不预占**。

**REQ-W-TEXTAREA-020**　↑/↓ 与 PageUp/PageDown 使用 `layout.moveVertical(caret, dir, goal_x)`（REQ-TEXT-023）：目标列 `goal_x` 在连续的垂直移动之间保持不变，任何水平移动、编辑、点击、Home/End 使其重置为当前光标 x；跨逻辑行时对相邻逻辑行做一次排版（若不在缓存中）。例：文档 `"abcdefghij\nab\nabcdefghij"`，光标在第 0 行第 8 簇（偏移 8），↓ 到第 1 行行末（偏移 13），再 ↓ 到第 2 行第 8 簇（偏移 22）；↑ 两次回到偏移 8。

**REQ-W-TEXTAREA-021**　PageDown：光标向下 `page_rows` 个视觉行（不足则到末行），视口纵向位置同样增加 `page_rows × 行高`（夹紧到最大偏移），随后若光标仍不可见则最小位移使其可见；PageUp 对称。光标已在首/末行时 PageUp/PageDown 分别移到偏移 0/文末。

**REQ-W-TEXTAREA-022**　无修饰的 Enter 与 Shift+Enter 插入 `\n`，不触发所在范围的默认按钮（控件预占，REQ-INPUT-028）；不做自动缩进。**Ctrl+Enter 不被预占、不被处理**：它不插入换行，按 08 的路由继续向后级传递（先查命令快捷键表，应用可把它登记为"提交"等命令；无人处理则被丢弃，**不**触发默认按钮，因第 ⑦ 级只处理无修饰的 Enter）。键入换行属于"键入"类编辑，可与相邻键入合并（遇光标移动等断开）。

**REQ-W-TEXTAREA-023**　`accepts_tab = true` 时无修饰的 Tab 插入一个 `\t`（有选区则替换选区，不做多行缩进）；Shift+Tab 不被预占，按 REQ-INPUT-035 做焦点导航；**Ctrl+Tab / Ctrl+Shift+Tab** 不被预占，先按第 ⑤ 级交给焦点节点的祖先处理（标签页用它切换页），无人处理时按 REQ-INPUT-035 以 Tab / Shift+Tab 的规则移动焦点，使预占了 Tab 的文本区仍可用键盘离开。`accepts_tab = false` 时 Tab 不被预占。

**REQ-W-TEXTAREA-024**　光标移动、编辑、组字更新后保证光标可见：纵向以光标所在视觉行矩形、横向（不换行时）以光标矩形加边距 `gap_sm`，经 scroll-view.md 的"使矩形可见"接口（07 的 `ScrollParams.reveal`）按最小位移实现。鼠标拖动选择期间暂停（由自动滚动接管）。

## 8. 焦点

**REQ-W-TEXTAREA-025**　可聚焦、Tab 停靠（`accepts_tab` 真时 Tab 被控件占用，仍可由 Shift+Tab 与 Ctrl+Tab 离开）。因 `tab`、`mnemonic`、`initial`、`programmatic`、`transfer` 获得焦点时**不**全选，光标与选区保持（与单行不同：编辑大段文本时 Tab 进入不应选中全部）；鼠标点击获得焦点时按点击定位。失去焦点：隐藏光标，**保留选区并以非活动色显示**（REQ-W-TEXTAREA-013），滚动位置保持；**不因失焦报告任何提交**（多行文本区没有 `committed`）；组字中则先提交（REQ-INPUT-063）。

## 9. 文本与输入法

**REQ-W-TEXTAREA-026**　输入法契约同 REQ-W-TEXTINPUT-051、REQ-W-TEXTINPUT-052、REQ-W-TEXTINPUT-053、REQ-W-TEXTINPUT-054、REQ-W-TEXTINPUT-055：组字串只在**显示**中临时插入光标所在逻辑行（该行单独重新排版一次），文档在组字期间不被修改；选区被组字串虚拟替换，取消时原样恢复；`ime_commit` 提交串中的换行保留为 `\n`（多行文本区的净化不替换换行）；每次构建报告 `ui.imeCaret`（含纵向滚动与行位置）。

**REQ-W-TEXTAREA-027**　粘贴净化为 REQ-W-TEXTINPUT-039 的变体：(1) 换行统一为 `\n`（`\r\n`、`\r`、U+0085、U+2028、U+2029 → `\n`）并**保留**；(2) 制表符保留；(3) 其余控制字符（U+0000–U+0008、U+000B、U+000C、U+000E–U+001F、U+007F、U+0080–U+009F 除 U+0085）删除；(4) 非法 UTF-8 按 REQ-TEXT-003；(5) 按 `max_bytes` 在字素簇边界截断。粘贴大文本（≥ `chunk_max_bytes`）时按块一次性插入，不逐字符处理。键入字符的过滤同 REQ-W-TEXTINPUT-037（控制字符忽略，Enter 与 Tab 由各自键位处理）。

**REQ-W-TEXTAREA-028**　撤销栈规则同 REQ-W-TEXTINPUT-042、REQ-W-TEXTINPUT-043，差异：(1) 栈存于文档（保留节点），随文档存活；(2) 容量上限 `undo_max_steps = 1000`、`undo_max_bytes = 16 MiB`，超限丢弃最旧步；单步超过上限（如粘贴 20 MB）该步不入栈并清空栈；(3) 键入换行并入连续键入的合并（同一光标处连续的键入含换行）；(4) 应用经 `textAreaReplace` 的修改**不入撤销栈**且**清空**撤销栈与重做栈，光标与选区夹紧；(5) 载入清空两栈。撤销/重做后光标恢复到记录的编辑前/后位置，并保证可见。

**REQ-W-TEXTAREA-029**　读取接口：`textAreaText` 返回全文（拷贝到调用方分配器，换行按 `eol` 还原）；`textAreaRange(start, end)` 返回字节范围（`start ≤ end ≤ 文档长度`，换行为 `\n`，不做 `eol` 还原；偏移须在字素簇边界，否则调试构建断言、发布构建向下对齐，REQ-TEXT-002）。两者的耗时与取出的字节数成正比，不依赖文档总大小（范围读取经块树定位）。返回的内存归调用方。

**REQ-W-TEXTAREA-030**　`textAreaReplace(start, end, bytes)` 以 `bytes` 替换范围：换行规范为 `\n`，其余同 `textAreaLoad` 的规范化；清空撤销栈；报告 `source = .api` 的变更；光标与选区按位置平移（位于被替换范围之后者平移，之内者夹紧到插入内容末尾）。`modified` 置真。

**REQ-W-TEXTAREA-031**　`textAreaSubscribe(fn, ctx)` 登记变更监听，`fn(ctx, Change)` 在每次文档内容改变后**同步**调用（界面线程，在改变发生的构建遍内、`changed` 之前），`Change = { start, removed, inserted, source, revision, line }`（偏移与长度为字节，`line` 为起始行号）。监听函数内**不得**再调用修改文档的接口（调试构建断言，发布构建忽略该调用）。可登记多个监听，`textAreaUnsubscribe` 取消；文本区不再被声明且文档槽被回收时监听被丢弃。

## 10. 动效

| 属性 | 触发 | 时长令牌 | 缓动 | 影响级别 |
|---|---|---|---|---|
| 容器边框、焦点环 | 悬停/焦点变化 | `dur_fast` | `ease_out` | paint |
| 光标 | 闪烁 | 无 | — | paint（定时器） |
| 滚动 | 滚轮、键盘、拖动 | 无（瞬时，不做平滑滚动） | — | build（`layout` 级，07） |

## 11. 无障碍

| 项 | 值 |
|---|---|
| UIA 控件类型 | Edit（多行，`IsMultiline`；文档较大时仍为 Edit） |
| 名称来源 | 同 text-input.md |
| 支持的模式 | Value、Text（以及随滚动容器提供的 Scroll） |
| 状态属性 | IsEnabled、HasKeyboardFocus、ValueIsReadOnly |

**REQ-W-TEXTAREA-032**　Value 模式的 `Value` 为全文（超过 1 MiB 时返回前 1 MiB 并经 Text 模式提供完整访问）；Text 模式以文档为范围，行、段落、字素簇、词的移动与可见范围由块树与行排版缓存支持，`GetBoundingRectangles` 只对可见行有值；`SetValue` 等同 `textAreaReplace(0, 末尾, …)`。选区与光标行为同 REQ-W-TEXTINPUT-056。

## 12. API 草案

```zig
// 草案：仅签名
pub const Eol = enum { lf, crlf, cr };
pub const TextAreaWrap = enum { none, word };

pub const TextAreaOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    wrap: TextAreaWrap = .word,
    accepts_tab: bool = false,
    read_only: bool = false,
    placeholder: ?[]const u8 = null,   // 借用至本帧结束
    mono: bool = false,
    tab_width: u8 = 4,
    max_bytes: ?u64 = null,
    tooltip: ?[]const u8 = null,
    layout: layout.ItemOptions = .{},
};

pub const TextAreaHandle = struct { id: WidgetId };   // 句柄：等于文本区控件的 WidgetId

pub const TextAreaResult = struct {
    handle: TextAreaHandle,
    // 持续性状态
    hovered: bool,
    focused: bool,
    composing: bool,
    selection: DocRange,         // 只读，start ≤ end
    caret: u64,
    caret_line: u32,             // 0 起
    caret_column: u32,           // 0 起，按字素簇计
    modified: bool,              // 自上次载入或 textAreaMarkSaved 起是否改动
    // 激活类结果
    changed: bool,               // 用户编辑、撤销、重做使内容改变
};
pub const DocRange = struct { start: u64, end: u64 };

pub fn textArea(ui: *Ui, src: std.builtin.SourceLocation, opts: TextAreaOptions) TextAreaResult;

// —— 文档句柄接口（界面线程；句柄所指文本区从未被声明过时，载入会创建文档槽）——
pub const LoadInfo = struct { eol: Eol, mixed: bool, had_bom: bool, lines: u32, bytes: u64 };
pub const SaveOptions = struct { eol: ?Eol = null, bom: ?bool = null };   // null = 沿用载入时记住的值
pub const TextAreaError = error{ OutOfMemory, TooLarge };

pub fn textAreaLoad(ui: *Ui, h: TextAreaHandle, bytes: []const u8) TextAreaError!LoadInfo;
pub fn textAreaText(ui: *Ui, h: TextAreaHandle, allocator: std.mem.Allocator, opts: SaveOptions) error{OutOfMemory}![]u8;
pub fn textAreaRange(ui: *Ui, h: TextAreaHandle, start: u64, end: u64, allocator: std.mem.Allocator) error{OutOfMemory}![]u8;
pub fn textAreaReplace(ui: *Ui, h: TextAreaHandle, start: u64, end: u64, bytes: []const u8) TextAreaError!void;
pub fn textAreaInfo(ui: *const Ui, h: TextAreaHandle) ?struct { bytes: u64, lines: u32, revision: u64, eol: Eol, modified: bool };
pub fn textAreaMarkSaved(ui: *Ui, h: TextAreaHandle) void;
pub fn textAreaSetSelection(ui: *Ui, h: TextAreaHandle, anchor: u64, caret: u64) void;   // 构建完成后生效

pub const ChangeSource = enum { user, api, undo, redo, load };
pub const Change = struct { start: u64, removed: u64, inserted: u64, source: ChangeSource, revision: u64, line: u32 };
pub const ChangeFn = *const fn (ctx: ?*anyopaque, change: Change) void;
pub const Subscription = enum(u32) { _ };
pub fn textAreaSubscribe(ui: *Ui, h: TextAreaHandle, f: ChangeFn, ctx: ?*anyopaque) error{OutOfMemory}!Subscription;
pub fn textAreaUnsubscribe(ui: *Ui, h: TextAreaHandle, s: Subscription) void;
```

`changed` 为激活类结果。文档由保留节点持有；传入的 `bytes` 借用至调用返回，框架复制；`textAreaText`、`textAreaRange` 返回的内存由调用方以所传分配器释放。

## 13. 保留状态

| 字段 | 类型 | 保留级别 | 说明 |
|---|---|---|---|
| `doc` | `TextDoc`（块树、行起点表、摘要、`eol`、`mixed`、`had_bom`、`revision`、`modified`） | 保留节点，`Retain.pinned`（不被 LRU 回收，仅 `ui.forget` 或窗口关闭时回收） | REQ-W-TEXTAREA-004 |
| `undo`、`redo`、`merge` | 同 text-input.md，容量见 REQ-W-TEXTAREA-028 | 保留节点 | |
| `anchor`、`caret`、`affinity`、`goal_x` | `u64`、`u64`、`Affinity`、`?f32` | sticky | 选区与目标列 |
| `top_line`、`top_offset`、`scroll_x` | `u32`、`f32`、`i32` | sticky | 滚动锚定（REQ-W-TEXTAREA-009） |
| `line_cache` | 行排版缓存（≤ 512 行，LRU） | sticky（可丢弃，重建代价为可见行排版） | REQ-W-TEXTAREA-007 |
| `content_w` | `f32` | sticky | 不换行时的内容宽度（只增） |
| `blink_epoch`、`comp`、`drag`、`autoscroll` | 同 text-input.md | transient | |
| `listeners` | 监听表 | 保留节点 | |

## 14. 失效规则

**REQ-W-TEXTAREA-033**　绘制键**必须**由以下各项构成：文档 `revision`、锚点与光标偏移、`top_line`/`top_offset`/`scroll_x`、排版宽度、`wrap`、`mono`、`tab_width`、组字串与片段、`placeholder`、`read_only`、`enabled`、有焦点、窗口是否活动、焦点可见。不含光标亮灭相位。布局输入的内容度量键由文档 `revision`、排版宽度（自动换行时）、字体样式构成。

| 变化 | 置脏级别 | 损伤范围 |
|---|---|---|
| 悬停、焦点环 | `paint` | 文本区绘制范围 |
| 光标闪烁 | `paint` | 光标矩形 |
| 键入/删除（视觉行数不变） | `build` | 被编辑逻辑行的视觉行矩形 |
| 键入换行、删除换行、换行引起视觉行数改变 | `build` | 自被编辑行起到视口底部 |
| 选区移动 | `build` | 新旧选区所在可见行 |
| 滚动 | `layout`（滚动偏移不入布局哈希，07） | 视口 |
| 视口尺寸变化（自动换行） | `layout` | 整个文本区 |
| 应用 `textAreaReplace`/`textAreaLoad` | `build` | 视口（载入）或变更行起到视口底部 |

**REQ-W-TEXTAREA-034**　仅悬停进入/离开与仅光标闪烁产生的帧为纯绘制帧（构建遍数 0），损伤分别不超出文本区绘制范围、**恰为光标叶节点矩形**。

## 15. 边界与错误情况

| 情况 | 规定 |
|---|---|
| 文档为空 | 一个空逻辑行；占位文字显示；偏移 0 |
| 文档以 `\n` 结尾 | 末尾有一个空逻辑行，光标可置于其上 |
| 单行超过 262 144 字节 | 切为多个排版段显示（REQ-W-TEXTAREA-007）；光标在段边界上的亲和性按软换行处理 |
| 单行极长（如 10 MB 一行） | 仍可编辑；每次编辑只重排受影响的排版段（≤ 262 144 字节） |
| 非法 UTF-8 | 显示为 U+FFFD，载入不验证，复制与 `textAreaText` 保持原始字节 |
| 载入失败（`TooLarge`、`OutOfMemory`） | 文档不变，返回错误 |
| 编辑分配失败 | 该次编辑放弃，文档与撤销栈不变，记录 `warn` |
| 滚动中文档被应用 `textAreaReplace` 缩短 | 滚动位置按 `top_line` 夹紧到合法范围 |
| `wrap` 在运行中切换 | 使所有行高精确值降级、`content_w` 清零，按 `top_line` 保持视口顶端 |
| 视口宽度为 0 / 过窄（小于一个簇宽） | 每视觉行至少容纳一个簇（REQ-TEXT-016） |
| 禁用/按下期间控件消失 | 同 text-input.md（捕获释放、选择结束、组字提交丢弃） |
| 文本区不在树中时应用调用 `textAreaText` | 若文档槽仍在则返回内容；已被回收则返回空串并记录 `warn` |
| 监听函数内调用 `textAreaReplace` | 调试构建断言，发布构建忽略 |

## 16. 验收标准

**夹具 F-TA**（除特别注明外）：无头、`fixed` 文本后端（每簇宽 6 px，行高 16 px）、缩放 1.0、B = 12；窗口 400×300；文本区 `@A` 位于 (50,50)、200×100，`wrap = .word`；视口为 (51,51) 起的 198×98，文本原点 (57,55)（边框 1 + `pad_input_x` 6，边框 1 + `gap_sm` 4），无纵向滚动条时排版宽度 186 px（31 簇），第 r 个视觉行的顶边 y = 55 + 16 r − 纵向偏移。`caret_blink_ms` = 500。行高取 `font_body` 的令牌行高 16（REQ-THEME-016），与 fixed 后端的自然行高无关；行框、光标、选区高度均为 16。回放记号同 text-input.md 第 16 节。

**AC-W-TEXTAREA-001**　`[金图]` 覆盖：REQ-W-TEXTAREA-001、REQ-W-TEXTAREA-013、REQ-W-TEXTAREA-014、REQ-W-TEXTAREA-002、REQ-W-TEXTAREA-010。状态矩阵：{常态, 悬停, 聚焦含光标, 聚焦且选区跨 3 行（含行尾延伸）, 失焦保留选区, 窗口非活动保留选区, 只读, 禁用, 占位, 自动换行 + 纵向滚动条, 不换行 + 双滚动条} × 浅/深/高对比度 × 缩放 1.0/1.5/2.0；内容含中英文混排与 emoji。预期：与基准图一致；失焦与非活动列的选区像素颜色为 `surface_selection_inactive`、文字为 `text_primary`、无光标；聚焦列选区为 `accent_fill_bottom`、选区内文字 `text_on_accent`；选区跨行时每个被跨越换行的行矩形右端延伸一个空格宽；滚动条显示策略 `auto`：内容超出时出现并占用 `scrollbar_w`（视口变窄、排版宽度随之减小并重排），内容未超出时不占位（视口不变）。

**AC-W-TEXTAREA-002**　`[回放]` 覆盖：REQ-W-TEXTAREA-020、REQ-W-TEXTAREA-021、REQ-W-TEXTAREA-024。（1）文档 `"abcdefghij\nab\nabcdefghij"`，光标 8：↓ → 13，↓ → 22，↑ → 13，↑ → 8（`goal_x` 保持）；↓ 后按 → 再 ↑ → 目标列重置为当前列。（2）70 个 "a"（无空格，宽 186 px → 每视觉行 31 簇：行 0 为 [0,31)、行 1 为 [31,62)、行 2 为 [62,70)）：光标 5，↓ → 36；End → 62（行 1 行末，亲和性 upstream）；Home → 31；Ctrl+Home → 0；Ctrl+End → 70。（3）100 个逻辑行（每行 "L"）：光标 0，`page_rows` = floor(98/16) − 1 = 5；PageDown → 光标在第 5 行（偏移 10）、纵向偏移 80；再 PageDown → 第 10 行、偏移 160；PageUp → 第 5 行、偏移 80；Ctrl+End → 末行，纵向偏移为最大值；Shift+PageUp → 选区自末行向上 5 行。（4）Ctrl+↓ → 纵向偏移 +16，光标不动。（5）光标移出视口时按最小位移使其可见（用 ↓ 逐行移动，偏移仅在光标越过底边时每次增 16 − 余量）。

**AC-W-TEXTAREA-003**　`[回放]` 覆盖：REQ-W-TEXTAREA-022、REQ-W-TEXTAREA-023、REQ-W-TEXTAREA-019、REQ-W-TEXTAREA-025。对话框范围内有 `@A`、默认按钮 B、取消按钮 C。`@A` 聚焦，`text "ab"`，按 Enter → 文档 "ab\n"、光标 3、B 无 `clicked`；按 Shift+Enter → 再插入 `\n`（"ab\n\n"、光标 4）；按 Ctrl+Enter → 不插入换行、B 无 `clicked`，若登记了 Ctrl+Enter 的命令则该命令被调用；按 Esc → C 被激活。`accepts_tab` 假：按 Tab → 焦点移走。`accepts_tab` 真：按 Tab → 插入 `\t`；选区 (0,2) 按 Tab → 选区被替换为 `\t`；按 Shift+Tab 与 Ctrl+Tab → 均为焦点导航（Ctrl+Tab 先交祖先，无人处理时按 Tab 规则导航，REQ-INPUT-035）；文本区位于一个处理 Ctrl+Tab 的标签页内时 Ctrl+Tab 切换页而不导航。Tab 进入 `@A`（`accepts_tab` 假，文档 "hello"）→ 选区不变（**未**全选）；鼠标点击进入按点击定位。失焦（Tab 离开）→ 不报告任何提交，选区保持并以非活动色绘制。

**AC-W-TEXTAREA-004**　`[回放]` 覆盖：REQ-W-TEXTAREA-015、REQ-W-TEXTAREA-016、REQ-W-TEXTAREA-017、REQ-W-TEXTAREA-018。文档 `"one two\nthree four\nfive"`（偏移：行 0 [0,7]、`\n` 在 7，行 1 [8,18]、`\n` 在 18，行 2 [19,23)）。点击 (57+6×4+1, 55+16+8) = (82,79)（行 1 第 4 簇前半）→ 光标 12；Shift+点击行 2 末尾右侧 (200,95) → 选区 (12,23)。双击行 1 的 "four"（点击 (57+6×7+1, 79) = (100,79)）→ (14,18)。三击行 0 → (0,8)（含换行）；三击行 2 → (19,23)（末行无换行）。拖动选择：文档 100 行，在行 0 起点 (58,56) 按下，拖到 (100,170)（视口底缘 y = 149 之下 d = 21 lpx），`advance 150`（3 拍，每拍 `dur_autoscroll` = 50 ms）→ 纵向偏移 3 × min(21, 49) = 63 lpx，选区起点 0、终点随拍单调增大；指针移回视口内后偏移不再变化。滚轮：文档 100 行，指针在 `@A` 上 `wheel -1`（向下 1 格，13：负值向下、偏移增大；`wheel_lines` = 3）→ 纵向偏移 48 lpx（3 行）；`wheel 1`（向上）→ 偏移回减 48；设 `wheel_lines` 为 `page` → 滚动 `98 − 16 = 82` lpx；已在底部继续 `wheel -1` → 事件冒泡给外层可滚动容器；滚动不改变光标与选区。

**AC-W-TEXTAREA-005**　`[回放]` 覆盖：REQ-W-TEXTAREA-027、REQ-W-TEXTAREA-028、REQ-W-TEXTAREA-026。（1）剪贴板 "a\r\nb\rc\td\u{7}e" → 粘贴后文档 "a\nb\nc\tde"（`\r\n`、`\r` 规范为 `\n` 并保留，制表符保留，BEL 删除）。（2）撤销：`text "abc"`、Enter、`text "def"`（一次注入、停顿 < `undo_merge_pause`）→ Ctrl+Z → ""（换行并入合并）；Ctrl+Y → "abc\ndef"。`text "x"`、`advance 1100`、`text "y"` → 两步。应用 `textAreaReplace(0,1,"Z")` 后 Ctrl+Z 无效果。撤销 1000 步的容量：1100 次独立编辑后恰可撤销 1000 次。（3）输入法：文档 "ab\ncd"，光标 5，`ime start`、`ime update "ni" 2` → 第 1 行显示 "cdni"、文档不变、`imeCaretRect` 为 (81,71,1,16)（第 1 行、组字内光标在第 4 簇后：x = 57 + 24，y = 55 + 16）；`ime commit "你好\n"`（含换行）→ 文档 "ab\ncd你好\n"、光标 12；`ime cancel` 路径：选区 (0,2) 时 `ime update "x" 1` → 显示替换、取消后选区恢复。

**AC-W-TEXTAREA-006**　`[单元]` 覆盖：REQ-W-TEXTAREA-003、REQ-W-TEXTAREA-005、REQ-W-TEXTAREA-006、REQ-W-TEXTAREA-029、REQ-W-TEXTAREA-030、REQ-W-TEXTAREA-031。（1）载入 "a\r\nb\r\nc" → `eol = crlf`、`mixed` 假、内部 "a\nb\nc"（5 字节，3 行）；`textAreaText` 默认 → "a\r\nb\r\nc"；指定 `.lf` → "a\nb\nc"。（2）载入 "a\r\nb\nc\r\n" → `eol = crlf`（2 比 1）、`mixed` 真；载入 "a\rb" → `eol = cr`；载入 "abc" → `eol = lf`；载入 "\u{FEFF}hi" → `had_bom` 真、内部 "hi"、`textAreaText` 默认带 BOM 还原。（3）`textAreaRange(2,5)` 对 "hello world" 返回 "llo"；范围读取耗时与范围大小成正比（对 10 MB 文档读 100 字节 ≤ 0.1 ms）。（4）`textAreaReplace(6,11,"你好")`（"hello world"）→ "hello 你好"、撤销栈清空、监听收到 `{start 6, removed 5, inserted 6, source .api}`；光标在 11 时平移为 12（11 位于被替换范围末端 → 夹紧到插入内容末尾）。（5）监听收到用户键入、撤销、载入的各自 `source`；监听内调用 `textAreaReplace` 在调试构建断言中止；取消订阅后不再收到。（6）载入超过 `max_bytes` → `error.TooLarge`，文档不变。（7）U+2028 保持为普通字符，显示为空格。（8）文档由保留节点持有：应用不持有文本缓冲，文本区暂不被声明（5 次构建）后再声明，文档内容、撤销栈、光标仍在；文档槽为 `Retain.pinned`：以假的 LRU 压力注入（超过 4096 个 sticky 槽）后文档仍在；`ui.forget(id)` 后文档被回收（监听被丢弃）；窗口关闭时回收。

**AC-W-TEXTAREA-007**　`[计量]` 覆盖：REQ-W-TEXTAREA-006、REQ-W-TEXTAREA-007、REQ-W-TEXTAREA-004。场景 S-TEXT-LOAD：10 MB、20 万行文档，冷状态载入 10 次，`time.text_load` 每次 ≤ 200 ms（W 上硬性，L 上趋势）；载入后首帧 `text.testing.atlasStats().shape_count` 增量 ≤ 视口行数 + 2（视口 98 px 时 ≤ 9，即只排版可见行）。块树不变量断言：每块行数 ≤ 128、字节 ≤ 16 KiB（单行例外）；对 20 万次随机"偏移 → 行 → 偏移"往返结果一致；对随机编辑序列（插入、删除、换行、合并）后，摘要字节数和行数之和等于独立计算的值。

**AC-W-TEXTAREA-008**　`[计量]` 覆盖：REQ-W-TEXTAREA-012、REQ-W-TEXTAREA-011、REQ-W-TEXTAREA-008、REQ-W-TEXTAREA-009。场景 S-TEXT-KEY：10 MB、20 万行文档，`@A` 聚焦、光标在中部，运行 1010 帧，每帧一次字符键按下与释放：`time.frame_cpu` P99 ≤ 2.0 ms；每帧 `shape_count` 增量 ≤ 2；每帧损伤为被编辑行的视觉行矩形（面积 ≤ 视口宽 × 行高）；按 Enter 的帧损伤为自该行起到视口底部。自动换行文档：滚到中部，应用 `textAreaReplace` 在文档开头插入 100 行 → 视口显示内容不跳动（`top_line` 随之重新定位，`top_line` 对应的行内容不变）；估计行高被精确化后同一屏的首行文字像素位置不变。大内容坐标：文档含 2 亿个逻辑行（`textAreaLoad` 的合成数据或测试桩）时滚到末尾，`ScrollMetrics.content_px` 与 `offset_px` 为 64 位精确值，所有可见行节点矩形的坐标绝对值 ≤ 视口尺寸 + 缓冲，`frame.nodes` 与 20 万行时相等（REQ-LAYOUT-054）。

**AC-W-TEXTAREA-009**　`[计量]` 覆盖：REQ-W-TEXTAREA-033、REQ-W-TEXTAREA-034、REQ-W-TEXTAREA-014。回放：指针移入移出 `@A` → 各帧构建遍数 0、损伤不超出其绘制范围；聚焦后 `advance 5000` → 10 帧，每帧构建遍数 0、损伤面积 = 16 ppx²（光标叶节点 1×16）；以相同参数再次 `invalidate(.build)` → 损伤为空；仅滚动 → `layout` 级、不执行构建；仅改变 `placeholder` → 损伤恰为 `@A` 的矩形。

**AC-W-TEXTAREA-010**　`[人工]` 覆盖：REQ-W-TEXTAREA-026、REQ-W-TEXTAREA-032、REQ-W-TEXTAREA-012。真实 Windows：在 10 MB 文档中段用微软拼音输入中文，组字串内联、候选窗跟随光标行；滚动后候选窗位置更新；用讲述人（Narrator）读取当前行与选区；持续按住字母键观察无卡顿（主观补充，判定以 `[计量]` 条款为准）。

## 17. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-W-TEXTAREA-02 | 行号栏（及其宽度随位数变化、点击选行） | 不在本版；若提供，作为 `line_numbers: bool` 选项，栏用 `surface_panel`、数字 `text_secondary`、`font_mono`，宽度由位数决定 |
| OPEN-W-TEXTAREA-03 | 多行选区的 Tab 缩进/Shift+Tab 反缩进、自动缩进 | 不提供；`accepts_tab` 仅插入制表符 |
| OPEN-W-TEXTAREA-05 | 不换行时内容宽度只按"已排版行"与"最长字节行"估计，滚动条范围可能先小后大 | 倾向接受；若体验差，可后台分帧排版最长的若干行 |
| OPEN-W-TEXTAREA-06 | 自动换行时滚动条依据估计高度，拖动滑块的位置在行高精确化后会有小幅漂移 | 倾向接受（锚定顶行保证内容不跳）；需用 200 万字符/长行基准验证 |
| OPEN-W-TEXTAREA-07 | `invalid`（校验失败）与前置图标、清除按钮在多行下的位置 | 不提供；校验提示由应用在文本区旁用 label 显示 |
| OPEN-W-TEXTAREA-08 | 大文本的撤销栈字节上限 16 MiB 与 10 MB 文档整体替换的关系 | 整体替换超限则清栈（REQ-W-TEXTAREA-028）；是否改为存块引用以支持，待基准 |
| OPEN-W-TEXTAREA-09 | 内容宽度估计、块大小（128 行 / 16 KiB）的取值需用 S-TEXT-KEY/S-TEXT-LOAD 实测调参 | 先按本文取值，基准后调整并更新 REQ-W-TEXTAREA-004 |
