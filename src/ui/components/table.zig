//! Simple data table: columns, row select, optional sort headers.
const std = @import("std");
const types = @import("../types.zig");
const Color = types.Color;
const Rect = types.Rect;

pub fn table(ui: anytype, opts: anytype) bool {
    const size = ui.theme.font_size;
    const row_h = ui.theme.row_h;
    const cols: []const []const u8 = opts.columns;
    const col_n = cols.len;
    if (col_n == 0) return false;
    const nrows: usize = if (@hasField(@TypeOf(opts), "nrows")) opts.nrows else opts.cells.len;

    const total_h = row_h * @as(f32, @floatFromInt(nrows + 1)) + 2;
    const r = ui.alloc(opts.w, total_h);
    const col_w = r.w / @as(f32, @floatFromInt(col_n));

    // Background fill (opaque) then outline only — never drawRectBorder with transparent fill.
    ui.drawRect(r, ui.theme.panel);
    ui.drawRectOutline(r, ui.theme.panel_border, 1);

    // Header
    ui.drawRect(.{ .x = r.x + 1, .y = r.y + 1, .w = r.w - 2, .h = row_h - 1 }, .{ 0.12, 0.14, 0.16, 1 });
    var c: usize = 0;
    while (c < col_n) : (c += 1) {
        const hr = Rect{
            .x = r.x + col_w * @as(f32, @floatFromInt(c)),
            .y = r.y,
            .w = col_w,
            .h = row_h,
        };
        var idb: [40]u8 = undefined;
        const ids = std.fmt.bufPrint(&idb, "{s}_h{d}", .{ opts.id, c }) catch "th";
        const hst = ui.interactEx(ui.id(ids), hr, false, .{ .focus_ring = false });
        if (hst.hot) ui.drawRect(hr, ui.theme.button_hot);
        ui.drawText(hr.x + 6, hr.y + 6, size, ui.theme.text_dim, cols[c]);
        // Sort carets: caret-n (up) / caret-s (down) = arrow_up / arrow_down.
        if (@hasField(@TypeOf(opts), "sort_col") and opts.sort_col.* == c) {
            const icon_sz: f32 = 12;
            const ic = if (opts.sort_asc.*) @import("../../icons.zig").IconId.arrow_up else @import("../../icons.zig").IconId.arrow_down;
            ui.drawIcon(hr.x + hr.w - icon_sz - 6, hr.y + (hr.h - icon_sz) * 0.5, icon_sz, ic, ui.theme.accent);
        }
        if (hst.clicked and @hasField(@TypeOf(opts), "sort_col")) {
            if (opts.sort_col.* == c) {
                opts.sort_asc.* = !opts.sort_asc.*;
            } else {
                opts.sort_col.* = c;
                opts.sort_asc.* = true;
            }
        }
        if (c + 1 < col_n) {
            ui.drawRect(.{ .x = hr.x + hr.w - 1, .y = r.y + 1, .w = 1, .h = total_h - 2 }, ui.theme.panel_border);
        }
    }
    ui.drawRect(.{ .x = r.x + 1, .y = r.y + row_h, .w = r.w - 2, .h = 1 }, ui.theme.panel_border);

    var changed = false;
    var row: usize = 0;
    while (row < nrows) : (row += 1) {
        const yy = r.y + row_h * @as(f32, @floatFromInt(row + 1));
        const rr = Rect{ .x = r.x + 1, .y = yy, .w = r.w - 2, .h = row_h };
        var idr: [40]u8 = undefined;
        const ids = std.fmt.bufPrint(&idr, "{s}_r{d}", .{ opts.id, row }) catch "tr";
        const rst = ui.interactEx(ui.id(ids), rr, false, .{ .focus_ring = false });
        const sel = if (@hasField(@TypeOf(opts), "selected")) opts.selected.* == @as(i32, @intCast(row)) else false;
        if (sel) {
            ui.drawRect(rr, ui.theme.selected);
        } else if (rst.hot) {
            ui.drawRect(rr, ui.theme.button_hot);
        } else if (row % 2 == 1) {
            ui.drawRect(rr, .{ 0.11, 0.12, 0.14, 1 });
        }
        c = 0;
        while (c < col_n) : (c += 1) {
            const cell: []const u8 = opts.cells[row][c];
            ui.drawText(r.x + col_w * @as(f32, @floatFromInt(c)) + 6, yy + 6, size, ui.theme.text, cell);
        }
        if (rst.clicked and @hasField(@TypeOf(opts), "selected")) {
            opts.selected.* = @intCast(row);
            changed = true;
        }
        if (rst.hot) ui.setSoftCursor(.cursor_hand_open);
    }
    _ = Color;
    return changed;
}
