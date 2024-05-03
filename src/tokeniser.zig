const std = @import("std");
const log = std.log;
const assert = std.debug.assert;

const u = usize;
const str = []const u8;

fn strn(comptime len: comptime_int) type {
    return [len]u8;
}

pub fn Tokeniser(comptime config: struct {
    spacing: str,
    quotes: strn(2),
    symbols: str,
}) type {
    return struct {
        input: str,
        current: u,

        pub fn init(input: str) @This() {
            return .{
                .input = input,
                .current = 0,
            };
        }

        pub const Token = struct {
            raw: str,
            kind: enum {
                qu_balanced,
                qu_unbalanced,
                literal,
                symbol,
                eof,
            },

            const TSelf = @This();

            pub const Info = struct {
                tok: TSelf,
                trim: u,
                chop: u,

                pub fn format(
                    value: @This(),
                    comptime _: []const u8,
                    _: std.fmt.FormatOptions,
                    writer: anytype,
                ) !void {
                    try writer.print(
                        "{}@#{d}->#{d}",
                        .{
                            value.tok,
                            value.trim,
                            value.chop,
                        },
                    );
                }
            };
            pub fn format(
                value: @This(),
                comptime _: []const u8,
                _: std.fmt.FormatOptions,
                writer: anytype,
            ) !void {
                try writer.print(
                    "tok[{s}]{{ \"{s}\" }}",
                    .{
                        @tagName(value.kind),
                        value.raw,
                    },
                );
            }
        };

        pub fn Location(comptime offset: [2]comptime_int) type {
            return struct {
                row: usize,
                col: usize,

                pub fn format(
                    value: @This(),
                    comptime _: []const u8,
                    _: std.fmt.FormatOptions,
                    writer: anytype,
                ) !void {
                    try writer.print("{d}:{d}:", .{ value.row + offset[0], value.col + offset[1] });
                }
            };
        }

        inline fn isOneOf(ch: u8, comptime chs: str) bool {
            const ret = for (chs) |sp| {
                if (ch == sp) break true;
            } else false;
            return ret;
        }

        pub fn next(self: *@This()) ?Token {
            const peek = self.peekNextTok();
            if (peek.tok.kind == .eof) return null;
            return peek.tok;
        }

        pub fn peekNextTok(self: *const @This()) Token.Info {
            const eof = self.input.len;
            if (self.current == eof) {
                return .{
                    .tok = .{
                        .raw = "",
                        .kind = .eof,
                    },
                    .trim = eof,
                    .chop = eof,
                };
            }
            assert(self.current < eof);

            var ix: u = self.current;
            var trim: u = ix;

            if (isOneOf(self.input[self.current], config.spacing)) {
                trim = while (ix < eof) : (ix += 1) {
                    if (!isOneOf(self.input[ix], config.spacing)) break ix;
                } else return .{
                    .tok = .{
                        .raw = "",
                        .kind = .eof,
                    },
                    .trim = trim,
                    .chop = eof,
                };
            }

            var chop: u = trim;
            if (self.input[trim] == config.quotes[0]) {
                ix += 1;
                chop = while (ix < eof) : (ix += 1) {
                    if (self.input[ix] == config.quotes[1]) break ix;
                } else return .{
                    .tok = .{
                        .raw = self.input[trim..],
                        .kind = .qu_unbalanced,
                    },
                    .trim = trim,
                    .chop = eof,
                };
                ix += 1;

                return .{ .tok = .{
                    .raw = self.input[trim .. chop + 1],
                    .kind = .qu_balanced,
                }, .trim = trim, .chop = chop + 1 };
            } else if (isOneOf(self.input[trim], config.symbols)) {
                ix += 1;

                return .{ .tok = .{
                    .raw = self.input[trim .. trim + 1],
                    .kind = .symbol,
                }, .trim = trim, .chop = trim + 1 };
            }

            chop = while (ix < eof) : (ix += 1) {
                if (isOneOf(
                    self.input[ix],
                    config.spacing ++ config.symbols,
                )) break ix;
            } else return .{ .tok = .{
                .raw = self.input[trim..],
                .kind = .literal,
            }, .trim = trim, .chop = eof };

            return .{ .tok = .{
                .raw = self.input[trim..chop],
                .kind = .literal,
            }, .trim = trim, .chop = chop };
        }

        // TODO(BL): This self pointer should be const, update internal API so that self.current
        // can be replaced with an ersatz value
        pub fn peekNextNTok(self: *@This(), comptime n: comptime_int) [n]Token.Info {
            const pop = self.current;
            // we'll monkey around with the tokeniser state in this method, then undo all our changes.
            defer self.current = pop;

            var ret: [n]Token.Info = undefined;

            inline for (0..n) |i| {
                ret[i] = .{
                    .tok = .{ .kind = .eof, .raw = "" },
                    .trim = self.input.len,
                    .chop = self.input.len,
                };
            }

            for (0..n) |i| {
                const t = self.peekNextTok();
                if (t.tok.kind == .eof) break;
                ret[i] = t;
                self.current = t.chop;
            }

            return ret;
        }

        pub fn getLocation(self: *const @This(), offset: usize) Location(.{ 1, 1 }) {
            if (offset >= self.input.len) return .{ .row = 0, .col = 0 };
            var row: usize = 0;
            var col: usize = 0;
            var idx: usize = 0;
            while (idx < offset) : (idx += 1) {
                switch (self.input[idx]) {
                    '\n', '\r' => |ch| {
                        if (ch == '\r') {
                            if (idx + 1 <= self.current) {
                                if (self.input[idx + 1] == '\n') idx += 1;
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
    };
}
test "tokeniser" {
    const input = "r<bca \"foo bar baz\"";
    const spacing: str = " \r\n\t";
    const quotes: strn(2) = "\"\"".*;

    var toks = Tokeniser(.{
        .spacing = spacing,
        .quotes = quotes,
        .symbols = "",
    }).init(input);
    var tok = toks.peekNextTok();
    while (tok.tok.kind != .eof) {
        toks.current = tok.chop;
        tok = toks.peekNextTok();
    }
}
