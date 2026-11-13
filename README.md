# nano_gui

用 Zig + NanoVG + Win32/GLFW 构建的桌面应用开发套件：不依赖任何上层语言运行时，受控即时模式、被动刷新、性能优先，Windows 优先。

**规范与验收文档已完成第一版**（1177 条规范条款、673 条验收条款，按 M0–M6 七个里程碑归档）。实现正在进行，所有实现必须以 `docs/` 为准。

## 从哪里读起

| 想了解 | 读 |
|---|---|
| 全部文档的索引、术语、编号约定 | [docs/00-index.md](docs/00-index.md) |
| 做什么、不做什么 | [docs/01-vision-scope.md](docs/01-vision-scope.md) |
| 为什么这么定 | [docs/adr/](docs/adr/) |
| 框架的核心运行方式 | [docs/06-frame-model.md](docs/06-frame-model.md) |
| 视觉语言 | [docs/09-theme.md](docs/09-theme.md) |
| 先做什么后做什么 | [docs/14-roadmap.md](docs/14-roadmap.md) |
| 某个控件该怎么表现 | [docs/10-widgets/](docs/10-widgets/)（范本：[button.md](docs/10-widgets/button.md)） |
| 怎样算做完 | [docs/acceptance/](docs/acceptance/) |

## 在其他项目中使用

需要 Zig 0.17.1 或更新版本。

```sh
zig fetch --save git+https://github.com/orangepro2001/nano_gui.git#v0.1.0
```

`build.zig`：

```zig
const nano = b.dependency("nano_gui", .{
    .target = target,
    .optimize = optimize,
    // 可选：.@"text-backend" = "fontstash",  // Windows 默认 directwrite，其他平台默认 fixed
});
exe.root_module.addImport("nano_gui", nano.module("nano_gui"));
```

代码中 `const nano = @import("nano_gui");`，最小示例见 `examples/hello.zig`。Windows 上的系统库由模块自动链接；Linux 上的窗口宿主（X11/GLFW）由应用自行提供，参考仓库内 `examples/gallery_window.zig`。

## 一句话原则

规范先于代码；想改行为，先改文档（涉及已定决策时先改 ADR），再改实现。
