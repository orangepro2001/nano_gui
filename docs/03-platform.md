# 03 平台层

## 1. 范围

定义 `platform` 模块的全部对外能力：进程初始化、窗口、消息循环与唤醒、事件、时钟、系统度量与外观、鼠标指针、剪贴板、输入法、通用对话框、OLE 拖放、托盘、显示器、弹出窗口、GL 上下文、致命错误、UI Automation 入口，以及 Win32 后端的实现细则与 GLFW 后端的降级矩阵。依据 ADR 0004、ADR 0008，并实现 REQ-FRAME-052、REQ-FRAME-055 对平台层提出的要求。

接口以 Win32 的能力为基准；GLFW 后端去适配它（ADR 0004）。窗口内的事件路由、焦点、命中测试见 08；帧调度见 06；GL 绘制见 04；文字与输入法组字的绘制见 05。

## 2. 术语

| 术语 | 定义 |
|---|---|
| 窗口 (`Window`) | 平台层的一个顶层原生窗口，含其 GL 上下文。弹出窗口也是 `Window`，带 `popup` 属性。 |
| 事件 (`Event`) | 平台层产出的、与后端无关的输入或系统通知记录。坐标为所属窗口客户区的物理像素。 |
| 事件汇 (`EventSink`) | 上层提供的、接收平台事件的回调。 |
| 帧回调 | 上层注册、由平台层在系统要求同步出帧时调用的函数（3.3）。 |
| 系统度量 (`SystemMetrics`) | 操作系统提供的、影响交互行为的参数集合（双击时间、拖拽阈值、滚轮行数等）。 |
| 系统外观 (`SystemAppearance`) | 操作系统提供的、影响视觉的参数集合（深浅色、强调色、高对比度颜色、消息字体等）。 |
| 弹出会话 | 从第一个非提示类弹出窗口打开，到最后一个关闭之间的时段。会话期间宿主窗口持有鼠标捕获（3.14）。 |
| 嵌套模态循环 | 由系统调用（对话框、`DoDragDrop`）或系统行为（拖边框、系统菜单）在内部运行的消息循环。 |
| 无头模式 | 无真实显示输出、时钟与垂直同步可注入、事件可注入的运行方式（3.19）。 |

## 3. 规范条款

### 3.1 后端与进程初始化

**REQ-PLAT-001**　`platform` 的公共接口**必须**是编译期解析到具体后端（`win32` 或 `glfw`）的命名空间（REQ-ARCH-004）。本文第 4 节的签名对两个后端同样成立；GLFW 后端无法实现的函数**必须**返回 `error.Unsupported` 或按降级矩阵（3.18）退化，**不得**在编译期缺失。

**REQ-PLAT-002**　`platform.init` **必须**在创建任何窗口之前调用，且只能调用一次。Win32 后端的初始化内容：`OleInitialize`（单线程单元，STA）；初始化通用控件库（comctl32 v6，由清单激活）；注册窗口类；创建一个临时窗口以加载 WGL 扩展函数（`wglCreateContextAttribsARB`、`wglChoosePixelFormatARB`、`wglSwapIntervalEXT`）后销毁；创建唤醒事件对象（REQ-PLAT-019）。任一步失败**必须**走 `platform.fatal` 并给出失败步骤的名称与 `GetLastError` 值。

**REQ-PLAT-003**　可执行文件的应用程序清单**必须**声明：`PerMonitorV2` DPI 感知、comctl32 v6 依赖、Windows 10 兼容性 GUID（使 `GetVersionEx` 类查询返回真实版本）。运行时不依赖 `SetProcessDpiAwarenessContext` 作为主要手段；仅当检测到清单缺失（如测试宿主）时才调用它并记录一条 `warn` 日志。

**REQ-PLAT-004**　最低支持系统为 Windows 10 版本 1809（REQ-VIS-002）。`platform.init` **必须**检测系统版本，低于 1809 时走 `platform.fatal`，消息写明所需版本。因系统版本而异的行为集中列于 3.17，实现**不得**在别处散布版本分支。

**REQ-PLAT-005**　所有 Win32 调用**必须**使用宽字符（`W`）版本；UTF-8 与 UTF-16 的转换只发生在 `platform` 内部（REQ-ARCH-016）。转换缓冲取自帧竞技场或栈；路径长度超过 260 个 UTF-16 单元时**必须**使用 `\\?\` 前缀或返回 `error.PathTooLong`（二选一，由具体调用点在 3.10 说明）。

### 3.2 窗口

**REQ-PLAT-006**　`platform.createWindow(opts)` 创建顶层窗口，选项**必须**包含：标题、初始客户区尺寸（lpx）、初始位置（屏幕物理像素，可为"系统默认"）、是否可调整大小、最小客户区尺寸（lpx）、owner（可空）、初始显示状态（普通/最大化/最小化/隐藏）。返回的 `*Window` 由调用方持有，`destroyWindow` 释放。

**REQ-PLAT-007**　窗口类**不得**设置背景刷，**不得**设置 `CS_HREDRAW`、`CS_VREDRAW`，**不得**设置 `CS_DBLCLKS`；`WM_ERASEBKGND` **必须**返回 1 且不做任何绘制。双击由 input 模块依据 `SystemMetrics`（3.7）自行判定，使两个后端行为一致。

**REQ-PLAT-008**　顶层应用窗口**必须**使用系统标题栏与系统边框，**不得**自绘非客户区、**不得**拦截 `WM_NCCALCSIZE` 以扩展客户区（ADR 0008）。系统菜单（Alt+Space）、贴靠布局、最大化/还原动画由系统提供，框架不干预。

**REQ-PLAT-009**　窗口标题栏的深浅**必须**与应用当前生效的深浅模式（REQ-THEME-010）同步，通过 DWM 属性 `DWMWA_USE_IMMERSIVE_DARK_MODE` 设置。接口为 `Window.setDarkTitleBar(bool)`。在系统不接受该属性时（见 3.17）调用返回 `error.Unsupported`，上层忽略即可。窗口创建后、首次显示前**必须**设置一次，以避免首帧标题栏闪白。

**REQ-PLAT-010**　每个窗口有独立的 `scale = DPI / 96`，`DPI` 来自 `GetDpiForWindow`。窗口创建时尺寸换算使用目标位置所在显示器的 DPI（`AdjustWindowRectExForDpi`）。`Window.scale()` 返回当前值；弹出窗口使用其所在显示器的 DPI（REQ-PLAT-072）。

**REQ-PLAT-011**　收到 `WM_DPICHANGED` 时，平台层**必须**用消息参数给出的系统建议矩形调用 `SetWindowPos` 重设窗口位置与大小，然后产出 `dpi_changed` 事件（含新 DPI 与 scale）。窗口在跨越不同 DPI 显示器的拖动过程中，每次 DPI 变化产出一次事件；不得缓存旧 scale。`dpi_changed` 之后立即到达的 `resized` 事件中的尺寸**必须**是新 DPI 下的物理像素。

**REQ-PLAT-012**　`Window` 属性接口**必须**至少包括：`setTitle`、`setClientSize`（lpx）、`setPosition`（屏幕 ppx）、`show/hide/minimize/maximize/restore`、`setMinClientSize`（lpx）、`setIcon`、`setCursor`（3.5）、`setDarkTitleBar`、`requestAttention`（任务栏闪烁）、`bringToFront`。所有尺寸入参为 lpx，返回的客户区尺寸为 ppx，换算由平台层按该窗口当前 scale 完成。

**REQ-PLAT-013**　最小尺寸**必须**通过 `WM_GETMINMAXINFO` 实现：最小客户区尺寸（lpx）× 当前 scale，经 `AdjustWindowRectExForDpi` 加上非客户区后写入 `ptMinTrackSize`。DPI 变化后重新换算。

**REQ-PLAT-014**　窗口位置持久化：`Window.getPlacement() WindowPlacement` 与 `platform.createWindow` 的 `NativeWindowOptions.placement` 选项（基于 `GetWindowPlacement`/`SetWindowPlacement`）。`WindowPlacement` 含正常状态矩形（`normal_rect`，虚拟屏幕物理像素 ppx）、显示状态、保存时窗口所在显示器的 DPI（`dpi`）。**恢复校验规则以本条为唯一定义**，上层（11）只存取该结构并调用 `platform.validatePlacement(p: WindowPlacement) WindowPlacement`，**不得**自行实现校验。`validatePlacement` 的规则：
1. 正常状态矩形与某显示器工作区的交集面积不小于该矩形面积的 25%，且标题栏（矩形顶部 `SM_CYCAPTION` 高的条带）的至少 `SM_CXSIZE` 宽一段位于某工作区内；
2. 满足则保持位置；若保存时的 `dpi` 与该位置所在显示器当前 DPI 不同，则尺寸按 lpx 不变换算：`size_ppx' = round(size_ppx × 当前 DPI / 保存的 dpi)`，位置左上角保持，并钳制到所在工作区尺寸内；
3. 不满足则丢弃位置，使用系统默认位置并保持换算后的尺寸（同样不超过目标工作区）；显示状态保持；
4. 返回的 `WindowPlacement.dpi` 为校验后所在显示器的 DPI。

**REQ-PLAT-015**　关闭请求（点击关闭按钮、Alt+F4、系统菜单"关闭"）**必须**产出 `close_requested` 事件而**不得**直接销毁窗口。上层通过 `Window.confirmClose()` 或 `Window.cancelClose()` 响应；平台层仅在 `confirmClose` 后调用 `DestroyWindow`。`WM_QUERYENDSESSION` **必须**产出 `session_ending` 事件（含 `logoff` 标志）并由上层在同一轮事件处理内通过 `platform.allowSessionEnd(bool)` 回答；未回答视为允许。上层（11 的 REQ-APP-044）把 `session_ending` 转换为各窗口的关闭请求流程，并在该流程结论确定后调用 `allowSessionEnd`。`WM_ENDSESSION` 为真时平台层**必须**先产出 `session_ended` 事件再返回，供应用同步保存设置。

**REQ-PLAT-016**　窗口销毁顺序：销毁窗口前**必须**先销毁以它为 owner 的全部弹出窗口；再释放其 GL 上下文（3.15）；`RevokeDragDrop`（3.11）；最后 `DestroyWindow`。销毁后该 `*Window` 不得再使用，其后到达的属于它的消息被丢弃。

**REQ-PLAT-017**　窗口最小化、完全被遮挡或不可见时，平台层**必须**通过 `visibility` 事件通知上层（`visible: bool`），并使 `Window.canPresent()` 返回假；此时 `present` 不得被调用（REQ-GFX-019）。判定使用 `IsIconic` 与 DWM 的遮蔽通知（`WM_SIZE` 的 `SIZE_MINIMIZED`、`WM_SHOWWINDOW`；遮挡检测的具体机制见 7 章 PLAT-OPEN-04）。

### 3.3 消息循环与唤醒

**REQ-PLAT-018**　平台层**必须**把 REQ-FRAME-052 的主循环拆成两个原语，由 `app` 组装：
- `platform.pumpMessages(sink) usize`：以 `PeekMessage(PM_REMOVE)` 循环取出并派发队列中的全部消息直至取空，返回处理的消息数；
- `platform.waitMessages(timeout_ms: ?u32) WaitResult`：以 `MsgWaitForMultipleObjectsEx` 阻塞，句柄集含唤醒事件，标志含 `MWMO_INPUTAVAILABLE`，唤醒条件含 `QS_ALLINPUT`；`null` 表示无限期。返回 `.message`、`.woken`、`.timeout`。

阻塞等待期间进程**不得**消耗可测量的 CPU 时间（REQ-FRAME-053）。

**REQ-PLAT-019**　`platform.wake()` **必须**线程安全，实现为对一个自动复位的事件对象调用 `SetEvent`，而不是向窗口 `PostMessage`（避免系统消息队列的上限与丢失）。重复的 `wake` 允许合并。`wake` 返回后，界面线程的 `waitMessages` 最迟在下一次调度内返回 `.woken`。

**REQ-PLAT-020**　`app.post` 的唤醒路径**必须**为：闭包入无锁队列（REQ-ARCH-010）→ `platform.wake()`。平台层不拥有回投队列，只提供唤醒；队列关闭语义见 02。

**REQ-PLAT-021**　`waitMessages` 的超时参数以毫秒计，实现**必须**向上取整，保证不早于所请求的时刻返回超过 1 ms，且不晚于所请求时刻加一个系统计时器粒度。动画期间的"等待下一个垂直同步"**必须**实现为 `waitMessages(period_ms)`，`period_ms = ceil(1000 / 窗口所在显示器刷新率)`；刷新率取自 `Monitor.refresh_hz`（3.13），取不到时按 60 Hz。当一帧通过 `present` 的垂直同步阻塞已经对齐了节奏（REQ-GFX-018）时，主循环**可以**直接进入下一轮而不再等待。

**REQ-PLAT-022**　系统嵌套模态循环（拖动边框缩放/移动、系统菜单、拖放、模态对话框）期间，应用的主循环不运行，平台层**必须**在窗口过程内部驱动帧：
1. 注册 `platform.setFrameCallback(window, cb)`，`cb(window, reason)` 由上层提供，执行该窗口一帧（含收集、分发、构建、布局、绘制、提交）；`reason` 取 `.size`、`.paint`、`.timer`、`.nested_modal`。
2. `WM_SIZE` 与 `WM_PAINT` 内**必须**同步调用帧回调，并在回调返回（含 `present`）后才返回窗口过程。
3. `WM_ENTERSIZEMOVE` 与 `WM_ENTERMENULOOP`（系统菜单）起**必须**用 `SetTimer` 建立周期计时器，周期不大于 `ceil(1000 / 刷新率)`，`WM_TIMER` 内调用帧回调（`.timer`），此时上层按 REQ-FRAME-048、REQ-FRAME-050 推进动画与定时器；`WM_EXITSIZEMOVE` 与 `WM_EXITMENULOOP` 起 `KillTimer`。
4. 回调中的帧**必须**是普通帧（阶段规则不变，REQ-FRAME-055）。

**REQ-PLAT-023**　拖动边框缩放时内容**必须**实时跟随、不出现黑边或未初始化区域：窗口过程在 `WM_SIZE` 内同步完成"重分配渲染目标（REQ-GFX-006）→ 布局 → 整窗绘制 → 提交"之后才返回；`WM_ERASEBKGND` 返回 1（REQ-PLAT-007）；窗口类无背景刷，因此系统不会用背景色填充新增区域。

**REQ-PLAT-024**　`WM_PAINT` 的无效区**必须**映射为 `repaint` 事件（`rect: RectI`，客户区 ppx），上层据此置 `paint` 级损伤（REQ-FRAME-037"系统要求重绘"一行）。实现：`BeginPaint`/`EndPaint` 取 `rcPaint` 后立即验证（不使用其 HDC 绘制）。呈现范围以 04 为准：由于渲染目标是持久离屏缓冲（REQ-GFX-004），系统要求重绘时把渲染目标的**整个客户区**拷到后缓冲并提交（REQ-GFX-005），**不得**只拷贝无效区；仅当渲染目标内容不可用时才提升为整窗损伤（REQ-FRAME-044）。`WM_PAINT` 内的同步帧与 REQ-PLAT-022 共用同一回调。

**REQ-PLAT-025**　嵌套模态循环由对话框或 `DoDragDrop` 产生时（`reason = .nested_modal`），帧回调**仅**允许因 `WM_PAINT`、`WM_SIZE`、`WM_DPICHANGED` 与 `WM_TIMER`（动画/定时器）而被调用；输入事件在此期间不得被分发到被禁用的 owner 窗口。由于此类嵌套循环由帧后动作启动（REQ-FRAME-027），`ui` **必须**保证在启动前帧已完全收尾（帧状态已清除、帧竞技场已重置），使嵌套帧不构成对"帧"的重入。

### 3.4 事件

**REQ-PLAT-026**　`Event` 是一个带标签联合，所有事件含 `window: *Window` 与 `time_ms: u64`（平台单调时钟，REQ-PLAT-044）。事件类型封闭集合如下，任何新增须同步修改本表：

| 事件 | 载荷 | Win32 来源 |
|---|---|---|
| `mouse_move` | `pos: Vec2i`（客户区 ppx）、`mods` | `WM_MOUSEMOVE` |
| `mouse_button` | `button`、`down: bool`、`pos`、`mods` | `WM_{L,R,M,X}BUTTON{DOWN,UP}` |
| `mouse_leave` | — | `WM_MOUSELEAVE` |
| `capture_lost` | — | `WM_CAPTURECHANGED` |
| `wheel` | `axis: .vertical/.horizontal`、`raw: i32`、`steps: i32`、`pos`、`mods` | `WM_MOUSEWHEEL`、`WM_MOUSEHWHEEL` |
| `key` | `vk: VirtualKey`、`scancode: u16`、`down: bool`、`repeat: bool`、`mods`、`extended: bool` | `WM_KEYDOWN/UP`、`WM_SYSKEYDOWN/UP` |
| `text` | `utf8: []const u8`（帧竞技场） | `WM_CHAR` |
| `ime_start` / `ime_update` / `ime_commit` / `ime_end` | 见 3.9 | `WM_IME_*` |
| `focus` | `gained: bool` | `WM_SETFOCUS`、`WM_KILLFOCUS` |
| `activate` | `active: bool`、`by_click: bool` | `WM_ACTIVATE` |
| `resized` | `client: Size2i`（ppx）、`state: .normal/.minimized/.maximized` | `WM_SIZE` |
| `moved` | `pos: Vec2i`（屏幕 ppx） | `WM_MOVE` |
| `dpi_changed` | `dpi: u32`、`scale: f32` | `WM_DPICHANGED` |
| `repaint` | `rect: RectI` | `WM_PAINT` |
| `visibility` | `visible: bool` | 见 REQ-PLAT-017 |
| `close_requested` | — | `WM_CLOSE` |
| `session_ending` / `session_ended` | `logoff: bool` | `WM_QUERYENDSESSION`、`WM_ENDSESSION` |
| `system_changed` | `what: SettingsChanged`（位集） | 见 REQ-PLAT-045 |
| `drag_enter` / `drag_over` / `drag_leave` / `drop` | 见 3.11 | `IDropTarget` |
| `tray` | `id`、`kind` | 托盘回调消息 |
| `popup_dismiss` | `reason` | 见 3.14 |
| `power_resume` | — | `WM_POWERBROADCAST`（`PBT_APMRESUMEAUTOMATIC`、`PBT_APMRESUMESUSPEND`） |

事件在 `pumpMessages` 内同步交给 `EventSink`，上层把它们排入本轮收集阶段的事件列表（REQ-FRAME-020）。事件载荷中的切片只在该次 `sink` 调用内有效，上层须复制。

**REQ-PLAT-027**　鼠标按键事件**必须**区分左、右、中、X1、X2 五个键。按下事件**必须**在窗口尚未持有捕获时由平台层自动 `SetCapture`，全部按键释放后自动 `ReleaseCapture`，使拖动出窗口仍能收到释放事件；除此之外上层可用 `Window.setCapture(bool)` 显式捕获（拖拽、滚动条、弹出会话）。捕获被系统夺走时（`WM_CAPTURECHANGED`）产出 `capture_lost`。

**REQ-PLAT-028**　`mouse_leave` **必须**通过 `TrackMouseEvent(TME_LEAVE)` 实现。每次鼠标进入窗口后的第一个 `WM_MOUSEMOVE` 重新武装一次（离开消息触发后追踪即失效）。鼠标被捕获期间离开客户区**不**产出 `mouse_leave`，改在捕获释放后若指针在窗口外时补发。

**REQ-PLAT-029**　滚轮事件**必须**累积余数以支持高精度滚轮：平台层对每个窗口、每个轴各维护一个累加器，累加 `WHEEL_DELTA` 单位的原始增量；`raw` 为本消息的**未取整**原始增量（单位 1/120 格，高精度设备可小于 120，不经累加器处理），`steps` 为累加器每满 `WHEEL_DELTA`（120）产生的整数格数（向零取整，余数保留）。"格"的浮点值 = `raw / 120.0`；按 `wheel_lines`/`wheel_chars`（含整页）把格数换算为滚动量由 08 完成。滚动方向反转时累加器清零。上层对平滑滚动使用 `raw / 120.0`，对离散步进（列表项移动）使用 `steps`。行数/字符数的换算使用 `SystemMetrics.wheel_lines/wheel_chars`（REQ-PLAT-047），不在平台层内完成。

**REQ-PLAT-030**　触摸与笔**仅**依赖系统将其提升为鼠标消息。平台层**不得**调用 `RegisterTouchWindow`、**不得**处理 `WM_TOUCH`、`WM_POINTER*`、`WM_GESTURE`（VIS 非目标）。

**REQ-PLAT-031**　键盘事件**必须**由 `WM_KEYDOWN`/`WM_SYSKEYDOWN`（`down = true`）与 `WM_KEYUP`/`WM_SYSKEYUP`（`down = false`）产生，给出虚拟键码、扫描码、扩展键标志、自动重复标志（`lParam` 第 30 位）与修饰键状态 `mods`（`shift`、`ctrl`、`alt`、`win`、`altgr` 五位，经 `GetKeyState` 在消息时刻读取）。`platform.VirtualKey` 是键码的**唯一定义**（08 引用它，不另设键码枚举），框架自有枚举，覆盖：字母 `a`–`z`、数字 `n0`–`n9`、功能键 `f1`–`f24`、导航键（方向、`home`、`end`、`page_up`、`page_down`）、编辑键（`insert`、`delete`、`backspace`、`tab`、`enter`、`escape`、`space`）、小键盘（`np0`–`np9`、`np_add/sub/mul/div/decimal`、`np_enter`）、锁定键（`caps_lock`、`num_lock`、`scroll_lock`）、`print_screen`、`pause`、`apps`（菜单键）、OEM 键（`oem_1`–`oem_8`、`oem_plus/comma/minus/period`、`oem_102`）、浏览器与媒体键，值与 Win32 `VK_*` 一一对应。**修饰键成员区分左右**：`lshift`、`rshift`、`lctrl`、`rctrl`、`lalt`、`ralt`、`lwin`、`rwin`（Win32 的 `VK_SHIFT/VK_CONTROL/VK_MENU` 由扫描码与扩展键位经 `MapVirtualKey(MAPVK_VSC_TO_VK_EX)` 区分左右）；`mods` 中的四位不区分左右。`mods.altgr` 在右 Alt 按下、且系统为 AltGr 键盘布局而合成了左 Ctrl（扫描码 0x21D 的伪 Ctrl 消息）时为真，此时 `mods.ctrl` 与 `mods.alt` **置为假**（合成的 Ctrl 不外露，避免快捷键误判）；判定细节见 PLAT-OPEN-12。GLFW 后端的键码按 `glfw` 键码映射到同一枚举。`VK_PROCESSKEY`（输入法处理中）的按键事件**不得**交给上层。键盘自动重复由系统产生，框架**不得**自行合成重复。

**REQ-PLAT-032**　文本事件**必须**由 `WM_CHAR` 产生，不使用 `WM_KEYDOWN` 推断字符。UTF-16 代理对（高代理项消息后紧随低代理项消息）**必须**合并后转为一个 UTF-8 码点序列；孤立的代理项丢弃并记录一次 `debug` 日志。控制字符（U+0000–U+001F、U+007F）**不得**产生 `text` 事件（Tab、Enter、Backspace 由 `key` 事件承载）。`WM_DEADCHAR` 忽略，组合结果由其后的 `WM_CHAR` 给出。`WM_SYSCHAR` **必须**被吞掉（不交 `DefWindowProc`），防止系统"叮"声。

**REQ-PLAT-033**　Alt 与 F10 的处理**必须**为：
- Alt 单击（`lalt`/`ralt` 按下后释放且期间无其他键）与 F10（`f10`）产生 `key` 事件并**被吞掉**，不进入系统菜单模式（本框架不使用 `HMENU` 菜单栏，菜单由上层自绘）；
- Alt+Space（系统菜单）、Alt+F4（关闭）、Alt+Tab 等系统组合**必须**交给 `DefWindowProc`；
- 其余 Alt+键 组合产生 `key` 事件，并**不**交给 `DefWindowProc`（避免"叮"声）；
- 平台层不得调用任何会触发"无匹配助记符"提示音的默认处理。

**REQ-PLAT-034**　`focus` 事件反映键盘焦点（`WM_SETFOCUS`/`WM_KILLFOCUS`），`activate` 事件反映窗口激活状态（`WM_ACTIVATE`，`by_click` 取自 `WA_CLICKACTIVE`）。弹出窗口的打开与关闭**不得**导致宿主产生 `activate{active=false}` 或 `focus{gained=false}`（REQ-PLAT-067）。

**REQ-PLAT-035**　`system_changed` 事件的产生与合并规则见 REQ-PLAT-045；`resized` 事件在窗口最小化时 `client` 为 0×0 且 `state = .minimized`，上层据此不构建、不绘制（06 第 5 节）。

### 3.5 鼠标指针

**REQ-PLAT-036**　`Window.setCursor(shape: CursorShape)` 设置当前窗口客户区的指针形状。`platform.CursorShape` 是指针形状的**唯一定义**（08 引用它），取值：`arrow`、`ibeam`、`hand`、`cross`、`size_we`、`size_ns`、`size_nwse`、`size_nesw`、`size_all`、`not_allowed`、`wait`、`progress`（后台忙碌，箭头加沙漏）、`hidden`。Win32 后端**必须**在 `WM_SETCURSOR`（命中测试码为 `HTCLIENT`）中应用该形状，其他命中码交 `DefWindowProc`，使边框缩放指针保持系统行为。形状选择规则见 REQ-THEME-032 与 08。

**REQ-PLAT-037**　指针形状使用系统共享指针（`LoadCursor` 加 `IDC_*`），不创建自定义位图指针（如需见 PLAT-OPEN-07）。`setCursor` 被重复调用同一值时**不得**产生系统调用。"键入时隐藏"由**平台层**负责：系统设置 `SPI_GETMOUSEVANISH` 为真时，平台层在产出 `text` 事件后隐藏指针，鼠标移动（`WM_MOUSEMOVE` 且坐标变化）或失去焦点时恢复；上层不需要处理。`hidden` 形状仍可由上层显式设置（如全屏播放），由上层负责恢复。

### 3.6 单调时钟

**REQ-PLAT-038**　`platform.nowMs() u64` 返回单调时钟，毫秒，起点任意；Win32 后端用 `QueryPerformanceCounter`，不使用 `GetTickCount`。`core` 与上层**不得**直接读取任何其他时钟（REQ-ARCH-002，REQ-FRAME-025）。

**REQ-PLAT-039**　时钟**必须**可注入：`platform.setClock(clock: ?*const Clock)`，`Clock` 为 `{ ctx: *anyopaque, now_ms: *const fn (*anyopaque) u64 }`。注入后 `nowMs` 返回注入值，`waitMessages` 的超时按注入时钟折算（无头模式下直接返回，见 3.19）。该接口只允许在无头模式或测试构建中使用；发布构建的 Win32 后端调用它返回 `error.Unsupported`。

### 3.7 系统度量与外观

**REQ-PLAT-040**　`SystemMetrics` 与 `SystemAppearance` 的值**必须**在 `platform.init` 时读取一次并缓存；此后仅在收到 `system_changed` 事件后重读受影响的部分。帧内读取（`platform.metrics()`、`platform.appearance()`）返回缓存，**不得**产生系统调用。读取按**窗口所在 DPI** 解释的值（拖拽阈值、消息字体）时使用 `GetSystemMetricsForDpi`/`SystemParametersInfoForDpi`，故接口为 `metrics(window)` 与 `appearance(window)`（见 PLAT-OPEN-02）。

**REQ-PLAT-041**　`SystemMetrics` **必须**包含下表全部字段及对应来源（Win32 后端的读取方式，字段取值为已换算的框架单位）：

| 字段 | 单位 | Win32 来源 | 说明 |
|---|---|---|---|
| `double_click_ms` | ms | `GetDoubleClickTime` | 双击最大间隔 |
| `double_click_size` | `Size2i` ppx | `GetSystemMetricsForDpi(SM_CXDOUBLECLK / SM_CYDOUBLECLK)` | 以第一次点击点为中心的矩形的宽高；第二次点击落在该矩形内且时间差 ≤ `double_click_ms` 才算双击 |
| `drag_size` | `Size2i` ppx | `GetSystemMetricsForDpi(SM_CXDRAG / SM_CYDRAG)` | 以按下点为中心的矩形的宽高；指针移出该矩形才开始拖拽 |
| `wheel_lines` | `ScrollAmount` | `SPI_GETWHEELSCROLLLINES` | 滚轮一格滚动的行数；取值为系统常量 `WHEEL_PAGESCROLL` 时为 `.page`（滚动一页）；0 表示禁用滚动 |
| `wheel_chars` | `ScrollAmount` | `SPI_GETWHEELSCROLLCHARS` | 水平滚轮一格的字符数，同上 |
| `menu_show_delay_ms` | ms | `SPI_GETMENUSHOWDELAY` | 子菜单展开延迟（ADR 0008） |
| `hover_time_ms` | ms | `SPI_GETMOUSEHOVERTIME` | 悬停多久触发提示等"悬停"行为 |
| `hover_size` | `Size2i` ppx | `SPI_GETMOUSEHOVERWIDTH` / `SPI_GETMOUSEHOVERHEIGHT` | 悬停计时期间允许的指针抖动矩形 |
| `caret_blink_ms` | `?u32` ms | `GetCaretBlinkTime` | 返回系统的"无限"取值（`INFINITE`）时为 `null`，表示不闪烁（REQ-FRAME-051） |
| `key_repeat_delay_ms` | `u32` ms | `SPI_GETKEYBOARDDELAY`（0–3 档，换算为约 250/500/750/1000 ms） | 按住连发类控件（滚动条槽、微调箭头）的首次重复延迟 |
| `key_repeat_interval_ms` | `u32` ms | `SPI_GETKEYBOARDSPEED`（0–31 档，线性换算为约 400 ms 至 33 ms） | 按住连发的重复间隔；精确换算表待实机确认 |
| `keyboard_cues` | bool | `SPI_GETKEYBOARDCUES` | 假：助记符下划线与焦点环默认隐藏，Alt/Tab 按下后才显示；真：始终显示 |
| `client_animation` | bool | `SPI_GETCLIENTAREAANIMATION` | 假则 `animate` 直接返回目标（REQ-FRAME-047） |
| `menu_animation` | bool | `SPI_GETMENUANIMATION` | 菜单/提示出现的动画开关 |
| `menu_fade` | bool | `SPI_GETMENUFADE` | 真：淡入淡出；假：滑动（仅当 `menu_animation` 为真时有意义）；框架只使用淡入 |

`ScrollAmount` 为 `union(enum) { lines: u32, page }`。上层把一格滚轮换算为滚动量时**必须**使用这些字段，不得写死 3 行。

**REQ-PLAT-042**　`SystemAppearance` **必须**包含：

| 字段 | Win32 来源 | 说明 |
|---|---|---|
| `apps_dark` | 注册表 `HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize` 的 `AppsUseLightTheme`（0 = 深色） | 值缺失视为浅色（REQ-THEME-010） |
| `accent` | `DwmGetColorizationColor`，丢弃 alpha | 系统强调色（REQ-THEME-009） |
| `high_contrast` | `SPI_GETHIGHCONTRAST`，`HCF_HIGHCONTRASTON` 位 | REQ-THEME-035 |
| `sys_colors` | `GetSysColor` 对 `SysColor` 枚举每一项取值 | 至少含 `window`、`window_text`、`btn_face`、`btn_text`、`gray_text`、`highlight`、`highlight_text`、`hotlight`，与 09 的高对比度映射表所用的 `COLOR_*` 全集一致 |
| `message_font` | `SystemParametersInfoForDpi(SPI_GETNONCLIENTMETRICS)` 的 `lfMessageFont` | 见 REQ-PLAT-043 |
| `text_scale` | 注册表 `HKCU\Software\Microsoft\Accessibility\TextScaleFactor`（DWORD 百分数），缺失为 1.0 | 系统"文本大小"辅助功能；来源待实机确认（PLAT-OPEN-03） |
| `metrics` | 内嵌 `SystemMetrics` | 方便 `Theme.default` 一处取全 |

**REQ-PLAT-043**　`message_font` 的结构为 `{ family: []const u8, size_lpx: f32, weight: u16, italic: bool }`。`size_lpx` = `abs(lfHeight) × 96 / 取值所用的 DPI`（`lfHeight` 为负时是字符高度，为正时是单元高度，后者须先用字体度量换算为字符高度）。字族名转 UTF-8。该值是 REQ-THEME-015、REQ-THEME-016 的基准字号 B 的来源；05 的默认字体取此值。

**REQ-PLAT-044**　`keyboard_cues` 为假时，上层**必须**默认隐藏助记符下划线与键盘焦点环，直到收到一次 Alt 键事件（`key` 事件 `vk` 为 `lalt` 或 `ralt`）或 Tab/方向键导航事件后才显示，并在该窗口失去激活时重新隐藏；为真时始终显示。平台层只报告该值，不做显示控制。

**REQ-PLAT-045**　系统设置变化**必须**通过 `system_changed` 事件通知上层，`what` 为 `SettingsChanged` 位集：`appearance`（深浅色、强调色、系统颜色、高对比度）、`metrics`（3.7 全部度量）、`font`（消息字体、文本大小）、`display`（显示器增减、分辨率、工作区）、`locale`（界面语言/区域设置，来源 `WM_SETTINGCHANGE` 的 `"intl"` 字符串与 `WM_INPUTLANGCHANGE`；具体消息待实机确认，PLAT-OPEN-13）。Win32 来源：`WM_SETTINGCHANGE`（按 `wParam` 的 `SPI_*` 值与 `lParam` 字符串，含 `"ImmersiveColorSet"` 对应 `appearance`）、`WM_SYSCOLORCHANGE`、`WM_THEMECHANGED`、`WM_DWMCOLORIZATIONCOLORCHANGED`、`WM_FONTCHANGE`、`WM_DISPLAYCHANGE`。无法判定具体类别时置全部位。同一轮消息内的多个通知合并为一个事件（位或）。事件产出前缓存已重读完毕。

**REQ-PLAT-046**　`system_changed` 事件到达后上层的处理顺序由 06 规定（REQ-FRAME-037："DPI 变化、主题/强调色/高对比度变化、字体设置变化"置 `build` 并清缓存）。平台层**必须**保证：在事件被投递给上层之前，`metrics()`/`appearance()` 已返回新值。

**REQ-PLAT-047**　`SystemMetrics.wheel_lines` 取 `.page` 时，滚动量 = 可视区高度减去一行（或 1 个行高的重叠，由 08/控件规范定义）；取 `lines(0)` 时滚轮不滚动。该换算由上层完成，平台层只忠实报告。

### 3.8 剪贴板

**REQ-PLAT-048**　`platform.clipboard` **必须**支持文本的读写：`getText(allocator) !?[]u8` 与 `setText(utf8) !void`，格式 `CF_UNICODETEXT`。内部文本统一使用 `\n` 换行；写入时把 `\n` 转为 `\r\n`，读取时把 `\r\n` 与孤立 `\r` 转为 `\n`。读取到的非法 UTF-16（孤立代理项）替换为 U+FFFD。

**REQ-PLAT-049**　`OpenClipboard` 失败（被其他进程占用）时**必须**有限重试：最多 5 次，每次失败后睡眠 10 ms（总计不超过约 50 ms），仍失败返回 `error.ClipboardBusy`。重试在界面线程同步进行；该上限写入常量，不得无限循环。`setText` 必须在 `OpenClipboard` 后 `EmptyClipboard`，并以 `SetClipboardData` 转移全局内存所有权；失败时释放该内存。

**REQ-PLAT-050**　剪贴板**必须**预留自定义格式接口：`registerFormat(name) !FormatId`（`RegisterClipboardFormat`）、`getData(format, allocator) !?[]u8`、`setData(format, bytes) !void`，并允许 `setText` 与 `setData` 在同一次写入中组合（`setMany(items)`）。`hasText() bool` 通过 `IsClipboardFormatAvailable` 实现，不打开剪贴板，供"粘贴"命令的可用状态查询。`sequenceNumber() u32`（`GetClipboardSequenceNumber`）供上层判断内容是否变化。

### 3.9 输入法（IMM32）

**REQ-PLAT-051**　M4 的输入法支持**必须**采用 IMM32。窗口过程处理 `WM_IME_STARTCOMPOSITION`、`WM_IME_COMPOSITION`、`WM_IME_ENDCOMPOSITION`、`WM_IME_SETCONTEXT`、`WM_IME_NOTIFY`。组字串由框架在文本控件内联绘制（见 05 的组字绘制条款），候选窗由系统绘制（ADR 0008）。`WM_IME_STARTCOMPOSITION` 与 `WM_IME_COMPOSITION` **不得**交给 `DefWindowProc`（否则系统会绘制自己的组字窗口，且结果串以 `WM_CHAR` 到达造成重复）；`WM_IME_SETCONTEXT` 的 `lParam` 清除 `ISC_SHOWUICOMPOSITIONWINDOW` 位后再交 `DefWindowProc`，使候选窗仍由系统显示。

**REQ-PLAT-052**　`WM_IME_COMPOSITION` 到达时，平台层按 `lParam` 标志读取 `ImmGetCompositionString`：
- `GCS_COMPSTR`：当前组字串（UTF-16 → UTF-8）；
- `GCS_COMPATTR`：每个 UTF-16 单元的属性（`ATTR_INPUT`、`ATTR_TARGET_CONVERTED`、`ATTR_CONVERTED`、`ATTR_TARGET_NOTCONVERTED`、`ATTR_INPUT_ERROR`、`ATTR_FIXEDCONVERTED`），**必须**转为按 UTF-8 字节范围划分的 `ImeSegment { start, end, style }` 序列，`style` 取 `unconverted / converted / target_converted / target_unconverted / error`；
- `GCS_CURSORPOS`：组字串内的光标位置（UTF-16 单元 → UTF-8 字节偏移，且落在字素簇边界）；
- `GCS_RESULTSTR`：确认结果串。

含 `GCS_RESULTSTR` 时先产出 `ime_commit{text}`，再（若同一消息含 `GCS_COMPSTR`）产出 `ime_update`。`WM_IME_STARTCOMPOSITION` 产出 `ime_start`，`WM_IME_ENDCOMPOSITION` 产出 `ime_end`（`ime_end` 是组字状态结束的唯一标志，提交后与取消后都发出）。`ime_update` 载荷为 `{ text: []const u8, cursor: usize, segments: []const ImeSegment }`。

**REQ-PLAT-053**　`Window.setImeCaretRect(caret: RectI, exclude: ?RectI)` 报告当前文本光标在客户区的矩形（ppx）与可选的排除矩形（目标转换子句的矩形，ppx，候选窗不得遮挡它）。坐标由框架（08）统一从 lpx 换算为 ppx 后传入，**平台层不再做任何换算**。Win32 后端**必须**据此调用 `ImmSetCompositionWindow`（`CFS_POINT`，光标矩形左下附近）与 `ImmSetCandidateWindow`（`CFS_EXCLUDE`，排除区为 `exclude`，缺省时取光标矩形所在行，使候选窗出现在其下方且不遮挡组字串）。上层**必须**在每次光标位置、滚动位置、窗口位置、DPI 变化后，且在组字期间的每次 `ime_update` 之后重新报告。

**REQ-PLAT-054**　`Window.setImeEnabled(enabled: bool)` 控制当前是否接受输入法：`false` 时调用 `ImmAssociateContext(hwnd, null)` 解除关联（并保存原输入上下文），`true` 时恢复。上层**必须**在键盘焦点落在非文本控件时设为 `false`，落在文本编辑控件时设为 `true`。`Window.commitComposition()` 以 `ImmNotifyIME(NI_COMPOSITIONSTR, CPS_COMPLETE)` 确认当前组字串（产出 `ime_commit`，随后 `ime_end`）。`setImeEnabled(false)` 之前若处于组字状态，上层**会先调用 `commitComposition`**；平台层自行"取消"（`CPS_CANCEL`，产出 `ime_end` 而无 `ime_commit`）只发生在强制结束的情形：窗口销毁、失去激活或焦点、捕获丢失（REQ-PLAT-055），以及系统自行取消。组字状态的结束**只**以 `ime_end` 为标志：它在提交之后与取消之后都会发出，每次 `ime_start` 恰对应一次 `ime_end`。

**REQ-PLAT-055**　组字期间，窗口失去焦点或收到 `capture_lost`，平台层**必须**取消组字（`CPS_CANCEL`）并产出 `ime_end`（不产生 `ime_commit`），保证上层的组字状态不残留。重新转换（`IMR_RECONVERTSTRING`）、`IMR_DOCUMENTFEED` 与 TSF 不在 M4 范围，见 PLAT-OPEN-05。

### 3.10 通用对话框与消息框

**REQ-PLAT-056**　`platform.dialogs` **必须**提供下列原生对话框，全部为阻塞调用，只能在帧后动作中调用（REQ-FRAME-027），调试构建在构建函数内调用即断言中止：

| 函数 | Win32 实现 | 返回 |
|---|---|---|
| `openFile(owner, opts) !?[]Path` | `IFileOpenDialog` | 所选路径（可多选）；取消为 `null` |
| `saveFile(owner, opts) !?Path` | `IFileSaveDialog` | 所选路径；取消为 `null` |
| `pickFolder(owner, opts) !?Path` | `IFileOpenDialog` + `FOS_PICKFOLDERS` | 所选文件夹 |
| `pickColor(owner, initial) !?Color` | `ChooseColor` | 所选颜色 |
| `pickFont(owner, initial) !?FontChoice` | `ChooseFont` | 所选字族、字号、字重、斜体（`FontChoice` 在本文第 4 节定义；转换为 `text.Style` 由 11 负责） |
| `taskDialog(owner, opts) !TaskResult` | `TaskDialogIndirect` | 按下的按钮、复选框状态 |

`opts`（`FileDialogOptions`、`TaskDialogOptions` 等，类型全部在本文第 4 节定义）含标题、初始目录、文件类型过滤（`FileFilter`：显示名 + 模式列表）、默认扩展名。函数名固定为 `platform.dialogs.openFile/saveFile/pickFolder/pickColor/pickFont/taskDialog`。取消不是错误。路径为 UTF-8。

**REQ-PLAT-057**　上述对话框的 `owner` 不为空时，系统自动禁用 owner 并在对话框关闭后恢复其启用与激活。对话框运行期间本进程的**其他**窗口与 owner 自身**必须**仍能重绘与响应缩放（REQ-PLAT-025）。对话框返回后，平台层**必须**重置所有鼠标按键与捕获的内部状态，并向上层产出一次 `mouse_leave`，避免按键状态卡死。

**REQ-PLAT-058**　`taskDialog` 依赖通用控件库 v6，清单未声明（REQ-PLAT-003）时 `platform.init` 的自检失败。`platform.messageBox(owner, title, text, kind) MessageResult` 是系统消息框的简单封装（`MessageBoxW`，`kind` ∈ `info/warning/error/question` × `ok/ok_cancel/yes_no/yes_no_cancel`），可在帧后动作和任何非构建上下文中调用，并**必须**能在 `platform.init` 之前、窗口不存在时使用。

**REQ-PLAT-059**　`platform.fatal(title, text) noreturn` **必须**用 `platform.messageBox` 的错误形态显示消息（不依赖 `ui`、`gfx`、`text` 任何模块），然后以退出码 1 结束进程。调试构建同时写 `core.log` 的 `err` 与 `OutputDebugString`。`fatal` 在任意线程可调用（REQ-ARCH-017）。

### 3.11 OLE 拖放

**REQ-PLAT-060**　每个顶层应用窗口（非弹出窗口）**必须**在创建后 `RegisterDragDrop` 一个 `IDropTarget` 实现，销毁前 `RevokeDragDrop`。目标接受两类数据：文件列表（`CF_HDROP`）与文本（`CF_UNICODETEXT`）。事件为 `drag_enter{formats, pos, effects_allowed}`、`drag_over{pos, mods}`、`drag_leave`、`drop{data: DropData, pos}`；`pos` 为客户区 ppx（由屏幕坐标换算）。

**REQ-PLAT-061**　`IDropTarget::DragOver` 必须同步返回 `DROPEFFECT`，而事件在帧内异步处理，因此平台层**必须**采用"上一决定"模型：上层通过 `Window.setDropEffect(effect: DropEffect)` 设置当前可接受的效果（`none/copy/move/link`），平台层在 `DragEnter`/`DragOver` 中返回最近一次设置的值（`drag_enter` 事件产出前的初值为 `none`，上层在处理 `drag_enter` 的同一帧内即可设置，之后的 `DragOver` 生效）。`Drop` 返回的效果同理。

**REQ-PLAT-062**　`drop` 事件的数据（路径列表、文本）**必须**在 `IDropTarget::Drop` 返回之前从 `IDataObject` 复制到帧竞技场之外的由事件持有的缓冲（`DropData` 持有分配器参数、由上层在处理后 `deinit`），`IDataObject` 的引用不得在 `Drop` 返回后使用。文件路径为 UTF-8，数量上限 10 000，超出部分丢弃并记录 `warn`。

**REQ-PLAT-063**　`platform.startDrag(window, data: DragData, allowed: DropEffects) !DropEffect` 以 `DoDragDrop` 实现拖出源，阻塞到拖放结束，返回最终效果（含 `none` 表示取消）。`DragData` 支持文件路径列表（`CF_HDROP`，路径须存在）与文本。只能在帧后动作中调用（REQ-FRAME-027）。拖动期间的指针形状由系统（`IDropSource::GiveFeedback` 默认行为）提供；Esc 取消与鼠标释放由系统判定。

### 3.12 托盘

**REQ-PLAT-064**　`platform.tray` **必须**用 `Shell_NotifyIcon` 提供：添加（`NIM_ADD`）、修改图标与提示（`NIM_MODIFY`）、删除（`NIM_DELETE`）、气泡通知（`NIF_INFO`，含标题、正文、图标类别）。图标由 RGBA 位图创建 `HICON`，随 scale 提供 16/20/24/32 ppx 之一（按系统托盘图标度量 `SM_CXSMICON` 选取）。回调消息使用 `NOTIFYICON_VERSION_4` 语义，产出 `tray{id, kind}`，`kind` ∈ `click / double_click / context_menu / balloon_clicked`。`context_menu` 事件携带屏幕坐标，应用以弹出窗口显示菜单（REQ-PLAT-067）；显示前**必须**先 `SetForegroundWindow` 宿主窗口以保证菜单外点击能关闭。

**REQ-PLAT-065**　平台层**必须**用 `RegisterWindowMessage("TaskbarCreated")` 监听资源管理器重启，收到后对所有已登记的托盘图标重新 `NIM_ADD`。应用退出（或 `session_ended`）前**必须**删除全部托盘图标，不得残留幽灵图标。

### 3.13 显示器

**REQ-PLAT-066**　`platform.monitors()` 返回全部显示器的 `Monitor`：`{ handle, bounds: RectI, work_area: RectI, dpi: u32, scale: f32, refresh_hz: u32, primary: bool }`，全部坐标为虚拟屏幕物理像素（PerMonitorV2 下 `GetMonitorInfo`、`GetCursorPos` 均为物理像素）。另提供 `monitorFromPoint(p)`（`MonitorFromPoint`，默认最近）与 `monitorFromWindow(w)`。`dpi` 取 `GetDpiForMonitor(MDT_EFFECTIVE_DPI)`；`refresh_hz` 取 `EnumDisplaySettings` 的当前模式，取不到时为 60。显示器配置变化时产出 `system_changed{display}`。

### 3.14 弹出窗口

**REQ-PLAT-067**　`platform.createPopup(owner, spec: PopupWindowSpec)` 创建弹出窗口（ADR 0008）：`WS_POPUP`，扩展样式 `WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE`，owner 为宿主窗口，无标题栏与边框。`PopupWindowSpec` 含屏幕矩形（物理像素）、`kind: PopupWindowKind`（`menu` / `dropdown` / `tooltip`）、`shadow: bool`。框架层 `input.PopupSpec.kind` 到 `PopupWindowKind` 的映射：`menu`、`context_menu` → `menu`；`dropdown`、`autocomplete` → `dropdown`；`tooltip` → `tooltip`。显示用 `SW_SHOWNOACTIVATE`/`SWP_NOACTIVATE`，创建与显示的任何阶段**不得**激活该窗口或使宿主失去激活。每个弹出窗口有自己的 GL 上下文（REQ-PLAT-076）。

**REQ-PLAT-068**　`WM_MOUSEACTIVATE` 在弹出窗口上**必须**返回 `MA_NOACTIVATE`。键盘焦点**始终**留在宿主窗口：弹出窗口不接收 `WM_KEYDOWN`/`WM_CHAR`；宿主收到的键盘与文本事件由 input 模块路由到弹出根（08）。提示类（`tooltip`）弹出窗口对 `WM_NCHITTEST` 返回 `HTTRANSPARENT`，使鼠标穿透、不抢占悬停。

**REQ-PLAT-069**　弹出会话期间（至少有一个 `menu` 或 `dropdown` 类弹出窗口存在），宿主窗口**必须**持有鼠标捕获（`SetCapture`）。此时所有鼠标事件到达宿主窗口过程，平台层将其转为带 `screen_pos`（屏幕 ppx）的 `mouse_move`/`mouse_button`/`wheel` 事件，附 `via_popup_capture = true`，由 input 模块依据各根的屏幕矩形做命中测试并路由到宿主根或某弹出根。只有落在**本进程全部窗口之外**（桌面、其他应用的窗口）的点击，才由平台层产出 `popup_dismiss{reason = .outside_click}`，且该次点击**不得**转发给被点击的窗口。落在宿主窗口（或本进程其他窗口）内、但在弹出窗口之外的点击，平台层照常以 `via_popup_capture = true` 的鼠标事件交给上层，由 08 判定是否关闭，并在关闭后**继续投递**给宿主根命中的节点（仅锚点控件的例外由 08 规定为吞掉）。

**REQ-PLAT-070**　除本进程窗口之外的点击外（REQ-PLAT-069），平台层**必须**在下列情形产出 `popup_dismiss`（框架层 `input.DismissReason` 包含这些成员并另加 `escape`、`host_destroyed`、`dialog_opened`、`programmatic`，与之一一映射），`reason` 如括号所示：宿主窗口失去激活（`WM_ACTIVATE` 为 `WA_INACTIVE` 或 `WM_ACTIVATEAPP` 为假；`deactivated`）；宿主被移动或开始移动（`WM_MOVING`、`WM_ENTERSIZEMOVE` 且为移动；`host_moved`）；宿主客户区尺寸变化（`WM_SIZE` 尺寸变化或缩放开始；`host_resized`）；宿主最小化或隐藏（`host_hidden`）；系统取消模式（`WM_CANCELMODE`；`cancel_mode`）；捕获被其他窗口夺走（`WM_CAPTURECHANGED` 且新捕获窗口不属于本会话；`capture_lost`）；DPI 变化（`dpi_changed`）。平台层只负责通知，关闭动作由上层执行；`tooltip` 类不参与会话捕获，但同样随上述事件被通知关闭。

**REQ-PLAT-071**　弹出窗口的外观：Windows 10 上其窗口类设置 `CS_DROPSHADOW`（`shadow = true` 时）；Windows 11 上不使用 `CS_DROPSHADOW`，改用 DWM 属性 `DWMWA_WINDOW_CORNER_PREFERENCE` 请求小圆角（`DWMWCP_ROUNDSMALL`），其阴影由 DWM 提供。两种系统的判定见 3.17。弹出窗口的客户区由框架填满（REQ-THEME-025），不绘制自己的阴影与圆角。

**REQ-PLAT-072**　弹出窗口的定位坐标为屏幕物理像素。上层**必须**用 `monitorFromPoint` 取得锚点所在显示器的工作区（`work_area`）做越界翻转与裁剪（翻转规则见控件规范）；平台层**不得**自动移动弹出窗口。弹出窗口的 DPI 与 scale 取其**最终所在**显示器：若创建矩形所在显示器的 DPI 不同于宿主，上层在创建后读取 `Window.scale()`，按该 scale 重新布局并调用 `setPopupRect` 调整一次；该调整**不得**产生可见的中间状态（窗口在布局完成前保持隐藏）。

**REQ-PLAT-073**　弹出窗口的生命周期：`destroyPopup(w)` 销毁窗口并释放其 GL 上下文；宿主销毁时先销毁其全部弹出窗口（REQ-PLAT-016）。平台层**可以**缓存最多 1 个已隐藏的弹出窗口以加速反复打开；缓存窗口不得持有鼠标捕获或可见内容。弹出窗口的出现动画由上层以 `paint` 级动画实现（REQ-FRAME-046），平台层**不得**使用 `AnimateWindow`。

**REQ-PLAT-074**　`createPopup` 的 owner 必须是已创建的非弹出窗口或另一弹出窗口（子菜单的 owner 为其父菜单窗口的宿主链顶端宿主）。子菜单的 owner 链**必须**统一指向最顶层宿主窗口，使其 Z 序高于宿主、低于任何置顶的系统窗口。

### 3.15 OpenGL 上下文

**REQ-PLAT-075**　Win32 后端**必须**使用 `wglChoosePixelFormatARB` 选择像素格式：硬件加速、支持窗口、支持 OpenGL、双缓冲、RGBA 每通道 8 位、8 位模板缓冲，不要求深度缓冲，不启用多重采样（REQ-GFX-012），不请求 sRGB 帧缓冲（REQ-GFX-009）。上下文通过 `wglCreateContextAttribsARB` 创建 OpenGL 3.3 Core Profile（ADR 0002）。

**REQ-PLAT-076**　每个顶层窗口（含弹出窗口）各有一个 WGL 上下文；除第一个窗口外，新上下文创建时**必须**与已有上下文共享对象（`wglShareLists`，或 `wglCreateContextAttribsARB` 的 `hShareContext` 参数），使纹理、着色器与缓冲跨窗口共用（REQ-GFX-028）。帧缓冲对象（FBO）与顶点数组对象**不**跨上下文共享，每个窗口自建。

**REQ-PLAT-077**　`Window.makeCurrent()` 将该窗口的上下文设为当前线程的当前上下文；`Window.swapBuffers()` 调用 `SwapBuffers`；`Window.setSwapInterval(n)` 调用 `wglSwapIntervalEXT`。窗口创建时交换间隔**必须**设为 1（垂直同步）。同一时刻每线程至多一个当前上下文，平台层在切换窗口绘制前负责 `makeCurrent`。

**REQ-PLAT-078**　GL 上下文或像素格式创建失败（无硬件加速驱动、远程桌面仅提供 GL 1.1、请求的版本不可用）属于不可恢复错误，**必须**走 `platform.fatal`，消息**必须**包含：失败步骤（选择像素格式 / 创建上下文 / 加载函数）、请求的版本（3.3 Core）、`glGetString(GL_RENDERER)` 与 `GL_VERSION`（若已能取得）、`GetLastError` 值，以及一句建议（更新显卡驱动或避免在无 GPU 的远程会话中运行）。

**REQ-PLAT-079**　上下文丢失（驱动重置，`glGetGraphicsResetStatus` 非零，或 `SwapBuffers` 失败且 `GetLastError` 指示）**必须**产出 `render_lost` 通知（作为 `repaint` 的特例，`rect` 为整窗），使 gfx 重建 FBO 与全部 GL 资源并整窗重绘（REQ-FRAME-044）。无法恢复时走 `platform.fatal`。

### 3.16 UI Automation 入口

**REQ-PLAT-080**　Win32 后端**必须**在窗口过程中处理 `WM_GETOBJECT`（`lParam` 为 `UiaRootObjectId`）：向上层请求该窗口的无障碍根节点，若上层未提供（M6 之前）则交给 `DefWindowProc`。实现排在 M6；M6 之前 `platform.uia.isEnabled()` 返回假且 `WM_GETOBJECT` 无副作用。接口为 `platform.uia.setProvider(window, provider: *const UiaProvider)`，`UiaProvider` 由 `ui` 提供，不在本文展开。

**REQ-PLAT-081**　节点到 UIA 的映射采用统一表格式：控件规范在各自的"无障碍"一节填写 `{ UIA 控件类型, 受支持模式, 名称来源, 值来源 }`。本文只固定下表的**框架**，具体控件由 10 填写：

| 控件类别（示例） | UIA 控件类型 | 典型模式 |
|---|---|---|
| 按钮 | `UIA_ButtonControlTypeId` | Invoke（切换类另加 Toggle） |
| 文本输入 | `UIA_EditControlTypeId` | Value、Text |
| 列表/列表项 | `UIA_ListControlTypeId` / `UIA_ListItemControlTypeId` | Selection、SelectionItem、ScrollItem |
| 树/树项 | `UIA_TreeControlTypeId` / `UIA_TreeItemControlTypeId` | ExpandCollapse、SelectionItem |
| 表格 | `UIA_TableControlTypeId` / `UIA_DataGridControlTypeId` | Grid、Table |
| 菜单/菜单项 | `UIA_MenuControlTypeId` / `UIA_MenuItemControlTypeId` | Invoke、ExpandCollapse |

表中类型常量名在 M6 实现时以 SDK 为准核对（PLAT-OPEN-06）。节点未声明角色时按"自定义"（`UIA_CustomControlTypeId`）处理并在调试构建警告。

### 3.17 Win32 版本差异

**REQ-PLAT-082**　因系统版本而异的行为**必须**集中于 `platform.compat` 的一个查询表，初始化时填充，其余代码只读该表：

| 行为 | Windows 10 1809 – 21H2 | Windows 11 |
|---|---|---|
| 弹出窗口圆角与阴影 | 直角；`CS_DROPSHADOW` 提供阴影 | `DWMWA_WINDOW_CORNER_PREFERENCE = DWMWCP_ROUNDSMALL`；阴影由 DWM 提供 |
| 深色标题栏属性 | `DWMWA_USE_IMMERSIVE_DARK_MODE` 的属性编号在 1809 与 2004 之后可能不同，须按编号逐个尝试 | 同左（以 Windows 11 的编号为准） |
| 顶层窗口圆角 | 无 | 系统自动 |
| 窗口边框色/标题栏色属性 | 不可用 | `DWMWA_BORDER_COLOR`、`DWMWA_CAPTION_COLOR`（可选使用，默认不设置） |
| 文本大小辅助功能 | 1809 起提供 | 提供 |

`compat` 通过 `RtlGetVersion` 或属性设置的返回值判定，并在 `platform.init` 以 `debug` 日志输出判定结果。DWM 属性设置失败**不得**视为错误，返回 `error.Unsupported` 由调用者忽略。

### 3.18 GLFW 降级矩阵

**REQ-PLAT-083**　GLFW 后端**必须**按下表实现。"完整"表示行为与 Win32 后端一致；"退化"表示按所述行为实现；"不支持"表示函数返回 `error.Unsupported`（或事件永不产生），上层**不得**因此分叉业务逻辑——应用代码应把 `error.Unsupported` 当作"该系统无此能力"处理。

| 能力 | Win32 | GLFW | 退化 / 不支持行为 |
|---|---|---|---|
| 进程初始化 | 完整 | 完整 | `glfwInit`；无 OLE |
| 窗口创建/属性/最小尺寸 | 完整 | 完整 | `glfwSetWindowSizeLimits` |
| 每窗口 scale、`dpi_changed` | 完整（PerMonitorV2） | 退化 | 取 `glfwGetWindowContentScale`；窗口跨显示器时产出 `dpi_changed`，无系统建议矩形，窗口物理尺寸按内容缩放比保持 lpx 尺寸不变 |
| 深色标题栏 `setDarkTitleBar` | 完整 | 不支持 | |
| 窗口位置持久化 | 完整 | 退化 | 仅保存/恢复矩形与最大化标志，不校验显示器 |
| 关闭请求可否决 | 完整 | 完整 | `glfwSetWindowCloseCallback` 与 `glfwSetWindowShouldClose(false)` |
| `session_ending`、`power_resume` | 完整 | 不支持 | 事件永不产生（无头模式可注入） |
| 消息循环/阻塞等待 | 完整 | 完整 | `glfwWaitEventsTimeout`；`wake` 用 `glfwPostEmptyEvent` |
| 系统模态循环内同步出帧 | 完整 | 退化 | 以窗口刷新回调（`glfwSetWindowRefreshCallback`）+ 尺寸回调同步出帧；缩放期间可能出现一帧延迟，不保证无黑边 |
| 鼠标/键/滚轮 | 完整 | 完整 | 滚轮 `raw` 由 GLFW 偏移量 × 120 折算，`steps` 同样累积 |
| 鼠标捕获 | 完整 | 退化 | 按键按下期间 GLFW 隐式捕获；`setCapture` 为空操作 |
| 键盘虚拟键、`text` | 完整 | 退化 | 由 GLFW 键码映射到 `VirtualKey`，缺失键映射为 `unknown`；`text` 来自 `glfwSetCharCallback`，无 Alt/F10 菜单键语义 |
| 输入法 | 完整（IMM32） | 退化 | 仅字符回调，不产生 `ime_start/update/commit/end`；`setImeCaretRect`、`setImeEnabled`、`commitComposition` 为空操作 |
| 鼠标指针形状 | 完整 | 退化 | `glfwCreateStandardCursor` 的标准形状；不在标准集的形状取最近似者（`size_all` → `arrow`） |
| 时钟 | 完整 | 完整 | `glfwGetTime` 折算毫秒 |
| 系统度量 `metrics` | 完整 | 退化 | 返回固定默认值（REQ-PLAT-084），永不产生 `system_changed{metrics}` |
| 系统外观 `appearance` | 完整 | 退化 | 返回固定默认值，浅色、无高对比度；无头模式可注入 |
| 剪贴板文本 | 完整 | 完整 | `glfwGetClipboardString`；自定义格式不支持 |
| 通用对话框、`messageBox` | 完整 | 不支持 | `messageBox`/`fatal` 退化为标准错误输出；`fatal` 仍以退出码 1 结束 |
| OLE 拖放（收/发） | 完整 | 退化 | 接收文件路径使用 `glfwSetDropCallback`（仅 `drop` 事件，无 `drag_enter/over/leave`）；`startDrag` 不支持 |
| 托盘 | 完整 | 不支持 | |
| 显示器信息 | 完整 | 完整 | `glfwGetMonitors` 等；工作区取 `glfwGetMonitorWorkarea` |
| 弹出窗口 | 完整（独立窗口） | 退化 | 退化为宿主窗口内的覆盖层：`createPopup` 不创建原生窗口，返回一个覆盖层句柄；该弹出根被裁剪在宿主客户区内（越界部分不可见，上层的翻转/裁剪逻辑以宿主客户区为工作区）；无系统阴影，由 `drawPopupFrame` 用发丝线边框即可；`popup_dismiss` 仅有 `outside_click`、`deactivated`、`host_moved` |
| GL 上下文 | 完整（WGL） | 完整 | `glfwCreateWindow`，共享 `share` 参数；仍为 3.3 Core |
| 垂直同步 | 完整 | 完整 | `glfwSwapInterval(1)` |
| 上下文丢失 | 完整 | 不支持 | |
| UI Automation | 完整（M6） | 不支持 | |
| 无头模式 | 不支持 | 完整 | 见 3.19 |

**REQ-PLAT-084**　GLFW 后端的系统度量固定默认值**必须**为：`double_click_ms = 500`、`double_click_size = 4×4 ppx`（乘 scale 取整）、`drag_size = 4×4 ppx`（同上）、`wheel_lines = lines(3)`、`wheel_chars = lines(3)`、`menu_show_delay_ms = 400`、`hover_time_ms = 400`、`hover_size = 4×4 ppx`、`caret_blink_ms = 530`、`keyboard_cues = false`、`client_animation = true`、`menu_animation = true`、`menu_fade = true`。外观默认值：`apps_dark = false`、`accent` 取 09 的默认强调色、`high_contrast = false`、`sys_colors` 取 09 高对比度映射表中的浅色等价值、`message_font = { family = 测试字体族名（05）, size_lpx = 12, weight = 400, italic = false }`、`text_scale = 1.0`。 另有 `key_repeat_delay_ms = 500`、`key_repeat_interval_ms = 33`。

### 3.19 无头模式

**REQ-PLAT-085**　GLFW 后端**必须**支持无头模式（`platform.initHeadless(opts)`），供单元、金图、回放测试使用。无头窗口是隐藏的 GLFW 窗口（`GLFW_VISIBLE = false`）加真实 GL 上下文（Linux 上由 Mesa llvmpipe 提供软件光栅；CI 以虚拟显示服务器提供显示连接，见 PLAT-OPEN-08）。`opts` 含：窗口客户区尺寸（ppx）、scale、初始 `SystemMetrics`、初始 `SystemAppearance`。

**REQ-PLAT-086**　无头模式**必须**提供下列可注入项，注入后行为确定且与墙钟无关：
- **假时钟**：`headless.advanceMs(n)` 推进 `nowMs`；`waitMessages(timeout)` 不阻塞，立即返回 `.timeout`，并把假时钟推进 `timeout`（无超时时返回 `.woken` 若有待处理事件，否则返回 `.idle` 表示无事可做）；
- **假垂直同步**：`swapBuffers` 不阻塞；`headless.vsync(n)` 推进 `n` 个垂直同步周期（每周期 `1000 / refresh_hz` ms，默认 60 Hz，推进假时钟）；
- **事件注入**：`headless.inject(event)`，事件按注入顺序在下一次 `pumpMessages` 中交给 `EventSink`；还提供 `injectMouseMove/Button/Wheel/Key/Text/Ime*` 等便捷函数；
- **系统外观与度量注入**：`headless.setAppearance(a)`、`headless.setMetrics(m)`，各自产出一个 `system_changed` 事件；
- **窗口状态注入**：`headless.setDpi`、`headless.resize`、`headless.setVisible`、`headless.setActive`，产出相应事件。

无头模式下 `wake` 立即使下一次 `waitMessages` 返回 `.woken`。

**REQ-PLAT-087**　无头模式**必须**提供观测接口供断言：`headless.cursorShape(window)`（最近一次 `setCursor` 的值）、`headless.imeCaretRect(window)`、`headless.imeEnabled(window)`、`headless.captured(window)`、`headless.presentCount(window)`、`headless.clipboard`（内存剪贴板，替代系统剪贴板）、`headless.popupRects()`（当前覆盖层弹出根的屏幕矩形）。

**REQ-PLAT-088**　电源事件：系统从睡眠或休眠恢复（`WM_POWERBROADCAST` 的 `PBT_APMRESUMEAUTOMATIC` 与 `PBT_APMRESUMESUSPEND`，两者同时到达时只产出一个）时，平台层**必须**产出 `power_resume` 事件，供上层重置依赖墙钟的状态、刷新显示器信息与重建可能失效的资源；平台层同时按 REQ-PLAT-079 检查上下文是否丢失。界面语言变化**必须**产出 `system_changed{locale}`（REQ-PLAT-045）。

## 4. 接口草案

```zig
// 草案：仅签名
pub const Vec2i = struct { x: i32, y: i32 };
pub const Path = []const u8;                         // UTF-8
pub const Size2i = struct { w: i32, h: i32 };
pub const RectI = core.RectI;

pub const Mods = packed struct { shift: bool, ctrl: bool, alt: bool, win: bool, altgr: bool };  // 不区分左右；altgr 时 ctrl/alt 为假
pub const MouseButton = enum { left, right, middle, x1, x2 };
pub const VirtualKey = enum(u16) {
    unknown,
    a, b, /* … */ z, n0, /* … */ n9, f1, /* … */ f24,
    lshift, rshift, lctrl, rctrl, lalt, ralt, lwin, rwin,   // 区分左右
    left, right, up, down, home, end, page_up, page_down,
    insert, delete, backspace, tab, enter, escape, space,
    np0, /* … */ np9, np_add, np_sub, np_mul, np_div, np_decimal, np_enter,
    caps_lock, num_lock, scroll_lock, print_screen, pause, apps,
    oem_1, oem_plus, oem_comma, oem_minus, oem_period, oem_102, /* … */
    _,
};
pub const CursorShape = enum { arrow, ibeam, hand, cross, size_we, size_ns, size_nwse, size_nesw, size_all, not_allowed, wait, progress, hidden };

pub const ImeSegmentStyle = enum { unconverted, converted, target_converted, target_unconverted, @"error" };
pub const ImeSegment = struct { start: u32, end: u32, style: ImeSegmentStyle }; // UTF-8 字节偏移
pub const DropEffect = enum { none, copy, move, link };
pub const DismissReason = enum { outside_click, deactivated, host_moved, host_resized, host_hidden, cancel_mode, capture_lost, dpi_changed };
pub const SettingsChanged = packed struct { appearance: bool, metrics: bool, font: bool, display: bool, locale: bool };

pub const Event = struct {
    window: *Window,
    time_ms: u64,
    body: union(enum) {
        mouse_move: struct { pos: Vec2i, screen_pos: Vec2i, mods: Mods, via_popup_capture: bool },
        mouse_button: struct { button: MouseButton, down: bool, pos: Vec2i, screen_pos: Vec2i, mods: Mods, via_popup_capture: bool },
        mouse_leave,
        capture_lost,
        wheel: struct { axis: enum { vertical, horizontal }, raw: i32, steps: i32, pos: Vec2i, screen_pos: Vec2i, mods: Mods, via_popup_capture: bool },
        key: struct { vk: VirtualKey, scancode: u16, down: bool, repeat: bool, extended: bool, mods: Mods },
        text: []const u8,
        ime_start,
        ime_update: struct { text: []const u8, cursor: usize, segments: []const ImeSegment },
        ime_commit: []const u8,
        ime_end,
        focus: bool,
        activate: struct { active: bool, by_click: bool },
        resized: struct { client: Size2i, state: enum { normal, minimized, maximized } },
        moved: Vec2i,
        dpi_changed: struct { dpi: u32, scale: f32 },
        repaint: RectI,
        visibility: bool,
        close_requested,
        session_ending: struct { logoff: bool },
        session_ended: struct { logoff: bool },
        system_changed: SettingsChanged,
        drag_enter: struct { formats: DropFormats, pos: Vec2i, effects_allowed: DropEffects },
        drag_over: struct { pos: Vec2i, mods: Mods },
        drag_leave,
        drop: struct { data: DropData, pos: Vec2i },
        tray: struct { id: u32, kind: TrayEventKind, screen_pos: Vec2i },
        popup_dismiss: DismissReason,
        power_resume,
    },
};

pub const EventSink = *const fn (ctx: *anyopaque, ev: *const Event) void;
pub const WaitResult = enum { message, woken, timeout, idle };
pub const FrameReason = enum { size, paint, timer, nested_modal };
pub const FrameCallback = *const fn (ctx: *anyopaque, w: *Window, reason: FrameReason) void;

pub const ScrollAmount = union(enum) { lines: u32, page };
pub const SystemMetrics = struct {
    double_click_ms: u32, double_click_size: Size2i, drag_size: Size2i,
    wheel_lines: ScrollAmount, wheel_chars: ScrollAmount,
    menu_show_delay_ms: u32, hover_time_ms: u32, hover_size: Size2i,
    caret_blink_ms: ?u32, keyboard_cues: bool,
    key_repeat_delay_ms: u32, key_repeat_interval_ms: u32,
    client_animation: bool, menu_animation: bool, menu_fade: bool,
};
pub const SysColor = enum { window, window_text, btn_face, btn_text, gray_text, highlight, highlight_text, hotlight /* … */ };
pub const MessageFont = struct { family: []const u8, size_lpx: f32, weight: u16, italic: bool };
pub const SystemAppearance = struct {
    apps_dark: bool, accent: core.Color, high_contrast: bool,
    sys_colors: std.EnumArray(SysColor, core.Color),
    message_font: MessageFont, text_scale: f32, metrics: SystemMetrics,
};

pub const WindowPlacement = struct { normal_rect: RectI, state: enum { normal, maximized, minimized }, dpi: u32 }; // ppx + 保存时的 DPI
pub const NativeWindowOptions = struct {
    title: []const u8, client_size: core.Vec2, position: ?Vec2i = null,
    resizable: bool = true, min_client_size: ?core.Vec2 = null,
    owner: ?*Window = null, show: enum { normal, maximized, minimized, hidden } = .normal,
    placement: ?WindowPlacement = null,
};
pub const PopupWindowKind = enum { menu, dropdown, tooltip };
pub const PopupWindowSpec = struct { rect: RectI, kind: PopupWindowKind, shadow: bool = true };

pub const Monitor = struct { handle: usize, bounds: RectI, work_area: RectI, dpi: u32, scale: f32, refresh_hz: u32, primary: bool };

pub const FormatId = enum(u32) { _ };
pub const ClipboardFormat = union(enum) { text, custom: FormatId };
pub const ClipboardItem = struct { format: ClipboardFormat, bytes: []const u8 };
pub const DropFormats = packed struct { files: bool, text: bool, custom: bool };
pub const DropEffects = packed struct { copy: bool, move: bool, link: bool };
/// 拖放/剪贴板载荷（08 的拖放载荷引用此类型）。切片的所有权随所在上下文：事件内由 DropData 持有。
pub const DataObject = struct {
    files: []const Path = &.{},
    text: ?[]const u8 = null,
    custom: []const ClipboardItem = &.{},
};
pub const DropData = struct {
    object: DataObject,
    allocator: std.mem.Allocator,
    pub fn deinit(self: *DropData) void;
};
pub const DragData = DataObject;                      // startDrag 的输入

pub const TrayEventKind = enum { click, double_click, context_menu, balloon_clicked };
pub const BalloonKind = enum { none, info, warning, @"error" };
pub const IconPixels = struct { w: u32, h: u32, rgba: []const u8 };   // 非预乘 RGBA8，顶行在前
pub const IconSet = []const IconPixels;                                // 多尺寸（如 16/20/24/32/48/256）

pub const FileFilter = struct { name: []const u8, patterns: []const []const u8 };   // 如 {"图片", {"*.png","*.jpg"}}
pub const FileDialogOptions = struct {
    title: ?[]const u8 = null,
    initial_dir: ?Path = null,
    default_name: ?[]const u8 = null,
    default_ext: ?[]const u8 = null,
    filters: []const FileFilter = &.{},
    multi: bool = false,                               // 仅 openFile
};
pub const FontChoice = struct { family: []const u8, size_lpx: f32, weight: u16, italic: bool };
pub const MessageIcon = enum { none, info, warning, @"error", question };
pub const MessageButtons = enum { ok, ok_cancel, yes_no, yes_no_cancel };
pub const MessageKind = struct { icon: MessageIcon, buttons: MessageButtons };
pub const MessageResult = enum { ok, cancel, yes, no };
pub const TaskButton = struct { id: u32, label: []const u8 };
pub const TaskDialogOptions = struct {
    title: []const u8,
    main_instruction: []const u8,
    content: []const u8 = "",
    expanded_info: ?[]const u8 = null,
    icon: MessageIcon = .none,
    buttons: []const TaskButton,
    default_button: ?u32 = null,
    verification: ?[]const u8 = null,                  // 复选框文字
};
pub const TaskResult = struct { button: ?u32, verification_checked: bool };   // button 为 null 表示被关闭

pub const Clock = struct { ctx: *anyopaque, now_ms: *const fn (ctx: *anyopaque) u64 };
pub const InitOptions = struct { app_name: []const u8 };
pub const HeadlessOptions = struct {
    client_size: Size2i,                               // ppx
    scale: f32 = 1.0,
    refresh_hz: u32 = 60,
    metrics: ?SystemMetrics = null,
    appearance: ?SystemAppearance = null,
};
pub const UiaNodeId = enum(u64) { none = 0, _ };
pub const UiaProvider = struct {                        // M6 细化；此处仅固定入口
    ctx: *anyopaque,
    root: *const fn (ctx: *anyopaque, w: *Window) UiaNodeId,
};

pub const Error = error{ Unsupported, ClipboardBusy, PathTooLong, OutOfMemory, PlatformFailure };

pub fn validatePlacement(p: WindowPlacement) WindowPlacement;   // REQ-PLAT-014
pub fn init(opts: InitOptions) void;                       // 失败走 fatal
pub fn deinit() void;
pub fn createWindow(opts: NativeWindowOptions) Error!*Window;
pub fn destroyWindow(w: *Window) void;
pub fn createPopup(owner: *Window, spec: PopupWindowSpec) Error!*Window;
pub fn destroyPopup(w: *Window) void;
pub fn setFrameCallback(w: *Window, ctx: *anyopaque, cb: FrameCallback) void;
pub fn pumpMessages(ctx: *anyopaque, sink: EventSink) usize;
pub fn waitMessages(timeout_ms: ?u32) WaitResult;
pub fn wake() void;                                        // 线程安全
pub fn allowSessionEnd(allow: bool) void;
pub fn nowMs() u64;
pub fn setClock(clock: ?*const Clock) Error!void;
pub fn metrics(w: *const Window) *const SystemMetrics;
pub fn appearance(w: *const Window) *const SystemAppearance;
pub fn monitors(allocator: std.mem.Allocator) Error![]Monitor;
pub fn monitorFromPoint(p: Vec2i) Monitor;
pub fn monitorFromWindow(w: *const Window) Monitor;
pub fn fatal(title: []const u8, text: []const u8) noreturn;
pub fn messageBox(owner: ?*Window, title: []const u8, text: []const u8, kind: MessageKind) MessageResult;

pub const Window = struct {
    pub fn scale(self: *const Window) f32;
    pub fn clientSize(self: *const Window) Size2i;          // ppx
    pub fn getPlacement(self: *const Window) WindowPlacement;
    pub fn setTitle(self: *Window, title: []const u8) void;
    pub fn setClientSize(self: *Window, size: core.Vec2) void;
    pub fn setPosition(self: *Window, p: Vec2i) void;
    pub fn setPopupRect(self: *Window, r: RectI) void;
    pub fn setMinClientSize(self: *Window, size: core.Vec2) void;
    pub fn setIcon(self: *Window, icons: IconSet) Error!void;     // 多尺寸像素缓冲，系统按需选取
    pub fn setDarkTitleBar(self: *Window, dark: bool) Error!void;
    pub fn show(self: *Window) void;
    pub fn hide(self: *Window) void;
    pub fn minimize(self: *Window) void;
    pub fn maximize(self: *Window) void;
    pub fn restore(self: *Window) void;
    pub fn requestAttention(self: *Window) void;
    pub fn bringToFront(self: *Window) void;
    pub fn confirmClose(self: *Window) void;
    pub fn cancelClose(self: *Window) void;
    pub fn canPresent(self: *const Window) bool;
    pub fn setCursor(self: *Window, shape: CursorShape) void;
    pub fn setCapture(self: *Window, on: bool) void;
    pub fn setImeCaretRect(self: *Window, caret: RectI, exclude: ?RectI) void;  // ppx，不再换算
    pub fn commitComposition(self: *Window) void;
    pub fn setImeEnabled(self: *Window, enabled: bool) void;
    pub fn setDropEffect(self: *Window, e: DropEffect) void;
    pub fn makeCurrent(self: *Window) Error!void;
    pub fn swapBuffers(self: *Window) void;
    pub fn setSwapInterval(self: *Window, n: u32) void;
};

pub const clipboard = struct {
    pub fn getText(allocator: std.mem.Allocator) Error!?[]u8;
    pub fn setText(utf8: []const u8) Error!void;
    pub fn hasText() bool;
    pub fn sequenceNumber() u32;
    pub fn registerFormat(name: []const u8) Error!FormatId;
    pub fn getData(f: FormatId, allocator: std.mem.Allocator) Error!?[]u8;
    pub fn setMany(items: []const ClipboardItem) Error!void;
};

pub const dialogs = struct {
    pub fn openFile(owner: ?*Window, opts: FileDialogOptions, allocator: std.mem.Allocator) Error!?[]Path;
    pub fn saveFile(owner: ?*Window, opts: FileDialogOptions, allocator: std.mem.Allocator) Error!?Path;
    pub fn pickFolder(owner: ?*Window, opts: FileDialogOptions, allocator: std.mem.Allocator) Error!?Path;
    pub fn pickColor(owner: ?*Window, initial: core.Color) Error!?core.Color;
    pub fn pickFont(owner: ?*Window, initial: FontChoice) Error!?FontChoice;
    pub fn taskDialog(owner: ?*Window, opts: TaskDialogOptions) Error!TaskResult;
};

pub fn startDrag(w: *Window, data: DragData, allowed: DropEffects) Error!DropEffect;

pub const tray = struct {
    pub fn add(owner: *Window, id: u32, icon: IconSet, tooltip: []const u8) Error!void;
    pub fn modify(id: u32, icon: ?IconSet, tooltip: ?[]const u8) Error!void;
    pub fn balloon(id: u32, title: []const u8, text: []const u8, kind: BalloonKind) Error!void;
    pub fn remove(id: u32) void;
};

pub const uia = struct {
    pub fn isEnabled() bool;
    pub fn setProvider(w: *Window, provider: *const UiaProvider) void;
};

pub const headless = struct {
    pub fn initHeadless(opts: HeadlessOptions) Error!void;
    pub fn advanceMs(n: u64) void;
    pub fn vsync(n: u32) void;
    pub fn inject(ev: Event) void;                       // 通用注入；以下为便捷包装，语义等同于构造对应事件后 inject
    pub fn injectMouseMove(w: *Window, pos: Vec2i) void;
    pub fn injectMouseButton(w: *Window, button: MouseButton, down: bool) void;
    pub fn injectWheel(w: *Window, raw_dx: i32, raw_dy: i32) void;
    pub fn injectKey(w: *Window, vk: VirtualKey, down: bool, repeat: bool) void;
    pub fn injectText(w: *Window, utf8: []const u8) void;
    pub fn injectImeStart(w: *Window) void;
    pub fn injectImeUpdate(w: *Window, text: []const u8, cursor: usize, segments: []const ImeSegment) void;
    pub fn injectImeCommit(w: *Window, text: []const u8) void;
    pub fn injectImeEnd(w: *Window) void;
    pub fn clipboard() *ClipboardItem;                   // 无头模式下的进程内假剪贴板
    pub fn setAppearance(a: SystemAppearance) void;
    pub fn setMetrics(m: SystemMetrics) void;
    pub fn simulateEnterSizeMove(w: *Window) void;      // 注入系统嵌套模态循环的进入/定时/退出
    pub fn simulateTimer(w: *Window) void;
    pub fn simulateExitSizeMove(w: *Window) void;
    pub fn simulateRenderLost(w: *Window) void;
    pub fn setDpi(w: *Window, dpi: u32) void;
    pub fn resize(w: *Window, size: Size2i) void;
    pub fn setVisible(w: *Window, v: bool) void;
    pub fn setActive(w: *Window, a: bool) void;
    pub fn cursorShape(w: *const Window) CursorShape;
    pub fn imeCaretRect(w: *const Window) RectI;
    pub fn imeEnabled(w: *const Window) bool;
    pub fn captured(w: *const Window) bool;
    pub fn presentCount(w: *const Window) u64;
    pub fn popupRects() []const RectI;
};
```

## 5. 边界与错误情况

| 情况 | 规定 |
|---|---|
| 窗口在 `WM_SIZE` 同步帧内再次收到 `WM_SIZE`（递归） | 帧回调不可重入（REQ-FRAME-023）；平台层在回调执行期间到达的 `WM_SIZE` 只记录最新尺寸，回调返回后若尺寸已变则再同步一次。 |
| 缩放到客户区 0×0 | 产出 `resized{0×0, minimized 或 normal}`，上层不构建不绘制；平台层不调用 `present`。 |
| 剪贴板中无文本 | `getText` 返回 `null`，不是错误。 |
| 剪贴板文本超过 64 MiB | `getText` 返回 `error.OutOfMemory`；`setText` 同样限制。 |
| 拖入的文件路径含无法转换的 UTF-16 | 该路径替换非法单元为 U+FFFD 并保留，记录 `warn`。 |
| 同一轮消息内收到多个 `WM_DPICHANGED` | 每个都应用系统建议矩形，仅最后一个值保留给事件（但不跳过 `SetWindowPos`）。 |
| 弹出窗口创建时宿主正在最小化 | `createPopup` 返回 `error.PlatformFailure`，上层视为无法打开。 |
| 对话框内触发 `WM_DPICHANGED` / 显示器断开 | 按普通路径处理；对话框由系统自行重定位。 |
| `WM_IME_COMPOSITION` 同时含 `GCS_RESULTSTR` 与 `GCS_COMPSTR` | 先 `ime_commit` 后 `ime_update`（REQ-PLAT-052）。 |
| `wake` 在窗口全部销毁后被调用 | 允许；事件对象在 `platform.deinit` 前一直有效，之后调用为未定义（`app.post` 在队列关闭后返回 `false`，REQ-ARCH 边界）。 |
| 事件载荷切片在 `sink` 返回后使用 | 未定义行为；调试构建在 `sink` 返回后将帧竞技场对应区域标记为不可访问。 |
| 在非界面线程调用非线程安全的 `platform` 函数 | 调试构建断言中止（REQ-ARCH-009）；线程安全清单仅 `wake`、`fatal`、`core.log`。 |
| Windows 10 上 `DWMWA_WINDOW_CORNER_PREFERENCE` 不被识别 | 返回错误，忽略（REQ-PLAT-082）。 |
| 高对比度主题下的 `accent` | 照常读取，由主题忽略（REQ-THEME-035）。 |

## 6. 验收标准

除标 `[人工]` 者外，以下测试在 GLFW 无头模式下运行，使用假时钟与假垂直同步。凡标 `[人工]` 的条款按 ADR 0004 必须在真实 Windows 上执行；Win11 与 Win10 1809 各执行一遍（条款另有说明者除外）。

**AC-PLAT-001**　`[单元]` 覆盖：REQ-PLAT-001。以两个目标分别编译 `platform` 的公共接口测试桩（Linux 本机、`x86_64-windows-gnu`），调用第 4 节全部函数的编译期存在性检查。预期：两个目标均通过编译；GLFW 后端中矩阵标"不支持"的函数在运行时返回 `error.Unsupported`（逐个断言）。

**AC-PLAT-002**　`[人工]` 覆盖：REQ-PLAT-002、REQ-PLAT-003、REQ-PLAT-004、REQ-PLAT-058。步骤：在 Windows 10 1809、Windows 11 上启动示例应用；再在一份去掉清单中 comctl32 v6 声明的构建上启动。观察要点：前者正常显示窗口，无异常对话框；用 `GetAwarenessFromDpiAwarenessContext` 的调试输出确认进程为 PerMonitorV2；后者在 `platform.init` 自检处以 `platform.fatal` 报告缺少通用控件 v6，退出码为 1。另在低于 1809 的系统上（或以版本伪装测试钩子）验证 `fatal` 的消息包含"1809"。

**AC-PLAT-003**　`[单元]` 覆盖：REQ-PLAT-005。向 `platform` 的字符串转换函数传入含 BMP 外字符、孤立代理项、空串、32 767 个 UTF-16 单元的路径。预期：BMP 外字符往返相等；孤立代理项转为 U+FFFD；空串为空；超长路径依具体调用点要求加 `\\?\` 前缀或返回 `error.PathTooLong`，且无越界。

**AC-PLAT-004**　`[人工]` 覆盖：REQ-PLAT-006、REQ-PLAT-007、REQ-PLAT-008、REQ-PLAT-009、REQ-PLAT-012。步骤：运行示例应用，浅色→深色切换系统"应用模式"；观察标题栏；将应用设为固定浅色再切换系统模式；用 Spy++ 类工具检查窗口类样式。预期：标题栏深浅随应用生效的模式变化，首次显示时无白色闪烁；窗口类样式不含 `CS_HREDRAW`、`CS_VREDRAW`、`CS_DBLCLKS`，无背景刷；标题栏、边框、系统菜单（Alt+Space）、最大化按钮悬停贴靠布局均为系统原生。

**AC-PLAT-005**　`[人工]` 覆盖：REQ-PLAT-010、REQ-PLAT-011。步骤：两台显示器分别为 100% 与 150% 缩放（或单机切换系统缩放）。将示例窗口（客户区 800×600 lpx）从 100% 屏拖到 150% 屏，缓慢越过边界，再拖回。观察要点：越过时窗口以系统建议矩形重设，客户区在 150% 屏上为 1200×900 ppx（800×600 lpx 保持不变）；内容无拉伸模糊、无残影；状态栏显示的 `scale` 依次为 1.0、1.5、1.0；跨屏瞬间无超过 1 帧的空白。

**AC-PLAT-006**　`[单元]` 覆盖：REQ-PLAT-010、REQ-PLAT-012、REQ-PLAT-013。无头注入 `setDpi(144)`，创建客户区 800×600 lpx、最小 320×200 lpx 的窗口。预期：`clientSize()` = 1200×900，`scale()` = 1.5；`setDpi(96)` 后事件序列含一个 `dpi_changed{96, 1.0}` 与一个 `resized{800×600}`；最小尺寸换算后 `setClientSize(100×100)` 被钳制到 320×200 lpx 对应的物理尺寸（480×300 @150%）。

**AC-PLAT-007**　`[人工]` 覆盖：REQ-PLAT-013。步骤：设最小客户区 320×200 lpx，在 100% 与 150% 的屏幕上分别拖边框缩小到极限。预期：客户区尺寸停在 320×200 lpx 对应的物理像素（320×200 与 480×300 ppx，±1 ppx）。

**AC-PLAT-008**　`[单元]` 覆盖：REQ-PLAT-014。以无头方式用桩显示器配置（一块 1920×1080，工作区 1920×1040）测试 `platform.validatePlacement`：(a) 矩形完全在内；(b) 矩形与工作区交集占 20%；(c) 矩形在已不存在的第二显示器上；(d) 保存时为最大化；(e) 保存时 `dpi = 96`、800×600 ppx，恢复到 `dpi = 144` 的显示器。预期：(a) 原样返回；(b)(c) 位置被丢弃（使用系统默认位置）、尺寸保留且不超过工作区；(d) 状态为最大化且保留正常状态矩形；(e) 尺寸为 1200×900 ppx 且返回的 `dpi = 144`。

**AC-PLAT-009**　`[回放]` 覆盖：REQ-PLAT-015。注入 `close_requested`，上层调用 `cancelClose`：窗口仍存在、`presentCount` 可继续增长；再注入一次并调用 `confirmClose`：窗口被销毁。另注入 `session_ending{logoff=true}` 并 `allowSessionEnd(false)`、再 `session_ended`。预期：事件顺序与回答被记录；未回答时视为允许。`[人工]` 补充：在 Windows 上使用"注销"且应用拒绝，观察注销被阻止并出现系统"此应用正在阻止"提示。

**AC-PLAT-010**　`[单元]` 覆盖：REQ-PLAT-016、REQ-PLAT-073、REQ-PLAT-074。创建一个窗口及其 3 个弹出窗口（含一个子菜单），销毁宿主。预期：销毁顺序记录为 3 个弹出窗口（子菜单先于其父弹出窗口）→ 宿主；之后对已销毁句柄的消息被丢弃（计数器 `dropped_after_destroy` 增加而不崩溃）；缓存的已隐藏弹出窗口数 ≤ 1。

**AC-PLAT-011**　`[回放]` 覆盖：REQ-PLAT-017。无头 `setVisible(false)` 后推进 5 秒并触发一次模型失效。预期：`canPresent()` 为假、`presentCount` 增量为 0；`setVisible(true)` 后收到 `visibility{true}`，首帧损伤为整根（对应 REQ-FRAME-049）。`[人工]` 补充：Windows 上最小化应用，持续运行动画 10 秒后还原，用 GPU 工具（任务管理器 GPU 引擎）确认最小化期间无渲染活动。

**AC-PLAT-012**　`[单元]` 覆盖：REQ-PLAT-018、REQ-PLAT-019、REQ-PLAT-020、REQ-PLAT-021。无头模式：(1) 无事件时 `waitMessages(100)` 返回 `.timeout` 且假时钟前进 100；(2) 从另一线程调用 `wake()` 后 `waitMessages(null)` 返回 `.woken`；(3) 连续 1000 次 `wake()` 后只需一次 `waitMessages` 即可清空（合并）；(4) `waitMessages(null)` 且无事件无唤醒返回 `.idle`。`[计量]` 补充（Windows 实机）：空闲 60 秒，进程内核+用户 CPU 时间增量 < 10 ms，且线程 `MsgWaitForMultipleObjectsEx` 进入阻塞次数 ≤ 2。

**AC-PLAT-013**　`[人工]` 覆盖：REQ-PLAT-022、REQ-PLAT-023、REQ-PLAT-024、REQ-PLAT-007。步骤：示例应用含自动换行的列表与一个进行中的进度动画，帧统计叠加开启。(1) 缓慢拖右下角边框放大再缩小，持续 10 秒；(2) 快速拖拽（约 2 秒内从最小拉到最大）；(3) 拖动窗口标题栏移动 5 秒；(4) 打开系统菜单（Alt+Space）停留 3 秒。预期：(1)(2) 缩放期间内容实时跟随，窗口新增区域从不出现黑色/白色/未绘制色块（以屏幕录像逐帧检查）；列表随宽度重排；(3)(4) 进度动画不停顿，帧统计的帧数在每次期间增长，增长速率 ≥ 显示器刷新率的 80%。

**AC-PLAT-014**　`[回放]` 覆盖：REQ-PLAT-022、REQ-PLAT-025。无头测试桩模拟系统回调：依次调用平台测试入口 `headless.simulateEnterSizeMove(w)`、两次 `headless.simulateTimer(w)`、`headless.resize(w, ...)`（同步帧）、`headless.simulateExitSizeMove(w)`。预期：帧回调被调用次数 = 2（timer）+ 1（size），`reason` 依次为 `.timer, .timer, .size`；`simulateExitSizeMove` 之后计时器计数为 0。再模拟在帧后动作内启动对话框桩：嵌套循环内只允许 `.paint/.size/.timer/.nested_modal` 原因的帧，且帧后动作启动嵌套循环时帧回调的调用深度计数为 0（测试桩在进入回调时记录深度，嵌套帧的深度恒为 1，从不为 2；即帧后动作执行时没有任何帧在运行）。

**AC-PLAT-015**　`[回放]` 覆盖：REQ-PLAT-024。无头注入 `repaint{rect = (10,10,100,50)}`。预期：产生 `paint` 级损伤恰为该矩形（向外取整后），构建遍数 0，该帧提交 1 次，且提交时拷贝的是整个客户区（GL 调用跟踪中 blit 的源矩形等于客户区）；注入整窗 `render_lost` 后下一帧损伤为整根。

**AC-PLAT-016**　`[单元]` 覆盖：REQ-PLAT-026、REQ-PLAT-027、REQ-PLAT-028。注入一串鼠标事件：移动 → 左键按下 → 移出窗口移动 → 左键释放。预期：事件序列字段与注入一致，`mouse_button.down` 先真后假；按下期间 `captured()` 为真，释放后为假；捕获期间离开客户区无 `mouse_leave`，释放后（指针在窗外）补发恰 1 个 `mouse_leave`。`[人工]` 补充：Windows 上按住左键拖出窗口外释放，观察控件收到释放（按钮不残留按下态）。

**AC-PLAT-017**　`[单元]` 覆盖：REQ-PLAT-029。注入垂直滚轮原始增量序列 `[+40, +40, +40, +120, -60, -60, -60]`。预期：`steps` 序列为 `[0, 0, 1, 1, 0, -1, 0]`：累加器依次为 40、80、120（产生 1 格，余 0）、120（产生 1 格，余 0）；第 5 个事件方向反转，累加器清零后为 -60（0 格）；第 6 个累计 -120（产生 -1 格，余 0）；第 7 个为 -60（0 格，余数保留）；`raw` 原样保留；水平轴累加器独立。`[人工]` 补充：用高精度触控板/自由滚轮鼠标在 Windows 上缓慢滚动，观察列表平滑移动且无"丢滚动"。

**AC-PLAT-018**　`[单元]` 覆盖：REQ-PLAT-030。检查 `platform` 的 Win32 后端源码（导入扫描脚本）。预期：不出现 `RegisterTouchWindow`、`WM_TOUCH`、`WM_POINTER`、`WM_GESTURE` 的引用。`[人工]` 补充：触摸屏上轻触按钮、拖动滚动条，观察均按鼠标语义工作。

**AC-PLAT-019**　`[单元]` 覆盖：REQ-PLAT-031、REQ-PLAT-032。无头注入：键 A 按下/释放；自动重复（`repeat = true`）；`VK_PROCESSKEY`；`WM_CHAR` 序列 `U+D83D U+DE00`（代理对）、孤立 `U+D83D`、`U+0009`、`U+001B`、`U+4E2D`。预期：key 事件字段正确；`VK_PROCESSKEY` 不产生 key 事件；`text` 事件依次为 `"😀"`（4 字节 UTF-8）、无（孤立代理项丢弃并 1 条 debug 日志）、无、无、`"中"`。

**AC-PLAT-020**　`[人工]` 覆盖：REQ-PLAT-033、REQ-PLAT-032。步骤：Windows 上示例应用的文本框聚焦，依次按：Alt 单击；F10；Alt+X（无绑定）；Alt+Space；Alt+F4（上层否决关闭）；在文本框内输入死键序列（美式国际键盘 `'` 然后 `e`）。预期：全程无系统"叮"声；Alt 与 F10 作为 key 事件到达上层（日志可见）且不出现系统菜单高亮；Alt+Space 弹出系统菜单；Alt+F4 产生 `close_requested`；死键序列输出 `é`。

**AC-PLAT-021**　`[回放]` 覆盖：REQ-PLAT-034。打开菜单弹出窗口（无头覆盖层）后检查事件流。预期：宿主窗口不收到 `activate{false}` 与 `focus{false}`；键盘事件仍作用于宿主的焦点路径。`[人工]` 补充：Windows 上打开菜单后观察宿主标题栏保持活动色。

**AC-PLAT-022**　`[单元]` 覆盖：REQ-PLAT-035、REQ-PLAT-017。注入 `resize(0×0)` 后 `minimized`。预期：`resized{client = 0×0, state = minimized}` 恰 1 个；`canPresent()` 为假；上层帧统计：构建/布局/绘制次数均不增加。

**AC-PLAT-023**　`[回放]` 覆盖：REQ-PLAT-036、REQ-PLAT-037。回放鼠标依次移到按钮、文本框、链接，各停留；并在同一位置连续触发 100 次相同形状的 `setCursor`。预期：`headless.cursorShape` 依次为 `arrow`、`ibeam`、`hand`；另在 `SPI_GETMOUSEVANISH` 为真的桩设置下注入 `text` 事件，预期指针被隐藏、随后的鼠标移动使其恢复；Win32 后端桩计数的 `SetCursor` 系统调用次数为 3（而不是 100）。`[人工]` 补充：Windows 上将指针移到窗口边框，观察显示系统缩放指针（`WM_SETCURSOR` 非客户区交还系统）。

**AC-PLAT-024**　`[单元]` 覆盖：REQ-PLAT-038、REQ-PLAT-039。(1) 连续调用真实 `nowMs` 1000 次，预期单调不减。(2) 注入假时钟后 `advanceMs(250)`，预期 `nowMs` 恰增 250；发布构建的 Win32 后端调用 `setClock` 返回 `error.Unsupported`（桩测试）。(3) 扫描 `src/` 除 `platform` 外的 Zig 代码，预期不出现对系统时钟 API 的引用。

**AC-PLAT-025**　`[单元]` 覆盖：REQ-PLAT-040、REQ-PLAT-041、REQ-PLAT-043、REQ-PLAT-084。用无头默认值读取 `metrics()` 与 `appearance()`。预期：全部字段与 REQ-PLAT-084 一致；`metrics()` 连续调用 10 000 次，后端系统调用桩计数为 0；以假 `LOGFONT`（`lfHeight = -16`，DPI 96；`lfHeight = -24`，DPI 144）测试 `message_font.size_lpx` 换算，预期均为 16。

**AC-PLAT-026**　`[人工]` 覆盖：REQ-PLAT-041、REQ-PLAT-044、REQ-PLAT-045、REQ-PLAT-046、REQ-PLAT-047。步骤：运行示例应用的"系统度量"调试页（实时显示 `SystemMetrics` 全部字段与事件日志）。在 Windows 设置/控制面板中依次修改：双击速度、鼠标"滚轮一次滚动行数"（1 → 10 → 一次一屏）、水平滚动字符数、菜单显示延迟（注册表 `MenuShowDelay` 经"视觉效果"）、鼠标悬停时间（通过 `SystemParametersInfo` 调用工具）、光标闪烁速度（含"无闪烁"）、"在 Windows 中显示动画"开/关、"始终显示键盘快捷方式的下划线"、"淡入淡出或滑动菜单"。预期：每次修改后调试页在 1 秒内显示对应字段新值，并有一条 `system_changed` 事件日志，`what` 含 `metrics`；页面上"滚轮一格滚动行数"在选择"一次一屏"时显示为 `page`；光标闪烁设为"无闪烁"时 `caret_blink_ms` 显示 `null`；"始终显示键盘快捷方式的下划线"关闭时，示例菜单栏的助记符下划线在按下 Alt 前不可见、按下后可见、窗口失去激活后再次隐藏。

**AC-PLAT-027**　`[人工]` 覆盖：REQ-PLAT-041。步骤：对"双击时间/矩形"和"拖拽阈值"各做边界实验：把双击速度调到最慢，以约 0.8 秒间隔点击两次；调到最快，以约 0.3 秒间隔点击两次；在列表上按下后向任一方向移动 1、2、3、4、5 ppx（100% 缩放）并松开。预期：判定与 `double_click_ms`、`double_click_size`、`drag_size` 一致：时间差 ≤ 阈值且位置在矩形内才产生双击；移动量超出 `drag_size` 的一半（矩形半宽）才进入拖拽；所用阈值与调试页显示一致，并与资源管理器文件列表的行为一致。

**AC-PLAT-028**　`[回放]` 覆盖：REQ-PLAT-042、REQ-PLAT-045、REQ-PLAT-046。无头 `setAppearance` 切换 `apps_dark`、`accent`、`high_contrast` 与 `sys_colors` 各一次。预期：每次恰产生 1 个 `system_changed`，`what.appearance = true`；事件被投递时 `appearance(w)` 已为新值；同一轮注入 3 次变化合并为 1 个事件。

**AC-PLAT-029**　`[人工]` 覆盖：REQ-PLAT-042、REQ-PLAT-043、REQ-PLAT-045。步骤：在 Windows 设置中切换：应用模式浅/深、强调色（手动选 3 种与"自动从背景选取"）、高对比度主题开/关、辅助功能"文本大小"、更改系统消息字体（通过注册表或第三方工具）。预期：调试页的 `apps_dark`、`accent`（与 DWM 返回值逐分量相等，忽略 alpha）、`high_contrast`、`sys_colors`、`message_font.family/size_lpx`、`text_scale` 在 1 秒内更新；无需重启。

**AC-PLAT-030**　`[单元]` 覆盖：REQ-PLAT-048、REQ-PLAT-050。无头内存剪贴板：写入 `"a\nb\r\nc\rd"` 的 `setText`；读取。预期：读取结果 `"a\nb\nc\nd"`；Win32 后端桩中实际写入的 UTF-16 为 `"a\r\nb\r\n..."` 形式（规范化后每个换行均为 `\r\n`）；注册自定义格式 `application/x-nano-test`，`setMany` 同时写入文本与自定义数据后两者均可读回；`hasText()` 不触发 `OpenClipboard`（桩计数 0）；`sequenceNumber` 在每次写入后递增。

**AC-PLAT-031**　`[单元]` 覆盖：REQ-PLAT-049。Win32 后端桩使 `OpenClipboard` 前 3 次失败、第 4 次成功；另一用例使其一直失败。预期：前者成功读写，总睡眠 30 ms（桩累计）；后者在第 5 次失败后返回 `error.ClipboardBusy`，总睡眠 ≤ 50 ms 且尝试次数恰为 5。`[人工]` 补充：用另一个持有剪贴板的工具进程（循环 OpenClipboard 持有 2 秒）与应用同时粘贴，观察应用不卡死、返回忙状态后上层给出可见提示。

**AC-PLAT-032**　`[回放]` 覆盖：REQ-PLAT-051、REQ-PLAT-052、REQ-PLAT-054、REQ-PLAT-055。无头注入 IME 事件脚本：`ime_start` → `ime_update{"ni", cursor=2}` → `ime_update{"你", segments=[{0,3,target_converted}]}` → `ime_commit{"你"}` → `ime_end`；再脚本：组字中注入 `focus{false}`；再脚本：组字中由上层调用 `commitComposition()` 后 `setImeEnabled(false)`。预期：文本框内容在提交后恰为 `"你"`，组字状态在 `ime_end` 后清除（每次 `ime_start` 恰对应 1 个 `ime_end`）；组字中失焦时平台测试桩收到取消组字调用（`CPS_CANCEL`）且产生 `ime_end` 而无 `ime_commit`；`commitComposition()` 产生 `ime_commit` 随后 `ime_end`，其后 `setImeEnabled(false)` 不再触发取消调用；组字期间 `key` 事件中 `VK_PROCESSKEY` 不交上层。UTF-16 属性数组到 UTF-8 字节区间的转换另以单元测试覆盖：属性 `[INPUT,INPUT,CONVERTED]`（对应 `"ab你"`）转换结果为 `[{0,2,unconverted},{2,5,converted}]`。

**AC-PLAT-033**　`[人工]` 覆盖：REQ-PLAT-051、REQ-PLAT-053、REQ-PLAT-054、REQ-PLAT-055。步骤：Windows 上启用微软拼音，在多行文本框内输入"nihao"并选择候选，分别在：文本中部、窗口右下角附近、滚动后的位置、150% 缩放屏上重复；再把焦点移到按钮并尝试打字。预期：组字串在文本框内联显示，带下划线，系统不显示独立的组字窗口；候选窗紧贴光标所在行下方，不遮挡组字串，窗口靠近屏幕底部时由系统自动翻到上方；候选窗位置与光标偏差 ≤ 4 ppx；焦点在按钮上时输入法被禁用（语言栏显示英文/无组字）；组字中点击窗口外，组字被取消且无残留下划线。

**AC-PLAT-034**　`[单元]` 覆盖：REQ-PLAT-053。无头记录 `setImeCaretRect` 调用。预期：文本框在以下每个时机后 `imeCaretRect` 更新到新矩形（客户区 ppx，由框架换算，平台层桩断言收到的值与调用参数逐位相等、未再乘以 scale）：光标移动、滚动、窗口 `moved`、`dpi_changed`、`ime_update`；组字有目标转换子句时 `exclude` 为其矩形，无则为 `null`；未变化的帧不重复调用（桩计数）。

**AC-PLAT-035**　`[人工]` 覆盖：REQ-PLAT-056、REQ-PLAT-057、REQ-PLAT-058。步骤：示例应用的"对话框"页逐个触发：打开文件（多选）、保存文件、选择文件夹、颜色、字体、任务对话框（含复选框）。每个对话框打开期间：拖动应用的**另一个**窗口、缩放被禁用的 owner 窗口、使其被其他窗口遮挡后移开。预期：取消返回 `null`，不报错；多选返回全部路径（UTF-8，含中文与空格）；对话框期间 owner 窗口被禁用但仍重绘（缩放时内容跟随，无黑块），另一窗口完全可交互；对话框关闭后 owner 被重新激活，鼠标按键状态无卡死（在 owner 内立即点击按钮有效，不需要先点击一次激活）。

**AC-PLAT-036**　`[单元]` 覆盖：REQ-PLAT-056、REQ-PLAT-059、REQ-PLAT-058。(1) 调试构建下在构建函数内调用 `dialogs.openFile`，预期断言中止并指出 REQ-FRAME-027；(2) 在 GLFW 后端调用任一 `dialogs.*`，预期返回 `error.Unsupported`；(3) `messageBox` 在 `platform.init` 之前调用，Win32 后端不崩溃（`[人工]`）；(4) `platform.fatal("标题", "正文")` 在 GLFW 后端把两段文字写到标准错误，进程退出码为 1（子进程测试）。

**AC-PLAT-037**　`[人工]` 覆盖：REQ-PLAT-059。步骤：在一台仅有软件渲染（远程桌面连接且无 GPU，或虚拟机未装显卡驱动）的 Windows 上运行示例应用。预期：弹出系统错误消息框，文字依次含：失败步骤（选择像素格式或创建上下文）、请求版本"3.3 Core"、`GL_RENDERER`/`GL_VERSION`（若可得）、`GetLastError` 数值、更新驱动的建议；点击确定后进程退出码为 1，无崩溃报告。

**AC-PLAT-038**　`[人工]` 覆盖：REQ-PLAT-060、REQ-PLAT-061、REQ-PLAT-062、REQ-PLAT-063。步骤：(1) 从资源管理器把 3 个文件（含中文名、含空格名）拖入应用的拖放区，再拖入一段选中的文本；(2) 拖入时观察指针效果；拖到不接受的区域；(3) 按 Esc 取消拖入；(4) 应用内从列表拖出一个文件到资源管理器窗口与桌面；拖出文本到记事本。预期：(1) `drop` 事件携带全部路径与文本，与源完全一致；(2) 进入接受区域指针显示"复制"，不接受区域显示禁止；(3) 收到 `drag_leave`，无 `drop`；(4) 目标获得文件副本，结果效果值为 `copy`，文本在记事本中完全一致；全程应用不卡死，拖入期间应用内动画不停顿。

**AC-PLAT-039**　`[单元]` 覆盖：REQ-PLAT-061、REQ-PLAT-062。Win32 后端桩模拟 `IDropTarget` 调用序列：`DragEnter` → `DragOver`（×3）→ `Drop`。上层在处理 `drag_enter` 事件的同一帧调用 `setDropEffect(.copy)`。预期：`DragEnter` 返回 `none`；第一个 `DragOver` 返回 `copy`；`Drop` 的事件载荷在 `Drop` 返回前已深拷贝（桩在返回后释放数据对象并将其内存填充为 0xAA，事件中的路径仍正确）；传入 10 001 个路径时只保留 10 000 个并记录 1 条 `warn`。

**AC-PLAT-040**　`[人工]` 覆盖：REQ-PLAT-064、REQ-PLAT-065。步骤：示例应用的"托盘"页：添加图标（带提示）→ 悬停查看提示 → 单击、双击、右键 → 触发气泡通知并点击气泡 → 修改图标与提示 → 在任务管理器中重启 `explorer.exe` → 退出应用。预期：图标可见，提示文字一致；单击/双击/右键分别产生 `click`/`double_click`/`context_menu` 事件（日志）；右键菜单在点击菜单外时关闭；气泡显示标题与正文，点击产生 `balloon_clicked`；资源管理器重启后图标在 3 秒内自动重新出现；应用退出后托盘中无残留图标（鼠标扫过托盘区后消失）。图标在 100%、150%、200% 缩放下清晰（无明显拉伸）。

**AC-PLAT-041**　`[单元]` 覆盖：REQ-PLAT-066。用桩显示器配置（主屏 1920×1080@96 DPI 60 Hz，副屏 3840×2160@144 DPI 120 Hz，位于主屏左侧，坐标为负）调用 `monitors()`、`monitorFromPoint`。预期：返回两项，副屏 `bounds.x < 0`、`scale = 1.5`、`refresh_hz = 120`、`primary = false`；点在两屏之外时返回最近者；取不到刷新率时为 60。`[人工]` 补充：对真实多显示器机器，对照"显示设置"核对分辨率、缩放、刷新率、工作区（任务栏占位）。

**AC-PLAT-042**　`[回放]` 覆盖：REQ-PLAT-067、REQ-PLAT-068、REQ-PLAT-069、REQ-PLAT-070。无头覆盖层：宿主内打开菜单弹出窗口；回放：点击菜单内一项、点击宿主内空白处、点击本进程全部窗口之外（注入屏幕坐标）、`activate{false}`、`moved`、宿主 `resized`、`dpi_changed`、`capture_lost`。预期：菜单内点击以 `via_popup_capture = true` 到达并带 `screen_pos`；点击宿主内空白处：以 `via_popup_capture = true` 的鼠标事件到达，**不**产生 `popup_dismiss`（由上层按 08 判定并继续投递）；点击本进程全部窗口之外（注入屏幕坐标）：产生 1 个 `outside_click`，该点击不被转发；`activate{false}`、`moved`、宿主 `resized`、`dpi_changed`、`capture_lost` 分别产生 1 个对应 `reason`（`deactivated`、`host_moved`、`host_resized`、`dpi_changed`、`capture_lost`）的 `popup_dismiss`；`tooltip` 类不开启捕获（`captured()` 为假）。

**AC-PLAT-043**　`[人工]` 覆盖：REQ-PLAT-067、REQ-PLAT-068、REQ-PLAT-069、REQ-PLAT-070、REQ-PLAT-071。步骤：Windows 10 1809 与 Windows 11 各一遍。示例应用的菜单页：(1) 右键打开上下文菜单，观察宿主标题栏活动色；(2) 在菜单内用方向键、Enter 操作，键盘焦点输入文本框是否仍在宿主；(3) 点击桌面、点击另一应用的窗口、点击本应用另一窗口；(4) 菜单打开时按 Alt+Tab、拖动宿主窗口、最小化宿主；(5) 打开提示框，鼠标指向提示框；(6) 观察阴影与圆角。预期：(1) 标题栏保持活动色，任务栏无新窗口按钮；(2) 菜单收到键导航，文本框的光标位置不变；(3) 每次点击后菜单关闭，且点击不触发被点击窗口中的按钮动作；(4) 每种情形菜单关闭；(5) 鼠标穿透提示框，下方控件仍悬停；(6) Win10 上直角带系统阴影，Win11 上小圆角带阴影。

**AC-PLAT-044**　`[人工]` 覆盖：REQ-PLAT-072。步骤：两台显示器（100% 与 150%），把宿主放在 100% 屏右边缘，向右打开一个 300×200 lpx 的菜单，使其落在 150% 屏上；再放在屏幕底部向下打开。观察要点：菜单在 150% 屏上以 150% 缩放渲染（字体与线宽清晰，无拉伸）；落点位置与上层计算的工作区翻转结果一致（偏差 ≤ 1 ppx）；创建过程中无半尺寸闪烁。

**AC-PLAT-045**　`[回放]` 覆盖：REQ-PLAT-075、REQ-PLAT-076、REQ-PLAT-077。无头：创建两个窗口，在窗口 A 上传一个 64×64 纹理并在窗口 B 的上下文中绘制它；查询交换间隔。预期：窗口 B 绘制出的像素与 A 一致（逐像素相等）；每个窗口的 `swapInterval` = 1；FBO 不跨窗口（B 无法绑定 A 的 FBO id，断言返回 GL 错误或不可见）。`[人工]` 补充：Windows 上用 `PIXELFORMATDESCRIPTOR`/GL 查询工具确认像素格式为 RGBA8、模板 8、双缓冲，上下文版本 ≥ 3.3 Core。

**AC-PLAT-046**　`[单元]` 覆盖：REQ-PLAT-078、REQ-PLAT-079。GLFW 后端桩使上下文创建返回失败：断言 `platform.fatal` 被以含"创建上下文""3.3 Core"字样的文本调用；Win32 逻辑层以桩数据验证消息格式化函数包含 `GL_RENDERER`/`GL_VERSION`/`GetLastError` 三项。另注入"上下文丢失"信号：预期产生整窗 `repaint`，gfx 重建计数 +1。

**AC-PLAT-047**　`[单元]` 覆盖：REQ-PLAT-080、REQ-PLAT-081。M6 之前：`uia.isEnabled()` 为假；向窗口过程桩发送 `WM_GETOBJECT(UiaRootObjectId)`，预期返回 `DefWindowProc` 的结果且无分配。映射表框架：断言控件规范注册表可登记 `{ UIA 控件类型, 模式, 名称来源, 值来源 }`，未登记节点在调试构建产生 1 条警告并按 `Custom` 处理。M6 起另补金图无关的 `[人工]` 项见 10 各控件。

**AC-PLAT-048**　`[单元]` 覆盖：REQ-PLAT-082。在 `compat` 测试桩中分别注入"Win10 1809"、"Win10 21H2"、"Win11"三种版本。预期：弹出窗口外观决策依次为 `drop_shadow`、`drop_shadow`、`corner_round_small`；DWM 属性设置失败返回 `error.Unsupported` 且无日志级别高于 `debug`；全仓库除 `platform.compat` 外无版本号比较（导入扫描脚本）。`[人工]` 补充：于两种系统实机观察 AC-PLAT-043(6) 的外观。

**AC-PLAT-049**　`[单元]` 覆盖：REQ-PLAT-083、REQ-PLAT-084。遍历降级矩阵的机器可读副本（由本文表格生成，位于测试数据中），逐行对 GLFW 后端断言："不支持"行返回 `error.Unsupported` 或事件永不产生；"退化"行满足描述的行为（例如：`createPopup` 返回覆盖层且 `popupRects` 被限制在宿主客户区内；`setImeCaretRect` 为空操作；`startDrag` 返回 `error.Unsupported`）；"完整"行与 Win32 桩一致。预期：矩阵每一行恰有一条断言，全部通过。

**AC-PLAT-050**　`[回放]` 覆盖：REQ-PLAT-085、REQ-PLAT-086、REQ-PLAT-087。无头模式端到端：创建 800×600 窗口，注入 `setDpi(120)`、假时钟、一串鼠标/键/文本/IME 事件、一次外观切换，并 `vsync(60)`。预期：整个过程不依赖墙钟（测试运行时间与假时钟推进量无关，墙钟耗时 < 2 秒）；`waitMessages` 从不阻塞；`presentCount` 与帧数一致；事件顺序与注入顺序一致；所有观测接口返回预期值。同一脚本重复运行 100 次结果逐字节相同（事件日志哈希相等）。

**AC-PLAT-051**　`[回放]` 覆盖：REQ-PLAT-088、REQ-PLAT-045。无头注入 `power_resume` 与 `setAppearance` 之外的 `system_changed{locale}`。预期：各产生恰 1 个对应事件；`power_resume` 同时到达 `PBT_APMRESUMEAUTOMATIC` 与 `PBT_APMRESUMESUSPEND`（Win32 桩）时只产出 1 个。`[人工]` 补充：Windows 上使电脑睡眠 30 秒后唤醒，调试页显示 `power_resume` 日志 1 条，动画与定时器恢复正常，窗口内容无花屏；在系统设置中切换界面语言/区域格式，调试页显示 `system_changed` 且 `what` 含 `locale`（通知时机见 PLAT-OPEN-13）。

## 7. 待定问题

- **PLAT-OPEN-01**　`WM_ENTERSIZEMOVE` 期间 `SetTimer` 的最小周期（系统计时器分辨率）能否达到 60 Hz 以上刷新率所需的精度，以及是否需要改用 `timeBeginPeriod`。需在 Windows 实机以帧统计确认；若不足，缩放期间的动画帧率会低于刷新率。
- **PLAT-OPEN-02**　`GetSystemMetricsForDpi`/`SystemParametersInfoForDpi` 在 1809 上返回的拖拽矩形、双击矩形是否随窗口 DPI 缩放；若不随之缩放，则改为系统 DPI 值乘 `scale / 系统 scale`。需实机确认。
- **PLAT-OPEN-03**　"文本大小"辅助功能的读取来源（注册表 `TextScaleFactor` 与 `UISettings.TextScaleFactor`）在 1809 与 Windows 11 上是否一致，以及它是否已体现在 `lfMessageFont` 中（避免重复缩放）。需实机确认。
- **PLAT-OPEN-04**　窗口"被完全遮挡"的可靠检测手段：`DWMWA_CLOAKED` 只覆盖被云化/虚拟桌面隐藏的情形，不覆盖被其他窗口遮挡。当前倾向：只把最小化与 `IsWindowVisible == false` 当作不可见，遮挡情形依赖驱动忽略 `SwapBuffers`。
- **PLAT-OPEN-05**　TSF（Text Services Framework）支持：IMM32 在新版输入法（手写、表情、语音输入、部分第三方输入法）下的行为有限。是否在 M6 之后引入 TSF，以及 `IMR_RECONVERTSTRING` 重新转换的支持，留待实测后以新 ADR 决定。
- **PLAT-OPEN-06**　UIA 控件类型与模式的具体常量名及版本要求，M6 开始前以 SDK 头文件核对。
- **PLAT-OPEN-07**　是否需要自定义位图指针（如拖拽中的特殊指针）。当前答案：不需要。
- **PLAT-OPEN-08**　无头 CI 的显示连接：采用虚拟显示服务器（Xvfb）还是 GLFW 的无显示器（EGL/OSMesa）上下文。需在 M0 的 CI 环境中验证 Mesa llvmpipe 的 GL 3.3 Core 可用性。
- **PLAT-OPEN-09**　`DWMWA_USE_IMMERSIVE_DARK_MODE` 属性编号在 1809 与更高版本上的差异，及 1809 上是否生效，需实机逐一确认（REQ-PLAT-082）。
- **PLAT-OPEN-10**　弹出会话中"宿主持有鼠标捕获"与"点击外部窗口不传递"的组合，在宿主处于嵌套模态（如对话框）时的交互，以及与屏幕阅读器的兼容性，需实机确认；备选方案为低级鼠标钩子（`WH_MOUSE_LL`），因其对系统整体输入链有延迟影响，当前不采用。
- **PLAT-OPEN-11**　`DoDragDrop` 拖出期间应用内动画与定时器的驱动：系统在 `DoDragDrop` 内部运行自己的消息循环，`WM_TIMER` 方案是否足够，需实机确认。
- **PLAT-OPEN-12**　AltGr 的判定：右 Alt 伴随系统合成的左 Ctrl（扫描码 0x21D）在不同键盘布局与远程桌面下的消息序列差异，以及合成 Ctrl 的 `key` 事件是否应当抑制，需实机（德语、法语、美式国际布局）确认。
- **PLAT-OPEN-13**　界面语言/区域设置变化的通知来源（`WM_SETTINGCHANGE` 的 `"intl"`、`WM_INPUTLANGCHANGE`、用户界面语言 `GetUserDefaultUILanguage` 的变化时机）需实机确认。
