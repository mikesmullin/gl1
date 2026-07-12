//! Box / flex / simple table layout.
const std = @import("std");
const dom = @import("dom.zig");

pub const Size = struct { w: f32, h: f32 };
pub const MeasureFn = *const fn (text: []const u8, font_size: f32) Size;

pub fn layout(doc: *dom.Document, content_w: f32, measure: MeasureFn) void {
    doc.layout_w = content_w;
    // Prefer body if present
    const body = findBody(doc.root) orelse doc.root;
    body.box = .{ .x = 0, .y = 0, .w = content_w, .h = 0 };
    const h = layoutBlock(body, content_w, 0, 0, measure);
    body.box.h = h;
    doc.content_h = h;
}

fn findBody(n: *dom.Node) ?*dom.Node {
    if (n.kind == .element and std.mem.eql(u8, n.tag, "body")) return n;
    for (n.children.items) |c| {
        if (findBody(c)) |b| return b;
    }
    // fallback: first element child of document
    if (n.kind == .document) {
        for (n.children.items) |c| {
            if (c.kind == .element) {
                if (std.mem.eql(u8, c.tag, "html")) {
                    for (c.children.items) |gc| {
                        if (gc.kind == .element and std.mem.eql(u8, gc.tag, "body")) return gc;
                    }
                    return c;
                }
                return c;
            }
        }
    }
    return null;
}

fn resolveWidth(st: *const dom.ComputedStyle, containing: f32) f32 {
    if (st.width) |w| return w;
    if (st.width_pct) |p| return containing * (p / 100.0);
    return containing;
}

fn layoutBlock(n: *dom.Node, containing_w: f32, x: f32, y: f32, measure: MeasureFn) f32 {
    if (n.kind == .text) {
        const m = measure(n.text, n.style.font_size);
        n.box = .{ .x = x, .y = y, .w = m.w, .h = m.h };
        return m.h;
    }
    if (n.style.display == .none) {
        n.box = .{ .x = x, .y = y, .w = 0, .h = 0 };
        return 0;
    }

    const st = n.style;
    const mt = st.margin[0];
    const mr = st.margin[1];
    const mb = st.margin[2];
    const ml = st.margin[3];
    const pt = st.padding[0];
    const pr = st.padding[1];
    const pb = st.padding[2];
    const pl = st.padding[3];
    const bw = st.border_w;

    var border_box_w = resolveWidth(&st, containing_w - ml - mr);
    // when width not set, fill containing
    if (st.width == null and st.width_pct == null) {
        border_box_w = containing_w - ml - mr;
    }
    border_box_w = @max(0, border_box_w);
    const content_w = @max(0, border_box_w - pl - pr - 2 * bw);

    const ox = x + ml;
    const oy = y + mt;
    n.box.x = ox;
    n.box.y = oy;
    n.box.w = border_box_w;

    // Replaced elements
    if (n.kind == .element and (std.mem.eql(u8, n.tag, "img") or std.mem.eql(u8, n.tag, "video") or std.mem.eql(u8, n.tag, "audio"))) {
        var iw: f32 = n.intrinsic_w;
        var ih: f32 = n.intrinsic_h;
        if (n.attr("width")) |ws| {
            if (std.fmt.parseFloat(f32, ws) catch null) |v| iw = v;
        }
        if (n.attr("height")) |hs| {
            if (std.fmt.parseFloat(f32, hs) catch null) |v| ih = v;
        }
        if (st.width) |w| iw = w;
        if (st.height) |h| ih = h;
        if (iw <= 0) iw = if (std.mem.eql(u8, n.tag, "audio")) content_w else 160;
        if (ih <= 0) ih = if (std.mem.eql(u8, n.tag, "audio")) 36 else if (std.mem.eql(u8, n.tag, "video")) 180 else 120;
        n.box.w = iw + pl + pr + 2 * bw;
        n.box.h = ih + pt + pb + 2 * bw + mb + mt;
        // store content size in box for paint (full border box)
        return n.box.h;
    }

    if (std.mem.eql(u8, n.tag, "br")) {
        const lh = st.font_size * st.line_height;
        n.box.w = 0;
        n.box.h = lh;
        return lh + mb + mt;
    }
    if (std.mem.eql(u8, n.tag, "hr")) {
        const h = st.height orelse 1;
        n.box.h = h + pt + pb + 2 * bw;
        return n.box.h + mt + mb;
    }

    var content_h: f32 = 0;

    if (st.display == .flex) {
        content_h = layoutFlex(n, content_w, ox + pl + bw, oy + pt + bw, measure);
    } else if (st.display == .table) {
        content_h = layoutTable(n, content_w, ox + pl + bw, oy + pt + bw, measure);
    } else {
        // block flow with simple inline line boxes
        content_h = layoutFlow(n, content_w, ox + pl + bw, oy + pt + bw, measure);
    }

    if (st.height) |fixed| content_h = fixed;
    if (st.height_pct) |p| content_h = containing_w * (p / 100.0); // weak

    n.box.h = content_h + pt + pb + 2 * bw;
    return n.box.h + mt + mb;
}

fn layoutFlow(n: *dom.Node, content_w: f32, cx: f32, cy: f32, measure: MeasureFn) f32 {
    var y: f32 = cy;
    var line_x: f32 = cx;
    var line_y: f32 = cy;
    var line_h: f32 = 0;
    var max_y: f32 = cy;

    const is_list = n.kind == .element and (std.mem.eql(u8, n.tag, "ul") or std.mem.eql(u8, n.tag, "ol"));
    const ordered = n.kind == .element and std.mem.eql(u8, n.tag, "ol");
    var li_index: u32 = 0;

    const finishLine = struct {
        fn f(line_x_p: *f32, line_y_p: *f32, line_h_p: *f32, max_y_p: *f32, cx0: f32) void {
            if (line_h_p.* > 0) {
                line_y_p.* += line_h_p.*;
                max_y_p.* = @max(max_y_p.*, line_y_p.*);
                line_x_p.* = cx0;
                line_h_p.* = 0;
            }
        }
    }.f;

    for (n.children.items) |c| {
        if (c.style.display == .none) continue;

        // Number list items in document order before laying them out.
        if (is_list and c.kind == .element and std.mem.eql(u8, c.tag, "li")) {
            li_index += 1;
            c.list_index = li_index;
            c.list_ordered = ordered;
        }

        if (c.kind == .text or c.style.display == .inline_) {
            // inline
            if (c.kind == .element and std.mem.eql(u8, c.tag, "br")) {
                finishLine(&line_x, &line_y, &line_h, &max_y, cx);
                line_y += c.style.font_size * c.style.line_height * 0.5;
                max_y = @max(max_y, line_y);
                continue;
            }
            if (c.kind == .element and std.mem.eql(u8, c.tag, "img")) {
                _ = layoutBlock(c, content_w, line_x, line_y, measure);
                if (line_x + c.box.w > cx + content_w and line_x > cx) {
                    finishLine(&line_x, &line_y, &line_h, &max_y, cx);
                    c.box.x = line_x;
                    c.box.y = line_y;
                }
                line_x += c.box.w + 4;
                line_h = @max(line_h, c.box.h);
                max_y = @max(max_y, line_y + line_h);
                continue;
            }

            const text = if (c.kind == .text) c.text else collectInlineText(c);
            const font_sz = c.style.font_size;
            // word wrap
            var rest = text;
            while (rest.len > 0) {
                const m_all = measure(rest, font_sz);
                const avail = cx + content_w - line_x;
                if (m_all.w <= avail or line_x <= cx + 0.5) {
                    // fits or forced
                    var take = rest;
                    if (m_all.w > content_w) {
                        // hard break by chars
                        take = takeChars(rest, content_w, font_sz, measure);
                    } else if (m_all.w > avail and line_x > cx + 0.5) {
                        finishLine(&line_x, &line_y, &line_h, &max_y, cx);
                        continue;
                    }
                    const m = measure(take, font_sz);
                    // only assign box on first fragment for simplicity — for text nodes set final
                    if (c.kind == .text and take.ptr == text.ptr) {
                        c.box = .{ .x = line_x, .y = line_y, .w = m.w, .h = m.h };
                    } else if (c.kind == .text) {
                        // multi-line: expand box
                        c.box.w = @max(c.box.w, m.w);
                        c.box.h = line_y + m.h - c.box.y;
                        if (c.box.y == 0 and c.box.x == 0) c.box = .{ .x = line_x, .y = line_y, .w = m.w, .h = m.h };
                    } else {
                        c.box = .{ .x = line_x, .y = line_y, .w = m.w, .h = m.h };
                        // layout children of inline element as none
                        for (c.children.items) |gc| {
                            if (gc.kind == .text) gc.box = c.box;
                        }
                    }
                    line_x += m.w;
                    line_h = @max(line_h, m.h);
                    max_y = @max(max_y, line_y + line_h);
                    if (take.len >= rest.len) break;
                    rest = rest[take.len..];
                    finishLine(&line_x, &line_y, &line_h, &max_y, cx);
                } else {
                    finishLine(&line_x, &line_y, &line_h, &max_y, cx);
                }
            }
        } else {
            // block-level
            finishLine(&line_x, &line_y, &line_h, &max_y, cx);
            y = max_y;
            const used = layoutBlock(c, content_w, cx, y, measure);
            y += used;
            max_y = y;
            line_y = y;
            line_x = cx;
            line_h = 0;
        }
    }
    finishLine(&line_x, &line_y, &line_h, &max_y, cx);
    return @max(0, max_y - cy);
}

fn takeChars(text: []const u8, max_w: f32, font_sz: f32, measure: MeasureFn) []const u8 {
    if (text.len == 0) return text;
    var lo: usize = 1;
    var hi: usize = text.len;
    var best: usize = 1;
    while (lo <= hi) {
        const mid = (lo + hi) / 2;
        const m = measure(text[0..mid], font_sz);
        if (m.w <= max_w) {
            best = mid;
            lo = mid + 1;
        } else {
            if (mid == 0) break;
            hi = mid - 1;
        }
    }
    // prefer break at space
    if (best < text.len) {
        if (std.mem.lastIndexOfScalar(u8, text[0..best], ' ')) |sp| {
            if (sp > 0) best = sp + 1;
        }
    }
    return text[0..@max(1, best)];
}

fn collectInlineText(n: *dom.Node) []const u8 {
    // For simple <a>text</a> / <strong>text</strong>
    if (n.children.items.len == 1 and n.children.items[0].kind == .text) {
        return n.children.items[0].text;
    }
    // concatenate first text-ish
    for (n.children.items) |c| {
        if (c.kind == .text) return c.text;
    }
    return n.text;
}

fn layoutFlex(n: *dom.Node, content_w: f32, cx: f32, cy: f32, measure: MeasureFn) f32 {
    const st = n.style;
    const gap = st.gap;
    var kbuf: [64]*dom.Node = undefined;
    var kn: usize = 0;
    for (n.children.items) |c| {
        if (c.style.display == .none) continue;
        if (kn < kbuf.len) {
            kbuf[kn] = c;
            kn += 1;
        }
    }

    if (st.flex_dir == .column) {
        var y = cy;
        for (kbuf[0..kn]) |c| {
            const used = layoutBlock(c, content_w, cx, y, measure);
            y += used + gap;
        }
        if (kn > 0) y -= gap;
        return @max(0, y - cy);
    }

    // row: first pass intrinsic widths
    var widths: [64]f32 = undefined;
    var heights: [64]f32 = undefined;
    var total_fixed: f32 = 0;
    var grow_sum: f32 = 0;
    for (kbuf[0..kn], 0..) |c, i| {
        // tentative layout with max content_w
        const child_cw = if (c.style.width != null or c.style.width_pct != null)
            resolveWidth(&c.style, content_w)
        else
            content_w / @as(f32, @floatFromInt(@max(kn, 1)));
        _ = layoutBlock(c, child_cw, 0, 0, measure);
        widths[i] = c.box.w + c.style.margin[1] + c.style.margin[3];
        heights[i] = c.box.h + c.style.margin[0] + c.style.margin[2];
        total_fixed += widths[i];
        grow_sum += c.style.flex_grow;
    }
    total_fixed += gap * @as(f32, @floatFromInt(if (kn > 1) kn - 1 else 0));
    var extra = content_w - total_fixed;
    if (extra < 0) extra = 0;
    if (grow_sum > 0 and extra > 0) {
        for (kbuf[0..kn], 0..) |c, i| {
            if (c.style.flex_grow > 0) {
                widths[i] += extra * (c.style.flex_grow / grow_sum);
            }
        }
    }

    var x = cx;
    var max_h: f32 = 0;
    // justify
    var total_w: f32 = 0;
    for (widths[0..kn]) |w| total_w += w;
    total_w += gap * @as(f32, @floatFromInt(if (kn > 1) kn - 1 else 0));
    if (st.justify == .center) {
        x = cx + (content_w - total_w) * 0.5;
    } else if (st.justify == .flex_end) {
        x = cx + content_w - total_w;
    }

    for (kbuf[0..kn], 0..) |c, i| {
        const mw = widths[i];
        const inner_w = @max(0, mw - c.style.margin[1] - c.style.margin[3]);
        _ = layoutBlock(c, inner_w, x, cy, measure);
        // re-assign x after margins inside layoutBlock
        c.box.x = x + c.style.margin[3];
        max_h = @max(max_h, heights[i]);
        x += mw + gap;
        if (st.justify == .space_between and kn > 1 and i + 1 < kn) {
            // already using gap; for space-between distribute extra
        }
    }
    if (st.justify == .space_between and kn > 1) {
        // second pass
        const free = content_w - (total_w - gap * @as(f32, @floatFromInt(kn - 1)));
        const space = free / @as(f32, @floatFromInt(kn - 1));
        x = cx;
        for (kbuf[0..kn], 0..) |c, i| {
            const mw = widths[i];
            const inner_w = @max(0, mw - c.style.margin[1] - c.style.margin[3]);
            _ = layoutBlock(c, inner_w, x, cy, measure);
            c.box.x = x + c.style.margin[3];
            x += mw + space;
        }
    }
    return max_h;
}

fn layoutTable(n: *dom.Node, content_w: f32, cx: f32, cy: f32, measure: MeasureFn) f32 {
    // Collect rows
    var rows: [32]*dom.Node = undefined;
    var rn: usize = 0;
    collectRows(n, &rows, &rn);

    // count cols
    var cols: usize = 0;
    for (rows[0..rn]) |row| {
        var cn: usize = 0;
        for (row.children.items) |c| {
            if (c.style.display == .table_cell or std.mem.eql(u8, c.tag, "td") or std.mem.eql(u8, c.tag, "th")) cn += 1;
        }
        cols = @max(cols, cn);
    }
    if (cols == 0) return 0;
    const col_w = content_w / @as(f32, @floatFromInt(cols));
    var y = cy;
    for (rows[0..rn]) |row| {
        var x = cx;
        var row_h: f32 = 0;
        var ci: usize = 0;
        for (row.children.items) |cell| {
            if (!(cell.style.display == .table_cell or std.mem.eql(u8, cell.tag, "td") or std.mem.eql(u8, cell.tag, "th"))) continue;
            cell.style.width = col_w;
            const used = layoutBlock(cell, col_w, x, y, measure);
            cell.box.x = x;
            cell.box.y = y;
            cell.box.w = col_w;
            row_h = @max(row_h, used);
            x += col_w;
            ci += 1;
            if (ci >= cols) break;
        }
        // equalize row cell heights
        for (row.children.items) |cell| {
            if (cell.style.display == .table_cell or std.mem.eql(u8, cell.tag, "td") or std.mem.eql(u8, cell.tag, "th")) {
                cell.box.h = row_h;
            }
        }
        row.box = .{ .x = cx, .y = y, .w = content_w, .h = row_h };
        y += row_h;
    }
    return y - cy;
}

fn collectRows(n: *dom.Node, rows: *[32]*dom.Node, rn: *usize) void {
    for (n.children.items) |c| {
        if (std.mem.eql(u8, c.tag, "tr")) {
            if (rn.* < rows.len) {
                rows[rn.*] = c;
                rn.* += 1;
            }
        } else if (std.mem.eql(u8, c.tag, "thead") or std.mem.eql(u8, c.tag, "tbody") or std.mem.eql(u8, c.tag, "tfoot")) {
            collectRows(c, rows, rn);
        }
    }
}
