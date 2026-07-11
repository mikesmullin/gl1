//! Reusable UI component.
const std = @import("std");
const types = @import("../types.zig");
const te = @import("../text_edit.zig");
const Color = types.Color;
const Rect = types.Rect;
const Id = types.Id;

const textFieldCore = @import("textFieldCore.zig");

pub fn textArea(ui: anytype, opts: anytype) bool {
    const i = ui.id(opts.id);
    const size = ui.theme.font_size;
    const lh = ui.font.lineHeight(size);
    const label_gap: f32 = 6;
    var body_h: f32 = @as(f32, @floatFromInt(opts.rows)) * lh + 12;
    if (opts.h > 0) body_h = opts.h;
    if (opts.min_height > 0) body_h = @max(body_h, opts.min_height);
    const max_h = if (opts.max_height > 0) opts.max_height else body_h * 3;
    // content height
    const text = opts.buf[0..opts.len.*];
    var nlines: usize = 1;
    for (text) |ch| {
        if (ch == '\n') nlines += 1;
    }
    const content_h = @as(f32, @floatFromInt(nlines)) * lh + 12;
    const view_h = @min(max_h, @max(body_h, @min(content_h, max_h)));
    const need_scroll = content_h > view_h;

    const r = ui.alloc(opts.w, view_h + 14 + label_gap);
    ui.drawText(r.x, r.y, size, ui.theme.text_dim, opts.label);
    const box = Rect{ .x = r.x, .y = r.y + 12 + label_gap, .w = opts.w, .h = view_h };

    // scroll offset for overflow
    var scroll: f32 = 0;
    if (need_scroll) {
        const gop = ui.scroll_y.getOrPut(i.a) catch null;
        if (gop) |g| {
            if (!g.found_existing) g.value_ptr.* = 0;
            if (box.contains(ui.input.mouse_x, ui.input.mouse_y)) {
                g.value_ptr.* -= ui.input.scroll_y * lh;
            }
            const max_scroll = content_h - view_h + 4;
            if (g.value_ptr.* < 0) g.value_ptr.* = 0;
            if (g.value_ptr.* > max_scroll) g.value_ptr.* = max_scroll;
            scroll = g.value_ptr.*;
        }
    }

    return textFieldCore.textFieldCore(ui, .{
        .id_key = i.a,
        .box = box,
        .buf = opts.buf,
        .len = opts.len,
        .multiline = true,
        .size = size,
        .scroll_y = scroll,
    });
}
