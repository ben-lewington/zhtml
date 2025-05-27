// ws := [' ' | '\n' | '\r' | '\t']
//
// symbols := {
//     def := '<'
//     push := '|'
//     pinch := ';'
//     pop := '>'
// }
//
// ident := [a-zA-Z0-9][a-zA-Z0-9-_]*
// literal := ".*"
//
// shorthand := {
//     class := '.'
//     id := '#'
// }
//
// markup :=
//     ([ident | literal] ws)* // text node
//   | symbols.def '!' ([ident | literal] ws)* symbols.pinch        // meta node
//   | symbols.def '!' '-' ws ([ident | literal] ws)* symbols.pinch // comment
//   | symbols.def ident ([ident | ident '=' literal])* symbols.push markup symbols.pop // actual
const std = @import("std");
const log = std.log.scoped(.tml);
const Tokeniser = @import("tokeniser.zig").Tokeniser;
const Allocator = std.mem.Allocator;

const Tree = struct {
    root: []const Inner,

    const Inner = struct {
        raw: []const u8,
        kind: enum(u8) {
            text = 0,
            meta = 1,
            comment = 2,
            tag = 3,
        } = .text,
        attr_start: ?u32 = null,
        branch: ?[]const Inner = null,

        pub fn format(value: Inner, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.print("node[{s}] \"{s}\".", .{ @tagName(value.kind), value.raw });
            if (value.branch) |ns| {
                try writer.print("open with branch: <\n", .{});
                for (ns) |n| {
                    try writer.print("{}", .{n});
                }
                try writer.print(">node[{s}] \"{s}\".\n", .{ @tagName(value.kind), value.raw });
            } else {
                try writer.print("\n", .{});
            }
        }
    };

    pub fn format(value: Tree, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("Tree:\n", .{});
        for (value.root) |ns| {
            try writer.print("{}", .{ns});
        }
        try writer.print("EndTree", .{});
    }
};

const ws = " \n\r\t";
const Symbol = enum(u8) {
    def = '<',
    push = '|',
    pop = '>',
    meta = '!',
    comment = '#',
};

fn parseInputAlloc(alloc: Allocator, input: []const u8) !Tree {
    return Tree{
        .root = try parseTopNode(alloc, input),
    };
}

fn countTopNodes(input: []const u8) !usize {
    var ret: usize = 0;
    var toks = Tokeniser(.{}, Symbol){ .input = input };

    var peek = toks.peekNextTok();
    while (peek.tok.kind != .eof) {
        switch (peek.tok.kind) {
            .token, .quote => {
                toks.current = peek.chop;
                peek = toks.peekNextTok();
                while (peek.tok.kind == .token or peek.tok.kind == .quote) {
                    toks.current = peek.chop;
                    peek = toks.peekNextTok();
                }
                ret += 1;
            },
            .symbol => {
                const sym: Symbol = @enumFromInt(peek.tok.raw[0]);
                switch (sym) {
                    .comment, .meta => {
                        toks.current = peek.chop;
                        peek = toks.peekNextTok();
                        while (peek.tok.kind != .symbol and peek.tok.raw[0] != @intFromEnum(sym)) {
                            toks.current = peek.chop;
                            peek = toks.peekNextTok();
                        }
                        toks.current = peek.chop;
                        peek = toks.peekNextTok();
                        ret += 1;
                    },
                    .def => {
                        var depth: isize = 0;
                        var push_valid: bool = true;

                        while (peek.tok.kind != .eof) {
                            switch (peek.tok.kind) {
                                .symbol => {
                                    const tsym: Symbol = @enumFromInt(peek.tok.raw[0]);
                                    switch (tsym) {
                                        .def => {
                                            if (push_valid) {
                                                depth += 1;
                                                push_valid = false;
                                            } else return error.UnexpectedNodeDefInNodeHeader;
                                        },
                                        .push => {
                                            if (!push_valid) {
                                                push_valid = true;
                                            } else return error.UnexpectedPushInNodeBody;
                                        },
                                        .pop => {
                                            if (depth == 0) return error.UnbalancedNode;
                                            depth -= 1;
                                        },
                                        .comment, .meta => {},
                                    }
                                },
                                .token, .quote => {},
                                .eof => unreachable,
                            }
                            toks.current = peek.chop;
                            peek = toks.peekNextTok();
                            if (depth == 0) {
                                ret += 1;
                                break;
                            }
                        }
                    },
                    .pop, .push => {
                        return error.UnexpectedUnescapedSymbolAtTopNode;
                    },
                }
            },
            .eof => unreachable,
        }
        toks.current = peek.chop;
        peek = toks.peekNextTok();
    }

    return ret;
}

fn parseTopNodeComptime(input: []const u8) ![]const Tree.Inner {
    const node_count = try countTopNodes(input);

    var nodes: [node_count]Tree.Inner = undefined;
    var node_ix: usize = 0;

    var toks = Tokeniser(.{}, Symbol){ .input = input };

    var peek = toks.peekNextTok();
    while (peek.tok.kind != .eof) {
        switch (peek.tok.kind) {
            .token, .quote => |t| {
                _ = t;
                const start_ix = peek.trim;
                var end_ix = peek.chop;

                toks.current = peek.chop;
                peek = toks.peekNextTok();

                while (peek.tok.kind != .eof and peek.tok.kind != .symbol) {
                    end_ix = peek.chop;
                    toks.current = peek.chop;
                    peek = toks.peekNextTok();
                }
                nodes[node_ix] = .{
                    .raw = input[start_ix..end_ix],
                    .kind = .text,
                };
                node_ix += 1;
            },
            .symbol => {
                const sym: Symbol = @enumFromInt(peek.tok.raw[0]);
                switch (sym) {
                    .def => {
                        const start_nodedef = peek.chop;
                        var depth: isize = 0;
                        var push_valid: bool = true;

                        b: while (peek.tok.kind != .eof) {
                            switch (peek.tok.kind) {
                                .symbol => {
                                    const tsym: Symbol = @enumFromInt(peek.tok.raw[0]);
                                    switch (tsym) {
                                        .def => {
                                            if (push_valid) {
                                                depth += 1;
                                                push_valid = false;
                                            } else return error.UnexpectedNodeDefInNodeHeader;
                                        },
                                        .push => {
                                            if (!push_valid) {
                                                push_valid = true;
                                            } else return error.UnexpectedPushInNodeBody;
                                        },
                                        .pop => {
                                            if (depth == 0) return error.UnbalancedNode;
                                            depth -= 1;
                                        },
                                        .comment, .meta => {},
                                    }
                                },
                                .token, .quote => {},
                                .eof => unreachable,
                            }
                            if (depth == 0) break :b;
                            toks.current = peek.chop;
                            peek = toks.peekNextTok();
                        }
                        const end_nodedef = peek.trim;

                        toks.current = start_nodedef;
                        peek = toks.peekNextTok();
                        if (peek.tok.kind != .token) return error.TagNamesShouldBeIdents;

                        const tag_start = peek.trim;
                        const attr_start = peek.chop;

                        // consume the node header tokens. If a | symbol is encountered, everything after
                        // that and before end_nodedef will be recursively parsed
                        const nodeh: struct { end: u32, branch: bool } = b: while (peek.chop <= end_nodedef) {
                            switch (peek.tok.kind) {
                                .symbol => {
                                    switch (@as(Symbol, @enumFromInt(peek.tok.raw[0]))) {
                                        .push => {
                                            const e = peek.trim;
                                            toks.current = peek.chop;
                                            peek = toks.peekNextTok();
                                            break :b .{
                                                .end = e,
                                                .branch = true,
                                            };
                                        },
                                        .meta => {},
                                        .comment => {},
                                        .def => return error.UnexpectedOpenTag,
                                        .pop => unreachable,
                                    }
                                },
                                .token, .quote => {},
                                .eof => unreachable,
                            }
                            toks.current = peek.chop;
                            peek = toks.peekNextTok();
                        } else .{
                            .end = end_nodedef,
                            .branch = false,
                        };
                        const branch = b: {
                            if (nodeh.branch) {
                                if (nodeh.end + 1 < end_nodedef) {
                                    const inner = input[nodeh.end + 1 .. end_nodedef];
                                    break :b try parseTopNodeComptime(inner);
                                } else break :b &.{};
                            } else {
                                break :b null;
                            }
                        };
                        nodes[node_ix] = .{
                            .raw = input[tag_start..nodeh.end],
                            .kind = .tag,
                            .attr_start = attr_start - tag_start,
                            .branch = branch,
                        };
                        node_ix += 1;
                        // updated the tokeniser state to after the node we just parsed
                        toks.current = end_nodedef + 1;
                        peek = toks.peekNextTok();
                    },
                    .push, .pop => {
                        return error.UnexpectedUnescapedSymbolAtTopNode;
                    },
                    .meta => {
                        // munch the symbol
                        toks.current = peek.chop;
                        const meta = toks.peekNextNTok(3);
                        if (meta[2].tok.kind != .symbol and meta[2].tok.raw[0] != @intFromEnum(Symbol.meta)) {
                            return error.ExpectedEndOfMetaDeclaration;
                        }
                        const start = meta[0].trim;
                        const end = meta[1].chop;

                        nodes[node_ix] = .{
                            .raw = input[start..end],
                            .kind = .meta,
                        };
                        node_ix += 1;

                        toks.current = meta[2].chop;
                        peek = toks.peekNextTok();
                    },
                    .comment => {
                        // munch the symbol
                        toks.current = peek.chop;
                        peek = toks.peekNextTok();

                        const start = peek.trim;
                        const end = b: while (peek.tok.kind != .eof) {
                            if (peek.tok.kind == .symbol and peek.tok.raw[0] == @intFromEnum(Symbol.comment)) {
                                break :b peek.trim;
                            }
                            toks.current = peek.chop;
                            peek = toks.peekNextTok();
                        } else return error.UnterminatedComment;

                        nodes[node_ix] = .{
                            .raw = input[start..end],
                            .kind = .comment,
                        };
                        node_ix += 1;

                        toks.current = peek.chop;
                        peek = toks.peekNextTok();
                    },
                }
            },
            .eof => unreachable,
        }
    }
    // running this at comptime will allow this value to escape stack lifetimes.
    // Hopefully there's no rug pull at some point in the future from the Zig compiler,
    // but a comptime known const value is essentially static, it ends up in .bss (fact check?)
    const ns: []Tree.Inner = &nodes;
    return ns;
}

fn parseTopNode(alloc: Allocator, input: []const u8) ![]const Tree.Inner {
    var nodes = std.ArrayList(Tree.Inner).init(alloc);
    defer nodes.deinit();

    var toks = Tokeniser(.{}, Symbol){ .input = input };

    var peek = toks.peekNextTok();
    while (peek.tok.kind != .eof) {
        switch (peek.tok.kind) {
            .token, .quote => |t| {
                _ = t;
                const start_ix = peek.trim;
                var end_ix = peek.chop;

                toks.current = peek.chop;
                peek = toks.peekNextTok();

                while (peek.tok.kind != .eof and peek.tok.kind != .symbol) {
                    end_ix = peek.chop;
                    toks.current = peek.chop;
                    peek = toks.peekNextTok();
                }
                try nodes.append(Tree.Inner{
                    .raw = input[start_ix..end_ix],
                    .kind = .text,
                });
            },
            .symbol => {
                const sym: Symbol = @enumFromInt(peek.tok.raw[0]);
                switch (sym) {
                    .def => {
                        // munch the symbol
                        toks.current = peek.chop;
                        peek = toks.peekNextTok();
                        if (peek.tok.kind != .token) return error.TagNamesShouldBeIdents;
                        const tag_start = peek.trim;
                        const attr_start = peek.chop;
                        // check there's a balancing pop symbol
                        var ix = input.len - 1;
                        const end_nodedef: u32 = while (ix > toks.current) : (ix -= 1) {
                            if (input[ix] == @intFromEnum(Symbol.pop)) break @intCast(ix);
                        } else return error.UnbalancedNode;

                        // consume the node header tokens. If a | symbol is encountered, everything after
                        // that and before end_nodedef will be recursively parsed
                        const nodeh: struct { end: u32, branch: bool } = while (peek.chop <= end_nodedef) {
                            switch (peek.tok.kind) {
                                .symbol => {
                                    switch (@as(Symbol, @enumFromInt(peek.tok.raw[0]))) {
                                        .push => {
                                            const e = peek.trim;
                                            toks.current = peek.chop;
                                            peek = toks.peekNextTok();
                                            break .{
                                                .end = e,
                                                .branch = true,
                                            };
                                        },
                                        .meta => {},
                                        .comment => {},
                                        .def => return error.UnexpectedOpenTag,
                                        .pop => unreachable,
                                    }
                                },
                                .token, .quote => {},
                                .eof => unreachable,
                            }
                            toks.current = peek.chop;
                            peek = toks.peekNextTok();
                        } else .{
                            .end = end_nodedef,
                            .branch = false,
                        };
                        if (nodeh.branch) {
                            const branch = try parseTopNode(alloc, input[nodeh.end + 1 .. end_nodedef]);
                            try nodes.append(Tree.Inner{
                                .raw = input[tag_start..nodeh.end],
                                .kind = .tag,
                                .attr_start = attr_start - tag_start,
                                .branch = branch,
                            });
                        } else {
                            try nodes.append(Tree.Inner{
                                .raw = input[tag_start..nodeh.end],
                                .kind = .tag,
                                .attr_start = attr_start - tag_start,
                            });
                        }
                        // updated the tokeniser state to after the node we just parsed
                        toks.current = end_nodedef + 1;
                        peek = toks.peekNextTok();
                    },
                    .push, .pop => {
                        std.log.debug("{}", .{peek});
                        return error.UnexpectedUnescapedSymbolAtTopNode;
                    },
                    .meta => {
                        // munch the symbol
                        toks.current = peek.chop;
                        const meta = toks.peekNextNTok(3);
                        if (meta[2].tok.kind != .symbol and meta[2].tok.raw[0] != @intFromEnum(Symbol.meta)) {
                            return error.ExpectedEndOfMetaDeclaration;
                        }
                        const start = meta[0].trim;
                        const end = meta[1].chop;

                        try nodes.append(Tree.Inner{
                            .raw = input[start..end],
                            .kind = .meta,
                        });

                        toks.current = meta[2].chop;
                        peek = toks.peekNextTok();
                    },
                    .comment => {
                        // munch the symbol
                        toks.current = peek.chop;
                        peek = toks.peekNextTok();

                        const start = peek.trim;
                        const end = while (peek.tok.kind != .eof) {
                            if (peek.tok.kind == .symbol and peek.tok.raw[0] == @intFromEnum(Symbol.comment)) {
                                break peek.trim;
                            }
                            toks.current = peek.chop;
                            peek = toks.peekNextTok();
                        } else return error.UnterminatedComment;

                        try nodes.append(Tree.Inner{
                            .raw = input[start..end],
                            .kind = .comment,
                        });

                        toks.current = peek.chop;
                        peek = toks.peekNextTok();
                    },
                }
            },
            .eof => unreachable,
        }
    }

    return try nodes.toOwnedSlice();
}
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const snapshot_tests: []const struct {
        tag: []const u8,
        input: []const u8,
        expected: []const u8,
    } = &.{
        .{
            .tag = "text node",
            .input =
            \\this is a string of tokens
            ,
            .expected =
            \\this is a string of tokens
            ,
        },
        .{
            .tag = "meta and comments",
            .input =
            \\!DOCTYPE HTML!
            \\#a comment#
            ,
            .expected =
            \\<!DOCTYPE HTML><!--a comment-->
            ,
        },
        .{
            .tag = "simple tag",
            .input =
            \\<a|>
            ,
            .expected =
            \\<a></a>
            ,
        },
        .{
            .tag = "nested tag",
            .input =
            \\<a href="/"|
            \\    <b|
            \\       Hello
            \\    >
            \\>
            ,
            .expected =
            \\<a href="/"><b>Hello</b></a>
            ,
        },
        .{
            .tag = "advanced",
            .input =
            \\<a foo| Hello >
            \\<b bar>
            \\<c bar>
            ,
            .expected =
            \\<a foo>Hello</a><b bar><c bar>
            ,
        },
    };

    @setEvalBranchQuota(10000);
    inline for (snapshot_tests) |t| {
        defer _ = arena.reset(.retain_capacity);
        const markup = comptime parseTopNodeComptime(t.input) catch unreachable;
        inline for (markup) |n| @compileLog(n);
        // std.log.info("(test)[{s}]: {} top nodes", .{ t.input, comptime countTopNodes(t.input) catch  });
    }
}

pub fn main1() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    defer arena.deinit();

    const snapshot_tests: []const struct {
        tag: []const u8,
        input: []const u8,
        expected: []const u8,
    } = &.{
        .{
            .tag = "text node",
            .input =
            \\this is a string of tokens
            ,
            .expected =
            \\this is a string of tokens
            ,
        },
        .{
            .tag = "meta and comments",
            .input =
            \\!DOCTYPE HTML!
            \\#a comment#
            ,
            .expected =
            \\<!DOCTYPE HTML><!--a comment-->
            ,
        },
        .{
            .tag = "simple tag",
            .input =
            \\<a|>
            ,
            .expected =
            \\<a></a>
            ,
        },
        .{
            .tag = "nested tag",
            .input =
            \\<a href="/"|
            \\    <b|
            \\       Hello
            \\    >
            \\>
            ,
            .expected =
            \\<a href="/"><b>Hello</b></a>
            ,
        },
        .{
            .tag = "advanced",
            .input =
            \\<a foo| Hello >
            \\<b bar>
            ,
            .expected =
            \\<a foo>Hello</a><b bar>
            ,
        },
    };

    inline for (snapshot_tests) |t| {
        defer _ = arena.reset(.retain_capacity);
        std.log.info("(test)[{s}]", .{t.tag});
        const markup = try parseInputAlloc(alloc, t.input);
        // var cur_parent: ?NodeIx = null;
        var buf = try std.ArrayListUnmanaged(u8).initCapacity(alloc, t.input.len * 4);
        const writer = buf.writer(alloc);
        try render(writer, markup.root);
        const output = try buf.toOwnedSlice(alloc);
        if (std.mem.eql(u8, t.expected, output)) {
            std.log.info("(test)[{s}]: PASS", .{t.tag});
        } else {
            std.log.info(
                "(test)[{s}]: FAIL\ninput:\n{s}\noutput:\n{s}\nexpected\n{s}",
                .{ t.tag, t.input, output, t.expected },
            );
            std.posix.exit(1);
        }
    }
}

fn render(writer: anytype, input: []const Tree.Inner) !void {
    for (input) |n| {
        std.log.debug("{s}: \"{s}\"", .{ @tagName(n.kind), n.raw });
        switch (n.kind) {
            .meta => try writer.print("<!{s}>", .{n.raw}),
            .comment => try writer.print("<!--{s}-->", .{n.raw}),
            .text => try writer.print("{s}", .{n.raw}),
            .tag => {
                try writer.print("<{s}>", .{n.raw});
                if (n.branch) |b| {
                    try render(writer, b);
                }
                try writer.print("</{s}>", .{n.raw[0 .. n.attr_start orelse n.raw.len]});
            },
        }
    }
}
