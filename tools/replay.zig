//! 输入回放运行器（13 第 3.4 节与第 4.1 节）。
//! 流程：先完整解析脚本（REQ-TEST-013/014），再经无头平台注入事件逐条执行；
//! 断言一律读框架的真实状态，失败不中止，最后汇总（REQ-TEST-019）。

const std = @import("std");
const nano = @import("nano_gui");
const ui = nano.ui;
const w = nano.widgets;
const core = nano.core;
const platform = nano.platform;
const input = nano.input;

// ---------------------------------------------------------------------------
// 测试应用：模型与构建函数（不含旁路状态，控件状态一律从框架读取）
// ---------------------------------------------------------------------------

const Model = struct {
    clicks: u32 = 0,
    checked: bool = false,
    /// 模型钩子 `dup`：令构建函数产出重名节点，用于验证 REQ-TEST-015。
    dup: bool = false,
};

const Runner = struct {
    gpa: std.mem.Allocator,
    file: []const u8,
    app: *nano.app.App,
    model: Model = .{},
    passed: u32 = 0,
    failed: u32 = 0,
    cur_line: u32 = 0,
    /// 当前鼠标位置（ppx）。
    pointer: core.Vec2i = .{},
    mods: platform.Mods = .{},
    /// 每个构建遍的调试名节点快照（下标 0/1 对应第 1/2 遍）。
    snaps: [2]std.ArrayListUnmanaged(Snap) = .{ .empty, .empty },
    pass_count: u8 = 0,
    dups: std.ArrayListUnmanaged(Dup) = .empty,
    /// 已报告过的重名调试名（每个名字只报一次）。
    dups_reported: std.ArrayListUnmanaged([]const u8) = .empty,
    timer_reported: bool = false,
    /// mark 基线；null 表示从未 mark。
    baseline: ?[]core.stats.Entry = null,
    /// 脏标记未清除的告警只报一次。
    storm_reported: bool = false,
};

const Snap = struct {
    name: []const u8,
    it: input.Interaction,
};

const Dup = struct {
    name: []const u8,
    a_file: []const u8,
    a_line: u32,
    b_file: []const u8,
    b_line: u32,
};

fn build(ctx: *anyopaque, u: *ui.Ui) void {
    const r: *Runner = @ptrCast(@alignCast(ctx));
    buildApp(r, u);
    collectSnapshot(r, u);
}

fn buildApp(r: *Runner, u: *ui.Ui) void {
    const m = &r.model;
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .padding = core.Insets.all(12), .gap = .md });
    const b = w.button(u, @src(), "Target", .{ .debug_name = "target", .key = ui.Key.str("target"), .variant = .accent });
    if (b.clicked) m.clicks += 1;
    var buf: [32]u8 = undefined;
    const txt = std.fmt.bufPrint(&buf, "{d}", .{m.clicks}) catch "0";
    // 文本缓冲在帧竞技场内复制，避免节点属性引用栈内存。
    const txt_dup = u.frameAlloc().dupe(u8, txt) catch "?";
    _ = w.label(u, @src(), txt_dup, .{ .debug_name = "counter", .style = .body_strong });
    _ = w.checkbox(u, @src(), "Option", &m.checked, .{ .debug_name = "check" });
    if (m.dup) {
        _ = w.label(u, @src(), "dup", .{ .debug_name = "counter", .key = ui.Key.str("dup") });
    }
    u.endColumn();
}

/// 每个构建遍结束时记录带调试名节点的交互快照，并检测同遍重名（REQ-TEST-015）。
fn collectSnapshot(r: *Runner, u: *ui.Ui) void {
    if (u.pass == 1) {
        r.snaps[0].clearRetainingCapacity();
        r.snaps[1].clearRetainingCapacity();
        // 重名只依据当前构建（REQ-TEST-015），每次构建重新判定。
        r.dups.clearRetainingCapacity();
    }
    if (u.pass < 1 or u.pass > 2) return;
    const idx: usize = u.pass - 1;
    r.pass_count = u.pass;
    for (u.roots.items) |root| walkSnap(r, idx, root);
}

fn walkSnap(r: *Runner, idx: usize, node: *ui.Node) void {
    if (node.debug_name) |dn| {
        var dup_of: ?Snap = null;
        for (r.snaps[idx].items) |s| {
            if (std.mem.eql(u8, s.name, dn)) dup_of = s;
        }
        if (dup_of != null) {
            recordDup(r, dn, node);
        } else {
            r.snaps[idx].append(r.gpa, .{ .name = dn, .it = node.interaction }) catch {};
        }
    }
    var c = node.first_child;
    while (c) |cc| : (c = cc.next) walkSnap(r, idx, cc);
}

fn recordDup(r: *Runner, name: []const u8, second: *ui.Node) void {
    for (r.dups.items) |d| if (std.mem.eql(u8, d.name, name)) return;
    // 找到先出现者的调用点。
    var first_file: []const u8 = "?";
    var first_line: u32 = 0;
    for (r.app.ui_state.roots.items) |root| {
        if (findFirst(root, name, second)) |f| {
            first_file = f.src_file;
            first_line = f.src_line;
            break;
        }
    }
    r.dups.append(r.gpa, .{ .name = name, .a_file = first_file, .a_line = first_line, .b_file = second.src_file, .b_line = second.src_line }) catch {};
}

fn findFirst(node: *ui.Node, name: []const u8, skip: *ui.Node) ?*ui.Node {
    if (node != skip) {
        if (node.debug_name) |dn| {
            if (std.mem.eql(u8, dn, name)) return node;
        }
    }
    var c = node.first_child;
    while (c) |cc| : (c = cc.next) {
        if (findFirst(cc, name, skip)) |f| return f;
    }
    return null;
}

// ---------------------------------------------------------------------------
// 指令与解析
// ---------------------------------------------------------------------------

const Cmp = enum { eq, ne, lt, le, gt, ge };

const Target = union(enum) {
    point: struct { x: f32, y: f32 },
    name: []const u8,
};

const SettingVal = union(enum) {
    int: u32,
    size: [2]i32,
    scroll: platform.ScrollAmount,
    opt_int: ?u32,
    flag: bool,
    color: core.Color,
    sys_color: struct { c: platform.SysColor, v: core.Color },
    scale: f32,
};

const VisualField = enum { hovered, pressed, focused_visible, disabled };

const Cmd = union(enum) {
    move: Target,
    down: platform.MouseButton,
    up: platform.MouseButton,
    wheel: f32,
    key_down: platform.VirtualKey,
    key_up: platform.VirtualKey,
    key_repeat: struct { vk: platform.VirtualKey, n: u32 },
    text: []const u8,
    ime_start,
    ime_update: struct { text: []const u8, cursor: usize },
    ime_commit: []const u8,
    ime_cancel,
    ole,
    resize: struct { w: f32, h: f32 },
    show: bool,
    activate: bool,
    window,
    close,
    dpi: u32,
    setting: struct { name: []const u8, val: SettingVal },
    invalidate: struct { level: ui.Dirty, target: ?[]const u8 },
    model: struct { name: []const u8, value: []const u8 },
    advance: u64,
    vsync: u32,
    mark,
    expect_counter: struct { name: []const u8, op: Cmp, value: i64 },
    expect_golden,
    expect_focus: ?[]const u8,
    expect_visual: struct { name: []const u8, field: VisualField, value: bool },
    expect_rect: struct { name: []const u8, x: f32, y: f32, w: f32, h: f32 },
    expect_text: struct { name: []const u8, text: []const u8 },
    expect_damage: struct { op: Cmp, area: ?i64, name: ?[]const u8 },
    expect_cursor: platform.CursorShape,
    expect_popup,
    expect_captured: ?[]const u8,
    expect_timers: u32,
    expect_result: struct { name: []const u8, field: []const u8, value: []const u8, pass: ?u8 },
};

const Step = struct { line: u32, cmd: Cmd };

const Tok = struct { text: []const u8, quoted: bool };

const ParseError = error{ Syntax, OutOfMemory };

/// 解析上下文：错误信息写入 msg。
const PCtx = struct {
    arena: std.mem.Allocator,
    toks: []const Tok = &.{},
    i: usize = 0,
    msg: []const u8 = "",

    fn bad(self: *PCtx, comptime fmt: []const u8, args: anytype) ParseError {
        self.msg = std.fmt.allocPrint(self.arena, fmt, args) catch "语法错误";
        return error.Syntax;
    }
    fn peek(self: *PCtx) ?Tok {
        if (self.i >= self.toks.len) return null;
        return self.toks[self.i];
    }
    fn next(self: *PCtx, what: []const u8) ParseError!Tok {
        if (self.i >= self.toks.len) return self.bad("缺少参数：{s}", .{what});
        defer self.i += 1;
        return self.toks[self.i];
    }
    fn word(self: *PCtx, what: []const u8) ParseError![]const u8 {
        const t = try self.next(what);
        if (t.quoted) return self.bad("{s} 不应为带引号字符串", .{what});
        return t.text;
    }
    fn str(self: *PCtx, what: []const u8) ParseError![]const u8 {
        const t = try self.next(what);
        if (!t.quoted) return self.bad("{s} 必须是带双引号的字符串", .{what});
        return t.text;
    }
    fn end(self: *PCtx) ParseError!void {
        if (self.i < self.toks.len) return self.bad("多余的参数：{s}", .{self.toks[self.i].text});
    }
    fn name(self: *PCtx, what: []const u8) ParseError![]const u8 {
        const t = try self.word(what);
        if (t.len < 2 or t[0] != '@') return self.bad("{s} 必须写作 @调试名", .{what});
        return t[1..];
    }
    fn int(self: *PCtx, comptime T: type, what: []const u8) ParseError!T {
        const t = try self.word(what);
        return std.fmt.parseInt(T, t, 10) catch self.bad("{s} 不是合法整数：{s}", .{ what, t });
    }
    fn float(self: *PCtx, what: []const u8) ParseError!f32 {
        const t = try self.word(what);
        return std.fmt.parseFloat(f32, t) catch self.bad("{s} 不是合法数值：{s}", .{ what, t });
    }
    fn boolean(self: *PCtx, what: []const u8) ParseError!bool {
        const t = try self.word(what);
        if (std.mem.eql(u8, t, "on") or std.mem.eql(u8, t, "true")) return true;
        if (std.mem.eql(u8, t, "off") or std.mem.eql(u8, t, "false")) return false;
        return self.bad("{s} 应为 on|off（或 true|false）：{s}", .{ what, t });
    }
    fn color(self: *PCtx, what: []const u8) ParseError!core.Color {
        const t = try self.word(what);
        if (t.len != 7 or t[0] != '#') return self.bad("{s} 应为 #RRGGBB：{s}", .{ what, t });
        const v = std.fmt.parseInt(u32, t[1..], 16) catch return self.bad("{s} 应为 #RRGGBB：{s}", .{ what, t });
        return core.Color.fromHex(v, 255);
    }
};

/// 切分一行为词元；双引号字符串内支持 \" \\ \n \u{hex}（13 的 `text` 指令）。
fn tokenize(p: *PCtx, line: []const u8) ParseError![]const Tok {
    var out = std.ArrayListUnmanaged(Tok).empty;
    var i: usize = 0;
    while (i < line.len) {
        const ch = line[i];
        if (ch == ' ' or ch == '\t') {
            i += 1;
            continue;
        }
        if (ch == '"') {
            i += 1;
            var buf = std.ArrayListUnmanaged(u8).empty;
            var closed = false;
            while (i < line.len) {
                const c = line[i];
                if (c == '"') {
                    closed = true;
                    i += 1;
                    break;
                }
                if (c == '\\') {
                    i += 1;
                    if (i >= line.len) return p.bad("字符串末尾的转义不完整", .{});
                    const e = line[i];
                    i += 1;
                    switch (e) {
                        '"' => try buf.append(p.arena, '"'),
                        '\\' => try buf.append(p.arena, '\\'),
                        'n' => try buf.append(p.arena, '\n'),
                        'u' => {
                            if (i >= line.len or line[i] != '{') return p.bad("\\u 后应为 {{十六进制}}", .{});
                            const close = std.mem.indexOfScalarPos(u8, line, i, '}') orelse return p.bad("\\u{{ 缺少 }}", .{});
                            const cp = std.fmt.parseInt(u21, line[i + 1 .. close], 16) catch return p.bad("\\u{{}} 内不是合法码点", .{});
                            var tmp: [4]u8 = undefined;
                            const n = std.unicode.utf8Encode(cp, &tmp) catch return p.bad("\\u{{}} 码点不是合法 Unicode 标量", .{});
                            try buf.appendSlice(p.arena, tmp[0..n]);
                            i = close + 1;
                        },
                        else => return p.bad("不支持的转义 \\{c}", .{e}),
                    }
                    continue;
                }
                try buf.append(p.arena, c);
                i += 1;
            }
            if (!closed) return p.bad("字符串缺少结束的双引号", .{});
            if (i < line.len and line[i] != ' ' and line[i] != '\t') return p.bad("字符串后应有空白", .{});
            try out.append(p.arena, .{ .text = buf.items, .quoted = true });
            continue;
        }
        const start = i;
        while (i < line.len and line[i] != ' ' and line[i] != '\t') : (i += 1) {
            if (line[i] == '"') return p.bad("引号只能出现在词元开头", .{});
        }
        try out.append(p.arena, .{ .text = line[start..i], .quoted = false });
    }
    return out.items;
}

fn parseMouseButton(p: *PCtx) ParseError!platform.MouseButton {
    const t = try p.word("鼠标键");
    if (std.mem.eql(u8, t, "left")) return .left;
    if (std.mem.eql(u8, t, "right")) return .right;
    if (std.mem.eql(u8, t, "middle")) return .middle;
    return p.bad("鼠标键应为 left|right|middle：{s}", .{t});
}

fn parseVk(p: *PCtx) ParseError!platform.VirtualKey {
    const t = try p.word("VK_*");
    if (!std.mem.startsWith(u8, t, "VK_")) return p.bad("虚拟键应写作 VK_*：{s}", .{t});
    const raw = t[3..];
    var lower_buf: [32]u8 = undefined;
    if (raw.len == 0 or raw.len > lower_buf.len) return p.bad("未知虚拟键：{s}", .{t});
    const lower = std.ascii.lowerString(&lower_buf, raw);
    const aliases = [_][2][]const u8{
        .{ "return", "enter" },       .{ "back", "backspace" },        .{ "prior", "page_up" },
        .{ "next", "page_down" },     .{ "control", "ctrl" },          .{ "menu", "alt" },
        .{ "capital", "caps_lock" },  .{ "snapshot", "print_screen" }, .{ "numpad0", "np0" },
        .{ "numpad1", "np1" },        .{ "numpad2", "np2" },           .{ "numpad3", "np3" },
        .{ "numpad4", "np4" },        .{ "numpad5", "np5" },           .{ "numpad6", "np6" },
        .{ "numpad7", "np7" },        .{ "numpad8", "np8" },           .{ "numpad9", "np9" },
        .{ "multiply", "np_mul" },    .{ "add", "np_add" },            .{ "subtract", "np_sub" },
        .{ "decimal", "np_decimal" }, .{ "divide", "np_div" },
    };
    var key_name: []const u8 = lower;
    for (aliases) |a| {
        if (std.mem.eql(u8, lower, a[0])) key_name = a[1];
    }
    var digit_buf: [3]u8 = undefined;
    if (key_name.len == 1 and key_name[0] >= '0' and key_name[0] <= '9') {
        digit_buf = .{ 'n', key_name[0], 0 };
        key_name = digit_buf[0..2];
    }
    return std.meta.stringToEnum(platform.VirtualKey, key_name) orelse p.bad("未知虚拟键：{s}", .{t});
}

fn parseCmp(p: *PCtx) ParseError!Cmp {
    const t = try p.word("运算符");
    if (std.mem.eql(u8, t, "==")) return .eq;
    if (std.mem.eql(u8, t, "!=")) return .ne;
    if (std.mem.eql(u8, t, "<")) return .lt;
    if (std.mem.eql(u8, t, "<=")) return .le;
    if (std.mem.eql(u8, t, ">")) return .gt;
    if (std.mem.eql(u8, t, ">=")) return .ge;
    return p.bad("运算符应为 == != < <= > >=：{s}", .{t});
}

fn interactionHasField(name: []const u8) bool {
    inline for (@typeInfo(input.Interaction).@"struct".field_names) |fname| {
        if (std.mem.eql(u8, fname, name)) return true;
    }
    return false;
}

fn parseSetting(p: *PCtx) ParseError!Cmd {
    const name = try p.word("字段名");
    const Kind = enum { int, size, scroll, opt_int, flag, color, sys_color, scale };
    const table = [_]struct { []const u8, Kind }{
        .{ "double_click_ms", .int },        .{ "double_click_size", .size },
        .{ "drag_size", .size },             .{ "wheel_lines", .scroll },
        .{ "wheel_chars", .scroll },         .{ "menu_show_delay_ms", .int },
        .{ "hover_time_ms", .int },          .{ "hover_size", .size },
        .{ "caret_blink_ms", .opt_int },     .{ "key_repeat_delay_ms", .int },
        .{ "key_repeat_interval_ms", .int }, .{ "keyboard_cues", .flag },
        .{ "client_animation", .flag },      .{ "menu_animation", .flag },
        .{ "menu_fade", .flag },             .{ "apps_dark", .flag },
        .{ "accent", .color },               .{ "high_contrast", .flag },
        .{ "sys_colors", .sys_color },       .{ "text_scale", .scale },
    };
    var kind: ?Kind = null;
    for (table) |e| if (std.mem.eql(u8, e[0], name)) {
        kind = e[1];
    };
    const k = kind orelse return p.bad("未知的 setting 字段：{s}", .{name});
    const val: SettingVal = switch (k) {
        .int => .{ .int = try p.int(u32, "值") },
        .size => .{ .size = .{ try p.int(i32, "W"), try p.int(i32, "H") } },
        .scroll => blk: {
            const t = try p.word("值");
            if (std.mem.eql(u8, t, "page")) break :blk .{ .scroll = .page };
            const n = std.fmt.parseInt(u32, t, 10) catch return p.bad("值应为整数或 page：{s}", .{t});
            break :blk .{ .scroll = .{ .lines = n } };
        },
        .opt_int => blk: {
            const t = try p.word("值");
            if (std.mem.eql(u8, t, "none")) break :blk .{ .opt_int = null };
            const n = std.fmt.parseInt(u32, t, 10) catch return p.bad("值应为整数或 none：{s}", .{t});
            break :blk .{ .opt_int = n };
        },
        .flag => .{ .flag = try p.boolean("值") },
        .color => .{ .color = try p.color("值") },
        .sys_color => blk: {
            const cn = try p.word("SysColor 成员名");
            const c = std.meta.stringToEnum(platform.SysColor, cn) orelse return p.bad("未知 SysColor 成员：{s}", .{cn});
            break :blk .{ .sys_color = .{ .c = c, .v = try p.color("颜色") } };
        },
        .scale => .{ .scale = try p.float("值") },
    };
    return .{ .setting = .{ .name = name, .val = val } };
}

fn parseExpect(p: *PCtx) ParseError!Cmd {
    const what = try p.word("expect 类型");
    if (std.mem.eql(u8, what, "counter")) {
        const name = try p.word("计数器名");
        const op = try parseCmp(p);
        const v = try p.int(i64, "值");
        return .{ .expect_counter = .{ .name = name, .op = op, .value = v } };
    }
    if (std.mem.eql(u8, what, "golden")) {
        _ = try p.word("用例路径");
        return .expect_golden;
    }
    if (std.mem.eql(u8, what, "focus")) {
        const t = try p.word("@调试名|none");
        if (std.mem.eql(u8, t, "none")) return .{ .expect_focus = null };
        if (t.len < 2 or t[0] != '@') return p.bad("应为 @调试名 或 none：{s}", .{t});
        return .{ .expect_focus = t[1..] };
    }
    if (std.mem.eql(u8, what, "visual")) {
        const name = try p.name("@调试名");
        const fname = try p.word("视觉字段");
        const field = std.meta.stringToEnum(VisualField, fname) orelse return p.bad("视觉字段应为 hovered|pressed|focused_visible|disabled：{s}", .{fname});
        const v = try p.boolean("true|false");
        return .{ .expect_visual = .{ .name = name, .field = field, .value = v } };
    }
    if (std.mem.eql(u8, what, "rect")) {
        const name = try p.name("@调试名");
        return .{ .expect_rect = .{ .name = name, .x = try p.float("x"), .y = try p.float("y"), .w = try p.float("w"), .h = try p.float("h") } };
    }
    if (std.mem.eql(u8, what, "text")) {
        const name = try p.name("@调试名");
        return .{ .expect_text = .{ .name = name, .text = try p.str("文本") } };
    }
    if (std.mem.eql(u8, what, "damage")) {
        const op = try parseCmp(p);
        const t = try p.word("面积|@调试名");
        if (t.len >= 2 and t[0] == '@') return .{ .expect_damage = .{ .op = op, .area = null, .name = t[1..] } };
        const a = std.fmt.parseInt(i64, t, 10) catch return p.bad("面积应为整数或 @调试名：{s}", .{t});
        return .{ .expect_damage = .{ .op = op, .area = a, .name = null } };
    }
    if (std.mem.eql(u8, what, "cursor")) {
        const t = try p.word("形状");
        const s = std.meta.stringToEnum(platform.CursorShape, t) orelse return p.bad("未知光标形状：{s}", .{t});
        return .{ .expect_cursor = s };
    }
    if (std.mem.eql(u8, what, "popup")) {
        // 两种形式都先校验形状，执行时判为未实现。
        const t = try p.word("数量|@调试名");
        if (t.len >= 2 and t[0] == '@') {
            const e = try p.word("存在|不存在");
            if (!std.mem.eql(u8, e, "存在") and !std.mem.eql(u8, e, "不存在")) return p.bad("应为 存在|不存在：{s}", .{e});
        } else {
            _ = std.fmt.parseInt(u32, t, 10) catch return p.bad("数量应为整数：{s}", .{t});
        }
        return .expect_popup;
    }
    if (std.mem.eql(u8, what, "captured")) {
        const t = try p.word("@调试名|none");
        if (std.mem.eql(u8, t, "none")) return .{ .expect_captured = null };
        if (t.len < 2 or t[0] != '@') return p.bad("应为 @调试名 或 none：{s}", .{t});
        return .{ .expect_captured = t[1..] };
    }
    if (std.mem.eql(u8, what, "timers")) {
        return .{ .expect_timers = try p.int(u32, "数量") };
    }
    if (std.mem.eql(u8, what, "result")) {
        const name = try p.name("@调试名");
        const field = try p.word("字段");
        if (!interactionHasField(field)) return p.bad("字段不属于 Interaction：{s}", .{field});
        const value = try p.word("值");
        var pass: ?u8 = null;
        if (p.peek()) |t| {
            if (!t.quoted and std.mem.eql(u8, t.text, "pass")) {
                p.i += 1;
                const n = try p.int(u8, "遍号");
                if (n != 1 and n != 2) return p.bad("pass 应为 1 或 2", .{});
                pass = n;
            }
        }
        return .{ .expect_result = .{ .name = name, .field = field, .value = value, .pass = pass } };
    }
    return p.bad("未知的 expect 类型：{s}", .{what});
}

fn parseLine(p: *PCtx) ParseError!Cmd {
    const cmd = try p.word("指令");
    const eql = std.mem.eql;
    if (eql(u8, cmd, "move")) {
        const t = try p.word("x 或 @调试名");
        if (t.len >= 2 and t[0] == '@') return .{ .move = .{ .name = t[1..] } };
        const x = std.fmt.parseFloat(f32, t) catch return p.bad("x 不是合法数值：{s}", .{t});
        return .{ .move = .{ .point = .{ .x = x, .y = try p.float("y") } } };
    }
    if (eql(u8, cmd, "down")) return .{ .down = try parseMouseButton(p) };
    if (eql(u8, cmd, "up")) return .{ .up = try parseMouseButton(p) };
    if (eql(u8, cmd, "wheel")) return .{ .wheel = try p.float("dy") };
    if (eql(u8, cmd, "key")) {
        const sub = try p.word("down|up|repeat");
        if (eql(u8, sub, "down")) return .{ .key_down = try parseVk(p) };
        if (eql(u8, sub, "up")) return .{ .key_up = try parseVk(p) };
        if (eql(u8, sub, "repeat")) {
            const vk = try parseVk(p);
            var n: u32 = 1;
            if (p.peek() != null) n = try p.int(u32, "次数");
            return .{ .key_repeat = .{ .vk = vk, .n = n } };
        }
        return p.bad("key 子指令应为 down|up|repeat：{s}", .{sub});
    }
    if (eql(u8, cmd, "text")) return .{ .text = try p.str("文本") };
    if (eql(u8, cmd, "ime")) {
        const sub = try p.word("子指令");
        if (eql(u8, sub, "start")) return .ime_start;
        if (eql(u8, sub, "cancel")) return .ime_cancel;
        if (eql(u8, sub, "commit")) return .{ .ime_commit = try p.str("文本") };
        if (eql(u8, sub, "update")) {
            const t = try p.str("文本");
            return .{ .ime_update = .{ .text = t, .cursor = try p.int(usize, "光标") } };
        }
        return p.bad("ime 子指令应为 start|update|commit|cancel：{s}", .{sub});
    }
    if (eql(u8, cmd, "ole")) {
        const sub = try p.word("子指令");
        if (eql(u8, sub, "enter")) {
            _ = try p.str("路径");
            while (p.peek() != null) _ = try p.str("路径");
            return .ole;
        }
        if (eql(u8, sub, "over")) {
            _ = try p.float("x");
            _ = try p.float("y");
            return .ole;
        }
        if (eql(u8, sub, "leave") or eql(u8, sub, "drop")) return .ole;
        return p.bad("ole 子指令应为 enter|over|leave|drop：{s}", .{sub});
    }
    if (eql(u8, cmd, "resize")) return .{ .resize = .{ .w = try p.float("w"), .h = try p.float("h") } };
    if (eql(u8, cmd, "show")) return .{ .show = try p.boolean("on|off") };
    if (eql(u8, cmd, "activate")) return .{ .activate = try p.boolean("on|off") };
    if (eql(u8, cmd, "window")) {
        const t = try p.word("main|@调试名");
        if (!eql(u8, t, "main") and !(t.len >= 2 and t[0] == '@')) return p.bad("应为 main 或 @调试名：{s}", .{t});
        return .window;
    }
    if (eql(u8, cmd, "close")) return .close;
    if (eql(u8, cmd, "dpi")) return .{ .dpi = try p.int(u32, "N") };
    if (eql(u8, cmd, "setting")) return parseSetting(p);
    if (eql(u8, cmd, "invalidate")) {
        const lv = try p.word("paint|layout|build");
        const level: ui.Dirty = if (eql(u8, lv, "paint")) .paint else if (eql(u8, lv, "layout")) .layout else if (eql(u8, lv, "build")) .build else return p.bad("级别应为 paint|layout|build：{s}", .{lv});
        var target: ?[]const u8 = null;
        if (p.peek() != null) target = try p.name("@调试名");
        return .{ .invalidate = .{ .level = level, .target = target } };
    }
    if (eql(u8, cmd, "model")) {
        const name = try p.word("名字");
        const t = try p.next("值");
        return .{ .model = .{ .name = name, .value = t.text } };
    }
    if (eql(u8, cmd, "advance")) return .{ .advance = try p.int(u64, "ms") };
    if (eql(u8, cmd, "vsync")) return .{ .vsync = try p.int(u32, "n") };
    if (eql(u8, cmd, "mark")) return .mark;
    if (eql(u8, cmd, "expect")) return parseExpect(p);
    return p.bad("未知指令：{s}", .{cmd});
}

/// 完整解析脚本；返回错误数。错误已按 文件:行 输出。
fn parseScript(arena: std.mem.Allocator, file: []const u8, src: []const u8, steps: *std.ArrayListUnmanaged(Step)) usize {
    var errors: usize = 0;
    var it = std.mem.splitScalar(u8, src, '\n');
    var line_no: u32 = 0;
    while (it.next()) |raw| {
        line_no += 1;
        if (!std.unicode.utf8ValidateSlice(raw)) {
            std.debug.print("{s}:{d}: 解析失败：非法 UTF-8\n", .{ file, line_no });
            errors += 1;
            continue;
        }
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        var p = PCtx{ .arena = arena };
        const result: ParseError!Cmd = blk: {
            p.toks = tokenize(&p, line) catch |e| break :blk e;
            const c = parseLine(&p) catch |e| break :blk e;
            p.end() catch |e| break :blk e;
            break :blk c;
        };
        if (result) |c| {
            steps.append(arena, .{ .line = line_no, .cmd = c }) catch {
                errors += 1;
            };
        } else |_| {
            std.debug.print("{s}:{d}: 解析失败：{s}\n", .{ file, line_no, p.msg });
            errors += 1;
        }
    }
    return errors;
}

// ---------------------------------------------------------------------------
// 执行
// ---------------------------------------------------------------------------

fn pass_(r: *Runner) void {
    r.passed += 1;
}

fn fail(r: *Runner, comptime fmt: []const u8, args: anytype) void {
    std.debug.print("{s}:{d}: ", .{ r.file, r.cur_line });
    std.debug.print(fmt, args);
    std.debug.print("\n", .{});
    r.failed += 1;
}

fn unimplemented(r: *Runner, what: []const u8, dep: []const u8) void {
    fail(r, "未实现：{s}（依赖 {s}）", .{ what, dep });
}

const Found = union(enum) { node: *ui.Node, missing, duplicate: Dup };

fn findNode(r: *Runner, name: []const u8) Found {
    for (r.dups.items) |d| if (std.mem.eql(u8, d.name, name)) return .{ .duplicate = d };
    for (r.app.ui_state.roots.items) |root| {
        if (findByName(root, name)) |n| return .{ .node = n };
    }
    return .missing;
}

fn findByName(node: *ui.Node, name: []const u8) ?*ui.Node {
    if (node.debug_name) |dn| {
        if (std.mem.eql(u8, dn, name)) return node;
    }
    var c = node.first_child;
    while (c) |cc| : (c = cc.next) {
        if (findByName(cc, name)) |f| return f;
    }
    return null;
}

/// 取节点；找不到或重名时记失败并返回 null（REQ-TEST-015）。
fn needNode(r: *Runner, name: []const u8) ?*ui.Node {
    switch (findNode(r, name)) {
        .node => |n| return n,
        .missing => fail(r, "找不到调试名 @{s}", .{name}),
        .duplicate => |d| fail(r, "调试名 @{s} 在同一构建遍内重复：{s}:{d} 与 {s}:{d}", .{ d.name, d.a_file, d.a_line, d.b_file, d.b_line }),
    }
    return null;
}

/// 报告尚未报告的重名。同一重名持续存在时只报告一次；重名消失后再次出现会重新报告（REQ-TEST-015）。
fn reportDups(r: *Runner) void {
    // 先剔除当前构建中已不再重名的名字。
    var k: usize = 0;
    while (k < r.dups_reported.items.len) {
        var still = false;
        for (r.dups.items) |d| {
            if (std.mem.eql(u8, d.name, r.dups_reported.items[k])) still = true;
        }
        if (still) k += 1 else _ = r.dups_reported.swapRemove(k);
    }
    for (r.dups.items) |d| {
        var seen = false;
        for (r.dups_reported.items) |n| {
            if (std.mem.eql(u8, n, d.name)) seen = true;
        }
        if (seen) continue;
        r.dups_reported.append(r.gpa, d.name) catch {
            fail(r, "内部错误：记录已报告重名时内存不足", .{});
            return;
        };
        fail(r, "调试名 @{s} 在同一构建遍内重复：{s}:{d} 与 {s}:{d}", .{ d.name, d.a_file, d.a_line, d.b_file, d.b_line });
    }
}

/// 驱动主循环直到无脏标记（REQ-TEST-016 第三条）。
/// force_first 为真时无条件先跑一帧以消费已注入的事件。
fn drive(r: *Runner, force_first: bool) void {
    const u = &r.app.ui_state;
    if (force_first) _ = r.app.step();
    var n: u32 = 0;
    while (u.dirty != .none and n < 64) : (n += 1) _ = r.app.step();
    if (u.dirty != .none and !r.storm_reported) {
        r.storm_reported = true;
        fail(r, "主循环 64 帧后仍有脏标记 {s}（失效风暴或脏标记未清除）", .{@tagName(u.dirty)});
    }
    reportDups(r);
}

fn nextTimerBetween(u: *const ui.Ui, after: u64, upto: u64) ?u64 {
    var best: ?u64 = null;
    var it = u.timers.valueIterator();
    while (it.next()) |t| {
        if (t.touched + 2 <= u.build_counter) continue;
        if (t.next_ms <= after or t.next_ms > upto) continue;
        if (best == null or t.next_ms < best.?) best = t.next_ms;
    }
    return best;
}

/// 推进假时钟至 target，逐个到期时刻停下并运行至无脏标记。
fn advanceTo(r: *Runner, target: u64) void {
    const u = &r.app.ui_state;
    var cursor = platform.nowMs();
    while (nextTimerBetween(u, cursor, target)) |t| {
        platform.Headless.advanceMs(t - platform.nowMs());
        cursor = t;
        // 不在运行器内替框架置脏：只有框架自己置了脏标记才会出帧（FRAME-050）。
        if (u.dirty != .none) {
            drive(r, false);
        } else if (!r.timer_reported) {
            // 定时器已到期但框架没有置脏：运行器不替框架置脏，如实失败（每脚本一次）。
            r.timer_reported = true;
            unimplemented(r, "定时器到期置脏", "06 REQ-FRAME-050 在 ui.zig 的实现");
        }
    }
    platform.Headless.advanceMs(target - platform.nowMs());
}

fn cmpOk(op: Cmp, a: i64, b: i64) bool {
    return switch (op) {
        .eq => a == b,
        .ne => a != b,
        .lt => a < b,
        .le => a <= b,
        .gt => a > b,
        .ge => a >= b,
    };
}

fn cmpStr(op: Cmp) []const u8 {
    return switch (op) {
        .eq => "==",
        .ne => "!=",
        .lt => "<",
        .le => "<=",
        .gt => ">",
        .ge => ">=",
    };
}

fn fmtField(buf: []u8, comptime T: type, v: T) []const u8 {
    const ti = @typeInfo(T);
    switch (ti) {
        .bool => return if (v) "true" else "false",
        .int => return std.fmt.bufPrint(buf, "{d}", .{v}) catch "?",
        .@"enum" => return @tagName(v),
        .optional => |o| {
            const val = v orelse return "none";
            if (@typeInfo(o.child) == .@"enum") return @tagName(val);
            return "some";
        },
        else => return "(不支持比较的字段类型)",
    }
}

fn fieldString(buf: []u8, it: input.Interaction, field: []const u8) []const u8 {
    const info = @typeInfo(input.Interaction).@"struct";
    inline for (info.field_names, info.field_types) |fname, ftype| {
        if (std.mem.eql(u8, fname, field)) return fmtField(buf, ftype, @field(it, fname));
    }
    return "(无此字段)";
}

fn applySetting(r: *Runner, s: anytype) void {
    var a = platform.appearance(r.app.window);
    const eql = std.mem.eql;
    const n = s.name;
    switch (s.val) {
        .int => |v| {
            if (eql(u8, n, "double_click_ms")) a.metrics.double_click_ms = v;
            if (eql(u8, n, "menu_show_delay_ms")) a.metrics.menu_show_delay_ms = v;
            if (eql(u8, n, "hover_time_ms")) a.metrics.hover_time_ms = v;
            if (eql(u8, n, "key_repeat_delay_ms")) {
                unimplemented(r, "setting key_repeat_delay_ms", "SystemMetrics 中尚无该字段");
                return;
            }
            if (eql(u8, n, "key_repeat_interval_ms")) {
                unimplemented(r, "setting key_repeat_interval_ms", "SystemMetrics 中尚无该字段");
                return;
            }
        },
        .size => |v| {
            const sz = core.Size2i{ .w = v[0], .h = v[1] };
            if (eql(u8, n, "double_click_size")) a.metrics.double_click_size = sz;
            if (eql(u8, n, "drag_size")) a.metrics.drag_size = sz;
            if (eql(u8, n, "hover_size")) a.metrics.hover_size = sz;
        },
        .scroll => |v| {
            if (eql(u8, n, "wheel_lines")) a.metrics.wheel_lines = v;
            if (eql(u8, n, "wheel_chars")) a.metrics.wheel_chars = v;
        },
        .opt_int => |v| a.metrics.caret_blink_ms = v,
        .flag => |v| {
            if (eql(u8, n, "keyboard_cues")) a.metrics.keyboard_cues = v;
            if (eql(u8, n, "client_animation")) a.metrics.client_animation = v;
            if (eql(u8, n, "menu_animation")) a.metrics.menu_animation = v;
            if (eql(u8, n, "menu_fade")) a.metrics.menu_fade = v;
            if (eql(u8, n, "apps_dark")) a.apps_dark = v;
            if (eql(u8, n, "high_contrast")) a.high_contrast = v;
        },
        .color => |v| a.accent = v,
        .sys_color => |v| a.sys_colors.map.set(v.c, v.v),
        .scale => |v| a.text_scale = v,
    }
    platform.Headless.setAppearance(a);
    platform.Headless.inject(.{ .system_changed = .{ .what = .{ .appearance = true, .metrics = true } } });
    drive(r, true);
}

fn execStep(r: *Runner, step: Step) void {
    r.cur_line = step.line;
    const app = r.app;
    const u = &app.ui_state;
    switch (step.cmd) {
        .move => |t| {
            switch (t) {
                .point => |pt| {
                    r.pointer = .{ .x = @intFromFloat(@round(pt.x * u.scale)), .y = @intFromFloat(@round(pt.y * u.scale)) };
                },
                .name => |nm| {
                    const n = needNode(r, nm) orelse return;
                    r.pointer = .{ .x = n.abs.x + @divTrunc(n.abs.w, 2), .y = n.abs.y + @divTrunc(n.abs.h, 2) };
                },
            }
            platform.Headless.injectMouseMove(r.pointer, r.mods);
            drive(r, true);
        },
        .down, .up => |b| {
            platform.Headless.injectMouseButton(b, step.cmd == .down, r.pointer, r.mods);
            drive(r, true);
        },
        .wheel => |dy| {
            platform.Headless.injectWheel(dy, r.pointer, r.mods);
            drive(r, true);
        },
        .key_down, .key_up => |vk| {
            const down = step.cmd == .key_down;
            switch (vk) {
                .shift => r.mods.shift = down,
                .ctrl => r.mods.ctrl = down,
                .alt => r.mods.alt = down,
                else => {},
            }
            platform.Headless.injectKey(vk, down, false, r.mods);
            drive(r, true);
        },
        .key_repeat => |k| {
            var i: u32 = 0;
            while (i < k.n) : (i += 1) platform.Headless.injectKey(k.vk, true, true, r.mods);
            drive(r, true);
        },
        .text => |s| {
            platform.Headless.injectText(s);
            drive(r, true);
        },
        .ime_start => {
            platform.Headless.injectImeStart();
            drive(r, true);
        },
        .ime_update => |v| {
            platform.Headless.injectImeUpdate(v.text, v.cursor);
            drive(r, true);
        },
        .ime_commit => |s| {
            platform.Headless.injectImeCommit(s);
            platform.Headless.injectImeEnd();
            drive(r, true);
        },
        .ime_cancel => {
            platform.Headless.injectImeCancel();
            drive(r, true);
        },
        .ole => unimplemented(r, "ole", "platform.Data 中的 drag_enter/drag_over/drag_leave/drop 事件（03 的 3.11 节）"),
        .window => unimplemented(r, "window", "多窗口/对话框窗口的无头注入目标选择"),
        .resize => |v| {
            platform.Headless.resize(@intFromFloat(@round(v.w * u.scale)), @intFromFloat(@round(v.h * u.scale)));
            drive(r, true);
        },
        .show => |on| {
            platform.Headless.setVisible(on);
            drive(r, true);
        },
        .activate => |on| {
            platform.Headless.setActive(on);
            drive(r, true);
        },
        .close => {
            platform.Headless.inject(.close_requested);
            drive(r, true);
        },
        .dpi => |n| {
            platform.Headless.setDpi(n);
            drive(r, true);
        },
        .setting => |s| applySetting(r, s),
        .invalidate => |inv| {
            if (inv.target) |nm| {
                const n = needNode(r, nm) orelse return;
                u.invalidateNode(n.id, inv.level);
            } else u.invalidate(inv.level);
            drive(r, false);
        },
        .model => |m| {
            if (std.mem.eql(u8, m.name, "clicks")) {
                r.model.clicks = std.fmt.parseInt(u32, m.value, 10) catch {
                    fail(r, "model clicks 的值不是整数：{s}", .{m.value});
                    return;
                };
            } else if (std.mem.eql(u8, m.name, "checked") or std.mem.eql(u8, m.name, "dup")) {
                const v = std.mem.eql(u8, m.value, "true") or std.mem.eql(u8, m.value, "on");
                if (std.mem.eql(u8, m.name, "checked")) r.model.checked = v else r.model.dup = v;
            } else {
                fail(r, "模型钩子未登记：{s}（ModelHookUnknown）", .{m.name});
                return;
            }
            u.invalidate(.build);
            drive(r, false);
        },
        .advance => |ms| advanceTo(r, platform.nowMs() + ms),
        .vsync => |n| {
            // 周期 = 1000 / refresh_hz（REQ-TEST-016），由无头平台按累计取整给出（03 的 REQ-PLAT-086）。
            var i: u32 = 0;
            while (i < n) : (i += 1) {
                const period = platform.Headless.peekVsyncPeriodMs();
                const end = platform.nowMs() + period;
                if (nextTimerBetween(u, platform.nowMs(), end) == null) {
                    platform.Headless.vsync(1);
                } else {
                    // 周期内有定时器到期：按时间顺序处理到周期末，再记一次垂直同步（不再推进时钟）。
                    advanceTo(r, end);
                    platform.Headless.completeVsyncCycle();
                }
                // 周期结束时若有脏标记或活动动画，运行一帧。
                if (u.dirty != .none or u.haveActiveAnimations()) drive(r, true);
            }
        },
        .mark => {
            var snap: core.stats.Snapshot = undefined;
            core.stats.snapshot(&snap);
            if (r.baseline) |old| r.gpa.free(old);
            r.baseline = r.gpa.dupe(core.stats.Entry, snap.entries) catch null;
        },
        .expect_counter => |e| {
            var snap: core.stats.Snapshot = undefined;
            core.stats.snapshot(&snap);
            for (snap.entries) |en| {
                if (!std.mem.eql(u8, en.name, e.name)) continue;
                if (en.kind == .timer) {
                    fail(r, "expect counter 只接受计数器与计量，{s} 是计时类", .{e.name});
                    return;
                }
                var actual: i64 = @intCast(en.value);
                if (en.kind == .counter) {
                    if (r.baseline) |base| {
                        for (base) |b| if (std.mem.eql(u8, b.name, e.name)) {
                            actual -= @as(i64, @intCast(b.value));
                        };
                    }
                }
                if (cmpOk(e.op, actual, e.value)) pass_(r) else fail(r, "期望 counter {s} {s} {d}，实际 {d}", .{ e.name, cmpStr(e.op), e.value, actual });
                return;
            }
            fail(r, "未知计数器名：{s}（不在 REQ-PERF-034 埋点清单）", .{e.name});
        },
        .expect_golden => unimplemented(r, "expect golden", "回放内的金图比对设施（帧缓冲读回与基准 PNG 比对接入回放运行器）"),
        .expect_popup => unimplemented(r, "expect popup", "Headless.popupRects（目前恒返回空，未接入弹出根）"),
        .expect_focus => |maybe| {
            if (maybe) |nm| {
                const n = needNode(r, nm) orelse return;
                if (u.focusedId() == n.id) pass_(r) else fail(r, "期望焦点 @{s}，实际 {s}", .{ nm, focusName(r) });
            } else {
                if (u.focusedId() == .none) pass_(r) else fail(r, "期望无焦点，实际 {s}", .{focusName(r)});
            }
        },
        .expect_visual => |e| {
            const n = needNode(r, e.name) orelse return;
            const it = n.interaction;
            const actual = switch (e.field) {
                .hovered => it.hovered,
                .pressed => it.pressed,
                .focused_visible => it.focus_visible,
                .disabled => it.disabled,
            };
            if (actual == e.value) pass_(r) else fail(r, "期望 @{s} {s} = {}，实际 {}", .{ e.name, @tagName(e.field), e.value, actual });
        },
        .expect_rect => |e| {
            const n = needNode(r, e.name) orelse return;
            const s = u.scale;
            const tol = 1.0 / s;
            const ax = @as(f32, @floatFromInt(n.abs.x)) / s;
            const ay = @as(f32, @floatFromInt(n.abs.y)) / s;
            const aw = @as(f32, @floatFromInt(n.abs.w)) / s;
            const ah = @as(f32, @floatFromInt(n.abs.h)) / s;
            if (@abs(ax - e.x) <= tol and @abs(ay - e.y) <= tol and @abs(aw - e.w) <= tol and @abs(ah - e.h) <= tol) {
                pass_(r);
            } else fail(r, "期望 @{s} 矩形 {d} {d} {d} {d}，实际 {d} {d} {d} {d}（lpx）", .{ e.name, e.x, e.y, e.w, e.h, ax, ay, aw, ah });
        },
        .expect_text => |e| {
            const n = needNode(r, e.name) orelse return;
            const actual = w.nodeText(n) orelse {
                fail(r, "@{s} 不是可读文本的控件（widgets.nodeText 未覆盖）", .{e.name});
                return;
            };
            if (std.mem.eql(u8, actual, e.text)) pass_(r) else fail(r, "期望 @{s} 文本 \"{s}\"，实际 \"{s}\"", .{ e.name, e.text, actual });
        },
        .expect_damage => |e| {
            var expected: i64 = 0;
            if (e.name) |nm| {
                const n = needNode(r, nm) orelse return;
                expected = @as(i64, n.abs.w) * @as(i64, n.abs.h);
            } else expected = e.area.?;
            const actual = u.last_damage_area;
            if (cmpOk(e.op, actual, expected)) pass_(r) else fail(r, "期望损伤面积 {s} {d}，实际 {d}（ppx）", .{ cmpStr(e.op), expected, actual });
        },
        .expect_cursor => |shape| {
            const actual = platform.Headless.cursorShape();
            if (actual == shape) pass_(r) else fail(r, "期望光标 {s}，实际 {s}", .{ @tagName(shape), @tagName(actual) });
        },
        .expect_captured => |maybe| {
            if (maybe) |nm| {
                const n = needNode(r, nm) orelse return;
                if (u.capturedId() == n.id) pass_(r) else fail(r, "期望捕获者 @{s}，实际 {s}", .{ nm, captureName(r) });
            } else {
                if (u.capturedId() == .none) pass_(r) else fail(r, "期望无捕获，实际 {s}", .{captureName(r)});
            }
        },
        .expect_timers => |n| {
            var count: u32 = 0;
            var it = u.timers.valueIterator();
            while (it.next()) |t| {
                if (t.touched + 2 > u.build_counter) count += 1;
            }
            if (count == n) pass_(r) else fail(r, "期望定时器数 {d}，实际 {d}", .{ n, count });
        },
        .expect_result => |e| {
            const n = needNode(r, e.name) orelse return;
            _ = n;
            if (r.pass_count == 0) {
                fail(r, "尚无构建遍可供断言", .{});
                return;
            }
            const pass_no: u8 = e.pass orelse r.pass_count;
            if (pass_no > r.pass_count) {
                fail(r, "最近一次构建只有 {d} 遍，无第 {d} 遍", .{ r.pass_count, pass_no });
                return;
            }
            for (r.snaps[pass_no - 1].items) |s| {
                if (!std.mem.eql(u8, s.name, e.name)) continue;
                var buf: [32]u8 = undefined;
                const actual = fieldString(&buf, s.it, e.field);
                if (std.mem.eql(u8, actual, e.value)) pass_(r) else fail(r, "期望 @{s}.{s} = {s}（第 {d} 遍），实际 {s}", .{ e.name, e.field, e.value, pass_no, actual });
                return;
            }
            fail(r, "第 {d} 遍构建中无 @{s}", .{ pass_no, e.name });
        },
    }
}

fn nameOfId(r: *Runner, id: core.WidgetId, buf: []u8) []const u8 {
    if (id == .none) return "无";
    for (r.app.ui_state.roots.items) |root| {
        if (findById(root, id)) |n| {
            if (n.debug_name) |dn| return std.fmt.bufPrint(buf, "@{s}", .{dn}) catch "?";
            return std.fmt.bufPrint(buf, "(无调试名节点 {s}:{d})", .{ n.src_file, n.src_line }) catch "?";
        }
    }
    return "(树中不存在的节点)";
}

fn findById(node: *ui.Node, id: core.WidgetId) ?*ui.Node {
    if (node.id == id) return node;
    var c = node.first_child;
    while (c) |cc| : (c = cc.next) {
        if (findById(cc, id)) |f| return f;
    }
    return null;
}

var name_buf: [160]u8 = undefined;

fn focusName(r: *Runner) []const u8 {
    return nameOfId(r, r.app.ui_state.focusedId(), &name_buf);
}

fn captureName(r: *Runner) []const u8 {
    return nameOfId(r, r.app.ui_state.capturedId(), &name_buf);
}

fn runScript(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !struct { passed: u32, failed: u32 } {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .unlimited) catch |e| {
        std.debug.print("{s}:0: 读取脚本失败：{s}\n", .{ path, @errorName(e) });
        return .{ .passed = 0, .failed = 1 };
    };
    defer gpa.free(bytes);

    // 先完整解析，再执行（REQ-TEST-013/014）。
    var steps = std.ArrayListUnmanaged(Step).empty;
    const perrs = parseScript(arena, path, bytes, &steps);
    if (perrs > 0) {
        std.debug.print("replay: {s} 解析失败，共 {d} 处错误，未执行\n", .{ path, perrs });
        return .{ .passed = 0, .failed = @intCast(perrs) };
    }

    var app = try nano.app.App.init(gpa, .{ .size = .{ .w = 420, .h = 240 }, .title = "replay" });
    nano.text.setDirectWrite(false);
    defer app.deinit();
    app.io = io;
    var r = Runner{ .gpa = gpa, .file = path, .app = &app };
    defer {
        r.snaps[0].deinit(gpa);
        r.snaps[1].deinit(gpa);
        r.dups.deinit(gpa);
        r.dups_reported.deinit(gpa);
        if (r.baseline) |b| gpa.free(b);
    }
    app.renderOnce(@as(*anyopaque, @ptrCast(&r)), build);
    r.cur_line = 0;
    reportDups(&r);

    for (steps.items) |s| execStep(&r, s);
    return .{ .passed = r.passed, .failed = r.failed };
}

pub fn main(init: std.process.Init) !void {
    nano.platform.forceHeadless();
    const gpa = init.gpa;
    const io = init.io;
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer args.deinit();
    _ = args.next(); // argv[0]
    var total_pass: u32 = 0;
    var total_fail: u32 = 0;
    var any = false;
    while (args.next()) |a| {
        if (std.mem.startsWith(u8, a, "-")) continue;
        any = true;
        const res = try runScript(gpa, io, a);
        total_pass += res.passed;
        total_fail += res.failed;
        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "replay: {s} 通过 {d}，失败 {d}\n", .{ a, res.passed, res.failed });
        try std.Io.File.stdout().writeStreamingAll(io, msg);
    }
    if (!any) {
        std.debug.print("replay: 未指定脚本\n", .{});
        std.process.exit(2);
    }
    if (total_fail > 0) {
        std.debug.print("replay: 汇总 通过 {d}，失败 {d}\n", .{ total_pass, total_fail });
        std.process.exit(1);
    }
}
