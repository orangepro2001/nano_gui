//! 设置持久化（11 的 M5 子集）：JSON 文件、类型化访问器、原子写入。
//! 文件结构为 `{ format, app_version, app, ui, ...未知顶层键 }`（REQ-APP-032）。

const std = @import("std");

pub const current_format: u32 = 1;

pub const Settings = struct {
    gpa: std.mem.Allocator,
    arena_ptr: *std.heap.ArenaAllocator,
    root: std.json.Value = .{ .object = .empty },
    dirty: bool = false,
    persistent: bool = true,
    recovered: bool = false,
    warnings: usize = 0,
    path_buf: std.ArrayListUnmanaged(u8) = .empty,
    now_ms: u64 = 0,

    pub fn init(gpa: std.mem.Allocator) Settings {
        const arena_ptr = gpa.create(std.heap.ArenaAllocator) catch @panic("nano_gui: settings arena");
        arena_ptr.* = std.heap.ArenaAllocator.init(gpa);
        var self = Settings{ .gpa = gpa, .arena_ptr = arena_ptr };
        self.root = .{ .object = .empty };
        self.ensureDefaults() catch {};
        return self;
    }

    pub fn deinit(self: *Settings) void {
        self.path_buf.deinit(self.gpa);
        self.arena_ptr.deinit();
        self.gpa.destroy(self.arena_ptr);
    }

    fn a(self: *Settings) std.mem.Allocator {
        return self.arena_ptr.allocator();
    }

    fn ensureDefaults(self: *Settings) !void {
        if (self.root != .object) self.root = .{ .object = .empty };
        const map = &self.root.object;
        try putMap(self.a(), map, "format", .{ .integer = current_format });
        try putMap(self.a(), map, "app_version", .{ .integer = 1 });
        _ = try ensureMap(self.a(), map, "app");
        _ = try ensureMap(self.a(), map, "ui");
    }

    fn putMap(allocator: std.mem.Allocator, map: *std.json.ObjectMap, key: []const u8, value: std.json.Value) !void {
        if (map.getPtr(key)) |slot| {
            slot.* = value;
            return;
        }
        const k = try allocator.dupe(u8, key);
        try map.put(allocator, k, value);
    }

    fn ensureMap(allocator: std.mem.Allocator, map: *std.json.ObjectMap, key: []const u8) !*std.json.Value {
        if (map.getPtr(key)) |v| {
            if (v.* != .object) v.* = .{ .object = .empty };
            return v;
        }
        const k = try allocator.dupe(u8, key);
        try map.put(allocator, k, .{ .object = .empty });
        return map.getPtr(key).?;
    }

    fn appObject(self: *Settings) !*std.json.ObjectMap {
        const app = try ensureMap(self.a(), &self.root.object, "app");
        return &app.object;
    }

    fn valueAt(self: *Settings, key: []const u8) ?*std.json.Value {
        const app = self.root.object.getPtr("app") orelse return null;
        if (app.* != .object) return null;
        var it = std.mem.splitScalar(u8, key, '.');
        var current: *std.json.Value = app;
        var first = true;
        while (it.next()) |seg| {
            if (seg.len == 0) return null;
            if (first) {
                first = false;
                if (current.* != .object) return null;
                current = current.object.getPtr(seg) orelse return null;
                continue;
            }
            if (current.* != .object) return null;
            current = current.object.getPtr(seg) orelse return null;
        }
        return current;
    }

    fn ensurePath(self: *Settings, key: []const u8) !*std.json.Value {
        const app = try ensureMap(self.a(), &self.root.object, "app");
        var current: *std.json.Value = app;
        var it = std.mem.splitScalar(u8, key, '.');
        while (it.next()) |seg| {
            if (seg.len == 0) return error.InvalidKey;
            const map = &current.object;
            const next = try ensureMap(self.a(), map, seg);
            current = next;
        }
        return current;
    }

    fn setValue(self: *Settings, key: []const u8, value: std.json.Value) void {
        const slot = self.ensurePath(key) catch return;
        slot.* = value;
        self.dirty = true;
    }

    // ---- 兼容早期字符串接口 ----
    pub fn put(self: *Settings, key: []const u8, value: []const u8) !void {
        const copy = try self.a().dupe(u8, value);
        self.setValue(key, .{ .string = copy });
    }
    pub fn get(self: *const Settings, key: []const u8) ?[]const u8 {
        const self_mut: *Settings = @constCast(self);
        const v = self_mut.valueAt(key) orelse return null;
        return switch (v.*) {
            .string => |s| s,
            .number_string => |s| s,
            else => null,
        };
    }

    pub fn getBool(self: *const Settings, key: []const u8, default: bool) bool {
        const self_mut: *Settings = @constCast(self);
        const v = self_mut.valueAt(key) orelse return default;
        return switch (v.*) {
            .bool => |b| b,
            else => blk: {
                self_mut.warnings += 1;
                break :blk default;
            },
        };
    }
    pub fn getInt(self: *const Settings, key: []const u8, default: i64) i64 {
        const self_mut: *Settings = @constCast(self);
        const v = self_mut.valueAt(key) orelse return default;
        return switch (v.*) {
            .integer => |n| n,
            else => blk: {
                self_mut.warnings += 1;
                break :blk default;
            },
        };
    }
    pub fn getFloat(self: *const Settings, key: []const u8, default: f64) f64 {
        const self_mut: *Settings = @constCast(self);
        const v = self_mut.valueAt(key) orelse return default;
        return switch (v.*) {
            .float => |f| f,
            .integer => |n| @floatFromInt(n),
            else => blk: {
                self_mut.warnings += 1;
                break :blk default;
            },
        };
    }
    pub fn getString(self: *const Settings, key: []const u8, default: []const u8) []const u8 {
        return self.get(key) orelse default;
    }

    pub fn setBool(self: *Settings, key: []const u8, value: bool) void {
        self.setValue(key, .{ .bool = value });
    }
    pub fn setInt(self: *Settings, key: []const u8, value: i64) void {
        self.setValue(key, .{ .integer = value });
    }
    pub fn putInt(self: *Settings, key: []const u8, value: i64) !void {
        self.setInt(key, value);
    }
    pub fn setFloat(self: *Settings, key: []const u8, value: f64) void {
        self.setValue(key, .{ .float = value });
    }
    pub fn setString(self: *Settings, key: []const u8, value: []const u8) void {
        const copy = self.a().dupe(u8, value) catch return;
        self.setValue(key, .{ .string = copy });
    }

    pub fn remove(self: *Settings, key: []const u8) void {
        const app = self.root.object.getPtr("app") orelse return;
        if (app.* != .object) return;
        const dot = std.mem.lastIndexOfScalar(u8, key, '.');
        var parent: *std.json.ObjectMap = &app.object;
        if (dot) |d| {
            var it = std.mem.splitScalar(u8, key[0..d], '.');
            while (it.next()) |seg| {
                const next = parent.getPtr(seg) orelse return;
                if (next.* != .object) return;
                parent = &next.object;
            }
        }
        const leaf = if (dot) |d| key[d + 1 ..] else key;
        _ = parent.orderedRemove(leaf);
        self.dirty = true;
    }

    pub fn recoveredFromCorruption(self: *const Settings) bool {
        return self.recovered;
    }

    pub fn path(self: *const Settings) []const u8 {
        return self.path_buf.items;
    }

    pub fn setPath(self: *Settings, p: []const u8) void {
        if (p.ptr == self.path_buf.items.ptr) return;
        self.path_buf.clearRetainingCapacity();
        self.path_buf.appendSlice(self.gpa, p) catch {};
    }

    fn serialize(self: *Settings) ![]u8 {
        try self.ensureDefaults();
        // 暴露 format 与 app_version 的当前值。
        _ = try putMap(self.a(), &self.root.object, "format", .{ .integer = current_format });
        return std.json.Stringify.valueAlloc(self.gpa, self.root, .{});
    }

    /// 原子写入：tmp → rename（REQ-APP-033）。
    pub fn save(self: *Settings, io: std.Io, file_path: []const u8) !void {
        self.setPath(file_path);
        const bytes = self.serialize() catch |e| {
            self.warnings += 1;
            return e;
        };
        defer self.gpa.free(bytes);
        const dir_name = std.fs.path.dirname(file_path);
        if (dir_name) |d| {
            std.Io.Dir.cwd().createDirPath(io, d) catch {};
        }
        var tmp_buf: [4096]u8 = undefined;
        const tmp = std.fmt.bufPrint(&tmp_buf, "{s}.tmp", .{file_path}) catch return error.NameTooLong;
        std.Io.Dir.cwd().writeFile(io, .{ .sub_path = tmp, .data = bytes }) catch |e| {
            std.Io.Dir.cwd().deleteFile(io, tmp) catch {};
            self.warnings += 1;
            return e;
        };
        std.Io.Dir.cwd().rename(tmp, std.Io.Dir.cwd(), file_path, io) catch |e| {
            std.Io.Dir.cwd().deleteFile(io, tmp) catch {};
            self.warnings += 1;
            return e;
        };
        self.dirty = false;
    }

    /// 读入；损坏时改名备份并以默认值启动（REQ-APP-035）。
    pub fn load(self: *Settings, io: std.Io, file_path: []const u8) !void {
        self.setPath(file_path);
        _ = self.arena_ptr.reset(.retain_capacity);
        self.root = .{ .object = .empty };
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, file_path, self.gpa, .unlimited) catch |e| switch (e) {
            error.FileNotFound => return,
            else => return e,
        };
        defer self.gpa.free(bytes);
        const parsed = std.json.parseFromSliceLeaky(std.json.Value, self.a(), bytes, .{}) catch {
            self.handleCorruption(io, file_path);
            return;
        };
        if (parsed != .object) {
            self.handleCorruption(io, file_path);
            return;
        }
        const fmt_val = parsed.object.get("format") orelse {
            self.handleCorruption(io, file_path);
            return;
        };
        if (fmt_val != .integer or fmt_val.integer > current_format) {
            self.handleCorruption(io, file_path);
            return;
        }
        self.root = parsed;
        self.ensureDefaults() catch {
            self.root = .{ .object = .empty };
            self.ensureDefaults() catch {};
        };
        self.dirty = false;
    }

    fn handleCorruption(self: *Settings, io: std.Io, file_path: []const u8) void {
        self.warnings += 1;
        self.recovered = true;
        const backup = std.fmt.allocPrint(self.gpa, "{s}.bad", .{file_path}) catch null;
        if (backup) |b| {
            defer self.gpa.free(b);
            std.Io.Dir.cwd().rename(file_path, std.Io.Dir.cwd(), b, io) catch {};
        }
        _ = self.arena_ptr.reset(.retain_capacity);
        self.root = .{ .object = .empty };
        self.ensureDefaults() catch {};
        self.dirty = true;
    }

    /// 退出时同步写入（REQ-APP-034 的落盘部分）。
    pub fn flush(self: *Settings, io: std.Io) void {
        if (!self.dirty or self.path_buf.items.len == 0) return;
        self.save(io, self.path_buf.items) catch {};
    }

    pub fn windowPlacement(self: *Settings, name: []const u8) ?std.json.Value {
        return storedWindowPlacement(self, name);
    }

    pub fn setWindowPlacement(self: *Settings, name: []const u8, placement: anytype) void {
        storeWindowPlacement(self, name, placement);
    }

    pub fn table(self: *Settings, name: []const u8) ?std.json.Value {
        return storedTable(self, name);
    }

    pub fn setTable(self: *Settings, name: []const u8, widths: []const f32, order: []const u16, hidden: []const bool, sort_col: ?u16, sort_asc: bool) void {
        storeTable(self, name, widths, order, hidden, sort_col, sort_asc);
    }

    pub fn tree(self: *Settings, name: []const u8) ?std.json.Value {
        return storedTree(self, name);
    }

    pub fn setTree(self: *Settings, name: []const u8, keys: []const []const u8) void {
        storeTree(self, name, keys);
    }

    pub fn splitter(self: *Settings, name: []const u8) ?std.json.Value {
        return storedSplitter(self, name);
    }

    pub fn setSplitter(self: *Settings, name: []const u8, mode: []const u8, value: f32) void {
        storeSplitter(self, name, mode, value);
    }
};

test "settings roundtrip in memory" {
    var s = Settings.init(std.testing.allocator);
    defer s.deinit();
    s.setString("theme.mode", "dark");
    s.setInt("width", 960);
    try std.testing.expectEqualStrings("dark", s.get("theme.mode").?);
    try std.testing.expectEqual(@as(i64, 960), s.getInt("width", 0));
    try std.testing.expectEqual(@as(i64, 960), s.getInt("width", 0));
}

test "serialize smoke" {
    var s = Settings.init(std.testing.allocator);
    defer s.deinit();
    const b = try s.serialize();
    defer std.testing.allocator.free(b);
    try std.testing.expect(std.mem.indexOf(u8, b, "\"format\":1") != null);
}

test "serialize after set" {
    var s = Settings.init(std.testing.allocator);
    defer s.deinit();
    s.setInt("editor.font_size", 14);
    s.setString("name", "abc");
    const b = try s.serialize();
    defer std.testing.allocator.free(b);
    try std.testing.expect(std.mem.indexOf(u8, b, "font_size") != null);
}

pub const PathOs = enum { windows, posix };
pub const EnvLookup = struct {
    ctx: ?*anyopaque = null,
    get: *const fn (ctx: ?*anyopaque, key: []const u8) ?[]const u8,
};

/// 设置文件路径（REQ-APP-031）：Windows `%APPDATA%\<vendor>\<name>\settings.json`；
/// POSIX `$XDG_CONFIG_HOME/<vendor>/<name>/settings.json`，未设置或空时 `$HOME/.config`。
pub fn resolvePath(allocator: std.mem.Allocator, vendor: []const u8, name: []const u8, os: PathOs, env: EnvLookup) ![]u8 {
    const sep: []const u8 = if (os == .windows) "\\" else "/";
    var base: []const u8 = "";
    if (os == .windows) {
        base = env.get(env.ctx, "APPDATA") orelse return error.MissingBase;
    } else {
        if (env.get(env.ctx, "XDG_CONFIG_HOME")) |x| {
            if (x.len > 0) base = x;
        }
        if (base.len == 0) {
            const home = env.get(env.ctx, "HOME") orelse return error.MissingBase;
            return std.fmt.allocPrint(allocator, "{s}/.config/{s}/{s}/settings.json", .{ home, vendor, name });
        }
    }
    return std.fmt.allocPrint(allocator, "{s}{s}{s}{s}{s}{s}settings.json", .{ base, sep, vendor, sep, name, sep });
}

/// 窗口位置记录的存取名（REQ-APP-014、037）。
pub fn storedWindowPlacement(self: *Settings, name: []const u8) ?std.json.Value {
    const ui = self.root.object.getPtr("ui") orelse return null;
    if (ui.* != .object) return null;
    const windows = ui.object.getPtr("windows") orelse return null;
    if (windows.* != .object) return null;
    return windows.object.get(name);
}

pub fn storeWindowPlacement(self: *Settings, name: []const u8, placement: anytype) void {
    const ui = ensureTopMap(self, "ui") catch return;
    const windows = Settings.ensureMap(self.a(), &ui.object, "windows") catch return;
    var obj = std.json.ObjectMap.empty;
    obj.put(self.a(), "x", .{ .integer = placement.x }) catch return;
    obj.put(self.a(), "y", .{ .integer = placement.y }) catch return;
    obj.put(self.a(), "w", .{ .integer = placement.w }) catch return;
    obj.put(self.a(), "h", .{ .integer = placement.h }) catch return;
    obj.put(self.a(), "dpi", .{ .integer = placement.dpi }) catch return;
    obj.put(self.a(), "maximized", .{ .bool = placement.maximized }) catch return;
    const k = self.a().dupe(u8, name) catch return;
    windows.object.put(self.a(), k, .{ .object = obj }) catch return;
    self.dirty = true;
}

fn ensureTopMap(self: *Settings, key: []const u8) !*std.json.Value {
    return Settings.ensureMap(self.a(), &self.root.object, key);
}

/// 表格界面状态存取（REQ-APP-037、REQ-W-TABLE-031）。
pub fn storeTable(
    self: *Settings,
    name: []const u8,
    widths: []const f32,
    order: []const u16,
    hidden: []const bool,
    sort_col: ?u16,
    sort_asc: bool,
) void {
    const ui = ensureTopMap(self, "ui") catch return;
    const tables = Settings.ensureMap(self.a(), &ui.object, "tables") catch return;
    var obj = std.json.ObjectMap.empty;
    var wa = std.json.Array.init(self.a());
    for (widths) |w| wa.append(.{ .float = w }) catch return;
    obj.put(self.a(), "widths", .{ .array = wa }) catch return;
    var oa = std.json.Array.init(self.a());
    for (order) |o| oa.append(.{ .integer = o }) catch return;
    obj.put(self.a(), "order", .{ .array = oa }) catch return;
    var ha = std.json.Array.init(self.a());
    for (hidden) |h| ha.append(.{ .bool = h }) catch return;
    obj.put(self.a(), "hidden", .{ .array = ha }) catch return;
    if (sort_col) |col| {
        var so = std.json.ObjectMap.empty;
        so.put(self.a(), "col", .{ .integer = col }) catch return;
        so.put(self.a(), "asc", .{ .bool = sort_asc }) catch return;
        obj.put(self.a(), "sort", .{ .object = so }) catch return;
    } else {
        obj.put(self.a(), "sort", .null) catch return;
    }
    const k = self.a().dupe(u8, name) catch return;
    tables.object.put(self.a(), k, .{ .object = obj }) catch return;
    self.dirty = true;
}

pub fn storedTable(self: *Settings, name: []const u8) ?std.json.Value {
    const ui = self.root.object.getPtr("ui") orelse return null;
    if (ui.* != .object) return null;
    const tables = ui.object.getPtr("tables") orelse return null;
    if (tables.* != .object) return null;
    return tables.object.get(name);
}

/// 树展开集合的持久化（REQ-W-TREE-010、REQ-APP-037）。
pub fn storeTree(self: *Settings, name: []const u8, keys: []const []const u8) void {
    const ui = ensureTopMap(self, "ui") catch return;
    const trees = Settings.ensureMap(self.a(), &ui.object, "trees") catch return;
    var arr = std.json.Array.init(self.a());
    for (keys) |k| {
        const copy = self.a().dupe(u8, k) catch return;
        arr.append(.{ .string = copy }) catch return;
    }
    const k = self.a().dupe(u8, name) catch return;
    trees.object.put(self.a(), k, .{ .array = arr }) catch return;
    self.dirty = true;
}

pub fn storedTree(self: *Settings, name: []const u8) ?std.json.Value {
    const ui = self.root.object.getPtr("ui") orelse return null;
    if (ui.* != .object) return null;
    const trees = ui.object.getPtr("trees") orelse return null;
    if (trees.* != .object) return null;
    return trees.object.get(name);
}

/// 分隔条状态（REQ-APP-037）：`mode` 为 ratio/fixed_first/fixed_second。
pub fn storeSplitter(self: *Settings, name: []const u8, mode: []const u8, value: f32) void {
    const ui = ensureTopMap(self, "ui") catch return;
    const sp = Settings.ensureMap(self.a(), &ui.object, "splitters") catch return;
    var obj = std.json.ObjectMap.empty;
    const m = self.a().dupe(u8, mode) catch return;
    obj.put(self.a(), "mode", .{ .string = m }) catch return;
    obj.put(self.a(), "value", .{ .float = value }) catch return;
    const k = self.a().dupe(u8, name) catch return;
    sp.object.put(self.a(), k, .{ .object = obj }) catch return;
    self.dirty = true;
}

pub fn storedSplitter(self: *Settings, name: []const u8) ?std.json.Value {
    const ui = self.root.object.getPtr("ui") orelse return null;
    if (ui.* != .object) return null;
    const sp = ui.object.getPtr("splitters") orelse return null;
    if (sp.* != .object) return null;
    return sp.object.get(name);
}
