const std = @import("std");
const app = @import("../app.zig");
const ui = @import("../ui/ui.zig");
const theme_mod = @import("../ui/theme.zig");
const state = @import("state.zig");

pub fn frame(a: *app.App) void {
    const u = &a.ui;
    u.drawText(16, 12, 2.0, u.theme.text, "scene: layout — vstack / hstack");

    u.beginVStack(.{ .x = 40, .y = 50, .w = 400, .h = 400, .pad = 12, .gap = 8 });
    defer _ = u.endVStack();

    u.drawRectBorder(u.place(40, 50, 400, 400), .{ 0.12, 0.13, 0.16, 1 }, u.theme.panel_border, 1);

    u.label(.{ .text = "Vertical stack" });
    u.beginHStack(.{ .x = 52, .y = 100, .w = 376, .h = 40, .pad = 0, .gap = 8 });
    if (u.button(.{ .id = "l1", .label = "One", .w = 80 })) {}
    if (u.button(.{ .id = "l2", .label = "Two", .w = 80 })) {}
    if (u.button(.{ .id = "l3", .label = "Three", .w = 80 })) {}
    _ = u.endHStack();

    u.beginVStack(.{ .x = 52, .y = 160, .w = 376, .h = 200, .pad = 8, .gap = 6 });
    u.label(.{ .text = "Inner vstack" });
    _ = u.slider(.{ .id = "lay_s", .label = "Param", .value = &a.scene_state.speed });
    u.label(.{ .text = "padding + gap from theme", .color = u.theme.text_dim });
    _ = u.endVStack();
}
