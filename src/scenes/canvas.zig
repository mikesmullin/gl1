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

// --- Game9-inspired raycasting ---------------------------------------------
// Game9 (`Camera.c`): Ray {pos, dir}, GetScreenToWorldRay via unproject
// near/far through inverse(P*V), GetWorldToScreen via P*V + Y flip.
// Intersection is separate (plane / rect / …). We add AABB for solid cubes.

/// Game9-style ray: origin + normalized direction.
const Ray = struct {
    pos: Vec3 = .{},
    dir: Vec3 = .{ .x = 0, .y = 0, .z = -1 },
};

/// Column-major 4×4 (OpenGL / sokol_gl layout).
const Mat4 = struct {
    /// m[col][row]
    m: [4][4]f32 = .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    },

    fn mul(a: Mat4, b: Mat4) Mat4 {
        var r: Mat4 = .{};
        var c: usize = 0;
        while (c < 4) : (c += 1) {
            var row: usize = 0;
            while (row < 4) : (row += 1) {
                r.m[c][row] =
                    a.m[0][row] * b.m[c][0] +
                    a.m[1][row] * b.m[c][1] +
                    a.m[2][row] * b.m[c][2] +
                    a.m[3][row] * b.m[c][3];
            }
        }
        return r;
    }

    fn mulV4(a: Mat4, v: [4]f32) [4]f32 {
        return .{
            a.m[0][0] * v[0] + a.m[1][0] * v[1] + a.m[2][0] * v[2] + a.m[3][0] * v[3],
            a.m[0][1] * v[0] + a.m[1][1] * v[1] + a.m[2][1] * v[2] + a.m[3][1] * v[3],
            a.m[0][2] * v[0] + a.m[1][2] * v[1] + a.m[2][2] * v[2] + a.m[3][2] * v[3],
            a.m[0][3] * v[0] + a.m[1][3] * v[1] + a.m[2][3] * v[2] + a.m[3][3] * v[3],
        };
    }

    /// Invert affine/projection matrix (general 4×4 via adjugate).
    fn inverse(a: Mat4) Mat4 {
        // Flatten column-major → row-major for classic inverse.
        var m: [16]f32 = undefined;
        var c: usize = 0;
        while (c < 4) : (c += 1) {
            var r: usize = 0;
            while (r < 4) : (r += 1) m[r * 4 + c] = a.m[c][r];
        }
        var inv: [16]f32 = undefined;
        inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] + m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10];
        inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] - m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10];
        inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] + m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9];
        inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] - m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9];
        inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] - m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10];
        inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] + m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10];
        inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] - m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9];
        inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] + m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9];
        inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] + m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6];
        inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] - m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6];
        inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] + m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5];
        inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] - m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5];
        inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] - m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6];
        inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] + m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6];
        inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] - m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5];
        inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] + m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5];
        const det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12];
        if (@abs(det) < 1e-12) return .{};
        const idet = 1.0 / det;
        var out: Mat4 = .{};
        c = 0;
        while (c < 4) : (c += 1) {
            var r: usize = 0;
            while (r < 4) : (r += 1) {
                // inv is row-major; store column-major
                out.m[c][r] = inv[r * 4 + c] * idet;
            }
        }
        return out;
    }
};

/// Match sgl_perspective (FOV radians, column-major m[col][row]).
fn matPerspective(fovy: f32, aspect: f32, znear: f32, zfar: f32) Mat4 {
    const sine = @sin(fovy * 0.5);
    const cotan = @cos(fovy * 0.5) / sine;
    const dz = zfar - znear;
    // sgl: v[0][0]=cot/aspect, v[1][1]=cot, v[2][2]=-(f+n)/dz, v[2][3]=-1, v[3][2]=-2nf/dz, v[3][3]=0
    return .{ .m = .{
        .{ cotan / aspect, 0, 0, 0 },
        .{ 0, cotan, 0, 0 },
        .{ 0, 0, -(zfar + znear) / dz, -1 },
        .{ 0, 0, -2 * znear * zfar / dz, 0 },
    } };
}

/// Match sgl_lookat exactly (column-major).
/// sgl stores col0=(side.x, up.x, -fwd.x, 0) etc — NOT (side.x, side.y, side.z).
fn matLookAt(eye: Vec3, center: Vec3, up_in: Vec3) Mat4 {
    const fwd = Vec3.norm(Vec3.sub(center, eye));
    var side = Vec3.cross(fwd, up_in);
    side = Vec3.norm(side);
    const up = Vec3.cross(side, fwd);
    // Then sgl multiplies by T(-eye): col3 = R * (-eye) in rotation basis.
    return .{ .m = .{
        .{ side.x, up.x, -fwd.x, 0 },
        .{ side.y, up.y, -fwd.y, 0 },
        .{ side.z, up.z, -fwd.z, 0 },
        .{
            -Vec3.dot(side, eye),
            -Vec3.dot(up, eye),
            Vec3.dot(fwd, eye),
            1,
        },
    } };
}

/// Game9 GetScreenToWorldRay: unproject near/far via inv(P·V); origin = eye.
fn screenToWorldRay(mx: f32, my: f32, w: f32, h: f32, eye: Vec3, inv_pv: Mat4) Ray {
    const ndc_x = (2.0 * mx / w) - 1.0;
    const ndc_y = 1.0 - (2.0 * my / h);
    const near_h = Mat4.mulV4(inv_pv, .{ ndc_x, ndc_y, -1.0, 1.0 });
    const far_h = Mat4.mulV4(inv_pv, .{ ndc_x, ndc_y, 1.0, 1.0 });
    const nw = 1.0 / near_h[3];
    const fw = 1.0 / far_h[3];
    const near_w = Vec3{ .x = near_h[0] * nw, .y = near_h[1] * nw, .z = near_h[2] * nw };
    const far_w = Vec3{ .x = far_h[0] * fw, .y = far_h[1] * fw, .z = far_h[2] * fw };
    return .{
        .pos = eye,
        .dir = Vec3.norm(Vec3.sub(far_w, near_w)),
    };
}

/// Game9 GetWorldToScreen: P·V · p, perspective divide, flip Y for top-left UI.
fn worldToScreen(p: Vec3, w: f32, h: f32, pv: Mat4) ?struct { x: f32, y: f32, z: f32 } {
    const clip = Mat4.mulV4(pv, .{ p.x, p.y, p.z, 1.0 });
    if (@abs(clip[3]) < 1e-8) return null;
    const iw = 1.0 / clip[3];
    const ndc_x = clip[0] * iw;
    const ndc_y = clip[1] * iw;
    const ndc_z = clip[2] * iw;
    // Allow a little slack past the clip volume for labels near the rim.
    if (ndc_z < -1.05 or ndc_z > 1.05) return null;
    return .{
        .x = (ndc_x + 1.0) * 0.5 * w,
        .y = (1.0 - ndc_y) * 0.5 * h,
        .z = ndc_z,
    };
}

/// Also keep camera-basis project as a cross-check path (matches buildCam side/up/fwd
/// which mirrors sgl lookat side/up/fwd). Used if inv fails.
fn worldToScreenBasis(p: Vec3, cam: Cam, w: f32, h: f32) ?struct { x: f32, y: f32, z: f32 } {
    const rel = Vec3.sub(p, cam.eye);
    // sgl lookat eye-space: X=side, Y=up, Z=-fwd
    const ex = Vec3.dot(rel, cam.right);
    const ey = Vec3.dot(rel, cam.up);
    const ez = -Vec3.dot(rel, cam.forward);
    if (ez >= -0.5) return null;
    const f = 1.0 / @tan(cam.fov_y * 0.5);
    const aspect = w / @max(h, 1);
    const ndc_x = (ex * f / aspect) / (-ez);
    const ndc_y = (ey * f) / (-ez);
    return .{
        .x = (ndc_x + 1.0) * 0.5 * w,
        .y = (1.0 - ndc_y) * 0.5 * h,
        .z = -ez,
    };
}

fn screenToWorldRayBasis(mx: f32, my: f32, w: f32, h: f32, cam: Cam) Ray {
    const ndc_x = (2.0 * mx / w) - 1.0;
    const ndc_y = 1.0 - (2.0 * my / h);
    const t = @tan(cam.fov_y * 0.5);
    const aspect = w / @max(h, 1);
    // Eye-space dir (looks down -Z) → world via side/up/fwd
    const dir = Vec3.norm(.{
        .x = cam.right.x * (ndc_x * aspect * t) + cam.up.x * (ndc_y * t) + cam.forward.x,
        .y = cam.right.y * (ndc_x * aspect * t) + cam.up.y * (ndc_y * t) + cam.forward.y,
        .z = cam.right.z * (ndc_x * aspect * t) + cam.up.z * (ndc_y * t) + cam.forward.z,
    });
    return .{ .pos = cam.eye, .dir = dir };
}

const Entity = struct {
    pos: Vec3,
    half: f32,
    color: ui.Color,
    name: []const u8,
};

/// Demo world: each cube is a stand-in for an ECS entity.
/// (No “Origin” mesh — world origin is implied by the compass + grid.)
const ents = [_]Entity{
    .{ .pos = .{ .x = 120, .y = 14, .z = -40 }, .half = 16, .color = .{ 0.3, 0.85, 0.4, 1 }, .name = "Hero" },
    .{ .pos = .{ .x = -80, .y = 18, .z = 90 }, .half = 18, .color = .{ 0.3, 0.5, 0.95, 1 }, .name = "Slime" },
    .{ .pos = .{ .x = 200, .y = 12, .z = 140 }, .half = 12, .color = .{ 0.95, 0.8, 0.2, 1 }, .name = "Torch" },
    .{ .pos = .{ .x = -160, .y = 22, .z = -100 }, .half = 20, .color = .{ 0.75, 0.4, 0.9, 1 }, .name = "Crystal" },
    .{ .pos = .{ .x = 40, .y = 16, .z = 60 }, .half = 14, .color = .{ 0.9, 0.55, 0.2, 1 }, .name = "Crate" },
};

fn isSelected(st: *const state.State, i: usize) bool {
    return (st.canvas_sel_mask & (@as(u32, 1) << @intCast(i))) != 0;
}

fn setSelected(st: *state.State, i: usize, on: bool) void {
    const bit = @as(u32, 1) << @intCast(i);
    if (on) st.canvas_sel_mask |= bit else st.canvas_sel_mask &= ~bit;
}

fn clearSelection(st: *state.State) void {
    st.canvas_sel_mask = 0;
    st.canvas_sel_primary = -1;
}

fn orbitPivot(st: *const state.State) Vec3 {
    if (st.canvas_sel_primary >= 0 and st.canvas_sel_primary < ents.len) {
        return ents[@intCast(st.canvas_sel_primary)].pos;
    }
    // No selection: keep current look target (screen-center focus).
    return .{ .x = st.canvas_tx, .y = st.canvas_ty, .z = st.canvas_tz };
}

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

    // Same basis as sgl_lookat: side = normalize(fwd × world_up), up = side × fwd.
    const forward = Vec3.norm(Vec3.sub(target, eye));
    const world_up: Vec3 = .{ .x = 0, .y = 1, .z = 0 };
    var side = Vec3.cross(forward, world_up);
    if (Vec3.length(side) < 1e-4) {
        side = .{ .x = cy, .y = 0, .z = -sy };
    }
    side = Vec3.norm(side);
    const up = Vec3.cross(side, forward); // already unit if side⊥fwd

    return .{
        .eye = eye,
        .target = target,
        .forward = forward,
        .right = side,
        .up = up,
        .fov_y = 50.0 * std.math.pi / 180.0,
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
    // Grid on XZ ground plane (Y=0) — no world-origin gizmo (compass is corner HUD).
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
    sgl.end();
}

/// Always-on orientation compass (top-right): how world +X/+Y/+Z project on screen.
fn drawCompass(u: anytype, cam: Cam, screen_w: f32) void {
    const ox = screen_w - 56;
    const oy: f32 = 56;
    const len: f32 = 36;
    const axes = [_]struct { v: Vec3, c: ui.Color, label: []const u8 }{
        .{ .v = .{ .x = 1, .y = 0, .z = 0 }, .c = .{ 0.9, 0.3, 0.3, 1 }, .label = "X" },
        .{ .v = .{ .x = 0, .y = 1, .z = 0 }, .c = .{ 0.3, 0.85, 0.4, 1 }, .label = "Y" },
        .{ .v = .{ .x = 0, .y = 0, .z = 1 }, .c = .{ 0.35, 0.55, 0.95, 1 }, .label = "Z" },
    };
    // Dim disc behind
    u.drawRect(.{ .x = ox - 42, .y = oy - 42, .w = 84, .h = 84 }, .{ 0.08, 0.09, 0.11, 0.65 });
    for (axes) |ax| {
        // Project world axis onto camera right/up (view plane).
        const sx = Vec3.dot(ax.v, cam.right) * len;
        const sy = -Vec3.dot(ax.v, cam.up) * len; // screen Y down
        const x1 = ox + sx;
        const y1 = oy + sy;
        // Thick-ish line via rect segments
        const steps: i32 = 12;
        var s: i32 = 0;
        while (s <= steps) : (s += 1) {
            const t = @as(f32, @floatFromInt(s)) / @as(f32, @floatFromInt(steps));
            const px = ox + sx * t;
            const py = oy + sy * t;
            u.drawRect(.{ .x = px - 1.5, .y = py - 1.5, .w = 3, .h = 3 }, ax.c);
        }
        u.drawText(x1 + 4, y1 - 6, 1.5, ax.c, ax.label);
    }
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

/// Pick solid cube only (labels never generate hits). Game9 pattern:
/// build ray once, then run per-object intersection, keep nearest hit.
fn pickEntity(ray: Ray) i32 {
    var best: i32 = -1;
    var best_t: f32 = 1e9;
    for (ents, 0..) |e, i| {
        const bmin = Vec3{ .x = e.pos.x - e.half, .y = e.pos.y - e.half, .z = e.pos.z - e.half };
        const bmax = Vec3{ .x = e.pos.x + e.half, .y = e.pos.y + e.half, .z = e.pos.z + e.half };
        if (rayAabb(ray.pos, ray.dir, bmin, bmax)) |hit_t| {
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

    // Orbit pivot: selected entity (primary), else current look-target (= screen center focus).
    if (a.input.mousePressed(.middle)) {
        st.canvas_orbiting = true;
        const pivot = orbitPivot(st);
        st.canvas_tx = pivot.x;
        st.canvas_ty = pivot.y;
        st.canvas_tz = pivot.z;
    }
    if (a.input.mouseReleased(.middle)) st.canvas_orbiting = false;
    if (st.canvas_orbiting and a.input.mouseDown(.middle)) {
        // Keep orbiting the selection if it is still the primary.
        if (st.canvas_sel_primary >= 0) {
            const pivot = orbitPivot(st);
            st.canvas_tx = pivot.x;
            st.canvas_ty = pivot.y;
            st.canvas_tz = pivot.z;
        }
        const sens: f32 = 0.005;
        // Yaw around world Y — match Blender turntable (was inverted).
        st.canvas_yaw += a.input.mouse_dx * sens;
        st.canvas_pitch += a.input.mouse_dy * sens;
        const lim: f32 = std.math.pi * 0.5 - 0.02;
        st.canvas_pitch = std.math.clamp(st.canvas_pitch, -lim, lim);
    }

    // Pan — Space + LMB (move look target in camera plane)
    const space_pan = a.input.keyDown(.space) and a.input.mouseDown(.left);
    if (space_pan) st.canvas_panning = true;
    if (!a.input.mouseDown(.left) or !a.input.keyDown(.space)) st.canvas_panning = false;

    var cam = buildCam(st);
    if (st.canvas_panning) {
        const k = st.canvas_dist * 0.0022;
        const r = Vec3.scale(cam.right, -a.input.mouse_dx * k);
        const uu = Vec3.scale(cam.up, a.input.mouse_dy * k);
        st.canvas_tx += r.x + uu.x;
        st.canvas_ty += r.y + uu.y;
        st.canvas_tz += r.z + uu.z;
        cam = buildCam(st);
    }

    // --- Fly navigation (Unity / Blender Walk-Fly style) ---
    // WASD = forward / left / back / right along view
    // Q = down, E / Space = up  (world Y)
    // Shift = faster
    // Skip when a text field has focus so typing isn't stolen.
    if (u.focus.isNone() and !u.palette_open) {
        const base_speed: f32 = 180.0;
        const speed = if (a.input.shift) base_speed * 2.5 else base_speed;
        const step = speed * a.dt;
        var move = Vec3{};
        if (a.input.keyDown(.w)) move = Vec3.add(move, cam.forward);
        if (a.input.keyDown(.s)) move = Vec3.sub(move, cam.forward);
        if (a.input.keyDown(.d)) move = Vec3.add(move, cam.right);
        if (a.input.keyDown(.a)) move = Vec3.sub(move, cam.right);
        // Vertical: world up so flying feels level (not camera-tilt dependent).
        // Space = up unless Space+LMB pan is active.
        if (a.input.keyDown(.e) or (a.input.keyDown(.space) and !a.input.mouseDown(.left)))
            move = Vec3.add(move, .{ .x = 0, .y = 1, .z = 0 });
        if (a.input.keyDown(.q)) move = Vec3.add(move, .{ .x = 0, .y = -1, .z = 0 });
        if (Vec3.length(move) > 1e-4) {
            move = Vec3.scale(Vec3.norm(move), step);
            st.canvas_tx += move.x;
            st.canvas_ty += move.y;
            st.canvas_tz += move.z;
            cam = buildCam(st);
        }
    }

    const aspect = w / @max(h, 1);
    const znear: f32 = 1.0;
    const zfar: f32 = 8000.0;
    // Build P·V matching sgl (for validation / future tools). Labels + pick use the
    // camera-basis path below — same side/up/fwd as sgl lookat, FOV in radians.
    const mat_p = matPerspective(cam.fov_y, aspect, znear, zfar);
    const mat_v = matLookAt(cam.eye, cam.target, .{ .x = 0, .y = 1, .z = 0 });
    const pv = Mat4.mul(mat_p, mat_v);
    _ = pv;

    // Select — LMB on mesh only. Ctrl/Shift = multi-select toggle; plain click replaces.
    if (a.input.mousePressed(.left) and !a.input.keyDown(.space) and !u.palette_open) {
        // Basis ray matches sgl lookat eye-space (was mis-calibrated when lookat matrix was transposed).
        const ray = screenToWorldRayBasis(a.input.mouse_x, a.input.mouse_y, w, h, cam);
        const hit = pickEntity(ray);
        const multi = a.input.ctrl or a.input.shift;
        if (hit < 0) {
            if (!multi) clearSelection(st);
        } else {
            const iu: usize = @intCast(hit);
            if (multi) {
                const on = !isSelected(st, iu);
                setSelected(st, iu, on);
                if (on) st.canvas_sel_primary = hit else if (st.canvas_sel_primary == hit) {
                    // Primary deselected — fall back to any remaining bit.
                    st.canvas_sel_primary = -1;
                    var bi: usize = 0;
                    while (bi < ents.len) : (bi += 1) {
                        if (isSelected(st, bi)) {
                            st.canvas_sel_primary = @intCast(bi);
                            break;
                        }
                    }
                }
            } else {
                clearSelection(st);
                setSelected(st, iu, true);
                st.canvas_sel_primary = hit;
            }
            u.log("canvas select");
        }
    }

    // --- 3D pass (sgl builds the same perspective/lookat we use for rays) ---
    sgl.defaults();
    if (a.pip_3d.id != 0) sgl.loadPipeline(a.pip_3d);
    sgl.matrixModeProjection();
    sgl.loadIdentity();
    sgl.perspective(cam.fov_y, aspect, znear, zfar);
    sgl.matrixModeModelview();
    sgl.loadIdentity();
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
        drawCube(e, isSelected(st, i), u.theme.accent);
    }

    // --- Restore 2D for UI overlay text ---
    sgl.matrixModeProjection();
    sgl.loadIdentity();
    sgl.ortho(0, w, h, 0, -1, 1);
    sgl.matrixModeModelview();
    sgl.loadIdentity();
    if (a.pip_alpha.id != 0) sgl.loadPipeline(a.pip_alpha);

    // Labels track cube tops (not clickable). Basis project matches GPU lookat+persp.
    for (ents, 0..) |e, i| {
        const anchor = Vec3.add(e.pos, .{ .x = 0, .y = e.half + 6, .z = 0 });
        if (worldToScreenBasis(anchor, cam, w, h)) |s| {
            const sel = isSelected(st, i);
            const col = if (sel) u.theme.accent else u.theme.text;
            const tw = u.font.measure(e.name, 1.5).w;
            u.drawText(s.x - tw * 0.5, s.y - 10, 1.5, col, e.name);
        }
    }

    drawCompass(u, cam, w);

    // HUD
    u.drawText(16, 16, 2.0, u.theme.text, "scene: canvas — 3D orbit viewport");
    u.drawText(16, 40, 1.5, u.theme.text_dim, "MMB orbit  |  Space+LMB pan  |  wheel dolly  |  WASD+QE fly");
    u.drawText(16, 58, 1.5, u.theme.text_dim, "LMB select  ·  Ctrl/Shift multi  ·  Shift=fast fly  ·  7/1/3 views");

    var buf: [96]u8 = undefined;
    const nsel = @popCount(st.canvas_sel_mask);
    const msg = std.fmt.bufPrint(&buf, "yaw {d:.2}  pitch {d:.2}  dist {d:.0}  sel {d} (primary {d})", .{
        st.canvas_yaw,
        st.canvas_pitch,
        st.canvas_dist,
        nsel,
        st.canvas_sel_primary,
    }) catch "";
    u.drawText(16, h - 40, 1.5, u.theme.text_dim, msg);
    u.drawText(16, h - 22, 1.5, u.theme.text_dim, "Ctrl+P palette  |  type scene");
}
