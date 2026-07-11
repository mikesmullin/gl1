//! Multi-line text area with optional resize grip (bottom-right).
const std = @import("std");
const types = @import("../types.zig");
const te = @import("../text_edit.zig");
const Color = types.Color;
const Rect = types.Rect;
const Id = types.Id;

const textFieldCore = @import("textFieldCore.zig");

const grip: f32 = 12;

pub fn textArea(ui: anytype, opts: anytype) bool {
    const i = ui.id(opts.id);
    const ed = ui.editState(i.a);
    const size = ui.theme.font_size;
    const lh = ui.font.lineHeight(size);
    const label_gap: f32 = 6;

    // Default size from rows / min_height / max_height
    var body_h: f32 = @as(f32, @floatFromInt(if (@hasField(@TypeOf(opts), "rows")) opts.rows else @as(u32, 3))) * lh + 12;
    if (@hasField(@TypeOf(opts), "h") and opts.h > 0) body_h = opts.h;
    if (@hasField(@TypeOf(opts), "min_height") and opts.min_height > 0) body_h = @max(body_h, opts.min_height);
    const max_h: f32 = if (@hasField(@TypeOf(opts), "max_height") and opts.max_height > 0) opts.max_height else 10000;

    var body_w: f32 = if (@hasField(@TypeOf(opts), "w")) opts.w else 280;
    // Apply user resize (from corner grip)
    if (ed.user_w > 0) body_w = ed.user_w;
    if (ed.user_h > 0) body_h = ed.user_h;
    body_h = @min(body_h, max_h);
    body_w = @max(body_w, 80);
    body_h = @max(body_h, lh + 12);

    const text = opts.buf[0..opts.len.*];
    var nlines: usize = 1;
    for (text) |ch| {
        if (ch == '\n') nlines += 1;
    }
    const content_h = @as(f32, @floatFromInt(nlines)) * lh + 12;
    const view_h = body_h;
    const need_scroll = content_h > view_h;

    const total_h = view_h + 14 + label_gap;
    const r = ui.alloc(body_w, total_h);
    ui.drawText(r.x, r.y, size, ui.theme.text_dim, opts.label);
    const box = Rect{ .x = r.x, .y = r.y + 12 + label_gap, .w = body_w, .h = view_h };

    // Resize grip (bottom-right of the box)
    const gr = Rect{ .x = box.x + box.w - grip, .y = box.y + box.h - grip, .w = grip, .h = grip };
    const gid = ui.idFlat("ta_grip");
    // hit-test grip first
    if (ui.input.mousePressed(.left) and gr.contains(ui.input.mouse_x, ui.input.mouse_y)) {
        ed.resizing = true;
        ed.resize_anchor_x = ui.input.mouse_x;
        ed.resize_anchor_y = ui.input.mouse_y;
        ed.resize_start_w = body_w;
        ed.resize_start_h = body_h;
        if (ed.user_w <= 0) ed.user_w = body_w;
        if (ed.user_h <= 0) ed.user_h = body_h;
    }
    if (ed.resizing) {
        if (ui.input.mouseDown(.left)) {
            const dx = ui.input.mouse_x - ed.resize_anchor_x;
            const dy = ui.input.mouse_y - ed.resize_anchor_y;
            ed.user_w = @max(80, ed.resize_start_w + dx);
            ed.user_h = std.math.clamp(ed.resize_start_h + dy, lh + 12, max_h);
        } else {
            ed.resizing = false;
        }
    }

    // scroll offset for overflow
    var scroll: f32 = 0;
    if (need_scroll and !ed.resizing) {
        const gop = ui.scroll_y.getOrPut(i.a) catch null;
        if (gop) |g| {
            if (!g.found_existing) g.value_ptr.* = 0;
            if (box.contains(ui.input.mouse_x, ui.input.mouse_y) and !gr.contains(ui.input.mouse_x, ui.input.mouse_y)) {
                g.value_ptr.* -= ui.input.scroll_y * lh;
            }
            const max_scroll = content_h - view_h + 4;
            if (g.value_ptr.* < 0) g.value_ptr.* = 0;
            if (g.value_ptr.* > max_scroll) g.value_ptr.* = max_scroll;
            scroll = g.value_ptr.*;
        }
    }

    // If currently resizing, skip text interaction this frame on the grip
    const changed = if (ed.resizing) false else textFieldCore.textFieldCore(ui, .{
        .id_key = i.a,
        .box = box,
        .buf = opts.buf,
        .len = opts.len,
        .multiline = true,
        .size = size,
        .scroll_y = scroll,
    });

    // Draw grip (after field so it's visible on top of border)
    ui.drawRect(gr, if (ed.resizing) ui.theme.accent else ui.theme.panel_border);
    // diagonal lines
    const gcol = if (ed.resizing or gr.contains(ui.input.mouse_x, ui.input.mouse_y)) ui.theme.accent else ui.theme.text_dim;
    _ = gcol;
    ui.drawRect(.{ .x = gr.x + 3, .y = gr.y + gr.h - 4, .w = gr.w - 4, .h = 1 }, ui.theme.text_dim);
    ui.drawRect(.{ .x = gr.x + 6, .y = gr.y + gr.h - 7, .w = gr.w - 7, .h = 1 }, ui.theme.text_dim);
    ui.drawRect(.{ .x = gr.x + 9, .y = gr.y + gr.h - 10, .w = gr.w - 10, .h = 1 }, ui.theme.text_dim);
    _ = gid;

    return changed;
}
