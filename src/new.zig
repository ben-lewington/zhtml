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
//     ([ident | literal] ws)* // text node
//   | symbols.def '!' ([ident | literal] ws)* symbols.pinch        // meta node
//   | symbols.def '!' '-' ws ([ident | literal] ws)* symbols.pinch // comment
//   | symbols.def ident ([ident | ident '=' literal])* symbols.push markup symbols.pop // actual
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

fn captureInterps(roots: []const Tree.Inner, out: [][]const u8, ix: *usize) void {
    for (roots) |node| {
        switch (node.kind) {
            .interp => {
                out[ix.*] = node.raw;
                ix.* += 1;
            },
            .tag => if (node.branch) |children| captureInterps(children, out, ix),
            else => {},
        }
    }
}

pub fn Template(comptime id: Atom, comptime roots: []const Tree.Inner) type {
    const interp = countInterp(roots);

    const interp_args: []const []const u8 = b: {
        var out: [interp][]const u8 = undefined;
        var ix: usize = 0;
        captureInterps(roots, &out, &ix);
        const iargs = out[0..interp].*;
        break :b &iargs;
    };

    return struct {
        pub const identifier = @tagName(id);
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

            inline for (roots) |node| {
                const inner = node.raw[0 .. node.attr_start orelse node.raw.len];
                switch (node.kind) {
                    .meta => try writer.print("<!{s}>", .{inner}),
                    .comment => try writer.print("<!--{s}-->", .{inner}),
                    .text => try writer.print("{s}", .{inner}),
                    .tag => {
                        try writer.print("<{s}>", .{node.raw});
                        if (node.branch) |child| {
                            try Template(id, child).render(writer, .{});
                            try writer.print("</{s}>", .{inner});
                        }
                    },
                    .interp => try writer.print("{s}", .{@field(args, node.raw)}),
                }
            }
        }
    };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const ir = comptime parser.parseTopNodeComptime(snapshot_tests[5].input) catch unreachable;
    for (ir) |n| {
        std.log.debug("{}", .{n});
    }
    const templ = Template(.interp, ir);

    const stdout = std.io.getStdOut().writer();
    try templ.render(stdout);
    _ = try stdout.write("\n");
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
};

test "snapshot" {
    const alc = std.testing.allocator;

    const generated_ir: []const Tree = comptime b: {
        var outs: [snapshot_tests.len]Tree = undefined;
        for (snapshot_tests, 0..) |snapshot, i| {
            outs[i] = .{ .root = parser.parseTopNodeComptime(snapshot.input) catch unreachable };
        }
        const os = outs[0..snapshot_tests.len].*;
        break :b &os;
    };

    inline for (snapshot_tests, generated_ir) |snapshot, ir| {
        std.log.debug("{s}", .{@tagName(snapshot.tag)});
        var out_buf = std.ArrayList(u8).init(alc);
        defer out_buf.deinit();
        const w = out_buf.writer();
        try Template(snapshot.tag, ir.root).render(w, snapshot.args);
        const output = out_buf.items[0..out_buf.items.len];
        try std.testing.expectEqualSlices(u8, snapshot.expected, output);
    }
}
