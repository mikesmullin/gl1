//! Indeterminate spinner (rotating arc approximated with ticks).
const std = @import("std");
const types = @import("../types.zig");

pub fn spinner(ui: anytype, opts: anytype) void {
    const sz: f32 = if (@hasField(@TypeOf(opts), "size") and opts.size > 0) opts.size else 22;
    const r = ui.alloc(sz, sz);
    const cx = r.x + sz * 0.5;
    const cy = r.y + sz * 0.5;
    const rad = sz * 0.38;
    const t = ui.time;
    const n: i32 = 10;
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const a = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n)) * std.math.tau + @as(f32, @floatCast(t)) * 4.0;
        const fade = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
        const px = cx + @cos(a) * rad;
        const py = cy + @sin(a) * rad;
        const col = ui.theme.accent;
        ui.drawRect(.{
            .x = px - 2,
            .y = py - 2,
            .w = 4,
            .h = 4,
        }, .{ col[0], col[1], col[2], 0.25 + 0.75 * fade });
    }
    if (@hasField(@TypeOf(opts), "label") and opts.label.len > 0) {
        ui.drawText(r.x + sz + 8, r.y + (sz - ui.font.lineHeight(ui.theme.font_size)) * 0.5, ui.theme.font_size, ui.theme.text_dim, opts.label);
    }
}
