const std = @import("std");

const Escaper = @import("../Escaper.zig");
const Measure = @import("Measure.zig");
const Parser = @import("Parser.zig");
const QuotedTokeniser = @import("toks").QuotedTokeniser;

const Document = @This();

nodes: []const Node,
attributes: []const Node.Attr,
top_level_node_count: u32,

pub const Node = struct {
    kind: Kind,
    content: []const u8,
    attrs: ?Slice = null,
    children: ?Slice = null,

    const Slice = struct { u32, u32 };

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
};

pub fn initComptime(comptime input: []const u8) !Document {
    @setEvalBranchQuota(1_000_000);

    const specs = comptime b: {
        var sp = Document.Measure{};
        try sp.measureTml(input);
        break :b sp;
    };
    var nodes: [specs.total_nodes]Node = undefined;
    var attrs: [specs.total_attributes]Node.Attr = undefined;
    var children: [specs.total_top_level_children]Parser.Lazy = undefined;

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
            try w.print("<!{f}>", .{ Escaper.init(node.content)});
        },
        .comment => {
            try w.print("<--{f}-->", .{ Escaper.init(node.content)});
        },
        .text => {
            var texttoks = QuotedTokeniser { .input = node.content };
            var peek = texttoks.peekNextTok();
            var thr: []const u8 = "";
            tokens: switch (peek.tok.kind) {
                .token => {
                    try w.print("{s}{f}", .{ thr, Escaper.init(peek.tok.raw)});
                    thr = " ";
                    texttoks.current = peek.chop;
                    peek = texttoks.peekNextTok();
                    continue :tokens peek.tok.kind;
                },
                .quote => {
                    try w.print("{s}{f}", .{ thr, Escaper.init(peek.tok.raw[1..peek.tok.raw.len - 1])});
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
                        try w.print("=\"{f}\"", .{ Escaper.init(v)});
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
