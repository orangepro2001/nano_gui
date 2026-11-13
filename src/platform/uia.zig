//! UI Automation 提供者骨架（M6）。
//!
//! 与平台无关的部分先固定：控件角色、模式、名称/值来源与节点遍历接口。
//! Win32 后端在 `WM_GETOBJECT` 时把该提供者桥接到 UIA COM；当前 Linux 宿主
//! 使用同一接口做单元测试与调试快照。

const std = @import("std");
const core = @import("../core.zig");

pub const ControlType = enum {
    button,
    checkbox,
    radio_button,
    switch_,
    slider,
    progress,
    edit,
    text,
    list,
    list_item,
    tree,
    tree_item,
    table,
    data_grid,
    data_item,
    header,
    header_item,
    menu,
    menu_item,
    dialog,
    tooltip,
    custom,
};

pub const SortDirection = enum { none, ascending, descending };
pub const ExpandState = enum { collapsed, expanded, leaf_node };

pub const Pattern = enum {
    invoke,
    toggle,
    value,
    selection,
    selection_item,
    scroll,
    scroll_item,
    expand_collapse,
    grid,
    grid_item,
    table,
    table_item,
    range_value,
    text,
};

pub const Node = struct {
    id: core.WidgetId,
    control_type: ControlType = .custom,
    name: []const u8 = "",
    value: []const u8 = "",
    enabled: bool = true,
    focused: bool = false,
    selected: bool = false,
    expanded: ?bool = null,
    patterns: []const Pattern = &.{},
    parent: core.WidgetId = .none,
    can_select_multiple: bool = false,
    selection_required: bool = false,
    row_count: usize = 0,
    column_count: usize = 0,
    row_major: bool = true,
    level: u16 = 0,
    expand_state: ?ExpandState = null,
    sort_direction: ?SortDirection = null,
    row: ?usize = null,
    column: ?u16 = null,
    row_span: u16 = 1,
    column_span: u16 = 1,
};

pub const Provider = struct {
    ctx: *anyopaque,
    root: *const fn (ctx: *anyopaque) Node,
    children: *const fn (ctx: *anyopaque, id: core.WidgetId, out: *std.ArrayListUnmanaged(Node)) void,
    invoke: ?*const fn (ctx: *anyopaque, id: core.WidgetId) void = null,
    setValue: ?*const fn (ctx: *anyopaque, id: core.WidgetId, text: []const u8) bool = null,
};

pub const Registry = struct {
    allocator: std.mem.Allocator,
    provider: ?Provider = null,
    enabled: bool = false,

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Registry) void {
        self.* = undefined;
    }
    pub fn set(self: *Registry, provider: ?Provider) void {
        self.provider = provider;
        self.enabled = provider != null;
    }
    pub fn isEnabled(self: *const Registry) bool {
        return self.enabled;
    }
    pub fn roleName(t: ControlType) []const u8 {
        return @tagName(t);
    }
    pub fn patternName(p: Pattern) []const u8 {
        return @tagName(p);
    }
};

pub const uia_root_object_id: isize = -25;

var global_provider: ?Provider = null;
var uia_active: bool = false;

/// 注册或清除平台级 UIA 提供者（REQ-PLAT-080）。线程：界面线程。
pub fn setProvider(provider: ?Provider) void {
    global_provider = provider;
    uia_active = provider != null;
}

/// 查询当前是否已收到 UIA 查询或注册提供者（AC-PLAT-047）。线程：界面线程。
pub fn isEnabled() bool {
    return uia_active or global_provider != null;
}

/// 响应 `WM_GETOBJECT`：若为 `UiaRootObjectId` 则激活 UIA 并返回 true（AC-PLAT-047）。线程：界面线程。
pub fn handleGetObject(obj_id: isize) bool {
    if (obj_id != uia_root_object_id) return false;
    uia_active = true;
    return global_provider != null;
}

test "uia role/pattern names are stable" {
    try std.testing.expectEqualStrings("button", Registry.roleName(.button));
    try std.testing.expectEqualStrings("invoke", Registry.patternName(.invoke));
}
