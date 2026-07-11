//! Renderer-agnostic draw commands + sokol_gl backend (plan phase 8).

const sokol = @import("sokol");
const sgl = sokol.gl;
const sapp = sokol.app;
const font_mod = @import("font.zig");
const icons_mod = @import("icons.zig");

pub const Color = [4]f32;

pub const Rect = struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,

    pub fn intersect(a: Rect, b: Rect) Rect {
        const x0 = @max(a.x, b.x);
        const y0 = @max(a.y, b.y);
        const x1 = @min(a.x + a.w, b.x + b.w);
        const y1 = @min(a.y + a.h, b.y + b.h);
        return .{
            .x = x0,
            .y = y0,
            .w = @max(0, x1 - x0),
            .h = @max(0, y1 - y0),
        };
    }
};

pub const Command = union(enum) {
    rect: struct { r: Rect, color: Color },
    text: struct { x: f32, y: f32, size: f32, color: Color, text: []const u8 },
    /// Icon atlas sprite; `id` is `@intFromEnum(icons.IconId)`.
    icon: struct { x: f32, y: f32, size: f32, id: u16, color: Color },
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

    pub fn icon(self: *List, x: f32, y: f32, size: f32, id: u16, color: Color) void {
        self.push(.{ .icon = .{ .x = x, .y = y, .size = size, .id = id, .color = color } });
    }

    fn applyScissor(r: Rect) void {
        // Scissor is in framebuffer pixels; account for DPI.
        const dpi = sapp.dpiScale();
        const x: i32 = @intFromFloat(@floor(r.x * dpi));
        const y: i32 = @intFromFloat(@floor(r.y * dpi));
        const w: i32 = @intFromFloat(@ceil(r.w * dpi));
        const h: i32 = @intFromFloat(@ceil(r.h * dpi));
        // origin_top_left = true matches our ortho (0,0 top-left).
        sgl.scissorRect(x, y, @max(w, 0), @max(h, 0), true);
    }

    /// Execute with sokol_gl (top-left ortho already set by caller).
    pub fn flushSgl(self: *const List, font: *const font_mod.Font, icons: ?*const icons_mod.Icons) void {
        // Nested scissor stack: pop restores parent clip (intersected), never full-screen wipe
        // while an outer clip is still active — that was why scrolled panels leaked.
        var stack: [16]Rect = undefined;
        var depth: usize = 0;
        const fullscreen = Rect{ .x = 0, .y = 0, .w = 1 << 14, .h = 1 << 14 };

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
                .icon => |c| {
                    if (icons) |ic| {
                        const id: icons_mod.IconId = @enumFromInt(c.id);
                        ic.draw(c.x, c.y, c.size, id, c.color);
                    }
                },
                .scissor_push => |r| {
                    const parent = if (depth > 0) stack[depth - 1] else fullscreen;
                    const clipped = Rect.intersect(parent, r);
                    if (depth < stack.len) {
                        stack[depth] = clipped;
                        depth += 1;
                    }
                    applyScissor(clipped);
                },
                .scissor_pop => {
                    if (depth > 0) depth -= 1;
                    if (depth > 0) {
                        applyScissor(stack[depth - 1]);
                    } else {
                        applyScissor(fullscreen);
                    }
                },
            }
        }
        // Leave scissor open full-frame for any subsequent draw lists.
        applyScissor(fullscreen);
    }
};
