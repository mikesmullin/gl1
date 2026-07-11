const std = @import("std");

pub const SceneKind = enum {
    inspector,
    canvas,
    storybook,
    text,
    triangle,
    panels,
};

pub const all = [_]SceneKind{
    .inspector,
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
    collab_a: bool = true,
    collab_b: bool = false,
    list_sel: usize = 1,
    spinner_val: f32 = 12,
    /// 0=dark, 1=cool, 2=warm (see theme.byIndex).
    theme_id: u32 = 0,
    /// Legacy bool kept in sync with theme_id for inspector/palette toggles.
    theme_cool: bool = false,
    color_idx: usize = 0,
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
    notes: [512]u8 = undefined,
    notes_len: usize = 0,
    show_console: bool = true,
    console_h: f32 = 120,
    /// Canvas scene — orbit camera (Blender-ish mini viewport).
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
    }
};
