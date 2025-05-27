const std = @import("std");
const log = std.log;
const assert = std.debug.assert;

pub fn Tokeniser(comptime config: struct {
    spacing: []const u8 = " \t\n\r",
    quotes: [2]u8 = "\"\"".*,
}, comptime Symbols: type) type {
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

                pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
                    try writer.print("{}@#{d}->#{d}", .{ value.tok, value.trim, value.chop });
                }
            };

            pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
                if (value.kind == .symbol) {
                    try writer.print(
                        "[sym={s}({s})]",
                        .{ @tagName(@as(Symbols, @enumFromInt(value.raw[0]))), value.raw },
                    );
                } else {
                    try writer.print(
                        "[{s}=\"{s}\"]",
                        .{ @tagName(value.kind), value.raw },
                    );
                }
            }
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
            assert(self.current < eof);

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

            pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
                try writer.print("{d}:{d}:", .{ value.row + 1, value.col + 1 });
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
