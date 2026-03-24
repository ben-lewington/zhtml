const std = @import("std");
const Parser = @import("Parser.zig");
const Symbol = Parser.Symbol;
const AttrSymbol = Parser.AttrSymbol;
const Tokeniser = Parser.Tokeniser;
const AttrsTokeniser = Parser.AttrsTokeniser;
const Measure = @This();
const log = std.log.scoped(.tml_measurer);
total_nodes: u32 = 0,
total_attributes: u32 = 0,
total_top_level_children: u32 = 0,

pub fn measureTmlAttrs(self: *Measure, input: []const u8) !void {
    var atoks = AttrsTokeniser{ .input = input };
    var apeek = atoks.peekNextTok();
    var cur_name_opt: ?[]const u8 = null;
    var cur_value_opt: ?[]const u8 = null;
    start: switch (apeek.tok.kind) {
        .token => {
            if (cur_name_opt != null) {
                self.total_attributes += 1;
                cur_value_opt = null;
            }
            cur_name_opt = apeek.tok.raw;
            atoks.current = apeek.chop;
            apeek = atoks.peekNextTok();
            continue :start apeek.tok.kind;
        },
        .symbol => switch (std.enums.fromInt(AttrSymbol, apeek.tok.raw[0]).?) {
            .eq => {
                if (cur_name_opt == null) {
                    log.err("{} \"=\" without a preceding attribute name", .{atoks.getLocation(apeek.trim)});
                    return error.Unexpected;
                }

                atoks.current = apeek.chop;
                apeek = atoks.peekNextTok();
                if (apeek.tok.kind != .quote) {
                    log.err("{} \"=\" without a proceeding quoted value", .{atoks.getLocation(apeek.trim)});
                    return error.Unexpected;
                }

                cur_value_opt = apeek.tok.raw[1 .. apeek.tok.raw.len - 1];
                atoks.current = apeek.chop;
                apeek = atoks.peekNextTok();
                continue :start apeek.tok.kind;
            },
            inline else => |s| {
                if (cur_name_opt != null) {
                    self.total_attributes += 1;
                    cur_name_opt = null;
                    cur_value_opt = null;
                }

                atoks.current = apeek.chop;
                apeek = atoks.peekNextTok();
                if (apeek.tok.kind != .token) {
                    log.err("{} expected token after symbol {}", .{atoks.getLocation(apeek.trim), s});
                    return error.Unexpected;
                }

                self.total_attributes += 1;
            },
        },
        .eof => {
            if (cur_name_opt != null) {
                self.total_attributes += 1;
            }
            break :start;
        },
        .quote => {
            log.err("{} expected attribute names to be identifiers, not quoted strings", .{atoks.getLocation(apeek.trim)});
            return error.Unexpected;
        },
    }
}

pub fn measureTml(self: *Measure, input: []const u8) !void {
    var toks = Tokeniser{ .input = input };
    var peek = toks.peekNextTok();
    start: switch (peek.tok.kind) {
        .quote, .token => {
            toks.current = peek.chop;
            peek = toks.peekNextTok();
            while (peek.tok.kind == .quote or peek.tok.kind == .token) {
                toks.current = peek.chop;
                peek = toks.peekNextTok();
            }

            self.total_nodes += 1;

            continue :start peek.tok.kind;
        },
        .symbol => switch (std.enums.fromInt(Symbol, peek.tok.raw[0]).?) {
            .def => {
                toks.current = peek.chop;
                peek = toks.peekNextTok();
                if (peek.tok.kind != .token) {
                    log.err("{} unexpected tag name after \"<\"", .{toks.getLocation(peek.trim)});
                    return error.Unexpected;
                }
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

                            toks.current = peek.chop;
                            peek = toks.peekNextTok();

                            var depth: i32 = 1;
                            const child_start = peek.trim;
                            lazy_child: switch (peek.tok.kind) {
                                .eof => {
                                    log.err("{} unexpected \"<\" in tag header", .{toks.getLocation(peek.trim)});
                                    return error.Unbalanced;
                                },
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

                            if (attr_start) |as| {
                                try self.measureTmlAttrs(toks.input[as..nodedef_end]);
                            }

                            self.total_nodes += 1;

                            const child_input = toks.input[child_start..peek.trim];
                            self.total_top_level_children += 1;
                            try self.measureTml(child_input);

                            toks.current = peek.chop;
                            peek = toks.peekNextTok();
                            continue :start peek.tok.kind;
                        },
                        .pop => {
                            const nodedef_end = peek.trim;

                            if (attr_start) |as| {
                                try self.measureTmlAttrs(toks.input[as..nodedef_end]);
                            }
                            self.total_nodes += 1;

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
                    .eof => {
                        log.err("{f} eof in node definition", .{toks.getLocation(peek.trim)});
                        return error.Unbalanced;
                    },
                }
            },
            .push => {
                log.err("{f} unexpected \"|\"", .{toks.getLocation(peek.trim)});
                return error.Unexpected;
            },
            .pop => {
                log.err("{f} unexpected \">\"", .{toks.getLocation(peek.trim)});
                return error.Unexpected;
            },
            .meta => {
                toks.current = peek.chop;
                peek = toks.peekNextTok();
                if (peek.tok.kind != .token) {
                    log.err(
                        "{f} meta declarations require an unquoted identifier in the first argument",
                        .{toks.getLocation(peek.trim)},
                    );
                    return error.Unexpected;
                }
                toks.current = peek.chop;
                peek = toks.peekNextTok();
                if (peek.tok.kind != .token) {
                    log.err(
                        "{f} meta declarations require an unquoted identifier in the second argument",
                        .{toks.getLocation(peek.trim)},
                    );
                    return error.Unexpected;
                }

                toks.current = peek.chop;
                peek = toks.peekNextTok();
                if (peek.tok.kind != .symbol) {
                    log.err(
                        "{f} expected \"!\" symbol to end meta declaration",
                        .{toks.getLocation(peek.trim)},
                    );
                    return error.Unexpected;
                }
                if (std.enums.fromInt(Symbol, peek.tok.raw[0]) != .meta) {
                    log.err(
                        "{f} expected \"!\" symbol to end meta declaration",
                        .{toks.getLocation(peek.trim)},
                    );
                    return error.Unexpected;
                }

                toks.current = peek.chop;
                peek = toks.peekNextTok();

                self.total_nodes += 1;
                continue :start peek.tok.kind;
            },
            .comment => {
                toks.current = peek.chop;
                peek = toks.peekNextTok();
                while (true) {
                    if (peek.tok.kind == .symbol) {
                        if (peek.tok.raw[0] == @intFromEnum(Symbol.comment)) break;
                    }
                    toks.current = peek.chop;
                    peek = toks.peekNextTok();
                }
                toks.current = peek.chop;
                peek = toks.peekNextTok();

                self.total_nodes += 1;
                continue :start peek.tok.kind;
            },
        },
        .eof => break :start,
    }
}
