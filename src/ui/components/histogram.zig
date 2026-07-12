//! Scrolling bar histogram + frame-time specialization.
const std = @import("std");
const types = @import("../types.zig");
const Color = types.Color;
const Rect = types.Rect;

/// Map t in [0,1] → cool blue → hot red (low = good / cool).
pub fn coldHot(t: f32) Color {
    const u = std.math.clamp(t, 0, 1);
    if (u < 0.5) {
        const s = u * 2;
        return .{
            0.20 + (0.95 - 0.20) * s,
            0.45 + (0.85 - 0.45) * s,
            0.95 + (0.25 - 0.95) * s,
            1,
        };
    } else {
        const s = (u - 0.5) * 2;
        return .{
            0.95,
            0.85 + (0.25 - 0.85) * s,
            0.25 + (0.20 - 0.25) * s,
            1,
        };
    }
}

fn drawBars(ui: anytype, x0: f32, y0: f32, w: f32, h: f32, samples: []const f32, max_v: f32) void {
    if (samples.len == 0) return;
    const n = samples.len;
    const bar_w = @max(1, w / @as(f32, @floatFromInt(n)));
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const v = samples[i];
        if (v <= 0.0001) continue;
        const t = std.math.clamp(v / max_v, 0, 1);
        const bh = @max(1, h * t);
        const col = coldHot(t);
        ui.drawRect(.{
            .x = x0 + bar_w * @as(f32, @floatFromInt(i)),
            .y = y0 + h - bh,
            .w = @max(1, bar_w - 0.5),
            .h = bh,
        }, col);
    }
}

fn drawOverlay(ui: anytype, x: f32, y: f32, w: f32, h: f32, text: []const u8) void {
    if (text.len == 0) return;
    const size: f32 = 1.5;
    const m = ui.font.measure(text, size);
    // Glyphs already carry a 1px outline — no plate behind the text.
    ui.drawText(x + (w - m.w) * 0.5, y + (h - m.h) * 0.5, size, ui.theme.text, text);
}

/// Draw scrolling histogram. Transparent background (no fill) so idle = invisible.
/// Optional `overlay` text is centered (e.g. "60fps").
pub fn histogram(ui: anytype, opts: anytype) void {
    const w: f32 = if (@hasField(@TypeOf(opts), "w")) opts.w else 120;
    const h: f32 = if (@hasField(@TypeOf(opts), "h")) opts.h else 24;
    const r = ui.alloc(w, h);

    const samples: []const f32 = opts.samples;
    const max_v: f32 = if (@hasField(@TypeOf(opts), "max_value")) @max(opts.max_value, 1e-6) else 1;
    drawBars(ui, r.x, r.y, w, h, samples, max_v);

    if (@hasField(@TypeOf(opts), "overlay")) {
        if (opts.overlay.len > 0) drawOverlay(ui, r.x, r.y, w, h, opts.overlay);
    } else if (samples.len > 0) {
        // Default: show latest sample as 2-decimal number.
        var buf: [24]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d:.2}", .{samples[samples.len - 1]}) catch "";
        drawOverlay(ui, r.x, r.y, w, h, s);
    }
    _ = Rect;
}

/// Absolute placement (for HUD). Transparent bg + centered overlay.
pub fn histogramAt(ui: anytype, x: f32, y: f32, w: f32, h: f32, samples: []const f32, max_value: f32, overlay: []const u8) void {
    drawBars(ui, x, y, w, h, samples, @max(max_value, 1e-6));
    drawOverlay(ui, x, y, w, h, overlay);
}
