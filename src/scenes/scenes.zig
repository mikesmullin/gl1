const std = @import("std");
const app = @import("../app.zig");
const ui = @import("../ui/ui.zig");
const theme_mod = @import("../ui/theme.zig");

fn containsIgnoreCase(hay: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > hay.len) return false;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        var ok = true;
        for (needle, 0..) |nc, j| {
            const hc = hay[i + j];
            const a = if (nc >= 'A' and nc <= 'Z') nc + 32 else nc;
            const b = if (hc >= 'A' and hc <= 'Z') hc + 32 else hc;
            if (a != b) {
                ok = false;
                break;
            }
        }
        if (ok) return true;
    }
    return false;
}

pub const SceneKind = enum {
    storybook,
    triangle,
    rects,
    text,
    widgets_basic,
    panels,
    layout,
    inspector,
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
    .inspector,
};

// ---------------------------------------------------------------------------
// Per-scene persistent state
// ---------------------------------------------------------------------------

pub const State = struct {
    selected: usize = 0,
    checked: bool = true,
    toggled: bool = false,
    radio_group: u32 = 0,
    speed: f32 = 0.45,
    volume: f32 = 0.7,
    clicks: u32 = 0,
    text_buf: [64]u8 = undefined,
    text_len: usize = 0,
    progress: f32 = 0.35,
    spin: f32 = 0,
    dropdown_sel: usize = 0,
    dropdown_open: bool = false,
    tab_sel: usize = 0,
    modal_open: bool = false,
    collab_a: bool = true,
    collab_b: bool = false,
    list_sel: usize = 1,
    spinner_val: f32 = 12,
    theme_cool: bool = false,
    color_idx: usize = 0,
    tree_open: bool = true,
    entity_name: [32]u8 = undefined,
    entity_name_len: usize = 0,
    entity_hp: f32 = 80,
    entity_visible: bool = true,
    /// Left pane width (inspector splitter).
    split_w: f32 = 220,
    filter_buf: [32]u8 = undefined,
    filter_len: usize = 0,
    confirm_delete: bool = false,
    world_open: bool = true,
    npcs_open: bool = true,

    pub fn init(self: *State) void {
        const hello = "hello gl1";
        @memcpy(self.text_buf[0..hello.len], hello);
        self.text_len = hello.len;
        const en = "Hero";
        @memcpy(self.entity_name[0..en.len], en);
        self.entity_name_len = en.len;
    }
};

// ---------------------------------------------------------------------------
// Scenes
// ---------------------------------------------------------------------------

pub fn frame(a: *app.App) void {
    // Apply theme variant.
    a.ui.theme = if (a.scene_state.theme_cool) theme_mod.dark_cool else theme_mod.dark;

    switch (a.scene) {
        .triangle => frameTriangle(a),
        .rects => frameRects(a),
        .text => frameText(a),
        .widgets_basic => frameWidgets(a),
        .panels => framePanels(a),
        .layout => frameLayout(a),
        .inspector => frameInspector(a),
        .storybook => frameStorybook(a),
    }

    drawHud(a);
}

fn drawHud(a: *app.App) void {
    const u = &a.ui;
    // FPS / scene strip (top-right, non-interactive chrome).
    var buf: [64]u8 = undefined;
    const fps = if (a.dt > 0) 1.0 / a.dt else 0;
    const msg = std.fmt.bufPrint(&buf, "{s}  {d:.0} fps", .{ nameOf(a.scene), fps }) catch "";
    const m = u.font.measure(msg, 1.5);
    u.drawText(a.width - m.w - 10, 8, 1.5, u.theme.text_dim, msg);
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
    u.drawText(16, 16, 2.0, u.theme.text, "scene: text — bitmap font atlas (magenta = transparent)");
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

    if (u.beginPanel(.{ .id = "widgets", .x = 24, .y = 24, .w = 380, .h = 480, .title = "widgets_basic" })) {
        defer u.endPanel();

        u.label(.{ .text = "Immediate-mode widgets (Style A)" });
        u.separator();

        if (u.button(.{ .id = "btn_click", .label = "Click me" })) {
            st.clicks +%= 1;
            u.toast("Button clicked", .ok, 1.5);
        }
        var buf: [48]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "clicks: {d}", .{st.clicks}) catch "";
        u.label(.{ .text = s, .color = u.theme.text_dim });

        _ = u.checkbox(.{ .id = "chk", .label = "Enable feature", .value = &st.checked });
        _ = u.toggle(.{ .id = "togw", .label = "Turbo", .value = &st.toggled });
        _ = u.slider(.{ .id = "speed", .label = "Speed", .value = &st.speed, .min = 0, .max = 1 });
        _ = u.spinner(.{ .id = "spin", .label = "Count", .value = &st.spinner_val, .min = 0, .max = 100, .step = 1 });
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

fn frameInspector(a: *app.App) void {
    const u = &a.ui;
    const st = &a.scene_state;

    // Menubar
    _ = u.beginMenubar(.{});
    if (u.menuItem(.{ .id = "m_file", .label = "File" })) u.toast("File menu (stub)", .info, 1.2);
    if (u.menuItem(.{ .id = "m_edit", .label = "Edit" })) u.toast("Edit menu (stub)", .info, 1.2);
    if (u.menuItem(.{ .id = "m_view", .label = "View" })) u.toast("View menu (stub)", .info, 1.2);
    if (u.menuItem(.{ .id = "m_help", .label = "Help" })) {
        st.modal_open = true;
    }
    u.endMenubar();

    const top = u.theme.menubar_h;
    const bot = u.theme.statusbar_h;
    const body_h = a.height - top - bot;
    const margin: f32 = 8;
    const max_split = a.width - 280;
    st.split_w = std.math.clamp(st.split_w, 160, @max(160, max_split));

    const left_x = margin;
    const left_y = top + margin;
    const left_w = st.split_w;
    const left_h = body_h - margin * 2;
    const right_x = left_x + left_w + 6;
    const right_w = a.width - right_x - margin;

    // Left: entity list + filter + tree
    if (u.beginPanel(.{ .id = "ents", .x = left_x, .y = left_y, .w = left_w, .h = left_h, .title = "Entities" })) {
        defer u.endPanel();

        _ = u.searchField(.{
            .id = "filter",
            .buf = &st.filter_buf,
            .len = &st.filter_len,
            .placeholder = "Filter…",
            .w = left_w - 28,
        });

        const all_ents = [_][]const u8{ "Camera", "Hero", "Slime", "Torch", "Chest" };
        // Filter into stack buffer of indices.
        var filtered: [8][]const u8 = undefined;
        var fct: usize = 0;
        const needle = st.filter_buf[0..st.filter_len];
        for (all_ents) |name| {
            const match = needle.len == 0 or containsIgnoreCase(name, needle);
            if (match and fct < filtered.len) {
                filtered[fct] = name;
                fct += 1;
            }
        }
        const view = filtered[0..fct];
        if (st.list_sel >= view.len and view.len > 0) st.list_sel = view.len - 1;

        if (u.listBoxNav(.{
            .id = "entlist",
            .items = view,
            .selected = &st.list_sel,
            .w = left_w - 28,
            .h = 120,
        })) {
            if (view.len > 0) {
                const name = view[st.list_sel];
                const n = @min(name.len, st.entity_name.len);
                @memcpy(st.entity_name[0..n], name[0..n]);
                st.entity_name_len = n;
            }
        }

        // Right-click list → context menu (prefer this frame's rect, else previous).
        const list_id = u.id("entlist");
        if (u.currRectOf(list_id) orelse u.prevRectOf("entlist")) |lr| {
            _ = u.rightClickOpen("ent_ctx", lr);
        }

        u.separator();
        u.label(.{ .text = "Scene tree", .color = u.theme.text_dim });
        const tw = u.treeNode(.{ .id = "tr_world", .label = "World", .open = &st.world_open, .depth = 0 });
        _ = tw;
        if (st.world_open) {
            if (u.treeNode(.{ .id = "tr_cam", .label = "Camera", .depth = 1, .selected = st.list_sel == 0 }).clicked) {
                st.list_sel = 0;
            }
            const tn = u.treeNode(.{ .id = "tr_npcs", .label = "NPCs", .open = &st.npcs_open, .depth = 1 });
            _ = tn;
            if (st.npcs_open) {
                if (u.treeNode(.{ .id = "tr_hero", .label = "Hero", .depth = 2, .selected = std.mem.eql(u8, st.entity_name[0..st.entity_name_len], "Hero") }).clicked) {
                    const name = "Hero";
                    @memcpy(st.entity_name[0..name.len], name);
                    st.entity_name_len = name.len;
                }
                if (u.treeNode(.{ .id = "tr_slime", .label = "Slime", .depth = 2 }).clicked) {
                    const name = "Slime";
                    @memcpy(st.entity_name[0..name.len], name);
                    st.entity_name_len = name.len;
                }
            }
            if (u.treeNode(.{ .id = "tr_torch", .label = "Torch", .depth = 1 }).clicked) {
                const name = "Torch";
                @memcpy(st.entity_name[0..name.len], name);
                st.entity_name_len = name.len;
            }
        }

        u.separator();
        if (u.button(.{ .id = "add_ent", .label = "Add Entity", .w = 140 })) {
            st.clicks +%= 1;
            u.toast("Spawned entity (demo)", .ok, 1.5);
        }
        if (u.button(.{ .id = "del_ent", .label = "Delete…", .w = 140 })) {
            st.confirm_delete = true;
        }
    }

    // Drag splitter between panes.
    u.vSplitter(.{
        .id = "split",
        .x = left_x,
        .y = left_y,
        .h = left_h,
        .width = &st.split_w,
        .min = 160,
        .max = @max(160, max_split),
    });

    // Right: inspector form
    if (u.beginPanel(.{
        .id = "insp",
        .x = right_x,
        .y = left_y,
        .w = right_w,
        .h = left_h,
        .title = "Inspector",
    })) {
        defer u.endPanel();

        u.label(.{ .text = "Composite — split + tree + form + modal", .color = u.theme.text_dim });
        u.separator();

        _ = u.textInput(.{
            .id = "ename",
            .label = "Name",
            .buf = &st.entity_name,
            .len = &st.entity_name_len,
            .w = @min(320, right_w - 40),
        });
        _ = u.slider(.{ .id = "hp", .label = "HP", .value = &st.entity_hp, .min = 0, .max = 100, .w = @min(320, right_w - 40) });
        _ = u.toggle(.{ .id = "vis", .label = "Visible", .value = &st.entity_visible });
        _ = u.spinner(.{ .id = "layer", .label = "Layer", .value = &st.spinner_val, .min = 0, .max = 32, .step = 1, .w = 200 });

        u.separator();
        if (u.beginCollapsible(.{ .id = "col_xf", .title = "Transform", .open = &st.collab_a })) {
            defer u.endCollapsible(true);
            _ = u.slider(.{ .id = "px", .label = "Pos X", .value = &st.speed, .min = 0, .max = 1, .w = 240 });
            _ = u.slider(.{ .id = "py", .label = "Pos Y", .value = &st.volume, .min = 0, .max = 1, .w = 240 });
        } else {
            u.endCollapsible(false);
        }

        if (u.beginCollapsible(.{ .id = "col_mat", .title = "Material", .open = &st.collab_b })) {
            defer u.endCollapsible(true);
            u.label(.{ .text = "Tint swatches" });
            u.beginHStack(.{ .pad = 0, .gap = 6 });
            const swatches = [_]ui.Color{
                .{ 1, 1, 1, 1 },
                .{ 0.9, 0.3, 0.3, 1 },
                .{ 0.3, 0.85, 0.4, 1 },
                .{ 0.3, 0.5, 0.95, 1 },
                .{ 0.95, 0.8, 0.2, 1 },
            };
            for (swatches, 0..) |c, idx| {
                var idb: [16]u8 = undefined;
                const id = std.fmt.bufPrint(&idb, "sw{d}", .{idx}) catch "sw";
                if (u.colorSwatch(.{ .id = id, .color = c, .selected = st.color_idx == idx })) {
                    st.color_idx = idx;
                }
            }
            _ = u.endHStack();
        } else {
            u.endCollapsible(false);
        }

        u.separator();
        if (u.button(.{ .id = "open_modal", .label = "Open About Modal" })) {
            st.modal_open = true;
        }
        if (u.button(.{ .id = "toast_warn", .label = "Toast warning" })) {
            u.toast("Something needs attention", .warn, 2.5);
        }
    }

    // Context menu for entities
    if (u.contextMenu(.{
        .owner = "ent_ctx",
        .items = &.{ "Rename", "Duplicate", "Delete…", "Focus in view" },
    })) |choice| {
        switch (choice) {
            0 => u.toast("Rename (stub)", .info, 1.2),
            1 => {
                st.clicks +%= 1;
                u.toast("Duplicated", .ok, 1.2);
            },
            2 => st.confirm_delete = true,
            3 => u.toast("Focused camera on entity", .info, 1.5),
            else => {},
        }
    }

    // About modal
    if (u.beginModal(.{ .id = "about", .title = "About gl1", .open = &st.modal_open, .w = 420, .h = 240 })) {
        defer u.endModal();
        u.label(.{ .text = "gl1 — Zig + Sokol immediate UI" });
        u.label(.{ .text = "Dark-themed prototype for portable graphics apps.", .color = u.theme.text_dim });
        u.separator();
        u.label(.{ .text = "Esc or X closes this dialog (does not quit)." });
        if (u.button(.{ .id = "modal_ok", .label = "OK", .w = 80 })) {
            st.modal_open = false;
            u.toast("Modal closed", .ok, 1.2);
        }
    }

    // Confirm delete modal
    if (u.beginModal(.{ .id = "confirm_del", .title = "Delete entity?", .open = &st.confirm_delete, .w = 360, .h = 180 })) {
        defer u.endModal();
        u.label(.{ .text = "This cannot be undone (demo only)." });
        u.label(.{ .text = st.entity_name[0..st.entity_name_len], .color = u.theme.danger });
        u.separator();
        u.beginHStack(.{ .pad = 0, .gap = 8 });
        if (u.button(.{ .id = "del_yes", .label = "Delete", .w = 90 })) {
            st.confirm_delete = false;
            u.toast("Deleted (demo)", .err, 1.5);
        }
        if (u.button(.{ .id = "del_no", .label = "Cancel", .w = 90 })) {
            st.confirm_delete = false;
        }
        _ = u.endHStack();
    }

    var rbuf: [64]u8 = undefined;
    const right = std.fmt.bufPrint(&rbuf, "{s}  split={d:.0}", .{ st.entity_name[0..st.entity_name_len], st.split_w }) catch "";
    u.statusBar("inspector ready  |  drag splitter  |  right-click list", right);
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
        "Toggle",
        "Slider",
        "Spinner",
        "TextInput",
        "Dropdown",
        "Tabs",
        "ListBox",
        "Scroll",
        "Collapsible",
        "Modal",
        "Toast",
        "Menubar",
        "Splitter",
        "ContextMenu",
        "Tree",
        "Progress",
        "Panel",
        "Layout",
        "Theme",
        "Inspector",
    };

    // Sidebar (scrollable when many items)
    u.drawRect(u.place(0, 0, sidebar_w, a.height), u.theme.sidebar);
    u.drawText(16, 16, 2.5, u.theme.accent, "gl1 storybook");
    u.drawText(16, 42, 1.5, u.theme.text_dim, "living widget gallery");

    _ = u.beginScroll(.{ .id = "sb_nav", .x = 4, .y = 60, .w = sidebar_w - 8, .h = a.height - 150 });
    for (items, 0..) |item, idx| {
        // list rows via button-like labels
        const i = u.id(item);
        const r = u.alloc(0, 28);
        const full = ui.Rect{ .x = r.x, .y = r.y, .w = sidebar_w - 24, .h = 28 };
        const stt = u.interact(i, full, false);
        if (stt.clicked) st.selected = idx;
        const selected = st.selected == idx;
        if (selected) u.drawRect(full, u.theme.selected) else if (stt.hot) u.drawRect(full, u.theme.button_hot);
        u.drawText(full.x + 10, full.y + 6, 2.0, if (selected) u.theme.accent else u.theme.text, item);
        if (stt.hot) u.setTooltip(item);
    }
    u.endScroll();

    u.drawText(16, a.height - 80, 1.5, u.theme.text_dim, "Ctrl+0 storybook");
    u.drawText(16, a.height - 62, 1.5, u.theme.text_dim, "Ctrl+1..7 scenes");
    u.drawText(16, a.height - 44, 1.5, u.theme.text_dim, "Esc: modal then quit");

    const dx = sidebar_w + 16;
    const dw = a.width - dx - 16;
    const title = if (st.selected < items.len) items[st.selected] else "Story";
    if (u.beginPanel(.{ .id = "detail", .x = dx, .y = 16, .w = dw, .h = a.height - 32, .title = title })) {
        defer u.endPanel();

        switch (st.selected) {
            0 => {
                u.label(.{ .text = "GL1 prototype — Zig + Sokol immediate UI" });
                u.label(.{ .text = "Style A: begin/end + defer. Dark theme.", .color = u.theme.text_dim });
                u.separator();
                u.label(.{ .text = "Launch: zig build && ./zig-out/bin/gl1" });
                u.label(.{ .text = "Scenes: --scene storybook|inspector|triangle|..." });
                u.label(.{ .text = "Font: assets/fonts/glyphs-outline.bmp" });
                u.separator();
                if (u.button(.{ .id = "go_insp", .label = "Open inspector scene" })) {
                    a.scene = .inspector;
                }
                if (u.button(.{ .id = "go_tri", .label = "Open triangle scene" })) {
                    a.scene = .triangle;
                }
            },
            1 => {
                u.label(.{ .text = "Button — hover / active / click" });
                if (u.button(.{ .id = "sb_btn", .label = "Primary" })) {
                    st.clicks +%= 1;
                    u.toast("Clicked Primary", .ok, 1.2);
                }
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
            },
            4 => {
                u.label(.{ .text = "Toggle switch" });
                _ = u.toggle(.{ .id = "tog", .label = "Notifications", .value = &st.toggled });
            },
            5 => {
                u.label(.{ .text = "Slider" });
                _ = u.slider(.{ .id = "sb_sp", .label = "Speed", .value = &st.speed });
                _ = u.slider(.{ .id = "sb_vo", .label = "Volume", .value = &st.volume, .min = 0, .max = 2 });
            },
            6 => {
                u.label(.{ .text = "Spinner (− / +)" });
                _ = u.spinner(.{ .id = "sb_spin", .label = "Value", .value = &st.spinner_val, .min = 0, .max = 100, .step = 0.5 });
            },
            7 => {
                u.label(.{ .text = "Text input (Ctrl+digit = scenes; ! types fine)" });
                _ = u.textInput(.{ .id = "sb_ti", .label = "Value", .buf = &st.text_buf, .len = &st.text_len, .w = 280 });
                u.label(.{ .text = st.text_buf[0..st.text_len], .color = u.theme.accent });
            },
            8 => {
                u.label(.{ .text = "Dropdown / select" });
                const dd_items = [_][]const u8{ "Apple", "Banana", "Cherry", "Date" };
                _ = u.dropdown(.{
                    .id = "dd",
                    .label = "Fruit",
                    .items = &dd_items,
                    .selected = &st.dropdown_sel,
                    .open = &st.dropdown_open,
                    .w = 220,
                });
            },
            9 => {
                u.label(.{ .text = "Tabs" });
                const tab_items = [_][]const u8{ "General", "Graphics", "Audio" };
                _ = u.tabs(.{ .id = "tabs", .items = &tab_items, .selected = &st.tab_sel });
                u.separator();
                switch (st.tab_sel) {
                    0 => u.label(.{ .text = "General settings placeholder" }),
                    1 => u.label(.{ .text = "Graphics settings placeholder" }),
                    else => u.label(.{ .text = "Audio settings placeholder" }),
                }
            },
            10 => {
                u.label(.{ .text = "List box" });
                const li = [_][]const u8{ "Alpha", "Bravo", "Charlie", "Delta", "Echo" };
                _ = u.listBox(.{ .id = "lb", .items = &li, .selected = &st.list_sel, .w = 220, .h = 140 });
            },
            11 => {
                u.label(.{ .text = "Scroll area (wheel + scissor)" });
                _ = u.beginScroll(.{ .id = "sb_scroll", .x = dx + 24, .y = 100, .w = dw - 48, .h = 220 });
                var li: u32 = 0;
                while (li < 24) : (li += 1) {
                    var lbuf: [40]u8 = undefined;
                    const line = std.fmt.bufPrint(&lbuf, "scroll line {d}", .{li}) catch "";
                    u.label(.{ .text = line });
                }
                u.endScroll();
            },
            12 => {
                u.label(.{ .text = "Collapsible sections" });
                if (u.beginCollapsible(.{ .id = "c1", .title = "Section A", .open = &st.collab_a })) {
                    defer u.endCollapsible(true);
                    u.label(.{ .text = "Hidden until expanded." });
                    _ = u.checkbox(.{ .id = "c1c", .label = "Nested checkbox", .value = &st.checked });
                } else u.endCollapsible(false);
                if (u.beginCollapsible(.{ .id = "c2", .title = "Section B", .open = &st.collab_b })) {
                    defer u.endCollapsible(true);
                    u.label(.{ .text = "Another group of controls." });
                    _ = u.slider(.{ .id = "c2s", .label = "Nested", .value = &st.speed });
                } else u.endCollapsible(false);
            },
            13 => {
                u.label(.{ .text = "Modal dialog (Esc closes modal, not app)" });
                if (u.button(.{ .id = "open_m", .label = "Open modal" })) st.modal_open = true;
            },
            14 => {
                u.label(.{ .text = "Toast notifications" });
                if (u.button(.{ .id = "t_ok", .label = "OK toast" })) u.toast("All good", .ok, 2);
                if (u.button(.{ .id = "t_info", .label = "Info toast" })) u.toast("FYI message", .info, 2);
                if (u.button(.{ .id = "t_warn", .label = "Warn toast" })) u.toast("Watch out", .warn, 2);
                if (u.button(.{ .id = "t_err", .label = "Error toast" })) u.toast("Something failed", .err, 2);
            },
            15 => {
                u.label(.{ .text = "Menubar lives in the Inspector scene." });
                if (u.button(.{ .id = "go_i2", .label = "Open inspector" })) a.scene = .inspector;
            },
            16 => {
                u.label(.{ .text = "Vertical splitter — drag the gap between panes" });
                u.label(.{ .text = "See Inspector (Ctrl+7). Width is persisted in scene state.", .color = u.theme.text_dim });
                if (u.button(.{ .id = "go_split", .label = "Open inspector" })) a.scene = .inspector;
            },
            17 => {
                u.label(.{ .text = "Context menu — right-click the entity list in Inspector" });
                if (u.button(.{ .id = "ctx_demo", .label = "Open sample menu here" })) {
                    u.openContextMenu("sb_ctx");
                }
                if (u.contextMenu(.{ .owner = "sb_ctx", .items = &.{ "Action A", "Action B", "Cancel" } })) |c| {
                    var b: [32]u8 = undefined;
                    u.toast(std.fmt.bufPrint(&b, "chose {d}", .{c}) catch "chose", .info, 1.5);
                }
            },
            18 => {
                u.label(.{ .text = "Tree nodes — expand / select" });
                _ = u.treeNode(.{ .id = "sb_root", .label = "Root", .open = &st.world_open, .depth = 0 });
                if (st.world_open) {
                    _ = u.treeNode(.{ .id = "sb_c1", .label = "Child A", .depth = 1 });
                    _ = u.treeNode(.{ .id = "sb_c2", .label = "Child B", .open = &st.npcs_open, .depth = 1 });
                    if (st.npcs_open) {
                        _ = u.treeNode(.{ .id = "sb_c3", .label = "Leaf", .depth = 2, .selected = true });
                    }
                }
            },
            19 => {
                u.label(.{ .text = "Progress" });
                st.progress = @mod(st.progress + a.dt * 0.15, 1.0);
                u.progress(.{ .label = "Indeterminate loop", .value = st.progress, .w = 300 });
            },
            20 => {
                u.label(.{ .text = "Panel chrome — title bar + body." });
                u.label(.{ .text = "Use beginPanel / defer endPanel.", .color = u.theme.text_dim });
            },
            21 => {
                u.label(.{ .text = "Layout: vstack + hstack + padding/gap" });
                if (u.button(.{ .id = "sb_h1", .label = "A", .w = 60 })) {}
                if (u.button(.{ .id = "sb_h2", .label = "B", .w = 60 })) {}
                if (u.button(.{ .id = "sb_h3", .label = "C", .w = 60 })) {}
            },
            22 => {
                u.label(.{ .text = "Theme tokens" });
                _ = u.toggle(.{ .id = "theme_cool", .label = "Cool dark variant", .value = &st.theme_cool });
                u.separator();
                const sw = 28.0;
                const colors = [_]ui.Color{ u.theme.bg, u.theme.panel, u.theme.accent, u.theme.button, u.theme.danger, u.theme.warning, u.theme.info, u.theme.slider_fill };
                for (colors, 0..) |c, idx| {
                    var idb: [12]u8 = undefined;
                    const id = std.fmt.bufPrint(&idb, "th{d}", .{idx}) catch "th";
                    _ = u.colorSwatch(.{ .id = id, .color = c, .w = sw });
                }
                u.label(.{ .text = "bg panel accent button danger warn info fill", .color = u.theme.text_dim });
            },
            23 => {
                u.label(.{ .text = "Full composite demo: inspector scene" });
                if (u.button(.{ .id = "go_i3", .label = "Go to inspector" })) a.scene = .inspector;
            },
            else => {},
        }
    }

    // Storybook-level modal (shared state)
    if (u.beginModal(.{ .id = "sb_modal", .title = "Demo Modal", .open = &st.modal_open, .w = 400, .h = 220 })) {
        defer u.endModal();
        u.label(.{ .text = "This is a modal stack sample." });
        u.label(.{ .text = "Press Esc to close without quitting.", .color = u.theme.text_dim });
        if (u.button(.{ .id = "sb_modal_ok", .label = "Close" })) st.modal_open = false;
    }
}
