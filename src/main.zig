//! gl1 — portable Zig + Sokol graphics prototype with custom immediate UI.

const std = @import("std");
const app = @import("app.zig");
const scenes = @import("scenes/scenes.zig");

const VERSION = "0.1.0";

const HELP =
    \\gl1 — Zig + Sokol UI prototype
    \\
    \\usage:
    \\  gl1 [--scene <name>] [--story-tab <name>] [--auto-quit <seconds>]
    \\  gl1 help
    \\  gl1 version
    \\
    \\scenes:
    \\  storybook       widget gallery (default)
    \\  canvas          3D editor viewport + scene tree / inspector / console
    \\  text            bitmap font sample
    \\  triangle        hello triangle
    \\  panels          desktop windows + dock
    \\
    \\options:
    \\  --story-tab     open storybook on this sidebar tab (e.g. Button)
    \\  --auto-quit     quit after N seconds (screenshot automation)
    \\
    \\keys:
    \\  Ctrl+P          command palette (type "scene" for scenes)
    \\  Esc             close modal/palette / clear focus / quit
    \\
;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buf);
    const stdout = &stdout_writer.interface;

    var scene: scenes.SceneKind = .storybook;
    var story_tab: ?[]const u8 = null;
    var auto_quit_s: f32 = 0;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "help") or std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) {
            try stdout.print("{s}", .{HELP});
            try stdout.flush();
            return;
        }
        if (std.mem.eql(u8, a, "version") or std.mem.eql(u8, a, "--version")) {
            try stdout.print("gl1 {s}\n", .{VERSION});
            try stdout.flush();
            return;
        }
        if (std.mem.eql(u8, a, "--scene") and i + 1 < args.len) {
            i += 1;
            scene = scenes.parse(args[i]) orelse {
                try stdout.print("error: unknown scene '{s}'\n\n{s}", .{ args[i], HELP });
                try stdout.flush();
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, a, "--story-tab") and i + 1 < args.len) {
            i += 1;
            story_tab = args[i];
            scene = .storybook;
        } else if (std.mem.eql(u8, a, "--auto-quit") and i + 1 < args.len) {
            i += 1;
            auto_quit_s = std.fmt.parseFloat(f32, args[i]) catch {
                try stdout.print("error: bad --auto-quit value '{s}'\n", .{args[i]});
                try stdout.flush();
                std.process.exit(1);
            };
        } else {
            try stdout.print("error: unknown arg '{s}'\n\n{s}", .{ a, HELP });
            try stdout.flush();
            std.process.exit(1);
        }
    }

    app.run(arena, scene, init.io, .{ .story_tab = story_tab, .auto_quit_s = auto_quit_s });
}
