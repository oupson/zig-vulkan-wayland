const std = @import("std");
const builtin = @import("builtin");

const wayland = @import("wayland");
const wl = wayland.client.wl;

const Allocator = std.mem.Allocator;

const App = @import("app.zig");
const Renderer = @import("renderer.zig");

fn DebuggableAllocator() type {
    if (builtin.mode == .Debug) {
        return struct {
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};

            fn allocator(_: *@This()) std.mem.Allocator {
                return gpa.allocator();
            }

            fn deinit(_: *@This()) std.heap.Check {
                return gpa.deinit();
            }
        };
    } else {
        return struct {
            fn allocator(_: *@This()) std.mem.Allocator {
                return std.heap.c_allocator;
            }

            fn deinit(_: *@This()) std.heap.Check {
                return .ok;
            }
        };
    }
}

pub fn main() !void {
    var debugAllocator = DebuggableAllocator(){};
    defer std.debug.assert(debugAllocator.deinit() == .ok);

    const allocator = debugAllocator.allocator();

    var app = try App.init(allocator);
    defer app.deinit();
    try app.connect();

    while (app.running) {
        try app.dispatch();
    }

    std.log.info("end", .{});
}
