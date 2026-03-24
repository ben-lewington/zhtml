const std = @import("std");
const Node = @import("../tml.zig").Node;
const Document = @import("Document.zig");
const Parser = @This();
const log = std.log.scoped(.tml_parser);

const tokeniser = @import("toks");
pub const Tokeniser = tokeniser.Tokeniser(.{.Symbols = Symbol});
pub const AttrsTokeniser = tokeniser.Tokeniser(.{.Symbols = AttrSymbol});

nodes: std.ArrayList(Node),
attrs: std.ArrayList(Node.Attr),
children: std.ArrayList(Node.Lazy),
top_end: ?u32 = null,

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

pub fn initPinned(
    self: *Parser,
    nodes: std.ArrayList(Node),
    attrs: std.ArrayList(Node.Attr),
    children: std.ArrayList(Node.Lazy),
) void {
    self.* = .{
        .nodes = nodes,
        .attrs = attrs,
        .children = children,
    };
}

pub fn init(alloc: std.mem.Allocator, specs: Document.Specs) !Parser {
    return .{
        .nodes = try .initCapacity(alloc, specs.total_nodes),
        .attrs = try .initCapacity(alloc, specs.total_attributes),
        .children = try .initCapacity(alloc, specs.total_top_level_children),
    };
}

pub fn deinit(self: *Parser, alloc: std.mem.Allocator) void {
    self.nodes.deinit(alloc);
    self.attrs.deinit(alloc);
    self.children.deinit(alloc);
}

/// parse (returns the number of top level nodes):
///   node_start = current number of nodes
///   child_start = current number of children
///   0: check first token:
///     quote, token => chomp quote/token until we see another kind. push .text. continue :0
///     eof => nothing to do
///     symbol => check symbol:
///       def     (<) => chomp next token, assert token (tag_name).
///         1: check token:
///           quote, token => set attr_start, continue :1
///           eof => error
///           symbol => check symbol:
///             def     (<) => error
///             push    (|) =>
///               depth = 1
///               child_start = chop |
///               2: lazy check child token
///                 quote, token => continue :2
///                 eof => error
///                 symbol => lazy check symbol:
///                   pop     (>) => depth = depth - 1. if depth = 0, push child and break :2. continue :2
///                   def     (<) => depth = depth + 1. continue :2
///                   meta    (!) => ignore, continue :2
///                   comment (#) => ignore, continue :2
///               if attr_start is set, parseAttrs
///               push .tag
///               push child with the node_ix of this tag
///               continue :0
///             pop     (>) =>
///               if attr_start is set, parseAttrs
///               push .tag
///               continue :0
///       push    (|) => invalid at top level, must be quoted, error
///       pop     (>) => invalid at top level, must be quoted, error
///       meta    (!) => chomp exactly four tokens, assert !, token, quote/token, !. push .meta. continue :0
///       comment (#) => chomp # and then all tokens until next #. push .comment. continue :0
///   top_levels_added = current number of children
///   for each child added:
///     child_top_levels_added = parse child input
///     if any added, for the parent node, set children to be the new slice
///   return top_levels_added
pub fn parse(self: *Parser, input: []const u8) !u32 {
    const top_nodes_start = self.nodes.items.len;
    const cur_child_start = self.children.items.len;
    var toks: Tokeniser = .{ .input = input };
    var peek = toks.peekNextTok();

    start: switch (peek.tok.kind) {
        .quote, .token => {
            const start: u32 = peek.trim;

            toks.current = peek.chop;
            peek = toks.peekNextTok();
            while (peek.tok.kind == .quote or peek.tok.kind == .token) {
                toks.current = peek.chop;
                peek = toks.peekNextTok();
            }

            try self.nodes.appendBounded(.{
                .kind = .text,
                .content = toks.input[start..peek.trim],
            });

            continue :start peek.tok.kind;
        },
        .symbol => switch (std.enums.fromInt(Symbol, peek.tok.raw[0]).?) {
            .def => {
                toks.current = peek.chop;
                peek = toks.peekNextTok();
                if (peek.tok.kind != .token and peek.tok.kind != .quote) return error.Unexpected;
                const tag_start = peek.trim;
                const tag_end = peek.chop;

                toks.current = peek.chop;
                peek = toks.peekNextTok();
                var attr_start: ?u32 = null;
                node_def: switch (peek.tok.kind) {
                    .quote, .token => {
                        if (attr_start == null) attr_start = peek.trim;
                        toks.current = peek.chop;
                        peek = toks.peekNextTok();
                        continue :node_def peek.tok.kind;
                    },
                    .symbol => switch (std.enums.fromInt(Symbol, peek.tok.raw[0]).?) {
                        .def => return error.Unbalanced,
                        .push => {
                            const nodedef_end = peek.trim;
                            const parent_ix = self.nodes.items.len;

                            toks.current = peek.chop;
                            peek = toks.peekNextTok();

                            var depth: i32 = 1;
                            const child_start = peek.trim;
                            lazy_child: switch (peek.tok.kind) {
                                .eof => return error.Unbalanced,
                                .quote, .token => {
                                    toks.current = peek.chop;
                                    peek = toks.peekNextTok();
                                    continue :lazy_child peek.tok.kind;
                                },
                                .symbol => switch (std.enums.fromInt(Symbol, peek.tok.raw[0]).?) {
                                    .def => {
                                        depth += 1;
                                        toks.current = peek.chop;
                                        peek = toks.peekNextTok();
                                        continue :lazy_child peek.tok.kind;
                                    },
                                    .pop => {
                                        depth -= 1;
                                        if (depth == 0) break :lazy_child;
                                        toks.current = peek.chop;
                                        peek = toks.peekNextTok();
                                        continue :lazy_child peek.tok.kind;
                                    },
                                    .push, .meta, .comment => {
                                        toks.current = peek.chop;
                                        peek = toks.peekNextTok();
                                        continue :lazy_child peek.tok.kind;
                                    },
                                },
                            }

                            var tag_node: Node = .{
                                .kind = .tag,
                                .content = toks.input[tag_start..tag_end],
                            };

                            if (attr_start) |as| {
                                try self.parseAttrs(&tag_node, toks.input[as..nodedef_end]);
                            }

                            try self.nodes.appendBounded(tag_node);
                            const child_input = toks.input[child_start..peek.trim];
                            try self.children.appendBounded(.{
                                .parent_ix = @intCast(parent_ix),
                                .input = child_input,
                            });

                            toks.current = peek.chop;
                            peek = toks.peekNextTok();
                            continue :start peek.tok.kind;
                        },
                        .pop => {
                            const nodedef_end = peek.trim;
                            var tag_node: Node = .{
                                .kind = .tag,
                                .content = toks.input[tag_start..tag_end],
                            };

                            if (attr_start) |as| {
                                try self.parseAttrs(&tag_node, toks.input[as..nodedef_end]);
                            }
                            try self.nodes.appendBounded(tag_node);

                            toks.current = peek.chop;
                            peek = toks.peekNextTok();
                            continue :start peek.tok.kind;
                        },
                        .meta, .comment => {
                            toks.current = peek.chop;
                            peek = toks.peekNextTok();
                            continue :node_def peek.tok.kind;
                        },
                    },
                    .eof => return error.Unbalanced,
                }
            },
            .meta => {
                const start = peek.trim;
                toks.current = peek.chop;
                peek = toks.peekNextTok();
                if (peek.tok.kind != .token) return error.Unexpected;
                toks.current = peek.chop;
                peek = toks.peekNextTok();
                if (peek.tok.kind != .token) return error.Unexpected;

                toks.current = peek.chop;
                peek = toks.peekNextTok();
                if (peek.tok.kind != .symbol) return error.Unexpected;
                if (std.enums.fromInt(Symbol, peek.tok.raw[0]) != .meta) return error.Unexpected;

                const end = peek.chop;
                toks.current = peek.chop;
                peek = toks.peekNextTok();

                try self.nodes.appendBounded(.{
                    .kind = .meta,
                    .content = toks.input[start + 1 .. end - 1],
                });

                continue :start peek.tok.kind;
            },
            .comment => {
                const start = peek.trim;
                toks.current = peek.chop;
                peek = toks.peekNextTok();
                while (true) {
                    if (peek.tok.kind == .symbol) {
                        if (peek.tok.raw[0] == @intFromEnum(Symbol.comment)) break;
                    }
                    toks.current = peek.chop;
                    peek = toks.peekNextTok();
                }
                const end = peek.chop;
                toks.current = peek.chop;
                peek = toks.peekNextTok();

                try self.nodes.appendBounded(.{
                    .kind = .comment,
                    .content = toks.input[start + 1 .. end - 1],
                });

                continue :start peek.tok.kind;
            },
            .push, .pop => return error.Unexpected,
        },
        .eof => break :start,
    }

    const top_nodes_end = self.nodes.items.len;
    if (self.top_end == null) self.top_end = @intCast(top_nodes_end);

    const cur_child_end = self.children.items.len;
    for (self.children.items[cur_child_start..cur_child_end]) |c| {
        const nstart = self.nodes.items.len;
        const num_top_nodes = try self.parse(c.input);

        if (num_top_nodes > 0) {
            self.nodes.items[c.parent_ix].children = .{@intCast(nstart), @intCast(nstart + num_top_nodes)};
        }
    }

    // Return the number of top-level nodes added at THIS level, which only includes
    // the nodes added before recursion (the direct children parse results are attached as slices)
    const num_top_nodes_added = top_nodes_end - top_nodes_start;
    return @intCast(num_top_nodes_added);
}

fn parseAttrs(self: *Parser, node: *Node, input: []const u8) !void {
    const attrs_start = self.attrs.items.len;
    var atoks = AttrsTokeniser{ .input = input };
    var apeek = atoks.peekNextTok();
    var cur_name_opt: ?[]const u8 = null;
    var cur_value_opt: ?[]const u8 = null;
    start: switch (apeek.tok.kind) {
        .token => {
            if (cur_name_opt) |cur_name| {
                try self.attrs.appendBounded(.{ .name = cur_name, .value = cur_value_opt });
                cur_value_opt = null;
            }
            cur_name_opt = apeek.tok.raw;
            atoks.current = apeek.chop;
            apeek = atoks.peekNextTok();
            continue :start apeek.tok.kind;
        },
        .symbol => switch (std.enums.fromInt(AttrSymbol, apeek.tok.raw[0]).?) {
            .eq => {
                if (cur_name_opt == null) return error.Unexpected;

                atoks.current = apeek.chop;
                apeek = atoks.peekNextTok();
                if (apeek.tok.kind != .quote) return error.Unexpected;

                cur_value_opt = apeek.tok.raw[1 .. apeek.tok.raw.len - 1];
                atoks.current = apeek.chop;
                apeek = atoks.peekNextTok();
                continue :start apeek.tok.kind;
            },
            inline else => |s| {
                if (cur_name_opt) |cur_name| {
                    try self.attrs.appendBounded(.{ .name = cur_name, .value = cur_value_opt });
                    cur_name_opt = null;
                    cur_value_opt = null;
                }

                atoks.current = apeek.chop;
                apeek = atoks.peekNextTok();
                if (apeek.tok.kind != .token) return error.Unexpected;

                try self.attrs.appendBounded(.{
                    .name = @tagName(s),
                    .value = apeek.tok.raw,
                });
            },
        },
        .eof => {
            if (cur_name_opt) |cur_name| {
                try self.attrs.appendBounded(.{ .name = cur_name, .value = cur_value_opt });
            }
            break :start;
        },
        .quote => return error.Unexpected,
    }

    node.attrs = .{ @intCast(attrs_start), @intCast(self.attrs.items.len) };
}

const behaviour: []const struct { []const u8, Document, []const u8 } = &.{
    .{
        \\this is a string of "tokens"
        ,
        .{
            .attributes = &.{},
            .nodes = &.{
                Node{
                    .kind = .text,
                    .content = "this is a string of \"tokens\"",
                },
            },
            .top_level_node_count = 1,
        },
        \\this is a string of tokens
    },
    .{
        \\!doctype html!
        \\#a comment#
        ,
        .{
            .attributes = &.{},
            .nodes = &.{
                Node{
                    .kind = .meta,
                    .content = "doctype html",
                },
                Node{
                    .kind = .comment,
                    .content = "a comment",
                },
            },
            .top_level_node_count = 2,
        },
        \\<!doctype html><--a comment-->
    },
    .{
        \\<a|>
        ,
        .{
            .attributes = &.{},
            .nodes = &.{
                Node{
                    .kind = .tag,
                    .content = "a",
                },
            },
            .top_level_node_count = 1,
        },
        \\<a></a>
    },
    .{
        \\<a href="/"|
        \\  <b|
        \\    Hello
        \\  >
        \\>
        ,
        .{
            .attributes = &.{
                Node.Attr{
                    .name = "href",
                    .value = "/",
                },
            },
            .nodes = &.{
                Node{
                    .kind = .tag,
                    .content = "a",
                    .attrs = .{ 0, 1 },
                    .children = .{ 1, 2 },
                },
                Node{
                    .kind = .tag,
                    .content = "b",
                    .children = .{ 2, 3 },
                },
                Node{
                    .kind = .text,
                    .content = "Hello",
                },
            },
            .top_level_node_count = 1,
        },
        \\<a href="/"><b>Hello</b></a>
    },
    .{
        \\<a foo| Hello >
        \\<b bar>
        \\<c bar>
        ,
        .{
            .attributes = &.{
                Node.Attr{.name = "foo"},
                Node.Attr{.name = "bar"},
                Node.Attr{.name = "bar"},
            },
            .nodes = &.{
                Node{
                    .kind = .tag,
                    .content = "a",
                    .attrs = .{0, 1},
                    .children = .{3, 4},
                },
                Node{
                    .kind = .tag,
                    .content = "b",
                    .attrs = .{1, 2},
                },
                Node{
                    .kind = .tag,
                    .content = "c",
                    .attrs = .{2, 3},
                },
                Node{
                    .kind = .text,
                    .content = "Hello",
                },
            },
            .top_level_node_count = 3,
        },
        \\<a foo>Hello</a><b bar></b><c bar></c>
    },
};

comptime {
    for (behaviour) |bt| {
        _ = struct {
            test {
                const alloc = std.testing.allocator;

                var builder = Parser{
                    .nodes = try std.ArrayList(Node).initCapacity(alloc, 10),
                    .attrs = try std.ArrayList(Node.Attr).initCapacity(alloc, 10),
                    .children = try std.ArrayList(Node.Lazy).initCapacity(alloc, 10),
                    .top_end = null,
                };
                defer {
                    builder.deinit(alloc);
                }
                _ = try builder.parse(bt.@"0");
                const doc: Document = .{
                    .attributes = builder.attrs.items,
                    .nodes = builder.nodes.items,
                    .top_level_node_count = builder.top_end orelse @intCast(builder.nodes.items.len),
                };

                docsEqual(doc, bt.@"1") catch |err| {
                    log.err("expected:\n{f}\ngot:\n{f}", .{doc, bt.@"1"});
                    return err;
                };

                const html = try std.fmt.allocPrint(alloc, "{f}", .{doc.html()});
                defer alloc.free(html);
                std.testing.expectEqualSlices(u8, bt.@"2", html) catch |err| {
                    log.err("expected:\n{s}\ngot:\n{s}", .{bt.@"2", html});
                    return err;
                };
            }
        };
    }
}

// Tests
fn docsEqual(expected: Document, actual: Document) !void {
    try std.testing.expectEqual(expected.top_level_node_count, actual.top_level_node_count);
    for (expected.nodes, actual.nodes) |e, a| {
        try std.testing.expectEqualDeep(e, a);
    }
    for (expected.attributes, actual.attributes) |e, a| {
        try std.testing.expectEqualDeep(e, a);
    }
}

