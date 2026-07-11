const std = @import("std");
const app = @import("../app.zig");
const ui = @import("../ui/ui.zig");
const theme_mod = @import("../ui/theme.zig");
const state = @import("state.zig");

pub fn frame(a: *app.App) void {
    const sgl = @import("sokol").gl;
    const w = a.width;
    const h = a.height;
    const t: f32 = @floatCast(a.time);

    sgl.beginTriangles();
    sgl.v2fC3f(w * 0.5, h * 0.2, 1, 0.3 + 0.2 * @sin(t), 0.3);
    sgl.v2fC3f(w * 0.2, h * 0.8, 0.2, 0.6, 1);
    sgl.v2fC3f(w * 0.8, h * 0.8, 0.3, 1, 0.5);
    sgl.end();

    a.ui.drawText(16, 16, 2.0, a.ui.theme.text, "scene: triangle  (mouse moves ok)");
    var buf: [64]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "mouse {d:.0},{d:.0}", .{ a.input.mouse_x, a.input.mouse_y }) catch "";
    a.ui.drawText(16, 40, 2.0, a.ui.theme.text_dim, msg);
}
