//! 绘制接口与软件光栅后端。
//!
//! 生产构建在 Windows 上由 NanoVG/OpenGL 实现同一 Canvas 接口；本仓库提供一个
//! 确定性的软件实现，使无头金图、单元测试与 Linux 开发宿主无需 GL 上下文即可
//! 得到逐像素可复现的结果。所有绘制在物理像素上完成，输入矩形为 lpx。

const std = @import("std");
const core = @import("core.zig");
const platform = @import("platform.zig");

pub const TextureId = enum(u32) { none = 0, _ };
pub const ImageId = enum(u32) { none = 0, _ };
pub const TextureFormat = enum { a8, rgba8 };
pub const TextureUsage = enum { dynamic, static };
pub const GlyphKind = enum { alpha, rgba };
pub const LineCap = enum { butt, round };
pub const LineJoin = enum { miter, round, bevel };
pub const ImageFilter = enum { linear, nearest };
pub const ImageState = enum { loading, ready, failed };
pub const ReadSource = enum { target, presented };

pub const GlyphQuad = struct {
    dst: core.RectI,
    src: core.RectI,
};

pub const ImageDrawOpts = struct {
    tint: ?core.Color = null,
    src: ?core.Rect = null,
    filter: ImageFilter = .linear,
};

pub const Pixels = struct {
    width: u32,
    height: u32,
    rgba: []u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Pixels) void {
        self.allocator.free(self.rgba);
        self.* = undefined;
    }
};

pub const DecodeError = error{ UnsupportedFormat, TooLarge, DecodeFailed, OutOfMemory };
pub const GfxError = error{ OutOfBounds, BufferTooSmall, TooLargeForSync, InvalidHandle, OutOfMemory };

/// 线程安全：无全局状态的可恢复解码入口（REQ-ARCH-008）。
pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) DecodeError!Pixels {
    if (bytes.len >= 8 and std.mem.eql(u8, bytes[0..8], "\x89PNG\r\n\x1a\n")) {
        return decodePng(allocator, bytes);
    }
    return error.UnsupportedFormat;
}

// ---------------------------------------------------------------------------
// 纹理与图像缓存
// ---------------------------------------------------------------------------

const Texture = struct {
    w: u32,
    h: u32,
    fmt: TextureFormat,
    data: std.ArrayListUnmanaged(u8) = .empty,
    used: bool = false,
};

var textures: [64]Texture = undefined;
var textures_init: bool = false;
var next_texture: u32 = 1;
var gfx_spin = std.atomic.Value(bool).init(false);

fn gfxLock() void {
    while (gfx_spin.swap(true, .acquire)) std.atomic.spinLoopHint();
}
fn gfxUnlock() void {
    gfx_spin.store(false, .release);
}

fn ensureTextures() void {
    if (textures_init) return;
    textures_init = true;
    for (&textures) |*t| t.* = .{ .w = 0, .h = 0, .fmt = .rgba8, .used = false };
}

pub fn createTexture(w: u32, h: u32, fmt: TextureFormat, usage: TextureUsage) GfxError!TextureId {
    _ = usage;
    gfxLock();
    defer gfxUnlock();
    ensureTextures();
    var i: usize = 0;
    while (i < textures.len) : (i += 1) {
        if (!textures[i].used) {
            const bpp: usize = if (fmt == .a8) 1 else 4;
            textures[i].used = true;
            textures[i].w = w;
            textures[i].h = h;
            textures[i].fmt = fmt;
            textures[i].data.clearRetainingCapacity();
            textures[i].data.appendNTimes(std.heap.page_allocator, 0, @as(usize, w) * h * bpp) catch return error.OutOfMemory;
            const id: u32 = next_texture;
            next_texture += 1;
            return @fromBackingInt(@intCast((id << 8) | @as(u32, @intCast(i + 1))));
        }
    }
    return error.OutOfMemory;
}

fn textureIndex(id: TextureId) ?usize {
    const v: u32 = @backingInt(id);
    if (v == 0) return null;
    const i = (v & 0xFF);
    if (i == 0 or i > textures.len) return null;
    return i - 1;
}

pub fn destroyTexture(id: TextureId) void {
    gfxLock();
    defer gfxUnlock();
    if (textureIndex(id)) |i| {
        textures[i].used = false;
        textures[i].data.clearRetainingCapacity();
    }
}

pub fn textureShadow(id: TextureId) GfxError![]u8 {
    if (textureIndex(id)) |i| {
        if (!textures[i].used) return error.InvalidHandle;
        return textures[i].data.items;
    }
    return error.InvalidHandle;
}

pub fn markDirty(_: TextureId, _: core.RectI) void {}
pub fn flushUploads() void {}

const ImageEntry = struct {
    key: u64,
    pixels: Pixels,
    id: ImageId,
    used: bool = false,
};

var images_buf: [32]ImageEntry = undefined;
var images_init: bool = false;
var next_image: u32 = 1;
var image_capacity: usize = 32 * 1024 * 1024;

fn ensureImages() void {
    if (images_init) return;
    images_init = true;
    for (&images_buf) |*e| e.* = .{ .key = 0, .pixels = undefined, .id = .none, .used = false };
}

pub const ImageKey = struct {
    hash: u64,

    pub fn fromPath(path: []const u8) ImageKey {
        return .{ .hash = core.hashBytes(0x9e3779b97f4a7c15, path) };
    }
    pub fn fromBytes(bytes: []const u8) ImageKey {
        return .{ .hash = core.hashBytes(0x123456789abcdef, bytes) };
    }
};

pub const ImageVariant = struct { key: ImageKey, scale_pct: u16 };
pub const ImageSet = union(enum) {
    variants: []const ImageVariant,
    single: struct { key: ImageKey, source_scale_pct: u16 },
};

pub const images = struct {
    pub fn setLoader(_: ?anyopaque) void {}
    pub fn request(_: ImageKey) ImageState {
        return .loading;
    }
    pub fn state(key: ImageKey) ImageState {
        gfxLock();
        defer gfxUnlock();
        ensureImages();
        for (&images_buf) |*e| {
            if (e.used and e.key == key.hash) return .ready;
        }
        return .failed;
    }
    pub fn id(key: ImageKey) ?ImageId {
        gfxLock();
        defer gfxUnlock();
        ensureImages();
        for (&images_buf) |*e| {
            if (e.used and e.key == key.hash) return e.id;
        }
        return null;
    }
    pub fn loadSync(key: ImageKey, bytes: []const u8) GfxError!ImageId {
        const pix = decode(std.heap.page_allocator, bytes) catch return error.InvalidHandle;
        return insert(key, pix, .{});
    }
    pub fn insert(key: ImageKey, pixels: Pixels, opts: struct { pinned: bool = false, mip: bool = false }) GfxError!ImageId {
        _ = opts;
        gfxLock();
        defer gfxUnlock();
        ensureImages();
        for (&images_buf) |*e| {
            if (!e.used) {
                e.* = .{ .key = key.hash, .pixels = pixels, .id = @fromBackingInt(@intCast(next_image)), .used = true };
                next_image += 1;
                return e.id;
            }
        }
        return error.OutOfMemory;
    }
    pub fn pick(set: ImageSet, scale: f32) ImageKey {
        const pct: u16 = @intFromFloat(@round(scale * 100));
        switch (set) {
            .single => |s| return s.key,
            .variants => |vs| {
                var best = vs[0];
                for (vs) |v| {
                    if (v.scale_pct <= pct and v.scale_pct >= best.scale_pct) best = v;
                }
                return best.key;
            },
        }
    }
    pub fn release(_: ImageKey) void {}
    pub fn forgetFailure(_: ImageKey) void {}
    pub fn clear() void {
        gfxLock();
        defer gfxUnlock();
        ensureImages();
        for (&images_buf) |*e| {
            if (e.used) {
                e.pixels.deinit();
                e.used = false;
            }
        }
    }
    pub fn setCapacity(bytes: usize) void {
        image_capacity = bytes;
    }
};

fn findImage(id: ImageId) ?*ImageEntry {
    ensureImages();
    for (&images_buf) |*e| {
        if (e.used and e.id == id) return e;
    }
    return null;
}

// ---------------------------------------------------------------------------
// Path
// ---------------------------------------------------------------------------

pub const PathBuilder = struct {
    points: [256]core.Vec2 = undefined,
    count: usize = 0,

    pub fn moveTo(self: *PathBuilder, p: core.Vec2) void {
        if (self.count >= self.points.len) return;
        self.points[self.count] = p;
        self.count += 1;
    }
    pub fn lineTo(self: *PathBuilder, p: core.Vec2) void {
        self.moveTo(p);
    }
    pub fn bezierTo(self: *PathBuilder, c1: core.Vec2, c2: core.Vec2, p: core.Vec2) void {
        const start = self.points[self.count - 1];
        var i: usize = 1;
        while (i <= 8) : (i += 1) {
            const t = @as(f32, @floatFromInt(i)) / 8.0;
            const mt = 1 - t;
            const x = mt * mt * mt * start.x + 3 * mt * mt * t * c1.x + 3 * mt * t * t * c2.x + t * t * t * p.x;
            const y = mt * mt * mt * start.y + 3 * mt * mt * t * c1.y + 3 * mt * t * t * c2.y + t * t * t * p.y;
            self.moveTo(.{ .x = x, .y = y });
        }
    }
    pub fn close(self: *PathBuilder) void {
        _ = self;
    }
};

// ---------------------------------------------------------------------------
// Canvas
// ---------------------------------------------------------------------------

pub const Canvas = struct {
    pixels: []u8,
    width: u32,
    height: u32,
    scale: f32 = 1.0,
    allocator: std.mem.Allocator,
    clip: core.RectI,
    clip_stack: [32]core.RectI = undefined,
    clip_depth: usize = 0,
    translate_x: f32 = 0,
    translate_y: f32 = 0,
    transform_stack: [32]struct { x: f32, y: f32 } = undefined,
    transform_depth: usize = 0,
    text_regions: std.ArrayListUnmanaged(core.RectI) = .empty,

    pub fn init(allocator: std.mem.Allocator, pixels: []u8, w: u32, h: u32, scale: f32) Canvas {
        return .{
            .pixels = pixels,
            .width = w,
            .height = h,
            .scale = scale,
            .allocator = allocator,
            .clip = .{ .x = 0, .y = 0, .w = @intCast(w), .h = @intCast(h) },
        };
    }

    pub fn deinit(self: *Canvas) void {
        self.text_regions.deinit(self.allocator);
    }

    fn px(self: *const Canvas, v: f32) f32 {
        return v * self.scale + self.translate_x;
    }
    fn py(self: *const Canvas, v: f32) f32 {
        return v * self.scale + self.translate_y;
    }
    fn toRectI(self: *const Canvas, r: core.Rect) core.RectI {
        const x0: i32 = @intFromFloat(@round(self.px(r.x)));
        const y0: i32 = @intFromFloat(@round(self.py(r.y)));
        const x1: i32 = @intFromFloat(@round(self.px(r.x + r.w)));
        const y1: i32 = @intFromFloat(@round(self.py(r.y + r.h)));
        return .{ .x = x0, .y = y0, .w = x1 - x0, .h = y1 - y0 };
    }

    fn putPixel(self: *Canvas, x: i32, y: i32, color: core.Color, coverage: f32) void {
        if (x < 0 or y < 0 or x >= @as(i32, @intCast(self.width)) or y >= @as(i32, @intCast(self.height))) return;
        if (!self.clip.contains(.{ .x = x, .y = y })) return;
        const idx: usize = (@as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x))) * 4;
        var c = color;
        if (coverage < 1.0) c.a = @intFromFloat(@round(@as(f32, @floatFromInt(c.a)) * coverage));
        if (c.a == 0) return;
        const dst = core.Color{ .r = self.pixels[idx], .g = self.pixels[idx + 1], .b = self.pixels[idx + 2], .a = self.pixels[idx + 3] };
        const out = core.Color.blend(c, dst);
        self.pixels[idx] = out.r;
        self.pixels[idx + 1] = out.g;
        self.pixels[idx + 2] = out.b;
        self.pixels[idx + 3] = out.a;
    }

    pub fn fillRect(self: *Canvas, r: core.Rect, color: core.Color) void {
        const ri = self.toRectI(r);
        if (ri.isEmpty()) return;
        const clipped = ri.intersect(self.clip);
        if (clipped.isEmpty()) return;
        var y = clipped.y;
        while (y < clipped.bottom()) : (y += 1) {
            var x = clipped.x;
            while (x < clipped.right()) : (x += 1) self.putPixel(x, y, color, 1.0);
        }
    }

    pub fn fillRectV(self: *Canvas, r: core.Rect, top: core.Color, bottom: core.Color) void {
        const ri = self.toRectI(r);
        if (ri.isEmpty()) return;
        const clipped = ri.intersect(self.clip);
        if (clipped.isEmpty()) return;
        var y = clipped.y;
        while (y < clipped.bottom()) : (y += 1) {
            const t = if (ri.h <= 1) 0.0 else @as(f32, @floatFromInt(y - ri.y)) + 0.5 / @as(f32, @floatFromInt(ri.h));
            const c = core.Color.lerp(top, bottom, t);
            var x = clipped.x;
            while (x < clipped.right()) : (x += 1) self.putPixel(x, y, c, 1.0);
        }
    }

    fn sdRoundRect(px_: f32, py_: f32, hw: f32, hh: f32, r: f32) f32 {
        const qx = @abs(px_) - hw + r;
        const qy = @abs(py_) - hh + r;
        const ax = @max(qx, 0);
        const ay = @max(qy, 0);
        return std.math.sqrt(ax * ax + ay * ay) + @min(@max(qx, qy), 0) - r;
    }

    pub fn fillRoundRect(self: *Canvas, r: core.Rect, radius: f32, color: core.Color) void {
        const ri = self.toRectI(r);
        if (ri.isEmpty()) return;
        const clipped = ri.intersect(self.clip);
        if (clipped.isEmpty()) return;
        const rr = @min(@as(f32, @floatFromInt(@min(ri.w, ri.h))) * 0.5, radius * self.scale);
        const cx = @as(f32, @floatFromInt(ri.x)) + @as(f32, @floatFromInt(ri.w)) * 0.5;
        const cy = @as(f32, @floatFromInt(ri.y)) + @as(f32, @floatFromInt(ri.h)) * 0.5;
        const hw = @as(f32, @floatFromInt(ri.w)) * 0.5;
        const hh = @as(f32, @floatFromInt(ri.h)) * 0.5;
        var y = clipped.y;
        while (y < clipped.bottom()) : (y += 1) {
            var x = clipped.x;
            while (x < clipped.right()) : (x += 1) {
                const d = sdRoundRect(@as(f32, @floatFromInt(x)) + 0.5 - cx, @as(f32, @floatFromInt(y)) + 0.5 - cy, hw, hh, rr);
                const cov = std.math.clamp(0.5 - d, 0, 1);
                if (cov > 0) self.putPixel(x, y, color, cov);
            }
        }
    }

    pub fn fillRoundRectV(self: *Canvas, r: core.Rect, radius: f32, top: core.Color, bottom: core.Color) void {
        const ri = self.toRectI(r);
        if (ri.isEmpty()) return;
        const clipped = ri.intersect(self.clip);
        if (clipped.isEmpty()) return;
        const rr = @min(@as(f32, @floatFromInt(@min(ri.w, ri.h))) * 0.5, radius * self.scale);
        const cx = @as(f32, @floatFromInt(ri.x)) + @as(f32, @floatFromInt(ri.w)) * 0.5;
        const cy = @as(f32, @floatFromInt(ri.y)) + @as(f32, @floatFromInt(ri.h)) * 0.5;
        const hw = @as(f32, @floatFromInt(ri.w)) * 0.5;
        const hh = @as(f32, @floatFromInt(ri.h)) * 0.5;
        var y = clipped.y;
        while (y < clipped.bottom()) : (y += 1) {
            const t = if (ri.h <= 1) 0.0 else @as(f32, @floatFromInt(y - ri.y)) + 0.5 / @as(f32, @floatFromInt(ri.h));
            const c = core.Color.lerp(top, bottom, t);
            var x = clipped.x;
            while (x < clipped.right()) : (x += 1) {
                const d = sdRoundRect(@as(f32, @floatFromInt(x)) + 0.5 - cx, @as(f32, @floatFromInt(y)) + 0.5 - cy, hw, hh, rr);
                const cov = std.math.clamp(0.5 - d, 0, 1);
                if (cov > 0) self.putPixel(x, y, c, cov);
            }
        }
    }

    pub fn strokeRect(self: *Canvas, r: core.Rect, color: core.Color, width_ppx: i32) void {
        const w: f32 = @floatFromInt(@max(1, width_ppx));
        const s = r;
        self.fillRect(.{ .x = s.x, .y = s.y, .w = s.w, .h = w / self.scale }, color);
        self.fillRect(.{ .x = s.x, .y = s.bottom() - w / self.scale, .w = s.w, .h = w / self.scale }, color);
        self.fillRect(.{ .x = s.x, .y = s.y, .w = w / self.scale, .h = s.h }, color);
        self.fillRect(.{ .x = s.right() - w / self.scale, .y = s.y, .w = w / self.scale, .h = s.h }, color);
    }

    pub fn strokeRoundRect(self: *Canvas, r: core.Rect, radius: f32, color: core.Color, width_ppx: i32) void {
        const ri = self.toRectI(r);
        if (ri.isEmpty()) return;
        const clipped = ri.intersect(self.clip);
        if (clipped.isEmpty()) return;
        const w = @as(f32, @floatFromInt(@max(1, width_ppx)));
        const rr = @min(@as(f32, @floatFromInt(@min(ri.w, ri.h))) * 0.5, radius * self.scale);
        const cx = @as(f32, @floatFromInt(ri.x)) + @as(f32, @floatFromInt(ri.w)) * 0.5;
        const cy = @as(f32, @floatFromInt(ri.y)) + @as(f32, @floatFromInt(ri.h)) * 0.5;
        const hw = @as(f32, @floatFromInt(ri.w)) * 0.5;
        const hh = @as(f32, @floatFromInt(ri.h)) * 0.5;
        var y = clipped.y;
        while (y < clipped.bottom()) : (y += 1) {
            var x = clipped.x;
            while (x < clipped.right()) : (x += 1) {
                const d = sdRoundRect(@as(f32, @floatFromInt(x)) + 0.5 - cx, @as(f32, @floatFromInt(y)) + 0.5 - cy, hw, hh, rr);
                const cov = std.math.clamp(w * 0.5 - @abs(d), 0, 1);
                if (cov > 0) self.putPixel(x, y, color, cov);
            }
        }
    }

    pub fn strokeLine(self: *Canvas, a: core.Vec2, b: core.Vec2, color: core.Color, width_ppx: i32) void {
        const ax = self.px(a.x);
        const ay = self.py(a.y);
        const bx = self.px(b.x);
        const by = self.py(b.y);
        const w = @as(f32, @floatFromInt(@max(1, width_ppx)));
        const minx: i32 = @intFromFloat(@floor(@min(ax, bx) - w));
        const maxx: i32 = @intFromFloat(@ceil(@max(ax, bx) + w));
        const miny: i32 = @intFromFloat(@floor(@min(ay, by) - w));
        const maxy: i32 = @intFromFloat(@ceil(@max(ay, by) + w));
        const dx = bx - ax;
        const dy = by - ay;
        const len2 = dx * dx + dy * dy;
        var y = @max(0, miny);
        while (y <= @min(@as(i32, @intCast(self.height)) - 1, maxy)) : (y += 1) {
            var x = @max(0, minx);
            while (x <= @min(@as(i32, @intCast(self.width)) - 1, maxx)) : (x += 1) {
                const px_ = @as(f32, @floatFromInt(x)) + 0.5;
                const py_ = @as(f32, @floatFromInt(y)) + 0.5;
                var t: f32 = 0;
                if (len2 > 0) t = std.math.clamp(((px_ - ax) * dx + (py_ - ay) * dy) / len2, 0, 1);
                const qx = ax + dx * t;
                const qy = ay + dy * t;
                const dist = std.math.sqrt((px_ - qx) * (px_ - qx) + (py_ - qy) * (py_ - qy));
                const cov = std.math.clamp(w * 0.5 + 0.5 - dist, 0, 1);
                if (cov > 0) self.putPixel(x, y, color, cov);
            }
        }
    }

    pub fn innerRadius(self: *const Canvas, outer_ppx: i32, width_ppx: i32) i32 {
        _ = self;
        return @max(0, outer_ppx - width_ppx);
    }

    pub fn path(self: *Canvas) PathBuilder {
        _ = self;
        return .{};
    }

    pub fn fillPath(self: *Canvas, p: *const PathBuilder, color: core.Color) void {
        if (p.count < 3) return;
        var miny: f32 = p.points[0].y;
        var maxy: f32 = p.points[0].y;
        var i: usize = 1;
        while (i < p.count) : (i += 1) {
            miny = @min(miny, p.points[i].y);
            maxy = @max(maxy, p.points[i].y);
        }
        const y0: i32 = @intFromFloat(@floor(self.py(miny)));
        const y1: i32 = @intFromFloat(@ceil(self.py(maxy)));
        var y = @max(0, y0);
        while (y <= @min(@as(i32, @intCast(self.height)) - 1, y1)) : (y += 1) {
            const scan_y = @as(f32, @floatFromInt(y)) + 0.5;
            var xs: [64]f32 = undefined;
            var n: usize = 0;
            var j: usize = 0;
            while (j < p.count and n < xs.len) : (j += 1) {
                const a = p.points[j];
                const b = p.points[(j + 1) % p.count];
                const ay = self.py(a.y);
                const by = self.py(b.y);
                if ((ay <= scan_y and by > scan_y) or (by <= scan_y and ay > scan_y)) {
                    const t = (scan_y - ay) / (by - ay);
                    xs[n] = self.px(a.x) + (self.px(b.x) - self.px(a.x)) * t;
                    n += 1;
                }
            }
            std.mem.sort(f32, xs[0..n], {}, std.sort.asc(f32));
            var k: usize = 0;
            while (k + 1 < n) : (k += 2) {
                const xa: i32 = @intFromFloat(@ceil(xs[k] - 0.5));
                const xb: i32 = @intFromFloat(@floor(xs[k + 1] - 0.5));
                var x = xa;
                while (x <= xb) : (x += 1) self.putPixel(x, y, color, 1.0);
            }
        }
    }

    pub fn strokePath(self: *Canvas, p: *const PathBuilder, color: core.Color, width_lpx: f32, cap: LineCap, join: LineJoin) void {
        _ = cap;
        _ = join;
        const w: i32 = @intFromFloat(@round(@max(1.0, width_lpx * self.scale)));
        var i: usize = 0;
        while (i + 1 < p.count) : (i += 1) self.strokeLine(p.points[i], p.points[i + 1], color, w);
    }

    pub fn pushClip(self: *Canvas, r: core.Rect) void {
        if (self.clip_depth >= self.clip_stack.len) return;
        self.clip_stack[self.clip_depth] = self.clip;
        self.clip_depth += 1;
        self.clip = self.clip.intersect(self.toRectI(r));
    }
    pub fn popClip(self: *Canvas) void {
        if (self.clip_depth == 0) return;
        self.clip_depth -= 1;
        self.clip = self.clip_stack[self.clip_depth];
    }
    pub fn pushTranslate(self: *Canvas, dx: f32, dy: f32) void {
        if (self.transform_depth < self.transform_stack.len) {
            self.transform_stack[self.transform_depth] = .{ .x = self.translate_x, .y = self.translate_y };
            self.transform_depth += 1;
        }
        self.translate_x += dx * self.scale;
        self.translate_y += dy * self.scale;
    }
    pub fn pushRotate(self: *Canvas, center: core.Vec2, radians: f32) void {
        _ = self;
        _ = center;
        _ = radians;
    }
    pub fn popTransform(self: *Canvas) void {
        if (self.transform_depth == 0) return;
        self.transform_depth -= 1;
        self.translate_x = self.transform_stack[self.transform_depth].x;
        self.translate_y = self.transform_stack[self.transform_depth].y;
    }

    pub fn drawImage(self: *Canvas, id: ImageId, dst: core.Rect, opts: ImageDrawOpts) bool {
        const e = findImage(id) orelse return false;
        const ri = self.toRectI(dst);
        var y = @max(0, ri.y);
        while (y < @min(@as(i32, @intCast(self.height)), ri.bottom())) : (y += 1) {
            var x = @max(0, ri.x);
            while (x < @min(@as(i32, @intCast(self.width)), ri.right())) : (x += 1) {
                const sx: usize = @intCast(@divTrunc(@as(i64, x - ri.x) * e.pixels.width, @as(i64, @max(1, ri.w))));
                const sy: usize = @intCast(@divTrunc(@as(i64, y - ri.y) * e.pixels.height, @as(i64, @max(1, ri.h))));
                if (sx >= e.pixels.width or sy >= e.pixels.height) continue;
                const idx = (sy * e.pixels.width + sx) * 4;
                var c = core.Color{ .r = e.pixels.rgba[idx], .g = e.pixels.rgba[idx + 1], .b = e.pixels.rgba[idx + 2], .a = e.pixels.rgba[idx + 3] };
                if (opts.tint) |t| c = .{ .r = c.r * t.r / 255, .g = c.g * t.g / 255, .b = c.b * t.b / 255, .a = c.a * t.a / 255 };
                self.putPixel(x, y, c, 1.0);
            }
        }
        return true;
    }

    pub fn drawGlyphQuads(self: *Canvas, tex: TextureId, kind: GlyphKind, quads: []const GlyphQuad, color: core.Color) void {
        _ = kind;
        const ti = textureIndex(tex) orelse return;
        const t = &textures[ti];
        if (!t.used) return;
        for (quads) |q| {
            if (q.dst.isEmpty()) continue;
            var y = q.dst.y;
            while (y < q.dst.bottom()) : (y += 1) {
                var x = q.dst.x;
                while (x < q.dst.right()) : (x += 1) {
                    const sx: u32 = @intCast(@as(i64, @divTrunc(@as(i64, x - q.dst.x) * q.src.w, @as(i64, @max(1, q.dst.w))) + q.src.x));
                    const sy: u32 = @intCast(@as(i64, @divTrunc(@as(i64, y - q.dst.y) * q.src.h, @as(i64, @max(1, q.dst.h))) + q.src.y));
                    if (sx >= t.w or sy >= t.h) continue;
                    const idx = (@as(usize, sy) * t.w + sx) * (if (t.fmt == .a8) @as(usize, 1) else 4);
                    const a: u8 = if (t.fmt == .a8) t.data.items[idx] else t.data.items[idx + 3];
                    if (a == 0) continue;
                    self.putPixel(x, y, color, @as(f32, @floatFromInt(a)) / 255.0);
                }
            }
            self.text_regions.append(self.allocator, q.dst) catch {};
        }
    }

    /// 内部：直接绘制一个 1bpp 字形位图（供确定性的 fixed 文字后端使用）。
    pub fn blitAlpha(self: *Canvas, x: i32, y: i32, w: i32, h: i32, bits: []const u8, color: core.Color) void {
        var yy: i32 = 0;
        while (yy < h) : (yy += 1) {
            var xx: i32 = 0;
            while (xx < w) : (xx += 1) {
                const bit_index: usize = @intCast(yy * w + xx);
                const byte = bits[bit_index / 8];
                const mask: u8 = @as(u8, 1) << @intCast(7 - (bit_index % 8));
                if (byte & mask != 0) self.putPixel(x + xx, y + yy, color, 1.0);
            }
        }
    }
};

// ---------------------------------------------------------------------------
// Surface
// ---------------------------------------------------------------------------

pub const Surface = struct {
    allocator: std.mem.Allocator,
    width: u32 = 0,
    height: u32 = 0,
    scale: f32 = 1.0,
    pixels: []u8 = &.{},
    presented: []u8 = &.{},
    canvas: ?Canvas = null,
    valid: bool = true,
    frame_active: bool = false,
    damage: core.RectI = .{},

    pub fn init(allocator: std.mem.Allocator, window: ?*platform.Window) GfxError!Surface {
        var s = Surface{ .allocator = allocator };
        if (window) |w| {
            s.width = @intCast(@max(0, w.client.w));
            s.height = @intCast(@max(0, w.client.h));
            s.scale = w.scale();
            try s.allocBuffers();
        }
        return s;
    }

    fn allocBuffers(self: *Surface) GfxError!void {
        if (self.width == 0 or self.height == 0) return;
        const n: usize = @as(usize, self.width) * self.height * 4;
        self.pixels = try self.allocator.alloc(u8, n);
        @memset(self.pixels, 0);
        self.presented = try self.allocator.alloc(u8, n);
        @memset(self.presented, 0);
    }

    pub fn deinit(self: *Surface) void {
        if (self.canvas) |*c| c.deinit();
        if (self.pixels.len > 0) self.allocator.free(self.pixels);
        if (self.presented.len > 0) self.allocator.free(self.presented);
        self.* = undefined;
    }

    pub fn resize(self: *Surface, client: platform.Size2i) void {
        const w: u32 = @intCast(@max(0, client.w));
        const h: u32 = @intCast(@max(0, client.h));
        if (w == self.width and h == self.height) return;
        if (self.pixels.len > 0) self.allocator.free(self.pixels);
        if (self.presented.len > 0) self.allocator.free(self.presented);
        self.width = w;
        self.height = h;
        self.pixels = &.{};
        self.presented = &.{};
        self.allocBuffers() catch {
            self.valid = false;
            return;
        };
        self.valid = false;
    }

    pub fn contentValid(self: *const Surface) bool {
        return self.valid;
    }
    pub fn invalidateContent(self: *Surface) void {
        self.valid = false;
    }

    pub fn beginFrame(self: *Surface, damage_in: core.RectI, scale: f32) *Canvas {
        self.scale = scale;
        self.damage = damage_in;
        if (self.canvas) |*c| c.deinit();
        self.canvas = Canvas.init(self.allocator, self.pixels, self.width, self.height, scale);
        const c = &self.canvas.?;
        c.clip = damage_in.intersect(.{ .x = 0, .y = 0, .w = @intCast(self.width), .h = @intCast(self.height) });
        self.frame_active = true;
        return c;
    }

    pub fn endFrame(self: *Surface) void {
        self.frame_active = false;
        self.valid = true;
    }

    pub fn present(self: *Surface) void {
        if (self.pixels.len > 0 and self.presented.len == self.pixels.len) @memcpy(self.presented, self.pixels);
    }

    pub fn readPixels(self: *Surface, rect: core.RectI, source: ReadSource, out: []u8) GfxError!void {
        const src = if (source == .target) self.pixels else self.presented;
        if (src.len == 0) return error.OutOfBounds;
        const r = rect.intersect(.{ .x = 0, .y = 0, .w = @intCast(self.width), .h = @intCast(self.height) });
        const need: usize = @as(usize, @intCast(r.w)) * @as(usize, @intCast(r.h)) * 4;
        if (out.len < need) return error.BufferTooSmall;
        var y: i32 = 0;
        while (y < r.h) : (y += 1) {
            const src_off: usize = (@as(usize, @intCast(r.y + y)) * self.width + @as(usize, @intCast(r.x))) * 4;
            const dst_off: usize = @as(usize, @intCast(y)) * @as(usize, @intCast(r.w)) * 4;
            @memcpy(out[dst_off .. dst_off + @as(usize, @intCast(r.w)) * 4], src[src_off .. src_off + @as(usize, @intCast(r.w)) * 4]);
        }
    }

    pub fn textRegions(self: *const Surface) []const core.RectI {
        if (self.canvas) |*c| return c.text_regions.items;
        return &.{};
    }
};

pub const testing = struct {
    pub fn textRegions(surface: *const Surface) []const core.RectI {
        return surface.textRegions();
    }
};

// ---------------------------------------------------------------------------
// PNG（无压缩 stored 块，供确定性的金图基准使用）
// ---------------------------------------------------------------------------

fn writeU32(out: *std.ArrayListUnmanaged(u8), gpa: std.mem.Allocator, v: u32) !void {
    var b: [4]u8 = undefined;
    std.mem.writeInt(u32, &b, v, .big);
    try out.appendSlice(gpa, &b);
}

pub fn encodePng(allocator: std.mem.Allocator, rgba: []const u8, w: u32, h: u32) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "\x89PNG\r\n\x1a\n");

    // IHDR
    var ihdr: [13]u8 = undefined;
    std.mem.writeInt(u32, ihdr[0..4], w, .big);
    std.mem.writeInt(u32, ihdr[4..8], h, .big);
    ihdr[8] = 8; // bit depth
    ihdr[9] = 6; // RGBA
    ihdr[10] = 0;
    ihdr[11] = 0;
    ihdr[12] = 0;
    try writeChunk(allocator, &out, "IHDR", &ihdr);

    // 原始扫描线（filter 0）
    const row_bytes: usize = @as(usize, w) * 4;
    const raw_len: usize = (row_bytes + 1) * h;
    const raw = try allocator.alloc(u8, raw_len);
    defer allocator.free(raw);
    var y: u32 = 0;
    while (y < h) : (y += 1) {
        raw[y * (row_bytes + 1)] = 0;
        @memcpy(raw[y * (row_bytes + 1) + 1 .. y * (row_bytes + 1) + 1 + row_bytes], rgba[y * row_bytes .. (y + 1) * row_bytes]);
    }

    // zlib: 头 + stored deflate 块 + adler32
    var z: std.ArrayListUnmanaged(u8) = .empty;
    defer z.deinit(allocator);
    try z.appendSlice(allocator, &.{ 0x78, 0x01 });
    var off: usize = 0;
    while (off < raw.len) {
        const n = @min(raw.len - off, 65535);
        const last: u8 = if (off + n >= raw.len) 1 else 0;
        try z.append(allocator, last);
        try z.append(allocator, @intCast(n & 0xFF));
        try z.append(allocator, @intCast((n >> 8) & 0xFF));
        try z.append(allocator, @intCast((~n) & 0xFF));
        try z.append(allocator, @intCast(((~n) >> 8) & 0xFF));
        try z.appendSlice(allocator, raw[off .. off + n]);
        off += n;
    }
    var adler: u32 = 1;
    var s1: u32 = 1;
    var s2: u32 = 0;
    for (raw) |b| {
        s1 = (s1 + b) % 65521;
        s2 = (s2 + s1) % 65521;
    }
    adler = (s2 << 16) | s1;
    try writeU32(&z, allocator, adler);

    try writeChunk(allocator, &out, "IDAT", z.items);
    try writeChunk(allocator, &out, "IEND", &.{});
    return out.toOwnedSlice(allocator);
}

fn writeChunk(allocator: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), kind: []const u8, data: []const u8) !void {
    try writeU32(out, allocator, @intCast(data.len));
    const start = out.items.len;
    try out.appendSlice(allocator, kind);
    try out.appendSlice(allocator, data);
    var crc = std.hash.Crc32.init();
    crc.update(out.items[start..]);
    try writeU32(out, allocator, crc.final());
}

pub fn decodePng(allocator: std.mem.Allocator, bytes: []const u8) DecodeError!Pixels {
    if (bytes.len < 8) return error.DecodeFailed;
    var pos: usize = 8;
    var w: u32 = 0;
    var h: u32 = 0;
    var idat: std.ArrayListUnmanaged(u8) = .empty;
    defer idat.deinit(allocator);
    var saw_end = false;
    while (pos + 12 <= bytes.len) {
        const len = std.mem.readInt(u32, bytes[pos .. pos + 4][0..4], .big);
        const kind = bytes[pos + 4 .. pos + 8];
        const data = bytes[pos + 8 .. pos + 8 + len];
        pos += 12 + len;
        if (std.mem.eql(u8, kind, "IHDR")) {
            if (data.len < 13) return error.DecodeFailed;
            w = std.mem.readInt(u32, data[0..4], .big);
            h = std.mem.readInt(u32, data[4..8], .big);
            if (data[8] != 8 or data[9] != 6) return error.UnsupportedFormat;
        } else if (std.mem.eql(u8, kind, "IDAT")) {
            try idat.appendSlice(allocator, data);
        } else if (std.mem.eql(u8, kind, "IEND")) {
            saw_end = true;
            break;
        }
    }
    if (!saw_end or w == 0 or h == 0) return error.DecodeFailed;
    if (idat.items.len < 6) return error.DecodeFailed;
    if (idat.items[0] != 0x78) return error.UnsupportedFormat;
    var raw = std.ArrayListUnmanaged(u8).empty;
    defer raw.deinit(allocator);
    var p: usize = 2;
    while (p + 5 <= idat.items.len) {
        const bfinal = idat.items[p] & 1;
        const btype = (idat.items[p] >> 1) & 3;
        if (btype != 0) return error.UnsupportedFormat;
        const n = @as(usize, idat.items[p + 1]) | (@as(usize, idat.items[p + 2]) << 8);
        if (p + 5 + n > idat.items.len) return error.DecodeFailed;
        try raw.appendSlice(allocator, idat.items[p + 5 .. p + 5 + n]);
        p += 5 + n;
        if (bfinal == 1) break;
    }
    const row_bytes: usize = @as(usize, w) * 4;
    if (raw.items.len < (row_bytes + 1) * h) return error.DecodeFailed;
    const out = try allocator.alloc(u8, row_bytes * h);
    errdefer allocator.free(out);
    var y: usize = 0;
    while (y < h) : (y += 1) {
        const filter = raw.items[y * (row_bytes + 1)];
        const src = raw.items[y * (row_bytes + 1) + 1 .. y * (row_bytes + 1) + 1 + row_bytes];
        const dst = out[y * row_bytes .. (y + 1) * row_bytes];
        const prev = if (y > 0) out[(y - 1) * row_bytes .. y * row_bytes] else null;
        var i: usize = 0;
        while (i < row_bytes) : (i += 1) {
            const a: u8 = if (i >= 4) dst[i - 4] else 0;
            const b: u8 = if (prev) |pv| pv[i] else 0;
            const c: u8 = if (prev != null and i >= 4) prev.?[i - 4] else 0;
            dst[i] = switch (filter) {
                0 => src[i],
                1 => src[i] +% a,
                2 => src[i] +% b,
                3 => src[i] +% @as(u8, @intCast((@as(u32, a) + b) / 2)),
                4 => src[i] +% paeth(a, b, c),
                else => return error.UnsupportedFormat,
            };
        }
    }
    return .{ .width = w, .height = h, .rgba = out, .allocator = allocator };
}

fn paeth(a: u8, b: u8, c: u8) u8 {
    const p = @as(i32, a) + @as(i32, b) - @as(i32, c);
    const pa = @abs(p - @as(i32, a));
    const pb = @abs(p - @as(i32, b));
    const pc = @abs(p - @as(i32, c));
    if (pa <= pb and pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
}

test "png roundtrip" {
    const gpa = std.testing.allocator;
    const w: u32 = 2;
    const h: u32 = 2;
    var rgba = [_]u8{ 255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255 };
    const png = try encodePng(gpa, &rgba, w, h);
    defer gpa.free(png);
    var pix = try decodePng(gpa, png);
    defer pix.deinit();
    try std.testing.expectEqualSlices(u8, &rgba, pix.rgba);
}

test "canvas fill" {
    var buf: [16]u8 = @splat(0);
    var c = Canvas.init(std.testing.allocator, &buf, 2, 2, 1);
    defer c.deinit();
    c.fillRect(.{ .x = 0, .y = 0, .w = 1, .h = 1 }, .{ .r = 255, .g = 0, .b = 0 });
    try std.testing.expectEqual(@as(u8, 255), buf[0]);
    try std.testing.expectEqual(@as(u8, 0), buf[4]);
}
