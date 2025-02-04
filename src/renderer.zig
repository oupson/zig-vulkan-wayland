const std = @import("std");
const builtin = @import("builtin");

const vulkan = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("vulkan/vulkan_wayland.h");
});

const wayland = @import("wayland");
const wl = wayland.client.wl;

const validationLayerName: [1][:0]const u8 = .{
    "VK_LAYER_KHRONOS_validation",
};

const deviceExtensions: [1]*align(1) const [:0]u8 = .{
    @ptrCast(vulkan.VK_KHR_SWAPCHAIN_EXTENSION_NAME),
};

const requiredExtensions: [3]*align(1) const [:0]u8 = .{
    @ptrCast(vulkan.VK_KHR_SURFACE_EXTENSION_NAME),
    @ptrCast(vulkan.VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME),
    @ptrCast(vulkan.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME),
};

const MAX_FRAMES_IN_FLIGHT: usize = 2;

const Allocator = std.mem.Allocator;
const Self = @This();

pub const Instance = struct {
    instance: vulkan.VkInstance,

    pub fn init(allocator: Allocator) !@This() {
        const instance = try createInstance(allocator);
        return @This(){
            .instance = instance,
        };
    }

    pub fn deinit(self: *@This()) void {
        std.log.debug("deinit instance", .{});
        vulkan.vkDestroyInstance(self.instance, null);
    }
};

const Vertex = struct {
    pos: @Vector(2, f32),
    color: @Vector(3, f32),

    fn getBindingDescription() vulkan.VkVertexInputBindingDescription {
        var bindingDescription = vulkan.VkVertexInputBindingDescription{};
        bindingDescription.binding = 0;
        bindingDescription.stride = @sizeOf(@This());
        bindingDescription.inputRate = vulkan.VK_VERTEX_INPUT_RATE_VERTEX;

        return bindingDescription;
    }

    fn getAttributeDescriptions() [2]vulkan.VkVertexInputAttributeDescription {
        var attributeDescriptions: [2]vulkan.VkVertexInputAttributeDescription = .{ .{}, .{} };
        attributeDescriptions[0].binding = 0;
        attributeDescriptions[0].location = 0;
        attributeDescriptions[0].format = vulkan.VK_FORMAT_R32G32_SFLOAT;
        attributeDescriptions[0].offset = @offsetOf(Vertex, "pos");

        attributeDescriptions[1].binding = 0;
        attributeDescriptions[1].location = 1;
        attributeDescriptions[1].format = vulkan.VK_FORMAT_R32G32B32_SFLOAT;
        attributeDescriptions[1].offset = @offsetOf(Vertex, "color");

        return attributeDescriptions;
    }
};

const vertices = [_]Vertex{
    .{ .pos = .{ -0.5, -0.5 }, .color = .{ 1.0, 0.0, 0.0 } },
    .{ .pos = .{ 0.5, -0.5 }, .color = .{ 0.0, 1.0, 0.0 } },
    .{ .pos = .{ 0.5, 0.5 }, .color = .{ 0.0, 0.0, 1.0 } },
    .{ .pos = .{ -0.5, 0.5 }, .color = .{ 1.0, 1.0, 1.0 } },
};

const indices = [_]u16{ 0, 1, 2, 2, 3, 0 };

allocator: Allocator,
instance: vulkan.VkInstance,
vulkanSurface: vulkan.VkSurfaceKHR,
device: vulkan.VkDevice,
graphicQueue: vulkan.VkQueue,
presentQueue: vulkan.VkQueue,
swapChain: vulkan.VkSwapchainKHR,
extent: vulkan.VkExtent2D,
imageViewList: []vulkan.VkImageView,
renderPass: vulkan.VkRenderPass,
pipelineLayout: vulkan.VkPipelineLayout,
pipeline: vulkan.VkPipeline,
swapChainFramebuffers: []vulkan.VkFramebuffer,
commandPool: vulkan.VkCommandPool,
vertexBuffer: vulkan.VkBuffer,
vertexBufferMemory: vulkan.VkDeviceMemory,
indexBuffer: vulkan.VkBuffer,
indexBufferMemory: vulkan.VkDeviceMemory,
commandBuffers: []vulkan.VkCommandBuffer,
imageAvailableSemaphores: []vulkan.VkSemaphore,
renderFinishedSemaphores: []vulkan.VkSemaphore,
inFlightFences: []vulkan.VkFence,
currentFrame: usize = 0,

pub fn new(
    vulkanInstance: Instance,
    allocator: Allocator,
    display: *wl.Display,
    surface: *wl.Surface,
    width: i32,
    height: i32,
) !Self {
    const instance = vulkanInstance.instance;
    const vulkanSurface = try createSurface(instance, display, surface);

    const physicalDevice = try getPhysicalDevice(instance, allocator, vulkanSurface);

    const familyIndice = try findQueueFamilyIndice(physicalDevice, allocator, vulkanSurface);

    const device = try createDevice(physicalDevice, familyIndice);

    var graphicQueue: vulkan.VkQueue = null;
    vulkan.vkGetDeviceQueue(device, familyIndice.graphics.?, 0, &graphicQueue);
    var presentQueue: vulkan.VkQueue = null;
    vulkan.vkGetDeviceQueue(device, familyIndice.present.?, 0, &presentQueue);

    const swapChain, const format, const extent = try createSwapChain(
        allocator,
        device,
        physicalDevice,
        vulkanSurface,
        width,
        height,
    );

    const imageList = try getImageList(allocator, device, swapChain);
    defer allocator.free(imageList);

    const imageViewList = try getImageViewList(allocator, device, imageList, format);

    const renderPass = try createRenderPass(device, format.format);
    const pipelineLayout, const pipeline = try createGraphicPipeline(allocator, device, extent, renderPass); //  while (app.running) {

    const swapChainFramebuffers = try createFramebuffers(allocator, device, imageViewList, renderPass, extent);

    const commandPool = try createCommandPool(allocator, physicalDevice, device, vulkanSurface);

    const vertexBuffer, const vertexBufferMemory = try createVertexBuffer(device, physicalDevice, commandPool, graphicQueue);
    const indexBuffer, const indexBufferMemory = try createIndexBuffer(device, physicalDevice, commandPool, graphicQueue);

    const commandBuffers = try createCommandBuffers(allocator, device, commandPool);
    const imageAvailableSemaphores, const renderFinishedSemaphores, const inFlightFences = try createSyncObjects(allocator, device);
    return Self{
        .allocator = allocator,
        .instance = instance,
        .vulkanSurface = vulkanSurface,
        .device = device,
        .graphicQueue = graphicQueue,
        .presentQueue = presentQueue,
        .swapChain = swapChain,
        .extent = extent,
        .imageViewList = imageViewList,
        .renderPass = renderPass,
        .pipelineLayout = pipelineLayout,
        .pipeline = pipeline,
        .swapChainFramebuffers = swapChainFramebuffers,
        .commandPool = commandPool,
        .vertexBuffer = vertexBuffer,
        .vertexBufferMemory = vertexBufferMemory,
        .indexBuffer = indexBuffer,
        .indexBufferMemory = indexBufferMemory,
        .commandBuffers = commandBuffers,
        .imageAvailableSemaphores = imageAvailableSemaphores,
        .renderFinishedSemaphores = renderFinishedSemaphores,
        .inFlightFences = inFlightFences,
    };
}

pub fn deinit(self: *const Self) !void {
    if (vulkan.VK_SUCCESS != vulkan.vkDeviceWaitIdle(self.device)) return error.VulkanError;
    vulkan.vkDestroyBuffer(self.device, self.vertexBuffer, null);
    vulkan.vkFreeMemory(self.device, self.vertexBufferMemory, null);

    vulkan.vkDestroyBuffer(self.device, self.indexBuffer, null);
    vulkan.vkFreeMemory(self.device, self.indexBufferMemory, null);

    for (self.inFlightFences) |fence| {
        vulkan.vkDestroyFence(self.device, fence, null);
    }
    self.allocator.free(self.inFlightFences);

    for (self.renderFinishedSemaphores) |semaphore| {
        vulkan.vkDestroySemaphore(self.device, semaphore, null);
    }
    self.allocator.free(self.renderFinishedSemaphores);

    for (self.imageAvailableSemaphores) |semaphore| {
        vulkan.vkDestroySemaphore(self.device, semaphore, null);
    }
    self.allocator.free(self.imageAvailableSemaphores);

    self.allocator.free(self.commandBuffers);

    vulkan.vkDestroyCommandPool(self.device, self.commandPool, null);

    for (self.swapChainFramebuffers) |framebuffer| {
        vulkan.vkDestroyFramebuffer(self.device, framebuffer, null);
    }
    self.allocator.free(self.swapChainFramebuffers);

    vulkan.vkDestroyPipeline(self.device, self.pipeline, null);
    vulkan.vkDestroyPipelineLayout(self.device, self.pipelineLayout, null);
    vulkan.vkDestroyRenderPass(self.device, self.renderPass, null);

    for (self.imageViewList) |imageView| {
        vulkan.vkDestroyImageView(self.device, imageView, null);
    }
    self.allocator.free(self.imageViewList);

    // imageList

    vulkan.vkDestroySwapchainKHR(self.device, self.swapChain, null);

    vulkan.vkDestroyDevice(self.device, null);

    vulkan.vkDestroySurfaceKHR(self.instance, self.vulkanSurface, null);
}

pub fn draw(self: *Self) !void {
    if (vulkan.VK_SUCCESS != vulkan.vkWaitForFences(self.device, 1, &self.inFlightFences[self.currentFrame], vulkan.VK_TRUE, std.math.maxInt(u64))) return error.VulkanError;
    if (vulkan.VK_SUCCESS != vulkan.vkResetFences(self.device, 1, &self.inFlightFences[self.currentFrame])) return error.VulkanError;

    var imageIndex: u32 = 0;

    if (vulkan.VK_SUCCESS != vulkan.vkAcquireNextImageKHR(
        self.device,
        self.swapChain,
        std.math.maxInt(u64),
        self.imageAvailableSemaphores[self.currentFrame],
        null,
        &imageIndex,
    )) return error.VulkanError;

    if (vulkan.VK_SUCCESS != vulkan.vkResetCommandBuffer(self.commandBuffers[self.currentFrame], 0)) return error.VulkanError;
    try recordCommandBuffer(
        self.commandBuffers[self.currentFrame],
        self.renderPass,
        self.extent,
        self.swapChainFramebuffers[imageIndex],
        self.pipeline,
        self.vertexBuffer,
        self.indexBuffer,
    );

    var submitInfo = vulkan.VkSubmitInfo{};
    submitInfo.sType = vulkan.VK_STRUCTURE_TYPE_SUBMIT_INFO;

    const waitSemaphores = [_]vulkan.VkSemaphore{self.imageAvailableSemaphores[self.currentFrame]};
    const waitStages = [_]vulkan.VkPipelineStageFlags{vulkan.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
    submitInfo.waitSemaphoreCount = waitSemaphores.len;
    submitInfo.pWaitSemaphores = &waitSemaphores;
    submitInfo.pWaitDstStageMask = &waitStages;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &self.commandBuffers[
        self.currentFrame
    ];

    const signalSemaphores = [_]vulkan.VkSemaphore{self.renderFinishedSemaphores[self.currentFrame]};
    submitInfo.signalSemaphoreCount = signalSemaphores.len;
    submitInfo.pSignalSemaphores = &signalSemaphores;

    if (vulkan.VK_SUCCESS != vulkan.vkQueueSubmit(self.graphicQueue, 1, &submitInfo, self.inFlightFences[self.currentFrame])) {
        return error.VulkanError;
    }

    self.currentFrame = (self.currentFrame + 1) % MAX_FRAMES_IN_FLIGHT;

    var presentInfo = vulkan.VkPresentInfoKHR{};
    presentInfo.sType = vulkan.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;

    presentInfo.waitSemaphoreCount = signalSemaphores.len;
    presentInfo.pWaitSemaphores = &signalSemaphores;

    const swapChains = [_]vulkan.VkSwapchainKHR{self.swapChain};
    presentInfo.swapchainCount = swapChains.len;
    presentInfo.pSwapchains = &swapChains;
    presentInfo.pImageIndices = &imageIndex;
    presentInfo.pResults = null; // Optional

    if (vulkan.VK_SUCCESS != vulkan.vkQueuePresentKHR(self.presentQueue, &presentInfo)) {
        return error.VulkanError;
    }
}

fn createInstance(allocator: Allocator) !vulkan.VkInstance {
    var appInfo = vulkan.VkApplicationInfo{};
    appInfo.sType = vulkan.VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = "Test Zig";
    appInfo.applicationVersion = vulkan.VK_MAKE_VERSION(1, 0, 0);
    appInfo.pEngineName = "No Engine";
    appInfo.engineVersion = vulkan.VK_MAKE_VERSION(1, 0, 0);
    appInfo.apiVersion = vulkan.VK_API_VERSION_1_0;

    var createInfo = vulkan.VkInstanceCreateInfo{};
    createInfo.sType = vulkan.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    createInfo.pApplicationInfo = &appInfo;
    createInfo.enabledLayerCount = 0;
    createInfo.flags = createInfo.flags | vulkan.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    createInfo.enabledExtensionCount = requiredExtensions.len;
    createInfo.ppEnabledExtensionNames = @ptrCast(&requiredExtensions);

    if (builtin.mode == .Debug) {
        const checkValidationLayerSupport = layerSupported: {
            var layerCount: u32 = 0;
            if (vulkan.VK_SUCCESS != vulkan.vkEnumerateInstanceLayerProperties(&layerCount, null)) {
                return error.VulkanError; // todo
            }

            const layerList = try allocator.alloc(vulkan.VkLayerProperties, layerCount);
            defer allocator.free(layerList);

            if (vulkan.VK_SUCCESS != vulkan.vkEnumerateInstanceLayerProperties(&layerCount, layerList.ptr)) {
                return error.VulkanError; // todo
            }

            for (layerList) |layer| {
                if (std.mem.orderZ(u8, @ptrCast(&layer.layerName), validationLayerName[0]) == .eq) {
                    break :layerSupported true;
                }
            }

            break :layerSupported false;
        };

        if (!checkValidationLayerSupport) {
            std.log.warn("missing validation layer", .{});
        } else {
            createInfo.enabledLayerCount = validationLayerName.len;
            createInfo.ppEnabledLayerNames = @ptrCast(&validationLayerName);
        }
    }

    var instance: vulkan.VkInstance = null;
    const result = vulkan.vkCreateInstance(&createInfo, null, &instance);
    if (result != vulkan.VK_SUCCESS) {
        return error.VulkanInitFailed;
    }
    return instance;
}

fn getPhysicalDevice(instance: vulkan.VkInstance, allocator: Allocator, surface: vulkan.VkSurfaceKHR) !vulkan.VkPhysicalDevice {
    var deviceCount: u32 = 0;
    if (vulkan.VK_SUCCESS != vulkan.vkEnumeratePhysicalDevices(instance, &deviceCount, null)) return error.VulkanError; // todo

    if (deviceCount == 0) {
        return error.NoVulkanDevice;
    }

    const deviceList = try allocator.alloc(vulkan.VkPhysicalDevice, deviceCount);
    defer allocator.free(deviceList);
    if (vulkan.VK_SUCCESS != vulkan.vkEnumeratePhysicalDevices(instance, &deviceCount, @ptrCast(deviceList.ptr))) return error.VulkanError; // todo

    for (deviceList) |device| {
        if (try isDeviceSuitable(device, allocator, surface)) {
            return device;
        }
    }

    return error.NoVulkanDevice;
}

// todo: improve on multi gpu setup
fn isDeviceSuitable(device: vulkan.VkPhysicalDevice, allocator: Allocator, surface: vulkan.VkSurfaceKHR) !bool {
    var deviceProperties: vulkan.VkPhysicalDeviceProperties = undefined;
    var deviceFeatures: vulkan.VkPhysicalDeviceFeatures = undefined;
    vulkan.vkGetPhysicalDeviceProperties(device, &deviceProperties);
    vulkan.vkGetPhysicalDeviceFeatures(device, &deviceFeatures);

    if (!(deviceProperties.deviceType == vulkan.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU or deviceProperties.deviceType == vulkan.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU)) {
        return false;
    }

    if (!try deviceExtensionSupported(device, allocator)) {
        return false;
    }

    var swapChainSupport = try SwapChainSupportDetails.tryInit(allocator, device, surface);
    defer swapChainSupport.deinit();

    if (swapChainSupport.formats.len == 0 or swapChainSupport.presentModes.len == 0) {
        return false;
    }

    return true;
}

fn deviceExtensionSupported(device: vulkan.VkPhysicalDevice, allocator: Allocator) !bool {
    var extensionCount: u32 = 0;
    if (vulkan.VK_SUCCESS != vulkan.vkEnumerateDeviceExtensionProperties(device, null, &extensionCount, null)) return error.VulkanError;

    const availableExtensions = try allocator.alloc(vulkan.VkExtensionProperties, @intCast(extensionCount));
    defer allocator.free(availableExtensions);
    if (vulkan.VK_SUCCESS != vulkan.vkEnumerateDeviceExtensionProperties(
        device,
        null,
        &extensionCount,
        availableExtensions.ptr,
    )) return error.VulkanError;

    for (availableExtensions) |ext| {
        // todo
        if (std.mem.orderZ(u8, @ptrCast(&ext.extensionName), @ptrCast(deviceExtensions[0])) == .eq) {
            return true;
        }
    }

    return false;
}

const QueueFamily = struct {
    graphics: ?u32 = null,
    present: ?u32 = null,
};

fn findQueueFamilyIndice(device: vulkan.VkPhysicalDevice, allocator: Allocator, surface: vulkan.VkSurfaceKHR) !QueueFamily {
    var queueFamilyCount: u32 = 0;
    vulkan.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, null);

    const queueFamilies = try allocator.alloc(vulkan.VkQueueFamilyProperties, queueFamilyCount);
    defer allocator.free(queueFamilies);

    vulkan.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, queueFamilies.ptr);

    var res = QueueFamily{};

    for (queueFamilies, 0..) |family, i| {
        if ((family.queueFlags & vulkan.VK_QUEUE_GRAPHICS_BIT) != 0) {
            res.graphics = @intCast(i);
        }
        var presentSupport: vulkan.VkBool32 = vulkan.VK_FALSE;
        if (vulkan.VK_SUCCESS != vulkan.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), surface, &presentSupport)) return error.VulkanFailed;
        if (presentSupport == vulkan.VK_TRUE) {
            res.present = @intCast(i);
        }
    }
    return res;
}

fn createDevice(physicalDevice: vulkan.VkPhysicalDevice, familyIndice: QueueFamily) !vulkan.VkDevice {
    var queuePriority: f32 = 1.0;

    var infos = [2]vulkan.VkDeviceQueueCreateInfo{
        .{
            .sType = vulkan.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueCount = 1,
            .pQueuePriorities = &queuePriority,
            .queueFamilyIndex = familyIndice.graphics.?, // todo
        },
        .{
            .sType = vulkan.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueCount = 1,
            .pQueuePriorities = &queuePriority,
            .queueFamilyIndex = familyIndice.present.?, // todo
        },
    };

    const count: u32 = if (familyIndice.present.? == familyIndice.graphics.?) 1 else 2;

    const deviceFeatures = vulkan.VkPhysicalDeviceFeatures{};

    var createInfo = vulkan.VkDeviceCreateInfo{};
    createInfo.sType = vulkan.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;

    createInfo.pQueueCreateInfos = &infos;
    createInfo.queueCreateInfoCount = count;

    createInfo.pEnabledFeatures = &deviceFeatures;

    createInfo.enabledExtensionCount = deviceExtensions.len;
    createInfo.ppEnabledExtensionNames = @ptrCast(&deviceExtensions);

    // if (enableValidationLayers) {
    //    createInfo.enabledLayerCount = static_cast<uint32_t>(validationLayers.size());
    //    createInfo.ppEnabledLayerNames = validationLayers.data();
    // } else {
    //        createInfo.enabledLayerCount = 0;
    //  }
    //
    var device: vulkan.VkDevice = null;
    if (vulkan.VK_SUCCESS != vulkan.vkCreateDevice(physicalDevice, &createInfo, null, &device)) {
        return error.FailedToCreateDevice;
    }
    return device;
}

fn createSurface(instance: vulkan.VkInstance, display: *wl.Display, surface: *wl.Surface) !vulkan.VkSurfaceKHR {
    var createInfo = vulkan.VkWaylandSurfaceCreateInfoKHR{};
    createInfo.sType = vulkan.VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR;
    createInfo.display = @ptrCast(display);
    createInfo.surface = @ptrCast(surface);

    var vulkanSurface: vulkan.VkSurfaceKHR = null;
    if (vulkan.VK_SUCCESS != vulkan.vkCreateWaylandSurfaceKHR(instance, &createInfo, null, &vulkanSurface)) return error.FailedToCreateVulkanSurface;
    return vulkanSurface;
}

const SwapChainSupportDetails = struct {
    allocator: Allocator,
    capabilities: vulkan.VkSurfaceCapabilitiesKHR,
    formats: []vulkan.VkSurfaceFormatKHR,
    presentModes: []vulkan.VkPresentModeKHR,

    fn tryInit(allocator: Allocator, device: vulkan.VkPhysicalDevice, surface: vulkan.VkSurfaceKHR) !@This() {
        var capabilities = vulkan.VkSurfaceCapabilitiesKHR{};
        if (vulkan.VK_SUCCESS != vulkan.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &capabilities)) return error.VulkanError;

        var formatCount: u32 = 0;
        if (vulkan.VK_SUCCESS != vulkan.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, null)) return error.VulkanError;
        const formats = try allocator.alloc(vulkan.VkSurfaceFormatKHR, formatCount);
        if (vulkan.VK_SUCCESS != vulkan.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, formats.ptr)) return error.VulkanError;

        var presentModeCount: u32 = 0;
        if (vulkan.VK_SUCCESS != vulkan.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &presentModeCount, null)) return error.VulkanError;
        const presentModes = try allocator.alloc(vulkan.VkPresentModeKHR, presentModeCount);
        if (vulkan.VK_SUCCESS != vulkan.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &presentModeCount, presentModes.ptr)) return error.VulkanError;

        return @This(){
            .allocator = allocator,
            .capabilities = capabilities,
            .formats = formats,
            .presentModes = presentModes,
        };
    }

    fn deinit(self: @This()) void {
        self.allocator.free(self.formats);
        self.allocator.free(self.presentModes);
    }
};

fn createSwapChain(
    allocator: Allocator,
    device: vulkan.VkDevice,
    physicalDevice: vulkan.VkPhysicalDevice,
    surface: vulkan.VkSurfaceKHR,
    width: i32,
    height: i32,
) !struct { vulkan.VkSwapchainKHR, vulkan.VkSurfaceFormatKHR, vulkan.VkExtent2D } {
    const swapChainSupport = try SwapChainSupportDetails.tryInit(
        allocator,
        physicalDevice,
        surface,
    ); // todo
    defer swapChainSupport.deinit();
    const surfaceFormat = chooseSwapSurfaceFormat(swapChainSupport.formats);
    const presentMode = chooseSwapPresentMode(swapChainSupport.presentModes);
    const extent = chooseSwapExtent(&swapChainSupport.capabilities, width, height);

    var imageCount = swapChainSupport.capabilities.minImageCount + 1;
    if (swapChainSupport.capabilities.maxImageCount > 0 and imageCount > swapChainSupport.capabilities.maxImageCount) {
        imageCount = swapChainSupport.capabilities.maxImageCount;
    }

    var createInfo = vulkan.VkSwapchainCreateInfoKHR{};
    createInfo.sType = vulkan.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    createInfo.surface = surface;

    createInfo.minImageCount = imageCount;
    createInfo.imageFormat = surfaceFormat.format;
    createInfo.imageColorSpace = surfaceFormat.colorSpace;
    createInfo.imageExtent = extent;
    createInfo.imageArrayLayers = 1;
    createInfo.imageUsage = vulkan.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

    const queueIndices = try findQueueFamilyIndice(physicalDevice, allocator, surface);
    const queueFamilyIndices = [_]u32{ queueIndices.graphics.?, queueIndices.present.? };

    if (queueIndices.graphics != queueIndices.present) {
        createInfo.imageSharingMode = vulkan.VK_SHARING_MODE_CONCURRENT;
        createInfo.queueFamilyIndexCount = 2;
        createInfo.pQueueFamilyIndices = &queueFamilyIndices;
    } else {
        createInfo.imageSharingMode = vulkan.VK_SHARING_MODE_EXCLUSIVE;
        createInfo.queueFamilyIndexCount = 0; // Optional
        createInfo.pQueueFamilyIndices = null; // Optional
    }

    createInfo.preTransform = swapChainSupport.capabilities.currentTransform;
    createInfo.compositeAlpha = vulkan.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;

    createInfo.presentMode = presentMode;
    createInfo.clipped = vulkan.VK_TRUE;

    createInfo.oldSwapchain = null;

    var swapChain: vulkan.VkSwapchainKHR = null;
    if (vulkan.VK_SUCCESS != vulkan.vkCreateSwapchainKHR(device, &createInfo, null, &swapChain)) {
        return error.FailedToCreateSwapChain;
    }

    return .{ swapChain, surfaceFormat, extent };
}

fn chooseSwapSurfaceFormat(availableFormats: []vulkan.VkSurfaceFormatKHR) vulkan.VkSurfaceFormatKHR {
    for (availableFormats) |format| {
        if (format.format == vulkan.VK_FORMAT_B8G8R8A8_SRGB and format.colorSpace == vulkan.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            return format;
        }
    }
    //todo
    return availableFormats[0];
}

fn chooseSwapPresentMode(availablePresentModes: []vulkan.VkPresentModeKHR) vulkan.VkPresentModeKHR {
    for (availablePresentModes) |m| {
        if (m == vulkan.VK_PRESENT_MODE_MAILBOX_KHR) {
            return m;
        }
    }
    return vulkan.VK_PRESENT_MODE_FIFO_KHR;
}

fn chooseSwapExtent(capabilities: *const vulkan.VkSurfaceCapabilitiesKHR, width: i32, height: i32) vulkan.VkExtent2D {
    // todo
    if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
        return capabilities.currentExtent;
    } else {
        return vulkan.VkExtent2D{
            .width = @intCast(width),
            .height = @intCast(height),
        };
    }
}

fn getImageList(allocator: Allocator, device: vulkan.VkDevice, swapChain: vulkan.VkSwapchainKHR) ![]vulkan.VkImage {
    var imageCount: u32 = 0;
    if (vulkan.VK_SUCCESS != vulkan.vkGetSwapchainImagesKHR(device, swapChain, &imageCount, null)) return error.VulkanFailed;
    const swapChainImages = try allocator.alloc(vulkan.VkImage, imageCount);
    if (vulkan.VK_SUCCESS != vulkan.vkGetSwapchainImagesKHR(device, swapChain, &imageCount, swapChainImages.ptr)) return error.VulkanFailed;
    return swapChainImages;
}

fn getImageViewList(allocator: Allocator, device: vulkan.VkDevice, images: []vulkan.VkImage, imageFormat: vulkan.VkSurfaceFormatKHR) ![]vulkan.VkImageView {
    var swapChainImageViews = try allocator.alloc(vulkan.VkImageView, images.len);
    for (0..images.len) |i| {
        var createInfo = vulkan.VkImageViewCreateInfo{};
        createInfo.sType = vulkan.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        createInfo.image = images[i];

        createInfo.viewType = vulkan.VK_IMAGE_VIEW_TYPE_2D;
        createInfo.format = imageFormat.format;
        createInfo.components.r = vulkan.VK_COMPONENT_SWIZZLE_IDENTITY;
        createInfo.components.g = vulkan.VK_COMPONENT_SWIZZLE_IDENTITY;

        createInfo.components.b = vulkan.VK_COMPONENT_SWIZZLE_IDENTITY;
        createInfo.components.a = vulkan.VK_COMPONENT_SWIZZLE_IDENTITY;

        createInfo.subresourceRange.aspectMask = vulkan.VK_IMAGE_ASPECT_COLOR_BIT;
        createInfo.subresourceRange.baseMipLevel = 0;
        createInfo.subresourceRange.levelCount = 1;
        createInfo.subresourceRange.baseArrayLayer = 0;
        createInfo.subresourceRange.layerCount = 1;

        if (vulkan.VK_SUCCESS != vulkan.vkCreateImageView(device, &createInfo, null, &swapChainImageViews[i])) return error.VulkanError;
    }

    return swapChainImageViews;
}

fn createGraphicPipeline(allocator: Allocator, device: vulkan.VkDevice, swapChainExtent: vulkan.VkExtent2D, renderPass: vulkan.VkRenderPass) !struct { vulkan.VkPipelineLayout, vulkan.VkPipeline } {
    const vertShaderCode = @embedFile("shaders/vertex.spv");
    const fragShaderCode = @embedFile("shaders/fragment.spv");

    const vertexModule = try createShaderModule(allocator, device, vertShaderCode);
    defer vulkan.vkDestroyShaderModule(device, vertexModule, null);
    const fragModule = try createShaderModule(allocator, device, fragShaderCode);
    defer vulkan.vkDestroyShaderModule(device, fragModule, null);

    var vertShaderStageInfo = vulkan.VkPipelineShaderStageCreateInfo{};
    vertShaderStageInfo.sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    vertShaderStageInfo.stage = vulkan.VK_SHADER_STAGE_VERTEX_BIT;
    vertShaderStageInfo.module = vertexModule;
    vertShaderStageInfo.pName = "main";

    var fragShaderStageInfo = vulkan.VkPipelineShaderStageCreateInfo{};
    fragShaderStageInfo.sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    fragShaderStageInfo.stage = vulkan.VK_SHADER_STAGE_FRAGMENT_BIT;
    fragShaderStageInfo.module = fragModule;
    fragShaderStageInfo.pName = "main";

    const shaderStages = [_]vulkan.VkPipelineShaderStageCreateInfo{ vertShaderStageInfo, fragShaderStageInfo };

    const dynamicStates = [_]c_uint{
        vulkan.VK_DYNAMIC_STATE_VIEWPORT,
        vulkan.VK_DYNAMIC_STATE_SCISSOR,
    };

    var dynamicState = vulkan.VkPipelineDynamicStateCreateInfo{};
    dynamicState.sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
    dynamicState.dynamicStateCount = dynamicStates.len;
    dynamicState.pDynamicStates = &dynamicStates;

    const bindingDescription = Vertex.getBindingDescription();
    const attributeDescriptions = Vertex.getAttributeDescriptions();

    var vertexInputInfo = vulkan.VkPipelineVertexInputStateCreateInfo{};
    vertexInputInfo.sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
    vertexInputInfo.vertexBindingDescriptionCount = 1;
    vertexInputInfo.pVertexBindingDescriptions = &bindingDescription;
    vertexInputInfo.vertexAttributeDescriptionCount = attributeDescriptions.len;
    vertexInputInfo.pVertexAttributeDescriptions = &attributeDescriptions;

    var inputAssembly = vulkan.VkPipelineInputAssemblyStateCreateInfo{};
    inputAssembly.sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
    inputAssembly.topology = vulkan.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    inputAssembly.primitiveRestartEnable = vulkan.VK_FALSE;

    var viewport = vulkan.VkViewport{};
    viewport.x = 0.0;
    viewport.y = 0.0;
    viewport.width = @floatFromInt(swapChainExtent.width);
    viewport.height = @floatFromInt(swapChainExtent.height);
    viewport.minDepth = 0.0;
    viewport.maxDepth = 1.0;

    var scissor = vulkan.VkRect2D{};
    scissor.offset = vulkan.VkOffset2D{ .x = 0, .y = 0 };
    scissor.extent = swapChainExtent;

    var viewportState = vulkan.VkPipelineViewportStateCreateInfo{};
    viewportState.sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
    viewportState.viewportCount = 1;
    viewportState.pViewports = &viewport;
    viewportState.scissorCount = 1;
    viewportState.pScissors = &scissor;

    var rasterizer = vulkan.VkPipelineRasterizationStateCreateInfo{};
    rasterizer.sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
    rasterizer.depthClampEnable = vulkan.VK_FALSE;
    rasterizer.polygonMode = vulkan.VK_POLYGON_MODE_FILL;
    rasterizer.lineWidth = 1.0;
    rasterizer.cullMode = vulkan.VK_CULL_MODE_BACK_BIT;
    rasterizer.frontFace = vulkan.VK_FRONT_FACE_CLOCKWISE;
    rasterizer.depthBiasEnable = vulkan.VK_FALSE;
    rasterizer.depthBiasConstantFactor = 0.0; // Optional
    rasterizer.depthBiasClamp = 0.0; // Optional
    rasterizer.depthBiasSlopeFactor = 0.0; // Optional

    var multisampling = vulkan.VkPipelineMultisampleStateCreateInfo{};
    multisampling.sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
    multisampling.sampleShadingEnable = vulkan.VK_FALSE;
    multisampling.rasterizationSamples = vulkan.VK_SAMPLE_COUNT_1_BIT;
    multisampling.minSampleShading = 1.0; // Optional
    multisampling.pSampleMask = null; // Optional
    multisampling.alphaToCoverageEnable = vulkan.VK_FALSE; // Optional
    multisampling.alphaToOneEnable = vulkan.VK_FALSE; // Optional

    var colorBlendAttachment = vulkan.VkPipelineColorBlendAttachmentState{};
    colorBlendAttachment.colorWriteMask = vulkan.VK_COLOR_COMPONENT_R_BIT | vulkan.VK_COLOR_COMPONENT_G_BIT | vulkan.VK_COLOR_COMPONENT_B_BIT | vulkan.VK_COLOR_COMPONENT_A_BIT;
    colorBlendAttachment.blendEnable = vulkan.VK_FALSE;
    colorBlendAttachment.srcColorBlendFactor = vulkan.VK_BLEND_FACTOR_ONE; // Optional
    colorBlendAttachment.dstColorBlendFactor = vulkan.VK_BLEND_FACTOR_ZERO; // Optional
    colorBlendAttachment.colorBlendOp = vulkan.VK_BLEND_OP_ADD; // Optional
    colorBlendAttachment.srcAlphaBlendFactor = vulkan.VK_BLEND_FACTOR_ONE; // Optional
    colorBlendAttachment.dstAlphaBlendFactor = vulkan.VK_BLEND_FACTOR_ZERO; // Optional
    colorBlendAttachment.alphaBlendOp = vulkan.VK_BLEND_OP_ADD; // Optional

    var colorBlending = vulkan.VkPipelineColorBlendStateCreateInfo{};
    colorBlending.sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    colorBlending.logicOpEnable = vulkan.VK_FALSE;
    colorBlending.logicOp = vulkan.VK_LOGIC_OP_COPY; // Optional
    colorBlending.attachmentCount = 1;
    colorBlending.pAttachments = &colorBlendAttachment;
    colorBlending.blendConstants[0] = 0.0; // Optional
    colorBlending.blendConstants[1] = 0.0; // Optional
    colorBlending.blendConstants[2] = 0.0; // Optional
    colorBlending.blendConstants[3] = 0.0; // Optional

    var pipelineLayoutInfo = vulkan.VkPipelineLayoutCreateInfo{};
    pipelineLayoutInfo.sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    pipelineLayoutInfo.setLayoutCount = 0; // Optional
    pipelineLayoutInfo.pSetLayouts = null; // Optional
    pipelineLayoutInfo.pushConstantRangeCount = 0; // Optional
    pipelineLayoutInfo.pPushConstantRanges = null; // Optional

    var pipelineLayout: vulkan.VkPipelineLayout = null;
    if (vulkan.VK_SUCCESS != vulkan.vkCreatePipelineLayout(device, &pipelineLayoutInfo, null, &pipelineLayout)) {
        return error.VulkanError;
    }

    var pipelineInfo = vulkan.VkGraphicsPipelineCreateInfo{};
    pipelineInfo.sType = vulkan.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
    pipelineInfo.stageCount = shaderStages.len;
    pipelineInfo.pStages = &shaderStages;
    pipelineInfo.pVertexInputState = &vertexInputInfo;
    pipelineInfo.pInputAssemblyState = &inputAssembly;
    pipelineInfo.pViewportState = &viewportState;
    pipelineInfo.pRasterizationState = &rasterizer;
    pipelineInfo.pMultisampleState = &multisampling;
    pipelineInfo.pDepthStencilState = null; // Optional
    pipelineInfo.pColorBlendState = &colorBlending;
    pipelineInfo.pDynamicState = &dynamicState;
    pipelineInfo.layout = pipelineLayout;
    pipelineInfo.renderPass = renderPass;
    pipelineInfo.subpass = 0;
    pipelineInfo.basePipelineHandle = null; // Optional
    pipelineInfo.basePipelineIndex = -1; // Optional

    var graphicsPipeline: vulkan.VkPipeline = null;
    if (vulkan.VK_SUCCESS != vulkan.vkCreateGraphicsPipelines(device, null, 1, &pipelineInfo, null, &graphicsPipeline)) {
        return error.VulkanError;
    }

    return .{ pipelineLayout, graphicsPipeline };
}

fn createShaderModule(allocator: Allocator, device: vulkan.VkDevice, code: [:0]const u8) !vulkan.VkShaderModule {
    // todo better way
    const alignedCode = try allocator.alignedAlloc(u8, 32, code.len);
    defer allocator.free(alignedCode);
    @memcpy(alignedCode, code);

    var createInfo = vulkan.VkShaderModuleCreateInfo{};
    createInfo.sType = vulkan.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    createInfo.codeSize = code.len;
    createInfo.pCode = @ptrCast(alignedCode.ptr);

    var module: vulkan.VkShaderModule = null;
    if (vulkan.VK_SUCCESS != vulkan.vkCreateShaderModule(device, &createInfo, null, &module)) return error.VulkanError;

    return module;
}

fn createRenderPass(device: vulkan.VkDevice, swapChainImageFormat: vulkan.VkFormat) !vulkan.VkRenderPass {
    var colorAttachment = vulkan.VkAttachmentDescription{};
    colorAttachment.format = swapChainImageFormat;
    colorAttachment.samples = vulkan.VK_SAMPLE_COUNT_1_BIT;
    colorAttachment.loadOp = vulkan.VK_ATTACHMENT_LOAD_OP_CLEAR;
    colorAttachment.storeOp = vulkan.VK_ATTACHMENT_STORE_OP_STORE;
    colorAttachment.stencilLoadOp = vulkan.VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    colorAttachment.stencilStoreOp = vulkan.VK_ATTACHMENT_STORE_OP_DONT_CARE;
    colorAttachment.initialLayout = vulkan.VK_IMAGE_LAYOUT_UNDEFINED;
    colorAttachment.finalLayout = vulkan.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;

    var colorAttachmentRef = vulkan.VkAttachmentReference{};
    colorAttachmentRef.attachment = 0;
    colorAttachmentRef.layout = vulkan.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

    var subpass = vulkan.VkSubpassDescription{};
    subpass.pipelineBindPoint = vulkan.VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpass.colorAttachmentCount = 1;
    subpass.pColorAttachments = &colorAttachmentRef;

    var dependency = vulkan.VkSubpassDependency{};
    dependency.srcSubpass = vulkan.VK_SUBPASS_EXTERNAL;
    dependency.dstSubpass = 0;
    dependency.srcStageMask = vulkan.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dependency.srcAccessMask = 0;
    dependency.dstStageMask = vulkan.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dependency.dstAccessMask = vulkan.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;

    var renderPassInfo = vulkan.VkRenderPassCreateInfo{};
    renderPassInfo.sType = vulkan.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    renderPassInfo.attachmentCount = 1;
    renderPassInfo.pAttachments = &colorAttachment;
    renderPassInfo.subpassCount = 1;
    renderPassInfo.pSubpasses = &subpass;
    renderPassInfo.dependencyCount = 1;
    renderPassInfo.pDependencies = &dependency;

    var renderPass: vulkan.VkRenderPass = null;
    if (vulkan.VK_SUCCESS != vulkan.vkCreateRenderPass(device, &renderPassInfo, null, &renderPass)) return error.VulkanError;

    return renderPass;
}

fn createFramebuffers(
    allocator: Allocator,
    device: vulkan.VkDevice,
    swapChainImageViews: []vulkan.VkImageView,
    renderPass: vulkan.VkRenderPass,
    swapChainExtent: vulkan.VkExtent2D,
) ![]vulkan.VkFramebuffer {
    const swapChainFramebuffers = try allocator.alloc(vulkan.VkFramebuffer, swapChainImageViews.len);

    for (swapChainImageViews, 0..) |imageView, i| {
        var attachments = [_]vulkan.VkImageView{imageView};

        var framebufferInfo = vulkan.VkFramebufferCreateInfo{};
        framebufferInfo.sType = vulkan.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
        framebufferInfo.renderPass = renderPass;
        framebufferInfo.attachmentCount = attachments.len;
        framebufferInfo.pAttachments = &attachments;
        framebufferInfo.width = swapChainExtent.width;
        framebufferInfo.height = swapChainExtent.height;
        framebufferInfo.layers = 1;

        if (vulkan.VK_SUCCESS != vulkan.vkCreateFramebuffer(device, &framebufferInfo, null, &swapChainFramebuffers[i])) {
            return error.VulkanError;
        }
    }
    return swapChainFramebuffers;
}

fn createCommandPool(allocator: Allocator, physicalDevice: vulkan.VkPhysicalDevice, device: vulkan.VkDevice, surface: vulkan.VkSurfaceKHR) !vulkan.VkCommandPool {
    const queueFamilyIndices = try findQueueFamilyIndice(physicalDevice, allocator, surface);

    var poolInfo = vulkan.VkCommandPoolCreateInfo{};
    poolInfo.sType = vulkan.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    poolInfo.flags = vulkan.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    poolInfo.queueFamilyIndex = queueFamilyIndices.graphics.?;

    var commandPool: vulkan.VkCommandPool = null;
    if (vulkan.VK_SUCCESS != vulkan.vkCreateCommandPool(device, &poolInfo, null, &commandPool)) {
        return error.VulkanError;
    }
    return commandPool;
}

fn createCommandBuffers(allocator: Allocator, device: vulkan.VkDevice, commandPool: vulkan.VkCommandPool) ![]vulkan.VkCommandBuffer {
    const commandBuffers: []vulkan.VkCommandBuffer = try allocator.alloc(vulkan.VkCommandBuffer, MAX_FRAMES_IN_FLIGHT);

    var allocInfo = vulkan.VkCommandBufferAllocateInfo{};
    allocInfo.sType = vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    allocInfo.commandPool = commandPool;
    allocInfo.level = vulkan.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    allocInfo.commandBufferCount = @intCast(commandBuffers.len);

    if (vulkan.VK_SUCCESS != vulkan.vkAllocateCommandBuffers(device, &allocInfo, commandBuffers.ptr)) {
        return error.VulkanError;
    }

    return commandBuffers;
}

fn recordCommandBuffer(
    commandBuffer: vulkan.VkCommandBuffer,
    renderPass: vulkan.VkRenderPass,
    swapChainExtent: vulkan.VkExtent2D,
    swapChainFramebuffer: vulkan.VkFramebuffer,
    graphicsPipeline: vulkan.VkPipeline,
    vertexBuffer: vulkan.VkBuffer,
    indexBuffer: vulkan.VkBuffer,
) !void {
    var beginInfo = vulkan.VkCommandBufferBeginInfo{};
    beginInfo.sType = vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    beginInfo.flags = 0; // Optional
    beginInfo.pInheritanceInfo = null; // Optional

    if (vulkan.VK_SUCCESS != vulkan.vkBeginCommandBuffer(commandBuffer, &beginInfo)) {
        return error.VulkanError;
    }

    var renderPassInfo = vulkan.VkRenderPassBeginInfo{};
    renderPassInfo.sType = vulkan.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    renderPassInfo.renderPass = renderPass;
    renderPassInfo.framebuffer = swapChainFramebuffer;
    renderPassInfo.renderArea.offset = .{ .x = 0, .y = 0 };
    renderPassInfo.renderArea.extent = swapChainExtent;

    const clearColor: vulkan.VkClearValue = .{ .color = .{ .float32 = .{ 0.0, 0.0, 0.0, 1.0 } } };
    renderPassInfo.clearValueCount = 1;
    renderPassInfo.pClearValues = &clearColor;

    vulkan.vkCmdBeginRenderPass(commandBuffer, &renderPassInfo, vulkan.VK_SUBPASS_CONTENTS_INLINE);

    {
        vulkan.vkCmdBindPipeline(commandBuffer, vulkan.VK_PIPELINE_BIND_POINT_GRAPHICS, graphicsPipeline);
        var viewport = vulkan.VkViewport{};
        viewport.x = 0.0;
        viewport.y = 0.0;
        viewport.width = @floatFromInt(swapChainExtent.width);
        viewport.height = @floatFromInt(swapChainExtent.height);
        viewport.minDepth = 0.0;
        viewport.maxDepth = 1.0;
        vulkan.vkCmdSetViewport(commandBuffer, 0, 1, &viewport);

        var scissor = vulkan.VkRect2D{};
        scissor.offset = .{ .x = 0, .y = 0 };
        scissor.extent = swapChainExtent;
        vulkan.vkCmdSetScissor(commandBuffer, 0, 1, &scissor);

        const vertexBuffers = [_]vulkan.VkBuffer{vertexBuffer};
        const offsets = [_]vulkan.VkDeviceSize{0};
        vulkan.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers, &offsets);
        vulkan.vkCmdBindIndexBuffer(commandBuffer, indexBuffer, 0, vulkan.VK_INDEX_TYPE_UINT16);

        vulkan.vkCmdDrawIndexed(commandBuffer, indices.len, 1, 0, 0, 0);
    }
    vulkan.vkCmdEndRenderPass(commandBuffer);

    if (vulkan.VK_SUCCESS != vulkan.vkEndCommandBuffer(commandBuffer)) {
        return error.VulkanError;
    }
}

fn createSyncObjects(allocator: Allocator, device: vulkan.VkDevice) !struct { []vulkan.VkSemaphore, []vulkan.VkSemaphore, []vulkan.VkFence } {
    var semaphoreInfo = vulkan.VkSemaphoreCreateInfo{};
    semaphoreInfo.sType = vulkan.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
    var fenceInfo = vulkan.VkFenceCreateInfo{};
    fenceInfo.sType = vulkan.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    fenceInfo.flags = vulkan.VK_FENCE_CREATE_SIGNALED_BIT;

    var imageAvailableSemaphores: []vulkan.VkSemaphore = try allocator.alloc(vulkan.VkSemaphore, MAX_FRAMES_IN_FLIGHT);
    var renderFinishedSemaphores: []vulkan.VkSemaphore = try allocator.alloc(vulkan.VkSemaphore, MAX_FRAMES_IN_FLIGHT);
    var inFlightFences: []vulkan.VkFence = try allocator.alloc(vulkan.VkFence, MAX_FRAMES_IN_FLIGHT);

    for (0..MAX_FRAMES_IN_FLIGHT) |i| {
        if (vulkan.vkCreateSemaphore(device, &semaphoreInfo, null, &imageAvailableSemaphores[i]) != vulkan.VK_SUCCESS or
            vulkan.vkCreateSemaphore(device, &semaphoreInfo, null, &renderFinishedSemaphores[i]) != vulkan.VK_SUCCESS or
            vulkan.vkCreateFence(device, &fenceInfo, null, &inFlightFences[i]) != vulkan.VK_SUCCESS)
        {
            return error.VulkanError;
        }
    }

    return .{ imageAvailableSemaphores, renderFinishedSemaphores, inFlightFences };
}

pub fn createVertexBuffer(
    device: vulkan.VkDevice,
    physicalDevice: vulkan.VkPhysicalDevice,
    commandPool: vulkan.VkCommandPool,
    graphicQueue: vulkan.VkQueue,
) !struct { vulkan.VkBuffer, vulkan.VkDeviceMemory } {
    const bufferSize = @sizeOf(Vertex) * vertices.len;
    const stagingBuffer, const stagingBufferMemory = try createBuffer(
        device,
        physicalDevice,
        bufferSize,
        vulkan.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        vulkan.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vulkan.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
    );
    defer {
        vulkan.vkDestroyBuffer(device, stagingBuffer, null);
        vulkan.vkFreeMemory(device, stagingBufferMemory, null);
    }

    var data: [*c]u8 = undefined;
    if (vulkan.VK_SUCCESS != vulkan.vkMapMemory(device, stagingBufferMemory, 0, bufferSize, 0, @ptrCast(&data))) {
        return error.MapMemoryFailed;
    }
    @memcpy(data[0..bufferSize], std.mem.asBytes(&vertices));
    vulkan.vkUnmapMemory(device, stagingBufferMemory);

    const vertexBuffer, const vertexBufferMemory = try createBuffer(
        device,
        physicalDevice,
        bufferSize,
        vulkan.VK_BUFFER_USAGE_TRANSFER_DST_BIT | vulkan.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        vulkan.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    );

    try copyBuffer(
        device,
        graphicQueue,
        commandPool,
        stagingBuffer,
        vertexBuffer,
        bufferSize,
    );

    return .{ vertexBuffer, vertexBufferMemory };
}

fn findMemoryType(physicalDevice: vulkan.VkPhysicalDevice, typeFilter: u32, properties: vulkan.VkMemoryPropertyFlags) !u32 {
    var memProperties = vulkan.VkPhysicalDeviceMemoryProperties{};
    vulkan.vkGetPhysicalDeviceMemoryProperties(physicalDevice, &memProperties);

    for (0..memProperties.memoryTypeCount) |i| {
        if ((typeFilter & @shlExact(i, 2) != 0) and ((memProperties.memoryTypes[i].propertyFlags & properties) == properties)) {
            return @intCast(i);
        }
    }

    return error.FailedToFindMemoryType;
}

fn createBuffer(
    device: vulkan.VkDevice,
    physicalDevice: vulkan.VkPhysicalDevice,
    size: usize,
    usage: vulkan.VkBufferUsageFlags,
    properties: vulkan.VkMemoryPropertyFlags,
) !struct { vulkan.VkBuffer, vulkan.VkDeviceMemory } {
    var bufferInfo = vulkan.VkBufferCreateInfo{};
    bufferInfo.sType = vulkan.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bufferInfo.size = size;
    bufferInfo.usage = usage;
    bufferInfo.sharingMode = vulkan.VK_SHARING_MODE_EXCLUSIVE;

    var vertexBuffer: vulkan.VkBuffer = null;
    if (vulkan.VK_SUCCESS != vulkan.vkCreateBuffer(device, &bufferInfo, null, &vertexBuffer)) {
        return error.FailedToCreateBuffer;
    }

    var memRequirements = vulkan.VkMemoryRequirements{};
    vulkan.vkGetBufferMemoryRequirements(device, vertexBuffer, &memRequirements);

    var allocInfo = vulkan.VkMemoryAllocateInfo{};
    allocInfo.sType = vulkan.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocInfo.allocationSize = memRequirements.size;
    allocInfo.memoryTypeIndex = try findMemoryType(physicalDevice, memRequirements.memoryTypeBits, properties);

    var vertexBufferMemory: vulkan.VkDeviceMemory = null;
    if (vulkan.VK_SUCCESS != vulkan.vkAllocateMemory(device, &allocInfo, null, &vertexBufferMemory)) {
        return error.VulkanAllocMemoryFailed;
    }

    if (vulkan.VK_SUCCESS != vulkan.vkBindBufferMemory(device, vertexBuffer, vertexBufferMemory, 0)) {
        return error.BindBufferFailed;
    }

    return .{ vertexBuffer, vertexBufferMemory };
}

fn copyBuffer(
    device: vulkan.VkDevice,
    graphicQueue: vulkan.VkQueue,
    commandPool: vulkan.VkCommandPool,
    srcBuffer: vulkan.VkBuffer,
    dstBuffer: vulkan.VkBuffer,
    size: u32,
) !void {
    var allocInfo = vulkan.VkCommandBufferAllocateInfo{};
    allocInfo.sType = vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    allocInfo.level = vulkan.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    allocInfo.commandPool = commandPool;
    allocInfo.commandBufferCount = 1;

    var commandBuffer: vulkan.VkCommandBuffer = null;
    if (vulkan.VK_SUCCESS != vulkan.vkAllocateCommandBuffers(device, &allocInfo, &commandBuffer)) {
        return error.FailedToAllocateCommandBuffer;
    }

    var beginInfo = vulkan.VkCommandBufferBeginInfo{};
    beginInfo.sType = vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    beginInfo.flags = vulkan.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;

    if (vulkan.VK_SUCCESS != vulkan.vkBeginCommandBuffer(commandBuffer, &beginInfo)) {
        return error.FailedToBeginCommandBuffer;
    }

    var copyRegion = vulkan.VkBufferCopy{};
    copyRegion.srcOffset = 0; // Optional
    copyRegion.dstOffset = 0; // Optional
    copyRegion.size = size;
    vulkan.vkCmdCopyBuffer(commandBuffer, srcBuffer, dstBuffer, 1, &copyRegion);

    if (vulkan.VK_SUCCESS != vulkan.vkEndCommandBuffer(commandBuffer)) {
        return error.FailedToEndCommandBuffer;
    }

    var submitInfo = vulkan.VkSubmitInfo{};
    submitInfo.sType = vulkan.VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &commandBuffer;

    if (vulkan.VK_SUCCESS != vulkan.vkQueueSubmit(graphicQueue, 1, &submitInfo, null)) {
        return error.FailedQueueSubmit;
    }

    if (vulkan.VK_SUCCESS != vulkan.vkQueueWaitIdle(graphicQueue)) {
        return error.FailedToWaitQueue;
    }

    vulkan.vkFreeCommandBuffers(device, commandPool, 1, &commandBuffer);
}

fn createIndexBuffer(
    device: vulkan.VkDevice,
    physicalDevice: vulkan.VkPhysicalDevice,
    commandPool: vulkan.VkCommandPool,
    graphicQueue: vulkan.VkQueue,
) !struct { vulkan.VkBuffer, vulkan.VkDeviceMemory } {
    const bufferSize = @sizeOf(u16) * indices.len;
    const stagingBuffer, const stagingBufferMemory = try createBuffer(
        device,
        physicalDevice,
        bufferSize,
        vulkan.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        vulkan.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vulkan.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
    );
    defer {
        vulkan.vkDestroyBuffer(device, stagingBuffer, null);
        vulkan.vkFreeMemory(device, stagingBufferMemory, null);
    }

    var data: [*c]u8 = undefined;
    if (vulkan.VK_SUCCESS != vulkan.vkMapMemory(device, stagingBufferMemory, 0, bufferSize, 0, @ptrCast(&data))) {
        return error.MapMemoryFailed;
    }
    @memcpy(data[0..bufferSize], std.mem.asBytes(&indices));
    vulkan.vkUnmapMemory(device, stagingBufferMemory);

    const indexBuffer, const indexBufferMemory = try createBuffer(
        device,
        physicalDevice,
        bufferSize,
        vulkan.VK_BUFFER_USAGE_TRANSFER_DST_BIT | vulkan.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
        vulkan.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    );

    try copyBuffer(
        device,
        graphicQueue,
        commandPool,
        stagingBuffer,
        indexBuffer,
        bufferSize,
    );

    return .{ indexBuffer, indexBufferMemory };
}
