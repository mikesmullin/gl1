//! Inspector scene — merged into the canvas editor.
//! Kept as a scene entry so palette/bookmarks still resolve; runs the canvas frame.

const app = @import("../app.zig");
const canvas = @import("canvas.zig");

pub fn frame(a: *app.App) void {
    canvas.frame(a);
}
