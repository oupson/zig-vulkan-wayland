const std = @import("std");
const mem = std.mem;

const W = std.unicode.utf8ToUtf16LeStringLiteral;

const windows = @cImport({
    @cDefine("MIDL_INTERFACE", "struct");
    @cInclude("Windows.h");
    @cInclude("vulkan/vulkan.h");
    @cInclude("vulkan/vulkan_win32.h");
});

const Renderer = @import("renderer.zig");
const Chunk = @import("chunk.zig");
const TextureManager = @import("texture_manager.zig");

const Allocator = std.mem.Allocator;

const Self = @This();

allocator: Allocator,
running: bool = false,
hInstance: windows.HINSTANCE = null,
hWnd: windows.HWND = null,
renderer: ?Renderer = null,
vulkanInstance: Renderer.Instance,
camera: Renderer.Camera = .{
    .y = 10,
    .yaw = 90,
},
world: [][10][10]Chunk,
textureManager: TextureManager,
recreate: bool = true,
keyboard_state: struct {
    forward: i32 = 0,
    right: i32 = 0,
    up: i32 = 0,
} = .{},
lastFrame: std.time.Instant,

const required_extensions: [1]*align(1) const [:0]u8 = .{
    @ptrCast(windows.VK_KHR_WIN32_SURFACE_EXTENSION_NAME),
};

pub fn init(allocator: Allocator) !Self {
    const world = try allocator.alloc([10][10]Chunk, 10);

    for (world) |*zchunk| {
        for (zchunk) |*ychunk| {
            for (ychunk) |*c| {
                c.* = Chunk.init(allocator);

                for (0..64) |x| {
                    for (0..64) |z| {
                        try c.putBlock(x, 0, z, if (std.crypto.random.boolean()) 1 else 2);
                    }
                }

                try c.putBlock(1, 2, 1, 3);
            }
        }
    }

    const textureManager = try TextureManager.init(allocator);
    return Self{
        .allocator = allocator,
        .vulkanInstance = try Renderer.Instance.init(allocator, &required_extensions),
        .world = world,
        .textureManager = textureManager,
        .lastFrame = try std.time.Instant.now(),
    };
}

pub fn deinit(self: *Self) void {
    if (self.renderer) |*r| {
        r.deinit() catch |e| {
            std.log.err("failed to deinit renderer: {}", .{e});
        };
    }
    self.allocator.free(self.world);
    self.vulkanInstance.deinit();
}

pub fn connect(self: *Self) !void {
    const hInstance = windows.GetModuleHandleW(null);

    const windowClass: windows.WNDCLASSEXW = .{
        .cbSize = @sizeOf(windows.WNDCLASSEXW), // cbSize
        .style = windows.CS_OWNDC, // | CS_HREDRAW | CS_VREDRAW*/, // style -- some window behavior
        .lpfnWndProc = wndProc, // lpfnWndProc -- set event handler
        .cbClsExtra = 0, // cbClsExtra -- set 0 extra bytes after class
        .cbWndExtra = @sizeOf(*Self), // cbWndExtra -- set 0 extra bytes after class instance
        .hInstance = hInstance, // hInstance
        .hIcon = windows.LoadIconA(null, windows.IDI_APPLICATION), // hIcon -- application icon
        .hCursor = windows.LoadCursorA(null, windows.IDC_ARROW), // hCursor -- cursor inside
        .hbrBackground = null, //(HBRUSH)( COLOR_WINDOW + 1 ), // hbrBackground
        .lpszMenuName = null, // lpszMenuName -- menu class name
        .lpszClassName = W("vkwc"), // lpszClassName -- window class name/identificator
        .hIconSm = windows.LoadIconA(null, windows.IDI_APPLICATION), // hIconSm
    };

    // register window class
    const classAtom = windows.RegisterClassExW(&windowClass);
    if (classAtom == 0) {
        return error.FailedToRegisterWindow;
        // throw std::string( "Trouble registering window class: " ) + std::to_string( GetLastError() );
    }

    const windowedStyle = windows.WS_OVERLAPPEDWINDOW | windows.WS_CLIPCHILDREN | windows.WS_CLIPSIBLINGS;
    const windowedExStyle = windows.WS_EX_OVERLAPPEDWINDOW;

    var windowRect = windows.RECT{
        .left = 0,
        .top = 0,
        .right = 480,
        .bottom = 480,
    };
    if (windows.AdjustWindowRectEx(&windowRect, windowedStyle, windows.FALSE, windowedExStyle) == 0) {
        // throw string( "Trouble adjusting window size: " ) + to_string( GetLastError() );
        return error.FailedToAdjustWindowSize;
    }

    const hWnd = windows.CreateWindowExA(
        windowedExStyle,
        windows.MAKEINTATOM(classAtom),
        "vulkan",
        windowedStyle,
        windows.CW_USEDEFAULT,
        windows.CW_USEDEFAULT,
        windowRect.right - windowRect.left,
        windowRect.bottom - windowRect.top,
        null,
        null,
        hInstance,
        null,
    );
    if (hWnd == 0) {
        // throw string( "Trouble creating window instance: " ) + to_string( GetLastError() );
        return error.FailedToCreateWindow;
    }

    windows.SetLastError(0);
    _ = windows.SetWindowLongPtr(hWnd, windows.GWLP_USERDATA, @intCast(@intFromPtr(self)));
    if (windows.GetLastError() != 0) {
        unreachable;
    }

    self.running = true;
    self.hWnd = hWnd;
    self.hInstance = hInstance;

    self.renderer = try Renderer.new(
        self.vulkanInstance,
        self.allocator,
        self.textureManager,
        .{
            .ptr = self,
            .vtable = .{
                .createVulkanSurface = @ptrCast(&createSurface),
            },
        },
    );
    self.renderer.?.updateWorld(self.world);

    _ = windows.ShowWindow(hWnd, windows.SW_SHOW); // TODO
    _ = windows.SetForegroundWindow(hWnd); // TODO
    // _ = windows.SetCapture(hWnd);
}

pub fn dispatch(self: *Self) !void {
    var msg: windows.MSG = undefined;
    while (true) {
        if (self.recreate) {
            try self.renderer.?.recreate(0, 0);
            self.recreate = false;
        }

        const ret = windows.GetMessageW(&msg, null, 0, 0);

        if (ret == 0) {
            break;
        }
        // TODO ERROR CHECK
        _ = windows.TranslateMessage(&msg);
        _ = windows.DispatchMessageW(&msg); //dispatch to wndProc; ignore return from wndProc
    }
}

fn createSurface(thiz: *anyopaque, vkInstance: windows.VkInstance) anyerror!windows.VkSurfaceKHR {
    const self: *Self = @ptrCast(@alignCast(thiz));

    var createInfo = windows.VkWin32SurfaceCreateInfoKHR{
        .sType = windows.VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
        .hinstance = self.hInstance,
        .hwnd = self.hWnd,
    };

    var vulkanSurface: windows.VkSurfaceKHR = null;
    if (windows.VK_SUCCESS != windows.vkCreateWin32SurfaceKHR(vkInstance, &createInfo, null, &vulkanSurface)) return error.FailedToCreateVulkanSurface;
    return vulkanSurface;
}

fn wndProc(hWnd: windows.HWND, uMsg: windows.UINT, wParam: windows.WPARAM, lParam: windows.LPARAM) callconv(.c) windows.LRESULT {
    const ptr = windows.GetWindowLongPtr(hWnd, windows.GWLP_USERDATA);
    if (ptr == 0) {
        return windows.DefWindowProc(hWnd, uMsg, wParam, lParam);
    }

    const self: *Self = @ptrFromInt(@as(usize, @intCast(ptr))); // TODO: check not null

    switch (uMsg) {
        windows.WM_CLOSE => {
            windows.PostQuitMessage(0);
            self.running = false;
            return 0;
        },
        // background will be cleared by Vulkan in WM_PAINT instead
        windows.WM_ERASEBKGND => {
            return 0;
        },

        windows.WM_SIZE => {
            //logger << "size " << wParam << " " << LOWORD( lParam ) << "x" << HIWORD( lParam ) << std::endl;
            // hasSwapchain = sizeEventHandler();
            // if (!hasSwapchain) ValidateRect(hWnd, NULL); // prevent WM_PAINT on minimized window
            self.recreate = true;
            return 0;
        },

        windows.WM_PAINT => { // sent after WM_SIZE -- react to this immediately to resize seamlessly
            //logger << "paint\n";
            // paintEventHandler();

            const lastFrame = self.lastFrame;
            self.lastFrame = std.time.Instant.now() catch {
                unreachable;
            };

            const deltaTime: f32 = @floatCast(@as(f64, @floatFromInt(self.lastFrame.since(lastFrame))) / 1000000000.0);

            const camera = &self.camera;
            const keyboard_state = &self.keyboard_state;

            const yaw = std.math.degreesToRadians(camera.yaw);
            const forward = @as(f32, @floatFromInt(keyboard_state.forward));
            const right = @as(f32, @floatFromInt(keyboard_state.right));

            const x = std.math.sin(yaw) * forward + std.math.cos(-yaw) * right;
            const z = std.math.cos(yaw) * forward + std.math.sin(-yaw) * right;

            camera.x += @as(f32, x) * deltaTime;
            camera.y += @as(f32, @floatFromInt(keyboard_state.up)) * deltaTime;
            camera.z += @as(f32, z) * deltaTime;

            self.renderer.?.draw(&self.camera) catch |e| {
                if (e == error.RecreateSwapchain) {
                    std.log.err("recreating swapchain", .{});
                    self.recreate = true;
                } else {
                    std.log.err("failed to draw : {}", .{e});
                    self.running = false;
                }
            };
            //ValidateRect( hWnd, NULL ); // never validate so window always gets redrawn
            return 0;
        },
        windows.WM_KEYUP => {
            switch (wParam) {
                'W' => self.keyboard_state.forward -= 1,
                'S' => self.keyboard_state.forward += 1,
                'D' => self.keyboard_state.right -= 1,
                'A' => self.keyboard_state.right += 1,
                windows.VK_SPACE => self.keyboard_state.up -= 1,
                windows.VK_SHIFT => self.keyboard_state.up += 1,
                else => {
                    return windows.DefWindowProc(hWnd, uMsg, wParam, lParam);
                },
            }
            return 0;
        },
        windows.WM_KEYDOWN => {
            const keyFlags = @shrExact(lParam, 16) & 0xffff;
            const wasKeyDown = (keyFlags & windows.KF_REPEAT) == windows.KF_REPEAT;
            if (!wasKeyDown) {
                switch (wParam) {
                    windows.VK_ESCAPE => {
                        windows.PostQuitMessage(0);
                        self.running = false;
                    },
                    'W' => self.keyboard_state.forward += 1,
                    'S' => self.keyboard_state.forward -= 1,
                    'D' => self.keyboard_state.right += 1,
                    'A' => self.keyboard_state.right -= 1,
                    windows.VK_SPACE => self.keyboard_state.up += 1,
                    windows.VK_SHIFT => self.keyboard_state.up -= 1,
                    else => {
                        return windows.DefWindowProc(hWnd, uMsg, wParam, lParam);
                    },
                }
            }
            return 0;
        },

        windows.WM_SYSCOMMAND => {
            switch (wParam) {
                windows.SC_KEYMENU => {
                    if (lParam == windows.VK_RETURN) { // Alt-Enter without "no sysmenu hotkey exists" beep
                        // toggleFullscreen(hWnd);
                        return 0;
                    } else return windows.DefWindowProc(hWnd, uMsg, wParam, lParam);
                },
                else => {
                    return windows.DefWindowProc(hWnd, uMsg, wParam, lParam);
                },
            }
        },

        windows.WM_MOUSEMOVE => {
            return 0;
        },

        else => return windows.DefWindowProc(hWnd, uMsg, wParam, lParam),
    }
}
