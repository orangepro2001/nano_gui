# 11 应用模型

## 1. 范围

定义应用层：`App` 的初始化、主循环、退出与线程协作；`Window` 的创建、关闭请求（可否决）与多窗口；应用内模态对话框与原生对话框；命令系统（命令、快捷键、重映射、标准编辑命令）；设置与界面状态的持久化；模型变更通知的契约与推荐模式；框架内建字符串；启动参数、会话结束、休眠恢复等生命周期事件。依据 ADR 0005、0006、0008。

帧的调度见 06，输入路由见 08（本文的快捷键查表在 08 的优先级 ④ 执行），菜单与工具栏控件见 10。崩溃处理、单实例、自动更新不在当前范围（见待定问题）。

## 2. 术语

| 术语 | 定义 |
|---|---|
| 应用标识 (`AppId`) | 厂商名与应用名，用于设置路径与注册的窗口类名。 |
| 关闭请求 | 窗口被要求关闭（用户、应用退出、会话结束等）时先询问窗口、窗口可否决的流程。 |
| 对话框 | 本文所指的应用内模态对话框：带系统标题栏的顶层窗口，客户区由框架绘制，从属于一个宿主窗口。 |
| 原生对话框 | 由系统绘制的通用对话框：文件/文件夹、颜色、字体、`TaskDialog`。 |
| 命令 (`Command`) | 见 00 术语表；本文给出其数据结构与调用语义。 |
| 命令状态 | 命令在某个窗口某次构建中声明的 `enabled`/`checked`。 |
| 设置存储 | 一个应用一份的 JSON 文件及其内存镜像。 |
| 界面状态 | 框架自动持久化的状态：窗口几何、分隔条位置、表格列、树展开集合、快捷键重映射。 |
| 去抖 (debounce) | 在最后一次变更之后等待一段静默时间再执行写入。 |

## 3. 规范条款

### 3.1 App

**REQ-APP-001**　每个应用**必须**在初始化时提供 `AppId{ vendor, name }`（UTF-8）。两者**必须**非空、各不超过 64 字节、不含路径分隔符与 `<>:"/\|?*` 及控制字符、不以点或空格结尾、不是 Windows 保留设备名（`CON`、`NUL`、`COM1` 等，不区分大小写）；否则 `App.init` 返回 `error.InvalidAppId`。`AppId` 在整个进程内不可变，是设置路径（REQ-APP-031）与窗口类名的唯一来源。

**REQ-APP-002**　`App.init(opts: AppOptions)` **必须**：创建持久分配器之上的 `App`、初始化平台层、读取设置存储（REQ-APP-031 至 REQ-APP-036）、选定内建字符串表（REQ-APP-042）、注册标准编辑命令（REQ-APP-030）。`init` **不得**创建或显示任何窗口，**不得**创建线程（REQ-ARCH-007）。可恢复的失败以显式错误集 `App.InitError` 返回；不可恢复的失败按 REQ-ARCH-017 处理。

**REQ-APP-003**　`App.run()` 运行界面线程的主循环，**必须**遵循 REQ-FRAME-052 至 REQ-FRAME-054，直到退出条件成立，然后依次：销毁所有窗口、强制落盘设置（REQ-APP-034）、释放平台层，并返回进程退出码（`i32`）。`run` 只能在调用 `init` 的线程上调用，且只能调用一次。

**REQ-APP-004**　`App.quit(code: i32)` 请求退出，分两阶段：(1) **询问**：记录退出码，对每个顶层窗口按创建的逆序依次发起关闭请求（`CloseReason.app_quit`，REQ-APP-012），只询问、不销毁；任一窗口否决则停止询问，整个退出被取消，退出码记录被清除，所有窗口保持原状。(2) **销毁**：全部窗口都允许后，按同样顺序销毁（每个窗口先关闭其对话框，REQ-APP-012）。全部窗口销毁后 `run` 返回所记录的退出码。无窗口时 `quit` 立即使 `run` 返回。未调用 `quit` 而因窗口全部关闭（REQ-APP-005）退出时，退出码为 0。`quit` 可在构建函数之外的任何界面线程代码（含命令处理函数、`afterFrame` 闭包）中调用，在构建函数内调用视为编程错误。

**REQ-APP-005**　`AppOptions.exit_policy` 取：`when_last_window_closes`（默认）——最后一个**顶层窗口**（对话框不计）被销毁后自动执行 `quit(0)`；`explicit`——窗口全部关闭后应用继续运行（配合托盘图标等），直到调用 `quit`。隐藏（`hide`）的窗口仍计为存活。

**REQ-APP-006**　`app.post(closure: Closure) bool` 与 `app.wake()` 是**线程安全**的（REQ-ARCH-008）。`post` 把闭包排入无界多生产者单消费者队列并唤醒界面线程，闭包按入队顺序在界面线程执行，且先于同一轮的帧（REQ-ARCH-010）；应用已进入退出流程（队列关闭）后 `post` 返回 `false` 且不执行闭包，调用方负责释放其捕获的资源。`Closure` 的所有权规则：`ctx` 由调用方分配，`post` 成功后**由闭包函数负责释放**；`call` 返回后框架不再引用 `ctx`。`wake` 仅唤醒阻塞等待，不产生帧（除非有其他失效）。

**REQ-APP-007**　框架不创建线程；"工作线程算完后回投结果并失效"的**规范模式**如下，应用**应当**遵循：
1. 界面线程在响应激活类结果（如 `clicked`）时分配 `Job`（含输入数据副本与结果槽），用 `std.Thread.spawn` 创建工作线程，并在模型中置"进行中"标记。
2. 工作线程只读写 `Job` 自己的数据，**不得**触碰 `Ui`、`Window`、模型或任何非线程安全 API。
3. 完成时工作线程调用 `app.post(done_closure)`。`post` 返回 `false`（应用退出中）时由工作线程自行释放 `Job`。
4. `done_closure` 在界面线程执行：把结果写入模型、释放或回收 `Job`、回收线程句柄，然后调用 `app.invalidateAll(.build)`（或所涉窗口的 `invalidate`）。
5. 进度更新同理：工作线程**应当**合并更新（同一时刻至多一个在途的进度闭包，且频率 ≤ 30 Hz）。
6. 取消通过 `Job` 内的原子标志，工作线程自行轮询；应用退出时界面线程设置标志并在退出流程中 `join`。

**REQ-APP-008**　`app.invalidateAll(level)` **只能**在界面线程调用，对全部窗口各置脏一次（REQ-FRAME-056）；`Window.invalidate(level)` 是线程安全的（REQ-ARCH-008，等价于回投一次失效）。其他线程要触发失效，**必须**使用 `Window.invalidate`、或 `app.post` 一个调用 `invalidateAll` 的闭包。

### 3.2 Window

**REQ-APP-009**　`app.createWindow(opts: WindowOptions, handlers: WindowHandlers) !*Window` 的选项**必须**包含：`title`（框架复制）、`size`（初始客户区尺寸，lpx，默认 900×600）、`min_size`（lpx，可选）、`icon`（可选，`WindowIcon`）、`persist_name`（可选字符串，REQ-APP-014）、`resizable`（默认真）、`visible`（默认真）、`owner`（可选）。`WindowOptions` 是应用层类型，创建时转换为 03 的 `platform.NativeWindowOptions`（`size`→`client_size`、`min_size`→`min_client_size`、`persist_name` 对应的位置记录→`placement`，REQ-APP-015）。`WindowIcon` 取 `set`（直接给出 03 的 `platform.IconSet`，多尺寸 RGBA 列表）或 `image`（`gfx.ImageId`，框架回读像素并缩放为 16、20、24、32、48、256 ppx 的 `IconPixels` 列表后交给 `Window.setIcon`）。窗口的**有效最小尺寸**取 `min_size` 与根节点最小期望尺寸 `ui.minWindowSize()`（07，REQ-LAYOUT-053）各分量较大者，由平台层用于 `WM_GETMINMAXINFO`。窗口标题栏、边框使用系统非客户区，并按 09 同步深浅色（ADR 0008）。

**REQ-APP-010**　`WindowHandlers` 含：`build: BuildFn`、`ctx: *anyopaque`（用户上下文指针，原样传给每个回调，框架不解引用、不拥有）、可选的 `on_close_request` 与 `on_closed`。`build(ui, ctx)` 是该窗口的构建函数，须满足 REQ-FRAME-024 至 REQ-FRAME-028。`ctx` 指向的对象**必须**活得比窗口久，直到 `on_closed` 返回。窗口创建时 `Ui` 随之创建，销毁时随之销毁（回收全部状态槽，REQ-FRAME-010）。

**REQ-APP-011**　`Window` 的生命周期操作：`show()`/`hide()` 改变可见性（隐藏不销毁、不丢状态）；`requestClose(reason)` 走关闭请求流程（REQ-APP-012）；`destroy()` **强制**销毁，不询问，仅供关闭流程内部与测试使用；`setTitle(utf8)`（框架复制）；`invalidate(level)`（线程安全）；`ui()` 取其 `Ui`。已销毁窗口的指针不得再使用；销毁后 `on_closed(ctx)` 恰好调用一次。

**REQ-APP-012**　**关闭请求可被否决**。以下来源统一走 `requestClose(reason)`：用户（标题栏关闭按钮、`Alt+F4`、系统菜单，`user`）、`App.quit`（`app_quit`）、会话结束（`session_end`，REQ-APP-044）、宿主关闭连带关闭其对话框（`owner_closed`）。流程**只有**下面三步：
1. **询问**：确定待关闭的窗口集合——`user` 为该窗口自身；`app_quit` 与 `session_end` 为全部顶层窗口，按创建的逆序。对集合中每个窗口依次调用 `on_close_request(ctx, reason) CloseDecision`（未设置该回调视为 `allow`）。任一窗口返回 `veto` 则立即停止询问、整个流程终止并通知调用方（`quit` 因此被取消，所有窗口保持原状，没有任何窗口被销毁）。`user` 来源下，有未关闭对话框的窗口已被禁用，OS 不会送达关闭请求。
2. **全部允许**后进入统一销毁；`session_end` 例外：只把结果回答系统（REQ-APP-044），不销毁。
3. **统一销毁**：按询问的顺序销毁集合中的窗口。销毁每个窗口时，**先**关闭它的全部对话框（结果码为取消，**不**调用 `on_result`），再保存窗口几何（REQ-APP-014）、销毁窗口、调用 `on_closed`；全部销毁后依 REQ-APP-005 判断是否退出。
`on_close_request` **不得**阻塞；"未保存的更改"提示的做法是：回调返回 `veto` 并打开一个应用内对话框（REQ-APP-016），用户在对话框中选择"保存/不保存"后由结果回调再次调用 `window.requestClose` 或 `destroy`。`session_end` 来源下对话框来不及显示，应用**应当**据 `reason` 自行决定自动保存并返回 `allow`。

**REQ-APP-013**　一个应用可有多个顶层窗口，每个窗口有独立的 `Ui`、独立的构建函数与状态存储，共享 `App` 的命令注册表、设置存储与字符串表（REQ-FRAME-056）。窗口间的数据共享经由应用模型，用 `app.invalidateAll` 通知；窗口的失效互不触发（REQ-FRAME-056）。各窗口按各自显示器的缩放系数独立布局（REQ-LAYOUT-052）。

**REQ-APP-014**　`persist_name` 非空的窗口，其**位置**自动持久化到设置存储（REQ-APP-037）。11 **只负责存取** 03 的 `platform.WindowPlacement`（`normal_rect` 为虚拟屏幕物理像素 ppx、显示状态、保存时所在显示器的 `dpi`）：保存的字段为 `x`、`y`、`w`、`h`（即 `normal_rect`，ppx）、`dpi`、`maximized`（显示状态为最大化时为真，最小化按正常状态保存）。保存时机：窗口移动或缩放结束、最大化/还原、关闭（允许之后）；保存值取自 `Window.getPlacement()`。`persist_name` 为空的窗口不持久化。同一进程内 `persist_name` **必须**唯一，重复时 `createWindow` 返回 `error.DuplicatePersistName`。

**REQ-APP-015**　创建窗口时恢复位置：**校验规则以 03 为唯一定义**（REQ-PLAT-014：与工作区交集不小于 25% 且标题栏落在工作区内，否则使用系统默认位置并保持换算后的尺寸；DPI 不同时按 lpx 不变换算尺寸），11 **不得**自行实现平移、居中或夹紧算法。流程：
1. 设置中无该名称的记录，或记录字段缺失、类型错误、`w`/`h` ≤ 0：忽略整条记录，`placement` 为空，使用 `WindowOptions.size` 与系统默认位置。
2. 有合法记录：构造 `WindowPlacement{ normal_rect = (x, y, w, h), state, dpi }`，调用 `platform.validatePlacement` 取得校验后的值，作为 `NativeWindowOptions.placement` 创建窗口；`maximized` 为真则 `state = maximized`。
3. 校验后的位置与尺寸即最终结果，11 不再修改。

### 3.3 对话框

**REQ-APP-016**　应用内模态对话框是**非阻塞 API**：`app.openDialog(owner: *Window, opts: DialogOptions, build: DialogBuildFn, ctx: *anyopaque, on_result: ?ResultFn) !*Dialog` 在对话框打开后**立即返回**。对话框是一个带系统标题栏的顶层窗口（Win32：`WS_POPUP | WS_CAPTION | WS_SYSMENU`，`WS_EX_DLGMODALFRAME`，以宿主为 owner），有独立的 `Ui`；其内容由 `build(ui, dlg, ctx)` 声明。**不允许**嵌套消息循环：框架中不存在任何阻塞到对话框关闭才返回的应用内对话框接口。

**REQ-APP-017**　对话框打开期间，宿主窗口**必须**被禁用（Win32：`EnableWindow(host, FALSE)`），使宿主不接收任何鼠标与键盘输入，仍可正常重绘、响应尺寸变化与 `invalidate`。对话框关闭时，**先**重新启用宿主，**再**销毁对话框窗口，使系统能把激活还给宿主。对话框可以以另一个对话框为宿主，形成链；只有链的末端启用。宿主被销毁时其全部对话框先被关闭（`owner_closed`）。宿主打开对话框时，宿主的全部弹出层以原因 `dialog_opened` 关闭（REQ-INPUT-054、REQ-INPUT-064）。

**REQ-APP-018**　对话框结果：`Dialog.close(code: u32)` 请求关闭并记下结果码（可在构建函数内响应激活类结果时调用，关闭在本帧提交之后生效）；关闭完成后 `on_result(ctx, code)` **恰好调用一次**，调用在一个独立的消息循环轮次内（经 `post`），不在对话框的帧内。宿主也可在其构建函数中轮询 `dialog.result() ?u32`（未关闭为 `null`）而不设 `on_result`。用户通过标题栏关闭按钮或 `Alt+F4` 关闭对话框视同点击取消按钮：声明了取消按钮的对话框收到 `activate(cancel_button)`（REQ-INPUT-034），未声明的以 `DialogCode.cancel` 关闭。宿主已被销毁时不调用 `on_result`。标准结果码 `DialogCode`：`ok = 1`、`cancel = 2`、`yes = 6`、`no = 7`（与 Windows 的 `IDOK` 等一致），自定义码 ≥ 100。

**REQ-APP-019**　对话框窗口属性：标题取 `DialogOptions.title`；无最小化/最大化按钮；默认 `resizable = false`；客户区尺寸 `size` 为 `null`（默认）时取根节点的期望尺寸（以工作区尺寸为限制测量，07），并在内容期望尺寸变化时重新适配窗口客户区（保持左上角不动）；窗口初始居中于宿主窗口（夹紧在工作区内）；客户区使用 `pad_dialog` 内边距（09）与 `surface_window` 底色。对话框遵循 REQ-LAYOUT-053，有效最小尺寸同样生效。对话框的 `Ui` 拥有独立的焦点与快捷键源，不继承宿主的快捷键表。

**REQ-APP-020**　对话框的按钮约定遵循 Windows：(1) 提供 `w.dialogButtons(ui, src, buttons) ?u32`（属 `widgets` 模块，见 dialog.md），把按钮排成一行，**右对齐**（`justify = end`，间距 `gap_md`），**按声明顺序从左到右排列**，确定类按钮在左、取消在右（如"确定、取消"，"保存、不保存、取消"）；返回本帧被点击的按钮的 `code`。(2) `DialogButton{ label, code, role }`，`role ∈ {normal, default, cancel, default_and_cancel}`（最后一种用于只有一个按钮的对话框，使 Enter 与 Esc 都返回该按钮的码）；至多一个默认与一个取消；按钮带 `enabled` 标志；各按钮等宽，取最宽者且不小于 `button_min_w`，`dialogButtons` 据此调用 `ui.rootScope` 设置默认/取消按钮（REQ-INPUT-039），默认按钮用 `accent` 变体绘制。(3) **初始焦点**：对话框首次构建完成后，焦点给 `ScopeSpec.initial_focus`（若设置），否则给第一个可聚焦的**非按钮**控件，都没有时给默认按钮（再没有则第一个 Tab 停靠点）；若该点是一个文本输入类控件则全选其内容。(4) 对话框内 Enter 触发默认按钮、Esc 触发取消按钮（REQ-INPUT-034）。

**REQ-APP-021**　原生对话框（`app.native`：`openFile`、`saveFile`、`pickFolder`、`pickColor`、`pickFont`、`taskDialog`）是**阻塞**的，**只能**在 `ui.afterFrame` 登记的帧后动作闭包（REQ-FRAME-027）内调用。`app.native.*` 是 03 的 `platform.dialogs.*` 的薄封装，函数名相同；选项与结果类型（`platform.FileDialogOptions`、`platform.TaskDialogOptions`、`platform.TaskResult`、`platform.FontChoice`、`platform.Path` 等）**直接引用 03 的定义**，11 不重复定义；`pickFont` 在 app 层把 `platform.FontChoice` 转成 `text.Style` 后再回调。结果经回调 `fn(ctx, result)` 交回（取消为 `null`；`taskDialog` 以 `TaskResult.button == null` 表示被关闭），回调返回后自动 `invalidate(.build)`。在构建函数内或绘制函数内调用，调试构建断言中止；发布构建返回 `error.NotInAfterFrame`。需指定 `owner: *Window`，对话框期间 owner 由系统禁用。

**REQ-APP-022**　原生对话框阻塞期间系统会泵送消息。此时帧后动作所在的那一帧已完全收尾（REQ-FRAME-023），本进程窗口的帧由平台层按 REQ-PLAT-025 驱动：仅因重绘、尺寸、DPI 变化与定时器/动画而出帧，使窗口内容保持正确且动画不停顿；输入事件不分发到被禁用的宿主窗口；回投队列照常累积，在对话框返回、`afterFrame` 闭包结束后按序处理。降级后端不支持的原生对话框返回 `error.Unsupported`（03 的降级矩阵）。

### 3.4 命令系统

**REQ-APP-023**　**命令** `Command` 由 `CommandSpec` 注册：`id`（稳定字符串标识，如 `file.save`，匹配 `[a-z0-9_]+(\.[a-z0-9_]+)*`、≤ 64 字节）、`title`（含助记符，语法同 REQ-INPUT-046，如 `保存(&S)`）、可选 `icon`、可选默认快捷键 `shortcut: ?input.Chord`、`handler`。`app.commands.register(spec)` 返回运行时句柄 `CommandId`；字符串标识重复时返回 `error.DuplicateCommand`，不符合上述格式时返回 `error.InvalidCommandId`。字符串标识是持久化与外部引用的唯一依据，**一经发布不得更名**（更名需迁移钩子，REQ-APP-036）；`CommandId` 句柄只在进程内有效。命令是应用级的，所有窗口共享。

**REQ-APP-024**　命令的**运行时状态**（`enabled`、`checked: ?bool`，`null` 表示不可勾选）由应用在**构建时**提供，不使用回调轮询：构建函数中调用 `ui.command(cmd, CommandState)` 声明该窗口本次构建中的状态，并返回它（供应用在同处使用）。框架在每次构建结束时为该窗口保存状态快照，分发阶段的快捷键查表（REQ-INPUT-029）读取快照。本次构建中未声明的命令，状态取 `CommandSpec.default_state`（默认 `enabled = true`）。菜单项、工具栏按钮显示的启用/勾选状态**必须**来自同一份声明。

**REQ-APP-025**　菜单项、工具栏按钮与快捷键都**绑定命令**，而不是各自带处理函数：菜单项与工具栏按钮控件（10）以 `CommandId` 构造，其标题（去助记符后的文本用于工具栏提示框）、图标、快捷键文本（REQ-APP-029）、启用、勾选均取自命令；被点击时调用 `ui.invoke(cmd, source)`。工具栏按钮的提示框文本为"标题（去助记符）+ 空格 + 括号内的快捷键文本"，无快捷键时只有标题。

**REQ-APP-026**　命令的调用时序：
- **快捷键**（来源 `shortcut`）在分发阶段（REQ-INPUT-029）立即调用处理函数，并置 `build` 脏；命令**禁用**时按键被吞掉而不调用。
- **菜单、工具栏**（来源 `menu`/`toolbar`）：`ui.invoke` 把调用排入本窗口的调用队列；该构建遍结束后**立即**依序执行队列中的处理函数（早于同帧的第二构建遍，使其效果在同帧可见，REQ-FRAME-030），并置 `build` 脏。
- 处理函数在界面线程执行，**不得**阻塞，可以修改模型、打开对话框、调用 `app.quit`、登记 `afterFrame`；处理函数内再调用 `ui.invoke` 排入队列，在同一次排空循环中继续执行，嵌套深度超过 8 视为编程错误。
- `ui.invoke` 作用于禁用的命令时忽略并在调试构建报告 `warn`；`app.commands.invoke(cmd, .programmatic)` 不检查状态。

**REQ-APP-027**　**快捷键重映射**：用户（或应用）可经 `app.commands.setShortcut(cmd, ?input.Chord, mode)` 改绑，`null` 表示取消绑定；`mode` 取 `reject`（该和弦已被另一个命令占用时返回 `error.ShortcutConflict` 并给出占用者）或 `steal`（从占用者处夺走，占用者变为未绑定）。快捷键必须至少含一个非修饰键；`Shift` 单独修饰的可打印字符键（`Shift+A`）因与文本输入冲突被拒绝（`error.InvalidShortcut`），功能键、方向键、带 Ctrl/Alt 的和弦除外。`resetShortcuts()` 恢复全部默认。改绑后菜单与提示框中的快捷键文本在下一次构建更新。

**REQ-APP-028**　快捷键重映射**必须**持久化：设置存储 `ui.shortcuts` 对象（REQ-APP-037）以命令的字符串标识为键、以不随语言变化的**固定格式**和弦字符串（`Ctrl+Shift+S`，英文键名）为值；`""` 表示用户显式取消绑定；与默认绑定相同的条目**不写入**。启动时先应用默认绑定再覆盖用户条目；条目引用的命令不存在、和弦无法解析或与已应用条目冲突时，忽略该条目并记录 `warn`。

**REQ-APP-029**　菜单与提示框中显示的**快捷键文本格式**：修饰键按固定顺序 `Ctrl`、`Alt`、`Shift`、`Win`，其后是键名，以 `+` 连接，无空格，如 `Ctrl+Shift+S`、`Alt+Enter`、`F5`。键名取自字符串表（REQ-APP-042）的 `key_names`：字母为大写字母，数字键为数字，其余为 `Enter`、`Esc`、`Del`、`Ins`、`Home`、`End`、`PgUp`、`PgDn`、`Space`、`Tab`、`Backspace`、`Left`、`Up`、`Right`、`Down`、`Menu`、`F1`…`F24`（与 `platform.VirtualKey` 覆盖的功能键一致）。简体中文与英文的默认表相同（与 Windows 中文版一致），应用可替换。固定格式（REQ-APP-028）使用英文键名且不可替换，解析时不区分大小写。

**REQ-APP-030**　**标准编辑命令** `edit.undo`、`edit.redo`、`edit.cut`、`edit.copy`、`edit.paste`、`edit.delete`、`edit.select_all` 由框架在 `init` 时注册，默认快捷键依次为 `Ctrl+Z`、`Ctrl+Y`、`Ctrl+X`、`Ctrl+C`、`Ctrl+V`、无、`Ctrl+A`。它们**路由到焦点控件**：调用时向激活窗口的 `Ui` 的宿主焦点节点（弹出层打开时也是宿主焦点节点，REQ-INPUT-036）投递 `edit_command` 事件。其状态**不**由应用声明，而由焦点节点在构建时经 `InteractOpts.edit`（`EditCaps`）声明的能力决定：焦点节点声明了对应能力则启用，否则禁用（禁用时其快捷键被吞掉，REQ-INPUT-029）。无焦点节点时全部禁用。文本输入类控件通常预占这些按键（REQ-INPUT-028），因此该路由主要服务于菜单项、工具栏按钮与非文本控件（列表的复制、全选）。

### 3.5 设置持久化

**REQ-APP-031**　设置文件路径：Win32 为 `%APPDATA%\<vendor>\<name>\settings.json`（`FOLDERID_RoamingAppData`）；GLFW 后端为 `$XDG_CONFIG_HOME/<vendor>/<name>/settings.json`，`XDG_CONFIG_HOME` 未设置或为空时取 `~/.config`。目录在首次写入时递归创建。文件为 UTF-8 编码、无 BOM 的 JSON。`Settings.path()` 返回该路径。

**REQ-APP-032**　设置文件顶层**必须**是对象，含：`format`（整数，框架文件格式版本，当前为 1）、`app_version`（整数，应用设置版本，来自 `AppOptions.settings_version`，默认 1）、`app`（对象，应用自有设置）、`ui`（对象，框架自动持久化的界面状态，REQ-APP-037）。未知的顶层键在读入时保留、写出时原样带回（便于新旧版本交替运行）。

**REQ-APP-033**　写入**必须**是原子的：序列化到同目录的 `settings.json.tmp`，刷新到磁盘（Win32：`FlushFileBuffers`；Linux：`fsync`），再用 `MoveFileExW(MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)`（Linux：`rename`）替换目标。任一步失败则删除临时文件、保持原文件不变、保持"脏"状态、记录一条 `warn`（同一原因不重复刷屏），并在下一次变更或退出时重试。读到的文件**不得**被就地修改。

**REQ-APP-034**　写入时机**必须**是：设置发生变更后**去抖 500 ms**——每次变更把写入截止时间重置为 `now + 500 ms`；持续变更时为避免饿死，自"首次变脏"起最迟 5000 ms 必须写入一次。截止时间由主循环作为定时器参与阻塞等待的超时计算（REQ-FRAME-052），不引入轮询、不产生帧。**退出时强制落盘**：`App.run` 在销毁窗口之后、返回之前，以及 `WM_ENDSESSION` 为真时，若为脏则同步写入一次。文件 I/O 在界面线程执行（设置文件很小；框架不创建线程）。

**REQ-APP-035**　**损坏处理**：读取时下列任一情形视为文件损坏——无法解析为 JSON、顶层不是对象、`format` 缺失或不是整数、`format` 大于框架已知的版本（来自更新的版本，不应被旧版本覆盖）。处理：把原文件改名为 `settings.json.bad-<UTC 时间 YYYYMMDD-HHMMSS>`（该目录下此类备份只保留最新 3 个，多余的删除），以默认值启动，记录一条 `warn`，并使 `Settings.recoveredFromCorruption()` 返回真。首次写入产生新文件。文件不存在不算损坏。

**REQ-APP-036**　迁移钩子：`format` 小于当前版本时，框架按版本号顺序执行内建迁移（每步 `format` 加 1）；`app_version` 小于 `AppOptions.settings_version` 时，在 `init` 内、应用读取设置之前**恰好调用一次** `AppOptions.settings_migrate(ctx, settings, from, to)`，钩子可读取旧键、写入新键、删除旧键。迁移成功后设置置脏（以新版本号重写）；迁移返回错误时按损坏处理（REQ-APP-035，原文件保留为备份）。`app_version` 大于 `settings_version` 时不迁移，按原样保留（降级运行）。

**REQ-APP-037**　框架自动持久化的**界面状态**以**字符串名**为键（REQ-FRAME-006，`WidgetId` 不入盘），写入 `ui` 对象，内容限于：
| 子对象 | 键 | 值 |
|---|---|---|
| `windows` | 窗口 `persist_name` | `{ x, y, w, h, dpi, maximized }`，ppx（REQ-APP-014） |
| `splitters` | `<窗口名>/<控件名>` | `{ mode: "ratio" \| "fixed_first" \| "fixed_second", value }` |
| `tables` | `<窗口名>/<控件名>` | `{ widths: [lpx…], order: [列索引…], hidden: [布尔…], sort: { col, asc } \| null }`（与 `TableState` 对应：`sort` 为 `null` 即 `sort_col = null`） |
| `trees` | `<窗口名>/<控件名>` | 展开节点的应用提供的字符串键数组（可选功能，控件规范声明是否启用） |
| `shortcuts` | 命令字符串标识 | 固定格式和弦字符串（REQ-APP-028） |
控件名由控件选项 `persist: ?[]const u8` 提供，窗口名为所在窗口的 `persist_name`；二者任一为空则该控件不持久化。控件在**首次出现**时读取一次（缺失则用代码默认值），在用户操作结束时（拖动释放、排序点击）写入，经设置存储的去抖机制落盘。未被任何存活控件引用的条目保留不删除。读入值越界（比例不在 0..1、列数与表格不符）时忽略该条目。

**REQ-APP-038**　应用自有设置经 `Settings` 的类型化访问器读写：`getBool/getInt/getFloat/getString(key, default)` 与对应的 `set*`、`remove(key)`、`flush()`；键为点分隔的 UTF-8 字符串（`editor.font_size`），存放在 `app` 对象下的嵌套结构中；值类型限于布尔、64 位整数、64 位浮点、字符串。`getString` 返回的切片只在下一次对同一设置存储的 `set*`/`remove` 之前有效，调用方需要保留时自行复制。类型不符时返回默认值并记录一次 `warn`。所有访问器**只能**在界面线程调用。目录不可创建或文件不可写（只读环境）时，设置仍在内存中工作，写入失败按 REQ-APP-033 处理，`Settings.persistent()` 返回假。

### 3.6 模型通知

**REQ-APP-039**　模型是应用的数据，框架不拥有，只接收变更通知。通知是**显式**的（ADR 0006）：模型变更后，应用**必须**调用 `window.invalidate(level)`、`ui.invalidate(level)` 或 `app.invalidateAll(level)`（默认 `.build`），否则界面不会更新。例外：响应激活类结果（REQ-FRAME-025）而在构建函数内修改模型时，激活本身已触发同帧第二构建遍，无需另行通知。同一轮消息内的多次通知合并为一帧（REQ-FRAME-038）。

**REQ-APP-040**　**推荐模式**（说明性，应用**应当**遵循）：(1) 模型封装为一个类型，所有变更都经其方法完成，每个变更方法结尾调用同一个 `changed()`，由它调用 `invalidateAll(.build)`（多窗口共享时）或所属窗口的 `invalidate`；(2) 批量变更先改完再通知一次；(3) 外部事件源（定时器、I/O、工作线程）的回调只做"改模型 + `changed()`"，且在界面线程执行（REQ-APP-007）；(4) 构建函数只读模型，仅在 `clicked`/`changed`/`committed` 等激活类结果的分支内调用模型的变更方法；(5) 仅影响外观的变化（如进度条的动画）使用 `paint` 级通知或框架动画，不用 `build`。

**REQ-APP-041**　**反模式**（应用**不得**采用，评审据此判定）：(1) 在构建函数中无条件修改模型或调用 `invalidate` 以"保持界面刷新"（构成失效风暴，REQ-FRAME-035）；(2) 用 `ui.timer` 周期性轮询模型是否变化；(3) 工作线程直接调用 `app.invalidateAll` 或直接修改模型；(4) 在绘制函数内通知（REQ-FRAME-018）；(5) 在模型的读取函数里通知；(6) 在构建函数中保存指向帧竞技场或状态槽的指针到模型；(7) 因担心遗漏而每次输入后无差别地 `invalidateAll`（应按窗口精确通知）。调试开关 `-Dforce-rebuild` 下界面行为与关闭时不同，即表明存在遗漏的通知。

### 3.7 内建字符串与生命周期

**REQ-APP-042**　框架内建的面向用户的字符串（对话框标准按钮、编辑上下文菜单项、快捷键键名、提示文字等）**必须**集中在一张 `Strings` 表中，不得散落在控件代码里。默认随系统界面语言提供**简体中文**（`zh_cn`）与**英文**（`en`）两份：Win32 取 `GetUserPreferredUILanguages` 的首项，语言标签以 `zh-Hans`、`zh-CN`、`zh-SG` 开头者用简体中文，其余用英文；GLFW 后端取 `LC_MESSAGES`/`LANG` 的语言前缀 `zh`。应用可通过 `AppOptions.strings` 或 `app.setStrings(table)` 整体替换（表中缺失字段不允许，类型强制全部提供）；运行中系统界面语言变化时（03 的 `system_changed` 事件的 `SettingsChanged.locale` 位，REQ-PLAT-045）未被应用固定的表重新选择，并置 `build` 脏。应用自己的字符串不在此表中。

**REQ-APP-043**　启动参数：`app.args()` 返回 UTF-8 的参数切片数组（Win32 由 `CommandLineToArgvW` 转换而来，首项为可执行文件路径），在应用存活期内有效。框架**不解析**参数含义，也不预设任何开关。

**REQ-APP-044**　**会话结束**，与 03 的衔接（REQ-PLAT-015）：收到 `session_ending` 事件（含 `logoff` 标志）时，框架在**同一轮事件处理内**对每个顶层窗口执行关闭请求流程的询问阶段（原因 `session_end`，REQ-APP-012，只询问、不销毁）；任一窗口否决则调用 `platform.allowSessionEnd(false)`，全部允许则调用 `platform.allowSessionEnd(true)`。收到 `session_ended` 事件（`WM_ENDSESSION` 为真）时，框架**同步**强制落盘设置（REQ-APP-034）、调用 `AppOptions.on_session_end`（可选，应用在其中保存数据）、然后不再处理任何界面工作，立即结束进程。在 `session_ending` 处理期间不显示任何新窗口或对话框。

**REQ-APP-045**　**系统休眠恢复**：收到 03 的 `power_resume` 事件（REQ-PLAT-088，睡眠或休眠恢复，两种系统通知合并为一个事件）时，框架对每个窗口的每个根产生一次**整根绘制**损伤（视为帧缓冲内容不可保留，REQ-FRAME-044）并置 `build` 脏，同时请求渲染层检查并在必要时重建图形上下文（04）。恢复期间的动画按 REQ-FRAME-049 直接跳到目标值。

## 4. 接口草案

```zig
// 草案：仅签名
pub const Closure = struct { ctx: *anyopaque, call: *const fn (ctx: *anyopaque) void };

pub const AppId = struct { vendor: []const u8, name: []const u8 };
pub const ExitPolicy = enum { when_last_window_closes, explicit };

pub const SettingsMigrateFn = *const fn (ctx: ?*anyopaque, settings: *Settings, from: u32, to: u32) MigrateError!void;
pub const MigrateError = error{ MigrationFailed };

pub const AppOptions = struct {
    id: AppId,
    allocator: std.mem.Allocator,
    exit_policy: ExitPolicy = .when_last_window_closes,
    strings: ?*const Strings = null,
    settings_version: u32 = 1,
    settings_migrate: ?SettingsMigrateFn = null,
    settings_migrate_ctx: ?*anyopaque = null,
    theme: ?theme.Theme = null,
    on_session_end: ?*const fn (ctx: ?*anyopaque) void = null,
    on_session_end_ctx: ?*anyopaque = null,
};

pub const App = struct {
    pub const InitError = error{ InvalidAppId, PlatformInitFailed, OutOfMemory };
    pub fn init(opts: AppOptions) InitError!*App;
    pub fn deinit(self: *App) void;
    pub fn run(self: *App) i32;                                  // 退出码
    pub fn quit(self: *App, code: i32) void;                     // 界面线程
    pub fn post(self: *App, closure: Closure) bool;              // 线程安全
    pub fn wake(self: *App) void;                                // 线程安全
    pub fn invalidateAll(self: *App, level: Dirty) void;         // 界面线程
    pub fn args(self: *const App) []const []const u8;
    pub fn setStrings(self: *App, table: *const Strings) void;
    pub fn createWindow(self: *App, opts: WindowOptions, handlers: WindowHandlers) CreateWindowError!*Window;
    pub fn openDialog(self: *App, owner: *Window, opts: DialogOptions, build: DialogBuildFn, ctx: *anyopaque, on_result: ?ResultFn) OpenDialogError!*Dialog;

    commands: Commands,
    settings: Settings,
    native: NativeDialogs,
};
pub const CreateWindowError = error{ DuplicatePersistName, PlatformFailed, OutOfMemory };
pub const OpenDialogError = error{ OwnerDestroyed, PlatformFailed, OutOfMemory };

// —— Window ——
pub const Size = struct { w: f32, h: f32 };       // lpx
pub const WindowIcon = union(enum) { set: platform.IconSet, image: gfx.ImageId };
pub const WindowOptions = struct {
    title: []const u8,                            // 框架复制
    size: Size = .{ .w = 900, .h = 600 },
    min_size: ?Size = null,
    icon: ?WindowIcon = null,                     // 窗口图标，见 REQ-APP-009
    persist_name: ?[]const u8 = null,             // 框架复制；进程内唯一
    resizable: bool = true,
    visible: bool = true,
    owner: ?*Window = null,
};
pub const CloseReason = enum { user, app_quit, session_end, owner_closed };
pub const CloseDecision = enum { allow, veto };
pub const BuildFn = *const fn (ui: *Ui, ctx: *anyopaque) void;
pub const WindowHandlers = struct {
    build: BuildFn,
    ctx: *anyopaque,
    on_close_request: ?*const fn (ctx: *anyopaque, reason: CloseReason) CloseDecision = null,
    on_closed: ?*const fn (ctx: *anyopaque) void = null,
};
pub const Window = struct {
    pub fn show(self: *Window) void;
    pub fn hide(self: *Window) void;
    pub fn requestClose(self: *Window, reason: CloseReason) void;
    pub fn destroy(self: *Window) void;                          // 强制，不询问
    pub fn setTitle(self: *Window, title: []const u8) void;     // 框架复制
    pub fn invalidate(self: *Window, level: Dirty) void;         // 线程安全
    pub fn ui(self: *Window) *Ui;
    pub fn scale(self: *const Window) f32;
};

// —— 对话框 ——
pub const DialogCode = struct {
    pub const ok: u32 = 1;
    pub const cancel: u32 = 2;
    pub const yes: u32 = 6;
    pub const no: u32 = 7;
    pub const custom_base: u32 = 100;
};
pub const DialogOptions = struct {
    title: []const u8,
    size: ?Size = null,                           // null = 按内容自适应
    resizable: bool = false,
    persist_name: ?[]const u8 = null,             // 仅持久化位置，不持久化尺寸
};
pub const ResultFn = *const fn (ctx: *anyopaque, code: u32) void;
pub const DialogBuildFn = *const fn (ui: *Ui, dlg: *Dialog, ctx: *anyopaque) void;
pub const Dialog = struct {
    pub fn close(self: *Dialog, code: u32) void;                 // 本帧提交后生效
    pub fn result(self: *const Dialog) ?u32;
    pub fn host(self: *const Dialog) *Window;
};
pub const ButtonRole = enum { normal, default, cancel, default_and_cancel };
pub const DialogButton = struct { label: []const u8, code: u32, role: ButtonRole = .normal, enabled: bool = true };
// dialogButtons 是 widgets 模块的自由函数（它使用按钮控件），规范见 10-widgets/dialog.md：
//   pub fn dialogButtons(ui: *Ui, src: std.builtin.SourceLocation, buttons: []const DialogButton) ?u32;

// —— 原生对话框（阻塞；只能在 afterFrame 闭包内调用）——
pub const NativeDialogs = struct {
    // 选项与结果类型全部引用 03：platform.FileDialogOptions、platform.TaskDialogOptions、
    // platform.TaskResult、platform.FontChoice、platform.Path
    pub const Error = error{ NotInAfterFrame, Unsupported, PlatformFailed };
    pub fn openFile(self: *NativeDialogs, owner: *Window, opts: platform.FileDialogOptions, ctx: *anyopaque, cb: *const fn (ctx: *anyopaque, paths: ?[]const platform.Path) void) Error!void;
    pub fn saveFile(self: *NativeDialogs, owner: *Window, opts: platform.FileDialogOptions, ctx: *anyopaque, cb: *const fn (ctx: *anyopaque, path: ?platform.Path) void) Error!void;
    pub fn pickFolder(self: *NativeDialogs, owner: *Window, opts: platform.FileDialogOptions, ctx: *anyopaque, cb: *const fn (ctx: *anyopaque, path: ?platform.Path) void) Error!void;
    pub fn pickColor(self: *NativeDialogs, owner: *Window, initial: Color, ctx: *anyopaque, cb: *const fn (ctx: *anyopaque, color: ?Color) void) Error!void;
    pub fn pickFont(self: *NativeDialogs, owner: *Window, initial: text.Style, ctx: *anyopaque, cb: *const fn (ctx: *anyopaque, style: ?text.Style) void) Error!void;   // 内部经 platform.FontChoice 转换
    pub fn taskDialog(self: *NativeDialogs, owner: *Window, opts: platform.TaskDialogOptions, ctx: *anyopaque, cb: *const fn (ctx: *anyopaque, result: platform.TaskResult) void) Error!void;
};

// —— 命令 ——
// CommandId 与 EditCommand 定义于 08（input.CommandId、input.EditCommand），input 位于 app 之下
pub const CommandId = input.CommandId;
pub const InvokeSource = enum { shortcut, menu, toolbar, programmatic };
pub const CommandState = struct { enabled: bool = true, checked: ?bool = null };
pub const CommandSpec = struct {
    id: []const u8,                               // 稳定字符串标识，框架复制
    title: []const u8,                            // 含助记符，框架复制
    icon: ?theme.Icon = null,                     // 09 的 theme.Icon
    shortcut: ?input.Chord = null,                      // 默认快捷键
    default_state: CommandState = .{},
    handler: *const fn (ctx: *anyopaque, source: InvokeSource) void,
    ctx: *anyopaque,
};
pub const ShortcutMode = enum { reject, steal };
pub const Commands = struct {
    pub const Error = error{ DuplicateCommand, InvalidCommandId, ShortcutConflict, InvalidShortcut, UnknownCommand };
    pub fn register(self: *Commands, spec: CommandSpec) Error!CommandId;
    pub fn find(self: *const Commands, id: []const u8) ?CommandId;
    pub fn invoke(self: *Commands, cmd: CommandId, source: InvokeSource) void;       // 不检查状态
    pub fn shortcutOf(self: *const Commands, cmd: CommandId) ?input.Chord;
    pub fn setShortcut(self: *Commands, cmd: CommandId, chord: ?input.Chord, mode: ShortcutMode) Error!void;
    pub fn resetShortcuts(self: *Commands) void;
    pub fn titleOf(self: *const Commands, cmd: CommandId) []const u8;                // 含 &
    pub fn iconOf(self: *const Commands, cmd: CommandId) ?theme.Icon;
    pub fn formatChord(self: *const Commands, buf: []u8, chord: input.Chord) []const u8;   // REQ-APP-029 本地化格式
    pub fn chordToInvariant(buf: []u8, chord: input.Chord) []const u8;                     // REQ-APP-028 固定格式
    pub fn chordFromInvariant(text: []const u8) error{InvalidShortcut}!input.Chord;
};
// ui 侧：
//   pub fn command(ui: *Ui, cmd: CommandId, state: CommandState) CommandState;     // 构建时声明
//   pub fn invoke(ui: *Ui, cmd: CommandId, source: InvokeSource) void;              // 排入调用队列
//   pub fn commandState(ui: *const Ui, cmd: CommandId) CommandState;               // 本次构建中最近一次 ui.command 声明的状态；未声明时为注册时的 default_state

// —— 设置 ——
pub const Settings = struct {
    pub fn path(self: *const Settings) []const u8;
    pub fn persistent(self: *const Settings) bool;
    pub fn recoveredFromCorruption(self: *const Settings) bool;
    pub fn getBool(self: *const Settings, key: []const u8, default: bool) bool;
    pub fn getInt(self: *const Settings, key: []const u8, default: i64) i64;
    pub fn getFloat(self: *const Settings, key: []const u8, default: f64) f64;
    pub fn getString(self: *const Settings, key: []const u8, default: []const u8) []const u8;
    pub fn setBool(self: *Settings, key: []const u8, value: bool) void;
    pub fn setInt(self: *Settings, key: []const u8, value: i64) void;
    pub fn setFloat(self: *Settings, key: []const u8, value: f64) void;
    pub fn setString(self: *Settings, key: []const u8, value: []const u8) void;   // 框架复制
    pub fn remove(self: *Settings, key: []const u8) void;
    pub fn flush(self: *Settings) void;                                           // 同步写入（若脏）
};

// 界面状态存取（控件使用；窗口名取自所在窗口的 persist_name）
pub const SplitState = struct { mode: enum { ratio, fixed_first, fixed_second }, value: f32 };
pub const TableState = struct { widths: []const f32, order: []const u16, hidden: []const bool, sort_col: ?u16, sort_asc: bool };
pub const UiStateStore = struct {
    pub fn splitter(self: *const UiStateStore, name: []const u8) ?SplitState;
    pub fn setSplitter(self: *UiStateStore, name: []const u8, s: SplitState) void;
    pub fn table(self: *const UiStateStore, arena: std.mem.Allocator, name: []const u8) ?TableState;
    pub fn setTable(self: *UiStateStore, name: []const u8, s: TableState) void;
    pub fn tree(self: *const UiStateStore, arena: std.mem.Allocator, name: []const u8) ?[]const []const u8;
    pub fn setTree(self: *UiStateStore, name: []const u8, expanded: []const []const u8) void;
};
// ui.state_store() 返回所在窗口的 *UiStateStore（无 persist_name 时返回 null）。

// —— 字符串表 ——
pub const KeyNames = struct {
    ctrl: []const u8, alt: []const u8, shift: []const u8, win: []const u8,
    enter: []const u8, esc: []const u8, del: []const u8, ins: []const u8,
    home: []const u8, end: []const u8, pg_up: []const u8, pg_dn: []const u8,
    space: []const u8, tab: []const u8, backspace: []const u8,
    left: []const u8, up: []const u8, right: []const u8, down: []const u8, menu: []const u8,
    function_prefix: []const u8,       // "F"，其后接 1–24
};
pub const Strings = struct {
    ok: []const u8, cancel: []const u8, yes: []const u8, no: []const u8, retry: []const u8,
    close: []const u8, apply: []const u8, save: []const u8, dont_save: []const u8,
    edit_undo: []const u8, edit_redo: []const u8, edit_cut: []const u8, edit_copy: []const u8,
    edit_paste: []const u8, edit_delete: []const u8, edit_select_all: []const u8,
    truncated_tooltip_prefix: []const u8,
    clear: []const u8,                                        // 文本框清除按钮的名称
    severity_info: []const u8, severity_warning: []const u8, severity_error: []const u8, // 标准消息对话框图标的无障碍名称
    key_names: KeyNames,
    pub const zh_cn: Strings;
    pub const en: Strings;
};
```

## 5. 边界与错误情况

| 情况 | 规定 |
|---|---|
| `on_close_request` 返回 `veto` 后宿主又被 `destroy()` | 强制销毁，不再询问；`on_closed` 照常调用 |
| 对话框打开时宿主收到 `app_quit` | 先询问全部窗口（对话框仍在）；全部允许后销毁宿主前先关闭其对话框（取消，不调 `on_result`） |
| 在对话框的构建函数内再 `openDialog` | 允许，新对话框以当前对话框为宿主；链末端启用 |
| `Dialog.close` 在同一帧内调用多次 | 只有第一次的结果码生效 |
| `openDialog` 的宿主已被销毁 | 返回 `error.OwnerDestroyed` |
| 对话框的 `on_result` 内再打开对话框 | 允许（此时宿主已重新启用） |
| 构建函数内直接调用原生对话框 | 调试构建断言中止；发布构建返回 `error.NotInAfterFrame`（REQ-FRAME-027） |
| 原生对话框打开期间用户操作被禁用的 owner | 系统吞掉；本进程其他窗口的输入入队待处理（REQ-APP-022） |
| 命令字符串标识不合法 | `register` 返回 `error.InvalidCommandId`（REQ-APP-023）；调试构建同时断言 |
| 两个窗口声明同一命令的不同状态 | 各窗口各自的快照，互不影响；快捷键查表用接收按键的窗口的快照 |
| 快捷键在处理函数中打开对话框 | 允许；对话框在本帧提交后创建 |
| 设置文件被其他进程同时改写 | 不做跨进程锁；读取时可能得到旧内容，写入以最后一次为准（单实例见待定问题） |
| 设置目录位于只读位置 | `persistent()` 为假，行为按 REQ-APP-038 |
| `persist_name` 含 `/` | 允许（只是字符串），但因控件键用 `/` 连接，建议避免；不作校验 |
| 窗口恢复矩形跨多个显示器或显示器已拔除 | 由 03 的 `validatePlacement` 判定（REQ-APP-015） |
| 系统时钟回拨导致备份文件名重复 | 追加 `-1`、`-2` 序号 |
| 去抖期间进程被强杀 | 最近 ≤ 5 s 的变更可能丢失；这是已接受的取舍，崩溃处理见待定问题 |
| 在构建函数内调用 `app.quit` | 视为编程错误，调试构建断言；改在激活类结果的处理中用 `afterFrame` 或命令处理函数调用 |
| 休眠恢复后图形上下文丢失 | 由 04 处理；本文只保证触发整根重绘与重建请求 |

## 6. 验收标准

除特别注明外，以下测试在降级后端上以无头方式运行，使用假平台层、假时钟、可注入的文件系统与假系统度量。

**AC-APP-001**　`[单元]` 覆盖：REQ-APP-001、REQ-APP-002。步骤：对 `AppId` 依次传入 `("Acme","Tool")`、`("","Tool")`、`("Acme","")`、含 `/` 的名称、含 `:` 的名称、以点结尾的名称、65 字节名称、`("CON","x")`、`("acme","nul")`。预期：仅第一个成功，其余均返回 `error.InvalidAppId`。`init` 成功后：未创建任何窗口，线程计数（AC-ARCH-004 的包装器）为 0，标准编辑命令已注册（`find("edit.copy")` 非空）。

**AC-APP-002**　`[回放]` 覆盖：REQ-APP-003、REQ-APP-004、REQ-APP-005。步骤与预期：① 创建窗口 A、B（A 先创建），A 的 `on_close_request` 返回 `veto`，调用 `quit(7)`：询问顺序为 B、A（创建逆序）；A 否决后退出取消，B 与 A 均**未**被销毁，退出码记录被清除，`run` 仍在运行；把 A 改为 `allow` 后再 `quit(7)`：两窗口都被询问后才被销毁，`run` 返回 7。② 默认策略下关闭最后一个窗口，`run` 返回 0；`explicit` 策略下关闭最后一个窗口后 `run` 仍在运行，调用 `quit(3)` 后返回 3。③ 隐藏窗口仍计为存活：`when_last_window_closes` 下仅剩一个隐藏窗口时应用不退出。④ 对话框不计入顶层窗口数。⑤ 在构建函数内调用 `quit` 于调试构建断言中止。⑥ 退出时若设置为脏，`run` 返回前恰写入 1 次，写入发生在窗口销毁之后。

**AC-APP-003**　`[单元]` 覆盖：REQ-APP-006。步骤与预期：工作线程回投 1 000 个闭包，界面线程记录序号，严格递增且全部执行；闭包在其入队同一轮的帧之前执行（阶段日志）；`wake()` 在无脏标记时不产生帧（帧计数不变）；进入退出流程后 `post` 返回 `false` 且闭包未执行；`post` 成功后闭包函数释放 `ctx`（泄漏检测无报告），`post` 失败后由调用方释放（无泄漏、无二次释放）。

**AC-APP-004**　`[回放]` 覆盖：REQ-APP-007、REQ-APP-008、REQ-APP-039。示例：点击"计算"按钮，创建工作线程睡眠 200 ms（假时钟推进）后写结果并 `post` 完成闭包。预期：点击帧构建遍数 = 2 且模型 `busy` = 真；工作线程运行期间帧数为 0（无轮询）；完成闭包执行后恰好 1 帧，界面显示结果；工作线程内调用 `ui.invalidate` 或 `app.invalidateAll` 在调试构建断言中止（线程检查，REQ-ARCH-009）；在工作线程调用 `Window.invalidate(.build)` 合法，产生 1 帧；应用在任务进行中调用 `quit`：取消标志被置位、线程被 `join` 后 `run` 才返回，泄漏检测无报告。

**AC-APP-005**　`[回放]` 覆盖：REQ-APP-008。两个窗口 A、B 共享模型。步骤：`app.invalidateAll(.build)` → A、B 各 1 帧；只在 A 内点击 → B 帧数不变；在工作线程调用 `A.invalidate(.paint)` → A 产生 1 帧、构建遍数 0、B 无帧。

**AC-APP-006**　`[单元]` 覆盖：REQ-APP-009、REQ-APP-010、REQ-APP-011。步骤与预期：用 `title`="T1" 创建窗口后改写调用方的原缓冲，窗口标题不变（框架复制）；`min_size`=(300,40) 且根节点最小期望尺寸 (216,48) 时有效最小尺寸 = (300,48)；`on_closed` 在 `destroy()` 后恰好调用 1 次；`ctx` 在每次构建与每个回调中都是创建时传入的指针；`hide()` 后 `Ui` 状态槽保留，`show()` 后 `sticky` 槽的内容仍在；两个窗口使用相同 `persist_name` 时第二次 `createWindow` 返回 `error.DuplicatePersistName`；`visible = false` 创建的窗口不产生帧直至 `show()`。

**AC-APP-007**　`[回放]` 覆盖：REQ-APP-012。步骤与预期：窗口有"已修改"标志。① 用户点关闭按钮：`on_close_request` 以 `user` 调用，返回 `veto` 并 `openDialog`（保存/不保存/取消）；窗口仍存活、被禁用。② 对话框选"不保存"→ `on_result` 内调用 `destroy()`，`on_closed` 1 次，`run` 随之按策略结束；选"取消"→ 窗口恢复可用。③ `quit` 引发的请求 `reason = app_quit`；`WM_QUERYENDSESSION` 引发的 `reason = session_end`，且只询问、不销毁。④ 窗口有对话框时 `quit`：先询问宿主（对话框仍在），全部允许后对话框先于宿主被关闭（结果码为取消，`on_result` 未调用），再销毁宿主。⑤ `on_close_request` 为空时等同 `allow`。

**AC-APP-008**　`[回放]` 覆盖：REQ-APP-013。创建窗口 A、B，各自独立的构建函数与焦点。步骤与预期：A 中聚焦文本框，B 中点击按钮，两窗口的焦点节点互不影响；A、B 的缩放系数设为 1.0 与 1.5（假），同一 `fixed(100)` 节点在 A 为 100 ppx、在 B 为 150 ppx；A 的状态槽在 B 中不可见；两窗口共享同一个 `app.commands`（在 A 注册的命令在 B 的快捷键查表中可见）。

**AC-APP-009**　`[单元]` 覆盖：REQ-APP-014、REQ-APP-037。窗口 `persist_name`="main"。步骤与预期：假平台层的 `getPlacement()` 返回 `{normal_rect=(100,80,900,600), state=normal, dpi=96}`，模拟移动结束 → 设置存储 `ui.windows.main` = `{x:100,y:80,w:900,h:600,dpi:96,maximized:false}`，置脏；最大化 → `maximized:true` 且 `x/y/w/h` 仍为还原矩形；窗口移到 dpi=144 的显示器后保存 → `dpi:144`；关闭（允许）→ 写入；`persist_name` 为空的窗口不产生 `ui.windows` 条目。

**AC-APP-010**　`[单元]` 覆盖：REQ-APP-015。假平台层：单显示器，工作区 (0,0,1920,1040)，dpi 96，`validatePlacement` 使用 03 的真实规则。步骤与预期（均检查传给 `createWindow` 的 `NativeWindowOptions.placement` 与客户区尺寸）：① 无记录 → `placement` 为空，`client_size` = `WindowOptions.size`。② 记录 `{x:100,y:80,w:900,h:600,dpi:96}` → 校验后不变。③ 记录 `{x:1500,y:80,w:900,h:600,dpi:96}`：交集 420×600，占 46.7% ≥ 25% 且标题栏在工作区内 → 位置不变。④ 记录 `{x:1800,y:80,w:900,h:600,dpi:96}`：交集占 13.3% < 25% → 位置被丢弃（`placement` 位置为系统默认），尺寸保持 900×600。⑤ 记录 `{x:100,y:1030,...}`：标题栏不在工作区内 → 丢弃位置。⑥ 记录 `{x:100,y:80,w:1350,h:900,dpi:144}` 在 dpi 96 的显示器上 → 尺寸换算为 900×600，位置 (100,80) 不变。⑦ 记录 `{x:0,y:0,w:3000,h:2000,dpi:96}` → 尺寸钳制为 1920×1040。⑧ `maximized:true` → `state = maximized`。⑨ 字段缺失（无 `w`）、`w` 为字符串、`w` ≤ 0 → 整条忽略并按 ① 处理，不报错、不调用 `validatePlacement`。11 的源码中不存在任何对工作区矩形的算术（静态扫描）。

**AC-APP-011**　`[回放]` 覆盖：REQ-APP-016、REQ-APP-017、REQ-APP-018。步骤与预期：在宿主 H 的 `clicked` 分支内（经 `afterFrame` 或直接）`openDialog`；`openDialog` 在对话框关闭之前返回（调用栈中不存在嵌套消息循环：用平台层桩计数 `GetMessage` 嵌套深度，始终 ≤ 1）；打开期间 H 被禁用（桩记录 `EnableWindow(H,false)`），H 的输入事件无处投递，但 `H.invalidate` 仍能产生帧；对话框内点击"确定"→ `dlg.close(DialogCode.ok)` 在本帧提交后生效；顺序为 先 `EnableWindow(H,true)` 再销毁对话框窗口；`on_result(ctx, 1)` 恰好调用 1 次，且发生在对话框的帧之外；用 `dialog.result()` 轮询：关闭前 `null`，关闭后 `1`；用标题栏关闭按钮关闭：有取消按钮 → 该按钮收到 `activate(cancel_button)`，无取消按钮 → 结果码 2；宿主已销毁时不调用 `on_result`。宿主此前打开的菜单弹出层的 owner 在 `openDialog` 当帧收到 `popup_dismissed(dialog_opened)`。对话框链：对话框 D1 内再开 D2，D1 被禁用、D2 启用；D2 关闭后 D1 启用。

**AC-APP-012**　`[单元]` 覆盖：REQ-APP-019。步骤与预期：`size = null`，内容根期望尺寸 (320,140) lpx，`pad_dialog` 12 → 客户区 (344,164)；内容增加一行使期望高度变为 180 → 客户区高度变为 204，窗口左上角不动；窗口初始居中于宿主（宿主矩形 (100,100,800,600)，对话框 344×164 → 左上角 (328,318)，不超出工作区）；无最小化/最大化按钮（样式位断言）；`resizable = false` 时用户无法缩放；对话框不继承宿主的快捷键源（宿主绑定 `Ctrl+S` 的命令在对话框中按 `Ctrl+S` 不被调用）；有效最小尺寸生效。

**AC-APP-013**　`[回放]` 覆盖：REQ-APP-020。步骤与预期：`dialogButtons` 传入 `[保存(default), 不保存, 取消(cancel)]`，对话框客户区宽 344、内边距 12：三个按钮从左到右按声明顺序，右缘距客户区右边缘 12 lpx，间距 `gap_md`（8）；按 Enter（焦点在文本框）→ 返回保存的 `code`；按 Esc → 返回取消的 `code`；对话框首次构建后焦点在第一个 Tab 停靠点（文本框，内容被全选，由选区断言）；无文本框时焦点在默认按钮；声明两个 `default` 按钮在调试构建断言；返回值只在被点击的那一帧非空。

**AC-APP-014**　`[单元]` 覆盖：REQ-APP-021、REQ-APP-022。步骤与预期：在构建函数内调用 `app.native.openFile` → 调试构建断言中止；发布构建返回 `error.NotInAfterFrame`。在 `afterFrame` 闭包内调用：回调收到假平台层返回的路径数组（`multi`）或 `null`（取消）；回调返回后产生 1 个 `build` 帧。假平台层在原生对话框"阻塞"期间注入：一个宿主窗口尺寸变化、一个 `WM_PAINT`、一次对宿主的鼠标点击、三个 `post` 闭包 → 期间帧调用深度计数始终 ≤ 1（不重入）；尺寸变化产生 1 个 `layout` 帧且损伤为整根；`WM_PAINT` 产生 1 个纯绘制帧（构建遍数 0）；鼠标点击未进入任何节点的收件列表；三个闭包在期间未执行，闭包返回后按序执行。`pickFont` 的回调收到的是 `text.Style`（由 `FontChoice{family="Segoe UI", size_lpx=12, weight=400, italic=false}` 转换而来，字段逐项对应）；`taskDialog` 的回调收到 `TaskResult`（`button` 为被关闭时 `null`）。降级后端对 `pickFont` 返回 `error.Unsupported`。

**AC-APP-015**　`[单元]` 覆盖：REQ-APP-023。步骤与预期：注册 `file.save` 成功；再次注册返回 `error.DuplicateCommand`；标识 `File.Save`、`a..b`、`a b`、空串、65 字节、`.a` 均返回 `error.InvalidCommandId`；`find("file.save")` 得到同一 `CommandId`；`titleOf` 返回含 `&` 的原标题；`CommandId` 句柄不出现在设置文件中（持久化内容只含字符串标识）。

**AC-APP-016**　`[回放]` 覆盖：REQ-APP-024、REQ-APP-025。前置：命令 `file.save`（`Ctrl+S`）；窗口 A 的构建函数在 `model.dirty` 为假时声明 `{enabled=false}`、为真时声明 `{enabled=true}`；窗口含菜单项与工具栏按钮均绑定该命令。步骤与预期：`dirty=false` 时菜单项与工具栏按钮均为禁用外观，按 `Ctrl+S` 被吞掉、处理函数调用次数 0；修改模型并 `invalidate` 后，两处同时变为启用（同一帧，来自同一声明），按 `Ctrl+S` 调用 1 次；工具栏按钮提示框文本为"保存 (Ctrl+S)"（去助记符），无快捷键的命令只有标题；命令 `view.grid` 声明 `checked=true` 时菜单项显示勾选，未声明时取 `default_state`；窗口 B 未声明 `file.save` → B 中该命令取 `default_state`（启用），不受 A 影响。

**AC-APP-017**　`[回放]` 覆盖：REQ-APP-026。步骤与预期：① 快捷键：`Ctrl+S` 的处理函数在该帧的分发阶段被调用（早于构建，阶段日志），置 `build` 脏，该帧构建遍数 = 1，调用次数 = 1。② 菜单点击：`ui.invoke` 排队，处理函数在第一构建遍结束后、第二构建遍之前执行，第二遍已反映模型变化（界面无一帧滞后，同 AC-FRAME-018 的判据），构建遍数 = 2。③ 处理函数内再次 `ui.invoke` 另一命令：同一排空循环内执行；构造 9 层嵌套 → 第 9 层在调试构建断言。④ 对禁用命令 `ui.invoke` → 不执行，调试构建 `warn` 1 条；`app.commands.invoke(cmd, .programmatic)` 不检查状态，执行 1 次。⑤ 处理函数调用 `app.quit(0)` 与 `openDialog` 均正常。

**AC-APP-018**　`[单元]` 覆盖：REQ-APP-027、REQ-APP-028。前置：`file.save` 默认 `Ctrl+S`，`file.save_all` 默认 `Ctrl+Shift+S`。步骤与预期：`setShortcut(save, Ctrl+Shift+S, .reject)` → `error.ShortcutConflict`（占用者为 `file.save_all`）；`.steal` → 成功，`save_all` 变为未绑定；`setShortcut(save, null, …)` → 未绑定，按键被放行（不再吞）；`Shift+A`、仅修饰键、`Ctrl+Shift`（无主键）→ `error.InvalidShortcut`；`F5`、`Ctrl+A`、`Shift+F5` 可设置。持久化：`ui.shortcuts` = `{"file.save":"Ctrl+Shift+S","file.save_all":""}`，与默认相同的条目不写入；重启（重新创建 `App`，读入该文件）后绑定保持；文件中含不存在的命令、非法和弦 `"Ctrl+Foo"`、冲突条目 → 各被忽略并各 1 条 `warn`，其余条目仍生效。`resetShortcuts()` 恢复默认并移除这些条目。

**AC-APP-019**　`[单元]` 覆盖：REQ-APP-029。`formatChord`：`{S,ctrl+shift}` → `Ctrl+Shift+S`；`{F5}` → `F5`；`{delete}` → `Del`；`{enter,alt}` → `Alt+Enter`；`{left,ctrl+alt+shift+win}` → `Ctrl+Alt+Shift+Win+Left`；`{page_down,ctrl}` → `Ctrl+PgDn`；`{d1,ctrl}` → `Ctrl+1`；`{space,shift}` → `Shift+Space`；`{escape}` → `Esc`；`{apps}` → `Menu`；`{f1}` → `F1`，`{f24}` → `F24`，`{f12,ctrl}` → `Ctrl+F12`。用自定义 `Strings`（`ctrl`="控制"）后输出 `控制+S`，而 `chordToInvariant` 仍为 `Ctrl+S`。`chordFromInvariant("ctrl+shift+s")` 与 `"Ctrl+Shift+S"` 得到同一和弦；`"Ctrl+"`、`"Foo"`、空串 → `error.InvalidShortcut`；往返 `parse(format(c)) == c` 对全部可绑定和弦成立。

**AC-APP-020**　`[回放]` 覆盖：REQ-APP-030。前置：窗口含单选列表 LI（`EditCaps{copy=true, select_all=true}`）、文本框 T（预占 `Ctrl+C/V/X/A/Z/Y`，`EditCaps` 随选区与撤销栈而变）、编辑菜单项绑定 `edit.*`。步骤与预期：焦点在 LI：菜单"复制""全选"启用，"粘贴""撤销"禁用；`Ctrl+C` 由快捷键表命中 `edit.copy` 并向 LI 投递 `edit_command{copy}`（T 的预占不适用）；`Ctrl+V` 命中但禁用 → 被吞掉，LI 无事件；焦点在 T 且无选区：复制/剪切禁用、全选启用；有选区后复制启用（同一帧菜单项状态随之改变）；焦点在 T 时 `Ctrl+C` 由 T 预占，事件是 `key_down` 而非 `edit_command`，而菜单点击"复制"产生 `edit_command{copy}`，两种路径结果一致；右键弹出的上下文菜单打开期间，"复制"仍作用于宿主焦点的 T；无焦点节点时全部禁用；`edit.delete` 无默认快捷键。

**AC-APP-021**　`[单元]` 覆盖：REQ-APP-031。使用假环境变量与假文件系统。步骤与预期：Win32 路径解析（桩）：`APPDATA`=`C:\Users\u\AppData\Roaming` → 路径 `C:\Users\u\AppData\Roaming\Acme\Tool\settings.json`；Linux：`XDG_CONFIG_HOME`=`/h/.config2` → `/h/.config2/Acme/Tool/settings.json`；未设置 → `$HOME/.config/Acme/Tool/settings.json`；设为空串 → 同未设置。首次写入前目录不存在，写入后递归创建；文件无 BOM。

**AC-APP-022**　`[单元]` 覆盖：REQ-APP-032、REQ-APP-036。步骤与预期：写出的文件顶层含 `format`=1、`app_version`=1、`app`、`ui`；读入含未知顶层键 `"x_future":{"a":1}` 的文件后写出，该键原样保留；`format` 小于当前（构造的 0 版本文件，内建迁移把 `ui.shortcut_map` 改名为 `ui.shortcuts`）→ 迁移后 `format`=1；`app_version`=1 的文件、`settings_version`=3：`settings_migrate` 恰好调用 1 次，参数 `(from=1,to=3)`，钩子写入的新键存在，写出文件的 `app_version`=3；`app_version`=5 大于 3：不调用钩子，文件中 5 保持；钩子返回错误 → 原文件改名为备份、默认值启动、`recoveredFromCorruption()` 为真。

**AC-APP-023**　`[单元]` 覆盖：REQ-APP-033。可注入故障的假文件系统。步骤与预期：正常写入：先出现 `settings.json.tmp`，最后只剩 `settings.json`，替换为单步原子操作（桩记录 `MoveFileExW` 标志含 `REPLACE_EXISTING|WRITE_THROUGH`）；故障一：写临时文件中途失败（磁盘满）→ 原文件内容逐字节不变，临时文件被删除，仍为脏，`warn` 1 条；故障二：重命名失败 → 同上；故障后下一次变更成功写入并清除脏标记；同一原因连续失败 10 次，`warn` 日志不超过 1 条；写入过程中读取原文件始终得到完整的旧内容。

**AC-APP-024**　`[单元]` 覆盖：REQ-APP-034。假时钟，假文件系统计写入次数。步骤与预期：t=0 变更一次 → t=499 写入 0 次，t=500 写入 1 次。t=0、300、600 各变更一次 → 写入发生在 t=1100，共 1 次。每 100 ms 变更一次共 6 000 ms（t=0..6000）→ 写入发生在 t=5000（首次变脏起 5000 ms）与 t=6500，共 2 次。干净状态下 `flush()` 不写入；脏状态下 `flush()` 同步写入 1 次。`App.run` 退出前脏则写入 1 次（写入发生在窗口销毁之后）；`WM_ENDSESSION`(TRUE) 同步写入。去抖期间主循环的阻塞等待超时恰为剩余时间（帧数为 0，无轮询唤醒）。

**AC-APP-025**　`[单元]` 覆盖：REQ-APP-035。分别构造文件：`{ not json`；`[]`；`{}`（缺 `format`）；`{"format":"1"}`；`{"format":99}`；空文件；以及不存在。预期：前六种均被改名为 `settings.json.bad-<时间>`（假 UTC 时钟 2026-01-02 03:04:05 → `settings.json.bad-20260102-030405`），以默认值启动，`recoveredFromCorruption()` = 真，`warn` 1 条；不存在的文件不产生备份、`recoveredFromCorruption()` = 假。连续制造 5 次损坏 → 目录下备份仅剩最新 3 个；同一秒内两次损坏 → 第二个备份名追加 `-1`。首次写入后得到合法的新文件。

**AC-APP-026**　`[回放]` 覆盖：REQ-APP-037。窗口 `persist_name`="main"，含分隔条（`persist`="side"）、表格（`persist`="files"）。步骤与预期：首次运行无记录 → 使用代码默认值；拖动分隔条释放 → `ui.splitters["main/side"]` = `{mode:"ratio",value:0.3}`（以拖动后的值）并置脏；点击表头排序、拖动列宽、拖动列重排 → `ui.tables["main/files"]` 含 `widths`、`order`、`sort`；重启后控件首次出现时读取并应用；记录中比例为 1.5（越界）→ 忽略并用默认值；列数与表格不符 → 忽略；窗口无 `persist_name` 或控件无 `persist` → 不产生任何条目；设置文件中不出现任何形如 `WidgetId` 的数值字段（AC-FRAME-004 的联合判据）；未被引用的旧条目保持不删。

**AC-APP-027**　`[单元]` 覆盖：REQ-APP-038。步骤与预期：`setInt("editor.font_size", 14)` 后 `getInt` = 14，文件 `app.editor.font_size` = 14；`getBool` 读取整数键 → 返回默认值并记录 1 条 `warn`；`setString` 复制入参（改写原缓冲不影响）；`getString` 的返回值在下一次 `set*` 后不保证有效（调试构建下该内存被毒化）；`remove` 后 `getInt` 返回默认值；在工作线程调用访问器 → 调试构建断言；目录只读：`persistent()` = 假，`set*` 后 `get*` 仍可读到，写入失败仅 1 条 `warn`。

**AC-APP-028**　`[单元]` 覆盖：REQ-APP-040、REQ-APP-041。静态检查与运行检查：示例应用的模型类型满足"每个变更方法结尾调用 `changed()`"（扫描脚本检查示例目录）；示例的构建函数中不存在对 `invalidate`/`invalidateAll` 的无条件调用、不使用 `ui.timer` 做变更检测（扫描）；运行"控件总览"页以 `-Dforce-rebuild=true` 与关闭时各执行同一回放，逐帧画面一致（二者不同即暴露遗漏通知）；一次批量变更 100 个元素后只调用 1 次 `changed()` → 1 帧。反例夹具：构建函数无条件 `invalidate` → 8 帧后出现失效风暴 `warn`（AC-FRAME-019）。

**AC-APP-029**　`[单元]` 覆盖：REQ-APP-042。步骤与预期：系统语言首项 `zh-CN` / `zh-Hans-CN` / `zh-SG` → 简体中文表（`ok`="确定"，`cancel`="取消"）；`en-US`、`fr-FR`、`zh-TW` → 英文表（`ok`="OK"）；GLFW 后端 `LANG=zh_CN.UTF-8` → 中文，`C` → 英文；两份表的每个字段非空（编译期 + 单元断言）；`app.setStrings` 用自定义表后对话框的"取消"按钮与编辑菜单项文字立即随之改变（下一次构建）；注入 `system_changed{locale}`（系统语言由 `en-US` 变为 `zh-CN`）使未固定的表重新选择并置 `build` 脏，已固定（`AppOptions.strings` 非空）的表不变。扫描控件源码，不存在中文或英文用户可见文字字面量（除 `Strings` 的定义文件外）。

**AC-APP-030**　`[单元]` 覆盖：REQ-APP-043。假命令行 `tool.exe "C:\a b\c.txt" --flag 文件`：`args()` = `["tool.exe","C:\a b\c.txt","--flag","文件"]`（UTF-8），首项为可执行文件路径；切片在应用整个存活期有效；框架不对 `--flag` 作任何解释（无副作用）。

**AC-APP-031**　`[回放]` 覆盖：REQ-APP-044。假平台层注入 `session_ending{logoff=true}`。步骤与预期：两个窗口都允许 → 同一轮事件处理内假平台层收到 `allowSessionEnd(true)` 恰好 1 次，两窗口各被询问一次，`reason = session_end`，期间未显示任何新窗口，窗口**未**被销毁；其中一个否决 → 收到 `allowSessionEnd(false)`，询问按创建逆序进行并在遇到否决时停止，所有窗口保持原状。随后注入 `session_ended`：设置同步落盘 1 次、`on_session_end` 调用 1 次、不再产生帧、进程结束；未注入 `session_ended`（用户取消注销）→ 无任何动作，应用继续运行。

**AC-APP-032**　`[回放]` 覆盖：REQ-APP-045。含动画与两个窗口的应用。假平台层注入 `power_resume` 事件（连续注入两次系统恢复通知时 03 只产出一个）。预期：两个窗口各产生 1 帧，损伤为整根，构建遍数 ≥ 1；活动动画直接到达目标值；渲染层桩收到 1 次"检查/重建上下文"请求；未收到恢复事件时无此类帧。

**AC-APP-033**　`[人工]` 覆盖：REQ-APP-016、REQ-APP-017、REQ-APP-021、REQ-APP-022、REQ-APP-031、REQ-APP-044。在真实 Windows 10 与 Windows 11 上执行：(1) 打开应用内模态对话框，尝试点击、键盘操作宿主窗口，并拖动对话框到宿主之外；(2) 在对话框打开时打开任务管理器再切回；(3) 调用原生"打开文件"对话框，在其打开期间拖动窗口、缩放宿主；(4) 在 `%APPDATA%` 下查看设置文件的路径与内容；(5) 注销/关机时保持一个有未保存更改的窗口。观察要点：宿主在对话框期间无法被操作、标题栏呈现非激活外观但内容可重绘；关闭对话框后激活回到宿主且没有窗口闪烁到后台；原生对话框期间宿主缩放后内容正确重绘；文件路径为 `%APPDATA%\<厂商>\<应用>\settings.json`；会话结束时被否决的窗口使系统出现"此应用阻止注销"之类提示（具体样式以系统为准）。

## 7. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-APP-01 | 崩溃处理：未处理异常/panic 时是否写出转储、是否尝试保存设置 | 当前不在范围；M6 前评估（仅考虑最小化的 `panic` 钩子写日志并同步落盘设置） |
| OPEN-APP-02 | 单实例：第二个实例启动时的转发与激活已有窗口（命名互斥体 + 窗口消息/命名管道） | 当前不在范围；需要时作为独立文档 |
| OPEN-APP-03 | 自动更新 | 当前不在范围 |
| OPEN-APP-04 | 会话结束（`session_end`）下无法显示"未保存"对话框；是否提供 `ShutdownBlockReasonCreate` 封装以向系统说明阻止原因 | 先不做，由应用自行决定自动保存 |
| OPEN-APP-05 | 设置文件是否支持跨进程并发写入的保护（文件锁） | 随单实例问题一并决定 |
| OPEN-APP-06 | 托盘图标与通知的 API（`explicit` 退出策略的配套）归属 03 还是本文 | 倾向放入 03 的平台接口，本文仅规定与退出策略的配合 |
| OPEN-APP-07 | 设置文件备份保留数（3）与去抖最长等待（5000 ms）是否需要可配置 | 当前写死；有实际需求再开放 |
