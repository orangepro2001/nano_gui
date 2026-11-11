# 09 主题：Instrument

## 1. 范围

定义默认主题 Instrument 的设计原则、全部令牌（颜色、度量、字体、动效）、状态表现、绘制基元的逐层配方、图标规范、高对比度与系统设置的适配。依据 ADR 0009。

控件规范只引用本文的令牌名与绘制基元名，不出现颜色或尺寸字面量。

## 2. 术语

| 术语 | 定义 |
|---|---|
| 发丝线 (hairline) | 宽度随缩放取整数物理像素的最细线，见 REQ-THEME-012。 |
| 凸起 (raised) | 看起来略高于所在表面的元素：按钮、表头、滑块手柄、滚动条滑块。 |
| 内凹 (sunken) | 看起来略低于所在表面的元素：输入框、列表底、进度槽、滑轨。 |
| 斜面 (bevel) | 凸起元素顶部 1 发丝线的内高光与底部略深的边。 |
| 强调色 (accent) | 表示选中、焦点、主要动作、进度的唯一彩色。 |
| 焦点可见 (focus-visible) | 焦点由键盘导航获得，或控件是文本输入类。只有此时才绘制焦点环。 |

## 3. 规范条款

### 3.1 设计原则

**REQ-THEME-001**　**光源恒定在正上方。** 凸起元素上亮下暗，内凹元素顶部有内阴影。任何元素不得出现与此矛盾的明暗。

**REQ-THEME-002**　**边界先于填充。** 每个可交互元素**必须**有发丝线边框，使其在去掉全部填充色后仍可辨认形状与范围。

**REQ-THEME-003**　**体积感以最小剂量表达。** 凸起渐变的首尾亮度差限制在 2–4%（以 CIE L\* 计，差值 ≤ 4），斜面高光与内阴影各只占 1 发丝线。

**REQ-THEME-004**　**中性为主，强调色稀缺。** 任一时刻一个窗口内使用强调色填充的面积**不应**超过客户区的 10%（大面积选区除外）。强调色只用于：选中项、焦点环、默认按钮、勾选/开启态、进度、链接。

**REQ-THEME-005**　**状态靠明度与边框区分，不靠透明度。** 禁用态**不得**通过给整个控件加透明度实现，而是换用专门的禁用令牌并去掉体积感。

**REQ-THEME-006**　**禁止项。** 以下做法**不得**出现在内建控件与示例中，评审据此判定是否滑向 Web 审美：

| 禁止 | 说明 |
|---|---|
| 无边框的可交互元素 | 包括仅靠悬停变色才显形的"幽灵按钮"；工具栏按钮例外见 REQ-THEME-031 |
| 圆角 > 4 lpx，胶囊形 | 开关控件的滑轨亦不得为胶囊形。唯一例外：单选框是边长 `check_size` 的正圆（REQ-THEME-039），这是该控件的通行识别形状 |
| 绘制的投影、发光、模糊 | 唯一的阴影是弹出窗口的系统阴影 |
| 大面积单一纯色的强调色块 | 如整条彩色标题区、彩色侧边栏 |
| 控件间距 > `gap_xl`，内容区留白 > `gap_2xl` | 紧凑密度 |
| 默认控件高度 > 28 lpx | |
| 入场动画、弹性/回弹缓动、视差、骨架屏闪烁 | |
| 纯图标且无提示文字的操作 | 图标按钮必须有 tooltip 与无障碍名称 |
| 用颜色作为唯一的状态区分 | 须同时有形状、图标或文字 |
| 自绘窗口标题栏 | ADR 0008 |

### 3.2 颜色令牌

**REQ-THEME-007**　主题**必须**以下表的令牌名提供浅色与深色两套颜色。表中色值是默认值，为规范性内容；带 α 的写作 `#RRGGBBAA`。

**表面**

| 令牌 | 浅色 | 深色 | 用途 |
|---|---|---|---|
| `surface_window` | `#ECEEF1` | `#1F2125` | 窗口底色 |
| `surface_panel` | `#F4F5F7` | `#26292E` | 面板、分组框、工具栏、状态栏 |
| `surface_raised_top` | `#FCFCFD` | `#3B3F46` | 凸起渐变起点（上） |
| `surface_raised_bottom` | `#EDEFF2` | `#33373D` | 凸起渐变终点（下） |
| `surface_raised_hover_top` | `#FFFFFF` | `#454A52` | 凸起·悬停 |
| `surface_raised_hover_bottom` | `#F3F5F8` | `#3C4047` | |
| `surface_raised_pressed_top` | `#DCDFE4` | `#2A2D32` | 凸起·按下（上暗下亮，反转） |
| `surface_raised_pressed_bottom` | `#E4E7EB` | `#2F3338` | |
| `surface_raised_disabled` | `#F0F1F3` | `#222428` | 凸起·禁用（纯色） |
| `surface_sunken` | `#FFFFFF` | `#16181B` | 输入框、列表、树、表格的底 |
| `surface_sunken_disabled` | `#F0F1F3` | `#222428` | |
| `surface_track` | `#D9DDE2` | `#17191C` | 进度槽、滑轨、滚动条槽 |
| `surface_popup` | `#F9FAFB` | `#2B2E33` | 菜单、下拉列表 |
| `surface_tooltip` | `#FFFFFF` | `#34383E` | 提示框 |
| `surface_row_alt` | `#F7F8FA` | `#232529` | 列表/表格的交替行（可选启用） |
| `surface_row_hover` | `#E6EAF0` | `#30343A` | 行、菜单项悬停 |
| `surface_selection_inactive` | `#D5D9DF` | `#3D4148` | 所在窗口或控件非活动时的选中底 |

**边框与斜面**

| 令牌 | 浅色 | 深色 | 用途 |
|---|---|---|---|
| `border_control` | `#7B838E` | `#747C87` | 可交互控件的边框 |
| `border_control_hover` | `#5F6772` | `#8F97A2` | 悬停时的边框 |
| `border_control_disabled` | `#C3C8CF` | `#40444A` | |
| `border_strong` | `#9AA1AB` | `#565C65` | 面板外框、分组框、弹出层外框 |
| `border_subtle` | `#D0D4DA` | `#383C42` | 分隔线、表格网格线、行分隔 |
| `bevel_highlight` | `#FFFFFFCC` | `#FFFFFF1A` | 凸起元素顶部内高光 |
| `bevel_shade` | `#0000001F` | `#00000059` | 凸起元素底边加深 |
| `inset_shadow` | `#00000024` | `#00000066` | 内凹元素顶部内阴影 |

**文字与图标**

| 令牌 | 浅色 | 深色 | 用途 |
|---|---|---|---|
| `text_primary` | `#1B1F24` | `#E7E9EC` | 正文、控件文字、图标 |
| `text_secondary` | `#555D68` | `#A7AEB8` | 说明、次要信息、快捷键提示 |
| `text_placeholder` | `#6A727D` | `#8C939D` | 输入框占位文字 |
| `text_disabled` | `#9299A3` | `#646B75` | |
| `text_on_accent` | `#FFFFFF` | `#FFFFFF` | 强调色填充上的文字与图标 |

**强调色**（默认值；实际由 REQ-THEME-009 从系统强调色派生）

| 令牌 | 浅色 | 深色 | 用途 |
|---|---|---|---|
| `accent_fill_top` | `#2F6EDF` | `#2F6FDE` | 默认按钮、选中项、勾选底的渐变起点 |
| `accent_fill_bottom` | `#1F59C6` | `#2561CE` | 渐变终点 |
| `accent_fill_hover_top` | `#3271E2` | `#3272E1` | 受 4.5 : 1 约束，只比常态略亮；悬停的可辨性主要来自渐变下端的提亮 |
| `accent_fill_hover_bottom` | `#2A63CF` | `#2F6AD6` | |
| `accent_fill_pressed_top` | `#1B50B4` | `#1F55B8` | |
| `accent_fill_pressed_bottom` | `#2259C2` | `#255DC2` | |
| `accent_border` | `#1A4CAB` | `#1B4FB0` | 强调色填充元素的边框 |
| `accent_mark` | `#2463D6` | `#4C8DF6` | 画在表面上的强调色：焦点环、进度填充、滑轨已选段、选中指示条 |
| `accent_text` | `#1F5BCB` | `#7FB0FF` | 表面上的强调色文字：链接 |
| `accent_halo` | `#2463D666` | `#4C8DF666` | 焦点环外圈 |

**状态色**（用于图标与文字；对应填充仅用于徽标）

| 令牌 | 浅色 | 深色 |
|---|---|---|
| `status_danger` | `#C4281C` | `#FF8A80` |
| `status_warning` | `#8A5A00` | `#F2B84B` |
| `status_success` | `#1E7B34` | `#6CCB7F` |
| `status_info` | `#1F5BCB` | `#7FB0FF` |

**REQ-THEME-008**　颜色令牌的默认值**必须**满足下列对比度（WCAG 2.1 相对亮度算法），应用替换令牌值时由 `theme.validate` 检查并在调试构建报告不达标项：

| 前景 | 背景 | 最小对比度 |
|---|---|---|
| `text_primary` | 全部 `surface_*`（禁用类除外） | 4.5 : 1 |
| `text_secondary` | `surface_window`、`surface_panel`、`surface_sunken`、`surface_popup`、`surface_row_alt` | 4.5 : 1 |
| `text_placeholder` | `surface_sunken` | 4.5 : 1 |
| `text_on_accent` | `accent_fill_top`、`accent_fill_bottom` 及其悬停/按下变体 | 4.5 : 1 |
| `accent_text`、`status_*` | `surface_window`、`surface_panel`、`surface_sunken`、`surface_popup` | 4.5 : 1 |
| `accent_mark` | 同上 | 3 : 1 |
| `border_control` | 同上（控件所处的表面） | 3 : 1 |

`text_disabled`、`border_control_disabled`、`border_subtle`、`border_strong` 不受对比度要求约束（禁用内容与装饰性分隔）。

**REQ-THEME-009**　强调色族**必须**默认从系统强调色派生（Win32：`DwmGetColorizationColor` 或 `UISettings` 等价值；应用可指定固定强调色覆盖）。派生算法：

1. 取系统色的色相 H 与饱和度 S（HSL）。若 S < 0.15（接近灰色），改用默认强调色族。
2. 保持 H，S 夹紧到 [0.55, 0.85]。
3. `accent_fill_bottom`：调整亮度 L 使其与 `text_on_accent` 的对比度恰 ≥ 5.5 : 1 的最大 L。
4. `accent_fill_top` = `accent_fill_bottom` 的 L + 0.05，若因此与 `text_on_accent` 对比度 < 4.5 : 1 则减小增量直至满足。
5. 悬停变体 = 对应值 L + 0.04（若因此与 `text_on_accent` 的对比度 < 4.5 : 1，则减小增量直至满足）；按下变体 = 对应值 L − 0.05 且上下互换；`accent_border` = `accent_fill_bottom` 的 L − 0.07。
6. `accent_mark`：浅色主题取 `accent_fill_bottom` 与 `accent_fill_top` 的中点；深色主题取 L 使其对 `surface_popup` 的对比度恰 ≥ 4 : 1 的最小 L。
7. `accent_text`：调整 L 使其对 `surface_panel` 的对比度恰 ≥ 5 : 1。
8. `accent_halo` = `accent_mark`，α = 40%。

系统强调色变化时（`WM_DWMCOLORIZATIONCOLORCHANGED` / `WM_SETTINGCHANGE`）重新派生并置 `build` 脏。

**REQ-THEME-010**　深浅色**必须**默认跟随系统的"应用模式"设置（注册表 `AppsUseLightTheme`，经 `WM_SETTINGCHANGE "ImmersiveColorSet"` 通知），应用可以固定为其一。切换时无需重启，标题栏的深浅通过 DWM 属性同步（03）。

### 3.3 度量令牌

**REQ-THEME-011**　主题**必须**提供下表度量令牌，单位 lpx。

| 令牌 | 值 | 用途 |
|---|---|---|
| `control_h_sm` / `control_h` / `control_h_lg` | 20 / 24 / 28 | 单行控件高度（按钮、输入框、下拉、行） |
| `row_h` | 22 | 列表、树、表格、菜单项的行高 |
| `header_h` | 24 | 表头、分组标题条 |
| `radius_control` | 3 | 按钮、输入框、滑块手柄 |
| `radius_container` | 4 | 分组框、弹出层、提示框、对话框内面板 |
| `radius_mark` | 2 | 勾选框、选中指示、进度条 |
| `gap_xs` / `gap_sm` / `gap_md` / `gap_lg` / `gap_xl` / `gap_2xl` | 2 / 4 / 8 / 12 / 16 / 24 | 间距阶梯。相关控件之间 `gap_sm`–`gap_md`，分组之间 `gap_lg`–`gap_xl` |
| `pad_control_x` | 10 | 按钮左右内边距 |
| `pad_input_x` | 6 | 输入框、下拉的左右内边距 |
| `pad_panel` | 8 | 面板、分组框内边距 |
| `pad_dialog` | 12 | 对话框客户区内边距 |
| `pad_popup_y` | 4 | 菜单、下拉列表的上下内边距 |
| `pad_item_x` | 8 | 行与菜单项的左右内边距 |
| `icon_sm` / `icon_md` / `icon_lg` | 16 / 20 / 32 | 图标边长；`icon_lg` 仅用于消息对话框的严重程度图标 |
| `check_size` | 14 | 勾选框、单选框边长 |
| `switch_w` / `switch_h` | 28 / 14 | 开关 |
| `slider_track_h` | 4 | 滑轨厚度 |
| `slider_thumb_w` / `slider_thumb_h` | 10 / 16 | 滑块手柄 |
| `slider_min_len` | 96 | 滑块控件沿滑动方向的最小长度 |
| `tab_indicator_h` | 2 | 标签页选中指示条的厚度 |
| `progress_h` | 6 | 进度条厚度 |
| `scrollbar_w` | 12 | 滚动条总宽。滚动条一旦显示即占位并保持可见，不做悬停才出现或淡出的"覆盖式"滚动条；是否显示仍由显示策略 auto/always/never 决定（07） |
| `scrollbar_thumb_min` | 24 | 滚动条滑块最小长度 |
| `splitter_w` | 5 | 分隔条命中宽度（可见线为发丝线） |
| `focus_ring_w` | 2 | 焦点环外圈宽度，同时是相应控件的绘制外延 |
| `indent` | 16 | 树的每级缩进 |
| `button_min_w` | 72 | 带文字按钮的最小宽度 |
| `tooltip_max_w` | 320 | 提示框最大宽度，超出换行 |
| `tooltip_offset_y` | 20 | 鼠标触发的提示框上缘相对指针热点的下移量 |
| `pad_tooltip_x` / `pad_tooltip_y` | 6 / 3 | 提示框内边距 |
| `menu_max_w` | 360 | 菜单最大宽度，超出的标题省略 |
| `dialog_text_max_w` | 420 | 标准消息对话框正文的最大宽度，超出换行 |

**REQ-THEME-012**　发丝线宽度**必须**为 `max(1, floor(scale))` 物理像素：缩放 100%–199% 时 1 ppx，200%–299% 时 2 ppx，依此类推。所有边框、分隔线、斜面高光、内阴影使用发丝线宽度，并对齐到物理像素边界（线的两侧都落在整数 ppx 坐标上）。

**REQ-THEME-013**　度量令牌换算到物理像素时**必须**四舍五入到整数 ppx，且不小于 1。同一令牌在同一缩放下换算结果恒定，使相同控件在任何位置尺寸一致。

**REQ-THEME-014**　圆角在绘制时取 `round(radius × scale)` ppx。内层形状（如边框内的填充）的圆角 = 外层圆角 − 发丝线宽度，不小于 0，以保持同心。

### 3.4 字体令牌

**REQ-THEME-015**　界面字体族**必须**取自系统消息字体（03），不内嵌字体。默认字号取系统消息字体字号（通常 9 pt = 12 lpx）。等宽字体族依次尝试 `Cascadia Mono`、`Consolas`、系统默认等宽字体。

**REQ-THEME-016**　主题**必须**提供下表文字样式。字号以"基准字号 B"（系统消息字体字号，lpx）的相对量定义，以跟随系统字体设置。 行高是主题规定的值，**不取**字体或文字后端的自然行高：控件排版时把令牌行高经 `text.LayoutOptions` 的行高参数传入，行框、文本光标高度、选区高度都等于令牌行高。因此同一控件在不同文字后端下的高度相同。

| 令牌 | 字号 | 字重 | 行高 | 用途 |
|---|---|---|---|---|
| `font_body` | B | 400 | `round(B × 4/3)`（B=12 时 16） | 默认 |
| `font_body_strong` | B | 600 | 同上 | 默认按钮文字、表头、选中的标签页 |
| `font_small` | B − 1 | 400 | `round((B−1) × 4/3)` | 状态栏、说明文字、快捷键提示 |
| `font_title` | B + 2 | 600 | `round((B+2) × 4/3)` | 对话框主指令、分区标题 |
| `font_mono` | B | 400 | 同 `font_body` | 代码、数值对齐 |

不提供更大的展示级字号。

**REQ-THEME-017**　单行控件内的文字**必须**在控件高度内按"行框垂直居中"放置：行框高 = 令牌行高，居中后基线位置取整到物理像素。同一行内不同控件（按钮、输入框、标签、勾选框）的文字基线**必须**落在同一条物理像素线上。

**REQ-THEME-018**　文字超出可用宽度时的默认处理是尾部省略号（`…`，U+2026），并在悬停时由提示框显示全文（控件规范逐一规定）。不得以裁切半个字形或渐隐处理。

### 3.5 动效令牌

**REQ-THEME-019**　主题**必须**提供下表动效令牌。

| 令牌 | 值 | 用途 |
|---|---|---|
| `dur_instant` | 0 ms | 按下态的出现（按下必须立即反馈） |
| `dur_fast` | 80 ms | 悬停进入/离开、按下释放、焦点环出现 |
| `dur_normal` | 120 ms | 勾选标记、开关滑块、标签页指示条、展开箭头旋转 |
| `dur_slow` | 200 ms | 进度值变化的追赶；仅此一处 |
| `dur_indeterminate` | 1600 ms | 不确定进度的一个循环周期 |
| `dur_autoscroll` | 50 ms | 拖动选择越界、拖放到边缘、菜单滚动指示悬停时的自动滚动节拍（定时器周期，不是过渡时长） |
| `ease_out` | cubic-bezier(0.2, 0, 0, 1) | 全部过渡的默认缓动 |
| `ease_linear` | 线性 | 不确定进度、进度追赶 |

**REQ-THEME-020**　动效**必须**满足：
- 只作用于颜色、透明度、小范围位移（≤ 16 lpx）与旋转；不得改变布局尺寸（展开/折叠内容是瞬时的）。
- 交互的生效时刻不等待动画：点击在释放瞬间生效，动画只是其后的视觉缓冲。
- 弹出层的出现/消失动画完全遵循系统设置：系统开启菜单淡入时用 `dur_fast` 的透明度淡入，关闭时瞬时出现；消失一律瞬时。
- 系统关闭动画时全部时长按 0 处理（REQ-FRAME-047），不确定进度改为静态的条纹图样。

### 3.6 绘制基元

`theme` 模块向控件提供下列绘制基元。每个基元的逐层配方是规范性的；"矩形 R"指控件传入的布局矩形（已对齐物理像素），`h` 为发丝线宽度，`r` 为所用圆角令牌。

**REQ-THEME-021**　`drawRaised(R, r, variant, visual)` —— 凸起表面。`variant` 为 `neutral` 或 `accent`。自下而上的层：

| 层 | 内容 |
|---|---|
| 1 填充 | 圆角矩形 R 内缩 `h`，圆角 `r − h`，自上而下线性渐变：`neutral` 用 `surface_raised_top → surface_raised_bottom`，`accent` 用 `accent_fill_top → accent_fill_bottom`；悬停/按下取对应变体 |
| 2 底边加深 | 填充区域最底部 `h` 高的一条，`bevel_shade`。按下态不画 |
| 3 顶部内高光 | 填充区域最顶部 `h` 高的一条，`bevel_highlight`，两端各内缩 `r`。按下态改为画 `inset_shadow` |
| 4 边框 | 圆角矩形 R 的发丝线描边：`neutral` 用 `border_control`（悬停 `border_control_hover`），`accent` 用 `accent_border` |

禁用态：层 1 改为纯色 `surface_raised_disabled`，不画层 2、3，层 4 用 `border_control_disabled`。

**REQ-THEME-022**　`drawSunken(R, r, visual, invalid)` —— 内凹表面。层：

| 层 | 内容 |
|---|---|
| 1 填充 | R 内缩 `h`，纯色 `surface_sunken`（禁用 `surface_sunken_disabled`） |
| 2 顶部内阴影 | 填充区域最顶部 `h` 高的一条，`inset_shadow`。禁用态不画 |
| 3 边框 | R 的发丝线描边，`border_control`（悬停 `border_control_hover`；聚焦 `accent_mark`；禁用 `border_control_disabled`） |

校验失败的输入框把层 3 的颜色换为 `status_danger`，并且**必须**同时显示错误图标或文字（REQ-THEME-006 末行）。

**REQ-THEME-023**　`drawFocusRing(R, r)` —— 焦点环。仅在焦点可见时绘制：在 R 外侧画宽 `focus_ring_w` 的圆角环，颜色 `accent_halo`，外圆角 `r + focus_ring_w`；同时该控件的边框颜色改为 `accent_mark`。出现用 `dur_fast` 淡入，消失瞬时。使用焦点环的节点**必须**声明绘制外延 = `focus_ring_w`。窗口非活动时不画焦点环。

**REQ-THEME-024**　`drawPanel(R, r)` —— 面板：纯色 `surface_panel` + `border_strong` 发丝线描边。无斜面。

**REQ-THEME-025**　`drawPopupFrame(R)` —— 弹出层底：纯色 `surface_popup` 填满弹出窗口，`border_strong` 发丝线描边；圆角与阴影交由系统（Windows 11 上请求系统小圆角，Windows 10 上为直角 + 系统阴影，见 03）。提示框用 `surface_tooltip`。

**REQ-THEME-026**　`drawSeparator(a, b)` —— 分隔线：`border_subtle` 的发丝线。位于 `surface_panel` 与 `surface_window` 交界处的结构性分隔（工具栏底、状态栏顶）用 `border_strong`。

**REQ-THEME-027**　`drawSelection(R, active)` —— 行选中底：`active` 为真（所在控件有焦点且窗口活动）时用 `accent_fill_bottom` 纯色、文字换 `text_on_accent`；否则 `surface_selection_inactive`、文字保持 `text_primary`。选中底为直角、占满行宽。

**REQ-THEME-028**　`drawTrack(R)` 与 `drawTrackFill(R)` —— 槽与填充：槽为 `surface_track` 纯色 + 顶部 `inset_shadow` 发丝线，圆角 `radius_mark`；填充为 `accent_mark` 纯色，同圆角。

**REQ-THEME-029**　`drawMark(kind, R, color)` —— 标记字形：`check`、`indeterminate`（横线）、`radio_dot`、`chevron_{up,down,left,right}`、`close`、`sort_{asc,desc}`、`grip`。以 16 lpx 网格定义的矢量路径，笔画宽 1.5 lpx、圆头圆角连接，绘制时整体对齐到物理像素。 `rotation`（弧度，绕 R 中心）参数供展开箭头等的旋转过渡使用，旋转时不做像素对齐；各文档行文中写作 `drawMark(kind, R, color)` 而省略该参数时即表示 0（不旋转）。

**REQ-THEME-038**　`drawRowFocus(R, on_selection)` —— 行内焦点指示：列表、树、表格、菜单中"焦点项"在焦点可见时的标记。在 R 内侧画一圈发丝线矩形（直角），颜色 `accent_mark`；该行同时为活动选中行时（调用方以 `on_selection` 告知）改用 `text_on_accent`。高对比度下用 `COLOR_WINDOWTEXT`（选中行上用 `COLOR_HIGHLIGHTTEXT`）。不产生绘制外延。窗口非活动时不画。

**REQ-THEME-039**　勾选类控件的专用基元。三者都带过渡进度 `t ∈ [0,1]`（由控件以 `dur_normal` 的 `ui.animate` 提供；0 = 未选/关，1 = 选中/开），`t` 只用于在两端外观之间做颜色线性插值与标记的几何显现，**不得**用整体透明度实现。

| 基元 | 配方 |
|---|---|
| `drawCheckBox(R, state, t, visual)` | R 为边长 `check_size` 的正方形，圆角 `radius_mark`。`off`：`drawSunken` 配方。`on`/`mixed`：填充为 `accent_fill_top → accent_fill_bottom` 纵向渐变（悬停/按下取对应变体），发丝线边框 `accent_border`，其上以 `text_on_accent` 画 `check` 或 `indeterminate` 标记；过渡时填充与边框颜色在 `off` 与 `on` 之间按 `t` 插值，标记按笔画长度的前 `t` 比例显现。禁用：填充 `surface_sunken_disabled`、边框 `border_control_disabled`、标记 `text_disabled`，无渐变。 |
| `drawRadio(R, on, t, visual)` | R 为边长 `check_size` 的正方形的内切**正圆**。未选：圆形的内凹表面（填充 `surface_sunken`、顶部弧形 `inset_shadow` 发丝线、发丝线边框 `border_control`，悬停 `border_control_hover`）。选中：填充与边框同 `drawCheckBox` 的 `on`，中心画 `radio_dot`（`text_on_accent`），圆点半径按 `t` 从 0 增至标称值。禁用同上表规则。 |
| `drawSwitch(R, on, t, visual)` | R 为 `switch_w × switch_h`，圆角 `radius_mark`。滑轨：关时为 `surface_track` 填充 + 顶部 `inset_shadow` + 发丝线边框 `border_control`；开时为 `accent_mark` 填充 + 边框 `accent_border`；颜色按 `t` 插值。滑块：边长 `switch_h − 2 × 发丝线` 的凸起表面（`drawRaised(neutral)` 配方，圆角 `radius_mark`），水平位置按 `t` 在滑轨内侧左端与右端之间线性移动并对齐物理像素。禁用：滑轨 `surface_sunken_disabled`、边框 `border_control_disabled`，滑块用凸起禁用配方。 |

三者在焦点可见时由控件另画 `drawFocusRing`（单选框的焦点环为同心圆环）。

**REQ-THEME-040**　槽类基元的变体：`drawTrack(R, disabled)` 在禁用时填充改为 `surface_sunken_disabled` 且不画内阴影；`drawTrackFill(R, tone)` 的 `tone` 取 `accent`（`accent_mark`）、`warning`（`status_warning`）、`danger`（`status_danger`）、`disabled`（`text_disabled`）；`drawTrackStripes(R, phase)` 在 R 内以 `accent_mark` 画等宽等距的竖直条纹（条宽与间隔均为 `gap_sm`，裁剪到 R 的圆角内），`phase ∈ [0,1)` 为条纹的水平相位，用于不确定进度的循环动画，系统关闭动画时恒传 0（静态条纹，REQ-THEME-020）。以状态色表达暂停/错误的进度条**必须**同时有文字或图标（REQ-THEME-006）。

**REQ-THEME-041**　`drawTab(R, selected, visual)` —— 标签页的标签：未选中时无填充无边框（位于有 `border_strong` 底边线的标签条内，属 REQ-THEME-031 的"安静"类），悬停时填充 `surface_row_hover`；选中时填充 `surface_panel`（与内容区连成一体，盖住标签条底边线的对应一段），左右与上方有 `border_strong` 发丝线，上方圆角 `radius_control`。选中指示条由控件另画：厚 `tab_indicator_h` 的 `accent_mark` 条，位于选中标签的顶边内侧，切换时其水平位置与宽度以 `dur_normal` 过渡。

### 3.7 状态表现总则

**REQ-THEME-030**　控件的视觉状态及其优先级（高者覆盖低者）**必须**为：禁用 > 按下 > 悬停 > 常态；聚焦与选中/勾选是可与前者叠加的独立维度。各状态的通用表现：

| 状态 | 表现 |
|---|---|
| 常态 | 按基元配方 |
| 悬停 | 填充换悬停变体，边框换 `border_control_hover`；过渡 `dur_fast` |
| 按下 | 凸起元素渐变反转 + 顶部内阴影，内容（文字与图标）整体下移 1 ppx；`dur_instant` 进入，`dur_fast` 退出 |
| 聚焦 | 焦点可见时画焦点环 |
| 禁用 | 换禁用令牌，无体积感，文字 `text_disabled`，不响应悬停，鼠标指针为默认箭头 |
| 选中/勾选 | 使用强调色（填充或标记），并有形状变化（勾、点、指示条） |

**REQ-THEME-031**　工具栏按钮与列表行内的操作按钮是"安静凸起"变体：常态不画填充与边框（仅图标/文字），悬停与按下时才按 `drawRaised` 完整绘制。这是 REQ-THEME-002 的唯一例外，成立前提是它们位于有明确边界的容器（工具栏、行）内且成组排列。 标签页的未选中标签同属此类（REQ-THEME-041），前提同上：它们成组位于有底边线的标签条内。

**REQ-THEME-032**　鼠标指针形状遵循系统约定：普通控件为箭头（**不**对按钮使用手形）；文本输入区为 I 形；链接为手形；分隔条与可调整的列边界为对应的双向箭头；禁用控件为箭头。

### 3.8 图标

**REQ-THEME-033**　内建图标**必须**是单色矢量路径，在 16 lpx 网格上设计，主要笔画宽 1.5 lpx（100% 缩放下允许微调到 1 或 2 ppx 以保持清晰），以 `text_primary`（或所在上下文的文字色）着色。不使用多色图标、不使用图标字体。

**REQ-THEME-034**　框架内建图标集限于控件自身需要的标记（REQ-THEME-029 所列）与通用状态图标（`info`、`warning`、`error`、`success`、`search`、`more`）。应用图标由应用以同样的路径格式或位图提供；位图图标须提供 100%/150%/200% 三档或一张 ≥ 2 倍的源图。

### 3.9 系统适配

**REQ-THEME-035**　系统启用高对比度（`SPI_GETHIGHCONTRAST`）时，主题**必须**切换到高对比度令牌集：全部颜色映射到系统颜色，去除一切渐变、斜面、内阴影，边框与焦点环加粗。

| 令牌族 | 映射 |
|---|---|
| 全部 `surface_*`（选中除外） | `COLOR_WINDOW`；凸起类用 `COLOR_BTNFACE` |
| `text_primary`、`text_secondary`、`text_placeholder` | `COLOR_WINDOWTEXT`；凸起类上用 `COLOR_BTNTEXT` |
| `text_disabled`、`border_control_disabled` | `COLOR_GRAYTEXT` |
| 全部 `border_*`（禁用除外） | `COLOR_WINDOWTEXT`（凸起类 `COLOR_BTNTEXT`） |
| `accent_fill_*`、`accent_mark`、选中底 | `COLOR_HIGHLIGHT` |
| `text_on_accent` | `COLOR_HIGHLIGHTTEXT` |
| `accent_text` | `COLOR_HOTLIGHT` |
| 悬停 | 边框换 `COLOR_HIGHLIGHT`，填充不变 |
| 焦点环 | `COLOR_WINDOWTEXT` 实线，宽 2 lpx，无外圈光晕 |

**REQ-THEME-036**　下列系统设置变化时主题**必须**即时响应（置 `build` 脏，必要时清缓存），无需重启：深浅色、强调色、高对比度开关及其配色、系统消息字体与字号、文本缩放系数、动画开关、DPI。

**REQ-THEME-037**　主题数据是一个普通的值结构 `Theme`（令牌表）。应用**可以**在启动时或运行中提供自己的 `Theme` 值或在默认值上改写个别令牌；框架不提供样式表、选择器、按控件实例的样式覆盖。个别控件确需不同外观时，使用该控件规范中列出的变体参数。

## 4. 接口草案

```zig
// 草案：仅签名
pub const Mode = enum { light, dark, high_contrast };

pub const ColorToken = enum {
    surface_window, surface_panel,
    surface_raised_top, surface_raised_bottom,
    surface_raised_hover_top, surface_raised_hover_bottom,
    surface_raised_pressed_top, surface_raised_pressed_bottom,
    surface_raised_disabled,
    surface_sunken, surface_sunken_disabled, surface_track,
    surface_popup, surface_tooltip,
    surface_row_alt, surface_row_hover, surface_selection_inactive,
    border_control, border_control_hover, border_control_disabled,
    border_strong, border_subtle,
    bevel_highlight, bevel_shade, inset_shadow,
    text_primary, text_secondary, text_placeholder, text_disabled, text_on_accent,
    accent_fill_top, accent_fill_bottom,
    accent_fill_hover_top, accent_fill_hover_bottom,
    accent_fill_pressed_top, accent_fill_pressed_bottom,
    accent_border, accent_mark, accent_text, accent_halo,
    status_danger, status_warning, status_success, status_info,
};

pub const Metric = enum {
    control_h_sm, control_h, control_h_lg, row_h, header_h,
    radius_control, radius_container, radius_mark,
    gap_xs, gap_sm, gap_md, gap_lg, gap_xl, gap_2xl,
    pad_control_x, pad_input_x, pad_panel, pad_dialog, pad_popup_y, pad_item_x,
    icon_sm, icon_md, icon_lg, check_size, switch_w, switch_h,
    slider_track_h, slider_thumb_w, slider_thumb_h, slider_min_len, tab_indicator_h, progress_h,
    scrollbar_w, scrollbar_thumb_min, splitter_w, focus_ring_w,
    indent, button_min_w, tooltip_max_w, tooltip_offset_y, pad_tooltip_x, pad_tooltip_y, menu_max_w, dialog_text_max_w,
};

pub const Gap = enum { none, xs, sm, md, lg, xl, xxl };  // 布局参数中使用的间距阶梯

pub const FontToken = enum { body, body_strong, small, title, mono };
pub const Duration = enum { instant, fast, normal, slow, indeterminate, autoscroll };
pub const Easing = enum { out, linear };

pub const Theme = struct {
    mode: Mode,
    colors: std.EnumArray(ColorToken, Color),
    metrics: std.EnumArray(Metric, f32),          // lpx
    fonts: std.EnumArray(FontToken, text.Style),  // 05
    durations_ms: std.EnumArray(Duration, u16),

    pub fn default(mode: Mode, sys: platform.SystemAppearance) Theme;
    pub fn color(self: *const Theme, t: ColorToken) Color;
    pub fn metric(self: *const Theme, m: Metric) f32;
    pub fn px(self: *const Theme, m: Metric, scale: f32) i32;      // REQ-THEME-013
    pub fn hairline(scale: f32) i32;                               // REQ-THEME-012
    pub fn deriveAccent(self: *Theme, system_accent: Color) void;  // REQ-THEME-009
    pub fn validate(self: *const Theme, out: *ValidationReport) bool; // REQ-THEME-008
};

pub const Visual = struct {
    hovered: bool, pressed: bool, focused_visible: bool, disabled: bool,
    hover_t: f32,  // 悬停过渡进度 0–1（dur_fast），由框架内建交互状态提供（REQ-FRAME-013）
    press_t: f32,  // 按下过渡进度 0–1（进入 dur_instant，退出 dur_fast）
    focus_t: f32,  // 焦点环淡入进度 0–1
};
/// 绘制基元所需的全部上下文。`ui.PaintCtx` 内含一个 `draw: theme.DrawCtx` 字段，控件的绘制函数传 `&ctx.draw`。
/// theme 不依赖 ui（REQ-ARCH-001）。
pub const DrawCtx = struct {
    canvas: *gfx.Canvas,
    theme: *const Theme,
    scale: f32,
    window_active: bool,
};

/// 图标：内建标记字形或应用提供的图像。各控件、命令、窗口图标共用。
pub const Icon = union(enum) { mark: MarkKind, image: gfx.ImageId, set: gfx.ImageSet }; // set：多缩放档，按 REQ-GFX-034 选取

pub const RaisedVariant = enum { neutral, accent, quiet };
pub const MarkKind = enum {
    check, indeterminate, radio_dot,
    chevron_up, chevron_down, chevron_left, chevron_right,
    close, sort_asc, sort_desc, grip,
    info, warning, @"error", success, search, more,
};

pub fn drawRaised(ctx: *const DrawCtx, r: Rect, radius: Metric, variant: RaisedVariant, v: Visual) void;
pub fn drawSunken(ctx: *const DrawCtx, r: Rect, radius: Metric, v: Visual, invalid: bool) void;
pub fn drawFocusRing(ctx: *const DrawCtx, r: Rect, radius: Metric) void;
pub fn drawPanel(ctx: *const DrawCtx, r: Rect, radius: Metric) void;
pub fn drawPopupFrame(ctx: *const DrawCtx, r: Rect, tooltip: bool) void;
pub fn drawSeparator(ctx: *const DrawCtx, a: Vec2, b: Vec2, structural: bool) void;
pub fn drawSelection(ctx: *const DrawCtx, r: Rect, active: bool) void;
pub const CheckState = enum { off, on, mixed };
pub const TrackTone = enum { accent, warning, danger, disabled };
pub fn drawCheckBox(ctx: *const DrawCtx, r: Rect, state: CheckState, t: f32, v: Visual) void;
pub fn drawRadio(ctx: *const DrawCtx, r: Rect, on: bool, t: f32, v: Visual) void;
pub fn drawSwitch(ctx: *const DrawCtx, r: Rect, on: bool, t: f32, v: Visual) void;
pub fn drawTrack(ctx: *const DrawCtx, r: Rect, disabled: bool) void;
pub fn drawTrackFill(ctx: *const DrawCtx, r: Rect, tone: TrackTone) void;
pub fn drawTrackStripes(ctx: *const DrawCtx, r: Rect, phase: f32) void;
pub fn drawTab(ctx: *const DrawCtx, r: Rect, selected: bool, v: Visual) void;
pub fn drawMark(ctx: *const DrawCtx, kind: MarkKind, r: Rect, color: ColorToken, rotation: f32) void;
pub fn drawRowFocus(ctx: *const DrawCtx, r: Rect, on_selection: bool) void;
```

## 5. 边界与错误情况

| 情况 | 规定 |
|---|---|
| 分数缩放（125%、150%、175%） | 发丝线恒为 1 ppx；令牌换算四舍五入；圆角按 REQ-THEME-014。不允许出现半像素模糊的边框。 |
| 控件矩形小于其基元所需的最小尺寸（< 2×(h + r)） | 圆角夹紧到 `min(w, h) / 2`；斜面与内阴影在高度 < 6 ppx 时不画。 |
| 系统强调色接近灰色或与表面对比不足 | 按 REQ-THEME-009 第 1 步回退，或由亮度调整步骤保证对比。 |
| 应用提供的 `Theme` 未通过 `validate` | 调试构建记录每个不达标项的 `warn`；仍然使用该主题（应用自负其责）。 |
| 系统消息字体不可用或字号异常（< 8 或 > 32 lpx） | 回退到 `Segoe UI` 12 lpx，记录 `warn`。 |
| 高对比度下应用自定义的强调色 | 忽略，使用系统颜色。 |
| 窗口非活动 | 选中底改用 `surface_selection_inactive`，不画焦点环，光标不闪烁且隐藏；其余不变（不整体变灰）。 |

## 6. 验收标准

**AC-THEME-001**　`[金图]` 覆盖：REQ-THEME-001、REQ-THEME-003、REQ-THEME-021、REQ-THEME-022。渲染一个凸起矩形与一个内凹矩形（各 80×24 lpx，缩放 100%，浅/深各一），读取像素。预期：凸起填充区第一行像素亮度 > 最后一行，CIE L\* 之差在 (0, 4] 内（不计高光与加深层）；按下态相反；顶部高光与底边加深各恰为 1 ppx 高；内凹矩形填充区首行比第二行暗；整体与基准图一致。

**AC-THEME-002**　`[金图]` 覆盖：REQ-THEME-002、REQ-THEME-031。渲染"控件总览"页，并以调试开关把全部填充色替换为窗口底色。预期：除工具栏按钮与行内操作按钮的常态外，每个可交互控件的轮廓仍由边框完整呈现（与"仅边框"基准图一致）。

**AC-THEME-003**　`[人工]` 覆盖：REQ-THEME-004、REQ-THEME-006。对三个示例应用的主界面逐项对照禁止项表评审，并用脚本统计截图中强调色族像素占比。预期：无禁止项命中；无大面积选区时强调色像素 ≤ 10%。

**AC-THEME-004**　`[金图]` 覆盖：REQ-THEME-005、REQ-THEME-030。渲染每种基础控件的 常态/悬停/按下/聚焦/禁用/选中 矩阵。预期：与基准图一致；禁用态像素中不存在由半透明混合产生的颜色（禁用态用到的颜色集合 ⊆ 禁用令牌 ∪ 表面令牌）；按下态内容相对常态下移恰 1 ppx。

**AC-THEME-005**　`[单元]` 覆盖：REQ-THEME-007、REQ-THEME-008。对默认浅色与深色主题调用 `theme.validate`；并断言 `ColorToken` 的每个成员在两套主题中的值与本文表格一致（测试数据由文档表格生成）。预期：校验通过，零不达标项；值全部相符。另构造一个把 `text_primary` 改为与 `surface_window` 相同的主题，预期 `validate` 返回假并指出该对。

**AC-THEME-006**　`[单元]` 覆盖：REQ-THEME-009。以 24 个色相均匀分布的高饱和色、3 个灰色、纯黑、纯白作为系统强调色调用 `deriveAccent`（浅/深各一次）。预期：每个结果均通过 `validate`；灰色、黑、白输入得到默认强调色族；非灰输入的结果色相与输入色相之差 ≤ 2°。

**AC-THEME-007**　`[人工]` 覆盖：REQ-THEME-010、REQ-THEME-036。应用运行中，在系统设置里依次切换：应用深浅色、强调色、高对比度开/关、文本大小（辅助功能）、动画开关；并把窗口拖到不同缩放的显示器。预期：每次变化后 1 秒内界面完成更新，标题栏深浅同步，无残留的旧颜色或旧尺寸，无需重启。

**AC-THEME-008**　`[单元]` 覆盖：REQ-THEME-011、REQ-THEME-013。断言 `Metric` 每个成员的默认值与本文表格一致。对每个令牌在缩放 1.0/1.25/1.5/1.75/2.0/2.5/3.0 下调用 `px`。预期：结果 = `max(1, round(值 × scale))`；重复调用结果恒定。

**AC-THEME-009**　`[金图]` 覆盖：REQ-THEME-012、REQ-THEME-014。在缩放 1.0/1.25/1.5/1.75/2.0/3.0 下渲染位于非整数 lpx 位置（如 x = 10.3）的按钮与输入框，放大检视边框像素。预期：边框宽度依次为 1/1/1/1/2/3 ppx；边框像素为纯色，无抗锯齿产生的中间色出现在直边上；内外圆角同心（内圆角半径 = 外半径 − 发丝线宽度）。

**AC-THEME-010**　`[人工]` 覆盖：REQ-THEME-015。在系统消息字体分别为默认（Segoe UI 9pt）与被修改为其他字体/字号的 Windows 上运行。预期：界面字体与同机资源管理器菜单字体的字族、字号一致；中文字符显示为系统回退字体（如 Microsoft YaHei UI），无豆腐块。

**AC-THEME-011**　`[单元]` 覆盖：REQ-THEME-016。以 B = 12、13、15 构造主题。预期：各样式的字号、字重、行高与表中公式一致（B=12 时 `font_body` 行高 16、`font_small` 字号 11 行高 15、`font_title` 字号 14 行高 19）。

**AC-THEME-012**　`[金图]` 覆盖：REQ-THEME-017。一行内并排放置按钮、输入框、下拉、勾选框（带标签）、纯标签，文字均为"Hxg中"；缩放 1.0/1.25/1.5/2.0。预期：检测每个控件文字基线所在的像素行（取字母 H 底边），全部相同。

**AC-THEME-013**　`[金图]` 覆盖：REQ-THEME-018。把含长文本的按钮、标签、列表行宽度压到文本宽度的一半。预期：文本以 `…` 结尾，最后一个可见字形完整，无被裁切的半个字形。

**AC-THEME-014**　`[单元]` 覆盖：REQ-THEME-019、REQ-THEME-020。断言各时长令牌值与表一致；断言 `ease_out` 在 t = 0、0.5、1 处的值为 0、(0.5, 1) 区间内、1。回放：点击勾选框。预期：`changed` 在释放事件所在帧返回（不晚于动画开始）；动画期间各帧的布局矩形集合完全相同（动效不改布局）。系统动画关闭时，不确定进度条在 3 秒内帧数为 0。

**AC-THEME-015**　`[金图]` 覆盖：REQ-THEME-023。同一按钮分别经 Tab 键与鼠标点击获得焦点；再使窗口失去激活。预期：Tab 获得焦点时出现宽 `focus_ring_w` 的外环且边框为 `accent_mark`；鼠标点击获得焦点时无环；窗口非活动时无环。损伤矩形包含外环范围。

**AC-THEME-016**　`[金图]` 覆盖：REQ-THEME-024、REQ-THEME-025、REQ-THEME-026、REQ-THEME-027、REQ-THEME-028、REQ-THEME-029、REQ-THEME-038。逐一渲染各绘制基元的全部变体（行内焦点指示于普通行与活动选中行上各一、旋转 90° 的 `chevron_right` 与 `chevron_down` 逐像素比对允许的差异仅限抗锯齿边缘、面板、弹出底与提示底、两种分隔线、活动/非活动选中底、槽与填充、全部标记字形于 16/20 lpx 两种尺寸），浅/深、缩放 1.0/1.5/2.0。预期：与基准图一致；标记字形在 100% 下笔画边缘落在整数像素上。

**AC-THEME-017**　`[回放]` 覆盖：REQ-THEME-032。鼠标依次移到：按钮、文本输入框、链接、分隔条、表格列边界、禁用按钮。预期：平台层记录的指针形状依次为 箭头、I 形、手形、双向箭头、双向箭头、箭头。

**AC-THEME-018**　`[单元]` 覆盖：REQ-THEME-033、REQ-THEME-034。检查内建图标数据。预期：全部为路径数据、无位图、无字体引用；图标名集合恰等于 `MarkKind` 成员集合；每个图标路径的包围盒在 16×16 网格内。

**AC-THEME-019**　`[人工]` 覆盖：REQ-THEME-035。在 Windows 上启用"高对比度黑色"与"高对比度白色"各运行"控件总览"页。预期：所有颜色来自系统高对比度配色；无渐变、无斜面；每个控件的边界、焦点、选中、禁用都可辨认；与同配色下的原生控件色彩一致。另 `[金图]` 以注入的系统颜色表在无头环境渲染并与基准比对。

**AC-THEME-020**　`[单元]` 覆盖：REQ-THEME-037。运行时把 `radius_control` 改为 0、`accent_*` 改为另一色族后置 `build` 脏。预期：下一帧全部控件随之变化；公开 API 中不存在按控件实例设置颜色/圆角的入口（控件规范列出的变体参数除外）。

**AC-THEME-021**　`[金图]` 覆盖：REQ-THEME-039、REQ-THEME-040、REQ-THEME-041。渲染：`drawCheckBox` 的 off/on/mixed × {常态, 悬停, 按下, 禁用}，以及 `t` = 0、0.5、1 三个过渡点；`drawRadio` 与 `drawSwitch` 的同类矩阵；`drawTrack` 启用/禁用、`drawTrackFill` 四种 `tone`、`drawTrackStripes` 于 `phase` = 0 与 0.5；`drawTab` 的 选中/未选中 × {常态, 悬停}。浅/深/高对比度，缩放 1.0/1.5/2.0。预期：与基准图一致；并以像素断言确认——`t` = 0.5 时勾选框填充色为两端颜色的线性中值（各通道误差 ≤ 1）且画面中不存在由整体半透明混合产生的颜色；单选框外轮廓为正圆（外接矩形宽 = 高 = `check_size` 换算值）；开关滑块在 `t` = 0 / 1 时分别贴滑轨内侧左 / 右端，`t` = 0.5 时居中（误差 ≤ 1 ppx）；`phase` 0 与 0.5 的条纹图样水平相差半个周期。

## 7. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-THEME-01 | 浅色下 `border_control` 为满足 3:1 而偏深，实机观感是否过重 | M3 实机评审；若过重，可仅对凸起类降低要求（其辨识还依赖渐变与文字），输入类保持 |
| OPEN-THEME-02 | 是否提供"舒适"密度（控件高 28）的整套切换 | 不提供；`control_h_lg` 供个别场合使用 |
| OPEN-THEME-03 | Windows 11 上弹出层是否请求 Mica/Acrylic 背景 | 不请求，保持不透明表面 |
