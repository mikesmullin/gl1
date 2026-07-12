//! Bitmap font atlas matching Game9 mono1 (glyphs-outline.bmp).

const std = @import("std");
const bmp = @import("bmp.zig");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sgl = sokol.gl;

/// How many mono columns a tab advances to the next stop (global, configurable).
/// `\t` is never drawn as a glyph — it expands to this many space-widths at tab stops.
pub var tab_columns: u32 = 4;

/// Columns to advance for a tab at the given 0-based column within the line.
pub fn tabAdvanceColumns(col: u32) u32 {
    const tw = if (tab_columns == 0) 1 else tab_columns;
    return tw - (col % tw);
}

/// Game9 Font mono1 layout on glyphs-outline.bmp (194×34).
pub const Font = struct {
    border: u32 = 1,
    spacex: u32 = 1,
    spacey: u32 = 0,
    cell_w: u32 = 5,
    cell_h: u32 = 8,
    cols: u32 = 32,
    rows: u32 = 4,
    base_size: f32 = 3.0,
    kerning: f32 = -0.5,

    img_w: u32 = 0,
    img_h: u32 = 0,
    image: sg.Image = .{},
    view: sg.View = .{},
    smp: sg.Sampler = .{},

    /// Magenta / hot-pink chroma key used as transparency in the atlas
    /// (Game9 COLOR_PINK convention).
    fn applyPinkMask(pixels: []u8) void {
        var i: usize = 0;
        while (i + 3 < pixels.len) : (i += 4) {
            const r = pixels[i + 0];
            const g = pixels[i + 1];
            const b = pixels[i + 2];
            // Exact classic pink, or near-magenta (high R+B, low G).
            const exact = (r == 255 and g == 0 and b == 255) or
                (r == 255 and g == 0 and b == 254) or
                (r >= 250 and g <= 5 and b >= 250);
            const near_pink = r > 200 and b > 200 and g < 80 and r > g + 100 and b > g + 100;
            if (exact or near_pink) {
                pixels[i + 3] = 0;
            }
        }
    }

    pub fn loadFromBytes(self: *Font, allocator: std.mem.Allocator, data: []const u8) !void {
        var image = try bmp.load(allocator, data);
        defer image.deinit(allocator);

        applyPinkMask(image.pixels);

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
            .label = "font-atlas",
        });
        self.view = sg.makeView(.{
            .texture = .{ .image = self.image },
            .label = "font-atlas-view",
        });
        self.smp = sg.makeSampler(.{
            .min_filter = .NEAREST,
            .mag_filter = .NEAREST,
            .wrap_u = .CLAMP_TO_EDGE,
            .wrap_v = .CLAMP_TO_EDGE,
            .label = "font-atlas-smp",
        });
    }

    pub fn deinit(self: *Font) void {
        if (self.view.id != 0) sg.destroyView(self.view);
        if (self.image.id != 0) sg.destroyImage(self.image);
        if (self.smp.id != 0) sg.destroySampler(self.smp);
        self.* = .{};
    }

    fn borderSpacingOffset(border: u32, spacing: u32, size: u32, index: u32) u32 {
        return border + (spacing + size) * index;
    }

    pub fn glyphUv(self: *const Font, ch: u8) struct { u_min: f32, v_min: f32, u_max: f32, v_max: f32 } {
        const xx = @as(u32, ch) % self.cols;
        const yy = @as(u32, ch) / self.cols;
        const tex_x = borderSpacingOffset(self.border, self.spacex, self.cell_w, xx);
        const tex_y = borderSpacingOffset(self.border, self.spacey, self.cell_h, yy);
        const iw: f32 = @floatFromInt(self.img_w);
        const ih: f32 = @floatFromInt(self.img_h);
        const u_min = @as(f32, @floatFromInt(tex_x)) / iw;
        const v_min = @as(f32, @floatFromInt(tex_y)) / ih;
        const u_max = @as(f32, @floatFromInt(tex_x + self.cell_w)) / iw;
        const v_max = @as(f32, @floatFromInt(tex_y + self.cell_h)) / ih;
        return .{ .u_min = u_min, .v_min = v_min, .u_max = u_max, .v_max = v_max };
    }

    pub fn advance(self: *const Font, size: f32) f32 {
        return (@as(f32, @floatFromInt(self.cell_w)) + self.kerning) * size;
    }

    pub fn lineHeight(self: *const Font, size: f32) f32 {
        return @as(f32, @floatFromInt(self.cell_h)) * size;
    }

    pub fn measure(self: *const Font, text: []const u8, size: f32) struct { w: f32, h: f32 } {
        var x: f32 = 0;
        var max_w: f32 = 0;
        var lines: f32 = 1;
        var col: u32 = 0;
        const adv = self.advance(size);
        const lh = self.lineHeight(size);
        for (text) |ch| {
            if (ch == '\n') {
                max_w = @max(max_w, x);
                x = 0;
                col = 0;
                lines += 1;
                continue;
            }
            if (ch == '\t') {
                const n = tabAdvanceColumns(col);
                x += adv * @as(f32, @floatFromInt(n));
                col += n;
                continue;
            }
            x += adv;
            col += 1;
        }
        max_w = @max(max_w, x);
        return .{ .w = max_w, .h = lines * lh };
    }

    /// Draw text with top-left origin. Color multiplies atlas (white glyphs → tint).
    /// Tabs advance like spaces (see `tab_columns`); no glyph is drawn for `\t`.
    pub fn draw(self: *const Font, x: f32, y: f32, size: f32, color: [4]f32, text: []const u8) void {
        if (self.image.id == 0) return;
        const adv = self.advance(size);
        const gw = @as(f32, @floatFromInt(self.cell_w)) * size;
        const gh = @as(f32, @floatFromInt(self.cell_h)) * size;
        const lh = self.lineHeight(size);

        sgl.enableTexture();
        sgl.texture(self.view, self.smp);
        sgl.beginQuads();
        sgl.c4f(color[0], color[1], color[2], color[3]);

        var cx = x;
        var cy = y;
        var col: u32 = 0;
        for (text) |ch| {
            if (ch == '\n') {
                cx = x;
                cy += lh;
                col = 0;
                continue;
            }
            if (ch == '\t') {
                const n = tabAdvanceColumns(col);
                cx += adv * @as(f32, @floatFromInt(n));
                col += n;
                continue;
            }
            const uv = self.glyphUv(ch);
            sgl.v2fT2f(cx, cy, uv.u_min, uv.v_min);
            sgl.v2fT2f(cx + gw, cy, uv.u_max, uv.v_min);
            sgl.v2fT2f(cx + gw, cy + gh, uv.u_max, uv.v_max);
            sgl.v2fT2f(cx, cy + gh, uv.u_min, uv.v_max);
            cx += adv;
            col += 1;
        }
        sgl.end();
        sgl.disableTexture();
    }
};
