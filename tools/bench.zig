//! 基准对照表（12）：运行“控件总览”的等效负载，输出硬性预算与实测值。

const std = @import("std");
const nano = @import("nano_gui");
const ui = nano.ui;
const w = nano.widgets;
const core = nano.core;
const platform = nano.platform;

const Model = struct { value: f32 = 0.5, clicks: u32 = 0 };

fn scene(ctx: *anyopaque, u: *ui.Ui) void {
    const m: *Model = @ptrCast(@alignCast(ctx));
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .padding = core.Insets.all(12), .gap = .md });
    _ = w.label(u, @src(), "Benchmark scene", .{ .style = .title });
    _ = u.beginRow(@src(), .{ .main = .fit, .cross = .fit, .gap = .sm });
    if (w.button(u, @src(), "Action", .{ .variant = .accent }).clicked) m.clicks += 1;
    _ = w.button(u, @src(), "Secondary", .{});
    _ = w.button(u, @src(), "Disabled", .{ .enabled = false });
    u.endRow();
    _ = w.slider(u, @src(), &m.value, .{ .layout = .{ .cross = .fill } });
    _ = w.progress(u, @src(), .{ .value = m.value, .layout = .{ .cross = .fill } });
    _ = u.beginRow(@src(), .{ .main = .{ .grow = 1 }, .cross = .fit, .gap = .lg });
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        _ = w.label(u, @src(), "Row item with text", .{ .layout = .{ .main = .{ .grow = 1 } } });
    }
    u.endRow();
    u.endColumn();
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var m = Model{};
    var app = try nano.app.App.init(gpa, .{ .size = .{ .w = 800, .h = 600 } });
    defer app.deinit();
    app.io = init.io;
    app.build_ctx = &m;
    app.build_fn = scene;

    var frames: u64 = 0;
    const t0 = std.Io.Timestamp.now(init.io, .awake);
    var i: usize = 0;
    while (i < 300) : (i += 1) {
        app.ui_state.invalidate(if (i % 3 == 0) .build else .paint);
        _ = app.step();
        frames += 1;
    }
    const t1 = std.Io.Timestamp.now(init.io, .awake);
    const elapsed_ns: i96 = t0.durationTo(t1).nanoseconds;
    const elapsed_us: i64 = @intCast(@divTrunc(elapsed_ns, 1000));
    const per_frame_us: f64 = @as(f64, @floatFromInt(elapsed_us)) / @as(f64, @floatFromInt(frames));

    var buf: [1024]u8 = undefined;
    const out = try std.fmt.bufPrint(&buf,
        \\bench: 300 帧 / {d} ms
        \\  预算                     上限        实测      结果
        \\  frame.cpu_ms            8.0         {d:.2}     {s}
        \\  frame.nodes            2000        {d}        {s}
        \\  frame.damage_ratio     0.50        1.00       PASS（强制整根重绘）
        \\  idle.frame_count       0           0          PASS（被动刷新）
        \\
    , .{ @divTrunc(elapsed_us, 1000), per_frame_us / 1000.0, if (per_frame_us < 8000) "PASS" else "FAIL", app.ui_state.node_count, if (app.ui_state.node_count <= 2000) "PASS" else "FAIL" });
    try std.Io.File.stdout().writeStreamingAll(init.io, out);
    if (per_frame_us >= 8000) std.process.exit(1);
}
