const std = @import("std");
const c = @import("c.zig");
const core = @import("mach").core;
const gpu = core.gpu;

var allocator: std.mem.Allocator = undefined;

// ------------------------------------------------------------------------------------------------
// Public API
// ------------------------------------------------------------------------------------------------

pub const InitOptions = struct {
    max_frames_in_flight: u32 = 3,
    color_format: ?gpu.Texture.Format = null, // uses swap chain format if null
    depth_stencil_format: gpu.Texture.Format = .undefined,
    mag_filter: gpu.FilterMode = .linear,
    min_filter: gpu.FilterMode = .linear,
    mipmap_filter: gpu.MipmapFilterMode = .linear,
};

pub fn init(
    allocator_: std.mem.Allocator,
    device: *gpu.Device,
    options: InitOptions,
) !void {
    allocator = allocator_;

    var io: *c.ImGuiIO = @ptrCast(c.igGetIO());
    std.debug.assert(io.BackendPlatformUserData == null);
    std.debug.assert(io.BackendRendererUserData == null);

    const brp = try allocator.create(BackendPlatformData);
    brp.* = BackendPlatformData.init();
    io.BackendPlatformUserData = brp;

    const brd = try allocator.create(BackendRendererData);
    brd.* = BackendRendererData.init(device, options);
    io.BackendRendererUserData = brd;
}

pub fn shutdown() void {
    var bpd = BackendPlatformData.get();
    bpd.deinit();
    allocator.destroy(bpd);

    var brd = BackendRendererData.get();
    brd.deinit();
    allocator.destroy(brd);
}

pub fn newFrame() !void {
    try BackendPlatformData.get().newFrame();
    try BackendRendererData.get().newFrame();
}

pub fn processEvent(event: core.Event) bool {
    return BackendPlatformData.get().processEvent(event);
}

pub fn renderDrawData(draw_data: *c.ImDrawData, pass_encoder: *gpu.RenderPassEncoder) !void {
    try BackendRendererData.get().render(draw_data, pass_encoder);
}

// ------------------------------------------------------------------------------------------------
// Platform
// ------------------------------------------------------------------------------------------------

// Missing from mach:
// - HasSetMousePos
// - Clipboard
// - IME
// - Mouse Source (e.g. pen, touch)
// - Mouse Enter/Leave
// - joystick/gamepad

// Bugs?
// - Positive Delta Time

const BackendPlatformData = struct {
    pub fn init() BackendPlatformData {
        var io: *c.ImGuiIO = @ptrCast(c.igGetIO());
        io.BackendPlatformName = "imgui_mach";
        io.BackendFlags |= c.ImGuiBackendFlags_HasMouseCursors;
        //io.backend_flags |= c.ImGuiBackendFlags_HasSetMousePos;

        var bd = BackendPlatformData{};
        bd.setDisplaySizeAndScale();
        return bd;
    }

    pub fn deinit(bd: *BackendPlatformData) void {
        _ = bd;
        var io: *c.ImGuiIO = @ptrCast(c.igGetIO());
        io.BackendPlatformName = null;
    }

    pub fn get() *BackendPlatformData {
        std.debug.assert(c.igGetCurrentContext() != null);

        const io: *c.ImGuiIO = @ptrCast(c.igGetIO());
        return @ptrCast(@alignCast(io.BackendPlatformUserData));
    }

    pub fn newFrame(bd: *BackendPlatformData) !void {
        var io: *c.ImGuiIO = @ptrCast(c.igGetIO());

        bd.setDisplaySizeAndScale();

        // DeltaTime
        io.DeltaTime = if (core.delta_time > 0.0) core.delta_time else 1.0e-6;

        // WantSetMousePos - TODO

        // MouseCursor
        if ((io.ConfigFlags & c.ImGuiConfigFlags_NoMouseCursorChange) == 0) {
            const imgui_cursor = c.igGetMouseCursor();

            if (io.MouseDrawCursor or imgui_cursor == c.ImGuiMouseCursor_None) {
                core.setCursorMode(.hidden);
            } else {
                core.setCursorMode(.normal);
                core.setCursorShape(machCursorShape(imgui_cursor));
            }
        }

        // Gamepads - TODO
    }

    pub fn processEvent(bd: *BackendPlatformData, event: core.Event) bool {
        _ = bd;
        const io: *c.ImGuiIO = @ptrCast(c.igGetIO());
        switch (event) {
            .key_press, .key_repeat => |data| {
                addKeyMods(data.mods);
                const key = imguiKey(data.key);
                c.ImGuiIO_AddKeyEvent(io, key, true);
                return true;
            },
            .key_release => |data| {
                addKeyMods(data.mods);
                const key = imguiKey(data.key);
                c.ImGuiIO_AddKeyEvent(io, key, false);
                return true;
            },
            .char_input => |data| {
                c.ImGuiIO_AddInputCharacter(io, data.codepoint);
                return true;
            },
            .mouse_motion => |data| {
                // TODO - io.addMouseSourceEvent
                c.ImGuiIO_AddMousePosEvent(
                    io,
                    @floatCast(data.pos.x),
                    @floatCast(data.pos.y),
                );
                return true;
            },
            .mouse_press => |data| {
                const mouse_button = imguiMouseButton(data.button);
                // TODO - io.addMouseSourceEvent
                c.ImGuiIO_AddMouseButtonEvent(io, mouse_button, true);
                return true;
            },
            .mouse_release => |data| {
                const mouse_button = imguiMouseButton(data.button);
                // TODO - io.addMouseSourceEvent
                c.ImGuiIO_AddMouseButtonEvent(io, mouse_button, false);
                return true;
            },
            .mouse_scroll => |data| {
                // TODO - io.addMouseSourceEvent
                c.ImGuiIO_AddMouseWheelEvent(io, data.xoffset, data.yoffset);
                return true;
            },
            .joystick_connected => {},
            .joystick_disconnected => {},
            .framebuffer_resize => {},
            .focus_gained => {
                c.ImGuiIO_AddFocusEvent(io, true);
                return true;
            },
            .focus_lost => {
                c.ImGuiIO_AddFocusEvent(io, false);
                return true;
            },
            .close => {},

            // TODO - mouse enter/leave?
        }

        return false;
    }

    fn addKeyMods(mods: core.KeyMods) void {
        const io: *c.ImGuiIO = @ptrCast(c.igGetIO());
        c.ImGuiIO_AddKeyEvent(io, c.ImGuiMod_Ctrl, mods.control);
        c.ImGuiIO_AddKeyEvent(io, c.ImGuiMod_Shift, mods.shift);
        c.ImGuiIO_AddKeyEvent(io, c.ImGuiMod_Alt, mods.alt);
        c.ImGuiIO_AddKeyEvent(io, c.ImGuiMod_Super, mods.super);
    }

    fn setDisplaySizeAndScale(bd: *BackendPlatformData) void {
        _ = bd;
        var io: *c.ImGuiIO = @ptrCast(c.igGetIO());

        // DisplaySize
        const window_size = core.size();
        const w: f32 = @floatFromInt(window_size.width);
        const h: f32 = @floatFromInt(window_size.height);
        const display_w: f32 = @floatFromInt(core.descriptor.width);
        const display_h: f32 = @floatFromInt(core.descriptor.height);

        io.DisplaySize = c.ImVec2{ .x = w, .y = h };

        // DisplayFramebufferScale
        if (w > 0 and h > 0)
            io.DisplayFramebufferScale = c.ImVec2{ .x = display_w / w, .y = display_h / h };
    }

    fn imguiMouseButton(button: core.MouseButton) i32 {
        return @intFromEnum(button);
    }

    fn imguiKey(key: core.Key) c.ImGuiKey {
        return switch (key) {
            .a => c.ImGuiKey_A,
            .b => c.ImGuiKey_B,
            .c => c.ImGuiKey_C,
            .d => c.ImGuiKey_D,
            .e => c.ImGuiKey_E,
            .f => c.ImGuiKey_F,
            .g => c.ImGuiKey_G,
            .h => c.ImGuiKey_H,
            .i => c.ImGuiKey_I,
            .j => c.ImGuiKey_J,
            .k => c.ImGuiKey_K,
            .l => c.ImGuiKey_L,
            .m => c.ImGuiKey_M,
            .n => c.ImGuiKey_N,
            .o => c.ImGuiKey_O,
            .p => c.ImGuiKey_P,
            .q => c.ImGuiKey_Q,
            .r => c.ImGuiKey_R,
            .s => c.ImGuiKey_S,
            .t => c.ImGuiKey_T,
            .u => c.ImGuiKey_U,
            .v => c.ImGuiKey_V,
            .w => c.ImGuiKey_W,
            .x => c.ImGuiKey_X,
            .y => c.ImGuiKey_Y,
            .z => c.ImGuiKey_Z,

            .zero => c.ImGuiKey_0,
            .one => c.ImGuiKey_1,
            .two => c.ImGuiKey_2,
            .three => c.ImGuiKey_3,
            .four => c.ImGuiKey_4,
            .five => c.ImGuiKey_5,
            .six => c.ImGuiKey_6,
            .seven => c.ImGuiKey_7,
            .eight => c.ImGuiKey_8,
            .nine => c.ImGuiKey_9,

            .f1 => c.ImGuiKey_F1,
            .f2 => c.ImGuiKey_F2,
            .f3 => c.ImGuiKey_F3,
            .f4 => c.ImGuiKey_F4,
            .f5 => c.ImGuiKey_F5,
            .f6 => c.ImGuiKey_F6,
            .f7 => c.ImGuiKey_F7,
            .f8 => c.ImGuiKey_F8,
            .f9 => c.ImGuiKey_F9,
            .f10 => c.ImGuiKey_F10,
            .f11 => c.ImGuiKey_F11,
            .f12 => c.ImGuiKey_F12,
            .f13 => c.ImGuiKey_None,
            .f14 => c.ImGuiKey_None,
            .f15 => c.ImGuiKey_None,
            .f16 => c.ImGuiKey_None,
            .f17 => c.ImGuiKey_None,
            .f18 => c.ImGuiKey_None,
            .f19 => c.ImGuiKey_None,
            .f20 => c.ImGuiKey_None,
            .f21 => c.ImGuiKey_None,
            .f22 => c.ImGuiKey_None,
            .f23 => c.ImGuiKey_None,
            .f24 => c.ImGuiKey_None,
            .f25 => c.ImGuiKey_None,

            .kp_divide => c.ImGuiKey_KeypadDivide,
            .kp_multiply => c.ImGuiKey_KeypadMultiply,
            .kp_subtract => c.ImGuiKey_KeypadSubtract,
            .kp_add => c.ImGuiKey_KeypadAdd,
            .kp_0 => c.ImGuiKey_Keypad0,
            .kp_1 => c.ImGuiKey_Keypad1,
            .kp_2 => c.ImGuiKey_Keypad2,
            .kp_3 => c.ImGuiKey_Keypad3,
            .kp_4 => c.ImGuiKey_Keypad4,
            .kp_5 => c.ImGuiKey_Keypad5,
            .kp_6 => c.ImGuiKey_Keypad6,
            .kp_7 => c.ImGuiKey_Keypad7,
            .kp_8 => c.ImGuiKey_Keypad8,
            .kp_9 => c.ImGuiKey_Keypad9,
            .kp_decimal => c.ImGuiKey_KeypadDecimal,
            .kp_equal => c.ImGuiKey_KeypadEqual,
            .kp_enter => c.ImGuiKey_KeypadEnter,

            .enter => c.ImGuiKey_Enter,
            .escape => c.ImGuiKey_Escape,
            .tab => c.ImGuiKey_Tab,
            .left_shift => c.ImGuiKey_LeftShift,
            .right_shift => c.ImGuiKey_RightShift,
            .left_control => c.ImGuiKey_LeftCtrl,
            .right_control => c.ImGuiKey_RightCtrl,
            .left_alt => c.ImGuiKey_LeftAlt,
            .right_alt => c.ImGuiKey_RightAlt,
            .left_super => c.ImGuiKey_LeftSuper,
            .right_super => c.ImGuiKey_RightSuper,
            .menu => c.ImGuiKey_Menu,
            .num_lock => c.ImGuiKey_NumLock,
            .caps_lock => c.ImGuiKey_CapsLock,
            .print => c.ImGuiKey_PrintScreen,
            .scroll_lock => c.ImGuiKey_ScrollLock,
            .pause => c.ImGuiKey_Pause,
            .delete => c.ImGuiKey_Delete,
            .home => c.ImGuiKey_Home,
            .end => c.ImGuiKey_End,
            .page_up => c.ImGuiKey_PageUp,
            .page_down => c.ImGuiKey_PageDown,
            .insert => c.ImGuiKey_Insert,
            .left => c.ImGuiKey_LeftArrow,
            .right => c.ImGuiKey_RightArrow,
            .up => c.ImGuiKey_UpArrow,
            .down => c.ImGuiKey_DownArrow,
            .backspace => c.ImGuiKey_Backspace,
            .space => c.ImGuiKey_Space,
            .minus => c.ImGuiKey_Minus,
            .equal => c.ImGuiKey_Equal,
            .left_bracket => c.ImGuiKey_LeftBracket,
            .right_bracket => c.ImGuiKey_RightBracket,
            .backslash => c.ImGuiKey_Backslash,
            .semicolon => c.ImGuiKey_Semicolon,
            .apostrophe => c.ImGuiKey_Apostrophe,
            .comma => c.ImGuiKey_Comma,
            .period => c.ImGuiKey_Period,
            .slash => c.ImGuiKey_Slash,
            .grave => c.ImGuiKey_GraveAccent,

            .unknown => c.ImGuiKey_None,
        };
    }

    fn machCursorShape(imgui_cursor: c.ImGuiMouseCursor) core.CursorShape {
        return switch (imgui_cursor) {
            c.ImGuiMouseCursor_Arrow => .arrow,
            c.ImGuiMouseCursor_TextInput => .ibeam,
            c.ImGuiMouseCursor_ResizeAll => .resize_all,
            c.ImGuiMouseCursor_ResizeNS => .resize_ns,
            c.ImGuiMouseCursor_ResizeEW => .resize_ew,
            c.ImGuiMouseCursor_ResizeNESW => .resize_nesw,
            c.ImGuiMouseCursor_ResizeNWSE => .resize_nwse,
            c.ImGuiMouseCursor_Hand => .pointing_hand,
            c.ImGuiMouseCursor_NotAllowed => .not_allowed,
            else => unreachable,
        };
    }
};

// ------------------------------------------------------------------------------------------------
// Renderer
// ------------------------------------------------------------------------------------------------

fn alignUp(x: usize, a: usize) usize {
    return (x + a - 1) & ~(a - 1);
}

const Uniforms = struct {
    MVP: [4][4]f32,
};

const BackendRendererData = struct {
    device: *gpu.Device,
    queue: *gpu.Queue,
    color_format: gpu.Texture.Format,
    depth_stencil_format: gpu.Texture.Format,
    mag_filter: gpu.FilterMode,
    min_filter: gpu.FilterMode,
    mipmap_filter: gpu.MipmapFilterMode,
    device_resources: ?DeviceResources,
    max_frames_in_flight: u32,
    frame_index: u32,

    pub fn init(
        device: *gpu.Device,
        options: InitOptions,
    ) BackendRendererData {
        var io: *c.ImGuiIO = @ptrCast(c.igGetIO());
        io.BackendRendererName = "imgui_mach";
        io.BackendFlags |= c.ImGuiBackendFlags_RendererHasVtxOffset;

        return .{
            .device = device,
            .queue = device.getQueue(),
            .color_format = options.color_format orelse core.descriptor.format,
            .depth_stencil_format = options.depth_stencil_format,
            .mag_filter = options.mag_filter,
            .min_filter = options.min_filter,
            .mipmap_filter = options.mipmap_filter,
            .device_resources = null,
            .max_frames_in_flight = options.max_frames_in_flight,
            .frame_index = std.math.maxInt(u32),
        };
    }

    pub fn deinit(bd: *BackendRendererData) void {
        var io: *c.ImGuiIO = @ptrCast(c.igGetIO());
        io.BackendRendererName = null;
        io.BackendRendererUserData = null;

        if (bd.device_resources) |*device_resources| device_resources.deinit();
        bd.queue.release();
    }

    pub fn get() *BackendRendererData {
        std.debug.assert(c.igGetCurrentContext() != null);

        const io: *c.ImGuiIO = @ptrCast(c.igGetIO());
        return @ptrCast(@alignCast(io.BackendRendererUserData));
    }

    pub fn newFrame(bd: *BackendRendererData) !void {
        if (bd.device_resources == null)
            bd.device_resources = try DeviceResources.init(bd);
    }

    pub fn render(bd: *BackendRendererData, draw_data: *c.ImDrawData, pass_encoder: *gpu.RenderPassEncoder) !void {
        if (draw_data.DisplaySize.x <= 0.0 or draw_data.DisplaySize.y <= 0.0)
            return;

        // FIXME: Assuming that this only gets called once per frame!
        // If not, we can't just re-allocate the IB or VB, we'll have to do a proper allocator.
        if (bd.device_resources) |*device_resources| {
            bd.frame_index = @addWithOverflow(bd.frame_index, 1)[0];
            var fr = &device_resources.frame_resources[bd.frame_index % bd.max_frames_in_flight];

            // Create and grow vertex/index buffers if needed
            if (fr.vertex_buffer == null or fr.vertex_buffer_size < draw_data.TotalVtxCount) {
                if (fr.vertex_buffer) |buffer| {
                    //buffer.destroy();
                    buffer.release();
                }
                if (fr.vertices) |x| allocator.free(x);
                fr.vertex_buffer_size = @intCast(draw_data.TotalVtxCount + 5000);

                fr.vertex_buffer = bd.device.createBuffer(&.{
                    .label = "Dear ImGui Vertex buffer",
                    .usage = .{ .copy_dst = true, .vertex = true },
                    .size = alignUp(fr.vertex_buffer_size * @sizeOf(c.ImDrawVert), 4),
                });
                fr.vertices = try allocator.alloc(c.ImDrawVert, fr.vertex_buffer_size);
            }
            if (fr.index_buffer == null or fr.index_buffer_size < draw_data.TotalIdxCount) {
                if (fr.index_buffer) |buffer| {
                    //buffer.destroy();
                    buffer.release();
                }
                if (fr.indices) |x| allocator.free(x);
                fr.index_buffer_size = @intCast(draw_data.TotalIdxCount + 10000);

                fr.index_buffer = bd.device.createBuffer(&.{
                    .label = "Dear ImGui Index buffer",
                    .usage = .{ .copy_dst = true, .index = true },
                    .size = alignUp(fr.index_buffer_size * @sizeOf(c.ImDrawIdx), 4),
                });
                fr.indices = try allocator.alloc(c.ImDrawIdx, fr.index_buffer_size);
            }

            // Upload vertex/index data into a single contiguous GPU buffer
            var vtx_dst = fr.vertices.?;
            var idx_dst = fr.indices.?;
            var vb_write_size: usize = 0;
            var ib_write_size: usize = 0;
            for (0..@intCast(draw_data.CmdListsCount)) |n| {
                const cmd_list: *c.ImDrawList = @ptrCast(draw_data.CmdLists.Data[n]);
                const vtx_size: usize = @intCast(cmd_list.VtxBuffer.Size);
                const idx_size: usize = @intCast(cmd_list.IdxBuffer.Size);
                @memcpy(vtx_dst[0..vtx_size], cmd_list.VtxBuffer.Data[0..vtx_size]);
                @memcpy(idx_dst[0..idx_size], cmd_list.IdxBuffer.Data[0..idx_size]);
                vtx_dst = vtx_dst[vtx_size..];
                idx_dst = idx_dst[idx_size..];
                vb_write_size += vtx_size;
                ib_write_size += idx_size;
            }
            vb_write_size = alignUp(vb_write_size, 4);
            ib_write_size = alignUp(ib_write_size, 4);
            if (vb_write_size > 0)
                bd.queue.writeBuffer(fr.vertex_buffer.?, 0, fr.vertices.?[0..vb_write_size]);
            if (ib_write_size > 0)
                bd.queue.writeBuffer(fr.index_buffer.?, 0, fr.indices.?[0..ib_write_size]);

            // Setup desired render state
            bd.setupRenderState(draw_data, pass_encoder, fr);

            // Render command lists
            var global_vtx_offset: c_uint = 0;
            var global_idx_offset: c_uint = 0;
            const clip_scale = draw_data.FramebufferScale;
            const clip_off = draw_data.DisplayPos;
            const fb_width = draw_data.DisplaySize.x * clip_scale.x;
            const fb_height = draw_data.DisplaySize.y * clip_scale.y;
            for (0..@intCast(draw_data.CmdListsCount)) |n| {
                const cmd_list: *c.ImDrawList = @ptrCast(draw_data.CmdLists.Data[n]);
                for (0..@intCast(cmd_list.CmdBuffer.Size)) |cmd_i| {
                    const cmd = &cmd_list.CmdBuffer.Data[cmd_i];
                    if (cmd.UserCallback != null) {
                        // TODO - imgui.DrawCallback_ResetRenderState not generating yet
                        cmd.UserCallback.?(cmd_list, cmd);
                    } else {
                        // Texture
                        const tex_id = c.ImDrawCmd_GetTexID(cmd);
                        const entry = try device_resources.image_bind_groups.getOrPut(allocator, tex_id);
                        if (!entry.found_existing) {
                            entry.value_ptr.* = bd.device.createBindGroup(
                                &gpu.BindGroup.Descriptor.init(.{
                                    .layout = device_resources.image_bind_group_layout,
                                    .entries = &[_]gpu.BindGroup.Entry{
                                        .{ .binding = 0, .texture_view = @ptrCast(tex_id), .size = 0 },
                                    },
                                }),
                            );
                        }

                        const bind_group = entry.value_ptr.*;
                        pass_encoder.setBindGroup(1, bind_group, &.{});

                        // Scissor
                        const clip_min: c.ImVec2 = .{
                            .x = @max(0.0, (cmd.ClipRect.x - clip_off.x) * clip_scale.x),
                            .y = @max(0.0, (cmd.ClipRect.y - clip_off.y) * clip_scale.y),
                        };
                        const clip_max: c.ImVec2 = .{
                            .x = @min(fb_width, (cmd.ClipRect.z - clip_off.x) * clip_scale.x),
                            .y = @min(fb_height, (cmd.ClipRect.w - clip_off.y) * clip_scale.y),
                        };
                        if (clip_max.x <= clip_min.x or clip_max.y <= clip_min.y)
                            continue;

                        pass_encoder.setScissorRect(
                            @intFromFloat(clip_min.x),
                            @intFromFloat(clip_min.y),
                            @intFromFloat(clip_max.x - clip_min.x),
                            @intFromFloat(clip_max.y - clip_min.y),
                        );

                        // Draw
                        pass_encoder.drawIndexed(cmd.ElemCount, 1, @intCast(cmd.IdxOffset + global_idx_offset), @intCast(cmd.VtxOffset + global_vtx_offset), 0);
                    }
                }
                global_idx_offset += @intCast(cmd_list.IdxBuffer.Size);
                global_vtx_offset += @intCast(cmd_list.VtxBuffer.Size);
            }
        }
    }

    fn setupRenderState(
        bd: *BackendRendererData,
        draw_data: *c.ImDrawData,
        pass_encoder: *gpu.RenderPassEncoder,
        fr: *FrameResources,
    ) void {
        if (bd.device_resources) |device_resources| {
            const L = draw_data.DisplayPos.x;
            const R = draw_data.DisplayPos.x + draw_data.DisplaySize.x;
            const T = draw_data.DisplayPos.y;
            const B = draw_data.DisplayPos.y + draw_data.DisplaySize.y;

            const uniforms: Uniforms = .{
                .MVP = [4][4]f32{
                    [4]f32{ 2.0 / (R - L), 0.0, 0.0, 0.0 },
                    [4]f32{ 0.0, 2.0 / (T - B), 0.0, 0.0 },
                    [4]f32{ 0.0, 0.0, 0.5, 0.0 },
                    [4]f32{ (R + L) / (L - R), (T + B) / (B - T), 0.5, 1.0 },
                },
            };
            bd.queue.writeBuffer(device_resources.uniforms, 0, &[_]Uniforms{uniforms});

            const width: f32 = @floatFromInt(core.descriptor.width);
            const height: f32 = @floatFromInt(core.descriptor.height);
            const index_format: gpu.IndexFormat = if (@sizeOf(c.ImDrawIdx) == 2) .uint16 else .uint32;

            pass_encoder.setViewport(0, 0, width, height, 0, 1);
            pass_encoder.setVertexBuffer(0, fr.vertex_buffer.?, 0, fr.vertex_buffer_size * @sizeOf(c.ImDrawVert));
            pass_encoder.setIndexBuffer(fr.index_buffer.?, index_format, 0, fr.index_buffer_size * @sizeOf(c.ImDrawIdx));
            pass_encoder.setPipeline(device_resources.pipeline);
            pass_encoder.setBindGroup(0, device_resources.common_bind_group, &.{});
        }
    }
};

const DeviceResources = struct {
    pipeline: *gpu.RenderPipeline,
    font_texture: *gpu.Texture,
    font_texture_view: *gpu.TextureView,
    sampler: *gpu.Sampler,
    uniforms: *gpu.Buffer,
    common_bind_group: *gpu.BindGroup,
    image_bind_groups: std.AutoArrayHashMapUnmanaged(c.ImTextureID, *gpu.BindGroup),
    image_bind_group_layout: *gpu.BindGroupLayout,
    frame_resources: []FrameResources,

    pub fn init(bd: *BackendRendererData) !DeviceResources {
        // Bind Group layouts
        const common_bind_group_layout = bd.device.createBindGroupLayout(
            &gpu.BindGroupLayout.Descriptor.init(.{
                .entries = &[_]gpu.BindGroupLayout.Entry{
                    .{
                        .binding = 0,
                        .visibility = .{ .vertex = true, .fragment = true },
                        .buffer = .{ .type = .uniform },
                    },
                    .{
                        .binding = 1,
                        .visibility = .{ .fragment = true },
                        .sampler = .{ .type = .filtering },
                    },
                },
            }),
        );
        defer common_bind_group_layout.release();

        const image_bind_group_layout = bd.device.createBindGroupLayout(
            &gpu.BindGroupLayout.Descriptor.init(.{
                .entries = &[_]gpu.BindGroupLayout.Entry{
                    .{
                        .binding = 0,
                        .visibility = .{ .fragment = true },
                        .texture = .{ .sample_type = .float, .view_dimension = .dimension_2d },
                    },
                },
            }),
        );
        errdefer image_bind_group_layout.release();

        // Pipeline layout
        const pipeline_layout = bd.device.createPipelineLayout(
            &gpu.PipelineLayout.Descriptor.init(.{
                .bind_group_layouts = &[2]*gpu.BindGroupLayout{
                    common_bind_group_layout,
                    image_bind_group_layout,
                },
            }),
        );
        defer pipeline_layout.release();

        // Shaders
        const shader_module = bd.device.createShaderModuleWGSL("shader.wgsl", @embedFile("shader.wgsl"));
        defer shader_module.release();

        // Pipeline
        const pipeline = bd.device.createRenderPipeline(
            &.{
                .layout = pipeline_layout,
                .vertex = gpu.VertexState.init(.{
                    .module = shader_module,
                    .entry_point = "vertex_main",
                    .buffers = &[_]gpu.VertexBufferLayout{
                        gpu.VertexBufferLayout.init(.{
                            .array_stride = @sizeOf(c.ImDrawVert),
                            .step_mode = .vertex,
                            .attributes = &[_]gpu.VertexAttribute{
                                .{ .format = .float32x2, .offset = @offsetOf(c.ImDrawVert, "pos"), .shader_location = 0 },
                                .{ .format = .float32x2, .offset = @offsetOf(c.ImDrawVert, "uv"), .shader_location = 1 },
                                .{ .format = .unorm8x4, .offset = @offsetOf(c.ImDrawVert, "col"), .shader_location = 2 },
                            },
                        }),
                    },
                }),
                .primitive = .{
                    .topology = .triangle_list,
                    .strip_index_format = .undefined,
                    .front_face = .cw,
                    .cull_mode = .none,
                },
                .depth_stencil = if (bd.depth_stencil_format == .undefined) null else &.{
                    .format = bd.depth_stencil_format,
                    .depth_write_enabled = .false,
                    .depth_compare = .always,
                    .stencil_front = .{ .compare = .always },
                    .stencil_back = .{ .compare = .always },
                },
                .multisample = .{
                    .count = 1,
                    .mask = std.math.maxInt(u32),
                    .alpha_to_coverage_enabled = .false,
                },
                .fragment = &gpu.FragmentState.init(.{
                    .module = shader_module,
                    .entry_point = "fragment_main",
                    .targets = &[_]gpu.ColorTargetState{.{
                        .format = bd.color_format,
                        .blend = &.{
                            .alpha = .{ .operation = .add, .src_factor = .one, .dst_factor = .one_minus_src_alpha },
                            .color = .{ .operation = .add, .src_factor = .src_alpha, .dst_factor = .one_minus_src_alpha },
                        },
                        .write_mask = gpu.ColorWriteMaskFlags.all,
                    }},
                }),
            },
        );
        errdefer pipeline.release();

        // Font Texture
        const io: *c.ImGuiIO = @ptrCast(c.igGetIO());
        var pixels: ?*c_char = undefined;
        var width: c_int = undefined;
        var height: c_int = undefined;
        var size_pp: c_int = undefined;
        c.ImFontAtlas_GetTexDataAsRGBA32(
            io.Fonts,
            @ptrCast(&pixels),
            &width,
            &height,
            &size_pp,
        );
        const pixels_data: ?[*]c_char = @ptrCast(pixels);

        const font_texture = bd.device.createTexture(&.{
            .label = "Dear ImGui Font Texture",
            .dimension = .dimension_2d,
            .size = .{
                .width = @intCast(width),
                .height = @intCast(height),
                .depth_or_array_layers = 1,
            },
            .sample_count = 1,
            .format = .rgba8_unorm,
            .mip_level_count = 1,
            .usage = .{ .copy_dst = true, .texture_binding = true },
        });
        errdefer font_texture.release();

        const font_texture_view = font_texture.createView(null);
        errdefer font_texture_view.release();

        bd.queue.writeTexture(
            &.{
                .texture = font_texture,
                .mip_level = 0,
                .origin = .{ .x = 0, .y = 0, .z = 0 },
                .aspect = .all,
            },
            &.{
                .offset = 0,
                .bytes_per_row = @intCast(width * size_pp),
                .rows_per_image = @intCast(height),
            },
            &.{ .width = @intCast(width), .height = @intCast(height), .depth_or_array_layers = 1 },
            pixels_data.?[0..@intCast(width * size_pp * height)],
        );

        // Sampler
        const sampler = bd.device.createSampler(&.{
            .min_filter = bd.min_filter,
            .mag_filter = bd.mag_filter,
            .mipmap_filter = bd.mipmap_filter,
            .address_mode_u = .repeat,
            .address_mode_v = .repeat,
            .address_mode_w = .repeat,
            .max_anisotropy = 1,
        });
        errdefer sampler.release();

        // Uniforms
        const uniforms = bd.device.createBuffer(&.{
            .label = "Dear ImGui Uniform buffer",
            .usage = .{ .copy_dst = true, .uniform = true },
            .size = alignUp(@sizeOf(Uniforms), 16),
        });
        errdefer uniforms.release();

        // Common Bind Group
        const common_bind_group = bd.device.createBindGroup(
            &gpu.BindGroup.Descriptor.init(.{
                .layout = common_bind_group_layout,
                .entries = &[_]gpu.BindGroup.Entry{
                    .{ .binding = 0, .buffer = uniforms, .offset = 0, .size = alignUp(@sizeOf(Uniforms), 16) },
                    .{ .binding = 1, .sampler = sampler, .size = 0 },
                },
            }),
        );
        errdefer common_bind_group.release();

        // Image Bind Group
        const image_bind_group = bd.device.createBindGroup(
            &gpu.BindGroup.Descriptor.init(.{
                .layout = image_bind_group_layout,
                .entries = &[_]gpu.BindGroup.Entry{
                    .{ .binding = 0, .texture_view = font_texture_view, .size = 0 },
                },
            }),
        );
        errdefer image_bind_group.release();

        // Image Bind Groups
        var image_bind_groups = std.AutoArrayHashMapUnmanaged(c.ImTextureID, *gpu.BindGroup){};
        errdefer image_bind_groups.deinit(allocator);

        try image_bind_groups.put(allocator, font_texture_view, image_bind_group);

        // Frame Resources
        const frame_resources = try allocator.alloc(FrameResources, bd.max_frames_in_flight);
        for (0..bd.max_frames_in_flight) |i| {
            var fr = &frame_resources[i];
            fr.index_buffer = null;
            fr.vertex_buffer = null;
            fr.indices = null;
            fr.vertices = null;
            fr.index_buffer_size = 10000;
            fr.vertex_buffer_size = 5000;
        }

        // ImGui
        c.ImFontAtlas_SetTexID(io.Fonts, font_texture_view);

        // Result
        return .{
            .pipeline = pipeline,
            .font_texture = font_texture,
            .font_texture_view = font_texture_view,
            .sampler = sampler,
            .uniforms = uniforms,
            .common_bind_group = common_bind_group,
            .image_bind_groups = image_bind_groups,
            .image_bind_group_layout = image_bind_group_layout,
            .frame_resources = frame_resources,
        };
    }

    pub fn deinit(dr: *DeviceResources) void {
        var io: *c.ImGuiIO = @ptrCast(c.igGetIO());
        io.Fonts[0].TexID = null;

        dr.pipeline.release();
        dr.font_texture.release();
        dr.font_texture_view.release();
        dr.sampler.release();
        dr.uniforms.release();
        dr.common_bind_group.release();
        for (dr.image_bind_groups.values()) |x| x.release();
        dr.image_bind_group_layout.release();
        for (dr.frame_resources) |*frame_resources| frame_resources.release();

        dr.image_bind_groups.deinit(allocator);
        allocator.free(dr.frame_resources);
    }
};

const FrameResources = struct {
    index_buffer: ?*gpu.Buffer,
    vertex_buffer: ?*gpu.Buffer,
    indices: ?[]c.ImDrawIdx,
    vertices: ?[]c.ImDrawVert,
    index_buffer_size: usize,
    vertex_buffer_size: usize,

    pub fn release(fr: *FrameResources) void {
        if (fr.index_buffer) |x| x.release();
        if (fr.vertex_buffer) |x| x.release();
        if (fr.indices) |x| allocator.free(x);
        if (fr.vertices) |x| allocator.free(x);
    }
};
