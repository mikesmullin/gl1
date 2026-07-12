//! Status pill — enum → colored badge (running / idle / error / …).
const types = @import("../types.zig");
const Color = types.Color;

pub const Kind = enum { idle, running, success, warning, error_ };

pub fn statusPill(ui: anytype, opts: anytype) void {
    const kind: Kind = opts.kind;
    const label: []const u8 = if (@hasField(@TypeOf(opts), "label") and opts.label.len > 0)
        opts.label
    else switch (kind) {
        .idle => "idle",
        .running => "running",
        .success => "success",
        .warning => "warning",
        .error_ => "error",
    };
    const col: Color = switch (kind) {
        .idle => ui.theme.text_dim,
        .running => ui.theme.info,
        .success => ui.theme.accent,
        .warning => ui.theme.warning,
        .error_ => ui.theme.danger,
    };
    // Reuse badge look
    @import("badge.zig").badge(ui, .{ .label = label, .color = col });
}
