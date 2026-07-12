//! Fullscreen diamond wipe / reveal (Game9 `Transition.c` + `diamond` shader).
//! Drawn with sokol_gl tiles so we don't need a custom GPU pipeline yet.

const std = @import("std");
const sokol = @import("sokol");
const sgl = sokol.gl;

pub const duration_s: f32 = 1.0;
const diamond_size: f32 = 48.0;

pub const Phase = enum { idle, wipe, reveal };

pub const Transition = struct {
    phase: Phase = .idle,
    /// 0..1 within current phase.
    t: f32 = 0,
    /// Scene change applied at wipe completion.
    pending: bool = false,

    pub fn busy(self: Transition) bool {
        return self.phase != .idle;
    }

    /// Start a wipe that will cover the screen (~1s). Caller should
    /// apply the scene change when `tick` returns `.swap`.
    pub fn startWipe(self: *Transition) void {
        self.phase = .wipe;
        self.t = 0;
        self.pending = true;
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

    /// Shader-equivalent progress: wipe 0→1 cover, reveal 1→0 uncover.
    pub fn progress(self: Transition) f32 {
        return switch (self.phase) {
            .idle => 0,
            .wipe => self.t,
            .reveal => 1.0 - self.t,
        };
    }

    /// Draw diamond overlay (call after UI, before present).
    pub fn draw(self: Transition, width: f32, height: f32) void {
        const p = self.progress();
        if (p <= 0.001) return;
        const thresh = p * 4.0;
        // Sample cell centers on a diamond grid.
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
                // Game9 discards fragments where metric > thresh → those stay transparent.
                // We *draw* where metric <= thresh (covered).
                if (metric <= thresh) {
                    const half = diamond_size * 0.35;
                    sgl.beginQuads();
                    sgl.c4f(0.10, 0.10, 0.10, 1);
                    // Diamond as 4-vert diamond (axis-aligned rhombus)
                    sgl.v2f(cx, cy - half);
                    sgl.v2f(cx + half, cy);
                    sgl.v2f(cx, cy + half);
                    sgl.v2f(cx - half, cy);
                    sgl.end();
                }
            }
        }
    }
};
