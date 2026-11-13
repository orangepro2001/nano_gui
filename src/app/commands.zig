//! 命令与快捷键表（11 的核心子集）。
//! 命令是具名、可绑定快捷键的应用动作；输入分发在 ④ 级查表后同步调用处理器。

const std = @import("std");
const core = @import("../core.zig");
const input = @import("../input.zig");
const platform = @import("../platform.zig");
const theme = @import("../theme.zig");

pub const Handler = *const fn (ctx: ?*anyopaque) void;
pub const HandlerSource = *const fn (ctx: ?*anyopaque, from: InvokeSource) void;
pub const InvokeSource = enum { shortcut, menu, toolbar, programmatic };
pub const ShortcutMode = enum { reject, steal };
pub const Error = error{ DuplicateCommand, InvalidCommandId, ShortcutConflict, InvalidShortcut, UnknownCommand, OutOfMemory };
pub const CommandState = struct { enabled: bool = true, checked: ?bool = null };

pub const Command = struct {
    name: []const u8,
    title: []const u8 = "",
    icon: ?theme.Icon = null,
    shortcut: ?input.Chord = null,
    default_shortcut: ?input.Chord = null,
    enabled: bool = true,
    default_state: CommandState = .{},
    handler: ?Handler = null,
    handler_source: ?HandlerSource = null,
    ctx: ?*anyopaque = null,
};

/// 命令字符串标识：`[a-z0-9_]+(\.[a-z0-9_]+)*`，≤ 64 字节（REQ-APP-023）。
pub fn validCommandId(id: []const u8) bool {
    if (id.len == 0 or id.len > 64) return false;
    var it = std.mem.splitScalar(u8, id, '.');
    while (it.next()) |seg| {
        if (seg.len == 0) return false;
        for (seg) |c| {
            if (!(std.ascii.isLower(c) or std.ascii.isDigit(c) or c == '_')) return false;
        }
    }
    return true;
}

pub const Registry = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayListUnmanaged(Command) = .empty,

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Registry) void {
        for (self.items.items) |c| {
            self.allocator.free(c.name);
            self.allocator.free(c.title);
        }
        self.items.deinit(self.allocator);
    }

    /// name 与 title 由框架复制；返回命令句柄（下标 + 1）。
    pub fn register(self: *Registry, cmd: Command) Error!input.CommandId {
        if (!validCommandId(cmd.name)) return error.InvalidCommandId;
        var i: usize = 0;
        while (i < self.items.items.len) : (i += 1) {
            if (std.mem.eql(u8, self.items.items[i].name, cmd.name)) return error.DuplicateCommand;
        }
        if (cmd.shortcut) |s| {
            if (!validShortcut(s)) return error.InvalidShortcut;
        }
        var c = cmd;
        c.name = try self.allocator.dupe(u8, cmd.name);
        errdefer self.allocator.free(c.name);
        c.title = try self.allocator.dupe(u8, cmd.title);
        errdefer self.allocator.free(c.title);
        c.default_shortcut = cmd.shortcut;
        c.default_state = cmd.default_state;
        // 注册时的默认快捷键也要互不冲突。
        if (c.shortcut) |s| {
            for (self.items.items) |other| {
                if (other.shortcut) |os| if (os.key == s.key and os.mods.eql(s.mods)) {
                    self.allocator.free(c.name);
                    self.allocator.free(c.title);
                    return error.ShortcutConflict;
                };
            }
        }
        try self.items.append(self.allocator, c);
        return @fromBackingInt(@intCast(@as(u32, @intCast(self.items.items.len))));
    }

    /// 兼容旧调用点。
    pub fn add(self: *Registry, cmd: Command) !input.CommandId {
        return self.register(cmd);
    }

    pub fn get(self: *const Registry, id: input.CommandId) ?*const Command {
        const idx: usize = @backingInt(id);
        if (idx == 0 or idx > self.items.items.len) return null;
        return &self.items.items[idx - 1];
    }

    pub fn getMut(self: *Registry, id: input.CommandId) ?*Command {
        const idx: usize = @backingInt(id);
        if (idx == 0 or idx > self.items.items.len) return null;
        return &self.items.items[idx - 1];
    }

    pub fn find(self: *const Registry, name: []const u8) ?input.CommandId {
        for (self.items.items, 0..) |c, i| {
            if (std.mem.eql(u8, c.name, name)) return @fromBackingInt(@intCast(@as(u32, @intCast(i + 1))));
        }
        return null;
    }

    pub fn titleOf(self: *const Registry, id: input.CommandId) []const u8 {
        const c = self.get(id) orelse return "";
        return c.title;
    }

    pub fn shortcutOf(self: *const Registry, id: input.CommandId) ?input.Chord {
        const c = self.get(id) orelse return null;
        return c.shortcut;
    }

    pub fn setEnabled(self: *Registry, id: input.CommandId, enabled: bool) void {
        if (self.getMut(id)) |c| c.enabled = enabled;
    }

    pub fn lookupChord(self: *Registry, chord: input.Chord) ?input.ShortcutHit {
        for (self.items.items, 0..) |c, i| {
            if (c.shortcut) |s| {
                if (s.key == chord.key and s.mods.eql(chord.mods)) {
                    return .{ .command = @fromBackingInt(@intCast(@as(u32, @intCast(i + 1)))), .enabled = c.enabled };
                }
            }
        }
        return null;
    }

    pub fn invoke(self: *Registry, id: input.CommandId) void {
        self.invokeSource(id, .programmatic);
    }

    pub fn invokeSource(self: *Registry, id: input.CommandId, from: InvokeSource) void {
        const c = self.get(id) orelse return;
        if (!c.enabled) return;
        if (c.handler_source) |h| {
            h(c.ctx, from);
        } else if (c.handler) |h| {
            h(c.ctx);
        }
    }

    pub fn setShortcut(self: *Registry, id: input.CommandId, chord: ?input.Chord, mode: ShortcutMode) Error!void {
        const idx: usize = @backingInt(id);
        if (idx == 0 or idx > self.items.items.len) return error.UnknownCommand;
        if (chord) |s| {
            if (!validShortcut(s)) return error.InvalidShortcut;
            for (self.items.items, 0..) |other, i| {
                if (i + 1 == idx) continue;
                if (other.shortcut) |os| {
                    if (os.key == s.key and os.mods.eql(s.mods)) {
                        if (mode == .reject) return error.ShortcutConflict;
                        self.items.items[i].shortcut = null;
                    }
                }
            }
        }
        self.items.items[idx - 1].shortcut = chord;
    }

    pub fn resetShortcuts(self: *Registry) void {
        for (self.items.items) |*c| c.shortcut = c.default_shortcut;
    }

    pub fn source(self: *Registry) input.ShortcutSource {
        return .{
            .ctx = self,
            .lookup = struct {
                fn lookup(ctx: *anyopaque, chord: input.Chord) ?input.ShortcutHit {
                    const r: *Registry = @ptrCast(@alignCast(ctx));
                    return r.lookupChord(chord);
                }
            }.lookup,
            .invoke = struct {
                fn invoke(ctx: *anyopaque, id: input.CommandId) void {
                    const r: *Registry = @ptrCast(@alignCast(ctx));
                    r.invokeSource(id, .shortcut);
                }
            }.invoke,
        };
    }

    pub fn formatChord(self: *const Registry, buf: []u8, chord: input.Chord) []const u8 {
        _ = self;
        return formatChordEnglish(buf, chord) catch "";
    }

    pub fn chordToInvariant(self: *const Registry, buf: []u8, chord: input.Chord) []const u8 {
        _ = self;
        return formatChordEnglish(buf, chord) catch "";
    }

    pub fn chordFromInvariant(_: *const Registry, text: []const u8) error{InvalidShortcut}!input.Chord {
        return parseChord(text);
    }
};

/// 和弦合法性（REQ-APP-027）：至少一个非修饰键；Shift+可打印字符拒绝。
pub fn validShortcut(chord: input.Chord) bool {
    const k = chord.key;
    if (k == .none or k == .shift or k == .ctrl or k == .alt or k == .lwin or k == .rwin) return false;
    if (chord.mods.shift and !chord.mods.ctrl and !chord.mods.alt and k != .space and !input.isFunction(k) and input.isPrintable(k)) {
        return false;
    }
    return true;
}

fn keyNameEnglish(buf: []u8, key: platform.VirtualKey) ![]const u8 {
    const v = @backingInt(key);
    if (v >= 'A' and v <= 'Z') return try std.fmt.bufPrint(buf, "{c}", .{@as(u8, @intCast(v))});
    if (v >= '0' and v <= '9') return try std.fmt.bufPrint(buf, "{c}", .{@as(u8, @intCast(v))});
    if (v >= 0x70 and v <= 0x87) return try std.fmt.bufPrint(buf, "F{d}", .{v - 0x6F});
    return switch (key) {
        .enter => "Enter",
        .escape => "Esc",
        .delete => "Del",
        .insert => "Ins",
        .home => "Home",
        .end => "End",
        .page_up => "PgUp",
        .page_down => "PgDn",
        .space => "Space",
        .tab => "Tab",
        .backspace => "Backspace",
        .left => "Left",
        .up => "Up",
        .right => "Right",
        .down => "Down",
        .apps => "Menu",
        .np_mul => "*",
        .np_add => "+",
        .np_sub => "-",
        .np_div => "/",
        .np_decimal => ".",
        else => try std.fmt.bufPrint(buf, "{d}", .{v}),
    };
}

fn appendPart(buf: []u8, pos: *usize, s: []const u8) !void {
    if (pos.* + s.len > buf.len) return error.NoSpaceLeft;
    @memcpy(buf[pos.* .. pos.* + s.len], s);
    pos.* += s.len;
}

pub fn formatChordEnglish(buf: []u8, chord: input.Chord) ![]const u8 {
    var pos: usize = 0;
    var first = true;
    const mods = [_]struct { on: bool, name: []const u8 }{
        .{ .on = chord.mods.ctrl, .name = "Ctrl" },
        .{ .on = chord.mods.alt, .name = "Alt" },
        .{ .on = chord.mods.shift, .name = "Shift" },
        .{ .on = chord.mods.win, .name = "Win" },
    };
    for (mods) |m| {
        if (!m.on) continue;
        if (!first) try appendPart(buf, &pos, "+");
        try appendPart(buf, &pos, m.name);
        first = false;
    }
    if (!first) try appendPart(buf, &pos, "+");
    var kb: [16]u8 = undefined;
    const name = try keyNameEnglish(&kb, chord.key);
    try appendPart(buf, &pos, name);
    return buf[0..pos];
}

fn parseKey(text: []const u8) ?platform.VirtualKey {
    if (text.len == 0) return null;
    if (text.len == 1) {
        const c = std.ascii.toUpper(text[0]);
        if (c >= 'A' and c <= 'Z') return @fromBackingInt(@intCast(@as(u16, c)));
        if (c >= '0' and c <= '9') return @fromBackingInt(@intCast(@as(u16, c)));
        if (text[0] == '*') return .np_mul;
        if (text[0] == '+') return .np_add;
        if (text[0] == '-') return .np_sub;
        if (text[0] == '/') return .np_div;
        if (text[0] == '.') return .np_decimal;
    }
    var low_buf: [16]u8 = undefined;
    if (text.len > low_buf.len) return null;
    for (text, 0..) |c, i| low_buf[i] = std.ascii.toLower(c);
    const low = low_buf[0..text.len];
    if (low.len >= 2 and low[0] == 'f') {
        const n = std.fmt.parseInt(u16, low[1..], 10) catch return null;
        if (n >= 1 and n <= 24) return @fromBackingInt(@intCast(@as(u16, 0x6F + n)));
    }
    const map = .{
        .{ "enter", platform.VirtualKey.enter },
        .{ "esc", platform.VirtualKey.escape },
        .{ "escape", platform.VirtualKey.escape },
        .{ "del", platform.VirtualKey.delete },
        .{ "delete", platform.VirtualKey.delete },
        .{ "ins", platform.VirtualKey.insert },
        .{ "insert", platform.VirtualKey.insert },
        .{ "home", platform.VirtualKey.home },
        .{ "end", platform.VirtualKey.end },
        .{ "pgup", platform.VirtualKey.page_up },
        .{ "pageup", platform.VirtualKey.page_up },
        .{ "pgdn", platform.VirtualKey.page_down },
        .{ "pagedown", platform.VirtualKey.page_down },
        .{ "space", platform.VirtualKey.space },
        .{ "tab", platform.VirtualKey.tab },
        .{ "backspace", platform.VirtualKey.backspace },
        .{ "left", platform.VirtualKey.left },
        .{ "up", platform.VirtualKey.up },
        .{ "right", platform.VirtualKey.right },
        .{ "down", platform.VirtualKey.down },
        .{ "menu", platform.VirtualKey.apps },
    };
    inline for (map) |entry| {
        if (std.mem.eql(u8, low, entry[0])) return entry[1];
    }
    return null;
}

pub fn parseChord(text: []const u8) error{InvalidShortcut}!input.Chord {
    if (text.len == 0) return error.InvalidShortcut;
    var mods = platform.Mods{};
    var key: ?platform.VirtualKey = null;
    var it = std.mem.splitScalar(u8, text, '+');
    var any = false;
    while (it.next()) |raw| {
        const part = std.mem.trim(u8, raw, " ");
        if (part.len == 0) return error.InvalidShortcut;
        any = true;
        if (std.ascii.eqlIgnoreCase(part, "ctrl") or std.ascii.eqlIgnoreCase(part, "control")) {
            mods.ctrl = true;
        } else if (std.ascii.eqlIgnoreCase(part, "alt")) {
            mods.alt = true;
        } else if (std.ascii.eqlIgnoreCase(part, "shift")) {
            mods.shift = true;
        } else if (std.ascii.eqlIgnoreCase(part, "win")) {
            mods.win = true;
        } else {
            if (key != null) return error.InvalidShortcut;
            key = parseKey(part) orelse return error.InvalidShortcut;
        }
    }
    if (!any) return error.InvalidShortcut;
    const k = key orelse return error.InvalidShortcut;
    const chord = input.Chord{ .key = k, .mods = mods };
    if (!validShortcut(chord)) return error.InvalidShortcut;
    return chord;
}

pub const Chord = input.Chord;

test "command registry smoke: lookup, invoke, disable (no AC yet)" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();
    const S = struct {
        var hits: u32 = 0;
        fn run(_: ?*anyopaque) void {
            hits += 1;
        }
    };
    const id = try reg.add(.{ .name = "file.save", .title = "保存", .shortcut = .{ .key = .s, .mods = .{ .ctrl = true } }, .handler = S.run });
    S.hits = 0;
    const hit = reg.lookupChord(.{ .key = .s, .mods = .{ .ctrl = true } });
    try std.testing.expect(hit != null);
    try std.testing.expect(hit.?.enabled);
    reg.invoke(id);
    try std.testing.expectEqual(@as(u32, 1), S.hits);
    reg.setEnabled(id, false);
    reg.invoke(id);
    try std.testing.expectEqual(@as(u32, 1), S.hits);
}
