//! Reusable UI component.
const std = @import("std");
const types = @import("../types.zig");
const te = @import("../text_edit.zig");
const Color = types.Color;
const Rect = types.Rect;
const Id = types.Id;

const textFieldCore = @import("textFieldCore.zig");

pub fn searchField(ui: anytype, opts: anytype) bool {
    const i = ui.id(opts.id);
    const r = ui.alloc(opts.w, ui.theme.row_h);
    const empty = opts.len.* == 0;
    const changed = textFieldCore.textFieldCore(ui, .{
        .id_key = i.a,
        .box = r,
        .buf = opts.buf,
        .len = opts.len,
        .multiline = false,
        .size = ui.theme.font_size,
        .scroll_y = 0,
    });
    if (empty and opts.len.* == 0 and ui.focus.a != i.a) {
        ui.drawText(r.x + 6, r.y + 6, ui.theme.font_size, ui.theme.text_dim, opts.placeholder);
    }
    return changed;
}
