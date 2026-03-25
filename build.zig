const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const tokeniser = b.createModule(.{
        .root_source_file = b.path("src/tokeniser.zig"),
        .target = target,
        .imports = &.{},
    });

    const tml = b.createModule(.{
        .root_source_file = b.path("src/tml.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "toks", .module = tokeniser },
        },
    });

    const ztml = b.createModule(.{
        .root_source_file = b.path("src/ztml.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "toks", .module = tokeniser },
        },
    });

    const tml_exe = b.addExecutable(.{
        .name = "ztml",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bin/tml.zig"),
            .target = target,
            .imports = &.{
                .{ .name = "tml", .module = tml },
                .{ .name = "toks", .module = tokeniser },
            },
        }),
    });
    b.installArtifact(tml_exe);

    const run_cmd = b.addRunArtifact(tml_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");

    inline for (&.{tml, ztml, tokeniser}) |mod| {
        const unit_tests = b.addTest(.{ .root_module = mod });
        const run_unit_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_unit_tests.step);
    }
}
