# 数据表（table）

> 本文复用 [list.md](list.md) 的行虚拟化与**选择模型**（list.md 5.3 节），只写差异。布局语义（列宽求解 `layout.solveColumns`、`ColumnWidth`）引用 07 的 REQ-LAYOUT-038 至 REQ-LAYOUT-040；滚动条、滚轮与滚动规则引用 [scroll-view.md](scroll-view.md)。

## 1. 用途

以表头加多列的形式展示大量同构记录，支持行选择、按列排序（由应用执行）、调整列宽、重排列与横向滚动。参照 Windows 的 ListView 报表视图（`LVS_REPORT`）与 DataGrid 的只读使用。本控件**必须**同时做**行虚拟化与列虚拟化**：只为可见行与可见列创建单元格节点，行数可达百万、列数可达数十（REQ-PERF-022：100 万行 × 20 列）。

- 单列条目 → 用 list；层级数据 → 用 tree。
- 需要就地编辑单元格、合并单元格、单元格级选择 → 本版不支持（单元格导航列为待定）。
- 少量行（几十行以内）且单元格内容复杂 → 用 07 的 Table 容器（`beginTable`，非虚拟化）加普通控件。
- 键值对的属性页 → 用 07 的 Form。

## 2. 解剖

```
┌────────────────────────────────────────────┬──┐ ← 框：drawSunken
│ 名称 ▲        │      大小 │ 类型     │ 修改…  │▲ │ ← 表头（凸起表面，header_h）
│               ┆           ┆          ┆        │█ │   ┆ = 列边界（命中带 splitter_w 在列的右端）
├───────────────┼───────────┼──────────┼────────┤█ │
│ readme.md     │    1,024  │ 文件     │ 2024…  │  │ ← 行（row_h）；网格线 border_subtle
│▌说明.txt（选中）│      512  │ 文件     │ 2024…  │  │
│ src           │         — │ 文件夹   │ 2024…  │  │
├───────────────┴───────────┴──────────┴────────┤  │
│◀ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░ ▶│  │ ← 横向滚动条（表头随之同步）
└────────────────────────────────────────────┴──┘
```

- **框**：整个控件外缘，`drawSunken`。
- **表头**：位于框内顶部、`header_h` 高的凸起表面条，由**表头单元格**（标题、排序标记）与**列边界**（调整列宽的命中带）组成；不随纵向滚动。
- **行**、**单元格**：行高 `row_h`，行内按列声明单元格。
- **网格线**：`border_subtle`，可选水平/垂直。
- **滚动条**：纵向条只覆盖表头之下的行区域；横向条在行区域底部。
- **表头底块**：纵向滚动条显示时表头右端补上的与滚动条等宽的凸起块，使表头与行区域对齐。
- **放置指示线**：重排列时画在覆盖层的竖线。

## 3. 度量与布局

| 项 | 取值（令牌） |
|---|---|
| 表头高度 | `header_h` |
| 表头文字 | `font_body_strong` |
| 行高 | `row_h`（选项 `row_height` 指定固定值，同 list） |
| 单元格左右内边距 | `pad_item_x` |
| 表头标题与排序标记间距 | `gap_sm` |
| 排序标记 | `drawMark(sort_asc / sort_desc)`，边长 `icon_sm` |
| 列边界命中带宽度 | `splitter_w`（位于该列右端、列内） |
| 列最小有效宽度 | `max(列的 min, 2 × pad_item_x + icon_sm)` |
| 网格线 | `border_subtle` 发丝线 |
| 框圆角、框内缩 | `radius_control`；`Params.border = 1`（一个发丝线宽度，REQ-LAYOUT-056） |
| 滚动条 | `scrollbar_w`、`scrollbar_thumb_min` |
| 缓冲行、缓冲列 | 视口上下各 5 行（同 list）；视口左右各 1 列（常量 `table_buffer_cols`） |
| 首次出现的回退 | 32 行 × 显示序前 16 列 |

**REQ-W-TABLE-001**　控件由下列节点构成：根（框，`drawSunken`，`Params.border = 1`，登记 `click`、`context`，可聚焦）→ 表头条 + 行区域滚动视图（scroll-view，`axes = both`，`bar_v`/`bar_h` 取选项 `scrollbar_v`/`scrollbar_h`（默认 `auto`），`report_viewport = true`，偏移由表格持有）。表头条在行区域**之外**（之上），不属于行区域的滚动内容，因此纵向滚动条只覆盖行区域。默认尺寸策略：主轴 `grow(1)`、交叉轴 `fill`，最小高度 `header_h + row_h`；调用方**可以**经 `layout` 选项覆盖。

**REQ-W-TABLE-002**　**列声明**：应用在每次构建传入 `columns: []const TableColumn`（借用至本帧结束，列的个数、顺序是列的**逻辑序**，下标即**列号**）。`TableColumn` 含：`title`、`width: layout.ColumnWidth`（`fixed(v)`、`grow(weight)`、`auto_header`，07）、`min`/`max`（lpx）、`h_align`（`left`/`right`/`center`，默认 `left`；数值列应用 `right`）、`font`（`theme.FontToken`，默认 `body`；数值列建议 `mono`）、`sortable`（默认假）、`resizable`（默认真）、`hidden`（默认假；列的**初始**可见性，之后由框架持有有效可见性，见 REQ-W-TABLE-031）。列数为 0 时只画框与表头条。

**REQ-W-TABLE-003**　**列宽求解**：显示序（REQ-W-TABLE-022 的顺序，隐藏列不参与）上各列的有效宽度由 `layout.solveColumns`（REQ-LAYOUT-039）求出：输入为各列的 `ColumnWidth`（被用户调整过宽度的列视为 `fixed(用户宽度)`）、`auto_header` 列的表头自然宽度（标题以 `font_body_strong` 测得，加 `2 × pad_item_x`，可排序列再加 `gap_sm + icon_sm`）、视口宽度（确定限制）与 `col_gap`（本控件固定为 `none`）。每列有效宽度再夹紧到 `[列最小有效宽度, max]`。`solveColumns` 是纯函数，每次构建对列数 O(列数) 调用一次，结果同时供表头与全部行使用，保证二者对齐。内容总宽 = 各列有效宽度之和；它不足视口宽度时 `grow` 列按 07 的规则分配剩余，全部为 `fixed`/`auto_header` 时行末留空白（表头条同样留空白，凸起底）。

**REQ-W-TABLE-004**　**行虚拟化同 list**：REQ-W-LIST-003（固定行高、整数 ppx、`virtual_extent_px`/`offset_px` 的 i64 大内容坐标，REQ-LAYOUT-054）、053（行位置逐像素精确，100 万行及以上也成立）、004（可见窗口与缓冲 5 行）、005（不可见行无节点，`list.virtual_nodes` 计量）、006（迭代协议，`TableIter`）、007（首次视口回退与布局反馈）、008（稳定键，`data.key_of`）、009（构建代价与总量无关）、015（焦点行与锚点的校正）、052（数据变化时的校正）在表格中原样适用，"行"指数据行（表头不是行、不占行下标、不参与选择）。视口高度取行区域的高度（扣除表头条与横向滚动条）。

**REQ-W-TABLE-005**　**列虚拟化**：横向偏移 `off_x`（ppx）、行区域视口宽 `vw`（ppx）下，显示序中列的横向区间与 `[off_x, off_x + vw)` 相交者为**可见列**；被创建单元格节点的列为可见列各向两侧扩展 `table_buffer_cols = 1` 列（夹紧在 `[0, 显示列数 − 1]`），即**已创建列**。不在已创建列内的单元格**不得**创建节点；行内第一个已创建列之前的横向距离由一个定宽前导占位叶子表达。每个行节点的单元格节点数 = 已创建列数，与总列数无关。表头同样只为已创建列创建表头单元格与列边界节点。

**REQ-W-TABLE-006**　**行与单元格的节点结构**：行节点以相对行区域视口的整数 ppx 位置排布（`virtual_pos_px.y = i × row_px − off_y`，无前导占位行），是水平 Row（固定高 `row_px`，宽 `max(内容总宽, 视口宽)`，不设内边距，裁剪子项）；其子项依次为：前导占位叶子（宽 = 第一个已创建列之前各列有效宽度之和，为 0 时省略）、已创建列的单元格节点。单元格节点是宽度固定为该列有效宽度、高 `row_px` 的 Row 容器，左右内边距 `pad_item_x`，子项在交叉轴居中，裁剪子项。行宽大于内容总宽的部分（视口比内容宽时）仍属于行节点，使选中底、悬停底、交替底色与网格线横跨整个视口宽度。

**REQ-W-TABLE-007**　**表头条**：高 `header_h`，宽等于行区域视口宽；整体先画 `drawRaised(neutral)`（圆角取 `radius_mark`，与框的内缩一致），其内各表头单元格依显示序排列、宽度同对应列的有效宽度；表头单元格内容为：标题（`font_body_strong`，按列 `h_align` 对齐，超宽尾部省略）与（当前排序列时）排序标记，左右内边距 `pad_item_x`；列边界为每个已创建列右端、宽 `splitter_w` 的命中带，其可见线是该列右边缘一条竖直发丝线（`drawSeparator`，`border_subtle`，上下各内缩 `gap_sm`；指针悬停在该列边界上时改为 `border_strong`）。最后一列之后的剩余宽度画表头底（凸起，无标题）。表头不是焦点节点，不参与 Tab 序（REQ-W-TABLE-028）。

**REQ-W-TABLE-008**　**表头冻结与横向同步**：表头始终可见，不随纵向滚动；横向滚动时表头与行区域**同帧**使用同一个横向偏移（表头的横向位移取行区域本次构建生效的 `ScrollViewHandle.offset.x`，不取上一帧的值），因此表头列边界与行内网格线始终对齐。行区域纵向滚动条显示时，表头条右端补一个宽 `scrollbar_w`、高 `header_h` 的**表头底块**（凸起表面，`drawRaised(neutral)`），使表头条宽度等于行区域含滚动条的总宽。首列冻结（横向滚动时首列不动）本版不提供（OPEN-W-TABLE-01）。

**REQ-W-TABLE-009**　**单元格迭代协议**：`var t = w.beginTable(ui, @src(), columns, count, opts); while (t.next()) |row| { var cells = row.cells(); while (cells.next()) |cell| { … 用 cell.column 声明内容 … } } const res = w.endTable(ui);`。`t.next()` 的行为同 list 的迭代器（REQ-W-LIST-006）；`cells.next()` 结束上一个单元格节点并开始下一个**已创建列**的单元格（以列的稳定标识为 ID 种子压栈），返回 `TableCell`（含逻辑列号 `column`、显示序号、有效宽度、`h_align`、`font`、`text_color`）；耗尽时结束最后一个单元格。应用只需为 `cell.column` 声明内容，**不得**在内层或外层迭代中 `break`，**不得**为同一单元格声明多于一个顶层内容。常用的 `w.tableCellText` 在单元格内放置单行文字（按列 `h_align`、`font` 与省略规则）。

**REQ-W-TABLE-010**　**行与单元格的外观**：行底、悬停、选中、交替行、焦点行指示同 list（REQ-W-LIST-045，选中底 `drawSelection` 横跨整个行宽）；单元格文字默认 `text_primary`，所在行选中且 `active` 时 `text_on_accent`，禁用 `text_disabled`。**网格线**：选项 `grid`（`none`/`horizontal`/`vertical`/`both`，默认 `horizontal`）；水平线为每行底边一条发丝线 `border_subtle`，垂直线为每个列的右边缘一条发丝线 `border_subtle`（行内，随单元格绘制，对齐表头的列边界）；网格线画在选中底**之上**。数值列建议 `h_align = .right` 与 `font = .mono`（REQ-THEME-016）；本控件只执行声明，不做自动判断。

**REQ-W-TABLE-011**　**数据回调**：`opts.data` 的类型 `TableData` 在 list 的 `ListData` 之上增加 `cell_text(ctx, row, column) []const u8`（可选）：用于列宽自适应测量（REQ-W-TABLE-020）、前缀搜索（取显示序第一列，REQ-W-TABLE-027）与无障碍单元格名称。`key_of`/`index_of`/`prefix_search` 语义同 list；`item_text` 在表格中不使用。回调在构建函数内同步调用，不得阻塞（REQ-FRAME-026）。

**REQ-W-TABLE-012**　**空状态与隐藏列**：`count = 0` 时仍绘制框与表头（表头可点击排序、调整列宽、重排），行区域显示 `opts.empty_text`（同 list REQ-W-LIST-011）。有效隐藏（REQ-W-TABLE-031）的列不参与列宽求解、不创建节点、不出现在表头，仍占据列号与持久化记录中的位置；全部列隐藏时等同列数为 0。

## 4. 变体与参数

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `mode` | `SelectionMode` | `multi` | 行选择，同 list；`single`/`none` 规则同 list |
| `selection` | `?*Selection` | `null` | 同 list；键为行键 |
| `data` | `TableData` | `{}` | 回调（REQ-W-TABLE-011） |
| `row_height` | `?f32`（lpx） | `null` | 同 list |
| `alternate_rows` | `bool` | `false` | 奇数行底色 `surface_row_alt` |
| `grid` | `GridLines` | `.horizontal` | 网格线 |
| `empty_text` | `?[]const u8` | `null` | 空状态文本 |
| `scrollbar_v`、`scrollbar_h` | `layout.BarPolicy` | `auto` | 滚动条显示策略 |
| `sort` | `?*TableSort` | `null` | 非空：排序状态由应用持有；空：框架保留 |
| `allow_unsorted` | `bool` | `false` | 为真时点击表头循环 升序 → 降序 → 无排序 |
| `reorder_columns` | `bool` | `true` | 允许拖动表头重排列 |
| `header_menu` | `bool` | `false` | 为真时表头右键产生 `header_context` 请求（用于显示/隐藏列菜单） |
| `persist` | `?[]const u8` | `null` | 持久化名（11 REQ-APP-037，`UiStateStore.table`） |
| `tooltip_on_truncate` | `bool` | `true` | 被截断的单元格/表头文字悬停显示全文 |
| `enabled`、`key`、`debug_name`、`layout` | 通用 | | 见模板 |

变体只有 `mode`、`grid`（结构性与外观开关）；颜色、尺寸不可逐实例指定。

## 5. 状态

### 5.1 状态机

行区域的鼠标/键盘状态机（`press`、`search`）同 list.md 5.1（本控件无"拖动重排"行）。表头相关新增状态变量：`hdr ∈ {无, 待排序, 调整宽度, 拖动列, 已取消}`。

| 当前 `hdr` | 事件 | 条件 | 下一 `hdr` | 动作 |
|---|---|---|---|---|
| 无 | 左键按下于列边界命中带 | 该列 `resizable` 且启用 | 调整宽度 | 隐式捕获；记下 `start_px`（该列按下时有效宽度）、`press_x` |
| 无 | 左键按下于表头单元格（边界命中带之外） | 该列 `sortable` 或 `reorder_columns` | 待排序 | 隐式捕获；单元格显示为按下 |
| 无 | 左键按下于表头单元格 | 该列不可排序且不可重排 | 无 | 无 |
| 待排序 | 左键释放且点击成立 | 该列 `sortable` | 无 | 按 REQ-W-TABLE-013 循环排序，报告 `sort_changed` |
| 待排序 | 指针越过拖拽阈值 | `reorder_columns` | 拖动列 | 点击取消；开始列拖动（REQ-W-TABLE-021） |
| 待排序 | 指针越过拖拽阈值 | 不可重排 | 待排序（点击已取消） | 无 |
| 调整宽度 | 指针移动 | — | 调整宽度 | 宽度 ← 夹紧(`start_px + (x − press_x)`)，实时生效 |
| 调整宽度 | 左键释放 | 宽度与按下时不同 | 无 | 报告 `column_resized`；持久化写入 |
| 调整宽度 | Esc / 捕获取消 | — | 已取消 | 宽度恢复为 `start_px` |
| 调整宽度 | 双击（第二次点击于同一边界） | — | 无 | 宽度 ← 自适应值（REQ-W-TABLE-020） |
| 拖动列 | 指针移动 | — | 拖动列 | 更新放置指示线（覆盖层） |
| 拖动列 | 左键释放于有效位置 | 重排后顺序改变 | 无 | 更新显示序；报告 `columns_reordered`；持久化写入 |
| 拖动列 | Esc / 捕获取消 / 释放于无效位置 / 顺序不变 | — | 已取消（Esc、捕获取消）或 无 | 无变化 |
| 已取消 | 全部按键释放 | — | 无 | — |

### 5.2 视觉表现

| 部件 | 状态 | 绘制（基元 + 令牌） |
|---|---|---|
| 框 | 常态/禁用 | `drawSunken(R, radius_control, visual, false)`；禁用 `surface_sunken_disabled` |
| 表头条 | 常态 | `drawRaised(neutral)` 整条；标题 `font_body_strong`、`text_primary` |
| 表头单元格 | 悬停 | 该单元格矩形裁剪内重画悬停变体（`surface_raised_hover_*`），过渡 `dur_fast`；仅 `sortable` 或可重排的列有悬停变体 |
| 表头单元格 | 按下（待排序，指针在内） | 按下变体（`surface_raised_pressed_*`）；标题与标记下移 1 ppx（REQ-THEME-030）；`dur_instant` 进入 |
| 排序标记 | 升序 / 降序 | `drawMark(sort_asc / sort_desc, icon_sm 见方, text_secondary)`，位于单元格右端、列边界命中带之前；无排序的列不画 |
| 列边界可见线 | 常态 / 指针在边界上或调整中 | `border_subtle` / `border_strong` |
| 表头 | 禁用 | `surface_raised_disabled` 纯色，标题 `text_disabled`，无悬停与按下 |
| 行、选中、悬停、交替、焦点行 | — | 同 list（REQ-W-LIST-045） |
| 网格线 | — | `border_subtle`（REQ-W-TABLE-010） |
| 放置指示线（列重排） | 拖动列中 | 覆盖层竖线，宽 2 个发丝线，`accent_mark`，高 = 表头条高度 + 行区域视口高度 |
| 表头底块 | — | `drawRaised(neutral)`，无标题 |

### 5.3 选择模型

引用 list.md 5.3 节：概念 `Sel`（行键集合）、`F`（焦点行）、`A`（锚点行）、区间、模式与类型全部沿用。差异：选择对象是**整行**；单元格级选择与单元格导航本版不提供（OPEN-W-TABLE-02）；表头点击不改变选择。

## 6. 鼠标行为

**REQ-W-TABLE-013**　**点击排序**：在 `sortable` 列的表头单元格（列边界命中带之外）上左键点击（按下与释放在同一单元格内、未越过拖拽阈值）时，该列的排序状态按下表循环，并报告 `sort_changed = SortChange{ column, dir: ?SortDir }`（激活类结果）。**排序由应用执行**，框架只显示标记。

| 当前排序状态 | `allow_unsorted = false` | `allow_unsorted = true` |
|---|---|---|
| 该列未排序（含其他列当前排序） | 升序（其他列的标记消失） | 升序 |
| 该列升序 | 降序 | 降序 |
| 该列降序 | 升序 | 无排序（`dir = null`，标记全部消失） |

点击不可排序的列不改变排序、不报告结果。`Shift`+点击追加次级排序列本版不提供（OPEN-W-TABLE-03，按普通点击处理）。排序**在释放时**生效，不在按下时。

**REQ-W-TABLE-014**　**点击与拖动、边界的优先级**：表头单元格登记 `click`，`reorder_columns = true` 时另登记 `drag`；越过拖拽阈值（读取系统度量 `drag_size`，03；REQ-INPUT-017）即取消点击（不排序）并转入列拖动（REQ-W-TABLE-021）。列边界命中带的命中先于其所在表头单元格（边界节点是单元格的后声明子项）：在边界命中带内按下只会调整宽度，不会排序或拖动列。表头上的右键、中键不排序、不调整、不拖动；中键无任何效果。

**REQ-W-TABLE-015**　**排序状态**由框架保留（sticky，`TableSort{ column: ?u16, dir }`，`column = null` 为无排序），或由应用经 `opts.sort` 持有（此时指针指向的值是唯一事实来源，框架在点击时写回）。点击排序后框架**不**对数据排序，也不重新创建行的稳定键；应用在 `sort_changed` 的那一帧（第二构建遍）按新排序提供数据即可。排序列号是**逻辑列号**，不随列重排改变；列被隐藏时排序状态保留但不显示标记。

**REQ-W-TABLE-016**　**表头单元格内的布局与标记**：标题与排序标记在单元格内左右内边距 `pad_item_x` 之间排列：当前排序列在右端预留 `gap_sm + icon_sm` 画标记，标题占其余宽度并按 `h_align` 对齐；其他列标题占满宽度。标题超出可用宽度时尾部省略（REQ-THEME-018），被截断时悬停显示全文提示（REQ-W-TABLE-029）。标记不因被省略而消失。

**REQ-W-TABLE-017**　**表头悬停与指针形状**：指针在 `sortable` 或可重排列的表头单元格上时显示悬停变体；其余表头单元格无悬停变体；指针形状在表头单元格上为箭头，在 `resizable` 列的边界命中带上为 `size_we`（REQ-THEME-032，悬停与调整中均如此，调整中即使指针移出命中带也保持）；`resizable = false` 的列边界为箭头。

**REQ-W-TABLE-018**　**列宽调整（拖动）**：在 `resizable` 列的边界命中带（该列右端、宽 `splitter_w`）按下左键即进入调整，不需要越过拖拽阈值（边界节点只登记 `click`，不登记 `drag`）。拖动中每个 `pointer_move` 实时更新该列宽度：`新宽度_ppx = clamp(start_px + (指针x − press_x), 最小有效宽度_ppx, max_ppx)`，下一帧的表头与全部行立即按新宽度布局；**不**画虚影。调整结束后该列的有效宽度成为用户宽度（视同 `fixed(用户宽度 lpx)`），其余列保持各自的宽度规则（`grow` 列因剩余空间变化而重新分配）；调整可使内容总宽超出视口而出现横向滚动条。

**REQ-W-TABLE-019**　**调整的约束与取消**：宽度受 `[最小有效宽度, max]` 约束（最小有效宽度 = `max(列的 min, 2 × pad_item_x + icon_sm)`）；指针移到命中带左侧很远处宽度停在最小值，不会使列消失或变负。拖动中分隔列持有焦点时按 Esc、或捕获被取消（REQ-INPUT-024）时，宽度恢复为 `start_px`，Esc 被消费（不触发取消按钮），不报告 `column_resized`；此后到全部按键释放前的移动被忽略。仅在调整进行中，表格才声明 Esc 为其处理的键。释放时宽度与 `start_px` 不同则报告 `column_resized = ColumnResize{ column, width }`（lpx，激活类结果）并持久化（REQ-W-TABLE-031）。

**REQ-W-TABLE-020**　**双击边界自适应**：在 `resizable` 列的边界命中带上的左键点击满足 `click_count = 2` 时，该列宽度设为 `clamp(max(表头自然宽, 可见行内容最大宽 + 2 × pad_item_x), 最小有效宽度, max)`：表头自然宽 = 标题宽（`font_body_strong`）+ `2 × pad_item_x`（可排序列再加 `gap_sm + icon_sm`）；可见行内容最大宽 = 当前**可见行**（不含缓冲行）在该列的 `data.cell_text(row, column)` 以该列 `font` 测得宽度的最大值；`cell_text` 为空时只取表头自然宽。结果成为用户宽度，报告 `column_resized` 并持久化。双击不改变其他列。

**REQ-W-TABLE-021**　**列重排（拖动表头）**：`reorder_columns = true` 时，在表头单元格（边界命中带之外）按下并越过拖拽阈值后，控件调用 `ui.beginDrag(table_id, DragPayload{ kind = table_column_kind, data = 列号 })`；被拖动的单元格保持原位（无拖影）。表格经 `ui.dropTarget` 登记为放置目标并只接受自己发起的列拖动。设指针的内容 x 坐标（含横向偏移）为 `x`，插入位置 `ins` = 显示序中中点不大于 `x` 的已创建列个数（0 至显示列数）；覆盖层在显示序第 `ins` 列的左边缘（`ins` 等于显示列数时取最后一列的右边缘）画放置指示线（视口外则不画）。表头条左右边缘带（宽 `row_h`）内的横向自动滚动按 REQ-W-SCROLLVIEW-017（作用于行区域滚动视图的横向）。

**REQ-W-TABLE-022**　**重排结果**：在可接受位置释放时，把被拖动列从原显示位置 `p` 取出并插入新位置（`ins > p` 时插入到 `ins − 1`，否则到 `ins`）；新显示序与原来相同（`ins ∈ {p, p + 1}`）视为无操作，**不**报告。有改变时更新**显示序**（保存为逻辑列号的排列，REQ-W-TABLE-031）、报告 `columns_reordered`（激活类结果）并持久化。Esc（REQ-INPUT-059）、捕获取消、在表头之外释放时不改变显示序，覆盖层指示线随下一次构建消失。`reorder_columns = false` 时表头不登记 `drag`，按下后越过阈值也不重排（点击排序仍可用）。逻辑列号、排序状态、宽度不随重排改变。

**REQ-W-TABLE-023**　**行区域的鼠标选择**同 list（REQ-W-LIST-019 至 028、030，`F`/`A`/`Sel` 的变更完全一致，"行"为数据行）：单击、Ctrl+单击、Shift+单击、Ctrl+Shift+单击、在已选中的多行之一上按下的延迟折叠、右键、空白处点击、双击激活均按 list 规则，作用于整行（点击行内任何列的位置等价）；单元格内的交互控件先于行接收事件。表头区域的点击**不**产生行选择。

**REQ-W-TABLE-024**　**滚动**：行区域经 scroll-view（`axes = both`）：纵向 `line_step = row_px`；滚轮读取 `wheel_lines`，Shift+滚轮横向读取 `wheel_chars`（REQ-W-SCROLLVIEW-011 至 013）；两条滚动条同时显示时右下有角块；横向滚动条宽度范围只覆盖行区域；到端点后边界吸收规则同 scroll-view。表头不响应滚轮横向滚动的"独立偏移"：它跟随行区域的偏移（REQ-W-TABLE-008）。在表头上滚动滚轮：纵向分量无处理者时冒泡到外层，Shift+滚轮横向滚动行区域（表头登记 `wheel`，转交行区域的横向偏移）。

**REQ-W-TABLE-025**　**上下文菜单**：行区域的右键与键盘菜单键请求同 list（REQ-W-LIST-025、030），结果 `context_menu: ?TableContext{ row: ?usize, column: ?u16, pos, anchor, from_keyboard }`；鼠标触发时 `column` 为指针所在列的逻辑列号（空白处为 `null`）。表头右键（`header_menu = true` 时）报告 `header_context: ?HeaderContext{ column: ?u16, pos, anchor }`，`column` 为被点击的列（边界或表头底之外的空白为 `null`），表头右键不改变选择与排序；`header_menu = false` 时表头右键无效果。显示/隐藏列的菜单由应用弹出，并经 `w.setTableColumnHidden(ui, table_id, column, hidden)` 修改有效可见性（框架不绘制该菜单）。

## 7. 键盘行为

行级键位完全同 list.md 第 7 节（↑/↓、Home/End、PageUp/PageDown、Space、Ctrl+A、Enter、前缀搜索、Shift+F10/菜单键，及其与 Ctrl、Shift、Ctrl+Shift 的组合；Ctrl+PageUp/PageDown 与 Ctrl+Shift+PageUp/PageDown 同 list 不使用，冒泡给外层标签页），作用于数据行；另增：

| 键 | 行为 |
|---|---|
| ← / Shift+← | 行区域横向偏移 − 一个步长（`line` = `row_px`），仅当有横向可滚动量 |
| → / Shift+→ | 行区域横向偏移 + 一个步长 |
| Ctrl+← / Ctrl+→、含 Alt 的组合 | 不处理（不列入 `extra`，冒泡） |
| Esc | 仅在列宽调整/列拖动进行中处理（取消），否则不处理 |

**REQ-W-TABLE-026**　表格持有焦点时，←/→ 使行区域横向偏移 ∓ 一个步长（夹紧到 `[0, max_off_x]`，自动重复照常），**不**移动焦点行、不改变选择；无横向滚动条时不处理（继续冒泡）；Shift+←/→（键组匹配仅 Shift 的方向键，到达表格）等同无修饰的 ←/→；Ctrl+←/→ 不列入 `extra`、不处理（冒泡）；含 Alt 的 ←/→ 不处理。选择与焦点移动、滚入规则同 list（REQ-W-LIST-031 至 040），其中纵向焦点滚入按行下标直接计算，不依赖行节点。键盘无法直接排序或调整列宽（UIA 的 `Invoke` 可排序，见 REQ-W-TABLE-030；键盘排序入口列为 OPEN-W-TABLE-05）。

**REQ-W-TABLE-027**　表格经 `InteractOpts` 声明：`handles` 的键组含 `arrows`、`home_end`、`page`、`space`、`enter`（只匹配无修饰或仅 Shift 的按键，REQ-INPUT-028）；`extra` 与 list 一样**逐个列出**带 Ctrl 的组合（Ctrl+↑、Ctrl+↓、Ctrl+Shift+↑、Ctrl+Shift+↓、Ctrl+Home、Ctrl+End、Ctrl+Shift+Home、Ctrl+Shift+End、Ctrl+Space、Ctrl+Shift+Space，仅 `multi` 的 Ctrl+A，REQ-W-LIST-031），Ctrl+←/→ 与 Ctrl+PageUp/PageDown 不列入；`preempt.printable = true`；Esc 仅在列宽调整或列拖动进行中声明。前缀搜索取显示序第一个可见列的 `data.cell_text(row, column)`（空则关闭，REQ-W-LIST-039 的其余规则不变）。

## 8. 焦点

**REQ-W-TABLE-028**　表格是**单个 Tab 停靠**（行区域，同 list REQ-W-LIST-041），焦点节点是根节点；表头单元格、列边界**不是**焦点节点，鼠标点击表头单元格或边界**不**取得焦点也不移走当前焦点（点击聚焦只在行区域与空白处发生，REQ-INPUT-022）。焦点指示画在焦点行（同 list），不存在"焦点列"。窗口失活、禁用、焦点转移规则同 list。

## 9. 文本与输入法

表头标题与单元格文字均为单行，不接受文本输入；表格不是文本输入类节点，聚焦时输入法禁用。

**REQ-W-TABLE-029**　单元格与表头标题文字超出可用宽度时尾部省略（REQ-THEME-018）；可用宽度 = 单元格（列）有效宽度 − `2 × pad_item_x`（表头再减去排序标记所占宽度）。文字被截断（`text.isTruncated`）且 `tooltip_on_truncate = true` 时，指针悬停该单元格（`ui.hoverFor(id, .tooltip)`，延迟读取系统 `hover_time_ms`）显示完整文字的提示框，锚点矩形为该单元格矩形（表头为表头单元格矩形）；未截断不显示；滚动、列宽调整、列拖动进行中不显示。`h_align` 为 `right` 时省略号仍在尾部。

## 10. 动效

| 属性 | 触发 | 时长令牌 | 缓动 | 影响级别 |
|---|---|---|---|---|
| 表头单元格底（常态 ↔ 悬停） | 悬停变化 | `dur_fast` | `ease_out` | paint（`Visual.hover_t`） |
| 表头单元格底（→ 按下） | 按下 | `dur_instant` | — | paint（`Visual.press_t`） |
| 表头单元格底（按下 →） | 释放 | `dur_fast` | `ease_out` | paint |
| 行悬停底色 | 悬停变化 | `dur_fast` | `ease_out` | paint |
| 列宽、列顺序、排序标记、滚动位置 | 任何来源 | 无（即时到位） | — | 见第 14 节 |

表格没有自有动画槽；列宽与列顺序的变化不做过渡。

## 11. 无障碍

| 项 | 值 |
|---|---|
| UIA 控件类型 | 表格：DataGrid；表头条：Header；表头单元格：HeaderItem；行：DataItem；单元格：DataItem（每个已创建的单元格一个子元素） |
| 名称来源 | 表格：应用提供的无障碍名称；HeaderItem：列标题；行：显示序第一列的 `cell_text`；单元格：`data.cell_text(row, column)` |
| 支持的模式 | DataGrid：Grid、Table、Selection、Scroll；HeaderItem：Invoke（可排序列）；行：SelectionItem、ScrollItem、Invoke；单元格：GridItem、TableItem |
| 状态属性 | Grid：RowCount = `count`、ColumnCount = 显示列数；Table：RowOrColumnMajor = RowMajor、ColumnHeaders = 各 HeaderItem；GridItem：Row = 行下标、Column = 显示序号、RowSpan = ColumnSpan = 1；SortDirection（HeaderItem，经 Table 提供的排序属性：Ascending/Descending/Indeterminate）；行：IsSelected、IsEnabled |

**REQ-W-TABLE-030**　UIA 操作**必须**与用户操作等效、在下一帧生效：`HeaderItem.Invoke` ≡ 点击该表头排序（可排序列，报告 `sort_changed`）；`GridPattern.GetItem(row, column)` 只返回已创建（可见与缓冲）的行列单元格，其余按 OPEN-W-LIST-05 的虚拟化提供方式处理；`SelectionItem`、`ScrollItem`、`Invoke`（行）等价 list（REQ-W-LIST-048）；`Scroll` 作用于行区域的滚动视图（REQ-W-SCROLLVIEW-024）。

## 12. API 草案

```zig
// 草案：仅签名
pub const HAlign = enum { left, right, center };
pub const SortDir = enum { asc, desc };
pub const GridLines = enum { none, horizontal, vertical, both };

pub const TableColumn = struct {
    title: []const u8,                              // 借用至本帧结束
    width: layout.ColumnWidth = .{ .fixed = 120 },  // 07
    min: f32 = 0,                                   // lpx
    max: f32 = std.math.inf(f32),
    h_align: HAlign = .left,
    font: theme.FontToken = .body,                  // 数值列建议 .mono
    sortable: bool = false,
    resizable: bool = true,
    hidden: bool = false,                           // 初始可见性；之后由框架持有（setTableColumnHidden / 持久化）
};

pub const TableSort = struct { column: ?u16 = null, dir: SortDir = .asc };   // column = null：无排序

pub const TableData = struct {
    ctx: ?*anyopaque = null,
    key_of: ?*const fn (ctx: ?*anyopaque, index: usize) ItemKey = null,
    index_of: ?*const fn (ctx: ?*anyopaque, key: ItemKey) ?usize = null,
    cell_text: ?*const fn (ctx: ?*anyopaque, row: usize, column: u16) []const u8 = null,   // 返回值只需存活至下一次调用
    prefix_search: ?*const fn (ctx: ?*anyopaque, prefix: []const u8, start: usize) ?usize = null,
};

pub const TableOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    mode: SelectionMode = .multi,
    selection: ?*Selection = null,
    data: TableData = .{},
    row_height: ?f32 = null,
    alternate_rows: bool = false,
    grid: GridLines = .horizontal,
    empty_text: ?[]const u8 = null,
    scrollbar_v: layout.BarPolicy = .auto,
    scrollbar_h: layout.BarPolicy = .auto,
    sort: ?*TableSort = null,
    allow_unsorted: bool = false,
    reorder_columns: bool = true,
    header_menu: bool = false,
    persist: ?[]const u8 = null,
    tooltip_on_truncate: bool = true,
    layout: layout.ItemOptions = .{},
};

pub const table_column_kind: u32 = 0x54424C43;       // 列重排的拖放载荷 kind（框架保留，'TBLC'）

pub const TableCell = struct {
    column: u16,                                     // 逻辑列号（columns 的下标）
    display: u16,                                    // 显示序号
    width: f32,                                      // lpx，有效宽度
    h_align: HAlign,
    font: theme.FontToken,
    text_color: theme.ColorToken,                    // 随所在行的选中/禁用状态
};
pub const CellIter = struct { pub fn next(self: *CellIter) ?TableCell; };

pub const TableRow = struct {
    index: usize,
    key: ItemKey,
    selected: bool,
    focused: bool,
    hovered: bool,
    text_color: theme.ColorToken,
    pub fn cells(self: *const TableRow) CellIter;    // 只产出已创建列（REQ-W-TABLE-005）
};
pub const TableIter = struct {
    id: ui.WidgetId,                                 // 供 setTableColumnHidden 使用
    pub fn next(self: *TableIter) ?TableRow;
};
/// 修改某逻辑列的有效可见性（响应 header_context 时调用）；下一次构建生效并持久化。
pub fn setTableColumnHidden(ui: *Ui, table_id: ui.WidgetId, column: u16, hidden: bool) void;

pub const SortChange = struct { column: u16, dir: ?SortDir };          // dir = null：无排序
pub const ColumnResize = struct { column: u16, width: f32 };           // lpx
pub const TableContext = struct { row: ?usize, column: ?u16, pos: core.Vec2, anchor: core.Rect, from_keyboard: bool };
pub const HeaderContext = struct { column: ?u16, pos: core.Vec2, anchor: core.Rect };

pub const TableResult = struct {
    // 持续性状态
    hovered: bool,
    focused: bool,
    focus_index: ?usize,
    selection: *const Selection,
    selected_visible: usize,
    sort: TableSort,                                 // 当前排序状态
    resizing: ?u16,                                  // 正在调整宽度的逻辑列号
    // 激活类结果（触发同帧第二构建遍，REQ-FRAME-030）
    selection_changed: bool,
    activated: ?usize,
    context_menu: ?TableContext,
    header_context: ?HeaderContext,
    sort_changed: ?SortChange,
    column_resized: ?ColumnResize,
    columns_reordered: bool,
};

pub fn beginTable(ui: *Ui, src: std.builtin.SourceLocation, columns: []const TableColumn, count: usize, opts: TableOptions) TableIter;
pub fn endTable(ui: *Ui) TableResult;

pub const TableCellTextOptions = struct { icon: ?theme.Icon = null };
/// 单元格内的单行文字，按列 h_align、font 与省略规则；text 借用至本帧结束。
pub fn tableCellText(ui: *Ui, src: std.builtin.SourceLocation, cell: TableCell, text: []const u8, opts: TableCellTextOptions) void;
```

`sort_changed`、`column_resized`、`columns_reordered`、`selection_changed`、`activated`、`context_menu`、`header_context` 是激活类结果，在其为真/非空的帧触发同帧第二构建遍。`columns` 切片借用至 `endTable` 返回，列的个数与顺序在两次构建之间改变时按 REQ-W-TABLE-035 处理；`opts.sort`、`opts.selection` 由应用持有，须存活至 `endTable` 返回。

## 13. 保留状态

| 字段 | 类型 | 保留级别 | 说明 |
|---|---|---|---|
| `TableState`（整体） | 保留节点（`ui.retained(TableState, id, .sticky)`） | 保留节点 | 滚动、焦点、锚点、搜索缓冲、列宽覆盖、显示序、排序 |
| `offset_px` | `[2]i64` | 保留节点 | 行区域的横向（x）、纵向（y）偏移（ppx，i64，REQ-LAYOUT-054），其地址作为 `ScrollViewOptions.offset_px` 传给行区域的 scroll-view；以下正文的 `off_x`、`off_y` 即其分量 |
| `focus`、`anchor`、`search`、`press`、`own_selection` | 同 list | 保留节点 | 见 list.md 第 13 节 |
| `user_widths` | `[]f32`（lpx，长度 = 列数；0 表示该列无用户宽度） | 保留节点 | 用户调整过的列宽 |
| `order` | `[]u16`（显示序 → 逻辑列号的排列） | 保留节点 | 列显示顺序；初始为恒等排列 |
| `hidden` | `[]bool`（长度 = 列数） | 保留节点 | 列的有效可见性；初始取 `TableColumn.hidden` |
| `sort` | `TableSort` | 保留节点 | 应用未提供 `sort` 指针时使用 |
| `hdr` 及其参数（`col`、`start_px`、`press_x`、`ins`） | 状态机变量 | transient | 列宽调整与列拖动的进行状态 |
| 表头单元格的悬停/按下过渡 | 框架内建 | transient | 无需槽 |

**REQ-W-TABLE-031**　**状态所有权与持久化**：列宽覆盖、显示序、列可见性（`hidden`）、排序保存在保留节点（sticky，REQ-FRAME-010）；应用可经 `opts.sort` 自持排序。`persist` 与窗口 `persist_name` 均非空时（11 REQ-APP-037，`UiStateStore.table`/`setTable`），控件首次出现读取一次 `TableState`。设置存储中的记录格式（11 REQ-APP-037）为 `{ widths, order, hidden, sort: { col, asc } | null }`，`UiStateStore.table` 把它读成 `TableState{ widths, order, hidden, sort_col, sort_asc }`（`sort_col = null` 对应记录的 `sort: null`）：`widths[i]`（lpx）为逻辑列 `i` 的用户宽度，**0 表示该列没有用户宽度**（沿用声明的 `width`）；`order` 为显示序到逻辑列号的排列；`hidden[i]` 为逻辑列 `i` 是否隐藏（读入时覆盖 `TableColumn.hidden` 的初始值；无记录时取 `TableColumn.hidden`）；`sort: null`（`sort_col = null`）表示无排序。列可见性只能经 `w.setTableColumnHidden`（及 UIA 无此入口）改变，改变时写入一次。写入时机：列宽调整释放/双击自适应（`column_resized`）、列重排释放（`columns_reordered`）、点击排序（`sort_changed`）各写一次，不在拖动的每次移动时写入；Esc 取消不写入；经设置存储去抖落盘。

**REQ-W-TABLE-032**　**持久化读入的校验**：`widths.len`、`order.len` 或 `hidden.len` 不等于声明的列数（含隐藏列）、`order` 不是 `0..n−1` 的排列、`sort_col` 不小于列数或指向不可排序的列、任一宽度为负或非有限数时，**整条记录被忽略**，取声明默认值（REQ-APP-037 的"列数与表格不符则忽略"）。用户宽度读入后仍受 `[最小有效宽度, max]` 夹紧。应用持有 `sort` 时仍可设置 `persist`：首次出现的读入排序值写入应用的 `sort`。列的个数在运行中改变时按 REQ-W-TABLE-035 处理。未被引用的旧记录保留不删。

保留节点内存取自状态存储池，`deinit` 释放 `user_widths`、`order` 与 `own_selection`。LRU 回收（REQ-FRAME-010）后偏移、焦点、锚点重置，列宽/顺序/排序若已持久化则从设置恢复，否则回到声明默认值。

## 14. 失效规则

**REQ-W-TABLE-033**　绘制键与布局输入键**必须**如下：行节点绘制键 = (是否选中、`active`、焦点指示显示、奇数行底色、`enabled`、`grid`、各已创建单元格内容的绘制键、已创建列的有效宽度序列)；表头条绘制键 = (各已创建表头单元格的标题、排序标记状态、`enabled`、有效宽度序列、横向偏移、表头底块是否出现)；根绘制键 = (`enabled`、焦点显示、`count = 0` 时的 `empty_text`)。悬停经 `Visual.hover_t`。行节点与单元格节点的布局输入含有效宽度与前导占位宽度。

| 变化 | 置脏级别 | 损伤范围 |
|---|---|---|
| 悬停进入/离开行或表头单元格 | `paint`（构建遍数 0） | 该行矩形 / 该表头单元格矩形 |
| 选择/焦点变化 | `build`（REQ-FRAME-037） | 选中状态或焦点指示变化的各行矩形 |
| 纵向滚动 | `build`；按 REQ-W-SCROLLVIEW-026；被创建行节点 ≤ 可见行 + 缓冲 | 行区域视口矩形与滚动条矩形 |
| 横向滚动 | `build`；被创建列的集合变化时新增列的单元格节点；表头同帧同偏移 | 行区域视口、表头条、滚动条矩形 |
| 列宽调整中的移动 | `build`（被捕获期间的移动）；布局：表头与已创建行重新指派 | 表头条与行区域视口（受影响列右侧整个区域） |
| 点击排序 | `build`；`sort_changed` 触发第二遍；应用提供排序后的数据 | 表头条（标记变化）与行区域（数据差分） |
| 列重排拖动中的移动 | `build`（被捕获期间的移动） | 旧新放置指示线矩形（覆盖层） |
| 列重排提交 | `build` | 表头条与行区域视口 |
| 视口尺寸变化 | `layout`；布局反馈同帧第二构建遍补齐行与列 | 整个表格 |
| 数据变化（模型通知） | `build` | 由差分决定 |

**REQ-W-TABLE-034**　**可计量断言**：
(1) 行节点数 ≤ 可见行数 + 2 × 5（`list.virtual_nodes`，同 REQ-W-LIST-051）；每行单元格节点数 = 已创建列数 ≤ 可见列数 + 2；计量 `list.virtual_cells`（12 已登记）每次 `endTable` 后设为已创建单元格节点总数 = 已创建行数 × 已创建列数，且与 `count`、总列数无关。总节点数 `frame.nodes` ≤ `已创建行数 × (1 + 已创建列数) + 2 × 已创建列数（表头单元格与列边界）+ 常数 16`（每个单元格声明一个节点时），且与 `count` 无关、与总列数无关（总列数 20 与 200 在同一视口下相等）。
(2) 纵向滚动一行：被构建的行节点数 ≤ 可见行数 + 缓冲行数；仅新进入窗口的行及其单元格被测量。
(3) 横向滚动一列的宽度：被创建的单元格节点集合只变化进入/离开已创建列的列；行节点数不变。
(4) S-TABLE-1M（100 万行 × 20 列，视口固定，每帧 `wheel -1`）：`time.frame_cpu` 的 P99 ≤ 3.0 ms（REQ-PERF-022）；规模从 1 万行增至 100 万行时 `time.build` 的 P99 增长 ≤ 1.5 倍（REQ-PERF-036）。
(5) 仅悬停变化的帧构建遍数 0，损伤 ≤ 该行（或表头单元格）矩形面积。
(6) 无变化的重复 `invalidate(.build)` 损伤为空，`frame.presents` 不变。
(7) `layout.solveColumns` 每次构建恰调用一次，成本 O(列数)。

## 15. 边界与错误情况

**REQ-W-TABLE-035**　**列的个数或顺序在构建之间改变**（应用换了一组列）：保留的 `user_widths`、`order` 长度与新列数不符时，整体丢弃并回到声明默认值（不持久化写入，直到下一次用户操作）；`sort.column` 不小于新列数或指向不可排序列时清为无排序；横向偏移夹紧。列数增加/减少而用户无任何操作的构建遍中**不**报告任何结果。

**REQ-W-TABLE-036**　**禁用**（`enabled = false`）：框用禁用配方；表头条为禁用外观（`surface_raised_disabled`、`text_disabled`），无悬停、按下与列边界光标；表头点击、列宽调整、列拖动、行选择、键盘均不响应（命中仍吞掉事件，REQ-INPUT-009）；滚动条按 scroll-view 禁用外观；既有选择、排序、列宽、顺序、偏移保持。调整/拖动进行中被禁用：恢复到按下前的值，不报告结果。

| 情况 | 规定 |
|---|---|
| 内容总宽 < 视口宽 | 无横向滚动条（`auto`）；行与表头底填满视口宽；`grow` 列按 07 分配 |
| 单列且 `grow` | 该列占满视口宽 |
| `count = 0` | 空状态，表头仍可操作 |
| 视口宽/高为 0 | 无已创建行与列；无结果 |
| 调整宽度使总宽超出视口 | 出现横向滚动条；调整中偏移不自动改变 |
| 调整宽度时窗口缩放 | 以新的视口继续；`start_px` 不变 |
| 排序列被隐藏 | 排序状态保留，不画标记；重新显示后标记恢复 |
| 按下表头期间表格消失 | 捕获释放（REQ-INPUT-024），无排序、无宽度变化 |
| 列拖动指针移出表格 | 无放置位置，释放不重排 |
| 单元格内容超长 | 同 REQ-W-TABLE-029；超过 05 的 `max_layout_bytes` 时截取并省略（REQ-TEXT-005） |
| `cell_text` 为空且双击自适应 | 只按表头自然宽 |
| 窗口非活动 | 悬停照常，选中底非活动色；点击先激活窗口，该次点击照常作用 |
| DPI 变化 | 用户宽度按 lpx 重新换算取整；列求解重做 |

## 16. 验收标准

下列夹具 `G1`：`scale` = 1.0，`row_h` = 22，`header_h` = 24，表格宽 812 lpx（含 12 lpx 的纵向滚动条，行区域视口宽 800）、行区域视口高 220 lpx（10 行），`mode = multi`；列（逻辑序）：0 "名称" `grow(1)`、`min` 60、可排序；1 "大小" `fixed(80)`、`h_align = right`、`font = mono`、可排序；2 "类型" `fixed(100)`、可排序；3 "修改日期" `fixed(140)`。因此初始有效宽度为 480/80/100/140（总 800）。文字测试夹具 `fixed` 后端：每字符宽 7 lpx。数据 `count = 10`，行键缺省取下标。

**AC-W-TABLE-001**　`[金图]` 覆盖：REQ-W-TABLE-007、REQ-W-TABLE-010、REQ-W-TABLE-013、REQ-W-TABLE-016、REQ-W-TABLE-017、REQ-W-TABLE-036。渲染 `G1`（12 行数据；行区域 220 lpx = 10 行，视口显示 10 行，另 2 行需滚动）：表头状态 {常态, 悬停于"名称", 按下于"类型", "名称"升序标记, "大小"降序标记, 禁用}；行状态 {悬停, 选中且 active, 选中失焦, 焦点行指示, 交替行}；`grid` ∈ {none, horizontal, vertical, both}；"大小"列右对齐等宽字体；缩放 1.0/1.5/2.0；浅/深/高对比度。预期：与基准图一致；表头为凸起表面，高 `header_h`；列边界发丝线 `border_subtle` 对齐表头与行内网格线；悬停与按下仅作用于该表头单元格且按下时标题与标记下移 1 ppx；排序标记位于单元格右端；纵向滚动条不覆盖表头，表头右端有表头底块；选中底横跨整个行宽、网格线画在选中底之上；禁用列表头为 `surface_raised_disabled` 且无悬停；省略号结尾无半个字形。

**AC-W-TABLE-002**　`[单元]` 覆盖：REQ-W-TABLE-002、REQ-W-TABLE-003。夹具 `G1`。预期：有效宽度 480/80/100/140（总 800）；把"大小"调整为用户宽度 120 → 有效宽度 440/120/100/140（"名称" grow 吸收）；表格视口缩小到 600 → "名称" `grow` 得 600 − 360 = 240，但 `min` 60 不起作用；缩小到 300 → "名称"得 `max(300 − 360, 0)` 夹到最小有效宽度 `max(60, 2 × 8 + 16 = 32)` = 60，总宽 420 超出视口，出现横向滚动条；列 3 声明 `auto_header` 且标题 "修改日期" 4 字符（28 lpx）、可排序：自然宽 = 28 + 2 × 8 + 4 + 16 = 64；`min` 为 0 时最小有效宽度 = 32；`hidden = true` 的列 2 不参与求解（有效宽度序列只含 3 项）；`solveColumns` 在一次构建中调用 1 次。`scale` = 1.5：令牌换算取整（`pad_item_x` 12，`icon_sm` 24，最小有效宽度 48 ppx）。

**AC-W-TABLE-003**　`[单元]` 覆盖：REQ-W-TABLE-004、REQ-W-TABLE-005、REQ-W-TABLE-006、REQ-W-TABLE-009。夹具：20 列各 `fixed(100)`（总宽 2000，有效宽度 100），行区域视口 800×660 lpx（`row_h` 22，30 行），`count` = 100000，纵向滚动条使视口宽 800（表格总宽 812）。预期：横向偏移 0 → 可见列 0–7（区间 [0,800)），已创建列 0–8（向右扩展 1 列，左侧夹紧），前导占位宽 0（省略）；偏移 450 → 可见列 4–12（[400,500) 至 [1200,1300)）共 9 列，已创建列 3–13（11 列），前导占位宽 300；最大偏移 1200（内容 2000 − 视口 800）→ 可见列 12–19，已创建列 11–19（9 列），前导占位宽 1100。每行单元格节点数 = 已创建列数；表头单元格数同；偏移 0 与纵向偏移 0 时行节点 [0, 34] 共 35 个，单元格节点共 35 × 9 = 315。行节点宽 = max(2000, 800) = 2000。内容总宽 600（视口 800）时行节点宽 800。首次出现（视口未知）→ 32 行 × 前 16 列，布局反馈后第二遍改为实际范围。

**AC-W-TABLE-004**　`[回放]` 覆盖：REQ-W-TABLE-013、REQ-W-TABLE-014、REQ-W-TABLE-015、REQ-W-TABLE-016。夹具 `G1`，排序状态初始为无。① 点击"名称"（x = 100，y = 12）→ 释放时 `sort_changed` = {列 0, asc}，标记 `sort_asc`；按下时无 `sort_changed`。② 再点击"名称" → {0, desc}。③ `allow_unsorted = false`：再点击 → {0, asc}；`allow_unsorted = true`：第三次点击 → {0, null}，标记消失。④ 点击"类型" → {2, asc}，"名称"的标记消失。⑤ 在 `sortable = false` 的列点击 → 无 `sort_changed`，排序不变。⑥ 在"名称"上按下后移动 10 lpx（越过 `drag_size` 4 ppx）→ 不排序（拖动列开始）；`reorder_columns = false` 时同样不排序也不重排。⑦ 点击列边界命中带（"名称"右端 [475, 480)）→ 不排序。⑧ 右键、中键点击表头 → 无排序、无 `sort_changed`。⑨ 排序在**释放**时生效：按住"类型"期间 `sort` 仍为之前的值，单元格为按下外观；指针移出单元格后释放 → 无 `sort_changed`。⑩ 应用持有 `opts.sort`：点击后指针所指值被写回为 {0, asc}；应用把它改为 {1, desc} → 下一次构建"大小"显示 `sort_desc`。⑪ 点击后框架不重排数据（应用在 `sort_changed` 的第二遍提供排序后的行键序，其行节点随之变化）。

**AC-W-TABLE-005**　`[回放]` 覆盖：REQ-W-TABLE-017、REQ-W-TABLE-018、REQ-W-TABLE-019。夹具 `G1`。步骤与预期：指针移到"大小"右端边界命中带（[555, 560)）→ 指针形状 `size_we`，列边界可见线变为 `border_strong`；移到"名称"区内 → 箭头。按下于 x = 557（`press_x` = 557，`start_px` = 80）并移到 x = 597 → "大小"宽度 120，有效宽度 440/120/100/140；下一帧表头与全部行已按新宽度布局（无虚影）；移到 x = 300 → 宽度夹紧到最小有效宽度 32；移到 x = 5000 → 宽度 = 80 + (5000 − 557) = 4523（`max` 无上限）→ 内容总宽超出视口，出现横向滚动条；释放（宽度 120 的情形）→ `column_resized` = {1, 120}，下一帧假。拖动全程指针形状 `size_we`（含指针移出命中带后）。Esc：拖动到 x = 640 后按 Esc → 宽度恢复 80，捕获者为空，无 `column_resized`，所在对话框的取消按钮未被触发；Esc 之后继续移动指针 → 宽度不变。`resizable = false` 的列：命中带处指针为箭头，按下无反应。拖动中令窗口失活 → 宽度恢复。非调整时按 Esc → 不被表格消费。

**AC-W-TABLE-006**　`[回放]` 覆盖：REQ-W-TABLE-020。夹具 `G1`，"类型"列（逻辑列 2）：当前可见行 0–9 的 `cell_text` 中最长为 "应用程序扩展"（6 字符 = 42 lpx）；表头标题 "类型"（2 字符 = 14 lpx，`font_body_strong` 同宽）。双击"类型"右端边界 → 宽度 = max(表头自然宽 14 + 2 × 8 + 4 + 16 = 50, 42 + 16 = 58) = 58，夹到 [32, ∞) → 58；`column_resized` = {2, 58}；其他列宽度不变（"名称"吸收变化）。缓冲行（视口外）中含更长文字时不计入；滚动使更长文字的行进入视口后再次双击 → 宽度增大。`cell_text` 为空 → 宽度 = 50。结果受 `max` 约束：`max` = 55 → 55。双击后点击排序不受影响。不可调整的列双击 → 无变化。

**AC-W-TABLE-007**　`[回放]` 覆盖：REQ-W-TABLE-021、REQ-W-TABLE-022。夹具 `G1`，显示序 [0,1,2,3]，宽度 480/80/100/140（列中点 240、520、610、730（内容 x））。步骤与预期：拖动"类型"（列 2，按下于 x = 600）越过阈值 → `beginDrag` 载荷 `kind = table_column_kind`、`data = 2`；指针移到 x = 500：中点不大于 500 的列有列 0（240）→ `ins` = 1，覆盖层竖线位于列 1 的左边缘 x = 480，高 = 24 + 220；释放 → 显示序 [0,2,1,3]，`columns_reordered` 真，逻辑列号与排序状态不变；另一次（显示序 [0,1,2,3]）把列 2 移到 x = 20 → `ins` = 0，释放 → [2,0,1,3]；放置在 x = 640（`ins` = 3，在原位置 2 之后紧邻：`ins ∈ {p, p+1}` = {2, 3}）→ 视为无操作，不报告；放置在表头之外或 Esc → 显示序不变，无 `columns_reordered`，指示线下一帧消失；`reorder_columns = false` → 无拖动开始。拖动期间指针靠近表头左右边缘 → 行区域横向自动滚动（有横向滚动条时）。重排后表头与行内单元格的列顺序一致，网格线对齐。

**AC-W-TABLE-008**　`[回放]` 覆盖：REQ-W-TABLE-023、REQ-W-TABLE-010。夹具 `G1`（行 i 占 y ∈ [24 + 22i, 24 + 22i + 22) 于表格坐标）。行选择与 list 的 AC-W-LIST-003 同一组步骤逐项适用，下标相同：单击行 3（点击行内任何列，如 x = 100、x = 600、x = 750）→ `Sel` {3}，A 3，F 3；Shift+单击行 7 → {3,4,5,6,7}，A 3，F 7；Ctrl+单击行 5 → {3,4,6,7}，A 5，F 5；Ctrl+单击行 9 → {3,4,6,7,9}，A 9，F 9；Ctrl+Shift+单击行 1 → {1..9}，A 9，F 1；Shift+单击行 6 → {6,7,8,9}，A 9，F 6。在已选中的多行之一上按下不立即改变选择，释放后折叠（同 AC-W-LIST-004）。右键行 8 → {8}，`context_menu` = {row 8, column = 指针所在列}。点击表头单元格 → `Sel` 不变。双击行 4 → `activated` = 4。点击空白处（`count` = 5，点击 y = 24 + 150）→ `multi` 清空选择。单元格内放一个按钮：点击按钮 → 按钮 `clicked`，行选择不变。选中底横跨整行宽（含超出视口宽的部分）。

**AC-W-TABLE-009**　`[回放]` 覆盖：REQ-W-TABLE-026、REQ-W-TABLE-027、REQ-W-TABLE-028。夹具 `G1`（总宽 2000 的 20 列变体用于横向）。① Tab 到表格 → F 0（描边可见）；表头单元格与列边界不在 Tab 序中；点击表头单元格 → 焦点不变（若焦点在文本框则仍在文本框）。② ↓、Shift+↓、Home、End、PageDown、Space、Ctrl+A、Enter 与 list 的 AC-W-LIST-008 至 AC-W-LIST-010 对应步骤一致（行下标相同）。③ → → 横向偏移 + 22；← → − 22；到 0 后 ← 无效果；`max_off_x` 处 → 无效果；焦点行与选择在这些按键后不变；无横向滚动条时 ←/→ 冒泡。④ Shift+→ 等同 →（横向偏移 +22），Shift+← 等同 ←；Ctrl+←、Ctrl+→、Alt+→ 不处理（偏移不变，键冒泡）；Ctrl+PageDown 不处理（冒泡）。⑤ 前缀搜索：`cell_text(row, 显示序第一列)` = "Apple" 等，同 AC-W-LIST-011 的 ①–④；`cell_text` 为空时字符不被消费。⑥ 调整列宽进行中 Esc 取消（AC-W-TABLE-005）；非进行中 Esc 不消费。⑦ 命令快捷键绑定 → 时命令优先。

**AC-W-TABLE-010**　`[回放]` 覆盖：REQ-W-TABLE-001、REQ-W-TABLE-008、REQ-W-TABLE-024。夹具：20 列各 100 lpx、`count` = 100，纵横滚动条均显示。步骤与预期：纵向滚动到偏移 440 → 表头条位置不变（y = 0），行内容上移，表头仍可见；纵向滚动条矩形只覆盖行区域（高 = 视口高）、不覆盖表头；横向滚动一格滚轮（Shift+`wheel -1`，`wheel_chars = lines(3)`，`line` = 22 → 横向偏移 +66 lpx）→ 行区域横向偏移 66，表头列边界与行内网格线仍逐像素对齐（同一帧、同一偏移，不滞后一帧）；拖动横向滑块 → 同帧同步；纵向滚动条显示时表头右端有 `scrollbar_w` 宽的表头底块，表头条总宽 = 行区域含滚动条的总宽；滚动条隐藏（`never`）时无底块。在表头上滚动滚轮：纵向分量在无外层滚动视图时被丢弃，Shift+滚轮横向滚动行区域。滚轮到端点后冒泡按 scroll-view 的边界吸收规则。

**AC-W-TABLE-011**　`[单元]` 覆盖：REQ-W-TABLE-031、REQ-W-TABLE-032。窗口 `persist_name` = "main"，表格 `persist` = "files"，4 列。步骤与预期：首次运行无记录 → 声明默认；调整"大小"宽度为 120 释放 → `ui.tables["main/files"]` = `{widths: [0,120,0,0], order: [0,1,2,3], hidden: [false,false,false,false], sort: null}`（写入 1 次，拖动中无写入）；重排使 order = [0,2,1,3] → 写入；点击"名称"排序 → `sort: {col: 0, asc: true}`；`allow_unsorted = true` 时第三次点击 → `sort: null`；经 `w.setTableColumnHidden` 隐藏"类型" → `hidden: [false,false,true,false]`；重启 → 首次出现读入并应用（"大小"用户宽度 120，显示序 [0,2,1,3]，"名称"升序标记，"类型"隐藏）；记录 `widths` 长度 3（列数不符）、`hidden` 长度 3、`order` = [0,0,1,2]（非排列）、`sort.col` = 7、`sort.col` 指向不可排序列、宽度含负数 → 整条记录忽略，取默认；Esc 取消调整不写入；窗口无 `persist_name` 或无 `persist` → 无条目；设置文件中无 `WidgetId` 数值；应用持有 `sort` 且设置 `persist`：读入的排序写入应用的 `sort`；未被引用的旧记录保留。LRU 回收后（未持久化）列宽/顺序/排序回到默认，（已持久化）从设置恢复。

**AC-W-TABLE-012**　`[回放]` 覆盖：REQ-W-TABLE-025。夹具 `G1`，`header_menu = true`。右键表头单元格"类型"（x = 600，y = 12）→ `header_context` = {column 2}，选择与排序不变；右键表头底空白处 → `column = null`；`header_menu = false` → 无结果。右键行 8 的"大小"列单元格 → `Sel` 变为 {8}（未选中时），`context_menu` = {row 8, column 1, from_keyboard 假}；右键空白处 → `{row null}`；键盘：F = 4，Shift+F10 → `context_menu` = {row 4, column null, from_keyboard 真, anchor = 行 4 的矩形}。应用据 `header_context` 弹出菜单并调用 `w.setTableColumnHidden(ui, table_id, 2, true)` 把"类型"列隐藏 → 下一次构建表头与行不再含该列，有效宽度重算为 3 项（"名称" grow 吸收，总宽 800），显示序与持久化记录仍含 4 项，且记录的 `hidden` = [false,false,true,false]；重启后首次出现读入并隐藏该列（覆盖 `TableColumn.hidden` 的声明值）；`hidden.len` 与列数不符 → 整条记录忽略。

**AC-W-TABLE-013**　`[回放]` 覆盖：REQ-W-TABLE-012、REQ-W-TABLE-035、REQ-W-TABLE-036。`count` = 0：表头与 `empty_text` 显示；点击"名称"仍报告 `sort_changed`；调整列宽仍可用；Tab 可聚焦，方向键、Enter 无效果。列数为 0：只显示框与空表头条。全部列 `hidden` → 同列数为 0。应用把列数由 4 改为 3 且保留了 4 项的 `user_widths`/`order` → 整体丢弃回默认，`sort.column` = 3 被清为无排序，且该构建遍不报告任何结果。禁用：`enabled = false` 时表头点击、边界拖动（指针为箭头）、列拖动、行点击、键盘均无反应；表头为禁用外观；进行中的调整在禁用瞬间恢复为按下前宽度且无 `column_resized`；禁用前已有的选择、排序、列宽保持。

**AC-W-TABLE-014**　`[计量]` 覆盖：REQ-W-TABLE-004、REQ-W-TABLE-005、REQ-W-TABLE-034。前置：S-TABLE-1M：`count` = 1000000，20 列各 `fixed(100)`，视口 800 × 660 lpx（30 行），`row_h` 22；每个单元格一个节点（`tableCellText`）。步骤与预期：纵向偏移 22000（行 1000 对齐）、横向偏移 0 → `list.virtual_nodes` = 40（行 995–1034），已创建列 0–8（9 列）→ `list.virtual_cells` = 360（= 40 × 9），`frame.nodes` ≤ 40 × (1 + 9) + 2 × 9 + 16 = 434；横向偏移 450 → 已创建列 3–13（11 列），`frame.nodes` ≤ 40 × 12 + 22 + 16 = 518；`count` 分别为 1 万、10 万、100 万 → `frame.nodes` 三次读数相等，`list.virtual_cells` 亦相等；纵向偏移取大值（100 万行 × 22 ppx、视口 660，`offset_px.y` = 21 999 340 与 16 777 217）时行位置逐像素精确（REQ-W-LIST-053，算例同 AC-W-LIST-023）；总列数 20 与 200（同视口）→ `frame.nodes` 相等；纵向滚动一行（偏移 +22）→ 行节点数不变、`layout.measured_nodes` 只含新进入的行及其单元格；横向滚动 100 lpx（一列宽）→ 单元格节点集合只变化一列。回放每帧 `wheel -1`（1010 帧）→ `time.frame_cpu` P99 ≤ 3.0 ms；1 万与 100 万行 `time.build` P99 之比 ≤ 1.5；`layout.solveColumns` 每构建遍 1 次。

**AC-W-TABLE-015**　`[计量]` 覆盖：REQ-W-TABLE-033。夹具 `G1` 稳定后。步骤与预期：指针移入/移出行 X → 构建遍数 0，损伤 ≤ 该行矩形面积；移入/移出表头"类型"（可排序）→ 构建遍数 0，损伤 ≤ 该表头单元格矩形面积；点击选中行 3 → 行 7（Shift 区间 {3} → {3..7}）→ 损伤为变化的各行；以相同参数 `invalidate(.build)` → 损伤为空，`frame.presents` 不变；点击排序 → 一帧 `build` + 第二遍（`sort_changed`），表头条标记变化；调整列宽拖动一步 → 一帧 `build`，损伤为表头条与行区域视口，Splitter/表格之外的节点全部复用（`frame.nodes_measure_reused` 的增量 ≥ 外部节点数）；横向滚动 → 表头条与行区域损伤，行节点数不变；列重排拖动中移动 → 损伤为旧新指示线矩形（覆盖层）。

**AC-W-TABLE-016**　`[单元]` 覆盖：REQ-W-TABLE-030、REQ-W-TABLE-011。经假 UIA 入口：表格 ControlType DataGrid，Grid：RowCount 10、ColumnCount 4；Table：RowOrColumnMajor = RowMajor，ColumnHeaders 为 4 个 HeaderItem，Name 为列标题；HeaderItem 的 SortDirection 随排序状态为 Ascending/Descending/Indeterminate；`HeaderItem.Invoke` 于"名称" → 下一帧 `sort_changed` {0, asc}，于不可排序列 → 无变化；`GetItem(3, 1)` → 行 3 的"大小"单元格，Name = `cell_text(3, 1)`，GridItem：Row 3、Column 1；视口外的行/列返回空或按虚拟化方案提供；行 DataItem 支持 SelectionItem（`Select` ≡ 单击）、ScrollItem、Invoke（≡ 激活）；`Selection.CanSelectMultiple` 与 `mode` 一致。

**AC-W-TABLE-017**　`[回放]` 覆盖：REQ-W-TABLE-029。夹具 `G1`，行 2 的"名称"单元格文字为 "非常长的文件名称示例.txt"（超出 480 lpx 之外的窄列场景：把"名称"调整到 80 lpx）。悬停该单元格并推进假时钟超过系统悬停时间 → 出现提示框，文字为完整文本，锚点矩形为该单元格矩形；未截断单元格悬停 → 无提示框；表头标题被截断（把"修改日期"调到 40 lpx）→ 悬停显示完整标题；`tooltip_on_truncate = false` → 无；调整列宽/滚动进行中 → 无；右对齐列被截断 → 省略号在尾部。

**AC-W-TABLE-018**　`[人工]` 覆盖：REQ-W-TABLE-008、REQ-W-TABLE-018、REQ-W-TABLE-021、REQ-W-TABLE-034。在真实 Windows 上的示例应用"表格"页（100 万行 × 20 列合成数据、一个 1000 行的文件列表）：用鼠标拖动列边界（实时重排、无虚影、拖出窗口再回仍连续）、双击边界自适应、点击表头排序（应用侧排序 1000 行数据）、拖动表头重排列并拖到边缘观察自动滚动；用滚轮、Shift+滚轮、滚动条拖动在 100 万行 × 20 列上滚动，确认流畅、无空白行/列闪现、表头始终与行对齐；切换 150%/200% 缩放、深浅色、高对比度；键盘 ←/→/PageDown 观察。观察要点：表头冻结且不抖动、列边界发丝线对齐整数像素、拖动 100 万行滑块时 CPU 占用与帧率、排序标记与光标形状切换及时。

## 17. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-W-TABLE-01 | 首列冻结（横向滚动时首列不动） | 本版不做：需要把行拆成冻结部分与滚动部分两个裁剪区，且表头同样拆分；07 的 OPEN-LAYOUT-01 也倾向由重型表格自行处理。优先级低于单元格导航 |
| OPEN-W-TABLE-02 | 单元格导航（焦点列、单元格级选择、Shift+方向键框选） | 本版不做，选择以整行为主；若引入，需要焦点节点区分"焦点单元格"、←/→ 改为移动焦点列（而非横向滚动），并新增 `cell_selection` 模式 |
| OPEN-W-TABLE-03 | `Shift`+点击表头追加次级排序列 | 本版不做；`TableSort` 只有单列。若引入，改为 `[]SortKey` 并在表头标记旁显示序号 |
| OPEN-W-TABLE-04 | （已关闭，见 REQ-W-TABLE-031：11 的 `TableState` 已含 `hidden`） | — |
| OPEN-W-TABLE-05 | 键盘无法排序、调整列宽、重排列 | 倾向后续增加"表头焦点模式"（如 Ctrl+Shift+方向键）；M6 无障碍评审时定；目前 UIA 的 `Invoke` 可排序 |
| OPEN-W-TABLE-06 | （已关闭，见 REQ-W-TABLE-034：12 已登记 `list.virtual_cells`） | — |
| OPEN-W-TABLE-07 | （已关闭，见 REQ-W-LIST-003、053：07 REQ-LAYOUT-054） | — |
| OPEN-W-TABLE-08 | 可变行高、行分组、单元格合并、就地编辑 | 不做 |
| OPEN-W-TABLE-09 | 表头的 `font_body_strong` 与数据列 `h_align` 为 `right` 时标题对齐方式（标题随列右对齐是否符合预期） | 倾向标题随列对齐，利于数值列阅读；评审时确认 |
| OPEN-W-TABLE-10 | 表头单元格的悬停变体在"仅点击排序/重排"列上才显示，其余列无悬停反馈，是否一致 | 倾向保持：无交互的表头单元格不给悬停反馈，避免暗示可点击 |
