//! Reusable UI component.
const std = @import("std");
const types = @import("../types.zig");
const te = @import("../text_edit.zig");
const Color = types.Color;
const Rect = types.Rect;
const Id = types.Id;

pub fn spinner(ui: anytype, opts: anytype) bool {
    const size = ui.theme.font_size;
    const r = ui.alloc(opts.w, ui.theme.row_h + 12);
    ui.drawText(r.x, r.y, size, ui.theme.text_dim, opts.label);
    const row_y = r.y + 12;
    const bh = ui.theme.button_h - 4;
    const bw: f32 = 28;
    var changed = false;

    ui.pushId(opts.id);
    defer ui.popId();

    const minus_r = Rect{ .x = r.x, .y = row_y, .w = bw, .h = bh };
    const plus_r = Rect{ .x = r.x + opts.w - bw, .y = row_y, .w = bw, .h = bh };
    const mid = Rect{ .x = r.x + bw + 4, .y = row_y, .w = opts.w - 2 * bw - 8, .h = bh };

    const mi = ui.id("minus");
    const pi = ui.id("plus");
    const mst = ui.interact(mi, minus_r, false);
    const pst = ui.interact(pi, plus_r, false);
    ui.drawRectBorder(minus_r, if (mst.hot) ui.theme.button_hot else ui.theme.button, ui.theme.panel_border, 1);
    ui.drawRectBorder(plus_r, if (pst.hot) ui.theme.button_hot else ui.theme.button, ui.theme.panel_border, 1);
    ui.drawText(minus_r.x + 10, minus_r.y + 5, size, ui.theme.text, "-");
    ui.drawText(plus_r.x + 10, plus_r.y + 5, size, ui.theme.text, "+");
    ui.drawRectBorder(mid, ui.theme.input_bg, ui.theme.panel_border, 1);

    if (mst.clicked) {
        opts.value.* = @max(opts.min, opts.value.* - opts.step);
        changed = true;
    }
    if (pst.clicked) {
        opts.value.* = @min(opts.max, opts.value.* + opts.step);
        changed = true;
    }

    var buf: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d:.2}", .{opts.value.*}) catch "?";
    const sm = ui.font.measure(s, size);
    ui.drawText(mid.x + (mid.w - sm.w) * 0.5, mid.y + 5, size, ui.theme.text, s);
    return changed;
}
