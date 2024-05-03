const std = @import("std");
const log = @import("log.zig");
const big_enough = @import("big_enough.zig");
const escape = @import("escape.zig");

const toks = @import("tokeniser.zig");

const WHITESPACE = " \n\r\t";
const QUOTES = .{ '"', '"' };

const HtmlTokeniser = toks.Tokeniser(.{
    .spacing = WHITESPACE,
    .quotes = QUOTES,
    .symbols = &SyntaxSym.asRaw(),
});

const str = []const u8;
const assert = std.debug.assert;

tokens: HtmlTokeniser,
esc_strs: big_enough.Buffer(u8),
nodes: big_enough.Buffer(Node),
attrs: big_enough.Buffer(NodeAttrs),
parent_stack: big_enough.Stack(*Node),

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
            attrs: ?[]NodeAttrs,
            self_closing: bool,
        };
    };
};

pub const NodeAttrs = struct {
    key: str,
    value: ?str,

    pub fn format(
        value: @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("{s}=\"{s}\"", .{ value.key, value.value orelse "" });
    }
};

// Syntax
pub const SyntaxSym = enum(u8) {
    // starts a node definition
    def = '<',
    // finishes the definition of a node, doesn't push it's value onto the parent stack
    pinch = '|',
    // finishes the definition of a node and pushes it's value onto the parent stack
    push = '{',
    // pops a value from the parent stack
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

pub const ParseNodeResult = struct { at: HtmlTokeniser.Token.Info, status: enum {
    ok,
    unexpected_symbol_while_parsing_node,
    expected_push_or_pinch_while_parsing_node_got_def,
    expected_push_or_pinch_while_parsing_node_got_pop,
    unexpected_symbol_while_parsing_node_attributes,
    unbalanced_quoted_literal,
    expected_end_of_node_definition_but_got_eof,
    expected_attribute_name_found_quoted_literal,
    expected_attribute_name_found_symbol,
    expected_attribute_name_found_eof,
    expected_attribute_value_found_unquoted_literal,
    expected_attribute_value_found_symbol,
    expected_attribute_value_found_eof,
    tag_name_cannot_be_quoted_literal,
    unbalanced_nodes,
} };

pub fn init(tokens: str, strs: []u8, nodes: []Node, attrs: []NodeAttrs, parent_stack: []*Node) Self {
    return .{
        .tokens = HtmlTokeniser.init(tokens),
        .esc_strs = big_enough.Buffer(u8).init(strs),
        .nodes = big_enough.Buffer(Node).init(nodes),
        .attrs = big_enough.Buffer(NodeAttrs).init(attrs),
        .parent_stack = big_enough.Stack(*Node).init(parent_stack),
    };
}

pub fn parseNode(self: *Self) ?ParseNodeResult {
    var peek = self.tokens.peekNextTok();
    if (peek.tok.kind == .eof) {
        if (self.parent_stack.peek()) |p| {
            log.debug("{}", .{p.data});
            return .{ .at = peek, .status = .unbalanced_nodes };
        }
        return null;
    }

    log.debug("{}, remaining \"{s}\"", .{
        peek,
        self.tokens.input[peek.chop..],
    });

    while (peek.tok.kind != .eof) {
        switch (peek.tok.kind) {
            .literal, .qu_balanced => {
                const node = self.parseLiteral(&peek);
                self.nodes.push(node);

                log.info("parsed node[literal]: parent?: {any}, literal: \"{s}\"", .{
                    node.parent == null,
                    node.data.literal,
                });

                return .{ .at = peek, .status = .ok };
            },
            .symbol => {
                var sym: SyntaxSym = @enumFromInt(peek.tok.raw[0]);
                switch (sym) {
                    .def => {
                        self.tokens.current = peek.chop;
                        peek = self.tokens.peekNextTok();

                        var tag: str = undefined;
                        var attrs: ?[]NodeAttrs = null;
                        switch (peek.tok.kind) {
                            .literal => {
                                const write_str_start = self.esc_strs.len;
                                // TODO(BL): need to validate this input.
                                self.esc_strs.extend(peek.tok.raw);

                                tag = self.esc_strs.inner[write_str_start..self.esc_strs.len];

                                //  Here, `tag` is well formed, need to parse the node attrs.
                                //  an attribute declaration will be of the form:
                                //      - key="value" (double quotes remove parsing ambiguities)
                                //      - key ="value" (double quotes remove parsing ambiguities)
                                //      - key= "value" (double quotes remove parsing ambiguities)
                                //      - key
                                //  The top cases are annoying, and it's because `=` a symbol for the
                                //  original tokeniser.
                                //
                                //  To get a resonable token stream, we will save the current peek.chop,
                                //  and consume tokens until we encounter either a `.push` or `.pinch`
                                //  symbol, erroring if any of the intermediate tokens are not `.literal`
                                //  or `.qu_balanced`.
                                const attrs_start = peek.chop;

                                log.debug("parsed {} as tag; finding end of attrs in remaining: \"{s}\"", .{
                                    peek,
                                    self.tokens.input[peek.chop..],
                                });

                                self.tokens.current = peek.chop;
                                peek = self.tokens.peekNextTok();
                                while (peek.tok.kind != .eof) {
                                    switch (peek.tok.kind) {
                                        .symbol => {
                                            sym = @enumFromInt(peek.tok.raw[0]);
                                            switch (sym) {
                                                .push, .pinch => break,
                                                else => return .{ .at = peek, .status = .unexpected_symbol_while_parsing_node_attributes },
                                            }
                                        },
                                        .literal, .qu_balanced => {},
                                        .qu_unbalanced => return .{
                                            .at = peek,
                                            .status = .unbalanced_quoted_literal,
                                        },
                                        .eof => return .{ .at = peek, .status = .expected_end_of_node_definition_but_got_eof },
                                    }
                                    self.tokens.current = peek.chop;
                                    peek = self.tokens.peekNextTok();

                                    log.debug("testing {}, remaining \"{s}\"", .{
                                        peek,
                                        self.tokens.input[peek.chop..],
                                    });
                                }
                                // Here, `peek.trim` points to the end of the attr declarations,
                                // just before we finish defining the node.
                                const raw_attrs = self.tokens.input[attrs_start..peek.trim];
                                log.debug(
                                    "found attrs{{ \"{s}\" }}@#{d}->#{d}, remaining: \"{s}\"",
                                    .{ raw_attrs, attrs_start, peek.trim, self.tokens.input[peek.trim..] },
                                );

                                const attrs_slice_start = self.attrs.len;

                                // tokenise the raw_attrs, using only `=` as a symbol.
                                var parse_attrs = toks.Tokeniser(.{
                                    .spacing = WHITESPACE,
                                    .quotes = QUOTES,
                                    .symbols = "=",
                                }).init(self.tokens.input[attrs_start..peek.trim]);

                                // walk the tokens in a window of three tokens
                                var apeek3 = parse_attrs.peekNextNTok(3);
                                while (apeek3[0].tok.kind != .eof) {
                                    var attr_name: str = undefined;

                                    // TODO(BL): need to validate this input.
                                    switch (apeek3[0].tok.kind) {
                                        .literal => attr_name = apeek3[0].tok.raw,
                                        .qu_balanced => return .{ .at = apeek3[0], .status = .expected_attribute_name_found_quoted_literal },
                                        .symbol => return .{ .at = apeek3[0], .status = .expected_attribute_name_found_symbol },
                                        .qu_unbalanced => return .{ .at = apeek3[0], .status = .unbalanced_quoted_literal },
                                        .eof => return .{ .at = apeek3[0], .status = .expected_attribute_name_found_eof },
                                    }

                                    const attr_str = self.esc_strs.len;
                                    self.esc_strs.extend(attr_name);
                                    attr_name = self.esc_strs.inner[attr_str..self.esc_strs.len];

                                    if (apeek3[1].tok.kind != .symbol) {
                                        // munch the first of the three tokens
                                        parse_attrs.current = apeek3[0].chop;
                                        const na: NodeAttrs = .{
                                            .key = attr_name,
                                            .value = null,
                                        };
                                        log.debug("parsed attr {}", .{na});
                                        self.attrs.push(na);

                                        apeek3 = parse_attrs.peekNextNTok(3);
                                        continue;
                                    }

                                    switch (apeek3[2].tok.kind) {
                                        .qu_balanced => {
                                            parse_attrs.current = apeek3[2].chop;
                                            const attrv_str = self.esc_strs.len;
                                            const s = apeek3[2].tok.raw;
                                            _ = escape.escapeToStr(s[1 .. s.len - 1], &self.esc_strs);
                                            const na: NodeAttrs = .{
                                                .key = attr_name,
                                                .value = self.esc_strs.inner[attrv_str..self.esc_strs.len],
                                            };
                                            log.debug("parsed attr {}", .{na});
                                            self.attrs.push(na);
                                        },
                                        .literal => return .{ .at = apeek3[2], .status = .expected_attribute_value_found_unquoted_literal },
                                        .symbol => return .{ .at = apeek3[2], .status = .expected_attribute_value_found_symbol },
                                        .qu_unbalanced => return .{ .at = apeek3[2], .status = .unbalanced_quoted_literal },
                                        .eof => return .{ .at = apeek3[2], .status = .expected_attribute_value_found_eof },
                                    }

                                    apeek3 = parse_attrs.peekNextNTok(3);
                                }

                                const node_attrs = self.attrs.inner[attrs_slice_start..self.attrs.len];

                                if (attrs_slice_start < self.attrs.len) attrs = node_attrs;

                                log.debug("{}, {s}", .{ peek, node_attrs });

                                //  after we have a tag name, there are two valid possibilities:
                                //      - a push or pinch symbol
                                //      - a valid ident (i.e. announcing an attribute
                                switch (peek.tok.kind) {
                                    .symbol => {
                                        sym = @enumFromInt(peek.tok.raw[0]);
                                        switch (sym) {
                                            .push, .pinch => {
                                                self.tokens.current = peek.chop;

                                                // snapshot the index, the push the pointer to the parent stack
                                                const node_ix = self.nodes.len;
                                                const parent = self.parent_stack.peek();
                                                const node = .{ .parent = parent, .data = .{
                                                    .node = .{
                                                        .tag = tag,
                                                        .attrs = attrs,
                                                        .self_closing = sym == .pinch,
                                                    },
                                                } };

                                                self.nodes.push(node);

                                                log.debug("parsed node[node]: parent?: {any}, <{s}{s}>", .{
                                                    node.parent != null,
                                                    node.data.node.tag,
                                                    if (node.data.node.self_closing) "/" else "",
                                                });

                                                const lookup_node = &self.nodes.inner[node_ix];
                                                if (sym == .push) self.parent_stack.push(lookup_node);

                                                return .{ .at = peek, .status = .ok };
                                            },
                                            .pop => return .{ .at = peek, .status = .expected_push_or_pinch_while_parsing_node_got_pop },
                                            .def => return .{ .at = peek, .status = .expected_push_or_pinch_while_parsing_node_got_def },
                                        }
                                    },
                                    else => unreachable,
                                }
                            },
                            .qu_balanced => return .{ .at = peek, .status = .tag_name_cannot_be_quoted_literal },
                            .qu_unbalanced => return .{ .at = peek, .status = .unbalanced_quoted_literal },
                            .symbol => return .{ .at = peek, .status = .unexpected_symbol_while_parsing_node },
                            .eof => return null,
                        }
                        unreachable;
                    },
                    .pop => {
                        _ = self.parent_stack.pop();

                        self.tokens.current = peek.chop;
                        peek = self.tokens.peekNextTok();

                        continue;
                    },
                    else => return .{ .at = peek, .status = .unexpected_symbol_while_parsing_node },
                }
            },
            .eof => break,
            .qu_unbalanced => return .{ .at = peek, .status = .unbalanced_quoted_literal },
        }
    }
    return null;
}

fn parseLiteral(self: *Self, peek: *HtmlTokeniser.Token.Info) Node {
    assert(peek.tok.kind == .literal or peek.tok.kind == .qu_balanced);

    const olit_s: usize = self.esc_strs.len;
    var olit_e: usize = olit_s;

    while (peek.tok.kind == .literal or peek.tok.kind == .qu_balanced) {
        const lit = switch (peek.tok.kind) {
            .literal => peek.tok.raw,
            .qu_balanced => peek.tok.raw[1 .. peek.tok.raw.len - 1],
            else => unreachable,
        };

        log.debug("literal: {s}", .{lit});

        if (escape.escapeNeeded(lit)) {
            const esc_res = escape.escapeToStr(lit, &self.esc_strs);
            self.esc_strs.push(' ');
            olit_e += esc_res.len + 1;
        } else {
            self.esc_strs.extend(lit);
            self.esc_strs.push(' ');
            olit_e += lit.len + 1;
        }

        self.tokens.current = peek.chop;
        peek.* = self.tokens.peekNextTok();

        log.debug("{}, remaining \"{s}\"", .{
            peek,
            self.tokens.input[peek.chop..],
        });
    }
    // get rid of the trailing space
    olit_e -= 1;

    return .{ .parent = self.parent_stack.peek(), .data = .{
        .literal = self.esc_strs.inner[olit_s..olit_e],
    } };
}

pub fn numOccurances(tokens: str, ch: u8) usize {
    var i = 0;
    for (tokens) |ich| {
        if (ich == ch) i += 1;
    }
    return i;
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
                    .node => return .CloseNodeBeforeCloseHeader,
                }
            },
            else => {},
        }
    }
}
