const std = @import("std");
pub const Document = @import("tml/Document.zig");
pub const Parser = @import("tml/Parser.zig");
pub const Measure = @import("tml/Measure.zig");

const tokeniser = @import("toks");
pub const TmlTokeniser = tokeniser.Tokeniser(.{ .Symbols = Symbol });
pub const TmlAttrsTokeniser = tokeniser.Tokeniser(.{ .Symbols = AttrSymbol });


pub const Symbol = enum(u8) {
    // TODO: attribute parsing
    /// We open a new node. expect at least a text token (tag_name) after.
    def = '<',
    /// We push a new branch into the tree.
    push = '|',
    /// We close the last node
    pop = '>',
    /// !doctype html!
    meta = '!',
    /// #a comment#
    comment = '#',
};

pub const AttrSymbol = enum(u8) {
    eq = '=',
    class = '.',
    id = '#',
};

test {
    _ = @import("tml/Document.zig");
    _ = @import("tml/Parser.zig");
    _ = @import("tml/Measure.zig");
    _ = @import("Escaper.zig");
}

comptime {
    for (behaviour_test_cases) |bt| {
        const test_name, const sut, const expected_measure, const expected_doc, const expected_html = bt;
        _ = struct {
            const log = std.log.scoped(test_name);
            test {
                const alloc = std.testing.allocator;

                var actual_measure = Measure{};
                try actual_measure.measureTml(sut);

                try std.testing.expectEqualDeep(expected_measure, actual_measure);

                var builder: Parser = try .init(alloc, actual_measure);
                defer builder.deinit(alloc);

                _ = try builder.parse(sut);

                const doc: Document = .{
                    .attributes = builder.attrs.items,
                    .nodes = builder.nodes.items,
                    .top_level_node_count = builder.top_end orelse @intCast(builder.nodes.items.len),
                };

                docsEqual(expected_doc, doc) catch |err| {
                    log.err("expected:\n{f}\ngot:\n{f}", .{ expected_doc, doc });
                    return err;
                };

                const html = try std.fmt.allocPrint(alloc, "{f}", .{doc.html()});
                defer alloc.free(html);
                std.testing.expectEqualSlices(u8, expected_html, html) catch |err| {
                    log.err("expected:\n{s}\ngot:\n{s}", .{ expected_html, html });
                    return err;
                };
            }
        };
    }
}

const behaviour_test_cases: []const struct { @EnumLiteral(), []const u8, Measure, Document, []const u8 } = &.{
    .{
        .text_and_quote_string,
        \\this is a string of "tokens"
        ,
        .{
            .total_nodes = 1,
            .total_attributes = 0,
            .total_top_level_children = 0,
        },
        .{
            .attributes = &.{},
            .nodes = &.{
                Document.Node{
                    .kind = .text,
                    .content = "this is a string of \"tokens\"",
                },
            },
            .top_level_node_count = 1,
        },
        \\this is a string of tokens
        ,
    },
    .{
        .meta_and_comments,
        \\!doctype html!
        \\#a comment#
        ,
        .{
            .total_nodes = 2,
            .total_attributes = 0,
            .total_top_level_children = 0,
        },
        .{
            .attributes = &.{},
            .nodes = &.{
                Document.Node{
                    .kind = .meta,
                    .content = "doctype html",
                },
                Document.Node{
                    .kind = .comment,
                    .content = "a comment",
                },
            },
            .top_level_node_count = 2,
        },
        \\<!doctype html><--a comment-->
        ,
    },
    .{
        .empty_tag,
        \\<a|>
        ,
        .{
            .total_nodes = 1,
            .total_attributes = 0,
            .total_top_level_children = 1,
        },
        .{
            .attributes = &.{},
            .nodes = &.{
                Document.Node{
                    .kind = .tag,
                    .content = "a",
                    .children = .{ 1, 1 },
                },
            },
            .top_level_node_count = 1,
        },
        \\<a></a>
        ,
    },
    .{
        .nested_tags,
        \\<a href="/"|
        \\  <b|
        \\    Hello
        \\  >
        \\>
        ,
        .{
            .total_nodes = 3,
            .total_attributes = 1,
            .total_top_level_children = 2,
        },
        .{
            .attributes = &.{
                Document.Node.Attr{
                    .name = "href",
                    .value = "/",
                },
            },
            .nodes = &.{
                Document.Node{
                    .kind = .tag,
                    .content = "a",
                    .attrs = .{ 0, 1 },
                    .children = .{ 1, 2 },
                },
                Document.Node{
                    .kind = .tag,
                    .content = "b",
                    .children = .{ 2, 3 },
                },
                Document.Node{
                    .kind = .text,
                    .content = "Hello",
                },
            },
            .top_level_node_count = 1,
        },
        \\<a href="/"><b>Hello</b></a>
        ,
    },
    .{
        .differently_nested_tags,
        \\<a foo| Hello >
        \\<b bar>
        \\<c bar>
        ,
        .{
            .total_nodes = 4,
            .total_attributes = 3,
            .total_top_level_children = 1,
        },
        .{
            .attributes = &.{
                Document.Node.Attr{ .name = "foo" },
                Document.Node.Attr{ .name = "bar" },
                Document.Node.Attr{ .name = "bar" },
            },
            .nodes = &.{
                Document.Node{
                    .kind = .tag,
                    .content = "a",
                    .attrs = .{ 0, 1 },
                    .children = .{ 3, 4 },
                },
                Document.Node{
                    .kind = .tag,
                    .content = "b",
                    .attrs = .{ 1, 2 },
                },
                Document.Node{
                    .kind = .tag,
                    .content = "c",
                    .attrs = .{ 2, 3 },
                },
                Document.Node{
                    .kind = .text,
                    .content = "Hello",
                },
            },
            .top_level_node_count = 3,
        },
        \\<a foo>Hello</a><b bar><c bar>
        ,
    },
};

fn docsEqual(expected: Document, actual: Document) !void {
    try std.testing.expectEqual(expected.top_level_node_count, actual.top_level_node_count);
    for (expected.nodes, actual.nodes) |e, a| {
        try std.testing.expectEqualDeep(e, a);
    }
    for (expected.attributes, actual.attributes) |e, a| {
        try std.testing.expectEqualDeep(e, a);
    }
}
