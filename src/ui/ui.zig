//! Immediate-mode UI (Style A: begin/end + defer).
//! Inspired by Game9 UI__Clickable hot/active FSM; Clay not used as a dependency.

const std = @import("std");
const input_mod = @import("../input.zig");
const font_mod = @import("../font.zig");
const theme_mod = @import("theme.zig");
const draw = @import("../draw.zig");

pub const Theme = theme_mod.Theme;
pub const Color = theme_mod.Color;
pub const Input = input_mod.Input;
pub const Font = font_mod.Font;

pub const Id = struct {
    a: u64 = 0,
    b: u64 = 0,

    pub fn eq(self: Id, o: Id) bool {
        return self.a == o.a and self.b == o.b;
    }
    pub fn isNone(self: Id) bool {
        return self.a == 0 and self.b == 0;
    }
};

pub const Rect = struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,

    pub fn contains(self: Rect, px: f32, py: f32) bool {
        return px >= self.x and py >= self.y and px < self.x + self.w and py < self.y + self.h;
    }
};

const LayoutNode = struct {
    kind: enum { free, vstack, hstack },
    cursor_x: f32,
    cursor_y: f32,
    origin_x: f32,
    origin_y: f32,
    width: f32,
    height: f32,
    pad: f32,
    gap: f32,
    max_cross: f32 = 0,
};

const MaxLayout = 32;
const MaxPrev = 256;

const IdRect = struct { id: Id, r: Rect };

pub const Ui = struct {
    input: *const Input = undefined,
    font: *const Font = undefined,
    theme: Theme = theme_mod.dark,
    width: f32 = 0,
    height: f32 = 0,
    dt: f32 = 0,
    time: f64 = 0,

    /// Phase-8 command list (flushed by app after endFrame).
    cmds: draw.List = .{},

    hot: Id = .{},
    active: Id = .{},
    any_hot: bool = false,

    layout_stack: [MaxLayout]LayoutNode = undefined,
    layout_depth: usize = 0,

    /// Previous-frame geometry for interactions (phase 7 light).
    prev_rects: [MaxPrev]IdRect = undefined,
    prev_count: usize = 0,
    curr_rects: [MaxPrev]IdRect = undefined,
    curr_count: usize = 0,

    id_stack: [16]u64 = undefined,
    id_depth: usize = 0,

    /// Scroll area state (keyed loosely by id hash).
    scroll_y: std.AutoHashMap(u64, f32) = undefined,
    text_bufs: std.AutoHashMap(u64, []u8) = undefined,
    allocator: std.mem.Allocator = undefined,
    inited: bool = false,

    /// Focus for text input.
    focus: Id = .{},

    pub fn init(self: *Ui, allocator: std.mem.Allocator) void {
        self.allocator = allocator;
        self.scroll_y = std.AutoHashMap(u64, f32).init(allocator);
        self.text_bufs = std.AutoHashMap(u64, []u8).init(allocator);
        self.inited = true;
    }

    pub fn deinit(self: *Ui) void {
        if (!self.inited) return;
        var it = self.text_bufs.iterator();
        while (it.next()) |e| {
            self.allocator.free(e.value_ptr.*);
        }
        self.text_bufs.deinit();
        self.scroll_y.deinit();
        self.inited = false;
    }

    pub fn beginFrame(self: *Ui, input: *const Input, font: *const Font, w: f32, h: f32, dt: f32, time: f64) void {
        self.input = input;
        self.font = font;
        self.width = w;
        self.height = h;
        self.dt = dt;
        self.time = time;
        self.any_hot = false;
        self.layout_depth = 0;
        self.id_depth = 0;
        self.curr_count = 0;
        self.cmds.clear();

        // Root free layout = full window.
        self.layout_stack[0] = .{
            .kind = .free,
            .cursor_x = 0,
            .cursor_y = 0,
            .origin_x = 0,
            .origin_y = 0,
            .width = w,
            .height = h,
            .pad = 0,
            .gap = 0,
        };
        self.layout_depth = 1;
    }

    pub fn endFrame(self: *Ui) void {
        if (!self.any_hot) {
            self.hot = .{};
        }
        // If mouse released and nothing active claim, clear active.
        if (!self.input.mouseDown(.left) and !self.active.isNone()) {
            // active cleared on release after widgets read click
        }
        if (!self.input.mouseDown(.left)) {
            self.active = .{};
        }
        // Swap prev geometry.
        self.prev_rects = self.curr_rects;
        self.prev_count = self.curr_count;
    }

    pub fn id(self: *Ui, name: []const u8) Id {
        var h: u64 = 0xcbf29ce484222325;
        const prime: u64 = 0x100000001b3;
        var i: usize = 0;
        while (i < self.id_depth) : (i += 1) {
            h ^= self.id_stack[i];
            h *%= prime;
        }
        for (name) |c| {
            h ^= c;
            h *%= prime;
        }
        return .{ .a = h, .b = @as(u64, @intCast(name.len)) << 32 | (if (self.id_depth > 0) self.id_stack[self.id_depth - 1] else 0) };
    }

    pub fn pushId(self: *Ui, name: []const u8) void {
        const i = self.id(name);
        if (self.id_depth < self.id_stack.len) {
            self.id_stack[self.id_depth] = i.a;
            self.id_depth += 1;
        }
    }

    pub fn popId(self: *Ui) void {
        if (self.id_depth > 0) self.id_depth -= 1;
    }

    fn remember(self: *Ui, i: Id, r: Rect) void {
        if (self.curr_count < MaxPrev) {
            self.curr_rects[self.curr_count] = .{ .id = i, .r = r };
            self.curr_count += 1;
        }
    }

    fn prevRect(self: *const Ui, i: Id) ?Rect {
        var n: usize = 0;
        while (n < self.prev_count) : (n += 1) {
            if (self.prev_rects[n].id.eq(i)) return self.prev_rects[n].r;
        }
        return null;
    }

    fn top(self: *Ui) *LayoutNode {
        return &self.layout_stack[self.layout_depth - 1];
    }

    /// Allocate next rect in current layout; for free layout uses absolute pos if provided.
    pub fn alloc(self: *Ui, w: f32, h: f32) Rect {
        const L = self.top();
        switch (L.kind) {
            .free => {
                // Caller must use place() for free layout; default stacks from top-left with pad.
                const r = Rect{ .x = L.cursor_x + L.pad, .y = L.cursor_y + L.pad, .w = w, .h = h };
                L.cursor_y += h + L.gap;
                return r;
            },
            .vstack => {
                const r = Rect{ .x = L.origin_x + L.pad, .y = L.cursor_y, .w = if (w > 0) w else L.width - 2 * L.pad, .h = h };
                L.cursor_y += h + L.gap;
                L.max_cross = @max(L.max_cross, r.w);
                return r;
            },
            .hstack => {
                const r = Rect{ .x = L.cursor_x, .y = L.origin_y + L.pad, .w = w, .h = if (h > 0) h else L.height - 2 * L.pad };
                L.cursor_x += w + L.gap;
                L.max_cross = @max(L.max_cross, r.h);
                return r;
            },
        }
    }

    pub fn place(self: *Ui, x: f32, y: f32, w: f32, h: f32) Rect {
        _ = self;
        return .{ .x = x, .y = y, .w = w, .h = h };
    }

    // --- Drawing primitives (queue → RenderCommand list) --------------------

    pub fn drawRect(self: *Ui, r: Rect, color: Color) void {
        self.cmds.rect(.{ .x = r.x, .y = r.y, .w = r.w, .h = r.h }, color);
    }

    pub fn drawRectBorder(self: *Ui, r: Rect, fill: Color, border: Color, thickness: f32) void {
        self.drawRect(r, border);
        const inner = Rect{
            .x = r.x + thickness,
            .y = r.y + thickness,
            .w = @max(0, r.w - 2 * thickness),
            .h = @max(0, r.h - 2 * thickness),
        };
        self.drawRect(inner, fill);
    }

    pub fn drawText(self: *Ui, x: f32, y: f32, size: f32, color: Color, text: []const u8) void {
        self.cmds.text(x, y, size, color, text);
    }

    pub fn flushDraw(self: *Ui) void {
        self.cmds.flushSgl(self.font);
    }

    // --- Interaction --------------------------------------------------------

    fn hitTest(self: *Ui, i: Id, r: Rect) bool {
        // Prefer previous-frame rect if available.
        const test_r = self.prevRect(i) orelse r;
        return test_r.contains(self.input.mouse_x, self.input.mouse_y);
    }

    pub fn interact(self: *Ui, i: Id, r: Rect, disabled: bool) struct { hot: bool, active: bool, clicked: bool } {
        self.remember(i, r);
        if (disabled) return .{ .hot = false, .active = false, .clicked = false };

        const over = self.hitTest(i, r);
        if (over) {
            self.any_hot = true;
            self.hot = i;
        }
        const is_hot = self.hot.eq(i);
        if (over and self.input.mousePressed(.left) and self.active.isNone()) {
            self.active = i;
        }
        const is_active = self.active.eq(i);
        const clicked = is_active and self.input.mouseReleased(.left) and over;
        return .{ .hot = is_hot, .active = is_active, .clicked = clicked };
    }

    // --- Layout containers --------------------------------------------------

    pub fn beginVStack(self: *Ui, opts: struct { x: f32 = 0, y: f32 = 0, w: f32 = 0, h: f32 = 0, pad: ?f32 = null, gap: ?f32 = null }) void {
        const pad = opts.pad orelse self.theme.pad;
        const gap = opts.gap orelse self.theme.gap;
        const parent = self.top();
        var x = opts.x;
        var y = opts.y;
        var w = opts.w;
        var h = opts.h;
        if (w == 0 and h == 0 and parent.kind != .free) {
            // Nest: take remaining width of parent.
            x = parent.origin_x + parent.pad;
            y = parent.cursor_y;
            w = parent.width - 2 * parent.pad;
            h = parent.height; // soft
        }
        if (self.layout_depth < MaxLayout) {
            self.layout_stack[self.layout_depth] = .{
                .kind = .vstack,
                .cursor_x = x + pad,
                .cursor_y = y + pad,
                .origin_x = x,
                .origin_y = y,
                .width = if (w > 0) w else self.width - x,
                .height = if (h > 0) h else self.height - y,
                .pad = pad,
                .gap = gap,
            };
            self.layout_depth += 1;
        }
    }

    pub fn endVStack(self: *Ui) Rect {
        if (self.layout_depth <= 1) return .{};
        const L = self.top().*;
        self.layout_depth -= 1;
        const used_h = L.cursor_y - L.origin_y + L.pad - L.gap;
        const r = Rect{ .x = L.origin_x, .y = L.origin_y, .w = L.width, .h = @max(0, used_h) };
        // Advance parent if parent is vstack.
        const p = self.top();
        if (p.kind == .vstack) {
            p.cursor_y = r.y + r.h + p.gap;
        } else if (p.kind == .hstack) {
            p.cursor_x = r.x + r.w + p.gap;
        }
        return r;
    }

    pub fn beginHStack(self: *Ui, opts: struct { x: f32 = 0, y: f32 = 0, w: f32 = 0, h: f32 = 0, pad: ?f32 = null, gap: ?f32 = null }) void {
        const pad = opts.pad orelse self.theme.pad;
        const gap = opts.gap orelse self.theme.gap;
        if (self.layout_depth < MaxLayout) {
            self.layout_stack[self.layout_depth] = .{
                .kind = .hstack,
                .cursor_x = opts.x + pad,
                .cursor_y = opts.y + pad,
                .origin_x = opts.x,
                .origin_y = opts.y,
                .width = if (opts.w > 0) opts.w else self.width - opts.x,
                .height = if (opts.h > 0) opts.h else self.theme.row_h + 2 * pad,
                .pad = pad,
                .gap = gap,
            };
            self.layout_depth += 1;
        }
    }

    pub fn endHStack(self: *Ui) Rect {
        if (self.layout_depth <= 1) return .{};
        const L = self.top().*;
        self.layout_depth -= 1;
        const used_w = L.cursor_x - L.origin_x + L.pad - L.gap;
        const r = Rect{ .x = L.origin_x, .y = L.origin_y, .w = @max(0, used_w), .h = L.height };
        const p = self.top();
        if (p.kind == .vstack) {
            p.cursor_y = r.y + r.h + p.gap;
        }
        return r;
    }

    pub fn beginPanel(self: *Ui, opts: struct {
        id: []const u8 = "panel",
        x: f32 = 0,
        y: f32 = 0,
        w: f32 = 320,
        h: f32 = 200,
        title: ?[]const u8 = null,
    }) bool {
        const i = self.id(opts.id);
        const r = self.place(opts.x, opts.y, opts.w, opts.h);
        self.remember(i, r);
        self.drawRectBorder(r, self.theme.panel, self.theme.panel_border, 1);

        var content_y = r.y + self.theme.pad;
        if (opts.title) |title| {
            const th = self.theme.row_h;
            self.drawRect(.{ .x = r.x, .y = r.y, .w = r.w, .h = th }, .{ 0.16, 0.17, 0.21, 1 });
            self.drawText(r.x + self.theme.pad, r.y + 6, self.theme.title_font_size, self.theme.text, title);
            content_y = r.y + th + self.theme.pad;
        }
        self.pushId(opts.id);
        self.beginVStack(.{
            .x = r.x,
            .y = content_y - self.theme.pad,
            .w = r.w,
            .h = r.h - (content_y - r.y),
            .pad = self.theme.pad,
            .gap = self.theme.gap,
        });
        return true;
    }

    pub fn endPanel(self: *Ui) void {
        _ = self.endVStack();
        self.popId();
    }

    // --- Widgets ------------------------------------------------------------

    pub fn spacer(self: *Ui, h: f32) void {
        _ = self.alloc(0, h);
    }

    pub fn label(self: *Ui, opts: struct { text: []const u8, color: ?Color = null, size: ?f32 = null }) void {
        const size = opts.size orelse self.theme.font_size;
        const color = opts.color orelse self.theme.text;
        const m = self.font.measure(opts.text, size);
        const r = self.alloc(m.w, @max(m.h, self.theme.row_h * 0.7));
        self.drawText(r.x, r.y + 2, size, color, opts.text);
    }

    pub fn button(self: *Ui, opts: struct {
        id: []const u8,
        label: []const u8,
        w: f32 = 0,
        disabled: bool = false,
    }) bool {
        const i = self.id(opts.id);
        const size = self.theme.font_size;
        const m = self.font.measure(opts.label, size);
        const bw = if (opts.w > 0) opts.w else @max(m.w + 24, 80);
        const bh = self.theme.button_h;
        const r = self.alloc(bw, bh);

        const st = self.interact(i, r, opts.disabled);
        const fill: Color = if (opts.disabled)
            self.theme.button_disabled
        else if (st.active)
            self.theme.button_active
        else if (st.hot)
            self.theme.button_hot
        else
            self.theme.button;

        self.drawRectBorder(r, fill, self.theme.panel_border, 1);
        const tx = r.x + (r.w - m.w) * 0.5;
        const ty = r.y + (r.h - m.h) * 0.5;
        const tc: Color = if (opts.disabled) self.theme.text_dim else self.theme.text;
        self.drawText(tx, ty, size, tc, opts.label);
        return st.clicked;
    }

    pub fn radio(self: *Ui, opts: struct { id: []const u8, label: []const u8, group: *u32, value: u32 }) bool {
        const i = self.id(opts.id);
        const box = 18.0;
        const size = self.theme.font_size;
        const m = self.font.measure(opts.label, size);
        const r = self.alloc(box + 8 + m.w, self.theme.row_h);
        const br = Rect{ .x = r.x, .y = r.y + (r.h - box) * 0.5, .w = box, .h = box };
        const st = self.interact(i, r, false);
        if (st.clicked) opts.group.* = opts.value;
        const on = opts.group.* == opts.value;
        self.drawRectBorder(br, self.theme.input_bg, self.theme.panel_border, 1);
        if (on) {
            const inset = 4;
            self.drawRect(.{
                .x = br.x + inset,
                .y = br.y + inset,
                .w = br.w - 2 * inset,
                .h = br.h - 2 * inset,
            }, self.theme.accent);
        }
        self.drawText(r.x + box + 8, r.y + (r.h - m.h) * 0.5, size, self.theme.text, opts.label);
        return st.clicked;
    }

    pub fn checkbox(self: *Ui, opts: struct { id: []const u8, label: []const u8, value: *bool }) bool {
        const i = self.id(opts.id);
        const box = 18.0;
        const size = self.theme.font_size;
        const m = self.font.measure(opts.label, size);
        const r = self.alloc(box + 8 + m.w, self.theme.row_h);
        const br = Rect{ .x = r.x, .y = r.y + (r.h - box) * 0.5, .w = box, .h = box };
        const st = self.interact(i, r, false);
        if (st.clicked) opts.value.* = !opts.value.*;

        self.drawRectBorder(br, self.theme.input_bg, self.theme.panel_border, 1);
        if (opts.value.*) {
            const inset = 4;
            self.drawRect(.{
                .x = br.x + inset,
                .y = br.y + inset,
                .w = br.w - 2 * inset,
                .h = br.h - 2 * inset,
            }, self.theme.accent);
        }
        self.drawText(r.x + box + 8, r.y + (r.h - m.h) * 0.5, size, self.theme.text, opts.label);
        return st.clicked;
    }

    pub fn slider(self: *Ui, opts: struct {
        id: []const u8,
        label: []const u8,
        value: *f32,
        min: f32 = 0,
        max: f32 = 1,
        w: f32 = 200,
    }) bool {
        const i = self.id(opts.id);
        const size = self.theme.font_size;
        _ = self.font.measure(opts.label, size);
        const track_h = 8.0;
        const row_h = self.theme.row_h + 8;
        const r = self.alloc(opts.w, row_h);

        self.drawText(r.x, r.y, size, self.theme.text_dim, opts.label);

        const track = Rect{ .x = r.x, .y = r.y + 16, .w = opts.w, .h = track_h };
        const st = self.interact(i, track, false);
        var changed = false;
        if (st.active and self.input.mouseDown(.left)) {
            const t = std.math.clamp((self.input.mouse_x - track.x) / track.w, 0, 1);
            const nv = opts.min + t * (opts.max - opts.min);
            if (nv != opts.value.*) {
                opts.value.* = nv;
                changed = true;
            }
        }
        const t = if (opts.max > opts.min) (opts.value.* - opts.min) / (opts.max - opts.min) else 0;
        self.drawRect(track, self.theme.slider_track);
        self.drawRect(.{ .x = track.x, .y = track.y, .w = track.w * t, .h = track.h }, self.theme.slider_fill);
        const knob_x = track.x + track.w * t - 5;
        self.drawRect(.{ .x = knob_x, .y = track.y - 4, .w = 10, .h = track_h + 8 }, if (st.hot or st.active) self.theme.accent_hot else self.theme.accent);

        var buf: [32]u8 = undefined;
        const val_s = std.fmt.bufPrint(&buf, "{d:.2}", .{opts.value.*}) catch "?";
        self.drawText(track.x + track.w + 8, track.y - 2, size, self.theme.text_dim, val_s);
        return changed;
    }

    pub fn textInput(self: *Ui, opts: struct {
        id: []const u8,
        label: []const u8,
        buf: []u8,
        len: *usize,
        w: f32 = 220,
    }) bool {
        const i = self.id(opts.id);
        const size = self.theme.font_size;
        const r = self.alloc(opts.w, self.theme.row_h + 14);
        self.drawText(r.x, r.y, size, self.theme.text_dim, opts.label);
        const box = Rect{ .x = r.x, .y = r.y + 12, .w = opts.w, .h = self.theme.row_h };
        const st = self.interact(i, box, false);
        if (st.clicked) self.focus = i;

        const focused = self.focus.eq(i);
        self.drawRectBorder(box, self.theme.input_bg, if (focused) self.theme.accent else self.theme.panel_border, 1);

        var changed = false;
        if (focused) {
            if (self.input.text_len > 0) {
                const avail = opts.buf.len - opts.len.*;
                const n = @min(avail, self.input.text_len);
                @memcpy(opts.buf[opts.len.* .. opts.len.* + n], self.input.text[0..n]);
                opts.len.* += n;
                changed = n > 0;
            }
            if (self.input.keyPressed(.backspace) and opts.len.* > 0) {
                opts.len.* -= 1;
                changed = true;
            }
        }
        const shown = opts.buf[0..opts.len.*];
        self.drawText(box.x + 6, box.y + 6, size, self.theme.text, shown);
        if (focused and @mod(@as(i64, @intFromFloat(self.time * 2)), 2) == 0) {
            const m = self.font.measure(shown, size);
            self.drawRect(.{ .x = box.x + 6 + m.w, .y = box.y + 4, .w = 2, .h = box.h - 8 }, self.theme.text);
        }
        return changed;
    }

    pub fn progress(self: *Ui, opts: struct { label: []const u8, value: f32, w: f32 = 200 }) void {
        const size = self.theme.font_size;
        const r = self.alloc(opts.w, self.theme.row_h);
        self.drawText(r.x, r.y, size, self.theme.text_dim, opts.label);
        const track = Rect{ .x = r.x, .y = r.y + 14, .w = opts.w, .h = 10 };
        const t = std.math.clamp(opts.value, 0, 1);
        self.drawRect(track, self.theme.slider_track);
        self.drawRect(.{ .x = track.x, .y = track.y, .w = track.w * t, .h = track.h }, self.theme.slider_fill);
    }

    pub fn separator(self: *Ui) void {
        const r = self.alloc(0, 8);
        self.drawRect(.{ .x = r.x, .y = r.y + 3, .w = self.top().width - 2 * self.top().pad, .h = 1 }, self.theme.panel_border);
    }

    /// Scrollable region with GPU scissor clip + wheel scroll when hovered.
    pub fn beginScroll(self: *Ui, opts: struct { id: []const u8, x: f32, y: f32, w: f32, h: f32 }) f32 {
        const i = self.id(opts.id);
        const r = self.place(opts.x, opts.y, opts.w, opts.h);
        self.remember(i, r);
        self.drawRectBorder(r, self.theme.panel, self.theme.panel_border, 1);
        const gop = self.scroll_y.getOrPut(i.a) catch return 0;
        if (!gop.found_existing) gop.value_ptr.* = 0;
        if (r.contains(self.input.mouse_x, self.input.mouse_y)) {
            gop.value_ptr.* -= self.input.scroll_y * 24;
            if (gop.value_ptr.* < 0) gop.value_ptr.* = 0;
        }
        const scroll = gop.value_ptr.*;
        // Clip subsequent draw commands to the scroll viewport (inset for border).
        const clip = Rect{ .x = r.x + 1, .y = r.y + 1, .w = r.w - 2, .h = r.h - 2 };
        self.cmds.push(.{ .scissor_push = .{ .x = clip.x, .y = clip.y, .w = clip.w, .h = clip.h } });
        self.pushId(opts.id);
        self.beginVStack(.{
            .x = r.x,
            .y = r.y - scroll,
            .w = r.w,
            .h = r.h + scroll,
            .pad = self.theme.pad,
            .gap = self.theme.gap,
        });
        return scroll;
    }

    pub fn endScroll(self: *Ui) void {
        _ = self.endVStack();
        self.popId();
        self.cmds.push(.{ .scissor_pop = {} });
    }

    /// Toggle switch (checkbox alternative).
    pub fn toggle(self: *Ui, opts: struct { id: []const u8, label: []const u8, value: *bool }) bool {
        const i = self.id(opts.id);
        const track_w: f32 = 40;
        const track_h: f32 = 20;
        const size = self.theme.font_size;
        const m = self.font.measure(opts.label, size);
        const r = self.alloc(track_w + 8 + m.w, self.theme.row_h);
        const tr = Rect{
            .x = r.x,
            .y = r.y + (r.h - track_h) * 0.5,
            .w = track_w,
            .h = track_h,
        };
        const st = self.interact(i, r, false);
        if (st.clicked) opts.value.* = !opts.value.*;
        const fill: Color = if (opts.value.*) self.theme.accent else self.theme.slider_track;
        self.drawRectBorder(tr, fill, self.theme.panel_border, 1);
        const knob_x = if (opts.value.*) tr.x + tr.w - track_h + 2 else tr.x + 2;
        self.drawRect(.{ .x = knob_x, .y = tr.y + 2, .w = track_h - 4, .h = track_h - 4 }, self.theme.text);
        self.drawText(r.x + track_w + 8, r.y + (r.h - m.h) * 0.5, size, self.theme.text, opts.label);
        return st.clicked;
    }

    /// Dropdown / select. `open` and `selected` are app-owned persistent state.
    pub fn dropdown(self: *Ui, opts: struct {
        id: []const u8,
        label: []const u8,
        items: []const []const u8,
        selected: *usize,
        open: *bool,
        w: f32 = 200,
    }) bool {
        const i = self.id(opts.id);
        const size = self.theme.font_size;
        const r = self.alloc(opts.w, self.theme.row_h + 14);
        self.drawText(r.x, r.y, size, self.theme.text_dim, opts.label);
        const box = Rect{ .x = r.x, .y = r.y + 12, .w = opts.w, .h = self.theme.row_h };
        const st = self.interact(i, box, false);
        if (st.clicked) opts.open.* = !opts.open.*;

        const sel = if (opts.selected.* < opts.items.len) opts.items[opts.selected.*] else "(none)";
        self.drawRectBorder(box, self.theme.input_bg, if (opts.open.*) self.theme.accent else self.theme.panel_border, 1);
        self.drawText(box.x + 6, box.y + 6, size, self.theme.text, sel);
        self.drawText(box.x + box.w - 18, box.y + 6, size, self.theme.text_dim, if (opts.open.*) "^" else "v");

        var changed = false;
        if (opts.open.*) {
            const item_h = self.theme.row_h;
            const menu = Rect{
                .x = box.x,
                .y = box.y + box.h,
                .w = box.w,
                .h = item_h * @as(f32, @floatFromInt(opts.items.len)),
            };
            self.drawRectBorder(menu, self.theme.panel, self.theme.panel_border, 1);
            for (opts.items, 0..) |item, idx| {
                const ir = Rect{
                    .x = menu.x,
                    .y = menu.y + @as(f32, @floatFromInt(idx)) * item_h,
                    .w = menu.w,
                    .h = item_h,
                };
                var id_buf: [64]u8 = undefined;
                const iid_s = std.fmt.bufPrint(&id_buf, "{s}#{d}", .{ opts.id, idx }) catch "dd";
                const iid = self.id(iid_s);
                const ist = self.interact(iid, ir, false);
                if (ist.hot or opts.selected.* == idx) {
                    self.drawRect(ir, if (opts.selected.* == idx) self.theme.selected else self.theme.button_hot);
                }
                self.drawText(ir.x + 6, ir.y + 6, size, self.theme.text, item);
                if (ist.clicked) {
                    opts.selected.* = idx;
                    opts.open.* = false;
                    changed = true;
                }
            }
            // Click outside closes (if not over menu/box).
            if (self.input.mousePressed(.left)) {
                const over = box.contains(self.input.mouse_x, self.input.mouse_y) or
                    menu.contains(self.input.mouse_x, self.input.mouse_y);
                if (!over) opts.open.* = false;
            }
        }
        return changed;
    }

    /// Horizontal tab bar. Returns true if selection changed.
    pub fn tabs(self: *Ui, opts: struct {
        id: []const u8,
        items: []const []const u8,
        selected: *usize,
        w: f32 = 0,
    }) bool {
        const bar_w = if (opts.w > 0) opts.w else self.top().width - 2 * self.top().pad;
        const r = self.alloc(bar_w, self.theme.row_h + 4);
        const n: f32 = @floatFromInt(@max(opts.items.len, 1));
        const tw = bar_w / n;
        var changed = false;
        self.pushId(opts.id);
        defer self.popId();
        for (opts.items, 0..) |item, idx| {
            const tr = Rect{
                .x = r.x + @as(f32, @floatFromInt(idx)) * tw,
                .y = r.y,
                .w = tw - 2,
                .h = r.h,
            };
            const tid = self.id(item);
            const st = self.interact(tid, tr, false);
            const on = opts.selected.* == idx;
            const fill: Color = if (on) self.theme.selected else if (st.hot) self.theme.button_hot else self.theme.button;
            self.drawRectBorder(tr, fill, self.theme.panel_border, 1);
            const m = self.font.measure(item, self.theme.font_size);
            self.drawText(tr.x + (tr.w - m.w) * 0.5, tr.y + (tr.h - m.h) * 0.5, self.theme.font_size, if (on) self.theme.accent else self.theme.text, item);
            if (st.clicked) {
                opts.selected.* = idx;
                changed = true;
            }
        }
        return changed;
    }
};
