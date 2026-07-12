//! Clickable text link — opens URL in the system browser when `url` is set.
const types = @import("../types.zig");
const Color = types.Color;
const Rect = types.Rect;
const open_url = @import("../open_url.zig");

pub fn link(ui: anytype, opts: anytype) bool {
    const size = if (@hasField(@TypeOf(opts), "size")) opts.size else ui.theme.font_size;
    const m = ui.font.measure(opts.label, size);
    const r = ui.alloc(m.w + 4, m.h + 4);
    const i = ui.id(opts.id);
    const st = ui.interact(i, r, false);
    const col: Color = if (st.hot) ui.theme.accent_hot else ui.theme.info;
    ui.drawText(r.x, r.y, size, col, opts.label);
    // underline
    ui.drawRect(.{ .x = r.x, .y = r.y + m.h + 1, .w = m.w, .h = 1 }, col);
    if (st.hot) ui.setSoftCursor(.cursor_hand_open);
    if (st.clicked) {
        if (@hasField(@TypeOf(opts), "url") and opts.url.len > 0) {
            open_url.openUrl(opts.url);
        }
        return true;
    }
    return false;
}
