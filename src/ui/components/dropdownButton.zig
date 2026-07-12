//! Primary button with split chevron menu.
//! Returns: null = none, -1 = main clicked, >=0 = menu item index.
const std = @import("std");
const types = @import("../types.zig");
const Color = types.Color;
const Rect = types.Rect;

pub fn dropdownButton(ui: anytype, opts: anytype) ?i32 {
    const size = ui.theme.font_size;
    const h = ui.theme.button_h;
    const m = ui.font.measure(opts.label, size);
    const main_w = if (@hasField(@TypeOf(opts), "w") and opts.w > 0) opts.w - 28 else @max(m.w + 24, 80);
    const r = ui.alloc(main_w + 28, h);
    const main = Rect{ .x = r.x, .y = r.y, .w = main_w, .h = h };
    const chev = Rect{ .x = r.x + main_w, .y = r.y, .w = 28, .h = h };

    var idm: [48]u8 = undefined;
    var idc: [48]u8 = undefined;
    const sm = std.fmt.bufPrint(&idm, "{s}_main", .{opts.id}) catch "dbm";
    const sc = std.fmt.bufPrint(&idc, "{s}_chev", .{opts.id}) catch "dbc";
    const im = ui.interact(ui.id(sm), main, false);
    const ic = ui.interact(ui.id(sc), chev, false);

    const fill: Color = if (im.active or ic.active) ui.theme.button_active else if (im.hot or ic.hot) ui.theme.button_hot else ui.theme.button;
    ui.drawRectBorder(main, fill, ui.theme.panel_border, 1);
    ui.drawRectBorder(chev, fill, ui.theme.panel_border, 1);
    ui.drawText(main.x + (main.w - m.w) * 0.5, main.y + (main.h - m.h) * 0.5, size, ui.theme.text, opts.label);
    ui.drawIcon(chev.x + 6, chev.y + 6, 16, if (opts.open.*) .arrow_down else .arrow_right, null);
    if (im.hot or ic.hot) ui.setSoftCursor(.cursor_hand_open);

    if (ic.clicked) opts.open.* = !opts.open.*;
    if (im.clicked) {
        opts.open.* = false;
        return -1;
    }

    if (opts.open.*) {
        const items: []const []const u8 = opts.items;
        const item_h = ui.theme.row_h;
        const menu = Rect{
            .x = main.x,
            .y = main.y + main.h,
            .w = main.w + chev.w,
            .h = item_h * @as(f32, @floatFromInt(items.len)),
        };
        ui.drawRectBorder(menu, ui.theme.panel, ui.theme.panel_border, 1);
        for (items, 0..) |item, idx| {
            const ir = Rect{
                .x = menu.x,
                .y = menu.y + @as(f32, @floatFromInt(idx)) * item_h,
                .w = menu.w,
                .h = item_h,
            };
            var idb: [48]u8 = undefined;
            const ids = std.fmt.bufPrint(&idb, "{s}#ddb{d}", .{ opts.id, idx }) catch "ddb";
            const ist = ui.interact(ui.id(ids), ir, false);
            if (ist.hot) ui.drawRect(ir, ui.theme.button_hot);
            ui.drawText(ir.x + 8, ir.y + 6, size, ui.theme.text, item);
            if (ist.clicked) {
                opts.open.* = false;
                return @intCast(idx);
            }
        }
        if (ui.input.mousePressed(.left)) {
            const over = main.contains(ui.input.mouse_x, ui.input.mouse_y) or
                chev.contains(ui.input.mouse_x, ui.input.mouse_y) or
                menu.contains(ui.input.mouse_x, ui.input.mouse_y);
            if (!over) opts.open.* = false;
        }
    }
    return null;
}
