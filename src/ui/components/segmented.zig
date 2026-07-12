//! Segmented control — exclusive button group.
const std = @import("std");
const types = @import("../types.zig");
const Color = types.Color;
const Rect = types.Rect;

pub fn segmented(ui: anytype, opts: anytype) bool {
    const size = ui.theme.font_size;
    const h = ui.theme.button_h;
    const n = opts.items.len;
    if (n == 0) return false;
    const r = ui.alloc(opts.w, h);
    const seg_w = r.w / @as(f32, @floatFromInt(n));
    var changed = false;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const sr = Rect{
            .x = r.x + seg_w * @as(f32, @floatFromInt(i)),
            .y = r.y,
            .w = if (i + 1 == n) r.w - seg_w * @as(f32, @floatFromInt(i)) else seg_w,
            .h = h,
        };
        var idbuf: [48]u8 = undefined;
        const id_s = std.fmt.bufPrint(&idbuf, "{s}#seg{d}", .{ opts.id, i }) catch "seg";
        const st = ui.interact(ui.id(id_s), sr, false);
        const on = opts.selected.* == i;
        const fill: Color = if (on) ui.theme.accent else if (st.hot) ui.theme.button_hot else ui.theme.button;
        ui.drawRectBorder(sr, fill, ui.theme.panel_border, 1);
        const m = ui.font.measure(opts.items[i], size);
        // White on accent (selected) and normal text otherwise — readable on dark chrome.
        const tc: Color = if (on) .{ 1, 1, 1, 1 } else ui.theme.text;
        ui.drawText(sr.x + (sr.w - m.w) * 0.5, sr.y + (sr.h - m.h) * 0.5, size, tc, opts.items[i]);
        if (st.clicked and !on) {
            opts.selected.* = i;
            changed = true;
        }
        if (st.hot) ui.setSoftCursor(.cursor_hand_open);
    }
    return changed;
}
