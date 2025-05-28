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

pub fn Markup(comptime roots: []const Tree.Inner) type {
    return struct {
        pub fn render(writer: anytype) !void {
            inline for (roots) |node| {
                switch (node.kind) {
                    .meta => try writer.print("<!{s}>", .{node.raw}),
                    .comment => try writer.print("<!--{s}-->", .{node.raw}),
                    .text => try writer.print("{s}", .{node.raw}),
                    .tag => {
                        try writer.print("<{s}>", .{node.raw});
                        if (node.branch) |child| {
                            try Markup(child).render(writer);
                            try writer.print("</{s}>", .{node.raw[0 .. node.attr_start orelse node.raw.len]});
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

    const ir = comptime parser.parseTopNodeComptime(snapshot_tests[4].input) catch unreachable;
    const templ = Markup(ir);

    const stdout = std.io.getStdOut().writer();
    try templ.render(stdout);
    _ = try stdout.write("\n");
}

const snapshot_tests: []const struct {
    tag: []const u8,
    input: []const u8,
    expected: []const u8,
    args: ?struct { content: []const u8 } = null,
} = &.{
    .{
        .tag = "text node",
        .input =
        \\this is a string of tokens
        ,
        .expected =
        \\this is a string of tokens
        ,
    },
    .{
        .tag = "meta and comments",
        .input =
        \\!DOCTYPE HTML!
        \\#a comment#
        ,
        .expected =
        \\<!DOCTYPE HTML><!--a comment-->
        ,
    },
    .{
        .tag = "simple tag",
        .input =
        \\<a|>
        ,
        .expected =
        \\<a></a>
        ,
    },
    .{
        .tag = "nested tag",
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
        .tag = "advanced",
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
        .tag = "interp",
        .input =
        \\<a foo| @{ .content }>
        ,
        .args = .{
            .content = "World",
        },
        .expected =
        \\<a foo>World</a>
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
        var out_buf = std.ArrayList(u8).init(alc);
        defer out_buf.deinit();
        const w = out_buf.writer();
        try Markup(ir.root).render(w);
        const output = out_buf.items[0..out_buf.items.len];
        try std.testing.expectEqualSlices(u8, snapshot.expected, output);
    }
}
