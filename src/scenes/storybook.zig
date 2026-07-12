const std = @import("std");
const app = @import("../app.zig");
const ui = @import("../ui/ui.zig");
const theme_mod = @import("../ui/theme.zig");
const color_picker = @import("../ui/components/colorPicker.zig");
const browser = @import("../ui/browser/browser.zig");
const demo_assets = @import("demo_assets");
const state = @import("state.zig");

/// Overview first, then alphabetical. Feel = springs / game-feel demos.
pub const items = [_][]const u8{
    "Overview",
    "Accordion",
    "Alert",
    "Avatar",
    "Badge",
    "Browser",
    "Button",
    "Checkbox",
    "Collapsible",
    "ColorPicker",
    "Combobox",
    "ContextMenu",
    "Counter",
    "Dropdown",
    "DropdownButton",
    "Feel",
    "Histogram",
    "Icons",
    "IconButton",
    "ImageWell",
    "KeyValue",
    "Layout",
    "Link",
    "ListBox",
    "Menubar",
    "Modal",
    "MultiSelect",
    "Panel",
    "Password",
    "Progress",
    "Radio",
    "RequestButton",
    "Scroll",
    "Segmented",
    "Slider",
    "Spinner",
    "Splitter",
    "Table",
    "Tabs",
    "TagInput",
    "TextInput",
    "Theme",
    "Toast",
    "Toggle",
    "Tree",
    "Typeahead",
};

fn ensureBrowsers(a: *app.App) void {
    const st = &a.scene_state;
    if (st.browser_ready) return;
    const alloc = a.allocator;
    st.browser_hello.init(alloc);
    st.browser_table.init(alloc);
    st.browser_news.init(alloc);
    st.browser_flex.init(alloc);
    st.browser_img.init(alloc);
    st.browser_audio.init(alloc);
    st.browser_video.init(alloc);

    st.browser_hello.loadHtml(demo_assets.html_hello, "fixture://hello.html") catch {};
    st.browser_table.loadHtml(demo_assets.html_table, "fixture://table.html") catch {};
    // Real origin so root-relative links (/newsletter/…) open on ladybird.org.
    st.browser_news.loadHtml(demo_assets.html_news, "https://ladybird.org/news/") catch {};
    st.browser_flex.loadHtml(demo_assets.html_flex, "fixture://flex.html") catch {};

    // Dedicated media iframes (simpler markup)
    const audio_html =
        \\<!DOCTYPE html><html><head><title>Audio</title>
        \\<style>body{margin:12px} h1{font-size:16px}</style></head>
        \\<body><h1>robot-g-funk.wav</h1>
        \\<audio src="robot-g-funk.wav" controls></audio>
        \\<p>Converted from mp3 · mono 22.05kHz · sokol_audio</p></body></html>
    ;
    const video_html =
        \\<!DOCTYPE html><html><head><title>Video</title>
        \\<style>body{margin:8px} h1{font-size:14px}</style></head>
        \\<body><h1>robot-breakdance.mp4</h1>
        \\<video src="robot-breakdance.mp4" width="320" height="200" controls poster="poster.png"></video>
        \\<p>Phase-1 frame strip (4 fps) · full mp4 on disk for later ffmpeg</p></body></html>
    ;
    const img_html =
        \\<!DOCTYPE html><html><head><title>Image</title>
        \\<style>body{margin:12px} h1{font-size:16px}</style></head>
        \\<body><h1>robot-daddy</h1>
        \\<img src="robot-daddy.png" width="320" height="153" alt="robot daddy"/>
        \\<p>&lt;img&gt; robot-daddy.png</p></body></html>
    ;
    st.browser_audio.loadHtml(audio_html, "fixture://audio.html") catch {};
    st.browser_audio.loadAudioFile(a.io, "assets/demo/media/robot-g-funk.wav");
    st.browser_video.loadHtml(video_html, "fixture://video.html") catch {};
    st.browser_video.ensureVideoPoster(a.io);
    st.browser_video.loadVideoFrames(a.io);
    st.browser_img.loadHtml(img_html, "fixture://img.html") catch {};
    st.browser_img.loadImagePng(a.io, "assets/demo/media/robot-daddy.png", 320, 153);

    st.browser_ready = true;
}

const fruit = [_][]const u8{ "Apple", "Apricot", "Banana", "Blueberry", "Cherry", "Grape", "Mango", "Orange", "Peach", "Pear" };
const ms_items = [_][]const u8{ "Read", "Write", "Execute", "Admin", "Audit", "Share" };
const table_cols = [_][]const u8{ "Name", "HP", "Status" };
const table_cells = [_][3][]const u8{
    .{ "Hero", "100", "ok" },
    .{ "Slime", "40", "hurt" },
    .{ "Torch", "1", "lit" },
    .{ "Crystal", "80", "ok" },
    .{ "Crate", "25", "ok" },
};

fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// Resolve storybook sidebar tab name → index (case-sensitive match on `items`).
pub fn tabIndex(name: []const u8) ?usize {
    for (items, 0..) |it, idx| {
        if (std.mem.eql(u8, it, name)) return idx;
    }
    return null;
}

pub fn frame(a: *app.App) void {
    const u = &a.ui;
    const st = &a.scene_state;
    const sidebar_w: f32 = 200;

    // Sidebar
    u.drawRect(u.place(0, 0, sidebar_w, a.height), u.theme.sidebar);
    u.drawText(16, 16, 2.5, u.theme.accent, "gl1 storybook");
    u.drawText(16, 42, 1.5, u.theme.text_dim, "living widget gallery");

    // Sidebar nav focus: click any tab to focus the list, then ↑/↓ to move selection.
    const nav_rect = ui.Rect{ .x = 4, .y = 60, .w = sidebar_w - 8, .h = a.height - 150 };
    if (a.input.mousePressed(.left) and nav_rect.contains(a.input.mouse_x, a.input.mouse_y)) {
        st.sb_nav_focus = true;
    } else if (a.input.mousePressed(.left) and !nav_rect.contains(a.input.mouse_x, a.input.mouse_y)) {
        // Click outside sidebar nav releases keyboard focus on the tab list.
        // (Detail panel widgets take their own focus as usual.)
        if (a.input.mouse_x > sidebar_w) st.sb_nav_focus = false;
    }
    const nav_item_h: f32 = 28;
    const nav_view_h = a.height - 150;
    if (st.sb_nav_focus) {
        var moved = false;
        if (a.input.keyPressed(.down)) {
            if (st.selected + 1 < items.len) {
                st.selected += 1;
                moved = true;
            }
        }
        if (a.input.keyPressed(.up)) {
            if (st.selected > 0) {
                st.selected -= 1;
                moved = true;
            }
        }
        // Keep selected tab in view when keyboard-navigating past the fold.
        if (moved) {
            const nav_id = u.id("sb_nav");
            if (u.scroll_phys.getPtr(nav_id.a)) |sp| {
                const step = nav_item_h + u.theme.gap;
                const pad = u.theme.pad;
                const item_top = pad + @as(f32, @floatFromInt(st.selected)) * step;
                const item_bot = item_top + nav_item_h;
                const view = nav_view_h - 2; // scissor inset
                if (item_top < sp.y) {
                    sp.y = item_top;
                    sp.vel = 0;
                    sp.mode = .idle;
                } else if (item_bot > sp.y + view) {
                    sp.y = item_bot - view;
                    sp.vel = 0;
                    sp.mode = .idle;
                }
                if (sp.y < 0) sp.y = 0;
            }
        }
    }

    _ = u.beginScroll(.{ .id = "sb_nav", .x = 4, .y = 60, .w = sidebar_w - 8, .h = nav_view_h });
    for (items, 0..) |item, idx| {
        const i = u.id(item);
        const r = u.alloc(0, nav_item_h);
        const full = ui.Rect{ .x = r.x, .y = r.y, .w = sidebar_w - 24, .h = nav_item_h };
        const stt = u.interact(i, full, false);
        if (stt.clicked) {
            st.selected = idx;
            st.sb_nav_focus = true;
        }
        const selected = st.selected == idx;
        if (selected) u.drawRect(full, u.theme.selected) else if (stt.hot) u.drawRect(full, u.theme.button_hot);
        // Focus ring on the active tab when nav has keyboard focus.
        if (selected and st.sb_nav_focus) {
            u.drawRectOutline(.{ .x = full.x, .y = full.y, .w = full.w, .h = full.h }, u.theme.accent, 1);
        }
        u.drawText(full.x + 10, full.y + 6, 2.0, if (selected) u.theme.accent else u.theme.text, item);
    }
    u.endScroll();

    u.drawText(16, a.height - 62, 1.5, u.theme.text_dim, "Ctrl+P command palette");
    u.drawText(16, a.height - 44, 1.5, u.theme.text_dim, "jump to any scene");

    const dx = sidebar_w + 16;
    const dw = a.width - dx - 16;
    const title = if (st.selected < items.len) items[st.selected] else "Story";
    const tab = if (st.selected < items.len) items[st.selected] else "";
    // Tall demos need body scroll. Use per-tab panel id so scroll offset does not
    // carry over from Icons (and leave short pages looking "empty").
    const detail_scroll = eq(tab, "Icons") or eq(tab, "RequestButton") or eq(tab, "Table") or eq(tab, "KeyValue") or eq(tab, "Histogram") or eq(tab, "ImageWell") or eq(tab, "Browser");
    var detail_id_buf: [64]u8 = undefined;
    const detail_id = std.fmt.bufPrint(&detail_id_buf, "detail_{s}", .{tab}) catch "detail";
    if (u.beginPanel(.{ .id = detail_id, .x = dx, .y = 16, .w = dw, .h = a.height - 32, .title = title, .scroll = detail_scroll })) {
        defer u.endPanel();

        if (eq(tab, "Overview")) {
            u.label(.{ .text = "gl1 is a portable Zig + Sokol immediate-mode UI prototype." });
            u.label(.{ .text = "It explores dense tool-style chrome (panels, editors, 3D canvas) in a single binary." });
            u.label(.{ .text = "Use Ctrl+P to open the command palette, type to filter, and Enter to jump to any scene" });
            u.label(.{ .text = "or action — including this storybook, the canvas editor, and more." });
            u.separator();
            u.label(.{ .text = "This storybook is a living gallery of every widget the UI toolkit exposes." });
            u.label(.{ .text = "Pick a tab on the left to try buttons, forms, layout, menus, scroll, trees, themes," });
            u.label(.{ .text = "and other building blocks in isolation — each page is a small interactive demo." });
            u.separator();
            u.label(.{ .text = "Stack: Zig (master) · Sokol · custom IMUI. Dark-first themes.", .color = u.theme.text_dim });
            u.separator();
            u.label(.{ .text = "Also try: Feel (springs), Spinner / Badge / Alert, scene changes (diamond wipe).", .color = u.theme.text_dim });
        } else if (eq(tab, "Alert")) {
            u.label(.{ .text = "Alert — inline status banner" });
            u.alert(.{ .text = "Info: scene switched via Ctrl+P uses a diamond wipe.", .kind = .info });
            u.alert(.{ .text = "Success: selection framed.", .kind = .ok });
            u.alert(.{ .text = "Warning: soft pointer armed — Esc to release.", .kind = .warn });
            u.alert(.{ .text = "Error: could not load optional asset.", .kind = .err });
        } else if (eq(tab, "Accordion")) {
            u.label(.{ .text = "Accordion — exclusive (only one section open)" });
            if (u.beginAccordion(.{ .id = "acc_a", .title = "General", .open_index = &st.acc_open, .index = 0 })) {
                defer u.endAccordion(true);
                u.label(.{ .text = "General settings live here." });
                _ = u.checkbox(.{ .id = "acc_c1", .label = "Enabled", .value = &st.checked });
            } else u.endAccordion(false);
            if (u.beginAccordion(.{ .id = "acc_b", .title = "Network", .open_index = &st.acc_open, .index = 1 })) {
                defer u.endAccordion(true);
                u.label(.{ .text = "Host / port / TLS options…" });
            } else u.endAccordion(false);
            if (u.beginAccordion(.{ .id = "acc_c", .title = "Advanced", .open_index = &st.acc_open, .index = 2 })) {
                defer u.endAccordion(true);
                u.label(.{ .text = "Danger zone.", .color = u.theme.danger });
            } else u.endAccordion(false);
        } else if (eq(tab, "Avatar")) {
            u.label(.{ .text = "Avatar / user chip — initials from name" });
            u.beginHStack(.{ .h = 48 });
            u.avatar(.{ .name = "Ada Lovelace", .size = 40 });
            u.avatar(.{ .name = "Grace Hopper", .size = 40, .color = u.theme.info });
            u.avatar(.{ .name = "Lin", .size = 40, .color = u.theme.warning });
            _ = u.endHStack();
            u.separator();
            u.userChip(.{ .name = "ada@example.com", .color = u.theme.accent });
            u.userChip(.{ .name = "guest", .color = u.theme.text_dim });
        } else if (eq(tab, "Badge")) {
            u.label(.{ .text = "Badge — compact status chips" });
            u.beginHStack(.{});
            u.badge(.{ .label = "default" });
            u.badge(.{ .label = "live", .color = .{ 0.3, 0.85, 0.45, 1 } });
            u.badge(.{ .label = "beta", .color = u.theme.warning });
            u.badge(.{ .label = "error", .color = u.theme.danger });
            _ = u.endHStack();
            u.separator();
            u.label(.{ .text = "Status pill — enum → color (badge family)" });
            u.beginHStack(.{});
            u.statusPill(.{ .kind = .idle });
            u.statusPill(.{ .kind = .running });
            u.statusPill(.{ .kind = .success });
            u.statusPill(.{ .kind = .warning });
            u.statusPill(.{ .kind = .error_ });
            _ = u.endHStack();
        } else if (eq(tab, "Browser")) {
            ensureBrowsers(a);
            u.label(.{ .text = "Browser — embedded mini-browser (HTML/CSS subset, content-only frames)" });
            u.label(.{ .text = "Hover a frame to scroll it (blocks outer panel) · white text / black bg defaults · no JS yet", .color = u.theme.text_dim });
            u.separator();

            const bw = dw - 40;
            const Rect = ui.Rect;
            // Stack of content-only iframe instances (no title/url chrome).
            const frames = [_]struct { title: []const u8, h: f32, doc: *browser.BrowserDoc }{
                .{ .title = "hello.html", .h = 200, .doc = &st.browser_hello },
                .{ .title = "img · robot-daddy", .h = 220, .doc = &st.browser_img },
                .{ .title = "audio", .h = 160, .doc = &st.browser_audio },
                .{ .title = "video", .h = 260, .doc = &st.browser_video },
                .{ .title = "geo · ohio (craigslist-ish)", .h = 280, .doc = &st.browser_table },
                .{ .title = "news (ladybird-ish)", .h = 260, .doc = &st.browser_news },
                .{ .title = "flex cards", .h = 200, .doc = &st.browser_flex },
            };
            for (frames, 0..) |fr, i| {
                u.label(.{ .text = fr.title, .color = u.theme.text_dim });
                const slot = u.alloc(bw, fr.h);
                var id_buf: [32]u8 = undefined;
                const id = std.fmt.bufPrint(&id_buf, "br_{d}", .{i}) catch "br";
                browser.frameAt(u, fr.doc, id, Rect{ .x = slot.x, .y = slot.y, .w = slot.w, .h = slot.h }, false);
                u.spacer(8);
            }
        } else if (eq(tab, "Button")) {
            u.label(.{ .text = "Button — hover / active / click (pointer cursor)" });
            if (u.button(.{ .id = "sb_btn", .label = "Primary", .primary = true })) {
                st.clicks +%= 1;
                u.toast("Clicked Primary", .ok, 1.2);
            }
            if (u.button(.{ .id = "sb_btn2", .label = "Wide button", .w = 180 })) st.clicks +%= 1;
            _ = u.button(.{ .id = "sb_dis", .label = "Disabled", .disabled = true });
            var buf: [32]u8 = undefined;
            u.label(.{ .text = std.fmt.bufPrint(&buf, "clicks={d}", .{st.clicks}) catch "", .color = u.theme.text_dim });
        } else if (eq(tab, "Checkbox")) {
            u.label(.{ .text = "Checkbox — independent multi-select (contrast with Radio)" });
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
            u.label(.{ .text = "Collapsible — expandable section headers" });
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
            u.label(.{ .text = "Dropdown — single-select menu (click or caret)" });
            const dd_items = [_][]const u8{ "Apple", "Banana", "Cherry", "Date" };
            _ = u.dropdown(.{
                .id = "dd",
                .label = "Fruit",
                .items = &dd_items,
                .selected = &st.dropdown_sel,
                .open = &st.dropdown_open,
                .w = 220,
            });
        } else if (eq(tab, "Feel")) {
            // --- Game feel / springs (Ryan Juckett + Toyful Games patterns) ---
            u.label(.{ .text = "Feel — springs for responsive UX (game feel)" });
            u.label(.{ .text = "Damped springs (Game9 Spring.c / Juckett). Tune damping + frequency live.", .color = u.theme.text_dim });
            _ = u.slider(.{ .id = "feel_d", .label = "Damping", .value = &st.spring_damp, .min = 0.05, .max = 1.5, .w = 260 });
            _ = u.slider(.{ .id = "feel_f", .label = "Frequency", .value = &st.spring_freq, .min = 1, .max = 28, .w = 260 });
            u.separator();

            const dt = a.dt;
            const damp = st.spring_damp;
            const freq = st.spring_freq;

            // 1) Press button with squash + settle
            u.label(.{ .text = "1. Juicy button (press squash + bounce)" });
            const br = u.alloc(160, 56);
            const bst = u.interact(u.id("feel_btn"), br, false);
            if (bst.hot and u.input.mousePressed(.left)) {
                st.feel_press.snap(1, 8); // instant down + kick
                st.feel_squash.target = 0.72;
                st.feel_squash.nudge(-2.5);
            }
            if (!u.input.mouseDown(.left)) {
                st.feel_press.target = 0;
                st.feel_squash.target = 1;
            } else if (bst.active or (bst.hot and u.input.mouseDown(.left))) {
                st.feel_press.target = 1;
                st.feel_squash.target = 0.72;
            }
            st.feel_press.step(dt, damp, freq);
            st.feel_squash.step(dt, damp, freq * 1.1);
            const press_y = st.feel_press.pos * 10;
            const sc = st.feel_squash.pos;
            const bw = 140 * (2.0 - sc); // stretch X when Y squishes
            const bh = 40 * sc;
            const bx = br.x + (br.w - bw) * 0.5;
            const by = br.y + 8 + press_y;
            u.drawRectBorder(.{ .x = bx, .y = by, .w = bw, .h = bh }, u.theme.button_hot, u.theme.accent, 1);
            u.drawText(bx + 36, by + bh * 0.3, u.theme.font_size, u.theme.text, "Press me");
            if (u.button(.{ .id = "feel_nudge", .label = "Nudge / attract", .w = 140 })) {
                st.feel_squash.nudge(-6);
                st.feel_press.nudge(4);
            }

            u.separator();
            // 2) Follow mouse (2D spring)
            u.label(.{ .text = "2. Follow spring (cursor trail)" });
            const fr = u.alloc(0, 120);
            u.drawRectBorder(fr, .{ 0.08, 0.09, 0.11, 1 }, u.theme.panel_border, 1);
            // Local mouse relative to pad
            var mx = u.input.mouse_x;
            var my = u.input.mouse_y;
            if (!fr.contains(mx, my)) {
                mx = fr.x + fr.w * 0.5;
                my = fr.y + fr.h * 0.5;
            }
            st.feel_follow.setTarget(mx, my);
            st.feel_follow.step(dt, damp, freq);
            const fx = st.feel_follow.x.pos;
            const fy = st.feel_follow.y.pos;
            u.drawRect(.{ .x = fx - 8, .y = fy - 8, .w = 16, .h = 16 }, u.theme.accent);
            u.drawText(fr.x + 8, fr.y + 6, 1.4, u.theme.text_dim, "hover this pad");

            u.separator();
            // 3) Track / snap
            u.label(.{ .text = "3. Track slider (spring follows value; release snaps to 0 / 0.5 / 1)" });
            _ = u.slider(.{ .id = "feel_track_goal", .label = "Goal", .value = &st.spring_track_target, .min = 0, .max = 1, .w = 280 });
            st.feel_track.target = st.spring_track_target;
            if (u.input.mouseReleased(.left)) {
                // Snap goal to thirds
                const g0 = st.spring_track_target;
                st.spring_track_target = if (g0 < 0.33) 0 else if (g0 < 0.66) 0.5 else 1;
                st.feel_track.target = st.spring_track_target;
            }
            st.feel_track.step(dt, damp, freq);
            const tr = u.alloc(300, 28);
            u.drawRectBorder(tr, u.theme.input_bg, u.theme.panel_border, 1);
            const knob_x = tr.x + 8 + (tr.w - 24) * st.feel_track.pos;
            u.drawRect(.{ .x = knob_x, .y = tr.y + 4, .w = 16, .h = tr.h - 8 }, u.theme.accent);

            u.separator();
            // 4) Meter pulse
            u.label(.{ .text = "4. Meter fill spring + shake on click" });
            if (u.button(.{ .id = "feel_fill", .label = "Pulse fill", .w = 120 })) {
                st.feel_meter.target = if (st.feel_meter.target > 0.5) 0.15 else 0.9;
                st.feel_meter.nudge(3);
            }
            st.feel_meter.step(dt, damp, freq);
            const mr = u.alloc(280, 18);
            u.drawRectBorder(mr, u.theme.input_bg, u.theme.panel_border, 1);
            const fw = (mr.w - 4) * std.math.clamp(st.feel_meter.pos, 0, 1);
            u.drawRect(.{ .x = mr.x + 2, .y = mr.y + 2, .w = fw, .h = mr.h - 4 }, u.theme.accent);
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
            u.separator();
            u.label(.{ .text = "Confirm modal — yes / no pattern" });
            if (u.button(.{ .id = "open_confirm", .label = "Delete item…" })) st.confirm_open = true;
            u.separator();
            u.label(.{ .text = "Prompt modal — text field + OK / Cancel" });
            if (u.button(.{ .id = "open_prompt", .label = "Rename…" })) st.prompt_open = true;
            if (st.prompt_len > 0) {
                var pb: [80]u8 = undefined;
                u.label(.{
                    .text = std.fmt.bufPrint(&pb, "Last prompt: {s}", .{st.prompt_buf[0..st.prompt_len]}) catch "",
                    .color = u.theme.accent,
                });
            }
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
            u.label(.{ .text = "Blender-style number slider (grab on hover)" });
            _ = u.slider(.{ .id = "sb_sp", .label = "Speed", .value = &st.speed });
            _ = u.slider(.{ .id = "sb_vo", .label = "Volume", .value = &st.volume, .min = 0, .max = 2 });
            _ = u.slider(.{ .id = "sb_layer", .label = "Layer", .value = &st.spinner_val, .min = 0, .max = 32, .w = 280 });
        } else if (eq(tab, "Spinner")) {
            u.label(.{ .text = "Spinner — indeterminate loading indicator" });
            u.spinner(.{ .size = 28, .label = "Loading…" });
            u.separator();
            u.label(.{ .text = "Building block for RequestState-style buttons later.", .color = u.theme.text_dim });
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
            u.label(.{ .text = "Tabs — horizontal page switcher" });
            const tab_items = [_][]const u8{ "General", "Graphics", "Audio" };
            _ = u.tabs(.{ .id = "tabs", .items = &tab_items, .selected = &st.tab_sel });
            u.separator();
            switch (st.tab_sel) {
                0 => u.label(.{ .text = "General settings placeholder" }),
                1 => u.label(.{ .text = "Graphics settings placeholder" }),
                else => u.label(.{ .text = "Audio settings placeholder" }),
            }
        } else if (eq(tab, "TextInput")) {
            u.label(.{ .text = "Single-line text input — caret, select, clipboard, undo" });
            _ = u.textInput(.{ .id = "sb_ti", .label = "Value", .buf = &st.text_buf, .len = &st.text_len, .w = 280 });
            u.label(.{ .text = st.text_buf[0..st.text_len], .color = u.theme.accent });
            u.separator();
            u.label(.{ .text = "Multi-line text area — soft wrap, multi-caret, column select, resize grip" });
            u.label(.{
                .text = "Alt+Shift+↑/↓: add caret · Alt+Shift+drag: column select · Tab: insert tab (or indent if selection) · Shift+Tab: outdent · Ctrl+D: next match",
                .color = u.theme.text_dim,
            });
            _ = u.textArea(.{
                .id = "sb_notes",
                .label = "Notes",
                .buf = &st.notes,
                .len = &st.notes_len,
                .w = @min(320, dw - 48),
                .rows = 3,
                .max_height = 160,
            });
            u.separator();
            u.label(.{ .text = "With hard-line numbers (gutter) — Tab inserts \\t mid-line; select lines then Tab to indent" });
            _ = u.textArea(.{
                .id = "sb_code",
                .label = "Code",
                .buf = &st.code_buf,
                .len = &st.code_len,
                .w = @min(360, dw - 48),
                .rows = 6,
                .max_height = 200,
                .line_numbers = true,
            });
        } else if (eq(tab, "ColorPicker")) {
            u.label(.{ .text = "ColorPicker — sinebow drag scrub; click to edit #hex" });
            u.label(.{
                .text = "Drag = rainbow hue · Click = type hex digits (Backspace) · # optional, auto-lowercased",
                .color = u.theme.text_dim,
            });
            _ = u.colorPicker(.{
                .id = "sb_cp",
                .label = "Accent",
                .color = &st.pick_color,
                .w = 280,
            });
            // Live swatch preview
            const sw = u.alloc(48, 48);
            u.drawRectBorder(sw, st.pick_color, u.theme.panel_border, 1);
            var hbuf: [7]u8 = undefined;
            const hs = color_picker.formatHex(st.pick_color, &hbuf);
            u.label(.{ .text = hs, .color = u.theme.text_dim });
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
            u.label(.{ .text = "Toast — transient corner notifications" });
            if (u.button(.{ .id = "t_ok", .label = "OK toast" })) u.toast("All good", .ok, 2);
            if (u.button(.{ .id = "t_info", .label = "Info toast" })) u.toast("FYI message", .info, 2);
            if (u.button(.{ .id = "t_warn", .label = "Warn toast" })) u.toast("Watch out", .warn, 2);
            if (u.button(.{ .id = "t_err", .label = "Error toast" })) u.toast("Something failed", .err, 2);
        } else if (eq(tab, "Toggle")) {
            u.label(.{ .text = "Toggle — binary switch control" });
            _ = u.toggle(.{ .id = "tog", .label = "Notifications", .value = &st.toggled });
        } else if (eq(tab, "Tree")) {
            u.label(.{ .text = "Tree — hierarchical nodes; click row to expand/collapse" });
            _ = u.treeNode(.{ .id = "sb_root", .label = "Root", .open = &st.world_open, .depth = 0 });
            if (st.world_open) {
                _ = u.treeNode(.{ .id = "sb_c1", .label = "Child A", .depth = 1 });
                _ = u.treeNode(.{ .id = "sb_c2", .label = "Child B", .open = &st.npcs_open, .depth = 1 });
                if (st.npcs_open) {
                    _ = u.treeNode(.{ .id = "sb_c3", .label = "Leaf", .depth = 2, .selected = true });
                }
            }
        } else if (eq(tab, "Password")) {
            u.label(.{ .text = "Password / secret — masked field + eye toggle" });
            _ = u.passwordInput(.{
                .id = "sb_pw",
                .label = "Secret",
                .buf = &st.pw_buf,
                .len = &st.pw_len,
                .show = &st.pw_show,
                .w = 280,
            });
            u.label(.{
                .text = if (st.pw_show) st.pw_buf[0..st.pw_len] else "(hidden)",
                .color = u.theme.text_dim,
            });
        } else if (eq(tab, "TagInput")) {
            u.label(.{ .text = "Tag input — chips + type; Enter or comma to add" });
            _ = u.tagInput(.{
                .id = "sb_tags",
                .label = "Tags",
                .tags = &st.tags,
                .tag_lens = &st.tag_lens,
                .tag_count = &st.tag_count,
                .buf = &st.tag_buf,
                .len = &st.tag_len,
                .w = 320,
            });
        } else if (eq(tab, "Typeahead")) {
            u.label(.{ .text = "Typeahead — filter list as you type; Enter picks first match" });
            _ = u.typeahead(.{
                .id = "sb_ta",
                .label = "Fruit",
                .buf = &st.ta_buf,
                .len = &st.ta_len,
                .items = &fruit,
                .selected = &st.ta_sel,
                .w = 280,
            });
        } else if (eq(tab, "Combobox")) {
            u.label(.{ .text = "Combobox — typeahead that shows full list while focused" });
            _ = u.combobox(.{
                .id = "sb_cb",
                .label = "Pick fruit",
                .buf = &st.cb_buf,
                .len = &st.cb_len,
                .items = &fruit,
                .selected = &st.cb_sel,
                .w = 280,
            });
        } else if (eq(tab, "KeyValue")) {
            u.label(.{ .text = "Key–value editor — add / edit / remove pairs" });
            _ = u.keyValueEditor(.{
                .id = "sb_kv",
                .label = "Headers",
                .keys = &st.kv_keys,
                .key_lens = &st.kv_key_lens,
                .vals = &st.kv_vals,
                .val_lens = &st.kv_val_lens,
                .count = &st.kv_count,
                .w = 400,
            });
        } else if (eq(tab, "MultiSelect")) {
            u.label(.{ .text = "Multi-select dropdown — checkbox menu" });
            _ = u.multiSelect(.{
                .id = "sb_ms",
                .label = "Permissions",
                .items = &ms_items,
                .selected = &st.ms_sel,
                .open = &st.ms_open,
                .w = 260,
            });
        } else if (eq(tab, "Segmented")) {
            u.label(.{ .text = "Segmented control — exclusive button group" });
            _ = u.segmented(.{
                .id = "sb_seg",
                .items = &.{ "Day", "Week", "Month", "Year" },
                .selected = &st.seg_sel,
                .w = 320,
            });
            var sbuf: [32]u8 = undefined;
            u.label(.{
                .text = std.fmt.bufPrint(&sbuf, "selected index={d}", .{st.seg_sel}) catch "",
                .color = u.theme.text_dim,
            });
        } else if (eq(tab, "IconButton")) {
            u.label(.{ .text = "Icon-only toolbar buttons" });
            u.beginHStack(.{ .h = 40 });
            if (u.iconButton(.{ .id = "ib_save", .icon = .save })) u.toast("save", .info, 1);
            if (u.iconButton(.{ .id = "ib_copy", .icon = .copy })) u.toast("copy", .info, 1);
            if (u.iconButton(.{ .id = "ib_trash", .icon = .trash })) u.toast("trash", .warn, 1);
            if (u.iconButton(.{ .id = "ib_set", .icon = .settings })) u.toast("settings", .info, 1);
            _ = u.endHStack();
            u.separator();
            u.label(.{ .text = "With labels" });
            _ = u.iconButton(.{ .id = "ib_lab", .icon = .download, .label = "Export" });
        } else if (eq(tab, "DropdownButton")) {
            u.label(.{ .text = "Dropdown button — main action + chevron menu" });
            if (u.dropdownButton(.{
                .id = "sb_ddb",
                .label = "Save",
                .items = &.{ "Save", "Save As…", "Export ZIP" },
                .open = &st.ddb_open,
            })) |pick| {
                if (pick < 0) u.toast("main: Save", .ok, 1.2) else {
                    var b: [32]u8 = undefined;
                    u.toast(std.fmt.bufPrint(&b, "menu {d}", .{pick}) catch "menu", .info, 1.2);
                }
            }
        } else if (eq(tab, "RequestButton")) {
            const rb = @import("../ui/components/requestButton.zig");
            u.label(.{ .text = "Request-state button — idle → loading → ok | err" });
            u.label(.{ .text = "Frozen states (one instance each):", .color = u.theme.text_dim });
            u.beginHStack(.{ .h = 40, .gap = 12 });
            _ = u.requestButton(.{ .id = "rb_f0", .label = "Submit", .force = rb.State.idle, .w = 110 });
            _ = u.requestButton(.{ .id = "rb_f1", .label = "Submit", .force = rb.State.loading, .w = 110 });
            _ = u.requestButton(.{ .id = "rb_f2", .label = "Submit", .force = rb.State.ok, .w = 110 });
            _ = u.requestButton(.{ .id = "rb_f3", .label = "Submit", .force = rb.State.err, .w = 110 });
            _ = u.endHStack();
            u.separator();
            u.label(.{ .text = "Live instance — click to cycle states (~1s each)" });
            // Drive live animation
            if (st.req_phase != 0 and st.req_t0 >= 0 and a.time - st.req_t0 >= 1.0) {
                if (st.req_phase == 1) {
                    st.req_state = if (st.req_to_err) .err else .ok;
                    st.req_phase = 2;
                    st.req_t0 = a.time;
                } else if (st.req_phase == 2) {
                    st.req_state = .idle;
                    st.req_phase = 0;
                    st.req_t0 = -1;
                    st.req_to_err = !st.req_to_err; // alternate ok/err next time
                }
            }
            if (u.requestButton(.{
                .id = "rb_live",
                .label = "Submit request",
                .label_loading = "Working…",
                .label_ok = "Success!",
                .label_err = "Failed",
                .state = &st.req_state,
                .w = 160,
            })) {
                st.req_state = .loading;
                st.req_phase = 1;
                st.req_t0 = a.time;
            }
            u.label(.{
                .text = "Next live result alternates ok / err",
                .color = u.theme.text_dim,
            });
        } else if (eq(tab, "Table")) {
            u.label(.{ .text = "Table — columns, row select, sort headers" });
            // sort cells copy for display
            var cells = table_cells;
            if (st.table_sort < 3) {
                // simple bubble sort demo on selected column
                var i: usize = 0;
                while (i + 1 < cells.len) : (i += 1) {
                    var j = i + 1;
                    while (j < cells.len) : (j += 1) {
                        const a_s = cells[i][st.table_sort];
                        const b_s = cells[j][st.table_sort];
                        const cmp = std.mem.order(u8, a_s, b_s);
                        const swap = if (st.table_asc) cmp == .gt else cmp == .lt;
                        if (swap) {
                            const tmp = cells[i];
                            cells[i] = cells[j];
                            cells[j] = tmp;
                        }
                    }
                }
            }
            const cell_views = [_][]const []const u8{
                &cells[0],
                &cells[1],
                &cells[2],
                &cells[3],
                &cells[4],
            };
            _ = u.table(.{
                .id = "sb_tbl",
                .columns = &table_cols,
                .cells = &cell_views,
                .selected = &st.table_sel,
                .sort_col = &st.table_sort,
                .sort_asc = &st.table_asc,
                .w = @min(420, dw - 40),
            });
            var tbuf: [32]u8 = undefined;
            u.label(.{
                .text = std.fmt.bufPrint(&tbuf, "selected row={d}", .{st.table_sel}) catch "",
                .color = u.theme.text_dim,
            });
        } else if (eq(tab, "Counter")) {
            u.label(.{ .text = "Counter / metric chips" });
            u.beginHStack(.{ .h = 56, .gap = 12 });
            u.counter(.{ .label = "entities", .value = 5 });
            u.counter(.{ .label = "fps", .value = @as(i32, @intFromFloat(if (a.dt > 0) 1.0 / a.dt else 0)), .color = u.theme.info });
            u.counter(.{ .label = "errors", .value = 0, .color = u.theme.danger });
            _ = u.endHStack();
        } else if (eq(tab, "Link")) {
            u.label(.{ .text = "Link — opens system browser when URL set" });
            _ = u.link(.{ .id = "lk1", .label = "https://ziglang.org", .url = "https://ziglang.org" });
            _ = u.link(.{ .id = "lk2", .label = "GitHub (gl1)", .url = "https://github.com/mikesmullin/gl1" });
            _ = u.link(.{ .id = "lk3", .label = "no-url (click only)", .url = "" });
        } else if (eq(tab, "ImageWell")) {
            const tex_mod = @import("../ui/tex.zig");
            u.label(.{ .text = "Image well — fire-dragon.png (non-square source)" });
            u.label(.{
                .text = "Same asset · square tiles · fit (contain) / stretch / fill (cover)",
                .color = u.theme.text_dim,
            });
            const dragon: ?*const tex_mod.Tex = if (a.demo_tex.ok) &a.demo_tex else null;
            u.beginHStack(.{ .h = 80, .gap = 16 });
            u.imageWell(.{ .w = 64, .h = 64, .tex = dragon, .fit = .fit, .label = "64 fit" });
            u.imageWell(.{ .w = 64, .h = 64, .tex = dragon, .fit = .stretch, .label = "64 stretch" });
            u.imageWell(.{ .w = 64, .h = 64, .tex = dragon, .fit = .fill, .label = "64 fill" });
            _ = u.endHStack();
            u.separator();
            u.label(.{ .text = "Larger tiles" });
            u.beginHStack(.{ .h = 140, .gap = 16 });
            u.imageWell(.{ .w = 120, .h = 120, .tex = dragon, .fit = .fit, .label = "fit" });
            u.imageWell(.{ .w = 120, .h = 120, .tex = dragon, .fit = .stretch, .label = "stretch" });
            u.imageWell(.{ .w = 120, .h = 120, .tex = dragon, .fit = .fill, .label = "fill" });
            _ = u.endHStack();
            u.separator();
            u.label(.{ .text = "Wide / tall destinations" });
            u.beginHStack(.{ .h = 100, .gap = 16 });
            u.imageWell(.{ .w = 160, .h = 72, .tex = dragon, .fit = .fit, .label = "wide fit" });
            u.imageWell(.{ .w = 72, .h = 96, .tex = dragon, .fit = .fill, .label = "tall fill" });
            u.imageWell(.{ .w = 64, .h = 64, .label = "no tex" });
            _ = u.endHStack();
        } else if (eq(tab, "Histogram")) {
            u.label(.{ .text = "Scrolling histogram — cold→hot by magnitude (transparent bg)" });
            u.histogram(.{ .samples = st.demo_hist[0..], .w = 280, .h = 24, .max_value = 1 });
            u.histogram(.{ .samples = st.demo_hist[0..], .w = 200, .h = 40, .max_value = 1 });
            u.separator();
            u.label(.{ .text = "Frame-time graph (live) — also on every scene, top-right HUD" });
            u.label(.{
                .text = "Bar height = frame ms; blue at low ms, red toward 50ms (steady 60fps ≈ cool)",
                .color = u.theme.text_dim,
            });
            var samples: [app.App.FtHist]f32 = undefined;
            const slice = a.frameTimeSamples(samples[0..]);
            var ov: [16]u8 = undefined;
            const ov_s: []const u8 = if (slice.len > 0 and slice[slice.len - 1] > 0.05)
                (std.fmt.bufPrint(&ov, "{d:.0}", .{1000.0 / slice[slice.len - 1]}) catch "")
            else
                "";
            u.histogram(.{ .samples = slice, .w = 120, .h = 24, .max_value = 50, .overlay = ov_s });
            st.demo_hist[@mod(@as(usize, @intFromFloat(a.time * 20)), st.demo_hist.len)] =
                0.2 + 0.6 * @abs(@sin(@as(f32, @floatCast(a.time * 3))));
        }
    }

    // Storybook-level modals
    if (u.beginModal(.{ .id = "sb_modal", .title = "Demo Modal", .open = &st.modal_open, .w = 400, .h = 220 })) {
        defer u.endModal();
        u.label(.{ .text = "This is a modal stack sample." });
        u.label(.{ .text = "Press Esc to close without quitting.", .color = u.theme.text_dim });
        if (u.button(.{ .id = "sb_modal_ok", .label = "Close" })) st.modal_open = false;
    }
    if (u.beginModal(.{ .id = "sb_confirm", .title = "Confirm delete", .open = &st.confirm_open, .w = 380, .h = 180 })) {
        defer u.endModal();
        u.label(.{ .text = "Delete this item permanently?" });
        u.label(.{ .text = "This cannot be undone.", .color = u.theme.danger });
        u.separator();
        u.beginHStack(.{ .h = 36, .gap = 10 });
        if (u.button(.{ .id = "cf_yes", .label = "Delete", .w = 100 })) {
            st.confirm_open = false;
            u.toast("Deleted", .warn, 1.5);
        }
        if (u.button(.{ .id = "cf_no", .label = "Cancel", .w = 100 })) st.confirm_open = false;
        _ = u.endHStack();
    }
    if (u.beginModal(.{ .id = "sb_prompt", .title = "Rename", .open = &st.prompt_open, .w = 400, .h = 200 })) {
        defer u.endModal();
        u.label(.{ .text = "Enter a new name:" });
        _ = u.textInput(.{ .id = "prompt_ti", .label = "Name", .buf = &st.prompt_buf, .len = &st.prompt_len, .w = 320 });
        u.beginHStack(.{ .h = 36, .gap = 10 });
        if (u.button(.{ .id = "pr_ok", .label = "OK", .w = 90 })) {
            st.prompt_open = false;
            u.toast("Renamed", .ok, 1.2);
        }
        if (u.button(.{ .id = "pr_cancel", .label = "Cancel", .w = 90 })) st.prompt_open = false;
        _ = u.endHStack();
    }
}
