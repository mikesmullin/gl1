//! Embedded mini-browser panel (iframe-like) — HTML/CSS subset + media.
const std = @import("std");
const dom = @import("dom.zig");
const html = @import("html.zig");
const css = @import("css.zig");
const layout_mod = @import("layout.zig");
const wav_mod = @import("wav.zig");
const tex_mod = @import("../tex.zig");
const open_url = @import("../open_url.zig");
const types = @import("../types.zig");
const demo_assets = @import("demo_assets");

pub const WavPlayer = wav_mod.Player;
pub const setupAudio = wav_mod.setupAudio;
pub const shutdownAudio = wav_mod.shutdownAudio;

pub const Document = dom.Document;

const chrome_h: f32 = 52;
const title_h: f32 = 22;
const url_h: f32 = 26;

pub const BrowserDoc = struct {
    doc: Document = undefined,
    url: [256]u8 = undefined,
    url_len: usize = 0,
    title_buf: [128]u8 = undefined,
    title_len: usize = 0,
    scroll_y: f32 = 0,
    inited: bool = false,
    img_tex: ?tex_mod.Tex = null,
    /// Pre-extracted video frames (phase-1 strip; up to 64 @ ~12 fps).
    video_frames: [64]tex_mod.Tex = @splat(.{}),
    video_frame_count: usize = 0,
    video_frame_i: usize = 0,
    video_playing: bool = false,
    video_t: f32 = 0,
    video_fps: f32 = 12,
    audio: WavPlayer = .{},
    has_audio_tag: bool = false,
    has_video_tag: bool = false,
    allocator: std.mem.Allocator = undefined,

    pub fn init(self: *BrowserDoc, allocator: std.mem.Allocator) void {
        self.* = .{
            .doc = Document.init(allocator),
            .allocator = allocator,
            .inited = true,
        };
    }

    pub fn deinit(self: *BrowserDoc) void {
        if (!self.inited) return;
        self.audio.deinit();
        if (self.img_tex) |*t| t.deinit();
        for (&self.video_frames) |*t| t.deinit();
        self.doc.deinit();
        self.inited = false;
    }

    pub fn setUrl(self: *BrowserDoc, url: []const u8) void {
        const n = @min(url.len, self.url.len);
        @memcpy(self.url[0..n], url[0..n]);
        self.url_len = n;
    }

    pub fn urlSlice(self: *const BrowserDoc) []const u8 {
        return self.url[0..self.url_len];
    }

    pub fn titleSlice(self: *const BrowserDoc) []const u8 {
        if (self.title_len > 0) return self.title_buf[0..self.title_len];
        if (self.doc.title.len > 0) return self.doc.title;
        return "about:blank";
    }

    pub fn loadHtml(self: *BrowserDoc, source: []const u8, url: []const u8) !void {
        self.setUrl(url);
        try html.parse(&self.doc, source);
        css.cascade(&self.doc);
        const t = self.doc.title;
        const n = @min(t.len, self.title_buf.len);
        if (n > 0) {
            @memcpy(self.title_buf[0..n], t[0..n]);
            self.title_len = n;
        }
        self.scroll_y = 0;
        self.has_audio_tag = containsTag(self.doc.root, "audio");
        self.has_video_tag = containsTag(self.doc.root, "video");
    }

    pub fn ensureDragonImage(self: *BrowserDoc) void {
        if (self.img_tex != null) return;
        var t: tex_mod.Tex = .{};
        t.loadFromPng(self.allocator, demo_assets.fire_dragon_png) catch return;
        self.img_tex = t;
        setImgIntrinsic(self.doc.root, @floatFromInt(t.w), @floatFromInt(t.h));
    }

    /// Load a PNG from disk (cwd-relative) into this doc's image texture.
    pub fn loadImagePng(self: *BrowserDoc, io: std.Io, path: []const u8, display_w: f32, display_h: f32) void {
        if (self.img_tex != null) return;
        const data = std.Io.Dir.cwd().readFileAlloc(io, path, self.allocator, .limited(8 * 1024 * 1024)) catch |err| {
            std.log.warn("browser image load {s}: {s}", .{ path, @errorName(err) });
            return;
        };
        defer self.allocator.free(data);
        var t: tex_mod.Tex = .{};
        t.loadFromPng(self.allocator, data) catch return;
        self.img_tex = t;
        const iw: f32 = if (display_w > 0) display_w else @floatFromInt(t.w);
        const ih: f32 = if (display_h > 0) display_h else @floatFromInt(t.h);
        setImgIntrinsic(self.doc.root, iw, ih);
    }

    /// Poster / paused frame: reuse robot-daddy.png (only still image under media/).
    pub fn ensureVideoPoster(self: *BrowserDoc, io: std.Io) void {
        if (self.img_tex != null) return;
        self.loadImagePng(io, "assets/demo/media/robot-daddy.png", 320, 180);
        setVideoIntrinsic(self.doc.root, 320, 180);
    }

    /// Load pre-extracted frame strip for phase-1 video (no in-process ffmpeg).
    /// Frames live under `assets/demo/media/vframes/` (gitignored). If missing and
    /// `ffmpeg` is on PATH, extract once from `robot-breakdance.mp4`.
    pub fn loadVideoFrames(self: *BrowserDoc, io: std.Io) void {
        if (self.video_frame_count > 0) return;
        if (!tryLoadVideoFrames(self, io)) {
            extractVframes(io) catch |err| {
                std.log.warn("browser: vframes extract failed ({s}); video shows poster only", .{@errorName(err)});
            };
            _ = tryLoadVideoFrames(self, io);
        }
        if (self.video_frame_count > 0) {
            setVideoIntrinsic(self.doc.root, 320, 180);
        }
    }

    fn tryLoadVideoFrames(self: *BrowserDoc, io: std.Io) bool {
        const dir = std.Io.Dir.cwd();
        var i: usize = 0;
        var loaded: usize = 0;
        while (i < self.video_frames.len) : (i += 1) {
            var path_buf: [96]u8 = undefined;
            const path = std.fmt.bufPrint(&path_buf, "assets/demo/media/vframes/f{d:0>3}.png", .{i + 1}) catch break;
            const data = dir.readFileAlloc(io, path, self.allocator, .limited(2 * 1024 * 1024)) catch break;
            defer self.allocator.free(data);
            self.video_frames[i].loadFromPng(self.allocator, data) catch break;
            loaded += 1;
        }
        self.video_frame_count = loaded;
        return loaded > 0;
    }

    pub fn loadAudioFile(self: *BrowserDoc, io: std.Io, path: []const u8) void {
        self.audio.loadPath(self.allocator, io, path) catch |err| {
            std.log.warn("browser audio load failed: {s}", .{@errorName(err)});
        };
    }

    pub fn tick(self: *BrowserDoc, dt: f32) void {
        self.audio.tick(dt);
        self.audio.pump();
        if (self.video_playing and self.video_frame_count > 0) {
            self.video_t += dt;
            const step = 1.0 / self.video_fps;
            while (self.video_t >= step) {
                self.video_t -= step;
                self.video_frame_i += 1;
                if (self.video_frame_i >= self.video_frame_count) {
                    self.video_frame_i = 0;
                }
            }
        }
    }
};

/// One-shot: ffmpeg → assets/demo/media/vframes/f%03d.png (12 fps, 320px wide).
fn extractVframes(io: std.Io) !void {
    const mp4 = "assets/demo/media/robot-breakdance.mp4";
    const out_dir = "assets/demo/media/vframes";
    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(io, out_dir) catch {};
    cwd.access(io, mp4, .{}) catch return error.MissingMp4;

    var child = try std.process.spawn(io, .{
        .argv = &.{
            "ffmpeg", "-y",
            "-i", mp4,
            "-t", "12",
            "-vf", "fps=12,scale=320:-1",
            "assets/demo/media/vframes/f%03d.png",
        },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    const term = try child.wait(io);
    if (!term.success()) return error.FfmpegFailed;
}

/// Queue a texture through the UI draw list (correct clip / z / position).
fn queueImage(ui: anytype, tex: *const tex_mod.Tex, x: f32, y: f32, w: f32, h: f32, fit: u8) void {
    if (!tex.ok) return;
    ui.cmds.image(x, y, w, h, tex, fit);
}

fn containsTag(n: *dom.Node, tag: []const u8) bool {
    if (n.kind == .element and std.mem.eql(u8, n.tag, tag)) return true;
    for (n.children.items) |c| {
        if (containsTag(c, tag)) return true;
    }
    return false;
}

fn setImgIntrinsic(n: *dom.Node, w: f32, h: f32) void {
    if (n.kind == .element and std.mem.eql(u8, n.tag, "img")) {
        n.intrinsic_w = w;
        n.intrinsic_h = h;
    }
    for (n.children.items) |c| setImgIntrinsic(c, w, h);
}

fn setVideoIntrinsic(n: *dom.Node, w: f32, h: f32) void {
    if (n.kind == .element and std.mem.eql(u8, n.tag, "video")) {
        n.intrinsic_w = w;
        n.intrinsic_h = h;
    }
    for (n.children.items) |c| setVideoIntrinsic(c, w, h);
}

/// Draw browser document into rect `r`.
/// `chrome=false` (default for storybook) shows only the document body.
pub fn frameAt(ui: anytype, bd: *BrowserDoc, id: []const u8, r: types.Rect, chrome: bool) void {
    _ = id;
    bd.tick(ui.dt);

    const content_y = r.y + if (chrome) chrome_h else 0;
    const content_h = r.h - if (chrome) chrome_h else 0;
    const content_r = types.Rect{ .x = r.x, .y = content_y, .w = r.w, .h = content_h };

    // Subtle outer edge so iframes separate on the storyboard.
    ui.drawRectBorder(r, .{ 0.06, 0.07, 0.09, 1 }, ui.theme.panel_border, 1);

    if (chrome) {
        ui.drawRect(.{ .x = r.x + 1, .y = r.y + 1, .w = r.w - 2, .h = title_h }, .{ 0.22, 0.23, 0.26, 1 });
        ui.drawRect(.{ .x = r.x + 8, .y = r.y + 7, .w = 8, .h = 8 }, .{ 0.9, 0.35, 0.35, 1 });
        ui.drawRect(.{ .x = r.x + 20, .y = r.y + 7, .w = 8, .h = 8 }, .{ 0.9, 0.75, 0.3, 1 });
        ui.drawRect(.{ .x = r.x + 32, .y = r.y + 7, .w = 8, .h = 8 }, .{ 0.35, 0.8, 0.4, 1 });
        ui.drawText(r.x + 48, r.y + 5, 1.4, ui.theme.text, bd.titleSlice());

        ui.drawRect(.{ .x = r.x + 1, .y = r.y + 1 + title_h, .w = r.w - 2, .h = url_h }, .{ 0.14, 0.15, 0.17, 1 });
        ui.drawRectBorder(.{ .x = r.x + 6, .y = r.y + title_h + 4, .w = r.w - 12, .h = url_h - 6 }, .{ 0.1, 0.11, 0.12, 1 }, .{ 0.3, 0.32, 0.36, 1 }, 1);
        ui.drawText(r.x + 12, r.y + title_h + 7, 1.35, .{ 0.7, 0.85, 0.7, 1 }, bd.urlSlice());
    }

    // Default document canvas: black (CSS body background may paint over).
    ui.drawRect(content_r, .{ 0.06, 0.07, 0.09, 1 });

    const layout_w = content_r.w - 4;
    const mfn = struct {
        var fptr: ?*const @TypeOf(ui.font.*) = null;
        fn measure(text: []const u8, font_size: f32) layout_mod.Size {
            const f = fptr orelse return .{ .w = @as(f32, @floatFromInt(text.len)) * font_size * 0.5, .h = font_size * 1.2 };
            const scale = font_size / 8.0;
            const m = f.measure(text, scale);
            return .{ .w = m.w, .h = @max(m.h, font_size * 1.15) };
        }
    };
    mfn.fptr = ui.font;

    if (bd.inited) {
        layout_mod.layout(&bd.doc, layout_w, mfn.measure);
    }

    const max_scroll = @max(0, bd.doc.content_h - content_r.h + 8);
    // While hovered, this iframe owns the wheel (blocks outer storybook panel).
    if (content_r.contains(ui.input.mouse_x, ui.input.mouse_y)) {
        const wheel = ui.wheelY();
        if (wheel != 0) {
            bd.scroll_y -= wheel * 32;
            bd.scroll_y = std.math.clamp(bd.scroll_y, 0, max_scroll);
            ui.eatScroll();
        }
    }
    bd.scroll_y = std.math.clamp(bd.scroll_y, 0, max_scroll);

    ui.cmds.push(.{ .scissor_push = .{ .x = content_r.x, .y = content_r.y, .w = content_r.w, .h = content_r.h } });
    paintNode(ui, bd, bd.doc.root, content_r.x + 2, content_r.y + 2 - bd.scroll_y);
    ui.cmds.push(.{ .scissor_pop = {} });

    if (max_scroll > 1) {
        const track_h = content_r.h - 4;
        const thumb_h = @max(20, track_h * (content_r.h / (bd.doc.content_h + 1)));
        const thumb_y = content_r.y + 2 + (track_h - thumb_h) * (bd.scroll_y / max_scroll);
        ui.drawRect(.{ .x = content_r.x + content_r.w - 6, .y = thumb_y, .w = 4, .h = thumb_h }, .{ 0.4, 0.45, 0.5, 0.7 });
    }

    // Link hit-test: hand cursor while hovering (same as ui.link); open on click.
    const ox = content_r.x + 2;
    const oy = content_r.y + 2 - bd.scroll_y;
    const mx = ui.input.mouse_x;
    const my = ui.input.mouse_y;
    if (content_r.contains(mx, my)) {
        if (hitLink(bd.doc.root, ox, oy, mx, my)) |href| {
            ui.setSoftCursor(.cursor_hand_open);
            if (ui.input.mousePressed(.left)) {
                activateHref(bd.urlSlice(), href);
                ui.log("browser: link");
            }
        }
    }
}

/// Resolve `href` against document URL and open http(s) in the system browser.
fn activateHref(doc_url: []const u8, href: []const u8) void {
    if (href.len == 0) return;
    // Pure in-page fragment — no external open.
    if (href[0] == '#') return;

    var buf: [768]u8 = undefined;
    const absolute = resolveHref(&buf, doc_url, href) orelse return;
    if (std.mem.startsWith(u8, absolute, "http://") or std.mem.startsWith(u8, absolute, "https://")) {
        open_url.openUrl(absolute);
    }
}

/// Resolve a href to an absolute URL string written into `buf`, or null if unresolvable.
fn resolveHref(buf: []u8, base: []const u8, href: []const u8) ?[]const u8 {
    // Already absolute
    if (std.mem.startsWith(u8, href, "http://") or std.mem.startsWith(u8, href, "https://")) {
        if (href.len > buf.len) return null;
        @memcpy(buf[0..href.len], href);
        return buf[0..href.len];
    }
    // Protocol-relative: //host/path
    if (std.mem.startsWith(u8, href, "//")) {
        return std.fmt.bufPrint(buf, "https:{s}", .{href}) catch null;
    }

    // Need an http(s) base document URL for relative resolution.
    const base_http = if (std.mem.startsWith(u8, base, "http://") or std.mem.startsWith(u8, base, "https://"))
        base
    else
        return null;

    // scheme://host
    const scheme_end = std.mem.indexOf(u8, base_http, "://") orelse return null;
    const after_scheme = base_http[scheme_end + 3 ..];
    const host_end_rel = std.mem.indexOfAny(u8, after_scheme, "/?#") orelse after_scheme.len;
    const origin = base_http[0 .. scheme_end + 3 + host_end_rel]; // https://ladybird.org

    // Root-relative: /path
    if (href[0] == '/') {
        return std.fmt.bufPrint(buf, "{s}{s}", .{ origin, href }) catch null;
    }

    // Path-relative: join with base directory
    // Drop query/fragment from base for path join
    const base_no_frag = if (std.mem.indexOfAny(u8, base_http, "?#")) |i| base_http[0..i] else base_http;
    const last_slash = std.mem.lastIndexOfScalar(u8, base_no_frag, '/') orelse return null;
    // If slash is inside "://", use origin + /
    const path_slash = if (last_slash < scheme_end + 3) scheme_end + 3 + host_end_rel else last_slash;
    const dir = base_http[0 .. path_slash + 1];
    return std.fmt.bufPrint(buf, "{s}{s}", .{ dir, href }) catch null;
}

fn paintNode(ui: anytype, bd: *BrowserDoc, n: *dom.Node, ox: f32, oy: f32) void {
    if (n.kind == .document) {
        for (n.children.items) |c| paintNode(ui, bd, c, ox, oy);
        return;
    }
    if (n.kind == .element and (std.mem.eql(u8, n.tag, "html") or std.mem.eql(u8, n.tag, "body"))) {
        if (n.style.bg) |bg| {
            // body background already covered by content rect; still paint if dark
            if (bg[0] + bg[1] + bg[2] < 2.5) {
                ui.drawRect(.{ .x = ox + n.box.x, .y = oy + n.box.y, .w = n.box.w, .h = n.box.h }, bg);
            }
        }
        for (n.children.items) |c| paintNode(ui, bd, c, ox, oy);
        return;
    }
    if (n.style.display == .none) return;

    if (n.kind == .text) {
        const scale = n.style.font_size / 8.0;
        ui.drawText(ox + n.box.x, oy + n.box.y, scale, n.style.color, n.text);
        return;
    }

    const x = ox + n.box.x;
    const y = oy + n.box.y;
    const w = n.box.w;
    const h = n.box.h;

    if (n.style.bg) |bg| {
        if (bg[3] > 0.01) ui.drawRect(.{ .x = x, .y = y, .w = w, .h = h }, bg);
    }
    if (n.style.border_w > 0 and w > 0 and h > 0) {
        ui.drawRectOutline(.{ .x = x, .y = y, .w = w, .h = h }, n.style.border_color, @max(1, n.style.border_w));
    }

    if (std.mem.eql(u8, n.tag, "img")) {
        const pad = n.style.padding[0];
        const bw = n.style.border_w;
        const ix = x + pad + bw;
        const iy = y + pad + bw;
        const iw = @max(1, w - 2 * (pad + bw));
        const ih = @max(1, h - 2 * (pad + bw));
        if (bd.img_tex) |*t| {
            queueImage(ui, t, ix, iy, iw, ih, 0); // fit
        } else {
            ui.drawRect(.{ .x = ix, .y = iy, .w = iw, .h = ih }, .{ 0.2, 0.22, 0.26, 1 });
            ui.drawText(ix + 8, iy + ih * 0.5 - 6, 1.3, .{ 0.7, 0.72, 0.78, 1 }, "[img missing]");
        }
        return;
    } else if (std.mem.eql(u8, n.tag, "audio")) {
        paintAudioControl(ui, bd, x, y, w, h);
        return;
    } else if (std.mem.eql(u8, n.tag, "video")) {
        paintVideoControl(ui, bd, x, y, w, h);
        return;
    } else if (std.mem.eql(u8, n.tag, "li")) {
        // Marker sits in the parent list's padding-left gutter.
        if (n.list_ordered and n.list_index > 0) {
            var num_buf: [12]u8 = undefined;
            const label = std.fmt.bufPrint(&num_buf, "{d}.", .{n.list_index}) catch "?.";
            const scale = n.style.font_size / 8.0;
            const m = ui.font.measure(label, scale);
            ui.drawText(x - 4 - m.w, y, scale, n.style.color, label);
        } else {
            ui.drawRect(.{
                .x = x - 14,
                .y = y + n.style.font_size * 0.35,
                .w = 5,
                .h = 5,
            }, n.style.color);
        }
    } else if (std.mem.eql(u8, n.tag, "a")) {
        const scale = n.style.font_size / 8.0;
        const text = firstText(n);
        var mw: f32 = w;
        var mh: f32 = h;
        if (text.len > 0) {
            const m = ui.font.measure(text, scale);
            mw = m.w;
            mh = m.h;
        }
        // Prefer text metrics for hit/hover when layout box is thin.
        const hit_w = @max(w, mw);
        const hit_h = @max(h, mh);
        const hot = ui.input.mouse_x >= x and ui.input.mouse_y >= y and
            ui.input.mouse_x < x + hit_w and ui.input.mouse_y < y + hit_h;
        // Match link component: hot → accent + hand cursor.
        const col = if (hot) ui.theme.accent_hot else n.style.color;
        if (hot) ui.setSoftCursor(.cursor_hand_open);
        if (text.len > 0) {
            ui.drawText(x, y, scale, col, text);
            ui.drawRect(.{ .x = x, .y = y + mh - 1, .w = mw, .h = 1 }, col);
        }
        // Keep box in sync for hitLink (used for click + outer hover).
        n.box.w = @max(n.box.w, hit_w);
        n.box.h = @max(n.box.h, hit_h);
        for (n.children.items) |c| {
            if (c.kind != .text) paintNode(ui, bd, c, ox, oy);
        }
        return;
    }

    for (n.children.items) |c| paintNode(ui, bd, c, ox, oy);
}

fn firstText(n: *dom.Node) []const u8 {
    for (n.children.items) |c| {
        if (c.kind == .text) return c.text;
    }
    return "";
}

fn paintAudioControl(ui: anytype, bd: *BrowserDoc, x: f32, y: f32, w: f32, h: f32) void {
    ui.drawRect(.{ .x = x, .y = y, .w = w, .h = h }, .{ 0.15, 0.16, 0.18, 1 });
    const playing = bd.audio.playing;
    const label = if (playing) "||" else ">";
    ui.drawRectBorder(.{ .x = x + 6, .y = y + 6, .w = 28, .h = h - 12 }, .{ 0.25, 0.45, 0.85, 1 }, .{ 0.4, 0.6, 1, 1 }, 1);
    ui.drawText(x + 14, y + h * 0.5 - 6, 1.5, .{ 1, 1, 1, 1 }, label);

    const bar_x = x + 42;
    const bar_w = @max(20, w - 50);
    const bar_y = y + h * 0.5 - 3;
    ui.drawRect(.{ .x = bar_x, .y = bar_y, .w = bar_w, .h = 6 }, .{ 0.3, 0.32, 0.35, 1 });
    const p = bd.audio.progress();
    ui.drawRect(.{ .x = bar_x, .y = bar_y, .w = bar_w * p, .h = 6 }, .{ 0.3, 0.75, 0.5, 1 });

    if (ui.input.mousePressed(.left)) {
        const mx = ui.input.mouse_x;
        const my = ui.input.mouse_y;
        if (mx >= x + 6 and mx <= x + 34 and my >= y + 6 and my <= y + h - 6) {
            bd.audio.toggle();
        } else if (mx >= bar_x and mx <= bar_x + bar_w and my >= bar_y - 4 and my <= bar_y + 10) {
            if (bd.audio.loaded and bd.audio.wav.samples.len > 0) {
                const t = std.math.clamp((mx - bar_x) / bar_w, 0, 1);
                bd.audio.seekFraction(t);
            }
        }
    }
}

fn paintVideoControl(ui: anytype, bd: *BrowserDoc, x: f32, y: f32, w: f32, h: f32) void {
    const ctrl_h: f32 = 28;
    const vid_h = @max(40, h - ctrl_h);
    // Plate under frames (so letterboxing looks intentional).
    ui.drawRect(.{ .x = x, .y = y, .w = w, .h = vid_h }, .{ 0.05, 0.05, 0.06, 1 });
    if (bd.video_frame_count > 0) {
        const fi = if (bd.video_playing)
            @min(bd.video_frame_i, bd.video_frame_count - 1)
        else
            @as(usize, 0);
        queueImage(ui, &bd.video_frames[fi], x, y, w, vid_h, 0); // fit
    } else if (bd.img_tex) |*t| {
        queueImage(ui, t, x, y, w, vid_h, 0);
    } else {
        ui.drawText(x + 12, y + vid_h * 0.5, 1.4, .{ 0.7, 0.7, 0.75, 1 }, "video");
    }

    const cy = y + vid_h;
    ui.drawRect(.{ .x = x, .y = cy, .w = w, .h = ctrl_h }, .{ 0.12, 0.13, 0.15, 0.95 });
    const playing = bd.video_playing;
    const label = if (playing) "||" else ">";
    ui.drawRectBorder(.{ .x = x + 6, .y = cy + 4, .w = 28, .h = 20 }, .{ 0.25, 0.45, 0.85, 1 }, .{ 0.4, 0.6, 1, 1 }, 1);
    ui.drawText(x + 14, cy + 7, 1.4, .{ 1, 1, 1, 1 }, label);
    ui.drawText(x + 42, cy + 7, 1.25, .{ 0.75, 0.78, 0.82, 1 }, "robot-breakdance");

    if (ui.input.mousePressed(.left)) {
        const mx = ui.input.mouse_x;
        const my = ui.input.mouse_y;
        if ((mx >= x + 6 and mx <= x + 34 and my >= cy + 4 and my <= cy + 24) or
            (mx >= x and mx <= x + w and my >= y and my <= y + vid_h))
        {
            bd.video_playing = !bd.video_playing;
        }
    }
}

fn hitLink(n: *dom.Node, ox: f32, oy: f32, mx: f32, my: f32) ?[]const u8 {
    if (n.style.display == .none) return null;
    // Depth-first: prefer innermost link if nested (rare).
    var child_hit: ?[]const u8 = null;
    for (n.children.items) |c| {
        if (hitLink(c, ox, oy, mx, my)) |h| child_hit = h;
    }
    if (child_hit) |h| return h;
    if (n.kind == .element and std.mem.eql(u8, n.tag, "a")) {
        const x = ox + n.box.x;
        const y = oy + n.box.y;
        const bw = @max(n.box.w, 8);
        const bh = @max(n.box.h, 14);
        if (mx >= x and my >= y and mx < x + bw and my < y + bh) {
            return n.attr("href");
        }
    }
    return null;
}
