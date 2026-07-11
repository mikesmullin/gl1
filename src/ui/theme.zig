//! Theme tokens — dark-first (user preference).

pub const Color = [4]f32;

pub const Theme = struct {
    bg: Color = .{ 0.10, 0.11, 0.13, 1 },
    panel: Color = .{ 0.14, 0.15, 0.18, 1 },
    panel_border: Color = .{ 0.25, 0.27, 0.32, 1 },
    text: Color = .{ 0.90, 0.91, 0.93, 1 },
    text_dim: Color = .{ 0.55, 0.58, 0.64, 1 },
    accent: Color = .{ 0.35, 0.75, 0.45, 1 },
    accent_hot: Color = .{ 0.45, 0.85, 0.55, 1 },
    button: Color = .{ 0.20, 0.22, 0.27, 1 },
    button_hot: Color = .{ 0.28, 0.32, 0.40, 1 },
    button_active: Color = .{ 0.16, 0.18, 0.22, 1 },
    button_disabled: Color = .{ 0.15, 0.15, 0.17, 1 },
    input_bg: Color = .{ 0.08, 0.09, 0.11, 1 },
    slider_track: Color = .{ 0.18, 0.19, 0.22, 1 },
    slider_fill: Color = .{ 0.30, 0.55, 0.40, 1 },
    danger: Color = .{ 0.85, 0.35, 0.35, 1 },
    warning: Color = .{ 0.90, 0.70, 0.25, 1 },
    info: Color = .{ 0.35, 0.60, 0.90, 1 },
    sidebar: Color = .{ 0.12, 0.13, 0.16, 1 },
    selected: Color = .{ 0.22, 0.35, 0.28, 1 },
    overlay: Color = .{ 0.0, 0.0, 0.0, 0.55 },
    modal: Color = .{ 0.16, 0.17, 0.21, 1 },
    tooltip_bg: Color = .{ 0.08, 0.09, 0.11, 0.95 },
    toast_bg: Color = .{ 0.18, 0.22, 0.20, 0.95 },
    menubar: Color = .{ 0.13, 0.14, 0.17, 1 },
    statusbar: Color = .{ 0.11, 0.12, 0.15, 1 },

    pad: f32 = 8,
    gap: f32 = 6,
    radius: f32 = 0, // solid rects; rounded later
    font_size: f32 = 2.0,
    title_font_size: f32 = 2.5,
    row_h: f32 = 28,
    button_h: f32 = 28,
    menubar_h: f32 = 28,
    statusbar_h: f32 = 24,
};

pub const dark = Theme{};

/// Slightly cooler / bluer dark variant for A/B in storybook.
pub const dark_cool = Theme{
    .bg = .{ 0.08, 0.09, 0.12, 1 },
    .panel = .{ 0.12, 0.14, 0.18, 1 },
    .accent = .{ 0.40, 0.70, 0.95, 1 },
    .accent_hot = .{ 0.50, 0.80, 1.0, 1 },
    .slider_fill = .{ 0.30, 0.50, 0.75, 1 },
    .selected = .{ 0.18, 0.28, 0.40, 1 },
};

/// Warm amber-accent dark variant (third storybook palette).
pub const dark_warm = Theme{
    .bg = .{ 0.11, 0.09, 0.08, 1 },
    .panel = .{ 0.16, 0.13, 0.11, 1 },
    .panel_border = .{ 0.32, 0.26, 0.20, 1 },
    .accent = .{ 0.92, 0.62, 0.28, 1 },
    .accent_hot = .{ 1.0, 0.72, 0.38, 1 },
    .slider_fill = .{ 0.70, 0.45, 0.22, 1 },
    .selected = .{ 0.35, 0.24, 0.14, 1 },
    .button = .{ 0.22, 0.18, 0.15, 1 },
    .button_hot = .{ 0.30, 0.24, 0.18, 1 },
    .sidebar = .{ 0.13, 0.11, 0.09, 1 },
};

/// Resolve theme by index: 0=dark, 1=cool, 2=warm.
pub fn byIndex(i: u32) Theme {
    return switch (i) {
        1 => dark_cool,
        2 => dark_warm,
        else => dark,
    };
}
