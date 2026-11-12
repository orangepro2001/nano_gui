# 05 文字

## 1. 范围

定义 `text` 模块：与后端无关的文字接口（样式、测量、排版、命中测试、光标与选区几何、字素簇与词边界、行信息）；排版缓存；字形图集；三个后端（Win32 的 DirectWrite、GLFW 的 fontstash、测试用的固定度量后端）；输入法组字的绘制支持；双向文字的显示。依据 ADR 0003。

窗口与输入法消息在 03；字形四边形的绘制与图集纹理的上传在 04（`Canvas.drawGlyphQuads`、`gfx.createTexture`）；文本编辑控件的行为在 10；基准字号、文字样式令牌与基线对齐的要求在 09（REQ-THEME-015 至 REQ-THEME-018）。

## 2. 术语

| 术语 | 定义 |
|---|---|
| 字素簇 (grapheme cluster) | Unicode UAX #29 定义的"用户感知字符"。光标移动与删除的最小单位。 |
| 整形簇 (shaping cluster) | 整形引擎产出的、字符到字形的映射单位，可粗于或细于字素簇（如连字）。 |
| 排版对象 (`Layout`) | 一次排版的完整结果：行、字形运行、簇的几何与映射。自包含，不引用后端对象。 |
| 字形运行 (run) | 同一字体面、同一双向层级、连续的一段字形。 |
| 插入符 (`Caret`) | `{ offset, affinity }`：文本位置加亲和性，用于消除软换行处与双向边界处的歧义。 |
| 亲和性 (affinity) | `upstream`（插入符属于前一位置所在行/运行的末端）或 `downstream`（属于后一位置所在行/运行的始端）。 |
| 图集 (atlas) | 存放已光栅化字形的 A8（或 RGBA）纹理页集合，由 `gfx` 纹理接口承载。 |
| 子像素档位 (`subpixel bin`) | 字形水平位置的小数部分量化到 0–3 的档位（每档 1/4 ppx）。 |
| 构建代 (build generation) | 每次构建完成时递增的计数，用于判定缓存条目是否仍被保留树引用。 |
| 组字 (composition) | 输入法尚未确认的临时文本。 |

## 3. 规范条款

### 3.1 总则

**REQ-TEXT-001**　`text` 的公共接口**必须**与后端无关，由编译期选择的后端实现（REQ-ARCH-004）：`directwrite`（Win32 默认）、`fontstash`（GLFW 默认）、`fixed`（固定度量测试后端，仅 `-Dtext-backend=fixed` 选择，供 `zig build test` 的布局与控件逻辑测试使用）。三个后端**必须**通过同一套接口一致性测试（度量数值按后端分别断言）。DirectWrite 与 COM 符号**只能**出现在 DirectWrite 后端的实现文件中，即 `src/text/directwrite.zig` 或 `src/text/directwrite/` 目录下（REQ-ARCH-003、REQ-ARCH-006）。

**REQ-TEXT-002**　全部文本位置（偏移）**必须**是调用方所传 UTF-8 字节串中的字节偏移，且**必须**落在字素簇边界上（0 与 `len` 视为边界）。接收偏移的函数收到非边界偏移时，调试构建断言中止，发布构建向下对齐到不大于该值的最近边界。返回偏移的函数**必须**只返回边界值。

**REQ-TEXT-003**　非法 UTF-8 **必须**按 WHATWG 的"最大非法子序列替换"处理：每个最大非法子序列显示为一个 U+FFFD（例如孤立字节 `FF` → 1 个；被截断的三字节序列 `E4 B8` → 1 个；过长编码 `C0 80` → 2 个；编码代理项 `ED A0 80` → 3 个；超出 U+10FFFF 的 `F4 90 80 80` → 4 个）（AC-ARCH-009）。排版内部使用规范化后的副本，但对外的偏移**必须**仍以调用方的**原始字节串**为准：被替换的非法序列的全部原始字节构成一个字素簇，其起止偏移即原始偏移。`Layout` 保留规范化副本到原始偏移的映射。

**REQ-TEXT-004**　特殊字符的排版规则：
- **制表符** U+0009：按制表位展开，制表位间隔 = `tab_width`（默认 4）个空格宽度，从行首起算；到达下一个制表位。制表符是一个簇。
- **换行**：`\n`、`\r\n`（视为一个簇）、`\r`、U+0085、U+2028、U+2029 是硬换行。`LayoutOptions.newlines = .break_lines`（默认）时产生换行；`= .as_space` 时每个硬换行（`\r\n` 整体）按一个空格显示、不换行（用于单行输入框与标签）。换行符属于其前一行末尾，本身不显示字形，其簇宽为 0。
- **其他 C0/C1 控制字符**（不含上述）：不显示字形、宽度 0，但各占一个簇以保持偏移映射。
- **零宽字符**：U+200B（零宽空格）宽 0、独立簇、是断行机会；U+200C/U+200D（ZWNJ/ZWJ）、U+2060、U+FEFF 参与整形与簇划分（如 emoji 序列），自身不可见；U+202A–U+202E、U+2066–U+2069（双向控制）参与双向算法，自身不可见。
- **不可见与未映射字符**：字体中无字形的码点由回退链处理（3.6）；仍无字形时显示字体的缺字字形（notdef），宽度取该字形宽度。

**REQ-TEXT-005**　输入长度与超长串：单次 `layout`/`measure` 的输入上限 `max_layout_bytes = 262 144`。超出时**必须**截取前 262 144 字节（回退到字素簇边界）后排版，使 `Layout.truncated` 为真，并强制附加省略号 U+2026，同时记录一条 `warn` 日志（同一内容哈希只记一次）；该函数**不得**返回错误（REQ-ARCH-018）。需要排版更长文本的控件（文本编辑）**必须**按段落分段排版。超长无空格串在 `wrap = .word` 下**必须**在字素簇边界强制断行（不拆分簇）；`wrap = .none` 时按省略规则处理。

### 3.2 样式与度量

**REQ-TEXT-006**　`text.Style` **必须**为不可变值类型：`{ family: Family, size: f32 (lpx), weight: u16 (1–1000，取 400/600 等 CSS 数值), italic: bool }`。`Family` 为令牌：`ui`（系统消息字体）、`mono`（等宽链）或应用以 `text.registerFamily(name) !Family` 注册的具名字族（名字由框架复制）。Style 的相等与哈希**必须**逐字段，`size` 按 1/64 lpx 量化后参与哈希。主题的文字令牌（REQ-THEME-016）是 `Style` 值（`Theme.fonts`）。

**REQ-TEXT-007**　`text.fontMetrics(style, scale) FontMetrics` 返回 `{ ascent, descent, line_gap, height }`，单位 lpx，由 ppx 度量除以 `scale` 得出（REQ-TEXT-008）；`height = ascent + descent + line_gap`。`LayoutOptions.line_height`（lpx，缺省为 `height`）覆盖行高；主题把 REQ-THEME-016 的行高令牌传入此处。

**REQ-TEXT-008**　排版**必须**在物理像素字号下进行：`ppx_size = size × scale`，量化到 1/4 ppx。后端以 `ppx_size` 整形与取度量，结果（宽度、坐标）以 ppx 保存在 `Layout` 内，对外报告时统一除以 `scale` 换回 lpx。每个 `scale` 的排版结果独立缓存（REQ-TEXT-013 的键含 `scale`）。**不得**先在 96 DPI 下排版再缩放几何。

**REQ-TEXT-009**　基线与行高**必须**对齐物理像素：每行的行高 `line_h_ppx = round(line_height × scale)`；行 `i` 的顶边 `top_i = Σ 前序行高`（整数 ppx）；基线 `baseline_i = top_i + floor((line_h_ppx − font_h_ppx) / 2) + round(ascent_ppx)`（`font_h_ppx = round(ascent_ppx) + round(descent_ppx) + round(line_gap_ppx)`），为整数 ppx。`text.baselineInBox(box_h_lpx, style, line_height, scale) f32` 返回单行文字在高 `box_h_lpx` 的盒内的基线 y（lpx）：`box_h_ppx = round(box_h × scale)`，`top = floor((box_h_ppx − line_h_ppx) / 2)`，基线 = `top + 行内基线偏移`，换回 lpx；其与 `scale` 相乘**必须**恰为整数（配合 REQ-THEME-017）。

### 3.3 测量与排版

**REQ-TEXT-010**　`text.measure(text, style, scale, opts) Size` 返回单行（`wrap = .none`、`newlines = .as_space`）或按 `opts` 排版后的包围尺寸（lpx），**必须**与 `layout(...).size` 完全相等，并共用同一缓存（测量不另起整形）。宽度为各行行宽的最大值，行宽**不含**行末悬挂的空白；高度 = 行数 × 行高。

**REQ-TEXT-011**　`text.layout(text, style, scale, opts) *const Layout` 的选项 `LayoutOptions` 如下，字段集合封闭：

| 字段 | 取值 | 说明 |
|---|---|---|
| `max_width` | `?f32`（lpx） | `null` 为不限宽 |
| `wrap` | `none` / `word` / `anywhere` | 不换行 / 按词换行（断行机会见 REQ-TEXT-016）/ 在任意字素簇边界换行 |
| `align` | `left` / `center` / `right` | 行在 `max_width` 内的水平对齐；`max_width = null` 时忽略。**不提供**两端对齐，也**不随文字方向翻转**（REQ-VIS-008） |
| `ellipsis` | `none` / `end` | `end`：内容超出时尾部省略号（REQ-TEXT-015） |
| `max_lines` | `?u32` | 行数上限；超出的内容被截断（`ellipsis = .end` 时最后一行加省略号） |
| `newlines` | `break_lines` / `as_space` | REQ-TEXT-004 |
| `tab_width` | `u8` | 默认 4 |
| `line_height` | `?f32`（lpx） | REQ-TEXT-007 |

所有基于宽度的计算在 ppx 上进行（`max_width_ppx = round(max_width × scale)`）。

**REQ-TEXT-012**　`Layout` **必须**自包含：后端在 `layout` 返回前把所有需要的信息提取进 `Layout`，之后的 `hitTest`、`caretRect`、`selectionRects`、`draw` 等**不得**再调用后端（DirectWrite 的 `IDWriteTextLayout` 等 COM 对象在提取完成后立即释放）。`Layout` 至少包含：
- `lines`：每行 `{ start, end（字节偏移，含行末悬挂空白与换行符）, top, baseline, height, width（不含悬挂空白）, x_offset（对齐产生的偏移）, run_range }`；
- `runs`：每个字形运行 `{ face: FaceId, bidi_level: u8, byte_range, glyph_range, is_ellipsis }`；
- `glyphs`：`{ index: u16, cluster: u32（簇序号）, x（运行内累计前进，ppx f32）, x_offset, y_offset, advance }`；
- `clusters`：按逻辑顺序，每个字素簇 `{ byte_start, byte_end, line, x0, x1（ppx f32，视觉左右边界）, bidi_level }`；整形簇粗于字素簇时（连字），簇内各字素边界的 `x` 在该整形簇范围内按字素数**等分插值**；
- `size`、`scale`、`truncated`、`text_len`（原始字节长度）。

不变量：`clusters` 覆盖 `[0, text_len)` 且无间隙无重叠；每个簇边界都是字素簇边界；各行的字节范围按序相接。

**REQ-TEXT-013**　**排版缓存**：`layout` 的结果**必须**缓存，键 = 哈希(文本字节, `Style`, `max_width_ppx`, `wrap`, `ellipsis`, `max_lines`, `newlines`, `tab_width`, `line_height_ppx`, `align`, `scale_milli = round(scale × 1000)`)。条目保存文本的完整副本（"框架复制"，REQ-ARCH-016），命中时**必须**逐字节比对文本，哈希相同而文本不同视为未命中。命中时**不得**重新整形（埋点 `text.shape_count` 不增加）。容量上限默认 4096 条目且总字节（`Layout` 数据 + 文本副本）≤ 8 MiB，超出以 LRU 淘汰（REQ-ARCH-014），占用计入埋点 `cache.text_layout.entries/bytes`。`max_width` 因量化到 ppx，相差不足 1 ppx 的宽度共用一个条目。DPI、字体设置、主题字体令牌变化时**必须**整体清空（REQ-FRAME-037）。

**REQ-TEXT-014**　`Layout` 指针的有效期：自获取它的那次构建（或布局阶段）起，至**下下次**构建完成为止，覆盖双份树竞技场的保留范围（REQ-ARCH-012）与其间的纯绘制帧、纯布局帧。实现：缓存条目记录最后一次被触达的构建代，淘汰只能选择最后触达代 < 当前代 − 1 的条目；若全部条目都受保护而超出容量，允许暂时超限，下一次构建完成后收敛。需要更长寿命的持有者（文本编辑保留节点）**必须**用 `text.layoutOwned(allocator, ...)` 取得不入缓存、由调用方 `deinit` 的 `OwnedLayout`。

**REQ-TEXT-015**　省略与截断：
1. `wrap = .none` 且 `ellipsis = .end`、内容宽度超出时（单行截断；多行被 `max_lines` 截断的情形见第 6 条），**必须**在尾部显示省略号 U+2026，字体样式取被截内容末簇所用的字体面。保留的前缀**必须**在字素簇边界结束，使 `前缀宽度 + 省略号宽度 ≤ max_width_ppx`，且保留尽可能多的完整簇；**不得**裁出半个字形或半个簇（REQ-THEME-018）。
2. 前缀末尾的空白簇在附加省略号前**去除**。
3. 若省略号本身宽于 `max_width`，行内不显示任何字形，`truncated` 仍为真。
4. 省略号字形在 `Layout` 中以 `is_ellipsis` 运行表示，其簇的 `byte_start = byte_end =` 保留前缀末尾的偏移；对其命中测试返回该偏移。
5. `Layout.truncated` 为真当且仅当存在被省略号替代或被 `max_lines` 截断的内容；`text.isTruncated(text, style, scale, max_width) bool` 是便捷查询，供控件决定是否在悬停时显示全文提示（REQ-THEME-018）。
6. `ellipsis = .end` 与 `wrap = .word/.anywhere` 联用时，仅当设置了 `max_lines` 并被截断，最后一行才加省略号；未设 `max_lines` 时不产生省略。算法（`wrap = .word` 或 `.anywhere` 且被 `max_lines` 截断）：先按 `wrap` 规则（REQ-TEXT-016）正常断行得到第 `max_lines` 行的内容；去掉该行行尾的空白簇；附加省略号；若附加后宽度超过 `max_width_ppx`，则从行尾起**按整簇**逐个回退，直到 `宽度 + 省略号宽度 ≤ max_width_ppx`（回退后若新的行尾是空白簇，同样去除）。该行之后的内容全部被截断，`truncated` 为真。因此多行截断时最后一行以词（或 `anywhere` 下以簇）为单位，而不是用尽整行宽度。

**REQ-TEXT-016**　断行规则（`wrap = .word`）：断行机会按 UAX #14 的基本规则确定，并满足：
1. 空白之后可断；连字符 `-` 之后可断。
2. 汉字、假名之间任意两个相邻簇之间可断（`wrap = .word` 对 CJK 等同逐字断行）。
3. **避头尾**：下列字符不得出现在行首（其前的断行机会被移除）：`，。、；：！？）】」』〉》”’…·` 及小写假名 `ぁぃぅぇぉっゃゅょァィゥェォッャュョ` 与长音 `ー`；下列字符不得出现在行尾（其后的断行机会被移除）：`（【「『〈《“‘`。
4. 行末的空白悬挂：超出 `max_width` 的行末空白不触发换行，不计入行宽。
5. 单个不可断单元宽于 `max_width` 时，在簇边界强制断行（REQ-TEXT-005）。
6. `wrap = .anywhere`：每个字素簇边界都是断行机会（仍遵守"不拆簇"）。

DirectWrite 后端使用 `IDWriteTextLayout` 的断行结果，其细节可能与上述基线略有差异（见 TEXT-OPEN-04）；`fontstash` 与 `fixed` 后端**必须**严格实现上述规则。

**REQ-TEXT-017**　对齐：`left`/`center`/`right` 在每行内计算 `x_offset = 0 / (max_width_ppx − line_width_ppx) / 2（向下取整）/ max_width_ppx − line_width_ppx`；`max_width = null` 时 `x_offset = 0`。基准文字方向恒为从左到右，`left` 永远是视觉左侧（REQ-VIS-008）。

### 3.4 编辑支持

**REQ-TEXT-018**　`layout.hitTest(point: Vec2) HitResult`（`point` 为相对 `Layout` 原点的 lpx 坐标）**必须**返回 `{ caret: Caret, cluster_start: u32, edge: leading|trailing, line: u32, inside: bool }`：
1. 先按 y 选行（y < 0 取首行，y ≥ 总高取末行），行内按 x 选簇。
2. `caret.offset` 为最近的簇边界：点落在簇宽度的前半（`x < (x0 + x1) / 2`）取该簇的**起始边界**（`edge = leading`），否则取**末尾边界**（`edge = trailing`）；恰在中点取 `trailing`。
3. 点在行左侧之外取该行首簇的视觉左边界、在行右侧之外取视觉右边界；`inside` 为假。
4. 返回的偏移**不得**落在字素簇内部（含 emoji 序列与组合字符序列）。
5. 软换行处的亲和性：行末的 trailing 边界得 `upstream`，下一行首的 leading 边界得 `downstream`。

**REQ-TEXT-019**　`layout.caretRect(caret: Caret) CaretRect` 返回 `{ x: f32, y: f32, h: f32 }`（lpx，相对 `Layout` 原点）：`y`、`h` 为该行的顶边与行高；`x` 为插入符所在簇边界的视觉位置，**必须**对齐到整数物理像素（`round(x_ppx) / scale`）。插入符宽度不由 `text` 决定（由控件取发丝线宽度）。同一偏移在软换行处，`upstream` 返回上一行末端位置（`x` 钳制在该行 `width`，即行末悬挂空白之前），`downstream` 返回下一行首位置；不在歧义位置时亲和性被忽略。

**REQ-TEXT-020**　`layout.selectionRects(start, end, opts, out: *List(Rect)) void` 把选区 `[start, end)` 转为 lpx 矩形列表：每行、每个双向运行至多一个矩形，高度为行高，同行内视觉相邻的矩形**合并**；`start == end` 时输出为空；`start > end` 时先交换。`opts.extend_line_breaks`（默认假）为真时，若选区包含某行末的硬换行，该行矩形向右延伸一个空格宽度。矩形边界对齐整数物理像素（同 REQ-TEXT-019）。含 RTL 运行的选区可产生多个同行矩形（REQ-TEXT-041）。

**REQ-TEXT-021**　字素簇边界函数**必须**与后端无关，由 `text` 自带的 Unicode 数据表实现 UAX #29 扩展字素簇规则（含 emoji ZWJ 序列、区域指示符对、韩文音节、组合字符、`\r\n`）：`text.nextGrapheme(s, offset) usize`、`text.prevGrapheme(s, offset) usize`、`text.isGraphemeBoundary(s, offset) bool`。Unicode 数据版本固定并记录在 `src/text/unicode_version.zig`；升级是单独提交。光标左右移动与向前/向后删除的最小单位即字素簇（具体删除行为的细节由 10 的文本编辑规范决定，见 TEXT-OPEN-02）。

**REQ-TEXT-022**　词边界函数：`text.nextWord(s, offset)`、`text.prevWord(s, offset)`（Ctrl+Right / Ctrl+Left）与 `text.wordRange(s, offset) Range`（双击选词）。**词单元**划分：
1. 字母/数字/下划线连续序列为一个词单元（按 UAX #29 词规则，含撇号与数字内小数点）；
2. 标点或符号连续序列为一个词单元；
3. 空白连续序列为一个词单元；
4. **汉字逐字**：每个汉字（Unified Ideographs 及扩展区）自成一个词单元；平假名连续序列、片假名连续序列各为一个词单元；谚文按 UAX #29（以空格分词）；
5. 其他脚本按 UAX #29。

`nextWord`：从 `offset` 起越过当前词单元，再越过随后的空白词单元，返回下一个非空白词单元的起点（无则 `len`）。`prevWord`：越过 `offset` 之前紧邻的空白词单元，再回到所在词单元起点（无则 0）。`wordRange(offset)`：返回包含 `offset` 的词单元范围（`offset` 落在两个词单元之间取其后者，文末取前者）；空白词单元也可被选中，**不**附带尾随空白。系统断词（`Windows.Data.Text.WordsSegmenter`）不使用，见 TEXT-OPEN-03。

**REQ-TEXT-023**　行信息与垂直移动：`layout.lineCount()`、`layout.lineOf(caret) u32`、`layout.lineRange(i) Range`（字节范围，含悬挂空白，不含换行符的显示）、`layout.lineRect(i) Rect`、`layout.lineStart(caret)`/`lineEnd(caret) Caret`（Home/End：行首偏移，行末偏移为不含硬换行符之前的位置；软换行行的行末取最后一个非悬挂空白簇之后）。`layout.moveVertical(caret, dir: up|down, goal_x: ?f32) struct { caret: Caret, goal_x: f32 }`：在相邻行内取与 `goal_x`（缺省取当前插入符 x）最近的簇边界；首行向上返回偏移 0，末行向下返回 `text_len`；`goal_x` 在连续垂直移动中保持不变。

**REQ-TEXT-024**　`layout.moveHorizontal(caret, dir: left|right) Caret`：在不含 RTL 运行的行内，等价于字素簇步进（`prevGrapheme`/`nextGrapheme`）并在行首/行末跨行；跨软换行处时亲和性按 REQ-TEXT-018 第 5 条更新。含 RTL 运行的行内的移动规则尚未确定（TEXT-OPEN-01）；在规则确定前，此情形按逻辑顺序步进。

### 3.5 字形图集与绘制

**REQ-TEXT-025**　字形图集由一组 **A8 纹理页**组成，每页默认 1024×1024，创建为 `gfx` 的 `dynamic` 纹理（带 CPU 影子缓冲，REQ-GFX-029）。页内采用行式装箱（shelf packing），字形四周留 1 ppx 透明边距。页数上限默认 16（16 MiB，即 12 的字形图集预算），可配置。图集占用（字节数、页数、已用像素比例）计入埋点 `cache.glyph_atlas.bytes`、`text.atlas_pages/atlas_used_ppx`（REQ-ARCH-014）。图集页**由 `text` 创建并拥有**，`gfx` 仅负责上传与绘制（`text → gfx` 依赖，REQ-ARCH-001）。

**REQ-TEXT-026**　图集键 = `(字体面 FaceId, 字形索引, ppx 字号（量化到 1/4 ppx）, 水平子像素档位 0–3)`。**水平**定位使用 4 档子像素；**垂直**不使用子像素，基线对齐整数像素（REQ-TEXT-009），故键中无垂直分量。字形的绘制位置换算：设字形最终位置 `X = origin_x_ppx（整数）+ glyph.x（f32 ppx）`，`ix = floor(X)`，`frac = X − ix`，`bin = floor(frac × 4 + 0.5)`；`bin = 4` 时 `ix += 1, bin = 0`。因此档位分界为 0.125、0.375、0.625、0.875，负坐标同样适用。光栅化时以 `bin / 4` ppx 的水平偏移生成位图。

**REQ-TEXT-027**　字形光栅化**必须**为**灰度**抗锯齿（A8 覆盖率），**不得**使用 ClearType 子像素渲染，输出中不得含有彩色滤色边（ADR 0003）。灰度覆盖率以 sRGB 编码空间与前景色混合（REQ-GFX-009）。覆盖率的具体生成方式（DirectWrite 的取法、对比度/伽马调整）见 REQ-TEXT-035 与 TEXT-OPEN-05。

**REQ-TEXT-028**　图集驻留与淘汰：
1. **驻留不变量**：任何在本构建代内被获取的 `Layout`（含缓存命中）所引用的字形，必须在其被获取的那一刻已驻留于图集（缺失者在此时光栅化并写入影子缓冲、`markDirty`）。绘制阶段（`gfx` 绘制遍内）**不得**光栅化、**不得**分配图集空间；`text.draw` 遇到未驻留字形时跳过该字形，调试构建断言。
2. 每页有 `epoch`；整页淘汰使该页 `epoch` 加 1。`Layout` 缓存条目记录所用页的 `(页号, epoch)` 列表，命中时若任一页 `epoch` 已变，则**仅重新光栅化**缺失字形（不重新整形，`text.shape_count` 不增，`text.raster_count` 增加）。
3. **整页淘汰**：新字形装不下且页数已达上限时，在"本构建代内未被触达"的页中选择最后触达代最小者，清空并重新装箱；若所有页都在本构建代被触达，**允许**临时新增至多 2 个溢出页，并在下一次构建完成后回收；溢出页也耗尽时，新字形不显示，记录一条 `warn` 日志（同一代只记一次）。
4. 淘汰是整页进行的，不做单字形淘汰。

**REQ-TEXT-029**　图集更新**必须**只在绘制阶段开始前批量上传：光栅化发生在构建/布局阶段（`layout` 调用内），结果写入影子缓冲并 `markDirty`；实际 `glTexSubImage2D` 由 `gfx.flushUploads()` 在一帧第一个绘制遍之前执行（REQ-GFX-020）。每页每帧至多一次上传调用（REQ-GFX-029）。

**REQ-TEXT-030**　彩色字形（emoji 等）使用**单独的 RGBA 页**（`rgba8` 预乘），键同 REQ-TEXT-026（子像素档位恒 0），经 `drawGlyphQuads(.., .rgba, ..)` 绘制。彩色字形支持列为 **M6、"应当"**：在此之前，彩色字形**应当**退化为字体提供的单色字形，无单色字形时显示缺字字形，且不创建 RGBA 页。

**REQ-TEXT-031**　`text.draw(canvas, layout, origin: Vec2, color: Color, opts: DrawOptions)` 把 `Layout` 的字形转为四边形并调用 `Canvas.drawGlyphQuads`：`origin`（lpx）的 x、y 先各自按 `round(v × scale)` 取整为整数 ppx；按页、按 `GlyphKind` 分组，每组一次调用（REQ-GFX-027）；`opts.spans: []ColorSpan`（`{ start, end, color }`，字节范围，互不重叠）用于选中文字换色等，范围内的字形使用该色，其余使用 `color`；`opts.line_range: ?Range` 限定只绘制部分行（虚拟化长文本）。`draw` 不修改任何缓存状态，满足绘制函数的纯函数约束（REQ-FRAME-018）。

### 3.6 Win32 后端：DirectWrite

**REQ-TEXT-032**　DirectWrite 后端的 COM 生命周期约定：
1. `IDWriteFactory`（共享型 `DWRITE_FACTORY_TYPE_SHARED`，需 `IDWriteFactory2` 及以上以获取系统回退）在 `text.init` 创建，`text.deinit` 释放；系统字体集合与回退对象同。
2. 每个 COM 接口指针由**唯一的所有者**持有，使用薄封装 `Com(T)`（`release()` 后指针置空）；**不得**复制裸指针长期持有；`AddRef` 仅在跨作用域转移所有权时使用并成对出现。
3. `layout` 内创建的 `IDWriteTextFormat`/`IDWriteTextLayout` 等瞬时对象**必须**在同一函数返回前释放（REQ-TEXT-012）；跨调用保留的只有工厂、字体集合、回退、`IDWriteFontFace` 缓存（`FaceId` → `IDWriteFontFace`，随字体设置变化清空）。
4. 全部 COM 调用在界面线程进行（REQ-ARCH-007）。
5. 调试构建统计各接口类型的未释放数，`text.deinit` 时必须全为 0，否则以非零码退出并列出接口类型。
6. HRESULT 失败：创建工厂失败走 `platform.fatal`；单次排版失败退化为空 `Layout`（尺寸 0）并记录一条 `err` 日志，不向调用方返回错误（REQ-ARCH-018）。

**REQ-TEXT-033**　字体选择：
1. `Family.ui` 取 `platform.appearance(window).message_font.family`（REQ-PLAT-043），字号基准取其 `size_lpx`（REQ-THEME-016 的 B）；若该字族在系统字体集合中不存在，依次回退 `Segoe UI`、`Arial`。
2. `Family.mono` 依次尝试 `Cascadia Mono`、`Consolas`，皆无时取 `Courier New`（REQ-THEME-015；"系统默认等宽字体"在此定为 `Courier New`，见 TEXT-OPEN-06）；解析结果在 `text.init` 与字体设置变化时确定并缓存，可经 `text.resolvedFamily(family)` 查询。
3. 字重 `weight` 映射到 DirectWrite 的字重枚举（取最近值），`italic` 映射到斜体样式；字体族无对应字重时由 DirectWrite 就近匹配，**不得**模拟加粗或斜体（`DWRITE_FONT_SIMULATIONS_NONE`）。
4. **字体回退**使用系统回退（`IDWriteFontFallback`，来自 `IDWriteFactory2::GetSystemFontFallback`）并通过 `IDWriteTextFormat1::SetFontFallback` 应用，中文、日文、韩文、符号与 emoji 的回退字体由系统决定；**不内嵌字体**（ADR 0003）。

**REQ-TEXT-034**　整形、断行与命中：`layout` 创建瞬时 `IDWriteTextLayout`（输入为规范化 UTF-16，字号 = `ppx_size`，最大宽度 = `max_width_ppx`，换行与修剪按 `LayoutOptions` 设置，基准阅读方向固定为从左到右），由其完成整形、断行（以 `IDWriteTextLayout` 的断行结果为准，REQ-TEXT-016 的差异见 TEXT-OPEN-04）、双向重排；随后经 `GetLineMetrics`、`GetClusterMetrics`、`HitTestTextPosition`/`HitTestTextRange` 与字形运行枚举（`IDWriteTextRenderer` 回调或等价手段）**一次性**提取为 `Layout`（REQ-TEXT-012）。提取时**必须**建立 UTF-16 → UTF-8 的偏移映射（单调数组），代理对不得被拆分；DirectWrite 报告的簇边界与字素簇边界不一致时，以字素簇边界为准（REQ-TEXT-012 的插值规则）。省略号由 `LayoutOptions` 驱动、在提取结果中作 `is_ellipsis` 运行，而不使用 DirectWrite 的修剪对象，以保证 REQ-TEXT-015 的"不裁半字形"在三个后端一致。

**REQ-TEXT-035**　字形光栅化使用 `IDWriteGlyphRunAnalysis`：对单个字形（`DWRITE_GLYPH_RUN`，`fontEmSize = ppx_size`，基线原点的 x 小数部分 = `bin / 4`，y = 0）创建分析对象，取 `GetAlphaBounds` 与 `GetAlphaTexture` 得到覆盖率，转为 A8 写入图集。转换必须满足 REQ-TEXT-027（输出灰度、无彩色边）。渲染模式与网格适配参数固定（不随显示器变化），使同一机器、同一版本的光栅结果可重复（REQ-TEXT-013 的缓存正确性与金图稳定性依赖于此）；具体参数选取与对比度调整见 TEXT-OPEN-05。单个字形位图超过 256×256 ppx 时不入图集，该字形跳过并记录 `warn`（极端大字号不属于本框架场景，REQ-THEME-016）。

**REQ-TEXT-036**　系统字体或显示设置变化（`platform` 的 `system_changed{font}`、`dpi_changed`）时，`text` **必须**：清空排版缓存（REQ-TEXT-013）、清空全部图集页（所有页 `epoch` 加 1）、释放并重建 `IDWriteFontFace` 缓存、重新解析 `ui`/`mono` 字族（REQ-TEXT-033）。该清理在下一次构建开始前完成，之后的 `layout` 全部重新整形。

### 3.7 GLFW 后端与固定度量后端

**REQ-TEXT-037**　`fontstash` 后端：以 NanoVG 的 fontstash（stb_truetype）加载仓库内的测试字体文件，放在 `tests/fonts/`，字体文件及其许可文本一并入库，许可与登记要求见 ADR 0010 与 REQ-CONV-031、REQ-CONV-032（来源不明的字体不得入库）。该后端**只保证**：度量稳定（同一字体文件、字号、`scale` 下跨运行与跨机器的宽度、行高逐位相同）；拉丁字母（U+0020–U+007E、U+00A0–U+00FF）、《通用规范汉字表》一级字（3500 字）及常用中文标点、KS X 1001 收录的 2350 个现代韩文音节（均位于 U+AC00–U+D7A3）与韩文兼容字母 U+3131–U+3163 可显示。缺字显示缺字字形。韩文只保证预组合音节：组合用字母序列（U+1100–U+11FF、U+A960–U+A97F、U+D7B0–U+D7FF）不合成为音节，按码位逐个字形绘制，字素簇边界仍按 REQ-TEXT-021。该后端不做复杂文种整形、不做字体回退链、不做双向重排（全部按从左到右），且**不保证**与 DirectWrite 像素一致。字族令牌 `ui` 与 `mono` 都解析到测试字体（`mono` 可为同一文件）；其族名为 `NanoTestSans`（REQ-PLAT-084）。光栅化同样遵循 REQ-TEXT-026、REQ-TEXT-027，使用同一图集机制。

**REQ-TEXT-038**　固定度量测试后端 `fixed`：不加载任何字体。**每个字素簇的前进宽度固定**为 `round(0.5 × ppx_size)` ppx（零宽字符与换行簇为 0），`ascent = 1.0 × ppx_size`、`descent = 0.25 × ppx_size`、`line_gap = 0`（均取整规则同 REQ-TEXT-009）。断行严格遵循 REQ-TEXT-016。`text.draw` 不绘制，仅向 `text.testing.drawLog()` 记录 `(layout, origin, color)`。该后端用于布局、控件逻辑的单元测试，使宽度、高度、换行位置、命中位置都可精确断言；`zig build test` 默认使用该后端（`text.backend_name` 为 `"fixed"`），`zig build test-golden` 使用平台默认后端。

### 3.8 输入法组字的绘制支持

**REQ-TEXT-039**　组字串由文本编辑控件**临时插入**排版文本（使换行、宽度、光标位置包含组字内容），并以 `text.drawComposition(canvas, layout, origin, comp, style)` 绘制其下划线与目标子句底色；组字串的字形本身用 `text.draw` 绘制。`Composition` = `{ start: u32（组字串在 Layout 文本中的起始字节偏移）, len: u32, cursor: u32（相对 start）, segments: []const platform.ImeSegment（相对 start）}`；`CompositionStyle` = `{ underline: Color, target_underline: Color, error_underline: Color, target_bg: ?Color }`（颜色由控件从主题令牌取得，`text` 不依赖主题）。下划线规则（宽度以 `hairline = max(1, floor(scale))` ppx 计，全部为整数像素矩形，无抗锯齿）：

| 段样式 | 线型 | 粗细 |
|---|---|---|
| `unconverted` | 点线（亮 `hairline` ppx、灭 `hairline` ppx 交替） | `hairline` |
| `converted` | 实线 | `hairline` |
| `target_converted` | 实线，并以 `target_bg` 填充该段文字背景 | `2 × hairline` |
| `target_unconverted` | 点线，并以 `target_bg` 填充该段文字背景 | `2 × hairline` |
| `error` | 实线，颜色取 `error_underline` | `2 × hairline` |

下划线的上边位于 `baseline + max(1, round(0.1 × ppx_size))` 处；每个段按其所跨行/运行拆分为多条线段（跨软换行时每行一条）。点线的相位自该段起点起算。目标子句背景绘制在字形之前，下划线绘制在字形之后。

**REQ-TEXT-040**　`layout.imeRects(comp) struct { caret: CaretRect, target: ?Rect }` 返回组字光标处的插入符矩形与目标子句（若有）的第一个矩形（lpx，相对 `Layout` 原点）。`text` 只以 lpx 提供这两个矩形；加上控件原点、换算为 ppx（`scale` 取整）并调用 `Window.setImeCaretRect(caret, exclude)`（REQ-PLAT-053）由**框架**（08 的 REQ-INPUT-062）统一完成，**不是控件的职责**。有目标子句时以其矩形作为排除区，否则排除区为空，以插入符矩形为准。

### 3.9 双向文字

**REQ-TEXT-041**　内嵌的 RTL 片段（阿拉伯文、希伯来文等）**必须**被正确显示：字符顺序按 Unicode 双向算法（UAX #9）重排，字形整形正确（阿拉伯文连写）。基准方向固定为从左到右，**不做**界面镜像、不做段落方向自动检测（REQ-VIS-008）。`Layout.runs[i].bidi_level` 与 `clusters[i].bidi_level` 保留层级；`hitTest`、`caretRect`、`selectionRects` 在含 RTL 运行时**必须**按视觉位置给出结果（选区可分裂为同一行内的多个矩形）。仅 DirectWrite 后端提供此能力；`fontstash` 与 `fixed` 后端把全部文字按从左到右处理（降级矩阵 REQ-PLAT-083）。光标在 LTR 与 RTL 混排处的移动规则是待定问题（TEXT-OPEN-01）。

## 4. 接口草案

```zig
// 草案：仅签名
pub const Family = enum(u16) { ui, mono, _ };
pub fn registerFamily(name: []const u8) error{OutOfMemory}!Family;   // 框架复制名字
pub fn resolvedFamily(f: Family) []const u8;

pub const Style = struct {
    family: Family = .ui,
    size: f32,                    // lpx
    weight: u16 = 400,
    italic: bool = false,
};

pub const Wrap = enum { none, word, anywhere };
pub const Align = enum { left, center, right };
pub const Ellipsis = enum { none, end };
pub const Newlines = enum { break_lines, as_space };

pub const LayoutOptions = struct {
    max_width: ?f32 = null,       // lpx
    wrap: Wrap = .none,
    @"align": Align = .left,
    ellipsis: Ellipsis = .none,
    max_lines: ?u32 = null,
    newlines: Newlines = .break_lines,
    tab_width: u8 = 4,
    line_height: ?f32 = null,     // lpx
};

pub const FontMetrics = struct { ascent: f32, descent: f32, line_gap: f32, height: f32 }; // lpx

pub const Affinity = enum { upstream, downstream };
pub const Caret = struct { offset: u32, affinity: Affinity = .downstream };
pub const Range = struct { start: u32, end: u32 };
pub const CaretRect = struct { x: f32, y: f32, h: f32 };
pub const Edge = enum { leading, trailing };

pub const HitResult = struct {
    caret: Caret,
    cluster_start: u32,
    edge: Edge,
    line: u32,
    inside: bool,
};

pub const SelectionOpts = struct { extend_line_breaks: bool = false };

pub const Layout = struct {
    size: core.Size,              // lpx
    scale: f32,
    truncated: bool,
    text_len: u32,

    pub fn lineCount(self: *const Layout) u32;
    pub fn lineOf(self: *const Layout, c: Caret) u32;
    pub fn lineRange(self: *const Layout, line: u32) Range;
    pub fn lineRect(self: *const Layout, line: u32) core.Rect;
    pub fn lineStart(self: *const Layout, c: Caret) Caret;
    pub fn lineEnd(self: *const Layout, c: Caret) Caret;

    pub fn hitTest(self: *const Layout, point: core.Vec2) HitResult;
    pub fn caretRect(self: *const Layout, c: Caret) CaretRect;
    pub fn selectionRects(self: *const Layout, start: u32, end: u32, opts: SelectionOpts, out: *std.ArrayList(core.Rect)) void;
    pub fn moveHorizontal(self: *const Layout, c: Caret, dir: enum { left, right }) Caret;
    pub fn moveVertical(self: *const Layout, c: Caret, dir: enum { up, down }, goal_x: ?f32) struct { caret: Caret, goal_x: f32 };
    pub fn imeRects(self: *const Layout, comp: Composition) struct { caret: CaretRect, target: ?core.Rect };
};

pub const OwnedLayout = struct {
    layout: Layout,
    pub fn deinit(self: *OwnedLayout) void;
};

// 返回的 *const Layout 有效至获取它的构建之后的第二次构建完成（REQ-TEXT-014）
pub fn layout(text: []const u8, style: Style, scale: f32, opts: LayoutOptions) *const Layout;
pub fn layoutOwned(allocator: std.mem.Allocator, text: []const u8, style: Style, scale: f32, opts: LayoutOptions) error{OutOfMemory}!OwnedLayout;
pub fn measure(text: []const u8, style: Style, scale: f32, opts: LayoutOptions) core.Size;
pub fn isTruncated(text: []const u8, style: Style, scale: f32, max_width: f32) bool;
pub fn fontMetrics(style: Style, scale: f32) FontMetrics;
pub fn baselineInBox(box_h: f32, style: Style, line_height: ?f32, scale: f32) f32;

// 字素簇与词（与后端无关）
pub fn nextGrapheme(s: []const u8, offset: usize) usize;
pub fn prevGrapheme(s: []const u8, offset: usize) usize;
pub fn isGraphemeBoundary(s: []const u8, offset: usize) bool;
pub fn nextWord(s: []const u8, offset: usize) usize;
pub fn prevWord(s: []const u8, offset: usize) usize;
pub fn wordRange(s: []const u8, offset: usize) Range;

// 绘制
pub const ColorSpan = struct { start: u32, end: u32, color: core.Color };
pub const DrawOptions = struct { spans: []const ColorSpan = &.{}, line_range: ?Range = null };
pub fn draw(canvas: *gfx.Canvas, l: *const Layout, origin: core.Vec2, color: core.Color, opts: DrawOptions) void;

// 输入法组字
pub const Composition = struct {
    start: u32, len: u32, cursor: u32,
    segments: []const platform.ImeSegment,
};
pub const CompositionStyle = struct {
    underline: core.Color, target_underline: core.Color, error_underline: core.Color,
    target_bg: ?core.Color = null,
};
pub fn drawComposition(canvas: *gfx.Canvas, l: *const Layout, origin: core.Vec2, comp: Composition, style: CompositionStyle) void;

// 生命周期与调度（由 app/ui 调用）
pub fn init(allocator: std.mem.Allocator, cfg: Config) error{OutOfMemory}!void;   // 不可恢复错误走 platform.fatal
pub fn deinit() void;
pub fn beginBuild() void;                 // 构建代 +1
pub fn onSettingsChanged() void;          // REQ-TEXT-036
pub fn trimCache() void;                  // 每次构建完成后调用，按 REQ-TEXT-014 淘汰

pub const Config = struct {
    layout_cache_entries: u32 = 4096,
    layout_cache_bytes: usize = 8 * 1024 * 1024,
    atlas_page_size: u32 = 1024,
    atlas_max_pages: u32 = 16,
};

pub const testing = struct {
    pub const DrawRecord = struct { layout: *const Layout, origin: core.Vec2, color: core.Color };
    pub fn drawLog() []const DrawRecord;
    pub fn atlasStats() struct { pages: u32, used_ppx: u64, raster_count: u64, shape_count: u64 };
};
```

## 5. 边界与错误情况

| 情况 | 规定 |
|---|---|
| 空串 | `Layout` 含 1 个空行：`lineCount() = 1`，`size.h` = 行高，`size.w` = 0，插入符矩形位于 (0, 0)。 |
| `max_width` 小于单个簇宽度 | 每行至少放一个簇（不死循环），该行超出 `max_width`；省略模式下按 REQ-TEXT-015 第 3 条。 |
| `max_width <= 0` | 视为 0；`wrap != .none` 时每行一个簇。 |
| `scale` 非正 | 调试构建断言，发布构建当作 1.0。 |
| `Style.size` 非正或 `NaN` | 同上，当作基准字号 B。 |
| `weight` 超出 1–1000 | 钳制。 |
| 偏移参数非边界 | 见 REQ-TEXT-002。 |
| `hitTest` 的点为 `NaN` | 调试构建断言，发布构建返回 `{offset 0}`。 |
| 文本含 `\0` 字节 | 视为 U+0000 控制字符（REQ-TEXT-004），不终止字符串。 |
| 一帧内排版调用次数极多（每个节点一次） | 允许；命中缓存的开销是哈希加一次文本比对，成本见 12。 |
| 排版缓存被淘汰后控件仍持有 `*const Layout` | 不会发生：受构建代保护（REQ-TEXT-014）；跨越两次构建持有须用 `layoutOwned`。 |
| 图集字形超过页尺寸 | 见 REQ-TEXT-035，跳过并记录。 |
| 系统回退字体缺失导致中文显示方框 | 视为环境问题，显示缺字字形；`debug` 日志记录第一个缺字码点。 |
| 双向文本在 `fontstash` 后端 | 全部按从左到右排列（可读性受限），不崩溃。 |
| 在 `directwrite` 后端于非 Windows 构建 | 编译期不包含；链接任何 DirectWrite 符号即构建失败。 |
| 窗口在不同 DPI 的显示器间拖动 | 两个 `scale` 的 `Layout` 并存于缓存；`dpi_changed` 触发整体清空（REQ-TEXT-036），不保留旧 scale 条目。 |

## 6. 验收标准

除标 `[人工]` 者外，以下测试在 `fixed` 后端（单元）或 GLFW 无头模式（金图）下运行。涉及 DirectWrite 的条款必须在真实 Windows 上执行。`fixed` 后端的度量：`scale = 1.0`、`size = 12` 时每簇前进 6 ppx，`ascent = 12`、`descent = 3`、行高 15。

**AC-TEXT-001**　`[单元]` 覆盖：REQ-TEXT-001。同一份接口一致性测试（`tests/text_conformance.zig`）分别以 `fixed`、`fontstash` 编译运行，Windows 上加 `directwrite`；测试仅断言结构性不变量（REQ-TEXT-012 的不变量、偏移合法性、缓存命中）与按后端分列的度量常量。预期：各后端全部通过。导入检查脚本断言 DirectWrite/COM 符号只出现在 `src/text/directwrite.zig` 或 `src/text/directwrite/` 下；`-Dtext-backend=fixed` 之外的构建不含 `fixed` 后端符号。

**AC-TEXT-002**　`[单元]` 覆盖：REQ-TEXT-002、REQ-TEXT-021。(1) 以 Unicode 官方 `GraphemeBreakTest.txt`（版本与 `unicode_version.zig` 一致）全部用例逐条断言 `isGraphemeBoundary`、`nextGrapheme`、`prevGrapheme`。预期：通过率 100%。(2) 手工向量：`"e\u{0301}"` → 边界 `{0, 3}`；`"🇨🇳🇺🇸"` → `{0, 8, 16}`；`"👨‍👩‍👧"` → `{0, 18}`；`"\r\n"` → `{0, 2}`；`"你好"` → `{0, 3, 6}`；`"한"`（`U+1112 U+1161 U+11AB`）→ 一个簇。(3) 将非边界偏移（如 `"e\u{0301}"` 的 1）传给 `caretRect`、`selectionRects`：调试构建断言中止；发布构建结果与偏移 0 相同；`hitTest` 对任意点返回的偏移全部属于边界集合（1000 个随机点）。

**AC-TEXT-003**　`[单元]` 覆盖：REQ-TEXT-003。输入与预期显示的 U+FFFD 个数（并检查光标偏移基于原始字节）：`"a\xFFb"` → 1；`"\xE4\xB8"` → 1；`"\xC0\x80"` → 2；`"\xED\xA0\x80"` → 3；`"\xF4\x90\x80\x80"` → 4；`"ok\xE4\xB8中"` → 1，且 `中` 的起始偏移为原始串中的 5。每个被替换的非法序列在 `Layout.clusters` 中对应一个簇，其 `byte_start/byte_end` 覆盖原始非法字节。对 1 MiB 的随机字节（固定种子）重复 1000 次 `layout`：不崩溃、不越界，`clusters` 满足 REQ-TEXT-012 的不变量。

**AC-TEXT-004**　`[单元]` 覆盖：REQ-TEXT-004。`fixed` 后端（制表位 4，即每 24 ppx）：(1) `"a\tb"`：`a` 占 [0,6)，`b` 占 [24,30)，总宽 30。(2) `"a\nb"` 2 行；`"a\r\nb"` 2 行且 `\r\n` 为一个簇；孤立 `"a\rb"` 2 行；`U+2028`、`U+2029`、`U+0085` 同样 2 行。(3) `newlines = .as_space`：`"a\r\nb"` 宽 18、1 行。(4) `U+200B`：宽 0、独立簇，`wrap = .word` 时在其后断行。(5) `U+0007`（BEL）：不产生字形（`glyphs` 数 0）、宽 0、占 1 个簇。(6) 含 ZWJ 的 emoji 序列 `"👨‍👩‍👧"` 为 1 个簇、宽 6。(7) 末尾换行 `"a\n"`：2 行（第二行为空行）。

**AC-TEXT-005**　`[单元]` 覆盖：REQ-TEXT-005。(1) 1 MiB 的 `x`：`layout` 返回，`truncated = true`，被排版字节 ≤ 262 144（+ 省略号），产生恰 1 条 `warn`（同一内容再次调用不再产生）；调用返回后立即改写原缓冲，不影响 `Layout`（AC-ARCH-009）。(2) 100 个 `x` 无空格，`wrap = .word`、`max_width = 100`：每行 16 个字符（96 ≤ 100），共 7 行（最后一行 4 个字符）。(3) `"e\u{0301}"` 重复 40 次、`max_width = 60`：每行恰 10 个簇，所有行首行尾偏移均为字素簇边界（组合符不会被孤立到行首）。(4) `wrap = .none`、`ellipsis = .end` 的超长串得到以 `…` 结尾的单行。

**AC-TEXT-006**　`[单元]` 覆盖：REQ-TEXT-006、REQ-TEXT-007。(1) `Style` 相等与哈希：仅 `size` 相差小于 1/64 lpx 的两个 `Style` 哈希相等且比较为等；`weight`、`italic`、`family` 任一不同则不等。(2) `registerFamily("Foo")` 后改写传入缓冲，`resolvedFamily` 仍为 `"Foo"`；两次注册同名返回同一令牌。(3) `fontMetrics(Style{.size = 12}, 1.0)` 在 `fixed` 后端为 `{ascent 12, descent 3, line_gap 0, height 15}`；`line_height = 20` 的 `layout` 行高为 20。

**AC-TEXT-007**　`[单元]` 覆盖：REQ-TEXT-008、REQ-TEXT-009。(1) `scale = 1.25`、`size = 12`（`ppx_size = 15`，每簇前进 `round(7.5) = 8` ppx）：`measure("abcd")` 宽 = 32 / 1.25 = 25.6 lpx；`layout` 行高 `round(18.75) = 19` ppx，三行文本各基线相差恰 19 ppx 且均为整数。(2) `baselineInBox(24, style, null, 1.25)`：`box_h_ppx = 30`，`top = floor((30 − 19) / 2) = 5`，基线 = 5 + `round(ascent 15 → 15)` = 20 ppx = 16.0 lpx。(3) 对 scale ∈ {1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0} 与盒高 ∈ {20, 24, 28, 32} lpx：`baselineInBox × scale` 与最近整数之差 < 1e-4。(4) 同一字符串在 scale 1.0 与 1.25 下的 `Layout` 是两个独立缓存条目（`text.shape_count` +2）。

**AC-TEXT-008**　`[单元]` 覆盖：REQ-TEXT-010、REQ-TEXT-011、REQ-TEXT-017。`fixed` 后端，`"hello world foo"`（15 个簇，宽 90）：(1) `measure` 与 `layout().size` 逐字段相等，且调用 `measure` 不增加 `text.shape_count`（先 `layout` 后 `measure`）。(2) `wrap = .word`、`max_width = 60`：2 行，第一行字节范围 `[0, 6)`（含悬挂空格）、宽 30，第二行 `[6, 15)`、宽 54，`size.w = 54`。(3) `align = .center`：两行 `x_offset` 分别为 15、3；`.right`：30、6；`.left`：0、0。(4) `wrap = .anywhere`、`max_width = 60`：第一行 `"hello worl"`、第二行 `"d foo"`。(5) `max_width = null` 时 `align` 被忽略。(6) 尾随悬挂空白不计入行宽：`"hello "` 在 `max_width = 30` 下为 1 行（宽 30）。(7) `max_lines = 1`、`wrap = .word`、`ellipsis = .end`、`max_width = 60`：第一行 `"hello…"`（先按词断行得到 `"hello "`，去掉行尾空格得 `"hello"`（30），附加 `…`（6）宽 36 ≤ 60，无需回退），`truncated = true`；另 `max_width = 33`、`max_lines = 1`：行内容 `"hello"`（30）+ `…`（6）= 36 > 33，按整簇回退为 `"hell…"`（宽 30），`truncated = true`。

**AC-TEXT-009**　`[单元]` 覆盖：REQ-TEXT-012。对 1000 个混合脚本字符串（拉丁、汉字、emoji、组合符、制表符、换行；固定种子）与 4 种选项组合排版，断言：`clusters` 覆盖 `[0, text_len)` 无间隙无重叠；每个簇边界满足 `isGraphemeBoundary`；各行字节范围按序相接；`lines`/`runs`/`glyphs` 的下标范围合法；`clusters[i].x1 ≥ clusters[i].x0`（LTR）。在 `directwrite` 后端（`[人工]`，Windows）追加：`layout` 返回后接口计数回到调用前，随后的 `hitTest` 等调用期间 COM 调用计数为 0。

**AC-TEXT-010**　`[计量]` 覆盖：REQ-TEXT-013。"控件总览"页含 50 个标签：(1) 100 帧（含 `-Dforce-rebuild`）：`text.shape_count` 总增量 = 50（仅首帧），之后缓存命中率 100%。(2) 修改一个标签的文本：`shape_count` +1。(3) 触发 `dpi_changed`：条目数归 0，随后重建，`shape_count` +50。(4) 容量测试：上限 1024 条目，写入 10 000 个互不相同的字符串：`cache.text_layout.entries ≤ 1024` 且 `bytes` ≤ 上限；最近使用的 100 条在写入后仍命中。(5) 键敏感性：`max_width` 相差 0.3 ppx → 同一条目；相差 1.5 ppx、`wrap`、`ellipsis`、`align`、`scale`、`Style` 任一字段不同 → 不同条目。(6) 构造两个哈希碰撞的不同文本（测试钩子强制同哈希）：互不污染。

**AC-TEXT-011**　`[单元]` 覆盖：REQ-TEXT-014。缓存容量设为 8 条目。构建 N 获取 8 个 `Layout`；构建 N+1 获取另 8 个：构建 N+1 完成前，构建 N 的 8 个指针内容仍有效且未被覆盖（逐字段与保存的副本比较）；两次构建之间执行 5 个纯绘制帧，`Layout` 内容不变。构建 N+2 完成后：构建 N 的条目可被淘汰（条目数 ≤ 8）。`layoutOwned` 的结果在 `onSettingsChanged()` 清空缓存后仍有效，`deinit` 后无泄漏（测试分配器泄漏检测通过）。

**AC-TEXT-012**　`[单元]` 覆盖：REQ-TEXT-015。`fixed` 后端：(1) `"abcdefghij"`（宽 60）`max_width = 36`、`ellipsis = .end`：保留 `"abcde"` + `…`，总宽 36，`truncated = true`，省略号运行 `is_ellipsis`，其簇偏移为 5。(2) `max_width = 5`：不显示任何字形，`truncated = true`。(3) `max_width = 60`：不截断，`truncated = false`。(4) `"ab cd"`、`max_width = 24`：前缀 `"ab "` 去除尾随空白后为 `"ab…"`（3 个字形，宽 18）。(5) `"e\u{0301}e\u{0301}e\u{0301}e\u{0301}"`（4 个簇）`max_width = 18`：保留 2 个完整簇 + `…`，不出现孤立的组合符；`"👨‍👩‍👧👨‍👩‍👧👨‍👩‍👧"` 同理不拆分。(6) 对省略号字形 `hitTest` 返回偏移 5。(7) `isTruncated` 与 `layout(...).truncated` 一致。(8) `wrap = .word`、`max_lines = 2`、宽度使文本需要 3 行：第 2 行以 `…` 结尾；未设 `max_lines` 的 `wrap = .word` + `ellipsis = .end` 不产生省略。`[金图]` 补充：见 AC-THEME-013。

**AC-TEXT-013**　`[单元]` 覆盖：REQ-TEXT-016。`fixed` 后端：(1) `"你好，世界"`、`wrap = .word`、`max_width = 12`：3 行 `"你"`、`"好，"`、`"世界"`（逗号不在行首）。(2) `"（你好）"`、`max_width = 12`：`（` 不在行尾：行为 `"（你"` / `"好）"`。(3) `"well-known state"`、`max_width = 36`：断在 `-` 之后 → `"well-"` / `"known"` / `"state"`（`known state` = 66 > 36）。(4) 假名小字 `"きょう"`、`max_width = 12`：`ょ` 不在行首，结果为 `"きょ"` / `"う"`。(5) 单个 20 簇的拉丁单词、`max_width = 60`：每行 10 簇强制断行。(6) `U+200B` 之后可断。(7) 汉字之间任意两簇可断，英文单词内部不可断。

**AC-TEXT-014**　`[单元]` 覆盖：REQ-TEXT-018、REQ-TEXT-019。`fixed` 后端，`"abcd"`（每簇 6，行高 15）：(1) `hitTest((8, 5))` → `offset 1`、`edge leading`（点在簇 1 前半）；`hitTest((9, 5))` → `offset 2`、`edge trailing`（恰在中点取 trailing）；`hitTest((−3, 5))` → `offset 0`、`inside = false`；`hitTest((100, 5))` → `offset 4`、`inside = false`；y = −5 → 行 0；y = 999 → 末行。(2) `"a👨‍👩‍👧b"`：边界偏移集合恰为 `{0, 1, 19, 20}`，任意点命中结果的偏移都属于该集合。(3) `caretRect(offset 2)` = `{x 12, y 0, h 15}`；`scale = 1.25` 时 `x = round(2 × 8) / 1.25 = 12.8`，`x × scale` 为整数。(4) `"hello world"` `wrap = .word`、`max_width = 36`（"hello " 一行）：`caretRect({6, upstream})` 位于第 0 行末（x = 30，y = 0），`caretRect({6, downstream})` 位于第 1 行首（x = 0，y = 15）；`hitTest` 点在第 0 行右侧之外返回 `{6, upstream}`，点在第 1 行左侧之外返回 `{6, downstream}`。

**AC-TEXT-015**　`[单元]` 覆盖：REQ-TEXT-020。`fixed` 后端，`"hello world foo"`、`wrap = .word`、`max_width = 60`（见 AC-TEXT-008 的两行）：(1) 选区 `[3, 9)` → 两个矩形：第 0 行 `{x 18, y 0, w 18, h 15}`（`"lo "`）与第 1 行 `{x 0, y 15, w 18, h 15}`（`"wor"`）。(2) 选区 `[0, 5)` 一个矩形 `{0, 0, 30, 15}`；`start == end` 输出空；`start > end` 与交换后结果相同。(3) 含硬换行文本 `"ab\ncd"` 选区 `[0, 3)`：`extend_line_breaks = false` 时第 0 行矩形宽 12；`= true` 时宽 18。(4) 同行内相邻矩形已合并（对 `[0, 15)` 逐字符相邻的选区，每行恰 1 个矩形）。(5) `scale = 1.25` 下所有矩形边界 × `scale` 为整数。

**AC-TEXT-016**　`[单元]` 覆盖：REQ-TEXT-022。表驱动（后端无关）：
| 文本 | 调用 | 预期 |
|---|---|---|
| `hello world` | `nextWord(0)` / `nextWord(6)` / `nextWord(11)` | 6 / 11 / 11 |
| `hello world` | `prevWord(11)` / `prevWord(6)` / `prevWord(3)` | 6 / 0 / 0 |
| `hello world` | `wordRange(2)` / `wordRange(5)` / `wordRange(11)` | [0,5) / [5,6) / [6,11) |
| `hello, world` | `nextWord` 自 0 | 依次 5, 7, 12 |
| `你好世界` | `nextWord` 自 0 | 依次 3, 6, 9, 12 |
| `abc你好def` | `nextWord` 自 0 | 依次 3, 6, 9, 12 |
| `カタカナです` | `nextWord(0)` | 12（片假名连续序列为一个词单元，后接平假名新词） |
| `foo_bar1 baz` | `nextWord(0)` | 9 |

另：`wordRange` 对空白范围不含尾随空白；偏移 0 与 `len` 的边界行为；所有返回值都是字素簇边界（随机 1000 个字符串）。

**AC-TEXT-017**　`[单元]` 覆盖：REQ-TEXT-023、REQ-TEXT-024。`fixed` 后端，`"hello world foo"` 两行排版（AC-TEXT-008 第 2 项）：(1) `lineCount = 2`；`lineOf({6, upstream}) = 0`、`lineOf({6, downstream}) = 1`；`lineRange(0) = [0,6)`、`lineRange(1) = [6,15)`；`lineStart/lineEnd`：行 0 为 0/5（`lineEnd` 位于最后一个非悬挂空白簇之后），行 1 为 6/15。(2) `moveVertical` 自 `{3}`（行 0，x = 18）向下：`goal_x = 18`，到偏移 9（行 1，3 个簇）；再向下：返回 15（末行向下 → `text_len`）；自 `{3}` 向上：偏移 0。短行保持 `goal_x`：在三行文本 `"abcdef\nab\nabcdef"` 中，自偏移 5（x = 30）向下到偏移 9（第二行行末，换行符之前，x = 12），再向下到偏移 15（第三行 x = 30，`goal_x` 仍为 30）。(3) `moveHorizontal` 对 `"e\u{0301}x"` 自 0 向右 → 3 → 4；向左逆序；跨软换行处亲和性按 REQ-TEXT-018 第 5 条变化；对 `"a\nb"` 在偏移 1 向右 → 2（换行簇之后），向左回 1。

**AC-TEXT-018**　`[单元]` 覆盖：REQ-TEXT-025、REQ-TEXT-026。(1) 子像素档位表：`X = 10 + frac`，`frac` = 0.00 → bin 0；0.12 → 0；0.125 → 1；0.37 → 1；0.375 → 2；0.62 → 2；0.625 → 3；0.87 → 3；0.875 → `ix = 11, bin 0`；`X = −0.3`（`floor = −1`，`frac = 0.7`）→ `ix −1, bin 3`。(2) 图集键：同 `(face, glyph, ppx_size, bin)` 只光栅化一次（`raster_count` +1）；`bin` 不同 → 不同槽；`ppx_size` 15 与 15.25 → 不同槽，15 与 15.1 → 同一槽（量化 1/4）；垂直小数位置不产生新槽。(3) 页：测试配置 128×128、上限 2 页，写入字形直到满（每字形 20×20，每页容纳 25 个）：第 26 个字形装入第 2 页；每个字形的位图周围有 1 ppx 透明边距（读影子缓冲验证）。(4) `text.atlas_pages/atlas_used_ppx` 埋点与实际一致。

**AC-TEXT-019**　`[金图]` 覆盖：REQ-TEXT-027、REQ-TEXT-031、REQ-TEXT-026。在 scale = 1.0、1.25、1.5、2.0 下以 `#000000` 在 `#FFFFFF` 上绘制 `"Hxg中 lil"`，并以 `#FF0000` 绘制一份。预期：黑字案例中每个文字区域像素 R = G = B（无彩色边）；红字案例中 G = B 且 R = 255；`l` 在 4 个不同子像素档位（通过 `origin.x` 加 0、0.25、0.5、0.75 ppx 的偏移）绘制得到 4 种互不相同的位图；同一档位重复绘制逐像素相同；`draw` 前后排版缓存与图集状态不变；`spans` 把 `"xg"` 改为 `#FF0000` 时仅该范围字形变色；`origin` 为小数时字形基线仍落在整数像素行。`glfw` 与 `win32` 后端各存基准（REQ-GFX-040）。

**AC-TEXT-020**　`[单元]` 覆盖：REQ-TEXT-028、REQ-TEXT-029、REQ-TEXT-025。测试配置：页 128×128、最多 2 页、`fixed` 光栅化桩（每字形位图 20×20，加 1 ppx 边距后占 22×22）。按行式装箱，每行放 `floor(128 / 22) = 5` 个、共 `floor(128 / 22) = 5` 行，故**每页恰容纳 25 个字形**。步骤：构建 1 获取含 25 个不同字形的 `Layout` L1（占满第 1 页）；构建 2 获取 L2（25 个新字形，占满第 2 页）；构建 3 仅获取 L3（新增 10 个字形）。预期：构建 3 时第 1 页（最后触达代最小）被整页淘汰，其 `epoch` +1，L3 写入该页（装入 10 个，页内余 15 个空位）；随后再获取 L1（缓存命中）：`shape_count` 不变，`raster_count` 增加（重新光栅化 L1 的缺失字形，其中需要空间的字形触发第 2 页的整页淘汰判定：此时第 1 页本代已被触达，第 2 页未被触达，故淘汰第 2 页）。溢出页场景：构建 3 改为同时获取 L1、L2（缓存命中，两页都在本代被触达）与含 10 个新字形的 L3：预期临时新增溢出页（总页 3），L3 写入其中；下一次构建完成后页数回到 2。溢出耗尽场景：构建 3 同时获取 L1、L2 与含 60 个新字形的 L3：2 个溢出页共容纳 50 个，其余 10 个不显示，`warn` 恰 1 条，总页数不超过 4。绘制遍内断言：以 `gfx` 调用跟踪确认 `beginFrame` 与 `endFrame` 之间 `text.raster_count` 不变、纹理上传调用为 0；故意制造一个未驻留字形：`text.draw` 跳过它，调试构建断言。另用默认页配置（1024×1024）：一帧内构建期光栅化 100 个字形，`glTexSubImage2D` 恰每页 1 次（REQ-GFX-029）。

**AC-TEXT-021**　`[单元]` 覆盖：REQ-TEXT-030。M6 前：含 `"😀"` 的文本在 `directwrite` 后端不创建 RGBA 页（`atlas_rgba_pages = 0`），显示单色字形或缺字字形且不崩溃。M6 起另补 `[人工]`：Windows 上显示 `"😀👨‍👩‍👧🇨🇳"`，预期为彩色字形、尺寸与相邻文字协调（高度约为字体行高）、按 `drawGlyphQuads(.rgba)` 绘制，`color.a = 128` 时整体半透明，ZWJ 序列显示为一个字形。

**AC-TEXT-022**　`[人工]` 覆盖：REQ-TEXT-032、REQ-TEXT-033、REQ-TEXT-034、REQ-TEXT-035。Windows（缩放 100%、125%、150%、200% 各一遍）上运行"文字"示例页，显示 `"Hello 世界 مرحبا שלום 😀"` 以及一个等宽样本 `"0O1lI {}[]"`。观察要点：(1) 拉丁字母字体与同机记事本/资源管理器菜单一致（默认 Segoe UI）；汉字为系统回退字体（如 Microsoft YaHei UI），无豆腐块；(2) 阿拉伯文连写正确、希伯来文与阿拉伯文均自右向左排列，与记事本同一字符串的显示顺序一致；(3) 等宽样本使用 Cascadia Mono，卸载后依次为 Consolas、Courier New（经 `text.resolvedFamily(.mono)` 显示核对）；(4) 字重 400 与 600 视觉可区分，且无合成加粗（与系统 UI 字体的真实粗体字形一致）；(5) 文字边缘为灰度抗锯齿，用放大镜检查无彩色边；(6) 与截图对比，同一字号的文字宽度与记事本相差 ≤ 1 ppx/行（相同字体、字号与缩放）。

**AC-TEXT-023**　`[人工]` 覆盖：REQ-TEXT-032。Windows 调试构建：启动 `text.init` 后记录各 COM 接口的未释放计数 `C0`；执行 1000 次不同文本的 `layout` 与 100 次 `onSettingsChanged`；预期计数回到 `C0`（仅工厂、字体集合、回退与缓存的字体面）；`text.deinit` 后所有接口计数为 0，进程退出码 0。向封装 `Com(T)` 重复 `release()`：第二次无效果且不崩溃；故意泄漏一个接口：`deinit` 时以非零码退出并列出接口类型。强制 `CreateTextLayout` 返回失败的测试钩子：`layout` 返回尺寸 0 的 `Layout`、记录 1 条 `err`，调用方无需 `try`。

**AC-TEXT-024**　`[单元]` 覆盖：REQ-TEXT-033、REQ-TEXT-006。用字体集合桩测试字族解析：`message_font.family = "Segoe UI"` 且存在 → `ui` 解析为它；`"Segoe UI"` 缺失且存在 `Arial` → `Arial`；两者都缺失 → 不崩溃并记录 `warn`。`mono`：桩集合 `{Cascadia Mono, Consolas}` → `Cascadia Mono`；`{Consolas}` → `Consolas`；`{}` → `Courier New`。`weight` 400/600 映射到 DirectWrite 字重常量，480 → 就近 500；传给 DirectWrite 的模拟标志恒为无模拟。`onSettingsChanged` 后重新解析。（桩层纯逻辑，可在 Linux 运行。）

**AC-TEXT-025**　`[单元]` 覆盖：REQ-TEXT-034。偏移映射函数表驱动：`"a😀你"`：UTF-16 `{0, 1, 3, 4}` ↔ UTF-8 `{0, 1, 5, 8}` 双向换算；UTF-16 位置 2（代理对内部）不可映射（返回向前对齐到 1）。DirectWrite 桩返回的簇边界：连字 `"fi"` 为一个整形簇 `[0, 2)`（UTF-16），字素簇为两个：`Layout.clusters` 为两个簇，其中间边界 `x` 为该整形簇宽度的一半；桩返回的簇粗于字素簇（组合字符序列被拆成两个整形簇）时，`Layout` 的簇仍为一个字素簇，`caretRect` 不会落在其内部；省略号路径不调用 DirectWrite 的修剪对象（桩断言未被调用）。

**AC-TEXT-026**　`[人工]` 覆盖：REQ-TEXT-036。Windows 上运行含大量文字的示例页（含 `stats` 叠加）。依次：更改系统缩放（跨显示器拖动窗口）、更改"文本大小"辅助功能、更改系统消息字体（注册表或第三方工具）。预期：每次变化后 1 秒内文字完成更新，字形清晰无旧字号残留；`cache.text_layout.entries` 在变化后的第一次构建前为 0；`atlas_used_ppx` 回落后重新增长；`raster_count` 与 `shape_count` 在变化后重新增长；无崩溃、无内存增长（连续切换 20 次后 `atlas_pages` ≤ 上限）。

**AC-TEXT-027**　`[单元]` 覆盖：REQ-TEXT-037。(1) 度量稳定：`measure("Hello, 世界", NanoTestSans 12, 1.0)` 与 `tests/golden-metrics.txt` 中记录的常量逐位相等，`measure("안녕하세요", NanoTestSans 12, 1.0)` 同样与该文件中记录的常量逐位相等；两台不同机器（CI 与本地）与 100 次重复结果相同；`scale = 1.25/1.5/2.0` 同理。(2) 覆盖：U+0020–U+007E、U+00A0–U+00FF、U+3131–U+3163 与 `tests/fonts/coverage.txt` 列出的全部 3500 个一级字、常用中文标点及 2350 个 KS X 1001 韩文音节，字体均含非缺字字形；组合用字母序列 U+1100 U+1161 不合成为 U+AC00，排版结果为一个字素簇，宽度等于两个码位各自字形（或缺字字形）宽度之和；缺字（如 U+0E01）显示缺字字形且宽度等于其字形宽度。(3) 阿拉伯文串在 `fontstash` 后端按从左到右排版、不崩溃。(4) `tests/fonts/` 下每个字体文件有对应的许可文本，并在 `THIRD_PARTY_NOTICES.md` 中登记（REQ-CONV-032，与 AC-CONV-030 为同一检查）；脚本断言无未登记的字体文件。

**AC-TEXT-028**　`[单元]` 覆盖：REQ-TEXT-038。`zig build test` 的默认 `text.backend_name == "fixed"`；`measure("abcd", 12, 1.0) = {24, 15}`；`scale = 1.25` 时每簇 8 ppx（`round(0.5 × 15)`）；`"\u{200B}"`、`"\n"`、BEL 的宽度为 0；`text.draw` 不触碰图集与 `gfx`，`testing.drawLog()` 记录每次调用的 `(layout, origin, color)`；`test-golden` 构建使用 `fontstash`（`backend_name == "fontstash"`）。

**AC-TEXT-029**　`[金图]` 覆盖：REQ-TEXT-039、REQ-TEXT-040。构造 `"你好"` 后插入组字串 `"ni hao"` 于偏移 6，段落为 `[{0,2,unconverted},{3,6,converted},...]` 并增加 `target_converted`、`target_unconverted`、`error` 各一段（共 5 种样式），在 scale = 1.0/1.5/2.0 下绘制。预期（逐样式读回像素）：下划线线粗依次为 hairline（1,1,2 ppx）与 `2 × hairline`（2,2,4 ppx）；点线的亮暗交替周期为 `hairline` ppx，相位自段起点；下划线上边位于基线下 `max(1, round(0.1 × ppx_size))` ppx；全部为整数像素矩形（无中间色）；`target_bg` 仅填充目标子句文字背景且位于字形之下；跨软换行的段落每行一条线；与基准一致。`imeRects(comp).caret` 等于 `caretRect({comp.start + comp.cursor})`；有目标子句时 `target` 等于其首个选区矩形；框架换算后传给 `setImeCaretRect` 的矩形 = lpx 矩形 × `scale` 向外取整，误差 ≤ 1 ppx。

**AC-TEXT-030**　`[人工]` 覆盖：REQ-TEXT-039、REQ-TEXT-040。Windows 上用微软拼音在示例多行文本框输入 `"nihao"`：未转换时下划线为点线；按空格进入转换后目标子句出现粗实线与底色，其余子句为细实线；用方向键切换目标子句时粗线与底色随之移动；输入法候选窗紧贴目标子句（偏差 ≤ 4 ppx）且不遮挡组字串；跨软换行的长组字串每行均有下划线；与记事本同一输入对比，组字下划线的线型一致（点线/实线/粗实线）。在 125%、150% 缩放与文本框滚动后重复。

**AC-TEXT-031**　`[人工]` 覆盖：REQ-TEXT-041。Windows 上显示并交互：`"abc אבג def"`、`"مرحبا بالعالم 123"`、`"价格 ‏١٢٣ 元"`。预期：字符顺序与记事本相同字符串的显示一致；纯阿拉伯文的标签仍靠左对齐（基准方向 LTR、无镜像）；点击 RTL 片段内部，插入符落在点击处最近的视觉边界；拖选跨越 LTR/RTL 边界的范围时，选区在同一行显示为两个或更多矩形，覆盖所有被选字符且不覆盖未选字符；数字 `123` 在 RTL 文中仍从左到右。`[单元]` 补充：用提供 bidi 运行的 DirectWrite 桩数据（一行内 LTR、RTL、LTR 三个运行），断言 `selectionRects` 对跨运行选区返回 2–3 个矩形且彼此不相交，`hitTest` 对每个运行内部的点返回该运行内的偏移；在 `fontstash`、`fixed` 后端中同一字符串全部按 LTR 排列且不崩溃。

## 7. 待定问题

- **TEXT-OPEN-01**　LTR 与 RTL 混排处插入符的左右移动规则：**视觉移动**（Left 始终使插入符向视觉左侧移动，Windows 编辑控件的行为）还是**逻辑移动**（按字符顺序）。**当前倾向：视觉移动**，在运行边界处借助 `Caret.affinity` 区分两侧位置；同时 Shift+方向键的选区扩展按逻辑范围计算。本条确定前，REQ-TEXT-024 对含 RTL 的行按逻辑顺序步进。需在 Windows 上与 Win32 Edit/RichEdit、记事本对照后定稿。
- **TEXT-OPEN-02**　Backspace 与 Delete 的删除单位：整个字素簇，还是仅最后一个码点（组合字符序列的 Backspace 在部分 Windows 应用中只删除最后一个组合符）。本文固定了光标移动的单位（字素簇）；删除单位由 10 的文本编辑规范决定。当前倾向：Delete 删整个簇，Backspace 对"基字 + 组合符"删除最后一个组合符，对 emoji ZWJ 序列删除整个序列。
- **TEXT-OPEN-03**　中文断词：是否在 Windows 后端用系统分词（`Windows.Data.Text.WordsSegmenter`，需 WinRT）替代"汉字逐字"。当前选择逐字，理由：确定性、无 WinRT 依赖、三个后端行为一致。需实机对照记事本/Word 的 Ctrl+方向键与双击选词体验后再议；若引入，须经 ADR，并保证 `fixed` 后端有可测的等价规则。
- **TEXT-OPEN-04**　DirectWrite 的断行（`IDWriteTextLayout` 内部使用的断行表）与 REQ-TEXT-016 基线（尤其中文避头尾字符集、连字符断行）可能不完全一致。需实机逐用例比对；若差异影响布局，可改用 `IDWriteTextAnalyzer::AnalyzeLineBreakpoints` 的结果自行断行，或在文档中承认差异并仅对 `fontstash`、`fixed` 严格要求。
- **TEXT-OPEN-05**　DirectWrite 灰度光栅化的具体取法：以 `IDWriteGlyphRunAnalysis` 的 ClearType 3×1 纹理取三个子像素覆盖率的平均，还是直接使用其灰度/混叠纹理类型；渲染模式（自然/对称/GDI 经典）、网格适配（`DWRITE_GRID_FIT_MODE`）与测量模式的选择；以及是否需要文字对比度/伽马增强（编码空间混合下文字可能偏细或偏粗）。需 M1 在 Windows 实机以 AC-TEXT-022 的观察要点调参，参数固定后写入本条并更新 REQ-TEXT-035。
- **TEXT-OPEN-06**　`mono` 链的第三项"系统默认等宽字体"在 DirectWrite 下没有直接对应；暂定 `Courier New`（所有受支持的 Windows 版本均自带），是否应改为通过 GDI 的 `ANSI_FIXED_FONT` 取得，需实机确认。
- **TEXT-OPEN-07**　是否需要字体特性开关（如数字等宽 `tnum`、禁用连字）。当前答案：不需要；数值对齐使用 `mono` 字族（REQ-THEME-016）。
- **TEXT-OPEN-08**　排版缓存中文本副本带来的内存开销对大量长文本场景（日志查看器）的影响。当前答案：此类控件使用 `layoutOwned` 按行排版并自行管理；是否需要缓存只存哈希而不存文本副本，待 12 的基准场景数据。
- **TEXT-OPEN-09**　字形图集 16 MiB 上限在 4K、200% 缩放、多字号场景下是否足够，以及整页淘汰引发的重光栅化抖动。需 M1/M5 以 12 的基准场景测量 `raster_count` 与淘汰次数后调整默认上限。
- **TEXT-OPEN-10**　`Unicode` 数据版本（`GraphemeBreakTest.txt`、词与断行属性表）的选定与升级节奏；表的生成脚本为非 Zig 文件，不得入库于 `src/`，生成结果以 Zig 源文件入库（REQ-VIS-001：仓库中除 `third_party/` 外不存在非 Zig 源文件）。
