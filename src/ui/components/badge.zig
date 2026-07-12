//! Small status badge / chip (compact label pill).
const types = @import("../types.zig");
const Color = types.Color;
const Rect = types.Rect;

pub fn badge(ui: anytype, opts: anytype) void {
    const size = ui.theme.font_size;
    const m = ui.font.measure(opts.label, size);
    const pad_x: f32 = 8;
    const pad_y: f32 = 3;
    const r = ui.alloc(m.w + pad_x * 2, m.h + pad_y * 2);
    const bg: Color = if (@hasField(@TypeOf(opts), "color")) opts.color else ui.theme.accent;
    // Dim pill
    const fill: Color = .{ bg[0] * 0.35, bg[1] * 0.35, bg[2] * 0.35, 0.95 };
    ui.drawRectBorder(r, fill, bg, 1);
    ui.drawText(r.x + pad_x, r.y + pad_y, size, bg, opts.label);
    _ = Rect;
}
