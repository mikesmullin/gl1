//! App shell: sokol_app + sokol_gfx + sokol_gl + scene runner.

const std = @import("std");
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const sgl = sokol.gl;

const input_mod = @import("input.zig");
const font_mod = @import("font.zig");
const icons_mod = @import("icons.zig");
const ui_mod = @import("ui/ui.zig");
const scenes = @import("scenes/scenes.zig");
const transition_mod = @import("transition.zig");
const font_assets = @import("font_assets");
const icon_assets = @import("icon_assets");
const demo_assets = @import("demo_assets");
const tex_mod = @import("ui/tex.zig");

pub const Input = input_mod.Input;
pub const Font = font_mod.Font;
pub const Icons = icons_mod.Icons;
pub const Ui = ui_mod.Ui;
pub const Transition = transition_mod.Transition;

pub const App = struct {
    allocator: std.mem.Allocator = undefined,
    io: std.Io = undefined,
    input: Input = .{},
    font: Font = .{},
    icons: Icons = .{},
    ui: Ui = .{},
    scene: scenes.SceneKind = .storybook,
    /// Scene to apply when diamond wipe completes.
    scene_pending: ?scenes.SceneKind = null,
    scene_state: scenes.State = .{},
    transition: Transition = .{},
    width: f32 = 0,
    height: f32 = 0,
    time: f64 = 0,
    dt: f32 = 0,
    last_time: f64 = 0,
    pip_alpha: sgl.Pipeline = .{},
    /// Depth-tested pipeline for 3D canvas cubes.
    pip_3d: sgl.Pipeline = .{},
    font_ok: bool = false,
    icons_ok: bool = false,
    /// Ring buffer of recent frame times (ms) for the HUD histogram.
    ft_ms: [60]f32 = @splat(0),
    ft_head: usize = 0,
    ft_count: usize = 0,
    /// Storybook demo image (fire-dragon.png).
    demo_tex: tex_mod.Tex = .{},
    /// When > 0, quit after this many seconds (screenshot automation).
    auto_quit_s: f32 = 0,

    pub const FtHist: usize = 60;

    pub fn pushFrameTime(self: *App, dt_s: f32) void {
        const ms = dt_s * 1000.0;
        self.ft_ms[self.ft_head] = ms;
        self.ft_head = (self.ft_head + 1) % FtHist;
        if (self.ft_count < FtHist) self.ft_count += 1;
    }

    /// Oldest → newest samples into `out` (returns slice length).
    pub fn frameTimeSamples(self: *const App, out: []f32) []const f32 {
        const n = @min(out.len, self.ft_count);
        if (n == 0) return out[0..0];
        const start = (self.ft_head + FtHist - n) % FtHist;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            out[i] = self.ft_ms[(start + i) % FtHist];
        }
        return out[0..n];
    }

    /// Per-scene wipe color (destination scene).
    pub fn sceneWipeColor(kind: scenes.SceneKind) [4]f32 {
        return switch (kind) {
            .canvas => transition_mod.color_blue,
            .storybook => transition_mod.color_charcoal,
            .text => transition_mod.color_green,
            .triangle => transition_mod.color_amber,
            .panels => transition_mod.color_pink,
        };
    }

    /// Request a scene change with diamond wipe (~1s). No-ops if already transitioning.
    pub fn requestScene(self: *App, next: scenes.SceneKind) void {
        if (next == self.scene and self.scene_pending == null) return;
        if (self.transition.busy()) return;
        self.scene_pending = next;
        self.transition.startWipe(sceneWipeColor(next));
    }
};

var g: App = .{};

pub fn global() *App {
    return &g;
}

pub fn run(allocator: std.mem.Allocator, scene: scenes.SceneKind, io: std.Io, opts: struct {
    story_tab: ?[]const u8 = null,
    auto_quit_s: f32 = 0,
}) void {
    g.allocator = allocator;
    g.io = io;
    g.scene = scene;
    g.scene_state.init();
    g.ui.init(allocator);
    g.auto_quit_s = opts.auto_quit_s;
    if (opts.story_tab) |tab_name| {
        if (@import("scenes/storybook.zig").tabIndex(tab_name)) |idx| {
            g.scene_state.selected = idx;
        } else {
            std.log.warn("unknown storybook tab '{s}'", .{tab_name});
        }
    }

    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .event_cb = event,
        .cleanup_cb = cleanup,
        .width = 1100,
        .height = 720,
        .sample_count = 4,
        .window_title = "gl1",
        .logger = .{ .func = slog.func },
        .icon = .{ .sokol_default = true },
        .enable_clipboard = true,
        .clipboard_size = 16 * 1024,
    });
}

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });
    sgl.setup(.{
        .logger = .{ .func = slog.func },
        .max_vertices = 256 * 1024,
        .max_commands = 64 * 1024,
    });

    // Alpha-blended pipeline for text / translucent rects (2D UI).
    var pip_desc: sg.PipelineDesc = .{};
    pip_desc.colors[0].blend = .{
        .enabled = true,
        .src_factor_rgb = .SRC_ALPHA,
        .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
        .src_factor_alpha = .ONE,
        .dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
    };
    g.pip_alpha = sgl.makePipeline(pip_desc);

    // 3D pipeline: depth test/write for solid cubes in the canvas scene.
    var pip3: sg.PipelineDesc = .{};
    pip3.depth = .{
        .compare = .LESS_EQUAL,
        .write_enabled = true,
    };
    pip3.colors[0].blend = .{
        .enabled = true,
        .src_factor_rgb = .SRC_ALPHA,
        .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
        .src_factor_alpha = .ONE,
        .dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
    };
    g.pip_3d = sgl.makePipeline(pip3);

    loadFont();
    loadIcons();
    loadDemoTex();
    // GPU diamond wipe (after sg + sgl are ready).
    g.transition.init();
    g.last_time = 0;
}

fn loadFont() void {
    // Single source of truth: assets/fonts/glyphs-outline.bmp
    const bytes = font_assets.glyphs_outline_bmp;
    g.font.loadFromBytes(g.allocator, bytes) catch |err| {
        std.log.err("failed to load embedded font atlas: {s}", .{@errorName(err)});
        return;
    };
    g.font_ok = true;
    std.log.info("loaded font atlas ({d} bytes)", .{bytes.len});
}

fn loadIcons() void {
    // Runtime PNG under assets/icons/ (cwd = zig-out/bin when using `zig build run`).
    // Edit icons.png / icons.yaml and restart — no rebuild needed.
    g.icons.load(g.allocator, g.io, icon_assets.icons_png, icon_assets.icons_yaml) catch |err| {
        std.log.err("failed to load icon atlas: {s}", .{@errorName(err)});
        return;
    };
    g.icons_ok = true;
}

fn loadDemoTex() void {
    g.demo_tex.loadFromPng(g.allocator, demo_assets.fire_dragon_png) catch |err| {
        std.log.err("failed to load demo texture: {s}", .{@errorName(err)});
        return;
    };
    std.log.info("loaded demo texture fire-dragon.png", .{});
}

fn trySceneHotkeys() void {
    // Called once per frame so keyPressed edges stay coherent.
    if (!g.input.ctrl) return;

    // Ctrl+P → command palette (scene switching is via palette filters).
    if (g.input.keyPressed(.p)) {
        g.ui.palette_open = !g.ui.palette_open;
        // Swallow typed 'p' / any buffered chars from this chord.
        g.input.text_len = 0;
        if (g.ui.palette_open) {
            g.ui.palette_query_len = 0;
            g.ui.palette_sel = 0;
            g.ui.palette_scroll = 0;
            g.ui.focus = .{};
            g.ui.menu_open = .{};
            g.ui.closeContextMenu();
            g.ui.log("palette opened");
        } else {
            g.ui.log("palette closed");
        }
    }
}

export fn event(ev: [*c]const sapp.Event) void {
    g.input.handleEvent(ev);
    // Clipboard paste events (requires enable_clipboard).
    if (ev.*.type == .CLIPBOARD_PASTED) {
        g.input.pushPaste(sapp.getClipboardString());
    }
    // Soft pointer: release when the window loses focus so OS cursor returns.
    if (ev.*.type == .FOCUSED) {
        // re-entering: leave soft_pointer as-is (user may still be mid-session)
    } else if (ev.*.type == .UNFOCUSED) {
        g.ui.releaseSoftPointer();
    }
}

export fn frame() void {
    const now = sapp.frameDuration(); // seconds since last frame actually
    // Prefer cumulative time from frame count * duration.
    g.dt = @floatCast(sapp.frameDuration());
    if (g.dt <= 0 or g.dt > 0.1) g.dt = 1.0 / 60.0;
    g.time += g.dt;
    g.pushFrameTime(g.dt);
    _ = now;
    if (g.auto_quit_s > 0 and g.time >= g.auto_quit_s) {
        sapp.quit();
    }

    g.width = sapp.widthf();
    g.height = sapp.heightf();

    const bg = g.ui.theme.bg;
    var pass_action: sg.PassAction = .{};
    pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = bg[0], .g = bg[1], .b = bg[2], .a = 1 },
    };
    // Depth clear for canvas 3D cubes (harmless for pure 2D scenes).
    pass_action.depth = .{
        .load_action = .CLEAR,
        .clear_value = 1.0,
    };

    sg.beginPass(.{ .action = pass_action, .swapchain = sglue.swapchain() });

    sgl.defaults();
    sgl.matrixModeProjection();
    sgl.ortho(0, g.width, g.height, 0, -1, 1); // top-left origin
    sgl.matrixModeModelview();
    sgl.loadIdentity();
    if (g.pip_alpha.id != 0) sgl.loadPipeline(g.pip_alpha);

    g.input.now = g.time;
    g.input.tickKeyRepeat();
    g.input.refreshModifiers();

    // Scene transition tick (diamond wipe → swap → reveal).
    if (g.transition.tick(g.dt) == .swap) {
        if (g.scene_pending) |next| {
            g.scene = next;
            g.scene_pending = null;
        }
    }

    g.ui.beginFrame(&g.input, &g.font, if (g.icons_ok) &g.icons else null, g.width, g.height, g.dt, g.time);
    trySceneHotkeys();
    scenes.frame(&g);
    g.ui.handleTabFocus();
    g.ui.endFrame();
    g.ui.flushDraw();

    // CPU diamond uses sgl quads → must enqueue before sgl.draw.
    if (g.transition.busy() and !g.transition.ok) {
        g.transition.draw(g.width, g.height);
    }

    sgl.draw();

    // GPU diamond is a raw sg fullscreen pass → after sgl so it covers UI.
    if (g.transition.busy() and g.transition.ok) {
        g.transition.draw(g.width, g.height);
    }

    sg.endPass();
    sg.commit();

    // Push any Ctrl+C/X copy requests to the system clipboard.
    if (g.input.takeCopyRequest()) |s| {
        var zbuf: [1025]u8 = undefined;
        const n = @min(s.len, zbuf.len - 1);
        @memcpy(zbuf[0..n], s[0..n]);
        zbuf[n] = 0;
        sapp.setClipboardString(zbuf[0..n :0]);
    }

    // Esc layers: modal/palette may have consumed it; else palette close;
    // else clear text focus; else release soft pointer; else quit.
    if (g.input.keyPressed(.escape) and !g.ui.consumed_escape) {
        if (g.ui.palette_open) {
            g.ui.palette_open = false;
        } else if (!g.ui.focus.isNone()) {
            g.ui.focus = .{};
        } else if (g.ui.soft_pointer) {
            g.ui.releaseSoftPointer();
        } else {
            sapp.quit();
        }
    }

    g.input.beginFrame();
}

export fn cleanup() void {
    g.transition.deinit();
    g.demo_tex.deinit();
    g.icons.deinit();
    g.font.deinit();
    g.ui.deinit();
    sgl.shutdown();
    sg.shutdown();
}
