//! Masked password / secret field (show/hide toggle).
const std = @import("std");
const types = @import("../types.zig");
const Rect = types.Rect;
const textFieldCore = @import("textFieldCore.zig");

pub fn passwordInput(ui: anytype, opts: anytype) bool {
    const i = ui.id(opts.id);
    const size = ui.theme.font_size;
    const label_gap: f32 = 6;
    const r = ui.alloc(opts.w, ui.theme.row_h + 14 + label_gap);
    ui.drawText(r.x, r.y, size, ui.theme.text_dim, opts.label);

    const eye_w: f32 = 28;
    const box = Rect{ .x = r.x, .y = r.y + 12 + label_gap, .w = opts.w - eye_w - 4, .h = ui.theme.row_h };
    const eye = Rect{ .x = box.x + box.w + 4, .y = box.y, .w = eye_w, .h = box.h };

    const show_ptr: *bool = opts.show;

    // Masked display buffer when hidden.
    var mask_buf: [128]u8 = undefined;
    const n = @min(opts.len.*, mask_buf.len);
    if (!show_ptr.*) {
        @memset(mask_buf[0..n], '*');
    }

    var changed = false;
    if (show_ptr.*) {
        changed = textFieldCore.textFieldCore(ui, .{
            .id_key = i.a,
            .box = box,
            .buf = opts.buf,
            .len = opts.len,
            .multiline = false,
            .size = size,
            .scroll_y = 0,
        });
    } else {
        // Draw masked look; still edit real buffer via core when focused —
        // simple approach: always use core on real buf, overlay mask when unfocused.
        // Better: always edit real, draw stars by temporarily swapping display.
        // For IMUI: run core on real buffer; if !show, redraw text as stars after.
        changed = textFieldCore.textFieldCore(ui, .{
            .id_key = i.a,
            .box = box,
            .buf = opts.buf,
            .len = opts.len,
            .multiline = false,
            .size = size,
            .scroll_y = 0,
        });
        // Cover real glyphs with stars when not showing (except caret still ok).
        if (n > 0) {
            ui.drawRect(.{ .x = box.x + 2, .y = box.y + 2, .w = box.w - 4, .h = box.h - 4 }, ui.theme.input_bg);
            ui.drawText(box.x + 6, box.y + 6, size, ui.theme.text, mask_buf[0..n]);
        }
    }

    const est = ui.interact(ui.id("eye"), eye, false);
    ui.drawRectBorder(eye, if (est.hot) ui.theme.button_hot else ui.theme.button, ui.theme.panel_border, 1);
    ui.drawIcon(eye.x + 5, eye.y + 5, 18, .eye, null);
    if (est.clicked) show_ptr.* = !show_ptr.*;
    if (est.hot) ui.setSoftCursor(.cursor_hand_open);
    _ = std;
    return changed;
}
