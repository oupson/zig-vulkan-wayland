const std = @import("std");
const mem = std.mem;
const posix = std.posix;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;

const Allocator = std.mem.Allocator;
const Renderer = @import("renderer.zig");

const Context = struct {
    shm: ?*wl.Shm = null,
    compositor: ?*wl.Compositor = null,
    wm_base: ?*xdg.WmBase = null,
    display: *wl.Display = undefined,
    registry: *wl.Registry = undefined,
    surface: *wl.Surface = undefined,
    xdg_surface: *xdg.Surface = undefined,
    xdg_top_level: *xdg.Toplevel = undefined,
};

allocator: Allocator,
vulkanInstance: Renderer.Instance,
context: Context = .{},
running: bool,
width: i32 = 0,
height: i32 = 0,
recreate: bool = false,
renderer: ?Renderer = null,

const Self = @This();

pub fn init(allocator: Allocator) !Self {
    const vulkanInstance = try Renderer.Instance.init(allocator);
    const self = Self{
        .allocator = allocator,
        .vulkanInstance = vulkanInstance,
        .running = true,
    };

    return self;
}

pub fn connect(self: *Self) !void {
    const display = try wl.Display.connect(null);
    const registry = try display.getRegistry();

    self.context.display = display;
    self.context.registry = registry;

    registry.setListener(*Context, registryListener, &self.context);
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    //const shm = context.shm orelse return error.NoWlShm;
    const compositor = self.context.compositor orelse return error.NoWlCompositor;
    const wm_base = self.context.wm_base orelse return error.NoXdgWmBase;

    self.context.surface = try compositor.createSurface();
    self.context.xdg_surface = try wm_base.getXdgSurface(self.context.surface);
    self.context.xdg_top_level = try self.context.xdg_surface.getToplevel();

    self.context.xdg_surface.setListener(*wl.Surface, xdgSurfaceListener, self.context.surface);
    self.context.xdg_top_level.setListener(*Self, xdgToplevelListener, self);

    self.context.surface.commit();
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
}

pub fn deinit(self: *Self) void {
    if (self.renderer) |r| {
        r.deinit() catch |e| {
            std.log.err("failed to deinit renderer: {}", .{e});
        };
    }
    self.context.xdg_top_level.destroy();
    self.context.xdg_surface.destroy();
    self.context.surface.destroy();
    self.context.registry.destroy();
    self.context.display.disconnect();
}

pub fn dispatch(self: *Self) !void {
    if (self.recreate) {
        if (self.renderer) |r| {
            try r.deinit();
        }
        self.renderer = try Renderer.new(
            self.vulkanInstance,
            self.allocator,
            self.context.display,
            self.context.surface,
            self.width,
            self.height,
        );
        try self.renderer.?.draw();
        self.recreate = false;

        const frame = try self.context.surface.frame();
        frame.setListener(*Self, frameCallback, self);
    }
    if (self.context.display.roundtrip() != .SUCCESS) return error.DispatchFailed;
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, context: *Context) void {
    switch (event) {
        .global => |global| {
            if (mem.orderZ(u8, global.interface, wl.Compositor.interface.name) == .eq) {
                context.compositor = registry.bind(global.name, wl.Compositor, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, wl.Shm.interface.name) == .eq) {
                context.shm = registry.bind(global.name, wl.Shm, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, xdg.WmBase.interface.name) == .eq) {
                context.wm_base = registry.bind(global.name, xdg.WmBase, 1) catch return;
            }
        },
        .global_remove => {},
    }
}

fn xdgSurfaceListener(xdg_surface: *xdg.Surface, event: xdg.Surface.Event, surface: *wl.Surface) void {
    switch (event) {
        .configure => |configure| {
            xdg_surface.ackConfigure(configure.serial);
            surface.commit();

            std.log.info("configure", .{});
        },
    }
}

fn xdgToplevelListener(_: *xdg.Toplevel, event: xdg.Toplevel.Event, app: *Self) void {
    switch (event) {
        .configure => |configure| {
            if (app.width != configure.width or app.height != configure.height) {
                app.width = configure.width;
                app.height = configure.height;
                app.recreate = true;
            }
            std.log.debug("xdg top level configure {}x{}", .{ configure.width, configure.height });
        },
        .wm_capabilities => {},
        .configure_bounds => {},
        .close => {
            app.running = false;
        },
    }
}

fn frameCallback(callback: *wl.Callback, event: wl.Callback.Event, data: *Self) void {
    _ = event;
    callback.destroy();

    if (data.renderer) |r| {
        r.draw() catch |e| {
            std.log.err("failed to render: {}", .{e});
        };
    }

    const frame = data.context.surface.frame() catch return;
    frame.setListener(*Self, frameCallback, data);
}
