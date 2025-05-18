const std = @import("std");

const VoxelInfo = struct {
    // TODO: Better logic
    pixels: []const []const u8,
    width: u32,
    height: u32,
    channels: u32,

    pub fn fillIndex(self: *const @This(), index: *[6]u32, start: u32) u32 {
        switch (self.pixels.len) {
            1 => {
                for (0..6) |i| {
                    index[i] = start;
                }
                return start + 1;
            },
            2 => {
                for (0..2) |i| {
                    index[i] = start;
                }

                for (0..4) |i| {
                    index[2 + i] = start + 1;
                }

                return start + 2;
            },
            6 => {
                for (0..6) |i| {
                    index[i] = start + @as(u32, @intCast(i));
                }

                return start + 6;
            },
            else => {
                unreachable; // TODO
            },
        }
    }
};

const voxelsInfos = [_]VoxelInfo{
    .{
        .pixels = &[_][]const u8{@embedFile("stone.rgba")},
        .width = 128 * 2,
        .height = 128,
        .channels = 4,
    },
    .{
        .pixels = &[_][]const u8{@embedFile("ugly-stone.rgba")},
        .width = 32,
        .height = 32,
        .channels = 4,
    },
    .{
        .pixels = &[_][]const u8{
            @embedFile("ugly-wood-top.rgba"),
            @embedFile("ugly-wood.rgba"),
        },
        .width = 32,
        .height = 32,
        .channels = 4,
    },
};

const Self = @This();

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) !Self {
    return Self{
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.textureIndexes);
}

pub fn getVoxelCount(self: *const Self) usize {
    _ = self;
    return voxelsInfos.len;
}

pub fn getVoxelInfo(self: *const Self, index: usize) ?*const VoxelInfo {
    _ = self;
    if (index < voxelsInfos.len) {
        return &voxelsInfos[index];
    } else {
        return null;
    }
}

pub fn getTextureCount(self: *const Self) usize {
    _ = self;
    var size = @as(usize, 0);

    for (voxelsInfos) |t| {
        size += t.pixels.len;
    }

    return size;
}
