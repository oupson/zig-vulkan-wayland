const vulkan = @cImport({
    @cInclude("vulkan/vulkan.h");
});

ptr: *anyopaque,
vtable: struct {
    createVulkanSurface: *const fn (*anyopaque, vulkan.VkInstance) anyerror!vulkan.VkSurfaceKHR,
},

pub fn createVulkanSurface(self: @This(), instance: vulkan.VkInstance) !vulkan.VkSurfaceKHR {
    return try self.vtable.createVulkanSurface(self.ptr, instance);
}
