//! Canvas / editor — Blender-like 3D viewport + Unity-style editor panels.
//! - MMB drag: orbit about look target
//! - Space+LMB: pan target in the camera plane
//! - Wheel: dolly (distance)
//! - Numpad / keys 7, 1, 3: Top / Front / Right (Blender convention)
//! - LMB click: select entity (accent outline)
//! - Floating panels: scene tree (left), inspector (right), console (bottom)

const std = @import("std");
const app = @import("../app.zig");
const ui = @import("../ui/ui.zig");
const state = @import("state.zig");
const editor = @import("editor.zig");
const anim = @import("../anim.zig");
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

fn toggleSelectAll(st: *state.State) void {
    // If everything alive is selected → clear; else select all alive.
    var all_mask: u32 = 0;
    var i: usize = 0;
    while (i < state.max_entities) : (i += 1) {
        if (st.entities[i].alive) all_mask |= @as(u32, 1) << @intCast(i);
    }
    if (all_mask != 0 and st.canvas_sel_mask == all_mask) {
        st.clearSelection();
    } else {
        st.selectAllAlive();
    }
}

fn entityPos(e: *const state.WorldEntity) Vec3 {
    return .{ .x = e.pos_x, .y = e.pos_y, .z = e.pos_z };
}

/// Local offset → world (scale + Yaw/Pitch/Roll as ZYX-ish: Y then X then Z simplified as Y only for mesh).
fn xformLocal(e: *const state.WorldEntity, lx: f32, ly: f32, lz: f32) Vec3 {
    const s = @max(0.05, e.scale);
    var x = lx * s;
    var y = ly * s;
    var z = lz * s;
    // Rot Y (degrees)
    const ry = e.rot_y * std.math.pi / 180.0;
    const cy = @cos(ry);
    const sy = @sin(ry);
    const x1 = x * cy + z * sy;
    const z1 = -x * sy + z * cy;
    x = x1;
    z = z1;
    // Rot X
    const rx = e.rot_x * std.math.pi / 180.0;
    const cx = @cos(rx);
    const sx = @sin(rx);
    const y1 = y * cx - z * sx;
    const z2 = y * sx + z * cx;
    y = y1;
    z = z2;
    // Rot Z
    const rz = e.rot_z * std.math.pi / 180.0;
    const cz = @cos(rz);
    const sz = @sin(rz);
    const x2 = x * cz - y * sz;
    const y2 = x * sz + y * cz;
    x = x2;
    y = y2;
    return .{ .x = e.pos_x + x, .y = e.pos_y + y, .z = e.pos_z + z };
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



fn drawCube(e: *const state.WorldEntity, selected: bool, accent: ui.Color) void {
    const h = e.half;
    // Local-space cube corners → world via scale + euler
    const local_faces = [_]struct { n: Vec3, verts: [4]Vec3 }{
        .{ .n = .{ .x = 0, .y = 1, .z = 0 }, .verts = .{
            .{ .x = -h, .y = h, .z = -h }, .{ .x = h, .y = h, .z = -h }, .{ .x = h, .y = h, .z = h }, .{ .x = -h, .y = h, .z = h },
        } },
        .{ .n = .{ .x = 0, .y = -1, .z = 0 }, .verts = .{
            .{ .x = -h, .y = -h, .z = h }, .{ .x = h, .y = -h, .z = h }, .{ .x = h, .y = -h, .z = -h }, .{ .x = -h, .y = -h, .z = -h },
        } },
        .{ .n = .{ .x = 0, .y = 0, .z = 1 }, .verts = .{
            .{ .x = -h, .y = -h, .z = h }, .{ .x = h, .y = -h, .z = h }, .{ .x = h, .y = h, .z = h }, .{ .x = -h, .y = h, .z = h },
        } },
        .{ .n = .{ .x = 0, .y = 0, .z = -1 }, .verts = .{
            .{ .x = h, .y = -h, .z = -h }, .{ .x = -h, .y = -h, .z = -h }, .{ .x = -h, .y = h, .z = -h }, .{ .x = h, .y = h, .z = -h },
        } },
        .{ .n = .{ .x = 1, .y = 0, .z = 0 }, .verts = .{
            .{ .x = h, .y = -h, .z = h }, .{ .x = h, .y = -h, .z = -h }, .{ .x = h, .y = h, .z = -h }, .{ .x = h, .y = h, .z = h },
        } },
        .{ .n = .{ .x = -1, .y = 0, .z = 0 }, .verts = .{
            .{ .x = -h, .y = -h, .z = -h }, .{ .x = -h, .y = -h, .z = h }, .{ .x = -h, .y = h, .z = h }, .{ .x = -h, .y = h, .z = -h },
        } },
    };

    const light = Vec3.norm(.{ .x = 0.4, .y = 0.85, .z = 0.35 });
    sgl.beginQuads();
    for (local_faces) |face| {
        // Transform normal by rotation only (approx: use face center delta)
        const n0 = xformLocal(e, face.n.x, face.n.y, face.n.z);
        const n1 = xformLocal(e, 0, 0, 0);
        const nw = Vec3.norm(Vec3.sub(n0, n1));
        const ndl = @max(0.25, Vec3.dot(nw, light));
        sgl.c4f(e.color[0] * ndl, e.color[1] * ndl, e.color[2] * ndl, e.color[3]);
        for (face.verts) |lv| {
            const v = xformLocal(e, lv.x, lv.y, lv.z);
            sgl.v3f(v.x, v.y, v.z);
        }
    }
    sgl.end();

    // Selection outline — expanded wireframe in accent
    if (selected) {
        const edges = [_][2]u8{
            .{ 0, 1 }, .{ 1, 2 }, .{ 2, 3 }, .{ 3, 0 },
            .{ 4, 5 }, .{ 5, 6 }, .{ 6, 7 }, .{ 7, 4 },
            .{ 0, 4 }, .{ 1, 5 }, .{ 2, 6 }, .{ 3, 7 },
        };
        sgl.beginLines();
        var pass: u32 = 0;
        while (pass < 2) : (pass += 1) {
            const pad: f32 = if (pass == 0) 2.5 else 4.0;
            const hl = e.half + pad / @max(0.05, e.scale);
            const cl = [_]Vec3{
                .{ .x = -hl, .y = -hl, .z = -hl }, .{ .x = hl, .y = -hl, .z = -hl },
                .{ .x = hl, .y = hl, .z = -hl }, .{ .x = -hl, .y = hl, .z = -hl },
                .{ .x = -hl, .y = -hl, .z = hl }, .{ .x = hl, .y = -hl, .z = hl },
                .{ .x = hl, .y = hl, .z = hl }, .{ .x = -hl, .y = hl, .z = hl },
            };
            var corners: [8]Vec3 = undefined;
            for (cl, 0..) |c, ci| corners[ci] = xformLocal(e, c.x, c.y, c.z);
            const a_col: f32 = if (pass == 0) 1 else 0.55;
            sgl.c4f(accent[0], accent[1], accent[2], a_col);
            for (edges) |ed| {
                const a = corners[ed[0]];
                const b = corners[ed[1]];
                sgl.v3f(a.x, a.y, a.z);
                sgl.v3f(b.x, b.y, b.z);
            }
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
/// `right_inset` is the width of UI docked on the right (e.g. expanded inspector + margin);
/// the gizmo sits left of that with a small gap so it is not covered.
fn drawCompass(u: anytype, cam: Cam, screen_w: f32, right_inset: f32) void {
    const gap: f32 = 8;
    const half: f32 = 42; // disc extends ±half from origin
    // Disc right edge at screen_w - right_inset - gap.
    const ox = screen_w - right_inset - gap - half;
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
/// Uses axis-aligned bounds from position ± halfScaled (rotation ignored for pick).
fn pickEntity(st: *const state.State, ray: Ray) i32 {
    var best: i32 = -1;
    var best_t: f32 = 1e9;
    var i: usize = 0;
    while (i < state.max_entities) : (i += 1) {
        const e = &st.entities[i];
        if (!e.alive) continue;
        const hs = e.halfScaled();
        const bmin = Vec3{ .x = e.pos_x - hs, .y = e.pos_y - hs, .z = e.pos_z - hs };
        const bmax = Vec3{ .x = e.pos_x + hs, .y = e.pos_y + hs, .z = e.pos_z + hs };
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

    // Dolly (wheel) — cancel frame anim if user zooms
    const dy = u.wheelY();
    if (dy != 0) {
        const factor: f32 = if (dy > 0) 0.9 else 1.0 / 0.9;
        st.canvas_dist = std.math.clamp(st.canvas_dist * factor, 80, 2500);
        st.canvas_frame.cancel();
        u.eatScroll();
    }

    // Numpad `.` / period: frame selection (center + zoom ~80% viewport).
    // Driven by Game9-inspired Timer + parallel Tweens (250ms, smoothstep).
    // Numpad `.` / period, or F (Blender-ish frame selected).
    if ((a.input.keyPressed(.period) or a.input.keyPressed(.f)) and st.selectionCount() != 0 and u.focus.isNone()) {
        var bmin = Vec3{ .x = 1e9, .y = 1e9, .z = 1e9 };
        var bmax = Vec3{ .x = -1e9, .y = -1e9, .z = -1e9 };
        var any = false;
        var fi: usize = 0;
        while (fi < state.max_entities) : (fi += 1) {
            if (!st.isSelected(fi)) continue;
            const e = &st.entities[fi];
            const hs = e.halfScaled();
            any = true;
            bmin.x = @min(bmin.x, e.pos_x - hs);
            bmin.y = @min(bmin.y, e.pos_y - hs);
            bmin.z = @min(bmin.z, e.pos_z - hs);
            bmax.x = @max(bmax.x, e.pos_x + hs);
            bmax.y = @max(bmax.y, e.pos_y + hs);
            bmax.z = @max(bmax.z, e.pos_z + hs);
        }
        if (any) {
            const center = Vec3{
                .x = (bmin.x + bmax.x) * 0.5,
                .y = (bmin.y + bmax.y) * 0.5,
                .z = (bmin.z + bmax.z) * 0.5,
            };
            const ext = Vec3.sub(bmax, bmin);
            const radius = 0.5 * @sqrt(ext.x * ext.x + ext.y * ext.y + ext.z * ext.z);
            const fov = 50.0 * std.math.pi / 180.0;
            const half_fit = 0.4 * fov;
            var dist = radius / @tan(half_fit);
            const aspect = w / @max(h, 1);
            if (aspect > 1) {
                const half_h_fit = std.math.atan(@tan(half_fit) * aspect);
                dist = @max(dist, radius / @tan(half_h_fit));
            }
            dist = std.math.clamp(dist, 80, 2500);

            st.canvas_frame.reset();
            st.canvas_frame.add(st.canvas_tx, center.x);
            st.canvas_frame.add(st.canvas_ty, center.y);
            st.canvas_frame.add(st.canvas_tz, center.z);
            st.canvas_frame.add(st.canvas_dist, dist);
            st.canvas_frame.play(a.time, 0.25);
        }
    }

    // Sample parallel tweens into camera (Game9 pull-style evaluation).
    if (st.canvas_frame.timer.playing()) {
        var outs: [4]f32 = undefined;
        _ = st.canvas_frame.tickInto(a.time, outs[0..]);
        st.canvas_tx = outs[0];
        st.canvas_ty = outs[1];
        st.canvas_tz = outs[2];
        st.canvas_dist = outs[3];
    }

    // Middle mouse: orbit (yaw/pitch only — never snap/translate look-target on click),
    // or Shift+MMB strafe (pan in camera plane).
    if (a.input.mousePressed(.middle)) {
        st.canvas_frame.cancel(); // user takes over
        if (a.input.shift) {
            st.canvas_strafing = true;
            st.canvas_orbiting = false;
        } else {
            st.canvas_orbiting = true;
            st.canvas_strafing = false;
            // Do NOT reassign canvas_t* here: MMB down must not center/translate.
            // Orbit rotates around the current look-target; numpad `.` frames selection.
        }
    }
    if (a.input.mouseReleased(.middle)) {
        st.canvas_orbiting = false;
        st.canvas_strafing = false;
    }
    // Orbit only while the mouse actually moves (dx/dy); pure click = no camera change.
    if (st.canvas_orbiting and a.input.mouseDown(.middle) and !a.input.shift) {
        const md = a.input.mouse_dx;
        const my = a.input.mouse_dy;
        if (md != 0 or my != 0) {
            const sens: f32 = 0.005;
            st.canvas_yaw -= md * sens;
            st.canvas_pitch -= my * sens;
            const lim: f32 = std.math.pi * 0.5 - 0.02;
            st.canvas_pitch = std.math.clamp(st.canvas_pitch, -lim, lim);
        }
    }

    // Pan — Space+LMB or Shift+MMB strafe
    const space_pan = a.input.keyDown(.space) and a.input.mouseDown(.left);
    if (space_pan) st.canvas_panning = true;
    if (!a.input.mouseDown(.left) or !a.input.keyDown(.space)) st.canvas_panning = false;
    // If shift held during MMB drag after starting orbit, treat as strafe.
    if (a.input.mouseDown(.middle) and a.input.shift) {
        st.canvas_strafing = true;
        st.canvas_orbiting = false;
    }

    var cam = buildCam(st);
    if (st.canvas_panning or (st.canvas_strafing and a.input.mouseDown(.middle))) {
        const k = st.canvas_dist * 0.0022;
        const r = Vec3.scale(cam.right, -a.input.mouse_dx * k);
        const uu = Vec3.scale(cam.up, a.input.mouse_dy * k);
        st.canvas_tx += r.x + uu.x;
        st.canvas_ty += r.y + uu.y;
        st.canvas_tz += r.z + uu.z;
        st.canvas_frame.cancel();
        cam = buildCam(st);
    }

    // Ctrl+A: toggle select all / none (A alone stays fly strafe-left).
    if (u.focus.isNone() and !u.palette_open and a.input.ctrl and a.input.keyPressed(.a)) {
        toggleSelectAll(st);
    }

    // --- Fly navigation (Unity / Blender Walk-Fly style) ---
    // WASD = forward / left / back / right along view
    // Q = down, E / Space = up  (world Y)
    // Shift = faster
    // Skip when a text field has focus so typing isn't stolen.
    // Skip fly when Ctrl is held so Ctrl+A doesn't also strafe.
    if (u.focus.isNone() and !u.palette_open and !a.input.ctrl) {
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

    {
        var di: usize = 0;
        while (di < state.max_entities) : (di += 1) {
            const e = &st.entities[di];
            if (!e.alive) continue;
            drawCube(e, st.isSelected(di), u.theme.accent);
        }
    }

    // --- Restore 2D for UI overlay text ---
    sgl.matrixModeProjection();
    sgl.loadIdentity();
    sgl.ortho(0, w, h, 0, -1, 1);
    sgl.matrixModeModelview();
    sgl.loadIdentity();
    if (a.pip_alpha.id != 0) sgl.loadPipeline(a.pip_alpha);

    // Labels track cube tops (not clickable).
    {
        var li: usize = 0;
        while (li < state.max_entities) : (li += 1) {
            const e = &st.entities[li];
            if (!e.alive) continue;
            const anchor = Vec3{ .x = e.pos_x, .y = e.pos_y + e.halfScaled() + 6, .z = e.pos_z };
            if (worldToScreenBasis(anchor, cam, w, h)) |s| {
                const sel = st.isSelected(li);
                const col = if (sel) u.theme.accent else u.theme.text;
                const name = e.nameSlice();
                const tw = u.font.measure(name, 1.5).w;
                u.drawText(s.x - tw * 0.5, s.y - 10, 1.5, col, name);
            }
        }
    }

    // Keep orientation gizmo left of the expanded inspector (gap handled in drawCompass).
    const insp_inset: f32 = if (st.selectionCount() > 0 and st.editor_inspector_open)
        st.editor_insp_w + 8
    else
        0;
    drawCompass(u, cam, w, insp_inset);

    // Editor panels (scene tree / inspector / console) on top of the viewport.
    editor.draw(a);

    // Delete selection (Del) when not typing in a field.
    if (u.focus.isNone() and !u.palette_open and a.input.keyPressed(.delete) and st.selectionCount() > 0) {
        const n = st.deleteSelected();
        var dbuf: [48]u8 = undefined;
        u.log(std.fmt.bufPrint(&dbuf, "deleted {d} entit(y/ies)", .{n}) catch "deleted");
        u.toast("Deleted selection", .err, 1.2);
    }

    // Select — LMB on mesh only, after UI so panel clicks don't pick through.
    // Ctrl/Shift = multi-select toggle; plain click replaces.
    if (a.input.mousePressed(.left) and !a.input.keyDown(.space) and !u.palette_open and !st.pointerOverEditorUi(a.input.mouse_x, a.input.mouse_y) and !u.any_hot) {
        const ray = screenToWorldRayBasis(a.input.mouse_x, a.input.mouse_y, w, h, cam);
        const hit = pickEntity(st, ray);
        const multi = a.input.ctrl or a.input.shift;
        if (hit < 0) {
            if (!multi) st.clearSelection();
        } else {
            const iu: usize = @intCast(hit);
            if (multi) {
                const on = !st.isSelected(iu);
                st.setSelected(iu, on);
                if (on) st.canvas_sel_primary = hit else if (st.canvas_sel_primary == hit) {
                    st.canvas_sel_primary = -1;
                    var bi: usize = 0;
                    while (bi < state.max_entities) : (bi += 1) {
                        if (st.isSelected(bi)) {
                            st.canvas_sel_primary = @intCast(bi);
                            break;
                        }
                    }
                }
            } else {
                st.clearSelection();
                st.setSelected(iu, true);
                st.canvas_sel_primary = hit;
            }
            u.log("select");
        }
    }

    // Compact HUD above console strip
    var buf: [96]u8 = undefined;
    const nsel = st.selectionCount();
    const msg = std.fmt.bufPrint(&buf, "canvas  sel {d}  entities {d}  ·  MMB orbit  WASD fly  Del delete  Ctrl+P", .{
        nsel,
        st.aliveCount(),
    }) catch "";
    const hud_y = if (st.editor_console_open) h - st.console_h - 28 else h - 18;
    u.drawText(16, hud_y, 1.4, u.theme.text_dim, msg);
}
