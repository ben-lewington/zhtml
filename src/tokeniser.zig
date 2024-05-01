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
                        "tok[{s}]: \"{s}\" @ #{d}->#{d}",
                        .{
                            @tagName(value.tok.kind),
                            value.tok.raw,
                            value.trim,
                            value.chop,
                        },
                    );
                }
            };
        };

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
        std.log.debug("tok[{s}]: \"{s}\", remaining \"{s}\"", .{
            @tagName(tok.tok.kind),
            tok.tok.raw,
            input[tok.chop..],
        });
        toks.current = tok.chop;
        tok = toks.peekNextTok();
    }
}
