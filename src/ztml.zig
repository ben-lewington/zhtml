const std = @import("std");
const tokeniser = @import("toks");

pub const Document = @import("ztml/Document.zig");
pub const Measure = @import("ztml/Measure.zig");
pub const Parser = @import("ztml/Parser.zig");

test {
    _ = @import("ztml/Document.zig");
    _ = @import("ztml/Measure.zig");
    _ = @import("ztml/Parser.zig");
}

pub const templ: Engine = .initComptime(.{
    .ui = .{
        .button =
        \\<div|
        \\  @inner@
        \\>
        ,
    },
    .layout =
    \\<html|@inner@>
    ,
    .homepage =
    \\<main|Hello>
    ,
});

pub fn Templ(comptime ztml: []const u8)

pub const Engine = struct {
    names: []const []const u8,

    pub fn initComptime(comptime init_args: anytype) Engine {
        const ti = @typeInfo(@TypeOf(init_args)).@"struct";
        _ = ti;
        return .{
            .names = &.{},
        };
    }

    pub fn Template(
        comptime self: *const Engine,
        comptime lookup: @EnumLiteral(),
        comptime link: @EnumLiteral(),
    ) type {
        _ = self;
        _ = lookup;
        _ = link;
        return struct {};
    }
};

pub fn isEngineLike(comptime info: std.builtin.Type) void {
    const ti = @typeInfo(info).@"struct";
    inline for (ti.fields) |tf| {
        const tfi: std.builtin.Type = @typeInfo(tf.type);
        switch (tfi) {
            .pointer => |p| {
                if (p.size != .slice) @compileError("hello");
                if (p.child != u8) @compileError("hello");
            },
            .@"struct" => isEngineLike(tfi),
            inline else => |i| {
                _ = i;
            },
        }
    }
}

pub fn isRenderable(comptime info: std.builtin.Type) void {
    _ = info;
}

pub fn isFormattable(comptime info: std.builtin.Type) void {
    _ = info;
}

pub fn isSplattable(comptime info: std.builtin.Type) void {
    _ = info;
}

test {
    _ = templ;
}
