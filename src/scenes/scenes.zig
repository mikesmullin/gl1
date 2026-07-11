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
const rects = @import("rects.zig");
const text = @import("text.zig");
const widgets_basic = @import("widgets_basic.zig");
const panels = @import("panels.zig");
const layout = @import("layout.zig");
const inspector = @import("inspector.zig");
const canvas = @import("canvas.zig");
const storybook = @import("storybook.zig");

/// Alphabetical "Scene: …" entries first (so filtering "scene" is predictable).
const palette_cmds = [_][]const u8{
    "Scene: canvas",
    "Scene: inspector",
    "Scene: layout",
    "Scene: panels",
    "Scene: rects",
    "Scene: storybook",
    "Scene: text",
    "Scene: triangle",
    "Scene: widgets_basic",
    "Action: Log hello",
    "Action: Toast hello",
    "Action: Toggle console",
    "Theme: Toggle cool dark",
};

pub fn frame(a: *app.App) void {
    a.ui.theme = if (a.scene_state.theme_cool) theme_mod.dark_cool else theme_mod.dark;

    switch (a.scene) {
        .triangle => triangle.frame(a),
        .rects => rects.frame(a),
        .text => text.frame(a),
        .widgets_basic => widgets_basic.frame(a),
        .panels => panels.frame(a),
        .layout => layout.frame(a),
        .inspector => inspector.frame(a),
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
            1 => a.scene = .inspector,
            2 => a.scene = .layout,
            3 => a.scene = .panels,
            4 => a.scene = .rects,
            5 => a.scene = .storybook,
            6 => a.scene = .text,
            7 => a.scene = .triangle,
            8 => a.scene = .widgets_basic,
            9 => u.log("palette: hello"),
            10 => u.toast("Hello from palette", .ok, 1.5),
            11 => a.scene_state.show_console = !a.scene_state.show_console,
            12 => a.scene_state.theme_cool = !a.scene_state.theme_cool,
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
