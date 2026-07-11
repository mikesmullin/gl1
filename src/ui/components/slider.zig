//! Reusable UI component.
const std = @import("std");
const types = @import("../types.zig");
const te = @import("../text_edit.zig");
const Color = types.Color;
const Rect = types.Rect;
const Id = types.Id;

pub fn slider(ui: anytype, opts: anytype) bool {
    const i = ui.id(opts.id);
    const size = ui.theme.font_size;
    _ = ui.font.measure(opts.label, size);
    const track_h = 8.0;
    const row_h = ui.theme.row_h + 8;
    const r = ui.alloc(opts.w, row_h);

    ui.drawText(r.x, r.y, size, ui.theme.text_dim, opts.label);

    const track = Rect{ .x = r.x, .y = r.y + 16, .w = opts.w, .h = track_h };
    const st = ui.interact(i, track, false);
    var changed = false;
    if (st.active and ui.input.mouseDown(.left)) {
        const t = std.math.clamp((ui.input.mouse_x - track.x) / track.w, 0, 1);
        const nv = opts.min + t * (opts.max - opts.min);
        if (nv != opts.value.*) {
            opts.value.* = nv;
            changed = true;
        }
    }
    const t = if (opts.max > opts.min) (opts.value.* - opts.min) / (opts.max - opts.min) else 0;
    ui.drawRect(track, ui.theme.slider_track);
    ui.drawRect(.{ .x = track.x, .y = track.y, .w = track.w * t, .h = track.h }, ui.theme.slider_fill);
    const knob_x = track.x + track.w * t - 5;
    ui.drawRect(.{ .x = knob_x, .y = track.y - 4, .w = 10, .h = track_h + 8 }, if (st.hot or st.active) ui.theme.accent_hot else ui.theme.accent);

    var buf: [32]u8 = undefined;
    const val_s = std.fmt.bufPrint(&buf, "{d:.2}", .{opts.value.*}) catch "?";
    ui.drawText(track.x + track.w + 8, track.y - 2, size, ui.theme.text_dim, val_s);
    return changed;
}
