const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sokol_dep = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });

    // Font atlas lives only under assets/fonts/ — exposed as a tiny Zig module
    // so @embedFile stays inside that package path (not duplicated under src/).
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

    const exe = b.addExecutable(.{
        .name = "gl1",
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

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    // Run from zig-out/bin so relative assets/ paths resolve.
    run_cmd.setCwd(b.path("zig-out/bin"));
    // Extra CLI args: `zig build run -- --scene triangle`
    // (Step.Run picks up trailing args from the build runner when present.)
    const run_step = b.step("run", "Run gl1");
    run_step.dependOn(&run_cmd.step);
}
