//! Reusable UI component.
const std = @import("std");
const types = @import("../types.zig");
const te = @import("../text_edit.zig");
const Color = types.Color;
const Rect = types.Rect;
const Id = types.Id;

pub fn colorSwatch(ui: anytype, opts: anytype) bool {
    const r = ui.alloc(opts.w, opts.w);
    const i = ui.id(opts.id);
    const st = ui.interact(i, r, false);
    const border: Color = if (opts.selected or st.hot) ui.theme.accent else ui.theme.panel_border;
    ui.drawRectBorder(r, opts.color, border, if (opts.selected) 2 else 1);
    return st.clicked;
}
