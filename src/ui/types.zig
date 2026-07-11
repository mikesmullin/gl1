//! Shared UI value types (no dependency on Ui) so components stay cycle-free.

pub const Color = [4]f32;

pub const Id = struct {
    a: u64 = 0,
    b: u64 = 0,

    pub fn eq(self: Id, o: Id) bool {
        return self.a == o.a and self.b == o.b;
    }
    pub fn isNone(self: Id) bool {
        return self.a == 0 and self.b == 0;
    }
};

pub const Rect = struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,

    pub fn contains(self: Rect, px: f32, py: f32) bool {
        return px >= self.x and py >= self.y and px < self.x + self.w and py < self.y + self.h;
    }
};
