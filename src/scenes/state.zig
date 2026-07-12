const std = @import("std");

pub const SceneKind = enum {
    canvas,
    storybook,
    text,
    triangle,
    panels,
};

pub const all = [_]SceneKind{
    .canvas,
    .storybook,
    .text,
    .triangle,
    .panels,
};

pub fn parse(name: []const u8) ?SceneKind {
    return std.meta.stringToEnum(SceneKind, name);
}

pub fn nameOf(k: SceneKind) []const u8 {
    return @tagName(k);
}

/// Floating desktop window for the panels scene.
pub const DeskWin = struct {
    open: bool = false,
    x: f32 = 80,
    y: f32 = 60,
    w: f32 = 300,
    h: f32 = 220,
};

/// Max simultaneous scene entities (selection mask is u32).
pub const max_entities: usize = 32;

/// Runtime scene object — edited in the canvas/editor inspector (in-memory only).
pub const WorldEntity = struct {
    alive: bool = false,
    name: [32]u8 = undefined,
    name_len: usize = 0,
    pos_x: f32 = 0,
    pos_y: f32 = 0,
    pos_z: f32 = 0,
    /// Euler degrees (Y used for cube yaw in the viewport).
    rot_x: f32 = 0,
    rot_y: f32 = 0,
    rot_z: f32 = 0,
    /// Uniform scale applied to base half-extent.
    scale: f32 = 1,
    half: f32 = 14,
    color: [4]f32 = .{ 0.5, 0.5, 0.5, 1 },

    pub fn setName(self: *WorldEntity, s: []const u8) void {
        const n = @min(s.len, self.name.len);
        @memcpy(self.name[0..n], s[0..n]);
        self.name_len = n;
    }

    pub fn nameSlice(self: *const WorldEntity) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn halfScaled(self: *const WorldEntity) f32 {
        return self.half * @max(0.05, self.scale);
    }
};

pub const State = struct {
    selected: usize = 0,
    checked: bool = true,
    checked_b: bool = false,
    checked_c: bool = true,
    toggled: bool = false,
    radio_group: u32 = 0,
    radio_group_b: u32 = 1,
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
    confirm_open: bool = false,
    prompt_open: bool = false,
    prompt_buf: [64]u8 = undefined,
    prompt_len: usize = 0,
    collab_a: bool = true,
    collab_b: bool = false,
    list_sel: usize = 1,
    spinner_val: f32 = 12,
    /// Storybook → Feel (springs) demo state.
    spring_btn_down: bool = false,
    spring_damp: f32 = 0.75,
    spring_freq: f32 = 10,
    spring_track_target: f32 = 0.5,
    /// Runtime spring channels (pos/vel); not serialized.
    feel_press: @import("../spring.zig").Spring1 = .{},
    feel_squash: @import("../spring.zig").Spring1 = .{ .pos = 1, .target = 1 },
    feel_follow: @import("../spring.zig").Spring2 = .{},
    feel_meter: @import("../spring.zig").Spring1 = .{},
    feel_track: @import("../spring.zig").Spring1 = .{ .pos = 0.5, .target = 0.5 },
    /// 0=dark, 1=cool, 2=warm (see theme.byIndex).
    theme_id: u32 = 0,
    /// Legacy bool kept in sync with theme_id for inspector/palette toggles.
    theme_cool: bool = false,
    color_idx: usize = 0,
    /// Storybook ColorPicker demo (RGBA 0..1).
    pick_color: [4]f32 = .{ 0.3, 0.85, 0.4, 1 },
    /// Storybook TextInput line-numbers example.
    code_buf: [512]u8 = undefined,
    code_len: usize = 0,

    // --- Storybook demos for new widgets ---
    pw_buf: [64]u8 = undefined,
    pw_len: usize = 0,
    pw_show: bool = false,
    tag_buf: [32]u8 = undefined,
    tag_len: usize = 0,
    tags: [12][24]u8 = undefined,
    tag_lens: [12]usize = @splat(0),
    tag_count: usize = 0,
    ta_buf: [48]u8 = undefined,
    ta_len: usize = 0,
    ta_sel: usize = 0,
    cb_buf: [48]u8 = undefined,
    cb_len: usize = 0,
    cb_sel: usize = 0,
    kv_keys: [8][32]u8 = undefined,
    kv_key_lens: [8]usize = @splat(0),
    kv_vals: [8][32]u8 = undefined,
    kv_val_lens: [8]usize = @splat(0),
    kv_count: usize = 2,
    ms_sel: [6]bool = .{ true, false, true, false, false, false },
    ms_open: bool = false,
    seg_sel: usize = 1,
    ddb_open: bool = false,
    req_state: @import("../ui/components/requestButton.zig").State = .idle,
    req_phase: u8 = 0, // 0 idle, 1 loading wait, 2 ok/err wait
    req_t0: f64 = -1,
    req_to_err: bool = false,
    table_sel: i32 = 0,
    table_sort: usize = 0,
    table_asc: bool = true,
    /// Accordion exclusive section (-1 = none).
    acc_open: i32 = 0,
    /// Storybook sidebar nav has keyboard focus (arrow up/down changes tab).
    sb_nav_focus: bool = false,
    /// Mini-browser storybook instances (lazy-init on first Browser tab visit).
    browser_ready: bool = false,
    browser_hello: @import("../ui/browser/browser.zig").BrowserDoc = .{},
    browser_table: @import("../ui/browser/browser.zig").BrowserDoc = .{},
    browser_news: @import("../ui/browser/browser.zig").BrowserDoc = .{},
    browser_flex: @import("../ui/browser/browser.zig").BrowserDoc = .{},
    browser_img: @import("../ui/browser/browser.zig").BrowserDoc = .{},
    browser_audio: @import("../ui/browser/browser.zig").BrowserDoc = .{},
    browser_video: @import("../ui/browser/browser.zig").BrowserDoc = .{},
    demo_hist: [48]f32 = undefined,
    /// Storybook splitter demo left width.
    sb_split_w: f32 = 160,
    sb_menu_status: [48]u8 = undefined,
    sb_menu_status_len: usize = 0,
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
    notes: [2048]u8 = undefined,
    notes_len: usize = 0,
    show_console: bool = true,
    console_h: f32 = 140,
    /// Canvas / editor — orbit camera (Blender-ish mini viewport).
    canvas_tx: f32 = 0,
    canvas_ty: f32 = 0,
    canvas_tz: f32 = 0,
    canvas_yaw: f32 = 0.6,
    canvas_pitch: f32 = -0.55,
    canvas_dist: f32 = 420,
    canvas_ox: f32 = 0,
    canvas_oy: f32 = 0,
    canvas_zoom: f32 = 1,
    canvas_panning: bool = false,
    canvas_orbiting: bool = false,
    canvas_strafing: bool = false,
    canvas_sel_mask: u32 = 0,
    canvas_sel_primary: i32 = -1,
    canvas_frame: @import("../anim.zig").Parallel = .{},

    /// Live scene graph (editable from editor panels + viewport).
    entities: [max_entities]WorldEntity = undefined,
    next_entity_serial: u32 = 1,

    /// Editor chrome (floating panels over the canvas).
    editor_tree_open: bool = true,
    editor_inspector_open: bool = true,
    editor_console_open: bool = true,
    /// Last frame had a non-empty selection (for auto-expand inspector).
    editor_had_selection: bool = false,
    editor_tree_w: f32 = 220,
    editor_insp_w: f32 = 280,
    /// Last selection mask we synced name edit buffer from.
    editor_name_sync_mask: u32 = 0xFFFFFFFF,
    /// Scratch buffer for multi-edit name field.
    editor_name_buf: [32]u8 = undefined,
    editor_name_len: usize = 0,
    /// Previous-frame hit rects so 3D pick ignores UI (set while drawing panels).
    editor_hit_tree: DeskWin = .{ .open = true, .x = 8, .y = 8, .w = 220, .h = 400 },
    editor_hit_insp: DeskWin = .{ .open = true, .x = 800, .y = 8, .w = 280, .h = 400 },
    editor_hit_console: DeskWin = .{ .open = true, .x = 8, .y = 560, .w = 1000, .h = 140 },

    /// Panels scene — desktop windows (positions remembered while open/closed).
    desk_a: DeskWin = .{ .open = true, .x = 40, .y = 40, .w = 300, .h = 220 },
    desk_b: DeskWin = .{ .open = true, .x = 380, .y = 80, .w = 320, .h = 260 },
    desk_c: DeskWin = .{ .open = false, .x = 200, .y = 140, .w = 280, .h = 200 },
    desk_drag: i32 = -1, // which window: 0=a,1=b,2=c
    desk_resize: i32 = -1,
    desk_drag_ox: f32 = 0,
    desk_drag_oy: f32 = 0,
    desk_resize_sw: f32 = 0,
    desk_resize_sh: f32 = 0,

    pub fn init(self: *State) void {
        const hello = "hello gl1";
        @memcpy(self.text_buf[0..hello.len], hello);
        self.text_len = hello.len;
        const en = "Hero";
        @memcpy(self.entity_name[0..en.len], en);
        self.entity_name_len = en.len;
        const note =
            \\Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
        ;
        @memcpy(self.notes[0..note.len], note);
        self.notes_len = note.len;
        const code =
            \\// line numbers demo
            \\fn main() void {
            \\    const msg = "hello";
            \\    _ = msg;
            \\}
        ;
        @memcpy(self.code_buf[0..code.len], code);
        self.code_len = code.len;
        const secret = "hunter2";
        @memcpy(self.pw_buf[0..secret.len], secret);
        self.pw_len = secret.len;
        // seed tags
        const t0 = "zig";
        const t1 = "sokol";
        @memcpy(self.tags[0][0..t0.len], t0);
        self.tag_lens[0] = t0.len;
        @memcpy(self.tags[1][0..t1.len], t1);
        self.tag_lens[1] = t1.len;
        self.tag_count = 2;
        const k0 = "host";
        const v0 = "localhost";
        @memcpy(self.kv_keys[0][0..k0.len], k0);
        self.kv_key_lens[0] = k0.len;
        @memcpy(self.kv_vals[0][0..v0.len], v0);
        self.kv_val_lens[0] = v0.len;
        const k1 = "port";
        const v1 = "8080";
        @memcpy(self.kv_keys[1][0..k1.len], k1);
        self.kv_key_lens[1] = k1.len;
        @memcpy(self.kv_vals[1][0..v1.len], v1);
        self.kv_val_lens[1] = v1.len;
        self.kv_count = 2;
        // demo histogram wave
        for (&self.demo_hist, 0..) |*s, i| {
            const t = @as(f32, @floatFromInt(i)) / 48.0;
            s.* = 0.3 + 0.5 * @sin(t * 6.28) * @sin(t * 12.0);
            if (s.* < 0) s.* = -s.*;
        }
        self.initWorld();
    }

    pub fn initWorld(self: *State) void {
        self.entities = std.mem.zeroes([max_entities]WorldEntity);
        self.next_entity_serial = 1;
        const seed = [_]struct {
            name: []const u8,
            x: f32,
            y: f32,
            z: f32,
            half: f32,
            color: [4]f32,
        }{
            .{ .name = "Hero", .x = 120, .y = 14, .z = -40, .half = 16, .color = .{ 0.3, 0.85, 0.4, 1 } },
            .{ .name = "Slime", .x = -80, .y = 18, .z = 90, .half = 18, .color = .{ 0.3, 0.5, 0.95, 1 } },
            .{ .name = "Torch", .x = 200, .y = 12, .z = 140, .half = 12, .color = .{ 0.95, 0.8, 0.2, 1 } },
            .{ .name = "Crystal", .x = -160, .y = 22, .z = -100, .half = 20, .color = .{ 0.75, 0.4, 0.9, 1 } },
            .{ .name = "Crate", .x = 40, .y = 16, .z = 60, .half = 14, .color = .{ 0.9, 0.55, 0.2, 1 } },
        };
        for (seed, 0..) |s, i| {
            self.entities[i].alive = true;
            self.entities[i].setName(s.name);
            self.entities[i].pos_x = s.x;
            self.entities[i].pos_y = s.y;
            self.entities[i].pos_z = s.z;
            self.entities[i].half = s.half;
            self.entities[i].color = s.color;
            self.entities[i].scale = 1;
        }
        self.next_entity_serial = @intCast(seed.len + 1);
        self.canvas_sel_mask = 0;
        self.canvas_sel_primary = -1;
    }

    pub fn isSelected(self: *const State, i: usize) bool {
        if (i >= max_entities) return false;
        return (self.canvas_sel_mask & (@as(u32, 1) << @intCast(i))) != 0 and self.entities[i].alive;
    }

    pub fn setSelected(self: *State, i: usize, on: bool) void {
        if (i >= max_entities) return;
        const bit = @as(u32, 1) << @intCast(i);
        if (on) self.canvas_sel_mask |= bit else self.canvas_sel_mask &= ~bit;
    }

    pub fn clearSelection(self: *State) void {
        self.canvas_sel_mask = 0;
        self.canvas_sel_primary = -1;
    }

    pub fn selectionCount(self: *const State) u32 {
        var n: u32 = 0;
        var i: usize = 0;
        while (i < max_entities) : (i += 1) {
            if (self.isSelected(i)) n += 1;
        }
        return n;
    }

    pub fn aliveCount(self: *const State) usize {
        var n: usize = 0;
        for (self.entities) |e| {
            if (e.alive) n += 1;
        }
        return n;
    }

    pub fn addEntity(self: *State, name: []const u8, x: f32, y: f32, z: f32) ?usize {
        var i: usize = 0;
        while (i < max_entities) : (i += 1) {
            if (!self.entities[i].alive) {
                self.entities[i] = .{};
                self.entities[i].alive = true;
                self.entities[i].setName(name);
                self.entities[i].pos_x = x;
                self.entities[i].pos_y = y;
                self.entities[i].pos_z = z;
                self.entities[i].half = 14;
                self.entities[i].scale = 1;
                self.entities[i].color = .{ 0.55, 0.75, 0.55, 1 };
                self.next_entity_serial +%= 1;
                return i;
            }
        }
        return null;
    }

    pub fn deleteSelected(self: *State) u32 {
        var n: u32 = 0;
        var i: usize = 0;
        while (i < max_entities) : (i += 1) {
            if (self.isSelected(i)) {
                self.entities[i].alive = false;
                self.entities[i].name_len = 0;
                n += 1;
            }
        }
        self.clearSelection();
        return n;
    }

    pub fn selectAllAlive(self: *State) void {
        var mask: u32 = 0;
        var primary: i32 = -1;
        var i: usize = 0;
        while (i < max_entities) : (i += 1) {
            if (self.entities[i].alive) {
                mask |= @as(u32, 1) << @intCast(i);
                if (primary < 0) primary = @intCast(i);
            }
        }
        self.canvas_sel_mask = mask;
        self.canvas_sel_primary = primary;
    }

    pub fn pointerOverEditorUi(self: *const State, mx: f32, my: f32) bool {
        const hits = [_]DeskWin{ self.editor_hit_tree, self.editor_hit_insp, self.editor_hit_console };
        for (hits) |hw| {
            if (!hw.open) continue;
            if (mx >= hw.x and mx < hw.x + hw.w and my >= hw.y and my < hw.y + hw.h) return true;
        }
        // Collapsed expand chips (tree top-left / inspector top-right) live in hit rects when open flags set.
        return false;
    }
};
