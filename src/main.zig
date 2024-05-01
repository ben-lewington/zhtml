const std = @import("std");

const HtmlParser = @import("parser.zig");
const big_enough = @import("big_enough.zig");

const Buffer = big_enough.Buffer;
const mem = std.mem;
const assert = std.debug.assert;
const str = []const u8;

fn strn(comptime len: comptime_int) type {
    return [len]u8;
}

pub fn main() !void {
    const zhtml =
        \\<div a="foo" bar c="baz" qux {}
        // \\<a-simple-tag { foo bar baz }
    ;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alc = gpa.allocator();

    const nodes = try alc.alloc(HtmlParser.Node, 1024);
    defer alc.free(nodes);

    const attrs = try alc.alloc(HtmlParser.NodeAttrs, 1024);
    defer alc.free(attrs);

    const parent_stack = try alc.alloc(*HtmlParser.Node, 50);
    defer alc.free(parent_stack);

    const strs = try alc.alloc(u8, 1024);
    defer alc.free(strs);

    const o = try alc.alloc(u8, 1024);
    defer alc.free(o);

    var parser = HtmlParser.init(zhtml, strs, nodes, attrs, parent_stack);

    var node = try parser.parseNode();
    while (node != null) : (node = try parser.parseNode()) {}

    var ob = Buffer(u8).init(o);
    render(nodes, &ob, null);

    std.log.debug("{s}", .{ob.inner[0..ob.len]});
}

fn render(nodes: []const HtmlParser.Node, output: *Buffer(u8), current_parent: ?*HtmlParser.Node) void {
    for (nodes) |*node| {
        if (node.parent != current_parent) continue;
        switch (node.data) {
            .literal => |l| output.extend(l),
            .node => |n| {
                output.push('<');
                output.extend(n.tag);
                if (n.attrs) |as| {
                    output.push(' ');
                    for (as) |a| {
                        output.extend(a.key);
                        output.extend("=\"");
                        output.extend(a.value orelse "");
                        output.extend("\" ");
                    }
                    if (as.len > 0) output.len -= 1;
                }

                if (n.self_closing) {
                    output.extend("/>");
                    continue;
                }
                output.push('>');
                render(nodes, output, @constCast(node));
                output.extend("</");
                output.extend(n.tag);
                output.push('>');
            },
        }
    }
}

fn testHtml(comptime buf_size: comptime_int, comptime input: str, comptime expected: str) !void {
    var alc = std.testing.allocator;
    const nodes = try alc.alloc(HtmlParser.Node, buf_size);
    defer alc.free(nodes);

    const node_attrs = try alc.alloc(HtmlParser.NodeAttrs, buf_size);
    defer alc.free(node_attrs);

    const parent_stack = try alc.alloc(*HtmlParser.Node, buf_size);
    defer alc.free(parent_stack);

    const strs = try alc.alloc(u8, buf_size);
    defer alc.free(strs);

    var parser = HtmlParser.init(input, strs, nodes, node_attrs, parent_stack);

    var node = try parser.parseNode();
    while (node != null) : (node = try parser.parseNode()) {}

    var result = Buffer(u8).init(try alc.alloc(u8, buf_size));
    defer alc.free(result.inner);
    render(parser.nodes.inner[0..parser.nodes.len], &result, null);
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
    try testHtml(
        500,
        "<a-simple-tag { foo bar baz <anuzza_tag { boo } }",
        "<a-simple-tag>foo bar baz<anuzza_tag>boo</anuzza_tag></a-simple-tag>",
    );
    try testHtml(
        500,
        \\<div a="foo"      bar c="baz" qux {}
    ,
        \\<div a="foo" bar="" c="baz" qux=""></div>
        ,
    );
}
