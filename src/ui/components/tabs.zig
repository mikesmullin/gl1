//! Reusable UI component.
const std = @import("std");
const types = @import("../types.zig");
const te = @import("../text_edit.zig");
const Color = types.Color;
const Rect = types.Rect;
const Id = types.Id;

pub fn tabs(ui: anytype, opts: anytype) bool {
    const bar_w = if (opts.w > 0) opts.w else ui.top().width - 2 * ui.top().pad;
    const r = ui.alloc(bar_w, ui.theme.row_h + 4);
    const n: f32 = @floatFromInt(@max(opts.items.len, 1));
    const tw = bar_w / n;
    var changed = false;
    ui.pushId(opts.id);
    defer ui.popId();
    for (opts.items, 0..) |item, idx| {
        const tr = Rect{
            .x = r.x + @as(f32, @floatFromInt(idx)) * tw,
            .y = r.y,
            .w = tw - 2,
            .h = r.h,
        };
        const tid = ui.id(item);
        const st = ui.interact(tid, tr, false);
        const on = opts.selected.* == idx;
        const fill: Color = if (on) ui.theme.selected else if (st.hot) ui.theme.button_hot else ui.theme.button;
        ui.drawRectBorder(tr, fill, ui.theme.panel_border, 1);
        const m = ui.font.measure(item, ui.theme.font_size);
        ui.drawText(tr.x + (tr.w - m.w) * 0.5, tr.y + (tr.h - m.h) * 0.5, ui.theme.font_size, if (on) ui.theme.accent else ui.theme.text, item);
        if (st.clicked) {
            opts.selected.* = idx;
            changed = true;
        }
    }
    return changed;
}
