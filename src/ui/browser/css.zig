//! Apply stylesheet + inline styles → ComputedStyle.
const std = @import("std");
const dom = @import("dom.zig");

pub fn cascade(doc: *dom.Document) void {
    // Defaults + walk from root
    if (doc.root.children.items.len == 0) return;
    cascadeNode(doc, doc.root, null);
}

fn cascadeNode(doc: *dom.Document, n: *dom.Node, parent: ?*const dom.ComputedStyle) void {
    if (n.kind == .text) {
        if (parent) |p| n.style = p.*;
        return;
    }
    if (n.kind == .document) {
        n.style = .{
            .color = .{ 1, 1, 1, 1 },
            .bg = .{ 0.06, 0.07, 0.09, 1 },
        };
        for (n.children.items) |c| cascadeNode(doc, c, &n.style);
        return;
    }

    var st: dom.ComputedStyle = .{
        .color = .{ 1, 1, 1, 1 },
    };
    if (parent) |p| {
        st.color = p.color;
        st.font_size = p.font_size;
        st.font_weight = p.font_weight;
        st.line_height = p.line_height;
        st.text_align = p.text_align;
    }
    st.display = dom.defaultDisplay(n.tag);

    // UA-ish defaults
    if (std.mem.eql(u8, n.tag, "h1")) {
        st.font_size = 22;
        st.font_weight = 700;
        st.margin = .{ 8, 0, 6, 0 };
    } else if (std.mem.eql(u8, n.tag, "h2")) {
        st.font_size = 16;
        st.font_weight = 700;
        st.margin = .{ 8, 0, 4, 0 };
    } else if (std.mem.eql(u8, n.tag, "h3")) {
        st.font_size = 14;
        st.font_weight = 700;
        st.margin = .{ 6, 0, 4, 0 };
    } else if (std.mem.eql(u8, n.tag, "p")) {
        st.margin = .{ 4, 0, 4, 0 };
    } else if (std.mem.eql(u8, n.tag, "ul") or std.mem.eql(u8, n.tag, "ol")) {
        // Indent via padding-left so markers sit in the gutter; margin alone is
        // often zeroed by author CSS like `ul { margin: 6px 0 }`.
        st.margin = .{ 6, 0, 6, 0 };
        st.padding = .{ 0, 0, 0, 22 };
    } else if (std.mem.eql(u8, n.tag, "li")) {
        st.margin = .{ 3, 0, 3, 0 };
        st.display = .block;
    } else if (std.mem.eql(u8, n.tag, "a")) {
        st.color = .{ 0.45, 0.7, 1.0, 1 }; // light link on dark default bg
        st.display = .inline_;
    } else if (std.mem.eql(u8, n.tag, "strong") or std.mem.eql(u8, n.tag, "b")) {
        st.font_weight = 700;
        st.display = .inline_;
    } else if (std.mem.eql(u8, n.tag, "em") or std.mem.eql(u8, n.tag, "i")) {
        st.display = .inline_;
    } else if (std.mem.eql(u8, n.tag, "th")) {
        st.font_weight = 700;
        st.padding = .{ 4, 6, 4, 6 };
        st.border_w = 1;
        st.border_color = .{ 0.35, 0.38, 0.42, 1 };
        st.display = .table_cell;
    } else if (std.mem.eql(u8, n.tag, "td")) {
        st.padding = .{ 4, 6, 4, 6 };
        st.border_w = 1;
        st.border_color = .{ 0.35, 0.38, 0.42, 1 };
        st.display = .table_cell;
    } else if (std.mem.eql(u8, n.tag, "table")) {
        st.display = .table;
        st.margin = .{ 6, 0, 6, 0 };
    } else if (std.mem.eql(u8, n.tag, "body") or std.mem.eql(u8, n.tag, "html")) {
        st.padding = .{ 0, 0, 0, 0 };
        // Dark canvas by default (matches gl1 theme); CSS may override.
        st.bg = .{ 0.06, 0.07, 0.09, 1 };
        st.color = .{ 1, 1, 1, 1 };
    } else if (std.mem.eql(u8, n.tag, "hr")) {
        st.height = 1;
        st.margin = .{ 8, 0, 8, 0 };
        st.bg = .{ 0.45, 0.48, 0.52, 1 };
    }

    // Stylesheet rules (document order, low specificity)
    for (doc.rules.items) |rule| {
        if (matches(n, rule)) applyDecls(&st, rule.decls);
    }
    // Inline style wins
    if (n.style_attr.len > 0) applyDecls(&st, n.style_attr);

    n.style = st;
    for (n.children.items) |c| cascadeNode(doc, c, &st);
}

fn matches(n: *const dom.Node, rule: dom.StylesheetRule) bool {
    if (rule.sel_tag.len > 0 and !std.mem.eql(u8, n.tag, rule.sel_tag)) return false;
    if (rule.sel_id.len > 0 and !std.mem.eql(u8, n.id_attr, rule.sel_id)) return false;
    if (rule.sel_class.len > 0) {
        if (!hasClass(n.class_attr, rule.sel_class)) return false;
    }
    // bare "" selector shouldn't match everything unless * — require at least one part
    if (rule.sel_tag.len == 0 and rule.sel_class.len == 0 and rule.sel_id.len == 0) return false;
    return true;
}

fn hasClass(class_attr: []const u8, want: []const u8) bool {
    var it = std.mem.tokenizeAny(u8, class_attr, " \t");
    while (it.next()) |c| {
        if (std.mem.eql(u8, c, want)) return true;
    }
    return false;
}

fn applyDecls(st: *dom.ComputedStyle, decls: []const u8) void {
    var it = std.mem.splitScalar(u8, decls, ';');
    while (it.next()) |raw| {
        const d = std.mem.trim(u8, raw, " \t\r\n");
        if (d.len == 0) continue;
        const colon = std.mem.indexOfScalar(u8, d, ':') orelse continue;
        const prop = std.mem.trim(u8, d[0..colon], " \t");
        const val = std.mem.trim(u8, d[colon + 1 ..], " \t");
        applyOne(st, prop, val);
    }
}

fn applyOne(st: *dom.ComputedStyle, prop: []const u8, val: []const u8) void {
    if (eql(prop, "display")) {
        if (eql(val, "none")) {
            st.display = .none;
        } else if (eql(val, "block")) {
            st.display = .block;
        } else if (eql(val, "inline")) {
            st.display = .inline_;
        } else if (eql(val, "flex")) {
            st.display = .flex;
        } else if (eql(val, "table")) {
            st.display = .table;
        }
    } else if (eql(prop, "width")) {
        parseLen(val, &st.width, &st.width_pct);
    } else if (eql(prop, "height")) {
        parseLen(val, &st.height, &st.height_pct);
    } else if (eql(prop, "margin")) {
        parseBox(val, &st.margin);
    } else if (eql(prop, "margin-top")) {
        st.margin[0] = parsePx(val) orelse st.margin[0];
    } else if (eql(prop, "margin-right")) {
        st.margin[1] = parsePx(val) orelse st.margin[1];
    } else if (eql(prop, "margin-bottom")) {
        st.margin[2] = parsePx(val) orelse st.margin[2];
    } else if (eql(prop, "margin-left")) {
        st.margin[3] = parsePx(val) orelse st.margin[3];
    } else if (eql(prop, "padding")) {
        parseBox(val, &st.padding);
    } else if (eql(prop, "padding-top")) {
        st.padding[0] = parsePx(val) orelse st.padding[0];
    } else if (eql(prop, "padding-right")) {
        st.padding[1] = parsePx(val) orelse st.padding[1];
    } else if (eql(prop, "padding-bottom")) {
        st.padding[2] = parsePx(val) orelse st.padding[2];
    } else if (eql(prop, "padding-left")) {
        st.padding[3] = parsePx(val) orelse st.padding[3];
    } else if (eql(prop, "color")) {
        if (parseColor(val)) |c| st.color = c;
    } else if (eql(prop, "background-color") or eql(prop, "background")) {
        if (parseColor(val)) |c| st.bg = c;
    } else if (eql(prop, "font-size")) {
        if (parsePx(val)) |px| st.font_size = px;
    } else if (eql(prop, "font-weight")) {
        if (eql(val, "bold") or eql(val, "700")) {
            st.font_weight = 700;
        } else if (eql(val, "normal") or eql(val, "400")) {
            st.font_weight = 400;
        } else if (parsePx(val)) |n| {
            st.font_weight = n;
        }
    } else if (eql(prop, "text-align")) {
        if (eql(val, "center")) {
            st.text_align = .center;
        } else if (eql(val, "right")) {
            st.text_align = .right;
        } else {
            st.text_align = .left;
        }
    } else if (eql(prop, "flex-direction")) {
        if (eql(val, "column")) {
            st.flex_dir = .column;
        } else {
            st.flex_dir = .row;
        }
    } else if (eql(prop, "justify-content")) {
        if (eql(val, "center")) {
            st.justify = .center;
        } else if (eql(val, "space-between")) {
            st.justify = .space_between;
        } else if (eql(val, "flex-end")) {
            st.justify = .flex_end;
        } else {
            st.justify = .flex_start;
        }
    } else if (eql(prop, "align-items")) {
        if (eql(val, "center")) {
            st.align_items = .center;
        } else if (eql(val, "flex-start")) {
            st.align_items = .flex_start;
        } else if (eql(val, "flex-end")) {
            st.align_items = .flex_end;
        } else {
            st.align_items = .stretch;
        }
    } else if (eql(prop, "gap")) {
        st.gap = parsePx(val) orelse st.gap;
    } else if (eql(prop, "flex-grow")) {
        st.flex_grow = parsePx(val) orelse st.flex_grow;
    } else if (eql(prop, "border")) {
        var parts = std.mem.tokenizeAny(u8, val, " \t");
        while (parts.next()) |p| {
            if (parsePx(p)) |px| {
                st.border_w = px;
            } else if (parseColor(p)) |c| {
                st.border_color = c;
            }
        }
    } else if (eql(prop, "border-width")) {
        st.border_w = parsePx(val) orelse st.border_w;
    } else if (eql(prop, "border-color")) {
        if (parseColor(val)) |c| st.border_color = c;
    } else if (eql(prop, "overflow")) {
        if (eql(val, "hidden")) {
            st.overflow = .hidden;
        } else if (eql(val, "auto") or eql(val, "scroll")) {
            st.overflow = .auto_;
        } else {
            st.overflow = .visible;
        }
    }
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

fn parseLen(val: []const u8, px_out: *?f32, pct_out: *?f32) void {
    if (eql(val, "auto")) {
        px_out.* = null;
        pct_out.* = null;
        return;
    }
    if (std.mem.endsWith(u8, val, "%")) {
        const n = std.fmt.parseFloat(f32, val[0 .. val.len - 1]) catch return;
        pct_out.* = n;
        px_out.* = null;
        return;
    }
    if (parsePx(val)) |px| {
        px_out.* = px;
        pct_out.* = null;
    }
}

fn parsePx(val: []const u8) ?f32 {
    var s = val;
    if (std.mem.endsWith(u8, s, "px")) s = s[0 .. s.len - 2];
    return std.fmt.parseFloat(f32, std.mem.trim(u8, s, " \t")) catch null;
}

fn parseBox(val: []const u8, out: *[4]f32) void {
    var vals: [4]f32 = .{ 0, 0, 0, 0 };
    var n: usize = 0;
    var it = std.mem.tokenizeAny(u8, val, " \t");
    while (it.next()) |p| {
        if (n >= 4) break;
        vals[n] = parsePx(p) orelse 0;
        n += 1;
    }
    if (n == 1) {
        out.* = .{ vals[0], vals[0], vals[0], vals[0] };
    } else if (n == 2) {
        out.* = .{ vals[0], vals[1], vals[0], vals[1] };
    } else if (n == 3) {
        out.* = .{ vals[0], vals[1], vals[2], vals[1] };
    } else if (n >= 4) {
        out.* = .{ vals[0], vals[1], vals[2], vals[3] };
    }
}

pub fn parseColor(val: []const u8) ?dom.Color {
    const v = std.mem.trim(u8, val, " \t");
    if (v.len == 0) return null;
    if (v[0] == '#') {
        if (v.len == 4) {
            const r = hexNibble(v[1]) orelse return null;
            const g = hexNibble(v[2]) orelse return null;
            const b = hexNibble(v[3]) orelse return null;
            return .{
                @as(f32, @floatFromInt(r)) / 15.0,
                @as(f32, @floatFromInt(g)) / 15.0,
                @as(f32, @floatFromInt(b)) / 15.0,
                1,
            };
        }
        if (v.len >= 7) {
            const r = (hexNibble(v[1]) orelse return null) * 16 + (hexNibble(v[2]) orelse return null);
            const g = (hexNibble(v[3]) orelse return null) * 16 + (hexNibble(v[4]) orelse return null);
            const b = (hexNibble(v[5]) orelse return null) * 16 + (hexNibble(v[6]) orelse return null);
            return .{ @as(f32, @floatFromInt(r)) / 255.0, @as(f32, @floatFromInt(g)) / 255.0, @as(f32, @floatFromInt(b)) / 255.0, 1 };
        }
    }
    // named
    if (eql(v, "white")) return .{ 1, 1, 1, 1 };
    if (eql(v, "black")) return .{ 0, 0, 0, 1 };
    if (eql(v, "red")) return .{ 0.9, 0.2, 0.2, 1 };
    if (eql(v, "transparent")) return .{ 0, 0, 0, 0 };
    return null;
}

fn hexNibble(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}
