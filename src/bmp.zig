//! Minimal BMP loader (32-bpp BI_BITFIELDS / uncompressed, top or bottom-up).

const std = @import("std");

pub const Image = struct {
    width: u32,
    height: u32,
    /// RGBA8 row-major, top-left origin.
    pixels: []u8,

    pub fn deinit(self: *Image, allocator: std.mem.Allocator) void {
        allocator.free(self.pixels);
        self.* = undefined;
    }
};

pub fn load(allocator: std.mem.Allocator, data: []const u8) !Image {
    if (data.len < 54) return error.InvalidBmp;
    if (data[0] != 'B' or data[1] != 'M') return error.InvalidBmp;

    const pixel_offset = std.mem.readInt(u32, data[10..14], .little);
    const dib_size = std.mem.readInt(u32, data[14..18], .little);
    if (dib_size < 40) return error.UnsupportedBmp;

    const width_i = std.mem.readInt(i32, data[18..22], .little);
    const height_i = std.mem.readInt(i32, data[22..26], .little);
    const planes = std.mem.readInt(u16, data[26..28], .little);
    const bpp = std.mem.readInt(u16, data[28..30], .little);
    const compression = std.mem.readInt(u32, data[30..34], .little);

    if (planes != 1) return error.UnsupportedBmp;
    if (bpp != 32 and bpp != 24) return error.UnsupportedBmp;
    // 0 = BI_RGB, 3 = BI_BITFIELDS
    if (compression != 0 and compression != 3) return error.UnsupportedBmp;

    const top_down = height_i < 0;
    const width: u32 = @intCast(@abs(width_i));
    const height: u32 = @intCast(@abs(height_i));
    if (width == 0 or height == 0) return error.InvalidBmp;

    const bytes_per_pixel: u32 = bpp / 8;
    const row_stride = (width * bytes_per_pixel + 3) & ~@as(u32, 3);

    if (pixel_offset > data.len) return error.InvalidBmp;
    const pixel_data = data[pixel_offset..];
    const needed = row_stride * height;
    if (pixel_data.len < needed) return error.InvalidBmp;

    const out = try allocator.alloc(u8, width * height * 4);
    errdefer allocator.free(out);

    var y: u32 = 0;
    while (y < height) : (y += 1) {
        const src_y: u32 = if (top_down) y else (height - 1 - y);
        const src_row = pixel_data[src_y * row_stride ..][0 .. width * bytes_per_pixel];
        const dst_row = out[y * width * 4 ..][0 .. width * 4];
        var x: u32 = 0;
        while (x < width) : (x += 1) {
            const si = x * bytes_per_pixel;
            const di = x * 4;
            // BMP stores BGRA (or BGR) typically.
            const b = src_row[si + 0];
            const g = src_row[si + 1];
            const r = src_row[si + 2];
            const a: u8 = if (bytes_per_pixel == 4) src_row[si + 3] else 255;
            dst_row[di + 0] = r;
            dst_row[di + 1] = g;
            dst_row[di + 2] = b;
            dst_row[di + 3] = a;
        }
    }

    return .{ .width = width, .height = height, .pixels = out };
}
