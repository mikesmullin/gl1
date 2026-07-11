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
const ui_mod = @import("ui/ui.zig");
const scenes = @import("scenes/scenes.zig");
const font_assets = @import("font_assets");

pub const Input = input_mod.Input;
pub const Font = font_mod.Font;
pub const Ui = ui_mod.Ui;

pub const App = struct {
    allocator: std.mem.Allocator = undefined,
    input: Input = .{},
    font: Font = .{},
    ui: Ui = .{},
    scene: scenes.SceneKind = .storybook,
    scene_state: scenes.State = .{},
    width: f32 = 0,
    height: f32 = 0,
    time: f64 = 0,
    dt: f32 = 0,
    last_time: f64 = 0,
    pip_alpha: sgl.Pipeline = .{},
    font_ok: bool = false,
};

var g: App = .{};

pub fn global() *App {
    return &g;
}

pub fn run(allocator: std.mem.Allocator, scene: scenes.SceneKind) void {
    g.allocator = allocator;
    g.scene = scene;
    g.scene_state.init();
    g.ui.init(allocator);

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

    // Alpha-blended pipeline for text / translucent rects.
    var pip_desc: sg.PipelineDesc = .{};
    pip_desc.colors[0].blend = .{
        .enabled = true,
        .src_factor_rgb = .SRC_ALPHA,
        .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
        .src_factor_alpha = .ONE,
        .dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
    };
    g.pip_alpha = sgl.makePipeline(pip_desc);

    loadFont();
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
}

export fn frame() void {
    const now = sapp.frameDuration(); // seconds since last frame actually
    // Prefer cumulative time from frame count * duration.
    g.dt = @floatCast(sapp.frameDuration());
    if (g.dt <= 0 or g.dt > 0.1) g.dt = 1.0 / 60.0;
    g.time += g.dt;
    _ = now;

    g.width = sapp.widthf();
    g.height = sapp.heightf();

    const bg = g.ui.theme.bg;
    var pass_action: sg.PassAction = .{};
    pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = bg[0], .g = bg[1], .b = bg[2], .a = 1 },
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

    g.ui.beginFrame(&g.input, &g.font, g.width, g.height, g.dt, g.time);
    trySceneHotkeys();
    scenes.frame(&g);
    g.ui.endFrame();
    g.ui.flushDraw();

    sgl.draw();
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

    // Esc: palette/modal may have consumed it; else clear focus; else quit.
    if (g.input.keyPressed(.escape) and !g.ui.consumed_escape) {
        if (g.ui.palette_open) {
            g.ui.palette_open = false;
        } else if (!g.ui.focus.isNone()) {
            g.ui.focus = .{};
        } else {
            sapp.quit();
        }
    }

    g.input.beginFrame();
}

export fn cleanup() void {
    g.font.deinit();
    g.ui.deinit();
    sgl.shutdown();
    sg.shutdown();
}
