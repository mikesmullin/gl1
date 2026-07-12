//! Metric counter chip: big number + small label.
const std = @import("std");
const types = @import("../types.zig");
const Color = types.Color;
const Rect = types.Rect;

pub fn counter(ui: anytype, opts: anytype) void {
    var nbuf: [32]u8 = undefined;
    const ns = if (@hasField(@TypeOf(opts), "text"))
        opts.text
    else
        (std.fmt.bufPrint(&nbuf, "{d}", .{opts.value}) catch "?");
    const label: []const u8 = opts.label;
    const nm = ui.font.measure(ns, 2.5);
    const lm = ui.font.measure(label, 1.4);
    const w = @max(nm.w, lm.w) + 20;
    const h: f32 = 48;
    const r = ui.alloc(w, h);
    ui.drawRectBorder(r, ui.theme.panel, ui.theme.panel_border, 1);
    const accent: Color = if (@hasField(@TypeOf(opts), "color")) opts.color else ui.theme.accent;
    ui.drawText(r.x + (r.w - nm.w) * 0.5, r.y + 6, 2.5, accent, ns);
    ui.drawText(r.x + (r.w - lm.w) * 0.5, r.y + 28, 1.4, ui.theme.text_dim, label);
    _ = Rect;
}
