// ws := [' ' | '\n' | '\r' | '\t']
//
// symbols := {
//     def := '<'
//     push := '|'
//     pinch := ';'
//     pop := '>'
// }
//
// ident := [a-zA-Z0-9][a-zA-Z0-9-_]*
// literal := ".*"
//
// shorthand := {
//     class := '.'
//     id := '#'
// }
//
// markup :=
//     ([ident | literal] ws)*                                                          // text
//   | symbols.def '!' ([ident | literal] ws)* symbols.pinch                            // meta
//   | symbols.def '!' '-' ws ([ident | literal] ws)* symbols.pinch                     // comment
//   | symbols.def ident ([ident | ident '=' literal])* symbols.push markup symbols.pop // tag
const std = @import("std");
const log = std.log.scoped(.tml);
const Tokeniser = @import("tokeniser.zig").Tokeniser;
const Allocator = std.mem.Allocator;
const parser = @import("parser.zig");
const Tree = parser.Tree;
const Atom = @TypeOf(.atom);

fn countInterp(roots: []const Tree.Inner) usize {
    var ix = 0;
    for (roots) |node| {
        switch (node.kind) {
            .interp => ix += 1,
            .tag => if (node.branch) |children| {
                ix += countInterp(children);
            },
            else => {},
        }
    }
    return ix;
}

fn captureInterps(roots: []const Tree.Inner, out: [][:0]const u8, ix: *usize) void {
    for (roots) |node| {
        switch (node.kind) {
            .interp => {
                out[ix.*] = node.raw ++ "";
                ix.* += 1;
            },
            .tag => if (node.branch) |children| captureInterps(children, out, ix),
            else => {},
        }
    }
}

pub const TmplProto = struct {
    id: []const u8 = "",
    ir: Tree = .{ .root = &.{}, .interps = &.{} },
};

pub fn Templ(comptime id: Atom, comptime template: []const u8) !type {
    const tree = try parser.parseTree(template);

    return struct {
        const Templ = @This();
        pub const this = TmplProto{
            .id = @tagName(id),
            .ir = tree,
        };
        const interp = countInterp(tree.root);

        const interp_args: []const []const u8 = b: {
            var out: [interp][:0]const u8 = undefined;
            var ix: usize = 0;
            captureInterps(tree.root, &out, &ix);
            const iargs = out[0..interp].*;
            break :b &iargs;
        };

        const LinkArgs: type = b: {
            const fields: []const std.builtin.Type.StructField = l: {
                var out: [interp]std.builtin.Type.StructField = undefined;
                for (interp_args, 0..) |a, i| {
                    out[i] = std.builtin.Type.StructField{
                        .name = a,
                        .type = TmplProto,
                        .is_comptime = true,
                        .alignment = @alignOf(TmplProto),
                        .default_value_ptr = null,
                    };
                }
                const iargs = out[0..interp].*;
                break :l &iargs;
            };
            _ = fields;

            break :b struct {};
        };

        pub fn render(writer: anytype, args: anytype) !void {
            const ti = switch (@typeInfo(@TypeOf(args))) {
                .@"struct" => |s| s.fields,
                else => |t| @compileError(std.fmt.comptimePrint(
                    "template[{s}]: args type `{s}` is not supported",
                    .{ @tagName(id), @tagName(t) },
                )),
            };
            comptime {
                for (interp_args) |a| {
                    var found: bool = false;
                    for (ti) |f| {
                        if (std.mem.eql(u8, a, f.name)) found = true;
                    }
                    if (!found) {
                        @compileError(std.fmt.comptimePrint(
                            "template[{s}]: argument `{s}` expected as a field to args",
                            .{ @tagName(id), a },
                        ));
                    }
                }
            }
            try renderNodes(tree.root, writer, args);
        }

        fn renderNodes(comptime nodes: []const Tree.Inner, writer: anytype, args: anytype) !void {
            inline for (nodes) |node| {
                const inner = node.raw[0 .. node.attr_start orelse node.raw.len];
                switch (node.kind) {
                    .meta => try writer.print("<!{s}>", .{inner}),
                    .comment => try writer.print("<!--{s}-->", .{inner}),
                    .text => try writer.print("{s}", .{inner}),
                    .tag => {
                        try writer.print("<{s}>", .{node.raw});
                        if (node.branch) |child| {
                            try renderNodes(child, writer, args);
                            try writer.print("</{s}>", .{inner});
                        }
                    },
                    .interp => {
                        const value = @field(args, node.raw);
                        const vti: std.builtin.Type = @typeInfo(@TypeOf(value));
                        switch (vti) {
                            .comptime_int, .int, .float, .comptime_float => try writer.print("{d}", .{value}),
                            .bool => try writer.print("{}", .{value}),
                            .pointer => |p| {
                                switch (p.size) {
                                    .slice => try writer.print("{s}", .{value}),
                                    .one, .many, .c => unreachable,
                                }
                            },
                            else => |t| @compileError(std.fmt.comptimePrint(
                                "template[{s}]: field `{s}`:  argument type `{s}` not supported",
                                .{ @tagName(id), node.raw, @tagName(t) },
                            )),
                        }
                    },
                }
            }
        }
    };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const templ = comptime Templ(
        .interp,
        \\<a|The content is @content@bar>
        ,
    ) catch unreachable;

    const stdout = std.io.getStdOut().writer();
    const foo: []const u8 = "foo";
    _ = foo;
    try templ.render(stdout, .{ .content = true, .bar = 3 });
    _ = try stdout.write("\n");
}

const testing = struct {
    const esc = @import("escape.zig");
    const lib = @import("new.zig");
    const iparser = @import("parser.zig");
    const tokeniser = @import("tokeniser.zig");

    comptime {
        _ = esc;
        _ = lib;
        _ = iparser;
        _ = tokeniser;
    }

    const snapshot_tests: []const struct {
        tag: Atom,
        input: []const u8,
        expected: []const u8,
        args: struct { content: []const u8 = &.{} } = .{},
    } = &.{
        .{
            .tag = .@"text node",
            .input =
            \\this is a string of tokens
            ,
            .expected =
            \\this is a string of tokens
            ,
        },
        .{
            .tag = .@"meta and comments",
            .input =
            \\!DOCTYPE HTML!
            \\#a comment#
            ,
            .expected =
            \\<!DOCTYPE HTML><!--a comment-->
            ,
        },
        .{
            .tag = .@"simple tag",
            .input =
            \\<a|>
            ,
            .expected =
            \\<a></a>
            ,
        },
        .{
            .tag = .@"nested tag",
            .input =
            \\<a href="/"|
            \\    <b|
            \\       Hello
            \\    >
            \\>
            ,
            .expected =
            \\<a href="/"><b>Hello</b></a>
            ,
        },
        .{
            .tag = .advanced,
            .input =
            \\<a foo| Hello >
            \\<b bar>
            \\<c bar>
            ,
            .expected =
            \\<a foo>Hello</a><b bar><c bar>
            ,
        },
        .{
            .tag = .interp_top_level,
            .input =
            \\@content
            ,
            .args = .{
                .content = "World",
            },
            .expected =
            \\World
            ,
        },
        .{
            .tag = .interp_inside,
            .input =
            \\<a|@content>
            ,
            .args = .{
                .content = "World",
            },
            .expected =
            \\<a>World</a>
            ,
        },
    };

    comptime {
        for (snapshot_tests) |snapshot| {
            _ = struct {
                const templ = Templ(snapshot.tag, snapshot.input);
                test {
                    const alc = std.testing.allocator;
                    std.log.debug("{s}", .{@tagName(snapshot.tag)});
                    var out_buf = std.ArrayList(u8).init(alc);
                    defer out_buf.deinit();
                    const w = out_buf.writer();
                    try templ.render(w, snapshot.args);
                    const output = out_buf.items[0..out_buf.items.len];
                    try std.testing.expectEqualSlices(u8, snapshot.expected, output);
                }
            };
        }
    }
};
