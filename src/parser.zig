const std = @import("std");
const Tokeniser = @import("tokeniser.zig").Tokeniser;

pub const NotRecTree = struct {
    nodes: []const Inner,
    interps: []const Interp,

    const Interp = struct {
        raw: []const u8,
        kind: enum(u8) {
            include,
            arg_simple,
            arg_attr,
            arg_if,
            arg_exists,
            arg_for,
            arg_switch,
        },
    };

    const View = struct {
        start: u32,
        end: u32,
    };
    pub const Inner = struct {
        child_nodes: ?View = null,
        interps: ?View = null,

        raw: []const u8,
        kind: enum(u8) {
            text,
            meta,
            comment,
            tag,
            interp,
        } = .text,
        attr_start: ?u32 = null,

        pub fn format(value: Inner, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.print("\n", .{});
            if (value.branch) |_| {
                try writer.print("<", .{});
            }
            try writer.print("node[{s}] \"{s}\"", .{ @tagName(value.kind), value.raw });
            if (value.branch) |ns| {
                for (ns) |n| try writer.print(" {{    {}", .{n});
                try writer.print("\n}} node[{s}]>", .{@tagName(value.kind)});
            }
            try writer.print("", .{});
        }
    };
};

pub const Tree = struct {
    root: []const Inner,
    interps: []const Interp,

    const Interp = struct {
        raw: []const u8,
        kind: enum(u8) {
            include,
            arg_simple,
            arg_attr,
            arg_if,
            arg_exists,
            arg_for,
            arg_switch,
        },
    };

    pub const Inner = struct {
        branch: ?[]const Inner = null,
        captures: ?[]const u32 = null,

        raw: []const u8,
        kind: enum(u8) {
            text,
            meta,
            comment,
            tag,
            interp,
        } = .text,
        attr_start: ?u32 = null,

        pub fn format(value: Inner, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.print("\n", .{});
            if (value.branch) |_| {
                try writer.print("<", .{});
            }
            try writer.print("node[{s}] \"{s}\"", .{ @tagName(value.kind), value.raw });
            if (value.branch) |ns| {
                for (ns) |n| try writer.print(" {{    {}", .{n});
                try writer.print("\n}} node[{s}]>", .{@tagName(value.kind)});
            }
            try writer.print("", .{});
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
    interp = '@',
};

const TreeSpecs = struct {
    num_nodes: usize,
    num_interps: usize,
};

pub fn countTopNodes(input: []const u8) !usize {
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
                    .interp => {
                        toks.current = peek.chop;
                        peek = toks.peekNextTok();
                        if (peek.tok.kind != .token and peek.tok.kind != .quote) {
                            return error.ExpectedInterpName;
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
                                        .interp => {
                                            if (!push_valid) {
                                                @compileLog(push_valid, input, std.fmt.comptimePrint("{}", .{peek}));
                                                @compileError("TODO: splatting a type into tag attributes");
                                            }
                                        },
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
                    .pop, .push => return error.UnexpectedUnescapedSymbolAtTopNode,
                }
            },
            .eof => unreachable,
        }
        toks.current = peek.chop;
        peek = toks.peekNextTok();
    }

    return ret;
}

pub fn measureTree(input: []const u8) !TreeSpecs {
    var ret: TreeSpecs = .{
        .num_nodes = 0,
        .num_interps = 0,
    };
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
                ret.num_nodes += 1;
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
                        ret.num_nodes += 1;
                    },
                    .interp => {
                        toks.current = peek.chop;
                        peek = toks.peekNextTok();
                        if (peek.tok.kind != .token and peek.tok.kind != .quote) {
                            return error.ExpectedInterpName;
                        }
                        toks.current = peek.chop;
                        peek = toks.peekNextTok();

                        ret.num_interps += 1;
                        ret.num_nodes += 1;
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
                                        .interp => {
                                            if (!push_valid) {
                                                @compileLog(push_valid, input, std.fmt.comptimePrint("{}", .{peek}));
                                                @compileError("TODO: splatting a type into tag attributes");
                                            }
                                        },
                                    }
                                },
                                .token, .quote => {},
                                .eof => unreachable,
                            }
                            toks.current = peek.chop;
                            peek = toks.peekNextTok();
                            if (depth == 0) {
                                ret.num_nodes += 1;
                                break;
                            }
                        }
                    },
                    .pop, .push => return error.UnexpectedUnescapedSymbolAtTopNode,
                }
            },
            .eof => unreachable,
        }
        toks.current = peek.chop;
        peek = toks.peekNextTok();
    }

    return ret;
}

fn countInterp(roots: []const Tree.Inner) usize {
    var ix = 0;
    for (roots) |node| {
        switch (node.kind) {
            .interp => ix += 1,
            .tag => if (node.branch) |children| {
                ix += countInterp(children);
            },
            else => {},
        }
    }
    return ix;
}

fn captureInterps(roots: []const Tree.Inner, out: [][]const u8, ix: *usize) void {
    for (roots) |node| {
        switch (node.kind) {
            .interp => {
                out[ix.*] = node.raw;
                ix.* += 1;
            },
            .tag => if (node.branch) |children| captureInterps(children, out, ix),
            else => {},
        }
    }
}

pub fn parseTree(input: []const u8) !Tree {
    const nodes = try parseTopNodeComptime(input);
    return .{
        .root = nodes,
        .interps = &.{},
    };
}

pub fn parseTopNodeComptime(input: []const u8) ![]const Tree.Inner {
    @setEvalBranchQuota(10000);
    const dims = try measureTree(input);

    var nodes: [dims.num_nodes]Tree.Inner = undefined;
    var node_ix: usize = 0;

    // var interps: [dims.num_nodes]Tree.Inner = undefined;
    // var interp_ix: usize = 0;

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
                                        .interp => {},
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
                                        else => unreachable,
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
                    .interp => {
                        toks.current = peek.chop;
                        peek = toks.peekNextTok();

                        if (peek.tok.kind != .token and peek.tok.kind != .quote) {
                            return error.ExpectedInterpSymbol;
                        }

                        nodes[node_ix] = Tree.Inner{
                            .kind = .interp,
                            .raw = peek.tok.raw,
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

    // From https://github.com/ziglang/zig/issues/19460#issuecomment-2025813676 (28Mar 2024)
    // Runtime values cannot alias comptime var memory, so we copy our results to a const variable.
    // A comptime const is essentially a static variable from the perspective of the program, so
    // there are no issues with stack lifetimes.
    const ns = nodes[0..nodes.len].*;
    return &ns;
}
