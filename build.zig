const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const host_exe = addGl1(b, target, optimize, "gl1");
    b.installArtifact(host_exe);

    // Install glyph atlas next to the binary for runtime load.
    b.getInstallStep().dependOn(
        &b.addInstallFile(b.path("assets/fonts/glyphs-outline.bmp"), "bin/assets/fonts/glyphs-outline.bmp").step,
    );
    b.getInstallStep().dependOn(
        &b.addInstallFile(b.path("assets/icons/icons.png"), "bin/assets/icons/icons.png").step,
    );
    b.getInstallStep().dependOn(
        &b.addInstallFile(b.path("assets/icons/icons.yaml"), "bin/assets/icons/icons.yaml").step,
    );

    const run_cmd = b.addRunArtifact(host_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    // Run from zig-out/bin so relative assets/ paths resolve.
    run_cmd.setCwd(b.path("zig-out/bin"));
    const run_step = b.step("run", "Run gl1");
    run_step.dependOn(&run_cmd.step);

    // --- Cross-compile (build only; copy binaries to other machines to test) ---
    //   zig build windows        → zig-out/windows/gl1-windows.exe  (works from Linux)
    //   zig build macos-x64      → needs macOS SDK / frameworks (build on a Mac)
    //   zig build macos-arm64    → needs macOS SDK / frameworks (build on a Mac)
    // Sokol links AppKit/Metal/etc.; those frameworks are not present on Linux.
    addCrossStep(b, optimize, "windows", "gl1-windows", .{
        .cpu_arch = .x86_64,
        .os_tag = .windows,
    });
    addCrossStep(b, optimize, "macos-x64", "gl1-macos-x64", .{
        .cpu_arch = .x86_64,
        .os_tag = .macos,
    });
    addCrossStep(b, optimize, "macos-arm64", "gl1-macos-arm64", .{
        .cpu_arch = .aarch64,
        .os_tag = .macos,
    });
}

fn addGl1(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
) *std.Build.Step.Compile {
    const sokol_dep = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });

    const font_assets = b.createModule(.{
        .root_source_file = b.path("assets/fonts/embed.zig"),
        .target = target,
        .optimize = optimize,
    });
    const icon_assets = b.createModule(.{
        .root_source_file = b.path("assets/icons/embed.zig"),
        .target = target,
        .optimize = optimize,
    });

    return b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "sokol", .module = sokol_dep.module("sokol") },
                .{ .name = "font_assets", .module = font_assets },
                .{ .name = "icon_assets", .module = icon_assets },
            },
        }),
    });
}

fn addCrossStep(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    step_name: []const u8,
    exe_name: []const u8,
    query: std.Target.Query,
) void {
    const resolved = b.resolveTargetQuery(query);
    const exe = addGl1(b, resolved, optimize, exe_name);
    const install = b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{ .custom = step_name } },
    });
    const step = b.step(step_name, b.fmt("Cross-compile gl1 for {s}", .{step_name}));
    step.dependOn(&install.step);
}
