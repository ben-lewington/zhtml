const std = @import("std");

pub const QuotedTokeniser = Tokeniser(.{});

pub fn Tokeniser(comptime config: struct {
    spacing: []const u8 = " \t\n\r",
    quotes: [2]u8 = "\"\"".*,
    Symbols: type = enum(u8) {},
}) type {
    const Symbols = config.Symbols;
    const enum_ti = @typeInfo(Symbols).@"enum";
    if (enum_ti.tag_type != u8) @compileError("symbol enum must have a u8 representation");
    const sym_arr = b: {
        var k: [enum_ti.fields.len][]const u8 = undefined;
        var v: [enum_ti.fields.len]u8 = undefined;
        for (enum_ti.fields, 0..) |f, i| {
            k[i] = f.name;
            v[i] = @intCast(f.value);
        }
        break :b .{
            .keys = k,
            .values = v,
        };
    };

    return struct {
        pub const Symbol = Symbols;
        input: []const u8,
        current: u32 = 0,

        pub const Token = struct {
            raw: []const u8,
            kind: enum {
                quote,
                token,
                symbol,
                eof,
            },

            pub const Info = struct {
                tok: Token,
                trim: u32,
                chop: u32,
            };
        };

        inline fn isOneOf(ch: u8, comptime chs: []const u8) bool {
            var r = false;
            inline for (chs) |sp| {
                if (ch == sp) r = true;
            }
            return r;
        }

        pub fn next(self: *@This()) ?Token {
            const peek = self.peekNextTok();
            if (peek.tok.kind == .eof) return null;
            self.current = peek.chop;
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
                    .trim = @intCast(eof),
                    .chop = @intCast(eof),
                };
            }
            std.debug.assert(self.current < eof);

            var ix: u32 = self.current;
            var trim: u32 = ix;

            if (isOneOf(self.input[self.current], config.spacing)) {
                trim = while (ix < eof) : (ix += 1) {
                    if (!isOneOf(self.input[ix], config.spacing)) break ix;
                } else return .{
                    .tok = .{
                        .raw = "",
                        .kind = .eof,
                    },
                    .trim = trim,
                    .chop = @intCast(eof),
                };
            }

            var chop: u32 = trim;
            if (self.input[trim] == config.quotes[0]) {
                ix += 1;
                chop = while (ix < eof) : (ix += 1) {
                    if (self.input[ix] == config.quotes[1]) break ix;
                } else return .{
                    .tok = .{
                        .raw = self.input[trim..],
                        .kind = .quote,
                    },
                    .trim = trim,
                    .chop = @intCast(eof),
                };
                ix += 1;

                return .{ .tok = .{
                    .raw = self.input[trim .. chop + 1],
                    .kind = .quote,
                }, .trim = trim, .chop = chop + 1 };
            } else if (isOneOf(self.input[trim], &sym_arr.values)) {
                ix += 1;

                return .{ .tok = .{
                    .raw = self.input[trim .. trim + 1],
                    .kind = .symbol,
                }, .trim = trim, .chop = trim + 1 };
            }

            chop = while (ix < eof) : (ix += 1) {
                if (isOneOf(
                    self.input[ix],
                    config.spacing ++ &sym_arr.values,
                )) break ix;
            } else return .{ .tok = .{
                .raw = self.input[trim..],
                .kind = .token,
            }, .trim = trim, .chop = @intCast(eof) };

            return .{ .tok = .{
                .raw = self.input[trim..chop],
                .kind = .token,
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
                    .trim = @intCast(self.input.len),
                    .chop = @intCast(self.input.len),
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

        pub fn getLocation(self: *const @This(), offset: u32) struct {
            row: u32,
            col: u32,

            pub fn format(value: @This(), w: *std.Io.Writer) !void {
                try w.print("{d}:{d}:", .{ value.row + 1, value.col + 1 });
            }
        } {
            if (offset >= self.input.len) return .{ .row = 0, .col = 0 };
            var row: u32 = 0;
            var col: u32 = 0;
            var idx: u32 = 0;
            while (idx < offset) : (idx += 1) {
                switch (self.input[idx]) {
                    '\r' => {
                        if (idx + 1 <= self.current) {
                            if (self.input[idx + 1] == '\n') idx += 1;
                        }
                        row += 1;
                        col = 0;
                    },
                    '\n' => {
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

// Tests
const testing = std.testing;

const TestSymbols = enum(u8) {
    paren_open = '(',
    paren_close = ')',
    bracket_open = '[',
    bracket_close = ']',
    brace_open = '{',
    brace_close = '}',
    comma = ',',
    semicolon = ';',
    equals = '=',
};

const TestTokeniser = Tokeniser(.{ .Symbols = TestSymbols });

const SyntaxSymbol = enum(u8) {
    def = '<',
    push = '|',
    pop = '>',
    meta = '!',
    comment = '#',
    interp = '@',
};

const SyntaxTokeniser = Tokeniser(.{ .Symbols = SyntaxSymbol });

test "basic token parsing" {
    var tok = TestTokeniser{
        .input = "hello world",
    };
    const t1 = tok.next().?;
    try testing.expectEqualSlices(u8, "hello", t1.raw);
    try testing.expect(t1.kind == .token);

    const t2 = tok.next().?;
    try testing.expectEqualSlices(u8, "world", t2.raw);
    try testing.expect(t2.kind == .token);

    try testing.expectEqual(@as(?TestTokeniser.Token, null), tok.next());
}

test "symbol detection" {
    var tok = TestTokeniser{
        .input = "( ) [ ] { } , ; =",
    };
    const symbols = [_][]const u8{ "(", ")", "[", "]", "{", "}", ",", ";", "=" };
    for (symbols) |expected| {
        const t = tok.next().?;
        try testing.expectEqualSlices(u8, expected, t.raw);
        try testing.expect(t.kind == .symbol);
    }
    try testing.expectEqual(@as(?TestTokeniser.Token, null), tok.next());
}

test "quoted strings" {
    var tok = TestTokeniser{
        .input = "\"hello world\" \"foo\"",
    };
    const t1 = tok.next().?;
    try testing.expectEqualSlices(u8, "\"hello world\"", t1.raw);
    try testing.expect(t1.kind == .quote);

    const t2 = tok.next().?;
    try testing.expectEqualSlices(u8, "\"foo\"", t2.raw);
    try testing.expect(t2.kind == .quote);
}

test "unclosed quote" {
    var tok = TestTokeniser{
        .input = "\"unterminated",
    };
    const t = tok.next().?;
    try testing.expectEqualSlices(u8, "\"unterminated", t.raw);
    try testing.expect(t.kind == .quote);
}

test "whitespace handling" {
    var tok = TestTokeniser{
        .input = "  \t  hello  \n\r  world  ",
    };
    const t1 = tok.next().?;
    try testing.expectEqualSlices(u8, "hello", t1.raw);

    const t2 = tok.next().?;
    try testing.expectEqualSlices(u8, "world", t2.raw);

    try testing.expectEqual(@as(?TestTokeniser.Token, null), tok.next());
}

test "mixed tokens and symbols" {
    var tok = TestTokeniser{
        .input = "func(arg1, arg2)",
    };
    const t1 = tok.next().?;
    try testing.expectEqualSlices(u8, "func", t1.raw);
    try testing.expect(t1.kind == .token);

    const t2 = tok.next().?;
    try testing.expectEqualSlices(u8, "(", t2.raw);
    try testing.expect(t2.kind == .symbol);

    const t3 = tok.next().?;
    try testing.expectEqualSlices(u8, "arg1", t3.raw);

    const t4 = tok.next().?;
    try testing.expectEqualSlices(u8, ",", t4.raw);
    try testing.expect(t4.kind == .symbol);

    const t5 = tok.next().?;
    try testing.expectEqualSlices(u8, "arg2", t5.raw);

    const t6 = tok.next().?;
    try testing.expectEqualSlices(u8, ")", t6.raw);
}

test "peek without advancing" {
    var tok = TestTokeniser{
        .input = "one two three",
    };
    var peek1 = tok.peekNextTok();
    try testing.expectEqualSlices(u8, "one", peek1.tok.raw);

    var peek2 = tok.peekNextTok();
    try testing.expectEqualSlices(u8, "one", peek2.tok.raw);

    _ = tok.next();
    var peek3 = tok.peekNextTok();
    try testing.expectEqualSlices(u8, "two", peek3.tok.raw);
}

test "peek N tokens" {
    var tok = TestTokeniser{
        .input = "one two three four five",
    };
    const peeked = tok.peekNextNTok(3);

    try testing.expectEqualSlices(u8, "one", peeked[0].tok.raw);
    try testing.expectEqualSlices(u8, "two", peeked[1].tok.raw);
    try testing.expectEqualSlices(u8, "three", peeked[2].tok.raw);

    // Current position should be unchanged
    const t1 = tok.next().?;
    try testing.expectEqualSlices(u8, "one", t1.raw);
}

test "peek N tokens with eof" {
    var tok = TestTokeniser{
        .input = "one two",
    };
    const peeked = tok.peekNextNTok(5);

    try testing.expectEqualSlices(u8, "one", peeked[0].tok.raw);
    try testing.expectEqualSlices(u8, "two", peeked[1].tok.raw);
    try testing.expect(peeked[2].tok.kind == .eof);
}

test "empty input" {
    var tok = TestTokeniser{
        .input = "",
    };
    try testing.expectEqual(@as(?TestTokeniser.Token, null), tok.next());
}

test "only whitespace" {
    var tok = TestTokeniser{
        .input = "   \t\n\r  ",
    };
    try testing.expectEqual(@as(?TestTokeniser.Token, null), tok.next());
}

test "location tracking simple" {
    var tok = TestTokeniser{
        .input = "hello\nworld",
    };
    const loc = tok.getLocation(0);
    try testing.expectEqual(@as(u32, 0), loc.row);
    try testing.expectEqual(@as(u32, 0), loc.col);

    const loc2 = tok.getLocation(6); // After newline
    try testing.expectEqual(@as(u32, 1), loc2.row);
    try testing.expectEqual(@as(u32, 0), loc2.col);
}

test "location tracking with carriage return" {
    var tok = TestTokeniser{
        .input = "hello\r\nworld",
    };
    const loc = tok.getLocation(6); // At \r
    try testing.expectEqual(@as(u32, 1), loc.row);
    try testing.expectEqual(@as(u32, 0), loc.col);
}

test "location tracking multiple lines" {
    var tok = TestTokeniser{
        .input = "line1\nline2\nline3",
    };
    const loc1 = tok.getLocation(0);
    try testing.expectEqual(@as(u32, 0), loc1.row);

    const loc2 = tok.getLocation(6);
    try testing.expectEqual(@as(u32, 1), loc2.row);

    const loc3 = tok.getLocation(12);
    try testing.expectEqual(@as(u32, 2), loc3.row);
}

test "complex nested structure" {
    var tok = TestTokeniser{
        .input = "{ key = \"value\", nested = [ 1, 2, 3 ] }",
    };
    const expected_raw = [_][]const u8{ "{", "key", "=", "\"value\"", ",", "nested", "=", "[", "1", ",", "2", ",", "3", "]", "}" };
    for (expected_raw) |exp| {
        const t = tok.next().?;
        try testing.expectEqualSlices(u8, exp, t.raw);
    }
    try testing.expectEqual(@as(?TestTokeniser.Token, null), tok.next());
}

test "special characters in tokens" {
    var tok = TestTokeniser{
        .input = "hello-world foo_bar baz.qux",
    };
    const t1 = tok.next().?;
    try testing.expectEqualSlices(u8, "hello-world", t1.raw);

    const t2 = tok.next().?;
    try testing.expectEqualSlices(u8, "foo_bar", t2.raw);

    const t3 = tok.next().?;
    try testing.expectEqualSlices(u8, "baz.qux", t3.raw);
}

test "syntax.zig symbols" {
    var tok = SyntaxTokeniser{
        .input = "< | > ! # @",
    };
    const symbols = [_][]const u8{ "<", "|", ">", "!", "#", "@" };
    for (symbols) |expected| {
        const t = tok.next().?;
        try testing.expectEqualSlices(u8, expected, t.raw);
        try testing.expect(t.kind == .symbol);
    }
}

test "syntax.zig tag definition" {
    var tok = SyntaxTokeniser{
        .input = "<div class=\"container\">",
    };
    const t1 = tok.next().?;
    try testing.expectEqualSlices(u8, "<", t1.raw);
    try testing.expect(t1.kind == .symbol);

    const t2 = tok.next().?;
    try testing.expectEqualSlices(u8, "div", t2.raw);
    try testing.expect(t2.kind == .token);

    const t3 = tok.next().?;
    try testing.expectEqualSlices(u8, "class=\"container\"", t3.raw);
    try testing.expect(t3.kind == .token);

    const t4 = tok.next().?;
    try testing.expectEqualSlices(u8, ">", t4.raw);
    try testing.expect(t4.kind == .symbol);
}

test "syntax.zig complex template" {
    var tok = SyntaxTokeniser{
        .input = "<div | foreach item @items > <p>@item</p> </div>",
    };

    // <div
    var t = tok.next().?;
    try testing.expect(t.kind == .symbol);
    try testing.expectEqualSlices(u8, "<", t.raw);

    t = tok.next().?;
    try testing.expect(t.kind == .token);
    try testing.expectEqualSlices(u8, "div", t.raw);

    // |
    t = tok.next().?;
    try testing.expect(t.kind == .symbol);
    try testing.expectEqualSlices(u8, "|", t.raw);

    // foreach item @items
    t = tok.next().?;
    try testing.expectEqualSlices(u8, "foreach", t.raw);

    t = tok.next().?;
    try testing.expectEqualSlices(u8, "item", t.raw);

    t = tok.next().?;
    try testing.expect(t.kind == .symbol);
    try testing.expectEqualSlices(u8, "@", t.raw);

    t = tok.next().?;
    try testing.expectEqualSlices(u8, "items", t.raw);

    // >
    t = tok.next().?;
    try testing.expect(t.kind == .symbol);
    try testing.expectEqualSlices(u8, ">", t.raw);
}

test "syntax.zig all symbols tokenize correctly" {
    var tok = SyntaxTokeniser{
        .input = "<|>!#@",
    };

    const expected_symbols = [_][]const u8{ "<", "|", ">", "!", "#", "@" };
    for (expected_symbols) |exp| {
        const t = tok.next().?;
        try testing.expectEqualSlices(u8, exp, t.raw);
        try testing.expect(t.kind == .symbol);
    }
}
