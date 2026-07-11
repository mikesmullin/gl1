//! Blender-style number slider.
//! - Full-height bar (looks like a text field + progress fill)
//! - Value centered on the bar
//! - Click anywhere to grab; relative drag (cursor hidden) changes the value
const std = @import("std");
const types = @import("../types.zig");
const Color = types.Color;
const Rect = types.Rect;
const Id = types.Id;
const sapp = @import("sokol").app;

pub fn slider(ui: anytype, opts: anytype) bool {
    const i = ui.id(opts.id);
    const size = ui.theme.font_size;
    const row_h = ui.theme.row_h;
    const r = ui.alloc(opts.w, row_h);

    // Label left, bar takes the rest (Blender property-row feel).
    const gap: f32 = 8;
    const label_m = ui.font.measure(opts.label, size);
    const label_w = @min(@max(label_m.w + 4, 48), opts.w * 0.40);
    ui.drawText(r.x, r.y + (row_h - ui.font.lineHeight(size)) * 0.5, size, ui.theme.text_dim, opts.label);

    const bar = Rect{
        .x = r.x + label_w + gap,
        .y = r.y + 2,
        .w = @max(40, r.w - label_w - gap),
        .h = row_h - 4,
    };

    const st = ui.interact(i, bar, false);
    var changed = false;
    const range = opts.max - opts.min;
    const span = if (range != 0) range else 1;

    // Start grab: relative drag from current value (not absolute click position).
    if (st.hot and ui.input.mousePressed(.left) and ui.drag.isNone()) {
        ui.drag = i;
        ui.drag_value0 = opts.value.*;
        ui.drag_anchor = 0; // accumulated mouse_dx while locked
        ui.mouse_captured_for_drag = true;
        sapp.lockMouse(true);
        sapp.showMouse(false);
    }

    // While dragging this slider: value follows relative mouse motion.
    // Full bar width of drag ≈ full [min, max] range (comfortable sensitivity).
    if (ui.drag.eq(i) and ui.input.mouseDown(.left)) {
        ui.drag_anchor += ui.input.mouse_dx;
        const nv = std.math.clamp(
            ui.drag_value0 + (ui.drag_anchor / bar.w) * span,
            opts.min,
            opts.max,
        );
        if (nv != opts.value.*) {
            opts.value.* = nv;
            changed = true;
        }
    }

    // Release: restore cursor (also handled in beginFrame as safety).
    if (ui.drag.eq(i) and ui.input.mouseReleased(.left)) {
        ui.drag = .{};
        if (ui.mouse_captured_for_drag) {
            ui.mouse_captured_for_drag = false;
            sapp.lockMouse(false);
            sapp.showMouse(true);
        }
    }

    const t = if (span != 0) std.math.clamp((opts.value.* - opts.min) / span, 0, 1) else 0;

    // Bar background (input-like) + progress fill
    const border = if (st.hot or st.active or ui.drag.eq(i)) ui.theme.accent else ui.theme.panel_border;
    ui.drawRectBorder(bar, ui.theme.input_bg, border, 1);
    if (t > 0) {
        const fill_w = @max(0, (bar.w - 2) * t);
        ui.drawRect(.{
            .x = bar.x + 1,
            .y = bar.y + 1,
            .w = fill_w,
            .h = bar.h - 2,
        }, ui.theme.slider_fill);
    }

    // Value centered on the bar (over the fill)
    var buf: [32]u8 = undefined;
    const val_s = std.fmt.bufPrint(&buf, "{d:.2}", .{opts.value.*}) catch "?";
    const vm = ui.font.measure(val_s, size);
    const tx = bar.x + (bar.w - vm.w) * 0.5;
    const ty = bar.y + (bar.h - ui.font.lineHeight(size)) * 0.5;
    ui.drawText(tx, ty, size, ui.theme.text, val_s);

    return changed;
}
