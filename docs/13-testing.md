# 13 测试

## 1. 范围

定义框架的四层测试及其职责、运行命令、金图基准的存放与比对规则、输入回放脚本的格式与指令集、测试辅助设施的注入点，以及文档一致性检查与验收追溯规则。

性能测试（`zig build bench`）不属于本文的四层，其规范见 12。规范文档与验收条款的编号与格式见 00；构建步骤名与文字后端选项见 02 的 REQ-ARCH-022。无头平台的注入接口（假时钟、假垂直同步、事件注入、系统外观与度量注入）由 03 的 REQ-PLAT-086 定义，本文只规定如何在测试中使用它们。

## 2. 术语

| 术语 | 定义 |
|---|---|
| 金图 | 一张由无头渲染读回的帧缓冲，与仓库中同名基准 PNG 比对的测试用例。 |
| 基准 PNG | 存于 `tests/golden/` 的已确认正确的金图图像。 |
| 文字区域 | 帧中由文字绘制（`drawGlyphQuads`）的四边形外接矩形所覆盖的像素区域，定义与比对规则见 04 的 REQ-GFX-040。 |
| 固定度量文字后端 | `text` 模块的 `fixed` 后端，不加载字体，度量按 05 的 REQ-TEXT-038 公式给出，用于单元测试。 |
| 回放脚本 | 按本文第 3.4 节格式书写的、每行一条指令的文本文件，由回放运行器执行。 |
| 回放运行器 | 解析并执行回放脚本、驱动无头平台、断言结果的测试程序。 |
| 无头平台 | 03 的 GLFW 无头模式，以假时钟、假垂直同步与注入事件替代真实依赖（REQ-PLAT-086）。 |
| 调试名 | 应用在控件选项的 `debug_name` 字段中给出的可选字符串，用于在测试中定位节点；在同一构建遍内必须唯一。 |
| 幂等校验 | 在无事件帧额外执行一遍构建函数，比对两次产出的节点树哈希的调试模式（06 第 5 节）。 |
| 里程碑清单 | 位于 `docs/acceptance/` 的文档，列出一个里程碑退出时必须通过的全部 AC，并记录执行结果。 |

## 3. 规范条款

### 3.1 四层测试

**REQ-TEST-001**　自动化测试**必须**分为四层，各层的职责、运行命令与结果判定如下：

| 层 | 职责 | 运行命令（02 REQ-ARCH-022） | 判定 |
|---|---|---|---|
| 1. 单元 | 纯逻辑：布局算法、ID 哈希、状态存储、文本位置运算、主题派生与校验、命令查表、设置读写 | `zig build test` | 全部用例通过，退出码为 0 |
| 2. 金图 | 无头渲染后与基准 PNG 比对 | `zig build test-golden` | 全部比对一致，退出码为 0 |
| 3. 回放 | 注入输入序列，逐步断言状态、计数器与金图 | `zig build test-replay` | 全部脚本的全部断言通过，退出码为 0 |
| 4. 人工 | 仅限 `[人工]` 标签的验收条款，在真实 Windows 上执行 | 无命令，按 REQ-TEST-026 的清单执行 | 清单项逐条记录结果 |

**REQ-TEST-002**　单元测试层**必须**只包含纯逻辑用例。单元测试**不得**创建窗口、不得创建 GL 上下文、不得访问系统字体。

**REQ-TEST-003**　金图层**必须**在无头模式下渲染到离屏帧缓冲，经 `readPixels` 读回后与基准 PNG 比对。金图层**不得**依赖窗口的显示或其内容。

**REQ-TEST-004**　回放层**必须**由回放运行器执行回放脚本。回放运行器**必须**使用无头平台的假时钟与假垂直同步（REQ-TEST-016），使结果不依赖真实耗时。

**REQ-TEST-005**　凡验收条款标为 `[人工]` 的，**必须**由人在真实 Windows 上操作并确认，不得由自动化替代。每个里程碑的人工项按 REQ-TEST-026 记录。

### 3.2 单元测试

**REQ-TEST-006**　单元测试**必须**使用固定度量文字后端（`-Dtext-backend=fixed`，02 的 REQ-ARCH-022 中 `zig build test` 的默认值）。该后端的前进宽度、ascent、descent 与行距按 05 的 REQ-TEXT-038 公式给出，同一字符串在任何机器上的度量结果**必须**完全相同。布局、排版位置与命中测试的用例**必须**使用该后端，以免字体差异影响断言。

### 3.3 金图测试

**REQ-TEST-007**　金图的输出**必须**经无头渲染与 `readPixels` 得到，渲染目标的尺寸、缩放与主题由用例指定。金图层的基准图像**必须**与渲染目标的像素格式一致（sRGB，非预乘）。金图层使用 `test-golden` 构建的文字后端：Linux 上为 `fontstash` 加仓库内测试字体，Windows 变体为 `directwrite`（REQ-TEXT-001）；不使用 `fixed` 后端。

**REQ-TEST-008**　基准 PNG 的目录**必须**为 `tests/golden/<后端>/<主题>/<缩放>/<用例>.png`，各段规则如下：
- `<后端>`：`win32` 或 `glfw`（04 的 REQ-GFX-040）。
- `<主题>`：ASCII snake_case 的主题名，如 `instrument_light`、`instrument_dark`、`high_contrast`。
- `<缩放>`：`s` 加百分比整数，如 `s100`、`s125`、`s150`。
- `<用例>`：ASCII snake_case，允许以 `/` 分层，如 `widget_gallery/button/hover`。

一个用例在一个后端、主题与缩放下只有一张基准图。

**REQ-TEST-009**　比对规则如下：
- 非文字区域**必须**逐像素相等（04 的 REQ-GFX-040 第 2 条）。
- 文字区域的界定与容差**以 04 的 REQ-GFX-040 为准**，本文不重复定义。测试构建中文字区域由 `gfx.testing.textRegions()` 报告，比对函数**必须**接收该区域集合。
- 文字基准**必须**按后端分开存放（ADR 0003）：同一用例在 `win32` 与 `glfw` 下分别有各自的基准图，两者不得互相替代。
- 文字区域的容差**不得**用于掩盖非文字区域的差异。

**REQ-TEST-010**　金图比对失败时，测试**必须**在输出目录写入 `<用例>.actual.png`（实际渲染结果）与 `<用例>.diff.png`（差异标注图）。这两类文件已在 `.gitignore` 中忽略，**不得**提交。失败时**不得**修改基准文件（04 的 REQ-GFX-040 第 5 条）。

**REQ-TEST-011**　基准 PNG 的更新**必须**作为独立提交完成，且该提交说明中**必须**写明更新原因（如"按 REQ-THEME-036 调整了高对比度下的焦点环"）。基准更新提交**不得**同时包含实现改动（见 CONV 的提交规范）。

**REQ-TEST-012**　CI 上金图测试**必须**使用固定版本的 Mesa（llvmpipe），版本号写入 CI 配置。CI 日志**必须**输出实际使用的 Mesa 版本。版本变更属于基准可能变化的事件，须与基准更新一同评审。

### 3.4 输入回放测试

**REQ-TEST-013**　回放脚本**必须**为 UTF-8 文本，每行一条指令。空行与以 `#` 开头（去除前导空白后）的行被忽略。行内的 `#` 不作为注释起始，以免与字符串内容混淆。解析失败**必须**报告脚本文件名与行号，并以非零码退出。

**REQ-TEST-014**　回放指令集**必须**与第 4.1 节指令表一致。指令名与参数形式冻结；新增指令须同步修改本文并经评审。未知指令**必须**视为解析失败。

**REQ-TEST-015**　节点通过调试名定位，写作 `@调试名`（如 `move @保存按钮`）。调试名在同一构建遍内**必须**唯一（与 06 的 REQ-FRAME-005 范围一致）：重复时回放失败并报告两处调用点。找不到调试名时回放失败。调试名可指向主根或弹出根中的节点。

**REQ-TEST-016**　回放运行器**必须**使用无头平台的假时钟与假垂直同步（03 的 REQ-PLAT-086），所有动画求值、定时器到期与光标闪烁均只由 `advance` 与 `vsync` 指令推进；测试代码**不得**读取系统时钟判定结果。推进语义**必须**如下：
- `advance ms`：推进假时钟 `ms` 毫秒，并按时间顺序逐个处理区间内的定时器到期时刻。每个到期时刻按定时器登记的级别置脏并运行至无脏标记，即该时刻产生一帧（同一时刻的多个到期合并为一帧）。`advance` 本身不推进动画，动画帧只由 `vsync` 产生。
- `vsync n`：推进 `n` 个垂直同步周期，与 03 的 `headless.vsync` 一致，每周期推进假时钟 `1000 / refresh_hz` ms（默认 60 Hz）。周期内到期的定时器按时间顺序处理；周期结束时若有脏标记或活动动画，运行一帧。
- 每条输入指令执行后，回放运行器**必须**驱动主循环直至无脏标记（06 的 REQ-FRAME-054 与 REQ-FRAME-052）。

以上语义使 06 的 AC-FRAME-028 可复现：周期 500 ms 的光标定时器，单条 `advance 5000` 产生 10 帧（每个到期时刻一帧），`frame.count` 增量为 10。

**REQ-TEST-017**　输入指令**必须**经无头平台的注入接口（`headless.inject` 或 `injectMouse*` 等便捷函数）进入，即经 `pumpMessages` 交给 `EventSink`，再由分发阶段路由（08 的 REQ-INPUT-002）；**不得**直接调用控件内部函数修改其状态。

**REQ-TEST-018**　`expect counter` 的取值规则：计数器取自上一次 `mark` 指令以来的增量；计量取求值时的当前值；若脚本中从未执行 `mark`，计数器取绝对值。名字**必须**属于 12 的埋点清单（REQ-PERF-034）或其所属模块文档登记的名字。

**REQ-TEST-019**　回放断言失败时，**必须**输出脚本文件名、行号、期望值与实际值。若该断言所在帧有金图输出，**必须**同时输出该帧的 `actual` 图像路径。

### 3.5 测试辅助设施

**REQ-TEST-020**　测试辅助设施**必须**复用 03 的无头平台（`platform.headless.*`）作为唯一的注入点，**不得**另造时钟、垂直同步、系统设置或输入的替身。测试专用的观测入口为：04 的 `gfx.testing.textRegions()`、05 的 `text.testing.drawLog()`，以及 03 的 `headless.cursorShape`、`headless.presentCount`、`headless.popupRects` 等观测函数。文字后端**不是**运行期注入点，只能在编译期通过 `-Dtext-backend` 选择（02 的 REQ-ARCH-022）。测试代码**不得**调用平台的真实时钟、真实系统度量或真实剪贴板。

**REQ-TEST-021**　随机交互测试**必须**以固定种子生成事件序列。种子值须写在用例中；同一种子**必须**生成完全相同的事件序列。随机交互用例以 AC-FRAME-024 的编号追溯（06）。

**REQ-TEST-022**　幂等校验**必须**只以运行期选项开启（`RunOptions.idempotence`，02 的 REQ-ARCH-022 说明）。开启后，在每个无事件帧额外执行一遍构建函数并比对节点树哈希（ID、结构、布局参数、绘制键）；不一致时**必须**报告首个差异节点的调用点。该模式用于检查 06 的 REQ-FRAME-024。

**REQ-TEST-023**　`-Dforce-rebuild` 与正常模式的结果**必须**比对。测试夹具中以运行期选项 `RunOptions.force_rebuild` 提供等价开关（02 的 REQ-ARCH-022），以便同一测试二进制内对比两种模式。对同一回放脚本，两种模式下全部金图**必须**逐像素相等，全部状态断言**必须**一致。帧统计允许不同，但两种模式下均**必须**满足 06 的 REQ-FRAME-057：被绘制的节点数 ≤ 节点数，复用度量的节点数 ≤ 节点数。不一致即表明存在失效缺陷（06 的 ADR 0006 后果）。

### 3.6 文档一致性检查

**REQ-TEST-024**　`zig build check-docs` **必须**检查下列项目，任一项失败即以非零码退出，并输出文件与行号：
1. 文档内的相对链接均可达。
2. REQ 与 AC 编号唯一、无跳号（废弃条款保留编号）。
3. 每条 REQ 至少被一条 AC 覆盖。
4. 每条 AC 出现在且仅出现在一个里程碑清单中。
5. 控件文档章节齐全（10 的模板章节）。
6. 主题文档中的令牌表格与代码内默认值一致（09 的 REQ-THEME-007 与 REQ-THEME-011）。

**REQ-TEST-025**　每条 AC **必须**至少对应一个自动化测试或一个人工清单项。自动化测试的名字**必须**包含该 AC 的编号（如 `AC-FRAME-024 random interaction 500 steps`），以便追溯。`check-docs` **必须**核对这一对应关系。

### 3.7 人工验收与里程碑

**REQ-TEST-026**　每个里程碑**必须**在 `docs/acceptance/` 下有一份清单，列出该里程碑全部 `[人工]` 与自动化 AC。每个人工项的执行记录**必须**包含：执行人、执行日期、Windows 版本（含内部版本号）、显示缩放、结果（通过 / 不通过 / 阻塞）与备注。

**REQ-TEST-027**　每个里程碑的退出条件是：该里程碑清单内全部 AC 的结果均为通过（路线图见 14）。未通过的 AC **不得**以"后续处理"放行。

### 3.8 持续集成与确定性

**REQ-TEST-028**　CI 的 Linux 作业**必须**运行第 1 至 3 层、`check-docs`，并交叉编译 Windows 目标（`zig build -Dtarget=x86_64-windows-gnu`）。若存在 Windows 测试机，**必须**运行第 1 至 3 层的 Win32 后端版本；若不存在，清单中记录"Windows 测试机缺席"并阻塞里程碑退出（见 OPEN-TEST-02）。

**REQ-TEST-029**　测试**必须**是确定的：结果**不得**依赖真实时钟、系统时区、系统区域设置、环境变量或执行顺序。测试中使用的随机性**必须**来自固定种子（REQ-TEST-021）。同一提交在不同时区与区域设置下运行的结果**必须**相同。

## 4. 接口草案

### 4.1 回放脚本指令表

回放脚本指令表（REQ-TEST-014 的规范内容）。参数中的 `lpx` 为逻辑像素（00 第 7 节）；`VK_*` 为 Win32 虚拟键名，原样书写（如 `VK_TAB`）。每条指令映射到的无头平台或框架接口在"映射"列注明。

| 指令 | 语法 | 语义 | 映射 |
|---|---|---|---|
| `move` | `move x y` 或 `move @调试名` | 鼠标移动到客户区 `(x, y)`（lpx）或节点中心。 | `headless.injectMouseMove` |
| `down` | `down left\|right\|middle` | 按下指定鼠标键。 | `headless.injectMouseButton` |
| `up` | `up left\|right\|middle` | 释放指定鼠标键。 | `headless.injectMouseButton` |
| `wheel` | `wheel dy` | 滚轮滚动 `dy` 格，`dy` 可为小数。符号与 Win32 的 `WHEEL_DELTA` 一致：**正值为向上/远离用户滚动（内容向下移，纵向滚动偏移减小），负值为向下滚动（偏移增大）**。折算为原始增量 `round(dy × 120)`，余数按 03 的 REQ-PLAT-029 累加。 | `headless.injectWheel` |
| `key` | `key down VK_*`、`key up VK_*` 或 `key repeat VK_* [n]` | 按下或释放键盘虚拟键；`repeat` 注入 `n` 个（缺省 1）自动重复的按下（`repeat = true`），须位于同一键的 `down` 之后、`up` 之前。 | `headless.injectKey` |
| `text` | `text "..."` | 输入字符序列（UTF-8）。字符串内支持 `\"`、`\\`、`\n` 与 `\u{十六进制}`。 | `headless.injectText` |
| `ime` | `ime start`；`ime update "<文本>" <光标>`；`ime commit "<文本>"`；`ime cancel` | 输入法组字。`start` 产生 `ime_start`；`update` 产生 `ime_update`，`<光标>` 为文本中的 UTF-8 字节偏移；`commit` 产生 `ime_commit` 后接 `ime_end`；`cancel` 仅产生 `ime_end`，不产生提交。 | `headless.injectIme*` |
| `ole` | `ole enter "路径"...`；`ole over x y`；`ole leave`；`ole drop` | 模拟外部文件拖入：`enter` 携带一个或多个文件路径，`over` 与 `leave` 与 `drop` 对应 03 的 `drag_enter`、`drag_over`、`drag_leave`、`drop`（03 的 3.11 节）。 | `headless.inject` |
| `resize` | `resize w h` | 将客户区设为 `w × h`（lpx）。 | `headless.resize` |
| `show` | `show on\|off` | 设置窗口可见性。 | `headless.setVisible` |
| `activate` | `activate on\|off` | 设置窗口激活状态。 | `headless.setActive` |
| `window` | `window main` 或 `window @调试名` | 把其后指令的目标切换到主窗口，或切换到由该调试名的节点所在的另一个应用窗口/对话框窗口（弹出层不需要切换：指针指令按屏幕位置自动落到弹出根）。 | 选择后续 `headless.*` 调用的 `*Window` |
| `close` | `close` | 向当前目标窗口注入一次关闭请求（等同用户点击标题栏关闭按钮或 Alt+F4）。 | `headless.inject(close_request)` |
| `dpi` | `dpi N` | 设置窗口 DPI（缩放 = N / 96）。 | `headless.setDpi` |
| `setting` | `setting 字段名 值` | 注入系统度量或外观，字段名与 03 的 `SystemMetrics`、`SystemAppearance` 字段名一致（见下表）。 | `headless.setMetrics` / `headless.setAppearance` |
| `invalidate` | `invalidate paint\|layout\|build` 或 `invalidate paint\|layout\|build @调试名` | 调用 `ui.invalidate(level)`（无名字）或 `ui.invalidateNode(id, level)`（有名字）。 | 06 的 `Ui` 失效接口 |
| `model` | `model 名字 值` | 调用测试应用登记的模型修改钩子（见 4.2 节 `ModelHook`）。值为单个字符串或数字字面量。 | 测试应用钩子 |
| `advance` | `advance ms` | 推进假时钟，逐个处理到期的定时器（REQ-TEST-016）。 | `headless.advanceMs` |
| `vsync` | `vsync n` | 推进 `n` 个假垂直同步周期（REQ-TEST-016）。 | `headless.vsync` |
| `mark` | `mark` | 记录全部计数器的基线，供之后的 `expect counter` 取增量。 | — |
| `expect counter` | `expect counter 名字 运算符 值` | 运算符为 `==`、`!=`、`<`、`<=`、`>`、`>=`。计数器取增量，计量取当前值（REQ-TEST-018）。 | `core.stats` |
| `expect golden` | `expect golden 用例路径` | 将当前主根的帧与 `tests/golden/<后端>/<主题>/<缩放>/<用例路径>.png` 比对；`<后端>`、`<主题>`、`<缩放>` 由回放运行选项指定。 | REQ-TEST-008 |
| `expect focus` | `expect focus @调试名` 或 `expect focus none` | 断言焦点节点为指定节点或无焦点。 | 08 的焦点状态 |
| `expect visual` | `expect visual @调试名 hovered\|pressed\|focused_visible\|disabled true\|false` | 断言节点的视觉状态，字段名与 09 的 `theme.Visual` 一致。 | 09 的 `Visual` |
| `expect rect` | `expect rect @调试名 x y w h` | 断言节点的布局矩形（lpx）。比较容差为 1 ppx 折算到 lpx 的值。 | 07 的布局结果 |
| `expect text` | `expect text @调试名 "..."` | 断言节点当前显示的文本（完整字符串，不含省略号处理）。见 OPEN-TEST-05。 | 控件暴露的文本 |
| `expect damage` | `expect damage 运算符 面积` 或 `expect damage 运算符 @调试名` | 断言最近一次执行绘制的帧的损伤面积合计（ppx）；`@调试名` 时面积取该节点绘制范围的面积（ppx）。无绘制帧时面积为 0。 | 06 的损伤计算 |
| `expect cursor` | `expect cursor 形状` | 断言最近一次 `setCursor` 的形状，取值为 03 的 `CursorShape` 成员名。 | `headless.cursorShape` |
| `expect popup` | `expect popup 数量` 或 `expect popup @调试名 存在\|不存在` | 断言当前打开的弹出根数量，或指定节点所在的弹出根是否存在。 | `headless.popupRects` |
| `expect captured` | `expect captured @调试名\|none` | 断言指针捕获的持有者为指定节点或无捕获。 | `headless.captured` 与 08 |
| `expect timers` | `expect timers 数量` | 断言当前登记中的定时器数量（06 的 REQ-FRAME-050）。 | 06 的定时器表 |
| `expect result` | `expect result @调试名 字段 值 [pass 1\|2]` | 断言最近一次执行构建的帧中，该节点的 `Interaction`（08）或控件结果（如 `ButtonResult`）字段值。`pass` 指定构建遍，缺省为最后一遍。字段名示例：`clicked`、`click_count`、`captured`。 | 08 的 `Interaction`、10 的结果结构 |

**`setting` 名字表**（用 03 的字段名本身作为名字，取值按 03 的表示）：

| 名字 | 取值 | 对应字段 |
|---|---|---|
| `double_click_ms` | 整数（ms） | `SystemMetrics.double_click_ms` |
| `double_click_size` | `W H`（ppx） | `SystemMetrics.double_click_size` |
| `drag_size` | `W H`（ppx） | `SystemMetrics.drag_size` |
| `wheel_lines` | 整数，或 `page` | `SystemMetrics.wheel_lines`（`ScrollAmount`） |
| `wheel_chars` | 整数，或 `page` | `SystemMetrics.wheel_chars`（`ScrollAmount`） |
| `menu_show_delay_ms` | 整数（ms） | `SystemMetrics.menu_show_delay_ms` |
| `hover_time_ms` | 整数（ms） | `SystemMetrics.hover_time_ms` |
| `hover_size` | `W H`（ppx） | `SystemMetrics.hover_size` |
| `caret_blink_ms` | 整数（ms），或 `none` 表示不闪烁（取值 `null`） | `SystemMetrics.caret_blink_ms` |
| `key_repeat_delay_ms` | 整数（ms） | `SystemMetrics.key_repeat_delay_ms` |
| `key_repeat_interval_ms` | 整数（ms） | `SystemMetrics.key_repeat_interval_ms` |
| `keyboard_cues` | `on\|off` | `SystemMetrics.keyboard_cues` |
| `client_animation` | `on\|off` | `SystemMetrics.client_animation` |
| `menu_animation` | `on\|off` | `SystemMetrics.menu_animation` |
| `menu_fade` | `on\|off` | `SystemMetrics.menu_fade` |
| `apps_dark` | `on\|off` | `SystemAppearance.apps_dark` |
| `accent` | `#RRGGBB` | `SystemAppearance.accent` |
| `high_contrast` | `on\|off` | `SystemAppearance.high_contrast` |
| `sys_colors` | `<SysColor 成员名> #RRGGBB` | `SystemAppearance.sys_colors` |
| `text_scale` | 小数 | `SystemAppearance.text_scale` |

脚本示例（示意）：

```text
# 点击计数按钮，断言标签、结果与金图
mark
move @计数按钮
down left
up left
advance 50
vsync 2
expect result @计数按钮 clicked true pass 2
expect text @计数标签 "2"
expect counter frame.build_passes >= 1
expect golden widget_gallery/button/hover
```

### 4.2 测试夹具签名

```zig
// 草案：仅签名
// 无头平台的注入点为 03 的 platform.headless.*，本文不另造替身。

pub const ReplayError = error{
    ScriptSyntax,
    DebugNameUnknown,
    DebugNameDuplicate,
    AssertionFailed,
    GoldenMismatch,
    ModelHookUnknown,
    IoFailed,
};

pub const Instruction = union(enum) {
    move: struct { target: Target },
    down: MouseButton,
    up: MouseButton,
    // 其余指令与 4.1 节一一对应，由解析器产生，省略
};

pub const Target = union(enum) {
    point: struct { x: f32, y: f32 },
    debug_name: []const u8,
};

pub const MouseButton = enum { left, right, middle };

pub const RunOptions = struct {
    backend: []const u8 = "glfw",        // 金图后端：win32 或 glfw（REQ-TEST-008）
    theme: []const u8 = "instrument_light",
    scale_pct: u32 = 100,
    idempotence: bool = false,           // REQ-TEST-022
    force_rebuild: bool = false,         // REQ-TEST-023
};

pub const Report = struct { passed: u32, failed: u32 };

pub const Replay = struct {
    pub fn parse(allocator: std.mem.Allocator, src: []const u8) ReplayError![]Instruction;
    pub fn run(allocator: std.mem.Allocator, script: []const Instruction, opts: RunOptions) ReplayError!Report;
};

// 模型修改钩子：测试应用在启动时按名字登记，`model` 指令调用。
pub const ModelHook = *const fn (value: []const u8) ModelHookError!void;
pub const ModelHookError = error{ InvalidValue, ModelRejected };

pub fn registerModelHook(name: []const u8, hook: ModelHook) void;

pub const GoldenError = error{ BaselineMissing, IoFailed };

pub const GoldenResult = struct { equal: bool, diff_pixels: u32 };

// text_regions 为 04 的 gfx.testing.textRegions() 报告的文字区域；其外的像素按非文字区域逐像素比对。
pub fn goldenCompare(
    allocator: std.mem.Allocator,
    actual_rgba: []const u8,
    width: u32,
    height: u32,
    baseline_path: []const u8,
    out_dir: []const u8,
    text_regions: []const core.RectI,
) GoldenError!GoldenResult;

pub const SeededInteraction = struct {
    pub fn init(seed: u64) SeededInteraction;
    pub fn nextEvent(self: *SeededInteraction) InteractionEvent;
};

pub const InteractionEvent = union(enum) {
    move: struct { x: f32, y: f32 },
    click: MouseButton,
    key: u16,
};

pub const IdempotenceReport = struct { same: bool, first_diff_caller: ?[]const u8 };

pub fn idempotenceCheck(ui: *Ui) IdempotenceReport;   // 06
```

## 5. 边界与错误情况

- **金图的容差与文字区域**：非文字区域逐像素相等；文字区域的界定与容差由 04 的 REQ-GFX-040 规定，本文不另设。
- **金图的缩放**：金图用例的缩放只取 `s100`、`s125`、`s150`、`s175`、`s200` 之一。非整数像素的边框在 125% 缩放下的表现由 09 的 REQ-THEME-012 决定，金图据此比对。
- **回放中的弹出层**：`expect golden` 与 `expect rect` 默认以主根为对象；对弹出根断言时，调试名须指向弹出层内的节点。
- **回放中的超时**：回放运行器**不得**以真实时间超时终止；若一个脚本运行中主循环连续 1000 次未取得进展（无脏标记、无时间推进、无输入），判定为失败并输出最近一次的状态。
- **幂等校验与性能**：幂等校验模式的额外构建不计入任何性能预算（12 的 REQ-PERF-009）。
- **随机交互的失败复现**：失败时输出种子与失败的步号，同一种子与步号必须可复现。
- **`ime update` 光标单位**：以组字串内的 UTF-8 字节偏移计，与 03 的 `ime_update.cursor` 一致。

## 6. 验收标准

**AC-TEST-001**　`[单元]` 覆盖：REQ-TEST-002、REQ-TEST-006。前置条件：Linux 环境，无显示服务（未设置 `DISPLAY`）。步骤：运行 `zig build test`（默认 `fixed` 后端）；在 `fixed` 后端下以 `ppx_size = 16` 测量字符串 "Hello 你好" 两次。预期：退出码为 0；未尝试打开窗口或创建 GL 上下文；`text.backend_name` 为 `"fixed"`；字素簇为 8 个，前进宽度均为 `round(0.5 × 16) = 8` ppx，总宽 64 ppx；ascent 为 16 ppx，descent 为 4 ppx，行距为 20 ppx；两次测量结果逐字段相等。

**AC-TEST-002**　`[单元]` 覆盖：REQ-TEST-001。步骤：检查 `build.zig` 中的步骤名。预期：存在 `test`、`test-golden`、`test-replay`、`check-docs`、`bench` 五个步骤，且每个步骤可单独执行。

**AC-TEST-003**　`[金图]` 覆盖：REQ-TEST-003、REQ-TEST-007。前置条件：Linux，Mesa 固定版本，测试用例为一个 80×24 lpx 的凸起矩形（主题 `instrument_light`，缩放 100%）。步骤：运行 `zig build test-golden`；再将基准 PNG 的一个非文字像素改为相邻值后再次运行。预期：第一次运行逐像素相等，退出码为 0；第二次运行失败，退出码非零，并输出 `actual.png` 与 `diff.png`，差异位置为被改动的像素。

**AC-TEST-004**　`[回放]` 覆盖：REQ-TEST-004。前置条件：一份仅含 `expect` 与 `vsync` 指令的回放脚本，断言计数器与金图。步骤：运行 `zig build test-replay`；将其中一条期望值改为错误值后再运行。预期：第一次全部断言通过、退出码为 0；第二次该断言失败，退出码非零，其他断言仍被执行。

**AC-TEST-005**　`[单元]` 覆盖：REQ-TEST-008。步骤：遍历 `tests/golden/` 下的全部 PNG 文件路径。预期：每个路径均符合 `<后端>/<主题>/<缩放>/<用例>.png`；后端仅取 `win32` 或 `glfw`；主题与用例段匹配 `^[a-z0-9_]+$`（用例段允许 `/` 分层）；缩放段匹配 `^s[0-9]+$`；同一用例在同一后端、主题、缩放下只有一个文件。

**AC-TEST-006**　`[金图]` 覆盖：REQ-TEST-009。前置条件：一个用例同时包含非文字矩形与一段文字。步骤：（a）在非文字区域改动 1 个像素的 RGB 值，运行比对；（b）以 `win32` 后端渲染，检查比对所用的基准路径。预期：（a）失败，报告的差异像素位于非文字区域；（b）比对使用 `win32` 分支的基准，不使用 `glfw` 分支的基准；文字区域的界定与容差与 04 的 REQ-GFX-040 一致（由 `goldenCompare` 收到的 `text_regions` 参数验证）。

**AC-TEST-007**　`[金图]` 覆盖：REQ-TEST-010。步骤：使金图比对失败，检查输出目录；检查基准文件的修改时间与内容；检查 `.gitignore`。预期：输出目录中同时存在 `<用例>.actual.png` 与 `<用例>.diff.png`；基准文件未被修改；`.gitignore` 包含 `*.actual.png` 与 `*.diff.png`，两类文件的 `git status` 中不出现。

**AC-TEST-008**　`[单元]` 覆盖：REQ-TEST-011。前置条件：仓库历史。步骤：对每个修改了 `tests/golden/` 的提交，检查其修改的文件集合与提交说明。预期：该提交仅改动 `tests/golden/` 下的文件；说明中含"基准"或"golden"字样，并给出原因（非空，不少于 10 个字符）。

**AC-TEST-009**　`[单元]` 覆盖：REQ-TEST-012。步骤：读取 CI 配置中的 Mesa 版本字段；查看 CI 日志。预期：配置中存在固定的版本号（非 `latest`）；日志中输出的实际版本与配置一致。

**AC-TEST-010**　`[回放]` 覆盖：REQ-TEST-013。步骤：执行三份脚本：（a）含空行、以 `#` 开头的注释行与字符串内含 `#` 的指令的脚本；（b）第 7 行为 `move`（缺参数）；（c）含非法 UTF-8 字节。预期：（a）正常执行，字符串内的 `#` 被保留；（b）解析失败，报告为第 7 行，退出码非零；（c）解析失败，退出码非零。

**AC-TEST-011**　`[回放]` 覆盖：REQ-TEST-014。步骤：对 4.1 节的每一条指令各写一个最小脚本执行；对 `setting` 的每个名字各执行一次并读取对应的 `SystemMetrics` 或 `SystemAppearance` 字段；再执行一条未知指令（如 `tap`）。预期：全部指令解析并执行成功；`setting` 的名字与 03 的字段名逐个一致，`caret_blink_ms none` 使字段为 `null`；未知指令解析失败并报告行号。

**AC-TEST-012**　`[回放]` 覆盖：REQ-TEST-015。前置条件：界面含调试名为 `保存按钮` 的按钮。步骤：（a）`move @保存按钮` 后 `expect focus` 与 `expect visual @保存按钮 hovered true`；（b）`move @不存在`；（c）同一构建遍中两个节点使用同名调试名。预期：（a）通过；（b）失败，错误为 `DebugNameUnknown`；（c）失败，错误为 `DebugNameDuplicate`，报告两处调用点。

**AC-TEST-013**　`[回放]` 覆盖：REQ-TEST-016。前置条件：一个 200 ms 的颜色过渡动画；一个周期 500 ms 的光标定时器（用例 2）。步骤：（1）`advance` 10000 ms 而不执行 `vsync`，记录墙上时间，读取动画值；随后 `vsync 1`，再读取动画值；（2）聚焦一个文本框，`advance 5000`，读取 `frame.count` 的增量。预期：（1）`advance` 后动画值为起点，墙上时间不超过 1 秒；`vsync` 后动画值为终点；（2）增量为 10。

**AC-TEST-014**　`[回放]` 覆盖：REQ-TEST-017。步骤：执行 `down left`，在无头平台的注入入口处记录事件，并在分发阶段记录目标节点。预期：事件经 `headless.inject` 注入、经 `pumpMessages` 交给 `EventSink`（记录可见），并由分发阶段路由到节点（分发日志可见）；控件内部状态的修改只发生在分发与构建之后。

**AC-TEST-015**　`[回放]` 覆盖：REQ-TEST-018、REQ-TEST-019。步骤：`mark` 后执行一次按钮点击，`expect counter frame.count == 1`；再执行一条错误断言 `expect counter frame.count == 5`；再以 `expect counter` 读取一个计量（如 `alloc.arena.bytes`）并与 `core.stats` 的当前值比较。预期：第一条通过（增量为 1）；第二条失败，输出脚本文件名、行号、期望值 5 与实际值 1，若该帧有金图则同时输出 `actual` 路径；计量取值与当前值一致。

**AC-TEST-016**　`[单元]` 覆盖：REQ-TEST-020。步骤：（a）在最小用例中替换无头平台的假时钟、假垂直同步、注入的系统设置，并确认结果随之变化；（b）静态扫描测试代码，检查其中不存在对平台真实时钟、真实系统度量与真实剪贴板的直接调用；（c）检查 `RunOptions` 与运行期接口中不存在文字后端的选择项。预期：（a）替身生效；（b）扫描结果为零命中；（c）文字后端仅由构建选项 `-Dtext-backend` 决定。

**AC-TEST-017**　`[金图]` 覆盖：REQ-TEST-021。前置条件：固定种子值写在用例中。步骤：运行名为 `AC-FRAME-024` 的随机交互用例（500 步，每步后比较局部重绘与整根重绘）。预期：500 步全部逐像素一致；两次运行生成的事件序列完全相同。

**AC-TEST-018**　`[单元]` 覆盖：REQ-TEST-022。步骤：对 G（控件总览）以 `RunOptions.idempotence = true` 运行全部回放脚本；另运行一个在构建中自增计数的反例。预期：G 的全部脚本零差异报告；反例报告指出该标签节点与其调用点。

**AC-TEST-019**　`[金图]` 覆盖：REQ-TEST-023。步骤：对同一回放脚本分别以 `RunOptions.force_rebuild = false` 与 `true` 运行，比对全部金图与状态断言，并检查两种模式下 06 的 REQ-FRAME-057 的两条约束；再以一个故意遗漏绘制键的控件重复一次。预期：正常用例下两种模式的金图逐像素相等、断言一致、约束成立；故意缺陷用例下两种模式的金图不一致，测试报告失效缺陷。

**AC-TEST-020**　`[单元]` 覆盖：REQ-TEST-024。步骤：（a）在干净仓库运行 `zig build check-docs`；（b）分别植入六类缺陷（断链、重复 REQ、未覆盖 REQ、AC 出现在两个清单、控件章节缺失、令牌表与默认值不一致），各运行一次。预期：（a）退出码为 0；（b）每类缺陷均使退出码非零，并输出含文件与行号的错误信息。

**AC-TEST-021**　`[单元]` 覆盖：REQ-TEST-025。步骤：列出所有 AC 编号；扫描全部测试名与人工清单项。预期：每条 AC 至少对应一个测试名（含其编号）或一个人工清单项；无测试名引用不存在的 AC 编号。

**AC-TEST-022**　`[单元]` 覆盖：REQ-TEST-026。步骤：检查每个里程碑清单。预期：清单文件位于 `docs/acceptance/`；每个 `[人工]` AC 均有一项；每个人工项含执行人、日期、Windows 版本、缩放、结果、备注六个字段。

**AC-TEST-023**　`[人工]` 覆盖：REQ-TEST-005。前置条件：真实 Windows 10 1809 或 Windows 11 机器，缩放 100%。步骤：按里程碑清单执行任一 `[人工]` 项，记录结果。预期：人工项按清单操作完成并记录结果；未经人工操作的 `[人工]` 项不计为通过。

**AC-TEST-024**　`[单元]` 覆盖：REQ-TEST-027。前置条件：某里程碑的全部自动化与人工清单结果。步骤：统计该里程碑清单内各 AC 的结果。预期：全部为"通过"时该里程碑标记为可退出；存在"不通过"或"阻塞"时不得标记为可退出。

**AC-TEST-025**　`[单元]` 覆盖：REQ-TEST-028。步骤：检查 CI 配置。预期：Linux 作业包含第 1 至 3 层、`check-docs` 与 Windows 交叉编译步骤；若存在 Windows 作业，其包含第 1 至 3 层的 Win32 后端版本。

**AC-TEST-026**　`[单元]` 覆盖：REQ-TEST-029。步骤：在两个不同时区、两种区域设置与打乱的执行顺序下各运行一次 `zig build test` 与 `zig build test-replay`；检查测试代码中是否存在对系统随机源与真实时钟的直接调用。预期：两次运行结果一致；测试代码中不存在未经注入的系统时钟与未带固定种子的随机源调用。

## 7. 待定问题

| 编号 | 问题 | 影响 | 当前倾向 |
|---|---|---|---|
| OPEN-TEST-01 | （已解决）幂等校验与 `force_rebuild` 的开关形式已由 02 的 REQ-ARCH-022 确定：构建选项 `-Dforce-rebuild`，测试夹具中以运行期选项等价提供；幂等校验只以运行期选项提供。 | REQ-TEST-022、REQ-TEST-023 | 已解决。 |
| OPEN-TEST-02 | Windows 测试机的可用时间点未定。缺席时 REQ-TEST-028 的 Win32 版本无法运行，里程碑退出受阻。 | 里程碑退出 | 由主代理在 M0 前确认测试机资源。 |
| OPEN-TEST-03 | CI 使用的 Mesa 固定版本号尚未选定。 | REQ-TEST-012 | 在 M1 开始金图测试前选定并写入 CI 配置。 |
| OPEN-TEST-04 | 金图用例清单（"控件总览"的各状态矩阵）尚未定义，依赖 10 与示例应用。 | AC-TEST-003、AC-TEST-017 | 随控件规范与示例应用一并确定。 |
| OPEN-TEST-05 | `expect text` 依赖控件暴露"当前显示文本"的接口，该接口未在 06、08 或 10 中定义。 | 4.1 节 `expect text` | 在 10 的控件通用接口中补充，或以调试节点的字符串属性替代。 |
| OPEN-TEST-06 | （已解决）`ime update` 的光标单位。 | 4.1 节 `ime` | UTF-8 字节偏移，与 03 的 `ime_update.cursor` 一致（03 的文本位置一律为 UTF-8 字节偏移）。 |
| OPEN-TEST-07 | （已解决）容器节点的调试名。 | REQ-TEST-015 | 07 的 `ContainerOptions` 已补充 `debug_name`。 |
