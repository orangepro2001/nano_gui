# 15 编码约定

## 1. 范围

定义 nano_gui 源码与提交的编码约定：语言与工具链版本、文件与模块组织、命名、控件 API 的形状、所有权与错误处理的书写方式、不使用的语言特性、C 互操作与 Win32 绑定、注释语言与内容、提交信息与分支评审规则，以及代码规模与依赖引入规则。

本文是规范性的：凡本文与 02 的架构条款冲突，以 02 为准；控件的选项与结果结构以 07（容器）与 10（控件规范）的草案为准，见第 4 节。约定的执行以脚本与评审相结合，多数条款有可运行的检查（见第 6 节）。

## 2. 术语

无新增。

## 3. 规范条款

### 3.1 语言与工具链

**REQ-CONV-001**　工具链**必须**固定为 Zig 0.17.1（ADR 0001）。版本号**必须**写入 `build.zig.zon` 的最低版本字段，并与 CI 配置一致。Zig 版本升级**必须**是独立的提交，不得与功能改动混合。

**REQ-CONV-002**　所有 `.zig` 源文件与 `build.zig` **必须**通过 `zig fmt --check`。该检查**必须**在 CI 中强制执行，未通过即失败。格式化结果以 `zig fmt` 为准，不得为个人偏好保留与之不同的格式。

### 3.2 文件与模块组织

**REQ-CONV-003**　源码目录**必须**与 02 的模块表一一对应：每个模块为 `src/<模块>/` 目录，并有且仅有一个入口文件 `src/<模块>.zig` 或 `src/<模块>/root.zig`。模块的公开接口**必须**集中再导出于入口文件，外部代码只能导入该入口（REQ-ARCH-006）。

**REQ-CONV-004**　`@import` 的依赖方向**必须**符合 02 的 REQ-ARCH-001：上层可导入下层的入口文件，下层**不得**导入上层；`core` **不得**导入任何其他模块与操作系统 API（REQ-ARCH-002）。NanoVG、OpenGL、Win32 与 GLFW 的符号**只能**出现在各自的后端文件中（REQ-ARCH-003）。

**REQ-CONV-005**　目录名与文件名**必须**为 `snake_case`，源文件扩展名为 `.zig`。单个文件的职责应当单一；文件行数没有硬性上限，但一个文件**不得**同时承担两个模块的公开接口。

### 3.3 命名

**REQ-CONV-006**　命名规则如下，遵循 Zig 标准库惯例：
- 类型（`struct`、`union`、`enum`、错误集）：`PascalCase`，例如 `WidgetId`、`ReplayError`。
- 函数与变量：`camelCase`，例如 `beginNode`、`frameArena`。返回类型的泛型构造函数按 Zig 标准库惯例使用 `PascalCase`，这是唯一例外。
- 常量：`snake_case`，例如 `frame_budget_ms`。枚举成员：`snake_case`，例如 `.high_contrast`。Win32 绑定中的常量与类型名除外，保持 Win32 原名（REQ-CONV-019）。
- 结构体字段：`snake_case`，与 02、06、08、09、10 的草案一致（如 `layout_feedback`、`paint_key`、`focused_visible`、`click_count`）。

**REQ-CONV-007**　令牌枚举的成员名**必须**由 09 文档令牌表格的令牌名机械地得出：`ColorToken` 与 `Metric` 的成员名与表格令牌名逐字一致；`FontToken`、`Duration`、`Easing`、`Gap` 的成员名为表格令牌名去掉类别前缀（`font_`、`dur_`、`ease_`、`gap_`），因为类别已由枚举类型表达（`gap_2xl` 因标识符不能以数字开头而写作 `xxl`，`Gap` 另有 `none`）。除此之外不允许任何缩写或改写。

**REQ-CONV-008**　控件 API 的声明形式**必须**为：第一个参数为 `ui: *Ui`，第二个参数为 `src: std.builtin.SourceLocation`（由调用方传入 `@src()`，REQ-FRAME-002），随后为控件特有参数，最后一个参数为选项结构，**按值**传递。Zig 没有统一函数调用语法，而 `widgets` 位于 `ui` 之上（REQ-ARCH-001），因此控件是 `widgets` 模块的自由函数而非 `Ui` 的方法，调用形式为 `w.<控件短名>(ui, @src(), …, opts)`（约定 `const w = nano_gui.widgets;`）；帧模型、布局容器与输入的 API（`pushId`、`beginRow`、`interact` 等）属于 `ui` 模块，是 `Ui` 的方法，调用形式为 `ui.<名字>(…)`，控件短名为 `camelCase`（如 `button`、`checkbox`）。控件函数的返回类型为 `<Name>Result`。

**REQ-CONV-009**　容器**必须**使用 `begin<Name>(ui, src, o)` 与 `end<Name>(ui)` 成对出现，`<Name>` 为 `PascalCase` 的容器名（如 `beginColumn`）。`begin` 返回该容器的 `WidgetId`（07 的草案），`end` 无返回值。每个 `begin` 必须有对应的 `end`，配对规则见 06 的 REQ-FRAME-028。

**REQ-CONV-010**　选项与结果结构的命名与内容如下：
- 控件的选项结构**必须**命名为 `<Name>Options`，结果结构**必须**命名为 `<Name>Result`。
- 纯布局容器（Row/Column/Stack 等 07 定义的容器）的选项结构共用 `ContainerOptions`，不按容器名另起。带自身行为与外观的容器型控件（group-box、tabs、toolbar、status-bar、scroll-view、list 等）使用自己的 `<Name>Options`，其中含通用的 `key`、`debug_name`、`enabled` 与所需的布局字段。
- 所有选项结构的字段**必须**都有默认值，使 `.{}` 可用。
- 结果结构**不得**包含指向帧竞技场或树竞技场的指针。 激活类结果的名字与含义全框架统一：`clicked`（一次点击或等效激活）；`changed`（控件持有或写回的值发生了变化，每次变化报告一次，拖动中连续报告）；`committed`（一次编辑手势结束且值可被视为用户的最终意图：拖动释放、文本框的 Enter 或失焦、微调的每一步）；`cancelled`（手势被 Esc 等取消，值已恢复）；`activated`（列表类的项被双击或 Enter）。一步即完成的控件（checkbox、switch、radio）只报告 `changed`，不报告 `committed`。
- 产生节点的叶子控件选项**必须**包含 `key: ?ui.Key = null`（REQ-FRAME-002）、`debug_name: ?[]const u8 = null`（供 13 的回放定位）与 `layout: layout.ItemOptions = .{}`（07）。容器选项中 `debug_name` 的补充见 OPEN-CONV-06。

**REQ-CONV-011**　所有权**必须**写在签名与文档注释中，使用且仅使用以下三种表述之一（REQ-ARCH-016）：
- "框架复制"：框架在调用期间或之后复制了输入。
- "调用方须保证存活至……"：框架持有引用，调用方负责生命周期，并写明截止点。
- "借用至本帧结束"：框架仅在本帧内使用输入，帧结束后不得保留。

未写明所有权的指针或切片参数**不得**出现在公开 API 中。

### 3.4 错误处理与断言

**REQ-CONV-012**　错误处理**必须**遵循 02 的 REQ-ARCH-017 至 REQ-ARCH-019：公开错误集**必须**是显式列举的具名集合，**不得**使用 `anyerror`；构建函数内调用的控件 API **不得**返回错误联合（REQ-ARCH-018）。

**REQ-CONV-013**　断言的使用规则如下：
- 编程错误（如 ID 冲突、未配对的 `begin`/`end`、越界）**必须**用 `std.debug.assert`，或带消息的自定义断言函数（消息须说明违反了哪条规则与调用点）。
- 环境错误（如文件不存在、图像解码失败、GL 上下文创建失败）**不得**用断言处理。可恢复的环境错误以错误联合返回；不可恢复的环境错误走 `platform.fatal`（REQ-ARCH-017）。

**REQ-CONV-014**　框架**不得**使用全局可变状态，但日志接收器（02 的 REQ-ARCH-020）与统计计数器（REQ-ARCH-021）除外。所有分配**必须**显式接收分配器或从所属上下文取得（REQ-ARCH-011），**不得**使用全局隐式分配器。

**REQ-CONV-015**　**不得**使用 `usingnamespace`。

**REQ-CONV-016**　`comptime` 泛型**只**在确有两处以上真实用例时引入。仅有一处用例时，**应当**写成具体类型。

### 3.5 C 互操作与 Win32 绑定

**REQ-CONV-017**　第三方 C 源码**只能**放在 `third_party/<库>/` 下，按上游原样 vendoring。对上游源码的每一处本地补丁**必须**逐条登记在 `third_party/<库>/PATCHES.md` 中，登记内容包括补丁目的、涉及文件与上游版本（ADR 0002）。未登记的补丁**不得**合入。

**REQ-CONV-018**　C 的 `extern` 声明与 `@cImport` **必须**集中在各后端的绑定文件中。绑定文件之外的代码**不得**直接声明外部函数。

**REQ-CONV-019**　Win32 绑定**必须**按需手写，只声明实际用到的类型、常量与函数。绑定的名字**必须**保持 Win32 原名（如 `CreateWindowExW`、`WM_PAINT`、`RECT`），不得为风格改名；Zig 侧的包装函数使用 REQ-CONV-006 的命名。

**REQ-CONV-020**　COM 接口的 vtable 声明**必须**与 COM 定义逐项一致：字段顺序与定义相同，`IUnknown` 的三项（`QueryInterface`、`AddRef`、`Release`）在最前。COM 指针**必须**由拥有它的结构体持有，该结构体的 `deinit` **必须**恰好调用一次 `Release`；调用方获取的接口指针在使用完毕后**必须**由获取方释放或转交给拥有者，不得依赖作用域结束或析构。

### 3.6 注释与文档

**REQ-CONV-021**　公开 API 的文档注释**必须**说明：线程要求（界面线程 / 线程安全）、所有权（REQ-CONV-011 的表述之一）与对应的规范条款编号（如有）。

**REQ-CONV-022**　注释语言**必须**为中文，标识符**必须**为英文。注释**应当**解释"为什么"（设计理由、约束来源、不显然的边界），**不得**复述代码已经表达的内容。

### 3.7 提交规范

**REQ-CONV-023**　提交信息的第一行**必须**符合 `<类型>(<范围>)?: <中文摘要>`，其中类型取 `feat`、`fix`、`docs`、`refactor`、`test`、`perf`、`build`、`chore` 之一，摘要中**必须**含中文字符。范围可省略。

**REQ-CONV-024**　修改 `src/` 的实现类提交，其正文**必须**包含一行 `AC: AC-…` 列出本次满足的验收条款编号（可多个，以逗号分隔）。编号**必须**存在于 `docs/acceptance/` 的某个清单中。

**REQ-CONV-025**　下列改动**必须**各自独立提交，不得与其他改动混合：规范改动（`docs/`）与实现改动（`src/`）；金图基准更新（REQ-TEST-011）；Zig 版本升级（REQ-CONV-001）。

### 3.8 分支、评审与规模

**REQ-CONV-026**　主分支**必须**始终可构建，且 `zig build`、`zig build test`、`zig build test-golden`、`zig build test-replay`、`zig build check-docs` 全部通过。任何合入主分支的提交都**必须**满足该条件。

**REQ-CONV-027**　每个合入请求的评审清单**必须**包含下列项目，评审人在合入前逐项勾选：
1. 本次改动满足的 AC 已列出，且对应测试通过。
2. 相关规范文档已同步修改，接口草案与代码一致。
3. 性能基准未回退超过 10%，或已在提交说明中解释（REQ-PERF-007）。
4. 未触碰非目标 REQ-VIS-008 中列出的内容。

**REQ-CONV-028**　`src/` 下 Zig 代码（不含空行与注释）的总行数**必须** ≤ 30 000（REQ-VIS-014）。超过时须在路线图中登记精简计划。

**REQ-CONV-029**　新增第三方依赖**必须**先以新 ADR 批准（ADR 0001 与 0002 的约束）。第三方依赖只能以源码形式存放在 `third_party/`，**不得**引入包管理器或预编译二进制。新增 `third_party/<库>/` 目录的合入请求，**必须**同时包含对应的 ADR 文件。

## 4. 接口草案

以下为控件与容器 API 的形状示意，说明 REQ-CONV-008 至 REQ-CONV-011 的书写方式。按钮的完整草案见 10 的 `button.md` 第 12 节，此处原样引用其选项与结果结构，不另行改写。

```zig
// 草案：仅签名（摘录自 docs/10-widgets/button.md §12，完整定义以该文件为准）
pub const ButtonVariant = enum { neutral, accent, quiet };
pub const ControlSize = enum { sm, md, lg };

pub const ButtonOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    variant: ButtonVariant = .neutral,
    size: ControlSize = .md,
    icon: ?Icon = null,
    checked: ?bool = null,
    tooltip: ?[]const u8 = null,      // 借用至本帧结束；框架在需要显示时复制
    layout: layout.ItemOptions = .{},
};

pub const ButtonResult = struct {
    hovered: bool,
    pressed: bool,
    focused: bool,
    clicked: bool,
    activated: ?input.ActivateSource,
};

// label 借用至本帧结束。选项按值传递。
pub fn button(ui: *Ui, src: std.builtin.SourceLocation, label: []const u8, opts: ButtonOptions) ButtonResult;
```

容器的形状（摘录自 07 的草案）：

```zig
// 草案：仅签名（摘录自 docs/07-layout.md，完整定义以该文件为准）
pub fn beginColumn(ui: *Ui, src: std.builtin.SourceLocation, o: ContainerOptions) WidgetId;
pub fn endColumn(ui: *Ui) void;
```

## 5. 边界与错误情况

- **类型构造器的命名**：返回类型的泛型函数按 REQ-CONV-006 的例外使用 `PascalCase`；这类函数仅限于标准库风格的容器，不得用于一般的工厂函数。
- **生成代码**：由工具生成的文件（如绑定生成的临时产物）若存在，应当放在 `third_party/` 或明确标注的生成目录，并遵守 REQ-CONV-002 的格式要求，除非生成工具不保证格式，此时须在 PR 中说明。
- **测试代码**：测试代码同样遵守本文的命名与断言规则。测试中的 `std.debug.assert` 不受 REQ-CONV-013 的环境错误限制。
- **日志与计数器的全局性**：日志接收器与统计计数器作为唯一允许的全局可变状态，其访问必须是线程安全的（02 的 REQ-ARCH-008）。
- **提交信息中的 AC 编号**：纯文档提交与纯基准更新提交无需 `AC:` 行，但必须符合 REQ-CONV-023。

## 6. 验收标准

**AC-CONV-001**　`[单元]` 覆盖：REQ-CONV-001。步骤：读取 `build.zig.zon` 的最低版本字段与 CI 配置中的 Zig 版本；检查最近一次修改该字段的提交。预期：两者均为 `0.17.1`；该提交不包含 `src/` 与 `docs/` 之外的改动，且不含其他功能性改动。

**AC-CONV-002**　`[单元]` 覆盖：REQ-CONV-002。步骤：运行 `zig fmt --check src build.zig`；检查 CI 配置中是否存在该步骤。预期：退出码为 0；CI 中该步骤存在且失败时任务失败。

**AC-CONV-003**　`[单元]` 覆盖：REQ-CONV-003。步骤：对 `src/` 下每个子目录，检查存在入口文件 `<模块>.zig` 或 `<模块>/root.zig`；扫描 `@import` 的路径，检查外部模块仅导入入口文件。预期：每个模块目录均有且仅有一个入口；不存在导入非入口文件的跨模块 `@import`。

**AC-CONV-004**　`[单元]` 覆盖：REQ-CONV-004。步骤：扫描 `src/` 中所有 `@import` 与 `extern` 声明，构建模块依赖图并对照 02 的 3.1 节允许的依赖；扫描 NanoVG、GL、Win32、GLFW 符号的出现位置。预期：依赖图无违反 REQ-ARCH-001 的边；`core` 无模块外导入；外部库符号只出现在允许的后端文件中。与 AC-ARCH-001 使用同一检查脚本。

**AC-CONV-005**　`[单元]` 覆盖：REQ-CONV-005。步骤：列出 `src/` 与 `tests/` 下的全部目录与文件名。预期：除扩展名 `.zig` 外，每个名字匹配 `^[a-z][a-z0-9_]*$`。

**AC-CONV-006**　`[单元]` 覆盖：REQ-CONV-006。步骤：扫描全部 `const X = struct|union|enum|error{` 声明，检查标识符为 `PascalCase`；扫描 `fn` 声明（排除返回 `type` 的函数），检查名字为 `camelCase`；检查枚举成员为 `snake_case` 或 `@"..."` 转义形式；检查 `src/` 中非 Win32 绑定文件的常量名为 `snake_case`。预期：无违反项。

**AC-CONV-007**　`[单元]` 覆盖：REQ-CONV-007。步骤：从 09 文档的令牌表格提取令牌名，按 REQ-CONV-007 的规则变换后，与代码中 `ColorToken`、`Metric`、`FontToken`、`Duration`、`Easing`、`Gap` 的成员名集合比较。预期：各枚举的成员集合与变换结果完全相等（`Gap.none` 除外）。

**AC-CONV-008**　`[单元]` 覆盖：REQ-CONV-008、REQ-CONV-009。步骤：扫描 `src/widgets/` 中所有控件函数，检查第一个参数类型为 `*Ui`，第二个为 `std.builtin.SourceLocation`，最后一个参数类型以 `Options` 结尾且不是指针（按值传递）；扫描全部容器的 `begin<Name>` 与 `end<Name>`，检查 `begin` 返回 `WidgetId`、`end` 无返回值。预期：无违反项；控件短名为 `camelCase`。

**AC-CONV-009**　`[单元]` 覆盖：REQ-CONV-009。步骤：扫描各构建函数中 `begin<Name>` 与 `end<Name>` 的调用次数与顺序；对一个故意遗漏 `end` 的测试构建运行。预期：静态扫描中 `begin` 与 `end` 数量一致、同名配对；遗漏 `end` 的构建在调试构建中按 REQ-FRAME-028 中止（与 AC-FRAME-016 同一测试）。

**AC-CONV-010**　`[单元]` 覆盖：REQ-CONV-010。步骤：扫描全部 `pub const *Options` 与 `*Result` 结构体；对每个 `Options` 编写一个编译期用例 `const _: Options = .{};`。扫描 `Result` 字段类型。预期：所有 `Options` 可由 `.{}` 初始化；所有 `Result` 字段类型不含指向竞技场的指针；每个产生节点的叶子控件的 `Options` 含 `key`、`debug_name` 与 `layout` 字段；容器选项使用 `ContainerOptions`。

**AC-CONV-011**　`[单元]` 覆盖：REQ-CONV-011。步骤：扫描公开 API 中所有指针与切片参数，检查其文档注释包含"框架复制""调用方须保证存活至""借用至本帧结束"之一。预期：无缺失项。

**AC-CONV-012**　`[单元]` 覆盖：REQ-CONV-012。步骤：扫描 `src/` 中 `anyerror` 的出现次数；扫描 `src/widgets/` 中控件函数的返回类型，检查不含 `!`。预期：`anyerror` 出现次数为 0；控件函数无错误联合返回类型。

**AC-CONV-013**　`[单元]` 覆盖：REQ-CONV-013。前置条件：测试用例指定一个不存在的图像文件。步骤：调用图像加载 API，观察行为。预期：返回错误（不触发断言、不中止进程）；控件显示占位框（AC-ARCH-010）。另检查：`std.debug.assert` 所在行附近存在描述性消息（静态扫描，无消息的断言列出待修正）。

**AC-CONV-014**　`[单元]` 覆盖：REQ-CONV-014。步骤：扫描 `src/` 中所有容器级 `var` 声明（非 `const`）；排除日志接收器与统计计数器所在文件后，统计剩余数量。预期：剩余数量为 0。

**AC-CONV-015**　`[单元]` 覆盖：REQ-CONV-015。步骤：扫描 `src/` 与 `tests/` 中的 `usingnamespace` 关键字。预期：出现次数为 0。

**AC-CONV-016**　`[单元]` 覆盖：REQ-CONV-016。步骤：扫描 `src/` 中所有以 `comptime T: type` 为参数的函数，统计其实例化的不同类型数。预期：每个泛型函数的实例化类型数 ≥ 2；仅一种实例化的函数列为违规项。

**AC-CONV-017**　`[单元]` 覆盖：REQ-CONV-017。步骤：检查 `third_party/` 下每个库目录；对每个目录，将其源文件与记录的上游版本比较（上游版本与校验和记录在 `PATCHES.md` 头部）；检查每处差异是否在 `PATCHES.md` 中有对应登记。预期：`third_party/` 中不含非 C 源码的第三方代码；每处差异均有登记；登记项包含目的、文件与上游版本。

**AC-CONV-018**　`[单元]` 覆盖：REQ-CONV-018。步骤：扫描 `src/` 中所有 `extern` 声明与 `@cImport`，检查其所在文件是否属于各后端的绑定文件。预期：所有外部声明均位于绑定文件中。

**AC-CONV-019**　`[单元]` 覆盖：REQ-CONV-019。步骤：扫描绑定文件中的 Win32 函数、类型与常量声明，检查名字与 Win32 原名一致（函数与类型保留原大小写与 `W` 后缀；常量保留原全大写名）。预期：无改名的 Win32 符号；Zig 侧包装函数位于非绑定文件中。

**AC-CONV-020**　`[单元]` 覆盖：REQ-CONV-020。前置条件：一个用假实现的 COM 对象（记录调用顺序与引用计数）。步骤：（a）比对 vtable 的字段名顺序与 COM 定义的顺序；（b）调用所属结构体的 `deinit`，检查引用计数。预期：（a）顺序一致，`QueryInterface`、`AddRef`、`Release` 位于前三位；（b）`Release` 恰好被调用一次，引用计数归零。

**AC-CONV-021**　`[单元]` 覆盖：REQ-CONV-021。步骤：扫描 `src/` 中所有公开的 `pub fn` 与 `pub const` 的文档注释，检查其包含线程要求关键字（"界面线程"或"线程安全"）；对有对应规范条款的，检查注释含 `REQ-` 编号；对涉及所有权的，检查注释含 REQ-CONV-011 的三种表述之一。预期：无缺失项。

**AC-CONV-022**　`[单元]` 覆盖：REQ-CONV-022。步骤：扫描 `src/` 中所有注释行与文档注释，检查每条注释含中文字符；扫描标识符，检查不含中文字符。预期：注释均含中文；标识符均为英文（字符串字面量与注释除外）。

**AC-CONV-023**　`[单元]` 覆盖：REQ-CONV-023。步骤：对最近 200 个提交的第一行运行正则 `^(feat|fix|docs|refactor|test|perf|build|chore)(\([^)]+\))?!?: .*[一-鿿]`。预期：全部匹配。

**AC-CONV-024**　`[单元]` 覆盖：REQ-CONV-024。步骤：对修改了 `src/` 的每个提交，检查正文是否含 `AC: AC-…` 行，并核对每个编号在 `docs/acceptance/` 中存在。预期：每个实现类提交均含至少一个存在的 AC 编号。

**AC-CONV-025**　`[单元]` 覆盖：REQ-CONV-025。步骤：遍历历史提交，检查每个提交修改的路径集合。预期：无提交同时修改 `docs/` 与 `src/`；修改 `tests/golden/` 的提交不修改其他路径（与 AC-TEST-008 同源）；修改 `minimum_zig_version` 的提交不含其他路径的功能性改动。

**AC-CONV-026**　`[单元]` 覆盖：REQ-CONV-026。步骤：在主分支最近一次合入的提交上运行 `zig build`、`zig build test`、`zig build test-golden`、`zig build test-replay`、`zig build check-docs`。预期：五条命令的退出码均为 0。

**AC-CONV-027**　`[人工]` 覆盖：REQ-CONV-027。步骤：对每个合入请求，由评审人检查评审清单四项是否均已勾选并附证据（AC 列表、文档改动、基准结果、非目标检查结论）。预期：四项全部勾选且有证据。

**AC-CONV-028**　`[计量]` 覆盖：REQ-CONV-028。步骤：统计 `src/` 下全部 `.zig` 文件中非空、非注释行的总数。预期：≤ 30 000；超过时路线图中须存在精简计划。与 AC-VIS-009 为同一统计。

**AC-CONV-029**　`[单元]` 覆盖：REQ-CONV-029。步骤：检查合入请求的文件列表：新增 `third_party/<库>/` 目录，或修改 `build.zig.zon` 中依赖声明的。预期：每次此类改动都在同一合入请求中新增一份 `docs/adr/` 文件；`third_party/` 中不含包管理器产物或预编译二进制（扩展名 `.lib`、`.dll`、`.a`、`.so` 等）。

## 7. 待定问题

| 编号 | 问题 | 影响 | 当前倾向 |
|---|---|---|---|
| OPEN-CONV-01 | （已解决）令牌枚举成员名与表格令牌名的对应规则。 | REQ-CONV-007 | 已写入 REQ-CONV-007：颜色与度量逐字一致，其余去类别前缀。 |
| OPEN-CONV-02 | （已解决）`[人工]` 标签是否涵盖评审项。 | AC-CONV-027 | 00 第 4 节已明确 `[人工]` 包含人工评审。 |
| OPEN-CONV-03 | （已解决，叶子控件部分）`debug_name` 字段已在 10 的 `button.md` 选项结构中出现。容器部分见 OPEN-CONV-06。 | REQ-CONV-010 | 叶子控件已解决。 |
| OPEN-CONV-04 | （已解决）结构体字段采用 `snake_case`，与 02、06、08、09、10 的草案一致。 | REQ-CONV-006 | 已解决。 |
| OPEN-CONV-05 | 第 5 节中"类型构造器"的例外范围依赖评审判断。 | REQ-CONV-006 | 收紧为仅标准库风格的容器，并在首次出现时在评审中确认。 |
| OPEN-CONV-06 | （已解决）容器的 `debug_name`。 | REQ-CONV-010 | 07 的 `ContainerOptions` 已补充 `debug_name`。 |
| OPEN-CONV-07 | （已解决）控件函数的调用形式。 | REQ-CONV-008 | 见 REQ-CONV-008：帧模型、布局、输入的 API 是 `Ui` 的方法；控件是 `widgets` 模块的自由函数，首参为 `ui: *Ui`。 |
