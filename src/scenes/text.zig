const std = @import("std");
const app = @import("../app.zig");
const ui = @import("../ui/ui.zig");
const theme_mod = @import("../ui/theme.zig");
const state = @import("state.zig");

pub fn frame(a: *app.App) void {
    const u = &a.ui;
    u.drawText(16, 16, 2.0, u.theme.text, "scene: text — bitmap font atlas (magenta = transparent)");
    u.drawText(16, 48, 1.5, u.theme.text_dim, "ABCDEFGHIJKLMNOPQRSTUVWXYZ");
    u.drawText(16, 70, 1.5, u.theme.text_dim, "abcdefghijklmnopqrstuvwxyz");
    u.drawText(16, 92, 1.5, u.theme.text_dim, "0123456789 !@#$%^&*()_+-=");
    u.drawText(16, 130, 3.0, u.theme.accent, "Size 3.0 accent");
    u.drawText(16, 170, 4.0, .{ 1, 0.85, 0.4, 1 }, "Size 4.0");
    u.drawText(16, 220, 2.0, u.theme.text, "The quick brown fox jumps over the lazy dog.");
}
