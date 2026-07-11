//! Reusable UI component.
const std = @import("std");
const types = @import("../types.zig");
const te = @import("../text_edit.zig");
const Color = types.Color;
const Rect = types.Rect;
const Id = types.Id;

pub fn button(ui: anytype, opts: anytype) bool {
    const i = ui.id(opts.id);
    const size = ui.theme.font_size;
    const m = ui.font.measure(opts.label, size);
    const bw = if (opts.w > 0) opts.w else @max(m.w + 24, 80);
    const bh = ui.theme.button_h;
    const r = ui.alloc(bw, bh);

    const st = ui.interact(i, r, opts.disabled);
    const fill: Color = if (opts.disabled)
        ui.theme.button_disabled
    else if (st.active)
        ui.theme.button_active
    else if (st.hot)
        ui.theme.button_hot
    else
        ui.theme.button;

    ui.drawRectBorder(r, fill, ui.theme.panel_border, 1);
    const tx = r.x + (r.w - m.w) * 0.5;
    const ty = r.y + (r.h - m.h) * 0.5;
    const tc: Color = if (opts.disabled) ui.theme.text_dim else ui.theme.text;
    ui.drawText(tx, ty, size, tc, opts.label);
    return st.clicked;
}
