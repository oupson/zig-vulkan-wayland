const std = @import("std");
const mem = std.mem;
const posix = std.posix;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zxdg = wayland.client.zxdg;
const zwp = wayland.client.zwp;
const Allocator = std.mem.Allocator;
const Renderer = @import("renderer.zig");
const Keyboard = @import("keyboard.zig");

const Context = struct {
    shm: ?*wl.Shm = null,
    compositor: ?*wl.Compositor = null,
    wm_base: ?*xdg.WmBase = null,
    display: *wl.Display = undefined,
    registry: *wl.Registry = undefined,
    surface: *wl.Surface = undefined,
    xdg_surface: *xdg.Surface = undefined,
    xdg_top_level: *xdg.Toplevel = undefined,
    zxdg_decoration_manager: ?*zxdg.DecorationManagerV1 = null,
    zxdg_decoration: ?*zxdg.ToplevelDecorationV1 = null,
    seat: *wl.Seat = undefined,
    pointer: ?*wl.Pointer = null,
    pointer_constraint: *zwp.PointerConstraintsV1 = undefined,
    locked_pointer: ?*zwp.LockedPointerV1 = null,
    relative_pointer_manager: *zwp.RelativePointerManagerV1 = undefined,
    relative_pointer: ?*zwp.RelativePointerV1 = null,
    keyboard: ?*wl.Keyboard = null,
    keyboardParser: Keyboard = undefined,
    keyboard_state: struct {
        forward: i32 = 0,
        right: i32 = 0,
        up: i32 = 0,
    } = .{},
};

allocator: Allocator,
vulkanInstance: Renderer.Instance,
context: Context = .{},
running: bool,
width: i32 = 0,
height: i32 = 0,
recreate: bool = false,
renderer: ?Renderer = null,
lastFrame: std.time.Instant,
camera: Renderer.Camera = .{},

const Self = @This();

pub fn init(allocator: Allocator) !Self {
    const vulkanInstance = try Renderer.Instance.init(allocator);
    const self = Self{
        .allocator = allocator,
        .vulkanInstance = vulkanInstance,
        .running = true,
        .lastFrame = try std.time.Instant.now(),
    };

    return self;
}

pub fn connect(self: *Self) !void {
    const display = try wl.Display.connect(null);
    const registry = try display.getRegistry();

    self.context.display = display;
    self.context.registry = registry;

    registry.setListener(*Self, registryListener, self);
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    //const shm = context.shm orelse return error.NoWlShm;
    const compositor = self.context.compositor orelse return error.NoWlCompositor;
    const wm_base = self.context.wm_base orelse return error.NoXdgWmBase;

    self.context.surface = try compositor.createSurface();
    self.context.xdg_surface = try wm_base.getXdgSurface(self.context.surface);
    self.context.xdg_top_level = try self.context.xdg_surface.getToplevel();

    self.context.xdg_surface.setListener(*wl.Surface, xdgSurfaceListener, self.context.surface);
    self.context.xdg_top_level.setListener(*Self, xdgToplevelListener, self);

    if (self.context.zxdg_decoration_manager) |dec| {
        self.context.zxdg_decoration = try dec.getToplevelDecoration(self.context.xdg_top_level);
        self.context.zxdg_decoration.?.setMode(.server_side);
    }

    self.context.surface.commit();

    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
}

pub fn deinit(self: *Self) void {
    if (self.renderer) |r| {
        r.deinit() catch |e| {
            std.log.err("failed to deinit renderer: {}", .{e});
        };
    }
    self.context.keyboardParser.deinit();
    if (self.context.relative_pointer) |pointer| {
        pointer.destroy();
    }
    self.context.relative_pointer_manager.destroy();
    if (self.context.locked_pointer) |p| {
        p.destroy();
    }
    self.context.pointer_constraint.destroy();
    if (self.context.pointer) |pointer| {
        pointer.release();
    }
    if (self.context.keyboard) |keyboard| {
        keyboard.release();
    }
    self.context.seat.destroy();
    if (self.context.zxdg_decoration) |dec| {
        dec.destroy();
    }
    if (self.context.zxdg_decoration_manager) |manager| {
        manager.destroy();
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
        self.recreate = false;
    }

    const lastFrame = self.lastFrame;
    self.lastFrame = try std.time.Instant.now();

    const deltaTime: f32 = @floatCast(@as(f64, @floatFromInt(self.lastFrame.since(lastFrame))) / 1000000000.0);

    const camera = &self.camera;
    const keyboard_state = &self.context.keyboard_state;

    const yaw = std.math.degreesToRadians(camera.yaw);
    const forward = @as(f32, @floatFromInt(keyboard_state.forward));
    const right = @as(f32, @floatFromInt(keyboard_state.right));

    const x = std.math.cos(yaw) * forward + std.math.sin(-yaw) * right;
    const z = std.math.sin(yaw) * forward + std.math.cos(-yaw) * right;

    camera.x += @as(f32, x) * deltaTime;
    camera.y += @as(f32, @floatFromInt(keyboard_state.up)) * deltaTime;
    camera.z += @as(f32, z) * deltaTime;

    try self.renderer.?.draw(&self.camera);

    if (self.context.display.dispatch() != .SUCCESS) return error.DispatchFailed;
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, data: *Self) void {
    var context = &data.context;
    switch (event) {
        .global => |global| {
            std.log.debug("registry interface : {s}", .{global.interface});
            if (mem.orderZ(u8, global.interface, wl.Compositor.interface.name) == .eq) {
                context.compositor = registry.bind(global.name, wl.Compositor, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, wl.Shm.interface.name) == .eq) {
                context.shm = registry.bind(global.name, wl.Shm, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, xdg.WmBase.interface.name) == .eq) {
                context.wm_base = registry.bind(global.name, xdg.WmBase, 1) catch return;
                context.wm_base.?.setListener(?*anyopaque, wmBaseListener, null);
            } else if (mem.orderZ(u8, global.interface, zxdg.DecorationManagerV1.interface.name) == .eq) {
                context.zxdg_decoration_manager = registry.bind(global.name, zxdg.DecorationManagerV1, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, wl.Seat.interface.name) == .eq) {
                context.seat = registry.bind(global.name, wl.Seat, 8) catch return;
                context.seat.setListener(*Self, wlSeatListener, data);
            } else if (mem.orderZ(u8, global.interface, zwp.PointerConstraintsV1.interface.name) == .eq) {
                context.pointer_constraint = registry.bind(global.name, zwp.PointerConstraintsV1, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, zwp.RelativePointerManagerV1.interface.name) == .eq) {
                context.relative_pointer_manager = registry.bind(global.name, zwp.RelativePointerManagerV1, 1) catch return;
            }
        },
        .global_remove => {},
    }
}

fn wmBaseListener(wm_base: *xdg.WmBase, event: xdg.WmBase.Event, _: ?*anyopaque) void {
    switch (event) {
        .ping => |ping| {
            wm_base.pong(ping.serial);
        },
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
            const newWidth = if (configure.width == 0) 640 else configure.width;
            const newHeight = if (configure.height == 0) 400 else configure.height;
            if (app.width != newWidth or app.height != newHeight) {
                app.width = newWidth;
                app.height = newHeight;
                app.recreate = true;
            }
            std.log.debug("xdg top level configure {}x{}", .{ app.width, app.height });
        },
        .wm_capabilities => {},
        .configure_bounds => {},
        .close => {
            app.running = false;
        },
    }
}

fn wlSeatListener(seat: *wl.Seat, event: wl.Seat.Event, data: *Self) void {
    _ = seat;
    switch (event) {
        .name => |name| {
            std.log.debug("seat name : {s}", .{name.name});
        },
        .capabilities => |capabilities| {
            std.log.debug("seat capabilities : pointer = {}, keyboard = {}, touch = {}", .{
                capabilities.capabilities.pointer,
                capabilities.capabilities.keyboard,
                capabilities.capabilities.touch,
            });
            if (capabilities.capabilities.pointer and data.context.pointer == null) {
                // todo: multiple
                data.context.pointer = data.context.seat.getPointer() catch unreachable;
                data.context.pointer.?.setListener(*Self, wlPointerListener, data);
                data.context.locked_pointer = data.context.pointer_constraint.lockPointer(data.context.surface, data.context.pointer.?, null, .persistent) catch unreachable;
                data.context.relative_pointer = data.context.relative_pointer_manager.getRelativePointer(data.context.pointer.?) catch unreachable; //todo
                data.context.relative_pointer.?.setListener(*Self, relativePointerListener, data);
            }

            if (capabilities.capabilities.keyboard and data.context.keyboard == null) {
                data.context.keyboard = data.context.seat.getKeyboard() catch unreachable;
                data.context.keyboardParser = Keyboard.init() catch unreachable;
                data.context.keyboard.?.setListener(*Self, wlKeyboardListener, data);
            }
        },
    }
}

fn wlPointerListener(pointer: *wl.Pointer, event: wl.Pointer.Event, data: *Self) void {
    _ = pointer;
    //std.log.debug("{any} {any}", .{ event, data.camera });
    switch (event) {
        .enter => |enter| {
            data.context.pointer.?.setCursor(enter.serial, null, 0, 0);
        },
        .leave => |_| {},
        .motion => {},
        .button => |_| {},
        .axis => |_| {},
        .frame => {},
        .axis_source => |_| {},
        .axis_stop => |_| {},
        .axis_discrete => |_| {},
        .axis_value120 => |_| {},
    }
}
fn relativePointerListener(relative_pointer_v1: *zwp.RelativePointerV1, event: zwp.RelativePointerV1.Event, data: *Self) void {
    _ = relative_pointer_v1;
    switch (event) {
        .relative_motion => |motion| {
            data.camera.yaw += @floatCast(motion.dx_unaccel.toDouble() * 0.1);
            data.camera.pitch += @floatCast(motion.dy_unaccel.toDouble() * 0.1);
        },
    }
}
fn wlKeyboardListener(keyboard: *wl.Keyboard, event: wl.Keyboard.Event, data: *Self) void {
    _ = keyboard;
    switch (event) {
        .keymap => |keymap| {
            if (keymap.format == .xkb_v1) {
                data.context.keyboardParser.parseKeymap(keymap.fd, keymap.size) catch unreachable;
            } else {
                std.log.warn("unknown keymap : {}", .{keymap.format});
            }
        },
        .enter => |e| {
            const keys = e.keys.slice(u32);
            for (keys) |key| {
                const xkbKey = Keyboard.toLower(data.context.keyboardParser.parseKeyCode(key));
                std.log.debug("{} {} {}", .{ true, xkbKey, data.context.keyboard_state });
                switch (xkbKey) {
                    Keyboard.xkbcommon.XKB_KEY_w => data.context.keyboard_state.forward += 1,
                    Keyboard.xkbcommon.XKB_KEY_s => data.context.keyboard_state.forward -= 1,
                    Keyboard.xkbcommon.XKB_KEY_d => data.context.keyboard_state.right += 1,
                    Keyboard.xkbcommon.XKB_KEY_a => data.context.keyboard_state.right -= 1,
                    Keyboard.xkbcommon.XKB_KEY_space => data.context.keyboard_state.up -= 1,
                    Keyboard.xkbcommon.XKB_KEY_Shift_L => data.context.keyboard_state.up += 1,
                    else => {},
                }
            }
        },
        .leave => {},
        .key => |key| {
            const xkbKey = Keyboard.toLower(data.context.keyboardParser.parseKeyCode(key.key));
            if (key.state == .released) {
                switch (xkbKey) {
                    Keyboard.xkbcommon.XKB_KEY_w => data.context.keyboard_state.forward -= 1,
                    Keyboard.xkbcommon.XKB_KEY_s => data.context.keyboard_state.forward += 1,
                    Keyboard.xkbcommon.XKB_KEY_d => data.context.keyboard_state.right -= 1,
                    Keyboard.xkbcommon.XKB_KEY_a => data.context.keyboard_state.right += 1,
                    Keyboard.xkbcommon.XKB_KEY_space => data.context.keyboard_state.up += 1,
                    Keyboard.xkbcommon.XKB_KEY_Shift_L => data.context.keyboard_state.up -= 1,
                    else => {},
                }
            } else {
                switch (xkbKey) {
                    Keyboard.xkbcommon.XKB_KEY_w => data.context.keyboard_state.forward += 1,
                    Keyboard.xkbcommon.XKB_KEY_s => data.context.keyboard_state.forward -= 1,
                    Keyboard.xkbcommon.XKB_KEY_d => data.context.keyboard_state.right += 1,
                    Keyboard.xkbcommon.XKB_KEY_a => data.context.keyboard_state.right -= 1,
                    Keyboard.xkbcommon.XKB_KEY_space => data.context.keyboard_state.up -= 1,
                    Keyboard.xkbcommon.XKB_KEY_Shift_L => data.context.keyboard_state.up += 1,
                    else => {},
                }
            }
        },
        .modifiers => |modifiers| {
            data.context.keyboardParser.setModifier(modifiers.mods_depressed, modifiers.mods_latched, modifiers.mods_locked, modifiers.group);
        },
        .repeat_info => {},
    }
}
