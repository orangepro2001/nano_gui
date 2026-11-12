# 12 性能

## 1. 范围

定义性能预算的数值、参考环境、测量方法、埋点清单（计数器、计量与计时器的名字），以及基准场景清单与预算的硬性判定规则。预算是 REQ-VIS-006 的具体化：任何功能若使预算被突破，必须先解决性能问题或缩减功能。

框架内部如何产生这些计数与计时（帧阶段、布局复用、缓存淘汰）分别见 06、07、05；`core.stats` 的接口（计数器、计量、计时器与样本）见 02 的 REQ-ARCH-021。本文不重复定义这些机制，只规定它们必须暴露的名字与预算值。

验证方式：本文 AC 以 `[计量]` 为主，在参考机 W 上执行；CI 机 L 只对 REQ-PERF-002 列明的类别做硬性判定。

## 2. 术语

| 术语 | 定义 |
|---|---|
| 参考机 W | 预算的唯一判定依据的硬件与系统环境，定义见 REQ-PERF-001。 |
| CI 机 L | 持续集成使用的无头 Linux 环境，定义见 REQ-PERF-002。 |
| 参考界面 G | 名为"控件总览"的示例页，包含全部内建控件与约 1500 个节点，定义见 REQ-PERF-003。 |
| 预算 | 一个带数值上限的性能或资源指标，逐项列于第 3.2 节。 |
| 硬性预算 | 超标即判定失败的预算（REQ-PERF-006）。 |
| 趋势预算 | 只记录、不因超标判定失败的预算；回退超过阈值时报警（REQ-PERF-008）。 |
| 预热 | 基准运行开始时执行、结果不计入统计的前 10 帧。 |
| P99 | 1000 个有效样本中按最近秩法取第 99 百分位的值，即第 990 个升序样本。 |
| 样本 | 一次计时器结束产生的纳秒值，或一帧中某计量的读数，供统计取值。 |
| 冷启动 | 进程从入口函数开始，到首个帧提交调用返回为止的全过程，不含操作系统加载可执行文件的时间。 |
| 稳定状态 | 界面结构与数据均不变，仅有相同输入重复驱动的连续帧。 |
| 基准场景 | 由构造方式、驱动方式与被测预算项组成的一个可重复运行单元，清单见 REQ-PERF-038。 |
| 基线 | 在参考机 W 上某里程碑结束时记录并入库的一组预算实测值，存于 `bench/baselines/`。 |
| MB | 本文中体积与内存的单位，1 MB = 2^20 字节（1 048 576 字节）。 |

## 3. 规范条款

### 3.1 参考环境与测量口径

**REQ-PERF-001**　全部预算的判定以参考机 W 为准。W 的定义：Windows 11 当前稳定版；4 核 x64 笔记本级 CPU（2018 年及以后发布）；集成显卡；显示器 1920×1080，缩放 100%；预算测量使用发布构建 ReleaseFast；体积预算使用 ReleaseSmall。测量报告**必须**记录操作系统版本、CPU 型号、GPU 型号与驱动版本、显示缩放与构建模式。

**REQ-PERF-002**　CI 机 L 的定义：Linux 与 Mesa llvmpipe 软件光栅的无头环境。在 L 上做硬性判定的类别为：
- 构建：REQ-PERF-011 的框架自身部分、REQ-PERF-012、REQ-PERF-013、REQ-PERF-014、REQ-PERF-021、REQ-PERF-036；
- 帧数：REQ-PERF-010 的帧数部分；
- 分配次数：REQ-PERF-026；
- 内存与缓存字节：REQ-PERF-027 至 REQ-PERF-030；
- 可执行文件体积：REQ-PERF-031、REQ-PERF-032。

在 L 上仅记录趋势（REQ-PERF-008）的为：绘制与帧耗时类（REQ-PERF-015 至 REQ-PERF-018、REQ-PERF-020、REQ-PERF-022、REQ-PERF-023、REQ-PERF-025）、输入延迟（REQ-PERF-019）、文本载入（REQ-PERF-024）、CPU 时间（REQ-PERF-010 的 CPU 部分）与 GL 绘制调用次数（REQ-PERF-033）。与 REQ-PERF-039 的汇总一致。

**REQ-PERF-003**　参考界面 G 指示例应用中的"控件总览"页在缩放 100%、1920×1080 下的稳定状态。G **必须**满足：包含全部内建控件各至少一个实例（处于常态）；稳定状态下 `frame.nodes` 的读数在 1400 至 1600 之间；其构建函数与数据不随帧变化。G 的组成**将**由 `docs/10-widgets/` 的控件规范完成后，在 `14-roadmap.md` 的 M3 一节冻结（见 OPEN-PERF-04）；冻结后 G 的变更必须同步更新本条的节点数判定。

**REQ-PERF-004**　统计口径统一为：每项预算在 10 帧预热（丢弃）之后采集 1000 帧。判定方式按预算的统计类型区分，且每项只能使用其中一种：
- **P99 类**（绝大多数耗时与节点数预算）：取 1000 个样本的 P99，与预算值比较。
- **字节类**（REQ-PERF-027、REQ-PERF-028、REQ-PERF-029、REQ-PERF-030）：取运行期间每帧采样的计量值的**最大值**，与上限比较。即 1000 帧中**每一帧**的读数都必须 ≤ 上限。
- **增量类**（REQ-PERF-010 的帧数与 CPU 时间）：取 60 秒内的总增量。
- **零值类**（REQ-PERF-026）：1000 帧的每一个样本都必须为 0。
- **逐次类**（REQ-PERF-011 的冷启动与 REQ-PERF-024 的文本载入）：连续运行 10 次，每次都须满足预算。
- **单次类**（REQ-PERF-031、REQ-PERF-032）：取构建产物的单次读数。

首帧与缓存冷启动**不计入** P99 样本（见第 5 节）。

**REQ-PERF-005**　所有预算的测量数据**必须**来自 `core.stats` 的计数器、计量与计时器（REQ-ARCH-021）以及平台提供的进程 CPU 时间与体积读数；不得以外部秒表或人工计时替代。计时器的样本即该次计时的纳秒耗时值，基准驱动器按名字调用 `drainSamples` 取出（接口见 02 与第 4 节）。计时器在基准构建中**必须**全部启用（REQ-ARCH-021）。

**REQ-PERF-006**　预算是硬性验收项（REQ-VIS-006）。`zig build bench` **必须**输出"项 / 预算 / 实测 / 是否达标"对照表，每行对应一条预算。任一硬性项超标时，进程退出码**必须**非零。性能问题不得以"以后优化"为由放行：超标的功能要么先解决性能问题，要么缩减功能，不得仅修改预算值或将其改为趋势项。

**REQ-PERF-007**　每个里程碑结束时，**必须**在参考机 W 上运行全部基准场景，将结果作为基线存入仓库 `bench/baselines/`。此后任一提交的实测值较基线回退超过 10%，该提交的说明**必须**解释原因（见 CONV 的提交规范）。本条为提交说明的要求，不改变硬性判定。

**REQ-PERF-008**　在 L 上的趋势预算较基线回退超过 20% 时，**必须**产生一条报警（输出为 CI 的警告标记，不使任务失败）。L 上的硬性项超标即失败。参考机 W 不可得时（例如暂无 Windows 测试机），在 L 上记录的结果**必须**标注"未在 W 验证"；该里程碑在 W 可用后**必须**补测，补测结果更新基线。

**REQ-PERF-009**　预算只在发布构建上判定。调试构建不适用任何预算（见第 5 节）。

### 3.2 预算表的测量规定

以下各条的测量场景与埋点名见第 3.4 节的基准场景清单与第 3.3 节的埋点清单。"帧"指一次完整的帧（06 的 3.4 节），"构建遍"指一次构建函数的完整执行（06 的 3.6 节）。

**REQ-PERF-010**　空闲（无输入、无动画、无定时器）时，场景 S-IDLE 的帧数**必须**为 0；60 秒内的进程 CPU 时间增量**必须** < 10 ms。帧数取 `frame.count` 的增量；CPU 时间取平台提供的进程 CPU 时间。CPU 部分在 L 上只记录趋势。

**REQ-PERF-011**　场景 S-COLD 的冷启动时间**必须** ≤ 100 ms，即计时器 `time.startup` 的值。其中 GL 上下文创建耗时（计时器 `time.gl_context`）单独记录；框架自身部分（`time.startup` 减去 `time.gl_context`）**必须** ≤ 40 ms，在 W 与 L 上均为硬性。两项均逐次判定（见 REQ-PERF-004）。

**REQ-PERF-012**　场景 S-G-BUILD 中，G 的一次构建遍耗时（计时器 `time.build` 的每个样本，即每个构建遍一个样本）的 P99**必须** ≤ 1.0 ms。

**REQ-PERF-013**　场景 S-G-LAYOUT-FULL 中，G 的全量布局耗时（计时器 `time.layout`，仅统计布局发生的帧）的 P99**必须** ≤ 0.5 ms。全量布局指每帧所有节点的可用空间约束均发生改变，使复用条件（REQ-FRAME-039）全部不成立。

**REQ-PERF-014**　场景 S-G-LAYOUT-INC 中，G 的增量布局耗时（计时器 `time.layout`）的 P99**必须** ≤ 0.1 ms。增量布局指每帧仅一个叶节点的内容变化，其余节点按 REQ-FRAME-039 复用。

**REQ-PERF-015**　场景 S-G-PAINT-FULL 中，G 整根绘制的 CPU 侧耗时（计时器 `time.paint`，即从绘制开始至提交调用前）的 P99**必须** ≤ 2.0 ms。该场景每帧损伤为整根。GL 绘制调用次数不属于本条（见 REQ-PERF-033）。

**REQ-PERF-016**　场景 S-G-FRAME 中，G 的完整帧（构建、布局、绘制）的 CPU 耗时（计时器 `time.frame_cpu`，从收集阶段开始至绘制结束，不含提交与垂直同步等待）的 P99**必须** ≤ 4.0 ms。该场景每帧置构建脏、并改变一个控件的状态。

**REQ-PERF-017**　场景 S-HOVER 中，仅悬停目标变化的纯绘制帧（不构建、不布局）的 `time.frame_cpu` 的 P99**必须** ≤ 0.3 ms。

**REQ-PERF-018**　场景 S-CARET 中，仅文本光标闪烁的纯绘制帧的 `time.frame_cpu` 的 P99**必须** ≤ 0.1 ms。

**REQ-PERF-019**　场景 S-INPUT 中，输入事件从到达界面线程（平台消息处理入口的单调时间戳）至提交调用前的耗时（计时器 `time.input_to_present`）的 P99**必须** ≤ 4.0 ms，即不超过一帧预算。框架在此期间**不得**引入人为延迟（见 06 的 REQ-FRAME-054）。在 W 上为硬性，在 L 上为趋势。

**REQ-PERF-020**　场景 S-VLIST-100K 中，虚拟列表含 10 万行、滚动中的每帧 `time.frame_cpu` 的 P99**必须** ≤ 2.0 ms。

**REQ-PERF-021**　在视口尺寸与可见行数相同的前提下，虚拟列表的节点数**必须**与总行数无关。场景 S-VLIST-SCALE 分别以 1 万、10 万、100 万行运行，同一稳定帧的计量 `frame.nodes` 的读数**必须**在三次运行间完全相等；节点数与可见行数成正比（见 AC-PERF-018）。

**REQ-PERF-022**　场景 S-TABLE-1M 中，表格含 100 万行 × 20 列、滚动中的每帧 `time.frame_cpu` 的 P99**必须** ≤ 3.0 ms。

**REQ-PERF-023**　场景 S-TEXT-KEY 中，文本编辑区（10 MB、20 万行）单次按键产生的帧的 `time.frame_cpu` 的 P99**必须** ≤ 2.0 ms。单次按键指一次按下与一次释放对应的输入，产生一帧。

**REQ-PERF-024**　场景 S-TEXT-LOAD 中，载入 10 MB、20 万行的文本编辑区，计时器 `time.text_load` 的值**必须** ≤ 200 ms，连续 10 次逐次判定（见 REQ-PERF-004）。在 W 上为硬性，在 L 上为趋势。

**REQ-PERF-025**　场景 S-RESIZE-4K 中，窗口客户区为 3840×2160 时，缩放过程中每帧的 `time.frame_cpu` 的 P99**必须** ≤ 8.0 ms。该场景每帧仅改变窗口尺寸，触发布局脏。

**REQ-PERF-026**　稳定状态下每帧的持久分配次数**必须**为 0，即场景 S-G-STEADY 的 1000 个样本中，`alloc.persistent.count` 的增量、`alloc.state.count` 的增量与 `alloc.frame.grow_count` 的增量**全部**为 0。此为 REQ-ARCH-013 的可测形式，判定规则为"每个样本均为 0"，不取 P99。

**REQ-PERF-027**　框架自身内存（经分配器统计，G，不含 GL 驱动内存）**必须** ≤ 8 MB。计算方式为每帧的 `alloc.persistent.bytes` 与 `alloc.arena.bytes` 之和；在场景 S-G-STEADY 的 1000 帧中，该和的**最大值****必须** ≤ 8 MB（字节类判定，见 REQ-PERF-004）。

**REQ-PERF-028**　字形图集的占用（计量 `cache.glyph_atlas.bytes`）在场景 S-CACHE-LIMIT 运行期间每帧采样，其**最大值必须** ≤ 16 MB。写入超过上限的内容时仍须成立（见 AC-ARCH-007）。

**REQ-PERF-029**　排版缓存的占用（计量 `cache.text_layout.bytes`）在场景 S-CACHE-LIMIT 运行期间每帧采样，其**最大值必须** ≤ 8 MB。

**REQ-PERF-030**　图像缓存在应用未调整上限时，计量 `cache.image.bytes` 在运行期间每帧采样的**最大值必须** ≤ 64 MB。应用可以调整该上限（见 REQ-ARCH-014）；本条判定针对默认上限。

**REQ-PERF-031**　使用 ReleaseSmall 构建的最小窗口示例可执行文件（单个窗口、一个按钮与一个标签）的文件体积**必须** ≤ 1.5 MB。

**REQ-PERF-032**　使用 ReleaseSmall 构建的 G（示例应用"控件总览"）可执行文件的文件体积**必须** ≤ 3 MB。

**REQ-PERF-033**　场景 S-G-FRAME 中，每帧的 GL 绘制调用次数（计数器 `frame.gl_draw_calls`）**不设门槛**，仅记录其 P99 与基线趋势；回退超过 20% 按 REQ-PERF-008 报警。

### 3.3 埋点清单

**REQ-PERF-034**　本表是跨模块埋点名字的**唯一登记处**，覆盖 `frame.*`、`time.*`、`alloc.*`、`cache.*`、`loop.*`、`threads.*`、`list.*` 前缀的名字。框架**必须**在 `core.stats` 中注册下表全部名字（名字冻结；改名需同步本文与所有引用处）。类别取 02 的 REQ-ARCH-021 的三类：计数器（单调递增，逐帧读取增量）、计量（可设为任意当前值）、计时器（每次结束产生一个纳秒样本）。发布构建中计数器与计量**必须**保留（REQ-ARCH-021）。

模块专有的补充埋点（如 04 的 REQ-GFX-042 中的 `gfx.*`、05 中的 `text.*`）由各自文档登记，不在本表重复；它们不得使用本表的前缀。

| 名字 | 类别 | 含义 |
|---|---|---|
| `frame.count` | 计数器 | 完成收尾阶段的帧数（含未绘制、未提交的帧） |
| `frame.build_passes` | 计数器 | 构建遍的累计次数 |
| `frame.nodes` | 计量 | 本帧保留树中的节点数（稳定帧读数） |
| `frame.nodes_measure_reused` | 计数器 | 布局中沿用旧测量结果的节点数的累计，含被整体跳过的复用子树内的全部后代（REQ-FRAME-039；由 layout 更新，REQ-LAYOUT-048） |
| `frame.nodes_painted` | 计数器 | 被调用绘制函数的节点数的累计 |
| `frame.damage_area_ppx` | 计数器 | 损伤面积（物理像素）的累计，各根之和 |
| `frame.presents` | 计数器 | 提交（呈现）调用的次数 |
| `frame.gl_draw_calls` | 计数器 | GL 绘制调用次数的累计 |
| `time.collect` | 计时器 | 收集阶段耗时 |
| `time.dispatch` | 计时器 | 分发阶段耗时 |
| `time.build` | 计时器 | 每个构建遍的耗时（每遍一个样本） |
| `time.layout` | 计时器 | 布局阶段耗时（仅布局发生的帧） |
| `time.damage` | 计时器 | 损伤计算耗时 |
| `time.paint` | 计时器 | 绘制阶段耗时（至提交调用前） |
| `time.present` | 计时器 | 提交调用耗时 |
| `time.frame_cpu` | 计时器 | 收集至绘制结束的耗时，不含提交与垂直同步等待（REQ-PERF-016） |
| `time.input_to_present` | 计时器 | 输入到达至提交调用前的耗时（REQ-PERF-019） |
| `time.startup` | 计时器 | 冷启动至首帧提交调用返回（REQ-PERF-011） |
| `time.gl_context` | 计时器 | GL 上下文创建耗时（REQ-PERF-011） |
| `time.text_load` | 计时器 | 文本编辑区载入耗时（REQ-PERF-024） |
| `alloc.persistent.count` | 计数器 | 持久分配器的累计分配次数 |
| `alloc.persistent.bytes` | 计量 | 持久分配器当前占用字节数 |
| `alloc.state.count` | 计数器 | 状态存储池的累计分配次数 |
| `alloc.arena.bytes` | 计量 | 帧竞技场与两份树竞技场的当前容量字节数 |
| `alloc.frame.grow_count` | 计数器 | 帧竞技场或树竞技场向系统申请内存的累计次数 |
| `cache.text_layout.bytes` | 计量 | 排版缓存当前占用字节数 |
| `cache.text_layout.entries` | 计量 | 排版缓存当前条目数 |
| `cache.text_layout.hits` | 计数器 | 排版缓存命中次数的累计 |
| `cache.text_layout.misses` | 计数器 | 排版缓存未命中次数的累计 |
| `cache.glyph_atlas.bytes` | 计量 | 字形图集当前占用字节数 |
| `cache.image.bytes` | 计量 | 图像缓存当前占用字节数 |
| `list.virtual_nodes` | 计量 | 虚拟列表当前已创建的行节点数（REQ-PERF-035） |
| `list.virtual_cells` | 计量 | 虚拟化表格当前已创建的单元格节点数（REQ-PERF-035） |
| `loop.block_waits` | 计数器 | 主循环进入操作系统阻塞等待的次数的累计 |
| `threads.created` | 计数器 | 框架模块创建的线程数的累计（REQ-ARCH-007） |

**REQ-PERF-035**　虚拟化容器**不得**为不可见项创建节点。"不可见"指完全位于视口与其预取边距之外的项。节点的创建数量**必须**只与当前可见项数相关；当前创建的行节点数由计量 `list.virtual_nodes` 报告。

**REQ-PERF-036**　构建函数内**不得**做与模型总量成正比（O(模型总量)）的工作。此条由应用保证，框架提供虚拟化容器使之可行。本条属于构建类预算，在 W 与 L 上均为硬性；判定方式见 AC-PERF-033：构建遍耗时在模型规模从 1 万行增至 100 万行时，P99 的增长**必须** ≤ 1.5 倍。

**REQ-PERF-037**　所有缓存**必须**有显式上限并在埋点中暴露占用（REQ-ARCH-014）。本条的具体上限值由 REQ-PERF-028 至 REQ-PERF-030 规定；新增缓存**必须**在本节补充上限与埋点名后，方可合入。

### 3.4 基准场景清单

**REQ-PERF-038**　基准场景**必须**按下表以冻结名字实现。每个场景的构造方式、驱动方式与被测预算项是规范性内容，不得以未在本表登记的场景替代判定。"驱动方式"列注明驱动是"回放脚本"（经 13 的回放运行器执行的输入指令）还是"基准驱动器 API 调用"（基准驱动器直接调用的失效、模型变更或平台接口）。

| 场景名 | 构造方式 | 驱动方式 | 被测项 |
|---|---|---|---|
| S-IDLE | G，窗口已显示 | 无驱动：无输入、无动画，静置 60 秒（真实时钟） | REQ-PERF-010 |
| S-COLD | 最小窗口示例（一个按钮、一个标签）与 G，各冷启动 10 次 | 基准驱动器 API 调用：进程启动，显示首帧后退出 | REQ-PERF-011 |
| S-G-BUILD | G | 基准驱动器 API 调用：每帧 `invalidate(.build)`，无状态变化 | REQ-PERF-012 |
| S-G-LAYOUT-FULL | G | 回放脚本：每帧 `resize` 在两个相邻宽度间交替 1 lpx，使全部节点约束改变 | REQ-PERF-013 |
| S-G-LAYOUT-INC | G，含一个文本长度可变的叶节点 | 基准驱动器 API 调用：每帧模型变更使该叶节点文本在两个长度间交替 | REQ-PERF-014 |
| S-G-PAINT-FULL | G | 基准驱动器 API 调用：每帧 `invalidateRect` 覆盖整窗口 | REQ-PERF-015 |
| S-G-FRAME | G | 基准驱动器 API 调用：每帧 `invalidate(.build)` 并通过模型变更切换一个复选框的状态 | REQ-PERF-016，REQ-PERF-033 |
| S-G-STEADY | G，预热后 | 基准驱动器 API 调用：无输入，每帧一次 `invalidate(.build)`，界面结构不变 | REQ-PERF-026，REQ-PERF-027 |
| S-HOVER | G，两个普通按钮并排 | 回放脚本：每帧 `move` 在两按钮中心之间交替 | REQ-PERF-017 |
| S-CARET | G，聚焦一个文本框，系统光标闪烁周期 500 ms | 回放脚本：每次 `advance 500` | REQ-PERF-018 |
| S-INPUT | G | 回放脚本：每帧一次 `down left` 与 `up left` | REQ-PERF-019 |
| S-VLIST-100K | 虚拟列表 10 万行，视口固定 | 回放脚本：每帧 `wheel -1`（向下滚动一格） | REQ-PERF-020，REQ-PERF-035 |
| S-VLIST-SCALE | 同 S-VLIST-100K，总行数分别为 1 万、10 万、100 万 | 回放脚本：同 S-VLIST-100K | REQ-PERF-021，REQ-PERF-035，REQ-PERF-036（取 1 万与 100 万两档的 `time.build` P99 之比，见 AC-PERF-033） |
| S-TABLE-1M | 表格 100 万行 × 20 列 | 回放脚本：每帧 `wheel -1`（向下滚动一格） | REQ-PERF-022 |
| S-TEXT-KEY | 文本编辑区，10 MB、20 万行，已聚焦 | 回放脚本：每帧一次 `key down` 与 `key up` 字符键 | REQ-PERF-023 |
| S-TEXT-LOAD | 文本编辑区，10 MB、20 万行 | 基准驱动器 API 调用：从冷状态载入 10 次 | REQ-PERF-024 |
| S-RESIZE-4K | G，窗口客户区 3840×2160 | 回放脚本：每帧 `resize` 在两个相邻宽度间交替 | REQ-PERF-025 |
| S-CACHE-LIMIT | 持续写入不同字形、排版与图像内容，写入量超过各上限的两倍 | 基准驱动器 API 调用：每帧写入一批新内容 | REQ-PERF-028，REQ-PERF-029，REQ-PERF-030 |
| S-SIZE | 最小窗口示例与 G，各以 ReleaseSmall 构建 | 无驱动：构建产物检查 | REQ-PERF-031，REQ-PERF-032 |

### 3.5 预算的硬性判定汇总

**REQ-PERF-039**　硬性判定规则汇总如下，并以 `zig build bench` 的对照表为唯一判定输出：
- 在 W 上：第 3.2 节中带数值门槛的预算项全部为硬性判定，包括 REQ-PERF-019 与 REQ-PERF-024；REQ-PERF-036 作为构建类比值同样为硬性。REQ-PERF-033 无门槛，仅记录。
- 在 L 上硬性判定的为 REQ-PERF-002 列明的类别：REQ-PERF-011（框架自身部分）、REQ-PERF-012、REQ-PERF-013、REQ-PERF-014、REQ-PERF-021、REQ-PERF-026、REQ-PERF-027、REQ-PERF-028、REQ-PERF-029、REQ-PERF-030、REQ-PERF-031、REQ-PERF-032、REQ-PERF-036，以及 REQ-PERF-010 的帧数部分。
- 在 L 上仅记录趋势的为其余带门槛的项：REQ-PERF-010 的 CPU 部分、REQ-PERF-015 至 REQ-PERF-020、REQ-PERF-022、REQ-PERF-023、REQ-PERF-024、REQ-PERF-025，以及 REQ-PERF-033。

## 4. 接口草案

```zig
// 草案：仅签名
pub const Judge = enum { hard_both, hard_w_trend_l, trend_both };

pub const Unit = enum { ms, mb, bytes, count, calls, ratio };

// 统计类型，对应 REQ-PERF-004
pub const Stat = enum { p99, max, run_delta, every_sample_zero, single_read, per_run_each };

// 多个埋点的组合方式，用于由多个名字得出一个预算值（如 REQ-PERF-027 的两项之和）
pub const Combine = enum { single, sum, difference, equal_across_runs };

pub const Budget = struct {
    req: []const u8,              // 如 "REQ-PERF-012"
    name: []const u8,             // 对照表行名
    limit: ?f64,                  // null 表示无门槛（仅记录，REQ-PERF-033）
    unit: Unit,
    stat: Stat,
    judge: Judge,
    sources: []const []const u8,  // 埋点名列表，如 &.{"time.build"}
    combine: Combine = .single,
};

pub const BenchError = error{ ScenarioUnknown, SetupFailed, SampleMissing, NotReleaseBuild };

pub const BenchResult = struct {
    budget: *const Budget,
    measured: f64,
    pass: bool,        // 对 judge 为 trend_both 的项恒为 true，仅记录
};

// 取出并清空某计时器的全部纳秒样本（02 的 REQ-ARCH-021 接口，本文仅引用）。
pub fn drainSamples(name: []const u8, out: []u64) usize;

// 运行一个基准场景。非发布构建调用时返回 NotReleaseBuild（REQ-PERF-009）。
pub fn runScenario(allocator: std.mem.Allocator, name: []const u8) BenchError![]BenchResult;

// 输出对照表；返回 true 表示全部硬性项达标。
pub fn printTable(writer: anytype, results: []const BenchResult) bool;
```

## 5. 边界与错误情况

- **首帧与缓存冷启动**不计入任何 P99 样本。首帧的耗时只通过 `time.startup` 与 REQ-PERF-011 判定。"缓存冷启动"指字形图集、排版缓存与图像缓存均为空的状态；场景中的预热即为从冷状态过渡到稳定。
- **调试构建**不适用任何预算（REQ-PERF-009）。调试开关（`-Dforce-rebuild`、`-Dshow-damage`）开启时，不得用于性能判定。
- **窗口最小化或尺寸为 0** 时不产生帧，不计入任何样本。
- **测量期间的系统干扰**：样本中的离群值不得删除；若某次运行的 P99 超标，结论以该次运行为准，允许在同机补测后另行记录，但不得替换原始结果。
- **参考机 W 不可得**：按 REQ-PERF-008 处理，结果标注"未在 W 验证"，不得据此在里程碑退出条件中判定性能达标。
- **L 与 W 的绘制耗时不可比**：L 上绘制类结果不得与 W 基线直接比较，只能与 L 自身的基线比较。
- **预算数值的修改**：预算数值变更属于规范变更，必须先改本文并说明理由，且须经评审（REQ-VIS-006）。

## 6. 验收标准

**AC-PERF-001**　`[计量]` 覆盖：REQ-PERF-001、REQ-PERF-003。前置条件：参考机 W。步骤：运行 `zig build bench`，读取报告头部的环境信息；运行 S-G-STEADY 并读取计量 `frame.nodes`。预期：报告头记录操作系统、CPU、GPU 与驱动版本、缩放 100%、ReleaseFast；`frame.nodes` 读数在 1400 至 1600 之间（区间随 OPEN-PERF-04 的 G 冻结而确认）。

**AC-PERF-002**　`[计量]` 覆盖：REQ-PERF-002。前置条件：CI 机 L（Linux，Mesa llvmpipe 无头）。步骤：在 L 上运行 `zig build bench`。预期：报告标注运行环境为 L；REQ-PERF-039 中列为 L 硬性的项参与判定，其余项仅输出数值与基线对比。

**AC-PERF-003**　`[计量]` 覆盖：REQ-PERF-004、REQ-PERF-005。前置条件：W 上运行 S-G-FRAME。步骤：读取 `time.frame_cpu` 的全部样本（经 `drainSamples`，纳秒），并与基准驱动器报告的 P99 对比；另以一组已知分布的样本（测试替身）验证 P99 与最大值的计算。预期：样本数为 1000（不含预热的 10 帧）；P99 等于第 990 个升序样本；预热帧的样本未进入统计；字节类测试替身的最大值判定正确。

**AC-PERF-004**　`[计量]` 覆盖：REQ-PERF-006。前置条件：W。步骤：运行 `zig build bench`，随后以测试替身把 `time.build` 注入为超过预算的值后再次输出对照表。预期：正常运行的对照表每行含项、预算、实测、是否达标四列；注入后对应行显示"未达标"，进程退出码非零；没有任何硬性项超标时退出码为 0。

**AC-PERF-005**　`[计量]` 覆盖：REQ-PERF-007。前置条件：里程碑结束时的 W 与 `bench/baselines/`。步骤：运行全部场景，比较结果与最近基线。预期：`bench/baselines/` 中存在当前里程碑的基线文件，列出全部预算项的实测值；对比时，回退超过 10% 的项在提交说明中有对应解释（由评审检查提交说明）。

**AC-PERF-006**　`[计量]` 覆盖：REQ-PERF-008。前置条件：L 上已有基线。步骤：（a）以测试替身使构建类硬性项 `time.build` 的 P99 超过预算值，运行一次；（b）以测试替身使绘制类趋势项 `time.paint` 的 P99 较基线回退 25%（未超预算值），运行一次。预期：（a）任务失败、退出码非零，判定依据为超过预算值，与基线无关；（b）产生一条警告标记，任务不失败。另：在"未在 W 验证"的环境中，结果文件的每行带有该标注。

**AC-PERF-007**　`[计量]` 覆盖：REQ-PERF-010。前置条件：W，G 已显示，无输入。步骤：静置 60 秒，记录 `frame.count` 的增量与进程 CPU 时间的增量。预期：帧数增量 = 0；CPU 时间增量 < 10 ms。

**AC-PERF-008**　`[计量]` 覆盖：REQ-PERF-011。前置条件：W，发布构建。步骤：连续冷启动 10 次，每次读取 `time.startup` 与 `time.gl_context`。预期：每次 `time.startup` ≤ 100 ms；每次 `time.startup` − `time.gl_context` ≤ 40 ms。

**AC-PERF-009**　`[计量]` 覆盖：REQ-PERF-012。前置条件：W，S-G-BUILD。步骤：运行 1010 帧，丢弃前 10 帧，读取 `time.build` 的样本。预期：P99 ≤ 1.0 ms。

**AC-PERF-010**　`[计量]` 覆盖：REQ-PERF-013。前置条件：W，S-G-LAYOUT-FULL。步骤：运行 1010 帧，读取 `time.layout` 的样本（仅布局发生的帧）并确认 `frame.nodes_measure_reused` 在这些帧中的增量为 0。预期：P99 ≤ 0.5 ms。

**AC-PERF-011**　`[计量]` 覆盖：REQ-PERF-014。前置条件：W，S-G-LAYOUT-INC。步骤：运行 1010 帧，读取 `time.layout` 的样本。预期：P99 ≤ 0.1 ms；每帧 `frame.nodes_measure_reused` 的增量 ≥ `frame.nodes` − 叶节点祖先链长度 − 受其尺寸影响的兄弟数。

**AC-PERF-012**　`[计量]` 覆盖：REQ-PERF-015。前置条件：W，S-G-PAINT-FULL。步骤：运行 1010 帧，读取 `time.paint` 的样本与 `frame.damage_area_ppx` 的每帧增量。预期：每帧损伤面积等于窗口面积；`time.paint` 的 P99 ≤ 2.0 ms。

**AC-PERF-013**　`[计量]` 覆盖：REQ-PERF-016。前置条件：W，S-G-FRAME。步骤：运行 1010 帧，读取 `time.frame_cpu` 的样本。预期：P99 ≤ 4.0 ms。

**AC-PERF-014**　`[计量]` 覆盖：REQ-PERF-017。前置条件：W，S-HOVER。步骤：运行 1010 帧，仅取 `frame.build_passes` 增量为 0 且 `time.layout` 未执行的帧，读取其 `time.frame_cpu`。预期：这些帧的 P99 ≤ 0.3 ms；取样帧数 ≥ 1000。

**AC-PERF-015**　`[计量]` 覆盖：REQ-PERF-018。前置条件：W，S-CARET。步骤：运行 1010 帧，取仅光标闪烁的帧，读取 `time.frame_cpu`。预期：P99 ≤ 0.1 ms。

**AC-PERF-016**　`[计量]` 覆盖：REQ-PERF-019。前置条件：W，S-INPUT。步骤：运行 1010 帧，读取 `time.input_to_present` 的样本。预期：P99 ≤ 4.0 ms。

**AC-PERF-017**　`[计量]` 覆盖：REQ-PERF-020。前置条件：W，S-VLIST-100K。步骤：滚动运行 1010 帧，读取 `time.frame_cpu`。预期：P99 ≤ 2.0 ms。

**AC-PERF-018**　`[计量]` 覆盖：REQ-PERF-021。前置条件：W，S-VLIST-SCALE 三个规模。步骤：每个规模在相同视口下稳定后读取 `frame.nodes`；并以两个不同视口高度（可见行数不同）各测一次。预期：三个规模的 `frame.nodes` 读数完全相等（判定方式 `equal_across_runs`）；视口变化时 `frame.nodes` 随可见行数线性变化，两点间比例误差 ≤ 5%。

**AC-PERF-019**　`[计量]` 覆盖：REQ-PERF-022。前置条件：W，S-TABLE-1M。步骤：滚动运行 1010 帧，读取 `time.frame_cpu`。预期：P99 ≤ 3.0 ms。

**AC-PERF-020**　`[计量]` 覆盖：REQ-PERF-023。前置条件：W，S-TEXT-KEY。步骤：运行 1010 帧，每帧一次按键，读取 `time.frame_cpu`。预期：P99 ≤ 2.0 ms。

**AC-PERF-021**　`[计量]` 覆盖：REQ-PERF-024。前置条件：W，S-TEXT-LOAD。步骤：连续载入 10 次，每次读取 `time.text_load`。预期：10 次的每一次均 ≤ 200 ms。

**AC-PERF-022**　`[计量]` 覆盖：REQ-PERF-025。前置条件：W，窗口 3840×2160，S-RESIZE-4K。步骤：运行 1010 帧，读取 `time.frame_cpu`。预期：P99 ≤ 8.0 ms。

**AC-PERF-023**　`[计量]` 覆盖：REQ-PERF-026。前置条件：W，G，已预热。步骤：运行 S-G-STEADY 1000 帧，读取 `alloc.persistent.count`、`alloc.state.count`、`alloc.frame.grow_count` 的每帧增量。预期：每个样本均为 0。同时参见 AC-ARCH-006（REQ-ARCH-013）。

**AC-PERF-024**　`[计量]` 覆盖：REQ-PERF-027。前置条件：W，G，S-G-STEADY 运行 1000 帧。步骤：每帧读取 `alloc.persistent.bytes` 与 `alloc.arena.bytes`，求和后取最大值。预期：最大值 ≤ 8 MB。

**AC-PERF-025**　`[计量]` 覆盖：REQ-PERF-028。前置条件：S-CACHE-LIMIT。步骤：持续写入字形至写入量超过上限两倍，每帧读取 `cache.glyph_atlas.bytes`。预期：所有样本的最大值 ≤ 16 MB。

**AC-PERF-026**　`[计量]` 覆盖：REQ-PERF-029。前置条件：S-CACHE-LIMIT。步骤：持续写入不同排版内容，每帧读取 `cache.text_layout.bytes`。预期：所有样本的最大值 ≤ 8 MB。

**AC-PERF-027**　`[计量]` 覆盖：REQ-PERF-030。前置条件：应用未调整图像缓存上限。步骤：持续写入不同图像，每帧读取 `cache.image.bytes`。预期：所有样本的最大值 ≤ 64 MB。

**AC-PERF-028**　`[计量]` 覆盖：REQ-PERF-031。前置条件：ReleaseSmall 构建的最小窗口示例。步骤：读取可执行文件字节数。预期：≤ 1.5 MB（≤ 1 572 864 字节）。

**AC-PERF-029**　`[计量]` 覆盖：REQ-PERF-032。前置条件：ReleaseSmall 构建的 G。步骤：读取可执行文件字节数。预期：≤ 3 MB（≤ 3 145 728 字节）。

**AC-PERF-030**　`[计量]` 覆盖：REQ-PERF-033。前置条件：W，S-G-FRAME。步骤：运行 1010 帧，读取 `frame.gl_draw_calls` 的每帧增量并计算 P99。预期：对照表中出现该项，不标记为达标或未达标；基线对比结果出现在报告中。

**AC-PERF-031**　`[单元]` 覆盖：REQ-PERF-034。步骤：启动框架后调用 `core.stats` 的 `snapshot` 枚举全部已注册项。预期：第 3.3 节表中全部名字均已注册，且各自的 `Kind` 与表中类别一致（计数器对应 `counter`，计量对应 `gauge`，计时器对应 `timer`）；注册表中不存在表外的 `frame.`、`time.`、`alloc.`、`cache.`、`loop.`、`threads.`、`list.` 前缀名字。

**AC-PERF-032**　`[单元]` 覆盖：REQ-PERF-035。前置条件：虚拟列表 10 万行，视口显示 30 行，预取边距 5 行。步骤：固定视口，滚动至 1000 行处后稳定，读取计量 `list.virtual_nodes`；滚动前后各读取一次。预期：`list.virtual_nodes` ≤ 30 + 2 × 5 = 40；滚动前后读数相等。

**AC-PERF-033**　`[计量]` 覆盖：REQ-PERF-036。前置条件：W，虚拟列表两个规模（1 万行与 100 万行）。步骤：各运行 1010 帧，读取 `time.build` 的样本。预期：100 万行的 P99 ÷ 1 万行的 P99 ≤ 1.5。同一判定在 L 上亦执行（硬性）。

**AC-PERF-034**　`[计量]` 覆盖：REQ-PERF-037。前置条件：S-CACHE-LIMIT。步骤：对三类缓存各写入超过上限两倍的内容，每帧读取占用计量。预期：三类占用的最大值均 ≤ 各自上限；每类缓存均存在对应的埋点名（见 REQ-PERF-034）。

**AC-PERF-035**　`[单元]` 覆盖：REQ-PERF-038。步骤：读取基准场景注册表。预期：第 3.4 节表中全部场景名均已注册，每个场景具备构造、驱动方式与被测项三项，驱动方式注明"回放脚本"或"基准驱动器 API 调用"或"无驱动"；注册表中不存在表外场景名。

**AC-PERF-036**　`[计量]` 覆盖：REQ-PERF-039。前置条件：W 与 L 各运行一次 `zig build bench`。步骤：核对对照表中每行的判定列来源与 REQ-PERF-039 的分类。预期：W 上全部带门槛的项为硬性；L 上仅 REQ-PERF-039 所列硬性项导致退出码非零，列为趋势的项超标时只出现警告。

**AC-PERF-037**　`[单元]` 覆盖：REQ-PERF-009。前置条件：调试构建（Debug）。步骤：以调试构建运行 `zig build bench`。预期：进程以非零码退出，并打印"调试构建不适用预算"；不生成对照表。`runScenario` 对非发布构建返回 `NotReleaseBuild`。

## 7. 待定问题

| 编号 | 问题 | 影响 | 当前倾向 |
|---|---|---|---|
| OPEN-PERF-01 | （已解决）`core.stats` 的逐次样本、计量设值与快照枚举由 02 的 REQ-ARCH-021 与草案提供，`drainSamples` 返回纳秒。 | REQ-PERF-005 | 已解决。 |
| OPEN-PERF-02 | （已解决）新增埋点名已并入第 3.3 节唯一登记表，类别按 02 的三类划分。 | REQ-PERF-034 | 已解决。 |
| OPEN-PERF-03 | （已解决）REQ-PERF-019 与 REQ-PERF-024 在 W 上硬性、在 L 上趋势。 | REQ-PERF-039 | 已解决。 |
| OPEN-PERF-04 | （已解决）参考界面 G 的组成。 | REQ-PERF-003 | 已在 14-roadmap.md 的 M3 一节"参考界面 G 的组成"中冻结，约 1460 个节点。 |
| OPEN-PERF-05 | 报警的输出通道（CI 注释、摘要或独立产物）未定。 | REQ-PERF-008 | 由 CI 配置决定，不影响判定。 |
