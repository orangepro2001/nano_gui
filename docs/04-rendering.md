# 04 渲染

## 1. 范围

定义 `gfx` 模块：控件可见的绘制接口 `gfx.Canvas`；每个根的持久离屏渲染目标与局部重绘的呈现流程；色彩与混合约定；抗锯齿与物理像素对齐的取整规则；纹理与图像（解码、缓存、多缩放档、占位）；GL 状态约定；NanoVG 补丁登记；以及无头渲染、像素读取与金图比对的测试支持。依据 ADR 0002、ADR 0006。

字形的整形、光栅化与图集管理在 05；本文只规定图集纹理如何提交给 `gfx` 以及字形四边形如何绘制。窗口与 GL 上下文的创建在 03。帧阶段与损伤矩形的计算在 06。令牌与主题绘制基元在 09，它们构建在本文的 `Canvas` 之上。

## 2. 术语

| 术语 | 定义 |
|---|---|
| 画布 (`Canvas`) | 控件与主题绘制代码唯一可见的绘制接口，一次绘制遍内有效。 |
| 表面 (`Surface`) | 一个根的渲染资源：GL 上下文引用、持久离屏帧缓冲、NanoVG 上下文。每个根（含每个弹出根）一个。注意与 00 中"表面（主题背景层级）"同名但不同义，本文一律写 `Surface`。 |
| 渲染目标 | `Surface` 内的持久离屏帧缓冲（颜色纹理 + 模板缓冲）。 |
| 容量尺寸 (`cap`) | 渲染目标实际分配的物理像素尺寸，可大于客户区。 |
| 绘制遍 (pass) | 对一个损伤矩形的一次 `beginFrame`…`endFrame`。 |
| 纹理 (`TextureId`) | `gfx` 管理的共享 GL 纹理的句柄，所有窗口的上下文通用。 |
| 图像 (`ImageId`) | 由解码得到的位图纹理的句柄，带缓存状态（`loading/ready/failed`）。 |
| 后缓冲 | 窗口默认帧缓冲的后台缓冲，由 `SwapBuffers` 呈现。 |
| 内容丢失 | 渲染目标的内容不能再被认为是上一帧的结果（3.2）。 |

## 3. 规范条款

### 3.1 接口边界

**REQ-GFX-001**　控件、主题与 `ui` 的绘制代码**必须**只通过 `gfx.Canvas` 绘制，不得见到或调用 NanoVG、OpenGL 的任何符号（REQ-ARCH-003）。`gfx` 的公开接口**不得**暴露 GL 对象名（纹理名、FBO 名）、NanoVG 图像编号或 NanoVG 上下文指针。绘制函数经 `ctx.draw.canvas`（06 的 `PaintCtx.draw: theme.DrawCtx`，09）取得 `*gfx.Canvas`，该指针即 `Surface.beginFrame` 的返回值，仅在当前绘制遍内有效，**不得**保存到绘制遍之外。`gfx` **不得**导入 `text`（依赖方向见 REQ-ARCH-001）；字形绘制通过已解析好的四边形接口完成（REQ-GFX-027）。

**REQ-GFX-002**　`Canvas` 的能力集是封闭清单，**仅**包含：
1. 纯色与纵向线性渐变的矩形、圆角矩形填充；
2. 对齐物理像素的发丝线（或整数物理像素宽）矩形、圆角矩形、线段描边；
3. 通用路径（`moveTo/lineTo/bezierTo/close`）的填充与描边，仅供图标与标记字形使用；
4. 图像绘制（按目标矩形缩放、可整体着色）；
5. 字形四边形绘制（来自 05 的图集）；
6. 裁剪栈（仅轴对齐矩形，逐层取交集）；
7. 平移栈，以及一个绕点旋转（仅供标记字形动画）。

**不得**提供：阴影、模糊、全局透明度、任意仿射变换、径向/圆锥渐变、图案填充、混合模式切换、九宫格拉伸。新增能力须先修改本条并经评审（REQ-VIS-012）。

**REQ-GFX-003**　`Canvas` 的几何入参**一律**使用逻辑像素（lpx，`f32`），由 `Canvas` 依据所属表面的 `scale` 按 REQ-GFX-013 换算为物理像素后绘制；`Canvas` 不接受物理像素入参，唯一例外是 `drawGlyphQuads` 与 `strokeRect/strokeRoundRect/strokeLine` 的 `width_ppx` 参数（调用方已按 REQ-THEME-012 取得整数宽度）。传给 NanoVG 的像素比（`devicePixelRatio`）**必须**恒为 1.0，所有送入 NanoVG 的坐标均已是物理像素。

### 3.2 渲染目标与局部重绘

**REQ-GFX-004**　每个 `Surface` **必须**拥有一个持久的离屏渲染目标：`GL_RGBA8` 颜色纹理加 8 位模板缓冲（NanoVG 填充需要模板）。局部重绘**必须**把绘制限制在损伤矩形内绘入该渲染目标，使帧间内容的保留不依赖驱动或 DWM 对交换链后缓冲内容的处理方式（交换后后缓冲内容视为未定义）。

**REQ-GFX-005**　一次提交的呈现流程**必须**为：对每个损伤矩形各执行一遍绘制遍（以 GL scissor 限定到该矩形，REQ-GFX-017）绘入渲染目标；全部绘制遍结束后，把渲染目标中客户区范围**整体**拷贝（`glBlitFramebuffer`，不缩放）到窗口默认帧缓冲的后缓冲，再 `SwapBuffers`。**不得**只拷贝损伤矩形，也**不得**依赖上一次交换后的后缓冲残留内容。

**REQ-GFX-006**　渲染目标的容量尺寸 `cap` **必须**遵循下列策略：
1. 容量按 **64 ppx** 向上取整：`up(n) = ceil(n / 64) × 64`。
2. **增长**：客户区尺寸 `(w, h)` 任一维度超过当前 `cap` 时重新分配，新 `cap = (max(cap.w, up(w)), max(cap.h, up(h)))`。
3. **缩小**：客户区任一维度 `≤ cap 对应维度 / 2`（整数除法向下取整）时重新分配，新 `cap = (up(w), up(h))`。
4. 其他情况（含客户区在 `cap` 范围内的增减）**不得**重新分配。
5. 重新分配时旧纹理与模板缓冲在新对象创建成功后释放；创建失败走 `platform.fatal`（内存耗尽，REQ-ARCH-017）。
6. 最小 `cap` 为 64×64；客户区为 0 时不分配、不绘制。

**REQ-GFX-007**　下列情形**必须**视为"帧缓冲内容丢失"（REQ-FRAME-044），`Surface.contentValid()` 返回假，直到一次整根绘制并提交成功：
1. 首帧（渲染目标刚创建）；
2. 渲染目标被重新分配（REQ-GFX-006）；
3. 客户区尺寸发生任何变化（即使在 `cap` 之内，因为客户区外与新增区域的内容无定义）；
4. DPI/scale 变化；
5. 上下文丢失事件（REQ-GFX-037）；
6. 上层显式调用 `Surface.invalidateContent()`。

内容丢失时 `Surface.beginFrame` **必须**拒绝局部损伤（调试构建断言，发布构建自动改为整根损伤），上层（06）负责提升损伤。

**REQ-GFX-008**　客户区在渲染目标中**必须**映射到纹理的左上角：视口为 `(0, cap.h − h, w, h)`（GL 坐标，原点在左下），使 NanoVG 的 y 向下坐标与窗口客户区一致；`glBlitFramebuffer` 的源与目的矩形取同一客户区范围，**不得**发生翻转或缩放。`cap` 大于客户区的部分不被绘制也不被拷出。

### 3.3 色彩与混合

**REQ-GFX-009**　全部混合与插值**必须**在 sRGB 编码空间进行：渲染目标与所有纹理使用 `GL_RGBA8`/`GL_R8`（非 `SRGB8_ALPHA8`），**不得**启用 `GL_FRAMEBUFFER_SRGB`，着色器**不得**做 sRGB↔线性转换。理由：与设计稿工具及系统控件的合成结果一致（半透明叠加、渐变在设计稿中即为编码空间计算）；代价（物理上不正确的叠加）是已知并接受的。

**REQ-GFX-010**　混合**必须**使用预乘 alpha：混合函数 `(ONE, ONE_MINUS_SRC_ALPHA)`。API 层的颜色一律是 sRGB 非预乘（00 第 7 节），由 `Canvas` 在提交给 NanoVG 前转换（NanoVG 的着色器对输入颜色做预乘）；图像像素在上传前**必须**由 `gfx` 在 CPU 上预乘并以 NanoVG 的预乘标志创建，使缩放采样的边缘不出现暗边。渲染目标最终呈现时 alpha 恒为 255（根背景不透明）。

**REQ-GFX-011**　纵向线性渐变**必须**在 sRGB 编码空间对非预乘颜色逐通道线性插值，渐变轴覆盖矩形的物理像素高度（顶行取起点色，底行取终点色，取整后的像素行均匀分段）。两端颜色相同的渐变等同纯色填充，且**不得**产生条带。

### 3.4 抗锯齿与物理像素对齐

**REQ-GFX-012**　抗锯齿**必须**使用 NanoVG 的几何抗锯齿（`NVG_ANTIALIAS`），**不得**使用多重采样（像素格式不请求 MSAA，REQ-PLAT-075）。

**REQ-GFX-013**　lpx → ppx 的换算点与取整规则（对所有基元统一）：
1. **边取整，而非位置加尺寸**：对 lpx 矩形 `(x, y, w, h)`，物理边为 `x0 = floor(x × scale + 0.5)`，`x1 = floor((x + w) × scale + 0.5)`，`y` 同理；物理尺寸 `w_ppx = x1 − x0`。这使共享边的两个相邻矩形在物理像素上严丝合缝（无缝隙、无重叠）。
2. `w > 0` 而 `w_ppx = 0` 时取 `w_ppx = 1`（右/下边向外取 1）；`w = 0` 时保持 0，不绘制。
3. 圆角半径 `round(radius × scale)` 个 ppx，并钳制到 `min(w_ppx, h_ppx) / 2`（REQ-THEME-014）。
4. 裁剪矩形、图像目的矩形、字形四边形目的矩形使用同一规则。
5. 平移栈的偏移量在**入栈时**按本规则的 `floor(v × scale + 0.5)` 取整为整数 ppx 后累加；因此平移不改变任何图元的小数部分对齐。绕点旋转内的坐标不做该取整（旋转中心取整，其余按旋转后的浮点值）。
6. 路径的控制点：`moveTo/lineTo/bezierTo` 的 lpx 坐标乘 `scale` 后**不取整**（图标路径依赖其自身网格设计，REQ-THEME-029、REQ-THEME-033），但整体平移遵循第 5 条。

**REQ-GFX-014**　轴对齐、边落在整数物理像素上的矩形填充，其**直边**像素**必须**为纯色（覆盖率 100% 的像素值恰为填充色，覆盖率 0% 的像素值恰为背景），**不得**出现由抗锯齿产生的中间色（与 AC-THEME-009 一致）。圆角部分的弧线允许抗锯齿。若未经修改的 NanoVG 不能满足本条，**必须**以补丁实现（REQ-GFX-036）；本条由 AC-GFX-006 在每次 NanoVG 升级或补丁变更时回归。

**REQ-GFX-015**　描边的几何规则：`strokeRect/strokeRoundRect(r, ..., color, width_ppx)` 的**外边界**即 REQ-GFX-013 取整后的矩形边界，描边向内侧展开 `width_ppx` 个物理像素（边框不超出节点矩形）；送入 NanoVG 的中心线为该矩形向内缩进 `width_ppx / 2` 的矩形，线宽为 `width_ppx`。由此 `width_ppx` 为奇数时中心线落在像素中心、为偶数时落在像素边界，两种情况下描边的两侧边缘都精确落在整数物理像素坐标上。`strokeLine(a, b, ...)` 对水平或垂直线段同样处理：端点按 REQ-GFX-013 取整，线条以其中心线展开，线宽方向的两侧边缘落在整数物理像素上，线端平头不外延；非水平非垂直的线段不保证对齐。

**REQ-GFX-016**　圆角矩形的内外层同心：描边与内层填充配合使用时，内层圆角半径 = 外层半径 − `width_ppx`（不小于 0，REQ-THEME-014）。`Canvas` 提供 `innerRadius(outer_ppx, width_ppx)` 辅助，使各调用点不各自重复计算。

### 3.5 帧流程与呈现

**REQ-GFX-017**　绘制遍的流程**必须**为：
1. `Surface.beginFrame(damage: RectI, scale: f32) *Canvas`：使该 `Surface` 的 GL 上下文成为当前（`platform.Window.makeCurrent`）；绑定渲染目标；设置视口（REQ-GFX-008）；启用 GL scissor 并设为 `damage`（物理像素，已按渲染目标坐标换算）；调用 `nvgBeginFrame(w, h, 1.0)`；重置裁剪栈与平移栈。
2. 调用方（`ui` 的绘制阶段）对与损伤相交的节点调用绘制函数；`Canvas` 的裁剪栈在 GL scissor 之内继续取交集（`nvgScissor`）。
3. `Surface.endFrame()`：`nvgEndFrame`（冲刷全部绘制命令）；检查裁剪栈与平移栈已平衡（调试构建断言）。

一个根有多个损伤矩形（至多 8 个，REQ-FRAME-041）时，对每个矩形各执行一遍 1–3，最后**一次** `present`。不同损伤矩形的绘制遍之间**不得**共享 NanoVG 的未冲刷状态。

**REQ-GFX-018**　`Surface.present()` **必须**：把渲染目标的客户区范围拷到后缓冲（REQ-GFX-005）；调用 `Window.swapBuffers`；交换间隔为 1（REQ-PLAT-077）。垂直同步的阻塞发生在 `SwapBuffers` 内，该耗时**必须**计入埋点 `time.present`，不得计入构建、布局、绘制耗时。多窗口各自 `present`：对每个有损伤的根依次 `makeCurrent`、`present`；某一窗口的垂直同步阻塞会延迟其后窗口的呈现，这是已知限制（见 7 章 GFX-OPEN-02）。每次 `present` 后 `Surface.contentValid()` 为真。

**REQ-GFX-019**　窗口最小化、`Window.canPresent()` 为假、客户区为 0 时，`Surface.beginFrame` **不得**被调用，`present` **不得**被调用（与 REQ-FRAME-043、REQ-FRAME-049 一致）。调试构建中在此状态调用 `beginFrame`/`present` 断言中止。

**REQ-GFX-020**　所有纹理的像素上传（字形图集、图像）**必须**在一帧的第一个绘制遍的 `beginFrame` 之前批量完成：`Surface.beginFrame` 的第一次调用先执行 `gfx.flushUploads()`。绘制遍期间（`beginFrame` 与 `endFrame` 之间）**不得**发生任何纹理上传、纹理创建或删除。绘制函数中请求尚未上传的资源时，使用占位或上一版本内容，并在下一帧可见（由请求方置 `paint` 脏）。

### 3.6 绘制基元

**REQ-GFX-021**　填充基元的行为：
- `fillRect(r, color)`、`fillRoundRect(r, radius, color)`：纯色，`color.a = 0` 时无输出（不产生 draw call）。
- `fillRectV(r, top, bottom)`、`fillRoundRectV(r, radius, top, bottom)`：REQ-GFX-011 的纵向渐变。
- 圆角的 `radius` 单位为 lpx，换算见 REQ-GFX-013 第 3 条。四个角相同；不提供逐角半径。

**REQ-GFX-022**　描边基元：`strokeRect(r, color, width_ppx)`、`strokeRoundRect(r, radius, color, width_ppx)`、`strokeLine(a, b, color, width_ppx)`。几何见 REQ-GFX-015。`width_ppx` 必须 ≥ 1，调试构建中 0 断言中止。描边只支持纯色。

**REQ-GFX-023**　通用路径：`Canvas.path()` 返回 `PathBuilder`（分配在帧竞技场），提供 `moveTo/lineTo/bezierTo/close`；`fillPath(path, color)`（非零环绕）与 `strokePath(path, color, width_lpx, cap, join)`（`cap` ∈ `butt/round`，`join` ∈ `miter/round/bevel`，斜接限制固定为 4）。单个路径最多 256 个命令，超出调试构建断言、发布构建截断。路径**仅**供图标与标记字形（09 的 `drawMark`）使用，控件不得用它绘制普通的矩形/圆角矩形外观。

**REQ-GFX-024**　裁剪栈：`pushClip(r)` 把当前裁剪区与 `r`（按 REQ-GFX-013 取整）取交集后压栈，`popClip()` 恢复。交集为空时后续所有绘制无输出。深度上限 32，超出调试构建断言。裁剪**仅**支持轴对齐矩形。在 `pushRotate` 作用域内调用 `pushClip` 为编程错误（调试构建断言）。裁剪不影响 GL scissor（REQ-GFX-017）：二者共同作用，结果为交集。

**REQ-GFX-025**　变换：`pushTranslate(dx, dy)`（lpx，取整规则见 REQ-GFX-013 第 5 条）与 `popTransform()`；`pushRotate(center: Vec2, radians: f32)`，旋转中心取整为整数物理像素，作用至对应的 `popTransform()`。`pushRotate` 仅供标记字形动画（如折叠箭头）。在旋转作用域内允许 `fillPath/strokePath`、`drawImage`，不允许 `pushClip`（REQ-GFX-024）与 `drawGlyphQuads`。变换栈深度上限 16。

**REQ-GFX-026**　图像绘制：`drawImage(id: ImageId, dst: Rect, opts: ImageDrawOpts)`，`opts` 含 `tint: ?Color`（逐通道与图像像素相乘，缺省不着色）、`src: ?Rect`（源子矩形，像素，缺省整图）、`filter`（`linear` 默认 / `nearest`）。`dst` 按 REQ-GFX-013 取整；目的矩形尺寸与源像素尺寸相同时必须是 1:1 的逐像素拷贝（不产生模糊）。纹理环绕模式固定为边缘钳位。`id` 状态不是 `ready` 时不绘制任何内容并返回 `false`，调用方决定占位表现（REQ-GFX-033）。

**REQ-GFX-027**　字形四边形绘制：`drawGlyphQuads(tex: TextureId, kind: GlyphKind, quads: []const GlyphQuad, color: Color)`，`GlyphKind` ∈ `alpha`（A8 图集，覆盖率乘 `color`）、`rgba`（彩色字形，预乘 RGBA，`color` 仅取其 alpha 作整体不透明度）。`GlyphQuad` 含目的矩形（**整数物理像素**，调用方已完成子像素定位）与 `tex` 内的源矩形（像素）。`Canvas` **不得**对四边形再做取整、平移栈以外的变换或过滤（使用 `nearest`，1:1 采样）。同一次调用的全部四边形**应当**合并为不超过 1 个 draw call。平移栈对四边形有效（整数 ppx 偏移）。

### 3.7 纹理与图像

**REQ-GFX-028**　全部纹理（字形图集页、图像）**必须**创建于共享对象组中（REQ-PLAT-076），以 `TextureId`（带世代号的句柄）引用，由 `gfx` 内部的注册表持有 GL 纹理名。每个 `Surface` 的 NanoVG 上下文**必须**对注册表中的纹理**惰性包装**为本上下文的 NanoVG 图像（`nvglCreateImageFromHandle` 或等价），首次在该上下文绘制时创建并缓存。纹理销毁时，各上下文的包装**必须**延迟到该上下文下次成为当前上下文时释放（延迟删除队列），GL 纹理名在所有包装释放后删除。渲染目标、顶点数组、NanoVG 自身的缓冲**不**共享，每个上下文自建。

**REQ-GFX-029**　纹理接口：`createTexture(w, h, fmt: TextureFormat, usage: TextureUsage) !TextureId`，`fmt` ∈ `a8`、`rgba8`；`usage` ∈ `dynamic`（带由 `gfx` 持有的 CPU 影子缓冲，供字形图集逐块更新）、`static`（创建时一次性上传，无影子）。`dynamic` 纹理通过 `textureShadow(id) []u8` 取得影子缓冲（行主序、顶行在前、无填充行距），写入后调用 `markDirty(id, rect)`。`flushUploads()` 对每张脏纹理**至多发起一次** `glTexSubImage2D`，范围为本帧全部脏矩形的并集包围矩形，数据取自影子缓冲。`destroyTexture(id)` 后该 `id` 失效，任何使用均返回错误（世代校验）。纹理总字节数计入埋点 `gfx.texture_bytes`（REQ-ARCH-014）。

**REQ-GFX-030**　图像解码使用 stb_image，编译期仅启用 PNG、JPEG、BMP 三种格式（`STBI_ONLY_PNG/JPEG/BMP`），其他格式（GIF、TGA、PSD、HDR 等）返回 `error.UnsupportedFormat`。`gfx.decode(allocator, bytes) DecodeError!Pixels` **必须**是无全局状态、可重入的纯函数，可在任意线程调用（线程安全清单需在 02 增补，见 7 章 GFX-OPEN-05），输出 RGBA8 非预乘像素。解码前**必须**先读取头部尺寸并拒绝任一维度 > 16 384 或总像素 > 64 MPx 的图像（`error.TooLarge`），不得先分配再检查。损坏数据返回 `error.DecodeFailed`。`DecodeError` 为显式错误集。

**REQ-GFX-031**　图像加载**必须**遵守"解码不得阻塞构建"（REQ-FRAME-026）：
1. **同步路径** `images.loadSync(key, bytes)` 仅允许用于解码后像素数 ≤ 65 536（256×256）的图像（内建图标、小资源）；更大者返回 `error.TooLargeForSync`。
2. **异步路径**：`images.request(key: ImageKey) ImageState`。缓存命中且 `ready` 时直接可用；未命中时登记请求并**同步**调用应用提供的 `ImageLoader` 回调（`fn (key: ImageKey) void`，仅用于启动加载，**不得**在其中解码）；应用在工作线程读取与解码（可调用 `gfx.decode`）后，经 `app.post` 回投调用 `images.insert(key, pixels)`（界面线程）完成上传并对使用该图像的节点置 `paint` 脏。框架不创建线程（REQ-ARCH-007）。
3. 每个 `ImageKey` 在未完成前至多触发一次 `ImageLoader` 调用。
4. 若应用未设置 `ImageLoader`，异步路径下未命中即视为 `failed`。

`ImageKey` 为 `{ hash: u64 }`，由路径字节串或内容哈希计算（`ImageKey.fromPath`、`ImageKey.fromBytes`）。

**REQ-GFX-032**　图像缓存**必须**有显式容量上限（默认 64 MiB 的纹理字节数，可配置）与 LRU 淘汰（REQ-ARCH-014）：每次 `request` 命中或 `drawImage` 成功更新该条目的访问序号；插入使占用超限时，淘汰访问序号最小者，直到占用 ≤ 上限。**当前帧内被绘制过**的图像不得被淘汰（即使超限，也等到下一帧）。被淘汰条目的状态回到"未命中"，再次请求时重新走 REQ-GFX-031。由 `insert` 的像素创建、且应用声明为 `pinned` 的图像不参与淘汰，由应用调用 `images.release(key)` 释放。当前占用与条目数计入埋点。

**REQ-GFX-033**　图像的状态与占位：`images.state(key) ImageState`，取值 `loading`、`ready`、`failed`（含解码失败、文件不存在、无 `ImageLoader`、超限）。`gfx` 本身**不**绘制占位；使用图像的控件根据状态绘制占位框（REQ-ARCH-018）：`loading` 与 `failed` 的外观由控件规范规定且必须可区分。进入 `failed` 时**必须**记录恰好一条 `warn` 日志（含 key 的可读描述与原因），并建立"失败缓存"：同一 key 不再触发 `ImageLoader`，直到 `images.forgetFailure(key)` 或 `images.clear()`。

**REQ-GFX-034**　多缩放档选取（REQ-THEME-034）：`ImageSet` 含若干 `ImageVariant { key: ImageKey, scale_pct: u16 }`（如 100、150、200）或单个带 `source_scale_pct` 的源图（≥ 200 时视为"大源图"）。选取规则：
1. 窗口 scale 换算为百分数 `s = round(scale × 100)`。
2. 多档：取 `scale_pct ≥ s` 的最小档；不存在则取最大档（放大使用）。
3. 单源：直接使用，按 `s / source_scale_pct` 缩放。
4. 当所选图像相对目标物理尺寸的缩小比（源像素宽 ÷ 目的 ppx 宽）≥ 1.5 时，上传该纹理时**必须**生成 mipmap 并以 `GL_LINEAR_MIPMAP_LINEAR` 采样；否则用线性采样且无 mipmap。同一纹理在不同缩小比下需要不同模式时，以首次选取的结果为准（不重复上传），缓存键含"是否 mip"。
5. 目的尺寸由调用方以 lpx 给出（图像逻辑尺寸 = 源像素 ÷ (`scale_pct` / 100)），不由像素尺寸决定。

### 3.8 GL 状态、补丁与恢复

**REQ-GFX-035**　GL 状态约定：
1. `gfx` 之外的代码**不得**调用任何 GL 函数（REQ-ARCH-003）。
2. 进入每个绘制遍时，`gfx` 假定并确保"基线状态"：无深度测试；背面剔除关；混合开启，函数 `(ONE, ONE_MINUS_SRC_ALPHA)`；scissor 开启；模板测试关；`GL_UNPACK_ALIGNMENT = 1`；活动纹理单元 0。NanoVG 的 GL3 后端在其自己的冲刷中设置并恢复其所需状态；`gfx` 在每次 `endFrame` 后、以及自己的 GL 操作（blit、上传、FBO 创建）之前，**必须**重新建立基线状态，并还原其修改过的绑定（纹理 2D、读/写帧缓冲、VAO、程序）。
3. 调试构建在每个绘制遍结束与每次 `present` 后检查 `glGetError()`，非零则断言中止并打印遍序号与最近一次 `gfx` 操作名；发布构建不检查。
4. 状态管理集中在 `gfx` 的单一文件（`gfx/gl_state.zig`），其他文件不得直接修改 GL 状态。

**REQ-GFX-036**　NanoVG 以源码 vendoring 在 `third_party/nanovg/`，对其的每一处改动**必须**在 `third_party/nanovg/PATCHES.md` 登记（ADR 0002）。每条登记含：编号、改动目的、被修改的函数/文件、对应的规范条款（如 REQ-GFX-014）、对应的验收条款、上游基线版本（提交哈希）、是否可向上游提交。未登记的改动视为缺陷。预期补丁位（是否需要由实测决定，见 GFX-OPEN-01）：直边对齐无抗锯齿过渡（REQ-GFX-014）、外部 GL 纹理包装（REQ-GFX-028）、字形四边形的批量绘制（REQ-GFX-027）、单通道（A8）纹理采样与预乘的处理。

**REQ-GFX-037**　上下文丢失（`platform` 产出 `render_lost`，REQ-PLAT-079）时，`gfx` **必须**：重建所有 `Surface` 的渲染目标；使全部纹理的 GPU 侧失效，`dynamic` 纹理由影子缓冲重新上传，`static` 纹理（图像）从缓存中移除并以 `ImageLoader` 重新请求（`pinned` 图像通过 `ImageLoader` 的 `reset` 回调要求应用重新提交）；重建 NanoVG 上下文；将各 `Surface` 标记为内容丢失（REQ-GFX-007）。重建失败走 `platform.fatal`。

### 3.9 测试支持与调试

**REQ-GFX-038**　`Surface.readPixels(rect: RectI, source: ReadSource, out: []u8) !void`：读取渲染目标（`source = .target`）或最近一次呈现后的后缓冲（`source = .presented`，含 show-damage 叠加）中的像素，输出 RGBA8、**顶行在前**、紧密排列（行距 = `w × 4`）、sRGB 编码值、alpha 恒 255；`rect` 为客户区物理像素，超出客户区返回 `error.OutOfBounds`；`out` 长度不足返回 `error.BufferTooSmall`。仅限测试与调试用途，发布构建的正常运行路径不得调用（可编译期关闭）。

**REQ-GFX-039**　无头渲染：在 Linux 上以 Mesa llvmpipe 提供软件 OpenGL（环境约定：`LIBGL_ALWAYS_SOFTWARE=1`、请求的 GL 3.3 Core），通过 `platform.initHeadless` 创建隐藏窗口，走与真实运行完全相同的 `Surface` 路径。金图测试的 Mesa 版本在 CI 配置中固定；版本升级必须整体重生成基准并经评审。同一进程内同一场景重复渲染 100 次的结果**必须**逐字节相同。

**REQ-GFX-040**　金图比对规则：
1. 基准图的目录布局由 13 的 REQ-TEST-008 定义（`tests/golden/<后端>/<主题>/<缩放>/<用例>.png`），`<后端>` ∈ `glfw`、`win32`。
2. **非文字区域**：逐像素逐通道**必须**相等（容差 0）。
3. **文字区域**：由测试框架在测试构建中自动登记——`drawGlyphQuads` 在测试构建下把每次调用的四边形外接矩形（外扩 1 ppx）加入 `gfx.testing.textRegions()`。`glfw` 后端基准在固定 Mesa 与固定测试字体下**同样要求逐像素相等**；`win32` 后端基准（DirectWrite 的光栅结果随系统版本与显卡驱动有细微差异）允许：单通道差 ≤ 12，且超差像素数 ≤ 文字区域总像素的 1%。
4. 文字基准按后端分别存放，不得共用。`win32` 基准只能在真实 Windows 上生成与比对（`[人工]` 触发的 `zig build test-golden` 的 Windows 变体）。
5. 失败时输出差异图（红色标出超差像素）与统计，不覆盖基准；更新基准须显式命令。

**REQ-GFX-041**　`-Dshow-damage=true` 的呈现方式（REQ-FRAME-057）：在 `present` 内、渲染目标拷到后缓冲**之后**、`SwapBuffers` **之前**，直接向后缓冲绘制本次呈现的每个损伤矩形——填充 `#FF00FF40`，外加 1 ppx 边框 `#FF00FFC0`。该叠加**不得**写入渲染目标，因此下一次呈现（整体拷贝）自然将其清除，且不影响损伤计算。这些颜色是仅调试可见的字面量，豁免 09 的"不出现颜色字面量"约束。关闭该选项时无任何额外开销与代码路径。

**REQ-GFX-042**　`gfx` **必须**通过 `core.stats` 暴露下列埋点（名称冻结；本条只登记 `gfx` 模块专有的 `gfx.*` 项。`gfx` 另负责更新 12 的 REQ-PERF-034 所登记的跨模块项 `frame.presents`、`time.present`、`frame.gl_draw_calls`、`cache.image.bytes`，其名字与定义以 12 为准）：`gfx.pass_count`（绘制遍）、`gfx.fbo_realloc`、`gfx.texture_bytes`、`gfx.upload_calls`、`gfx.upload_bytes`、`gfx.image_cache_entries`、`gfx.image_evictions`、`gfx.image_load_requests`、`gfx.image_failures`。

## 4. 接口草案

```zig
// 草案：仅签名
pub const TextureId = enum(u32) { none = 0, _ };    // 低位索引、高位世代
pub const ImageId = enum(u32) { none = 0, _ };
pub const TextureFormat = enum { a8, rgba8 };
pub const TextureUsage = enum { dynamic, static };
pub const GlyphKind = enum { alpha, rgba };
pub const LineCap = enum { butt, round };
pub const LineJoin = enum { miter, round, bevel };
pub const ImageFilter = enum { linear, nearest };
pub const ImageState = enum { loading, ready, failed };
pub const ReadSource = enum { target, presented };

pub const GlyphQuad = struct {
    dst: core.RectI,       // 整数物理像素，已含子像素定位的取整
    src: core.RectI,       // 纹理内像素矩形
};

pub const ImageDrawOpts = struct {
    tint: ?core.Color = null,
    src: ?core.Rect = null,          // 源像素子矩形
    filter: ImageFilter = .linear,
};

pub const ImageKey = struct {
    hash: u64,
    pub fn fromPath(path: []const u8) ImageKey;
    pub fn fromBytes(bytes: []const u8) ImageKey;
};

pub const ImageVariant = struct { key: ImageKey, scale_pct: u16 };
pub const ImageSet = union(enum) {
    variants: []const ImageVariant,
    single: struct { key: ImageKey, source_scale_pct: u16 },
};

pub const Pixels = struct {
    width: u32, height: u32,
    rgba: []u8,                      // 非预乘 RGBA8，所有权属于分配器调用方
    pub fn deinit(self: *Pixels, allocator: std.mem.Allocator) void;
};

pub const DecodeError = error{ UnsupportedFormat, TooLarge, DecodeFailed, OutOfMemory };
pub const GfxError = error{ OutOfBounds, BufferTooSmall, TooLargeForSync, InvalidHandle, OutOfMemory };

/// 线程安全：无全局状态的纯函数。
pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) DecodeError!Pixels;

pub const PathBuilder = struct {
    pub fn moveTo(self: *PathBuilder, p: core.Vec2) void;
    pub fn lineTo(self: *PathBuilder, p: core.Vec2) void;
    pub fn bezierTo(self: *PathBuilder, c1: core.Vec2, c2: core.Vec2, p: core.Vec2) void;
    pub fn close(self: *PathBuilder) void;
};

pub const Canvas = struct {
    scale: f32,

    // —— 填充 ——
    pub fn fillRect(self: *Canvas, r: core.Rect, color: core.Color) void;
    pub fn fillRoundRect(self: *Canvas, r: core.Rect, radius: f32, color: core.Color) void;
    pub fn fillRectV(self: *Canvas, r: core.Rect, top: core.Color, bottom: core.Color) void;
    pub fn fillRoundRectV(self: *Canvas, r: core.Rect, radius: f32, top: core.Color, bottom: core.Color) void;

    // —— 描边（发丝线或整数物理像素宽）——
    pub fn strokeRect(self: *Canvas, r: core.Rect, color: core.Color, width_ppx: i32) void;
    pub fn strokeRoundRect(self: *Canvas, r: core.Rect, radius: f32, color: core.Color, width_ppx: i32) void;
    pub fn strokeLine(self: *Canvas, a: core.Vec2, b: core.Vec2, color: core.Color, width_ppx: i32) void;
    pub fn innerRadius(self: *const Canvas, outer_ppx: i32, width_ppx: i32) i32;

    // —— 路径（仅图标/标记）——
    pub fn path(self: *Canvas) PathBuilder;
    pub fn fillPath(self: *Canvas, p: *const PathBuilder, color: core.Color) void;
    pub fn strokePath(self: *Canvas, p: *const PathBuilder, color: core.Color, width_lpx: f32, cap: LineCap, join: LineJoin) void;

    // —— 裁剪与变换 ——
    pub fn pushClip(self: *Canvas, r: core.Rect) void;
    pub fn popClip(self: *Canvas) void;
    pub fn pushTranslate(self: *Canvas, dx: f32, dy: f32) void;
    pub fn pushRotate(self: *Canvas, center: core.Vec2, radians: f32) void;
    pub fn popTransform(self: *Canvas) void;

    // —— 图像与字形 ——
    pub fn drawImage(self: *Canvas, id: ImageId, dst: core.Rect, opts: ImageDrawOpts) bool;
    pub fn drawGlyphQuads(self: *Canvas, tex: TextureId, kind: GlyphKind, quads: []const GlyphQuad, color: core.Color) void;
};

pub const Surface = struct {
    pub fn init(allocator: std.mem.Allocator, window: *platform.Window) GfxError!Surface;
    pub fn deinit(self: *Surface) void;
    pub fn resize(self: *Surface, client: platform.Size2i) void;   // 客户区 ppx；按 REQ-GFX-006 决定是否重分配
    pub fn contentValid(self: *const Surface) bool;
    pub fn invalidateContent(self: *Surface) void;
    pub fn beginFrame(self: *Surface, damage: core.RectI, scale: f32) *Canvas;
    pub fn endFrame(self: *Surface) void;
    pub fn present(self: *Surface) void;
    pub fn readPixels(self: *Surface, rect: core.RectI, source: ReadSource, out: []u8) GfxError!void;
};

pub fn createTexture(w: u32, h: u32, fmt: TextureFormat, usage: TextureUsage) GfxError!TextureId;
pub fn destroyTexture(id: TextureId) void;
pub fn textureShadow(id: TextureId) GfxError![]u8;
pub fn markDirty(id: TextureId, rect: core.RectI) void;
pub fn flushUploads() void;

pub const ImageLoader = struct {
    ctx: *anyopaque,
    request: *const fn (ctx: *anyopaque, key: ImageKey) void,   // 仅启动加载，不得解码
    reset: *const fn (ctx: *anyopaque) void,                    // 上下文丢失后通知
};

pub const images = struct {
    pub fn setLoader(loader: ?ImageLoader) void;
    pub fn request(key: ImageKey) ImageState;
    pub fn state(key: ImageKey) ImageState;
    pub fn id(key: ImageKey) ?ImageId;                          // 仅 ready 时有值
    pub fn loadSync(key: ImageKey, bytes: []const u8) GfxError!ImageId;
    pub fn insert(key: ImageKey, pixels: Pixels, opts: struct { pinned: bool = false, mip: bool = false }) GfxError!ImageId;
    pub fn pick(set: ImageSet, scale: f32) ImageKey;            // REQ-GFX-034
    pub fn size(id: ImageId) ?core.Size;                        // 源像素尺寸；尚未就绪或加载失败时为 null
    pub fn release(key: ImageKey) void;
    pub fn forgetFailure(key: ImageKey) void;
    pub fn clear() void;
    pub fn setCapacity(bytes: usize) void;
};

pub const testing = struct {
    pub fn textRegions(surface: *const Surface) []const core.RectI;
};
```

## 5. 边界与错误情况

| 情况 | 规定 |
|---|---|
| 损伤矩形部分超出客户区 | `beginFrame` 前钳制到客户区；钳制后为空则不执行绘制遍。 |
| 客户区尺寸 0×0 | 不分配、不绘制、不呈现（REQ-GFX-006、REQ-GFX-019）。 |
| `cap` 内的客户区缩小 | 不重分配，但按 REQ-GFX-007 第 3 条视为内容丢失，下一帧整根重绘。 |
| 同一帧内对同一纹理多次 `markDirty` | 合并为并集包围矩形，一次上传（REQ-GFX-029）。 |
| `drawImage` 的 `src` 超出图像范围 | 钳制到图像范围；钳制后为空则无输出。调试构建断言。 |
| 以已销毁的 `TextureId`/`ImageId` 绘制 | 世代校验失败：无输出，调试构建断言，发布构建记录一次 `err` 日志。 |
| 图像文件在缓存期间被外部修改 | 不检测；应用通过更换 `ImageKey`（路径加版本号）或 `release` 后重新请求来刷新。 |
| 图像尺寸 0 或解码得到 0 像素 | `error.DecodeFailed`，状态 `failed`。 |
| 同时存在多个 `Surface`，其中一个上下文丢失 | 按整体处理：全部 `Surface` 重建（共享对象组一并失效）。 |
| 路径命令超过 256 | 调试构建断言；发布构建截断并记录一次 `warn`。 |
| 裁剪或变换栈不平衡 | `endFrame` 时调试构建断言，发布构建自动恢复并记录一次 `err`。 |
| 旋转中心 / 平移量为 `NaN` 或无穷 | 调试构建断言；发布构建忽略该次入栈调用。 |
| 驱动对 `glBlitFramebuffer` 不支持（极旧 GL） | 不会发生：上下文请求 3.3 Core 已保证支持；创建失败走 `platform.fatal`（REQ-PLAT-078）。 |
| 高 DPI 下渲染目标过大 | 8K 屏（7680×4320）渲染目标约 127 MiB（RGBA8 + 模板），属已知上限；超出显存时 `fatal` 并给出可读原因。 |

## 6. 验收标准

除标 `[人工]` 者外，以下测试在 GLFW 无头模式（Mesa llvmpipe）下运行。

**AC-GFX-001**　`[单元]` 覆盖：REQ-GFX-001、REQ-GFX-002、REQ-GFX-003。(1) 运行导入检查脚本：`widgets`、`theme`、`ui` 源码中不出现 `nvg`、`gl`、`GL_` 前缀符号或对 `gfx` 内部文件的导入；`gfx` 不导入 `text`；`gfx` 公开接口中不出现 `c_uint` 形式的 GL 对象名类型。(2) 反射 `gfx.Canvas` 的公开声明集合。预期：恰为 REQ-GFX-002 清单对应的函数集合（第 4 节所列），不含名为 `shadow`、`blur`、`alpha`、`opacity`、`transform`、`matrix`、`radial`、`blend` 的成员。(3) 在 `scale = 1.5` 下以 `fillRect((0,0,10,10))` 绘制，断言实际送入后端的像素尺寸为 15×15，且 `nvgBeginFrame` 的像素比参数为 1.0（后端记录钩子）。

**AC-GFX-002**　`[金图]` 覆盖：REQ-GFX-004、REQ-GFX-005、REQ-GFX-008。场景：800×600 窗口，整根绘制一幅含渐变、文字、图标的页面并 `present`；随后在测试钩子中把后缓冲整体填成 `#FF00FF`（模拟交换后后缓冲内容丢失），仅对矩形 `(100,100,40,20)` 修改一个色块并局部重绘、`present`。预期：`readPixels(.presented)` 的全窗口结果与"同状态整根重绘"的结果逐像素一致；`.presented` 中无任何 `#FF00FF` 像素；渲染目标客户区的左上角像素与页面左上角像素一致（无垂直翻转：页面顶部标记色块出现在读回数据的第 0 行）；`cap` 大于客户区的情形下（见 AC-GFX-003）读回数据不含 `cap` 区域的内容。

**AC-GFX-003**　`[单元]` 覆盖：REQ-GFX-006。依次调用 `resize`，记录 `cap` 与 `gfx.fbo_realloc` 增量：
| 序 | 客户区 | 预期 `cap` | 是否重分配 |
|---|---|---|---|
| 1 | 800×600 | 832×640 | 是（首次） |
| 2 | 810×610 | 832×640 | 否 |
| 3 | 832×640 | 832×640 | 否 |
| 4 | 833×640 | 896×640 | 是（宽度超出，增长取各维最大值） |
| 5 | 900×700 | 960×704 | 是 |
| 6 | 500×400 | 960×704 | 否（500 > 480 且 400 > 352） |
| 7 | 480×400 | 512×448 | 是（480 ≤ 960/2；缩小后 `up` 重新计算） |
| 8 | 0×0 | 不分配 | 否，且不触发绘制 |

预期：`gfx.fbo_realloc` 总增量恰为 4；每次重分配后 `contentValid()` 为假。

**AC-GFX-004**　`[单元]` 覆盖：REQ-GFX-007。对一个已有效的 `Surface` 依次触发：首帧、`resize` 到不同客户区（`cap` 内）、scale 变化、模拟 `render_lost`、`invalidateContent()`，每次之后立即检查 `contentValid()`，再做一遍整根绘制并 `present` 后再检查；另在 `contentValid()` 为假时以局部损伤调用 `beginFrame`。预期：每种触发后为假，成功 `present` 后为真；调试构建中局部损伤调用断言中止，发布构建中实际绘制范围为整根（以读回像素验证整窗已绘制）。

**AC-GFX-005**　`[金图]` 覆盖：REQ-GFX-009、REQ-GFX-010、REQ-GFX-011。场景（背景纯黑 `#000000` 窗口，100% 缩放）：(a) 80×80 的 `#FFFFFF80` 填充；(b) 80×80 的 `#FF000080` 叠加在 `#0000FF` 底之上；(c) 宽 32、高 256 的 `fillRectV(#000000, #FFFFFF)`；(d) 同一渐变两端同色；(e) 用 `readPixels` 对 (a) 取中心像素。预期：(a) 中心像素每通道 ∈ {127, 128}（编码空间混合；线性空间混合会得到约 188）；(b) 中心像素 R ∈ {127,128}、G = 0、B ∈ {127,128}；(c) 第 `i` 行（0 ≤ i < 256）灰度值与 `i` 之差 ≤ 1 且单调不减；(d) 全部像素等于该色（无条带）；GL 状态查询确认 `GL_FRAMEBUFFER_SRGB` 为关、渲染目标内部格式为 `GL_RGBA8`。

**AC-GFX-006**　`[金图]` 覆盖：REQ-GFX-012、REQ-GFX-013、REQ-GFX-014。在 scale = 1.0/1.25/1.5/1.75/2.0/3.0 下，白底上绘制：矩形 A `(10.3, 7.7, 33.4, 20.2)` lpx 纯色 `#336699`；与 A 共享右边（x = 43.7）的矩形 B `(43.7, 7.7, 20, 20.2)` 纯色 `#CC3300`；`w = 0.2` 的细矩形 C。预期（逐 scale 按公式计算期望边 `x0 = floor(x·s + 0.5)` 等）：A、B 的四条直边上的每个像素的值**恰为**填充色或恰为背景白色，无中间值；A 与 B 之间无背景色缝隙像素、无重叠覆盖（A 的最右列与 B 的最左列相邻）；C 的物理宽度 ≥ 1 ppx；A 的物理尺寸等于公式值（例如 scale = 1.25 时 A 宽 `55 − 13 = 42` ppx）；所有 6 个 scale 的结果与基准一致。该测试同时是 NanoVG 升级与补丁变更的回归测试。

**AC-GFX-007**　`[单元]` 覆盖：REQ-GFX-013。对取整函数做表驱动测试（纯函数，无 GL）：
| x, w (lpx) | scale | 预期 `x0`, `w_ppx` |
|---|---|---|
| 10.3, 33.4 | 1.0 | 10, 34 |
| 10.3, 33.4 | 1.25 | 13, 42 |
| 10.3, 33.4 | 1.5 | 15, 51 |
| 10.0, 0.2 | 1.0 | 10, 1（钳到最小 1） |
| 10.0, 0.0 | 1.0 | 10, 0（不绘制） |
| 0.4, 10 | 1.0 | 0, 10 |
| 0.5, 10 | 1.0 | 1, 10 |

另验证圆角半径钳制：`radius = 20 lpx` 于 `10×10 lpx` 矩形，scale 1.0 → 5 ppx。平移：`pushTranslate(0.4, 0.4)` 在 scale = 1.0 时偏移为 0，`pushTranslate(0.6, 0.6)` 为 1。

**AC-GFX-008**　`[金图]` 覆盖：REQ-GFX-015、REQ-GFX-016、REQ-GFX-022。在 scale = 1.0/1.5/2.0/3.0 下，以 `width_ppx` = 1/1/2/3（即发丝线宽度，REQ-THEME-012）绘制矩形 `(10.3, 7.7, 60, 30)` 的 `strokeRect` 与半径 3 lpx 的 `strokeRoundRect`；并在描边内用 `innerRadius` 绘制同心内层填充。预期：描边外边界等于取整后的矩形边界（外侧第一个像素是背景，内侧第一个像素是描边色）；直边上宽度恰为 `width_ppx` 个像素、均为纯描边色；矩形角与圆角中心对称（四象限镜像后逐像素一致）；`strokeLine` 水平线 `(5,20)→(50,20)` 的线条占满恰 `width_ppx` 行且两端无外延；内层圆角半径 = 外层 − `width_ppx`（读回像素检查弧线起点距离）；`width_ppx = 0` 在调试构建中断言中止。

**AC-GFX-009**　`[单元]` 覆盖：REQ-GFX-017。对 3 个互不相交的损伤矩形各执行一遍绘制遍，之后一次 `present`。预期：`gfx.pass_count` 增量 3，`frame.presents` 增量 1；GL 调用跟踪显示每遍的 scissor 等于对应矩形；矩形外像素与调用前的渲染目标逐像素相等；`endFrame` 前未平衡的裁剪栈（故意少一次 `popClip`）在调试构建中断言，在发布构建中记录 1 条 `err` 日志并恢复；`scissor` 之外的绘制命令（故意画一个覆盖整个窗口的矩形）不改变矩形外的像素。

**AC-GFX-010**　`[单元]` 覆盖：REQ-GFX-018、REQ-GFX-019。(1) 无头假垂直同步下连续 `present` 3 次，`swapBuffers` 调用 3 次，`presentCount` 与之相等；`time.present` 的计时记入 `present` 区间而不记入绘制遍。(2) `setVisible(false)` 后对一个叶节点置脏，预期 `beginFrame` 与 `present` 调用数均为 0；调试构建中在此状态强行调用 `present` 断言中止。(3) 创建两个窗口各一个 `Surface`，依次呈现，预期每次 `present` 前 `makeCurrent` 指向对应窗口。`[计量]` 补充（Windows 实机）：60 Hz 显示器上运行持续动画 120 帧，记录相邻两次 `present` 返回的时间间隔。预期：平均 16.67 ms ± 0.5 ms，最大值 ≤ 33.4 ms。

**AC-GFX-011**　`[单元]` 覆盖：REQ-GFX-020、REQ-GFX-029。在构建/绘制阶段之前创建一张 1024×1024 `a8` `dynamic` 纹理，向其影子缓冲写入并对其中 10 个互不相交的矩形 `markDirty`，再创建并写入一张 `rgba8` 纹理一个矩形。GL 调用跟踪。预期：`flushUploads` 后 `glTexSubImage2D` 恰调用 2 次（每张纹理一次），第一张的范围等于 10 个矩形的并集包围矩形；所有上传调用均先于第一个绘制遍的 `nvgBeginFrame`；绘制遍内调用 `createTexture` 在调试构建中断言；对已销毁的 `TextureId` 调用 `markDirty` 返回错误；`gfx.upload_calls` 与调用跟踪一致；创建纹理后 `gfx.texture_bytes` 增加 `1024×1024 + w×h×4`。

**AC-GFX-012**　`[金图]` 覆盖：REQ-GFX-021、REQ-GFX-023、REQ-GFX-024。绘制：不同半径的圆角矩形纯色与渐变、一个由 `moveTo/lineTo/bezierTo/close` 构成的 16×16 图标（填充与 3 种 `cap/join` 的描边）、`pushClip((0,0,50,50))` 内再 `pushClip((25,25,50,50))` 后用大矩形填充、`popClip` 两次后再次填充。预期：嵌套裁剪时只有 `(25,25)–(50,50)` 的方块被着色，像素边界精确；`popClip` 后恢复为外层裁剪；空交集的裁剪内无输出；路径填充使用非零环绕（一个自交的五角星中心被填充）；`color.a = 0` 的填充使 `frame.gl_draw_calls` 增量为 0；裁剪栈第 33 层在调试构建中断言。与基准图一致。

**AC-GFX-013**　`[金图]` 覆盖：REQ-GFX-025。用 `drawMark` 的 `chevron_right` 路径，中心位于整数物理像素，绘制：无变换；`pushRotate(center, π/2)`；`pushTranslate(20, 0)` 后无旋转。预期：旋转 90° 的结果与手工交换坐标得到的 `chevron_down` 参照路径的绘制结果逐通道差 ≤ 1；平移后的图形与无平移图形在整体平移 `20 × scale` 个整数像素后逐像素相等；在 `pushRotate` 内调用 `pushClip` 与 `drawGlyphQuads` 在调试构建中断言；变换栈第 17 层断言。

**AC-GFX-014**　`[金图]` 覆盖：REQ-GFX-026、REQ-GFX-010。用 `insert` 提供一张 16×16 的 RGBA 棋盘（含半透明像素）与一张 8×8 纯白图。预期：1:1 绘制时读回的 16×16 区域与源像素预乘后叠加到背景的结果逐通道差 ≤ 1（无模糊）；整数倍放大使用 `nearest` 时每个源像素对应整齐的方块；以 `tint = #FF0000` 绘制纯白图得到 `#FF0000`；`src` 子矩形只绘制所指的部分；半透明边缘在 2× 缩放后无暗色边（预乘效果，与参照"先缩放再叠加"的结果差 ≤ 2）；状态非 `ready` 的 `ImageId` 返回 `false` 且无输出。

**AC-GFX-015**　`[金图]` 覆盖：REQ-GFX-027。创建 8×8 的 `a8` 动态纹理，其中左半 255、右半 128；白底上以 `color = #000000` 绘制 2 个四边形（整数位置 (10,10) 与 (30,10)），再以 `#FF0000` 绘制一个。预期：覆盖率 255 的像素为纯 `color`，覆盖率 128 的像素每通道 = 白色 × (1 − 128/255) 的取整值 ±1（编码空间混合）；四边形与目的矩形逐像素对齐（无模糊，无半像素偏移）；3 次调用 + 同一调用内含 100 个四边形的情形下 draw call 数 ≤ 调用次数；`kind = .rgba` 的四边形颜色取自纹理，`color.a = 128` 时整体不透明度约 50%。

**AC-GFX-016**　`[单元]` 覆盖：REQ-GFX-028。创建两个窗口 A、B（共享对象组），在 A 的上下文创建图像并在 A、B 中分别绘制，再销毁该图像。预期：B 中绘制结果与 A 中一致；销毁后立即检查 GL 纹理名仍存在（`glIsTexture` 为真，包装尚在延迟队列）；A、B 各再呈现一帧后 `glIsTexture` 为假；调用 `destroyTexture` 两次第二次无副作用；纹理销毁前后 `gfx.texture_bytes` 回到基线。FBO 不跨窗口共享（在 B 上下文绑定 A 的 FBO 名触发 GL 错误）。

**AC-GFX-017**　`[单元]` 覆盖：REQ-GFX-030。输入集：合法 PNG（RGBA、调色板、灰度、16 位）、JPEG（基线、渐进）、BMP（24 位、32 位）、GIF、TGA、PSD、损坏的 PNG（截断）、头部声明 20 000×20 000 的 PNG、总像素 70 MPx 的图。预期：前三类解码成功且尺寸与像素与参照一致（RGBA 非预乘）；GIF/TGA/PSD 返回 `error.UnsupportedFormat`；截断返回 `error.DecodeFailed`；超限两项返回 `error.TooLarge`，且在测试分配器上的最大单次分配 < 1 MiB（证明先查头再分配）；4 个线程各解码 100 次同一批文件，输出哈希一致，无数据竞争（线程消毒器运行）。

**AC-GFX-018**　`[回放]` 覆盖：REQ-GFX-031、REQ-GFX-033。一个图像控件引用路径 P（1024×1024），应用提供假 `ImageLoader`（只记录调用，稍后由测试经 `app.post` 回投 `insert`）。步骤：首次构建；回投像素；下一帧；再用一个不存在的路径 Q 重复；再 `loadSync` 一张 64×64 与一张 512×512 图像。预期：首次构建时 `ImageLoader` 被调用恰 1 次，构建函数在不执行任何解码的情况下返回（解码计数 0），状态 `loading`；回投后 `ready`，随后一帧的损伤恰为该图像控件的矩形；Q 的状态为 `failed`，产生恰 1 条 `warn`，之后 10 次构建中 `ImageLoader` 调用数增量为 0；`forgetFailure(Q)` 后下一次请求再次调用 1 次；64×64 同步成功，512×512 返回 `error.TooLargeForSync`；无 `ImageLoader` 时未命中直接 `failed`。

**AC-GFX-019**　`[计量]` 覆盖：REQ-GFX-032、REQ-GFX-033。缓存上限设为 8 MiB，依次 `insert` 100 张互不相同的 512×512 图像（每张 1 MiB 纹理）。预期：任一时刻 `cache.image.bytes` ≤ 8 MiB；`gfx.image_evictions` = 92（或更多，取决于固定开销，不得少于 92）；访问次序测试：先插入 A、B、…、H（8 张），再访问 A，再插入 I：被淘汰的是 B 而不是 A；一张本帧被绘制的图像在同帧内不被淘汰；`pinned` 图像在超限时不被淘汰，`release` 后可淘汰；被淘汰的路径图像再次 `request` 时 `ImageLoader` 恰被调用 1 次；进程常驻内存不随插入量线性增长（与 AC-ARCH-007 一致）。

**AC-GFX-020**　`[单元]` 覆盖：REQ-GFX-034。表驱动（纯函数）：
| 变体集 | scale | 预期选取 |
|---|---|---|
| {100, 150, 200} | 1.0 | 100 |
| {100, 150, 200} | 1.25 | 150 |
| {100, 150, 200} | 1.5 | 150 |
| {100, 150, 200} | 1.75 | 200 |
| {100, 150, 200} | 3.0 | 200（放大） |
| {100, 200} | 1.25 | 200 |
| {100} | 2.0 | 100（放大） |

另：单源 `source_scale_pct = 200`：scale 1.0 时缩小比 2.0 ≥ 1.5，纹理带 mipmap；scale 1.5 时缩小比 1.33，无 mipmap；scale 2.0 时 1:1，无 mipmap。`[金图]` 补充：scale 1.0 下缩小 4 倍的细线条图标，带 mipmap 的结果比无 mipmap 的与基准参照（高质量缩放）的平均误差更小，且不出现闪烁的锯齿（相邻两个子像素位移的结果差异 ≤ 参照）。

**AC-GFX-021**　`[单元]` 覆盖：REQ-GFX-035。在每个绘制遍结束、`present` 之后，通过 `glGet*` 查询并断言基线状态：混合开且函数为 `(ONE, ONE_MINUS_SRC_ALPHA)`、无深度测试、无剔除、`GL_UNPACK_ALIGNMENT` = 1、活动纹理单元 0；`gfx` 的 blit 与上传之后，读/写帧缓冲绑定、纹理 2D 绑定、VAO、程序与调用前相同。故意在一次绘制遍内插入一个非法 GL 调用：调试构建断言中止并报告遍序号；发布构建不检查。扫描 `src/`：除 `gfx`（及 `text` 后端实现，REQ-ARCH-003）外无 GL 调用，`gfx` 内 GL 状态修改只出现在 `gl_state.zig`。

**AC-GFX-022**　`[单元]` 覆盖：REQ-GFX-036。运行补丁登记检查脚本：以上游基线哈希还原 `third_party/nanovg/` 并与当前目录做差异；每个差异块必须落在 `PATCHES.md` 某条登记所列的函数内；每条登记包含全部必填字段，且其引用的 REQ 与 AC 存在。预期：无未登记差异块，无字段缺失。

**AC-GFX-023**　`[回放]` 覆盖：REQ-GFX-037。有 2 个窗口、3 个路径图像（已缓存）与 1 个 `pinned` 图像、文字图集已有字形时注入"上下文丢失"。预期：全部 `Surface.contentValid()` 为假；`ImageLoader.request` 对 3 个路径图像各调用恰 1 次，`reset` 回调恰 1 次；图集页由影子缓冲重新上传（字形无需重新光栅化，光栅化计数增量 0）；NanoVG 上下文重建计数 +2；下一帧两窗口均整根重绘并呈现，读回像素与丢失前同状态的基准一致；重建失败（桩注入）时 `platform.fatal` 被调用。

**AC-GFX-024**　`[单元]` 覆盖：REQ-GFX-038、REQ-GFX-039。(1) `readPixels` 读取 1×1、整窗、跨 `cap` 边界的矩形：返回 RGBA8、顶行在前、alpha 255、字节数 = `w × h × 4`；紧贴右下角的读取成功，超出一像素返回 `error.OutOfBounds`；缓冲不足返回 `error.BufferTooSmall`。(2) `.target` 与 `.presented` 在未启用 show-damage 时逐字节相等。(3) 无头上下文：`GL_VERSION` 报告 ≥ 3.3 且为 Core Profile；同一场景渲染 100 次的读回数据哈希全部相同。

**AC-GFX-025**　`[金图]` 覆盖：REQ-GFX-040。使用比对工具自检：(a) 在非文字像素上把一个通道改 1 个等级。预期失败，输出差异图并列出该像素；(b) `glfw` 基准的文字区域中改 1 个等级。预期失败；(c) `win32` 比对模式下对文字区域内 1% 以内的像素做 ±12 的改动。预期通过，做 ±13 或超过 1% 的像素改动预期失败；(d) 测试构建中 `textRegions` 恰包含该用例中每次 `drawGlyphQuads` 的外接矩形（外扩 1 ppx）；(e) 失败时基准文件未被修改；(f) 缺少对应后端基准时测试失败而不是静默通过。`[人工]` 补充：在 Windows 上对控件总览页生成 `win32` 基准，隔日在同一机器上重新比对，应通过。

**AC-GFX-026**　`[金图]` 覆盖：REQ-GFX-041。以 `-Dshow-damage=true` 构建：渲染一帧后仅一个叶节点的损伤 `(30,40,50,20)` 局部重绘并 `present`。预期：`readPixels(.presented)` 中该矩形内像素等于"页面像素以 `#FF00FF40` 叠加"的结果（±1），外框 1 ppx 为 `#FF00FFC0` 叠加；矩形外与基准一致；`readPixels(.target)` 完全不含叠加色（与同状态整根重绘一致）；下一帧只有另一矩形损伤时，上一矩形的叠加色已消失。关闭选项的构建中以相同步骤 `.presented` 与 `.target` 逐字节相等，且二进制中不含叠加路径的符号（符号检查）。

**AC-GFX-027**　`[计量]` 覆盖：REQ-GFX-042。运行"控件总览"页预热后的 100 帧随机交互回放。预期：REQ-GFX-042 列出的全部埋点计数器存在、非负且自洽：`gfx.pass_count ≥ frame.presents`；`gfx.upload_bytes` 非零；`frame.gl_draw_calls` 的每帧值被记录；`cache.image.bytes` ≤ 上限；`gfx.fbo_realloc` 在无尺寸变化的回放中增量为 0。

## 7. 待定问题

- **GFX-OPEN-01**　未修改的 NanoVG 在整数对齐的轴对齐矩形边缘上是否产生中间色，以及单个字形四边形一个 draw call 的开销是否可接受。需 M1 以 AC-GFX-006、AC-GFX-015 实测后决定是否需要补丁（REQ-GFX-036 的预期补丁位）。若字形绘制成为热点，考虑自写一个专用的字形批绘制后端（仍在 `gfx` 内部），与 ADR 0002 不冲突。
- **GFX-OPEN-02**　多个窗口（含多个弹出窗口）在同一线程依次 `SwapBuffers` 时垂直同步阻塞的累积延迟。当前做法：每窗口交换间隔 1 并依次呈现；若实测弹出窗口出现明显拖慢，备选是弹出窗口交换间隔 0，或仅在主根使用垂直同步。需 Windows 实机测量。
- **GFX-OPEN-03**　`glBlitFramebuffer` 整体拷贝在高分辨率（4K、8K）下的带宽开销与是否可以改为仅拷贝损伤矩形的并集（需要保证后缓冲未定义内容不外泄的前提，目前不满足）。需 12 的基准场景提供数据。
- **GFX-OPEN-04**　远程桌面、无驱动环境下是否引入 ANGLE 或 D3D11 后端（ADR 0002 已留口），以新 ADR 在实测后决定。
- **GFX-OPEN-05**　`gfx.decode` 可在工作线程调用，需要在 02 的 REQ-ARCH-008 线程安全清单中增补（该清单当前为封闭集合，未列入）。
- **GFX-OPEN-06**　Mesa llvmpipe 在 GL 3.3 Core 下的渐变与抗锯齿结果是否在不同 CPU 指令集（AVX2 / AVX512 / ARM）之间逐字节一致；若不一致，金图基准需对 CI 的 CPU 型号加固定约束，或对渐变区域放宽为 ±1。
- **GFX-OPEN-07**　位图图标之外的矢量图标缓存（把 `drawMark` 栅格化到纹理）是否有必要。当前答案：不缓存，路径直接绘制；若 12 的预算受影响再议。
