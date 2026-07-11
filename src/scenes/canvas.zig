const std = @import("std");
const app = @import("../app.zig");
const ui = @import("../ui/ui.zig");
const theme_mod = @import("../ui/theme.zig");
const state = @import("state.zig");

pub fn frame(a: *app.App) void {
    const u = &a.ui;
    const st = &a.scene_state;
    const sgl = @import("sokol").gl;

    u.drawText(16, 16, 2.0, u.theme.text, "scene: canvas — pan (MMB/Space+LMB)  zoom (wheel)");
    u.drawText(16, 40, 1.5, u.theme.text_dim, "Grid in world space; entities as colored quads");

    // Zoom (respect overlay scroll capture — e.g. command palette)
    const dy = u.wheelY();
    if (dy != 0) {
        const factor: f32 = if (dy > 0) 1.1 else 1.0 / 1.1;
        st.canvas_zoom = std.math.clamp(st.canvas_zoom * factor, 0.25, 8);
        u.eatScroll();
    }

    // Pan
    const space_pan = a.input.keyDown(.space) and a.input.mouseDown(.left);
    const mid_pan = a.input.mouseDown(.middle);
    if (space_pan or mid_pan) {
        st.canvas_ox += a.input.mouse_dx;
        st.canvas_oy += a.input.mouse_dy;
    }

    const z = st.canvas_zoom;
    const ox = st.canvas_ox + a.width * 0.5;
    const oy = st.canvas_oy + a.height * 0.5;

    // Grid
    const grid: f32 = 40;
    const gw = grid * z;
    sgl.beginLines();
    sgl.c4f(0.2, 0.22, 0.26, 1);
    var gx: f32 = @mod(ox, gw);
    while (gx < a.width) : (gx += gw) {
        sgl.v2f(gx, 0);
        sgl.v2f(gx, a.height);
    }
    var gy: f32 = @mod(oy, gw);
    while (gy < a.height) : (gy += gw) {
        sgl.v2f(0, gy);
        sgl.v2f(a.width, gy);
    }
    // Axes
    sgl.c4f(0.5, 0.25, 0.25, 1);
    sgl.v2f(ox, 0);
    sgl.v2f(ox, a.height);
    sgl.c4f(0.25, 0.5, 0.3, 1);
    sgl.v2f(0, oy);
    sgl.v2f(a.width, oy);
    sgl.end();

    // Demo entities in world space
    const ents = [_]struct { x: f32, y: f32, c: ui.Color, n: []const u8 }{
        .{ .x = 0, .y = 0, .c = .{ 0.9, 0.3, 0.3, 1 }, .n = "Origin" },
        .{ .x = 120, .y = -40, .c = .{ 0.3, 0.85, 0.4, 1 }, .n = "Hero" },
        .{ .x = -80, .y = 90, .c = .{ 0.3, 0.5, 0.95, 1 }, .n = "Slime" },
        .{ .x = 200, .y = 140, .c = .{ 0.95, 0.8, 0.2, 1 }, .n = "Torch" },
    };
    for (ents) |e| {
        const sx = ox + e.x * z;
        const sy = oy + e.y * z;
        const s = 28 * z;
        u.drawRect(.{ .x = sx - s * 0.5, .y = sy - s * 0.5, .w = s, .h = s }, e.c);
        u.drawText(sx - s * 0.5, sy + s * 0.5 + 4, 1.5, u.theme.text, e.n);
    }

    var buf: [48]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "zoom {d:.2}  pan {d:.0},{d:.0}", .{ z, st.canvas_ox, st.canvas_oy }) catch "";
    u.drawText(16, a.height - 40, 1.5, u.theme.text_dim, msg);
    u.drawText(16, a.height - 22, 1.5, u.theme.text_dim, "Ctrl+P palette  |  type scene");
}
