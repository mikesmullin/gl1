//! Editor chrome over the canvas: scene tree, inspector, console.
//! Floating panels (fixed edges for now; docking later).

const std = @import("std");
const app = @import("../app.zig");
const ui = @import("../ui/ui.zig");
const state = @import("state.zig");
const util = @import("util.zig");

const MixedF = struct {
    value: f32,
    mixed: bool,
};

fn aggF(st: *const state.State, comptime field: []const u8) MixedF {
    var first = true;
    var v: f32 = 0;
    var mixed = false;
    var i: usize = 0;
    while (i < state.max_entities) : (i += 1) {
        if (!st.isSelected(i)) continue;
        const e = st.entities[i];
        const ev = @field(e, field);
        if (first) {
            v = ev;
            first = false;
        } else if (@abs(ev - v) > 1e-4) {
            mixed = true;
        }
    }
    return .{ .value = v, .mixed = mixed };
}

fn applyF(st: *state.State, comptime field: []const u8, v: f32) void {
    var i: usize = 0;
    while (i < state.max_entities) : (i += 1) {
        if (!st.isSelected(i)) continue;
        @field(st.entities[i], field) = v;
    }
}

/// Relative multi-edit: add the same delta to each selected entity (clamped).
fn applyDeltaF(st: *state.State, comptime field: []const u8, delta: f32, min: f32, max: f32) void {
    if (delta == 0) return;
    var i: usize = 0;
    while (i < state.max_entities) : (i += 1) {
        if (!st.isSelected(i)) continue;
        const cur = @field(st.entities[i], field);
        @field(st.entities[i], field) = std.math.clamp(cur + delta, min, max);
    }
}

fn namesAgree(st: *const state.State) struct { same: bool, sample: []const u8 } {
    var first = true;
    var sample: []const u8 = "";
    var i: usize = 0;
    while (i < state.max_entities) : (i += 1) {
        if (!st.isSelected(i)) continue;
        const n = st.entities[i].nameSlice();
        if (first) {
            sample = n;
            first = false;
        } else if (!std.mem.eql(u8, n, sample)) {
            return .{ .same = false, .sample = sample };
        }
    }
    return .{ .same = !first, .sample = sample };
}

fn syncNameBuffer(st: *state.State) void {
    if (st.editor_name_sync_mask == st.canvas_sel_mask) return;
    st.editor_name_sync_mask = st.canvas_sel_mask;
    const nsel = st.selectionCount();
    if (nsel == 0) {
        st.editor_name_len = 0;
        return;
    }
    const ag = namesAgree(st);
    if (ag.same) {
        const n = @min(ag.sample.len, st.editor_name_buf.len);
        @memcpy(st.editor_name_buf[0..n], ag.sample[0..n]);
        st.editor_name_len = n;
    } else {
        const h = "-";
        @memcpy(st.editor_name_buf[0..h.len], h);
        st.editor_name_len = h.len;
    }
}

fn applyName(st: *state.State) void {
    const name = st.editor_name_buf[0..st.editor_name_len];
    if (std.mem.eql(u8, name, "-")) return;
    var i: usize = 0;
    while (i < state.max_entities) : (i += 1) {
        if (!st.isSelected(i)) continue;
        st.entities[i].setName(name);
    }
}

const MixedColor = struct {
    value: [4]f32,
    mixed: bool,
};

fn aggColor(st: *const state.State) MixedColor {
    var first = true;
    var v: [4]f32 = .{ 0.5, 0.5, 0.5, 1 };
    var mixed = false;
    var i: usize = 0;
    while (i < state.max_entities) : (i += 1) {
        if (!st.isSelected(i)) continue;
        const c = st.entities[i].color;
        if (first) {
            v = c;
            first = false;
        } else {
            var k: usize = 0;
            while (k < 4) : (k += 1) {
                if (@abs(c[k] - v[k]) > 1e-3) mixed = true;
            }
        }
    }
    return .{ .value = v, .mixed = mixed };
}

fn applyColor(st: *state.State, c: [4]f32) void {
    var i: usize = 0;
    while (i < state.max_entities) : (i += 1) {
        if (!st.isSelected(i)) continue;
        st.entities[i].color = c;
    }
}

/// Scratch color for the inspector picker (synced from selection when mask changes).
var insp_color: [4]f32 = .{ 0.5, 0.5, 0.5, 1 };
var insp_color_mask: u32 = 0xFFFFFFFF;

fn colorPickerRow(u: *ui.Ui, st: *state.State, id: []const u8, label: []const u8, w: f32) void {
    const ag = aggColor(st);
    if (st.canvas_sel_mask != insp_color_mask) {
        insp_color_mask = st.canvas_sel_mask;
        insp_color = ag.value;
    }
    // Show "-" when selection has mixed colors (drag/click still writes one color to all).
    if (u.colorPicker(.{
        .id = id,
        .label = label,
        .color = &insp_color,
        .display_override = if (ag.mixed) "-" else null,
        .w = w,
    })) {
        applyColor(st, insp_color);
        insp_color_mask = st.canvas_sel_mask;
    }
}

/// Header row with title left and a collapse icon float-right.
fn panelHeaderCollapse(u: anytype, title: []const u8, collapse_id: []const u8, icon: ui.IconId) bool {
    const row_h = u.theme.row_h;
    const row = u.alloc(0, row_h);
    u.drawText(row.x, row.y + 6, u.theme.title_font_size, u.theme.text, title);
    const btn_w: f32 = 28;
    const br = ui.Rect{
        .x = row.x + row.w - btn_w,
        .y = row.y + 2,
        .w = btn_w,
        .h = row_h - 4,
    };
    const stt = u.interact(u.id(collapse_id), br, false);
    u.drawRect(br, if (stt.hot) u.theme.button_hot else u.theme.button);
    u.drawIcon(br.x + (br.w - 18) * 0.5, br.y + (br.h - 18) * 0.5, 18, icon, null);
    if (stt.hot) u.setSoftCursor(.cursor_hand_open);
    return stt.clicked;
}

/// Numeric property slider. Multi-select uses *relative* deltas (preserve offsets / show "-").
fn floatSlider(u: anytype, st: *state.State, id: []const u8, label: []const u8, comptime field: []const u8, min: f32, max: f32, w: f32) void {
    const nsel = st.selectionCount();
    const multi_rel = nsel > 1;
    const ag = aggF(st, field);
    // Drag anchor for the widget: first selected value (or shared value when not mixed).
    var tmp = ag.value;
    const ov: ?[]const u8 = if (ag.mixed) "-" else null;
    const before = tmp;
    if (u.slider(.{ .id = id, .label = label, .value = &tmp, .display_override = ov, .min = min, .max = max, .w = w })) {
        if (multi_rel) {
            // Slider moves from the first entity's value; map that motion onto every selection as a delta.
            const delta = tmp - before;
            applyDeltaF(st, field, delta, min, max);
        } else {
            applyF(st, field, tmp);
        }
    }
}

/// Draw floating editor UI on top of the 3D canvas. Updates hit rects for pick blocking.
pub fn draw(a: *app.App) void {
    const u = &a.ui;
    const st = &a.scene_state;
    const margin: f32 = 8;
    const tree_w = st.editor_tree_w;
    const insp_w = st.editor_insp_w;
    const console_h: f32 = if (st.editor_console_open) st.console_h else 0;
    const top: f32 = margin;
    const bot = if (st.editor_console_open) console_h + margin + 4 else margin;
    const body_h = a.height - top - bot;

    const nsel = st.selectionCount();

    // Inspector: auto-collapse when nothing selected; auto-expand when selection appears.
    if (nsel == 0) {
        st.editor_inspector_open = false;
    } else if (!st.editor_had_selection) {
        st.editor_inspector_open = true;
    }
    st.editor_had_selection = nsel > 0;

    // --- Scene tree (left) ---
    if (!st.editor_tree_open) {
        const chip = ui.Rect{ .x = 6, .y = 6, .w = 22, .h = 22 };
        const stt = u.interact(u.id("ed_tree_expand"), chip, false);
        u.drawRectBorder(chip, if (stt.hot) u.theme.button_hot else u.theme.panel, u.theme.accent, 1);
        // Collapsed panel chip: caret-right (expand).
        u.drawIcon(chip.x + 2, chip.y + 2, 18, .arrow_right, null);
        if (stt.clicked) st.editor_tree_open = true;
        st.editor_hit_tree = .{ .open = true, .x = chip.x, .y = chip.y, .w = chip.w, .h = chip.h };
    } else {
        const tree_x = margin;
        const tree_y = top;
        const tree_h = body_h;
        st.editor_hit_tree = .{ .open = true, .x = tree_x, .y = tree_y, .w = tree_w, .h = tree_h };

        if (u.beginPanel(.{ .id = "ed_tree", .x = tree_x, .y = tree_y, .w = tree_w, .h = tree_h, .scroll = true })) {
            defer u.endPanel();

            if (panelHeaderCollapse(u, "Entities", "ed_tree_collapse", .arrow_left)) {
                st.editor_tree_open = false;
            }

            _ = u.searchField(.{
                .id = "ed_filter",
                .buf = &st.filter_buf,
                .len = &st.filter_len,
                .placeholder = "Filter…",
                .w = tree_w - 28,
            });

            if (u.button(.{ .id = "ed_add", .label = "+ Add Entity", .w = tree_w - 28 })) {
                var nbuf: [24]u8 = undefined;
                const nm = std.fmt.bufPrint(&nbuf, "Entity {d}", .{st.next_entity_serial}) catch "Entity";
                if (st.addEntity(nm, st.canvas_tx, st.canvas_ty + 16, st.canvas_tz)) |idx| {
                    st.clearSelection();
                    st.setSelected(idx, true);
                    st.canvas_sel_primary = @intCast(idx);
                    u.log("spawned entity");
                    u.toast("Added entity", .ok, 1.2);
                } else {
                    u.toast("Entity limit reached", .warn, 1.5);
                }
            }

            u.separator();
            u.label(.{ .text = "Scene", .color = u.theme.text_dim });

            const needle = st.filter_buf[0..st.filter_len];
            var i: usize = 0;
            while (i < state.max_entities) : (i += 1) {
                const e = &st.entities[i];
                if (!e.alive) continue;
                const name = e.nameSlice();
                if (needle.len > 0 and !util.containsIgnoreCase(name, needle)) continue;

                var idb: [24]u8 = undefined;
                const id = std.fmt.bufPrint(&idb, "ed_ent{d}", .{i}) catch "ed_ent";
                const sel = st.isSelected(i);
                if (u.treeNode(.{ .id = id, .label = name, .depth = 0, .selected = sel }).clicked) {
                    const multi = u.input.ctrl or u.input.shift;
                    if (multi) {
                        st.setSelected(i, !sel);
                        if (!sel) st.canvas_sel_primary = @intCast(i);
                    } else {
                        st.clearSelection();
                        st.setSelected(i, true);
                        st.canvas_sel_primary = @intCast(i);
                    }
                }
            }

            if (st.aliveCount() == 0) {
                u.label(.{ .text = "(empty scene)", .color = u.theme.text_dim });
            }
        }
    }

    // --- Inspector (right) ---
    if (nsel == 0) {
        // Fully tucked away while nothing is selected.
        st.editor_hit_insp = .{ .open = false, .x = 0, .y = 0, .w = 0, .h = 0 };
    } else if (!st.editor_inspector_open) {
        // User-collapsed while selection exists — chip to re-open.
        // Sit below the scene/fps HUD label (~y=8) so the icon stays visible.
        const chip = ui.Rect{ .x = a.width - 28, .y = 26, .w = 22, .h = 22 };
        const stt = u.interact(u.id("ed_insp_expand"), chip, false);
        u.drawRectBorder(chip, if (stt.hot) u.theme.button_hot else u.theme.panel, u.theme.accent, 1);
        // arrow_right art renders pointing left (axis inversion on filled arrows).
        u.drawIcon(chip.x + 2, chip.y + 2, 18, .arrow_right, null);
        if (stt.clicked) st.editor_inspector_open = true;
        st.editor_hit_insp = .{ .open = true, .x = chip.x, .y = chip.y, .w = chip.w, .h = chip.h };
    } else {
        const insp_x = a.width - insp_w - margin;
        const insp_y = top;
        const insp_h = body_h;
        st.editor_hit_insp = .{ .open = true, .x = insp_x, .y = insp_y, .w = insp_w, .h = insp_h };

        if (u.beginPanel(.{ .id = "ed_insp", .x = insp_x, .y = insp_y, .w = insp_w, .h = insp_h, .scroll = true })) {
            defer u.endPanel();

            if (panelHeaderCollapse(u, "Inspector", "ed_insp_collapse", .arrow_right)) {
                st.editor_inspector_open = false;
            }

            var hbuf: [48]u8 = undefined;
            u.label(.{
                .text = std.fmt.bufPrint(&hbuf, "{d} selected", .{nsel}) catch "",
                .color = u.theme.text_dim,
            });
            u.separator();

            syncNameBuffer(st);
            const ag_name = namesAgree(st);
            const name_label = if (nsel > 1 and !ag_name.same) "Name (mixed)" else "Name";
            if (u.textInput(.{
                .id = "ed_name",
                .label = name_label,
                .buf = &st.editor_name_buf,
                .len = &st.editor_name_len,
                .w = insp_w - 36,
            })) {
                applyName(st);
                st.editor_name_sync_mask = st.canvas_sel_mask;
            }

            u.separator();
            u.label(.{ .text = "Transform", .color = u.theme.text_dim });
            if (nsel > 1) {
                u.label(.{ .text = "Sliders apply relative deltas", .color = u.theme.text_dim });
            }
            const sw = insp_w - 36;
            floatSlider(u, st, "ed_px", "Pos X", "pos_x", -500, 500, sw);
            floatSlider(u, st, "ed_py", "Pos Y", "pos_y", -200, 200, sw);
            floatSlider(u, st, "ed_pz", "Pos Z", "pos_z", -500, 500, sw);
            floatSlider(u, st, "ed_rx", "Rot X", "rot_x", -180, 180, sw);
            floatSlider(u, st, "ed_ry", "Rot Y", "rot_y", -180, 180, sw);
            floatSlider(u, st, "ed_rz", "Rot Z", "rot_z", -180, 180, sw);
            floatSlider(u, st, "ed_sc", "Scale", "scale", 0.1, 4.0, sw);

            u.separator();
            u.label(.{ .text = "Appearance", .color = u.theme.text_dim });
            colorPickerRow(u, st, "ed_col", "Color", sw);

            u.separator();
            u.label(.{ .text = "Delete removes selection (Del key)", .color = u.theme.text_dim });
        }
    }

    // --- Bottom: Console ---
    st.editor_hit_console.open = st.editor_console_open;
    if (st.editor_console_open) {
        const ch = st.console_h;
        const cx = margin;
        const cy = a.height - ch - margin;
        const cw = a.width - margin * 2;
        st.editor_hit_console = .{ .open = true, .x = cx, .y = cy, .w = cw, .h = ch };

        u.drawRectBorder(.{ .x = cx, .y = cy, .w = cw, .h = ch }, u.theme.panel, u.theme.panel_border, 1);
        u.drawRect(.{ .x = cx, .y = cy, .w = cw, .h = 24 }, .{ 0.16, 0.17, 0.21, 1 });
        u.drawText(cx + 8, cy + 5, u.theme.font_size, u.theme.text, "Console");
        const cr = ui.Rect{ .x = cx + cw - 36, .y = cy + 2, .w = 28, .h = 20 };
        const cst = u.interact(u.id("ed_con_collapse"), cr, false);
        u.drawRect(cr, if (cst.hot) u.theme.button_hot else u.theme.button);
        // Open console: caret-down (collapse).
        u.drawIcon(cr.x + 6, cr.y + 2, 14, .arrow_down, null);
        if (cst.clicked) st.editor_console_open = false;

        u.console(.{
            .id = "ed_log",
            .x = cx + 2,
            .y = cy + 24,
            .w = cw - 4,
            .h = ch - 26,
        });
    } else {
        const bar = ui.Rect{ .x = margin, .y = a.height - 22 - margin, .w = 120, .h = 20 };
        st.editor_hit_console = .{ .open = true, .x = bar.x, .y = bar.y, .w = bar.w, .h = bar.h };
        const bst = u.interact(u.id("ed_con_expand"), bar, false);
        u.drawRectBorder(bar, if (bst.hot) u.theme.button_hot else u.theme.panel, u.theme.panel_border, 1);
        // Collapsed: caret-up (click to expand).
        u.drawIcon(bar.x + 6, bar.y + 2, 14, .arrow_up, null);
        u.drawText(bar.x + 24, bar.y + 3, 1.5, u.theme.text_dim, "Console");
        if (bst.clicked) st.editor_console_open = true;
    }
}
