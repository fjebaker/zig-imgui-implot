const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // const use_freetype = b.option(bool, "use_freetype", "Use Freetype") orelse false;

    // const mach_dep = b.dependency("mach", .{
    //     .target = target,
    //     .optimize = optimize,
    // });
    const imgui_dep = b.dependency("imgui", .{
        .target = target,
        .optimize = optimize,
    });
    const implot_dep = b.dependency("implot", .{
        .target = target,
        .optimize = optimize,
    });

    const imgui_lib = b.addStaticLibrary(.{
        .name = "imgui",
        .target = target,
        .optimize = optimize,
    });
    imgui_lib.linkLibC();
    imgui_lib.addIncludePath(.{ .path = "src" });
    imgui_lib.addIncludePath(imgui_dep.path("."));
    imgui_lib.addCSourceFiles(.{ .root = imgui_dep.path("."), .files = &.{
        "imgui.cpp",      "imgui_widgets.cpp", "imgui_tables.cpp",
        "imgui_draw.cpp", "imgui_demo.cpp",
    } });
    imgui_lib.addCSourceFiles(.{ .files = &.{
        "src/cimgui.cpp",
    } });

    b.installArtifact(imgui_lib);

    const implot_lib = b.addStaticLibrary(.{
        .name = "implot",
        .target = target,
        .optimize = optimize,
    });
    implot_lib.linkLibC();
    implot_lib.addIncludePath(imgui_dep.path("."));
    implot_lib.addIncludePath(implot_dep.path("."));
    implot_lib.addCSourceFiles(.{ .root = implot_dep.path("."), .files = &.{
        "implot.cpp", "implot_items.cpp",
    } });
    implot_lib.addIncludePath(.{ .path = "src" });
    implot_lib.addCSourceFiles(.{ .files = &.{
        "src/cimplot.cpp",
    } });

    b.installArtifact(implot_lib);

    const mod = b.addModule("zig-imgui", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .path = "src/imgui_wrapper.zig" },
    });
    mod.linkLibrary(imgui_lib);
    mod.linkLibrary(implot_lib);
    mod.addIncludePath(.{ .path = "src" });
}
