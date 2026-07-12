//! Fullscreen diamond wipe / reveal (Game9 Transition + diamond.glsl).
//! GPU path: per-pixel fragment shader with progress + color.
//! CPU tile path: fallback if shader init fails.

const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sgl = sokol.gl;
const diamond_shd = @import("shaders/diamond.zig");
const anim = @import("anim.zig");

pub const duration_s: f32 = 1.0;
const diamond_size: f32 = 48.0;

pub const color_charcoal: [4]f32 = .{ 0.10, 0.10, 0.10, 1 };
pub const color_blue: [4]f32 = .{ 0.20, 0.40, 0.95, 1 };
pub const color_pink: [4]f32 = .{ 0.90, 0.30, 0.55, 1 };
pub const color_green: [4]f32 = .{ 0.20, 0.70, 0.40, 1 };
pub const color_amber: [4]f32 = .{ 0.90, 0.65, 0.20, 1 };

pub const Phase = enum { idle, wipe, reveal };

pub const Transition = struct {
    phase: Phase = .idle,
    /// Linear 0..1 within current phase (eased for display).
    t: f32 = 0,
    pending: bool = false,
    color: [4]f32 = color_charcoal,

    // GPU resources
    ok: bool = false,
    pip: sg.Pipeline = .{},
    bind: sg.Bindings = .{},
    shd: sg.Shader = .{},
    vbuf: sg.Buffer = .{},

    pub fn init(self: *Transition) void {
        const backend = sg.queryBackend();
        const desc = diamond_shd.shaderDesc(backend);
        if (desc.vertex_func.source == null or desc.fragment_func.source == null) {
            self.ok = false;
            return;
        }
        self.shd = sg.makeShader(desc);
        // Fullscreen triangle in NDC (same as ada avatar).
        self.vbuf = sg.makeBuffer(.{
            .data = sg.asRange(&[_]f32{
                -1.0, -1.0,
                3.0,  -1.0,
                -1.0, 3.0,
            }),
        });
        self.bind.vertex_buffers[0] = self.vbuf;
        var pip_desc: sg.PipelineDesc = .{
            .shader = self.shd,
            .primitive_type = .TRIANGLES,
            .label = "diamond-pip",
        };
        pip_desc.layout.attrs[diamond_shd.ATTR_position].format = .FLOAT2;
        // Premultiplied-friendly; discard handles holes.
        pip_desc.colors[0].blend = .{
            .enabled = true,
            .src_factor_rgb = .SRC_ALPHA,
            .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
            .src_factor_alpha = .ONE,
            .dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
        };
        self.pip = sg.makePipeline(pip_desc);
        self.ok = self.pip.id != 0 and self.shd.id != 0;
    }

    pub fn deinit(self: *Transition) void {
        if (self.pip.id != 0) sg.destroyPipeline(self.pip);
        if (self.shd.id != 0) sg.destroyShader(self.shd);
        if (self.vbuf.id != 0) sg.destroyBuffer(self.vbuf);
        self.* = .{};
    }

    pub fn busy(self: Transition) bool {
        return self.phase != .idle;
    }

    pub fn startWipe(self: *Transition, color: [4]f32) void {
        self.phase = .wipe;
        self.t = 0;
        self.pending = true;
        self.color = color;
    }

    pub const TickResult = enum { none, swap };

    pub fn tick(self: *Transition, dt: f32) TickResult {
        if (self.phase == .idle) return .none;
        self.t += dt / duration_s;
        if (self.t >= 1.0) {
            self.t = 1.0;
            if (self.phase == .wipe) {
                self.phase = .reveal;
                self.t = 0;
                const had = self.pending;
                self.pending = false;
                return if (had) .swap else .none;
            } else {
                self.phase = .idle;
                self.t = 0;
            }
        }
        return .none;
    }

    /// Game9-style progress with ease: wipe easeOut, reveal easeIn (inverted).
    pub fn progress(self: Transition) f32 {
        return switch (self.phase) {
            .idle => 0,
            .wipe => anim.ease(.ease_out_cubic, self.t),
            .reveal => 1.0 - anim.ease(.ease_in_quad, self.t),
        };
    }

    pub fn draw(self: Transition, width: f32, height: f32) void {
        const p = self.progress();
        if (p <= 0.001) return;
        if (self.ok) {
            self.drawGpu(width, height, p);
        } else {
            drawCpuTiles(width, height, p, self.color);
        }
    }

    fn drawGpu(self: Transition, width: f32, height: f32, p: f32) void {
        // Must draw in a pass that's already begun; apply pipeline and draw.
        var params: diamond_shd.FsParams = .{
            .progress = p,
            .res_x = width,
            .res_y = height,
            .color = self.color,
        };
        sg.applyPipeline(self.pip);
        sg.applyBindings(self.bind);
        sg.applyUniforms(diamond_shd.UB_fs_params, sg.asRange(&params));
        sg.draw(0, 3, 1);
    }
};

fn drawCpuTiles(width: f32, height: f32, p: f32, color: [4]f32) void {
    const thresh = p * 4.0;
    var y: f32 = 0;
    while (y < height + diamond_size) : (y += diamond_size * 0.5) {
        var x: f32 = 0;
        while (x < width + diamond_size) : (x += diamond_size * 0.5) {
            const cx = x + diamond_size * 0.25;
            const cy = y + diamond_size * 0.25;
            const fx = @abs(@mod(cx / diamond_size, 1.0) - 0.5);
            const fy = @abs(@mod(cy / diamond_size, 1.0) - 0.5);
            const uvx = cx / width;
            const uvy = cy / height;
            const metric = fx + fy + uvx + uvy;
            if (metric <= thresh) {
                const half = diamond_size * 0.5;
                sgl.beginQuads();
                sgl.c4f(color[0], color[1], color[2], color[3]);
                sgl.v2f(cx, cy - half);
                sgl.v2f(cx + half, cy);
                sgl.v2f(cx, cy + half);
                sgl.v2f(cx - half, cy);
                sgl.end();
            }
        }
    }
}
