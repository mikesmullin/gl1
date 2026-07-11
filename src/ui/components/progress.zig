//! Reusable UI component.
const std = @import("std");
const types = @import("../types.zig");
const te = @import("../text_edit.zig");
const Color = types.Color;
const Rect = types.Rect;
const Id = types.Id;

pub fn progress(ui: anytype, opts: anytype) void {
    const size = ui.theme.font_size;
    const r = ui.alloc(opts.w, ui.theme.row_h);
    ui.drawText(r.x, r.y, size, ui.theme.text_dim, opts.label);
    const track = Rect{ .x = r.x, .y = r.y + 14, .w = opts.w, .h = 10 };
    const t = std.math.clamp(opts.value, 0, 1);
    ui.drawRect(track, ui.theme.slider_track);
    ui.drawRect(.{ .x = track.x, .y = track.y, .w = track.w * t, .h = track.h }, ui.theme.slider_fill);
}
