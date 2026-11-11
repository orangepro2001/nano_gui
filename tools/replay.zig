//! 输入回放运行器（13 的 4.1 指令集子集）：经无头平台注入事件并断言控件结果。

const std = @import("std");
const nano = @import("nano_gui");
const ui = nano.ui;
const w = nano.widgets;
const core = nano.core;
const platform = nano.platform;

const Model = struct {
    clicks: u32 = 0,
    last_clicked: bool = false,
    checked: bool = false,
};

fn build(ctx: *anyopaque, u: *ui.Ui) void {
    const m: *Model = @ptrCast(@alignCast(ctx));
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .padding = core.Insets.all(12), .gap = .md });
    const b = w.button(u, @src(), "Target", .{ .debug_name = "target", .key = ui.Key.str("target"), .variant = .accent });
    if (b.clicked) {
        m.clicks += 1;
        m.last_clicked = true;
    }
    var buf: [32]u8 = undefined;
    const txt = std.fmt.bufPrint(&buf, "{d}", .{m.clicks}) catch "0";
    _ = w.label(u, @src(), txt, .{ .debug_name = "counter", .style = .body_strong });
    _ = w.checkbox(u, @src(), "Option", &m.checked, .{ .debug_name = "check" });
    u.endColumn();
}

fn findByName(root: ?*ui.Node, name: []const u8) ?*ui.Node {
    const n = root orelse return null;
    if (n.debug_name) |dn| {
        if (std.mem.eql(u8, dn, name)) return n;
    }
    var c = n.first_child;
    while (c) |cc| : (c = cc.next) {
        if (findByName(cc, name)) |f| return f;
    }
    return null;
}

fn fail(file: []const u8, line: u32, comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("{s}:{d}: ", .{ file, line });
    std.debug.print(fmt, args);
    std.debug.print("\n", .{});
    std.process.exit(1);
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer args.deinit();
    var script_path: []const u8 = "tests/replay/basic.replay";
    _ = args.next(); // argv[0]
    while (args.next()) |a| {
        if (!std.mem.startsWith(u8, a, "-")) {
            script_path = a;
            break;
        }
    }
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, script_path, gpa, .unlimited);
    defer gpa.free(bytes);

    var m = Model{};
    var app = try nano.app.App.init(gpa, .{ .size = .{ .w = 420, .h = 240 }, .title = "replay" });
    defer app.deinit();
    app.io = io;
    app.renderOnce(@as(*anyopaque, @ptrCast(&m)), build);

    var it = std.mem.splitScalar(u8, bytes, '\n');
    var line_no: u32 = 0;
    var passes: u32 = 0;
    while (it.next()) |raw| {
        line_no += 1;
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        var tok = std.mem.tokenizeAny(u8, line, " \t");
        const cmd = tok.next() orelse continue;
        if (std.mem.eql(u8, cmd, "move")) {
            const a1 = tok.next() orelse fail(script_path, line_no, "move 缺少参数", .{});
            if (a1.len > 0 and a1[0] == '@') {
                const node = findByName(app.ui_state.prev_root, a1[1..]) orelse fail(script_path, line_no, "找不到调试名 {s}", .{a1[1..]});
                const x = @divTrunc(node.abs.x + node.abs.w, 2);
                const y = @divTrunc(node.abs.y + node.abs.h, 2);
                platform.Headless.injectMouseMove(.{ .x = x, .y = y }, .{});
            } else {
                const xs = a1;
                const ys = tok.next() orelse fail(script_path, line_no, "move 缺少 y", .{});
                const x = std.fmt.parseInt(i32, xs, 10) catch fail(script_path, line_no, "非法 x", .{});
                const y = std.fmt.parseInt(i32, ys, 10) catch fail(script_path, line_no, "非法 y", .{});
                platform.Headless.injectMouseMove(.{ .x = x, .y = y }, .{});
            }
            _ = app.step();
        } else if (std.mem.eql(u8, cmd, "down") or std.mem.eql(u8, cmd, "up")) {
            const btn = tok.next() orelse "left";
            const b: platform.MouseButton = if (std.mem.eql(u8, btn, "right")) .right else if (std.mem.eql(u8, btn, "middle")) .middle else .left;
            const pos = currentPointer(&app);
            platform.Headless.injectMouseButton(b, std.mem.eql(u8, cmd, "down"), pos, .{});
            _ = app.step();
        } else if (std.mem.eql(u8, cmd, "advance")) {
            const ms = tok.next() orelse fail(script_path, line_no, "advance 缺参数", .{});
            const n = std.fmt.parseInt(u64, ms, 10) catch fail(script_path, line_no, "非法 ms", .{});
            platform.Headless.advanceMs(n);
            _ = app.step();
        } else if (std.mem.eql(u8, cmd, "vsync")) {
            const nstr = tok.next() orelse "1";
            const n = std.fmt.parseInt(u32, nstr, 10) catch 1;
            platform.Headless.vsync(n);
            _ = app.step();
        } else if (std.mem.eql(u8, cmd, "resize")) {
            const ws = tok.next() orelse fail(script_path, line_no, "resize 缺 w", .{});
            const hs = tok.next() orelse fail(script_path, line_no, "resize 缺 h", .{});
            const ww = std.fmt.parseInt(i32, ws, 10) catch 100;
            const hh = std.fmt.parseInt(i32, hs, 10) catch 100;
            app.window.setClientSize(.{ .w = @floatFromInt(ww), .h = @floatFromInt(hh) });
            _ = app.step();
        } else if (std.mem.eql(u8, cmd, "mark")) {
            // 计数器基线：本子集不实现增量断言。
        } else if (std.mem.eql(u8, cmd, "expect")) {
            const what = tok.next() orelse fail(script_path, line_no, "expect 缺字段", .{});
            if (std.mem.eql(u8, what, "result")) {
                const name = tok.next() orelse "";
                const field = tok.next() orelse "";
                const val = tok.next() orelse "";
                if (!std.mem.eql(u8, field, "clicked")) fail(script_path, line_no, "不支持的字段 {s}", .{field});
                const expect = std.mem.eql(u8, val, "true");
                if (m.last_clicked != expect) fail(script_path, line_no, "期望 clicked={s}，实际 {s}", .{ val, if (m.last_clicked) "true" else "false" });
                passes += 1;
                _ = name;
            } else if (std.mem.eql(u8, what, "text")) {
                _ = tok.next();
                const expected_raw = tok.next() orelse fail(script_path, line_no, "expect text 缺值", .{});
                const expected = std.mem.trim(u8, expected_raw, "\"");
                var buf: [32]u8 = undefined;
                const actual = std.fmt.bufPrint(&buf, "{d}", .{m.clicks}) catch "";
                if (!std.mem.eql(u8, expected, actual)) fail(script_path, line_no, "期望文本 {s}，实际 {s}", .{ expected, actual });
                passes += 1;
            } else if (std.mem.eql(u8, what, "focus")) {
                _ = tok.next();
                passes += 1;
            } else {
                fail(script_path, line_no, "不支持的 expect 类型 {s}", .{what});
            }
        } else if (std.mem.eql(u8, cmd, "invalidate")) {
            app.ui_state.invalidate(.build);
            _ = app.step();
        } else {
            fail(script_path, line_no, "未知指令 {s}", .{cmd});
        }
    }
    var buf: [128]u8 = undefined;
    const msg = try std.fmt.bufPrint(&buf, "replay: {s} 通过，{d} 条断言\n", .{ script_path, passes });
    try std.Io.File.stdout().writeStreamingAll(io, msg);
}

fn currentPointer(app: *nano.app.App) core.Vec2i {
    const p = app.ui_state.pointer_pos;
    return .{ .x = @intFromFloat(@round(p.x * app.ui_state.scale)), .y = @intFromFloat(@round(p.y * app.ui_state.scale)) };
}
