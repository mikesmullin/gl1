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
            0 => a.requestScene(.canvas),
            1 => a.requestScene(.panels),
            2 => a.requestScene(.storybook),
            3 => a.requestScene(.text),
            4 => a.requestScene(.triangle),
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
    const hist = @import("../ui/components/histogram.zig");
    // Scene name left of frame-time graph (top-right).
    var buf: [48]u8 = undefined;
    const name = std.fmt.bufPrint(&buf, "{s}", .{nameOf(a.scene)}) catch "";
    const graph_w: f32 = 120;
    const graph_h: f32 = 24;
    const m = u.font.measure(name, 1.5);
    const gx = a.width - graph_w - 10;
    const gy: f32 = 6;
    u.drawText(gx - m.w - 8, 10, 1.5, u.theme.text_dim, name);
    var samples: [app.App.FtHist]f32 = undefined;
    const slice = a.frameTimeSamples(samples[0..]);
    // Overlay latest fps as a bare number (ms → fps), e.g. "60".
    var ov: [16]u8 = undefined;
    const overlay: []const u8 = if (slice.len > 0 and slice[slice.len - 1] > 0.05)
        (std.fmt.bufPrint(&ov, "{d:.0}", .{1000.0 / slice[slice.len - 1]}) catch "")
    else
        "";
    // max ~50ms so steady ~16ms (60fps) sits in the cool-blue zone; spikes go red.
    hist.histogramAt(u, gx, gy, graph_w, graph_h, slice, 50.0, overlay);
}
