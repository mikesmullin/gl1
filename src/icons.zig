//! Icon atlas loaded from assets/icons (PNG + YAML manifest).
//! Prefer runtime files under `assets/icons/` (edit + restart, no rebuild).
//! Falls back to compile-time embed when files are missing.

const std = @import("std");
const png = @import("png.zig");
const yaml = @import("yaml_mini.zig");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sgl = sokol.gl;

pub const IconId = enum {
    // cursors
    cursor_arrow,
    cursor_hand_open,
    cursor_hand_closed,
    cursor_text,
    cursor_cross,
    cursor_resize_h,
    cursor_resize_v,
    cursor_resize_nwse,
    cursor_resize_nesw,
    cursor_busy,
    // carets / chrome (also used for tree expand/collapse)
    arrow_down,
    arrow_up,
    arrow_left,
    arrow_right,
    // tree / dirs
    tree_leaf,
    folder,
    folder_open,
    // ui
    check,
    close,
    plus,
    minus,
    search,
    settings,
    home,
    save,
    copy,
    paste,
    trash,
    eye,
    lock,
    star,
    download,
    // emoji
    emoji_smile,
    emoji_heart,
    emoji_laugh,
    emoji_thumbs_up,
    emoji_fire,
    emoji_party,
    emoji_cry,
    emoji_think,
    emoji_clap,
    emoji_100,
    // compass / long arrows (from sheet row 2)
    arrow_s,
    arrow_n,
    arrow_w,
    arrow_e,
    long_arrow_w,
    long_arrow_e,
    // chevrons (row 8)
    chevron_s,
    chevron_n,
    chevron_s_dark,
    chevron_n_dark,

    pub fn name(self: IconId) []const u8 {
        return @tagName(self);
    }

    pub fn fromName(s: []const u8) ?IconId {
        // Canonical hyphen aliases + legacy underscore / short forms
        if (std.mem.eql(u8, s, "caret-down") or std.mem.eql(u8, s, "v")) return .arrow_down;
        if (std.mem.eql(u8, s, "caret-up") or std.mem.eql(u8, s, "^")) return .arrow_up;
        if (std.mem.eql(u8, s, "caret-left") or std.mem.eql(u8, s, "<")) return .arrow_left;
        if (std.mem.eql(u8, s, "caret-right") or std.mem.eql(u8, s, ">")) return .arrow_right;
        // hand = open palm; grab = closed fist (legacy name was "grabbing")
        if (std.mem.eql(u8, s, "hand")) return .cursor_hand_open;
        if (std.mem.eql(u8, s, "grab") or std.mem.eql(u8, s, "grabbing")) return .cursor_hand_closed;
        if (std.mem.eql(u8, s, "pointer")) return .cursor_arrow;
        if (std.mem.eql(u8, s, "ibeam") or std.mem.eql(u8, s, "text")) return .cursor_text;
        if (std.mem.eql(u8, s, "crosshair")) return .cursor_cross;
        if (std.mem.eql(u8, s, "resize-ew") or std.mem.eql(u8, s, "resize_ew")) return .cursor_resize_h;
        if (std.mem.eql(u8, s, "resize-ns") or std.mem.eql(u8, s, "resize_ns")) return .cursor_resize_v;
        if (std.mem.eql(u8, s, "resize-nwse") or std.mem.eql(u8, s, "resize_nwse")) return .cursor_resize_nwse;
        if (std.mem.eql(u8, s, "resize-nesw") or std.mem.eql(u8, s, "resize_nesw")) return .cursor_resize_nesw;
        if (std.mem.eql(u8, s, "wait")) return .cursor_busy;
        // tree-closed / tree-open removed — same art as caret-right / caret-down
        if (std.mem.eql(u8, s, "tree-closed") or std.mem.eql(u8, s, "tree_closed")) return .arrow_right;
        if (std.mem.eql(u8, s, "tree-open") or std.mem.eql(u8, s, "tree_open")) return .arrow_down;
        if (std.mem.eql(u8, s, "dir-open") or std.mem.eql(u8, s, "dir_open")) return .folder_open;
        if (std.mem.eql(u8, s, "dir")) return .folder;
        if (std.mem.eql(u8, s, "ok") or std.mem.eql(u8, s, "tick")) return .check;
        if (std.mem.eql(u8, s, "x") or std.mem.eql(u8, s, "cancel")) return .close;
        if (std.mem.eql(u8, s, "plus") or std.mem.eql(u8, s, "add")) return .plus;
        if (std.mem.eql(u8, s, "minus") or std.mem.eql(u8, s, "subtract") or std.mem.eql(u8, s, "remove")) return .minus;
        if (std.mem.eql(u8, s, "find") or std.mem.eql(u8, s, "filter")) return .search;
        if (std.mem.eql(u8, s, "gear") or std.mem.eql(u8, s, "cog")) return .settings;
        if (std.mem.eql(u8, s, "disk")) return .save;
        if (std.mem.eql(u8, s, "delete")) return .trash;
        if (std.mem.eql(u8, s, "eye") or std.mem.eql(u8, s, "visible")) return .eye;
        if (std.mem.eql(u8, s, "leaf")) return .tree_leaf;
        if (std.mem.eql(u8, s, "download")) return .download;
        if (std.mem.eql(u8, s, "smile")) return .emoji_smile;
        if (std.mem.eql(u8, s, "heart")) return .emoji_heart;
        if (std.mem.eql(u8, s, "joy")) return .emoji_laugh;
        if (std.mem.eql(u8, s, "thumbs-up") or std.mem.eql(u8, s, "thumbsup")) return .emoji_thumbs_up;
        if (std.mem.eql(u8, s, "fire")) return .emoji_fire;
        if (std.mem.eql(u8, s, "tada")) return .emoji_party;
        if (std.mem.eql(u8, s, "sad")) return .emoji_cry;
        if (std.mem.eql(u8, s, "thinking")) return .emoji_think;
        if (std.mem.eql(u8, s, "clap")) return .emoji_clap;
        if (std.mem.eql(u8, s, "hundred")) return .emoji_100;
        if (std.mem.eql(u8, s, "arrow-s")) return .arrow_s;
        if (std.mem.eql(u8, s, "arrow-n")) return .arrow_n;
        if (std.mem.eql(u8, s, "arrow-w")) return .arrow_w;
        if (std.mem.eql(u8, s, "arrow-e")) return .arrow_e;
        if (std.mem.eql(u8, s, "long-arrow-w")) return .long_arrow_w;
        if (std.mem.eql(u8, s, "long-arrow-e")) return .long_arrow_e;
        if (std.mem.eql(u8, s, "chevron-s")) return .chevron_s;
        if (std.mem.eql(u8, s, "chevron-n")) return .chevron_n;
        if (std.mem.eql(u8, s, "chevron-s-dark")) return .chevron_s_dark;
        if (std.mem.eql(u8, s, "chevron-n-dark")) return .chevron_n_dark;
        if (std.mem.eql(u8, s, "star") or std.mem.eql(u8, s, "favorite")) return .star;
        return std.meta.stringToEnum(IconId, s);
    }

    /// Primary display alias (storybook labels / conversation). Prefer hyphens.
    pub fn primaryAlias(self: IconId) []const u8 {
        return switch (self) {
            .cursor_arrow => "pointer",
            .cursor_hand_open => "hand",
            .cursor_hand_closed => "grab",
            .cursor_text => "ibeam",
            .cursor_cross => "crosshair",
            .cursor_resize_h => "resize-ew",
            .cursor_resize_v => "resize-ns",
            .cursor_resize_nwse => "resize-nwse",
            .cursor_resize_nesw => "resize-nesw",
            .cursor_busy => "wait",
            .arrow_down => "caret-down",
            .arrow_up => "caret-up",
            .arrow_left => "caret-left",
            .arrow_right => "caret-right",
            .tree_leaf => "leaf",
            .folder => "dir",
            .folder_open => "dir-open",
            .check => "ok",
            .close => "x",
            .plus => "plus",
            .minus => "minus",
            .search => "find",
            .settings => "gear",
            .home => "home",
            .save => "disk",
            .copy => "copy",
            .paste => "paste",
            .trash => "delete",
            .eye => "eye",
            .lock => "lock",
            .star => "star",
            .download => "download",
            .emoji_smile => "smile",
            .emoji_heart => "heart",
            .emoji_laugh => "joy",
            .emoji_thumbs_up => "thumbs-up",
            .emoji_fire => "fire",
            .emoji_party => "tada",
            .emoji_cry => "sad",
            .emoji_think => "thinking",
            .emoji_clap => "clap",
            .emoji_100 => "hundred",
            .arrow_s => "arrow-s",
            .arrow_n => "arrow-n",
            .arrow_w => "arrow-w",
            .arrow_e => "arrow-e",
            .long_arrow_w => "long-arrow-w",
            .long_arrow_e => "long-arrow-e",
            .chevron_s => "chevron-s",
            .chevron_n => "chevron-n",
            .chevron_s_dark => "chevron-s-dark",
            .chevron_n_dark => "chevron-n-dark",
        };
    }
};

pub const IconRect = struct {
    x: u16 = 0,
    y: u16 = 0,
    w: u16 = 24,
    h: u16 = 24,
    hotspot_x: u8 = 0,
    hotspot_y: u8 = 0,
};

/// Native atlas cell size (keep in sync with tools/icon_atlas.py).
pub const native_size: f32 = 24;

pub const Icons = struct {
    image: sg.Image = .{},
    view: sg.View = .{},
    smp: sg.Sampler = .{},
    img_w: u32 = 0,
    img_h: u32 = 0,
    rects: [64]IconRect = undefined,
    alias_map: std.StringHashMap(IconId) = undefined,
    alias_arena: std.heap.ArenaAllocator = undefined,
    arena_inited: bool = false,
    ok: bool = false,

    pub fn loadFromBytes(self: *Icons, allocator: std.mem.Allocator, png_bytes: []const u8, yaml_bytes: []const u8) !void {
        @memset(std.mem.asBytes(&self.rects), 0);
        self.alias_arena = std.heap.ArenaAllocator.init(allocator);
        self.arena_inited = true;
        errdefer {
            self.alias_arena.deinit();
            self.arena_inited = false;
        }
        self.alias_map = std.StringHashMap(IconId).init(self.alias_arena.allocator());

        var image = try png.load(allocator, png_bytes);
        defer image.deinit(allocator);
        var pi: usize = 0;
        while (pi + 3 < image.pixels.len) : (pi += 4) {
            if (image.pixels[pi + 3] == 0) {
                image.pixels[pi + 0] = 0;
                image.pixels[pi + 1] = 0;
                image.pixels[pi + 2] = 0;
            }
        }

        self.img_w = image.width;
        self.img_h = image.height;

        var img_data: sg.ImageData = .{};
        img_data.mip_levels[0] = .{
            .ptr = image.pixels.ptr,
            .size = image.pixels.len,
        };
        self.image = sg.makeImage(.{
            .width = @intCast(image.width),
            .height = @intCast(image.height),
            .pixel_format = .RGBA8,
            .data = img_data,
            .label = "icon-atlas",
        });
        self.view = sg.makeView(.{
            .texture = .{ .image = self.image },
            .label = "icon-atlas-view",
        });
        self.smp = sg.makeSampler(.{
            .min_filter = .LINEAR,
            .mag_filter = .LINEAR,
            .wrap_u = .CLAMP_TO_EDGE,
            .wrap_v = .CLAMP_TO_EDGE,
            .label = "icon-atlas-smp",
        });

        try self.loadYaml(allocator, yaml_bytes);
        self.ok = true;
    }

    fn loadYaml(self: *Icons, allocator: std.mem.Allocator, yaml_bytes: []const u8) !void {
        var doc = try yaml.parse(allocator, yaml_bytes);
        defer doc.deinit();

        const icons_list = doc.root.getListMap("icons") orelse return error.MissingIcons;
        for (icons_list) |entry| {
            const id_s = entry.getString("id") orelse continue;
            const id = IconId.fromName(id_s) orelse {
                std.log.warn("icons.yaml: unknown id '{s}'", .{id_s});
                continue;
            };
            const idx = @intFromEnum(id);
            self.rects[idx] = .{
                .x = @intCast(entry.getInt("x") orelse 0),
                .y = @intCast(entry.getInt("y") orelse 0),
                .w = @intCast(entry.getInt("w") orelse 24),
                .h = @intCast(entry.getInt("h") orelse 24),
                .hotspot_x = @intCast(entry.getInt("hotspot_x") orelse 0),
                .hotspot_y = @intCast(entry.getInt("hotspot_y") orelse 0),
            };
            try self.alias_map.put(try self.alias_arena.allocator().dupe(u8, id_s), id);
            try self.alias_map.put(try self.alias_arena.allocator().dupe(u8, id.primaryAlias()), id);
            if (entry.getList("aliases")) |aliases| {
                for (aliases) |al| {
                    try self.alias_map.put(try self.alias_arena.allocator().dupe(u8, al), id);
                }
            }
        }
    }

    pub fn load(
        self: *Icons,
        allocator: std.mem.Allocator,
        io: std.Io,
        embed_png: []const u8,
        embed_yaml: []const u8,
    ) !void {
        const png_path = "assets/icons/icons.png";
        const yaml_path = "assets/icons/icons.yaml";
        const dir = std.Io.Dir.cwd();
        const png_file = dir.readFileAlloc(io, png_path, allocator, .limited(16 * 1024 * 1024)) catch null;
        const yaml_file = dir.readFileAlloc(io, yaml_path, allocator, .limited(1024 * 1024)) catch null;
        defer if (png_file) |p| allocator.free(p);
        defer if (yaml_file) |y| allocator.free(y);

        if (png_file) |p| {
            const y = yaml_file orelse embed_yaml;
            self.loadFromBytes(allocator, p, y) catch |err| {
                std.log.warn("runtime icon load failed ({s}), trying embed", .{@errorName(err)});
                try self.loadFromBytes(allocator, embed_png, embed_yaml);
                return;
            };
            std.log.info("loaded icons from {s} ({d} bytes)", .{ png_path, p.len });
            return;
        }
        try self.loadFromBytes(allocator, embed_png, embed_yaml);
        std.log.info("loaded icons from embed ({d} png bytes)", .{embed_png.len});
    }

    pub fn loadFromEmbed(self: *Icons, allocator: std.mem.Allocator, png_bytes: []const u8, yaml_bytes: []const u8) !void {
        try self.loadFromBytes(allocator, png_bytes, yaml_bytes);
    }

    pub fn deinit(self: *Icons) void {
        if (self.view.id != 0) sg.destroyView(self.view);
        if (self.image.id != 0) sg.destroyImage(self.image);
        if (self.smp.id != 0) sg.destroySampler(self.smp);
        if (self.arena_inited) self.alias_arena.deinit();
        self.* = .{};
    }

    pub fn resolve(self: *const Icons, name_or_alias: []const u8) ?IconId {
        if (IconId.fromName(name_or_alias)) |id| return id;
        return self.alias_map.get(name_or_alias);
    }

    pub fn rectOf(self: *const Icons, id: IconId) IconRect {
        return self.rects[@intFromEnum(id)];
    }

    pub fn draw(self: *const Icons, x: f32, y: f32, size: f32, id: IconId, color: [4]f32) void {
        if (!self.ok or self.image.id == 0) return;
        const r = self.rectOf(id);
        const iw: f32 = @floatFromInt(self.img_w);
        const ih: f32 = @floatFromInt(self.img_h);
        const pad_u = 0.5 / iw;
        const pad_v = 0.5 / ih;
        const uu0 = @as(f32, @floatFromInt(r.x)) / iw + pad_u;
        const vv0 = @as(f32, @floatFromInt(r.y)) / ih + pad_v;
        const uu1 = @as(f32, @floatFromInt(r.x + r.w)) / iw - pad_u;
        const vv1 = @as(f32, @floatFromInt(r.y + r.h)) / ih - pad_v;

        sgl.enableTexture();
        sgl.texture(self.view, self.smp);
        sgl.beginQuads();
        sgl.c4f(color[0], color[1], color[2], color[3]);
        sgl.v2fT2f(x, y, uu0, vv0);
        sgl.v2fT2f(x + size, y, uu1, vv0);
        sgl.v2fT2f(x + size, y + size, uu1, vv1);
        sgl.v2fT2f(x, y + size, uu0, vv1);
        sgl.end();
        sgl.disableTexture();
    }

    pub fn drawHotspot(self: *const Icons, mouse_x: f32, mouse_y: f32, size: f32, id: IconId, color: [4]f32) void {
        const r = self.rectOf(id);
        const scale = size / @as(f32, @floatFromInt(@max(r.w, 1)));
        const ox = @as(f32, @floatFromInt(r.hotspot_x)) * scale;
        const oy = @as(f32, @floatFromInt(r.hotspot_y)) * scale;
        self.draw(mouse_x - ox, mouse_y - oy, size, id, color);
    }
};
