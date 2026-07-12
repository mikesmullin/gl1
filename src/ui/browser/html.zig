//! Tiny HTML5 subset parser → DOM tree.
const std = @import("std");
const dom = @import("dom.zig");

pub fn parse(doc: *dom.Document, html: []const u8) !void {
    doc.reset();
    const a = doc.allocator();
    doc.source = try a.dupe(u8, html);

    doc.root = try a.create(dom.Node);
    doc.root.* = .{ .kind = .document, .tag = "document" };

    var i: usize = 0;
    _ = try parseChildren(doc, doc.root, html, &i, null);

    // Title from first <title>
    if (findFirst(doc.root, "title")) |t| {
        doc.title = collectText(a, t) catch "";
    }

    // Collect <style> rules
    try collectStyles(doc, doc.root);
}

fn parseChildren(doc: *dom.Document, parent: *dom.Node, html: []const u8, i: *usize, stop_tag: ?[]const u8) !void {
    const a = doc.allocator();
    while (i.* < html.len) {
        if (html[i.*] == '<') {
            if (i.* + 1 < html.len and html[i.* + 1] == '/') {
                // closing tag
                i.* += 2;
                const name = readIdent(html, i);
                skipWs(html, i);
                if (i.* < html.len and html[i.*] == '>') i.* += 1;
                if (stop_tag) |st| {
                    if (std.ascii.eqlIgnoreCase(name, st)) return;
                }
                // mismatched close — ignore
                continue;
            }
            if (i.* + 3 < html.len and std.mem.startsWith(u8, html[i.*..], "<!--")) {
                if (std.mem.indexOf(u8, html[i.*..], "-->")) |end| {
                    i.* += end + 3;
                } else i.* = html.len;
                continue;
            }
            if (i.* + 2 < html.len and html[i.* + 1] == '!') {
                // doctype / comment-ish
                while (i.* < html.len and html[i.*] != '>') : (i.* += 1) {}
                if (i.* < html.len) i.* += 1;
                continue;
            }
            // open tag
            i.* += 1;
            const raw_tag = readIdent(html, i);
            var tag_buf: [32]u8 = undefined;
            const tag = lowerInto(&tag_buf, raw_tag);

            var attrs_list: std.ArrayListUnmanaged(dom.Attr) = .empty;
            var self_close = false;
            while (i.* < html.len) {
                skipWs(html, i);
                if (i.* >= html.len) break;
                if (html[i.*] == '>') {
                    i.* += 1;
                    break;
                }
                if (html[i.*] == '/' and i.* + 1 < html.len and html[i.* + 1] == '>') {
                    self_close = true;
                    i.* += 2;
                    break;
                }
                const key = readIdent(html, i);
                if (key.len == 0) {
                    i.* += 1;
                    continue;
                }
                skipWs(html, i);
                var val: []const u8 = "";
                if (i.* < html.len and html[i.*] == '=') {
                    i.* += 1;
                    skipWs(html, i);
                    val = readAttrValue(html, i);
                }
                const k = try a.dupe(u8, lowerDupe(a, key) catch key);
                const v = try a.dupe(u8, decodeEntities(a, val) catch val);
                try attrs_list.append(a, .{ .key = k, .val = v });
            }

            const node = try a.create(dom.Node);
            node.* = .{
                .kind = .element,
                .tag = try a.dupe(u8, tag),
                .attrs = try attrs_list.toOwnedSlice(a),
            };
            for (node.attrs) |at| {
                if (std.mem.eql(u8, at.key, "class")) node.class_attr = at.val;
                if (std.mem.eql(u8, at.key, "id")) node.id_attr = at.val;
                if (std.mem.eql(u8, at.key, "style")) node.style_attr = at.val;
            }
            try parent.children.append(a, node);

            const voidish = dom.isVoidTag(tag) or self_close;
            if (!voidish) {
                try parseChildren(doc, node, html, i, tag);
            }
            continue;
        }

        // text run
        const start = i.*;
        while (i.* < html.len and html[i.*] != '<') : (i.* += 1) {}
        const raw = html[start..i.*];
        const trimmed = std.mem.trim(u8, raw, " \t\r\n");
        if (trimmed.len > 0) {
            const text = try decodeEntities(a, raw);
            // collapse? keep simple trim of whole if only whitespace runs — use raw collapsed
            const collapsed = try collapseWs(a, text);
            if (collapsed.len > 0) {
                const tn = try a.create(dom.Node);
                tn.* = .{ .kind = .text, .text = collapsed };
                try parent.children.append(a, tn);
            }
        }
    }
}

fn readIdent(html: []const u8, i: *usize) []const u8 {
    const start = i.*;
    while (i.* < html.len) : (i.* += 1) {
        const c = html[i.*];
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == ':' or c == '_') continue;
        break;
    }
    return html[start..i.*];
}

fn readAttrValue(html: []const u8, i: *usize) []const u8 {
    if (i.* >= html.len) return "";
    if (html[i.*] == '"' or html[i.*] == '\'') {
        const q = html[i.*];
        i.* += 1;
        const start = i.*;
        while (i.* < html.len and html[i.*] != q) : (i.* += 1) {}
        const v = html[start..i.*];
        if (i.* < html.len) i.* += 1;
        return v;
    }
    const start = i.*;
    while (i.* < html.len and !std.ascii.isWhitespace(html[i.*]) and html[i.*] != '>') : (i.* += 1) {}
    return html[start..i.*];
}

fn skipWs(html: []const u8, i: *usize) void {
    while (i.* < html.len and std.ascii.isWhitespace(html[i.*])) : (i.* += 1) {}
}

fn lowerInto(buf: []u8, s: []const u8) []const u8 {
    const n = @min(buf.len, s.len);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        buf[i] = std.ascii.toLower(s[i]);
    }
    return buf[0..n];
}

fn lowerDupe(a: std.mem.Allocator, s: []const u8) ![]const u8 {
    const out = try a.alloc(u8, s.len);
    for (s, 0..) |c, i| out[i] = std.ascii.toLower(c);
    return out;
}

fn collapseWs(a: std.mem.Allocator, s: []const u8) ![]const u8 {
    var list: std.ArrayListUnmanaged(u8) = .empty;
    errdefer list.deinit(a);
    var prev_space = true; // trim leading
    for (s) |c| {
        if (c == '\r') continue;
        if (c == '\n' or c == '\t' or c == ' ') {
            if (!prev_space) {
                try list.append(a, ' ');
                prev_space = true;
            }
        } else {
            try list.append(a, c);
            prev_space = false;
        }
    }
    if (list.items.len > 0 and list.items[list.items.len - 1] == ' ') {
        _ = list.pop();
    }
    return try list.toOwnedSlice(a);
}

fn decodeEntities(a: std.mem.Allocator, s: []const u8) ![]const u8 {
    if (std.mem.indexOfScalar(u8, s, '&') == null) return try a.dupe(u8, s);
    var list: std.ArrayListUnmanaged(u8) = .empty;
    errdefer list.deinit(a);
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '&') {
            if (std.mem.startsWith(u8, s[i..], "&amp;")) {
                try list.append(a, '&');
                i += 5;
                continue;
            }
            if (std.mem.startsWith(u8, s[i..], "&lt;")) {
                try list.append(a, '<');
                i += 4;
                continue;
            }
            if (std.mem.startsWith(u8, s[i..], "&gt;")) {
                try list.append(a, '>');
                i += 4;
                continue;
            }
            if (std.mem.startsWith(u8, s[i..], "&quot;")) {
                try list.append(a, '"');
                i += 6;
                continue;
            }
            if (std.mem.startsWith(u8, s[i..], "&nbsp;")) {
                try list.append(a, ' ');
                i += 6;
                continue;
            }
            if (std.mem.startsWith(u8, s[i..], "&#")) {
                // numeric skip simple
                if (std.mem.indexOfScalar(u8, s[i..], ';')) |semi| {
                    i += semi + 1;
                    try list.append(a, '?');
                    continue;
                }
            }
        }
        try list.append(a, s[i]);
        i += 1;
    }
    return try list.toOwnedSlice(a);
}

fn findFirst(n: *dom.Node, tag: []const u8) ?*dom.Node {
    if (n.kind == .element and std.mem.eql(u8, n.tag, tag)) return n;
    for (n.children.items) |c| {
        if (findFirst(c, tag)) |f| return f;
    }
    return null;
}

fn collectText(a: std.mem.Allocator, n: *dom.Node) ![]const u8 {
    var list: std.ArrayListUnmanaged(u8) = .empty;
    errdefer list.deinit(a);
    try walkText(a, n, &list);
    return try list.toOwnedSlice(a);
}

fn walkText(a: std.mem.Allocator, n: *dom.Node, list: *std.ArrayListUnmanaged(u8)) !void {
    if (n.kind == .text) {
        try list.appendSlice(a, n.text);
        return;
    }
    for (n.children.items) |c| try walkText(a, c, list);
}

fn collectStyles(doc: *dom.Document, n: *dom.Node) !void {
    if (n.kind == .element and std.mem.eql(u8, n.tag, "style")) {
        const a = doc.allocator();
        const css = try collectText(a, n);
        try parseStylesheet(doc, css);
    }
    for (n.children.items) |c| try collectStyles(doc, c);
}

fn parseStylesheet(doc: *dom.Document, css: []const u8) !void {
    const a = doc.allocator();
    var i: usize = 0;
    while (i < css.len) {
        skipWs(css, &i);
        if (i >= css.len) break;
        // skip comments
        if (i + 1 < css.len and css[i] == '/' and css[i + 1] == '*') {
            i += 2;
            while (i + 1 < css.len and !(css[i] == '*' and css[i + 1] == '/')) : (i += 1) {}
            if (i + 1 < css.len) i += 2;
            continue;
        }
        const sel_start = i;
        while (i < css.len and css[i] != '{') : (i += 1) {}
        if (i >= css.len) break;
        const sel_raw = std.mem.trim(u8, css[sel_start..i], " \t\r\n");
        i += 1; // {
        const body_start = i;
        while (i < css.len and css[i] != '}') : (i += 1) {}
        const body = std.mem.trim(u8, css[body_start..i], " \t\r\n");
        if (i < css.len) i += 1;

        // support comma-separated selectors
        var it = std.mem.splitScalar(u8, sel_raw, ',');
        while (it.next()) |one| {
            const s = std.mem.trim(u8, one, " \t\r\n");
            if (s.len == 0) continue;
            var rule: dom.StylesheetRule = .{ .decls = try a.dupe(u8, body) };
            parseSimpleSelector(s, &rule);
            try doc.rules.append(a, rule);
        }
    }
}

fn parseSimpleSelector(s: []const u8, rule: *dom.StylesheetRule) void {
    // last simple compound only: tag.class #id .class tag
    var i: usize = 0;
    if (s.len > 0 and s[0] != '.' and s[0] != '#') {
        const start = i;
        while (i < s.len and s[i] != '.' and s[i] != '#' and s[i] != ' ') : (i += 1) {}
        rule.sel_tag = s[start..i];
    }
    while (i < s.len) {
        if (s[i] == '.') {
            i += 1;
            const start = i;
            while (i < s.len and s[i] != '.' and s[i] != '#' and s[i] != ' ') : (i += 1) {}
            rule.sel_class = s[start..i];
        } else if (s[i] == '#') {
            i += 1;
            const start = i;
            while (i < s.len and s[i] != '.' and s[i] != '#' and s[i] != ' ') : (i += 1) {}
            rule.sel_id = s[start..i];
        } else {
            // descendant — take last class/id/tag only; skip space
            i += 1;
        }
    }
}
