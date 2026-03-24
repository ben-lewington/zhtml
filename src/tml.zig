const std = @import("std");
pub const Document = @import("tml/Document.zig");
pub const Parser = @import("tml/Parser.zig");

const Slice = struct { u32, u32 };

pub const Node = struct {
    kind: Kind,
    content: []const u8,
    attrs: ?Slice = null,
    children: ?Slice = null,

    pub const Kind = enum(u8) {
        /// any string of alphanumeric, whitespace delimited tokens
        text,
        /// !doctype html!
        meta,
        /// # a comment #
        comment,
        /// <tag_name (attr="value")* | children >
        tag,
    };

    /// by deferring the parsing of child documents, we get the sibling nodes contiguous trivially.
    pub const Lazy = struct {
        parent_ix: u32,
        input: []const u8,
    };

    pub const Attr = struct {
        name: []const u8,
        value: ?[]const u8 = null,

        pub fn format(self: Attr, w: *std.Io.Writer) !void {
            try w.writeAll(self.name);
            if (self.value) |v| {
                try w.print("=\"{s}\"", .{v});
            }
        }
    };

    pub fn format(self: Node, w: *std.Io.Writer) !void {
        try w.print("[{}] {s} ", .{ self.kind, self.content });
        if (self.attrs) |as| {
            try w.print("{}-{}", as);
        }
        if (self.children) |cs| {
            try w.print("{}-{}", cs);
            try w.writeByte('>');
        }
        try w.writeByte('\n');
    }
};

test {
    _ = @import("tml/Document.zig");
    _ = @import("tml/Parser.zig");
}

// const testing = struct {
//     const esc = @import("escape.zig");
//     const iparser = @import("parser.zig");
//     const tokeniser = @import("tokeniser.zig");
//
//     comptime {
//         _ = esc;
//         _ = iparser;
//         _ = tokeniser;
//     }
//
//     const snapshot_tests: []const struct {
//         tag: @EnumLiteral(),
//         input: []const u8,
//         expected: []const u8,
//         args: struct { content: []const u8 = &.{} } = .{},
//     } = &.{
//         .{
//             .tag = .@"text node",
//             .input =
//             \\this is a string of tokens
//             ,
//             .expected =
//             \\this is a string of tokens
//             ,
//         },
//         .{
//             .tag = .@"meta and comments",
//             .input =
//             \\!DOCTYPE HTML!
//             \\#a comment#
//             ,
//             .expected =
//             \\<!DOCTYPE HTML><!--a comment-->
//             ,
//         },
//         .{
//             .tag = .@"simple tag",
//             .input =
//             \\<a|>
//             ,
//             .expected =
//             \\<a></a>
//             ,
//         },
//         .{
//             .tag = .@"nested tag",
//             .input =
//             \\<a href="/"|
//             \\    <b|
//             \\       Hello
//             \\    >
//             \\>
//             ,
//             .expected =
//             \\<a href="/"><b>Hello</b></a>
//             ,
//         },
//         .{
//             .tag = .advanced,
//             .input =
//             \\<a foo| Hello >
//             \\<b bar>
//             \\<c bar>
//             ,
//             .expected =
//             \\<a foo>Hello</a><b bar><c bar>
//             ,
//         },
//         .{
//             .tag = .interp_top_level,
//             .input =
//             \\@content
//             ,
//             .args = .{
//                 .content = "World",
//             },
//             .expected =
//             \\World
//             ,
//         },
//         .{
//             .tag = .interp_inside,
//             .input =
//             \\<a|@content>
//             ,
//             .args = .{
//                 .content = "World",
//             },
//             .expected =
//             \\<a>World</a>
//             ,
//         },
//     };
//
//     comptime {
//         for (snapshot_tests) |snapshot| {
//             _ = struct {
//                 const templ = Templ(snapshot.tag, snapshot.input);
//                 test {
//                     const alc = std.testing.allocator;
//                     std.log.debug("{s}", .{@tagName(snapshot.tag)});
//                     var out_buf = std.ArrayList(u8).init(alc);
//                     defer out_buf.deinit();
//                     const w = out_buf.writer();
//                     try templ.render(w, snapshot.args);
//                     const output = out_buf.items[0..out_buf.items.len];
//                     try std.testing.expectEqualSlices(u8, snapshot.expected, output);
//                 }
//             };
//         }
//     }
// };
