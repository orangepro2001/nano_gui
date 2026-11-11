# ADR 0003：文字以 DirectWrite 为主，fontstash 兜底

**状态**：已采纳

## 背景
NanoVG 自带的 fontstash 只做逐码点查字形与简单字距，没有字体回退链、复杂文种整形，小字号下的清晰度也不及系统渲染。本框架要长期承载中文界面，文字观感是第一印象。

## 决策
- 定义与后端无关的 `text` 接口（见 05）：字体选择、整段排版、测量、命中测试、字形光栅化。
- **Win32 后端**：用 DirectWrite 完成字体枚举与回退、整形、断行、字形光栅化。光栅结果写入框架自管的字形图集纹理，由 `gfx` 以贴图四边形绘制。
- 抗锯齿采用**灰度**（非 ClearType 子像素）。理由：子像素渲染要求知道背景色且不能经过任意合成，与图层缓存、半透明浮层、不同像素排列的显示器都有冲突；灰度在 ≥125% 缩放下与 ClearType 差距很小。
- 默认界面字体取系统消息字体（`SystemParametersInfo(SPI_GETNONCLIENTMETRICS)` 的 `lfMessageFont`），中文回退由 DirectWrite 系统回退链决定，不内嵌字体。
- **GLFW 后端**：用 NanoVG fontstash + 指定的字体文件。只保证拉丁与常用汉字能显示、度量稳定以支撑金图测试，不保证与 Win32 像素一致。
- 排版结果（字形运行、行信息）按内容哈希缓存，命中时不重新整形（见 05）。

## 后果
- Windows 上文字与系统应用观感一致，中文、emoji、混排无需额外工作。
- 两个后端的文字度量不同，因此**涉及文字的金图基准按后端分开存放**；布局逻辑测试使用固定度量的测试字体后端。
- 需要自写 DirectWrite 的 COM 绑定（接口不多：Factory、TextFormat、TextLayout、FontFallback、GlyphRunAnalysis）。
- 放弃子像素渲染，在 100% 缩放的低 DPI 屏上小字略逊于 ClearType。可接受。

## 被否方案
- **全平台 fontstash**：实现最简单，但中文回退与清晰度不达标。
- **FreeType + HarfBuzz**：跨平台像素一致、整形完备，但依赖重，且观感与 Windows 原生不同，仍需自行解决字体回退。
- **GDI 文字**：质量与 API 都已过时。
