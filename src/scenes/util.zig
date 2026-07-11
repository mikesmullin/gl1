const std = @import("std");

pub fn containsIgnoreCase(hay: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > hay.len) return false;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        var ok = true;
        for (needle, 0..) |nc, j| {
            const hc = hay[i + j];
            const a = if (nc >= 'A' and nc <= 'Z') nc + 32 else nc;
            const b = if (hc >= 'A' and hc <= 'Z') hc + 32 else hc;
            if (a != b) {
                ok = false;
                break;
            }
        }
        if (ok) return true;
    }
    return false;
}
