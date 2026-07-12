//! Multi-select dropdown (real checkbox chrome per row).
const std = @import("std");
const types = @import("../types.zig");
const Rect = types.Rect;

pub fn multiSelect(ui: anytype, opts: anytype) bool {
    const i = ui.id(opts.id);
    const size = ui.theme.font_size;
    const label_gap: f32 = 6;
    const r = ui.alloc(opts.w, ui.theme.row_h + 14 + label_gap);
    ui.drawText(r.x, r.y, size, ui.theme.text_dim, opts.label);
    const box = Rect{ .x = r.x, .y = r.y + 12 + label_gap, .w = opts.w, .h = ui.theme.row_h };
    const st = ui.interact(i, box, false);
    if (st.clicked) opts.open.* = !opts.open.*;

    var n_on: usize = 0;
    const items: []const []const u8 = opts.items;
    for (opts.selected[0..items.len]) |s| {
        if (s) n_on += 1;
    }
    var sum: [48]u8 = undefined;
    const sum_s = if (n_on == 0)
        "(none)"
    else
        (std.fmt.bufPrint(&sum, "{d} selected", .{n_on}) catch "?");
    ui.drawRectBorder(box, ui.theme.input_bg, if (opts.open.*) ui.theme.accent else ui.theme.panel_border, 1);
    ui.drawText(box.x + 6, box.y + 6, size, ui.theme.text, sum_s);
    ui.drawIcon(box.x + box.w - 22, box.y + (box.h - 16) * 0.5, 16, if (opts.open.*) .arrow_down else .arrow_right, null);
    if (st.hot) ui.setSoftCursor(.cursor_hand_open);

    var changed = false;
    if (opts.open.*) {
        const item_h = ui.theme.row_h;
        const menu = Rect{
            .x = box.x,
            .y = box.y + box.h,
            .w = box.w,
            .h = item_h * @as(f32, @floatFromInt(items.len)),
        };
        ui.drawRectBorder(menu, ui.theme.panel, ui.theme.panel_border, 1);
        const box_sz: f32 = 16;
        for (items, 0..) |item, idx| {
            const ir = Rect{
                .x = menu.x,
                .y = menu.y + @as(f32, @floatFromInt(idx)) * item_h,
                .w = menu.w,
                .h = item_h,
            };
            var idb: [48]u8 = undefined;
            const ids = std.fmt.bufPrint(&idb, "{s}#ms{d}", .{ opts.id, idx }) catch "ms";
            const ist = ui.interact(ui.id(ids), ir, false);
            if (ist.hot) ui.drawRect(ir, ui.theme.button_hot);
            // Checkbox chrome (matches checkbox.zig style, no layout alloc).
            const br = Rect{
                .x = ir.x + 8,
                .y = ir.y + (item_h - box_sz) * 0.5,
                .w = box_sz,
                .h = box_sz,
            };
            ui.drawRectBorder(br, ui.theme.input_bg, ui.theme.panel_border, 1);
            if (opts.selected[idx]) {
                const inset: f32 = 3;
                ui.drawRect(.{
                    .x = br.x + inset,
                    .y = br.y + inset,
                    .w = br.w - 2 * inset,
                    .h = br.h - 2 * inset,
                }, ui.theme.accent);
            }
            ui.drawText(ir.x + 8 + box_sz + 8, ir.y + 6, size, ui.theme.text, item);
            if (ist.clicked) {
                opts.selected[idx] = !opts.selected[idx];
                changed = true;
            }
        }
        if (ui.input.mousePressed(.left)) {
            const over = box.contains(ui.input.mouse_x, ui.input.mouse_y) or
                menu.contains(ui.input.mouse_x, ui.input.mouse_y);
            if (!over) opts.open.* = false;
        }
    }
    return changed;
}
