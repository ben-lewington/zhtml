const std = @import("std");
const Document = @import("Document.zig");
const Measure = @import("Measure.zig");
const Parser = @This();
const TmlTokeniser = @import("../tml.zig").TmlTokeniser;
const TmlAttrsTokeniser = @import("../tml.zig").TmlAttrsTokeniser;
const log = std.log.scoped(.tml_parser);

nodes: std.ArrayList(Document.Node),
attrs: std.ArrayList(Document.Node.Attr),
children: std.ArrayList(Lazy),
top_end: ?u32 = null,

/// by deferring the parsing of child documents, we get the sibling nodes contiguous trivially.
pub const Lazy = struct {
    parent_ix: u32,
    input: []const u8,
};

pub fn init(alloc: std.mem.Allocator, specs: Measure) !Parser {
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

pub fn parse(self: *Parser, input: []const u8) !u32 {
    const top_nodes_start = self.nodes.items.len;
    const cur_child_start = self.children.items.len;
    var toks: TmlTokeniser = .{ .input = input };
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
        .symbol => switch (std.enums.fromInt(TmlTokeniser.Symbol, peek.tok.raw[0]).?) {
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
                    .symbol => switch (std.enums.fromInt(TmlTokeniser.Symbol, peek.tok.raw[0]).?) {
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
                                .symbol => switch (std.enums.fromInt(TmlTokeniser.Symbol, peek.tok.raw[0]).?) {
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

                            var tag_node: Document.Node = .{
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
                            var tag_node: Document.Node = .{
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
                if (std.enums.fromInt(TmlTokeniser.Symbol, peek.tok.raw[0]) != .meta) return error.Unexpected;

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
                        if (peek.tok.raw[0] == @intFromEnum(TmlTokeniser.Symbol.comment)) break;
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

        self.nodes.items[c.parent_ix].children = .{ @intCast(nstart), @intCast(nstart + num_top_nodes) };
    }

    // Return the number of top-level nodes added at THIS level, which only includes
    // the nodes added before recursion (the direct children parse results are attached as slices)
    const num_top_nodes_added = top_nodes_end - top_nodes_start;
    return @intCast(num_top_nodes_added);
}

fn parseAttrs(self: *Parser, node: *Document.Node, input: []const u8) !void {
    const attrs_start = self.attrs.items.len;
    var atoks = TmlAttrsTokeniser{ .input = input };
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
        .symbol => switch (std.enums.fromInt(TmlAttrsTokeniser.Symbol, apeek.tok.raw[0]).?) {
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
