const std = @import("std");
const buf = @import("big_enough.zig");
const escape = @import("escape.zig");

const Tokeniser = @import("tokeniser.zig").Tokeniser(.{
    .spacing = " \n\r\t",
    .quotes = .{ '"', '"' },
    .symbols = &SyntaxSym.asRaw(),
});

const str = []const u8;
const log = std.log;
const assert = std.debug.assert;

tokens: Tokeniser,

esc_strs: buf.Buffer(u8),
nodes: buf.Buffer(Node),
parent_stack: buf.Stack(*Node),

const Self = @This();

const NodeType = enum {
    literal,
    node,
};

// structure representing a HTML node.
pub const Node = struct {
    parent: ?*Node,
    data: NodeData,

    const NodeData = union(NodeType) {
        literal: str,
        node: NodeVariant,

        const NodeVariant = struct {
            tag: str,
            attrs: ?Attrs,
            self_closing: bool,

            const Attrs = struct {
                keys: []str,
                values: []?str,
            };
        };
    };
};

// Syntax
pub const SyntaxSym = enum(u8) {
    // starts a node definition
    def = '<',
    // finishes the definition of a node, doesn't push it's value onto the parent_ix stack
    pinch = '|',
    // finishes the definition of a node and pushes it's value onto the parent_ix stack
    push = '{',
    // pops a value from the parent_ix stack
    pop = '}',

    const SSelf = @This();
    const fields = @typeInfo(SSelf).Enum.fields;

    pub inline fn asRaw() [fields.len]u8 {
        comptime var f: [fields.len]u8 = undefined;
        inline for (fields, 0..) |field, i| f[i] = field.value;
        return f;
    }

    pub fn literally(self: SSelf) u8 {
        return @intFromEnum(self);
    }
};

pub fn init(tokens: str, strs: []u8, nodes: []Node, parent_stack: []*Node) Self {
    return .{
        .tokens = Tokeniser.init(tokens),
        .esc_strs = buf.Buffer(u8).init(strs),
        .nodes = buf.Buffer(Node).init(nodes),
        .parent_stack = buf.Stack(*Node).init(parent_stack),
    };
}

pub fn parseNode(self: *Self) !?void {
    // log.debug("Parsing tokens \"{s}\"", .{self.tokens});
    var peek = self.tokens.peekNextTok();
    if (peek.tok.kind == .eof or self.tokens.current > self.tokens.input.len) return null;

    std.log.debug("tok[{s}]: \"{s}\", remaining \"{s}\"", .{
        @tagName(peek.tok.kind),
        peek.tok.raw,
        self.tokens.input[peek.chop..],
    });

    while (peek.tok.kind != .eof) {
        switch (peek.tok.kind) {
            .literal, .qu_balanced => {
                const esc_lit_start: usize = self.esc_strs.len;
                var esc_lit_end: usize = esc_lit_start;

                while (peek.tok.kind == .literal or peek.tok.kind == .qu_balanced) {
                    var lit: str = undefined;
                    switch (peek.tok.kind) {
                        .literal => lit = peek.tok.raw,
                        .qu_balanced => lit = peek.tok.raw[1 .. peek.tok.raw.len - 1],
                        else => unreachable,
                    }
                    const esc = escape.escapeNeeded(lit);
                    if (esc) {
                        const esc_res = escape.escapeToStr(lit, &self.esc_strs);
                        self.esc_strs.push(' ');
                        esc_lit_end += esc_res.len + 1;
                    } else {
                        self.esc_strs.extend(lit);
                        self.esc_strs.push(' ');
                        esc_lit_end += lit.len + 1;
                    }

                    self.tokens.current = peek.chop;
                    peek = self.tokens.peekNextTok();

                    std.log.debug("tok[{s}]: \"{s}\", remaining \"{s}\"", .{
                        @tagName(peek.tok.kind),
                        peek.tok.raw,
                        self.tokens.input[peek.chop..],
                    });
                }

                esc_lit_end -= 1;
                const node = .{
                    .parent = self.parent_stack.peek(),
                    .data = .{
                        .literal = self.esc_strs.inner[esc_lit_start..esc_lit_end],
                    },
                };
                self.nodes.push(node);

                std.log.info("pushed node[literal]: parent?: {any}, literal: \"{s}\"", .{
                    node.parent == null,
                    node.data.literal,
                });

                return;
            },
            .symbol => {
                var sym: SyntaxSym = @enumFromInt(peek.tok.raw[0]);
                switch (sym) {
                    .def => {
                        self.tokens.current = peek.chop;
                        peek = self.tokens.peekNextTok();

                        var tag: str = undefined;

                        switch (peek.tok.kind) {
                            .literal => {
                                tag = peek.tok.raw;

                                self.tokens.current = peek.chop;
                                peek = self.tokens.peekNextTok();

                                switch (peek.tok.kind) {
                                    .symbol => {
                                        sym = @enumFromInt(peek.tok.raw[0]);
                                        switch (sym) {
                                            .push, .pinch => {
                                                self.tokens.current = peek.chop;

                                                if (sym == .push) {
                                                    defer {
                                                        const node_ix = self.nodes.len;
                                                        self.parent_stack.push(&self.nodes.inner[node_ix]);
                                                    }
                                                }

                                                const node = .{ .parent = self.parent_stack.peek(), .data = .{
                                                    .node = .{
                                                        .tag = tag,
                                                        .attrs = null,
                                                        .self_closing = false,
                                                    },
                                                } };

                                                self.nodes.push(node);

                                                std.log.debug("pushed node[node]: parent?: {any}, <{s}{s}>", .{
                                                    node.parent == null,
                                                    node.data.node.tag,
                                                    if (node.data.node.self_closing) "/" else "",
                                                });
                                                return;
                                            },
                                            .pop => return error.expected_push_or_pinch_while_parsing_node_got_pop,
                                            .def => return error.expected_push_or_pinch_while_parsing_node_got_def,
                                        }
                                    },
                                    .literal => assert(false),
                                    .qu_balanced => return error.expected_attribute_name_found_quoted_literal,
                                    .qu_unbalanced => return error.unbalanced_quoted_strings,
                                    .eof => return null,
                                }
                            },
                            .qu_balanced => return error.expected_tag_name_found_quoted_literal,
                            .qu_unbalanced => return error.unbalanced_quoted_strings,
                            .symbol => return error.unexpected_symbol_while_parsing_node,
                            .eof => return null,
                        }
                        assert(false);
                    },
                    .pop => {
                        _ = self.parent_stack.pop();

                        self.tokens.current = peek.chop;
                        peek = self.tokens.peekNextTok();

                        continue;
                    },
                    else => unreachable,
                }
            },
            .eof => break,
            .qu_unbalanced => return error.unbalanced_quoted_strings,
        }
    }
    return null;
}

pub fn numOccurances(tokens: str, ch: u8) usize {
    var i = 0;
    for (tokens) |ich| {
        if (ich == ch) i += 1;
    }
    return i;
}

pub fn FileLoc(comptime offset: [2]comptime_int) type {
    return struct {
        row: usize,
        col: usize,

        pub fn format(
            value: @This(),
            comptime _: []const u8,
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            try writer.print(" {d}:{d}:", .{ value.row + offset[0], value.col + offset[1] });
        }
    };
}

pub fn getLocation(self: *const Self, offset: usize) FileLoc(.{ 1, 1 }) {
    if (offset >= self.tokens.len) return .{ .row = 0, .col = 0 };
    var row: usize = 0;
    var col: usize = 0;
    var idx: usize = 0;
    while (idx < offset) : (idx += 1) {
        switch (self.tokens[idx]) {
            '\n', '\r' => |ch| {
                if (ch == '\r') {
                    if (idx + 1 <= self.current) {
                        if (self.tokens[idx + 1] == '\n') idx += 1;
                    }
                }
                row += 1;
                col = 0;
            },
            else => col += 1,
        }
    }
    return .{ .row = row, .col = col };
}

pub fn outputSize(tokens: str) !struct {
    nodes: usize,
    depth: usize,
} {
    var nodes: usize = 0;
    var depth: usize = 0;

    var parsing: NodeType = null;

    var cur_depth: usize = 0;
    for (tokens) |ch| {
        switch (ch) {
            '<' => {
                switch (parsing) {
                    null => parsing = .node,
                    .literal => {
                        nodes += 1;
                        parsing = .node;
                    },
                    .node => {
                        nodes += 1;
                        cur_depth += 1;
                        if (cur_depth > depth) depth = cur_depth;
                        parsing = null;
                    },
                }
            },
            ';' => {
                switch (parsing) {
                    null, .literal => {},
                    .node => {
                        nodes += 1;
                        parsing = null;
                    },
                }
            },
            '>' => {
                switch (parsing) {
                    null, .literal => {
                        cur_depth -= 1;
                    },
                    .node => return error.CloseNodeBeforeCloseHeader,
                }
            },
            else => {},
        }
    }
}

// const MarkupSyntax = union(enum) {
//     tag_name: Ident,
//     attribute: Attribute,
//     literal: str,
//     symbol: SyntaxSym,
//
//     const Ident = struct {
//         literally: str,
//     };
//
//     const Attribute = struct {
//         key: Ident,
//         value: Literal,
//     };
//
//     const Literal = struct {
//         literally: str,
//     };
// };
