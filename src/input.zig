//! Normalized input snapshot for UI + scenes.

const sokol = @import("sokol");
const sapp = sokol.app;

pub const Key = enum {
    escape,
    space,
    enter,
    tab,
    backspace,
    left,
    right,
    up,
    down,
    w,
    a,
    s,
    d,
    r,
    k,
    p,
    f,
    n,
    c,
    v,
    one,
    two,
    three,
    four,
    five,
    six,
    seven,
    eight,
    nine,
    zero,
};

pub const MouseButton = enum { left, right, middle };

pub const Input = struct {
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    mouse_dx: f32 = 0,
    mouse_dy: f32 = 0,
    scroll_y: f32 = 0,

    mouse_down: [3]bool = .{ false, false, false },
    mouse_pressed: [3]bool = .{ false, false, false },
    mouse_released: [3]bool = .{ false, false, false },

    keys_down: std.EnumArray(Key, bool) = std.EnumArray(Key, bool).initFill(false),
    keys_pressed: std.EnumArray(Key, bool) = std.EnumArray(Key, bool).initFill(false),
    keys_released: std.EnumArray(Key, bool) = std.EnumArray(Key, bool).initFill(false),

    /// UTF-8 chars typed this frame (for text fields).
    text: [32]u8 = undefined,
    text_len: usize = 0,

    /// Paste buffer filled from CLIPBOARD_PASTED (consumed by focused text fields).
    paste: [512]u8 = undefined,
    paste_len: usize = 0,

    /// Modifier state (updated from key events).
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    super: bool = false,

    const std = @import("std");

    pub fn beginFrame(self: *Input) void {
        self.mouse_dx = 0;
        self.mouse_dy = 0;
        self.scroll_y = 0;
        self.mouse_pressed = .{ false, false, false };
        self.mouse_released = .{ false, false, false };
        self.keys_pressed = std.EnumArray(Key, bool).initFill(false);
        self.keys_released = std.EnumArray(Key, bool).initFill(false);
        self.text_len = 0;
        self.paste_len = 0;
        // shift/ctrl/alt kept sticky across frames from key down/up
    }

    pub fn pushPaste(self: *Input, s: []const u8) void {
        const n = @min(s.len, self.paste.len);
        @memcpy(self.paste[0..n], s[0..n]);
        self.paste_len = n;
    }

    pub fn takePaste(self: *Input) []const u8 {
        const out = self.paste[0..self.paste_len];
        self.paste_len = 0;
        return out;
    }

    pub fn mouseDown(self: *const Input, btn: MouseButton) bool {
        return self.mouse_down[@intFromEnum(btn)];
    }
    pub fn mousePressed(self: *const Input, btn: MouseButton) bool {
        return self.mouse_pressed[@intFromEnum(btn)];
    }
    pub fn mouseReleased(self: *const Input, btn: MouseButton) bool {
        return self.mouse_released[@intFromEnum(btn)];
    }
    pub fn keyDown(self: *const Input, k: Key) bool {
        return self.keys_down.get(k);
    }
    pub fn keyPressed(self: *const Input, k: Key) bool {
        return self.keys_pressed.get(k);
    }

    pub fn handleEvent(self: *Input, ev: [*c]const sapp.Event) void {
        const e = ev.*;
        // Keep modifiers current on every event that carries them.
        self.shift = (e.modifiers & sapp.modifier_shift) != 0;
        self.ctrl = (e.modifiers & sapp.modifier_ctrl) != 0;
        self.alt = (e.modifiers & sapp.modifier_alt) != 0;
        self.super = (e.modifiers & sapp.modifier_super) != 0;

        switch (e.type) {
            .MOUSE_MOVE => {
                self.mouse_dx += e.mouse_dx;
                self.mouse_dy += e.mouse_dy;
                self.mouse_x = e.mouse_x;
                self.mouse_y = e.mouse_y;
            },
            .MOUSE_DOWN => {
                if (mapMouse(e.mouse_button)) |bi| {
                    self.mouse_down[bi] = true;
                    self.mouse_pressed[bi] = true;
                }
                self.mouse_x = e.mouse_x;
                self.mouse_y = e.mouse_y;
            },
            .MOUSE_UP => {
                if (mapMouse(e.mouse_button)) |bi| {
                    self.mouse_down[bi] = false;
                    self.mouse_released[bi] = true;
                }
            },
            .MOUSE_SCROLL => {
                self.scroll_y += e.scroll_y;
            },
            .KEY_DOWN => {
                if (mapKey(e.key_code)) |k| {
                    if (!e.key_repeat) {
                        self.keys_pressed.set(k, true);
                    }
                    self.keys_down.set(k, true);
                }
            },
            .KEY_UP => {
                if (mapKey(e.key_code)) |k| {
                    self.keys_down.set(k, false);
                    self.keys_released.set(k, true);
                }
            },
            .CHAR => {
                if (e.char_code >= 32 and e.char_code < 127) {
                    if (self.text_len < self.text.len) {
                        self.text[self.text_len] = @intCast(e.char_code);
                        self.text_len += 1;
                    }
                }
            },
            else => {},
        }
    }

    fn mapMouse(btn: sapp.Mousebutton) ?usize {
        return switch (btn) {
            .LEFT => 0,
            .RIGHT => 1,
            .MIDDLE => 2,
            else => null,
        };
    }

    fn mapKey(code: sapp.Keycode) ?Key {
        return switch (code) {
            .ESCAPE => .escape,
            .SPACE => .space,
            .ENTER => .enter,
            .TAB => .tab,
            .BACKSPACE => .backspace,
            .LEFT => .left,
            .RIGHT => .right,
            .UP => .up,
            .DOWN => .down,
            .W => .w,
            .A => .a,
            .S => .s,
            .D => .d,
            .R => .r,
            .K => .k,
            .P => .p,
            .F => .f,
            .N => .n,
            .C => .c,
            .V => .v,
            ._1 => .one,
            ._2 => .two,
            ._3 => .three,
            ._4 => .four,
            ._5 => .five,
            ._6 => .six,
            ._7 => .seven,
            ._8 => .eight,
            ._9 => .nine,
            ._0 => .zero,
            else => null,
        };
    }
};
