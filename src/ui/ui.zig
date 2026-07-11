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
    input: *Input = undefined,
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

    /// Tooltip: set via `setTooltip` while a widget is hot; drawn in `endFrame`.
    tooltip_text: [128]u8 = undefined,
    tooltip_len: usize = 0,
    tooltip_set: bool = false,

    /// Toast stack (app can also call `toast`).
    toasts: [4]Toast = .{.{}, .{}, .{}, .{}},
    toast_count: usize = 0,

    /// True if a modal consumed Esc this frame (app should not quit).
    consumed_escape: bool = false,

    /// Active drag (splitter, etc.).
    drag: Id = .{},
    drag_anchor: f32 = 0,
    drag_value0: f32 = 0,

    /// Context menu (right-click).
    ctx_open: bool = false,
    ctx_x: f32 = 0,
    ctx_y: f32 = 0,
    /// Flat id (ignores pushId stack) so open/draw can span layout scopes.
    ctx_owner: Id = .{},
    /// Skip outside-click dismiss on the frame the menu opened.
    ctx_just_opened: bool = false,

    /// Open menubar dropdown (flat id of the menu root, e.g. "file").
    menu_open: Id = .{},
    menu_anchor: Rect = .{},

    /// Command palette (Ctrl+K / Ctrl+P).
    palette_open: bool = false,
    palette_query: [64]u8 = undefined,
    palette_query_len: usize = 0,
    palette_sel: usize = 0,

    /// Simple ring log for console panel.
    log_lines: [48][96]u8 = undefined,
    log_lens: [48]usize = @splat(0),
    log_count: usize = 0,
    log_head: usize = 0,

    /// Nested beginPanel(scroll=true) markers for endPanel scissor pops.
    panel_scroll_stack: [8]bool = @splat(false),
    panel_scroll_depth: usize = 0,

    pub const ToastKind = enum { info, ok, warn, err };
    pub const Toast = struct {
        text: [96]u8 = undefined,
        len: usize = 0,
        expires: f64 = 0,
        kind: ToastKind = .info,
    };

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

    pub fn beginFrame(self: *Ui, input: *Input, font: *const Font, w: f32, h: f32, dt: f32, time: f64) void {
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
        self.panel_scroll_depth = 0;
        self.cmds.clear();
        self.tooltip_set = false;
        self.tooltip_len = 0;
        self.consumed_escape = false;
        // Clear drag when mouse released.
        if (!input.mouseDown(.left) and !self.drag.isNone()) {
            self.drag = .{};
        }
        // ctx_just_opened cleared at end of frame after contextMenu runs.

        // Expire toasts.
        var ti: usize = 0;
        while (ti < self.toast_count) {
            if (self.toasts[ti].expires <= time) {
                var j = ti;
                while (j + 1 < self.toast_count) : (j += 1) {
                    self.toasts[j] = self.toasts[j + 1];
                }
                self.toast_count -= 1;
            } else {
                ti += 1;
            }
        }

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

        // Draw tooltip near cursor (after widgets).
        if (self.tooltip_set and self.tooltip_len > 0) {
            const msg = self.tooltip_text[0..self.tooltip_len];
            const m = self.font.measure(msg, self.theme.font_size);
            const pad: f32 = 6;
            var tx = self.input.mouse_x + 14;
            var ty = self.input.mouse_y + 16;
            if (tx + m.w + pad * 2 > self.width) tx = self.width - m.w - pad * 2;
            if (ty + m.h + pad * 2 > self.height) ty = self.input.mouse_y - m.h - pad * 2 - 8;
            const tr = Rect{ .x = tx, .y = ty, .w = m.w + pad * 2, .h = m.h + pad * 2 };
            self.drawRectBorder(tr, self.theme.tooltip_bg, self.theme.panel_border, 1);
            self.drawText(tr.x + pad, tr.y + pad, self.theme.font_size, self.theme.text, msg);
        }

        // Draw toasts bottom-right.
        if (self.toast_count > 0) {
            var y = self.height - 16;
            var k: usize = self.toast_count;
            while (k > 0) {
                k -= 1;
                const t = self.toasts[k];
                const msg = t.text[0..t.len];
                const m = self.font.measure(msg, self.theme.font_size);
                const pad: f32 = 10;
                const tw = m.w + pad * 2;
                const th = m.h + pad * 2;
                y -= th + 8;
                const tr = Rect{ .x = self.width - tw - 16, .y = y, .w = tw, .h = th };
                const accent: Color = switch (t.kind) {
                    .info => self.theme.info,
                    .ok => self.theme.accent,
                    .warn => self.theme.warning,
                    .err => self.theme.danger,
                };
                self.drawRectBorder(tr, self.theme.toast_bg, accent, 2);
                self.drawText(tr.x + pad, tr.y + pad, self.theme.font_size, self.theme.text, msg);
            }
        }
    }

    pub fn setTooltip(self: *Ui, text: []const u8) void {
        const n = @min(text.len, self.tooltip_text.len);
        @memcpy(self.tooltip_text[0..n], text[0..n]);
        self.tooltip_len = n;
        self.tooltip_set = true;
    }

    pub fn log(self: *Ui, text: []const u8) void {
        const slot = self.log_head % self.log_lines.len;
        const n = @min(text.len, self.log_lines[0].len);
        @memcpy(self.log_lines[slot][0..n], text[0..n]);
        self.log_lens[slot] = n;
        self.log_head += 1;
        if (self.log_count < self.log_lines.len) self.log_count += 1;
    }

    pub fn toast(self: *Ui, text: []const u8, kind: ToastKind, duration_s: f64) void {
        if (self.toast_count >= self.toasts.len) {
            // Drop oldest.
            var j: usize = 0;
            while (j + 1 < self.toast_count) : (j += 1) {
                self.toasts[j] = self.toasts[j + 1];
            }
            self.toast_count -= 1;
        }
        var t = &self.toasts[self.toast_count];
        const n = @min(text.len, t.text.len);
        @memcpy(t.text[0..n], text[0..n]);
        t.len = n;
        t.kind = kind;
        t.expires = self.time + duration_s;
        self.toast_count += 1;
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

    /// Id that ignores the pushId stack (menus/context that span scopes).
    pub fn idFlat(self: *Ui, name: []const u8) Id {
        _ = self;
        var h: u64 = 0xcbf29ce484222325;
        const prime: u64 = 0x100000001b3;
        for (name) |c| {
            h ^= c;
            h *%= prime;
        }
        return .{ .a = h, .b = @as(u64, @intCast(name.len)) };
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

    /// Lookup previous-frame rect by widget id name (same hashing as `id()`).
    pub fn prevRectOf(self: *Ui, name: []const u8) ?Rect {
        return self.prevRect(self.id(name));
    }

    /// Lookup current-frame rect if already submitted this frame.
    pub fn currRectOf(self: *const Ui, name_id: Id) ?Rect {
        var n: usize = 0;
        while (n < self.curr_count) : (n += 1) {
            if (self.curr_rects[n].id.eq(name_id)) return self.curr_rects[n].r;
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
        const parent = self.top();
        var x = opts.x;
        var y = opts.y;
        var w = opts.w;
        var h = opts.h;
        // Nest into parent layout when no explicit box was provided (same convention as beginVStack).
        if (w == 0 and h == 0 and parent.kind != .free) {
            if (parent.kind == .vstack) {
                x = parent.origin_x + parent.pad;
                y = parent.cursor_y;
                w = parent.width - 2 * parent.pad;
                h = self.theme.row_h + 2 * pad;
            } else if (parent.kind == .hstack) {
                x = parent.cursor_x;
                y = parent.origin_y + parent.pad;
                w = parent.width;
                h = parent.height - 2 * parent.pad;
            }
        } else {
            if (h == 0) h = self.theme.row_h + 2 * pad;
            if (w == 0) w = self.width - x;
        }
        if (self.layout_depth < MaxLayout) {
            self.layout_stack[self.layout_depth] = .{
                .kind = .hstack,
                .cursor_x = x + pad,
                .cursor_y = y + pad,
                .origin_x = x,
                .origin_y = y,
                .width = w,
                .height = h,
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
            // Advance parent past this row (do not jump to absolute r.y if parent already moved).
            p.cursor_y = @max(p.cursor_y, r.y + r.h) + p.gap;
        } else if (p.kind == .hstack) {
            p.cursor_x = @max(p.cursor_x, r.x + r.w) + p.gap;
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
        /// When true, body scrolls with mouse wheel (state keyed by panel id).
        scroll: bool = false,
    }) bool {
        const i = self.id(opts.id);
        const r = self.place(opts.x, opts.y, opts.w, opts.h);
        self.remember(i, r);
        self.drawRectBorder(r, self.theme.panel, self.theme.panel_border, 1);

        var content_y = r.y + self.theme.pad;
        var title_h: f32 = 0;
        if (opts.title) |title| {
            title_h = self.theme.row_h;
            self.drawRect(.{ .x = r.x, .y = r.y, .w = r.w, .h = title_h }, .{ 0.16, 0.17, 0.21, 1 });
            self.drawText(r.x + self.theme.pad, r.y + 6, self.theme.title_font_size, self.theme.text, title);
            content_y = r.y + title_h + self.theme.pad;
        }
        const body = Rect{
            .x = r.x,
            .y = r.y + title_h,
            .w = r.w,
            .h = r.h - title_h,
        };

        var scroll_off: f32 = 0;
        if (opts.scroll) {
            const gop = self.scroll_y.getOrPut(i.a) catch null;
            if (gop) |g| {
                if (!g.found_existing) g.value_ptr.* = 0;
                if (body.contains(self.input.mouse_x, self.input.mouse_y)) {
                    g.value_ptr.* -= self.input.scroll_y * 28;
                    if (g.value_ptr.* < 0) g.value_ptr.* = 0;
                    // Soft max — content-driven clamp happens as user scrolls empty space.
                    if (g.value_ptr.* > 4000) g.value_ptr.* = 4000;
                }
                scroll_off = g.value_ptr.*;
            }
            self.cmds.push(.{ .scissor_push = .{
                .x = body.x + 1,
                .y = body.y + 1,
                .w = body.w - 2,
                .h = body.h - 2,
            } });
        }

        self.pushId(opts.id);
        // Stash whether this panel used scroll so endPanel can pop scissor.
        // Encode in id stack unused — use a simple side channel via gap field abuse? 
        // Instead: push a marker on a small stack.
        if (self.panel_scroll_depth < self.panel_scroll_stack.len) {
            self.panel_scroll_stack[self.panel_scroll_depth] = opts.scroll;
            self.panel_scroll_depth += 1;
        }
        self.beginVStack(.{
            .x = r.x,
            .y = content_y - self.theme.pad - scroll_off,
            .w = r.w,
            .h = body.h + scroll_off,
            .pad = self.theme.pad,
            .gap = self.theme.gap,
        });
        return true;
    }

    pub fn endPanel(self: *Ui) void {
        _ = self.endVStack();
        self.popId();
        if (self.panel_scroll_depth > 0) {
            self.panel_scroll_depth -= 1;
            if (self.panel_scroll_stack[self.panel_scroll_depth]) {
                self.cmds.push(.{ .scissor_pop = {} });
            }
        }
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
            changed = self.appendFocusedText(opts.buf, opts.len) or changed;
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

    fn appendFocusedText(self: *Ui, buf: []u8, len: *usize) bool {
        var changed = false;
        if (self.input.text_len > 0) {
            const avail = buf.len - len.*;
            const n = @min(avail, self.input.text_len);
            @memcpy(buf[len.* .. len.* + n], self.input.text[0..n]);
            len.* += n;
            changed = n > 0;
        }
        // Ctrl+V / clipboard paste buffer
        if (self.input.paste_len > 0) {
            const pasted = self.input.paste[0..self.input.paste_len];
            const avail = buf.len - len.*;
            const n = @min(avail, pasted.len);
            // Filter to printable ASCII + newline for multi-line.
            var wrote: usize = 0;
            for (pasted[0..n]) |ch| {
                if (ch == '\n' or ch == '\t' or (ch >= 32 and ch < 127)) {
                    if (len.* + wrote < buf.len) {
                        buf[len.* + wrote] = if (ch == '\t') ' ' else ch;
                        wrote += 1;
                    }
                }
            }
            len.* += wrote;
            self.input.paste_len = 0;
            changed = wrote > 0 or changed;
        }
        return changed;
    }

    /// Multi-line text area.
    pub fn textArea(self: *Ui, opts: struct {
        id: []const u8,
        label: []const u8,
        buf: []u8,
        len: *usize,
        w: f32 = 280,
        h: f32 = 100,
    }) bool {
        const i = self.id(opts.id);
        const size = self.theme.font_size;
        const r = self.alloc(opts.w, opts.h + 14);
        self.drawText(r.x, r.y, size, self.theme.text_dim, opts.label);
        const box = Rect{ .x = r.x, .y = r.y + 12, .w = opts.w, .h = opts.h };
        const st = self.interact(i, box, false);
        if (st.clicked) self.focus = i;
        const focused = self.focus.eq(i);
        self.drawRectBorder(box, self.theme.input_bg, if (focused) self.theme.accent else self.theme.panel_border, 1);

        var changed = false;
        if (focused) {
            changed = self.appendFocusedText(opts.buf, opts.len) or changed;
            if (self.input.keyPressed(.enter)) {
                if (opts.len.* < opts.buf.len) {
                    opts.buf[opts.len.*] = '\n';
                    opts.len.* += 1;
                    changed = true;
                }
            }
            if (self.input.keyPressed(.backspace) and opts.len.* > 0) {
                opts.len.* -= 1;
                changed = true;
            }
        }

        self.cmds.push(.{ .scissor_push = .{ .x = box.x + 1, .y = box.y + 1, .w = box.w - 2, .h = box.h - 2 } });
        // Draw lines; caret at end of buffer (insert point).
        const origin_x = box.x + 6;
        const origin_y = box.y + 4;
        const lh = self.font.lineHeight(size);
        const text = opts.buf[0..opts.len.*];
        var line_start: usize = 0;
        var li: usize = 0;
        var line_i: usize = 0;
        while (li <= text.len) : (li += 1) {
            if (li == text.len or text[li] == '\n') {
                const line = text[line_start..li];
                const ly = origin_y + @as(f32, @floatFromInt(line_i)) * lh;
                self.drawText(origin_x, ly, size, self.theme.text, line);
                line_i += 1;
                line_start = li + 1;
            }
        }
        // Caret after last line's content (or start of empty last line).
        var nlines: usize = 0;
        var last_nl: ?usize = null;
        for (text, 0..) |ch, idx| {
            if (ch == '\n') {
                nlines += 1;
                last_nl = idx;
            }
        }
        const last_start = if (last_nl) |n| n + 1 else 0;
        const last_line = text[last_start..];
        const caret_x = origin_x + self.font.measure(last_line, size).w;
        const caret_y = origin_y + @as(f32, @floatFromInt(nlines)) * lh;
        if (focused and @mod(@as(i64, @intFromFloat(self.time * 2)), 2) == 0) {
            self.drawRect(.{ .x = caret_x, .y = caret_y, .w = 2, .h = lh }, self.theme.text);
        }
        self.cmds.push(.{ .scissor_pop = {} });
        return changed;
    }

    /// Console log panel (reads internal ring buffer).
    pub fn console(self: *Ui, opts: struct { id: []const u8, x: f32, y: f32, w: f32, h: f32 }) void {
        const r = self.place(opts.x, opts.y, opts.w, opts.h);
        self.drawRectBorder(r, self.theme.input_bg, self.theme.panel_border, 1);
        self.drawText(r.x + 6, r.y + 4, self.theme.font_size, self.theme.text_dim, "console");
        self.cmds.push(.{ .scissor_push = .{ .x = r.x + 1, .y = r.y + 18, .w = r.w - 2, .h = r.h - 20 } });
        const lh = self.font.lineHeight(self.theme.font_size);
        var y = r.y + r.h - 6 - lh;
        var shown: usize = 0;
        const max_lines: usize = @intFromFloat(@max(1, (r.h - 24) / lh));
        var i: usize = 0;
        while (i < self.log_count and shown < max_lines) : (i += 1) {
            const idx = (self.log_head - 1 - i) % self.log_lines.len;
            const line = self.log_lines[idx][0..self.log_lens[idx]];
            self.drawText(r.x + 6, y, self.theme.font_size, self.theme.text, line);
            y -= lh;
            shown += 1;
        }
        self.cmds.push(.{ .scissor_pop = {} });
        _ = opts.id;
    }

    /// Command palette overlay. Returns selected command index into `items`, or null.
    pub fn commandPalette(self: *Ui, opts: struct {
        items: []const []const u8,
    }) ?usize {
        if (!self.palette_open) return null;

        // Dim
        self.drawRect(.{ .x = 0, .y = 0, .w = self.width, .h = self.height }, self.theme.overlay);

        if (self.input.keyPressed(.escape)) {
            self.palette_open = false;
            self.consumed_escape = true;
            return null;
        }

        const pw: f32 = @min(520, self.width - 40);
        const max_vis: usize = 10;
        const row_h = self.theme.row_h;
        const ph: f32 = row_h + 12 + @as(f32, @floatFromInt(@min(opts.items.len, max_vis))) * row_h + 16;
        const px = (self.width - pw) * 0.5;
        const py = self.height * 0.18;
        const box = Rect{ .x = px, .y = py, .w = pw, .h = ph };
        self.drawRectBorder(box, self.theme.modal, self.theme.accent, 2);
        self.drawText(box.x + 12, box.y + 8, self.theme.title_font_size, self.theme.text_dim, "Command palette");

        // Query field
        const qbox = Rect{ .x = box.x + 12, .y = box.y + 28, .w = pw - 24, .h = row_h };
        self.drawRectBorder(qbox, self.theme.input_bg, self.theme.accent, 1);
        // Always type into palette query while open
        if (self.input.text_len > 0) {
            const avail = self.palette_query.len - self.palette_query_len;
            const n = @min(avail, self.input.text_len);
            @memcpy(self.palette_query[self.palette_query_len .. self.palette_query_len + n], self.input.text[0..n]);
            self.palette_query_len += n;
            self.palette_sel = 0;
        }
        if (self.input.keyPressed(.backspace) and self.palette_query_len > 0) {
            self.palette_query_len -= 1;
            self.palette_sel = 0;
        }
        const q = self.palette_query[0..self.palette_query_len];
        if (q.len == 0) {
            self.drawText(qbox.x + 8, qbox.y + 6, self.theme.font_size, self.theme.text_dim, "Type to filter…");
        } else {
            self.drawText(qbox.x + 8, qbox.y + 6, self.theme.font_size, self.theme.text, q);
        }

        // Filter matches
        var matches: [64]usize = undefined;
        var mct: usize = 0;
        for (opts.items, 0..) |item, idx| {
            if (q.len == 0 or containsIgnoreCaseUi(item, q)) {
                if (mct < matches.len) {
                    matches[mct] = idx;
                    mct += 1;
                }
            }
        }
        if (mct == 0) {
            self.drawText(box.x + 12, qbox.y + row_h + 12, self.theme.font_size, self.theme.text_dim, "No matches");
            return null;
        }
        if (self.palette_sel >= mct) self.palette_sel = mct - 1;

        if (self.input.keyPressed(.down)) {
            self.palette_sel = @min(self.palette_sel + 1, mct - 1);
        }
        if (self.input.keyPressed(.up)) {
            if (self.palette_sel > 0) self.palette_sel -= 1;
        }

        const list_y = qbox.y + row_h + 8;
        var result: ?usize = null;
        const vis = @min(mct, max_vis);
        var vi: usize = 0;
        while (vi < vis) : (vi += 1) {
            const item_idx = matches[vi];
            const ir = Rect{
                .x = box.x + 12,
                .y = list_y + @as(f32, @floatFromInt(vi)) * row_h,
                .w = pw - 24,
                .h = row_h,
            };
            const on = vi == self.palette_sel;
            if (on) self.drawRect(ir, self.theme.selected);
            self.drawText(ir.x + 8, ir.y + 6, self.theme.font_size, if (on) self.theme.accent else self.theme.text, opts.items[item_idx]);
            const st = self.interact(self.id(opts.items[item_idx]), ir, false);
            if (st.clicked) {
                result = item_idx;
            }
        }

        if (self.input.keyPressed(.enter) and mct > 0) {
            result = matches[self.palette_sel];
        }
        if (result != null) {
            self.palette_open = false;
            self.palette_query_len = 0;
        }
        return result;
    }

    fn containsIgnoreCaseUi(hay: []const u8, needle: []const u8) bool {
        if (needle.len == 0) return true;
        if (needle.len > hay.len) return false;
        var i: usize = 0;
        while (i + needle.len <= hay.len) : (i += 1) {
            var ok = true;
            for (needle, 0..) |nc, j| {
                const hc = hay[i + j];
                const a: u8 = if (nc >= 'A' and nc <= 'Z') nc + 32 else nc;
                const b: u8 = if (hc >= 'A' and hc <= 'Z') hc + 32 else hc;
                if (a != b) {
                    ok = false;
                    break;
                }
            }
            if (ok) return true;
        }
        return false;
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

    /// Collapsible section header. Returns true while expanded (draw children inside).
    pub fn beginCollapsible(self: *Ui, opts: struct { id: []const u8, title: []const u8, open: *bool }) bool {
        const i = self.id(opts.id);
        const r = self.alloc(0, self.theme.row_h);
        const full = Rect{ .x = r.x, .y = r.y, .w = self.top().width - 2 * self.top().pad, .h = self.theme.row_h };
        const st = self.interact(i, full, false);
        if (st.clicked) opts.open.* = !opts.open.*;
        if (st.hot) self.setTooltip(if (opts.open.*) "Click to collapse" else "Click to expand");
        self.drawRect(full, if (st.hot) self.theme.button_hot else self.theme.button);
        const arrow: []const u8 = if (opts.open.*) "v " else "> ";
        self.drawText(full.x + 6, full.y + 6, self.theme.font_size, self.theme.accent, arrow);
        const am = self.font.measure(arrow, self.theme.font_size);
        self.drawText(full.x + 6 + am.w, full.y + 6, self.theme.font_size, self.theme.text, opts.title);
        if (opts.open.*) {
            self.pushId(opts.id);
            self.beginVStack(.{
                .x = full.x,
                .y = full.y + full.h,
                .w = full.w,
                .h = 400,
                .pad = 4,
                .gap = self.theme.gap,
            });
        }
        return opts.open.*;
    }

    pub fn endCollapsible(self: *Ui, open: bool) void {
        if (!open) return;
        _ = self.endVStack();
        self.popId();
    }

    /// Centered modal. While open, dims the background. Esc closes (`open` -> false).
    pub fn beginModal(self: *Ui, opts: struct {
        id: []const u8,
        title: []const u8,
        open: *bool,
        w: f32 = 400,
        h: f32 = 280,
    }) bool {
        if (!opts.open.*) return false;

        // Dim full window.
        self.drawRect(.{ .x = 0, .y = 0, .w = self.width, .h = self.height }, self.theme.overlay);

        if (self.input.keyPressed(.escape)) {
            opts.open.* = false;
            self.consumed_escape = true;
            return false;
        }

        const mw = opts.w;
        const mh = opts.h;
        const mx = (self.width - mw) * 0.5;
        const my = (self.height - mh) * 0.5;
        const r = Rect{ .x = mx, .y = my, .w = mw, .h = mh };
        self.remember(self.id(opts.id), r);
        self.drawRectBorder(r, self.theme.modal, self.theme.accent, 2);

        // Title bar
        const th = self.theme.row_h;
        self.drawRect(.{ .x = r.x, .y = r.y, .w = r.w, .h = th }, .{ 0.12, 0.13, 0.16, 1 });
        self.drawText(r.x + self.theme.pad, r.y + 6, self.theme.title_font_size, self.theme.text, opts.title);

        // Close button
        const cr = Rect{ .x = r.x + r.w - 28, .y = r.y + 4, .w = 22, .h = 20 };
        const ci = self.id("modal_close");
        const cst = self.interact(ci, cr, false);
        self.drawRect(cr, if (cst.hot) self.theme.danger else self.theme.button);
        self.drawText(cr.x + 6, cr.y + 3, self.theme.font_size, self.theme.text, "x");
        if (cst.clicked) {
            opts.open.* = false;
            return false;
        }

        self.pushId(opts.id);
        self.beginVStack(.{
            .x = r.x,
            .y = r.y + th,
            .w = r.w,
            .h = r.h - th,
            .pad = self.theme.pad,
            .gap = self.theme.gap,
        });
        return true;
    }

    pub fn endModal(self: *Ui) void {
        _ = self.endVStack();
        self.popId();
    }

    /// Top menubar strip. Returns height used.
    pub fn beginMenubar(self: *Ui, opts: struct { id: []const u8 = "menubar" }) f32 {
        const h = self.theme.menubar_h;
        const r = Rect{ .x = 0, .y = 0, .w = self.width, .h = h };
        self.drawRect(r, self.theme.menubar);
        self.drawRect(.{ .x = 0, .y = h - 1, .w = self.width, .h = 1 }, self.theme.panel_border);
        self.pushId(opts.id);
        self.beginHStack(.{ .x = 0, .y = 0, .w = self.width, .h = h, .pad = 4, .gap = 2 });
        return h;
    }

    pub fn endMenubar(self: *Ui) void {
        _ = self.endHStack();
        self.popId();
    }

    /// Top-level menubar button that toggles a dropdown. `items` drawn while open.
    /// Returns index of chosen item, or null.
    pub fn menuDropdown(self: *Ui, opts: struct {
        id: []const u8,
        label: []const u8,
        items: []const []const u8,
    }) ?usize {
        const m = self.font.measure(opts.label, self.theme.font_size);
        const r = self.alloc(m.w + 20, self.theme.menubar_h - 6);
        const i = self.idFlat(opts.id);
        const st = self.interact(i, r, false);
        const open = self.menu_open.eq(i);
        if (st.hot or open) self.drawRect(r, self.theme.button_hot);
        self.drawText(r.x + 10, r.y + 4, self.theme.font_size, self.theme.text, opts.label);

        if (st.clicked) {
            if (open) {
                self.menu_open = .{};
            } else {
                self.menu_open = i;
                self.menu_anchor = r;
                self.closeContextMenu();
            }
        }

        if (!self.menu_open.eq(i)) return null;

        // Dropdown panel under the label.
        const item_h = self.theme.row_h - 2;
        const pad: f32 = 4;
        var max_w: f32 = r.w;
        for (opts.items) |it| {
            max_w = @max(max_w, self.font.measure(it, self.theme.font_size).w + 24);
        }
        const menu_h = item_h * @as(f32, @floatFromInt(opts.items.len)) + pad * 2;
        const menu = Rect{ .x = r.x, .y = r.y + r.h + 2, .w = max_w, .h = menu_h };
        self.drawRectBorder(menu, self.theme.modal, self.theme.panel_border, 1);

        var chosen: ?usize = null;
        for (opts.items, 0..) |item, idx| {
            const ir = Rect{
                .x = menu.x + pad,
                .y = menu.y + pad + @as(f32, @floatFromInt(idx)) * item_h,
                .w = max_w - pad * 2,
                .h = item_h,
            };
            var idbuf: [64]u8 = undefined;
            const iname = std.fmt.bufPrint(&idbuf, "menu:{s}:{d}", .{ opts.id, idx }) catch item;
            const iid = self.idFlat(iname);
            const ist = self.interact(iid, ir, false);
            if (ist.hot) self.drawRect(ir, self.theme.button_hot);
            self.drawText(ir.x + 8, ir.y + 5, self.theme.font_size, self.theme.text, item);
            if (ist.clicked) chosen = idx;
        }

        // Click outside closes (not on the menu button itself this frame if just toggled).
        if (self.input.mousePressed(.left)) {
            const on_btn = r.contains(self.input.mouse_x, self.input.mouse_y);
            const on_menu = menu.contains(self.input.mouse_x, self.input.mouse_y);
            if (!on_btn and !on_menu) self.menu_open = .{};
        }
        if (chosen != null) self.menu_open = .{};
        return chosen;
    }

    /// Simple menubar action button (no dropdown) — kept for Help-style actions.
    pub fn menuItem(self: *Ui, opts: struct { id: []const u8, label: []const u8 }) bool {
        const m = self.font.measure(opts.label, self.theme.font_size);
        const r = self.alloc(m.w + 20, self.theme.menubar_h - 6);
        const i = self.id(opts.id);
        const st = self.interact(i, r, false);
        if (st.hot) self.drawRect(r, self.theme.button_hot);
        self.drawText(r.x + 10, r.y + 4, self.theme.font_size, self.theme.text, opts.label);
        return st.clicked;
    }

    /// Bottom status bar.
    pub fn statusBar(self: *Ui, left: []const u8, right: []const u8) void {
        const h = self.theme.statusbar_h;
        const r = Rect{ .x = 0, .y = self.height - h, .w = self.width, .h = h };
        self.drawRect(r, self.theme.statusbar);
        self.drawRect(.{ .x = 0, .y = r.y, .w = self.width, .h = 1 }, self.theme.panel_border);
        self.drawText(r.x + 8, r.y + 5, self.theme.font_size, self.theme.text_dim, left);
        const rm = self.font.measure(right, self.theme.font_size);
        self.drawText(r.x + r.w - rm.w - 8, r.y + 5, self.theme.font_size, self.theme.text_dim, right);
    }

    /// Simple list row selector.
    pub fn listBox(self: *Ui, opts: struct {
        id: []const u8,
        items: []const []const u8,
        selected: *usize,
        w: f32 = 200,
        h: f32 = 160,
    }) bool {
        const i = self.id(opts.id);
        const r = self.alloc(opts.w, opts.h);
        self.remember(i, r);
        self.drawRectBorder(r, self.theme.input_bg, self.theme.panel_border, 1);
        var changed = false;
        const item_h = self.theme.row_h - 4;
        self.pushId(opts.id);
        defer self.popId();
        self.cmds.push(.{ .scissor_push = .{ .x = r.x + 1, .y = r.y + 1, .w = r.w - 2, .h = r.h - 2 } });
        for (opts.items, 0..) |item, idx| {
            const ir = Rect{
                .x = r.x + 2,
                .y = r.y + 2 + @as(f32, @floatFromInt(idx)) * item_h,
                .w = r.w - 4,
                .h = item_h,
            };
            const iid = self.id(item);
            const st = self.interact(iid, ir, false);
            const on = opts.selected.* == idx;
            if (on or st.hot) {
                self.drawRect(ir, if (on) self.theme.selected else self.theme.button_hot);
            }
            self.drawText(ir.x + 6, ir.y + 5, self.theme.font_size, self.theme.text, item);
            if (st.clicked) {
                opts.selected.* = idx;
                changed = true;
            }
        }
        self.cmds.push(.{ .scissor_pop = {} });
        return changed;
    }

    /// Color swatch button (shows color; returns true on click).
    pub fn colorSwatch(self: *Ui, opts: struct { id: []const u8, color: Color, selected: bool = false, w: f32 = 28 }) bool {
        const r = self.alloc(opts.w, opts.w);
        const i = self.id(opts.id);
        const st = self.interact(i, r, false);
        const border: Color = if (opts.selected or st.hot) self.theme.accent else self.theme.panel_border;
        self.drawRectBorder(r, opts.color, border, if (opts.selected) 2 else 1);
        return st.clicked;
    }

    /// Number spinner (float) with − / + buttons.
    pub fn spinner(self: *Ui, opts: struct {
        id: []const u8,
        label: []const u8,
        value: *f32,
        min: f32 = 0,
        max: f32 = 100,
        step: f32 = 1,
        w: f32 = 160,
    }) bool {
        const size = self.theme.font_size;
        const r = self.alloc(opts.w, self.theme.row_h + 12);
        self.drawText(r.x, r.y, size, self.theme.text_dim, opts.label);
        const row_y = r.y + 12;
        const bh = self.theme.button_h - 4;
        const bw: f32 = 28;
        var changed = false;

        self.pushId(opts.id);
        defer self.popId();

        const minus_r = Rect{ .x = r.x, .y = row_y, .w = bw, .h = bh };
        const plus_r = Rect{ .x = r.x + opts.w - bw, .y = row_y, .w = bw, .h = bh };
        const mid = Rect{ .x = r.x + bw + 4, .y = row_y, .w = opts.w - 2 * bw - 8, .h = bh };

        const mi = self.id("minus");
        const pi = self.id("plus");
        const mst = self.interact(mi, minus_r, false);
        const pst = self.interact(pi, plus_r, false);
        self.drawRectBorder(minus_r, if (mst.hot) self.theme.button_hot else self.theme.button, self.theme.panel_border, 1);
        self.drawRectBorder(plus_r, if (pst.hot) self.theme.button_hot else self.theme.button, self.theme.panel_border, 1);
        self.drawText(minus_r.x + 10, minus_r.y + 5, size, self.theme.text, "-");
        self.drawText(plus_r.x + 10, plus_r.y + 5, size, self.theme.text, "+");
        self.drawRectBorder(mid, self.theme.input_bg, self.theme.panel_border, 1);

        if (mst.clicked) {
            opts.value.* = @max(opts.min, opts.value.* - opts.step);
            changed = true;
        }
        if (pst.clicked) {
            opts.value.* = @min(opts.max, opts.value.* + opts.step);
            changed = true;
        }

        var buf: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d:.2}", .{opts.value.*}) catch "?";
        const sm = self.font.measure(s, size);
        self.drawText(mid.x + (mid.w - sm.w) * 0.5, mid.y + 5, size, self.theme.text, s);
        return changed;
    }

    /// Horizontal form row: fixed-width label column + remaining content width.
    /// Opens a nested hstack; call `endFormRow` after the control.
    pub fn beginFormRow(self: *Ui, opts: struct { label: []const u8, label_w: f32 = 90 }) void {
        const row_h = self.theme.row_h + 4;
        const full_w = self.top().width - 2 * self.top().pad;
        // Reserve vertical space then open hstack for the row.
        const r = self.alloc(full_w, row_h);
        self.beginHStack(.{ .x = r.x, .y = r.y, .w = full_w, .h = row_h, .pad = 0, .gap = 8 });
        const lm = self.font.measure(opts.label, self.theme.font_size);
        // Label cell (not interactive).
        const lr = self.alloc(opts.label_w, row_h);
        self.drawText(lr.x, lr.y + (row_h - lm.h) * 0.5, self.theme.font_size, self.theme.text_dim, opts.label);
    }

    pub fn endFormRow(self: *Ui) void {
        _ = self.endHStack();
    }

    /// Vertical splitter handle. Updates `width` while dragged (left pane width).
    pub fn vSplitter(self: *Ui, opts: struct {
        id: []const u8,
        x: f32,
        y: f32,
        h: f32,
        width: *f32,
        min: f32 = 140,
        max: f32 = 480,
    }) void {
        const i = self.id(opts.id);
        const handle_w: f32 = 5;
        const r = Rect{ .x = opts.x + opts.width.* - handle_w * 0.5, .y = opts.y, .w = handle_w, .h = opts.h };
        self.remember(i, r);
        const over = r.contains(self.input.mouse_x, self.input.mouse_y);
        if (over) {
            self.any_hot = true;
            self.hot = i;
            self.setTooltip("Drag to resize");
        }
        if (over and self.input.mousePressed(.left)) {
            self.drag = i;
            self.drag_anchor = self.input.mouse_x;
            self.drag_value0 = opts.width.*;
        }
        if (self.drag.eq(i) and self.input.mouseDown(.left)) {
            const dx = self.input.mouse_x - self.drag_anchor;
            opts.width.* = std.math.clamp(self.drag_value0 + dx, opts.min, opts.max);
        }
        const fill: Color = if (self.drag.eq(i) or self.hot.eq(i)) self.theme.accent else self.theme.panel_border;
        self.drawRect(r, fill);
    }

    /// Open a context menu at the cursor (typically on right-click).
    /// `owner` is matched with idFlat (ignores layout id stack).
    pub fn openContextMenu(self: *Ui, owner: []const u8) void {
        self.ctx_open = true;
        self.ctx_x = self.input.mouse_x;
        self.ctx_y = self.input.mouse_y;
        self.ctx_owner = self.idFlat(owner);
        self.ctx_just_opened = true;
        self.menu_open = .{}; // close any menubar dropdown
    }

    pub fn closeContextMenu(self: *Ui) void {
        self.ctx_open = false;
        self.ctx_owner = .{};
        self.ctx_just_opened = false;
    }

    /// Draw/context-handle an open context menu. Returns clicked item index, or null.
    pub fn contextMenu(self: *Ui, opts: struct {
        owner: []const u8,
        items: []const []const u8,
    }) ?usize {
        if (!self.ctx_open) return null;
        if (!self.ctx_owner.eq(self.idFlat(opts.owner))) return null;

        if (self.input.keyPressed(.escape)) {
            self.closeContextMenu();
            self.consumed_escape = true;
            return null;
        }

        const item_h = self.theme.row_h - 2;
        const pad: f32 = 4;
        var max_w: f32 = 80;
        for (opts.items) |it| {
            max_w = @max(max_w, self.font.measure(it, self.theme.font_size).w + 24);
        }
        const menu_h = item_h * @as(f32, @floatFromInt(opts.items.len)) + pad * 2;
        var mx = self.ctx_x;
        var my = self.ctx_y;
        if (mx + max_w > self.width) mx = self.width - max_w - 4;
        if (my + menu_h > self.height) my = self.height - menu_h - 4;

        const menu = Rect{ .x = mx, .y = my, .w = max_w, .h = menu_h };
        self.drawRectBorder(menu, self.theme.modal, self.theme.panel_border, 1);

        var clicked: ?usize = null;
        for (opts.items, 0..) |item, idx| {
            const ir = Rect{
                .x = menu.x + pad,
                .y = menu.y + pad + @as(f32, @floatFromInt(idx)) * item_h,
                .w = max_w - pad * 2,
                .h = item_h,
            };
            // Flat ids so they don't collide with layout stack.
            var idbuf: [64]u8 = undefined;
            const iname = std.fmt.bufPrint(&idbuf, "ctx:{s}:{d}", .{ opts.owner, idx }) catch item;
            const iid = self.idFlat(iname);
            const st = self.interact(iid, ir, false);
            if (st.hot) self.drawRect(ir, self.theme.button_hot);
            self.drawText(ir.x + 8, ir.y + 5, self.theme.font_size, self.theme.text, item);
            if (st.clicked) clicked = idx;
        }

        // Click outside closes — but not on the opening right-click frame.
        if (!self.ctx_just_opened) {
            if (self.input.mousePressed(.left) or self.input.mousePressed(.right)) {
                if (!menu.contains(self.input.mouse_x, self.input.mouse_y)) {
                    self.closeContextMenu();
                    return null;
                }
            }
        }
        self.ctx_just_opened = false;
        if (clicked != null) self.closeContextMenu();
        return clicked;
    }

    /// Right-clickable region helper: if right-pressed over `r`, opens context menu.
    pub fn rightClickOpen(self: *Ui, owner: []const u8, r: Rect) bool {
        if (self.input.mousePressed(.right) and r.contains(self.input.mouse_x, self.input.mouse_y)) {
            self.openContextMenu(owner);
            return true;
        }
        return false;
    }

    /// Search/filter field (single-line text, no separate label).
    pub fn searchField(self: *Ui, opts: struct {
        id: []const u8,
        buf: []u8,
        len: *usize,
        placeholder: []const u8 = "Search…",
        w: f32 = 200,
    }) bool {
        const i = self.id(opts.id);
        const r = self.alloc(opts.w, self.theme.row_h);
        const st = self.interact(i, r, false);
        if (st.clicked) self.focus = i;
        const focused = self.focus.eq(i);
        self.drawRectBorder(r, self.theme.input_bg, if (focused) self.theme.accent else self.theme.panel_border, 1);

        var changed = false;
        if (focused) {
            changed = self.appendFocusedText(opts.buf, opts.len) or changed;
            if (self.input.keyPressed(.backspace) and opts.len.* > 0) {
                opts.len.* -= 1;
                changed = true;
            }
        }
        if (opts.len.* == 0 and !focused) {
            self.drawText(r.x + 6, r.y + 6, self.theme.font_size, self.theme.text_dim, opts.placeholder);
        } else {
            self.drawText(r.x + 6, r.y + 6, self.theme.font_size, self.theme.text, opts.buf[0..opts.len.*]);
        }
        return changed;
    }

    /// List box with optional keyboard navigation when hovered/selected.
    pub fn listBoxNav(self: *Ui, opts: struct {
        id: []const u8,
        items: []const []const u8,
        selected: *usize,
        w: f32 = 200,
        h: f32 = 160,
    }) bool {
        var changed = self.listBox(.{
            .id = opts.id,
            .items = opts.items,
            .selected = opts.selected,
            .w = opts.w,
            .h = opts.h,
        });
        // Keyboard when list region is hot or has selection focus via hover.
        const i = self.id(opts.id);
        const r = self.prevRect(i) orelse return changed;
        if (r.contains(self.input.mouse_x, self.input.mouse_y) or self.hot.eq(i)) {
            if (opts.items.len > 0) {
                if (self.input.keyPressed(.down)) {
                    opts.selected.* = @min(opts.selected.* + 1, opts.items.len - 1);
                    changed = true;
                }
                if (self.input.keyPressed(.up)) {
                    if (opts.selected.* > 0) opts.selected.* -= 1;
                    changed = true;
                }
            }
        }
        return changed;
    }

    /// Simple selectable tree node (indent + expand arrow + label).
    pub fn treeNode(self: *Ui, opts: struct {
        id: []const u8,
        label: []const u8,
        open: ?*bool = null,
        selected: bool = false,
        depth: u32 = 0,
    }) struct { clicked: bool, toggled: bool } {
        const i = self.id(opts.id);
        const indent: f32 = @as(f32, @floatFromInt(opts.depth)) * 14;
        const r = self.alloc(0, self.theme.row_h - 2);
        const full = Rect{
            .x = r.x,
            .y = r.y,
            .w = self.top().width - 2 * self.top().pad,
            .h = self.theme.row_h - 2,
        };
        const st = self.interact(i, full, false);
        if (st.hot or opts.selected) {
            self.drawRect(full, if (opts.selected) self.theme.selected else self.theme.button_hot);
        }
        var toggled = false;
        var x = full.x + 4 + indent;
        if (opts.open) |op| {
            const arrow: []const u8 = if (op.*) "v" else ">";
            self.drawText(x, full.y + 5, self.theme.font_size, self.theme.accent, arrow);
            if (st.clicked and self.input.mouse_x < x + 18) {
                op.* = !op.*;
                toggled = true;
            }
            x += 16;
        }
        self.drawText(x, full.y + 5, self.theme.font_size, self.theme.text, opts.label);
        const clicked = st.clicked and !toggled;
        return .{ .clicked = clicked, .toggled = toggled };
    }
};
