# 02 架构

## 1. 范围

定义模块划分、依赖方向、线程模型、内存策略与错误处理约定。各模块的内部规范见对应文档。

## 2. 术语

| 术语 | 定义 |
|---|---|
| 界面线程 | 创建窗口并运行消息循环的线程。全部框架 API 默认只能在此线程调用。 |
| 工作线程 | 应用自行创建的其他线程。 |
| 回投 (post) | 工作线程把一个闭包或消息排入界面线程队列并唤醒它。 |
| 持久分配器 | 生命周期跨帧的通用分配器。 |

## 3. 规范条款

### 3.1 分层与模块

```
┌──────────────────────────────────────────────────────────┐
│ 应用 (app code)        构建函数、模型、命令处理              │
├──────────────────────────────────────────────────────────┤
│ app      应用生命周期、窗口管理、命令、设置          (11)   │
│ widgets  全部控件                                 (10)   │
├──────────────────────────────────────────────────────────┤
│ ui       帧模型：ID、状态存储、节点树、脏标记、动画   (06)   │
│ layout   测量与排布                                (07)   │
│ input    命中测试、路由、焦点、快捷键               (08)   │
│ theme    令牌表与控件绘制基元                       (09)   │
├──────────────────────────────────────────────────────────┤
│ gfx      绘制接口、绘制列表、图像、图层             (04)   │
│ text     字体、排版、度量、字形图集                 (05)   │
├──────────────────────────────────────────────────────────┤
│ platform 窗口、消息、输入法、剪贴板、对话框、时钟    (03)   │
│   ├─ win32   一等后端                                     │
│   └─ glfw    降级后端                                     │
├──────────────────────────────────────────────────────────┤
│ core     数学、矩形、颜色、哈希、容器、分配器、日志、埋点    │
└──────────────────────────────────────────────────────────┘
  third_party: nanovg, glfw(仅 Linux), stb_image
```

**REQ-ARCH-001**　模块依赖**必须**单向向下：上层可以依赖下层，下层**不得**导入上层。同层模块之间允许的依赖按下列固定次序，只能由后者依赖前者：中间层 `theme` ← `layout` ← `input` ← `ui`（即 `layout` 可用 `theme` 的令牌类型，`input` 可用 `layout` 的几何与方位类型，`ui` 可用三者）；上层 `widgets` ← `app`；底层 `gfx` ← `text`（提交图集纹理）。反方向一律不允许。因此 `theme` 的绘制基元只能依赖 `gfx` 与自身的类型，不得引用 `ui` 的 `PaintCtx`/`Node`。

**REQ-ARCH-002**　`core` **不得**依赖任何其他模块与任何操作系统 API（时钟、文件等经由 `platform` 注入）。

**REQ-ARCH-003**　NanoVG 与 OpenGL 的符号**必须**只出现在 `gfx` 与 `text` 的后端实现文件中。Win32 API 与 GLFW 的符号**必须**只出现在 `platform` 的对应后端及 `text` 的 DirectWrite 后端中。

**REQ-ARCH-004**　后端选择**必须**在编译期完成（按目标操作系统），不存在运行时的后端虚表分发。`platform`、`text` 的公共接口是一个在编译期解析到具体后端的命名空间。

**REQ-ARCH-005**　`widgets` 中的每个控件**必须**只通过 `ui`、`layout`、`input`、`theme`、`gfx`、`text` 的公开接口实现，不得访问这些模块的内部状态。检验标准：应用可以用同样的公开接口写出与内建控件同等能力的自定义控件。

**REQ-ARCH-006**　源码目录**必须**与模块一一对应：`src/<模块>/`，模块的公开接口集中在 `src/<模块>.zig`（或 `src/<模块>/root.zig`）再导出，外部只导入该文件。

### 3.2 线程模型

**REQ-ARCH-007**　框架是单线程的：窗口创建、消息循环、构建、布局、绘制、全部控件 API **必须**在界面线程上执行。框架自身**不得**创建任何后台线程（操作系统在内部创建的线程不计）。

**REQ-ARCH-008**　允许从工作线程调用的 API 是一个封闭清单，且**必须**在签名文档中标注"线程安全"：
- `app.post(...)`：回投闭包到界面线程。
- `app.wake()`：仅唤醒界面线程。
- `Window.invalidate(...)`：等价于回投一次失效。
- `core.log` 的写入。
- `platform.wake`、`platform.fatal`。
- `gfx.decode`：无全局状态的纯函数，供工作线程解码图像后回投像素（04）。

**REQ-ARCH-009**　调试构建中，非线程安全 API **必须**在入口断言当前线程为界面线程，违反时以明确信息中止。

**REQ-ARCH-010**　回投队列**必须**是无界多生产者单消费者队列；回投的闭包按入队顺序在界面线程的消息循环中执行，且在同一轮内先于该轮的帧。

### 3.3 内存

**REQ-ARCH-011**　框架**不得**使用全局隐式分配器。所有需要分配的入口显式接收分配器或从所属上下文（`App`、`Window`、`Ui`）取得。

**REQ-ARCH-012**　分配器按生命周期分为四类，使用场合**必须**符合下表：

| 分配器 | 生命周期 | 用途 | 释放方式 |
|---|---|---|---|
| 帧竞技场 | 一帧 | 事件列表、临时字符串、布局与绘制的中间量 | 帧开始时整体重置（保留容量） |
| 树竞技场（双份） | 一次构建到下一次构建 | 节点树及其属性数据。当前树在两次构建之间保持有效，供纯绘制帧、纯布局帧与命中测试使用；旧树保留到新构建完成，供差分 | 每次构建开始时两份互换，并重置将要写入的那份 |
| 状态存储池 | 控件存活期 | 状态槽、保留节点 | 槽回收时释放 |
| 持久分配器 | 应用存活期 | 窗口、图集、字体、缓存、设置 | 显式释放 |

**REQ-ARCH-013**　稳定状态下（界面结构不变的连续帧），一帧内对持久分配器与状态存储池的分配次数**必须**为 0。帧竞技场与树竞技场在达到稳定容量后**不得**再向操作系统申请内存。

**REQ-ARCH-014**　所有缓存（排版、度量、图像、字形图集）**必须**有显式容量上限与淘汰策略，并在埋点中暴露当前占用。

**REQ-ARCH-015**　调试构建**必须**使用带泄漏检测的持久分配器，应用正常退出时有泄漏即以非零码退出并打印分配点。

**REQ-ARCH-016**　字符串在 API 边界**必须**是 UTF-8 的 `[]const u8`。向 Win32 传递前在 `platform` 内部转换为 UTF-16，转换缓冲取自帧竞技场或栈。框架不保存调用方传入切片的引用超过当前帧，除非签名注明"框架复制"或"调用方须保证存活"。

### 3.4 错误处理

**REQ-ARCH-017**　错误分三类处理：

| 类别 | 例子 | 处理 |
|---|---|---|
| 编程错误 | ID 冲突、在错误线程调用、未配对的 begin/end、越界 | 调试构建断言中止；发布构建按文档规定的安全退化继续 |
| 可恢复的环境错误 | 文件不存在、剪贴板被占用、图像解码失败 | 以 Zig 错误联合返回给调用方 |
| 不可恢复的环境错误 | GL 上下文创建失败、内存耗尽 | 通过 `platform.fatal` 显示系统消息框并退出，退出码非零 |

**REQ-ARCH-018**　构建函数内调用的控件 API **不得**返回错误联合（否则应用代码将充满 `try`）。控件内部遇到的可恢复错误**必须**退化为可见的占位表现（如缺失图像显示占位框）并记录一次日志；内存耗尽按不可恢复处理。

**REQ-ARCH-019**　每个公开错误集**必须**是显式列举的具名集合，不使用 `anyerror`。

### 3.5 日志与埋点

**REQ-ARCH-020**　`core.log` **必须**提供 `err/warn/info/debug` 四级，带模块标签，输出目的地可由应用设置；默认调试构建输出到标准错误与 `OutputDebugString`，发布构建只保留 `err/warn`。

**REQ-ARCH-021**　`core.stats` **必须**提供命名的计数器（单调递增）、计量（可设为任意当前值，如缓存字节数）与计时器，供 12 的预算测量与 `[计量]` 验收读取。计时器在启用时**必须**保留逐次样本，可按名字取出，以支持分位数统计。发布构建中计数器与计量保留，细粒度计时器可编译期关闭；基准构建（`zig build bench`）中计时器**必须**全部启用。

### 3.6 构建配置

**REQ-ARCH-022**　`build.zig` **必须**提供以下步骤与选项（名称冻结）：

| 名称 | 作用 |
|---|---|
| `zig build` | 构建库与全部示例（本机目标） |
| `zig build -Dtarget=x86_64-windows-gnu` | 交叉编译 Windows 目标 |
| `zig build run-<示例名>` | 运行示例 |
| `zig build test` | 运行单元测试 |
| `zig build test-golden` | 运行金图测试（无头） |
| `zig build test-replay` | 运行输入回放测试 |
| `zig build bench` | 运行基准场景并输出预算对照表 |
| `zig build check-docs` | 运行文档一致性检查 |
| `-Dtext-backend=<名>` | 选择文字后端：`directwrite`/`fontstash`/`fixed`（05）。`zig build test` 默认 `fixed`，其余默认随平台 |
| `-Dforce-rebuild=true` | 调试开关：每帧强制构建脏（ADR 0006） |
| `-Dshow-damage=true` | 调试开关：以色块闪烁标出损伤矩形 |

两个调试开关在测试夹具中另有等价的运行期选项（13），以便同一测试二进制内对比两种模式；幂等校验（06 第 5 节）只以运行期选项提供。

## 4. 接口草案

```zig
// 草案：仅签名
pub const core = struct {
    pub const Vec2 = struct { x: f32, y: f32 };
    pub const Rect = struct { x: f32, y: f32, w: f32, h: f32 };      // lpx
    pub const RectI = struct { x: i32, y: i32, w: i32, h: i32 };     // ppx
    pub const Insets = struct { l: f32, t: f32, r: f32, b: f32 };
    pub const Color = packed struct { r: u8, g: u8, b: u8, a: u8 };  // sRGB 非预乘
    pub const WidgetId = enum(u64) { none = 0, _ };
    pub const Closure = struct { ctx: ?*anyopaque, func: *const fn (ctx: ?*anyopaque) void }; // afterFrame、post 共用

    pub const FrameArena = struct {
        pub fn allocator(self: *FrameArena) std.mem.Allocator;
        pub fn reset(self: *FrameArena) void;            // 保留容量
        pub fn bytesUsed(self: *const FrameArena) usize;
    };

    pub const log = struct {
        pub const Level = enum { err, warn, info, debug };
        pub fn scoped(comptime tag: @TypeOf(.enum_literal)) type; // 返回带 err/warn/info/debug 的命名空间
        pub fn setSink(sink: ?*const fn (Level, tag: []const u8, msg: []const u8) void) void; // 线程安全
    };

    pub const stats = struct {
        pub fn counter(comptime name: []const u8) *u64;
        pub fn gauge(comptime name: []const u8) *u64;
        pub fn timerBegin(comptime name: []const u8) void;
        pub fn timerEnd(comptime name: []const u8) void;
        pub const Kind = enum { counter, gauge, timer };
        pub const Entry = struct { name: []const u8, kind: Kind, value: u64 }; // timer 的 value 为累计纳秒
        pub const Snapshot = struct { entries: []const Entry };                // 切片有效至下次 snapshot
        pub fn snapshot(out: *Snapshot) void;                                  // 枚举全部已注册项
        pub fn drainSamples(name: []const u8, out: []u64) usize; // 取出并清空该计时器的样本（纳秒），返回写入数量
    };
};
```

## 5. 边界与错误情况

- **帧竞技场耗尽**：竞技场按块增长；增长失败视为内存耗尽，走不可恢复路径。
- **回投发生在应用退出过程中**：队列关闭后 `app.post` 返回 `false` 且不执行闭包；调用方负责释放闭包捕获的资源。
- **在构建函数内回投**：允许；闭包在下一轮消息循环执行。
- **发布构建中的编程错误**：每类错误的退化行为在相应文档定义（例如 ID 冲突时后者复用前者的状态槽并记录一次 `err` 日志）。

## 6. 验收标准

**AC-ARCH-001**　`[单元]` 覆盖：REQ-ARCH-001、REQ-ARCH-002、REQ-ARCH-003、REQ-ARCH-006。运行导入检查脚本，扫描 `src/` 中所有 `@import` 与 `@cImport`/extern 声明。预期：不存在违反 3.1 依赖规则的导入；NanoVG/GL/Win32/GLFW 符号只出现在允许的文件中；`core` 无任何模块外导入。

**AC-ARCH-002**　`[单元]` 覆盖：REQ-ARCH-004。在 Linux 上以 `-Dtarget=x86_64-windows-gnu` 构建。预期：产物中不含任何 GLFW 符号；本机 Linux 构建产物不含 Win32 后端符号。

**AC-ARCH-003**　`[单元]` 覆盖：REQ-ARCH-005。示例目录中存在一个"自定义控件"示例，它在 `widgets` 模块之外、仅使用公开接口实现一个带悬停/按下/焦点/键盘激活的自绘按钮。预期：编译通过，其回放测试与内建按钮的行为断言一致。

**AC-ARCH-004**　`[计量]` 覆盖：REQ-ARCH-007。示例应用运行期间枚举进程内由框架模块创建的线程（通过包装线程创建入口计数）。预期：计数为 0。

**AC-ARCH-005**　`[单元]` 覆盖：REQ-ARCH-008、REQ-ARCH-009、REQ-ARCH-010。测试一：从工作线程连续回投 10 000 个带序号的闭包，界面线程记录执行序号，预期严格递增且无丢失。测试二（调试构建）：从工作线程调用一个非线程安全 API，预期进程以断言信息中止。

**AC-ARCH-006**　`[计量]` 覆盖：REQ-ARCH-011、REQ-ARCH-012、REQ-ARCH-013。"控件总览"页预热 10 帧后，以 `-Dforce-rebuild=true` 连续跑 1000 帧。预期：持久分配器与状态存储池的分配计数增量为 0；帧竞技场与树竞技场向系统申请内存的次数增量为 0。

**AC-ARCH-007**　`[计量]` 覆盖：REQ-ARCH-014。向排版缓存与图像缓存持续写入超过其上限两倍的不同内容。预期：埋点显示的占用始终 ≤ 上限；进程常驻内存不随写入量线性增长。

**AC-ARCH-008**　`[单元]` 覆盖：REQ-ARCH-015。调试构建下故意泄漏一次持久分配后正常退出。预期：退出码非零，标准错误包含泄漏的分配点。

**AC-ARCH-009**　`[单元]` 覆盖：REQ-ARCH-016。向标签控件传入含 BMP 外字符、非法 UTF-8 序列、空串、超长串（1 MB）的文本。预期：不崩溃；非法序列显示为 U+FFFD；调用返回后立即改写原缓冲不影响已提交帧的显示。

**AC-ARCH-010**　`[单元]` 覆盖：REQ-ARCH-017、REQ-ARCH-018、REQ-ARCH-019。测试一：图像控件加载不存在的文件，预期显示占位框、产生恰好一条 `warn` 日志、构建函数无需 `try`。测试二：扫描公开 API 签名，预期不出现 `anyerror`。测试三（发布构建）：制造 ID 冲突，预期不崩溃且产生一条 `err` 日志。

**AC-ARCH-011**　`[单元]` 覆盖：REQ-ARCH-020、REQ-ARCH-021。设置自定义日志接收器后各级各写一条；读取一个计数器与一个计时器。预期：调试构建收到 4 条，发布构建收到 2 条；计数器值与递增次数一致。

**AC-ARCH-012**　`[单元]` 覆盖：REQ-ARCH-022。逐一执行表中各构建步骤。预期：全部退出码为 0（`bench` 在预算达标时为 0）。

## 7. 待定问题

- 是否需要为超大应用提供"每窗口独立界面线程"的模式。当前答案：不需要；单线程是硬约束。
