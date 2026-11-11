# 分隔线（separator）

## 1. 用途

在相邻的控件组之间画一条发丝线，表示分组边界。分隔线**不可交互**、没有状态、不可聚焦。参照 Windows 对话框中的 Static（`SS_ETCHEDHORZ` / `SS_ETCHEDVERT`）与菜单、工具栏中的分隔线。

- 需要带标题并框住一组控件 → 用 group-box。
- 可由用户拖动调整两侧大小 → 用 splitter（07 的容器），不是本控件。
- 窗口内大块区域之间的结构性边界（工具栏底、状态栏顶）由工具栏、状态栏控件自己绘制，也可用本控件的 `structural` 变体。
- 仅为了留白 → 用容器的 `gap`，不要用分隔线。

## 2. 解剖

```
 水平分隔线（在 Column 中）          垂直分隔线（在 Row 中）

  ──────────────────────              A  │  B
                                          │
  └ 厚度 = gap_xs，线 = 一条发丝线           └ 厚度 = gap_xs
```

- **线**：一条发丝线（REQ-THEME-012），位于节点厚度内居中。
- 没有其他部件：无标签、无图标、无容器填充。

## 3. 度量与布局

| 项 | 取值（令牌） |
|---|---|
| 厚度 | `gap_xs`（换算按 REQ-THEME-013），线本身为发丝线宽并在厚度内居中 |
| 长度 | 填满父容器的交叉轴（线的方向沿父容器的交叉轴） |
| 两端缩进 | `inset`（`theme.Gap`，默认 `none`） |
| 颜色 | 普通：`border_subtle`；`structural`：`border_strong`（REQ-THEME-026） |
| 绘制外延 | 0 |

**REQ-W-SEPARATOR-001**　**自动方向**：`orientation` 为 `null`（默认）时，由 `ui.parentAxis()`（07：当前最内层容器的主轴）决定：`parentAxis` 为水平（Row）时为**垂直**线，为垂直（Column）时为**水平**线（线沿父容器的交叉轴延伸，厚度占父容器的主轴）。`parentAxis` 对 Row 与 Column 以外的容器（Stack、Form、Table 单元格、Scroll 内容、根）一律报告水平，因而线为垂直；这些场景下分隔线**应当**显式指定 `orientation`。方向在每次构建时按 `parentAxis` 决定，父容器变化时随之变化。

**REQ-W-SEPARATOR-002**　**显式方向**：`orientation` 非空时按其取值，不受父容器影响。显式方向与自动方向一致时，尺寸策略同 REQ-W-SEPARATOR-003；不一致时（如在 Row 中显式取水平），厚度沿父容器的交叉轴 `fixed(gap_xs)`、长度沿父容器的主轴 `grow(1)`（使其占满该行的剩余空间；调用方可经 `layout` 覆盖为 `fixed`）。

**REQ-W-SEPARATOR-003**　默认尺寸策略：厚度方向 `fixed(gap_xs)`，长度方向 `fill`（父容器交叉轴；交叉轴为非确定且无界时退化为 `fit`，期望长度为 0，REQ-LAYOUT-009）。调用方**可以**经通用布局选项覆盖。`inset` 不为 `none` 时，线的两端各向内缩 `px(inset)`；缩进后长度不足 0 时线不绘制。

## 4. 变体与参数

| 参数 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `orientation` | `?layout.Orientation` | `null` | `null` 为自动方向（REQ-W-SEPARATOR-001） |
| `structural` | `bool` | `false` | `true` 用于 `surface_panel` 与 `surface_window` 交界处的结构性分隔，线色 `border_strong` |
| `inset` | `theme.Gap` | `.none` | 线两端的缩进 |
| `enabled` | `bool` | `true` | 保留字段：对外观与行为没有影响（分隔线没有禁用外观，不响应输入） |
| `key`、`debug_name`、`layout` | 通用 | | 见模板 |

没有颜色、粗细、线型（虚线、点线）参数。

## 5. 状态

### 5.1 状态机

不适用：分隔线没有状态，不响应任何输入，也不因悬停、聚焦、禁用而改变外观。

### 5.2 视觉表现

| 状态 | 绘制（基元 + 令牌） |
|---|---|
| 唯一外观 | `drawSeparator(a, b, structural)`：`a`、`b` 为线的两端点（两端各缩进 `inset`）。普通 `border_subtle`，`structural` 为 `border_strong` |

**REQ-W-SEPARATOR-004**　绘制：线宽 = 发丝线宽 `max(1, floor(scale))` ppx（REQ-THEME-012），在节点厚度内居中（偏移 `floor((厚度 ppx − 线宽) / 2)`），两侧都落在整数 ppx 坐标上；线长为节点沿线方向的全长减去两端 `inset`；水平线、垂直线只是坐标轴互换，颜色一致。高对比度下颜色由 REQ-THEME-035 映射，不引入新颜色。

## 6. 鼠标行为

**REQ-W-SEPARATOR-005**　分隔线**不可交互**：不登记任何指针兴趣（不进入命中表，REQ-INPUT-007），因此不产生悬停、不吞鼠标事件、不取得捕获、不显示提示框，也不改变指针形状（指针形状由其下方的节点决定）。其上的左键、右键、双击、拖拽、滚轮按未命中该控件处理，沿所在位置下方的节点与祖先正常路由（REQ-INPUT-019）。

## 7. 键盘行为

无键位：分隔线不可聚焦，不处理任何键，不登记助记符。

| 键 | 行为 |
|---|---|
| （任何键） | 不处理 |

## 8. 焦点

不适用：分隔线不可聚焦、不是 Tab 停靠，不进入 Tab 序，不是漫游组成员，也不影响焦点转移（REQ-INPUT-037、REQ-INPUT-042）。

## 9. 文本与输入法

不适用：分隔线不显示文本、不接受文本输入。

## 10. 动效

不适用：分隔线没有动效（无状态可过渡）。

## 11. 无障碍

| 项 | 值 |
|---|---|
| UIA 控件类型 | Separator |
| 名称来源 | 无（装饰性，`IsContentElement` 为假，`IsControlElement` 为假） |
| 支持的模式 | 无 |
| 状态属性 | 无；`Orientation` 取线的方向（水平/垂直） |

**REQ-W-SEPARATOR-006**　分隔线对辅助技术只暴露为 Separator 类型的装饰元素（不属于内容视图），不可聚焦、不提供任何模式；它**不得**出现在读屏的 Tab 或方向键遍历的可聚焦序列中。

## 12. API 草案

```zig
// 草案：仅签名
pub const SeparatorOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,              // 保留字段，无效果
    orientation: ?layout.Orientation = null,   // null = 由父容器自动决定
    structural: bool = false,
    inset: theme.Gap = .none,
    layout: layout.ItemOptions = .{},  // 各控件共用（07）
};

/// 分隔线没有结果：不可交互、没有持续性状态，也没有激活类结果。
pub const SeparatorResult = struct {};

pub fn separator(ui: *Ui, src: std.builtin.SourceLocation, opts: SeparatorOptions) SeparatorResult;
```

分隔线不持有任何应用值，也不借用调用方的切片。`SeparatorResult` 为空结构，仅为与其他控件的形状一致（REQ-CONV-010）。

## 13. 保留状态

不适用：分隔线没有状态槽，也不使用框架内建的交互状态（不登记指针兴趣）。

## 14. 失效规则

**REQ-W-SEPARATOR-007**　绘制键**必须**由以下各项构成：方向、`structural`、`inset`。布局输入的内容度量键由方向构成（厚度与长度策略随之变化）。

| 变化 | 置脏级别 | 损伤范围 |
|---|---|---|
| 方向变化（父容器变化或 `orientation` 变化） | `layout`（随同构建） | 新旧矩形 |
| `structural` 或 `inset` 变化 | `build`（由应用引起） | 分隔线矩形 |
| 指针经过、点击、按键 | 不置脏 | 空 |
| 缩放或主题变化 | `build`（REQ-FRAME-037） | 整根 |

**REQ-W-SEPARATOR-008**　指针移入或移出分隔线所覆盖的区域**不得**产生任何帧（分隔线不在命中表内，悬停目标不因它而变）；以相同参数重复声明的分隔线不产生损伤。

## 15. 边界与错误情况

| 情况 | 规定 |
|---|---|
| 长度为 0 或 `inset` 过大 | 不绘制线；节点仍存在，厚度照常占位 |
| 位于 Stack/Form/Table/Scroll 内且无显式方向 | 见 REQ-W-SEPARATOR-001 |
| 父容器为 `fit` 且无其他子项 | 长度退化为 0，不绘制 |
| 被 `layout` 覆盖为大于默认厚度的 `fixed` | 线仍为发丝线宽并在厚度内居中，多余厚度为留白 |
| 位于被禁用的容器内 | 外观不变（不整体变灰） |
| `hidden` | 占位但不绘制（07，REQ-LAYOUT-005） |
| 缩放极端（> 8） | 线宽取 `floor(scale)` ppx；不保证，见 07 第 5 节 |

## 16. 验收标准

**AC-W-SEPARATOR-001**　`[金图]` 覆盖：REQ-W-SEPARATOR-001、REQ-W-SEPARATOR-002、REQ-W-SEPARATOR-003、REQ-W-SEPARATOR-004。渲染：Row 中夹在两个按钮之间的分隔线（自动，应为垂直）；Column 中夹在两个标签之间的分隔线（自动，应为水平）；Row 中显式水平的分隔线；Column 中显式垂直的分隔线（给定 `fixed` 高度）；`structural` 与普通各一；`inset = .md` 一条；缩放 1.0/1.25/1.5/2.0，浅/深/高对比度。预期：与基准图一致；布局断言——自动垂直线宽度 = `px(gap_xs)`、高度 = Row 内部高度；自动水平线高度 = `px(gap_xs)`、宽度 = Column 内部宽度；线宽恒为发丝线宽（1/1/1/2 ppx），像素为纯色且无抗锯齿中间色；线在厚度内居中；`structural` 线色 = `border_strong`，普通线色 = `border_subtle`；`inset` 线两端各缩进 `px(gap_md)`；Stack 内无显式方向的分隔线 → 垂直（`parentAxis` 为水平）。

**AC-W-SEPARATOR-002**　`[回放]` 覆盖：REQ-W-SEPARATOR-005、REQ-W-SEPARATOR-006。确认不响应输入。界面：Column 内依次为按钮 A、分隔线、按钮 B，外层面板登记了 `click`。脚本：指针移到分隔线上；左键单击、双击、按下后拖动、右键、中键；滚动滚轮（外层为可滚动容器）；按 Tab 三次、Space、Enter。预期：分隔线上指针移动期间悬停目标为外层面板（而非分隔线）；左键单击被外层面板接收；滚轮 → 容器偏移变化；平台层记录的指针形状与下方节点一致（外层面板为箭头）；Tab 序列依次为 A → B（不含分隔线）；任何输入期间分隔线的绘制节点计数为 0；经假 UIA 入口：控件类型 Separator、`IsContentElement` 假、`IsControlElement` 假、不提供任何模式，且遍历可聚焦元素时不含它。

**AC-W-SEPARATOR-003**　`[单元]` 覆盖：REQ-W-SEPARATOR-001、REQ-W-SEPARATOR-002、REQ-W-SEPARATOR-007。方向判定：对父容器种类 {Row, Column, Stack, Form, Table 单元格, Scroll, 根} 逐一调用，自动方向依次为 垂直、水平、垂直、垂直、垂直、垂直、垂直（`parentAxis` 对 Row 与非 Row/Column 容器报告水平，对 Column 报告垂直）。同一分隔线的父容器由 Row 换成 Column 后下一次构建方向随之改变，绘制键不同。`orientation` 显式给定时不论父容器均按其取值。绘制键仅由 {方向, `structural`, `inset`} 决定：改变 `enabled` 不改变绘制键。

**AC-W-SEPARATOR-004**　`[计量]` 覆盖：REQ-W-SEPARATOR-007、REQ-W-SEPARATOR-008。界面含 100 条分隔线（Row 与 Column 各半）。回放：指针匀速扫过全部分隔线 → 在该扫动期间，若指针未改变外层悬停目标，`frame.count` 增量为 0；若外层悬停目标变化，各帧构建遍数为 0。以相同参数再次 `invalidate(.build)` → 损伤为空、`frame.presents` 不变。仅把其中一条的 `structural` 由假改为真并 `invalidate(.build)` → 损伤恰为该线的矩形。缩放由 1.0 改为 2.0 → 整根重绘，线宽由 1 ppx 变为 2 ppx。

## 17. 待定问题

| 编号 | 问题 | 当前倾向 |
|---|---|---|
| OPEN-W-SEPARATOR-01 | 是否提供虚线、带标题的分隔线（"—— 标题 ——"） | 不提供；带标题的分组用 group-box 或 label + separator 组合 |
| OPEN-W-SEPARATOR-02 | 节点厚度取 `gap_xs`（含线两侧的留白），是否需要更紧凑的厚度选项 | 不提供厚度参数；间距由容器的 `gap` 控制 |
