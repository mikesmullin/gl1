//! Reusable UI component.
const std = @import("std");
const types = @import("../types.zig");
const te = @import("../text_edit.zig");
const Color = types.Color;
const Rect = types.Rect;
const Id = types.Id;

pub fn textFieldCore(ui: anytype, opts: anytype) bool {
    const box = opts.box;
    const i = Id{ .a = opts.id_key, .b = 0 };
    const st = ui.interact(i, box, false);
    const ed = ui.editState(opts.id_key);
    ed.clampAll(opts.len.*);

    // Only on press — never on release (`st.clicked`), so multi-click counting stays correct.
    if (ui.input.mousePressed(.left) and box.contains(ui.input.mouse_x, ui.input.mouse_y)) {
        ui.focus = i;
        const ox = box.x + 6;
        const oy = box.y + 4 - opts.scroll_y;
        te.handleMouseDown(
            ed,
            opts.buf[0..opts.len.*],
            ui.font,
            opts.size,
            ox,
            oy,
            ui.input.mouse_x,
            ui.input.mouse_y,
            opts.multiline,
            ui.time,
            ui.input.alt,
            ui.input.shift,
        );
    }
    const focused = ui.focus.a == opts.id_key;
    _ = st; // hit-test still registered for hot/active
    if (focused and ui.input.mouseDown(.left) and ed.dragging) {
        const ox = box.x + 6;
        const oy = box.y + 4 - opts.scroll_y;
        te.handleMouseDrag(ed, opts.buf[0..opts.len.*], ui.font, opts.size, ox, oy, ui.input.mouse_x, ui.input.mouse_y, opts.multiline);
    }
    if (ui.input.mouseReleased(.left)) te.handleMouseUp(ed);

    ui.drawRectBorder(box, ui.theme.input_bg, if (focused) ui.theme.accent else ui.theme.panel_border, 1);

    var changed = false;
    if (focused) {
        changed = te.handleKeys(ed, opts.buf, opts.len, ui.input, opts.multiline);
    }

    ui.cmds.push(.{ .scissor_push = .{ .x = box.x + 1, .y = box.y + 1, .w = box.w - 2, .h = box.h - 2 } });
    const origin_x = box.x + 6;
    const origin_y = box.y + 4 - opts.scroll_y;
    const lh = ui.font.lineHeight(opts.size);
    const text = opts.buf[0..opts.len.*];

    // selection highlight(s)
    var ci: usize = 0;
    while (ci < ed.caret_ct) : (ci += 1) {
        const rg = ed.carets[ci];
        if (!rg.hasSel()) continue;
        // draw per-line selection
        var p = rg.lo();
        const hi = rg.hi();
        while (p < hi) {
            const ls = te.lineStart(text, p);
            const le = te.lineEnd(text, p);
            const seg_lo = @max(p, ls);
            const seg_hi = @min(hi, le);
            const row = te.rowOf(text, seg_lo);
            const pre = text[ls..seg_lo];
            const mid = text[seg_lo..seg_hi];
            const x0 = origin_x + ui.font.measure(pre, opts.size).w;
            const w = ui.font.measure(mid, opts.size).w;
            const y0 = origin_y + @as(f32, @floatFromInt(row)) * lh;
            ui.drawRect(.{ .x = x0, .y = y0, .w = @max(w, 2), .h = lh }, .{ 0.25, 0.45, 0.35, 0.55 });
            if (seg_hi >= le and hi > le) {
                p = le + 1;
            } else break;
        }
    }

    // text lines
    var line_start: usize = 0;
    var li: usize = 0;
    var line_i: usize = 0;
    while (li <= text.len) : (li += 1) {
        if (li == text.len or text[li] == '\n') {
            const line = text[line_start..li];
            const ly = origin_y + @as(f32, @floatFromInt(line_i)) * lh;
            ui.drawText(origin_x, ly, opts.size, ui.theme.text, line);
            line_i += 1;
            line_start = li + 1;
        }
    }

    // carets
    if (focused and @mod(@as(i64, @intFromFloat(ui.time * 2)), 2) == 0) {
        ci = 0;
        while (ci < ed.caret_ct) : (ci += 1) {
            const cpos = ed.carets[ci].caret;
            const row = te.rowOf(text, cpos);
            const ls = te.lineStart(text, cpos);
            const pre = text[ls..cpos];
            const cx = origin_x + ui.font.measure(pre, opts.size).w;
            const cy = origin_y + @as(f32, @floatFromInt(row)) * lh;
            ui.drawRect(.{ .x = cx, .y = cy, .w = 2, .h = lh }, ui.theme.text);
        }
    }
    ui.cmds.push(.{ .scissor_pop = {} });
    return changed;
}
