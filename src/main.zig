const std = @import("std");
const c = @cImport({
    @cInclude("webgpu.h");
});
const glfw = @import("mach-glfw");
const Context = @import("mod.zig").Context;

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    _ = glfw.init(.{});

    const window = glfw.Window.create(
        1280,
        720,
        "zwgpu",
        null,
        null,
        .{ .client_api = .no_api },
    ) orelse return error.glfwError;

    const platform = glfw.getPlatform();

    var ctx: Context = undefined;
    // _ = surface; // autofix
    switch (platform) {
        .x11 => {
            const native = glfw.Native(.{ .x11 = true });
            const display = native.getX11Display();
            const x11_window = native.getX11Window(window);

            const xlib: c.WGPUSurfaceDescriptorFromXlibWindow = .{
                .chain = c.WGPUChainedStruct{
                    .sType = c.WGPUSType_SurfaceDescriptorFromXlibWindow,
                },
                .display = display,
                .window = x11_window,
            };

            const size = window.getSize();
            ctx = try Context.init(c.WGPUSurfaceDescriptor{
                .nextInChain = @ptrCast(&xlib),
            }, size.width, size.height);
        },
        else => @panic("unsupported platform"),
    }

    const module = blk: {
        const wgsl_code = try std.fs.cwd().readFileAlloc(allocator, "./shader.wgsl", std.math.maxInt(usize));
        const wgsl_code_string = try std.fmt.allocPrintZ(allocator, "{s}", .{wgsl_code});
        defer allocator.free(wgsl_code);
        defer allocator.free(wgsl_code_string);

        const module = c.wgpuDeviceCreateShaderModule(ctx.device, @ptrCast(&c.WGPUShaderModuleDescriptor{
            .label = "main",
            .nextInChain = @ptrCast(&c.WGPUShaderModuleWGSLDescriptor{
                .chain = c.WGPUChainedStruct{
                    .sType = c.WGPUSType_ShaderModuleWGSLDescriptor,
                },
                .code = wgsl_code_string.ptr,
            }),
        }));

        break :blk module;
    };

    const pipeline_layout = c.wgpuDeviceCreatePipelineLayout(ctx.device, &c.WGPUPipelineLayoutDescriptor{
        .label = "main",
    });

    const render_pipeline = c.wgpuDeviceCreateRenderPipeline(ctx.device, &c.WGPURenderPipelineDescriptor{
        .label = "render_pipeline",
        .layout = pipeline_layout,
        .vertex = c.WGPUVertexState{
            .module = module,
            .entryPoint = "vs_main",
        },
        .fragment = &c.WGPUFragmentState{
            .module = module,
            .entryPoint = "fs_main",
            .targets = &c.WGPUColorTargetState{
                .format = ctx.config.format,
                .writeMask = c.WGPUColorWriteMask_All,
            },
            .targetCount = 1,
        },
        .primitive = c.WGPUPrimitiveState{
            .topology = c.WGPUPrimitiveTopology_TriangleList,
        },
        .multisample = c.WGPUMultisampleState{
            .count = 1,
            .mask = 0xFFFFFFFF,
        },
    });

    const queue = c.wgpuDeviceGetQueue(ctx.device);

    while (!window.shouldClose()) {
        glfw.pollEvents();

        var surface_texture: c.WGPUSurfaceTexture = undefined;
        c.wgpuSurfaceGetCurrentTexture(ctx.surface, &surface_texture);

        switch (surface_texture.status) {
            c.WGPUSurfaceGetCurrentTextureStatus_Success => {},
            c.WGPUSurfaceGetCurrentTextureStatus_Timeout | c.WGPUSurfaceGetCurrentTextureStatus_Outdated | c.WGPUSurfaceGetCurrentTextureStatus_Lost => {
                if (surface_texture.texture != null) {
                    c.wgpuTextureRelease(surface_texture.texture);
                }
                const size = window.getSize();
                ctx.config.width = size.width;
                ctx.config.height = size.height;
                c.wgpuSurfaceConfigure(ctx.surface, &ctx.config);
                continue;
            },
            else => std.debug.panic("unexpected surface texture status {d}", .{surface_texture.status}),
        }

        const frame = c.wgpuTextureCreateView(surface_texture.texture, null);

        const command_encoder = c.wgpuDeviceCreateCommandEncoder(ctx.device, &c.WGPUCommandEncoderDescriptor{
            .label = "command_encoder",
        });
        const render_pass_encoder = c.wgpuCommandEncoderBeginRenderPass(command_encoder, &c.WGPURenderPassDescriptor{
            .label = "render_pass_encoder",
            .colorAttachmentCount = 1,
            .colorAttachments = &c.WGPURenderPassColorAttachment{
                .view = frame,
                .loadOp = c.WGPULoadOp_Clear,
                .storeOp = c.WGPUStoreOp_Store,
                .clearValue = c.WGPUColor{
                    .r = 0.0,
                    .g = 0.0,
                    .b = 0.0,
                    .a = 1.0,
                },
            },
        });
        c.wgpuRenderPassEncoderSetPipeline(render_pass_encoder, render_pipeline);
        c.wgpuRenderPassEncoderDraw(render_pass_encoder, 3, 1, 0, 0);
        c.wgpuRenderPassEncoderEnd(render_pass_encoder);
        c.wgpuRenderPassEncoderRelease(render_pass_encoder);

        const command_buffer = c.wgpuCommandEncoderFinish(command_encoder, &c.WGPUCommandBufferDescriptor{
            .label = "command_buffer",
        });
        c.wgpuQueueSubmit(queue, 1, &command_buffer);
        c.wgpuSurfacePresent(ctx.surface);

        c.wgpuCommandBufferRelease(command_buffer);
        c.wgpuCommandEncoderRelease(command_encoder);
        c.wgpuTextureViewRelease(frame);
        c.wgpuTextureRelease(surface_texture.texture);
    }
}
