const std = @import("std");
const HtmlParser = @import("parser.zig");
const Buffer = @import("big_enough.zig").Buffer;
const mem = std.mem;
const assert = std.debug.assert;
const str = []const u8;
const Tokeniser = @import("tokeniser.zig").Tokeniser;

fn strn(comptime len: comptime_int) type {
    return [len]u8;
}

const t = @import("tokeniser.zig");

pub fn main() !void {
    const zhtml =
        // \\abc "foo  bar   baz"    qux
        // \\abc "foo  bar  baz" aaaa
        \\<a-simple-tag { foo bar baz }
    ;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alc = gpa.allocator();

    const nodes = try alc.alloc(HtmlParser.Node, 1024);
    defer alc.free(nodes);

    const parent_stack = try alc.alloc(*HtmlParser.Node, 50);
    defer alc.free(parent_stack);

    const strs = try alc.alloc(u8, 1024);
    defer alc.free(strs);

    var parser = HtmlParser.init(zhtml, strs, nodes, parent_stack);

    var node = try parser.parseNode();
    while (node != null) : (node = try parser.parseNode()) {}

    for (parser.nodes.inner[0..parser.nodes.len]) |n| {

        // std.debug.print("node[{s}]: <{s}>\n", .{
        //     @tagName(n.data),
        //     n.data.node.tag,
        // });

        var depth: usize = 0;
        var pn = n.parent;
        while (pn) |p| {
            // const tmp = p.*;

            depth += 1;
            pn = p.parent;
        }
    }

    std.debug.print("d", .{});
}

fn render(nodes: []const HtmlParser.Node, output: *Buffer(u8), current_parent: ?*HtmlParser.Node) !void {
    for (nodes) |*node| {
        if (node.parent != current_parent) continue;
        switch (node.data) {
            .literal => |l| output.extend(l),
            .node => |n| {
                output.push('<');
                output.extend(n.tag);
                output.push('>');
                try render(nodes, output, @constCast(node));
                defer {
                    output.push('<');
                    output.push('/');
                    output.extend(n.tag);
                    output.push('>');
                }
            },
        }
    }
}

fn testHtml(comptime buf_size: comptime_int, comptime input: str, comptime expected: str) !void {
    var alc = std.testing.allocator;
    const nodes = try alc.alloc(HtmlParser.Node, buf_size);
    defer alc.free(nodes);

    const parent_stack = try alc.alloc(*HtmlParser.Node, buf_size);
    defer alc.free(parent_stack);

    const strs = try alc.alloc(u8, buf_size);
    defer alc.free(strs);

    var parser = HtmlParser.init(input, strs, nodes, parent_stack);

    var node = try parser.parseNode();
    while (node != null) : (node = try parser.parseNode()) {}

    var result = Buffer(u8).init(try alc.alloc(u8, buf_size));
    defer alc.free(result.inner);
    try render(parser.nodes.inner[0..parser.nodes.len], &result, null);
    try std.testing.expectEqualSlices(u8, expected, result.inner[0..result.len]);
}

test "literals" {
    try testHtml(50, "Hello\n   World", "Hello World");
    try testHtml(50, "Hello\r\n   \t\t       World", "Hello World");
    try testHtml(50, "\"foo  bar\"", "foo  bar");
    try testHtml(50, "abc \"foo  bar   baz\"    qux", "abc foo  bar   baz qux");
    try testHtml(50, "123 456 ;;;", "123 456 ;;;");
    try testHtml(50, "<a-simple-tag { foo bar baz }", "<a-simple-tag>foo bar baz</a-simple-tag>");
    try testHtml(50, "<a-simple-tag|", "<a-simple-tag/>");
}

// test "current full featureset test" {
//     const alc = std.testing.allocator;
//     const example_html =
//         \\<a <
//         \\  b <c foo=1 <
//         \\   'true '0 <d |
//         \\  >
//         \\>
//     ;
//     const expected =
//         \\<a><b><c foo="1">true 0 <d></c></b></a>
//     ;
//     const res = try render_as_html(alc, example_html);
//     try std.testing.expectEqualSlices(u8, expected, res);
// }
