//! Reusable UI component.
const std = @import("std");
const types = @import("../types.zig");
const te = @import("../text_edit.zig");
const Color = types.Color;
const Rect = types.Rect;
const Id = types.Id;

pub fn toggle(ui: anytype, opts: anytype) bool {
    const i = ui.id(opts.id);
    const track_w: f32 = 40;
    const track_h: f32 = 20;
    const size = ui.theme.font_size;
    const m = ui.font.measure(opts.label, size);
    const r = ui.alloc(track_w + 8 + m.w, ui.theme.row_h);
    const tr = Rect{
        .x = r.x,
        .y = r.y + (r.h - track_h) * 0.5,
        .w = track_w,
        .h = track_h,
    };
    const st = ui.interact(i, r, false);
    if (st.clicked) opts.value.* = !opts.value.*;
    const fill: Color = if (opts.value.*) ui.theme.accent else ui.theme.slider_track;
    ui.drawRectBorder(tr, fill, ui.theme.panel_border, 1);
    const knob_x = if (opts.value.*) tr.x + tr.w - track_h + 2 else tr.x + 2;
    ui.drawRect(.{ .x = knob_x, .y = tr.y + 2, .w = track_h - 4, .h = track_h - 4 }, ui.theme.text);
    ui.drawText(r.x + track_w + 8, r.y + (r.h - m.h) * 0.5, size, ui.theme.text, opts.label);
    return st.clicked;
}
