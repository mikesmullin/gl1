//! Minimal virtual DOM for the embedded browser.
const std = @import("std");

pub const Display = enum { block, inline_, none, flex, table, table_row, table_cell };
pub const FlexDir = enum { row, column };
pub const Justify = enum { flex_start, center, space_between, flex_end };
pub const AlignItems = enum { stretch, center, flex_start, flex_end };
pub const TextAlign = enum { left, center, right };
pub const Overflow = enum { visible, hidden, auto_ };

pub const Color = [4]f32;

pub const ComputedStyle = struct {
    display: Display = .block,
    width: ?f32 = null, // px
    height: ?f32 = null,
    width_pct: ?f32 = null,
    height_pct: ?f32 = null,
    margin: [4]f32 = .{ 0, 0, 0, 0 }, // t r b l
    padding: [4]f32 = .{ 0, 0, 0, 0 },
    border_w: f32 = 0,
    border_color: Color = .{ 0.7, 0.7, 0.7, 1 },
    /// Default white — bitmap glyphs read better on dark chrome than black.
    color: Color = .{ 1, 1, 1, 1 },
    bg: ?Color = null,
    font_size: f32 = 13,
    font_weight: f32 = 400,
    text_align: TextAlign = .left,
    line_height: f32 = 1.35,
    flex_dir: FlexDir = .row,
    justify: Justify = .flex_start,
    align_items: AlignItems = .stretch,
    gap: f32 = 0,
    flex_grow: f32 = 0,
    overflow: Overflow = .visible,
};

pub const Box = struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,
};

pub const NodeKind = enum { document, element, text };

pub const Node = struct {
    kind: NodeKind,
    /// Tag name (lowercased) for elements; empty for text/document.
    tag: []const u8 = "",
    /// Text content for text nodes; title text etc.
    text: []const u8 = "",
    /// Attribute key/value pairs (arena-owned slices).
    attrs: []const Attr = &.{},
    children: std.ArrayListUnmanaged(*Node) = .empty,
    style: ComputedStyle = .{},
    /// Inline style attribute raw (before cascade).
    style_attr: []const u8 = "",
    class_attr: []const u8 = "",
    id_attr: []const u8 = "",
    box: Box = .{},
    /// Intrinsic image size once known.
    intrinsic_w: f32 = 0,
    intrinsic_h: f32 = 0,
    /// 1-based index when this is an `li` inside `ul`/`ol` (0 = not a list item).
    list_index: u32 = 0,
    /// True when parent list is `ol` (paint decimal marker).
    list_ordered: bool = false,

    pub fn attr(self: *const Node, name: []const u8) ?[]const u8 {
        for (self.attrs) |a| {
            if (std.mem.eql(u8, a.key, name)) return a.val;
        }
        return null;
    }
};

pub const Attr = struct {
    key: []const u8,
    val: []const u8,
};

pub const StylesheetRule = struct {
    /// Simple selector: tag, .class, #id, or tag.class
    sel_tag: []const u8 = "",
    sel_class: []const u8 = "",
    sel_id: []const u8 = "",
    decls: []const u8 = "",
};

pub const Document = struct {
    arena: std.heap.ArenaAllocator,
    root: *Node = undefined,
    title: []const u8 = "",
    rules: std.ArrayListUnmanaged(StylesheetRule) = .empty,
    source: []const u8 = "",
    layout_w: f32 = 0,
    content_h: f32 = 0,

    pub fn init(child_allocator: std.mem.Allocator) Document {
        return .{ .arena = std.heap.ArenaAllocator.init(child_allocator) };
    }

    pub fn deinit(self: *Document) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn allocator(self: *Document) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn reset(self: *Document) void {
        const child = self.arena.child_allocator;
        self.arena.deinit();
        self.* = init(child);
    }
};

pub fn isVoidTag(tag: []const u8) bool {
    const voids = [_][]const u8{ "br", "hr", "img", "meta", "link", "input", "source", "area", "base", "col", "embed", "wbr" };
    for (voids) |v| {
        if (std.mem.eql(u8, tag, v)) return true;
    }
    return false;
}

pub fn defaultDisplay(tag: []const u8) Display {
    if (tag.len == 0) return .block;
    const inline_tags = [_][]const u8{ "span", "a", "strong", "b", "em", "i", "small", "code", "img", "br" };
    for (inline_tags) |t| {
        if (std.mem.eql(u8, tag, t)) return .inline_;
    }
    if (std.mem.eql(u8, tag, "table")) return .table;
    if (std.mem.eql(u8, tag, "tr")) return .table_row;
    if (std.mem.eql(u8, tag, "td") or std.mem.eql(u8, tag, "th")) return .table_cell;
    if (std.mem.eql(u8, tag, "audio") or std.mem.eql(u8, tag, "video")) return .block;
    if (std.mem.eql(u8, tag, "head") or std.mem.eql(u8, tag, "script") or std.mem.eql(u8, tag, "style") or std.mem.eql(u8, tag, "meta") or std.mem.eql(u8, tag, "title") or std.mem.eql(u8, tag, "link"))
        return .none;
    return .block;
}
