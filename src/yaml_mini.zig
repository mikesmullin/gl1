//! Minimal YAML subset parser for the icon manifest.
//! Supports:
//!   key: value
//!   key: [a, b, c]
//!   key:
//!     - id: foo
//!       x: 0
//! Comments (#) and blank lines ignored. Indentation by spaces only.

const std = @import("std");

pub const Value = union(enum) {
    string: []const u8,
    int: i64,
    list: []const []const u8,
    map: Map,
    list_map: []const Map,
};

pub const Map = struct {
    entries: []const Entry = &.{},

    pub const Entry = struct {
        key: []const u8,
        value: Value,
    };

    pub fn get(self: Map, key: []const u8) ?Value {
        for (self.entries) |e| {
            if (std.mem.eql(u8, e.key, key)) return e.value;
        }
        return null;
    }

    pub fn getString(self: Map, key: []const u8) ?[]const u8 {
        const v = self.get(key) orelse return null;
        return switch (v) {
            .string => |s| s,
            else => null,
        };
    }

    pub fn getInt(self: Map, key: []const u8) ?i64 {
        const v = self.get(key) orelse return null;
        return switch (v) {
            .int => |i| i,
            .string => |s| std.fmt.parseInt(i64, s, 10) catch null,
            else => null,
        };
    }

    pub fn getList(self: Map, key: []const u8) ?[]const []const u8 {
        const v = self.get(key) orelse return null;
        return switch (v) {
            .list => |l| l,
            else => null,
        };
    }

    pub fn getListMap(self: Map, key: []const u8) ?[]const Map {
        const v = self.get(key) orelse return null;
        return switch (v) {
            .list_map => |l| l,
            else => null,
        };
    }
};

pub const Doc = struct {
    root: Map,
    /// Arena of allocated slices/arrays for this parse.
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *Doc) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

fn stripComment(line: []const u8) []const u8 {
    // Don't strip # inside quotes (we don't support quotes much).
    if (std.mem.indexOfScalar(u8, line, '#')) |i| {
        return line[0..i];
    }
    return line;
}

fn indentOf(line: []const u8) usize {
    var i: usize = 0;
    while (i < line.len and line[i] == ' ') : (i += 1) {}
    return i;
}

fn parseScalar(alloc: std.mem.Allocator, raw: []const u8) !Value {
    const s = trim(raw);
    if (s.len == 0) return .{ .string = try alloc.dupe(u8, "") };
    if (s[0] == '[' and s[s.len - 1] == ']') {
        const inner = trim(s[1 .. s.len - 1]);
        if (inner.len == 0) {
            const empty: []const []const u8 = &.{};
            return .{ .list = empty };
        }
        var list: std.ArrayListUnmanaged([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, inner, ',');
        while (it.next()) |part| {
            const p = trim(part);
            if (p.len == 0) continue;
            try list.append(alloc, try alloc.dupe(u8, p));
        }
        return .{ .list = try list.toOwnedSlice(alloc) };
    }
    if (std.fmt.parseInt(i64, s, 10)) |n| {
        return .{ .int = n };
    } else |_| {}
    return .{ .string = try alloc.dupe(u8, s) };
}

const Line = struct {
    indent: usize,
    text: []const u8, // trimmed content without indent
};

pub fn parse(parent_allocator: std.mem.Allocator, src: []const u8) !Doc {
    var arena = std.heap.ArenaAllocator.init(parent_allocator);
    errdefer arena.deinit();
    const alloc = arena.allocator();

    var lines: std.ArrayListUnmanaged(Line) = .empty;
    var it = std.mem.splitScalar(u8, src, '\n');
    while (it.next()) |raw_line| {
        const no_c = stripComment(raw_line);
        if (trim(no_c).len == 0) continue;
        const ind = indentOf(no_c);
        try lines.append(alloc, .{ .indent = ind, .text = try alloc.dupe(u8, trim(no_c[ind..])) });
    }

    var idx: usize = 0;
    const root = try parseMap(alloc, lines.items, 0, &idx);
    return .{ .root = root, .arena = arena };
}

fn parseMap(alloc: std.mem.Allocator, lines: []const Line, base_indent: usize, idx: *usize) !Map {
    var entries: std.ArrayListUnmanaged(Map.Entry) = .empty;
    while (idx.* < lines.len) {
        const L = lines[idx.*];
        if (L.indent < base_indent) break;
        if (L.indent > base_indent) return error.BadIndent;
        // list item at this level belongs to parent
        if (std.mem.startsWith(u8, L.text, "- ")) break;

        const colon = std.mem.indexOfScalar(u8, L.text, ':') orelse return error.MissingColon;
        const key = trim(L.text[0..colon]);
        const rest = trim(L.text[colon + 1 ..]);
        idx.* += 1;

        if (rest.len > 0) {
            try entries.append(alloc, .{
                .key = try alloc.dupe(u8, key),
                .value = try parseScalar(alloc, rest),
            });
            continue;
        }

        // Nested structure: either list of maps or nested map
        if (idx.* < lines.len and lines[idx.*].indent > base_indent) {
            const child_indent = lines[idx.*].indent;
            if (std.mem.startsWith(u8, lines[idx.*].text, "- ")) {
                const lm = try parseListMap(alloc, lines, child_indent, idx);
                try entries.append(alloc, .{
                    .key = try alloc.dupe(u8, key),
                    .value = .{ .list_map = lm },
                });
            } else {
                const nested = try parseMap(alloc, lines, child_indent, idx);
                try entries.append(alloc, .{
                    .key = try alloc.dupe(u8, key),
                    .value = .{ .map = nested },
                });
            }
        } else {
            try entries.append(alloc, .{
                .key = try alloc.dupe(u8, key),
                .value = .{ .string = try alloc.dupe(u8, "") },
            });
        }
    }
    return .{ .entries = try entries.toOwnedSlice(alloc) };
}

fn parseListMap(alloc: std.mem.Allocator, lines: []const Line, item_indent: usize, idx: *usize) ![]const Map {
    var maps: std.ArrayListUnmanaged(Map) = .empty;
    while (idx.* < lines.len) {
        const L = lines[idx.*];
        if (L.indent < item_indent) break;
        if (L.indent > item_indent) return error.BadIndent;
        if (!std.mem.startsWith(u8, L.text, "- ")) break;

        // "- id: foo"  or  "-" then nested
        const after = trim(L.text[2..]);
        idx.* += 1;
        var item_entries: std.ArrayListUnmanaged(Map.Entry) = .empty;

        if (after.len > 0) {
            const colon = std.mem.indexOfScalar(u8, after, ':') orelse return error.MissingColon;
            const key = trim(after[0..colon]);
            const rest = trim(after[colon + 1 ..]);
            try item_entries.append(alloc, .{
                .key = try alloc.dupe(u8, key),
                .value = try parseScalar(alloc, rest),
            });
        }

        // Subsequent keys for this list item are indented deeper than item_indent
        while (idx.* < lines.len) {
            const M = lines[idx.*];
            if (M.indent <= item_indent) break;
            if (std.mem.startsWith(u8, M.text, "- ")) break;
            const colon = std.mem.indexOfScalar(u8, M.text, ':') orelse return error.MissingColon;
            const key = trim(M.text[0..colon]);
            const rest = trim(M.text[colon + 1 ..]);
            idx.* += 1;
            try item_entries.append(alloc, .{
                .key = try alloc.dupe(u8, key),
                .value = try parseScalar(alloc, rest),
            });
        }

        try maps.append(alloc, .{ .entries = try item_entries.toOwnedSlice(alloc) });
    }
    return try maps.toOwnedSlice(alloc);
}
