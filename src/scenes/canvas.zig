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

fn project(p: Vec3, cam: Cam, w: f32, h: f32) ?struct { x: f32, y: f32, z: f32 } {
    const rel = Vec3.sub(p, cam.eye);
    const cx = Vec3.dot(rel, cam.right);
    const cy = Vec3.dot(rel, cam.up);
    // Camera looks along +forward; depth positive in front
    const cz = Vec3.dot(rel, cam.forward);
    if (cz < 1.0) return null;
    const f = 1.0 / @tan(cam.fov_y * 0.5);
    const aspect = w / @max(h, 1);
    const ndc_x = (cx / cz) * f / aspect;
    const ndc_y = (cy / cz) * f;
    return .{
        .x = (ndc_x + 1) * 0.5 * w,
        .y = (1 - ndc_y) * 0.5 * h,
        .z = cz,
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

fn pickEntity(mx: f32, my: f32, cam: Cam, w: f32, h: f32) i32 {
    var best: i32 = -1;
    var best_z: f32 = 1e9;
    for (ents, 0..) |e, i| {
        var min_x: f32 = 1e9;
        var min_y: f32 = 1e9;
        var max_x: f32 = -1e9;
        var max_y: f32 = -1e9;
        var any = false;
        var avg_z: f32 = 0;
        var n: f32 = 0;
        for (cubeCorners(e)) |c| {
            if (project(c, cam, w, h)) |s| {
                any = true;
                min_x = @min(min_x, s.x);
                min_y = @min(min_y, s.y);
                max_x = @max(max_x, s.x);
                max_y = @max(max_y, s.y);
                avg_z += s.z;
                n += 1;
            }
        }
        if (!any) continue;
        // Pad pick region a little
        const pad: f32 = 4;
        if (mx >= min_x - pad and mx <= max_x + pad and my >= min_y - pad and my <= max_y + pad) {
            const z = avg_z / n;
            if (z < best_z) {
                best_z = z;
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
        st.canvas_yaw = -std.math.pi * 0.5;
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
    sgl.perspective(cam.fov_y * 180.0 / std.math.pi, aspect, 1.0, 8000.0);
    sgl.matrixModeModelview();
    sgl.loadIdentity();
    // Always pass world up into lookat (turntable) — matches buildCam and
    // prevents the view from rolling so the green +Y axis points “down”.
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

    // Projected labels
    for (ents, 0..) |e, i| {
        const top = Vec3.add(e.pos, .{ .x = 0, .y = e.half + 4, .z = 0 });
        if (project(top, cam, w, h)) |s| {
            const sel = st.canvas_sel == @as(i32, @intCast(i));
            const col = if (sel) u.theme.accent else u.theme.text;
            u.drawText(s.x - 20, s.y - 4, 1.5, col, e.name);
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
