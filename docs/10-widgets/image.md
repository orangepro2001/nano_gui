# 图像（image）

## 1. 用途

显示一幅图像：内建标记字形与通用状态图标（`theme.Icon.mark`）、应用提供的位图（`gfx.ImageId`），或带多个缩放档的位图集合（`gfx.ImageSet`）。图像控件**只显示**，不可交互。参照 Windows 的 Static（`SS_ICON` / `SS_BITMAP`）。

- 需要点击 → 把图像放进 quiet 按钮（button 的 `variant = .quiet`）或在按钮选项里传 `icon`；本控件自身不响应点击。
- 按钮、标签、菜单项、标签页等控件自带的图标由该控件的 `icon` 选项绘制，不需要另放本控件。
- 大图的缩放、平移、选区 → 不支持（M5 之后另议）。
- 位图的解码与加载由 `gfx.images` 负责（04），本控件只消费其状态。

## 2. 解剖

```
 ┌───────────────────────────┐
 │       ┌─────────┐         │   ← 布局矩形（容器，无背景、无边框）
 │       │  图像   │         │   ← 图像：按缩放模式放入布局矩形
 │       └─────────┘         │
 └───────────────────────────┘
 加载中：drawTrack 占位          加载失败：border_strong 边框 + 错误标记
```

- **图像**：标记字形（矢量）或位图。
- **占位**：来源是位图且状态为 `loading` 或 `failed` 时绘制（REQ-W-IMAGE-008）。
- 没有标签、没有焦点环、没有容器填充。

## 3. 度量与布局

| 项 | 取值（令牌） |
|---|---|
| 标记字形尺寸 | `icon_sm`（默认）或 `icon_md`，见 `icon_size` |
| 位图自然尺寸 | `.image` 来源缺省取 `gfx.images.size(id)`（源像素，视作 lpx）；`.set` 来源及 `size` 尚不可得时由调用方给出 `natural_size`（lpx，逻辑尺寸 = 源像素 ÷ (`scale_pct` / 100)，REQ-GFX-034 第 5 条） |
| 内边距 | 无 |
| 绘制外延 | 0 |

**REQ-W-IMAGE-001**　默认尺寸策略：水平与垂直方向均 `fit`，期望尺寸 = 标记字形的 `icon_sm`/`icon_md` 见方，或位图的 `natural_size`（`ceil(lpx × scale)` 换算，REQ-LAYOUT-014）。调用方**可以**经通用布局选项设 `fixed`/`grow`/`fill` 等，此时图像按缩放模式（REQ-W-IMAGE-004）放入所得矩形。内容度量**不得**依赖加载状态：位图在 `loading`、`failed`、`ready` 三种状态下期望尺寸相同。

**REQ-W-IMAGE-002**　**图像来源**：来源是一个 `theme.Icon`（09），取下列之一：
- `.mark`：内建标记字形或通用状态图标；
- `.image`：一个 `gfx.ImageId`（应用持有其生命周期）；
- `.set`：一个 `gfx.ImageSet`（多缩放档位图或单张大源图，REQ-W-IMAGE-006）。

位图来源（`.image`、`.set`）的自然尺寸：`.image` 来源缺省取 `gfx.images.size(id)`（源像素，视作 lpx，REQ-GFX-034）；`size` 返回 `null`（尚未就绪或加载失败）或来源为 `.set`（加载前无法得知逻辑尺寸）时**必须**经 `natural_size` 给出，使内容度量不依赖加载状态（REQ-W-IMAGE-001）。缺失时调试构建断言，发布构建取 `icon_md` 见方。`.image` 的值为 `ImageId.none` 或世代已失效时按"加载失败"处理（REQ-W-IMAGE-008）并在调试构建断言。

**REQ-W-IMAGE-003**　**标记字形**：`.mark` 以 `drawMark(kind, 图像矩形, 颜色令牌, 0)` 绘制（末参为旋转角，图像不旋转，传 0），边长 `icon_sm` 或 `icon_md`（`icon_size`），颜色由 `tint` 决定（5.2）；字形按 REQ-THEME-029 在 16 lpx 网格上定义，`icon_md`（20 lpx）时整体等比放大。标记字形**必须**以文字色着色而不使用多色或位图（REQ-THEME-033）。

**REQ-W-IMAGE-004**　**缩放模式**（`scale`，作用于布局矩形 `D` 与图像自然尺寸 `N`，均换算为 ppx，图像始终在 `D` 内**居中**）：

| 模式 | 目标尺寸 | 裁剪 |
|---|---|---|
| `none` | `N`（不缩放；标记字形取 `icon_*` 边长） | 大于 `D` 的部分裁剪（`pushClip` 到 `D`） |
| `fit`（默认） | 等比缩放使其**完全落入** `D`：`s = min(Dw/Nw, Dh/Nh)`，尺寸 `round(N × s)` | 无；`D` 中图像之外的部分不绘制（无填充） |
| `fill` | 等比缩放使其**覆盖** `D`：`s = max(Dw/Nw, Dh/Nh)` | 裁剪到 `D` |
| `stretch` | 不等比，尺寸 = `D` | 无 |

标记字形是矢量：`fit`、`fill`、`stretch` 一律取 `min(Dw, Dh)` 见方居中（不拉伸变形）。`N` 或 `D` 任一维为 0 时不绘制。

**REQ-W-IMAGE-005**　**像素对齐**：图像的目标矩形（位置与尺寸）按 REQ-GFX-013 取整到整数 ppx；目标尺寸与所选图像的源像素尺寸相同（如 150% 缩放下选中 150 档且缩放模式使其恰为自然尺寸）时**必须**是逐像素的 1:1 绘制，不产生模糊（REQ-GFX-026）。居中偏移取 `floor((空间 − 尺寸) / 2)`，使同一缩放下位置确定。

**REQ-W-IMAGE-006**　**DPI 与多缩放档**：`.set` 来源每次构建以窗口 `scale` 调用 `images.pick(set, scale)` 取得所用 `ImageKey`（REQ-GFX-034：`s = round(scale × 100)`；多档取 `scale_pct ≥ s` 的最小档，不存在则取最大档并放大；单张源图按 `s / source_scale_pct` 缩放），再以 `images.request(key)` 取状态、`images.id(key)` 取 `ImageId`。图像的目的尺寸由 `natural_size` 与缩放模式决定（lpx），**不**由所选档的像素尺寸决定。缩放系数变化（DPI 变化）时重新选档；新档为 `loading` 而上一次绘制的 `shown_key` 仍为 `ready` 时**继续绘制** `shown_key`，直到新档 `ready`，使切换 DPI 时不闪出占位。`.image` 来源是单一纹理，不选档，按目的尺寸线性采样缩放；缩小比 ≥ 1.5 时的 mipmap 由 `gfx` 在上传时处理（REQ-GFX-034 第 4 条）。

**REQ-W-IMAGE-007**　**着色与禁用**：标记字形按 `tint` 取颜色（5.2）；`enabled = false` 时标记字形一律换 `text_disabled`。位图**不着色**，且**不因 `enabled` 改变**（REQ-THEME-005 禁止用透明度表达禁用，09 没有灰化配方）；应用需要禁用外观时提供另一张位图。高对比度下标记字形的颜色经令牌映射（REQ-THEME-035），位图不变。

**REQ-W-IMAGE-008**　**占位**（REQ-ARCH-018、REQ-GFX-033）：位图来源状态为 `loading` 时绘制 `drawTrack(D)`；为 `failed`（含解码失败、文件不存在、无 `ImageLoader`、超限、`ImageId` 无效）时绘制 `D` 的 `border_strong` 发丝线空框，`min(Dw, Dh) ≥ icon_sm` 时居中叠加 `error` 标记；二者**必须**可区分。占位矩形 `D` 即图像的布局矩形，占位期间期望尺寸与 `ready` 时相同（REQ-W-IMAGE-001）。控件**不**返回错误，也**不**自行记录日志（`failed` 的那一条 `warn` 由 `gfx` 记录，REQ-GFX-033）。

**REQ-W-IMAGE-009**　**加载流程**：位图来源每次构建经 `images.request(key)` 取得状态；缓存未命中时由 `gfx` 同步调用应用的 `ImageLoader` 启动加载（至多一次，REQ-GFX-031 第 3 条），控件不创建线程、不解码。**位图状态在绘制时取得**：构建期经 `images.request(key)` 只用于触发加载与填写 `ImageResult.state`（仅供应用参考）；节点属性中**不**保存构建期读到的 `loading`/`ready`/`failed`，绘制函数在绘制时经 `gfx.images` 的状态查询（`images.state(key)`、`images.id(key)`）取得当前状态并据此绘制位图或占位。加载完成（`images.insert`）后 `gfx` 对使用该图像的节点置 `paint`（REQ-GFX-031 第 2 条），因此该节点在下一帧重绘即显示位图，无需重建；若节点属性中存着旧状态，则此 `paint` 会重绘出过时的占位，故必须在绘制时查询。`failed` 状态不再触发 `ImageLoader`，直到应用调用 `images.forgetFailure(key)`（REQ-GFX-033）。

## 4. 变体与参数

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `scale` | `enum { none, fit, fill, stretch }` | `fit` | 缩放模式（REQ-W-IMAGE-004） |
| `natural_size` | `?core.Vec2` | `null` | 位图的自然（逻辑）尺寸，lpx；`.set` 来源、或 `gfx.images.size` 不可得时必须给出；`.image` 来源缺省取 `images.size(id)`；标记字形忽略 |
| `icon_size` | `enum { sm, md }` | `sm` | 标记字形边长档：`icon_sm` / `icon_md` |
| `tint` | `ImageTint` | `.auto` | 标记字形的着色角色，见 5.2；位图忽略 |
| `alt` | `?[]const u8` | `null` | 替代文字（无障碍名称）；`null` 表示装饰性图像（REQ-W-IMAGE-011） |
| `tooltip` | `?[]const u8` | `null` | 悬停提示；非空时才登记 `hover` 兴趣（`hover_visual = false`） |
| `enabled` | `bool` | `true` | 仅影响标记字形的颜色（`text_disabled`）；位图不受影响（REQ-W-IMAGE-007） |
| `key`、`debug_name`、`layout` | 通用 | | 见模板 |

`ImageTint = enum { auto, primary, secondary, danger, warning, success, info }`。`auto`：状态标记（`info`、`warning`、`error`、`success`）取对应的 `status_*`，其余标记取 `text_primary`。图像来源不是选项而是位置参数。

## 5. 状态

### 5.1 状态机

不适用：图像控件没有交互状态，不响应任何输入。其显示由来源的**加载状态**决定（来源为位图时），该状态由 `gfx.images` 维护而非本控件：

| 当前加载状态 | 事件 | 下一状态 | 动作 |
|---|---|---|---|
| （无）未请求 | 首次声明 `.set` 来源 | `loading` | `images.request(key)`；key 由 `images.pick(set, scale)` 取得（REQ-W-IMAGE-006） |
| `loading` | 应用经 `images.insert` 完成上传 | `ready` | 对使用该图像的节点置 `paint`（REQ-GFX-031），绘制图像 |
| `loading` | 加载或解码失败 | `failed` | `gfx` 记录恰一条 `warn`，建立失败缓存（REQ-GFX-033） |
| `failed` | 应用调用 `images.forgetFailure(key)` 后再次声明 | `loading` | 重新请求 |
| `ready` | 缓存被淘汰 | `loading` | 重新请求（REQ-GFX-032）；淘汰不发生于当前帧内被绘制过的图像 |
| `ready` | 缩放档变化（DPI 变化） | 新 key 的状态 | 见 REQ-W-IMAGE-006 |

### 5.2 视觉表现

| 状态 | 绘制（基元 + 令牌） |
|---|---|
| 标记·启用 | `drawMark(kind, 矩形, 颜色, 0)`：`tint = .auto` 时状态标记取 `status_info`/`status_warning`/`status_danger`（`error` 标记）/`status_success`，其余取 `text_primary`；`primary` → `text_primary`；`secondary` → `text_secondary`；`danger/warning/success/info` → 对应 `status_*` |
| 标记·禁用 | `text_disabled`（无论 `tint`） |
| 位图·`ready` | `Canvas.drawImage(id, 目标矩形, .{})`，不着色（`tint` 缺省，保留源色） |
| 位图·`loading` | 占位：`drawTrack(D)`（`surface_track` + 顶部 `inset_shadow`，圆角 `radius_mark`） |
| 位图·`failed` | 占位：`D` 的 `border_strong` 发丝线描边（圆角 `radius_mark`）；`min(Dw, Dh) ≥ icon_sm` 时居中叠加 `error` 标记（`status_danger`，`icon_sm`） |

`loading` 与 `failed` 的占位在外观上**必须**可区分（REQ-GFX-033）：前者是填充槽，后者是空框加错误标记。

## 6. 鼠标行为

**REQ-W-IMAGE-010**　图像**不可交互**：不登记 `click`/`drag`/`context`/`wheel`，不取得焦点，不在 Tab 序内，不吞鼠标事件。其上的左键、右键、双击、拖拽、滚轮按未命中该控件处理，沿祖先冒泡（REQ-INPUT-019）；指针形状恒为箭头。仅当 `tooltip` 非空时登记 `hover` 兴趣以显示提示框，置 `hover_visual = false`（悬停变化不置脏，REQ-FRAME-037），此时仍不处理任何点击。需要点击的图像**必须**包在 quiet 按钮里（或使用按钮的 `icon`）。

## 7. 键盘行为

无键位：图像不可聚焦，不处理任何键，不登记助记符。

| 键 | 行为 |
|---|---|
| （任何键） | 不处理 |

## 8. 焦点

不适用：图像不可聚焦、不是 Tab 停靠，没有焦点环；任何键盘与焦点事件**不得**改变其显示，也不影响 Tab 序与焦点转移（REQ-INPUT-042）。

## 9. 文本与输入法

不适用：图像不显示文本、不接受文本输入。`alt` 与 `tooltip` 仅用于无障碍名称与悬停提示。

## 10. 动效

不适用：图像没有动效（加载完成的出现是瞬时的，不做淡入，REQ-THEME-006 禁止入场动画）。

## 11. 无障碍

| 项 | 值 |
|---|---|
| UIA 控件类型 | Image |
| 名称来源 | `alt`；`alt` 为 `null` 时取 `tooltip`；再无则为装饰性图像 |
| 支持的模式 | 无 |
| 状态属性 | IsEnabled；装饰性图像（`alt` 与 `tooltip` 均为 `null`）的 `IsContentElement` 与 `IsControlElement` 为假，不进入读屏遍历 |

**REQ-W-IMAGE-011**　有 `alt`（或 `tooltip`）的图像**必须**以 Image 类型暴露其名称；二者均无的图像**必须**作为装饰性元素对辅助技术隐藏。图像不可聚焦、不可调用、不提供任何模式。位图加载失败时名称不变。

## 12. API 草案

```zig
// 草案：仅签名
pub const ImageScale = enum { none, fit, fill, stretch };
pub const ImageIconSize = enum { sm, md };
pub const ImageTint = enum { auto, primary, secondary, danger, warning, success, info };

pub const ImageOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    scale: ImageScale = .fit,
    natural_size: ?core.Vec2 = null,   // lpx；.set 或 images.size 不可得时必须给出
    icon_size: ImageIconSize = .sm,
    tint: ImageTint = .auto,
    alt: ?[]const u8 = null,           // 借用至本帧结束；框架复制
    tooltip: ?[]const u8 = null,       // 借用至本帧结束；框架在需要显示时复制
    layout: layout.ItemOptions = .{},  // 各控件共用（07）
};

pub const ImageResult = struct {
    // 持续性状态（图像没有激活类结果）
    hovered: bool,                     // 仅 tooltip 非空时可能为真
    state: gfx.ImageState,             // 构建期快照，仅供应用参考，不参与绘制；标记字形恒为 .ready
};

/// source：按值传入的 theme.Icon。.image 的生命周期由应用负责；.set 的 variants 切片与其中的 ImageKey 借用至本帧结束。
/// 加载失败不返回错误（REQ-ARCH-018）：退化为占位表现，state 报告 .failed。
pub fn image(ui: *Ui, src: std.builtin.SourceLocation, source: theme.Icon, opts: ImageOptions) ImageResult;
```

图像是只读控件：没有激活类结果，不触发第二构建遍；`hovered` 与 `state` 是持续性状态。控件不持有也不写入应用的数据；位图的所有权与缓存归 `gfx.images`。

## 13. 保留状态

| 字段 | 类型 | 保留级别 | 说明 |
|---|---|---|---|
| `shown_key` | `gfx.ImageKey`（仅 `.set` 来源） | transient | 最近一次成功绘制的图像 key；DPI 变化后新档尚未就绪时继续绘制它（REQ-W-IMAGE-006） |

无其他状态槽；不登记指针兴趣时没有框架内建交互状态。

## 14. 失效规则

**REQ-W-IMAGE-012**　绘制键**必须**由以下各项构成：来源标识（标记种类，或图像 ID / `ImageSet` 所选 key）、`scale`、`icon_size`、`tint`、`enabled`（仅标记）、缩放系数（决定所选档）。位图的加载状态**不进入**绘制键：它由绘制函数在绘制时查询，其变化由 `gfx` 对使用该图像的节点置 `paint`（REQ-W-IMAGE-009）。布局输入的内容度量键由 `natural_size`（或 `icon_size`）与 `scale` 构成，**不含**加载状态。

| 变化 | 置脏级别 | 损伤范围 |
|---|---|---|
| 位图由 `loading` 变 `ready`（`images.insert`，REQ-GFX-031），自然尺寸已由 `natural_size`/`images.size` 在构建期给定 | `paint`（由 `gfx` 置脏，绘制时查询状态） | 图像矩形 |
| 自然尺寸由未知变为已知（`images.size(id)` 由 `null` 变为有值，且未给 `natural_size`） | `build`（内容度量变化，需要重新布局） | 新旧矩形 |
| 位图进入 `failed` | `paint` | 图像矩形 |
| 来源或 `scale`、`tint`、`icon_size`、`natural_size` 变化 | `build`（由应用引起） | 新旧矩形 |
| DPI 变化 | `build`（REQ-FRAME-037），重新选档 | 整根 |
| 指针移动、悬停（含有 `tooltip` 时） | 不置脏（无视觉变化） | 空 |

**REQ-W-IMAGE-013**　位图加载完成（`loading → ready`）所产生的帧**必须**是纯绘制帧（构建遍数 0、不改变任何节点的布局矩形；自然尺寸已由 `natural_size` 给定时不需要 `build`）；图像上的指针移动与悬停**不得**置脏、不产生帧（REQ-FRAME-037）。同一 `ImageKey` 在未完成前至多触发一次 `ImageLoader` 调用，控件的重复构建**不得**重复请求（REQ-GFX-031 第 3 条）。

## 15. 边界与错误情况

| 情况 | 规定 |
|---|---|
| 位图来源缺 `natural_size` | 见 REQ-W-IMAGE-002 |
| `natural_size` 任一维 ≤ 0 | 当作 0；不绘制（占位也不画）；调试构建断言 |
| `.set` 为空（无变体） | 当作加载失败；调试构建断言 |
| 布局矩形为 0 尺寸 | 不绘制 |
| `scale = .fill` 或 `none` 且图像大于布局矩形 | 以布局矩形裁剪（`pushClip`），不越出 |
| 缩小比（源像素宽 ÷ 目的 ppx 宽）≥ 1.5 | 上传时生成 mipmap（REQ-GFX-034 第 4 条），由 `gfx` 负责，控件不干预 |
| 图像被缓存淘汰 | 回到 `loading` 并重新请求；占位期间不闪烁整个布局（尺寸不变） |
| DPI 变化时新档未就绪 | 继续绘制 `shown_key`（若其仍为 `ready`，且可能略模糊）；新档就绪后切换 |
| 上下文丢失（`render_lost`） | 由 `gfx` 重新上传（REQ-GFX-037）；控件无需处理 |
| 禁用（`enabled = false`）的位图 | 不改变绘制（REQ-W-IMAGE-007） |
| 来源为已销毁的 `ImageId`（世代失效） | `gfx` 世代校验失败：不绘制图像，本控件改画失败占位并调试构建断言 |
| 窗口非活动 | 外观不变 |

## 16. 验收标准

**AC-W-IMAGE-001**　`[金图]` 覆盖：REQ-W-IMAGE-001、REQ-W-IMAGE-004、REQ-W-IMAGE-005。渲染：一张 40×20 lpx 自然尺寸的位图（`insert` 的棋盘图）与一张 20×40 的位图，分别放入 100×60 lpx 的固定矩形，`scale` 取 none/fit/fill/stretch 四种；另渲染不指定矩形（`fit` 策略）的两张图；缩放 1.0/1.5/2.0。预期：与基准图一致；几何断言——`none`：图像为自然尺寸且居中，超出矩形的部分被裁剪；`fit`：40×20 图尺寸为 100×50、20×40 图为 30×60，均居中；`fill`：40×20 图覆盖整个矩形（尺寸 120×60，被裁剪到 100×60）；`stretch`：尺寸 = 矩形；不指定矩形时布局尺寸 = `natural_size`；目标尺寸等于源像素尺寸的情形（缩放 1.0、`none`）逐像素与源一致（无模糊，REQ-GFX-026）；居中偏移取 `floor`，两个缩放下位置恒定。

**AC-W-IMAGE-002**　`[金图]` 覆盖：REQ-W-IMAGE-003、REQ-W-IMAGE-007。渲染全部标记字形（`MarkKind` 各成员）于 `icon_sm` 与 `icon_md` 两档，`tint` 取 auto / primary / secondary / 四种状态色，启用与禁用，浅/深/高对比度，缩放 1.0/1.5/2.0。预期：与基准图一致；边长 = `px(icon_sm)`/`px(icon_md)`；`auto` 下 `info`、`warning`、`error`、`success` 四个标记依次为 `status_info`、`status_warning`、`status_danger`、`status_success`，其余标记 `text_primary`；禁用态全部为 `text_disabled`；标记为单色（颜色集合为单一令牌色 ∪ 抗锯齿过渡）；位图（`enabled = false`）渲染结果与启用时逐像素相同。

**AC-W-IMAGE-003**　`[金图]` 覆盖：REQ-W-IMAGE-008。渲染一张处于 `loading` 状态的图像（`ImageLoader` 未回投）、一张 `failed`（文件不存在）的图像，各取 80×60 lpx 与 12×12 lpx 两种矩形；浅/深/高对比度。预期：与基准图一致；`loading` 为 `drawTrack` 槽、不含边框描边与错误标记；`failed` 为 `border_strong` 描边的空框，80×60 时居中带 `error` 标记（`status_danger`）、12×12（< `icon_sm`）时无标记；二者像素差异可区分；`failed` 的占位尺寸与 `loading` 相同。

**AC-W-IMAGE-004**　`[回放]` 覆盖：REQ-W-IMAGE-010、REQ-W-IMAGE-011。确认不响应输入。图像位于可滚动容器内，外层面板登记了 `click`；另有一个包着图像的 quiet 按钮 B。脚本：在图像上依次左键单击、双击、右键、按下后拖动；滚动滚轮；Tab 三次、Space、Enter。预期：图像无焦点、Tab 序列不含图像（只含 B）；单击被外层面板接收；滚轮 → 容器偏移变化；指针形状为箭头；上述输入期间图像的绘制节点计数为 0；点击 B → `clicked` 真。给出 `tooltip` 的图像：悬停推进假时钟超过系统悬停时间 → 出现提示框，点击仍由外层面板接收。

**AC-W-IMAGE-005**　`[回放]` 覆盖：REQ-W-IMAGE-006、REQ-W-IMAGE-013。`ImageSet` 含 100、150、200 三档（尺寸分别为 16、24、32 像素见方），`natural_size` = 16×16 lpx。依次在缩放 1.0、1.25、1.5、1.75、2.0、2.5 下构建：所选档依次为 100、150、150、200、200、200（REQ-GFX-034 第 2 条；2.5 取最大档放大）；缩放为 1.5 时 24×24 源像素图 1:1 绘制。单张大源图（`source_scale_pct = 200`，64×64 像素，`natural_size` = 32×32 lpx）：缩放 1.0 时缩小比 2.0 → 上传时带 mipmap；缩放 2.0 时 1:1 且无 mipmap。DPI 由 1.0 变为 2.0：200 档尚在 `loading` 时继续绘制 100 档（金图保持旧图，不出现 `loading` 占位）；200 档 `ready` 后下一帧切换，且该帧构建遍数为 0。每个 `ImageKey` 的 `ImageLoader` 调用次数恒为 1（多次重复构建不增加）。

**AC-W-IMAGE-006**　`[回放]` 覆盖：REQ-W-IMAGE-008、REQ-W-IMAGE-009、REQ-W-IMAGE-013。一张尚未加载的图像：首帧 `ImageResult.state = .loading`，绘制函数在绘制时查询得 `loading` 并绘制 `drawTrack` 占位，`ImageLoader` 被同步调用 1 次；应用经 `images.insert` 回投 → `gfx` 对该节点置 `paint`，下一帧绘制函数在绘制时查询得 `ready` 并绘制位图（构建函数未重跑亦如此），该帧构建遍数为 0、损伤 = 图像矩形、所有节点的布局矩形不变。另一张加载失败的图像：`gfx` 记录恰 1 条 `warn`（控件不再自行记录）、`state = .failed`、绘制失败占位；重复构建 20 次 → `ImageLoader` 调用与 `warn` 计数均不再增加；`images.forgetFailure(key)` 后再构建 → 重新进入 `loading` 并再次调用 `ImageLoader` 1 次。构建函数全程无 `try`。

**AC-W-IMAGE-007**　`[单元]` 覆盖：REQ-W-IMAGE-002、REQ-W-IMAGE-011、REQ-W-IMAGE-001。`.set` 来源缺 `natural_size`、或 `.image` 来源在 `images.size` 为 `null` 时缺 `natural_size` → 调试构建断言中止；发布构建取 `icon_md` 见方。`.image` 来源已就绪且未给 `natural_size` → 期望尺寸取 `images.size(id)`。`ImageId.none` → 失败占位 + 调试构建断言。`natural_size` 为 0 → 不绘制。三种来源（`.mark`、`.image`、`.set`）下期望尺寸分别为 `icon_sm`、`images.size`（或 `natural_size`）、`natural_size` 换算的 ppx，且在 `loading`/`failed`/`ready` 三种状态下相同。经假 UIA 入口：给 `alt` → 控件类型 Image、Name 为 `alt`、不提供任何模式；`alt` 缺省而给 `tooltip` → Name 为 `tooltip`；二者均缺省 → `IsContentElement` 假、`IsControlElement` 假；图像不可聚焦。

**AC-W-IMAGE-008**　`[计量]` 覆盖：REQ-W-IMAGE-012、REQ-W-IMAGE-013。界面含 100 个图像（50 个标记、50 个位图均已 `ready`）。回放：指针移过全部图像（其中 10 个带 `tooltip`，停留不足悬停时间）→ `frame.count` 增量为 0（REQ-FRAME-037）。仅改变某图像的 `tint` 并 `invalidate(.build)` → 损伤恰为该图像矩形；以相同参数再次 `invalidate(.build)` → 损伤为空、`frame.presents` 不变。对某 `loading` 图像回投 `insert` → 该帧 `frame.build_passes` 增量为 0，被绘制的节点集合 ⊆ {该图像及其与损伤相交的祖先}，损伤 = 该图像矩形。重复构建 100 次后 `ImageLoader` 总调用数 = 位图图像的不同 key 个数。

## 17. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-W-IMAGE-01 | 禁用态的位图不变灰（REQ-THEME-005 禁止用透明度，09 无灰化着色配方） | 先不处理；应用需要时提供禁用版位图 |
| OPEN-W-IMAGE-02 | 是否提供圆角裁剪或边框（头像、缩略图） | 不提供；需要边框时用 group-box 或自绘容器 |
| OPEN-W-IMAGE-03 | 位图的 `fill` 模式的对齐点（居中以外）与 `tint` 位图单色化 | 不提供 |
