//! Reusable UI component.
const std = @import("std");
const types = @import("../types.zig");
const te = @import("../text_edit.zig");
const Color = types.Color;
const Rect = types.Rect;
const Id = types.Id;

const textFieldCore = @import("textFieldCore.zig");

pub fn textInput(ui: anytype, opts: anytype) bool {
    const i = ui.id(opts.id);
    const size = ui.theme.font_size;
    const label_gap: f32 = 6;
    const r = ui.alloc(opts.w, ui.theme.row_h + 14 + label_gap);
    ui.drawText(r.x, r.y, size, ui.theme.text_dim, opts.label);
    const box = Rect{ .x = r.x, .y = r.y + 12 + label_gap, .w = opts.w, .h = ui.theme.row_h };
    return textFieldCore.textFieldCore(ui, .{
        .id_key = i.a,
        .box = box,
        .buf = opts.buf,
        .len = opts.len,
        .multiline = false,
        .size = size,
        .scroll_y = 0,
    });
}
