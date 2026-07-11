//! Reusable UI component.
const std = @import("std");
const types = @import("../types.zig");
const te = @import("../text_edit.zig");
const Color = types.Color;
const Rect = types.Rect;
const Id = types.Id;

pub fn separator(ui: anytype) void {
    const r = ui.alloc(0, 8);
    ui.drawRect(.{ .x = r.x, .y = r.y + 3, .w = ui.top().width - 2 * ui.top().pad, .h = 1 }, ui.theme.panel_border);
}
