//! Reusable UI component.
const std = @import("std");
const types = @import("../types.zig");
const te = @import("../text_edit.zig");
const Color = types.Color;
const Rect = types.Rect;
const Id = types.Id;

pub fn dropdown(ui: anytype, opts: anytype) bool {
    const i = ui.id(opts.id);
    const size = ui.theme.font_size;
    const r = ui.alloc(opts.w, ui.theme.row_h + 14);
    ui.drawText(r.x, r.y, size, ui.theme.text_dim, opts.label);
    const box = Rect{ .x = r.x, .y = r.y + 12, .w = opts.w, .h = ui.theme.row_h };
    const st = ui.interact(i, box, false);
    if (st.clicked) opts.open.* = !opts.open.*;

    const sel = if (opts.selected.* < opts.items.len) opts.items[opts.selected.*] else "(none)";
    ui.drawRectBorder(box, ui.theme.input_bg, if (opts.open.*) ui.theme.accent else ui.theme.panel_border, 1);
    ui.drawText(box.x + 6, box.y + 6, size, ui.theme.text, sel);
    ui.drawText(box.x + box.w - 18, box.y + 6, size, ui.theme.text_dim, if (opts.open.*) "^" else "v");

    var changed = false;
    if (opts.open.*) {
        const item_h = ui.theme.row_h;
        const menu = Rect{
            .x = box.x,
            .y = box.y + box.h,
            .w = box.w,
            .h = item_h * @as(f32, @floatFromInt(opts.items.len)),
        };
        ui.drawRectBorder(menu, ui.theme.panel, ui.theme.panel_border, 1);
        for (opts.items, 0..) |item, idx| {
            const ir = Rect{
                .x = menu.x,
                .y = menu.y + @as(f32, @floatFromInt(idx)) * item_h,
                .w = menu.w,
                .h = item_h,
            };
            var id_buf: [64]u8 = undefined;
            const iid_s = std.fmt.bufPrint(&id_buf, "{s}#{d}", .{ opts.id, idx }) catch "dd";
            const iid = ui.id(iid_s);
            const ist = ui.interact(iid, ir, false);
            if (ist.hot or opts.selected.* == idx) {
                ui.drawRect(ir, if (opts.selected.* == idx) ui.theme.selected else ui.theme.button_hot);
            }
            ui.drawText(ir.x + 6, ir.y + 6, size, ui.theme.text, item);
            if (ist.clicked) {
                opts.selected.* = idx;
                opts.open.* = false;
                changed = true;
            }
        }
        // Click outside closes (if not over menu/box).
        if (ui.input.mousePressed(.left)) {
            const over = box.contains(ui.input.mouse_x, ui.input.mouse_y) or
                menu.contains(ui.input.mouse_x, ui.input.mouse_y);
            if (!over) opts.open.* = false;
        }
    }
    return changed;
}
