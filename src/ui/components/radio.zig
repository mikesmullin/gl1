//! Reusable UI component.
const std = @import("std");
const types = @import("../types.zig");
const te = @import("../text_edit.zig");
const Color = types.Color;
const Rect = types.Rect;
const Id = types.Id;

pub fn radio(ui: anytype, opts: anytype) bool {
    const i = ui.id(opts.id);
    const box = 18.0;
    const size = ui.theme.font_size;
    const m = ui.font.measure(opts.label, size);
    const r = ui.alloc(box + 8 + m.w, ui.theme.row_h);
    const br = Rect{ .x = r.x, .y = r.y + (r.h - box) * 0.5, .w = box, .h = box };
    const st = ui.interact(i, r, false);
    if (st.clicked) opts.group.* = opts.value;
    const on = opts.group.* == opts.value;
    ui.drawRectBorder(br, ui.theme.input_bg, ui.theme.panel_border, 1);
    if (on) {
        const inset = 4;
        ui.drawRect(.{
            .x = br.x + inset,
            .y = br.y + inset,
            .w = br.w - 2 * inset,
            .h = br.h - 2 * inset,
        }, ui.theme.accent);
    }
    ui.drawText(r.x + box + 8, r.y + (r.h - m.h) * 0.5, size, ui.theme.text, opts.label);
    return st.clicked;
}
