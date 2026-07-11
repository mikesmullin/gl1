//! Reusable UI component.
const std = @import("std");
const types = @import("../types.zig");
const te = @import("../text_edit.zig");
const Color = types.Color;
const Rect = types.Rect;
const Id = types.Id;

pub fn label(ui: anytype, opts: anytype) void {
    const size = opts.size orelse ui.theme.font_size;
    const color = opts.color orelse ui.theme.text;
    const m = ui.font.measure(opts.text, size);
    const r = ui.alloc(m.w, @max(m.h, ui.theme.row_h * 0.7));
    ui.drawText(r.x, r.y + 2, size, color, opts.text);
}
