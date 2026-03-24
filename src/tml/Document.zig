const std = @import("std");
const Parser = @import("Parser.zig");
const Node = @import("../tml.zig").Node;
const TmlParser = @This();
const Symbol = Parser.Symbol;
const AttrSymbol = Parser.AttrSymbol;
const Tokeniser = Parser.Tokeniser;
const AttrsTokeniser = Parser.AttrsTokeniser;
const Document = @This();
const Measure = @import("Measure.zig");

/// an unowned slice. backing memory is owned by the Parser (and it's slices by the input)
attributes: []const Node.Attr,
/// an unowned slice. backing memory is owned by the Parser (and it's slices by the input)
nodes: []const Node,
top_level_node_count: u32,

pub fn initComptime(comptime input: []const u8) !Document {
    @setEvalBranchQuota(1_000_000);

    const specs = comptime b: {
        var sp = Document.Measure{};
        try sp.measureTml(input);
        break :b sp;
    };
    var nodes: [specs.total_nodes]Node = undefined;
    var attrs: [specs.total_attributes]Node.Attr = undefined;
    var children: [specs.total_top_level_children]Node.Lazy = undefined;

    var parser = Parser{
        .nodes = .initBuffer(&nodes),
        .attrs = .initBuffer(&attrs),
        .children = .initBuffer(&children),
    };

    _ = try parser.parse(input);

    // const te = parser.top_end.?;
    const ncopy = nodes;
    const acopy = attrs;
    const tc = parser.top_end orelse specs.total_nodes;

    return .{
        .nodes = &ncopy,
        .attributes = &acopy,
        .top_level_node_count = tc,
    };
}


pub fn html(self: *const Document) struct {
    inner: *const Document,


    pub fn format(this: @This(), w: *std.Io.Writer) !void {
        try this.inner.writeHtml(w);
    }
} {
    return .{ .inner = self };
}

pub fn writeHtml(self: *const Document, w: *std.Io.Writer) !void {
    for (self.nodes[0..self.top_level_node_count]) |n| {
        try self.writeHtmlDocumentNode(n, w);
    }
}

fn writeHtmlDocumentNode(self: *const Document, node: Node, w: *std.Io.Writer) !void {
    switch (node.kind) {
        .meta => {
            // FIXME: escape??
            try w.print("<!{s}>", .{ node.content });
        },
        .comment => {
            // FIXME: escape??
            try w.print("<--{s}-->", .{ node.content });
        },
        .text => {
            var texttoks = @import("toks").Tokeniser(.{}) { .input = node.content };
            var peek = texttoks.peekNextTok();
            var thr: []const u8 = "";
            tokens: switch (peek.tok.kind) {
                .token => {
                    // FIXME: escape
                    try w.print("{s}{s}", .{ thr, peek.tok.raw });
                    thr = " ";
                    texttoks.current = peek.chop;
                    peek = texttoks.peekNextTok();
                    continue :tokens peek.tok.kind;
                },
                .quote => {
                    // FIXME: escape
                    try w.print("{s}{s}", .{ thr, peek.tok.raw[1..peek.tok.raw.len - 1] });
                    thr = " ";
                    texttoks.current = peek.chop;
                    peek = texttoks.peekNextTok();
                    continue :tokens peek.tok.kind;
                },
                .symbol => unreachable,
                .eof => break :tokens,
            }
        },
        .tag => {
            const tag_name = node.content;
            try w.print("<{s}", .{tag_name});
            if (node.attrs) |na| {
                for (self.attributes[na.@"0"..na.@"1"]) |a| {
                    try w.print(" {s}", .{ a.name });
                    if (a.value) |v| {
                        try w.print("=\"{s}\"", .{ v });
                    }
                }
            }
            _ = try w.write(">");
            if (node.children) |c| {
                for (self.nodes[c.@"0"..c.@"1"]) |cn| {
                    try self.writeHtmlDocumentNode(cn, w);
                }
                try w.print("</{s}>", .{tag_name});
            }
        },
    }
    try w.flush();
}

pub fn format(self: Document, w: *std.Io.Writer) !void {
    for (self.nodes[0..self.top_level_node_count]) |n| {
        try w.print("[{}] {s} ", .{ n.kind, n.content });
        if (n.attrs) |as| {
            var thr: []const u8 = "";
            for (self.attributes[as.@"0"..as.@"1"]) |a| {
                try w.print("{s}{s}", .{thr, a.name});
                thr = " ";
                if (a.value) |v| {
                    try w.print("=\"{s}\"", .{ v });
                }
            }
            try w.writeByte('\n');
        }
        if (n.children) |cs| {
            for (self.nodes[cs.@"0"..cs.@"1"]) |c| {
                try w.print("  [{}] {s} ...\n", .{ c.kind, c.content });
            }
        }
    }
}

// Tests for Measure
const testing = std.testing;

test "Measure: count single text node" {
    var specs: Measure = .{};
    try specs.measureTml("hello world");
    try testing.expectEqual(@as(u32, 1), specs.total_nodes);
    try testing.expectEqual(@as(u32, 0), specs.total_attributes);
    try testing.expectEqual(@as(u32, 0), specs.total_top_level_children);
}

test "Measure: count multiple text nodes" {
    var specs: Measure = .{};
    try specs.measureTml("hello world foo bar");
    try testing.expectEqual(@as(u32, 1), specs.total_nodes);
    try testing.expectEqual(@as(u32, 0), specs.total_attributes);
    try testing.expectEqual(@as(u32, 0), specs.total_top_level_children);
}

test "Measure: count simple tag without children" {
    var specs: Measure = .{};
    try specs.measureTml("<div>");
    try testing.expectEqual(@as(u32, 1), specs.total_nodes);
    try testing.expectEqual(@as(u32, 0), specs.total_attributes);
    try testing.expectEqual(@as(u32, 0), specs.total_top_level_children);
}

test "Measure: count tag with text child" {
    var specs: Measure = .{};
    try specs.measureTml("<div|hello>");
    try testing.expectEqual(@as(u32, 2), specs.total_nodes);
    try testing.expectEqual(@as(u32, 0), specs.total_attributes);
    try testing.expectEqual(@as(u32, 1), specs.total_top_level_children);
}

test "Measure: count tag with single attribute" {
    var specs: Measure = .{};
    try specs.measureTml("<div id=\"test\">");
    try testing.expectEqual(@as(u32, 1), specs.total_nodes);
    try testing.expectEqual(@as(u32, 1), specs.total_attributes);
    try testing.expectEqual(@as(u32, 0), specs.total_top_level_children);
}

test "Measure: count tag with multiple attributes" {
    var specs: Measure = .{};
    try specs.measureTml("<div id=\"test\" class=\"container\" disabled>");
    try testing.expectEqual(@as(u32, 1), specs.total_nodes);
    try testing.expectEqual(@as(u32, 3), specs.total_attributes);
    try testing.expectEqual(@as(u32, 0), specs.total_top_level_children);
}

test "Measure: count tag with attributes and children" {
    var specs: Measure = .{};
    try specs.measureTml("<div id=\"test\"|hello>");
    try testing.expectEqual(@as(u32, 2), specs.total_nodes);
    try testing.expectEqual(@as(u32, 1), specs.total_attributes);
    try testing.expectEqual(@as(u32, 1), specs.total_top_level_children);
}

test "Measure: count nested tags" {
    var specs: Measure = .{};
    try specs.measureTml("<div|<span|hello>>");
    try testing.expectEqual(@as(u32, 3), specs.total_nodes);
    try testing.expectEqual(@as(u32, 0), specs.total_attributes);
    try testing.expectEqual(@as(u32, 2), specs.total_top_level_children);
}

test "Measure: count multiple sibling tags" {
    var specs: Measure = .{};
    try specs.measureTml("<div><span><p>");
    try testing.expectEqual(@as(u32, 3), specs.total_nodes);
    try testing.expectEqual(@as(u32, 0), specs.total_attributes);
    try testing.expectEqual(@as(u32, 0), specs.total_top_level_children);
}

test "Measure: count deeply nested structure" {
    var specs: Measure = .{};
    try specs.measureTml("<div|<p|<span|text>>>");
    try testing.expectEqual(@as(u32, 4), specs.total_nodes);
    try testing.expectEqual(@as(u32, 0), specs.total_attributes);
    try testing.expectEqual(@as(u32, 3), specs.total_top_level_children);
}

test "Measure: count complex structure with mixed attributes and children" {
    var specs: Measure = .{};
    try specs.measureTml("<div id=\"root\"|<p class=\"text\"|hello><span data-attr=\"val\"|world>>");
    try testing.expectEqual(@as(u32, 5), specs.total_nodes);
    try testing.expectEqual(@as(u32, 3), specs.total_attributes);
    try testing.expectEqual(@as(u32, 3), specs.total_top_level_children);
}

test "Measure: count meta declarations" {
    var specs: Measure = .{};
    try specs.measureTml("!doctype html!");
    try testing.expectEqual(@as(u32, 1), specs.total_nodes);
    try testing.expectEqual(@as(u32, 0), specs.total_attributes);
    try testing.expectEqual(@as(u32, 0), specs.total_top_level_children);
}

test "Measure: count comments" {
    var specs: Measure = .{};
    try specs.measureTml("#this is a comment#");
    try testing.expectEqual(@as(u32, 1), specs.total_nodes);
    try testing.expectEqual(@as(u32, 0), specs.total_attributes);
    try testing.expectEqual(@as(u32, 0), specs.total_top_level_children);
}

test "Measure: count mixed meta and tags" {
    var specs: Measure = .{};
    try specs.measureTml("!doctype html!<div><p>");
    try testing.expectEqual(@as(u32, 3), specs.total_nodes);
    try testing.expectEqual(@as(u32, 0), specs.total_attributes);
    try testing.expectEqual(@as(u32, 0), specs.total_top_level_children);
}

test "Measure: count attributes with values" {
    var specs: Measure = .{};
    try specs.measureTml("<input type=\"text\" placeholder=\"Enter name\">");
    try testing.expectEqual(@as(u32, 1), specs.total_nodes);
    try testing.expectEqual(@as(u32, 2), specs.total_attributes);
    try testing.expectEqual(@as(u32, 0), specs.total_top_level_children);
}

test "Measure: count mixed content structure" {
    var specs: Measure = .{};
    try specs.measureTml("hello <div|world> <span|text> foo");
    try testing.expectEqual(@as(u32, 6), specs.total_nodes);
    try testing.expectEqual(@as(u32, 0), specs.total_attributes);
    try testing.expectEqual(@as(u32, 2), specs.total_top_level_children);
}

test "Measure: count attributes with mixed syntax" {
    var specs: Measure = .{};
    try specs.measureTml("<button disabled checked id=\"btn\">");
    try testing.expectEqual(@as(u32, 1), specs.total_nodes);
    try testing.expectEqual(@as(u32, 3), specs.total_attributes);
    try testing.expectEqual(@as(u32, 0), specs.total_top_level_children);
}
