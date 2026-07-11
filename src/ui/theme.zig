//! Dark theme tokens (v1).

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
    sidebar: Color = .{ 0.12, 0.13, 0.16, 1 },
    selected: Color = .{ 0.22, 0.35, 0.28, 1 },

    pad: f32 = 8,
    gap: f32 = 6,
    radius: f32 = 0, // solid rects; rounded later
    font_size: f32 = 2.0,
    title_font_size: f32 = 2.5,
    row_h: f32 = 28,
    button_h: f32 = 28,
};

pub const dark = Theme{};
