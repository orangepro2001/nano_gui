//! 绘制接口与软件光栅后端。
//!
//! 生产构建在 Windows 上由 NanoVG/OpenGL 实现同一 Canvas 接口；本仓库提供一个
//! 确定性的软件实现，使无头金图、单元测试与 Linux 开发宿主无需 GL 上下文即可
//! 得到逐像素可复现的结果。所有绘制在物理像素上完成，输入矩形为 lpx。

const std = @import("std");
const builtin = @import("builtin");
const core = @import("core.zig");
const platform = @import("platform.zig");

var gfx_allocator: std.mem.Allocator = std.heap.smp_allocator;

/// 注入持久分配器（由 App 在初始化时调用）。
pub fn init(allocator: std.mem.Allocator) void {
    gfx_allocator = allocator;
}

pub fn deinit() void {
    images.clear();
    gfxLock();
    defer gfxUnlock();
    if (textures_init) {
        for (&textures) |*t| {
            t.data.deinit(t.allocator);
            t.* = .{ .w = 0, .h = 0, .fmt = .rgba8, .used = false };
        }
    }
    textures_init = false;
    next_texture = 1;
    updateTextureStats();
}

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
    allocator: std.mem.Allocator = std.heap.smp_allocator,
    used: bool = false,
    dirty_rect: core.RectI = .{},
    has_dirty: bool = false,
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

fn updateTextureStats() void {
    var total: u64 = 0;
    if (textures_init) {
        for (&textures) |*t| {
            if (t.used) total += t.data.items.len;
        }
    }
    core.stats.gauge("gfx.texture_bytes").* = total;
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
            textures[i].allocator = gfx_allocator;
            textures[i].w = w;
            textures[i].h = h;
            textures[i].fmt = fmt;
            textures[i].data.clearRetainingCapacity();
            textures[i].data.appendNTimes(gfx_allocator, 0, @as(usize, w) * h * bpp) catch return error.OutOfMemory;
            const id: u32 = next_texture;
            next_texture += 1;
            updateTextureStats();
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
        textures[i].has_dirty = false;
        textures[i].data.clearRetainingCapacity();
        updateTextureStats();
    }
}

/// 立即释放纹理数据（字形图集等大缓冲使用）。
pub fn freeTexture(id: TextureId) void {
    gfxLock();
    defer gfxUnlock();
    if (textureIndex(id)) |i| {
        textures[i].data.deinit(textures[i].allocator);
        textures[i] = .{ .w = 0, .h = 0, .fmt = .rgba8, .used = false };
        updateTextureStats();
    }
}

pub fn textureShadow(id: TextureId) GfxError![]u8 {
    if (textureIndex(id)) |i| {
        if (!textures[i].used) return error.InvalidHandle;
        return textures[i].data.items;
    }
    return error.InvalidHandle;
}

/// 标记纹理脏矩形，供下次 flushUploads 统计与上传（REQ-GFX-027）。线程：界面线程。
pub fn markDirty(id: TextureId, rect: core.RectI) void {
    gfxLock();
    defer gfxUnlock();
    if (textureIndex(id)) |i| {
        if (!textures[i].used) return;
        const bounds = core.RectI{ .x = 0, .y = 0, .w = @intCast(textures[i].w), .h = @intCast(textures[i].h) };
        const clamped = rect.intersect(bounds);
        if (clamped.isEmpty()) return;
        if (textures[i].has_dirty) {
            textures[i].dirty_rect = textures[i].dirty_rect.unionWith(clamped);
        } else {
            textures[i].dirty_rect = clamped;
            textures[i].has_dirty = true;
        }
    }
}

/// 提交全部脏纹理上传并更新上传统计（REQ-GFX-027、REQ-GFX-042）。线程：界面线程。
pub fn flushUploads() void {
    gfxLock();
    defer gfxUnlock();
    if (!textures_init) return;
    for (&textures) |*t| {
        if (!t.used or !t.has_dirty) continue;
        const bpp: u64 = if (t.fmt == .a8) 1 else 4;
        const bytes: u64 = @as(u64, @intCast(@max(0, t.dirty_rect.w))) * @as(u64, @intCast(@max(0, t.dirty_rect.h))) * bpp;
        core.stats.counter("gfx.upload_calls").* += 1;
        core.stats.counter("gfx.upload_bytes").* += bytes;
        t.has_dirty = false;
        t.dirty_rect = .{};
    }
}

pub const ImageLoader = struct {
    ctx: *anyopaque,
    request: *const fn (ctx: *anyopaque, key: ImageKey) void,
    reset: *const fn (ctx: *anyopaque) void,
};

const ImageEntry = struct {
    key: u64,
    pixels: Pixels,
    id: ImageId,
    pinned: bool = false,
    refs: u32 = 0,
    last_use: u64 = 0,
    bytes: usize = 0,
};

var image_entries: std.ArrayListUnmanaged(ImageEntry) = .empty;
var image_failed: std.AutoHashMapUnmanaged(u64, void) = .empty;
var image_loading: std.AutoHashMapUnmanaged(u64, void) = .empty;
var image_loader: ?ImageLoader = null;
var next_image: u32 = 1;
var image_use_seq: u64 = 1;
var image_bytes_used: usize = 0;
var image_capacity: usize = 64 * 1024 * 1024;

fn updateImageStats() void {
    core.stats.gauge("cache.image.bytes").* = image_bytes_used;
    core.stats.gauge("gfx.image_cache_entries").* = image_entries.items.len;
}

fn evictImagesIfNeeded() void {
    while (image_bytes_used > image_capacity) {
        var best_idx: ?usize = null;
        var best_seq: u64 = std.math.maxInt(u64);
        for (image_entries.items, 0..) |e, idx| {
            if (e.pinned or e.refs > 0) continue;
            if (e.last_use < best_seq) {
                best_seq = e.last_use;
                best_idx = idx;
            }
        }
        const idx = best_idx orelse break;
        var removed = image_entries.orderedRemove(idx);
        image_bytes_used -|= removed.bytes;
        removed.pixels.deinit();
        core.stats.counter("gfx.image_evictions").* += 1;
    }
    updateImageStats();
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
    /// 设置异步图像加载器（REQ-GFX-031）。线程：界面线程。
    pub fn setLoader(loader: ?ImageLoader) void {
        gfxLock();
        defer gfxUnlock();
        image_loader = loader;
    }
    /// 请求图像：命中缓存返回 ready，已失败返回 failed，否则交给加载器并返回 loading（REQ-GFX-031）。线程：界面线程。
    pub fn request(key: ImageKey) ImageState {
        gfxLock();
        defer gfxUnlock();
        for (image_entries.items) |*e| {
            if (e.key == key.hash) {
                image_use_seq += 1;
                e.last_use = image_use_seq;
                return .ready;
            }
        }
        if (image_failed.contains(key.hash)) return .failed;
        if (image_loading.contains(key.hash)) return .loading;
        if (image_loader) |loader| {
            image_loading.put(gfx_allocator, key.hash, {}) catch {};
            core.stats.counter("gfx.image_load_requests").* += 1;
            gfxUnlock();
            loader.request(loader.ctx, key);
            gfxLock();
            for (image_entries.items) |*e| {
                if (e.key == key.hash) return .ready;
            }
            if (image_failed.contains(key.hash)) return .failed;
        }
        return .loading;
    }
    pub fn state(key: ImageKey) ImageState {
        gfxLock();
        defer gfxUnlock();
        for (image_entries.items) |e| {
            if (e.key == key.hash) return .ready;
        }
        if (image_loading.contains(key.hash)) return .loading;
        return .failed;
    }
    pub fn id(key: ImageKey) ?ImageId {
        gfxLock();
        defer gfxUnlock();
        for (image_entries.items) |*e| {
            if (e.key == key.hash) {
                image_use_seq += 1;
                e.last_use = image_use_seq;
                return e.id;
            }
        }
        return null;
    }
    pub fn loadSync(key: ImageKey, bytes: []const u8) GfxError!ImageId {
        const pix = decode(gfx_allocator, bytes) catch |err| {
            gfxLock();
            image_failed.put(gfx_allocator, key.hash, {}) catch {};
            _ = image_loading.remove(key.hash);
            core.stats.counter("gfx.image_failures").* += 1;
            gfxUnlock();
            return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                error.TooLarge => error.TooLargeForSync,
                else => error.InvalidHandle,
            };
        };
        return insert(key, pix, .{});
    }
    pub fn insert(key: ImageKey, pixels: Pixels, opts: struct { pinned: bool = false, mip: bool = false }) GfxError!ImageId {
        _ = opts.mip;
        gfxLock();
        defer gfxUnlock();
        _ = image_loading.remove(key.hash);
        _ = image_failed.remove(key.hash);
        for (image_entries.items) |*e| {
            if (e.key == key.hash) {
                image_bytes_used -|= e.bytes;
                e.pixels.deinit();
                e.pixels = pixels;
                e.bytes = pixels.rgba.len;
                e.pinned = opts.pinned;
                image_use_seq += 1;
                e.last_use = image_use_seq;
                image_bytes_used += e.bytes;
                evictImagesIfNeeded();
                return e.id;
            }
        }
        const img_id: ImageId = @fromBackingInt(@intCast(next_image));
        next_image += 1;
        image_use_seq += 1;
        const byte_len = pixels.rgba.len;
        image_entries.append(gfx_allocator, .{
            .key = key.hash,
            .pixels = pixels,
            .id = img_id,
            .pinned = opts.pinned,
            .last_use = image_use_seq,
            .bytes = byte_len,
        }) catch return error.OutOfMemory;
        image_bytes_used += byte_len;
        evictImagesIfNeeded();
        return img_id;
    }
    pub fn pick(set: ImageSet, scale: f32) ImageKey {
        const pct: u16 = @intFromFloat(@round(scale * 100));
        switch (set) {
            .single => |s| return s.key,
            .variants => |vs| {
                // REQ-GFX-034：取 scale_pct >= s 的最小档；不存在则取最大档。
                var best = vs[0];
                var found = false;
                for (vs) |v| {
                    if (v.scale_pct >= pct) {
                        if (!found or v.scale_pct < best.scale_pct) best = v;
                        found = true;
                    } else if (!found and v.scale_pct > best.scale_pct) {
                        best = v;
                    }
                }
                return best.key;
            },
        }
    }
    /// 返回图像源像素尺寸；不存在时返回 null（REQ-GFX-034）。线程：界面线程。
    pub fn size(img_id: ImageId) ?core.Size {
        gfxLock();
        defer gfxUnlock();
        const e = findImage(img_id) orelse return null;
        return .{ .w = @floatFromInt(e.pixels.width), .h = @floatFromInt(e.pixels.height) };
    }
    pub fn release(key: ImageKey) void {
        gfxLock();
        defer gfxUnlock();
        for (image_entries.items) |*e| {
            if (e.key == key.hash and e.refs > 0) e.refs -= 1;
        }
    }
    pub fn forgetFailure(key: ImageKey) void {
        gfxLock();
        defer gfxUnlock();
        _ = image_failed.remove(key.hash);
    }
    pub fn clear() void {
        gfxLock();
        defer gfxUnlock();
        for (image_entries.items) |*e| e.pixels.deinit();
        image_entries.deinit(gfx_allocator);
        image_entries = .empty;
        image_failed.deinit(gfx_allocator);
        image_failed = .empty;
        image_loading.deinit(gfx_allocator);
        image_loading = .empty;
        image_bytes_used = 0;
        updateImageStats();
    }
    pub fn setCapacity(bytes: usize) void {
        gfxLock();
        defer gfxUnlock();
        image_capacity = bytes;
        evictImagesIfNeeded();
    }
};

fn findImage(id: ImageId) ?*ImageEntry {
    for (image_entries.items) |*e| {
        if (e.id == id) return e;
    }
    return null;
}

// ---------------------------------------------------------------------------
// 矢量路径（Path）
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
// 画布（Canvas）
// ---------------------------------------------------------------------------

const nanovg = @import("gfx/nanovg.zig");
pub const GlHooks = nanovg.GlHooks;
pub const GlSurface = nanovg.GlSurface;

pub const Canvas = struct {
    gl: ?GlHooks = null,
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
    rotate_rad: f32 = 0,
    rotate_cx: f32 = 0,
    rotate_cy: f32 = 0,
    transform_stack: [32]struct { x: f32, y: f32, rot: f32, rcx: f32, rcy: f32 } = undefined,
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
    fn pxPt(self: *const Canvas, pt: core.Vec2) core.Vec2 {
        var x = pt.x * self.scale + self.translate_x;
        var y = pt.y * self.scale + self.translate_y;
        if (self.rotate_rad != 0) {
            const dx = x - self.rotate_cx;
            const dy = y - self.rotate_cy;
            const c = @cos(self.rotate_rad);
            const s = @sin(self.rotate_rad);
            x = self.rotate_cx + dx * c - dy * s;
            y = self.rotate_cy + dx * s + dy * c;
        }
        return .{ .x = x, .y = y };
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
        if (self.gl) |g| return g.fill_rect(g.ctx, r, color);
        if (color.a == 0) return;
        const ri = self.toRectI(r);
        if (ri.isEmpty()) return;
        const bounds = core.RectI{ .x = 0, .y = 0, .w = @intCast(self.width), .h = @intCast(self.height) };
        const clipped = ri.intersect(self.clip).intersect(bounds);
        if (clipped.isEmpty()) return;
        if (color.a == 255 and self.pixels.len >= @as(usize, self.width) * self.height * 4) {
            const packed_col: u32 = @bitCast(color);
            const px_u32: [*]u32 = @ptrCast(@alignCast(self.pixels.ptr));
            const x0: usize = @intCast(clipped.x);
            const x1: usize = @intCast(clipped.right());
            const w: usize = @intCast(self.width);
            var y = clipped.y;
            while (y < clipped.bottom()) : (y += 1) {
                const row_off = @as(usize, @intCast(y)) * w;
                @memset(px_u32[row_off + x0 .. row_off + x1], packed_col);
            }
            return;
        }
        var y = clipped.y;
        while (y < clipped.bottom()) : (y += 1) {
            var x = clipped.x;
            while (x < clipped.right()) : (x += 1) self.putPixel(x, y, color, 1.0);
        }
    }

    pub fn fillRectV(self: *Canvas, r: core.Rect, top: core.Color, bottom: core.Color) void {
        if (self.gl) |g| return g.fill_rect_v(g.ctx, r, top, bottom);
        const ri = self.toRectI(r);
        if (ri.isEmpty()) return;
        const clipped = ri.intersect(self.clip);
        if (clipped.isEmpty()) return;
        var y = clipped.y;
        while (y < clipped.bottom()) : (y += 1) {
            // 顶行取起点色，底行取终点色（REQ-GFX-011）。
            const t = if (ri.h <= 1) 0.0 else @as(f32, @floatFromInt(y - ri.y)) / @as(f32, @floatFromInt(ri.h - 1));
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
        if (self.gl) |g| return g.fill_round_rect(g.ctx, r, radius, color);
        const ri = self.toRectI(r);
        if (ri.isEmpty()) return;
        const clipped = ri.intersect(self.clip);
        if (clipped.isEmpty()) return;
        const rr = @min(@as(f32, @floatFromInt(@min(ri.w, ri.h))) * 0.5, radius * self.scale);
        const cx = @as(f32, @floatFromInt(ri.x)) + @as(f32, @floatFromInt(ri.w)) * 0.5;
        const cy = @as(f32, @floatFromInt(ri.y)) + @as(f32, @floatFromInt(ri.h)) * 0.5;
        const hw = @as(f32, @floatFromInt(ri.w)) * 0.5;
        const hh = @as(f32, @floatFromInt(ri.h)) * 0.5;
        const corner_x0 = @as(f32, @floatFromInt(ri.x)) + rr;
        const corner_x1 = @as(f32, @floatFromInt(ri.right())) - rr;
        const corner_y0 = @as(f32, @floatFromInt(ri.y)) + rr;
        const corner_y1 = @as(f32, @floatFromInt(ri.bottom())) - rr;
        const inner_x0: i32 = @max(clipped.x, @as(i32, @intFromFloat(@ceil(corner_x0))));
        const inner_x1: i32 = @min(clipped.right(), @as(i32, @intFromFloat(@floor(corner_x1))));
        var y = clipped.y;
        while (y < clipped.bottom()) : (y += 1) {
            const fy = @as(f32, @floatFromInt(y)) + 0.5;
            const in_flat_y = fy >= corner_y0 and fy <= corner_y1;
            if (in_flat_y and color.a == 255 and self.pixels.len >= @as(usize, self.width) * self.height * 4) {
                const packed_col: u32 = @bitCast(color);
                const px_u32: [*]u32 = @ptrCast(@alignCast(self.pixels.ptr));
                const row_off = @as(usize, @intCast(y)) * @as(usize, self.width);
                @memset(px_u32[row_off + @as(usize, @intCast(clipped.x)) .. row_off + @as(usize, @intCast(clipped.right()))], packed_col);
                continue;
            }
            var x = clipped.x;
            while (x < clipped.right()) : (x += 1) {
                if (in_flat_y or (x >= inner_x0 and x < inner_x1)) {
                    self.putPixel(x, y, color, 1.0);
                    continue;
                }
                const d = sdRoundRect(@as(f32, @floatFromInt(x)) + 0.5 - cx, fy - cy, hw, hh, rr);
                const cov = std.math.clamp(0.5 - d, 0, 1);
                if (cov > 0) self.putPixel(x, y, color, cov);
            }
        }
    }

    pub fn fillRoundRectV(self: *Canvas, r: core.Rect, radius: f32, top: core.Color, bottom: core.Color) void {
        if (self.gl) |g| return g.fill_round_rect_v(g.ctx, r, radius, top, bottom);
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
            // 顶行取起点色，底行取终点色（REQ-GFX-011）。
            const t = if (ri.h <= 1) 0.0 else @as(f32, @floatFromInt(y - ri.y)) / @as(f32, @floatFromInt(ri.h - 1));
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
        if (self.gl) |g| return g.stroke_rect(g.ctx, r, color, width_ppx);
        const w: f32 = @floatFromInt(@max(1, width_ppx));
        const s = r;
        self.fillRect(.{ .x = s.x, .y = s.y, .w = s.w, .h = w / self.scale }, color);
        self.fillRect(.{ .x = s.x, .y = s.bottom() - w / self.scale, .w = s.w, .h = w / self.scale }, color);
        self.fillRect(.{ .x = s.x, .y = s.y, .w = w / self.scale, .h = s.h }, color);
        self.fillRect(.{ .x = s.right() - w / self.scale, .y = s.y, .w = w / self.scale, .h = s.h }, color);
    }

    pub fn strokeRoundRect(self: *Canvas, r: core.Rect, radius: f32, color: core.Color, width_ppx: i32) void {
        if (self.gl) |g| return g.stroke_round_rect(g.ctx, r, radius, color, width_ppx);
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
        const pad_w: i32 = @intFromFloat(@ceil(w * 0.5 + 1.0));
        const corner_y0 = @as(f32, @floatFromInt(ri.y)) + rr + w * 0.5 + 1.0;
        const corner_y1 = @as(f32, @floatFromInt(ri.bottom())) - rr - w * 0.5 - 1.0;
        const hole_x0 = @max(clipped.x, ri.x + pad_w);
        const hole_x1 = @min(clipped.right(), ri.right() - pad_w);
        var y = clipped.y;
        while (y < clipped.bottom()) : (y += 1) {
            const fy = @as(f32, @floatFromInt(y)) + 0.5;
            if (fy >= corner_y0 and fy <= corner_y1 and hole_x0 < hole_x1) {
                var x = clipped.x;
                while (x < hole_x0) : (x += 1) {
                    const d = sdRoundRect(@as(f32, @floatFromInt(x)) + 0.5 - cx, fy - cy, hw, hh, rr);
                    const cov = std.math.clamp(w * 0.5 - @abs(d), 0, 1);
                    if (cov > 0) self.putPixel(x, y, color, cov);
                }
                x = hole_x1;
                while (x < clipped.right()) : (x += 1) {
                    const d = sdRoundRect(@as(f32, @floatFromInt(x)) + 0.5 - cx, fy - cy, hw, hh, rr);
                    const cov = std.math.clamp(w * 0.5 - @abs(d), 0, 1);
                    if (cov > 0) self.putPixel(x, y, color, cov);
                }
                continue;
            }
            var x = clipped.x;
            while (x < clipped.right()) : (x += 1) {
                const d = sdRoundRect(@as(f32, @floatFromInt(x)) + 0.5 - cx, fy - cy, hw, hh, rr);
                const cov = std.math.clamp(w * 0.5 - @abs(d), 0, 1);
                if (cov > 0) self.putPixel(x, y, color, cov);
            }
        }
    }

    pub fn strokeLine(self: *Canvas, a: core.Vec2, b: core.Vec2, color: core.Color, width_ppx: i32) void {
        if (self.gl) |g| return g.stroke_line(g.ctx, a, b, color, width_ppx);
        const pa = self.pxPt(a);
        const pb = self.pxPt(b);
        const ax = pa.x;
        const ay = pa.y;
        const bx = pb.x;
        const by = pb.y;
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
        var miny: f32 = self.pxPt(p.points[0]).y;
        var maxy: f32 = miny;
        var i: usize = 1;
        while (i < p.count) : (i += 1) {
            const tp = self.pxPt(p.points[i]);
            miny = @min(miny, tp.y);
            maxy = @max(maxy, tp.y);
        }
        const y0: i32 = @intFromFloat(@floor(miny));
        const y1: i32 = @intFromFloat(@ceil(maxy));
        var y = @max(0, y0);
        while (y <= @min(@as(i32, @intCast(self.height)) - 1, y1)) : (y += 1) {
            const scan_y = @as(f32, @floatFromInt(y)) + 0.5;
            var xs: [64]f32 = undefined;
            var n: usize = 0;
            var j: usize = 0;
            while (j < p.count and n < xs.len) : (j += 1) {
                const a = self.pxPt(p.points[j]);
                const b = self.pxPt(p.points[(j + 1) % p.count]);
                const ay = a.y;
                const by = b.y;
                if ((ay <= scan_y and by > scan_y) or (by <= scan_y and ay > scan_y)) {
                    const t = (scan_y - ay) / (by - ay);
                    xs[n] = a.x + (b.x - a.x) * t;
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
        if (self.gl != null) {
            const w: i32 = @intFromFloat(@round(@max(1.0, width_lpx * self.scale)));
            var i: usize = 0;
            while (i + 1 < p.count) : (i += 1) self.strokeLine(p.points[i], p.points[i + 1], color, w);
            return;
        }
        _ = cap;
        _ = join;
        const w: i32 = @intFromFloat(@round(@max(1.0, width_lpx * self.scale)));
        var i: usize = 0;
        while (i + 1 < p.count) : (i += 1) self.strokeLine(p.points[i], p.points[i + 1], color, w);
    }

    pub fn pushClip(self: *Canvas, r: core.Rect) void {
        if (self.gl) |g| return g.push_clip(g.ctx, r);
        if (self.clip_depth >= self.clip_stack.len) return;
        self.clip_stack[self.clip_depth] = self.clip;
        self.clip_depth += 1;
        self.clip = self.clip.intersect(self.toRectI(r));
    }
    pub fn popClip(self: *Canvas) void {
        if (self.gl) |g| return g.pop_clip(g.ctx);
        if (self.clip_depth == 0) return;
        self.clip_depth -= 1;
        self.clip = self.clip_stack[self.clip_depth];
    }
    pub fn pushTranslate(self: *Canvas, dx: f32, dy: f32) void {
        if (self.gl) |g| return g.push_translate(g.ctx, dx, dy);
        if (self.transform_depth < self.transform_stack.len) {
            self.transform_stack[self.transform_depth] = .{ .x = self.translate_x, .y = self.translate_y, .rot = self.rotate_rad, .rcx = self.rotate_cx, .rcy = self.rotate_cy };
            self.transform_depth += 1;
        }
        self.translate_x += dx * self.scale;
        self.translate_y += dy * self.scale;
    }
    /// 绕指定中心点（lpx）压入旋转变换。线程：界面线程。
    pub fn pushRotate(self: *Canvas, center: core.Vec2, radians: f32) void {
        if (self.transform_depth < self.transform_stack.len) {
            self.transform_stack[self.transform_depth] = .{ .x = self.translate_x, .y = self.translate_y, .rot = self.rotate_rad, .rcx = self.rotate_cx, .rcy = self.rotate_cy };
            self.transform_depth += 1;
        }
        self.rotate_cx = self.px(center.x);
        self.rotate_cy = self.py(center.y);
        self.rotate_rad += radians;
    }
    pub fn popTransform(self: *Canvas) void {
        if (self.gl) |g| return g.pop_transform(g.ctx);
        if (self.transform_depth == 0) return;
        self.transform_depth -= 1;
        const st = self.transform_stack[self.transform_depth];
        self.translate_x = st.x;
        self.translate_y = st.y;
        self.rotate_rad = st.rot;
        self.rotate_cx = st.rcx;
        self.rotate_cy = st.rcy;
    }

    pub fn drawImage(self: *Canvas, id: ImageId, dst: core.Rect, opts: ImageDrawOpts) bool {
        gfxLock();
        const e_copy = if (findImage(id)) |e| blk: {
            image_use_seq += 1;
            e.last_use = image_use_seq;
            break :blk e.pixels;
        } else {
            gfxUnlock();
            return false;
        };
        gfxUnlock();
        const ri = self.toRectI(dst);
        if (ri.isEmpty() or e_copy.width == 0 or e_copy.height == 0) return false;
        const src_r = opts.src orelse core.Rect{ .x = 0, .y = 0, .w = @floatFromInt(e_copy.width), .h = @floatFromInt(e_copy.height) };
        const sx0 = std.math.clamp(src_r.x, 0, @as(f32, @floatFromInt(e_copy.width)));
        const sy0 = std.math.clamp(src_r.y, 0, @as(f32, @floatFromInt(e_copy.height)));
        const sw = std.math.clamp(src_r.w, 0, @as(f32, @floatFromInt(e_copy.width)) - sx0);
        const sh = std.math.clamp(src_r.h, 0, @as(f32, @floatFromInt(e_copy.height)) - sy0);
        if (sw <= 0 or sh <= 0) return false;

        var y = @max(0, ri.y);
        while (y < @min(@as(i32, @intCast(self.height)), ri.bottom())) : (y += 1) {
            const v = (@as(f32, @floatFromInt(y - ri.y)) + 0.5) / @as(f32, @floatFromInt(@max(1, ri.h)));
            var x = @max(0, ri.x);
            while (x < @min(@as(i32, @intCast(self.width)), ri.right())) : (x += 1) {
                const u = (@as(f32, @floatFromInt(x - ri.x)) + 0.5) / @as(f32, @floatFromInt(@max(1, ri.w)));
                const fx = sx0 + u * sw;
                const fy = sy0 + v * sh;
                var c = switch (opts.filter) {
                    .nearest => sampleNearest(e_copy, fx, fy),
                    .linear => sampleBilinear(e_copy, fx, fy),
                };
                if (opts.tint) |t| c = .{ .r = tintMul(c.r, t.r), .g = tintMul(c.g, t.g), .b = tintMul(c.b, t.b), .a = tintMul(c.a, t.a) };
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

    /// 按覆盖率混合一个像素；供 fontstash 字形位图等外部栅格使用。
    pub fn blendPixel(self: *Canvas, x: i32, y: i32, color: core.Color, coverage: f32) void {
        if (self.gl) |g| {
            var c = color;
            c.a = @intFromFloat(@round(@as(f32, @floatFromInt(c.a)) * coverage));
            return g.fill_rect(g.ctx, .{ .x = @floatFromInt(x), .y = @floatFromInt(y), .w = 1, .h = 1 }, c);
        }
        self.putPixel(x, y, color, coverage);
    }

    /// 按一个像素混合颜色；供 DirectWrite 字形位图等外部栅格使用。
    pub fn blitPixel(self: *Canvas, x: f32, y: f32, color: core.Color) void {
        if (self.gl) |g| return g.fill_rect(g.ctx, .{ .x = x, .y = y, .w = 1, .h = 1 }, color);
        const ix: i32 = @intFromFloat(@round(x));
        const iy: i32 = @intFromFloat(@round(y));
        self.putPixel(ix, iy, color, 1.0);
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
// 绘制表面（Surface）
// ---------------------------------------------------------------------------

pub const Surface = struct {
    allocator: std.mem.Allocator,
    width: u32 = 0,
    height: u32 = 0,
    scale: f32 = 1.0,
    pixels: []u8 = &.{},
    presented: []u8 = &.{},
    canvas: ?Canvas = null,
    gl: ?GlSurface = null,
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

    /// 使用 NanoVG/GL 后端的表面；持久离屏目标由后端上下文（gl.ctx）持有。
    pub fn initGl(allocator: std.mem.Allocator, w: u32, h: u32, scale: f32, gl: GlSurface) Surface {
        return .{ .allocator = allocator, .width = w, .height = h, .scale = scale, .gl = gl };
    }

    /// 平台窗口的后端选择：Windows 优先 NanoVG/GL3，失败回退软件栅格。
    pub fn initForWindow(allocator: std.mem.Allocator, window: *platform.Window) GfxError!Surface {
        if (nanovg.tryInitWin32Surface(window)) |gl_surf| {
            return initGl(allocator, @intCast(@max(0, window.client.w)), @intCast(@max(0, window.client.h)), window.scale(), gl_surf);
        }
        return Surface.init(allocator, window);
    }

    fn allocBuffers(self: *Surface) GfxError!void {
        if (self.width == 0 or self.height == 0) return;
        const n: usize = @as(usize, self.width) * self.height * 4;
        // 软件离屏表面等价于 GPU 帧缓冲，不计入框架 CPU 持久内存（REQ-PERF-027）。
        self.pixels = std.heap.smp_allocator.alloc(u8, n) catch return error.OutOfMemory;
        @memset(self.pixels, 0);
        self.presented = std.heap.smp_allocator.alloc(u8, n) catch return error.OutOfMemory;
        @memset(self.presented, 0);
    }

    pub fn deinit(self: *Surface) void {
        if (self.canvas) |*c| c.deinit();
        if (self.gl) |g| if (g.deinit) |d| d(g.ctx);
        if (self.pixels.len > 0) std.heap.smp_allocator.free(self.pixels);
        if (self.presented.len > 0) std.heap.smp_allocator.free(self.presented);
        self.* = undefined;
    }

    pub fn resize(self: *Surface, client: platform.Size2i) void {
        const w: u32 = @intCast(@max(0, client.w));
        const h: u32 = @intCast(@max(0, client.h));
        if (w == self.width and h == self.height) return;
        if (self.gl) |g| {
            self.width = w;
            self.height = h;
            if (g.resize) |r| r(g.ctx, w, h, self.scale);
            self.valid = false;
            return;
        }
        if (self.pixels.len > 0) std.heap.smp_allocator.free(self.pixels);
        if (self.presented.len > 0) std.heap.smp_allocator.free(self.presented);
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
        if (scale != self.scale) self.valid = false;
        self.scale = scale;
        const full = core.RectI{ .x = 0, .y = 0, .w = @intCast(self.width), .h = @intCast(self.height) };
        if (!self.valid) {
            // 内容已失效时必须整根重绘（REQ-GFX-004）；调试构建断言调用方遵守。
            std.debug.assert(damage_in.w == full.w and damage_in.h == full.h and damage_in.x == 0 and damage_in.y == 0);
            self.damage = full;
        } else self.damage = damage_in;
        if (self.canvas) |*old| old.deinit();
        if (self.gl) |g| {
            g.begin(g.ctx, damage_in, scale);
            self.canvas = Canvas.init(self.allocator, &.{}, self.width, self.height, scale);
            const c = &self.canvas.?;
            c.gl = g.canvas;
            c.clip = self.damage.intersect(.{ .x = 0, .y = 0, .w = @intCast(self.width), .h = @intCast(self.height) });
            self.frame_active = true;
            return c;
        }
        self.canvas = Canvas.init(self.allocator, self.pixels, self.width, self.height, scale);
        const c = &self.canvas.?;
        c.clip = self.damage.intersect(.{ .x = 0, .y = 0, .w = @intCast(self.width), .h = @intCast(self.height) });
        self.frame_active = true;
        return c;
    }

    pub fn endFrame(self: *Surface) void {
        if (self.gl) |g| g.end(g.ctx);
        self.frame_active = false;
    }

    pub fn present(self: *Surface) void {
        if (self.gl) |g| {
            core.stats.counter("frame.gl_draw_calls").* += 1;
            g.present(g.ctx);
            self.valid = true;
            return;
        }
        core.stats.counter("frame.gl_draw_calls").* += 0;
        if (self.pixels.len > 0 and self.presented.len == self.pixels.len) {
            const full = core.RectI{ .x = 0, .y = 0, .w = @intCast(self.width), .h = @intCast(self.height) };
            const r = if (self.valid) self.damage.intersect(full) else full;
            if (!self.valid or (r.x == 0 and r.y == 0 and r.w == full.w and r.h == full.h)) {
                @memcpy(self.presented, self.pixels);
            } else if (!r.isEmpty()) {
                const stride = @as(usize, self.width) * 4;
                const x0 = @as(usize, @intCast(r.x)) * 4;
                const row_bytes = @as(usize, @intCast(r.w)) * 4;
                var y: i32 = r.y;
                while (y < r.bottom()) : (y += 1) {
                    const off = @as(usize, @intCast(y)) * stride + x0;
                    @memcpy(self.presented[off .. off + row_bytes], self.pixels[off .. off + row_bytes]);
                }
            }
        }
        self.valid = true;
    }

    pub fn readPixels(self: *Surface, rect: core.RectI, source: ReadSource, out: []u8) GfxError!void {
        if (self.gl) |g| {
            if (g.read) |r| {
                if (r(g.ctx, rect, out)) return;
            }
            return error.OutOfBounds;
        }
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

    // PNG 图像头块（IHDR）
    var ihdr: [13]u8 = undefined;
    std.mem.writeInt(u32, ihdr[0..4], w, .big);
    std.mem.writeInt(u32, ihdr[4..8], h, .big);
    ihdr[8] = 8; // 每通道位深
    ihdr[9] = 6; // 色彩类型 RGBA
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

fn sampleNearest(pix: Pixels, fx: f32, fy: f32) core.Color {
    const sx: usize = @intCast(std.math.clamp(@as(i32, @intFromFloat(@floor(fx))), 0, @as(i32, @intCast(pix.width)) - 1));
    const sy: usize = @intCast(std.math.clamp(@as(i32, @intFromFloat(@floor(fy))), 0, @as(i32, @intCast(pix.height)) - 1));
    const idx = (sy * pix.width + sx) * 4;
    return .{ .r = pix.rgba[idx], .g = pix.rgba[idx + 1], .b = pix.rgba[idx + 2], .a = pix.rgba[idx + 3] };
}

fn sampleBilinear(pix: Pixels, fx: f32, fy: f32) core.Color {
    const ux = std.math.clamp(fx - 0.5, 0, @as(f32, @floatFromInt(pix.width - 1)));
    const uy = std.math.clamp(fy - 0.5, 0, @as(f32, @floatFromInt(pix.height - 1)));
    const x0: usize = @intFromFloat(@floor(ux));
    const y0: usize = @intFromFloat(@floor(uy));
    const x1 = @min(pix.width - 1, x0 + 1);
    const y1 = @min(pix.height - 1, y0 + 1);
    const tx = ux - @as(f32, @floatFromInt(x0));
    const ty = uy - @as(f32, @floatFromInt(y0));
    const c00 = sampleNearest(pix, @floatFromInt(x0), @floatFromInt(y0));
    const c10 = sampleNearest(pix, @floatFromInt(x1), @floatFromInt(y0));
    const c01 = sampleNearest(pix, @floatFromInt(x0), @floatFromInt(y1));
    const c11 = sampleNearest(pix, @floatFromInt(x1), @floatFromInt(y1));
    const top = core.Color.lerp(c00, c10, tx);
    const bot = core.Color.lerp(c01, c11, tx);
    return core.Color.lerp(top, bot, ty);
}

/// 逐通道着色相乘（先提升到 u16 避免 u8 溢出），带四舍五入。
fn tintMul(a: u8, b: u8) u8 {
    return @intCast((@as(u16, a) * @as(u16, b) + 127) / 255);
}

pub fn decodePng(allocator: std.mem.Allocator, bytes: []const u8) DecodeError!Pixels {
    if (bytes.len < 8) return error.DecodeFailed;
    var pos: usize = 8;
    var w: u32 = 0;
    var h: u32 = 0;
    var color_type: u8 = 0;
    var idat: std.ArrayListUnmanaged(u8) = .empty;
    defer idat.deinit(allocator);
    var plte: [256 * 3]u8 = @splat(0);
    var plte_len: usize = 0;
    var trns: [256]u8 = @splat(255);
    var saw_end = false;
    while (pos + 12 <= bytes.len) {
        const len = std.mem.readInt(u32, bytes[pos .. pos + 4][0..4], .big);
        const kind = bytes[pos + 4 .. pos + 8];
        // chunk 长度不得超出剩余数据（含 4 字节 CRC）。
        if (@as(u64, len) + 12 > bytes.len - pos) return error.DecodeFailed;
        const data = bytes[pos + 8 .. pos + 8 + len];
        pos += 12 + @as(usize, len);
        if (std.mem.eql(u8, kind, "IHDR")) {
            if (data.len < 13) return error.DecodeFailed;
            w = std.mem.readInt(u32, data[0..4], .big);
            h = std.mem.readInt(u32, data[4..8], .big);
            const bit_depth = data[8];
            color_type = data[9];
            const interlace = data[12];
            if (bit_depth != 8 or interlace != 0) return error.UnsupportedFormat;
            if (color_type != 0 and color_type != 2 and color_type != 3 and color_type != 4 and color_type != 6) return error.UnsupportedFormat;
            // 先查尺寸再分配（REQ-GFX-030）。
            if (w == 0 or h == 0) return error.DecodeFailed;
            if (w > 16384 or h > 16384 or @as(u64, w) * h > 64 * 1024 * 1024) return error.TooLarge;
        } else if (std.mem.eql(u8, kind, "PLTE")) {
            const n = @min(data.len, plte.len);
            @memcpy(plte[0..n], data[0..n]);
            plte_len = n / 3;
        } else if (std.mem.eql(u8, kind, "tRNS")) {
            const n = @min(data.len, trns.len);
            @memcpy(trns[0..n], data[0..n]);
        } else if (std.mem.eql(u8, kind, "IDAT")) {
            try idat.appendSlice(allocator, data);
        } else if (std.mem.eql(u8, kind, "IEND")) {
            saw_end = true;
            break;
        }
    }
    if (!saw_end or w == 0 or h == 0) return error.DecodeFailed;
    if (idat.items.len < 6) return error.DecodeFailed;
    const bpp: usize = switch (color_type) {
        0, 3 => 1,
        4 => 2,
        2 => 3,
        6 => 4,
        else => return error.UnsupportedFormat,
    };
    const row_bytes: usize = @as(usize, w) * bpp;
    const expected_raw: usize = (row_bytes + 1) * h;

    var in_r = std.Io.Reader.fixed(idat.items);
    var decomp = std.compress.flate.Decompress.init(&in_r, .zlib, &.{});
    const raw = decomp.reader.allocRemaining(allocator, .limited(expected_raw + 64)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.DecodeFailed,
    };
    defer allocator.free(raw);
    if (raw.len < expected_raw) return error.DecodeFailed;

    const unfiltered = try allocator.alloc(u8, row_bytes * h);
    defer allocator.free(unfiltered);
    var y: usize = 0;
    while (y < h) : (y += 1) {
        const filter = raw[y * (row_bytes + 1)];
        const src = raw[y * (row_bytes + 1) + 1 .. y * (row_bytes + 1) + 1 + row_bytes];
        const dst = unfiltered[y * row_bytes .. (y + 1) * row_bytes];
        const prev = if (y > 0) unfiltered[(y - 1) * row_bytes .. y * row_bytes] else null;
        var i: usize = 0;
        while (i < row_bytes) : (i += 1) {
            const a: u8 = if (i >= bpp) dst[i - bpp] else 0;
            const b: u8 = if (prev) |pv| pv[i] else 0;
            const c: u8 = if (prev != null and i >= bpp) prev.?[i - bpp] else 0;
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
    const out = try allocator.alloc(u8, @as(usize, w) * h * 4);
    errdefer allocator.free(out);
    if (color_type == 6) {
        @memcpy(out, unfiltered);
    } else {
        const pixels_n = @as(usize, w) * h;
        var p: usize = 0;
        while (p < pixels_n) : (p += 1) {
            const s = p * bpp;
            const d = p * 4;
            switch (color_type) {
                0 => {
                    const g = unfiltered[s];
                    out[d] = g;
                    out[d + 1] = g;
                    out[d + 2] = g;
                    out[d + 3] = 255;
                },
                2 => {
                    out[d] = unfiltered[s];
                    out[d + 1] = unfiltered[s + 1];
                    out[d + 2] = unfiltered[s + 2];
                    out[d + 3] = 255;
                },
                3 => {
                    const idx = unfiltered[s];
                    if (idx < plte_len) {
                        out[d] = plte[idx * 3];
                        out[d + 1] = plte[idx * 3 + 1];
                        out[d + 2] = plte[idx * 3 + 2];
                        out[d + 3] = trns[idx];
                    } else {
                        out[d] = 0;
                        out[d + 1] = 0;
                        out[d + 2] = 0;
                        out[d + 3] = 0;
                    }
                },
                4 => {
                    const g = unfiltered[s];
                    out[d] = g;
                    out[d + 1] = g;
                    out[d + 2] = g;
                    out[d + 3] = unfiltered[s + 1];
                },
                else => unreachable,
            }
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
