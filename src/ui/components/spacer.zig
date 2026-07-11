//! Vertical spacer.
pub fn spacer(ui: anytype, h: f32) void {
    _ = ui.alloc(0, h);
}
