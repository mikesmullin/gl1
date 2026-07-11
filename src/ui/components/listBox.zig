//! Reusable UI component.
const std = @import("std");
const types = @import("../types.zig");
const te = @import("../text_edit.zig");
const Color = types.Color;
const Rect = types.Rect;
const Id = types.Id;

pub fn listBox(ui: anytype, opts: anytype) bool {
    const i = ui.id(opts.id);
    const r = ui.alloc(opts.w, opts.h);
    ui.remember(i, r);
    ui.drawRectBorder(r, ui.theme.input_bg, ui.theme.panel_border, 1);
    var changed = false;
    const item_h = ui.theme.row_h - 4;
    ui.pushId(opts.id);
    defer ui.popId();
    ui.cmds.push(.{ .scissor_push = .{ .x = r.x + 1, .y = r.y + 1, .w = r.w - 2, .h = r.h - 2 } });
    for (opts.items, 0..) |item, idx| {
        const ir = Rect{
            .x = r.x + 2,
            .y = r.y + 2 + @as(f32, @floatFromInt(idx)) * item_h,
            .w = r.w - 4,
            .h = item_h,
        };
        const iid = ui.id(item);
        const st = ui.interact(iid, ir, false);
        const on = opts.selected.* == idx;
        if (on or st.hot) {
            ui.drawRect(ir, if (on) ui.theme.selected else ui.theme.button_hot);
        }
        ui.drawText(ir.x + 6, ir.y + 5, ui.theme.font_size, ui.theme.text, item);
        if (st.clicked) {
            opts.selected.* = idx;
            changed = true;
        }
    }
    ui.cmds.push(.{ .scissor_pop = {} });
    return changed;
}
