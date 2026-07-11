//! Reusable UI component.
const std = @import("std");
const types = @import("../types.zig");
const te = @import("../text_edit.zig");
const Color = types.Color;
const Rect = types.Rect;
const Id = types.Id;

pub fn listBoxNav(ui: anytype, opts: anytype) bool {
    var changed = ui.listBox(.{
        .id = opts.id,
        .items = opts.items,
        .selected = opts.selected,
        .w = opts.w,
        .h = opts.h,
    });
    // Keyboard when list region is hot or has selection focus via hover.
    const i = ui.id(opts.id);
    const r = ui.prevRect(i) orelse return changed;
    if (r.contains(ui.input.mouse_x, ui.input.mouse_y) or ui.hot.eq(i)) {
        if (opts.items.len > 0) {
            if (ui.input.keyPressed(.down)) {
                opts.selected.* = @min(opts.selected.* + 1, opts.items.len - 1);
                changed = true;
            }
            if (ui.input.keyPressed(.up)) {
                if (opts.selected.* > 0) opts.selected.* -= 1;
                changed = true;
            }
        }
    }
    return changed;
}
