const std = @import("std");
const app = @import("../app.zig");
const ui = @import("../ui/ui.zig");
const theme_mod = @import("../ui/theme.zig");
const state = @import("state.zig");
const util = @import("util.zig");

pub fn frame(a: *app.App) void {
    const u = &a.ui;
    const st = &a.scene_state;

    // Menubar with real dropdowns
    _ = u.beginMenubar(.{});
    if (u.menuDropdown(.{
        .id = "file",
        .label = "File",
        .items = &.{ "New", "Open…", "Save", "Command palette", "Quit" },
    })) |fi| {
        switch (fi) {
            0 => {
                u.toast("New (stub)", .info, 1.2);
                u.log("file: new");
            },
            1 => {
                u.toast("Open (stub)", .info, 1.2);
                u.log("file: open");
            },
            2 => {
                u.toast("Saved (stub)", .ok, 1.2);
                u.log("file: save");
            },
            3 => {
                u.palette_open = true;
                u.palette_query_len = 0;
            },
            4 => @import("sokol").app.quit(),
            else => {},
        }
    }
    if (u.menuDropdown(.{
        .id = "edit",
        .label = "Edit",
        .items = &.{ "Undo", "Redo", "Cut", "Copy", "Paste" },
    })) |ei| {
        const names = [_][]const u8{ "Undo", "Redo", "Cut", "Copy", "Paste" };
        if (ei < names.len) {
            u.toast(names[ei], .info, 1.0);
            u.log(names[ei]);
        }
    }
    if (u.menuDropdown(.{
        .id = "view",
        .label = "View",
        .items = &.{ "Storybook", "Inspector", "Canvas", "Toggle console", "Cycle theme" },
    })) |vi| {
        switch (vi) {
            0 => a.scene = .storybook,
            1 => a.scene = .inspector,
            2 => a.scene = .canvas,
            3 => st.show_console = !st.show_console,
            4 => st.theme_id = (st.theme_id + 1) % 3,
            else => {},
        }
    }
    if (u.menuItem(.{ .id = "m_help", .label = "Help" })) {
        st.modal_open = true;
    }
    u.endMenubar();

    const top = u.theme.menubar_h;
    const bot = u.theme.statusbar_h;
    const console_h: f32 = if (st.show_console) st.console_h + 8 else 0;
    const body_h = a.height - top - bot - console_h;
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
            const match = needle.len == 0 or util.containsIgnoreCase(name, needle);
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

        // Right-click list (or empty area below tree) → context menu.
        const list_id = u.id("entlist");
        if (u.currRectOf(list_id) orelse u.prevRectOf("entlist")) |lr| {
            _ = u.rightClickOpen("ent_ctx", lr);
        }
        // Also open when right-clicking the entity panel body (easier hit target).
        if (u.input.mousePressed(.right)) {
            const panel_r = u.currRectOf(u.id("ents")) orelse u.prevRectOf("ents");
            if (panel_r) |pr| {
                if (pr.contains(u.input.mouse_x, u.input.mouse_y)) {
                    u.openContextMenu("ent_ctx");
                }
            }
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

    // Right: inspector form (scrollable body for short windows)
    if (u.beginPanel(.{
        .id = "insp",
        .x = right_x,
        .y = left_y,
        .w = right_w,
        .h = left_h,
        .title = "Inspector",
        .scroll = true,
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
        _ = u.slider(.{ .id = "layer", .label = "Layer", .value = &st.spinner_val, .min = 0, .max = 32, .w = @min(320, right_w - 40) });

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
        // Viewport preview of selected entity tint
        u.label(.{ .text = "Viewport preview", .color = u.theme.text_dim });
        const vp_w = @min(280, right_w - 40);
        const vp_h: f32 = 100;
        const vpr = u.alloc(vp_w, vp_h);
        const swatches = [_]ui.Color{
            .{ 1, 1, 1, 1 },
            .{ 0.9, 0.3, 0.3, 1 },
            .{ 0.3, 0.85, 0.4, 1 },
            .{ 0.3, 0.5, 0.95, 1 },
            .{ 0.95, 0.8, 0.2, 1 },
        };
        const tint = swatches[st.color_idx % swatches.len];
        u.drawRectBorder(vpr, .{ 0.06, 0.07, 0.09, 1 }, u.theme.panel_border, 1);
        // "Entity" rect centered in viewport
        const ew = 48 * (0.5 + st.entity_hp / 100);
        const eh = 48 * (0.5 + st.entity_hp / 100);
        if (st.entity_visible) {
            u.drawRect(.{
                .x = vpr.x + (vpr.w - ew) * 0.5,
                .y = vpr.y + (vpr.h - eh) * 0.5,
                .w = ew,
                .h = eh,
            }, tint);
        }
        u.drawText(vpr.x + 6, vpr.y + 4, 1.5, u.theme.text_dim, st.entity_name[0..st.entity_name_len]);

        _ = u.textArea(.{
            .id = "notes",
            .label = "Notes",
            .buf = &st.notes,
            .len = &st.notes_len,
            .w = @min(320, right_w - 40),
            .rows = 3,
            .max_height = 160,
        });

        u.separator();
        if (u.button(.{ .id = "open_modal", .label = "Open About Modal" })) {
            st.modal_open = true;
            u.log("opened about modal");
        }
        if (u.button(.{ .id = "toast_warn", .label = "Toast warning" })) {
            u.toast("Something needs attention", .warn, 2.5);
            u.log("toast warning");
        }
        _ = u.toggle(.{ .id = "show_con", .label = "Show console", .value = &st.show_console });
    }

    // Console docked under panels
    if (st.show_console) {
        const ch = st.console_h;
        u.console(.{
            .id = "insp_log",
            .x = margin,
            .y = a.height - bot - ch - 4,
            .w = a.width - margin * 2,
            .h = ch,
        });
    }

    // Context menu for entities
    if (u.contextMenu(.{
        .owner = "ent_ctx",
        .items = &.{ "Rename", "Duplicate", "Delete…", "Focus in view" },
    })) |choice| {
        switch (choice) {
            0 => {
                u.toast("Rename (stub)", .info, 1.2);
                u.log("ctx: rename");
            },
            1 => {
                st.clicks +%= 1;
                u.toast("Duplicated", .ok, 1.2);
                u.log("ctx: duplicate");
            },
            2 => st.confirm_delete = true,
            3 => {
                u.toast("Focused camera on entity", .info, 1.5);
                u.log("ctx: focus");
            },
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
    u.statusBar("Ctrl+P palette  |  drag splitter  |  right-click list", right);
}
