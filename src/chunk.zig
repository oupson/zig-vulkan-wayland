const std = @import("std");
const Renderer = @import("renderer.zig");

const Self = @This();

position: @Vector(3, f32),

elements: [32 * 32 * 32]u32,

pub fn init(x: f32, y: f32, z: f32) Self {
    return Self{
        .position = .{ x, y, z },
        .elements = [_]u8{0} ** (32 * 32 * 32),
    };
}

pub fn getBlock(self: *const Self, x: usize, y: usize, z: usize) usize {
    const index = z * 32 * 32 + y * 32 + x;
    return self.elements[index];
}

pub fn putBlock(self: *Self, x: usize, y: usize, z: usize, block: u8) void {
    const index = z * 32 * 32 + y * 32 + x;
    self.elements[index] = block;
}

inline fn getPos(index: usize) @Vector(3, u32) {
    return @Vector(3, u32){
        @as(u32, @intCast(index % 32)),
        @as(u32, @intCast(@divTrunc(index, 32) % 32)),
        @as(u32, @intCast(@divTrunc(@divTrunc(index, 32), 32))),
    };
}
