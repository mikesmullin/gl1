//! Renderer-agnostic draw commands + sokol_gl backend (plan phase 8).

const sokol = @import("sokol");
const sgl = sokol.gl;
const font_mod = @import("font.zig");

pub const Color = [4]f32;

pub const Rect = struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,
};

pub const Command = union(enum) {
    rect: struct { r: Rect, color: Color },
    text: struct { x: f32, y: f32, size: f32, color: Color, text: []const u8 },
    scissor_push: Rect,
    scissor_pop: void,
};

pub const List = struct {
    cmds: [4096]Command = undefined,
    count: usize = 0,
    /// Scratch for owned text copies this frame (pointed into by .text commands).
    text_scratch: [64 * 1024]u8 = undefined,
    text_used: usize = 0,

    pub fn clear(self: *List) void {
        self.count = 0;
        self.text_used = 0;
    }

    pub fn intern(self: *List, s: []const u8) []const u8 {
        if (self.text_used + s.len > self.text_scratch.len) {
            // Truncate rather than crash; rare for UI demos.
            const n = @min(s.len, self.text_scratch.len -| self.text_used);
            if (n == 0) return "";
            @memcpy(self.text_scratch[self.text_used .. self.text_used + n], s[0..n]);
            const out = self.text_scratch[self.text_used .. self.text_used + n];
            self.text_used += n;
            return out;
        }
        @memcpy(self.text_scratch[self.text_used .. self.text_used + s.len], s);
        const out = self.text_scratch[self.text_used .. self.text_used + s.len];
        self.text_used += s.len;
        return out;
    }

    pub fn push(self: *List, cmd: Command) void {
        if (self.count >= self.cmds.len) return;
        self.cmds[self.count] = cmd;
        self.count += 1;
    }

    pub fn rect(self: *List, r: Rect, color: Color) void {
        self.push(.{ .rect = .{ .r = r, .color = color } });
    }

    pub fn text(self: *List, x: f32, y: f32, size: f32, color: Color, s: []const u8) void {
        self.push(.{ .text = .{ .x = x, .y = y, .size = size, .color = color, .text = self.intern(s) } });
    }

    /// Execute with sokol_gl (top-left ortho already set by caller).
    pub fn flushSgl(self: *const List, font: *const font_mod.Font) void {
        var i: usize = 0;
        while (i < self.count) : (i += 1) {
            switch (self.cmds[i]) {
                .rect => |c| {
                    sgl.disableTexture();
                    sgl.beginQuads();
                    sgl.c4f(c.color[0], c.color[1], c.color[2], c.color[3]);
                    sgl.v2f(c.r.x, c.r.y);
                    sgl.v2f(c.r.x + c.r.w, c.r.y);
                    sgl.v2f(c.r.x + c.r.w, c.r.y + c.r.h);
                    sgl.v2f(c.r.x, c.r.y + c.r.h);
                    sgl.end();
                },
                .text => |c| {
                    font.draw(c.x, c.y, c.size, c.color, c.text);
                },
                .scissor_push => |r| {
                    // sgl scissor uses top-left origin when set that way via defaults.
                    sgl.scissorRect(@intFromFloat(r.x), @intFromFloat(r.y), @intFromFloat(r.w), @intFromFloat(r.h), true);
                },
                .scissor_pop => {
                    // No nested stack helper in sgl — re-enable full viewport via huge scissor.
                    sgl.scissorRect(0, 0, 1 << 14, 1 << 14, true);
                },
            }
        }
    }
};
