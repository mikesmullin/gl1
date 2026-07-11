const std = @import("std");
const app = @import("../app.zig");
const ui = @import("../ui/ui.zig");
const theme_mod = @import("../ui/theme.zig");
const state = @import("state.zig");

/// Overview first, then alphabetical. Inspector removed (use Ctrl+P).
const items = [_][]const u8{
    "Overview",
    "Button",
    "Checkbox",
    "Collapsible",
    "ContextMenu",
    "Dropdown",
    "Icons",
    "Layout",
    "ListBox",
    "Menubar",
    "Modal",
    "Panel",
    "Progress",
    "Radio",
    "Scroll",
    "Slider",
    "Splitter",
    "Tabs",
    "TextInput",
    "Theme",
    "Toast",
    "Toggle",
    "Tree",
};

fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub fn frame(a: *app.App) void {
    const u = &a.ui;
    const st = &a.scene_state;
    const sidebar_w: f32 = 200;

    // Sidebar
    u.drawRect(u.place(0, 0, sidebar_w, a.height), u.theme.sidebar);
    u.drawText(16, 16, 2.5, u.theme.accent, "gl1 storybook");
    u.drawText(16, 42, 1.5, u.theme.text_dim, "living widget gallery");

    _ = u.beginScroll(.{ .id = "sb_nav", .x = 4, .y = 60, .w = sidebar_w - 8, .h = a.height - 150 });
    for (items, 0..) |item, idx| {
        const i = u.id(item);
        const r = u.alloc(0, 28);
        const full = ui.Rect{ .x = r.x, .y = r.y, .w = sidebar_w - 24, .h = 28 };
        const stt = u.interact(i, full, false);
        if (stt.clicked) st.selected = idx;
        const selected = st.selected == idx;
        if (selected) u.drawRect(full, u.theme.selected) else if (stt.hot) u.drawRect(full, u.theme.button_hot);
        u.drawText(full.x + 10, full.y + 6, 2.0, if (selected) u.theme.accent else u.theme.text, item);
        // No tooltips on nav tabs — they only repeated the label.
    }
    u.endScroll();

    u.drawText(16, a.height - 62, 1.5, u.theme.text_dim, "Ctrl+P command palette");
    u.drawText(16, a.height - 44, 1.5, u.theme.text_dim, "jump to any scene");

    const dx = sidebar_w + 16;
    const dw = a.width - dx - 16;
    const title = if (st.selected < items.len) items[st.selected] else "Story";
    const tab = if (st.selected < items.len) items[st.selected] else "";
    // Icons grid is tall — enable body scroll on the detail panel for that tab.
    const detail_scroll = eq(tab, "Icons");
    if (u.beginPanel(.{ .id = "detail", .x = dx, .y = 16, .w = dw, .h = a.height - 32, .title = title, .scroll = detail_scroll })) {
        defer u.endPanel();

        if (eq(tab, "Overview")) {
            u.label(.{ .text = "gl1 is a portable Zig + Sokol immediate-mode UI prototype." });
            u.label(.{ .text = "It explores dense tool-style chrome (panels, editors, 3D canvas) in a single binary." });
            u.label(.{ .text = "Use Ctrl+P to open the command palette, type to filter, and Enter to jump to any scene" });
            u.label(.{ .text = "or action — including this storybook, the inspector, canvas, and more." });
            u.separator();
            u.label(.{ .text = "This storybook is a living gallery of every widget the UI toolkit exposes." });
            u.label(.{ .text = "Pick a tab on the left to try buttons, forms, layout, menus, scroll, trees, themes," });
            u.label(.{ .text = "and other building blocks in isolation — each page is a small interactive demo." });
            u.separator();
            u.label(.{ .text = "Stack: Zig (master) · Sokol · custom IMUI. Dark-first themes.", .color = u.theme.text_dim });
        } else if (eq(tab, "Button")) {
            u.label(.{ .text = "Button — hover / active / click" });
            if (u.button(.{ .id = "sb_btn", .label = "Primary" })) {
                st.clicks +%= 1;
                u.toast("Clicked Primary", .ok, 1.2);
            }
            if (u.button(.{ .id = "sb_btn2", .label = "Wide button", .w = 180 })) st.clicks +%= 1;
            _ = u.button(.{ .id = "sb_dis", .label = "Disabled", .disabled = true });
            var buf: [32]u8 = undefined;
            u.label(.{ .text = std.fmt.bufPrint(&buf, "clicks={d}", .{st.clicks}) catch "", .color = u.theme.text_dim });
        } else if (eq(tab, "Checkbox")) {
            u.label(.{ .text = "Checkboxes — independent multi-select (contrast with Radio)" });
            _ = u.checkbox(.{ .id = "sb_chk_a", .label = "Enable notifications", .value = &st.checked });
            _ = u.checkbox(.{ .id = "sb_chk_b", .label = "Auto-save drafts", .value = &st.checked_b });
            _ = u.checkbox(.{ .id = "sb_chk_c", .label = "Show grid lines", .value = &st.checked_c });
            u.separator();
            var cbuf: [64]u8 = undefined;
            u.label(.{
                .text = std.fmt.bufPrint(&cbuf, "states: {s} / {s} / {s}", .{
                    if (st.checked) "on" else "off",
                    if (st.checked_b) "on" else "off",
                    if (st.checked_c) "on" else "off",
                }) catch "",
                .color = u.theme.text_dim,
            });
        } else if (eq(tab, "Collapsible")) {
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
        } else if (eq(tab, "ContextMenu")) {
            u.label(.{ .text = "Context menu — open a sample menu here" });
            if (u.button(.{ .id = "ctx_demo", .label = "Open sample menu" })) {
                u.openContextMenu("sb_ctx");
            }
            if (u.contextMenu(.{ .owner = "sb_ctx", .items = &.{ "Action A", "Action B", "Cancel" } })) |c| {
                var b: [32]u8 = undefined;
                u.toast(std.fmt.bufPrint(&b, "chose {d}", .{c}) catch "chose", .info, 1.5);
            }
        } else if (eq(tab, "Dropdown")) {
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
        } else if (eq(tab, "Icons")) {
            u.label(.{ .text = "Icon atlas (24×24) — assets/icons + YAML manifest" });
            u.label(.{ .text = "Soft pointer: first click hides OS cursor. Refer to icons by alias when reporting issues.", .color = u.theme.text_dim });
            u.separator();
            u.label(.{ .text = "Samples (icon buttons)" });
            if (u.iconButton(.{ .id = "ic_save", .icon = .save, .label = "Save" })) u.toast("Save", .ok, 1);
            if (u.iconButton(.{ .id = "ic_search", .icon = .search, .label = "Search" })) u.toast("Search", .info, 1);
            if (u.iconButton(.{ .id = "ic_trash", .icon = .trash, .label = "Delete" })) u.toast("Delete", .err, 1);
            if (u.iconButton(.{ .id = "ic_settings", .icon = .settings, .label = "Settings" })) u.toast("Settings", .info, 1);
            u.separator();
            u.label(.{ .text = "All icons — alias + glyph (atlas order, multi-column)" });
            u.label(.{ .text = "Use the alias text when calling out a slot that needs cleanup.", .color = u.theme.text_dim });

            // Tabular multi-column: each cell is [icon][alias].
            const all = std.meta.tags(ui.IconId);
            const icon_sz: f32 = 24;
            const col_w: f32 = 148; // icon + gap + alias text
            const row_h: f32 = 32;
            const gap_x: f32 = 8;
            const gap_y: f32 = 4;
            const panel_inner_w = @max(200.0, dw - 48);
            const ncols: usize = @max(1, @as(usize, @intFromFloat(@floor((panel_inner_w + gap_x) / (col_w + gap_x)))));
            const nrows = (all.len + ncols - 1) / ncols;

            var row_i: usize = 0;
            while (row_i < nrows) : (row_i += 1) {
                const row = u.alloc(0, row_h + gap_y);
                var col_i: usize = 0;
                while (col_i < ncols) : (col_i += 1) {
                    // Row-major: left-to-right, top-to-bottom = atlas sheet order.
                    const idx_rm = row_i * ncols + col_i;
                    if (idx_rm >= all.len) break;
                    const cid = all[idx_rm];
                    const cell_x = row.x + @as(f32, @floatFromInt(col_i)) * (col_w + gap_x);
                    const cell_y = row.y;
                    u.drawIcon(cell_x, cell_y + (row_h - icon_sz) * 0.5, icon_sz, cid, null);
                    const alias = cid.primaryAlias();
                    u.drawText(cell_x + icon_sz + 8, cell_y + (row_h - u.font.lineHeight(1.6)) * 0.5, 1.6, u.theme.text, alias);
                }
            }

            u.separator();
            u.separator();
            u.label(.{ .text = "Hover buttons for pointer; sliders use hand/grab. Esc releases soft pointer before quit.", .color = u.theme.text_dim });
        } else if (eq(tab, "Layout")) {
            u.label(.{ .text = "Layout: vstack + hstack + padding/gap" });
            u.label(.{ .text = "Example 1 — horizontal row of actions", .color = u.theme.text_dim });
            u.beginHStack(.{});
            _ = u.button(.{ .id = "sb_h1", .label = "A", .w = 60 });
            _ = u.button(.{ .id = "sb_h2", .label = "B", .w = 60 });
            _ = u.button(.{ .id = "sb_h3", .label = "C", .w = 60 });
            _ = u.endHStack();
            u.separator();
            u.label(.{ .text = "Example 2 — form-style label + control rows", .color = u.theme.text_dim });
            u.beginFormRow(.{ .label = "Name", .label_w = 70 });
            _ = u.button(.{ .id = "sb_f1", .label = "Edit…", .w = 100 });
            u.endFormRow();
            u.beginFormRow(.{ .label = "Layer", .label_w = 70 });
            _ = u.slider(.{ .id = "sb_f2", .label = "", .value = &st.spinner_val, .min = 0, .max = 32, .w = 180 });
            u.endFormRow();
            u.separator();
            u.label(.{ .text = "Example 3 — nested hstack of toggles", .color = u.theme.text_dim });
            u.beginHStack(.{});
            _ = u.toggle(.{ .id = "lay_t1", .label = "Snap", .value = &st.toggled });
            _ = u.checkbox(.{ .id = "lay_c1", .label = "Grid", .value = &st.checked_b });
            _ = u.endHStack();
        } else if (eq(tab, "ListBox")) {
            u.label(.{ .text = "List box" });
            const li = [_][]const u8{ "Alpha", "Bravo", "Charlie", "Delta", "Echo" };
            _ = u.listBox(.{ .id = "lb", .items = &li, .selected = &st.list_sel, .w = 220, .h = 140 });
        } else if (eq(tab, "Menubar")) {
            u.label(.{ .text = "Menubar — simulated mini window (no scene jump)" });
            u.label(.{ .text = "Click File / Edit / View. Menus draw above the body.", .color = u.theme.text_dim });

            // Reserve vertical space, then draw a framed mini-window with its own menubar.
            const win_h: f32 = 160;
            const slot = u.alloc(0, win_h + 8);
            const win_w = @min(420.0, slot.w);
            const win = ui.Rect{ .x = slot.x, .y = slot.y, .w = win_w, .h = win_h };
            u.drawRectBorder(win, u.theme.panel, u.theme.panel_border, 1);

            const mh = u.beginMenubar(.{ .id = "sb_mb", .x = win.x + 1, .y = win.y + 1, .w = win.w - 2 });
            if (u.menuDropdown(.{ .id = "sb_file", .label = "File", .items = &.{ "New", "Open…", "Save", "Quit" } })) |fi| {
                const names = [_][]const u8{ "New", "Open…", "Save", "Quit" };
                const msg = names[fi];
                @memcpy(st.sb_menu_status[0..msg.len], msg);
                st.sb_menu_status_len = msg.len;
                u.toast(msg, .info, 1.2);
            }
            if (u.menuDropdown(.{ .id = "sb_edit", .label = "Edit", .items = &.{ "Undo", "Redo", "Cut", "Copy", "Paste" } })) |ei| {
                const names = [_][]const u8{ "Undo", "Redo", "Cut", "Copy", "Paste" };
                const msg = names[ei];
                @memcpy(st.sb_menu_status[0..msg.len], msg);
                st.sb_menu_status_len = msg.len;
                u.toast(msg, .info, 1.2);
            }
            if (u.menuDropdown(.{ .id = "sb_view", .label = "View", .items = &.{ "Zoom In", "Zoom Out", "Reset" } })) |vi| {
                const names = [_][]const u8{ "Zoom In", "Zoom Out", "Reset" };
                const msg = names[vi];
                @memcpy(st.sb_menu_status[0..msg.len], msg);
                st.sb_menu_status_len = msg.len;
                u.toast(msg, .info, 1.2);
            }
            u.endMenubar();

            const body_y = win.y + mh + 1;
            u.drawText(win.x + 12, body_y + 16, u.theme.font_size, u.theme.text, "Document body");
            const status = if (st.sb_menu_status_len > 0) st.sb_menu_status[0..st.sb_menu_status_len] else "(pick a menu item)";
            u.drawText(win.x + 12, body_y + 44, u.theme.font_size, u.theme.text_dim, "Last action:");
            u.drawText(win.x + 12, body_y + 66, u.theme.font_size, u.theme.accent, status);
        } else if (eq(tab, "Modal")) {
            u.label(.{ .text = "Modal dialog (Esc closes modal, not app)" });
            if (u.button(.{ .id = "open_m", .label = "Open modal" })) st.modal_open = true;
        } else if (eq(tab, "Panel")) {
            u.label(.{ .text = "Panel chrome — title bar + body." });
            u.label(.{ .text = "Use beginPanel / defer endPanel. This detail pane is one.", .color = u.theme.text_dim });
        } else if (eq(tab, "Progress")) {
            u.label(.{ .text = "Progress" });
            st.progress = @mod(st.progress + a.dt * 0.15, 1.0);
            u.progress(.{ .label = "Indeterminate loop", .value = st.progress, .w = 300 });
        } else if (eq(tab, "Radio")) {
            u.label(.{ .text = "Radio groups — exclusive within each cluster" });
            u.beginHStack(.{ .h = 150, .pad = 0, .gap = 24 });
            u.beginVStack(.{ .w = 180, .h = 140, .pad = 4, .gap = 4 });
            u.label(.{ .text = "Quality", .color = u.theme.text_dim });
            _ = u.radio(.{ .id = "r0", .label = "Low", .group = &st.radio_group, .value = 0 });
            _ = u.radio(.{ .id = "r1", .label = "Medium", .group = &st.radio_group, .value = 1 });
            _ = u.radio(.{ .id = "r2", .label = "High", .group = &st.radio_group, .value = 2 });
            _ = u.endVStack();
            u.beginVStack(.{ .w = 200, .h = 140, .pad = 4, .gap = 4 });
            u.label(.{ .text = "Theme mode", .color = u.theme.text_dim });
            _ = u.radio(.{ .id = "rb0", .label = "Follow system", .group = &st.radio_group_b, .value = 0 });
            _ = u.radio(.{ .id = "rb1", .label = "Always dark", .group = &st.radio_group_b, .value = 1 });
            _ = u.radio(.{ .id = "rb2", .label = "Always light", .group = &st.radio_group_b, .value = 2 });
            _ = u.endVStack();
            _ = u.endHStack();
            u.separator();
            var rbuf: [48]u8 = undefined;
            u.label(.{
                .text = std.fmt.bufPrint(&rbuf, "quality={d}  mode={d}", .{ st.radio_group, st.radio_group_b }) catch "",
                .color = u.theme.text_dim,
            });
        } else if (eq(tab, "Scroll")) {
            u.label(.{ .text = "Scroll area (wheel + scissor + scrollbar)" });
            // Use relative layout: place after labels by allocating space then absolute beginScroll.
            const scroll_slot = u.alloc(0, 240);
            _ = u.beginScroll(.{
                .id = "sb_scroll",
                .x = scroll_slot.x,
                .y = scroll_slot.y,
                .w = @min(dw - 48, scroll_slot.w),
                .h = 220,
            });
            var li: u32 = 0;
            while (li < 30) : (li += 1) {
                var lbuf: [40]u8 = undefined;
                const line = std.fmt.bufPrint(&lbuf, "scroll line {d}", .{li}) catch "";
                u.label(.{ .text = line });
            }
            u.endScroll();
        } else if (eq(tab, "Slider")) {
            u.label(.{ .text = "Blender-style number slider" });
            _ = u.slider(.{ .id = "sb_sp", .label = "Speed", .value = &st.speed });
            _ = u.slider(.{ .id = "sb_vo", .label = "Volume", .value = &st.volume, .min = 0, .max = 2 });
            _ = u.slider(.{ .id = "sb_layer", .label = "Layer", .value = &st.spinner_val, .min = 0, .max = 32, .w = 280 });
        } else if (eq(tab, "Splitter")) {
            u.label(.{ .text = "Vertical splitter — drag the gap between panes" });
            u.label(.{ .text = "Standalone demo (width is remembered while you stay in storybook).", .color = u.theme.text_dim });

            const split_h: f32 = 200;
            const slot = u.alloc(0, split_h + 8);
            const total_w = @min(slot.w, 480.0);
            st.sb_split_w = std.math.clamp(st.sb_split_w, 80, total_w - 80);

            const left = ui.Rect{ .x = slot.x, .y = slot.y, .w = st.sb_split_w, .h = split_h };
            const right = ui.Rect{
                .x = slot.x + st.sb_split_w,
                .y = slot.y,
                .w = total_w - st.sb_split_w,
                .h = split_h,
            };
            u.drawRectBorder(left, u.theme.input_bg, u.theme.panel_border, 1);
            u.drawRectBorder(right, u.theme.panel, u.theme.panel_border, 1);
            u.drawText(left.x + 10, left.y + 12, u.theme.font_size, u.theme.text, "Left pane");
            u.drawText(left.x + 10, left.y + 36, u.theme.font_size, u.theme.text_dim, "drag →");
            u.drawText(right.x + 10, right.y + 12, u.theme.font_size, u.theme.text, "Right pane");
            var sbuf: [40]u8 = undefined;
            u.drawText(right.x + 10, right.y + 36, u.theme.font_size, u.theme.text_dim, std.fmt.bufPrint(&sbuf, "left_w={d:.0}", .{st.sb_split_w}) catch "");

            u.vSplitter(.{
                .id = "sb_split",
                .x = slot.x,
                .y = slot.y,
                .h = split_h,
                .width = &st.sb_split_w,
                .min = 80,
                .max = total_w - 80,
            });
        } else if (eq(tab, "Tabs")) {
            u.label(.{ .text = "Tabs" });
            const tab_items = [_][]const u8{ "General", "Graphics", "Audio" };
            _ = u.tabs(.{ .id = "tabs", .items = &tab_items, .selected = &st.tab_sel });
            u.separator();
            switch (st.tab_sel) {
                0 => u.label(.{ .text = "General settings placeholder" }),
                1 => u.label(.{ .text = "Graphics settings placeholder" }),
                else => u.label(.{ .text = "Audio settings placeholder" }),
            }
        } else if (eq(tab, "TextInput")) {
            u.label(.{ .text = "Single-line text input" });
            _ = u.textInput(.{ .id = "sb_ti", .label = "Value", .buf = &st.text_buf, .len = &st.text_len, .w = 280 });
            u.label(.{ .text = st.text_buf[0..st.text_len], .color = u.theme.accent });
            u.separator();
            u.label(.{ .text = "Multi-line text area (soft wrap, multi-caret, resize grip)" });
            _ = u.textArea(.{
                .id = "sb_notes",
                .label = "Notes",
                .buf = &st.notes,
                .len = &st.notes_len,
                .w = @min(320, dw - 48),
                .rows = 3,
                .max_height = 160,
            });
        } else if (eq(tab, "Theme")) {
            u.label(.{ .text = "Theme selection" });
            u.label(.{ .text = "Choose a palette (applies app-wide):", .color = u.theme.text_dim });
            _ = u.radio(.{ .id = "th_dark", .label = "Dark (default green accent)", .group = &st.theme_id, .value = 0 });
            _ = u.radio(.{ .id = "th_cool", .label = "Cool (blue accent)", .group = &st.theme_id, .value = 1 });
            _ = u.radio(.{ .id = "th_warm", .label = "Warm (amber accent)", .group = &st.theme_id, .value = 2 });
            u.separator();
            u.label(.{ .text = "Palette swatches (display only — not clickable)", .color = u.theme.text_dim });

            const names = [_][]const u8{ "bg", "panel", "accent", "button", "danger", "warn", "info", "fill" };
            const colors = [_]ui.Color{ u.theme.bg, u.theme.panel, u.theme.accent, u.theme.button, u.theme.danger, u.theme.warning, u.theme.info, u.theme.slider_fill };
            const sw: f32 = 28;
            // Horizontal row of non-interactive swatches with labels under each.
            const row = u.alloc(0, sw + 28);
            var cx = row.x;
            for (colors, 0..) |c, idx| {
                const cell_w: f32 = 56;
                const sr = ui.Rect{ .x = cx, .y = row.y, .w = sw, .h = sw };
                u.drawRectBorder(sr, c, u.theme.panel_border, 1);
                u.drawText(cx, row.y + sw + 6, 1.4, u.theme.text_dim, names[idx]);
                cx += cell_w;
            }
        } else if (eq(tab, "Toast")) {
            u.label(.{ .text = "Toast notifications" });
            if (u.button(.{ .id = "t_ok", .label = "OK toast" })) u.toast("All good", .ok, 2);
            if (u.button(.{ .id = "t_info", .label = "Info toast" })) u.toast("FYI message", .info, 2);
            if (u.button(.{ .id = "t_warn", .label = "Warn toast" })) u.toast("Watch out", .warn, 2);
            if (u.button(.{ .id = "t_err", .label = "Error toast" })) u.toast("Something failed", .err, 2);
        } else if (eq(tab, "Toggle")) {
            u.label(.{ .text = "Toggle switch" });
            _ = u.toggle(.{ .id = "tog", .label = "Notifications", .value = &st.toggled });
        } else if (eq(tab, "Tree")) {
            u.label(.{ .text = "Tree nodes — click the row (arrow or label) to expand" });
            _ = u.treeNode(.{ .id = "sb_root", .label = "Root", .open = &st.world_open, .depth = 0 });
            if (st.world_open) {
                _ = u.treeNode(.{ .id = "sb_c1", .label = "Child A", .depth = 1 });
                _ = u.treeNode(.{ .id = "sb_c2", .label = "Child B", .open = &st.npcs_open, .depth = 1 });
                if (st.npcs_open) {
                    _ = u.treeNode(.{ .id = "sb_c3", .label = "Leaf", .depth = 2, .selected = true });
                }
            }
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
