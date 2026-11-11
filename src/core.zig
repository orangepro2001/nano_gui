//! nano_gui 基础层：数学类型、颜色、哈希、帧竞技场、日志与埋点。
//! 本模块不依赖任何其他模块与操作系统 API（REQ-ARCH-002）。

const std = @import("std");

pub const Vec2 = struct {
    x: f32 = 0,
    y: f32 = 0,

    pub fn add(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }
    pub fn sub(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }
    pub fn scale(a: Vec2, s: f32) Vec2 {
        return .{ .x = a.x * s, .y = a.y * s };
    }
};

pub const Vec2i = struct {
    x: i32 = 0,
    y: i32 = 0,
};

pub const Size = struct {
    w: f32 = 0,
    h: f32 = 0,
};

pub const Size2i = struct {
    w: i32 = 0,
    h: i32 = 0,
};

pub const Rect = struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,

    pub fn right(self: Rect) f32 {
        return self.x + self.w;
    }
    pub fn bottom(self: Rect) f32 {
        return self.y + self.h;
    }
    pub fn center(self: Rect) Vec2 {
        return .{ .x = self.x + self.w * 0.5, .y = self.y + self.h * 0.5 };
    }
    pub fn contains(self: Rect, p: Vec2) bool {
        return p.x >= self.x and p.y >= self.y and p.x < self.right() and p.y < self.bottom();
    }
    pub fn inset(self: Rect, i: Insets) Rect {
        return .{
            .x = self.x + i.l,
            .y = self.y + i.t,
            .w = @max(0, self.w - i.l - i.r),
            .h = @max(0, self.h - i.t - i.b),
        };
    }
    pub fn intersect(a: Rect, b: Rect) Rect {
        const x0 = @max(a.x, b.x);
        const y0 = @max(a.y, b.y);
        const x1 = @min(a.right(), b.right());
        const y1 = @min(a.bottom(), b.bottom());
        if (x1 <= x0 or y1 <= y0) return .{};
        return .{ .x = x0, .y = y0, .w = x1 - x0, .h = y1 - y0 };
    }
    pub fn unionRect(a: Rect, b: Rect) Rect {
        if (a.w <= 0 or a.h <= 0) return b;
        if (b.w <= 0 or b.h <= 0) return a;
        const x0 = @min(a.x, b.x);
        const y0 = @min(a.y, b.y);
        const x1 = @max(a.right(), b.right());
        const y1 = @max(a.bottom(), b.bottom());
        return .{ .x = x0, .y = y0, .w = x1 - x0, .h = y1 - y0 };
    }
    pub fn isEmpty(self: Rect) bool {
        return self.w <= 0 or self.h <= 0;
    }
};

pub const RectI = struct {
    x: i32 = 0,
    y: i32 = 0,
    w: i32 = 0,
    h: i32 = 0,

    pub fn right(self: RectI) i32 {
        return self.x + self.w;
    }
    pub fn bottom(self: RectI) i32 {
        return self.y + self.h;
    }
    pub fn contains(self: RectI, p: Vec2i) bool {
        return p.x >= self.x and p.y >= self.y and p.x < self.right() and p.y < self.bottom();
    }
    pub fn intersect(a: RectI, b: RectI) RectI {
        const x0 = @max(a.x, b.x);
        const y0 = @max(a.y, b.y);
        const x1 = @min(a.right(), b.right());
        const y1 = @min(a.bottom(), b.bottom());
        if (x1 <= x0 or y1 <= y0) return .{};
        return .{ .x = x0, .y = y0, .w = x1 - x0, .h = y1 - y0 };
    }
    pub fn unionRect(a: RectI, b: RectI) RectI {
        if (a.w <= 0 or a.h <= 0) return b;
        if (b.w <= 0 or b.h <= 0) return a;
        const x0 = @min(a.x, b.x);
        const y0 = @min(a.y, b.y);
        const x1 = @max(a.right(), b.right());
        const y1 = @max(a.bottom(), b.bottom());
        return .{ .x = x0, .y = y0, .w = x1 - x0, .h = y1 - y0 };
    }
    pub fn isEmpty(self: RectI) bool {
        return self.w <= 0 or self.h <= 0;
    }
    pub fn area(self: RectI) i64 {
        if (self.w <= 0 or self.h <= 0) return 0;
        return @as(i64, self.w) * @as(i64, self.h);
    }
};

pub const Insets = struct {
    l: f32 = 0,
    t: f32 = 0,
    r: f32 = 0,
    b: f32 = 0,

    pub fn all(v: f32) Insets {
        return .{ .l = v, .t = v, .r = v, .b = v };
    }
    pub fn symmetric(x: f32, y: f32) Insets {
        return .{ .l = x, .t = y, .r = x, .b = y };
    }
};

pub const Color = packed struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 255,

    pub const transparent: Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
    pub const white: Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 };
    pub const black: Color = .{ .r = 0, .g = 0, .b = 0, .a = 255 };

    pub fn fromHex(hex: u32, alpha: u8) Color {
        return .{
            .r = @truncate(hex >> 16),
            .g = @truncate(hex >> 8),
            .b = @truncate(hex),
            .a = alpha,
        };
    }

    pub fn parse(text: []const u8) !Color {
        var s = text;
        if (s.len > 0 and s[0] == '#') s = s[1..];
        if (s.len != 6 and s.len != 8) return error.InvalidColor;
        var value: u32 = 0;
        for (s) |c| {
            const d: u32 = switch (c) {
                '0'...'9' => c - '0',
                'a'...'f' => c - 'a' + 10,
                'A'...'F' => c - 'A' + 10,
                else => return error.InvalidColor,
            };
            value = value * 16 + d;
        }
        if (s.len == 8) return .{
            .r = @truncate(value >> 24),
            .g = @truncate(value >> 16),
            .b = @truncate(value >> 8),
            .a = @truncate(value),
        };
        return fromHex(value, 255);
    }

    pub fn withAlpha(self: Color, a: u8) Color {
        return .{ .r = self.r, .g = self.g, .b = self.b, .a = a };
    }

    pub fn blend(src: Color, dst: Color) Color {
        if (src.a == 255) return src;
        if (src.a == 0) return dst;
        const sa: u32 = src.a;
        const da: u32 = dst.a;
        const ia: u32 = 255 - sa;
        const out_a = sa + da * ia / 255;
        if (out_a == 0) return transparent;
        const r = (@as(u32, src.r) * sa + @as(u32, dst.r) * da * ia / 255) / out_a;
        const g = (@as(u32, src.g) * sa + @as(u32, dst.g) * da * ia / 255) / out_a;
        const b = (@as(u32, src.b) * sa + @as(u32, dst.b) * da * ia / 255) / out_a;
        return .{ .r = @intCast(@min(255, r)), .g = @intCast(@min(255, g)), .b = @intCast(@min(255, b)), .a = @intCast(@min(255, out_a)) };
    }

    pub fn lerp(a: Color, b: Color, t: f32) Color {
        const tt = std.math.clamp(t, 0, 1);
        return .{
            .r = @intFromFloat(@round(@as(f32, @floatFromInt(a.r)) + (@as(f32, @floatFromInt(b.r)) - @as(f32, @floatFromInt(a.r))) * tt)),
            .g = @intFromFloat(@round(@as(f32, @floatFromInt(a.g)) + (@as(f32, @floatFromInt(b.g)) - @as(f32, @floatFromInt(a.g))) * tt)),
            .b = @intFromFloat(@round(@as(f32, @floatFromInt(a.b)) + (@as(f32, @floatFromInt(b.b)) - @as(f32, @floatFromInt(a.b))) * tt)),
            .a = @intFromFloat(@round(@as(f32, @floatFromInt(a.a)) + (@as(f32, @floatFromInt(b.a)) - @as(f32, @floatFromInt(a.a))) * tt)),
        };
    }

    pub fn luminance(self: Color) f32 {
        const r = srgbToLinear(@as(f32, @floatFromInt(self.r)) / 255.0);
        const g = srgbToLinear(@as(f32, @floatFromInt(self.g)) / 255.0);
        const b = srgbToLinear(@as(f32, @floatFromInt(self.b)) / 255.0);
        return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    }

    pub fn contrast(a: Color, b: Color) f32 {
        const la = a.luminance();
        const lb = b.luminance();
        const hi = @max(la, lb);
        const lo = @min(la, lb);
        return (hi + 0.05) / (lo + 0.05);
    }

    fn srgbToLinear(c: f32) f32 {
        if (c <= 0.04045) return c / 12.92;
        return std.math.pow(f32, (c + 0.055) / 1.055, 2.4);
    }
};

pub const WidgetId = enum(u64) {
    none = 0,
    _,

    pub fn raw(self: WidgetId) u64 {
        return @backingInt(self);
    }
    pub fn fromHash(h: u64) WidgetId {
        if (h == 0) return @fromBackingInt(@intCast(1));
        return @fromBackingInt(@intCast(h));
    }
};

pub const Closure = struct {
    ctx: ?*anyopaque,
    func: *const fn (ctx: ?*anyopaque) void,
};

pub fn hashBytes(seed: u64, bytes: []const u8) u64 {
    var h = std.hash.Wyhash.init(seed);
    h.update(bytes);
    return h.final();
}

pub fn hashU64(seed: u64, value: u64) u64 {
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, value, .little);
    return hashBytes(seed, &buf);
}

pub const FrameArena = struct {
    arena: std.heap.ArenaAllocator,

    pub fn init(backing: std.mem.Allocator) FrameArena {
        return .{ .arena = std.heap.ArenaAllocator.init(backing) };
    }
    pub fn deinit(self: *FrameArena) void {
        self.arena.deinit();
    }
    pub fn allocator(self: *FrameArena) std.mem.Allocator {
        return self.arena.allocator();
    }
    pub fn reset(self: *FrameArena) void {
        _ = self.arena.reset(.retain_capacity);
    }
    pub fn bytesUsed(self: *const FrameArena) usize {
        return self.arena.queryCapacity();
    }
};

pub const log = struct {
    pub const Level = enum { err, warn, info, debug };

    pub const Sink = *const fn (level: Level, tag: []const u8, msg: []const u8) void;

    var sink: ?Sink = null;
    var spin = std.atomic.Value(bool).init(false);

    fn acquire() void {
        while (spin.swap(true, .acquire)) {
            std.atomic.spinLoopHint();
        }
    }
    fn release() void {
        spin.store(false, .release);
    }

    pub fn setSink(s: ?Sink) void {
        acquire();
        defer release();
        sink = s;
    }

    pub fn write(level: Level, tag: []const u8, comptime fmt: []const u8, args: anytype) void {
        acquire();
        const s = sink;
        release();
        if (s) |cb| {
            var buf: [1024]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, fmt, args) catch fmt;
            cb(level, tag, msg);
        } else {
            if (level == .debug and @import("builtin").mode == .ReleaseFast) return;
            std.debug.print("[{s}] {s}: " ++ fmt ++ "\n", .{ @tagName(level), tag } ++ args);
        }
    }

    pub fn scoped(comptime tag: @TypeOf(.enum_literal)) type {
        return struct {
            pub fn err(comptime fmt: []const u8, args: anytype) void {
                write(.err, @tagName(tag), fmt, args);
            }
            pub fn warn(comptime fmt: []const u8, args: anytype) void {
                write(.warn, @tagName(tag), fmt, args);
            }
            pub fn info(comptime fmt: []const u8, args: anytype) void {
                write(.info, @tagName(tag), fmt, args);
            }
            pub fn debug(comptime fmt: []const u8, args: anytype) void {
                write(.debug, @tagName(tag), fmt, args);
            }
        };
    }
};

pub const stats = struct {
    pub const Kind = enum { counter, gauge, timer };
    pub const Entry = struct { name: []const u8, kind: Kind, value: u64 };
    pub const Snapshot = struct { entries: []const Entry };

    const max_entries = 512;

    const Slot = struct {
        name: []const u8,
        kind: Kind,
        value: *u64,
        used: bool = false,
    };

    var slots: [max_entries]Slot = undefined;
    var count: usize = 0;
    var spin = std.atomic.Value(bool).init(false);
    var snapshot_buf: [max_entries]Entry = undefined;

    fn acquire() void {
        while (spin.swap(true, .acquire)) std.atomic.spinLoopHint();
    }
    fn release() void {
        spin.store(false, .release);
    }

    fn find(name: []const u8) ?*Slot {
        var i: usize = 0;
        while (i < count) : (i += 1) {
            if (std.mem.eql(u8, slots[i].name, name)) return &slots[i];
        }
        return null;
    }

    fn register(comptime name: []const u8, kind: Kind, ptr: *u64) *u64 {
        acquire();
        defer release();
        if (find(name)) |s| return s.value;
        if (count >= max_entries) return ptr;
        slots[count] = .{ .name = name, .kind = kind, .value = ptr, .used = true };
        count += 1;
        return ptr;
    }

    pub fn counter(comptime name: []const u8) *u64 {
        const S = struct {
            var v: u64 = 0;
        };
        return register(name, .counter, &S.v);
    }

    pub fn gauge(comptime name: []const u8) *u64 {
        const S = struct {
            var v: u64 = 0;
        };
        return register(name, .gauge, &S.v);
    }

    const TimerSlot = struct {
        var total: u64 = 0;
        var start: u64 = 0;
    };

    fn timerPtr(comptime name: []const u8) *u64 {
        const S = struct {
            var total: u64 = 0;
        };
        return register(name, .timer, &S.total);
    }

    pub fn timerBegin(comptime name: []const u8) void {
        _ = timerPtr(name);
    }

    pub fn timerEnd(comptime name: []const u8) void {
        // 计时由注入的 Io/平台时钟在基准构建中采样；纯逻辑测试不依赖真实时钟。
        _ = timerPtr(name);
    }

    /// 返回全部已注册项的快照；切片在下一次 snapshot 前有效。
    pub fn snapshot(out: *Snapshot) void {
        acquire();
        defer release();
        var i: usize = 0;
        while (i < count) : (i += 1) {
            snapshot_buf[i] = .{ .name = slots[i].name, .kind = slots[i].kind, .value = slots[i].value.* };
        }
        out.* = .{ .entries = snapshot_buf[0..count] };
    }

    pub fn drainSamples(_: []const u8, _: []u64) usize {
        return 0;
    }

    /// 注册 REQ-PERF-034 表中全部冻结名字；重复调用无副作用。
    pub fn initRegistry() void {
        const counters = [_][]const u8{
            "frame.count",            "frame.build_passes",     "frame.nodes_measure_reused",
            "frame.nodes_painted",    "frame.damage_area_ppx",  "frame.presents",
            "frame.gl_draw_calls",    "alloc.persistent.count", "alloc.state.count",
            "alloc.frame.grow_count", "cache.text_layout.hits", "cache.text_layout.misses",
            "loop.block_waits",       "threads.created",
        };
        const gauges = [_][]const u8{
            "frame.nodes",             "alloc.persistent.bytes",    "alloc.arena.bytes",
            "cache.text_layout.bytes", "cache.text_layout.entries", "cache.glyph_atlas.bytes",
            "cache.image.bytes",       "list.virtual_nodes",        "list.virtual_cells",
        };
        const timers = [_][]const u8{
            "time.collect", "time.dispatch",   "time.build",
            "time.layout",  "time.damage",     "time.paint",
            "time.present", "time.frame_cpu",  "time.input_to_present",
            "time.startup", "time.gl_context", "time.text_load",
        };
        inline for (counters) |name| _ = counter(name);
        inline for (gauges) |name| _ = gauge(name);
        inline for (timers) |name| _ = timerPtr(name);
    }

    pub fn resetAll() void {
        acquire();
        defer release();
        var i: usize = 0;
        while (i < count) : (i += 1) slots[i].value.* = 0;
    }
};

pub fn nextCodepoint(s: []const u8, offset: usize) struct { cp: u21, len: usize } {
    if (offset >= s.len) return .{ .cp = 0, .len = 0 };
    const b = s[offset];
    const len: usize = std.unicode.utf8ByteSequenceLength(b) catch 1;
    if (offset + len > s.len) return .{ .cp = 0xFFFD, .len = 1 };
    const cp = std.unicode.utf8Decode(s[offset .. offset + len]) catch return .{ .cp = 0xFFFD, .len = 1 };
    return .{ .cp = cp, .len = len };
}

pub fn codepointCount(s: []const u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        const r = nextCodepoint(s, i);
        i += @max(1, r.len);
        n += 1;
    }
    return n;
}

pub fn utf8Encode(cp: u21, out: *[4]u8) usize {
    return std.unicode.utf8Encode(cp, out) catch 1;
}

test "color parse and contrast" {
    const c = try Color.parse("#ECEEF1");
    try std.testing.expectEqual(@as(u8, 0xEC), c.r);
    try std.testing.expect(Color.contrast(Color.white, Color.black) > 20);
}

test "hash is stable and nonzero mapped" {
    const a = hashBytes(0, "hello");
    const b = hashBytes(0, "hello");
    try std.testing.expectEqual(a, b);
    try std.testing.expectEqual(@as(u64, 1), @backingInt(WidgetId.fromHash(0)));
}

test "codepoint count" {
    try std.testing.expectEqual(@as(usize, 8), codepointCount("Hello 你好"));
}
