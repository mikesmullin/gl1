//! Immediate-mode UI (Style A: begin/end + defer).
//! Inspired by Game9 UI__Clickable hot/active FSM; Clay not used as a dependency.

const std = @import("std");
const input_mod = @import("../input.zig");
const font_mod = @import("../font.zig");
const theme_mod = @import("theme.zig");
const draw = @import("../draw.zig");
const te = @import("text_edit.zig");
const types = @import("types.zig");
const components = @import("components/root.zig");

pub const Theme = theme_mod.Theme;
pub const Color = types.Color;
pub const Input = input_mod.Input;
pub const Font = font_mod.Font;
pub const TextEdit = te.Edit;
pub const Id = types.Id;
pub const Rect = types.Rect;

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
    /// Drawn after `cmds` so menus/overlays sit above panels.
    front: draw.List = .{},

    /// Persistent text-edit state keyed by widget id hash.
    edits: std.AutoHashMap(u64, te.Edit) = undefined,

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
    /// Wheel already claimed this frame (stop bubbling to lower widgets/scene).
    scroll_eaten: bool = false,

    /// Active drag (splitter, Blender-style slider, etc.).
    drag: Id = .{},
    drag_anchor: f32 = 0,
    drag_value0: f32 = 0,
    /// True while a widget has hidden/locked the mouse for relative drag.
    mouse_captured_for_drag: bool = false,

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

    /// Command palette (Ctrl+P).
    palette_open: bool = false,
    palette_query: [64]u8 = undefined,
    palette_query_len: usize = 0,
    palette_sel: usize = 0,
    palette_scroll: usize = 0,

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
        self.edits = std.AutoHashMap(u64, te.Edit).init(allocator);
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
        self.edits.deinit();
        self.inited = false;
    }

    pub fn editState(self: *Ui, key: u64) *te.Edit {
        const gop = self.edits.getOrPut(key) catch {
            // fallback static — shouldn't happen
            unreachable;
        };
        if (!gop.found_existing) gop.value_ptr.* = .{};
        return gop.value_ptr;
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
        self.front.clear();
        self.tooltip_set = false;
        self.tooltip_len = 0;
        self.consumed_escape = false;
        self.scroll_eaten = false;
        // Clear drag when mouse released; restore cursor if a slider captured it.
        if (!input.mouseDown(.left) and !self.drag.isNone()) {
            self.drag = .{};
            if (self.mouse_captured_for_drag) {
                self.mouse_captured_for_drag = false;
                const sapp = @import("sokol").app;
                sapp.lockMouse(false);
                sapp.showMouse(true);
            }
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

        // Tooltip / toasts on the front layer (above panels).
        if (self.tooltip_set and self.tooltip_len > 0) {
            const msg = self.tooltip_text[0..self.tooltip_len];
            const m = self.font.measure(msg, self.theme.font_size);
            const pad: f32 = 6;
            var tx = self.input.mouse_x + 14;
            var ty = self.input.mouse_y + 16;
            if (tx + m.w + pad * 2 > self.width) tx = self.width - m.w - pad * 2;
            if (ty + m.h + pad * 2 > self.height) ty = self.input.mouse_y - m.h - pad * 2 - 8;
            const tr = Rect{ .x = tx, .y = ty, .w = m.w + pad * 2, .h = m.h + pad * 2 };
            self.drawRectBorderFront(tr, self.theme.tooltip_bg, self.theme.panel_border, 1);
            self.drawTextFront(tr.x + pad, tr.y + pad, self.theme.font_size, self.theme.text, msg);
        }

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
                self.drawRectBorderFront(tr, self.theme.toast_bg, accent, 2);
                self.drawTextFront(tr.x + pad, tr.y + pad, self.theme.font_size, self.theme.text, msg);
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

    pub fn remember(self: *Ui, i: Id, r: Rect) void {
        if (self.curr_count < MaxPrev) {
            self.curr_rects[self.curr_count] = .{ .id = i, .r = r };
            self.curr_count += 1;
        }
    }

    pub fn prevRect(self: *const Ui, i: Id) ?Rect {
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

    pub fn top(self: *Ui) *LayoutNode {
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

    // --- Wheel / scroll capture ---------------------------------------------

    /// Remaining wheel delta for *content* this frame.
    /// Returns 0 if already eaten, or if the command palette is open (overlay
    /// owns the wheel until it calls `eatScroll`).
    pub fn wheelY(self: *const Ui) f32 {
        if (self.scroll_eaten) return 0;
        if (self.palette_open) return 0;
        return self.input.scroll_y;
    }

    /// Wheel delta for overlay chrome (command palette). Ignores the
    /// palette_open content block so the palette can still scroll.
    pub fn wheelYOverlay(self: *const Ui) f32 {
        if (self.scroll_eaten) return 0;
        return self.input.scroll_y;
    }

    /// Stop the wheel from bubbling to anything else this frame.
    pub fn eatScroll(self: *Ui) void {
        self.scroll_eaten = true;
        self.input.scroll_y = 0;
    }

    // --- Drawing primitives (queue → RenderCommand list) --------------------

    pub fn drawRect(self: *Ui, r: Rect, color: Color) void {
        self.cmds.rect(.{ .x = r.x, .y = r.y, .w = r.w, .h = r.h }, color);
    }

    pub fn drawRectFront(self: *Ui, r: Rect, color: Color) void {
        self.front.rect(.{ .x = r.x, .y = r.y, .w = r.w, .h = r.h }, color);
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

    pub fn drawRectBorderFront(self: *Ui, r: Rect, fill: Color, border: Color, thickness: f32) void {
        self.drawRectFront(r, border);
        const inner = Rect{
            .x = r.x + thickness,
            .y = r.y + thickness,
            .w = @max(0, r.w - 2 * thickness),
            .h = @max(0, r.h - 2 * thickness),
        };
        self.drawRectFront(inner, fill);
    }

    pub fn drawText(self: *Ui, x: f32, y: f32, size: f32, color: Color, text: []const u8) void {
        self.cmds.text(x, y, size, color, text);
    }

    pub fn drawTextFront(self: *Ui, x: f32, y: f32, size: f32, color: Color, text: []const u8) void {
        self.front.text(x, y, size, color, text);
    }

    pub fn flushDraw(self: *Ui) void {
        self.cmds.flushSgl(self.font);
        self.front.flushSgl(self.font);
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
        // Always scissor panel body so labels/buttons cannot paint past the border
        // (fixes “Zig defer.” overflow). Nested text-field scissors restore parent.
        if (opts.scroll) {
            const gop = self.scroll_y.getOrPut(i.a) catch null;
            if (gop) |g| {
                if (!g.found_existing) g.value_ptr.* = 0;
                const dy = self.wheelY();
                if (dy != 0 and body.contains(self.input.mouse_x, self.input.mouse_y)) {
                    g.value_ptr.* -= dy * 28;
                    if (g.value_ptr.* < 0) g.value_ptr.* = 0;
                    if (g.value_ptr.* > 4000) g.value_ptr.* = 4000;
                    self.eatScroll();
                }
                scroll_off = g.value_ptr.*;
            }
        }
        self.cmds.push(.{ .scissor_push = .{
            .x = body.x + 1,
            .y = body.y + 1,
            .w = @max(0, body.w - 2),
            .h = @max(0, body.h - 2),
        } });

        self.pushId(opts.id);
        if (self.panel_scroll_depth < self.panel_scroll_stack.len) {
            // Always true: endPanel always pops one scissor.
            self.panel_scroll_stack[self.panel_scroll_depth] = true;
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
        components.spacer.spacer(self, h);
    }

    pub fn label(self: *Ui, opts: struct { text: []const u8, color: ?Color = null, size: ?f32 = null }) void {
        components.label.label(self, opts);
    }

    pub fn button(self: *Ui, opts: struct {
        id: []const u8,
        label: []const u8,
        w: f32 = 0,
        disabled: bool = false,
    }) bool {
        return components.button.button(self, opts);
    }

    pub fn radio(self: *Ui, opts: struct { id: []const u8, label: []const u8, group: *u32, value: u32 }) bool {
        return components.radio.radio(self, opts);
    }

    pub fn checkbox(self: *Ui, opts: struct { id: []const u8, label: []const u8, value: *bool }) bool {
        return components.checkbox.checkbox(self, opts);
    }

    pub fn slider(self: *Ui, opts: struct {
        id: []const u8,
        label: []const u8,
        value: *f32,
        min: f32 = 0,
        max: f32 = 1,
        w: f32 = 200,
    }) bool {
        return components.slider.slider(self, opts);
    }

    pub fn textInput(self: *Ui, opts: struct {
        id: []const u8,
        label: []const u8,
        buf: []u8,
        len: *usize,
        w: f32 = 220,
    }) bool {
        return components.textInput.textInput(self, opts);
    }

    /// Multi-line text area.
    /// - `rows`: default height in text rows (like HTML textarea rows=N)
    /// - `min_height`: pixel min (supersedes rows when set > 0)
    /// - `max_height`: pixel max; overflow scrolls inside
    pub fn textArea(self: *Ui, opts: struct {
        id: []const u8,
        label: []const u8,
        buf: []u8,
        len: *usize,
        w: f32 = 280,
        rows: u32 = 3,
        min_height: f32 = 0,
        max_height: f32 = 0,
        h: f32 = 0, // legacy explicit height; if >0 used as min
    }) bool {
        return components.textArea.textArea(self, opts);
    }

    fn textFieldCore(self: *Ui, opts: struct {
        id_key: u64,
        box: Rect,
        buf: []u8,
        len: *usize,
        multiline: bool,
        size: f32,
        scroll_y: f32 = 0,
    }) bool {
        return components.textFieldCore.textFieldCore(self, opts);
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

        self.drawRectFront(.{ .x = 0, .y = 0, .w = self.width, .h = self.height }, self.theme.overlay);

        if (self.input.keyPressed(.escape)) {
            self.palette_open = false;
            self.consumed_escape = true;
            return null;
        }

        const pw: f32 = @min(520, self.width - 40);
        const max_vis: usize = 10;
        const row_h = self.theme.row_h;
        var q = self.palette_query[0..self.palette_query_len];
        // Typing into query — consume so fields never see the chars.
        if (self.input.text_len > 0) {
            const avail = self.palette_query.len - self.palette_query_len;
            const n = @min(avail, self.input.text_len);
            @memcpy(self.palette_query[self.palette_query_len .. self.palette_query_len + n], self.input.text[0..n]);
            self.palette_query_len += n;
            self.palette_sel = 0;
            self.palette_scroll = 0;
            self.input.text_len = 0;
            q = self.palette_query[0..self.palette_query_len];
        }
        if (self.input.keyPressed(.backspace) and self.palette_query_len > 0) {
            self.palette_query_len -= 1;
            self.palette_sel = 0;
            self.palette_scroll = 0;
            q = self.palette_query[0..self.palette_query_len];
        }

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

        // Layout: fixed chrome + fixed list viewport (always max_vis rows tall when
        // there are matches) so the box does not grow/shrink with partial last page
        // and the list never paints past the border.
        const pad: f32 = 12;
        const title_h: f32 = 22;
        const gap: f32 = 8;
        const list_viewport_h = @as(f32, @floatFromInt(max_vis)) * row_h;
        const chrome_h = pad + title_h + gap + row_h + gap; // title + query + gaps
        const bottom_pad: f32 = pad;

        if (mct == 0) {
            const ph_empty = chrome_h + row_h + bottom_pad;
            const box = Rect{ .x = (self.width - pw) * 0.5, .y = self.height * 0.18, .w = pw, .h = ph_empty };
            self.drawRectBorderFront(box, self.theme.modal, self.theme.accent, 2);
            self.drawTextFront(box.x + pad, box.y + pad, self.theme.title_font_size, self.theme.text_dim, "Command palette  (Ctrl+P)");
            const qbox = Rect{ .x = box.x + pad, .y = box.y + pad + title_h + gap, .w = pw - pad * 2, .h = row_h };
            self.drawRectBorderFront(qbox, self.theme.input_bg, self.theme.accent, 1);
            if (q.len == 0)
                self.drawTextFront(qbox.x + 8, qbox.y + 6, self.theme.font_size, self.theme.text_dim, "Type to filter… e.g. scene")
            else
                self.drawTextFront(qbox.x + 8, qbox.y + 6, self.theme.font_size, self.theme.text, q);
            self.drawTextFront(box.x + pad, qbox.y + row_h + gap, self.theme.font_size, self.theme.text_dim, "No matches");
            return null;
        }

        if (self.palette_sel >= mct) self.palette_sel = mct - 1;

        // Keyboard: move selection; scroll only follows when keys move sel.
        var keyboard_nav = false;
        if (self.input.keyPressed(.down)) {
            self.palette_sel = @min(self.palette_sel + 1, mct - 1);
            keyboard_nav = true;
        }
        if (self.input.keyPressed(.up) and self.palette_sel > 0) {
            self.palette_sel -= 1;
            keyboard_nav = true;
        }

        const max_scroll = if (mct > max_vis) mct - max_vis else 0;
        const ph = chrome_h + list_viewport_h + bottom_pad;
        const box = Rect{ .x = (self.width - pw) * 0.5, .y = self.height * 0.18, .w = pw, .h = ph };
        const qbox = Rect{ .x = box.x + pad, .y = box.y + pad + title_h + gap, .w = pw - pad * 2, .h = row_h };
        const list_y = qbox.y + row_h + gap;
        const list_r = Rect{ .x = box.x + pad, .y = list_y, .w = pw - pad * 2, .h = list_viewport_h };

        // Wheel: scroll the list only — does not change selection. Content under
        // the palette already sees wheelY()==0; we still eatScroll so nothing
        // later in the frame can use residual wheel.
        const dy = self.wheelYOverlay();
        if (dy != 0) {
            if (box.contains(self.input.mouse_x, self.input.mouse_y)) {
                const steps_f = @abs(dy);
                var steps: usize = @intFromFloat(@floor(steps_f));
                if (steps == 0) steps = 1;
                var s: usize = 0;
                while (s < steps) : (s += 1) {
                    if (dy > 0) {
                        if (self.palette_scroll > 0) self.palette_scroll -= 1;
                    } else {
                        if (self.palette_scroll < max_scroll) self.palette_scroll += 1;
                    }
                }
            }
            self.eatScroll();
        }

        // Only keyboard nav forces the selection into the viewport (so arrowing
        // below the fold still works). Wheel leaves selection alone.
        if (keyboard_nav) {
            if (self.palette_sel < self.palette_scroll) self.palette_scroll = self.palette_sel;
            if (self.palette_sel >= self.palette_scroll + max_vis)
                self.palette_scroll = self.palette_sel + 1 - max_vis;
        }
        if (self.palette_scroll > max_scroll) self.palette_scroll = max_scroll;

        const vis = @min(mct - self.palette_scroll, max_vis);

        self.drawRectBorderFront(box, self.theme.modal, self.theme.accent, 2);
        self.drawTextFront(box.x + pad, box.y + pad, self.theme.title_font_size, self.theme.text_dim, "Command palette  (Ctrl+P)");
        self.drawRectBorderFront(qbox, self.theme.input_bg, self.theme.accent, 1);
        if (q.len == 0)
            self.drawTextFront(qbox.x + 8, qbox.y + 6, self.theme.font_size, self.theme.text_dim, "Type to filter… e.g. scene")
        else
            self.drawTextFront(qbox.x + 8, qbox.y + 6, self.theme.font_size, self.theme.text, q);

        // Clip list rows to the viewport.
        self.front.push(.{ .scissor_push = .{
            .x = list_r.x,
            .y = list_r.y,
            .w = list_r.w,
            .h = list_r.h,
        } });

        var result: ?usize = null;
        var vi: usize = 0;
        while (vi < vis) : (vi += 1) {
            const match_i = self.palette_scroll + vi;
            const item_idx = matches[match_i];
            const ir = Rect{
                .x = list_r.x,
                .y = list_y + @as(f32, @floatFromInt(vi)) * row_h,
                .w = list_r.w - 8, // leave room for scrollbar
                .h = row_h,
            };
            // Hover selects only while the mouse is *moving* so arrow keys still
            // work when the cursor rests over a row.
            const mouse_moved = @abs(self.input.mouse_dx) > 0.5 or @abs(self.input.mouse_dy) > 0.5;
            if (mouse_moved and ir.contains(self.input.mouse_x, self.input.mouse_y)) {
                self.palette_sel = match_i;
            }
            const on = match_i == self.palette_sel;
            if (on) self.drawRectFront(ir, self.theme.selected);
            self.drawTextFront(ir.x + 8, ir.y + 6, self.theme.font_size, if (on) self.theme.accent else self.theme.text, opts.items[item_idx]);
            if (self.interact(self.idFlat(opts.items[item_idx]), ir, false).clicked) result = item_idx;
        }
        self.front.push(.{ .scissor_pop = {} });

        if (max_scroll > 0) {
            const track = Rect{ .x = box.x + pw - pad - 4, .y = list_y, .w = 4, .h = list_viewport_h };
            self.drawRectFront(track, self.theme.slider_track);
            // Thumb size reflects viewport vs total list; position tracks scroll.
            const thumb_h = @max(12, list_viewport_h * @as(f32, @floatFromInt(max_vis)) / @as(f32, @floatFromInt(mct)));
            const thumb_t = list_y + (list_viewport_h - thumb_h) * (@as(f32, @floatFromInt(self.palette_scroll)) / @as(f32, @floatFromInt(max_scroll)));
            self.drawRectFront(.{ .x = track.x, .y = thumb_t, .w = 4, .h = thumb_h }, self.theme.accent);
        }

        if (self.input.keyPressed(.enter) and mct > 0) result = matches[self.palette_sel];
        if (result != null) {
            self.palette_open = false;
            self.palette_query_len = 0;
            self.palette_scroll = 0;
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
        components.progress.progress(self, opts);
    }

    pub fn separator(self: *Ui) void {
        components.separator.separator(self);
    }

    /// Scrollable region with GPU scissor clip + wheel scroll when hovered.
    pub fn beginScroll(self: *Ui, opts: struct { id: []const u8, x: f32, y: f32, w: f32, h: f32 }) f32 {
        const i = self.id(opts.id);
        const r = self.place(opts.x, opts.y, opts.w, opts.h);
        self.remember(i, r);
        self.drawRectBorder(r, self.theme.panel, self.theme.panel_border, 1);
        const gop = self.scroll_y.getOrPut(i.a) catch return 0;
        if (!gop.found_existing) gop.value_ptr.* = 0;
        const dy = self.wheelY();
        if (dy != 0 and r.contains(self.input.mouse_x, self.input.mouse_y)) {
            gop.value_ptr.* -= dy * 24;
            if (gop.value_ptr.* < 0) gop.value_ptr.* = 0;
            self.eatScroll();
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
        return components.toggle.toggle(self, opts);
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
        return components.dropdown.dropdown(self, opts);
    }

    /// Horizontal tab bar. Returns true if selection changed.
    pub fn tabs(self: *Ui, opts: struct {
        id: []const u8,
        items: []const []const u8,
        selected: *usize,
        w: f32 = 0,
    }) bool {
        return components.tabs.tabs(self, opts);
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

        // Dropdown on the front layer so it paints above panels.
        const item_h = self.theme.row_h - 2;
        const pad: f32 = 4;
        var max_w: f32 = r.w;
        for (opts.items) |it| {
            max_w = @max(max_w, self.font.measure(it, self.theme.font_size).w + 24);
        }
        const menu_h = item_h * @as(f32, @floatFromInt(opts.items.len)) + pad * 2;
        const menu = Rect{ .x = r.x, .y = r.y + r.h + 2, .w = max_w, .h = menu_h };
        self.drawRectBorderFront(menu, self.theme.modal, self.theme.panel_border, 1);

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
            if (ist.hot) self.drawRectFront(ir, self.theme.button_hot);
            self.drawTextFront(ir.x + 8, ir.y + 5, self.theme.font_size, self.theme.text, item);
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
        return components.listBox.listBox(self, opts);
    }

    /// Color swatch button (shows color; returns true on click).
    pub fn colorSwatch(self: *Ui, opts: struct { id: []const u8, color: Color, selected: bool = false, w: f32 = 28 }) bool {
        return components.colorSwatch.colorSwatch(self, opts);
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
        self.drawRectBorderFront(menu, self.theme.modal, self.theme.panel_border, 1);

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
            if (st.hot) self.drawRectFront(ir, self.theme.button_hot);
            self.drawTextFront(ir.x + 8, ir.y + 5, self.theme.font_size, self.theme.text, item);
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
        return components.searchField.searchField(self, opts);
    }

    /// List box with optional keyboard navigation when hovered/selected.
    pub fn listBoxNav(self: *Ui, opts: struct {
        id: []const u8,
        items: []const []const u8,
        selected: *usize,
        w: f32 = 200,
        h: f32 = 160,
    }) bool {
        return components.listBoxNav.listBoxNav(self, opts);
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
