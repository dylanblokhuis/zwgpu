const std = @import("std");
const c = @cImport({
    @cInclude("webgpu.h");
});

fn handle_request_adapter(status: c.WGPURequestAdapterStatus, adapter: c.WGPUAdapter, msg: [*c]const u8, user_data: ?*anyopaque) callconv(.C) void {
    const ctx: *Context = @ptrCast(@alignCast(user_data));
    if (status == c.WGPURequestAdapterStatus_Success) {
        ctx.*.adapter = adapter;
    } else {
        std.debug.panic("Failed to request adapter: {s}\n", .{msg});
    }
}

fn handle_request_device(status: c.WGPURequestDeviceStatus, device: c.WGPUDevice, msg: [*c]const u8, user_data: ?*anyopaque) callconv(.C) void {
    const ctx: *Context = @ptrCast(@alignCast(user_data));
    if (status == c.WGPURequestDeviceStatus_Success) {
        ctx.*.device = device;
    } else {
        std.debug.panic("Failed to request device: {s}\n", .{msg});
    }
}

pub const Context = struct {
    instance: c.WGPUInstance,
    surface: c.WGPUSurface,
    adapter: c.WGPUAdapter,
    device: c.WGPUDevice,
    config: c.WGPUSurfaceConfiguration,

    pub fn init(desc: c.WGPUSurfaceDescriptor, width: u32, height: u32) !Context {
        var ctx: Context = undefined;
        ctx.instance = c.wgpuCreateInstance(null);
        ctx.surface = c.wgpuInstanceCreateSurface(ctx.instance, &desc);
        c.wgpuInstanceRequestAdapter(ctx.instance, @ptrCast(&c.WGPURequestAdapterOptions{
            .compatibleSurface = ctx.surface,
        }), handle_request_adapter, &ctx);
        c.wgpuAdapterRequestDevice(ctx.adapter, null, handle_request_device, &ctx);

        // const queue = c.wgpuDeviceGetQueue(ctx.device);
        // _ = queue; // autofix
        var surface_capabilities: c.WGPUSurfaceCapabilities = undefined;
        c.wgpuSurfaceGetCapabilities(ctx.surface, ctx.adapter, &surface_capabilities);

        ctx.config = c.WGPUSurfaceConfiguration{
            .device = ctx.device,
            .usage = c.WGPUTextureUsage_RenderAttachment,
            .format = surface_capabilities.formats[0],
            .presentMode = c.WGPUPresentMode_Mailbox,
            .alphaMode = surface_capabilities.alphaModes[0],
            .width = width,
            .height = height,
        };
        c.wgpuSurfaceConfigure(ctx.surface, &ctx.config);

        return ctx;
    }
};
