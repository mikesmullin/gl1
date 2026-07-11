//! Shared text editing model for single-line and multi-line fields.
//! Supports caret, selection, word/line motion, mouse placement, and
//! multi-caret (Ctrl+D) for multi-line text areas.

const std = @import("std");
const input_mod = @import("../input.zig");
const font_mod = @import("../font.zig");

pub const Input = input_mod.Input;
pub const Font = font_mod.Font;

pub const MaxCarets = 8;

pub const Range = struct {
    /// Insert/caret position (0..len).
    caret: usize = 0,
    /// Selection anchor; equals caret when empty selection.
    anchor: usize = 0,

    pub fn hasSel(self: Range) bool {
        return self.caret != self.anchor;
    }
    pub fn lo(self: Range) usize {
        return @min(self.caret, self.anchor);
    }
    pub fn hi(self: Range) usize {
        return @max(self.caret, self.anchor);
    }
};

pub const MaxUndo = 48;
pub const MaxSnap = 512;

pub const Snap = struct {
    data: [MaxSnap]u8 = undefined,
    len: usize = 0,
    caret: usize = 0,
    anchor: usize = 0,
};

pub const Edit = struct {
    /// Primary + multi-carets (index 0 is primary).
    carets: [MaxCarets]Range = @splat(.{}),
    caret_ct: usize = 1,
    /// Preferred column for vertical motion (multi-line).
    preferred_col: usize = 0,
    /// Block (column) selection mode.
    block: bool = false,
    block_col0: usize = 0,
    block_col1: usize = 0,
    block_row0: usize = 0,
    block_row1: usize = 0,
    /// Mouse drag selecting.
    dragging: bool = false,
    /// Click tracking for double/triple.
    last_click_time: f64 = -1,
    last_click_pos: usize = 0,
    click_count: u8 = 0,
    /// Undo/redo ring: snaps[0..undo_len], undo_at is current index (redo is ahead).
    snaps: [MaxUndo]Snap = undefined,
    undo_len: usize = 0,
    undo_at: usize = 0,
    /// Coalesce typing into one undo step until pause/nav.
    coalesce_typing: bool = false,

    pub fn primary(self: *Edit) *Range {
        return &self.carets[0];
    }
    pub fn primaryConst(self: *const Edit) Range {
        return self.carets[0];
    }

    pub fn clearSel(self: *Edit) void {
        var i: usize = 0;
        while (i < self.caret_ct) : (i += 1) {
            self.carets[i].anchor = self.carets[i].caret;
        }
        self.block = false;
    }

    pub fn setCaret(self: *Edit, pos: usize, len: usize, keep_sel: bool) void {
        const p = @min(pos, len);
        self.carets[0].caret = p;
        if (!keep_sel) self.carets[0].anchor = p;
        self.caret_ct = 1;
        self.block = false;
    }

    pub fn clampAll(self: *Edit, len: usize) void {
        var i: usize = 0;
        while (i < self.caret_ct) : (i += 1) {
            self.carets[i].caret = @min(self.carets[i].caret, len);
            self.carets[i].anchor = @min(self.carets[i].anchor, len);
        }
    }

    pub fn pushUndo(self: *Edit, buf: []const u8, len: usize) void {
        // Drop redo branch
        self.undo_len = self.undo_at;
        if (self.undo_len >= MaxUndo) {
            // shift left
            var i: usize = 0;
            while (i + 1 < MaxUndo) : (i += 1) {
                self.snaps[i] = self.snaps[i + 1];
            }
            self.undo_len = MaxUndo - 1;
            self.undo_at = self.undo_len;
        }
        var s = &self.snaps[self.undo_len];
        const n = @min(len, MaxSnap);
        @memcpy(s.data[0..n], buf[0..n]);
        s.len = n;
        s.caret = self.carets[0].caret;
        s.anchor = self.carets[0].anchor;
        self.undo_len += 1;
        self.undo_at = self.undo_len;
    }

    pub fn undo(self: *Edit, buf: []u8, len: *usize) bool {
        if (self.undo_at == 0) return false;
        // Save current as redo point if at tip
        if (self.undo_at == self.undo_len and self.undo_len < MaxUndo) {
            var s = &self.snaps[self.undo_len];
            const n = @min(len.*, MaxSnap);
            @memcpy(s.data[0..n], buf[0..n]);
            s.len = n;
            s.caret = self.carets[0].caret;
            s.anchor = self.carets[0].anchor;
            self.undo_len += 1;
        }
        self.undo_at -= 1;
        const s = self.snaps[self.undo_at];
        const n = @min(s.len, buf.len);
        @memcpy(buf[0..n], s.data[0..n]);
        len.* = n;
        self.carets[0] = .{ .caret = @min(s.caret, n), .anchor = @min(s.anchor, n) };
        self.caret_ct = 1;
        self.coalesce_typing = false;
        return true;
    }

    pub fn redo(self: *Edit, buf: []u8, len: *usize) bool {
        if (self.undo_at + 1 >= self.undo_len) return false;
        self.undo_at += 1;
        const s = self.snaps[self.undo_at];
        const n = @min(s.len, buf.len);
        @memcpy(buf[0..n], s.data[0..n]);
        len.* = n;
        self.carets[0] = .{ .caret = @min(s.caret, n), .anchor = @min(s.anchor, n) };
        self.caret_ct = 1;
        self.coalesce_typing = false;
        return true;
    }

    fn beforeMutate(self: *Edit, buf: []const u8, len: usize, typing: bool) void {
        if (typing and self.coalesce_typing) return;
        self.pushUndo(buf, len);
        self.coalesce_typing = typing;
    }
};

// --- line helpers -----------------------------------------------------------

pub fn lineStart(text: []const u8, pos: usize) usize {
    var i = @min(pos, text.len);
    while (i > 0 and text[i - 1] != '\n') : (i -= 1) {}
    return i;
}

pub fn lineEnd(text: []const u8, pos: usize) usize {
    var i = @min(pos, text.len);
    while (i < text.len and text[i] != '\n') : (i += 1) {}
    return i;
}

pub fn colOf(text: []const u8, pos: usize) usize {
    return pos - lineStart(text, pos);
}

pub fn rowOf(text: []const u8, pos: usize) usize {
    var row: usize = 0;
    var i: usize = 0;
    const p = @min(pos, text.len);
    while (i < p) : (i += 1) {
        if (text[i] == '\n') row += 1;
    }
    return row;
}

pub fn posAtRowCol(text: []const u8, row: usize, col: usize) usize {
    var r: usize = 0;
    var i: usize = 0;
    while (i < text.len and r < row) : (i += 1) {
        if (text[i] == '\n') r += 1;
    }
    const ls = i;
    const le = lineEnd(text, ls);
    const max_col = le - ls;
    return ls + @min(col, max_col);
}

fn isWord(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or
        (ch >= 'A' and ch <= 'Z') or
        (ch >= '0' and ch <= '9') or
        ch == '_';
}

pub fn wordStart(text: []const u8, pos: usize) usize {
    var i = @min(pos, text.len);
    if (i == 0) return 0;
    if (i == text.len or !isWord(text[i])) {
        // move left into a word
        while (i > 0 and !isWord(text[i - 1])) : (i -= 1) {}
    }
    while (i > 0 and isWord(text[i - 1])) : (i -= 1) {}
    return i;
}

pub fn wordEnd(text: []const u8, pos: usize) usize {
    var i = @min(pos, text.len);
    while (i < text.len and !isWord(text[i])) : (i += 1) {}
    while (i < text.len and isWord(text[i])) : (i += 1) {}
    return i;
}

pub fn prevWord(text: []const u8, pos: usize) usize {
    var i = @min(pos, text.len);
    if (i == 0) return 0;
    i -= 1;
    while (i > 0 and !isWord(text[i])) : (i -= 1) {}
    while (i > 0 and isWord(text[i - 1])) : (i -= 1) {}
    return i;
}

pub fn nextWord(text: []const u8, pos: usize) usize {
    return wordEnd(text, pos);
}

// --- mutations --------------------------------------------------------------

fn deleteRange(buf: []u8, len: *usize, lo: usize, hi: usize) void {
    if (lo >= hi or hi > len.*) return;
    const n = hi - lo;
    std.mem.copyForwards(u8, buf[lo .. len.* - n], buf[hi..len.*]);
    len.* -= n;
}

fn insertAt(buf: []u8, len: *usize, pos: usize, bytes: []const u8) usize {
    const space = buf.len - len.*;
    const n = @min(space, bytes.len);
    if (n == 0) return 0;
    const p = @min(pos, len.*);
    std.mem.copyBackwards(u8, buf[p + n .. len.* + n], buf[p..len.*]);
    @memcpy(buf[p .. p + n], bytes[0..n]);
    len.* += n;
    return n;
}

/// Delete selection(s) or nothing. Returns true if buffer changed.
pub fn deleteSelections(edit: *Edit, buf: []u8, len: *usize) bool {
    // Process from end so earlier indices stay valid.
    var changed = false;
    // Sort carets by lo descending
    var order: [MaxCarets]usize = undefined;
    var i: usize = 0;
    while (i < edit.caret_ct) : (i += 1) order[i] = i;
    // simple bubble by lo desc
    var a: usize = 0;
    while (a < edit.caret_ct) : (a += 1) {
        var b: usize = a + 1;
        while (b < edit.caret_ct) : (b += 1) {
            if (edit.carets[order[a]].lo() < edit.carets[order[b]].lo()) {
                const t = order[a];
                order[a] = order[b];
                order[b] = t;
            }
        }
    }
    i = 0;
    while (i < edit.caret_ct) : (i += 1) {
        const r = &edit.carets[order[i]];
        if (r.hasSel()) {
            const lo = r.lo();
            const hi = r.hi();
            deleteRange(buf, len, lo, hi);
            r.caret = lo;
            r.anchor = lo;
            changed = true;
        }
    }
    edit.clampAll(len.*);
    return changed;
}

pub fn insertText(edit: *Edit, buf: []u8, len: *usize, bytes: []const u8) bool {
    _ = deleteSelections(edit, buf, len);
    // Insert at each caret from end
    var order: [MaxCarets]usize = undefined;
    var i: usize = 0;
    while (i < edit.caret_ct) : (i += 1) order[i] = i;
    var a: usize = 0;
    while (a < edit.caret_ct) : (a += 1) {
        var b: usize = a + 1;
        while (b < edit.caret_ct) : (b += 1) {
            if (edit.carets[order[a]].caret < edit.carets[order[b]].caret) {
                const t = order[a];
                order[a] = order[b];
                order[b] = t;
            }
        }
    }
    var changed = false;
    i = 0;
    while (i < edit.caret_ct) : (i += 1) {
        const r = &edit.carets[order[i]];
        const n = insertAt(buf, len, r.caret, bytes);
        if (n > 0) {
            r.caret += n;
            r.anchor = r.caret;
            changed = true;
        }
    }
    return changed;
}

pub fn backspace(edit: *Edit, buf: []u8, len: *usize) bool {
    if (deleteSelections(edit, buf, len)) return true;
    var changed = false;
    // From end
    var order: [MaxCarets]usize = undefined;
    var i: usize = 0;
    while (i < edit.caret_ct) : (i += 1) order[i] = i;
    var a: usize = 0;
    while (a < edit.caret_ct) : (a += 1) {
        var b: usize = a + 1;
        while (b < edit.caret_ct) : (b += 1) {
            if (edit.carets[order[a]].caret < edit.carets[order[b]].caret) {
                const t = order[a];
                order[a] = order[b];
                order[b] = t;
            }
        }
    }
    i = 0;
    while (i < edit.caret_ct) : (i += 1) {
        const r = &edit.carets[order[i]];
        if (r.caret > 0) {
            deleteRange(buf, len, r.caret - 1, r.caret);
            r.caret -= 1;
            r.anchor = r.caret;
            changed = true;
        }
    }
    return changed;
}

pub fn deleteForward(edit: *Edit, buf: []u8, len: *usize) bool {
    if (deleteSelections(edit, buf, len)) return true;
    var changed = false;
    var order: [MaxCarets]usize = undefined;
    var i: usize = 0;
    while (i < edit.caret_ct) : (i += 1) order[i] = i;
    var a: usize = 0;
    while (a < edit.caret_ct) : (a += 1) {
        var b: usize = a + 1;
        while (b < edit.caret_ct) : (b += 1) {
            if (edit.carets[order[a]].caret < edit.carets[order[b]].caret) {
                const t = order[a];
                order[a] = order[b];
                order[b] = t;
            }
        }
    }
    i = 0;
    while (i < edit.caret_ct) : (i += 1) {
        const r = &edit.carets[order[i]];
        if (r.caret < len.*) {
            deleteRange(buf, len, r.caret, r.caret + 1);
            r.anchor = r.caret;
            changed = true;
        }
    }
    return changed;
}

// --- navigation -------------------------------------------------------------

pub fn moveLeft(edit: *Edit, text: []const u8, extend: bool, by_word: bool) void {
    var i: usize = 0;
    while (i < edit.caret_ct) : (i += 1) {
        var r = &edit.carets[i];
        if (!extend and r.hasSel() and !by_word) {
            r.caret = r.lo();
            r.anchor = r.caret;
            continue;
        }
        if (by_word) {
            r.caret = prevWord(text, r.caret);
        } else if (r.caret > 0) {
            r.caret -= 1;
        }
        if (!extend) r.anchor = r.caret;
    }
    edit.preferred_col = colOf(text, edit.carets[0].caret);
    edit.block = false;
}

pub fn moveRight(edit: *Edit, text: []const u8, extend: bool, by_word: bool) void {
    var i: usize = 0;
    while (i < edit.caret_ct) : (i += 1) {
        var r = &edit.carets[i];
        if (!extend and r.hasSel() and !by_word) {
            r.caret = r.hi();
            r.anchor = r.caret;
            continue;
        }
        if (by_word) {
            r.caret = nextWord(text, r.caret);
        } else if (r.caret < text.len) {
            r.caret += 1;
        }
        if (!extend) r.anchor = r.caret;
    }
    edit.preferred_col = colOf(text, edit.carets[0].caret);
    edit.block = false;
}

pub fn moveHome(edit: *Edit, text: []const u8, extend: bool, doc: bool) void {
    var i: usize = 0;
    while (i < edit.caret_ct) : (i += 1) {
        var r = &edit.carets[i];
        r.caret = if (doc) 0 else lineStart(text, r.caret);
        if (!extend) r.anchor = r.caret;
    }
    edit.preferred_col = 0;
    edit.block = false;
}

pub fn moveEnd(edit: *Edit, text: []const u8, extend: bool, doc: bool) void {
    var i: usize = 0;
    while (i < edit.caret_ct) : (i += 1) {
        var r = &edit.carets[i];
        r.caret = if (doc) text.len else lineEnd(text, r.caret);
        if (!extend) r.anchor = r.caret;
    }
    edit.preferred_col = colOf(text, edit.carets[0].caret);
    edit.block = false;
}

pub fn moveUp(edit: *Edit, text: []const u8, extend: bool, block: bool) void {
    if (block) {
        edit.block = true;
        // expand block selection up
        const r = edit.carets[0].caret;
        const row = rowOf(text, r);
        if (row > 0) {
            edit.block_row0 = @min(edit.block_row0, row - 1);
            edit.block_row1 = @max(edit.block_row1, row);
            edit.carets[0].caret = posAtRowCol(text, row - 1, edit.preferred_col);
        }
        return;
    }
    var i: usize = 0;
    while (i < edit.caret_ct) : (i += 1) {
        var r = &edit.carets[i];
        const row = rowOf(text, r.caret);
        if (row == 0) {
            r.caret = 0;
        } else {
            r.caret = posAtRowCol(text, row - 1, edit.preferred_col);
        }
        if (!extend) r.anchor = r.caret;
    }
    edit.block = false;
}

pub fn moveDown(edit: *Edit, text: []const u8, extend: bool, block: bool) void {
    if (block) {
        edit.block = true;
        const r = edit.carets[0].caret;
        const row = rowOf(text, r);
        edit.block_row1 = @max(edit.block_row1, row + 1);
        edit.carets[0].caret = posAtRowCol(text, row + 1, edit.preferred_col);
        return;
    }
    var i: usize = 0;
    while (i < edit.caret_ct) : (i += 1) {
        var r = &edit.carets[i];
        const row = rowOf(text, r.caret);
        r.caret = posAtRowCol(text, row + 1, edit.preferred_col);
        if (!extend) r.anchor = r.caret;
    }
    edit.block = false;
}

/// Hit-test buffer position from pixel coords inside the text box.
pub fn posFromPoint(
    text: []const u8,
    font: *const Font,
    size: f32,
    origin_x: f32,
    origin_y: f32,
    px: f32,
    py: f32,
    multiline: bool,
) usize {
    const lh = font.lineHeight(size);
    if (!multiline) {
        // single line: binary-ish scan
        var best: usize = 0;
        var best_d: f32 = 1e9;
        var i: usize = 0;
        while (i <= text.len) : (i += 1) {
            const w = font.measure(text[0..i], size).w;
            const d = @abs(origin_x + w - px);
            if (d < best_d) {
                best_d = d;
                best = i;
            }
        }
        return best;
    }
    const row_f = (py - origin_y) / lh;
    const row: usize = if (row_f < 0) 0 else @intFromFloat(row_f);
    // find line
    var r: usize = 0;
    var ls: usize = 0;
    var i: usize = 0;
    while (i < text.len and r < row) : (i += 1) {
        if (text[i] == '\n') {
            r += 1;
            ls = i + 1;
        }
    }
    const le = lineEnd(text, ls);
    const line = text[ls..le];
    var best: usize = ls;
    var best_d: f32 = 1e9;
    i = 0;
    while (i <= line.len) : (i += 1) {
        const w = font.measure(line[0..i], size).w;
        const d = @abs(origin_x + w - px);
        if (d < best_d) {
            best_d = d;
            best = ls + i;
        }
    }
    return best;
}

/// Ctrl+D:
/// 1st: select word nearest caret (if no selection, or selection is not that word)
/// 2nd+: add next identical match as multi-caret selection
pub fn ctrlD(edit: *Edit, text: []const u8) void {
    const p = &edit.carets[0];
    // Resolve word at caret
    const ws = wordStart(text, if (p.caret < text.len) p.caret else p.caret);
    const we = wordEnd(text, p.caret);
    const word_ok = ws < we;

    if (!p.hasSel() or edit.caret_ct == 1) {
        // First press (or only primary caret): ensure word is selected
        if (!p.hasSel() or (word_ok and !(p.lo() == ws and p.hi() == we))) {
            if (word_ok) {
                p.anchor = ws;
                p.caret = we;
                edit.caret_ct = 1;
                return;
            }
            return;
        }
    }
    // Subsequent: match next occurrence of primary selection text
    const sel_lo = p.lo();
    const sel_hi = p.hi();
    if (sel_lo >= sel_hi) return;
    const needle = text[sel_lo..sel_hi];
    var start: usize = 0;
    var i: usize = 0;
    while (i < edit.caret_ct) : (i += 1) {
        start = @max(start, edit.carets[i].hi());
    }
    if (start >= text.len) return;
    if (std.mem.indexOf(u8, text[start..], needle)) |rel| {
        const abs = start + rel;
        if (edit.caret_ct < MaxCarets) {
            edit.carets[edit.caret_ct] = .{ .anchor = abs, .caret = abs + needle.len };
            edit.caret_ct += 1;
        }
    }
}

fn copyText(edit: *Edit, text: []const u8, multiline: bool) []const u8 {
    const p = edit.carets[0];
    if (p.hasSel()) {
        return text[p.lo()..p.hi()];
    }
    // Nothing selected → current line (or whole buffer for single-line)
    if (!multiline) return text;
    const ls = lineStart(text, p.caret);
    var le = lineEnd(text, p.caret);
    if (le < text.len and text[le] == '\n') le += 1;
    return text[ls..le];
}

/// Handle keyboard for an edit session. Only call when field is focused.
pub fn handleKeys(
    edit: *Edit,
    buf: []u8,
    len: *usize,
    input: *Input,
    multiline: bool,
) bool {
    const text = buf[0..len.*];
    var changed = false;
    const shift = input.shift;
    const ctrl = input.ctrl;
    const alt = input.alt;

    // Clipboard / select-all / undo (focused-only; caller gates focus)
    if (ctrl and input.keyPressed(.a)) {
        edit.carets[0] = .{ .anchor = 0, .caret = len.* };
        edit.caret_ct = 1;
        edit.coalesce_typing = false;
        return false;
    }
    if (ctrl and input.keyPressed(.c)) {
        input.requestCopy(copyText(edit, text, multiline));
        return false;
    }
    if (ctrl and input.keyPressed(.x)) {
        const slice = copyText(edit, text, multiline);
        input.requestCopy(slice);
        edit.beforeMutate(buf, len.*, false);
        if (edit.carets[0].hasSel()) {
            changed = deleteSelections(edit, buf, len) or changed;
        } else if (multiline) {
            // cut line
            const ls = lineStart(text, edit.carets[0].caret);
            var le = lineEnd(text, edit.carets[0].caret);
            if (le < len.* and buf[le] == '\n') le += 1;
            deleteRange(buf, len, ls, le);
            edit.carets[0] = .{ .caret = ls, .anchor = ls };
            edit.caret_ct = 1;
            changed = true;
        } else {
            // single-line: cut all
            len.* = 0;
            edit.carets[0] = .{};
            edit.caret_ct = 1;
            changed = true;
        }
        edit.coalesce_typing = false;
        return changed;
    }
    if (ctrl and input.keyPressed(.z)) {
        if (shift) {
            return edit.redo(buf, len);
        } else {
            return edit.undo(buf, len);
        }
    }

    if (input.keyPressed(.left)) {
        moveLeft(edit, text, shift, ctrl);
        edit.coalesce_typing = false;
    }
    if (input.keyPressed(.right)) {
        moveRight(edit, text, shift, ctrl);
        edit.coalesce_typing = false;
    }
    if (multiline and input.keyPressed(.up)) {
        moveUp(edit, text, shift, alt and shift);
        edit.preferred_col = colOf(text, edit.carets[0].caret);
        edit.coalesce_typing = false;
    }
    if (multiline and input.keyPressed(.down)) {
        moveDown(edit, text, shift, alt and shift);
        edit.preferred_col = colOf(text, edit.carets[0].caret);
        edit.coalesce_typing = false;
    }
    if (input.keyPressed(.home)) {
        moveHome(edit, text, shift, ctrl);
        edit.coalesce_typing = false;
    }
    if (input.keyPressed(.end)) {
        moveEnd(edit, text, shift, ctrl);
        edit.coalesce_typing = false;
    }
    if (input.keyPressed(.backspace)) {
        edit.beforeMutate(buf, len.*, false);
        changed = backspace(edit, buf, len) or changed;
        edit.coalesce_typing = false;
    }
    if (input.keyPressed(.delete)) {
        edit.beforeMutate(buf, len.*, false);
        changed = deleteForward(edit, buf, len) or changed;
        edit.coalesce_typing = false;
    }
    // Ctrl+D works on single- and multi-line
    if (ctrl and input.keyPressed(.d)) {
        ctrlD(edit, buf[0..len.*]);
        edit.coalesce_typing = false;
    }
    if (multiline and input.keyPressed(.enter)) {
        edit.beforeMutate(buf, len.*, false);
        changed = insertText(edit, buf, len, "\n") or changed;
        edit.coalesce_typing = false;
    }

    // Typed chars (Ctrl chars never reach text[] thanks to input filter)
    if (!ctrl and input.text_len > 0) {
        edit.beforeMutate(buf, len.*, true);
        changed = insertText(edit, buf, len, input.text[0..input.text_len]) or changed;
    }
    if (input.paste_len > 0) {
        var tmp: [512]u8 = undefined;
        var n: usize = 0;
        for (input.paste[0..input.paste_len]) |ch| {
            if (ch == '\n') {
                if (multiline and n < tmp.len) {
                    tmp[n] = ch;
                    n += 1;
                }
            } else if (ch >= 32 and ch < 127 and n < tmp.len) {
                tmp[n] = ch;
                n += 1;
            }
        }
        if (n > 0) {
            edit.beforeMutate(buf, len.*, false);
            changed = insertText(edit, buf, len, tmp[0..n]) or changed;
        }
        input.paste_len = 0;
        edit.coalesce_typing = false;
    }

    edit.clampAll(len.*);
    return changed;
}

/// Mouse down in field. Returns true if focus should be taken.
pub fn handleMouseDown(
    edit: *Edit,
    text: []const u8,
    font: *const Font,
    size: f32,
    origin_x: f32,
    origin_y: f32,
    mx: f32,
    my: f32,
    multiline: bool,
    now: f64,
    alt: bool,
    shift: bool,
) void {
    const pos = posFromPoint(text, font, size, origin_x, origin_y, mx, my, multiline);

    // click counting (1=caret, 2=word, 3=line) within multi_click window
    const window = input_mod.config.multi_click_s;
    if (now - edit.last_click_time < window and
        @abs(@as(i64, @intCast(pos)) - @as(i64, @intCast(edit.last_click_pos))) <= 2)
    {
        edit.click_count = @min(edit.click_count + 1, 3);
    } else {
        edit.click_count = 1;
    }
    edit.last_click_time = now;
    edit.last_click_pos = pos;
    edit.coalesce_typing = false;

    if (alt and shift and multiline) {
        // block select start
        edit.block = true;
        edit.block_row0 = rowOf(text, pos);
        edit.block_row1 = edit.block_row0;
        edit.block_col0 = colOf(text, pos);
        edit.block_col1 = edit.block_col0;
        edit.carets[0] = .{ .caret = pos, .anchor = pos };
        edit.caret_ct = 1;
        edit.dragging = true;
        return;
    }

    if (edit.click_count == 2) {
        // word select
        const ws = wordStart(text, pos);
        const we = wordEnd(text, pos);
        edit.carets[0] = .{ .anchor = ws, .caret = we };
        edit.caret_ct = 1;
        edit.dragging = true;
    } else if (edit.click_count >= 3 and multiline) {
        // line select
        const ls = lineStart(text, pos);
        var le = lineEnd(text, pos);
        if (le < text.len and text[le] == '\n') le += 1;
        edit.carets[0] = .{ .anchor = ls, .caret = le };
        edit.caret_ct = 1;
        edit.dragging = true;
    } else {
        if (shift) {
            edit.carets[0].caret = pos;
        } else {
            edit.carets[0] = .{ .caret = pos, .anchor = pos };
            edit.caret_ct = 1;
        }
        edit.dragging = true;
        edit.preferred_col = colOf(text, pos);
    }
    edit.block = false;
}

pub fn handleMouseDrag(
    edit: *Edit,
    text: []const u8,
    font: *const Font,
    size: f32,
    origin_x: f32,
    origin_y: f32,
    mx: f32,
    my: f32,
    multiline: bool,
) void {
    if (!edit.dragging) return;
    const pos = posFromPoint(text, font, size, origin_x, origin_y, mx, my, multiline);
    if (edit.block and multiline) {
        edit.block_row1 = rowOf(text, pos);
        edit.block_col1 = colOf(text, pos);
        edit.carets[0].caret = pos;
        return;
    }
    edit.carets[0].caret = pos;
}

pub fn handleMouseUp(edit: *Edit) void {
    edit.dragging = false;
}
