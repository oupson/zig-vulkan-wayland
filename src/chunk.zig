const std = @import("std");
const Renderer = @import("renderer.zig");

const Self = @This();

pub const MESH_SIZE = 32 * 32 * 32 * 24;
pub const INDEX_BUFFER_SIZE = 32 * 32 * 32 * 36;

position: @Vector(3, f32),

elements: [32 * 32 * 32]u8,

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

const vertices = [_]Renderer.Vertex{
    // bottom
    .{
        .pos = .{ 0, 0, 1 },
        .texCoord = .{ 0.0, 0.0 },
    },
    .{
        .pos = .{ 1, 0, 1 },
        .texCoord = .{ 0.5, 0.0 },
    },
    .{
        .pos = .{ 1, 0, 0 },
        .texCoord = .{ 0.5, 1.0 },
    },
    .{
        .pos = .{ 0, 0, 0 },
        .texCoord = .{ 0.0, 1.0 },
    },
    // top
    .{
        .pos = .{ 0, 1, 1 },
        .texCoord = .{ 0.0, 0.0 },
    },
    .{
        .pos = .{ 1, 1, 1 },
        .texCoord = .{ 0.5, 0.0 },
    },
    .{
        .pos = .{ 1, 1, 0 },
        .texCoord = .{ 0.5, 1.0 },
    },
    .{
        .pos = .{ 0, 1, 0 },
        .texCoord = .{ 0.0, 1.0 },
    },
    // north 8-11
    .{
        .pos = .{ 0, 0, 1 },
        .texCoord = .{ 0.5, 1.0 },
    },
    .{
        .pos = .{ 0, 1, 1 },
        .texCoord = .{ 0.5, 0.0 },
    },
    .{
        .pos = .{ 1, 1, 1 },
        .texCoord = .{ 1.0, 0.0 },
    },
    .{
        .pos = .{ 1, 0, 1 },
        .texCoord = .{ 1.0, 1.0 },
    },
    // east 12-15
    .{
        .pos = .{ 1, 0, 0 },
        .texCoord = .{ 1.0, 1.0 },
    },
    .{
        .pos = .{ 1, 1, 0 },
        .texCoord = .{ 1.0, 0.0 },
    },
    .{
        .pos = .{ 1, 1, 1 },
        .texCoord = .{ 0.5, 0.0 },
    },
    .{
        .pos = .{ 1, 0, 1 },
        .texCoord = .{ 0.5, 1.0 },
    },
    // south 16-19
    .{
        .pos = .{ 0, 0, 0 },
        .texCoord = .{ 1.0, 1.0 },
    },
    .{
        .pos = .{ 0, 1, 0 },
        .texCoord = .{ 1.0, 0.0 },
    },
    .{
        .pos = .{ 1, 1, 0 },
        .texCoord = .{ 0.5, 0.0 },
    },
    .{
        .pos = .{ 1, 0, 0 },
        .texCoord = .{ 0.5, 1.0 },
    },
    // 20-23
    .{
        .pos = .{ 0, 0, 0 },
        .texCoord = .{ 0.5, 1.0 },
    },
    .{
        .pos = .{ 0, 1, 0 },
        .texCoord = .{ 0.5, 0.0 },
    },
    .{
        .pos = .{ 0, 1, 1 },
        .texCoord = .{ 1.0, 0.0 },
    },
    .{
        .pos = .{ 0, 0, 1 },
        .texCoord = .{ 1.0, 1.0 },
    },
};

const indices = [_]u16{
    // bottom
    0,  2,  3,  0,  1,  2,
    // top
    4,  7,  6,  4,  6,  5,
    // north
    8,  9,  10, 10, 11, 8,
    // east
    13, 12, 14, 14, 12, 15,
    // south
    16, 18, 17, 18, 16, 19,
    // west
    20, 21, 22, 22, 23, 20,
};

pub fn getMesh(self: *Self, mesh: []Renderer.Vertex, index_buffer: []u32, base_index: usize) struct { usize, usize } {
    var vertex_buffer_count: usize = 0;
    var index_buffer_count: usize = 0;

    for (self.elements, 0..) |elem, pos| {
        if (elem > 0) {
            const real_pos = getPos(pos);

            const blockX = @as(f32, @floatFromInt(real_pos[0])) + self.position[0] * 32.0;
            const blockY = @as(f32, @floatFromInt(real_pos[1])) + self.position[1] * 32.0;
            const blockZ = @as(f32, @floatFromInt(real_pos[2])) + self.position[2] * 32.0;

            for (indices) |i| {
                index_buffer[index_buffer_count] = @intCast(vertex_buffer_count + @as(usize, i) + base_index);
                index_buffer_count += 1;
            }

            for (vertices) |v| {
                mesh[vertex_buffer_count] = v;
                mesh[vertex_buffer_count].pos[0] += blockX;
                mesh[vertex_buffer_count].pos[1] += blockY;
                mesh[vertex_buffer_count].pos[2] += blockZ;

                vertex_buffer_count += 1;
            }
        }
    }

    return .{ vertex_buffer_count, index_buffer_count };
}

inline fn getPos(index: usize) @Vector(3, u32) {
    return @Vector(3, u32){
        @as(u32, @intCast(index % 32)),
        @as(u32, @intCast(@divTrunc(index, 32) % 32)),
        @as(u32, @intCast(@divTrunc(@divTrunc(index, 32), 32))),
    };
}
