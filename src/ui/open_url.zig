//! Open a URL in the system default browser (best-effort).

const std = @import("std");
const builtin = @import("builtin");
const app_mod = @import("../app.zig");

pub fn openUrl(url: []const u8) void {
    if (url.len == 0) return;
    const io = app_mod.global().io;

    var argv_storage: [4][]const u8 = undefined;
    const argv: []const []const u8 = switch (builtin.os.tag) {
        .linux => blk: {
            argv_storage[0] = "xdg-open";
            argv_storage[1] = url;
            break :blk argv_storage[0..2];
        },
        .macos => blk: {
            argv_storage[0] = "open";
            argv_storage[1] = url;
            break :blk argv_storage[0..2];
        },
        .windows => blk: {
            argv_storage[0] = "cmd";
            argv_storage[1] = "/c";
            argv_storage[2] = "start";
            argv_storage[3] = url;
            break :blk argv_storage[0..4];
        },
        else => return,
    };

    // Fire-and-forget: spawn and do not wait (browser stays open).
    _ = std.process.spawn(io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch {};
}
