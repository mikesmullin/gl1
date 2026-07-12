//! Simple key–value pair list editor.
const std = @import("std");
const types = @import("../types.zig");
const Rect = types.Rect;
const textFieldCore = @import("textFieldCore.zig");

pub const MaxPairs = 8;
pub const FieldLen = 32;

pub fn keyValueEditor(ui: anytype, opts: anytype) bool {
    const size = ui.theme.font_size;
    const row_h = ui.theme.row_h;
    const n = opts.count.*;
    const rm_w: f32 = 26;
    const gap: f32 = 6;
    const label_h: f32 = 14 + 6;
    // Tight packing: label + n rows + one add-button row (no spare empty rows).
    const h = label_h + @as(f32, @floatFromInt(n)) * (row_h + 4) + row_h + 4;
    const r = ui.alloc(opts.w, h);
    ui.drawText(r.x, r.y, size, ui.theme.text_dim, opts.label);

    var changed = false;
    var y = r.y + label_h;
    const fields_w = opts.w - rm_w - gap;
    const col_w = (fields_w - gap) * 0.5;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        var idk: [40]u8 = undefined;
        var idv: [40]u8 = undefined;
        const sk = std.fmt.bufPrint(&idk, "{s}_k{d}", .{ opts.id, i }) catch "k";
        const sv = std.fmt.bufPrint(&idv, "{s}_v{d}", .{ opts.id, i }) catch "v";
        const bk = Rect{ .x = r.x, .y = y, .w = col_w, .h = row_h };
        const bv = Rect{ .x = r.x + col_w + gap, .y = y, .w = col_w, .h = row_h };
        if (textFieldCore.textFieldCore(ui, .{
            .id_key = ui.id(sk).a,
            .box = bk,
            .buf = opts.keys[i][0..],
            .len = &opts.key_lens[i],
            .multiline = false,
            .size = size,
            .scroll_y = 0,
        })) changed = true;
        if (textFieldCore.textFieldCore(ui, .{
            .id_key = ui.id(sv).a,
            .box = bv,
            .buf = opts.vals[i][0..],
            .len = &opts.val_lens[i],
            .multiline = false,
            .size = size,
            .scroll_y = 0,
        })) changed = true;

        const rm = Rect{ .x = bv.x + bv.w + gap, .y = y, .w = rm_w, .h = row_h };
        var idr: [40]u8 = undefined;
        const sr = std.fmt.bufPrint(&idr, "{s}_rm{d}", .{ opts.id, i }) catch "rm";
        const rst = ui.interact(ui.id(sr), rm, false);
        ui.drawRectBorder(rm, if (rst.hot) ui.theme.button_hot else ui.theme.button, ui.theme.panel_border, 1);
        ui.drawIcon(rm.x + (rm.w - 14) * 0.5, rm.y + (rm.h - 14) * 0.5, 14, .close, if (rst.hot) ui.theme.danger else null);
        if (rst.hot) ui.setSoftCursor(.cursor_hand_open);
        if (rst.clicked) {
            var j = i;
            while (j + 1 < opts.count.*) : (j += 1) {
                opts.keys[j] = opts.keys[j + 1];
                opts.key_lens[j] = opts.key_lens[j + 1];
                opts.vals[j] = opts.vals[j + 1];
                opts.val_lens[j] = opts.val_lens[j + 1];
            }
            opts.count.* -= 1;
            changed = true;
            break;
        }
        y += row_h + 4;
    }
    if (opts.count.* < MaxPairs) {
        // Place add control immediately under last row (absolute, no extra layout gap).
        var ida: [48]u8 = undefined;
        const sa = std.fmt.bufPrint(&ida, "{s}_add", .{opts.id}) catch "kvadd";
        const add_r = Rect{ .x = r.x, .y = y, .w = 100, .h = row_h };
        // iconButton would alloc; draw absolute icon+label button
        const st = ui.interact(ui.id(sa), add_r, false);
        ui.drawRectBorder(add_r, if (st.hot) ui.theme.button_hot else ui.theme.button, ui.theme.panel_border, 1);
        // "add" maps to plus art in the atlas (fromName("add") → .plus)
        ui.drawIcon(add_r.x + 8, add_r.y + (row_h - 16) * 0.5, 16, .plus, null);
        ui.drawText(add_r.x + 8 + 16 + 6, add_r.y + 6, size, ui.theme.text, "pair");
        if (st.hot) ui.setSoftCursor(.cursor_hand_open);
        if (st.clicked) {
            const c = opts.count.*;
            opts.key_lens[c] = 0;
            opts.val_lens[c] = 0;
            opts.count.* += 1;
            changed = true;
        }
    }
    return changed;
}
