const std = @import("std");
const testing = std.testing;

const Chunk = @import("chunk.zig");

const Brick = extern struct {
    metadata: packed struct(u16) {
        full: bool,
        reserved: u15 = 0,
    },
    material: u16 align(4),
};

fn toBrickMap(chunk: *Chunk, buffer: []u8) void {
    const brickMap: []Brick = @ptrCast(buffer);
    _ = chunk;
    _ = brickMap;
}

test "brick have correct abi" {
    try testing.expectEqual(@sizeOf(u64), @sizeOf(Brick));
    try testing.expectEqual(0, @bitOffsetOf(Brick, "metadata"));
    try testing.expectEqual(32, @bitOffsetOf(Brick, "material"));
}

test "metadata have correct abi" {
    const brick = Brick{
        .metadata = .{
            .full = true,
        },
        .material = 2,
    };
    try testing.expectEqual(2, brick.material);
    try testing.expectEqual(0b0000000000000001, @as(u16, @bitCast(brick.metadata)));
}
