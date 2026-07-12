//! Typeahead / autocomplete: filter items as you type; click or Enter to pick.
//! Arrow up/down moves highlight; Tab injects first match; Enter activates highlight.
const std = @import("std");
const types = @import("../types.zig");
const Rect = types.Rect;
const textFieldCore = @import("textFieldCore.zig");

fn matches(q: []const u8, item: []const u8) bool {
    if (q.len == 0) return true;
    if (q.len > item.len) return false;
    var i: usize = 0;
    while (i + q.len <= item.len) : (i += 1) {
        var ok = true;
        var j: usize = 0;
        while (j < q.len) : (j += 1) {
            const a = std.ascii.toLower(item[i + j]);
            const b = std.ascii.toLower(q[j]);
            if (a != b) {
                ok = false;
                break;
            }
        }
        if (ok) return true;
    }
    return false;
}

pub fn typeahead(ui: anytype, opts: anytype) bool {
    const i = ui.id(opts.id);
    const size = ui.theme.font_size;
    const label_gap: f32 = 6;
    const r = ui.alloc(opts.w, ui.theme.row_h + 14 + label_gap);
    ui.drawText(r.x, r.y, size, ui.theme.text_dim, opts.label);
    const box = Rect{ .x = r.x, .y = r.y + 12 + label_gap, .w = opts.w, .h = ui.theme.row_h };

    _ = textFieldCore.textFieldCore(ui, .{
        .id_key = i.a,
        .box = box,
        .buf = opts.buf,
        .len = opts.len,
        .multiline = false,
        .size = size,
        .scroll_y = 0,
    });

    var changed = false;
    const focused = ui.focus.a == i.a;
    const q = opts.buf[0..opts.len.*];
    const show_all = if (@hasField(@TypeOf(opts), "show_all_when_empty")) opts.show_all_when_empty else false;
    const open = focused and (q.len > 0 or show_all);

    // Highlight index stored in selected when present, else local via edit state reuse of selected.
    const hi_ptr: ?*usize = if (@hasField(@TypeOf(opts), "highlight")) opts.highlight else if (@hasField(@TypeOf(opts), "selected")) opts.selected else null;

    if (open) {
        const item_h = ui.theme.row_h;
        var shown: usize = 0;
        var match_idx: [32]usize = undefined;
        const items: []const []const u8 = opts.items;
        for (items, 0..) |item, idx| {
            if (!matches(q, item)) continue;
            if (shown >= match_idx.len) break;
            match_idx[shown] = idx;
            shown += 1;
        }
        if (shown > 0) {
            var hi: usize = 0;
            if (hi_ptr) |hp| {
                if (hp.* >= shown) hp.* = 0;
                hi = hp.*;
            }

            // Keyboard: arrows move highlight; Enter commits; Tab injects first match.
            if (ui.input.keyPressed(.down)) {
                if (hi_ptr) |hp| hp.* = (hi + 1) % shown;
                hi = if (hi_ptr) |hp| hp.* else 0;
            }
            if (ui.input.keyPressed(.up)) {
                if (hi_ptr) |hp| hp.* = if (hi == 0) shown - 1 else hi - 1;
                hi = if (hi_ptr) |hp| hp.* else 0;
            }
            if (ui.input.keyPressed(.tab)) {
                // First match into field; stay focused (don't cycle focus).
                ui.consumed_tab = true;
                applyPick(ui, opts, match_idx[0]);
                if (hi_ptr) |hp| hp.* = 0;
                changed = true;
            }
            if (ui.input.keyPressed(.enter)) {
                applyPick(ui, opts, match_idx[hi]);
                ui.focus = .{};
                changed = true;
            }

            const menu = Rect{
                .x = box.x,
                .y = box.y + box.h,
                .w = box.w,
                .h = item_h * @as(f32, @floatFromInt(shown)),
            };
            ui.drawRectBorder(menu, ui.theme.panel, ui.theme.panel_border, 1);
            var s: usize = 0;
            while (s < shown) : (s += 1) {
                const idx = match_idx[s];
                const ir = Rect{
                    .x = menu.x,
                    .y = menu.y + @as(f32, @floatFromInt(s)) * item_h,
                    .w = menu.w,
                    .h = item_h,
                };
                var idb: [48]u8 = undefined;
                const ids = std.fmt.bufPrint(&idb, "{s}#ta{d}", .{ opts.id, idx }) catch "ta";
                const ist = ui.interact(ui.id(ids), ir, false);
                const lit = ist.hot or s == hi;
                if (lit) ui.drawRect(ir, if (s == hi) ui.theme.selected else ui.theme.button_hot);
                ui.drawText(ir.x + 6, ir.y + 6, size, ui.theme.text, items[idx]);
                if (ist.clicked) {
                    applyPick(ui, opts, idx);
                    ui.focus = .{};
                    changed = true;
                }
                if (ist.hot and hi_ptr != null) hi_ptr.?.* = s;
            }
        }
    }
    return changed;
}

fn applyPick(ui: anytype, opts: anytype, idx: usize) void {
    const pick = opts.items[idx];
    const n = @min(pick.len, opts.buf.len);
    @memcpy(opts.buf[0..n], pick[0..n]);
    opts.len.* = n;
    if (@hasField(@TypeOf(opts), "selected")) {
        opts.selected.* = idx;
    }
    // Move caret to end of inserted value.
    const key = ui.id(opts.id).a;
    const ed = ui.editState(key);
    ed.setCaret(opts.len.*, opts.len.*, false);
}

/// Combobox: typeahead that shows the full list while focused (empty query OK).
pub fn combobox(ui: anytype, opts: anytype) bool {
    if (@hasField(@TypeOf(opts), "selected")) {
        return typeahead(ui, .{
            .id = opts.id,
            .label = opts.label,
            .buf = opts.buf,
            .len = opts.len,
            .items = opts.items,
            .w = opts.w,
            .selected = opts.selected,
            .highlight = if (@hasField(@TypeOf(opts), "highlight")) opts.highlight else opts.selected,
            .show_all_when_empty = true,
        });
    }
    return typeahead(ui, .{
        .id = opts.id,
        .label = opts.label,
        .buf = opts.buf,
        .len = opts.len,
        .items = opts.items,
        .w = opts.w,
        .show_all_when_empty = true,
    });
}
