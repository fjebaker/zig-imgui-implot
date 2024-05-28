# ImGui and ImPlot bindings for Zig and Mach

This project provides bindings to ImGui (with docking) and ImPlot to Zig with a Mach backend. This packages also exposes a utility function to make ImGui use a Zig allocator.

- [Dear Imgui](https://github.com/ocornut/imgui), and the [cimgui bindings](https://github.com/cimgui/cimgui) used.
- [ImPlot](https://github.com/epezent/implot), and the [cimplot bindings](https://github.com/cimgui/cimplot) used.
- [Mach](https://machengine.org/), with the ImGui mach backend modified from [foxnne/zig-imgui](https://github.com/foxnne/zig-imgui).

This project directly exposes the `cimgui` and `cimplot` C API to the user. By using these it is easier for the wrapper to keep up to date with the latest versions of both ImGui and ImPlot.

```zig
const imgui = @import("zig-imgui");

// ...
_ = imgui.igCreateContext(null);
_ = imgui.ImPlot_CreateContext();
// ...
```

## Example

See the [project template](https://github.com/fjebaker/zig-imgui-implot-template) as an example.

## Using in a project

- **Requires 0.12.0-dev.3180+83e578a18**

Use the Zig package manager to fetch this dependency. Ideally use a specific commit hash, but for illustration we take the main branch:

```bash
zig fetch --save=zigimgui https://github.com/fjebaker/zig-imgui-implot/archive/main.tar.gz
```

Then, in your `build.zig`:

```zig
// Get the mach core dependency
const mach_dep = b.dependency("mach", .{
    .target = target,
    .optimize = optimize,
    // Since we're only using @import("mach").core, we can specify this to avoid
    // pulling in unneccessary dependencies.
    .core = true,
});

// Get this dependency
const zig_imgui_dep = b.dependency(
    "zigimgui",
    .{ .target = target, .optimize = optimize },
);

const imgui_module = zig_imgui_dep.module("zig-imgui");
// Need to give the same mach module to the bindings
imgui_module.addImport("mach", mach_dep.module("mach"));

// Add to your app
const app = try mach.CoreApp.init(b, mach_dep.builder, .{
    .name = "zfv",
    .src = "src/main.zig",
    .target = target,
    .optimize = optimize,
    .mach_mod = mach_dep.module("mach"),
    .deps = &.{
        // Here is the important line
        .{ .name = "zig-imgui", .module = imgui_module },
    },
});
```

If you **do not want to use the mach backend** you can also access the static libraries for ImGui and ImPlot with
```zig
const imgui_lib = zig_imgui_dep.artifact("imgui");
const implot_lib = zig_imgui_dep.artifact("implot");
const include_path = zig_imgui_dep.path("src");
```
