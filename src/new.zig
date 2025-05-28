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

pub fn Template(comptime id: Atom, comptime roots: []const Tree.Inner) type {
    return struct {
        pub const identifier = @tagName(id);
        pub fn render(writer: anytype) !void {
            inline for (roots) |node| {
                const inner = node.raw[0 .. node.attr_start orelse node.raw.len];
                switch (node.kind) {
                    .meta => try writer.print("<!{s}>", .{inner}),
                    .comment => try writer.print("<!--{s}-->", .{inner}),
                    .text => try writer.print("{s}", .{inner}),
                    .tag => {
                        try writer.print("<{s}>", .{node.raw});
                        if (node.branch) |child| {
                            try Template(id, child).render(writer);
                            try writer.print("</{s}>", .{inner});
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
    args: ?struct { content: []const u8 } = null,
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
        .tag = .interp,
        .input =
        \\<a foo @{.x}| @{ .content }>
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
        std.log.debug("{s}", .{@tagName(snapshot.tag)});
        var out_buf = std.ArrayList(u8).init(alc);
        defer out_buf.deinit();
        const w = out_buf.writer();
        try Template(snapshot.tag, ir.root).render(w);
        const output = out_buf.items[0..out_buf.items.len];
        try std.testing.expectEqualSlices(u8, snapshot.expected, output);
    }
}
