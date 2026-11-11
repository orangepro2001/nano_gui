//! 受控即时模式帧模型（06）：ID、状态存储、节点树、脏标记、损伤、动画与定时器。

const std = @import("std");
const core = @import("core.zig");
const platform = @import("platform.zig");
const gfx = @import("gfx.zig");
const text = @import("text.zig");
const theme = @import("theme.zig");
const layout = @import("layout.zig");
const input = @import("input.zig");

pub const WidgetId = core.WidgetId;

pub const Dirty = enum(u8) { none = 0, paint = 1, layout = 2, build = 3 };
pub const Retain = enum { transient, sticky, pinned };

pub const Key = struct {
    hash: u64,

    pub fn int(v: u64) Key {
        return .{ .hash = core.hashU64(0x51ed270b, v) };
    }
    pub fn str(s: []const u8) Key {
        return .{ .hash = core.hashBytes(0x51ed270b, s) };
    }
    pub fn ptr(p: *const anyopaque) Key {
        return .{ .hash = core.hashU64(0x51ed270b, @intFromPtr(p)) };
    }
};

pub const NodeFlags = packed struct {
    layout_feedback: bool = false,
    hover_rebuild: bool = false,
    focusable: bool = false,
    clip_children: bool = false,
    disabled: bool = false,
    hidden: bool = false,
    tab_stop: bool = true,
    hit_passthrough: bool = false,
    overlay: bool = false,
};

pub const PaintFn = *const fn (ctx: *PaintCtx, node: *const Node) void;

pub const OverlayPaintFn = *const fn (ctx: *PaintCtx, rect: core.Rect, props: ?*const anyopaque) void;
pub const OverlaySpec = struct {
    rect: core.Rect,
    paint: OverlayPaintFn,
    props: ?*const anyopaque = null,
    paint_key: u64 = 0,
};

pub const NodeSpec = struct {
    layout: layout.Params = .{},
    flags: NodeFlags = .{},
    paint: ?PaintFn = null,
    props: ?*const anyopaque = null,
    paint_key: u64 = 0,
    paint_outset: f32 = 0,
};

pub const AnimSpec = struct {
    duration: theme.Duration,
    easing: theme.Easing,
    level: Dirty = .paint,
};

pub const Node = struct {
    id: core.WidgetId,
    parent: ?*Node = null,
    first_child: ?*Node = null,
    last_child: ?*Node = null,
    prev: ?*Node = null,
    next: ?*Node = null,
    layout: layout.Params = .{},
    flags: NodeFlags = .{},
    paint: ?PaintFn = null,
    props: ?*const anyopaque = null,
    paint_key: u64 = 0,
    paint_outset: f32 = 0,
    rect: core.RectI = .{},
    abs: core.RectI = .{},
    clip: core.RectI = .{},
    measured: layout.SizeI = .{},
    measured_valid: bool = false,
    measured_limit: layout.Limit = .{ .w = 0, .h = 0 },
    measured_mode: layout.MeasureMode = .natural,
    interact_opts: input.InteractOpts = .{},
    interaction: input.Interaction = .{},
    debug_name: ?[]const u8 = null,
    visible: bool = true,
    src_file: []const u8 = "",
    src_line: u32 = 0,
    root_index: usize = 0,
    scroll_metrics: ?layout.ScrollMetrics = null,
    split_metrics: ?layout.SplitMetrics = null,
};

pub const RootId = u16;

pub const StateKey = struct { id: u64, type_id: u64 };

const StateSlot = struct {
    data: *anyopaque,
    size: usize,
    type_id: u64,
    level: Retain,
    touched: u64,
    last_touch: u64 = 0,
    serial: u64 = 0,
    deinit_fn: ?*const fn (data: *anyopaque, allocator: std.mem.Allocator) void,
    destroy_fn: ?*const fn (data: *anyopaque, allocator: std.mem.Allocator) void,
    allocator: std.mem.Allocator,
};

const Anim = struct {
    current: f32 = 0,
    start: f32 = 0,
    target: f32 = 0,
    start_ms: u64 = 0,
    duration_ms: u16 = 0,
    level: Dirty = .paint,
    easing: theme.Easing = .out,
    initialized: bool = false,
};

const Timer = struct {
    interval_ms: u32,
    level: Dirty,
    next_ms: u64,
    touched: u64,
    due: bool = false,
};

const Pending = struct {
    clicked: bool = false,
    click_count: u8 = 0,
    click_button: platform.MouseButton = .left,
    right_clicked: bool = false,
    middle_clicked: bool = false,
    context_menu: ?input.ContextRequest = null,
    activated: ?input.ActivateSource = null,
    focus_gained: ?input.FocusReason = null,
    focus_lost: bool = false,
    wheel: core.Vec2 = .{},
    drag_started: bool = false,
    drag_ended: bool = false,
    drag_cancelled: bool = false,
    popup_dismissed: ?input.DismissInfo = null,
};

pub const Ui = struct {
    gpa: std.mem.Allocator,
    frame: core.FrameArena,
    tree_a: core.FrameArena,
    tree_b: core.FrameArena,
    tree_is_a: bool = true,
    current_root: ?*Node = null,
    prev_root: ?*Node = null,
    diff_root: ?*Node = null,
    roots: std.ArrayListUnmanaged(*Node) = .empty,
    prev_roots: std.ArrayListUnmanaged(*Node) = .empty,
    node_map: std.AutoHashMapUnmanaged(u64, *Node) = .empty,
    prev_map: std.AutoHashMapUnmanaged(u64, *Node) = .empty,
    id_stack: std.ArrayListUnmanaged(u64) = .empty,
    parent_stack: std.ArrayListUnmanaged(*Node) = .empty,
    overlays: std.ArrayListUnmanaged(OverlaySpec) = .empty,
    prev_overlays: std.ArrayListUnmanaged(OverlaySpec) = .empty,
    states: std.AutoHashMapUnmanaged(StateKey, *StateSlot) = .empty,
    anims: std.AutoHashMapUnmanaged(u64, Anim) = .empty,
    timers: std.AutoHashMapUnmanaged(u64, Timer) = .empty,
    inbox: std.AutoHashMapUnmanaged(u64, std.ArrayListUnmanaged(input.NodeEvent)) = .empty,
    pending: std.AutoHashMapUnmanaged(u64, Pending) = .empty,
    interaction_cache: std.AutoHashMapUnmanaged(u64, input.Interaction) = .empty,
    after_frame: std.ArrayListUnmanaged(core.Closure) = .empty,
    build_counter: u64 = 0,
    frame_now: u64 = 0,
    pass: u8 = 0,
    dirty: Dirty = .build,
    invalidated_rects: std.ArrayListUnmanaged(core.RectI) = .empty,
    damage: core.RectI = .{},
    viewport: core.Size2i = .{ .w = 800, .h = 600 },
    last_viewport_w: i32 = 0,
    last_viewport_h: i32 = 0,
    scale: f32 = 1.0,
    theme_ptr: *const theme.Theme = undefined,
    window_active: bool = true,
    window: ?*platform.Window = null,
    // 输入状态
    hover_id: core.WidgetId = .none,
    capture_id: core.WidgetId = .none,
    pressed_id: core.WidgetId = .none,
    focus_id: core.WidgetId = .none,
    focus_visible: bool = false,
    pointer_pos: core.Vec2 = .{},
    pointer_known: bool = false,
    press_pos: core.Vec2 = .{},
    dragging: bool = false,
    last_click_ms: u64 = 0,
    last_click_pos: core.Vec2 = .{},
    last_click_id: core.WidgetId = .none,
    click_streak: u8 = 0,
    keyboard_cues: bool = false,
    activation_seen: bool = false,
    rebuild_requested: bool = false,
    build_passes: u32 = 0,
    frame_count: u64 = 0,
    painted_nodes: u32 = 0,
    node_count: u32 = 0,
    measure_reused: u32 = 0,
    measured_nodes: u32 = 0,
    arranged_nodes: u32 = 0,
    last_damage_area: i64 = 0,
    show_damage: bool = false,
    force_rebuild: bool = false,
    idempotence: bool = false,
    focus_after_build: ?core.WidgetId = null,
    clear_focus_requested: bool = false,
    hover_rebuild_requested: bool = false,
    shortcut_source: ?input.ShortcutSource = null,
    ime_active: bool = false,
    command_ctx: ?*anyopaque = null,
    command_title_fn: ?*const fn (?*anyopaque, input.CommandId) []const u8 = null,
    command_invoke_fn: ?*const fn (?*anyopaque, input.CommandId) void = null,
    ime_buffer: std.ArrayListUnmanaged(u8) = .empty,
    built_this_frame: bool = false,
    sticky_limit: usize = 4096,
    state_serial: u64 = 0,
    open_menu: core.WidgetId = .none,
    popup_rect: ?core.RectI = null,
    aux_ptr: ?*anyopaque = null,
    aux_id: core.WidgetId = .none,

    pub fn init(gpa: std.mem.Allocator) Ui {
        core.stats.initRegistry();
        text.init(gpa, .{}) catch {};
        return .{
            .gpa = gpa,
            .frame = core.FrameArena.init(gpa),
            .tree_a = core.FrameArena.init(gpa),
            .tree_b = core.FrameArena.init(gpa),
        };
    }

    pub fn deinit(self: *Ui) void {
        var it = self.states.valueIterator();
        while (it.next()) |slot| {
            if (slot.*.deinit_fn) |df| df(slot.*.data, slot.*.allocator);
            if (slot.*.destroy_fn) |df| df(slot.*.data, slot.*.allocator);
            self.gpa.destroy(slot.*);
        }
        var iit = self.inbox.valueIterator();
        while (iit.next()) |list| list.deinit(self.gpa);
        self.states.deinit(self.gpa);
        self.anims.deinit(self.gpa);
        self.timers.deinit(self.gpa);
        self.inbox.deinit(self.gpa);
        self.pending.deinit(self.gpa);
        self.interaction_cache.deinit(self.gpa);
        self.after_frame.deinit(self.gpa);
        self.node_map.deinit(self.gpa);
        self.prev_map.deinit(self.gpa);
        self.roots.deinit(self.gpa);
        self.prev_roots.deinit(self.gpa);
        self.id_stack.deinit(self.gpa);
        self.parent_stack.deinit(self.gpa);
        self.overlays.deinit(self.gpa);
        self.prev_overlays.deinit(self.gpa);
        self.invalidated_rects.deinit(self.gpa);
        self.frame.deinit();
        self.tree_a.deinit();
        self.tree_b.deinit();
    }

    pub fn setTheme(self: *Ui, t: *const theme.Theme) void {
        self.theme_ptr = t;
    }
    pub fn setViewport(self: *Ui, w: i32, h: i32, scale: f32) void {
        self.viewport = .{ .w = w, .h = h };
        self.scale = scale;
    }
    pub fn setWindow(self: *Ui, w: *platform.Window) void {
        self.window = w;
        self.setViewport(w.client.w, w.client.h, w.scale());
    }

    /// 本帧有效（REQ-ARCH-012 的帧竞技场）。
    pub fn frameAlloc(self: *Ui) std.mem.Allocator {
        return self.frame.allocator();
    }
    /// 至下次构建有效（REQ-ARCH-012 的树竞技场）。
    pub fn treeAlloc(self: *Ui) std.mem.Allocator {
        return if (self.tree_is_a) self.tree_a.allocator() else self.tree_b.allocator();
    }
    /// 本帧时间戳（ms）。
    pub fn scaleFactor(self: *const Ui) f32 {
        return self.scale;
    }

    // ---- ID ----
    pub fn id(self: *Ui, src: std.builtin.SourceLocation, key: ?Key) core.WidgetId {
        const parent_seed: u64 = if (self.id_stack.items.len > 0) self.id_stack.items[self.id_stack.items.len - 1] else 0;
        var seed = core.hashBytes(parent_seed, src.file);
        seed = core.hashU64(seed, src.line);
        seed = core.hashU64(seed, src.column);
        if (key) |k| seed = core.hashU64(seed, k.hash);
        return core.WidgetId.fromHash(seed);
    }
    pub fn pushId(self: *Ui, key: Key) void {
        const parent = if (self.id_stack.items.len > 0) self.id_stack.items[self.id_stack.items.len - 1] else 0;
        self.id_stack.append(self.gpa, core.hashU64(parent, key.hash)) catch {};
    }
    pub fn popId(self: *Ui) void {
        _ = self.id_stack.pop();
    }

    // ---- 节点 ----
    pub fn beginNode(self: *Ui, widget_id: core.WidgetId, spec: NodeSpec) *Node {
        const alloc = if (self.tree_is_a) self.tree_a.allocator() else self.tree_b.allocator();
        const node = alloc.create(Node) catch @panic("nano_gui: tree arena exhausted");
        node.* = .{
            .id = widget_id,
            .layout = spec.layout,
            .flags = spec.flags,
            .paint = spec.paint,
            .props = spec.props,
            .paint_key = spec.paint_key,
            .paint_outset = spec.paint_outset,
            .root_index = if (self.parent_stack.items.len == 0) self.roots.items.len else self.parent_stack.items[0].root_index,
        };
        self.node_map.put(self.gpa, widget_id.raw(), node) catch {};
        if (self.parent_stack.items.len == 0) {
            self.roots.append(self.gpa, node) catch {};
        } else {
            const parent = self.parent_stack.items[self.parent_stack.items.len - 1];
            node.parent = parent;
            if (parent.last_child) |last| {
                last.next = node;
                node.prev = last;
                parent.last_child = node;
            } else {
                parent.first_child = node;
                parent.last_child = node;
            }
        }
        self.parent_stack.append(self.gpa, node) catch {};
        self.id_stack.append(self.gpa, widget_id.raw()) catch {};
        return node;
    }

    pub fn endNode(self: *Ui) void {
        _ = self.parent_stack.pop();
        _ = self.id_stack.pop();
    }

    pub fn leaf(self: *Ui, widget_id: core.WidgetId, spec: NodeSpec) *Node {
        const n = self.beginNode(widget_id, spec);
        self.endNode();
        return n;
    }

    pub fn getNode(self: *const Ui, widget_id: core.WidgetId) ?*Node {
        return self.node_map.get(widget_id.raw());
    }
    pub fn getPrevNode(self: *const Ui, widget_id: core.WidgetId) ?*Node {
        return self.prev_map.get(widget_id.raw());
    }

    fn setDebugName(self: *Ui, widget_id: core.WidgetId, name: ?[]const u8) void {
        if (name) |n| {
            if (self.getNode(widget_id)) |node| node.debug_name = n;
        }
    }
    pub fn setDebugNameFor(self: *Ui, widget_id: core.WidgetId, name: ?[]const u8) void {
        self.setDebugName(widget_id, name);
    }
    pub fn setFlags(self: *Ui, widget_id: core.WidgetId, flags: NodeFlags) void {
        if (self.getNode(widget_id)) |n| n.flags = flags;
    }
    pub fn setFocusable(self: *Ui, widget_id: core.WidgetId, focusable: bool, tab_stop: bool) void {
        if (self.getNode(widget_id)) |n| {
            n.flags.focusable = focusable;
            n.flags.tab_stop = tab_stop;
        }
    }

    pub fn beginColumn(self: *Ui, src: std.builtin.SourceLocation, o: layout.ContainerOptions) core.WidgetId {
        return self.beginContainer(src, o, .column);
    }
    pub fn endColumn(self: *Ui) void {
        self.endNode();
    }
    pub fn beginRow(self: *Ui, src: std.builtin.SourceLocation, o: layout.ContainerOptions) core.WidgetId {
        return self.beginContainer(src, o, .row);
    }
    pub fn endRow(self: *Ui) void {
        self.endNode();
    }
    pub fn beginStack(self: *Ui, src: std.builtin.SourceLocation, o: layout.ContainerOptions) core.WidgetId {
        return self.beginContainer(src, o, .stack);
    }
    pub fn endStack(self: *Ui) void {
        self.endNode();
    }

    fn beginContainer(self: *Ui, src: std.builtin.SourceLocation, o: layout.ContainerOptions, kind: layout.Kind) core.WidgetId {
        const widget_id = self.id(src, null);
        const p = layout.Params{
            .kind = kind,
            .main = o.main,
            .cross = o.cross,
            .main_min = o.main_min,
            .main_max = o.main_max,
            .cross_min = o.cross_min,
            .cross_max = o.cross_max,
            .padding = o.padding,
            .gap = o.gap,
            .justify = o.justify,
            .cross_align = o.cross_align,
            .self_align = o.self_align,
        };
        if (o.hidden) self.setNodeFlagsLater(widget_id);
        const node = self.beginNode(widget_id, .{ .layout = p, .flags = .{ .clip_children = o.clip, .hidden = o.hidden } });
        _ = node;
        self.setDebugName(widget_id, o.debug_name);
        return widget_id;
    }

    fn setNodeFlagsLater(_: *Ui, _: core.WidgetId) void {}

    pub fn beginScroll(self: *Ui, src: std.builtin.SourceLocation, o: layout.ContainerOptions, s: layout.ScrollParams) core.WidgetId {
        const widget_id = self.id(src, null);
        const p = layout.Params{
            .kind = .{ .scroll = s },
            .main = o.main,
            .cross = o.cross,
            .padding = o.padding,
            .gap = o.gap,
            .main_min = o.main_min,
            .main_max = o.main_max,
            .cross_min = o.cross_min,
            .cross_max = o.cross_max,
        };
        _ = self.beginNode(widget_id, .{ .layout = p, .flags = .{ .clip_children = true, .hidden = o.hidden } });
        self.setDebugName(widget_id, o.debug_name);
        return widget_id;
    }
    pub fn endScroll(self: *Ui) void {
        self.endNode();
    }

    pub fn beginSplitter(self: *Ui, src: std.builtin.SourceLocation, o: layout.ContainerOptions, s: layout.SplitterParams) core.WidgetId {
        const widget_id = self.id(src, null);
        const p = layout.Params{ .kind = .{ .splitter = s }, .main = o.main, .cross = o.cross, .padding = o.padding };
        _ = self.beginNode(widget_id, .{ .layout = p, .flags = .{ .clip_children = true } });
        self.setDebugName(widget_id, o.debug_name);
        return widget_id;
    }
    pub fn endSplitter(self: *Ui) void {
        self.endNode();
    }

    pub fn beginTable(self: *Ui, src: std.builtin.SourceLocation, o: layout.ContainerOptions, t: layout.TableParams) core.WidgetId {
        const widget_id = self.id(src, null);
        const p = layout.Params{ .kind = .{ .table = t }, .main = o.main, .cross = o.cross, .padding = o.padding, .gap = o.gap };
        _ = self.beginNode(widget_id, .{ .layout = p, .flags = .{ .clip_children = true } });
        self.setDebugName(widget_id, o.debug_name);
        return widget_id;
    }
    pub fn beginTableRow(self: *Ui, src: std.builtin.SourceLocation, o: layout.ContainerOptions) core.WidgetId {
        const widget_id = self.id(src, null);
        const p = layout.Params{ .kind = .table_row, .main = o.main, .cross = o.cross, .padding = o.padding, .gap = o.gap };
        _ = self.beginNode(widget_id, .{ .layout = p });
        return widget_id;
    }
    pub fn endTableRow(self: *Ui) void {
        self.endNode();
    }
    pub fn endTable(self: *Ui) void {
        self.endNode();
    }

    pub fn beginForm(self: *Ui, src: std.builtin.SourceLocation, o: layout.ContainerOptions, f: layout.FormParams) core.WidgetId {
        const widget_id = self.id(src, null);
        const p = layout.Params{ .kind = .{ .form = f }, .main = o.main, .cross = o.cross, .padding = o.padding, .gap = o.gap, .cross_align = o.cross_align };
        _ = self.beginNode(widget_id, .{ .layout = p });
        self.setDebugName(widget_id, o.debug_name);
        return widget_id;
    }
    pub fn endForm(self: *Ui) void {
        self.endNode();
    }

    pub fn beginAnchor(self: *Ui, src: std.builtin.SourceLocation, a: layout.AnchorParams) core.WidgetId {
        const widget_id = self.id(src, null);
        const p = layout.Params{ .kind = .{ .anchor = a }, .main = .fit, .cross = .fit };
        _ = self.beginNode(widget_id, .{ .layout = p });
        return widget_id;
    }
    pub fn endAnchor(self: *Ui) void {
        self.endNode();
    }

    pub fn spacer(self: *Ui, src: std.builtin.SourceLocation, weight: f32) core.WidgetId {
        const widget_id = self.id(src, null);
        var p = layout.Params{ .main = .{ .grow = weight }, .main_min = 0 };
        p.kind = .leaf;
        _ = self.leaf(widget_id, .{ .layout = p });
        return widget_id;
    }

    /// 在窗口内声明一个弹出层（菜单/下拉的首版）：用锚容器实现出流定位与置顶绘制。
    pub fn beginPopup(self: *Ui, widget_id: core.WidgetId, spec: input.PopupSpec) bool {
        const parent = if (self.parent_stack.items.len > 0) self.parent_stack.items[self.parent_stack.items.len - 1] else null;
        var rel = spec.anchor;
        if (parent) |par| {
            if (self.getPrevNode(par.id)) |pn| {
                rel.x -= @as(f32, @floatFromInt(pn.abs.x)) / self.scale;
                rel.y -= @as(f32, @floatFromInt(pn.abs.y)) / self.scale;
            }
        }
        const ap = layout.AnchorParams{
            .target = .{ .rect = rel },
            .placement = spec.placement,
            .gap = spec.gap,
            .bounds = .root,
        };
        const popup_anchor = self.beginNode(widget_id, .{
            .layout = .{ .kind = .{ .anchor = ap }, .main = .fit, .cross = .fit },
            .flags = .{ .overlay = true },
            .paint_outset = 0,
        });
        _ = popup_anchor;
        // 内容面板
        const panel_id = self.beginColumn(@src(), .{
            .main = .fit,
            .cross = .fit,
            .padding = core.Insets.all(self.theme_ptr.metric(.pad_popup_y)),
            .gap = .none,
        });
        if (self.getNode(panel_id)) |n| {
            n.paint = paintPopupPanel;
            n.paint_key = 0x504f5055;
        }
        return true;
    }
    pub fn endPopup(self: *Ui) void {
        self.endColumn();
        self.endNode();
    }

    pub fn overlay(self: *Ui, widget_id: core.WidgetId, spec: OverlaySpec) void {
        _ = widget_id;
        self.overlays.append(self.gpa, spec) catch {};
    }

    pub fn lastRect(self: *const Ui, widget_id: core.WidgetId) ?core.Rect {
        const r0 = self.lastRectPx(widget_id) orelse return null;
        return .{
            .x = @as(f32, @floatFromInt(r0.x)) / self.scale,
            .y = @as(f32, @floatFromInt(r0.y)) / self.scale,
            .w = @as(f32, @floatFromInt(r0.w)) / self.scale,
            .h = @as(f32, @floatFromInt(r0.h)) / self.scale,
        };
    }
    pub fn lastRectPx(self: *const Ui, widget_id: core.WidgetId) ?core.RectI {
        if (self.prev_map.get(widget_id.raw())) |n| {
            if (n.rect.w != 0 or n.rect.h != 0) return n.abs;
        }
        return null;
    }

    // ---- 状态存储 ----
    pub fn state(self: *Ui, comptime T: type, widget_id: core.WidgetId, init_value: T) *T {
        return self.stateImpl(T, widget_id, init_value, .transient);
    }
    pub fn stateSticky(self: *Ui, comptime T: type, widget_id: core.WidgetId, init_value: T) *T {
        return self.stateImpl(T, widget_id, init_value, .sticky);
    }
    fn stateImpl(self: *Ui, comptime T: type, widget_id: core.WidgetId, init_value: T, level: Retain) *T {
        const key = StateKey{ .id = widget_id.raw(), .type_id = core.hashBytes(0x9e3779b9, @typeName(T)) ^ @as(u64, @sizeOf(T)) *% 0x100000001b3 };
        if (self.states.get(key)) |slot| {
            slot.touched = self.build_counter;
            slot.last_touch = self.build_counter;
            self.state_serial += 1;
            slot.serial = self.state_serial;
            return @ptrCast(@alignCast(slot.data));
        }
        const ptr = self.gpa.create(T) catch @panic("nano_gui: state allocation failed");
        ptr.* = init_value;
        const slot = self.gpa.create(StateSlot) catch @panic("nano_gui: state allocation failed");
        slot.* = .{
            .data = @ptrCast(ptr),
            .size = @sizeOf(T),
            .type_id = key.type_id,
            .level = level,
            .touched = self.build_counter,
            .last_touch = self.build_counter,
            .serial = blk: {
                self.state_serial += 1;
                break :blk self.state_serial;
            },
            .deinit_fn = null,
            .destroy_fn = struct {
                fn destroy(data: *anyopaque, alloc: std.mem.Allocator) void {
                    const p: *T = @ptrCast(@alignCast(data));
                    alloc.destroy(p);
                }
            }.destroy,
            .allocator = self.gpa,
        };
        self.states.put(self.gpa, key, slot) catch {};
        return ptr;
    }

    pub fn retained(self: *Ui, comptime T: type, widget_id: core.WidgetId, level: Retain) *T {
        if (@hasDecl(T, "init") and @hasDecl(T, "deinit")) {
            return self.retainedImpl(T, widget_id, level);
        } else {
            @compileError("retained 类型必须提供 init(allocator) 与 deinit(*T)");
        }
    }

    fn retainedImpl(self: *Ui, comptime T: type, widget_id: core.WidgetId, level: Retain) *T {
        const key = StateKey{ .id = widget_id.raw(), .type_id = core.hashBytes(0x9e3779b9, @typeName(T)) ^ @as(u64, @sizeOf(T)) *% 0x100000001b3 };
        if (self.states.get(key)) |slot| {
            slot.touched = self.build_counter;
            slot.last_touch = self.build_counter;
            self.state_serial += 1;
            slot.serial = self.state_serial;
            return @ptrCast(@alignCast(slot.data));
        }
        const ptr = self.gpa.create(T) catch @panic("nano_gui: retained allocation failed");
        ptr.* = T.init(self.gpa);
        const slot = self.gpa.create(StateSlot) catch @panic("nano_gui: retained allocation failed");
        slot.* = .{
            .data = @ptrCast(ptr),
            .size = @sizeOf(T),
            .type_id = key.type_id,
            .level = level,
            .touched = self.build_counter,
            .last_touch = self.build_counter,
            .serial = blk: {
                self.state_serial += 1;
                break :blk self.state_serial;
            },
            .deinit_fn = struct {
                fn deinit(data: *anyopaque, _: std.mem.Allocator) void {
                    const p: *T = @ptrCast(@alignCast(data));
                    p.deinit();
                }
            }.deinit,
            .destroy_fn = struct {
                fn destroy(data: *anyopaque, alloc: std.mem.Allocator) void {
                    const p: *T = @ptrCast(@alignCast(data));
                    alloc.destroy(p);
                }
            }.destroy,
            .allocator = self.gpa,
        };
        self.states.put(self.gpa, key, slot) catch {};
        return ptr;
    }

    /// 读取已存在的状态槽；不存在返回 null。线程：界面线程。
    pub fn stateSlotCount(self: *const Ui) usize {
        return self.states.count();
    }

    pub fn getState(self: *const Ui, comptime T: type, widget_id: core.WidgetId) ?*T {
        const key = StateKey{ .id = widget_id.raw(), .type_id = core.hashBytes(0x9e3779b9, @typeName(T)) ^ @as(u64, @sizeOf(T)) *% 0x100000001b3 };
        if (self.states.get(key)) |slot| return @ptrCast(@alignCast(slot.data));
        return null;
    }

    pub fn forget(self: *Ui, widget_id: core.WidgetId) void {
        var keys = std.ArrayListUnmanaged(StateKey).empty;
        defer keys.deinit(self.gpa);
        var it = self.states.keyIterator();
        while (it.next()) |k| {
            if (k.id == widget_id.raw()) keys.append(self.gpa, k.*) catch {};
        }
        for (keys.items) |k| self.removeState(k);
    }

    pub fn forgetSubtree(self: *Ui, widget_id: core.WidgetId) void {
        self.forget(widget_id);
        if (self.getNode(widget_id)) |n| {
            var child = n.first_child;
            while (child) |c| : (child = c.next) self.forgetSubtree(c.id);
        }
    }

    fn removeState(self: *Ui, key: StateKey) void {
        if (self.states.fetchRemove(key)) |kv| {
            const slot = kv.value;
            if (slot.deinit_fn) |df| df(slot.data, slot.allocator);
            if (slot.destroy_fn) |df| df(slot.data, slot.allocator);
            self.gpa.destroy(slot);
        }
    }

    // ---- 失效 ----
    pub fn invalidate(self: *Ui, level: Dirty) void {
        if (@backingInt(level) > @backingInt(self.dirty)) self.dirty = level;
    }
    pub fn invalidateNode(self: *Ui, widget_id: core.WidgetId, level: Dirty) void {
        self.invalidate(level);
        if (self.getPrevNode(widget_id)) |n| {
            if (@backingInt(level) <= @backingInt(Dirty.paint)) {
                self.invalidated_rects.append(self.gpa, n.abs) catch {};
            }
        }
    }
    pub fn invalidateRect(self: *Ui, _: RootId, rect: core.Rect) void {
        self.invalidate(.paint);
        self.invalidated_rects.append(self.gpa, .{
            .x = @intFromFloat(@round(rect.x * self.scale)),
            .y = @intFromFloat(@round(rect.y * self.scale)),
            .w = @intFromFloat(@round(rect.w * self.scale)),
            .h = @intFromFloat(@round(rect.h * self.scale)),
        }) catch {};
    }
    pub fn requestRebuild(self: *Ui) void {
        self.rebuild_requested = true;
        self.invalidate(.build);
    }
    pub fn afterFrame(self: *Ui, closure: core.Closure) void {
        self.after_frame.append(self.gpa, closure) catch {};
    }

    // ---- 时间 ----
    pub fn now(self: *const Ui) u64 {
        return self.frame_now;
    }
    pub fn animate(self: *Ui, widget_id: core.WidgetId, slot: u8, target: f32, spec: AnimSpec) f32 {
        const key = (widget_id.raw() << 8) | slot;
        const theme_ptr = self.theme_ptr;
        const dur = theme_ptr.durationMs(spec.duration);
        if (self.anims.getPtr(key)) |a| {
            if (!a.initialized) {
                a.* = .{ .current = target, .start = target, .target = target, .start_ms = self.frame_now, .duration_ms = dur, .level = spec.level, .easing = spec.easing, .initialized = true };
                return target;
            }
            if (a.target != target) {
                a.start = a.current;
                a.target = target;
                a.start_ms = self.frame_now;
                a.duration_ms = dur;
                a.level = spec.level;
                a.easing = spec.easing;
            }
            if (dur == 0 or !self.theme_ptr.durationsOn()) {
                a.current = target;
            } else {
                const elapsed = self.frame_now -| a.start_ms;
                const t = std.math.clamp(@as(f32, @floatFromInt(elapsed)) / @as(f32, @floatFromInt(dur)), 0, 1);
                const e = if (spec.easing == .out) easeOut(t) else t;
                a.current = a.start + (a.target - a.start) * e;
                if (t < 1) self.invalidate(spec.level);
            }
            return a.current;
        }
        self.anims.put(self.gpa, key, .{
            .current = target,
            .start = target,
            .target = target,
            .start_ms = self.frame_now,
            .duration_ms = dur,
            .level = spec.level,
            .easing = spec.easing,
            .initialized = true,
        }) catch {};
        return target;
    }

    pub fn animateColor(self: *Ui, widget_id: core.WidgetId, slot: u8, target: core.Color, spec: AnimSpec) core.Color {
        var out: core.Color = undefined;
        inline for ([_]u8{ 0, 1, 2, 3 }) |ch| {
            const v = self.animate(widget_id, slot + ch, @floatFromInt(@field(target, fieldName(ch))), spec);
            @field(out, fieldName(ch)) = @intFromFloat(std.math.clamp(v, 0, 255));
        }
        return out;
    }

    fn fieldName(comptime i: u8) []const u8 {
        return switch (i) {
            0 => "r",
            1 => "g",
            2 => "b",
            else => "a",
        };
    }

    pub fn timer(self: *Ui, widget_id: core.WidgetId, interval_ms: u32, level: Dirty) bool {
        const key = widget_id.raw();
        if (self.timers.getPtr(key)) |t| {
            t.touched = self.build_counter;
            t.level = level;
            const due = t.due or self.frame_now >= t.next_ms;
            t.due = false;
            if (due) t.next_ms = self.frame_now + interval_ms;
            return due;
        }
        self.timers.put(self.gpa, key, .{
            .interval_ms = interval_ms,
            .level = level,
            .next_ms = self.frame_now + interval_ms,
            .touched = self.build_counter,
        }) catch {};
        return false;
    }

    pub fn haveActiveAnimations(self: *const Ui) bool {
        var it = self.anims.valueIterator();
        while (it.next()) |a| {
            if (a.duration_ms > 0 and a.current != a.target) return true;
        }
        return false;
    }

    pub fn nextTimerMs(self: *const Ui) ?u64 {
        var best: ?u64 = null;
        var it = self.timers.valueIterator();
        while (it.next()) |t| {
            if (!self.timerTouched(t.touched)) continue;
            if (best == null or t.next_ms < best.?) best = t.next_ms;
        }
        return best;
    }

    fn timerTouched(self: *const Ui, touched: u64) bool {
        return touched + 2 > self.build_counter;
    }

    // ---- 交互 ----
    pub fn interact(self: *Ui, widget_id: core.WidgetId, opts: input.InteractOpts) input.Interaction {
        if (self.pass == 0 or self.pass > 2) return .{};
        if (self.pass == 2) self.activation_seen = false;
        if (self.interaction_cache.get(widget_id.raw())) |cached| return cached;
        const node = self.getNode(widget_id) orelse return .{};
        node.interact_opts = opts;
        const disabled = self.effectiveDisabled(idOrNone(widget_id));
        var out = input.Interaction{
            .hovered = self.hover_id == widget_id,
            .hovered_within = self.hover_id == widget_id,
            .captured = self.capture_id == widget_id,
            .focused = self.focus_id == widget_id,
            .focus_visible = self.focus_id == widget_id and self.window_active and (self.focus_visible or opts.text_input),
            .disabled = disabled,
            .pressed = self.pressed_id == widget_id and self.pointerInNode(widget_id, self.pointer_pos),
            .dragging = self.dragging and self.capture_id == widget_id,
        };
        if (out.hovered or out.captured) {
            if (self.getPrevNode(widget_id)) |n| {
                out.pointer = .{
                    .x = self.pointer_pos.x - @as(f32, @floatFromInt(n.abs.x)) / self.scale,
                    .y = self.pointer_pos.y - @as(f32, @floatFromInt(n.abs.y)) / self.scale,
                };
            }
        }
        if (self.pass == 1) {
            if (self.pending.get(widget_id.raw())) |p| {
                out.clicked = p.clicked;
                out.click_count = p.click_count;
                out.click_button = p.click_button;
                out.double_clicked = p.clicked and p.click_count == 2;
                out.triple_clicked = p.clicked and p.click_count == 3;
                out.right_clicked = p.right_clicked;
                out.middle_clicked = p.middle_clicked;
                out.context_menu = p.context_menu;
                out.activated = p.activated;
                out.focus_gained = p.focus_gained;
                out.focus_lost = p.focus_lost;
                out.wheel = p.wheel;
                out.drag_started = p.drag_started;
                out.drag_ended = p.drag_ended;
                out.drag_cancelled = p.drag_cancelled;
                out.popup_dismissed = p.popup_dismissed;
                if (p.clicked or p.right_clicked or p.middle_clicked or p.activated != null or p.drag_started or p.drag_ended or p.drag_cancelled) {
                    self.activation_seen = true;
                }
            }
        }
        node.interaction = out;
        self.interaction_cache.put(self.gpa, widget_id.raw(), out) catch {};
        return out;
    }

    fn idOrNone(widget_id: core.WidgetId) core.WidgetId {
        return widget_id;
    }

    fn effectiveDisabled(self: *const Ui, widget_id: core.WidgetId) bool {
        if (self.getNode(widget_id)) |n| {
            var cur: ?*Node = n;
            while (cur) |c| {
                if (c.flags.disabled) return true;
                cur = c.parent;
            }
        }
        return false;
    }

    fn pointerInNode(self: *const Ui, widget_id: core.WidgetId, pos: core.Vec2) bool {
        const n = self.getPrevNode(widget_id) orelse self.getNode(widget_id) orelse return false;
        const ppx: core.Vec2i = .{
            .x = @intFromFloat(@round(pos.x * self.scale)),
            .y = @intFromFloat(@round(pos.y * self.scale)),
        };
        return n.abs.contains(ppx) or (n.abs.w == 0 and n.abs.h == 0);
    }

    pub fn events(self: *Ui, widget_id: core.WidgetId) []const input.NodeEvent {
        if (self.pass == 2) return &.{};
        if (self.inbox.get(widget_id.raw())) |list| return list.items;
        return &.{};
    }

    pub fn capturePointer(self: *Ui, widget_id: core.WidgetId) void {
        self.capture_id = widget_id;
    }
    pub fn releaseCapture(self: *Ui) void {
        self.capture_id = .none;
    }
    pub fn capturedId(self: *const Ui) core.WidgetId {
        return self.capture_id;
    }
    pub fn focusedId(self: *const Ui) core.WidgetId {
        return self.focus_id;
    }
    pub fn setFocus(self: *Ui, widget_id: core.WidgetId) void {
        self.focus_after_build = widget_id;
    }
    pub fn clearFocus(self: *Ui) void {
        self.clear_focus_requested = true;
    }
    pub fn autoFocus(self: *Ui, widget_id: core.WidgetId) void {
        self.focus_after_build = widget_id;
    }
    pub fn keyboardCuesVisible(self: *const Ui) bool {
        return self.keyboard_cues;
    }
    /// 接入命令快捷键表（11）。线程：界面线程。
    pub fn setShortcutSource(self: *Ui, source: ?input.ShortcutSource) void {
        self.shortcut_source = source;
    }

    pub fn setCommands(self: *Ui, ctx: ?*anyopaque, titleFn: ?*const fn (?*anyopaque, input.CommandId) []const u8, invokeFn: ?*const fn (?*anyopaque, input.CommandId) void) void {
        self.command_ctx = ctx;
        self.command_title_fn = titleFn;
        self.command_invoke_fn = invokeFn;
    }
    pub fn commandTitle(self: *const Ui, cmd_id: input.CommandId) []const u8 {
        if (self.command_title_fn) |f| return f(self.command_ctx, cmd_id);
        return "";
    }
    pub fn invokeCommand(self: *Ui, cmd_id: input.CommandId) void {
        if (self.command_invoke_fn) |f| f(self.command_ctx, cmd_id);
        self.invalidate(.build);
    }

    // ---- 帧 ----
    pub fn beginFrame(self: *Ui, now_ms: u64, window_active: bool) void {
        self.frame_now = now_ms;
        self.window_active = window_active;
        if (self.force_rebuild) self.dirty = .build;
        if (self.current_root == null) self.dirty = .build;
        self.frame.reset();
        self.clearInbox();
        self.pending.clearRetainingCapacity();
        self.interaction_cache.clearRetainingCapacity();
        self.activation_seen = false;
        self.rebuild_requested = false;
        self.built_this_frame = false;
        self.build_passes = 0;
        self.overlays.clearRetainingCapacity();
    }

    pub fn dispatch(self: *Ui, event: platform.Event) void {
        if (self.prev_root == null) {
            if (event.data == .resized) self.invalidate(.layout);
            return;
        }
        switch (event.data) {
            .mouse_move => |m| self.onMouseMove(m.pos, m.mods),
            .mouse_button => |m| self.onMouseButton(m.button, m.down, m.pos, m.mods),
            .mouse_leave => {
                if (self.capture_id == .none) self.setHover(.none);
            },
            .wheel => |w| self.onWheel(w.raw, w.pos, w.mods, w.axis),
            .key => |k| self.onKey(k.vk, k.down, k.repeat, k.mods),
            .text => |t| self.onText(t),
            .ime_start => {
                self.ime_active = true;
                if (self.focus_id != .none) {
                    self.pushEvent(self.focus_id, .ime_start);
                    self.invalidate(.build);
                }
            },
            .ime_update => |u| {
                self.ime_active = true;
                if (self.focus_id != .none) {
                    const txt = self.frameAlloc().dupe(u8, u.text) catch return;
                    const segs = self.frameAlloc().dupe(platform.ImeSegment, u.segments) catch return;
                    self.pushEvent(self.focus_id, .{ .ime_update = .{ .text = txt, .cursor = u.cursor, .segments = segs } });
                    self.invalidate(.paint);
                }
            },
            .ime_commit => |t| {
                if (self.focus_id != .none) {
                    const txt = self.frameAlloc().dupe(u8, t) catch return;
                    self.pushEvent(self.focus_id, .{ .ime_commit = txt });
                    self.invalidate(.build);
                }
            },
            .ime_end => {
                self.ime_active = false;
                if (self.focus_id != .none) {
                    self.pushEvent(self.focus_id, .ime_end);
                    self.invalidate(.paint);
                }
            },
            .focus => |f| {
                if (f.gained) {
                    if (self.focus_id != .none) self.markFocus(self.focus_id, true, .restore);
                } else {
                    self.releaseCapture();
                    self.focus_visible = false;
                    self.invalidate(.paint);
                }
            },
            .activate => |a| {
                if (a.active != self.window_active) {
                    self.window_active = a.active;
                    if (!a.active) {
                        self.releaseCapture();
                        self.focus_visible = false;
                    }
                    self.invalidate(.paint);
                }
            },
            .resized => |r| {
                self.setViewport(r.client.w, r.client.h, self.scale);
                self.invalidate(.layout);
            },
            .dpi_changed => |d| {
                self.scale = d.scale;
                self.invalidate(.build);
            },
            .system_changed => self.invalidate(.build),
            .visibility => |v| {
                if (!v.visible) self.invalidate(.paint) else self.invalidate(.build);
            },
            .repaint => |r| {
                if (!r.rect.isEmpty()) {
                    self.invalidated_rects.append(self.gpa, r.rect) catch {};
                    self.invalidate(.paint);
                }
            },
            else => {},
        }
    }

    fn onMouseMove(self: *Ui, pos_px: core.Vec2i, mods: platform.Mods) void {
        self.pointer_pos = .{ .x = @as(f32, @floatFromInt(pos_px.x)) / self.scale, .y = @as(f32, @floatFromInt(pos_px.y)) / self.scale };
        self.pointer_known = true;
        if (self.capture_id != .none) {
            self.pushEvent(self.capture_id, .{ .pointer_move = .{ .pos = self.pointer_pos, .mods = mods } });
            if (self.dragging) {
                self.pushEvent(self.capture_id, .{ .drag_move = .{ .pos = self.pointer_pos, .delta = self.pointer_pos.sub(self.press_pos) } });
            }
            self.invalidate(.paint);
            return;
        }
        const hit = self.hitTest(pos_px);
        self.setHover(hit);
    }

    fn onMouseButton(self: *Ui, button: platform.MouseButton, down: bool, pos_px: core.Vec2i, mods: platform.Mods) void {
        self.pointer_pos = .{ .x = @as(f32, @floatFromInt(pos_px.x)) / self.scale, .y = @as(f32, @floatFromInt(pos_px.y)) / self.scale };
        self.pointer_known = true;
        if (down) {
            self.focus_visible = false;
            if (self.open_menu != .none) {
                const inside_popup = if (self.popup_rect) |pr| pr.contains(.{ .x = pos_px.x, .y = pos_px.y }) else false;
                if (!inside_popup) {
                    self.open_menu = .none;
                    self.invalidate(.build);
                }
            }
            const hit = self.hitTest(pos_px);
            if (hit == .none) return;
            const n = self.getPrevNode(hit) orelse return;
            if (self.effectiveDisabled(hit)) return;
            self.capture_id = hit;
            self.pressed_id = hit;
            self.press_pos = self.pointer_pos;
            self.dragging = false;
            self.pushEvent(hit, .{ .press = .{ .button = button, .pos = self.pointer_pos, .mods = mods, .clicks = 1 } });
            // 点击聚焦
            var cur: ?*Node = n;
            while (cur) |c| {
                if (c.flags.focusable) {
                    if (self.focus_id != c.id) self.setFocusNow(c.id, .pointer);
                    break;
                }
                cur = c.parent;
            }
            self.invalidate(.build);
        } else {
            const target = self.capture_id;
            if (target == .none) return;
            const inside = self.pointerInNode(target, self.pointer_pos);
            self.pushEvent(target, .{ .release = .{ .button = button, .pos = self.pointer_pos, .mods = mods, .inside = inside } });
            if (button == .left and inside and !self.dragging and self.pressed_id == target) {
                const sm = platform.metrics(self.window);
                var count: u8 = 1;
                const dx = @abs(self.pointer_pos.x - self.last_click_pos.x) * self.scale;
                const dy = @abs(self.pointer_pos.y - self.last_click_pos.y) * self.scale;
                const in_rect = dx <= @as(f32, @floatFromInt(@max(1, sm.double_click_size.w))) * 0.5 and
                    dy <= @as(f32, @floatFromInt(@max(1, sm.double_click_size.h))) * 0.5;
                if (self.frame_now -| self.last_click_ms <= sm.double_click_ms and self.last_click_id == target and in_rect) {
                    count = if (self.click_streak >= 3) 1 else self.click_streak + 1;
                }
                self.click_streak = count;
                self.last_click_id = target;
                self.last_click_ms = self.frame_now;
                self.last_click_pos = self.pointer_pos;
                const p = self.getPending(target);
                p.clicked = true;
                p.click_count = count;
                p.click_button = button;
                self.pushEvent(target, .{ .click = .{ .button = button, .pos = self.pointer_pos, .mods = mods, .count = count } });
            }
            if (button == .right and inside and self.pressed_id == target) {
                const p = self.getPending(target);
                p.right_clicked = true;
                p.context_menu = .{ .pos = self.pointer_pos, .anchor = .{ .x = self.pointer_pos.x, .y = self.pointer_pos.y, .w = 1, .h = 1 }, .from_keyboard = false };
            }
            if (button == .middle and inside and self.pressed_id == target) {
                self.getPending(target).middle_clicked = true;
            }
            self.capture_id = .none;
            self.pressed_id = .none;
            self.dragging = false;
            const hit = self.hitTest(pos_px);
            self.setHover(hit);
            self.invalidate(.build);
        }
    }

    fn onWheel(self: *Ui, raw: i32, pos_px: core.Vec2i, mods: platform.Mods, axis: platform.Axis) void {
        const hit = self.hitTest(pos_px);
        if (hit == .none) return;
        var cur: ?*Node = self.getPrevNode(hit);
        while (cur) |c| {
            if (c.interact_opts.sense.wheel and !self.effectiveDisabled(c.id)) {
                const delta = if (axis == .vertical) core.Vec2{ .x = 0, .y = @as(f32, @floatFromInt(raw)) / 120.0 } else core.Vec2{ .x = @as(f32, @floatFromInt(raw)) / 120.0, .y = 0 };
                self.pushEvent(c.id, .{ .wheel = .{ .delta = delta, .page = false, .mods = mods, .pos = self.pointer_pos } });
                const p = self.getPending(c.id);
                p.wheel = p.wheel.add(delta);
                self.invalidate(.build);
                return;
            }
            cur = c.parent;
        }
    }

    fn onKey(self: *Ui, vk: platform.VirtualKey, down: bool, repeat: bool, mods: platform.Mods) void {
        if (down and vk == .escape and self.open_menu != .none) {
            self.open_menu = .none;
            self.invalidate(.build);
            return;
        }
        if (down) {
            self.focus_visible = true;
            self.keyboard_cues = true;
        }
        // ④ 快捷键：非自动重复、非 AltGr 的 key_down。
        if (down and !repeat and !mods.altgr) {
            if (self.shortcut_source) |src| {
                if (src.lookup(src.ctx, .{ .key = vk, .mods = mods })) |hit| {
                    if (hit.enabled) src.invoke(src.ctx, hit.command);
                    self.invalidate(.build);
                    return;
                }
            }
        }
        if (self.focus_id == .none) {
            if (down and vk == .tab) self.moveFocus(repeat);
            return;
        }
        if (down and vk == .tab and !repeat) {
            const focus_node = self.getPrevNode(self.focus_id);
            const handles_tab = if (focus_node) |n| n.interact_opts.handles.matches(.tab, mods) else false;
            if (handles_tab) {
                self.pushEvent(self.focus_id, .{ .key_down = .{ .key = vk, .mods = mods, .repeat = false } });
                self.invalidate(.build);
                return;
            }
            self.moveFocus(mods.shift);
            return;
        }
        if (down and vk == .escape and self.capture_id != .none) {
            self.getPending(self.capture_id).drag_cancelled = true;
            self.releaseCapture();
            return;
        }
        self.pushEvent(self.focus_id, if (down) .{ .key_down = .{ .key = vk, .mods = mods, .repeat = repeat } } else .{ .key_up = .{ .key = vk, .mods = mods } });
        self.invalidate(.build);
    }

    fn onText(self: *Ui, t_in: []const u8) void {
        if (self.focus_id == .none) return;
        const node = self.getNode(self.focus_id);
        if (node == null) return;
        const t = self.frameAlloc().dupe(u8, t_in) catch return;
        var i: usize = 0;
        while (i < t.len) {
            const r = core.nextCodepoint(t, i);
            self.pushEvent(self.focus_id, .{ .char = r.cp });
            i += @max(1, r.len);
        }
        self.invalidate(.build);
    }

    fn pushEvent(self: *Ui, widget_id: core.WidgetId, ev: input.NodeEvent) void {
        const gop = self.inbox.getOrPut(self.gpa, widget_id.raw()) catch return;
        if (!gop.found_existing) gop.value_ptr.* = .empty;
        gop.value_ptr.append(self.gpa, ev) catch {};
    }

    fn getPending(self: *Ui, widget_id: core.WidgetId) *Pending {
        const gop = self.pending.getOrPut(self.gpa, widget_id.raw()) catch @panic("nano_gui: pending allocation failed");
        if (!gop.found_existing) gop.value_ptr.* = .{};
        return gop.value_ptr;
    }

    pub fn hitTest(self: *const Ui, pos_px: core.Vec2i) core.WidgetId {
        var overlays = std.ArrayListUnmanaged(*Node).empty;
        defer overlays.deinit(self.gpa);
        collectOverlayHits(self.prev_root, false, &overlays, self.gpa);
        var i = overlays.items.len;
        while (i > 0) {
            i -= 1;
            const n = overlays.items[i];
            if (n.flags.hidden or n.flags.hit_passthrough) continue;
            if (!n.abs.contains(pos_px)) continue;
            if (!n.clip.contains(pos_px)) continue;
            return n.id;
        }
        var list = std.ArrayListUnmanaged(*Node).empty;
        defer list.deinit(self.gpa);
        collectNormalHits(self.prev_root, false, &list, self.gpa);
        i = list.items.len;
        while (i > 0) {
            i -= 1;
            const n = list.items[i];
            if (n.flags.hidden or n.flags.hit_passthrough) continue;
            if (!n.abs.contains(pos_px)) continue;
            if (!n.clip.contains(pos_px)) continue;
            return n.id;
        }
        return .none;
    }

    fn collectHit(node: ?*Node, out: *std.ArrayListUnmanaged(*Node), gpa: std.mem.Allocator) void {
        collectNormalHits(node, false, out, gpa);
    }

    fn collectNormalHits(node: ?*Node, in_overlay: bool, out: *std.ArrayListUnmanaged(*Node), gpa: std.mem.Allocator) void {
        const n = node orelse return;
        if (n.flags.hidden) return;
        if (in_overlay or n.flags.overlay) return;
        const o = n.interact_opts.sense;
        if (o.hover or o.click or o.drag or o.wheel or o.context) out.append(gpa, n) catch {};
        var c = n.first_child;
        while (c) |cc| : (c = cc.next) collectNormalHits(cc, false, out, gpa);
    }

    fn collectOverlayHits(node: ?*Node, in_overlay: bool, out: *std.ArrayListUnmanaged(*Node), gpa: std.mem.Allocator) void {
        const n = node orelse return;
        if (n.flags.hidden) return;
        const inside = in_overlay or n.flags.overlay;
        if (inside) {
            const o = n.interact_opts.sense;
            if (o.hover or o.click or o.drag or o.wheel or o.context) out.append(gpa, n) catch {};
        }
        var c = n.first_child;
        while (c) |cc| : (c = cc.next) collectOverlayHits(cc, inside, out, gpa);
    }

    fn paintOverlayTrees(ctx: *PaintCtx, node: *Node, damage: core.RectI) void {
        if (node.flags.overlay) {
            paintTreeForce(ctx, node, damage);
            return;
        }
        var c = node.first_child;
        while (c) |cc| : (c = cc.next) paintOverlayTrees(ctx, cc, damage);
    }

    fn paintTreeForce(ctx: *PaintCtx, node: *Node, damage: core.RectI) void {
        if (node.flags.hidden) return;
        const r = node.abs;
        if (!r.intersect(damage).isEmpty()) {
            if (node.paint) |f| {
                f(ctx, node);
                ctx.ui.painted_nodes += 1;
            }
        }
        if (node.flags.clip_children) {
            ctx.draw.canvas.pushClip(.{
                .x = @as(f32, @floatFromInt(node.clip.x)) / ctx.draw.scale,
                .y = @as(f32, @floatFromInt(node.clip.y)) / ctx.draw.scale,
                .w = @as(f32, @floatFromInt(node.clip.w)) / ctx.draw.scale,
                .h = @as(f32, @floatFromInt(node.clip.h)) / ctx.draw.scale,
            });
        }
        var c = node.first_child;
        while (c) |cc| : (c = cc.next) paintTreeForce(ctx, cc, damage);
        if (node.flags.clip_children) ctx.draw.canvas.popClip();
    }

    fn setHover(self: *Ui, next: core.WidgetId) void {
        if (self.hover_id == next) return;
        const old = self.hover_id;
        self.hover_id = next;
        if (old != .none) self.invalidateNode(old, .paint);
        if (next != .none) self.invalidateNode(next, .paint);
    }

    fn setFocusNow(self: *Ui, widget_id: core.WidgetId, reason: input.FocusReason) void {
        if (self.focus_id == widget_id) return;
        if (self.focus_id != .none) {
            self.getPending(self.focus_id).focus_lost = true;
            self.pushEvent(self.focus_id, .focus_lost);
            self.invalidateNode(self.focus_id, .paint);
        }
        self.focus_id = widget_id;
        if (self.window) |w| {
            if (self.getPrevNode(widget_id)) |n| w.setImeEnabled(n.interact_opts.text_input);
        }
        self.getPending(widget_id).focus_gained = reason;
        self.pushEvent(widget_id, .{ .focus_gained = reason });
        self.invalidateNode(widget_id, .paint);
        self.invalidate(.build);
    }

    fn markFocus(self: *Ui, widget_id: core.WidgetId, on: bool, reason: input.FocusReason) void {
        if (on) self.setFocusNow(widget_id, reason);
    }

    fn moveFocus(self: *Ui, backwards: bool) void {
        var list = std.ArrayListUnmanaged(*Node).empty;
        defer list.deinit(self.gpa);
        tabStops(self.prev_root, &list, self.gpa);
        if (list.items.len == 0) return;
        var idx: usize = 0;
        var found = false;
        for (list.items, 0..) |n, i| {
            if (n.id == self.focus_id) {
                idx = i;
                found = true;
                break;
            }
        }
        var next: usize = 0;
        if (backwards) {
            next = if (found) (idx + list.items.len - 1) % list.items.len else list.items.len - 1;
        } else {
            next = if (found) (idx + 1) % list.items.len else 0;
        }
        self.setFocusNow(list.items[next].id, .tab);
        self.focus_visible = true;
    }

    fn tabStops(node: ?*Node, out: *std.ArrayListUnmanaged(*Node), gpa: std.mem.Allocator) void {
        const n = node orelse return;
        if (n.flags.hidden) return;
        if (n.flags.focusable and n.flags.tab_stop and !n.flags.disabled) out.append(gpa, n) catch {};
        var c = n.first_child;
        while (c) |cc| : (c = cc.next) tabStops(cc, out, gpa);
    }

    // ---- 构建 ----
    pub fn build(self: *Ui, ctx: anytype, buildFn: *const fn (@TypeOf(ctx), *Ui) void) void {
        if (self.dirty != .build and !self.force_rebuild) return;
        const old_root = self.current_root;
        self.popup_rect = null;
        var pass: u8 = 1;
        while (pass <= 2) : (pass += 1) {
            self.pass = pass;
            self.build_counter += 1;
            self.node_map.clearRetainingCapacity();
            self.roots.clearRetainingCapacity();
            self.id_stack.clearRetainingCapacity();
            self.parent_stack.clearRetainingCapacity();
            self.interaction_cache.clearRetainingCapacity();
            // 第一遍写入选定竞技场；第二遍复用同一竞技场。
            if (pass == 1) {
                self.tree_is_a = !self.tree_is_a;
                const arena = if (self.tree_is_a) &self.tree_a else &self.tree_b;
                arena.reset();
            } else {
                const arena = if (self.tree_is_a) &self.tree_a else &self.tree_b;
                arena.reset();
                // 第二遍：丢弃第一遍节点，但旧树仍为上一帧的树。
            }
            const root_alloc = if (self.tree_is_a) self.tree_a.allocator() else self.tree_b.allocator();
            const root = root_alloc.create(Node) catch @panic("nano_gui: tree arena exhausted");
            root.* = .{ .id = .none, .layout = .{ .kind = .stack, .main = .{ .grow = 1 }, .cross = .fill }, .flags = .{ .clip_children = true }, .paint = paintRoot, .root_index = 0 };
            self.roots.append(self.gpa, root) catch {};
            self.current_root = root;
            self.parent_stack.append(self.gpa, root) catch {};
            text.beginBuild();
            buildFn(ctx, self);
            if (self.parent_stack.items.len != 1) {
                @panic("nano_gui: begin/end 不配对（REQ-FRAME-028）");
            }
            _ = self.parent_stack.pop();
            self.id_stack.clearRetainingCapacity();
            self.build_passes += 1;
            core.stats.counter("frame.build_passes").* += 1;
            const needs_second = self.activation_seen or self.rebuild_requested;
            if (!needs_second) break;
            if (pass == 2) break;
            self.activation_seen = false;
            self.rebuild_requested = false;
        }
        self.pass = 0;
        self.built_this_frame = true;
        self.diff_root = old_root;
        self.prev_root = self.current_root;
        self.prev_map.clearRetainingCapacity();
        if (self.prev_root) |root| collectMap(root, &self.prev_map, self.gpa);
        // 回收本次构建未触达的 transient 槽（REQ-FRAME-010）。
        var remove = std.ArrayListUnmanaged(StateKey).empty;
        defer remove.deinit(self.gpa);
        var sit = self.states.iterator();
        while (sit.next()) |kv| {
            const slot = kv.value_ptr.*;
            if (slot.level == .transient and slot.touched != self.build_counter) remove.append(self.gpa, kv.key_ptr.*) catch {};
        }
        for (remove.items) |k| self.removeState(k);
        // sticky LRU：超过上限时回收最久未触达且本次未触达的槽（pinned 不回收）。
        var sticky_count: usize = 0;
        var sit2 = self.states.valueIterator();
        while (sit2.next()) |slot| if (slot.*.level == .sticky) {
            sticky_count += 1;
        };
        while (sticky_count > self.sticky_limit) {
            var victim: ?StateKey = null;
            var oldest: u64 = std.math.maxInt(u64);
            var oldest_serial: u64 = std.math.maxInt(u64);
            var vit = self.states.iterator();
            while (vit.next()) |kv| {
                const slot = kv.value_ptr.*;
                if (slot.level != .sticky or slot.touched == self.build_counter) continue;
                if (slot.last_touch < oldest or (slot.last_touch == oldest and slot.serial < oldest_serial)) {
                    oldest = slot.last_touch;
                    oldest_serial = slot.serial;
                    victim = kv.key_ptr.*;
                }
            }
            const v = victim orelse break;
            self.removeState(v);
            sticky_count -= 1;
        }
        self.dirty = .layout;
        self.applyPostBuildFocus();
    }

    fn applyPostBuildFocus(self: *Ui) void {
        if (self.clear_focus_requested) {
            self.focus_id = .none;
            self.clear_focus_requested = false;
        } else if (self.focus_after_build) |fid| {
            if (self.getNode(fid) != null and self.getNode(fid).?.flags.focusable and !self.getNode(fid).?.flags.disabled) {
                self.focus_id = fid;
            }
            self.focus_after_build = null;
        }
        if (self.focus_id != .none) {
            const n = self.getNode(self.focus_id);
            if (n == null or !n.?.flags.focusable or n.?.flags.disabled or n.?.flags.hidden) {
                self.focus_id = .none;
                var list = std.ArrayListUnmanaged(*Node).empty;
                defer list.deinit(self.gpa);
                if (self.current_root) |r| tabStops(r, &list, self.gpa);
                if (list.items.len > 0) self.focus_id = list.items[0].id;
            }
        } else {
            var list = std.ArrayListUnmanaged(*Node).empty;
            defer list.deinit(self.gpa);
            if (self.current_root) |r| tabStops(r, &list, self.gpa);
            if (list.items.len > 0) self.focus_id = list.items[0].id;
        }
    }

    fn collectMap(node: ?*Node, map: *std.AutoHashMapUnmanaged(u64, *Node), gpa: std.mem.Allocator) void {
        const n = node orelse return;
        map.put(gpa, n.id.raw(), n) catch {};
        var c = n.first_child;
        while (c) |cc| : (c = cc.next) collectMap(cc, map, gpa);
    }

    pub fn layoutTree(self: *Ui) void {
        if (self.dirty != .build and self.dirty != .layout) return;
        const root = self.current_root orelse return;
        const client = core.RectI{ .x = 0, .y = 0, .w = self.viewport.w, .h = self.viewport.h };
        self.measured_nodes = 0;
        self.arranged_nodes = 0;
        const lim = layout.Limit{ .w = client.w, .h = client.h, .definite_w = true, .definite_h = true };
        _ = self.measureNode(root, lim, .natural);
        self.arrangeNode(root, client, null);
        self.node_count = 0;
        countNodes(root, &self.node_count);
        self.computeDamage();
    }

    fn measureNode(self: *Ui, node: *Node, limit: layout.Limit, mode: layout.MeasureMode) layout.SizeI {
        if (node.measured_valid and limitEqual(node.measured_limit, limit) and node.measured_mode == mode) return node.measured;
        self.measured_nodes += 1;
        var size: layout.SizeI = .{};
        const p = &node.layout;
        const pad_w = px(p.padding.l, self.scale) + px(p.padding.r, self.scale);
        const pad_h = px(p.padding.t, self.scale) + px(p.padding.b, self.scale);
        switch (p.kind) {
            .leaf => {
                const cw = pxF(p.content.size.x, self.scale, true);
                const ch = pxF(p.content.size.y, self.scale, true);
                size = .{ .w = cw + pad_w, .h = ch + pad_h };
            },
            .row, .column, .table_row => {
                const vertical = p.kind == .column;
                var main_total: i32 = 0;
                var cross_max: i32 = 0;
                var count: usize = 0;
                var c = node.first_child;
                while (c) |child| : (c = child.next) {
                    if (child.layout.kind == .anchor) continue;
                    count += 1;
                    const child_lim = layout.Limit{
                        .w = if (vertical) limit.w else layout.unbounded,
                        .h = if (vertical) layout.unbounded else limit.h,
                    };
                    const cs = self.measureNode(child, child_lim, mode);
                    const cm = if (vertical) cs.h else cs.w;
                    const cc = if (vertical) cs.w else cs.h;
                    main_total += cm;
                    cross_max = @max(cross_max, cc);
                }
                const g = if (count > 1) pxGap(p.gap, self.scale) * @as(i32, @intCast(count - 1)) else 0;
                size = if (vertical)
                    .{ .w = cross_max + pad_w, .h = main_total + g + pad_h }
                else
                    .{ .w = main_total + g + pad_w, .h = cross_max + pad_h };
            },
            .stack, .form, .table => {
                var maxw: i32 = 0;
                var maxh: i32 = 0;
                var c = node.first_child;
                while (c) |child| : (c = child.next) {
                    if (child.layout.kind == .anchor) continue;
                    const cs = self.measureNode(child, limit, mode);
                    maxw = @max(maxw, cs.w);
                    maxh = @max(maxh, cs.h);
                }
                size = .{ .w = maxw + pad_w, .h = maxh + pad_h };
            },
            .scroll => |s| {
                var cw: i32 = 0;
                var ch: i32 = 0;
                if (node.first_child) |child| {
                    const cl = layout.Limit{
                        .w = if (s.axes == .vertical) @max(0, limit.w - pad_w) else layout.unbounded,
                        .h = if (s.axes == .horizontal) @max(0, limit.h - pad_h) else layout.unbounded,
                        .definite_w = s.axes == .vertical,
                        .definite_h = s.axes == .horizontal,
                    };
                    const cs = self.measureNode(child, cl, mode);
                    cw = cs.w;
                    ch = cs.h;
                }
                const bar = px(self.theme_ptr.metric(.scrollbar_w), self.scale);
                const need_v = s.axes != .horizontal and s.bar_v != .never;
                const need_h = s.axes != .vertical and s.bar_h != .never;
                size = .{
                    .w = @min(if (limit.definite_w) limit.w else cw + pad_w + (if (need_v) bar else 0), if (limit.definite_w) limit.w else layout.unbounded),
                    .h = @min(if (limit.definite_h) limit.h else ch + pad_h + (if (need_h) bar else 0), if (limit.definite_h) limit.h else layout.unbounded),
                };
                if (limit.definite_w) size.w = limit.w;
                if (limit.definite_h) size.h = limit.h;
            },
            .splitter => |s| {
                const sw = px(self.theme_ptr.metric(.splitter_w), self.scale);
                const min1 = px(s.min_first, self.scale);
                const min2 = px(s.min_second, self.scale);
                if (s.orientation == .horizontal) {
                    size = .{ .w = min1 + sw + min2 + pad_w, .h = if (limit.definite_h) limit.h else 100 };
                } else {
                    size = .{ .w = if (limit.definite_w) limit.w else 100, .h = min1 + sw + min2 + pad_h };
                }
            },
            .anchor => {
                size = .{ .w = 0, .h = 0 };
            },
            .custom => |cl| {
                var ctx = layout.MeasureCtx{ .scale = self.scale };
                size = cl.measure(&ctx, mode, limit);
            },
        }
        size.w = clampSize(size.w, p.main_min, p.main_max, self.scale);
        size.h = clampSize(size.h, p.cross_min, p.cross_max, self.scale);
        node.measured = size;
        node.measured_valid = true;
        node.measured_limit = limit;
        node.measured_mode = mode;
        return size;
    }

    fn arrangeNode(self: *Ui, node: *Node, rect: core.RectI, parent_abs: ?core.RectI) void {
        self.arranged_nodes += 1;
        node.rect = rect;
        const pabs = parent_abs orelse core.RectI{ .x = 0, .y = 0, .w = 0, .h = 0 };
        node.abs = .{ .x = pabs.x + rect.x, .y = pabs.y + rect.y, .w = rect.w, .h = rect.h };
        node.clip = node.abs;
        if (node.parent) |par| {
            node.clip = node.clip.intersect(par.clip);
        }
        if (node.flags.clip_children) {
            node.clip = node.clip.intersect(node.abs);
        }
        switch (node.layout.kind) {
            .row, .column, .table_row => {
                const vertical = node.layout.kind == .column;
                const pad = node.layout.padding;
                const inner = core.RectI{
                    .x = px(pad.l, self.scale),
                    .y = px(pad.t, self.scale),
                    .w = @max(0, rect.w - px(pad.l, self.scale) - px(pad.r, self.scale)),
                    .h = @max(0, rect.h - px(pad.t, self.scale) - px(pad.b, self.scale)),
                };
                var count: usize = 0;
                var c = node.first_child;
                while (c) |ch| : (c = ch.next) {
                    if (ch.layout.kind == .anchor) continue;
                    count += 1;
                }
                const gap = pxGap(node.layout.gap, self.scale);
                const avail = if (vertical) inner.h else inner.w;
                var items = std.ArrayListUnmanaged(layout.FlexItem).empty;
                defer items.deinit(self.gpa);
                var children = std.ArrayListUnmanaged(*Node).empty;
                defer children.deinit(self.gpa);
                c = node.first_child;
                while (c) |ch| : (c = ch.next) {
                    if (ch.layout.kind == .anchor) continue;
                    const natural = self.measureNode(ch, .{ .w = if (vertical) inner.w else layout.unbounded, .h = if (vertical) layout.unbounded else inner.h }, .natural);
                    const main_n = if (vertical) natural.h else natural.w;
                    var kind: layout.FlexKind = .fit;
                    var base = main_n;
                    var wq: u32 = 0;
                    switch (ch.layout.main) {
                        .fixed => |v| {
                            kind = .fixed;
                            base = px(v, self.scale);
                        },
                        .fit => kind = .fit,
                        .fit_shrink => kind = .shrink,
                        .grow => |w| {
                            kind = .grow;
                            base = 0;
                            wq = layout.quantizeWeight(w);
                        },
                    }
                    items.append(self.gpa, .{
                        .kind = kind,
                        .base = base,
                        .min = px(ch.layout.main_min, self.scale),
                        .max = if (ch.layout.main_max == std.math.inf(f32)) layout.unbounded else px(ch.layout.main_max, self.scale),
                        .wq = wq,
                    }) catch {};
                    children.append(self.gpa, ch) catch {};
                }
                const gap_total = if (children.items.len > 1) gap * @as(i32, @intCast(children.items.len - 1)) else 0;
                var sizes = std.ArrayListUnmanaged(i32).empty;
                defer sizes.deinit(self.gpa);
                sizes.appendNTimes(self.gpa, 0, children.items.len) catch {};
                const dr = layout.distribute(items.items, @max(0, avail - gap_total), sizes.items);
                _ = dr;
                var pos = if (vertical) inner.y else inner.x;
                for (children.items, 0..) |ch, i| {
                    const ms = sizes.items[i];
                    var cs: i32 = if (vertical) ch.measured.w else ch.measured.h;
                    switch (ch.layout.cross) {
                        .fixed => |v| cs = px(v, self.scale),
                        .fit => cs = if (vertical) ch.measured.w else ch.measured.h,
                        .fill => cs = if (vertical) inner.w else inner.h,
                    }
                    const cross_avail = if (vertical) inner.w else inner.h;
                    cs = @min(cs, cross_avail);
                    const alignment = ch.layout.self_align orelse node.layout.cross_align;
                    const off = switch (alignment) {
                        .start => 0,
                        .center => @divFloor(@max(0, cross_avail - cs), 2),
                        .end => @max(0, cross_avail - cs),
                    };
                    const child_rect = if (vertical)
                        core.RectI{ .x = inner.x + off, .y = pos, .w = cs, .h = ms }
                    else
                        core.RectI{ .x = pos, .y = inner.y + off, .w = ms, .h = cs };
                    self.arrangeNode(ch, child_rect, node.abs);
                    pos += ms + gap;
                }
                // Anchor 子项：按父内部矩形放置
                c = node.first_child;
                while (c) |ch| : (c = ch.next) {
                    if (ch.layout.kind == .anchor) self.arrangeAnchor(ch, inner, node.abs);
                }
            },
            .stack, .form, .table => {
                const inner = core.RectI{
                    .x = px(node.layout.padding.l, self.scale),
                    .y = px(node.layout.padding.t, self.scale),
                    .w = @max(0, rect.w - px(node.layout.padding.l, self.scale) - px(node.layout.padding.r, self.scale)),
                    .h = @max(0, rect.h - px(node.layout.padding.t, self.scale) - px(node.layout.padding.b, self.scale)),
                };
                var c = node.first_child;
                while (c) |ch| : (c = ch.next) {
                    if (ch.layout.kind == .anchor) {
                        self.arrangeAnchor(ch, inner, node.abs);
                        continue;
                    }
                    const ms = self.measureNode(ch, .{ .w = inner.w, .h = inner.h, .definite_w = true, .definite_h = true }, .natural);
                    var w = ms.w;
                    var h = ms.h;
                    switch (ch.layout.main) {
                        .fixed => |v| w = px(v, self.scale),
                        .grow => w = inner.w,
                        else => {},
                    }
                    switch (ch.layout.cross) {
                        .fixed => |v| h = px(v, self.scale),
                        .fill => h = inner.h,
                        else => {},
                    }
                    const main_align: layout.Align = ch.layout.self_main_align orelse switch (node.layout.justify) {
                        .center => .center,
                        .end => .end,
                        else => .start,
                    };
                    const ax = switch (main_align) {
                        .center => @divFloor(@max(0, inner.w - w), 2),
                        .end => @max(0, inner.w - w),
                        else => 0,
                    };
                    const ay = switch (ch.layout.self_align orelse node.layout.cross_align) {
                        .center => @divFloor(@max(0, inner.h - h), 2),
                        .end => @max(0, inner.h - h),
                        else => 0,
                    };
                    self.arrangeNode(ch, .{ .x = inner.x + ax, .y = inner.y + ay, .w = w, .h = h }, node.abs);
                }
            },
            .scroll => |s| {
                const bar = px(self.theme_ptr.metric(.scrollbar_w), self.scale);
                const inner = core.RectI{
                    .x = px(node.layout.padding.l, self.scale),
                    .y = px(node.layout.padding.t, self.scale),
                    .w = @max(0, rect.w - px(node.layout.padding.l, self.scale) - px(node.layout.padding.r, self.scale)),
                    .h = @max(0, rect.h - px(node.layout.padding.t, self.scale) - px(node.layout.padding.b, self.scale)),
                };
                var content_size = core.Size2i{};
                if (node.first_child) |child| {
                    const cl = layout.Limit{
                        .w = if (s.axes == .vertical) inner.w else layout.unbounded,
                        .h = if (s.axes == .horizontal) inner.h else layout.unbounded,
                        .definite_w = s.axes == .vertical,
                        .definite_h = s.axes == .horizontal,
                    };
                    content_size = self.measureNode(child, cl, .natural);
                }
                var viewport = inner;
                const need_v = s.axes != .horizontal and (s.bar_v == .always or content_size.h > inner.h);
                if (need_v) viewport.w = @max(0, viewport.w - bar);
                const need_h = s.axes != .vertical and (s.bar_h == .always or content_size.w > viewport.w);
                if (need_h) viewport.h = @max(0, viewport.h - bar);
                if (need_v and s.bar_v == .auto and node.first_child != null) {
                    const cl2 = layout.Limit{ .w = viewport.w, .h = if (s.axes == .horizontal) viewport.h else layout.unbounded, .definite_w = s.axes == .vertical, .definite_h = s.axes == .horizontal };
                    const c2 = self.measureNode(node.first_child.?, cl2, .natural);
                    content_size = c2;
                }
                const max_x = @max(0, content_size.w - viewport.w);
                const max_y = @max(0, content_size.h - viewport.h);
                var off_x: i32 = @intFromFloat(@round(s.offset.x * self.scale));
                var off_y: i32 = @intFromFloat(@round(s.offset.y * self.scale));
                off_x = std.math.clamp(off_x, 0, max_x);
                off_y = std.math.clamp(off_y, 0, max_y);
                if (s.anchor_end and max_y > 0 and @as(i32, @intFromFloat(@round(s.offset.y * self.scale))) >= max_y) off_y = max_y;
                node.scroll_metrics = .{
                    .offset = .{ .x = @as(f32, @floatFromInt(off_x)) / self.scale, .y = @as(f32, @floatFromInt(off_y)) / self.scale },
                    .offset_px = .{ .x = off_x, .y = off_y },
                    .max_offset = .{ .x = @as(f32, @floatFromInt(max_x)) / self.scale, .y = @as(f32, @floatFromInt(max_y)) / self.scale },
                    .viewport = .{ .x = @as(f32, @floatFromInt(viewport.x)) / self.scale, .y = @as(f32, @floatFromInt(viewport.y)) / self.scale, .w = @as(f32, @floatFromInt(viewport.w)) / self.scale, .h = @as(f32, @floatFromInt(viewport.h)) / self.scale },
                    .content = .{ .x = @as(f32, @floatFromInt(content_size.w)) / self.scale, .y = @as(f32, @floatFromInt(content_size.h)) / self.scale },
                    .bar_v = if (need_v) .{ .x = viewport.x + viewport.w, .y = viewport.y, .w = bar, .h = viewport.h } else null,
                    .bar_h = if (need_h) .{ .x = viewport.x, .y = viewport.y + viewport.h, .w = viewport.w, .h = bar } else null,
                };
                if (node.first_child) |child| {
                    const abs_viewport = core.RectI{
                        .x = node.abs.x + viewport.x,
                        .y = node.abs.y + viewport.y,
                        .w = viewport.w,
                        .h = viewport.h,
                    };
                    node.clip = node.clip.intersect(abs_viewport);
                    self.arrangeNode(child, .{ .x = viewport.x - off_x, .y = viewport.y - off_y, .w = @max(content_size.w, viewport.w), .h = @max(content_size.h, viewport.h) }, node.abs);
                    child.clip = child.clip.intersect(abs_viewport);
                }
            },
            .splitter => |s| {
                const sw = px(self.theme_ptr.metric(.splitter_w), self.scale);
                const inner = core.RectI{
                    .x = px(node.layout.padding.l, self.scale),
                    .y = px(node.layout.padding.t, self.scale),
                    .w = @max(0, rect.w - px(node.layout.padding.l, self.scale) - px(node.layout.padding.r, self.scale)),
                    .h = @max(0, rect.h - px(node.layout.padding.t, self.scale) - px(node.layout.padding.b, self.scale)),
                };
                const horizontal = s.orientation == .horizontal;
                const avail = if (horizontal) inner.w - sw else inner.h - sw;
                var first: i32 = switch (s.pos) {
                    .ratio => |r| @intFromFloat(@round(@as(f32, @floatFromInt(avail)) * std.math.clamp(r, 0, 1))),
                    .fixed_first => |v| px(v, self.scale),
                    .fixed_second => |v| avail - px(v, self.scale),
                };
                const min1 = px(s.min_first, self.scale);
                const min2 = px(s.min_second, self.scale);
                if (min1 + min2 > avail and min1 + min2 > 0) {
                    first = @divFloor(avail * min1, min1 + min2);
                } else {
                    first = std.math.clamp(first, min1, @max(min1, avail - min2));
                }
                const second = @max(0, avail - first);
                node.split_metrics = .{ .first_px = first, .second_px = second, .divider = if (horizontal) .{ .x = inner.x + first, .y = inner.y, .w = sw, .h = inner.h } else .{ .x = inner.x, .y = inner.y + first, .w = inner.w, .h = sw } };
                var idx: usize = 0;
                var c = node.first_child;
                while (c) |ch| : (c = ch.next) {
                    if (idx == 0) {
                        self.arrangeNode(ch, if (horizontal) .{ .x = inner.x, .y = inner.y, .w = first, .h = inner.h } else .{ .x = inner.x, .y = inner.y, .w = inner.w, .h = first }, node.abs);
                    } else if (idx == 1) {
                        self.arrangeNode(ch, if (horizontal) .{ .x = inner.x + first + sw, .y = inner.y, .w = second, .h = inner.h } else .{ .x = inner.x, .y = inner.y + first + sw, .w = inner.w, .h = second }, node.abs);
                    }
                    idx += 1;
                }
            },
            .anchor => {},
            .custom => {},
            .leaf => {},
        }
    }

    fn arrangeAnchor(self: *Ui, anchor: *Node, parent_inner: core.RectI, parent_abs: core.RectI) void {
        const a = switch (anchor.layout.kind) {
            .anchor => |ap| ap,
            else => layout.AnchorParams{},
        };
        const target_rel = switch (a.target) {
            .parent => parent_inner,
            .rect => |r| core.RectI{
                .x = parent_inner.x + @as(i32, @intFromFloat(@round(r.x * self.scale))),
                .y = parent_inner.y + @as(i32, @intFromFloat(@round(r.y * self.scale))),
                .w = @as(i32, @intFromFloat(@round(r.w * self.scale))),
                .h = @as(i32, @intFromFloat(@round(r.h * self.scale))),
            },
        };
        anchor.rect = .{ .x = parent_inner.x, .y = parent_inner.y, .w = parent_inner.w, .h = parent_inner.h };
        anchor.abs = .{ .x = parent_abs.x + anchor.rect.x, .y = parent_abs.y + anchor.rect.y, .w = anchor.rect.w, .h = anchor.rect.h };
        anchor.clip = if (a.bounds == .root) core.RectI{ .x = 0, .y = 0, .w = self.viewport.w, .h = self.viewport.h } else anchor.abs;
        if (anchor.first_child) |child| {
            const cs = self.measureNode(child, .{ .w = self.viewport.w, .h = self.viewport.h }, .natural);
            const gap = pxGap(a.gap, self.scale);
            const bounds = switch (a.bounds) {
                .parent => core.RectI{
                    .x = parent_abs.x + parent_inner.x,
                    .y = parent_abs.y + parent_inner.y,
                    .w = parent_inner.w,
                    .h = parent_inner.h,
                },
                .root => core.RectI{ .x = 0, .y = 0, .w = self.viewport.w, .h = self.viewport.h },
            };
            const target_root = core.RectI{
                .x = parent_abs.x + target_rel.x,
                .y = parent_abs.y + target_rel.y,
                .w = target_rel.w,
                .h = target_rel.h,
            };
            const res = layout.placeAnchored(target_root, cs, a.placement, gap, bounds);
            if (a.bounds == .root) self.popup_rect = res.rect;
            self.arrangeNode(child, .{
                .x = res.rect.x - parent_abs.x,
                .y = res.rect.y - parent_abs.y,
                .w = res.rect.w,
                .h = res.rect.h,
            }, parent_abs);
        }
    }

    // ---- 损伤与绘制 ----
    fn computeDamage(self: *Ui) void {
        const root = self.current_root orelse return;
        var damage = core.RectI{};
        var full = (self.dirty == .build and self.diff_root == null) or self.force_rebuild;
        if (full) {
            damage = .{ .x = 0, .y = 0, .w = self.viewport.w, .h = self.viewport.h };
        } else if (self.dirty == .layout) {
            if (self.viewport.w != self.lastViewportW() or self.viewport.h != self.lastViewportH()) full = true;
        }
        if (self.diff_root == null or self.built_this_frame) {
            // 差分
            var list = std.ArrayListUnmanaged(core.RectI).empty;
            defer list.deinit(self.gpa);
            diffTree(self.diff_root, root, &list, self.gpa);
            for (list.items) |r| damage = unionRects(damage, r);
        }
        for (self.invalidated_rects.items) |r| damage = unionRects(damage, r);
        self.invalidated_rects.clearRetainingCapacity();
        if (full) damage = .{ .x = 0, .y = 0, .w = self.viewport.w, .h = self.viewport.h };
        if (damage.isEmpty() and self.dirty == .paint) damage = .{ .x = 0, .y = 0, .w = self.viewport.w, .h = self.viewport.h };
        if (damage.area() * 2 >= @as(i64, self.viewport.w) * @as(i64, self.viewport.h)) {
            damage = .{ .x = 0, .y = 0, .w = self.viewport.w, .h = self.viewport.h };
        }
        self.damage = damage;
        self.last_damage_area = damage.area();
        self.last_viewport_w = self.viewport.w;
        self.last_viewport_h = self.viewport.h;
    }

    fn lastViewportW(self: *const Ui) i32 {
        return self.last_viewport_w;
    }
    fn lastViewportH(self: *const Ui) i32 {
        return self.last_viewport_h;
    }

    pub fn paint(self: *Ui, surface: *gfx.Surface) bool {
        if (self.current_root == null) return false;
        if (self.damage.isEmpty()) {
            self.dirty = .none;
            return false;
        }
        const canvas = surface.beginFrame(self.damage, self.scale);
        var ctx = PaintCtx{
            .draw = .{ .canvas = canvas, .theme = self.theme_ptr, .scale = self.scale, .window_active = self.window_active },
            .now = self.frame_now,
            .ui = self,
        };
        canvas.clip = self.damage.intersect(.{ .x = 0, .y = 0, .w = @intCast(surface.width), .h = @intCast(surface.height) });
        self.painted_nodes = 0;
        paintTree(&ctx, self.current_root.?, self.damage);
        paintOverlayTrees(&ctx, self.current_root.?, self.damage);
        for (self.overlays.items) |ov| {
            const r = core.RectI{ .x = @intFromFloat(@round(ov.rect.x * self.scale)), .y = @intFromFloat(@round(ov.rect.y * self.scale)), .w = @intFromFloat(@round(ov.rect.w * self.scale)), .h = @intFromFloat(@round(ov.rect.h * self.scale)) };
            if (!r.intersect(self.damage).isEmpty()) ov.paint(&ctx, ov.rect, ov.props);
        }
        if (self.show_damage) {
            canvas.strokeRect(.{
                .x = @as(f32, @floatFromInt(self.damage.x)) / self.scale,
                .y = @as(f32, @floatFromInt(self.damage.y)) / self.scale,
                .w = @as(f32, @floatFromInt(self.damage.w)) / self.scale,
                .h = @as(f32, @floatFromInt(self.damage.h)) / self.scale,
            }, .{ .r = 255, .g = 0, .b = 255, .a = 180 }, 1);
        }
        surface.endFrame();
        surface.present();
        if (self.window) |w| {
            w.present_rgba = surface.presented;
            w.present_w = surface.width;
            w.present_h = surface.height;
            platform.present(w);
        }
        self.dirty = .none;
        self.frame_count += 1;
        _ = core.stats.gauge("frame.damage_area");
        core.stats.counter("frame.damage_area_ppx").* += @intCast(@max(0, self.damage.area()));
        core.stats.counter("frame.nodes_painted").* += self.painted_nodes;
        core.stats.counter("frame.presents").* += 1;
        core.stats.gauge("frame.nodes").* = self.node_count;
        core.stats.counter("frame.nodes_measure_reused").* += self.measure_reused;
        core.stats.gauge("alloc.arena.bytes").* = self.frame.bytesUsed() + self.tree_a.bytesUsed() + self.tree_b.bytesUsed();
        return true;
    }

    fn paintTree(ctx: *PaintCtx, node: *Node, damage: core.RectI) void {
        if (node.flags.hidden) return;
        if (node.flags.overlay) return;
        const r = node.abs;
        if (!r.intersect(damage).isEmpty()) {
            if (node.paint) |f| {
                f(ctx, node);
                ctx.ui.painted_nodes += 1;
            }
        }
        if (node.flags.clip_children) {
            ctx.draw.canvas.pushClip(.{
                .x = @as(f32, @floatFromInt(node.clip.x)) / ctx.draw.scale,
                .y = @as(f32, @floatFromInt(node.clip.y)) / ctx.draw.scale,
                .w = @as(f32, @floatFromInt(node.clip.w)) / ctx.draw.scale,
                .h = @as(f32, @floatFromInt(node.clip.h)) / ctx.draw.scale,
            });
        }
        var c = node.first_child;
        while (c) |cc| : (c = cc.next) paintTree(ctx, cc, damage);
        if (node.flags.clip_children) ctx.draw.canvas.popClip();
    }

    pub fn finishFrame(self: *Ui) void {
        // 回收过期定时器。
        var tdel = std.ArrayListUnmanaged(u64).empty;
        defer tdel.deinit(self.gpa);
        var tit = self.timers.iterator();
        while (tit.next()) |kv| {
            if (kv.value_ptr.touched + 2 < self.build_counter) tdel.append(self.gpa, kv.key_ptr.*) catch {};
        }
        for (tdel.items) |k| _ = self.timers.remove(k);
        // 帧后动作在帧状态清除后执行。
        self.frame.reset();
        self.clearInbox();
        self.pending.clearRetainingCapacity();
        self.interaction_cache.clearRetainingCapacity();
        for (self.after_frame.items) |cl| cl.func(cl.ctx);
        self.after_frame.clearRetainingCapacity();
        core.stats.counter("frame.count").* += 1;
    }

    fn clearInbox(self: *Ui) void {
        var it = self.inbox.valueIterator();
        while (it.next()) |list| list.deinit(self.gpa);
        self.inbox.clearRetainingCapacity();
    }

    pub fn needsFrame(self: *const Ui) bool {
        return self.dirty != .none or self.haveActiveAnimations();
    }

    pub fn scrollMetrics(self: *const Ui, widget_id: core.WidgetId) ?layout.ScrollMetrics {
        if (self.prev_map.get(widget_id.raw())) |n| return n.scroll_metrics;
        return null;
    }
    pub fn splitMetrics(self: *const Ui, widget_id: core.WidgetId) ?layout.SplitMetrics {
        if (self.prev_map.get(widget_id.raw())) |n| return n.split_metrics;
        return null;
    }
    pub fn minWindowSize(self: *const Ui) core.Vec2 {
        const root = self.current_root orelse return .{};
        return .{ .x = @as(f32, @floatFromInt(root.measured.w)) / self.scale, .y = @as(f32, @floatFromInt(root.measured.h)) / self.scale };
    }
};

fn countNodes(node: *Node, out: *u32) void {
    out.* += 1;
    var c = node.first_child;
    while (c) |cc| : (c = cc.next) countNodes(cc, out);
}

fn limitEqual(a: layout.Limit, b: layout.Limit) bool {
    return a.w == b.w and a.h == b.h and a.definite_w == b.definite_w and a.definite_h == b.definite_h;
}

fn px(v: f32, scale: f32) i32 {
    if (v == 0) return 0;
    if (v == std.math.inf(f32)) return layout.unbounded;
    return @max(1, @as(i32, @intFromFloat(@round(v * scale))));
}
fn pxF(v: f32, scale: f32, ceil_mode: bool) i32 {
    if (v == 0) return 0;
    if (ceil_mode) return @max(1, @as(i32, @intFromFloat(@ceil(v * scale - 0.001))));
    return px(v, scale);
}
fn pxGap(g: theme.Gap, scale: f32) i32 {
    return switch (g) {
        .none => 0,
        .xs => px(2, scale),
        .sm => px(4, scale),
        .md => px(8, scale),
        .lg => px(12, scale),
        .xl => px(16, scale),
        .xxl => px(24, scale),
    };
}
fn clampSize(v: i32, min_lpx: f32, max_lpx: f32, scale: f32) i32 {
    const mn = px(min_lpx, scale);
    const mx = if (max_lpx == std.math.inf(f32)) layout.unbounded else px(max_lpx, scale);
    const hi = if (mx < mn) mn else mx;
    return std.math.clamp(v, mn, hi);
}
fn unionRects(a: core.RectI, b: core.RectI) core.RectI {
    return a.unionRect(b);
}

fn diffTree(old: ?*Node, new: ?*Node, out: *std.ArrayListUnmanaged(core.RectI), gpa: std.mem.Allocator) void {
    if (old == null and new == null) return;
    if (old == null) {
        out.append(gpa, new.?.abs) catch {};
        return;
    }
    if (new == null) {
        out.append(gpa, old.?.abs) catch {};
        return;
    }
    const o = old.?;
    const n = new.?;
    if (o.rect.x != n.rect.x or o.rect.y != n.rect.y or o.rect.w != n.rect.w or o.rect.h != n.rect.h) out.append(gpa, unionRects(o.abs, n.abs)) catch {};
    if (o.paint_key != n.paint_key) out.append(gpa, n.abs) catch {};
    var oc = o.first_child;
    var nc = n.first_child;
    while (oc != null or nc != null) {
        diffTree(oc, nc, out, gpa);
        if (oc != null) oc = oc.?.next;
        if (nc != null) nc = nc.?.next;
    }
}

fn easeOut(t: f32) f32 {
    const mt = 1 - t;
    return 1 - mt * mt * mt;
}

fn paintPopupPanel(ctx: *PaintCtx, node: *const Node) void {
    theme.drawPopupFrame(&ctx.draw, ctx.rect(node), false);
}

fn paintRoot(ctx: *PaintCtx, node: *const Node) void {
    _ = node;
    ctx.draw.canvas.fillRect(.{
        .x = 0,
        .y = 0,
        .w = @as(f32, @floatFromInt(ctx.ui.viewport.w)) / ctx.draw.scale,
        .h = @as(f32, @floatFromInt(ctx.ui.viewport.h)) / ctx.draw.scale,
    }, ctx.draw.theme.color(.surface_window));
}

pub const PaintCtx = struct {
    draw: theme.DrawCtx,
    now: u64,
    ui: *Ui,

    pub fn rect(self: *const PaintCtx, node: *const Node) core.Rect {
        return .{
            .x = @as(f32, @floatFromInt(node.abs.x)) / self.draw.scale,
            .y = @as(f32, @floatFromInt(node.abs.y)) / self.draw.scale,
            .w = @as(f32, @floatFromInt(node.abs.w)) / self.draw.scale,
            .h = @as(f32, @floatFromInt(node.abs.h)) / self.draw.scale,
        };
    }

    pub fn visual(self: *const PaintCtx, node: *const Node) theme.Visual {
        _ = self;
        return .{
            .hovered = node.interaction.hovered,
            .pressed = node.interaction.pressed or (node.interaction.captured and node.interaction.pressed),
            .focused_visible = node.interaction.focus_visible,
            .disabled = node.interaction.disabled,
            .hover_t = if (node.interaction.hovered) 1 else 0,
            .press_t = if (node.interaction.pressed) 1 else 0,
            .focus_t = if (node.interaction.focus_visible) 1 else 0,
        };
    }

    pub fn anim(self: *const PaintCtx, node: *const Node, slot: u8) f32 {
        const key = (node.id.raw() << 8) | slot;
        if (self.ui.anims.get(key)) |a| return a.current;
        return 0;
    }

    pub fn stateOf(self: *const PaintCtx, comptime T: type, node: *const Node) ?*const T {
        const key = StateKey{ .id = node.id.raw(), .type_id = core.hashBytes(0x9e3779b9, @typeName(T)) ^ @as(u64, @sizeOf(T)) *% 0x100000001b3 };
        if (self.ui.states.get(key)) |slot| return @ptrCast(@alignCast(slot.data));
        return null;
    }
};
