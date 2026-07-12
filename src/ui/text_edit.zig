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
    /// After first Ctrl+D word select, subsequent presses add exact matches.
    ctrl_d_active: bool = false,
    /// Caret index when the current Ctrl+D session began (Esc restores here).
    ctrl_d_origin: usize = 0,
    /// User-resized dimensions for multi-line (0 = use layout default).
    user_w: f32 = 0,
    user_h: f32 = 0,
    /// Resize grip drag. Layout keeps committed `user_w`/`user_h` until release;
    /// `resize_preview_*` drives the live ghost rectangle during the drag.
    resizing: bool = false,
    resize_anchor_x: f32 = 0,
    resize_anchor_y: f32 = 0,
    resize_start_w: f32 = 0,
    resize_start_h: f32 = 0,
    resize_preview_w: f32 = 0,
    resize_preview_h: f32 = 0,

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

/// Word nearest caret (VS Code-style): prefer word under caret, else next, else previous.
pub fn wordAt(text: []const u8, pos: usize) struct { start: usize, end: usize } {
    if (text.len == 0) return .{ .start = 0, .end = 0 };
    const p = @min(pos, text.len);
    if (p < text.len and isWord(text[p])) {
        return .{ .start = wordStart(text, p), .end = wordEnd(text, p) };
    }
    if (p > 0 and isWord(text[p - 1])) {
        return .{ .start = wordStart(text, p - 1), .end = wordEnd(text, p - 1) };
    }
    // seek forward
    var i = p;
    while (i < text.len and !isWord(text[i])) : (i += 1) {}
    if (i < text.len) {
        return .{ .start = wordStart(text, i), .end = wordEnd(text, i) };
    }
    // seek backward
    i = p;
    while (i > 0 and !isWord(text[i - 1])) : (i -= 1) {}
    if (i > 0) {
        return .{ .start = wordStart(text, i - 1), .end = wordEnd(text, i - 1) };
    }
    return .{ .start = p, .end = p };
}

fn isWholeWordBoundary(text: []const u8, lo: usize, hi: usize) bool {
    if (lo > 0 and isWord(text[lo - 1])) return false;
    if (hi < text.len and isWord(text[hi])) return false;
    return true;
}

/// Find next exact substring match of `needle` at/after `start`.
/// When `whole_word`, only match at word boundaries (Ctrl+D after word select).
pub fn findNextMatch(text: []const u8, needle: []const u8, start: usize, whole_word: bool) ?struct { start: usize, end: usize } {
    if (needle.len == 0 or start >= text.len) return null;
    var i = start;
    while (i + needle.len <= text.len) : (i += 1) {
        if (std.mem.eql(u8, text[i .. i + needle.len], needle)) {
            if (!whole_word or isWholeWordBoundary(text, i, i + needle.len)) {
                return .{ .start = i, .end = i + needle.len };
            }
        }
    }
    return null;
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

/// After inserting `n` bytes at `pos`, shift every caret/anchor that was strictly after `pos`.
fn bumpCaretsAfterInsert(edit: *Edit, pos: usize, n: usize, except: usize) void {
    var j: usize = 0;
    while (j < edit.caret_ct) : (j += 1) {
        if (j == except) continue;
        var r = &edit.carets[j];
        if (r.caret > pos) r.caret += n;
        if (r.anchor > pos) r.anchor += n;
    }
}

/// After deleting [lo,hi), shift carets past the hole leftward.
fn bumpCaretsAfterDelete(edit: *Edit, lo: usize, hi: usize, except: usize) void {
    const n = hi - lo;
    var j: usize = 0;
    while (j < edit.caret_ct) : (j += 1) {
        if (j == except) continue;
        var r = &edit.carets[j];
        if (r.caret >= hi) r.caret -= n else if (r.caret > lo) r.caret = lo;
        if (r.anchor >= hi) r.anchor -= n else if (r.anchor > lo) r.anchor = lo;
    }
}

fn sortCaretsBy(edit: *Edit, order: *[MaxCarets]usize, comptime by_lo: bool) void {
    var i: usize = 0;
    while (i < edit.caret_ct) : (i += 1) order[i] = i;
    var a: usize = 0;
    while (a < edit.caret_ct) : (a += 1) {
        var b: usize = a + 1;
        while (b < edit.caret_ct) : (b += 1) {
            const va = if (by_lo) edit.carets[order[a]].lo() else edit.carets[order[a]].caret;
            const vb = if (by_lo) edit.carets[order[b]].lo() else edit.carets[order[b]].caret;
            // ascending (low index first)
            if (va > vb) {
                const t = order[a];
                order[a] = order[b];
                order[b] = t;
            }
        }
    }
}

/// Delete selection(s). Process low→high with caret fixups so multi-caret stays consistent.
pub fn deleteSelections(edit: *Edit, buf: []u8, len: *usize) bool {
    var changed = false;
    var order: [MaxCarets]usize = undefined;
    // High→low so earlier ranges stay valid without fixups on later deletes... 
    // actually use high→low delete + fix remaining carets via bumpCaretsAfterDelete for others.
    sortCaretsBy(edit, &order, true);
    // reverse to high-first
    var i: usize = edit.caret_ct;
    while (i > 0) {
        i -= 1;
        const idx = order[i];
        const r = &edit.carets[idx];
        if (r.hasSel()) {
            const lo = r.lo();
            const hi = r.hi();
            deleteRange(buf, len, lo, hi);
            bumpCaretsAfterDelete(edit, lo, hi, idx);
            r.caret = lo;
            r.anchor = lo;
            changed = true;
        }
    }
    edit.clampAll(len.*);
    return changed;
}

/// Insert `bytes` at every caret. Process high→low and bump other carets when needed
/// so simultaneous multi-caret typing stays in order (not reversed).
pub fn insertText(edit: *Edit, buf: []u8, len: *usize, bytes: []const u8) bool {
    var changed = deleteSelections(edit, buf, len);
    if (bytes.len == 0) return changed;

    var order: [MaxCarets]usize = undefined;
    sortCaretsBy(edit, &order, false);
    // High caret first so earlier positions stay stable; bump higher carets on each insert.
    var i: usize = edit.caret_ct;
    while (i > 0) {
        i -= 1;
        const idx = order[i];
        const r = &edit.carets[idx];
        const pos = r.caret;
        const n = insertAt(buf, len, pos, bytes);
        if (n > 0) {
            bumpCaretsAfterInsert(edit, pos, n, idx);
            r.caret = pos + n;
            r.anchor = r.caret;
            changed = true;
        }
    }
    edit.clampAll(len.*);
    return changed;
}

pub fn backspace(edit: *Edit, buf: []u8, len: *usize) bool {
    if (deleteSelections(edit, buf, len)) {
        mergeCarets(edit);
        return true;
    }
    var order: [MaxCarets]usize = undefined;
    sortCaretsBy(edit, &order, false);
    var changed = false;
    var i: usize = edit.caret_ct;
    while (i > 0) {
        i -= 1;
        const idx = order[i];
        const r = &edit.carets[idx];
        if (r.caret > 0) {
            const lo = r.caret - 1;
            const hi = r.caret;
            deleteRange(buf, len, lo, hi);
            bumpCaretsAfterDelete(edit, lo, hi, idx);
            r.caret = lo;
            r.anchor = lo;
            changed = true;
        }
    }
    edit.clampAll(len.*);
    if (changed) mergeCarets(edit);
    return changed;
}

/// Ctrl+Backspace: delete to previous word boundary (or selection).
pub fn backspaceWord(edit: *Edit, buf: []u8, len: *usize) bool {
    if (deleteSelections(edit, buf, len)) {
        mergeCarets(edit);
        return true;
    }
    const text = buf[0..len.*];
    var order: [MaxCarets]usize = undefined;
    sortCaretsBy(edit, &order, false);
    var changed = false;
    var i: usize = edit.caret_ct;
    while (i > 0) {
        i -= 1;
        const idx = order[i];
        const r = &edit.carets[idx];
        if (r.caret == 0) continue;
        const lo = wordStart(text, r.caret);
        const hi = r.caret;
        if (lo >= hi) continue;
        deleteRange(buf, len, lo, hi);
        bumpCaretsAfterDelete(edit, lo, hi, idx);
        r.caret = lo;
        r.anchor = lo;
        changed = true;
    }
    edit.clampAll(len.*);
    if (changed) mergeCarets(edit);
    return changed;
}

pub fn deleteForward(edit: *Edit, buf: []u8, len: *usize) bool {
    if (deleteSelections(edit, buf, len)) {
        mergeCarets(edit);
        return true;
    }
    var order: [MaxCarets]usize = undefined;
    sortCaretsBy(edit, &order, false);
    var changed = false;
    var i: usize = edit.caret_ct;
    while (i > 0) {
        i -= 1;
        const idx = order[i];
        const r = &edit.carets[idx];
        if (r.caret < len.*) {
            const lo = r.caret;
            const hi = r.caret + 1;
            deleteRange(buf, len, lo, hi);
            bumpCaretsAfterDelete(edit, lo, hi, idx);
            r.anchor = r.caret;
            changed = true;
        }
    }
    edit.clampAll(len.*);
    if (changed) mergeCarets(edit);
    return changed;
}

/// Ctrl+Delete: delete to next word boundary.
pub fn deleteWordForward(edit: *Edit, buf: []u8, len: *usize) bool {
    if (deleteSelections(edit, buf, len)) {
        mergeCarets(edit);
        return true;
    }
    const text = buf[0..len.*];
    var order: [MaxCarets]usize = undefined;
    sortCaretsBy(edit, &order, false);
    var changed = false;
    var i: usize = edit.caret_ct;
    while (i > 0) {
        i -= 1;
        const idx = order[i];
        const r = &edit.carets[idx];
        if (r.caret >= len.*) continue;
        const lo = r.caret;
        const hi = wordEnd(text, r.caret);
        if (lo >= hi) continue;
        deleteRange(buf, len, lo, hi);
        bumpCaretsAfterDelete(edit, lo, hi, idx);
        r.anchor = r.caret;
        changed = true;
    }
    edit.clampAll(len.*);
    if (changed) mergeCarets(edit);
    return changed;
}

/// Collapse carets that share the same caret/anchor position after edits.
pub fn mergeCarets(edit: *Edit) void {
    if (edit.caret_ct <= 1) return;
    var write: usize = 0;
    var i: usize = 0;
    while (i < edit.caret_ct) : (i += 1) {
        const c = edit.carets[i];
        var dup = false;
        var j: usize = 0;
        while (j < write) : (j += 1) {
            if (edit.carets[j].caret == c.caret and edit.carets[j].anchor == c.anchor) {
                dup = true;
                break;
            }
        }
        if (!dup) {
            edit.carets[write] = c;
            write += 1;
        }
    }
    edit.caret_ct = @max(1, write);
}


// --- soft wrap (display only; never mutates buffer) --------------------------

/// One visual row after soft-wrapping. `[start, end)` indexes the original text.
/// Soft wrap does not insert `\n` into the buffer — only real Enter does.
pub const VisualRow = struct {
    start: usize,
    end: usize,
};

pub const MaxSoftRows = MaxSnap;

/// Layout `text` into visual rows. When `max_px` > 0, long hard-lines break at
/// spaces (or mid-word if needed). Original bytes are never modified.
pub fn layoutSoft(
    text: []const u8,
    font: *const Font,
    size: f32,
    max_px: f32,
    out: []VisualRow,
) usize {
    if (out.len == 0) return 0;
    var count: usize = 0;

    const wrap = max_px >= 16;
    var i: usize = 0;
    // Always produce at least one row for empty text.
    if (text.len == 0) {
        out[0] = .{ .start = 0, .end = 0 };
        return 1;
    }

    while (i <= text.len) {
        const para_end = lineEnd(text, i);
        var line_start = i;

        if (line_start == para_end) {
            // Empty hard line (e.g. between \n\n or trailing newline content).
            if (count < out.len) {
                out[count] = .{ .start = line_start, .end = para_end };
                count += 1;
            }
        } else if (!wrap) {
            if (count < out.len) {
                out[count] = .{ .start = line_start, .end = para_end };
                count += 1;
            }
        } else {
            while (line_start < para_end and count < out.len) {
                var last_good: usize = line_start;
                var last_space: ?usize = null;
                var j = line_start;
                while (j < para_end) : (j += 1) {
                    if (text[j] == ' ') last_space = j;
                    const w = font.measure(text[line_start .. j + 1], size).w;
                    if (w <= max_px) {
                        last_good = j + 1;
                    } else break;
                }
                var cut = if (j >= para_end) para_end else (last_space orelse last_good);
                if (cut <= line_start) cut = @min(line_start + 1, para_end);

                out[count] = .{ .start = line_start, .end = cut };
                count += 1;
                line_start = cut;
                // Space that caused the wrap stays in the buffer but is not drawn
                // as the first glyph of the next visual row.
                if (line_start < para_end and text[line_start] == ' ') {
                    line_start += 1;
                }
            }
        }

        if (para_end < text.len and text[para_end] == '\n') {
            i = para_end + 1;
            if (i > text.len) break;
            // Trailing newline with no following content still ends the loop next.
            if (i == text.len) {
                // Document ends with \n → extra empty visual row (like most editors).
                if (count < out.len) {
                    out[count] = .{ .start = i, .end = i };
                    count += 1;
                }
                break;
            }
        } else {
            break;
        }
    }
    if (count == 0 and out.len > 0) {
        out[0] = .{ .start = 0, .end = text.len };
        return 1;
    }
    return count;
}

/// Visual row index for a buffer offset (soft-wrap aware).
pub fn visualRowOf(rows: []const VisualRow, pos: usize) usize {
    if (rows.len == 0) return 0;
    var best: usize = 0;
    var i: usize = 0;
    while (i < rows.len) : (i += 1) {
        const r = rows[i];
        if (pos < r.start) break;
        best = i;
        // pos in [start, end] (end = caret after last char on row)
        if (pos <= r.end) {
            // Prefer this row; if pos is a skipped wrap-space (end < pos < next.start),
            // fall through to keep best as previous then check next.
            if (pos < r.end or i + 1 >= rows.len or rows[i + 1].start > pos) {
                return i;
            }
        }
    }
    return best;
}

/// Buffer offset for visual row + column (column = chars from row start).
pub fn posAtVisualRowCol(rows: []const VisualRow, text: []const u8, vrow: usize, col: usize) usize {
    if (rows.len == 0) return 0;
    const ri = @min(vrow, rows.len - 1);
    const r = rows[ri];
    const max_col = r.end - r.start;
    _ = text;
    return r.start + @min(col, max_col);
}

/// Count visual rows (for scroll height).
pub fn countSoftRows(text: []const u8, font: *const Font, size: f32, max_px: f32) usize {
    var rows: [MaxSoftRows]VisualRow = undefined;
    return layoutSoft(text, font, size, max_px, rows[0..]);
}

/// Pixel caret position (origin-relative top-left of glyph cell).
pub fn caretDrawPos(
    text: []const u8,
    font: *const Font,
    size: f32,
    pos: usize,
    rows: []const VisualRow,
) struct { x: f32, row: usize } {
    const ri = visualRowOf(rows, pos);
    const r = rows[ri];
    const p = @min(pos, r.end);
    const pre = text[r.start..p];
    return .{ .x = font.measure(pre, size).w, .row = ri };
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

pub fn moveUp(edit: *Edit, text: []const u8, extend: bool, font: ?*const Font, size: f32, wrap_px: f32) void {
    var rows_buf: [MaxSoftRows]VisualRow = undefined;
    const rows: []const VisualRow = if (font) |f| blk: {
        const n = layoutSoft(text, f, size, wrap_px, rows_buf[0..]);
        break :blk rows_buf[0..n];
    } else rows_buf[0..0];

    var i: usize = 0;
    while (i < edit.caret_ct) : (i += 1) {
        var r = &edit.carets[i];
        if (rows.len > 0) {
            const vr = visualRowOf(rows, r.caret);
            if (vr == 0) {
                r.caret = rows[0].start;
            } else {
                r.caret = posAtVisualRowCol(rows, text, vr - 1, edit.preferred_col);
            }
        } else {
            const row = rowOf(text, r.caret);
            if (row == 0) {
                r.caret = 0;
            } else {
                r.caret = posAtRowCol(text, row - 1, edit.preferred_col);
            }
        }
        if (!extend) r.anchor = r.caret;
    }
    edit.block = false;
}

pub fn moveDown(edit: *Edit, text: []const u8, extend: bool, font: ?*const Font, size: f32, wrap_px: f32) void {
    var rows_buf: [MaxSoftRows]VisualRow = undefined;
    const rows: []const VisualRow = if (font) |f| blk: {
        const n = layoutSoft(text, f, size, wrap_px, rows_buf[0..]);
        break :blk rows_buf[0..n];
    } else rows_buf[0..0];

    var i: usize = 0;
    while (i < edit.caret_ct) : (i += 1) {
        var r = &edit.carets[i];
        if (rows.len > 0) {
            const vr = visualRowOf(rows, r.caret);
            if (vr + 1 >= rows.len) {
                r.caret = rows[rows.len - 1].end;
            } else {
                r.caret = posAtVisualRowCol(rows, text, vr + 1, edit.preferred_col);
            }
        } else {
            const row = rowOf(text, r.caret);
            r.caret = posAtRowCol(text, row + 1, edit.preferred_col);
        }
        if (!extend) r.anchor = r.caret;
    }
    edit.block = false;
}

fn hasCaretAt(edit: *const Edit, pos: usize) bool {
    var i: usize = 0;
    while (i < edit.caret_ct) : (i += 1) {
        if (edit.carets[i].caret == pos or edit.carets[i].anchor == pos) return true;
        if (edit.carets[i].hasSel() and pos >= edit.carets[i].lo() and pos < edit.carets[i].hi()) return true;
    }
    return false;
}

/// Alt+Shift+Up/Down (or Ctrl+Alt+Up/Down): add a caret on the next visual line
/// above/below the current extreme, at the preferred column
/// (VS Code “Add Cursor Above/Below”).
///
/// Uses soft-wrap visual rows when `font` + `wrap_px` are set so multi-caret
/// still works across hard newlines *and* soft-wrapped display lines. Buffer
/// is never mutated.
pub fn addCaretVertical(
    edit: *Edit,
    text: []const u8,
    delta_row: i32,
    font: ?*const Font,
    size: f32,
    wrap_px: f32,
) void {
    if (edit.caret_ct == 0 or delta_row == 0) return;
    if (edit.caret_ct >= MaxCarets) return;

    var rows_buf: [MaxSoftRows]VisualRow = undefined;
    const rows: []const VisualRow = if (font) |f| blk: {
        const n = layoutSoft(text, f, size, wrap_px, rows_buf[0..]);
        break :blk rows_buf[0..n];
    } else blk: {
        // Hard-line fallback (one visual row per hard line).
        var count: usize = 0;
        var i: usize = 0;
        while (i <= text.len and count < rows_buf.len) {
            const le = lineEnd(text, i);
            rows_buf[count] = .{ .start = i, .end = le };
            count += 1;
            if (le < text.len and text[le] == '\n') {
                i = le + 1;
                if (i == text.len) {
                    // trailing newline → empty last row
                    if (count < rows_buf.len) {
                        rows_buf[count] = .{ .start = i, .end = i };
                        count += 1;
                    }
                    break;
                }
            } else break;
        }
        if (count == 0) {
            rows_buf[0] = .{ .start = 0, .end = text.len };
            count = 1;
        }
        break :blk rows_buf[0..count];
    };
    if (rows.len == 0) return;

    // Session start: remember origin for Esc; lock column from primary visual row.
    if (edit.caret_ct == 1) {
        edit.ctrl_d_origin = edit.carets[0].caret;
        const vr0 = visualRowOf(rows, edit.carets[0].caret);
        const rs = rows[vr0].start;
        const caret = edit.carets[0].caret;
        edit.preferred_col = if (caret >= rs) caret - rs else 0;
        // Collapse primary selection so we place a bare caret column.
        edit.carets[0].anchor = edit.carets[0].caret;
    }

    var extreme_row: usize = visualRowOf(rows, edit.carets[0].caret);
    var i: usize = 1;
    while (i < edit.caret_ct) : (i += 1) {
        const r = visualRowOf(rows, edit.carets[i].caret);
        if (delta_row < 0) {
            extreme_row = @min(extreme_row, r);
        } else {
            extreme_row = @max(extreme_row, r);
        }
    }

    var new_row: usize = extreme_row;
    if (delta_row < 0) {
        if (extreme_row == 0) return;
        new_row = extreme_row - 1;
    } else {
        if (extreme_row + 1 >= rows.len) return;
        new_row = extreme_row + 1;
    }

    const pos = posAtVisualRowCol(rows, text, new_row, edit.preferred_col);
    if (hasCaretAt(edit, pos)) return;

    edit.carets[edit.caret_ct] = .{ .caret = pos, .anchor = pos };
    edit.caret_ct += 1;
    edit.block = false;
}

/// Hit-test buffer position from pixel coords inside the text box.
/// `wrap_px` > 0 enables soft-wrap aware hit testing (multiline only).
pub fn posFromPoint(
    text: []const u8,
    font: *const Font,
    size: f32,
    origin_x: f32,
    origin_y: f32,
    px: f32,
    py: f32,
    multiline: bool,
    wrap_px: f32,
) usize {
    const lh = font.lineHeight(size);
    if (!multiline) {
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

    var rows_buf: [MaxSoftRows]VisualRow = undefined;
    const n = layoutSoft(text, font, size, wrap_px, rows_buf[0..]);
    const rows = rows_buf[0..n];
    if (rows.len == 0) return 0;

    const row_f = (py - origin_y) / lh;
    var row: usize = if (row_f < 0) 0 else @intFromFloat(row_f);
    if (row >= rows.len) row = rows.len - 1;

    const vr = rows[row];
    const line = text[vr.start..vr.end];
    var best: usize = vr.start;
    var best_d: f32 = 1e9;
    var i: usize = 0;
    while (i <= line.len) : (i += 1) {
        const w = font.measure(line[0..i], size).w;
        const d = @abs(origin_x + w - px);
        if (d < best_d) {
            best_d = d;
            best = vr.start + i;
        }
    }
    return best;
}

/// Ctrl+D (VS Code “Add Next Occurrence”):
/// - No selection: select word nearest caret (session starts; does not add another match yet).
/// - Already have a selection (mouse/shift or prior Ctrl+D): add next exact match of that
///   selection (whole-word when the needle sits on word boundaries). Repeat until no matches.
/// Esc ends the session: single caret at the pre-session position, no selection.
pub fn ctrlD(edit: *Edit, text: []const u8) void {
    const p = &edit.carets[0];

    // Remember where the caret was when this Ctrl+D session began.
    if (!edit.ctrl_d_active) {
        edit.ctrl_d_origin = p.caret;
    }

    // No selection yet → select nearest word only (like a first press with empty sel).
    if (!p.hasSel()) {
        const w = wordAt(text, p.caret);
        if (w.start < w.end) {
            p.anchor = w.start;
            p.caret = w.end;
            edit.caret_ct = 1;
            edit.ctrl_d_active = true;
        }
        return;
    }

    // Selection already exists (user made it, or prior Ctrl+D selected the word):
    // treat as “add next occurrence” of the primary selection text.
    const sel_lo = p.lo();
    const sel_hi = p.hi();
    if (sel_lo >= sel_hi) return;
    const needle = text[sel_lo..sel_hi];
    const whole = isWholeWordBoundary(text, sel_lo, sel_hi);

    var start: usize = 0;
    var i: usize = 0;
    while (i < edit.caret_ct) : (i += 1) {
        start = @max(start, edit.carets[i].hi());
    }
    if (findNextMatch(text, needle, start, whole)) |m| {
        if (edit.caret_ct < MaxCarets) {
            edit.carets[edit.caret_ct] = .{ .anchor = m.start, .caret = m.end };
            edit.caret_ct += 1;
        }
    }
    edit.ctrl_d_active = true;
}

/// End multi-caret / Ctrl+D / Alt+Shift cursor session (Esc):
/// one caret at session origin, no selection.
pub fn collapseCarets(edit: *Edit) void {
    const restore = edit.ctrl_d_active or edit.caret_ct > 1;
    const pos = if (restore) edit.ctrl_d_origin else edit.carets[0].caret;
    edit.caret_ct = 1;
    edit.carets[0] = .{ .caret = pos, .anchor = pos };
    edit.ctrl_d_active = false;
    edit.block = false;
}

/// Ctrl+Shift+L: select all exact occurrences of primary selection / word.
pub fn selectAllOccurrences(edit: *Edit, text: []const u8) void {
    const p = &edit.carets[0];
    if (!p.hasSel()) {
        const w = wordAt(text, p.caret);
        if (w.start >= w.end) return;
        p.anchor = w.start;
        p.caret = w.end;
    }
    const needle = text[p.lo()..p.hi()];
    if (needle.len == 0) return;
    const whole = isWholeWordBoundary(text, p.lo(), p.hi());
    edit.caret_ct = 0;
    var start: usize = 0;
    while (findNextMatch(text, needle, start, whole)) |m| {
        if (edit.caret_ct >= MaxCarets) break;
        edit.carets[edit.caret_ct] = .{ .anchor = m.start, .caret = m.end };
        edit.caret_ct += 1;
        start = m.end;
    }
    if (edit.caret_ct == 0) edit.caret_ct = 1;
    edit.ctrl_d_active = true;
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
/// `wrap_px` > 0 enables soft word-wrap for vertical motion (display-only; buffer unchanged).
pub fn handleKeys(
    edit: *Edit,
    buf: []u8,
    len: *usize,
    input: *Input,
    multiline: bool,
    wrap_px: f32,
    font: ?*const Font,
    font_size: f32,
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
    if (input.keyPressed(.escape)) {
        if (edit.caret_ct > 1 or edit.ctrl_d_active) {
            collapseCarets(edit);
            return false;
        }
    }
    if (ctrl and shift and input.keyPressed(.l)) {
        selectAllOccurrences(edit, text);
        edit.coalesce_typing = false;
        return false;
    }

    if (input.keyPressed(.left)) {
        moveLeft(edit, text, shift, ctrl);
        edit.coalesce_typing = false;
        edit.ctrl_d_active = false;
    }
    if (input.keyPressed(.right)) {
        moveRight(edit, text, shift, ctrl);
        edit.coalesce_typing = false;
        edit.ctrl_d_active = false;
    }
    // Add Cursor Above/Below: Alt+Shift+↑/↓ or Ctrl+Alt+↑/↓ (VS Code-ish).
    const add_cursor_vert = (alt and shift) or (ctrl and alt);
    if (multiline and input.keyPressed(.up)) {
        if (add_cursor_vert) {
            addCaretVertical(edit, text, -1, font, font_size, wrap_px);
        } else {
            moveUp(edit, text, shift, font, font_size, wrap_px);
            edit.ctrl_d_active = false;
        }
        edit.coalesce_typing = false;
    }
    if (multiline and input.keyPressed(.down)) {
        if (add_cursor_vert) {
            addCaretVertical(edit, text, 1, font, font_size, wrap_px);
        } else {
            moveDown(edit, text, shift, font, font_size, wrap_px);
            edit.ctrl_d_active = false;
        }
        edit.coalesce_typing = false;
    }
    if (input.keyPressed(.home)) {
        moveHome(edit, text, shift, ctrl);
        edit.coalesce_typing = false;
        edit.ctrl_d_active = false;
    }
    if (input.keyPressed(.end)) {
        moveEnd(edit, text, shift, ctrl);
        edit.coalesce_typing = false;
        edit.ctrl_d_active = false;
    }
    if (input.keyPressed(.backspace)) {
        edit.beforeMutate(buf, len.*, false);
        if (ctrl) {
            changed = backspaceWord(edit, buf, len) or changed;
        } else {
            changed = backspace(edit, buf, len) or changed;
        }
        edit.coalesce_typing = false;
    }
    if (input.keyPressed(.delete)) {
        edit.beforeMutate(buf, len.*, false);
        if (ctrl) {
            changed = deleteWordForward(edit, buf, len) or changed;
        } else {
            changed = deleteForward(edit, buf, len) or changed;
        }
        edit.coalesce_typing = false;
    }
    // Ctrl+D works on single- and multi-line
    if (ctrl and input.keyPressed(.d)) {
        ctrlD(edit, buf[0..len.*]);
        edit.coalesce_typing = false;
    }
    // Enter → hard line break at every caret (including mid-line)
    if (multiline and input.keyPressed(.enter)) {
        edit.beforeMutate(buf, len.*, false);
        changed = insertText(edit, buf, len, "\n") or changed;
        edit.coalesce_typing = false;
        edit.ctrl_d_active = false;
    }

    // Typed chars (Ctrl chars never reach text[] thanks to input filter)
    if (!ctrl and input.text_len > 0) {
        // Filter out any accidental control bytes; allow printable only
        var tmp: [32]u8 = undefined;
        var tn: usize = 0;
        for (input.text[0..input.text_len]) |ch| {
            if (ch >= 32 and ch < 127 and tn < tmp.len) {
                tmp[tn] = ch;
                tn += 1;
            }
        }
        if (tn > 0) {
            edit.beforeMutate(buf, len.*, true);
            changed = insertText(edit, buf, len, tmp[0..tn]) or changed;
        }
    }
    if (input.paste_len > 0) {
        var tmp: [512]u8 = undefined;
        var n: usize = 0;
        for (input.paste[0..input.paste_len]) |ch| {
            if (ch == '\n' or ch == '\r') {
                if (multiline and n < tmp.len) {
                    tmp[n] = '\n';
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

    // Soft wrap is display-only — never mutate the buffer here.

    edit.clampAll(len.*);
    return changed;
}

/// Mouse down — only call on mousePressed (not release/clicked).
/// 1st click: place caret · 2nd (within multi_click_s, same area): word · 3rd: line
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
    wrap_px: f32,
    now: f64,
    alt: bool,
    shift: bool,
) void {
    const pos = posFromPoint(text, font, size, origin_x, origin_y, mx, my, multiline, wrap_px);
    const row = rowOf(text, pos);
    const col = colOf(text, pos);

    // Multi-click: same line+col (±1 col) within debounce window
    const window = input_mod.config.multi_click_s;
    const last_row = rowOf(text, edit.last_click_pos);
    const last_col = colOf(text, edit.last_click_pos);
    const same_spot = (row == last_row and @abs(@as(i64, @intCast(col)) - @as(i64, @intCast(last_col))) <= 1);
    if (now - edit.last_click_time < window and same_spot) {
        edit.click_count = @min(edit.click_count + 1, 3);
    } else {
        edit.click_count = 1;
    }
    edit.last_click_time = now;
    edit.last_click_pos = pos;
    edit.coalesce_typing = false;
    edit.ctrl_d_active = false;

    if (alt and shift and multiline) {
        edit.block = true;
        edit.block_row0 = row;
        edit.block_row1 = row;
        edit.block_col0 = col;
        edit.block_col1 = col;
        edit.carets[0] = .{ .caret = pos, .anchor = pos };
        edit.caret_ct = 1;
        edit.dragging = true;
        return;
    }

    // Alt+click: add secondary caret (VS Code / JetBrains style)
    if (alt and !shift and multiline) {
        if (edit.caret_ct == 1 and !edit.ctrl_d_active) {
            edit.ctrl_d_origin = edit.carets[0].caret;
        }
        if (edit.caret_ct < MaxCarets) {
            edit.carets[edit.caret_ct] = .{ .caret = pos, .anchor = pos };
            edit.caret_ct += 1;
        }
        edit.dragging = false;
        return;
    }

    if (edit.click_count == 2) {
        const w = wordAt(text, pos);
        edit.carets[0] = .{ .anchor = w.start, .caret = w.end };
        edit.caret_ct = 1;
        edit.dragging = true; // double-click drag extends by word (simplified: free drag)
    } else if (edit.click_count >= 3 and multiline) {
        const ls = lineStart(text, pos);
        var le = lineEnd(text, pos);
        if (le < text.len and text[le] == '\n') le += 1;
        edit.carets[0] = .{ .anchor = ls, .caret = le };
        edit.caret_ct = 1;
        edit.dragging = true;
    } else {
        // click 1: place caret (or shift-extend)
        if (shift) {
            edit.carets[0].caret = pos;
            edit.caret_ct = 1;
        } else {
            edit.carets[0] = .{ .caret = pos, .anchor = pos };
            edit.caret_ct = 1;
        }
        edit.dragging = true;
        edit.preferred_col = col;
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
    wrap_px: f32,
) void {
    if (!edit.dragging) return;
    const pos = posFromPoint(text, font, size, origin_x, origin_y, mx, my, multiline, wrap_px);
    if (edit.block and multiline) {
        edit.block_row1 = rowOf(text, pos);
        edit.block_col1 = colOf(text, pos);
        edit.carets[0].caret = pos;
        return;
    }
    // Double-click drag: expand by whole words from the original click seed.
    // (Without this, every drag frame would set caret to the mid-word click pos and
    // shrink a full-word selection to "start..click", e.g. "hams" of "hamster".)
    if (edit.click_count == 2) {
        const seed = edit.last_click_pos;
        const a = wordAt(text, seed);
        const b = wordAt(text, pos);
        const start = @min(a.start, b.start);
        const end = @max(a.end, b.end);
        edit.carets[0] = .{ .anchor = start, .caret = end };
        edit.caret_ct = 1;
        return;
    }
    // Triple-click drag: expand by whole lines.
    if (edit.click_count >= 3 and multiline) {
        const seed = edit.last_click_pos;
        const ls0 = lineStart(text, seed);
        var le0 = lineEnd(text, seed);
        if (le0 < text.len and text[le0] == '\n') le0 += 1;
        const ls1 = lineStart(text, pos);
        var le1 = lineEnd(text, pos);
        if (le1 < text.len and text[le1] == '\n') le1 += 1;
        edit.carets[0] = .{
            .anchor = @min(ls0, ls1),
            .caret = @max(le0, le1),
        };
        edit.caret_ct = 1;
        return;
    }
    edit.carets[0].caret = pos;
}

pub fn handleMouseUp(edit: *Edit) void {
    edit.dragging = false;
}

// --- tests ------------------------------------------------------------------

test "insertText mid-line newline" {
    var buf: [64]u8 = undefined;
    const src = "hello world";
    @memcpy(buf[0..src.len], src);
    var len: usize = src.len;
    var edit: Edit = .{};
    edit.carets[0] = .{ .caret = 5, .anchor = 5 }; // after "hello"
    try std.testing.expect(insertText(&edit, &buf, &len, "\n"));
    try std.testing.expectEqualStrings("hello\n world", buf[0..len]);
    try std.testing.expectEqual(@as(usize, 6), edit.carets[0].caret);
}

test "multi-caret insert not reversed" {
    // Simulate Ctrl+D on two "haha" occurrences, then type "honeybee"
    var buf: [128]u8 = undefined;
    const src = "say haha then haha end";
    @memcpy(buf[0..src.len], src);
    var len: usize = src.len;
    var edit: Edit = .{};
    // "haha" at 4..8 and 14..18
    edit.carets[0] = .{ .anchor = 4, .caret = 8 };
    edit.carets[1] = .{ .anchor = 14, .caret = 18 };
    edit.caret_ct = 2;

    // Type one char at a time (as key events do)
    for ("honeybee") |ch| {
        const s = [_]u8{ch};
        try std.testing.expect(insertText(&edit, &buf, &len, &s));
    }
    try std.testing.expectEqualStrings("say honeybee then honeybee end", buf[0..len]);
    try std.testing.expectEqual(@as(usize, 2), edit.caret_ct);
    // Both carets after their respective inserts
    try std.testing.expectEqual(@as(usize, 12), edit.carets[0].caret);
    try std.testing.expectEqual(@as(usize, 26), edit.carets[1].caret);
}

test "multi-caret whole-string insert" {
    var buf: [128]u8 = undefined;
    const src = "aa X bb X cc";
    @memcpy(buf[0..src.len], src);
    var len: usize = src.len;
    var edit: Edit = .{};
    edit.carets[0] = .{ .anchor = 3, .caret = 4 }; // first X
    edit.carets[1] = .{ .anchor = 8, .caret = 9 }; // second X
    edit.caret_ct = 2;
    try std.testing.expect(insertText(&edit, &buf, &len, "YY"));
    try std.testing.expectEqualStrings("aa YY bb YY cc", buf[0..len]);
}

test "ctrlD: no selection selects word only" {
    const text = "say haha then haha end";
    var edit: Edit = .{};
    edit.carets[0] = .{ .caret = 6, .anchor = 6 }; // inside first haha
    ctrlD(&edit, text);
    try std.testing.expectEqual(@as(usize, 1), edit.caret_ct);
    try std.testing.expectEqual(@as(usize, 4), edit.carets[0].lo());
    try std.testing.expectEqual(@as(usize, 8), edit.carets[0].hi());
    try std.testing.expect(edit.ctrl_d_active);
}

test "ctrlD: existing selection adds next match on first press" {
    const text = "say haha then haha end";
    var edit: Edit = .{};
    // User already selected first "haha" (e.g. double-click / drag)
    edit.carets[0] = .{ .anchor = 4, .caret = 8 };
    edit.ctrl_d_active = false;
    ctrlD(&edit, text);
    try std.testing.expectEqual(@as(usize, 2), edit.caret_ct);
    try std.testing.expectEqual(@as(usize, 4), edit.carets[0].lo());
    try std.testing.expectEqual(@as(usize, 8), edit.carets[0].hi());
    try std.testing.expectEqual(@as(usize, 14), edit.carets[1].lo());
    try std.testing.expectEqual(@as(usize, 18), edit.carets[1].hi());
    try std.testing.expect(edit.ctrl_d_active);
}

test "ctrlD Esc restores origin caret and clears selection" {
    const text = "say haha then haha end";
    var edit: Edit = .{};
    edit.carets[0] = .{ .caret = 6, .anchor = 6 }; // middle of first haha
    ctrlD(&edit, text); // select word
    try std.testing.expect(edit.carets[0].hasSel());
    try std.testing.expectEqual(@as(usize, 6), edit.ctrl_d_origin);
    ctrlD(&edit, text); // add next
    try std.testing.expectEqual(@as(usize, 2), edit.caret_ct);
    collapseCarets(&edit);
    try std.testing.expectEqual(@as(usize, 1), edit.caret_ct);
    try std.testing.expect(!edit.carets[0].hasSel());
    try std.testing.expectEqual(@as(usize, 6), edit.carets[0].caret);
    try std.testing.expect(!edit.ctrl_d_active);
}

test "alt-shift add caret above/below and Esc restores" {
    const text = "abc def ghi jkl\nabc def zhi jkl\nabc def xhi jkl";
    const z_pos = std.mem.indexOfScalar(u8, text, 'z').?;
    const g_pos = std.mem.indexOfScalar(u8, text, 'g').?;
    const x_pos = std.mem.indexOfScalar(u8, text, 'x').?;
    var edit: Edit = .{};
    edit.carets[0] = .{ .caret = z_pos, .anchor = z_pos };
    // null font → hard-line visual rows (no soft wrap)
    addCaretVertical(&edit, text, -1, null, 1, 0);
    try std.testing.expectEqual(@as(usize, 2), edit.caret_ct);
    try std.testing.expectEqual(z_pos, edit.carets[0].caret);
    try std.testing.expectEqual(g_pos, edit.carets[1].caret);
    try std.testing.expectEqual(z_pos, edit.ctrl_d_origin);

    edit = .{};
    edit.carets[0] = .{ .caret = z_pos, .anchor = z_pos };
    addCaretVertical(&edit, text, 1, null, 1, 0);
    try std.testing.expectEqual(@as(usize, 2), edit.caret_ct);
    try std.testing.expectEqual(z_pos, edit.carets[0].caret);
    try std.testing.expectEqual(x_pos, edit.carets[1].caret);

    collapseCarets(&edit);
    try std.testing.expectEqual(@as(usize, 1), edit.caret_ct);
    try std.testing.expectEqual(z_pos, edit.carets[0].caret);
    try std.testing.expect(!edit.carets[0].hasSel());
}
