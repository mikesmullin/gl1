//! Sinebow color picker — looks like a Blender-style slider.
//! - Drag: scrub hue via d3-style sinebow interpolation; bar is a rainbow.
//! - Click (no drag): simple hex field — auto `#` prefix, max 6 digits, caret at end.
//! - Display: centered lowercase `#rrggbb`.

const std = @import("std");
const types = @import("../types.zig");
const Color = types.Color;
const Rect = types.Rect;
const Id = types.Id;
const sapp = @import("sokol").app;

/// Per-widget ephemeral state (keyed in Ui.color_picks).
pub const State = struct {
    /// Last sinebow parameter in [0, 1] used while scrubbing.
    t: f32 = 0.5,
    /// True while the user is typing a hex value.
    editing: bool = false,
    /// Hex digits only (no `#`), max 6, stored lowercase.
    hex: [6]u8 = undefined,
    hex_len: usize = 0,
    /// Mouse moved enough this press → treat as scrub, not click-to-edit.
    did_scrub: bool = false,
    /// Press is active on this widget (before scrub threshold).
    press_pending: bool = false,
};

/// d3-style sinebow: `t = 0.5 - t; rgb = sin(π (t + k/3))²`.
pub fn sinebow(t_in: f32) Color {
    const t = 0.5 - t_in;
    const pi = std.math.pi;
    const r = @sin(pi * (t + 0.0 / 3.0));
    const g = @sin(pi * (t + 1.0 / 3.0));
    const b = @sin(pi * (t + 2.0 / 3.0));
    return .{ r * r, g * g, b * b, 1 };
}

pub fn formatHex(color: Color, out: *[7]u8) []const u8 {
    const ri: u8 = @intFromFloat(std.math.clamp(color[0], 0, 1) * 255.0 + 0.5);
    const gi: u8 = @intFromFloat(std.math.clamp(color[1], 0, 1) * 255.0 + 0.5);
    const bi: u8 = @intFromFloat(std.math.clamp(color[2], 0, 1) * 255.0 + 0.5);
    return std.fmt.bufPrint(out, "#{x:0>2}{x:0>2}{x:0>2}", .{ ri, gi, bi }) catch "#000000";
}

fn hexVal(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

/// Parse 3 or 6 hex digits (no `#`) into RGB 0..1. Returns false if incomplete/invalid.
pub fn parseHexDigits(digits: []const u8, out: *Color) bool {
    if (digits.len == 3) {
        const r = hexVal(digits[0]) orelse return false;
        const g = hexVal(digits[1]) orelse return false;
        const b = hexVal(digits[2]) orelse return false;
        out.* = .{
            @as(f32, @floatFromInt(r * 17)) / 255.0,
            @as(f32, @floatFromInt(g * 17)) / 255.0,
            @as(f32, @floatFromInt(b * 17)) / 255.0,
            1,
        };
        return true;
    }
    if (digits.len == 6) {
        const r0 = hexVal(digits[0]) orelse return false;
        const r1 = hexVal(digits[1]) orelse return false;
        const g0 = hexVal(digits[2]) orelse return false;
        const g1 = hexVal(digits[3]) orelse return false;
        const b0 = hexVal(digits[4]) orelse return false;
        const b1 = hexVal(digits[5]) orelse return false;
        out.* = .{
            @as(f32, @floatFromInt(r0 * 16 + r1)) / 255.0,
            @as(f32, @floatFromInt(g0 * 16 + g1)) / 255.0,
            @as(f32, @floatFromInt(b0 * 16 + b1)) / 255.0,
            1,
        };
        return true;
    }
    return false;
}

fn toLowerHex(c: u8) u8 {
    if (c >= 'A' and c <= 'F') return c + 32;
    return c;
}

fn fillHexFromColor(st: *State, color: Color) void {
    var buf: [7]u8 = undefined;
    const s = formatHex(color, &buf);
    if (s.len >= 7) {
        @memcpy(st.hex[0..6], s[1..7]);
        st.hex_len = 6;
    } else {
        st.hex_len = 0;
    }
}

fn applyHexLive(st: *const State, color: *Color) bool {
    if (st.hex_len == 3 or st.hex_len == 6) {
        return parseHexDigits(st.hex[0..st.hex_len], color);
    }
    return false;
}

fn beginScrub(ui: anytype, i: Id, cp: *State) void {
    if (ui.drag.eq(i)) return;
    ui.drag = i;
    ui.drag_value0 = cp.t;
    ui.drag_anchor = 0;
    ui.mouse_captured_for_drag = true;
    sapp.lockMouse(true);
    sapp.showMouse(false);
}

fn endScrubCapture(ui: anytype) void {
    if (ui.mouse_captured_for_drag) {
        ui.mouse_captured_for_drag = false;
        sapp.lockMouse(false);
        if (!ui.soft_pointer) sapp.showMouse(true);
    }
}

pub fn colorPicker(ui: anytype, opts: anytype) bool {
    const i = ui.id(opts.id);
    const size = ui.theme.font_size;
    const row_h = ui.theme.row_h;
    const r = ui.alloc(opts.w, row_h);

    const gap: f32 = 8;
    const label_m = ui.font.measure(opts.label, size);
    const label_w = @min(@max(label_m.w + 4, 48), opts.w * 0.40);
    ui.drawText(r.x, r.y + (row_h - ui.font.lineHeight(size)) * 0.5, size, ui.theme.text_dim, opts.label);

    const bar = Rect{
        .x = r.x + label_w + gap,
        .y = r.y + 2,
        .w = @max(40, r.w - label_w - gap),
        .h = row_h - 4,
    };

    const st_ui = ui.interact(i, bar, false);
    const cp = ui.colorPickState(i.a);
    var changed = false;

    const override: ?[]const u8 = if (@hasField(@TypeOf(opts), "display_override")) opts.display_override else null;
    const disabled_edit = override != null;

    // --- Press / scrub / click-to-edit ---
    // Do NOT lock the mouse until scrub is confirmed — lock noise was flipping
    // did_scrub and blocking hex edit.
    if (!cp.editing and st_ui.hot and ui.input.mousePressed(.left) and ui.drag.isNone()) {
        cp.press_pending = true;
        cp.did_scrub = false;
        ui.drag_anchor = 0;
        ui.drag_value0 = cp.t;
    }

    if (cp.press_pending and ui.input.mouseDown(.left)) {
        ui.drag_anchor += ui.input.mouse_dx;
        if (@abs(ui.drag_anchor) > 3) {
            if (!cp.did_scrub) {
                cp.did_scrub = true;
                beginScrub(ui, i, cp);
                // Reset anchor so scrub starts from current t cleanly.
                ui.drag_anchor = 0;
            }
        }
        if (cp.did_scrub and ui.drag.eq(i)) {
            const nt = std.math.clamp(ui.drag_value0 + ui.drag_anchor / bar.w, 0, 1);
            if (nt != cp.t) {
                cp.t = nt;
                opts.color.* = sinebow(cp.t);
                changed = true;
            }
        }
    }

    if (cp.press_pending and ui.input.mouseReleased(.left)) {
        const was_scrub = cp.did_scrub;
        cp.press_pending = false;
        if (ui.drag.eq(i)) ui.drag = .{};
        endScrubCapture(ui);
        if (!was_scrub and !disabled_edit) {
            cp.editing = true;
            fillHexFromColor(cp, opts.color.*);
            ui.focus = i;
        }
        cp.did_scrub = false;
    }

    // Safety: if focus lost while editing, commit.
    if (cp.editing and !ui.focus.eq(i) and !cp.press_pending) {
        cp.editing = false;
    }

    if (st_ui.hot and !cp.did_scrub and !cp.editing) {
        ui.setSoftCursor(.cursor_hand_open);
    }

    // --- Hex edit mode (caret always at end; `#` is display-only prefix) ---
    if (cp.editing) {
        ui.focus = i;
        ui.setSoftCursor(.cursor_text);

        // Backspace removes last digit (never the `#`).
        if (ui.input.keyPressed(.backspace) and cp.hex_len > 0) {
            cp.hex_len -= 1;
            _ = applyHexLive(cp, opts.color);
            changed = true;
        }

        // Append hex digits only; max 6; ignore `#` and non-hex.
        var ti: usize = 0;
        while (ti < ui.input.text_len) : (ti += 1) {
            const ch = ui.input.text[ti];
            if (ch == '#') continue;
            if (hexVal(ch) == null) continue;
            if (cp.hex_len >= 6) continue;
            cp.hex[cp.hex_len] = toLowerHex(ch);
            cp.hex_len += 1;
            if (applyHexLive(cp, opts.color)) changed = true;
        }
        if (ui.input.text_len > 0) ui.input.text_len = 0;

        if (ui.input.keyPressed(.enter)) {
            cp.editing = false;
        }
        if (ui.input.keyPressed(.escape)) {
            cp.editing = false;
            ui.consumed_escape = true;
        }

        // Click outside → leave edit. Click on bar while editing: if scrub,
        // exit edit; simple click stays in edit (re-select field).
        if (ui.input.mousePressed(.left) and !bar.contains(ui.input.mouse_x, ui.input.mouse_y)) {
            cp.editing = false;
        }
    }

    // --- Draw track: solid chosen color by default; rainbow only while scrub-dragging ---
    const scrubbing = cp.did_scrub and (ui.drag.eq(i) or ui.input.mouseDown(.left));
    const border = if (st_ui.hot or st_ui.active or scrubbing or cp.editing) ui.theme.accent else ui.theme.panel_border;
    const solid: Color = if (override != null)
        ui.theme.input_bg
    else
        opts.color.*;
    ui.drawRectBorder(bar, if (scrubbing) ui.theme.input_bg else solid, border, 1);
    const inner = Rect{ .x = bar.x + 1, .y = bar.y + 1, .w = bar.w - 2, .h = bar.h - 2 };
    if (scrubbing) {
        const segs: i32 = @intFromFloat(@max(8, @min(inner.w, 64)));
        var s: i32 = 0;
        while (s < segs) : (s += 1) {
            const t0 = @as(f32, @floatFromInt(s)) / @as(f32, @floatFromInt(segs));
            const col = sinebow(t0);
            const x0 = inner.x + @as(f32, @floatFromInt(s)) * inner.w / @as(f32, @floatFromInt(segs));
            const x1 = inner.x + @as(f32, @floatFromInt(s + 1)) * inner.w / @as(f32, @floatFromInt(segs));
            ui.drawRect(.{ .x = x0, .y = inner.y, .w = @max(1, x1 - x0), .h = inner.h }, col);
        }
        // Hue position tick while scrubbing.
        const tick_x = inner.x + cp.t * inner.w;
        ui.drawRect(.{ .x = tick_x - 1, .y = inner.y, .w = 2, .h = inner.h }, .{ 1, 1, 1, 0.85 });
    }

    // Centered hex value — glyphs already have a 1px outline; no plate behind text.
    var hex_buf: [8]u8 = undefined;
    const val_s: []const u8 = blk: {
        if (override) |o| break :blk o;
        if (cp.editing) {
            hex_buf[0] = '#';
            if (cp.hex_len > 0) @memcpy(hex_buf[1 .. 1 + cp.hex_len], cp.hex[0..cp.hex_len]);
            break :blk hex_buf[0 .. 1 + cp.hex_len];
        }
        break :blk formatHex(opts.color.*, hex_buf[0..7]);
    };
    const vm = ui.font.measure(val_s, size);
    const lh = ui.font.lineHeight(size);
    const tx = bar.x + (bar.w - vm.w) * 0.5;
    const ty = bar.y + (bar.h - lh) * 0.5;
    ui.drawText(tx, ty, size, ui.theme.text, val_s);

    // Blinking caret always at end of the digit run (after last char / after `#` if empty).
    if (cp.editing) {
        const blink_on = @mod(@as(i64, @intFromFloat(ui.time * 2.2)), 2) == 0;
        if (blink_on) {
            ui.drawRect(.{ .x = tx + vm.w + 1, .y = ty, .w = 2, .h = lh }, ui.theme.text);
        }
    }

    return changed;
}
