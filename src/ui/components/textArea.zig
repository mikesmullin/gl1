//! Multi-line text area with optional resize grip (bottom-right).
//! During grip-drag, layout stays at the committed size and a lightweight
//! "ghost" rect previews the new size until mouse-up commits it.
const std = @import("std");
const types = @import("../types.zig");
const te = @import("../text_edit.zig");
const Rect = types.Rect;

const textFieldCore = @import("textFieldCore.zig");

const grip: f32 = 12;

/// Solid SE resize triangle (bottom-right corner), colored like the field border.
fn drawGrip(ui: anytype, gr: Rect, color: types.Color) void {
    // Vertices: top-right, bottom-right, bottom-left of the grip square.
    // Fill with horizontal spans so we don't need a triangle draw command.
    var row: f32 = 0;
    while (row < gr.h) : (row += 1) {
        const t = if (gr.h > 1) row / (gr.h - 1) else 1;
        const ww = @max(1, gr.w * t);
        ui.drawRect(.{ .x = gr.x + gr.w - ww, .y = gr.y + row, .w = ww, .h = 1 }, color);
    }
}

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
    // Committed user resize only (not live drag preview — avoids layout thrash).
    if (ed.user_w > 0) body_w = ed.user_w;
    if (ed.user_h > 0) body_h = ed.user_h;
    body_h = @min(body_h, max_h);
    body_w = @max(body_w, 80);
    body_h = @max(body_h, lh + 12);

    const want_gutter = @hasField(@TypeOf(opts), "line_numbers") and opts.line_numbers;
    // Gutter wide enough for 2–3 digit hard-line numbers.
    const gutter_w: f32 = if (want_gutter) 36 else 0;

    const text = opts.buf[0..opts.len.*];
    // Soft-wrap row count for scroll (display-only; buffer may be one long hard line).
    const wrap_px: f32 = @max(0, body_w - gutter_w - 12);
    const nlines = te.countSoftRows(text, ui.font, size, wrap_px);
    const content_h = @as(f32, @floatFromInt(nlines)) * lh + 12;
    const view_h = body_h;
    const need_scroll = content_h > view_h;

    const total_h = view_h + 14 + label_gap;
    const r = ui.alloc(body_w, total_h);
    ui.drawText(r.x, r.y, size, ui.theme.text_dim, opts.label);
    const outer = Rect{ .x = r.x, .y = r.y + 12 + label_gap, .w = body_w, .h = view_h };
    // Text field box sits to the right of the optional line-number gutter.
    const box = Rect{ .x = outer.x + gutter_w, .y = outer.y, .w = body_w - gutter_w, .h = view_h };

    // Grip hit target: outer SE corner (includes optional gutter width).
    var gr = Rect{ .x = outer.x + body_w - grip, .y = outer.y + view_h - grip, .w = grip, .h = grip };
    if (ed.resizing and ed.resize_preview_w > 0 and ed.resize_preview_h > 0) {
        gr = .{
            .x = outer.x + ed.resize_preview_w - grip,
            .y = outer.y + ed.resize_preview_h - grip,
            .w = grip,
            .h = grip,
        };
    }

    if (ui.input.mousePressed(.left) and gr.contains(ui.input.mouse_x, ui.input.mouse_y)) {
        ed.resizing = true;
        ed.resize_anchor_x = ui.input.mouse_x;
        ed.resize_anchor_y = ui.input.mouse_y;
        ed.resize_start_w = body_w;
        ed.resize_start_h = body_h;
        ed.resize_preview_w = body_w;
        ed.resize_preview_h = body_h;
        if (ed.user_w <= 0) ed.user_w = body_w;
        if (ed.user_h <= 0) ed.user_h = body_h;
    }

    if (ed.resizing) {
        if (ui.input.mouseDown(.left)) {
            const dx = ui.input.mouse_x - ed.resize_anchor_x;
            const dy = ui.input.mouse_y - ed.resize_anchor_y;
            ed.resize_preview_w = @max(80, ed.resize_start_w + dx);
            ed.resize_preview_h = std.math.clamp(ed.resize_start_h + dy, lh + 12, max_h);
            // Keep grip under cursor for the rest of this frame's draw.
            gr = .{
                .x = outer.x + ed.resize_preview_w - grip,
                .y = outer.y + ed.resize_preview_h - grip,
                .w = grip,
                .h = grip,
            };
        } else {
            // Commit on release — next frame layout uses the new size.
            ed.user_w = ed.resize_preview_w;
            ed.user_h = ed.resize_preview_h;
            ed.resizing = false;
            ed.resize_preview_w = 0;
            ed.resize_preview_h = 0;
        }
    }

    // scroll offset for overflow
    var scroll: f32 = 0;
    if (need_scroll and !ed.resizing) {
        const gop = ui.scroll_y.getOrPut(i.a) catch null;
        if (gop) |g| {
            if (!g.found_existing) g.value_ptr.* = 0;
            const dy = ui.wheelY();
            if (dy != 0 and outer.contains(ui.input.mouse_x, ui.input.mouse_y) and !gr.contains(ui.input.mouse_x, ui.input.mouse_y)) {
                g.value_ptr.* -= dy * lh;
                ui.eatScroll();
            }
            const max_scroll = content_h - view_h + 4;
            if (g.value_ptr.* < 0) g.value_ptr.* = 0;
            if (g.value_ptr.* > max_scroll) g.value_ptr.* = max_scroll;
            scroll = g.value_ptr.*;
        }
    }

    const focused = ui.focus.a == i.a;
    // Grip matches field border (accent when focused/resizing).
    const grip_col = if (focused or ed.resizing) ui.theme.accent else ui.theme.panel_border;

    var changed = false;
    if (ed.resizing) {
        // Ghost: empty field shell at the preview size (no text/layout thrash).
        const ghost = Rect{
            .x = outer.x,
            .y = outer.y,
            .w = ed.resize_preview_w,
            .h = ed.resize_preview_h,
        };
        // Dim placeholder of the committed slot so layout space stays visible.
        ui.drawRectBorder(outer, .{ 0.06, 0.07, 0.09, 0.35 }, ui.theme.panel_border, 1);
        // Live preview shell (matches input chrome, accent border while active).
        ui.drawRectBorder(ghost, ui.theme.input_bg, ui.theme.accent, 1);
        // Optional label hint inside ghost
        ui.drawText(ghost.x + 6, ghost.y + 4, size, ui.theme.text_dim, "…");
        drawGrip(ui, gr, grip_col);
    } else {
        if (want_gutter) {
            // One rectangle around gutter + text (no second focus ring from textFieldCore).
            const border_col = if (focused) ui.theme.accent else ui.theme.panel_border;
            ui.drawRectBorder(outer, ui.theme.input_bg, border_col, 1);
            // Gutter plate inset so it never redraws a second border column.
            ui.drawRect(.{
                .x = outer.x + 1,
                .y = outer.y + 1,
                .w = gutter_w - 1,
                .h = outer.h - 2,
            }, .{ 0.10, 0.11, 0.13, 1 });
            // Subtle divider between gutter and text (not a focus chrome).
            ui.drawRect(.{
                .x = outer.x + gutter_w - 1,
                .y = outer.y + 1,
                .w = 1,
                .h = outer.h - 2,
            }, ui.theme.panel_border);
            // Hard-line numbers aligned to the first soft row of each hard line.
            var rows_buf: [te.MaxSoftRows]te.VisualRow = undefined;
            const nrows = te.layoutSoft(text, ui.font, size, wrap_px, rows_buf[0..]);
            var hard_n: u32 = 1;
            var ri: usize = 0;
            while (ri < nrows) : (ri += 1) {
                const vr = rows_buf[ri];
                const is_hard_start = vr.start == 0 or (vr.start > 0 and text[vr.start - 1] == '\n');
                if (!is_hard_start) continue;
                const y = outer.y + 4 - scroll + @as(f32, @floatFromInt(ri)) * lh;
                if (y + lh < outer.y or y > outer.y + outer.h) {
                    hard_n += 1;
                    continue;
                }
                var nbuf: [8]u8 = undefined;
                const ns = std.fmt.bufPrint(&nbuf, "{d}", .{hard_n}) catch "?";
                const nm = ui.font.measure(ns, size);
                ui.drawText(outer.x + gutter_w - 6 - nm.w, y, size, ui.theme.text_dim, ns);
                hard_n += 1;
            }
            changed = textFieldCore.textFieldCore(ui, .{
                .id_key = i.a,
                .box = box,
                // Full field including gutter for hover/focus hit-testing.
                .hit_box = outer,
                .buf = opts.buf,
                .len = opts.len,
                .multiline = true,
                .size = size,
                .scroll_y = scroll,
                .show_border = false,
            });
        } else {
            changed = textFieldCore.textFieldCore(ui, .{
                .id_key = i.a,
                .box = box,
                .buf = opts.buf,
                .len = opts.len,
                .multiline = true,
                .size = size,
                .scroll_y = scroll,
            });
        }
        drawGrip(ui, gr, grip_col);
    }

    // After textFieldCore (which may set ibeam): SE grip wins with resize_nwse.
    if (ed.resizing or gr.contains(ui.input.mouse_x, ui.input.mouse_y)) {
        ui.setSoftCursor(.cursor_resize_nwse);
    }

    return changed;
}
