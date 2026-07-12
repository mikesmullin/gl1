//! Tag chips + free-type entry (Enter / comma to add).
const std = @import("std");
const types = @import("../types.zig");
const Rect = types.Rect;
const textFieldCore = @import("textFieldCore.zig");

pub const MaxTags = 12;
pub const TagLen = 24;

pub fn tagInput(ui: anytype, opts: anytype) bool {
    const size = ui.theme.font_size;
    const lh = ui.font.lineHeight(size);
    const chip_h = lh + 8;
    const label_gap: f32 = 6;
    // Count rows of chips roughly.
    const r = ui.alloc(opts.w, 14 + label_gap + chip_h + 8 + ui.theme.row_h);
    ui.drawText(r.x, r.y, size, ui.theme.text_dim, opts.label);

    var changed = false;
    var cx = r.x;
    var cy = r.y + 12 + label_gap;
    const tags: [][TagLen]u8 = opts.tags;
    const tag_lens: []usize = opts.tag_lens;
    const tag_count: *usize = opts.tag_count;

    var ti: usize = 0;
    while (ti < tag_count.*) : (ti += 1) {
        const label = tags[ti][0..tag_lens[ti]];
        const m = ui.font.measure(label, size);
        const icon_sz: f32 = 12;
        const gap_li: f32 = 5; // label → close icon
        const cw = m.w + 12 + gap_li + icon_sz + 6;
        if (cx + cw > r.x + opts.w and cx > r.x) {
            cx = r.x;
            cy += chip_h + 4;
        }
        const chip = Rect{ .x = cx, .y = cy, .w = cw, .h = chip_h };
        ui.drawRectBorder(chip, .{ 0.18, 0.22, 0.2, 1 }, ui.theme.accent, 1);
        ui.drawText(chip.x + 6, chip.y + 4, size, ui.theme.accent, label);
        // Close icon to remove
        var idb: [32]u8 = undefined;
        const ids = std.fmt.bufPrint(&idb, "{s}_rm{d}", .{ opts.id, ti }) catch "trm";
        const xr = Rect{
            .x = chip.x + 6 + m.w + gap_li,
            .y = chip.y + (chip_h - icon_sz) * 0.5,
            .w = icon_sz + 2,
            .h = icon_sz + 2,
        };
        const xst = ui.interact(ui.id(ids), xr, false);
        ui.drawIcon(xr.x, xr.y, icon_sz, .close, if (xst.hot) ui.theme.danger else ui.theme.text_dim);
        if (xst.hot) ui.setSoftCursor(.cursor_hand_open);
        if (xst.clicked) {
            // shift down
            var j = ti;
            while (j + 1 < tag_count.*) : (j += 1) {
                tags[j] = tags[j + 1];
                tag_lens[j] = tag_lens[j + 1];
            }
            tag_count.* -= 1;
            changed = true;
            break;
        }
        cx += cw + 6;
    }

    const entry_y = cy + chip_h + 6;
    const box = Rect{ .x = r.x, .y = entry_y, .w = opts.w, .h = ui.theme.row_h };
    const i = ui.id(opts.id);
    _ = textFieldCore.textFieldCore(ui, .{
        .id_key = i.a,
        .box = box,
        .buf = opts.buf,
        .len = opts.len,
        .multiline = false,
        .size = size,
        .scroll_y = 0,
    });

    // Enter or comma commits a tag.
    const focused = ui.focus.a == i.a;
    if (focused and opts.len.* > 0) {
        var commit = ui.input.keyPressed(.enter);
        // comma in text buffer
        if (opts.len.* > 0 and opts.buf[opts.len.* - 1] == ',') {
            opts.len.* -= 1;
            commit = true;
        }
        if (commit and tag_count.* < MaxTags) {
            const raw = opts.buf[0..opts.len.*];
            // trim spaces
            var a: usize = 0;
            while (a < raw.len and raw[a] == ' ') a += 1;
            var b = raw.len;
            while (b > a and raw[b - 1] == ' ') b -= 1;
            if (b > a) {
                const slice = raw[a..b];
                const n = @min(slice.len, TagLen);
                @memcpy(tags[tag_count.*][0..n], slice[0..n]);
                tag_lens[tag_count.*] = n;
                tag_count.* += 1;
                opts.len.* = 0;
                changed = true;
            } else {
                opts.len.* = 0;
            }
        }
    }
    return changed;
}
