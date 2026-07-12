//! Exclusive accordion — only one section open at a time.
const types = @import("../types.zig");
const Rect = types.Rect;

/// `open_index` holds the currently open section (-1 = all closed).
/// `index` is this section's id within the group.
pub fn beginSection(ui: anytype, opts: anytype) bool {
    const i = ui.id(opts.id);
    const r = ui.alloc(0, ui.theme.row_h);
    const full = Rect{ .x = r.x, .y = r.y, .w = r.w, .h = ui.theme.row_h };
    const st = ui.interact(i, full, false);

    const open_index: *i32 = opts.open_index;
    const index: i32 = @intCast(opts.index);
    const is_open = open_index.* == index;

    if (st.clicked) {
        if (is_open) {
            open_index.* = -1; // collapse
        } else {
            open_index.* = index; // exclusive open
        }
    }
    const now_open = open_index.* == index;

    ui.drawRect(full, if (st.hot) ui.theme.button_hot else ui.theme.button);
    ui.drawIcon(full.x + 6, full.y + 6, 16, if (now_open) .arrow_down else .arrow_right, null);
    ui.drawText(full.x + 28, full.y + 6, ui.theme.font_size, ui.theme.text, opts.title);
    if (st.hot) ui.setSoftCursor(.cursor_hand_open);
    if (now_open) {
        ui.pushId(opts.id);
        ui.beginVStack(.{
            .x = full.x,
            .y = full.y + full.h,
            .w = full.w,
            .h = 400,
            .pad = 4,
            .gap = ui.theme.gap,
        });
    }
    return now_open;
}

pub fn endSection(ui: anytype, open: bool) void {
    if (!open) return;
    _ = ui.endVStack();
    ui.popId();
}
