//! Canvas scene — mini Blender-like 3D viewport.
//! - MMB drag: orbit about look target
//! - Space+LMB: pan target in the camera plane
//! - Wheel: dolly (distance)
//! - Numpad / keys 7, 1, 3: Top / Front / Right (Blender convention)
//! - LMB click: select entity (accent outline) — demo “ECS” cubes

const std = @import("std");
const app = @import("../app.zig");
const ui = @import("../ui/ui.zig");
const state = @import("state.zig");
const sgl = @import("sokol").gl;

const Vec3 = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,

    fn add(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }
    fn sub(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
    }
    fn scale(a: Vec3, s: f32) Vec3 {
        return .{ .x = a.x * s, .y = a.y * s, .z = a.z * s };
    }
    fn dot(a: Vec3, b: Vec3) f32 {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }
    fn cross(a: Vec3, b: Vec3) Vec3 {
        return .{
            .x = a.y * b.z - a.z * b.y,
            .y = a.z * b.x - a.x * b.z,
            .z = a.x * b.y - a.y * b.x,
        };
    }
    fn length(a: Vec3) f32 {
        return @sqrt(dot(a, a));
    }
    fn norm(a: Vec3) Vec3 {
        const L = length(a);
        if (L < 1e-6) return .{ .x = 0, .y = 1, .z = 0 };
        return scale(a, 1.0 / L);
    }
};

const Entity = struct {
    pos: Vec3,
    half: f32,
    color: ui.Color,
    name: []const u8,
};

/// Demo world: each cube is a stand-in for an ECS entity.
const ents = [_]Entity{
    .{ .pos = .{ .x = 0, .y = 14, .z = 0 }, .half = 14, .color = .{ 0.9, 0.3, 0.3, 1 }, .name = "Origin" },
    .{ .pos = .{ .x = 120, .y = 14, .z = -40 }, .half = 16, .color = .{ 0.3, 0.85, 0.4, 1 }, .name = "Hero" },
    .{ .pos = .{ .x = -80, .y = 18, .z = 90 }, .half = 18, .color = .{ 0.3, 0.5, 0.95, 1 }, .name = "Slime" },
    .{ .pos = .{ .x = 200, .y = 12, .z = 140 }, .half = 12, .color = .{ 0.95, 0.8, 0.2, 1 }, .name = "Torch" },
    .{ .pos = .{ .x = -160, .y = 22, .z = -100 }, .half = 20, .color = .{ 0.75, 0.4, 0.9, 1 }, .name = "Crystal" },
};

const Cam = struct {
    eye: Vec3,
    target: Vec3,
    forward: Vec3,
    right: Vec3,
    up: Vec3,
    fov_y: f32,
};

/// Turntable orbit (Blender-style): yaw around world Y, pitch about horizontal.
/// Basis always uses **world up** so the view never rolls inverted at the poles
/// (that made +Y appear stuck pointing down and orbit feel like only ~180°).
fn buildCam(st: *const state.State) Cam {
    const yaw = st.canvas_yaw;
    const pitch = st.canvas_pitch;
    const dist = st.canvas_dist;
    const cp = @cos(pitch);
    const sp = @sin(pitch);
    const cy = @cos(yaw);
    const sy = @sin(yaw);

    const target: Vec3 = .{ .x = st.canvas_tx, .y = st.canvas_ty, .z = st.canvas_tz };

    // Eye on a sphere around the target.
    // pitch = 0, yaw = 0 → on +Z (front); pitch = −π/2 → on +Y (top).
    const to_eye = Vec3{
        .x = dist * cp * sy,
        .y = dist * (-sp),
        .z = dist * cp * cy,
    };
    const eye = Vec3.add(target, to_eye);

    const forward = Vec3.norm(Vec3.sub(target, eye));
    const world_up: Vec3 = .{ .x = 0, .y = 1, .z = 0 };
    var right = Vec3.cross(forward, world_up);
    if (Vec3.length(right) < 1e-4) {
        // Nearly top/bottom — horizontal right from yaw.
        right = .{ .x = cy, .y = 0, .z = -sy };
    }
    right = Vec3.norm(right);
    const up = Vec3.norm(Vec3.cross(right, forward));

    return .{
        .eye = eye,
        .target = target,
        .forward = forward,
        .right = right,
        .up = up,
        .fov_y = 50.0 * std.math.pi / 180.0,
    };
}

/// Project world → screen. Must match sgl lookat + perspective (OpenGL-style,
/// Y-up NDC, FOV in radians). Screen origin is top-left (UI convention).
fn project(p: Vec3, cam: Cam, w: f32, h: f32) ?struct { x: f32, y: f32, z: f32 } {
    const rel = Vec3.sub(p, cam.eye);
    // Eye-space matching sgl/glu lookat: X=side, Y=up, Z=−forward
    const ex = Vec3.dot(rel, cam.right);
    const ey = Vec3.dot(rel, cam.up);
    const ez = -Vec3.dot(rel, cam.forward); // negative in front
    if (ez >= -1.0) return null; // behind / too near
    const f = 1.0 / @tan(cam.fov_y * 0.5);
    const aspect = w / @max(h, 1);
    // Perspective divide by −ez (positive depth in front)
    const ndc_x = (ex * f / aspect) / (-ez);
    const ndc_y = (ey * f) / (-ez);
    return .{
        .x = (ndc_x + 1) * 0.5 * w,
        .y = (1 - ndc_y) * 0.5 * h, // NDC +Y → screen top
        .z = -ez,
    };
}

fn cubeCorners(e: Entity) [8]Vec3 {
    const h = e.half;
    const p = e.pos;
    return .{
        .{ .x = p.x - h, .y = p.y - h, .z = p.z - h },
        .{ .x = p.x + h, .y = p.y - h, .z = p.z - h },
        .{ .x = p.x + h, .y = p.y + h, .z = p.z - h },
        .{ .x = p.x - h, .y = p.y + h, .z = p.z - h },
        .{ .x = p.x - h, .y = p.y - h, .z = p.z + h },
        .{ .x = p.x + h, .y = p.y - h, .z = p.z + h },
        .{ .x = p.x + h, .y = p.y + h, .z = p.z + h },
        .{ .x = p.x - h, .y = p.y + h, .z = p.z + h },
    };
}

fn drawCube(e: Entity, selected: bool, accent: ui.Color) void {
    const h = e.half;
    const p = e.pos;
    // 6 faces, slight per-face shade (fake light from upper-right)
    const faces = [_]struct { n: Vec3, verts: [4]Vec3 }{
        .{ // +Y top
            .n = .{ .x = 0, .y = 1, .z = 0 },
            .verts = .{
                .{ .x = p.x - h, .y = p.y + h, .z = p.z - h },
                .{ .x = p.x + h, .y = p.y + h, .z = p.z - h },
                .{ .x = p.x + h, .y = p.y + h, .z = p.z + h },
                .{ .x = p.x - h, .y = p.y + h, .z = p.z + h },
            },
        },
        .{ // -Y bottom
            .n = .{ .x = 0, .y = -1, .z = 0 },
            .verts = .{
                .{ .x = p.x - h, .y = p.y - h, .z = p.z + h },
                .{ .x = p.x + h, .y = p.y - h, .z = p.z + h },
                .{ .x = p.x + h, .y = p.y - h, .z = p.z - h },
                .{ .x = p.x - h, .y = p.y - h, .z = p.z - h },
            },
        },
        .{ // +Z
            .n = .{ .x = 0, .y = 0, .z = 1 },
            .verts = .{
                .{ .x = p.x - h, .y = p.y - h, .z = p.z + h },
                .{ .x = p.x + h, .y = p.y - h, .z = p.z + h },
                .{ .x = p.x + h, .y = p.y + h, .z = p.z + h },
                .{ .x = p.x - h, .y = p.y + h, .z = p.z + h },
            },
        },
        .{ // -Z
            .n = .{ .x = 0, .y = 0, .z = -1 },
            .verts = .{
                .{ .x = p.x + h, .y = p.y - h, .z = p.z - h },
                .{ .x = p.x - h, .y = p.y - h, .z = p.z - h },
                .{ .x = p.x - h, .y = p.y + h, .z = p.z - h },
                .{ .x = p.x + h, .y = p.y + h, .z = p.z - h },
            },
        },
        .{ // +X
            .n = .{ .x = 1, .y = 0, .z = 0 },
            .verts = .{
                .{ .x = p.x + h, .y = p.y - h, .z = p.z + h },
                .{ .x = p.x + h, .y = p.y - h, .z = p.z - h },
                .{ .x = p.x + h, .y = p.y + h, .z = p.z - h },
                .{ .x = p.x + h, .y = p.y + h, .z = p.z + h },
            },
        },
        .{ // -X
            .n = .{ .x = -1, .y = 0, .z = 0 },
            .verts = .{
                .{ .x = p.x - h, .y = p.y - h, .z = p.z - h },
                .{ .x = p.x - h, .y = p.y - h, .z = p.z + h },
                .{ .x = p.x - h, .y = p.y + h, .z = p.z + h },
                .{ .x = p.x - h, .y = p.y + h, .z = p.z - h },
            },
        },
    };

    const light = Vec3.norm(.{ .x = 0.4, .y = 0.85, .z = 0.35 });
    sgl.beginQuads();
    for (faces) |face| {
        const ndl = @max(0.25, Vec3.dot(face.n, light));
        sgl.c4f(e.color[0] * ndl, e.color[1] * ndl, e.color[2] * ndl, e.color[3]);
        for (face.verts) |v| sgl.v3f(v.x, v.y, v.z);
    }
    sgl.end();

    // Selection outline — expanded wireframe in accent
    if (selected) {
        const o = h + 2.5;
        const c = e.pos;
        const corners = [_]Vec3{
            .{ .x = c.x - o, .y = c.y - o, .z = c.z - o },
            .{ .x = c.x + o, .y = c.y - o, .z = c.z - o },
            .{ .x = c.x + o, .y = c.y + o, .z = c.z - o },
            .{ .x = c.x - o, .y = c.y + o, .z = c.z - o },
            .{ .x = c.x - o, .y = c.y - o, .z = c.z + o },
            .{ .x = c.x + o, .y = c.y - o, .z = c.z + o },
            .{ .x = c.x + o, .y = c.y + o, .z = c.z + o },
            .{ .x = c.x - o, .y = c.y + o, .z = c.z + o },
        };
        const edges = [_][2]u8{
            .{ 0, 1 }, .{ 1, 2 }, .{ 2, 3 }, .{ 3, 0 },
            .{ 4, 5 }, .{ 5, 6 }, .{ 6, 7 }, .{ 7, 4 },
            .{ 0, 4 }, .{ 1, 5 }, .{ 2, 6 }, .{ 3, 7 },
        };
        sgl.beginLines();
        sgl.c4f(accent[0], accent[1], accent[2], 1);
        for (edges) |ed| {
            const a = corners[ed[0]];
            const b = corners[ed[1]];
            sgl.v3f(a.x, a.y, a.z);
            sgl.v3f(b.x, b.y, b.z);
        }
        // second pass slightly larger for “shader outline” thickness
        sgl.c4f(accent[0], accent[1], accent[2], 0.55);
        const o2 = h + 4.0;
        const corners2 = [_]Vec3{
            .{ .x = c.x - o2, .y = c.y - o2, .z = c.z - o2 },
            .{ .x = c.x + o2, .y = c.y - o2, .z = c.z - o2 },
            .{ .x = c.x + o2, .y = c.y + o2, .z = c.z - o2 },
            .{ .x = c.x - o2, .y = c.y + o2, .z = c.z - o2 },
            .{ .x = c.x - o2, .y = c.y - o2, .z = c.z + o2 },
            .{ .x = c.x + o2, .y = c.y - o2, .z = c.z + o2 },
            .{ .x = c.x + o2, .y = c.y + o2, .z = c.z + o2 },
            .{ .x = c.x - o2, .y = c.y + o2, .z = c.z + o2 },
        };
        for (edges) |ed| {
            const a = corners2[ed[0]];
            const b = corners2[ed[1]];
            sgl.v3f(a.x, a.y, a.z);
            sgl.v3f(b.x, b.y, b.z);
        }
        sgl.end();
    }
}

fn drawGrid(extent: f32, step: f32) void {
    sgl.beginLines();
    // Grid on XZ ground plane (Y=0)
    sgl.c4f(0.22, 0.24, 0.28, 1);
    var x: f32 = -extent;
    while (x <= extent + 0.1) : (x += step) {
        sgl.v3f(x, 0, -extent);
        sgl.v3f(x, 0, extent);
    }
    var z: f32 = -extent;
    while (z <= extent + 0.1) : (z += step) {
        sgl.v3f(-extent, 0, z);
        sgl.v3f(extent, 0, z);
    }
    // Axes
    sgl.c4f(0.75, 0.25, 0.25, 1);
    sgl.v3f(0, 0.05, 0);
    sgl.v3f(extent * 0.5, 0.05, 0);
    sgl.c4f(0.25, 0.7, 0.35, 1);
    sgl.v3f(0, 0, 0);
    sgl.v3f(0, extent * 0.35, 0);
    sgl.c4f(0.3, 0.45, 0.9, 1);
    sgl.v3f(0, 0.05, 0);
    sgl.v3f(0, 0.05, extent * 0.5);
    sgl.end();
}

/// Ray vs axis-aligned box; returns distance along ray or null.
fn rayAabb(orig: Vec3, dir: Vec3, bmin: Vec3, bmax: Vec3) ?f32 {
    var tmin: f32 = 0;
    var tmax: f32 = 1e9;
    const dims = [_]struct { o: f32, d: f32, mn: f32, mx: f32 }{
        .{ .o = orig.x, .d = dir.x, .mn = bmin.x, .mx = bmax.x },
        .{ .o = orig.y, .d = dir.y, .mn = bmin.y, .mx = bmax.y },
        .{ .o = orig.z, .d = dir.z, .mn = bmin.z, .mx = bmax.z },
    };
    for (dims) |a| {
        if (@abs(a.d) < 1e-8) {
            if (a.o < a.mn or a.o > a.mx) return null;
            continue;
        }
        var t0 = (a.mn - a.o) / a.d;
        var t1 = (a.mx - a.o) / a.d;
        if (t0 > t1) {
            const tmp = t0;
            t0 = t1;
            t1 = tmp;
        }
        tmin = @max(tmin, t0);
        tmax = @min(tmax, t1);
        if (tmax < tmin) return null;
    }
    if (tmin >= 0) return tmin;
    if (tmax >= 0) return tmax;
    return null;
}

/// Pick only the solid cube (mesh AABB) — labels are not clickable.
fn pickEntity(mx: f32, my: f32, cam: Cam, w: f32, h: f32) i32 {
    // Screen → NDC (top-left UI → OpenGL Y-up NDC)
    const ndc_x = (2.0 * mx / w) - 1.0;
    const ndc_y = 1.0 - (2.0 * my / h);
    const t = @tan(cam.fov_y * 0.5);
    const aspect = w / @max(h, 1);
    // Eye-space ray (GL: looks down −Z), then to world via camera basis.
    const dir = Vec3.norm(Vec3.add(
        Vec3.add(
            Vec3.scale(cam.right, ndc_x * aspect * t),
            Vec3.scale(cam.up, ndc_y * t),
        ),
        cam.forward,
    ));
    const orig = cam.eye;

    var best: i32 = -1;
    var best_t: f32 = 1e9;
    for (ents, 0..) |e, i| {
        const bmin = Vec3{ .x = e.pos.x - e.half, .y = e.pos.y - e.half, .z = e.pos.z - e.half };
        const bmax = Vec3{ .x = e.pos.x + e.half, .y = e.pos.y + e.half, .z = e.pos.z + e.half };
        if (rayAabb(orig, dir, bmin, bmax)) |hit_t| {
            if (hit_t < best_t) {
                best_t = hit_t;
                best = @intCast(i);
            }
        }
    }
    return best;
}

pub fn frame(a: *app.App) void {
    const u = &a.ui;
    const st = &a.scene_state;
    const w = a.width;
    const h = a.height;

    // --- Blender-style view presets (numpad or top-row 1/3/7) ---
    // 7 = Top, 1 = Front, 3 = Right
    if (a.input.keyPressed(.seven)) {
        st.canvas_yaw = 0;
        st.canvas_pitch = -std.math.pi * 0.5 + 0.02;
    }
    if (a.input.keyPressed(.one)) {
        st.canvas_yaw = 0;
        st.canvas_pitch = 0;
    }
    if (a.input.keyPressed(.three)) {
        // From +X looking toward −X (Blender “Right”)
        st.canvas_yaw = std.math.pi * 0.5;
        st.canvas_pitch = 0;
    }

    // Dolly (wheel)
    const dy = u.wheelY();
    if (dy != 0) {
        const factor: f32 = if (dy > 0) 0.9 else 1.0 / 0.9;
        st.canvas_dist = std.math.clamp(st.canvas_dist * factor, 80, 2500);
        u.eatScroll();
    }

    // Orbit — middle mouse drag (turntable).
    // Natural “grab the view”: drag right → orbit right; drag up → tilt up
    // (previous signs felt inverted). Pitch is clamped just inside ±90° so we
    // never hit true gimbal lock; yaw is free → full 360° around world Y.
    if (a.input.mousePressed(.middle)) st.canvas_orbiting = true;
    if (a.input.mouseReleased(.middle)) st.canvas_orbiting = false;
    if (st.canvas_orbiting and a.input.mouseDown(.middle)) {
        const sens: f32 = 0.005;
        st.canvas_yaw -= a.input.mouse_dx * sens;
        st.canvas_pitch += a.input.mouse_dy * sens;
        // Keep a tiny margin from ±π/2 so world-up lookat stays stable.
        const lim: f32 = std.math.pi * 0.5 - 0.02;
        st.canvas_pitch = std.math.clamp(st.canvas_pitch, -lim, lim);
    }

    // Pan — Space + LMB (move look target in camera plane)
    const space_pan = a.input.keyDown(.space) and a.input.mouseDown(.left);
    if (space_pan) st.canvas_panning = true;
    if (!a.input.mouseDown(.left) or !a.input.keyDown(.space)) st.canvas_panning = false;

    var cam = buildCam(st);

    if (st.canvas_panning) {
        // Screen drag → world along camera right / up
        const k = st.canvas_dist * 0.0022;
        const r = Vec3.scale(cam.right, -a.input.mouse_dx * k);
        const uu = Vec3.scale(cam.up, a.input.mouse_dy * k);
        st.canvas_tx += r.x + uu.x;
        st.canvas_ty += r.y + uu.y;
        st.canvas_tz += r.z + uu.z;
        cam = buildCam(st);
    }

    // Select — LMB click (not pan)
    if (a.input.mousePressed(.left) and !a.input.keyDown(.space) and !u.palette_open) {
        // Avoid UI chrome at top ~60px for HUD — still allow world pick there if empty
        const hit = pickEntity(a.input.mouse_x, a.input.mouse_y, cam, w, h);
        st.canvas_sel = hit;
        if (hit >= 0) {
            u.log("canvas select");
        }
    }

    // --- 3D pass ---
    sgl.defaults();
    if (a.pip_3d.id != 0) sgl.loadPipeline(a.pip_3d);
    sgl.matrixModeProjection();
    sgl.loadIdentity();
    const aspect = w / @max(h, 1);
    // sgl_perspective takes FOV in *radians* (sin(fovy/2) with no deg conversion).
    // Passing degrees made the GPU frustum disagree with project() → labels floated
    // free of their cubes and the view felt orientation-broken / “gimbal locked”.
    sgl.perspective(cam.fov_y, aspect, 1.0, 8000.0);
    sgl.matrixModeModelview();
    sgl.loadIdentity();
    // Turntable: fixed world up so +Y stays upright on screen (never rolls inverted).
    sgl.lookat(
        cam.eye.x,
        cam.eye.y,
        cam.eye.z,
        cam.target.x,
        cam.target.y,
        cam.target.z,
        0,
        1,
        0,
    );

    drawGrid(400, 40);

    for (ents, 0..) |e, i| {
        const sel = st.canvas_sel == @as(i32, @intCast(i));
        drawCube(e, sel, u.theme.accent);
    }

    // --- Restore 2D for UI overlay text ---
    sgl.matrixModeProjection();
    sgl.loadIdentity();
    sgl.ortho(0, w, h, 0, -1, 1);
    sgl.matrixModeModelview();
    sgl.loadIdentity();
    if (a.pip_alpha.id != 0) sgl.loadPipeline(a.pip_alpha);

    // Labels track each cube’s transform: just above the top face, centered.
    // (Not clickable — picking is mesh-only via ray/AABB.)
    for (ents, 0..) |e, i| {
        const anchor = Vec3.add(e.pos, .{ .x = 0, .y = e.half + 6, .z = 0 });
        if (project(anchor, cam, w, h)) |s| {
            const sel = st.canvas_sel == @as(i32, @intCast(i));
            const col = if (sel) u.theme.accent else u.theme.text;
            const tw = u.font.measure(e.name, 1.5).w;
            u.drawText(s.x - tw * 0.5, s.y - 10, 1.5, col, e.name);
        }
    }

    // HUD
    u.drawText(16, 16, 2.0, u.theme.text, "scene: canvas — 3D orbit viewport");
    u.drawText(16, 40, 1.5, u.theme.text_dim, "MMB orbit  |  Space+LMB pan  |  wheel dolly  |  LMB select");
    u.drawText(16, 58, 1.5, u.theme.text_dim, "Numpad/keys 7 top  ·  1 front  ·  3 right  (Blender)");

    var buf: [96]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "yaw {d:.2}  pitch {d:.2}  dist {d:.0}  sel {d}", .{
        st.canvas_yaw,
        st.canvas_pitch,
        st.canvas_dist,
        st.canvas_sel,
    }) catch "";
    u.drawText(16, h - 40, 1.5, u.theme.text_dim, msg);
    u.drawText(16, h - 22, 1.5, u.theme.text_dim, "Ctrl+P palette  |  type scene");
}
