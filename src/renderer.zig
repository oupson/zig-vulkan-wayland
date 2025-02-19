const std = @import("std");
const builtin = @import("builtin");

const zalgebra = @import("zalgebra");

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
    pos: @Vector(3, f32),
    color: @Vector(3, f32),
    texCoord: @Vector(2, f32),

    fn getBindingDescription() vulkan.VkVertexInputBindingDescription {
        var bindingDescription = vulkan.VkVertexInputBindingDescription{};
        bindingDescription.binding = 0;
        bindingDescription.stride = @sizeOf(@This());
        bindingDescription.inputRate = vulkan.VK_VERTEX_INPUT_RATE_VERTEX;

        return bindingDescription;
    }

    fn getAttributeDescriptions() [3]vulkan.VkVertexInputAttributeDescription {
        var attributeDescriptions: [3]vulkan.VkVertexInputAttributeDescription = .{ .{}, .{}, .{} };
        attributeDescriptions[0].binding = 0;
        attributeDescriptions[0].location = 0;
        attributeDescriptions[0].format = vulkan.VK_FORMAT_R32G32B32_SFLOAT;
        attributeDescriptions[0].offset = @offsetOf(Vertex, "pos");

        attributeDescriptions[1].binding = 0;
        attributeDescriptions[1].location = 1;
        attributeDescriptions[1].format = vulkan.VK_FORMAT_R32G32B32_SFLOAT;
        attributeDescriptions[1].offset = @offsetOf(Vertex, "color");

        attributeDescriptions[2].binding = 0;
        attributeDescriptions[2].location = 2;
        attributeDescriptions[2].format = vulkan.VK_FORMAT_R32G32_SFLOAT;
        attributeDescriptions[2].offset = @offsetOf(Vertex, "texCoord");

        return attributeDescriptions;
    }
};

const UniformBufferObject = extern struct {
    model: zalgebra.Mat4 align(16),
    view: zalgebra.Mat4 align(16),
    proj: zalgebra.Mat4 align(16),
};

const vertices = [_]Vertex{
    .{
        .pos = .{ -0.5, -0.5, 0.0 },
        .color = .{ 1.0, 0.0, 0.0 },
        .texCoord = .{ 1.0, 0.0 },
    },
    .{
        .pos = .{ 0.5, -0.5, 0.0 },
        .color = .{ 0.0, 1.0, 0.0 },
        .texCoord = .{ 0.0, 0.0 },
    },
    .{
        .pos = .{ 0.5, 0.5, 0.0 },
        .color = .{ 0.0, 0.0, 1.0 },
        .texCoord = .{ 0.0, 1.0 },
    },
    .{
        .pos = .{ -0.5, 0.5, 0.0 },
        .color = .{ 1.0, 1.0, 1.0 },
        .texCoord = .{ 1.0, 1.0 },
    },

    .{
        .pos = .{ -0.5, -0.5, -0.5 },
        .color = .{ 1.0, 0.0, 0.0 },
        .texCoord = .{ 1.0, 0.0 },
    },
    .{
        .pos = .{ 0.5, -0.5, -0.5 },
        .color = .{ 0.0, 1.0, 0.0 },
        .texCoord = .{ 0.0, 0.0 },
    },
    .{
        .pos = .{ 0.5, 0.5, -0.5 },
        .color = .{ 0.0, 0.0, 1.0 },
        .texCoord = .{ 0.0, 1.0 },
    },
    .{
        .pos = .{ -0.5, 0.5, -0.5 },
        .color = .{ 1.0, 1.0, 1.0 },
        .texCoord = .{ 1.0, 1.0 },
    },
};

const indices = [_]u16{ 0, 1, 2, 2, 3, 0, 4, 5, 6, 6, 7, 4 };

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
descriptorSetLayout: vulkan.VkDescriptorSetLayout,
uniformBuffers: []vulkan.VkBuffer,
uniformBuffersMemory: []vulkan.VkDeviceMemory,
uniformBuffersMapped: [][]u8,
startTime: std.time.Instant,
descriptorPool: vulkan.VkDescriptorPool,
descriptorSets: []vulkan.VkDescriptorSet,
textureImage: vulkan.VkImage,
textureImageMemory: vulkan.VkDeviceMemory,
textureImageView: vulkan.VkImageView,
textureSampler: vulkan.VkSampler,
depthImage: vulkan.VkImage,
depthImageMemory: vulkan.VkDeviceMemory,
depthImageView: vulkan.VkImageView,

pub fn new(
    vulkanInstance: Instance,
    allocator: Allocator,
    display: *wl.Display,
    surface: *wl.Surface,
    width: i32,
    height: i32,
) !Self {
    std.log.info("create", .{});
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

    const descriptorSetLayout = try createDescriptorSetLayout(device);

    const renderPass = try createRenderPass(device, physicalDevice, format.format);
    const pipelineLayout, const pipeline = try createGraphicPipeline(allocator, device, extent, renderPass, descriptorSetLayout);

    const commandPool = try createCommandPool(allocator, physicalDevice, device, vulkanSurface);

    const depthImage, const depthImageMemory, const depthImageView = try createDepthResources(
        device,
        physicalDevice,
        commandPool,
        graphicQueue,
        extent,
    );

    const swapChainFramebuffers = try createFramebuffers(
        allocator,
        device,
        imageViewList,
        renderPass,
        extent,
        depthImageView,
    );

    const textureImage, const textureImageMemory = try createTextureImage(device, physicalDevice, commandPool, graphicQueue);
    const textureImageView = try createTextureImageView(device, textureImage);
    const textureSampler = try createTextureSampler(device, physicalDevice);

    const vertexBuffer, const vertexBufferMemory = try createVertexBuffer(device, physicalDevice, commandPool, graphicQueue);
    const indexBuffer, const indexBufferMemory = try createIndexBuffer(device, physicalDevice, commandPool, graphicQueue);
    const uniformBuffers, const uniformBuffersMemory, const uniformBuffersMapped = try createUniformBuffers(allocator, device, physicalDevice);

    const descriptorPool = try createDescriptorPool(device);
    const descriptorSets = try createDescriptorSet(allocator, device, descriptorPool, uniformBuffers, descriptorSetLayout, textureImageView, textureSampler);

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
        .uniformBuffers = uniformBuffers,
        .uniformBuffersMemory = uniformBuffersMemory,
        .uniformBuffersMapped = uniformBuffersMapped,
        .commandBuffers = commandBuffers,
        .imageAvailableSemaphores = imageAvailableSemaphores,
        .renderFinishedSemaphores = renderFinishedSemaphores,
        .inFlightFences = inFlightFences,
        .descriptorSetLayout = descriptorSetLayout,
        .startTime = try std.time.Instant.now(),
        .descriptorPool = descriptorPool,
        .descriptorSets = descriptorSets,
        .textureImage = textureImage,
        .textureImageMemory = textureImageMemory,
        .textureImageView = textureImageView,
        .textureSampler = textureSampler,
        .depthImage = depthImage,
        .depthImageMemory = depthImageMemory,
        .depthImageView = depthImageView,
    };
}

// todo partial deinit
pub fn deinit(self: *const Self) !void {
    std.log.info("deinit", .{});
    if (vulkan.VK_SUCCESS != vulkan.vkDeviceWaitIdle(self.device)) return error.VulkanError;

    vulkan.vkDestroyImageView(self.device, self.depthImageView, null);
    vulkan.vkDestroyImage(self.device, self.depthImage, null);
    vulkan.vkFreeMemory(self.device, self.depthImageMemory, null);

    vulkan.vkDestroySampler(self.device, self.textureSampler, null);
    vulkan.vkDestroyImageView(self.device, self.textureImageView, null);

    vulkan.vkDestroyImage(self.device, self.textureImage, null);
    vulkan.vkFreeMemory(self.device, self.textureImageMemory, null);

    vulkan.vkDestroyBuffer(self.device, self.vertexBuffer, null);
    vulkan.vkFreeMemory(self.device, self.vertexBufferMemory, null);

    vulkan.vkDestroyBuffer(self.device, self.indexBuffer, null);
    vulkan.vkFreeMemory(self.device, self.indexBufferMemory, null);

    for (0..MAX_FRAMES_IN_FLIGHT) |i| {
        vulkan.vkDestroyBuffer(self.device, self.uniformBuffers[i], null);
        vulkan.vkFreeMemory(self.device, self.uniformBuffersMemory[i], null);
    }
    self.allocator.free(self.uniformBuffers);
    self.allocator.free(self.uniformBuffersMemory);
    self.allocator.free(self.uniformBuffersMapped);

    vulkan.vkDestroyDescriptorSetLayout(self.device, self.descriptorSetLayout, null);
    vulkan.vkDestroyDescriptorPool(self.device, self.descriptorPool, null);

    self.allocator.free(self.descriptorSets);

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

    try self.updateUniformBuffer();

    if (vulkan.VK_SUCCESS != vulkan.vkResetCommandBuffer(self.commandBuffers[self.currentFrame], 0)) return error.VulkanError;
    try recordCommandBuffer(
        self.commandBuffers[self.currentFrame],
        self.renderPass,
        self.extent,
        self.swapChainFramebuffers[imageIndex],
        self.pipeline,
        self.vertexBuffer,
        self.indexBuffer,
        self.pipelineLayout,
        &self.descriptorSets[self.currentFrame],
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

    var supportedFeatures = vulkan.VkPhysicalDeviceFeatures{};
    vulkan.vkGetPhysicalDeviceFeatures(device, &supportedFeatures);
    if (supportedFeatures.samplerAnisotropy != vulkan.VK_TRUE) {
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

    var deviceFeatures = vulkan.VkPhysicalDeviceFeatures{};
    deviceFeatures.samplerAnisotropy = vulkan.VK_TRUE;

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
        swapChainImageViews[i] = try createImageView(device, images[i], imageFormat.format, vulkan.VK_IMAGE_ASPECT_COLOR_BIT);
    }

    return swapChainImageViews;
}

fn createGraphicPipeline(allocator: Allocator, device: vulkan.VkDevice, swapChainExtent: vulkan.VkExtent2D, renderPass: vulkan.VkRenderPass, descriptorSetLayout: vulkan.VkDescriptorSetLayout) !struct { vulkan.VkPipelineLayout, vulkan.VkPipeline } {
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
    rasterizer.frontFace = vulkan.VK_FRONT_FACE_COUNTER_CLOCKWISE;
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
    pipelineLayoutInfo.setLayoutCount = 1;
    pipelineLayoutInfo.pSetLayouts = &descriptorSetLayout;
    pipelineLayoutInfo.pushConstantRangeCount = 0; // Optional
    pipelineLayoutInfo.pPushConstantRanges = null; // Optional

    var pipelineLayout: vulkan.VkPipelineLayout = null;
    if (vulkan.VK_SUCCESS != vulkan.vkCreatePipelineLayout(device, &pipelineLayoutInfo, null, &pipelineLayout)) {
        return error.VulkanError;
    }

    var depthStencil = vulkan.VkPipelineDepthStencilStateCreateInfo{};
    depthStencil.sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
    depthStencil.depthTestEnable = vulkan.VK_TRUE;
    depthStencil.depthWriteEnable = vulkan.VK_TRUE;
    depthStencil.depthCompareOp = vulkan.VK_COMPARE_OP_LESS;
    depthStencil.depthBoundsTestEnable = vulkan.VK_FALSE;
    depthStencil.minDepthBounds = 0.0; // Optional
    depthStencil.maxDepthBounds = 1.0; // Optional
    depthStencil.stencilTestEnable = vulkan.VK_FALSE;
    depthStencil.front = .{}; // Optional
    depthStencil.back = .{}; // Optional

    var pipelineInfo = vulkan.VkGraphicsPipelineCreateInfo{};
    pipelineInfo.sType = vulkan.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
    pipelineInfo.stageCount = shaderStages.len;
    pipelineInfo.pStages = &shaderStages;
    pipelineInfo.pVertexInputState = &vertexInputInfo;
    pipelineInfo.pInputAssemblyState = &inputAssembly;
    pipelineInfo.pViewportState = &viewportState;
    pipelineInfo.pRasterizationState = &rasterizer;
    pipelineInfo.pMultisampleState = &multisampling;
    pipelineInfo.pDepthStencilState = &depthStencil;
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

fn createRenderPass(device: vulkan.VkDevice, physicalDevice: vulkan.VkPhysicalDevice, swapChainImageFormat: vulkan.VkFormat) !vulkan.VkRenderPass {
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

    var depthAttachment = vulkan.VkAttachmentDescription{};
    depthAttachment.format = try findDepthFormat(physicalDevice);
    depthAttachment.samples = vulkan.VK_SAMPLE_COUNT_1_BIT;
    depthAttachment.loadOp = vulkan.VK_ATTACHMENT_LOAD_OP_CLEAR;
    depthAttachment.storeOp = vulkan.VK_ATTACHMENT_STORE_OP_DONT_CARE;
    depthAttachment.stencilLoadOp = vulkan.VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    depthAttachment.stencilStoreOp = vulkan.VK_ATTACHMENT_STORE_OP_DONT_CARE;
    depthAttachment.initialLayout = vulkan.VK_IMAGE_LAYOUT_UNDEFINED;
    depthAttachment.finalLayout = vulkan.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

    var depthAttachmentRef = vulkan.VkAttachmentReference{};
    depthAttachmentRef.attachment = 1;
    depthAttachmentRef.layout = vulkan.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

    var subpass = vulkan.VkSubpassDescription{};
    subpass.pipelineBindPoint = vulkan.VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpass.colorAttachmentCount = 1;
    subpass.pColorAttachments = &colorAttachmentRef;
    subpass.pDepthStencilAttachment = &depthAttachmentRef;

    var dependency = vulkan.VkSubpassDependency{};
    dependency.srcSubpass = vulkan.VK_SUBPASS_EXTERNAL;
    dependency.dstSubpass = 0;
    dependency.srcStageMask = vulkan.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | vulkan.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
    dependency.srcAccessMask = 0;
    dependency.dstStageMask = vulkan.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | vulkan.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
    dependency.dstAccessMask = vulkan.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | vulkan.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
    var attachments = [_]vulkan.VkAttachmentDescription{ colorAttachment, depthAttachment };

    var renderPassInfo = vulkan.VkRenderPassCreateInfo{};
    renderPassInfo.sType = vulkan.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    renderPassInfo.attachmentCount = attachments.len;
    renderPassInfo.pAttachments = &attachments;
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
    depthImageView: vulkan.VkImageView,
) ![]vulkan.VkFramebuffer {
    const swapChainFramebuffers = try allocator.alloc(vulkan.VkFramebuffer, swapChainImageViews.len);

    for (swapChainImageViews, 0..) |imageView, i| {
        var attachments = [_]vulkan.VkImageView{ imageView, depthImageView };

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
    pipelineLayout: vulkan.VkPipelineLayout,
    descriptorSet: *vulkan.VkDescriptorSet,
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

    const clearValues = [_]vulkan.VkClearValue{
        .{ .color = .{ .float32 = .{ 0.0, 0.0, 0.0, 1.0 } } },
        .{ .depthStencil = .{ .depth = 1.0, .stencil = 0.0 } },
    };
    renderPassInfo.clearValueCount = clearValues.len;
    renderPassInfo.pClearValues = &clearValues;

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
        vulkan.vkCmdBindDescriptorSets(
            commandBuffer,
            vulkan.VK_PIPELINE_BIND_POINT_GRAPHICS,
            pipelineLayout,
            0,
            1,
            descriptorSet,
            0,
            null,
        );

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
        if ((typeFilter & @shlExact(i, 1) != 0) and ((memProperties.memoryTypes[i].propertyFlags & properties) == properties)) {
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
    const commandBuffer = try beginSingleTimeCommands(device, commandPool);

    var copyRegion = vulkan.VkBufferCopy{};
    copyRegion.srcOffset = 0; // Optional
    copyRegion.dstOffset = 0; // Optional
    copyRegion.size = size;
    vulkan.vkCmdCopyBuffer(commandBuffer, srcBuffer, dstBuffer, 1, &copyRegion);

    try endSingleTimeCommands(device, commandPool, commandBuffer, graphicQueue);
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

fn createDescriptorSetLayout(device: vulkan.VkDevice) !vulkan.VkDescriptorSetLayout {
    var uboLayoutBinding = vulkan.VkDescriptorSetLayoutBinding{};
    uboLayoutBinding.binding = 0;
    uboLayoutBinding.descriptorType = vulkan.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    uboLayoutBinding.descriptorCount = 1;
    uboLayoutBinding.stageFlags = vulkan.VK_SHADER_STAGE_VERTEX_BIT;
    uboLayoutBinding.pImmutableSamplers = null; // Optional

    var samplerLayoutBinding = vulkan.VkDescriptorSetLayoutBinding{};
    samplerLayoutBinding.binding = 1;
    samplerLayoutBinding.descriptorCount = 1;
    samplerLayoutBinding.descriptorType = vulkan.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    samplerLayoutBinding.pImmutableSamplers = null;
    samplerLayoutBinding.stageFlags = vulkan.VK_SHADER_STAGE_FRAGMENT_BIT;

    const bindings = [_]vulkan.VkDescriptorSetLayoutBinding{ uboLayoutBinding, samplerLayoutBinding };

    var layoutInfo = vulkan.VkDescriptorSetLayoutCreateInfo{};
    layoutInfo.sType = vulkan.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    layoutInfo.bindingCount = bindings.len;
    layoutInfo.pBindings = &bindings;

    var descriptorSetLayout: vulkan.VkDescriptorSetLayout = null;
    if (vulkan.VK_SUCCESS != vulkan.vkCreateDescriptorSetLayout(device, &layoutInfo, null, &descriptorSetLayout)) {
        return error.FailedToCreateDescriptorSetLayout;
    }

    return descriptorSetLayout;
}

fn createUniformBuffers(allocator: Allocator, device: vulkan.VkDevice, physicalDevice: vulkan.VkPhysicalDevice) !struct {
    []vulkan.VkBuffer,
    []vulkan.VkDeviceMemory,
    [][]u8,
} {
    const bufferSize = @sizeOf(UniformBufferObject);

    const uniformBuffers = try allocator.alloc(vulkan.VkBuffer, MAX_FRAMES_IN_FLIGHT);
    const uniformBuffersMemory = try allocator.alloc(vulkan.VkDeviceMemory, MAX_FRAMES_IN_FLIGHT);
    const uniformBuffersMapped = try allocator.alloc([]u8, MAX_FRAMES_IN_FLIGHT);

    for (0..MAX_FRAMES_IN_FLIGHT) |i| {
        const b, const m = try createBuffer(
            device,
            physicalDevice,
            bufferSize,
            vulkan.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            vulkan.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vulkan.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        );

        uniformBuffers[i] = b;
        uniformBuffersMemory[i] = m;

        var memory: [*c]u8 = null;
        if (vulkan.VK_SUCCESS != vulkan.vkMapMemory(device, uniformBuffersMemory[i], 0, bufferSize, 0, @ptrCast(&memory))) {
            return error.FailedToMapMemory;
        }
        uniformBuffersMapped[i] = memory[0..bufferSize];
    }

    return .{ uniformBuffers, uniformBuffersMemory, uniformBuffersMapped };
}

fn updateUniformBuffer(self: *Self) !void {
    const now = try std.time.Instant.now();

    const ellapsed: f32 = @as(f32, @floatFromInt(now.since(self.startTime))) / 1_000_000_000.0;

    const Mat4 = zalgebra.Mat4;
    const Vector3 = zalgebra.GenericVector(3, f32);
    const model = Mat4.identity().rotate(ellapsed * 90.0, Vector3.new(0.0, 0.0, 1.0));
    const view = Mat4.lookAt(Vector3.new(2, 2, 2), Vector3.new(0, 0, 0), Vector3.new(0, 0, 1));
    var proj = Mat4.perspective(
        45,
        @as(f32, @floatFromInt(self.extent.width)) / @as(f32, @floatFromInt(self.extent.height)),
        0.1,
        10.0,
    );

    proj.data[1][1] *= -1;

    var ubo = UniformBufferObject{
        .view = view,
        .proj = proj,
        .model = model,
    };

    @memcpy(self.uniformBuffersMapped[self.currentFrame], std.mem.asBytes(&ubo));
}

fn createDescriptorPool(device: vulkan.VkDevice) !vulkan.VkDescriptorPool {
    var poolSizes = [_]vulkan.VkDescriptorPoolSize{
        .{
            .type = vulkan.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = MAX_FRAMES_IN_FLIGHT,
        },
        .{
            .type = vulkan.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = MAX_FRAMES_IN_FLIGHT,
        },
    };

    var poolInfo = vulkan.VkDescriptorPoolCreateInfo{};
    poolInfo.sType = vulkan.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    poolInfo.poolSizeCount = poolSizes.len;
    poolInfo.pPoolSizes = &poolSizes;
    poolInfo.maxSets = MAX_FRAMES_IN_FLIGHT;

    var descriptorPool: vulkan.VkDescriptorPool = null;
    if (vulkan.VK_SUCCESS != vulkan.vkCreateDescriptorPool(device, &poolInfo, null, &descriptorPool)) {
        return error.FailedToAllocateDescriptorPool;
    }

    return descriptorPool;
}

fn createDescriptorSet(
    allocator: Allocator,
    device: vulkan.VkDevice,
    descriptorPool: vulkan.VkDescriptorPool,
    uniformBuffers: []vulkan.VkBuffer,
    descriptorSetLayout: vulkan.VkDescriptorSetLayout,
    textureImageView: vulkan.VkImageView,
    textureSampler: vulkan.VkSampler,
) ![]vulkan.VkDescriptorSet {
    var layouts: [MAX_FRAMES_IN_FLIGHT]vulkan.VkDescriptorSetLayout = .{ descriptorSetLayout, descriptorSetLayout };

    var allocInfo = vulkan.VkDescriptorSetAllocateInfo{};
    allocInfo.sType = vulkan.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    allocInfo.descriptorPool = descriptorPool;
    allocInfo.descriptorSetCount = layouts.len;
    allocInfo.pSetLayouts = &layouts;

    const descriptorSets = try allocator.alloc(vulkan.VkDescriptorSet, MAX_FRAMES_IN_FLIGHT);
    if (vulkan.VK_SUCCESS != vulkan.vkAllocateDescriptorSets(device, &allocInfo, descriptorSets.ptr)) {
        return error.FailedToAllocateDescriptorSets;
    }

    for (0..MAX_FRAMES_IN_FLIGHT) |i| {
        var bufferInfo = vulkan.VkDescriptorBufferInfo{};
        bufferInfo.buffer = uniformBuffers[i];
        bufferInfo.offset = 0;
        bufferInfo.range = @sizeOf(UniformBufferObject);

        var imageInfo = vulkan.VkDescriptorImageInfo{};
        imageInfo.imageLayout = vulkan.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        imageInfo.imageView = textureImageView;
        imageInfo.sampler = textureSampler;

        var descriptorWrites = [2]vulkan.VkWriteDescriptorSet{
            .{
                .sType = vulkan.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = descriptorSets[i],
                .dstBinding = 0,
                .dstArrayElement = 0,
                .descriptorType = vulkan.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .descriptorCount = 1,
                .pBufferInfo = &bufferInfo,
                .pImageInfo = null, // Optional
                .pTexelBufferView = null, // Optional
            },
            .{
                .sType = vulkan.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = descriptorSets[i],
                .dstBinding = 1,
                .dstArrayElement = 0,
                .descriptorType = vulkan.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .descriptorCount = 1,
                .pBufferInfo = null,
                .pImageInfo = &imageInfo, // Optional
                .pTexelBufferView = null, // Optional
            },
        };

        vulkan.vkUpdateDescriptorSets(device, 2, &descriptorWrites, 0, null);
    }
    return descriptorSets;
}

fn createTextureImage(device: vulkan.VkDevice, physicalDevice: vulkan.VkPhysicalDevice, commandPool: vulkan.VkCommandPool, graphicsQueue: vulkan.VkQueue) !struct { vulkan.VkImage, vulkan.VkDeviceMemory } {
    const pixels = @embedFile("texture.rgba");

    const width = 512;
    const height = 512;
    const channels = 4;

    const bufferSize = width * height * channels;
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
    @memcpy(data[0..bufferSize], pixels);
    vulkan.vkUnmapMemory(device, stagingBufferMemory);

    const textureImage, const textureImageMemory = try createImage(
        device,
        physicalDevice,
        width,
        height,
        vulkan.VK_FORMAT_R8G8B8A8_SRGB,
        vulkan.VK_IMAGE_TILING_OPTIMAL,
        vulkan.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vulkan.VK_IMAGE_USAGE_SAMPLED_BIT,
        vulkan.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    );

    try transitionImageLayout(
        device,
        commandPool,
        graphicsQueue,
        textureImage,
        vulkan.VK_FORMAT_R8G8B8A8_SRGB,
        vulkan.VK_IMAGE_LAYOUT_UNDEFINED,
        vulkan.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    );
    try copyBufferToImage(
        device,
        commandPool,
        graphicsQueue,
        stagingBuffer,
        textureImage,
        width,
        height,
    );
    try transitionImageLayout(
        device,
        commandPool,
        graphicsQueue,
        textureImage,
        vulkan.VK_FORMAT_R8G8B8A8_SRGB,
        vulkan.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        vulkan.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    );

    return .{ textureImage, textureImageMemory };
}

fn createImage(
    device: vulkan.VkDevice,
    physicalDevice: vulkan.VkPhysicalDevice,
    width: u32,
    height: u32,
    format: vulkan.VkFormat,
    tiling: vulkan.VkImageTiling,
    usage: vulkan.VkImageUsageFlags,
    properties: vulkan.VkMemoryPropertyFlags,
) !struct { vulkan.VkImage, vulkan.VkDeviceMemory } {
    var imageInfo = vulkan.VkImageCreateInfo{};
    imageInfo.sType = vulkan.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    imageInfo.imageType = vulkan.VK_IMAGE_TYPE_2D;
    imageInfo.extent.width = width;
    imageInfo.extent.height = height;
    imageInfo.extent.depth = 1;
    imageInfo.mipLevels = 1;
    imageInfo.arrayLayers = 1;
    imageInfo.format = format;
    imageInfo.tiling = tiling;
    imageInfo.initialLayout = vulkan.VK_IMAGE_LAYOUT_UNDEFINED;
    imageInfo.usage = usage;
    imageInfo.sharingMode = vulkan.VK_SHARING_MODE_EXCLUSIVE;
    imageInfo.samples = vulkan.VK_SAMPLE_COUNT_1_BIT;
    imageInfo.flags = 0; // Optional

    var textureImage: vulkan.VkImage = null;
    if (vulkan.VK_SUCCESS != vulkan.vkCreateImage(device, &imageInfo, null, &textureImage)) {
        return error.FailedToCreateImage;
    }

    var memRequirements = vulkan.VkMemoryRequirements{};
    vulkan.vkGetImageMemoryRequirements(device, textureImage, &memRequirements);

    var allocInfo = vulkan.VkMemoryAllocateInfo{};
    allocInfo.sType = vulkan.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocInfo.allocationSize = memRequirements.size;
    allocInfo.memoryTypeIndex = try findMemoryType(physicalDevice, memRequirements.memoryTypeBits, properties);

    var textureImageMemory: vulkan.VkDeviceMemory = null;
    if (vulkan.VK_SUCCESS != vulkan.vkAllocateMemory(device, &allocInfo, null, &textureImageMemory)) {
        return error.FailedToAllocateMemory;
    }

    if (vulkan.VK_SUCCESS != vulkan.vkBindImageMemory(device, textureImage, textureImageMemory, 0)) {
        return error.FailedToBindMemory;
    }
    return .{ textureImage, textureImageMemory };
}

fn beginSingleTimeCommands(device: vulkan.VkDevice, commandPool: vulkan.VkCommandPool) !vulkan.VkCommandBuffer {
    var allocInfo = vulkan.VkCommandBufferAllocateInfo{};
    allocInfo.sType = vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    allocInfo.level = vulkan.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    allocInfo.commandPool = commandPool;
    allocInfo.commandBufferCount = 1;

    var commandBuffer: vulkan.VkCommandBuffer = null;
    if (vulkan.VK_SUCCESS != vulkan.vkAllocateCommandBuffers(device, &allocInfo, &commandBuffer)) {
        return error.AllocateCommandBufferFailed;
    }

    var beginInfo = vulkan.VkCommandBufferBeginInfo{};
    beginInfo.sType = vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    beginInfo.flags = vulkan.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;

    if (vulkan.VK_SUCCESS != vulkan.vkBeginCommandBuffer(commandBuffer, &beginInfo)) {
        return error.BeginCommandBufferFailed;
    }

    return commandBuffer;
}

fn endSingleTimeCommands(
    device: vulkan.VkDevice,
    commandPool: vulkan.VkCommandPool,
    commandBuffer: vulkan.VkCommandBuffer,
    graphicsQueue: vulkan.VkQueue,
) !void {
    if (vulkan.VK_SUCCESS != vulkan.vkEndCommandBuffer(commandBuffer)) {
        return error.EndCommandBufferFailed;
    }

    var submitInfo = vulkan.VkSubmitInfo{};
    submitInfo.sType = vulkan.VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &commandBuffer;

    if (vulkan.VK_SUCCESS != vulkan.vkQueueSubmit(graphicsQueue, 1, &submitInfo, null)) {
        return error.QueueSubmitFailed;
    }
    if (vulkan.VK_SUCCESS != vulkan.vkQueueWaitIdle(graphicsQueue)) {
        return error.QueueWaitFailed;
    }

    vulkan.vkFreeCommandBuffers(device, commandPool, 1, &commandBuffer);
}

fn transitionImageLayout(
    device: vulkan.VkDevice,
    commandPool: vulkan.VkCommandPool,
    graphicsQueue: vulkan.VkQueue,
    image: vulkan.VkImage,
    format: vulkan.VkFormat,
    oldLayout: vulkan.VkImageLayout,
    newLayout: vulkan.VkImageLayout,
) !void {
    const commandBuffer = try beginSingleTimeCommands(device, commandPool);

    var barrier = vulkan.VkImageMemoryBarrier{};
    barrier.sType = vulkan.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrier.oldLayout = oldLayout;
    barrier.newLayout = newLayout;
    barrier.srcQueueFamilyIndex = vulkan.VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = vulkan.VK_QUEUE_FAMILY_IGNORED;
    barrier.image = image;
    barrier.subresourceRange.aspectMask = vulkan.VK_IMAGE_ASPECT_COLOR_BIT;
    barrier.subresourceRange.baseMipLevel = 0;
    barrier.subresourceRange.levelCount = 1;
    barrier.subresourceRange.baseArrayLayer = 0;
    barrier.subresourceRange.layerCount = 1;

    var sourceStage: vulkan.VkPipelineStageFlags = undefined;
    var destinationStage: vulkan.VkPipelineStageFlags = undefined;

    if (oldLayout == vulkan.VK_IMAGE_LAYOUT_UNDEFINED and newLayout == vulkan.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) {
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = vulkan.VK_ACCESS_TRANSFER_WRITE_BIT;

        sourceStage = vulkan.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        destinationStage = vulkan.VK_PIPELINE_STAGE_TRANSFER_BIT;
    } else if (oldLayout == vulkan.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL and newLayout == vulkan.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
        barrier.srcAccessMask = vulkan.VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = vulkan.VK_ACCESS_SHADER_READ_BIT;

        sourceStage = vulkan.VK_PIPELINE_STAGE_TRANSFER_BIT;
        destinationStage = vulkan.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
    } else if (oldLayout == vulkan.VK_IMAGE_LAYOUT_UNDEFINED and newLayout == vulkan.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL) {
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = vulkan.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT | vulkan.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;

        sourceStage = vulkan.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        destinationStage = vulkan.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
    } else {
        return error.UnsupportedLayoutTransition;
    }

    if (newLayout == vulkan.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL) {
        barrier.subresourceRange.aspectMask = vulkan.VK_IMAGE_ASPECT_DEPTH_BIT;

        if (hasStencilComponent(format)) {
            barrier.subresourceRange.aspectMask |= vulkan.VK_IMAGE_ASPECT_STENCIL_BIT;
        }
    } else {
        barrier.subresourceRange.aspectMask = vulkan.VK_IMAGE_ASPECT_COLOR_BIT;
    }

    vulkan.vkCmdPipelineBarrier(
        commandBuffer,
        sourceStage,
        destinationStage,
        0,
        0,
        null,
        0,
        null,
        1,
        &barrier,
    );

    try endSingleTimeCommands(device, commandPool, commandBuffer, graphicsQueue);
}

fn copyBufferToImage(
    device: vulkan.VkDevice,
    commandPool: vulkan.VkCommandPool,
    graphicsQueue: vulkan.VkQueue,
    buffer: vulkan.VkBuffer,
    image: vulkan.VkImage,
    width: u32,
    height: u32,
) !void {
    const commandBuffer = try beginSingleTimeCommands(device, commandPool);

    var region = vulkan.VkBufferImageCopy{};
    region.bufferOffset = 0;
    region.bufferRowLength = 0;
    region.bufferImageHeight = 0;

    region.imageSubresource.aspectMask = vulkan.VK_IMAGE_ASPECT_COLOR_BIT;
    region.imageSubresource.mipLevel = 0;
    region.imageSubresource.baseArrayLayer = 0;
    region.imageSubresource.layerCount = 1;

    region.imageOffset = .{ .x = 0, .y = 0, .z = 0 };
    region.imageExtent = .{ .width = width, .height = height, .depth = 1 };

    vulkan.vkCmdCopyBufferToImage(
        commandBuffer,
        buffer,
        image,
        vulkan.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        1,
        &region,
    );

    try endSingleTimeCommands(device, commandPool, commandBuffer, graphicsQueue);
}

fn createTextureImageView(device: vulkan.VkDevice, textureImage: vulkan.VkImage) !vulkan.VkImageView {
    return createImageView(device, textureImage, vulkan.VK_FORMAT_R8G8B8A8_SRGB, vulkan.VK_IMAGE_ASPECT_COLOR_BIT);
}

fn createImageView(
    device: vulkan.VkDevice,
    image: vulkan.VkImage,
    format: vulkan.VkFormat,
    aspectFlags: vulkan.VkImageAspectFlags,
) !vulkan.VkImageView {
    var viewInfo = vulkan.VkImageViewCreateInfo{};
    viewInfo.sType = vulkan.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    viewInfo.image = image;
    viewInfo.viewType = vulkan.VK_IMAGE_VIEW_TYPE_2D;
    viewInfo.format = format;
    viewInfo.subresourceRange.aspectMask = aspectFlags;
    viewInfo.subresourceRange.baseMipLevel = 0;
    viewInfo.subresourceRange.levelCount = 1;
    viewInfo.subresourceRange.baseArrayLayer = 0;
    viewInfo.subresourceRange.layerCount = 1;

    var imageView: vulkan.VkImageView = null;
    if (vulkan.VK_SUCCESS != vulkan.vkCreateImageView(device, &viewInfo, null, &imageView)) {
        return error.CreateImageViewFailed;
    }

    return imageView;
}

fn createTextureSampler(device: vulkan.VkDevice, physicalDevice: vulkan.VkPhysicalDevice) !vulkan.VkSampler {
    var properties = vulkan.VkPhysicalDeviceProperties{};
    vulkan.vkGetPhysicalDeviceProperties(physicalDevice, &properties);

    var samplerInfo = vulkan.VkSamplerCreateInfo{};
    samplerInfo.sType = vulkan.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
    samplerInfo.magFilter = vulkan.VK_FILTER_LINEAR;
    samplerInfo.minFilter = vulkan.VK_FILTER_LINEAR;
    samplerInfo.addressModeU = vulkan.VK_SAMPLER_ADDRESS_MODE_REPEAT;
    samplerInfo.addressModeV = vulkan.VK_SAMPLER_ADDRESS_MODE_REPEAT;
    samplerInfo.addressModeW = vulkan.VK_SAMPLER_ADDRESS_MODE_REPEAT;
    samplerInfo.anisotropyEnable = vulkan.VK_TRUE;
    samplerInfo.maxAnisotropy = properties.limits.maxSamplerAnisotropy;
    samplerInfo.borderColor = vulkan.VK_BORDER_COLOR_INT_OPAQUE_BLACK;
    samplerInfo.unnormalizedCoordinates = vulkan.VK_FALSE;
    samplerInfo.compareEnable = vulkan.VK_FALSE;
    samplerInfo.compareOp = vulkan.VK_COMPARE_OP_ALWAYS;
    samplerInfo.mipmapMode = vulkan.VK_SAMPLER_MIPMAP_MODE_LINEAR;
    samplerInfo.mipLodBias = 0.0;
    samplerInfo.minLod = 0.0;
    samplerInfo.maxLod = 0.0;

    var textureSampler: vulkan.VkSampler = null;
    if (vulkan.VK_SUCCESS != vulkan.vkCreateSampler(device, &samplerInfo, null, &textureSampler)) {
        return error.FailedToCreateSampler;
    }
    return textureSampler;
}

fn createDepthResources(
    device: vulkan.VkDevice,
    physicalDevice: vulkan.VkPhysicalDevice,
    commandPool: vulkan.VkCommandPool,
    graphicsQueue: vulkan.VkQueue,
    swapChainExtent: vulkan.VkExtent2D,
) !struct { vulkan.VkImage, vulkan.VkDeviceMemory, vulkan.VkImageView } {
    const depthFormat = try findDepthFormat(physicalDevice);
    const depthImage, const depthImageMemory = try createImage(
        device,
        physicalDevice,
        swapChainExtent.width,
        swapChainExtent.height,
        depthFormat,
        vulkan.VK_IMAGE_TILING_OPTIMAL,
        vulkan.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
        vulkan.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    );

    const depthImageView = try createImageView(device, depthImage, depthFormat, vulkan.VK_IMAGE_ASPECT_DEPTH_BIT);

    try transitionImageLayout(
        device,
        commandPool,
        graphicsQueue,
        depthImage,
        depthFormat,
        vulkan.VK_IMAGE_LAYOUT_UNDEFINED,
        vulkan.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    );

    return .{ depthImage, depthImageMemory, depthImageView };
}

fn findSupportedFormat(
    physicalDevice: vulkan.VkPhysicalDevice,
    candidates: []vulkan.VkFormat,
    tiling: vulkan.VkImageTiling,
    features: vulkan.VkFormatFeatureFlags,
) !vulkan.VkFormat {
    for (candidates) |format| {
        var props = vulkan.VkFormatProperties{};
        vulkan.vkGetPhysicalDeviceFormatProperties(physicalDevice, format, &props);
        if (tiling == vulkan.VK_IMAGE_TILING_LINEAR and (props.linearTilingFeatures & features) == features) {
            return format;
        } else if (tiling == vulkan.VK_IMAGE_TILING_OPTIMAL and (props.optimalTilingFeatures & features) == features) {
            return format;
        }
    }
    return error.FailedToFindFormat;
}

fn findDepthFormat(physicalDevice: vulkan.VkPhysicalDevice) !vulkan.VkFormat {
    var formats = [_]vulkan.VkFormat{ vulkan.VK_FORMAT_D32_SFLOAT, vulkan.VK_FORMAT_D32_SFLOAT_S8_UINT, vulkan.VK_FORMAT_D24_UNORM_S8_UINT };
    return findSupportedFormat(
        physicalDevice,
        &formats,
        vulkan.VK_IMAGE_TILING_OPTIMAL,
        vulkan.VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT,
    );
}

fn hasStencilComponent(format: vulkan.VkFormat) bool {
    return format == vulkan.VK_FORMAT_D32_SFLOAT_S8_UINT or format == vulkan.VK_FORMAT_D24_UNORM_S8_UINT;
}
