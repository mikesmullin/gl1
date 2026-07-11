const std = @import("std");
const app = @import("../app.zig");
const ui = @import("../ui/ui.zig");

pub const SceneKind = enum {
    storybook,
    triangle,
    rects,
    text,
    widgets_basic,
    panels,
    layout,
};

pub fn parse(name: []const u8) ?SceneKind {
    return std.meta.stringToEnum(SceneKind, name);
}

pub fn nameOf(k: SceneKind) []const u8 {
    return @tagName(k);
}

pub const all = [_]SceneKind{
    .storybook,
    .triangle,
    .rects,
    .text,
    .widgets_basic,
    .panels,
    .layout,
};

// ---------------------------------------------------------------------------
// Per-scene persistent state
// ---------------------------------------------------------------------------

pub const State = struct {
    // storybook
    selected: usize = 0,
    // widgets demos
    checked: bool = true,
    radio_group: u32 = 0,
    speed: f32 = 0.45,
    volume: f32 = 0.7,
    clicks: u32 = 0,
    text_buf: [64]u8 = undefined,
    text_len: usize = 0,
    progress: f32 = 0.35,
    spin: f32 = 0,

    pub fn init(self: *State) void {
        const hello = "hello gl1";
        @memcpy(self.text_buf[0..hello.len], hello);
        self.text_len = hello.len;
    }
};

// ---------------------------------------------------------------------------
// Scenes
// ---------------------------------------------------------------------------

pub fn frame(a: *app.App) void {
    switch (a.scene) {
        .triangle => frameTriangle(a),
        .rects => frameRects(a),
        .text => frameText(a),
        .widgets_basic => frameWidgets(a),
        .panels => framePanels(a),
        .layout => frameLayout(a),
        .storybook => frameStorybook(a),
    }
}

fn frameTriangle(a: *app.App) void {
    const sgl = @import("sokol").gl;
    const w = a.width;
    const h = a.height;
    const t: f32 = @floatCast(a.time);

    sgl.beginTriangles();
    sgl.v2fC3f(w * 0.5, h * 0.2, 1, 0.3 + 0.2 * @sin(t), 0.3);
    sgl.v2fC3f(w * 0.2, h * 0.8, 0.2, 0.6, 1);
    sgl.v2fC3f(w * 0.8, h * 0.8, 0.3, 1, 0.5);
    sgl.end();

    a.ui.drawText(16, 16, 2.0, a.ui.theme.text, "scene: triangle  (mouse moves ok)");
    var buf: [64]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "mouse {d:.0},{d:.0}", .{ a.input.mouse_x, a.input.mouse_y }) catch "";
    a.ui.drawText(16, 40, 2.0, a.ui.theme.text_dim, msg);
}

fn frameRects(a: *app.App) void {
    const u = &a.ui;
    const t: f32 = @floatCast(a.time);
    u.drawRect(u.place(40, 40, 120, 80), .{ 0.8, 0.3, 0.3, 1 });
    u.drawRect(u.place(180, 60, 100, 100), .{ 0.3, 0.7, 0.4, 0.9 });
    u.drawRect(u.place(300, 50 + 20 * @sin(t * 2), 140, 60), .{ 0.3, 0.4, 0.9, 1 });
    u.drawRectBorder(u.place(40, 200, 200, 100), .{ 0.15, 0.15, 0.18, 1 }, .{ 0.9, 0.8, 0.3, 1 }, 3);
    u.drawText(16, 16, 2.0, u.theme.text, "scene: rects");
}

fn frameText(a: *app.App) void {
    const u = &a.ui;
    u.drawText(16, 16, 2.0, u.theme.text, "scene: text — bitmap font atlas (Game9 glyphs-outline)");
    u.drawText(16, 48, 1.5, u.theme.text_dim, "ABCDEFGHIJKLMNOPQRSTUVWXYZ");
    u.drawText(16, 70, 1.5, u.theme.text_dim, "abcdefghijklmnopqrstuvwxyz");
    u.drawText(16, 92, 1.5, u.theme.text_dim, "0123456789 !@#$%^&*()_+-=");
    u.drawText(16, 130, 3.0, u.theme.accent, "Size 3.0 accent");
    u.drawText(16, 170, 4.0, .{ 1, 0.85, 0.4, 1 }, "Size 4.0");
    u.drawText(16, 220, 2.0, u.theme.text, "The quick brown fox jumps over the lazy dog.");
}

fn frameWidgets(a: *app.App) void {
    const u = &a.ui;
    const st = &a.scene_state;

    if (u.beginPanel(.{ .id = "widgets", .x = 24, .y = 24, .w = 360, .h = 420, .title = "widgets_basic" })) {
        defer u.endPanel();

        u.label(.{ .text = "Immediate-mode widgets (Style A)" });
        u.separator();

        if (u.button(.{ .id = "btn_click", .label = "Click me" })) {
            st.clicks +%= 1;
        }
        var buf: [48]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "clicks: {d}", .{st.clicks}) catch "";
        u.label(.{ .text = s, .color = u.theme.text_dim });

        _ = u.checkbox(.{ .id = "chk", .label = "Enable feature", .value = &st.checked });
        _ = u.slider(.{ .id = "speed", .label = "Speed", .value = &st.speed, .min = 0, .max = 1 });
        _ = u.slider(.{ .id = "vol", .label = "Volume", .value = &st.volume, .min = 0, .max = 1, .w = 240 });
        _ = u.textInput(.{ .id = "name", .label = "Name", .buf = &st.text_buf, .len = &st.text_len });
        u.progress(.{ .label = "Load", .value = st.progress });
        st.progress = @mod(st.progress + a.dt * 0.1, 1.0);
    }
}

fn framePanels(a: *app.App) void {
    const u = &a.ui;
    if (u.beginPanel(.{ .id = "p1", .x = 20, .y = 20, .w = 280, .h = 200, .title = "Panel A" })) {
        defer u.endPanel();
        u.label(.{ .text = "Nested content" });
        if (u.button(.{ .id = "a", .label = "Action A" })) {}
        u.label(.{ .text = "defer endPanel()", .color = u.theme.text_dim });
    }
    if (u.beginPanel(.{ .id = "p2", .x = 320, .y = 40, .w = 300, .h = 260, .title = "Panel B" })) {
        defer u.endPanel();
        u.label(.{ .text = "Second panel" });
        _ = u.checkbox(.{ .id = "bchk", .label = "Option", .value = &a.scene_state.checked });
        if (u.button(.{ .id = "b", .label = "Action B", .w = 120 })) {}
        u.separator();
        u.label(.{ .text = "Panels use begin/end + Zig defer.", .color = u.theme.text_dim });
    }
}

fn frameLayout(a: *app.App) void {
    const u = &a.ui;
    u.drawText(16, 12, 2.0, u.theme.text, "scene: layout — vstack / hstack");

    u.beginVStack(.{ .x = 40, .y = 50, .w = 400, .h = 400, .pad = 12, .gap = 8 });
    defer _ = u.endVStack();

    u.drawRectBorder(u.place(40, 50, 400, 400), .{ 0.12, 0.13, 0.16, 1 }, u.theme.panel_border, 1);

    // Re-open stack after background (place doesn't advance vstack — reset)
    // Simpler: draw widgets via alloc after begin
    u.label(.{ .text = "Vertical stack" });
    u.beginHStack(.{ .x = 52, .y = 100, .w = 376, .h = 40, .pad = 0, .gap = 8 });
    if (u.button(.{ .id = "l1", .label = "One", .w = 80 })) {}
    if (u.button(.{ .id = "l2", .label = "Two", .w = 80 })) {}
    if (u.button(.{ .id = "l3", .label = "Three", .w = 80 })) {}
    _ = u.endHStack();

    u.beginVStack(.{ .x = 52, .y = 160, .w = 376, .h = 200, .pad = 8, .gap = 6 });
    u.label(.{ .text = "Inner vstack" });
    _ = u.slider(.{ .id = "lay_s", .label = "Param", .value = &a.scene_state.speed });
    u.label(.{ .text = "padding + gap from theme", .color = u.theme.text_dim });
    _ = u.endVStack();
}

fn frameStorybook(a: *app.App) void {
    const u = &a.ui;
    const st = &a.scene_state;
    const sidebar_w: f32 = 200;
    const items = [_][]const u8{
        "Overview",
        "Button",
        "Checkbox",
        "Radio",
        "Slider",
        "TextInput",
        "Progress",
        "Panel",
        "Layout",
        "Theme",
    };

    // Sidebar
    u.drawRect(u.place(0, 0, sidebar_w, a.height), u.theme.sidebar);
    u.drawText(16, 16, 2.5, u.theme.accent, "gl1 storybook");
    u.drawText(16, 42, 1.5, u.theme.text_dim, "living widget gallery");

    var y: f32 = 70;
    for (items, 0..) |item, idx| {
        const r = u.place(8, y, sidebar_w - 16, 28);
        const i = u.id(item);
        const stt = u.interact(i, r, false);
        if (stt.clicked) st.selected = idx;
        const selected = st.selected == idx;
        if (selected) u.drawRect(r, u.theme.selected) else if (stt.hot) u.drawRect(r, u.theme.button_hot);
        u.drawText(r.x + 10, r.y + 6, 2.0, if (selected) u.theme.accent else u.theme.text, item);
        y += 32;
    }

    // Scene shortcuts
    u.drawText(16, a.height - 80, 1.5, u.theme.text_dim, "Ctrl+0 storybook");
    u.drawText(16, a.height - 62, 1.5, u.theme.text_dim, "Ctrl+1..6 scenes");
    u.drawText(16, a.height - 44, 1.5, u.theme.text_dim, "Esc quit  (type freely)");

    // Detail
    const dx = sidebar_w + 16;
    const dw = a.width - dx - 16;
    if (u.beginPanel(.{ .id = "detail", .x = dx, .y = 16, .w = dw, .h = a.height - 32, .title = items[st.selected] })) {
        defer u.endPanel();

        switch (st.selected) {
            0 => {
                u.label(.{ .text = "GL1 prototype — Zig + Sokol immediate UI" });
                u.label(.{ .text = "Style A: begin/end + defer. Dark theme.", .color = u.theme.text_dim });
                u.separator();
                u.label(.{ .text = "Launch: zig build run" });
                u.label(.{ .text = "Select scene: --scene storybook|triangle|..." });
                u.label(.{ .text = "Font: assets/fonts/glyphs-outline.bmp (Game9)" });
                u.separator();
                if (u.button(.{ .id = "go_tri", .label = "Open triangle scene" })) {
                    a.scene = .triangle;
                }
            },
            1 => {
                u.label(.{ .text = "Button — hover / active / click" });
                if (u.button(.{ .id = "sb_btn", .label = "Primary" })) st.clicks +%= 1;
                if (u.button(.{ .id = "sb_btn2", .label = "Wide button", .w = 180 })) st.clicks +%= 1;
                _ = u.button(.{ .id = "sb_dis", .label = "Disabled", .disabled = true });
                var buf: [32]u8 = undefined;
                u.label(.{ .text = std.fmt.bufPrint(&buf, "clicks={d}", .{st.clicks}) catch "", .color = u.theme.text_dim });
            },
            2 => {
                u.label(.{ .text = "Checkbox" });
                _ = u.checkbox(.{ .id = "sb_chk", .label = "Checked option", .value = &st.checked });
                u.label(.{ .text = if (st.checked) "state: true" else "state: false", .color = u.theme.text_dim });
            },
            3 => {
                u.label(.{ .text = "Radio group" });
                _ = u.radio(.{ .id = "r0", .label = "Option A", .group = &st.radio_group, .value = 0 });
                _ = u.radio(.{ .id = "r1", .label = "Option B", .group = &st.radio_group, .value = 1 });
                _ = u.radio(.{ .id = "r2", .label = "Option C", .group = &st.radio_group, .value = 2 });
                var rbuf: [24]u8 = undefined;
                u.label(.{ .text = std.fmt.bufPrint(&rbuf, "selected={d}", .{st.radio_group}) catch "", .color = u.theme.text_dim });
            },
            4 => {
                u.label(.{ .text = "Slider" });
                _ = u.slider(.{ .id = "sb_sp", .label = "Speed", .value = &st.speed });
                _ = u.slider(.{ .id = "sb_vo", .label = "Volume", .value = &st.volume, .min = 0, .max = 2 });
            },
            5 => {
                u.label(.{ .text = "Text input (focus + type; Ctrl+digit = scenes)" });
                _ = u.textInput(.{ .id = "sb_ti", .label = "Value", .buf = &st.text_buf, .len = &st.text_len, .w = 280 });
                u.label(.{ .text = st.text_buf[0..st.text_len], .color = u.theme.accent });
            },
            6 => {
                u.label(.{ .text = "Progress" });
                st.progress = @mod(st.progress + a.dt * 0.15, 1.0);
                u.progress(.{ .label = "Indeterminate loop", .value = st.progress, .w = 300 });
            },
            7 => {
                u.label(.{ .text = "Panel is this chrome — title bar + body." });
                u.label(.{ .text = "Use beginPanel / defer endPanel.", .color = u.theme.text_dim });
            },
            8 => {
                u.label(.{ .text = "Layout: vstack + hstack + padding/gap" });
                u.beginHStack(.{ .x = dx + 24, .y = 120, .w = dw - 48, .h = 40, .pad = 0, .gap = 8 });
                _ = u.button(.{ .id = "sb_h1", .label = "A", .w = 60 });
                _ = u.button(.{ .id = "sb_h2", .label = "B", .w = 60 });
                _ = u.button(.{ .id = "sb_h3", .label = "C", .w = 60 });
                _ = u.endHStack();
            },
            9 => {
                u.label(.{ .text = "Theme tokens (dark)" });
                const sw = 28.0;
                const colors = [_]ui.Color{ u.theme.bg, u.theme.panel, u.theme.accent, u.theme.button, u.theme.danger, u.theme.slider_fill };
                var cx: f32 = dx + 24;
                const cy: f32 = 110;
                for (colors) |c| {
                    u.drawRect(u.place(cx, cy, sw, sw), c);
                    cx += sw + 8;
                }
                u.label(.{ .text = "bg panel accent button danger fill", .color = u.theme.text_dim });
            },
            else => {},
        }
    }

}
