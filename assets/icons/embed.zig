//! Compile-time embed fallback for the icon atlas + YAML.
//! Runtime prefers assets/icons/icons.png next to the binary (edit without rebuild).
pub const icons_png = @embedFile("icons.png");
pub const icons_yaml = @embedFile("icons.yaml");
