//! 内建控件。控件只通过 ui/layout/input/theme/gfx/text 的公开接口实现（REQ-ARCH-005）。

const std = @import("std");
const core = @import("core.zig");
const platform = @import("platform.zig");
const gfx = @import("gfx.zig");
const text = @import("text.zig");
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
    const owned = text.layoutOwned(ui_ptr.treeAlloc(), s, style, ui_ptr.scale, opts) catch @panic("nano_gui: text layout allocation failed");
    return owned.layout;
}

fn styleFor(t: *const Theme, token: theme.FontToken) text.Style {
    return t.fonts.get(token);
}

fn hashStr(seed: u64, s: []const u8) u64 {
    return core.hashBytes(seed, s);
}

// ---------------------------------------------------------------------------
// label
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
    props.* = .{ .label = label_text, .cl = l, .color = opts.color, .variant = opts.variant, .icon = opts.icon };
    const node = ui_ptr.leaf(id, .{ .layout = p, .flags = .{ .focusable = opts.variant == .link, .tab_stop = opts.variant == .link, .disabled = !opts.enabled }, .paint = paintLabel, .props = props, .paint_key = core.hashBytes(0x6611, label_text) ^ @backingInt(opts.variant) });
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
// button
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
        });
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
// checkbox / radio / switch
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
            const thumb_w = sh - 4;
            const thumb = core.Rect{ .x = if (p.checked) track.right() - thumb_w - 2 else track.x + 2, .y = track.y + 2, .w = thumb_w, .h = thumb_w };
            ctx.draw.canvas.fillRoundRect(thumb, t.metric(.radius_mark), t.color(.surface_raised_hover_top));
            if (v.focused_visible) theme.drawFocusRing(&ctx.draw, track, .radius_control, v);
            if (p.label.len > 0) text.draw(ctx.draw.canvas, p.tl, .{ .x = r.x + sw + t.metric(.gap_sm), .y = r.y + (r.h - p.tl.size.h) * 0.5 }, if (v.disabled) t.color(.text_disabled) else t.color(.text_primary), .{});
        },
    }
    _ = &v;
}

// ---------------------------------------------------------------------------
// slider / progress / separator / panel
// ---------------------------------------------------------------------------

pub const SliderOptions = struct {
    key: ?ui.Key = null,
    debug_name: ?[]const u8 = null,
    enabled: bool = true,
    min: f32 = 0,
    max: f32 = 1,
    step: f32 = 0,
    layout: layout.ItemOptions = .{},
};
pub const SliderResult = struct { hovered: bool = false, dragging: bool = false, focused: bool = false, changed: bool = false, value: f32 = 0 };

const SliderProps = struct { value: f32, min: f32, max: f32 };

pub fn slider(ui_ptr: *Ui, src: std.builtin.SourceLocation, value: *f32, opts: SliderOptions) SliderResult {
    const id = ui_ptr.id(src, opts.key);
    const t = ui_ptr.theme_ptr;
    var p = layout.Params{
        .kind = .leaf,
        .main = .fit,
        .cross = .fit,
        .content = .{ .size = .{ .x = 120, .y = t.metric(.control_h) } },
    };
    applyItem(&p, opts.layout);
    const props = ui_ptr.treeAlloc().create(SliderProps) catch @panic("nano_gui: props allocation failed");
    props.* = .{ .value = value.*, .min = opts.min, .max = opts.max };
    const node = ui_ptr.leaf(id, .{ .layout = p, .flags = .{ .focusable = opts.enabled }, .paint = paintSlider, .props = props, .paint_key = @as(u64, @as(u32, @bitCast(value.*))), .paint_outset = t.metric(.focus_ring_w) });
    node.src_file = src.file;
    node.src_line = src.line;
    if (opts.debug_name) |dn| node.debug_name = dn;
    const it = ui_ptr.interact(id, .{ .sense = .{ .hover = true, .click = true, .drag = true }, .handles = .{ .groups = .{ .arrows = true, .home_end = true } } });
    var result = SliderResult{ .hovered = it.hovered, .dragging = it.dragging, .focused = it.focused, .value = value.* };
    if (opts.enabled) {
        var changed = false;
        if ((it.clicked or it.dragging) and it.pointer != null) {
            const frac = std.math.clamp(it.pointer.?.x / @max(1, @as(f32, @floatFromInt(ui_ptr.getPrevNode(id).?.abs.w)) / ui_ptr.scale), 0, 1);
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
    const track = core.Rect{ .x = r.x + tw * 0.5, .y = r.y + (r.h - track_h) * 0.5, .w = @max(1, r.w - tw), .h = track_h };
    theme.drawTrack(&ctx.draw, track);
    const frac = if (p.max > p.min) std.math.clamp((p.value - p.min) / (p.max - p.min), 0, 1) else 0;
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
        .main = .fit,
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
    return .{ .id = id };
}
pub fn endGroupBox(ui_ptr: *Ui) void {
    ui_ptr.endColumn();
}

// ---------------------------------------------------------------------------
// image / icon
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
    }
}

// ---------------------------------------------------------------------------
// scroll view
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
// splitter
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
    const o = layout.ContainerOptions{ .debug_name = opts.debug_name, .main = .{ .grow = 1 }, .cross = .fill };
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
// tabs / toolbar / status bar
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
    const o = layout.ContainerOptions{ .debug_name = opts.debug_name, .main = .fixedSize(ui_ptr.theme_ptr.metric(.control_h_sm)), .cross = .fill, .padding = core.Insets.symmetric(opts.padding, 2), .gap = opts.gap, .cross_align = .center };
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
// text input
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
    placeholder: []const u8 = "",
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
};

const TextInputProps = struct {
    tl: *const text.Layout,
    placeholder: []const u8,
    caret_px: i32,
    placeholder_layout: ?*const text.Layout,
};

pub fn textInput(ui_ptr: *Ui, src: std.builtin.SourceLocation, buf: *TextBuf, opts: TextInputOptions) TextInputResult {
    const id = ui_ptr.id(src, opts.key);
    const t = ui_ptr.theme_ptr;
    const style = styleFor(t, .body);
    const st = ui_ptr.stateSticky(TextInputState, id, .{ .caret = buf.len() });
    st.caret = @min(st.caret, buf.len());
    const l = makeLayout(ui_ptr, buf.slice(), style, .{ .newlines = .as_space });
    var p = layout.Params{ .kind = .leaf, .main = .fit, .cross = .fit, .content = .{ .size = .{ .x = @max(120, l.size.w + t.metric(.pad_input_x) * 2), .y = t.metric(.control_h) } } };
    applyItem(&p, opts.layout);
    const placeholder_layout = if (opts.placeholder.len > 0) makeLayout(ui_ptr, opts.placeholder, style, .{ .newlines = .as_space }) else null;
    const props = ui_ptr.treeAlloc().create(TextInputProps) catch @panic("nano_gui: props allocation failed");
    props.* = .{ .tl = l, .placeholder = opts.placeholder, .caret_px = 0, .placeholder_layout = placeholder_layout };
    const node = ui_ptr.leaf(id, .{
        .layout = p,
        .flags = .{ .focusable = opts.enabled, .disabled = !opts.enabled },
        .paint = paintTextInput,
        .props = props,
        .paint_outset = t.metric(.focus_ring_w),
        .paint_key = core.hashBytes(0xbbcc, buf.slice()) ^ @as(u64, buf.revision()) << 8,
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
                    var tmp: [4]u8 = undefined;
                    const n = core.utf8Encode(cp, &tmp);
                    if (st.caret <= buf.len()) {
                        buf.replace(st.caret, st.caret, tmp[0..n]) catch {};
                        st.caret += n;
                        result.changed = true;
                    }
                },
                .ime_commit => |txt| {
                    buf.replace(st.caret, st.caret, txt) catch {};
                    st.caret += txt.len;
                    result.changed = true;
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
    if (result.changed) buf.revision_value +%= 1;
    props.caret_px = @intFromFloat(@round(measurePrefix(buf.slice(), st.caret, style, ui_ptr.scale, t) * ui_ptr.scale));
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
    theme.drawSunken(&ctx.draw, r, .radius_control, v, false);
    const pad = t.metric(.pad_input_x);
    ctx.draw.canvas.pushClip(.{ .x = r.x + pad, .y = r.y, .w = @max(0, r.w - pad * 2), .h = r.h });
    const fg = if (v.disabled) t.color(.text_disabled) else t.color(.text_primary);
    if (p.tl.text.len == 0 and p.placeholder_layout != null) {
        text.draw(ctx.draw.canvas, p.placeholder_layout.?, .{ .x = r.x + pad, .y = r.y + (r.h - p.placeholder_layout.?.size.h) * 0.5 }, t.color(.text_placeholder), .{});
    } else {
        text.draw(ctx.draw.canvas, p.tl, .{ .x = r.x + pad, .y = r.y + (r.h - p.tl.size.h) * 0.5 }, fg, .{});
    }
    if (v.focused_visible) {
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
// tooltip
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
// spin box
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

pub fn comboBox(ui_ptr: *Ui, src: std.builtin.SourceLocation, selected: *?u32, items: ItemSource, opts: ComboBoxOptions) ComboBoxResult {
    const id = ui_ptr.id(src, opts.key);
    const t = ui_ptr.theme_ptr;
    const text_value = if (selected.*) |i| items.textAt(i, ui_ptr.treeAlloc()) else (opts.placeholder orelse "");
    const l = makeLayout(ui_ptr, text_value, styleFor(t, .body), .{ .newlines = .as_space });
    const w = @max(96, l.size.w + t.metric(.pad_input_x) * 2 + t.metric(.icon_sm));
    var p = layout.Params{ .kind = .leaf, .main = .fit, .cross = .fit, .content = .{ .size = .{ .x = w, .y = heightFor(t, opts.size) } } };
    applyItem(&p, opts.layout);
    const props = ui_ptr.treeAlloc().create(ComboProps) catch @panic("nano_gui: props allocation failed");
    props.* = .{ .tl = l };
    const node = ui_ptr.leaf(id, .{ .layout = p, .flags = .{ .focusable = opts.enabled, .disabled = !opts.enabled }, .paint = paintCombo, .props = props, .paint_outset = t.metric(.focus_ring_w), .paint_key = core.hashBytes(0xeeff, text_value) });
    node.src_file = src.file;
    node.src_line = src.line;
    if (opts.debug_name) |dn| node.debug_name = dn;
    const it = ui_ptr.interact(id, .{ .sense = .{ .hover = true, .click = true }, .handles = .{ .groups = .{ .arrows = true, .enter = true } } });
    var res = ComboBoxResult{ .id = id, .hovered = it.hovered, .focused = it.focused };
    if (opts.enabled and it.clicked) {
        const n = items.count();
        if (n > 0) {
            const next = if (selected.*) |s| (s + 1) % n else 0;
            selected.* = next;
            res.picked = next;
            res.changed = true;
        }
    }
    for (ui_ptr.events(id)) |ev| switch (ev) {
        .key_down => |k| {
            const n = items.count();
            if (n == 0) continue;
            if (k.key == .down) {
                selected.* = if (selected.*) |s| (s + 1) % n else 0;
                res.changed = true;
                res.picked = selected.*;
            } else if (k.key == .up) {
                selected.* = if (selected.*) |s| (s + n - 1) % n else n - 1;
                res.changed = true;
                res.picked = selected.*;
            }
        },
        else => {},
    };
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

pub const TextAreaState = struct {
    buf: TextBuf,
    caret: usize = 0,
    anchor: usize = 0,
    modified: bool = false,
    eol: Eol = .lf,
    had_bom: bool = false,

    pub fn init(allocator: std.mem.Allocator) TextAreaState {
        return .{ .buf = TextBuf.init(allocator) };
    }
    pub fn deinit(self: *TextAreaState) void {
        self.buf.deinit();
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
    const t = ui_ptr.theme_ptr;
    const style = if (opts.mono) styleFor(t, .mono) else styleFor(t, .body);
    var lines = std.ArrayListUnmanaged(*const text.Layout).empty;
    defer lines.deinit(ui_ptr.treeAlloc());
    var line_it = std.mem.splitScalar(u8, st.buf.slice(), '\n');
    var caret_line: usize = 0;
    var caret_col: usize = 0;
    var seen: usize = 0;
    var best_col: f32 = 0;
    while (line_it.next()) |line| {
        const l = makeLayout(ui_ptr, line, style, .{ .newlines = .break_lines });
        lines.append(ui_ptr.treeAlloc(), l) catch {};
        if (st.caret >= seen and st.caret <= seen + line.len) {
            caret_line = lines.items.len - 1;
            caret_col = st.caret - seen;
            best_col = text.advance(style, ui_ptr.scale) * @as(f32, @floatFromInt(core.codepointCount(line[0..@min(caret_col, line.len)])));
        }
        seen += line.len + 1;
    }
    const height = @max(80, @as(f32, @floatFromInt(lines.items.len)) * style.size * 1.25 + t.metric(.pad_input_x) * 2);
    var p = layout.Params{
        .kind = .leaf,
        .main = .fit,
        .cross = .fit,
        .content = .{ .size = .{ .x = 260, .y = @min(height, 180) }, .key = hashStr(0x1357, st.buf.slice()) },
    };
    applyItem(&p, opts.layout);
    const props = ui_ptr.treeAlloc().create(TextAreaProps) catch @panic("nano_gui: props allocation failed");
    props.* = .{
        .text_layouts = try_dupe_layouts(ui_ptr, lines.items),
        .caret_line = caret_line,
        .caret_x = best_col,
        .placeholder = if (opts.placeholder) |ph| makeLayout(ui_ptr, ph, style, .{ .newlines = .as_space }) else null,
    };
    const node = ui_ptr.leaf(id, .{
        .layout = p,
        .flags = .{ .focusable = opts.enabled, .disabled = !opts.enabled },
        .paint = paintTextArea,
        .props = props,
        .paint_outset = t.metric(.focus_ring_w),
        .paint_key = core.hashBytes(0x2468, st.buf.slice()) ^ @as(u64, st.buf.revision()) << 8,
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
                st.buf.replace(st.caret, st.caret, tmp[0..n]) catch {};
                st.caret += n;
                st.modified = true;
                res.changed = true;
            },
            .ime_commit => |txt| {
                st.buf.replace(st.caret, st.caret, txt) catch {};
                st.caret += txt.len;
                st.modified = true;
                res.changed = true;
            },
            .key_down => |k| {
                switch (k.key) {
                    .backspace => if (st.caret > 0) {
                        const prev = text.prevGrapheme(st.buf.slice(), st.caret);
                        st.buf.replace(prev, st.caret, "") catch {};
                        st.caret = prev;
                        st.modified = true;
                        res.changed = true;
                    },
                    .delete => if (st.caret < st.buf.len()) {
                        const next = text.nextGrapheme(st.buf.slice(), st.caret);
                        st.buf.replace(st.caret, next, "") catch {};
                        st.modified = true;
                        res.changed = true;
                    },
                    .left => st.caret = text.prevGrapheme(st.buf.slice(), st.caret),
                    .right => st.caret = text.nextGrapheme(st.buf.slice(), st.caret),
                    .home => {
                        var i = st.caret;
                        while (i > 0 and st.buf.slice()[i - 1] != '\n') i -= 1;
                        st.caret = i;
                    },
                    .end => {
                        var i = st.caret;
                        while (i < st.buf.len() and st.buf.slice()[i] != '\n') i += 1;
                        st.caret = i;
                    },
                    .enter => {
                        st.buf.replace(st.caret, st.caret, "\n") catch {};
                        st.caret += 1;
                        st.modified = true;
                        res.changed = true;
                    },
                    .tab => if (opts.accepts_tab) {
                        st.buf.replace(st.caret, st.caret, "\t") catch {};
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
    res.caret = st.caret;
    res.selection = .{ .start = @min(st.caret, st.anchor), .end = @max(st.caret, st.anchor) };
    return res;
}

fn try_dupe_layouts(ui_ptr: *Ui, items: []const *const text.Layout) []const *const text.Layout {
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
    const st = ui_ptr.retained(TextAreaState, h.id, .pinned);
    st.buf.set(bytes) catch return error.OutOfMemory;
    st.modified = false;
    st.caret = 0;
    st.anchor = 0;
    var lines: u32 = 1;
    for (bytes) |c| if (c == '\n') {
        lines += 1;
    };
    return .{ .eol = .lf, .mixed = false, .had_bom = false, .lines = lines, .bytes = bytes.len };
}

pub fn textAreaText(ui_ptr: *Ui, h: TextAreaHandle, allocator: std.mem.Allocator, opts: SaveOptions) error{OutOfMemory}![]u8 {
    _ = opts;
    const st = ui_ptr.retained(TextAreaState, h.id, .pinned);
    return allocator.dupe(u8, st.buf.slice());
}

pub fn textAreaRange(ui_ptr: *Ui, h: TextAreaHandle, start: u64, end: u64, allocator: std.mem.Allocator) error{OutOfMemory}![]u8 {
    const st = ui_ptr.retained(TextAreaState, h.id, .pinned);
    const a = @min(@as(usize, @intCast(start)), st.buf.len());
    const b = @min(@as(usize, @intCast(end)), st.buf.len());
    return allocator.dupe(u8, st.buf.slice()[a..b]);
}

pub fn textAreaReplace(ui_ptr: *Ui, h: TextAreaHandle, start: u64, end: u64, bytes: []const u8) TextAreaError!void {
    const st = ui_ptr.retained(TextAreaState, h.id, .pinned);
    st.buf.replace(@intCast(start), @intCast(end), bytes) catch return error.OutOfMemory;
    st.modified = true;
}

pub const TextAreaInfo = struct { bytes: u64, lines: u32, revision: u64, eol: Eol, modified: bool };

pub fn textAreaInfo(ui_ptr: *const Ui, h: TextAreaHandle) ?TextAreaInfo {
    const st = ui_ptr.getState(TextAreaState, h.id) orelse return null;
    var lines: u32 = 1;
    for (st.buf.slice()) |c| if (c == '\n') {
        lines += 1;
    };
    return .{ .bytes = st.buf.len(), .lines = lines, .revision = st.buf.revision(), .eol = st.eol, .modified = st.modified };
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
// list / selection
// ---------------------------------------------------------------------------

pub const ItemKey = u64;
pub const SelectionMode = enum { none, single, multi };

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

    pub fn init(allocator: std.mem.Allocator) Selection {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Selection) void {
        self.keys.deinit(self.allocator);
    }
    pub fn contains(self: *const Selection, key: ItemKey) bool {
        for (self.keys.items) |k| if (k == key) return true;
        return false;
    }
    pub fn len(self: *const Selection) usize {
        return self.keys.items.len;
    }
    pub fn clear(self: *Selection) void {
        self.keys.clearRetainingCapacity();
    }
    pub fn add(self: *Selection, key: ItemKey) error{OutOfMemory}!void {
        if (!self.contains(key)) try self.keys.append(self.allocator, key);
    }
    pub fn remove(self: *Selection, key: ItemKey) void {
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
            if (!found) _ = self.keys.orderedRemove(i) else i += 1;
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
    if (p.selected) {
        ctx.draw.canvas.fillRect(r, t.color(.accent_fill_bottom));
    } else if (p.hovered) {
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

pub const ListIter = struct {
    ui_ptr: *Ui,
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
        if (self.open_row) self.ui_ptr.endRow();
        const i = self.index;
        self.index += 1;
        const key = self.opts.data.keyAt(i);
        const row_id = self.ui_ptr.id(@src(), ui.Key.int(key));
        _ = self.ui_ptr.beginRow(@src(), .{ .main = .fixedSize(self.row_h), .cross = .fill, .padding = core.Insets.symmetric(4, 0), .cross_align = .center });
        const it = self.ui_ptr.interact(row_id, .{ .sense = .{ .hover = true, .click = true }, .cursor = .arrow });
        var selected = false;
        var changed = false;
        if (self.opts.selection) |sel| {
            if (it.clicked) {
                switch (self.opts.mode) {
                    .single => {
                        sel.setOnly(key) catch {};
                        changed = true;
                    },
                    .multi => {
                        _ = sel.toggle(key) catch {};
                        changed = true;
                    },
                    .none => {},
                }
                if (changed) self.ui_ptr.invalidate(.build);
            }
            selected = sel.contains(key);
        }
        if (it.clicked) self.focused_index = i;
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
            .focused = self.focused_index == i,
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
    const content_id = ui_ptr.beginColumn(src, .{ .main = .fit, .cross = .fill, .gap = .none });
    _ = content_id;
    const viewport_h: f32 = if (sv.viewport) |v| v.y else 240;
    const offset_y: f32 = sv.offset.y;
    const first: usize = if (count == 0) 0 else @min(count - 1, @as(usize, @intFromFloat(@max(0, @floor(offset_y / @max(1, row_h))))));
    const visible: usize = @max(1, @as(usize, @intFromFloat(@ceil(viewport_h / @max(1, row_h)))) + 2);
    const last: usize = @min(count, first + visible);
    if (first > 0) listSpacer(ui_ptr, @as(f32, @floatFromInt(first)) * row_h);
    const iter = ListIter{
        .ui_ptr = ui_ptr,
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
    if (iter.open_row) ui_ptr.endRow();
    const limit = if (iter.last > iter.first) iter.last else iter.count;
    if (limit < iter.count) listSpacer(ui_ptr, @as(f32, @floatFromInt(iter.count - limit)) * iter.row_h);
    ui_ptr.endColumn();
    _ = endScrollView(ui_ptr, .{ .id = iter.scroll_id, .offset = .{}, .viewport = null, .line = iter.row_h });
    var res = ListResult{ .selection = iter.opts.selection, .focus_index = iter.focused_index };
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
            if (!self.contains(key)) try self.keys.append(self.allocator, key);
        } else {
            var i: usize = 0;
            while (i < self.keys.items.len) : (i += 1) {
                if (self.keys.items[i] == key) {
                    _ = self.keys.orderedRemove(i);
                    return;
                }
            }
        }
    }
    pub fn clear(self: *ExpandedSet) void {
        self.keys.clearRetainingCapacity();
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

const FlatRow = struct { node: TreeNode, key: ItemKey, depth: u16, has_children: bool, expanded: bool };
const TreeRuntime = struct {
    ui_ptr: *Ui,
    model: TreeModel,
    opts: TreeOptions,
    exp: *ExpandedSet,
    flat: std.ArrayListUnmanaged(FlatRow) = .empty,
    alloc: std.mem.Allocator,
    cursor: usize = 0,
    first: usize = 0,
    last: usize = 0,
    row_h: f32 = 22,
    scroll: ScrollViewHandle,
    open_row: bool = false,

    fn flatten(self: *TreeRuntime, node: TreeNode, depth: u16) void {
        const ctx = self.model.ctx;
        const n = self.model.child_count(ctx, node);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const child = self.model.child_at(ctx, node, i);
            const key = self.model.key_of(ctx, child);
            const has = self.model.has_children(ctx, child);
            const expanded = self.exp.contains(key) or depth < self.opts.initially_expanded_depth;
            self.flat.append(self.alloc, .{ .node = child, .key = key, .depth = depth, .has_children = has, .expanded = expanded }) catch {};
            if (has and expanded) self.flatten(child, depth + 1);
        }
    }

    fn nextRow(self: *TreeRuntime) ?TreeRow {
        if (self.open_row) {
            self.ui_ptr.endRow();
            self.open_row = false;
        }
        if (self.cursor >= self.last) return null;
        const i = self.cursor;
        self.cursor += 1;
        const e = self.flat.items[i];
        const row_id = self.ui_ptr.id(@src(), ui.Key.int(e.key));
        const indent = @as(f32, @floatFromInt(e.depth)) * self.ui_ptr.theme_ptr.metric(.indent);
        _ = self.ui_ptr.beginRow(@src(), .{ .main = .fixedSize(self.row_h), .cross = .fill, .padding = .{ .l = indent, .t = 0, .r = 4, .b = 0 }, .cross_align = .center });
        const it = self.ui_ptr.interact(row_id, .{ .sense = .{ .hover = true, .click = true }, .cursor = .arrow });
        var selected = false;
        if (self.opts.selection) |sel| {
            if (it.clicked) {
                switch (self.opts.mode) {
                    .single => sel.setOnly(e.key) catch {},
                    .multi => _ = sel.toggle(e.key) catch {},
                    .none => {},
                }
            }
            selected = sel.contains(e.key);
        }
        if (e.has_children and it.double_clicked) {
            self.exp.set(e.key, !e.expanded, null) catch {};
            self.ui_ptr.invalidate(.build);
        }
        for (self.ui_ptr.events(row_id)) |ev| switch (ev) {
            .key_down => |k| {
                if (e.has_children and (k.key == .right or k.key == .left)) {
                    self.exp.set(e.key, k.key == .right, null) catch {};
                    self.ui_ptr.invalidate(.build);
                }
            },
            else => {},
        };
        self.open_row = true;
        return .{
            .index = i,
            .key = e.key,
            .node = e.node,
            .depth = e.depth,
            .has_children = e.has_children,
            .expanded = e.expanded,
            .selected = selected,
            .focused = false,
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
    _ = ui_ptr.beginColumn(src, .{ .main = .fit, .cross = .fill, .gap = .none });
    const exp: *ExpandedSet = opts.expanded orelse ui_ptr.retained(ExpandedSet, id, .sticky);
    const row_h = ui_ptr.theme_ptr.metric(.row_h);
    const rt = ui_ptr.treeAlloc().create(TreeRuntime) catch @panic("nano_gui: tree runtime");
    rt.* = .{ .ui_ptr = ui_ptr, .model = model, .opts = opts, .exp = exp, .alloc = ui_ptr.treeAlloc(), .row_h = row_h, .scroll = scroll };
    rt.flatten(.root, 0);
    const viewport_h: f32 = if (scroll.viewport) |v| v.y else 240;
    const first: usize = if (rt.flat.items.len == 0) 0 else @min(rt.flat.items.len - 1, @as(usize, @intFromFloat(@max(0, @floor(scroll.offset.y / @max(1, row_h))))));
    const visible: usize = @max(1, @as(usize, @intFromFloat(@ceil(viewport_h / @max(1, row_h)))) + 2);
    rt.first = first;
    rt.last = @min(rt.flat.items.len, first + visible);
    rt.cursor = first;
    if (first > 0) listSpacer(ui_ptr, @as(f32, @floatFromInt(first)) * row_h);
    ui_ptr.aux_ptr = rt;
    ui_ptr.aux_id = id;
    return .{ .rt = rt };
}

pub fn endTree(ui_ptr: *Ui) TreeResult {
    const raw = ui_ptr.aux_ptr orelse return .{};
    const rt: *TreeRuntime = @ptrCast(@alignCast(raw));
    if (rt.open_row) ui_ptr.endRow();
    if (rt.last < rt.flat.items.len) listSpacer(ui_ptr, @as(f32, @floatFromInt(rt.flat.items.len - rt.last)) * rt.row_h);
    ui_ptr.endColumn();
    _ = endScrollView(ui_ptr, rt.scroll);
    ui_ptr.aux_ptr = null;
    var res = TreeResult{ .selection = rt.opts.selection };
    if (rt.opts.selection) |sel| {
        var n: usize = 0;
        var i: usize = rt.first;
        while (i < rt.last) : (i += 1) if (sel.contains(rt.flat.items[i].key)) {
            n += 1;
        };
        res.selected_visible = n;
    }
    return res;
}

pub fn treeLabel(ui_ptr: *Ui, src: std.builtin.SourceLocation, row: TreeRow, label_text: []const u8, opts: ListLabelOptions) void {
    _ = opts;
    _ = label(ui_ptr, src, label_text, .{ .style = .body, .color = if (row.selected) .on_accent else .primary, .layout = .{ .main = .{ .grow = 1 } } });
}

// table ----------------------------------------------------------------------

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
    open_row: bool = false,

    fn nextRow(self: *TableRuntime) ?TableRow {
        if (self.open_row) {
            self.ui_ptr.endRow();
            self.open_row = false;
        }
        if (self.cursor >= self.last) return null;
        const i = self.cursor;
        self.cursor += 1;
        const key = if (self.opts.data.key_of) |f| f(self.opts.data.ctx, i) else @as(ItemKey, @intCast(i));
        const row_id = self.ui_ptr.id(@src(), ui.Key.int(key));
        _ = self.ui_ptr.beginRow(@src(), .{ .main = .fixedSize(self.row_h), .cross = .fill, .padding = core.Insets.symmetric(4, 0), .cross_align = .center });
        const it = self.ui_ptr.interact(row_id, .{ .sense = .{ .hover = true, .click = true }, .cursor = .arrow });
        var selected = false;
        if (self.opts.selection) |sel| {
            if (it.clicked) switch (self.opts.mode) {
                .single => sel.setOnly(key) catch {},
                .multi => _ = sel.toggle(key) catch {},
                .none => {},
            };
            selected = sel.contains(key);
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

pub fn beginTable(ui_ptr: *Ui, src: std.builtin.SourceLocation, columns: []const TableColumn, count: usize, opts: TableOptions) TableIter {
    const id = ui_ptr.id(src, opts.key);
    const t = ui_ptr.theme_ptr;
    const row_h = opts.row_height orelse t.metric(.row_h);
    _ = ui_ptr.beginColumn(src, .{ .main = .{ .grow = 1 }, .cross = .fill, .gap = .none });
    const tmp = ui_ptr.treeAlloc().alloc(i32, columns.len) catch @panic("nano_gui: table widths");
    const widths = ui_ptr.treeAlloc().alloc(f32, columns.len) catch @panic("nano_gui: table widths");
    const header_w = ui_ptr.treeAlloc().alloc(i32, columns.len) catch @panic("nano_gui: table widths");
    @memset(header_w, 0);
    const approx_w: i32 = @intFromFloat(@max(200, @as(f32, @floatFromInt(ui_ptr.viewport.w)) - 32));
    const layout_cols = ui_ptr.treeAlloc().alloc(layout.Column, columns.len) catch @panic("nano_gui: table columns");
    for (columns, 0..) |col, i| layout_cols[i] = .{ .width = col.width, .min = col.min, .max = col.max };
    layout.solveColumns(layout_cols, header_w, approx_w, true, 0, ui_ptr.scale, tmp);
    for (tmp, 0..) |v, i| widths[i] = @as(f32, @floatFromInt(v));
    _ = ui_ptr.beginRow(src, .{ .main = .fixedSize(t.metric(.header_h)), .cross = .fill, .gap = .none, .cross_align = .center });
    for (columns, 0..) |col, i| {
        if (col.hidden) continue;
        _ = label(ui_ptr, @src(), col.title, .{ .style = .small, .color = .secondary, .layout = .{ .main = .fixedSize(widths[i] / ui_ptr.scale) } });
    }
    ui_ptr.endRow();
    const scroll = beginScrollView(ui_ptr, src, .{
        .key = opts.key,
        .debug_name = opts.debug_name,
        .enabled = opts.enabled,
        .axes = .vertical,
        .bar_v = opts.scrollbar_v,
        .layout = .{ .main = .{ .grow = 1 }, .cross = .fill },
    });
    _ = ui_ptr.beginColumn(src, .{ .main = .fit, .cross = .fill, .gap = .none });
    const viewport_h: f32 = if (scroll.viewport) |v| v.y else 240;
    const first: usize = if (count == 0) 0 else @min(count - 1, @as(usize, @intFromFloat(@max(0, @floor(scroll.offset.y / @max(1, row_h))))));
    const visible: usize = @max(1, @as(usize, @intFromFloat(@ceil(viewport_h / @max(1, row_h)))) + 2);
    const last = @min(count, first + visible);
    if (first > 0) listSpacer(ui_ptr, @as(f32, @floatFromInt(first)) * row_h);
    const hidden = ui_ptr.treeAlloc().alloc(bool, columns.len) catch @panic("nano_gui: table hidden");
    for (columns, 0..) |col, i| hidden[i] = col.hidden;
    const rt = ui_ptr.treeAlloc().create(TableRuntime) catch @panic("nano_gui: table runtime");
    rt.* = .{ .ui_ptr = ui_ptr, .opts = opts, .columns = columns, .widths = widths, .hidden = hidden, .count = count, .cursor = first, .first = first, .last = last, .row_h = row_h, .scroll = scroll };
    ui_ptr.aux_ptr = rt;
    ui_ptr.aux_id = id;
    return .{ .rt = rt, .id = id };
}

pub fn endTable(ui_ptr: *Ui) TableResult {
    const raw = ui_ptr.aux_ptr orelse return .{};
    const rt: *TableRuntime = @ptrCast(@alignCast(raw));
    if (rt.open_row) ui_ptr.endRow();
    if (rt.last < rt.count) listSpacer(ui_ptr, @as(f32, @floatFromInt(rt.count - rt.last)) * rt.row_h);
    ui_ptr.endColumn();
    _ = endScrollView(ui_ptr, rt.scroll);
    ui_ptr.endColumn();
    ui_ptr.aux_ptr = null;
    return .{ .selection = rt.opts.selection };
}

pub fn tableCellText(ui_ptr: *Ui, src: std.builtin.SourceLocation, cell: TableCell, label_text: []const u8, opts: struct { icon: ?theme.Icon = null }) void {
    _ = opts;
    _ = label(ui_ptr, src, label_text, .{
        .style = .body,
        .color = if (cell.selected) .on_accent else .primary,
        .layout = .{ .main = .fixedSize(cell.width / ui_ptr.scale) },
    });
}
pub fn setTableColumnHidden(_: *Ui, _: core.WidgetId, _: u16, _: bool) void {}

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
    const r = button(ui_ptr, src, label_text, .{ .variant = .quiet, .key = opts.key, .enabled = opts.enabled, .icon = opts.icon });
    const result = MenuItemResult{ .hovered = r.hovered, .clicked = r.clicked };
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
// dialog body / button row
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
        .main = .fit,
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
pub fn dialogButtons(ui_ptr: *Ui, src: std.builtin.SourceLocation, buttons: []const @import("app.zig").DialogButton) ?u32 {
    if (buttons.len == 0) return null;
    _ = ui_ptr.beginRow(src, .{ .main = .fit, .cross = .fit, .gap = .sm, .justify = .end, .cross_align = .center });
    var result: ?u32 = null;
    for (buttons) |b| {
        const variant: ButtonVariant = if (b.role == .default or b.role == .default_and_cancel) .accent else .neutral;
        const r = button(ui_ptr, @src(), b.label, .{ .variant = variant, .enabled = b.enabled });
        if (r.clicked) result = b.code;
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

pub fn comboBoxEditable(ui_ptr: *Ui, src: std.builtin.SourceLocation, text_buf: *TextBuf, _: ItemSource, opts: ComboBoxEditableOptions) ComboBoxResult {
    const r = textInput(ui_ptr, src, text_buf, .{
        .key = opts.key,
        .debug_name = opts.debug_name,
        .enabled = opts.enabled,
        .placeholder = opts.placeholder orelse "",
        .layout = opts.layout,
    });
    return .{ .hovered = r.hovered, .focused = r.focused, .changed = r.changed, .committed = r.committed };
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

pub fn statusPane(ui_ptr: *Ui, src: std.builtin.SourceLocation, label_text: []const u8, opts: StatusPaneOptions) StatusPaneResult {
    var item = opts.layout;
    if (opts.grow > 0) item.main = .{ .grow = opts.grow };
    if (opts.width) |w| item.main = .fixedSize(w);
    const r = label(ui_ptr, src, label_text, .{ .key = opts.key, .debug_name = opts.debug_name, .style = .small, .color = .secondary, .text_align = opts.@"align", .layout = item });
    return .{ .hovered = r.hovered };
}

pub fn tooltipIfTruncated(ui_ptr: *Ui, src: std.builtin.SourceLocation, owner: core.WidgetId, label_text: []const u8, opts: TooltipOptions) TooltipResult {
    return tooltip(ui_ptr, src, owner, label_text, opts);
}

pub const ChangeSource = enum { user, api, undo, redo, load };
pub const Change = struct { start: u64, removed: u64, inserted: u64, source: ChangeSource, revision: u64, line: u32 };
pub const ChangeFn = *const fn (ctx: ?*anyopaque, change: Change) void;
pub const Subscription = enum(u32) { none = 0, _ };

pub fn textAreaSubscribe(_: *Ui, _: TextAreaHandle, _: ChangeFn, _: ?*anyopaque) error{OutOfMemory}!Subscription {
    return .none;
}
pub fn textAreaUnsubscribe(_: *Ui, _: TextAreaHandle, _: Subscription) void {}

pub fn textInputSetSelection(ui_ptr: *Ui, id: core.WidgetId, _: u32, caret: u32) void {
    const st = ui_ptr.stateSticky(TextInputState, id, .{});
    st.caret = caret;
}

// 文档容器形式的标签页入口（内部复用 tabs 叶节点；内容由调用方在 endTabs 前声明）。
pub const TabSpec = struct { label: []const u8, icon: ?theme.Icon = null, closable: bool = false };
pub fn beginTabs(ui_ptr: *Ui, src: std.builtin.SourceLocation, tabs_spec: []const TabSpec, current: *usize, opts: TabsOptions) TabsResult {
    const labels = ui_ptr.treeAlloc().alloc([]const u8, tabs_spec.len) catch return .{};
    for (tabs_spec, 0..) |t, i| labels[i] = t.label;
    var o = opts;
    o.items = labels;
    o.selected = current;
    return tabs(ui_ptr, src, o);
}
pub fn beginTabsRetained(ui_ptr: *Ui, src: std.builtin.SourceLocation, tabs_spec: []const TabSpec, initial: usize, opts: TabsOptions) TabsResult {
    const cur = ui_ptr.stateSticky(usize, ui_ptr.id(src, opts.key), initial);
    return beginTabs(ui_ptr, src, tabs_spec, cur, opts);
}
pub fn endTabs(_: *Ui) void {}
