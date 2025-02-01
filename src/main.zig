const std = @import("std");
const builtin = @import("builtin");

const wayland = @import("wayland");
const wl = wayland.client.wl;

const Allocator = std.mem.Allocator;

const App = @import("app.zig");
const Renderer = @import("renderer.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    var app = try App.init(allocator);
    defer app.deinit();
    try app.connect();

    while (app.running) {
        try app.dispatch();
    }

    std.log.info("end", .{});
}
