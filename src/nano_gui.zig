//! nano_gui 公共入口。外部代码只导入本文件（REQ-ARCH-006）。

pub const core = @import("core.zig");
pub const platform = @import("platform.zig");
pub const gfx = @import("gfx.zig");
pub const text = @import("text.zig");
pub const theme = @import("theme.zig");
pub const layout = @import("layout.zig");
pub const input = @import("input.zig");
pub const ui = @import("ui.zig");
pub const widgets = @import("widgets.zig");
pub const app = @import("app.zig");
pub const commands = app.commands;
pub const settings = app.settings;
pub const uia = platform.uia;

pub const version = "0.1.0";

test {
    _ = core;
    _ = platform;
    _ = gfx;
    _ = text;
    _ = theme;
    _ = layout;
    _ = input;
    _ = ui;
    _ = widgets;
    _ = app;
    _ = commands;
    _ = settings;
    _ = uia;
}
