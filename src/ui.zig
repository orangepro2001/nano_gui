//! 受控即时模式帧模型（06）：ID、状态存储、节点树、脏标记、损伤、动画与定时器。

const std = @import("std");
const core = @import("core.zig");
const platform = @import("platform.zig");
const gfx = @import("gfx.zig");
const text = @import("text.zig");
const theme = @import("theme.zig");
const layout = @import("layout.zig");
const input = @import("input.zig");
const builtin = @import("builtin");

pub const WidgetId = core.WidgetId;

pub const Dirty = enum(u8) { none = 0, paint = 1, layout = 2, build = 3 };

/// 帧阶段（REQ-FRAME-020）。仅供测试观察阶段顺序。
pub const FramePhase = enum { collect, dispatch, build, layout, damage, paint, submit, finish };
pub var test_phase_hook: ?*const fn (?*anyopaque, FramePhase) void = null;
/// 测试：强制走“发布构建”的不配对恢复路径。
pub var test_force_soft_unbalanced: bool = false;
/// 测试：强制走“发布构建”的重复 ID 恢复路径。
pub var test_force_soft_duplicate: bool = false;
pub var test_phase_ctx: ?*anyopaque = null;
pub fn notePhase(phase: FramePhase) void {
    if (test_phase_hook) |f| f(test_phase_ctx, phase);
}
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
    first_child: ?*Node = null,
    next: ?*Node = null,
    rect: core.RectI = .{},
    abs: core.RectI = .{},
    clip: core.RectI = .{},
    scroll_metrics: ?*layout.ScrollMetrics = null,
    split_metrics: ?*layout.SplitMetrics = null,
    id: core.WidgetId,
    parent: ?*Node = null,
    last_child: ?*Node = null,
    prev: ?*Node = null,
    layout: layout.Params = .{},
    flags: NodeFlags = .{},
    paint: ?PaintFn = null,
    props: ?*const anyopaque = null,
    paint_key: u64 = 0,
    paint_outset: f32 = 0,
    measured: layout.SizeI = .{},
    measured_valid: bool = false,
    measured_limit: layout.Limit = .{ .w = 0, .h = 0 },
    measured_mode: layout.MeasureMode = .natural,
    measured2: layout.SizeI = .{},
    measured2_valid: bool = false,
    measured2_limit: layout.Limit = .{ .w = 0, .h = 0 },
    measured2_mode: layout.MeasureMode = .natural,
    interact_opts: input.InteractOpts = .{},
    registered_interact: bool = false,
    interaction: input.Interaction = .{},
    debug_name: ?[]const u8 = null,
    visible: bool = true,
    src_file: []const u8 = "",
    src_line: u32 = 0,
    root_index: usize = 0,
    layout_hash: u64 = 0,
    min_measured: layout.SizeI = .{},
    min_measured_valid: bool = false,
    reused_measure: bool = false,
    diff_checked: bool = false,
    reused_from: ?*const Node = null,
    has_feedback: bool = false,
    has_anchor_child: bool = false,
    has_hfw: bool = false,
    subtree_count: u32 = 1,
    fit_shrink_warned: bool = false,
    /// 构建期间 lastRect 观察到的尺寸（ppx）；未调用时 seen_last_rect 为 false。
    seen_last_rect: bool = false,
    seen_w: i32 = 0,
    seen_h: i32 = 0,
};

const LoopAnim = struct {
    level: Dirty,
    touched: u64,
};

const MnemonicReg = struct {
    id: core.WidgetId,
    ch: u21,
    action: input.MnemonicAction,
};

const FocusGroupReg = struct {
    id: core.WidgetId,
    spec: input.GroupSpec,
};

const FocusScopeReg = struct {
    id: core.WidgetId,
    spec: input.ScopeSpec,
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

const AnimKey = struct { id: u64, slot: u8 };

const Anim = struct {
    widget_id: u64 = 0,
    current: f32 = 0,
    start: f32 = 0,
    target: f32 = 0,
    start_ms: u64 = 0,
    duration_ms: u16 = 0,
    level: Dirty = .paint,
    easing: theme.Easing = .out,
    initialized: bool = false,
    /// 最近一次被声明的构建代（REQ-FRAME-045：节点停止声明后动画记忆随之失效）。
    touched: u64 = 0,
};

const BlinkState = struct {
    next_ms: u64,
    interval_ms: u32,
    rect: core.RectI,
    on: bool = true,
    touched: u64,
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
    nodes_a: core.FrameArena,
    nodes_b: core.FrameArena,
    tree_is_a: bool = true,
    current_root: ?*Node = null,
    prev_root: ?*Node = null,
    diff_root: ?*Node = null,
    roots: std.ArrayListUnmanaged(*Node) = .empty,
    prev_roots: std.ArrayListUnmanaged(*Node) = .empty,
    node_map: std.AutoHashMapUnmanaged(u64, *Node) = .empty,
    prev_map: std.AutoHashMapUnmanaged(u64, *Node) = .empty,
    diff_map: std.AutoHashMapUnmanaged(u64, *Node) = .empty,
    pending_seen: std.AutoHashMapUnmanaged(u64, struct { w: i32, h: i32 }) = .empty,
    seen_id_src: std.AutoHashMapUnmanaged(u64, std.builtin.SourceLocation) = .empty,
    dup_reported: std.AutoHashMapUnmanaged(u64, void) = .empty,
    id_stack: std.ArrayListUnmanaged(u64) = .empty,
    parent_stack: std.ArrayListUnmanaged(*Node) = .empty,
    container_stack: std.ArrayListUnmanaged(std.builtin.SourceLocation) = .empty,
    overlays: std.ArrayListUnmanaged(OverlaySpec) = .empty,
    prev_overlays: std.ArrayListUnmanaged(OverlaySpec) = .empty,
    states: std.AutoHashMapUnmanaged(StateKey, *StateSlot) = .empty,
    anims: std.AutoHashMapUnmanaged(AnimKey, Anim) = .empty,
    timers: std.AutoHashMapUnmanaged(u64, Timer) = .empty,
    blinks: std.AutoHashMapUnmanaged(u64, BlinkState) = .empty,
    inbox: std.AutoHashMapUnmanaged(u64, std.ArrayListUnmanaged(input.NodeEvent)) = .empty,
    pending: std.AutoHashMapUnmanaged(u64, Pending) = .empty,
    interaction_cache: std.AutoHashMapUnmanaged(u64, input.Interaction) = .empty,
    command_states: std.AutoHashMapUnmanaged(u32, input.CommandState) = .empty,
    command_queue: std.ArrayListUnmanaged(input.CommandId) = .empty,
    after_frame: std.ArrayListUnmanaged(core.Closure) = .empty,
    build_counter: u64 = 0,
    frame_now: u64 = 0,
    pass: u8 = 0,
    dirty: Dirty = .build,
    /// 构建期间发出的失效（REQ-FRAME-023）：构建结束时与 .layout 取较高者并入 dirty。
    pending_dirty: Dirty = .none,
    /// 需要延续到下一帧的失效（构建期间合并的 .build），在 finishFrame 清除 dirty 后写回。
    carry_dirty: Dirty = .none,
    /// 当前是否处于构建遍内。
    building: bool = false,
    /// 当前是否正在执行帧后动作。
    running_after_frame: bool = false,
    /// 初始焦点是否已设置过（REQ-INPUT-043：仅根首次构建完成后）。
    initial_focus_done: bool = false,
    invalidated_rects: std.ArrayListUnmanaged(core.RectI) = .empty,
    damage: core.RectI = .{},
    damage_rects: [8]core.RectI = @splat(.{}),
    damage_count: usize = 0,
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
    pointer_screen: ?core.Vec2i = null,
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
    rebuild_streak: u32 = 0,
    rebuild_storm_warned: bool = false,
    rebuild_src_file: []const u8 = "",
    rebuild_src_line: u32 = 0,
    build_passes: u32 = 0,
    frame_count: u64 = 0,
    frame_generation: u64 = 0,
    frame_did_layout: bool = false,
    last_frame_damage: core.RectI = .{},
    repaint_all: bool = false,
    inspect_active: bool = false,
    min_window: core.Vec2 = .{},
    last_scroll_axis_limit: ?layout.Limit = null,
    scroll_states: std.AutoHashMapUnmanaged(u64, struct { req_y: i32, max_y: i32, has: bool }) = .empty,
    hfw_calls: u32 = 0,
    scroll_remeasures: u32 = 0,
    painted_nodes: u32 = 0,
    node_count: u32 = 0,
    measure_reused: u32 = 0,
    measured_nodes: u32 = 0,
    arranged_nodes: u32 = 0,
    last_damage_area: i64 = 0,
    show_damage: bool = false,
    /// 当前处于绘制遍内；绘制函数不得发出失效（REQ-FRAME-018）。
    in_paint: bool = false,
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
    loop_anims: std.AutoHashMapUnmanaged(AnimKey, LoopAnim) = .empty,
    disable_animations: bool = false,
    hover_enter_ms: u64 = 0,
    hover_leave_id: core.WidgetId = .none,
    hover_leave_ms: u64 = 0,
    focus_groups: std.ArrayListUnmanaged(FocusGroupReg) = .empty,
    focus_scopes: std.ArrayListUnmanaged(FocusScopeReg) = .empty,
    root_scope_spec: input.ScopeSpec = .{},
    mnemonics_list: std.ArrayListUnmanaged(MnemonicReg) = .empty,
    active_drag: ?input.DragInfo = null,
    drop_target_id: core.WidgetId = .none,
    dropped_id: core.WidgetId = .none,
    dropped_payload: ?input.DragPayload = null,
    dropped_pos: core.Vec2 = .{},
    tooltip_owner: core.WidgetId = .none,
    tooltip_text: []const u8 = "",
    owns_text: bool = false,

    pub fn init(gpa: std.mem.Allocator) Ui {
        core.stats.initRegistry();
        var owns = false;
        if (!text.isInitialized()) {
            text.init(gpa, .{}) catch {};
            owns = true;
        }
        return .{
            .gpa = gpa,
            .frame = core.FrameArena.init(gpa),
            .tree_a = core.FrameArena.init(gpa),
            .tree_b = core.FrameArena.init(gpa),
            .nodes_a = core.FrameArena.init(gpa),
            .nodes_b = core.FrameArena.init(gpa),
            .owns_text = owns,
        };
    }

    pub fn deinit(self: *Ui) void {
        if (self.owns_text) text.deinit();
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
        self.blinks.deinit(self.gpa);
        self.inbox.deinit(self.gpa);
        self.pending.deinit(self.gpa);
        self.interaction_cache.deinit(self.gpa);
        self.command_states.deinit(self.gpa);
        self.command_queue.deinit(self.gpa);
        self.after_frame.deinit(self.gpa);
        self.node_map.deinit(self.gpa);
        self.prev_map.deinit(self.gpa);
        self.diff_map.deinit(self.gpa);
        self.pending_seen.deinit(self.gpa);
        self.seen_id_src.deinit(self.gpa);
        self.dup_reported.deinit(self.gpa);
        self.roots.deinit(self.gpa);
        self.prev_roots.deinit(self.gpa);
        self.id_stack.deinit(self.gpa);
        self.parent_stack.deinit(self.gpa);
        self.container_stack.deinit(self.gpa);
        self.scroll_states.deinit(self.gpa);
        self.overlays.deinit(self.gpa);
        self.prev_overlays.deinit(self.gpa);
        self.invalidated_rects.deinit(self.gpa);
        self.loop_anims.deinit(self.gpa);
        self.focus_groups.deinit(self.gpa);
        self.focus_scopes.deinit(self.gpa);
        self.mnemonics_list.deinit(self.gpa);
        if (self.tooltip_text.len > 0) self.gpa.free(self.tooltip_text);
        self.frame.deinit();
        self.tree_a.deinit();
        self.tree_b.deinit();
        self.nodes_a.deinit();
        self.nodes_b.deinit();
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

    /// 帧竞技场重置代数；帧后动作可据此断言帧状态已清除。
    pub fn frameGeneration(self: *const Ui) u64 {
        return self.frame_generation;
    }
    /// 至下次构建有效（REQ-ARCH-012 的树竞技场）。
    pub fn treeAlloc(self: *Ui) std.mem.Allocator {
        return if (self.tree_is_a) self.tree_a.allocator() else self.tree_b.allocator();
    }
    fn nodeAlloc(self: *Ui) std.mem.Allocator {
        return if (self.tree_is_a) self.nodes_a.allocator() else self.nodes_b.allocator();
    }
    /// 本帧时间戳（ms）。
    pub fn scaleFactor(self: *const Ui) f32 {
        return self.scale;
    }

    // ---- 标识 ID ----
    pub fn id(self: *Ui, src: std.builtin.SourceLocation, key: ?Key) core.WidgetId {
        const parent_seed: u64 = if (self.id_stack.items.len > 0) self.id_stack.items[self.id_stack.items.len - 1] else 0;
        var seed = core.hashBytes(parent_seed, src.file);
        seed = core.hashU64(seed, src.line);
        seed = core.hashU64(seed, src.column);
        if (key) |k| seed = core.hashU64(seed, k.hash);
        const out = core.WidgetId.fromHash(seed);
        if (comptime builtin.optimize == .debug) {
            self.seen_id_src.put(self.gpa, out.raw(), src) catch {};
        }
        return out;
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
        if (self.node_map.contains(widget_id.raw())) {
            var buf: [256]u8 = undefined;
            const src = self.seen_id_src.get(widget_id.raw()) orelse std.builtin.SourceLocation{
                .module = "nano_gui",
                .file = "<unknown>",
                .fn_name = "<unknown>",
                .line = 0,
                .column = 0,
            };
            const msg = std.fmt.bufPrint(&buf, "同一构建内重复的控件 ID：{s}:{d}", .{ src.file, src.line }) catch "同一构建内重复的控件 ID";
            const hard = builtin.optimize == .debug and !test_force_soft_duplicate;
            if (hard) std.debug.panic("{s}", .{msg});
            if (!self.dup_reported.contains(widget_id.raw())) {
                self.dup_reported.put(self.gpa, widget_id.raw(), {}) catch {};
                core.log.write(.err, "frame", "{s}", .{msg});
            }
        }
        const alloc = self.nodeAlloc();
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
        if (self.pending_seen.get(widget_id.raw())) |seen| {
            node.seen_last_rect = true;
            node.seen_w = seen.w;
            node.seen_h = seen.h;
        }
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

    fn endContainerNode(self: *Ui) void {
        _ = self.container_stack.pop();
        self.endNode();
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
        if (self.building) return self.diff_map.get(widget_id.raw());
        return self.node_map.get(widget_id.raw());
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
        self.endContainerNode();
    }
    pub fn beginRow(self: *Ui, src: std.builtin.SourceLocation, o: layout.ContainerOptions) core.WidgetId {
        return self.beginContainer(src, o, .row);
    }
    pub fn endRow(self: *Ui) void {
        self.endContainerNode();
    }
    pub fn beginStack(self: *Ui, src: std.builtin.SourceLocation, o: layout.ContainerOptions) core.WidgetId {
        return self.beginContainer(src, o, .stack);
    }
    pub fn endStack(self: *Ui) void {
        self.endContainerNode();
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
        self.container_stack.append(self.gpa, src) catch {};
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
        self.container_stack.append(self.gpa, src) catch {};
        _ = self.beginNode(widget_id, .{ .layout = p, .flags = .{ .clip_children = true, .hidden = o.hidden } });
        self.setDebugName(widget_id, o.debug_name);
        return widget_id;
    }
    pub fn endScroll(self: *Ui) void {
        self.endContainerNode();
    }

    pub fn beginSplitter(self: *Ui, src: std.builtin.SourceLocation, o: layout.ContainerOptions, s: layout.SplitterParams) core.WidgetId {
        const widget_id = self.id(src, null);
        const p = layout.Params{ .kind = .{ .splitter = s }, .main = o.main, .cross = o.cross, .padding = o.padding };
        self.container_stack.append(self.gpa, src) catch {};
        _ = self.beginNode(widget_id, .{ .layout = p, .flags = .{ .clip_children = true } });
        self.setDebugName(widget_id, o.debug_name);
        return widget_id;
    }
    pub fn endSplitter(self: *Ui) void {
        self.endContainerNode();
    }

    pub fn beginTable(self: *Ui, src: std.builtin.SourceLocation, o: layout.ContainerOptions, t: layout.TableParams) core.WidgetId {
        const widget_id = self.id(src, null);
        const p = layout.Params{ .kind = .{ .table = t }, .main = o.main, .cross = o.cross, .padding = o.padding, .gap = o.gap };
        self.container_stack.append(self.gpa, src) catch {};
        _ = self.beginNode(widget_id, .{ .layout = p, .flags = .{ .clip_children = true } });
        self.setDebugName(widget_id, o.debug_name);
        return widget_id;
    }
    pub fn beginTableRow(self: *Ui, src: std.builtin.SourceLocation, o: layout.ContainerOptions) core.WidgetId {
        const widget_id = self.id(src, null);
        const p = layout.Params{ .kind = .table_row, .main = o.main, .cross = o.cross, .padding = o.padding, .gap = o.gap };
        self.container_stack.append(self.gpa, src) catch {};
        _ = self.beginNode(widget_id, .{ .layout = p });
        return widget_id;
    }
    pub fn endTableRow(self: *Ui) void {
        self.endContainerNode();
    }
    pub fn endTable(self: *Ui) void {
        self.endContainerNode();
    }

    pub fn beginForm(self: *Ui, src: std.builtin.SourceLocation, o: layout.ContainerOptions, f: layout.FormParams) core.WidgetId {
        const widget_id = self.id(src, null);
        const p = layout.Params{ .kind = .{ .form = f }, .main = o.main, .cross = o.cross, .padding = o.padding, .gap = o.gap, .cross_align = o.cross_align };
        self.container_stack.append(self.gpa, src) catch {};
        _ = self.beginNode(widget_id, .{ .layout = p });
        self.setDebugName(widget_id, o.debug_name);
        return widget_id;
    }
    pub fn endForm(self: *Ui) void {
        self.endContainerNode();
    }

    pub fn beginAnchor(self: *Ui, src: std.builtin.SourceLocation, a: layout.AnchorParams) core.WidgetId {
        const widget_id = self.id(src, null);
        const p = layout.Params{ .kind = .{ .anchor = a }, .main = .fit, .cross = .fit };
        self.container_stack.append(self.gpa, src) catch {};
        _ = self.beginNode(widget_id, .{ .layout = p });
        return widget_id;
    }
    pub fn endAnchor(self: *Ui) void {
        self.endContainerNode();
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

    pub fn lastRect(self: *Ui, widget_id: core.WidgetId) ?core.Rect {
        const r0 = self.lastRectPx(widget_id) orelse return null;
        return .{
            .x = @as(f32, @floatFromInt(r0.x)) / self.scale,
            .y = @as(f32, @floatFromInt(r0.y)) / self.scale,
            .w = @as(f32, @floatFromInt(r0.w)) / self.scale,
            .h = @as(f32, @floatFromInt(r0.h)) / self.scale,
        };
    }
    pub fn lastRectPx(self: *Ui, widget_id: core.WidgetId) ?core.RectI {
        if (self.getPrevNode(widget_id)) |n| {
            if (n.rect.w != 0 or n.rect.h != 0) {
                if (self.node_map.get(widget_id.raw())) |cur| {
                    cur.seen_last_rect = true;
                    cur.seen_w = n.abs.w;
                    cur.seen_h = n.abs.h;
                } else {
                    self.pending_seen.put(self.gpa, widget_id.raw(), .{ .w = n.abs.w, .h = n.abs.h }) catch {};
                }
                return n.abs;
            }
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
            // 同一槽被以更高保留级别再次请求时升级（如 transient → sticky）。
            if (@backingInt(level) > @backingInt(slot.level)) slot.level = level;
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
        core.stats.counter("alloc.state.count").* += 1;
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
            // 同一槽被以更高保留级别再次请求时升级（如 transient → sticky）。
            if (@backingInt(level) > @backingInt(slot.level)) slot.level = level;
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
        core.stats.counter("alloc.state.count").* += 1;
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
        std.debug.assert(!self.in_paint); // REQ-FRAME-018：绘制函数不得发出失效
        if (self.building) {
            if (@backingInt(level) > @backingInt(self.pending_dirty)) self.pending_dirty = level;
            return;
        }
        if (@backingInt(level) > @backingInt(self.dirty)) self.dirty = level;
    }
    pub fn invalidateNode(self: *Ui, widget_id: core.WidgetId, level: Dirty) void {
        self.invalidate(level);
        if (self.getPrevNode(widget_id)) |n| {
            if (@backingInt(level) <= @backingInt(Dirty.paint)) {
                const r = outsetPx(n.abs, n.paint_outset, self.scale);
                self.invalidated_rects.append(self.gpa, r) catch {};
                self.damage = unionRects(self.damage, r);
                self.promoteDamage();
            }
        }
    }

    fn promoteDamage(self: *Ui) void {
        if (self.damage.area() * 2 >= @as(i64, self.viewport.w) * @as(i64, self.viewport.h)) {
            self.damage = .{ .x = 0, .y = 0, .w = self.viewport.w, .h = self.viewport.h };
        }
    }
    pub fn invalidateRect(self: *Ui, _: RootId, rect: core.Rect) void {
        std.debug.assert(!self.in_paint); // REQ-FRAME-018：绘制函数不得发出失效
        self.invalidate(.paint);
        const r = core.RectI{
            .x = @intFromFloat(@round(rect.x * self.scale)),
            .y = @intFromFloat(@round(rect.y * self.scale)),
            .w = @intFromFloat(@round(rect.w * self.scale)),
            .h = @intFromFloat(@round(rect.h * self.scale)),
        };
        self.damage = unionRects(self.damage, r);
        self.invalidated_rects.append(self.gpa, .{
            .x = @intFromFloat(@round(rect.x * self.scale)),
            .y = @intFromFloat(@round(rect.y * self.scale)),
            .w = @intFromFloat(@round(rect.w * self.scale)),
            .h = @intFromFloat(@round(rect.h * self.scale)),
        }) catch {};
        self.promoteDamage();
    }
    pub fn requestRebuild(self: *Ui) void {
        self.requestRebuildAt(.{ .module = "nano_gui", .file = "<requestRebuild>", .fn_name = "requestRebuild", .line = 0, .column = 0 });
    }

    /// 带调用点的重建请求；失效风暴日志使用该位置（REQ-FRAME-035）。
    pub fn requestRebuildAt(self: *Ui, src: std.builtin.SourceLocation) void {
        std.debug.assert(!self.in_paint); // REQ-FRAME-018：绘制函数不得请求重建
        self.rebuild_requested = true;
        self.rebuild_src_file = src.file;
        self.rebuild_src_line = src.line;
        // 构建内的重建请求由第二遍处理，不并入待处理失效；构建外照常置构建脏。
        if (!self.building) self.invalidate(.build);
    }

    /// 连续 8 帧 requestRebuild 的失效风暴检测（REQ-FRAME-035）。
    fn noteRebuildStreak(self: *Ui) void {
        if (!self.rebuild_requested) {
            self.rebuild_streak = 0;
            self.rebuild_storm_warned = false;
            return;
        }
        self.rebuild_streak +|= 1;
        if (self.rebuild_streak < 8 or self.rebuild_storm_warned) return;
        self.rebuild_storm_warned = true;
        core.log.write(.warn, "frame", "失效风暴：连续 8 帧 requestRebuild（{s}:{d}）", .{ self.rebuild_src_file, self.rebuild_src_line });
    }
    pub fn afterFrame(self: *Ui, closure: core.Closure) void {
        self.after_frame.append(self.gpa, closure) catch {};
    }

    // ---- 时间 ----
    pub fn now(self: *const Ui) u64 {
        return self.frame_now;
    }
    pub fn animate(self: *Ui, widget_id: core.WidgetId, slot: u8, target: f32, spec: AnimSpec) f32 {
        const key = AnimKey{ .id = widget_id.raw(), .slot = slot };
        const theme_ptr = self.theme_ptr;
        var dur = theme_ptr.durationMs(spec.duration);
        if (!platform.metrics(self.window).client_animation) dur = 0;
        if (self.anims.getPtr(key)) |a| {
            a.touched = self.build_counter;
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
            .widget_id = widget_id.raw(),
            .current = target,
            .start = target,
            .target = target,
            .start_ms = self.frame_now,
            .duration_ms = dur,
            .level = spec.level,
            .easing = spec.easing,
            .initialized = true,
            .touched = self.build_counter,
        }) catch {};
        return target;
    }

    pub fn animationCurrent(self: *const Ui, widget_id: core.WidgetId, slot: u8) ?f32 {
        const key = AnimKey{ .id = widget_id.raw(), .slot = slot };
        if (self.anims.get(key)) |a| return a.current;
        return null;
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

    /// 循环动画（REQ-FRAME-045）：返回 [0, 1) 相位；关闭动效时返回 0 且不登记活动动画。线程：界面线程。
    pub fn animateLoop(self: *Ui, widget_id: core.WidgetId, slot: u8, period: theme.Duration, level: Dirty) f32 {
        const key = AnimKey{ .id = widget_id.raw(), .slot = slot };
        if (self.disable_animations or !platform.metrics(self.window).client_animation) {
            _ = self.loop_anims.remove(key);
            return 0;
        }
        const period_ms = @max(@as(u64, 1), self.theme_ptr.durationMs(period));
        self.loop_anims.put(self.gpa, key, .{ .level = level, .touched = self.build_counter }) catch {};
        self.invalidateNode(widget_id, level);
        const phase_ms = self.frame_now % period_ms;
        return @as(f32, @floatFromInt(phase_ms)) / @as(f32, @floatFromInt(period_ms));
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

    /// 重新从当前帧时间戳计时（REQ-FRAME-050）。线程：界面线程。
    pub fn timerRestart(self: *Ui, widget_id: core.WidgetId) void {
        if (self.timers.getPtr(widget_id.raw())) |t| {
            t.next_ms = self.frame_now + t.interval_ms;
            t.due = false;
        }
        if (self.blinks.getPtr(widget_id.raw())) |b| {
            b.on = true;
            b.next_ms = self.frame_now + b.interval_ms;
        }
    }

    /// 光标闪烁：由文本控件在构建期登记，绘制期读取状态。
    pub fn setCaretBlink(self: *Ui, widget_id: core.WidgetId, interval_ms: ?u32, rect: core.RectI) void {
        if (interval_ms == null) {
            _ = self.blinks.remove(widget_id.raw());
            return;
        }
        const gop = self.blinks.getOrPut(self.gpa, widget_id.raw()) catch return;
        if (!gop.found_existing) {
            gop.value_ptr.* = .{ .next_ms = self.frame_now + interval_ms.?, .interval_ms = interval_ms.?, .rect = rect, .touched = self.build_counter };
        } else {
            gop.value_ptr.interval_ms = interval_ms.?;
            gop.value_ptr.rect = rect;
            gop.value_ptr.touched = self.build_counter;
        }
    }

    pub fn caretVisible(self: *const Ui, widget_id: core.WidgetId) bool {
        if (self.blinks.get(widget_id.raw())) |b| return b.on;
        return true;
    }

    pub fn hasDueBlink(self: *const Ui, now_ms: u64) bool {
        var it = self.blinks.valueIterator();
        while (it.next()) |b| if (now_ms >= b.next_ms) return true;
        return false;
    }

    pub fn blinkCount(self: *const Ui) usize {
        return self.blinks.count();
    }

    pub fn caretBlinkRect(self: *const Ui, widget_id: core.WidgetId) ?core.RectI {
        if (self.blinks.get(widget_id.raw())) |b| return b.rect;
        return null;
    }

    pub fn haveActiveAnimations(self: *const Ui) bool {
        var lit = self.loop_anims.valueIterator();
        while (lit.next()) |la| {
            if (la.touched + 2 > self.build_counter) return true;
        }
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
        const node = self.getNode(widget_id) orelse return .{};
        if (node.registered_interact) return node.interaction;
        node.interact_opts = opts;
        node.registered_interact = true;
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
        return out;
    }

    fn idOrNone(widget_id: core.WidgetId) core.WidgetId {
        return widget_id;
    }

    fn effectiveDisabled(self: *const Ui, widget_id: core.WidgetId) bool {
        if (self.getNode(widget_id) orelse self.getPrevNode(widget_id)) |n| {
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
        if (self.getNode(widget_id)) |n| {
            // REQ-INPUT-004：未经 interact 登记的节点读取收件列表属于控件缺陷。
            std.debug.assert(n.registered_interact);
        }
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

    /// 最近一次指针事件的屏幕坐标（ppx），供弹出根与主根比较（REQ-INPUT-002）。
    pub fn pointerScreen(self: *const Ui) ?core.Vec2i {
        return self.pointer_screen;
    }
    pub fn setFocus(self: *Ui, widget_id: core.WidgetId) void {
        self.focus_after_build = widget_id;
    }
    /// 在构建完成后按指定原因设置焦点（REQ-INPUT-044）。线程：界面线程。
    pub fn setFocusReason(self: *Ui, widget_id: core.WidgetId, reason: input.FocusReason) void {
        self.focus_after_build = widget_id;
        self.focus_visible = (reason == .tab or reason == .shortcut or reason == .mnemonic);
    }
    pub fn clearFocus(self: *Ui) void {
        self.clear_focus_requested = true;
    }
    pub fn autoFocus(self: *Ui, widget_id: core.WidgetId) void {
        self.focus_after_build = widget_id;
    }
    /// 查询焦点环是否应可见（REQ-INPUT-046）。线程：界面线程。
    pub fn isFocusVisible(self: *const Ui) bool {
        return self.focus_visible and self.window_active;
    }
    /// 声明逻辑焦点组（REQ-INPUT-047）。线程：界面线程。
    pub fn focusGroup(self: *Ui, widget_id: core.WidgetId, spec: input.GroupSpec) void {
        self.focus_groups.append(self.gpa, .{ .id = widget_id, .spec = spec }) catch {};
    }
    /// 声明焦点作用域（REQ-INPUT-048）。线程：界面线程。
    pub fn focusScope(self: *Ui, widget_id: core.WidgetId, spec: input.ScopeSpec) void {
        self.focus_scopes.append(self.gpa, .{ .id = widget_id, .spec = spec }) catch {};
    }
    /// 声明根焦点作用域（REQ-INPUT-048）。线程：界面线程。
    pub fn rootScope(self: *Ui, spec: input.ScopeSpec) void {
        self.root_scope_spec = spec;
    }
    /// 登记助记符（REQ-INPUT-056）。线程：界面线程。
    pub fn mnemonic(self: *Ui, widget_id: core.WidgetId, ch: u21, action: input.MnemonicAction) void {
        if (ch <= 0x20) return;
        self.mnemonics_list.append(self.gpa, .{ .id = widget_id, .ch = ch, .action = action }) catch {};
    }
    /// 悬停持续超过系统延迟（REQ-INPUT-050）。线程：界面线程。
    pub fn hoverFor(self: *Ui, widget_id: core.WidgetId, delay: input.HoverDelay) bool {
        if (self.hover_id != widget_id) return false;
        const sm = platform.metrics(self.window);
        const ms: u64 = switch (delay) {
            .menu => sm.menu_show_delay_ms,
            .tooltip => sm.hover_time_ms,
        };
        if (self.frame_now -| self.hover_enter_ms >= ms) return true;
        _ = self.timer(widget_id, @intCast(@max(1, ms - (self.frame_now -| self.hover_enter_ms))), .build);
        return false;
    }
    /// 离开悬停持续超过系统延迟（REQ-INPUT-051）。线程：界面线程。
    pub fn notHoverFor(self: *Ui, widget_id: core.WidgetId, delay: input.HoverDelay) bool {
        if (self.hover_id == widget_id) return false;
        if (self.hover_leave_id != widget_id) return true;
        const sm = platform.metrics(self.window);
        const ms: u64 = switch (delay) {
            .menu => sm.menu_show_delay_ms,
            .tooltip => sm.hover_time_ms,
        };
        if (self.frame_now -| self.hover_leave_ms >= ms) return true;
        _ = self.timer(widget_id, @intCast(@max(1, ms - (self.frame_now -| self.hover_leave_ms))), .build);
        return false;
    }
    /// 声明应用内拖放源（REQ-INPUT-060）。线程：界面线程。
    pub fn beginDrag(self: *Ui, source: core.WidgetId, payload: input.DragPayload) void {
        self.active_drag = .{
            .source = source,
            .payload = payload,
            .pos = self.pointer_pos,
            .over = self.drop_target_id,
        };
        self.capture_id = source;
        self.dragging = true;
    }
    /// 返回当前活动拖拽信息（REQ-INPUT-060）。线程：界面线程。
    pub fn dragInfo(self: *const Ui) ?input.DragInfo {
        return self.active_drag;
    }
    /// 声明拖放目标（REQ-INPUT-061）。线程：界面线程。
    pub fn dropTarget(self: *Ui, widget_id: core.WidgetId, accept: input.DropAccept) input.DropState {
        if (self.dropped_id == widget_id and self.dropped_payload != null) {
            const pay = self.dropped_payload.?;
            var ok = false;
            for (accept.kinds) |k| if (k == pay.kind) {
                ok = true;
                break;
            };
            if (ok) {
                return .{ .over = false, .acceptable = true, .pos = self.dropped_pos, .dropped = true, .payload = pay, .effect = .move };
            }
        }
        const drag = self.active_drag orelse return .{ .over = false, .acceptable = false, .pos = .{}, .dropped = false, .payload = null, .effect = .none };
        var ok = false;
        for (accept.kinds) |k| if (k == drag.payload.kind) {
            ok = true;
            break;
        };
        const over = self.pointerInNode(widget_id, self.pointer_pos);
        if (over and ok) self.drop_target_id = widget_id;
        return .{ .over = over, .acceptable = ok, .pos = self.pointer_pos, .dropped = false, .payload = if (over) drag.payload else null, .effect = if (over and ok) .move else .none };
    }
    /// 登记提示文本（框架复制；REQ-INPUT-052）。线程：界面线程。
    pub fn tooltip(self: *Ui, owner: core.WidgetId, tip_text: []const u8) void {
        if (!self.hoverFor(owner, .tooltip)) return;
        if (self.tooltip_text.len > 0) self.gpa.free(self.tooltip_text);
        self.tooltip_text = self.gpa.dupe(u8, tip_text) catch "";
        self.tooltip_owner = owner;
    }
    /// 仅当文本被截断时显示提示（REQ-INPUT-052）。线程：界面线程。
    pub fn tooltipIfTruncated(self: *Ui, owner: core.WidgetId, tip_text: []const u8, style: text.Style) void {
        const r = self.lastRect(owner) orelse return;
        if (!text.isTruncated(tip_text, style, self.scale, r.w)) return;
        self.tooltip(owner, tip_text);
    }
    /// 上报输入法插入符与排除区（REQ-INPUT-062）。线程：界面线程。
    pub fn imeCaret(self: *Ui, widget_id: core.WidgetId, caret: core.Rect, exclude: ?core.Rect) void {
        if (self.focus_id != widget_id) return;
        const w = self.window orelse return;
        const cpx = core.RectI{
            .x = @intFromFloat(@round(caret.x * self.scale)),
            .y = @intFromFloat(@round(caret.y * self.scale)),
            .w = @max(1, @as(i32, @intFromFloat(@round(caret.w * self.scale)))),
            .h = @max(1, @as(i32, @intFromFloat(@round(caret.h * self.scale)))),
        };
        const epx: ?core.RectI = if (exclude) |ex| .{
            .x = @intFromFloat(@round(ex.x * self.scale)),
            .y = @intFromFloat(@round(ex.y * self.scale)),
            .w = @max(1, @as(i32, @intFromFloat(@round(ex.w * self.scale)))),
            .h = @max(1, @as(i32, @intFromFloat(@round(ex.h * self.scale)))),
        } else null;
        w.setImeCaretRect(cpx, epx);
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
    /// 构建时声明命令状态（REQ-APP-024）；本次构建未声明的命令由应用给默认值。
    pub fn command(self: *Ui, cmd_id: input.CommandId, cmd_state: input.CommandState) input.CommandState {
        self.command_states.put(self.gpa, @backingInt(cmd_id), cmd_state) catch {};
        return cmd_state;
    }
    pub fn commandState(self: *const Ui, cmd_id: input.CommandId) input.CommandState {
        return self.command_states.get(@backingInt(cmd_id)) orelse .{};
    }
    /// 菜单/工具栏调用：排入队列，在第一构建遍结束后执行（REQ-APP-026）。
    pub fn invokeCommand(self: *Ui, cmd_id: input.CommandId) void {
        self.command_queue.append(self.gpa, cmd_id) catch return;
    }
    /// 标准编辑命令路由到焦点节点（REQ-APP-030）；能力不足时返回 false 并吞掉按键。
    pub fn editCommand(self: *Ui, cmd: input.EditCommand) bool {
        if (self.focus_id == .none) return false;
        const node = self.getNode(self.focus_id) orelse return false;
        const caps = node.interact_opts.edit;
        const enabled = switch (cmd) {
            .undo => caps.undo,
            .redo => caps.redo,
            .cut => caps.cut,
            .copy => caps.copy,
            .paste => caps.paste,
            .delete => caps.delete,
            .select_all => caps.select_all,
        };
        if (!enabled) return false;
        self.pushEvent(self.focus_id, .{ .edit_command = cmd });
        self.invalidate(.build);
        return true;
    }

    pub fn drainCommands(self: *Ui) usize {
        if (self.command_queue.items.len == 0) return 0;
        const n = self.command_queue.items.len;
        var i: usize = 0;
        while (i < self.command_queue.items.len) : (i += 1) {
            const cmd_id = self.command_queue.items[i];
            const cmd_state = self.commandState(cmd_id);
            if (!cmd_state.enabled) continue;
            if (self.command_invoke_fn) |f| f(self.command_ctx, cmd_id);
        }
        self.command_queue.clearRetainingCapacity();
        self.invalidate(.build);
        return n;
    }

    // ---- 帧 ----
    pub fn beginFrame(self: *Ui, now_ms: u64, window_active: bool) void {
        self.frame_now = now_ms;
        self.window_active = window_active;
        self.last_damage_area = 0;
        if (self.force_rebuild) self.dirty = .build;
        if (self.current_root == null) self.dirty = .build;
        self.frame.reset();
        self.frame_generation += 1;
        self.clearInbox();
        self.pending.clearRetainingCapacity();
        self.interaction_cache.clearRetainingCapacity();
        self.activation_seen = false;
        self.rebuild_requested = false;
        self.built_this_frame = false;
        self.frame_did_layout = false;
        self.last_frame_damage = .{};
        self.build_passes = 0;
        self.overlays.clearRetainingCapacity();
        var bit = self.blinks.iterator();
        while (bit.next()) |kv| {
            const b = kv.value_ptr;
            if (now_ms < b.next_ms) continue;
            b.on = !b.on;
            b.next_ms += b.interval_ms;
            if (b.next_ms <= now_ms) b.next_ms = now_ms + b.interval_ms;
            const r = core.RectI{ .x = b.rect.x - 1, .y = b.rect.y - 1, .w = b.rect.w + 2, .h = b.rect.h + 2 };
            self.invalidated_rects.append(self.gpa, r) catch {};
            self.damage = unionRects(self.damage, r);
            if (@backingInt(self.dirty) < @backingInt(Dirty.paint)) self.dirty = .paint;
        }
        self.updateAnimations(now_ms);
    }

    fn updateAnimations(self: *Ui, now_ms: u64) void {
        var it = self.anims.iterator();
        while (it.next()) |kv| {
            const a = kv.value_ptr;
            if (!a.initialized or a.duration_ms == 0) continue;
            if (a.current == a.target) continue;
            const elapsed = now_ms -| a.start_ms;
            const t = std.math.clamp(@as(f32, @floatFromInt(elapsed)) / @as(f32, @floatFromInt(a.duration_ms)), 0, 1);
            const e = if (a.easing == .out) easeOut(t) else t;
            const next = a.start + (a.target - a.start) * e;
            if (next != a.current) {
                a.current = next;
                const wid: core.WidgetId = @fromBackingInt(@intCast(a.widget_id));
                self.invalidateNode(wid, .paint);
            }
        }
    }

    pub fn dispatch(self: *Ui, event: platform.Event) void {
        if (self.prev_root == null) {
            if (event.data == .resized) self.invalidate(.layout);
            return;
        }
        switch (event.data) {
            .mouse_move => |m| self.onMouseMove(m.pos, m.mods, m.screen_pos),
            .mouse_button => |m| self.onMouseButton(m.button, m.down, m.pos, m.mods, m.screen_pos),
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
            .render_lost => {
                self.repaint_all = true;
                self.invalidate(.paint);
            },
            else => {},
        }
    }

    fn onMouseMove(self: *Ui, pos_px: core.Vec2i, mods: platform.Mods, screen_pos: ?core.Vec2i) void {
        self.pointer_pos = .{ .x = @as(f32, @floatFromInt(pos_px.x)) / self.scale, .y = @as(f32, @floatFromInt(pos_px.y)) / self.scale };
        if (screen_pos) |sp| self.pointer_screen = sp;
        self.pointer_known = true;
        if (self.capture_id != .none) {
            if (!self.dragging and self.pressed_id == self.capture_id) {
                if (self.getPrevNode(self.capture_id)) |cn| {
                    if (cn.interact_opts.sense.drag) {
                        const sm = platform.metrics(self.window);
                        const dx = @abs(self.pointer_pos.x - self.press_pos.x) * self.scale;
                        const dy = @abs(self.pointer_pos.y - self.press_pos.y) * self.scale;
                        if (dx >= @as(f32, @floatFromInt(@max(1, sm.drag_size.w))) or dy >= @as(f32, @floatFromInt(@max(1, sm.drag_size.h)))) {
                            self.dragging = true;
                            self.getPending(self.capture_id).drag_started = true;
                            self.pushEvent(self.capture_id, .{ .drag_start = .{ .pos = self.press_pos } });
                        }
                    }
                }
            }
            self.pushEvent(self.capture_id, .{ .pointer_move = .{ .pos = self.pointer_pos, .mods = mods } });
            if (self.dragging) {
                self.pushEvent(self.capture_id, .{ .drag_move = .{ .pos = self.pointer_pos, .delta = self.pointer_pos.sub(self.press_pos) } });
                if (self.active_drag) |*d| {
                    d.pos = self.pointer_pos;
                    d.over = self.drop_target_id;
                }
            }
            self.invalidate(.paint);
            return;
        }
        const hit = self.hitTest(pos_px);
        self.setHover(hit);
    }

    fn onMouseButton(self: *Ui, button: platform.MouseButton, down: bool, pos_px: core.Vec2i, mods: platform.Mods, screen_pos: ?core.Vec2i) void {
        self.pointer_pos = .{ .x = @as(f32, @floatFromInt(pos_px.x)) / self.scale, .y = @as(f32, @floatFromInt(pos_px.y)) / self.scale };
        if (screen_pos) |sp| self.pointer_screen = sp;
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
            if (self.dragging) {
                self.getPending(target).drag_ended = true;
                self.pushEvent(target, .{ .drag_end = .{ .cancelled = false } });
                if (self.active_drag) |d| {
                    if (self.drop_target_id != .none) {
                        self.dropped_id = self.drop_target_id;
                        self.dropped_payload = d.payload;
                        self.dropped_pos = self.pointer_pos;
                    }
                }
            }
            self.active_drag = null;
            self.drop_target_id = .none;
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
                const page = switch (platform.metrics(self.window).wheel_lines) {
                    .page => true,
                    .lines => false,
                };
                self.pushEvent(c.id, .{ .wheel = .{ .delta = delta, .page = page, .mods = mods, .pos = self.pointer_pos } });
                const p = self.getPending(c.id);
                p.wheel = p.wheel.add(delta);
                self.invalidate(.build);
                return;
            }
            cur = c.parent;
        }
    }

    fn onKey(self: *Ui, vk: platform.VirtualKey, down: bool, repeat: bool, mods: platform.Mods) void {
        if (vk == .f12) {
            self.inspect_active = down;
            return;
        }
        // ① 弹出栈最上层（轻关闭/Esc/独占键盘模式）。
        if (down and vk == .escape and self.open_menu != .none) {
            self.open_menu = .none;
            self.invalidate(.build);
            return;
        }
        if (down) {
            self.focus_visible = true;
            self.keyboard_cues = true;
        }
        // ② 活跃文本输入控件在输入法组字期间拦截方向/Esc/回车。
        if (self.ime_active and self.focus_id != .none) {
            self.pushEvent(self.focus_id, if (down) .{ .key_down = .{ .key = vk, .mods = mods, .repeat = repeat } } else .{ .key_up = .{ .key = vk, .mods = mods } });
            self.invalidate(.build);
            return;
        }
        // ③ 焦点节点 preempt 预占。
        if (down and self.focus_id != .none) {
            if (self.getPrevNode(self.focus_id)) |fn_node| {
                if (fn_node.interact_opts.preempt.matches(vk, mods)) {
                    self.pushEvent(self.focus_id, .{ .key_down = .{ .key = vk, .mods = mods, .repeat = repeat } });
                    self.invalidate(.build);
                    return;
                }
            }
        }
        // ④ 快捷键：非自动重复、非 AltGr 的 key_down。
        if (down and !repeat and !mods.altgr) {
            if (self.shortcut_source) |src| {
                if (src.lookup(src.ctx, .{ .key = vk, .mods = mods })) |hit| {
                    const declared = self.command_states.get(@backingInt(hit.command));
                    const enabled = hit.enabled and (declared == null or declared.?.enabled);
                    if (enabled) src.invoke(src.ctx, hit.command);
                    self.invalidate(.build);
                    return;
                }
            }
        }
        if (self.focus_id == .none) {
            if (down and vk == .tab) self.moveFocus(mods.shift);
            return;
        }
        if (down and vk == .escape and self.capture_id != .none) {
            self.getPending(self.capture_id).drag_cancelled = true;
            self.active_drag = null;
            self.drop_target_id = .none;
            self.releaseCapture();
            return;
        }
        // ⑤ 焦点节点 handles 与观察者向上冒泡。
        var cur: ?*Node = self.getPrevNode(self.focus_id);
        while (cur) |c| {
            if (c.interact_opts.observes.matches(vk, mods)) {
                self.pushEvent(c.id, if (down) .{ .key_down = .{ .key = vk, .mods = mods, .repeat = repeat } } else .{ .key_up = .{ .key = vk, .mods = mods } });
            }
            if (c.interact_opts.handles.matches(vk, mods)) {
                self.pushEvent(c.id, if (down) .{ .key_down = .{ .key = vk, .mods = mods, .repeat = repeat } } else .{ .key_up = .{ .key = vk, .mods = mods } });
                self.invalidate(.build);
                return;
            }
            cur = c.parent;
        }
        // ⑥ 焦点组方向键导航（REQ-INPUT-047）。
        if (down and (vk == .left or vk == .right or vk == .up or vk == .down or vk == .home or vk == .end)) {
            for (self.focus_groups.items) |fg| {
                if (self.isDescendant(self.focus_id, fg.id)) {
                    const match_axis = switch (fg.spec.orientation) {
                        .horizontal => vk == .left or vk == .right or (fg.spec.home_end and (vk == .home or vk == .end)),
                        .vertical => vk == .up or vk == .down or (fg.spec.home_end and (vk == .home or vk == .end)),
                        .both => true,
                    };
                    if (match_axis and self.moveFocusInGroup(fg.id, vk, fg.spec)) return;
                }
            }
        }
        // ⑦ Tab 切换、作用域默认/取消按钮、Alt 助记符（REQ-INPUT-048/056）。
        if (down and vk == .tab and !repeat) {
            self.moveFocus(mods.shift);
            return;
        }
        if (down and !repeat and (vk == .enter or vk == .escape)) {
            const target = self.resolveScopeButton(vk == .enter);
            if (target != .none) {
                self.getPending(target).activated = if (vk == .enter) .default_button else .cancel_button;
                self.pushEvent(target, .{ .activate = if (vk == .enter) .default_button else .cancel_button });
                self.invalidate(.build);
                return;
            }
        }
        if (down and !repeat and mods.alt and !mods.ctrl) {
            if (input.keyToChar(vk, .{})) |ch| {
                const lower_ch = if (ch >= 'A' and ch <= 'Z') ch + 32 else ch;
                for (self.mnemonics_list.items) |m| {
                    const m_ch = if (m.ch >= 'A' and m.ch <= 'Z') m.ch + 32 else m.ch;
                    if (m_ch == lower_ch) {
                        switch (m.action) {
                            .activate => {
                                self.getPending(m.id).activated = .mnemonic;
                                self.pushEvent(m.id, .{ .activate = .mnemonic });
                            },
                            .focus => self.setFocusNow(m.id, .mnemonic),
                            .focus_next, .focus_within => self.setFocusNow(m.id, .mnemonic),
                        }
                        self.invalidate(.build);
                        return;
                    }
                }
            }
        }
        // ⑧ 兜底投递给焦点节点。
        self.pushEvent(self.focus_id, if (down) .{ .key_down = .{ .key = vk, .mods = mods, .repeat = repeat } } else .{ .key_up = .{ .key = vk, .mods = mods } });
        self.invalidate(.build);
    }

    fn isDescendant(self: *const Ui, child_id: core.WidgetId, ancestor_id: core.WidgetId) bool {
        var cur = self.getPrevNode(child_id);
        while (cur) |c| {
            if (c.id == ancestor_id) return true;
            cur = c.parent;
        }
        return false;
    }

    fn moveFocusInGroup(self: *Ui, group_id: core.WidgetId, vk: platform.VirtualKey, spec: input.GroupSpec) bool {
        const root = self.getPrevNode(group_id) orelse return false;
        var list = std.ArrayListUnmanaged(*Node).empty;
        defer list.deinit(self.gpa);
        collectGroupStops(root, &list, self.gpa);
        if (list.items.len == 0) return false;
        var idx: usize = 0;
        var found = false;
        for (list.items, 0..) |n, i| {
            if (n.id == self.focus_id) {
                idx = i;
                found = true;
                break;
            }
        }
        const next: usize = switch (vk) {
            .home => 0,
            .end => list.items.len - 1,
            .left, .up => if (!found) 0 else if (idx > 0) idx - 1 else if (spec.wrap) list.items.len - 1 else return true,
            .right, .down => if (!found) 0 else if (idx + 1 < list.items.len) idx + 1 else if (spec.wrap) 0 else return true,
            else => return false,
        };
        self.setFocusNow(list.items[next].id, .group);
        self.focus_visible = true;
        return true;
    }

    fn collectGroupStops(node: ?*Node, out: *std.ArrayListUnmanaged(*Node), gpa: std.mem.Allocator) void {
        const n = node orelse return;
        if (n.flags.hidden) return;
        if (n.flags.focusable and !n.flags.disabled) out.append(gpa, n) catch {};
        var c = n.first_child;
        while (c) |cc| : (c = cc.next) collectGroupStops(cc, out, gpa);
    }

    fn resolveScopeButton(self: *const Ui, is_default: bool) core.WidgetId {
        var i = self.focus_scopes.items.len;
        while (i > 0) {
            i -= 1;
            const sc = self.focus_scopes.items[i];
            if (self.focus_id != .none and self.isDescendant(self.focus_id, sc.id)) {
                const btn = if (is_default) sc.spec.default_button else sc.spec.cancel_button;
                if (btn != .none) return btn;
            }
        }
        return if (is_default) self.root_scope_spec.default_button else self.root_scope_spec.cancel_button;
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
        // Anchor 是出流容器，自身不参与命中；其子项仍可命中。
        if (n.layout.kind != .anchor) {
            const o = n.interact_opts.sense;
            if (o.hover or o.click or o.drag or o.wheel or o.context) out.append(gpa, n) catch {};
        }
        var c = n.first_child;
        while (c) |cc| : (c = cc.next) collectNormalHits(cc, false, out, gpa);
    }

    fn collectOverlayHits(node: ?*Node, in_overlay: bool, out: *std.ArrayListUnmanaged(*Node), gpa: std.mem.Allocator) void {
        const n = node orelse return;
        if (n.flags.hidden) return;
        const inside = in_overlay or n.flags.overlay;
        if (inside and n.layout.kind != .anchor) {
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
        if (old != .none) {
            self.hover_leave_id = old;
            self.hover_leave_ms = self.frame_now;
            self.startHoverAnim(old, false);
            self.invalidateNode(old, .paint);
        }
        if (next != .none) {
            self.hover_enter_ms = self.frame_now;
            self.startHoverAnim(next, true);
            self.invalidateNode(next, .paint);
        }
    }

    /// 悬停动画在分发阶段启动，使纯绘制帧即可推进（REQ-FRAME-046）。
    fn startHoverAnim(self: *Ui, wid: core.WidgetId, on: bool) void {
        const node = self.getNode(wid) orelse self.getPrevNode(wid) orelse return;
        if (!node.interact_opts.hover_anim) return;
        var dur: u16 = self.theme_ptr.durationMs(.fast);
        if (!platform.metrics(self.window).client_animation) dur = 0;
        const key = AnimKey{ .id = wid.raw(), .slot = 0 };
        const target: f32 = if (on) 1 else 0;
        if (self.anims.getPtr(key)) |a| {
            if (a.target == target and a.initialized) return;
            a.start = a.current;
            a.target = target;
            a.start_ms = self.frame_now;
            a.duration_ms = dur;
            a.level = .paint;
            a.easing = .out;
            a.touched = self.build_counter;
            if (dur == 0) a.current = target;
        } else {
            self.anims.put(self.gpa, key, .{
                .widget_id = wid.raw(),
                .current = if (dur == 0) target else 0,
                .start = 0,
                .target = target,
                .start_ms = self.frame_now,
                .duration_ms = dur,
                .level = .paint,
                .easing = .out,
                .initialized = true,
                .touched = self.build_counter,
            }) catch {};
        }
        self.invalidate(.paint);
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
        std.mem.swap(@TypeOf(self.diff_map), &self.diff_map, &self.node_map);
        self.popup_rect = null;
        self.building = true;
        platform.setInBuild(true);
        self.pending_dirty = .none;
        var pass: u8 = 1;
        while (pass <= 2) : (pass += 1) {
            self.pass = pass;
            self.build_counter += 1;
            self.node_map.clearRetainingCapacity();
            self.pending_seen.clearRetainingCapacity();
            self.seen_id_src.clearRetainingCapacity();
            self.roots.clearRetainingCapacity();
            self.id_stack.clearRetainingCapacity();
            self.parent_stack.clearRetainingCapacity();
            self.container_stack.clearRetainingCapacity();
            self.interaction_cache.clearRetainingCapacity();
            self.focus_groups.clearRetainingCapacity();
            self.focus_scopes.clearRetainingCapacity();
            self.mnemonics_list.clearRetainingCapacity();
            self.root_scope_spec = .{};
            self.tooltip_owner = .none;
            // 第一遍写入选定竞技场；第二遍复用同一竞技场。
            if (pass == 1) {
                self.command_states.clearRetainingCapacity();
                self.tree_is_a = !self.tree_is_a;
                const arena = if (self.tree_is_a) &self.tree_a else &self.tree_b;
                const narena = if (self.tree_is_a) &self.nodes_a else &self.nodes_b;
                arena.reset();
                narena.reset();
            } else {
                const arena = if (self.tree_is_a) &self.tree_a else &self.tree_b;
                const narena = if (self.tree_is_a) &self.nodes_a else &self.nodes_b;
                arena.reset();
                narena.reset();
                // 第二遍：丢弃第一遍节点，但旧树仍为上一帧的树。
            }
            const root_alloc = self.nodeAlloc();
            const root = root_alloc.create(Node) catch @panic("nano_gui: tree arena exhausted");
            root.* = .{ .id = .none, .layout = .{ .kind = .stack, .main = .{ .grow = 1 }, .cross = .fill }, .flags = .{ .clip_children = true }, .paint = paintRoot, .root_index = 0 };
            self.roots.append(self.gpa, root) catch {};
            self.current_root = root;
            self.parent_stack.append(self.gpa, root) catch {};
            text.beginBuild();
            core.stats.timerBegin("time.build");
            buildFn(ctx, self);
            core.stats.timerEnd("time.build");
            if (self.drainCommands() > 0) self.rebuild_requested = true;
            text.trimCache();
            if (self.parent_stack.items.len != 1) {
                var buf: [256]u8 = undefined;
                const src: std.builtin.SourceLocation = if (self.container_stack.items.len > 0)
                    self.container_stack.items[self.container_stack.items.len - 1]
                else
                    .{ .module = "nano_gui", .file = "<unknown>", .fn_name = "<unknown>", .line = 0, .column = 0 };
                const msg = formatUnbalanced(&buf, src);
                const hard = builtin.optimize == .debug and !test_force_soft_unbalanced;
                if (hard) std.debug.panic("{s}", .{msg});
                core.log.write(.err, "frame", "{s}", .{msg});
                while (self.parent_stack.items.len > 1) _ = self.parent_stack.pop();
            }
            _ = self.parent_stack.pop();
            self.id_stack.clearRetainingCapacity();
            self.container_stack.clearRetainingCapacity();
            self.build_passes += 1;
            core.stats.counter("frame.build_passes").* += 1;
            const needs_second = self.activation_seen or self.rebuild_requested;
            if (!needs_second) break;
            if (pass == 2) {
                // REQ-FRAME-032：两遍之后条件仍在，以当前结果完成本帧并请求下一帧。
                if (self.rebuild_requested) self.pending_dirty = .build;
                break;
            }
            self.activation_seen = false;
            self.rebuild_requested = false;
        }
        self.pass = 0;
        self.noteRebuildStreak();
        self.built_this_frame = true;
        self.diff_root = old_root;
        self.prev_root = self.current_root;
        if (self.prev_root) |root| {
            _ = self.computeLayoutHash(root);
        }
        // 回收本次构建未触达的 transient 槽（REQ-FRAME-010）。
        const fa = self.frameAlloc();
        var remove = std.ArrayListUnmanaged(StateKey).empty;
        var sit = self.states.iterator();
        while (sit.next()) |kv| {
            const slot = kv.value_ptr.*;
            if (slot.level == .transient and slot.touched != self.build_counter) remove.append(fa, kv.key_ptr.*) catch {};
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
        // 节点停止声明时丢弃其动画记忆（REQ-FRAME-045）。
        var adel = std.ArrayListUnmanaged(AnimKey).empty;
        var ait = self.anims.iterator();
        while (ait.next()) |kv| {
            if (kv.value_ptr.touched != self.build_counter) adel.append(fa, kv.key_ptr.*) catch {};
        }
        for (adel.items) |k| _ = self.anims.remove(k);
        platform.setInBuild(false);
        self.building = false;
        // 合并构建期间的失效：取 max(待处理, .layout)（REQ-FRAME-023/032）。
        self.dirty = if (@backingInt(self.pending_dirty) > @backingInt(Dirty.layout)) self.pending_dirty else .layout;
        if (@backingInt(self.pending_dirty) > @backingInt(Dirty.layout)) self.carry_dirty = self.pending_dirty;
        self.pending_dirty = .none;
        self.applyPostBuildFocus();
    }

    fn applyPostBuildFocus(self: *Ui) void {
        if (self.clear_focus_requested) {
            self.focus_id = .none;
            self.clear_focus_requested = false;
        } else if (self.focus_after_build) |fid| {
            if (self.getPrevNode(fid)) |fn_n| {
                if (fn_n.flags.focusable and !fn_n.flags.disabled) {
                    self.focus_id = fid;
                }
            }
            self.focus_after_build = null;
        }
        if (self.focus_id != .none) {
            const n = self.getPrevNode(self.focus_id);
            if (n == null or !n.?.flags.focusable or n.?.flags.disabled or n.?.flags.hidden) {
                self.focus_id = .none;
                var list = std.ArrayListUnmanaged(*Node).empty;
                if (self.current_root) |r| tabStops(r, &list, self.frameAlloc());
                if (list.items.len > 0) self.focus_id = list.items[0].id;
            }
        } else if (!self.initial_focus_done) {
            // 初始焦点只在根首次构建完成后设置一次（REQ-INPUT-043），之后 clearFocus 保持为空。
            var list = std.ArrayListUnmanaged(*Node).empty;
            if (self.current_root) |r| tabStops(r, &list, self.frameAlloc());
            if (list.items.len > 0) self.focus_id = list.items[0].id;
        }
        self.initial_focus_done = true;
    }

    fn collectMap(node: ?*Node, map: *std.AutoHashMapUnmanaged(u64, *Node), gpa: std.mem.Allocator) void {
        const n = node orelse return;
        map.put(gpa, n.id.raw(), n) catch {};
        var c = n.first_child;
        while (c) |cc| : (c = cc.next) collectMap(cc, map, gpa);
    }

    /// 构建幂等校验报告（REQ-FRAME-024/025）。
    pub const IdempotenceReport = struct {
        differences: usize = 0,
        first_id: WidgetId = .none,
        first_name: ?[]const u8 = null,
        first_file: []const u8 = "",
        first_line: u32 = 0,
    };

    /// 在无事件、模型不变的前提下连续构建两次并比较节点树。
    pub fn checkIdempotence(self: *Ui, ctx: anytype, buildFn: *const fn (@TypeOf(ctx), *Ui) void) IdempotenceReport {
        self.invalidate(.build);
        self.build(ctx, buildFn);
        var first: std.ArrayListUnmanaged(NodeSnap) = .empty;
        defer first.deinit(self.gpa);
        snapshotTree(self.current_root, 0, &first, self.gpa);
        self.invalidate(.build);
        self.build(ctx, buildFn);
        var second: std.ArrayListUnmanaged(NodeSnap) = .empty;
        defer second.deinit(self.gpa);
        snapshotTree(self.current_root, 0, &second, self.gpa);
        var report = IdempotenceReport{};
        compareSnapshots(first.items, second.items, &report);
        return report;
    }

    /// 布局反馈检查：节点最终尺寸是否不同于构建期 lastRect 所见（REQ-FRAME-031）。
    pub fn needsLayoutFeedbackRebuild(self: *const Ui) bool {
        const root = self.current_root orelse return false;
        if (!root.has_feedback) return false;
        return feedbackDiffers(root);
    }

    /// 由布局反馈触发的一次额外构建遍；随后调用方须再次 layoutTree。
    pub fn rebuildForLayoutFeedback(self: *Ui, ctx: anytype, buildFn: *const fn (@TypeOf(ctx), *Ui) void) void {
        self.dirty = .build;
        self.build(ctx, buildFn);
    }

    /// 测量与排布，不计算损伤；布局反馈检查可在其后、损伤计算之前进行。
    pub fn arrangeTree(self: *Ui) void {
        const root = self.current_root orelse return;
        core.stats.timerBegin("time.layout");
        defer core.stats.timerEnd("time.layout");
        self.frame_did_layout = true;
        const client = core.RectI{ .x = 0, .y = 0, .w = self.viewport.w, .h = self.viewport.h };
        self.measured_nodes = 0;
        self.arranged_nodes = 0;
        self.measure_reused = 0;
        self.hfw_calls = 0;
        self.scroll_remeasures = 0;
        const lim = layout.Limit{ .w = client.w, .h = client.h, .definite_w = true, .definite_h = true };
        _ = self.measureNode(root, lim, .natural);
        self.arrangeNode(root, client, null);
        self.node_count = root.subtree_count;
        const minm = self.measureNode(root, .{ .w = layout.unbounded, .h = layout.unbounded }, .min);
        self.min_window = .{
            .x = @as(f32, @floatFromInt(minm.w)) / self.scale,
            .y = @as(f32, @floatFromInt(minm.h)) / self.scale,
        };
        core.stats.gauge("layout.measured_nodes").* = self.measured_nodes;
        core.stats.gauge("layout.arranged_nodes").* = self.arranged_nodes;
        core.stats.gauge("layout.hfw_calls").* = self.hfw_calls;
        core.stats.gauge("layout.scroll_remeasures").* = self.scroll_remeasures;
    }

    pub fn computeLayoutDamage(self: *Ui) void {
        self.computeDamage();
    }

    pub fn layoutTree(self: *Ui) void {
        if (self.dirty != .build and self.dirty != .layout) return;
        self.arrangeTree();
        self.computeLayoutDamage();
    }

    fn measurementCacheHitOn(measured_sz: layout.SizeI, valid: bool, mode_cached: layout.MeasureMode, c: layout.Limit, limit: layout.Limit, mode: layout.MeasureMode) bool {
        if (!valid or mode_cached != mode) return false;
        if (limitEqual(c, limit)) return true;
        // 确定限制必须逐分量相等（REQ-LAYOUT-021）。
        if (c.definite_w or c.definite_h or limit.definite_w or limit.definite_h) return false;
        // 两次均非确定：缓存限制更大且缓存结果能放入请求限制时必然相同。
        if (c.w < limit.w or c.h < limit.h) return false;
        if (measured_sz.w > limit.w or measured_sz.h > limit.h) return false;
        return true;
    }

    fn measurementCacheHit(node: *const Node, limit: layout.Limit, mode: layout.MeasureMode) ?layout.SizeI {
        if (measurementCacheHitOn(node.measured, node.measured_valid, node.measured_mode, node.measured_limit, limit, mode)) return node.measured;
        if (measurementCacheHitOn(node.measured2, node.measured2_valid, node.measured2_mode, node.measured2_limit, limit, mode)) return node.measured2;
        return null;
    }

    /// 仅供测试：以任意限制/模式进入测量入口（REQ-LAYOUT-021 的缓存验证）。
    pub fn measureForTest(self: *Ui, node: *Node, limit: layout.Limit, mode: layout.MeasureMode) layout.SizeI {
        if (comptime @import("builtin").is_test) return self.measureNode(node, limit, mode);
        return .{};
    }

    fn countSubtreeNodes(node: *const Node) u32 {
        var n: u32 = 1;
        var c = node.first_child;
        while (c) |cc| : (c = cc.next) n += countSubtreeNodes(cc);
        return n;
    }

    fn computeLayoutHash(self: *const Ui, node: *Node) u64 {
        const p = &node.layout;
        var h = core.hashU64(0x517cc1b727220a95, @as(u32, @bitCast(self.scale)));
        h = core.hashU64(h, @backingInt(p.kind));
        switch (p.kind) {
            .scroll => |s| {
                h = core.hashU64(h, @backingInt(s.axes));
                h = core.hashU64(h, @backingInt(s.bar_v));
                h = core.hashU64(h, @backingInt(s.bar_h));
                h = core.hashU64(h, @intFromBool(s.anchor_end));
                if (s.virtual_extent_px) |ve| {
                    h = core.hashU64(h, @bitCast(ve[0]));
                    h = core.hashU64(h, @bitCast(ve[1]));
                }
            },
            .splitter => |sp| {
                h = core.hashU64(h, @backingInt(sp.orientation));
                h = core.hashU64(h, @as(u32, @bitCast(sp.min_first)));
                h = core.hashU64(h, @as(u32, @bitCast(sp.min_second)));
            },
            .table => |tb| {
                h = core.hashU64(h, tb.header_rows);
                h = core.hashU64(h, @backingInt(tb.col_gap));
                h = core.hashU64(h, tb.columns.len);
                for (tb.columns) |col| {
                    h = core.hashU64(h, @backingInt(col.width));
                    switch (col.width) {
                        .fixed => |v| h = core.hashU64(h, @as(u32, @bitCast(v))),
                        .grow => |w| h = core.hashU64(h, @as(u32, @bitCast(w))),
                        .auto_header => {},
                    }
                    h = core.hashU64(h, @as(u32, @bitCast(col.min)));
                    h = core.hashU64(h, @as(u32, @bitCast(col.max)));
                }
            },
            .form => |fm| {
                h = core.hashU64(h, @as(u32, @bitCast(fm.label_max)));
                h = core.hashU64(h, @backingInt(fm.col_gap));
            },
            .anchor => |an| {
                h = core.hashU64(h, @backingInt(an.placement.side));
                h = core.hashU64(h, @backingInt(an.placement.align_));
                h = core.hashU64(h, @intFromBool(an.placement.flip_cross));
                h = core.hashU64(h, @backingInt(an.gap));
                h = core.hashU64(h, @backingInt(an.bounds));
            },
            .custom => |cl| h = core.hashU64(h, cl.key),
            else => {},
        }
        h = core.hashU64(h, @backingInt(p.main));
        switch (p.main) {
            .fixed => |v| h = core.hashU64(h, @as(u32, @bitCast(v))),
            .grow => |w| h = core.hashU64(h, @as(u32, @bitCast(w))),
            else => {},
        }
        h = core.hashU64(h, @backingInt(p.cross));
        if (p.cross == .fixed) h = core.hashU64(h, @as(u32, @bitCast(p.cross.fixed)));
        h = core.hashU64(h, @as(u32, @bitCast(p.main_min)));
        h = core.hashU64(h, @as(u32, @bitCast(p.main_max)));
        h = core.hashU64(h, @as(u32, @bitCast(p.cross_min)));
        h = core.hashU64(h, @as(u32, @bitCast(p.cross_max)));
        h = core.hashU64(h, @as(u32, @bitCast(p.padding.l)));
        h = core.hashU64(h, @as(u32, @bitCast(p.padding.t)));
        h = core.hashU64(h, @as(u32, @bitCast(p.padding.r)));
        h = core.hashU64(h, @as(u32, @bitCast(p.padding.b)));
        h = core.hashU64(h, p.border);
        h = core.hashU64(h, @backingInt(p.gap));
        h = core.hashU64(h, @backingInt(p.justify));
        h = core.hashU64(h, @backingInt(p.cross_align));
        h = core.hashU64(h, if (p.self_align) |sa| @as(u64, @backingInt(sa)) + 1 else 0);
        h = core.hashU64(h, if (p.self_main_align) |sma| @as(u64, @backingInt(sma)) + 1 else 0);
        h = core.hashU64(h, @intFromBool(p.form_span));
        h = core.hashU64(h, @intFromBool(node.flags.hidden));
        h = core.hashU64(h, p.content.key);
        if (p.content.hfw) |cb| h = core.hashU64(h, @intFromPtr(cb));
        h = core.hashU64(h, @as(u32, @bitCast(p.content.size.x)));
        h = core.hashU64(h, @as(u32, @bitCast(p.content.size.y)));
        var fb = node.flags.layout_feedback;
        var has_anch = false;
        var hh = (p.content.hfw != null and p.content.key == 0);
        var sub_cnt: u32 = 1;
        var cnt: u64 = 0;
        var c = node.first_child;
        while (c) |cc| : (c = cc.next) {
            if (cc.layout.kind == .anchor) {
                has_anch = true;
                continue;
            }
            cnt += 1;
            const ch = self.computeLayoutHash(cc);
            sub_cnt += cc.subtree_count;
            if (cc.has_feedback) fb = true;
            if (cc.has_hfw) hh = true;
            h = core.hashU64(h, cc.id.raw());
            h = core.hashU64(h, ch);
        }
        h = core.hashU64(h, cnt);
        node.layout_hash = h;
        node.has_feedback = fb;
        node.has_anchor_child = has_anch;
        node.has_hfw = hh;
        node.subtree_count = sub_cnt;
        return h;
    }

    fn measureNode(self: *Ui, node: *Node, limit: layout.Limit, mode: layout.MeasureMode) layout.SizeI {
        if (mode == .min and limit.w == layout.unbounded and limit.h == layout.unbounded and node.min_measured_valid) {
            return node.min_measured;
        }
        if (measurementCacheHit(node, limit, mode)) |hit| return hit;
        if (node.id != .none and !node.has_hfw) {
            if (self.diff_map.get(node.id.raw())) |old_n| {
                if (old_n.layout_hash == node.layout_hash) {
                    if (mode == .min and limit.w == layout.unbounded and limit.h == layout.unbounded and old_n.min_measured_valid) {
                        node.min_measured = old_n.min_measured;
                        node.min_measured_valid = true;
                        return node.min_measured;
                    }
                    if (measurementCacheHit(old_n, limit, mode)) |hit| {
                        node.measured = old_n.measured;
                        node.measured_valid = old_n.measured_valid;
                        node.measured_limit = old_n.measured_limit;
                        node.measured_mode = old_n.measured_mode;
                        node.measured2 = old_n.measured2;
                        node.measured2_valid = old_n.measured2_valid;
                        node.measured2_limit = old_n.measured2_limit;
                        node.measured2_mode = old_n.measured2_mode;
                        node.reused_measure = true;
                        node.reused_from = old_n;
                        node.min_measured = old_n.min_measured;
                        node.min_measured_valid = old_n.min_measured_valid;
                        if (mode == .natural) self.measure_reused += node.subtree_count;
                        return hit;
                    }
                }
            }
        }
        self.measured_nodes += 1;
        var size: layout.SizeI = .{};
        const p = &node.layout;
        const bi = @as(i32, p.border) * self.theme_ptr.hairline(self.scale);
        const pad_w = px(p.padding.l, self.scale) + px(p.padding.r, self.scale) + bi * 2;
        const pad_h = px(p.padding.t, self.scale) + px(p.padding.b, self.scale) + bi * 2;
        switch (p.kind) {
            .leaf => {
                const cw = pxF(p.content.size.x, self.scale, true);
                var ch = pxF(p.content.size.y, self.scale, true);
                var width = cw;
                if (p.content.hfw) |cb| {
                    const max_w = if (limit.w == layout.unbounded) cw else @max(0, limit.w - pad_w);
                    width = @min(cw, max_w);
                    const h_lpx = cb(p.content.hfw_ctx, @as(f32, @floatFromInt(width)) / self.scale);
                    ch = pxF(h_lpx, self.scale, true);
                    self.hfw_calls += 1;
                }
                size = .{ .w = width + pad_w, .h = ch + pad_h };
            },
            .row, .column, .table_row => {
                const vertical = p.kind == .column;
                const main_limit = if (vertical) limit.h else limit.w;
                const main_definite = if (vertical) limit.definite_h else limit.definite_w;
                const pad_main = if (vertical) pad_h else pad_w;
                const fa = self.frameAlloc();
                var stack_items: [32]layout.FlexItem = undefined;
                var stack_children: [32]*Node = undefined;
                var stack_sizes: [32]i32 = undefined;
                var dyn_items = std.ArrayListUnmanaged(layout.FlexItem).empty;
                var dyn_children = std.ArrayListUnmanaged(*Node).empty;
                var count: usize = 0;
                var c = node.first_child;
                while (c) |child| : (c = child.next) {
                    if (child.layout.kind == .anchor) continue;
                    const cross_definite = if (vertical) limit.definite_w else limit.definite_h;
                    const skip_nat = mode == .natural and main_definite and child.layout.main == .grow and
                        (child.layout.cross == .fill or child.layout.cross == .fixed) and
                        (cross_definite or child.layout.cross == .fixed);
                    var nat_main: i32 = 0;
                    if (!skip_nat) {
                        const child_lim = layout.Limit{
                            .w = if (vertical) limit.w else layout.unbounded,
                            .h = if (vertical) layout.unbounded else limit.h,
                            // 主轴限制恒为无界，因此主轴上的 definite 标志必须为 false。
                            .definite_w = if (vertical) limit.definite_w else false,
                            .definite_h = if (vertical) false else limit.definite_h,
                        };
                        const nat = self.measureNode(child, child_lim, mode);
                        nat_main = if (vertical) nat.h else nat.w;
                    }
                    var kind: layout.FlexKind = .fit;
                    var base = nat_main;
                    var wq: u32 = 0;
                    switch (child.layout.main) {
                        .fixed => kind = .fixed,
                        .fit => kind = .fit,
                        .fit_shrink => {
                            if (child.layout.kind == .leaf) {
                                kind = .shrink;
                                if (mode == .min) base = px(child.layout.main_min, self.scale);
                            } else kind = .fit;
                        },
                        .grow => |w| {
                            kind = .grow;
                            // 非确定限制下 grow 取 main_min（REQ-LAYOUT-020 第 3 步）。
                            base = px(child.layout.main_min, self.scale);
                            wq = layout.quantizeWeight(w);
                        },
                    }
                    const item = layout.FlexItem{
                        .kind = kind,
                        .base = base,
                        .min = px(child.layout.main_min, self.scale),
                        .max = if (child.layout.main_max == std.math.inf(f32)) layout.unbounded else px(child.layout.main_max, self.scale),
                        .wq = wq,
                    };
                    if (count < 32 and dyn_items.items.len == 0) {
                        stack_items[count] = item;
                        stack_children[count] = child;
                    } else {
                        if (dyn_items.items.len == 0) {
                            dyn_items.appendSlice(fa, stack_items[0..count]) catch {};
                            dyn_children.appendSlice(fa, stack_children[0..count]) catch {};
                        }
                        dyn_items.append(fa, item) catch {};
                        dyn_children.append(fa, child) catch {};
                    }
                    count += 1;
                }
                const items_slice = if (dyn_items.items.len > 0) dyn_items.items else stack_items[0..count];
                const children_slice = if (dyn_children.items.len > 0) dyn_children.items else stack_children[0..count];
                const g = if (count > 1) pxGap(p.gap, self.scale) * @as(i32, @intCast(count - 1)) else 0;
                var main_total: i32 = 0;
                const sizes_slice: []i32 = if (count <= 32) stack_sizes[0..count] else (fa.alloc(i32, count) catch &[_]i32{});
                if (main_definite and count > 0) {
                    @memset(sizes_slice, 0);
                    const avail = @max(0, main_limit - pad_main - g);
                    _ = layout.distribute(fa, items_slice, avail, sizes_slice);
                    for (sizes_slice) |sz| main_total += sz;
                } else {
                    for (items_slice) |it| main_total += it.base;
                }
                var cross_max: i32 = 0;
                for (children_slice, 0..) |child, i| {
                    var measured = child.measured;
                    if (main_definite and i < sizes_slice.len) {
                        const chk = child.layout.main;
                        const remeasure = switch (chk) {
                            .grow => true,
                            .fit_shrink => child.layout.kind == .leaf and sizes_slice[i] != items_slice[i].base,
                            else => false,
                        };
                        if (remeasure) {
                            const relim = layout.Limit{
                                .w = if (vertical) limit.w else sizes_slice[i],
                                .h = if (vertical) sizes_slice[i] else limit.h,
                                .definite_w = if (vertical) limit.definite_w else true,
                                .definite_h = if (vertical) true else limit.definite_h,
                            };
                            measured = self.measureNode(child, relim, mode);
                        }
                    }
                    const cc = if (vertical) measured.w else measured.h;
                    cross_max = @max(cross_max, cc);
                }
                size = if (vertical)
                    .{ .w = cross_max + pad_w, .h = main_total + g + pad_h }
                else
                    .{ .w = main_total + g + pad_w, .h = cross_max + pad_h };
            },
            .stack => {
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
            .table => |tb| {
                const ncols = tb.columns.len;
                const col_gap = pxGap(tb.col_gap, self.scale);
                const row_gap = pxGap(p.gap, self.scale);
                const header_w = self.frameAlloc().alloc(i32, ncols) catch @panic("oom");
                @memset(header_w, 0);
                const col_w = self.frameAlloc().alloc(i32, ncols) catch @panic("oom");
                @memset(col_w, 0);

                var row_idx: usize = 0;
                var c = node.first_child;
                while (c) |row| : (c = row.next) {
                    if (row.layout.kind == .anchor) continue;
                    if (row_idx < tb.header_rows) {
                        var ci: usize = 0;
                        var cell = row.first_child;
                        while (cell) |cc| : (cell = cc.next) {
                            if (ci < header_w.len) {
                                const cs = self.measureNode(cc, .{ .w = layout.unbounded, .h = layout.unbounded }, mode);
                                header_w[ci] = @max(header_w[ci], cs.w);
                            }
                            ci += 1;
                        }
                    }
                    row_idx += 1;
                }
                if (ncols > 0) {
                    const inner_w = @max(0, limit.w - pad_w);
                    layout.solveColumns(self.frameAlloc(), tb.columns, header_w, inner_w, limit.definite_w, col_gap, self.scale, col_w);
                }
                var total_w: i32 = if (ncols > 1) col_gap * @as(i32, @intCast(ncols - 1)) else 0;
                for (col_w) |cw| total_w += cw;

                var total_h: i32 = 0;
                var rows_n: usize = 0;
                c = node.first_child;
                while (c) |row| : (c = row.next) {
                    if (row.layout.kind == .anchor) continue;
                    var rh: i32 = 0;
                    switch (row.layout.cross) {
                        .fixed => |v| rh = px(v, self.scale),
                        else => {
                            var ci: usize = 0;
                            var cell = row.first_child;
                            while (cell) |cc| : (cell = cc.next) {
                                if (ci < col_w.len) {
                                    const cs = self.measureNode(cc, .{ .w = col_w[ci], .h = layout.unbounded, .definite_w = true }, mode);
                                    rh = @max(rh, cs.h);
                                }
                                ci += 1;
                            }
                        },
                    }
                    total_h += rh;
                    rows_n += 1;
                }
                if (rows_n > 1) total_h += row_gap * @as(i32, @intCast(rows_n - 1));
                size = .{ .w = total_w + pad_w, .h = total_h + pad_h };
            },
            .form => |f| {
                const fa = self.frameAlloc();
                var items = std.ArrayListUnmanaged(struct { sz: layout.SizeI, span: bool }).empty;
                var c = node.first_child;
                while (c) |child| : (c = child.next) {
                    if (child.layout.kind == .anchor) continue;
                    const cs = self.measureNode(child, .{ .w = layout.unbounded, .h = layout.unbounded }, mode);
                    items.append(fa, .{ .sz = cs, .span = child.layout.form_span }) catch {};
                }
                const col_gap = pxGap(f.col_gap, self.scale);
                const row_gap = pxGap(p.gap, self.scale);
                var label_w: i32 = 0;
                var field_max: i32 = 0;
                var total_h: i32 = 0;
                var rows: usize = 0;
                var i: usize = 0;
                while (i < items.items.len) {
                    const it = items.items[i];
                    if (it.span) {
                        total_h += it.sz.h;
                        rows += 1;
                        i += 1;
                        continue;
                    }
                    var rh = it.sz.h;
                    if (i + 1 < items.items.len and !items.items[i + 1].span) {
                        label_w = @max(label_w, it.sz.w);
                        field_max = @max(field_max, items.items[i + 1].sz.w);
                        rh = @max(rh, items.items[i + 1].sz.h);
                        i += 2;
                    } else {
                        // 落单的最后一项是字段，标签列留空。
                        field_max = @max(field_max, it.sz.w);
                        i += 1;
                    }
                    total_h += rh;
                    rows += 1;
                }
                if (rows > 1) total_h += row_gap * @as(i32, @intCast(rows - 1));
                const cap = px(f.label_max, self.scale);
                const half = if (limit.definite_w) @divFloor(@max(0, limit.w - pad_w), 2) else cap;
                label_w = @min(label_w, @min(cap, half));
                if (limit.definite_w) {
                    size.w = limit.w;
                } else {
                    size.w = label_w + col_gap + field_max + pad_w;
                }
                size.h = total_h + pad_h;
            },
            .scroll => |s| {
                if (limit.definite_w and limit.definite_h) {
                    size = .{ .w = limit.w, .h = limit.h };
                } else {
                    var cw: i32 = 0;
                    var ch: i32 = 0;
                    if (node.first_child) |child| {
                        const cl = layout.Limit{
                            .w = if (s.axes == .vertical) @max(0, limit.w - pad_w) else layout.unbounded,
                            .h = if (s.axes == .horizontal) @max(0, limit.h - pad_h) else layout.unbounded,
                            .definite_w = s.axes == .vertical and limit.w != layout.unbounded,
                            .definite_h = s.axes == .horizontal and limit.h != layout.unbounded,
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
                }
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
                var rctx = self.makeCustomRunCtx(node);
                defer rctx.children.deinit(self.gpa);
                defer rctx.placed.deinit(self.gpa);
                var ctx = layout.MeasureCtx{
                    .scale = self.scale,
                    .ctx = &rctx,
                    .child_count_fn = CustomRunCtx.childCount,
                    .child_params_fn = CustomRunCtx.childParams,
                    .measure_child_fn = CustomRunCtx.measureChild,
                };
                size = cl.measure(&ctx, mode, limit);
            },
        }
        if (!node.measured_valid and p.main_min > p.main_max) {
            core.log.write(.warn, "layout", "main_min({d}) > main_max({d})，按 [min, min] 处理（REQ-LAYOUT-010）", .{ p.main_min, p.main_max });
        }
        if (!node.measured_valid and p.cross_min > p.cross_max) {
            core.log.write(.warn, "layout", "cross_min({d}) > cross_max({d})，按 [min, min] 处理（REQ-LAYOUT-010）", .{ p.cross_min, p.cross_max });
        }
        size.w = clampSize(size.w, p.main_min, p.main_max, self.scale);
        size.h = clampSize(size.h, p.cross_min, p.cross_max, self.scale);
        if (mode == .min and limit.w == layout.unbounded and limit.h == layout.unbounded) {
            node.min_measured = size;
            node.min_measured_valid = true;
            return size;
        }
        if (node.measured_valid) {
            node.measured2 = node.measured;
            node.measured2_valid = node.measured_valid;
            node.measured2_limit = node.measured_limit;
            node.measured2_mode = node.measured_mode;
        }
        node.measured = size;
        node.measured_valid = true;
        node.measured_limit = limit;
        node.measured_mode = mode;
        return size;
    }

    fn cloneScrollMetrics(self: *Ui, src: ?*layout.ScrollMetrics) ?*layout.ScrollMetrics {
        const s = src orelse return null;
        const p = self.treeAlloc().create(layout.ScrollMetrics) catch return null;
        p.* = s.*;
        return p;
    }

    fn cloneSplitMetrics(self: *Ui, src: ?*layout.SplitMetrics) ?*layout.SplitMetrics {
        const s = src orelse return null;
        const p = self.treeAlloc().create(layout.SplitMetrics) catch return null;
        p.* = s.*;
        return p;
    }

    fn copySubtreeArrange(tree_alloc: std.mem.Allocator, old_n: *const Node, new_n: *Node, dx: i32, dy: i32, same_clip: bool) void {
        var oc = old_n.first_child;
        var nc = new_n.first_child;
        if (same_clip and dx == 0 and dy == 0) {
            while (oc != null and nc != null) {
                const o = oc.?;
                const n = nc.?;
                n.rect = o.rect;
                n.abs = o.abs;
                n.clip = o.clip;
                if (o.first_child != null) {
                    if (o.scroll_metrics) |sm| {
                        if (tree_alloc.create(layout.ScrollMetrics)) |p| {
                            p.* = sm.*;
                            n.scroll_metrics = p;
                        } else |_| {}
                    }
                    if (o.split_metrics) |spm| {
                        if (tree_alloc.create(layout.SplitMetrics)) |p| {
                            p.* = spm.*;
                            n.split_metrics = p;
                        } else |_| {}
                    }
                    copySubtreeArrange(tree_alloc, o, n, 0, 0, true);
                }
                oc = o.next;
                nc = n.next;
            }
            return;
        }
        while (oc != null and nc != null) {
            const o = oc.?;
            const n = nc.?;
            n.rect = o.rect;
            n.abs = .{ .x = o.abs.x + dx, .y = o.abs.y + dy, .w = o.abs.w, .h = o.abs.h };
            n.clip = if (same_clip) o.clip else n.abs.intersect(new_n.clip);
            if (o.first_child != null) {
                if (o.scroll_metrics) |sm| {
                    if (tree_alloc.create(layout.ScrollMetrics)) |p| {
                        p.* = sm.*;
                        n.scroll_metrics = p;
                    } else |_| {}
                }
                if (o.split_metrics) |spm| {
                    if (tree_alloc.create(layout.SplitMetrics)) |p| {
                        p.* = spm.*;
                        n.split_metrics = p;
                    } else |_| {}
                }
                copySubtreeArrange(tree_alloc, o, n, dx, dy, same_clip and o.clip.w == n.clip.w and o.clip.h == n.clip.h);
            }
            oc = o.next;
            nc = n.next;
        }
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
        if (node.reused_measure and !node.has_anchor_child and node.layout.kind != .scroll and node.layout.kind != .splitter and node.layout.kind != .anchor) {
            if (node.reused_from) |old_n| {
                if (old_n.rect.w == rect.w and old_n.rect.h == rect.h) {
                    if (old_n.scroll_metrics != null) node.scroll_metrics = self.cloneScrollMetrics(old_n.scroll_metrics);
                    if (old_n.split_metrics != null) node.split_metrics = self.cloneSplitMetrics(old_n.split_metrics);
                    const dx = node.abs.x - old_n.abs.x;
                    const dy = node.abs.y - old_n.abs.y;
                    const same_clip = dx == 0 and dy == 0 and node.clip.x == old_n.clip.x and node.clip.y == old_n.clip.y and node.clip.w == old_n.clip.w and node.clip.h == old_n.clip.h;
                    if (old_n.first_child != null) copySubtreeArrange(self.treeAlloc(), old_n, node, dx, dy, same_clip);
                    return;
                }
            }
        }
        switch (node.layout.kind) {
            .row, .column, .table_row => {
                const vertical = node.layout.kind == .column;
                const pad = node.layout.padding;
                const bi = @as(i32, node.layout.border) * self.theme_ptr.hairline(self.scale);
                const inner = core.RectI{
                    .x = px(pad.l, self.scale) + bi,
                    .y = px(pad.t, self.scale) + bi,
                    .w = @max(0, rect.w - px(pad.l, self.scale) - px(pad.r, self.scale) - bi * 2),
                    .h = @max(0, rect.h - px(pad.t, self.scale) - px(pad.b, self.scale) - bi * 2),
                };
                const gap = pxGap(node.layout.gap, self.scale);
                const avail = if (vertical) inner.h else inner.w;
                const fa = self.frameAlloc();
                var stack_items: [32]layout.FlexItem = undefined;
                var stack_children: [32]*Node = undefined;
                var stack_sizes: [32]i32 = undefined;
                var dyn_items = std.ArrayListUnmanaged(layout.FlexItem).empty;
                var dyn_children = std.ArrayListUnmanaged(*Node).empty;
                var child_cnt: usize = 0;
                var c = node.first_child;
                while (c) |ch| : (c = ch.next) {
                    if (ch.layout.kind == .anchor) continue;
                    const natural = self.measureNode(ch, .{
                        .w = if (vertical) inner.w else layout.unbounded,
                        .h = if (vertical) layout.unbounded else inner.h,
                        .definite_w = vertical,
                        .definite_h = !vertical,
                    }, .natural);
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
                        .fit_shrink => {
                            if (ch.layout.kind == .leaf) {
                                kind = .shrink;
                            } else {
                                // 容器不参与 fit_shrink 收缩（REQ-LAYOUT-011）。
                                kind = .fit;
                                if (!ch.fit_shrink_warned) {
                                    ch.fit_shrink_warned = true;
                                    core.log.write(.warn, "layout", "容器节点声明 fit_shrink，按 fit 处理（REQ-LAYOUT-011）", .{});
                                }
                            }
                        },
                        .grow => |w| {
                            kind = .grow;
                            base = 0;
                            wq = layout.quantizeWeight(w);
                        },
                    }
                    const item = layout.FlexItem{
                        .kind = kind,
                        .base = base,
                        .min = px(ch.layout.main_min, self.scale),
                        .max = if (ch.layout.main_max == std.math.inf(f32)) layout.unbounded else px(ch.layout.main_max, self.scale),
                        .wq = wq,
                    };
                    if (child_cnt < 32 and dyn_items.items.len == 0) {
                        stack_items[child_cnt] = item;
                        stack_children[child_cnt] = ch;
                    } else {
                        if (dyn_items.items.len == 0) {
                            dyn_items.appendSlice(fa, stack_items[0..child_cnt]) catch {};
                            dyn_children.appendSlice(fa, stack_children[0..child_cnt]) catch {};
                        }
                        dyn_items.append(fa, item) catch {};
                        dyn_children.append(fa, ch) catch {};
                    }
                    child_cnt += 1;
                }
                const items_slice = if (dyn_items.items.len > 0) dyn_items.items else stack_items[0..child_cnt];
                const children_slice = if (dyn_children.items.len > 0) dyn_children.items else stack_children[0..child_cnt];
                const gap_total = if (child_cnt > 1) gap * @as(i32, @intCast(child_cnt - 1)) else 0;
                const sizes_slice: []i32 = if (child_cnt <= 32) stack_sizes[0..child_cnt] else (fa.alloc(i32, child_cnt) catch &[_]i32{});
                const dr = layout.distribute(fa, items_slice, @max(0, avail - gap_total), sizes_slice);
                _ = dr;
                var used: i32 = gap_total;
                for (sizes_slice) |sz| used += sz;
                const free = @max(0, avail - used);
                const justify_off: i32 = switch (node.layout.justify) {
                    .center => @divFloor(free, 2),
                    .end => free,
                    else => 0,
                };
                const n_children = child_cnt;
                const sb = node.layout.justify == .space_between and n_children > 1;
                const sb_base = if (sb) @divTrunc(free, @as(i32, @intCast(n_children - 1))) else 0;
                const sb_rem = if (sb) @mod(free, @as(i32, @intCast(n_children - 1))) else 0;
                var pos = (if (vertical) inner.y else inner.x) + justify_off;
                for (children_slice, 0..) |ch, i| {
                    const ms = sizes_slice[i];
                    var cs: i32 = if (vertical) ch.measured.w else ch.measured.h;
                    switch (ch.layout.cross) {
                        .fixed => |v| cs = px(v, self.scale),
                        .fit => cs = if (vertical) ch.measured.w else ch.measured.h,
                        .fill => cs = if (vertical) inner.w else inner.h,
                    }
                    cs = clampSize(cs, ch.layout.cross_min, ch.layout.cross_max, self.scale);
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
                    if (sb and i + 1 < n_children) {
                        pos += sb_base + @as(i32, @intFromBool(i < sb_rem));
                    }
                }
                // Anchor 子项：按父内部矩形放置
                c = node.first_child;
                while (c) |ch| : (c = ch.next) {
                    if (ch.layout.kind == .anchor) self.arrangeAnchor(ch, inner, node.abs);
                }
            },
            .stack => {
                const bi = @as(i32, node.layout.border) * self.theme_ptr.hairline(self.scale);
                const inner = core.RectI{
                    .x = px(node.layout.padding.l, self.scale) + bi,
                    .y = px(node.layout.padding.t, self.scale) + bi,
                    .w = @max(0, rect.w - px(node.layout.padding.l, self.scale) - px(node.layout.padding.r, self.scale) - bi * 2),
                    .h = @max(0, rect.h - px(node.layout.padding.t, self.scale) - px(node.layout.padding.b, self.scale) - bi * 2),
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
                        .fit, .fit_shrink => w = @min(w, inner.w),
                    }
                    switch (ch.layout.cross) {
                        .fixed => |v| h = px(v, self.scale),
                        .fill => h = inner.h,
                        else => {},
                    }
                    if (ch.layout.virtual_pos_px) |vp| {
                        self.arrangeNode(ch, .{ .x = inner.x + vp[0], .y = inner.y + vp[1], .w = w, .h = h }, node.abs);
                        continue;
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
            .table => |tb| {
                const bi = @as(i32, node.layout.border) * self.theme_ptr.hairline(self.scale);
                const inner = core.RectI{
                    .x = px(node.layout.padding.l, self.scale) + bi,
                    .y = px(node.layout.padding.t, self.scale) + bi,
                    .w = @max(0, rect.w - px(node.layout.padding.l, self.scale) - px(node.layout.padding.r, self.scale) - bi * 2),
                    .h = @max(0, rect.h - px(node.layout.padding.t, self.scale) - px(node.layout.padding.b, self.scale) - bi * 2),
                };
                const ncols = tb.columns.len;
                const col_gap = pxGap(tb.col_gap, self.scale);
                const row_gap = pxGap(node.layout.gap, self.scale);
                const header_w = self.frameAlloc().alloc(i32, ncols) catch @panic("oom");
                @memset(header_w, 0);
                const col_w = self.frameAlloc().alloc(i32, ncols) catch @panic("oom");
                @memset(col_w, 0);
                var row_idx: usize = 0;
                var c = node.first_child;
                while (c) |row| : (c = row.next) {
                    if (row.layout.kind == .anchor) continue;
                    if (row_idx < tb.header_rows) {
                        var ci: usize = 0;
                        var cell = row.first_child;
                        while (cell) |cc| : (cell = cc.next) {
                            if (ci < header_w.len) {
                                const cs = self.measureNode(cc, .{ .w = layout.unbounded, .h = layout.unbounded }, .natural);
                                header_w[ci] = @max(header_w[ci], cs.w);
                            }
                            ci += 1;
                        }
                    }
                    row_idx += 1;
                }
                if (ncols > 0) {
                    layout.solveColumns(self.frameAlloc(), tb.columns, header_w, inner.w, true, col_gap, self.scale, col_w);
                }
                var y = inner.y;
                var first_row = true;
                c = node.first_child;
                while (c) |row| : (c = row.next) {
                    if (row.layout.kind == .anchor) {
                        self.arrangeAnchor(row, inner, node.abs);
                        continue;
                    }
                    var rh: i32 = 0;
                    switch (row.layout.cross) {
                        .fixed => |v| rh = px(v, self.scale),
                        else => {
                            var ci: usize = 0;
                            var cell = row.first_child;
                            while (cell) |cc| : (cell = cc.next) {
                                if (ci < col_w.len) {
                                    const cs = self.measureNode(cc, .{ .w = col_w[ci], .h = layout.unbounded, .definite_w = true }, .natural);
                                    rh = @max(rh, cs.h);
                                }
                                ci += 1;
                            }
                        },
                    }
                    if (!first_row) y += row_gap;
                    first_row = false;
                    // 设置行矩形与各列单元格矩形（REQ-LAYOUT-038/040）。
                    row.rect = .{ .x = inner.x, .y = y, .w = inner.w, .h = rh };
                    row.abs = .{ .x = node.abs.x + inner.x, .y = node.abs.y + y, .w = inner.w, .h = rh };
                    row.clip = row.abs.intersect(node.clip);
                    var x: i32 = 0;
                    var ci: usize = 0;
                    var cell = row.first_child;
                    while (cell) |cc| : (cell = cc.next) {
                        if (ci >= col_w.len) break;
                        const cw = col_w[ci];
                        const ms = self.measureNode(cc, .{ .w = cw, .h = rh, .definite_w = true, .definite_h = true }, .natural);
                        const w = switch (cc.layout.main) {
                            .grow => cw,
                            .fixed => |v| px(v, self.scale),
                            .fit, .fit_shrink => @min(ms.w, cw),
                        };
                        const h = switch (cc.layout.cross) {
                            .fill => rh,
                            .fixed => |v| px(v, self.scale),
                            .fit => @min(ms.h, rh),
                        };
                        const ax = switch (cc.layout.self_main_align orelse .start) {
                            .center => @divFloor(@max(0, cw - w), 2),
                            .end => @max(0, cw - w),
                            else => 0,
                        };
                        const ay = switch (cc.layout.self_align orelse row.layout.cross_align) {
                            .center => @divFloor(@max(0, rh - h), 2),
                            .end => @max(0, rh - h),
                            else => 0,
                        };
                        self.arrangeNode(cc, .{ .x = x + ax, .y = ay, .w = w, .h = h }, row.abs);
                        x += cw + col_gap;
                        ci += 1;
                    }
                    y += rh;
                }
            },
            .form => |f| {
                const bi = @as(i32, node.layout.border) * self.theme_ptr.hairline(self.scale);
                const inner = core.RectI{
                    .x = px(node.layout.padding.l, self.scale) + bi,
                    .y = px(node.layout.padding.t, self.scale) + bi,
                    .w = @max(0, rect.w - px(node.layout.padding.l, self.scale) - px(node.layout.padding.r, self.scale) - bi * 2),
                    .h = @max(0, rect.h - px(node.layout.padding.t, self.scale) - px(node.layout.padding.b, self.scale) - bi * 2),
                };
                const fa = self.frameAlloc();
                var kids = std.ArrayListUnmanaged(*Node).empty;
                var c = node.first_child;
                while (c) |ch| : (c = ch.next) {
                    if (ch.layout.kind == .anchor) continue;
                    kids.append(fa, ch) catch {};
                }
                var label_w: i32 = 0;
                var i: usize = 0;
                while (i < kids.items.len) {
                    const ch = kids.items[i];
                    if (!ch.layout.form_span and i + 1 < kids.items.len and !kids.items[i + 1].layout.form_span) {
                        label_w = @max(label_w, self.measureNode(ch, .{ .w = layout.unbounded, .h = layout.unbounded }, .natural).w);
                        i += 2;
                    } else i += 1;
                }
                const cap = px(f.label_max, self.scale);
                label_w = @min(label_w, @min(cap, @divFloor(inner.w, 2)));
                const col_gap = pxGap(f.col_gap, self.scale);
                const field_w = @max(0, inner.w - label_w - col_gap);
                const row_gap = pxGap(node.layout.gap, self.scale);
                var y = inner.y;
                var first_row = true;
                i = 0;
                while (i < kids.items.len) {
                    const first = kids.items[i];
                    var row_h: i32 = 0;
                    var second: ?*Node = null;
                    if (first.layout.form_span) {
                        row_h = self.measureNode(first, .{ .w = inner.w, .h = layout.unbounded, .definite_w = true }, .natural).h;
                    } else {
                        const ls = self.measureNode(first, .{ .w = label_w, .h = layout.unbounded, .definite_w = true }, .natural);
                        row_h = ls.h;
                        if (i + 1 < kids.items.len and !kids.items[i + 1].layout.form_span) {
                            second = kids.items[i + 1];
                            const fs = self.measureNode(second.?, .{ .w = field_w, .h = layout.unbounded, .definite_w = true }, .natural);
                            row_h = @max(row_h, fs.h);
                        }
                    }
                    if (!first_row) y += row_gap;
                    first_row = false;
                    if (first.layout.form_span) {
                        const h = row_h;
                        self.arrangeNode(first, .{ .x = inner.x, .y = y, .w = inner.w, .h = h }, node.abs);
                        y += h;
                        i += 1;
                        continue;
                    }
                    if (second == null) {
                        const fs = self.measureNode(first, .{ .w = field_w, .h = layout.unbounded, .definite_w = true }, .natural);
                        const fy = switch (first.layout.self_align orelse .center) {
                            .start => y,
                            .center => y + @divFloor(@max(0, row_h - fs.h), 2),
                            .end => y + @max(0, row_h - fs.h),
                        };
                        self.arrangeNode(first, .{ .x = inner.x + label_w + col_gap, .y = fy, .w = field_w, .h = fs.h }, node.abs);
                        i += 1;
                        y += row_h;
                        continue;
                    }
                    const ls = self.measureNode(first, .{ .w = label_w, .h = layout.unbounded, .definite_w = true }, .natural);
                    const ly = switch (first.layout.self_align orelse .center) {
                        .start => y,
                        .center => y + @divFloor(@max(0, row_h - ls.h), 2),
                        .end => y + @max(0, row_h - ls.h),
                    };
                    self.arrangeNode(first, .{ .x = inner.x, .y = ly, .w = label_w, .h = ls.h }, node.abs);
                    if (second) |fld| {
                        const fs = self.measureNode(fld, .{ .w = field_w, .h = layout.unbounded, .definite_w = true }, .natural);
                        const fy = switch (fld.layout.self_align orelse .center) {
                            .start => y,
                            .center => y + @divFloor(@max(0, row_h - fs.h), 2),
                            .end => y + @max(0, row_h - fs.h),
                        };
                        self.arrangeNode(fld, .{ .x = inner.x + label_w + col_gap, .y = fy, .w = field_w, .h = fs.h }, node.abs);
                        i += 2;
                    } else {
                        i += 1;
                    }
                    y += row_h;
                }
            },
            .scroll => |s| {
                const bar = px(self.theme_ptr.metric(.scrollbar_w), self.scale);
                const bi = @as(i32, node.layout.border) * self.theme_ptr.hairline(self.scale);
                const inner = core.RectI{
                    .x = px(node.layout.padding.l, self.scale) + bi,
                    .y = px(node.layout.padding.t, self.scale) + bi,
                    .w = @max(0, rect.w - px(node.layout.padding.l, self.scale) - px(node.layout.padding.r, self.scale) - bi * 2),
                    .h = @max(0, rect.h - px(node.layout.padding.t, self.scale) - px(node.layout.padding.b, self.scale) - bi * 2),
                };
                var content_size = core.Size2i{};
                if (node.first_child) |child| {
                    const cl = layout.Limit{
                        .w = if (s.axes == .vertical) inner.w else layout.unbounded,
                        .h = if (s.axes == .horizontal) inner.h else layout.unbounded,
                        .definite_w = s.axes == .vertical,
                        .definite_h = s.axes == .horizontal,
                    };
                    self.last_scroll_axis_limit = cl;
                    content_size = self.measureNode(child, cl, .natural);
                }
                var viewport = inner;
                const need_v = s.axes != .horizontal and switch (s.bar_v) {
                    .never => false,
                    .always => true,
                    .auto => content_size.h > inner.h,
                };
                if (need_v) viewport.w = @max(0, viewport.w - bar);
                const need_h = s.axes != .vertical and switch (s.bar_h) {
                    .never => false,
                    .always => true,
                    .auto => content_size.w > viewport.w,
                };
                if (need_h) viewport.h = @max(0, viewport.h - bar);
                if (s.axes == .vertical and need_v and s.bar_v == .auto and node.first_child != null) {
                    const cl2 = layout.Limit{ .w = viewport.w, .h = layout.unbounded, .definite_w = true };
                    self.last_scroll_axis_limit = cl2;
                    content_size = self.measureNode(node.first_child.?, cl2, .natural);
                    self.scroll_remeasures += 1;
                } else if (s.axes == .horizontal and need_h and s.bar_h == .auto and node.first_child != null) {
                    const cl2 = layout.Limit{ .w = layout.unbounded, .h = viewport.h, .definite_h = true };
                    self.last_scroll_axis_limit = cl2;
                    content_size = self.measureNode(node.first_child.?, cl2, .natural);
                    self.scroll_remeasures += 1;
                }
                const content_w_64: i64 = if (s.virtual_extent_px) |ve| ve[0] else if (s.axes == .vertical) viewport.w else content_size.w;
                const content_h_64: i64 = if (s.virtual_extent_px) |ve| ve[1] else if (s.axes == .horizontal) viewport.h else content_size.h;
                const content_w: i32 = @intCast(@min(content_w_64, std.math.maxInt(i32)));
                const content_h: i32 = @intCast(@min(content_h_64, std.math.maxInt(i32)));
                const max_x_64 = @max(@as(i64, 0), content_w_64 - viewport.w);
                const max_y_64 = @max(@as(i64, 0), content_h_64 - viewport.h);
                const max_y: i32 = @intCast(@min(max_y_64, std.math.maxInt(i32)));
                const req_x: i64 = if (s.offset_px) |opx| opx[0] else scrollOffsetPx(s.offset.x, self.scale);
                const req_y: i64 = if (s.offset_px) |opx| opx[1] else scrollOffsetPx(s.offset.y, self.scale);
                const off_x: i32 = @intCast(std.math.clamp(req_x, 0, max_x_64));
                var off_y_64: i64 = std.math.clamp(req_y, 0, max_y_64);
                const prev = self.scroll_states.get(node.id.raw());
                if (s.anchor_end and max_y > 0 and prev != null and prev.?.has and prev.?.req_y >= prev.?.max_y) {
                    off_y_64 = max_y_64;
                }
                if (s.reveal) |rev| {
                    const ry: i64 = scrollOffsetPx(rev.y, self.scale);
                    const rh: i64 = @max(0, scrollOffsetPx(rev.h, self.scale));
                    if (rh >= viewport.h) {
                        off_y_64 = ry;
                    } else if (ry < off_y_64) {
                        off_y_64 = ry;
                    } else if (ry + rh > off_y_64 + viewport.h) {
                        off_y_64 = ry + rh - viewport.h;
                    }
                    off_y_64 = std.math.clamp(off_y_64, 0, max_y_64);
                }
                const off_y: i32 = @intCast(std.math.clamp(off_y_64, 0, std.math.maxInt(i32)));
                self.scroll_states.put(self.gpa, node.id.raw(), .{ .req_y = @intCast(std.math.clamp(req_y, 0, std.math.maxInt(i32))), .max_y = max_y, .has = true }) catch {};
                const sm_ptr = node.scroll_metrics orelse (self.treeAlloc().create(layout.ScrollMetrics) catch @panic("oom"));
                sm_ptr.* = .{
                    .offset = .{ .x = @as(f32, @floatFromInt(off_x)) / self.scale, .y = @as(f32, @floatFromInt(off_y_64)) / self.scale },
                    .offset_px = .{ .x = off_x, .y = off_y },
                    .content_px = .{ content_w_64, content_h_64 },
                    .viewport_px = .{ viewport.w, viewport.h },
                    .max_offset = .{ .x = @as(f32, @floatFromInt(max_x_64)) / self.scale, .y = @as(f32, @floatFromInt(max_y_64)) / self.scale },
                    .viewport = .{ .x = @as(f32, @floatFromInt(viewport.x)) / self.scale, .y = @as(f32, @floatFromInt(viewport.y)) / self.scale, .w = @as(f32, @floatFromInt(viewport.w)) / self.scale, .h = @as(f32, @floatFromInt(viewport.h)) / self.scale },
                    .content = .{ .x = @as(f32, @floatFromInt(content_w_64)) / self.scale, .y = @as(f32, @floatFromInt(content_h_64)) / self.scale },
                    .bar_v = if (need_v) .{ .x = viewport.x + viewport.w, .y = viewport.y, .w = bar, .h = viewport.h } else null,
                    .bar_h = if (need_h) .{ .x = viewport.x, .y = viewport.y + viewport.h, .w = viewport.w, .h = bar } else null,
                };
                node.scroll_metrics = sm_ptr;
                if (node.first_child) |child| {
                    const abs_viewport = core.RectI{
                        .x = node.abs.x + viewport.x,
                        .y = node.abs.y + viewport.y,
                        .w = viewport.w,
                        .h = viewport.h,
                    };
                    node.clip = node.clip.intersect(abs_viewport);
                    const child_pos = if (child.layout.virtual_pos_px) |vp|
                        core.RectI{ .x = viewport.x + vp[0], .y = viewport.y + vp[1], .w = viewport.w, .h = viewport.h }
                    else if (s.virtual_extent_px != null)
                        core.RectI{ .x = viewport.x, .y = viewport.y, .w = viewport.w, .h = viewport.h }
                    else
                        core.RectI{ .x = viewport.x - off_x, .y = viewport.y - off_y, .w = @max(content_w, viewport.w), .h = @max(content_h, viewport.h) };
                    self.arrangeNode(child, child_pos, node.abs);
                    child.clip = child.clip.intersect(abs_viewport);
                }
            },
            .splitter => |s| {
                const sw = px(self.theme_ptr.metric(.splitter_w), self.scale);
                const bi = @as(i32, node.layout.border) * self.theme_ptr.hairline(self.scale);
                const inner = core.RectI{
                    .x = px(node.layout.padding.l, self.scale) + bi,
                    .y = px(node.layout.padding.t, self.scale) + bi,
                    .w = @max(0, rect.w - px(node.layout.padding.l, self.scale) - px(node.layout.padding.r, self.scale) - bi * 2),
                    .h = @max(0, rect.h - px(node.layout.padding.t, self.scale) - px(node.layout.padding.b, self.scale) - bi * 2),
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
                const sp_ptr = node.split_metrics orelse (self.treeAlloc().create(layout.SplitMetrics) catch @panic("oom"));
                sp_ptr.* = .{ .first_px = first, .second_px = second, .divider = if (horizontal) .{ .x = inner.x + first, .y = inner.y, .w = sw, .h = inner.h } else .{ .x = inner.x, .y = inner.y + first, .w = inner.w, .h = sw } };
                node.split_metrics = sp_ptr;
                var idx: usize = 0;
                var c = node.first_child;
                while (c) |ch| : (c = ch.next) {
                    if (idx == 0) {
                        ch.flags.clip_children = true;
                        self.arrangeNode(ch, if (horizontal) .{ .x = inner.x, .y = inner.y, .w = first, .h = inner.h } else .{ .x = inner.x, .y = inner.y, .w = inner.w, .h = first }, node.abs);
                    } else if (idx == 1) {
                        ch.flags.clip_children = true;
                        self.arrangeNode(ch, if (horizontal) .{ .x = inner.x + first + sw, .y = inner.y, .w = second, .h = inner.h } else .{ .x = inner.x, .y = inner.y + first + sw, .w = inner.w, .h = second }, node.abs);
                    }
                    idx += 1;
                }
            },
            .anchor => {},
            .custom => |cl| {
                const bi = @as(i32, node.layout.border) * self.theme_ptr.hairline(self.scale);
                const inner = core.RectI{
                    .x = px(node.layout.padding.l, self.scale) + bi,
                    .y = px(node.layout.padding.t, self.scale) + bi,
                    .w = @max(0, rect.w - px(node.layout.padding.l, self.scale) - px(node.layout.padding.r, self.scale) - bi * 2),
                    .h = @max(0, rect.h - px(node.layout.padding.t, self.scale) - px(node.layout.padding.b, self.scale) - bi * 2),
                };
                var rctx = self.makeCustomRunCtx(node);
                rctx.inner_origin = .{ .x = inner.x, .y = inner.y };
                defer rctx.children.deinit(self.gpa);
                defer rctx.placed.deinit(self.gpa);
                var ctx = layout.ArrangeCtx{
                    .scale = self.scale,
                    .ctx = &rctx,
                    .child_count_fn = CustomRunCtx.childCount,
                    .child_params_fn = CustomRunCtx.childParams,
                    .measure_child_fn = CustomRunCtx.measureChild,
                    .place_child_fn = CustomRunCtx.placeChild,
                };
                cl.arrange(&ctx, .{ .x = 0, .y = 0, .w = inner.w, .h = inner.h });
                for (rctx.children.items, 0..) |ch, i| {
                    if (!rctx.placed.items[i]) {
                        self.arrangeNode(ch, .{ .x = inner.x, .y = inner.y, .w = 0, .h = 0 }, node.abs);
                    }
                }
            },
            .leaf => {},
        }
    }

    const CustomRunCtx = struct {
        ui: *Ui,
        children: std.ArrayListUnmanaged(*Node) = .empty,
        placed: std.ArrayListUnmanaged(bool) = .empty,
        inner_origin: core.Vec2i = .{},

        fn childCount(raw: *anyopaque) usize {
            const self: *CustomRunCtx = @ptrCast(@alignCast(raw));
            return self.children.items.len;
        }
        fn childParams(raw: *anyopaque, index: usize) *const layout.Params {
            const self: *CustomRunCtx = @ptrCast(@alignCast(raw));
            return &self.children.items[index].layout;
        }
        fn measureChild(raw: *anyopaque, index: usize, limit: layout.Limit) layout.SizeI {
            const self: *CustomRunCtx = @ptrCast(@alignCast(raw));
            return self.ui.measureNode(self.children.items[index], limit, .natural);
        }
        fn placeChild(raw: *anyopaque, index: usize, r: core.RectI) void {
            const self: *CustomRunCtx = @ptrCast(@alignCast(raw));
            if (index >= self.children.items.len) return;
            self.placed.items[index] = true;
            const ch = self.children.items[index];
            self.ui.arrangeNode(ch, .{
                .x = self.inner_origin.x + r.x,
                .y = self.inner_origin.y + r.y,
                .w = r.w,
                .h = r.h,
            }, ch.parent.?.abs);
        }
    };

    fn makeCustomRunCtx(self: *Ui, node: *Node) CustomRunCtx {
        var rctx = CustomRunCtx{ .ui = self };
        var c = node.first_child;
        while (c) |ch| : (c = ch.next) {
            if (ch.layout.kind == .anchor) continue;
            rctx.children.append(self.gpa, ch) catch {};
            rctx.placed.append(self.gpa, false) catch {};
        }
        return rctx;
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

    fn addDamageRect(rects: *[8]core.RectI, count: *usize, r_in: core.RectI) void {
        if (r_in.isEmpty()) return;
        for (rects[0..count.*]) |*ex| {
            if (ex.x <= r_in.x and ex.y <= r_in.y and ex.right() >= r_in.right() and ex.bottom() >= r_in.bottom()) return;
            if (!ex.intersect(r_in).isEmpty()) {
                ex.* = unionRects(ex.*, r_in);
                return;
            }
        }
        if (count.* < 8) {
            rects[count.*] = r_in;
            count.* += 1;
            return;
        }
        // REQ-FRAME-041：超过 8 个时合并面积增量最小的一对（含新矩形）。
        var best_a: usize = 0;
        var best_b: usize = 8;
        var best_inc: i64 = std.math.maxInt(i64);
        var i: usize = 0;
        while (i < 8) : (i += 1) {
            const inc_new = unionRects(rects[i], r_in).area() - rects[i].area() - r_in.area();
            if (inc_new < best_inc) {
                best_inc = inc_new;
                best_a = i;
                best_b = 8;
            }
            var j: usize = i + 1;
            while (j < 8) : (j += 1) {
                const inc = unionRects(rects[i], rects[j]).area() - rects[i].area() - rects[j].area();
                if (inc < best_inc) {
                    best_inc = inc;
                    best_a = i;
                    best_b = j;
                }
            }
        }
        if (best_b == 8) {
            rects[best_a] = unionRects(rects[best_a], r_in);
        } else {
            rects[best_a] = unionRects(rects[best_a], rects[best_b]);
            rects[best_b] = r_in;
        }
    }

    pub fn damageRects(self: *const Ui) []const core.RectI {
        return self.damage_rects[0..self.damage_count];
    }

    // ---- 损伤与绘制 ----
    fn computeDamage(self: *Ui) void {
        const root = self.current_root orelse return;
        core.stats.timerBegin("time.damage");
        defer core.stats.timerEnd("time.damage");
        var rects: [8]core.RectI = @splat(.{});
        var count: usize = 0;
        var damage = core.RectI{};
        var full = (self.dirty == .build and self.diff_root == null) or self.force_rebuild;
        if (full) {
            damage = .{ .x = 0, .y = 0, .w = self.viewport.w, .h = self.viewport.h };
        } else if (self.dirty == .layout) {
            if (self.viewport.w != self.lastViewportW() or self.viewport.h != self.lastViewportH()) full = true;
        }
        if (self.built_this_frame) {
            // 差分
            const fa = self.frameAlloc();
            var list = std.ArrayListUnmanaged(core.RectI).empty;
            diffTree(self.diff_root, root, &list, fa, self.scale);
            for (list.items) |r| {
                addDamageRect(&rects, &count, r);
                damage = unionRects(damage, r);
            }
        }
        for (self.invalidated_rects.items) |r| {
            addDamageRect(&rects, &count, r);
            damage = unionRects(damage, r);
        }
        self.invalidated_rects.clearRetainingCapacity();
        if (full) {
            damage = .{ .x = 0, .y = 0, .w = self.viewport.w, .h = self.viewport.h };
            rects[0] = damage;
            count = 1;
        }
        if (damage.isEmpty() and self.dirty == .paint) {
            damage = .{ .x = 0, .y = 0, .w = self.viewport.w, .h = self.viewport.h };
            rects[0] = damage;
            count = 1;
        }
        var total_area: i64 = 0;
        for (rects[0..count]) |dr| total_area += dr.area();
        if (total_area * 2 >= @as(i64, self.viewport.w) * @as(i64, self.viewport.h)) {
            damage = .{ .x = 0, .y = 0, .w = self.viewport.w, .h = self.viewport.h };
            rects[0] = damage;
            count = 1;
        }
        self.damage = damage;
        self.damage_rects = rects;
        self.damage_count = count;
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
        // 脏标记的清除统一在 finishFrame（每帧必经），paint 不再清除。
        if (self.damage.isEmpty()) return false;
        self.last_frame_damage = self.damage;
        core.stats.timerBegin("time.paint");
        const canvas = surface.beginFrame(self.damage, self.scale);
        var ctx = PaintCtx{
            .draw = .{ .canvas = canvas, .theme = self.theme_ptr, .scale = self.scale, .window_active = self.window_active },
            .now = self.frame_now,
            .ui = self,
        };
        canvas.clip = self.damage.intersect(.{ .x = 0, .y = 0, .w = @intCast(surface.width), .h = @intCast(surface.height) });
        self.painted_nodes = 0;
        self.in_paint = true;
        paintTree(&ctx, self.current_root.?, self.damage);
        paintOverlayTrees(&ctx, self.current_root.?, self.damage);
        for (self.overlays.items) |ov| {
            const r = core.RectI{ .x = @intFromFloat(@round(ov.rect.x * self.scale)), .y = @intFromFloat(@round(ov.rect.y * self.scale)), .w = @intFromFloat(@round(ov.rect.w * self.scale)), .h = @intFromFloat(@round(ov.rect.h * self.scale)) };
            if (!r.intersect(self.damage).isEmpty()) ov.paint(&ctx, ov.rect, ov.props);
        }
        self.in_paint = false;
        if (self.show_damage) {
            const dr = core.Rect{
                .x = @as(f32, @floatFromInt(self.damage.x)) / self.scale,
                .y = @as(f32, @floatFromInt(self.damage.y)) / self.scale,
                .w = @as(f32, @floatFromInt(self.damage.w)) / self.scale,
                .h = @as(f32, @floatFromInt(self.damage.h)) / self.scale,
            };
            canvas.fillRect(dr, .{ .r = 255, .g = 0, .b = 255, .a = 32 });
            canvas.strokeRect(dr, .{ .r = 255, .g = 0, .b = 255, .a = 180 }, 1);
        }
        if (self.inspect_active and self.hover_id != .none) {
            if (self.getPrevNode(self.hover_id) orelse self.getNode(self.hover_id)) |n| {
                canvas.strokeRect(.{
                    .x = @as(f32, @floatFromInt(n.abs.x)) / self.scale,
                    .y = @as(f32, @floatFromInt(n.abs.y)) / self.scale,
                    .w = @as(f32, @floatFromInt(n.abs.w)) / self.scale,
                    .h = @as(f32, @floatFromInt(n.abs.h)) / self.scale,
                }, .{ .r = 255, .g = 0, .b = 0, .a = 255 }, 2);
            }
        }
        surface.endFrame();
        core.stats.timerEnd("time.paint");
        core.stats.timerEnd("time.frame_cpu");
        core.stats.timerEnd("time.input_to_present");
        core.stats.timerBegin("time.present");
        surface.present();
        core.stats.timerEnd("time.present");
        if (self.window) |w| {
            w.present_rgba = surface.presented;
            w.present_w = surface.width;
            w.present_h = surface.height;
            platform.present(w);
        }
        self.frame_count += 1;
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
        var tit = self.timers.iterator();
        while (tit.next()) |kv| {
            if (kv.value_ptr.touched + 2 < self.build_counter) tdel.append(self.frameAlloc(), kv.key_ptr.*) catch {};
        }
        for (tdel.items) |k| _ = self.timers.remove(k);
        self.dirty = self.carry_dirty;
        self.carry_dirty = .none;
        self.frame.reset();
        self.frame_generation += 1;
        self.clearInbox();
        self.pending.clearRetainingCapacity();
        self.interaction_cache.clearRetainingCapacity();
        self.dropped_id = .none;
        self.dropped_payload = null;
        self.running_after_frame = true;
        for (self.after_frame.items) |cl| cl.func(cl.ctx);
        self.running_after_frame = false;
        self.after_frame.clearRetainingCapacity();
        self.damage = .{};
        self.invalidated_rects.clearRetainingCapacity();
        core.stats.counter("frame.count").* += 1;
    }

    fn clearInbox(self: *Ui) void {
        var it = self.inbox.valueIterator();
        while (it.next()) |list| list.deinit(self.gpa);
        self.inbox.clearRetainingCapacity();
    }

    /// 节点检视文本：ID、调用点、矩形与状态槽数量（REQ-FRAME-057）。
    pub fn inspectionText(self: *const Ui, widget_id: core.WidgetId, buf: []u8) []const u8 {
        const n = self.getPrevNode(widget_id) orelse self.getNode(widget_id) orelse return "";
        var state_count: usize = 0;
        var sit = self.states.keyIterator();
        while (sit.next()) |k| if (k.id == widget_id.raw()) {
            state_count += 1;
        };
        return std.fmt.bufPrint(buf, "id={d} src={s}:{d} rect=({d},{d},{d},{d}) states={d}", .{
            widget_id.raw(), n.src_file, n.src_line, n.abs.x, n.abs.y, n.abs.w, n.abs.h, state_count,
        }) catch "";
    }

    pub fn frameDidLayout(self: *const Ui) bool {
        return self.frame_did_layout;
    }

    pub fn lastFrameDamage(self: *const Ui) core.RectI {
        return self.last_frame_damage;
    }

    pub fn needsFrame(self: *const Ui) bool {
        return self.dirty != .none or self.haveActiveAnimations();
    }

    pub fn lastScrollAxisLimit(self: *const Ui) ?layout.Limit {
        return self.last_scroll_axis_limit;
    }
    pub fn scrollMetrics(self: *const Ui, widget_id: core.WidgetId) ?layout.ScrollMetrics {
        if (self.getPrevNode(widget_id)) |n| if (n.scroll_metrics) |sm| return sm.*;
        return null;
    }
    pub fn splitMetrics(self: *const Ui, widget_id: core.WidgetId) ?layout.SplitMetrics {
        if (self.getPrevNode(widget_id)) |n| if (n.split_metrics) |sm| return sm.*;
        return null;
    }
    pub fn minWindowSize(self: *const Ui) core.Vec2 {
        if (self.current_root == null) return .{};
        if (self.min_window.x != 0 or self.min_window.y != 0) return self.min_window;
        const root = self.current_root.?;
        return .{ .x = @as(f32, @floatFromInt(root.measured.w)) / self.scale, .y = @as(f32, @floatFromInt(root.measured.h)) / self.scale };
    }
};

const NodeSnap = struct {
    id: u64,
    depth: u16,
    paint_key: u64,
    layout: layout.Params,
    flags: NodeFlags,
    name: ?[]const u8,
    file: []const u8,
    line: u32,
};

fn snapshotTree(node: ?*Node, depth: u16, out: *std.ArrayListUnmanaged(NodeSnap), gpa: std.mem.Allocator) void {
    const n = node orelse return;
    out.append(gpa, .{
        .id = n.id.raw(),
        .depth = depth,
        .paint_key = n.paint_key,
        .layout = n.layout,
        .flags = n.flags,
        .name = n.debug_name,
        .file = n.src_file,
        .line = n.src_line,
    }) catch {};
    var c = n.first_child;
    while (c) |cc| : (c = cc.next) snapshotTree(cc, depth + 1, out, gpa);
}

fn noteSnapDiff(report: *Ui.IdempotenceReport, snap: NodeSnap) void {
    report.differences += 1;
    if (report.first_id != .none) return;
    report.first_id = @fromBackingInt(@intCast(snap.id));
    report.first_name = snap.name;
    report.first_file = snap.file;
    report.first_line = snap.line;
}

fn compareSnapshots(a: []const NodeSnap, b: []const NodeSnap, report: *Ui.IdempotenceReport) void {
    const n = @min(a.len, b.len);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const x = a[i];
        const y = b[i];
        if (x.id != y.id or x.depth != y.depth or x.paint_key != y.paint_key or
            !std.meta.eql(x.layout, y.layout) or !std.meta.eql(x.flags, y.flags))
        {
            noteSnapDiff(report, y);
        }
    }
    if (a.len > n) {
        for (a[n..]) |x| noteSnapDiff(report, x);
    } else if (b.len > n) {
        for (b[n..]) |y| noteSnapDiff(report, y);
    }
}

fn formatUnbalanced(buf: *[256]u8, src: std.builtin.SourceLocation) []const u8 {
    return std.fmt.bufPrint(buf, "begin/end 不配对：{s}:{d}", .{ src.file, src.line }) catch "begin/end 不配对";
}

fn feedbackDiffers(node: ?*Node) bool {
    const n = node orelse return false;
    if (n.flags.layout_feedback) {
        if (!n.seen_last_rect or n.seen_w != n.abs.w or n.seen_h != n.abs.h) return true;
    }
    var c = n.first_child;
    while (c) |cc| : (c = cc.next) {
        if (feedbackDiffers(cc)) return true;
    }
    return false;
}

fn countNodes(node: *Node, out: *u32) void {
    out.* += 1;
    var c = node.first_child;
    while (c) |cc| : (c = cc.next) countNodes(cc, out);
}

fn limitEqual(a: layout.Limit, b: layout.Limit) bool {
    return a.w == b.w and a.h == b.h and a.definite_w == b.definite_w and a.definite_h == b.definite_h;
}

fn scrollOffsetPx(v: f32, scale: f32) i32 {
    if (std.math.isNan(v)) return 0;
    const s = v * scale;
    if (s >= @as(f32, @floatFromInt(std.math.maxInt(i32)))) return std.math.maxInt(i32);
    if (s <= @as(f32, @floatFromInt(std.math.minInt(i32)))) return std.math.minInt(i32);
    return @intFromFloat(@round(s));
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

fn outsetPx(r: core.RectI, outset_lpx: f32, scale: f32) core.RectI {
    if (outset_lpx <= 0) return r;
    const d: i32 = @intFromFloat(@ceil(outset_lpx * scale));
    return .{ .x = r.x - d, .y = r.y - d, .w = r.w + d * 2, .h = r.h + d * 2 };
}

fn diffTree(old: ?*Node, new: ?*Node, out: *std.ArrayListUnmanaged(core.RectI), gpa: std.mem.Allocator, scale: f32) void {
    if (old == null and new == null) return;
    if (old == null) {
        out.append(gpa, outsetPx(new.?.abs, new.?.paint_outset, scale)) catch {};
        return;
    }
    if (new == null) {
        out.append(gpa, outsetPx(old.?.abs, old.?.paint_outset, scale)) catch {};
        return;
    }
    const o = old.?;
    const n = new.?;
    const moved = o.rect.x != n.rect.x or o.rect.y != n.rect.y or o.rect.w != n.rect.w or o.rect.h != n.rect.h;
    if (moved) out.append(gpa, outsetPx(unionRects(o.abs, n.abs), @max(o.paint_outset, n.paint_outset), scale)) catch {};
    if (o.paint_key != n.paint_key) out.append(gpa, outsetPx(n.abs, n.paint_outset, scale)) catch {};
    var oc = o.first_child;
    var nc = n.first_child;
    while (oc != null or nc != null) {
        diffTree(oc, nc, out, gpa, scale);
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
        const key = AnimKey{ .id = node.id.raw(), .slot = slot };
        if (self.ui.anims.get(key)) |a| return a.current;
        return 0;
    }

    pub fn stateOf(self: *const PaintCtx, comptime T: type, node: *const Node) ?*const T {
        const key = StateKey{ .id = node.id.raw(), .type_id = core.hashBytes(0x9e3779b9, @typeName(T)) ^ @as(u64, @sizeOf(T)) *% 0x100000001b3 };
        if (self.ui.states.get(key)) |slot| return @ptrCast(@alignCast(slot.data));
        return null;
    }
};
