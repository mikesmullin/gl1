//! Async / request-state button: idle → loading → ok | err.
const std = @import("std");
const types = @import("../types.zig");
const Color = types.Color;
const Rect = types.Rect;

pub const State = enum { idle, loading, ok, err };

pub fn requestButton(ui: anytype, opts: anytype) bool {
    const size = ui.theme.font_size;
    const st_val: State = if (@hasField(@TypeOf(opts), "force"))
        opts.force
    else
        opts.state.*;

    const label: []const u8 = switch (st_val) {
        .idle => if (@hasField(@TypeOf(opts), "label")) opts.label else "Submit",
        .loading => if (@hasField(@TypeOf(opts), "label_loading")) opts.label_loading else "Working…",
        .ok => if (@hasField(@TypeOf(opts), "label_ok")) opts.label_ok else "Done",
        .err => if (@hasField(@TypeOf(opts), "label_err")) opts.label_err else "Failed",
    };
    const m = ui.font.measure(label, size);
    const bw = if (@hasField(@TypeOf(opts), "w") and opts.w > 0) opts.w else @max(m.w + 28, 100);
    const bh = ui.theme.button_h;
    const r = ui.alloc(bw, bh);
    const i = ui.id(opts.id);
    const disabled = st_val == .loading or if (@hasField(@TypeOf(opts), "force")) true else false;
    // force= frozen display: never clickable
    const frozen = @hasField(@TypeOf(opts), "force");
    const st = ui.interact(i, r, frozen or disabled);

    const fill: Color = switch (st_val) {
        .idle => if (st.active) ui.theme.button_active else if (st.hot) ui.theme.button_hot else ui.theme.button,
        .loading => ui.theme.button_disabled,
        .ok => .{ ui.theme.accent[0] * 0.35, ui.theme.accent[1] * 0.35, ui.theme.accent[2] * 0.35, 1 },
        .err => .{ ui.theme.danger[0] * 0.35, ui.theme.danger[1] * 0.35, ui.theme.danger[2] * 0.35, 1 },
    };
    const border: Color = switch (st_val) {
        .idle => ui.theme.panel_border,
        .loading => ui.theme.panel_border,
        .ok => ui.theme.accent,
        .err => ui.theme.danger,
    };
    ui.drawRectBorder(r, fill, border, 1);

    if (st_val == .loading) {
        // Mini spinner dots
        const t = ui.time;
        const phase = @mod(@as(i32, @intFromFloat(t * 6)), 3);
        _ = phase;
        const lm = ui.font.measure(label, size);
        const spin_r: f32 = 6;
        const pad_l: f32 = 5; // left inset so spinner isn't flush to button edge
        const gap_sp: f32 = 5; // spinner → label
        const block_w = pad_l + spin_r * 2 + gap_sp + lm.w;
        // Prefer centered block; if that would clip left pad, pin to left+pad.
        var block_x = r.x + (r.w - block_w) * 0.5;
        if (block_x < r.x + pad_l) block_x = r.x + pad_l;
        const cx = block_x + pad_l + spin_r;
        const cy = r.y + r.h * 0.5;
        ui.drawText(block_x + pad_l + spin_r * 2 + gap_sp, r.y + (r.h - lm.h) * 0.5, size, ui.theme.text_dim, label);
        // spinning dots
        const ang = @as(f32, @floatCast(t * 6));
        var k: i32 = 0;
        while (k < 8) : (k += 1) {
            const a = ang + @as(f32, @floatFromInt(k)) * 0.785;
            const fade = @as(f32, @floatFromInt(k)) / 8.0;
            const px = cx + @cos(a) * spin_r;
            const py = cy + @sin(a) * spin_r;
            ui.drawRect(.{ .x = px, .y = py, .w = 2, .h = 2 }, .{ 1, 1, 1, 0.3 + fade * 0.7 });
        }
    } else {
        const tc: Color = switch (st_val) {
            .err => ui.theme.danger,
            .ok => ui.theme.accent,
            else => ui.theme.text,
        };
        ui.drawText(r.x + (r.w - m.w) * 0.5, r.y + (r.h - m.h) * 0.5, size, tc, label);
    }
    if (st.hot and !frozen and !disabled) ui.setSoftCursor(.cursor_hand_open);
    return st.clicked and !frozen and st_val == .idle;
}
