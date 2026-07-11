//! Lightweight animation primitives inspired by Game9 (`Timer.c`, `Animate.c`).
//!
//! Game9 patterns we keep:
//! - **Timer**: start epoch + duration → `pct` / `lerp` / busy-complete
//! - **Tween**: `from` → `to` over progress, with an **Easing** curve
//! - **Passive sample**: pull value with `tween.sample(timer.pct(now))` (no forced graph)
//!
//! Simpler than full Game9 Anim (no keyframe chains / composition / FPS yet).

const std = @import("std");

// --- Easing (Game9 `easy(Easing, t)`) ----------------------------------------

pub const Easing = enum {
    linear,
    /// Hermite smoothstep (default for camera framing).
    smoothstep,
    ease_in_quad,
    ease_out_quad,
    ease_in_out_quad,
    ease_out_cubic,
    /// Soft settle with a tiny overshoot (scroll bounce / rubber return).
    ease_out_back,
};

pub fn ease(e: Easing, t: f32) f32 {
    const x = std.math.clamp(t, 0, 1);
    return switch (e) {
        .linear => x,
        .smoothstep => x * x * (3 - 2 * x),
        .ease_in_quad => x * x,
        .ease_out_quad => 1 - (1 - x) * (1 - x),
        .ease_in_out_quad => if (x < 0.5) 2 * x * x else 1 - ((-2 * x + 2) * (-2 * x + 2)) / 2,
        .ease_out_cubic => blk: {
            const u = 1 - x;
            break :blk 1 - u * u * u;
        },
        .ease_out_back => blk: {
            // c1 = 1.70158, c3 = c1 + 1
            const c1: f32 = 1.70158;
            const c3: f32 = c1 + 1;
            const u = x - 1;
            break :blk 1 + c3 * u * u * u + c1 * u * u;
        },
    };
}

/// Linear map t∈[0,1] from a→b (Game9 `lerp`).
pub fn mix(t: f32, a: f32, b: f32) f32 {
    return a + (b - a) * t;
}

// --- Timer (Game9 `Timer` / T_play / T_pct / T_lerp) --------------------------

/// Wall-clock timer. `start < 0` means idle/canceled (Game9 uses 0 for canceled).
pub const Timer = struct {
    /// Epoch seconds when started (`-1` = not playing).
    start: f64 = -1,
    /// Duration in seconds.
    duration_s: f32 = 0,

    pub fn idle(self: Timer) bool {
        return self.start < 0;
    }

    pub fn playing(self: Timer) bool {
        return self.start >= 0;
    }

    /// Start or restart (Game9 `T_play`).
    pub fn play(self: *Timer, now: f64, duration_s: f32) void {
        self.start = now;
        self.duration_s = duration_s;
    }

    /// Abort early (Game9 `T_cancel`).
    pub fn cancel(self: *Timer) void {
        self.start = -1;
        self.duration_s = 0;
    }

    pub fn elapsed(self: Timer, now: f64) f32 {
        if (self.start < 0) return 0;
        return @floatCast(@max(0, now - self.start));
    }

    /// 0..1 progress (Game9 `T_pct`). Clamped.
    pub fn pct(self: Timer, now: f64) f32 {
        if (self.start < 0) return 0;
        if (self.duration_s <= 0) return 1;
        return std.math.clamp(self.elapsed(now) / self.duration_s, 0, 1);
    }

    pub fn completed(self: Timer, now: f64) bool {
        if (self.start < 0) return false;
        return self.pct(now) >= 1;
    }

    pub fn busy(self: Timer, now: f64) bool {
        return self.playing() and !self.completed(now);
    }

    /// Map progress to range a..b with optional easing (Game9 `T_lerp` + ease).
    pub fn map(self: Timer, now: f64, a: f32, b: f32, e: Easing) f32 {
        return mix(ease(e, self.pct(now)), a, b);
    }
};

// --- Tween (Game9 `Tween` / Tween__value) -------------------------------------

/// Single-channel from→to interpolation.
pub const Tween = struct {
    from: f32 = 0,
    to: f32 = 0,
    ease: Easing = .smoothstep,

    pub fn init(from: f32, to: f32) Tween {
        return .{ .from = from, .to = to };
    }

    pub fn initEase(from: f32, to: f32, e: Easing) Tween {
        return .{ .from = from, .to = to, .ease = e };
    }

    /// Game9 `Tween__value(tw, t)` — `t` is 0..1 raw progress.
    pub fn sample(self: Tween, t: f32) f32 {
        return mix(ease(self.ease, t), self.from, self.to);
    }

    pub fn sampleTimer(self: Tween, timer: Timer, now: f64) f32 {
        return self.sample(timer.pct(now));
    }
};

// --- Parallel multi-channel (simplified Anim: one timer, N tweens) -----------

/// Several float channels driven by one Timer (Game9 parallel keyframes lite).
pub const Parallel = struct {
    timer: Timer = .{},
    ch: [8]Tween = undefined,
    ct: usize = 0,

    pub fn reset(self: *Parallel) void {
        self.timer.cancel();
        self.ct = 0;
    }

    pub fn add(self: *Parallel, from: f32, to: f32) void {
        if (self.ct >= self.ch.len) return;
        self.ch[self.ct] = Tween.init(from, to);
        self.ct += 1;
    }

    pub fn play(self: *Parallel, now: f64, duration_s: f32) void {
        self.timer.play(now, duration_s);
    }

    pub fn cancel(self: *Parallel) void {
        self.timer.cancel();
    }

    pub fn busy(self: Parallel, now: f64) bool {
        return self.timer.busy(now);
    }

    /// Sample channel `i` at current timer progress.
    pub fn value(self: Parallel, now: f64, i: usize) f32 {
        if (i >= self.ct) return 0;
        return self.ch[i].sampleTimer(self.timer, now);
    }

    /// Advance; returns false when finished (and marks idle).
    pub fn tick(self: *Parallel, now: f64) bool {
        if (self.timer.idle()) return false;
        if (self.timer.completed(now)) {
            // Snap to end values once, then idle.
            self.timer.cancel();
            return false;
        }
        return true;
    }

    /// Like tick, but writes final `to` values when completing.
    pub fn tickInto(self: *Parallel, now: f64, outs: []f32) bool {
        if (self.timer.idle()) return false;
        const t = self.timer.pct(now);
        const done = t >= 1;
        const n = @min(outs.len, self.ct);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            outs[i] = if (done) self.ch[i].to else self.ch[i].sample(t);
        }
        if (done) self.timer.cancel();
        return !done;
    }
};
