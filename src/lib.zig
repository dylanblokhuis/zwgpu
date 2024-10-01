const std = @import("std");
const c = @cImport({
    @cInclude("webgpu.h");
});
const Context = @import("mod.zig").Context;

export fn init(width: u32, height: u32) void {
    const allocator = std.heap.wasm_allocator;
    const canvas: c.WGPUSurfaceDescriptorFromCanvasHTMLSelector = .{
        .chain = c.WGPUChainedStruct{
            .sType = c.WGPUSType_SurfaceDescriptorFromCanvasHTMLSelector,
        },
        .selector = "canvas",
    };

    const ctx = Context.init(.{
        .nextInChain = @ptrCast(&canvas),
    }, width, height) catch unreachable;
    _ = ctx; // autofix
    _ = allocator.alloc(u8, 1000) catch unreachable;
}
