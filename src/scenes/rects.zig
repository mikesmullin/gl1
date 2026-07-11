const std = @import("std");
const app = @import("../app.zig");
const ui = @import("../ui/ui.zig");
const theme_mod = @import("../ui/theme.zig");
const state = @import("state.zig");

pub fn frame(a: *app.App) void {
    const u = &a.ui;
    const t: f32 = @floatCast(a.time);
    u.drawRect(u.place(40, 40, 120, 80), .{ 0.8, 0.3, 0.3, 1 });
    u.drawRect(u.place(180, 60, 100, 100), .{ 0.3, 0.7, 0.4, 0.9 });
    u.drawRect(u.place(300, 50 + 20 * @sin(t * 2), 140, 60), .{ 0.3, 0.4, 0.9, 1 });
    u.drawRectBorder(u.place(40, 200, 200, 100), .{ 0.15, 0.15, 0.18, 1 }, .{ 0.9, 0.8, 0.3, 1 }, 3);
    u.drawText(16, 16, 2.0, u.theme.text, "scene: rects");
}
