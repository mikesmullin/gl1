//! Image well / thumbnail — optional texture with fit / stretch / fill.
const types = @import("../types.zig");
const Color = types.Color;
const Rect = types.Rect;
const tex_mod = @import("../tex.zig");

pub const Fit = tex_mod.Tex.Fit;

pub fn imageWell(ui: anytype, opts: anytype) void {
    const w: f32 = if (@hasField(@TypeOf(opts), "w")) opts.w else 96;
    const h: f32 = if (@hasField(@TypeOf(opts), "h")) opts.h else 96;
    const r = ui.alloc(w, h);
    const fit: Fit = if (@hasField(@TypeOf(opts), "fit")) opts.fit else .fit;
    const border = if (@hasField(@TypeOf(opts), "border") and !opts.border)
        false
    else
        true;

    // Base plate + border
    if (border) {
        ui.drawRectBorder(r, ui.theme.input_bg, ui.theme.panel_border, 1);
    } else {
        ui.drawRect(r, ui.theme.input_bg);
    }

    const inner = Rect{ .x = r.x + 1, .y = r.y + 1, .w = w - 2, .h = h - 2 };
    const has_tex = @hasField(@TypeOf(opts), "tex") and opts.tex != null and opts.tex.?.ok;

    // Checkerboard always under content so PNG alpha shows through (and empty wells match).
    {
        const cell: f32 = 8;
        var y: f32 = 0;
        while (y < h - 2) : (y += cell) {
            var x: f32 = 0;
            while (x < w - 2) : (x += cell) {
                const on = @mod(@as(i32, @intFromFloat(x / cell)) + @as(i32, @intFromFloat(y / cell)), 2) == 0;
                if (on) {
                    ui.drawRect(.{
                        .x = r.x + 1 + x,
                        .y = r.y + 1 + y,
                        .w = @min(cell, w - 2 - x),
                        .h = @min(cell, h - 2 - y),
                    }, .{ 0.16, 0.17, 0.2, 1 });
                }
            }
        }
    }

    if (has_tex) {
        const fit_u: u8 = switch (fit) {
            .fit => 0,
            .stretch => 1,
            .fill => 2,
        };
        // Image draws with alpha over checkerboard (sgl blend is on).
        ui.cmds.image(inner.x, inner.y, inner.w, inner.h, opts.tex.?, fit_u);
    }

    if (@hasField(@TypeOf(opts), "label") and opts.label.len > 0) {
        const m = ui.font.measure(opts.label, 1.5);
        // Dim plate behind caption
        ui.drawRect(.{
            .x = r.x + (w - m.w) * 0.5 - 4,
            .y = r.y + h - m.h - 8,
            .w = m.w + 8,
            .h = m.h + 4,
        }, .{ 0.05, 0.06, 0.07, 0.7 });
        ui.drawText(r.x + (w - m.w) * 0.5, r.y + h - m.h - 6, 1.5, ui.theme.text, opts.label);
    }
    _ = Color;
}
