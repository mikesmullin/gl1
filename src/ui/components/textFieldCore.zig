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

    // Content width inside padding (6px left + ~6px right). Soft wrap is display-only.
    const wrap_px: f32 = if (opts.multiline) @max(0, box.w - 12) else 0;

    // Refresh modifiers every interaction — mouse events often omit Alt on Linux.
    ui.input.refreshModifiers();
    const alt = ui.input.alt;
    const shift = ui.input.shift;
    const ctrl = ui.input.ctrl;
    const middle_down = ui.input.mouseDown(.middle);
    const left_press = ui.input.mousePressed(.left);
    const mid_press = ui.input.mousePressed(.middle);
    const over = box.contains(ui.input.mouse_x, ui.input.mouse_y);

    // Only on press — never on release (`st.clicked`), so multi-click counting stays correct.
    // Middle-click also starts a block selection on multi-line (no modifiers needed).
    if ((left_press or mid_press) and over) {
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
            wrap_px,
            ui.time,
            alt,
            shift,
            ctrl,
            mid_press or (middle_down and left_press),
        );
    }
    const focused = ui.focus.a == opts.id_key;
    // I-beam over text content (single-line and multi-line).
    if (st.hot or focused) ui.setSoftCursor(.cursor_text);
    const dragging_btn = ui.input.mouseDown(.left) or ui.input.mouseDown(.middle);
    if (focused and dragging_btn and ed.dragging) {
        const ox = box.x + 6;
        const oy = box.y + 4 - opts.scroll_y;
        te.handleMouseDrag(
            ed,
            opts.buf[0..opts.len.*],
            ui.font,
            opts.size,
            ox,
            oy,
            ui.input.mouse_x,
            ui.input.mouse_y,
            opts.multiline,
            wrap_px,
            alt,
            shift,
            ctrl,
            middle_down,
        );
    }
    if (ui.input.mouseReleased(.left) or ui.input.mouseReleased(.middle)) te.handleMouseUp(ed);

    ui.drawRectBorder(box, ui.theme.input_bg, if (focused) ui.theme.accent else ui.theme.panel_border, 1);

    var changed = false;
    if (focused) {
        // Esc ending a Ctrl+D / multi-caret session should not also clear focus.
        if (ui.input.keyPressed(.escape) and (ed.ctrl_d_active or ed.caret_ct > 1)) {
            ui.consumed_escape = true;
        }
        // Tab indent (multi-line) must mark the UI so global Tab focus doesn't steal it.
        if (opts.multiline and ui.input.keyPressed(.tab) and !ui.input.ctrl and !ui.input.alt) {
            ui.consumed_tab = true;
        }
        changed = te.handleKeys(
            ed,
            opts.buf,
            opts.len,
            ui.input,
            opts.multiline,
            wrap_px,
            ui.font,
            opts.size,
        );
    }

    ui.cmds.push(.{ .scissor_push = .{ .x = box.x + 1, .y = box.y + 1, .w = box.w - 2, .h = box.h - 2 } });
    const origin_x = box.x + 6;
    const origin_y = box.y + 4 - opts.scroll_y;
    const lh = ui.font.lineHeight(opts.size);
    const text = opts.buf[0..opts.len.*];

    var rows_buf: [te.MaxSoftRows]te.VisualRow = undefined;
    const nrows = te.layoutSoft(text, ui.font, opts.size, wrap_px, rows_buf[0..]);
    const rows = rows_buf[0..nrows];

    // selection highlight(s) — per soft visual row
    var ci: usize = 0;
    while (ci < ed.caret_ct) : (ci += 1) {
        const rg = ed.carets[ci];
        if (!rg.hasSel()) continue;
        const sel_lo = rg.lo();
        const sel_hi = rg.hi();
        var sri: usize = 0;
        while (sri < rows.len) : (sri += 1) {
            const vr = rows[sri];
            if (vr.end <= sel_lo or vr.start >= sel_hi) continue;
            const seg_lo = @max(sel_lo, vr.start);
            const seg_hi = @min(sel_hi, vr.end);
            if (seg_lo >= seg_hi) continue;
            const pre = text[vr.start..seg_lo];
            const mid = text[seg_lo..seg_hi];
            const x0 = origin_x + ui.font.measure(pre, opts.size).w;
            const w = ui.font.measure(mid, opts.size).w;
            const y0 = origin_y + @as(f32, @floatFromInt(sri)) * lh;
            ui.drawRect(.{ .x = x0, .y = y0, .w = @max(w, 2), .h = lh }, .{ 0.25, 0.45, 0.35, 0.55 });
        }
    }

    // text: one draw per soft visual row
    var ri: usize = 0;
    while (ri < rows.len) : (ri += 1) {
        const vr = rows[ri];
        const line = text[vr.start..vr.end];
        const ly = origin_y + @as(f32, @floatFromInt(ri)) * lh;
        ui.drawText(origin_x, ly, opts.size, ui.theme.text, line);
    }

    // carets
    if (focused and @mod(@as(i64, @intFromFloat(ui.time * 2)), 2) == 0) {
        ci = 0;
        while (ci < ed.caret_ct) : (ci += 1) {
            const cpos = ed.carets[ci].caret;
            const cp = te.caretDrawPos(text, ui.font, opts.size, cpos, rows);
            const cx = origin_x + cp.x;
            const cy = origin_y + @as(f32, @floatFromInt(cp.row)) * lh;
            ui.drawRect(.{ .x = cx, .y = cy, .w = 2, .h = lh }, ui.theme.text);
        }
    }
    ui.cmds.push(.{ .scissor_pop = {} });
    return changed;
}
