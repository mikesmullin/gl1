const std = @import("std");
const app = @import("../app.zig");
const ui = @import("../ui/ui.zig");
const theme_mod = @import("../ui/theme.zig");
const state = @import("state.zig");

pub fn frame(a: *app.App) void {
    const u = &a.ui;
    const st = &a.scene_state;

    if (u.beginPanel(.{ .id = "widgets", .x = 24, .y = 24, .w = 380, .h = 480, .title = "widgets_basic" })) {
        defer u.endPanel();

        u.label(.{ .text = "Immediate-mode widgets (Style A)" });
        u.separator();

        if (u.button(.{ .id = "btn_click", .label = "Click me" })) {
            st.clicks +%= 1;
            u.toast("Button clicked", .ok, 1.5);
        }
        var buf: [48]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "clicks: {d}", .{st.clicks}) catch "";
        u.label(.{ .text = s, .color = u.theme.text_dim });

        _ = u.checkbox(.{ .id = "chk", .label = "Enable feature", .value = &st.checked });
        _ = u.toggle(.{ .id = "togw", .label = "Turbo", .value = &st.toggled });
        _ = u.slider(.{ .id = "speed", .label = "Speed", .value = &st.speed, .min = 0, .max = 1 });
        _ = u.spinner(.{ .id = "spin", .label = "Count", .value = &st.spinner_val, .min = 0, .max = 100, .step = 1 });
        _ = u.textInput(.{ .id = "name", .label = "Name", .buf = &st.text_buf, .len = &st.text_len });
        u.progress(.{ .label = "Load", .value = st.progress });
        st.progress = @mod(st.progress + a.dt * 0.1, 1.0);
    }
}
