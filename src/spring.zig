//! Damped spring (Ryan Juckett / Game9 `Spring.c`).
//! Great for game-feel: press squash, follow, shake, UI settle.
//!
//! Usage:
//! ```
//! var s = spring.Spring1{};
//! s.target = 1.0;
//! s.step(dt, 0.85, 12.0); // damping, frequency (Hz-ish angular)
//! // s.pos is the smoothed value
//! ```

const std = @import("std");

/// Cached coefficients for one (dt, frequency, damping) triple.
pub const Params = struct {
    pos_pos: f32 = 1,
    pos_vel: f32 = 0,
    vel_pos: f32 = 0,
    vel_vel: f32 = 1,

    /// Build coeffs for this timestep (Game9 `Spring__Create`).
    /// `frequency` = angular frequency (higher = snappier).
    /// `damping` = 0..∞; 1 = critical, <1 bounce, >1 sluggish.
    pub fn create(delta_time: f32, frequency: f32, damping: f32) Params {
        const epsilon: f32 = 0.0001;
        const damping_ratio = @max(0, damping);
        const angular = @max(0, frequency);
        if (angular < epsilon) {
            return .{};
        }
        if (damping_ratio > 1.0 + epsilon) {
            // over-damped
            const za = -angular * damping_ratio;
            const zb = angular * @sqrt(damping_ratio * damping_ratio - 1.0);
            const z1 = za - zb;
            const z2 = za + zb;
            const e1 = @exp(z1 * delta_time);
            const e2 = @exp(z2 * delta_time);
            const inv_two_zb = 1.0 / (2.0 * zb);
            const e1_over = e1 * inv_two_zb;
            const e2_over = e2 * inv_two_zb;
            const z1e1 = z1 * e1_over;
            const z2e2 = z2 * e2_over;
            return .{
                .pos_pos = e1_over * z2 - z2e2 + e2,
                .pos_vel = -e1_over + e2_over,
                .vel_pos = (z1e1 - z2e2 + e2) * z2,
                .vel_vel = -z1e1 + z2e2,
            };
        } else if (damping_ratio < 1.0 - epsilon) {
            // under-damped
            const omega_zeta = angular * damping_ratio;
            const alpha = angular * @sqrt(1.0 - damping_ratio * damping_ratio);
            const exp_term = @exp(-omega_zeta * delta_time);
            const cos_term = @cos(alpha * delta_time);
            const sin_term = @sin(alpha * delta_time);
            const inv_alpha = 1.0 / alpha;
            const exp_sin = exp_term * sin_term;
            const exp_cos = exp_term * cos_term;
            const exp_oz = exp_term * omega_zeta * sin_term * inv_alpha;
            return .{
                .pos_pos = exp_cos + exp_oz,
                .pos_vel = exp_sin * inv_alpha,
                .vel_pos = -exp_sin * alpha - omega_zeta * exp_oz,
                .vel_vel = exp_cos - exp_oz,
            };
        } else {
            // critically damped
            const exp_term = @exp(-angular * delta_time);
            const time_exp = delta_time * exp_term;
            const time_exp_freq = time_exp * angular;
            return .{
                .pos_pos = time_exp_freq + exp_term,
                .pos_vel = time_exp,
                .vel_pos = -angular * time_exp_freq,
                .vel_vel = -time_exp_freq + exp_term,
            };
        }
    }
};

/// 1D spring state.
pub const Spring1 = struct {
    pos: f32 = 0,
    vel: f32 = 0,
    target: f32 = 0,

    pub fn step(self: *Spring1, dt: f32, damping: f32, frequency: f32) void {
        const p = Params.create(dt, frequency, damping);
        const old_pos = self.pos - self.target;
        const old_vel = self.vel;
        self.pos = old_pos * p.pos_pos + old_vel * p.pos_vel + self.target;
        self.vel = old_pos * p.vel_pos + old_vel * p.vel_vel;
    }

    /// Snap to target with optional velocity kick (press feedback).
    pub fn snap(self: *Spring1, to: f32, kick_vel: f32) void {
        self.pos = to;
        self.target = to;
        self.vel = kick_vel;
    }

    /// Impulse on velocity without changing rest pose (attract / shake).
    pub fn nudge(self: *Spring1, impulse: f32) void {
        self.vel += impulse;
    }
};

/// 2D spring (mouse follow, camera, etc.).
pub const Spring2 = struct {
    x: Spring1 = .{},
    y: Spring1 = .{},

    pub fn setTarget(self: *Spring2, tx: f32, ty: f32) void {
        self.x.target = tx;
        self.y.target = ty;
    }

    pub fn step(self: *Spring2, dt: f32, damping: f32, frequency: f32) void {
        self.x.step(dt, damping, frequency);
        self.y.step(dt, damping, frequency);
    }

    pub fn nudge(self: *Spring2, ix: f32, iy: f32) void {
        self.x.nudge(ix);
        self.y.nudge(iy);
    }
};
