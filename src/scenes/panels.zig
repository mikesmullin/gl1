//! Panels scene — lightweight “desktop”: floating windows + macOS-style dock.
//! Drag title bar to move, bottom-right triangle to resize; dock toggles windows
//! while remembering x/y/w/h between open/close.
const std = @import("std");
const app = @import("../app.zig");
const ui = @import("../ui/ui.zig");
const state = @import("state.zig");

const grip: f32 = 14;
const dock_h: f32 = 64;
const dock_pad: f32 = 10;
const icon: f32 = 44;

const WinDef = struct {
    key: []const u8,
    title: []const u8,
    dock_label: []const u8,
    color: ui.Color,
};

const win_defs = [_]WinDef{
    .{ .key = "desk_a", .title = "Panel A", .dock_label = "A", .color = .{ 0.35, 0.75, 0.45, 1 } },
    .{ .key = "desk_b", .title = "Panel B", .dock_label = "B", .color = .{ 0.40, 0.60, 0.95, 1 } },
    .{ .key = "desk_c", .title = "Notes", .dock_label = "N", .color = .{ 0.90, 0.70, 0.30, 1 } },
};

fn winPtr(st: *state.State, idx: usize) *state.DeskWin {
    return switch (idx) {
        0 => &st.desk_a,
        1 => &st.desk_b,
        else => &st.desk_c,
    };
}

fn drawTriangleGrip(u: anytype, gr: ui.Rect, color: ui.Color) void {
    var row: f32 = 0;
    while (row < gr.h) : (row += 1) {
        const t = if (gr.h > 1) row / (gr.h - 1) else 1;
        const ww = @max(1, gr.w * t);
        u.drawRect(.{ .x = gr.x + gr.w - ww, .y = gr.y + row, .w = ww, .h = 1 }, color);
    }
}

fn clampWin(win: *state.DeskWin, screen_w: f32, screen_h: f32) void {
    win.w = std.math.clamp(win.w, 180, screen_w - 20);
    win.h = std.math.clamp(win.h, 120, screen_h - dock_h - 40);
    win.x = std.math.clamp(win.x, 0, @max(0, screen_w - win.w));
    win.y = std.math.clamp(win.y, 0, @max(0, screen_h - dock_h - win.h - 8));
}

fn handleChrome(u: anytype, st: *state.State, idx: i32, win: *state.DeskWin, title_h: f32) void {
    const title = ui.Rect{ .x = win.x, .y = win.y, .w = win.w, .h = title_h };
    const gr = ui.Rect{ .x = win.x + win.w - grip, .y = win.y + win.h - grip, .w = grip, .h = grip };

    // Resize grip (priority over title when overlapping corner)
    var gid_buf: [24]u8 = undefined;
    const gid = std.fmt.bufPrint(&gid_buf, "desk_rg{d}", .{idx}) catch "desk_rg";
    const gst = u.interact(u.id(gid), gr, false);
    if (gst.hot and u.input.mousePressed(.left)) {
        st.desk_resize = idx;
        st.desk_resize_sw = win.w;
        st.desk_resize_sh = win.h;
        st.desk_drag_ox = u.input.mouse_x;
        st.desk_drag_oy = u.input.mouse_y;
        st.desk_drag = -1;
    }

    var tid_buf: [24]u8 = undefined;
    const tid = std.fmt.bufPrint(&tid_buf, "desk_tb{d}", .{idx}) catch "desk_tb";
    const tst = u.interact(u.id(tid), title, false);
    if (tst.hot and u.input.mousePressed(.left) and st.desk_resize < 0) {
        st.desk_drag = idx;
        st.desk_drag_ox = u.input.mouse_x - win.x;
        st.desk_drag_oy = u.input.mouse_y - win.y;
    }

    if (st.desk_drag == idx and u.input.mouseDown(.left)) {
        win.x = u.input.mouse_x - st.desk_drag_ox;
        win.y = u.input.mouse_y - st.desk_drag_oy;
        clampWin(win, u.width, u.height);
    }
    if (st.desk_resize == idx and u.input.mouseDown(.left)) {
        win.w = st.desk_resize_sw + (u.input.mouse_x - st.desk_drag_ox);
        win.h = st.desk_resize_sh + (u.input.mouse_y - st.desk_drag_oy);
        clampWin(win, u.width, u.height);
    }
    if (u.input.mouseReleased(.left)) {
        if (st.desk_drag == idx) st.desk_drag = -1;
        if (st.desk_resize == idx) st.desk_resize = -1;
    }
}

pub fn frame(a: *app.App) void {
    const u = &a.ui;
    const st = &a.scene_state;
    const title_h = u.theme.row_h;

    // Desktop wallpaper
    u.drawRect(.{ .x = 0, .y = 0, .w = u.width, .h = u.height }, .{ 0.12, 0.16, 0.22, 1 });
    // subtle vignette bars
    u.drawRect(.{ .x = 0, .y = 0, .w = u.width, .h = 36 }, .{ 0.08, 0.10, 0.14, 0.55 });
    u.drawText(16, 10, 2.0, u.theme.text, "Desktop");
    u.drawText(100, 12, 1.5, u.theme.text_dim, "drag title bars · resize corner · dock toggles windows");

    // Draw open windows (back to front: A, B, C)
    var wi: usize = 0;
    while (wi < win_defs.len) : (wi += 1) {
        const def = win_defs[wi];
        const win = winPtr(st, wi);
        if (!win.open) continue;
        clampWin(win, u.width, u.height);
        handleChrome(u, st, @intCast(wi), win, title_h);

        if (u.beginPanel(.{
            .id = def.key,
            .x = win.x,
            .y = win.y,
            .w = win.w,
            .h = win.h,
            .title = def.title,
            .scroll = true,
        })) {
            defer u.endPanel();
            switch (wi) {
                0 => {
                    u.label(.{ .text = "Nested content" });
                    if (u.button(.{ .id = "a_act", .label = "Action A" })) u.toast("Panel A action", .ok, 1.2);
                    u.label(.{ .text = "defer endPanel()", .color = u.theme.text_dim });
                    u.separator();
                    u.label(.{ .text = "Panels use begin/end + Zig defer.", .color = u.theme.text_dim });
                },
                1 => {
                    u.label(.{ .text = "Second window" });
                    _ = u.checkbox(.{ .id = "bchk", .label = "Option", .value = &st.checked });
                    if (u.button(.{ .id = "b_act", .label = "Action B", .w = 120 })) u.log("panel B");
                    u.separator();
                    _ = u.slider(.{ .id = "b_s", .label = "Value", .value = &st.speed, .min = 0, .max = 1, .w = win.w - 24 });
                },
                else => {
                    u.label(.{ .text = "Sticky notes" });
                    u.label(.{ .text = "Position & size persist while you toggle via the dock.", .color = u.theme.text_dim });
                    u.separator();
                    if (u.button(.{ .id = "c_close", .label = "Close" })) win.open = false;
                },
            }
        }
        // Resize triangle on top of panel chrome
        const gr = ui.Rect{ .x = win.x + win.w - grip, .y = win.y + win.h - grip, .w = grip, .h = grip };
        const gcol = if (st.desk_resize == @as(i32, @intCast(wi))) u.theme.accent else def.color;
        drawTriangleGrip(u, gr, gcol);
    }

    // --- Dock (bottom center) ---
    const n: f32 = @floatFromInt(win_defs.len);
    const dock_w = n * (icon + dock_pad) + dock_pad;
    const dock_x = (u.width - dock_w) * 0.5;
    const dock_y = u.height - dock_h - 12;
    u.drawRectBorder(.{
        .x = dock_x,
        .y = dock_y,
        .w = dock_w,
        .h = dock_h,
    }, .{ 0.14, 0.15, 0.18, 0.92 }, u.theme.panel_border, 1);

    for (win_defs, 0..) |def, i| {
        const win = winPtr(st, i);
        const ix = dock_x + dock_pad + @as(f32, @floatFromInt(i)) * (icon + dock_pad);
        const iy = dock_y + (dock_h - icon) * 0.5;
        const ir = ui.Rect{ .x = ix, .y = iy, .w = icon, .h = icon };
        var idb: [16]u8 = undefined;
        const id = std.fmt.bufPrint(&idb, "dock{d}", .{i}) catch "dock";
        const stt = u.interact(u.id(id), ir, false);
        const bg: ui.Color = if (stt.hot) u.theme.button_hot else u.theme.button;
        u.drawRectBorder(ir, bg, if (win.open) def.color else u.theme.panel_border, if (win.open) 2 else 1);
        const lm = u.font.measure(def.dock_label, 2.5);
        u.drawText(ix + (icon - lm.w) * 0.5, iy + 10, 2.5, def.color, def.dock_label);
        // Indicator dot when open
        if (win.open) {
            u.drawRect(.{ .x = ix + icon * 0.5 - 3, .y = dock_y + dock_h - 10, .w = 6, .h = 6 }, def.color);
        }
        if (stt.clicked) {
            win.open = !win.open;
            // Re-show brings to front visually by drawing order — C last; for A/B we just toggle.
            if (win.open) clampWin(win, u.width, u.height);
        }
    }
}
