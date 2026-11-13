//! M6 示例应用 ③：设置面板（分类导航 + 表单控件 + 对话框操作）。
//! 运行：zig build run-settings_panel

const std = @import("std");
const nano = @import("nano_gui");
const w = nano.widgets;
const ui = nano.ui;
const core = nano.core;

pub const Model = struct {
    category: usize = 0,
    username: w.TextBuf,
    font_size: i64 = 12,
    auto_save: bool = true,
    animations: bool = true,
    telemetry: bool = false,
    theme_choice: ?u32 = 0,
    density: u8 = 1,
    volume: f32 = 0.75,
    split_pos: nano.layout.SplitPos = .{ .fixed_first = 180 },
    status: []const u8 = "设置未修改",
    show_confirm: bool = false,
    revision: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) !Model {
        return .{ .username = try w.TextBuf.initFrom(allocator, "user") };
    }
    pub fn deinit(self: *Model) void {
        self.username.deinit();
    }
    pub fn changed(self: *Model) void {
        self.revision += 1;
    }
};

const CatListCtx = struct {
    fn text(_: ?*anyopaque, idx: usize) []const u8 {
        const items = [_][]const u8{ "常规", "外观与字体", "编辑与保存", "关于" };
        return if (idx < items.len) items[idx] else "";
    }
};

pub fn page(u: *ui.Ui, m: *Model) void {
    const t = u.theme_ptr;
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .padding = core.Insets.all(t.metric(.pad_panel)), .gap = .md });

    _ = w.label(u, @src(), "应用设置", .{ .style = .title });
    _ = w.separator(u, @src(), .{ .structural = true });

    const sp = w.beginSplitter(u, @src(), .{ .orientation = .horizontal, .pos = &m.split_pos, .layout = .{ .main = .{ .grow = 1 }, .cross = .fill } });
    var cat_list = w.beginList(u, @src(), 4, .{ .debug_name = "settings-cats", .data = .{ .ctx = null, .item_text = CatListCtx.text }, .layout = .{ .main = .{ .grow = 1 }, .cross = .fill } });
    while (cat_list.next()) |row| w.listLabel(u, @src(), row, CatListCtx.text(null, row.index), .{});
    const cres = w.endList(u, &cat_list);
    if (cres.focus_index) |fi| m.category = fi;

    _ = w.beginPanel(u, @src(), .{ .debug_name = "settings-form-panel", .layout = .{ .main = .{ .grow = 1 }, .cross = .fill } });
    _ = u.beginForm(@src(), .{ .cross = .fill, .gap = .sm }, .{});
    _ = w.label(u, @src(), "用户名", .{});
    if (w.textInput(u, @src(), &m.username, .{ .debug_name = "username-input", .layout = .{ .cross = .fill } }).changed) {
        m.status = "用户名已修改";
        m.changed();
    }
    _ = w.label(u, @src(), "主题模式", .{});
    if (w.comboBox(u, @src(), &m.theme_choice, .{ .slice = &.{ "跟随系统", "浅色 Instrument", "深色 Instrument" } }, .{ .debug_name = "theme-combo" }).changed) {
        m.status = "主题已切换";
        m.changed();
    }
    _ = w.label(u, @src(), "基准字号", .{});
    _ = w.spinBoxInt(u, @src(), &m.font_size, .{ .min = 10, .max = 24, .debug_name = "font-size-spin" });
    _ = w.label(u, @src(), "界面密度", .{});
    _ = w.beginRadioGroup(u, @src(), .{ .gap = .sm });
    _ = w.radio(u, @src(), "紧凑", &m.density, @as(u8, 0), .{});
    _ = w.radio(u, @src(), "标准", &m.density, @as(u8, 1), .{});
    _ = w.radio(u, @src(), "宽松", &m.density, @as(u8, 2), .{});
    w.endRadioGroup(u);
    _ = w.label(u, @src(), "提示音音量", .{});
    _ = w.slider(u, @src(), &m.volume, .{ .debug_name = "vol-slider" });
    _ = w.label(u, @src(), "自动保存", .{});
    _ = w.switchBox(u, @src(), "启用自动保存", &m.auto_save, .{});
    _ = w.label(u, @src(), "动画效果", .{});
    _ = w.checkbox(u, @src(), "启用过渡动画", &m.animations, .{});
    _ = w.label(u, @src(), "诊断日志", .{});
    _ = w.checkbox(u, @src(), "记录本地诊断指标", &m.telemetry, .{});
    u.endForm();
    _ = u.spacer(@src(), 1);
    const btns = [_]nano.app.DialogButton{
        .{ .label = "恢复默认", .code = 2, .role = .cancel },
        .{ .label = "应用并保存", .code = 1, .role = .default },
    };
    if (w.dialogButtons(u, @src(), &btns)) |code| {
        if (code == 1) {
            m.status = "设置已保存";
        } else {
            m.font_size = 12;
            m.auto_save = true;
            m.animations = true;
            m.density = 1;
            m.volume = 0.75;
            m.status = "已恢复默认设置";
        }
        m.changed();
    }
    w.endPanel(u);
    _ = w.endSplitter(u, sp);

    _ = w.separator(u, @src(), .{ .structural = true });
    _ = w.beginStatusBar(u, @src(), .{});
    _ = w.label(u, @src(), m.status, .{ .style = .small, .color = .secondary });
    w.endStatusBar(u);
    u.endColumn();
}

pub fn build(ctx: *anyopaque, u: *ui.Ui) void {
    const m: *Model = @ptrCast(@alignCast(ctx));
    page(u, m);
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var m = try Model.init(gpa);
    defer m.deinit();
    var app = try nano.app.App.init(gpa, .{ .title = "nano_gui Settings", .size = .{ .w = 820, .h = 560 } });
    defer app.deinit();
    app.renderOnce(&m, build);
    const out = try std.fmt.allocPrint(gpa, "settings_panel: frames={d} nodes={d}\n", .{ app.frames, app.ui_state.node_count });
    defer gpa.free(out);
    try std.Io.File.stdout().writeStreamingAll(init.io, out);
}
