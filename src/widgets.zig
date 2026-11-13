//! 内建控件。控件只通过 ui/layout/input/theme/gfx/text 的公开接口实现（REQ-ARCH-005）。

const std = @import("std");
const core = @import("core.zig");
const platform = @import("platform.zig");
const gfx = @import("gfx.zig");
const text = @import("text.zig");
const uia = @import("platform.zig").uia;
const theme = @import("theme.zig");
const layout = @import("layout.zig");
const input = @import("input.zig");
const ui = @import("ui.zig");

const Ui = ui.Ui;
const Theme = theme.Theme;
const PaintCtx = ui.PaintCtx;
const Node = ui.Node;

pub const ControlSize = enum { sm, md, lg };

fn heightFor(t: *const Theme, size: ControlSize) f32 {
    return switch (size) {
        .sm => t.metric(.control_h_sm),
        .md => t.metric(.control_h),
        .lg => t.metric(.control_h_lg),
    };
}

fn applyItem(p: *layout.Params, item: layout.ItemOptions) void {
    if (item.main) |v| p.main = v;
    if (item.cross) |v| p.cross = v;
    if (item.main_min) |v| p.main_min = v;
    if (item.main_max) |v| p.main_max = v;
    if (item.cross_min) |v| p.cross_min = v;
    if (item.cross_max) |v| p.cross_max = v;
    if (item.self_align) |v| p.self_align = v;
}

fn makeLayout(ui_ptr: *Ui, s: []const u8, style: text.Style, opts: text.LayoutOptions) *const text.Layout {
    return text.layout(s, style, ui_ptr.scale, opts);
}

fn styleFor(t: *const Theme, token: theme.FontToken) text.Style {
    return t.fonts.get(token);
}

fn hashStr(seed: u64, s: []const u8) u64 {
    return core.hashBytes(seed, s);
}

// ---------------------------------------------------------------------------
// 标签（label）
// ---------------------------------------------------------------------------

pub const LabelColor = enum { primary, secondary, disabled, danger, warning, success, info, on_accent };
pub const LabelVariant = enum { text, link };
pub const LabelWrap = enum { none, word };
pub const LabelStyle = enum { body, body_strong, small, title, mono };

pub const LabelOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    style: LabelStyle = .body,
    color: LabelColor = .primary,
    variant: LabelVariant = .text,
    wrap: LabelWrap = .none,
    max_lines: ?u32 = null,
    text_align: text.Align = .left,
    icon: ?theme.Icon = null,
    tooltip: ?[]const u8 = null,
    for_id: ?core.WidgetId = null,
    hit_passthrough: bool = false,
    layout: layout.ItemOptions = .{},
};

pub const LabelResult = struct {
    hovered: bool = false,
    pressed: bool = false,
    focused: bool = false,
    truncated: bool = false,
    clicked: bool = false,
    activated: ?input.ActivateSource = null,
};

const LabelProps = struct {
    label: []const u8,
    cl: *const text.Layout,
    color: LabelColor,
    variant: LabelVariant,
    icon: ?theme.Icon,
};

pub fn label(ui_ptr: *Ui, src: std.builtin.SourceLocation, label_text: []const u8, opts: LabelOptions) LabelResult {
    const id = ui_ptr.id(src, opts.key);
    const t = ui_ptr.theme_ptr;
    const style = switch (opts.style) {
        .body => styleFor(t, .body),
        .body_strong => styleFor(t, .body_strong),
        .small => styleFor(t, .small),
        .title => styleFor(t, .title),
        .mono => styleFor(t, .mono),
    };
    const l = makeLayout(ui_ptr, label_text, style, .{ .newlines = .as_space, .@"align" = opts.text_align, .max_lines = opts.max_lines, .wrap = if (opts.wrap == .word) .word else .none });
    var p = layout.Params{
        .kind = .leaf,
        .main = .fit,
        .cross = .fit,
        .content = .{ .size = .{ .x = l.size.w + (if (opts.icon != null) t.metric(.icon_sm) + t.metric(.gap_sm) else 0), .y = l.size.h }, .key = hashStr(0x1a2b3c, label_text) },
    };
    applyItem(&p, opts.layout);
    const props = ui_ptr.treeAlloc().create(LabelProps) catch @panic("nano_gui: props allocation failed");
    // REQ-ARCH-016：框架不保存调用方切片超过当前帧，标签文本复制进树竞技场。
    const owned_label = ui_ptr.treeAlloc().dupe(u8, label_text) catch @panic("nano_gui: props allocation failed");
    props.* = .{ .label = owned_label, .cl = l, .color = opts.color, .variant = opts.variant, .icon = opts.icon };
    const node = ui_ptr.leaf(id, .{ .layout = p, .flags = .{ .focusable = opts.variant == .link, .tab_stop = opts.variant == .link, .disabled = !opts.enabled, .hit_passthrough = opts.hit_passthrough }, .paint = paintLabel, .props = props, .paint_key = core.hashBytes(0x6611, label_text) ^ @backingInt(opts.variant) });
    node.src_file = src.file;
    node.src_line = src.line;
    if (opts.debug_name) |dn| node.debug_name = dn;

    var result = LabelResult{};
    if (opts.variant == .link and opts.enabled) {
        const it = ui_ptr.interact(id, .{ .sense = .{ .hover = true, .click = true }, .cursor = .hand });
        result.hovered = it.hovered;
        result.pressed = it.pressed;
        result.focused = it.focused;
        result.clicked = it.clicked;
        result.activated = it.activated;
    } else {
        const it = ui_ptr.interact(id, .{ .sense = .{ .hover = true } });
        result.hovered = it.hovered;
    }
    result.truncated = l.truncated;
    return result;
}

fn paintLabel(ctx: *PaintCtx, node: *const Node) void {
    const p: *const LabelProps = @ptrCast(@alignCast(node.props.?));
    const r = ctx.rect(node);
    const t = ctx.draw.theme;
    var color = switch (p.color) {
        .primary => t.color(.text_primary),
        .secondary => t.color(.text_secondary),
        .disabled => t.color(.text_disabled),
        .danger => t.color(.status_danger),
        .warning => t.color(.status_warning),
        .success => t.color(.status_success),
        .info => t.color(.status_info),
        .on_accent => t.color(.text_on_accent),
    };
    if (p.variant == .link) {
        color = t.color(.accent_text);
        if (ctx.visual(node).pressed) color = t.color(.accent_fill_pressed_top);
    }
    var x = r.x;
    if (p.icon) |icon| {
        drawIcon(ctx, icon, .{ .x = r.x, .y = r.y + (r.h - t.metric(.icon_sm)) * 0.5, .w = t.metric(.icon_sm), .h = t.metric(.icon_sm) }, color);
        x += t.metric(.icon_sm) + t.metric(.gap_sm);
    }
    ctx.draw.canvas.pushClip(r);
    text.draw(ctx.draw.canvas, p.cl, .{ .x = x, .y = r.y + (r.h - p.cl.size.h) * 0.5 }, color, .{});
    ctx.draw.canvas.popClip();
    if (p.variant == .link and ctx.visual(node).focused_visible) theme.drawFocusRing(&ctx.draw, r, .radius_control, ctx.visual(node));
}

// ---------------------------------------------------------------------------
// 按钮（button）
// ---------------------------------------------------------------------------

pub const ButtonVariant = enum { neutral, accent, quiet };

pub const ButtonOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    variant: ButtonVariant = .neutral,
    size: ControlSize = .md,
    icon: ?theme.Icon = null,
    checked: ?bool = null,
    tooltip: ?[]const u8 = null,
    layout: layout.ItemOptions = .{},
};

pub const ButtonResult = struct {
    hovered: bool = false,
    pressed: bool = false,
    focused: bool = false,
    clicked: bool = false,
    activated: ?input.ActivateSource = null,
};

const ButtonProps = struct {
    label: []const u8,
    bl: *const text.Layout,
    variant: ButtonVariant,
    size: ControlSize,
    icon: ?theme.Icon,
    checked: ?bool,
    enabled: bool,
};

const ButtonState = struct {
    armed_space: bool = false,
};

pub fn button(ui_ptr: *Ui, src: std.builtin.SourceLocation, label_text: []const u8, opts: ButtonOptions) ButtonResult {
    const id = ui_ptr.id(src, opts.key);
    const t = ui_ptr.theme_ptr;
    const style = styleFor(t, if (opts.variant == .accent) .body_strong else .body);
    const l = makeLayout(ui_ptr, label_text, style, .{ .newlines = .as_space });
    const h = heightFor(t, opts.size);
    const icon_w = if (opts.icon != null) t.metric(.icon_sm) + (if (label_text.len > 0) t.metric(.gap_sm) else 0) else 0;
    const min_w = if (label_text.len > 0) t.metric(.button_min_w) else h;
    var p = layout.Params{
        .kind = .leaf,
        .main = .fit,
        .cross = .fit,
        .content = .{ .size = .{ .x = @max(min_w, t.metric(.pad_control_x) * 2 + icon_w + l.size.w), .y = h }, .key = hashStr(0x77aa, label_text) ^ @as(u64, @backingInt(opts.size)) },
    };
    if (label_text.len == 0) p.content.size.x = h;
    applyItem(&p, opts.layout);
    const props = ui_ptr.treeAlloc().create(ButtonProps) catch @panic("nano_gui: props allocation failed");
    props.* = .{ .label = label_text, .bl = l, .variant = opts.variant, .size = opts.size, .icon = opts.icon, .checked = opts.checked, .enabled = opts.enabled };
    const node = ui_ptr.leaf(id, .{
        .layout = p,
        .flags = .{ .focusable = opts.enabled, .tab_stop = opts.variant != .quiet, .disabled = !opts.enabled },
        .paint = paintButton,
        .props = props,
        .paint_outset = t.metric(.focus_ring_w),
        .paint_key = core.hashBytes(0x77bb, label_text) ^ @as(u64, @backingInt(opts.variant)) ^ (@as(u64, 1) << 40) * @intFromBool(opts.checked orelse false),
    });
    node.src_file = src.file;
    node.src_line = src.line;
    if (opts.debug_name) |dn| node.debug_name = dn;

    var result = ButtonResult{};
    if (!opts.enabled) {
        _ = ui_ptr.interact(id, .{ .sense = .{ .hover = true } });
        return result;
    }
    const st = ui_ptr.state(ButtonState, id, .{});
    if (opts.variant != .quiet or true) {
        const it = ui_ptr.interact(id, .{
            .sense = .{ .hover = true, .click = true },
            .cursor = .arrow,
            .handles = .{ .groups = .{ .space = true, .enter = true } },
            .hover_anim = true,
        });
        _ = ui_ptr.animate(id, 0, if (it.hovered) 1 else 0, .{ .duration = .fast, .easing = .out, .level = .paint });
        result.hovered = it.hovered;
        result.pressed = it.pressed or st.armed_space;
        result.focused = it.focused;
        if (it.clicked) {
            result.clicked = true;
            result.activated = it.activated;
        }
        if (opts.tooltip) |tip| _ = tooltip(ui_ptr, @src(), id, tip, .{});
        for (ui_ptr.events(id)) |ev| {
            switch (ev) {
                .key_down => |k| {
                    if (k.key == .space and !k.repeat and it.focused) st.armed_space = true;
                    if (k.key == .enter and !k.repeat and it.focused) {
                        result.clicked = true;
                    }
                },
                .key_up => |k| {
                    if (k.key == .space and st.armed_space) {
                        st.armed_space = false;
                        result.clicked = true;
                    }
                },
                else => {},
            }
        }
    }
    return result;
}

fn paintButton(ctx: *PaintCtx, node: *const Node) void {
    const p: *const ButtonProps = @ptrCast(@alignCast(node.props.?));
    const r = ctx.rect(node);
    const t = ctx.draw.theme;
    var v = ctx.visual(node);
    v.hover_t = ctx.anim(node, 0);
    const checked = p.checked orelse false;
    if (checked and !v.pressed) v.pressed = true;
    theme.drawRaised(&ctx.draw, r, .radius_control, if (p.variant == .quiet) .neutral else if (p.variant == .accent) .accent else .neutral, v);
    var fg = if (p.variant == .accent) t.color(.text_on_accent) else if (p.variant == .quiet) t.color(.text_primary) else t.color(.text_primary);
    if (v.disabled) fg = t.color(.text_disabled);
    const content_w = (if (p.icon != null) t.metric(.icon_sm) + (if (p.label.len > 0) t.metric(.gap_sm) else 0) else 0) + p.bl.size.w;
    var x = r.x + (r.w - content_w) * 0.5;
    var y = r.y + (r.h - p.bl.size.h) * 0.5;
    if (v.pressed and !checked) y += 1.0 / ctx.draw.scale;
    ctx.draw.canvas.pushClip(r);
    if (p.icon) |icon| {
        drawIcon(ctx, icon, .{ .x = x, .y = r.y + (r.h - t.metric(.icon_sm)) * 0.5, .w = t.metric(.icon_sm), .h = t.metric(.icon_sm) }, fg);
        x += t.metric(.icon_sm) + (if (p.label.len > 0) t.metric(.gap_sm) else 0);
    }
    text.draw(ctx.draw.canvas, p.bl, .{ .x = x, .y = y }, fg, .{});
    ctx.draw.canvas.popClip();
}

// ---------------------------------------------------------------------------
// 复选框 / 单选框 / 开关（checkbox / radio / switch）
// ---------------------------------------------------------------------------

pub const CheckState = enum { off, on, mixed };

pub const CheckboxOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    size: ControlSize = .md,
    tooltip: ?[]const u8 = null,
    a11y_name: ?[]const u8 = null,
    layout: layout.ItemOptions = .{},
};
pub const CheckboxResult = struct {
    hovered: bool = false,
    pressed: bool = false,
    focused: bool = false,
    changed: bool = false,
    activated: ?input.ActivateSource = null,
};

const ToggleProps = struct {
    label: []const u8,
    tl: *const text.Layout,
    kind: enum { checkbox, radio, switch_box },
    checked: bool,
    mixed: bool = false,
};

fn toggleCommon(ui_ptr: *Ui, src: std.builtin.SourceLocation, label_text: []const u8, checked: bool, opts_key: ?ui.Key, debug_name: ?[]const u8, enabled: bool, kind: anytype) struct { id: core.WidgetId, it: input.Interaction, lit: bool } {
    const id = ui_ptr.id(src, opts_key);
    const t = ui_ptr.theme_ptr;
    const style = styleFor(t, .body);
    const l = makeLayout(ui_ptr, label_text, style, .{ .newlines = .as_space });
    const box = t.metric(.check_size);
    const gap = if (label_text.len > 0) t.metric(.gap_sm) else 0;
    const p = layout.Params{
        .kind = .leaf,
        .main = .fit,
        .cross = .fit,
        .content = .{ .size = .{ .x = box + gap + l.size.w, .y = t.metric(.control_h) }, .key = hashStr(0x99aa, label_text) },
    };
    const props = ui_ptr.treeAlloc().create(ToggleProps) catch @panic("nano_gui: props allocation failed");
    props.* = .{ .label = label_text, .tl = l, .kind = kind, .checked = checked };
    const node = ui_ptr.leaf(id, .{
        .layout = p,
        .flags = .{ .focusable = enabled, .disabled = !enabled },
        .paint = paintToggle,
        .props = props,
        .paint_outset = t.metric(.focus_ring_w),
        .paint_key = core.hashBytes(0x99bb, label_text) ^ @as(u64, @intFromBool(checked)),
    });
    node.src_file = src.file;
    node.src_line = src.line;
    if (debug_name) |dn| node.debug_name = dn;
    const it = ui_ptr.interact(id, .{ .sense = .{ .hover = true, .click = true }, .handles = .{ .groups = .{ .space = true, .enter = true } } });
    return .{ .id = id, .it = it, .lit = checked };
}

pub fn checkbox(ui_ptr: *Ui, src: std.builtin.SourceLocation, label_text: []const u8, value: *bool, opts: CheckboxOptions) CheckboxResult {
    const r = toggleCommon(ui_ptr, src, label_text, value.*, opts.key, opts.debug_name, opts.enabled, .checkbox);
    var result = CheckboxResult{ .hovered = r.it.hovered, .pressed = r.it.pressed, .focused = r.it.focused };
    if (!opts.enabled) return result;
    var flip = r.it.clicked;
    for (ui_ptr.events(r.id)) |ev| {
        switch (ev) {
            .key_down => |k| {
                if (k.key == .enter and !k.repeat and r.it.focused) flip = true;
            },
            else => {},
        }
    }
    if (flip) {
        value.* = !value.*;
        result.changed = true;
        result.activated = r.it.activated;
    }
    return result;
}

pub fn checkboxTri(ui_ptr: *Ui, src: std.builtin.SourceLocation, label_text: []const u8, value: *CheckState, opts: CheckboxOptions) CheckboxResult {
    const checked = value.* != .off;
    const r = toggleCommon(ui_ptr, src, label_text, checked, opts.key, opts.debug_name, opts.enabled, .checkbox);
    var result = CheckboxResult{ .hovered = r.it.hovered, .pressed = r.it.pressed, .focused = r.it.focused };
    if (opts.enabled and r.it.clicked) {
        value.* = switch (value.*) {
            .off => .on,
            .mixed => .on,
            .on => .off,
        };
        result.changed = true;
    }
    if (r.it.hovered) {}
    if (value.* == .mixed) {
        if (ui_ptr.getNode(r.id)) |n| {
            const p: *ToggleProps = @ptrCast(@alignCast(@constCast(n.props.?)));
            p.mixed = true;
        }
    }
    return result;
}

pub const RadioOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    size: ControlSize = .md,
    tooltip: ?[]const u8 = null,
    a11y_name: ?[]const u8 = null,
    layout: layout.ItemOptions = .{},
};
pub const RadioResult = struct {
    hovered: bool = false,
    pressed: bool = false,
    focused: bool = false,
    selected: bool = false,
    changed: bool = false,
    activated: ?input.ActivateSource = null,
};
pub const RadioGroupOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    direction: layout.Orientation = .vertical,
    gap: theme.Gap = .sm,
    layout: layout.ItemOptions = .{},
};

pub fn beginRadioGroup(ui_ptr: *Ui, src: std.builtin.SourceLocation, opts: RadioGroupOptions) core.WidgetId {
    const o = layout.ContainerOptions{
        .debug_name = opts.debug_name,
        .main = if (opts.direction == .vertical) .fit else .fit,
        .cross = .fit,
        .gap = opts.gap,
        .main_min = opts.layout.main_min orelse 0,
    };
    return if (opts.direction == .vertical) ui_ptr.beginColumn(src, o) else ui_ptr.beginRow(src, o);
}
pub fn endRadioGroup(ui_ptr: *Ui) void {
    ui_ptr.endColumn();
}

pub fn radio(ui_ptr: *Ui, src: std.builtin.SourceLocation, label_text: []const u8, value: anytype, this_value: anytype, opts: RadioOptions) RadioResult {
    const selected = value.* == this_value;
    const r = toggleCommon(ui_ptr, src, label_text, selected, opts.key, opts.debug_name, opts.enabled, .radio);
    var result = RadioResult{ .hovered = r.it.hovered, .pressed = r.it.pressed, .focused = r.it.focused, .selected = selected };
    if (opts.enabled and r.it.clicked) {
        value.* = this_value;
        result.changed = !selected;
        result.selected = true;
        result.activated = r.it.activated;
    }
    return result;
}

pub const SwitchStateText = struct { on: []const u8 = "开", off: []const u8 = "关" };
pub const SwitchOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    size: ControlSize = .md,
    state_text: ?SwitchStateText = null,
    tooltip: ?[]const u8 = null,
    a11y_name: ?[]const u8 = null,
    layout: layout.ItemOptions = .{},
};
pub const SwitchResult = struct {
    hovered: bool = false,
    pressed: bool = false,
    focused: bool = false,
    changed: bool = false,
    activated: ?input.ActivateSource = null,
};

pub fn switchBox(ui_ptr: *Ui, src: std.builtin.SourceLocation, label_text: []const u8, value: *bool, opts: SwitchOptions) SwitchResult {
    const id = ui_ptr.id(src, opts.key);
    const t = ui_ptr.theme_ptr;
    const style = styleFor(t, .body);
    const l = makeLayout(ui_ptr, label_text, style, .{ .newlines = .as_space });
    const sw = t.metric(.switch_w);
    const sh = t.metric(.switch_h);
    var p = layout.Params{
        .kind = .leaf,
        .main = .fit,
        .cross = .fit,
        .content = .{ .size = .{ .x = sw + (if (label_text.len > 0) t.metric(.gap_sm) + l.size.w else 0), .y = t.metric(.control_h) }, .key = hashStr(0xaa55, label_text) },
    };
    applyItem(&p, opts.layout);
    const props = ui_ptr.treeAlloc().create(ToggleProps) catch @panic("nano_gui: props allocation failed");
    props.* = .{ .label = label_text, .tl = l, .kind = .switch_box, .checked = value.* };
    const node = ui_ptr.leaf(id, .{
        .layout = p,
        .flags = .{ .focusable = opts.enabled, .disabled = !opts.enabled },
        .paint = paintToggle,
        .props = props,
        .paint_outset = t.metric(.focus_ring_w),
        .paint_key = core.hashBytes(0xaa56, label_text) ^ @as(u64, @intFromBool(value.*)),
    });
    node.src_file = src.file;
    node.src_line = src.line;
    if (opts.debug_name) |dn| node.debug_name = dn;
    const it = ui_ptr.interact(id, .{ .sense = .{ .hover = true, .click = true }, .handles = .{ .groups = .{ .space = true, .enter = true } } });
    var result = SwitchResult{ .hovered = it.hovered, .pressed = it.pressed, .focused = it.focused };
    if (opts.enabled and it.clicked) {
        value.* = !value.*;
        result.changed = true;
        result.activated = it.activated;
    }
    _ = sh;
    return result;
}

fn paintToggle(ctx: *PaintCtx, node: *const Node) void {
    const p: *const ToggleProps = @ptrCast(@alignCast(node.props.?));
    const r = ctx.rect(node);
    const t = ctx.draw.theme;
    var v = ctx.visual(node);
    const control_h = t.metric(.control_h);
    switch (p.kind) {
        .checkbox, .radio => {
            const box = t.metric(.check_size);
            const box_r = core.Rect{ .x = r.x, .y = r.y + (control_h - box) * 0.5, .w = box, .h = box };
            if (p.checked) {
                theme.drawRaised(&ctx.draw, box_r, .radius_control, .accent, .{ .hovered = v.hovered, .pressed = false, .focused_visible = false, .disabled = v.disabled, .hover_t = 1, .press_t = 0, .focus_t = 1 });
                theme.drawMark(&ctx.draw, if (p.mixed) .indeterminate else if (p.kind == .radio) .radio_dot else .check, box_r, .text_on_accent);
            } else {
                theme.drawSunken(&ctx.draw, box_r, .radius_control, v, false);
                if (p.kind == .radio and v.hovered) {
                    ctx.draw.canvas.fillRoundRect(.{ .x = box_r.x + box * 0.3, .y = box_r.y + box * 0.3, .w = box * 0.4, .h = box * 0.4 }, box, t.color(.border_control_hover));
                }
            }
            if (v.focused_visible) theme.drawFocusRing(&ctx.draw, box_r, .radius_control, v);
            if (p.label.len > 0) {
                const x = r.x + box + t.metric(.gap_sm);
                text.draw(ctx.draw.canvas, p.tl, .{ .x = x, .y = r.y + (r.h - p.tl.size.h) * 0.5 }, if (v.disabled) t.color(.text_disabled) else t.color(.text_primary), .{});
            }
        },
        .switch_box => {
            const sw = t.metric(.switch_w);
            const sh = t.metric(.switch_h);
            const track = core.Rect{ .x = r.x, .y = r.y + (r.h - sh) * 0.5, .w = sw, .h = sh };
            ctx.draw.canvas.fillRoundRect(track, t.metric(.radius_control), if (p.checked) t.color(.accent_fill_bottom) else t.color(.surface_track));
            ctx.draw.canvas.strokeRoundRect(track, t.metric(.radius_control), if (v.hovered) t.color(.border_control_hover) else t.color(.border_control), t.hairline(ctx.draw.scale));
            const hair = @as(f32, @floatFromInt(t.hairline(ctx.draw.scale)));
            const thumb_w = @max(1, sh - hair * 2);
            const thumb = core.Rect{ .x = if (p.checked) track.right() - thumb_w - hair else track.x + hair, .y = track.y + hair, .w = thumb_w, .h = thumb_w };
            ctx.draw.canvas.fillRoundRect(thumb, t.metric(.radius_mark), t.color(.surface_raised_hover_top));
            if (v.focused_visible) theme.drawFocusRing(&ctx.draw, track, .radius_control, v);
            if (p.label.len > 0) text.draw(ctx.draw.canvas, p.tl, .{ .x = r.x + sw + t.metric(.gap_sm), .y = r.y + (r.h - p.tl.size.h) * 0.5 }, if (v.disabled) t.color(.text_disabled) else t.color(.text_primary), .{});
        },
    }
    _ = &v;
}

// ---------------------------------------------------------------------------
// 滑条 / 进度条 / 分隔线 / 面板（slider / progress / separator / panel）
// ---------------------------------------------------------------------------

pub const SliderOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    orientation: layout.Orientation = .horizontal,
    min: f32 = 0,
    max: f32 = 1,
    step: f32 = 0,
    layout: layout.ItemOptions = .{},
};
pub const SliderResult = struct { hovered: bool = false, dragging: bool = false, focused: bool = false, changed: bool = false, value: f32 = 0 };

const SliderProps = struct { value: f32, min: f32, max: f32, orientation: layout.Orientation = .horizontal };

pub fn slider(ui_ptr: *Ui, src: std.builtin.SourceLocation, value: *f32, opts: SliderOptions) SliderResult {
    const id = ui_ptr.id(src, opts.key);
    const t = ui_ptr.theme_ptr;
    var p = layout.Params{
        .kind = .leaf,
        .main = .fit,
        .cross = .fit,
        .content = .{ .size = if (opts.orientation == .horizontal) .{ .x = 120, .y = t.metric(.control_h) } else .{ .x = t.metric(.control_h), .y = 80 } },
    };
    applyItem(&p, opts.layout);
    const props = ui_ptr.treeAlloc().create(SliderProps) catch @panic("nano_gui: props allocation failed");
    props.* = .{ .value = value.*, .min = opts.min, .max = opts.max, .orientation = opts.orientation };
    const node = ui_ptr.leaf(id, .{ .layout = p, .flags = .{ .focusable = opts.enabled }, .paint = paintSlider, .props = props, .paint_key = @as(u64, @as(u32, @bitCast(value.*))), .paint_outset = t.metric(.focus_ring_w) });
    node.src_file = src.file;
    node.src_line = src.line;
    if (opts.debug_name) |dn| node.debug_name = dn;
    const it = ui_ptr.interact(id, .{ .sense = .{ .hover = true, .click = true, .drag = true }, .handles = .{ .groups = .{ .arrows = true, .home_end = true } } });
    var result = SliderResult{ .hovered = it.hovered, .dragging = it.dragging, .focused = it.focused, .value = value.* };
    if (opts.enabled) {
        var changed = false;
        if ((it.clicked or it.dragging) and it.pointer != null) {
            const prev_abs = ui_ptr.getPrevNode(id).?.abs;
            const frac = if (opts.orientation == .horizontal)
                std.math.clamp(it.pointer.?.x / @max(1, @as(f32, @floatFromInt(prev_abs.w)) / ui_ptr.scale), 0, 1)
            else
                1.0 - std.math.clamp(it.pointer.?.y / @max(1, @as(f32, @floatFromInt(prev_abs.h)) / ui_ptr.scale), 0, 1);
            var nv = opts.min + (opts.max - opts.min) * frac;
            if (opts.step > 0) nv = opts.min + @round((nv - opts.min) / opts.step) * opts.step;
            value.* = std.math.clamp(nv, opts.min, opts.max);
            changed = true;
        }
        for (ui_ptr.events(id)) |ev| {
            switch (ev) {
                .key_down => |k| {
                    const step = if (opts.step > 0) opts.step else (opts.max - opts.min) / 20.0;
                    if (k.key == .left or k.key == .down) {
                        value.* = std.math.clamp(value.* - step, opts.min, opts.max);
                        changed = true;
                    } else if (k.key == .right or k.key == .up) {
                        value.* = std.math.clamp(value.* + step, opts.min, opts.max);
                        changed = true;
                    } else if (k.key == .home) {
                        value.* = opts.min;
                        changed = true;
                    } else if (k.key == .end) {
                        value.* = opts.max;
                        changed = true;
                    }
                },
                else => {},
            }
        }
        result.changed = changed;
        result.value = value.*;
    }
    return result;
}

fn paintSlider(ctx: *PaintCtx, node: *const Node) void {
    const p: *const SliderProps = @ptrCast(@alignCast(node.props.?));
    const r = ctx.rect(node);
    const t = ctx.draw.theme;
    const track_h = t.metric(.slider_track_h);
    const tw = t.metric(.slider_thumb_w);
    const th = t.metric(.slider_thumb_h);
    const frac = if (p.max > p.min) std.math.clamp((p.value - p.min) / (p.max - p.min), 0, 1) else 0;
    if (p.orientation == .vertical) {
        const track = core.Rect{ .x = r.x + (r.w - track_h) * 0.5, .y = r.y + th * 0.5, .w = track_h, .h = @max(1, r.h - th) };
        theme.drawTrack(&ctx.draw, track);
        if (frac > 0) theme.drawTrackFill(&ctx.draw, .{ .x = track.x, .y = track.y + track.h * (1 - frac), .w = track.w, .h = track.h * frac });
        const thumb = core.Rect{ .x = r.x + (r.w - tw) * 0.5, .y = track.y + track.h * (1 - frac) - th * 0.5, .w = tw, .h = th };
        theme.drawRaised(&ctx.draw, thumb, .radius_control, .neutral, .{ .hovered = ctx.visual(node).hovered, .pressed = ctx.visual(node).pressed, .focused_visible = ctx.visual(node).focused_visible, .hover_t = 1, .press_t = 0, .focus_t = 1 });
        if (ctx.visual(node).focused_visible) theme.drawFocusRing(&ctx.draw, thumb, .radius_control, ctx.visual(node));
        return;
    }
    const track = core.Rect{ .x = r.x + tw * 0.5, .y = r.y + (r.h - track_h) * 0.5, .w = @max(1, r.w - tw), .h = track_h };
    theme.drawTrack(&ctx.draw, track);
    if (frac > 0) theme.drawTrackFill(&ctx.draw, .{ .x = track.x, .y = track.y, .w = track.w * frac, .h = track.h });
    const thumb = core.Rect{ .x = track.x + track.w * frac - tw * 0.5, .y = r.y + (r.h - th) * 0.5, .w = tw, .h = th };
    theme.drawRaised(&ctx.draw, thumb, .radius_control, .neutral, .{ .hovered = ctx.visual(node).hovered, .pressed = ctx.visual(node).pressed, .focused_visible = ctx.visual(node).focused_visible, .hover_t = 1, .press_t = 0, .focus_t = 1 });
    if (ctx.visual(node).focused_visible) theme.drawFocusRing(&ctx.draw, thumb, .radius_control, ctx.visual(node));
}

pub const ProgressOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    value: f32 = 0,
    indeterminate: bool = false,
    layout: layout.ItemOptions = .{},
};

pub fn progress(ui_ptr: *Ui, src: std.builtin.SourceLocation, opts: ProgressOptions) void {
    const id = ui_ptr.id(src, opts.key);
    const t = ui_ptr.theme_ptr;
    var p = layout.Params{ .kind = .leaf, .main = .fit, .cross = .fit, .content = .{ .size = .{ .x = 120, .y = t.metric(.progress_h) } } };
    applyItem(&p, opts.layout);
    const node = ui_ptr.leaf(id, .{ .layout = p, .paint = paintProgress, .paint_key = @as(u64, @as(u32, @bitCast(opts.value))) ^ @as(u64, @intFromBool(opts.indeterminate)) });
    node.src_file = src.file;
    node.src_line = src.line;
    if (opts.debug_name) |dn| node.debug_name = dn;
    const state = ui_ptr.state(f32, id, opts.value);
    state.* = opts.value;
    _ = ui_ptr.interact(id, .{ .sense = .{ .hover = false } });
}

fn paintProgress(ctx: *PaintCtx, node: *const Node) void {
    const r = ctx.rect(node);
    const v = ctx.stateOf(f32, node) orelse return;
    theme.drawTrack(&ctx.draw, r);
    theme.drawTrackFill(&ctx.draw, .{ .x = r.x, .y = r.y, .w = r.w * std.math.clamp(v.*, 0, 1), .h = r.h });
}

pub const SeparatorOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    orientation: layout.Orientation = .horizontal,
    structural: bool = false,
    layout: layout.ItemOptions = .{},
};

pub fn separator(ui_ptr: *Ui, src: std.builtin.SourceLocation, opts: SeparatorOptions) void {
    const id = ui_ptr.id(src, opts.key);
    const t = ui_ptr.theme_ptr;
    var p = layout.Params{
        .kind = .leaf,
        .main = .fixedSize(1),
        .cross = if (opts.orientation == .horizontal) .fill else .fixedSize(t.metric(.control_h)),
    };
    applyItem(&p, opts.layout);
    const node = ui_ptr.leaf(id, .{ .layout = p, .paint = paintSeparator, .paint_key = @intFromBool(opts.structural) });
    node.src_file = src.file;
    node.src_line = src.line;
    if (opts.debug_name) |dn| node.debug_name = dn;
    _ = ui_ptr.interact(id, .{ .sense = .{ .hover = false } });
}

fn paintSeparator(ctx: *PaintCtx, node: *const Node) void {
    const r = ctx.rect(node);
    const structural = node.paint_key != 0;
    const t = ctx.draw.theme;
    ctx.draw.canvas.fillRect(.{ .x = r.x, .y = r.y, .w = r.w, .h = @max(1, r.h) }, t.color(if (structural) .border_strong else .border_subtle));
}

pub const PanelOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    padding: f32 = 8,
    gap: theme.Gap = .md,
    layout: layout.ItemOptions = .{},
};

pub fn beginPanel(ui_ptr: *Ui, src: std.builtin.SourceLocation, opts: PanelOptions) core.WidgetId {
    const t = ui_ptr.theme_ptr;
    var o = layout.ContainerOptions{
        .debug_name = opts.debug_name,
        .padding = core.Insets.all(opts.padding),
        .gap = opts.gap,
        .main = .fit,
        .cross = .fit,
        .clip = true,
    };
    if (opts.layout.main) |v| o.main = v;
    if (opts.layout.cross) |v| o.cross = v;
    if (opts.layout.main_min) |v| o.main_min = v;
    if (opts.layout.main_max) |v| o.main_max = v;
    if (opts.layout.cross_min) |v| o.cross_min = v;
    if (opts.layout.cross_max) |v| o.cross_max = v;
    if (opts.layout.self_align) |v| o.self_align = v;
    const id = ui_ptr.beginColumn(src, o);
    if (ui_ptr.getNode(id)) |n| {
        n.paint = paintPanel;
        n.paint_key = 1;
        n.src_file = src.file;
        n.src_line = src.line;
    }
    _ = t;
    return id;
}
pub fn endPanel(ui_ptr: *Ui) void {
    ui_ptr.endColumn();
}

fn paintPanel(ctx: *PaintCtx, node: *const Node) void {
    theme.drawPanel(&ctx.draw, ctx.rect(node), .radius_container);
}

pub const GroupBoxOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    title: ?[]const u8 = null,
    enabled: bool = true,
    padding: f32 = 8,
    gap: theme.Gap = .md,
    layout: layout.ItemOptions = .{},
};

pub const GroupHandle = struct { id: core.WidgetId };

pub fn beginGroupBox(ui_ptr: *Ui, src: std.builtin.SourceLocation, opts: GroupBoxOptions) GroupHandle {
    var o = layout.ContainerOptions{
        .debug_name = opts.debug_name,
        .padding = core.Insets.all(opts.padding + 4),
        .gap = opts.gap,
        .main = .{ .grow = 1 },
        .cross = .fit,
    };
    if (opts.layout.main) |v| o.main = v;
    if (opts.layout.cross) |v| o.cross = v;
    const id = ui_ptr.beginColumn(src, o);
    if (ui_ptr.getNode(id)) |n| {
        n.paint = paintPanel;
        n.paint_key = 2;
        n.src_file = src.file;
        n.src_line = src.line;
    }
    if (opts.title) |ttl| {
        _ = label(ui_ptr, src, ttl, .{ .key = ui.Key.str("gb-title"), .style = .body_strong, .color = .secondary });
    }
    return .{ .id = id };
}
pub fn endGroupBox(ui_ptr: *Ui) void {
    ui_ptr.endColumn();
}

// ---------------------------------------------------------------------------
// 图像 / 图标（image / icon）
// ---------------------------------------------------------------------------

pub const ImageOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    size: core.Vec2 = .{ .x = 20, .y = 20 },
    layout: layout.ItemOptions = .{},
};

pub fn image(ui_ptr: *Ui, src: std.builtin.SourceLocation, id_image: ?gfx.ImageId, opts: ImageOptions) void {
    const id = ui_ptr.id(src, opts.key);
    var p = layout.Params{ .kind = .leaf, .main = .fit, .cross = .fit, .content = .{ .size = opts.size } };
    applyItem(&p, opts.layout);
    const props = ui_ptr.treeAlloc().create(?gfx.ImageId) catch @panic("nano_gui: props allocation failed");
    props.* = id_image;
    const node = ui_ptr.leaf(id, .{ .layout = p, .paint = paintImage, .props = props });
    node.src_file = src.file;
    node.src_line = src.line;
    if (opts.debug_name) |dn| node.debug_name = dn;
    _ = ui_ptr.interact(id, .{ .sense = .{ .hover = false } });
}

/// 从文件加载图像的可恢复错误集（REQ-ARCH-019）：文件读取、解码与缓存插入的错误之并集。
pub const LoadImageError = std.Io.Dir.ReadFileAllocError || gfx.DecodeError || gfx.GfxError;

/// 读取并解码图像文件，插入图像缓存并返回句柄；文件不存在等环境错误以错误返回，
/// 不断言、不中止（REQ-CONV-013）。线程：界面线程（写图像缓存）。
pub fn loadImageFile(gpa: std.mem.Allocator, io: std.Io, path: []const u8) LoadImageError!gfx.ImageId {
    const key = gfx.ImageKey.fromPath(path);
    if (gfx.images.id(key)) |cached| return cached;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .unlimited);
    defer gpa.free(bytes);
    return gfx.images.loadSync(key, bytes);
}

const ImageFileState = struct {
    path_hash: u64 = 0,
    attempted: bool = false,
    image: ?gfx.ImageId = null,
};

/// 显示来自文件的图像（REQ-ARCH-018）：构建函数无需 `try`；加载失败时显示占位框，
/// 并对同一路径只记录一条 `warn` 日志。结果按控件 ID 缓存，路径变化时重新加载。
/// 线程：界面线程。
pub fn imageFile(ui_ptr: *Ui, src: std.builtin.SourceLocation, io: std.Io, path: []const u8, opts: ImageOptions) void {
    const id = ui_ptr.id(src, opts.key);
    const st = ui_ptr.state(ImageFileState, id, .{});
    const h = core.hashBytes(0x1f11e, path);
    if (!st.attempted or st.path_hash != h) {
        st.attempted = true;
        st.path_hash = h;
        st.image = loadImageFile(ui_ptr.gpa, io, path) catch |e| blk: {
            core.log.write(.warn, "widgets", "图像加载失败，显示占位框：{s}（{s}）", .{ path, @errorName(e) });
            break :blk null;
        };
    }
    image(ui_ptr, src, st.image, opts);
}

fn paintImage(ctx: *PaintCtx, node: *const Node) void {
    const p: *const ?gfx.ImageId = @ptrCast(@alignCast(node.props.?));
    const r = ctx.rect(node);
    if (p.*) |iid| {
        if (ctx.draw.canvas.drawImage(iid, r, .{})) return;
    }
    ctx.draw.canvas.strokeRect(r, ctx.draw.theme.color(.border_control_disabled), 1);
    const s = @min(r.w, r.h) * 0.5;
    ctx.draw.canvas.strokeLine(.{ .x = r.center().x - s * 0.5, .y = r.center().y + s * 0.3 }, .{ .x = r.center().x, .y = r.center().y - s * 0.3 }, ctx.draw.theme.color(.border_control_disabled), 1);
    ctx.draw.canvas.strokeLine(.{ .x = r.center().x, .y = r.center().y - s * 0.3 }, .{ .x = r.center().x + s * 0.5, .y = r.center().y + s * 0.3 }, ctx.draw.theme.color(.border_control_disabled), 1);
}

fn drawIcon(ctx: *PaintCtx, icon: theme.Icon, r: core.Rect, color: core.Color) void {
    _ = color;
    switch (icon) {
        .mark => |m| theme.drawMark(&ctx.draw, m, r, .text_primary),
        .image => |img| _ = ctx.draw.canvas.drawImage(img, r, .{}),
        .set => |s| {
            const key = gfx.images.pick(s, ctx.draw.scale);
            _ = gfx.images.request(key);
            if (gfx.images.id(key)) |img| {
                _ = ctx.draw.canvas.drawImage(img, r, .{});
            }
        },
    }
}

// ---------------------------------------------------------------------------
// 滚动视图（scroll view）
// ---------------------------------------------------------------------------

pub const ScrollViewOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    axes: layout.ScrollAxes = .vertical,
    bar_v: layout.BarPolicy = .auto,
    bar_h: layout.BarPolicy = .auto,
    focusable: bool = false,
    offset: ?*core.Vec2 = null,
    line_step: ?f32 = null,
    anchor_end: bool = false,
    reveal: ?core.Rect = null,
    report_viewport: bool = false,
    layout: layout.ItemOptions = .{},
};

pub const ScrollViewHandle = struct { id: core.WidgetId, offset: core.Vec2, viewport: ?core.Vec2, line: f32 };
pub const ScrollViewResult = struct {
    hovered: bool = false,
    focused: bool = false,
    offset: core.Vec2 = .{},
    max_offset: core.Vec2 = .{},
    viewport: core.Vec2 = .{},
    content: core.Vec2 = .{},
    scrolled: bool = false,
};

const ScrollState = struct { offset: core.Vec2 = .{} };
const ScrollProps = struct { axes: layout.ScrollAxes };

pub fn beginScrollView(ui_ptr: *Ui, src: std.builtin.SourceLocation, opts: ScrollViewOptions) ScrollViewHandle {
    const id = ui_ptr.id(src, opts.key);
    const t = ui_ptr.theme_ptr;
    const st = ui_ptr.stateSticky(ScrollState, id, .{});
    var off = if (opts.offset) |o| o.* else st.offset;
    const metrics = ui_ptr.scrollMetrics(id);
    if (metrics) |m| {
        if (opts.offset == null) {
            off = m.offset;
        }
    }
    var scrolled = false;
    if (opts.enabled) {
        const it = ui_ptr.interact(id, .{ .sense = .{ .hover = true, .click = false, .wheel = true }, .wheel_caps = .{ .up = true, .down = true, .left = true, .right = true }, .cursor = .arrow });
        for (ui_ptr.events(id)) |ev| {
            switch (ev) {
                .wheel => |w| {
                    const step = opts.line_step orelse t.metric(.row_h);
                    const sm = platform.metrics(ui_ptr.window);
                    const viewport = if (metrics) |m| m.viewport else core.Rect{ .w = step * 10, .h = step * 10 };
                    const vlines: f32 = switch (sm.wheel_lines) {
                        .lines => |n| @floatFromInt(n),
                        .page => @max(1, viewport.h / step - 1),
                    };
                    const hchars: f32 = switch (sm.wheel_chars) {
                        .lines => |n| @floatFromInt(n),
                        .page => @max(1, viewport.w / step - 1),
                    };
                    off.x -= w.delta.x * step * hchars;
                    off.y -= w.delta.y * step * vlines;
                    scrolled = true;
                },
                else => {},
            }
        }
        if (it.hovered) {}
    }
    if (scrolled) {
        if (opts.offset) |o| o.* = off else st.offset = off;
    }
    var o = layout.ContainerOptions{
        .debug_name = opts.debug_name,
        .main = .fit,
        .cross = .fit,
        .clip = true,
    };
    if (opts.layout.main) |v| o.main = v;
    if (opts.layout.cross) |v| o.cross = v;
    if (opts.layout.main_min) |v| o.main_min = v;
    if (opts.layout.main_max) |v| o.main_max = v;
    if (opts.layout.cross_min) |v| o.cross_min = v;
    if (opts.layout.cross_max) |v| o.cross_max = v;
    if (opts.layout.self_align) |v| o.self_align = v;
    _ = ui_ptr.beginScroll(src, o, .{ .axes = opts.axes, .bar_v = opts.bar_v, .bar_h = opts.bar_h, .offset = off, .anchor_end = opts.anchor_end, .reveal = opts.reveal });
    if (ui_ptr.getNode(id)) |n| {
        n.paint = paintScrollView;
        n.paint_key = 3;
        n.src_file = src.file;
        n.src_line = src.line;
    }
    const props = ui_ptr.treeAlloc().create(ScrollProps) catch @panic("nano_gui: props allocation failed");
    props.* = .{ .axes = opts.axes };
    if (ui_ptr.getNode(id)) |n| n.props = props;
    return .{ .id = id, .offset = off, .viewport = if (metrics) |m| .{ .x = m.viewport.w, .y = m.viewport.h } else null, .line = opts.line_step orelse t.metric(.row_h) };
}

pub fn endScrollView(ui_ptr: *Ui, handle: ScrollViewHandle) ScrollViewResult {
    ui_ptr.endScroll();
    var result = ScrollViewResult{};
    if (ui_ptr.scrollMetrics(handle.id)) |m| {
        result.offset = m.offset;
        result.max_offset = m.max_offset;
        result.viewport = .{ .x = m.viewport.w, .y = m.viewport.h };
        result.content = m.content;
    }
    if (ui_ptr.getPrevNode(handle.id)) |n| {
        result.hovered = n.interaction.hovered;
        result.focused = n.interaction.focused;
    }
    result.scrolled = true;
    return result;
}

fn paintScrollView(ctx: *PaintCtx, node: *const Node) void {
    const t = ctx.draw.theme;
    const r = ctx.rect(node);
    ctx.draw.canvas.fillRect(r, t.color(.surface_sunken));
    if (node.scroll_metrics) |m| {
        if (m.bar_v) |b| {
            const br = core.Rect{ .x = r.x + @as(f32, @floatFromInt(b.x)) / ctx.draw.scale, .y = r.y + @as(f32, @floatFromInt(b.y)) / ctx.draw.scale, .w = @as(f32, @floatFromInt(b.w)) / ctx.draw.scale, .h = @as(f32, @floatFromInt(b.h)) / ctx.draw.scale };
            ctx.draw.canvas.fillRect(br, t.color(.surface_track));
            const frac = if (m.content.y > 0) @min(1, m.viewport.h / m.content.y) else 1;
            const thumb_h = @max(t.metric(.scrollbar_thumb_min), br.h * frac);
            const off = if (m.max_offset.y > 0) m.offset.y / m.max_offset.y else 0;
            const th = core.Rect{ .x = br.x + 2, .y = br.y + (br.h - thumb_h) * off, .w = br.w - 4, .h = thumb_h };
            ctx.draw.canvas.fillRoundRect(th, 3, t.color(.border_control));
        }
        if (m.bar_h) |b| {
            const br = core.Rect{ .x = r.x + @as(f32, @floatFromInt(b.x)) / ctx.draw.scale, .y = r.y + @as(f32, @floatFromInt(b.y)) / ctx.draw.scale, .w = @as(f32, @floatFromInt(b.w)) / ctx.draw.scale, .h = @as(f32, @floatFromInt(b.h)) / ctx.draw.scale };
            ctx.draw.canvas.fillRect(br, t.color(.surface_track));
            const frac = if (m.content.x > 0) @min(1, m.viewport.w / m.content.x) else 1;
            const thumb_w = @max(t.metric(.scrollbar_thumb_min), br.w * frac);
            const off = if (m.max_offset.x > 0) m.offset.x / m.max_offset.x else 0;
            const th = core.Rect{ .x = br.x + (br.w - thumb_w) * off, .y = br.y + 2, .w = thumb_w, .h = br.h - 4 };
            ctx.draw.canvas.fillRoundRect(th, 3, t.color(.border_control));
        }
    }
}

// ---------------------------------------------------------------------------
// 分割器（splitter）
// ---------------------------------------------------------------------------

pub const SplitterOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    orientation: layout.Orientation = .horizontal,
    default_pos: layout.SplitPos = .{ .ratio = 0.5 },
    pos: ?*layout.SplitPos = null,
    min_first: f32 = 0,
    min_second: f32 = 0,
    persist: ?[]const u8 = null,
    layout: layout.ItemOptions = .{},
};
pub const SplitterResult = struct {
    hovered: bool = false,
    dragging: bool = false,
    focused: bool = false,
    pos: layout.SplitPos = .{ .ratio = 0.5 },
    first: f32 = 0,
    moved: bool = false,
    committed: bool = false,
};

const SplitterState = struct { pos: layout.SplitPos = .{ .ratio = 0.5 } };
const SplitterProps = struct { orientation: layout.Orientation };

pub fn beginSplitter(ui_ptr: *Ui, src: std.builtin.SourceLocation, opts: SplitterOptions) core.WidgetId {
    const id = ui_ptr.id(src, opts.key);
    const st = ui_ptr.stateSticky(SplitterState, id, .{ .pos = opts.default_pos });
    var pos = if (opts.pos) |p| p.* else st.pos;
    var o = layout.ContainerOptions{ .debug_name = opts.debug_name, .main = .{ .grow = 1 }, .cross = .fill };
    if (opts.layout.main) |v| o.main = v;
    if (opts.layout.cross) |v| o.cross = v;
    if (opts.layout.main_min) |v| o.main_min = v;
    if (opts.layout.main_max) |v| o.main_max = v;
    if (opts.layout.cross_min) |v| o.cross_min = v;
    if (opts.layout.cross_max) |v| o.cross_max = v;
    if (opts.layout.self_align) |v| o.self_align = v;
    _ = ui_ptr.beginSplitter(src, o, .{ .orientation = opts.orientation, .pos = pos, .min_first = opts.min_first, .min_second = opts.min_second });
    const props = ui_ptr.treeAlloc().create(SplitterProps) catch @panic("nano_gui: props allocation failed");
    props.* = .{ .orientation = opts.orientation };
    if (ui_ptr.getNode(id)) |n| {
        n.paint = paintSplitter;
        n.props = props;
        n.paint_key = 4;
        n.src_file = src.file;
        n.src_line = src.line;
    }
    _ = &pos;
    return id;
}

pub fn endSplitter(ui_ptr: *Ui, id: core.WidgetId) SplitterResult {
    ui_ptr.endSplitter();
    var result = SplitterResult{};
    if (ui_ptr.splitMetrics(id)) |m| result.first = @as(f32, @floatFromInt(m.first_px)) / ui_ptr.scale;
    if (ui_ptr.getPrevNode(id)) |n| {
        result.hovered = n.interaction.hovered;
        result.dragging = n.interaction.dragging;
        result.focused = n.interaction.focused;
    }
    if (ui_ptr.getNode(id)) |n| {
        const p: *const SplitterProps = @ptrCast(@alignCast(n.props.?));
        _ = p;
    }
    return result;
}

fn paintSplitter(ctx: *PaintCtx, node: *const Node) void {
    const r = ctx.rect(node);
    const t = ctx.draw.theme;
    const m = node.split_metrics orelse return;
    const d = core.Rect{ .x = r.x + @as(f32, @floatFromInt(m.divider.x)) / ctx.draw.scale, .y = r.y + @as(f32, @floatFromInt(m.divider.y)) / ctx.draw.scale, .w = @as(f32, @floatFromInt(m.divider.w)) / ctx.draw.scale, .h = @as(f32, @floatFromInt(m.divider.h)) / ctx.draw.scale };
    const p: *const SplitterProps = @ptrCast(@alignCast(node.props.?));
    if (p.orientation == .horizontal) {
        ctx.draw.canvas.fillRect(.{ .x = d.x + (d.w - 1) * 0.5, .y = d.y, .w = 1, .h = d.h }, t.color(.border_subtle));
    } else {
        ctx.draw.canvas.fillRect(.{ .x = d.x, .y = d.y + (d.h - 1) * 0.5, .w = d.w, .h = 1 }, t.color(.border_subtle));
    }
}

// ---------------------------------------------------------------------------
// 标签页 / 工具栏 / 状态栏（tabs / toolbar / status bar）
// ---------------------------------------------------------------------------

pub const TabsOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    items: []const []const u8,
    selected: *usize,
    layout: layout.ItemOptions = .{},
};
pub const TabsResult = struct { changed: bool = false, selected: usize = 0 };
const TabsProps = struct { items: []const []const u8, widths: []const f32, selected: usize };

pub fn tabs(ui_ptr: *Ui, src: std.builtin.SourceLocation, opts: TabsOptions) TabsResult {
    const id = ui_ptr.id(src, opts.key);
    const t = ui_ptr.theme_ptr;
    const style = styleFor(t, .body);
    var total_w: f32 = 0;
    const widths = ui_ptr.treeAlloc().alloc(f32, opts.items.len) catch @panic("nano_gui: tabs alloc failed");
    for (opts.items, 0..) |it, i| {
        widths[i] = text.measure(it, style, ui_ptr.scale, .{}).w + t.metric(.pad_item_x) * 2;
        total_w += widths[i];
    }
    var p = layout.Params{ .kind = .leaf, .main = .fit, .cross = .fit, .content = .{ .size = .{ .x = total_w, .y = t.metric(.header_h) } } };
    applyItem(&p, opts.layout);
    const props = ui_ptr.treeAlloc().create(TabsProps) catch @panic("nano_gui: props allocation failed");
    const copy = ui_ptr.treeAlloc().dupe([]const u8, opts.items) catch @panic("nano_gui: tabs copy failed");
    props.* = .{ .items = copy, .widths = widths, .selected = opts.selected.* };
    const node = ui_ptr.leaf(id, .{ .layout = p, .paint = paintTabs, .props = props, .paint_key = @intCast(opts.selected.*) });
    node.src_file = src.file;
    node.src_line = src.line;
    if (opts.debug_name) |dn| node.debug_name = dn;
    const it = ui_ptr.interact(id, .{ .sense = .{ .hover = true, .click = true } });
    var result = TabsResult{ .selected = opts.selected.* };
    if (it.clicked) {
        if (it.pointer) |pt| {
            var x: f32 = 0;
            for (widths, 0..) |w, i| {
                if (pt.x >= x and pt.x < x + w) {
                    if (opts.selected.* != i) {
                        opts.selected.* = i;
                        result.changed = true;
                    }
                    result.selected = i;
                    break;
                }
                x += w;
            }
        }
    }
    return result;
}

fn paintTabs(ctx: *PaintCtx, node: *const Node) void {
    const p: *const TabsProps = @ptrCast(@alignCast(node.props.?));
    const r = ctx.rect(node);
    const t = ctx.draw.theme;
    ctx.draw.canvas.fillRect(r, t.color(.surface_panel));
    var x = r.x;
    for (p.items, 0..) |it, i| {
        const w = p.widths[i];
        const rr = core.Rect{ .x = x, .y = r.y, .w = w, .h = r.h };
        if (i == p.selected) {
            ctx.draw.canvas.fillRect(rr, t.color(.surface_panel));
            ctx.draw.canvas.fillRect(.{ .x = x, .y = r.y + 1, .w = w, .h = t.metric(.tab_indicator_h) }, t.color(.accent_mark));
        }
        const font = if (i == p.selected) t.fonts.get(.body_strong) else t.fonts.get(.body);
        const l = text.layout(it, font, ctx.draw.scale, .{});
        text.draw(ctx.draw.canvas, l, .{ .x = x + t.metric(.pad_item_x), .y = r.y + (r.h - l.size.h) * 0.5 }, t.color(if (i == p.selected) .text_primary else .text_secondary), .{});
        x += w;
    }
    ctx.draw.canvas.fillRect(.{ .x = r.x, .y = r.bottom() - 1, .w = r.w, .h = 1 }, t.color(.border_strong));
}

pub const ToolbarOptions = struct { key: ?ui.Key = null, debug_name: ?[]const u8 = null, gap: theme.Gap = .xs, padding: f32 = 4 };
pub fn beginToolbar(ui_ptr: *Ui, src: std.builtin.SourceLocation, opts: ToolbarOptions) core.WidgetId {
    const h = ui_ptr.theme_ptr.metric(.control_h) + ui_ptr.theme_ptr.metric(.gap_xs) * 2;
    const o = layout.ContainerOptions{ .debug_name = opts.debug_name, .main = .fixedSize(h), .cross = .fill, .padding = core.Insets.all(opts.padding), .gap = opts.gap, .cross_align = .center };
    const id = ui_ptr.beginRow(src, o);
    if (ui_ptr.getNode(id)) |n| {
        n.paint = paintToolbar;
        n.paint_key = 5;
    }
    return id;
}
pub fn endToolbar(ui_ptr: *Ui) void {
    ui_ptr.endRow();
}
fn paintToolbar(ctx: *PaintCtx, node: *const Node) void {
    theme.drawPanel(&ctx.draw, ctx.rect(node), .radius_container);
}

pub const StatusBarOptions = struct { key: ?ui.Key = null, debug_name: ?[]const u8 = null, gap: theme.Gap = .md, padding: f32 = 6 };
pub fn beginStatusBar(ui_ptr: *Ui, src: std.builtin.SourceLocation, opts: StatusBarOptions) core.WidgetId {
    const o = layout.ContainerOptions{ .debug_name = opts.debug_name, .main = .fixedSize(ui_ptr.theme_ptr.metric(.control_h_sm)), .cross = .fill, .padding = core.Insets.symmetric(opts.padding, ui_ptr.theme_ptr.metric(.gap_xs)), .gap = opts.gap, .cross_align = .center };
    const id = ui_ptr.beginRow(src, o);
    if (ui_ptr.getNode(id)) |n| {
        n.paint = paintToolbar;
        n.paint_key = 6;
    }
    return id;
}
pub fn endStatusBar(ui_ptr: *Ui) void {
    ui_ptr.endRow();
}

// ---------------------------------------------------------------------------
// 文本输入框（text input）
// ---------------------------------------------------------------------------

pub const TextBuf = struct {
    data: std.ArrayListUnmanaged(u8) = .empty,
    serial_value: u64,
    revision_value: u32 = 0,
    allocator: std.mem.Allocator,

    var next_serial: u64 = 1;

    pub fn init(allocator: std.mem.Allocator) TextBuf {
        return .{ .allocator = allocator, .serial_value = next_serial };
    }
    pub fn initFrom(allocator: std.mem.Allocator, bytes: []const u8) error{OutOfMemory}!TextBuf {
        var b = TextBuf.init(allocator);
        errdefer b.deinit();
        try b.data.appendSlice(allocator, bytes);
        next_serial += 1;
        return b;
    }
    pub fn deinit(self: *TextBuf) void {
        self.data.deinit(self.allocator);
    }
    pub fn slice(self: *const TextBuf) []const u8 {
        return self.data.items;
    }
    pub fn len(self: *const TextBuf) usize {
        return self.data.items.len;
    }
    pub fn set(self: *TextBuf, bytes: []const u8) error{OutOfMemory}!void {
        if (std.mem.eql(u8, self.data.items, bytes)) return;
        self.data.clearRetainingCapacity();
        try self.data.appendSlice(self.allocator, bytes);
        self.revision_value +%= 1;
    }
    pub fn replace(self: *TextBuf, start: usize, end: usize, bytes: []const u8) error{OutOfMemory}!void {
        self.data.replaceRange(self.allocator, start, end - start, bytes) catch |e| return e;
        self.revision_value +%= 1;
    }
    pub fn clear(self: *TextBuf) void {
        self.data.clearRetainingCapacity();
        self.revision_value +%= 1;
    }
    pub fn serial(self: *const TextBuf) u64 {
        return self.serial_value;
    }
    pub fn revision(self: *const TextBuf) u32 {
        return self.revision_value;
    }
};

pub const TextInputOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    read_only: bool = false,
    password: bool = false,
    invalid: bool = false,
    clear_button: bool = false,
    max_len: ?u32 = null,
    placeholder: []const u8 = "",
    tooltip: ?[]const u8 = null,
    layout: layout.ItemOptions = .{},
};

pub const TextInputResult = struct {
    hovered: bool = false,
    pressed: bool = false,
    focused: bool = false,
    changed: bool = false,
    committed: bool = false,
    cancelled: bool = false,
};

const TextInputState = struct {
    caret: usize = 0,
    anchor: usize = 0,
};

const TextInputProps = struct {
    tl: *const text.Layout,
    placeholder: []const u8,
    caret_px: i32,
    placeholder_layout: ?*const text.Layout,
    invalid: bool = false,
};

pub fn textInput(ui_ptr: *Ui, src: std.builtin.SourceLocation, buf: *TextBuf, opts: TextInputOptions) TextInputResult {
    const id = ui_ptr.id(src, opts.key);
    const t = ui_ptr.theme_ptr;
    const style = styleFor(t, .body);
    const st = ui_ptr.stateSticky(TextInputState, id, .{ .caret = buf.len() });
    st.caret = @min(st.caret, buf.len());
    const disp_slice: []const u8 = if (opts.password and buf.len() > 0) blk: {
        const cp_cnt = core.codepointCount(buf.slice());
        if (ui_ptr.frameAlloc().alloc(u8, cp_cnt)) |m| {
            @memset(m, '*');
            break :blk m;
        } else |_| break :blk buf.slice();
    } else buf.slice();
    const l = makeLayout(ui_ptr, disp_slice, style, .{ .newlines = .as_space });
    var p = layout.Params{ .kind = .leaf, .main = .fit, .cross = .fit, .content = .{ .size = .{ .x = @max(120, l.size.w + t.metric(.pad_input_x) * 2), .y = t.metric(.control_h) } } };
    applyItem(&p, opts.layout);
    const placeholder_layout = if (opts.placeholder.len > 0) makeLayout(ui_ptr, opts.placeholder, style, .{ .newlines = .as_space }) else null;
    const props = ui_ptr.treeAlloc().create(TextInputProps) catch @panic("nano_gui: props allocation failed");
    props.* = .{ .tl = l, .placeholder = opts.placeholder, .caret_px = 0, .placeholder_layout = placeholder_layout, .invalid = opts.invalid };
    const node = ui_ptr.leaf(id, .{
        .layout = p,
        .flags = .{ .focusable = opts.enabled, .disabled = !opts.enabled },
        .paint = paintTextInput,
        .props = props,
        .paint_outset = t.metric(.focus_ring_w),
        .paint_key = core.hashBytes(0xbbcc, disp_slice) ^ (@as(u64, buf.revision()) << 8) ^ (@as(u64, @intFromBool(opts.invalid)) << 1),
    });
    node.src_file = src.file;
    node.src_line = src.line;
    if (opts.debug_name) |dn| node.debug_name = dn;
    const it = ui_ptr.interact(id, .{
        .sense = .{ .hover = true, .click = true },
        .cursor = .ibeam,
        .text_input = true,
        .preempt = .{ .groups = .{ .printable = true, .arrows = true, .home_end = true, .page = true, .backspace_delete = true, .edit_chords = true } },
    });
    var result = TextInputResult{ .hovered = it.hovered, .pressed = it.pressed, .focused = it.focused };
    if (opts.enabled and !opts.read_only) {
        for (ui_ptr.events(id)) |ev| {
            switch (ev) {
                .char => |cp| {
                    const ok_len = if (opts.max_len) |ml| core.codepointCount(buf.slice()) < ml else true;
                    if (ok_len) {
                        var tmp: [4]u8 = undefined;
                        const n = core.utf8Encode(cp, &tmp);
                        if (st.caret <= buf.len()) {
                            buf.replace(st.caret, st.caret, tmp[0..n]) catch {};
                            st.caret += n;
                            result.changed = true;
                        }
                    }
                },
                .ime_commit => |txt| {
                    const ok_len = if (opts.max_len) |ml| core.codepointCount(buf.slice()) + core.codepointCount(txt) <= ml else true;
                    if (ok_len) {
                        buf.replace(st.caret, st.caret, txt) catch {};
                        st.caret += txt.len;
                        result.changed = true;
                    }
                },
                .key_down => |k| {
                    switch (k.key) {
                        .backspace => {
                            if (st.caret > 0) {
                                const prev = text.prevGrapheme(buf.slice(), st.caret);
                                buf.replace(prev, st.caret, "") catch {};
                                st.caret = prev;
                                result.changed = true;
                            }
                        },
                        .delete => {
                            if (st.caret < buf.len()) {
                                const next = text.nextGrapheme(buf.slice(), st.caret);
                                buf.replace(st.caret, next, "") catch {};
                                result.changed = true;
                            }
                        },
                        .left => st.caret = text.prevGrapheme(buf.slice(), st.caret),
                        .right => st.caret = text.nextGrapheme(buf.slice(), st.caret),
                        .home => st.caret = 0,
                        .end => st.caret = buf.len(),
                        .enter => result.committed = true,
                        .escape => result.cancelled = true,
                        .v => {
                            if (k.mods.ctrl) {
                                if (platform.clipboard.getText(ui_ptr.gpa)) |maybe| {
                                    defer if (maybe) |txt| ui_ptr.gpa.free(txt);
                                    if (maybe) |txt| {
                                        buf.replace(st.caret, st.caret, txt) catch {};
                                        st.caret += txt.len;
                                        result.changed = true;
                                    }
                                } else |_| {}
                            }
                        },
                        .c => {
                            if (k.mods.ctrl) platform.clipboard.setText(buf.slice()) catch {};
                        },
                        .a => {
                            if (k.mods.ctrl) st.caret = buf.len();
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }
    }
    if (it.focused and it.clicked) st.caret = buf.len();
    if (result.changed) {
        buf.revision_value +%= 1;
        // 事件处理会修改文本；重算本帧的排版与绘制键，避免显示滞后与漏损伤。
        const nl = makeLayout(ui_ptr, buf.slice(), style, .{ .newlines = .as_space });
        props.tl = nl;
        node.paint_key = core.hashBytes(0xbbcc, buf.slice()) ^ @as(u64, buf.revision()) << 8;
        node.layout.content.size = .{
            .x = @max(120, nl.size.w + t.metric(.pad_input_x) * 2),
            .y = t.metric(.control_h),
        };
    }
    props.caret_px = @intFromFloat(@round(measurePrefix(buf.slice(), st.caret, style, ui_ptr.scale, t) * ui_ptr.scale));
    if (it.focused) {
        const blink = platform.metrics(ui_ptr.window).caret_blink_ms;
        if (ui_ptr.lastRectPx(id)) |nr| {
            const pad = t.metric(.pad_input_x);
            const cx = nr.x + @as(i32, @intFromFloat(@round(pad * ui_ptr.scale))) + props.caret_px;
            ui_ptr.setCaretBlink(id, blink, .{ .x = cx, .y = nr.y + 4, .w = 1, .h = @max(1, nr.h - 8) });
            const lr = ui_ptr.lastRect(id).?;
            ui_ptr.imeCaret(id, .{ .x = lr.x + pad + @as(f32, @floatFromInt(props.caret_px)) / ui_ptr.scale, .y = lr.y + 2, .w = 1, .h = @max(1, lr.h - 4) }, null);
        } else {
            ui_ptr.setCaretBlink(id, blink, .{ .x = 0, .y = 0, .w = 1, .h = 1 });
        }
    } else {
        ui_ptr.setCaretBlink(id, null, .{});
    }
    if (opts.tooltip) |tip| ui_ptr.tooltip(id, tip);
    return result;
}

fn measurePrefix(s: []const u8, upto: usize, style: text.Style, scale: f32, t: *const Theme) f32 {
    _ = t;
    return text.advance(style, scale) * @as(f32, @floatFromInt(core.codepointCount(s[0..@min(upto, s.len)])));
}

fn paintTextInput(ctx: *PaintCtx, node: *const Node) void {
    const p: *const TextInputProps = @ptrCast(@alignCast(node.props.?));
    const r = ctx.rect(node);
    const t = ctx.draw.theme;
    const v = ctx.visual(node);
    theme.drawSunken(&ctx.draw, r, .radius_control, v, p.invalid);
    const pad = t.metric(.pad_input_x);
    ctx.draw.canvas.pushClip(.{ .x = r.x + pad, .y = r.y, .w = @max(0, r.w - pad * 2), .h = r.h });
    const fg = if (v.disabled) t.color(.text_disabled) else t.color(.text_primary);
    if (p.tl.text.len == 0 and p.placeholder_layout != null) {
        text.draw(ctx.draw.canvas, p.placeholder_layout.?, .{ .x = r.x + pad, .y = r.y + (r.h - p.placeholder_layout.?.size.h) * 0.5 }, t.color(.text_placeholder), .{});
    } else {
        text.draw(ctx.draw.canvas, p.tl, .{ .x = r.x + pad, .y = r.y + (r.h - p.tl.size.h) * 0.5 }, fg, .{});
    }
    if (v.focused_visible and ctx.ui.caretVisible(node.id)) {
        const cx = r.x + pad + @as(f32, @floatFromInt(p.caret_px)) / ctx.draw.scale;
        ctx.draw.canvas.fillRect(.{ .x = cx, .y = r.y + 4, .w = 1, .h = r.h - 8 }, t.color(.accent_mark));
    }
    ctx.draw.canvas.popClip();
}

test "text buffer" {
    var b = TextBuf.init(std.testing.allocator);
    defer b.deinit();
    try b.set("hello");
    try std.testing.expectEqualStrings("hello", b.slice());
    try b.replace(1, 4, "i");
    try std.testing.expectEqualStrings("hio", b.slice());
}

// ---------------------------------------------------------------------------
// 提示框（tooltip）
// ---------------------------------------------------------------------------

pub const TooltipOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    shortcut_text: ?[]const u8 = null,
    layout: layout.ItemOptions = .{},
};

pub const TooltipResult = struct { shown: bool = false };

const TooltipState = struct { start_ms: u64 = 0, active: bool = false };
const TooltipProps = struct { tl: *const text.Layout, shortcut: ?*const text.Layout };

pub fn tooltip(ui_ptr: *Ui, src: std.builtin.SourceLocation, owner: core.WidgetId, label_text: []const u8, opts: TooltipOptions) TooltipResult {
    if (!opts.enabled) return .{};
    const owner_node = ui_ptr.getPrevNode(owner) orelse return .{};
    if (!owner_node.interaction.hovered or ui_ptr.capturedId() != .none) return .{};
    const id = ui_ptr.id(src, opts.key);
    const st = ui_ptr.stateSticky(TooltipState, id, .{});
    if (!st.active) {
        st.active = true;
        st.start_ms = ui_ptr.now();
    }
    const delay = platform.metrics(ui_ptr.window).hover_time_ms;
    if (ui_ptr.now() -| st.start_ms < delay) {
        _ = ui_ptr.timer(id, delay, .paint);
        return .{};
    }
    const t = ui_ptr.theme_ptr;
    const style = styleFor(t, .small);
    const max_w = t.metric(.tooltip_max_w);
    const l = makeLayout(ui_ptr, label_text, style, .{ .max_width = max_w, .wrap = .word, .newlines = .as_space });
    const props = ui_ptr.treeAlloc().create(TooltipProps) catch @panic("nano_gui: props allocation failed");
    props.* = .{ .tl = l, .shortcut = if (opts.shortcut_text) |s| makeLayout(ui_ptr, s, style, .{ .newlines = .as_space }) else null };
    const ow = owner_node.abs;
    const pad = t.metric(.pad_panel);
    const w = l.size.w + pad * 2;
    const h = l.size.h + pad * 2;
    var rect = core.Rect{
        .x = @as(f32, @floatFromInt(ow.x)) / ui_ptr.scale,
        .y = (@as(f32, @floatFromInt(ow.y + ow.h)) + t.metric(.gap_sm)) / ui_ptr.scale,
        .w = w,
        .h = h,
    };
    const vp = core.Rect{ .x = 0, .y = 0, .w = @as(f32, @floatFromInt(ui_ptr.viewport.w)) / ui_ptr.scale, .h = @as(f32, @floatFromInt(ui_ptr.viewport.h)) / ui_ptr.scale };
    if (rect.bottom() > vp.bottom()) rect.y = @as(f32, @floatFromInt(ow.y)) / ui_ptr.scale - h - t.metric(.gap_sm) / ui_ptr.scale;
    rect.x = std.math.clamp(rect.x, 0, @max(0, vp.w - w));
    ui_ptr.overlay(id, .{ .rect = rect, .paint = paintTooltip, .props = props });
    return .{ .shown = true };
}

fn paintTooltip(ctx: *PaintCtx, rect: core.Rect, props: ?*const anyopaque) void {
    const p: *const TooltipProps = @ptrCast(@alignCast(props.?));
    theme.drawPopupFrame(&ctx.draw, rect, true);
    const t = ctx.draw.theme;
    text.draw(ctx.draw.canvas, p.tl, .{ .x = rect.x + t.metric(.pad_panel), .y = rect.y + t.metric(.pad_panel) }, t.color(.text_primary), .{});
    if (p.shortcut) |sl| {
        text.draw(ctx.draw.canvas, sl, .{ .x = rect.right() - t.metric(.pad_panel) - sl.size.w, .y = rect.y + t.metric(.pad_panel) }, t.color(.text_secondary), .{});
    }
}

// ---------------------------------------------------------------------------
// 微调框（spin box）
// ---------------------------------------------------------------------------

pub const SpinBoxIntOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    min: i64 = std.math.minInt(i64),
    max: i64 = std.math.maxInt(i64),
    step: i64 = 1,
    big_step: ?i64 = null,
    read_only: bool = false,
    show_arrows: bool = true,
    size: ControlSize = .md,
    tooltip: ?[]const u8 = null,
    layout: layout.ItemOptions = .{},
};

pub const SpinBoxFloatOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    min: f64 = -1.0e15,
    max: f64 = 1.0e15,
    step: f64 = 1.0,
    big_step: ?f64 = null,
    decimals: u8 = 2,
    read_only: bool = false,
    show_arrows: bool = true,
    size: ControlSize = .md,
    tooltip: ?[]const u8 = null,
    layout: layout.ItemOptions = .{},
};

pub const SpinBoxResult = struct {
    id: core.WidgetId = .none,
    hovered: bool = false,
    focused: bool = false,
    editing: bool = false,
    changed: bool = false,
    committed: bool = false,
};

const SpinProps = struct { tl: *const text.Layout };

fn spinCommon(ui_ptr: *Ui, src: std.builtin.SourceLocation, label_text: []const u8, key: ?ui.Key, debug_name: ?[]const u8, enabled: bool, read_only: bool, layout_item: layout.ItemOptions, arrows: bool) struct { id: core.WidgetId, it: input.Interaction, node: *Node } {
    const id = ui_ptr.id(src, key);
    const t = ui_ptr.theme_ptr;
    const l = makeLayout(ui_ptr, label_text, styleFor(t, .body), .{ .newlines = .as_space });
    const arrow_w = if (arrows) t.metric(.icon_sm) else 0;
    const w = @max(72, l.size.w + t.metric(.pad_input_x) * 2 + arrow_w);
    var p = layout.Params{
        .kind = .leaf,
        .main = .fit,
        .cross = .fit,
        .content = .{ .size = .{ .x = w, .y = t.metric(.control_h) } },
    };
    applyItem(&p, layout_item);
    const props = ui_ptr.treeAlloc().create(SpinProps) catch @panic("nano_gui: props allocation failed");
    props.* = .{ .tl = l };
    const node = ui_ptr.leaf(id, .{
        .layout = p,
        .flags = .{ .focusable = enabled, .disabled = !enabled },
        .paint = paintSpin,
        .props = props,
        .paint_outset = t.metric(.focus_ring_w),
        .paint_key = core.hashBytes(0xccdd, label_text),
    });
    node.src_file = src.file;
    node.src_line = src.line;
    if (debug_name) |dn| node.debug_name = dn;
    const it = ui_ptr.interact(id, .{
        .sense = .{ .hover = true, .click = true },
        .handles = .{ .groups = .{ .arrows = true, .page = true, .enter = true } },
        .take_focus_on_click = !read_only,
    });
    return .{ .id = id, .it = it, .node = node };
}

fn paintSpin(ctx: *PaintCtx, node: *const Node) void {
    const p: *const SpinProps = @ptrCast(@alignCast(node.props.?));
    const r = ctx.rect(node);
    const t = ctx.draw.theme;
    const v = ctx.visual(node);
    theme.drawSunken(&ctx.draw, r, .radius_control, v, false);
    const arrow_w = t.metric(.icon_sm);
    text.draw(ctx.draw.canvas, p.tl, .{ .x = r.x + t.metric(.pad_input_x), .y = r.y + (r.h - p.tl.size.h) * 0.5 }, if (v.disabled) t.color(.text_disabled) else t.color(.text_primary), .{});
    if (node.layout.content.size.x >= 72) {
        const cx = r.right() - arrow_w * 0.5;
        ctx.draw.canvas.strokeLine(.{ .x = cx - 3, .y = r.y + r.h * 0.45 }, .{ .x = cx, .y = r.y + r.h * 0.3 }, t.color(.text_secondary), 1);
        ctx.draw.canvas.strokeLine(.{ .x = cx, .y = r.y + r.h * 0.3 }, .{ .x = cx + 3, .y = r.y + r.h * 0.45 }, t.color(.text_secondary), 1);
        ctx.draw.canvas.strokeLine(.{ .x = cx - 3, .y = r.y + r.h * 0.55 }, .{ .x = cx, .y = r.y + r.h * 0.7 }, t.color(.text_secondary), 1);
        ctx.draw.canvas.strokeLine(.{ .x = cx, .y = r.y + r.h * 0.7 }, .{ .x = cx + 3, .y = r.y + r.h * 0.55 }, t.color(.text_secondary), 1);
    }
    if (v.focused_visible) theme.drawFocusRing(&ctx.draw, r, .radius_control, v);
}

pub fn spinBoxInt(ui_ptr: *Ui, src: std.builtin.SourceLocation, value: *i64, opts: SpinBoxIntOptions) SpinBoxResult {
    const text_value = std.fmt.allocPrint(ui_ptr.treeAlloc(), "{d}", .{value.*}) catch "0";
    const c = spinCommon(ui_ptr, src, text_value, opts.key, opts.debug_name, opts.enabled, opts.read_only, opts.layout, opts.show_arrows);
    var res = SpinBoxResult{ .id = c.id, .hovered = c.it.hovered, .focused = c.it.focused };
    if (!opts.enabled or opts.read_only) return res;
    var delta: i64 = 0;
    if (c.it.clicked) {
        if (c.it.pointer) |pt| {
            const wppx = @as(f32, @floatFromInt(c.node.abs.w));
            if (pt.x * ui_ptr.scale > wppx - ui_ptr.theme_ptr.metric(.icon_sm)) {
                if (pt.y * ui_ptr.scale < @as(f32, @floatFromInt(c.node.abs.h)) * 0.5) delta = opts.step else delta = -opts.step;
            }
        }
    }
    for (ui_ptr.events(c.id)) |ev| switch (ev) {
        .key_down => |k| {
            if (k.key == .up) delta = opts.step;
            if (k.key == .down) delta = -opts.step;
            if (k.key == .page_up) delta = opts.big_step orelse opts.step * 10;
            if (k.key == .page_down) delta = -(opts.big_step orelse opts.step * 10);
        },
        else => {},
    };
    if (delta != 0) {
        value.* = std.math.clamp(value.* +% delta, opts.min, opts.max);
        res.changed = true;
    }
    return res;
}

pub fn spinBoxFloat(ui_ptr: *Ui, src: std.builtin.SourceLocation, value: *f64, opts: SpinBoxFloatOptions) SpinBoxResult {
    const text_value = std.fmt.allocPrint(ui_ptr.treeAlloc(), "{d}", .{value.*}) catch "0";
    const c = spinCommon(ui_ptr, src, text_value, opts.key, opts.debug_name, opts.enabled, opts.read_only, opts.layout, opts.show_arrows);
    var res = SpinBoxResult{ .id = c.id, .hovered = c.it.hovered, .focused = c.it.focused };
    if (!opts.enabled or opts.read_only) return res;
    var delta: f64 = 0;
    if (c.it.clicked) {
        if (c.it.pointer) |pt| {
            const wppx = @as(f32, @floatFromInt(c.node.abs.w));
            if (pt.x * ui_ptr.scale > wppx - ui_ptr.theme_ptr.metric(.icon_sm)) {
                if (pt.y * ui_ptr.scale < @as(f32, @floatFromInt(c.node.abs.h)) * 0.5) delta = opts.step else delta = -opts.step;
            }
        }
    }
    for (ui_ptr.events(c.id)) |ev| switch (ev) {
        .key_down => |k| {
            if (k.key == .up) delta = opts.step;
            if (k.key == .down) delta = -opts.step;
            if (k.key == .page_up) delta = opts.big_step orelse opts.step * 10;
            if (k.key == .page_down) delta = -(opts.big_step orelse opts.step * 10);
        },
        else => {},
    };
    if (delta != 0) {
        value.* = std.math.clamp(value.* + delta, opts.min, opts.max);
        res.changed = true;
    }
    return res;
}

// ---------------------------------------------------------------------------
// combo box（本实现的弹出层退化为“点击循环下一项”，接口与结果保持稳定）
// ---------------------------------------------------------------------------

pub const ItemSource = union(enum) {
    slice: []const []const u8,
    callback: struct {
        count: u32,
        ctx: ?*const anyopaque = null,
        text_at: *const fn (ctx: ?*const anyopaque, index: u32, arena: std.mem.Allocator) []const u8,
    },

    pub fn count(self: ItemSource) u32 {
        return switch (self) {
            .slice => |s| @intCast(s.len),
            .callback => |c| c.count,
        };
    }
    pub fn textAt(self: ItemSource, index: u32, arena: std.mem.Allocator) []const u8 {
        return switch (self) {
            .slice => |s| if (index < s.len) s[index] else "",
            .callback => |c| if (index < c.count) c.text_at(c.ctx, index, arena) else "",
        };
    }
};

pub const ComboBoxOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    max_rows: u8 = 10,
    placeholder: ?[]const u8 = null,
    size: ControlSize = .md,
    tooltip: ?[]const u8 = null,
    layout: layout.ItemOptions = .{},
};

pub const ComboBoxResult = struct {
    id: core.WidgetId = .none,
    hovered: bool = false,
    focused: bool = false,
    open: bool = false,
    changed: bool = false,
    committed: bool = false,
    picked: ?u32 = null,
};

const ComboProps = struct { tl: *const text.Layout };
const ComboState = struct { open: bool = false };

pub fn comboBox(ui_ptr: *Ui, src: std.builtin.SourceLocation, selected: *?u32, items: ItemSource, opts: ComboBoxOptions) ComboBoxResult {
    const id = ui_ptr.id(src, opts.key);
    const st = ui_ptr.stateSticky(ComboState, id, .{});
    const t = ui_ptr.theme_ptr;
    const text_value = if (selected.*) |i| items.textAt(i, ui_ptr.treeAlloc()) else (opts.placeholder orelse "");
    const l = makeLayout(ui_ptr, text_value, styleFor(t, .body), .{ .newlines = .as_space });
    const w = @max(96, l.size.w + t.metric(.pad_input_x) * 2 + t.metric(.icon_sm));
    var p = layout.Params{ .kind = .leaf, .main = .fit, .cross = .fit, .content = .{ .size = .{ .x = w, .y = heightFor(t, opts.size) } } };
    applyItem(&p, opts.layout);
    const props = ui_ptr.treeAlloc().create(ComboProps) catch @panic("nano_gui: props allocation failed");
    props.* = .{ .tl = l };
    const node = ui_ptr.leaf(id, .{ .layout = p, .flags = .{ .focusable = opts.enabled, .disabled = !opts.enabled }, .paint = paintCombo, .props = props, .paint_outset = t.metric(.focus_ring_w), .paint_key = core.hashBytes(0xeeff, text_value) ^ @intFromBool(st.open) });
    node.src_file = src.file;
    node.src_line = src.line;
    if (opts.debug_name) |dn| node.debug_name = dn;
    const it = ui_ptr.interact(id, .{ .sense = .{ .hover = true, .click = true }, .handles = .{ .groups = .{ .arrows = true, .enter = true, .escape = st.open } } });
    var res = ComboBoxResult{ .id = id, .hovered = it.hovered, .focused = it.focused, .open = st.open };
    if (opts.enabled and it.clicked) {
        st.open = !st.open;
        res.open = st.open;
    }
    for (ui_ptr.events(id)) |ev| switch (ev) {
        .key_down => |k| {
            const n = items.count();
            if (n == 0) continue;
            if (k.key == .escape and st.open) {
                st.open = false;
                res.open = false;
            } else if (k.key == .enter or k.key == .space) {
                st.open = !st.open;
                res.open = st.open;
            } else if (k.key == .down) {
                if (k.mods.alt) {
                    st.open = true;
                    res.open = true;
                } else {
                    selected.* = if (selected.*) |s| (s + 1) % n else 0;
                    res.changed = true;
                    res.committed = true;
                    res.picked = selected.*;
                }
            } else if (k.key == .up) {
                selected.* = if (selected.*) |s| (s + n - 1) % n else n - 1;
                res.changed = true;
                res.committed = true;
                res.picked = selected.*;
            }
        },
        else => {},
    };
    if (opts.enabled and st.open) {
        const n = items.count();
        const anchor = ui_ptr.lastRect(id) orelse core.Rect{ .x = 0, .y = 0, .w = w, .h = heightFor(t, opts.size) };
        const popup_id = ui_ptr.id(src, ui.Key.int(id.raw() ^ 0x636f6d62));
        if (ui_ptr.beginPopup(popup_id, .{ .kind = .dropdown, .anchor = anchor, .anchor_id = id, .match_anchor_width = true, .min_width = anchor.w, .owner = id })) {
            const show_n = @min(n, @as(u32, opts.max_rows));
            var i: u32 = 0;
            while (i < show_n) : (i += 1) {
                const item_label = items.textAt(i, ui_ptr.treeAlloc());
                const r = button(ui_ptr, @src(), item_label, .{
                    .key = ui.Key.int(i + 0x636d0000),
                    .variant = if (selected.* == i) .accent else .quiet,
                    .layout = .{ .cross = .fill },
                });
                if (r.clicked) {
                    selected.* = i;
                    res.picked = i;
                    res.changed = true;
                    res.committed = true;
                    st.open = false;
                    res.open = false;
                }
            }
            ui_ptr.endPopup();
        }
    }
    if (opts.tooltip) |tip| ui_ptr.tooltip(id, tip);
    return res;
}

fn paintCombo(ctx: *PaintCtx, node: *const Node) void {
    const p: *const ComboProps = @ptrCast(@alignCast(node.props.?));
    const r = ctx.rect(node);
    const t = ctx.draw.theme;
    const v = ctx.visual(node);
    theme.drawRaised(&ctx.draw, r, .radius_control, .neutral, v);
    text.draw(ctx.draw.canvas, p.tl, .{ .x = r.x + t.metric(.pad_input_x), .y = r.y + (r.h - p.tl.size.h) * 0.5 }, if (v.disabled) t.color(.text_disabled) else t.color(.text_primary), .{});
    const cx = r.right() - t.metric(.icon_sm) * 0.5 - 2;
    ctx.draw.canvas.strokeLine(.{ .x = cx - 3, .y = r.y + r.h * 0.42 }, .{ .x = cx, .y = r.y + r.h * 0.56 }, t.color(.text_secondary), 1);
    ctx.draw.canvas.strokeLine(.{ .x = cx, .y = r.y + r.h * 0.56 }, .{ .x = cx + 3, .y = r.y + r.h * 0.42 }, t.color(.text_secondary), 1);
}

// ---------------------------------------------------------------------------
// text area（多行文本，保留节点为 TextBuf 的轻量包装）
// ---------------------------------------------------------------------------

pub const Eol = enum { lf, crlf, cr };
pub const TextAreaWrap = enum { none, word };
pub const TextAreaHandle = struct { id: core.WidgetId };
pub const DocRange = struct { start: u64, end: u64 };

pub const TextAreaOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    wrap: TextAreaWrap = .word,
    accepts_tab: bool = false,
    read_only: bool = false,
    placeholder: ?[]const u8 = null,
    mono: bool = false,
    tab_width: u8 = 4,
    max_bytes: ?u64 = null,
    initial_text: ?[]const u8 = null,
    tooltip: ?[]const u8 = null,
    layout: layout.ItemOptions = .{},
};

pub const TextAreaResult = struct {
    handle: TextAreaHandle = .{ .id = .none },
    hovered: bool = false,
    focused: bool = false,
    composing: bool = false,
    selection: DocRange = .{ .start = 0, .end = 0 },
    caret: u64 = 0,
    caret_line: u32 = 0,
    caret_column: u32 = 0,
    modified: bool = false,
    changed: bool = false,
};

const TextSub = struct { f: ChangeFn, ctx: ?*anyopaque };

pub const TextAreaState = struct {
    data: std.ArrayListUnmanaged(u8) = .empty,
    gap_start: usize = 0,
    gap_end: usize = 0,
    revision_value: u32 = 0,
    caret: usize = 0,
    anchor: usize = 0,
    modified: bool = false,
    eol: Eol = .lf,
    had_bom: bool = false,
    subs: std.ArrayListUnmanaged(TextSub) = .empty,
    line_starts: std.ArrayListUnmanaged(u32) = .empty,
    line_rev: u32 = std.math.maxInt(u32),
    delta_after_line: usize = std.math.maxInt(usize),
    delta_bytes: i64 = 0,
    owner_allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TextAreaState {
        return .{ .owner_allocator = allocator };
    }
    pub fn deinit(self: *TextAreaState) void {
        self.data.deinit(self.owner_allocator);
        self.subs.deinit(self.owner_allocator);
        self.line_starts.deinit(self.owner_allocator);
    }
    pub fn textLen(self: *const TextAreaState) usize {
        return self.data.items.len - (self.gap_end - self.gap_start);
    }
    pub fn revision(self: *const TextAreaState) u32 {
        return self.revision_value;
    }
    fn byteAt(self: *const TextAreaState, idx: usize) u8 {
        return if (idx < self.gap_start) self.data.items[idx] else self.data.items[idx + (self.gap_end - self.gap_start)];
    }
    fn moveGap(self: *TextAreaState, pos: usize) void {
        const gap_len = self.gap_end - self.gap_start;
        if (pos == self.gap_start or gap_len == 0) {
            self.gap_start = pos;
            self.gap_end = pos + gap_len;
            return;
        }
        if (pos < self.gap_start) {
            const move_len = self.gap_start - pos;
            std.mem.copyBackwards(u8, self.data.items[pos + gap_len .. self.gap_end], self.data.items[pos..self.gap_start]);
            self.gap_start = pos;
            self.gap_end = pos + gap_len;
            _ = move_len;
        } else {
            const move_len = pos - self.gap_start;
            @memcpy(self.data.items[self.gap_start .. self.gap_start + move_len], self.data.items[self.gap_end .. self.gap_end + move_len]);
            self.gap_start = pos;
            self.gap_end = pos + gap_len;
        }
    }
    fn ensureGap(self: *TextAreaState, need: usize) error{OutOfMemory}!void {
        const cur = self.gap_end - self.gap_start;
        if (cur >= need) return;
        const extra = @max(need - cur, 4096);
        const old_len = self.data.items.len;
        const tail_len = old_len - self.gap_end;
        try self.data.resize(self.owner_allocator, old_len + extra);
        if (tail_len > 0) {
            std.mem.copyBackwards(u8, self.data.items[self.gap_end + extra .. old_len + extra], self.data.items[self.gap_end..old_len]);
        }
        self.gap_end += extra;
    }
    pub fn setText(self: *TextAreaState, bytes: []const u8) error{OutOfMemory}!void {
        self.data.clearRetainingCapacity();
        try self.data.ensureTotalCapacity(self.owner_allocator, bytes.len + 4096);
        self.data.appendSliceAssumeCapacity(bytes);
        self.gap_start = bytes.len;
        self.gap_end = bytes.len;
        self.revision_value +%= 1;
        self.delta_after_line = std.math.maxInt(usize);
        self.delta_bytes = 0;
        self.line_rev = std.math.maxInt(u32);
    }
    fn flushDelta(self: *TextAreaState) void {
        if (self.delta_after_line >= self.line_starts.items.len or self.delta_bytes == 0) {
            self.delta_after_line = std.math.maxInt(usize);
            self.delta_bytes = 0;
            return;
        }
        for (self.line_starts.items[self.delta_after_line + 1 ..]) |*v| {
            v.* = @intCast(@as(i64, v.*) + self.delta_bytes);
        }
        self.delta_after_line = std.math.maxInt(usize);
        self.delta_bytes = 0;
    }
    pub fn replaceText(self: *TextAreaState, start_in: usize, end_in: usize, bytes: []const u8) error{OutOfMemory}!void {
        const tlen = self.textLen();
        const start = @min(start_in, tlen);
        const end = @max(start, @min(end_in, tlen));
        const removed = end - start;
        var has_nl = std.mem.indexOfScalar(u8, bytes, '\n') != null;
        if (!has_nl and removed > 0) {
            var i: usize = start;
            while (i < end) : (i += 1) {
                if (self.byteAt(i) == '\n') {
                    has_nl = true;
                    break;
                }
            }
        }
        self.moveGap(start);
        self.gap_end += removed;
        if (bytes.len > 0) {
            try self.ensureGap(bytes.len);
            @memcpy(self.data.items[self.gap_start .. self.gap_start + bytes.len], bytes);
            self.gap_start += bytes.len;
        }
        const prev_rev = self.revision_value;
        self.revision_value +%= 1;
        if (!has_nl and self.line_rev == prev_rev and self.line_starts.items.len > 0) {
            const line = self.findLine(start);
            if (self.delta_after_line != line and self.delta_after_line < self.line_starts.items.len) {
                self.flushDelta();
            }
            self.delta_after_line = line;
            self.delta_bytes += @as(i64, @intCast(bytes.len)) - @as(i64, @intCast(removed));
            self.line_rev = self.revision_value;
        } else {
            self.delta_after_line = std.math.maxInt(usize);
            self.delta_bytes = 0;
        }
    }
    pub fn copyRange(self: *const TextAreaState, allocator: std.mem.Allocator, start_in: usize, end_in: usize) error{OutOfMemory}![]u8 {
        const tlen = self.textLen();
        const a = @min(start_in, tlen);
        const b = @max(a, @min(end_in, tlen));
        const out = try allocator.alloc(u8, b - a);
        if (b <= self.gap_start) {
            @memcpy(out, self.data.items[a..b]);
        } else if (a >= self.gap_start) {
            const g = self.gap_end - self.gap_start;
            @memcpy(out, self.data.items[a + g .. b + g]);
        } else {
            const first = self.gap_start - a;
            @memcpy(out[0..first], self.data.items[a..self.gap_start]);
            @memcpy(out[first..], self.data.items[self.gap_end .. self.gap_end + (b - self.gap_start)]);
        }
        return out;
    }
    fn localSlice(self: *const TextAreaState, start_in: usize, end_in: usize, scratch: []u8) []const u8 {
        const tlen = self.textLen();
        const a = @min(start_in, tlen);
        const b = @min(@max(a, @min(end_in, tlen)), a + scratch.len);
        var i: usize = 0;
        while (a + i < b) : (i += 1) scratch[i] = self.byteAt(a + i);
        return scratch[0..i];
    }
    pub fn ensureLines(self: *TextAreaState) void {
        const rev = self.revision_value;
        if (self.line_rev == rev and self.line_starts.items.len > 0) return;
        self.delta_after_line = std.math.maxInt(usize);
        self.delta_bytes = 0;
        self.line_starts.clearRetainingCapacity();
        self.line_starts.append(self.owner_allocator, 0) catch return;
        const gap_len = self.gap_end - self.gap_start;
        const left = self.data.items[0..self.gap_start];
        var pos: usize = 0;
        while (std.mem.indexOfScalarPos(u8, left, pos, '\n')) |nl| {
            self.line_starts.append(self.owner_allocator, @intCast(nl + 1)) catch break;
            pos = nl + 1;
        }
        const right = self.data.items[self.gap_end..];
        pos = 0;
        while (std.mem.indexOfScalarPos(u8, right, pos, '\n')) |nl| {
            self.line_starts.append(self.owner_allocator, @intCast(self.gap_start + nl + 1)) catch break;
            pos = nl + 1;
        }
        _ = gap_len;
        self.line_rev = rev;
    }
    pub fn lineAt(self: *const TextAreaState, idx: usize) usize {
        if (idx >= self.line_starts.items.len) return 0;
        const base = self.line_starts.items[idx];
        return if (idx > self.delta_after_line) @intCast(@as(i64, base) + self.delta_bytes) else base;
    }
    pub fn findLine(self: *const TextAreaState, offset: usize) usize {
        const n = self.line_starts.items.len;
        if (n == 0) return 0;
        var lo: usize = 0;
        var hi: usize = n;
        while (lo + 1 < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.lineAt(mid) <= offset) lo = mid else hi = mid;
        }
        return lo;
    }
    pub fn notify(self: *TextAreaState, start: u64, removed: u64, inserted: u64, source: ChangeSource) void {
        for (self.subs.items) |sub| {
            sub.f(sub.ctx, .{
                .start = start,
                .removed = removed,
                .inserted = inserted,
                .source = source,
                .revision = self.revision_value,
                .line = 0,
            });
        }
    }
};

const TextAreaProps = struct {
    text_layouts: []const *const text.Layout,
    caret_line: usize,
    caret_x: f32,
    placeholder: ?*const text.Layout,
};

pub fn textArea(ui_ptr: *Ui, src: std.builtin.SourceLocation, opts: TextAreaOptions) TextAreaResult {
    const id = ui_ptr.id(src, opts.key);
    const st = ui_ptr.retained(TextAreaState, id, .pinned);
    if (opts.initial_text) |init_txt| {
        if (st.textLen() == 0 and st.revision() == 0 and !st.modified) {
            st.setText(init_txt) catch {};
        }
    }
    const t = ui_ptr.theme_ptr;
    const style = if (opts.mono) styleFor(t, .mono) else styleFor(t, .body);
    st.ensureLines();
    const tlen = st.textLen();
    const total_lines = @max(@as(usize, 1), st.line_starts.items.len);
    const caret_line = st.findLine(@min(st.caret, tlen));
    const line_start_off: usize = st.lineAt(caret_line);
    const line_end_off: usize = if (caret_line + 1 < st.line_starts.items.len) st.lineAt(caret_line + 1) - 1 else tlen;
    const cur_line = st.copyRange(ui_ptr.frameAlloc(), line_start_off, @min(line_end_off, tlen)) catch "";
    const caret_col = @min(st.caret -| line_start_off, cur_line.len);
    const best_col = text.advance(style, ui_ptr.scale) * @as(f32, @floatFromInt(core.codepointCount(cur_line[0..caret_col])));

    const vis_start = caret_line -| 8;
    const vis_end = @min(total_lines, vis_start + 32);
    var lines = std.ArrayListUnmanaged(*const text.Layout).empty;
    defer lines.deinit(ui_ptr.treeAlloc());
    var li: usize = vis_start;
    while (li < vis_end) : (li += 1) {
        const ls: usize = st.lineAt(li);
        const le: usize = if (li + 1 < st.line_starts.items.len) st.lineAt(li + 1) - 1 else tlen;
        const line = st.copyRange(ui_ptr.frameAlloc(), ls, @min(le, tlen)) catch "";
        const l = makeLayout(ui_ptr, line, style, .{ .newlines = .break_lines });
        lines.append(ui_ptr.treeAlloc(), l) catch {};
    }
    const vis_caret_line = caret_line - vis_start;
    const height = @max(80, @as(f32, @floatFromInt(total_lines)) * style.size * 1.25 + t.metric(.pad_input_x) * 2);
    const content_key: u64 = (@as(u64, st.revision()) << 32) ^ @as(u64, total_lines) ^ @as(u64, st.caret);
    var p = layout.Params{
        .kind = .leaf,
        .main = .fit,
        .cross = .fit,
        .content = .{ .size = .{ .x = 260, .y = @min(height, 180) }, .key = content_key },
    };
    applyItem(&p, opts.layout);
    const props = ui_ptr.treeAlloc().create(TextAreaProps) catch @panic("nano_gui: props allocation failed");
    props.* = .{
        .text_layouts = tryDupeLayouts(ui_ptr, lines.items),
        .caret_line = vis_caret_line,
        .caret_x = best_col,
        .placeholder = if (opts.placeholder) |ph| makeLayout(ui_ptr, ph, style, .{ .newlines = .as_space }) else null,
    };
    const node = ui_ptr.leaf(id, .{
        .layout = p,
        .flags = .{ .focusable = opts.enabled, .disabled = !opts.enabled },
        .paint = paintTextArea,
        .props = props,
        .paint_outset = t.metric(.focus_ring_w),
        .paint_key = content_key,
    });
    node.src_file = src.file;
    node.src_line = src.line;
    if (opts.debug_name) |dn| node.debug_name = dn;
    const it = ui_ptr.interact(id, .{
        .sense = .{ .hover = true, .click = true },
        .cursor = .ibeam,
        .text_input = true,
        .preempt = .{ .groups = .{ .printable = true, .arrows = true, .home_end = true, .page = true, .backspace_delete = true, .edit_chords = true, .tab = opts.accepts_tab } },
        .handles = .{ .groups = .{ .tab = opts.accepts_tab } },
    });
    var res = TextAreaResult{
        .handle = .{ .id = id },
        .hovered = it.hovered,
        .focused = it.focused,
        .caret = st.caret,
        .caret_line = @intCast(caret_line),
        .caret_column = @intCast(caret_col),
        .modified = st.modified,
    };
    if (opts.enabled and !opts.read_only) {
        for (ui_ptr.events(id)) |ev| switch (ev) {
            .char => |cp| {
                var tmp: [4]u8 = undefined;
                const n = core.utf8Encode(cp, &tmp);
                st.replaceText(st.caret, st.caret, tmp[0..n]) catch {};
                st.caret += n;
                st.modified = true;
                res.changed = true;
            },
            .ime_commit => |txt| {
                st.replaceText(st.caret, st.caret, txt) catch {};
                st.caret += txt.len;
                st.modified = true;
                res.changed = true;
            },
            .key_down => |k| {
                var win_buf: [64]u8 = undefined;
                switch (k.key) {
                    .backspace => if (st.caret > 0) {
                        const base = st.caret -| 32;
                        const loc = st.localSlice(base, st.caret, &win_buf);
                        const prev = base + text.prevGrapheme(loc, loc.len);
                        st.replaceText(prev, st.caret, "") catch {};
                        st.caret = prev;
                        st.modified = true;
                        res.changed = true;
                    },
                    .delete => if (st.caret < st.textLen()) {
                        const loc = st.localSlice(st.caret, st.caret + 32, &win_buf);
                        const next = st.caret + text.nextGrapheme(loc, 0);
                        st.replaceText(st.caret, next, "") catch {};
                        st.modified = true;
                        res.changed = true;
                    },
                    .left => if (st.caret > 0) {
                        const base = st.caret -| 32;
                        const loc = st.localSlice(base, st.caret, &win_buf);
                        st.caret = base + text.prevGrapheme(loc, loc.len);
                    },
                    .right => if (st.caret < st.textLen()) {
                        const loc = st.localSlice(st.caret, st.caret + 32, &win_buf);
                        st.caret = st.caret + text.nextGrapheme(loc, 0);
                    },
                    .home => {
                        var i = st.caret;
                        while (i > 0 and st.byteAt(i - 1) != '\n') i -= 1;
                        st.caret = i;
                    },
                    .end => {
                        var i = st.caret;
                        const cur_len = st.textLen();
                        while (i < cur_len and st.byteAt(i) != '\n') i += 1;
                        st.caret = i;
                    },
                    .enter => {
                        st.replaceText(st.caret, st.caret, "\n") catch {};
                        st.caret += 1;
                        st.modified = true;
                        res.changed = true;
                    },
                    .tab => if (opts.accepts_tab) {
                        st.replaceText(st.caret, st.caret, "\t") catch {};
                        st.caret += 1;
                        st.modified = true;
                        res.changed = true;
                    },
                    else => {},
                }
            },
            else => {},
        };
    }
    if (res.changed) st.notify(@intCast(st.caret), 0, 0, .user);
    if (it.focused) {
        if (ui_ptr.lastRect(id)) |lr| {
            const pad = t.metric(.pad_input_x);
            const lh = style.size * 1.25;
            ui_ptr.imeCaret(id, .{ .x = lr.x + pad + best_col, .y = lr.y + pad + @as(f32, @floatFromInt(caret_line)) * lh, .w = 1, .h = style.size }, null);
        }
    }
    if (opts.tooltip) |tip| ui_ptr.tooltip(id, tip);
    res.caret = st.caret;
    res.selection = .{ .start = @min(st.caret, st.anchor), .end = @max(st.caret, st.anchor) };
    return res;
}

fn tryDupeLayouts(ui_ptr: *Ui, items: []const *const text.Layout) []const *const text.Layout {
    const out = ui_ptr.treeAlloc().alloc(*const text.Layout, items.len) catch @panic("nano_gui: text area layouts");
    @memcpy(out, items);
    return out;
}

fn paintTextArea(ctx: *PaintCtx, node: *const Node) void {
    const p: *const TextAreaProps = @ptrCast(@alignCast(node.props.?));
    const r = ctx.rect(node);
    const t = ctx.draw.theme;
    const v = ctx.visual(node);
    theme.drawSunken(&ctx.draw, r, .radius_control, v, false);
    const pad = t.metric(.pad_input_x);
    ctx.draw.canvas.pushClip(.{ .x = r.x + pad, .y = r.y + pad, .w = @max(0, r.w - pad * 2), .h = @max(0, r.h - pad * 2) });
    if (p.text_layouts.len == 1 and p.text_layouts[0].text.len == 0 and p.placeholder != null) {
        text.draw(ctx.draw.canvas, p.placeholder.?, .{ .x = r.x + pad, .y = r.y + pad }, t.color(.text_placeholder), .{});
    } else {
        for (p.text_layouts, 0..) |l, i| {
            text.draw(ctx.draw.canvas, l, .{ .x = r.x + pad, .y = r.y + pad + @as(f32, @floatFromInt(i)) * l.style.size * 1.25 }, if (v.disabled) t.color(.text_disabled) else t.color(.text_primary), .{});
        }
    }
    if (v.focused_visible) {
        const cy = r.y + pad + @as(f32, @floatFromInt(p.caret_line)) * t.fonts.get(.body).size * 1.25;
        ctx.draw.canvas.fillRect(.{ .x = r.x + pad + p.caret_x, .y = cy + 2, .w = 1, .h = t.fonts.get(.body).size }, t.color(.accent_mark));
    }
    ctx.draw.canvas.popClip();
}

pub const LoadInfo = struct { eol: Eol, mixed: bool, had_bom: bool, lines: u32, bytes: u64 };
pub const SaveOptions = struct { eol: ?Eol = null, bom: ?bool = null };
pub const TextAreaError = error{ OutOfMemory, TooLarge };

pub fn textAreaLoad(ui_ptr: *Ui, h: TextAreaHandle, bytes: []const u8) TextAreaError!LoadInfo {
    core.stats.timerBegin("time.text_load");
    defer core.stats.timerEnd("time.text_load");
    const st = ui_ptr.retained(TextAreaState, h.id, .pinned);
    st.setText(bytes) catch return error.OutOfMemory;
    st.ensureLines();
    st.modified = false;
    st.caret = 0;
    st.anchor = 0;
    return .{ .eol = .lf, .mixed = false, .had_bom = false, .lines = @intCast(@max(@as(usize, 1), st.line_starts.items.len)), .bytes = bytes.len };
}

pub fn textAreaText(ui_ptr: *Ui, h: TextAreaHandle, allocator: std.mem.Allocator, opts: SaveOptions) error{OutOfMemory}![]u8 {
    _ = opts;
    const st = ui_ptr.retained(TextAreaState, h.id, .pinned);
    return st.copyRange(allocator, 0, st.textLen());
}

pub fn textAreaRange(ui_ptr: *Ui, h: TextAreaHandle, start: u64, end: u64, allocator: std.mem.Allocator) error{OutOfMemory}![]u8 {
    const st = ui_ptr.retained(TextAreaState, h.id, .pinned);
    return st.copyRange(allocator, @intCast(start), @intCast(end));
}

pub fn textAreaReplace(ui_ptr: *Ui, h: TextAreaHandle, start: u64, end: u64, bytes: []const u8) TextAreaError!void {
    const st = ui_ptr.retained(TextAreaState, h.id, .pinned);
    st.replaceText(@intCast(start), @intCast(end), bytes) catch return error.OutOfMemory;
    st.modified = true;
}

pub const TextAreaInfo = struct { bytes: u64, lines: u32, revision: u64, eol: Eol, modified: bool };

pub fn textAreaInfo(ui_ptr: *const Ui, h: TextAreaHandle) ?TextAreaInfo {
    const st = ui_ptr.getState(TextAreaState, h.id) orelse return null;
    const mutable: *TextAreaState = @constCast(st);
    mutable.ensureLines();
    return .{ .bytes = st.textLen(), .lines = @intCast(@max(@as(usize, 1), st.line_starts.items.len)), .revision = st.revision(), .eol = st.eol, .modified = st.modified };
}

pub fn textAreaMarkSaved(ui_ptr: *Ui, h: TextAreaHandle) void {
    const st = ui_ptr.retained(TextAreaState, h.id, .pinned);
    st.modified = false;
}

pub fn textAreaSetSelection(ui_ptr: *Ui, h: TextAreaHandle, anchor: u64, caret: u64) void {
    const st = ui_ptr.retained(TextAreaState, h.id, .pinned);
    st.anchor = @intCast(anchor);
    st.caret = @intCast(caret);
}

// ---------------------------------------------------------------------------
// 列表与选择集（list / selection）
// ---------------------------------------------------------------------------

pub const ItemKey = u64;
pub const SelectionMode = enum { none, single, multi };
/// 列表拖动重排的拖放载荷 kind（框架保留，'LSTR'）。
pub const list_reorder_kind: u32 = 0x4C535452;

pub const KeyView = struct {
    ctx: ?*anyopaque = null,
    count: usize,
    key_of: ?*const fn (ctx: ?*anyopaque, index: usize) ItemKey = null,

    pub fn keyAt(self: KeyView, index: usize) ItemKey {
        if (self.key_of) |f| return f(self.ctx, index);
        return @intCast(index);
    }
};

pub const Selection = struct {
    allocator: std.mem.Allocator,
    keys: std.ArrayListUnmanaged(ItemKey) = .empty,
    /// 键索引：`contains` 为 O(1) 期望（REQ-W-LIST-013）。
    set: std.AutoHashMapUnmanaged(ItemKey, void) = .empty,

    pub fn init(allocator: std.mem.Allocator) Selection {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Selection) void {
        self.keys.deinit(self.allocator);
        self.set.deinit(self.allocator);
    }
    pub fn contains(self: *const Selection, key: ItemKey) bool {
        return self.set.contains(key);
    }
    pub fn len(self: *const Selection) usize {
        return self.keys.items.len;
    }
    pub fn clear(self: *Selection) void {
        self.keys.clearRetainingCapacity();
        self.set.clearRetainingCapacity();
    }
    pub fn add(self: *Selection, key: ItemKey) error{OutOfMemory}!void {
        const gop = try self.set.getOrPut(self.allocator, key);
        if (gop.found_existing) return;
        errdefer _ = self.set.remove(key);
        try self.keys.append(self.allocator, key);
    }
    pub fn remove(self: *Selection, key: ItemKey) void {
        if (!self.set.remove(key)) return;
        var i: usize = 0;
        while (i < self.keys.items.len) : (i += 1) {
            if (self.keys.items[i] == key) {
                _ = self.keys.orderedRemove(i);
                return;
            }
        }
    }
    pub fn toggle(self: *Selection, key: ItemKey) error{OutOfMemory}!bool {
        if (self.contains(key)) {
            self.remove(key);
            return false;
        }
        try self.add(key);
        return true;
    }
    pub fn setOnly(self: *Selection, key: ItemKey) error{OutOfMemory}!void {
        self.clear();
        try self.add(key);
    }
    pub fn addRange(self: *Selection, view: KeyView, a: usize, b: usize) error{OutOfMemory}!void {
        const lo = @min(a, b);
        const hi = @max(a, b);
        var i = lo;
        while (i <= hi and i < view.count) : (i += 1) try self.add(view.keyAt(i));
    }
    pub fn pruneTo(self: *Selection, view: KeyView) void {
        var i: usize = 0;
        while (i < self.keys.items.len) {
            var found = false;
            var j: usize = 0;
            while (j < view.count) : (j += 1) {
                if (view.keyAt(j) == self.keys.items[i]) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                _ = self.set.remove(self.keys.items[i]);
                _ = self.keys.orderedRemove(i);
            } else i += 1;
        }
    }
    pub fn iterator(self: *const Selection) Iterator {
        return .{ .sel = self };
    }
    pub const Iterator = struct {
        sel: *const Selection,
        index: usize = 0,
        pub fn next(self: *Iterator) ?ItemKey {
            if (self.index >= self.sel.keys.items.len) return null;
            const key = self.sel.keys.items[self.index];
            self.index += 1;
            return key;
        }
    };
};

pub const ListData = struct {
    ctx: ?*anyopaque = null,
    key_of: ?*const fn (ctx: ?*anyopaque, index: usize) ItemKey = null,
    index_of: ?*const fn (ctx: ?*anyopaque, key: ItemKey) ?usize = null,
    item_text: ?*const fn (ctx: ?*anyopaque, index: usize) []const u8 = null,
    prefix_search: ?*const fn (ctx: ?*anyopaque, prefix: []const u8, start: usize) ?usize = null,

    pub fn keyAt(self: ListData, index: usize) ItemKey {
        if (self.key_of) |f| return f(self.ctx, index);
        return @intCast(index);
    }
    pub fn textAt(self: ListData, index: usize) []const u8 {
        if (self.item_text) |f| return f(self.ctx, index);
        return "";
    }
};

pub const ListOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    mode: SelectionMode = .single,
    selection: ?*Selection = null,
    data: ListData = .{},
    row_height: ?f32 = null,
    alternate_rows: bool = false,
    empty_text: ?[]const u8 = null,
    scrollbar: layout.BarPolicy = .auto,
    reorder: bool = false,
    tooltip_on_truncate: bool = true,
    layout: layout.ItemOptions = .{},
};

const ListRowProps = struct { selected: bool, hovered: bool };

fn paintListRow(ctx: *PaintCtx, node: *const Node) void {
    const p: *const ListRowProps = @ptrCast(@alignCast(node.props.?));
    const r = ctx.rect(node);
    const t = ctx.draw.theme;
    var hovered = p.hovered;
    if (!hovered and ctx.ui.hover_id != .none) {
        var cur = ctx.ui.getNode(ctx.ui.hover_id);
        while (cur) |n| : (cur = n.parent) {
            if (n.id == node.id) {
                hovered = true;
                break;
            }
        }
    }
    if (p.selected) {
        ctx.draw.canvas.fillRect(r, t.color(.accent_fill_bottom));
    } else if (hovered) {
        ctx.draw.canvas.fillRect(r, t.color(.surface_row_hover));
    }
}

pub const ListRow = struct {
    index: usize,
    key: ItemKey,
    selected: bool,
    focused: bool,
    hovered: bool,
    text_color: theme.ColorToken,
};

const ListCtrlBox = struct {
    ctrl: ListController,
    pub fn init(allocator: std.mem.Allocator) ListCtrlBox {
        return .{ .ctrl = ListController.init(allocator, .{}) };
    }
    pub fn deinit(self: *ListCtrlBox) void {
        self.ctrl.deinit();
    }
};

pub const ListIter = struct {
    ui_ptr: *Ui,
    ctrl: *ListController,
    count: usize,
    opts: ListOptions,
    index: usize = 0,
    open_row: bool = false,
    current_key: ItemKey = 0,
    scroll_id: core.WidgetId = .none,
    viewport_h: f32 = 0,
    row_h: f32 = 0,
    first: usize = 0,
    last: usize = 0,
    focused_index: ?usize = null,

    pub fn next(self: *ListIter) ?ListRow {
        const limit = if (self.last > self.first) self.last else self.count;
        if (self.index >= limit) return null;
        if (self.open_row) {
            self.ui_ptr.endRow();
            self.ui_ptr.popId();
            self.open_row = false;
        }
        const i = self.index;
        self.index += 1;
        const key = self.opts.data.keyAt(i);
        self.ui_ptr.pushId(ui.Key.int(key));
        const row_id = self.ui_ptr.beginRow(@src(), .{ .main = .fixedSize(self.row_h), .cross = .fill, .padding = core.Insets.symmetric(4, 0), .cross_align = .center });
        const it = self.ui_ptr.interact(row_id, .{ .sense = .{ .hover = true, .click = true }, .cursor = .arrow });
        var selection_changed = false;
        for (self.ui_ptr.events(row_id)) |ev| switch (ev) {
            .press => |p| {
                const u = self.ctrl.pointerPress(i, p.button, p.mods, self.count);
                selection_changed = selection_changed or u.selection_changed;
            },
            .release => |r| {
                const u = self.ctrl.pointerRelease(i, r.inside, if (it.double_clicked) 2 else 1, r.mods, self.count);
                selection_changed = selection_changed or u.selection_changed;
            },
            else => {},
        };
        if (selection_changed) self.ui_ptr.invalidate(.build);
        const selected = self.ctrl.selection().contains(key);
        if (it.hovered) self.focused_index = i;
        if (self.ui_ptr.getNode(row_id)) |node| {
            const props = self.ui_ptr.treeAlloc().create(ListRowProps) catch null;
            if (props) |pr| {
                pr.* = .{ .selected = selected, .hovered = it.hovered };
                node.paint = paintListRow;
                node.props = pr;
                node.paint_key = @as(u64, @intFromBool(selected)) | (@as(u64, @intFromBool(it.hovered)) << 1);
            }
        }
        self.open_row = true;
        self.current_key = key;
        return .{
            .index = i,
            .key = key,
            .selected = selected,
            .focused = if (self.ctrl.focus) |f| f.index == i else false,
            .hovered = it.hovered,
            .text_color = if (selected) .text_on_accent else .text_primary,
        };
    }
};

pub const ListResult = struct {
    hovered: bool = false,
    focused: bool = false,
    focus_index: ?usize = null,
    selection: ?*Selection = null,
    selected_visible: usize = 0,
    selection_changed: bool = false,
    activated: ?usize = null,
    context_menu: ?struct { index: ?usize, pos: core.Vec2, anchor: core.Rect, from_keyboard: bool } = null,
    reordered: ?*anyopaque = null,
};

pub fn beginList(ui_ptr: *Ui, src: std.builtin.SourceLocation, count: usize, opts: ListOptions) ListIter {
    const t = ui_ptr.theme_ptr;
    const row_h = opts.row_height orelse t.metric(.row_h);
    const sv = beginScrollView(ui_ptr, src, .{
        .key = opts.key,
        .debug_name = opts.debug_name,
        .enabled = opts.enabled,
        .axes = .vertical,
        .bar_v = opts.scrollbar,
        .layout = .{ .main = .{ .grow = 1 }, .cross = .fill },
    });
    if (ui_ptr.getNode(sv.id)) |sn| {
        sn.flags.layout_feedback = true;
        _ = ui_ptr.lastRectPx(sv.id);
    }
    const box = ui_ptr.retained(ListCtrlBox, sv.id, .sticky);
    box.ctrl.opts = opts;
    const ctrl = &box.ctrl;
    const viewport_h: f32 = if (sv.viewport) |v| v.y else 240;
    ctrl.setViewport(if (sv.viewport) |v| v.x else 320, viewport_h, count);
    ctrl.offset = sv.offset.y;
    ctrl.correct(count);
    const content_id = ui_ptr.beginColumn(src, .{ .main = .fit, .cross = .fill, .gap = .none });
    _ = content_id;
    const offset_y: f32 = sv.offset.y;
    const first: usize = if (count == 0) 0 else @min(count - 1, @as(usize, @intFromFloat(@max(0, @floor(offset_y / @max(1, row_h))))));
    const visible: usize = @max(1, @as(usize, @intFromFloat(@ceil(viewport_h / @max(1, row_h)))) + 2);
    const last: usize = @min(count, first + visible);
    core.stats.gauge("list.virtual_nodes").* = last - first;
    if (first > 0) listSpacer(ui_ptr, @as(f32, @floatFromInt(first)) * row_h);
    const iter = ListIter{
        .ui_ptr = ui_ptr,
        .ctrl = ctrl,
        .count = count,
        .opts = opts,
        .scroll_id = sv.id,
        .row_h = row_h,
        .viewport_h = viewport_h,
        .first = first,
        .last = last,
        .index = first,
    };
    if (count == 0) {
        if (opts.empty_text) |txt| _ = label(ui_ptr, src, txt, .{ .style = .small, .color = .secondary });
    }
    return iter;
}

pub fn listLabel(ui_ptr: *Ui, src: std.builtin.SourceLocation, row: ListRow, label_text: []const u8, opts: ListLabelOptions) void {
    _ = opts;
    _ = label(ui_ptr, src, label_text, .{
        .hit_passthrough = true,
        .style = .body,
        .color = if (row.selected) .on_accent else .primary,
        .layout = .{ .main = .{ .grow = 1 } },
    });
}

pub const ListLabelOptions = struct { icon: ?theme.Icon = null };

fn listSpacer(ui_ptr: *Ui, h: f32) void {
    const id = ui_ptr.id(@src(), null);
    _ = ui_ptr.leaf(id, .{ .layout = .{ .kind = .leaf, .main = .fixedSize(h), .cross = .fill, .content = .{ .size = .{ .x = 0, .y = h } } } });
}

pub fn endList(ui_ptr: *Ui, iter: *ListIter) ListResult {
    if (iter.open_row) {
        ui_ptr.endRow();
        ui_ptr.popId();
    }
    const limit = if (iter.last > iter.first) iter.last else iter.count;
    if (limit < iter.count) listSpacer(ui_ptr, @as(f32, @floatFromInt(iter.count - limit)) * iter.row_h);
    ui_ptr.endColumn();
    _ = endScrollView(ui_ptr, .{ .id = iter.scroll_id, .offset = .{}, .viewport = null, .line = iter.row_h });
    var res = ListResult{ .selection = iter.ctrl.selection(), .focus_index = if (iter.ctrl.focus) |f| f.index else iter.focused_index };
    if (iter.opts.selection) |sel| {
        var n: usize = 0;
        var idx: usize = iter.first;
        while (idx < limit) : (idx += 1) {
            if (sel.contains(iter.opts.data.keyAt(idx))) n += 1;
        }
        res.selected_visible = n;
    }
    return res;
}

// ---------------------------------------------------------------------------
// tree / table（文档 API；行节点按可见窗口虚拟化）
// ---------------------------------------------------------------------------

pub const TreeNode = enum(u64) { root = 0, _ };
pub const LoadState = enum { loaded, loading };

pub const TreeModel = struct {
    ctx: ?*anyopaque = null,
    child_count: *const fn (ctx: ?*anyopaque, node: TreeNode) usize,
    child_at: *const fn (ctx: ?*anyopaque, node: TreeNode, index: usize) TreeNode,
    has_children: *const fn (ctx: ?*anyopaque, node: TreeNode) bool,
    key_of: *const fn (ctx: ?*anyopaque, node: TreeNode) ItemKey,
    text_of: ?*const fn (ctx: ?*anyopaque, node: TreeNode) []const u8 = null,
    str_key_of: ?*const fn (ctx: ?*anyopaque, node: TreeNode) []const u8 = null,
    load_state: ?*const fn (ctx: ?*anyopaque, node: TreeNode) LoadState = null,
    version: u64 = 0,
};

pub const ExpandedSet = struct {
    allocator: std.mem.Allocator,
    keys: std.ArrayListUnmanaged(ItemKey) = .empty,
    revision: u64 = 0,
    pub fn init(allocator: std.mem.Allocator) ExpandedSet {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *ExpandedSet) void {
        self.keys.deinit(self.allocator);
    }
    pub fn contains(self: *const ExpandedSet, key: ItemKey) bool {
        for (self.keys.items) |k| if (k == key) return true;
        return false;
    }
    pub fn set(self: *ExpandedSet, key: ItemKey, expanded: bool, _: ?[]const u8) error{OutOfMemory}!void {
        if (expanded) {
            if (!self.contains(key)) {
                try self.keys.append(self.allocator, key);
                self.revision +%= 1;
            }
        } else {
            var i: usize = 0;
            while (i < self.keys.items.len) : (i += 1) {
                if (self.keys.items[i] == key) {
                    _ = self.keys.orderedRemove(i);
                    self.revision +%= 1;
                    return;
                }
            }
        }
    }
    pub fn clear(self: *ExpandedSet) void {
        self.keys.clearRetainingCapacity();
        self.revision +%= 1;
    }
    pub fn len(self: *const ExpandedSet) usize {
        return self.keys.items.len;
    }
};

pub const TreeOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    mode: SelectionMode = .single,
    selection: ?*Selection = null,
    expanded: ?*ExpandedSet = null,
    persist: ?[]const u8 = null,
    initially_expanded_depth: u8 = 0,
    activate_parents: bool = false,
    changed: []const TreeNode = &.{},
    alternate_rows: bool = false,
    empty_text: ?[]const u8 = null,
    scrollbar: layout.BarPolicy = .auto,
    tooltip_on_truncate: bool = true,
    layout: layout.ItemOptions = .{},
};

pub const TreeRow = struct {
    index: usize,
    key: ItemKey,
    node: TreeNode,
    depth: u16,
    has_children: bool,
    expanded: bool,
    selected: bool,
    focused: bool,
    hovered: bool,
    text_color: theme.ColorToken,
};

pub const Toggle = struct { node: TreeNode, key: ItemKey, expanded: bool };
pub const TreeContext = struct { node: ?TreeNode, key: ?ItemKey, pos: core.Vec2, anchor: core.Rect, from_keyboard: bool };
pub const TreeResult = struct {
    hovered: bool = false,
    focused: bool = false,
    focus_key: ?ItemKey = null,
    selection: ?*Selection = null,
    selected_visible: usize = 0,
    selection_changed: bool = false,
    activated: ?TreeNode = null,
    toggled: []const Toggle = &.{},
    context_menu: ?TreeContext = null,
};

fn dummyTreeCount(_: ?*anyopaque, _: TreeNode) usize {
    return 0;
}
fn dummyTreeAt(_: ?*anyopaque, _: TreeNode, _: usize) TreeNode {
    return .root;
}
fn dummyTreeHas(_: ?*anyopaque, _: TreeNode) bool {
    return false;
}
fn dummyTreeKey(_: ?*anyopaque, _: TreeNode) ItemKey {
    return 0;
}

const TreeCtrlBox = struct {
    ctrl: TreeController,
    pub fn init(allocator: std.mem.Allocator) TreeCtrlBox {
        return .{ .ctrl = TreeController.init(allocator, .{ .child_count = dummyTreeCount, .child_at = dummyTreeAt, .has_children = dummyTreeHas, .key_of = dummyTreeKey }, .{}) };
    }
    pub fn deinit(self: *TreeCtrlBox) void {
        self.ctrl.deinit();
    }
};

const TreeRuntime = struct {
    ui_ptr: *Ui,
    ctrl: *TreeController,
    cursor: usize = 0,
    first: usize = 0,
    last: usize = 0,
    row_h: f32 = 22,
    scroll: ScrollViewHandle,
    open_row: bool = false,
    selection_changed: bool = false,
    activated: ?TreeNode = null,

    fn nextRow(self: *TreeRuntime) ?TreeRow {
        if (self.open_row) {
            self.ui_ptr.endRow();
            self.ui_ptr.popId();
            self.open_row = false;
        }
        if (self.cursor >= @min(self.last, self.ctrl.rows.items.len)) return null;
        const i = self.cursor;
        self.cursor += 1;
        const e = self.ctrl.rows.items[i];
        const indent = @as(f32, @floatFromInt(e.depth)) * self.ui_ptr.theme_ptr.metric(.indent);
        self.ui_ptr.pushId(ui.Key.int(e.key));
        const row_id = self.ui_ptr.beginRow(@src(), .{ .main = .fixedSize(self.row_h), .cross = .fill, .padding = .{ .l = indent, .t = 0, .r = 4, .b = 0 }, .cross_align = .center });
        const it = self.ui_ptr.interact(row_id, .{ .sense = .{ .hover = true, .click = true }, .cursor = .arrow });
        for (self.ui_ptr.events(row_id)) |ev| switch (ev) {
            .press => |p| {
                if (p.button == .left and e.has_children) {
                    if (self.ctrl.pointerPressArrow(i, p.pos.x)) |tu| {
                        _ = tu;
                        self.ui_ptr.invalidate(.build);
                        continue;
                    }
                }
                const tu = self.ctrl.pointerPress(i, p.button, p.mods);
                self.selection_changed = self.selection_changed or tu.selection_changed;
            },
            .key_down => |k| {
                const tu = self.ctrl.keyDown(k.key, k.mods, k.repeat, self.ui_ptr.now());
                self.selection_changed = self.selection_changed or tu.selection_changed;
                if (tu.activated) |act| self.activated = act;
                if (tu.toggled.len > 0) self.ui_ptr.invalidate(.build);
            },
            else => {},
        };
        if (it.double_clicked) {
            const tu = self.ctrl.doubleClick(i, .{});
            if (tu.activated) |act| self.activated = act;
            if (tu.toggled.len > 0) self.ui_ptr.invalidate(.build);
        }
        const selected = self.ctrl.selection().contains(e.key);
        if (self.ui_ptr.getNode(row_id)) |node| {
            const props = self.ui_ptr.treeAlloc().create(ListRowProps) catch null;
            if (props) |pr| {
                pr.* = .{ .selected = selected, .hovered = it.hovered };
                node.paint = paintListRow;
                node.props = pr;
                node.paint_key = @as(u64, @intFromBool(selected)) | (@as(u64, @intFromBool(it.hovered)) << 1);
            }
        }
        self.open_row = true;
        return .{
            .index = i,
            .key = e.key,
            .node = e.node,
            .depth = e.depth,
            .has_children = e.has_children,
            .expanded = e.expanded,
            .selected = selected,
            .focused = if (self.ctrl.focus) |f| f.index == i else false,
            .hovered = it.hovered,
            .text_color = if (selected) .text_on_accent else .text_primary,
        };
    }
};

pub const TreeIter = struct {
    rt: *TreeRuntime,
    pub fn next(self: *TreeIter) ?TreeRow {
        return self.rt.nextRow();
    }
};

pub fn beginTree(ui_ptr: *Ui, src: std.builtin.SourceLocation, model: TreeModel, opts: TreeOptions) TreeIter {
    const id = ui_ptr.id(src, opts.key);
    const scroll = beginScrollView(ui_ptr, src, .{
        .key = opts.key,
        .debug_name = opts.debug_name,
        .enabled = opts.enabled,
        .axes = .vertical,
        .bar_v = opts.scrollbar,
        .layout = .{ .main = .{ .grow = 1 }, .cross = .fill },
    });
    if (ui_ptr.getNode(scroll.id)) |sn| {
        sn.flags.layout_feedback = true;
        _ = ui_ptr.lastRectPx(scroll.id);
    }
    _ = ui_ptr.beginColumn(src, .{ .main = .fit, .cross = .fill, .gap = .none });
    const tbox = ui_ptr.retained(TreeCtrlBox, id, .sticky);
    tbox.ctrl.model = model;
    tbox.ctrl.opts = opts;
    const row_h = ui_ptr.theme_ptr.metric(.row_h);
    const viewport_h: f32 = if (scroll.viewport) |v| v.y else 240;
    tbox.ctrl.setViewport(if (scroll.viewport) |v| v.x else 320, viewport_h);
    tbox.ctrl.offset = scroll.offset.y;
    tbox.ctrl.correct();
    const total = tbox.ctrl.rows.items.len;
    const first: usize = if (total == 0) 0 else @min(total - 1, @as(usize, @intFromFloat(@max(0, @floor(scroll.offset.y / @max(1, row_h))))));
    const visible: usize = @max(1, @as(usize, @intFromFloat(@ceil(viewport_h / @max(1, row_h)))) + 2);
    const last = @min(total, first + visible);
    const rt = ui_ptr.treeAlloc().create(TreeRuntime) catch @panic("nano_gui: tree runtime");
    rt.* = .{ .ui_ptr = ui_ptr, .ctrl = &tbox.ctrl, .first = first, .last = last, .cursor = first, .row_h = row_h, .scroll = scroll };
    if (first > 0) listSpacer(ui_ptr, @as(f32, @floatFromInt(first)) * row_h);
    ui_ptr.aux_ptr = rt;
    ui_ptr.aux_id = id;
    return .{ .rt = rt };
}

pub fn endTree(ui_ptr: *Ui) TreeResult {
    const raw = ui_ptr.aux_ptr orelse return .{};
    const rt: *TreeRuntime = @ptrCast(@alignCast(raw));
    if (rt.open_row) {
        ui_ptr.endRow();
        ui_ptr.popId();
    }
    const total = rt.ctrl.rows.items.len;
    if (rt.last < total) listSpacer(ui_ptr, @as(f32, @floatFromInt(total - rt.last)) * rt.row_h);
    ui_ptr.endColumn();
    _ = endScrollView(ui_ptr, rt.scroll);
    ui_ptr.aux_ptr = null;
    var res = TreeResult{
        .selection = rt.ctrl.selection(),
        .focus_key = if (rt.ctrl.focus) |f| f.key else null,
        .selection_changed = rt.selection_changed,
        .activated = rt.activated,
        .toggled = rt.ctrl.toggles.items,
    };
    const sel = rt.ctrl.selection();
    var n: usize = 0;
    var i: usize = rt.first;
    const lim = @min(rt.last, total);
    while (i < lim) : (i += 1) if (sel.contains(rt.ctrl.rows.items[i].key)) {
        n += 1;
    };
    res.selected_visible = n;
    return res;
}

const TreeArrowProps = struct {
    color: theme.ColorToken,
    rotation: f32,
};

fn paintTreeArrow(ctx: *PaintCtx, node: *const Node) void {
    const p: *const TreeArrowProps = @ptrCast(@alignCast(node.props.?));
    const r = ctx.rect(node);
    const t = ctx.draw.theme;
    const s = @min(r.w, r.h);
    const cx = r.x + r.w * 0.5;
    const cy = r.y + r.h * 0.5;
    const rot = ctx.ui.animationCurrent(node.id, 0) orelse p.rotation;
    const ca = @cos(rot);
    const sa = @sin(rot);
    const pts = [_]core.Vec2{
        .{ .x = -0.12, .y = -0.25 },
        .{ .x = 0.18, .y = 0 },
        .{ .x = -0.12, .y = 0.25 },
    };
    var path = ctx.draw.canvas.path();
    for (pts, 0..) |pt, i| {
        const x = pt.x * s;
        const y = pt.y * s;
        const rx = x * ca - y * sa + cx;
        const ry = x * sa + y * ca + cy;
        if (i == 0) path.moveTo(.{ .x = rx, .y = ry }) else path.lineTo(.{ .x = rx, .y = ry });
    }
    ctx.draw.canvas.strokePath(&path, t.color(p.color), 1.5, .round, .round);
}

fn treeArrow(ui_ptr: *Ui, src: std.builtin.SourceLocation, row: TreeRow) void {
    const t = ui_ptr.theme_ptr;
    const id = ui_ptr.id(src, ui.Key.str("tree-chevron"));
    const target: f32 = if (row.expanded) std.math.pi * 0.5 else 0;
    _ = ui_ptr.animate(id, 0, target, .{ .duration = .normal, .easing = .out, .level = .paint });
    const props = ui_ptr.treeAlloc().create(TreeArrowProps) catch @panic("nano_gui: tree arrow props");
    props.* = .{
        .color = if (row.selected) .text_on_accent else .text_secondary,
        .rotation = target,
    };
    _ = ui_ptr.leaf(id, .{
        .layout = .{ .kind = .leaf, .main = .fixedSize(t.metric(.icon_sm)), .cross = .fit, .content = .{ .size = .{ .x = t.metric(.icon_sm), .y = t.metric(.icon_sm) } } },
        .flags = .{ .hit_passthrough = true },
        .paint = paintTreeArrow,
        .props = props,
        .paint_key = @as(u64, @intFromBool(row.has_children)) | (@as(u64, @intFromBool(row.selected)) << 1),
    });
    if (ui_ptr.getNode(id)) |n| n.debug_name = "tree-arrow";
}

pub fn treeLabel(ui_ptr: *Ui, src: std.builtin.SourceLocation, row: TreeRow, label_text: []const u8, opts: ListLabelOptions) void {
    _ = opts;
    treeArrow(ui_ptr, src, row);
    _ = label(ui_ptr, src, label_text, .{
        .key = ui.Key.str("tree-text"),
        .hit_passthrough = true,
        .style = .body,
        .color = if (row.selected) .on_accent else .primary,
        .layout = .{ .main = .{ .grow = 1 } },
    });
}

// 表格控件（table） ---------------------------------------------------------

pub const HAlign = enum { left, right, center };
pub const SortDir = enum { asc, desc };
pub const GridLines = enum { none, horizontal, vertical, both };

pub const TableColumn = struct {
    title: []const u8 = "",
    width: layout.ColumnWidth = .{ .fixed = 120 },
    min: f32 = 0,
    max: f32 = std.math.inf(f32),
    h_align: HAlign = .left,
    font: theme.FontToken = .body,
    sortable: bool = false,
    resizable: bool = true,
    hidden: bool = false,
};
pub const TableSort = struct { column: ?u16 = null, dir: SortDir = .asc };
pub const TableData = struct {
    ctx: ?*anyopaque = null,
    key_of: ?*const fn (ctx: ?*anyopaque, index: usize) ItemKey = null,
    index_of: ?*const fn (ctx: ?*anyopaque, key: ItemKey) ?usize = null,
    cell_text: ?*const fn (ctx: ?*anyopaque, row: usize, column: u16) []const u8 = null,
    prefix_search: ?*const fn (ctx: ?*anyopaque, prefix: []const u8, start: usize) ?usize = null,
};
pub const TableOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    mode: SelectionMode = .multi,
    selection: ?*Selection = null,
    data: TableData = .{},
    row_height: ?f32 = null,
    alternate_rows: bool = false,
    grid: GridLines = .horizontal,
    empty_text: ?[]const u8 = null,
    scrollbar_v: layout.BarPolicy = .auto,
    scrollbar_h: layout.BarPolicy = .auto,
    sort: ?*TableSort = null,
    allow_unsorted: bool = false,
    reorder_columns: bool = true,
    header_menu: bool = false,
    persist: ?[]const u8 = null,
    tooltip_on_truncate: bool = true,
    layout: layout.ItemOptions = .{},
};
pub const table_column_kind: u32 = 0x54424C43;
pub const TableCell = struct {
    column: u16,
    display: u16 = 0,
    width: f32 = 0,
    h_align: HAlign = .left,
    font: theme.FontToken = .body,
    selected: bool = false,
    hovered: bool = false,
    text_color: theme.ColorToken = .text_primary,
};
pub const CellIter = struct {
    row_index: usize,
    columns: []const TableColumn,
    widths: []const f32,
    hidden: []const bool,
    selected: bool,
    hovered: bool,
    text_color: theme.ColorToken,
    index: usize = 0,
    pub fn next(self: *CellIter) ?TableCell {
        while (self.index < self.columns.len) {
            const i = self.index;
            self.index += 1;
            if (i < self.hidden.len and self.hidden[i]) continue;
            return .{
                .column = @intCast(i),
                .display = @intCast(i),
                .width = if (i < self.widths.len) self.widths[i] else 120,
                .h_align = self.columns[i].h_align,
                .font = self.columns[i].font,
                .selected = self.selected,
                .hovered = self.hovered,
                .text_color = self.text_color,
            };
        }
        return null;
    }
};
pub const TableRow = struct {
    index: usize,
    key: ItemKey,
    selected: bool,
    focused: bool,
    hovered: bool,
    text_color: theme.ColorToken = .text_primary,
    columns: []const TableColumn = &.{},
    widths: []const f32 = &.{},
    hidden: []const bool = &.{},
    pub fn cells(self: *const TableRow) CellIter {
        return .{ .row_index = self.index, .columns = self.columns, .widths = self.widths, .hidden = self.hidden, .selected = self.selected, .hovered = self.hovered, .text_color = self.text_color };
    }
};
pub const TableResult = struct {
    hovered: bool = false,
    focused: bool = false,
    focus_index: ?usize = null,
    selection: ?*Selection = null,
    selected_visible: usize = 0,
    sort: TableSort = .{},
    resizing: ?u16 = null,
    selection_changed: bool = false,
    activated: ?usize = null,
    context_menu: ?struct { row: ?usize, column: ?u16, pos: core.Vec2, anchor: core.Rect, from_keyboard: bool } = null,
    header_context: ?struct { column: ?u16, pos: core.Vec2, anchor: core.Rect } = null,
    sort_changed: ?struct { column: u16, dir: ?SortDir } = null,
    column_resized: ?struct { column: u16, width: f32 } = null,
    columns_reordered: bool = false,
};
const TableRuntime = struct {
    ui_ptr: *Ui,
    opts: TableOptions,
    columns: []const TableColumn,
    widths: []const f32,
    hidden: []const bool,
    count: usize,
    cursor: usize,
    first: usize,
    last: usize,
    row_h: f32,
    scroll: ScrollViewHandle,
    ctrl: *ListController,
    open_row: bool = false,

    fn nextRow(self: *TableRuntime) ?TableRow {
        if (self.open_row) {
            self.ui_ptr.endRow();
            self.ui_ptr.popId();
            self.open_row = false;
        }
        if (self.cursor >= self.last) return null;
        const i = self.cursor;
        self.cursor += 1;
        const key = if (self.opts.data.key_of) |f| f(self.opts.data.ctx, i) else @as(ItemKey, @intCast(i));
        self.ui_ptr.pushId(ui.Key.int(key));
        const row_id = self.ui_ptr.beginRow(@src(), .{ .main = .fixedSize(self.row_h), .cross = .fill, .padding = core.Insets.symmetric(4, 0), .cross_align = .center });
        const it = self.ui_ptr.interact(row_id, .{ .sense = .{ .hover = true, .click = true }, .cursor = .arrow });
        var selection_changed = false;
        for (self.ui_ptr.events(row_id)) |ev| switch (ev) {
            .press => |p| {
                const u = self.ctrl.pointerPress(i, p.button, p.mods, self.count);
                selection_changed = selection_changed or u.selection_changed;
            },
            .release => |r| {
                const u = self.ctrl.pointerRelease(i, r.inside, if (it.double_clicked) 2 else 1, r.mods, self.count);
                selection_changed = selection_changed or u.selection_changed;
            },
            else => {},
        };
        if (selection_changed) self.ui_ptr.invalidate(.build);
        const selected = self.ctrl.selection().contains(key);
        if (self.ui_ptr.getNode(row_id)) |node| {
            const props = self.ui_ptr.treeAlloc().create(ListRowProps) catch null;
            if (props) |pr| {
                pr.* = .{ .selected = selected, .hovered = it.hovered };
                node.paint = paintListRow;
                node.props = pr;
                node.paint_key = @as(u64, @intFromBool(selected)) | (@as(u64, @intFromBool(it.hovered)) << 1);
            }
        }
        self.open_row = true;
        return .{
            .index = i,
            .key = key,
            .selected = selected,
            .focused = false,
            .hovered = it.hovered,
            .text_color = if (selected) .text_on_accent else .text_primary,
            .columns = self.columns,
            .widths = self.widths,
            .hidden = self.hidden,
        };
    }
};

pub const TableIter = struct {
    rt: *TableRuntime,
    id: ui.WidgetId = .none,
    pub fn next(self: *TableIter) ?TableRow {
        return self.rt.nextRow();
    }
};

const TableHiddenState = struct {
    mask: u64 = 0,
};

pub fn beginTable(ui_ptr: *Ui, src: std.builtin.SourceLocation, columns: []const TableColumn, count: usize, opts: TableOptions) TableIter {
    const id = ui_ptr.id(src, opts.key);
    const t = ui_ptr.theme_ptr;
    const row_h = opts.row_height orelse t.metric(.row_h);
    const hid_st = ui_ptr.stateSticky(TableHiddenState, id, .{});
    const hidden = ui_ptr.treeAlloc().alloc(bool, columns.len) catch @panic("nano_gui: table hidden");
    for (columns, 0..) |col, i| {
        const dyn_hid = if (i < 64) (hid_st.mask & (@as(u64, 1) << @intCast(i))) != 0 else false;
        hidden[i] = col.hidden or dyn_hid;
    }
    _ = ui_ptr.beginColumn(src, .{ .main = .{ .grow = 1 }, .cross = .fill, .gap = .none });
    const tmp = ui_ptr.treeAlloc().alloc(i32, columns.len) catch @panic("nano_gui: table widths");
    const widths = ui_ptr.treeAlloc().alloc(f32, columns.len) catch @panic("nano_gui: table widths");
    const header_w = ui_ptr.treeAlloc().alloc(i32, columns.len) catch @panic("nano_gui: table widths");
    @memset(header_w, 0);
    const approx_w: i32 = @intFromFloat(@max(200, @as(f32, @floatFromInt(ui_ptr.viewport.w)) - 32));
    const layout_cols = ui_ptr.treeAlloc().alloc(layout.Column, columns.len) catch @panic("nano_gui: table columns");
    for (columns, 0..) |col, i| {
        layout_cols[i] = if (hidden[i]) .{ .width = .{ .fixed = 0 }, .min = 0, .max = 0 } else .{ .width = col.width, .min = col.min, .max = col.max };
    }
    layout.solveColumns(ui_ptr.frameAlloc(), layout_cols, header_w, approx_w, true, 0, ui_ptr.scale, tmp);
    for (tmp, 0..) |v, i| widths[i] = if (hidden[i]) 0 else @as(f32, @floatFromInt(v));
    ui_ptr.pushId(ui.Key.str("table-header"));
    _ = ui_ptr.beginRow(src, .{ .main = .fixedSize(t.metric(.header_h)), .cross = .fill, .gap = .none, .cross_align = .center });
    for (columns, 0..) |col, i| {
        if (hidden[i]) continue;
        const sort_icon: ?theme.Icon = if (opts.sort) |sp| blk: {
            if (sp.column == @as(u16, @intCast(i))) {
                break :blk .{ .mark = if (sp.dir == .asc) .sort_asc else .sort_desc };
            }
            break :blk null;
        } else null;
        if (col.sortable and opts.sort != null) {
            const hb = button(ui_ptr, @src(), col.title, .{
                .key = ui.Key.int(i + 0x54424c00),
                .variant = .quiet,
                .icon = sort_icon,
                .layout = .{ .main = .fixedSize(widths[i] / ui_ptr.scale) },
            });
            if (hb.clicked) {
                const sp = opts.sort.?;
                if (sp.column == @as(u16, @intCast(i))) {
                    sp.dir = if (sp.dir == .asc) .desc else .asc;
                } else {
                    sp.column = @intCast(i);
                    sp.dir = .asc;
                }
            }
        } else {
            _ = label(ui_ptr, @src(), col.title, .{ .key = ui.Key.int(i + 0x54424c00), .style = .body, .color = .primary, .icon = sort_icon, .layout = .{ .main = .fixedSize(widths[i] / ui_ptr.scale) } });
        }
    }
    ui_ptr.endRow();
    ui_ptr.popId();
    const scroll = beginScrollView(ui_ptr, src, .{
        .key = opts.key,
        .debug_name = opts.debug_name,
        .enabled = opts.enabled,
        .axes = .vertical,
        .bar_v = opts.scrollbar_v,
        .layout = .{ .main = .{ .grow = 1 }, .cross = .fill },
    });
    if (ui_ptr.getNode(scroll.id)) |sn| {
        sn.flags.layout_feedback = true;
        _ = ui_ptr.lastRectPx(scroll.id);
    }
    const cbox = ui_ptr.retained(ListCtrlBox, id, .sticky);
    cbox.ctrl.opts = .{
        .mode = opts.mode,
        .selection = opts.selection,
        .data = .{ .ctx = opts.data.ctx, .key_of = opts.data.key_of, .index_of = opts.data.index_of },
        .row_height = row_h,
    };
    const ctrl = &cbox.ctrl;
    const viewport_h: f32 = if (scroll.viewport) |v| v.y else 240;
    ctrl.setViewport(if (scroll.viewport) |v| v.x else 800, viewport_h, count);
    ctrl.offset = scroll.offset.y;
    ctrl.correct(count);
    _ = ui_ptr.beginColumn(src, .{ .main = .fit, .cross = .fill, .gap = .none });
    const first: usize = if (count == 0) 0 else @min(count - 1, @as(usize, @intFromFloat(@max(0, @floor(scroll.offset.y / @max(1, row_h))))));
    const visible: usize = @max(1, @as(usize, @intFromFloat(@ceil(viewport_h / @max(1, row_h)))) + 2);
    const last = @min(count, first + visible);
    core.stats.gauge("list.virtual_cells").* = (last - first) * columns.len;
    if (first > 0) listSpacer(ui_ptr, @as(f32, @floatFromInt(first)) * row_h);
    const rt = ui_ptr.treeAlloc().create(TableRuntime) catch @panic("nano_gui: table runtime");
    rt.* = .{ .ui_ptr = ui_ptr, .opts = opts, .columns = columns, .widths = widths, .hidden = hidden, .count = count, .cursor = first, .first = first, .last = last, .row_h = row_h, .scroll = scroll, .ctrl = ctrl };
    ui_ptr.aux_ptr = rt;
    ui_ptr.aux_id = id;
    return .{ .rt = rt, .id = id };
}

pub fn endTable(ui_ptr: *Ui) TableResult {
    const raw = ui_ptr.aux_ptr orelse return .{};
    const rt: *TableRuntime = @ptrCast(@alignCast(raw));
    if (rt.open_row) {
        ui_ptr.endRow();
        ui_ptr.popId();
    }
    if (rt.last < rt.count) listSpacer(ui_ptr, @as(f32, @floatFromInt(rt.count - rt.last)) * rt.row_h);
    ui_ptr.endColumn();
    _ = endScrollView(ui_ptr, rt.scroll);
    ui_ptr.endColumn();
    ui_ptr.aux_ptr = null;
    return .{ .selection = rt.ctrl.selection(), .focus_index = if (rt.ctrl.focus) |f| f.index else null };
}

pub fn tableCellText(ui_ptr: *Ui, src: std.builtin.SourceLocation, cell: TableCell, label_text: []const u8, opts: struct { icon: ?theme.Icon = null }) void {
    _ = label(ui_ptr, src, label_text, .{
        .key = ui.Key.int(cell.column + 1),
        .hit_passthrough = true,
        .style = .body,
        .color = if (cell.selected) .on_accent else .primary,
        .icon = opts.icon,
        .layout = .{ .main = .fixedSize(cell.width / ui_ptr.scale) },
    });
}

/// 切换表格指定列的隐藏状态（REQ-W-TABLE-016）。线程：界面线程。
pub fn setTableColumnHidden(ui_ptr: *Ui, table_id: core.WidgetId, col: u16, hide: bool) void {
    if (col >= 64) return;
    const st = ui_ptr.stateSticky(TableHiddenState, table_id, .{});
    const bit = @as(u64, 1) << @intCast(col);
    if (hide) st.mask |= bit else st.mask &= ~bit;
    ui_ptr.invalidate(.build);
}

// ---------------------------------------------------------------------------
// menu bar / menu / items（窗口内弹出层；X11 下由原生窗口宿主呈现）
// ---------------------------------------------------------------------------

pub const MenuBarOptions = struct { key: ?ui.Key = null, debug_name: ?[]const u8 = null, enabled: bool = true, layout: layout.ItemOptions = .{} };
pub const MenuOptions = struct { key: ?ui.Key = null, debug_name: ?[]const u8 = null, enabled: bool = true, icon: ?theme.Icon = null, layout: layout.ItemOptions = .{} };
pub const MenuItemOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    icon: ?theme.Icon = null,
    shortcut_text: ?[]const u8 = null,
    checked: ?bool = null,
    radio: bool = false,
    command: ?input.CommandId = null,
    layout: layout.ItemOptions = .{},
};
pub const MenuItemResult = struct { hovered: bool = false, highlighted: bool = false, clicked: bool = false };
pub const ContextMenuOptions = struct { key: ?ui.Key = null, debug_name: ?[]const u8 = null, enabled: bool = true };
pub const MenuBarHandle = struct { id: core.WidgetId };
pub const MenuHandle = struct { id: core.WidgetId, open: bool };

pub fn beginMenuBar(ui_ptr: *Ui, src: std.builtin.SourceLocation, opts: MenuBarOptions) MenuBarHandle {
    var o = layout.ContainerOptions{
        .debug_name = opts.debug_name,
        .main = .fixedSize(24),
        .cross = .fill,
        .padding = core.Insets.symmetric(4, 2),
        .gap = .xs,
        .cross_align = .center,
    };
    if (opts.layout.main) |v| o.main = v;
    if (opts.layout.cross) |v| o.cross = v;
    const id = ui_ptr.beginRow(src, o);
    if (ui_ptr.getNode(id)) |n| {
        n.paint = paintMenuBar;
        n.paint_key = 0x4d454e55;
    }
    return .{ .id = id };
}
pub fn endMenuBar(ui_ptr: *Ui) void {
    ui_ptr.endRow();
}
fn paintMenuBar(ctx: *PaintCtx, node: *const Node) void {
    theme.drawPanel(&ctx.draw, ctx.rect(node), .radius_container);
}

pub fn beginMenu(ui_ptr: *Ui, src: std.builtin.SourceLocation, label_text: []const u8, opts: MenuOptions) bool {
    const id = ui_ptr.id(src, opts.key);
    const st = ui_ptr.stateSticky(bool, id, false);
    if (!opts.enabled) {
        _ = button(ui_ptr, src, label_text, .{ .variant = .quiet, .enabled = false });
        return false;
    }
    const r = button(ui_ptr, src, label_text, .{ .variant = .quiet, .key = opts.key });
    if (r.clicked) {
        st.* = !st.*;
        ui_ptr.open_menu = if (st.*) id else .none;
    } else if (ui_ptr.open_menu != .none and ui_ptr.open_menu != id and r.hovered) {
        // 菜单已展开时悬停同级顶层菜单自动切换展开（REQ-W-MENU-005）。
        ui_ptr.open_menu = id;
        st.* = true;
    }
    if (ui_ptr.open_menu != id) st.* = false;
    if (!st.*) return false;
    const anchor = ui_ptr.lastRect(id) orelse core.Rect{ .x = 0, .y = 0, .w = 80, .h = 24 };
    const popup_id = ui_ptr.id(src, ui.Key.int(id.raw() ^ 0x9e3779b9));
    _ = ui_ptr.beginPopup(popup_id, .{ .kind = .menu, .anchor = anchor, .anchor_id = id, .placement = .{ .side = .below, .align_ = .start }, .gap = .none, .owner = id });
    return true;
}
pub fn endMenu(ui_ptr: *Ui) void {
    ui_ptr.endPopup();
}
pub fn menuItem(ui_ptr: *Ui, src: std.builtin.SourceLocation, label_text: []const u8, opts: MenuItemOptions) MenuItemResult {
    const item_icon: ?theme.Icon = if (opts.checked == true)
        .{ .mark = if (opts.radio) .radio_dot else .check }
    else
        opts.icon;
    const full_label = if (opts.shortcut_text) |sc|
        std.fmt.allocPrint(ui_ptr.frameAlloc(), "{s}  {s}", .{ label_text, sc }) catch label_text
    else
        label_text;
    const r = button(ui_ptr, src, full_label, .{ .variant = .quiet, .key = opts.key, .enabled = opts.enabled, .icon = item_icon, .layout = .{ .cross = .fill } });
    const result = MenuItemResult{ .hovered = r.hovered, .clicked = r.clicked };
    if (r.clicked) {
        if (opts.command) |cmd| ui_ptr.invokeCommand(cmd);
    }
    if (r.clicked and ui_ptr.open_menu != .none) {
        const st = ui_ptr.stateSticky(bool, ui_ptr.open_menu, false);
        st.* = false;
        ui_ptr.open_menu = .none;
    }
    return result;
}
pub fn menuSeparator(ui_ptr: *Ui, src: std.builtin.SourceLocation) void {
    _ = separator(ui_ptr, src, .{ .layout = .{ .cross = .fill } });
}
const ContextMenuState = struct { request: ?input.ContextRequest = null };
pub fn openContextMenu(ui_ptr: *Ui, owner: core.WidgetId, request: input.ContextRequest) void {
    const st = ui_ptr.stateSticky(ContextMenuState, owner, .{});
    st.request = request;
}
pub fn beginContextMenu(ui_ptr: *Ui, src: std.builtin.SourceLocation, owner: core.WidgetId, opts: ContextMenuOptions) bool {
    const st = ui_ptr.stateSticky(ContextMenuState, owner, .{});
    const req = st.request orelse return false;
    const popup_id = ui_ptr.id(src, opts.key orelse ui.Key.int(owner.raw() ^ 0x517cc1b7));
    _ = ui_ptr.beginPopup(popup_id, .{ .kind = .context_menu, .anchor = req.anchor, .anchor_id = owner, .owner = owner, .placement = .{ .side = .below, .align_ = .start } });
    return true;
}
pub fn endContextMenu(ui_ptr: *Ui) void {
    ui_ptr.endPopup();
}

// ---------------------------------------------------------------------------
// 对话框正文与按钮行（dialog body / button row）
// ---------------------------------------------------------------------------

pub const DialogBodyOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    gap: theme.Gap = .md,
    min_width: ?f32 = null,
    layout: layout.ItemOptions = .{},
};
pub fn beginDialogBody(ui_ptr: *Ui, src: std.builtin.SourceLocation, opts: DialogBodyOptions) core.WidgetId {
    var o = layout.ContainerOptions{
        .debug_name = opts.debug_name,
        .padding = core.Insets.all(ui_ptr.theme_ptr.metric(.pad_dialog)),
        .gap = opts.gap,
        .main = .{ .grow = 1 },
        .cross = .fit,
    };
    if (opts.layout.main) |v| o.main = v;
    if (opts.layout.cross) |v| o.cross = v;
    const id = ui_ptr.beginColumn(src, o);
    if (opts.min_width) |mw| if (ui_ptr.getNode(id)) |n| {
        n.layout.cross_min = mw;
    };
    return id;
}
pub fn endDialogBody(ui_ptr: *Ui) void {
    ui_ptr.endColumn();
}
pub const ButtonRole = enum { normal, default, cancel, default_and_cancel };
pub const DialogButton = struct {
    label: []const u8,
    code: u32,
    role: ButtonRole = .normal,
    enabled: bool = true,
    debug_name: ?[]const u8 = null,
};
pub fn dialogButtons(ui_ptr: *Ui, src: std.builtin.SourceLocation, buttons: []const DialogButton) ?u32 {
    if (buttons.len == 0) return null;
    const t = ui_ptr.theme_ptr;
    const scale = ui_ptr.scale;
    var max_w: f32 = t.metric(.button_min_w);
    for (buttons) |b| {
        const sz = text.measure(b.label, styleFor(t, .body), scale, .{});
        max_w = @max(max_w, sz.w + 2 * t.metric(.gap_md));
    }
    const row_id = ui_ptr.beginRow(src, .{ .main = .fit, .cross = .fill, .gap = .md, .justify = .end, .cross_align = .center });
    _ = ui_ptr.interact(row_id, .{ .sense = .{}, .handles = .{ .groups = .{ .enter = true, .escape = true } } });
    var key_enter = false;
    var key_escape = false;
    for (ui_ptr.events(row_id)) |ev| switch (ev) {
        .key_down => |k| {
            if (k.key == .enter) key_enter = true;
            if (k.key == .escape) key_escape = true;
        },
        else => {},
    };
    var result: ?u32 = null;
    for (buttons, 0..) |b, bi| {
        const variant: ButtonVariant = if (b.role == .default or b.role == .default_and_cancel) .accent else .neutral;
        const r = button(ui_ptr, @src(), b.label, .{
            .key = ui.Key.int(bi),
            .variant = variant,
            .enabled = b.enabled,
            .debug_name = b.debug_name,
            .layout = .{ .main = .fixedSize(max_w), .cross = .fit },
        });
        if (r.clicked) result = b.code;
        if (result == null and b.enabled) {
            if ((b.role == .default or b.role == .default_and_cancel) and key_enter) result = b.code;
            if ((b.role == .cancel or b.role == .default_and_cancel) and key_escape) result = b.code;
        }
    }
    ui_ptr.endRow();
    return result;
}

// ---------------------------------------------------------------------------
// 文档 API 便捷入口
// ---------------------------------------------------------------------------

pub fn sliderInt(ui_ptr: *Ui, src: std.builtin.SourceLocation, value: *i32, opts: struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    min: i32 = 0,
    max: i32 = 100,
    step: i32 = 1,
    layout: layout.ItemOptions = .{},
}) SliderResult {
    var f: f32 = @floatFromInt(value.*);
    const r = slider(ui_ptr, src, &f, .{
        .key = opts.key,
        .debug_name = opts.debug_name,
        .enabled = opts.enabled,
        .min = @floatFromInt(opts.min),
        .max = @floatFromInt(opts.max),
        .step = @floatFromInt(opts.step),
        .layout = opts.layout,
    });
    if (r.changed) value.* = @intFromFloat(@round(f));
    return r;
}

pub fn comboBoxEditable(ui_ptr: *Ui, src: std.builtin.SourceLocation, text_buf: *TextBuf, items: ItemSource, opts: ComboBoxEditableOptions) ComboBoxResult {
    const id = ui_ptr.id(src, opts.key);
    const row_id = ui_ptr.beginRow(src, .{ .main = .fit, .cross = .fit, .gap = .xs, .cross_align = .center });
    const r = textInput(ui_ptr, src, text_buf, .{
        .key = opts.key,
        .debug_name = opts.debug_name,
        .enabled = opts.enabled,
        .placeholder = opts.placeholder orelse "",
        .max_len = opts.max_len,
        .layout = .{ .main = .{ .grow = 1 }, .cross = .fill },
    });
    const st = ui_ptr.stateSticky(ComboState, id, .{});
    const picker = button(ui_ptr, @src(), "v", .{ .variant = .quiet, .enabled = opts.enabled });
    ui_ptr.endRow();
    var res = ComboBoxResult{ .id = id, .hovered = r.hovered or picker.hovered, .focused = r.focused, .open = st.open, .changed = r.changed, .committed = r.committed };
    if (opts.enabled and picker.clicked) {
        st.open = !st.open;
        res.open = st.open;
    }
    if (opts.enabled and st.open) {
        const n = items.count();
        const anchor = ui_ptr.lastRect(row_id) orelse core.Rect{ .x = 0, .y = 0, .w = 140, .h = heightFor(ui_ptr.theme_ptr, opts.size) };
        const popup_id = ui_ptr.id(src, ui.Key.int(id.raw() ^ 0x65646974));
        if (ui_ptr.beginPopup(popup_id, .{ .kind = .dropdown, .anchor = anchor, .anchor_id = row_id, .match_anchor_width = true, .min_width = anchor.w, .owner = id })) {
            const show_n = @min(n, @as(u32, opts.max_rows));
            var i: u32 = 0;
            while (i < show_n) : (i += 1) {
                const item_label = items.textAt(i, ui_ptr.treeAlloc());
                const ir = button(ui_ptr, @src(), item_label, .{
                    .key = ui.Key.int(i + 0x65640000),
                    .variant = .quiet,
                    .layout = .{ .cross = .fill },
                });
                if (ir.clicked) {
                    text_buf.set(item_label) catch {};
                    res.picked = i;
                    res.changed = true;
                    res.committed = true;
                    st.open = false;
                    res.open = false;
                }
            }
            ui_ptr.endPopup();
        }
    }
    if (opts.tooltip) |tip| ui_ptr.tooltip(id, tip);
    return res;
}

pub const ComboBoxEditableOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    max_rows: u8 = 10,
    placeholder: ?[]const u8 = null,
    autocomplete: bool = true,
    max_len: ?u32 = null,
    commit_on_blur: bool = true,
    size: ControlSize = .md,
    tooltip: ?[]const u8 = null,
    layout: layout.ItemOptions = .{},
};

pub const ToolbarButtonOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    icon: ?theme.Icon = null,
    show_text: bool = true,
    tooltip: ?[]const u8 = null,
    enabled: bool = true,
    checked: ?bool = null,
    layout: layout.ItemOptions = .{},
};
pub const ToolbarButtonResult = struct { clicked: bool = false, hovered: bool = false, in_overflow: bool = false };

pub fn toolbarButton(ui_ptr: *Ui, src: std.builtin.SourceLocation, label_text: []const u8, opts: ToolbarButtonOptions) ToolbarButtonResult {
    const r = button(ui_ptr, src, if (opts.show_text) label_text else "", .{
        .key = opts.key,
        .debug_name = opts.debug_name,
        .enabled = opts.enabled,
        .variant = .quiet,
        .icon = opts.icon,
        .checked = opts.checked,
        .tooltip = opts.tooltip,
        .layout = opts.layout,
    });
    return .{ .clicked = r.clicked, .hovered = r.hovered };
}

pub const ToolbarCommandOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    show_text: bool = false,
    overflow: enum { menu, pinned } = .menu,
};

pub fn toolbarCommand(ui_ptr: *Ui, src: std.builtin.SourceLocation, cmd: input.CommandId, opts: ToolbarCommandOptions) ToolbarButtonResult {
    const title = ui_ptr.commandTitle(cmd);
    const r = button(ui_ptr, src, if (opts.show_text) title else "", .{
        .key = opts.key,
        .debug_name = opts.debug_name,
        .variant = .quiet,
        .icon = .{ .mark = .more },
        .tooltip = if (title.len > 0) title else null,
    });
    if (r.clicked) ui_ptr.invokeCommand(cmd);
    return .{ .clicked = r.clicked, .hovered = r.hovered };
}

pub fn toolbarSeparator(ui_ptr: *Ui, src: std.builtin.SourceLocation) void {
    _ = separator(ui_ptr, src, .{ .orientation = .vertical });
}
pub fn toolbarSpacer(ui_ptr: *Ui, src: std.builtin.SourceLocation) void {
    _ = ui_ptr.spacer(src, 1);
}
pub fn beginToolbarItem(ui_ptr: *Ui, src: std.builtin.SourceLocation, opts: struct { key: ?ui.Key = null, debug_name: ?[]const u8 = null, enabled: bool = true, layout: layout.ItemOptions = .{} }) core.WidgetId {
    _ = opts.enabled;
    return ui_ptr.beginStack(src, .{ .debug_name = opts.debug_name, .main = .fit, .cross = .fit });
}
pub fn endToolbarItem(ui_ptr: *Ui) void {
    ui_ptr.endStack();
}

pub const StatusPaneOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    grow: f32 = 0,
    width: ?f32 = null,
    @"align": text.Align = .left,
    layout: layout.ItemOptions = .{},
};
pub const StatusPaneResult = struct { hovered: bool = false, clicked: bool = false };

pub fn beginStatusPane(ui_ptr: *Ui, src: std.builtin.SourceLocation, opts: StatusPaneOptions) core.WidgetId {
    var item = opts.layout;
    if (opts.grow > 0) item.main = .{ .grow = opts.grow };
    if (opts.width) |w| item.main = .fixedSize(w);
    const o = layout.ContainerOptions{
        .debug_name = opts.debug_name,
        .main = item.main orelse .fit,
        .cross = item.cross orelse .fill,
        .gap = .xs,
        .cross_align = .center,
    };
    return ui_ptr.beginRow(src, o);
}
pub fn endStatusPane(ui_ptr: *Ui) void {
    ui_ptr.endRow();
}

pub fn statusPane(ui_ptr: *Ui, src: std.builtin.SourceLocation, label_text: []const u8, opts: StatusPaneOptions) StatusPaneResult {
    var item = opts.layout;
    if (opts.grow > 0) item.main = .{ .grow = opts.grow };
    if (opts.width) |w| item.main = .fixedSize(w);
    const r = label(ui_ptr, src, label_text, .{ .key = opts.key, .debug_name = opts.debug_name, .style = .small, .color = .secondary, .text_align = opts.@"align", .layout = item });
    return .{ .hovered = r.hovered };
}

pub fn tooltipIfTruncated(ui_ptr: *Ui, src: std.builtin.SourceLocation, owner: core.WidgetId, label_text: []const u8, opts: TooltipOptions) TooltipResult {
    const node = ui_ptr.getPrevNode(owner) orelse return .{};
    const avail = @as(f32, @floatFromInt(node.abs.w)) / ui_ptr.scale;
    const needed = text.measure(label_text, ui_ptr.theme_ptr.fonts.get(.body), ui_ptr.scale, .{}).w;
    if (needed <= avail) return .{};
    return tooltip(ui_ptr, src, owner, label_text, opts);
}

pub const ChangeSource = enum { user, api, undo, redo, load };
pub const Change = struct { start: u64, removed: u64, inserted: u64, source: ChangeSource, revision: u64, line: u32 };
pub const ChangeFn = *const fn (ctx: ?*anyopaque, change: Change) void;
pub const Subscription = enum(u32) { none = 0, _ };

pub fn textAreaSubscribe(ui_ptr: *Ui, h: TextAreaHandle, f: ChangeFn, ctx: ?*anyopaque) error{OutOfMemory}!Subscription {
    const st = ui_ptr.retained(TextAreaState, h.id, .pinned);
    try st.subs.append(st.owner_allocator, .{ .f = f, .ctx = ctx });
    return @fromBackingInt(@intCast(@as(u32, @intCast(st.subs.items.len))));
}
pub fn textAreaUnsubscribe(ui_ptr: *Ui, h: TextAreaHandle, s: Subscription) void {
    const st = ui_ptr.retained(TextAreaState, h.id, .pinned);
    const idx: usize = @backingInt(s);
    if (idx == 0 or idx > st.subs.items.len) return;
    _ = st.subs.orderedRemove(idx - 1);
}

pub fn textInputSetSelection(ui_ptr: *Ui, id: core.WidgetId, anchor: u32, caret: u32) void {
    const st = ui_ptr.stateSticky(TextInputState, id, .{});
    st.anchor = anchor;
    st.caret = caret;
}

// 文档容器形式的标签页入口（内部复用 tabs 叶节点；内容由调用方在 endTabs 前声明）。
pub const TabSpec = struct { label: []const u8, icon: ?theme.Icon = null, closable: bool = false };
pub fn beginTabs(ui_ptr: *Ui, src: std.builtin.SourceLocation, tabs_spec: []const TabSpec, current: *usize, opts: TabsOptions) TabsResult {
    _ = ui_ptr.beginColumn(src, .{ .main = .{ .grow = 1 }, .cross = .fill, .gap = .none });
    const labels = ui_ptr.treeAlloc().alloc([]const u8, tabs_spec.len) catch return .{};
    for (tabs_spec, 0..) |t, i| labels[i] = t.label;
    var o = opts;
    o.items = labels;
    o.selected = current;
    return tabs(ui_ptr, @src(), o);
}
pub fn beginTabsRetained(ui_ptr: *Ui, src: std.builtin.SourceLocation, tabs_spec: []const TabSpec, initial: usize, opts: TabsOptions) TabsResult {
    const cur = ui_ptr.stateSticky(usize, ui_ptr.id(src, opts.key), initial);
    return beginTabs(ui_ptr, src, tabs_spec, cur, opts);
}
pub fn endTabs(ui_ptr: *Ui) void {
    ui_ptr.endColumn();
}

/// 测试观测入口（13 的 REQ-TEST-014 `expect text`）：返回节点当前显示的完整文本，只读。
/// 目前覆盖 label、button、checkbox/radio/switch；其余控件返回 null。
pub fn nodeText(node: *const Node) ?[]const u8 {
    const f = node.paint orelse return null;
    const props = node.props orelse return null;
    if (f == &paintLabel) {
        const p: *const LabelProps = @ptrCast(@alignCast(props));
        return p.label;
    }
    if (f == &paintButton) {
        const p: *const ButtonProps = @ptrCast(@alignCast(props));
        return p.label;
    }
    if (f == &paintToggle) {
        const p: *const ToggleProps = @ptrCast(@alignCast(props));
        return p.label;
    }
    return null;
}

// ---------------------------------------------------------------------------
// 列表/树/表格共用的输入状态机（M5）
//
// 控件实现把指针与键盘事件转交给这里，渲染层只读取结果。这样选择模型、
// 焦点/锚点校正、滚入与滚动规则可以脱离窗口做精确的单元测试。
// ---------------------------------------------------------------------------

pub const ListRowRef = struct { index: usize, key: ItemKey };
pub const ListPress = enum { none, pending_collapse, drag_reorder };
pub const ListContext = struct { index: ?usize, pos: core.Vec2, anchor: core.Rect, from_keyboard: bool, column: ?u16 = null };
pub const ReorderRequest = struct { keys: []const ItemKey, insert_at: usize };

pub const ListUpdate = struct {
    selection_changed: bool = false,
    activated: ?usize = null,
    focus_index: ?usize = null,
    context_menu: ?ListContext = null,
    reordered: ?ReorderRequest = null,
    consumed: bool = false,
    offset_changed: bool = false,
    drag_started: bool = false,
};

pub const VisibleRange = struct { first: usize, last: usize, has_rows: bool };

/// 列表的选择/焦点/滚动状态机。字段与 list.md 第 13 节的保留状态一一对应。
pub const ListController = struct {
    allocator: std.mem.Allocator,
    opts: ListOptions,
    own_selection: Selection,
    offset: f32 = 0,
    viewport_h: f32 = 220,
    viewport_w: f32 = 320,
    focus: ?ListRowRef = null,
    anchor: ?ListRowRef = null,
    press: ListPress = .none,
    press_ref: ?ListRowRef = null,
    search_buf: [32]u8 = undefined,
    search_len: u8 = 0,
    search_last_ms: u64 = 0,
    last_count: usize = 0,
    hover_row: ?usize = null,
    hover_since_ms: u64 = 0,
    update: ListUpdate = .{},

    pub fn init(allocator: std.mem.Allocator, opts: ListOptions) ListController {
        return .{
            .allocator = allocator,
            .opts = opts,
            .own_selection = Selection.init(allocator),
        };
    }

    pub fn deinit(self: *ListController) void {
        if (self.opts.selection == null) self.own_selection.deinit();
    }

    pub fn selectionPtr(self: *ListController) *Selection {
        return self.opts.selection orelse &self.own_selection;
    }
    pub fn selection(self: *const ListController) *Selection {
        if (self.opts.selection) |s| return s;
        return @constCast(&self.own_selection);
    }

    pub fn rowHeight(self: *const ListController) f32 {
        return self.opts.row_height orelse 22;
    }

    pub fn selectedKeys(self: *const ListController) []const ItemKey {
        return self.selection().keys.items;
    }

    pub fn focusKey(self: *const ListController) ?ItemKey {
        return if (self.focus) |f| f.key else null;
    }
    pub fn anchorKey(self: *const ListController) ?ItemKey {
        return if (self.anchor) |a| a.key else null;
    }

    pub fn searchText(self: *const ListController) []const u8 {
        return self.search_buf[0..self.search_len];
    }

    fn keyAt(self: *const ListController, index: usize) ItemKey {
        return self.opts.data.keyAt(index);
    }

    pub fn refAt(self: *const ListController, index: usize) ListRowRef {
        return .{ .index = index, .key = self.keyAt(index) };
    }

    fn signature(self: *const ListController) u64 {
        var h: u64 = 0xcbf29ce484222325;
        for (self.selection().keys.items) |k| {
            h ^= k;
            h *%= 0x100000001b3;
        }
        return h ^ @as(u64, @intCast(self.selection().len()));
    }

    fn reset(self: *ListController) void {
        self.update = .{ .focus_index = if (self.focus) |f| f.index else null };
    }

    fn noteChanged(self: *ListController, before: u64) void {
        self.update.selection_changed = before != self.signature();
    }

    pub fn maxOffset(self: *const ListController, count: usize) f32 {
        const total = @as(f32, @floatFromInt(count)) * self.rowHeight();
        return @max(0, total - self.viewport_h);
    }

    pub fn clampOffset(self: *ListController, count: usize) void {
        const mo = self.maxOffset(count);
        if (self.offset < 0) self.offset = 0;
        if (self.offset > mo) self.offset = mo;
    }

    pub fn pageRows(self: *const ListController) usize {
        const n: i64 = @intFromFloat(@floor(self.viewport_h / @max(1, self.rowHeight())));
        return @intCast(@max(1, n - 1));
    }

    /// REQ-W-LIST-004：可见窗口含上下各 5 行缓冲。
    pub fn visibleRange(self: *const ListController, count: usize) VisibleRange {
        if (count == 0) return .{ .first = 0, .last = 0, .has_rows = false };
        const rh = @max(1, self.rowHeight());
        const first_vis: usize = @intFromFloat(@floor(@max(0, self.offset) / rh));
        const last_vis_f: f32 = @floor((@max(0, self.offset) + self.viewport_h - 1) / rh);
        const last_vis: usize = @min(count - 1, @as(usize, @intFromFloat(@max(0, last_vis_f))));
        const first = first_vis -| 5;
        const last = @min(count - 1, last_vis + 5);
        return .{ .first = @min(first, count - 1), .last = last, .has_rows = true };
    }

    /// REQ-W-LIST-015：焦点与锚点每次构建前校正。
    pub fn correct(self: *ListController, count: usize) void {
        self.reset();
        self.last_count = count;
        if (count == 0) {
            self.focus = null;
            self.anchor = null;
            self.offset = 0;
            self.press = .none;
            self.press_ref = null;
            return;
        }
        if (self.focus) |f| {
            var idx = @min(f.index, count - 1);
            if (self.opts.data.index_of) |io| {
                if (io(self.opts.data.ctx, f.key)) |found| {
                    idx = @min(found, count - 1);
                }
            }
            self.focus = self.refAt(idx);
        }
        if (self.anchor) |a| {
            var idx = @min(a.index, count - 1);
            if (self.opts.data.index_of) |io| {
                if (io(self.opts.data.ctx, a.key)) |found| idx = @min(found, count - 1);
            }
            self.anchor = self.refAt(idx);
        }
        if (self.press == .pending_collapse) {
            if (self.press_ref) |p| {
                if (p.index >= count) {
                    self.press = .none;
                    self.press_ref = null;
                }
            }
        }
        self.clampOffset(count);
    }

    pub fn setViewport(self: *ListController, width: f32, height: f32, count: usize) void {
        self.viewport_w = width;
        self.viewport_h = height;
        self.clampOffset(count);
    }

    /// 视口内 y（lpx，相对行区域顶）对应的行；空白区域返回 null。
    pub fn rowAt(self: *const ListController, y: f32, count: usize) ?usize {
        if (count == 0 or y < 0) return null;
        const content_y = y + self.offset;
        const idx: usize = @intFromFloat(@floor(@max(0, content_y) / @max(1, self.rowHeight())));
        if (idx >= count) return null;
        return idx;
    }

    pub fn rowRect(self: *const ListController, index: usize) core.Rect {
        return .{
            .x = 0,
            .y = @as(f32, @floatFromInt(index)) * self.rowHeight() - self.offset,
            .w = self.viewport_w,
            .h = self.rowHeight(),
        };
    }

    /// REQ-W-LIST-040：以最小位移把行完整滚入视口。
    pub fn ensureVisible(self: *ListController, index: usize, count: usize) void {
        const old = self.offset;
        const rh = self.rowHeight();
        const top = @as(f32, @floatFromInt(index)) * rh;
        const bottom = top + rh;
        if (top < self.offset) {
            self.offset = top;
        } else if (bottom > self.offset + self.viewport_h) {
            self.offset = bottom - self.viewport_h;
        }
        self.clampOffset(count);
        if (@abs(self.offset - old) > 0.0001) self.update.offset_changed = true;
    }

    fn setOffset(self: *ListController, value: f32, count: usize) void {
        const old = self.offset;
        self.offset = value;
        self.clampOffset(count);
        if (@abs(self.offset - old) > 0.0001) self.update.offset_changed = true;
    }

    fn selectOnly(self: *ListController, ref: ListRowRef) void {
        if (self.opts.mode == .none) return;
        self.selectionPtr().setOnly(ref.key) catch {};
    }
    fn addToSelection(self: *ListController, ref: ListRowRef) void {
        if (self.opts.mode == .none) return;
        self.selectionPtr().add(ref.key) catch {};
    }
    fn toggleSelection(self: *ListController, ref: ListRowRef) void {
        if (self.opts.mode == .none) return;
        _ = self.selectionPtr().toggle(ref.key) catch {};
    }
    fn clearSelection(self: *ListController) void {
        self.selectionPtr().clear();
    }

    fn replaceRange(self: *ListController, a: usize, b: usize, count: usize) void {
        if (self.opts.mode == .none) return;
        const sel = self.selectionPtr();
        if (self.opts.mode == .single) {
            sel.setOnly(self.keyAt(@min(a, count - 1))) catch {};
            return;
        }
        sel.clear();
        sel.addRange(.{ .ctx = self.opts.data.ctx, .count = count, .key_of = self.opts.data.key_of }, a, b) catch {};
    }

    fn addRange(self: *ListController, a: usize, b: usize, count: usize) void {
        if (self.opts.mode != .multi) return;
        self.selectionPtr().addRange(.{ .ctx = self.opts.data.ctx, .count = count, .key_of = self.opts.data.key_of }, a, b) catch {};
    }

    fn selectAll(self: *ListController, count: usize) void {
        if (self.opts.mode != .multi or count == 0) return;
        self.selectionPtr().addRange(.{ .ctx = self.opts.data.ctx, .count = count, .key_of = self.opts.data.key_of }, 0, count - 1) catch {};
    }

    /// 单击/右键按下的选择效果（在按下时生效）。
    pub fn pointerPress(self: *ListController, index: ?usize, mouse_button: platform.MouseButton, mods: platform.Mods, count: usize) ListUpdate {
        self.reset();
        const before = self.signature();
        if (count == 0) {
            self.focus = null;
            self.anchor = null;
            return self.update;
        }
        if (index == null) {
            if (mouse_button == .left and self.opts.mode == .multi) self.clearSelection();
            self.noteChanged(before);
            return self.update;
        }
        const i = @min(index.?, count - 1);
        const ref = self.refAt(i);
        if (mouse_button == .right) {
            if (!self.selection().contains(ref.key)) {
                self.selectOnly(ref);
                self.focus = ref;
                self.anchor = ref;
            } else {
                self.focus = ref;
            }
            self.noteChanged(before);
            self.ensureVisible(i, count);
            return self.update;
        }
        if (mouse_button != .left) return self.update;
        switch (self.opts.mode) {
            .none => {
                self.focus = ref;
                self.anchor = ref;
            },
            .single => {
                if (mods.ctrl and !mods.alt) {
                    self.toggleSelection(ref);
                } else {
                    self.selectOnly(ref);
                }
                self.focus = ref;
                self.anchor = ref;
            },
            .multi => {
                if (mods.ctrl and mods.shift) {
                    if (self.anchor == null) self.anchor = ref;
                    const a = self.anchor.?.index;
                    self.addRange(a, i, count);
                    self.focus = ref;
                } else if (mods.shift) {
                    if (self.anchor == null) self.anchor = ref;
                    const a = self.anchor.?.index;
                    self.replaceRange(a, i, count);
                    self.focus = ref;
                } else if (mods.ctrl) {
                    self.toggleSelection(ref);
                    self.focus = ref;
                    self.anchor = ref;
                } else if (self.selection().contains(ref.key) and self.selection().len() > 1) {
                    // REQ-W-LIST-023：多选中的一个已选中行，延迟到点击成立时折叠。
                    self.focus = ref;
                    self.press = .pending_collapse;
                    self.press_ref = ref;
                } else {
                    self.selectOnly(ref);
                    self.focus = ref;
                    self.anchor = ref;
                    self.press = .none;
                    self.press_ref = null;
                }
            },
        }
        self.noteChanged(before);
        self.ensureVisible(i, count);
        return self.update;
    }

    /// 左键释放；`click_count` 来自框架的双击判定。返回激活结果。
    pub fn pointerRelease(self: *ListController, index: ?usize, inside: bool, click_count: u8, mods: platform.Mods, count: usize) ListUpdate {
        self.reset();
        const before = self.signature();
        if (self.press == .pending_collapse) {
            if (inside and index != null and self.press_ref != null and index.? == self.press_ref.?.index) {
                const ref = self.refAt(@min(index.?, @max(0, count - 1)));
                self.selectOnly(ref);
                self.anchor = ref;
                self.focus = ref;
                self.noteChanged(before);
            }
            self.press = .none;
            self.press_ref = null;
        }
        if (inside and index != null and click_count == 2 and !mods.ctrl and !mods.shift and !mods.alt) {
            self.update.activated = index;
        }
        self.update.focus_index = if (self.focus) |f| f.index else null;
        return self.update;
    }

    pub fn contextMenu(self: *ListController, index: ?usize, pos: core.Vec2, from_keyboard: bool) ListUpdate {
        self.reset();
        var anchor: core.Rect = .{ .x = 0, .y = 0, .w = self.viewport_w, .h = self.viewport_h };
        var out_pos = pos;
        if (index) |i| {
            anchor = self.rowRect(i);
            out_pos = .{ .x = anchor.x, .y = anchor.y + anchor.h };
        }
        self.update.context_menu = .{ .index = index, .pos = out_pos, .anchor = anchor, .from_keyboard = from_keyboard };
        return self.update;
    }

    /// 滚轮：`steps` 为正表示向上滚（与 08 的 wheel delta 同号）。
    pub fn wheel(self: *ListController, steps: f32, count: usize, amount: platform.ScrollAmount, mods: platform.Mods) ListUpdate {
        self.reset();
        if (mods.shift) return self.update;
        const base: f32 = switch (amount) {
            .lines => |n| @as(f32, @floatFromInt(n)) * self.rowHeight(),
            .page => @max(self.rowHeight(), self.viewport_h - self.rowHeight()),
        };
        self.setOffset(self.offset - steps * base, count);
        self.clearHover();
        return self.update;
    }

    pub fn pointerHover(self: *ListController, index: ?usize, now_ms: u64) void {
        if (index == self.hover_row) return;
        self.hover_row = index;
        self.hover_since_ms = now_ms;
    }

    pub fn clearHover(self: *ListController) void {
        self.hover_row = null;
    }

    /// 行文字被截断且悬停超过系统时间时返回提示框（REQ-W-LIST-046）。
    pub fn tooltip(self: *ListController, now_ms: u64, hover_time_ms: u32, truncated: bool) ?struct { index: usize, text: []const u8, anchor: core.Rect } {
        if (!self.opts.tooltip_on_truncate or !truncated) return null;
        const idx = self.hover_row orelse return null;
        if (now_ms -| self.hover_since_ms < hover_time_ms) return null;
        return .{ .index = idx, .text = self.opts.data.textAt(idx), .anchor = self.rowRect(idx) };
    }

    fn moveTo(self: *ListController, index: usize, mods: platform.Mods, count: usize, from: ?usize) void {
        const old = from orelse index;
        self.focus = self.refAt(index);
        if (self.opts.mode == .none) {
            self.ensureVisible(index, count);
            return;
        }
        if (mods.ctrl and mods.shift) {
            if (self.anchor == null) self.anchor = self.refAt(old);
            self.addRange(self.anchor.?.index, index, count);
        } else if (mods.shift and self.opts.mode == .multi) {
            if (self.anchor == null) self.anchor = self.refAt(old);
            self.replaceRange(self.anchor.?.index, index, count);
        } else if (mods.ctrl) {
            // 仅移动焦点。
        } else {
            self.selectOnly(self.focus.?);
            self.anchor = self.focus;
        }
        self.ensureVisible(index, count);
    }

    /// 键盘按下。`key_down` 的 repeat 对 Enter 特殊处理（只激活一次）。
    pub fn keyDown(self: *ListController, key: platform.VirtualKey, mods: platform.Mods, repeat: bool, count: usize, now_ms: u64) ListUpdate {
        self.reset();
        const before = self.signature();
        if (mods.alt or mods.altgr) return self.update;
        if (count == 0) {
            self.update.consumed = key == .enter; // Enter 冒泡给默认按钮
            return self.update;
        }
        const f = self.focus;
        const page = self.pageRows();
        switch (key) {
            .down, .up => {
                var target: usize = 0;
                if (f) |cur| {
                    target = if (key == .down) @min(count - 1, cur.index + 1) else cur.index -| 1;
                } else {
                    target = if (key == .down) 0 else count - 1;
                }
                const before_sig = self.signature();
                self.moveTo(target, mods, count, if (f) |x| x.index else null);
                self.noteChanged(before_sig);
                self.update.consumed = true;
            },
            .home, .end => {
                const target: usize = if (key == .home) 0 else count - 1;
                const before_sig = self.signature();
                self.moveTo(target, mods, count, if (f) |x| x.index else null);
                self.noteChanged(before_sig);
                self.update.consumed = true;
            },
            .page_down, .page_up => {
                if (mods.ctrl) return self.update; // 冒泡给外层标签页
                const start = if (f) |x| x.index else if (key == .page_down) 0 else count - 1;
                const target: usize = if (key == .page_down)
                    @min(count - 1, start + page)
                else
                    start -| page;
                const before_sig = self.signature();
                self.moveTo(target, mods, count, if (f) |x| x.index else null);
                self.noteChanged(before_sig);
                self.update.consumed = true;
            },
            .space => {
                if (self.search_len > 0 and now_ms -| self.search_last_ms <= 1000) return self.update;
                if (f) |cur| {
                    const before_sig = self.signature();
                    if (mods.ctrl) self.toggleSelection(cur) else self.selectOnly(cur);
                    self.anchor = cur;
                    self.noteChanged(before_sig);
                    self.update.consumed = true;
                }
                _ = before;
            },
            .a => {
                if (mods.ctrl and self.opts.mode == .multi) {
                    const before_sig = self.signature();
                    self.selectAll(count);
                    self.noteChanged(before_sig);
                    self.update.consumed = true;
                }
            },
            .enter => {
                if (f) |cur| {
                    if (!repeat) self.update.activated = cur.index;
                    self.update.consumed = true;
                }
            },
            .f10 => {
                if (mods.shift and !mods.ctrl and !mods.alt) {
                    const idx = if (f) |cur| cur.index else null;
                    _ = self.contextMenu(idx, .{ .x = 0, .y = 0 }, true);
                    return self.update;
                }
            },
            .apps => {
                const idx = if (f) |cur| cur.index else null;
                _ = self.contextMenu(idx, .{ .x = 0, .y = 0 }, true);
                return self.update;
            },
            else => {},
        }
        self.update.focus_index = if (self.focus) |x| x.index else null;
        return self.update;
    }

    /// 可打印字符（REQ-W-LIST-039）。返回是否消费该字符。
    pub fn charInput(self: *ListController, cp: u21, mods: platform.Mods, count: usize, now_ms: u64) ListUpdate {
        self.reset();
        if (mods.ctrl or mods.alt or mods.altgr) return self.update;
        if (count == 0) return self.update;
        if (self.opts.data.item_text == null and self.opts.data.prefix_search == null) return self.update;
        if (now_ms -| self.search_last_ms > 1000) self.search_len = 0;
        if (self.search_len >= self.search_buf.len) self.search_len = 0;
        const old_len = self.search_len;
        if (cp >= 0x80) {
            var tmp: [4]u8 = undefined;
            const n = std.unicode.utf8Encode(cp, &tmp) catch return self.update;
            if (self.search_len + n > self.search_buf.len) return self.update;
            @memcpy(self.search_buf[self.search_len .. self.search_len + n], tmp[0..n]);
            self.search_len += @intCast(n);
        } else {
            self.search_buf[self.search_len] = @intCast(cp & 0x7f);
            self.search_len += 1;
        }
        self.search_last_ms = now_ms;
        const start: usize = blk: {
            if (self.opts.data.prefix_search) |ps| break :blk ps(self.opts.data.ctx, self.searchText(), 0) orelse break :blk 0;
            const base = if (self.focus) |f| f.index else 0;
            break :blk if (old_len == 0) (base + 1) % count else base % count;
        };
        var found: ?usize = null;
        if (self.opts.data.prefix_search) |ps| {
            found = ps(self.opts.data.ctx, self.searchText(), start);
        } else {
            const text_fn = self.opts.data.item_text.?;
            var n: usize = 0;
            while (n < count) : (n += 1) {
                const i = (start + n) % count;
                if (startsWithFold(text_fn(self.opts.data.ctx, i), self.searchText())) {
                    found = i;
                    break;
                }
            }
        }
        if (found) |i| {
            const before_sig = self.signature();
            const from = if (self.focus) |f| f.index else null;
            self.moveTo(i, mods, count, from);
            self.noteChanged(before_sig);
        }
        self.update.consumed = true;
        self.update.focus_index = if (self.focus) |f| f.index else null;
        return self.update;
    }

    /// 开始拖动重排（REQ-W-LIST-042）。
    pub fn dragStart(self: *ListController, count: usize) ListUpdate {
        self.reset();
        if (!self.opts.reorder or self.opts.mode == .none) return self.update;
        if (self.opts.data.key_of == null) return self.update;
        if (self.press != .pending_collapse and self.selection().len() == 0) return self.update;
        self.press = .drag_reorder;
        self.update.drag_started = true;
        _ = count;
        return self.update;
    }

    /// 放置（REQ-W-LIST-044）。`content_y` 为含偏移的内容坐标。
    pub fn drop(self: *ListController, scratch: std.mem.Allocator, content_y: f32, count: usize) ListUpdate {
        self.reset();
        if (self.press != .drag_reorder) return self.update;
        defer {
            self.press = .none;
            self.press_ref = null;
        }
        const rh = self.rowHeight();
        var ins: usize = @intFromFloat(@floor((content_y + rh * 0.5) / rh));
        if (content_y < 0) ins = 0;
        if (ins > count) ins = count;
        if (self.opts.data.key_of == null) return self.update;
        var dragged = std.ArrayListUnmanaged(ItemKey).empty;
        defer dragged.deinit(scratch);
        var first: ?usize = null;
        var last: usize = 0;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            if (self.selection().contains(self.keyAt(i))) {
                dragged.append(scratch, self.keyAt(i)) catch return self.update;
                if (first == null) first = i;
                last = i;
            }
        }
        if (dragged.items.len == 0) return self.update;
        if (first != null and dragged.items.len == last - first.? + 1) {
            if (ins >= first.? and ins <= last + 1) return self.update;
        }
        const keys = scratch.dupe(ItemKey, dragged.items) catch return self.update;
        self.update.reordered = .{ .keys = keys, .insert_at = ins };
        return self.update;
    }

    pub fn cancelDrag(self: *ListController) void {
        if (self.press == .drag_reorder) {
            self.press = .none;
            self.press_ref = null;
        }
    }

    /// 焦点行滚入（用于 UIA ScrollItem.ScrollIntoView）。
    pub fn scrollIntoView(self: *ListController, index: usize, count: usize) ListUpdate {
        self.reset();
        self.ensureVisible(index, count);
        return self.update;
    }
};

/// ASCII 大小写折叠的前缀比较（REQ-W-LIST-039 的简化实现；非 ASCII 逐字节）。
fn startsWithFold(haystack: []const u8, prefix: []const u8) bool {
    if (prefix.len > haystack.len) return false;
    for (prefix, 0..) |p, i| {
        if (std.ascii.toLower(p) != std.ascii.toLower(haystack[i])) return false;
    }
    return true;
}

// ---------------------------------------------------------------------------
// 树：展平缓存与选择/键盘状态机（REQ-W-TREE-002 至 020）
// ---------------------------------------------------------------------------

pub const flat_tree_max_depth: u16 = 256;
pub const tree_expand_all_limit: usize = 100000;

pub const FlatTreeRow = struct {
    node: TreeNode = .root,
    key: ItemKey = 0,
    parent: ?usize = null,
    depth: u16 = 0,
    has_children: bool = false,
    expanded: bool = false,
    placeholder: bool = false,
};

pub const TreeUpdate = struct {
    selection_changed: bool = false,
    activated: ?TreeNode = null,
    focus_index: ?usize = null,
    context_menu: ?TreeContext = null,
    toggled: []const Toggle = &.{},
    consumed: bool = false,
    offset_changed: bool = false,
};

pub const TreeController = struct {
    allocator: std.mem.Allocator,
    model: TreeModel,
    opts: TreeOptions,
    own_selection: Selection,
    own_expanded: ExpandedSet,
    rows: std.ArrayListUnmanaged(FlatTreeRow) = .empty,
    index_map: std.AutoHashMapUnmanaged(ItemKey, usize) = .empty,
    toggles: std.ArrayListUnmanaged(Toggle) = .empty,
    offset: f32 = 0,
    viewport_h: f32 = 220,
    viewport_w: f32 = 320,
    focus: ?ListRowRef = null,
    anchor: ?ListRowRef = null,
    search_buf: [32]u8 = undefined,
    search_len: u8 = 0,
    search_last_ms: u64 = 0,
    version_seen: u64 = 0,
    exp_rev_seen: u64 = std.math.maxInt(u64),
    built: bool = false,
    update: TreeUpdate = .{},

    pub fn init(allocator: std.mem.Allocator, model: TreeModel, opts: TreeOptions) TreeController {
        return .{
            .allocator = allocator,
            .model = model,
            .opts = opts,
            .own_selection = Selection.init(allocator),
            .own_expanded = ExpandedSet.init(allocator),
        };
    }

    pub fn deinit(self: *TreeController) void {
        self.rows.deinit(self.allocator);
        self.index_map.deinit(self.allocator);
        self.toggles.deinit(self.allocator);
        if (self.opts.selection == null) self.own_selection.deinit();
        if (self.opts.expanded == null) self.own_expanded.deinit();
    }

    pub fn selectionPtr(self: *TreeController) *Selection {
        return self.opts.selection orelse &self.own_selection;
    }
    pub fn expandedPtr(self: *TreeController) *ExpandedSet {
        return self.opts.expanded orelse &self.own_expanded;
    }
    pub fn selection(self: *const TreeController) *Selection {
        if (self.opts.selection) |s| return s;
        return @constCast(&self.own_selection);
    }
    pub fn expanded(self: *const TreeController) *ExpandedSet {
        if (self.opts.expanded) |e| return e;
        return @constCast(&self.own_expanded);
    }

    pub fn rowHeight(self: *const TreeController) f32 {
        _ = self;
        return 22;
    }

    pub fn rowsSlice(self: *const TreeController) []const FlatTreeRow {
        return self.rows.items;
    }

    pub fn indexOfKey(self: *const TreeController, key: ItemKey) ?usize {
        return self.index_map.get(key);
    }

    fn keyAt(self: *const TreeController, index: usize) ItemKey {
        if (index >= self.rows.items.len) return 0;
        return self.rows.items[index].key;
    }
    pub fn refAt(self: *const TreeController, index: usize) ListRowRef {
        return .{ .index = index, .key = self.keyAt(index) };
    }

    fn signature(self: *const TreeController) u64 {
        var h: u64 = 0xcbf29ce484222325;
        for (self.selection().keys.items) |k| {
            h ^= k;
            h *%= 0x100000001b3;
        }
        return h ^ @as(u64, @intCast(self.selection().len()));
    }

    fn reset(self: *TreeController) void {
        self.toggles.clearRetainingCapacity();
        self.update = .{ .focus_index = if (self.focus) |f| f.index else null };
    }
    fn noteChanged(self: *TreeController, before: u64) void {
        self.update.selection_changed = before != self.signature();
    }

    fn addRow(self: *TreeController, row: FlatTreeRow) void {
        self.rows.append(self.allocator, row) catch return;
    }

    fn reindex(self: *TreeController) void {
        self.index_map.clearRetainingCapacity();
        for (self.rows.items, 0..) |r, i| {
            if (!r.placeholder) self.index_map.put(self.allocator, r.key, i) catch {};
        }
    }

    fn appendSubtree(self: *TreeController, node: TreeNode, depth: u16, parent: ?usize) void {
        if (depth > flat_tree_max_depth) return;
        const n = self.model.child_count(self.model.ctx, node);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const child = self.model.child_at(self.model.ctx, node, i);
            const key = self.model.key_of(self.model.ctx, child);
            const has = self.model.has_children(self.model.ctx, child);
            const implicit = depth < self.opts.initially_expanded_depth and has;
            if (implicit) self.expandedPtr().set(key, true, null) catch {};
            const is_expanded = self.expandedPtr().contains(key);
            const row_index = self.rows.items.len;
            self.addRow(.{
                .node = child,
                .key = key,
                .parent = parent,
                .depth = depth,
                .has_children = has,
                .expanded = is_expanded,
            });
            if (has and is_expanded) {
                const loading = if (self.model.load_state) |ls| ls(self.model.ctx, child) == .loading else false;
                if (loading) {
                    self.addRow(.{
                        .node = child,
                        .key = 0,
                        .parent = row_index,
                        .depth = depth + 1,
                        .has_children = false,
                        .expanded = false,
                        .placeholder = true,
                    });
                } else {
                    self.appendSubtree(child, depth + 1, row_index);
                }
            }
        }
    }

    /// 全量重建展平缓存（REQ-W-TREE-003）。保存焦点/锚点的键。
    pub fn rebuild(self: *TreeController) void {
        self.rows.clearRetainingCapacity();
        self.appendSubtree(.root, 0, null);
        self.reindex();
        self.version_seen = self.model.version;
        self.exp_rev_seen = self.expandedPtr().revision;
        self.built = true;
        if (self.focus) |f| {
            self.focus = if (self.index_map.get(f.key)) |i| self.refAt(i) else null;
        }
        if (self.anchor) |a| {
            self.anchor = if (self.index_map.get(a.key)) |i| self.refAt(i) else null;
        }
        self.clampOffset();
    }

    /// 构建前校正：version 或外部展开集合变化时重建（REQ-W-TREE-005）。
    pub fn correct(self: *TreeController) void {
        self.reset();
        if (!self.built or self.model.version != self.version_seen or self.expandedPtr().revision != self.exp_rev_seen) self.rebuild();
        self.clampOffset();
    }

    pub fn maxOffset(self: *const TreeController) f32 {
        const total = @as(f32, @floatFromInt(self.rows.items.len)) * self.rowHeight();
        return @max(0, total - self.viewport_h);
    }
    pub fn clampOffset(self: *TreeController) void {
        if (self.offset < 0) self.offset = 0;
        const mo = self.maxOffset();
        if (self.offset > mo) self.offset = mo;
    }
    pub fn setViewport(self: *TreeController, width: f32, height: f32) void {
        self.viewport_w = width;
        self.viewport_h = height;
        self.clampOffset();
    }
    pub fn visibleRange(self: *const TreeController) VisibleRange {
        const count = self.rows.items.len;
        if (count == 0) return .{ .first = 0, .last = 0, .has_rows = false };
        const first_vis: usize = @intFromFloat(@floor(@max(0, self.offset) / self.rowHeight()));
        const last_vis_f: f32 = @floor((@max(0, self.offset) + self.viewport_h - 1) / self.rowHeight());
        const last_vis: usize = @min(count - 1, @as(usize, @intFromFloat(@max(0, last_vis_f))));
        return .{ .first = first_vis -| 5, .last = @min(count - 1, last_vis + 5), .has_rows = true };
    }
    pub fn rowAt(self: *const TreeController, y: f32) ?usize {
        if (self.rows.items.len == 0 or y < 0) return null;
        const idx: usize = @intFromFloat(@floor((y + self.offset) / self.rowHeight()));
        if (idx >= self.rows.items.len or self.rows.items[idx].placeholder) return null;
        return idx;
    }
    pub fn rowRect(self: *const TreeController, index: usize) core.Rect {
        return .{ .x = 0, .y = @as(f32, @floatFromInt(index)) * self.rowHeight() - self.offset, .w = self.viewport_w, .h = self.rowHeight() };
    }
    pub fn ensureVisible(self: *TreeController, index: usize) void {
        const old = self.offset;
        const top = @as(f32, @floatFromInt(index)) * self.rowHeight();
        const bottom = top + self.rowHeight();
        if (top < self.offset) self.offset = top else if (bottom > self.offset + self.viewport_h) self.offset = bottom - self.viewport_h;
        self.clampOffset();
        if (@abs(self.offset - old) > 0.0001) self.update.offset_changed = true;
    }
    fn setOffset(self: *TreeController, value: f32) void {
        const old = self.offset;
        self.offset = value;
        self.clampOffset();
        if (@abs(self.offset - old) > 0.0001) self.update.offset_changed = true;
    }

    pub fn arrowZoneX(self: *const TreeController, depth: u16) core.Vec2 {
        _ = self;
        const x = 8 + @as(f32, @floatFromInt(depth)) * 16;
        return .{ .x = x, .y = x + 16 };
    }

    /// 内容起点 x（lpx）：pad_item_x + depth × indent + icon_sm + gap_xs。
    pub fn contentX(self: *const TreeController, depth: u16) f32 {
        _ = self;
        return 8 + @as(f32, @floatFromInt(depth)) * 16 + 16 + 2;
    }

    fn toggleRow(self: *TreeController, index: usize) void {
        if (index >= self.rows.items.len) return;
        if (self.rows.items[index].placeholder) return;
        if (!self.rows.items[index].has_children) return;
        const row = self.rows.items[index];
        const now_expanded = !row.expanded;
        self.expandedPtr().set(row.key, now_expanded, null) catch return;
        self.toggles.append(self.allocator, .{ .node = row.node, .key = row.key, .expanded = now_expanded }) catch {};
        if (now_expanded) self.insertChildren(index) else self.removeChildren(index);
        self.update.toggled = self.toggles.items;
    }

    fn insertChildren(self: *TreeController, index: usize) void {
        const row = self.rows.items[index];
        self.rows.items[index].expanded = true;
        var tmp = std.ArrayListUnmanaged(FlatTreeRow).empty;
        const saved_rows = self.rows;
        const saved_map = self.index_map;
        // 用同一套展开集合在临时控制器状态上生成子树。
        self.rows = tmp;
        self.index_map = .empty;
        const loading = if (self.model.load_state) |ls| ls(self.model.ctx, row.node) == .loading else false;
        if (loading) {
            self.addRow(.{
                .node = row.node,
                .key = 0,
                .parent = null,
                .depth = row.depth + 1,
                .has_children = false,
                .expanded = false,
                .placeholder = true,
            });
        } else {
            self.appendSubtree(row.node, row.depth + 1, null);
        }
        tmp = self.rows;
        self.rows = saved_rows;
        self.index_map = saved_map;
        const added = tmp.items.len;
        if (added == 0) {
            tmp.deinit(self.allocator);
            return;
        }
        self.rows.insertSlice(self.allocator, index + 1, tmp.items) catch {
            tmp.deinit(self.allocator);
            return;
        };
        // 子树的 parent 以 index 为基准。
        var j: usize = 0;
        while (j < added) : (j += 1) {
            const r = &self.rows.items[index + 1 + j];
            r.parent = if (tmp.items[j].parent) |p| index + 1 + p else index;
        }
        // 其后已有行的 parent 平移。
        var k: usize = index + 1 + added;
        while (k < self.rows.items.len) : (k += 1) {
            if (self.rows.items[k].parent) |p| {
                if (p > index) self.rows.items[k].parent = p + added;
            }
        }
        if (self.focus) |f| {
            if (f.index > index) self.focus = .{ .index = f.index + added, .key = f.key };
        }
        if (self.anchor) |a| {
            if (a.index > index) self.anchor = .{ .index = a.index + added, .key = a.key };
        }
        tmp.deinit(self.allocator);
        self.reindex();
    }

    fn removeChildren(self: *TreeController, index: usize) void {
        self.rows.items[index].expanded = false;
        const depth = self.rows.items[index].depth;
        var end = index + 1;
        while (end < self.rows.items.len and self.rows.items[end].depth > depth) : (end += 1) {}
        const removed = end - (index + 1);
        if (removed == 0) return;
        // 焦点/锚点落在被删除的后代中时移到折叠节点。
        if (self.focus) |f| {
            if (f.index > index and f.index < end) self.focus = self.refAt(index);
        }
        if (self.anchor) |a| {
            if (a.index > index and a.index < end) self.anchor = self.refAt(index);
        }
        self.rows.replaceRangeAssumeCapacity(index + 1, removed, &.{});
        _ = &self.rows;
        var k: usize = index + 1;
        while (k < self.rows.items.len) : (k += 1) {
            if (self.rows.items[k].parent) |p| {
                if (p > index) self.rows.items[k].parent = p - removed;
            }
        }
        if (self.focus) |f| {
            if (f.index >= end) self.focus = .{ .index = f.index - removed, .key = f.key };
        }
        if (self.anchor) |a| {
            if (a.index >= end) self.anchor = .{ .index = a.index - removed, .key = a.key };
        }
        self.reindex();
    }

    pub fn toggle(self: *TreeController, index: usize) TreeUpdate {
        self.reset();
        const before = self.signature();
        self.toggleRow(index);
        self.noteChanged(before);
        self.update.focus_index = if (self.focus) |f| f.index else null;
        return self.update;
    }

    /// 展开 F 与全部后代（小键盘 *，REQ-W-TREE-019）。
    pub fn expandAllFrom(self: *TreeController, index: usize) TreeUpdate {
        self.reset();
        if (index >= self.rows.items.len) return self.update;
        var expanded_count: usize = 0;
        // 先展开自身，再逐行处理新增行直到达到上限。
        if (self.rows.items[index].has_children) {
            if (!self.rows.items[index].expanded) self.toggleRow(index) else self.toggles.append(self.allocator, .{ .node = self.rows.items[index].node, .key = self.rows.items[index].key, .expanded = true }) catch {};
            expanded_count += 1;
        }
        var cursor = index + 1;
        while (cursor < self.rows.items.len and expanded_count < tree_expand_all_limit) : (cursor += 1) {
            const r = self.rows.items[cursor];
            if (r.depth <= self.rows.items[index].depth and cursor > index) break;
            if (r.placeholder or !r.has_children or r.expanded) continue;
            self.toggleRow(cursor);
            expanded_count += 1;
        }
        self.update.toggled = self.toggles.items;
        self.update.focus_index = if (self.focus) |f| f.index else null;
        return self.update;
    }

    fn selectOnly(self: *TreeController, ref: ListRowRef) void {
        if (self.opts.mode == .none) return;
        self.selectionPtr().setOnly(ref.key) catch {};
    }
    fn toggleSelection(self: *TreeController, ref: ListRowRef) void {
        if (self.opts.mode == .none) return;
        _ = self.selectionPtr().toggle(ref.key) catch {};
    }
    fn addRangeRows(self: *TreeController, a: usize, b: usize) void {
        if (self.opts.mode == .none) return;
        const lo = @min(a, b);
        const hi = @max(a, b);
        var i = lo;
        while (i <= hi and i < self.rows.items.len) : (i += 1) {
            if (!self.rows.items[i].placeholder) self.selectionPtr().add(self.rows.items[i].key) catch {};
        }
    }
    fn replaceRangeRows(self: *TreeController, a: usize, b: usize) void {
        if (self.opts.mode == .none) return;
        const sel = self.selectionPtr();
        sel.clear();
        self.addRangeRows(a, b);
    }

    /// 点击行的箭头位（REQ-W-TREE-013）。`x` 为行内 x（lpx）。
    pub fn pointerPressArrow(self: *TreeController, index: usize, x: f32) ?TreeUpdate {
        if (index >= self.rows.items.len or self.rows.items[index].placeholder) return null;
        const r = self.rows.items[index];
        if (!r.has_children) return null;
        const zone = self.arrowZoneX(r.depth);
        if (x < zone.x or x >= zone.y) return null;
        self.reset();
        self.toggleRow(index);
        self.update.focus_index = if (self.focus) |f| f.index else null;
        return self.update;
    }

    pub fn pointerPress(self: *TreeController, index: ?usize, mouse_button: platform.MouseButton, mods: platform.Mods) TreeUpdate {
        self.reset();
        const before = self.signature();
        if (index == null or index.? >= self.rows.items.len or self.rows.items[index.?].placeholder) {
            if (index == null and mouse_button == .left and self.opts.mode == .multi) self.selectionPtr().clear();
            self.noteChanged(before);
            return self.update;
        }
        const i = index.?;
        const ref = self.refAt(i);
        if (mouse_button == .right) {
            if (!self.selection().contains(ref.key)) {
                self.selectOnly(ref);
                self.focus = ref;
                self.anchor = ref;
            } else self.focus = ref;
        } else if (mouse_button == .left) {
            switch (self.opts.mode) {
                .none => {
                    self.focus = ref;
                    self.anchor = ref;
                },
                .single => {
                    if (mods.ctrl and !mods.alt) self.toggleSelection(ref) else self.selectOnly(ref);
                    self.focus = ref;
                    self.anchor = ref;
                },
                .multi => {
                    if (mods.ctrl and mods.shift) {
                        if (self.anchor == null) self.anchor = ref;
                        self.addRangeRows(self.anchor.?.index, i);
                        self.focus = ref;
                    } else if (mods.shift) {
                        if (self.anchor == null) self.anchor = ref;
                        self.replaceRangeRows(self.anchor.?.index, i);
                        self.focus = ref;
                    } else if (mods.ctrl) {
                        self.toggleSelection(ref);
                        self.focus = ref;
                        self.anchor = ref;
                    } else {
                        self.selectOnly(ref);
                        self.focus = ref;
                        self.anchor = ref;
                    }
                },
            }
        }
        self.noteChanged(before);
        self.ensureVisible(i);
        return self.update;
    }

    /// 双击/激活语义（REQ-W-TREE-014）：有子项只切换展开，叶子报告 activated。
    pub fn doubleClick(self: *TreeController, index: usize, mods: platform.Mods) TreeUpdate {
        self.reset();
        if (index >= self.rows.items.len or self.rows.items[index].placeholder) return self.update;
        if (mods.ctrl or mods.shift or mods.alt) return self.update;
        const r = self.rows.items[index];
        if (r.has_children) {
            self.toggleRow(index);
            if (self.opts.activate_parents) self.update.activated = r.node;
        } else {
            self.update.activated = r.node;
        }
        return self.update;
    }

    pub fn contextMenu(self: *TreeController, index: ?usize, pos: core.Vec2, from_keyboard: bool) TreeUpdate {
        self.reset();
        var node: ?TreeNode = null;
        var key: ?ItemKey = null;
        var anchor: core.Rect = .{ .x = 0, .y = 0, .w = self.viewport_w, .h = self.viewport_h };
        var out_pos = pos;
        if (index) |i| {
            if (i < self.rows.items.len and !self.rows.items[i].placeholder) {
                node = self.rows.items[i].node;
                key = self.rows.items[i].key;
            }
            anchor = self.rowRect(i);
            out_pos = .{ .x = anchor.x, .y = anchor.y + anchor.h };
        }
        self.update.context_menu = .{ .node = node, .key = key, .pos = out_pos, .anchor = anchor, .from_keyboard = from_keyboard };
        return self.update;
    }

    fn moveTo(self: *TreeController, index: usize, mods: platform.Mods) void {
        const old = if (self.focus) |f| f.index else index;
        self.focus = self.refAt(index);
        if (self.opts.mode == .none) {
            self.ensureVisible(index);
            return;
        }
        if (mods.ctrl and mods.shift) {
            if (self.anchor == null) self.anchor = self.refAt(old);
            self.addRangeRows(self.anchor.?.index, index);
        } else if (mods.shift and self.opts.mode == .multi) {
            if (self.anchor == null) self.anchor = self.refAt(old);
            self.replaceRangeRows(self.anchor.?.index, index);
        } else if (!mods.ctrl) {
            self.selectOnly(self.focus.?);
            self.anchor = self.focus;
        }
        self.ensureVisible(index);
    }

    fn nextFocusable(self: *const TreeController, from: usize) ?usize {
        if (self.rows.items.len == 0) return null;
        var i = from + 1;
        while (i < self.rows.items.len) : (i += 1) {
            if (!self.rows.items[i].placeholder) return i;
        }
        return null;
    }
    fn prevFocusable(self: *const TreeController, from: usize) ?usize {
        var i = from;
        while (i > 0) {
            i -= 1;
            if (!self.rows.items[i].placeholder) return i;
        }
        return null;
    }
    fn firstFocusable(self: *const TreeController) ?usize {
        for (self.rows.items, 0..) |r, i| {
            if (!r.placeholder) return i;
        }
        return null;
    }
    fn lastFocusable(self: *const TreeController) ?usize {
        var i = self.rows.items.len;
        while (i > 0) {
            i -= 1;
            if (!self.rows.items[i].placeholder) return i;
        }
        return null;
    }

    pub fn keyDown(self: *TreeController, key: platform.VirtualKey, mods: platform.Mods, repeat: bool, now_ms: u64) TreeUpdate {
        _ = now_ms;
        self.reset();
        const before = self.signature();
        if (mods.alt or mods.altgr) return self.update;
        const count = self.rows.items.len;
        if (count == 0) return self.update;
        const f = self.focus;
        const page: usize = @intCast(@max(1, @as(i64, @intFromFloat(@floor(self.viewport_h / self.rowHeight()))) - 1));
        switch (key) {
            .down, .up => {
                if (f == null) {
                    const first = self.firstFocusable() orelse return self.update;
                    const last = self.lastFocusable() orelse return self.update;
                    self.moveTo(if (key == .down) first else last, mods);
                } else {
                    const i = f.?.index;
                    const next = if (key == .down) self.nextFocusable(i) else self.prevFocusable(i);
                    if (next == null) return self.update;
                    self.moveTo(next.?, mods);
                }
                self.noteChanged(before);
                self.update.consumed = true;
            },
            .right => {
                if (mods.ctrl) return self.update;
                if (f) |cur| {
                    const r = self.rows.items[cur.index];
                    if (r.has_children and !r.expanded) {
                        self.toggleRow(cur.index);
                    } else if (r.has_children and r.expanded) {
                        const child = self.nextFocusable(cur.index);
                        if (child != null and self.rows.items[child.?].depth > r.depth) {
                            self.moveTo(child.?, mods);
                            self.noteChanged(before);
                        }
                    }
                }
                self.update.consumed = true;
            },
            .left => {
                if (mods.ctrl) return self.update;
                if (f) |cur| {
                    const r = self.rows.items[cur.index];
                    if (r.has_children and r.expanded) {
                        self.toggleRow(cur.index);
                    } else if (r.parent) |p| {
                        self.moveTo(p, mods);
                        self.noteChanged(before);
                    }
                }
                self.update.consumed = true;
            },
            .home, .end, .page_up, .page_down => {
                if (mods.ctrl and (key == .page_up or key == .page_down)) return self.update;
                const start = if (f) |x| x.index else if (key == .home or key == .page_up) 0 else count - 1;
                var target: usize = switch (key) {
                    .home => self.firstFocusable() orelse return self.update,
                    .end => self.lastFocusable() orelse return self.update,
                    .page_down => @min(count - 1, start + page),
                    .page_up => start -| page,
                    else => start,
                };
                if (target >= count) target = count - 1;
                if (self.rows.items[target].placeholder) {
                    var probe = target;
                    while (probe < count and self.rows.items[probe].placeholder) : (probe += 1) {}
                    if (probe < count) target = probe else {
                        const back = self.prevFocusable(target) orelse target;
                        target = back;
                    }
                }
                self.moveTo(target, mods);
                self.noteChanged(before);
                self.update.consumed = true;
            },
            .np_mul => {
                if (f) |cur| {
                    _ = self.expandAllFrom(cur.index);
                    self.update.consumed = true;
                }
            },
            .np_add => {
                if (f) |cur| {
                    if (self.rows.items[cur.index].has_children and !self.rows.items[cur.index].expanded) self.toggleRow(cur.index);
                    self.update.consumed = true;
                }
            },
            .np_sub => {
                if (f) |cur| {
                    if (self.rows.items[cur.index].has_children and self.rows.items[cur.index].expanded) self.toggleRow(cur.index);
                    self.update.consumed = true;
                }
            },
            .space => {
                if (f) |cur| {
                    if (mods.ctrl) self.toggleSelection(cur) else self.selectOnly(cur);
                    self.anchor = cur;
                    self.noteChanged(before);
                    self.update.consumed = true;
                }
            },
            .enter => {
                if (f) |cur| {
                    const r = self.rows.items[cur.index];
                    if (r.has_children) {
                        self.toggleRow(cur.index);
                        if (self.opts.activate_parents) self.update.activated = r.node;
                    } else if (!repeat) {
                        self.update.activated = r.node;
                    }
                    self.update.consumed = true;
                }
            },
            .a => {
                if (mods.ctrl and self.opts.mode == .multi) {
                    var i: usize = 0;
                    while (i < count) : (i += 1) {
                        if (!self.rows.items[i].placeholder) self.selectionPtr().add(self.rows.items[i].key) catch {};
                    }
                    self.noteChanged(before);
                    self.update.consumed = true;
                }
            },
            .f10 => {
                if (mods.shift) {
                    const idx = if (f) |cur| cur.index else null;
                    _ = self.contextMenu(idx, .{ .x = 0, .y = 0 }, true);
                }
            },
            .apps => {
                const idx = if (f) |cur| cur.index else null;
                _ = self.contextMenu(idx, .{ .x = 0, .y = 0 }, true);
            },
            else => {},
        }
        self.update.focus_index = if (self.focus) |x| x.index else null;
        return self.update;
    }

    pub fn wheel(self: *TreeController, steps: f32, amount: platform.ScrollAmount, mods: platform.Mods) TreeUpdate {
        self.reset();
        if (mods.shift) return self.update;
        const base: f32 = switch (amount) {
            .lines => |n| @as(f32, @floatFromInt(n)) * self.rowHeight(),
            .page => @max(self.rowHeight(), self.viewport_h - self.rowHeight()),
        };
        self.setOffset(self.offset - steps * base);
        return self.update;
    }

    pub fn charInput(self: *TreeController, cp: u21, mods: platform.Mods, now_ms: u64) TreeUpdate {
        self.reset();
        if (mods.ctrl or mods.alt or mods.altgr) return self.update;
        if (self.model.text_of == null or self.rows.items.len == 0) return self.update;
        if (now_ms -| self.search_last_ms > 1000) self.search_len = 0;
        if (self.search_len >= self.search_buf.len) self.search_len = 0;
        const old_len = self.search_len;
        self.search_buf[self.search_len] = @intCast(cp & 0x7f);
        self.search_len += 1;
        self.search_last_ms = now_ms;
        const count = self.rows.items.len;
        const base = if (self.focus) |f| f.index else 0;
        const start = if (old_len == 0) (base + 1) % count else base % count;
        var n: usize = 0;
        while (n < count) : (n += 1) {
            const i = (start + n) % count;
            if (self.rows.items[i].placeholder) continue;
            if (startsWithFold(self.model.text_of.?(self.model.ctx, self.rows.items[i].node), self.searchText())) {
                const before = self.signature();
                self.moveTo(i, mods);
                self.noteChanged(before);
                break;
            }
        }
        self.update.consumed = true;
        self.update.focus_index = if (self.focus) |f| f.index else null;
        return self.update;
    }

    pub fn searchText(self: *const TreeController) []const u8 {
        return self.search_buf[0..self.search_len];
    }

    pub fn selectedVisibleCount(self: *const TreeController) usize {
        var n: usize = 0;
        for (self.rows.items) |r| {
            if (!r.placeholder and self.selection().contains(r.key)) n += 1;
        }
        return n;
    }
};

// ---------------------------------------------------------------------------
// 表格：列宽求解、列虚拟化、排序与表头交互（M5）
// ---------------------------------------------------------------------------

pub const table_splitter_w: f32 = 5;
pub const table_pad_item_x: f32 = 8;
pub const table_icon_sm: f32 = 16;
pub const table_gap_sm: f32 = 4;
pub const table_min_col_width: f32 = 32;
pub const table_buffer_cols: usize = 1;

pub const HeaderHit = union(enum) {
    none,
    cell: struct { column: u16, display: u16 },
    boundary: struct { column: u16, display: u16 },
};

pub const ColumnSpan = struct {
    first_created: usize,
    last_created: usize,
    first_visible: usize,
    last_visible: usize,
    leader_width: f32,
    content_width: f32,
    created: usize,
    visible: usize,
    has_columns: bool,
};

pub const TableUpdate = struct {
    selection_changed: bool = false,
    activated: ?usize = null,
    sort_changed: ?struct { column: u16, dir: ?SortDir } = null,
    column_resized: ?struct { column: u16, width: f32 } = null,
    columns_reordered: bool = false,
    header_context: ?struct { column: ?u16, pos: core.Vec2, anchor: core.Rect } = null,
    resizing: ?u16 = null,
};

pub const TableController = struct {
    allocator: std.mem.Allocator,
    columns: []const TableColumn,
    count: usize,
    opts: TableOptions,
    row_sel: ListController,
    user_widths: []f32,
    hidden: []bool,
    order: []u16,
    widths: []f32,
    sort_state: TableSort,
    viewport_w: f32 = 800,
    viewport_h: f32 = 220,
    offset_x: f32 = 0,
    header_widths: []i32,
    resizing: ?struct { column: u16, start: f32, press_x: f32 } = null,
    pending_sort: ?u16 = null,
    hover_cell: ?struct { row: usize, column: u16 } = null,
    hover_header: ?u16 = null,
    hover_since_ms: u64 = 0,
    update: TableUpdate = .{},

    pub fn init(allocator: std.mem.Allocator, columns: []const TableColumn, count: usize, opts: TableOptions) !TableController {
        const n = columns.len;
        const user_widths = try allocator.alloc(f32, n);
        const hidden = try allocator.alloc(bool, n);
        const order = try allocator.alloc(u16, n);
        const widths = try allocator.alloc(f32, n);
        const header_widths = try allocator.alloc(i32, n);
        @memset(user_widths, 0);
        @memset(widths, 0);
        @memset(header_widths, 0);
        for (columns, 0..) |c, i| {
            hidden[i] = c.hidden;
            order[i] = @intCast(i);
        }
        const row_sel = ListController.init(allocator, .{
            .mode = opts.mode,
            .selection = opts.selection,
            .data = .{
                .ctx = opts.data.ctx,
                .key_of = opts.data.key_of,
                .index_of = opts.data.index_of,
                .prefix_search = opts.data.prefix_search,
            },
            .row_height = opts.row_height,
        });
        return .{
            .allocator = allocator,
            .columns = columns,
            .count = count,
            .opts = opts,
            .row_sel = row_sel,
            .user_widths = user_widths,
            .hidden = hidden,
            .order = order,
            .widths = widths,
            .sort_state = if (opts.sort) |s| s.* else .{},
            .header_widths = header_widths,
        };
    }

    pub fn deinit(self: *TableController) void {
        self.allocator.free(self.user_widths);
        self.allocator.free(self.hidden);
        self.allocator.free(self.order);
        self.allocator.free(self.widths);
        self.allocator.free(self.header_widths);
        self.row_sel.deinit();
    }

    pub fn selectionPtr(self: *TableController) *Selection {
        return self.row_sel.selectionPtr();
    }
    pub fn selection(self: *const TableController) *Selection {
        return self.row_sel.selection();
    }

    pub fn sort(self: *const TableController) TableSort {
        return self.sort_state;
    }

    pub fn displayCount(self: *const TableController) usize {
        var n: usize = 0;
        for (self.order) |col| {
            if (!self.hidden[col]) n += 1;
        }
        return n;
    }

    fn displayColumn(self: *const TableController, display: usize) struct { column: u16, width: f32 } {
        var seen: usize = 0;
        for (self.order) |col| {
            if (self.hidden[col]) continue;
            if (seen == display) return .{ .column = col, .width = self.widths[col] };
            seen += 1;
        }
        return .{ .column = 0, .width = 0 };
    }

    pub fn naturalHeaderWidth(column: usize) i32 {
        // 由调用方在 measure 后填入；本函数只给无测量时的字符近似。
        _ = column;
        return 0;
    }

    /// 计算有效列宽（REQ-W-TABLE-003）。`scratch` 可以是帧竞技场。
    /// `char_width` 是 auto_header 的自然宽度测量（每字符 lpx）。
    pub fn layoutColumns(self: *TableController, scratch: std.mem.Allocator, viewport_w: f32, scale: f32, char_width: f32) void {
        self.viewport_w = viewport_w;
        const n = self.columns.len;
        if (n == 0) return;
        var cols = scratch.alloc(layout.Column, n) catch return;
        var out = scratch.alloc(i32, n) catch return;
        var header = scratch.alloc(i32, n) catch return;
        var map = scratch.alloc(u16, n) catch return;
        var m: usize = 0;
        for (self.order) |col| {
            if (self.hidden[col]) continue;
            const c = self.columns[col];
            var width = c.width;
            if (self.user_widths[col] > 0) width = .{ .fixed = self.user_widths[col] };
            cols[m] = .{
                .width = width,
                .min = @max(c.min, table_min_col_width),
                .max = c.max,
            };
            const pad_scaled = table_pad_item_x * scale;
            const icon_scaled = table_icon_sm * scale;
            const gap_scaled = table_gap_sm * scale;
            const title_cp = std.unicode.utf8CountCodepoints(c.title) catch c.title.len;
            var natural: f32 = @as(f32, @floatFromInt(title_cp)) * char_width + 2 * pad_scaled;
            if (c.sortable) natural += gap_scaled + icon_scaled;
            header[m] = @intFromFloat(@round(natural));
            map[m] = col;
            m += 1;
        }
        if (m == 0) return;
        layout.solveColumns(scratch, cols[0..m], header[0..m], @intFromFloat(@max(0, viewport_w)), true, 0, 1, out[0..m]);
        @memset(self.widths, 0);
        for (0..m) |i| self.widths[map[i]] = @floatFromInt(out[i]);
        // 隐藏列宽度为 0。
        for (self.hidden, 0..) |h, i| if (h) {
            self.widths[i] = 0;
        };
    }

    pub fn contentWidth(self: *const TableController) f32 {
        var w: f32 = 0;
        for (self.widths) |v| w += v;
        return w;
    }

    /// 列虚拟化（REQ-W-TABLE-005）。
    pub fn columnSpan(self: *const TableController, off_x: f32) ColumnSpan {
        var content: f32 = 0;
        var first_visible: ?usize = null;
        var last_visible: usize = 0;
        var pos: f32 = 0;
        var display: usize = 0;
        for (self.order) |col| {
            if (self.hidden[col]) continue;
            const w = self.widths[col];
            const lo = pos;
            const hi = pos + w;
            content = hi;
            if (hi > off_x and lo < off_x + self.viewport_w) {
                if (first_visible == null) first_visible = display;
                last_visible = display;
            }
            pos = hi;
            display += 1;
        }
        const total = display;
        if (total == 0 or first_visible == null) {
            return .{ .first_created = 0, .last_created = 0, .first_visible = 0, .last_visible = 0, .leader_width = 0, .content_width = content, .created = 0, .visible = 0, .has_columns = false };
        }
        const fv = first_visible.?;
        const first_created = fv -| table_buffer_cols;
        const last_created = @min(total - 1, last_visible + table_buffer_cols);
        var leader: f32 = 0;
        display = 0;
        for (self.order) |col| {
            if (self.hidden[col]) continue;
            if (display == first_created) break;
            leader += self.widths[col];
            display += 1;
        }
        return .{
            .first_created = first_created,
            .last_created = last_created,
            .first_visible = fv,
            .last_visible = last_visible,
            .leader_width = leader,
            .content_width = content,
            .created = last_created - first_created + 1,
            .visible = last_visible - fv + 1,
            .has_columns = true,
        };
    }

    pub fn maxOffsetX(self: *const TableController) f32 {
        return @max(0, self.contentWidth() - self.viewport_w);
    }

    /// 表头命中：列边界优先于单元格（REQ-W-TABLE-014）。
    pub fn headerHit(self: *const TableController, x: f32) HeaderHit {
        var pos: f32 = 0;
        var display: usize = 0;
        for (self.order) |col| {
            if (self.hidden[col]) continue;
            const w = self.widths[col];
            const end = pos + w;
            if (self.columns[col].resizable and x >= end - table_splitter_w and x < end) {
                return .{ .boundary = .{ .column = col, .display = @intCast(display) } };
            }
            if (x >= pos and x < end) {
                return .{ .cell = .{ .column = col, .display = @intCast(display) } };
            }
            pos = end;
            display += 1;
        }
        return .none;
    }

    fn reset(self: *TableController) void {
        self.update = .{ .resizing = if (self.resizing) |r| r.column else null };
    }

    /// 表头按下（REQ-W-TABLE-014/018）。返回命中的列信息。
    pub fn headerPress(self: *TableController, x: f32) HeaderHit {
        self.reset();
        const hit = self.headerHit(x);
        switch (hit) {
            .boundary => |b| {
                self.resizing = .{ .column = b.column, .start = self.widths[b.column], .press_x = x };
                self.update.resizing = b.column;
            },
            .cell => |c| {
                if (self.columns[c.column].sortable or self.opts.reorder_columns) self.pending_sort = c.column;
            },
            .none => {},
        }
        return hit;
    }

    /// 拖动调整列宽（REQ-W-TABLE-018/019）。
    pub fn headerDrag(self: *TableController, x: f32) void {
        self.reset();
        self.clearHover();
        const r = self.resizing orelse return;
        const col = r.column;
        const min = @max(self.columns[col].min, table_min_col_width);
        const max = self.columns[col].max;
        var w = r.start + (x - r.press_x);
        if (w < min) w = min;
        if (w > max) w = max;
        self.user_widths[col] = w;
        self.widths[col] = w;
        self.update.resizing = col;
    }

    pub fn headerRelease(self: *TableController, x: f32) void {
        self.reset();
        if (self.resizing) |r| {
            const min = @max(self.columns[r.column].min, table_min_col_width);
            const max = self.columns[r.column].max;
            var w = r.start + (x - r.press_x);
            if (w < min) w = min;
            if (w > max) w = max;
            if (@abs(w - r.start) > 0.0001) {
                self.user_widths[r.column] = w;
                self.widths[r.column] = w;
                self.update.column_resized = .{ .column = r.column, .width = w };
            }
            self.resizing = null;
            self.update.resizing = null;
            return;
        }
        if (self.pending_sort) |col| {
            self.pending_sort = null;
            if (!self.columns[col].sortable) return;
            const old = self.sort_state;
            if (old.column != col) {
                self.sort_state = .{ .column = col, .dir = .asc };
            } else if (old.dir == .asc) {
                self.sort_state = .{ .column = col, .dir = .desc };
            } else if (self.opts.allow_unsorted) {
                self.sort_state = .{ .column = null, .dir = .asc };
            } else {
                self.sort_state = .{ .column = col, .dir = .asc };
            }
            self.update.sort_changed = .{ .column = col, .dir = if (self.sort_state.column == null) null else self.sort_state.dir };
            if (self.opts.sort) |s| s.* = self.sort_state;
        }
    }

    pub fn cancelResize(self: *TableController) void {
        if (self.resizing) |r| {
            self.user_widths[r.column] = r.start;
            self.widths[r.column] = r.start;
        }
        self.resizing = null;
        self.pending_sort = null;
        self.update.resizing = null;
    }

    /// 列重排（REQ-W-TABLE-022）：display 为被拖动列的显示序号，ins 为插入边界。
    pub fn moveColumn(self: *TableController, display: usize, ins: usize) void {
        self.reset();
        const total = self.displayCount();
        if (display >= total or ins > total) return;
        var src_logic: u16 = 0;
        var seen: usize = 0;
        for (self.order) |col| {
            if (self.hidden[col]) continue;
            if (seen == display) {
                src_logic = col;
                break;
            }
            seen += 1;
        }
        if (ins == display or ins == display + 1) return;
        var new_order = self.allocator.alloc(u16, self.columns.len) catch return;
        defer self.allocator.free(new_order);
        var target = ins;
        if (ins > display) target = ins - 1;
        if (target == display) return;
        var w: usize = 0;
        var out_display: usize = 0;
        var inserted = false;
        for (self.order) |col| {
            if (col == src_logic or self.hidden[col]) continue;
            if (!inserted and out_display == target) {
                new_order[w] = src_logic;
                w += 1;
                inserted = true;
            }
            new_order[w] = col;
            w += 1;
            out_display += 1;
        }
        if (!inserted) {
            new_order[w] = src_logic;
            w += 1;
        }
        // 隐藏列追加在可见列之后，不参与显示序。
        for (self.order) |col| {
            if (!self.hidden[col]) continue;
            new_order[w] = col;
            w += 1;
        }
        var same = true;
        for (new_order, 0..) |col, i| {
            if (self.order[i] != col) {
                same = false;
                break;
            }
        }
        if (same) return;
        @memcpy(self.order, new_order);
        self.update.columns_reordered = true;
    }

    pub fn setColumnHidden(self: *TableController, column: u16, hidden: bool) void {
        if (column >= self.columns.len) return;
        if (self.hidden[column] == hidden) return;
        self.hidden[column] = hidden;
        if (hidden) self.widths[column] = 0;
        const mo = self.maxOffsetX();
        if (self.offset_x > mo) self.offset_x = mo;
    }

    pub fn correct(self: *TableController) void {
        self.row_sel.correct(self.count);
        if (self.opts.sort) |s| self.sort_state = s.*;
        if (self.sort_state.column) |c| {
            if (c >= self.columns.len or !self.columns[c].sortable) self.sort_state.column = null;
        }
        self.row_sel.viewport_h = self.viewport_h;
        if (self.offset_x > self.maxOffsetX()) self.offset_x = self.maxOffsetX();
    }

    pub fn pointerPress(self: *TableController, row: ?usize, mouse_button: platform.MouseButton, mods: platform.Mods) ListUpdate {
        return self.row_sel.pointerPress(row, mouse_button, mods, self.count);
    }
    pub fn pointerRelease(self: *TableController, row: ?usize, inside: bool, clicks: u8, mods: platform.Mods) ListUpdate {
        return self.row_sel.pointerRelease(row, inside, clicks, mods, self.count);
    }
    pub fn keyDown(self: *TableController, key: platform.VirtualKey, mods: platform.Mods, repeat: bool, now_ms: u64) ListUpdate {
        // ←/→ 横向滚动（REQ-W-TABLE-026）；Esc 仅在调整中出现由上层处理。
        if ((key == .left or key == .right) and !mods.ctrl and !mods.alt and !mods.altgr) {
            var u = ListUpdate{};
            if (self.maxOffsetX() > 0) {
                const step = 22;
                if (key == .left) {
                    if (self.offset_x > 0) {
                        self.offset_x = @max(0, self.offset_x - step);
                        u.offset_changed = true;
                    }
                } else if (self.offset_x < self.maxOffsetX()) {
                    self.offset_x = @min(self.maxOffsetX(), self.offset_x + step);
                    u.offset_changed = true;
                }
            }
            u.consumed = u.offset_changed;
            if (u.consumed) return u;
        }
        const u = self.row_sel.keyDown(key, mods, repeat, self.count, now_ms);
        self.update.selection_changed = u.selection_changed;
        self.update.activated = u.activated;
        return u;
    }

    /// 表头右键（REQ-W-TABLE-025）：header_menu 为真时给出列号。
    pub fn headerRightClick(self: *TableController, x: f32) TableUpdate {
        self.reset();
        if (!self.opts.header_menu) return self.update;
        var column: ?u16 = null;
        switch (self.headerHit(x)) {
            .cell => |c| column = c.column,
            .boundary => |b| column = b.column,
            .none => {},
        }
        var anchor = core.Rect{ .x = 0, .y = 0, .w = self.viewport_w, .h = 24 };
        if (column) |c| {
            var pos: f32 = 0;
            for (self.order) |col| {
                if (self.hidden[col]) continue;
                if (col == c) {
                    anchor = .{ .x = pos, .y = 0, .w = self.widths[col], .h = 24 };
                    break;
                }
                pos += self.widths[col];
            }
        }
        self.update.header_context = .{ .column = column, .pos = .{ .x = anchor.x, .y = 0 }, .anchor = anchor };
        return self.update;
    }

    /// 行右键（REQ-W-TABLE-025）：返回 row 与指针所在逻辑列。
    pub fn rowContextMenu(self: *TableController, row: ?usize, x: f32, pos: core.Vec2, from_keyboard: bool) ListUpdate {
        var u = self.row_sel.contextMenu(row, pos, from_keyboard);
        if (u.context_menu) |cm| {
            var column: ?u16 = null;
            if (!from_keyboard) {
                switch (self.headerHit(x)) {
                    .cell => |c| column = c.column,
                    .boundary => |b| column = b.column,
                    .none => {},
                }
            }
            u.context_menu = .{ .index = cm.index, .pos = cm.pos, .anchor = cm.anchor, .from_keyboard = from_keyboard, .column = column };
        }
        return u;
    }

    /// 双击列边界自适应（REQ-W-TABLE-020）：表头自然宽与当前可见行内容宽取大者。
    pub fn autoFitColumn(self: *TableController, col: u16, char_width: f32) ?TableUpdate {
        if (col >= self.columns.len) return null;
        const c = self.columns[col];
        if (!c.resizable) return null;
        const pad = 8.0;
        const gap = 4.0;
        const icon = 16.0;
        const title_cp = std.unicode.utf8CountCodepoints(c.title) catch c.title.len;
        var natural: f32 = @as(f32, @floatFromInt(title_cp)) * char_width + 2 * pad;
        if (c.sortable) natural += gap + icon;
        const row_h = self.row_sel.rowHeight();
        const offset = self.row_sel.offset;
        const vp = self.row_sel.viewport_h;
        const first_vis: usize = @intFromFloat(@floor(@max(0, offset) / row_h));
        const last_vis: usize = @min(self.count -| 1, @as(usize, @intFromFloat(@floor((@max(0, offset) + vp - 1) / row_h))));
        if (self.count > 0) {
            var i = first_vis;
            while (i <= last_vis and i < self.count) : (i += 1) {
                if (self.opts.data.cell_text) |f| {
                    const txt = f(self.opts.data.ctx, i, col);
                    if (txt.len > 0) {
                        const cp = std.unicode.utf8CountCodepoints(txt) catch txt.len;
                        const w = @as(f32, @floatFromInt(cp)) * char_width + 2 * pad;
                        natural = @max(natural, w);
                    }
                }
            }
        }
        const min = @max(c.min, table_min_col_width);
        const max = c.max;
        const w = std.math.clamp(natural, min, max);
        self.user_widths[col] = w;
        self.widths[col] = w;
        self.reset();
        self.update.column_resized = .{ .column = col, .width = w };
        return self.update;
    }

    /// 双击列边界（REQ-W-TABLE-020）。
    pub fn doubleClickBoundary(self: *TableController, x: f32, char_width: f32) ?TableUpdate {
        const hit = self.headerHit(x);
        switch (hit) {
            .boundary => |b| return self.autoFitColumn(b.column, char_width),
            else => return null,
        }
    }

    /// 列拖动开始（REQ-W-TABLE-021）：返回拖放载荷。
    pub fn columnDragStart(self: *TableController, display: usize) ?struct { kind: u32, data: u16 } {
        if (!self.opts.reorder_columns) return null;
        if (display >= self.displayCount()) return null;
        const d = self.displayColumn(display);
        return .{ .kind = table_column_kind, .data = d.column };
    }

    /// 列插入位置（REQ-W-TABLE-021）：内容 x 坐标，返回 0..显示列数。
    pub fn columnDropIndex(self: *TableController, content_x: f32) usize {
        var ins: usize = 0;
        var pos: f32 = 0;
        for (self.order) |col| {
            if (self.hidden[col]) continue;
            const mid = pos + self.widths[col] * 0.5;
            if (mid <= content_x) ins += 1 else break;
            pos += self.widths[col];
        }
        return ins;
    }

    pub fn pointerHoverCell(self: *TableController, row: ?usize, col: ?u16, now_ms: u64) void {
        const same = if (row == null or col == null) self.hover_cell == null else if (self.hover_cell) |h| h.row == row.? and h.column == col.? else false;
        self.hover_header = null;
        if (same) return;
        self.hover_cell = if (row != null and col != null) .{ .row = row.?, .column = col.? } else null;
        self.hover_since_ms = now_ms;
    }

    pub fn pointerHoverHeader(self: *TableController, col: ?u16, now_ms: u64) void {
        self.hover_cell = null;
        if (col == self.hover_header) return;
        self.hover_header = col;
        self.hover_since_ms = now_ms;
    }

    pub fn clearHover(self: *TableController) void {
        self.hover_cell = null;
        self.hover_header = null;
    }

    fn columnX(self: *const TableController, col: u16) f32 {
        var x: f32 = 0;
        for (self.order) |c| {
            if (self.hidden[c]) continue;
            if (c == col) return x - self.offset_x;
            x += self.widths[c];
        }
        return -self.offset_x;
    }

    pub fn cellRect(self: *const TableController, row: usize, col: u16) core.Rect {
        return .{
            .x = self.columnX(col),
            .y = @as(f32, @floatFromInt(row)) * self.row_sel.rowHeight() - self.row_sel.offset,
            .w = if (col < self.widths.len) self.widths[col] else 0,
            .h = self.row_sel.rowHeight(),
        };
    }

    pub fn headerRect(self: *const TableController, col: u16) core.Rect {
        return .{ .x = self.columnX(col), .y = 0, .w = if (col < self.widths.len) self.widths[col] else 0, .h = 24 };
    }

    /// 单元格文字被截断且悬停超过系统时间时返回提示框（REQ-W-TABLE-029）。
    pub fn cellTooltip(self: *TableController, now_ms: u64, hover_time_ms: u32, truncated: bool) ?struct { row: usize, column: u16, text: []const u8, anchor: core.Rect } {
        if (!self.opts.tooltip_on_truncate or !truncated) return null;
        const h = self.hover_cell orelse return null;
        if (now_ms -| self.hover_since_ms < hover_time_ms) return null;
        const text_fn = self.opts.data.cell_text orelse return null;
        return .{ .row = h.row, .column = h.column, .text = text_fn(self.opts.data.ctx, h.row, h.column), .anchor = self.cellRect(h.row, h.column) };
    }

    /// 表头标题被截断时返回提示框。
    pub fn headerTooltip(self: *TableController, now_ms: u64, hover_time_ms: u32, truncated: bool) ?struct { column: u16, text: []const u8, anchor: core.Rect } {
        if (!self.opts.tooltip_on_truncate or !truncated) return null;
        const col = self.hover_header orelse return null;
        if (now_ms -| self.hover_since_ms < hover_time_ms) return null;
        if (col >= self.columns.len) return null;
        return .{ .column = col, .text = self.columns[col].title, .anchor = self.headerRect(col) };
    }

    /// UIA HeaderItem.Invoke：等价于点击表头排序（REQ-W-TABLE-030）。
    pub fn invokeHeader(self: *TableController, col: u16) TableUpdate {
        self.reset();
        if (col >= self.columns.len or !self.columns[col].sortable) return self.update;
        if (self.sort_state.column != col) {
            self.sort_state = .{ .column = col, .dir = .asc };
        } else if (self.sort_state.dir == .asc) {
            self.sort_state = .{ .column = col, .dir = .desc };
        } else if (self.opts.allow_unsorted) {
            self.sort_state = .{ .column = null, .dir = .asc };
        } else {
            self.sort_state = .{ .column = col, .dir = .asc };
        }
        self.update.sort_changed = .{ .column = col, .dir = if (self.sort_state.column == null) null else self.sort_state.dir };
        if (self.opts.sort) |sp| sp.* = self.sort_state;
        return self.update;
    }

    /// 持久化写入（REQ-W-TABLE-031）。
    pub fn saveToSettings(self: *TableController, s: anytype, name: []const u8) void {
        s.setTable(name, self.user_widths, self.order, self.hidden, self.sort_state.column, self.sort_state.dir == .asc);
    }

    /// 持久化读入与校验（REQ-W-TABLE-032）；返回是否应用。
    pub fn loadFromSettings(self: *TableController, s: anytype, name: []const u8) bool {
        const v = s.table(name) orelse return false;
        if (v != .object) return false;
        const obj = v.object;
        const n = self.columns.len;
        const widths_v = obj.get("widths") orelse return false;
        const order_v = obj.get("order") orelse return false;
        const hidden_v = obj.get("hidden") orelse return false;
        if (widths_v != .array or widths_v.array.items.len != n) return false;
        if (order_v != .array or order_v.array.items.len != n) return false;
        if (hidden_v != .array or hidden_v.array.items.len != n) return false;
        var uw: [64]f32 = undefined;
        if (n > uw.len) return false;
        var seen: [64]bool = @splat(false);
        for (widths_v.array.items, 0..) |item, i| {
            if (item != .float and item != .integer) return false;
            const f: f64 = if (item == .float) item.float else @floatFromInt(item.integer);
            if (!std.math.isFinite(f) or f < 0) return false;
            uw[i] = @floatCast(f);
        }
        var ord: [64]u16 = undefined;
        for (order_v.array.items, 0..) |item, i| {
            if (item != .integer or item.integer < 0 or item.integer >= n) return false;
            const oi: usize = @intCast(item.integer);
            if (seen[oi]) return false;
            seen[oi] = true;
            ord[i] = @intCast(oi);
        }
        var hid: [64]bool = undefined;
        for (hidden_v.array.items, 0..) |item, i| {
            if (item != .bool) return false;
            hid[i] = item.bool;
        }
        var sc: ?u16 = null;
        var asc = true;
        const sort_v = obj.get("sort") orelse return false;
        if (sort_v != .null) {
            if (sort_v != .object) return false;
            const col_v = sort_v.object.get("col") orelse return false;
            const asc_v = sort_v.object.get("asc") orelse return false;
            if (col_v != .integer or asc_v != .bool) return false;
            if (col_v.integer < 0 or col_v.integer >= n) return false;
            const ci: usize = @intCast(col_v.integer);
            if (!self.columns[ci].sortable) return false;
            sc = @intCast(ci);
            asc = asc_v.bool;
        }
        @memcpy(self.user_widths, uw[0..n]);
        @memcpy(self.order, ord[0..n]);
        @memcpy(self.hidden, hid[0..n]);
        self.sort_state = .{ .column = sc, .dir = if (asc) .asc else .desc };
        if (self.opts.sort) |sp| sp.* = self.sort_state;
        return true;
    }
    pub fn wheel(self: *TableController, steps: f32, amount: platform.ScrollAmount, mods: platform.Mods) ListUpdate {
        self.clearHover();
        return self.row_sel.wheel(steps, self.count, amount, mods);
    }
    pub fn rowVisibleRange(self: *TableController) VisibleRange {
        self.row_sel.viewport_h = self.viewport_h;
        return self.row_sel.visibleRange(self.count);
    }
    pub fn setViewport(self: *TableController, width: f32, height: f32) void {
        self.viewport_w = width;
        self.viewport_h = height;
        self.row_sel.setViewport(width, height, self.count);
    }
};

// ---------------------------------------------------------------------------
// 树展开集合持久化（REQ-W-TREE-010）
// ---------------------------------------------------------------------------

pub fn treeSaveToSettings(self: *TreeController, s: anytype, name: []const u8) void {
    if (self.model.str_key_of == null) return;
    var list = std.ArrayListUnmanaged([]const u8).empty;
    defer list.deinit(self.allocator);
    for (self.rows.items) |r| {
        if (r.placeholder) continue;
        if (!self.expandedPtr().contains(r.key)) continue;
        const sk = self.model.str_key_of.?(self.model.ctx, r.node);
        var dup = false;
        for (list.items) |existing| if (std.mem.eql(u8, existing, sk)) {
            dup = true;
            break;
        };
        if (!dup) list.append(self.allocator, sk) catch {};
    }
    std.mem.sort([]const u8, list.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);
    s.setTree(name, list.items);
}

pub fn treeLoadFromSettings(self: *TreeController, s: anytype, name: []const u8) usize {
    const v = s.tree(name) orelse return 0;
    if (v != .array) return 0;
    var n: usize = 0;
    for (v.array.items) |item| {
        if (item != .string) continue;
        const key = ui.Key.str(item.string).hash;
        self.expandedPtr().set(key, true, item.string) catch {};
        n += 1;
    }
    self.built = false;
    return n;
}

// ---------------------------------------------------------------------------
// M5 UIA 适配器（REQ-W-LIST-048、REQ-W-TABLE-030、REQ-W-TREE-027）
//
// 假 UIA 入口直接读取控制器的状态机，并把 UIA 操作映射回与用户操作等效的
// 方法，供 Linux 宿主做单元测试与调试快照。Win32 的 COM 桥接在 M6 接入。
// ---------------------------------------------------------------------------

const uia_list_patterns = [_]uia.Pattern{ .selection, .scroll };
const uia_list_item_patterns = [_]uia.Pattern{ .selection_item, .scroll_item, .invoke };
const uia_table_patterns = [_]uia.Pattern{ .grid, .table, .selection, .scroll };
const uia_table_cell_patterns = [_]uia.Pattern{ .grid_item, .table_item };
const uia_header_patterns = [_]uia.Pattern{.invoke};
const uia_tree_patterns = [_]uia.Pattern{ .selection, .scroll };
const uia_tree_parent_patterns = [_]uia.Pattern{ .expand_collapse, .selection_item, .scroll_item, .invoke };
const uia_tree_leaf_patterns = [_]uia.Pattern{ .selection_item, .scroll_item, .invoke };

fn uiaId(seed: u64) core.WidgetId {
    return core.WidgetId.fromHash(seed);
}

pub const UiaList = struct {
    ctrl: *ListController,

    pub fn root(self: UiaList) uia.Node {
        return .{
            .id = uiaId(0x4c495354),
            .control_type = .list,
            .enabled = self.ctrl.opts.enabled,
            .patterns = &uia_list_patterns,
            .can_select_multiple = self.ctrl.opts.mode == .multi,
            .selection_required = false,
            .row_count = self.ctrl.last_count,
        };
    }

    pub fn row(self: UiaList, index: usize) ?uia.Node {
        if (index >= self.ctrl.last_count) return null;
        return .{
            .id = uiaId(0x4c495354 ^ (@as(u64, index) +% 1)),
            .control_type = .list_item,
            .name = self.ctrl.opts.data.textAt(index),
            .enabled = self.ctrl.opts.enabled,
            .selected = self.ctrl.selection().contains(self.ctrl.opts.data.keyAt(index)),
            .focused = if (self.ctrl.focus) |f| f.index == index else false,
            .patterns = &uia_list_item_patterns,
            .row = index,
        };
    }

    pub fn select(self: UiaList, index: usize) ListUpdate {
        return self.ctrl.pointerPress(index, .left, .{}, self.ctrl.last_count);
    }

    pub fn addToSelection(self: UiaList, index: usize) ListUpdate {
        if (self.ctrl.opts.mode == .single) return self.select(index);
        return self.ctrl.pointerPress(index, .left, .{ .ctrl = true }, self.ctrl.last_count);
    }

    pub fn removeFromSelection(self: UiaList, index: usize) ListUpdate {
        const before = self.ctrl.selection().len();
        const key = self.ctrl.opts.data.keyAt(index);
        self.ctrl.selectionPtr().remove(key);
        const changed = self.ctrl.selection().len() != before;
        return .{ .selection_changed = changed, .focus_index = if (self.ctrl.focus) |f| f.index else null };
    }

    pub fn scrollIntoView(self: UiaList, index: usize) ListUpdate {
        return self.ctrl.scrollIntoView(index, self.ctrl.last_count);
    }

    pub fn invoke(self: UiaList, index: usize) ListUpdate {
        return .{ .activated = index, .focus_index = if (self.ctrl.focus) |f| f.index else null };
    }

    /// GetSelection 只返回已创建（可见窗口 + 缓冲）行中的选中项。
    pub fn selectionNodes(self: UiaList, allocator: std.mem.Allocator) []uia.Node {
        var out = std.ArrayListUnmanaged(uia.Node).empty;
        if (self.ctrl.last_count == 0) return out.toOwnedSlice(allocator) catch &.{};
        const range = self.ctrl.visibleRange(self.ctrl.last_count);
        var i = range.first;
        while (i <= range.last and i < self.ctrl.last_count) : (i += 1) {
            if (!self.ctrl.selection().contains(self.ctrl.opts.data.keyAt(i))) continue;
            if (self.row(i)) |n| out.append(allocator, n) catch {};
        }
        return out.toOwnedSlice(allocator) catch &.{};
    }
};

pub const UiaTable = struct {
    ctrl: *TableController,

    pub fn root(self: UiaTable) uia.Node {
        return .{
            .id = uiaId(0x5441424c),
            .control_type = .data_grid,
            .enabled = self.ctrl.opts.enabled,
            .patterns = &uia_table_patterns,
            .can_select_multiple = self.ctrl.opts.mode == .multi,
            .selection_required = false,
            .row_count = self.ctrl.count,
            .column_count = self.ctrl.displayCount(),
            .row_major = true,
        };
    }

    pub fn headers(self: UiaTable, allocator: std.mem.Allocator) []uia.Node {
        var out = std.ArrayListUnmanaged(uia.Node).empty;
        for (self.ctrl.order) |col| {
            if (self.ctrl.hidden[col]) continue;
            const c = self.ctrl.columns[col];
            const dir: uia.SortDirection = if (self.ctrl.sort_state.column) |sc| blk: {
                if (sc != col) break :blk .none;
                break :blk if (self.ctrl.sort_state.dir == .asc) .ascending else .descending;
            } else .none;
            out.append(allocator, .{
                .id = uiaId(0x48445200 ^ (@as(u64, col) +% 1)),
                .control_type = .header_item,
                .name = c.title,
                .enabled = self.ctrl.opts.enabled,
                .patterns = if (c.sortable) &uia_header_patterns else &.{},
                .sort_direction = dir,
                .column = col,
            }) catch {};
        }
        return out.toOwnedSlice(allocator) catch &.{};
    }

    pub fn cell(self: UiaTable, row: usize, col: u16) ?uia.Node {
        if (row >= self.ctrl.count or col >= self.ctrl.columns.len) return null;
        const text_fn = self.ctrl.opts.data.cell_text orelse return null;
        return .{
            .id = uiaId(0x43454c4c ^ ((@as(u64, row) +% 1) *% 0x100 +% col)),
            .control_type = .data_item,
            .name = text_fn(self.ctrl.opts.data.ctx, row, col),
            .enabled = self.ctrl.opts.enabled,
            .selected = self.ctrl.selection().contains(if (self.ctrl.opts.data.key_of) |k| k(self.ctrl.opts.data.ctx, row) else @as(ItemKey, @intCast(row))),
            .patterns = &uia_table_cell_patterns,
            .row = row,
            .column = col,
            .row_span = 1,
            .column_span = 1,
        };
    }

    pub fn headerInvoke(self: UiaTable, col: u16) ?TableUpdate {
        if (col >= self.ctrl.columns.len or !self.ctrl.columns[col].sortable) return null;
        return self.ctrl.invokeHeader(col);
    }

    pub fn select(self: UiaTable, row: usize) ListUpdate {
        return self.ctrl.pointerPress(row, .left, .{});
    }
    pub fn invoke(self: UiaTable, row: usize) ListUpdate {
        return .{ .activated = row, .focus_index = if (self.ctrl.row_sel.focus) |f| f.index else null };
    }
    pub fn scrollIntoView(self: UiaTable, row: usize) ListUpdate {
        return self.ctrl.row_sel.scrollIntoView(row, self.ctrl.count);
    }
};

pub const UiaTree = struct {
    ctrl: *TreeController,

    pub fn root(self: UiaTree) uia.Node {
        return .{
            .id = uiaId(0x54524545),
            .control_type = .tree,
            .enabled = self.ctrl.opts.enabled,
            .patterns = &uia_tree_patterns,
            .can_select_multiple = self.ctrl.opts.mode == .multi,
            .selection_required = false,
            .row_count = self.ctrl.rowsSlice().len,
        };
    }

    pub fn row(self: UiaTree, index: usize) ?uia.Node {
        if (index >= self.ctrl.rowsSlice().len) return null;
        const r = self.ctrl.rowsSlice()[index];
        if (r.placeholder) return null;
        const state: uia.ExpandState = if (!r.has_children) .leaf_node else if (r.expanded) .expanded else .collapsed;
        const name = if (self.ctrl.model.text_of) |f| f(self.ctrl.model.ctx, r.node) else "";
        return .{
            .id = uiaId(0x54524545 ^ (r.key +% 1)),
            .control_type = .tree_item,
            .name = name,
            .enabled = self.ctrl.opts.enabled,
            .selected = self.ctrl.selection().contains(r.key),
            .focused = if (self.ctrl.focus) |f| f.index == index else false,
            .patterns = if (r.has_children) &uia_tree_parent_patterns else &uia_tree_leaf_patterns,
            .level = r.depth + 1,
            .expand_state = state,
            .expanded = if (r.has_children) r.expanded else null,
            .row = index,
        };
    }

    pub fn select(self: UiaTree, index: usize) TreeUpdate {
        return self.ctrl.pointerPress(index, .left, .{});
    }

    pub fn expand(self: UiaTree, index: usize) ?TreeUpdate {
        if (index >= self.ctrl.rowsSlice().len) return null;
        const r = self.ctrl.rowsSlice()[index];
        if (!r.has_children or r.expanded) return null;
        return self.ctrl.toggle(index);
    }

    pub fn collapse(self: UiaTree, index: usize) ?TreeUpdate {
        if (index >= self.ctrl.rowsSlice().len) return null;
        const r = self.ctrl.rowsSlice()[index];
        if (!r.has_children or !r.expanded) return null;
        return self.ctrl.toggle(index);
    }

    pub fn invoke(self: UiaTree, index: usize) ?TreeUpdate {
        if (index >= self.ctrl.rowsSlice().len) return null;
        const r = self.ctrl.rowsSlice()[index];
        if (r.has_children) return self.ctrl.toggle(index);
        return .{ .activated = r.node, .focus_index = if (self.ctrl.focus) |f| f.index else null };
    }
};
