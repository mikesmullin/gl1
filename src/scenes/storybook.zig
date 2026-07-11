const std = @import("std");
const app = @import("../app.zig");
const ui = @import("../ui/ui.zig");
const theme_mod = @import("../ui/theme.zig");
const state = @import("state.zig");

pub fn frame(a: *app.App) void {
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

    u.drawText(16, a.height - 62, 1.5, u.theme.text_dim, "Ctrl+P command palette");
    u.drawText(16, a.height - 44, 1.5, u.theme.text_dim, "type 'scene' then Enter");

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
                u.label(.{ .text = "Ctrl+P palette — type 'scene' for scene list" });
                u.label(.{ .text = "Font: assets/fonts/glyphs-outline.bmp" });
                u.separator();
                if (u.button(.{ .id = "go_insp", .label = "Open inspector scene" })) {
                    a.scene = .inspector;
                }
                if (u.button(.{ .id = "go_canvas", .label = "Open canvas scene" })) {
                    a.scene = .canvas;
                }
                if (u.button(.{ .id = "open_pal", .label = "Open command palette" })) {
                    a.ui.palette_open = true;
                    a.ui.palette_query_len = 0;
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
                u.label(.{ .text = "See Inspector (Ctrl+P → scene). Split width is persisted.", .color = u.theme.text_dim });
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
