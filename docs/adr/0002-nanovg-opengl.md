# ADR 0002：NanoVG + OpenGL 3.3 Core 作为渲染后端，藏在薄 gfx 接口之后

**状态**：已采纳

## 背景
需要一个体量小、可读完、可修改的 2D 矢量渲染器，能画抗锯齿的圆角矩形、渐变、路径与贴图。Windows 上的候选图形 API 有 OpenGL、Direct3D 11、Direct2D。

## 决策
- 使用 NanoVG 官方实现及其 GL3 后端，源码 vendoring 进仓库，允许按需打补丁（补丁须在 `third_party/nanovg/PATCHES.md` 逐条登记）。
- 图形 API 为 **OpenGL 3.3 Core Profile**。Win32 后端通过 WGL（`WGL_ARB_create_context`、`WGL_ARB_pixel_format`、`WGL_EXT_swap_control`）创建上下文；GLFW 后端由 GLFW 创建。
- 控件与主题代码**不得**直接调用 NanoVG 或 OpenGL。它们只使用 `gfx` 模块暴露的绘制接口（见 04）。NanoVG 是 `gfx` 的实现细节。
- 文字不走 NanoVG 的 fontstash 主路径（见 ADR 0003），但字形图集以 NanoVG 图像的形式绘制。
- 每个顶层窗口（含弹出层）一个 GL 上下文，所有上下文共享对象（纹理、着色器），以便图集与图像跨窗口复用。

## 后果
- 两个平台后端共用同一套渲染代码，Linux 上可用 Mesa 软件光栅做无头金图测试。
- OpenGL 在 Windows 上依赖显卡驱动质量；远程桌面或无驱动环境可能只有 GL 1.1。启动时检测到上下文创建失败**必须**给出明确错误（见 03），是否引入 ANGLE 或 D3D11 后端留待实测后以新 ADR 决定。
- `gfx` 接口保持窄小，日后替换为 D3D11 后端时控件代码不需要改动。
- NanoVG 没有真正的局部重绘与图层缓存，需要在 `gfx` 层自行用剪裁与离屏帧缓冲补足（见 04）。

## 被否方案
- **Direct2D**：与"深度契合原生"相符且文字质量最好，但把渲染完全绑定在 Windows，Linux 开发机上无法运行与测试，且偏离用户指定的 NanoVG。
- **NanoVG 的 D3D11 移植**：非官方维护，质量不可控；窗口缩放时的呈现行为更好，但失去 Linux 可测性。保留为未来选项。
- **自写渲染器**：掌控度最高，但前期成本与本阶段目标不符。
