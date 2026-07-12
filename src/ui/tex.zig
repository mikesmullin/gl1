//! Simple GPU texture for UI image wells (RGBA8).
const std = @import("std");
const png = @import("../png.zig");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sgl = sokol.gl;

pub const Tex = struct {
    image: sg.Image = .{},
    view: sg.View = .{},
    smp: sg.Sampler = .{},
    w: u32 = 0,
    h: u32 = 0,
    ok: bool = false,

    pub fn loadFromPng(self: *Tex, allocator: std.mem.Allocator, bytes: []const u8) !void {
        self.deinit();
        var img = try png.load(allocator, bytes);
        defer img.deinit(allocator);
        self.w = img.width;
        self.h = img.height;
        var img_data: sg.ImageData = .{};
        img_data.mip_levels[0] = sg.asRange(img.pixels);
        self.image = sg.makeImage(.{
            .width = @intCast(img.width),
            .height = @intCast(img.height),
            .pixel_format = .RGBA8,
            .data = img_data,
            .label = "ui-tex",
        });
        self.view = sg.makeView(.{ .texture = .{ .image = self.image } });
        self.smp = sg.makeSampler(.{
            .min_filter = .LINEAR,
            .mag_filter = .LINEAR,
            .wrap_u = .CLAMP_TO_EDGE,
            .wrap_v = .CLAMP_TO_EDGE,
        });
        self.ok = self.image.id != 0;
    }

    pub fn deinit(self: *Tex) void {
        if (self.smp.id != 0) sg.destroySampler(self.smp);
        if (self.view.id != 0) sg.destroyView(self.view);
        if (self.image.id != 0) sg.destroyImage(self.image);
        self.* = .{};
    }

    pub const Fit = enum { fit, stretch, fill };

    /// Draw into destination rect with fit mode.
    pub fn draw(self: *const Tex, dx: f32, dy: f32, dw: f32, dh: f32, fit: Fit) void {
        if (!self.ok or self.image.id == 0) return;
        const iw: f32 = @floatFromInt(self.w);
        const ih: f32 = @floatFromInt(self.h);
        var x = dx;
        var y = dy;
        var w = dw;
        var h = dh;
        var uv0x: f32 = 0;
        var uv0y: f32 = 0;
        var uv1x: f32 = 1;
        var uv1y: f32 = 1;

        switch (fit) {
            .stretch => {},
            .fit => {
                // Contain: letterbox inside dest.
                const scale = @min(dw / iw, dh / ih);
                w = iw * scale;
                h = ih * scale;
                x = dx + (dw - w) * 0.5;
                y = dy + (dh - h) * 0.5;
            },
            .fill => {
                // Cover: crop to fill dest.
                const scale = @max(dw / iw, dh / ih);
                const sw = dw / scale;
                const sh = dh / scale;
                const sx = (iw - sw) * 0.5;
                const sy = (ih - sh) * 0.5;
                uv0x = sx / iw;
                uv0y = sy / ih;
                uv1x = (sx + sw) / iw;
                uv1y = (sy + sh) / ih;
            },
        }

        sgl.enableTexture();
        sgl.texture(self.view, self.smp);
        sgl.beginQuads();
        sgl.c4f(1, 1, 1, 1);
        sgl.v2fT2f(x, y, uv0x, uv0y);
        sgl.v2fT2f(x + w, y, uv1x, uv0y);
        sgl.v2fT2f(x + w, y + h, uv1x, uv1y);
        sgl.v2fT2f(x, y + h, uv0x, uv1y);
        sgl.end();
        sgl.disableTexture();
    }
};
