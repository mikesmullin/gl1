//! Circular(ish) avatar / user chip with initials.
const std = @import("std");
const types = @import("../types.zig");
const Color = types.Color;
const Rect = types.Rect;

pub fn avatar(ui: anytype, opts: anytype) void {
    const size: f32 = if (@hasField(@TypeOf(opts), "size")) opts.size else 32;
    const r = ui.alloc(size + 4, size + 4);
    const box = Rect{ .x = r.x, .y = r.y, .w = size, .h = size };
    const bg: Color = if (@hasField(@TypeOf(opts), "color")) opts.color else ui.theme.accent;
    ui.drawRectBorder(box, bg, ui.theme.panel_border, 1);
    const name: []const u8 = opts.name;
    var initials: [2]u8 = .{ '?', '?' };
    var ni: usize = 0;
    var sp = true;
    for (name) |ch| {
        if (ch == ' ') {
            sp = true;
            continue;
        }
        if (sp and ni < 2) {
            initials[ni] = std.ascii.toUpper(ch);
            ni += 1;
            sp = false;
        }
    }
    const label = initials[0..@max(ni, 1)];
    const m = ui.font.measure(label, ui.theme.font_size);
    // White initials on colored plate (bitmap font has no outline; white reads best).
    ui.drawText(box.x + (box.w - m.w) * 0.5, box.y + (box.h - m.h) * 0.5, ui.theme.font_size, .{ 1, 1, 1, 1 }, label);
    if (@hasField(@TypeOf(opts), "label") and opts.label.len > 0) {
        ui.drawText(box.x + size + 8, box.y + (size - m.h) * 0.5, ui.theme.font_size, ui.theme.text, opts.label);
    }
}

/// Avatar + name as a chip row.
pub fn userChip(ui: anytype, opts: anytype) void {
    const size: f32 = 22;
    const name: []const u8 = opts.name;
    const m = ui.font.measure(name, ui.theme.font_size);
    const r = ui.alloc(size + 12 + m.w, size + 6);
    const box = Rect{ .x = r.x + 2, .y = r.y + 2, .w = size, .h = size };
    const bg: Color = if (@hasField(@TypeOf(opts), "color")) opts.color else ui.theme.info;
    ui.drawRectBorder(r, .{ 0.14, 0.15, 0.18, 1 }, ui.theme.panel_border, 1);
    ui.drawRect(box, bg);
    var ini: [1]u8 = .{std.ascii.toUpper(if (name.len > 0) name[0] else '?')};
    const im = ui.font.measure(ini[0..], 1.5);
    ui.drawText(box.x + (box.w - im.w) * 0.5, box.y + 3, 1.5, .{ 1, 1, 1, 1 }, ini[0..]);
    ui.drawText(box.x + size + 6, r.y + 5, ui.theme.font_size, ui.theme.text, name);
}
