//! Minimal WAV (PCM s16le) loader + sokol_audio push player.
//! Playback position is a wall-clock playhead; the ring is only filled a short
//! buffer ahead so the scrubber does not race to 100% before audio ends.
const std = @import("std");
const sokol = @import("sokol");
const saudio = sokol.audio;

pub var audio_ready: bool = false;

pub fn setupAudio() void {
    if (audio_ready) return;
    saudio.setup(.{
        .sample_rate = 22050,
        .num_channels = 1,
        .buffer_frames = 1024,
        .logger = .{ .func = sokol.log.func },
    });
    audio_ready = saudio.isvalid();
}

pub fn shutdownAudio() void {
    if (!audio_ready) return;
    saudio.shutdown();
    audio_ready = false;
}

pub const Wav = struct {
    samples: []f32 = &.{},
    sample_rate: u32 = 22050,
    channels: u32 = 1,
    allocator: std.mem.Allocator = undefined,
    owned: bool = false,

    pub fn deinit(self: *Wav) void {
        if (self.owned and self.samples.len > 0) {
            self.allocator.free(self.samples);
        }
        self.* = .{};
    }

    pub fn loadFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !Wav {
        const data = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(16 * 1024 * 1024));
        defer allocator.free(data);
        return try loadBytes(allocator, data);
    }

    pub fn loadBytes(allocator: std.mem.Allocator, data: []const u8) !Wav {
        if (data.len < 44) return error.InvalidWav;
        if (!std.mem.eql(u8, data[0..4], "RIFF") or !std.mem.eql(u8, data[8..12], "WAVE"))
            return error.InvalidWav;

        var offset: usize = 12;
        var fmt_channels: u16 = 1;
        var fmt_rate: u32 = 22050;
        var fmt_bits: u16 = 16;
        var pcm: []const u8 = &.{};

        while (offset + 8 <= data.len) {
            const id = data[offset .. offset + 4];
            const size = std.mem.readInt(u32, data[offset + 4 ..][0..4], .little);
            offset += 8;
            if (offset + size > data.len) break;
            const chunk = data[offset .. offset + size];
            if (std.mem.eql(u8, id, "fmt ")) {
                if (chunk.len >= 16) {
                    const format = std.mem.readInt(u16, chunk[0..2], .little);
                    if (format != 1) return error.UnsupportedWav;
                    fmt_channels = std.mem.readInt(u16, chunk[2..4], .little);
                    fmt_rate = std.mem.readInt(u32, chunk[4..8], .little);
                    fmt_bits = std.mem.readInt(u16, chunk[14..16], .little);
                }
            } else if (std.mem.eql(u8, id, "data")) {
                pcm = chunk;
            }
            offset += size;
            if (size % 2 == 1) offset += 1;
        }
        if (pcm.len == 0) return error.InvalidWav;
        if (fmt_bits != 16) return error.UnsupportedWav;

        const frame_bytes: usize = @as(usize, fmt_channels) * 2;
        const frames = pcm.len / frame_bytes;
        const out = try allocator.alloc(f32, frames);
        var i: usize = 0;
        while (i < frames) : (i += 1) {
            var acc: f32 = 0;
            var ch: u16 = 0;
            while (ch < fmt_channels) : (ch += 1) {
                const off = i * frame_bytes + @as(usize, ch) * 2;
                const s = std.mem.readInt(i16, pcm[off..][0..2], .little);
                acc += @as(f32, @floatFromInt(s)) / 32768.0;
            }
            out[i] = acc / @as(f32, @floatFromInt(@max(fmt_channels, 1)));
        }
        return .{
            .samples = out,
            .sample_rate = fmt_rate,
            .channels = 1,
            .allocator = allocator,
            .owned = true,
        };
    }
};

pub const Player = struct {
    wav: Wav = .{},
    /// Next sample index to push into the audio ring.
    write_cursor: usize = 0,
    /// Audible position (samples); advanced by wall-clock while playing.
    playhead: f64 = 0,
    playing: bool = false,
    loaded: bool = false,

    /// How far ahead of the playhead we fill the ring (samples).
    const buffer_ahead: f64 = 2048;

    pub fn deinit(self: *Player) void {
        self.wav.deinit();
        self.* = .{};
    }

    pub fn loadPath(self: *Player, allocator: std.mem.Allocator, io: std.Io, path: []const u8) !void {
        self.wav.deinit();
        self.wav = try Wav.loadFile(allocator, io, path);
        self.write_cursor = 0;
        self.playhead = 0;
        self.playing = false;
        self.loaded = true;
    }

    pub fn play(self: *Player) void {
        if (!self.loaded) return;
        self.playing = true;
        // Keep write cursor at least at playhead so we don't re-push old audio.
        const ph: usize = @intFromFloat(@max(0, self.playhead));
        if (self.write_cursor < ph) self.write_cursor = ph;
    }

    pub fn pause(self: *Player) void {
        self.playing = false;
    }

    pub fn stop(self: *Player) void {
        self.playing = false;
        self.write_cursor = 0;
        self.playhead = 0;
    }

    pub fn toggle(self: *Player) void {
        if (self.playing) self.pause() else self.play();
    }

    pub fn seekFraction(self: *Player, t: f32) void {
        if (!self.loaded or self.wav.samples.len == 0) return;
        const tt = std.math.clamp(t, 0, 1);
        const pos = tt * @as(f64, @floatFromInt(self.wav.samples.len));
        self.playhead = pos;
        self.write_cursor = @intFromFloat(pos);
    }

    /// UI scrubber: based on playhead, not ring write cursor.
    pub fn progress(self: *const Player) f32 {
        if (!self.loaded or self.wav.samples.len == 0) return 0;
        const p = self.playhead / @as(f64, @floatFromInt(self.wav.samples.len));
        return @floatCast(std.math.clamp(p, 0, 1));
    }

    /// Advance playhead by dt seconds; call once per frame before pump.
    pub fn tick(self: *Player, dt: f32) void {
        if (!self.playing or !self.loaded) return;
        const rate: f64 = @floatFromInt(if (self.wav.sample_rate == 0) 22050 else self.wav.sample_rate);
        self.playhead += @as(f64, dt) * rate;
        const len_f: f64 = @floatFromInt(self.wav.samples.len);
        if (self.playhead >= len_f) {
            self.playing = false;
            self.playhead = 0;
            self.write_cursor = 0;
        }
    }

    /// Push only enough samples to stay ~buffer_ahead ahead of the playhead.
    pub fn pump(self: *Player) void {
        if (!self.playing or !self.loaded or !audio_ready) return;
        const len = self.wav.samples.len;
        if (len == 0) return;

        const target_f = @min(@as(f64, @floatFromInt(len)), self.playhead + buffer_ahead);
        const target: usize = @intFromFloat(target_f);
        if (self.write_cursor >= target) {
            // Still keep ring from underrunning if expect is large and we're near end
            if (self.write_cursor >= len) return;
        }

        const want = saudio.expect();
        if (want <= 0) return;

        var buf: [1024]f32 = undefined;
        var left: i32 = want;
        while (left > 0) {
            // Don't write far past playhead + buffer_ahead
            if (self.write_cursor >= target and self.write_cursor >= @as(usize, @intFromFloat(self.playhead + buffer_ahead * 0.5))) break;
            if (self.write_cursor >= len) break;

            const n: usize = @min(@as(usize, @intCast(left)), buf.len);
            const avail = len - self.write_cursor;
            const take = @min(n, avail);
            @memcpy(buf[0..take], self.wav.samples[self.write_cursor .. self.write_cursor + take]);
            if (take < n) {
                @memset(buf[take..n], 0);
            }
            const pushed = saudio.push(&buf[0], @intCast(take));
            if (pushed <= 0) break;
            self.write_cursor += @as(usize, @intCast(pushed));
            left -= pushed;
        }
    }
};
