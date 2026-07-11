//! Normalized input snapshot for UI + scenes.
//! Includes software key-repeat (configurable delay/rate).

const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;

pub const Key = enum {
    escape,
    space,
    enter,
    tab,
    backspace,
    delete,
    home,
    end,
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
    x,
    z,
    l,
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

/// Global input timing knobs (seconds).
pub const Config = struct {
    /// Delay before first software repeat after key down.
    key_repeat_delay_s: f64 = 0.240,
    /// Interval between subsequent software repeats.
    key_repeat_rate_s: f64 = 0.060,
    /// Multi-click chain window (double/triple click). ~350ms matches typical editors.
    multi_click_s: f64 = 0.350,
};

pub var config: Config = .{};

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

    /// Next software-repeat fire time per key (-1 = not held / not scheduled).
    key_repeat_at: std.EnumArray(Key, f64) = std.EnumArray(Key, f64).initFill(-1),

    /// UTF-8 chars typed this frame (for text fields). Ctrl/Alt chars are blocked.
    text: [32]u8 = undefined,
    text_len: usize = 0,

    /// Paste buffer filled from CLIPBOARD_PASTED (consumed by focused text fields).
    paste: [512]u8 = undefined,
    paste_len: usize = 0,

    /// Copy buffer for Ctrl+C/X → sokol clipboard (set by text fields).
    copy_request: [1024]u8 = undefined,
    copy_request_len: usize = 0,

    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    super: bool = false,

    /// Seconds, updated by app each frame before UI.
    now: f64 = 0,

    pub fn beginFrame(self: *Input) void {
        self.mouse_dx = 0;
        self.mouse_dy = 0;
        self.scroll_y = 0;
        self.mouse_pressed = .{ false, false, false };
        self.mouse_released = .{ false, false, false };
        self.keys_pressed = std.EnumArray(Key, bool).initFill(false);
        self.keys_released = std.EnumArray(Key, bool).initFill(false);
        self.text_len = 0;
        // paste_len cleared when consumed by text edit; don't wipe if set this frame mid-event
        // copy_request consumed by app after UI
    }

    /// Call once per frame after `now` is set and events have been processed.
    pub fn tickKeyRepeat(self: *Input) void {
        // Explicit list — software repeat for navigation/editing keys.
        const repeatable = [_]Key{
            .backspace, .delete, .left, .right, .up, .down, .home, .end,
            .enter,     .space,  .tab,
        };
        for (repeatable) |k| {
            if (self.keys_down.get(k)) {
                const at = self.key_repeat_at.get(k);
                if (at >= 0 and self.now >= at) {
                    self.keys_pressed.set(k, true);
                    self.key_repeat_at.set(k, self.now + config.key_repeat_rate_s);
                }
            } else {
                self.key_repeat_at.set(k, -1);
            }
        }
    }

    pub fn pushPaste(self: *Input, s: []const u8) void {
        const n = @min(s.len, self.paste.len);
        @memcpy(self.paste[0..n], s[0..n]);
        self.paste_len = n;
    }

    pub fn requestCopy(self: *Input, s: []const u8) void {
        const n = @min(s.len, self.copy_request.len);
        @memcpy(self.copy_request[0..n], s[0..n]);
        self.copy_request_len = n;
    }

    pub fn takeCopyRequest(self: *Input) ?[]const u8 {
        if (self.copy_request_len == 0) return null;
        const out = self.copy_request[0..self.copy_request_len];
        self.copy_request_len = 0;
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
                        // First software repeat after delay (sapp may also auto-repeat; we gate CHAR separately).
                        self.key_repeat_at.set(k, self.now + config.key_repeat_delay_s);
                    }
                    self.keys_down.set(k, true);
                }
            },
            .KEY_UP => {
                if (mapKey(e.key_code)) |k| {
                    self.keys_down.set(k, false);
                    self.keys_released.set(k, true);
                    self.key_repeat_at.set(k, -1);
                }
            },
            .CHAR => {
                // Never type into fields while Ctrl/Alt/Super held (blocks Ctrl+P leaking 'p').
                if (self.ctrl or self.alt or self.super) return;
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
            .KP_ENTER => .enter,
            .TAB => .tab,
            .BACKSPACE => .backspace,
            .DELETE => .delete,
            .HOME => .home,
            .END => .end,
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
            .X => .x,
            .Z => .z,
            .L => .l,
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
            // Numpad (Blender-style view hotkeys, etc.)
            .KP_1 => .one,
            .KP_2 => .two,
            .KP_3 => .three,
            .KP_4 => .four,
            .KP_5 => .five,
            .KP_6 => .six,
            .KP_7 => .seven,
            .KP_8 => .eight,
            .KP_9 => .nine,
            .KP_0 => .zero,
            else => null,
        };
    }
};
