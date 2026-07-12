//! Scene runner — each scene lives in its own module under this folder.

const std = @import("std");
const app = @import("../app.zig");
const ui = @import("../ui/ui.zig");
const theme_mod = @import("../ui/theme.zig");

pub const state = @import("state.zig");
pub const SceneKind = state.SceneKind;
pub const State = state.State;
pub const all = state.all;
pub const parse = state.parse;
pub const nameOf = state.nameOf;

const triangle = @import("triangle.zig");
const text = @import("text.zig");
const panels = @import("panels.zig");
const canvas = @import("canvas.zig");
const storybook = @import("storybook.zig");

/// Command palette entries (displayed A–Z by the palette).
const palette_cmds = [_][]const u8{
    "Scene: canvas",
    "Scene: panels",
    "Scene: storybook",
    "Scene: text",
    "Scene: triangle",
    "Action: Log hello",
    "Action: Toast hello",
    "Action: Toggle console",
    "Theme: Cycle (dark / cool / warm)",
};

pub fn frame(a: *app.App) void {
    // Keep legacy bool in sync for any code still reading theme_cool.
    a.scene_state.theme_cool = a.scene_state.theme_id == 1;
    a.ui.theme = theme_mod.byIndex(a.scene_state.theme_id);

    switch (a.scene) {
        .triangle => triangle.frame(a),
        .text => text.frame(a),
        .panels => panels.frame(a),
        .canvas => canvas.frame(a),
        .storybook => storybook.frame(a),
    }

    runCommandPalette(a);
    drawHud(a);
}

fn runCommandPalette(a: *app.App) void {
    const u = &a.ui;
    if (u.commandPalette(.{ .items = &palette_cmds })) |idx| {
        switch (idx) {
            0 => a.scene = .canvas,
            1 => a.scene = .panels,
            2 => a.scene = .storybook,
            3 => a.scene = .text,
            4 => a.scene = .triangle,
            5 => u.log("palette: hello"),
            6 => u.toast("Hello from palette", .ok, 1.5),
            7 => a.scene_state.editor_console_open = !a.scene_state.editor_console_open,
            8 => a.scene_state.theme_id = (a.scene_state.theme_id + 1) % 3,
            else => {},
        }
        u.log("palette");
    }
}

fn drawHud(a: *app.App) void {
    const u = &a.ui;
    var buf: [64]u8 = undefined;
    const fps = if (a.dt > 0) 1.0 / a.dt else 0;
    const msg = std.fmt.bufPrint(&buf, "{s}  {d:.0} fps", .{ nameOf(a.scene), fps }) catch "";
    const m = u.font.measure(msg, 1.5);
    u.drawText(a.width - m.w - 10, 8, 1.5, u.theme.text_dim, msg);
}
