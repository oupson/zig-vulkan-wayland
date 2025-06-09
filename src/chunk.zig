const std = @import("std");
const Renderer = @import("renderer.zig");

const Allocator = std.mem.Allocator;

const Self = @This();

const CHUNK_SIZE = 64;

allocator: Allocator,
leaf: Leaf,

const Leaf = union(LeafType) {
    full: u16,
    leaves: []Leaf,

    pub fn deinit(self: *Leaf, allocator: Allocator) void {
        switch (self.*) {
            .full => {},
            .leaves => |leaves| {
                for (leaves) |*leaf| {
                    leaf.deinit(allocator);
                }
                allocator.free(leaves);
            },
        }
    }
};

pub fn init(allocator: Allocator) Self {
    return Self{
        .allocator = allocator,
        .leaf = .{ .full = 0 },
    };
}

pub fn deinit(self: *Self) void {
    self.leaf.deinit(self.allocator);
}

pub fn getBlock(self: *const Self, x: usize, y: usize, z: usize) u16 {
    var insideLeafX, var insideLeafY, var insideLeafZ = .{ x, y, z };
    var level = @as(usize, 3); // 2 + 1
    var leaf = &self.leaf;

    while (level > 0) {
        const leafIndex, const insideLeafIndex = getLeaveIndex(level - 1, insideLeafX, insideLeafY, insideLeafZ);
        const leafX, const leafY, const leafZ = leafIndex;
        insideLeafX, insideLeafY, insideLeafZ = insideLeafIndex;

        const leaves = init: {
            switch (leaf.*) {
                .full => |b| {
                    return b;
                },
                .leaves => |leaves| {
                    break :init leaves;
                },
            }
        };

        leaf = &leaves[leafZ * 4 * 4 + leafY * 4 + leafX];
        level -= 1;
    }

    return leaf.full;
}

// TODO: merge leaf
pub fn putBlock(self: *Self, x: usize, y: usize, z: usize, block: u16) !void {
    var insideLeafX, var insideLeafY, var insideLeafZ = .{ x, y, z };
    var level = @as(usize, 3); // 2 + 1
    var leaf = &self.leaf;

    while (level > 0) {
        const leafIndex, const insideLeafIndex = getLeaveIndex(level - 1, insideLeafX, insideLeafY, insideLeafZ);
        const leafX, const leafY, const leafZ = leafIndex;
        insideLeafX, insideLeafY, insideLeafZ = insideLeafIndex;

        const leaves = getLeaves: {
            switch (leaf.*) {
                .full => |b| {
                    if (b == block) {
                        return;
                    }

                    const leaves = try self.allocator.alloc(Leaf, 4 * 4 * 4);
                    for (leaves) |*initLeaf| {
                        initLeaf.* = .{ .full = b };
                    }
                    leaf.* = .{ .leaves = leaves };
                    break :getLeaves leaves;
                },
                .leaves => |leaves| {
                    break :getLeaves leaves;
                },
            }
        };

        leaf = &leaves[leafZ * 4 * 4 + leafY * 4 + leafX];

        level -= 1;
    }
    leaf.* = .{ .full = block };
}

inline fn getPos(index: usize) @Vector(3, u32) {
    return @Vector(3, u32){
        @as(u32, @intCast(index % CHUNK_SIZE)),
        @as(u32, @intCast(@divTrunc(index, CHUNK_SIZE) % CHUNK_SIZE)),
        @as(u32, @intCast(@divTrunc(@divTrunc(index, CHUNK_SIZE), CHUNK_SIZE))),
    };
}

pub const LeafType = enum { full, leaves };

pub fn getLeaveIndex(level: usize, x: usize, y: usize, z: usize) struct {
    struct { usize, usize, usize },
    struct { usize, usize, usize },
} {
    const denominator = std.math.pow(usize, 4, level);
    const leaveIndex = .{ x / denominator, y / denominator, z / denominator };
    const leaveOffset = .{ x % denominator, y % denominator, z % denominator };
    return .{ leaveIndex, leaveOffset };
}

const testing = std.testing;

test "expect when putBlock then layout is valid" {
    const allocator = testing.allocator;
    var c: @This() = .init(allocator);
    defer c.deinit();
    try c.putBlock(0, 0, 0, 1);

    const level1 = try allocator.alloc(Leaf, 4 * 4 * 4);
    defer allocator.free(level1);
    for (level1) |*l| {
        l.* = .{ .full = 0 };
    }

    const level2 = try allocator.alloc(Leaf, 4 * 4 * 4);
    defer allocator.free(level2);
    for (level2) |*l| {
        l.* = .{ .full = 0 };
    }
    level1[0] = .{ .leaves = level2 };

    const level3 = try allocator.alloc(Leaf, 4 * 4 * 4);
    defer allocator.free(level3);
    for (level3) |*l| {
        l.* = .{ .full = 0 };
    }

    level2[0] = .{ .leaves = level3 };
    level3[0] = .{ .full = 1 };

    try testing.expectEqualDeep(Leaf{ .leaves = level1 }, c.leaf);
}

test "expect when put block then getBlock return same block" {
    const allocator = testing.allocator;
    var c: @This() = .init(allocator);
    defer c.deinit();
    try c.putBlock(0, 0, 0, 1);

    try testing.expectEqual(1, c.getBlock(0, 0, 0));
}

test "expect when put same block then leaf don't split" {
    const allocator = testing.allocator;
    var c: @This() = .init(allocator);
    defer c.deinit();
    try c.putBlock(0, 0, 0, 0);

    try testing.expectEqualDeep(Leaf{ .full = 0 }, c.leaf);
}

test "expect when chunk is init then chunk full of air" {
    const allocator = testing.allocator;

    var c: @This() = .init(allocator);
    defer c.deinit();
    for (0..CHUNK_SIZE) |z| {
        for (0..CHUNK_SIZE) |y| {
            for (0..CHUNK_SIZE) |x| {
                try testing.expectEqual(0, c.getBlock(x, y, z));
            }
        }
    }
}

test "expect when all putBlock then getBlock return this block" {
    const allocator = testing.allocator;
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var random = prng.random();

    var c: @This() = .init(allocator);
    defer c.deinit();

    for (0..CHUNK_SIZE) |z| {
        for (0..CHUNK_SIZE) |y| {
            for (0..CHUNK_SIZE) |x| {
                const block = random.int(u16);
                try c.putBlock(x, y, z, block);
            }
        }
    }

    prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    random = prng.random();
    for (0..CHUNK_SIZE) |z| {
        for (0..CHUNK_SIZE) |y| {
            for (0..CHUNK_SIZE) |x| {
                const block = random.int(u16);
                try testing.expectEqual(block, c.getBlock(x, y, z));
            }
        }
    }
}
test "expect when put same block then leaves are merged" {
    const allocator = testing.allocator;
    var c: @This() = .init(allocator);
    defer c.deinit();

    try c.putBlock(0, 0, 0, 1);
    try c.putBlock(0, 0, 0, 0);

    try testing.expectEqualDeep(Leaf{ .full = 0 }, c.leaf);
}

test "expect when put all same block then leaves are merged" {
    const allocator = testing.allocator;
    var c: @This() = .init(allocator);
    defer c.deinit();

    for (0..CHUNK_SIZE) |z| {
        for (0..CHUNK_SIZE) |y| {
            for (0..CHUNK_SIZE) |x| {
                try c.putBlock(x, y, z, 1);
            }
        }
    }

    try testing.expectEqualDeep(Leaf{ .full = 1 }, c.leaf);
}
