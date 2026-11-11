# 树（tree）

> 本文复用 [list.md](list.md) 的虚拟化与**选择模型**（list.md 5.3 节），只写差异。凡写"同 list"之处，条款编号见 REQ-W-TREE-001 的继承清单。

## 1. 用途

展示层级数据（文件夹、大纲、设置分类），支持展开/折叠、选择与激活。参照 Windows 的 TreeView（`SysTreeView32`，不含复选框与连接线样式）。本控件把层级**展平为可见行**后按 list 的方式虚拟化：只为可见行与缓冲行创建节点，可见行总数可达百万。

- 一层的平面数据 → 用 list；多列数据 → 用 table（本版不提供"树表"）。
- 节点需要内嵌复杂控件 → 在行内容中声明，同 list。
- 需要拖放改变层级 → 本版不支持（待定）。

## 2. 解剖

```
┌──────────────────────────────────────┬──┐  ← 框、视口、滚动条同 list
│ ▾ ▣ 项目                              │  │  ← 根层行：[展开箭头] [图标] 文字
│   ▸ ▣ 源码                            │  │  ← 缩进 = indent × 深度；折叠态箭头朝右
│   ▾ ▣ 文档                            │  │
│       · 说明.md                       │  │  ← 叶子行：无箭头，仍保留箭头位
│       ◌ 加载中…                       │  │  ← 加载占位行（惰性加载，不可选）
│ ▸ ▣ 资源                              │  │
└──────────────────────────────────────┴──┘
   └pad_item_x┘└indent×深度┘└箭头位 icon_sm┘
```

- **行**：同 list 的行，另带深度。
- **缩进**：`indent × 深度` lpx（不画连接线）。
- **展开箭头**：`icon_sm` 见方的箭头位，用 `chevron_right`（折叠）/`chevron_down`（展开）；叶子行留空但保留位置。
- **图标**（可选）、**文字**：行内容，由应用经 `treeLabel` 声明。
- **加载占位行**：惰性加载中显示的、框架绘制的不可选行。

## 3. 度量与布局

| 项 | 取值（令牌） |
|---|---|
| 行高 | `row_h`（同 list，固定） |
| 行内左边距 | `pad_item_x` |
| 每级缩进 | `indent` |
| 展开箭头位 | `icon_sm` 见方；箭头位与后续内容的间距 `gap_xs` |
| 图标 | `icon_sm`；图标与文字间距 `gap_sm` |
| 文字样式 | `font_body` |
| 缓冲行、首次回退行数 | 同 list（各 5 行、32 行） |
| 其余（框、圆角、滚动条） | 同 list |

行内内容的起点 x = `pad_item_x + 深度 × indent + icon_sm + gap_xs`；展开箭头位的 x 范围 = `[pad_item_x + 深度 × indent, 该值 + icon_sm)`。

**REQ-W-TREE-001**　**继承**：树的下列方面**必须**与 list 的对应条款一致，只把"行"理解为**展平后的可见行**，把"行下标"理解为展平序中的下标，把"稳定键"理解为节点键（`key_of(node)`）：默认尺寸策略与三层节点结构（REQ-W-LIST-001、REQ-W-LIST-002）；固定行高与整数 ppx（REQ-W-LIST-003）；可见窗口与缓冲（REQ-W-LIST-004）；不可见行无节点与 `list.virtual_nodes` 计量（REQ-W-LIST-005）；迭代协议（REQ-W-LIST-006，迭代器改为 `TreeIter`）；首次视口回退与布局反馈（REQ-W-LIST-007）；构建代价与总量无关（REQ-W-LIST-009）；行内容容器（REQ-W-LIST-010）；滚动（REQ-W-LIST-012，滚轮读取系统行数）；选择模型的类型、模式、焦点行与锚点、`selection_changed` 判定（REQ-W-LIST-013 至 REQ-W-LIST-018）；单击、Ctrl+单击、Shift+单击、Ctrl+Shift+单击、在已选多行上按下的延迟折叠、`single`/`none` 的修饰键、右键、空白处点击（REQ-W-LIST-019 至 REQ-W-LIST-026，其中点击落在展开箭头位上的情形见 REQ-W-TREE-013）；悬停与其他输入、点击聚焦（REQ-W-LIST-028、REQ-W-LIST-029）；方向键、Home/End、PageUp/PageDown、Space、Ctrl+A、前缀搜索、焦点滚入（REQ-W-LIST-031 至 REQ-W-LIST-036、REQ-W-LIST-039、REQ-W-LIST-040，Ctrl+A 与区间的"全部行"指可见行，见 REQ-W-TREE-024）；单个 Tab 停靠与焦点指示（REQ-W-LIST-041）；行绘制顺序、禁用（REQ-W-LIST-045、REQ-W-LIST-047）；行文字省略与提示（REQ-W-LIST-046）；保留节点生命周期（REQ-W-LIST-049）；绘制键与可计量断言的各项（REQ-W-LIST-050、REQ-W-LIST-051）；行位置逐像素精确与虚拟内容范围（REQ-W-LIST-003、REQ-W-LIST-053，100 万行及以上也成立）；焦点行指示用 `drawRowFocus`（REQ-W-LIST-045）；框内缩 `Params.border = 1`（REQ-W-LIST-002）。差异见本文其余条款。树不提供拖动重排、行高可变、双击/Enter 的 list 语义（见 REQ-W-TREE-014、REQ-W-TREE-021）。

**REQ-W-TREE-002**　**数据由应用以回调提供**，节点用不透明句柄 `TreeNode`（`u64`，`root` 为不可见的虚拟根，其子项是顶层行）。`TreeModel` 必须提供：`child_count(node)`、`child_at(node, i)`、`has_children(node)`（廉价，只回答"是否有子项"，不得触发加载）、`key_of(node)`（稳定键：同一节点跨重排/重载不变，在整棵树内唯一）；可选：`text_of(node)`（行文本，供前缀搜索与无障碍名称）、`str_key_of(node)`（持久化用字符串键，REQ-W-TREE-010）、`load_state(node)`（惰性加载状态）。`child_count`/`child_at` 只对**已展开**的节点调用；回调在构建函数内同步调用，不得阻塞（REQ-FRAME-026）。

**REQ-W-TREE-003**　**展平缓存**保存在树的保留节点中（REQ-FRAME-011，sticky）：一个按先序排列的可见行数组，每行记录 `{ node, key, parent: u32（展平序下标，顶层为 none）, depth: u16, flags }`（共 24 字节，`flags` 含 `has_children`、`expanded`、`placeholder`），外加"键 → 下标"的哈希映射（O(1) 期望）。可见行 = 顶层节点，以及已展开节点的子项（递归）。构建时迭代器只读取该缓存，**不**调用 `child_count`/`child_at`/`has_children`；只有可见窗口内的行才调用 `text_of`（由 `treeLabel` 的调用者决定）。缓存的首次建立或全量重建是 O(可见行总数) 的一次性操作，不在滚动帧中发生。

**REQ-W-TREE-004**　**增量更新**：用户展开/折叠节点（箭头位点击、键盘、双击）时缓存**增量更新**而非重建。展开下标 `i` 处的节点：对其子项递归（仅向下经过已展开的后代）生成可见行，插入 `i + 1` 之后，其后各行的 `parent` 下标与映射项按插入量平移；折叠：删除 `i + 1` 起所有 `depth > depth(i)` 的行（到第一个 `depth ≤ depth(i)` 的行为止）并平移其后。成本为 O(变动行数 + 其后的行数)（数组移动），不是对整棵树重新调用回调；回调调用次数 ≤ 新增行数 + 1（一次 `child_count`、各子项的 `child_at`/`has_children`/`key_of`）。焦点行、锚点的展平下标按平移量更新。

**REQ-W-TREE-005**　**数据变化**：应用经 `TreeModel.version`（递增整数）通知"数据已变"，经 `opts.changed`（本次构建内，其子项发生变化的节点集合，应用每次构建重新给出）通知局部变化。`version` 与上次保留的值不同 → 全量重建缓存（O(可见行总数)，保持展开集合、焦点、锚点、选中；按键重新定位）；仅 `changed` 非空 → 只重建这些节点的子树（等价于折叠后重新展开，保持后代的展开状态）。两者都未变 → 缓存原样使用。应用忘记通知则界面不更新（同 ADR 0006 的显式契约）。

**REQ-W-TREE-006**　**滚动帧成本只与可见行数相关**：展平行总数为 100 万（全部节点已展开）时，纯滚动帧（偏移变化、无展开折叠、`version` 与 `changed` 不变）中：(a) 被创建的行节点数 ≤ 可见行数 + 缓冲行数（同 REQ-W-LIST-051）；(b) 对 `TreeModel` 的 `child_count`、`child_at`、`has_children` 的调用次数为 0；(c) `key_of` 与 `text_of` 的调用次数各 ≤ 可见行数 + 缓冲行数；(d) `time.frame_cpu` 的 P99 ≤ 2.0 ms（同 S-VLIST-100K 的预算，REQ-PERF-020），且与展平行总数无关（1000 行与 100 万行两个规模的 P99 之比 ≤ 1.5）。

**REQ-W-TREE-007**　**惰性加载与占位行**：节点被展开时才询问其子项。`load_state(node)` 返回 `loading` 的已展开节点，在缓存中于其后插入**一个占位行**（`placeholder`，深度 +1），由框架绘制：文字取自 `Strings` 的"加载中…"（11 REQ-APP-042）、`text_secondary`、无箭头位内容。占位行**不可聚焦、不可选中、点击无效、不被迭代器产出给应用**；键盘移动与区间运算跳过它（区间内的占位行不被选中）；它计入可见行与 `list.virtual_nodes`。节点从 `loading` 转为 `loaded` 须由应用递增 `version` 或经 `changed` 通知，缓存随即以真实子项替换占位行。展开未加载（尚无子项）的节点时控件报告 `toggled`（`expanded = true`），应用据此启动加载。`has_children` 为真而 `child_count` 为 0 的节点：展开后不插入任何行，箭头位保持可见（由应用经 `has_children` 的变化来表达"其实没有子项"）。

**REQ-W-TREE-008**　行解剖与几何：深度为 `d` 的行，展开箭头位 x 范围 `[pad_item_x + d × indent, pad_item_x + d × indent + icon_sm)`（lpx，竖直居中于行）；内容起点 `pad_item_x + d × indent + icon_sm + gap_xs`；可选图标 `icon_sm`，后接 `gap_sm`，再接文字。叶子行（`has_children` 假）不画箭头但保留箭头位，使同级文字对齐。**不画连接线**（父子之间的虚线）。选中底与悬停底占满整行宽，不随缩进收窄。

**REQ-W-TREE-009**　**展开箭头的画法与动画**：箭头用 `drawMark`（REQ-THEME-029）绘制，色 `text_secondary`，选中且 `active` 时 `text_on_accent`，禁用时 `text_disabled`。静止时折叠为 `chevron_right`、展开为 `chevron_down`。用户展开/折叠时箭头以 `ui.animate`（REQ-FRAME-045）在 `dur_normal`、`ease_out` 内绕箭头位中心旋转 0° → 90°（展开）或 90° → 0°（折叠），影响级别 `paint`；动画期间以 `drawMark(chevron_right, R, color, rotation)` 绘制，`rotation`（弧度，绕箭头位中心，REQ-THEME-029）由 0 渐变到 π/2（展开）或反向（折叠），旋转时不做像素对齐；动画结束后画 `rotation = 0` 的静止形状（`chevron_right` 或 `chevron_down`），使静止时笔画对齐物理像素。系统关闭界面动画（`SystemMetrics.client_animation` 为假）时立即到位（REQ-FRAME-047）。滚动进入视野的行与数据变化引起的行**不**播放动画（首次 `animate` 直接取目标值，REQ-FRAME-045）。

**REQ-W-TREE-010**　**展开集合**是 `ItemKey` 的集合，**由框架保留**（保留节点内的 `ExpandedSet`，sticky），也可由应用持有（`opts.expanded` 非空时它是唯一事实来源）。**可持久化**（11 REQ-APP-037，`UiStateStore.tree`/`setTree`）：`persist` 与窗口 `persist_name` 均非空时，控件首次出现读取一次展开节点的**字符串键**数组，要求提供 `str_key_of`，且节点的 `ItemKey` 必须等于 `ui.Key.str(str_key_of(node)).hash`（调试构建校验）；读入的键即刻进入展开集合（不依赖节点是否已加载）；展开/折叠时写入当前展开集合对应的字符串键数组（按字符串字典序，确定），经设置存储去抖落盘。缺少 `str_key_of` 而设置了 `persist` 为调试构建断言。读入的条目中不存在于当前数据的键保留不删（节点可能尚未加载）。

**REQ-W-TREE-011**　**初始展开**：选项 `initially_expanded_depth`（默认 0）——展开集合首次建立且无持久化记录、无应用传入的集合时，深度小于该值的有子项节点视为已展开（深度 0 为顶层）。此后展开集合只由用户操作与应用对集合的直接修改改变。

**REQ-W-TREE-012**　**深度与环**：节点深度上限 `max_depth = 256`；超过时该节点的子项不被展平并在调试构建记录一条 `warn`。模型含环（节点是自己的后代）属应用错误：展平遇到深度超限即停止，不进入死循环。

## 4. 变体与参数

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `mode` | `SelectionMode` | `single` | 同 list |
| `selection` | `?*Selection` | `null` | 同 list；键为节点键 |
| `expanded` | `?*ExpandedSet` | `null` | 非空：展开集合由应用持有 |
| `persist` | `?[]const u8` | `null` | 持久化名（11）；要求 `str_key_of` |
| `initially_expanded_depth` | `u8` | `0` | 初始展开的层数 |
| `activate_parents` | `bool` | `false` | 为真时有子项的行在双击/Enter 展开折叠的同时也报告 `activated` |
| `changed` | `[]const TreeNode` | `&.{}` | 本次构建内其子项变化的节点（REQ-W-TREE-005） |
| `alternate_rows`、`empty_text`、`scrollbar`、`tooltip_on_truncate` | 同 list | | |
| `enabled`、`key`、`debug_name`、`layout` | 通用 | | 见模板 |

无 `reorder`、无 `row_height`（行高固定 `row_h`）。变体只有 `mode`。

## 5. 状态

### 5.1 状态机

状态变量与 list 相同（`press ∈ {无, 待折叠}`，无"拖动重排"）；另增每个节点的 `expanded`（属展开集合）。以下只列与 list 不同或新增的转移；其余同 list.md 5.1。下表 `r` 为行。

| 当前 | 事件 | 条件 | 下一状态 | 动作 |
|---|---|---|---|---|
| 任意 | 左键按下于行 r 的展开箭头位 | r 有子项（`has_children`） | 不变 | 切换 r 的展开；**不**改变 `Sel`、`F`、`A`（REQ-W-TREE-013） |
| 任意 | 左键按下于叶子行的箭头位 | r 为叶子 | 同 list 的行按下 | 按行内其他位置处理 |
| 任意 | 左键按下于占位行 | — | 不变 | 无（占位行点击无效）；列表仍取得焦点 |
| 任意 | 第二次点击（`click_count = 2`）于行 r | r 有子项，无 Ctrl/Shift | 不变 | 切换 r 的展开；`activate_parents` 时同时报告 `activated`（REQ-W-TREE-014） |
| 任意 | 第二次点击于行 r | r 为叶子，无 Ctrl/Shift | 不变 | 报告 `activated`（r） |
| 任意 | → | `F` 为折叠的有子项节点 | 不变 | 展开 `F`（REQ-W-TREE-017） |
| 任意 | → | `F` 为已展开的有子项节点且有真实子项 | 不变 | 移动并选中第一个子项 |
| 任意 | ← | `F` 为已展开的有子项节点 | 不变 | 折叠 `F` |
| 任意 | ← | 其他且 `F` 非顶层 | 不变 | 移动并选中 `F` 的父节点（REQ-W-TREE-018） |
| 任意 | 数字键盘 `*` / `+` / `-` | 见 REQ-W-TREE-019、020 | 不变 | 展开全部后代 / 展开 / 折叠 |
| 任意 | Enter | `F` 有子项 | 不变 | 切换展开；`activate_parents` 时同时 `activated` |
| 任意 | Enter | `F` 为叶子 | 不变 | 报告 `activated`（`F`） |
| 任意 | 某节点折叠 | 其后代含 `F` 或 `A` | 不变 | `F`/`A` ← 被折叠的节点（REQ-W-TREE-023） |

### 5.2 视觉表现

在 list.md 5.2 的基础上：

| 状态 | 绘制（基元 + 令牌） |
|---|---|
| 展开箭头 | `drawMark(chevron_right / chevron_down, …, rotation)`，`text_secondary`；选中且 `active` 为 `text_on_accent`；禁用 `text_disabled`；动画见 REQ-W-TREE-009 |
| 悬停在箭头位 | 无额外变化（不画箭头按钮底） |
| 叶子行 | 无箭头，保留箭头位 |
| 加载占位行 | 文字"加载中…"，`text_secondary`；无选中底、无悬停底、无焦点指示 |
| 其余（框、行底、选中底、焦点行指示、禁用） | 同 list |

选中状态属于节点键：被折叠隐藏的选中节点不画（不可见），其选中状态在重新展开后恢复显示。

### 5.3 选择模型

引用 list.md 5.3 节（概念：选中集合 `Sel`、焦点行 `F`、锚点行 `A`、区间、模式；类型 `ItemKey`、`Selection`、`SelectionMode`、`KeyView`）。差异：

- 键为节点键 `key_of(node)`；`KeyView` 的下标是**展平序下标**。
- "区间 `[A, r]`"指展平序上**当前可见行**的区间；占位行不入区间。
- 选中集合可含当前不可见（被折叠）的节点键，见 REQ-W-TREE-024。

## 6. 鼠标行为

**REQ-W-TREE-013**　**点击展开箭头位**只展开/折叠该节点，**不**改变选择、焦点行与锚点（因此不报告 `selection_changed`，`F`、`A` 不变）。按下即生效（不等释放）；按下不进入"待折叠"，不开始拖拽。列表仍按点击聚焦取得焦点（REQ-INPUT-022，焦点不可见）。叶子行的箭头位没有箭头也无此行为，点击按行点击处理。箭头位的命中范围是 `[pad_item_x + d × indent, pad_item_x + d × indent + icon_sm)` × 行高（与 REQ-W-TREE-008 的箭头位一致，不含其后的 `gap_xs`）。

**REQ-W-TREE-014**　**双击**（同一行第二次点击，`click_count = 2`，无 Ctrl/Shift）：有子项的行**只切换展开**（`activated` 不触发，除非 `activate_parents = true`），叶子行触发 `activated`（该行的节点）。第二次按下的选择效果按 list 规则照常发生。双击落在展开箭头位时，两次按下各切换一次（REQ-W-TREE-013），净效果为展开后又折叠，不触发本条的双击语义；双击落在行的其他位置只切换一次。空白处双击无效果。

**REQ-W-TREE-015**　**点击行的其他位置**（含图标、文字、行尾空白）：同 list 的单击规则，`Sel`、`F`、`A` 按节点键处理；`multi` 下 Shift+单击的区间取展平序上的可见行。

**REQ-W-TREE-016**　**右键**同 list（REQ-W-LIST-025）；上下文菜单请求为 `TreeContext{ node: ?TreeNode, key: ?ItemKey, pos, anchor, from_keyboard }`；占位行与空白处给出 `node = null`。

## 7. 键盘行为

在 list.md 第 7 节键位表的基础上（↑/↓、Home/End、PageUp/PageDown、Space、Ctrl+A、前缀搜索、Shift+F10 完全同 list，作用于展平的可见行），增加或改变：

| 键 | 行为 |
|---|---|
| → | `F` 为折叠且有子项：展开，`F`、`Sel` 不变；已展开且有真实子项：移动并选中第一个子项；叶子或仅有占位行：无作用 |
| ← | `F` 为已展开且有子项：折叠，`F`、`Sel` 不变；否则 `F` 非顶层：移动并选中其父节点；顶层折叠或叶子：无作用 |
| 小键盘 `*` | 展开 `F` 及其全部后代 |
| 小键盘 `+` | 展开 `F`（折叠且有子项时） |
| 小键盘 `-` | 折叠 `F`（已展开时） |
| Enter | `F` 有子项：切换展开；叶子：`activated` |
| Space、Ctrl+Space | 同 list（选中/切换 `F`），**不**展开折叠 |
| Shift+← / Shift+→ | 等同无修饰的 ← / →（键组匹配仅 Shift 的方向键，到达树） |
| Ctrl+← / Ctrl+→、含 Alt 的组合 | 不处理（不列入 `extra`，继续冒泡） |
| Ctrl+PageUp / Ctrl+PageDown | 不处理（冒泡给外层标签页），同 list |

**REQ-W-TREE-017**　**→**：设 `F` 为焦点行。`F` 为折叠的有子项节点：展开它，焦点行与选择不变（箭头同时旋转）；`F` 为已展开且有至少一个真实子项（非占位）：按"移动并选中"处理第一个子项；`F` 为叶子，或已展开但只有占位行：无作用。无 `F` 时无作用。

**REQ-W-TREE-018**　**←**：`F` 为已展开的有子项节点：折叠它，焦点行与选择不变；否则（折叠的有子项节点或叶子）若存在父节点（`parent` 非 none）：按"移动并选中"处理父节点；顶层节点无作用。无 `F` 时无作用。

**REQ-W-TREE-019**　**小键盘 `*`**：展开 `F`，并递归展开其全部后代（对每个有子项的后代调用 `child_count`/`child_at`；`load_state` 为 `loading` 的节点标记展开并按 REQ-W-TREE-007 报告 `toggled`）。一次操作最多展开 100000 个节点，达到上限即停止、保留已展开部分并在调试构建记录一条 `warn`。焦点行与选择不变。该操作的成本 O(新增行数)，是用户触发的一次性操作。

**REQ-W-TREE-020**　**小键盘 `+`/`-`**：`+` 在 `F` 为折叠的有子项节点时展开它，否则无作用；`-` 在 `F` 为已展开节点时折叠它，否则无作用。均不改变焦点行与选择。主键盘区的 `+`、`-` 是可打印字符，参与前缀搜索而不展开折叠（见 OPEN-W-TREE-02）。

**REQ-W-TREE-021**　**Enter**：`F` 有子项时切换其展开状态（`activate_parents = true` 时同时报告 `activated`），`F` 为叶子时报告 `activated`；有意与 list 的"Enter 恒激活"不同，使键盘与双击行为一致（REQ-W-TREE-014）。自动重复的 Enter 被忽略。

**REQ-W-TREE-022**　树经 `InteractOpts` 声明：`handles` 的键组含 `arrows`、`home_end`、`page`、`space`、`enter`（只匹配无修饰或仅 Shift 的按键，REQ-INPUT-028，因此 Shift+←/→ 到达树并等同无修饰的 ←/→）；`handles.extra` **逐个列出**带 Ctrl 的组合——与 list 相同的 Ctrl+↑、Ctrl+↓、Ctrl+Shift+↑、Ctrl+Shift+↓、Ctrl+Home、Ctrl+End、Ctrl+Shift+Home、Ctrl+Shift+End、Ctrl+Space、Ctrl+Shift+Space、（仅 `multi`）Ctrl+A（REQ-W-LIST-031）——以及无修饰的单键：小键盘 `*`、`+`、`-`（08 REQ-INPUT-028 允许 `extra` 列无修饰单键）；Ctrl+←/→ **不**列入（不处理，冒泡），Ctrl+PageUp/PageDown 不使用；`preempt.printable = true`。由小键盘 `*`、`+`、`-` 产生的 `char` **不进入**前缀搜索缓冲（即使到达也被丢弃）。前缀搜索在**可见行**的 `text_of` 上进行（折叠隐藏的节点不参与）；`text_of` 为空时前缀搜索关闭。

## 8. 焦点

同 list（REQ-W-LIST-041）：单个 Tab 停靠，内部方向键导航，焦点指示画在焦点行。折叠导致焦点行不可见时的转移见 REQ-W-TREE-023。

**REQ-W-TREE-023**　**折叠对焦点与锚点的影响**：折叠节点 N 使当前焦点行 `F` 或锚点 `A` 位于 N 的后代中（不可见）时，`F`（及 `A`）**移到 N**；不改变选中集合，因此该次折叠不报告 `selection_changed`（折叠本身经 `toggled` 报告）。数据变化使 `F`/`A` 的节点消失时按键重新定位：键不存在则 `F` 取原展平下标夹紧后的行、`A` 清空（同 REQ-W-LIST-015）。

**REQ-W-TREE-024**　**被隐藏的选中项保留在选中集合中**：折叠不会取消其后代的选中；这些键保留在 `Sel` 内但不可见，重新展开后选中底恢复。对 Shift 区间与全选的影响：(a) 区间 `[A, r]` 只含当前可见行，隐藏的选中项既不会被区间选入，也不因"并入"而丢失；(b) 无修饰单击、Shift+单击、Space、无修饰方向键与 Home/End/PageUp/PageDown（"移动并选中"）、Shift 区间等"替换"类操作把 `Sel` **整体**替换，隐藏的选中项一并被清除（保证用户总能清空不可见的选择）；(c) Ctrl+Shift+单击、Ctrl+单击、Ctrl+Space 保留隐藏的选中项；(d) Ctrl+A 选中全部**可见**行，隐藏的选中项保持原状（折叠节点下未选中者不被选中，已选中者仍选中）；(e) `selection_changed` 仅在 `Sel` 内容改变时报告。应用对 `Sel` 的批量操作（如"删除所选"）须意识到其中含不可见项，`TreeResult.selected_visible` 给出可见（已创建节点）的选中行数以便区分。

**REQ-W-TREE-025**　展开不改变选择、焦点行与锚点；展开一个节点后其子项出现在该行之下，**不**自动滚动使子项可见（用户可见区域内的行位置保持不动，其下的行被推后）；经 `→` 移动到第一个子项时按 REQ-W-LIST-040 把它滚入。折叠使偏移越界时偏移夹紧。

**REQ-W-TREE-026**　**结果与持久化写入**：`toggled: []const Toggle`（`Toggle{ node, key, expanded }`，帧竞技场）列出本帧用户操作导致的展开/折叠变化（含 `*` 展开的各节点），是激活类结果，触发同帧第二构建遍。每次有变化的展开/折叠操作都是一次提交，操作后按 REQ-W-TREE-010 写入持久化（树没有拖动式的连续调整）。展开/折叠本身不报告 `selection_changed`。

## 9. 文本与输入法

同 list（REQ-W-LIST-046）：行文字单行尾部省略并在被截断时悬停提示完整文字；提示框锚点为该行矩形。可用宽度 = 行宽 − 内容起点 − `pad_item_x` − 图标与间距。不接受文本输入。

## 10. 动效

| 属性 | 触发 | 时长令牌 | 缓动 | 影响级别 |
|---|---|---|---|---|
| 展开箭头旋转 | 用户展开/折叠 | `dur_normal` | `ease_out` | paint（`ui.animate` 槽 0，行节点） |
| 行悬停底色 | 悬停变化 | `dur_fast` | `ease_out` | paint（`Visual.hover_t`） |
| 行的出现/消失（展开折叠时子行） | 展开折叠 | 无（即时） | — | build |
| 选中、焦点行指示、滚动位置 | — | 无 | — | 同 list |

## 11. 无障碍

| 项 | 值 |
|---|---|
| UIA 控件类型 | 树：Tree；行：TreeItem |
| 名称来源 | 行：`text_of(node)`，缺失时为空串；树：应用提供的无障碍名称 |
| 支持的模式 | 树：Selection、Scroll；行：ExpandCollapse（仅有子项的行）、SelectionItem、ScrollItem、Invoke（叶子） |
| 状态属性 | 树：CanSelectMultiple（`multi`）、IsEnabled、HasKeyboardFocus；行：ExpandCollapseState（Collapsed/Expanded/LeafNode）、IsSelected、Level（深度 + 1）、IsEnabled、HasKeyboardFocus（`F` 且树持焦） |

**REQ-W-TREE-027**　UIA `ExpandCollapse.Expand/Collapse` **必须**与键盘等效（经 `→`/`←` 的展开/折叠，不改变选择与焦点），在下一帧生效并报告 `toggled`；对叶子行 `ExpandCollapseState = LeafNode`。`SelectionItem`、`ScrollItem`、`Invoke` 与 list 等效（REQ-W-LIST-048），`Invoke` 对有子项的行等价双击（切换展开）。虚拟化下未创建节点的 UIA 项提供方式同 list（OPEN-W-LIST-05）。

## 12. API 草案

```zig
// 草案：仅签名
pub const TreeNode = enum(u64) { root = 0, _ };       // 应用定义的不透明句柄；root 为不可见虚拟根
pub const LoadState = enum { loaded, loading };

pub const TreeModel = struct {
    ctx: ?*anyopaque = null,
    child_count: *const fn (ctx: ?*anyopaque, node: TreeNode) usize,
    child_at: *const fn (ctx: ?*anyopaque, node: TreeNode, index: usize) TreeNode,
    has_children: *const fn (ctx: ?*anyopaque, node: TreeNode) bool,       // 廉价，不触发加载
    key_of: *const fn (ctx: ?*anyopaque, node: TreeNode) ItemKey,          // 稳定键
    text_of: ?*const fn (ctx: ?*anyopaque, node: TreeNode) []const u8 = null,      // 返回值只需存活至下一次调用
    str_key_of: ?*const fn (ctx: ?*anyopaque, node: TreeNode) []const u8 = null,  // 持久化用；ItemKey 须等于 Key.str(s).hash
    load_state: ?*const fn (ctx: ?*anyopaque, node: TreeNode) LoadState = null,
    version: u64 = 0,                                                       // 数据变化时递增
};

/// 展开集合：ItemKey 的集合（持久化时同时保留字符串键）。
pub const ExpandedSet = struct {
    pub fn init(allocator: std.mem.Allocator) ExpandedSet;
    pub fn deinit(self: *ExpandedSet) void;
    pub fn contains(self: *const ExpandedSet, key: ItemKey) bool;
    pub fn set(self: *ExpandedSet, key: ItemKey, expanded: bool, str_key: ?[]const u8) error{OutOfMemory}!void;
    pub fn clear(self: *ExpandedSet) void;
    pub fn len(self: *const ExpandedSet) usize;
};

pub const TreeOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    mode: SelectionMode = .single,
    selection: ?*Selection = null,
    expanded: ?*ExpandedSet = null,
    persist: ?[]const u8 = null,
    initially_expanded_depth: u8 = 0,
    activate_parents: bool = false,
    changed: []const TreeNode = &.{},      // 本次构建内子项发生变化的节点；借用至本帧结束
    alternate_rows: bool = false,
    empty_text: ?[]const u8 = null,
    scrollbar: layout.BarPolicy = .auto,
    tooltip_on_truncate: bool = true,
    layout: layout.ItemOptions = .{},
};

pub const TreeRow = struct {
    index: usize,                          // 展平序下标
    key: ItemKey,
    node: TreeNode,
    depth: u16,
    has_children: bool,
    expanded: bool,
    selected: bool,
    focused: bool,
    hovered: bool,
    text_color: theme.ColorToken,
};

pub const TreeIter = struct {
    pub fn next(self: *TreeIter) ?TreeRow;   // 不产出占位行
};

pub const Toggle = struct { node: TreeNode, key: ItemKey, expanded: bool };
pub const TreeContext = struct { node: ?TreeNode, key: ?ItemKey, pos: core.Vec2, anchor: core.Rect, from_keyboard: bool };

pub const TreeResult = struct {
    // 持续性状态
    hovered: bool,
    focused: bool,
    focus_key: ?ItemKey,
    selection: *const Selection,
    selected_visible: usize,
    // 激活类结果（触发同帧第二构建遍，REQ-FRAME-030）
    selection_changed: bool,
    activated: ?TreeNode,
    toggled: []const Toggle,               // 帧竞技场
    context_menu: ?TreeContext,
};

pub fn beginTree(ui: *Ui, src: std.builtin.SourceLocation, model: TreeModel, opts: TreeOptions) TreeIter;
pub fn endTree(ui: *Ui) TreeResult;

pub const TreeLabelOptions = struct { icon: ?theme.Icon = null };
/// 行内的图标 + 单行文字；缩进与展开箭头由行节点绘制，内容从内容起点开始。
pub fn treeLabel(ui: *Ui, src: std.builtin.SourceLocation, row: TreeRow, text: []const u8, opts: TreeLabelOptions) void;
```

`TreeModel` 按值传入，回调的 `ctx` 须存活至 `endTree` 返回；`toggled`、`context_menu`、`selection_changed`、`activated` 是激活类结果。`selection`/`expanded` 指针由应用持有，须存活至 `endTree` 返回。`opts.changed` 与 `TreeModel.version` 的语义见 REQ-W-TREE-005。

## 13. 保留状态

| 字段 | 类型 | 保留级别 | 说明 |
|---|---|---|---|
| `TreeState`（整体） | 保留节点（`ui.retained(TreeState, id, .sticky)`） | 保留节点 | 展平缓存、展开集合、滚动、焦点、锚点、搜索缓冲 |
| `flat` | 行数组（24 B/行）+ 键到下标映射 | 保留节点 | REQ-W-TREE-003；LRU 回收后按展开集合重新展平 |
| `version_seen` | `u64` | 保留节点 | 上次同步的 `TreeModel.version` |
| `expanded` | `ExpandedSet` | 保留节点 | 应用未提供 `expanded` 时使用；可持久化 |
| `offset_px`、`focus`、`anchor`、`search`、`press`、`own_selection` | 同 list | 保留节点 | 见 list.md 第 13 节 |
| 箭头旋转进度 | `ui.animate` 槽 | transient | 行节点内 |

**REQ-W-TREE-028**　树的保留节点为 sticky（REQ-FRAME-010）：被 LRU 回收后展平缓存重建（展开集合若由框架持有且已持久化则从设置恢复，否则回到初始展开状态），偏移、焦点、锚点重置；应用持有的 `Selection` 与 `ExpandedSet` 不受影响。展平缓存的内存随可见行总数线性增长（每行约 24 字节加映射）；100 万行约数十 MB，列为 OPEN-W-TREE-05。

## 14. 失效规则

**REQ-W-TREE-029**　绘制键与布局输入键**必须**如下：行节点的绘制键 = (list 的各项、`depth`、`has_children`、`expanded`、占位行标记)；箭头旋转经 `ui.animate` 的 `paint` 级动画而非绘制键。行节点的布局输入含 `depth`（决定内容起点）。展开/折叠使窗口内行的集合与位置变化，因此：

| 变化 | 置脏级别 | 损伤范围 |
|---|---|---|
| 展开/折叠节点（输入事件） | `build`；展平缓存增量更新；`toggled` 触发第二遍 | 从 `max(切换行顶, 视口顶)` 到视口底的区域：切换行在视口内时为其行顶起；切换行在视口上方时（偏移不变，视口内各行的下标整体改变）为整个视口；切换行在视口下方时无可见变化，损伤为空（REQ-FRAME-043） |
| 箭头旋转动画帧 | `paint`（构建遍数 0） | 该行的箭头位矩形 |
| 悬停进入/离开行 | `paint` | 该行矩形 |
| 选择/焦点变化 | `build` | 同 list |
| 滚动 | `build`；按 REQ-W-SCROLLVIEW-026 | 视口矩形与滚动条矩形 |
| `version`/`changed` 变化 | `build`；全量重建或子树重建 | 由差分决定 |

**REQ-W-TREE-030**　**可计量断言**：(1) 同 REQ-W-TREE-006 的 (a)–(d)。(2) 展开一个有 1000 个子项的节点（位于 100 万行的缓存中）：被构建的行节点数仍 ≤ 可见行数 + 缓冲行数；对 `TreeModel` 的调用次数：`child_count` 1 次、`child_at` 1000 次、`has_children` 与 `key_of` 各 ≤ 1000 次、其他节点的 `child_count`/`child_at` 0 次（增量，REQ-W-TREE-004）。(3) 箭头旋转动画期间每帧构建遍数 0，`frame.nodes_painted` 只含该行节点及与损伤相交的祖先。(4) 无变化的重复 `invalidate(.build)` 损伤为空，`frame.presents` 不变。

## 15. 边界与错误情况

**REQ-W-TREE-031**　模型不一致的处理：`key_of` 返回重复键（两个节点同键）——调试构建断言并报告两个节点（同 REQ-FRAME-005 的精神），发布构建以先出现者为准、后出现者作为不可选的普通行并记录 `err`；节点在展开状态下被应用删除——`changed` 通知其父节点后，其行与其后代的行从缓存移除，展开集合中的键保留（节点可能被重新加入）；焦点行节点被删除——按 REQ-W-TREE-023 的转移；展开一个 `has_children` 为假的节点无效果（不进入展开集合）。

| 情况 | 规定 |
|---|---|
| 根无子项（`child_count(root) = 0`） | 空状态，同 list |
| 展开 100 万子项的节点 | 一次性 O(子项数) 的展平，不在帧内分批；调试构建在其超过 100 ms 时记录 `warn` |
| 展开时回调阻塞 | 违反 REQ-FRAME-026，应用责任 |
| `persist` 读入键不对应任何节点 | 保留在展开集合，不影响显示 |
| 双击落在箭头位 | 两次按下各切换一次（REQ-W-TREE-014） |
| 持有焦点的行所在祖先被折叠 | 焦点移到该祖先，选择不变（REQ-W-TREE-023） |
| 按下期间节点消失 | 待折叠取消，选择不变 |
| 展开动画期间节点被折叠 | 动画从当前值朝新目标继续（REQ-FRAME-045） |
| 禁用中途发生 | 同 list（REQ-W-LIST-047）；展开集合保持 |
| 深度超过 `max_depth` | 该分支不展平并告警（REQ-W-TREE-012） |
| 窗口非活动 | 同 list：选中底为非活动色 |

## 16. 验收标准

下列夹具 `T1`：`multi`，`row_h` = 22，`scale` = 1.0，视口高 220 lpx（10 行），模型（节点名即键）：
```
A
├ A1
├ A2
│ ├ A2a
│ └ A2b
└ A3
B
└ B1
C
```
初始全部折叠，展平序为 [A, B, C]（下标 0–2）。展开 A 后 [A, A1, A2, A3, B, C]；再展开 A2 后 [A, A1, A2, A2a, A2b, A3, B, C]。

**AC-W-TREE-001**　`[金图]` 覆盖：REQ-W-TREE-008、REQ-W-TREE-009、REQ-W-TREE-007、REQ-W-TREE-001。渲染 `T1` 全部展开并带图标：{选中且 active, 选中且失焦, 悬停, 焦点行指示, 禁用, 加载占位行（给 B 设为 `loading`）} × 浅/深/高对比度 × 缩放 1.0/1.5/2.0。预期：与基准图一致；深度 0/1/2 的箭头位 x 分别为 `pad_item_x` 起 0/16/32 lpx（换算 ppx 后对齐整数）；叶子行无箭头但文字与同级有子项行的文字对齐；无连接线；占位行文字"加载中…"为 `text_secondary` 且无选中底；选中底占满整行宽；箭头选中且 active 时为 `text_on_accent`；折叠为 `chevron_right`、展开为 `chevron_down`。

**AC-W-TREE-002**　`[单元]` 覆盖：REQ-W-TREE-002、REQ-W-TREE-003、REQ-W-TREE-004。展平缓存单元测试（无窗口，带调用计数的模型）：初始建立 → 行 [A, B, C]，仅对顶层节点调用 `has_children`/`key_of`，`child_count(root)` 1 次；展开 A（下标 0）→ 插入 A1、A2、A3，行 [A, A1, A2, A3, B, C]，`parent` 依次为 none, 0, 0, 0, none, none，`child_count(A)` 1 次、其他节点 0 次；展开 A2（下标 2）→ [A, A1, A2, A2a, A2b, A3, B, C]，`A3`、`B`、`C` 的下标各 +2，A3 的 `parent` 仍为 0，A2a、A2b 的 `parent` 为 2；折叠 A → [A, B, C]，A2 仍在展开集合中；再展开 A → [A, A1, A2, A2a, A2b, A3, B, C]（后代展开状态保留）。键 → 下标映射：`indexOf(A3)` = 5。焦点行与锚点随平移更新：展开 A2 之前 `F` = A3（下标 3）、锚点 = A1（下标 1）；展开 A2（下标 2）后 `F` 的下标为 5，锚点下标仍为 1。

**AC-W-TREE-003**　`[回放]` 覆盖：REQ-W-TREE-017、REQ-W-TREE-018、REQ-W-TREE-023。夹具 `T1`，`Sel` = ∅，焦点 Tab 到树（F = A，下标 0，`Sel` ∅）。① → → 展开 A，F A，`Sel` ∅，展平 [A, A1, A2, A3, B, C]，`toggled` = [{A, 展开}]（第二遍为空）。② → → F = A1，`Sel` = {A1}，A1。③ → 于叶子 A1 → 无变化。④ ← → F = A，`Sel` = {A}，A = A（移动并选中父节点）；⑤ ← → 折叠 A（已展开），F A，`Sel` {A} 不变，展平 [A, B, C]；⑥ ← 于已折叠的顶层 A → 无变化。⑦ ↓ → F B，`Sel` {B}；→ → 展开 B（B1 出现）；→ → F B1，`Sel` {B1}；← → F B，{B}。⑧ 展开 A、A2 后 F = A2b（下标 4），`Sel` {A2b}，A = A2b；点击 A 的箭头位折叠 A→ 展平 [A, B, C]，F ← A、A ← A（下标 0），`Sel` 仍为 {A2b}（隐藏保留），`selection_changed` 假，`toggled` 含 {A, 折叠}。⑨ 在 F = A（折叠）时 Shift+→ → 展开 A（等同 →）；Shift+← → 折叠 A（等同 ←）；Ctrl+→、Ctrl+← → 树不处理（`F`、`Sel`、展开状态不变，键冒泡）；Alt+→ 不处理；Ctrl+PageDown → 不处理（冒泡）。⑩ 无焦点行时 → ← 无作用。

**AC-W-TREE-004**　`[回放]` 覆盖：REQ-W-TREE-019、REQ-W-TREE-020、REQ-W-TREE-021、REQ-W-TREE-022。夹具 `T1` 全折叠，F = A。① 小键盘 `*` → 展开 A 与 A2（A2 有子项），展平 [A, A1, A2, A2a, A2b, A3, B, C]；B 不受影响；F 与选择不变；`toggled` = [{A,展开},{A2,展开}]。② F = A2（下标 2，折叠状态，另设）：小键盘 `+` → 展开；再按 `+` → 无变化；小键盘 `-` → 折叠；再按 `-` → 无变化；F = A1（叶子）`+`/`-` 无作用。③ 主键盘区的 `+`、`-` 不展开折叠（作为字符参与前缀搜索；`text_of` 缺失时不消费）。④ Enter：F = A2（有子项）→ 切换展开，不报告 `activated`；F = A1（叶子）→ `activated` = A1；`activate_parents = true` 时 F = A2 的 Enter → 切换展开且 `activated` = A2。⑤ 上限：构造 `*` 要展开 150000 个节点的模型 → 恰展开 100000 个后停止，调试构建 1 条 `warn`，已展开部分保留。⑥ 命令快捷键绑定小键盘 `+` → 命令优先，不展开。

**AC-W-TREE-005**　`[回放]` 覆盖：REQ-W-TREE-013、REQ-W-TREE-014、REQ-W-TREE-015、REQ-W-TREE-016。夹具 `T1`，A 与 A2 已展开（[A, A1, A2, A2a, A2b, A3, B, C]，行 i 占 y ∈ [22i, 22i+22)），`Sel` = {A1}，A = A1，F = A1。① 点击 A2 的箭头位（depth 1：x ∈ [8 + 16, 8 + 16 + 16) = [24, 40)，行下标 2，y = 55）→ A2 折叠，`Sel` {A1}、F、A 不变，`selection_changed` 假，`toggled` = [{A2,折叠}]；再点击 → 展开。② 点击叶子 A3 的箭头位 x = 30（depth 1 的箭头位，无箭头）→ 按行点击处理：`Sel` = {A3}。③ 点击 A2 的文字（x = 80）→ `Sel` = {A2}，不展开。④ 双击 A2 的文字 → 第二次点击时展开状态切换（折叠），`activated` 无；双击叶子 A1 → `activated` = A1；`activate_parents` 开启后双击 A2 → 切换展开且 `activated` = A2；Ctrl+双击 → 无切换、无 `activated`。⑤ 双击箭头位：两次按下各切换一次，结果状态与初始相同。⑥ `multi`：点击 A1，Shift+点击 A3 → `Sel` = {A1, A2, A2a, A2b, A3}（展平序可见行区间）；折叠 A2 后再 Shift+点击 A3（锚点 A1）→ `Sel` = {A1, A2, A3}（A2a、A2b 不可见不入区间，且替换清除了先前的隐藏选中）。⑦ 右键 B → `Sel` = {B}，`context_menu` = {node B, from_keyboard 假}；右键空白处 → `node = null`。⑧ 点击占位行 → 无选择变化，树取得焦点。

**AC-W-TREE-006**　`[回放]` 覆盖：REQ-W-TREE-023、REQ-W-TREE-024、REQ-W-TREE-025。夹具 `T1`，A、A2 已展开，`multi`，`Sel` = {A2b, A3}，F = A2b，A = A2b。① 折叠 A（点击 A 的箭头位）→ 展平 [A, B, C]；F = A，A（锚点）= A；`Sel` 仍 {A2b, A3}；`selection_changed` 假。② Shift+点击 C → `Sel` = {A, B, C}（替换；A2b、A3 被清除），F = C，锚点 A。③ 恢复到①后的状态（`Sel` {A2b, A3}，锚点 A）Ctrl+Shift+点击 C → `Sel` = {A2b, A3, A, B, C}。④ 同状态 Ctrl+点击 B → `Sel` = {A2b, A3, B}（保留隐藏项），锚点 B。⑤ 同状态 Ctrl+A → `Sel` = {A2b, A3, A, B, C}。⑥ 同状态普通点击 B → `Sel` = {B}（隐藏项被清除）。⑦ 承接 ① 之后的状态（未执行 ②–⑥ 的改动，即 `Sel` = {A2b, A3}，F = A，锚点 = A，A 折叠、A2 仍在展开集合中）：点击 A 的箭头位展开 A → 展平 [A, A1, A2, A2a, A2b, A3, B, C]（A2 仍展开），A2b 与 A3 显示选中底，`Sel`、F、锚点不变，`selection_changed` 假；`TreeResult.selected_visible`：① 状态为 0，⑦ 状态为 2。⑧ 承接 ⑦，视口改为 5 行（110 lpx），先点击 B 的文字（B 的行下标 6，占 [132, 154)；`Sel` = {B}，滚入后偏移 = 154 − 110 = 44），再点击 B 的箭头位展开 B（B1 出现于下标 7，占 [154, 176)）→ 焦点与选择不变，偏移保持 44（不自动滚动，B1 在视口 [44, 154) 之下）；按 → 移到 B1 → F = B1，`Sel` = {B1}，偏移 = 176 − 110 = 66（最小位移使 B1 完整可见）。

**AC-W-TREE-007**　`[回放]` 覆盖：REQ-W-TREE-007。夹具 `T1`，B 的 `load_state` 为 `loading`（子项尚未提供）。展开 B → `toggled` = [{B,展开}]；展平 [A, B, B 的占位行, C]（A 折叠）；占位行文字"加载中…"；点击占位行 → 无选择变化；F = B 按 ↓ → F = C（跳过占位行）；Shift+↓ 区间含占位行时占位行不入 `Sel`；Ctrl+A 不选占位行；前缀搜索不命中占位行。应用把 B1 提供出来并把 `load_state` 置为 `loaded`、递增 `version` → 下一次构建占位行被 B1 替换，展开状态保留，焦点与选择按键重新定位。`has_children(B)` 为真而 `child_count(B)` = 0：展开 B 后不插入任何行，箭头位保持。占位行计入 `list.virtual_nodes`。

**AC-W-TREE-008**　`[单元]` 覆盖：REQ-W-TREE-010、REQ-W-TREE-011、REQ-W-TREE-026、REQ-W-TREE-028。窗口 `persist_name` = "main"，树 `persist` = "tree1"，`str_key_of` = 节点路径（"A"、"A/A2" …），`ItemKey = Key.str(路径).hash`。步骤与预期：首次运行无记录 → 全部折叠；展开 A、A2 → `ui.trees["main/tree1"]` = ["A", "A/A2"]（字典序），每次展开/折叠各写一次；重启后首次出现 → 展开集合读入，A、A2 即刻展开；记录中含不存在的键 "Z" → 保留（`ExpandedSet.contains(Key.str("Z"))` 真），重新写出时仍含；`str_key_of` 为空而 `persist` 非空 → 调试构建断言；窗口无 `persist_name` → 无条目；`initially_expanded_depth` = 1 且无记录 → 顶层节点均展开（A、B 展开，A2 不展开）；有记录时忽略该选项；应用传入 `expanded` 指针 → 用户操作写回该集合；框架保留的展开集合在被 LRU 回收后（未持久化）回到初始展开。`toggled` 在 `*` 展开多个节点时逐个列出。

**AC-W-TREE-009**　`[回放]` 覆盖：REQ-W-TREE-009。夹具 `T1`，假时钟，`client_animation = true`。展开 A（点击箭头位）→ 动画第 0 帧箭头旋转角 0°；推进 60 ms 角度在 (0°, 90°) 内且单调；推进到 120 ms → 90°，之后画静止的 `chevron_down`；动画期间每帧构建遍数 0，损伤 = 该行箭头位矩形（≤ 16 × 22 lpx 的面积）。折叠 → 90° → 0°；动画进行中再次切换 → 从当前角度朝新目标继续。`client_animation = false` → 点击后同帧即到目标角度，不登记活动动画（`loop.block_waits` 随后增加）。滚动使已展开的行进入视野 → 直接为 `chevron_down`，无动画。

**AC-W-TREE-010**　`[计量]` 覆盖：REQ-W-TREE-001、REQ-W-TREE-005、REQ-W-TREE-006、REQ-W-TREE-031。前置：模型含 1000 个顶层节点，每个有 1000 个子项，全部展开 → 展平 1,001,000 行；视口 30 行（660 lpx），`row_h` 22；已稳定；回调带调用计数。步骤与预期：回放每帧 `wheel -1`（1010 帧）→ 每帧 `list.virtual_nodes` ≤ 40；`child_count`、`child_at`、`has_children` 调用累计 0；`key_of`、`text_of` 每帧 ≤ 40；`time.frame_cpu` P99 ≤ 2.0 ms；换成 1010 行展平规模（10 个顶层 × 100 个子项，共 10 + 1000 行）相同回放 → 两个规模的 `time.frame_cpu` P99 之比 ≤ 1.5；两规模的 `frame.nodes` 相等。位置精确（REQ-W-LIST-053）：对 1,001,000 行取偏移 `offset_px.y` = 16 777 217（视口 660、行高 22）→ 首个可见行 762 600，位置 −17，再 +1 → −18，算例同 AC-W-LIST-023。`version` 递增一次 → 全量重建发生一次（`child_count` 累计 ≈ 1000 + 1），其后帧恢复为 0 调用。`changed = [某顶层节点]` → 只对该节点子树调用回调（`child_at` ≈ 1000，其他节点 0 次）。

**AC-W-TREE-011**　`[计量]` 覆盖：REQ-W-TREE-004、REQ-W-TREE-030、REQ-W-TREE-029。前置：同 AC-W-TREE-010 的 100 万行模型，把其中某顶层节点折叠后位于下标 500000 附近。步骤与预期：展开它（1000 个子项）→ 该帧回调计数：`child_count` 1、`child_at` 1000、其他节点 0；行节点数 ≤ 40；缓存在展开点之后的行下标平移 1000（取样断言 `indexOf` 变化）。折叠 → 删除 1000 行，回调 0 次。损伤：展开点（节点原下标）位于视口内时 = 从该行顶到视口底的矩形；位于视口上方（偏移不变，视口内容整体改变）时 = 整个视口矩形；位于视口下方时无可见变化，损伤为空、不绘制不提交（REQ-FRAME-043）。三种情形损伤面积分别 ≤ 视口面积、= 视口面积、= 0。箭头旋转动画期间每帧构建遍数 0，`frame.nodes_painted` 只含该行节点及相交祖先。无变化的 `invalidate(.build)` → 损伤为空。悬停进入/离开行 → 构建遍数 0。

**AC-W-TREE-012**　`[回放]` 覆盖：REQ-W-TREE-001、REQ-W-TREE-022。夹具 `T1` 展开 A 与 A2，行文本即节点名（"A"、"A1"、"A2"、"A2a"、"A2b"、"A3"、"B"、"C"），`text_of` 已提供。前缀搜索：F = A，输入 'a' → 从 F+1 起搜索 → F = A1（"A1"），`Sel` {A1}；输入 "2" 于 400 ms 内 → 缓冲 "a2"，自 F（含）起 → "A2" 命中 → F = A2；折叠 A 后输入 'a' → 只在可见行搜索（A 自身，F+1 起回绕 → A）。Ctrl+A → 全部**可见**行选中。Home/End、PageUp/PageDown、Ctrl+Space、Space 在展平序上与 list 行为一致（取 list 的 AC-W-LIST-008 至 AC-W-LIST-010 的对应步骤，下标换成展平下标）。拖动无重排；`count` 变化（展开）使偏移越界时夹紧。

**AC-W-TREE-013**　`[单元]` 覆盖：REQ-W-TREE-027。经假 UIA 入口：树 ControlType Tree，行 TreeItem；A 的 ExpandCollapseState = Collapsed，`Expand()` → 下一帧展开并 `toggled` 一次，`Level` 属性 A（深度 0）为 1、A2（深度 1）为 2、A2a（深度 2）为 3；`Collapse()` 同理；叶子 A1 的 State = LeafNode，`Expand()` 被忽略；`SelectionItem.Select` 于 A2 → `Sel` {A2}（不改变展开）；`Invoke` 于叶子 → `activated`，于有子项的行 → 切换展开；Name = `text_of`。

**AC-W-TREE-014**　`[单元]` 覆盖：REQ-W-TREE-008、REQ-W-TREE-012、REQ-W-TREE-031。几何：`scale` = 1.0，深度 2 的行：箭头位 x ∈ [8 + 32, 8 + 32 + 16) = [40, 56)，内容起点 x = 56 + `gap_xs`（2）= 58（令牌：`pad_item_x` 8、`indent` 16、`icon_sm` 16、`gap_xs` 2）；`scale` = 1.5：箭头位 x ∈ [60, 84)，内容起点 87。深度：构造深度 300 的链 → 超过 `max_depth` 256 的分支不展平，调试构建 1 条 `warn`；含环的模型不死循环。键重复：两个节点 `key_of` 同值 → 调试构建断言；发布构建后者为不可选的普通行并 1 条 `err`。展开 `has_children` 为假的节点 → 无效果、不入展开集合。删除展开中的节点（经 `changed` 通知其父）→ 该节点及其后代行移除，展开集合保留其键；焦点行被删除 → F 取原下标夹紧后的行。

**AC-W-TREE-015**　`[人工]` 覆盖：REQ-W-TREE-006、REQ-W-TREE-009、REQ-W-TREE-014、REQ-W-TREE-019、REQ-W-TREE-024。在真实 Windows 上的示例应用"树"页（文件系统式树，惰性加载目录；另有 100 万行合成树）：用鼠标点击箭头、双击文件夹与文件、键盘 →/←/`*`/小键盘 `+`/`-`；展开含大量子项的目录观察占位行与替换；折叠含选中项的祖先后再展开观察选中恢复；对 100 万行合成树用滚轮与滚动条拖动，确认无卡顿；系统关闭动画与 150%/200% 缩放下观察箭头旋转与对齐。观察要点：箭头旋转平滑且不抖动、缩进对齐整数像素、折叠后焦点移到祖先、占位行不可选。

## 17. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-W-TREE-01 | 拖放改变层级（应用内拖放，把节点拖到另一节点之下/之间） | 本版不做；将来可复用 list 的拖放与覆盖层指示，放置语义（成为子项 / 在其前 / 在其后）与持久化需另行定义 |
| OPEN-W-TREE-02 | 主键盘区的 `+`/`-`/`*` 是否也应展开折叠 | 不；它们是可打印字符，参与前缀搜索；与原生 TreeView 一致，且避免与前缀搜索冲突 |
| OPEN-W-TREE-03 | 折叠含选中后代的祖先时是否应把选择移到祖先（原生行为） | 本文保留隐藏的选中（REQ-W-TREE-024）、只移动焦点；理由：不丢失用户的多选；代价见 `selected_visible` |
| OPEN-W-TREE-04 | （已关闭，见 REQ-W-TREE-009：09 的 `drawMark` 已有 `rotation` 参数） | — |
| OPEN-W-TREE-05 | 展平缓存按行物化：100 万行约 24 MB + 映射；展开 100 万子项时的一次性 O(n) | 先接受；若成为问题，改用"展开节点的可见子树大小"的顺序统计结构按需定位（接口不变） |
| OPEN-W-TREE-06 | 数据变更通知粒度：目前为全局 `version` 与逐节点 `changed` | 先如此；惰性加载频繁时用 `changed` |
| OPEN-W-TREE-07 | 程序化"展开到某节点并滚入"（需要父链） | 回调无父指针，暂不提供；应用可自行展开各祖先并设置 `Selection` |
| OPEN-W-TREE-08 | 加载失败态（`load_state = failed`）与重试 | 暂不提供；应用把节点置 `loaded` 且无子项，或在行内容中自行表达 |
