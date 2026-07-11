const std = @import("std");

pub const SceneKind = enum {
    storybook,
    triangle,
    rects,
    text,
    widgets_basic,
    panels,
    layout,
    inspector,
    canvas,
};

pub const all = [_]SceneKind{
    .storybook,
    .triangle,
    .rects,
    .text,
    .widgets_basic,
    .panels,
    .layout,
    .inspector,
    .canvas,
};

pub fn parse(name: []const u8) ?SceneKind {
    return std.meta.stringToEnum(SceneKind, name);
}

pub fn nameOf(k: SceneKind) []const u8 {
    return @tagName(k);
}

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
    notes: [256]u8 = undefined,
    notes_len: usize = 0,
    show_console: bool = true,
    console_h: f32 = 120,
    /// Canvas scene pan/zoom.
    canvas_ox: f32 = 0,
    canvas_oy: f32 = 0,
    canvas_zoom: f32 = 1,
    canvas_panning: bool = false,

    pub fn init(self: *State) void {
        const hello = "hello gl1";
        @memcpy(self.text_buf[0..hello.len], hello);
        self.text_len = hello.len;
        const en = "Hero";
        @memcpy(self.entity_name[0..en.len], en);
        self.entity_name_len = en.len;
        const note = "Notes…";
        @memcpy(self.notes[0..note.len], note);
        self.notes_len = note.len;
    }
};
