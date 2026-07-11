const std = @import("std");
const app = @import("../app.zig");
const ui = @import("../ui/ui.zig");
const theme_mod = @import("../ui/theme.zig");
const state = @import("state.zig");

pub fn frame(a: *app.App) void {
    const u = &a.ui;
    if (u.beginPanel(.{ .id = "p1", .x = 20, .y = 20, .w = 280, .h = 200, .title = "Panel A" })) {
        defer u.endPanel();
        u.label(.{ .text = "Nested content" });
        if (u.button(.{ .id = "a", .label = "Action A" })) {}
        u.label(.{ .text = "defer endPanel()", .color = u.theme.text_dim });
    }
    if (u.beginPanel(.{ .id = "p2", .x = 320, .y = 40, .w = 300, .h = 260, .title = "Panel B" })) {
        defer u.endPanel();
        u.label(.{ .text = "Second panel" });
        _ = u.checkbox(.{ .id = "bchk", .label = "Option", .value = &a.scene_state.checked });
        if (u.button(.{ .id = "b", .label = "Action B", .w = 120 })) {}
        u.separator();
        u.label(.{ .text = "Panels use begin/end + Zig defer.", .color = u.theme.text_dim });
    }
}
