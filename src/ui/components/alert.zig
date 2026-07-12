//! Inline alert banner (info / success / warn / error).
const types = @import("../types.zig");
const Color = types.Color;

pub const Kind = enum { info, ok, warn, err };

pub fn alert(ui: anytype, opts: anytype) void {
    const kind: Kind = if (@hasField(@TypeOf(opts), "kind")) opts.kind else .info;
    const size = ui.theme.font_size;
    const msg: []const u8 = opts.text;
    const m = ui.font.measure(msg, size);
    const pad: f32 = 10;
    const r = ui.alloc(@max(m.w + pad * 2, 120), m.h + pad * 2);
    const bg: Color = switch (kind) {
        .info => .{ 0.15, 0.28, 0.42, 1 },
        .ok => .{ 0.12, 0.35, 0.22, 1 },
        .warn => .{ 0.40, 0.32, 0.12, 1 },
        .err => .{ 0.42, 0.15, 0.15, 1 },
    };
    const border: Color = switch (kind) {
        .info => ui.theme.info,
        .ok => .{ 0.35, 0.85, 0.5, 1 },
        .warn => ui.theme.warning,
        .err => ui.theme.danger,
    };
    ui.drawRectBorder(r, bg, border, 1);
    ui.drawText(r.x + pad, r.y + pad, size, ui.theme.text, msg);
}
