//! 输入类型与通用机制（08）。本模块不引用 ui 的任何类型。

const std = @import("std");
const core = @import("core.zig");
const platform = @import("platform.zig");
const layout = @import("layout.zig");
const theme = @import("theme.zig");

pub const Chord = struct { key: platform.VirtualKey, mods: platform.Mods = .{} };

pub const CommandId = enum(u32) { none = 0, _ };
pub const EditCommand = enum { undo, redo, cut, copy, paste, delete, select_all };

pub const ImeCaret = struct { caret: core.Rect, exclude: ?core.Rect = null };

pub const FocusReason = enum { pointer, tab, group, mnemonic, programmatic, restore, transfer, initial };
pub const ActivateSource = enum { default_button, cancel_button, mnemonic };
pub const DismissReason = enum {
    outside_click,
    escape,
    host_deactivated,
    host_moved,
    host_resized,
    host_hidden,
    host_destroyed,
    cancel_mode,
    capture_lost,
    dpi_changed,
    dialog_opened,
    programmatic,
};
pub const DismissInfo = struct { popup: core.WidgetId, reason: DismissReason };
pub const ContextRequest = struct { pos: core.Vec2, anchor: core.Rect, from_keyboard: bool };

pub const KeyGroups = packed struct {
    printable: bool = false,
    arrows: bool = false,
    home_end: bool = false,
    page: bool = false,
    enter: bool = false,
    space: bool = false,
    escape: bool = false,
    tab: bool = false,
    backspace_delete: bool = false,
    edit_chords: bool = false,
    function_keys: bool = false,
};

pub const KeyMask = struct {
    groups: KeyGroups = .{},
    extra: []const Chord = &.{},

    pub fn matches(self: KeyMask, key: platform.VirtualKey, mods: platform.Mods) bool {
        for (self.extra) |c| {
            if (c.key == key and c.mods.eql(mods)) return true;
        }
        const g = self.groups;
        if (g.printable and isPrintable(key) and !mods.ctrl and !mods.alt and !mods.win) return true;
        if (g.arrows and isArrow(key)) return true;
        if (g.home_end and (key == .home or key == .end)) return true;
        if (g.page and (key == .page_up or key == .page_down)) return true;
        if (g.enter and key == .enter) return true;
        if (g.space and key == .space) return true;
        if (g.escape and key == .escape) return true;
        if (g.tab and key == .tab) return true;
        if (g.backspace_delete and (key == .backspace or key == .delete)) return true;
        if (g.function_keys and isFunction(key)) return true;
        if (g.edit_chords and mods.ctrl and (key == .a or key == .c or key == .v or key == .x or key == .z or key == .y or key == .insert)) return true;
        if (g.edit_chords and mods.shift and (key == .insert or key == .delete)) return true;
        return false;
    }
};

pub const Sense = packed struct { hover: bool = true, click: bool = false, drag: bool = false, wheel: bool = false, context: bool = false };
pub const WheelCaps = packed struct { up: bool = false, down: bool = false, left: bool = false, right: bool = false, zoom: bool = false };
pub const EditCaps = packed struct { undo: bool = false, redo: bool = false, cut: bool = false, copy: bool = false, paste: bool = false, delete: bool = false, select_all: bool = false };

pub const InteractOpts = struct {
    sense: Sense = .{},
    cursor: platform.CursorShape = .arrow,
    take_focus_on_click: bool = true,
    text_input: bool = false,
    preempt: KeyMask = .{},
    handles: KeyMask = .{},
    wheel_caps: WheelCaps = .{},
    edit: EditCaps = .{},
    reveal_target: bool = false,
};

pub const Interaction = struct {
    hovered: bool = false,
    hovered_within: bool = false,
    pressed: bool = false,
    captured: bool = false,
    dragging: bool = false,
    focused: bool = false,
    focus_visible: bool = false,
    disabled: bool = false,
    pointer: ?core.Vec2 = null,
    press_origin: ?core.Vec2 = null,
    drag_delta: core.Vec2 = .{},
    clicked: bool = false,
    click_count: u8 = 0,
    click_button: platform.MouseButton = .left,
    double_clicked: bool = false,
    triple_clicked: bool = false,
    right_clicked: bool = false,
    middle_clicked: bool = false,
    context_menu: ?ContextRequest = null,
    drag_started: bool = false,
    drag_ended: bool = false,
    drag_cancelled: bool = false,
    activated: ?ActivateSource = null,
    focus_gained: ?FocusReason = null,
    focus_lost: bool = false,
    wheel: core.Vec2 = .{},
    popup_dismissed: ?DismissInfo = null,
};

pub const NodeEvent = union(enum) {
    pointer_move: struct { pos: core.Vec2, mods: platform.Mods },
    press: struct { button: platform.MouseButton, pos: core.Vec2, mods: platform.Mods, clicks: u8 },
    release: struct { button: platform.MouseButton, pos: core.Vec2, mods: platform.Mods, inside: bool },
    click: struct { button: platform.MouseButton, pos: core.Vec2, mods: platform.Mods, count: u8 },
    drag_start: struct { pos: core.Vec2 },
    drag_move: struct { pos: core.Vec2, delta: core.Vec2 },
    drag_end: struct { cancelled: bool },
    wheel: struct { delta: core.Vec2, page: bool, mods: platform.Mods, pos: core.Vec2 },
    key_down: struct { key: platform.VirtualKey, mods: platform.Mods, repeat: bool },
    key_up: struct { key: platform.VirtualKey, mods: platform.Mods },
    char: u21,
    ime_start,
    ime_update: struct { text: []const u8, cursor: usize, segments: []const platform.ImeSegment },
    ime_commit: []const u8,
    ime_end,
    focus_gained: FocusReason,
    focus_lost,
    context_menu: ContextRequest,
    reveal: core.Rect,
    activate: ActivateSource,
    activate_menu_bar,
    popup_dismissed: DismissInfo,
    edit_command: EditCommand,
    dropped: DropState,
};

pub const GroupOrientation = enum { horizontal, vertical, both };
pub const GroupSpec = struct { orientation: GroupOrientation, wrap: bool = true, home_end: bool = true, current: core.WidgetId = .none };
pub const ScopeSpec = struct { default_button: core.WidgetId = .none, cancel_button: core.WidgetId = .none, initial_focus: core.WidgetId = .none, trap_tab: bool = false };

pub const MnemonicAction = enum { activate, focus, focus_next };
pub const Mnemonic = struct {
    text: []const u8,
    underline: ?struct { start: u32, len: u32 } = null,
    key: ?u21 = null,
};

/// 解析标签中的助记符语法（REQ-INPUT-046）。返回的显示文本由调用方分配。
pub fn parseMnemonic(arena: std.mem.Allocator, label: []const u8) Mnemonic {
    var out = std.ArrayListUnmanaged(u8).empty;
    out.ensureTotalCapacity(arena, label.len) catch return .{ .text = label };
    var i: usize = 0;
    var marked_start: ?u32 = null;
    var marked_key: ?u21 = null;
    while (i < label.len) {
        if (label[i] == '&' and i + 1 < label.len) {
            if (label[i + 1] == '&') {
                out.append(arena, '&') catch {};
                i += 2;
                continue;
            }
            const r = core.nextCodepoint(label, i + 1);
            if (marked_start == null) {
                marked_start = @intCast(out.items.len);
                marked_key = r.cp;
            }
            out.appendSlice(arena, label[i + 1 .. i + 1 + r.len]) catch {};
            i += 1 + r.len;
            continue;
        }
        if (label[i] == '&' and i + 1 == label.len) {
            i += 1;
            continue;
        }
        out.append(arena, label[i]) catch {};
        i += 1;
    }
    return .{
        .text = out.items,
        .underline = if (marked_start) |s| .{ .start = s, .len = 1 } else null,
        .key = marked_key,
    };
}

pub const PopupKind = enum { menu, dropdown, context_menu, autocomplete, tooltip };
pub const KeyboardMode = enum { grab, passive };
pub const PopupSpec = struct {
    kind: PopupKind,
    anchor: core.Rect,
    anchor_id: core.WidgetId = .none,
    placement: layout.Placement = .{},
    gap: theme.Gap = .none,
    match_anchor_width: bool = false,
    min_width: f32 = 0,
    max_height: ?f32 = null,
    light_dismiss: bool = true,
    close_on_escape: bool = true,
    close_on_host_change: bool = true,
    keyboard: KeyboardMode = .grab,
    owner: core.WidgetId = .none,
    parent_popup: core.WidgetId = .none,

    pub fn defaults(kind: PopupKind, anchor: core.Rect) PopupSpec {
        return .{
            .kind = kind,
            .anchor = anchor,
            .light_dismiss = kind != .tooltip,
            .close_on_escape = kind != .tooltip,
            .keyboard = if (kind == .menu or kind == .dropdown or kind == .context_menu) .grab else .passive,
        };
    }
};

pub const HoverDelay = enum { menu, tooltip };

pub const DragPayload = struct { kind: u32, data: u64 = 0, ptr: ?*const anyopaque = null, external: ?*anyopaque = null };
pub const DragInfo = struct { source: core.WidgetId, payload: DragPayload, pos: core.Vec2, over: core.WidgetId };
pub const DropAccept = struct { kinds: []const u32 = &.{}, external_files: bool = false, external_text: bool = false };
pub const DropState = struct { over: bool, acceptable: bool, pos: core.Vec2, dropped: bool, payload: ?DragPayload, effect: platform.DropEffect };

pub const ShortcutHit = struct { command: CommandId, enabled: bool };
pub const ShortcutSource = struct {
    ctx: *anyopaque,
    lookup: *const fn (ctx: *anyopaque, chord: Chord) ?ShortcutHit,
    invoke: *const fn (ctx: *anyopaque, command: CommandId) void,
};

pub fn isArrow(k: platform.VirtualKey) bool {
    return k == .left or k == .right or k == .up or k == .down;
}

pub fn isFunction(k: platform.VirtualKey) bool {
    const v = @backingInt(k);
    return v >= 0x70 and v <= 0x87;
}

pub fn isPrintable(k: platform.VirtualKey) bool {
    const v = @backingInt(k);
    if (v >= 0x41 and v <= 0x5A) return true;
    if (v >= 0x30 and v <= 0x39) return true;
    if (v >= 0x60 and v <= 0x69) return true;
    if (v >= 0xBA and v <= 0xDF) return true;
    return k == .space;
}

pub fn keyToChar(k: platform.VirtualKey, mods: platform.Mods) ?u21 {
    const v = @backingInt(k);
    if (v >= 0x41 and v <= 0x5A) {
        const base: u21 = @intCast('a' + (v - 0x41));
        if (mods.shift) return @intCast('A' + (v - 0x41));
        return base;
    }
    if (v >= 0x30 and v <= 0x39) return @intCast('0' + (v - 0x30));
    return switch (k) {
        .space => ' ',
        .oem_period => '.',
        .oem_comma => ',',
        .oem_minus => '-',
        .oem_plus => '+',
        .oem_1 => ';',
        .oem_2 => '/',
        .oem_3 => '`',
        .oem_4 => '[',
        .oem_5 => '\\',
        .oem_6 => ']',
        .oem_7 => '\'',
        else => null,
    };
}

test "parse mnemonic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const m = parseMnemonic(arena.allocator(), "保存(&S)");
    try std.testing.expectEqualStrings("保存(S)", m.text);
    try std.testing.expectEqual(@as(u21, 'S'), m.key.?);
}
