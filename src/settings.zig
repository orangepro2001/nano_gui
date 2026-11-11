//! 设置持久化（11 的核心子集）：字符串键值，UTF-8 文本格式 `key=value\n`。
//! 复杂版本迁移与按窗口布局的保存由应用层扩展；框架只保证显式分配器与显式 I/O。

const std = @import("std");

pub const Settings = struct {
    allocator: std.mem.Allocator,
    map: std.StringHashMapUnmanaged([]u8) = .empty,
    dirty: bool = false,

    pub fn init(allocator: std.mem.Allocator) Settings {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Settings) void {
        var it = self.map.iterator();
        while (it.next()) |kv| {
            self.allocator.free(kv.key_ptr.*);
            self.allocator.free(kv.value_ptr.*);
        }
        self.map.deinit(self.allocator);
    }

    pub fn put(self: *Settings, key: []const u8, value: []const u8) !void {
        if (self.map.fetchRemove(key)) |old| {
            self.allocator.free(old.key);
            self.allocator.free(old.value);
        }
        const k = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(k);
        const v = try self.allocator.dupe(u8, value);
        try self.map.put(self.allocator, k, v);
        self.dirty = true;
    }

    pub fn get(self: *const Settings, key: []const u8) ?[]const u8 {
        return self.map.get(key);
    }

    pub fn putInt(self: *Settings, key: []const u8, value: i64) !void {
        var buf: [32]u8 = undefined;
        const s = try std.fmt.bufPrint(&buf, "{d}", .{value});
        try self.put(key, s);
    }

    pub fn getInt(self: *const Settings, key: []const u8, default: i64) i64 {
        const s = self.get(key) orelse return default;
        return std.fmt.parseInt(i64, s, 10) catch default;
    }

    pub fn save(self: *Settings, io: std.Io, path: []const u8) !void {
        var out = std.ArrayListUnmanaged(u8).empty;
        defer out.deinit(self.allocator);
        var it = self.map.iterator();
        while (it.next()) |kv| {
            try out.appendSlice(self.allocator, kv.key_ptr.*);
            try out.append(self.allocator, '=');
            try out.appendSlice(self.allocator, kv.value_ptr.*);
            try out.append(self.allocator, '\n');
        }
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = out.items });
        self.dirty = false;
    }

    pub fn load(self: *Settings, io: std.Io, path: []const u8) !void {
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, self.allocator, .unlimited) catch |e| switch (e) {
            error.FileNotFound => return,
            else => return e,
        };
        defer self.allocator.free(bytes);
        var it = std.mem.splitScalar(u8, bytes, '\n');
        while (it.next()) |line| {
            if (line.len == 0 or line[0] == '#') continue;
            const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
            try self.put(line[0..eq], line[eq + 1 ..]);
        }
    }
};

test "settings roundtrip in memory" {
    var s = Settings.init(std.testing.allocator);
    defer s.deinit();
    try s.put("theme", "dark");
    try s.putInt("width", 960);
    try std.testing.expectEqualStrings("dark", s.get("theme").?);
    try std.testing.expectEqual(@as(i64, 960), s.getInt("width", 0));
}
