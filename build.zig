const std = @import("std");
const Translator = @import("translate_c").Translator;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseFast,
    });
    const translate_c = b.dependency("translate_c", .{});
    const atspi = Translator.init(translate_c, .{
        .c_source_file = b.path("include/atspi.h"),
        .target = target,
        .optimize = optimize,
        .link_system_libs = &.{
            .{ .name = "atspi-2" },
            .{ .name = "X11" },
        },
    });
    const gtk = Translator.init(translate_c, .{
        .c_source_file = b.path("include/gtk.h"),
        .target = target,
        .optimize = optimize,
        .link_system_libs = &.{
            .{ .name = "gtk+-3.0" },
        },
    });
    const log = Translator.init(translate_c, .{
        .c_source_file = b.path("include/log.h"),
        .target = target,
        .optimize = optimize,
        .link_system_libs = &.{
            .{ .name = "libnotify" },
        },
    });
    const uinput = Translator.init(translate_c, .{
        .c_source_file = b.path("include/uinput.h"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "MouselessDesktop",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "atspi",
                    .module = atspi.mod,
                },
                .{
                    .name = "gtk",
                    .module = gtk.mod,
                },
                .{
                    .name = "log",
                    .module = log.mod,
                },
                .{
                    .name = "uinput",
                    .module = uinput.mod,
                },
            },
        }),
    });
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
