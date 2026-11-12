//! 命令与快捷键表（11 的核心子集）。
//! 命令是具名、可绑定快捷键的应用动作；输入分发在 ④ 级查表后同步调用处理器。

const std = @import("std");
const core = @import("core.zig");
const input = @import("input.zig");
const platform = @import("platform.zig");

pub const Handler = *const fn (ctx: ?*anyopaque) void;

pub const Command = struct {
    name: []const u8,
    title: []const u8 = "",
    shortcut: ?input.Chord = null,
    enabled: bool = true,
    handler: ?Handler = null,
    ctx: ?*anyopaque = null,
};

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

    /// name 与 title 由框架复制；函数返回命令句柄（下标 + 1）。
    pub fn add(self: *Registry, cmd: Command) !input.CommandId {
        var c = cmd;
        c.name = try self.allocator.dupe(u8, cmd.name);
        errdefer self.allocator.free(c.name);
        c.title = try self.allocator.dupe(u8, cmd.title);
        try self.items.append(self.allocator, c);
        return @fromBackingInt(@intCast(@as(u32, @intCast(self.items.items.len))));
    }

    pub fn get(self: *const Registry, id: input.CommandId) ?*const Command {
        const idx: usize = @backingInt(id);
        if (idx == 0 or idx > self.items.items.len) return null;
        return &self.items.items[idx - 1];
    }

    pub fn setEnabled(self: *Registry, id: input.CommandId, enabled: bool) void {
        const idx: usize = @backingInt(id);
        if (idx != 0 and idx <= self.items.items.len) self.items.items[idx - 1].enabled = enabled;
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
        const c = self.get(id) orelse return;
        if (!c.enabled) return;
        if (c.handler) |h| h(c.ctx);
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
                    r.invoke(id);
                }
            }.invoke,
        };
    }
};

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
